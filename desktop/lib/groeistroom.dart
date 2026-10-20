// Spelen terwijl het nog binnenkomt (Saber, 20-10-2026: "dat het liedje toch al begint te spelen terwijl
// hij nog download … ik wil wel dat het vlekkeloos gaat").
//
// **Wat er gemeten is vóór en tijdens het schrijven** (libmpv-2.dll van de app in een eigen proefopstelling,
// met dezelfde opties als player.dart; zie de kladmap `stroomproef`):
//
//   * `appending://` — mpv's eigen weg voor een bestand dat groeit — gaf het op na een hapering van ~5 s:
//     "flac: invalid residual" en einde, op 15,8 s. Een Soulseek-peer valt geregeld langer stil.
//   * Een HTTP-adres dat de VOLLE grootte belooft (Soulseek kent die vooraf) en bij het einde van wat er
//     al staat wacht in plaats van stopt: haperingen van 15 en 28 s, mpv zette zichzelf op
//     "paused-for-cache" en speelde daarna gewoon door, tot het einde.
//   * Op Windows mag een tweede lezer meelezen met de schrijver van soulseek.dart (zonder flush), maar een
//     bestand dat iemand open heeft, laat zich NIET verplaatsen (errno 32). Daarom leest deze server per
//     stuk: openen, lezen, dicht — en zodra het bestand compleet is, neemt hij het in het geheugen
//     ([Groei.binnen]) zodat opbergen en tags schrijven er vrij over kunnen beschikken.
//   * Breekt de verbinding, dan verbindt ffmpeg opnieuw met HETZELFDE adres op dezelfde byte — ook na een
//     doorverwijzing. Zie [Groeistroom._verzoek] voor wat er dan moet gebeuren, en waarom niet "410".
//
// Uit het downloadlogboek van dezelfde ochtend: Soulseek-overdrachten breken geregeld af ("Overdracht
// afgebroken na 1 s / 2 s / 4 s / 6 s / 18 s"), en een goede peer levert het hele nummer in 7 à 13 s. Een
// andere uploader midden in het nummer is dus geen randgeval: zie [Groei.speelbaarVanaf].
//
// Alleen dart:io: zo is hij buiten Flutter met de echte libmpv te beproeven.
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'flac_frames.dart';

/// Hoeveel er per keer gelezen en verstuurd wordt.
const kGroeiStuk = 256 * 1024;

/// Groter dan dit gaat niet in het geheugen; dan breekt de stroom bij het opbergen even af en gaat de
/// speler verder in het opgeborgen bestand (zie [Groei.geland]). Een 24/192 van zeven minuten.
const kGroeiVastPlafond = 400 * 1024 * 1024;

/// Minstens zoveel audio binnen voordat het mag klinken.
const kGroeiMinBuffer = 256 * 1024;

/// Zo lang moet een peer leveren voordat we op hem rekenen — en voordat het klinkt.
///
/// **Drie seconden en niet anderhalf**: van de afgebroken overdrachten in het logboek van 20-10-2026 hield
/// de helft het binnen zes seconden voor gezien (1, 2, 4 en 6 s). Wie net begint te spelen en dan al van
/// uploader moet wisselen, hoort een gat; anderhalve seconde langer meten voorkomt er een deel van.
const kGroeiMinGemeten = Duration(seconds: 3);

/// Zo kort mag het meten bij een uploader die ruim vlot is en al ruim vooruit staat (zie [magBeginnen]).
const kGroeiSnelGemeten = Duration(milliseconds: 750);

/// Mag het al klinken — vanaf [vanaf] in het nummer?
///
/// **De rekensom, over de audio** (zonder de kop van [kop] bytes: een hoes vooraan is in één keer
/// "verbruikt"). Klinken verbruikt `verbruik` bytes per seconde (audio gedeeld door looptijd), de peer
/// levert `snelheid`. Vanaf [vanaf] moet er nog `rest` audio komen; is de peer trager dan het verbruik,
/// dan moet er bij het begin al zoveel vóór de speelplek staan dat het verschil tot het einde goedkomt:
/// `voorsprong + snelheid·t ≥ verbruik·t`, dus `voorsprong ≥ rest·(1 − snelheid/verbruik)`. Met 30 %
/// marge en een reserve van 8 s audio; een ruim snellere peer (≥ 1,25×) alleen 2 s reserve.
///
/// **Waarom 30 % en niet 15 %.** Gemeten op 20-10-2026 met de libmpv van de app en een peer op 85 % van
/// het verbruik: met 15 % stond de muziek op 204 van 215 s toch nog twee seconden stil. Een FLAC heeft
/// geen vaste bitsnelheid; drukke stukken (het slot, hier) kosten meer dan het gemiddelde.
bool magBeginnen({
  required int binnen,
  required int totaal,
  required Duration duur,
  required double snelheid,
  required Duration gemeten,
  int kop = 0,
  Duration vanaf = Duration.zero,
}) {
  if (totaal > 0 && binnen >= totaal) return true;
  if (totaal <= 0 || duur <= Duration.zero) return false;
  final audio = totaal - kop;
  if (audio <= 0 || gemeten < kGroeiSnelGemeten || snelheid <= 0) return false;
  final deel = (vanaf.inMilliseconds / duur.inMilliseconds).clamp(0.0, 1.0);
  final speelplek = kop + audio * deel;
  final voorsprong = binnen - speelplek;
  if (voorsprong < kGroeiMinBuffer) return false;
  final verbruik = audio / (duur.inMilliseconds / 1000);
  // **Ruim vlot en ruim vooruit: niet de volle drie seconden meten.** Twee keer het verbruik en 15 s
  // muziek klaar: haakt zo'n uploader alsnog af, dan overbrugt die voorsprong de wissel naar de volgende
  // (met `?vanaf=` een tel, gemeten op 20-10-2026). Op de pc dezelfde middag: 3 MB/s, en toch 3 s wachten.
  final ruim = snelheid >= verbruik * 2 && voorsprong >= verbruik * 15;
  if (gemeten < kGroeiMinGemeten && !ruim) return false;
  final rest = audio * (1 - deel);
  final achterstand = snelheid >= verbruik ? 0.0 : rest * (1 - snelheid / verbruik) * 1.3;
  final reserve = verbruik * (snelheid >= verbruik * 1.25 ? 2 : 8);
  return voorsprong >= achterstand + reserve;
}

/// De snelheid waarop we rekenen: de TRAAGSTE van het gemiddelde sinds het begin en dat van de laatste
/// drie seconden. Een peer die snel begint en dan inzakt, telt zo met zijn inzakking.
double voorzichtigeSnelheid(List<({Duration t, int bytes})> metingen) {
  if (metingen.length < 2) return 0;
  double tempo(({Duration t, int bytes}) a, ({Duration t, int bytes}) b) {
    final s = (b.t - a.t).inMilliseconds / 1000;
    return s <= 0 ? 0 : (b.bytes - a.bytes) / s;
  }

  final laatste = metingen.last;
  final heel = tempo(metingen.first, laatste);
  final grens = laatste.t - const Duration(seconds: 3);
  final vanaf = metingen.lastWhere((m) => m.t <= grens, orElse: () => metingen.first);
  return min(heel, tempo(vanaf, laatste));
}

/// De server. Eén per app, alleen op 127.0.0.1.
class Groeistroom {
  Groeistroom({
    this.wachtOpPoging = const Duration(seconds: 40),
    this.stilGrens = const Duration(seconds: 90),
    this.peil = const Duration(milliseconds: 200),
    this.vastPlafond = kGroeiVastPlafond,
  });

  static final gedeeld = Groeistroom();

  /// Zo lang wacht een nieuw verzoek op een bruikbare poging (de volgende peer). Onder de 60 s van mpv's
  /// `network-timeout`, zodat mpv een eerlijk "niet beschikbaar" krijgt en geen afgebroken verbinding.
  final Duration wachtOpPoging;

  /// Zo lang mag een poging stilvallen voordat dit antwoord het opgeeft. Soulseek zelf geeft het na 30 s
  /// op (`_pump`), dus normaal komt [Groei.afgebroken] eerder.
  final Duration stilGrens;

  /// Hoe vaak er gekeken wordt of er iets bij is gekomen.
  final Duration peil;

  /// Zie [kGroeiVastPlafond]. Instelbaar voor de toetsen.
  final int vastPlafond;

  /// Logregels.
  void Function(String regel)? spoor;

  /// Speelt de speler dit adres nog? Zolang wel, blijft wat in het geheugen staat staan: mpv kan nog
  /// terugspringen of na een hik opnieuw openen, en moet dan dezelfde bytes krijgen.
  bool Function(String adres)? inGebruik;

  Future<HttpServer>? _opstart;
  final _alle = <String, Groei>{};
  var _teller = 0;
  Timer? _opruimer;

  /// Is [adres] een adres van deze server (van welke app-start dan ook)?
  static bool isAdres(String adres) =>
      adres.startsWith('http://127.0.0.1:') && adres.contains('/g/');

  /// De [Groei] achter [adres], of null (een ander adres, of al opgeruimd).
  Groei? van(String adres) {
    if (!isAdres(adres)) return null;
    final delen = Uri.tryParse(adres)?.pathSegments ?? const [];
    return delen.length == 2 ? _alle[delen[1].split('.').first] : null;
  }

  /// Een nieuw nummer dat gaat binnenkomen. [naam] alleen voor het logboek.
  Future<Groei> nieuw(String naam) async {
    final s = await (_opstart ??= _begin());
    final id = '${++_teller}${Random().nextInt(1 << 30).toRadixString(36)}';
    final g = Groei._(this, id, 'http://127.0.0.1:${s.port}/g/$id.flac', naam);
    _alle[id] = g;
    _opruimer ??= Timer.periodic(const Duration(seconds: 30), (_) => _ruimOp());
    return g;
  }

  Future<HttpServer> _begin() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    s.listen((r) => unawaited(_verzoek(r)), onError: (_) {});
    return s;
  }

  /// Voor de toetsen: alles dicht.
  Future<void> stop() async {
    _opruimer?.cancel();
    _opruimer = null;
    for (final g in _alle.values.toList()) {
      g.sluit();
    }
    final s = _opstart;
    _opstart = null;
    if (s != null) await (await s).close(force: true);
  }

  /// Wat klaar is en niet meer gespeeld wordt, weg — ook uit het geheugen.
  void _ruimOp() {
    final nu = DateTime.now();
    for (final g in _alle.values.toList()) {
      final toestel = g._toestelSinds;
      if (g._openAntwoorden > 0 ||
          (inGebruik?.call(g.adres) ?? false) ||
          (toestel != null && nu.difference(toestel) < kToestelGeduld)) {
        g._rustSinds = null;
        continue;
      }
      final af = g._opgegeven || g._geland != null;
      final rust = g._rustSinds ??= nu;
      final grens = af ? const Duration(seconds: 60) : const Duration(minutes: 30);
      if (nu.difference(rust) >= grens) g.sluit();
    }
  }

  Future<void> _verzoek(HttpRequest req) async {
    final res = req.response;
    try {
      final delen = req.uri.pathSegments;
      if (delen.length != 2 || delen.first != 'g') return await _antwoord(res, 404);
      final g = _alle[delen[1].split('.').first];
      if (g == null) return await _antwoord(res, 404);
      final bereik = req.headers.value(HttpHeaders.rangeHeader);
      final vanaf = int.tryParse(RegExp(r'bytes=(\d+)-').firstMatch(bereik ?? '')?.group(1) ?? '') ?? 0;
      _Opening? o;
      if (vanaf == 0) {
        // OPENEN: de poging die nu bruikbaar is (zo nodig wachten op de volgende peer). Daarvan leest de
        // speler de kop, dus daar hoort elk vervolgverzoek bij.
        final p = await g._wachtOpBruikbaar(wachtOpPoging);
        if (p == null) {
          g._log('${req.method} ${bereik ?? "-"} → ${g._opgegeven ? 404 : 503}');
          return await _antwoord(res, g._opgegeven ? 404 : 503);
        }
        // `?vanaf=` (milliseconden): verder op een plek in het nummer, zonder te springen — zie
        // [Groei._openingVanaf].
        final ms = int.tryParse(req.uri.queryParameters['vanaf'] ?? '') ?? 0;
        o = g._geopend = (ms > 0 ? g._openingVanaf(p, Duration(milliseconds: ms)) : null) ?? _Opening(p);
      } else {
        // EEN VERVOLG op een plek midden in het bestand: een sprong, of ffmpeg die na een hik opnieuw
        // verbindt. **Gemeten op 20-10-2026:** ffmpeg verbindt dan opnieuw met HETZELFDE adres op dezelfde
        // byte — ook na een doorverwijzing. Dus nooit "de poging van nu" geven: is het bestand waarvan de
        // speler de kop las weg (een andere peer, of opgeborgen met nieuwe tags), dan zou hij midden in
        // een ánder bestand verder lezen. Gezien met een poging zonder geheugen: "flac: invalid frame
        // header", en vier seconden terug in het nummer.
        o = g._geopend;
        if (o == null || o.p.afgebroken) {
          // **Een einde, en geen foutcode.** Op "410" bleef ffmpeg het een minuut proberen (na 1, 3, 7, 15
          // en 31 s) en stond de muziek 25 s stil terwijl de volgende uploader al klaar was. Een leeg
          // antwoord dat zegt dat het bestand HIER ophoudt, is voor ffmpeg gewoon het einde: mpv speelt
          // zijn buffer leeg, meldt het einde, en de speler gaat verder met de volgende uploader op
          // dezelfde tijd (`_hervatGroei` in player.dart).
          g._log('${req.method} $bereik → einde (het bestand waarvan de speler de kop las is weg)');
          res.statusCode = HttpStatus.partialContent;
          res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $vanaf-$vanaf/$vanaf');
          res.contentLength = 0;
          return await res.close();
        }
      }
      g._log('${req.method} ${bereik ?? "-"} → poging ${o.p.n}${o.vanByte > 0 ? ' (vanaf byte ${o.vanByte})' : ''}');
      await g._dien(req, o);
    } catch (_) {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  static Future<void> _antwoord(HttpResponse res, int code) async {
    res.statusCode = code;
    res.contentLength = 0;
    await res.close();
  }
}

/// Eén poging: het bestand van één peer.
class _Poging {
  _Poging(this.n, this.pad, this.totaal);
  final int n;
  final String pad;
  final int totaal;

  /// De kop is gelezen en klopt (dit nummer, de juiste lengte): pas dan mag hij klinken.
  bool goed = false;

  /// Hoe lang dit bestand duurt volgens zijn eigen kop.
  Duration duur = Duration.zero;

  /// Waar de audio begint (de kop, met een eventuele hoes).
  int kop = 0;

  /// Compleet; verandert niet meer.
  bool klaar = false;

  /// Deze peer haakte af, of zijn bestand werd afgekeurd.
  bool afgebroken = false;

  /// Compleet in het geheugen: het bestand op schijf mag weg of verplaatst worden.
  Uint8List? vast;

  /// Het bestand gaat verhuizen en is niet in het geheugen genomen: niet meer van schijf lezen.
  bool verhuist = false;

  /// Heeft iemand dit al opgevraagd?
  bool gebruikt = false;

  int open = 0;

  /// Sinds de kop goedgekeurd werd: hoeveel er wanneer binnen was.
  final klok = Stopwatch();
  final metingen = <({Duration t, int bytes})>[];
}

/// Wat de speler bij het openen kreeg: een poging, en bij `?vanaf=` een eigen kop met de frames vanaf
/// [vanByte] erachter. Elk vervolgverzoek (een sprong, een herverbinding) rekent met dezelfde opening.
class _Opening {
  _Opening(this.p, {this.kop, this.vanByte = 0});
  final _Poging p;

  /// De kop zoals de speler hem krijgt (tot het eerste frame), of null: dan het bestand zoals het is.
  final Uint8List? kop;

  /// De echte byte waar de frames achter [kop] beginnen.
  final int vanByte;

  /// Hoe groot het bestand is zoals de speler het ziet.
  int get lengte => kop == null ? p.totaal : kop!.length + (p.totaal - vanByte);

  /// De echte byte achter byte [v] van de speler (voorbij de kop).
  int echt(int v) => kop == null ? v : vanByte + (v - kop!.length);

  /// Hoeveel er voor de speler beschikbaar is, als er [staat] echte bytes zijn.
  int beschikbaar(int staat) => kop == null ? staat : kop!.length + max(0, staat - vanByte);
}

/// Iemand die wacht tot het vanaf [vanaf] kan klinken.
class _Wachter {
  _Wachter(this.vanaf);
  final Duration vanaf;
  final klaar = Completer<bool>();
}

/// Eén nummer dat binnenkomt, en het adres waarop het nu al te horen is.
///
/// De haal (online.dart) meldt wat er gebeurt: [poging] zodra een peer bytes stuurt, [goedgekeurd] als
/// de kop klopt, [afgebroken] als die peer afvalt, [binnen] als het bestand compleet is, [geland] als
/// het in de bibliotheek staat. Wie wil luisteren wacht op [speelbaar] en speelt [adres].
/// Hoe lang een groei na de laatste vraag van een toestel blijft staan ([Groei.opToestel]).
///
/// Een toestel speelt niet hier: wat mpv daar nog speelt, ziet [Groeistroom.inGebruik] niet. mpv op het
/// toestel vraagt alleen opnieuw na een hik of een sprong, en dan moet hij dezelfde bytes krijgen — ook
/// als het nummer intussen geland is (dat is een ánder bestand, zie [Groei.geland]).
const kToestelGeduld = Duration(minutes: 10);

/// Een nummer dat nog binnenkomt: hier ([Groei]), of op de pc voor dit toestel (`GroeiOpPc`). De speler
/// doet met beide hetzelfde: na een breuk wachten tot het verder kan, dan op dezelfde plek verder.
abstract interface class Groeiend {
  /// Klaar om vanaf [plek] te klinken? Zie [Groei.speelbaarVanaf].
  Future<bool> speelbaarVanaf(Duration plek);

  /// Waar het nummer na het landen staat (het pad in de rij), of null.
  String? get geborgen;
}

class Groei implements Groeiend {
  Groei._(this._server, this.id, this.adres, this.naam);

  final Groeistroom _server;
  final String id;
  final String adres;
  final String naam;

  final _pogingen = <int, _Poging>{};
  var _laatste = 0;
  bool _opgegeven = false;
  bool _gesloten = false;
  String? _geland;
  DateTime? _rustSinds;
  DateTime? _toestelSinds;

  /// Een toestel vroeg naar deze groei (de LAN-server geeft hem door): blijft staan tot [kToestelGeduld]
  /// na de laatste vraag.
  void opToestel() => _toestelSinds = DateTime.now();

  /// Wat de speler bij het laatste openen (een verzoek vanaf byte 0) kreeg; daar hoort elk vervolg bij.
  _Opening? _geopend;

  final _wachters = <_Wachter>[];
  Future<bool>? _vanafBegin;
  Timer? _meter;
  _Poging? _gemeten;

  /// Klaar om vanaf het begin te klinken: de kop klopt en er staat genoeg om zonder haperen door te
  /// spelen. True zodra dat zo is, false als er geen uploader meer komt. Eén keer: wie al speelt, speelt
  /// door.
  Future<bool> get speelbaar =>
      _vanafBegin ??= speelbaarVanaf(Duration.zero).then((kan) => _klinkbaar = kan && !_gesloten);

  /// Klaar om vanaf [plek] te klinken — bij deze uploader of de volgende die goedgekeurd wordt. Voor als
  /// een uploader midden in het nummer afhaakte: het gat duurt dan tot de volgende zo ver is.
  @override
  Future<bool> speelbaarVanaf(Duration plek) {
    if (_gesloten || _opgegeven) return Future.value(false);
    final p = _huidig;
    // Het hele bestand is er al (of het staat in de bibliotheek): meteen.
    if (p != null && p.goed && !p.afgebroken && (p.klaar || p.vast != null)) return Future.value(true);
    final w = _Wachter(plek);
    _wachters.add(w);
    if (p != null && p.goed && !p.afgebroken && _gemeten != p) _meet(p);
    return w.klaar.future;
  }

  /// Iemand wil dit meteen horen (▶, of de radio die een stroomregel in de rij zet): komt het hele bestand
  /// binnen voordat de speler het opent, dan toch in het geheugen (zie [binnen]).
  ///
  /// **Waarom.** Gemeten op de pc (20-10-2026, 3.9.522, Arctic Monkeys — Do I Wanna Know?): een uploader
  /// leverde 50 MB in één tel, 145 ms vóór mpv het adres opende. Niemand luisterde nog, dus niets
  /// vastgehouden; mpv's verzoek wachtte op het opbergen, brak af en begon opnieuw in het opgeborgen
  /// bestand — een seconde later dan nodig.
  void zalKlinken() => _zalKlinken = true;
  bool _zalKlinken = false;

  /// Kan het nu vanaf het begin klinken? Hetzelfde als [speelbaar], maar zonder te wachten — voor de
  /// radio, die elke tik kijkt wat er klaar is.
  bool get kanKlinken => _klinkbaar;
  bool _klinkbaar = false;

  /// Heeft de speler dit adres al opgevraagd?
  bool get gestart => _pogingen.values.any((p) => p.gebruikt);

  /// Waar het nummer na het opbergen staat, of null.
  @override
  String? get geborgen => _geland;

  int get _openAntwoorden => _pogingen.values.fold(0, (s, p) => s + p.open);

  _Poging? get _huidig => _pogingen[_laatste];

  void _log(String s) => _server.spoor?.call('groeistroom "$naam": $s');

  /// Een peer begint te sturen. Wat er van een vorige peer liep, houdt op.
  void poging({required String pad, required int totaal}) {
    if (_gesloten) return;
    final vorig = _huidig;
    if (vorig != null && !vorig.afgebroken && !vorig.klaar) vorig.afgebroken = true;
    final p = _Poging(++_laatste, pad, totaal);
    _pogingen[p.n] = p;
    _log('poging ${p.n}: ${(totaal / 1048576).toStringAsFixed(1)} MB');
  }

  /// De kop van de huidige poging klopt. Vanaf nu wordt er gemeten voor wie wacht.
  void goedgekeurd(Duration duur, {int kopBytes = 0}) {
    final p = _huidig;
    if (p == null || p.afgebroken || _gesloten) return;
    p.goed = true;
    p.duur = duur;
    p.kop = kopBytes;
    p.klok.start();
    _log('poging ${p.n} goedgekeurd (${duur.inSeconds} s)');
    _meet(p);
  }

  /// Meet de snelheid van [p] vanaf het moment dat hij goedgekeurd is, tot hij compleet of weg is — ook
  /// als niemand wacht. Zo hoeft wie na een breuk op de VOLGENDE uploader wacht niet opnieuw drie
  /// seconden te meten: die levert misschien al een halve minuut (proef van 20-10-2026: 3,0 s gat bij
  /// een uploader die al 28 s aan het leveren was).
  void _meet(_Poging p) {
    _meter?.cancel();
    _gemeten = p;
    _meter = Timer.periodic(const Duration(milliseconds: 250), (t) {
      if (p.afgebroken || _gesloten) {
        t.cancel();
        if (_gemeten == p) _gemeten = null;
        return;
      }
      final binnen = p.klaar ? p.totaal : _grootte(p.pad);
      p.metingen.add((t: p.klok.elapsed, bytes: binnen));
      final snelheid = voorzichtigeSnelheid(p.metingen);
      for (final w in _wachters.toList()) {
        if (!magBeginnen(
            binnen: binnen,
            totaal: p.totaal,
            duur: p.duur,
            snelheid: snelheid,
            gemeten: p.klok.elapsed,
            kop: p.kop,
            vanaf: w.vanaf)) {
          continue;
        }
        _wachters.remove(w);
        _log('poging ${p.n} speelbaar vanaf ${w.vanaf.inSeconds} s, ${p.klok.elapsed.inMilliseconds} ms na de kop: '
            '${(binnen / 1048576).toStringAsFixed(1)} MB binnen, ${(snelheid / 1024).round()} kB/s, verbruik '
            '${((p.totaal - p.kop) / max(1, p.duur.inSeconds) / 1024).round()} kB/s');
        w.klaar.complete(true);
      }
      // Compleet en niemand die wacht: niets meer te meten. Wie hierna nog komt, kan meteen (zie
      // [speelbaarVanaf]).
      if (binnen >= p.totaal && _wachters.isEmpty) {
        t.cancel();
        if (_gemeten == p) _gemeten = null;
      }
    });
  }

  /// De huidige peer valt af: afgehaakt, of zijn bestand bleek iets anders.
  ///
  /// Na [geland] doet dit niets meer: het nummer staat er, en wat al klinkt hoort door te klinken.
  void afgebroken() {
    final p = _huidig;
    if (p == null || p.afgebroken || _geland != null) return;
    p.afgebroken = true;
    p.vast = null;
    _log('poging ${p.n} afgebroken${p.gebruikt ? " terwijl hij klonk" : ""}');
  }

  /// Het bestand van de huidige poging is compleet. Klonk het al, dan gaat het in het geheugen: daarna
  /// mag het opgeborgen en van tags voorzien worden terwijl mpv gewoon dezelfde bytes blijft krijgen.
  /// Tags schrijven kan de audio in een FLAC verschuiven — met de oude bytes in het geheugen maakt dat
  /// voor een lopende stroom niets uit.
  Future<void> binnen() async {
    final p = _huidig;
    if (p == null || p.afgebroken || _gesloten) return;
    p.klaar = true;
    if (!p.gebruikt && !_zalKlinken) {
      // Niemand luistert, en niemand zei dat hij het meteen wil horen (de radio die vooruit haalt): niets
      // vasthouden. Komt er tijdens het opbergen toch een verzoek, dan wacht dat op [geland].
      p.verhuist = true;
      return;
    }
    if (p.totaal > _server.vastPlafond) {
      p.verhuist = true;
      _log('poging ${p.n}: te groot om vast te houden — straks verder vanuit de bibliotheek');
      return;
    }
    try {
      final bytes = await File(p.pad).readAsBytes();
      if (bytes.length == p.totaal) {
        p.vast = bytes;
        return;
      }
      _log('poging ${p.n}: ${bytes.length} van ${p.totaal} bytes op schijf');
    } catch (e) {
      _log('poging ${p.n}: niet vast te houden ($e)');
    }
    p.verhuist = true;
  }

  /// In de bibliotheek, op [pad]. Liep er een stroom zonder geheugen, dan breekt die nu af en gaat de
  /// speler verder in het opgeborgen bestand: dat is een ánder bestand (de tags), dus nooit verder op
  /// dezelfde byte — zie [Groeistroom._verzoek].
  void geland(String pad) {
    if (_gesloten) return;
    _geland = pad;
    final p = _huidig;
    if (p != null && p.vast != null) {
      _meldKlaar(p);
      return; // de lopende stroom heeft alles al
    }
    int grootte;
    try {
      grootte = File(pad).lengthSync();
    } catch (_) {
      return;
    }
    if (p != null) p.afgebroken = true;
    final nieuw = _Poging(++_laatste, pad, grootte)
      ..goed = true
      ..klaar = true
      ..duur = p?.duur ?? Duration.zero;
    _pogingen[nieuw.n] = nieuw;
    _meldKlaar(nieuw);
  }

  /// Het hele nummer is er: iedereen die wacht, mag.
  void _meldKlaar(_Poging p) {
    for (final w in _wachters) {
      w.klaar.complete(true);
    }
    _wachters.clear();
  }

  /// Geen enkele peer leverde: wie wacht, krijgt een nee.
  void opgegeven() {
    if (_geland != null) return;
    _opgegeven = true;
    afgebroken();
    _laatNiemandWachten();
    _log('opgegeven');
  }

  /// Weg: geheugen vrij, het adres bestaat niet meer.
  void sluit() {
    if (_gesloten) return;
    _gesloten = true;
    _meter?.cancel();
    for (final p in _pogingen.values) {
      p.afgebroken = true;
      p.vast = null;
    }
    _laatNiemandWachten();
    _server._alle.remove(id);
  }

  void _laatNiemandWachten() {
    for (final w in _wachters) {
      w.klaar.complete(false);
    }
    _wachters.clear();
  }

  Future<_Poging?> _wachtOpBruikbaar(Duration max) async {
    final eind = DateTime.now().add(max);
    while (true) {
      final p = _huidig;
      if (p != null && p.goed && !p.afgebroken) return p;
      if (_opgegeven || _gesloten || DateTime.now().isAfter(eind)) return null;
      await Future<void>.delayed(_server.peil);
    }
  }

  static int _grootte(String pad) {
    try {
      return File(pad).lengthSync();
    } catch (_) {
      return 0;
    }
  }

  /// Openen, lezen, dicht: nooit een handvat dat blijft staan. Zie de kop van dit bestand.
  static Uint8List? _lees(String pad, int vanaf, int hoeveel) {
    RandomAccessFile? f;
    try {
      f = File(pad).openSync();
      f.setPositionSync(vanaf);
      return f.readSync(hoeveel);
    } catch (_) {
      return null;
    } finally {
      try {
        f?.closeSync();
      } catch (_) {}
    }
  }

  /// Een opening die bij [plek] begint: de kop van het bestand en daarachter de frames vanaf het frame waarin
  /// die tijd valt. Er valt niets te springen — en springen wacht in een FLAC op het einde van het bestand,
  /// ook mét zoektabel (gemeten op 20-10-2026: 9 en 52 s stilte na een peerwissel; zie flac_frames.dart).
  /// Elk frame draagt zijn eigen tijd, dus mpv toont de juiste plek en de volle duur, mits
  /// `rebase-start-time=no` (zie `_hervatGroei` in player.dart). Null als het frame niet te vinden is.
  _Opening? _openingVanaf(_Poging p, Duration plek) {
    final staat = p.klaar || p.vast != null ? p.totaal : _grootte(p.pad);
    Uint8List lees(int v, int n) {
      final vast = p.vast;
      if (vast != null) return Uint8List.sublistView(vast, min(v, vast.length), min(v + n, vast.length));
      if (v >= staat) return Uint8List(0);
      return _lees(p.pad, v, min(n, staat - v)) ?? Uint8List(0);
    }

    // De kop zoals de haal hem mat; past hij daar niet in (of is hij niet gemeten), dan ruimer lezen.
    var kop = lees(0, max(p.kop, 64 * 1024));
    if (flacBlokken(kop) == null) kop = lees(0, 16 * 1024 * 1024);
    final blokken = flacBlokken(kop);
    final si = flacStroominfo(kop);
    if (blokken == null || si == null || si.frequentie <= 0) {
      _log('poging ${p.n}: geen leesbare kop voor een start op ${plek.inSeconds} s — dan van voren af aan');
      return null;
    }
    final laatste = blokken.last;
    final audioBegin = laatste.begin + 4 + laatste.lengte;
    final doel = (plek.inMilliseconds * si.frequentie / 1000).round();
    final f = flacFrameBij(doel, audioBegin: audioBegin, einde: staat, si: si, lees: lees);
    if (f == null) {
      _log('poging ${p.n}: geen frame gevonden op ${plek.inSeconds} s — dan van voren af aan');
      return null;
    }
    _log('poging ${p.n} vanaf ${(f.monster / si.frequentie).toStringAsFixed(2)} s: frame op byte ${f.byte}');
    return _Opening(p, kop: Uint8List.fromList(Uint8List.sublistView(kop, 0, audioBegin)), vanByte: f.byte);
  }

  Future<void> _dien(HttpRequest req, _Opening o) async {
    final p = o.p;
    final res = req.response;
    final totaal = o.lengte;
    var start = 0;
    var eind = totaal - 1;
    final r = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(req.headers.value(HttpHeaders.rangeHeader) ?? '');
    if (r != null) {
      final a = r.group(1)!, b = r.group(2)!;
      if (a.isNotEmpty) {
        start = int.parse(a);
        if (b.isNotEmpty) eind = min(int.parse(b), totaal - 1);
      } else if (b.isNotEmpty) {
        start = max(0, totaal - int.parse(b));
      }
    }
    // **Een sprong voorbij wat er al is: meteen nee, niet wachten.** Om naar een tijd te springen leest
    // ffmpeg eerst vanaf het EINDE terug om de laatste tijd te vinden (`ff_find_last_ts`); met een nee
    // stapt hij verder terug tot hij in het binnengekomen deel uitkomt, in plaats van te wachten tot de
    // download klaar is. (Daarna loopt hij nog frame voor frame vooruit naar het einde, en DAT wacht wél —
    // daarom springt het verdergaan na een peerwissel niet, zie [_openingVanaf]. Alleen een sprong die jij
    // maakt terwijl het nog binnenkomt, kan nog op de download wachten.) Een gewone stroom vraagt nooit
    // voorbij het einde van wat hij kreeg, dus die merkt hier niets van.
    final staatNu = o.beschikbaar(p.klaar || p.vast != null ? p.totaal : _grootte(p.pad));
    if (start >= totaal || start > eind || start > staatNu) {
      res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$totaal');
      res.contentLength = 0;
      await res.close();
      return;
    }
    res.statusCode = r != null ? HttpStatus.partialContent : HttpStatus.ok;
    res.headers.contentType = ContentType('audio', 'flac');
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    if (r != null) res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$eind/$totaal');
    res.contentLength = eind - start + 1;
    if (req.method == 'HEAD') {
      await res.close();
      return;
    }
    p.gebruikt = true;
    p.open++;
    var pos = start;
    var stilSinds = DateTime.now();
    final kop = o.kop;
    try {
      while (pos <= eind && !p.afgebroken && !_gesloten) {
        Uint8List? stuk;
        if (kop != null && pos < kop.length) {
          stuk = Uint8List.sublistView(kop, pos, min(kop.length, eind + 1));
        } else {
          final echt = o.echt(pos), echtEind = o.echt(eind);
          final vast = p.vast;
          if (vast != null) {
            stuk = Uint8List.sublistView(vast, echt, min(echtEind + 1, echt + kGroeiStuk));
          } else if (!p.verhuist) {
            final staat = _grootte(p.pad);
            if (staat > echt) stuk = _lees(p.pad, echt, min(echtEind + 1, min(staat, echt + kGroeiStuk)) - echt);
          }
        }
        if (stuk != null && stuk.isNotEmpty) {
          res.add(stuk);
          await res.flush();
          pos += stuk.length;
          stilSinds = DateTime.now();
          continue;
        }
        if (DateTime.now().difference(stilSinds) > _server.stilGrens) {
          _log('poging ${p.n}: ${_server.stilGrens.inSeconds} s niets nieuws op byte $pos — opgegeven');
          break;
        }
        await Future<void>.delayed(_server.peil);
      }
      // Met minder bytes dan beloofd sluiten: Dart breekt de verbinding dan af ("Content size below
      // specified contentLength"), en ffmpeg ziet een breuk in plaats van een einde. Gemeten met een
      // eigen proef; `detachSocket` kan hier niet meer ("Headers already sent").
      await res.close();
    } catch (_) {
      // De speler hing op (een sprong, een ander nummer), of de breuk hierboven: niets aan de hand.
    } finally {
      p.open--;
    }
  }
}

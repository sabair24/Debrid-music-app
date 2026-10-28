import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models.dart';
import '../warm_log.dart';
import 'catalog.dart';
import 'dtos.dart';
import 'kef.dart';
import 'net.dart';
import 'speaker_klok.dart';
import 'transcode.dart';
import 'upnp.dart';
import 'zones.dart' show SpeakerStand, plekVoorNummer;

/// The Shield running the DebridMusic TV app.
///
/// Not a UPnP renderer — it takes a plain POST and hands the URL to ExoPlayer, which is the whole
/// reason to send music there rather than to a speaker: bit-perfect FLAC out of the HDMI, with no
/// ceiling on sample rate.
class ShieldTarget {
  const ShieldTarget({required this.host, required this.name});

  final String host;
  final String name;

  /// 8124, not 8123 — the Debrid **Media** app already listens on 8123 on the same Shield.
  static const port = 8124;

  String get id => 'shield:$host';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'model': 'Android TV',
        'manufacturer': 'DebridMusic',
        'kind': 'shield',
        'maxSampleRate': 0,
      };
}

/// The subnets to sweep for a television, from every address this machine has.
///
/// De-duplicated: two addresses on one subnet is one subnet. A plain function so the rule can be
/// stated in a test — the bug this exists for raises nothing and logs nothing, it just returns an
/// empty list as confidently as a correct search would.
Set<String> sweepPrefixes(Iterable<String> addresses) =>
    {for (final a in addresses) a.split('.').take(3).join('.')};

/// Ask one host whether the music receiver is listening, and what it calls itself.
///
/// Null for anything that is not ours: a closed port, some other web server, or the Debrid **Media**
/// app — which lives on the same television and answers the same shape one port down. Offering that
/// as a speaker would start a video player when somebody picked a place to listen.
Future<String?> probeShield(String host, {int port = ShieldTarget.port}) async {
  final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 600);
  try {
    final request = await client.getUrl(Uri.parse('http://$host:$port/ping'));
    final response = await request.close().timeout(const Duration(milliseconds: 900));
    if (response.statusCode != 200) return null;
    final body = await response.transform(utf8.decoder).join();
    if (!body.contains('debridmusic')) return null;
    // The receiver says what the television calls itself. Use it — "Woonkamer" is what the speaker
    // list should read; an address is what you fall back to, not what you show.
    try {
      final name = (jsonDecode(body) as Map)['name'];
      if (name is String && name.trim().isNotEmpty) return name.trim();
    } catch (_) {/* not JSON we understand; the address still identifies it */}
    return 'Shield ($host)';
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Is de MUZIEK een nummer opgeschoven, of alleen de boekhouding van de speaker?
///
/// Een losse functie omdat dit de regel is waar het casten twee keer op stukliep, en een regel die je in
/// een test kunt uitschrijven is een regel die je kunt controleren. Hij wordt pas gesteld als de speaker
/// de volgende-URL al in TrackURI meldt; de vraag hier is of dat ergens op slaat.
///
/// [top] is de hoogste positie die op het huidige nummer gezien is, [positie] wat de speaker nu meldt,
/// [gespeeld] hoe lang geleden dit nummer geopend werd, [lengte] hoe lang het duurt (null = onbekend).
///
/// Twee wegen, want niet elke speaker meldt hetzelfde:
///
/// * **De positie viel terug.** Het echte bewijs. Een speaker die aan een nieuw nummer begint telt weer
///   vanaf nul; zolang zijn klok dóórloopt speelt hetzelfde nummer nog, wat hij verder ook beweert.
/// * **De klok van hier.** Alleen voor speakers die geen bruikbare positie geven. Zwakker -- pauzeren
///   telt gewoon door -- maar het is dan de enige weg die nog open staat.
///
/// [terugval] staat ruim boven het geruis van een embedded klok en ruim onder de lengte van zelfs een kort
/// nummer. Ruim mag: bij de valse melding is de terugval niet klein maar negatief, want de positie stijgt.
({bool ja, String reden}) muziekIsGewisseld({
  required Duration top,
  required Duration gespeeld,
  Duration? positie,
  Duration? lengte,
  Duration terugval = const Duration(seconds: 10),
  Duration speling = const Duration(seconds: 15),
}) {
  // "Meldt deze speaker een positie?" is niet hetzelfde als "staat de positie hoog?". Op die twee door
  // elkaar te halen ging een eerdere versie hiervan alsnog de mist in: vlak na het begin van een nummer
  // staat de klok laag, en dan zou de klokweg het overnemen en meteen ja zeggen.
  if (positie != null && !(positie == Duration.zero && top == Duration.zero)) {
    if (top >= positie + terugval) {
      return (ja: true, reden: 'positie viel terug ${top.inSeconds}s → ${positie.inSeconds}s');
    }
    return (ja: false, reden: 'positie loopt door (top ${top.inSeconds}s, nu ${positie.inSeconds}s)');
  }
  if (lengte == null || lengte <= Duration.zero) {
    return (ja: true, reden: 'geen positie én geen lengte om aan te toetsen');
  }
  if (gespeeld >= lengte - speling) {
    return (ja: true, reden: 'geen positie, maar ${gespeeld.inSeconds}s van ${lengte.inSeconds}s om');
  }
  return (ja: false, reden: 'geen positie, pas ${gespeeld.inSeconds}s van ${lengte.inSeconds}s gespeeld');
}

/// Sends music to a speaker or the TV, and keeps it going.
///
/// The PC does this, not the iPad. Three reasons, in order of how much they matter:
/// the audio then goes straight from here to the speaker instead of being relayed by whatever
/// you happened to tap on; one implementation serves every device in the house; and it sidesteps
/// Apple's multicast entitlement, which SSDP discovery from an iPad would otherwise need.
/// De lijst die naar de Shield gaat: per bekend nummer een adres, en PARALLEL daaraan de
/// luidheidsopgave voor dat adres (gelijk volume). Eén lus met één `continue`, zodat de twee lijsten
/// nooit uit de pas lopen als een nummer niet (meer) in de catalogus staat. Puur, zodat een toets het
/// kan nalopen zonder Shield.
({List<String> urls, List<Map<String, dynamic>?> luidheid}) shieldLijst({
  required List<String> trackIds,
  required List<Track?> tracks,
  required String Function(String id, Track t) adres,
  Map<String, dynamic>? Function(Track t, List<Track> rij, int plek)? opgave,
}) {
  final rij = [for (final t in tracks) if (t != null) t];
  final urls = <String>[];
  final luidheid = <Map<String, dynamic>?>[];
  for (var i = 0; i < trackIds.length && i < tracks.length; i++) {
    final track = tracks[i];
    if (track == null) continue;
    urls.add(adres(trackIds[i], track));
    luidheid.add(opgave?.call(track, rij, urls.length - 1));
  }
  return (urls: urls, luidheid: luidheid);
}

/// Zo lang wacht een speaker die een nummer niet aannam, voor hij het nog één keer krijgt (zie `_openCurrent`).
const kOpnieuwOpenen = Duration(seconds: 1);

/// Waar een bewaarde sessie verdergaat na een herstart ([CastManager.herstelSessies]): de bewaarde plek als de speaker
/// daar nog staat, anders waar hij nu wel staat in de rij, en null als hij iets speelt wat niet in de rij staat.
int? herstelPlek(List<String> rij, int bewaard, String? speeltId) {
  if (speeltId == null) return null;
  if (bewaard >= 0 && bewaard < rij.length && rij[bewaard] == speeltId) return bewaard;
  final i = rij.indexOf(speeltId);
  return i < 0 ? null : i;
}

class CastManager {
  CastManager({
    required this.catalog,
    required this.token,
    required this.port,
    UpnpControlPoint? upnp,
    Transcoder? transcoder,
    String? logPath,
    @visibleForTesting this.startGrace = const Duration(seconds: 8),
    @visibleForTesting int Function()? klokUs,
    @visibleForTesting this.spoelNa = const Duration(seconds: 3),
    @visibleForTesting Future<String?> Function(String host)? adresVoor,
    @visibleForTesting this.toeval,
    @visibleForTesting KefBediening? kef,
    @visibleForTesting Future<List<Renderer>> Function()? zoekKef,
    this.sessiePad,
  })  : _upnp = upnp ?? UpnpControlPoint(),
        _kef = kef ?? KefBediening(),
        _zoekKef = zoekKef ?? zoekKefs,
        _transcoder = transcoder ?? Transcoder(),
        _klokUs = klokUs ?? (() => DateTime.now().microsecondsSinceEpoch),
        _adresVoor = adresVoor ?? lanAddressFor,
        _log = logPath == null ? null : WarmLog(logPath);

  /// De klok van de pc (µs) — dezelfde als die van `/api/tijd`, waar elk toestel zijn klok op ijkt.
  final int Function() _klokUs;

  /// Het adres van deze pc zoals [host] het ziet (een toets geeft er een vast adres voor: het netwerk
  /// aflopen is echte IO, en die loopt niet in een stilgezette klok).
  final Future<String?> Function(String host) _adresVoor;

  /// Het toeval van de speakerklok (een toets geeft een vast zaad).
  final Random? toeval;

  /// Hoe lang na het starten [play] met `vanafMs` spoelt: een Sonos negeert een Seek tijdens het laden.
  final Duration spoelNa;

  final LanCatalog catalog;
  final UpnpControlPoint _upnp;

  /// De KEF via zijn eigen API (zie `kef.dart`): dezelfde handelingen als [_upnp], in die vorm.
  final KefBediening _kef;
  final Future<List<Renderer>> Function() _zoekKef;

  /// Wie [r] bedient: de KEF-API of UPnP.
  UpnpControlPoint _voor(Renderer r) => isKef(r) ? _kef : _upnp;
  final Transcoder _transcoder;
  final int port;
  String token;

  /// Waarom de speaker stil bleef, als hij stil bleef.
  ///
  /// Casten faalt bij uitstek zonder klap: de app zet een album op het scherm, de speaker haalt het
  /// bestand op, kan er niets mee, en zwijgt. Tot nu toe stond er in de hele castlaag geen enkel
  /// foutveld — de app KON het je dus niet vertellen, en het enige spoor was `cast.log` op de pc.
  /// Deze reis mee in de status, zodat de speakerkiezer het gewoon kan zeggen.
  String? probleem;

  /// Wat er tussen de app en de speaker gebeurt, in `cast.log` naast de andere staatbestanden.
  ///
  /// Bestaat omdat casten precies het soort fout heeft waar redeneren op stukloopt: alles speelt door,
  /// niets klapt, er verschijnt geen melding -- alleen staat er een ander album op het scherm dan er
  /// klinkt. Van buitenaf is dat één symptoom voor een handvol oorzaken, en een release-build slikt
  /// [debugPrint]. Twee reparaties zijn zo op een vermoeden gemikt.
  ///
  /// Wat hier in gaat is de WAARNEMING, niet het oordeel: welke URI de speaker meldt, waar de positie
  /// staat, wat de sessie denkt. Dan is achteraf te zien of een regel goed besliste op slechte feiten of
  /// andersom.
  final WarmLog? _log;

  Map<String, Renderer> _renderers = {};
  List<ShieldTarget> _shields = [];

  /// De sessies, per speaker (zones, 21-10-2026: elke speaker is een eigen zone, en twee speakers kunnen
  /// tegelijk iets anders spelen). Elk met zijn eigen tijdklok en zijn eigen slot.
  ///
  /// **De oude speakerkeuze blijft één speaker tegelijk.** Wie in het speakerblad een andere speaker
  /// kiest, laat de vorige ophouden met doorschuiven, zoals altijd ([play] zonder `alsZone`). Alleen een
  /// zone (`/api/zone/cmd`) krijgt een sessie die naast de andere doorloopt.
  final Map<String, _Session> _sessies = {};

  /// Er veranderde iets aan wat de speaker doet (of er is geen sessie meer). Voor de zonelijst.
  void Function()? bijStand;

  /// Speakers waarmee toestellen meespelen (groeperen, stap 3.3, Saber 21-10-2026: "pc + Sonos ongeveer,
  /// met een schuif"). Die krijgen een [SpeakerKlok], ook als hun sessie pas later begint.
  final Set<String> _klokGewenst = {};

  /// Waar een speaker met meespelers is, veranderde: de server stuurt ze een nieuw anker ([ankerVan]).
  void Function(String speakerId)? bijAnker;

  /// Wat er met een radiosessie gebeurt (`speaker_radio.dart` volgt hem): de rij of de plek veranderde, hij
  /// staat droog, iemand wil verder (volgende op het laatste nummer), of de sessie is weg (een andere
  /// wachtrij nam de speaker over, of hij werd gestopt).
  Stream<({String id, bool wilVerder, bool weg})> get radioGebeurtenis => _radioGebeurtenis.stream;
  final _radioGebeurtenis = StreamController<({String id, bool wilVerder, bool weg})>.broadcast(sync: true);

  void _meldRadio(_Session s, {bool wilVerder = false, bool weg = false}) {
    if (s.radio == null || _radioGebeurtenis.isClosed) return;
    _radioGebeurtenis.add((id: s.renderer.id, wilVerder: wilVerder, weg: weg));
  }

  /// Staat de radiosessie op [id] droog (de rij is op, de radio vult hem nog aan)?
  bool isDroog(String id) => _sessies[id]?.droog ?? false;

  /// Toestellen spelen met speaker [id] mee ([aan]), of niet meer.
  void volgKlok(String id, bool aan) {
    if (aan) {
      _klokGewenst.add(id);
    } else {
      _klokGewenst.remove(id);
    }
    final s = _sessies[id];
    if (s != null) _zetKlok(s);
  }

  void _zetKlok(_Session s) {
    final wil = _klokGewenst.contains(s.renderer.id);
    if (wil && s.klok == null) {
      _log?.line('klok aan voor ${s.renderer.name}');
      s.klok = SpeakerKlok(
        klokUs: _klokUs,
        toeval: toeval,
        // Een KEF werkt zijn plek bij op een eigen klokje (~1 s, blokjes van 48 ms): zie speaker_klok.dart.
        houdMs: isKef(s.renderer) ? 1150 : 1000,
        korrelMs: isKef(s.renderer) ? 48 : 0,
        gericht: !isKef(s.renderer),
        vraag: () async => (await _voor(s.renderer).positionInfo(s.renderer))?.position?.inMilliseconds,
        bijVerandering: () {
          final p = s.klok?.plekNu;
          if (p != null && p.speelt) s.stilVoorKlok = null;
          // Niet via [_zie]: die voegt regels samen die alleen in getallen verschillen, en juist die getallen
          // (hoe smal de klok wordt) wil je bij een meting zien. Om de 5 s, en meteen bij een andere stand.
          final b = s.klok?.schatting.breedteUs;
          final stand = p == null ? '?' : (p.speelt ? 'speelt' : 'stil');
          final nu = DateTime.now().millisecondsSinceEpoch;
          if (stand != s.klokLogStand || nu - s.klokLogOp >= 5000) {
            s.klokLogStand = stand;
            s.klokLogOp = nu;
            _log?.line('klok ${s.renderer.name}: ${p == null ? '?' : p.speelt ? 'speelt op ${p.positieMs} ms' : 'stil'}'
                '${b == null ? '' : ' ±${(b / 2000).toStringAsFixed(1)} ms'}');
          }
          if (!s.aanloop) bijAnker?.call(s.renderer.id);
        },
        bijBreuk: () => unawaited(_naBreuk(s)),
      )..start();
    } else if (!wil && s.klok != null) {
      s.klok!.stop();
      s.klok = null;
      _log?.line('klok uit voor ${s.renderer.name}');
    }
  }

  /// De plek van [s] viel terug of sprong. Een nieuw nummer ziet de tijdklok pas binnen vijf seconden, en
  /// tot dan zou het anker het OUDE nummer noemen met de plek van het nieuwe: kijk dus meteen, en houd het
  /// anker zolang in.
  Future<void> _naBreuk(_Session s) async {
    if (s.wachtOpNummer) return;
    s.wachtOpNummer = true;
    try {
      for (var i = 0; i < 40 && s.advancing; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await _maybeAdvance(s);
    } catch (_) {
      // Dan pakt de tijdklok het op.
    } finally {
      s.wachtOpNummer = false;
    }
    if (!s.aanloop) bijAnker?.call(s.renderer.id);
  }

  /// De wachtrij van [s] veranderde (hierna, achteraan, verplaatst, weg): wie meespeelt, krijgt hem meteen,
  /// niet pas bij de volgende nummerwissel.
  void _rijVeranderd(_Session s) {
    if (s.klok != null && !s.aanloop && !s.wachtOpNummer) bijAnker?.call(s.renderer.id);
  }

  /// De speaker gaat stilstaan op [ms] (een pauze, spoelen of een ander nummer vanaf hier): wie meespeelt,
  /// hoort het meteen en wacht daar tot de speaker weer speelt — in plaats van door te spelen tot de klok
  /// het merkt.
  void _meldStil(_Session s, int ms) {
    final klok = s.klok;
    if (klok == null) return;
    s.stilVoorKlok = ms;
    klok.verstoord();
    if (!s.aanloop) bijAnker?.call(s.renderer.id);
  }

  /// Waar speaker [id] is, voor wie meespeelt (stap 3.3, zie `samen.dart`): in de vorm van
  /// `SamenAnker.toJson`. Null als dat nu niet te zeggen is (geen klok, net een nieuw nummer, nog aan het
  /// laden).
  Map<String, dynamic>? ankerVan(String id) {
    final s = _sessies[id];
    final klok = s?.klok;
    if (s == null || klok == null || s.wachtOpNummer || s.aanloop) return null;
    final tid = s.queue.elementAtOrNull(s.index);
    if (tid == null) return null;
    final stil = s.stilVoorKlok;
    final plek = klok.plekNu ?? (stil == null ? null : (speelt: false, positieMs: stil));
    if (plek == null) return null;
    return {
      'groep': 'spk:$id',
      'trackId': tid,
      'rij': List.of(s.queue),
      'index': s.index,
      'positieMs': plek.positieMs,
      'pcMs': _klokUs() ~/ 1000,
      'speelt': plek.speelt,
    };
  }

  /// Wat elke speaker met een sessie het laatst zei — zonder hem iets te vragen: de tijdklok van vijf
  /// seconden en elke statusvraag houden het bij. Zie `zones.dart`.
  List<SpeakerStand> get laatsteStanden => [for (final sessie in _sessies.values) _standVan(sessie)];

  SpeakerStand _standVan(_Session s) {
    final tid = s.queue.elementAtOrNull(s.index);
    var duur = s.duur?.inMilliseconds ?? 0;
    if (duur <= 0 && tid != null) duur = catalog.track(tid)?.duration?.inMilliseconds ?? 0;
    return (
      id: s.renderer.id,
      naam: s.renderer.name,
      trackId: tid,
      index: s.index,
      lengte: s.queue.length,
      // Nog niets gehoord: net gestart, dus speelt hij (of gaat hij zo spelen).
      speelt: s.speelt ?? true,
      positieMs: s.positie?.inMilliseconds ?? 0,
      duurMs: duur,
      opMs: s.gezienOp ?? s.startedAt.millisecondsSinceEpoch,
      volume: s.volume ?? -1,
      radio: s.radio ?? '',
    );
  }

  /// De speakers die de pc op het netwerk kent (ook zonder sessie): als zone in de lijst, zodat je er
  /// muziek naartoe kunt sturen. Zie [zoekSpeakers].
  List<({String id, String naam, bool sonos})> get bekendeSpeakers => [
        for (final r in _renderers.values) (id: r.id, naam: r.name, sonos: r.isSonos && r.udn.isNotEmpty),
      ];

  Timer? _zoeker;
  Timer? _groepKijker;

  /// Hoe de Sonossen gegroepeerd zijn (stap 3.1, Saber 21-10-2026: "Sonos onderling"), in renderer-ids:
  /// per groep van meer dan één bekende speaker de leider en alle leden (de leider erbij). Gelezen bij het
  /// zoeken, om de minuut (de Sonos-app kan ze ook veranderen) en na elke wijziging hier.
  List<({String leider, List<String> leden})> get speakerGroepen => _groepen;
  List<({String leider, List<String> leden})> _groepen = const [];

  Renderer? _vanUdn(String udn) => _renderers.values.where((r) => r.udn == udn).firstOrNull;

  /// De groep waarvan [id] de leider is, met meer dan één lid; of null.
  ({String leider, List<String> leden})? _groepVan(String id) =>
      _groepen.where((g) => g.leider == id && g.leden.length > 1).firstOrNull;

  Future<void> leesGroepen() async {
    final sonos = _renderers.values.where((r) => r.isSonos && r.udn.isNotEmpty).firstOrNull;
    if (sonos == null) return;
    final g = await _upnp.sonosGroepen(sonos).catchError((Object _) => null);
    if (g == null) return;
    final nieuw = [
      for (final x in g)
        if (_vanUdn(x.leider) case final leider?)
          (leider: leider.id, leden: [for (final l in x.leden) if (_vanUdn(l) case final r?) r.id]),
    ].where((x) => x.leden.length > 1).toList();
    final was = [for (final x in _groepen) '${x.leider}:${x.leden.join(',')}'].join(';');
    final nu = [for (final x in nieuw) '${x.leider}:${x.leden.join(',')}'].join(';');
    if (was == nu) return;
    _groepen = nieuw;
    _log?.line('groepen: ${nieuw.isEmpty ? '(geen)' : nu}');
    bijStand?.call();
  }

  /// [leiderId] met precies [ledenIds] in één groep: wie er nog niet in zat, komt erbij (en houdt op met
  /// zijn eigen muziek); wie er wel in zat en niet in [ledenIds] staat, gaat eruit. Alleen Sonossen: die
  /// lopen onderling op de seconde gelijk.
  ///
  /// **De Sonossen melden een nieuwe groep pas na een paar seconden** (gemeten 21-10-2026: "los" kort na
  /// "samen" deed niets, want de pc zag de groep nog niet). Daarom eerst de echte groepen lezen, dan meteen
  /// tonen wat er gevraagd is, en na 2 en 5 s nog eens nalezen.
  Future<void> groepeer(String leiderId, List<String> ledenIds) async {
    final leider = await _renderer(leiderId);
    if (!leider.isSonos || leider.udn.isEmpty) throw StateError('Alleen Sonossen kunnen (nog) samen spelen.');
    // Wat er net gevraagd was (misschien nog niet door de Sonossen gemeld) én wat ze nu melden.
    final gevraagd = {...?_groepVan(leiderId)?.leden};
    await leesGroepen();
    // Is de leider zelf lid van een andere groep, dan eerst op zichzelf.
    if (_groepen.any((g) => g.leider != leiderId && g.leden.contains(leiderId))) {
      await _upnp.maakLosUitGroep(leider);
    }
    final willen = {...ledenIds}..remove(leiderId);
    final nu = {...gevraagd, ...?_groepVan(leiderId)?.leden}..remove(leiderId);
    for (final id in willen.difference(nu)) {
      final lid = await _renderer(id);
      if (!lid.isSonos || lid.udn.isEmpty) throw StateError('${lid.name} is geen Sonos.');
      final eigen = _sessies[id];
      if (eigen != null) _sluit(eigen);
      await _upnp.voegToeAanGroep(lid, leider.udn);
      _log?.line('groep: ${lid.name} bij ${leider.name}');
    }
    for (final id in nu.difference(willen)) {
      await _upnp.maakLosUitGroep(await _renderer(id));
      _log?.line('groep: ${_renderers[id]?.name ?? id} los van ${leider.name}');
    }
    // Meteen tonen wat er gevraagd is; de Sonossen bevestigen het straks.
    _groepen = [
      for (final g in _groepen)
        if (g.leider != leiderId && !willen.contains(g.leider))
          (leider: g.leider, leden: [for (final l in g.leden) if (l != leiderId && !willen.contains(l)) l]),
      if (willen.isNotEmpty) (leider: leiderId, leden: [leiderId, ...willen]),
    ].where((g) => g.leden.length > 1).toList();
    bijStand?.call();
    for (final na in const [Duration(seconds: 2), Duration(seconds: 5)]) {
      Timer(na, () => unawaited(leesGroepen()));
    }
  }

  /// Om de [elke] op het netwerk kijken welke speakers er zijn (en meteen één keer). Alleen in de app:
  /// een toets mag het netwerk niet op (zie "toets nooit tegen de echte deur").
  void zoekSpeakers({Duration elke = const Duration(minutes: 10)}) {
    _zoeker?.cancel();
    Future<void> zoek() async {
      try {
        await devices();
      } catch (_) {/* geen netwerk: de vorige lijst blijft */}
    }

    unawaited(zoek());
    _zoeker = Timer.periodic(elke, (_) => unawaited(zoek()));
    _groepKijker?.cancel();
    _groepKijker = Timer.periodic(const Duration(minutes: 1), (_) => unawaited(leesGroepen()));
  }

  /// Onthoud wat de speaker zei, en meld het als het iets nieuws is.
  void _zag(_Session s, {Duration? positie, Duration? duur, bool? speelt}) {
    final nu = DateTime.now().millisecondsSinceEpoch;
    final speeltWas = s.speelt;
    // Waar hij nu zou moeten zijn als hij gewoon doorspeelde: wijkt de melding meer dan drie seconden
    // af, dan is er gespoeld en moet de lijst het ook weten.
    final verwacht = (s.positie?.inMilliseconds ?? 0) +
        ((s.speelt ?? true) && s.gezienOp != null ? nu - s.gezienOp! : 0);
    final gesprongen = positie != null && s.gezienOp != null && (positie.inMilliseconds - verwacht).abs() > 3000;
    if (positie != null) s.positie = positie;
    if (duur != null && duur > Duration.zero) s.duur = duur;
    if (speelt != null) s.speelt = speelt;
    s.gezienOp = nu;
    if (speeltWas != s.speelt || s.zagIndex != s.index || gesprongen) {
      s.zagIndex = s.index;
      bijStand?.call();
      _meldRadio(s);
    }
  }

  /// Every place the music can go, this device excluded.
  Future<List<Map<String, dynamic>>> devices({bool refresh = true}) async {
    if (refresh || _renderers.isEmpty) {
      final found = await _upnp.discover();
      final kefs = await _zoekKef().catchError((Object _) => <Renderer>[]);
      _renderers = {for (final r in found) r.id: r, for (final k in kefs) k.id: k};
      for (final r in _renderers.values) {
        _namen[r.id] = r.name;
      }
      _shields = await _findShields();
      bijStand?.call();
      unawaited(leesGroepen());
    }
    return [
      for (final r in _renderers.values) r.toJson(),
      for (final s in _shields) s.toJson(),
    ];
  }

  /// Ask the LAN whether a Shield running the TV app is listening.
  ///
  /// A direct probe of the /24 rather than mDNS: the Shield's receiver is a bare socket with no
  /// service advertisement, and on a home network 254 parallel pings with a short timeout finish
  /// in under a second.
  ///
  /// EVERY /24 this machine is on, not just the first. A PC with a Hyper-V switch, a VPN adapter or
  /// two network cards has several, and [primaryLanAddress] can only guess which one the television
  /// is on — guess wrong and the sweep runs to completion against a subnet with nothing in it, then
  /// reports no Shield with as much confidence as if it had looked in the right place.
  Future<List<ShieldTarget>> _findShields() async {
    final own = await lanAddresses();
    if (own.isEmpty) return [];
    final mine = own.toSet();
    final prefixes = sweepPrefixes(own);
    final found = <ShieldTarget>[];
    await Future.wait([
      for (final prefix in prefixes)
        for (var i = 1; i < 255; i++)
          () async {
            final host = '$prefix.$i';
            if (mine.contains(host)) return;
            final name = await _pingShield(host);
            if (name != null) found.add(ShieldTarget(host: host, name: name));
          }()
    ]);
    found.sort((a, b) => a.host.compareTo(b.host));
    return found;
  }

  Future<String?> _pingShield(String host) => probeShield(host);

  // ── Playing ──────────────────────────────────────────────────────────────

  /// Start [trackIds] on [deviceId] at [index].
  ///
  /// [alsZone]: vanuit de zones. Dan blijven de andere speakers spelen wat ze speelden; anders (de oude
  /// speakerkeuze) houdt de vorige speaker op met doorschuiven, zoals altijd.
  ///
  /// [vanafMs]: zo ver in het nummer beginnen (overdragen, samen spelen). Een Sonos negeert een Seek tijdens
  /// het laden, dus spoelt dit pas na [spoelNa], naar waar de bron dan is. Tot dan krijgt wie meespeelt geen
  /// anker: die speelt gewoon door tot de speaker op zijn plek staat.
  ///
  /// [radio]: een radio van de pc speelt hier (`speaker_radio.dart`), met deze naam. Zo'n sessie blijft open
  /// als de rij op is ([_Session.droog]) — de radio vult hem aan — en meldt wat er gebeurt ([radioGebeurtenis]).
  Future<void> play(String deviceId, List<String> trackIds, int index,
      {bool alsZone = false, int vanafMs = 0, String? radio}) async {
    if (trackIds.isEmpty) throw ArgumentError('nothing to play');
    _tussendoor.remove(deviceId);
    if (!alsZone) {
      for (final ander in _sessies.values.where((x) => !x.alsZone && x.renderer.id != deviceId).toList()) {
        _sluit(ander);
      }
    }

    final shield = _shields.where((s) => s.id == deviceId).firstOrNull;
    if (shield != null) {
      await _playOnShield(shield, trackIds, index);
      return;
    }

    final renderer = await _renderer(deviceId);
    _log?.line('── start op ${renderer.name}: ${trackIds.length} nummers, vanaf $index'
        '${alsZone ? ' (zone)' : ''} ──');
    final oud = _sessies[renderer.id];
    if (oud != null) _sluit(oud, melden: false);
    final session = _Session(
        renderer: renderer,
        queue: List.of(trackIds),
        index: index.clamp(0, trackIds.length - 1),
        alsZone: alsZone);
    session.radio = radio;
    _sessies[renderer.id] = session;
    final spoelen = vanafMs > 3000;
    session.aanloop = spoelen;
    _zetKlok(session);
    bijStand?.call();
    _bewaarSessies();
    try {
      await _openCurrent(session);
    } catch (e) {
      // Een start die niet lukte, laat geen sessie achter: anders staat de speaker in de zones als bron, met een rij en
      // een klok, terwijl hij niets speelt. Gezien op de pc (22-10-2026, 19:01:54): de KEF nam het niet aan, en een
      // kwartier later werd er "overgedragen" van een KEF die nooit begonnen was.
      _log?.line('START MISLUKT op ${renderer.name}: $e');
      _sluit(session);
      rethrow;
    }
    if (spoelen) {
      final begon = _klokUs();
      Timer(spoelNa, () => unawaited(_spoelNaStart(session, vanafMs, begon)));
    }
    // The renderer plays one track; something has to notice it ended and send the next.
    // Een KEF zet geen volgend nummer klaar (naadloos): hij stopt, en dan opent de cast het volgende. Elke
    // seconde kijken houdt dat gat kort; om de 5 s was het tot 5 s stilte.
    session.advance = Timer.periodic(Duration(seconds: isKef(renderer) ? 1 : 5), (_) => _maybeAdvance(session));
    unawaited(_haalVolume(session));
  }

  Future<void> _spoelNaStart(_Session s, int vanafMs, int begonUs) async {
    if (!identical(_sessies[s.renderer.id], s)) return;
    // Waar de bron nu is, op een halve seconde afgerond (de Sonos spoelt op hele seconden).
    final doel = (vanafMs + (_klokUs() - begonUs) ~/ 1000 + 500) ~/ 1000;
    try {
      s.hoogstePositie = Duration(seconds: doel);
      await _voor(s.renderer).seek(s.renderer, Duration(seconds: doel));
      _log?.line('gespoeld naar ${doel}s (na het laden)');
    } catch (_) {
      // Dan speelt hij vanaf het begin; wie meespeelt, volgt hem daar.
    } finally {
      s.aanloop = false;
      _meldStil(s, doel * 1000);
    }
  }

  /// Een sessie beëindigen: geen tijdklok meer, en weg uit de lijst. De speaker zelf krijgt niets te
  /// horen (hij speelt het nummer van nu uit), net als vroeger bij een andere keuze.
  void _sluit(_Session s, {bool melden = true}) {
    s.advance?.cancel();
    s.advance = null;
    _meldRadio(s, weg: true);
    s.klok?.stop();
    s.klok = null;
    if (identical(_sessies[s.renderer.id], s)) _sessies.remove(s.renderer.id);
    if (melden) bijStand?.call();
    _bewaarSessies();
  }

  /// Waar de speakersessies op schijf staan (`cast_sessies.json`), of null: dan niets bewaren (een toets).
  ///
  /// **Waarom (Saber, 28-10-2026).** *"als ik de app sluit dat de kef wireless verder speelt maar de app ziet wel de kef
  /// maar niet meer wat er speelt"*. De rij, de plek en welke speaker stonden alleen in het geheugen. De KEF speelt na
  /// het sluiten zijn nummer uit; na een herstart wist de app niet meer dat het zijn nummer was, en deed hij niets meer.
  final String? sessiePad;

  /// Wat er het laatst bewaard is, als korte vingerafdruk: bewaren gebeurt alleen bij een verschil.
  String _bewaardAls = '';

  /// Achter elkaar schrijven, nooit twee tegelijk.
  Future<void> _bewaarRij = Future.value();

  /// Voor een toets: klaar met wegschrijven.
  @visibleForTesting
  Future<void> get bewaardVoorToets => _bewaarRij;

  void _bewaarSessies() {
    final pad = sessiePad;
    if (pad == null) return;
    final vinger = [
      for (final s in _sessies.values)
        '${s.renderer.id}|${s.index}|${s.queue.length}|${s.queue.isEmpty ? '' : s.queue.last}|${s.alsZone}',
    ].join(';');
    if (vinger == _bewaardAls) return;
    _bewaardAls = vinger;
    final tekst = jsonEncode([
      for (final s in _sessies.values)
        {'id': s.renderer.id, 'naam': s.renderer.name, 'rij': s.queue, 'plek': s.index, 'zone': s.alsZone},
    ]);
    _bewaarRij = _bewaarRij.then((_) async {
      try {
        await File(pad).writeAsString(tekst, flush: true);
      } catch (e) {
        _log?.line('sessies bewaren lukte niet: $e');
      }
    });
  }

  /// Na een herstart van de app: de speakers die nog spelen wat deze pc ze gaf, weer volgen — zonder ze opnieuw te
  /// starten. Een speaker die intussen iets anders speelt (een eigen app, de radio van de KEF) laat hij met rust.
  ///
  /// Welk nummer hij speelt, zegt de speaker zelf: het id in zijn adres (`/stream/<id>.…`). Staat dat in de bewaarde rij,
  /// dan gaat de sessie daar verder; als het nummer op is, opent de app het volgende, zoals altijd.
  Future<void> herstelSessies() async {
    final pad = sessiePad;
    if (pad == null) return;
    List<dynamic> lijst;
    try {
      final f = File(pad);
      if (!await f.exists()) return;
      lijst = jsonDecode(await f.readAsString()) as List<dynamic>;
    } catch (e) {
      _log?.line('herstel: cast_sessies.json niet te lezen: $e');
      return;
    }
    if (lijst.isEmpty) return;
    // Zoeken alleen als er een speaker bij is die hij nog niet kent (na een herstart: allemaal).
    if (lijst.any((e) => e is! Map || !_renderers.containsKey(e['id']))) {
      try {
        await devices();
      } catch (_) {/* dan kent hij alleen wat hij al kende */}
    }
    for (final e in lijst.whereType<Map>()) {
      final id = e['id'];
      if (id is! String || _sessies.containsKey(id)) continue;
      final r = _renderers[id];
      final rij = [for (final x in (e['rij'] as List<dynamic>? ?? const [])) '$x'];
      if (r == null || rij.isEmpty) {
        _log?.line('herstel: ${e['naam'] ?? id} ${r == null ? 'niet gevonden' : 'zonder rij'} — niet gevolgd');
        continue;
      }
      ({Duration? position, Duration duration, String? trackUri})? pos;
      try {
        pos = await _voor(r).positionInfo(r);
      } catch (_) {/* geen antwoord: dan niet */}
      final plek = herstelPlek(rij, (e['plek'] as num?)?.toInt() ?? -1, _idVanUrl(pos?.trackUri));
      if (plek == null) {
        _log?.line('herstel: ${r.name} speelt niet meer uit deze rij — niet gevolgd');
        continue;
      }
      final s = _Session(renderer: r, queue: rij, index: plek, alsZone: e['zone'] == true);
      s.currentUrl = pos?.trackUri;
      // Meteen geloven wat hij meldt: hij speelt al lang, er is geen aanloop om af te wachten.
      s.startedAt = DateTime.now().subtract(startGrace);
      _sessies[r.id] = s;
      _zetKlok(s);
      if (pos?.position case final p?) _zag(s, positie: p, duur: pos!.duration);
      s.advance = Timer.periodic(Duration(seconds: isKef(r) ? 1 : 5), (_) => _maybeAdvance(s));
      _log?.line('herstel: volgt ${r.name} weer — ${_naam(rij[plek])} (${plek + 1}/${rij.length})');
      unawaited(_haalVolume(s));
    }
    bijStand?.call();
    _bewaarSessies();
  }

  /// Het volume van de speaker, voor de schuif van zijn zone. Stil bij een speaker zonder volume.
  Future<void> _haalVolume(_Session s) async {
    try {
      // De leider van een groep: het volume van de hele groep.
      final v = _groepVan(s.renderer.id) != null
          ? await _upnp.groepsvolume(s.renderer)
          : await _voor(s.renderer).getVolume(s.renderer);
      if (v != null && v != s.volume) {
        s.volume = v;
        bijStand?.call();
      }
    } catch (_) {}
  }

  /// Nummers in de wachtrij van de speaker zetten: achter het spelende nummer ([hierna]) of achteraan.
  /// Wat er al komt en hetzelfde nummer is, verhuist (zoals op een toestel).
  Future<void> voegToe(String deviceId, List<String> ids, {required bool hierna}) async {
    final s = _sessies[deviceId];
    if (s == null) throw StateError('Die speaker speelt nu niets.');
    if (ids.isEmpty) return;
    // Tussendoor: in de rij die terugkomt — de radio vult gewoon aan, en hoort niets van de kopie.
    final td = _tussendoor[deviceId];
    if (td != null) {
      if (hierna) {
        td.queue.insertAll(td.index + 1, ids);
      } else {
        td.queue.addAll(ids);
      }
      return;
    }
    final nieuw = ids.toSet();
    for (var i = s.queue.length - 1; i > s.index; i--) {
      if (nieuw.contains(s.queue[i])) s.queue.removeAt(i);
    }
    final volgendeWas = s.queue.elementAtOrNull(s.index + 1);
    if (hierna) {
      s.queue.insertAll(s.index + 1, ids);
    } else {
      s.queue.addAll(ids);
    }
    if (s.droog && s.index + 1 < s.queue.length) {
      // Een droge radio: het eerste nieuwe nummer meteen.
      s.droog = false;
      s.index++;
      _log?.line('radio weer verder op ${s.renderer.name}');
      await _openCurrent(s);
      bijStand?.call();
      _rijVeranderd(s);
      _meldRadio(s);
      return;
    }
    _log?.line('${hierna ? 'hierna' : 'achteraan'}: ${ids.length} nummers  (nu ${s.queue.length})');
    // De speaker kreeg het volgende nummer al mee; is dat een ander geworden, dan het nieuwe.
    if (s.queue.elementAtOrNull(s.index + 1) != volgendeWas) await _armNext(s);
    bijStand?.call();
    _rijVeranderd(s);
    _meldRadio(s);
  }

  /// De wachtrij van een speaker met een sessie, en waar hij is. Null zonder sessie.
  ({List<String> rij, int index})? rijVan(String deviceId) {
    final s = _sessies[deviceId];
    // Tussendoor ([tussendoor]): de rij die terugkomt, niet de kopie die je even hoort.
    final td = _tussendoor[deviceId];
    if (td != null && s != null) return (rij: List.unmodifiable(td.queue), index: td.index);
    return s == null ? null : (rij: List.unmodifiable(s.queue), index: s.index);
  }

  /// Tot welke frequentie (0 = geen) en diepte een speaker het origineel neemt — voor "omgezet" op de zonekaart
  /// (zones, stap 3). Null als de pc de speaker niet kent.
  ({int rate, int bits})? plafondVan(String id) {
    final r = _renderers[id];
    return r == null ? null : (rate: r.maxSampleRate, bits: r.maxBitDepth);
  }

  /// Naar het nummer op [plek] in de wachtrij van de speaker. Met [trackId]: dat nummer, ook als de rij
  /// intussen verschoof ([plekVoorNummer]).
  Future<void> springNaar(String deviceId, int plek, {String trackId = ''}) async {
    final s = _sessies[deviceId];
    if (s == null) throw StateError('Die speaker speelt nu niets.');
    _zonderTussendoor(s);
    final i = plekVoorNummer(s.queue, plek, trackId);
    if (i < 0) throw StateError('Dat nummer staat niet meer in de wachtrij.');
    s.index = i;
    await _openCurrent(s);
  }

  /// Een nummer dat nog komt uit de wachtrij van de speaker halen.
  Future<void> haalUit(String deviceId, int plek, {String trackId = ''}) async {
    final s = _sessies[deviceId];
    if (s == null) throw StateError('Die speaker speelt nu niets.');
    _zonderTussendoor(s);
    final i = plekVoorNummer(s.queue, plek, trackId);
    if (i < 0 || i == s.index) throw StateError('Dat nummer staat niet (meer) in wat er nog komt.');
    s.queue.removeAt(i);
    if (i < s.index) s.index--;
    if (i == s.index + 1) await _armNext(s);
    bijStand?.call();
    _rijVeranderd(s);
    _meldRadio(s);
  }

  /// Een nummer in de wachtrij van de speaker verplaatsen, van [van] naar [naar].
  Future<void> verplaats(String deviceId, int van, int naar, {String trackId = ''}) async {
    final s = _sessies[deviceId];
    if (s == null) throw StateError('Die speaker speelt nu niets.');
    _zonderTussendoor(s);
    final i = plekVoorNummer(s.queue, van, trackId);
    if (i < 0 || i == s.index || naar < 0 || naar >= s.queue.length) {
      throw StateError('Dat nummer staat niet (meer) in wat er nog komt.');
    }
    final volgendeWas = s.queue.elementAtOrNull(s.index + 1);
    final id = s.queue.removeAt(i);
    s.queue.insert(naar, id);
    if (i < s.index && naar >= s.index) {
      s.index--;
    } else if (i > s.index && naar <= s.index) {
      s.index++;
    }
    if (s.queue.elementAtOrNull(s.index + 1) != volgendeWas) await _armNext(s);
    bijStand?.call();
    _rijVeranderd(s);
    _meldRadio(s);
  }

  /// [id] meteen, en de rest laten staan ("Nu spelen, rest laten staan").
  Future<void> speelNu(String deviceId, String id) async {
    final s = _sessies[deviceId];
    if (s == null) throw StateError('Die speaker speelt nu niets.');
    _zonderTussendoor(s);
    for (var i = s.queue.length - 1; i > s.index; i--) {
      if (s.queue[i] == id) s.queue.removeAt(i);
    }
    s.queue.insert(s.index + 1, id);
    s.index++;
    await _openCurrent(s);
  }

  // ── Tussendoor beluisteren ─────────────────────────────────────────────────

  /// Een klaargezette kopie beluisteren op een speaker, zonder zijn rij weg te gooien (Saber, 26-10-2026: "als ik
  /// luister op de kef op de kef … men liedje hervatten en men wachtrij moet er nog staan"). De sessie blijft dezelfde
  /// — een radio erop hoort niet dat hij weg is ([_meldRadio]) en vult de bewaarde rij gewoon aan ([voegToe]) — maar
  /// speelt even [b] (`kandidaat-…`, de nieuwe kopie) of [a] (het nummer zelf), A/B op dezelfde seconde
  /// ([tussendoorAB]). [tussendoorKlaar] zet de rij terug, op het nummer en de seconde waar hij was.
  Future<void> tussendoor(String deviceId, {required String a, required String b}) async {
    final s = _sessies[deviceId];
    if (s == null) throw StateError('Die speaker speelt nu niets.');
    var td = _tussendoor[deviceId];
    if (td == null) {
      final plek = s.klok?.plekNu?.positieMs ?? s.positie?.inMilliseconds ?? 0;
      td = _Tussendoor(queue: List.of(s.queue), index: s.index, positieMs: plek, speelde: s.speelt ?? true, a: a, b: b);
      _tussendoor[deviceId] = td;
    }
    td.opB = true;
    _log?.line('tussendoor op ${s.renderer.name}: B ($b); de rij (${td.queue.length}, nummer ${td.index + 1}) wacht '
        'op ${_sec(Duration(milliseconds: td.positieMs))}');
    await _speelTussendoor(s, b, vanafMs: 0);
  }

  /// A en B wisselen bij het tussendoor beluisteren op een speaker, op dezelfde seconde.
  Future<void> tussendoorAB(String deviceId) async {
    final s = _sessies[deviceId];
    final td = _tussendoor[deviceId];
    if (s == null || td == null) throw StateError('Er wordt op die speaker niets tussendoor beluisterd.');
    final pos = await _voor(s.renderer).positionInfo(s.renderer).catchError((_) => null);
    td.opB = !td.opB;
    final plek = pos?.position?.inMilliseconds ?? s.positie?.inMilliseconds ?? 0;
    _log?.line('tussendoor op ${s.renderer.name}: ${td.opB ? 'B' : 'A'} op ${_sec(Duration(milliseconds: plek))}');
    await _speelTussendoor(s, td.opB ? td.b : td.a, vanafMs: plek);
  }

  /// Tussendoor stoppen: de rij terug, op het nummer en de seconde waar hij was. [hervat] = false: daar op pauze.
  Future<void> tussendoorKlaar(String deviceId, {bool hervat = true}) async {
    final s = _sessies[deviceId];
    final td = _tussendoor.remove(deviceId);
    if (s == null || td == null) return;
    s.queue = td.queue;
    s.index = td.index.clamp(0, td.queue.isEmpty ? 0 : td.queue.length - 1);
    final spelen = hervat && td.speelde;
    _log?.line('tussendoor op ${s.renderer.name} klaar: terug naar nummer ${s.index + 1} op '
        '${_sec(Duration(milliseconds: td.positieMs))}${spelen ? '' : ' (op pauze)'}');
    await _openCurrent(s);
    bijStand?.call();
    _rijVeranderd(s);
    if (td.positieMs > 3000 || !spelen) {
      Timer(spoelNa, () async {
        if (!identical(_sessies[s.renderer.id], s)) return;
        try {
          if (td.positieMs > 3000) {
            s.hoogstePositie = Duration(milliseconds: td.positieMs);
            await _voor(s.renderer).seek(s.renderer, Duration(milliseconds: td.positieMs));
          }
          if (!spelen) await _voor(s.renderer).pause(s.renderer);
          _meldStil(s, td.positieMs);
        } catch (_) {/* dan speelt hij vanaf het begin van het nummer: niets kwijt */}
      });
    }
  }

  /// Is er op [deviceId] iets tussendoor te horen, en is dat B?
  ({bool opB})? tussendoorVan(String deviceId) {
    final td = _tussendoor[deviceId];
    return td == null ? null : (opB: td.opB);
  }

  final _tussendoor = <String, _Tussendoor>{};

  // ── Versies (versies.dart) ────────────────────────────────────────────

  /// Welke versie er voor een nummer speelt als je niets kiest: het id van die versie, of [id] zelf. Gezet door de
  /// server (`library.speelPadVoor`).
  String Function(String id)? speelVersie;

  /// Waar het moment [ms] van versie [van] in versie [naar] valt (een vinylrip begint vaak later). Gezet door de server;
  /// zonder: dezelfde ms.
  int Function(String van, String naar, int ms)? versiePlek;

  String _speelId(_Session s, int index, String anker) {
    final v = s.versie;
    if (v != null && v.index == index && v.anker == anker) return v.id;
    return speelVersie?.call(anker) ?? anker;
  }

  /// Welke versie er nu klinkt op [deviceId] (het id), of null zonder sessie.
  String? versieVan(String deviceId) {
    final s = _sessies[deviceId];
    final anker = s?.queue.elementAtOrNull(s.index);
    return s == null || anker == null ? null : _speelId(s, s.index, anker);
  }

  /// Een andere versie van het spelende nummer op de speaker (Saber, 26-10-2026: speakers ook, "met ~1 s stilte"): hij
  /// opent [versieId] en spoelt naar hetzelfde moment in de muziek ([versiePlek]). De rij en de radio blijven staan.
  Future<void> wisselVersie(String deviceId, String versieId) async {
    final s = _sessies[deviceId];
    if (s == null) throw StateError('Die speaker speelt nu niets.');
    if (_tussendoor.containsKey(deviceId)) throw StateError('Er wordt tussendoor iets beluisterd.');
    final anker = s.queue.elementAtOrNull(s.index);
    if (anker == null) return;
    final van = _speelId(s, s.index, anker);
    if (van == versieId) return;
    final pos = await _voor(s.renderer).positionInfo(s.renderer).catchError((_) => null);
    final plek = pos?.position?.inMilliseconds ?? s.klok?.plekNu?.positieMs ?? s.positie?.inMilliseconds ?? 0;
    final speelde = s.speelt ?? true;
    final t0 = _klokUs();
    s.versie = (index: s.index, anker: anker, id: versieId);
    _log?.line('versie op ${s.renderer.name}: ${_naam(van)} → ${_naam(versieId)} op ${_sec(Duration(milliseconds: plek))}');
    await _openCurrent(s);
    bijStand?.call();
    Timer(spoelNa, () async {
      if (!identical(_sessies[s.renderer.id], s)) return;
      // Waar de muziek nu zou zijn: de plek van toen, plus de tijd van het openen, in de nieuwe versie.
      final doel = (versiePlek?.call(van, versieId, plek) ?? plek) + (_klokUs() - t0) ~/ 1000;
      try {
        s.hoogstePositie = Duration(milliseconds: doel);
        await _voor(s.renderer).seek(s.renderer, Duration(milliseconds: doel));
        if (!speelde) await _voor(s.renderer).pause(s.renderer);
        _meldStil(s, doel);
      } catch (_) {/* dan speelt hij vanaf het begin van het nummer: niets kwijt */}
    });
  }

  /// [id] op de speaker van [s], als enige in zijn rij, vanaf [vanafMs].
  Future<void> _speelTussendoor(_Session s, String id, {required int vanafMs}) async {
    s.queue = [id];
    s.index = 0;
    s.droog = false;
    await _openCurrent(s);
    bijStand?.call();
    if (vanafMs > 3000) {
      Timer(spoelNa, () async {
        if (!identical(_sessies[s.renderer.id], s)) return;
        try {
          s.hoogstePositie = Duration(milliseconds: vanafMs);
          await _voor(s.renderer).seek(s.renderer, Duration(milliseconds: vanafMs));
        } catch (_) {}
      });
    }
  }

  /// Iemand bedient de rij (volgende, springen, weghalen): het tussendoor is dan voorbij, en de rij is weer de rij.
  void _zonderTussendoor(_Session s) {
    final td = _tussendoor.remove(s.renderer.id);
    if (td == null) return;
    s.queue = td.queue;
    s.index = td.index.clamp(0, td.queue.isEmpty ? 0 : td.queue.length - 1);
  }

  /// The Shield gets the whole queue at once — it has a real player and can manage its own gaps.
  /// Gelijk volume voor de Shield: de opgave per nummer (meting, plaatwaarde, stand van deze pc), of
  /// null. Ingehangen vanuit main.dart — daar zitten de bibliotheek en de instellingen. Zie
  /// luidheid_winkel.dart `zenderopgaveVoor`. Statisch: de castmanager wordt pas met de server
  /// gemaakt, en dit hoort één keer bij het opstarten gezet te worden.
  static Map<String, dynamic>? Function(Track t, List<Track> rij, int plek)? luidheidOpgave;

  Future<void> _playOnShield(ShieldTarget shield, List<String> trackIds, int index) async {
    final base = await lanAddressFor(shield.host);
    if (base == null) throw StateError('no route to ${shield.host}');
    // De versie die voor elk nummer speelt (versies.dart).
    final ids = [for (final id in trackIds) speelVersie?.call(id) ?? id];
    final tracks = [for (final id in ids) catalog.track(id)];
    final lijst = shieldLijst(
      trackIds: ids,
      tracks: tracks,
      adres: (id, t) => 'http://$base:$port/stream/$id.${t.ext}?token=$token',
      opgave: luidheidOpgave,
    );
    final urls = lijst.urls;
    if (urls.isEmpty) throw StateError('none of those tracks are in the library');

    final first = tracks[index.clamp(0, tracks.length - 1)];
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('http://${shield.host}:${ShieldTarget.port}/play'));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      // Same reason as the SOAP calls: the Shield's receiver reads Content-Length to know how
      // much body to expect, and a chunked request would arrive as an empty one.
      final payload = utf8.encode(jsonEncode({
        'streamUrls': urls,
        'index': index.clamp(0, urls.length - 1),
        'title': first?.title ?? '',
        'artist': first?.artist ?? '',
        'album': first?.album ?? '',
        // Parallel aan streamUrls; een oudere ontvanger negeert hem.
        if (lijst.luidheid.any((o) => o != null)) 'luidheid': lijst.luidheid,
      }));
      request.contentLength = payload.length;
      request.add(payload);
      final response = await request.close().timeout(const Duration(seconds: 8));
      await response.drain<void>();
      if (response.statusCode != 200) {
        throw StateError('de Shield weigerde het (HTTP ${response.statusCode})');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _openCurrent(_Session session) async {
    final anker = session.queue.elementAtOrNull(session.index);
    // De versie die voor dit nummer speelt (versies.dart): de rij houdt het nummer zelf, alleen het adres verandert.
    final id = anker == null ? null : _speelId(session, session.index, anker);
    final track = id == null ? null : catalog.track(id);
    if (id == null || track == null) return;
    // Een nieuw nummer op de speaker: meteen in de zonelijst.
    if (session.zagIndex != session.index) _zag(session, positie: Duration.zero);
    // En wie meespeelt, wacht op het begin ervan.
    _meldStil(session, 0);

    // Stamped BEFORE the SOAP calls, not after. Opening a track is three round trips of up to eight
    // seconds each, and until this line ran the timestamp still described the PREVIOUS track — so
    // the five-second tick arriving mid-open found the grace period long expired, asked a renderer
    // that had not started yet, was told STOPPED, and advanced again. The track being opened was
    // skipped without a sound. It is set again after the calls land, so the grace period is measured
    // from when the speaker actually got the track.
    session.startedAt = DateTime.now();

    final url = await _streamUrlFor(
        id, track.ext, session.renderer, track.sampleRate, track.bitsPerSample);
    final hoes = await _artUrlFor(id, session.renderer);
    Future<void> open() => _voor(session.renderer).playUrl(
          session.renderer,
          url,
          title: track.title,
          artist: track.artist,
          album: track.album,
          mime: mimeForExt(track.ext),
          artUrl: hoes,
          duration: track.duration,
        );
    try {
      await open();
    } catch (e) {
      // Eén keer opnieuw, na een tel. Saber, 22-10-2026, over de KEF: "bij de eerste keer heeft hij een HTTP fout …
      // bij de 2de keer pas ging het" — de tweede tik deed precies dit. Opnieuw openen is onschuldig: dezelfde url,
      // en een speaker die de eerste toch nam, begint hem gewoon opnieuw.
      _log?.line('openen op ${session.renderer.name} mislukte ($e) — over ${kOpnieuwOpenen.inMilliseconds} ms nog eens');
      await Future<void>.delayed(kOpnieuwOpenen);
      if (!identical(_sessies[session.renderer.id], session)) throw StateError('intussen iets anders gekozen');
      await open();
    }
    session.startedAt = DateTime.now();
    session.currentUrl = url;
    session.nextUrl = null;
    // Een nieuw nummer begint weer bij nul, dus het ijkpunt voor de terugval ook. Zou dit blijven staan,
    // dan zou de vorige lengte de eerstvolgende meting al als "teruggevallen" laten tellen.
    session.hoogstePositie = Duration.zero;
    _log?.line('open idx=${session.index}/${session.queue.length} ${_naam(id)}  (${_idVanUrl(url)})');

    // Hand the renderer the next one straight away, so the gap between two songs is the
    // speaker's own and not a round trip through here.
    await _armNext(session);
  }

  /// Geef de speaker alvast het nummer ná het huidige.
  ///
  /// De URL wordt bewaard, want dit is precies wat de speaker straks zelf gaat spelen zonder het te
  /// melden. Hem terugzien in TrackURI is NODIG om de overgang te zien, maar niet genoeg: een Sonos
  /// meldt hem al zodra hij hem ontvangt. Wat de overgang bewijst staat in [_echtGewisseld].
  Future<void> _armNext(_Session session) async {
    final volgend = session.queue.elementAtOrNull(session.index + 1);
    final nextId = volgend == null ? null : _speelId(session, session.index + 1, volgend);
    final nextTrack = nextId == null ? null : catalog.track(nextId);
    if (nextId == null || nextTrack == null) return;
    final nextUrl = await _streamUrlFor(
        nextId, nextTrack.ext, session.renderer, nextTrack.sampleRate, nextTrack.bitsPerSample);
    await _voor(session.renderer).setNextUrl(
      session.renderer,
      nextUrl,
      title: nextTrack.title,
      artist: nextTrack.artist,
      album: nextTrack.album,
      mime: mimeForExt(nextTrack.ext),
      duration: nextTrack.duration,
    );
    session.nextUrl = nextUrl;
    _log?.line('    volgende meegegeven: ${_naam(nextId)}  (${_idVanUrl(nextUrl)})');
  }

  /// Een andere volgorde voor wat er nog komt, zonder het lopende nummer aan te raken.
  ///
  /// Hiervoor bestond alleen [play], en die opent het huidige nummer opnieuw -- dus druk je tijdens het
  /// casten op shuffle, dan zou het liedje van voren af aan beginnen. Zonder deze weg deed de app iets
  /// ergers: ze schudde haar EIGEN lijst en liet die van de speaker staan. De index die de speaker
  /// terugmeldde wees daarna in twee verschillende lijsten, en dan toont het scherm een ander album dan
  /// er klinkt -- zonder dat er iets hapert of een melding verschijnt.
  ///
  /// De aanroeper zet het spelende nummer op [index]; dat is wat de volgorde hier en daar gelijk houdt.
  Future<void> requeue(String deviceId, List<String> trackIds, int index) async {
    final session = _sessies[deviceId];
    if (session == null || trackIds.isEmpty) return;
    session.queue = List.of(trackIds);
    // Waar staat het nummer dat NU klinkt in de nieuwe lijst? Dat is de index -- ongeacht wat de
    // aanroeper meestuurt. De speaker speelt door, dus de boekhouding hoort zich naar het geluid te
    // voegen en niet andersom. Zo kan één verkeerd gerekende index aan de andere kant hier geen
    // scheefstand meer veroorzaken, en als hij tóch afwijkt staat dat in het logboek.
    final huidig = _idVanUrl(session.currentUrl);
    final plek = huidig == null ? -1 : trackIds.indexOf(huidig);
    session.index = plek >= 0 ? plek : index.clamp(0, trackIds.length - 1);
    session.nextUrl = null;
    _log?.line('wachtrij vervangen: ${trackIds.length} nummers, nu op ${session.index} '
        '${_naam(session.queue.elementAtOrNull(session.index))}'
        '${plek >= 0 && plek != index ? '  (aanroeper zei $index)' : ''}'
        '${plek < 0 ? '  (het spelende nummer zit niet in de nieuwe lijst)' : ''}');
    await _armNext(session);
  }

  /// Is de speaker zelf doorgeschoven naar het nummer dat we hem alvast meegaven?
  ///
  /// De naadloze overgang van SetNextAVTransportURI is onzichtbaar in de transportstatus: PLAYING
  /// blijft PLAYING. Wat wél verandert is TrackURI. Zodra die gelijk is aan de URL die we als "volgende"
  /// hebben doorgegeven, weten we dat de speaker een nummer verder is en verhogen we de index -- en
  /// geven we meteen het nummer daarna mee, zodat de keten niet na twee liedjes ophoudt.
  ///
  /// Dit vervangt de STOPPED-weg niet: een speaker die de volgende-URL niet ondersteunt stopt wél, en
  /// dan is [_maybeAdvance] nog steeds wat de wachtrij doorzet.
  Future<bool> _followedRenderer(_Session session, String? trackUri, Duration? positie) async {
    // Eerst onthouden, en met de waarde van VOOR deze meting verder rekenen -- anders is de terugval
    // die we zoeken al weggeschreven voordat we hem konden zien.
    final top = session.hoogstePositie;
    if (positie != null && positie > top) session.hoogstePositie = positie;
    if (trackUri == null) return false;
    // Niet binnen de genadeperiode na het openen van een nummer, en dat is niet overdreven
    // voorzichtigheid maar een gemeten fout. Sonos neemt de "volgende"-URL op in zijn EIGEN wachtrij en
    // meldt hem daarna al in TrackURI, terwijl hij nog aan het huidige nummer bezig is. Eén druk op
    // volgende gaf daardoor:
    //
    //     16:09:02  index=4  pos=1s
    //     16:09:04  index=5  pos=1s
    //
    // De positie die dóórloopt in plaats van terug naar nul te springen verraadt het: er wisselde geen
    // nummer, alleen de boekhouding schoof op. Een ECHTE doorschuiving komt altijd aan het eind van een
    // nummer en dus ruim na deze periode, dus dit kost de goede kant niets.
    if (DateTime.now().difference(session.startedAt) < startGrace) return false;
    final volgende = session.nextUrl;
    if (volgende == null || trackUri != volgende) return false;
    if (session.index + 1 >= session.queue.length) return false;
    if (!_echtGewisseld(session, positie, top)) return false;
    _log?.line('volgt speaker: ${session.index} → ${session.index + 1}  '
        '${_naam(session.queue.elementAtOrNull(session.index + 1))}');
    session.index++;
    session.startedAt = DateTime.now();
    session.currentUrl = volgende;
    session.nextUrl = null;
    session.hoogstePositie = Duration.zero;
    // Wat de klok weet, hoort bij het vorige nummer: zonder dit noemde het anker even het nieuwe nummer met
    // de plek van het oude (bijna aan het eind), en spoelde wie meespeelt daarheen.
    session.klok?.verstoord();
    _zag(session, positie: Duration.zero);
    // Alleen de VOLGENDE doorgeven, niet opnieuw openen: de speaker speelt dit nummer al, en er
    // opnieuw een URL op zetten zou hem vanaf nul laten beginnen.
    try {
      await _armNext(session);
    } catch (_) {/* dan stopt de speaker na dit nummer en pakt _maybeAdvance het op */}
    return true;
  }

  /// Is de MUZIEK gewisseld, of alleen de boekhouding van de speaker?
  ///
  /// Dit is de vraag waar het op stukliep. Een Sonos zet de volgende-URL in zijn eigen wachtrij en meldt
  /// hem daarna in TrackURI terwijl het huidige nummer gewoon doorspeelt. "TrackURI is de volgende" was
  /// dus geen bewijs van een overgang maar van een ONTVANGST, en die komt seconden na de start. De
  /// genadeperiode van acht seconden stelde dat alleen maar uit: daarna klopte de voorwaarde nog steeds,
  /// de index schoof op, de app gaf meteen het nummer dáárna mee -- en acht seconden later gebeurde
  /// hetzelfde. Zo wandelde het scherm door de wachtrij terwijl er één nummer speelde. Dat is wat "ik
  /// hoor de Backstreet Boys maar zie Michael Jackson" was.
  ///
  /// Wat een overgang wél verraadt is de positie: die valt terug naar nul. Zolang de klok van de speaker
  /// dóórloopt, speelt hetzelfde nummer nog -- ongeacht welke URI hij noemt.
  bool _echtGewisseld(_Session session, Duration? positie, Duration top) {
    final oordeel = muziekIsGewisseld(
      top: top,
      positie: positie,
      gespeeld: DateTime.now().difference(session.startedAt),
      lengte: catalog.track(session.queue.elementAtOrNull(session.index) ?? '')?.duration,
    );
    if (!oordeel.ja) {
      _zie('nog niet gewisseld: ${oordeel.reden} -- terwijl de speaker de volgende URI al meldt');
      return false;
    }
    _log?.line('wissel gezien: ${oordeel.reden}');
    return true;
  }

  static String _sec(Duration d) => '${d.inSeconds}s';

  /// Hoe een nummer in het logboek heet.
  String _naam(String? id) {
    if (id == null) return '(niets)';
    final t = catalog.track(id);
    return t == null ? id : '${t.artist} - ${t.title}';
  }

  /// De id uit een stream-URL, want de hele URL is drie regels en zegt niet meer.
  String? _idVanUrl(String? url) {
    if (url == null) return null;
    final m = RegExp(r'/stream/([^/.?]+)').firstMatch(url);
    return m?.group(1);
  }

  String _laatsteRegel = '';
  DateTime _laatstGezien = DateTime.fromMillisecondsSinceEpoch(0);

  /// Een waarneming die zichzelf elke twee seconden herhaalt, hooguit twee keer per minuut opschrijven.
  ///
  /// De cijfers eruit gehaald om te vergelijken: "top 12s, nu 12s" en "top 14s, nu 14s" zijn dezelfde
  /// waarneming en horen niet allebei in het logboek. Een gebeurtenis -- een wissel, een opdracht, een
  /// nieuw nummer -- gaat langs deze rem heen, want die is per definitie nieuw.
  void _zie(String regel) {
    final kern = regel.replaceAll(RegExp(r'\d+'), '#');
    final nu = DateTime.now();
    if (kern == _laatsteRegel && nu.difference(_laatstGezien) < const Duration(seconds: 30)) return;
    _laatsteRegel = kern;
    _laatstGezien = nu;
    _log?.line(regel);
  }

  /// The URL to hand the speaker — converted first when the speaker cannot take the original.
  ///
  /// **Twee plafonds, niet één.** Dit keek alleen naar de bemonsteringsfrequentie, en dat is de helft
  /// van het verhaal. Gemeld op een KEF LS50 Wireless II: 32 bit / 384 kHz bleef stil, terwijl die
  /// speaker over het netwerk tot 24 bit / 384 kHz gaat. De frequentie was dus prima; de bitdiepte
  /// niet. Zie [Renderer.maxBitDepth].
  Future<String> _streamUrlFor(
      String id, String ext, Renderer renderer, int sampleRate, int bits) async {
    final base = await _adresVoor(renderer.host);
    final ceiling = renderer.maxSampleRate;
    final bitPlafond = renderer.maxBitDepth;
    // Sonos stops at 48 kHz and SKIPS anything higher — no error, no sound, just nothing. Send
    // it through the converter rather than let a hi-res album play as silence. Een te diepe plaat
    // gedraagt zich net zo: geen fout, geen geluid.
    final grens = castGrenzen(
        sampleRate: sampleRate,
        bits: bits,
        maxSampleRate: ceiling,
        maxBitDepth: bitPlafond);
    final teDiep = grens.bits != bits;
    if (grens.omzetten) {
      if (_transcoder.available) {
        probleem = null;
        // Beide grenzen gaan mee, ook als er maar één overschreden wordt: de omzetter moet weten wat
        // hij mag laten staan.
        // `cast=1` zegt de server WAARVOOR er omgezet wordt. Een speaker krijgt een weggooikopie en
        // wil hem snel; een gekoppeld toestel wil hem klein, want die bytes gaan over iemands
        // databundel. Zie [Omzetrecept] in transcode.dart.
        return 'http://$base:$port/stream/$id.flac'
            '?token=$token&maxRate=${grens.rate}&maxBits=${grens.bits}&cast=1';
      }
      // Hier ging het mis en zei niemand iets. Een Sonos slaat alles boven 48 kHz over zonder
      // foutmelding, dus zonder omzetter stuurden we een bestand waarvan we wisten dat het stil
      // zou blijven. Nu wordt het gezegd — dit is de enige plek die beide helften kent: wat de
      // plaat is, en dat er niets is om hem mee te verlagen.
      probleem = teDiep
          ? 'Deze speaker gaat tot $bitPlafond bit en dit nummer is $bits bit. Zonder ffmpeg op de '
              'pc kan ik het niet omzetten, en dan blijft de speaker stil.'
          : 'Deze speaker gaat tot ${ceiling ~/ 1000} kHz en dit nummer is '
              '${(sampleRate / 1000).round()} kHz. Zonder ffmpeg op de pc kan ik het niet omzetten, '
              'en dan blijft de speaker stil.';
      _log?.line('GEEN OMZETTER: ${bits}bit/${sampleRate}Hz tegen '
          '${bitPlafond}bit/${ceiling}Hz en ffmpeg ontbreekt — $id');
    } else {
      probleem = null;
    }
    return 'http://$base:$port/stream/$id.$ext?token=$token';
  }

  Future<String?> _artUrlFor(String id, Renderer renderer) async {
    final track = catalog.track(id);
    if (track == null) return null;
    final snapshot = catalog.snapshot();
    final dto = snapshot.catalog.tracks.where((t) => t.id == id).firstOrNull;
    if (dto?.artworkRef == null) return null;
    final base = await _adresVoor(renderer.host);
    return 'http://$base:$port/art/${dto!.artworkRef}?token=$token';
  }

  /// True while an advance is in flight, so the five-second tick cannot start a second one.
  ///
  /// Every step of an advance is slow — one state query plus three more round trips to open the next
  /// track, each allowed eight seconds — and the timer kept firing straight through it. Two overlapping
  /// advances each move the index, so the queue walks forward faster than the speaker plays it.
  /// Hoe lang een net geopend nummer met rust wordt gelaten voordat de speaker geloofd wordt.
  ///
  /// Eén constante voor beide vragen die erop leunen -- "is hij gestopt?" en "is hij doorgeschoven?" --
  /// want ze beschermen tegen hetzelfde: een renderer die de eerste seconden nog niets zinnigs meldt.
  /// Een Sonos zegt STOPPED terwijl hij de eerste bytes ophaalt, en meldt de volgende-URL al in
  /// TrackURI terwijl hij nog aan het huidige nummer bezig is. Twee keer uitgeschreven zouden ze
  /// uiteen gaan lopen.
  /// Hoe lang na het openen van een nummer een "STOPPED" of een nieuwe TrackURI niet geloofd wordt. Een
  /// toets zet hem op nul.
  final Duration startGrace;

  /// Move to the next track once the speaker says it has finished.
  Future<void> _maybeAdvance(_Session session) async {
    if (session.advancing) return;
    // Een sessie die intussen vervangen of gesloten is, schuift niets meer door.
    if (!identical(_sessies[session.renderer.id], session)) return;
    // Waar de rij nu staat, op schijf als dat veranderde (volgende, vorige, doorgeschoven). Zie [herstelSessies].
    _bewaarSessies();
    // Om de zes tikken (een halve minuut) het volume: dat verandert zelden vanzelf.
    if (++session.tikken % 6 == 0) unawaited(_haalVolume(session));
    // Give the renderer a moment after a start before believing "STOPPED" — a Sonos reports
    // exactly that for a second or two while it fetches the first bytes.
    if (DateTime.now().difference(session.startedAt) < startGrace) return;

    session.advancing = true;
    try {
      // Eerst: is de speaker zelf al doorgeschoven? Dan is er niets te doen behalve bijhouden waar hij
      // is. Deze vraag gaat vóór de transportstatus, want in dat geval staat die nog op PLAYING en zou
      // de rest van deze functie niets doen terwijl de index achterloopt.
      final pos = await _voor(session.renderer).positionInfo(session.renderer).catchError((_) => null);
      if (pos != null) _zag(session, positie: pos.position, duur: pos.duration);
      if (await _followedRenderer(session, pos?.trackUri, pos?.position)) return;

      final state = await _voor(session.renderer).transportState(session.renderer);
      if (state != null) _zag(session, speelt: state.isPlaying);
      _zie('kijk: ${state?.state ?? '?'} pos=${_sec(pos?.position ?? Duration.zero)} '
          'top=${_sec(session.hoogstePositie)} idx=${session.index}/${session.queue.length} '
          'uri=${_idVanUrl(pos?.trackUri) ?? '-'} nu=${_idVanUrl(session.currentUrl) ?? '-'} '
          'volgende=${_idVanUrl(session.nextUrl) ?? '-'}');
      if (state == null || !state.isStopped) return;
      // Tussendoor ([tussendoor]): de kopie is uit, en dan wacht hij op je keuze — niet sluiten, niet doorschuiven.
      if (_tussendoor.containsKey(session.renderer.id)) {
        _zag(session, speelt: false);
        return;
      }
      if (session.index + 1 >= session.queue.length) {
        if (session.radio != null) {
          // Een radio houdt open: de radio vult de rij aan ([voegToe]), en dan speelt het volgende meteen.
          if (!session.droog) {
            session.droog = true;
            _log?.line('radio droog op ${session.renderer.name}');
            _zag(session, speelt: false);
            _meldRadio(session);
          }
          return;
        }
        _meldStil(session, session.positie?.inMilliseconds ?? 0);
        _sluit(session);
        return;
      }
      session.index++;
      try {
        await _openCurrent(session);
      } catch (e) {
        // The index had already moved, and the timer throws the error away — so a renderer that
        // refuses the track (a busy Sonos answers "Transition not available" with an HTTP 500) lost
        // that song silently and the next tick took the one after it. Put the queue back where it
        // was and let the next tick try the same track again.
        session.index--;
        session.startedAt = DateTime.now();
        debugPrint('cast: kon ${session.queue.elementAtOrNull(session.index + 1)} niet openen: $e');
      }
    } finally {
      session.advancing = false;
    }
  }

  Future<void> control(String deviceId, String action, {int? value}) async {
    final shield = _shields.where((s) => s.id == deviceId).firstOrNull;
    if (shield != null) {
      if (action == 'stop') await _postShield(shield, '/stop');
      return;
    }
    final renderer = await _renderer(deviceId);
    final sessie = _sessies[renderer.id];
    _log?.line('opdracht $action${value == null ? '' : ' $value'}  '
        '(idx=${sessie?.index ?? -1})');
    if (sessie != null && (action == 'next' || action == 'previous' || action == 'stop')) _zonderTussendoor(sessie);
    switch (action) {
      case 'play':
        await _voor(renderer).play(renderer);
        sessie?.klok?.verstoord();
      case 'pause':
        final plek = sessie?.klok?.plekNu;
        await _voor(renderer).pause(renderer);
        if (sessie != null) _meldStil(sessie, plek?.positieMs ?? sessie.positie?.inMilliseconds ?? 0);
      case 'stop':
        if (sessie != null) {
          _meldStil(sessie, sessie.klok?.plekNu?.positieMs ?? 0);
          _sluit(sessie);
        }
        await _voor(renderer).stop(renderer);
      case 'next':
        if (sessie != null && sessie.index + 1 < sessie.queue.length) {
          sessie.index++;
          await _openCurrent(sessie);
        } else if (sessie != null && sessie.radio != null) {
          // Het laatste nummer van een radio: de radio moet nu iets nieuws geven ([wilVerder]).
          _meldRadio(sessie, wilVerder: true);
        }
      case 'previous':
        if (sessie != null && sessie.index > 0) {
          sessie.index--;
          await _openCurrent(sessie);
        }
      case 'volume':
        if (_groepVan(renderer.id) != null) {
          await _upnp.zetGroepsvolume(renderer, value ?? 50);
        } else {
          await _voor(renderer).setVolume(renderer, value ?? 50);
        }
        if (sessie != null) {
          sessie.volume = value ?? 50;
          bijStand?.call();
        }
      case 'seek':
        // Seconds on the wire rather than a formatted time: the phone has a slider, not a clock,
        // and the H:MM:SS the renderer wants is upnp.dart's business.
        //
        // Het ijkpunt voor de terugval verzetten, want anders is achteruit slepen niet te onderscheiden
        // van een nummer dat afliep: allebei valt de positie terug. Zo verzet slepen de meetlat mee.
        sessie?.hoogstePositie = Duration(seconds: value ?? 0);
        await _voor(renderer).seek(renderer, Duration(seconds: value ?? 0));
        if (sessie != null) _meldStil(sessie, (value ?? 0) * 1000);
      default:
        throw ArgumentError('unknown action: $action');
    }
  }

  /// What the speaker is doing, for a device that is holding the remote.
  ///
  /// Everything here is asked of the SPEAKER. A phone that is only steering does not decode the
  /// audio and cannot know the position; the alternative was a bar that crawled along on a guess,
  /// which is a lie you can sit and watch.
  ///
  /// Every field is optional on purpose. A renderer that answers some questions and not others is
  /// ordinary, and "no volume" must not cost you the play button.
  /// [withVolume] because this is polled while a bar moves on screen, and an embedded UPnP stack is
  /// not a web server. Volume almost never changes on its own, so asking for it every two seconds
  /// is a third more traffic to the speaker for an answer that is nearly always the same one.
  Future<Map<String, dynamic>> status(String deviceId, {bool withVolume = false}) async {
    final out = <String, dynamic>{'casting': false, if (probleem != null) 'probleem': probleem};
    // A Shield runs our own receiver and reports through the shared state, not through UPnP.
    if (_shields.any((s) => s.id == deviceId)) return out;

    final Renderer renderer;
    try {
      renderer = await _renderer(deviceId);
    } catch (_) {
      return out; // gone from the network; the caller shows its own last known state
    }
    final session = _sessies[renderer.id];
    out['casting'] = session != null;
    // Alle drie tegelijk gestart en pas daarna afgewacht: drie ronden naar een embedded stack, één na
    // de ander, is bijna een seconde — en dit wordt gepolst terwijl iemand naar een voortgangsbalk kijkt.
    //
    // Bewust drie losse futures en geen Future.wait met een lijst. Die geeft een List<Object?> terug, en
    // dan is elk element een `as`-cast die de compiler niet kan nakijken. Precies dat ging mis toen
    // positionInfo er een veld bij kreeg: de cast bleef op het oude record staan, de analyzer zag niets,
    // en élke statusvraag over een échte speaker klapte met een 500. De app las dat als "niet
    // bereikbaar", en dan vallen volgende en vorige dood terwijl de muziek doorloopt. Zo geschreven
    // klaagt de compiler de volgende keer wél.
    final bediening = _voor(renderer);
    final posF = bediening.positionInfo(renderer).catchError((_) => null);
    final stateF = bediening.transportState(renderer).catchError((_) => null);
    final volF = withVolume ? bediening.getVolume(renderer).catchError((_) => null) : null;
    final pos = await posF;
    final state = await stateF;
    final volume = volF == null ? null : await volF;
    if (pos != null) {
      // Ontbreekt de klok, dan blijft het veld weg in plaats van nul te worden -- de telefoon leest een
      // ontbrekend veld als "onbekend" en een nul als "terug bij het begin".
      final p = pos.position;
      if (p != null) out['positionMs'] = p.inMilliseconds;
      out['durationMs'] = pos.duration.inMilliseconds;
    }
    if (state != null) out['playing'] = state.isPlaying;
    if (volume != null) out['volume'] = volume;

    // Ook hier kijken of de speaker zelf is doorgeschoven, en niet alleen in de tijdklok van vijf
    // seconden. De positie is net al opgehaald, dus dit kost geen ronde extra -- en een telefoon polst
    // elke twee seconden. Gemeten op de KEF: de positie klapte van 209 naar 1 seconde terwijl de index
    // nog op het vorige nummer stond; die achterstand is nu twee tellen in plaats van vijf.
    //
    // Het antwoord wordt NA deze vraag samengesteld: eerst bijwerken, dan vertellen. Andersom zou deze
    // poll nog de oude index melden en pas de volgende de nieuwe.
    if (session != null) await _followGuarded(session, pos?.trackUri, pos?.position);
    final nu = _sessies[renderer.id];
    if (nu != null) {
      _zag(nu, positie: pos?.position, duur: pos?.duration, speelt: state?.isPlaying);
      out['index'] = nu.index;
      out['queueLength'] = nu.queue.length;
      final tid = nu.queue.elementAtOrNull(nu.index);
      out['trackId'] = tid;

      // Wat de speaker niet weet, weet de bibliotheek wel.
      //
      // Een Sonos geeft geen tracklengte terug -- TrackDuration blijft leeg of nul -- en zonder lengte
      // heeft de voortgangsbalk geen eindpunt en valt er niet in te slepen. Gemeten naast elkaar: de
      // KEF meldt hem wel, de Move niet. Dat is geen fout van de app maar wel iets wat de app kan
      // oplossen, want dit is een nummer van deze pc en zijn lengte staat in de catalogus.
      //
      // Alleen INVULLEN wat ontbreekt, nooit overschrijven. Wat de speaker zelf zegt gaat over het
      // bestand zoals hij het ontvangt, en dat kan korter zijn dan het origineel: een hi-res album gaat
      // voor een Sonos door de omzetter heen.
      if (((out['durationMs'] as int?) ?? 0) <= 0) {
        final lengte = tid == null ? null : catalog.track(tid)?.duration;
        if (lengte != null && lengte > Duration.zero) out['durationMs'] = lengte.inMilliseconds;
      }
    }
    return out;
  }

  /// [_followedRenderer] met hetzelfde slot als de tijdklok ervoor.
  ///
  /// Nodig omdat de status door meerdere toestellen tegelijk gepolst wordt: twee overlappende
  /// doorschuivingen verhogen allebei de index en dan loopt de wachtrij sneller dan de speaker speelt --
  /// exact de fout die de tijdklok eerder maakte en waarvoor [_Session.advancing] bestaat (per speaker).
  Future<void> _followGuarded(_Session session, String? trackUri, Duration? positie) async {
    // Geen `trackUri == null` meer als afslag hierboven: de positie moet óók onthouden worden als de
    // speaker even geen URI meldt, anders mist de terugval straks zijn ijkpunt.
    if (session.advancing) return;
    session.advancing = true;
    try {
      await _followedRenderer(session, trackUri, positie);
    } catch (_) {/* een mislukte doorschuiving mag geen statusvraag laten klappen */} finally {
      session.advancing = false;
    }
  }

  Future<void> _postShield(ShieldTarget shield, String path) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('http://${shield.host}:${ShieldTarget.port}$path'));
      final response = await request.close().timeout(const Duration(seconds: 5));
      await response.drain<void>();
    } catch (e) {
      debugPrint('shield $path failed: $e');
    } finally {
      client.close(force: true);
    }
  }

  /// De naam van elke speaker die ooit gevonden werd — ook als hij nu weg is, voor een melding die zegt wélke.
  final Map<String, String> _namen = {};

  Future<Renderer> _renderer(String id) async {
    final known = _renderers[id];
    if (known != null) return known;
    await devices();
    final found = _renderers[id];
    // Met de naam (24-10-2026: de Sonos Move sliep, en de melding zei "Sonos Amp antwoordt niet").
    if (found == null) throw StateError('${_namen[id] ?? 'Die speaker'} is niet (meer) op het netwerk — staat hij aan?');
    return found;
  }

  /// Voor een toets: deze speakers kent hij al (zonder op het netwerk te zoeken).
  @visibleForTesting
  void kenSpeakersVoorToets(List<Renderer> r) => _renderers = {for (final x in r) x.id: x};

  /// Voor een toets: met welke instellingen de klok van speaker [id] rekent (zie `speaker_klok.dart`).
  @visibleForTesting
  ({int houdMs, int korrelMs, bool gericht})? klokProfielVoorToets(String id) {
    final k = _sessies[id]?.klok?.schatting;
    return k == null ? null : (houdMs: k.houdMs, korrelMs: k.korrelMs, gericht: k.gericht);
  }

  /// Voor een toets: wat de tijdklok van vijf seconden doet, nu meteen, voor elke speaker.
  @visibleForTesting
  Future<void> tikVoorToets() async {
    for (final s in _sessies.values.toList()) {
      await _maybeAdvance(s);
    }
  }

  void dispose() {
    _kef.sluit();
    unawaited(_radioGebeurtenis.close());
    _zoeker?.cancel();
    _groepKijker?.cancel();
    for (final s in _sessies.values) {
      s.advance?.cancel();
      s.klok?.stop();
    }
    _sessies.clear();
  }
}

/// Wat een speaker speelde toen er tussendoor iets beluisterd werd ([CastManager.tussendoor]).
class _Tussendoor {
  _Tussendoor({required this.queue, required this.index, required this.positieMs, required this.speelde,
      required this.a, required this.b});
  final List<String> queue;
  final int index, positieMs;
  final bool speelde;
  final String a, b;
  bool opB = true;
}

class _Session {
  _Session({required this.renderer, required this.queue, required this.index, this.alsZone = false});

  final Renderer renderer;

  /// Gestart vanuit de zones: loopt naast de andere sessies door. Zie [CastManager.play].
  final bool alsZone;

  /// De tijdklok die het volgende nummer stuurt, en het slot ertegen dat twee doorschuivingen elkaar
  /// kruisen (vroeger één voor de hele castmanager; nu per speaker).
  Timer? advance;
  bool advancing = false;
  int tikken = 0;

  /// Het volume van de speaker (0–100), als hij het meldt.
  int? volume;

  /// Niet final: shuffle tijdens het casten geeft een andere volgorde voor wat er nog komt. Zie
  /// [CastManager.requeue].
  List<String> queue;
  int index;
  DateTime startedAt = DateTime.now();

  /// De URL's die deze speaker gekregen heeft voor het huidige en het volgende nummer.
  ///
  /// Nodig om te ZIEN dat de speaker zelf is doorgeschoven. De app geeft het volgende nummer alvast
  /// mee zodat er geen gat valt tussen twee liedjes, en dan gaat een Sonos van PLAYING naar PLAYING
  /// zonder ooit STOPPED te zeggen. Wie alleen op STOPPED let, loopt vanaf dat moment één nummer
  /// achter: de speaker speelt nummer 2, de app toont nummer 1, en "volgende" gaat naar het nummer dat
  /// al klinkt. Bij één album valt dat nauwelijks op, bij shuffle-all is elk nummer een ander album.
  String? currentUrl, nextUrl;

  /// De hoogste positie die op DIT nummer gezien is.
  ///
  /// Dit is wat een echte nummerwissel verraadt. Een speaker die van nummer wisselt begint opnieuw te
  /// tellen, dus de positie valt terug van bijna-de-hele-lengte naar nul. Zolang die terugval niet is
  /// gezien, klinkt hetzelfde nummer nog -- wat de speaker verder ook beweert.
  ///
  /// Het hoogste in plaats van het laatste, zodat één rare meting tussendoor niets kapotmaakt.
  Duration hoogstePositie = Duration.zero;

  /// Wat de speaker het laatst zei, en wanneer. Zie [CastManager.laatsteStand].
  bool? speelt;
  Duration? positie, duur;
  int? gezienOp;

  /// De index bij de laatste melding naar buiten: een nieuw nummer is ook iets nieuws.
  int zagIndex = -1;

  /// Samen spelen (stap 3.3): waar de speaker op de ms is ([SpeakerKlok]), zolang er toestellen meespelen.
  SpeakerKlok? klok;

  /// Wanneer de klok het laatst in cast.log stond, en met welke stand.
  String klokLogStand = '';
  int klokLogOp = 0;

  /// Hij gaat stilstaan op deze plek (ms) en de klok weet het nog niet: wat het anker dan zegt.
  int? stilVoorKlok;

  /// Net een breuk: wacht tot bekend is welk nummer er speelt. Zie [CastManager._naBreuk].
  bool wachtOpNummer = false;

  /// Nog aan het laden en spoelen (zie [CastManager.play] met `vanafMs`): nog geen anker.
  bool aanloop = false;

  /// Een radio van de pc (`speaker_radio.dart`): zijn naam. Null bij een gewone wachtrij.
  String? radio;

  /// Een radiosessie waarvan de rij op is: hij blijft open tot de radio aanvult ([CastManager.voegToe]).
  bool droog = false;

  /// Een versie die je tijdens het spelen koos (versies.dart, [CastManager.wisselVersie]): voor het nummer [anker] op plek
  /// [index] in de rij — een ander nummer speelt weer de versie die je voor de plaat of het nummer koos.
  ({int index, String anker, String id})? versie;
}

extension _ElementAtOrNull<E> on List<E> {
  E? elementAtOrNull(int index) => (index >= 0 && index < length) ? this[index] : null;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

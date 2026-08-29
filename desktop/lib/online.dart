import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'organize.dart';
import 'lossless_want.dart';
import 'quality.dart';
import 'radiovoorraad.dart' show kMaxWacht;
import 'rutracker.dart';
import 'search.dart';
import 'settings.dart';
import 'soulseek.dart';
import 'zoekladder.dart';
import 'torbox.dart';
import 'torznab.dart';
import 'torrentbestand.dart';
import 'aria2.dart';
import 'cue_knippen.dart';
import 'meldrem.dart';
import 'warm_log.dart';
import 'werkrij.dart';
import 'paths.dart';
import 'echtheid.dart';
import 'echtheid_meter.dart';
import 'echtheid_oordelen.dart';
import 'flac_tags.dart';
import 'torbox_stand.dart';
import 'vaste_keuze.dart';

/// De laatste map van een pad, of het nu met `/` of met `\` geschreven staat.
///
/// **Waarom dit geen detail is.** aria2 antwoordt met voorwaartse schuine strepen, ook op Windows:
/// `D:/Flac music 2024/DebridMusic Downloads/.dm-6f948bec/…`. Splitsen op `Platform.pathSeparator`
/// levert daar één stuk op — het hele pad — en dat werd vervolgens als mapnaam voor het bestand
/// gebruikt. Gemeten op 29-08-2026 stond er na een tweede download van hetzelfde nummer:
///
///     D__Flac music 2024_DebridMusic Downloads_.dm-6f948bec_Tears For Fears - Songs From The
///     Big Chair (Deluxe Edition) … - 03. Tears For Fears - Everybody Wants To Rule The World.flac
///
/// Een bestand van 29 MB met een naam waar niemand iets aan heeft, in de map waar de bibliotheek uit
/// leest.
String laatsteMap(String pad) {
  final delen = pad.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList();
  return delen.isEmpty ? '' : delen.last;
}

/// De KORTE map waarin aria2 mag werken, náást de doelmap in plaats van erin.
///
/// **Waarom dit een eigen functie is.** Windows kapt een pad op 260 tekens, en die grens haal je
/// sneller dan je denkt zodra een plaatnaam twee keer in hetzelfde pad staat. Dat gebeurde:
///
///     D:\Flac music 2024\DebridMusic Downloads\Tears For Fears - Songs From The Big Chair (Deluxe
///     Edition) (Deluxe) (1985 Pop Rock) [Flac 16-44]\Tears For Fears - Songs From The Big Chair
///     (Deluxe Edition) (Deluxe) (1985 Pop Rock) [Flac 16-44]\01. Tears For Fears - Shout.flac
///
/// 234 tekens, en de melding op het scherm was "File I/O error 3" — ERROR_PATH_NOT_FOUND, geen woord
/// over lengte. De doelmap heet al naar de plaat; aria2 maakt daarin nóg een map met diezelfde naam,
/// want zo heet de torrent. Dus laten we hem in `.dm-<8 tekens>` werken en verhuizen we de gekozen
/// nummers daarna. Zelfde schijf, dus dat verhuizen is een hernoeming.
String werkMapPad(Directory doelMap, String hash, String torrentNaam) {
  final kort = hash.length >= 8
      ? hash.substring(0, 8)
      : torrentNaam.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').padRight(8, 'x').substring(0, 8);
  return '${doelMap.parent.path}${Platform.pathSeparator}.dm-$kort';
}

/// Wat er terugkwam toen de app een bron zélf probeerde te pakken.
///
/// Het verschil tussen deze vier is het verschil tussen vier totaal andere adviezen: het lukte,
/// kies een andere treffer, zet aria2 erbij, of er valt hier niets te halen. Eén gedeelde `null`
/// maakte daar één spinner van die nergens over sprak.
enum LokaleBron { gelukt, geenZwerm, geenMotor, geenBron }

/// Wat er op het scherm hoort als niemand de torrent nog deelt.
///
/// **Waarom deze zin zo uitgebreid is.** De klacht was letterlijk: "Knaben heeft soms heel veel peers
/// maar wil niet downloaden". Die peers stáán er ook — op de zoeksite. Gemeten op 24-08-2026 met een
/// treffer die "18 seeders" meldde: vijfenzestig seconden lang nul verbindingen en nul bytes, óók
/// buiten de app om. De tellers van die sites komen uit hun eigen scrape en lopen maanden achter.
///
/// Wie dat niet weet gaat zijn eigen app, zijn eigen internet of zijn eigen instellingen zitten
/// wantrouwen — en dat is precies de avond die deze melding moet voorkomen.
const kGeenZwerm = 'Niemand deelt deze torrent op dit moment. De zoeksite meldt wel seeders, maar in '
    'dertig seconden reageerde er geen enkele — die tellers lopen vaak maanden achter. Kies een '
    'andere treffer; die met meer seeders bij een ANDERE bron doen het meestal wel.';

/// TorBox search + resolve + download, ported from the server's OnlineService.
class OnlineService {
  final AppSettings settings;
  final TorBox torbox;
  final RuTrackerService rutracker;

  /// De lokale torrentmotor. Eén per app: hij houdt één proces vast, en twee processen die dezelfde
  /// map vullen vechten om dezelfde bestanden.
  final Aria2 aria2 = Aria2();
  /// De zoekverdeler, met **dezelfde** [rutracker] erin als het veld hierboven.
  ///
  /// **Waarom dit een laat veld is en geen regel in de constructor.** Hier stonden TWEE
  /// `RuTrackerService(settings)`: één als veld, en één in de verdeler. Twee losse objecten met elk
  /// hun eigen geheugen.
  ///
  /// Dat is niet netjesheid maar de reden dat je niets te lezen kreeg. Het zoeken liep over het
  /// object in de verdeler en zette `lastError` daar; het scherm las `lastError` van het véld. Wat
  /// de app wist over waarom er niets binnenkwam — een verlopen sessie, Cloudflare, een pagina
  /// zonder rijen — stond dus in een object dat niemand ooit bekeek, en op het scherm bleef "Geen
  /// torrents gevonden." staan, punt. Alle meldingen die er speciaal voor bijgebouwd waren kwamen
  /// nergens aan.
  ///
  /// Dat het zoeken zélf wél werkte kwam doordat beide objecten hetzelfde `settings` lezen — een
  /// toevalligheid, geen ontwerp.
  ///
  /// Een gewone regel in de constructor kan niet: een initialisatielijst mag niet naar een ander
  /// veld wijzen. Een fabriek zou het ook oplossen, maar [RemoteOnlineService] erft hiervan met
  /// `super.settings`, en dat kan niet op een fabriek. Een laat veld mag het wel, en wordt pas
  /// gemaakt als iemand ernaar vraagt — op een telefoon, die alles aan de pc vraagt, dus nooit.
  late final SearchAggregator aggregator = SearchAggregator([
    ApibaySource(),
    BitSearchSource(),
    KnabenSource(),
    RuTrackerSource(rutracker),
    // Je eigen indexers, als je ze hebt. Leest de instellingen bij elke zoekopdracht opnieuw, zodat
    // een adres dat je net invulde meteen meedoet zonder de app te herstarten.
    TorznabSource(settings),
  ]);

  OnlineService(this.settings)
      : torbox = TorBox(() => settings.torboxToken),
        rutracker = RuTrackerService(settings);

  bool get torboxReady => torbox.hasKey;

  Future<List<SearchResult>> search(String query, {void Function(List<SearchResult>)? onPartial}) async {
    // Stream raw hits as each source finishes (fast perceived results); the ⚡Instant
    // cache marks are applied on the final pass below.
    final results = await aggregator.search(query, onPartial: onPartial);
    if (!torbox.hasKey) return results;
    // Mark instantly-cached results (top 40, batches of 20).
    final top = results.take(40).map((r) => r.hash.toLowerCase()).toList();
    final cached = <String>{};
    // Twee vragen náást elkaar in plaats van achter elkaar. Ze weten niets van elkaar, en met een
    // wachtklok van 15 seconden per stuk kostte het serieel afwerken tot een halve minuut ná het
    // moment dat alle bronnen hun resultaten al hadden liggen.
    final brokken = <List<String>>[
      for (var i = 0; i < top.length; i += 20) top.sublist(i, (i + 20).clamp(0, top.length)),
    ];
    for (final deel in await Future.wait(brokken.map(torbox.checkCached))) {
      cached.addAll(deel);
    }
    for (final r in results) {
      r.cached = cached.contains(r.hash.toLowerCase());
    }
    results.sort((a, b) {
      if (a.cached != b.cached) return a.cached ? -1 : 1;
      return b.seeders.compareTo(a.seeders);
    });
    return results;
  }

  Future<(int?, String)> _addOrFind(SearchResult r) async {
    // Eerst het BESTAND, als de bron er een heeft — en dat is niet netter, dat is het verschil
    // tussen wel en niet werken.
    //
    // Gemeten op 23-08-2026 met een RuTracker-vondst (Kai Tracid — Liquid Skies, 24/96 FLAC):
    //
    //     als magneet   : 2,5 uur "checking", size -1, seeds 0   -> nooit iets
    //     als .torrent  : na 12 s "downloading", 554 MB, seeds 1 -> 4% naar 61% in twee minuten
    //
    // Een magneet draagt alleen de infohash, dus moet wie hem oppakt de zwerm via DHT zien te
    // vinden. De zwerm van RuTracker hangt achter hun eigen announce, en die staat alleen IN het
    // torrentbestand.
    //
    // Het bestand gaat er meteen als eerste in, niet als reddingspoging achteraf: TorBox kijkt naar
    // de infohash, en staat er al een vastgelopen magneetpoging met dezelfde hash, dan antwoordt hij
    // "Found Cached Torrent" en krijg je die vastgelopen poging terug — bestand of niet.
    final redenen = <String>[];
    if (r.torrentUrl.isNotEmpty) {
      final bytes = await rutracker.haalTorrentBestand(r.torrentUrl);
      if (bytes == null || bytes.isEmpty) {
        redenen.add('het torrentbestand kwam niet binnen bij de bron (koekje verlopen?)');
      } else {
        final uitkomst = await torbox.addTorrentFile(bytes, '${r.hash}.torrent');
        final gevonden = await _uitTorboxAntwoord(uitkomst, r.hash);
        if (gevonden != null) return gevonden;
        // Ligt het aan TorBox zelf, dan heeft de magneet erachteraan geen zin: dat is nog eens
        // veertig seconden wachten op dezelfde stilte, waarna het scherm de verkeerde schuldige
        // aanwijst.
        if (uitkomst.storing) throw await _storingUitleg(uitkomst);
        redenen.add('bestand: ${uitkomst.reden}');
      }
      // Niet gelukt (geen sessie, of de bron gaf een pagina in plaats van een torrent)? Dan
      // alsnog de magneet: die werkt bij een torrent die wél in DHT zit.
    }
    // Open announce-adressen erbij als de magneet er geen heeft: anders moet TorBox de zwerm
    // uitsluitend via DHT zien te vinden, en dat is precies waar het bij een index als Knaben
    // misgaat — daar komt een kale `magnet:?xt=urn:btih:` uit. Zie `magneetMetAnnounce`.
    final uitkomst = await torbox.addMagnet(magneetMetAnnounce(r.magnet));
    final gevonden = await _uitTorboxAntwoord(uitkomst, r.hash);
    if (gevonden != null) return gevonden;
    if (uitkomst.storing) throw await _storingUitleg(uitkomst);
    redenen.add('magneet: ${uitkomst.reden}');
    throw redenen.isEmpty
        ? 'Kon torrent niet toevoegen'
        : 'TorBox nam deze bron niet aan — ${redenen.join('; ')}';
  }

  /// TorBox gaf iets terug dat niet over déze torrent gaat. Vraag hem of hij nog leeft, en zeg dan
  /// pas wat er aan de hand is.
  ///
  /// **Waarom die extra vraag het waard is.** Op 23-08-2026 stond er "Mislukt" bij een album dat in
  /// µTorrent tegelijk op 6 MB/s binnenkwam. Het lag aan TorBox — hun statuspagina meldde op dat
  /// moment "Some services are degraded — API" — maar het scherm gaf de gebruiker geen enkele
  /// aanleiding om dat te vermoeden, dus ging hij zijn eigen app en zijn eigen torrent wantrouwen.
  /// Eén korte vraag van tien seconden is genoeg om de schuldige bij naam te noemen.
  Future<String> _storingUitleg(TbToevoeging uitkomst) async {
    if (await torbox.leeft()) {
      return 'TorBox nam deze bron niet aan: ${uitkomst.reden}';
    }
    return 'TorBox zelf antwoordt op dit moment niet — hun API is verstoord. Het ligt niet aan deze '
        'torrent. Kijk op status.torbox.app en probeer het straks opnieuw.';
  }

  /// Het antwoord van TorBox op "voeg dit toe" uitpakken: (id, hash), of null als het niet lukte.
  Future<(int?, String)?> _uitTorboxAntwoord(TbToevoeging antwoord, String hashUitBron) async {
    final hash = (antwoord.hash != null && antwoord.hash!.isNotEmpty) ? antwoord.hash! : hashUitBron;
    final detail = antwoord.reden;
    if (hash.isEmpty) throw 'Torrent heeft geen infohash';
    if (antwoord.gelukt) return (antwoord.id, hash);
    if (detail.toLowerCase().contains('already')) {
      final item = (await torbox.listTorrents())
          .cast<TbTorrent?>()
          .firstWhere((t) => t?.hash?.toLowerCase() == hash.toLowerCase(), orElse: () => null);
      return (item?.id, hash);
    }
    return null;
  }

  /// Hoe lang er gewacht wordt vóór de volgende peiling, gegeven hoeveel er al verstreken is.
  ///
  /// Zuiver en apart, want dit is de rekensom die het verschil maakt tussen "meteen klaar" en "sta
  /// te wachten op niets", en het is het enige stuk van deze weg dat zonder TorBox na te meten is.
  ///
  /// Drie tempo's, en de reden staat in de getallen:
  ///
  /// - **de eerste 6 seconden: 400 ms.** Een gecachte torrent is er binnen een paar seconden. Hier
  ///   snel kijken kost twee of drie kleine verzoeken en scheelt de gebruiker de halve minuut die er
  ///   eerst stond.
  /// - **tot 45 seconden: 1,5 seconde.** De meeste niet-gecachte torrents met genoeg seeders landen
  ///   in dit venster.
  /// - **daarna: 5 seconden.** Nu is het een grote bron met weinig seeders. Vaker kijken maakt hem
  ///   niet sneller; het houdt alleen de lijn en de tekenlus bezig.
  static int tempoVoorPeiling(int verstrekenMs) {
    if (verstrekenMs < 6000) return 400;
    if (verstrekenMs < 45000) return 1500;
    return 5000;
  }

  Future<TbTorrent> _pollReady(int? id, String hash,
      {bool patient = false, void Function(double progress, String status)? onProgress}) async {
    // HET RITME LIEP DE VERKEERDE KANT OP. Het begon op twee seconden en werd elke ronde de helft
    // trager, tot tien. Precies in het venster waarin een gecachte of snelle torrent klaar komt
    // (vijf tot dertig seconden) zat de app dus het langst niks te doen: een bron die op t=12 klaar
    // was, werd pas op t=18 gezien. Dat is geen wachten op TorBox, dat is wachten op onszelf.
    //
    // Nu: snel beginnen, kort blijven zolang het ertoe doet, en pas ná een halve minuut rustiger
    // worden — want dán is het een grote torrent met weinig seeders en helpt vaker kijken niets.
    var delayMs = 400;
    var noProgress = 0;
    var readyNoAudio = 0;
    var verstreken = 0;
    // Big, low-seed torrents (a whole discography) take TorBox a long time to fetch from
    // few peers — be patient and, crucially, report progress so it's not a mystery spinner.
    final maxAttempts = patient ? 220 : 60;
    final stallTimeout = patient ? 90000 : 25000;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      // Eén torrent opvragen in plaats van je hele account. Zie [TorBox.listTorrents].
      final list = await torbox.listTorrents(id: id);
      final item = list.cast<TbTorrent?>().firstWhere(
          (t) => (id != null && t?.id == id) || (t?.hash?.toLowerCase() == hash.toLowerCase()),
          orElse: () => null);
      // **De waarheid doorgeven, niet alleen het percentage.** Deze regel gaf al een status mee, en
      // het venster gooide die weg voor een vaste zin over "weinig seeders" — op een torrent met er
      // veertig. Zie `torbox_stand.dart`.
      onProgress?.call(
        item?.progress ?? 0,
        torboxStand(
          gecacht: item?.cached ?? false,
          deel: item?.progress ?? 0,
          status: item?.status ?? 'toevoegen',
          seeds: item?.seeds ?? 0,
          grootte: item?.size ?? 0,
        ),
      );
      if (item == null) {
        noProgress += delayMs;
      } else if (item.isFailed) {
        throw 'Bron mislukt: ${item.status}';
      } else if (item.isReady && item.audio.isNotEmpty) {
        return item;
      } else if (item.isReady) {
        readyNoAudio += delayMs;
        if (readyNoAudio >= 18000) throw 'Geen afspeelbare audio in deze bron';
      } else {
        if (item.progress <= 0) {
          noProgress += delayMs;
        } else {
          noProgress = 0;
        }
      }
      if (noProgress >= stallTimeout) throw 'Bron loopt vast — geen voortgang';
      await Future.delayed(Duration(milliseconds: delayMs));
      verstreken += delayMs;
      delayMs = tempoVoorPeiling(verstreken);
    }
    throw 'Time-out bij voorbereiden van deze bron';
  }

  TbFile? _bestAudio(TbTorrent t) {
    final audio = t.audio;
    if (audio.isEmpty) return null;
    audio.sort((a, b) {
      final fa = a.isFlac ? 1 : 0, fb = b.isFlac ? 1 : 0;
      if (fa != fb) return fb - fa;
      return b.size.compareTo(a.size);
    });
    return audio.first;
  }

  List<TbFile> _sortedAudio(TbTorrent t) {
    final audio = t.audio;
    audio.sort((a, b) {
      final fa = a.isFlac ? 1 : 0, fb = b.isFlac ? 1 : 0;
      if (fa != fb) return fb - fa;
      return a.name.compareTo(b.name);
    });
    return audio;
  }

  /// Resolve the single best track of a result to a playable URL.
  Future<String> resolveStreamUrl(SearchResult r) async {
    if (!torbox.hasKey) throw 'Stel eerst je TorBox-sleutel in (Instellingen).';
    final (id, hash) = await _addOrFind(r);
    final item = await _pollReady(id, hash, patient: !r.cached);
    final best = _bestAudio(item);
    if (best == null) throw 'Geen audio in deze torrent';
    final url = await torbox.requestDownload(item.id, best.id);
    if (url == null) throw 'Lege download-URL';
    return url;
  }

  /// Resolve a recommended track (artist + title) to a playable URL, picking the file
  /// that actually matches [title] (so an album torrent doesn't play the wrong song).
  /// [instantOnly] true (Radio) = cached TorBox sources only, for speed; false (an
  /// explicit play) also tries un-cached sources (slower). Returns null if nothing matches.
  Future<String?> resolveRadio(String artist, String title, {bool instantOnly = true}) async {
    if (!torbox.hasKey) return null;
    final results = await search('$artist $title');
    if (results.isEmpty) return null;
    int score(SearchResult r) {
      final n = r.name.toLowerCase();
      var s = 0;
      if (_titleMatch(r.name, title)) s += 60;
      if (RegExp('flac', caseSensitive: false).hasMatch(n)) s += 10;
      if (r.size < 120 * 1000 * 1000) s += 20; // small => likely a single track, not an album
      return s + (r.seeders > 0 ? 3 : 0);
    }

    final top = (results.toList()..sort((a, b) => score(b) - score(a))).take(10).toList();
    // Directly cache-check these candidates — search() only flags the top 40 overall.
    Set<String> cachedSet = {};
    try {
      cachedSet = await torbox.checkCached(top.map((r) => r.hash.toLowerCase()).toList());
    } catch (_) {}
    bool isCached(SearchResult r) => r.cached || cachedSet.contains(r.hash.toLowerCase());
    final cached = top.where(isCached).toList();
    // Cached first; for an explicit play, fall back to un-cached (slower) sources too.
    final candidates = instantOnly ? cached : [...cached, ...top.where((r) => !isCached(r))];
    for (final r in candidates.take(instantOnly ? 3 : 4)) {
      try {
        final (item, files) = await resolveForDownload(r, null); // patient poll when not cached
        TbFile? pick;
        for (final f in files) {
          if (_titleMatch(f.name, title)) {
            pick = f;
            break;
          }
        }
        pick ??= files.length == 1 ? files.first : null; // single-track torrent
        if (pick == null) continue; // multi-track, no title match => avoid the wrong song
        final url = await torbox.requestDownload(item.id, pick.id);
        if (url != null) return url;
      } catch (_) {}
    }
    return null;
  }

  bool _titleMatch(String name, String title) {
    String n(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final t = n(title);
    return t.length >= 3 && n(name).contains(t);
  }

  /// De motor die deze bron gaat halen.
  ///
  /// `torbox` en `lokaal` zijn wat ze zeggen. `auto` is de afweging die de meeste mensen zouden
  /// maken als ze alle feiten hadden:
  ///
  ///  * staat het al bij TorBox in de cache, dan is dát meteen klaar en gaat er niets de zwerm in;
  ///  * staat het er niet, dan moet TorBox de hele torrent eerst zélf ophalen — precies waar het
  ///    traag wordt, en op 23-08-2026 waar het helemaal stilviel — dus doen we het zelf.
  ///
  /// Alleen met een `.torrent` in handen. Een kale magneet laten we aan TorBox: die moet de zwerm
  /// via DHT vinden, en dat is nu juist wat bij een tracker als RuTracker niet werkt.
  bool lokaalVoor(SearchResult r) => kiesLokaal(
        motor: settings.torrentMotor,
        heeftBron: r.torrentUrl.isNotEmpty || r.magnet.isNotEmpty,
        staatKlaarBijTorbox: r.cached,
        motorBeschikbaar: aria2.beschikbaar,
      );

  /// De regel zelf, los van waar de feiten vandaan komen — anders valt hij alleen te toetsen op een
  /// machine waar toevallig een aria2 staat, en dat is precies het soort regel dat ongemerkt kantelt.
  ///
  /// [heeftBron] telde eerst alleen een `.torrent`-bestand, en daarmee gold dit alleen voor
  /// RuTracker. Alles van Knaben en Pirate Bay — dus verreweg het meeste — viel terug op TorBox, ook
  /// wanneer de zwerm veertig seeders had. Een magneet kan hier gewoon mee: aria2 haalt de
  /// inhoudsopgave uit diezelfde zwerm.
  static bool kiesLokaal({
    required String motor,
    required bool heeftBron,
    required bool staatKlaarBijTorbox,
    required bool motorBeschikbaar,
  }) {
    if (!heeftBron || !motorBeschikbaar) return false;
    return switch (motor) {
      'torbox' => false,
      'lokaal' => true,
      _ => !staatKlaarBijTorbox,
    };
  }

  /// Het torrentbestand van deze bron, hoe hij ook binnenkomt.
  ///
  /// Twee wegen, want de bronnen verschillen: RuTracker geeft een `.torrent` af zodra je ingelogd
  /// bent, en Knaben en Pirate Bay geven alleen een magneet. Voor die tweede haalt aria2 in enkele
  /// seconden de inhoudsopgave uit de zwerm zelf.
  ///
  /// **Dit is de reparatie van "veel peers, en toch niets".** Een magneet zonder bestandslijst kon de
  /// app nergens anders heen brengen dan naar TorBox, en die moest dan de hele plaat eerst zelf
  /// binnenhalen — dat is de "Voorbereiden" die bleef staan terwijl Knaben veertig seeders toonde.
  /// De torrentbestanden die we in deze zitting al opgehaald hebben, op infohash.
  ///
  /// **Niet alleen voor de snelheid.** Bij een magneet haalt aria2 de inhoudsopgave uit de zwerm, en
  /// zo'n metadata-taak staat bij hem geregistreerd op dezelfde infohash als de echte download.
  /// Vraagt de app hem twee keer vlak na elkaar — en dat deed hij: één keer voor de nummerlijst en
  /// nog eens per gekozen nummer — dan botst de tweede op de eerste:
  ///
  ///     errorCode=12 InfoHash 6f948bec… is already registered
  ///
  /// Gemeten op 29-08-2026 met Tears For Fears: nummer 3 kwam binnen, nummer 1 viel om met die
  /// melding. Eén keer ophalen en onthouden lost het bij de wortel op, en scheelt bovendien twee
  /// gangen naar de zwerm.
  final Map<String, List<int>> _torrentCache = {};

  Future<({List<int>? bytes, LokaleBron stand})> _torrentBytes(SearchResult r) async {
    final sleutel = r.hash.toLowerCase();
    final bekend = sleutel.isEmpty ? null : _torrentCache[sleutel];
    if (bekend != null) return (bytes: bekend, stand: LokaleBron.gelukt);
    void onthoud(List<int> bytes) {
      if (sleutel.isEmpty) return;
      // Een handvol volstaat: het gaat om de paar torrents waar je op dit moment mee bezig bent, en
      // veertig kilobyte per stuk hoeft niet eindeloos mee te reizen.
      if (_torrentCache.length >= 20) _torrentCache.remove(_torrentCache.keys.first);
      _torrentCache[sleutel] = bytes;
    }

    if (r.torrentUrl.isNotEmpty) {
      final bytes = await rutracker.haalTorrentBestand(r.torrentUrl);
      if (bytes != null && bytes.isNotEmpty) {
        onthoud(bytes);
        return (bytes: bytes, stand: LokaleBron.gelukt);
      }
    }
    if (r.magnet.isEmpty) return (bytes: null, stand: LokaleBron.geenBron);
    final map = await Directory.systemTemp.createTemp('dm_meta_');
    try {
      if (!await aria2.start(downloadMap: map.path)) {
        return (bytes: null, stand: LokaleBron.geenMotor);
      }
      final bytes = await aria2.haalMetadata(r.magnet, map: map.path);
      if (bytes != null) onthoud(bytes);
      return bytes == null
          ? (bytes: null, stand: LokaleBron.geenZwerm)
          : (bytes: bytes, stand: LokaleBron.gelukt);
    } finally {
      await map.delete(recursive: true).catchError((_) => map);
    }
  }

  /// De nummerlijst uit het torrentbestand zelf, zonder iemand iets te hoeven vragen.
  ///
  /// Dit is het stuk dat de nummerkeuze van een halve minuut wachten naar een halve seconde brengt:
  /// wat erin zit staat IN het bestand, en dat hebben we al zodra RuTracker het heeft afgegeven.
  Future<(TbTorrent, List<TbFile>)?> _lokaleTracklist(SearchResult r) async {
    final (bytes: bytes, stand: stand) = await _torrentBytes(r);
    // Niemand thuis in de zwerm? Dan heeft doorschuiven naar TorBox geen enkele zin: die moet bij
    // exact dezelfde peers aankloppen. Gemeten op 24-08-2026 met een BitSearch-treffer die "18
    // seeders" meldde — vijfenzestig seconden lang nul verbindingen, nul bytes, ook op de kale
    // opdrachtregel. Precies zo'n torrent bleef bij TorBox uren op "Voorbereiden" staan.
    if (stand == LokaleBron.geenZwerm) throw kGeenZwerm;
    if (bytes == null || bytes.isEmpty) return null;
    final inhoud = TorrentInhoud.lees(bytes);
    if (inhoud == null) return null;

    final bestanden = [
      for (final f in inhoud.bestanden) TbFile(f.index, f.pad, f.naam, f.grootte, null),
    ];
    final torrent = TbTorrent(0, inhoud.naam, r.hash, 'lokaal', 0, bestanden, false, false,
        size: inhoud.totaleGrootte, seeds: r.seeders, lokaleTorrent: bytes);
    final audio = bestanden.where((f) => f.isAudio).toList();
    // De inhoudsopgave IS binnen en er zit niets speelbaars in. Dan is TorBox erbij halen zinloos:
    // die krijgt exact dezelfde lijst te zien.
    //
    // Gemeten op 24-08-2026 met een RuTracker-treffer die 29 seeders had: **282 seconden** om
    // uiteindelijk "geen afspeelbare audio" te melden — vier en een halve minuut wachten op een
    // antwoord dat na een halve seconde al vaststond. Het was een DSD-rip van vinyl; zeg dan ook
    // wat er wél in zit, anders lijkt het op een kapotte bron.
    if (audio.isEmpty) throw 'Geen afspeelbare audio in deze torrent${_watZitErin(bestanden)}.';
    return (torrent, audio);
  }

  /// De soorten bestanden in een torrent, kort, voor in een melding: " (wel .dsf, .cue)".
  String _watZitErin(List<TbFile> bestanden) {
    final soorten = <String>{};
    for (final f in bestanden) {
      final punt = f.name.lastIndexOf('.');
      if (punt > 0 && punt < f.name.length - 1) soorten.add(f.name.substring(punt).toLowerCase());
    }
    if (soorten.isEmpty) return '';
    final lijst = (soorten.toList()..sort()).take(4).join(', ');
    return ' (wel $lijst)';
  }

  /// (torrent, audio files) for the track picker.
  Future<(TbTorrent, List<TbFile>)> tracklist(SearchResult r,
      {void Function(double, String)? onProgress}) async {
    if (lokaalVoor(r)) {
      final lokaal = await _lokaleTracklist(r);
      if (lokaal != null) return lokaal;
      // Geen bestand of geen audio erin? Dan alsnog langs TorBox — beter een trage lijst dan geen.
    }
    if (!torbox.hasKey) throw 'Stel eerst je TorBox-sleutel in (Instellingen).';
    final (id, hash) = await _addOrFind(r);
    final item = await _pollReady(id, hash, patient: !r.cached, onProgress: onProgress);
    final files = _sortedAudio(item);
    if (files.isEmpty) throw 'Geen audio in deze torrent';
    return (item, files);
  }

  Future<String> resolveTrackUrl(int torrentId, int fileId) async {
    final url = await torbox.requestDownload(torrentId, fileId);
    if (url == null) throw 'Lege download-URL';
    return url;
  }

  /// Resolve the torrent + the files to download (all audio, or one file).
  Future<(TbTorrent, List<TbFile>)> resolveForDownload(SearchResult r, int? fileId,
      {void Function(double, String)? onProgress}) async {
    if (lokaalVoor(r)) {
      final lokaal = await _lokaleTracklist(r);
      if (lokaal != null) {
        final (torrent, audio) = lokaal;
        // Er valt hier niets te wachten: aria2 begint pas als de downloadlijst hem de opdracht
        // geeft. Dat is meteen het verschil met TorBox, waar dit punt betekende dat de torrent daar
        // al helemaal binnen moest zijn voordat de eerste byte deze kant op kwam.
        final gekozen =
            fileId != null ? torrent.files.where((f) => f.id == fileId).toList() : audio;
        if (gekozen.isNotEmpty) return (torrent, gekozen);
      }
    }
    if (!torbox.hasKey) throw 'Stel eerst je TorBox-sleutel in (Instellingen).';
    final (id, hash) = await _addOrFind(r);
    final item = await _pollReady(id, hash, patient: !r.cached, onProgress: onProgress);
    final files = fileId != null ? item.files.where((f) => f.id == fileId).toList() : _sortedAudio(item);
    if (files.isEmpty) throw 'Geen audio gevonden';
    return (item, files);
  }
}

/// Soulseek search (with the first-character "*" quirk) + credentials gate.
class SoulseekService {
  final AppSettings settings;
  final SoulseekClient client = SoulseekClient();
  SoulseekService(this.settings);

  bool get available => settings.soulseekUser.isNotEmpty && settings.soulseekPass.isNotEmpty;

  /// True while nothing may touch Soulseek — so normal browsing can't keep feeding the problem.
  ///
  /// [SoulseekClient.mustNotLogin], not `blocked`: the login budget stops logins just as firmly and
  /// used to do it invisibly, leaving the panel to report "0 bronnen" with no reason given.
  bool get blocked => client.mustNotLogin;
  Duration? get blockedFor => client.blockedFor;

  /// What is actually going on — see [SlskPause]. The screen wrote its own text from one boolean
  /// and called a kick, a silence and a wrong password all "login geweigerd".
  SlskPause get pause => client.pause;
  String get pauseLabel => client.pauseLabel;
  String? get whyNotLogin => client.whyNotLogin;

  /// Drop every wait standing in the way and let one login through.
  ///
  /// The session's own counters go too. Without them the button cleared the client's back-off and
  /// the session refused anyway, so nothing happened and the notice stayed on screen.
  void retryLoginNow() {
    // Een geplande herkansing hoort hier te vervallen: de gebruiker doet nu zelf wat die timer straks
    // zou doen, en anders vuurt hij later alsnog op een toestand die niets meer met zijn aanleiding
    // te maken heeft.
    _herkans?.cancel();
    _herkans = null;
    client.allowOneRetry();
    _session?.allowRetry();
  }

  // ── The one logged-in connection ──────────────────────────────────────────
  // Soulseek allows a single login per account and blocks on a burst of them, so EVERYTHING that
  // talks to the server — searching, downloading, the status check — shares this one session.
  // Searching used to open its own connection and log in per query (twice, with the broad-query
  // retry), which is what kept getting the account blocked.
  SlskSession? _session;
  Timer? _idle;
  int _users = 0;

  Future<T> withSession<T>(Future<T> Function(SlskSession) body) async {
    _users++;
    _idle?.cancel();
    try {
      client.listenPort = settings.soulseekPort; // so firewalled peers can reach us
      // A session holds the username and password it was built with. Correcting them in Settings
      // therefore changed nothing until the old session happened to idle out — so the fix for a
      // wrong password appeared not to work, which is the worst possible moment to be ignored.
      final s0 = _session;
      if (s0 != null && (s0.user != settings.soulseekUser || s0.pass != settings.soulseekPass)) {
        s0.close();
        _session = null;
      }
      final s = _session ??= client.newSession(settings.soulseekUser, settings.soulseekPass);
      // Er gaat nú iets naar Soulseek, dus dit is het moment waarop uitgestelde taken alsnog mogen.
      // Zie [DownloadManager.resumePending]: die start bij het opstarten niets meer, want een login
      // vóór de eerste gebruikersactie is precies wat met de vorige sessie botste.
      final wacht = bijEersteGebruik;
      if (wacht != null) {
        bijEersteGebruik = null;
        wacht();
      }
      return await body(s);
    } finally {
      _users--;
      if (_users == 0) _scheduleClose();
      // Liep het mis op een botsing met de vorige sessie, dan lost de app dat vanaf nu zélf op in
      // plaats van te wachten tot de gebruiker op "nu opnieuw proberen" drukt.
      _plaatsHerkansing();
    }
  }

  /// Houd de sessie open zolang de radio loopt. Geeft terug hoe je hem weer loslaat.
  ///
  /// **Waarom een radio dit nodig heeft, en waarom het zonder stilletjes fout gaat.** Soulseek staat
  /// vier aanmeldingen per tien minuten toe en de sessie sluit zichzelf na 120 seconden zonder
  /// verkeer. Een radio haalt om de paar minuten een nummer, dus elk haaltje zou op een VERSE
  /// aanmelding vallen — na een klein half uur is het account geblokkeerd. En `_searchOnce` slikt die
  /// fout: de radio zou dan gewoon weer "alleen wat ik al heb" spelen, zonder dat er ergens iets
  /// misgaat dat je kunt zien. Precies zoals [DownloadManager._chaseUpgrade] het al doet en uitlegt.
  ///
  /// Losser laten is verplicht: zolang deze leen loopt gaat de sessie niet dicht, ook niet als de app
  /// verder niets doet.
  void Function() leaseVoorRadio() {
    final tot = Completer<void>();
    unawaited(withSession((_) => tot.future).catchError((_) {}));
    return () {
      if (!tot.isCompleted) tot.complete();
    };
  }

  /// Wordt één keer aangeroepen zodra er echt een sessie nodig is — de haak waarmee onderbroken
  /// downloads alsnog op gang komen zonder dat het opstarten zelf inlogt.
  void Function()? bijEersteGebruik;

  /// Na een botsing met de vorige sessie: zelf opnieuw proberen, zonder dat de gebruiker iets doet.
  ///
  /// Dit was het gat waar Saber terecht op wees — "die knop moet zijn wat jij doet om de blokkade weg
  /// te halen". De pauze liep na anderhalve minuut af, maar er gebeurde daarna niets: pas als je
  /// tóevallig weer iets aanklikte werd het opnieuw geprobeerd, en anders bleef de melding staan.
  ///
  /// Alleen voor de twee pauzes die over ONZE kant gaan — een botsing met de vorige sessie en een
  /// netwerk dat van route wisselde — en hoogstens twee keer. Een echte weigering hoort NIET
  /// automatisch herhaald te worden: dan is doorgaan met kloppen precies wat het erger maakt.
  static const _zelfOplosbaar = {SlskPause.herstart, SlskPause.netwerkGewisseld};

  Timer? _herkans;
  int _herkansingen = 0;

  void _plaatsHerkansing() {
    if (!_zelfOplosbaar.contains(client.pause)) return;
    if (_herkansingen >= 2) return;
    final wacht = client.blockedFor;
    if (wacht == null) return;
    _herkans?.cancel();
    _herkans = Timer(wacht + const Duration(seconds: 3), () async {
      // NOG EENS KIJKEN of de pauze waarvoor deze timer gepland werd er überhaupt nog is.
      //
      // De controle stond alleen bovenaan, op het moment van plannen. In de anderhalve minuut die
      // ertussen zit kan er van alles gebeuren, en `allowOneRetry()` wist blind élke blokkade. Twee
      // gemeten gevolgen: een tikfout in het wachtwoord levert tien minuten `badLogin` met "wachten
      // helpt hier niet" — en die werd door de oude timer weggegooid, waarna er nóg een login met dat
      // foute wachtwoord vertrok. En lukt de herkansing terwijl de officiële app ons daarna kickt, dan
      // wiste diezelfde timer de kick-terugval en logde meteen weer in: de kickoorlog waar het
      // commentaar hierboven juist tegen beschermt.
      if (!_zelfOplosbaar.contains(client.pause)) {
        client.logboek('herkansing overgeslagen — de pauze is intussen ${client.pause.name}');
        return;
      }
      _herkansingen++;
      client.logboek('herkansing $_herkansingen na een botsing — zelf opnieuw proberen');
      client.allowOneRetry();
      _session?.allowRetry();
      try {
        final ok = await verify();
        client.logboek(ok ? 'herkansing gelukt' : 'herkansing mislukt');
        if (!ok) _plaatsHerkansing();
      } catch (_) {/* de volgende gebruikersactie probeert het toch weer */}
    });
  }

  /// Let go of the connection when nothing needs it, so the native client can log in again.
  ///
  /// Netjes afmelden, net als bij het afsluiten. Dit is namelijk de weg die in de praktijk ALTIJD
  /// wordt gelopen: wie om 19:23 iets downloadt is om 19:25 klaar, en dan sluit deze klok de
  /// verbinding — lang voordat het venster dichtgaat. Zolang hier `close()` stond (en dus
  /// `Socket.destroy()`, wegsmijten zonder af te ronden) bleef de sessie aan de serverkant staan, en
  /// botste de vólgende start ermee. De nette afmelding bij het sluiten van het venster vond dan al
  /// niets meer om af te melden; gemeten op drie seconden verschil.
  void _scheduleClose() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 120), () {
      if (_users > 0) return;
      final s = _session;
      _session = null;
      unawaited(s?.signOff() ?? Future.value());
    });
  }

  /// Shutdown only. Guarded on [_users]: closing a session that a search or a queued download is
  /// still holding would leave that operation with an orphaned session which logs itself back in —
  /// two live logins for an account that allows one.
  void disposeSession() {
    if (_users > 0) return;
    _idle?.cancel();
    final s = _session;
    _session = null;
    // Ook hier afmelden en niet wegsmijten — zie [_scheduleClose]. Niet afgewacht, want deze weg
    // loopt via `dispose()` en dat mag niet blokkeren; [signOff] doet het werk toch af.
    unawaited(s?.signOff() ?? Future.value());
  }

  /// Afmelden bij Soulseek omdat het venster dichtgaat.
  ///
  /// Bewust NIET afbreken op [_users], zoals [disposeSession] doet. Die terughoudendheid klopt tijdens
  /// het draaien — een sessie wegnemen onder een lopende download vandaan levert een weesverbinding op
  /// die zichzelf opnieuw aanmeldt. Maar bij het sluiten gaat het proces hoe dan ook weg, en dan is
  /// vasthouden juist hoe het spook ontstaat waar de volgende start mee botst.
  ///
  /// Wachten hoort hier wél: zie [SlskSession.signOff] voor waarom de volgorde ertoe doet.
  Future<void> signOff() async {
    _idle?.cancel();
    final s = _session;
    _session = null;
    await s?.signOff();
  }

  /// Confirm the Soulseek login works (used by the connection-status check).
  /// Goes through the shared session — it never costs a login of its own.
  Future<bool> verify() async {
    if (!available) return false;
    return withSession((s) => s.alive());
  }

  /// [onPartial] streams merged results as they arrive.
  ///
  /// Soulseek requires EVERY term to appear in a peer's path, so a long "Artist Title" query can
  /// come back completely empty while the artist alone has plenty (measured: "jaafar jackson got
  /// me singing" → 0 hits even after 30s, "jaafar jackson" → hits within 2s). So when a multi-word
  /// query finds nothing, retry once with just the first two words (usually the artist) rather
  /// than telling the user there are no sources. Both attempts run on the shared connection, so
  /// the retry costs nothing beyond the query itself.
  ///
  /// **De terugval loopt sinds kort in trappen** — zie [zoekLadder]. Hij sprong van de volledige
  /// vraag meteen naar de eerste twee woorden, en dat is bij een titel met een versie-aanduiding de
  /// titel kwijt: "Sting Fields of Gold (My Songs Version)" werd "Sting Fields". Je kreeg dan
  /// bronnen voor een ander nummer, zonder dat er iets over gezegd werd. De trede ertussen — dezelfde
  /// vraag zonder de haakjes — is precies de nuttigste.
  ///
  /// [gebruikteVraag] meldt op welke trede er uiteindelijk gezocht is, zodat het scherm eerlijk kan
  /// zeggen waar deze lijst over gaat.
  Future<List<SoulseekFile>> search(String query,
      {void Function(List<SoulseekFile>)? onPartial, void Function(String)? gebruikteVraag}) async {
    // An empty result because we couldn't log in is NOT "no sources" — retrying a broader query
    // would just burn another login and still show the user the wrong answer.
    final blocked = client.whyNotLogin;
    if (blocked != null) throw blocked;
    final rondes = zoekRondes(query);
    var laatste = <SoulseekFile>[];
    for (final ronde in rondes) {
      // De RUIMSTE vraag van deze ronde, want daar kunnen de resultaten vandaan komen. Zie
      // [ruimerGezocht]: dat is precies waar het scherm eerlijk over hoort te zijn.
      gebruikteVraag?.call(ronde.last);
      laatste = await _searchOnce(ronde, onPartial);
      if (laatste.isNotEmpty) return laatste;
      if (client.whyNotLogin != null) throw client.whyNotLogin!;
    }
    return laatste;
  }

  /// Alle vragen van één ronde in ÉÉN zoekopdracht — zie [zoekRondes].
  ///
  /// Ze gaan als losse tickets naar dezelfde sessie en komen op één hoop terug, dus twee vragen
  /// kosten hetzelfde als één. Zou je ze na elkaar sturen, dan was elke ronde er ruim acht seconden
  /// bij.
  Future<List<SoulseekFile>> _searchOnce(
      List<String> vragen, void Function(List<SoulseekFile>)? onPartial) async {
    if (!available) return [];
    final variants = <String>{};
    for (final v in vragen) {
      final q = v.trim();
      if (q.isEmpty) continue;
      // Alleen op de eerste vraag. De jokervariant vangt één weggevallen eerste teken op; hem voor
      // élke vraag meesturen verdubbelt het aantal tickets zonder er iets tegenover te zetten.
      if (variants.isEmpty && jokerHelpt(q)) variants.add('*${q.substring(1)}');
      variants.add(q);
    }
    if (variants.isEmpty) return [];
    try {
      return await withSession((s) => s.search(variants.toList(), onPartial: onPartial));
    } catch (_) {
      return [];
    }
  }
}

class DownloadJob {
  final String name;
  final String? key; // stable id so a specific tile/track row can show THIS job's progress inline
  double progress;
  String status; // queued | waiting | downloading | upgrading | done | failed | preparing
  String? detail; // failure reason, or "poging 2/5 · peer" while falling back
  int queuePlace = 0; // position in the uploader's queue while status == 'waiting' (0 = unknown)

  /// Everything this job currently has in flight — several at once while racing peers. Stopping
  /// the job means stopping all of them.
  final List<SlskCancel> live = [];
  bool cancelled = false;

  /// Only a Soulseek job can actually be stopped mid-flight; a TorBox transfer has no such
  /// handle, and offering a button that silently does nothing is worse than offering none.
  bool canCancel = false;

  /// De gebruiker heeft deze BRON zelf aangewezen, ook al noemde hij geen los bestand.
  ///
  /// Het geval waarvoor dit bestaat is "Download album": je hebt één map van één peer uitgekozen,
  /// maar per nummer staan er meer kopieën klaar voor als die peer niet levert — dus [exact] kan niet
  /// gezet worden zonder die uitwijk kwijt te raken. Zonder een eigen vlag telde zo'n download als
  /// automatisch, en ging de app er achteraf alsnog een "betere" versie voor zoeken.
  ///
  /// Wat het doet is precies hetzelfde als [exact]: het bestand wordt een vaste keuze (zie
  /// `vaste_keuze.dart`) en er komt geen jacht op iets beters achteraan.
  bool jouwKeuze = false;

  /// Identity of the TRACK, not of one peer's copy. Clicking five sources of the same song must
  /// not start five downloads of it.
  String? trackKey;

  /// De sleutel van de WENS die hierbij hoort, zodra deze download op de wenslijst gezet is.
  ///
  /// Zonder dit was een wens vanaf het scherm niet meer te bereiken: je zag "Later opnieuw" staan,
  /// maar de enige manier om ervan af te komen was de rij wegvegen — en dan bleef de wens achter en
  /// zocht de app door. Zie [DownloadManager.stopWens].
  String? wensSleutel;

  /// Every peer copy this job may fall back on — kept so the job can be written down and picked
  /// up again after a restart.
  List<SoulseekFile> candidates = const [];

  /// Het bestand dat de gebruiker ZELF aanwees, als hij dat deed.
  ///
  /// Gevuld betekent: haal dit, niet iets wat er volgens de rangschikking op lijkt. Alles wat de
  /// kwaliteitsjacht doet staat dan uit — sorteren, poolsplitsing, opwaarderen achteraf. Zie
  /// [DownloadManager.enqueueSoulseekBest].
  SoulseekFile? exact;

  /// What this track IS, according to the official release the user was looking at — not according
  /// to whichever peer happened to serve it. Soulseek delivers the audio; this decides the name,
  /// the folder and the tags. Null for a download with no album context (a loose search hit).
  TrackTags? authority;
  bool get busy =>
      status == 'queued' ||
      status == 'waiting' ||
      status == 'downloading' ||
      status == 'preparing' ||
      status == 'upgrading';

  /// The track is on disk and playable — even if something is still running for it.
  bool get playable => status == 'done' || status == 'upgrading';
  DownloadJob(this.name, {this.key, this.status = 'downloading'}) : progress = 0;
}

/// Streams TorBox + Soulseek downloads into the music library (with progress), then rescans.
class DownloadManager extends ChangeNotifier {
  final OnlineService online;
  final SoulseekService soulseek;
  final String musicRoot;
  final Future<void> Function() onLibraryChanged;

  /// Heeft de bibliotheek dit nummer al lossless? Laat een staande wens vervallen.
  ///
  /// Als vraag naar buiten en niet als eigen index: de bibliotheek weet dit al, en een tweede
  /// administratie zou ernaast gaan lopen zodra de gebruiker een map verplaatst.
  bool Function(String artist, String title)? haveLossless;

  /// Waar deze opname al staat, zodat een betere versie er NAARTOE gaat in plaats van ernaast.
  ///
  /// Zonder dit bergt de app een download op volgens diens eigen albumtag, en dan landt een 24/192 van
  /// Thriller in een map "Thriller" naast je "Thriller (MFSL One Step)" — twee albums, en het mindere
  /// bestand blijft staan omdat de vervangingsregel alleen binnen één map kijkt.
  /// [seconds] is de looptijd volgens de UITGAVE. Zonder haar antwoordde de bibliotheek "die heb je
  /// al" op enkel artiest + titel, en werd een heropname als mindere dubbel van schijf gewist. Zie
  /// [LibraryStore.fileOfRecording].
  String? Function(String artist, String title, {int? seconds})? mapVanBestaande;

  DownloadManager(this.online, this.soulseek, this.musicRoot, this.onLibraryChanged);

  final List<DownloadJob> jobs = [];

  // ── Shared Soulseek download session ──────────────────────────────────────
  // Soulseek allows ONE login per username and blocks on a burst of logins — but a file TRANSFER
  // is a separate peer socket and costs no login. So (like the native client) all downloads share
  // ONE logged-in session and run in PARALLEL on it, up to [_slskMaxParallel] at a time; the rest
  // queue. The session auto-closes ~2 min after the last download, freeing Soulseek's single
  // connection so the native client can be used again.
  /// GEMETEN op 07-08-2026, want zes was een gok en dit is te meten.
  ///
  /// **De lijn**, met wisselende hosts zodat één trage server niet als plafond doorgaat — die fout
  /// zat in de eerste meting en gaf een lijn van 60 Mbit/s die in werkelijkheid 540 blijkt:
  ///
  /// | stromen | samen |
  /// |---|---|
  /// | 4 | 36,3 MB/s (304 Mbit/s) |
  /// | 8 | **64,4 MB/s (540 Mbit/s)** |
  /// | 16 | 62,6 MB/s — geen winst meer |
  ///
  /// De lijn zit dus vol rond acht gelijktijdige stromen.
  ///
  /// **Eén peer**, gemeten aan echte Soulseek-overdrachten in diezelfde sessie: 2,59 · 3,22 · 3,23 ·
  /// 3,72 · 7,67 · 7,81 MB/s, en drie uitschieters van 35 tot 47. Mediaan rond 3,7 MB/s. Eén peer
  /// haalt de lijn dus bij lange na niet vol, en dat is precies het geval waarin meer tegelijk helpt.
  ///
  /// **Waarom twaalf.** Twaalf keer de mediaan is ~44 MB/s, onder het plafond van 64. En dit getal
  /// begrenst **zoekende** jobs, niet lopende overdrachten: een nummer houdt zijn slot vast terwijl
  /// het twintig peers afgaat zonder één byte te ontvangen, dus het werkelijke aantal stromende
  /// overdrachten ligt altijd lager. Hoger opendraaien koopt vooral peer-verbindingen (twintig per
  /// job) en geen doorvoer — en een Soulseek-netwerk waar honderden sockets vandaan komen is geen
  /// nette gast.
  static const _slskMaxParallel = 12;

  /// How many peers a sweep walks looking for "someone free right now". Lossless gets a much
  /// deeper sweep: settling for an MP3 while an untried FLAC was sitting at position 7 would
  /// break the one rule that matters here. A short probe timeout keeps that affordable.
  /// Each try is now a DIFFERENT peer (see [_sweepOrder]), so the budget buys real chances rather
  /// than several files from the same collector.
  static const _maxLosslessTries = 20;
  static const _maxLossyTries = 8;

  /// How fast the race opens new peer connections. Not a cap on how many run at once: a peer that
  /// answers "you're in my queue" frees its slot immediately and keeps waiting in the background,
  /// so within half a minute the whole shortlist is engaged. Peer connections, not logins — the
  /// shared session is untouched, so this cannot repeat the login problem.
  static const _probeWidth = 6;

  /// Total time spent chasing a better copy after a playable one already landed.
  static const _upgradeBudget = Duration(minutes: 10);

  /// Wat deze weg besloot, in `downloads.log` naast de andere staatbestanden.
  ///
  /// Gebouwd omdat een vraag niet te beantwoorden was. Een FLAC die via de app niet binnenkwam en via
  /// de native client meteen wel: er zijn vier mechanismen die dat kunnen verklaren -- geen kandidaat
  /// gevonden, tien minuten opwaardeerbudget op, wachten achter een andere opwaardering, of een
  /// herstart die de jacht afkapt -- en van buitenaf zijn ze niet van elkaar te onderscheiden.
  /// pending_downloads.json wordt opgeruimd en warm.log gaat alleen over de metadata-warmer, dus na
  /// een uur is er niets meer om naar te kijken. Precies de les die warm.log zelf al opschreef.
  late final WarmLog _log = WarmLog('$appDir${Platform.pathSeparator}downloads.log');

  /// Hoeveel opdrachten er op dezelfde aria2-taak hangen, per gid.
  ///
  /// **Waarom er geteld wordt en niet gewoon opgeruimd.** Twee nummers van dezelfde plaat delen één
  /// aria2-taak (zie het aanhaken in [_downloadLokaal]). Ruimt de eerste die klaar is die taak op,
  /// dan trekt hij de map onder de tweede vandaan: `ruimOpNaTorrent` gooit aria2's eigen map weg, en
  /// `verwijder` haalt het gid weg waar de tweede zijn voortgang uit leest. Alleen de laatste die
  /// vertrekt doet het licht uit.
  final Map<String, int> _lopersPerTorrent = {};

  /// Welk aria2-gid hoort bij welke infohash, zolang die taak loopt.
  ///
  /// **Waarom de app dit zelf bijhoudt.** Een tweede nummer van dezelfde plaat kan niet opnieuw
  /// aangemeld worden — aria2 kent een torrent aan zijn infohash en weigert dat. De app kwam daar
  /// eerst achter door de weigering óp te vangen en aria2 daarna te vragen welk gid erbij hoorde:
  /// drie plekken die stil fout kunnen gaan (de tekst van de weigering, `tellActive`, en of hij die
  /// taak wil aanwijzen) voor iets wat zij zelf weet, want zij heeft die taak aangemeld.
  final Map<String, String> _gidPerTorrent = {};

  /// Upgrades take NO download slot, so ze kunnen nooit een nummer ophouden waar je nog niets van
  /// hebt. Queued rather than dropped, so a whole album still gets upgraded.
  ///
  /// Niet meer strikt één tegelijk. Gemeten op het Sade-album van 14:44: negen nummers waren na twee
  /// minuten binnen, en daarna rekten de jachten het tot 14:51 — met "er loopt al een jacht, 2
  /// wachtend" in het logboek. Zeven minuten voor een album dat in twee binnen was, puur omdat de
  /// staart serieel liep. Drie tegelijk maakt die staart korter zonder de lijn te overvragen: elke
  /// jacht is één overdracht, en drie erbij past ruim in wat de lijn aankan (zie
  /// [_slskMaxParallel]).
  /// Hoe lang een torrentdownload mag zwijgen voor hij als stuk geldt.
  ///
  /// Zelfde gedachte als `stilte` in `offline.dart`, en om dezelfde reden een ruime waarde: het gaat
  /// om stilte, niet om duur.
  static const _torrentStilte = Duration(seconds: 60);

  /// Hoeveel bestanden van een plaat er tegelijk binnenkomen.
  ///
  /// Hier stond geen rem: `enqueue` vuurde voor élk bestand een `unawaited(_download(...))` af. Een
  /// plaat van 25 nummers opende dus 25 verbindingen naar de CDN én deed 25 gelijktijdige
  /// `requestdl`-aanroepen. Dat is niet sneller — een lijn heeft een bodem, en je verdeelt hem
  /// alleen in dunnere stroompjes — maar het maakt de voortgang wel onleesbaar en de kans op een
  /// afgeknepen verbinding groter. Vier tegelijk vult een gewone lijn en houdt de rest netjes in de
  /// wacht, zoals de opwaardeerjachten hierboven ook al deden.
  static const _maxParallelleDownloads = 4;

  static const _maxParallelleJachten = 3;

  final Werkrij _jachten = Werkrij(_maxParallelleJachten);

  /// Dezelfde rij, maar voor de bestanden van een torrent. Zie [_maxParallelleDownloads].
  final Werkrij _torrentRij = Werkrij(_maxParallelleDownloads);
  int _slskActive = 0; // downloads holding a PARALLEL SLOT (a queued one gives its slot back)
  final List<Completer<void>> _slskWaiting = [];

  /// Live count of Soulseek downloads running / waiting (for the UI).
  int get slskActive => _slskActive;
  int get slskQueued => _slskWaiting.length;

  /// [body] gets a `releaseSlot` callback: a download that ends up waiting in an uploader's queue
  /// holds its peer connection (losing it would cost our queue position) but must NOT keep
  /// occupying one of the parallel slots — otherwise one busy uploader stalls everything else.
  Future<T> _withSlsk<T>(Future<T> Function(SlskSession, void Function()) body) async {
    if (_slskActive >= _slskMaxParallel) {
      final wait = Completer<void>();
      _slskWaiting.add(wait);
      await wait.future;
    }
    _slskActive++;
    var released = false;
    void release() {
      if (released) return;
      released = true;
      _slskActive--;
      if (_slskWaiting.isNotEmpty) _slskWaiting.removeAt(0).complete(); // let the next one start
    }

    try {
      // The session belongs to SoulseekService and is shared with searching, so N parallel
      // downloads plus any search in flight still cost exactly ONE login. withSession also holds
      // the connection open for as long as anyone needs it — including a download parked in an
      // uploader's queue, whose retry would otherwise have to log in again.
      return await soulseek.withSession((s) => body(s, release));
    } finally {
      release();
    }
  }

  @override
  void dispose() {
    _rem.stop();
    soulseek.disposeSession();
    super.dispose();
  }

  /// De rem op de voortgangsmeldingen. Zie `meldrem.dart` voor waarom hij er is.
  ///
  /// Alleen voor VOORTGANG. Een eindtoestand — klaar, mislukt, gestopt — blijft `notifyListeners()`
  /// rechtstreeks aanroepen: die gebeurt één keer en hoort meteen op het scherm te staan.
  late final Meldrem _rem = Meldrem(notifyListeners);

  /// "Er is voortgang." Hoogstens vijf keer per seconde, hoeveel downloads er ook lopen.
  void _meldVoortgang() => _rem.vraag();

  /// The most recent job with this key (or null) — lets a tile/track row show its own progress.
  DownloadJob? jobByKey(String key) {
    for (final j in jobs) {
      if (j.key == key) return j;
    }
    return null;
  }

  /// Stop a download the user no longer wants. Everything in flight for it is torn down; the
  /// partial file is removed by the transfer itself.
  void cancelJob(DownloadJob job) {
    job.cancelled = true;
    for (final c in job.live) {
      c.cancel();
    }
    job.live.clear();
    job.status = 'failed';
    job.detail = 'geannuleerd';
    job.queuePlace = 0;
    notifyListeners();
    // Off the list at once — a download the user stopped must not come back at the next start.
    unawaited(_savePending());
  }

  /// Stop met dit nummer proberen: van de wenslijst af, en de rij van het scherm.
  ///
  /// Dit is het verschil met [clearFinished], en het is een echt verschil. Opruimen haalt rijen weg
  /// die niets meer van je vragen; dit zegt "hier hoef je niet meer naar te zoeken". Zonder deze
  /// weg was een eenmaal aangemaakte wens vanaf het scherm onbereikbaar: hij bleef op de
  /// achtergrond zoeken en er was geen knop die dat kon stoppen.
  Future<void> stopWens(DownloadJob job) async {
    final sleutel = job.wensSleutel;
    if (sleutel != null) {
      await _ensureWants();
      if (_wants.forget(sleutel)) await _wants.save();
    }
    jobs.remove(job);
    notifyListeners();
  }

  /// Remove finished (done/failed) jobs from the list; keep anything still in progress.
  void clearFinished() {
    // 'later' hoort hier NIET bij, en stond er eerst wel. Zo'n rij is niet afgerond maar wacht op
    // een volgende poging, en die verdween dus bij het opruimen van wat klaar was. De wens bleef
    // achter de schermen staan, dus de app bleef zoeken naar iets waarvan jij dacht dat je het had
    // weggehaald. Wie er echt vanaf wil, gebruikt het kruisje op die rij — zie [stopWens].
    jobs.removeWhere((j) => j.status == 'done' || j.status == 'failed');
    notifyListeners();
  }

  /// Rank peers offering the SAME track by QUALITY first: the user always wants the best copy
  /// available (24-bit hi-res FLAC → CD FLAC → … → MP3 only as an absolute last resort). The
  /// peer-fallback then falls through if the top pick won't actually download, so availability
  /// only breaks ties between EQUAL-quality copies.
  /// Rangschik peers die HETZELFDE nummer aanbieden, op kwaliteit eerst.
  ///
  /// GEMETEN EN VERWORPEN op 06-08-2026 — hier stond een regel die een hi-res-claim wegzette als
  /// maar een klein deel van het netwerk hem aanbood. Het idee: bestaat een plaat echt in hi-res,
  /// dan heeft een flink deel van de peers hem. Op twee albums leek dat te kloppen. Op negen
  /// nummers waarvan de spectrumproef bewijst dat ze écht hi-res zijn, klopt het niet:
  ///
  /// | bewezen echt (inhoud boven 22 kHz) | aandeel >48 kHz |
  /// |---|---|
  /// | Adele — Don't You Remember | 0,105 |
  /// | Adele — Rolling in the Deep | 0,080 |
  /// | Daft Punk — Aerodynamic | 0,074 |
  /// | George Michael — Careless Whisper | 0,039 |
  /// | Dua Lipa — Love Again | 0,017 |
  /// | George Michael — Jesus to a Child | 0,017 |
  /// | Beyoncé — Cuff It | 0,006 |
  /// | Alicia Keys — If I Ain't Got You | 0,001 |
  /// | Céline Dion — Falling Into You (24/192!) | 0,000 |
  ///
  /// De opgeschaalde Stromae-nummers zaten op 0,017–0,024 — middenin die reeks. Er is geen drempel
  /// die 0,017 van 0,017 scheidt, en een regel op 0,05 zou vijf van deze negen echte hi-res-platen
  /// hebben gedegradeerd. Van Céline Dion biedt het netwerk er zelfs GEEN ENKELE aan terwijl haar
  /// bestand aantoonbaar 24/192 met echte inhoud daarboven is.
  ///
  /// Wat het netwerk aanbiedt zegt dus iets over hoe populair een uitgave is, niet over of hij
  /// bestaat. Deze aantekening staat hier zodat niemand — ik incluis — dit een tweede keer probeert.
  static int _rankSlsk(SoulseekFile a, SoulseekFile b) {
    final qa = _slskScore(a), qb = _slskScore(b);
    if (qa != qb) return qb - qa; // higher quality first
    if (a.freeSlots != b.freeSlots) return a.freeSlots ? -1 : 1;
    if (a.queueLength != b.queueLength) return a.queueLength.compareTo(b.queueLength);
    if (a.speed != b.speed) return b.speed.compareTo(a.speed);
    return b.size.compareTo(a.size);
  }

  /// A comparable quality score: format tier dominates (lossless ≫ lossy), then effective
  /// bitrate distinguishes hi-res (24/192 ≈ 4000k) from CD (16/44 ≈ 900k) within a tier.
  static int _slskScore(SoulseekFile f) {
    final q = qualityFromFile(
      name: f.displayName,
      ext: f.ext,
      isFlac: f.isFlac,
      bitrate: f.bitrate,
      durationSec: f.durationSec,
      size: f.size,
      isVbr: f.isVbr,
    );
    final stereo = switch (q.tier) {
      QTier.hires => 4,
      QTier.lossless => 3,
      QTier.lossy => 1,
      QTier.unknown => 0,
    };
    // A surround rip carries the most bits of all and would win every comparison on bitrate — but
    // it gets downmixed on a stereo system and costs ten times the space (one measured track:
    // 263 MB). It sits below every stereo lossless copy, and still above MP3: it IS lossless.
    final tier = (stereo >= 3 && isMultichannel(f)) ? 2 : stereo;
    return tier * 1000000 + effectiveKbps(f).clamp(0, 999999);
  }

  /// Bitrate as actually delivered — the peer's own figure, else derived from size and duration.
  static int effectiveKbps(SoulseekFile f) {
    final stated = f.bitrate ?? 0;
    if (stated > 0) return stated;
    if ((f.durationSec ?? 0) > 0 && f.size > 0) return (f.size * 8 / f.durationSec! / 1000).round();
    return 0;
  }

  static final _multichannelRe = RegExp(
    r'(\b5[\._ ]1\b|\b7[\._ ]1\b|\b4[\._ ]0\b|surround|multi[\- ]?channel|quadraphonic|\bquad\b|atmos|\bdts\b|\bauro3d\b)',
    caseSensitive: false,
  );

  /// A 5.1/surround rip rather than a stereo master.
  ///
  /// The release name is the reliable signal; the bitrate is the backstop for rips that don't say
  /// so. 6500k is above what stereo 24/192 FLAC reaches (~5000k) and below 5.1 24/96 (~8000k).
  /// Drie wegen, van hard naar zacht — want elke weg alleen laat er doorheen glippen.
  ///
  /// 1. De SOM. Sinds de peer zijn sample rate en bitdiepte meestuurt, is dit te bewijzen: een FLAC is
  ///    nooit groter dan onbewerkt, dus wie boven `sampleRate × bits × 2` uitkomt heeft meer kanalen.
  ///    Zie [meerDanStereo]. Dit vervangt de vaste 6500 hieronder waar het kan, en dat is nodig: die
  ///    grens zit precies in het gebied waar 24/192 stereo leeft (4600–6500), dus hij nam echte
  ///    stereobestanden mee én liet een 5.1 op cd-kwaliteit (~2600) lopen.
  /// 2. De NAAM, voor peers die geen sample rate sturen.
  /// 3. De vaste grens, als vangnet voor diezelfde peers.
  static bool isMultichannel(SoulseekFile f) {
    final kbps = effectiveKbps(f);
    if (f.sampleRate != null && f.bitDepth != null) {
      return meerDanStereo(sampleRate: f.sampleRate, bitDepth: f.bitDepth, kbps: kbps) ||
          _multichannelRe.hasMatch(f.filename);
    }
    return _multichannelRe.hasMatch(f.filename) || kbps > 6500;
  }

  Future<void> enqueueSoulseek(SoulseekFile file) => enqueueSoulseekBest([file]);

  /// Download one track, trying its candidate peers best-first until one succeeds.
  /// [candidates] are copies of the SAME track from different peers. [key] lets the UI show
  /// this job's live progress inline on the tile/track row that started it.
  /// [exact] is het bestand waar de gebruiker ZELF op klikte in de Soulseek-lijst.
  ///
  /// Staat het gevuld, dan is de opdracht een andere: niet "haal dit nummer" maar "haal dit bestand".
  /// De hele kwaliteitsjacht gaat dan uit — zie [_soulseekBest]. Aanleiding: bij Joe Dassin is de
  /// best gerangschikte kopie een ánder nummer, en de gebruiker kon de juiste versie daardoor niet
  /// binnenhalen, hoe vaak hij er ook op klikte.
  ///
  /// Een [SoulseekFile] en geen `bool`: de aanroeper verbreedt één klik naar een kandidatenlijst, dus
  /// de manager moet weten wélk element het was. Bovendien overleeft het zo de notitie op schijf.
  /// [wachtOpAfloop] false = antwoord zodra de taak is aangenomen, en laat hem daarna zelf lopen.
  ///
  /// Standaard true, want de albumweg telt met `Future.wait` hoeveel er geland zijn en zou anders
  /// meteen "klaar" melden terwijl er nog niets binnen is.
  ///
  /// Maar over de LAN-route is true verkeerd: daar houdt het HTTP-verzoek van een gsm of iPad de
  /// hele download lang open. Gemeten op 07-08-2026 — zeven nummers achter elkaar aangevraagd
  /// startten twintig tot veertig seconden na elkaar, netjes serieel, terwijl er twaalf tegelijk
  /// hadden gekund. Niet omdat de app het niet kon, maar omdat de aanvrager per stuk stond te
  /// wachten op een antwoord dat pas na afloop kwam.
  Future<bool> enqueueSoulseekBest(List<SoulseekFile> candidates,
      {String? key,
      TrackTags? authority,
      SoulseekFile? exact,
      bool jouwKeuze = false,
      bool wachtOpAfloop = true}) async {
    if (!soulseek.available) throw 'Stel je Soulseek-login in (Instellingen).';
    if (candidates.isEmpty) return false;
    // Don't start a duplicate if this exact key is already in progress.
    if (key != null) {
      final existing = jobByKey(key);
      if (existing != null && existing.busy) {
        return false;
      }
    }
    // Nor if the same TRACK is already running from another source. Clicking five copies of one
    // song used to start five downloads of it; whichever finished second was thrown away as a
    // duplicate anyway, and the better copy is already chased automatically once one lands.
    //
    // The key carries the DURATION as well as the name: on name alone, "Intro" from one album
    // blocked "Intro" from another, and refusing a download the user actually wanted is worse
    // than allowing a duplicate.
    //
    // Bij een handmatige keuze geldt dat NIET. Juist dat blokkeerde de gebruiker: de automatische
    // keuze had het "nummer" al te pakken (de verkeerde opname), en elke poging om er zelf een andere
    // kopie bij te halen werd geweigerd met "loopt al". De sleutel `username|filename` beschermt hier
    // nog steeds tegen twee keer klikken op dezelfde regel.
    final track = exact == null ? _trackIdOf(candidates.first) : '';
    if (track.isNotEmpty && jobs.any((j) => j.busy && j.trackKey == track)) return false;
    // Starts as 'queued': with parallel downloads a job can sit waiting for a slot, and showing a
    // spinning progress ring for it looked like a stuck download. _soulseekBest flips it to
    // 'downloading' once it actually starts.
    final job = DownloadJob((exact ?? candidates.first).displayName, key: key, status: 'queued')
      ..trackKey = track
      ..canCancel = true
      ..authority = authority
      ..exact = exact
      ..jouwKeuze = jouwKeuze || exact != null
      ..candidates = candidates;
    jobs.insert(0, job);
    notifyListeners();
    // Written down BEFORE it starts: the point is to survive the app not getting a chance to
    // finish — a PC shut down mid-download is exactly the case this is for.
    unawaited(_savePending());
    // Runs on the shared session → reuses the one login (no new login per click).
    Future<bool> draai() async {
      final ok = await _withSlsk((s, release) => _soulseekBest(candidates, job, s, release));
      await _pruneStaging();
      unawaited(_savePending());
      return ok;
    }

    if (!wachtOpAfloop) {
      // De taak staat in de lijst en is zichtbaar; wie het startte hoeft er niet op te blijven staan.
      unawaited(draai());
      return true;
    }
    return draai();
  }

  // ── Surviving a restart ───────────────────────────────────────────────────
  // A download interrupted by the app closing (or the PC shutting down) used to be simply gone:
  // no record of it anywhere, and a half-written file left behind in staging.

  String get _appDir => appDir;
  File get _pendingFile => File('$_appDir${Platform.pathSeparator}pending_downloads.json');

  Future<void> _savePending() async {
    try {
      final open = jobs.where((j) => j.busy && j.candidates.isNotEmpty).toList();
      if (open.isEmpty) {
        if (await _pendingFile.exists()) await _pendingFile.delete();
        return;
      }
      await Directory(_appDir).create(recursive: true);
      await _pendingFile.writeAsString(jsonEncode([
        for (final j in open)
          {
            'name': j.name,
            'key': j.key,
            'candidates': [for (final c in j.candidates) c.toJson()],
            if (j.authority != null) 'authority': j.authority!.toJson(),
            // Een pc die middenin uitviel hervat de GEKOZEN kopie, niet de best gerangschikte.
            if (j.exact != null) 'exact': j.exact!.toJson(),
            // Zonder dit is een albumdownload die een herstart overleeft ineens géén keuze meer, en
            // gaat de app er alsnog iets "beters" voor zoeken.
            if (j.jouwKeuze) 'jouwKeuze': true,
          }
      ]));
    } catch (_) {/* losing the note is not worth failing a download over */}
  }

  /// Hoeveel onderbroken downloads er klaarstaan, zonder er één te starten.
  ///
  /// Gevuld door [resumePending] bij het opstarten. Ze beginnen pas als er om een ándere reden een
  /// Soulseek-sessie opengaat, of als de gebruiker op "nu hervatten" drukt.
  int wachtendeHervattingen = 0;

  /// Pick up where we left off. Called once at startup, after the library is loaded.
  ///
  /// Restarted from scratch rather than continued byte-for-byte: the half-file in staging came
  /// from one particular peer that may well be gone, and the race will find whoever is fastest
  /// right now anyway. Staging is cleared first — nothing in there can be live at startup.
  ///
  /// [start] staat bij het opstarten op false, en dat is de hele reparatie van "elke pc-herstart een
  /// wachtwoordfout". Dit was het eerste wat na een herstart inlogde — vóór enige gebruikersactie, en
  /// dus precies op het moment dat de vorige sessie bij Soulseek nog geregistreerd stond. De taken
  /// worden wel gelezen en geteld; ze gaan lopen zodra er toch een sessie nodig is (zie
  /// [SoulseekService.bijEersteGebruik]) of op de knop in Mijn downloads.
  Future<int> resumePending({bool start = true}) async {
    List<dynamic> saved;
    try {
      if (!await _pendingFile.exists()) return 0;
      saved = jsonDecode(await _pendingFile.readAsString()) as List<dynamic>;
    } catch (_) {
      return 0;
    }
    await _clearStaging();
    var n = 0;
    for (final e in saved) {
      if (e is! Map<String, dynamic>) continue;
      final cands = [
        for (final c in (e['candidates'] as List<dynamic>? ?? const []))
          if (c is Map<String, dynamic>) SoulseekFile.fromJson(c),
      ].whereType<SoulseekFile>().toList();
      if (cands.isEmpty) continue;
      n++;
      if (!start) continue;
      // Not awaited: they run in parallel under the usual slot cap, and startup mustn't block.
      // A row written before this existed simply has no authority and behaves as it always did.
      final auth = e['authority'];
      final exact = e['exact'];
      unawaited(enqueueSoulseekBest(cands,
              key: e['key'] as String?,
              authority: auth is Map<String, dynamic> ? TrackTags.fromJson(auth) : null,
              exact: exact is Map<String, dynamic> ? SoulseekFile.fromJson(exact) : null,
              jouwKeuze: e['jouwKeuze'] == true)
          .catchError((_) => false));
    }
    wachtendeHervattingen = start ? 0 : n;
    if (!start && n > 0) notifyListeners();
    return n;
  }

  /// De uitgestelde hervattingen alsnog starten.
  ///
  /// Eén keer: daarna is de notitie op schijf leidend en zou een tweede ronde dezelfde downloads
  /// dubbel opstarten.
  Future<int> hervatWachtende() async {
    if (wachtendeHervattingen == 0) return 0;
    wachtendeHervattingen = 0;
    notifyListeners();
    return resumePending();
  }

  /// Is dit bestand écht wat het zegt? Gemeten zodra het binnen is, nooit ervoor.
  ///
  /// Bij een zoekresultaat kan dit niet: je kunt niet in het bestand van een vreemde kijken zonder het
  /// eerst binnen te halen. Daar blijft het bij de verhoudingswaarschuwing uit
  /// [verdachtKleinVoorHiRes] — een aanwijzing, geen oordeel.
  Future<void> _meetEchtheid(File f) async {
    try {
      final tags = readFlacTags(f);
      if (tags == null || tags.sampleRate <= 0) return;
      final meter = Echtheidsmeter(cacheMap: '$appDir${Platform.pathSeparator}echtheid');
      if (!meter.available) return;
      final o = await meter.van(f.path,
          kopSampleRate: tags.sampleRate,
          kopBits: tags.bitsPerSample,
          duurSeconden: (tags.duration?.inSeconds ?? 0).toDouble());
      if (o != null) await onthoudOordeel(f.path, o);
    } catch (_) {/* een meting is een verrijking; hij mag een download nooit breken */}
  }

  /// Everything in staging at startup is a leftover from a session that ended mid-transfer.
  Future<void> _clearStaging() async {
    final root = Directory('$_downloadsRoot${Platform.pathSeparator}_inkomend');
    try {
      if (await root.exists()) await root.delete(recursive: true);
    } catch (_) {/* in use, or already gone */}
  }

  /// Fallback loop: try up to 5 peers best-first; the first that delivers wins. All attempts
  /// reuse [session]'s single login — trying another peer costs a new peer connection, NOT a
  /// new server login.
  Future<bool> _soulseekBest(
      List<SoulseekFile> candidates, DownloadJob job, SlskSession session, void Function() releaseSlot) async {
    // Koos de gebruiker zelf, dan is er niets te rangschikken: elke kandidaat is per definitie
    // hetzelfde bestand, en zijn keuze hoort vooraan. Sorteren op kwaliteit is precies wat hem het
    // verkeerde nummer bezorgde.
    final keuze = job.exact;
    // Jouw keuze, in de brede zin: een aangewezen BESTAND (`exact`) of een aangewezen BRON — "Download
    // album" uit een Soulseek-lijst. In beide gevallen geldt hetzelfde: het blijft staan, en er komt
    // geen jacht op iets wat de app beter vindt. Zie [DownloadJob.jouwKeuze].
    final vast = job.jouwKeuze;
    final ranked = keuze == null
        ? ([...candidates]..sort(_rankSlsk))
        : [keuze, ...candidates.where((c) => c.username != keuze.username || c.filename != keuze.filename)];

    /// Wat de spectrumproef vindt van het bestand dat er ná dit alles LIGT.
    ///
    /// Dit is het enige harde gegeven in deze hele keten. Vóór het binnenhalen valt er niets te
    /// weten — dat is op 06-08-2026 gemeten en staat bij [_rankSlsk] — maar zodra het bestand er
    /// ligt is het geen vermoeden meer.
    ///
    /// Nadrukkelijk het bestand dat BLIJFT, niet het bestand dat binnenkwam. Die twee lopen uiteen
    /// zodra er al een kopie lag: dan gooit `placeFileDetailed` de zwakste weg, en dat kan de
    /// binnengekomene zijn. Gemeten op 06-08 met Stromae — Tous les mêmes: er kwam een opgeblazen
    /// kopie binnen, die verloor meteen van het schone bestand dat er lag, en toch begon de jacht.
    /// Vijfenveertig peers afgegaan om iets te vervangen wat al in orde was.
    Echtheidsoordeel? oordeelVanWatErLigt;

    /// Waarom de laatste poging niets opleverde, in de woorden van de peer.
    ///
    /// **Dit bestond al en kwam nergens aan.** Elke poging eindigt in een [SlskFail] met een reden —
    /// "Geweigerd: ...", "Uploader niet bereikbaar (firewall)", "Geen reactie (slot bezet of
    /// offline)" — of in een plaats in een wachtrij die na een halfuur nog niet aan de beurt was. Dat
    /// ging naar het logboek en verder nergens heen: op het scherm stond alleen "mislukt", en dat is
    /// precies de vraag "wat wil dat zeggen?" waar niemand een antwoord op kon geven zonder een
    /// logbestand open te trekken.
    String? laatsteReden;

    /// Shared success path: file the track away tidily (Albums/Singles/Compilaties per artist)
    /// before the rescan picks it up, so the library never sees the loose landing-zone copy.
    Future<bool> succeed(SlskDone res) async {
      final staged = File(res.path);
      var how = Placement.stuck;
      try {
        // Koos de gebruiker dit bestand zelf, dan wordt het NU al onthouden — vóór het filen, want
        // tijdens het filen wordt er al vergeleken. Andersom kwam het net te laat: `placeFileDetailed`
        // zet de nieuwe kopie tegen wat er ligt, en zonder bescherming besliste de grootte. Zo belandde
        // de handmatig gekozen L'été indien in `_dubbel`.
        if (vast) await onthoudVasteKeuze(staged.path);
        // METEN VÓÓR HET FILEN, om exact dezelfde reden als de regel hierboven: `placeFileDetailed`
        // vergelijkt tijdens het landen, en `firstIsBetter` kijkt dan al naar het oordeel. Een mp3 die
        // naar FLAC is omgezet is vaak GROTER dan het origineel — gemeten 76 MB tegen 34 MB — en zou
        // zonder deze meting winnen op grootte.
        //
        // Een halve seconde op een download die seconden tot minuten duurde is onzichtbaar, en een
        // mislukte meting kost niets: dan is er simpelweg geen oordeel.
        await _meetEchtheid(staged);
        final uit =
            await placeFileDetailed(staged, _downloadsRoot, tags: job.authority, staatAl: mapVanBestaande);
        how = uit.how;
        // Pas HIER, want `uit.path` is het bestand dat blijft — bij `moved` de nieuwe kopie (het
        // oordeel is meeverhuisd), bij `duplicate` de kopie die er al lag en gewonnen heeft.
        oordeelVanWatErLigt = gemeten(uit.path);
        // En na afloop op het pad waar hij écht ligt. `_move` verhuist de markering mee, maar bij
        // `Placement.duplicate` is de bron verwijderd en is `uit.path` de kopie die bleef staan — die
        // hoort de bescherming niet zomaar te erven.
        if (vast && how == Placement.moved) await onthoudVasteKeuze(uit.path);
      } catch (_) {/* leave it where it landed — the scan still finds it */}
      job.progress = 1;
      job.status = 'done';
      job.queuePlace = 0;
      // Say what actually happened. A plain "Klaar" on a track that turned out to be a duplicate
      // (and was therefore discarded) reads as "added to your library" when nothing was added.
      job.detail = switch (how) {
        Placement.moved => null,
        Placement.duplicate => 'had je al — beste versie behouden',
        Placement.stuck => 'gedownload, maar tags onleesbaar — staat in _inkomend',
      };
      notifyListeners();
      try {
        await onLibraryChanged();
      } catch (_) {/* library rescan hiccup shouldn't un-succeed the download */}
      return true;
    }

    Future<SlskResult> attempt(SoulseekFile f,
        {required bool wait, SlskCancel? cancel, void Function()? onQueued, bool Function()? claim}) async {
      final t0 = DateTime.now();
      SlskResult uit;
      try {
        uit = await _rawTransfer(session, f, job, () => onQueued?.call(),
            waitInQueue: wait, cancel: cancel, claim: claim);
      } catch (_) {
        uit = SlskFail('Downloadfout'); // unexpected throw → a failed attempt, keep going
      }
      final duur = DateTime.now().difference(t0);
      _log.line('   ${f.username}: ${_uitkomst(uit)}  na ${_kort(duur)}${_tempo(uit, duur)}');
      return uit;
    }

    // Three pools, raced in this order. A race is won by whoever SENDS first, not by whoever is
    // best, so quality has to be decided by which pool runs — not by sorting inside one. Racing
    // surround alongside stereo did exactly what it sounds like: a free 5.1 rip beat every stereo
    // peer, landed 103 MB, and the upgrade chase then fetched the 32 MB stereo copy anyway.
    //
    // Bij een handmatige keuze vervalt de hele indeling: één bak, één ronde. Anders zou een bewust
    // aangeklikte MP3 pas in de derde ronde aan bod komen, nadat elke lossless kopie van iets anders
    // geprobeerd is — en dat is de overrule die weg moest.
    final stereo = keuze != null
        ? ranked
        : ranked.where((f) => isLossless(f) && !isMultichannel(f)).toList();
    final surround =
        keuze != null ? <SoulseekFile>[] : ranked.where((f) => isLossless(f) && isMultichannel(f)).toList();
    // An MP3 stays what it has always been here: an absolute last resort, never a shortcut — so a
    // free MP3 does NOT beat waiting for a FLAC.
    final lossy = keuze != null ? <SoulseekFile>[] : ranked.where((f) => !isLossless(f)).toList();

    // De eerste vraag bij "hij kwam niet binnen" is of er überhaupt iets te halen was. Zonder deze
    // regel is "geen kandidaat gevonden" niet te onderscheiden van "wel gevonden, maar afgebroken".
    _log.line(keuze != null
        ? '"${job.name}": VASTE KEUZE van ${keuze.username}, ${ranked.length} peers met exact dit bestand'
        : '"${job.name}": ${ranked.length} kandidaten '
            '(stereo ${stereo.length}, surround ${surround.length}, lossy ${lossy.length})');
    for (final f in ranked.take(3)) {
      _log.line('   beste: ${f.username}  ${f.displayName}  '
          '${isLossless(f) ? "lossless" : "lossy"}  wachtrij=${f.queueLength} vrij=${f.freeSlots}');
    }

    /// Ask every candidate peer and let the FIRST ONE THAT ACTUALLY SENDS win.
    ///
    /// This is what clicking twenty sources by hand in the native client does. The earlier version
    /// only asked [_probeWidth] at a time and, worse, threw away any peer that answered "you're in
    /// my queue" — those went on a list that was walked one at a time, minutes later. So a peer
    /// that would have come up in ten seconds was dropped, the counter marched to 20/20, and it
    /// looked as though only the last peer ever counted.
    ///
    /// Now a queue answer costs a peer nothing: it keeps waiting in the background while the
    /// window moves on to the next one. Within half a minute every candidate is engaged at once
    /// and whoever comes up first takes it. All of them ride the ONE shared login — twenty peer
    /// sockets, zero extra logins.
    Future<(SlskDone, SoulseekFile)?> race(List<SoulseekFile> pool, String label) async {
      final cap = identical(pool, lossy) ? _maxLossyTries : _maxLosslessTries;
      final order = sweepOrderFor(pool, first: keuze);
      final n = order.length < cap ? order.length : cap;

      SlskDone? winner;
      SoulseekFile? winnerFile;
      SoulseekFile? leader; // the peer currently sending; owns the progress line
      final decided = Completer<void>();
      final runners = <Future<void>>[];
      var asked = 0, queued = 0, cursor = 0;

      void paint() {
        // Never after a stop: cancelJob has already written the final word, and overwriting it
        // left the job looking busy forever.
        if (leader != null || winner != null || job.cancelled) return; // the sending peer owns the line
        job.status = 'waiting';
        job.progress = 0;
        job.queuePlace = 0;
        job.detail = '$label · $asked van $n gevraagd, $queued in de wachtrij';
        _meldVoortgang();
      }

      Future<void> run(SoulseekFile f, Completer<void> moveOn) async {
        final c = SlskCancel();
        job.live.add(c);
        asked++;
        paint();
        // Counted once. A queued peer re-reports its position every 30 seconds, so counting each
        // report had the line climbing to "137 in de wachtrij" out of twenty peers.
        var inLine = false;
        final res = await attempt(
          f,
          wait: true,
          cancel: c,
          // Queued is no longer a dead end — this peer stays in line while the window moves on.
          onQueued: () {
            if (!inLine) {
              inLine = true;
              queued++;
            }
            if (!moveOn.isCompleted) moveOn.complete();
            paint();
          },
          claim: () {
            if (leader == null) {
              leader = f;
              return true;
            }
            c.cancel(); // someone else is already sending — don't burn bandwidth alongside them
            return false;
          },
        );
        job.live.remove(c);
        // Vasthouden waaróm deze peer niets leverde. De laatste die iets zegt wint: bij één vaste
        // keuze is dat de enige peer die er is, en bij een race is de laatste even willekeurig als
        // elke andere — maar één echte reden is oneindig veel meer dan "mislukt".
        if (res is SlskFail) {
          laatsteReden = '${f.username}: ${res.reason}';
        } else if (res is SlskQueued && !job.cancelled) {
          laatsteReden = res.place > 0
              ? '${f.username} liet ons een halfuur op plaats ${res.place} staan'
              : '${f.username} hield ons een halfuur in de wachtrij';
        }
        if (inLine) queued--; // this peer gave up its place; the line really is shorter
        if (!moveOn.isCompleted) moveOn.complete();
        if (res is SlskDone) {
          if (winner == null) {
            winner = res;
            winnerFile = f;
            // Now everything else is redundant. Anything BETTER than this copy is still on the
            // list the upgrade chase walks afterwards, so quality is parked, not thrown away.
            for (final live in [...job.live]) {
              live.cancel();
            }
            if (!decided.isCompleted) decided.complete();
          } else {
            // Two finished in the same instant. The loser's file is complete but unwanted: bin it,
            // or it sits in staging forever — the library scan skips that folder.
            await _discardStaged(res.path);
          }
          return;
        }
        // The peer that was sending died on us. Release the line so another runner can take over
        // rather than leaving the job frozen on a name that stopped sending.
        if (identical(leader, f)) {
          leader = null;
          paint();
        }
      }

      /// Starts runners; each slot frees the moment its peer is merely queued, so the whole
      /// shortlist ends up engaged instead of four at a time.
      Future<void> feeder() async {
        while (winner == null && !job.cancelled) {
          final i = cursor++;
          if (i >= n) return;
          final moveOn = Completer<void>();
          final r = run(order[i], moveOn);
          runners.add(r);
          await Future.any([r, moveOn.future]);
        }
      }

      paint();
      final feeders = List.generate(_probeWidth, (_) => feeder());
      await Future.wait(feeders);
      // Everyone has been asked and nobody is sending, so this job is now just holding places in
      // other people's queues: hand the parallel slot to the next download. Releasing it on the
      // FIRST queued peer (as the old sequential wait did) meant a twelve-track album could have
      // every track racing twenty peers at once — the cap stopped capping anything.
      if (winner == null) releaseSlot();
      // Now sit on the ones still queued until one comes up.
      if (winner == null && !job.cancelled && runners.isNotEmpty) {
        await Future.any([Future.wait(runners), decided.future]);
      }
      if (winner != null) {
        // Return the winning FILE too: which copy we settled for is what decides whether a better
        // one is still worth chasing.
        return (winner!, winnerFile!);
      }
      return null;
    }

    /// Finish, and if what we settled for is beaten by another candidate, chase that in the
    /// background. Reached from EVERY success path — the copy most worth upgrading is the MP3
    /// we only took because no lossless could be had.
    Future<bool> finish(SlskDone res, SoulseekFile from) async {
      final ok = await succeed(res);
      // Bij een handmatige keuze: niets van dit alles. "Beter" is hier een ánder bestand, en de
      // gebruiker heeft juist gezegd dat hij DIT wil. Dagen later alsnog vervangen door een kopie die
      // hoger scoort is dezelfde overrule, alleen trager.
      //
      // Sinds 29-08-2026 geldt dat ook voor een heel album dat je zelf uit een lijst koos, en dat is
      // met zoveel woorden gevraagd. De prijs staat erbij en is echt: haal je een mp3-album omdat er
      // op dat moment geen lossless was, dan gaat de app er daarna niet meer zelf achteraan.
      if (vast) return ok;
      var better = ranked.where((f) => clearlyBetter(f, from)).toList();
      // BETRAPT BIJ HET LANDEN. Dan deugt "beter" niet meer als maatstaf, want de kopie die we
      // namen had juist de MEESTE bits — dat is precies waarom hij won. `clearlyBetter` vindt hier
      // dus niets en de jacht bleef achterwege, terwijl er honderden andere kandidaten klaarstonden.
      //
      // Wat vóór het binnenhalen niet kon, kan nu wel: er ligt een gemeten oordeel. Elke ANDERE
      // kandidaat is het proberen waard — niet omdat hij beter scoort, maar omdat deze aantoonbaar
      // niet is wat hij beweert. Wie wint beslist `firstIsBetter` als de tweede kopie landt, en die
      // kent `bewezenNep`: de betrapte verliest daar ook als hij groter is.
      //
      // Kandidaten die hetzelfde bestand zijn vallen af. Dezelfde upload nog eens halen levert
      // hetzelfde oordeel op, en dat is de bandbreedte niet waard.
      if (ok && (oordeelVanWatErLigt?.isNep ?? false)) {
        final anders = andereKopieDan(ranked, from);
        if (anders.isNotEmpty) {
          _log.line('"${job.name}": wat er nu ligt is betrapt (${waarom(oordeelVanWatErLigt!)}) — '
              '${anders.length} andere kandidaten, jacht op een echte');
          better = anders;
        }
      }
      if (ok && better.isNotEmpty) _queueUpgrade(better, job);
      // FLAC is koning. Landde er lossy, dan blijft de FLAC gewenst -- ook als er vandaag geen enkele
      // lossless bron was, want morgen staat er een andere peer online. Dat is niet theoretisch:
      // gemeten op één nummer waar de enige lossless peer het account geband had, en een dag later
      // leverde een andere hem in twee seconden.
      //
      // Bewust hier en niet bij _queueUpgrade: die vuurt alleen als er NU een betere bron in de lijst
      // staat, en juist het geval zonder kandidaat is het geval dat een staande wens nodig heeft.
      if (ok && !isLossless(from)) await _wantLossless(job, from);
      return ok;
    }

    // ── 1. Stereo lossless: the thing you actually want ──────────────────────
    final first = await race(stereo, 'poging');
    if (first != null) return finish(first.$1, first.$2);

    if (job.cancelled) return false;

    // ── 2. Surround — lossless, but it downmixes on a stereo system and costs ten times the space
    if (surround.isNotEmpty) {
      job.detail = 'alleen surround beschikbaar — 5.1 als tweede keus';
      notifyListeners();
      final second = await race(surround, '5.1-poging');
      if (second != null) return finish(second.$1, second.$2);
      if (job.cancelled) return false;
    }

    // ── 3. Only now, lossy — an MP3 is a last resort, never a shortcut ───────
    if (lossy.isNotEmpty) {
      job.detail = 'geen lossless beschikbaar — MP3 als laatste optie';
      notifyListeners();
      final third = await race(lossy, 'MP3-poging');
      if (third != null) return finish(third.$1, third.$2);
    }

    job.queuePlace = 0;
    // Don't rewrite the user's own stop as an uploader failure and invite them to retry.
    if (job.cancelled) {
      job.status = 'failed';
      notifyListeners();
      return false;
    }

    // NIET opgeven. Een peer die nu niet levert is meestal een peer die slaapt, en morgen staat hij
    // er weer — dat is precies waarom de wenslijst bestaat, en waarom de native client gewoon in de
    // wachtrij blijft staan. "Mislukt" en dan niets meer was het gat: het enige wat er nog gebeurde
    // was dat de gebruiker het zelf moest onthouden.
    final opDeLijst = await _wensNaMislukking(job, keuze);
    // Bij een vaste keuze is "geen enkele bron leverde" misleidend: er is niet gezocht, er is
    // precies één bestand geprobeerd.
    final reden = laatsteReden ??
        (keuze != null ? 'deze kopie kwam niet binnen' : 'geen enkele bron leverde');
    job.status = opDeLijst ? 'later' : 'failed';
    job.detail = opDeLijst
        ? '$reden — blijft op de lijst, de app probeert het vanzelf opnieuw'
        : '$reden — kies een andere regel in de lijst';
    notifyListeners();
    return false;
  }

  /// Een mislukte download op de wenslijst zetten, zodat hij vanzelf opnieuw geprobeerd wordt.
  ///
  /// Twee soorten wens, en het verschil is het hele punt:
  ///
  /// * **Zelf een regel aangeklikt** — dan wordt PRECIES dat bestand bij PRECIES die peer onthouden.
  ///   Morgen iets anders van hetzelfde nummer halen zou de overrule zijn die de gebruiker net had
  ///   weggeklikt: hij koos die regel juist omdat de automaat de verkeerde opname pakte.
  /// * **Gewoon gedownload** — dan wordt het nummer onthouden en morgen opnieuw gezocht, want dan
  ///   gaat het om de muziek en niet om die ene peer.
  ///
  /// Geeft terug of er iets op de lijst staat. Onwaar betekent: er valt niets te onthouden — geen
  /// gekozen bestand én geen artiest+titel om op te zoeken. Dan is "kies een andere regel" wél het
  /// eerlijke antwoord.
  Future<bool> _wensNaMislukking(DownloadJob job, SoulseekFile? keuze) async {
    final t = job.authority;
    final heeftNaam =
        t != null && t.artist.trim().isNotEmpty && t.title.trim().isNotEmpty;
    if (keuze == null && !heeftNaam) return false;

    await _ensureWants();
    final nu = DateTime.now().millisecondsSinceEpoch;
    final wens = LosslessWant(
      artist: heeftNaam ? t.artist.trim() : '',
      title: heeftNaam ? t.title.trim() : '',
      album: heeftNaam ? t.album : '',
      sinceMs: nu,
      // Eén poging is er net geweest, en die kostte een halfuur. Op nul beginnen zou betekenen dat
      // de eerstvolgende ronde meteen weer bij dezelfde slapende peer aanklopt.
      tries: 1,
      lastTryMs: nu,
      authority: heeftNaam ? t : null,
      performer: heeftNaam ? performerFromFilename(job.name, t.title) : null,
      exact: keuze == null
          ? null
          : VasteBron(
              username: keuze.username,
              filename: keuze.filename,
              size: keuze.size,
              bitrate: keuze.bitrate,
              durationSec: keuze.durationSec,
              sampleRate: keuze.sampleRate,
              bitDepth: keuze.bitDepth,
            ),
    );
    // Vastleggen vóórdat hij op de lijst gaat, zodat het kruisje op die rij weet wat het moet
    // vergeten — ook als de wens er al stond.
    job.wensSleutel = wens.key;
    final nieuw = _wants.want(wens);
    if (nieuw) {
      await _wants.save();
      _log.line('"${job.name}": niets binnen — op de lijst, volgende poging over '
          '${_kort(wachtVoor(1))} (${_wants.count} op de lijst)');
    }
    // Ook als hij er al stond staat hij op de lijst, en dat is wat het scherm meldt.
    return true;
  }

  /// Identity of a track across peers: the filename without its track number, plus the running
  /// time rounded to five seconds. Two peers' copies of one song agree on both; two different
  /// songs that merely share a title ("Intro") almost never do.
  static String _trackIdOf(SoulseekFile f) {
    final name = trackNameKey(f.displayName);
    if (name.isEmpty) return '';
    final secs = f.durationSec ?? 0;
    return secs > 0 ? '$name|${(secs / 5).round()}' : name;
  }

  /// Drop the empty per-peer folders a race leaves behind. Each attempt tidies up after itself,
  /// but with twenty running at once those deletes collide, and one leftover folder per peer ever
  /// tried adds up. Only empty ones: a folder that still holds a file is somebody's download.
  Future<void> _pruneStaging() async {
    final root = Directory('$_downloadsRoot${Platform.pathSeparator}_inkomend');
    try {
      await for (final e in root.list()) {
        if (e is! Directory) continue;
        try {
          await e.delete(); // non-recursive: throws if anything is in it
        } catch (_) {/* not empty — leave it */}
      }
    } catch (_) {/* no staging folder yet */}
  }

  /// Bin a completed file we turned out not to want, and the staging folder it came in.
  Future<void> _discardStaged(String path) async {
    try {
      final f = File(path);
      await f.delete();
      await f.parent.delete();
    } catch (_) {/* already gone, or the folder still holds something */}
  }

  /// Eén regel per uitkomst, kort genoeg om honderd pogingen naast elkaar te kunnen lezen.
  static String _uitkomst(SlskResult r) => switch (r) {
        SlskDone() => 'GELEVERD',
        SlskQueued(place: final p) => 'in de wachtrij${p > 0 ? " (plaats $p)" : ""}',
        SlskCancelled() => 'gestopt',
        // Geen vangnet-tak: SlskResult is gesloten, dus als er ooit een uitkomst bijkomt hoort de
        // compiler te klagen in plaats van hem stil als "onbekend" weg te schrijven.
        SlskFail(reason: final w) => 'mislukt: $w',
      };

  /// Hoeveel megabytes er per seconde binnenkwamen — het getal dat er tot nu toe niet was.
  ///
  /// Het logboek noteerde alleen "GELEVERD na 30s", zonder bytes, en dan valt er geen tempo uit af te
  /// leiden. Daarmee is de vraag "helpt parallel downloaden?" onbeantwoordbaar: je ziet niet of de
  /// lijn vol zit of dat één peer gewoon traag is. Gemeten op deze lijn: één stroom haalt 0,73 MB/s
  /// en acht stromen samen 3,96 MB/s — dus de lijn is niet de rem, de losse verbinding wel. Zonder
  /// dit getal in het logboek is dat achteraf niet na te rekenen op een échte download.
  ///
  /// Alleen bij een geslaagde overdracht: bij een afgebroken poging is er geen bestand om te wegen,
  /// en een tempo over nul bytes zegt niets.
  static String _tempo(SlskResult r, Duration d) {
    if (r is! SlskDone || d.inMilliseconds <= 0) return '';
    int bytes;
    try {
      bytes = File(r.path).lengthSync();
    } catch (_) {
      return '';
    }
    if (bytes <= 0) return '';
    final mb = bytes / 1048576;
    return '  ${mb.toStringAsFixed(1)} MB, ${(mb / (d.inMilliseconds / 1000)).toStringAsFixed(2)} MB/s';
  }

  static String _kort(Duration d) =>
      d.inMinutes >= 1 ? '${d.inMinutes}m${d.inSeconds % 60}s' : '${d.inSeconds}s';

  // ── FLAC is koning: de staande wens ──────────────────────────────────────
  //
  // De eenmalige jacht hierboven blijft staan voor de snelle winst -- als er NU een betere bron is,
  // is tien minuten wachten de beste kans. Wat eronder ligt is het lange spel: een lijst die een
  // herstart overleeft en dagen blijft proberen, omdat peers per dag wisselen.

  late final LosslessWants _wants =
      LosslessWants('$_appDir${Platform.pathSeparator}lossless_wanted.json');
  bool _wantsLoaded = false;
  bool _sweeping = false;

  Future<void> _ensureWants() async {
    if (_wantsLoaded) return;
    _wantsLoaded = true;
    await _wants.load();
  }

  /// Hoeveel nummers wachten er nog op hun FLAC. Voor het scherm en voor het logboek.
  int get losslessWanted => _wants.count;

  /// Hier hoeft niet meer naar gezocht te worden.
  ///
  /// **Zonder dit komt een weggegooid nummer terug.** Landt een radiohaal als mp3, dan zet
  /// [_wantLossless] hem op de verlanglijst; twintig minuten later haalt [sweepLosslessWants] alsnog
  /// de FLAC — van een nummer dat je zojuist met een rode duim hebt weggedaan. Dat is niet alleen
  /// vervelend, het is onbegrijpelijk: je hebt het weggegooid en het staat er weer.
  Future<void> vergeetWens(String artiest, String titel) async {
    if (titel.trim().isEmpty) return;
    await _ensureWants();
    final sleutel = '${normKey(artiest)}|${normKey(titel)}';
    if (_wants.forget(sleutel)) {
      await _wants.save();
      _log.line('wens "$artiest — $titel" vervallen: weggedaan met een duim omlaag');
    }
  }

  /// Zet dit nummer op de lijst. De TAGS beslissen wat er gezocht wordt, niet de bestandsnaam van de
  /// peer: die heet bij de een "215 - sabien tiels - trein.flac" en bij de ander "5-03 Sabien Tiels -
  /// Trein.mp3", en daar valt geen zoekvraag van te maken.
  Future<void> _wantLossless(DownloadJob job, SoulseekFile landed) async {
    final t = job.authority;
    if (t == null || t.artist.trim().isEmpty || t.title.trim().isEmpty) {
      _log.line('"${job.name}": lossy geland, maar zonder artiest+titel valt er niets te wensen');
      return;
    }
    if (haveLossless?.call(t.artist, t.title) ?? false) return; // je hebt hem al, elders
    await _ensureWants();
    final nieuw = _wants.want(LosslessWant(
      artist: t.artist.trim(),
      title: t.title.trim(),
      album: t.album,
      sinceMs: DateTime.now().millisecondsSinceEpoch,
      // Het gezag van DEZE landing gaat mee: de FLAC die de mp3 dagen later vervangt hoort op dezelfde
      // plek en met dezelfde nummering te belanden, ook als de peer een bestand zonder tags stuurt.
      authority: t,
      // En de naam waar peers hun bestand naar noemen, uit de bestandsnaam van deze peer. Op een
      // verzamelaar is dat de enige echte artiestennaam die er te vinden is.
      performer: performerFromFilename(landed.displayName, t.title),
    ));
    if (nieuw) {
      await _wants.save();
      _log.line('"${job.name}": lossy geland — FLAC blijft gewenst '
          '(${_wants.count} op de lijst)');
    }
  }

  /// Loop de wensen af die aan de beurt zijn, met een VERSE zoekopdracht per wens.
  ///
  /// Vers zoeken is het hele punt. De opgeslagen kandidaten van gisteren zijn de peers van gisteren;
  /// resumePending doet het hierom al zo, en dat is precies waarom een hervatte download vandaag een
  /// andere peer vond die in twee seconden leverde waar de enige van gisteren geband bleek.
  Future<int> sweepLosslessWants() async {
    if (_sweeping) return 0;
    _sweeping = true;
    try {
      await _ensureWants();
      final have = haveLossless;
      if (have != null) {
        final weg = _wants.forgetWhatWeHave(have);
        if (weg.isNotEmpty) {
          await _wants.save();
          _log.line('wensen: ${weg.length} vervallen — die FLAC staat al in de bibliotheek');
        }
      }
      final nu = DateTime.now().millisecondsSinceEpoch;
      final rij = _wants.due(nu);
      if (rij.isEmpty) return 0;
      _log.line('wensen: ${rij.length} van ${_wants.count} aan de beurt');
      var gehaald = 0;
      for (final w in rij) {
        if (await _chaseWant(w)) gehaald++;
      }
      await _wants.save();
      return gehaald;
    } finally {
      _sweeping = false;
    }
  }

  /// Eén wens: zoek opnieuw, sla geweigerde peers over, en probeer de beste lossless.
  Future<bool> _chaseWant(LosslessWant w) async {
    // Een wens om één bepaald bestand zoekt niet en vervangt niets: hij klopt opnieuw aan.
    if (w.exact != null) return _chaseExact(w);
    List<SoulseekFile> hits;
    try {
      hits = await soulseek.search(w.query);
    } catch (_) {
      return false; // geen net; de wens blijft staan en het ritme schuift niet op
    }
    final lossless = hits
        .where((f) => isLossless(f) && !isMultichannel(f))
        .where((f) => !w.refused.containsKey(f.username))
        .toList()
      ..sort(_rankSlsk);
    _log.line('wens "${w.artist} — ${w.title}": ${hits.length} treffers, '
        '${lossless.length} bruikbaar lossless (poging ${w.tries + 1}'
        '${w.refused.isEmpty ? "" : ", ${w.refused.length} peers overgeslagen"})');
    if (lossless.isEmpty) {
      _wants.update(w.met(tries: w.tries + 1, lastTryMs: DateTime.now().millisecondsSinceEpoch));
      return false;
    }

    final job = DownloadJob(w.title);
    final geweigerd = Map<String, String>.of(w.refused);
    var goed = false;
    try {
      await soulseek.withSession((session) async {
        for (final f in lossless.take(4)) {
          final t0 = DateTime.now();
          SlskResult res;
          try {
            // Ruim wachten mag hier: deze jacht houdt geen downloadslot bezig en er zit niemand op te
            // wachten. Een plaats in een wachtrij is waardevol -- weggooien is wat de app hiervoor deed.
            res = await _rawTransfer(session, f, job, () {},
                waitInQueue: true, maxWait: const Duration(minutes: 30));
          } catch (_) {
            continue;
          }
          final duur = DateTime.now().difference(t0);
          _log.line('   ${f.username}: ${_uitkomst(res)}  na ${_kort(duur)}${_tempo(res, duur)}');
          if (res is SlskFail) {
            final reden = res.reason.toLowerCase();
            // Onthouden, want de enige lossless bron voor een nummer kan er één zijn. Zonder dit
            // verbrandt elke ronde zijn poging op dezelfde peer die het account geband heeft.
            if (reden.contains('banned') || reden.contains('geweigerd')) {
              geweigerd[f.username] = 'banned';
            } else if (reden.contains('firewall')) {
              geweigerd[f.username] = 'firewall';
            }
            continue;
          }
          if (res is! SlskDone) continue;
          try {
            // Het gezag van de wens, niet dat van dit wegwerp-job: een peer stuurt geregeld een
            // bestand zonder één tag, en dan landt het als "Onbekende artiest" in Singles. Precies wat
            // de eerste echte vondst deed voordat dit erin stond.
            await placeFileDetailed(File(res.path), _downloadsRoot,
                tags: w.authority ??
                    TrackTags(title: w.title, artist: w.artist, album: w.album, trackNo: 0),
                staatAl: mapVanBestaande);
          } catch (_) {/* de scan vindt hem waar hij ook landde */}
          goed = true;
          return;
        }
      });
    } catch (_) {/* niets verloren: je houdt de kopie die je had */}

    if (goed) {
      _wants.forget(w.key);
      _log.line('wens "${w.artist} — ${w.title}": FLAC binnen na ${w.tries + 1} '
          'poging${w.tries == 0 ? "" : "en"} — van de lijst');
      try {
        await onLibraryChanged();
      } catch (_) {}
      return true;
    }
    _wants.update(w.met(
        tries: w.tries + 1, lastTryMs: DateTime.now().millisecondsSinceEpoch, refused: geweigerd));
    _log.line('wens "${w.artist} — ${w.title}": nog niet — volgende poging over '
        '${_kort(wachtVoor(w.tries + 1))}');
    return false;
  }

  /// Eén nummer voor de RADIO ophalen. Geeft het pad terug waar het geland is, of null.
  ///
  /// Alleen een pad terug als het bestand **nieuw** is: een landing die op muziek terechtkwam die je
  /// al had geldt hier als mislukt. Dat lijkt streng en is de belangrijkste regel van deze functie.
  /// [placeFileDetailed] buigt de bestemming namelijk om naar je bestaande bestand zodra [staatAl]
  /// zegt dat je die opname al hebt (zie de uitleg dáár — het is wat een opwaardering naast het
  /// origineel voorkomt). Wie zo'n landing als "door de radio gehaald" zou noteren, laat het opruimen
  /// bij het afsluiten straks muziek wissen die je zélf verzameld hebt. Dat mag nooit gebeuren, en
  /// deze regel is de plek waar dat wordt tegengehouden.
  ///
  /// Verder anders dan een gewone download, en telkens met reden:
  ///
  /// * **Korte adem** ([kMaxWacht], anderhalve minuut). Een wens uit de verlanglijst mag een half uur
  ///   in de rij van een uploader staan; hier luister je NU, en zo'n haal houdt al die tijd een van de
  ///   twaalf Soulseek-plekken bezet.
  /// * **Geen rij op het scherm.** Deze taak komt niet in [jobs] en dus ook niet in
  ///   `pending_downloads.json`. Vijfhonderd regels in Mijn downloads is geen informatie, en een
  ///   herstart hoort geen weesdownloads van een radio van gisteren op te starten.
  /// * **Gezag met een LEGE albumtitel**, mét jaar en looptijd. Leeg maakt er een single van, dus
  ///   `Singles/<Artiest>/<Titel>.flac` in plaats van vijfhonderd albumtegels met één nummer erin
  ///   ([classifyRelease] geeft `album` bij élke niet-lege albumtitel). Het jaar is wat de tags
  ///   gezaghebbend maakt — zonder dat schrijft [stampTags] niets. De looptijd is de Sting-val: zonder
  ///   haar denkt de bibliotheek op artiest+titel alleen al dat je iets hebt.
  /// De haaltjes die nu voor een radio lopen.
  ///
  /// Ze staan met opzet niet in [jobs] — zie hierboven — en waren daardoor ook met niets te stoppen.
  /// Sluit je de radio af, dan liepen de laatste acht gewoon door: ze landden minuten later alsnog
  /// op je schijf, van een radio die niet meer bestond en die ze dus ook nooit meer zou opruimen.
  /// Gemeld op 29-08-2026: "vanaf de radio stopt moeten de downloads ook stoppen, want nu zinderen
  /// er nog een paar achter."
  final Set<DownloadJob> _radiohalen = {};

  /// Alles wat er voor de radio loopt onmiddellijk afbreken. Geeft terug hoeveel er weggehaald zijn.
  ///
  /// Het halfbakken bestand ruimt de overdracht zelf op: een afgebroken overdracht eindigt niet als
  /// [SlskDone], en `_cleanStaging` gooit dan weg wat er in de wachtmap stond. Er blijft dus niets
  /// achter om met de hand op te ruimen.
  int staakRadiohalen() {
    var n = 0;
    for (final job in _radiohalen) {
      if (job.cancelled) continue;
      job.cancelled = true;
      for (final c in job.live) {
        c.cancel();
      }
      job.live.clear();
      n++;
    }
    _radiohalen.clear();
    if (n > 0) _log.line('radio gestopt: $n ${n == 1 ? "haal" : "halen"} afgebroken');
    return n;
  }

  Future<String?> haalVoorRadio({
    required String artiest,
    required String titel,
    int? seconden,
    int? jaar,
  }) async {
    if (!soulseek.available) return null;
    // Heb je dit al? Dan valt er niets te halen — en, net zo belangrijk, dan mag het straks ook niet
    // opgeruimd worden. De toets staat hier VOORAF, want achteraf is het onderscheid weg.
    if (mapVanBestaande?.call(artiest, titel, seconds: seconden) != null) return null;

    // Vanaf hier is er iets te stoppen, dus vanaf hier staat het in de lijst — ook tijdens het
    // zoeken. Een zoekopdracht duurt seconden, maar het is wél het moment waarop de meeste haaltjes
    // zich bevinden als je de radio afsluit.
    final job = DownloadJob(titel); // wegwerp: bewust niet in `jobs`
    _radiohalen.add(job);
    try {
      return await _haalVoorRadio(job, artiest, titel, seconden, jaar);
    } finally {
      _radiohalen.remove(job);
    }
  }

  Future<String?> _haalVoorRadio(
      DownloadJob job, String artiest, String titel, int? seconden, int? jaar) async {
    List<SoulseekFile> hits;
    try {
      hits = await soulseek.search(zoekvraagVoorNummer(titel, artist: artiest));
    } catch (_) {
      return null; // geen net of geen aanmelding; deze plek in het plan mislukt gewoon
    }
    if (job.cancelled) return null; // de radio is afgesloten terwijl we zochten
    final bruikbaar = hits.where((f) => !isMultichannel(f)).toList()..sort(_rankSlsk);
    // Lossless eerst, precies zoals overal in deze app. Maar niet lossless-of-niets: een
    // eurodance-single uit 1993 bestaat op dit netwerk soms alleen als mp3, en dan is die mp3 beter
    // dan stilte. `_rankSlsk` heeft de beste al vooraan gezet.
    final kandidaten = [
      ...bruikbaar.where(isLossless),
      ...bruikbaar.where((f) => !isLossless(f)),
    ];
    if (kandidaten.isEmpty) {
      _log.line('radio "$artiest — $titel": ${hits.length} treffers, niets bruikbaars');
      return null;
    }

    final gezag = TrackTags(
      title: titel,
      artist: artiest,
      album: '',
      trackNo: 0,
      year: jaar,
      seconds: seconden,
    );
    String? geland;
    try {
      await _withSlsk<void>((session, _) async {
        for (final f in kandidaten.take(3)) {
          if (job.cancelled) return;
          final t0 = DateTime.now();
          SlskResult res;
          // De stopschakelaar van DEZE poging, opgeborgen waar [staakRadiohalen] hem kan vinden.
          // Zonder dit is `job.cancelled` alleen een vlag die pas tússen twee peers gelezen wordt —
          // en een overdracht die halverwege een bestand van tien megabyte zit, leest hem dan pas
          // over een minuut.
          final stop = SlskCancel();
          job.live.add(stop);
          try {
            res = await _rawTransfer(session, f, job, () {},
                waitInQueue: true, maxWait: kMaxWacht, cancel: stop);
          } catch (_) {
            continue;
          } finally {
            job.live.remove(stop);
          }
          if (job.cancelled) return;
          _log.line('radio "$artiest — $titel": ${f.username} '
              '${_uitkomst(res)} na ${_kort(DateTime.now().difference(t0))}');
          if (res is! SlskDone) continue;

          // Nog één keer kijken, vlak vóór het filen. Tussen de toets bovenaan en dit moment kan een
          // andere haal — of de jacht op een betere kwaliteit — hetzelfde nummer hebben laten landen.
          final alBekend = mapVanBestaande?.call(artiest, titel, seconds: seconden);
          PlaceOutcome uit;
          try {
            uit = await placeFileDetailed(File(res.path), _downloadsRoot,
                tags: gezag, staatAl: mapVanBestaande);
          } catch (_) {
            continue;
          }
          if (alBekend != null || uit.how != Placement.moved) {
            _log.line('radio "$artiest — $titel": geland op muziek die je al had — '
                'niet van de radio, wordt straks niet opgeruimd');
            return;
          }
          // Pas NA het landen, en dit ontbrak op de hele downloadweg: `rebuildAlbums` groepeert op de
          // tags ván het bestand, dus zonder dit vult je raster zich met de rommelalbums van de
          // uploader.
          try {
            await stampTags(File(uit.path), gezag);
          } catch (_) {/* het bestand staat goed; een mislukte tagschrijf maakt het niet stuk */}
          geland = uit.path;
          return;
        }
      });
    } catch (_) {/* niets verloren: deze plek in het plan mislukt gewoon */}
    return geland;
  }

  /// Eén wens om PRECIES dit bestand: opnieuw aankloppen bij dezelfde peer, en niets anders.
  ///
  /// Geen zoekopdracht, geen "beste lossless", geen vervanging. De gebruiker heeft die regel
  /// aangeklikt omdat de automatische keuze de verkeerde opname pakte; hier alsnog gaan zoeken zou
  /// diezelfde overrule zijn, alleen een dag later.
  ///
  /// Ruim wachten mag: deze jacht houdt geen downloadslot bezig en er zit niemand naar te kijken.
  Future<bool> _chaseExact(LosslessWant w) async {
    final b = w.exact!;
    final f = SoulseekFile(
      username: b.username,
      filename: b.filename,
      size: b.size,
      bitrate: b.bitrate,
      durationSec: b.durationSec,
      sampleRate: b.sampleRate,
      bitDepth: b.bitDepth,
    );
    final job = DownloadJob(w.title.isEmpty ? f.displayName : w.title);
    var goed = false;
    _log.line('vaste keuze "${f.displayName}" van ${b.username}: poging ${w.tries + 1}');
    try {
      await soulseek.withSession((session) async {
        final t0 = DateTime.now();
        final res = await _rawTransfer(session, f, job, () {},
            waitInQueue: true, maxWait: const Duration(minutes: 30));
        _log.line('   ${b.username}: ${_uitkomst(res)}  na ${_kort(DateTime.now().difference(t0))}');
        if (res is! SlskDone) return;
        // Dezelfde volgorde als de gewone weg: eerst onthouden dat DIT de gekozen kopie is, dan pas
        // opbergen — want tijdens het opbergen wordt er al vergeleken met wat er ligt, en zonder die
        // bescherming wint daar de grootste in plaats van de gekozene.
        try {
          await onthoudVasteKeuze(res.path);
          final uit = await placeFileDetailed(File(res.path), _downloadsRoot,
              tags: w.authority, staatAl: mapVanBestaande);
          if (uit.how == Placement.moved) await onthoudVasteKeuze(uit.path);
        } catch (_) {/* de scan vindt hem waar hij ook landde */}
        goed = true;
      });
    } catch (_) {/* geen sessie, geen net — de wens blijft gewoon staan */}

    if (goed) {
      _wants.forget(w.key);
      _log.line('vaste keuze "${f.displayName}": binnen na ${w.tries + 1} '
          'poging${w.tries == 0 ? "" : "en"} — van de lijst');
      try {
        await onLibraryChanged();
      } catch (_) {}
      return true;
    }
    _wants.update(
        w.met(tries: w.tries + 1, lastTryMs: DateTime.now().millisecondsSinceEpoch));
    _log.line('vaste keuze "${f.displayName}": nog niet — volgende poging over '
        '${_kort(wachtVoor(w.tries + 1))}');
    return false;
  }

  /// Queue a background hunt for a better copy of a track you can already play.
  void _queueUpgrade(List<SoulseekFile> better, DownloadJob job) {
    job.status = 'upgrading';
    job.detail = 'speelbaar · betere kwaliteit zoeken';
    notifyListeners();
    // Of hij meteen begint of achter een andere jacht staat, is een van de vier verklaringen voor
    // "hij kwam niet binnen" -- en de enige die je nooit op het scherm ziet.
    _log.line('"${job.name}": ${better.length} betere kandidaten, opwaarderen in de rij'
        ' (${_jachten.lopend} van $_maxParallelleJachten jachten bezig'
        '${_jachten.wachtend > 0 ? ", ${_jachten.wachtend} wachtend" : ""})');
    _jachten.voegToe(() => _chaseUpgrade(better, job));
  }


  /// Chase a BETTER copy of a track that already landed.
  ///
  /// Bounded on purpose: you HAVE the track, so this must never cost you anything. It holds the
  /// shared session for its whole run — dipping out between peers would let the 120s idle close
  /// fire and make the next attempt a fresh LOGIN, which is what gets the account blocked — and
  /// deliberately takes no download slot, so a track you have nothing of never waits behind it.
  Future<void> _chaseUpgrade(List<SoulseekFile> better, DownloadJob job) async {
    final deadline = DateTime.now().add(_upgradeBudget);
    // A shadow job absorbs the transfer's own status/progress writes: the visible job is already
    // finished and must not flip back to "Bezig 34%" with a half-full bar.
    final shadow = DownloadJob(job.name);

    void settle(String detail) {
      if (job.cancelled) return; // a stopped job must not be forced back to 'done'
      job.status = 'done';
      job.progress = 1;
      job.detail = detail;
      notifyListeners();
    }

    _log.line('"${job.name}": jacht op betere kwaliteit start, budget ${_kort(_upgradeBudget)} '
        'voor ${better.length} peers samen');
    try {
      await soulseek.withSession((session) async {
        for (final f in better) {
          if (job.cancelled) return; // the user stopped this track; don't keep chasing it
          final left = deadline.difference(DateTime.now());
          if (left <= const Duration(seconds: 30)) {
            // DE grens waar dit stukloopt, en zonder deze regel is hij van buitenaf onzichtbaar: de
            // jacht houdt gewoon op en er komt nooit iets binnen.
            _log.line('   budget op na ${_kort(_upgradeBudget - left)} — '
                '${better.length - better.indexOf(f)} peers niet meer geprobeerd');
            return;
          }
          job.status = 'upgrading';
          job.progress = 1;
          job.detail = 'speelbaar · wacht op ${f.username} voor betere kwaliteit';
          notifyListeners();

          SlskResult res;
          final c = SlskCancel();
          job.live.add(c);
          final t0 = DateTime.now();
          try {
            res = await _rawTransfer(session, f, shadow, () {}, waitInQueue: true, maxWait: left, cancel: c);
          } catch (_) {
            _log.line('   ${f.username}: fout  na ${_kort(DateTime.now().difference(t0))}'
                '  (${_kort(left)} budget over bij de start)');
            continue;
          } finally {
            job.live.remove(c);
          }
          // De looptijd naast het resterende budget: zo zie je of een peer nog aan de gang was toen
          // het budget hem afkapte, of dat hij zelf niets deed.
          final duur = DateTime.now().difference(t0);
          _log.line('   ${f.username}: ${_uitkomst(res)}  na ${_kort(duur)}${_tempo(res, duur)}'
              '  (${_kort(left)} budget over bij de start)');
          if (res is SlskCancelled) return;
          if (res is! SlskDone) continue;

          // placeFileDetailed drops the copy this supersedes — but only if it actually won.
          Placement how = Placement.stuck;
          try {
            final staged = File(res.path);
            // Meten vóór het filen, net als op de gewone landingsweg — en dit ontbrak hier.
            // `placeFileDetailed` laat `firstIsBetter` beslissen, en die kijkt naar het oordeel;
            // zonder meting was er geen oordeel en besliste de grootte. Uitgerekend op deze weg is
            // dat verkeerd om: een opgeschaalde of uit mp3 omgezette kopie is juist GROTER dan het
            // origineel, dus de jacht op iets beters kon de betere kopie weggooien.
            await _meetEchtheid(staged);
            // The SAME authority as the first landing. Without it the sweep would quietly undo the
            // numbering a quarter of an hour later, using whatever this new peer's tags happen to say.
            how = (await placeFileDetailed(staged, _downloadsRoot, tags: job.authority, staatAl: mapVanBestaande)).how;
          } catch (_) {/* the scan still finds it wherever it landed */}
          if (how == Placement.duplicate) {
            settle('had al de beste kwaliteit');
            return;
          }
          settle(how == Placement.moved
              ? 'kwaliteit verbeterd · ${f.username}'
              : 'betere kopie opgehaald, maar tags onleesbaar');
          try {
            await onLibraryChanged();
          } catch (_) {}
          return;
        }
      });
    } catch (_) {/* nothing lost — you still have the copy that landed first */}

    if (job.status == 'upgrading') {
      // Hier eindigt de jacht zonder resultaat, en dit is de regel die zegt DAT hij geëindigd is.
      // Zonder hem lijkt een opwaardering die niets vond precies op een die nog loopt -- en de app
      // begint hem niet opnieuw, ook niet na een herstart.
      _log.line('"${job.name}": jacht klaar zonder betere kopie, '
          '${_kort(_upgradeBudget - deadline.difference(DateTime.now()))} verbruikt — komt niet terug');
      settle('beste vrije kwaliteit behouden');
    }
  }

  /// The order to try peers in when hunting for one that can start RIGHT NOW.
  ///
  /// Two things the plain quality ranking got wrong, both visible on a popular track with a
  /// hundred free sources while the download sat waiting:
  ///
  /// * ONE FILE PER PEER. Ranked purely on bitrate, the top of the list is the big hi-res rips —
  ///   and those come from a handful of collectors who each offer several. Fourteen attempts then
  ///   amounted to about five actual chances, while dozens of other peers were never asked.
  /// * FREE SLOTS FIRST. A peer that says it has a slot open is the whole point of this pass.
  ///   Quality still decides between two free peers, and the background upgrade goes after the
  ///   hi-res copy afterwards — so nothing is given up, it just plays sooner.
  ///
  /// [first] is het bestand dat de gebruiker zélf aanwees. Dat moet vooraan blijven, en het mag
  /// bovenal niet door `bestPerPeer` verdwijnen: bood diezelfde peer ook een hoger scorende kopie
  /// aan, dan viel juist de aangeklikte weg — en dat was, samen met de sortering, waarom een
  /// handmatige keuze niet aankwam.
  static List<SoulseekFile> sweepOrderFor(List<SoulseekFile> pool, {SoulseekFile? first}) {
    final bestPerPeer = <String, SoulseekFile>{};
    for (final f in pool) {
      final cur = bestPerPeer[f.username];
      if (cur == null || _slskScore(f) > _slskScore(cur)) bestPerPeer[f.username] = f;
    }
    // De keuze van de gebruiker wint van "de beste van deze peer" — anders wordt hij hier alsnog
    // weggestreept door een kopie die hij niet vroeg.
    if (first != null) bestPerPeer[first.username] = first;
    final out = bestPerPeer.values.toList();
    out.sort((a, b) {
      if (a.freeSlots != b.freeSlots) return a.freeSlots ? -1 : 1;
      if (a.queueLength != b.queueLength) return a.queueLength.compareTo(b.queueLength);
      return _slskScore(b) - _slskScore(a);
    });
    if (first != null) {
      out.removeWhere((f) => f.username == first.username && f.filename == first.filename);
      out.insert(0, first);
    }
    return out;
  }

  /// Lossless (or hi-res) — the tier that may serve as a fast stand-in.
  static bool isLossless(SoulseekFile f) => _slskScore(f) >= 2000000;

  /// Worth interrupting nothing for: a real step up, not rip-to-rip noise.
  ///
  /// Two rips of the same CD differ by a few kbps as a matter of course, so a plain "higher
  /// score" would start a chase after almost every download — and then swap a perfectly good
  /// FLAC for an equally good one. Only a better TIER, or a clearly higher bitrate, counts.
  /// De kandidaten die een ÁNDERE kopie zijn dan [genomen] — waar het nog zin heeft te kijken.
  ///
  /// Nodig zodra de binnengekomen kopie betrapt is. "Beter" bestaat dan niet meer als maatstaf: die
  /// kopie won juist omdat hij de meeste bits had. Wat overblijft is: probeer iets ánders.
  ///
  /// Wat eruit valt, en waarom:
  ///  - **dezelfde upload.** Honderd peers delen hetzelfde bestand; dat nog eens halen levert
  ///    hetzelfde oordeel op en kost alleen bandbreedte. [zelfdeBestand] kijkt naar naam, grootte
  ///    en speelduur samen.
  ///  - **lossy.** Een mp3 halen omdat de FLAC uit een mp3 bleek te komen is geen vooruitgang.
  ///  - **meerkanaals.** Wordt op een stereo-installatie teruggemengd en kost tien keer de ruimte —
  ///    dezelfde afweging die de gewone rangschikking al maakt.
  static List<SoulseekFile> andereKopieDan(List<SoulseekFile> kandidaten, SoulseekFile genomen) =>
      kandidaten
          .where((f) =>
              isLossless(f) &&
              !isMultichannel(f) &&
              !zelfdeBestand(
                  f.filename, f.size, f.durationSec, genomen.filename, genomen.size, genomen.durationSec))
          .toList();

  static bool clearlyBetter(SoulseekFile candidate, SoulseekFile settled) {
    final a = _slskScore(candidate), b = _slskScore(settled);
    final tierA = a ~/ 1000000, tierB = b ~/ 1000000;
    if (tierA != tierB) return tierA > tierB;
    final kbpsA = a % 1000000, kbpsB = b % 1000000;
    return kbpsB > 0 && kbpsA > kbpsB * 1.25;
  }

  /// Root of the app's own, tidily-organised download tree. Only ever writes inside here — the
  /// user's existing collection elsewhere under musicRoot is never touched or moved.
  String get _downloadsRoot => '$musicRoot${Platform.pathSeparator}DebridMusic Downloads';

  /// A peer that never delivered leaves an empty staging folder behind; drop it so `_inkomend`
  /// doesn't slowly fill with the name of every uploader we ever tried. Non-recursive on purpose:
  /// a folder that still holds a partial file is left alone.
  Future<SlskResult> _cleanStaging(Directory dir, File dest, Future<SlskResult> transfer) async {
    final res = await transfer;
    // A loser in a race can still have finished: a small file arrives inside one chunk, so the
    // peer was told "no" only after the bytes were already on disk. Nothing downstream looks at a
    // cancelled attempt, so without this the complete file sat in _inkomend forever — and kept the
    // folder non-empty, so that never got cleaned up either.
    if (res is! SlskDone) {
      try {
        await dest.delete();
      } catch (_) {/* never created, or already gone */}
    }
    try {
      await dir.delete();
    } catch (_) {/* another track of this album is still staging here — leave it */}
    return res;
  }

  /// The raw single-peer transfer over [session] (updates progress only; no status finalization).
  /// [claim] turns this into one runner in a race: it fires the moment the peer's first bytes
  /// arrive, and returns whether this attempt gets to own the job's progress line. A runner that
  /// is told no cancels itself. Without it the attempt drives the UI on its own, as a lone
  /// download does.
  Future<SlskResult> _rawTransfer(
      SlskSession session, SoulseekFile file, DownloadJob job, void Function() onQueued,
      {bool waitInQueue = true,
      Duration maxWait = const Duration(minutes: 30),
      SlskCancel? cancel,
      bool Function()? claim}) async {
    // Land in a staging folder; placeFile() moves it into Albums/Singles/Compilaties after.
    // Per-PEER subfolder: candidates for the same track share a display name, so a slow attempt
    // that is still winding down can never write into the file the next attempt just opened.
    final dir = Directory(
        '$_downloadsRoot${Platform.pathSeparator}_inkomend${Platform.pathSeparator}${_sanitize(file.username)}');
    await dir.create(recursive: true);
    final dest = File('${dir.path}${Platform.pathSeparator}${_sanitize(file.displayName)}');
    var settled = claim == null; // no race → this attempt owns the UI from the start
    var mine = claim == null;
    // Alleen bij een VERANDERING, want een peer herhaalt zijn plaats. Zonder deze regel is een
    // download die in een wachtrij staat onzichtbaar in het logboek tot hij eindigt -- en dat is juist
    // het geval dat we willen kunnen nakijken. Bleek bij het uittesten van het logboek zelf.
    var laatstePlaats = -1;
    return _cleanStaging(dir, dest, session.download(file, dest, (rec, tot) {
      if (!settled && rec > 0) {
        settled = true;
        mine = claim!(); // first bytes decide the race; a runner told no stops itself
      }
      // A stop is final. Bytes already in flight arrive for a moment afterwards, and letting them
      // write here turned "Gestopt" back into "Bezig 34%" — leaving the job permanently busy, which
      // made the duplicate guard refuse that track for the rest of the session.
      if (!mine || job.cancelled) return;
      if (job.status != 'downloading') {
        job.status = 'downloading'; // bytes are flowing — the wait is over
        job.queuePlace = 0;
        job.detail = file.username;
        notifyListeners(); // on its own: a peer that never sends a size has no progress to report
      }
      if (tot > 0) {
        final p = (rec / tot).clamp(0.0, 1.0);
        if (p - job.progress > 0.02) {
          job.progress = p;
          _meldVoortgang();
        }
      }
    }, onStatus: (q) {
      if (q.place != laatstePlaats) {
        laatstePlaats = q.place;
        _log.line('   ${file.username}: wachtrij${q.place > 0 ? " plaats ${q.place}" : " (plaats onbekend)"}');
      }
      // In a race the job line belongs to the race, which knows about all the runners; one of
      // twenty peers announcing its queue position would just fight the other nineteen for it.
      if (claim == null) {
        job.status = 'waiting';
        job.queuePlace = q.place;
        job.detail = q.place > 0 ? 'wachten op ${file.username} · plaats ${q.place}' : 'wachten op ${file.username}';
        _meldVoortgang();
      }
      onQueued();
    }, waitInQueue: waitInQueue, maxWait: maxWait, cancel: cancel));
  }

  /// Add a torrent download. Non-blocking: a "preparing" job shows TorBox's fetch progress
  /// immediately (so a big/low-seed torrent isn't a mystery spinner), then per-file jobs
  /// start once TorBox has it ready.
  /// [klaar] is een torrent die de aanroeper AL heeft laten voorbereiden.
  ///
  /// Het nummerkeuze-venster wachtte tot TorBox de bron klaar had, liet je kiezen, en gooide dat
  /// resultaat vervolgens weg: het downloaden begon met een nieuwe `createtorrent` en een nieuwe
  /// peiling, en bij een RuTracker-bron werd het `.torrent` ook nog een tweede keer opgehaald. Je
  /// zag dus twee keer hetzelfde wachten voor één klik. Met de torrent erbij is de tweede ronde
  /// weg.
  void enqueue(SearchResult result, {int? fileId, TbTorrent? klaar}) {
    final prep = DownloadJob(fileId != null ? result.name : 'Voorbereiden: ${result.name}')..status = 'preparing';
    jobs.insert(0, prep);
    notifyListeners();
    unawaited(() async {
      try {
        final gekozen =
            klaar == null || fileId == null ? null : klaar.files.where((f) => f.id == fileId).toList();
        final (torrent, files) = gekozen != null && gekozen.isNotEmpty
            ? (klaar!, gekozen)
            : await online.resolveForDownload(result, fileId, onProgress: (p, s) {
                prep.progress = p;
                notifyListeners();
              });
        jobs.remove(prep);
        final destDir = Directory(
            '$musicRoot${Platform.pathSeparator}DebridMusic Downloads${Platform.pathSeparator}${_sanitize(torrent.name)}');
        await destDir.create(recursive: true);
        final nieuwe = <DownloadJob>[];
        for (final f in files) {
          final job = DownloadJob(f.label);
          nieuwe.add(job);
          jobs.insert(0, job);
        }
        // De bladen erbij, zonder eigen regel in de lijst: ze zijn een paar kilobyte groot en het
        // zou raar staan om "album.cue — klaar" naast je nummers te zien. Zonder deze regel is een
        // `(image+.cue)` na afloop niet meer op te knippen, want dan ligt het blad er niet.
        final cues = torrent.files.where((f) => f.isCue).toList();
        notifyListeners();
        final lopend = <Future<void>>[];
        if (torrent.lokaal) {
          // Eén opdracht voor de hele torrent, niet één per nummer: aria2 kent een torrent aan zijn
          // infohash en zou een tweede aanmelding van dezelfde plaat als dubbel weigeren. De balken
          // per nummer komen uit zijn eigen bestandslijst.
          lopend.add(_inRij(() => _downloadLokaal(torrent, files, destDir, nieuwe, cues: cues)));
        } else {
          for (var i = 0; i < files.length; i++) {
            lopend.add(_inRij(() => _download(torrent.id, files[i], destDir, nieuwe[i])));
          }
          for (final c in cues) {
            // Een eigen taak zonder plek in de lijst: hij mag mislukken zonder dat iemand er iets
            // van merkt, want dan is er simpelweg niets te knippen.
            lopend.add(_inRij(() => _download(torrent.id, c, destDir, DownloadJob(c.label))));
          }
        }
        notifyListeners();
        // Wachten tot ALLES binnen is, en dan pas kijken of dit een image met een cue was. Eerder
        // kan niet: het blad en het grote bestand komen langs verschillende wegen binnen.
        await Future.wait(lopend);
        await _knipImages(destDir, nieuwe);
      } catch (e) {
        prep.status = 'failed';
        // `_addOrFind` gooit zinnen die precies zeggen wat er misging ("TorBox nam deze bron niet
        // aan — …", "het torrentbestand kwam niet binnen bij de bron (koekje verlopen?)"). Die
        // werden hier opgevangen en weggegooid, en op het scherm bleef "Mislukt" staan.
        prep.detail = '$e';
        notifyListeners();
      }
    }());
  }

  /// Download a whole album (used by "Download album" from Soulseek), ONE TRACK AT A TIME.
  /// Each element of [tracks] is the candidate peers for one track (the same song offered by
  /// several peers) — so a track whose best peer is busy falls back to another peer instead of
  /// failing. Sequential AND single-login: the WHOLE album runs on ONE session (one login), so a
  /// 12-track album costs 1 login, not one per track/peer — the burst that tripped the block.
  /// [authorities] is parallel to [tracks]: what each one IS according to the official release,
  /// or null where nothing on that release matched. A whole folder from one peer is still one
  /// peer's idea of the record — its internal numbering is no more trustworthy than a single file's.
  Future<int> enqueueSoulseekAlbum(List<List<SoulseekFile>> tracks,
      {List<TrackTags?> authorities = const []}) async {
    if (!soulseek.available) throw 'Stel je Soulseek-login in (Instellingen).';
    final running = <Future<bool>>[];
    for (var i = 0; i < tracks.length; i++) {
      final cands = tracks[i];
      if (cands.isEmpty) continue;
      final job = DownloadJob(cands.first.displayName, status: 'queued')
        ..authority = i < authorities.length ? authorities[i] : null
        // Je hebt deze MAP van deze peer uitgekozen, dus dit is een keuze en geen gok van de app.
        // `exact` kan hier niet: per nummer staan er meer kopieën klaar voor het geval die ene peer
        // niet levert, en die uitwijk is juist waarom een albumdownload doorloopt. Zie
        // [DownloadJob.jouwKeuze].
        ..jouwKeuze = true;
      jobs.insert(0, job);
      // Start them ALL now — _withSlsk runs up to _slskMaxParallel at once on the ONE shared
      // login and queues the rest, so a whole album downloads in parallel like the native client.
      running.add(_withSlsk((s, release) => _soulseekBest(cands, job, s, release)).catchError((_) {
        job.status = 'failed';
        notifyListeners();
        return false;
      }));
    }
    notifyListeners();
    final results = await Future.wait(running);
    return results.where((ok) => ok).length;
  }

  /// Fetch one file of a torrent to disk.
  ///
  /// Two things here were only true on the happy path, and both of them put broken music in the
  /// library. The handle and the connection were closed AFTER the loop, so an aborted stream — wifi
  /// dropping, the CDN hanging up — jumped to the catch and left them open. On Windows that stray
  /// handle means the truncated file cannot be moved or deleted for the rest of the session, so the
  /// cleanup, the filing into the library and the duplicate sweep all fail on exactly the files that
  /// need them. [SoulseekClient._pump] already gets this right, with a comment saying why.
  ///
  /// And there was no size check at all: progress went to 1 and the status to 'done' regardless. A
  /// stream that ends early but cleanly is not an error anywhere in this function, so a CDN cutting
  /// off mid-file produced a forty-second track that the app called finished.
  /// De hele plaat via aria2, met per nummer zijn eigen balk.
  ///
  /// **Waarom dit naast [_download] staat en niet erin.** De TorBox-weg is een HTTP-download per
  /// bestand: één verbinding, één voortgang, klaar is klaar. Een torrent is één zwerm die alle
  /// gekozen bestanden tegelijk vult, in stukken die zich niets van bestandsgrenzen aantrekken. Wie
  /// dat in dezelfde functie propt krijgt vanzelf een balk die achteruit loopt.
  Future<void> _downloadLokaal(
      TbTorrent torrent, List<TbFile> files, Directory destDir, List<DownloadJob> jobs,
      {List<TbFile> cues = const []}) async {
    // Een gestopte taak niet opnieuw beschrijven: `cancelJob` heeft daar het laatste woord al
    // gezet ("geannuleerd"), en de lus draait daarna nog minstens één ronde.
    void alle(String status, {String? detail}) {
      for (final j in jobs.where((j) => !j.cancelled)) {
        j.status = status;
        if (detail != null) j.detail = detail;
      }
      notifyListeners();
    }

    final motor = online.aria2;
    if (!await motor.start(downloadMap: destDir.path)) {
      alle('failed', detail: motor.laatsteFout ?? 'aria2 niet gevonden');
      return;
    }

    // WAAR ARIA2 SCHRIJFT IS NIET WAAR HET HEEN MOET, en dat scheelt honderd tekens.
    //
    // De doelmap heet al naar de plaat, en aria2 maakt dáárbinnen nog een map met diezelfde naam —
    // want zo heet de torrent nu eenmaal. Bij een lange naam telt dat dubbel op:
    //
    //     D:\Flac music 2024\DebridMusic Downloads\Tears For Fears - Songs From The Big Chair
    //     (Deluxe Edition) (Deluxe) (1985 Pop Rock) [Flac 16-44]\Tears For Fears - Songs From The
    //     Big Chair (Deluxe Edition) (Deluxe) (1985 Pop Rock) [Flac 16-44]\01. ... Shout.flac
    //
    // Dat is 234 tekens, en Windows kapt op 260. Gemeten op 29-08-2026: "Failed to open the file …
    // cause: File I/O error 3" — dat is ERROR_PATH_NOT_FOUND, en er stond geen woord bij over
    // lengte. Daarna liep die hele plaat vast, want het halve bestand bleef staan.
    //
    // Dus laat aria2 in een KORTE map werken, met de infohash als naam, en verhuizen we de gekozen
    // nummers daarna naar de plaat waar ze horen. Dezelfde schijf, dus dat verhuizen kost niets.
    // De bladen mee in dezelfde zwerm. Ze horen niet bij `files` — daar hangt per element een balk
    // aan — maar wel bij wat aria2 moet ophalen, anders staat er na afloop geen cue naast het
    // albumbestand en valt er niets te knippen.
    final gekozen = [...files.map((f) => f.id), ...cues.map((f) => f.id)];
    final hash = (torrent.hash ?? '').toLowerCase();

    final werkMap = Directory(werkMapPad(destDir, hash, torrent.name));
    await werkMap.create(recursive: true);

    // EERST KIJKEN OF WE HEM ZELF AL HEBBEN, en pas daarna aanmelden.
    //
    // Dit stond andersom: aanmelden, de weigering opvangen, en aan aria2 vragen welk gid daarbij
    // hoort. Dat werkte, maar het leunde op aria2's foutpad — op de tekst van zijn weigering, op
    // `tellActive`, op zijn bereidheid een lopende taak aan te wijzen. Drie plekken waar het stil
    // fout kan gaan, voor iets wat de app zelf gewoon weet: zij heeft die taak zelf aangemeld.
    //
    // Nu onthoudt [_gidPerTorrent] dat, en is de gewone weg voor het tweede nummer van een plaat
    // geen mislukking-met-herstel meer maar één stap.
    String? gid;
    if (hash.isNotEmpty) {
      final lopend = _gidPerTorrent[hash];
      if (lopend != null && await motor.kiesErbij(lopend, gekozen)) {
        gid = lopend;
        _log.line('torrent $hash liep al (gid=$lopend) — erbij gekozen zonder nieuwe aanmelding');
      }
    }
    gid ??= await motor.voegTorrentToe(torrent.lokaleTorrent!, map: werkMap.path, kies: gekozen);

    // AANHAKEN IN PLAATS VAN OPGEVEN.
    //
    // aria2 kent een torrent aan zijn infohash en weigert een tweede aanmelding van dezelfde plaat.
    // Binnen één opdracht was dat ondervangen (één taak voor de hele torrent, zie [enqueue]), maar
    // niet tussen twee opdrachten door: haal nummer 5 van een album en daarna nummer 9 van
    // hetzelfde album, en de tweede klik meldt dezelfde torrent opnieuw aan. Dat is de weigering die
    // op 26-08-2026 als "InfoHash …" onder een mislukte download stond — en het verklaart precies de
    // klacht dat je van RuTracker geen VERSCHILLENDE nummers kon halen.
    //
    // De torrent die er al is, is niet in de weg: hij is precies wat we nodig hebben. Er wordt
    // aangehaakt op de lopende taak en het gevraagde nummer wordt aan zijn selectie toegevoegd.
    //
    // Wie er straks mag opruimen wordt niet híer bepaald maar door [_lopersPerTorrent] geteld: ook
    // de opdracht die de torrent zélf aanmeldde mag de map niet weggooien zolang er nog een tweede
    // aan hangt.
    var aanhaakReden = '';
    if (gid == null) {
      final bestaand = await motor.zoekGidVoor(hash);
      if (bestaand == null) {
        aanhaakReden = hash.isEmpty
            ? 'deze bron gaf geen infohash mee'
            : 'aria2 kende hem wel maar wilde hem niet aanwijzen';
      } else if (await motor.kiesErbij(bestaand, gekozen)) {
        gid = bestaand;
        _log.line('torrent $hash liep al (gid=$bestaand) — aangehaakt in plaats van '
            'opnieuw aangemeld');
      } else {
        aanhaakReden = motor.laatsteFout ?? 'er kon niets bij gekozen worden';
      }
    }

    // WACHTEN IS BETER DAN MISLUKKEN.
    //
    // Aanhaken is de snelle weg en werkt meestal. Maar aria2 laat `select-file` niet in alle
    // toestanden veranderen, en dan stond er "Mislukt" op een nummer dat gewoon even had kunnen
    // wachten tot de rest van de plaat binnen was. Gemeten op 26-08-2026 met Boney M: nummer 3 kwam
    // binnen, nummer 1 en 2 vielen om met "InfoHash … is already registered".
    //
    // Zodra de andere download klaar is haalt [verwijder] de torrent uit aria2, en dan gaat deze
    // aanmelding alsnog. Vier minuten is ruim voor een nummer, en eindig genoeg om niet voor eeuwig
    // een plek in de rij te bezetten.
    if (gid == null && hash.isNotEmpty) {
      alle('waiting', detail: 'wacht op een andere download van deze plaat');
      final tot = DateTime.now().add(const Duration(minutes: 4));
      while (gid == null && DateTime.now().isBefore(tot)) {
        if (jobs.every((j) => j.cancelled)) return;
        await Future<void>.delayed(const Duration(seconds: 3));
        gid = await motor.voegTorrentToe(torrent.lokaleTorrent!,
            map: werkMap.path, kies: gekozen);
      }
    }

    if (gid == null) {
      // Zeg wat er ECHT gebeurde. "InfoHash … is already registered" laat de gebruiker denken dat
      // zijn download dubbel is; de waarheid is dat de app hem niet bij de lopende torrent kreeg,
      // en waarom dat niet lukte is het enige waar iemand iets mee kan.
      final kaal = motor.laatsteFout ?? 'torrent geweigerd';
      alle('failed',
          detail: aanhaakReden.isEmpty
              ? kaal
              : 'Deze plaat wordt al opgehaald en dit nummer kon er niet bij — $aanhaakReden. '
                  '($kaal)');
      return;
    }

    _lopersPerTorrent.update(gid, (n) => n + 1, ifAbsent: () => 1);
    // Onthouden welk gid bij deze plaat hoort, zodat het VOLGENDE nummer er meteen bij kan in
    // plaats van eerst tegen een weigering aan te lopen. Weggehaald door dezelfde teller die het
    // opruimen regelt — zolang er nog iemand op deze taak hangt, is hij geldig.
    if (hash.isNotEmpty) _gidPerTorrent[hash] = gid;

    alle('downloading');
    // Dit is de eerste torrentdownload die écht te stoppen is. Bij TorBox loopt het ophalen aan hún
    // kant door en heeft de app geen handvat; hier is er een gid, en die kunnen we weghalen.
    for (final j in jobs) {
      j.canCancel = true;
    }
    var stilStaandeSeconden = 0;
    var laatstGedaan = 0;
    try {
      while (true) {
        await Future<void>.delayed(const Duration(seconds: 2));
        // Alles weggetikt? Dan heeft niemand deze zwerm nog nodig.
        if (jobs.every((j) => j.cancelled)) return;
        final s = await motor.stand(gid);
        if (s == null) continue;

        for (var i = 0; i < files.length; i++) {
          final b = s.bestand(files[i].id);
          if (b == null) continue;
          jobs[i].progress = b.voortgang;
        }
        // Zeggen wat er te zien valt: geen seeders is iets anders dan traag, en dat verschil is het
        // enige dat je kunt gebruiken om te beslissen of je op een andere bron overstapt.
        alle('downloading',
            detail: s.geenBron
                ? 'nog geen bron gevonden — zoeken in de zwerm'
                : '${s.seeders} seeders · ${s.verbindingen} verbindingen');

        if (s.klaar) break;
        if (s.stuk) {
          // Met "aria2:" ervoor, want zonder die twee woorden is niet te zien wie er spreekt. Op
          // 26-08-2026 stond er een melding op het scherm die met "InfoHash" begon, en het kostte
          // een halve avond om te bepalen of dat aria2, TorBox of de app zelf was.
          alle('failed', detail: s.fout.isEmpty ? 'aria2 stopte ermee' : 'aria2: ${s.fout}');
          return;
        }
        stilStaandeSeconden = s.gedaan > laatstGedaan ? 0 : stilStaandeSeconden + 2;
        laatstGedaan = s.gedaan;
        // Een kwartier geen enkele byte: dan is er niets om op te wachten. aria2 stopt zelf ook na
        // deze tijd (--bt-stop-timeout), maar dan zonder iemand iets te zeggen.
        if (stilStaandeSeconden >= 900) {
          alle('failed', detail: 'een kwartier lang geen byte — geen bron voor deze torrent');
          // Niet zelf weghalen: dat doet de `finally`, en alléén als er niemand anders meer op deze
          // taak hangt. Hier alvast opruimen zou een tweede nummer van dezelfde plaat meesleuren.
          return;
        }
      }

      // Binnen. aria2 zet alles onder een map met de torrentnaam; de app verwacht de bestanden los
      // in de doelmap, want dat is wat de bibliotheek straks inleest.
      final s = await motor.stand(gid);
      for (var i = 0; i < files.length; i++) {
        final b = s?.bestand(files[i].id);
        // Een nummer dat je onderweg hebt weggetikt hoort niet alsnog in je bibliotheek te landen.
        // Het stuk dat aria2 er al van had blijft in zijn eigen map staan en gaat mee in de
        // opruiming hieronder.
        if (jobs[i].cancelled) continue;
        if (b == null) {
          // Stil doorlopen stond hier, en dat is de ergste soort: `ruimOpNaTorrent` gooit aria2's map
          // zo meteen weg, dus dit nummer is dan wég terwijl zijn regel op "bezig" blijft staan.
          jobs[i].status = 'failed';
          jobs[i].detail = 'aria2 kende dit bestand niet meer';
          continue;
        }
        final bron = File(b.pad);
        if (!await bron.exists()) {
          jobs[i].status = 'failed';
          jobs[i].detail = 'aria2 meldde klaar, maar het bestand staat er niet';
          continue;
        }
        final geland = await _verhuisNaar(bron, destDir, files[i].label);
        if (geland == null) {
          jobs[i].status = 'failed';
          jobs[i].detail = 'geen vrije naam in de doelmap';
          continue;
        }
        await _jouwKeuze(geland);
        jobs[i].progress = 1;
        jobs[i].status = 'done';
      }
      // En de bladen, vóór het opruimen: `ruimOpNaTorrent` gooit de map weg die aria2 aanmaakte, en
      // een cue die daar blijft staan verdwijnt mét die map — waarna er niets meer te knippen valt.
      for (final c in cues) {
        final b = s?.bestand(c.id);
        if (b == null) continue;
        final bron = File(b.pad);
        if (await bron.exists()) await _verhuisNaar(bron, destDir, c.label);
      }
      notifyListeners();
      // Opruimen mag alleen als deze taak van ons alleen is. Hangt er nog een tweede nummer van
      // dezelfde plaat aan, dan gooit `ruimOpNaTorrent` de map weg waar dat nummer nog in staat.
      if ((_lopersPerTorrent[gid] ?? 1) <= 1) {
        await ruimOpNaTorrent(werkMap, s);
        // En de werkmap zelf: hij hoort niet in de muziekmap thuis zodra hij leeg is.
        try {
          if (await werkMap.exists()) await werkMap.delete(recursive: true);
        } catch (_) {
          // Blijft hij staan, dan is dat hooguit een lege verborgen map.
        }
      }
      await onLibraryChanged();
    } finally {
      // De torrent uit aria2 halen zodra hij klaar is: hij seedt toch niet (--seed-time=0) en een
      // lijst die volloopt met afgeronde taken maakt elke volgende vraag trager.
      //
      // Maar pas als de laatste loper weg is. Een gid dat weggehaald wordt terwijl een tweede
      // opdracht er zijn voortgang uit leest, laat die opdracht op niets wachten.
      final over = (_lopersPerTorrent[gid] ?? 1) - 1;
      if (over <= 0) {
        _lopersPerTorrent.remove(gid);
        // Ook de snelkoppeling weg, en alléén als hij nog naar ONS gid wijst: een derde nummer dat
        // ondertussen een nieuwe taak voor dezelfde plaat opzette mag hier zijn ingang niet
        // kwijtraken.
        if (_gidPerTorrent[hash] == gid) _gidPerTorrent.remove(hash);
        await motor.verwijder(gid);
      } else {
        _lopersPerTorrent[gid] = over;
      }
    }
  }

  Future<void> _download(int torrentId, TbFile f, Directory destDir, DownloadJob job) async {
    http.Client? client;
    IOSink? sink;
    File? dest;
    // Het pad waar dit bestand terechtkwam, apart bijgehouden. Niet `dest` opnieuw uitlezen na het
    // `finally`: of dat daar nog als "niet null" geldt hangt af van hoe de analyse door een
    // try/catch/finally heen redeneert, en dat is geen ding om een bouw op te laten struikelen.
    var gelandPad = '';
    var complete = false;
    try {
      final url = await online.resolveTrackUrl(torrentId, f.id);
      client = http.Client();
      final req = http.Request('GET', Uri.parse(url));
      final resp = await client.send(req).timeout(_torrentStilte);
      if (resp.statusCode < 200 || resp.statusCode >= 300) throw 'HTTP ${resp.statusCode}';
      final total = resp.contentLength ?? f.size;
      // Een vrije naam, en meteen VASTGELEGD. Dezelfde botsing als bij de torrentweg — een
      // verzamelbox heet bij elke schijf opnieuw `01 - ….flac` — maar hier komen de bestanden náást
      // elkaar binnen, dus "bestaat hij al?" is geen antwoord: twee downloads kijken dan allebei op
      // hetzelfde moment en zien allebei niets. `create(exclusive: true)` slaagt maar één keer.
      dest = await _legVast(destDir, f.label);
      if (dest == null) throw 'geen vrije naam in de doelmap';
      gelandPad = dest.path;
      sink = dest.openWrite();
      var received = 0;
      // De wachtklok staat op de STROOM en niet op het geheel: hij slaat toe als er zólang niets
      // binnenkomt, niet als het lang duurt. Een plaat van een gigabyte mag een uur doen; een
      // minuut niets is stuk.
      //
      // Hier stond niets. Een verbinding die opengaat en dan zwijgt liet de download voor eeuwig
      // op 34% staan — geen voortgang, geen fout, geen einde. En omdat alle nummers van een plaat
      // tegelijk starten, zag één zieke verbinding eruit als een plaat die vastliep.
      await for (final chunk in resp.stream.timeout(_torrentStilte)) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final p = (received / total).clamp(0.0, 1.0);
          if (p - job.progress > 0.02) {
            job.progress = p;
            _meldVoortgang();
          }
        }
      }
      // Short of what was announced is a failure, however politely the stream ended. Only when the
      // length was never announced (total <= 0) is "it ended" all we have to go on.
      complete = total <= 0 ? received > 0 : received >= total;
      if (!complete) throw 'incompleet: $received van $total bytes';
    } catch (e) {
      job.status = 'failed';
      // Hier stond alleen "Mislukt" en verder niets. Een download die afbreekt op een 403, op een
      // verlopen adres of halverwege de stroom zag er precies hetzelfde uit als een download die
      // door een tijdslimiet viel — en dan valt er niets te beslissen over wat je nu moet doen.
      job.detail = 'TorBox: $e';
      notifyListeners();
      return;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client?.close();
      // A part-file must not survive: the scanner does not skip this folder, so what is left here
      // ends up in the library as a track that stops halfway.
      if (!complete && dest != null) {
        await dest.delete().catchError((_) => dest!);
      }
    }
    // Jouw keuze, dus hij verliest straks niet van iets wat de app beter vindt. Zie [_jouwKeuze].
    if (gelandPad.isNotEmpty) await _jouwKeuze(gelandPad);
    job.progress = 1;
    job.status = 'done';
    notifyListeners();
    await onLibraryChanged();
  }

  /// Dit bestand heeft de gebruiker ZELF aangewezen, dus het verliest nooit van een automatische regel.
  ///
  /// **Waarom de torrentweg dit nodig heeft en de rest niet.** Bij Soulseek bestond dit al, maar
  /// alleen voor "haal precies dít bestand van precies díe peer" (`job.exact`). Een torrent is per
  /// definitie zo'n keuze: je hebt een uitgave uitgezocht, soms zelfs één nummer eruit. En juist die
  /// stond nergens beschermd — hij landde los in de downloadmap, en de eerstvolgende opruiming of
  /// dubbelveger liet [firstIsBetter] beslissen. Die kijkt naar formaat en grootte, dus jouw keuze
  /// verloor van iets wat de app beter vond. Gemeld op 29-08-2026: "als ik manueel download moet dit
  /// overheersen."
  ///
  /// Het kost hier niets aan opwaarderen: de jacht op een betere kwaliteit loopt alleen over Soulseek
  /// en raakt een torrentbestand nooit.
  Future<void> _jouwKeuze(String pad) async {
    try {
      await onthoudVasteKeuze(pad);
    } catch (_) {/* de download is geslaagd; de bescherming is geen voorwaarde */}
  }

  /// Een vrije naam in [destDir] pakken en meteen vastleggen, of null als er geen te vinden is.
  ///
  /// Vastleggen en niet alleen kijken: [_download] draait voor elk bestand van een plaat tegelijk,
  /// en twee downloads die allebei "bestaat hij al?" vragen krijgen allebei "nee" — waarna de een
  /// over de ander heen schrijft. `create(exclusive: true)` kan maar door één van de twee winnen.
  Future<File?> _legVast(Directory destDir, String naam) async {
    for (final kandidaat in vrijeNamen(_sanitize(naam))) {
      final doel = File('${destDir.path}${Platform.pathSeparator}$kandidaat');
      try {
        await doel.create(exclusive: true);
        return doel;
      } catch (_) {
        continue; // bezet — de volgende naam
      }
    }
    return null;
  }

  /// Eén bestand uit aria2's eigen map naar de doelmap halen. Geeft het pad terug, of null.
  ///
  /// De bibliotheek leest de doelmap; wat in de submap van aria2 blijft staan gaat straks mee in
  /// [ruimOpNaTorrent] en is dan weg.
  ///
  /// **Nooit over een ander bestand heen.** Een torrent wordt hier plat uitgepakt, dus alles gaat op
  /// zijn eigen naam naar dezelfde map — en een verzamelbox of een discografie heet bij elke schijf
  /// opnieuw `01 - ….flac`. `rename` schrijft daar zonder één woord overheen: je koos honderd
  /// nummers, er stonden er twaalf, elke taak meldde "klaar", en de originelen waren al door
  /// [ruimOpNaTorrent] opgeruimd. Zie [vrijeNamen] voor welke naam er dan gekozen wordt.
  ///
  /// De aanroepers verhuizen één voor één, dus kijken of een naam vrij is kan hier gewoon.
  Future<String?> _verhuisNaar(File bron, Directory destDir, String naam) async {
    // De map waar het bestand IN DE TORRENT stond — dat is wat "CD2" of "1965 - Poupée de cire" van
    // elkaar onderscheidt zodra de namen erin gelijk zijn.
    final ouder = bron.parent.path;
    final submap = ouder == destDir.path ? '' : laatsteMap(ouder);
    for (final kandidaat in vrijeNamen(_sanitize(naam), submap: _sanitize(submap))) {
      final doel = File('${destDir.path}${Platform.pathSeparator}$kandidaat');
      if (bron.path == doel.path) return doel.path;
      if (await doel.exists()) continue;
      try {
        await bron.rename(doel.path);
      } catch (_) {
        // Over een schijfgrens heen kan `rename` niet; dan maar kopiëren en de bron opruimen.
        await bron.copy(doel.path);
        await bron.delete().catchError((_) => bron);
      }
      return doel.path;
    }
    return null;
  }

  /// Werk in de torrentrij zetten en een Future teruggeven die afloopt als het klaar is.
  ///
  /// [Werkrij.voegToe] geeft niets terug — met opzet, want de rij hoort niet te weten wie er wacht.
  /// Maar het knippen moet wél weten wanneer álles binnen is, en de rij laat er meerdere tegelijk
  /// lopen, dus "de laatste taak" bestaat niet.
  Future<void> _inRij(Future<void> Function() werk) {
    final klaar = Completer<void>();
    _torrentRij.voegToe(() async {
      try {
        await werk();
      } finally {
        if (!klaar.isCompleted) klaar.complete();
      }
    });
    return klaar.future;
  }

  /// Is dit één groot albumbestand met een cue? Dan opknippen tot losse nummers.
  ///
  /// Zie `cue_knippen.dart` voor het waarom. Hier staat alleen wat de gebruiker ervan ziet, en dat
  /// is het punt: dit duurt op een plaat van een gigabyte een minuut of twee, en zonder een regel
  /// die dat zegt lijkt de app in die tijd te hangen.
  Future<void> _knipImages(Directory destDir, List<DownloadJob> gedaan) async {
    // Alles mislukt of weggetikt? Dan is er niets binnengekomen om te knippen.
    if (gedaan.isNotEmpty && gedaan.every((j) => j.cancelled || j.status == 'failed')) return;

    final knipper = Knipper();
    final job = DownloadJob('Nummers uit het albumbestand halen')..status = 'downloading';
    var getoond = false;

    try {
      final uit = await knipper.knipMap(destDir, onVoortgang: (n, totaal) {
        if (!getoond) {
          // Pas tonen zodra er écht geknipt wordt: bij een gewone plaat gebeurt hier niets, en dan
          // hoort er ook geen regel te verschijnen die meteen weer weggaat.
          jobs.insert(0, job);
          getoond = true;
        }
        job.progress = totaal == 0 ? 0 : n / totaal;
        job.detail = 'nummer $n van $totaal';
        notifyListeners();
      });
      if (uit.melding.isEmpty) {
        if (getoond) jobs.remove(job);
        notifyListeners();
        return;
      }
      // Een melding is er ook als het NIET gelukt is — geen ffmpeg, een blad dat niet klopte. Die
      // hoort op het scherm te komen: een plaat die stilletjes één blok blijft is precies het soort
      // stilte waar deze app genoeg van heeft gehad.
      if (!getoond) {
        jobs.insert(0, job);
        getoond = true;
      }
      job.progress = 1;
      job.status = uit.iets ? 'done' : 'failed';
      job.detail = uit.melding;
      notifyListeners();
      if (uit.iets) await onLibraryChanged();
    } catch (e) {
      if (getoond) {
        job.status = 'failed';
        job.detail = 'knippen mislukt: $e';
        notifyListeners();
      }
    }
  }

  String _sanitize(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
}

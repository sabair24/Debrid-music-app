import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max, min;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'organize.dart';
import 'lossless_want.dart';
import 'quality.dart';
import 'radiobestand.dart';
import 'radiovoorraad.dart' show RadioAlGehad, RadioLaterOpnieuw, kMaxWacht;
import 'rutracker.dart';
import 'search.dart';
import 'settings.dart';
import 'soulseek.dart';
import 'versiecontrole.dart' show kAndereVersieOnder, kZelfdeVersieVanaf;
import 'zoekladder.dart';
import 'torbox.dart';
import 'torznab.dart';
import 'redacted.dart';
import 'torrentbestand.dart';
import 'aria2.dart';
import 'cue_knippen.dart';
import 'meldrem.dart';
import 'warm_log.dart';
import 'werkrij.dart';
import 'paths.dart';
import 'audioformaten.dart' show isAudioBestand, isVerliesvrij, soortVan;
import 'echtheid.dart';
import 'enrichment.dart' show albumIsDeSingle, lijktVerzamelaar;
import 'echtheid_meter.dart';
import 'echtheid_oordelen.dart';
import 'flac_tags.dart';
import 'groeistroom.dart' show Groei;
import 'fingerprint.dart' show Fingerprinter, similarity, maybeSameRecordingScore;
import 'integriteit.dart';
import 'keuring.dart' show Heelheid, kwaliteitZin;
import 'wavpack_kop.dart' show readWvKop;
import 'tidal.dart' show TidalTrack;
import 'tidal_beter.dart' show TidalBeterUitslag, TidalMinstens, tidalMinstens;
import 'torrent_hires.dart';
import 'torrent_beter.dart' show TorrentJacht;
import 'twijfel.dart';
import 'prullenbak.dart' show heeftPrullenbak, naarPrullenbak;
import 'cachesleutel.dart' show fnv1a;
import 'kandidatenzeef.dart' show lengteVanDeMeerderheid;
import 'kopiesoort.dart';
import 'luidheid.dart' show Gemeten;
import 'luidheid_veger.dart' show meetLuidheid;
import 'soortjacht.dart';
import 'vinyl.dart' show isVinylRip, vinylAchteraan;
import 'versie_opbergen.dart';
import 'versies.dart' show versieLabel;
import 'wav_naar_flac.dart' show wavNaarFlac;
import 'tidaler.dart' show Tidaler, haalVanTidal, kTidalRadioPerUur, kiesTidalTreffers, zoekOpTidal;
import 'torbox_stand.dart';
import 'vaste_keuze.dart';
import 'vervangjacht.dart';
import 'zoekplafond.dart';

/// Hoort deze bron te worden teruggedeeld nadat je hem hebt binnengehaald?
///
/// **Op een besloten tracker is dat geen beleefdheid maar een voorwaarde.** Redacted houdt bij wat
/// je haalt en wat je teruggeeft; binnenhalen en meteen stoppen heet daar hit-and-run en kost je je
/// account. Bij Pirate Bay of Knaben kraait er geen haan naar.
///
/// Eén functie in plaats van een `==` verspreid over het bestand: komt er ooit een tweede besloten
/// tracker bij, dan staat op één plek wat "besloten" betekent.
bool bronVraagtSeeden(String bron) => bron.toLowerCase() == 'redacted';

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
  return '${doelMap.parent.path}${Platform.pathSeparator}$torrentWerkMap'
      '${Platform.pathSeparator}$kort';
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

  /// Redacted, met de sleutel uit de instellingen. Wordt bij elke vraag opnieuw gelezen, zodat een
  /// net ingevulde sleutel meteen meedoet zonder de app te herstarten.
  late final RedactedApi redacted = RedactedApi(() => settings.redactedKey);
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
    // Je eigen account op Redacted, als je er een hebt. Zie .
    RedactedSource(redacted),
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

  /// Wat er in de torrents zit die TorBox al heeft. Zie [TorBox.bestandenVanGecacht] en
  /// `torrentvoornummer.dart`: zo blijkt of een discografie het gezochte nummer echt bevat.
  Future<Map<String, List<String>>> bestandenVanGecacht(List<String> hashes) =>
      torbox.bestandenVanGecacht(hashes);

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
    // Redacted geeft geen infohash mee, dus daar is het adres de sleutel. Zonder dit valt die bron
    // buiten de cache en haalt de app hetzelfde bestand drie keer op.
    final sleutel = r.hash.isNotEmpty ? r.hash.toLowerCase() : r.torrentUrl;
    final bekend = sleutel.isEmpty ? null : _torrentCache[sleutel];
    if (bekend != null) return (bytes: bekend, stand: LokaleBron.gelukt);
    void onthoud(List<int> bytes) {
      if (sleutel.isEmpty) return;
      // Een handvol volstaat: het gaat om de paar torrents waar je op dit moment mee bezig bent, en
      // veertig kilobyte per stuk hoeft niet eindeloos mee te reizen.
      if (_torrentCache.length >= 20) _torrentCache.remove(_torrentCache.keys.first);
      _torrentCache[sleutel] = bytes;
    }

    // Redacted eerst, want daar hoort een sleutel bij en geen koekje: het adres is een API-aanroep
    // met een `Authorization`-kop, en die kent de RuTracker-weg niet.
    if (isRedactedAdres(r.torrentUrl)) {
      final bytes = await redacted.torrentBestand(redactedIdUit(r.torrentUrl));
      if (bytes != null && bytes.isNotEmpty) {
        onthoud(bytes);
        return (bytes: bytes, stand: LokaleBron.gelukt);
      }
      // Geen terugval op TorBox: Redacted geeft geen magneet en geen infohash, dus daar valt niets
      // door te geven. Zeg gewoon wat er is.
      return (bytes: null, stand: LokaleBron.geenBron);
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
    // De hash uit het BESTAND als de bron er geen meegaf (Redacted). Zonder hem denkt aria2 dat
    // twee nummers van dezelfde plaat bij verschillende torrents horen.
    final hash = r.hash.isNotEmpty ? r.hash : inhoud.infohash;
    final torrent = TbTorrent(0, inhoud.naam, hash, 'lokaal', 0, bestanden, false, false,
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
  ///
  /// **Een bestandslijst uit een `.torrent` gaat ALTIJD voor.** Ook als TorBox de torrent al in zijn
  /// cache heeft: het bestand hebben we hier, en TorBox moet antwoorden. Gemeten op 30-08-2026 met
  /// dezelfde zoekopdracht:
  ///
  ///     RuTracker, .torrent, niet bij TorBox   ->  0,2 s
  ///     RuTracker, .torrent, WEL bij TorBox    -> 25,5 s   (want dan ging hij langs TorBox)
  ///
  /// Voor het DOWNLOADEN blijft de afweging andersom staan — zie [lokaalVoor]. Wat daar telt is de
  /// snelheid van de bytes, en die komen bij TorBox van hun eigen schijf in plaats van uit een zwerm.
  /// Alleen voor het lijstje is "zelf lezen" altijd sneller, en dat kost bovendien niemand iets.
  Future<(TbTorrent, List<TbFile>)> tracklist(SearchResult r,
      {void Function(double, String)? onProgress}) async {
    // Een echt torrentbestand: lezen kan meteen, en daar is geen aria2 en geen net voor nodig.
    if (r.torrentUrl.isNotEmpty) {
      final lokaal = await _lokaleTracklist(r);
      if (lokaal != null) return lokaal;
    } else if (lokaalVoor(r)) {
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

  /// De stream-URL voor één nummer uit de keuzelijst.
  ///
  /// [resolveTrackUrl] alleen was genoeg zolang die lijst van TorBox kwam. Voor een `.torrent` komt
  /// hij sinds 30-08-2026 uit het bestand zelf ([tracklist]), en dan is [lijst] een torrent zonder
  /// TorBox-nummer (0) en nummeren de bestanden zoals het torrentbestand. Gemeten op 19-09-2026:
  /// elke ▶ in zo'n lijst gaf "Afspelen mislukt: Lege download-URL". Afspelen gaat via TorBox, dus
  /// daar wordt de torrent opgezocht en het bestand op naam en grootte gekoppeld.
  Future<String> speelUrl(SearchResult r, TbTorrent lijst, TbFile f) async {
    if (!lijst.lokaal) return resolveTrackUrl(lijst.id, f.id);
    if (!torbox.hasKey) throw 'Afspelen gaat via TorBox — stel eerst je TorBox-sleutel in (Instellingen).';
    final (id, hash) = await _addOrFind(r);
    final item = await _pollReady(id, hash, patient: !r.cached);
    final bij = zelfdeBestandIn(item.files, f);
    if (bij == null) throw 'Dit nummer staat niet in de lijst van TorBox';
    return resolveTrackUrl(item.id, bij.id);
  }

  /// Het bestand met dit nummer in de lijst die [tracklist] liet zien — maar alleen als die lijst
  /// uit het torrentbestand zelf kwam. Anders null: dan nummerde de lijst al zoals TorBox.
  ///
  /// Voor wie alleen het nummer kent. Een telefoon van vóór 3.9.403 stuurt niets anders mee.
  Future<TbFile?> _uitEigenLijst(SearchResult r, int fileId) async {
    if (r.torrentUrl.isEmpty) return null;
    try {
      final lokaal = await _lokaleTracklist(r);
      if (lokaal == null) return null;
      for (final f in lokaal.$1.files) {
        if (f.id == fileId) return f;
      }
    } catch (_) {/* geen lijst uit het bestand — dan ook geen andere nummering */}
    return null;
  }

  /// Resolve the torrent + the files to download (all audio, or one file).
  ///
  /// [bestand] is het bestand zoals de keuzelijst het TOONDE. Geef het mee waar je het hebt: dan
  /// wordt er op naam en grootte gekozen en doet de nummering er niet meer toe — zie
  /// [zelfdeBestandIn] voor wat er misging toen alleen [fileId] meeging.
  Future<(TbTorrent, List<TbFile>)> resolveForDownload(SearchResult r, int? fileId,
      {TbFile? bestand, void Function(double, String)? onProgress}) async {
    List<TbFile> kies(List<TbFile> lijst, TbFile? bedoeld) {
      if (bedoeld == null) return lijst.where((f) => f.id == fileId).toList();
      final bij = zelfdeBestandIn(lijst, bedoeld);
      return bij == null ? const [] : [bij];
    }

    if (lokaalVoor(r)) {
      final lokaal = await _lokaleTracklist(r);
      if (lokaal != null) {
        final (torrent, audio) = lokaal;
        // Er valt hier niets te wachten: aria2 begint pas als de downloadlijst hem de opdracht
        // geeft. Dat is meteen het verschil met TorBox, waar dit punt betekende dat de torrent daar
        // al helemaal binnen moest zijn voordat de eerste byte deze kant op kwam.
        final gekozen = fileId != null ? kies(torrent.files, bestand) : audio;
        if (gekozen.isNotEmpty) return (torrent, gekozen);
      }
    }
    if (!torbox.hasKey) throw 'Stel eerst je TorBox-sleutel in (Instellingen).';
    // **Het nummer uit de keuzelijst geldt hier niet.** Voor een `.torrent` kwam die lijst uit het
    // bestand zelf en nummert hij zoals dat bestand; TorBox nummert anders. Hier stond
    // `item.files.where((f) => f.id == fileId)`, en dat haalde een ánder nummer binnen. Gemeten op
    // 19-09-2026 met Stevie Wonder — Talking Book: Superstition aangeklikt, Lookin For Another Pure
    // Love binnengekregen; Sunshine aangeklikt, Maybe Your Baby binnengekregen.
    final bedoeld = fileId == null ? null : bestand ?? await _uitEigenLijst(r, fileId);
    final (id, hash) = await _addOrFind(r);
    final item = await _pollReady(id, hash, patient: !r.cached, onProgress: onProgress);
    final files = fileId != null ? kies(item.files, bedoeld) : _sortedAudio(item);
    if (files.isEmpty) {
      throw fileId != null ? 'Dit nummer staat niet in de lijst van TorBox' : 'Geen audio gevonden';
    }
    return (item, files);
  }
}

/// Soulseek search (with the first-character "*" quirk) + credentials gate.
/// Hoeveel zeker goede kopieën een tussenstand moet tonen voordat ⬇ al begint — zie [SoulseekService.zoekVroeg].
/// Acht, omdat de race van één nummer met twintig tegelijk begint ([DownloadManager.raceBreedte]): met
/// minder is de vroege lijst te mager om er iets mee te winnen.
const kVroegGenoeg = 8;

/// Toont [z] al genoeg kopieën die zeker goed zijn om de race te beginnen? Lossless, stereo, een vrije
/// plek, en de officiële lengte (±2 s, [lengteKlopt]) als die bekend is.
bool vroegGenoeg(List<SoulseekFile> z, int? seconden) =>
    z
        .where((f) =>
            f.freeSlots &&
            DownloadManager.isLossless(f) &&
            !DownloadManager.isMultichannel(f) &&
            (seconden == null || seconden <= 0 || lengteKlopt(seconden, f.durationSec)))
        .length >=
    kVroegGenoeg;

/// Zo lang mag de winnaar van een wedloop stilvallen voordat hij afvalt — zie [bewaakStilte].
const kWinnaarStil = Duration(seconds: 6);

/// Zo lang meet [teTraag] voordat hij iets zegt: de eerste tel van een overdracht zegt nog weinig.
const kTraagNa = Duration(seconds: 5);

/// Onder deze snelheid (bytes per seconde) is een uploader voor ⬇ traag — als er ook nog meer dan
/// [kTraagRest] te gaan is. Gemeten op 20-10-2026 in één race voor Lola Young — Messy: 1,8, 3,5, 15,8, 0,8
/// en 0,5 MB/s bij de anderen, en de winnaar (dweee) leverde 42 kB/s: tien minuten voor één nummer.
const kTraagSnelheid = 250 * 1024;

/// Zie [kTraagSnelheid]: wie bijna klaar is, mag traag zijn.
const kTraagRest = Duration(seconds: 45);

/// Is de uploader die nu stuurt zo traag dat een ander het beter overneemt? [binnen] bytes van [totaal] in
/// [bezig] (sinds hij begon te sturen).
///
/// Met [verbruik] (bytes per seconde die het nummer bij het afspelen vraagt, voor ▶): te traag als hij
/// minder dan 1,2 keer dat levert — dan kan het niet zonder haperen klinken, en een volgende ronde levert
/// meestal binnen een paar tellen. Zonder (⬇): onder [kTraagSnelheid] en nog meer dan [kTraagRest] te gaan.
/// Saber, 20-10-2026: "als het echt zo traag gaat, beter niet wachten en direct een andere proberen".
bool teTraag({required int binnen, required int totaal, required Duration bezig, double? verbruik}) {
  if (bezig < kTraagNa || totaal <= 0 || binnen >= totaal) return false;
  final snelheid = binnen / (bezig.inMilliseconds / 1000);
  if (verbruik != null && verbruik > 0) return snelheid < verbruik * 1.2;
  final nogNodig = (totaal - binnen) / max(snelheid, 1);
  return snelheid < kTraagSnelheid && nogNodig > kTraagRest.inSeconds;
}

/// Bewaakt de winnaar van een wedloop: komen er [stil] lang geen nieuwe bytes in [dest] terwijl het bestand
/// nog niet compleet is ([totaal]), dan gaat [stop] en is het true. Klaar ([klaar]) of al gestopt: false.
///
/// **Waarom.** In een wedloop wint wie het eerst bytes stuurt, en de anderen stoppen meteen. Valt die
/// winnaar daarna stil, dan wachtte alles tot Soulseek zelf opgaf. Gemeten op de gsm (20-10-2026, 3.9.529,
/// Hozier — Too Sweet): fraiklers33king stuurde na 3,6 s, de kop kwam nooit binnen, "Overdracht afgebroken
/// na 38s" — en de ronde daarna leverde in 2,9 s (peachleaf). 44 s van tik tot geluid, waarvan 34 s wachten
/// op een uploader die niets meer stuurde. Een gezonde uploader levert ruim meer dan het verbruik (peachleaf:
/// 3,2 MB/s tegen 207 kB/s); zes seconden zonder één byte is geen hapering meer.
///
/// [traag]: ook stoppen als die zegt dat hij te traag is ([teTraag]) — met wat er binnen is en hoe lang
/// hij al stuurt (vanaf de eerste byte).
Future<bool> bewaakStilte(File dest, int totaal, SlskCancel stop, bool Function() klaar,
    {Duration stil = kWinnaarStil,
    Duration peil = const Duration(milliseconds: 250),
    bool Function(int binnen, Duration bezig)? traag,
    void Function(int binnen, String waarom)? gestopt}) async {
  var vorige = -1;
  var sinds = DateTime.now();
  DateTime? eersteByte;
  while (!klaar() && !stop.isCancelled) {
    await Future<void>.delayed(peil);
    if (klaar() || stop.isCancelled) return false;
    int staat;
    try {
      staat = dest.existsSync() ? dest.lengthSync() : 0;
    } catch (_) {
      staat = vorige < 0 ? 0 : vorige;
    }
    if (totaal > 0 && staat >= totaal) return false;
    final nu = DateTime.now();
    if (staat > 0) eersteByte ??= nu;
    final e = eersteByte;
    if (traag != null && e != null && traag(staat, nu.difference(e))) {
      final kBs = staat / max(1, nu.difference(e).inMilliseconds) * 1000 / 1024;
      gestopt?.call(staat, 'te traag (${kBs.round()} kB/s)');
      stop.cancel();
      return true;
    }
    if (staat != vorige) {
      vorige = staat;
      sinds = nu;
      continue;
    }
    if (nu.difference(sinds) >= stil) {
      gestopt?.call(staat, '${nu.difference(sinds).inSeconds} s niets nieuws');
      stop.cancel();
      return true;
    }
  }
  return false;
}

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

  /// Waarom achtergrondwerk nu niet zoekt, als de server zwijgt ([SoulseekClient.serverZwijgt]); anders null.
  String? get waaromStil => client.serverZwijgt ? kZwijgZin : null;

  /// Is de gedeelde sessie nu echt aangemeld? Een zoekopdracht zonder aanmelding geeft een lege lijst,
  /// net als een zoekopdracht zonder treffers — en alleen dit onderscheidt ze.
  bool get verbonden => _session?.verbonden ?? false;

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
  /// Zoeken voor ⬇ met een vroege start, zoals ▶ al deed (Saber, 20-10-2026: "doe ook maar voor download").
  ///
  /// **Waarom.** Gemeten op de pc (3.9.526): ⬇ Please Please Please 12 s van tik tot bestand, waarvan 5 s
  /// zoeken; Indigo Night 21 s, waarvan 8 s zoeken — een Soulseek-zoekopdracht wacht een vaste tijd op
  /// uitslagen. ▶ begint al na [DownloadManager.kVroegZoeken] met wat er dan is.
  ///
  /// Vanaf die tel wordt elke tussenstand door [zeef] gehaald (dezelfde zeef als de hele uitslag, nooit
  /// twee tegelijk); toont hij er al [kVroegGenoeg] die zeker goed zijn ([vroegGenoeg]: lossless, stereo,
  /// een vrije plek, de officiële lengte), dan is dat de lijst en begint de race. Anders — een minder
  /// bekend nummer — gewoon de hele uitslag, zoals voorheen. Het zoeken loopt intussen verder; wat er later
  /// nog binnenkomt doet niet meer mee.
  ///
  /// [zeefOp]: waar [zeef] op zeeft. Hier niet nodig; een toestel stuurt het naar de pc, die daar zoekt en
  /// vroeg stopt (`RemoteSoulseekService.zoekVroeg`).
  Future<List<SoulseekFile>> zoekVroeg(String vraag,
      {required Future<List<SoulseekFile>> Function(List<SoulseekFile>) zeef,
      int? seconden,
      ({String titel, String artiest, String? album})? zeefOp,
      List<String> extra = const []}) {
    final uit = Completer<List<SoulseekFile>>();
    final klok = Stopwatch()..start();
    var bezig = false;
    Future<void> kijk(List<SoulseekFile> tussen) async {
      if (uit.isCompleted || bezig || klok.elapsed < DownloadManager.kVroegZoeken) return;
      bezig = true;
      try {
        final z = await zeef(tussen);
        if (!uit.isCompleted && vroegGenoeg(z, seconden)) uit.complete(z);
      } catch (_) {/* dan wacht het op de hele uitslag */} finally {
        bezig = false;
      }
    }

    search(vraag, onPartial: (l) => unawaited(kijk(l)), extra: extra).then((alles) async {
      if (uit.isCompleted) return;
      try {
        final z = await zeef(alles);
        if (!uit.isCompleted) uit.complete(z);
      } catch (e, s) {
        if (!uit.isCompleted) uit.completeError(e, s);
      }
    }, onError: (Object e, StackTrace s) {
      if (!uit.isCompleted) uit.completeError(e, s);
    });
    return uit.future;
  }

  /// Jouw antwoord aan een uploader (uploaderberichten.dart), over de gedeelde login — zoals zoeken. Waar als het
  /// verstuurd is; gooit als Soulseek nu niet mag inloggen (dezelfde reden als bij zoeken).
  Future<bool> stuurBericht(String aan, String tekst) async {
    if (!available) return false;
    final blocked = client.whyNotLogin;
    if (blocked != null) throw blocked;
    return withSession((s) => s.stuurBericht(aan, tekst));
  }

  /// [gebruikteVraag] meldt op welke trede er uiteindelijk gezocht is, zodat het scherm eerlijk kan
  /// zeggen waar deze lijst over gaat.
  ///
  /// [achtergrond]: de radio, de verlanglijst of een betere kopie — die wachten eerder op de zoekrem dan wat je zelf
  /// zoekt (`kZoekVoorJou` in soulseek.dart).
  ///
  /// [extra]: woorden waarmee de volledige vraag daarna nog eens als EIGEN zoekopdracht uitgaat ([kHiresZoekwoorden] voor
  /// de jacht op beter), elk ±8 s; de uitslag komt bij de gewone, nooit in de plaats ervan. Alleen waar niemand wacht.
  Future<List<SoulseekFile>> search(String query,
      {void Function(List<SoulseekFile>)? onPartial,
      void Function(String)? gebruikteVraag,
      bool achtergrond = false,
      List<String> extra = const [],
      bool terugval = true,
      bool Function()? nogNodig}) async {
    // An empty result because we couldn't log in is NOT "no sources" — retrying a broader query
    // would just burn another login and still show the user the wrong answer.
    final blocked = client.whyNotLogin;
    if (blocked != null) throw blocked;
    // **De server zwijgt** ([SoulseekClient.serverZwijgt], [kZwijgDrempel]): achtergrondwerk zoekt niet — het komt later
    // terug, zoals bij een geweigerde aanmelding — en wat je zelf zoekt krijgt één ronde, zonder terugval, extra woorden
    // of de vraag zonder "The". Elke vraag erbij vulde op 25-10-2026 alleen de rem, en de volgende pagina wachtte erachter.
    final stil = client.serverZwijgt;
    if (stil && achtergrond) throw const SoulseekZwijgt();
    // [terugval] onwaar: alleen de eerste ronde. Een smalle vraag ("… 24bit" na het landen) die niets vindt, hoort
    // niet door te vallen naar de eerste twee woorden — dat is een tweede zoekopdracht naar iets wat er niet is.
    final alle = zoekRondes(query);
    final rondes = terugval && !stil ? alle : alle.take(1).toList();
    // Nooit meer dan [kZoekPlafond] bestanden, de best passende eerst — zie zoekplafond.dart. "Live V"
    // gaf 60.143 bestanden: de pc stond 6 s stil om ze te versturen en de gsm crashte erop.
    final deel = onPartial == null ? null : (List<SoulseekFile> p) => onPartial(beperkZoekuitslag(query, p));
    var laatste = <SoulseekFile>[];
    for (var i = 0; i < rondes.length; i++) {
      // Wie vroeg is weg (de pagina is dicht): geen volgende ronde.
      if (nogNodig != null && !nogNodig()) return laatste;
      final ronde = rondes[i];
      // De RUIMSTE vraag van deze ronde, want daar kunnen de resultaten vandaan komen. Zie
      // [ruimerGezocht]: dat is precies waar het scherm eerlijk over hoort te zijn.
      gebruikteVraag?.call(ronde.last);
      final gevonden = await _searchOnce(ronde, deel, achtergrond: achtergrond, nogNodig: nogNodig);
      if (gevonden.isNotEmpty) {
        // De [extra] woorden als EIGEN zoekopdracht, na de gewone, elk met een eigen venster. Gemeten op 24-10-2026:
        // meegestuurd in hetzelfde venster leverde "24bit" bijna niets op (9 bestanden met 24bit in het pad, Phil
        // Collins) — het venster sluit zodra de brede vraag genoeg heeft, na 3,9 s, en de antwoorden op de smalle
        // vraag komen later. Als eigen zoekopdracht: 112. Alleen na een gewone ronde die iets vond: wat zonder het
        // woord niets oplevert, levert met het woord ook niets op.
        final samen = [...gevonden];
        if (i == 0 && !stil) {
          final al = {for (final f in gevonden) '${f.username}|${f.filename}'};
          for (final v in extraVragen(ronde.first, extra)) {
            for (final f in await _searchOnce([v], null, achtergrond: achtergrond)) {
              if (al.add('${f.username}|${f.filename}')) samen.add(f);
            }
          }
        }
        return beperkZoekuitslag(query, samen);
      }
      laatste = gevonden;
      if (client.whyNotLogin != null) throw client.whyNotLogin!;
    }
    // **"The …" zonder "The".** Gemeten op de pc (25-10-2026): "The Beatles Let It Be" en "The Weeknd Alone Again"
    // kregen geen enkel antwoord, "Beatles Let It Be" 5000 bestanden en "Weeknd Alone Again" 693 — terwijl "The Police
    // Roxanne" gewoon werkte. Het netwerk weert bepaalde namen met "The" ervoor; dan nog één keer zonder.
    final zonderThe = query.trim().replaceFirst(RegExp(r'^the\s+', caseSensitive: false), '');
    if (terugval && !stil && laatste.isEmpty && zonderThe != query.trim() && zonderThe.isNotEmpty) {
      final gevonden = await _searchOnce([zonderThe], deel, achtergrond: achtergrond, nogNodig: nogNodig);
      if (gevonden.isNotEmpty) {
        gebruikteVraag?.call(zonderThe);
        return beperkZoekuitslag(query, gevonden);
      }
    }
    return laatste;
  }

  /// Alle vragen van één ronde in ÉÉN zoekopdracht — zie [zoekRondes].
  ///
  /// Ze gaan als losse tickets naar dezelfde sessie en komen op één hoop terug, dus twee vragen
  /// kosten hetzelfde als één. Zou je ze na elkaar sturen, dan was elke ronde er ruim acht seconden
  /// bij.
  Future<List<SoulseekFile>> _searchOnce(List<String> vragen, void Function(List<SoulseekFile>)? onPartial,
      {bool achtergrond = false, bool Function()? nogNodig}) async {
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
      return await withSession(
          (s) => s.search(variants.toList(), onPartial: onPartial, achtergrond: achtergrond, nogNodig: nogNodig));
    } catch (e) {
      // Leeg, maar niet "niets gevonden" — dus wel in het logboek, anders is het van een lege uitslag niet te onderscheiden.
      client.logboek('zoeken "${variants.last}" mislukte: $e');
      return [];
    }
  }
}

/// Hoe een [DownloadManager.zoekEnHaal] afliep, zodat het scherm (als het er nog is) het juiste zegt.
enum ZoekUitkomst { gestart, geenBron, loopt, geannuleerd }

/// Eén voorstel om een kopie uit `_dubbel` terug te zetten. Zie [DownloadManager.zoekTerugzettingen].
class Terugzetting {
  /// De kopie in `_dubbel` die terug zou moeten.
  final String geparkeerd;

  /// Wat er nu op haar plek staat, en opzij gaat.
  final String huidig;
  final String artiest, titel;

  /// Waarom, in een zin: "echte hi-res (96 kHz) boven cd-kwaliteit", of "even goed … — de vervanging
  /// was geen winst".
  final String reden;

  const Terugzetting(
      {required this.geparkeerd,
      required this.huidig,
      required this.artiest,
      required this.titel,
      required this.reden});
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

  /// Waar het binnengekomen bestand op de keuring wacht (de torrentweg, zie [keuringMap]). Na de
  /// keuring staat in [detail] wat ermee gebeurde: opgeborgen, weggezet omdat je hem al even goed had,
  /// of afgekeurd omdat hij kapot is.
  String? keuringsPad;

  /// Wat er na de uitkomst van de keuring nog bij hoort, zoals "deelt nog 72 uur terug".
  String? naKeuring;

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

  /// Eén nummer dat je zelf met ⬇ startte (zie [DownloadManager.zoekEnHaal]): de race krijgt de ruimte van
  /// de wedloop — [DownloadManager.kWedloopLopers] kandidaten in plaats van twintig, en wie na
  /// [DownloadManager.kVerbindGeduld] nog niet antwoordt houdt zijn plek niet bezet. Een album niet: twaalf
  /// nummers tegelijk keer zestig peers is geen nette gast meer.
  bool ruim = false;

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

  /// Hoort deze taak in de hervatnotitie (`pending_downloads.json`)? Alleen wat nog niet speelbaar is.
  ///
  /// Een taak die al geland is en nog op betere kwaliteit jaagt (`upgrading`) telt als [busy], en ging
  /// zo de notitie in op het moment dat de race afliep — de jacht liep dan nog. Na de jacht schreef
  /// niemand de notitie opnieuw, dus bij de volgende start haalde de pc het hele nummer nog eens, met de
  /// kandidaten van toen. Gemeten op 21-10-2026: Doechii — Anxiety, om 23:44 al in 88.2 kHz binnen,
  /// werd na de herstart opnieuw gehaald (80,7 MB) en weggegooid ("niet bewezen beter dan wat je
  /// hebt") — op het moment van een ▶, want een hervatting wacht op de eerste Soulseek-sessie.
  /// Een onderbroken jacht kost niets: je hebt het nummer, en een lossy landing staat al als wens op
  /// de lijst ([DownloadManager._wantLossless]).
  bool get hoortInHervatnotitie => busy && !playable && candidates.isNotEmpty;
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
  /// [nietIn] is de map die net wordt opgeborgen; wat daar ligt is het binnenkomende zelf, niet
  /// "wat je al hebt". Zie [_bergTorrentOp].
  String? Function(String artist, String title, {int? seconds, String? nietIn})? mapVanBestaande;

  /// De bibliotheek: welke bestanden van deze artiest ongeveer zo lang duren. Voor de keuring, als een
  /// binnenkomer onder een andere titel staat dan jouw kopie — zie [_alGehadOnderAndereTitel].
  List<String> Function(String artist, int seconds, {String? nietIn})? opLengte;

  /// Bestanden in een torrentmap die op dit moment nog GESCHREVEN worden — tot ze helemaal binnen
  /// zijn en als jouw keuze vastliggen.
  ///
  /// Een TorBox-download schrijft rechtstreeks onder zijn definitieve naam in de torrentmap, en
  /// twee keuzes uit dezelfde torrent delen die map. Wie als eerste klaar was, borg de hele map op
  /// ([_bergTorrentOp]) — ook het bestand dat de ander nog aan het schrijven was. Gemeten op
  /// 19-09-2026: een "02 - Maybe Your Baby.flac" van 162 MB kwam als afgekapte kopie van 71,5 MB in
  /// de bibliotheek (3:00 van de 6:50 speelbaar), omdat een ander nummer uit dezelfde torrent
  /// negen seconden eerder klaar was.
  final Set<String> _inAanmaak = {};

  /// Hoeveel torrentopdrachten er nu in elke keuringsmap werken.
  ///
  /// Twee keuzes uit dezelfde torrent delen één keuringsmap. Wat er na het opbergen overblijft — een
  /// nummer zonder leesbare tags, een .cue, een boekje — gaat terug naar de zichtbare map, maar pas
  /// als de LAATSTE opdracht klaar is: anders verhuist de eerste een blad waar de tweede nog mee moet
  /// knippen. Zie [_zetRestZichtbaar].
  final Map<String, int> _opKeuring = {};

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

  /// Zo lang wacht de race van een los nummer ([DownloadJob.ruim]) op een antwoord voor hij de volgende
  /// vraagt. Gemeten op 20-10-2026: vijftien onbereikbare peers hielden elk 18 s een plek bezet.
  static const kVerbindGeduld = Duration(seconds: 4);
  static const _maxLossyTries = 8;

  /// How fast the race opens new peer connections. Not a cap on how many run at once: a peer that
  /// answers "you're in my queue" frees its slot immediately and keeps waiting in the background,
  /// so within half a minute the whole shortlist is engaged. Peer connections, not logins — the
  /// shared session is untouched, so this cannot repeat the login problem.
  ///
  /// The FLOOR now — see [raceBreedte] for how wide a race actually starts.
  static const _probeWidth = 6;

  /// Zoveel uploaders spreken alle lopende downloads samen ongeveer tegelijk aan — zie [raceBreedte].
  static const kRaceBudget = 30;

  /// Hoeveel kandidaten één race tegelijk aanspreekt: het [kRaceBudget] verdeeld over de downloads die
  /// lopen, nooit minder dan [_probeWidth] en nooit meer dan [cap].
  ///
  /// **Waarom.** Gemeten op de pc (20-10-2026): "Tell Him" met ⬇ — 141 kopieën met de officiële lengte,
  /// zes kanalen, en elk kanaal wachtte tot zijn uploader antwoordde of opgaf (een onbereikbare houdt er
  /// één tot ~20 s vast): 56 s voor het bestand er stond. Met ▶, waar dertig meteen samen beginnen
  /// ([kWedloopTegelijk]), werden populaire nummers 4 à 8 s. Saber: "dat zou het gewone downloaden
  /// drastisch versnellen". Eén nummer begint dus met alle twintig samen; een album van twaalf blijft
  /// op zes per nummer, zodat het totaal niet honderden verbindingen in één tel wordt.
  static int raceBreedte({required int actief, required int cap}) =>
      max(_probeWidth, min(cap, kRaceBudget ~/ max(1, actief)));

  /// Total time spent chasing a better copy after a playable one already landed.
  static const _upgradeBudget = Duration(minutes: 10);

  // ── De klokken van de verlanglijst ──────────────────────────────────────────────────────
  // Hiervoor stond er `take(4)` met dertig minuten wachten per peer: tot TWEE UUR voor één wens,
  // en de veegbeurt draait ze SERIEEL af. Met 176 te vervangen bestanden op de lijst is dat ruim
  // dertien dagen voor één veegbeurt, terwijl `_sweeping` alle volgende blokkeert.
  //
  // Alles is nu een klok en geen teller, want dat is de eenheid die telt: een trage peer kost
  // minuten, niet megabytes.

  /// Alles wat één wens mag kosten, van zoeken tot opbergen.
  static const _wensBudget = Duration(minutes: 20);

  /// Hoe lang er bij ÉÉN peer in de wachtrij gestaan wordt. Wie je acht minuten laat wachten
  /// levert over dertig ook niets.
  static const _maxWachtPerPeer = Duration(minutes: 8);

  /// Hoeveel kandidaten er per ronde geprobeerd worden. Meer dan de vier van hiervoor, omdat elke
  /// poging nu veel goedkoper is — en omdat een betrapte kopie een poging kost zonder resultaat.
  static const _maxWensPogingen = 6;

  /// Hoeveel wensen één veegbeurt afwerkt.
  static const _maxWensenPerVeeg = 6;

  /// Hoeveel nummers van TIDAL er per ronde gehaald worden voor één wens. Weinig: de keuze is al
  /// streng op titel en artiest, en wat de keuring afwijst komt niet terug ([LosslessWant.tidalNee]).
  static const _maxTidalPogingen = 2;

  /// Boven welke wachtrijplaats er niet meer gewacht wordt.
  ///
  /// GEMETEN op 08-09-2026: de jacht stond acht minuten op plaats **26549**, en een andere keer op
  /// 2506 en op 84 — alle drie liepen ze het volle wachtbudget uit zonder één byte. Wat er wél
  /// leverde stond op plaats 5 of 6. De plaats is meteen bekend, dus daar acht minuten op wachten
  /// is niets anders dan de klok verzetten.
  ///
  /// Vijftig en niet vijf: een wachtrij kan snel leeglopen, en er is niets kapot aan even
  /// aanschuiven. Maar op vijftig is het al uren, en er staan honderden andere kandidaten klaar.
  static const _maxWachtrijPlaats = 50;

  /// Hoe lang een peer die net "nee" zei met rust gelaten wordt, over ALLE wensen heen.
  ///
  /// GEMETEN op 08-09-2026: `Inhabitantz+` kostte 24,4 minuten, verdeeld over DRIE verschillende
  /// wensen — elke keer acht minuten wachten en dan "Geweigerd: Queued". [LosslessWant.refused] is
  /// per wens, dus elke nieuwe wens ontdekte dezelfde dode peer opnieuw. Over de hele avond ging
  /// 41% van de wachttijd naar peers die na het volle wachtbudget niets leverden.
  ///
  /// Een uur, want dit is een momentopname en geen oordeel: een wachtrij die nu vol is kan straks
  /// leeg zijn, en een firewall kan opengaan. Alleen in het geheugen — na een herstart mag iedereen
  /// weer meedoen.
  static const _peerRustDuur = Duration(hours: 1);

  /// Wanneer een peer voor het laatst nee zei. Zie [_peerRustDuur].
  final Map<String, DateTime> _peerRust = {};

  /// De peers die nu even overgeslagen worden. Ruimt zichzelf op.
  Set<String> _rustendePeers() {
    final nu = DateTime.now();
    _peerRust.removeWhere((_, wanneer) => nu.difference(wanneer) > _peerRustDuur);
    return _peerRust.keys.toSet();
  }

  /// En hoe lang die veegbeurt zelf mag duren. BEWUST onder de tik van twintig minuten
  /// (`main.dart`), zodat een veegbeurt altijd klaar is voor de volgende aan de beurt is en de
  /// tijdklok zijn betekenis houdt.
  static const _veegBudget = Duration(minutes: 15);

  /// Wat deze weg besloot, in `downloads.log` naast de andere staatbestanden.
  ///
  /// Gebouwd omdat een vraag niet te beantwoorden was. Een FLAC die via de app niet binnenkwam en via
  /// de native client meteen wel: er zijn vier mechanismen die dat kunnen verklaren -- geen kandidaat
  /// gevonden, tien minuten opwaardeerbudget op, wachten achter een andere opwaardering, of een
  /// herstart die de jacht afkapt -- en van buitenaf zijn ze niet van elkaar te onderscheiden.
  /// pending_downloads.json wordt opgeruimd en warm.log gaat alleen over de metadata-warmer, dus na
  /// een uur is er niets meer om naar te kijken. Precies de les die warm.log zelf al opschreef.
  late final WarmLog _log = WarmLog('$appDir${Platform.pathSeparator}downloads.log');

  /// Een regel in `downloads.log` van buiten de beheerder: de TIDAL-ronde over de bibliotheek (tidal_beter.dart).
  void logRegel(String regel) => _log.line(regel);

  /// Wat de vervangjacht doet, voor het scherm. Zie [VervangJacht].
  ///
  /// Een eigen melder en niet `notifyListeners()`: de Kwaliteitspagina bouwt dan alleen zijn strook
  /// opnieuw en niet de hele lijst met honderden rijen eronder, en dat scheelt bij een regel per
  /// paar seconden.
  final ValueNotifier<VervangJacht> jacht = ValueNotifier(const VervangJacht(opDeLijst: 0));

  /// Wanneer de volgende veegbeurt aan de beurt is. Gezet door de klok in `main.dart`, want die
  /// bepaalt het ritme — hier weten we alleen wat er ná een tik gebeurt.
  set volgendeVeegOm(DateTime? wanneer) => jacht.value = jacht.value.met(volgendeOm: wanneer);

  void _jachtRegel(String regel) => jacht.value = jacht.value.met(regel: regel);

  /// Hoeveel opdrachten er op dezelfde aria2-taak hangen, per gid.
  ///
  /// **Waarom er geteld wordt en niet gewoon opgeruimd.** Twee nummers van dezelfde plaat delen één
  /// aria2-taak (zie het aanhaken in [_downloadLokaal]). Ruimt de eerste die klaar is die taak op,
  /// dan trekt hij de map onder de tweede vandaan: het opruimen gooit aria2's eigen map weg, en
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

  /// Wie er op dit moment bezig is één torrent bij aria2 aan te melden, per infohash.
  ///
  /// **Waarom een slot en niet alleen [_gidPerTorrent].** Dat kaartje wordt pas ingevuld NADAT de
  /// aanmelding gelukt is. Klik je zeven nummers van één plaat aan, dan starten er zeven opdrachten
  /// tegelijk, kijken ze alle zeven op een leeg kaartje, en melden ze alle zeven dezelfde torrent
  /// aan. Kijken-en-dan-doen zonder slot ertussen.
  ///
  /// **Gemeten op 31-08-2026, Beyoncé — Dangerously In Love via RuTracker.** Zeven aanvragen binnen
  /// acht duizendsten van een seconde; aria2 nam er één aan en wees er zes af met "InfoHash …
  /// is already registered". Erger nog: de zesde en zevende vonden intussen wél een kaartje, maar
  /// dat wees naar het gid van een AFGEWEZEN aanmelding — vandaar "Cannot change option for GID#…".
  /// Zes van de zeven nummers mislukten, en dat is precies de klacht "hij pakt er maar één".
  ///
  /// Met dit slot meldt de eerste hem aan en wachten de rest op diezelfde taak, waarna ze er met
  /// `kiesErbij` bij gaan zitten — de weg die er al lag en die nooit aan de beurt kwam.
  final Map<String, Future<void>> _aanmeldSlot = {};

  /// Leeft deze aria2-taak nog, of is hij binnen een tel omgevallen?
  ///
  /// Kort wachten en dan pas oordelen. Meteen na het aanmelden staat een taak op `waiting` — dat
  /// zegt nog niets — en de weigering die we zoeken komt uit aria2's eigen lus, niet uit het
  /// antwoord op onze aanroep. Anderhalve seconde is ruim: in de meting van 31-08-2026 stond de
  /// afwijzing er binnen twee duizendsten.
  Future<bool> _leeftNog(Aria2 motor, String gid) async {
    for (var i = 0; i < 5; i++) {
      final s = await motor.stand(gid);
      if (s == null) return false;
      if (s.stuk) return false;
      if (s.status != 'waiting') return true;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    // Nog steeds in de wacht: dat is geen fout, dat is een rij. Die mag gewoon doorlopen.
    return true;
  }

  /// Voert [werk] uit met de zekerheid dat geen tweede opdracht voor dezelfde torrent er tegelijk
  /// in zit. Zonder infohash valt er niets te botsen en gaat het gewoon meteen.
  Future<T> _perTorrent<T>(String hash, Future<T> Function() werk) {
    if (hash.isEmpty) return werk();
    final vorige = _aanmeldSlot[hash] ?? Future<void>.value();
    final mijn = Completer<void>();
    _aanmeldSlot[hash] = mijn.future;
    // `catchError` op de vorige: struikelt die, dan mag de volgende alsnog naar binnen in plaats van
    // mee om te vallen. Een mislukte aanmelding is geen reden om de rest van de plaat op te geven.
    return vorige.catchError((_) {}).then((_) => werk()).whenComplete(() {
      mijn.complete();
      if (identical(_aanmeldSlot[hash], mijn.future)) _aanmeldSlot.remove(hash);
    });
  }

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
      bool wachtOpAfloop = true,
      bool ruim = false}) async {
    if (!soulseek.available) throw 'Stel je Soulseek-login in (Instellingen).';
    if (candidates.isEmpty) return false;
    // Kiest de app zelf, dan een vinyl-rip pas als er niets anders is (Saber, 24-10-2026: vinyl "alleen als ik kies").
    // Wie zelf op een regel klikte ([exact]) of zelf een uitgave koos ([jouwKeuze]), krijgt wat hij koos.
    if (exact == null && !jouwKeuze) candidates = vinylAchteraan(candidates, (f) => f.filename);
    // De lengte van de kopieën zelf, als de uitgave ernaast zit ([lengteVanDeMeerderheid]): anders gaan in de race de
    // kopieën met de verkeerde lengte voor, en keurt [keurOverdracht] (±12 s) een goede kopie na de overdracht af.
    // "Kids Of The Future" (Jonas Brothers, 2007): de uitgave zei 2:55, de kopieën 3:18–3:19.
    final gezag = authority;
    if (gezag != null && exact == null && !jouwKeuze) {
      final lengte = lengteVanDeMeerderheid(candidates, gezag.seconds);
      if (lengte != null) {
        _log.line('"${gezag.artist} — ${gezag.title}": de uitgave zegt ${_mmss(gezag.seconds!)}, de kopieën '
            '${_mmss(lengte)} — die lengte geldt');
        authority = gezag.metSeconden(lengte);
      }
    }
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
      ..ruim = ruim
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

  /// Een download die eerst een bron moet zoeken — en daarbij NIET afhangt van het scherm dat hem
  /// startte.
  ///
  /// Saber op 04-10-2026: *"als ik bij soulseek op de download knop klik, en dan uit het venster ga,
  /// dan wordt de download niet actief, ik moet in het venster blijven tot de download begint"*. Dat
  /// klopte precies. De albumpagina zocht eerst zélf een bron — een Soulseek-zoekopdracht van tien tot
  /// dertig seconden — en maakte pas dáárna de download aan, met `if (!mounted) return` ertussen. Wie
  /// de pagina in die tijd verliet, gooide zijn klik stil weg: geen taak, geen melding, niets.
  ///
  /// Nu staat de taak bij de klik al in de downloadlijst ("bron zoeken…"), en zoekt deze functie
  /// verder, ook als het scherm weg is. [zoek] mag daarom niets nodig hebben dat met het scherm
  /// verdwijnt: pak de diensten vast vóór je deze functie aanroept, niet erin.
  ///
  /// Komt terug zodra de download is AANGEMAAKT, niet als hij klaar is: wie hierop wacht wil weten óf er
  /// iets loopt, niet een minuut lang niets horen.
  Future<ZoekUitkomst> zoekEnHaal(
      {required String naam,
      required String key,
      required Future<List<SoulseekFile>> Function() zoek,
      TrackTags? authority}) async {
    final bestaand = jobByKey(key);
    if (bestaand != null && bestaand.busy) return ZoekUitkomst.loopt;
    final job = DownloadJob(naam, key: key, status: 'preparing')
      ..detail = 'bron zoeken…'
      ..canCancel = true
      ..authority = authority;
    jobs.insert(0, job);
    notifyListeners();
    List<SoulseekFile> kandidaten;
    try {
      kandidaten = await zoek();
    } catch (_) {
      kandidaten = const [];
    }
    // Weggetikt terwijl er gezocht werd: dan heeft `cancelJob` het laatste woord al gezet.
    if (job.cancelled) return ZoekUitkomst.geannuleerd;
    jobs.remove(job);
    if (kandidaten.isEmpty) {
      job
        ..status = 'failed'
        ..detail = 'geen Soulseek-bron gevonden'
        ..canCancel = false;
      jobs.insert(0, job);
      notifyListeners();
      _log.line('"$naam": geen Soulseek-bron gevonden');
      return ZoekUitkomst.geenBron;
    }
    notifyListeners();
    // Dezelfde sleutel, zodat de knop op de pagina gewoon doorloopt van "zoeken" naar "bezig".
    // Eén nummer dat je zelf startte: de ruimte van de wedloop (zie [DownloadJob.ruim]). Gemeten op 20-10-2026
    // (⬇ Doechii — Anxiety vanaf de gsm): 196 kopieën met de officiële lengte, twintig geprobeerd — bijna
    // allemaal onbereikbaar (elk 18 s een plek bezet) of afgebroken — en dan "de andere lengtes": 2 min 24 s.
    final gestart =
        await enqueueSoulseekBest(kandidaten, key: key, authority: authority, wachtOpAfloop: false, ruim: true);
    return gestart ? ZoekUitkomst.gestart : ZoekUitkomst.loopt;
  }

  // ── Surviving a restart ───────────────────────────────────────────────────
  // A download interrupted by the app closing (or the PC shutting down) used to be simply gone:
  // no record of it anywhere, and a half-written file left behind in staging.

  String get _appDir => appDir;
  File get _pendingFile => File('$_appDir${Platform.pathSeparator}pending_downloads.json');

  Future<void> _savePending() async {
    try {
      final open = jobs.where((j) => j.hoortInHervatnotitie).toList();
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

  /// Werkmappen van torrents die bij een vorige keer bleven liggen, opruimen. Eén keer bij het
  /// opstarten.
  ///
  /// **Waarom.** aria2 start zonder sessiebestand (zie `aria2.dart`): na een herstart kent hij geen
  /// enkele torrent meer, dus wat er onder [torrentWerkMap] ligt hoort nergens meer bij. Ging de app
  /// dicht terwijl een torrent liep, dan bleef zijn werkmap staan "tot de volgende download van
  /// dezelfde plaat hem overneemt" ([_ruimNaSeeden]) — en die kwam nooit. Gevonden op 11-10-2026: zes
  /// halve torrents, samen zo'n 900 MB, de oudste van 30-08 (Oasis, "Wonderwall" 78 MB binnen toen de
  /// app om 09:41 dichtging).
  ///
  /// Een map die nu wél bij een lopende torrent hoort ([_gidPerTorrent]) blijft staan, voor het geval
  /// dit ooit later dan bij het opstarten aangeroepen wordt.
  Future<int> ruimDodeTorrentwerkOp() async {
    final werk = Directory('$_downloadsRoot${Platform.pathSeparator}$torrentWerkMap');
    if (!await werk.exists()) return 0;
    final inGebruik = {
      for (final h in _gidPerTorrent.keys)
        if (h.length >= 8) h.substring(0, 8)
    };
    var n = 0;
    await for (final e in werk.list(followLinks: false)) {
      final naam = e.path.split(Platform.pathSeparator).last;
      if (inGebruik.contains(naam.toLowerCase())) continue;
      try {
        await e.delete(recursive: true);
        n++;
      } catch (_) {/* staat er een vast, dan de volgende keer */}
    }
    if (n > 0) _log.line('opstarten: $n achtergebleven torrentwerkmap${n == 1 ? '' : 'pen'} opgeruimd');
    return n;
  }

  /// Doen alsof deze torrent nu loopt, voor de toets van [ruimDodeTorrentwerkOp].
  @visibleForTesting
  void torrentLooptVoorToets(String hash) => _gidPerTorrent[hash.toLowerCase()] = 'toets';

  /// Is dit bestand écht wat het zegt? Gemeten zodra het binnen is, nooit ervoor.
  ///
  /// Bij een zoekresultaat kan dit niet: je kunt niet in het bestand van een vreemde kijken zonder het
  /// eerst binnen te halen. Daar blijft het bij de verhoudingswaarschuwing uit
  /// [verdachtKleinVoorHiRes] — een aanwijzing, geen oordeel.
  ///
  /// Geeft het oordeel ook terug, want op de wensweg wordt er meteen op beslist: een betrapt
  /// bestand gaat niet de bibliotheek in maar de vuilnisbak. Null betekent "niet te meten" — en dat
  /// is nooit een reden om iets te weigeren.
  Future<Echtheidsoordeel?> _meetEchtheid(File f) async {
    try {
      // FLAC en WavPack. Die laatste bleef ongemeten, en een ongemeten bestand kan niets bewijzen —
      // op 29-09-2026 stonden er vier WavPacks van 32/192 in de plaats van FLACs, zonder dat iemand
      // wist wat erin zat. Een WavPack met zwevende kommagetallen niet: daar zegt proef A niets.
      int rate, bits;
      double duur;
      final tags = readFlacTags(f);
      if (tags != null && tags.sampleRate > 0) {
        rate = tags.sampleRate;
        bits = tags.bitsPerSample;
        duur = (tags.duration?.inSeconds ?? 0).toDouble();
      } else if (f.path.toLowerCase().endsWith('.wv')) {
        final k = readWvKop(f);
        if (k == null || k.sampleRate <= 0 || k.zwevend) return null;
        rate = k.sampleRate;
        bits = k.bitsPerSample;
        duur = (k.duration?.inSeconds ?? 0).toDouble();
      } else {
        return null;
      }
      final meter = Echtheidsmeter(cacheMap: '$appDir${Platform.pathSeparator}echtheid');
      if (!meter.available) return null;
      final o = await meter.van(f.path, kopSampleRate: rate, kopBits: bits, duurSeconden: duur);
      if (o != null) await onthoudOordeel(f.path, o);
      return o;
    } catch (_) {
      /* een meting is een verrijking; hij mag een download nooit breken */
      return null;
    }
  }

  /// Maak de vergelijking eerlijk vóór het filen: meet de binnenkomer én wat er al ligt, en geef het
  /// pad van wat er ligt terug (of null).
  ///
  /// **Waarom ook wat er al ligt.** `firstIsBetter` telt alleen wat bewezen is. Een 24/192 in je
  /// bibliotheek die nooit gemeten werd, geldt daar als "hi-res volgens de kop, niet gemeten" — en dan
  /// kan een gemeten echte 24/96 er niet van winnen, maar ook niet van verliezen: het is "weet niet",
  /// en dan blijft jouw bestand staan. Dat is veilig, maar het beste antwoord is gewoon meten. En een
  /// kapot bestand van jou hoort te verliezen van een heel bestand; ook dat moet eerst bekend zijn.
  Future<String?> _bereidVergelijkingVoor(File nieuw, TrackTags? gezag) async {
    await _meetEchtheid(nieuw);
    final t = gezag ?? readTags(nieuw);
    if (t == null) return null;
    final bestaand = mapVanBestaande?.call(t.artist, t.title, seconds: t.seconds);
    if (bestaand == null || !File(bestaand).existsSync()) return null;
    if (gemeten(bestaand) == null) await _meetEchtheid(File(bestaand));
    await controleerHeel(bestaand);
    return bestaand;
  }

  /// Is [a] dezelfde opname als [b]? Null als het niet te zeggen valt (geen fpcalc, niet te lezen).
  ///
  /// Zelfde titel is geen zelfde nummer: van zes vervangers die ooit binnenkwamen waren er zes een
  /// radio-edit. De looptijd vangt het meeste, maar een remaster met dezelfde lengte of een andere
  /// opname van precies even lang ziet alleen de vingerafdruk. Onder [maybeSameRecordingScore] is het
  /// een andere opname.
  Future<bool?> _zelfdeOpname(String a, String b) async {
    final s = await _opnameScore(a, b);
    return s == null ? null : s >= maybeSameRecordingScore;
  }

  /// De vingerafdruk van [a] tegen [b] (0–1), of null als het niet te zeggen valt. Zie [opnameOordeel].
  Future<double?> _opnameScore(String a, String b) async {
    try {
      final fp = Fingerprinter();
      if (!fp.available) return null;
      final x = await fp.of(a), y = await fp.of(b);
      if (x == null || y == null || x.raw.isEmpty || y.raw.isEmpty) return null;
      return similarity(x.raw, y.raw);
    } catch (_) {
      return null;
    }
  }

  /// De twijfelgevallen (twijfel.dart); gezet door main.dart op de pc. Null: er wordt niets bewaard, en een twijfel is
  /// "een andere opname" zoals voorheen.
  Twijfellijst? twijfel;

  /// Een kopie die bewezen beter klinkt maar waarvan de vingerafdruk twijfelt ([Opnameoordeel.twijfel]): niet weggooien
  /// en niet vervangen, maar bewaren in [twijfelMap] tot je kiest (Saber, 25-10-2026). Waar als hij bewaard is of er al
  /// een twijfelgeval voor dit nummer wacht — dan is [staged] in beide gevallen weg uit de keuringsmap.
  @visibleForTesting
  Future<bool> bewaarAlsTwijfel(File staged, String bestaand, double score, String bron, TrackTags? gezag) async {
    final lijst = twijfel;
    if (lijst == null) return false;
    final naam = gezag == null ? baseName(bestaand) : '${gezag.artist} — ${gezag.title}';
    final s = score.toStringAsFixed(2).replaceAll('.', ',');
    final grootte = staged.lengthSync();
    if (lijst.van(bestaand) != null || lijst.afgewezen(bestaand, grootte)) {
      _log.line('   $bron: twijfel ($s) voor "$naam", maar er wacht al een twijfelgeval of je gooide deze weg — weggegooid');
      await _discardStaged(staged.path);
      return true;
    }
    final kop = readFlacTags(staged);
    final soort = soortVan(staged.path).toUpperCase();
    final kwaliteit = kop == null || kop.bitsPerSample <= 0
        ? soort
        : '$soort ${kop.bitsPerSample}/${(kop.sampleRate / 1000).toStringAsFixed(1).replaceAll('.0', '').replaceAll('.', ',')}';
    final id = fnv1a('${bestaand.toLowerCase()}|${DateTime.now().microsecondsSinceEpoch}');
    final punt = staged.path.lastIndexOf('.');
    final ext = punt < 0 ? '' : staged.path.substring(punt).toLowerCase();
    final sep = Platform.pathSeparator;
    final doel = File('$_downloadsRoot$sep$twijfelMap$sep$id$ext');
    String bewaard;
    try {
      await doel.parent.create(recursive: true);
      bewaard = await moveWithRetry(staged, doel);
    } catch (e) {
      _log.line('   $bron: twijfelkopie niet te bewaren ($e) — weggegooid');
      await _discardStaged(staged.path);
      return true;
    }
    try {
      await staged.parent.delete();
    } catch (_) {/* de keuringsmap houdt nog iets vast */}
    lijst.zet(Twijfelgeval(
      id: id,
      pad: bestaand,
      kandidaat: bewaard,
      bron: bron,
      score: score,
      kwaliteit: kwaliteit,
      ms: DateTime.now().millisecondsSinceEpoch,
      grootte: grootte,
      gezag: gezag?.toJson(),
    ));
    await lijst.bewaar();
    _log.line('"$naam": TWIJFEL — $bron klinkt beter ($kwaliteit), maar de vingerafdruk zegt $s: bewaard tot je kiest');
    return true;
  }

  /// "Vervangen" uit het twijfelmenu: de twijfelkopie in de plaats van [pad], zoals een opwaardering — wat er lag gaat
  /// naar `_dubbel`. Geeft de zin voor op het scherm terug.
  ///
  /// [behalveLezer] en [behalveZone]: het toestel dat vraagt (zijn adres, zijn id) — wat dat zelf leest of speelt, houdt
  /// het houden niet tegen ([inGebruikVoorHouden]).
  Future<String> vervangDoorTwijfel(String pad, {String? behalveLezer, String? behalveZone}) async {
    final lijst = twijfel;
    final g = lijst?.van(pad);
    if (lijst == null || g == null) return 'Er wacht geen twijfelkopie meer voor dit nummer';
    final f = File(g.kandidaat);
    if (!f.existsSync()) {
      lijst.verwijder(pad);
      await lijst.bewaar();
      return 'De twijfelkopie staat er niet meer';
    }
    // Net losgelaten om te vervangen (Deze houden terwijl het speelde): even wachten tot niets het nog open heeft.
    bool inGebruik() =>
        inGebruikVoorHouden?.call(pad, behalveLezer: behalveLezer, behalveZone: behalveZone) ??
        (speeltNu?.call(pad) ?? false);
    for (var i = 0; i < 25 && inGebruik(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (inGebruik()) {
      _log.line('"${baseName(pad)}": houden gaat nu niet — het bestand is in gebruik (hier of op een toestel)');
      return 'Het nummer speelt nu — vervang het als het niet meer speelt';
    }
    final gezag = g.gezag == null ? null : TrackTags.fromJson(g.gezag!);
    final naam = gezag == null ? baseName(pad) : '${gezag.artist} — ${gezag.title}';
    try {
      // Een kopie die je zelf vroeg (studio, cd, vinyl): jouw keuze wint altijd, ook van een kopie die op papier beter
      // is — daarvoor vroeg je hem ([placeFileDetailed] vervangAltijd).
      final uit = await placeFileDetailed(f, _downloadsRoot,
          tags: gezag,
          staatAl: (artist, title, {int? seconds}) => pad,
          parkeerAltijd: true,
          vervangAltijd: g.gevraagd);
      if (uit.how != Placement.moved) {
        // Verloren van wat er nu ligt: de kopie staat in _dubbel/binnengekomen, en het geval is voorbij.
        lijst.verwijder(pad);
        await lijst.bewaar();
        _log.line('"$naam": twijfelkopie gekozen (${g.bron}), maar je huidige kopie is intussen even goed of beter');
        return 'Niet vervangen: je huidige kopie is intussen even goed of beter';
      }
      if (gezag != null) {
        try {
          await stampTags(File(uit.path), gezag);
        } catch (_) {/* het bestand staat goed; een mislukte tagschrijf maakt het niet stuk */}
      }
      // De soort van wat er nu ligt. Gevraagd: jouw keuze — daarna waardeert de app alleen binnen die soort op.
      if (g.soort case final s?) {
        zetSoort(uit.path, s, gekozen: true);
        if (_soortSleutel(uit.path) != _soortSleutel(pad)) zetSoort(pad, null);
        if (soortvragen?.verwijder(pad) != null) await soortvragen!.bewaar();
      } else {
        _noteerSoort(uit.path, g.bronpad ?? g.bron);
      }
    } catch (e) {
      return 'Vervangen lukte niet: $e';
    }
    lijst.verwijder(pad);
    await lijst.bewaar();
    _log.line('"$naam": twijfelkopie gekozen (${g.bron}, ${g.kwaliteit}) — vervangen, de vorige staat in _dubbel');
    try {
      await onLibraryChanged();
    } catch (_) {}
    return g.soort == null
        ? 'Vervangen door ${g.kwaliteit} — je vorige kopie staat in _dubbel'
        : 'Gehouden: ${g.soort!.naam} (${g.kwaliteit}) — je vorige kopie staat in _dubbel';
  }

  /// Wie een twijfelkopie naar de prullenbak brengt ([naarPrullenbak]); een toets zet er een nep in, zodat hij nooit
  /// de echte prullenbak van Windows raakt.
  @visibleForTesting
  static Future<Set<String>> Function(List<String> paden) prullenbak = naarPrullenbak;

  /// "Weggooien" uit het twijfelmenu: de twijfelkopie naar de prullenbak (waar die er is), en dezelfde kandidaat komt
  /// niet terug ([Twijfellijst.afgewezen]).
  Future<String> gooiTwijfelWeg(String pad) async {
    final lijst = twijfel;
    final g = lijst?.verwijder(pad, nee: true);
    if (lijst == null || g == null) return 'Er wacht geen twijfelkopie meer voor dit nummer';
    await lijst.bewaar();
    var weg = false;
    if (heeftPrullenbak) {
      try {
        weg = (await prullenbak([g.kandidaat])).contains(g.kandidaat);
      } catch (_) {}
    }
    if (!weg) {
      try {
        await File(g.kandidaat).delete();
      } catch (_) {}
    }
    _log.line('"${baseName(pad)}": ${g.soort == null ? 'twijfelkopie' : '${g.soort!.naam}-kopie'} weggegooid (${g.bron}) — je eigen kopie blijft');
    // Gevraagd: de vraag blijft staan en zoekt meteen de volgende (Saber, 25-10-2026: "weg → volgende zoeken").
    final v = g.soort == null ? null : soortvragen?.van(pad);
    if (v != null && v.soort == g.soort) {
      unawaited(_soortRonde([v]));
      return 'Weggegooid — je eigen kopie blijft. Hij zoekt de volgende ${v.soort.naam}-kopie.';
    }
    return 'Weggegooid — je eigen kopie blijft';
  }

  /// Een gewone vervanging van [pad]: een twijfelkopie ervoor is dan achterhaald (ze werd tegen het oude bestand
  /// gemeten).
  Future<void> _vergeetTwijfel(String pad) async {
    final g = twijfel?.verwijder(pad);
    if (g == null) return;
    try {
      await File(g.kandidaat).delete();
    } catch (_) {}
    await twijfel?.bewaar();
  }

  /// Welke soort [staged] is, uit zijn kop en [bronpad] (kopiesoort.dart).
  static Kopiesoort? _soortVanBinnen(File staged, String bronpad) {
    final kop = readFlacTags(staged);
    return kopiesoortVan(
        bronpad: bronpad,
        bits: kop?.bitsPerSample ?? 0,
        hz: kop?.sampleRate ?? 0,
        verliesvrij: isVerliesvrij(soortVan(staged.path)));
  }

  /// Wat er net op [pad] landde, onthouden als studio, cd of vinyl (kopiesoort.dart). [bronpad]: waar hij vandaan kwam
  /// (het pad bij de uploader, in de torrent, of "TIDAL …") — na het opbergen weet niets anders nog dat het een
  /// vinylrip was. Diepte en bemonstering uit de kop. Een nieuwe kopie zonder soort wist die van de vorige.
  void _noteerSoort(String pad, String bronpad, {bool gekozen = false}) {
    try {
      final kop = readFlacTags(File(pad));
      zetSoort(
          pad,
          kopiesoortVan(
              bronpad: bronpad,
              bits: kop?.bitsPerSample ?? 0,
              hz: kop?.sampleRate ?? 0,
              verliesvrij: isVerliesvrij(soortVan(pad))),
          gekozen: gekozen);
    } catch (_) {/* dan geen label; het bestand staat goed */}
  }

  /// Mag dit binnengehaalde bestand blijven?
  ///
  /// **Geen oordeel is JA.** Een mislukte meting — geen ffmpeg, een te kort nummer, een formaat
  /// waar `readFlacTags` niets van maakt — mag nooit een bestand weigeren. Anders zou het uitvallen
  /// van een verrijking de hele downloadweg stilleggen, en dat is precies wat de meter zelf ook
  /// belooft ("nooit hard falen", `echtheid_meter.dart`).
  ///
  /// Let op wat dit NIET zegt. Op een bestand van 44,1 kHz kan alleen de muurproef spreken: proef B
  /// draait pas boven de 48 kHz en proef A pas boven de 16 bits. "Mag blijven" betekent hier dus
  /// "niets sprak het tegen", niet "bewezen echt".
  static bool magBlijven(Echtheidsoordeel? o) => o == null || !o.isNep;

  /// Hoe lang het bestand op dit pad werkelijk duurt, of null als dat niet te lezen valt.
  int? _duurVan(String pad) {
    try {
      final s = readFlacTags(File(pad))?.duration?.inSeconds;
      return s == null || s <= 0 ? null : s;
    } catch (_) {
      return null;
    }
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
    // De officiële lengte van wat we zoeken, voor de volgorde van de race en de opwaardeerjacht. Niet bij
    // jouw eigen keuze: een aangewezen bestand of een zelf gekozen albummap is wat je wilde.
    final officieel = keuze == null && !vast ? job.authority?.seconds : null;

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

    /// Waar het bestand ligt dat bleef (zie [oordeelVanWatErLigt]) — voor de 24bit-zoektocht na het landen.
    String? padVanWatErLigt;

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
    Future<bool> succeed(SlskDone res, SoulseekFile from) async {
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
        final bestaand = await _bereidVergelijkingVoor(staged, job.authority);
        // Een ANDERE opname dan wat je hebt: niet eroverheen, maar ernaast. Zonder dit stuurt
        // [mapVanBestaande] hem op artiest en titel naar jouw bestand, en dan vergelijkt de keuring
        // twee verschillende nummers met elkaar.
        final andere = bestaand != null && await _zelfdeOpname(staged.path, bestaand) == false;
        if (andere) {
          _log.line('   ${job.name}: een andere opname dan wat je hebt — ernaast, niet eroverheen');
        }
        final uit = await placeFileDetailed(staged, _downloadsRoot,
            tags: job.authority, staatAl: andere ? null : mapVanBestaande);
        how = uit.how;
        if (how == Placement.duplicate && bestaand != null) {
          _log.line('   ${job.name}: niet bewezen beter dan wat je hebt — ${whyBetter(File(uit.path), staged)}; '
              'de nieuwe is weggegooid');
        }
        // Pas HIER, want `uit.path` is het bestand dat blijft — bij `moved` de nieuwe kopie (het
        // oordeel is meeverhuisd), bij `duplicate` de kopie die er al lag en gewonnen heeft.
        oordeelVanWatErLigt = gemeten(uit.path);
        padVanWatErLigt = uit.path;
        if (how == Placement.moved) _noteerSoort(uit.path, from.filename);
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
        // Kort, want op een gsm is deze regel 211 punten: "had je al in minstens even goede…" zei
        // niet wát er gebeurde (S26, 16-10-2026). Zie [detailRegels].
        Placement.duplicate => 'had je al, even goed of beter — niet bewaard',
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
    Future<(SlskDone, SoulseekFile)?> race(List<SoulseekFile> pool, String label, {bool alsLossy = false}) async {
      final cap = alsLossy ? _maxLossyTries : (job.ruim ? kWedloopLopers : _maxLosslessTries);
      final order = sweepOrderFor(pool, first: keuze);
      final n = order.length < cap ? order.length : cap;

      SlskDone? winner;
      SoulseekFile? winnerFile;
      SoulseekFile? leader; // the peer currently sending; owns the progress line
      // Zijn stopschakelaar en wanneer hij begon te sturen: een trage leider maakt plaats ([teTraag]).
      SlskCancel? leaderStop;
      DateTime? leaderSinds;
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
        // Antwoordt hij na [kVerbindGeduld] nog niet (onbereikbaar: rechtstreeks 3 s, dan via de server tot
        // 15 s), dan mag de race alvast de volgende vragen — hij blijft gewoon verder verbinden.
        final geduld = job.ruim
            ? Timer(kVerbindGeduld, () {
                if (!moveOn.isCompleted && !identical(leader, f)) moveOn.complete();
              })
            : null;
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
              leaderStop = c;
              leaderSinds = DateTime.now();
              return true;
            }
            // **Een trage leider maakt plaats** voor wie nu begint te sturen. Gemeten op 20-10-2026 (⬇ van
            // Lola Young — Messy, vanaf de gsm): de leider leverde 42 kB/s, en elke snellere die daarna
            // begon werd hier gestopt — tien minuten voor één nummer.
            final l = leader!, sinds = leaderSinds;
            if (sinds != null) {
              int binnen;
              try {
                binnen = _bestemming(l).lengthSync();
              } catch (_) {
                binnen = 0;
              }
              final bezig = DateTime.now().difference(sinds);
              if (teTraag(binnen: binnen, totaal: l.size, bezig: bezig)) {
                final kBs = binnen / max(1, bezig.inMilliseconds) * 1000 / 1024;
                _log.line('   ${l.username}: te traag (${kBs.round()} kB/s, ${(binnen / 1048576).toStringAsFixed(1)} '
                    'van ${(l.size / 1048576).toStringAsFixed(1)} MB) — ${f.username} neemt over');
                leaderStop?.cancel();
                leader = f;
                leaderStop = c;
                leaderSinds = DateTime.now();
                return true;
              }
            }
            c.cancel(); // someone else is already sending — don't burn bandwidth alongside them
            return false;
          },
        );
        job.live.remove(c);
        geduld?.cancel();
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
      final feeders = List.generate(raceBreedte(actief: _slskActive, cap: n), (_) => feeder());
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
      final ok = await succeed(res, from);
      // Bij een handmatige keuze: niets van dit alles. "Beter" is hier een ánder bestand, en de
      // gebruiker heeft juist gezegd dat hij DIT wil. Dagen later alsnog vervangen door een kopie die
      // hoger scoort is dezelfde overrule, alleen trager.
      //
      // Sinds 29-08-2026 geldt dat ook voor een heel album dat je zelf uit een lijst koos, en dat is
      // met zoveel woorden gevraagd. De prijs staat erbij en is echt: haal je een mp3-album omdat er
      // op dat moment geen lossless was, dan gaat de app er daarna niet meer zelf achteraan.
      if (vast) return ok;
      // "Beter" mag nooit verder van de officiële lengte liggen dan wat er nu ligt: een 24/96 live-opname
      // van 3:54 is geen opwaardering van een 24/44,1 van 3:59. Zie [lengteKlopt].
      var better = vinylAchteraan(ranked.where((f) => magOpwaarderen(f, from, officieel)).toList(), (f) => f.filename);
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
      // En "24bit" op de achtergrond, als wat er ligt 16 bit of minder is (Saber, 24-10-2026: "na het landen").
      if (ok) _naLandenHires(padVanWatErLigt, job.authority, from);
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

    // **Binnen elke bak eerst wat de officiële lengte heeft.** Een race wint wie het eerst VERSTUURT, dus
    // "het dichtst bij de officiële tijd" kan niet uit een sortering komen — alleen uit wat er meedoet.
    // Gemeten op 30-09-2026 met Sam Smith — I'm Not The Only One (officieel 3:59): de peers boden 3:59
    // (24/96 en 24/44,1), 3:54 (de live-opname uit de Royal Albert Hall), 3:43 en 3:40. Allemaal binnen
    // de twaalf seconden van [fileOffersTitle], dus allemaal in dezelfde race. Nu doen eerst alleen de
    // 3:59-kopieën mee, en de rest pas als geen van die levert — de rest is niet fout (een andere persing
    // verschilt ook weleens vijf tellen), maar hij is niet de eerste keus. Zie [lengteDelen].
    List<List<SoulseekFile>> opLengte(List<SoulseekFile> bak) => lengteDelen(bak, officieel);

    /// Eén bak, in de delen van [opLengte]. Het tweede deel meldt zich, want "hij probeert nu een kopie
    /// van een andere lengte" hoort op het scherm te staan en niet alleen in het logboek.
    Future<(SlskDone, SoulseekFile)?> bak(List<SoulseekFile> pool, String label, {bool alsLossy = false}) async {
      final delen = opLengte(pool);
      if (delen.length > 1) {
        _log.line('"${job.name}": ${delen.first.length} kandidaat/kandidaten met de officiële lengte '
            '(${_mmss(officieel!)}) gaan voor, ${delen.last.length} andere wachten');
      }
      for (var i = 0; i < delen.length; i++) {
        if (i > 0) {
          if (job.cancelled) return null;
          job.detail = 'geen kopie van ${_mmss(officieel!)} leverde — nu een van een andere lengte';
          notifyListeners();
          _log.line('"${job.name}": geen kopie met de officiële lengte leverde — nu de andere lengtes');
        }
        final r = await race(delen[i], i == 0 ? label : '$label, andere lengte', alsLossy: alsLossy);
        if (r != null) return r;
      }
      return null;
    }

    // ── 1. Stereo lossless: the thing you actually want ──────────────────────
    final first = await bak(stereo, 'poging');
    if (first != null) return finish(first.$1, first.$2);

    if (job.cancelled) return false;

    // ── 2. Surround — lossless, but it downmixes on a stereo system and costs ten times the space
    if (surround.isNotEmpty) {
      job.detail = 'alleen surround beschikbaar — 5.1 als tweede keus';
      notifyListeners();
      final second = await bak(surround, '5.1-poging');
      if (second != null) return finish(second.$1, second.$2);
      if (job.cancelled) return false;
    }

    // ── 3. Only now, lossy — an MP3 is a last resort, never a shortcut ───────
    if (lossy.isNotEmpty) {
      job.detail = 'geen lossless beschikbaar — MP3 als laatste optie';
      notifyListeners();
      final third = await bak(lossy, 'MP3-poging', alsLossy: true);
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
  ///
  /// Ook het OORDEEL gaat weg. Sinds de wensweg meet vóór het opbergen wordt er een oordeel bewaard
  /// op het pad in `_inkomend`, en dat pad verdwijnt hier. Zonder dit groeit
  /// `echtheid_oordelen.json` met elke afgewezen kandidaat — en `nepSleutels()` gaat bij elke scan
  /// mee naar een isolate.
  Future<void> _discardStaged(String path) async {
    try {
      vergeetOordeel(path);
    } catch (_) {/* er hoefde er geen te staan */}
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

  /// Voor de strook op het scherm: "65,4 MB". Uit de aangekondigde grootte en niet van schijf —
  /// hier is er nog geen bestand.
  static String _mb(int bytes) =>
      bytes <= 0 ? '' : '${(bytes / 1048576).toStringAsFixed(1)} MB';

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
    // Meteen op het scherm: de strook hoort na een herstart te zeggen hoeveel er nog openstaat,
    // niet pas na de eerste veegbeurt twintig minuten later.
    jacht.value = jacht.value.met(opDeLijst: _wants.count);
  }

  /// Hoeveel nummers wachten er nog op hun FLAC. Voor het scherm en voor het logboek.
  int get losslessWanted => _wants.count;

  /// Zorg dat de strook op de Kwaliteitspagina een getal heeft.
  ///
  /// **Waarom dit nodig is.** De verlanglijst wordt lui geladen: pas als er iets mee gebeurt. De
  /// eerste veegbeurt komt drie minuten na de start, en tot dan stond [jacht] op nul — waardoor de
  /// strook zichzelf verborg. Gezien op 08-09-2026 na een verse installatie: de knop zei "Laat de
  /// app zoeken (165)" en eronder stond niets. Precies het beeld waar die strook tegen gebouwd is.
  Future<void> ververJachtStand() async {
    await _ensureWants();
    jacht.value = jacht.value.met(opDeLijst: _wants.count);
  }

  /// Hier hoeft niet meer naar gezocht te worden.
  ///
  /// **Zonder dit komt een weggegooid nummer terug.** Landt een radiohaal als mp3, dan zet
  /// [_wantLossless] hem op de verlanglijst; twintig minuten later haalt [sweepLosslessWants] alsnog
  /// de FLAC — van een nummer dat je zojuist met een rode duim hebt weggedaan. Dat is niet alleen
  /// vervelend, het is onbegrijpelijk: je hebt het weggegooid en het staat er weer.
  /// Zet betrapte nummers op de verlanglijst, zodat de app zélf een echte kopie gaat zoeken.
  ///
  /// **Waarom dit er is.** De kwaliteitslijst toont wat er afgekapt is en laat je zelf een vervanger
  /// aanwijzen. Dat werkt, maar het vraagt dat jij erbij zit. Gemeld op 30-08-2026 met Gorki — Anja:
  /// een 24/44.1 die op 17,4 kHz dichtklapt. Liever een echte 16/44.1 dan een opgeblazen 24 — en dan
  /// moet de app ernaar op zoek, ook als er vandaag geen goede bron is.
  ///
  /// Dat zoeken kan de verlanglijst al: hij probeert het opnieuw met een steeds ruimer wordend ritme,
  /// overleeft een herstart, en houdt bij welke peers al nee zeiden. Wat ontbrak is dat een betrapt
  /// bestand er ooit op kwam.
  ///
  /// Wie er wint als de vervanger binnen is beslist `firstIsBetter`, en die kent `bewezenNep`: een
  /// betrapt bestand verliest daar ook als het gróter is. Een echte 16/44.1 wint dus van een
  /// opgeblazen 24/44.1 — precies waar het om gaat.
  ///
  /// Geeft terug hoeveel er nieuw op de lijst kwamen.
  /// [gezag] bouwt de tags waarmee de vervanger moet landen. Meegeven, want de bibliotheek weet
  /// meer dan één `Track`: `albumArtist` en `trackTotal` maken `TrackTags.isAuthoritative` waar, en
  /// dát is wat de vervanger ÓP het origineel laat landen in plaats van ernaast als `(2)`. Zonder
  /// deze haak bouwde dit met de hand een armere tagset dan `library.tagsVoorVervanger` al kon.
  Future<int> wensEchteVersies(Iterable<Track> nummers,
      {TrackTags Function(Track)? gezag}) async {
    await _ensureWants();
    var nieuw = 0;
    for (final t in nummers) {
      if (t.artist.trim().isEmpty || t.title.trim().isEmpty) {
        _log.line('"${t.title}": betrapt, maar zonder artiest+titel valt er niets te zoeken');
        continue;
      }
      // WAT JE ZELF KOOS BLIJFT DE BAAS. Een handmatig aangewezen bestand hoort niet op de jachtlijst:
      // `firstIsBetter` laat zo'n keuze van niets verliezen, dus alles wat hiervoor binnenkomt wordt
      // meteen weer geparkeerd. Zoeken naar een vervanger die niet mag vervangen is verspilling.
      if (isVasteKeuze(t.path)) {
        _log.line('"${t.artist} — ${t.title}": betrapt, maar door jou zelf gekozen — met rust gelaten');
        continue;
      }
      final erbij = _wants.want(LosslessWant(
        artist: t.artist.trim(),
        title: t.title.trim(),
        album: t.album,
        sinceMs: DateTime.now().millisecondsSinceEpoch,
        // Het gezag van wat er NU ligt gaat mee: de vervanger hoort op dezelfde plek en met dezelfde
        // nummering te belanden, ook als de peer een bestand zonder tags stuurt.
        authority: gezag?.call(t) ??
            TrackTags(
              artist: t.artist,
              title: t.title,
              album: t.album,
              trackNo: t.trackNo,
              year: t.year,
            ),
      ));
      if (erbij) nieuw++;
    }
    if (nieuw > 0) {
      await _wants.save();
      _log.line('$nieuw betrapt(e) nummer(s) op de verlanglijst gezet '
          '(${_wants.count} op de lijst)');
    }
    // Ook bij nul: dan stonden ze er al, en juist dán moet de strook laten zien HOEVEEL er staan.
    jacht.value = jacht.value.met(opDeLijst: _wants.count);
    return nieuw;
  }

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

  /// Wensen laten vallen waarvan een verliesvrije kopie inmiddels in de bibliotheek staat.
  ///
  /// Stond alleen bovenaan [sweepLosslessWants], en die draait om de twintig minuten. Een torrent die
  /// net een hele plaat heeft opgeborgen hoort de jacht op die plaat METEEN te stoppen, niet pas een
  /// kwartier later — anders haalt Soulseek er intussen nog een kopie van binnen die daarna naar
  /// `_dubbel` gaat. Zie [_bergTorrentOp].
  Future<int> vergeetWatErAlIs() async {
    await _ensureWants();
    final have = haveLossless;
    if (have == null) return 0;
    final weg = _wants.forgetWhatWeHave(have);
    if (weg.isEmpty) return 0;
    await _wants.save();
    jacht.value = jacht.value.met(opDeLijst: _wants.count);
    _log.line('wensen: ${weg.length} vervallen — die staat al verliesvrij in de bibliotheek');
    return weg.length;
  }

  /// Elk verliesvrij bestand dat een torrent net afleverde door de echtheidsmeter halen.
  ///
  /// [_meetEchtheid] onthoudt het oordeel op het huidige pad, en het verplaatsen neemt het mee
  /// (`herNoemOordeel` in `_move`). Wat de meter niet kan lezen — een APE, een WavPack — levert geen
  /// oordeel, en dat is geen nee: zie [magBlijven].
  Future<void> _meetBinnengekomen(Directory destDir, String naam) async {
    final bestanden = <File>[];
    try {
      await for (final e in destDir.list(recursive: true, followLinks: false)) {
        // Wat nog binnenkomt niet: een halve FLAC meten levert een oordeel over een half bestand.
        if (e is File && isVerliesvrij(e.path.split('.').last) && !_inAanmaak.contains(e.path)) {
          bestanden.add(e);
        }
      }
    } catch (_) {
      return;
    }
    for (final f in bestanden) {
      final o = await _meetEchtheid(f);
      if (o != null && o.isNep) {
        _log.line('torrent "$naam": ${f.uri.pathSegments.last} — ${waarom(o)}');
      }
    }
  }

  /// Een binnengekomen torrent keuren en opbergen zoals een Soulseek-download dat al werd.
  ///
  /// **Waarom het opbergen er moest komen.** Soulseek en torrent hielden geen rekening met elkaar, en
  /// Saber zag dat zelf: *"torrent vervangt de soulseek download niet, en anders om ook niet"*. Een
  /// Soulseek-nummer gaat bij binnenkomst door [placeFileDetailed] en landt in de albummap, waar
  /// [firstIsBetter] kiest wat blijft; een torrent bleef liggen tot iemand op "Opruimen" drukte.
  /// Gemeten op 17-09-2026: Culture Beat — Mr. Vain lag sinds 14-09 als schone 24/192 van een torrent
  /// náást de bibliotheek, terwijl in `Albums\` de als opgeblazen gemeten Soulseek-kopie bleef staan.
  ///
  /// **Waarom er sinds 29-09-2026 eerst gekeurd wordt.** Tot dan kwam een torrent binnen in een map die
  /// de bibliotheek inleest, en won hij als "jouw keuze" van alles wat je niet zelf koos — ook als hij
  /// kapot of slechter was. Saber die dag, bij Blood On The Dance Floor: *"als er een slechtere binnenkomt
  /// dan wat ik heb moet die weg, en moet mijn betere kwaliteit die ik al had blijven."* Nu wacht de
  /// torrent in de keuringsmap ([keuringMap]), en per bestand:
  ///
  ///  * kapot (de decodeerproef, [controleerHeel]) — naar `_dubbel`, niet de bibliotheek in;
  ///  * bewezen slechter of gelijk aan wat er ligt — naar `_dubbel`, en wat je had blijft staan;
  ///    bij gelijk wint alleen jouw keuze, en een torrent IS jouw keuze ([_jouwKeuze]);
  ///  * bewezen beter — neemt de plek in, en wat er lag gaat naar `_dubbel` (nooit weg).
  ///
  /// Wat niet op te bergen is maar wel heel — een nummer zonder leesbare tags, een .cue, een boekje —
  /// gaat terug naar `DebridMusic Downloads\<torrent>`, waar het vroeger ook stond ([_zetRestZichtbaar]).
  /// Onder elk nummer in [binnen] komt te staan wat de keuring besliste.
  Future<TidyReport?> _bergTorrentOp(Directory destDir, String naam,
      {Directory? zichtbaar, List<DownloadJob> binnen = const []}) async {
    TidyReport? r;
    try {
      // Meten vóór het opbergen, net als elke Soulseek-landingsweg. Gemeten op 18-09-2026 met Kings of
      // Leon — Sex On Fire: een 24/192-vinylrip van RuTracker die de meter van deze app "niets boven
      // 22 kHz — opgeschaald, geen echte hi-res" noemt. Zonder meting geldt hij als "hi-res volgens de
      // kop, niet bewezen", en dan kan hij niets vervangen — met meting weet de keuring waar hij staat.
      await _meetBinnengekomen(destDir, naam);
      // **`nietIn: destDir` hoort er nog bij.** De bibliotheek leest de keuringsmap niet, dus daar kan
      // ze het torrentbestand zelf niet meer aanwijzen. Maar een torrent die vóór 29-09-2026 in de
      // zichtbare map binnenkwam en nu pas opgeborgen wordt, kent ze wél — en "waar staat deze opname
      // al?" mag nooit het bestand zelf antwoorden. Gemeten op 17 en 18-09-2026: vijf platen van Justin
      // Bieber bleven zo liggen met "0 verplaatst". Zie [LibraryStore.fileOfRecording].
      final zoek = mapVanBestaande;
      r = await bergMapOp(destDir.path, _downloadsRoot,
          staatAl: zoek == null
              ? null
              : (artist, title, {int? seconds}) =>
                  zoek(artist, title, seconds: seconds, nietIn: destDir.path),
          // Een ander nummer uit dezelfde torrent dat nog binnenkomt blijft staan; zijn eigen
          // download bergt het op als het klaar is. Zie [_inAanmaak].
          slaOver: _inAanmaak.contains,
          keur: _keurVoorBibliotheek,
          alGehad: _alGehadOnderAndereTitel);
      _log.line('torrent "$naam" gekeurd en opgeborgen: $r');
      for (final p in r.tegengehouden) {
        _log.line('torrent "$naam": ${p.split(Platform.pathSeparator).last} — ${r.uitkomst[p]}');
      }
      // Alleen voor wat een lopende opdracht nog ophaalt: de rest (een geknipt nummer, een restant van
      // de vorige keer) heeft geen regel in de lijst, en zou hier anders blijven hangen.
      final wachtend = {
        for (final j in jobs)
          if (j.busy && j.keuringsPad != null) j.keuringsPad!,
      };
      for (final e in r.uitkomst.entries) {
        if (!wachtend.contains(e.key)) continue;
        _gekeurd[e.key] = (zin: e.value, afgekeurd: r.tegengehouden.contains(e.key));
      }
    } catch (e) {
      // Blijft liggen waar hij lag — in de keuringsmap, en dus NIET in je bibliotheek. Bij de volgende
      // start probeert [hervatKeuring] het opnieuw.
      _log.line('torrent "$naam" keuren of opbergen mislukt: $e — hij wacht in $keuringMap');
    }
    // Wat er over is terug naar waar het vroeger stond — maar pas als niemand anders meer in deze
    // keuringsmap werkt. Zie [_opKeuring].
    var zichtbaarGezet = <String, String>{};
    // Alleen na een keuring die ook echt liep: viel ze om, dan is "de rest" alles — en dan zou deze stap
    // ongekeurde bestanden alsnog zichtbaar maken. Die wachten liever tot [hervatKeuring].
    if (r != null && zichtbaar != null && (_opKeuring[destDir.path] ?? 0) <= 1) {
      try {
        zichtbaarGezet = await _zetRestZichtbaar(destDir, zichtbaar, r.tegengehouden);
      } catch (e) {
        _log.line('torrent "$naam": de rest terugzetten mislukt: $e');
      }
    }
    for (final j in binnen) {
      final p = j.keuringsPad;
      if (p == null || j.cancelled || j.status == 'failed') continue;
      final u = _gekeurd.remove(p);
      final elders = zichtbaarGezet[p];
      final String zin;
      if (u != null) {
        zin = elders == null ? u.zin : '${u.zin} — staat in ${zichtbaar!.path}';
      } else if (elders != null) {
        zin = 'niet op te bergen — staat in ${zichtbaar!.path}';
      } else if (!File(p).existsSync()) {
        // Een image dat in losse nummers geknipt is: die nummers zijn elk apart gekeurd.
        zin = 'binnen en gekeurd';
      } else if (r == null) {
        zin = 'binnen, maar de keuring liep vast — hij wacht in $keuringMap en wordt bij de volgende '
            'start opnieuw gekeurd';
      } else {
        zin = 'binnen, maar nog niet gekeurd — wacht in $keuringMap';
      }
      // Niet in je bibliotheek is niet "klaar": afgekeurd, of een keuring die omviel.
      j.status = (u != null && u.afgekeurd) || (u == null && elders == null && r == null && File(p).existsSync())
          ? 'failed'
          : 'done';
      j.detail = j.naKeuring == null ? zin : '$zin · ${j.naKeuring}';
    }
    notifyListeners();
    final r2 = r;
    if (r2 == null) return null;
    if (r2.moved + r2.duplicates + r2.afgekeurd == 0 && zichtbaarGezet.isEmpty) return r2;
    await onLibraryChanged();
    await vergeetWatErAlIs();
    return r2;
  }

  /// Een nieuwe keuringsmap voor een download die niet via de torrentrij loopt — TIDAL.
  ///
  /// Hij telt meteen als "in gebruik" ([_opKeuring]), zodat [hervatKeuring] een download die nog
  /// binnenkomt niet voor een restant van de vorige keer aanziet. [keurBinnengekomen] geeft hem vrij.
  Directory keuringsmapVoor(String naam) {
    final d = Directory('$_downloadsRoot${Platform.pathSeparator}$keuringMap'
        '${Platform.pathSeparator}${_sanitize(naam)}');
    d.createSync(recursive: true);
    _opKeuring.update(d.path, (n) => n + 1, ifAbsent: () => 1);
    return d;
  }

  /// Alles in [map] keuren en opbergen, zoals een torrent ([_bergTorrentOp]), en de map vrijgeven.
  ///
  /// [jouwKeuze]: je hebt dit zelf opgehaald, dus bij gelijke kwaliteit wint het van wat er lag — net
  /// als een torrent ([_jouwKeuze]). Wat niet op te bergen is gaat naar [zichtbaar].
  Future<TidyReport?> keurBinnengekomen(Directory map, String naam,
      {required Directory zichtbaar, bool jouwKeuze = true}) async {
    try {
      if (jouwKeuze && await map.exists()) {
        await for (final e in map.list(recursive: true, followLinks: false)) {
          if (e is File && isAudioBestand(e.path)) await _jouwKeuze(e.path);
        }
      }
      return await _bergTorrentOp(map, naam, zichtbaar: zichtbaar);
    } finally {
      _geefKeuringsmapVrij(map);
    }
  }

  /// De tegenhanger van [keuringsmapVoor].
  void _geefKeuringsmapVrij(Directory map) {
    final over = (_opKeuring[map.path] ?? 1) - 1;
    if (over <= 0) {
      _opKeuring.remove(map.path);
    } else {
      _opKeuring[map.path] = over;
    }
  }

  /// Waar wat van TIDAL niet op te bergen is terechtkomt: zichtbaar, zoals vroeger alles van tiddl (nu tidaler).
  Directory get tidalRest => Directory('$_downloadsRoot${Platform.pathSeparator}TIDAL');

  /// Zoek in `_dubbel` wat er ten onrechte vervangen werd: kopieën die onder de regel van 29-09-2026
  /// ([firstIsBetter]) hadden moeten blijven staan. Alleen lezen en meten — er verhuist hier niets.
  ///
  /// **Waarom.** Saber, over Blood On The Dance Floor: *"ik kon zweren, dat ik alle liedjes in beste
  /// kwaliteit had … en nu staan er een paar … in mindere kwaliteit."* Gemeten die dag: van de 95
  /// kopieën in `_dubbel` hadden er 47 een opvolger met een lager label. Een deel terecht (een
  /// opgeschaalde 24/192 Material Girl voor een echte 24/96), een deel niet (Is It Scary: een
  /// opgeschaalde 24/96 voor een eerlijke 24/48 — dezelfde muziek, geen winst).
  ///
  /// Per kopie drie bewijzen, anders geen voorstel:
  ///  * hij is heel ([controleerHeel]) — een kapotte kopie terugzetten is geen herstel;
  ///  * wat er nu staat is NIET bewezen beter; bij gelijk blijft wat je had, tenzij je de nieuwe zelf
  ///    koos (dan wint die, zie [firstIsBetter]);
  ///  * het is dezelfde opname (vingerafdruk) — zelfde titel is geen zelfde nummer. Zonder fpcalc dus
  ///    geen voorstellen: liever niets dan een gok.
  ///
  /// Alleen de bovenste laag van `_dubbel`: daar staat wat VERVANGEN werd. Wat binnenkwam en verloor
  /// ([parkeerBinnenkomer]) of werd afgekeurd ([parkeerAfgekeurd]) was nooit van jou.
  Future<List<Terugzetting>> zoekTerugzettingen(
      {void Function(int gedaan, int totaal)? voortgang}) async {
    final zoek = mapVanBestaande;
    final dubbel = Directory('$_downloadsRoot${Platform.pathSeparator}$parkeerMap');
    if (zoek == null || !await dubbel.exists()) return const [];
    final kandidaten = <File>[];
    await for (final e in dubbel.list(followLinks: false)) {
      if (e is File && isAudioBestand(e.path)) kandidaten.add(e);
    }
    final perHuidig = <String, Terugzetting>{};
    for (var i = 0; i < kandidaten.length; i++) {
      voortgang?.call(i, kandidaten.length);
      final p = kandidaten[i];
      try {
        final v = await _terugzettingVoor(p, zoek, dubbel.path);
        if (v == null) continue;
        // Twee kopieën voor dezelfde plek ("(2) 01 - 7 Years.flac" naast "01 - 7 Years.flac"): de
        // beste, en bij gelijk de eerste.
        final eerder = perHuidig[v.huidig];
        if (eerder != null && !firstIsBetter(p, File(eerder.geparkeerd))) continue;
        perHuidig[v.huidig] = v;
      } catch (e) {
        _log.line('terugzetten: ${p.path} overgeslagen — $e');
      }
    }
    voortgang?.call(kandidaten.length, kandidaten.length);
    final uit = perHuidig.values.toList()
      ..sort((a, b) => '${a.artiest} ${a.titel}'.toLowerCase().compareTo('${b.artiest} ${b.titel}'.toLowerCase()));
    _log.line('terugzetten: ${uit.length} voorstel(len) uit ${kandidaten.length} geparkeerde kopieën');
    return uit;
  }

  /// De decodeerproef voor het terugzetten, als veld zodat een toets "niet te zeggen" kan naspelen.
  ///
  /// Zonder ffmpeg (of na de tijdslimiet) geeft [controleerHeel] null. Dan is "heel" niet bewezen, en
  /// een kopie waarvan dat niet vaststaat hoort niet terug in je bibliotheek — ook al zegt de
  /// kwaliteitsvergelijking dan niets tegen, want zij weet evenmin dat hij kapot is.
  @visibleForTesting
  Future<Heelheid?> Function(String pad) decodeerproef = controleerHeel;

  Future<Terugzetting?> _terugzettingVoor(File p,
      String? Function(String artist, String title, {int? seconds, String? nietIn}) zoek,
      String dubbel) async {
    final t = readTags(p);
    if (t == null) return null;
    final huidig = zoek(t.artist, t.title, seconds: looptijdInSeconden(p), nietIn: dubbel);
    if (huidig == null) return null;
    final c = File(huidig);
    if (!await c.exists()) return null;
    final heel = await decodeerproef(p.path);
    if (heel == null || !heel.heel) return null;
    await decodeerproef(c.path);
    if (gemeten(p.path) == null) await _meetEchtheid(p);
    if (gemeten(c.path) == null) await _meetEchtheid(c);
    if (firstIsBetter(c, p)) return null;
    if (await _zelfdeOpname(p.path, c.path) != true) return null;
    return Terugzetting(
      geparkeerd: p.path,
      huidig: c.path,
      artiest: t.artist,
      titel: t.title,
      reden: firstIsBetter(p, c)
          ? whyBetter(p, c)
          : 'even goed (${kwaliteitZin(kwaliteitVan(p))}) — de vervanging was geen winst',
    );
  }

  /// De gekozen voorstellen uitvoeren. Geeft het aantal dat lukte.
  ///
  /// Wat er nu staat gaat naar `_dubbel\binnengekomen` en niet naar `_dubbel` zelf: het is de
  /// binnenkomer die onder de regel van 29-09-2026 had moeten verliezen. In `_dubbel` zelf zou een
  /// volgende zoekronde hem als "ten onrechte vervangen" zien, en bij gelijke kwaliteit gingen de twee
  /// dan eindeloos heen en weer.
  Future<int> zetTerug(List<Terugzetting> lijst) async {
    final sep = Platform.pathSeparator;
    final opzij = '$_downloadsRoot$sep$parkeerMap$sep$parkeerBinnenkomer';
    var n = 0;
    for (final v in lijst) {
      final uit = await zetGeparkeerdeTerug(File(v.geparkeerd), File(v.huidig), parkeerIn: opzij);
      if (uit == null) {
        _log.line('terugzetten mislukt: ${v.geparkeerd} — alles staat nog zoals het stond');
        continue;
      }
      n++;
      _log.line('teruggezet: ${v.artiest} — ${v.titel} (${v.reden})');
    }
    if (n > 0) await onLibraryChanged();
    return n;
  }

  /// Wat de keuring per pad besliste, voor een opdracht die zijn uitkomst nog niet ophaalde.
  ///
  /// Twee keuzes uit dezelfde torrent delen één keuringsmap, en wie het eerst klaar is keurt ook wat de
  /// ander al binnen had. Zonder dit bleef het nummer van de tweede op "wacht op de keuring" staan,
  /// terwijl het allang gekeurd en opgeborgen was.
  final Map<String, ({String zin, bool afgekeurd})> _gekeurd = {};

  /// De keuring van één binnengekomen bestand, vóór het de bibliotheek in mag. Geeft de reden van
  /// afkeuren terug, of null.
  ///
  /// Eerst de decodeerproef ([controleerHeel]): een bestand dat ffmpeg niet tot het einde krijgt is
  /// kapot, hoe mooi zijn kop ook is. Dat is precies wat er bij Blood On The Dance Floor binnenkwam, en
  /// tot 29-09-2026 keek niemand ernaar. Kan er niet gedecodeerd worden (geen ffmpeg), dan houdt dit
  /// niets tegen: niet weten is niet afkeuren.
  ///
  /// Daarna wordt gemeten wat er AL ligt, zodat [firstIsBetter] op bewijs vergelijkt: een eigen kopie
  /// die nooit gemeten werd telt als "weet niet", en dan kan een bewezen betere hem niet vervangen —
  /// en een kapotte eigen kopie hoort juist te verliezen, ook dat moet eerst bekend zijn.
  Future<String?> _keurVoorBibliotheek(File f) async {
    final h = await controleerHeel(f.path);
    if (h != null && !h.heel) return 'kapot bestand (${h.reden ?? 'decodeert niet tot het einde'})';
    final t = readTags(f);
    if (t == null) return null;
    final bestaand = mapVanBestaande?.call(t.artist, t.title,
        seconds: looptijdInSeconden(f), nietIn: f.parent.path);
    if (bestaand != null && File(bestaand).existsSync()) {
      if (gemeten(bestaand) == null) await _meetEchtheid(File(bestaand));
      await controleerHeel(bestaand);
    }
    return null;
  }

  /// Staat deze opname al in je bibliotheek onder een ANDERE titel, en is de binnenkomer niet beter?
  ///
  /// Gevonden bij de proef op 29-09-2026: "Earth Song (Hani's Club Experience).mp3" kwam naast
  /// "Earth Song (Hani's Extended Radio Experience).wv" te staan — dezelfde opname (475,4 tegen 475,5 s,
  /// vingerafdruk 0,91), alleen anders getiteld door een andere bron. Het opbergen zoekt op titel en
  /// bestandsnaam en zag dus niets.
  ///
  /// Alleen als de titel NIETS oplevert: vindt de bibliotheek hem op titel, dan vergelijkt het
  /// opbergen zelf al ([staatAl]). Kandidaten zijn nummers van dezelfde artiest met bijna dezelfde
  /// lengte ([opLengte]); of het dezelfde opname is beslist de vingerafdruk. Zonder fpcalc of
  /// zonder leesbare lengte: niets tegenhouden.
  Future<bool> _alGehadOnderAndereTitel(File f) async {
    final kandidaten = opLengte;
    if (kandidaten == null) return false;
    final t = readTags(f);
    final sec = looptijdInSeconden(f);
    if (t == null || sec == null) return false;
    if (mapVanBestaande?.call(t.artist, t.title, seconds: sec, nietIn: f.parent.path) != null) {
      return false;
    }
    for (final c in kandidaten(t.artist, sec, nietIn: f.parent.path)) {
      if (!File(c).existsSync()) continue;
      if (await _zelfdeOpname(f.path, c) != true) continue;
      if (gemeten(c) == null) await _meetEchtheid(File(c));
      await controleerHeel(c);
      if (firstIsBetter(f, File(c))) continue;
      _log.line('keuring: ${f.uri.pathSegments.last} is dezelfde opname als '
          '${c.split(Platform.pathSeparator).last} (andere titel) en niet beter — opzij');
      return true;
    }
    return false;
  }

  /// Wat na het opbergen nog in de keuringsmap ligt, terugzetten waar het vroeger binnenkwam.
  ///
  /// Dat is alleen wat de keuring niet tegenhield maar ook niet kon opbergen: een nummer zonder
  /// leesbare tags, een .cue, een boekje, een logbestand. Tot 29-09-2026 bleef dat in
  /// `DebridMusic Downloads\<torrent>` liggen en stond zo'n nummer toch in je bibliotheek; zonder deze
  /// stap zou het nu onzichtbaar in `_keuring` blijven staan.
  ///
  /// Nooit wat afgekeurd is ([tegengehouden]) — ook niet als het parkeren daarvan mislukte: dat hoort
  /// juist níet zichtbaar te worden. En nooit wat nog binnenkomt ([_inAanmaak], een `.part`). Geeft per
  /// verhuisd bestand het nieuwe pad.
  Future<Map<String, String>> _zetRestZichtbaar(
      Directory keuring, Directory zichtbaar, Set<String> tegengehouden) async {
    final verhuisd = <String, String>{};
    if (!await keuring.exists()) return verhuisd;
    final rest = <File>[];
    await for (final e in keuring.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      if (_inAanmaak.contains(e.path) || tegengehouden.contains(e.path)) continue;
      if (e.path.toLowerCase().endsWith('.part')) continue;
      rest.add(e);
    }
    final sep = Platform.pathSeparator;
    for (final f in rest) {
      // De submap uit de torrent blijft behouden: "CD1\01.flac" en "CD2\01.flac" horen niet op elkaar.
      final onder = f.path.substring(keuring.path.length);
      var doel = File('${zichtbaar.path}$onder');
      try {
        await doel.parent.create(recursive: true);
        final naam = doel.uri.pathSegments.last;
        for (var n = 2; await doel.exists(); n++) {
          doel = File('${doel.parent.path}$sep($n) $naam');
        }
        verhuisd[f.path] = await moveWithRetry(f, doel);
      } catch (_) {/* blijft in de keuringsmap; de volgende start probeert het opnieuw */}
    }
    await _ruimLegeMappen(keuring);
    return verhuisd;
  }

  /// Lege mappen onder (en met) [map] weghalen, diepste eerst. Alleen wat ECHT leeg is: een map
  /// verwijderen zonder `recursive` weigert zodra er nog iets in staat.
  Future<void> _ruimLegeMappen(Directory map) async {
    try {
      final mappen = <Directory>[];
      await for (final e in map.list(recursive: true, followLinks: false)) {
        if (e is Directory) mappen.add(e);
      }
      mappen.sort((a, b) => b.path.length.compareTo(a.path.length));
      for (final d in [...mappen, map]) {
        try {
          await d.delete();
        } catch (_) {/* niet leeg */}
      }
    } catch (_) {/* al weg */}
  }

  /// Wat er bij het afsluiten nog in de keuringsmap stond: alsnog keuren en opbergen.
  ///
  /// Een torrent die binnen was maar niet gekeurd — de app ging uit, of viel om midden in het
  /// opbergen — zou anders voor altijd onzichtbaar in `_keuring` blijven. Eerst gaat wat half is weg:
  /// een `.part` is een download die niet afkwam ([_download]), en een leeg bestand is een reservering
  /// zonder inhoud ([_legVast]). Geeft het aantal nagekeurde torrents.
  Future<int> hervatKeuring() async {
    final wortel = Directory('$_downloadsRoot${Platform.pathSeparator}$keuringMap');
    if (!await wortel.exists()) return 0;
    final mappen = <Directory>[];
    try {
      await for (final e in wortel.list(followLinks: false)) {
        if (e is Directory) mappen.add(e);
      }
    } catch (_) {
      return 0;
    }
    var n = 0;
    for (final m in mappen) {
      // Al bezig in deze sessie: dan is het geen restant, en keurt zijn eigen opdracht het.
      if (_opKeuring.containsKey(m.path)) continue;
      final half = <File>[];
      try {
        await for (final e in m.list(recursive: true, followLinks: false)) {
          if (e is! File) continue;
          if (e.path.toLowerCase().endsWith('.part') || await e.length() == 0) half.add(e);
        }
      } catch (_) {
        continue;
      }
      for (final f in half) {
        try {
          await f.delete();
        } catch (_) {/* in gebruik — dan laat de keuring hem als kapot liggen */}
      }
      final naam = m.path.split(Platform.pathSeparator).last;
      _log.line('keuring: "$naam" lag er nog van de vorige keer — nu alsnog gekeurd');
      _opKeuring[m.path] = 1;
      try {
        await _bergTorrentOp(m, naam,
            zichtbaar: Directory('$_downloadsRoot${Platform.pathSeparator}$naam'));
      } finally {
        _opKeuring.remove(m.path);
      }
      n++;
    }
    return n;
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
      await vergeetWatErAlIs();
      final nu = DateTime.now().millisecondsSinceEpoch;
      final rij = _wants.due(nu);
      jacht.value = jacht.value.met(opDeLijst: _wants.count);
      if (rij.isEmpty) return 0;
      _log.line('wensen: ${rij.length} van ${_wants.count} aan de beurt'
          '${rij.length > _maxWensenPerVeeg ? " — deze beurt de eerste $_maxWensenPerVeeg" : ""}');
      jacht.value = jacht.value.met(
          dezeBeurt: rij.length < _maxWensenPerVeeg ? rij.length : _maxWensenPerVeeg,
          gedaan: 0,
          poging: 0,
          maxPoging: 0);
      // Twee remmen, en ze zijn nodig zodra de lijst groot is. Een veegbeurt die niet terugkomt
      // blokkeert via `_sweeping` ook alle volgende, dus een verse wens uit een mislukte download
      // zou dagen kunnen wachten. `due()` sorteert oudste eerst, dus wie blijft staan is de
      // volgende keer als eerste aan de beurt.
      final veegEinde = DateTime.now().add(_veegBudget);
      var gehaald = 0;
      for (final w in rij.take(_maxWensenPerVeeg)) {
        if (DateTime.now().isAfter(veegEinde)) {
          _log.line('wensen: beurt vol — de rest komt over twintig minuten');
          _jachtRegel('Beurt vol — de rest komt de volgende ronde.');
          break;
        }
        if (await _chaseWant(w)) gehaald++;
        jacht.value = jacht.value
            .met(gedaan: jacht.value.gedaan + 1, opDeLijst: _wants.count, poging: 0, maxPoging: 0);
      }
      await _wants.save();
      return gehaald;
    } finally {
      _sweeping = false;
      // Ook als er onderweg iets omviel: een balk die blijft staan liegt harder dan geen balk.
      jacht.value = jacht.value.klaar(opDeLijst: _wants.count);
    }
  }

  /// Eén wens: zoek opnieuw, sla geweigerde peers over, en probeer de beste lossless.
  Future<bool> _chaseWant(LosslessWant w) async {
    // Een wens om één bepaald bestand zoekt niet en vervangt niets: hij klopt opnieuw aan.
    if (w.exact != null) return _chaseExact(w);
    List<SoulseekFile> hits;
    try {
      // Met "24bit" erbij (kHiresZoekwoorden): een wens zoekt een betere kopie.
      hits = await soulseek.search(w.query, achtergrond: true, extra: kHiresZoekwoorden);
    } catch (_) {
      return false; // geen net; de wens blijft staan en het ritme schuift niet op
    }
    final rustend = _rustendePeers();
    final lossless = kandidatenVoorWens(w, hits, rustendePeers: rustend);
    jacht.value = jacht.value.met(
      bezigMet: '${w.artist} — ${w.title}',
      poging: 0,
      maxPoging: lossless.length < _maxWensPogingen ? lossless.length : _maxWensPogingen,
      regel: lossless.isEmpty
          ? 'Niets bruikbaars gevonden bij ${hits.length} treffers.'
          : '${lossless.length} bruikbare lossless kandidaten gevonden.',
    );
    _log.line('wens "${w.artist} — ${w.title}": ${hits.length} treffers, '
        '${lossless.length} bruikbaar lossless (poging ${w.tries + 1}'
        '${w.refused.isEmpty ? "" : ", ${w.refused.length} peers overgeslagen"}'
        '${rustend.isEmpty ? "" : ", ${rustend.length} peers rusten uit"}'
        '${w.nep.isEmpty ? "" : ", ${w.nep.length} betrapte uploads overgeslagen"})');
    final geweigerd = Map<String, String>.of(w.refused);
    final betrapt = List<VasteBron>.of(w.nep);
    if (lossless.isEmpty) return _rondWensAf(w, goed: false, geweigerd: geweigerd, betrapt: betrapt);

    final job = DownloadJob(w.title);
    var goed = false;
    // Een klok in plaats van een teller, naar het model van [_chaseUpgrade]. Hiervoor stond er
    // `take(4)` met dertig minuten wachten per peer: tot TWEE UUR voor één wens, terwijl de veegbeurt
    // serieel is. Nu mogen er meer kandidaten geprobeerd worden, elk veel goedkoper — en een peer die
    // je acht minuten in de wachtrij laat staan levert over dertig ook niets.
    final einde = DateTime.now().add(_wensBudget);
    var geprobeerd = 0;
    try {
      await soulseek.withSession((session) async {
        for (final f in lossless) {
          if (geprobeerd >= _maxWensPogingen) break;
          final over = einde.difference(DateTime.now());
          if (over <= const Duration(seconds: 30)) {
            _log.line('   budget op na $geprobeerd poging(en) — de wens blijft staan');
            break;
          }
          geprobeerd++;
          jacht.value = jacht.value
              .met(poging: geprobeerd, regel: 'Probeert ${f.username} — ${_mb(f.size)}.');
          final t0 = DateTime.now();
          SlskResult res;
          try {
            // Ruim wachten mag hier: deze jacht houdt geen downloadslot bezig en er zit niemand op te
            // wachten. Een plaats in een wachtrij is waardevol -- weggooien is wat de app hiervoor deed.
            res = await _rawTransfer(session, f, job, () {},
                waitInQueue: true,
                maxWait: over < _maxWachtPerPeer ? over : _maxWachtPerPeer,
                maxPlaats: _maxWachtrijPlaats);
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
            // En ook over de wensen HEEN, want dit is niet iets van dit nummer. Zie [_peerRustDuur]:
            // `Inhabitantz+` kostte 24 minuten aan drie verschillende wensen met hetzelfde antwoord.
            _peerRust[f.username] = DateTime.now();
            continue;
          }
          // Een afgekapte poging is er ook een: hij stond te ver in de rij of het budget was op.
          // Diezelfde peer heeft bij de volgende wens dezelfde rij.
          if (res is SlskCancelled || res is SlskQueued) _peerRust[f.username] = DateTime.now();
          if (res is! SlskDone) continue;

          // METEN VÓÓR HET OPBERGEN, en dit ontbrak juist op deze weg.
          //
          // De twee andere landingswegen doen het al, met de reden erbij: een opgeschaalde of uit
          // mp3 omgezette kopie is GROTER dan het origineel. Hier was het gevolg nog scherper.
          // `firstIsBetter` kent de regel "wat bewezen nep is verliest", en die staat bóven de
          // grootte — maar een ONGEMETEN binnenkomer geldt niet als nep. Dus won elke verse kopie
          // van het bewezen neppe bestand in de bibliotheek, wat het ook was: de echte kopie ging
          // naar `_dubbel` om plaats te maken voor de volgende vervalsing, de wens verviel, en
          // `hasLossless` telde de nieuwe mee. Stilletjes "opgelost", nog steeds nep.
          final staged = File(res.path);
          final uitslag = await _keurVoorWens(w, staged, f.username, bronpad: f.filename);
          if (uitslag == _Wenskeuring.afgewezen) {
            betrapt.add(VasteBron(
                username: f.username,
                filename: f.filename,
                size: f.size,
                durationSec: f.durationSec));
          }
          if (uitslag != _Wenskeuring.opgeborgen) continue;
          goed = true;
          return;
        }
      });
    } catch (_) {/* niets verloren: je houdt de kopie die je had */}
    return _rondWensAf(w, goed: goed, geweigerd: geweigerd, betrapt: betrapt);
  }

  /// Het einde van een wensronde: lukte Soulseek niet, dan TIDAL als reserve, en dan van de lijst of
  /// opnieuw plannen.
  ///
  /// **TIDAL pas na drie rondes zonder iets** ([wensMagNaarTidal]). Saber, 22-10-2026: *"Tidal is wel
  /// enkel als back-up e, soulseek blijft prio."* Op Soulseek staat vaak een 24-bitkopie. Een nummer dat
  /// op Soulseek niet in FLAC staat, kreeg zo nooit een FLAC, ook als je TIDAL hebt. Sinds 22-10-2026 met
  /// tidaler in plaats van tiddl: die krijgt van TIDAL ook 24 bit, waar TIDAL het heeft (zie tidaler.dart).
  Future<bool> _rondWensAf(LosslessWant w,
      {required bool goed,
      required Map<String, String> geweigerd,
      required List<VasteBron> betrapt}) async {
    final tidalNee = List<String>.of(w.tidalNee);
    var via = '';
    if (!goed && wensMagNaarTidal(w, tidalErIs: Tidaler.beschikbaar)) {
      goed = await _wensViaTidal(w, tidalNee);
      if (goed) via = ' via TIDAL';
    }
    if (goed) {
      _wants.forget(w.key);
      _log.line('wens "${w.artist} — ${w.title}": FLAC binnen$via na ${w.tries + 1} '
          'poging${w.tries == 0 ? "" : "en"} — van de lijst');
      jacht.value = jacht.value.met(
          binnen: jacht.value.binnen + 1,
          opDeLijst: _wants.count,
          regel: 'Echte kopie binnen$via voor ${w.artist} — ${w.title}.');
      try {
        await onLibraryChanged();
      } catch (_) {}
      return true;
    }
    // `tries` gaat ook omhoog als er alleen vervalsingen langskwamen. Zonder dat zou de veegbeurt
    // elke twintig minuten dezelfde ronde overdoen op hetzelfde nummer.
    _wants.update(w.met(
        tries: w.tries + 1,
        lastTryMs: DateTime.now().millisecondsSinceEpoch,
        refused: geweigerd,
        nep: betrapt,
        tidalNee: tidalNee));
    _log.line('wens "${w.artist} — ${w.title}": nog niet — volgende poging over '
        '${_kort(wachtVoor(w.tries + 1))}');
    _jachtRegel('${w.artist} — ${w.title}: nog niets echts gevonden, opnieuw over '
        '${duurTekst(wachtVoor(w.tries + 1))}.');
    return false;
  }

  /// TIDAL voor één wens: zoeken, het juiste nummer kiezen ([kiesTidalTreffers]), halen in een eigen
  /// keuringsmap, en dan dezelfde keuring als een kandidaat van Soulseek ([_keurVoorWens]). Wat de
  /// keuring afwijst, komt in [nee] en wordt niet opnieuw gehaald.
  Future<bool> _wensViaTidal(LosslessWant w, List<String> nee) async {
    final artiest = (w.performer?.isNotEmpty ?? false) ? w.performer! : w.artist;
    final treffers = await zoekOpTidal(w.query);
    if (treffers == null) {
      _log.line('   TIDAL: zoeken lukte niet');
      return false;
    }
    final ids = kiesTidalTreffers(treffers, artiest: artiest, titel: w.title, nee: nee);
    _log.line('   TIDAL: ${treffers.length} treffers, ${ids.length} met deze titel en artiest'
        '${nee.isEmpty ? "" : " (${nee.length} eerder afgewezen)"}');
    for (final id in ids.take(_maxTidalPogingen)) {
      jacht.value = jacht.value.met(regel: 'Probeert TIDAL (nummer $id).');
      final map = keuringsmapVoor('tidal-wens-$id');
      var laten = false;
      try {
        final t0 = DateTime.now();
        final r = await haalVanTidal(doel: 'track/$id', map: map.path, zoekMap: map.path);
        if (r.fout != null) {
          _log.line('   TIDAL $id: mislukt: ${r.fout!.split('\n').last}');
          continue;
        }
        final binnen = <File>[];
        await for (final e in map.list(recursive: true, followLinks: false)) {
          if (e is File && isVerliesvrij(soortVan(e.path))) binnen.add(e);
        }
        if (binnen.length != 1) {
          _log.line('   TIDAL $id: ${binnen.length} verliesvrije bestanden binnen — overgeslagen');
          continue;
        }
        _log.line('   TIDAL $id: GELEVERD${r.kwaliteit == null ? "" : " (${r.kwaliteit})"} '
            'na ${_kort(DateTime.now().difference(t0))}');
        final uitslag = await _keurVoorWens(w, binnen.single, 'TIDAL $id');
        if (uitslag == _Wenskeuring.afgewezen) nee.add(id);
        if (uitslag != _Wenskeuring.opgeborgen) continue;
        // Kon hij niet opgeborgen worden, dan blijft de map staan: `hervatKeuring` keurt hem bij de
        // volgende start alsnog, en de scan kijkt niet in de keuringsmap.
        laten = binnen.single.existsSync();
        return true;
      } catch (e) {
        _log.line('   TIDAL $id: $e');
      } finally {
        if (!laten) {
          try {
            if (map.existsSync()) await map.delete(recursive: true);
          } catch (_) {/* in gebruik; dan keurt de volgende start het restant */}
        }
        _geefKeuringsmapVrij(map);
      }
    }
    return false;
  }

  /// Een betere kopie van TIDAL voor [t], dat al in je bibliotheek staat — voor de TIDAL-ronde over de hele
  /// bibliotheek (tidal_beter.dart; Saber, 24-10-2026: "als er een beter versie kwaliteit te vinden is op tidal, moet
  /// de app deze gebruiken"). Halen in een eigen keuringsmap, en dan de keuring van een wens ([_keurVoorWens]): echt,
  /// even lang, dezelfde opname, bewezen beter. Je eigen tags gaan mee ([gezag]), dus het album van TIDAL (vaak een
  /// verzamelaar) komt er niet in; wat verliest, gaat naar `_dubbel`.
  Future<TidalBeterUitslag> haalBeterVanTidal(Track t, TidalTrack kandidaat, {required TrackTags gezag}) async {
    final naam = '${t.artist} — ${t.title}';
    final id = kandidaat.id;
    final map = keuringsmapVoor('tidal-beter-$id');
    var laten = false;
    try {
      final t0 = DateTime.now();
      final r = await haalVanTidal(doel: 'track/$id', map: map.path, zoekMap: map.path);
      if (r.fout != null) {
        _log.line('   TIDAL $id: mislukt: ${r.fout!.split('\n').last}');
        return TidalBeterUitslag.mislukt;
      }
      final binnen = <File>[];
      await for (final e in map.list(recursive: true, followLinks: false)) {
        if (e is File && isVerliesvrij(soortVan(e.path))) binnen.add(e);
      }
      if (binnen.length != 1) {
        _log.line('   TIDAL $id: ${binnen.length} verliesvrije bestanden binnen — overgeslagen');
        return TidalBeterUitslag.mislukt;
      }
      _log.line('   TIDAL $id: GELEVERD${r.kwaliteit == null ? "" : " (${r.kwaliteit})"} '
          'na ${_kort(DateTime.now().difference(t0))}');
      final w = LosslessWant(artist: t.artist, title: t.title, album: t.album, authority: gezag);
      final uitslag = await _keurVoorWens(w, binnen.single, 'TIDAL $id', inJacht: false);
      switch (uitslag) {
        case _Wenskeuring.opgeborgen:
          // Kon hij niet opgeborgen worden, dan blijft de map staan: `hervatKeuring` keurt hem bij de volgende start.
          laten = binnen.single.existsSync();
          _log.line('"$naam": vervangen door de kopie van TIDAL${r.kwaliteit == null ? "" : " (${r.kwaliteit})"}');
          try {
            await onLibraryChanged();
          } catch (_) {}
          return TidalBeterUitslag.vervangen;
        case _Wenskeuring.afgewezen:
        case _Wenskeuring.alAanwezig:
        case _Wenskeuring.alsVersie:
          return TidalBeterUitslag.afgewezen;
      }
    } catch (e) {
      _log.line('   TIDAL $id: $e');
      return TidalBeterUitslag.mislukt;
    } finally {
      if (!laten) {
        try {
          if (map.existsSync()) await map.delete(recursive: true);
        } catch (_) {/* in gebruik; dan keurt de volgende start het restant */}
      }
      _geefKeuringsmapVrij(map);
    }
  }

  /// Platen waarvoor de torrentjacht nu loopt ([_zoekHiresInTorrents]): twee keer "Zoek hi-res" is één jacht.
  final _torrentJacht = <String>{};

  /// Hi-res uit torrents voor de nummers van één plaat, bij "Zoek hi-res" (Saber, 25-10-2026: "ook via torrents moet
  /// worden gezocht, wel losse tracks"). Zie torrent_hires.dart voor welke torrents: wat TorBox al heeft, de plaat
  /// zelf, verliesvrij (hi-res als er een nummer al cd-kwaliteit is), losse nummers, digitaal vóór vinyl. Per nummer
  /// één bestand uit de torrent, in een eigen keuringsmap, en dan de keuring van een wens ([_keurVoorWens]); wat
  /// verliest gaat naar `_dubbel`. Vervangen pas als het nummer niet meer speelt. Geeft terug hoeveel nummers er
  /// vervangen werden, en voor de torrent-ronde (torrent_beter.dart) of het aan TorBox lag.
  Future<TorrentJacht> _zoekHiresInTorrents(List<Track> nummers, String album, TrackTags Function(Track)? gezag) async {
    if (!online.torboxReady || nummers.isEmpty) return (vervangen: 0, bruikbaar: 0, storing: true, alBezig: false);
    final artiest = nummers.first.artist;
    final sleutel = '${normKey(artiest)}|${normKey(album)}';
    if (!_torrentJacht.add(sleutel)) return (vervangen: 0, bruikbaar: 0, storing: false, alBezig: true);
    final plaat = '"$artiest — $album"';
    var vervangen = 0, bruikbaar = 0;
    // Torrents die TorBox al had maar niet opende: gaan ze allemaal niet open, dan hapert TorBox zelf.
    var klaarDicht = 0, klaarOpen = 0;
    try {
      bool verdacht(Track t) {
        final o = gemeten(t.path);
        return o != null && (o.band == Bandbreedte.vermoedelijk || o.band == Bandbreedte.afgekapt);
      }

      final eis = <Track, TidalMinstens>{
        for (final t in nummers)
          if (tidalMinstens(t, verdacht: verdacht(t)) case final m when m != TidalMinstens.geenWinst) t: m,
      };
      if (eis.isEmpty) {
        _log.line('$plaat: torrents — niets te winnen, alles is al hi-res');
        return (vervangen: 0, bruikbaar: 0, storing: false, alBezig: false);
      }
      final hiresNodig = eis.values.contains(TidalMinstens.hires);
      final treffers = await online.search(albumZoekvraag(artiest, album, jaar: nummers.first.year));
      final kandidaten = torrentsVoorHires(treffers,
          artiest: artiest, album: album, jaar: nummers.first.year, hiresNodig: hiresNodig);
      _log.line('$plaat: torrents — ${treffers.length} treffers, ${kandidaten.length} bruikbaar '
          '(${kandidaten.where((r) => r.cached).length} al bij TorBox; ${hiresNodig ? "hi-res" : "verliesvrij"}, de plaat '
          'zelf, geen image)');
      final open = {...eis.keys};
      var klaarGeprobeerd = 0, nietKlaarGeprobeerd = 0;
      for (final r in kandidaten) {
        if (open.isEmpty) break;
        if (r.cached ? klaarGeprobeerd >= kTorrentHiresHoogstens : nietKlaarGeprobeerd >= kTorrentHiresNietKlaar) continue;
        r.cached ? klaarGeprobeerd++ : nietKlaarGeprobeerd++;
        bruikbaar++;
        final hires = hiresVolgensNaam(r.name);
        final TbTorrent item;
        final t0 = DateTime.now();
        try {
          final (id, hash) = await online._addOrFind(r);
          // Wat TorBox nog moet halen: geduldig, tot een kwartier, en weg na anderhalve minuut zonder voortgang.
          item = await online._pollReady(id, hash, patient: !r.cached);
        } catch (e) {
          _log.line('   torrent "${r.name}": ${r.cached ? "niet te openen" : "niet binnen"} bij TorBox — $e');
          if (r.cached) klaarDicht++;
          continue;
        }
        if (r.cached) klaarOpen++;
        if (!r.cached) {
          _log.line('   torrent "${r.name}": bij TorBox binnen na ${_kort(DateTime.now().difference(t0))} '
              '(${r.seeders} seeders)');
        }
        final indeling = indelingUitBestanden(item.files.map((f) => f.name));
        if (indeling != TorrentIndeling.losseNummers) {
          _log.line('   torrent "${r.name}": ${indeling == TorrentIndeling.image ? "image met cue" : "geen muziek"} '
              '— overgeslagen');
          continue;
        }
        final muziek = [for (final f in item.files) if (f.isAudio && isVerliesvrij(soortVan(f.name))) f];
        _log.line('   torrent "${r.name}": ${muziek.length} nummers${isVinylRip(r.name) ? ", vinyl" : ""}');
        for (final t in [...open]) {
          if (eis[t] == TidalMinstens.hires && !hires) continue;
          // Soulseek of TIDAL kan het intussen al vervangen hebben: die jachten lopen tegelijk. Daft Punk, Discovery
          // (25-10-2026): negen nummers waren 24 bit vóór TorBox de torrent klaar had.
          if (intussenVervangen(t, eis[t]!)) {
            open.remove(t);
            _log.line('   torrent "${r.name}": "${t.artist} — ${t.title}" is intussen al beter — niet gehaald');
            continue;
          }
          final f = muziek
              .where((f) => fileOffersTitle(t.title, t.duration?.inSeconds, artiest, f.name, null, album: album))
              .firstOrNull;
          if (f == null) continue;
          if (await _haalUitTorrentEnKeur(t, r, item, f, gezag)) {
            open.remove(t);
            vervangen++;
          }
        }
      }
      _log.line('$plaat: torrents — $vervangen van ${eis.length} nummers vervangen');
      if (vervangen > 0) {
        try {
          await onLibraryChanged();
        } catch (_) {}
      }
      return (vervangen: vervangen, bruikbaar: bruikbaar, storing: klaarDicht > 0 && klaarOpen == 0, alBezig: false);
    } catch (e) {
      _log.line('$plaat: torrents — $e');
      return (vervangen: vervangen, bruikbaar: bruikbaar, storing: true, alBezig: false);
    } finally {
      _torrentJacht.remove(sleutel);
    }
  }

  /// De torrentjacht voor de ronde over de hele bibliotheek (torrent_beter.dart): [nummers] zijn de nummers van één
  /// plaat die beter kunnen. Dezelfde jacht als bij "Zoek hi-res", met het gezag van de bibliotheek ([gezagVoor]).
  Future<TorrentJacht> zoekBeterInTorrents(List<Track> nummers, String album) =>
      _zoekHiresInTorrents(nummers, album, gezagVoor);

  /// Is [t] intussen vervangen: staat het bestand er niet meer (een mp3 die nu een FLAC is), of is een FLAC die
  /// hi-res moest worden het nu wel en bij de start nog niet ([eis] = [TidalMinstens.hires])? Het bestand zelf is de
  /// stand van nu, [t] die van vóór de jacht. "Bij de start nog niet": Seal, "Stand by Me", 16 bit op 192 kHz (25-10-2026)
  /// telde anders als al hi-res, en dan kwam de echte 24 bit uit de torrent er nooit aan te pas.
  @visibleForTesting
  static bool intussenVervangen(Track t, TidalMinstens eis) {
    final f = File(t.path);
    if (!f.existsSync()) return true;
    if (eis != TidalMinstens.hires) return false;
    final k = readFlacTags(f);
    bool hires(int bits, int hz) => bits > 16 || hz > 48000;
    return k != null && hires(k.bitsPerSample, k.sampleRate) && !hires(t.bitsPerSample, t.sampleRate);
  }

  /// Eén nummer uit een torrent bij TorBox halen en keuren. Waar als het in de bibliotheek staat.
  Future<bool> _haalUitTorrentEnKeur(
      Track t, SearchResult r, TbTorrent item, TbFile f, TrackTags Function(Track)? gezag) async {
    final naam = '${t.artist} — ${t.title}';
    final map = keuringsmapVoor('torrent-hires-${item.id}-${f.id}');
    final bron = 'torrent "${r.name}"';
    var laten = false;
    try {
      final doel = await _haalTorrentBestand(item, f, map, bron, naam);
      if (!await _wachtTotNietMeerSpeelt(t.path)) {
        _log.line('   $bron: "$naam" speelt nog — niet vervangen');
        return false;
      }
      final w = LosslessWant(
          artist: t.artist,
          title: t.title,
          album: t.album,
          authority: gezag?.call(t) ??
              TrackTags(
                  title: t.title,
                  artist: t.artist,
                  album: t.album,
                  trackNo: t.trackNo,
                  year: t.year,
                  seconds: t.duration?.inSeconds));
      final uitslag = await _keurVoorWens(w, doel, bron, inJacht: false, bronpad: '${item.name}/${f.label}');
      if (uitslag != _Wenskeuring.opgeborgen) return false;
      laten = doel.existsSync();
      _log.line('"$naam": vervangen door de kopie uit $bron');
      return true;
    } catch (e) {
      _log.line('   $bron: "$naam" mislukt — $e');
      return false;
    } finally {
      if (!laten) {
        try {
          if (map.existsSync()) await map.delete(recursive: true);
        } catch (_) {/* in gebruik; dan keurt de volgende start het restant */}
      }
      _geefKeuringsmapVrij(map);
    }
  }

  /// Eén bestand [f] uit de torrent [item] bij TorBox naar [map] halen. Gooit bij een fout of een onvolledig bestand;
  /// het opruimen van [map] is aan wie hem vroeg.
  Future<File> _haalTorrentBestand(TbTorrent item, TbFile f, Directory map, String bron, String naam) async {
    final t0 = DateTime.now();
    String? url;
    for (var poging = 1; url == null; poging++) {
      try {
        url = await online.resolveTrackUrl(item.id, f.id);
      } catch (_) {
        // Vlak na het toevoegen geeft TorBox soms nog geen adres. Seal, "Stand by Me" (25-10-2026): "Lege download-URL",
        // en een minuut later kwam hetzelfde bestand gewoon binnen.
        if (poging >= kTorrentAdresPogingen) rethrow;
        await Future<void>.delayed(Duration(seconds: 5 * poging));
      }
    }
    final client = http.Client();
    try {
      final resp = await client.send(http.Request('GET', Uri.parse(url))).timeout(_torrentStilte);
      if (resp.statusCode < 200 || resp.statusCode >= 300) throw 'HTTP ${resp.statusCode}';
      await map.create(recursive: true);
      final doel = File('${map.path}${Platform.pathSeparator}${baseName(f.label)}');
      final deel = File('${doel.path}.part');
      final sink = deel.openWrite();
      var binnen = 0;
      try {
        await for (final stuk in resp.stream.timeout(_torrentStilte)) {
          sink.add(stuk);
          binnen += stuk.length;
        }
      } finally {
        await sink.close();
      }
      final verwacht = resp.contentLength ?? f.size;
      if (verwacht > 0 && binnen < verwacht) throw 'incompleet: $binnen van $verwacht bytes';
      await deel.rename(doel.path);
      _log.line('   $bron: "${baseName(f.label)}" GELEVERD voor "$naam" na ${_kort(DateTime.now().difference(t0))}, '
          '${(binnen / 1048576).toStringAsFixed(1)} MB');
      return doel;
    } finally {
      client.close();
    }
  }

  /// Wat er met een binnengekomen kandidaat voor een wens gebeurt, van Soulseek of van TIDAL ([bron]
  /// staat in het logboek). Alles wat niet [_Wenskeuring.opgeborgen] is, is al weggegooid.
  ///
  /// [inJacht]: meldt zich in de strook van de vervangjacht ([jacht]). De TIDAL-ronde over de bibliotheek
  /// ([haalBeterVanTidal]) doet dat niet: die is geen wens, en twintig afwijzingen per uur daar zeggen niets.
  ///
  /// [bronpad]: waar hij vandaan kwam als pad (bij de uploader, in de torrent) — wat hem tot vinyl maakt ([_noteerSoort]).
  Future<_Wenskeuring> _keurVoorWens(LosslessWant w, File staged, String bron,
      {bool inJacht = true, String? bronpad}) async {
    final oordeel = await _meetEchtheid(staged);
    if (!magBlijven(oordeel)) {
      _log.line('   $bron: betrapt bij binnenkomst '
          '(${waarom(oordeel!)}) — weggegooid, volgende kandidaat');
      if (inJacht) jacht.value = jacht.value.met(
          weggegooid: jacht.value.weggegooid + 1,
          regel: 'Vervalsing betrapt bij $bron (${waarom(oordeel)}) — weggegooid.');
      await _discardStaged(staged.path);
      return _Wenskeuring.afgewezen;
    }

    // En het moet DEZELFDE OPNAME zijn. De lengte van de peer is vóór het binnenhalen al
    // gewogen (zie [zelfdeLengte]), maar lang niet iedereen meldt er een; hier staat het
    // bestand er, dus hier valt het écht te meten. Zonder deze tweede laag landt een
    // radio-edit als `(2)` naast het origineel en blijft de vervalsing staan.
    // FLAC uit zijn kop; elk ander formaat uit de decodeerproef die er net overheen ging.
    final lengte = _duurVan(staged.path) ?? gedecodeerdeLengte(staged.path)?.round();
    // Een vinylrip duurt vaak een paar seconden langer (de naald erop, de uitloop): die mag tot [kVinylLengteSpeling]
    // afwijken — maar alleen als VERSIE, en dan beslist de vingerafdruk of het dezelfde opname is (versies.dart).
    final vinyl = isVinylRip(bronpad ?? bron);
    final alleenAlsVersie = !zelfdeLengte(w.authority?.seconds, lengte) &&
        vinyl &&
        (w.authority!.seconds! - lengte!).abs() <= kVinylLengteSpeling;
    if (!zelfdeLengte(w.authority?.seconds, lengte) && !alleenAlsVersie) {
      _log.line('   $bron: andere uitgave (${lengte}s tegen '
          '${w.authority?.seconds}s) — weggegooid, volgende kandidaat');
      if (inJacht) jacht.value = jacht.value.met(
          weggegooid: jacht.value.weggegooid + 1,
          regel: 'Andere uitgave bij $bron — weggegooid.');
      await _discardStaged(staged.path);
      return _Wenskeuring.afgewezen;
    }

    // En schoon is niet genoeg: hij moet ook minstens evenveel ECHTE muziek dragen als wat er
    // al ligt — bij de proefjacht kwam er een eerlijke 16/48 binnen voor
    // een opgeschaalde 24/96 die in werkelijkheid 24 bits op 44,1 draagt, en dat is minder.
    // Sinds 29-09-2026 dezelfde regel als elke andere weg: alleen wat BEWEZEN beter is, vervangt
    // ([firstIsBetter]). Hier stond een eigen toets, [draagtGenoeg], die "minstens evenveel"
    // vroeg — en daarmee ruilde de wens Sabers opgeschaalde 24/96 van Is It Scary in voor een
    // eerlijke 24/48 die niets beter was, en die van Stranger In Moscow voor een 24/44,1. Zijn
    // woorden: "als er een slechtere binnenkomt dan wat ik heb moet die weg."
    final bestaand = await _bereidVergelijkingVoor(
        staged,
        w.authority ?? TrackTags(title: w.title, artist: w.artist, album: w.album, trackNo: 0));
    var score = bestaand == null ? null : await _opnameScore(staged.path, bestaand);
    // Een vinylrip begint vaak verder van de eerste noot dan de cd: dan nog eens, met meer ruimte om te schuiven.
    if (vinyl && bestaand != null && score != null && score < maybeSameRecordingScore) {
      score = await _opnameScoreRuim(staged.path, bestaand) ?? score;
    }
    final opname = opnameOordeel(score);
    final andereOpname = bestaand != null && (opname == Opnameoordeel.andere || opname == Opnameoordeel.twijfel);
    final nietBeter = bestaand != null && !firstIsBetter(staged, File(bestaand));
    // Een andere versie dan wat je hebt (versies.dart, Saber 26-10-2026: "Behoud ik alles e, cd, studio, en vinyl"):
    // bewaren in plaats van weggooien of vervangen. Alleen als de vingerafdruk zegt dat het dezelfde opname is.
    var plan = bestaand != null && (opname == Opnameoordeel.zelfde || opname == Opnameoordeel.twijfel)
        ? versieplanVoor(staged, bestaand, bronpad ?? bron)
        : null;
    // Het nummer opzij zetten mag alleen voor een kopie die ook bewezen beter is, en die binnen je eigen soortkeuze valt;
    // anders wordt hij gewoon een versie en blijft wat je had.
    if (plan != null &&
        plan.besluit == Versiebesluit.ankerOpzij &&
        (nietBeter || !magVanzelf(bestaand!, plan.soort))) {
      plan = plan.als(Versiebesluit.nieuweVersie);
    }
    // Koos je zelf een soort voor dit nummer (kopiesoort.dart): alleen binnen die soort vervangen — ook TIDAL en torrents.
    // Een versie vervangt niets, en mag dus wel.
    if (bestaand != null &&
        !(plan?.isVersie ?? false) &&
        !magVanzelf(bestaand, _soortVanBinnen(staged, bronpad ?? bron))) {
      _log.line('   $bron: je koos ${gekozenSoort(bestaand)?.voluit} voor dit nummer, en dit is een andere soort — weggegooid');
      await _discardStaged(staged.path);
      return _Wenskeuring.afgewezen;
    }
    // Klinkt bewezen beter, of is een andere versie, maar de vingerafdruk twijfelt: niet weggooien, aanbieden (twijfel.dart).
    if (bestaand != null &&
        opname == Opnameoordeel.twijfel &&
        (!nietBeter || (plan?.isVersie ?? false)) &&
        await bewaarAlsTwijfel(staged, bestaand, score!, bron, w.authority)) {
      if (inJacht) jacht.value = jacht.value.met(regel: 'Bij $bron: twijfel — bewaard tot je kiest.');
      return _Wenskeuring.afgewezen;
    }
    if (plan != null && plan.isVersie && opname == Opnameoordeel.zelfde) {
      final uit = await _bergOpAlsVersie(staged, plan, w.authority, bron, inJacht: inJacht);
      if (uit != null) return uit;
    }
    if (alleenAlsVersie) {
      _log.line('   $bron: andere uitgave (${lengte}s tegen ${w.authority?.seconds}s, en geen andere versie dan wat je hebt) — '
          'weggegooid, volgende kandidaat');
      await _discardStaged(staged.path);
      return _Wenskeuring.afgewezen;
    }
    if (andereOpname || nietBeter) {
      final waaromNiet = andereOpname
          ? 'een andere opname dan wat je hebt'
          : 'niet bewezen beter: ${kwaliteitZin(kwaliteitVan(staged))} tegen '
              '${kwaliteitZin(kwaliteitVan(File(bestaand)))}';
      _log.line('   $bron: $waaromNiet — weggegooid, volgende kandidaat');
      if (inJacht) jacht.value = jacht.value.met(
          weggegooid: jacht.value.weggegooid + 1,
          regel: 'Bij $bron: $waaromNiet — weggegooid.');
      await _discardStaged(staged.path);
      return _Wenskeuring.afgewezen;
    }

    try {
      // Het gezag van de wens, niet dat van dit wegwerp-job: een peer stuurt geregeld een
      // bestand zonder één tag, en dan landt het als "Onbekende artiest" in Singles. Precies wat
      // de eerste echte vondst deed voordat dit erin stond.
      final uit = await placeFileDetailed(staged, _downloadsRoot,
          tags: w.authority ??
              TrackTags(title: w.title, artist: w.artist, album: w.album, trackNo: 0),
          staatAl: mapVanBestaande);
      // Verloor hij van wat er al lag, dan is er niets opgelost en blijft de wens staan. Dit
      // stond er niet: `goed` werd gezet ongeacht de uitkomst, dus een kopie die verloor liet
      // de wens tóch vervallen.
      if (uit.how == Placement.duplicate) return _Wenskeuring.alAanwezig;
      if (uit.how == Placement.moved) _noteerSoort(uit.path, bronpad ?? bron);
      if (bestaand != null) await _vergeetTwijfel(bestaand);
    } catch (_) {/* de scan vindt hem waar hij ook landde */}
    return _Wenskeuring.opgeborgen;
  }

  /// [staged] opbergen als versie van wat er ligt ([plan], versie_opbergen.dart), met het logboek en de strook erbij. Null:
  /// het lukte niet — dan gaat de keuring verder zoals zonder versies. Geeft voor de wens [_Wenskeuring.opgeborgen] als hij
  /// het nummer werd (een echte studiokopie voor je cd), en anders [_Wenskeuring.alsVersie]: de wens zoekt verder.
  Future<_Wenskeuring?> _bergOpAlsVersie(File staged, Versieplan plan, TrackTags? gezag, String bron,
      {bool inJacht = true}) async {
    final naam = gezag == null ? baseName(plan.anker) : '${gezag.artist} — ${gezag.title}';
    final label = versieLabel(plan.soort!, plan.persing, bits: readFlacTags(staged)?.bitsPerSample ?? 0,
        hz: readFlacTags(staged)?.sampleRate ?? 0);
    Versieuitslag? uit;
    try {
      uit = await bergOpAlsVersie(staged, plan, root: _downloadsRoot, tags: gezag);
      // Het nummer zat vast (een speler had het open): dan wordt de nieuwe een versie, en blijft wat je had.
      if (uit == null && plan.besluit == Versiebesluit.ankerOpzij && staged.existsSync()) {
        uit = await bergOpAlsVersie(staged, plan.als(Versiebesluit.nieuweVersie), root: _downloadsRoot, tags: gezag);
      }
    } catch (e) {
      _log.line('   $bron: "$naam" als versie bewaren lukte niet — $e');
      return null;
    }
    if (uit == null) return null;
    if (uit.verloor) {
      _log.line('   $bron: "$naam" is dezelfde versie als je ${plan.vervangt?.persing.isNotEmpty == true ? plan.vervangt!.persing : plan.soort!.naam}-versie, '
          'en niet bewezen beter — weggegooid');
      return _Wenskeuring.afgewezen;
    }
    if (uit.werdAnker) {
      _log.line('"$naam": $bron BEWEZEN BETER ($label) — nu het nummer; je vorige kopie bleef als versie '
          '(${plan.ankerSoort?.naam ?? '?'})');
      if (plan.anker != uit.pad) await _vergeetTwijfel(plan.anker);
    } else {
      _log.line('"$naam": $bron bewaard als versie — $label, in "${baseName(File(uit.pad).parent.path)}"');
    }
    if (inJacht) jacht.value = jacht.value.met(regel: uit.werdAnker ? 'Bij $bron: beter — je vorige kopie bleef als versie.' : 'Bij $bron: bewaard als versie ($label).');
    try {
      await onLibraryChanged();
    } catch (_) {}
    return uit.werdAnker ? _Wenskeuring.opgeborgen : _Wenskeuring.alsVersie;
  }

  /// Zoals [_opnameScore], maar met tot vijftien seconden schuiven in plaats van vier: een vinylrip begint vaak met de
  /// naald en een stukje uitloop, en dan valt het begin niet samen met de cd.
  Future<double?> _opnameScoreRuim(String a, String b) async {
    try {
      final fp = Fingerprinter();
      if (!fp.available) return null;
      final x = await fp.of(a), y = await fp.of(b);
      if (x == null || y == null || x.raw.isEmpty || y.raw.isEmpty) return null;
      return similarity(x.raw, y.raw, maxOffset: 120);
    } catch (_) {
      return null;
    }
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

  /// Per radionummer de uploaders die het deze radio al niet leverden, of iets anders leverden.
  ///
  /// Gezien op 26-09-2026: "Pat Krimson — Silence" mislukte drie keer, telkens bij hondo77 met
  /// "overdracht afgebroken" — want dezelfde zoekvraag zet dezelfde peer steeds weer bovenaan. Leeg
  /// bij elke nieuwe radio (zie [staakRadiohalen]).
  final Map<String, Set<String>> _radioNietBij = {};

  /// Nummers waarvoor de laatste haal géén enkel bestand vond dat door de zeef kwam.
  final Set<String> _radioZonderKandidaat = {};

  /// Vond de laatste haal van dit nummer niets wat dit nummer is? Dan levert meteen opnieuw zoeken
  /// hetzelfde op, en is het alleen een zoekopdracht meer — zuinig zijn met zoeken is wat een account bij
  /// Soulseek uit de problemen houdt. Gezien op 20-10-2026: Sabien Tiels en Timbaland, elk vier keer
  /// gezocht, vier keer "niets bruikbaars".
  bool vondGeenKandidaat(String artiest, String titel) =>
      _radioZonderKandidaat.contains(_radioSleutel(artiest, titel));

  static String _radioSleutel(String artiest, String titel) =>
      '${normKey(artiest)}|${normKey(titel)}';

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
    _radioNietBij.clear();
    if (n > 0) _log.line('radio gestopt: $n ${n == 1 ? "haal" : "halen"} afgebroken');
    return n;
  }

  Future<String?> haalVoorRadio({
    required String artiest,
    required String titel,
    int? seconden,
    int? jaar,
  }) =>
      haalEnLaatHoren(artiest: artiest, titel: titel, seconden: seconden, jaar: jaar);

  /// [haalVoorRadio], en met [vroeg] klinkt het al terwijl het binnenkomt (zie `groeistroom.dart`).
  ///
  /// Een eigen naam en geen extra parameter op [haalVoorRadio]: die wordt in de toetsen nagebootst, en
  /// een extra parameter zou al die nabootsingen breken voor iets wat ze nooit gebruiken.
  ///
  /// [zoekDaarnaBeter]: na het landen dezelfde jacht op beter als na een gewone download — voor ▶, niet
  /// voor de radio (die doet het pas bij een 👍).
  ///
  /// [losVanDeRadio]: ▶ — dit hoort niet bij een radio, en [staakRadiohalen] laat het staan. Gemeten op de
  /// gsm (20-10-2026, 3.9.529, Myles Smith — Stargazing): ▶ terwijl er een radio liep; het nummer begon
  /// te klinken, dat sloot de radio, en het sluiten brak precies deze haal af — 404, en niets te horen.
  /// Op de pc net zo.
  ///
  /// [album]: de uitgave waarop je het nummer zag — zie [gezagVoorHaal].
  Future<String?> haalEnLaatHoren({
    required String artiest,
    required String titel,
    int? seconden,
    int? jaar,
    Groei? vroeg,
    bool zoekDaarnaBeter = false,
    bool losVanDeRadio = false,
    String? album,
  }) async {
    if (!soulseek.available) return null;
    // Heb je dit al? Dan valt er niets te halen — en, net zo belangrijk, dan mag het straks ook niet
    // opgeruimd worden. De toets staat hier VOORAF, want achteraf is het onderscheid weg.
    //
    // En wat je al hebt, klinkt dan ook — als jouw nummer ([RadioAlGehad]). Eerst werd het een lege
    // plek, en na een pauze midden in een haal zelfs een bestand dat de radio nog binnenhaalde maar
    // in geen enkele notitie meer stond (derde beoordeling van 26-09-2026).
    final al = mapVanBestaande?.call(artiest, titel, seconds: seconden);
    if (al != null) {
      if (File(al).existsSync()) throw RadioAlGehad(al);
      return null;
    }

    // Vanaf hier is er iets te stoppen, dus vanaf hier staat het in de lijst — ook tijdens het
    // zoeken. Een zoekopdracht duurt seconden, maar het is wél het moment waarop de meeste haaltjes
    // zich bevinden als je de radio afsluit.
    final job = DownloadJob(titel); // wegwerp: bewust niet in `jobs`
    if (!losVanDeRadio) _radiohalen.add(job);
    try {
      final pad = await _haalVoorRadio(job, artiest, titel, seconden, jaar,
          vroeg: vroeg, zoekBeter: zoekDaarnaBeter, album: album);
      if (pad != null || job.cancelled) return pad;
      // Soulseek had geen enkele kopie van dit nummer (niet: alle uploaders faalden) — dan TIDAL als reserve.
      if (!_radioZonderKandidaat.contains(_radioSleutel(artiest, titel))) return null;
      return await _radioViaTidal(job, artiest, titel, seconden, jaar, album: album, waarom: 'niet op Soulseek');
    } on RadioLaterOpnieuw catch (e) {
      // Soulseek doet niet mee (geen aanmelding, de server zwijgt): dan TIDAL, en anders later opnieuw. Saber,
      // 22-10-2026, na een radio die om 19:37 stilviel toen Soulseek ons buitensloot: "oei radio stopt al".
      final pad = await _radioViaTidal(job, artiest, titel, seconden, jaar, album: album, waarom: e.waarom);
      if (pad != null) return pad;
      rethrow;
    } finally {
      _radiohalen.remove(job);
    }
  }

  /// Wanneer de radio (en ▶) TIDAL vroeg — voor [kTidalRadioPerUur].
  final List<DateTime> _tidalRadioTijden = [];

  /// TIDAL als reserve voor een radiohaal: zoeken met tidaler, het juiste nummer kiezen ([kiesTidalTreffers]),
  /// halen in een eigen keuringsmap, en dan dezelfde keuringen als een kopie van Soulseek in [_haalVoorRadio] — de
  /// tags moeten dit nummer zijn, de lengte moet kloppen, en wat je al had blijft van jou ([RadioAlGehad]).
  ///
  /// **Soulseek blijft eerst** (Saber, 22-10-2026: "Tidal is wel enkel als back-up e, soulseek blijft prio"): dit
  /// draait alleen als Soulseek niet meedoet of het nummer niet heeft. En hoogstens [kTidalRadioPerUur] per uur: bij
  /// een storing met vijftig nummers vooruit trok de radio anders in een paar minuten tientallen nummers van TIDAL,
  /// en precies dat patroon levert een geblokkeerd account op ("abuse_detected", gemeld bij tidal-dl-ng).
  Future<String?> _radioViaTidal(DownloadJob job, String artiest, String titel, int? seconden, int? jaar,
      {String? album, required String waarom}) async {
    if (job.cancelled || Tidaler.inToets || !Tidaler.beschikbaar || Tidaler.python == null) return null;
    final nu = DateTime.now();
    _tidalRadioTijden.removeWhere((t) => nu.difference(t) >= const Duration(hours: 1));
    final wacht =
        zoekWachttijd(_tidalRadioTijden, nu, max: kTidalRadioPerUur, venster: const Duration(hours: 1));
    if (wacht > Duration.zero) {
      _log.line('radio "$artiest — $titel": $waarom — TIDAL niet: al $kTidalRadioPerUur dit uur '
          '(weer over ${wacht.inMinutes} min)');
      return null;
    }
    final treffers = await zoekOpTidal('$artiest $titel');
    if (treffers == null) {
      _log.line('radio "$artiest — $titel": $waarom — TIDAL: zoeken lukte niet');
      return null;
    }
    final ids = kiesTidalTreffers(treffers, artiest: artiest, titel: titel);
    _log.line('radio "$artiest — $titel": $waarom — TIDAL: ${treffers.length} treffers, ${ids.length} met deze '
        'titel en artiest');
    // Ook hier het oorspronkelijke album, zoals via Soulseek ([_haalVoorRadio]), alvast terwijl TIDAL haalt. Zonder dit
    // kwam elk nummer via TIDAL zonder album binnen: Carnival van Natalie Merchant (23-10-2026).
    final metAlbum = album?.trim() ?? '';
    final alsSingle = metAlbum.isNotEmpty && albumIsDeSingle(metAlbum, titel);
    final origineelF = ids.isNotEmpty && (metAlbum.isEmpty || alsSingle)
        ? origineleUitgave?.call(artiest, titel, seconden).then<({String album, int? jaar})?>((o) => o,
            onError: (Object _) => null)
        : null;
    if (ids.isNotEmpty) {
      meldAlbum(artiest, titel, seconden,
          album: metAlbum.isEmpty || alsSingle || lijktVerzamelaar(metAlbum) ? '' : metAlbum, origineel: origineelF);
    }
    for (final id in ids.take(2)) {
      if (job.cancelled) return null;
      _tidalRadioTijden.add(DateTime.now());
      final map = keuringsmapVoor('tidal-radio-$id');
      try {
        final t0 = DateTime.now();
        final r = await haalVanTidal(doel: 'track/$id', map: map.path);
        if (r.fout != null) {
          _log.line('   TIDAL $id: mislukt: ${r.fout!.split('\n').last}');
          continue;
        }
        final binnen = <File>[];
        await for (final e in map.list(recursive: true, followLinks: false)) {
          if (e is File && isVerliesvrij(soortVan(e.path))) binnen.add(e);
        }
        if (binnen.length != 1) {
          _log.line('   TIDAL $id: ${binnen.length} verliesvrije bestanden binnen — overgeslagen');
          continue;
        }
        final bestand = binnen.single;
        final tags = readTags(bestand);
        if (radioTagsSprekenTegen(artiest, titel, tags)) {
          _log.line('   TIDAL $id: leverde een ander nummer (${tags?.artist} — ${tags?.title}) — overgeslagen');
          continue;
        }
        final echt = looptijdInSeconden(bestand);
        if (radioLengteSpreektTegen(seconden, echt)) {
          _log.line('   TIDAL $id: ${echt}s, gevraagd ${seconden}s — een andere versie, overgeslagen');
          continue;
        }
        if (job.cancelled) return null;
        // Opbergen zoals een radiokopie van Soulseek: zonder jaar, opzij wat verliest, nooit weg.
        final plaatsing = TrackTags(title: titel, artist: artiest, album: '', trackNo: 0, seconds: seconden);
        final alBekend = mapVanBestaande?.call(artiest, titel, seconds: seconden);
        await _bereidVergelijkingVoor(bestand, plaatsing);
        final uit = await placeFileDetailed(bestand, _downloadsRoot,
            tags: plaatsing, staatAl: mapVanBestaande, parkeerAltijd: true, parkeerBinnenkomend: false);
        if (alBekend != null || uit.how != Placement.moved || uit.verving) {
          _log.line('   TIDAL $id: geland op muziek die je al had — niet van de radio');
          if (uit.how != Placement.stuck && File(uit.path).existsSync()) throw RadioAlGehad(uit.path);
          return null;
        }
        _noteerSoort(uit.path, 'TIDAL $id');
        var gezag = gezagVoorHaal(artiest: artiest, titel: titel, album: album, jaar: jaar, seconden: seconden);
        try {
          ({int? jaar, int nummer, int schijf})? plek;
          final gevonden =
              origineelF == null ? null : await origineelF.timeout(const Duration(seconds: 8), onTimeout: () => null);
          if (gevonden != null && (!alsSingle || normKey(gevonden.album) != normKey(metAlbum))) {
            final j = gevonden.jaar;
            gezag = gezagVoorHaal(
                artiest: artiest,
                titel: titel,
                album: gevonden.album,
                jaar: j == null ? jaar : (jaar == null || j < jaar ? j : jaar),
                seconden: seconden);
            _log.line('radio "$artiest — $titel": album uit MusicBrainz — "${gevonden.album}"'
                '${j == null ? '' : ' ($j)'}');
            plek = await plekOpAlbum
                ?.call(artiest, titel, gevonden.album)
                .timeout(const Duration(seconds: 8), onTimeout: () => null)
                .then<({int? jaar, int nummer, int schijf})?>((p) => p, onError: (Object _) => null);
          } else {
            gezag = await metAlbumVanUploader(gezag, uit.path, artiest, titel, jaar, seconden);
          }
          final velden = veldenNaHaal(gezag,
              eigenAlbum: gezag.album.isEmpty ? null : readTags(File(uit.path))?.album, plek: plek);
          if (velden.isNotEmpty) await schrijfRadioTags(uit.path, velden, '$artiest — $titel');
        } catch (_) {/* het bestand staat goed; een mislukte tagschrijf maakt het niet stuk */}
        _log.line('radio "$artiest — $titel": TIDAL $id GELEVERD${r.kwaliteit == null ? "" : " (${r.kwaliteit})"} '
            'na ${_kort(DateTime.now().difference(t0))} — ${baseName(uit.path)}');
        return uit.path;
      } on RadioAlGehad {
        rethrow;
      } catch (e) {
        _log.line('   TIDAL $id: $e');
      } finally {
        try {
          if (map.existsSync()) await map.delete(recursive: true);
        } catch (_) {/* in gebruik; dan keurt de volgende start het restant */}
        _geefKeuringsmapVrij(map);
      }
    }
    return null;
  }

  /// Zoveel uploaders lopen tegelijk in een [_wedloop]: zoveel als er goede zijn, tot dertig. Elke loper
  /// erbij kan de kans op een vlotte start alleen vergroten.
  ///
  /// Gemeten op de pc (20-10-2026). Met 3.9.521: van zeven goede kandidaten (FLAC, vrije plek) begonnen er
  /// twee à drie meteen te sturen; de rest was onbereikbaar, brak af zonder één byte of begon pas na 20 s.
  /// Met twintig (3.9.522, vijf nummers via ▶) won loper #9, #4, #4, #3 en #19 — twee van de vijf stonden
  /// voorbij de vijfde, één voorbij de tiende, en elke keer liepen er twintig. Dus dertig (Saber: "wat met
  /// 30 tegelijkertijd?"); of de lopers 21–30 ooit winnen, staat in de logregel van de winnaar.
  ///
  /// Geen last voor Soulseek zelf: de overdrachten lopen tussen de peers, en het gewone downloaden houdt
  /// tot [_slskMaxParallel] nummers met elk [_maxLosslessTries] peers tegelijk open.
  ///
  /// **Wie ons in zijn rij zet, telt hier niet mee** — zoals in de race van het gewone downloaden ("a slot
  /// frees once its peer is queued"). Gemeten op de pc (20-10-2026, 3.9.524, Benson Boone — Beautiful
  /// Things): negen van de dertig vroege lopers zetten ons in hun rij ondanks hun "vrije plek", de rest
  /// was onbereikbaar; de dertig plaatsen bleven 17,7 s bezet zonder één byte, en de uploader die het in
  /// 0,7 s leverde (later in de zoekuitslag) kwam pas daarna aan de beurt — 21 s van tik tot geluid. Wie in
  /// een rij staat, houdt zijn plek daar en wint alsnog als hij als eerste begint.
  static const kWedloopTegelijk = 30;

  /// Zoveel uploaders hoogstens in één [_wedloop], ook als er later in de zoekuitslag nog goede opduiken.
  /// Ruimer dan [kWedloopTegelijk], omdat wie in een rij staat geen plaats inneemt.
  static const kWedloopLopers = 60;

  /// Een wedloop voor een nummer met een groeistroom: niet op één uploader wachten.
  ///
  /// **Waarom.** Gemeten op de pc (20-10-2026, 3.9.521): van drie vroege keuzes — FLAC, "vrije plek", een
  /// opgegeven snelheid van ruim een megabyte per seconde — begon er één na 1,5 s te sturen, één na 20 s
  /// (Kings Of Leon: 23 s van tik tot geluid) en één brak na 17 s zonder één byte af (Whitney Houston:
  /// ± 30 s). Een vrije plek zegt niets over hoe snel een uploader begint. Dus beginnen [eerste] en wat
  /// [volgende] nog geeft meteen samen, tot [kWedloopTegelijk]; wie afvalt of later in de uitslag opduikt,
  /// vult aan tot [kWedloopLopers]. Wie het eerst bytes stuurt wint (de `claim` van [_rawTransfer]); de rest
  /// stopt meteen. Zo doet het gewone downloaden het ook — één aanmelding, de verliezers afgebroken voor ze
  /// iets sturen. Null als niemand iets stuurde.
  Future<({SoulseekFile f, SlskResult res, bool afgekeurd})?> _wedloop(SlskSession session, DownloadJob job,
      SoulseekFile eerste, SoulseekFile? Function(Set<String> al) volgende, Groei vroeg,
      {required String artiest, required String titel, required int? seconden, void Function(String)? viel}) async {
    SoulseekFile? winnaar;
    final lopers = <SoulseekFile, ({SlskCancel stop, Future<SlskResult> res})>{};
    final klaar = <SoulseekFile>{};
    // Wie ons in zijn rij zette: die wacht daar, maar neemt geen plaats in (zie [kWedloopTegelijk]).
    final inRij = <SoulseekFile>{};
    // Waarom wie afviel afviel — alleen gelogd als niemand won, om na te gaan wat er gebeurde.
    final uitkomsten = <String>[];
    final klok = Stopwatch()..start();
    // Vastgelegd op het moment van winnen: daarna vallen de gestopte verliezers ook in [klaar].
    var winstMs = 0, afgevallen = 0, lopend = 0;
    void start(SoulseekFile f) {
      final stop = SlskCancel();
      job.live.add(stop);
      final res = _rawTransfer(session, f, job, () => inRij.add(f),
          waitInQueue: true, maxWait: kMaxWacht, cancel: stop, claim: () {
        if (winnaar != null) return false;
        winnaar = f;
        winstMs = klok.elapsedMilliseconds;
        afgevallen = klaar.length;
        lopend = lopers.length;
        for (final e in lopers.entries) {
          if (e.key != f) e.value.stop.cancel();
        }
        return true;
      }).then<SlskResult>((r) => r, onError: (Object e) => SlskFail('$e'));
      lopers[f] = (stop: stop, res: res);
      unawaited(res.then((r) {
        klaar.add(f);
        job.live.remove(stop);
        // Klaar vóór er een winnaar was = uit zichzelf afgevallen (onbereikbaar, afgebroken, te lang in de
        // rij). Wie pas daarna stopt, stopte omdat een ander won — die blijft goed voor een volgende ronde.
        if (winnaar == null && !job.cancelled) {
          viel?.call(f.username);
          uitkomsten.add('${f.username}: ${_uitkomst(r)} na ${klok.elapsedMilliseconds} ms'
              '${inRij.contains(f) ? ' (stond in de rij)' : ''}');
        }
      }));
    }

    // Aanvullen tot [kWedloopTegelijk] lopen: bij de start, en elke kwart seconde opnieuw — de tussenstand
    // van het zoeken groeit nog, en wie afvalt of ons in zijn rij zet, laat een plek vrij.
    int bezig() => lopers.keys.where((l) => !klaar.contains(l) && !inRij.contains(l)).length;
    void vulAan() {
      while (winnaar == null && lopers.length < kWedloopLopers && bezig() < kWedloopTegelijk) {
        final f = volgende({for (final l in lopers.keys) l.username});
        if (f == null) return;
        start(f);
      }
    }

    start(eerste);
    vulAan();
    while (winnaar == null && !job.cancelled) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (winnaar != null || job.cancelled) break;
      vulAan();
      if (lopers.length == klaar.length) break;
    }
    final w = winnaar;
    if (w == null) {
      for (final l in lopers.values) {
        l.stop.cancel();
      }
      _log.line('radio "$artiest — $titel": wedloop zonder winnaar — niemand van de ${lopers.length} stuurde '
          'iets (${klok.elapsedMilliseconds} ms)');
      for (final u in uitkomsten) {
        _log.line('   $u');
      }
      return null;
    }
    // Welke loper won (#1 = de eerste die begon) en hoeveel er toen al afgevallen waren: daaruit valt af te
    // lezen of de lopers achteraan ooit winnen — zie [kWedloopTegelijk].
    _log.line('radio "$artiest — $titel": ${w.username} stuurde als eerste, na $winstMs ms '
        '(loper #${lopers.keys.toList().indexOf(w) + 1} van $lopend, $afgevallen al afgevallen) — '
        '${baseName(w.filename)}');
    var overdrachtKlaar = false;
    final afgekeurd = w.size > 0 && w.filename.toLowerCase().endsWith('.flac')
        ? _vroegKeuren(vroeg, _bestemming(w), w, lopers[w]!.stop, () => overdrachtKlaar,
            artiest: artiest, titel: titel, seconden: seconden)
        : Future.value(false);
    // Een winnaar die stilvalt, valt af — zie [bewaakStilte]. Dan is de uitslag "gestopt", en de ronde
    // erna (zonder hem, [viel]) begint meteen.
    // Een winnaar die trager levert dan het nummer klinkt, valt ook af — maar alleen als er anderen
    // meededen: is hij de enige, dan liever traag dan niets ([teTraag]).
    final duur = (w.durationSec ?? 0) > 0 ? w.durationSec! : (seconden ?? 0);
    final verbruik = duur > 0 && w.size > 0 ? w.size / duur : null;
    final stilgevallen = bewaakStilte(_bestemming(w), w.size, lopers[w]!.stop, () => overdrachtKlaar,
        traag: verbruik == null || lopend < 2
            ? null
            : (binnen, bezig) => teTraag(binnen: binnen, totaal: w.size, bezig: bezig, verbruik: verbruik),
        gestopt: (binnen, waarom) {
      viel?.call(w.username);
      _log.line('radio "$artiest — $titel": ${w.username} viel af — $waarom op '
          '${(binnen / 1048576).toStringAsFixed(1)} van ${(w.size / 1048576).toStringAsFixed(1)} MB; gestopt, volgende');
    });
    final res = await lopers[w]!.res;
    overdrachtKlaar = true;
    await stilgevallen;
    return (f: w, res: res, afgekeurd: await afgekeurd);
  }

  /// Kijkt mee terwijl één kandidaat binnenkomt, en meldt het aan [g] (zie `groeistroom.dart`).
  ///
  /// Zodra er bytes staan: een [Groei.poging]. Zodra de kop compleet is ([flacAudioBegin]): dezelfde
  /// keuring als na het halen ([vroegeAfkeur]). Klopt die, dan [Groei.goedgekeurd] en mag het klinken;
  /// klopt die niet, dan wordt deze overdracht METEEN gestopt — er klinkt nooit eerst een verkeerd
  /// nummer, en de volgende uploader hoeft niet te wachten tot een fout bestand helemaal binnen is.
  /// Geeft terug of het afgekeurd werd. Alleen voor FLAC: zie de aanroep.
  Future<bool> _vroegKeuren(Groei g, File dest, SoulseekFile f, SlskCancel stop, bool Function() klaar,
      {required String artiest, required String titel, required int? seconden}) async {
    var gemeld = false;
    while (!klaar() && !stop.isCancelled) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (klaar() || stop.isCancelled) return false;
      int staat;
      try {
        staat = dest.lengthSync();
      } catch (_) {
        continue; // nog niet aangemaakt
      }
      if (staat <= 0) continue;
      if (!gemeld) {
        gemeld = true;
        g.poging(pad: dest.path, totaal: f.size);
      }
      final kopBytes = flacAudioBegin(dest);
      if (kopBytes == null) {
        // Een kop van meer dan 24 MB (een hoes van een poster) is geen kop meer: dan maar niet vroeg.
        if (staat > 24 * 1024 * 1024) return false;
        continue;
      }
      final kop = readFlacTags(dest);
      final tags = kop == null || (kop.title == null && kop.artist == null && kop.album == null)
          ? null
          : TrackTags(
              title: kop.title ?? baseName(f.filename),
              artist: kop.artist ?? '',
              album: kop.album ?? '',
              trackNo: kop.trackNo,
              vanBestand: true);
      final duur = kop?.duration;
      final waarom = vroegeAfkeur(
          artiest: artiest,
          titel: titel,
          seconden: seconden,
          tags: tags,
          bestandSeconden: duur == null ? null : (duur.inMilliseconds / 1000).round(),
          pad: dest.path);
      if (waarom != null) {
        _log.line('radio "$artiest — $titel": ${f.username} — kop gelezen terwijl hij binnenkwam: $waarom; '
            'gestopt, volgende');
        stop.cancel();
        return true;
      }
      g.goedgekeurd(duur!, kopBytes: kopBytes);
      return false;
    }
    return false;
  }

  /// Zo lang verzamelt een haal met een groeistroom uitslagen voordat hij al mag beginnen. Zie
  /// [vroegeKandidaat].
  static const kVroegZoeken = Duration(milliseconds: 1200);

  /// Hoe vlot een uploader minstens moet zijn (zijn eigen opgave, bytes per seconde) om vroeg te
  /// beginnen. Een cd-FLAC verbruikt 100 à 200 kB/s; met een halve megabyte per seconde staat er na een
  /// tel al genoeg om door te spelen.
  static const kVroegeSnelheid = 512 * 1024;

  /// De kandidaat waarmee een haal al mag beginnen terwijl het zoeken nog loopt, of null.
  ///
  /// Strenger dan de gewone keuze, want er is nog niet alles binnen om uit te kiezen: alleen FLAC (dan
  /// kan het klinken terwijl het binnenkomt, zie groeistroom.dart), alleen een uploader met een vrije
  /// plek (geen wachtrij) en een opgegeven snelheid van minstens [kVroegeSnelheid], en door dezelfde
  /// zeef als de gewone weg ([radioBestandKlopt]). Daarbinnen de officiële lengte voorop.
  @visibleForTesting
  static SoulseekFile? vroegeKandidaat(List<SoulseekFile> tussenstand,
      {required String artiest, required String titel, int? seconden, Set<String> nietBij = const {}}) {
    final goed = [
      for (final f in tussenstand)
        if (f.freeSlots &&
            f.speed >= kVroegeSnelheid &&
            f.size > 0 &&
            f.filename.toLowerCase().endsWith('.flac') &&
            isLossless(f) &&
            !isMultichannel(f) &&
            !nietBij.contains(f.username) &&
            // Alleen de officiële lengte (±2 s, [lengteKlopt]) — zoals de race van het gewone downloaden
            // ([lengteDelen]): in een wedloop wint wie het eerst stuurt, dus de voorkeur moet uit wie
            // meedoet komen, niet uit een sortering. Een andere lengte binnen de radiomarge komt pas in
            // de hele uitslag aan de beurt, als er niets met de juiste lengte is.
            (seconden == null || seconden <= 0 || lengteKlopt(seconden, f.durationSec)) &&
            radioBestandKlopt(
                artiest: artiest, titel: titel, seconden: seconden, pad: f.filename, padSeconden: f.durationSec))
          f
    ]..sort(opLengteDanRang(seconden));
    return goed.isEmpty ? null : goed.first;
  }

  /// De tags die een radiohaal of ▶ na het landen in het bestand schrijft ([stampTags]).
  ///
  /// Met [album] (▶: de uitgave waarop je het nummer zag) ook ALBUM en ALBUMARTIST. Zonder dat hield het
  /// bestand de albumtag van de uploader: Jordy — Dur Dur D'être Bébé, met ▶ uit de zoekuitslag waar
  /// Deezer "Pochette Surprise" toont, stond als "Foute Cd 11 Cd2" in je bibliotheek, met de hoes van die
  /// verzamelaar (Saber, 21-10-2026: "het moet echt de originele hoes zijn"). De ⬇ ernaast deed dit al.
  /// Is dat album zelf een verzamelaar ([lijktVerzamelaar]), dan blijft het zoals het was.
  @visibleForTesting
  static TrackTags gezagVoorHaal(
      {required String artiest, required String titel, String? album, int? jaar, int? seconden}) {
    final a = album?.trim() ?? '';
    final metAlbum = a.isNotEmpty && !lijktVerzamelaar(a);
    return TrackTags(
      title: titel,
      artist: artiest,
      album: metAlbum ? a : '',
      albumArtist: metAlbum ? artiest : null,
      trackNo: 0,
      year: jaar,
      seconds: seconden,
    );
  }

  /// Wat een radiohaal of ▶ na het landen in het bestand schrijft: [gezag], als dat gezaghebbend is.
  ///
  /// Heeft het gezag een album en had het bestand een ánder ([eigenAlbum]: een verzamelrip), dan horen zijn
  /// nummer, schijf en jaar bij die andere uitgave: weg — of, als Deezer het weet ([plek]), die van deze
  /// uitgave. Jordy uit de Foute CD stond zo als nummer 11 van 2012 op Pochette Surprise (1992).
  @visibleForTesting
  static Map<String, String?> veldenNaHaal(TrackTags gezag,
      {String? eigenAlbum, ({int? jaar, int nummer, int schijf})? plek}) {
    final velden = <String, String?>{};
    if (gezag.album.isNotEmpty && normKey(eigenAlbum ?? '') != normKey(gezag.album)) {
      for (final k in const ['TRACKNUMBER', 'TRACKTOTAL', 'TOTALTRACKS', 'DISCNUMBER', 'DISCTOTAL', 'TOTALDISCS', 'DATE']) {
        velden[k] = null;
      }
      if (plek != null) {
        if (plek.nummer > 0) velden['TRACKNUMBER'] = '${plek.nummer}';
        if (plek.schijf > 0) velden['DISCNUMBER'] = '${plek.schijf}';
        if (plek.jaar != null) velden['DATE'] = '${plek.jaar}';
      }
    }
    if (gezag.isAuthoritative) velden.addAll(gezag.vorbisFields);
    return velden;
  }

  /// [gezag] met het nummer en het jaar uit [plek] — voor de jacht op beter na ▶, die na het vervangen
  /// opnieuw tagt ([_queueUpgrade]).
  static TrackTags metPlek(TrackTags gezag, ({int? jaar, int nummer, int schijf})? plek) => plek == null
      ? gezag
      : TrackTags(
          title: gezag.title,
          artist: gezag.artist,
          album: gezag.album,
          albumArtist: gezag.albumArtist,
          trackNo: plek.nummer > 0 ? plek.nummer : gezag.trackNo,
          year: gezag.year ?? plek.jaar,
          seconds: gezag.seconds,
        );

  Future<String?> _haalVoorRadio(DownloadJob job, String artiest, String titel, int? seconden, int? jaar,
      {Groei? vroeg, bool zoekBeter = false, String? album}) async {
    final sleutel = _radioSleutel(artiest, titel);
    // Alleen wat ECHT dit nummer is, in de gevraagde uitvoering en ongeveer de juiste lengte — zie
    // `radiobestand.dart` voor de zes verkeerde nummers van 26-09-2026 — en niet bij een uploader die
    // het deze radio al liet afweten.
    var alleenMp3 = 0; // met een groeistroom: zoveel treffers waren dit nummer, maar niet lossless
    List<SoulseekFile> kandidatenUit(List<SoulseekFile> hits) {
      final nietBij = _radioNietBij[sleutel] ?? const <String>{};
      final passend = [
        for (final f in hits)
          if (!isMultichannel(f) &&
              !nietBij.contains(f.username) &&
              radioBestandKlopt(
                  artiest: artiest,
                  titel: titel,
                  seconden: seconden,
                  pad: f.filename,
                  padSeconden: f.durationSec))
            f
      ];
      // De officiële lengte voorop, net als bij elke andere download — zie [opLengteDanRang].
      // En een vinyl-rip pas als er niets anders is: de radio kiest zelf, en vinyl is "alleen als ik kies".
      final bruikbaar = vinylAchteraan(passend..sort(opLengteDanRang(seconden)), (f) => f.filename);
      // Lossless eerst, precies zoals overal in deze app. Maar niet lossless-of-niets: een
      // eurodance-single uit 1993 bestaat op dit netwerk soms alleen als mp3, en dan is die mp3 beter
      // dan stilte. `_rankSlsk` heeft de beste al vooraan gezet.
      //
      // En binnen lossless eerst wat de app kan taggen (FLAC): een AIFF of WAV zonder tags staat anders
      // als "Onbekende artiest" in je bibliotheek — zie [radioZonderTags].
      //
      // Met een groeistroom (▶, en de radio met de proef aan) nooit een mp3 — Saber, 20-10-2026: "geen mp3
      // binnenhalen". In een wedloop wint wie het eerst stuurt, niet wie het best is: stond er een mp3
      // tussen, dan kon die het halen van een FLAC. Bestaat het nummer hier alleen als mp3, dan telt het als
      // niets bruikbaars — één zoekronde, en ▶ vraagt het daarna aan TorBox.
      alleenMp3 = vroeg == null ? 0 : bruikbaar.where((f) => !isLossless(f)).length;
      return [
        ...bruikbaar.where((f) => isLossless(f) && radioTagsSchrijfbaar(f.filename)),
        ...bruikbaar.where((f) => isLossless(f) && !radioTagsSchrijfbaar(f.filename)),
        if (vroeg == null) ...bruikbaar.where((f) => !isLossless(f)),
      ];
    }

    // Wat er gevonden werd maar niet door de zeef kwam: een paar voorbeelden in het logboek, zodat "niets
    // bruikbaars" na te kijken is (20-10-2026: 203 treffers voor Sabien Tiels, en geen enkele telde).
    String voorbeelden(List<SoulseekFile> hits) => hits.isEmpty
        ? ''
        : ' — bv. ${[
            for (final f in hits.take(3))
              '"${f.filename.split(RegExp(r'[\\/]')).reversed.take(2).toList().reversed.join('/')}"'
                  '${f.durationSec == null ? '' : ' (${f.durationSec} s)'}'
          ].join(', ')}${seconden == null ? '' : '; gevraagd $seconden s'}';

    void logKandidaten(List<SoulseekFile> kandidaten, List<SoulseekFile> hits) {
      final nietBij = _radioNietBij[sleutel] ?? const <String>{};
      if (kandidaten.isEmpty && nietBij.isEmpty) {
        _radioZonderKandidaat.add(sleutel);
      } else {
        _radioZonderKandidaat.remove(sleutel);
      }
      if (kandidaten.isEmpty && alleenMp3 > 0) {
        _log.line('radio "$artiest — $titel": ${hits.length} treffers, niets bruikbaars — $alleenMp3 zijn dit '
            'nummer, maar alleen lossy (mp3 of zo), en met een groeistroom niet');
        return;
      }
      if (kandidaten.isEmpty) {
        _log.line('radio "$artiest — $titel": ${hits.length} treffers, niets bruikbaars'
            '${hits.isEmpty ? "" : " — geen enkele is dit nummer in deze uitvoering${voorbeelden(hits)}"}');
        return;
      }
      // Hoeveel er door de zeef kwam: zonder dit getal is "de radio vindt minder" niet te scheiden van
      // "Soulseek heeft het niet".
      _log.line('radio "$artiest — $titel": ${kandidaten.length} van ${hits.length} treffers '
          'zijn dit nummer${nietBij.isEmpty ? "" : ", ${nietBij.length} uploader(s) overgeslagen"}');
    }

    // **Met een groeistroom ([vroeg]) niet wachten tot het zoeken klaar is.** Een zoekopdracht wacht acht
    // seconden op uitslagen (`_SearchRun.settle`); gemeten op 20-10-2026 was dat het grootste deel van
    // 15 s van tik tot geluid. Staat er na [kVroegZoeken] een goede kandidaat — FLAC, een vrije plek, een
    // vlotte uploader, door dezelfde zeef — dan begint die meteen, terwijl het zoeken doorloopt. Lukt
    // die niet, dan gaat het verder met de hele uitslag, zonder die uploader.
    final klok = Stopwatch()..start();
    final vroegeKeus = Completer<SoulseekFile?>();
    var tussenstand = const <SoulseekFile>[];
    void kies() {
      if (vroegeKeus.isCompleted) return;
      final f = vroegeKandidaat(tussenstand,
          artiest: artiest, titel: titel, seconden: seconden, nietBij: _radioNietBij[sleutel] ?? const {});
      if (f != null) vroegeKeus.complete(f);
    }

    // De radio is achtergrond; ▶ (los van de radio) niet — daar wacht je op.
    final zoek = soulseek.search(zoekvraagVoorNummer(titel, artist: artiest),
        achtergrond: _radiohalen.contains(job),
        onPartial: vroeg == null
            ? null
            : (lijst) {
                tussenstand = lijst;
                if (klok.elapsed >= kVroegZoeken) kies();
              });
    Timer? kijk;
    if (vroeg != null) {
      kijk = Timer(kVroegZoeken, kies);
      unawaited(zoek.then((_) {}, onError: (_) {}).whenComplete(() {
        kijk?.cancel();
        if (!vroegeKeus.isCompleted) vroegeKeus.complete(null);
      }));
    }
    final eerste = vroeg == null ? null : await vroegeKeus.future;

    Future<List<SoulseekFile>?> uitslag() async {
      try {
        return await zoek;
      } catch (_) {
        // Geen aanmelding is geen mislukte plek — zie [RadioLaterOpnieuw]. Een zwijgende server ook niet. Geen net wel.
        final waarom = soulseek.whyNotLogin ?? soulseek.waaromStil;
        if (waarom != null) throw RadioLaterOpnieuw(waarom);
        return null;
      }
    }

    var kandidaten = const <SoulseekFile>[];
    if (eerste == null) {
      final hits = await uitslag();
      if (hits == null) return null;
      if (job.cancelled) return null; // de radio is afgesloten terwijl we zochten
      // Niets gevonden ZONDER aanmelding is geen antwoord. Een verbinding die niet opkomt (geen net,
      // een route die wisselt, de server die herstart) zet geen blokkade, dus [whyNotLogin] zegt niets —
      // en dan brandde de radio zijn plan op aan "0 treffers" (review van 26-09-2026).
      if (hits.isEmpty && soulseek.available && !soulseek.verbonden) {
        throw const RadioLaterOpnieuw('geen verbinding met Soulseek');
      }
      kandidaten = kandidatenUit(hits);
      logKandidaten(kandidaten, hits);
      if (kandidaten.isEmpty) return null;
    } else {
      _log.line('radio "$artiest — $titel": na ${klok.elapsedMilliseconds} ms al begonnen bij ${eerste.username} '
          '(${tussenstand.length} treffers tot dan) — ${baseName(eerste.filename)}');
    }

    var gezag = gezagVoorHaal(artiest: artiest, titel: titel, album: album, jaar: jaar, seconden: seconden);
    // Geen album (de radio), of dat van een verzamelaar: de oorspronkelijke uitgave opzoeken, en die in het bestand
    // zetten. Saber, 23-10-2026, op de vraag of de app dat zelf mag: "Ja". Ook alvast, terwijl er gezocht wordt.
    // En als het album gewoon de single van dit nummer is ("Summer Of '69" in plaats van Reckless): dan ook, want een
    // single krijgt geen tracklijst en geen cd-afbeelding — zie `albumIsDeSingle`.
    final alsSingle = gezag.album.isNotEmpty && albumIsDeSingle(gezag.album, titel);
    final origineelF = gezag.album.isEmpty || alsSingle
        ? origineleUitgave?.call(artiest, titel, seconden).then<({String album, int? jaar})?>((o) => o,
            onError: (Object _) => null)
        : null;
    // En de hoezen van die plaat alvast, terwijl er gehaald wordt ([albumBekend]).
    meldAlbum(artiest, titel, seconden, album: alsSingle ? '' : gezag.album, origineel: origineelF);
    // Waar het nummer op dat album staat: alvast opzoeken, terwijl er gezocht en gehaald wordt.
    final plekF = gezag.album.isEmpty
        ? null
        : plekOpAlbum?.call(artiest, titel, gezag.album).then<({int? jaar, int nummer, int schijf})?>((p) => p,
            onError: (Object _) => null);
    // Opbergen met de tags ZONDER jaar, en pas daarna de gezaghebbende schrijven: met een jaar geldt
    // alles wat op dezelfde plek ligt als dezelfde opname, zonder naar naam of versie te kijken, en dan
    // zou een andere opname van jou met dezelfde titel stil opzij gaan (review van 26-09-2026).
    final plaatsing = TrackTags(
      title: titel,
      artist: artiest,
      album: '',
      trackNo: 0,
      seconds: seconden,
    );
    String? geland;
    try {
      await _withSlsk<void>((session, _) async {
        // Eén uploader: halen, keuren, opbergen. [_Uit.volgende] = probeer de volgende.
        // [mee]: een wedloop — zie [_wedloop]. Dan is [f] daarna de uploader die won.
        Future<_Uit> probeer(SoulseekFile f, {SoulseekFile? Function(Set<String> al)? mee}) async {
          if (job.cancelled) return _Uit.stop;
          final t0 = DateTime.now();
          SlskResult res;
          final Future<bool> vroegAfgekeurd;
          if (mee != null && vroeg != null) {
            // Wie in de wedloop uit zichzelf afviel, slaat dit nummer voortaan over — net als een uploader
            // die hieronder mislukt. Wie stopte omdat een ander won, niet.
            final w = await _wedloop(session, job, f, mee, vroeg,
                artiest: artiest,
                titel: titel,
                seconden: seconden,
                viel: (u) => (_radioNietBij[sleutel] ??= {}).add(u));
            if (w == null) {
              vroeg.afgebroken();
              return job.cancelled ? _Uit.stop : _Uit.volgende;
            }
            f = w.f;
            res = w.res;
            vroegAfgekeurd = Future.value(w.afgekeurd);
          } else {
            // De stopschakelaar van DEZE poging, opgeborgen waar [staakRadiohalen] hem kan vinden.
            // Zonder dit is `job.cancelled` alleen een vlag die pas tússen twee peers gelezen wordt —
            // en een overdracht die halverwege een bestand van tien megabyte zit, leest hem dan pas
            // over een minuut.
            final stop = SlskCancel();
            job.live.add(stop);
            // Al laten klinken terwijl het binnenkomt: alleen FLAC, want alleen daar staat alles wat de
            // keuring hieronder wil weten (artiest, titel, looptijd) vóór de audio. En alleen met een
            // bekende grootte: die belooft de stroom vooraf aan mpv.
            var overdrachtKlaar = false;
            vroegAfgekeurd = vroeg != null && f.size > 0 && f.filename.toLowerCase().endsWith('.flac')
                ? _vroegKeuren(vroeg, _bestemming(f), f, stop, () => overdrachtKlaar,
                    artiest: artiest, titel: titel, seconden: seconden)
                : Future.value(false);
            try {
              res = await _rawTransfer(session, f, job, () {},
                  waitInQueue: true, maxWait: kMaxWacht, cancel: stop);
            } catch (_) {
              vroeg?.afgebroken();
              return _Uit.volgende;
            } finally {
              overdrachtKlaar = true;
              job.live.remove(stop);
            }
          }
          if (await vroegAfgekeurd) (_radioNietBij[sleutel] ??= {}).add(f.username);
          if (job.cancelled) return _Uit.stop;
          _log.line('radio "$artiest — $titel": ${f.username} '
              '${_uitkomst(res)} na ${_kort(DateTime.now().difference(t0))} — ${baseName(f.filename)}');
          if (res is! SlskDone) vroeg?.afgebroken();
          if (res is! SlskDone) {
            // Kon ONZE kant niet aanmelden, dan ligt het niet aan deze uploader, en ook niet aan de
            // volgende twee: stoppen en de plek later opnieuw. Gemeten op 26-09-2026: "mislukt: Kan
            // niet inloggen bij Soulseek na 0s", drie peers achter elkaar, en alle drie werden ze
            // daarna voor dat nummer overgeslagen.
            if ((res is SlskFail && res.reason.startsWith('Kan niet inloggen')) ||
                soulseek.whyNotLogin != null) {
              throw RadioLaterOpnieuw(soulseek.whyNotLogin ?? 'geen aanmelding');
            }
            (_radioNietBij[sleutel] ??= {}).add(f.username);
            return _Uit.volgende;
          }
          // Klonk het al terwijl het binnenkwam, dan nu in het geheugen ermee: vanaf hier mag het bestand
          // verplaatst en van tags voorzien worden zonder dat de lopende stroom het merkt (groeistroom.dart).
          await vroeg?.binnen();
          // Het tweede net: wat er IN het bestand staat. Een peer kan een bestand goed noemen en iets
          // anders laten klinken, en dat hoort nooit in je bibliotheek te landen.
          final binnen = File(res.path);
          final t = readTags(binnen);
          if (radioTagsSprekenTegen(artiest, titel, t)) {
            _log.line('radio "$artiest — $titel": ${f.username} leverde een ander nummer '
                '(${t?.artist} — ${t?.title}) — weggegooid, volgende');
            (_radioNietBij[sleutel] ??= {}).add(f.username);
            vroeg?.afgebroken();
            try {
              await binnen.delete();
            } catch (_) {/* dan ruimt de wachtmap het later op */}
            return _Uit.volgende;
          }
          // Geen tags, en ze zijn er ook niet in te zetten (AIFF, WAV): dan blijft het voor altijd
          // "Onbekende artiest". Liever de volgende uploader — zie [radioZonderTags].
          if (radioZonderTags(t, binnen.path)) {
            _log.line('radio "$artiest — $titel": ${f.username} leverde een bestand zonder tags dat de '
                'app niet kan beschrijven — weggegooid, volgende');
            (_radioNietBij[sleutel] ??= {}).add(f.username);
            vroeg?.afgebroken();
            try {
              await binnen.delete();
            } catch (_) {/* dan ruimt de wachtmap het later op */}
            return _Uit.volgende;
          }
          // En de ECHTE lengte. Een peer meldt die lang niet altijd, en dan telde de lengte vóór het
          // halen niet mee — zo kan een albumversie van 5:36 op de plek van een single van 4:17 komen.
          final echt = looptijdInSeconden(binnen);
          if (radioLengteSpreektTegen(seconden, echt)) {
            _log.line('radio "$artiest — $titel": ${f.username} leverde ${echt}s, gevraagd '
                '${seconden}s — een andere versie, weggegooid, volgende');
            (_radioNietBij[sleutel] ??= {}).add(f.username);
            vroeg?.afgebroken();
            try {
              await binnen.delete();
            } catch (_) {/* dan ruimt de wachtmap het later op */}
            return _Uit.volgende;
          }

          // Nog één keer kijken, vlak vóór het filen. Tussen de toets bovenaan en dit moment kan een
          // andere haal — of de jacht op een betere kwaliteit — hetzelfde nummer hebben laten landen.
          final alBekend = mapVanBestaande?.call(artiest, titel, seconds: seconden);
          PlaceOutcome uit;
          // Meten vóór het filen, zoals op elke andere weg — hier gebeurde het niet, en dan besliste de
          // keuring over een radiobestand zonder te weten wat erin zat. Heel is hij al: dat deed de
          // overdracht zelf (zie [_cleanStaging]).
          await _bereidVergelijkingVoor(File(res.path), plaatsing);
          try {
            // [parkeerAltijd]: wat hier verliest, gaat opzij en nooit weg. Zonder dat wiste een radio-FLAC
            // een mp3 die je al had wanneer de bibliotheek ze niet als dezelfde opname herkende.
            uit = await placeFileDetailed(File(res.path), _downloadsRoot,
                tags: plaatsing,
                staatAl: mapVanBestaande,
                parkeerAltijd: true,
                parkeerBinnenkomend: false);
          } catch (_) {
            vroeg?.afgebroken();
            return _Uit.volgende;
          }
          if (alBekend != null || uit.how != Placement.moved || uit.verving) {
            _log.line('radio "$artiest — $titel": geland op muziek die je al had — '
                'niet van de radio, wordt straks niet opgeruimd');
            // Wel laten klinken: daarvoor werd het gehaald. Zie [RadioAlGehad] — eerst bleef hier een
            // lege plek in de radio.
            if (uit.how != Placement.stuck && File(uit.path).existsSync()) {
              vroeg?.geland(uit.path);
              throw RadioAlGehad(uit.path);
            }
            return _Uit.stop;
          }
          _noteerSoort(uit.path, f.filename);
          // Pas NA het landen, en dit ontbrak op de hele downloadweg: `rebuildAlbums` groepeert op de
          // tags ván het bestand, dus zonder dit vult je raster zich met de rommelalbums van de
          // uploader.
          ({int? jaar, int nummer, int schijf})? plek;
          try {
            final gevonden =
                origineelF == null ? null : await origineelF.timeout(const Duration(seconds: 8), onTimeout: () => null);
            // Bij een single als album alleen iets ánders dan die single: het studioalbum of de ep waar hij op staat.
            final origineel = gevonden != null && (!alsSingle || normKey(gevonden.album) != normKey(gezag.album))
                ? gevonden
                : null;
            if (origineel != null) {
              final j = origineel.jaar;
              gezag = gezagVoorHaal(
                  artiest: artiest,
                  titel: titel,
                  album: origineel.album,
                  // Het vroegste: Deezer dateert een heruitgave, MusicBrainz de eerste persing.
                  jaar: j == null ? jaar : (jaar == null || j < jaar ? j : jaar),
                  seconden: seconden);
              _log.line('radio "$artiest — $titel": album uit MusicBrainz — "${origineel.album}"'
                  '${j == null ? '' : ' ($j)'}');
              plek = await plekOpAlbum
                  ?.call(artiest, titel, origineel.album)
                  .timeout(const Duration(seconds: 8), onTimeout: () => null)
                  .then<({int? jaar, int nummer, int schijf})?>((p) => p, onError: (Object _) => null);
              // Een Deezer-single draagt zelf geen jaar: dan dat van de plek op die single.
              final pj = plek?.jaar;
              if (j == null && pj != null) {
                gezag = gezagVoorHaal(
                    artiest: artiest,
                    titel: titel,
                    album: origineel.album,
                    jaar: jaar == null || pj < jaar ? pj : jaar,
                    seconden: seconden);
              }
            } else {
              gezag = await metAlbumVanUploader(gezag, uit.path, artiest, titel, jaar, seconden);
              plek = plekF == null
                  ? null
                  : await plekF.timeout(const Duration(seconds: 8), onTimeout: () => null);
            }
            final velden = veldenNaHaal(gezag,
                eigenAlbum: gezag.album.isEmpty ? null : readTags(File(uit.path))?.album, plek: plek);
            if (velden.isNotEmpty) await schrijfRadioTags(uit.path, velden, '$artiest — $titel');
          } catch (_) {/* het bestand staat goed; een mislukte tagschrijf maakt het niet stuk */}
          // Zonder jaartal is het gezag niet gezaghebbend en schrijft [stampTags] niets. Heeft het
          // bestand zelf dan ook geen artiest of titel, dan staat het als "Onbekende artiest" met
          // de bestandsnaam als titel in de rij — gezien op 26-09-2026 bij "Got To Move Your Body"
          // en "The Mackenzie Feat. Jessy - Innocence". Alleen die twee velden, en alleen als ze
          // ontbreken: een album of jaartal dat er wél staat blijft staan.
          if (!gezag.isAuthoritative) {
            try {
              if (radioTagsOntbreken(readTags(File(uit.path)))) {
                await writeTagFields(File(uit.path), {'TITLE': titel, 'ARTIST': artiest});
              }
            } catch (_) {/* zelfde als hierboven */}
          }
          vroeg?.geland(uit.path);
          geland = uit.path;
          if (zoekBeter) {
            unawaited(_zoekBeterNaHetLanden(job, f, uit.path, seconden,
                gezag: metPlek(gezag, plek),
                plaatsing: plaatsing,
                // De hele uitslag: bij een vroege start zocht de zoektocht intussen verder.
                alle: () async => kandidatenUit(await uitslag() ?? tussenstand)));
          }
          return _Uit.klaar;
        }

        if (eerste != null) {
          final wedloop = await probeer(eerste,
              mee: (al) => vroegeKandidaat(tussenstand,
                  artiest: artiest,
                  titel: titel,
                  seconden: seconden,
                  nietBij: {...?_radioNietBij[sleutel], ...al}));
          if (wedloop != _Uit.volgende) return;
          // De vroege ging niet: dan de hele uitslag, zonder wie afviel of mislukte (dat staat al in
          // [_radioNietBij] — zie `viel` in [probeer]).
          final hits = await uitslag();
          if (hits == null || job.cancelled) return;
          kandidaten = kandidatenUit(hits);
          logKandidaten(kandidaten, hits);
        }
        if (vroeg == null) {
          for (final f in kandidaten.take(3)) {
            if (await probeer(f) != _Uit.volgende) return;
          }
          return;
        }
        // Met een groeistroom alleen FLAC in de wedloop (een mp3 staat hier al niet meer tussen — zie
        // `alleenMp3`). Geen FLAC: dan nog een AIFF of WAV (lossless, maar klinkt pas als hij binnen is),
        // één voor één.
        bool stroombaar(SoulseekFile k) => k.size > 0 && k.filename.toLowerCase().endsWith('.flac');
        final flac = kandidaten.where(stroombaar).toList();
        if (flac.isEmpty) {
          for (final f in kandidaten.where(isLossless).take(3)) {
            if (await probeer(f) != _Uit.volgende) return;
          }
          return;
        }
        // De volledige lijst als wedloop, niet één voor één. Gemeten op de pc (20-10-2026, Selah Sue —
        // Raggamuffin): de eerste onbereikbaar (23 s), de tweede afgebroken zonder één byte (18 s), de derde
        // leverde alles in één tel — 45 s van tik tot geluid.
        //
        // Een volgende ronde alleen als de winnaar mislukte of afgekeurd werd, of als niemand stuurde. Wie
        // in [_radioNietBij] staat, viel af of mislukte; de verliezers die stopten omdat een ander won, doen
        // gewoon weer mee.
        bool vrij(SoulseekFile k) => !(_radioNietBij[sleutel]?.contains(k.username) ?? false);
        // Eerst alleen wat de officiële lengte heeft, dan pas de rest — zoals het gewone downloaden
        // ([lengteDelen]; Saber: "letten dat hij de juiste song binnenhaalt"). Wie het eerst stuurt wint, dus
        // een kopie die 10 s langer is mag niet meedoen zolang er een met de juiste lengte kan.
        for (final deel in lengteDelen(flac, seconden)) {
          for (var ronde = 0; ronde < 3; ronde++) {
            final over = deel.where(vrij).toList();
            if (over.isEmpty) break;
            final uit = await probeer(over.first, mee: (al) {
              for (final k in over) {
                if (!al.contains(k.username) && vrij(k)) return k;
              }
              return null;
            });
            if (uit != _Uit.volgende) return;
          }
        }
      });
    } on RadioLaterOpnieuw catch (e) {
      _log.line('radio "$artiest — $titel": Soulseek doet even niet mee (${e.waarom}) — later opnieuw');
      rethrow;
    } on RadioAlGehad {
      rethrow; // geen storing: het nummer is er, alleen niet van de radio
    } catch (_) {
      // Niets verloren: deze plek in het plan mislukt gewoon — tenzij het aan de aanmelding lag.
      final waarom = soulseek.whyNotLogin;
      if (waarom != null) throw RadioLaterOpnieuw(waarom);
    } finally {
      // Elke andere uitgang (gestopt, geen aanmelding, een fout): wat er klonk van een peer die niet
      // landde, houdt op. Na [Groei.geland] doet dit niets meer.
      vroeg?.afgebroken();
    }
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
          // Meten vóór het filen: hier gebeurde dat niet, en dan kon jouw vaste keuze alleen op de
          // gelijkstand winnen — of verliezen van iets wat nooit gemeten werd.
          await _bereidVergelijkingVoor(File(res.path), w.authority);
          final uit = await placeFileDetailed(File(res.path), _downloadsRoot,
              tags: w.authority, staatAl: mapVanBestaande);
          if (uit.how == Placement.moved) await onthoudVasteKeuze(uit.path);
          if (uit.how == Placement.moved) _noteerSoort(uit.path, b.filename);
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

  /// Speelt de speler dit pad nu (ook gepauzeerd)? Gezet in main.dart. Een betere kopie van een nummer
  /// dat je net met ▶ aanzette, vervangt het pas als het niet meer speelt — zie [_chaseUpgrade].
  bool Function(String pad)? speeltNu;

  /// Voor Deze houden ([vervangDoorTwijfel]): [speeltNu], maar zonder wat het vragende toestel zelf leest of speelt.
  /// Null: dan [speeltNu].
  bool Function(String pad, {String? behalveLezer, String? behalveZone})? inGebruikVoorHouden;

  /// Hoe lang een gevonden betere kopie wacht tot het nummer niet meer speelt. Daarna gaat ze weg: wie
  /// een nummer twintig minuten op pauze laat staan, krijgt de jacht een volgende keer opnieuw.
  static const kWachtOpStilte = Duration(minutes: 20);

  Future<bool> _wachtTotNietMeerSpeelt(String pad) async {
    final tot = DateTime.now().add(kWachtOpStilte);
    while (speeltNu?.call(pad) ?? false) {
      if (DateTime.now().isAfter(tot)) return false;
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    return true;
  }

  /// De kandidaten die [gekozen] mogen opwaarderen ([magOpwaarderen]: duidelijk beter, en nooit verder
  /// van de officiële lengte), zonder hetzelfde bestand nog eens.
  static List<SoulseekFile> betereKandidaten(List<SoulseekFile> alle, SoulseekFile gekozen, int? officieel) =>
      vinylAchteraan([
        for (final k in alle)
          if (!(k.username == gekozen.username && k.filename == gekozen.filename) &&
              magOpwaarderen(k, gekozen, officieel))
            k
      ], (f) => f.filename);

  /// Na ▶: het klonk meteen met de snelste FLAC, en nu dezelfde jacht op beter als na een gewone
  /// download (Saber, 20-10-2026: "eerst de snelste flac, om daarna een betere versie te zoeken").
  /// Uit de hele zoekuitslag van dít nummer; vervangen pas als het niet meer speelt.
  Future<void> _zoekBeterNaHetLanden(DownloadJob job, SoulseekFile gekozen, String pad, int? seconden,
      {required TrackTags gezag, required TrackTags plaatsing, required Future<List<SoulseekFile>> Function() alle}) async {
    // ▶ is binnen: "24bit" op de achtergrond, los van de kandidaten hieronder (Saber, 24-10-2026: "na het landen").
    _naLandenHires(pad, plaatsing, gekozen);
    try {
      final beter = betereKandidaten(await alle(), gekozen, seconden);
      if (beter.isEmpty) {
        _log.line('"${job.name}": na ▶ geen betere kandidaat in deze zoekuitslag — het blijft '
            '${baseName(gekozen.filename)}');
        return;
      }
      job.authority = plaatsing;
      _queueUpgrade(beter, job, gezag: gezag, speeltPad: pad, parkeerAltijd: true);
    } catch (_) {/* niets verloren: wat klonk, staat in je bibliotheek */}
  }

  /// Je eigen bestand als Soulseek-kandidaat, om er een gevonden kopie mee te vergelijken. [clearlyBetter]
  /// kijkt naar de soort en de bitrate (grootte gedeeld door lengte), zoals Soulseek die van een kopie
  /// toont. Null zonder grootte of lengte: dan valt er niets te vergelijken.
  static SoulseekFile? eigenAlsKandidaat(Track t) {
    final sec = t.duration?.inSeconds ?? 0;
    if (t.sizeBytes <= 0 || sec <= 0) return null;
    return SoulseekFile(
        username: '',
        filename: t.path,
        size: t.sizeBytes,
        durationSec: sec,
        sampleRate: t.sampleRate > 0 ? t.sampleRate : null,
        bitDepth: t.bitsPerSample > 0 ? t.bitsPerSample : null);
  }

  /// Wat in [hits] een betere kopie is van [t]: hetzelfde nummer — dezelfde zeef als een wens
  /// ([kandidatenVoorWens]: titel, lengte ±6 s, lossless, stereo, één per uploader) — en duidelijk beter
  /// dan wat er ligt ([magOpwaarderen] tegen [eigenAlsKandidaat]).
  ///
  /// [verdacht]: wat er ligt heeft een muur in het spectrum ("vermoedelijk" of "afgekapt", zie
  /// `Bandbreedte`). Dan telt ook een kopie die op papier niet hoger staat — een echte 16/44,1 tegen een
  /// verdachte 24/48 — want pas na het binnenhalen kan de keuring zien of zij voorbij die muur doorloopt
  /// ([metMuurBewijs]). Hoogstens [kVerdachtKandidaten].
  static List<SoulseekFile> beterDanWatErLigt(Track t, List<SoulseekFile> hits, {bool verdacht = false}) {
    final eigen = eigenAlsKandidaat(t);
    if (eigen == null) return const [];
    if (verdacht) return kandidatenVoorWens(_wensVoor(t), hits).take(kVerdachtKandidaten).toList();
    return [
      for (final k in kandidatenVoorWens(_wensVoor(t), hits))
        if (magOpwaarderen(k, eigen, t.duration?.inSeconds)) k
    ];
  }

  /// Zoveel kandidaten hoogstens voor een verdacht bestand — elke verliezer gaat naar `_dubbel`.
  static const kVerdachtKandidaten = 6;

  static LosslessWant _wensVoor(Track t) => LosslessWant(
      artist: t.artist,
      title: t.title,
      album: t.album,
      authority: TrackTags(
          title: t.title, artist: t.artist, album: t.album, trackNo: t.trackNo, seconds: t.duration?.inSeconds));

  /// Hoe lang [_naLandenHires] wacht op het volgende nummer van hetzelfde album: een album komt nummer voor nummer
  /// binnen, en het hele album is één zoekopdracht. Ook bij één nummer: dan heeft de bibliotheek het intussen gelezen.
  static const kNaLandenAdem = Duration(seconds: 90);

  /// Een geland pad als [Track] uit de bibliotheek, en het gezag dat na het vervangen in het bestand komt. Gezet door
  /// main op de pc; null: geen 24bit-zoektocht na het landen.
  Track? Function(String pad)? trackVoorPad;
  TrackTags Function(Track t)? gezagVoor;

  final Map<String, ({Set<String> paden, String album})> _naLanden = {};
  final Map<String, Timer> _naLandenKlok = {};

  /// ▶ of een download is binnen ([pad], gekozen uit [van]): is dat 16 bit of minder, dan zoekt de app over
  /// [kNaLandenAdem] op de achtergrond "<artiest> <titel> 24bit", of voor een album één keer "<artiest> <album> 24bit"
  /// (Saber, 24-10-2026: "na het landen"). ▶ en downloaden worden er zo niet trager door: als eigen zoekopdracht kost
  /// "24bit" ±8 s, en meegestuurd met de gewone leverde het bijna niets op. Wat jij zelf koos, komt hier niet langs
  /// (`finish` stopt bij een vaste keuze), en vervangen doet alleen wat bewezen beter is, nooit vinyl.
  void _naLandenHires(String? pad, TrackTags? gezag, SoulseekFile van) {
    if (pad == null || trackVoorPad == null) return;
    // Koos je cd of vinyl voor dit nummer, dan zoekt de app vanzelf geen 24 bit (kopiesoort.dart).
    final keuze = gekozenSoort(pad);
    if (keuze != null && keuze != Kopiesoort.studio) return;
    if ((van.bitDepth ?? 0) > 16 || (van.sampleRate ?? 0) > 48000) return;
    final album = gezag?.album.trim() ?? '';
    final artiest = (gezag?.albumArtist?.trim().isNotEmpty ?? false) ? gezag!.albumArtist!.trim() : gezag?.artist.trim() ?? '';
    final sleutel = album.isEmpty ? 'los|$pad' : '${normKey(artiest)}|${normKey(album)}';
    (_naLanden[sleutel] ??= (paden: <String>{}, album: album)).paden.add(pad);
    _naLandenKlok[sleutel]?.cancel();
    _naLandenKlok[sleutel] = Timer(kNaLandenAdem, () => unawaited(_zoekHiresNaLanden(sleutel)));
  }

  Future<void> _zoekHiresNaLanden(String sleutel) async {
    _naLandenKlok.remove(sleutel);
    final g = _naLanden.remove(sleutel);
    final vind = trackVoorPad;
    if (g == null || vind == null) return;
    final nummers = [for (final p in g.paden) if (vind(p) case final t?) t];
    if (nummers.isEmpty) return;
    _log.line(nummers.length == 1
        ? '"${nummers.single.artist} — ${nummers.single.title}": na het landen 24bit zoeken'
        : '"${nummers.first.artist} — ${g.album}": na het landen 24bit zoeken voor ${nummers.length} nummers');
    try {
      await zoekBeterVoor(nummers, album: nummers.length > 1 ? g.album : null, gezag: gezagVoor, alleenHires: true);
    } catch (_) {/* een volgende keer; de TIDAL-ronde komt er ook nog langs */}
  }

  /// Een betere kopie zoeken voor nummers die al in je bibliotheek staan — op jouw vraag (de knop "Zoek
  /// hi-res" op een album) of bij een 👍 op een nummer dat de radio haalde (Saber, 20-10-2026: "alleen
  /// als ik het vraag", en voor de radio "bij nummers die ik beslis om bij te houden").
  ///
  /// **Eén zoekopdracht voor een heel album** ([album] en meer dan één nummer): "artiest album" geeft de
  /// albummappen, ook de hi-res-rips, en elk nummer wordt daarin op titel en lengte teruggevonden — één
  /// vraag aan Soulseek in plaats van twaalf. Anders per nummer.
  ///
  /// Daarna de gewone jacht ([_queueUpgrade]): een vingerafdruk tegen jouw bestand (dezelfde opname?), de
  /// keuring beslist (alleen bewezen beter vervangt), wat verliest gaat opzij, en een spelend nummer wordt
  /// pas vervangen als het niet meer speelt. Een zelf gekozen bestand ([isVasteKeuze]) blijft met rust.
  ///
  /// **Ook bij TIDAL** ([tidalNu]; Saber, 24-10-2026: "als er een beter versie kwaliteit te vinden is op tidal, moet
  /// de app deze gebruiken"): dezelfde nummers gaan meteen naar de TIDAL-ronde (tidal_beter.dart), die ze één voor
  /// één nakijkt — ook als Soulseek er niet is.
  /// Geeft terug voor hoeveel nummers er een jacht begon (bij Soulseek, bij TIDAL of bij allebei).
  ///
  /// [alleenHires]: na het landen ([_naLandenHires]) — alleen "<vraag> 24bit", zonder terugval, en niet bij TIDAL (de
  /// TIDAL-ronde komt er zelf langs). De gewone vraag ging bij het downloaden al uit.
  Future<int> zoekBeterVoor(List<Track> nummers,
      {String? album, TrackTags Function(Track)? gezag, bool alleenHires = false}) async {
    final te = [
      for (final t in nummers)
        if (t.artist.trim().isNotEmpty && t.title.trim().isNotEmpty && !isVasteKeuze(t.path)) t
    ];
    if (te.isEmpty) return 0;
    final begonnen = <String>{if (!alleenHires) ...?tidalNu?.call(te)};
    // "Zoek hi-res" op een plaat: ook de torrents, op de achtergrond (Saber, 25-10-2026: "ook via torrents moet worden
    // gezocht, wel losse tracks") — zie [_zoekHiresInTorrents].
    if (!alleenHires && (album?.trim() ?? '').isNotEmpty) unawaited(_zoekHiresInTorrents(te, album!.trim(), gezag));
    if (!soulseek.available) return begonnen.length;
    // Gewoon: de vraag, met "24bit" als eigen zoekopdracht erachter. Na het landen: alleen die tweede.
    Future<List<SoulseekFile>> zoek(String vraag) => alleenHires
        ? (extraVragen(vraag, kHiresZoekwoorden).isEmpty
            ? Future.value(const <SoulseekFile>[])
            : soulseek.search(extraVragen(vraag, kHiresZoekwoorden).first, achtergrond: true, terugval: false))
        : soulseek.search(vraag, achtergrond: true, extra: kHiresZoekwoorden);
    List<SoulseekFile>? albumHits;
    final albumNaam = album?.trim() ?? '';
    if (albumNaam.isNotEmpty && te.length > 1) {
      try {
        albumHits = await zoek(zoekvraagVoorAlbum(te.first.artist, albumNaam));
      } catch (_) {
        return begonnen.length;
      }
      _log.line('"${te.first.artist} — $albumNaam": betere kwaliteit zoeken — ${albumHits.length} treffers '
          'voor ${te.length} nummers');
    }
    for (final t in te) {
      final naam = '${t.artist} — ${t.title}';
      List<SoulseekFile> hits;
      if (albumHits != null) {
        hits = albumHits;
      } else {
        try {
          hits = await zoek(zoekvraagVoorNummer(t.title, artist: t.artist, album: t.album));
        } catch (_) {
          continue;
        }
      }
      // Een muur in het spectrum: dan ook echte cd-kopieën proberen — zie [beterDanWatErLigt].
      final o = gemeten(t.path);
      final verdacht = o != null && (o.band == Bandbreedte.vermoedelijk || o.band == Bandbreedte.afgekapt);
      // Koos je zelf een soort voor dit nummer (kopiesoort.dart), dan alleen kandidaten die die soort kunnen zijn.
      final keuze = gekozenSoort(t.path);
      final beter = [
        for (final k in beterDanWatErLigt(t, hits, verdacht: verdacht))
          if (keuze == null ||
              kanSoortZijn(keuze, bronpad: k.filename, bits: k.bitDepth ?? 0, hz: k.sampleRate ?? 0) != false)
            k
      ];
      if (beter.isEmpty) {
        _log.line('"$naam": geen betere kopie dan wat je hebt');
        continue;
      }
      if (verdacht) {
        _log.line('"$naam": verdacht (muur op ${((o.afkapHz ?? 0) / 1000).toStringAsFixed(1)} kHz) — ook echte '
            'cd-kopieën proberen; de keuring meet of ze voorbij die muur doorlopen');
      }
      _log.line('"$naam": ${beter.length} betere kandidaten, de beste ${beter.first.username} — '
          '${baseName(beter.first.filename)}');
      final job = DownloadJob(naam)
        ..authority = gezag?.call(t) ??
            TrackTags(
                title: t.title,
                artist: t.artist,
                album: t.album,
                trackNo: t.trackNo,
                year: t.year,
                seconds: t.duration?.inSeconds);
      _queueUpgrade(beter, job, speeltPad: t.path, parkeerAltijd: true, blijfZoeken: verdacht);
      begonnen.add(t.path);
    }
    return begonnen.length;
  }

  /// De TIDAL-ronde op jouw vraag ([TidalBeterRonde.nu]); gezet door main.dart op de pc met tidaler. Geeft de paden
  /// terug die TIDAL gaat nakijken.
  Set<String> Function(List<Track> nummers)? tidalNu;

  // ── Studio, cd of vinyl op jouw vraag (kopiesoort.dart, soortjacht.dart; Saber, 25-10-2026) ───────────────────

  /// De staande vragen; gezet door main.dart op de pc (samen met [twijfel]). Null: hier wordt niets gevraagd.
  Soortvragen? soortvragen;

  /// Een korte melding voor op het scherm ("cd klaar: …", "nog geen …"); main.dart toont hem.
  final ValueNotifier<String?> klaarMelding = ValueNotifier<String?>(null);

  /// Ook twee keer dezelfde zin is twee meldingen (een ValueNotifier meldt alleen een verandering).
  void _meldKlaar(String zin) {
    klaarMelding.value = null;
    klaarMelding.value = zin;
  }

  /// Nummers waarvoor nu een ronde loopt: twee keer vragen is één ronde.
  final Set<String> _soortBezig = {};
  Timer? _soortKlok;

  static String _soortSleutel(String pad) => pad.replaceAll('\\', '/').toLowerCase();

  /// "Download in studio-kwaliteit / cd-kwaliteit / vinyl" voor [nummers]. Niets wordt vervangen: wat de jacht vindt,
  /// staat klaar in [twijfelMap] (label "cd klaar") tot je luistert en kiest. Vindt hij niets, dan blijft de vraag
  /// staan en zoekt hij later opnieuw ([soortvraagWacht]). Geeft de zin voor op het scherm.
  Future<String> vraagSoort(List<Track> nummers, Kopiesoort soort,
      {String? album, TrackTags Function(Track)? gezag}) async {
    final vragen = soortvragen;
    final lijst = twijfel;
    if (vragen == null || lijst == null) return 'Dit kan alleen op de pc';
    final te = [for (final t in nummers) if (t.artist.trim().isNotEmpty && t.title.trim().isNotEmpty) t];
    if (te.isEmpty) return 'Geen nummer om voor te zoeken';
    final nu = DateTime.now().millisecondsSinceEpoch;
    final nieuw = <Soortvraag>[];
    var klaar = 0;
    for (final t in te) {
      if (lijst.van(t.path)?.soort == soort) {
        klaar++;
        continue;
      }
      final v = Soortvraag(
        pad: t.path,
        soort: soort,
        artiest: t.artist,
        titel: t.title,
        album: t.album,
        seconden: t.duration?.inSeconds,
        sindsMs: nu,
        gezag: (gezag?.call(t) ??
                TrackTags(
                    title: t.title,
                    artist: t.artist,
                    album: t.album,
                    trackNo: t.trackNo,
                    year: t.year,
                    seconds: t.duration?.inSeconds))
            .toJson(),
      );
      vragen.zet(v);
      nieuw.add(v);
    }
    await vragen.bewaar();
    _log.line(nieuw.length == 1
        ? '"${nieuw.single.artiest} — ${nieuw.single.titel}": ${soort.voluit} gevraagd'
        : '${nieuw.length} nummers${album == null ? '' : ' van "$album"'}: ${soort.voluit} gevraagd');
    if (nieuw.isNotEmpty) unawaited(_soortRonde(nieuw, album: nieuw.length > 1 ? album : null));
    _planSoortKlok();
    if (nieuw.isEmpty) return klaar == 1 ? 'Er staat al een ${soort.naam}-kopie klaar' : 'Er staan al ${soort.naam}-kopieën klaar';
    final wat = nieuw.length == 1 ? '"${nieuw.single.titel}"' : '${nieuw.length} nummers';
    return 'Zoekt ${soort.voluit} voor $wat. Vindt hij er een, dan staat er "${soort.naam} klaar" bij het nummer — '
        'je vervangt pas als jij kiest.';
  }

  /// De vraag voor [pad] intrekken. Een kopie die al klaarstaat, blijft staan tot je kiest.
  Future<String> trekSoortvraagIn(String pad) async {
    final v = soortvragen?.verwijder(pad);
    if (v == null) return 'Er liep geen vraag voor dit nummer';
    await soortvragen!.bewaar();
    _log.line('"${v.artiest} — ${v.titel}": vraag om ${v.soort.voluit} ingetrokken');
    return 'Gestopt met zoeken naar ${v.soort.voluit}';
  }

  /// Elke tien minuten: de vragen die aan de beurt zijn ([Soortvraag.aanDeBeurt]), en die nog niets klaar hebben staan.
  void _planSoortKlok() {
    if (_soortKlok != null || soortvragen == null) return;
    _soortKlok = Timer.periodic(const Duration(minutes: 10), (_) => unawaited(soortvragenNakijken()));
  }

  /// De vragen die aan de beurt zijn opnieuw laten zoeken. Ook bij het opstarten (main.dart).
  Future<void> soortvragenNakijken() async {
    final vragen = soortvragen;
    final lijst = twijfel;
    if (vragen == null || lijst == null) return;
    _planSoortKlok();
    final nu = DateTime.now();
    final weg = [for (final v in vragen.alle) if (!File(v.pad).existsSync()) v];
    for (final v in weg) {
      vragen.verwijder(v.pad);
      _log.line('"${v.artiest} — ${v.titel}": vraag om ${v.soort.voluit} vervallen — het nummer staat er niet meer');
    }
    if (weg.isNotEmpty) await vragen.bewaar();
    final te = [
      for (final v in vragen.alle)
        if (lijst.van(v.pad)?.soort != v.soort && v.aanDeBeurt(nu) && !_soortBezig.contains(_soortSleutel(v.pad))) v
    ];
    if (te.isNotEmpty) await _soortRonde(te);
  }

  /// Eén ronde voor [te]: Soulseek (bij een plaat één zoekopdracht voor alle nummers), en anders TIDAL — cd en studio,
  /// geen vinyl — en dan torrents, per plaat ([_soortViaTorrents]). Wat de keuring doorstaat, staat klaar ([_zetKlaar]);
  /// de vraag blijft staan tot je kiest.
  Future<void> _soortRonde(List<Soortvraag> te, {String? album}) async {
    final vragen = soortvragen;
    if (vragen == null) return;
    final open = [for (final v in te) if (_soortBezig.add(_soortSleutel(v.pad))) v];
    if (open.isEmpty) return;
    final nietGevonden = <String>[];
    try {
      List<SoulseekFile>? albumHits;
      final plaat = album?.trim() ?? '';
      if (soulseek.available && plaat.isNotEmpty && open.length > 1) {
        try {
          albumHits = await soulseek.search(zoekvraagVoorAlbum(open.first.artiest, plaat),
              achtergrond: true, extra: zoekwoordenVoorSoort(open.first.soort));
          _log.line('"${open.first.artiest} — $plaat": ${open.first.soort.voluit} zoeken — ${albumHits.length} treffers '
              'voor ${open.length} nummers');
        } catch (_) {/* dan per nummer */}
      }
      final gedaan = <Soortvraag>[], nogNiet = <Soortvraag>[];
      for (final v in open) {
        if (!identical(vragen.van(v.pad), v)) continue; // ingetrokken of opnieuw gevraagd
        gedaan.add(v);
        var klaar = false;
        if (soulseek.available) {
          var hits = albumHits;
          if (hits == null) {
            try {
              hits = await soulseek.search(zoekvraagVoorNummer(v.titel, artist: v.artiest),
                  achtergrond: true, extra: zoekwoordenVoorSoort(v.soort));
            } catch (_) {
              hits = const [];
            }
          }
          final kandidaten = _soortKandidaten(v, hits);
          _log.line('"${v.artiest} — ${v.titel}": ${kandidaten.length} kandidaten voor ${v.soort.voluit}'
              '${kandidaten.isEmpty ? '' : ', de eerste ${kandidaten.first.username} — ${baseName(kandidaten.first.filename)}'}');
          if (kandidaten.isNotEmpty) klaar = await _soortVanSoulseek(v, kandidaten);
        }
        if (!klaar && identical(vragen.van(v.pad), v)) klaar = await _soortViaTidal(v);
        if (!klaar) nogNiet.add(v);
      }
      // Torrents als derde bron: per plaat, dus pas als elk nummer bij Soulseek en TIDAL langs is geweest.
      final uitTorrents = nogNiet.isEmpty ? const <Soortvraag>{} : await _soortViaTorrents(nogNiet);
      for (final v in gedaan) {
        v.rondes++;
        v.laatsteMs = DateTime.now().millisecondsSinceEpoch;
        if (nogNiet.contains(v) && !uitTorrents.contains(v)) {
          if (v.rondes == 1) nietGevonden.add(v.titel);
          _log.line('"${v.artiest} — ${v.titel}": nog geen ${v.soort.voluit} — opnieuw over '
              '${duurTekst(soortvraagWacht(v.rondes))}');
        }
      }
      await vragen.bewaar();
    } finally {
      for (final v in open) {
        _soortBezig.remove(_soortSleutel(v.pad));
      }
    }
    if (nietGevonden.isNotEmpty) {
      final s = open.first.soort;
      _meldKlaar(nietGevonden.length == 1
          ? 'Nog geen ${s.voluit} voor "${nietGevonden.single}" — de app blijft zoeken'
          : 'Nog geen ${s.voluit} voor ${nietGevonden.length} nummers — de app blijft zoeken');
    }
  }

  /// Wat in [hits] een kopie van de gevraagde soort kan zijn: dezelfde zeef als een wens ([kandidatenVoorWens]: titel,
  /// lengte, verliesvrij, stereo, één per uploader) — bij vinyl met een ruimere lengte ([kVinylLengteSpeling]) — en dan
  /// [kandidatenVoorSoort]: de soort, niet je eigen bestand, niet wat je weggooide.
  List<SoulseekFile> _soortKandidaten(Soortvraag v, List<SoulseekFile> hits) {
    final vinyl = v.soort == Kopiesoort.vinyl;
    final w = LosslessWant(
        artist: v.artiest,
        title: v.titel,
        album: v.album,
        authority: TrackTags(
            title: v.titel, artist: v.artiest, album: v.album, trackNo: 0, seconds: vinyl ? null : v.seconden));
    // Alleen wat de app na het halen kan lezen: FLAC, en WAV (wordt FLAC). Een AIFF zegt zijn diepte niet aan
    // readFlacTags, en werd na het halen alsnog afgekeurd (Digital Love, 25-10-2026: de eerste kandidaat).
    var zeef = [
      for (final f in kandidatenVoorWens(w, hits))
        if (const {'flac', 'wav'}.contains(soortVan(f.filename))) f
    ];
    final sec = v.seconden;
    if (vinyl && sec != null) {
      zeef = [for (final f in zeef) if (f.durationSec == null || (f.durationSec! - sec).abs() <= kVinylLengteSpeling) f];
    }
    final eigen = File(v.pad);
    return kandidatenVoorSoort(v.soort, zeef,
            eigenGrootte: eigen.existsSync() ? eigen.lengthSync() : 0,
            afgewezen: twijfel?.afgewezenGroottes(v.pad) ?? const {})
        .take(kSoortKandidaten)
        .toList();
  }

  Future<bool> _soortVanSoulseek(Soortvraag v, List<SoulseekFile> kandidaten) async {
    final job = DownloadJob('${v.artiest} — ${v.titel}');
    final deadline = DateTime.now().add(_upgradeBudget);
    var klaar = false;
    try {
      await soulseek.withSession((session) async {
        for (final f in kandidaten) {
          if (!identical(soortvragen?.van(v.pad), v)) return;
          final left = deadline.difference(DateTime.now());
          if (left <= const Duration(seconds: 30)) return;
          final t0 = DateTime.now();
          SlskResult res;
          try {
            // Zoals een wens: niet achteraan een rij van duizenden aanschuiven (Digital Love, 25-10-2026: plaats 7360
            // hield de hele ronde vast), en per uploader een begrensde wachttijd.
            res = await _rawTransfer(session, f, job, () {},
                waitInQueue: true,
                maxWait: left < _maxWachtPerPeer ? left : _maxWachtPerPeer,
                maxPlaats: _maxWachtrijPlaats);
          } catch (_) {
            continue;
          }
          _log.line('   ${f.username}: ${_uitkomst(res)}  na ${_kort(DateTime.now().difference(t0))}');
          if (res is! SlskDone) continue;
          if (await _keurVoorSoort(v, File(res.path), 'Soulseek ${f.username}', f.filename)) {
            klaar = true;
            return;
          }
        }
      });
    } catch (_) {/* geen sessie, geen net: de vraag blijft staan */}
    return klaar;
  }

  /// TIDAL voor cd (LOSSLESS, 16/44,1) of studio (HIRES); nooit vinyl. Dezelfde keuring als van Soulseek.
  Future<bool> _soortViaTidal(Soortvraag v) async {
    if (v.soort == Kopiesoort.vinyl || Tidaler.pad == null) return false;
    final treffers = await zoekOpTidal(zoekvraagVoorNummer(v.titel, artist: v.artiest));
    if (treffers == null) return false;
    final ids = kiesTidalTreffers(treffers, artiest: v.artiest, titel: v.titel);
    for (final id in ids.take(2)) {
      if (!identical(soortvragen?.van(v.pad), v)) return false;
      final map = keuringsmapVoor('tidal-soort-$id');
      try {
        final r = await haalVanTidal(
            doel: 'track/$id', map: map.path, kwaliteit: v.soort == Kopiesoort.cd ? 'high' : 'max');
        if (r.fout != null) {
          _log.line('   TIDAL $id: mislukt: ${r.fout!.split('\n').last}');
          continue;
        }
        final binnen = <File>[];
        await for (final e in map.list(recursive: true, followLinks: false)) {
          if (e is File && isVerliesvrij(soortVan(e.path))) binnen.add(e);
        }
        if (binnen.length != 1) continue;
        if (await _keurVoorSoort(v, binnen.single, 'TIDAL $id', 'TIDAL $id')) return true;
      } catch (e) {
        _log.line('   TIDAL $id: $e');
      } finally {
        try {
          if (map.existsSync()) await map.delete(recursive: true);
        } catch (_) {/* de volgende start ruimt het op */}
        _geefKeuringsmapVrij(map);
      }
    }
    return false;
  }

  /// Torrents voor de vragen in [open] die na Soulseek en TIDAL niets klaar hebben (Saber, 25-10-2026: torrents als
  /// derde bron). Per plaat één zoektocht ([albumZoekvraag]); welke torrents: [torrentsVoorSoort], hoogstens
  /// [kTorrentHiresHoogstens] die TorBox al heeft en [kTorrentHiresNietKlaar] die hij nog moet halen. Per nummer één
  /// bestand (FLAC of WAV, niet je eigen bestand, niet wat je weggooide) in een eigen keuringsmap, en dan dezelfde
  /// keuring als van Soulseek en TIDAL ([_keurVoorSoort]). Zonder plaat geen torrent. Geeft terug wat nu klaarstaat.
  Future<Set<Soortvraag>> _soortViaTorrents(List<Soortvraag> open) async {
    final klaar = <Soortvraag>{};
    if (!online.torboxReady) return klaar;
    final perPlaat = <String, List<Soortvraag>>{};
    for (final v in open) {
      if (v.album.trim().isEmpty) continue;
      perPlaat.putIfAbsent('${normKey(v.artiest)}|${normKey(v.album)}|${v.soort.naam}', () => []).add(v);
    }
    for (final groep in perPlaat.values) {
      final eerste = groep.first;
      final album = eerste.album.trim();
      final plaat = '"${eerste.artiest} — $album"';
      try {
        final treffers = await online.search(albumZoekvraag(eerste.artiest, album));
        final kandidaten = torrentsVoorSoort(treffers, eerste.soort, artiest: eerste.artiest, album: album);
        _log.line('$plaat: ${eerste.soort.voluit} in torrents — ${treffers.length} treffers, ${kandidaten.length} '
            'bruikbaar (${kandidaten.where((r) => r.cached).length} al bij TorBox)');
        final te = [...groep];
        var klaarGeprobeerd = 0, nietKlaarGeprobeerd = 0;
        for (final r in kandidaten) {
          te.removeWhere((v) => !identical(soortvragen?.van(v.pad), v)); // ingetrokken of opnieuw gevraagd
          if (te.isEmpty) break;
          if (r.cached ? klaarGeprobeerd >= kTorrentHiresHoogstens : nietKlaarGeprobeerd >= kTorrentHiresNietKlaar) continue;
          r.cached ? klaarGeprobeerd++ : nietKlaarGeprobeerd++;
          final TbTorrent item;
          try {
            final (id, hash) = await online._addOrFind(r);
            item = await online._pollReady(id, hash, patient: !r.cached);
          } catch (e) {
            _log.line('   torrent "${r.name}": ${r.cached ? "niet te openen" : "niet binnen"} bij TorBox — $e');
            continue;
          }
          if (indelingUitBestanden(item.files.map((f) => f.name)) != TorrentIndeling.losseNummers) {
            _log.line('   torrent "${r.name}": geen losse nummers — overgeslagen');
            continue;
          }
          final muziek = [for (final f in item.files) if (f.isAudio && const {'flac', 'wav'}.contains(soortVan(f.name))) f];
          for (final v in [...te]) {
            final eigen = File(v.pad);
            final eigenGrootte = eigen.existsSync() ? eigen.lengthSync() : 0;
            final afgewezen = twijfel?.afgewezenGroottes(v.pad) ?? const <int>{};
            final f = muziek
                .where((f) =>
                    f.size != eigenGrootte &&
                    !afgewezen.contains(f.size) &&
                    fileOffersTitle(v.titel, v.soort == Kopiesoort.vinyl ? null : v.seconden, v.artiest, f.name, null,
                        album: album))
                .firstOrNull;
            if (f == null) continue;
            final naam = '${v.artiest} — ${v.titel}';
            final bron = 'torrent "${r.name}"';
            final map = keuringsmapVoor('torrent-soort-${item.id}-${f.id}');
            try {
              final doel = await _haalTorrentBestand(item, f, map, bron, naam);
              if (await _keurVoorSoort(v, doel, bron, '${item.name}/${f.label}')) {
                te.remove(v);
                klaar.add(v);
              }
            } catch (e) {
              _log.line('   $bron: "$naam" mislukt — $e');
            } finally {
              try {
                if (map.existsSync()) await map.delete(recursive: true);
              } catch (_) {/* de volgende start ruimt het op */}
              _geefKeuringsmapVrij(map);
            }
          }
        }
      } catch (e) {
        _log.line('$plaat: ${eerste.soort.voluit} in torrents — $e');
      }
    }
    return klaar;
  }

  /// De keuring van een kandidaat voor een gevraagde soort. Niet "bewezen beter" (jij kiest de soort, ook als je huidige
  /// kopie op papier hoger staat), wel: echt, de gevraagde soort volgens zijn kop en zijn bron, ongeveer even lang, en
  /// dezelfde opname — vanaf [kTwijfelVanaf] mag hij klaarstaan, daaronder (live, remix) nooit. Waar als hij klaarstaat;
  /// anders is [staged] weggegooid.
  Future<bool> _keurVoorSoort(Soortvraag v, File staged, String bron, String bronpad) async {
    final naam = '${v.artiest} — ${v.titel}';
    Future<bool> weg(String waarom) async {
      _log.line('   $bron: $waarom — weggegooid, volgende kandidaat');
      await _discardStaged(staged.path);
      return false;
    }

    if (twijfel == null || !File(v.pad).existsSync()) return weg('het nummer staat er niet meer');
    final oordeel = await _meetEchtheid(staged);
    if (!magBlijven(oordeel)) return weg('betrapt (${waarom(oordeel!)})');
    final kop = readFlacTags(staged);
    final soort = kopiesoortVan(
        bronpad: bronpad,
        bits: kop?.bitsPerSample ?? 0,
        hz: kop?.sampleRate ?? 0,
        verliesvrij: isVerliesvrij(soortVan(staged.path)));
    if (soort != v.soort) return weg('geen ${v.soort.voluit} maar ${soort?.voluit ?? kwaliteitZin(kwaliteitVan(staged))}');
    final lengte = _duurVan(staged.path) ?? gedecodeerdeLengte(staged.path)?.round();
    final score = await _opnameScore(staged.path, v.pad);
    final nee = waaromNietKlaar(
        gevraagd: v.soort, binnen: soort, lengte: lengte, seconden: v.seconden, score: score, drempel: kTwijfelVanaf);
    if (nee != null) return weg(nee);
    final ok = await _zetKlaar(v, staged, bron, bronpad, score ?? 0);
    if (ok) {
      final let = misschienAndereOpname(score ?? 0) ? ' — misschien een andere opname' : '';
      _meldKlaar('${v.soort.naam} klaar: $naam$let');
    }
    return ok;
  }

  @visibleForTesting
  Future<bool> zetKlaarVoorToets(Soortvraag v, File staged, String bron, String bronpad, double score) =>
      _zetKlaar(v, staged, bron, bronpad, score);

  /// [staged] in [twijfelMap] zetten als de klaargezette kopie voor [v]. Eén kandidaat per nummer: wat er voor dit
  /// nummer wachtte (een twijfelgeval van de app, of een andere soort) gaat weg.
  Future<bool> _zetKlaar(Soortvraag v, File staged, String bron, String bronpad, double score) async {
    final lijst = twijfel!;
    final kop = readFlacTags(staged);
    final formaat = soortVan(staged.path).toUpperCase();
    final kwaliteit = kop == null || kop.bitsPerSample <= 0
        ? formaat
        : '$formaat ${kop.bitsPerSample}/${(kop.sampleRate / 1000).toStringAsFixed(1).replaceAll('.0', '').replaceAll('.', ',')}';
    final grootte = staged.lengthSync();
    final id = fnv1a('${v.pad.toLowerCase()}|${v.soort.naam}|${DateTime.now().microsecondsSinceEpoch}');
    final punt = staged.path.lastIndexOf('.');
    final ext = punt < 0 ? '' : staged.path.substring(punt).toLowerCase();
    final sep = Platform.pathSeparator;
    final doel = File('$_downloadsRoot$sep$twijfelMap$sep$id$ext');
    String bewaard;
    try {
      await doel.parent.create(recursive: true);
      bewaard = await moveWithRetry(staged, doel);
    } catch (e) {
      _log.line('   $bron: kopie niet klaar te zetten ($e) — weggegooid');
      await _discardStaged(staged.path);
      return false;
    }
    try {
      await staged.parent.delete();
    } catch (_) {/* de map houdt nog iets vast */}
    // De luidheid, voor een eerlijke A/B: B klinkt dan even luid als jouw kopie (abVersterking in luidheid.dart).
    Map<String, dynamic>? luid;
    try {
      final m = await meetLuidheid(bewaard, limiet: const Duration(minutes: 2));
      if (m.uitslag case Gemeten(:final meting)) luid = meting.toJson();
    } catch (_) {/* dan zoals A; de kopie staat er gewoon */}
    final oud = lijst.verwijder(v.pad);
    if (oud != null) {
      try {
        await File(oud.kandidaat).delete();
      } catch (_) {}
    }
    lijst.zet(Twijfelgeval(
      id: id,
      pad: v.pad,
      kandidaat: bewaard,
      bron: bron,
      score: score,
      kwaliteit: kwaliteit,
      ms: DateTime.now().millisecondsSinceEpoch,
      grootte: grootte,
      gezag: v.gezag,
      soort: v.soort,
      bronpad: bronpad,
      luid: luid,
    ));
    await lijst.bewaar();
    _log.line('"${v.artiest} — ${v.titel}": ${v.soort.naam.toUpperCase()} KLAAR — $bron ($kwaliteit, vingerafdruk '
        '${score.toStringAsFixed(2).replaceAll('.', ',')}): wacht tot je luistert en kiest');
    return true;
  }

  /// Queue a background hunt for a better copy of a track you can already play.
  ///
  /// [gezag]: de tags om na het vervangen te schrijven (▶ bergt op zonder jaar en schrijft daarna het
  /// gezag — zie `_haalVoorRadio`). [speeltPad]: vervang pas als dat niet meer speelt. [parkeerAltijd]:
  /// wat verliest gaat opzij, nooit weg — zoals bij de eerste landing van ▶.
  ///
  /// [blijfZoeken]: is een binnengehaalde kopie niet bewezen beter, dan de volgende proberen in plaats van te
  /// stoppen — voor een verdacht bestand, waar meerdere uploaders hetzelfde opgeblazen bestand delen.
  void _queueUpgrade(List<SoulseekFile> better, DownloadJob job,
      {TrackTags? gezag, String? speeltPad, bool parkeerAltijd = false, bool blijfZoeken = false}) {
    job.status = 'upgrading';
    job.detail = 'speelbaar · betere kwaliteit zoeken';
    notifyListeners();
    // Of hij meteen begint of achter een andere jacht staat, is een van de vier verklaringen voor
    // "hij kwam niet binnen" -- en de enige die je nooit op het scherm ziet.
    _log.line('"${job.name}": ${better.length} betere kandidaten, opwaarderen in de rij'
        ' (${_jachten.lopend} van $_maxParallelleJachten jachten bezig'
        '${_jachten.wachtend > 0 ? ", ${_jachten.wachtend} wachtend" : ""})');
    _jachten.voegToe(() =>
        _chaseUpgrade(better, job,
            gezag: gezag, speeltPad: speeltPad, parkeerAltijd: parkeerAltijd, blijfZoeken: blijfZoeken));
  }


  /// Chase a BETTER copy of a track that already landed.
  ///
  /// Bounded on purpose: you HAVE the track, so this must never cost you anything. It holds the
  /// shared session for its whole run — dipping out between peers would let the 120s idle close
  /// fire and make the next attempt a fresh LOGIN, which is what gets the account blocked — and
  /// deliberately takes no download slot, so a track you have nothing of never waits behind it.
  Future<void> _chaseUpgrade(List<SoulseekFile> better, DownloadJob job,
      {TrackTags? gezag, String? speeltPad, bool parkeerAltijd = false, bool blijfZoeken = false}) async {
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
            final bestaand = await _bereidVergelijkingVoor(staged, job.authority);
            var score = bestaand == null ? null : await _opnameScore(staged.path, bestaand);
            // Een vinylrip begint vaak verder van de eerste noot dan de cd: dan nog eens, met meer ruimte om te schuiven.
            if (isVinylRip(f.filename) && bestaand != null && score != null && score < maybeSameRecordingScore) {
              score = await _opnameScoreRuim(staged.path, bestaand) ?? score;
            }
            final opname = opnameOordeel(score);
            // Een andere versie dan wat je hebt (versies.dart): bewaren in plaats van weggooien of vervangen. Het nummer
            // opzij zetten alleen voor een kopie die ook bewezen beter is en binnen je eigen soortkeuze valt.
            var plan = bestaand != null && (opname == Opnameoordeel.zelfde || opname == Opnameoordeel.twijfel)
                ? versieplanVoor(staged, bestaand, f.filename)
                : null;
            if (plan != null &&
                plan.besluit == Versiebesluit.ankerOpzij &&
                (!firstIsBetter(staged, File(bestaand!)) || !magVanzelf(bestaand, plan.soort))) {
              plan = plan.als(Versiebesluit.nieuweVersie);
            }
            if (bestaand != null &&
                !(plan?.isVersie ?? false) &&
                !magVanzelf(bestaand, _soortVanBinnen(staged, f.filename))) {
              _log.line('   ${job.name}: je koos ${gekozenSoort(bestaand)?.voluit} voor dit nummer, en dit is een andere soort — '
                  'weggegooid');
              await _discardStaged(staged.path);
              continue;
            }
            // Klinkt bewezen beter, maar de vingerafdruk twijfelt: aanbieden in plaats van weggooien (twijfel.dart).
            if (bestaand != null &&
                opname == Opnameoordeel.twijfel &&
                (firstIsBetter(staged, File(bestaand)) || (plan?.isVersie ?? false)) &&
                await bewaarAlsTwijfel(staged, bestaand, score!, 'Soulseek ${f.username}', job.authority)) {
              continue;
            }
            if (bestaand != null && (opname == Opnameoordeel.andere || opname == Opnameoordeel.twijfel)) {
              _log.line('   ${job.name}: de betere kandidaat is een andere opname — weggegooid');
              await _discardStaged(staged.path);
              continue;
            }
            // Niet onder een spelend nummer door (▶): wachten tot het niet meer speelt.
            if (speeltPad != null && !await _wachtTotNietMeerSpeelt(speeltPad)) {
              _log.line('   ${job.name}: betere kopie klaar, maar het nummer speelde nog na '
                  '${kWachtOpStilte.inMinutes} min — weggegooid, de oude blijft');
              await _discardStaged(staged.path);
              settle('beste vrije kwaliteit behouden');
              return;
            }
            if (plan != null && plan.isVersie && opname == Opnameoordeel.zelfde) {
              final uitslag = await _bergOpAlsVersie(staged, plan, job.authority, 'Soulseek ${f.username}', inJacht: false);
              if (uitslag == _Wenskeuring.opgeborgen) {
                settle('kwaliteit verbeterd · ${f.username}');
                return;
              }
              // Bewaard als versie, of dezelfde versie als er al een is: de jacht op het nummer zelf gaat door.
              if (uitslag != null) continue;
            }
            // The SAME authority as the first landing. Without it the sweep would quietly undo the
            // numbering a quarter of an hour later, using whatever this new peer's tags happen to say.
            final uit = await placeFileDetailed(staged, _downloadsRoot,
                tags: job.authority, staatAl: mapVanBestaande, parkeerAltijd: parkeerAltijd);
            how = uit.how;
            if (how == Placement.moved && gezag != null) {
              try {
                await stampTags(File(uit.path), gezag);
              } catch (_) {/* het bestand staat goed; een mislukte tagschrijf maakt het niet stuk */}
            }
            if (how == Placement.moved) _noteerSoort(uit.path, f.filename);
            if (how == Placement.moved && bestaand != null) await _vergeetTwijfel(bestaand);
          } catch (_) {/* the scan still finds it wherever it landed */}
          if (how == Placement.duplicate) {
            if (blijfZoeken) {
              _log.line('   ${job.name}: ${f.username} niet bewezen beter dan wat je hebt — volgende');
              continue;
            }
            // Ook hier een regel: Steps, "5, 6, 7, 8" (26-10-2026) — de 24-bitkopie kwam binnen en verdween zonder woord.
            _log.line('   ${job.name}: ${f.username} niet bewezen beter dan wat je hebt — weggegooid, de vorige blijft');
            settle('had al de beste kwaliteit');
            return;
          }
          // In het logboek, en niet alleen op het scherm: zonder deze regel zag een geslaagde jacht er in
          // downloads.log uit als een die na de laatste "GELEVERD" was blijven hangen (Snoop Dogg —
          // Beautiful, 21-10-2026: vervangen om 17:59, en er stond niets).
          _log.line(how == Placement.moved
              ? '   ${job.name}: ${f.username} BEWEZEN BETER — vervangen, de vorige staat in _dubbel'
              : '   ${job.name}: ${f.username} binnen, maar niet als vervanger geplaatst ($how)');
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

  /// De kandidaten waar het voor deze wens nog zin heeft aan te kloppen.
  ///
  /// Drie zeven, en de laatste twee zijn nieuw:
  ///  - **lossless en stereo**, op de BELOFTE. Voor het binnenhalen valt er niets te meten; zie de
  ///    aantekening bij [_rankSlsk].
  ///  - **geen peer die ons niet kan bedienen** — geband of firewall, uit `w.refused`.
  ///  - **geen upload die de METING al betrapt heeft.** Niet de peer maar het BESTAND: dezelfde
  ///    vervalsing staat bij honderd peers, en wie er één deelt heeft er tien goede naast. Zelfde
  ///    vergelijking als [andereKopieDan] gebruikt.
  ///  - **één bestand per peer.** De top van een hi-res-eerst-ranglijst is precies waar een handvol
  ///    verzamelaars zit; zonder dit gaan alle pogingen naar dezelfde peer.
  /// Hoeveel een vervanger in LENGTE mag afwijken van wat er al ligt.
  ///
  /// GEMETEN op 08-09-2026, en dit is de reden dat deze regel bestaat. Van de 22 bestanden die de
  /// jacht die avond binnenhaalde landden er ELF als `(2)` naast het origineel in plaats van erop,
  /// en van de zes waar het origineel nog naast lag was het ELKE KEER een andere uitgave:
  ///
  ///     Whitney Houston — It's Not Right But It's Okay   3:33 tegen 4:52   79s
  ///     Natasha St-Pier — Tu trouveras                   3:42 tegen 4:59   77s
  ///     The Mackenzie — Arpegia (the love mix)           8:26 tegen 7:13   74s
  ///     Garou — Sous le vent                             4:38 tegen 3:31   67s
  ///     Janet Jackson — Miss You Much                    3:53 tegen 4:12   20s
  ///     Whigfield — Saturday Night (radio edit)          3:40 tegen 3:58   18s
  ///
  /// Radio-edits, single-versies, remixen. Zo'n bestand KAN het origineel niet vervangen — het is
  /// een andere opname — dus landt het ernaast, blijft de vervalsing staan, en heeft de
  /// bibliotheek er een dubbel bij. Precies het omgekeerde van wat de knop belooft.
  ///
  /// Zes seconden: twee ripjes van dezelfde plaat verschillen hooguit een tel of twee door een
  /// andere gapless-snit of wat stilte aan het eind, en de kleinste échte misser hierboven was
  /// achttien. Streng mogen zijn kost hier niets: er staan honderden kandidaten per wens klaar, en
  /// eentje te veel weigeren betekent alleen dat de volgende aan de beurt is.
  static const _duurSpeling = 6;

  /// Is dit dezelfde OPNAME, voor zover de lengte daar iets over zegt?
  ///
  /// **Onbekend is JA.** Lang niet elke peer meldt een duur, en een ontbrekende meting mag nooit
  /// een kandidaat afwijzen — zie [magBlijven] en [firstIsBetter], dezelfde regel. Wat er zo
  /// doorheen glipt wordt ná het binnenhalen alsnog aan het echte bestand gemeten.
  static bool zelfdeLengte(int? gewenst, int? gevonden) =>
      gewenst == null ||
      gevonden == null ||
      gewenst <= 0 ||
      gevonden <= 0 ||
      (gewenst - gevonden).abs() <= _duurSpeling;

  /// Eerst wat de officiële lengte heeft ([lengteKlopt]), dan de rest — en binnen elk van die twee de
  /// gewone rangorde van [_rankSlsk].
  ///
  /// Saber op 30-09-2026, bij Sam Smith — I'm Not The Only One (officieel 3:59, binnengekomen een
  /// live-opname van 3:54): *"de app moet leren om het nummer te downloaden het meest dichte met de
  /// officiele tijd van het nummer"*. Tot dan speelde de lengte in de volgorde geen enkele rol: een
  /// 24/48 van 3:54 scoorde hoger dan een 24/44,1 van 3:59, puur op bits.
  static Comparator<SoulseekFile> opLengteDanRang(int? officieel) => (a, b) {
        final la = lengteKlopt(officieel, a.durationSec), lb = lengteKlopt(officieel, b.durationSec);
        if (la != lb) return la ? -1 : 1;
        return _rankSlsk(a, b);
      };

  /// Een bak kandidaten in twee delen: eerst wat de officiële lengte heeft, dan de rest. Eén deel als
  /// de lengte onbekend is, of als alles (of niets) de lengte heeft — dan valt er niets te kiezen.
  ///
  /// Een race wint wie het eerst verstuurt, dus de voorkeur moet uit wat er meedoet komen, niet uit een
  /// sortering. Zie de race in [_soulseekBest].
  static List<List<SoulseekFile>> lengteDelen(List<SoulseekFile> bak, int? officieel) {
    if (officieel == null || officieel <= 0) return [bak];
    final juist = [for (final f in bak) if (lengteKlopt(officieel, f.durationSec)) f];
    if (juist.isEmpty || juist.length == bak.length) return [bak];
    return [juist, [for (final f in bak) if (!lengteKlopt(officieel, f.durationSec)) f]];
  }

  /// Mag [f] de kopie [van] opwaarderen? Duidelijk beter ([clearlyBetter]) — en nooit verder van de
  /// officiële lengte dan wat er ligt: een 24/96 live-opname van 3:54 is geen opwaardering van een
  /// 24/44,1 van 3:59. Heeft wat er ligt de lengte zelf niet, dan telt alleen de kwaliteit.
  ///
  /// **Ook een vinyl-rip** ([isVinylRip]), sinds 25-10-2026. Eerst niet (Saber, 24-10-2026: "alleen als ik kies"), maar:
  /// "ik mis wel heel veel goede kwaliteit liedjes door vinyl en lp weg te laten oor, laat ze toch maar door — LP,
  /// 24/96, 24/192, PBTHAL". De keuring na het halen (zelfde opname, bewezen beter) blijft; de lijsten die de app zelf
  /// afloopt, zetten vinyl wel achter een digitale kopie ([vinylAchteraan]).
  static bool magOpwaarderen(SoulseekFile f, SoulseekFile van, int? officieel) =>
      clearlyBetter(f, van) && (!lengteKlopt(officieel, van.durationSec) || lengteKlopt(officieel, f.durationSec));

  static List<SoulseekFile> kandidatenVoorWens(LosslessWant w, List<SoulseekFile> hits,
      {Set<String> rustendePeers = const {}}) {
    // **Ook de TITEL, en niet alleen de lengte.** Hier stond alleen de lengte (±6 s), en zo kwam de
    // live-opname van Sam Smith binnen: 3:54 tegen 3:59 viel erbinnen, en "(Live From The Royal Albert
    // Hall)" in de naam telde nergens. Bij een zoekladder die terugvalt op alleen de artiestnaam telde
    // zelfs élk ander nummer van die artiest van ongeveer dezelfde lengte. Nu dezelfde toets als
    // "Ontbrekende downloaden" ([fileOffersTitle]), mét de map ([mapVerraadtAndereVersie]).
    final titel = (w.authority?.title ?? w.title).trim();
    final artiest = (w.authority?.artist ?? w.artist).trim();
    final album = (w.authority?.album ?? w.album).trim();
    bool isDitNummer(SoulseekFile f) =>
        titel.isEmpty ||
        fileOffersTitle(titel, w.authority?.seconds, artiest, f.filename, f.durationSec,
            album: album.isEmpty ? null : album);
    List<SoulseekFile> zeef(bool metRust) => hits
        .where((f) => isLossless(f) && !isMultichannel(f))
        .where((f) => zelfdeLengte(w.authority?.seconds, f.durationSec))
        .where(isDitNummer)
        .where((f) => !w.refused.containsKey(f.username))
        .where((f) => !metRust || !rustendePeers.contains(f.username))
        .where((f) => !w.nep.any((n) =>
            zelfdeBestand(f.filename, f.size, f.durationSec, n.filename, n.size, n.durationSec)))
        .toList()
      ..sort(opLengteDanRang(w.authority?.seconds));
    // Een optimalisatie mag "een paar kandidaten" nooit in "geen enkele" veranderen. Blijft er na
    // het overslaan van de rustende peers niets over, dan tellen ze gewoon weer mee — beter een
    // kansloze poging dan een wens die stilvalt omdat de lijst op is.
    var bruikbaar = zeef(true);
    if (bruikbaar.isEmpty) bruikbaar = zeef(false);
    final perPeer = <String>{};
    // Vinyl mag (Saber, 25-10-2026: "laat ze toch maar door"), maar na elke digitale kopie: wie het eerst bewezen beter
    // is, wint, en een digitale hi-res is dezelfde uitgave als je cd.
    return [
      for (final f in vinylAchteraan(bruikbaar, (f) => f.filename))
        if (perPeer.add(f.username)) f,
    ];
  }

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

  /// DE DECODEERPROEF op een afgeronde overdracht, voordat iets anders het bestand te zien krijgt.
  ///
  /// Een kapot bestand wordt een mislukte poging ([SlskFail]), en dan probeert de race gewoon de
  /// volgende peer. Dit zit in [_cleanStaging], de enige doorgang waar élke Soulseek-overdracht
  /// langskomt — de gewone, de handmatige, het album, de jacht op iets beters, de wens en de radio —
  /// dus hier hoeft het maar één keer.
  ///
  /// Gemeten op 29-09-2026: Just Dance zegt in zijn kop 242,8 s en speelt er 192,9. Aan de kop was dat
  /// niet te zien; decoderen kost voor acht minuten 24/96 een paar tienden van een seconde. Niet te
  /// zeggen (geen ffmpeg) is nooit een reden om te weigeren.
  @visibleForTesting
  ///
  /// **[verwachtSeconden]: en is het wel het nummer van de goede lengte?** Een peer meldt zijn eigen
  /// lengte, en lang niet elke peer meldt er een; vóór het binnenhalen telt "onbekend" dus als goed.
  /// Hier ligt het bestand er, en de decodeerproef heeft het net tot het einde gelezen. Wijkt het meer
  /// dan [kLengteSpelingNaHalen] af van de officiële lengte, dan is het een andere uitvoering — een
  /// radio-edit, een live-opname, een extended mix — en dan is dit een mislukte poging, precies als
  /// een kapot bestand: de race gaat door met de volgende peer.
  ///
  /// **[gevraagd]: en is het de VERSIE die gevraagd werd?** Het bestand tegen het Deezer-fragment van die
  /// versie ([versiecontrole], zie `versiecontrole.dart`). Onder [kAndereVersieOnder] een mislukte poging,
  /// zoals een andere lengte: "Light Switch (Acoustic)" van de Sabrina-radio bleek de albumversie (0,642
  /// tegen het akoestische fragment, 0,945 tegen dat van het origineel — 21-10-2026). Geen oordeel is ja.
  static Future<SlskResult> keurOverdracht(SlskResult res,
      {void Function(String)? spoor, int? verwachtSeconden, ({String artiest, String titel})? gevraagd}) async {
    if (res is! SlskDone) return res;
    final h = await controleerHeel(res.path);
    final naam = res.path.split(Platform.pathSeparator).last;
    if (h != null && !h.heel) {
      spoor?.call('   kapot binnengekomen: $naam — ${h.reden}; weggegooid, volgende');
      return SlskFail('kapot bestand (${h.reden})');
    }
    if (verwachtSeconden != null && verwachtSeconden > 0) {
      final echt = gedecodeerdeLengte(res.path);
      if (echt != null && (echt - verwachtSeconden).abs() > kLengteSpelingNaHalen) {
        spoor?.call('   andere lengte binnengekomen: $naam — ${_mmss(echt)}, officieel '
            '${_mmss(verwachtSeconden)}; weggegooid, volgende');
        return SlskFail('andere uitvoering (${_mmss(echt)} in plaats van ${_mmss(verwachtSeconden)})');
      }
    }
    final vc = versiecontrole;
    if (vc != null && gevraagd != null && gevraagd.artiest.trim().isNotEmpty && gevraagd.titel.trim().isNotEmpty) {
      final score = await vc(res.path, artiest: gevraagd.artiest, titel: gevraagd.titel, seconden: verwachtSeconden);
      if (score != null) {
        final s = score.toStringAsFixed(2);
        if (score < kAndereVersieOnder) {
          spoor?.call('   andere versie binnengekomen: $naam — $s tegen het Deezer-fragment van '
              '"${gevraagd.titel}"; weggegooid, volgende');
          return SlskFail('andere versie (vingerafdruk $s tegen het Deezer-fragment)');
        }
        spoor?.call(score < kZelfdeVersieVanaf
            ? '   twijfel over de versie: $naam — $s tegen het Deezer-fragment; gehouden'
            : '   versie klopt: $naam — $s tegen het Deezer-fragment');
      }
    }
    // Een WAV wordt hier FLAC (Saber, 24-10-2026: "WAV halen, omzetten naar FLAC"): verliesvrij, en daarna kan de app
    // er tags en een hoes in schrijven. Hier, en niet later: alles na deze doorgang ziet zo alleen nog een FLAC.
    if (soortVan(res.path) == 'wav') {
      final flac = await (wavOmzetter ?? wavNaarFlac)(res.path);
      if (flac == null) {
        spoor?.call('   WAV niet om te zetten naar FLAC: $naam — weggegooid, volgende');
        return SlskFail('WAV niet om te zetten naar FLAC');
      }
      spoor?.call('   WAV omgezet naar FLAC: $naam');
      return SlskDone(flac);
    }
    return res;
  }

  /// Hoe [keurOverdracht] een WAV omzet; null = [wavNaarFlac]. Voor de toetsen.
  @visibleForTesting
  static Future<String?> Function(String wav)? wavOmzetter;

  /// Waar een nummer op een uitgave staat (jaar, nummer, schijf) — zie `deezerPlekOpAlbum` en
  /// [veldenNaHaal]. Gezet bij het opstarten van de pc; null (een toets, een toestel): niet opzoeken.
  static Future<({int? jaar, int nummer, int schijf})?> Function(String artiest, String titel, String album)?
      plekOpAlbum;

  /// De oorspronkelijke uitgave van een nummer dat zonder album binnenkomt (de radio, of ▶ met een verzamelaar) —
  /// zie `origineleUitgaveVan` in enrichment.dart. Gezet bij het opstarten van de pc; null: niet opzoeken.
  static Future<({String album, int? jaar})?> Function(String artiest, String titel, int? seconden)?
      origineleUitgave;

  /// Klopt de albumtag van de uploader honderd procent — zie `uploaderAlbumKlopt` in enrichment.dart. Gezet bij het
  /// opstarten van de pc; null (een toets, een toestel): niet nakijken, dan blijft hij weg zoals voorheen.
  static Future<({String album, int? jaar})?> Function(String artiest, String titel, String album)? albumVanUploader;

  /// [gezag] zonder album (het opzoeken vond niets): dan het album dat de uploader in [pad] zette, als het honderd
  /// procent klopt ([albumVanUploader]) — anders [gezag] zoals het was, en dan gaat zijn tag weg zoals voorheen. Saber,
  /// 23-10-2026: "Ja als het 100 procent klopt ja."
  @visibleForTesting
  Future<TrackTags> metAlbumVanUploader(
      TrackTags gezag, String pad, String artiest, String titel, int? jaar, int? seconden) async {
    final f = albumVanUploader;
    if (f == null || gezag.album.isNotEmpty) return gezag;
    final eigen = (readTags(File(pad))?.album ?? '').trim();
    if (eigen.isEmpty) return gezag;
    final klopt = await f(artiest, titel, eigen)
        .timeout(const Duration(seconds: 10), onTimeout: () => null)
        .then<({String album, int? jaar})?>((o) => o, onError: (Object _) => null);
    if (klopt == null) {
      _log.line('radio "$artiest — $titel": album van de uploader "$eigen" niet zeker — weg');
      return gezag;
    }
    final j = klopt.jaar;
    _log.line('radio "$artiest — $titel": album van de uploader klopt — "${klopt.album}"${j == null ? '' : ' ($j)'}');
    return gezagVoorHaal(
        artiest: artiest,
        titel: titel,
        album: klopt.album,
        jaar: j == null ? jaar : (jaar == null || j < jaar ? j : jaar),
        seconden: seconden);
  }

  /// Zodra bekend is op welke plaat een nummer komt dat nu binnenkomt (de radio, ▶): de hoezen van die plaat alvast
  /// ophalen — `FactsWarmer.alvast`. Gezet bij het opstarten van de pc; null (een toets, een toestel): niets. Saber,
  /// 23-10-2026: *"vanaf het moment dat het liedje begint te downloaden moet die hoes, cd afbeelding en achterkant al
  /// beginnen"*.
  static void Function(String artiest, String album, String titel, int? seconden)? albumBekend;

  /// [origineel] (de oorspronkelijke uitgave die gezocht wordt) of [album] (al bekend, en geen single van dit nummer):
  /// meld [albumBekend] zodra er een album is.
  @visibleForTesting
  static void meldAlbum(String artiest, String titel, int? seconden,
      {String album = '', Future<({String album, int? jaar})?>? origineel}) {
    final f = albumBekend;
    if (f == null) return;
    if (album.trim().isNotEmpty) {
      f(artiest, album, titel, seconden);
      return;
    }
    unawaited(origineel?.then((o) {
      if (o != null) f(artiest, o.album, titel, seconden);
    }, onError: (Object _) {}));
  }

  /// Na tags die pas later in een bestand kwamen ([_schrijfRadioTags]): de bibliotheek leest het opnieuw. Gezet bij het
  /// opstarten van de pc (`LibraryStore.voegBestandToe`); null (een toets, een toestel): niets.
  static Future<void> Function(String pad)? naLateTags;

  /// Wie de tags schrijft — [writeTagFields]; een toets zet er een nep in.
  @visibleForTesting
  static Future<bool> Function(File f, Map<String, String?> velden, {void Function(String)? waarom}) tagSchrijver =
      writeTagFields;

  /// Hoe vaak en met welke tussenpoos [_schrijfRadioTags] het opnieuw probeert: twintig keer om de dertig seconden,
  /// tien minuten — langer dan bijna elk nummer duurt.
  @visibleForTesting
  static Duration tagsLaterTussen = const Duration(seconds: 30);
  static const kTagsLaterPogingen = 20;

  /// De tags van een radiohaal in [pad]: nu, en lukt dat niet, dan later nog eens — om de [tagsLaterTussen], hoogstens
  /// [kTagsLaterPogingen] keer, zolang het bestand er staat. Daarna leest de bibliotheek het opnieuw ([naLateTags]).
  /// Klaar (true) als het meteen lukte.
  ///
  /// **Waarom (radio vanaf Luka, 23-10-2026).** Bij Luka en Cathedral Song vond de app het juiste album, maar bleef de
  /// tag van de uploader staan. Dat waren de nummers die al speelden terwijl ze binnenkwamen: Windows laat een bestand
  /// dat open staat niet vervangen, het schrijven mislukte stil, en niemand probeerde het opnieuw.
  @visibleForTesting
  Future<bool> schrijfRadioTags(String pad, Map<String, String?> velden, String wie) async {
    String? reden;
    if (await tagSchrijver(File(pad), velden, waarom: (w) => reden = w)) return true;
    _log.line('radio "$wie": tags nog niet geschreven (${reden ?? 'onbekend'}) — straks opnieuw');
    unawaited(() async {
      for (var i = 1; i <= kTagsLaterPogingen; i++) {
        await Future<void>.delayed(tagsLaterTussen);
        if (!File(pad).existsSync()) return;
        String? waarom;
        if (await tagSchrijver(File(pad), velden, waarom: (w) => waarom = w)) {
          _log.line('radio "$wie": tags alsnog geschreven (poging $i)');
          try {
            await naLateTags?.call(pad);
          } catch (_) {/* de tags staan in het bestand; de volgende scan ziet ze */}
          return;
        }
        if (i == kTagsLaterPogingen) {
          _log.line('radio "$wie": tags niet geschreven na $i pogingen (${waarom ?? 'onbekend'})');
        }
      }
    }());
    return false;
  }

  /// De versiecontrole van de pc — zie [keurOverdracht] en `versiecontrole.dart`. Gezet bij het opstarten
  /// van de pc; null (een toets, een toestel): niet controleren.
  static Future<double?> Function(String pad, {required String artiest, required String titel, int? seconden})?
      versiecontrole;

  /// Zo ver mag een binnengekomen bestand van de officiële lengte afwijken. Dezelfde twaalf seconden als
  /// vóór het binnenhalen ([fileOffersTitle]): twee persingen van één plaat verschillen soms zeven, acht
  /// tellen (gemeten op 30-09-2026 over Sabers bibliotheek: 117 nummers wijken 4 tot 10 s af van hun
  /// uitgave), en een terecht bestand weigeren omdat de fade-out langer is, is geen winst.
  static const kLengteSpelingNaHalen = 12;

  /// "3:59" voor 239 seconden.
  static String _mmss(num seconden) {
    final s = seconden.round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// A peer that never delivered leaves an empty staging folder behind; drop it so `_inkomend`
  /// doesn't slowly fill with the name of every uploader we ever tried. Non-recursive on purpose:
  /// a folder that still holds a partial file is left alone.
  Future<SlskResult> _cleanStaging(Directory dir, File dest, Future<SlskResult> transfer,
      {int? verwachtSeconden, ({String artiest, String titel})? gevraagd}) async {
    final res = await keurOverdracht(await transfer,
        spoor: _log.line, verwachtSeconden: verwachtSeconden, gevraagd: gevraagd);
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

  /// Waar [_rawTransfer] dit bestand neerzet: `_inkomend/<peer>/<naam>`.
  File _bestemming(SoulseekFile file) => File('$_downloadsRoot${Platform.pathSeparator}_inkomend'
      '${Platform.pathSeparator}${_sanitize(file.username)}${Platform.pathSeparator}${_sanitize(file.displayName)}');

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
      int? maxPlaats,
      bool Function()? claim}) async {
    // Land in a staging folder; placeFile() moves it into Albums/Singles/Compilaties after.
    // Per-PEER subfolder: candidates for the same track share a display name, so a slow attempt
    // that is still winding down can never write into the file the next attempt just opened.
    final dest = _bestemming(file);
    final dir = dest.parent;
    await dir.create(recursive: true);
    var settled = claim == null; // no race → this attempt owns the UI from the start
    var mine = claim == null;
    // Alleen bij een VERANDERING, want een peer herhaalt zijn plaats. Zonder deze regel is een
    // download die in een wachtrij staat onzichtbaar in het logboek tot hij eindigt -- en dat is juist
    // het geval dat we willen kunnen nakijken. Bleek bij het uittesten van het logboek zelf.
    var laatstePlaats = -1;
    // Een eigen stopknop, alleen als er een plaatsgrens is en de aanroeper er niet al een heeft.
    // Zie [_maxWachtrijPlaats]: acht minuten wachten op plaats 26549 is de klok verzetten.
    final plaatsStop = maxPlaats != null && cancel == null ? SlskCancel() : null;
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
      if (maxPlaats != null && q.place > maxPlaats && plaatsStop != null && !plaatsStop.isCancelled) {
        _log.line('   ${file.username}: plaats ${q.place} is kansloos — niet op wachten, volgende');
        plaatsStop.cancel();
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
    }, waitInQueue: waitInQueue, maxWait: maxWait, cancel: cancel ?? plaatsStop),
        // De officiële lengte van wat deze download zoekt — niet bij jouw eigen keuze. Zie [keurOverdracht].
        verwachtSeconden: job.exact == null && !job.jouwKeuze ? job.authority?.seconds : null,
        // En de versie die gevraagd werd, net zo.
        gevraagd: job.exact == null && !job.jouwKeuze && job.authority != null
            ? (artiest: job.authority!.artist, titel: job.authority!.title)
            : null);
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
  ///
  /// [bestand] is het gekozen bestand zoals de keuzelijst het toonde. Het nummer alleen is niet
  /// genoeg zodra de download een ándere weg neemt dan de lijst — zie [OnlineService.resolveForDownload].
  void enqueue(SearchResult result, {int? fileId, TbFile? bestand, TbTorrent? klaar}) {
    final prep = DownloadJob(fileId != null ? result.name : 'Voorbereiden: ${result.name}')..status = 'preparing';
    jobs.insert(0, prep);
    notifyListeners();
    unawaited(() async {
      try {
        // De torrent die het keuzevenster al klaar had gaat mee — behalve wanneer het DOWNLOADEN
        // beter langs TorBox kan.
        //
        // Sinds de nummerlijst altijd uit het torrentbestand zelf komt (zie [tracklist]) is `klaar`
        // ook lokaal bij een plaat die TorBox al in zijn cache heeft. Voor het lijstje is dat de
        // snelste weg; voor de bytes niet — die komen bij TorBox van hun eigen schijf in plaats van
        // uit een zwerm van één seeder. [lokaalVoor] weet dat verschil al, dus die beslist.
        final magHergebruiken =
            klaar != null && fileId != null && (!klaar.lokaal || online.lokaalVoor(result));
        // Zonder `!`: `magHergebruiken` is een final bool die met `klaar != null` begint, en Dart
        // leidt daaruit af dat `klaar` hier niet null kan zijn. Een uitroepteken dat niets doet is
        // hier een waarschuwing, en waarschuwingen breken de bouw af.
        final gekozen =
            !magHergebruiken ? null : klaar.files.where((f) => f.id == fileId).toList();
        final (torrent, files) = gekozen != null && gekozen.isNotEmpty
            ? (klaar!, gekozen)
            : await online.resolveForDownload(result, fileId, bestand: bestand, onProgress: (p, s) {
                prep.progress = p;
                notifyListeners();
              });
        jobs.remove(prep);
        final naamMap = _sanitize(torrent.name);
        // **Binnenkomen in de keuringsmap, niet in de bibliotheek.** Tot 29-09-2026 stond hier
        // `DebridMusic Downloads\<torrent>` — een map die de bibliotheek inleest — en stond een
        // afgekapte FLAC dus in je bibliotheek zodra hij binnen was. Nu wacht alles in `_keuring`, en
        // pas wat de keuring doorstaat gaat naar zijn plek. Zie [keuringMap] en [_bergTorrentOp].
        final destDir = Directory(
            '$_downloadsRoot${Platform.pathSeparator}$keuringMap${Platform.pathSeparator}$naamMap');
        // Waar de rest heen gaat die niet op te bergen is — de map waar vroeger alles binnenkwam.
        final zichtbaar = Directory('$_downloadsRoot${Platform.pathSeparator}$naamMap');
        await destDir.create(recursive: true);
        _opKeuring.update(destDir.path, (n) => n + 1, ifAbsent: () => 1);
        try {
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
            lopend.add(_inRij(() => _downloadLokaal(torrent, files, destDir, nieuwe,
                cues: cues, seedNa: bronVraagtSeeden(result.source))));
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
          // Pas NA het knippen: een image met een cue is vóór deze regel één groot bestand, en dat
          // hoort niet als één nummer in je bibliotheek te belanden.
          await _bergTorrentOp(destDir, torrent.name, zichtbaar: zichtbaar, binnen: nieuwe);
        } finally {
          final over = (_opKeuring[destDir.path] ?? 1) - 1;
          if (over <= 0) {
            _opKeuring.remove(destDir.path);
          } else {
            _opKeuring[destDir.path] = over;
          }
        }
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
  /// [seedNa] betekent: dit komt van een besloten tracker, dus blijven delen na afloop.
  ///
  /// Dat verandert drie dingen, en alle drie zijn nodig — half seeden is niet seeden. De torrent
  /// krijgt een seed-tijd mee, de bestanden worden GEKOPIEERD in plaats van verplaatst (aria2 blijft
  /// uitdelen wat in zijn eigen map staat), en er wordt na afloop niets opgeruimd zolang hij deelt.
  /// Dat kost tijdelijk twee keer de ruimte; dat is de prijs van een account dat blijft bestaan.
  Future<void> _downloadLokaal(
      TbTorrent torrent, List<TbFile> files, Directory destDir, List<DownloadJob> jobs,
      {List<TbFile> cues = const [], bool seedNa = false}) async {
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

    // Naast de plaat in de downloadmap, zoals altijd — niet onder de keuringsmap waar [destDir] sinds
    // 29-09-2026 staat. Een seedende torrent houdt zijn werkmap uren vast, en de keuring hoort die
    // nooit voor een binnengekomen plaat aan te zien.
    final werkMap = Directory(werkMapPad(
        Directory('$_downloadsRoot${Platform.pathSeparator}${_sanitize(torrent.name)}'),
        hash,
        torrent.name));
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
    final seedMin = seedNa && online.settings.seedUren > 0 ? online.settings.seedUren * 60 : null;
    String? gid;
    var aanhaakReden = '';
    var afgebroken = false;

    // ÉÉN TEGELIJK PER PLAAT, van hier tot en met het bijhouden van [_gidPerTorrent].
    //
    // Alles hieronder is kijken-en-dan-doen: is er al een taak voor deze torrent, en zo nee, meld
    // hem aan. Zonder slot ertussen deden zeven gelijktijdige opdrachten dat alle zeven tegelijk.
    // Zie [_perTorrent] voor de meting.
    //
    // **Het slot is kort en het wachten staat erbuiten.** Dat is met opzet: in de eerste opzet zat
    // ook de wachtlus hieronder binnen het slot, en toen bleef één opdracht die niet kon aanhaken
    // negentien seconden liggen — met de vier opdrachten achter hem erbij. Wie niet naar binnen
    // kan, hoort de deur niet dicht te houden voor wie dat misschien wel kan.
    Future<void> poging() => _perTorrent(hash, () async {
      if (hash.isNotEmpty) {
        final lopend = _gidPerTorrent[hash];
        if (lopend != null && await motor.kiesErbij(lopend, gekozen)) {
          gid = lopend;
          _log.line('torrent $hash liep al (gid=$lopend) — erbij gekozen zonder nieuwe aanmelding');
        }
      }
      gid ??= await motor.voegTorrentToe(torrent.lokaleTorrent!,
          map: werkMap.path, kies: gekozen, seedMinuten: seedMin);
      // EEN GID DAT METEEN OMVALT IS GEEN TAAK.
      //
      // `aria2.addTorrent` neemt de aanmelding aan en geeft netjes een gid terug; de weigering komt
      // pas een tel later uit aria2's eigen lus, als "errorCode=12 InfoHash … is already
      // registered". De app hield dat gid dan vast, hing zijn balk eraan, en meldde een halve
      // minuut later "Mislukt" — terwijl de torrent gewoon liep, alleen onder een ander gid.
      //
      // Even kijken of hij nog leeft is genoeg. Blijkt hij stuk, dan valt deze opdracht door naar
      // het aanhaken hieronder, en dát is precies de weg die wél werkt.
      if (gid != null && !await _leeftNog(motor, gid!)) {
        _log.line('gid $gid viel meteen om (${motor.laatsteFout ?? 'geweigerd'}) — aanhaken dan');
        gid = null;
      }

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

      // Nog binnen het slot: pas als dít kaartje ligt mag de volgende opdracht naar binnen, want
      // anders leest die opnieuw een leeg kaartje en meldt hij de torrent alsnog een tweede keer.
      final g = gid;
      if (g != null) {
        _lopersPerTorrent.update(g, (n) => n + 1, ifAbsent: () => 1);
        // Onthouden welk gid bij deze plaat hoort, zodat het VOLGENDE nummer er meteen bij kan in
        // plaats van eerst tegen een weigering aan te lopen. Weggehaald door dezelfde teller die het
        // opruimen regelt — zolang er nog iemand op deze taak hangt, is hij geldig.
        if (hash.isNotEmpty) _gidPerTorrent[hash] = g;
      }
    });

    await poging();

    // WACHTEN IS BETER DAN MISLUKKEN, en dit wachten gebeurt BUITEN het slot.
    //
    // Aanhaken is de snelle weg en werkt meestal. Maar aria2 laat `select-file` niet in alle
    // toestanden veranderen — een taak die net klaar is, neemt er niets meer bij — en dan stond er
    // "Mislukt" op een nummer dat gewoon even had kunnen wachten tot de rest van de plaat binnen
    // was. Gemeten op 26-08-2026 met Boney M: nummer 3 kwam binnen, nummer 1 en 2 vielen om met
    // "InfoHash … is already registered".
    //
    // Zodra die andere download klaar is haalt [verwijder] de torrent uit aria2, en dan gaat de
    // aanmelding alsnog. Elke ronde is een volledige poging: eerst opnieuw kijken of er intussen een
    // taak ligt om bij aan te haken, en pas daarna zelf aanmelden. Vier minuten is ruim voor één
    // nummer, en eindig genoeg om niet voor eeuwig een plek in de rij te bezetten.
    if (gid == null && hash.isNotEmpty) {
      alle('waiting', detail: 'wacht op een andere download van deze plaat');
      final tot = DateTime.now().add(const Duration(minutes: 4));
      while (gid == null && DateTime.now().isBefore(tot)) {
        if (jobs.every((j) => j.cancelled)) {
          afgebroken = true;
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 3));
        await poging();
      }
    }

    if (afgebroken) return;
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

    // Vanaf hier ligt de taak vast. Een eigen naam is nodig, geen `gid!` overal: `gid` wordt door de
    // closure hierboven beschreven, en Dart laat zo'n variabele daarom nooit naar niet-null
    // promoveren.
    final taak = gid!;

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
        final s = await motor.stand(taak);
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
      final s = await motor.stand(taak);
      for (var i = 0; i < files.length; i++) {
        final b = s?.bestand(files[i].id);
        // Een nummer dat je onderweg hebt weggetikt hoort niet alsnog in je bibliotheek te landen.
        // Het stuk dat aria2 er al van had blijft in zijn eigen map staan en gaat mee in de
        // opruiming hieronder.
        if (jobs[i].cancelled) continue;
        if (b == null) {
          // Stil doorlopen stond hier, en dat is de ergste soort: het opruimen gooit aria2's map
          // zo meteen weg, dus dit nummer is dan wég terwijl zijn regel op "bezig" blijft staan.
          jobs[i].status = 'failed';
          jobs[i].detail = 'aria2 kende dit bestand niet meer';
          continue;
        }
        // BESTAAT IS NIET AF.
        //
        // Hier stond alleen een `exists()`, en dat is precies één bit te weinig. aria2 maakt bij het
        // starten ALLE bestanden aan die hij gaat aanraken — leeg, nul bytes — en vult ze pas
        // seconden later. Ook de buren van wat je koos: een blok dat over de grens van twee
        // bestanden valt, laat een half bestand achter waar je niets om vroeg.
        //
        // **Gemeten op 31-08-2026, Beyoncé — Dangerously In Love.** Een filmpje van de werkmap, elke
        // seconde één opname:
        //
        //     22:02:46.314  NIEUW            0 B  07 - Yes.flac
        //     22:02:51.788  0 ->    26.369.312 B  07 - Yes.flac
        //     22:02:51.788  0 ->       450.051 B  03 - Baby Boy.flac   <- buurbestand, half
        //
        // Vijf seconden lang komt een leeg bestand door `exists()` heen. In die spleet verhuisde de
        // app een FLAC van nul bytes naar de albummap, zette de taak op "Klaar", en zag de
        // gebruiker een nummer dat 0:00 duurt en niet afspeelt — terwijl het volgens de naam en de
        // extensie een keurige FLAC is. Dat is de klacht van vandaag, en `08 - Signs` stond er zo
        // bij: 0 B, terwijl aria2 er 32 MiB van had binnengehaald.
        //
        // **De schijf beslist, niet aria2's boekhouding.** De eerste opzet keek naar zijn
        // voortgang per bestand (`completedLength`), en dat leek de nette weg. Gemeten op
        // 31-08-2026 bij zeven nummers tegelijk: nadat een taak klaar is meldt aria2 voor élk
        // bestand nul, ook voor de bestanden die hij zojuist compleet heeft binnengehaald. Alle
        // zeven nummers kregen zo "0% binnen" terwijl er drie gewoon op schijf stonden.
        //
        // De lengte uit de torrent naast de lengte op schijf is wél te vertrouwen, en beantwoordt
        // exact dezelfde vraag: is dit bestand af? Een lege huls en een half buurbestand vallen er
        // allebei op af, en een compleet bestand komt er altijd doorheen.
        final bron = File(b.pad);
        if (!await bron.exists()) {
          jobs[i].status = 'failed';
          jobs[i].detail = 'aria2 meldde klaar, maar het bestand staat er niet';
          continue;
        }
        final opSchijf = await bron.length();
        if (b.lengte > 0 && opSchijf < b.lengte) {
          jobs[i].status = 'failed';
          jobs[i].detail = opSchijf == 0
              ? 'leeg gebleven — aria2 had dit nummer niet binnen'
              : 'onvolledig: ${opSchijf ~/ 1024} van ${b.lengte ~/ 1024} kB binnen';
          continue;
        }
        final geland = await _verhuisNaar(bron, destDir, files[i].label, kopieer: seedNa);
        if (geland == null) {
          jobs[i].status = 'failed';
          jobs[i].detail = 'geen vrije naam in de doelmap';
          continue;
        }
        await _jouwKeuze(geland);
        // Heel, en als jouw keuze vastgelegd: nu mag hij gekeurd en opgeborgen worden. Zie
        // [_inAanmaak].
        _inAanmaak.remove(geland);
        // Zeggen dat er nog gedeeld wordt. Anders staat er "Klaar" terwijl er nog uren
        // bandbreedte weggaat, en dat hoort niemand te ontdekken via zijn router.
        _wachtOpKeuring(jobs[i], geland,
            naKeuring: seedMin == null
                ? null
                : 'deelt nog ${online.settings.seedUren} uur terug (besloten tracker)');
      }
      // En de bladen, vóór het opruimen: het opruimen gooit de map weg die aria2 aanmaakte, en
      // een cue die daar blijft staan verdwijnt mét die map — waarna er niets meer te knippen valt.
      for (final c in cues) {
        final b = s?.bestand(c.id);
        // Dezelfde regel als hierboven, en om dezelfde reden op de schijf gemeten: een blad dat nog
        // nul bytes is, is geen blad. Zo kwamen er drie lege .cue-bestanden in de albummap terecht —
        // "… - Dangerously In Love (2).cue", "(3)", "(4)" — allemaal 0 B, allemaal naast elkaar.
        if (b == null) continue;
        final bron = File(b.pad);
        if (!await bron.exists()) continue;
        final opSchijf = await bron.length();
        if (opSchijf == 0 || (b.lengte > 0 && opSchijf < b.lengte)) continue;
        final blad = await _verhuisNaar(bron, destDir, c.label);
        if (blad != null) _inAanmaak.remove(blad);
      }
      notifyListeners();
      // Opruimen mag alleen als deze taak van ons alleen is. Hangt er nog een tweede nummer van
      // dezelfde plaat aan, dan gooit het opruimen de map weg waar dat nummer nog in staat.
      //
      // En bij een besloten tracker helemaal niet: aria2 deelt uit wat in die map ligt. Wie hier
      // opruimt heeft wel geseed op papier en niets teruggegeven in de praktijk. De map gaat weg
      // wanneer het seeden afloopt — zie [_ruimNaSeeden].
      if (seedMin != null) {
        _log.line('seeden: ${werkMap.path} blijft staan, nog ${online.settings.seedUren} uur');
        unawaited(_ruimNaSeeden(motor, taak, werkMap, Duration(minutes: seedMin)));
      }
      // Het opruimen zelf staat in de `finally` hieronder — daar wordt geteld wie er nog aan deze
      // torrent hangt, en dat is de enige plek waar dat kloppend gebeurt. Zie de uitleg daar.
      //
      // Geen `onLibraryChanged` meer: wat hier binnenkwam staat in de keuringsmap, en die leest de
      // bibliotheek niet. Het opbergen daarna laat haar inlezen ([_bergTorrentOp]).
    } finally {
      // De torrent uit aria2 halen zodra hij klaar is: hij seedt toch niet (--seed-time=0) en een
      // lijst die volloopt met afgeronde taken maakt elke volgende vraag trager.
      //
      // Maar pas als de laatste loper weg is. Een gid dat weggehaald wordt terwijl een tweede
      // opdracht er zijn voortgang uit leest, laat die opdracht op niets wachten.
      final over = (_lopersPerTorrent[taak] ?? 1) - 1;
      if (over <= 0) {
        _lopersPerTorrent.remove(taak);
        // Ook de snelkoppeling weg, en alléén als hij nog naar ONS gid wijst: een derde nummer dat
        // ondertussen een nieuwe taak voor dezelfde plaat opzette mag hier zijn ingang niet
        // kwijtraken.
        if (_gidPerTorrent[hash] == taak) _gidPerTorrent.remove(hash);
        // Behalve wanneer hij nog aan het delen is: weghalen bij aria2 IS stoppen met delen.
        if (seedMin == null) {
          await motor.verwijder(taak);
          // OPRUIMEN HOORT HIER, en niet hierboven bij het verhuizen.
          //
          // Daar werd geteld hoeveel opdrachten er nog aan deze torrent hingen, maar de teller gaat
          // pas hier omlaag. Twee nummers die binnen dezelfde seconde klaar zijn zien dus allebei
          // "er hangt er nog een aan mij" en ruimen allebei niet op. Gemeten op 29-08-2026 met Tears
          // For Fears: beide nummers netjes binnen, en de werkmap bleef staan met drie halve
          // bestanden erin — nummers die niemand had aangeklikt, want een torrentstuk loopt over de
          // grens van een bestand heen.
          //
          // Wat de gebruiker koos is op dit punt allang verhuisd; wat hier nog ligt is per definitie
          // rommel.
          try {
            if (await werkMap.exists()) await werkMap.delete(recursive: true);
          } catch (_) {
            // Blijft hij staan, dan is dat hooguit verspilde ruimte in een map die de scanner
            // overslaat — en de volgende download van dezelfde plaat ruimt hem alsnog op.
          }
        }
      } else {
        _lopersPerTorrent[taak] = over;
      }
    }
  }

  /// Wachten tot het seeden afgelopen is, en dan pas de werkmap opruimen.
  ///
  /// aria2 stopt zelf met delen zodra `seed-time` om is; deze lus kijkt daarnaar in plaats van blind
  /// een klok af te tellen, want een torrent kan ook eerder klaar zijn (afgebroken, verwijderd, of
  /// de app die opnieuw start). De bovengrens is er voor het geval aria2 er niet meer is: dan blijft
  /// er anders voor altijd een map staan.
  ///
  /// Gaat de app tussendoor uit, dan blijft de map staan tot de volgende download van dezelfde
  /// plaat hem overneemt. Een paar honderd megabyte die blijft liggen is minder erg dan een account
  /// dat wordt ingetrokken.
  Future<void> _ruimNaSeeden(Aria2 motor, String gid, Directory werkMap, Duration hoelang) async {
    final tot = DateTime.now().add(hoelang + const Duration(minutes: 5));
    while (DateTime.now().isBefore(tot)) {
      await Future<void>.delayed(const Duration(minutes: 1));
      final s = await motor.stand(gid);
      // Weg, gestopt of mislukt: dan valt er niets meer te delen.
      if (s == null || s.stuk || s.status == 'removed') break;
      if (s.status == 'complete' && s.seeders == 0 && s.verbindingen == 0) {
        // aria2 laat een afgeronde torrent op `complete` staan; pas als hij ook niemand meer
        // bedient is het seeden echt voorbij. Nog één ronde wachten om niet te vroeg te zijn.
        await Future<void>.delayed(const Duration(minutes: 2));
        final nog = await motor.stand(gid);
        if (nog == null || nog.verbindingen == 0) break;
      }
    }
    await motor.verwijder(gid);
    try {
      if (await werkMap.exists()) await werkMap.delete(recursive: true);
      _log.line('seeden afgelopen: ${werkMap.path} opgeruimd');
    } catch (_) {
      // Een map die blijft staan is geen reden om iets te melden; de volgende download ruimt hem op.
    }
  }

  Future<void> _download(int torrentId, TbFile f, Directory destDir, DownloadJob job) async {
    http.Client? client;
    IOSink? sink;
    File? dest;
    // Waar de bytes binnenkomen: naast de gereserveerde naam, met `.part` erachter. Pas bij de laatste
    // byte krijgt het bestand zijn eigen naam. Valt de app midden in een download om, dan ziet
    // [hervatKeuring] zo wat half is — een halve mp3 is aan zijn inhoud niet te herkennen, een halve
    // FLAC wel, maar alleen met ffmpeg erbij.
    File? part;
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
      // Vanaf nu tot hij als jouw keuze vastligt: niet opbergen. Zie [_inAanmaak].
      _inAanmaak.add(gelandPad);
      part = File('${dest.path}.part');
      sink = part.openWrite();
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
      final binnen = total <= 0 ? received > 0 : received >= total;
      if (!binnen) throw 'incompleet: $received van $total bytes';
      // Eerst dicht, dan pas hernoemen: op Windows laat een open schrijfhandvat zich niet verplaatsen.
      await sink.close();
      sink = null;
      // Hernoemen vervangt de lege reservering van [_legVast] (gemeten: Dart's `rename` schrijft op
      // Windows over een bestaand bestand heen).
      await part.rename(dest.path);
      complete = true;
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
      if (!complete && part != null) {
        await part.delete().catchError((_) => part!);
      }
      if (!complete && dest != null) {
        await dest.delete().catchError((_) => dest!);
      }
      if (!complete) _inAanmaak.remove(gelandPad);
    }
    // Jouw keuze: bij gelijke kwaliteit wint hij van wat er al lag. Zie [_jouwKeuze].
    if (gelandPad.isNotEmpty) await _jouwKeuze(gelandPad);
    // Pas NU mag hij gekeurd en opgeborgen worden: helemaal binnen, en als jouw keuze vastgelegd. Eén
    // regel eerder zou een ander nummer uit dezelfde torrent hem kunnen opbergen vóór de bescherming
    // erop zit — en dan verliest hij bij gelijke kwaliteit van wat er al lag.
    _inAanmaak.remove(gelandPad);
    // Geen `onLibraryChanged` meer: hij staat in de keuringsmap, en die leest de bibliotheek niet.
    _wachtOpKeuring(job, gelandPad);
  }

  /// Binnen, maar nog niet goedgekeurd.
  ///
  /// "Klaar" zou hier liegen: het bestand staat nog niet in je bibliotheek, en óf het er komt beslist
  /// de keuring pas als de hele plaat binnen is ([_bergTorrentOp]). [naKeuring] komt achter wat de
  /// keuring zegt — voor wat er daarna nog doorloopt, zoals het terugdelen aan een besloten tracker.
  void _wachtOpKeuring(DownloadJob job, String pad, {String? naKeuring}) {
    job.keuringsPad = pad;
    job.naKeuring = naKeuring;
    job.progress = 1;
    job.status = 'downloading';
    job.canCancel = false;
    job.detail = naKeuring == null ? 'binnen — wacht op de keuring' : 'binnen — wacht op de keuring · $naKeuring';
    notifyListeners();
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
    // De map kan intussen weg zijn: het opbergen van een andere keuze uit dezelfde torrent ruimt een
    // lege keuringsmap op ([pruneVacated]), en dan faalt élke exclusieve aanmaak hieronder — waarna er
    // "geen vrije naam" stond terwijl er niets in de weg lag.
    await destDir.create(recursive: true);
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
  /// het opruimen na afloop en is dan weg.
  ///
  /// **Nooit over een ander bestand heen.** Een torrent wordt hier plat uitgepakt, dus alles gaat op
  /// zijn eigen naam naar dezelfde map — en een verzamelbox of een discografie heet bij elke schijf
  /// opnieuw `01 - ….flac`. `rename` schrijft daar zonder één woord overheen: je koos honderd
  /// nummers, er stonden er twaalf, elke taak meldde "klaar", en de originelen waren al door
  /// het opruimen na afloop al weggegooid. Zie [vrijeNamen] voor welke naam er dan gekozen wordt.
  ///
  /// De aanroepers verhuizen één voor één, dus kijken of een naam vrij is kan hier gewoon.
  /// [kopieer] laat het origineel staan. Dat is nodig bij een besloten tracker: aria2 deelt uit wat
  /// in zijn eigen map ligt, en een verplaatst bestand kan hij niet meer uitdelen — dan sta je alsnog
  /// als hit-and-run te boek terwijl de app "klaar" meldt.
  Future<String?> _verhuisNaar(File bron, Directory destDir, String naam,
      {bool kopieer = false}) async {
    // De map waar het bestand IN DE TORRENT stond — dat is wat "CD2" of "1965 - Poupée de cire" van
    // elkaar onderscheidt zodra de namen erin gelijk zijn.
    final ouder = bron.parent.path;
    final submap = ouder == destDir.path ? '' : laatsteMap(ouder);
    // Zie [_legVast]: de keuringsmap kan door een ander opbergen al opgeruimd zijn.
    await destDir.create(recursive: true);
    for (final kandidaat in vrijeNamen(_sanitize(naam), submap: _sanitize(submap))) {
      final doel = File('${destDir.path}${Platform.pathSeparator}$kandidaat');
      if (bron.path == doel.path) return doel.path;
      if (await doel.exists()) continue;
      // Tijdens het kopiëren staat hier een half bestand. De aanroeper haalt hem uit [_inAanmaak]
      // zodra hij heel is en vastligt — niet deze functie, want die weet niet wanneer dat is.
      _inAanmaak.add(doel.path);
      // Kopiëren gaat via een `.part`, net als [_download]: valt de app halverwege om, dan weet
      // [hervatKeuring] dat dit geen heel bestand is.
      Future<void> kopieerHeel() async {
        final part = '${doel.path}.part';
        await bron.copy(part);
        await File(part).rename(doel.path);
      }

      if (kopieer) {
        await kopieerHeel();
        return doel.path;
      }
      try {
        await bron.rename(doel.path);
      } catch (_) {
        // Over een schijfgrens heen kan `rename` niet; dan maar kopiëren en de bron opruimen.
        await kopieerHeel();
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

/// Hoe één poging bij een uploader afliep, binnen `_haalVoorRadio`.
enum _Uit { klaar, volgende, stop }

/// Hoe een kandidaat voor een wens door de keuring kwam (`_keurVoorWens`).
enum _Wenskeuring {
  /// In de bibliotheek: de wens is vervuld.
  opgeborgen,

  /// Nep, een andere uitgave of niet bewezen beter. Onthouden, zodat hij niet terugkomt.
  afgewezen,

  /// Verloor van wat er al lag. Niet onthouden: het bestand was in orde.
  alAanwezig,

  /// Bewaard als andere versie van het nummer (versies.dart): het nummer zelf bleef. De wens zoekt verder.
  alsVersie,
}

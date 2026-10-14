import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/foundation.dart';

import '../ai.dart';
import '../album_facts.dart';
import '../cloud/device_identity.dart';
import '../downloadbron.dart';
import '../album_facts_resolver.dart';
import '../enrichment.dart';
import '../kapot_bestand.dart';
import '../library.dart';
import '../models.dart';
import '../musicbrainz.dart';
import '../online.dart';
import '../organize.dart';
import '../paths.dart';
import '../prullenbak.dart' show heeftPrullenbak;
import '../warm_log.dart';
import '../settings.dart';
import '../soulseek.dart';
import '../torbox.dart';
import 'cast_manager.dart';
import 'radiohaler.dart';
import 'remming.dart';
import 'accountkoppeling.dart';
import 'catalog.dart';
import 'certificaat.dart';
import 'dtos.dart';
import 'net.dart';
import 'pairing.dart';
import 'pc_bijwerker.dart';
import 'range.dart';
import 'state_store.dart';
import 'tls_ingang.dart';
import 'poorten.dart';
export 'poorten.dart';
import 'quota.dart';
import 'tokens.dart';
import 'transcode.dart';
import 'upnp.dart';
import '../artwork.dart';

/// The port the other devices look for. Fixed on purpose — an ephemeral port would mean every
/// restart hands out a different address, and anything a client saved would go stale.
const int kLanPort = 47820;

/// Langs welke ingang een verzoek binnenkwam. Het beleid volgt uit de socket die de verbinding aannam,
/// nooit uit het bronadres: dat beslist alleen nog of het op een thuisingang mag.
enum Ingang {
  /// 47820: HTTP, zoals altijd. Alleen HTTP-sleutels, alleen privé-adressen.
  http,

  /// 47822: TLS, alle rechten, alleen privé-adressen (thuis, Tailscale). Alleen TLS-sleutels.
  tlsThuis,

  /// 47821: TLS, wat via de modem binnenkomt. Alleen TLS-sleutels, en alleen wat op [weigerVanBuiten] mag.
  tlsBuiten,
}

/// Waarom iets van buiten (47821) niet mag, of null als het mag. Alleen op pad en methode; wat van het
/// lijf afhangt (bijwerken, speakers) staat bij die routes zelf.
///
/// **Een witte lijst, geen zwarte.** Wat hier niet staat, kan van buiten niet — ook een route die er
/// morgen bij komt. Niet van buiten: koppelen, de hele bibliotheek doorzoeken of uitlijsten, de
/// gebeurtenissenstroom, muziek op een speaker thuis starten, RuTracker aanmelden en de warmtemeting.
@visibleForTesting
String? weigerVanBuiten(String pad, String methode) {
  const exact = {
    '/health', '/api/catalog', '/api/album/facts', '/api/state', '/api/state/ops', '/api/uitwijk',
    '/api/config', '/api/radio', '/api/jobs', '/api/corrections', '/api/move/plan', '/api/move/apply',
    '/api/update', '/api/cast/devices', '/api/cast/control', '/api/cast/status',
  };
  const voorvoegsels = ['/stream/', '/art/', '/waarom/', '/api/online/', '/api/soulseek/', '/api/jobs/'];
  if (exact.contains(pad) || voorvoegsels.any(pad.startsWith)) return null;
  if (pad == '/api/rutracker/sessie') return 'Kan alleen met je gsm thuis op wifi.';
  return 'Dit kan alleen thuis of via Tailscale.';
}

/// Mag dit adres in een bewerking die van buiten (47821) komt? Leeg mag (dat wist een keuze). Verder
/// alleen `https` naar een naam of adres op het internet: de pc haalt zo'n adres later zelf op, en een
/// adres op het eigen netwerk (de modem, een speaker, `pc.invalid`) of een bestand op de pc hoort daar
/// niet via de deur naar buiten in te komen.
@visibleForTesting
bool adresVanBuitenMag(String url) {
  if (url.isEmpty) return true;
  final u = Uri.tryParse(url);
  if (u == null || u.scheme != 'https' || u.host.isEmpty || u.userInfo.isNotEmpty) return false;
  final host = u.host.toLowerCase();
  final ip = InternetAddress.tryParse(host);
  if (ip != null) {
    if (ip.isMulticast || toestelWeg(ip) != 'buiten') return false;
    final eerste = int.tryParse(host.split('.').first);
    return ip.type == InternetAddressType.IPv6 || (eerste != null && eerste != 0 && eerste < 224);
  }
  if (!host.contains('.') || host == 'localhost') return false;
  const binnen = ['.localhost', '.local', '.lan', '.home', '.internal', '.localdomain', '.home.arpa', '.invalid', '.test'];
  return !binnen.any(host.endsWith);
}

/// Of dit bronadres op een thuisingang (47820, 47822) mag: deze pc zelf, het eigen netwerk en Tailscale.
/// Zie [toestelWeg]: alles wat daar `buiten` heet, niet.
bool magOpThuisingang(InternetAddress bron) => toestelWeg(bron) != 'buiten';

/// Serves this machine's library to the Mac, the iPad and the Shield.
///
/// It runs inside the app rather than as a separate service, and reads straight from the live
/// [LibraryStore]. That is the whole design: the covers you picked, the pressings you pinned and
/// the albums you merged are in those objects, so there is no second scan that could disagree
/// with what you see on screen here.
class LanServer {
  LanServer({
    required this.library,
    required this.token,
    required this.state,
    required this.pairing,
    this.port = kLanPort,
    this.version = '',
    this.online,
    this.soulseek,
    this.downloads,
    this.settings,
    this.musicbrainz,
    this.cloudUid,
    this.uidVanSleutel,
    this.firebaseProject,
    this.certificaat,
    this.tlsPoort = kTlsPoort,
    this.publiekPoort,
    ValueNotifier<String?>? rodeMelding,
    GrantStore? grants,
  })  : grants = grants ?? GrantStore(),
        rodeMelding = rodeMelding ?? ValueNotifier(null),
        catalog = LanCatalog(library) {
    final dir = library.configDir;
    cast = CastManager(
      catalog: catalog,
      token: token,
      port: port,
      logPath: dir.isEmpty ? null : '$dir${Platform.pathSeparator}cast.log',
    );
    // NIET afhankelijk van `configDir`, en dat is een reparatie.
    //
    // Stond die map leeg op het moment dat de server werd opgezet — en dat kan, want `applySettings`
    // loopt naast het inlezen van de bibliotheek — dan was `_koppelLog` null en werd er de hele
    // sessie GEEN ENKELE weigering opgeschreven. Gemeten op 30-08-2026: elk toestel kreeg 401, ook
    // met de goede gedeelde sleutel, en in `koppeling.log` stond niets van die dag. Dan is er niets
    // te onderzoeken; er is alleen een telefoon die niet meer binnenkomt.
    //
    // `logDir` bestaat altijd (zie paths.dart), dus dit logboek nu ook.
    _koppelLog = WarmLog('${dir.isEmpty ? logDir : dir}${Platform.pathSeparator}koppeling.log');
    _stroomLog = WarmLog('${dir.isEmpty ? logDir : dir}${Platform.pathSeparator}stroom.log');
    _warmteLog = WarmLog('${dir.isEmpty ? logDir : dir}${Platform.pathSeparator}warmte.log');
  }

  /// Met welk account deze pc zelf is ingelogd, of leeg als hij dat niet is.
  ///
  /// Een functie en geen waarde: er wordt op de pc in- en uitgelogd terwijl de server draait, en een
  /// account dat bij het opstarten werd vastgelegd zou daarna blijven staan.
  final String Function()? cloudUid;

  /// Van welk account is deze inlogsleutel? Zie `CloudAuth.uidVanIdToken`.
  ///
  /// Meegegeven en niet hier opgebouwd, zodat een toets deze deur kan uitproberen zonder Google —
  /// en dat is precies de deur die je wél wil kunnen uitproberen.
  final Future<String> Function(String idToken)? uidVanSleutel;

  /// Het Firebase-project van deze build, voor de eerste blik op een inlogsleutel
  /// (`inlogsleutelFout`). Null of leeg: die blik wordt overgeslagen en beslist Google alleen.
  final String Function()? firebaseProject;

  /// Het eigen certificaat (`certificaat.dart`). Null: geen versleutelde ingangen, alleen 47820.
  final PcCertificaat? certificaat;

  /// De versleutelde poort voor thuis. 0 in toetsen.
  final int tlsPoort;

  /// De poort voor buiten, of null zolang de deur naar buiten niet aan staat (stap 7). 0 in toetsen.
  final int? publiekPoort;

  /// Een rode melding voor op de pc: iets wat op misbruik van een sleutel wijst. Zie [_ruil] en de
  /// TLS-sleutel die op 47820 aankwam.
  final ValueNotifier<String?> rodeMelding;

  /// Zie `remming.dart`.
  final Remming remming = Remming();

  /// Hoeveel duur werk een sleutel van buiten mag laten doen. Zie `quota.dart`.
  final Quota quota = Quota();

  /// Langs welke ingang elk verzoek binnenkwam, voor de routes die het zelf moeten weten (quota, de
  /// regels voor bewerkingen van buiten) zonder dat elke route een extra argument krijgt.
  final Expando<Ingang> _ingangVan = Expando('ingang');

  /// Kan deze pc iets naar een prullenbak sturen? Van buiten gaat verwijderen alleen zo.
  @visibleForTesting
  bool Function() prullenbakAanwezig = () => heeftPrullenbak;
  final KoppelBudget koppelBudget = KoppelBudget();

  /// Eén regel bij het opzetten: waarmee deze server dénkt te mogen werken.
  ///
  /// **Waarom dit erbij moet.** Een weigering vertelt wat er geboden werd, maar niet of de server
  /// überhaupt iets had om mee te vergelijken. Op 30-08-2026 weigerde hij álles — ook zijn eigen
  /// gedeelde sleutel uit `settings.json` — en er viel van buiten niet vast te stellen of hij nul
  /// koppelingen had, een lege sleutel, of allebei. Deze regel maakt dat één blik.
  void _meldStand() {
    _koppelLog?.line('SERVER OP  poort $port'
        '  gedeelde sleutel: ${token.isEmpty ? "LEEG" : "${token.substring(0, 4)}… (${token.length})"}'
        '  koppelingen in geheugen: ${grants.all.length}'
        '  bibliotheekmap: ${library.configDir.isEmpty ? "(nog leeg)" : library.configDir}');
  }

  /// Waarom een verzoek geweigerd werd. Alleen bij een WEIGERING, nooit bij een geslaagd verzoek.
  ///
  /// **Waarom dit er moest komen.** Gemeten op 11-08-2026: met de app onafgebroken draaiend gaf
  /// `/api/catalog` opeens 401 voor ALLE 19 koppelingen uit `grants.json` én voor de gedeelde sleutel
  /// — op localhost, op het LAN-adres en via Tailscale. Na de app te herstarten werkte dezelfde
  /// sleutel meteen weer. Op de telefoon las dat als "je pc staat uit", want die kant kent alleen
  /// "het lukte niet".
  ///
  /// Van buitenaf is een 401 één symptoom voor drie heel verschillende oorzaken: het geheugen is
  /// leeggelopen, de gedeelde sleutel is opnieuw verzonnen, of dit toestel is echt nooit gekoppeld.
  /// Zonder deze regel zijn die niet te scheiden en blijft het gissen.
  ///
  /// Van de aangeboden sleutel gaan alleen de eerste vier tekens mee — genoeg om te zien of het
  /// telkens hetzelfde toestel is, te weinig om er iets mee te kunnen.
  WarmLog? _koppelLog;

  /// Wat er met elk gestart nummer gebeurde: origineel, uit de cache, of nieuw omgezet — en hoe lang
  /// dat duurde. **Waarom dit er is.** Saber op 06-10-2026: het omzetten naar cd-kwaliteit voor 5G "is
  /// nog traag en niet altijd juist of doet hij het niet". Op de pc stond daar niets van: geen
  /// aanvraag, geen duur, niet of de cache raak was. Zonder regel valt "het hapert op 5G" niet uit
  /// elkaar te halen in "de pc zette te lang om", "er werd niet omgezet" en "er kwam niets aan".
  WarmLog? _stroomLog;

  /// Wat elk toestel tekent en hoe warm het is — zie `warmtemeter.dart`. Een iPad hangt niet aan
  /// een kabel; dit is de enige plek waar zijn metingen te lezen zijn.
  WarmLog? _warmteLog;

  /// Eén regel per gestart nummer: zonder Range of vanaf byte 0. De vervolgstukken die een speler
  /// opvraagt zouden het logboek anders vullen met hetzelfde nummer.
  void _stroomRegel(HttpRequest req, Track track, String wat) {
    final range = req.headers.value(HttpHeaders.rangeHeader);
    if (range != null && !range.trim().startsWith('bytes=0-')) return;
    final van = req.connectionInfo?.remoteAddress.address ?? '?';
    final bron = '${track.bitsPerSample > 0 ? track.bitsPerSample : '?'}/${track.sampleRate > 0 ? track.sampleRate : '?'} ${track.ext}';
    _stroomLog?.line('van $van  "${track.artist} – ${track.title}"  $bron  →  $wat');
  }

  static String _mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';
  int _geweigerd = 0;
  DateTime _laatsteWeigerRegel = DateTime.fromMillisecondsSinceEpoch(0);

  final LibraryStore library;
  final LanCatalog catalog;

  /// Searching and downloading, done HERE on behalf of a Mac or an iPad.
  ///
  /// Nullable because the server is also constructed in tests that care only about the library,
  /// and because a PC with no TorBox key still shares its music perfectly well. The routes answer
  /// 503 rather than crashing when they are absent — a client can then say so.
  final OnlineService? online;
  final SoulseekService? soulseek;
  final DownloadManager? downloads;

  /// Needed by [LibraryStore.applyCorrection] — a hand-picked cover is written into the cover
  /// cache, and that lives where the settings say.
  final AppSettings? settings;

  /// So this machine can work out an album's pressing on a client's behalf. Nullable for the tests
  /// that only care about the library; without it `/api/album/facts` answers only what is already
  /// known, which is a slower client rather than a broken one.
  final MusicBrainzService? musicbrainz;

  /// Which devices may fetch anything, one token each. See `tokens.dart` — it deliberately knows
  /// nothing about who signed in, so this server keeps working with the internet unplugged.
  final GrantStore grants;
  final LanStateStore state;
  final PairingStore pairing;

  /// Sending music to a speaker or the TV. Lives on the PC so the audio goes straight from here
  /// to the speaker, and so every device gets the same destination list.
  late final CastManager cast;
  final Transcoder transcoder = Transcoder();

  /// Zichzelf bijwerken op verzoek van een gekoppeld toestel. Zie `pc_bijwerker.dart`.
  final PcBijwerker bijwerker = PcBijwerker();

  /// Nummers ophalen voor de radio van een gekoppeld toestel. Zie `radiohaler.dart`.
  late final Radiohaler radiohaler = Radiohaler(downloads, soulseek, library, settings);
  final int port;
  final String version;
  String token;

  HttpServer? _http;
  HttpServer? _tls;
  HttpServer? _publiek;
  TlsIngang? _tlsIngang;
  TlsIngang? _publiekIngang;

  bool get running => _http != null;

  /// De poorten waar de versleutelde ingangen echt op luisteren, of null.
  int? get tlsBoundPort => _tls?.port;
  int? get publiekBoundPort => _publiek?.port;

  /// The port actually listening. Equals [port] in the app; differs only when [port] is 0, which
  /// tests use to let the OS pick something free rather than fight the running app for 47820.
  int get boundPort => _http?.port ?? port;

  /// Starts listening. Returns null on success, or a message to show the user.
  Future<String?> start() async {
    if (_http != null) return null;
    try {
      // anyIPv4, not `anyIPv4Loopback` and not the default: binding the default address gives an
      // IPv6 socket, and on a network where the other devices only speak IPv4 every connection
      // then fails without a single log line. The Android receiver in the media app was bitten by
      // exactly this — see the note in that project's cast receiver.
      _http = await HttpServer.bind(InternetAddress.anyIPv4, port);
      grants.alleenLezen = false;
    } on SocketException catch (e) {
      // Deze kopie luistert niet. Dan mag ze ook geen koppelingen meer wegschrijven: zie
      // [GrantStore.alleenLezen]. Een tweede kopie zette anders haar eigen, oudere beeld over de
      // lijst heen, en dan moet elk toestel opnieuw koppelen.
      grants.alleenLezen = true;
      return e.osError?.errorCode == 10048 || e.osError?.errorCode == 48
          ? 'Poort $port is al in gebruik door een ander programma.'
          : 'Kon niet starten op poort $port: ${e.osError?.message ?? e.message}';
    }
    _http!.autoCompress = false; // audio and covers are already compressed
    _meldStand();
    unawaited(_serve(_http!));
    await _startTls();
    return null;
  }

  /// De versleutelde ingangen. Lukt dat niet (poort bezet), dan draait 47820 gewoon door: zonder
  /// versleutelde weg vallen de toestellen terug op wat ze vandaag doen.
  Future<void> _startTls() async {
    final c = certificaat;
    if (c == null) return;
    Future<(HttpServer, TlsIngang)?> open(int poort, Ingang ingang) async {
      try {
        final i = await TlsIngang.bind(InternetAddress.anyIPv4, poort, c.context());
        final h = HttpServer.listenOn(i)..autoCompress = false;
        unawaited(_serve(h, ingang));
        return (h, i);
      } catch (e) {
        _koppelLog?.line('VERSLEUTELDE POORT $poort niet geopend: $e');
        return null;
      }
    }

    final thuis = await open(tlsPoort, Ingang.tlsThuis);
    _tls = thuis?.$1;
    _tlsIngang = thuis?.$2;
    final p = publiekPoort;
    if (p != null) {
      final buiten = await open(p, Ingang.tlsBuiten);
      _publiek = buiten?.$1;
      _publiekIngang = buiten?.$2;
    }
    _koppelLog?.line('VERSLEUTELD  thuis ${_tls?.port ?? '-'}  buiten ${_publiek?.port ?? '-'}  pin ${c.pin.substring(0, 12)}…');
  }

  Future<void> stop() async {
    final http = _http;
    _http = null;
    await http?.close(force: true);
    final tls = _tls;
    final publiek = _publiek;
    final tlsIngang = _tlsIngang;
    final publiekIngang = _publiekIngang;
    _tls = null;
    _publiek = null;
    _tlsIngang = null;
    _publiekIngang = null;
    await tls?.close(force: true);
    await publiek?.close(force: true);
    // **Ook de ingangen zelf.** Een HttpServer uit `listenOn` sluit de socket die hij kreeg NIET
    // (dart:io, `_closeServer = false`): zonder deze twee regels bleef 47822 luisteren en handdrukken
    // aannemen na het stoppen, en mislukte de volgende start met "poort in gebruik". Gevonden met de
    // toets voor de noodrem (sharing_grants_test).
    await tlsIngang?.close();
    await publiekIngang?.close();
  }

  /// Stop for good. Separate from [stop] so switching sharing off and on again doesn't leave the
  /// catalogue detached from the library and quietly serving a frozen snapshot.
  Future<void> dispose() async {
    await stop();
    cast.dispose();
    catalog.dispose();
    // Een opslagbeurt die een verzoek net startte (`touch`), nog afmaken: anders gaat hij verloren,
    // of schrijft hij in een map die intussen weg is.
    await grants.wachtOpOpslaan();
  }

  Future<void> _serve(HttpServer server, [Ingang ingang = Ingang.http]) async {
    await for (final request in server) {
      // One bad request must never take the server — and with it the whole app — down.
      unawaited(_handle(request, ingang).catchError((Object e, StackTrace s) {
        debugPrint('LAN request failed (${request.uri.path}): $e');
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.close();
        } catch (_) {/* already closed or hung up */}
      }));
    }
  }

  Future<void> _handle(HttpRequest req, [Ingang ingang = Ingang.http]) async {
    final res = req.response;
    _ingangVan[req] = ingang;
    // Een thuisingang neemt alleen het eigen netwerk, Tailscale en deze pc zelf aan — in code, niet
    // alleen via de firewall: die laat DebridMusic.exe op 'Openbaar' op elke poort binnen (gemeten
    // 14-10-2026), en een toewijzing in de modem naar 47820 zou dan alles openzetten.
    final bron = req.connectionInfo?.remoteAddress;
    if (ingang != Ingang.tlsBuiten && bron != null && !(_bronMagThuis ?? magOpThuisingang)(bron)) {
      _koppelLog?.line('VAN BUITEN op een thuisingang ($ingang) geweigerd: ${bron.address}');
      return _rauw(req, 403, 'Forbidden', {'error': 'Dit kan alleen thuis of via Tailscale.'});
    }
    // CORS alleen op 47820: een browser hoort niet bij de versleutelde ingangen.
    if (ingang == Ingang.http) {
    res.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Headers', 'Authorization, Content-Type, Range, If-None-Match')
      ..set('Access-Control-Allow-Methods', 'GET, POST, HEAD, OPTIONS')
      // Without this a browser client can't read the range headers it just asked for.
      ..set('Access-Control-Expose-Headers', 'Content-Range, Accept-Ranges, Content-Length, ETag');
    }

    if (req.method == 'OPTIONS') {
      res.statusCode = HttpStatus.noContent;
      await res.close();
      return;
    }

    final path = req.uri.path;

    // Unauthenticated on purpose: this is how a device confirms it found the right machine, and
    // how the app itself checks whether a second copy is already running.
    if (path == '/health') {
      // Van buiten alleen dat het deze pc is: geen naam, geen versie, geen aantallen.
      if (ingang == Ingang.tlsBuiten) {
        return _json(res, {
          'status': 'ok',
          if ((settings?.serverId ?? '').isNotEmpty) 'serverId': settings!.serverId,
        });
      }
      return _json(res, {
        'status': 'ok',
        'name': 'debridmusic-desktop',
        'version': version,
        'deviceName': deviceName(),
        'trackCount': library.tracks.length,
        'albumCount': library.albums.length,
        // Welke pc dit is, zodat een toestel dat tussen adressen kiest weet dat het de zijne is.
        if ((settings?.serverId ?? '').isNotEmpty) 'serverId': settings!.serverId,
      });
    }

    // Koppelen en ruilen kan niet van buiten (koppelen van overal komt pas met uitlevering C).
    if (ingang == Ingang.tlsBuiten && (path == '/pair' || path == '/pair-cloud' || path == '/api/sleutel/ruil')) {
      return _rauw(req, 403, 'Forbidden', {'error': 'Dit kan alleen thuis of via Tailscale.'});
    }
    // De ruil: alleen op 47822, met de huidige HTTP-sleutel van een echt toestel. Zie [GrantStore.ruil].
    if (path == '/api/sleutel/ruil' && ingang == Ingang.tlsThuis) return _ruil(req);

    // Also unauthenticated, necessarily — this is how a device that has no token gets one.
    // Over 47822 komt er meteen een TLS-sleutel bij.
    if (path == '/pair') return _pair(req, metTls: ingang == Ingang.tlsThuis);

    // Dezelfde soort deur, maar met je account in plaats van zes cijfers. Zie
    // `accountkoppeling.dart` voor waarom die er moest komen: zonder deze weg sloot één haperende
    // Firestore je buiten je eigen muziek, ook met de pc op dezelfde wifi.
    // Koppelen via het account alleen nog versleuteld (47822): een inlogsleutel gaat nooit meer
    // onversleuteld over de lijn. Een app van vóór uitlevering B hoort dat in gewone taal.
    if (path == '/pair-cloud' && ingang == Ingang.http) {
      _koppelLog?.line('PAIR-CLOUD  over 47820 geweigerd (410): een oude app, die moet bijgewerkt worden');
      return _rauw(req, 410, 'Gone', {
        'error': 'Werk de app op dit toestel bij: koppelen via je account gaat nu versleuteld.',
      });
    }
    if (path == '/pair-cloud') return _pairCloud(req, metTls: ingang == Ingang.tlsThuis);

    final van = req.connectionInfo?.remoteAddress.address ?? '?';
    if (!await _authorizedOfHerstel(req, ingang)) {
      // Per adres steeds later, en NOOIT bij een geldige sleutel (die komt hier niet). Zie `remming.dart`.
      final wacht = remming.naMislukt(van);
      if (wacht > Duration.zero) await Future<void>.delayed(wacht);
      // Met een lijf dat nog moet komen: niet via close(), want die wacht op dat lijf (zie [_teGroot]).
      if (req.contentLength > 0 || req.headers.chunkedTransferEncoding) {
        return _rauw(req, 401, 'Unauthorized', const {});
      }
      res.statusCode = HttpStatus.unauthorized;
      return res.close();
    }
    remming.gelukt(van);
    // Een geldig verzoek: deze verbinding telt niet meer mee voor het plafond van de TLS-ingang.
    if (ingang == Ingang.tlsThuis) _tlsIngang?.geldig(req.connectionInfo);
    if (ingang == Ingang.tlsBuiten) {
      _publiekIngang?.geldig(req.connectionInfo);
      final nee = weigerVanBuiten(path, req.method);
      if (nee != null) return _weigerVanBuiten(req, nee);
    }

    switch (path) {
      case '/api/catalog':
        return _catalog(req);
      case '/api/library/artists':
        return _json(res, [for (final a in catalog.snapshot().catalog.artists) a.toJson()]);
      case '/api/library/albums':
        return _json(res, [for (final a in catalog.snapshot().catalog.albums) a.toJson()]);
      case '/api/library/tracks':
        return _tracks(req);
      case '/api/album/facts':
        return _albumFacts(req);
      case '/api/search':
        return _json(res, catalog.search(req.uri.queryParameters['q'] ?? '').toJson());
      case '/api/state':
        return _state(req);
      case '/api/state/ops':
        return _stateOps(req);
      case '/api/events':
        return _events(req);
      case '/api/cast/devices':
        return _json(res, await cast.devices());
      case '/api/cast/play':
        return _castPlay(req);
      case '/api/cast/requeue':
        return _castRequeue(req);
      case '/api/cast/control':
        return _castControl(req, ingang);
      case '/api/cast/status':
        // GET with the id in the query: a phone polls this while a progress bar is on screen, and
        // a body on every poll is needless ceremony.
        return _json(
            res,
            await cast.status(req.uri.queryParameters['deviceId'] ?? '',
                withVolume: req.uri.queryParameters['volume'] == '1'));
      case '/api/online/search':
        return _onlineSearch(req);
      case '/api/online/tracklist':
        return _onlineTracklist(req);
      case '/api/online/download':
        return _onlineDownload(req);
      case '/api/soulseek/search':
        return _soulseekSearch(req);
      case '/api/soulseek/download':
        return _soulseekDownload(req);
      case '/api/soulseek/download-album':
        return _soulseekDownloadAlbum(req);
      case '/api/jobs':
        return _json(res, {'jobs': jobsSnapshot()});
      case '/api/jobs/cancel':
        return _jobCancel(req);
      case '/api/jobs/clear':
        return _jobsClear(req);
      case '/api/jobs/stopwens':
        return _jobStopWens(req);
      case '/api/rutracker/sessie':
        return _rutrackerSessie(req);
      case '/api/config':
        return _config(req);
      case '/api/uitwijk':
        return _uitwijk(req);
      case '/api/corrections':
        return _corrections(req);
      case '/api/move/plan':
        return _movePlan(req);
      case '/api/move/apply':
        return _moveApply(req);
      case '/api/update':
        return _update(req, ingang);
      case '/api/radio':
        return _radio(req);
      case '/api/diag/warmte':
        return _warmte(req);
    }

    if (path.startsWith('/stream/')) return _stream(req);
    if (path.startsWith('/art/')) return _art(req);
    if (path.startsWith('/waarom/')) return _waarom(req);

    res.statusCode = HttpStatus.notFound;
    return res.close();
  }

  /// Eén keer per sessie: misschien staan de koppelingen wél op schijf en niet in het geheugen.
  ///
  /// **Waarom dit bestaat.** Op 30-08-2026 weigerde deze server élk verzoek — ook met de gedeelde
  /// sleutel die gewoon in `settings.json` stond — en `koppeling.log` bevatte die hele dag geen
  /// regel. Van buiten viel niet vast te stellen of hij nul koppelingen had, een lege sleutel, of
  /// allebei; van binnen was er niemand die het nakeek. Een telefoon die er zo uit ligt komt er uit
  /// zichzelf nooit meer in: het inlezen gebeurt één keer, bij het opstarten.
  ///
  /// Dit leest hetzelfde bestand dat hij bij het opstarten had moeten lezen. Er komt dus geen enkele
  /// koppeling bij die er niet al was — het is een herstelpoging, geen achterdeur.
  bool _koppelingenHerladen = false;

  Future<bool> _herlaadKoppelingen() async {
    if (_koppelingenHerladen) return false;
    _koppelingenHerladen = true;
    final voor = grants.all.length;
    try {
      await grants.load();
    } catch (e) {
      _koppelLog?.line('KOPPELINGEN HERLADEN mislukt: $e');
      return false;
    }
    final na = grants.all.length;
    _koppelLog?.line('KOPPELINGEN HERLADEN na een weigering: $voor -> $na');
    return na > voor;
  }

  Future<bool> _authorizedOfHerstel(HttpRequest req, [Ingang ingang = Ingang.http]) async {
    if (_authorized(req, stil: true, ingang: ingang)) return true;
    // Nog één kans, en alleen de eerste keer: opnieuw inlezen en het aanbod nog eens toetsen.
    if (await _herlaadKoppelingen() && _authorized(req, stil: true, ingang: ingang)) return true;
    _authorized(req, ingang: ingang); // nu mét de regel in het logboek
    return false;
  }

  /// Voor de toetsen: welk bronadres op een thuisingang mag. Null = [magOpThuisingang].
  @visibleForTesting
  bool Function(InternetAddress bron)? bronMagThuisVoorToets;
  bool Function(InternetAddress bron)? get _bronMagThuis => bronMagThuisVoorToets;

  /// Een quotum van buiten boeken. Null = mag (en is geboekt); anders de zin voor het toestel. Thuis
  /// en via Tailscale altijd null: daar telt niets.
  String? _quotum(HttpRequest req, Quotumsoort soort, [int aantal = 1]) {
    if (_ingangVan[req] != Ingang.tlsBuiten) return null;
    final kop = req.headers.value(HttpHeaders.authorizationHeader) ?? '';
    final sleutel = kop.startsWith('Bearer ') ? kop.substring(7).trim() : '';
    final nee = quota.boek(sleutel, soort, aantal);
    if (nee != null) {
      _koppelLog?.line('QUOTUM ${soort.naam} geraakt  "${grants.grantFor(sleutel)?.deviceName ?? '?'}"  ($aantal gevraagd)');
    }
    return nee;
  }

  /// 429 met de zin uit het quotum: wat, en tot wanneer.
  Future<void> _teVeel(HttpRequest req, String zin) =>
      _json(req.response, {'error': zin}, status: HttpStatus.tooManyRequests);

  Future<void> _weigerVanBuiten(HttpRequest req, String waarom) {
    if (req.contentLength > 0 || req.headers.chunkedTransferEncoding) {
      return _rauw(req, 403, 'Forbidden', {'error': waarom});
    }
    return _json(req.response, {'error': waarom}, status: HttpStatus.forbidden);
  }

  bool _authorized(HttpRequest req, {bool stil = false, Ingang ingang = Ingang.http}) {
    final header = req.headers.value(HttpHeaders.authorizationHeader) ?? '';
    final bearer = header.startsWith('Bearer ') ? header.substring(7).trim() : '';
    final adres = req.connectionInfo?.remoteAddress;
    // Versleuteld: alleen een TLS-sleutel, en alleen in de kop. Nooit de gedeelde sleutel, nooit
    // `?token=` (een adres met een sleutel erin belandt in logboeken en geschiedenis).
    if (ingang != Ingang.http) {
      if (bearer.isNotEmpty && grants.acceptsTls(bearer)) {
        final via = ingang == Ingang.tlsBuiten ? 'buiten' : (adres == null ? null : toestelWeg(adres));
        if (grants.touch(bearer, via: via)) unawaited(grants.save());
        return true;
      }
      if (!stil) _noteerWeigering(req, bearer);
      return false;
    }
    // The query form is not laziness: a UPnP renderer and an <audio> tag both fetch the URL
    // themselves and have nowhere to put a header.
    final query = req.uri.queryParameters['token'] ?? '';
    final offered = bearer.isNotEmpty ? bearer : query;
    if (offered.isEmpty) return false;

    // Een TLS-sleutel hoort hier nooit: hij reisde nu onversleuteld. Weigeren, intrekken en melden.
    if (grants.isTlsSleutel(offered)) {
      if (!stil) {
        final g = grants.grantFor(offered);
        grants.trekSleutelIn(offered);
        unawaited(grants.save());
        _koppelLog?.line('TLS-SLEUTEL OP 47820  "${g?.deviceName ?? '?'}"  van ${adres?.address ?? '?'} — ingetrokken');
        rodeMelding.value = 'De versleutelde sleutel van "${g?.deviceName ?? 'een toestel'}" kwam onversleuteld '
            'binnen en is ingetrokken. Het toestel koppelt vanzelf opnieuw.';
      }
      return false;
    }

    // A per-device grant, or the one shared token this used to have. The legacy check stays and is
    // NOT rotated on upgrade: a device paired yesterday must keep working the moment this ships,
    // and unpairing everything at once is exactly what the old design was stuck with.
    if (grants.accepts(offered)) {
      if (grants.touch(offered, via: adres == null ? null : toestelWeg(adres))) unawaited(grants.save());
      if (grants.grantFor(offered)?.legacy ?? false) _gedeeldGebruikt(req);
      return true;
    }
    // De gedeelde sleutel, en bij twijfel die uit de instellingen.
    //
    // Dit veld wordt gezet door `applySettings`. Loopt dat mis of te laat, dan staat hier een lege
    // tekst en weigert de server ook de sleutel die gewoon in `settings.json` staat — zonder dat er
    // iets te zien is. Wat er op schijf staat is de waarheid; dit is dezelfde sleutel, niet een
    // tweede.
    final gedeeld = token.isNotEmpty ? token : (settings?.lanToken ?? '');
    if (gedeeld.isNotEmpty && _constantTimeEquals(offered, gedeeld)) {
      _gedeeldGebruikt(req);
      return true;
    }
    if (!stil) _noteerWeigering(req, offered);
    return false;
  }

  /// Waarvoor de gedeelde sleutel nog gebruikt wordt, en van waar. Eén regel per pad en adres per uur.
  ///
  /// **Waarom.** Sinds 14-10-2026 krijgt elk toestel een sleutel van zichzelf, maar de gedeelde blijft
  /// geldig: de pc zet hem zelf in elke cast-URL naar Sonos en KEF, en een toestel dat nog niet opnieuw
  /// koppelde gebruikt hem misschien ook. Het plan beperkt hem later tot wat hij werkelijk nodig
  /// heeft — en dat wordt eerst een week gemeten, hier, in plaats van geraden.
  void _gedeeldGebruikt(HttpRequest req) {
    final delen = req.uri.pathSegments;
    final soort = delen.isEmpty ? '/' : '/${delen.take(delen.length > 1 && delen[0] == 'api' ? 2 : 1).join('/')}';
    final van = req.connectionInfo?.remoteAddress.address ?? '?';
    final sleutel = '$soort $van';
    final nu = DateTime.now();
    final vorige = _gedeeldGezien[sleutel];
    if (vorige != null && nu.difference(vorige) < const Duration(hours: 1)) return;
    if (_gedeeldGezien.length > 500) _gedeeldGezien.clear();
    _gedeeldGezien[sleutel] = nu;
    _koppelLog?.line('GEDEELDE SLEUTEL  ${req.method} $soort  van $van'
        '${req.connectionInfo?.remoteAddress.isLoopback ?? false ? ' (deze pc)' : ''}');
  }

  final _gedeeldGezien = <String, DateTime>{};

  /// Eén regel per weigering, hoogstens één per tien seconden — een client die blijft pollen mag geen
  /// logboek van megabytes maken, en WarmLog schrijft synchroon met een flush per regel.
  void _noteerWeigering(HttpRequest req, String offered) {
    _geweigerd++;
    final nu = DateTime.now();
    if (nu.difference(_laatsteWeigerRegel).inSeconds < 10) return;
    _laatsteWeigerRegel = nu;
    _koppelLog?.line('GEWEIGERD ${req.uri.path}  van ${req.connectionInfo?.remoteAddress.address}'
        '  sleutel ${offered.length < 8 ? "(kort)" : "${offered.substring(0, 4)}…"}'
        '  koppelingen in geheugen: ${grants.all.length}'
        '  gedeelde sleutel: ${token.isEmpty ? "LEEG" : "${token.substring(0, 4)}… (${token.length})"}'
        '  totaal geweigerd deze sessie: $_geweigerd');
  }

  /// Not `==`. Comparing a secret with an early-exit comparison leaks, through timing, how much of
  /// a guess was right — which is the one thing a guesser needs.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<void> _catalog(HttpRequest req) async {
    final snap = catalog.snapshot();
    final res = req.response;
    // A client that already has this version gets 304 and no body. With a library of tens of
    // thousands of tracks that is the difference between a sync costing megabytes and costing
    // nothing, which matters when four devices re-check every time they wake up.
    if (req.headers.value(HttpHeaders.ifNoneMatchHeader) == snap.etag) {
      res.statusCode = HttpStatus.notModified;
      res.headers.set(HttpHeaders.etagHeader, snap.etag);
      return res.close();
    }
    res.statusCode = HttpStatus.ok;
    res.headers
      ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8')
      ..set(HttpHeaders.etagHeader, snap.etag);
    // Ingepakt als de client dat aankan.
    //
    // `autoCompress` staat serverbreed uit, en met reden: audio en hoezen zijn al gecomprimeerd en
    // die nog eens door gzip halen kost alleen rekentijd. Maar dat zette het óók uit voor dit
    // antwoord — het enige dat groot én goed samendrukbaar is. Deze JSON is megabytes, en de
    // cloudkopie in dit project meet zelf dat diezelfde tekst ongeveer vijfvoudig comprimeert. Vier
    // toestellen betaalden dat na elke wijziging vijfvoudig te veel over wifi.
    //
    // Dus hier expliciet, alleen voor de catalogus. De ETag blijft die van de ONgecomprimeerde
    // inhoud, zodat een 304 precies hetzelfde blijft betekenen; `Vary` staat erbij zodat niets
    // onderweg een ingepakt antwoord aan een client geeft die er niet om vroeg.
    final magInpakken =
        (req.headers.value(HttpHeaders.acceptEncodingHeader) ?? '').toLowerCase().contains('gzip');
    final lijf = magInpakken ? snap.gzipJson : snap.json;
    if (magInpakken) res.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
    res.headers.set(HttpHeaders.varyHeader, HttpHeaders.acceptEncodingHeader);
    res.headers.contentLength = lijf.length;
    res.add(lijf);
    return res.close();
  }

  /// What this record IS — its pressing, the label's tracklist, what is missing.
  ///
  /// The PC answers this so that no other device ever has to. Before, every device ran its own
  /// MusicBrainz search on every album open: four devices browsing meant four independent
  /// six-request chains against the same anonymous one-per-second budget, each with its own cache,
  /// none of them helping the others. Now the answer is worked out once, here, and handed out.
  ///
  /// Resolved on demand when it is not yet known, rather than 404ing. Otherwise a client could only
  /// see facts for albums somebody had already opened ON the PC, which is not a rule anyone could
  /// predict from the outside.
  Future<void> _albumFacts(HttpRequest req) async {
    final res = req.response;
    final id = req.uri.queryParameters['albumId'] ?? '';
    final album = catalog.album(id);
    if (album == null) return _json(res, {'error': 'unknown album'}, status: HttpStatus.notFound);

    final uid = library.uidOf(album);
    final hash = library.trackSetHashFor(album);
    var facts = library.facts.get(uid);

    if (needsResolve(facts,
        trackSetHash: hash,
        nowMs: DateTime.now().millisecondsSinceEpoch,
        pinnedMbid: library.pinnedMbid(album),
        pinned: library.pinnedRelease(album),
        // Null on a client, which has no files to fingerprint anyway.
        canHear: settings != null && canHear(settings!),
        force: req.uri.queryParameters['force'] == '1')) {
      final mb = musicbrainz;
      final s = settings;
      if (mb != null && s != null && uid.isNotEmpty) {
        // Nooit langer dan vier seconden laten wachten. Een toestel krijgt dan wat er al bekend is
        // — of niets, en dan toont het zijn eigen nummers — terwijl de zoektocht hier doorloopt en
        // bewaard wordt. Gemeten op 12-09-2026: mediaan 84 ms, langste 1,9 s. Dit knipt alleen de
        // staart eraf, en die staart stond op het scherm van een telefoon.
        final zoek = resolveAlbumFacts(album,
                uid: uid,
                trackSetHash: hash,
                mb: mb,
                settings: s,
                pinnedMbid: library.pinnedMbid(album),
                pinned: library.pinnedRelease(album))
            .then<AlbumFacts?>((verse) {
              library.facts.put(verse, folder: library.sidecarFolderFor(album));
              return verse;
            })
            .catchError((_) => null);
        facts = await zoek.timeout(const Duration(seconds: 4), onTimeout: () => facts);
      }
    }

    // Nothing known and nothing able to find out — say so at once. A client that gets this shows
    // the tracks it has, which is what it showed before any of this existed.
    if (facts == null) return _json(res, {'error': 'no facts'}, status: HttpStatus.notFound);

    // Cheap to revalidate: the body is a tracklist, and it changes about as often as the record
    // does. A client that already has this version pays a few bytes.
    final etag = '"$uid-${facts.updatedMs}"';
    if (req.headers.value(HttpHeaders.ifNoneMatchHeader) == etag) {
      res.statusCode = HttpStatus.notModified;
      res.headers.set(HttpHeaders.etagHeader, etag);
      return res.close();
    }
    res.headers.set(HttpHeaders.etagHeader, etag);
    return _json(res, facts.toJson());
  }

  Future<void> _tracks(HttpRequest req) async {
    final all = catalog.snapshot().catalog.tracks;
    final albumId = req.uri.queryParameters['albumId'];
    final artistId = req.uri.queryParameters['artistId'];
    final filtered = all.where((t) =>
        (albumId == null || t.albumId == albumId) && (artistId == null || t.artistId == artistId));
    return _json(req.response, [for (final t in filtered) t.toJson()]);
  }

  /// Trade a six-digit code for a token of this device's own.
  ///
  /// Answers exactly the same way for a wrong code and for pairing not being open at all, so
  /// nothing on the network can work out whether a code is currently on screen.
  ///
  /// **Sinds 14-10-2026 een eigen sleutel, niet de gedeelde.** Hier ging de gedeelde sleutel de deur
  /// uit — dezelfde die in elke cast-URL naar Sonos en KEF staat, en die niet per toestel in te
  /// trekken is. Nu krijgt elk toestel een rij en een sleutel van zichzelf. Een toestel van vóór deze
  /// versie stuurt geen id mee; dan maakt de pc er een (zelfde vorm als `device_identity.dart`).
  Future<void> _pair(HttpRequest req, {bool metTls = false}) async {
    if (req.method != 'POST') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      return req.response.close();
    }
    final body = await _leesLijf(req, lijfZonderSleutel);
    if (body == null) return;
    final decoded = jsonDecode(body.isEmpty ? '{}' : body);
    final map = decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
    final opgegeven = map['deviceId'];
    if (opgegeven != null && (opgegeven is! String || !geldigToestelId(opgegeven))) {
      return _json(req.response, {'error': 'Dit toestel stuurde een ongeldig id mee.'},
          status: HttpStatus.badRequest);
    }
    if (!pairing.redeem((map['code'] ?? '').toString())) {
      req.response.statusCode = HttpStatus.forbidden;
      return req.response.close();
    }
    final id = (opgegeven as String?) ?? generateDeviceToken();
    final naam = schoneToestelnaam(map['deviceName']);
    final grant = grants.nieuweSleutel(
      deviceId: id,
      deviceName: naam,
      platform: schoneToestelnaam(map['platform'], leeg: ''),
      metTls: metTls,
    );
    await grants.save();
    _meldNieuweSleutel(req, grant, via: 'code');
    if (metTls) _tlsIngang?.geldig(req.connectionInfo);
    return _json(req.response, {
      'token': grant.token,
      if (grant.tlsToken != null) 'tlsToken': grant.tlsToken,
      'deviceId': id,
      'name': deviceName(),
      'trackCount': library.tracks.length,
    });
  }

  /// De eenmalige ruil (alleen op 47822): de huidige HTTP-sleutel van dit toestel in het lijf, een
  /// TLS-sleutel terug. Zie [GrantStore.ruil] voor wie mag.
  ///
  /// **Een 409 is een alarm.** Het echte toestel ruilt hoogstens één keer. Heeft het toestel al een
  /// TLS-sleutel en vraagt iemand opnieuw met zijn HTTP-sleutel, dan had iemand anders die HTTP-sleutel
  /// (afgeluisterd op het netwerk thuis) — of het toestel zelf zijn TLS-sleutel kwijt. Hoe dan ook:
  /// rood op de pc, met wat te doen.
  Future<void> _ruil(HttpRequest req) async {
    if (req.method != 'POST') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      return req.response.close();
    }
    final van = req.connectionInfo?.remoteAddress.address ?? '?';
    final body = await _leesLijf(req, lijfZonderSleutel);
    if (body == null) return;
    Map<String, dynamic> map;
    try {
      final d = jsonDecode(body.isEmpty ? '{}' : body);
      map = d is Map ? d.cast<String, dynamic>() : <String, dynamic>{};
    } on FormatException {
      map = <String, dynamic>{};
    }
    final http = (map['sleutel'] ?? '').toString();
    final gedeeld = token.isNotEmpty ? token : (settings?.lanToken ?? '');
    if (http.isNotEmpty && gedeeld.isNotEmpty && _constantTimeEquals(http, gedeeld)) {
      _koppelLog?.line('RUIL  geweigerd: de gedeelde sleutel, van $van');
      return _json(req.response, {'error': 'De gedeelde sleutel kan niet omgeruild worden.'}, status: HttpStatus.forbidden);
    }
    final r = grants.ruil(http);
    switch (r.status) {
      case 200:
        remming.gelukt(van);
        // Eerst naar schijf, dan pas teruggeven: een pc die daarna omvalt, mag geen toestel achterlaten
        // met een sleutel die hij nooit gekend heeft.
        await grants.save();
        _tlsIngang?.geldig(req.connectionInfo);
        _koppelLog?.line('RUIL  "${r.grant!.deviceName}" gebruikt nu een versleutelde verbinding (van $van)');
        // Een nieuwe sleutel is een melding op de pc, ook deze — met [Intrekken] voor die ene sleutel.
        grants.nieuweSleutelMelding.value = SleutelMelding(
          deviceId: r.grant!.deviceId,
          deviceName: r.grant!.deviceName,
          bestaand: true,
          via: 'ruil',
          van: van,
          sleutel: r.tls!,
        );
        return _json(req.response, {'tlsToken': r.tls});
      case 409:
        _koppelLog?.line('RUIL  NOG EENS voor "${r.grant?.deviceName ?? '?'}" (van $van) — geweigerd, rood gemeld');
        rodeMelding.value = 'De sleutel van "${r.grant?.deviceName ?? 'een toestel'}" werd al door een ander toestel '
            'omgeruild. Trek die sleutel in bij Instellingen → Delen → Toestellen.';
        return _json(req.response, {
          'error': 'De sleutel van dit toestel werd al door een ander toestel omgeruild. Trek die sleutel in op je pc.'
        }, status: HttpStatus.conflict);
      default:
        final wacht = remming.naMislukt(van);
        if (wacht > Duration.zero) await Future<void>.delayed(wacht);
        _koppelLog?.line('RUIL  geweigerd (${r.status}) van $van');
        return _json(req.response, {'error': 'Deze sleutel kan niet omgeruild worden.'}, status: r.status);
    }
  }

  /// Elke nieuwe sleutel: één regel in `koppeling.log` en een melding op de pc. Zie [SleutelMelding].
  void _meldNieuweSleutel(HttpRequest req, DeviceGrant grant, {required String via}) {
    final van = req.connectionInfo?.remoteAddress.address ?? '?';
    final bestaand = grant.oudereTokens.isNotEmpty;
    _koppelLog?.line('${bestaand ? 'NIEUWE SLEUTEL' : 'NIEUW TOESTEL'}  "${grant.deviceName}"'
        '  via $via  van $van  (${grant.oudereTokens.length} eerdere sleutel(s) blijven geldig)');
    grants.nieuweSleutelMelding.value = SleutelMelding(
      deviceId: grant.deviceId,
      deviceName: grant.deviceName,
      bestaand: bestaand,
      via: via,
      van: van,
      sleutel: grant.token,
    );
  }

  /// Toegang op grond van het ACCOUNT, over het lokale netwerk, zonder Firestore.
  ///
  /// Het toestel stuurt zijn verse inlogsleutel; deze pc vraagt bij Google van wie die is en
  /// vergelijkt dat met zijn eigen account. Zie `accountkoppeling.dart` voor de beslissing zelf en
  /// waarom die apart staat.
  ///
  /// **Elke weigering wordt opgeschreven.** Dit is een deur naar je hele bibliotheek; als er ooit
  /// iets vreemds langskomt hoort dat in `koppeling.log` te staan en niet alleen in een 403 die
  /// niemand ziet.
  Future<void> _pairCloud(HttpRequest req, {bool metTls = false}) async {
    if (req.method != 'POST') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      return req.response.close();
    }
    final opzoeker = uidVanSleutel;
    final mijn = (cloudUid?.call() ?? '').trim();
    if (opzoeker == null) {
      // Deze bouw kent geen Firebase. Dan is de code de enige weg, en dat is een antwoord.
      _koppelLog?.line('PAIR-CLOUD  geweigerd: deze pc kent geen account-inlog');
      return _json(req.response, {'error': koppelweigering(uidVanSleutel: '', uidVanPc: '')},
          status: HttpStatus.forbidden);
    }

    final body = await _leesLijf(req, lijfZonderSleutel);
    if (body == null) return;
    final decoded = jsonDecode(body.isEmpty ? '{}' : body);
    final map = decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
    final sleutel = (map['idToken'] ?? '').toString();

    // Het eigen id van het toestel, en alleen een geldig: één rij per toestel, zodat intrekken werkt.
    // Hier stond `deviceId ?? naam` — een toestel zonder id kreeg zijn NAAM als id, en twee gsm's met
    // dezelfde naam deelden dan één sleutel. En nooit `legacy`: die rij is de gedeelde sleutel.
    // Vóór Google: een verzoek dat toch geweigerd wordt, kost geen opzoeking.
    final id = map['deviceId'];
    if (id is! String || !geldigToestelId(id)) {
      _koppelLog?.line('PAIR-CLOUD  geweigerd: geen geldig toestel-id meegestuurd');
      return _json(req.response, {'error': 'Dit toestel stuurde geen geldig id mee. Werk de app bij.'},
          status: HttpStatus.badRequest);
    }

    // De eerste blik: rommel krijgt meteen nee, zonder Google en zonder het budget te raken.
    final project = (firebaseProject?.call() ?? '').trim();
    if (project.isNotEmpty) {
      final waarom = inlogsleutelFout(sleutel, project: project);
      if (waarom != null) {
        _koppelLog?.line('PAIR-CLOUD  geweigerd vóór Google: $waarom');
        return _json(req.response,
            {'error': 'Je inlogsleutel klopt niet ($waarom). Log opnieuw in en probeer het nog eens.'},
            status: HttpStatus.forbidden);
      }
    }
    final weerOm = koppelBudget.neem();
    if (weerOm != null) {
      final om = '${weerOm.hour.toString().padLeft(2, '0')}:${weerOm.minute.toString().padLeft(2, '0')}';
      _koppelLog?.line('PAIR-CLOUD  geremd: te veel pogingen, weer vanaf $om');
      return _json(
          req.response,
          {
            'error': 'Er wordt nu te vaak geprobeerd te koppelen via je account. '
                'Probeer het om $om opnieuw, of koppel met de zes cijfers op de pc.'
          },
          status: HttpStatus.tooManyRequests);
    }

    String vanWie;
    try {
      vanWie = await opzoeker(sleutel);
    } catch (e) {
      // Google onbereikbaar. Dat is geen weigering maar een "nu niet", en het verschil hoort op het
      // scherm van het toestel te staan -- anders ga je een wachtwoord zoeken dat prima was.
      _koppelLog?.line('PAIR-CLOUD  niet na te kijken: $e');
      return _json(
        req.response,
        {'error': 'Je pc kon je inlog niet nakijken bij Google. Probeer het zo nog eens.'},
        status: HttpStatus.serviceUnavailable,
      );
    }

    if (!magKoppelenOpAccount(uidVanSleutel: vanWie, uidVanPc: mijn)) {
      _koppelLog?.line('PAIR-CLOUD  geweigerd'
          '  sleutel van: ${vanWie.isEmpty ? "(onbekend)" : "…${vanWie.substring(vanWie.length > 6 ? vanWie.length - 6 : 0)}"}'
          '  deze pc: ${mijn.isEmpty ? "(niet ingelogd)" : "…${mijn.substring(mijn.length > 6 ? mijn.length - 6 : 0)}"}');
      return _json(req.response,
          {'error': koppelweigering(uidVanSleutel: vanWie, uidVanPc: mijn)},
          status: HttpStatus.forbidden);
    }

    final naam = schoneToestelnaam(map['deviceName']);
    final grant = grants.nieuweSleutel(
      deviceId: id,
      deviceName: naam,
      platform: schoneToestelnaam(map['platform'], leeg: ''),
      metTls: metTls,
    );
    // Eerst naar schijf, dan pas teruggeven. Andersom zou een pc die daarna omvalt een toestel
    // achterlaten met een sleutel waar hij nooit meer van gehoord heeft.
    await grants.save();
    _meldNieuweSleutel(req, grant, via: 'account');
    if (metTls) _tlsIngang?.geldig(req.connectionInfo);
    return _json(req.response, {
      'token': grant.token,
      if (grant.tlsToken != null) 'tlsToken': grant.tlsToken,
      'name': deviceName(),
      'trackCount': library.tracks.length,
    });
  }

  Future<void> _castPlay(HttpRequest req) async {
    if (req.method != 'POST') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      return req.response.close();
    }
    final map = await _body(req);
    if (map == null) return;
    try {
      await cast.play(
        (map['deviceId'] ?? '') as String,
        [for (final id in (map['trackIds'] as List? ?? const [])) id.toString()],
        (map['index'] as int?) ?? 0,
      );
      return _json(req.response, {'ok': true});
    } catch (e) {
      // A speaker that has gone off the network, or a track that isn't there any more. The
      // client shows this, so it must read like something a person can act on.
      return _json(req.response, {'error': '$e'}, status: HttpStatus.badRequest);
    }
  }

  /// Dezelfde nummers in een andere volgorde, terwijl het lopende nummer doorspeelt.
  Future<void> _castRequeue(HttpRequest req) async {
    if (req.method != 'POST') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      return req.response.close();
    }
    final map = await _body(req);
    if (map == null) return;
    try {
      await cast.requeue(
        (map['deviceId'] ?? '') as String,
        [for (final id in (map['trackIds'] as List? ?? const [])) id.toString()],
        (map['index'] as int?) ?? 0,
      );
      return _json(req.response, {'ok': true});
    } catch (e) {
      return _json(req.response, {'error': '$e'}, status: HttpStatus.badRequest);
    }
  }

  Future<void> _castControl(HttpRequest req, [Ingang ingang = Ingang.http]) async {
    if (req.method != 'POST') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      return req.response.close();
    }
    final map = await _body(req);
    if (map == null) return;
    // Van buiten: wat al speelt pauzeren, stoppen of zachter zetten — niet thuis iets laten afspelen.
    if (ingang == Ingang.tlsBuiten && !const {'pause', 'stop', 'volume'}.contains(map['action'])) {
      return _json(req.response, {'error': 'Op een speaker thuis iets afspelen kan alleen thuis of via Tailscale.'},
          status: HttpStatus.forbidden);
    }
    try {
      await cast.control(
        (map['deviceId'] ?? '') as String,
        (map['action'] ?? '') as String,
        value: map['value'] as int?,
      );
      return _json(req.response, {'ok': true});
    } catch (e) {
      return _json(req.response, {'error': '$e'}, status: HttpStatus.badRequest);
    }
  }

  /// Hoeveel een verzoek ZONDER sleutel mag meesturen (`/pair`, `/pair-cloud`): zes cijfers of een
  /// inlogsleutel van ongeveer een kilobyte, met ruimte.
  static const kLijfZonderSleutel = 4 * 1024;

  /// En met een geldige sleutel. Ruim, want een catalogusbewerking of een rij favorieten kan groot
  /// zijn: dit is een grens tegen een lijf dat het geheugen volloopt, geen quotum.
  static const kLijfMetSleutel = 8 * 1024 * 1024;

  /// Voor de toetsen, die de grens niet met acht megabyte willen bewijzen.
  @visibleForTesting
  int lijfZonderSleutel = kLijfZonderSleutel;
  @visibleForTesting
  int lijfMetSleutel = kLijfMetSleutel;

  /// Het lijf van een verzoek, hoogstens [max] bytes. Daarboven null, en dan is er al 413 gestuurd.
  ///
  /// **Waarom dit er moest komen.** Elke route las het lijf met `utf8.decoder.bind(req).join()`:
  /// onbegrensd, in het geheugen. Ook `/pair` en `/pair-cloud`, die zonder sleutel open staan — wie
  /// het netwerk op kon, kon de pc zo een gigabyte laten bufferen. Een lijf dat zijn lengte vooraf
  /// opgeeft wordt meteen geweigerd, zonder één byte te lezen; een lijf zonder lengte wordt tijdens
  /// het lezen afgebroken zodra het over de grens gaat.
  Future<String?> _leesLijf(HttpRequest req, int max) async {
    if (req.contentLength > max) {
      await _teGroot(req, max);
      return null;
    }
    final bytes = BytesBuilder(copy: false);
    var teGroot = false;
    await for (final stuk in req) {
      bytes.add(stuk);
      if (bytes.length > max) {
        teGroot = true;
        break;
      }
    }
    if (teGroot) {
      await _teGroot(req, max);
      return null;
    }
    try {
      return utf8.decode(bytes.takeBytes());
    } on FormatException {
      await _json(req.response, {'error': 'Dat verzoek is geen geldige tekst.'},
          status: HttpStatus.badRequest);
      return null;
    }
  }

  /// 413, rechtstreeks op de verbinding, en dan de verbinding dicht.
  ///
  /// **Niet via `response.close()`.** Gemeten op 14-10-2026 (`scratchpad/meet_413`): Dart houdt een
  /// antwoord vast tot het aangekondigde lijf helemaal binnen is. Een verzoek dat "10 MB" aankondigt
  /// en niets stuurt, kreeg na drie seconden nog geen antwoord — en hield de verbinding zo lang open
  /// als de afzender wou. Via `detachSocket` kwam de 413 na 2 ms aan.
  Future<void> _teGroot(HttpRequest req, int max) => _rauw(req, 413, 'Request Entity Too Large',
      {'error': 'Dat verzoek is te groot (meer dan ${max ~/ 1024} KB).'});

  /// Een antwoord rechtstreeks op de verbinding, en dan de verbinding dicht. Voor als het lijf van
  /// het verzoek niet gelezen wordt: dan houdt `response.close()` het antwoord vast (zie [_teGroot]).
  Future<void> _rauw(HttpRequest req, int status, String woord, Map<String, dynamic> body) async {
    final lijf = utf8.encode(jsonEncode(body));
    final sok = await req.response.detachSocket(writeHeaders: false);
    try {
      sok.add(utf8.encode('HTTP/1.1 $status $woord\r\n'
          'Content-Type: application/json; charset=utf-8\r\n'
          'Content-Length: ${lijf.length}\r\n'
          'Connection: close\r\n\r\n'));
      sok.add(lijf);
      await sok.flush().timeout(const Duration(seconds: 5));
    } catch (_) {/* de afzender is al weg */} finally {
      sok.destroy();
    }
  }

  /// Null als het lijf te groot of geen tekst was; dan is het antwoord al verstuurd.
  Future<Map<String, dynamic>?> _body(HttpRequest req) async {
    final text = await _leesLijf(req, lijfMetSleutel);
    if (text == null) return null;
    final decoded = jsonDecode(text.isEmpty ? '{}' : text);
    return decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
  }

  Future<void> _state(HttpRequest req) async {
    final since = int.tryParse(req.uri.queryParameters['since'] ?? '');
    // Nothing durable has changed since the client last looked. The position may well have, so
    // it rides along — it is a handful of bytes and saves a second round trip.
    if (since != null && since == state.rev) {
      return _json(req.response, {
        'rev': state.rev,
        'progressRev': state.progressRev,
        'unchanged': true,
        'progress': state.progress.toJson(),
      });
    }
    return _json(req.response, state.snapshot());
  }

  Future<void> _stateOps(HttpRequest req) async {
    if (req.method != 'POST') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      return req.response.close();
    }
    final body = await _leesLijf(req, lijfMetSleutel);
    if (body == null) return;
    final decoded = jsonDecode(body.isEmpty ? '{}' : body);
    final map = decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
    final result = state.applyOps(
      (map['ops'] as List?) ?? const [],
      deviceId: (map['deviceId'] ?? '') as String,
      deviceName: (map['deviceName'] ?? '') as String,
    );
    return _json(req.response, result);
  }

  /// Server-sent events: the PC tells every device the moment something changes, instead of four
  /// devices asking every few seconds whether anything did.
  Future<void> _events(HttpRequest req) async {
    final res = req.response;
    res.statusCode = HttpStatus.ok;
    res.headers
      ..set(HttpHeaders.contentTypeHeader, 'text/event-stream; charset=utf-8')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..set(HttpHeaders.connectionHeader, 'keep-alive')
      // Nginx and friends buffer by default, which turns an event stream into silence.
      ..set('X-Accel-Buffering', 'no');
    res.bufferOutput = false;

    void send(Map<String, dynamic> data) {
      try {
        res.write('data: ${jsonEncode(data)}\n\n');
      } catch (_) {/* client gone; the done-handler below cleans up */}
    }

    send({'rev': state.rev, 'progressRev': state.progressRev, 'progress': state.progress.toJson()});

    final sub = state.changes.listen(send);
    // A silent connection is indistinguishable from a dead one, and home routers drop idle TCP.
    final beat = Timer.periodic(const Duration(seconds: 20), (_) {
      try {
        res.write(': ping\n\n');
      } catch (_) {}
    });

    // Held open until the client hangs up.
    await res.done.catchError((Object _) {});
    await sub.cancel();
    beat.cancel();
  }

  /// Waarom een nummer niet open te krijgen is — gevraagd door een toestel dat het NIET zelf kan
  /// zien.
  ///
  /// **Waarom dit bestaat.** [waaromNietTeOpenen] kijkt naar de bytes van een bestand, en dat kan
  /// alleen de machine waar dat bestand op staat. Een telefoon die van de pc streamt heeft geen pad
  /// maar een adres; daar viel niets te kijken, en dus bleef mpv's eigen zin staan. Op 14-09-2026
  /// stond er om 19:15 en nog eens om 20:08 in `speler.log` van de telefoon "Error decoding audio"
  /// bij Sommeil — een bestand waarvan hier op schijf te zien is dat er 0,13 % van het geluid in
  /// staat. De pc wist het, en werd niet gevraagd.
  ///
  /// Geeft 204 als er niets bijzonders te melden valt, en dat is verreweg het meest voorkomende
  /// antwoord: de meeste mislukte openingen liggen aan de verbinding en niet aan het bestand. Dan
  /// is mpv's eigen woord nog altijd beter dan een verzonnen verklaring.
  Future<void> _waarom(HttpRequest req) async {
    final res = req.response;
    // Zelfde vorm als `/stream/<id>`: de extensie mag erbij staan en hoort er niet bij het zoeken.
    final rauw = Uri.decodeComponent(req.uri.pathSegments.last);
    final punt = rauw.lastIndexOf('.');
    final id = punt > 0 ? rauw.substring(0, punt) : rauw;

    final track = catalog.track(id);
    if (track == null) {
      res.statusCode = HttpStatus.notFound;
      return res.close();
    }
    RandomAccessFile? raf;
    try {
      final f = File(track.path);
      if (!f.existsSync()) return _json(res, {'reden': 'het bestand staat er niet meer'});
      final grootte = f.lengthSync();
      var kop = const <int>[];
      // Vierenzestig, net als in `player.dart`: de STREAMINFO van een FLAC loopt tot byte 42.
      if (grootte > 0) {
        raf = f.openSync();
        kop = raf.readSync(64);
      }
      final reden = waaromNietTeOpenen(naam: track.path, bytes: grootte, kop: kop);
      if (reden == null) {
        res.statusCode = HttpStatus.noContent;
        return res.close();
      }
      return _json(res, {'reden': reden});
    } catch (_) {
      // Niet kunnen kijken is geen uitspraak.
      res.statusCode = HttpStatus.noContent;
      return res.close();
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {}
    }
  }

  Future<void> _stream(HttpRequest req) async {
    // `/stream/<id>` and `/stream/<id>.flac` are the same track. The extension is there for the
    // Apple clients: AVFoundation types an asset by its path, and refuses one it can't place.
    final raw = Uri.decodeComponent(req.uri.pathSegments.last);
    final dot = raw.lastIndexOf('.');
    final id = dot > 0 ? raw.substring(0, dot) : raw;

    final track = catalog.track(id);
    if (track == null) {
      req.response.statusCode = HttpStatus.notFound;
      return req.response.close();
    }
    final file = File(track.path);
    if (!await file.exists()) {
      req.response.statusCode = HttpStatus.notFound;
      return req.response.close();
    }

    // `?maxRate=` is how a speaker with a ceiling gets a version it can actually play — Sonos
    // stops at 48 kHz and skips anything above rather than downsampling it. Only the cast path
    // ever asks for this; every other client gets the file untouched.
    final maxRate = int.tryParse(req.uri.queryParameters['maxRate'] ?? '');
    // `?maxBits=` is de tweede as, en die ontbrak. Een KEF LS50 Wireless II neemt 384 kHz zonder
    // morren maar houdt op bij 24 bit; een bestand van 32 bit bleef daar stil, precies zoals een
    // hi-res plaat op een Sonos stil blijft. Zelfde soort mislukking, andere grens.
    final maxBits = int.tryParse(req.uri.queryParameters['maxBits'] ?? '');
    // Dezelfde regel als aan de andere kant, en letterlijk dezelfde functie: wat niet overschreden
    // wordt blijft staan, en een onbekende diepte is geen te grote diepte. Hier stond een tweede
    // kopie van dat rekensommetje; twee kopieën van een regel lopen uiteen zodra er één bijgesteld
    // wordt, en deze is degene die nagemeten is (`test/castgrenzen_test.dart`).
    final vanSpeaker = req.uri.queryParameters['cast'] == '1';
    // Een toestel (geen speaker) dat om een plafond vraagt. Dat doet het ook als de catalogus de maat
    // NIET weet — zie `metStand` — en dan meet de pc het bestand hier zelf na in plaats van op een
    // nul te beslissen. Een speaker blijft precies zoals hij was.
    final toestelVraagt = !vanSpeaker && (maxRate != null || maxBits != null);
    var rate = track.sampleRate;
    var bits = track.bitsPerSample;
    if (toestelVraagt && (rate <= 0 || bits <= 0)) {
      final maat = await transcoder.meet(file);
      if (rate <= 0) rate = maat?.rate ?? 0;
      if (bits <= 0) bits = maat?.bits ?? 0;
    }
    var grens = castGrenzen(
      sampleRate: rate,
      bits: bits,
      maxSampleRate: maxRate ?? 0,
      maxBitDepth: maxBits ?? 0,
      // Ook na het nameten onbekend: dan het plafond. Een te grote stroom over 5G merk je pas als
      // je bundel op is; een onnodige omzetting kost een halve seconde.
      onbekendIsTeVeel: toestelVraagt,
    );
    // Wie om een plafond vraagt kreeg van `metStand` een adres op `.flac`. Dan moet er ook FLAC
    // uitkomen, ook als de maat al binnen het plafond zit: een AIFF achter een `.flac`-adres weigert
    // AVFoundation, en ongecomprimeerd is het over 5G bovendien bijna het dubbele.
    if (toestelVraagt && !grens.omzetten && track.ext.toLowerCase() != 'flac') {
      grens = (omzetten: true, rate: grens.rate, bits: grens.bits);
    }
    if (grens.omzetten) {
      // Een gekoppeld toestel vraagt om KLEIN (het gaat over iemands databundel), een speaker om
      // SNEL (de kopie wordt na het spelen weggegooid). Zie [Omzetrecept].
      return _streamResampled(req, file, grens.rate, grens.bits <= 0 ? 24 : grens.bits,
          recept: vanSpeaker ? receptCast : receptStroom, track: track);
    }
    _stroomRegel(req, track,
        'origineel${maxRate == null ? '' : ' (vraag $maxRate/${maxBits ?? '-'}, valt eronder)'}  ${_mb(track.sizeBytes)}');
    return serveFile(req, file, contentType: mimeForExt(track.ext));
  }

  /// De omgezette versie serveren — als BESTAND, nooit als pijp.
  ///
  /// Nagemeten tegen de Sonos Amp: een omzetting die al coderend doorgestuurd wordt gaat zonder
  /// Content-Length de deur uit, en de FLAC erin heeft een onbekend aantal monsters. De speaker
  /// neemt de URL aan, zegt PLAYING, laat zijn lengte oplopen en komt nooit van 0:00:00 — hij leest
  /// het als een eindeloze radiostroom. Een bestand heeft een lengte, een echte kop en Range, en
  /// speelt gewoon. Daarom loopt dit via [serveFile]: het spoelen komt er gratis bij.
  ///
  /// **De pijp die hier als terugval onder hing is weg.** Hij was de oude weg, hij kon niet spoelen
  /// en hij kon niet zeggen hoe lang iets was — en zolang hij bleef staan was "eerst omzetten, dan
  /// sturen" een keuze in plaats van een eigenschap. Lukt het omzetten niet, dan gaat het origineel
  /// de deur uit: dat is bij een gekoppeld toestel gewoon de oude situatie, en bij een speaker met
  /// een plafond een nummer dat overgeslagen wordt — precies wat er zonder ffmpeg ook al gebeurde.
  Future<void> _streamResampled(HttpRequest req, File file, int maxRate, int maxBits,
      {Omzetrecept recept = receptCast, Track? track}) async {
    final map = recept.naam == receptCast.naam ? 'cast_cache' : 'stream_cache';
    final cache = Directory('$appDir${Platform.pathSeparator}$map');
    // Van buiten telt alleen NIEUW werk, en een geraakt plafond weigert niets: dan het origineel. Dat
    // is groter, maar het speelt — omzetten voor 5G mag nooit de reden zijn dat een nummer stilvalt.
    if (_ingangVan[req] == Ingang.tlsBuiten &&
        !transcoder.alOmgezet(file, maxSampleRate: maxRate, maxBits: maxBits, recept: recept, cacheDir: cache) &&
        _quotum(req, kQuotumOmzetten) != null) {
      if (track != null) _stroomRegel(req, track, 'quotum omzetten geraakt — origineel  ${_mb(track.sizeBytes)}');
      return serveFile(req, file, contentType: mimeForExt(track?.ext ?? 'flac'));
    }
    final klok = Stopwatch()..start();
    final klaar = await transcoder.resampleToFile(file,
        maxSampleRate: maxRate,
        maxBits: maxBits,
        recept: recept,
        cacheDir: cache);
    if (track != null) {
      final ms = klok.elapsedMilliseconds;
      _stroomRegel(
          req,
          track,
          klaar == null
              ? 'omzetten naar $maxBits/$maxRate MISLUKT na $ms ms — origineel  ${_mb(track.sizeBytes)}'
              : '${ms < 40 ? 'uit de cache' : 'omgezet'} naar $maxBits/$maxRate in $ms ms'
                  '${transcoder.soxr ? ' (soxr)' : ''}  ${_mb(klaar.lengthSync())}'
                  '${recept.naam == receptCast.naam ? '  [speaker]' : ''}');
    }
    // Het merkteken van een omzetting is bron plus recept: de naam in de cache (`_sleutel`).
    final naam = klaar?.uri.pathSegments.last ?? '';
    return serveFile(req, klaar ?? file,
        contentType: 'audio/flac', merk: naam.endsWith('.flac') ? naam.substring(0, naam.length - 5) : null);
  }


  // ── Searching and downloading, on behalf of another device ─────────────────
  //
  // The Mac and the iPad have no TorBox key, no Soulseek login and, on an iPad, nowhere to put a
  // music library anyway. So they ask this PC to do it: the search runs here, the download lands
  // here, and the finished album comes back to everyone through the catalogue that already syncs.
  // That also means one set of credentials, on the machine that already had them.

  /// What the job list looks like to another device. Only the fields a progress row shows — the
  /// live peer sockets and the fallback candidates are this machine's business.
  List<Map<String, dynamic>> jobsSnapshot() => [
        for (final j in downloads?.jobs ?? const <DownloadJob>[])
          {
            'name': j.name,
            'key': j.key,
            'progress': j.progress,
            'status': j.status,
            'detail': j.detail,
            'queuePlace': j.queuePlace,
            'canCancel': j.canCancel,
            // Zonder dit staat op de telefoon "Mislukt" in het rood boven een download die de
            // gebruiker zelf net heeft gestopt. Hier is dat onderscheid er wel — 'failed' plus
            // [DownloadJob.cancelled] — en het is het verschil tussen "er ging iets mis" en "ik
            // heb hem afgezet". Gemeten op 17-08 door hem op de telefoon te stoppen.
            'cancelled': j.cancelled,
            'trackKey': j.trackKey,
          },
      ];

  Future<Map<String, dynamic>?> _jsonBody(HttpRequest req) async {
    if (req.method != 'POST') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      await req.response.close();
      return null;
    }
    final text = await _leesLijf(req, lijfMetSleutel);
    if (text == null) return null;
    final decoded = jsonDecode(text.isEmpty ? '{}' : text);
    return decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// De metingen van een toestel in `warmte.log`. Zie `warmtemeter.dart`.
  ///
  /// Begrensd: hoogstens 60 regels van 800 tekens per keer, want dit is een logboek en geen opslag.
  /// Het toestel staat ervoor, en zijn adres, zodat de iPad en de telefoon uit elkaar te houden zijn.
  Future<void> _warmte(HttpRequest req) async {
    final body = await _jsonBody(req);
    if (body == null) return;
    String kort(Object? s, int n) {
      final t = (s is String ? s : '').replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      return t.length > n ? t.substring(0, n) : t;
    }

    final toestel = kort(body['toestel'], 80);
    final adres = req.connectionInfo?.remoteAddress.address ?? '?';
    final regels = body['regels'];
    var n = 0;
    if (regels is List) {
      for (final r in regels.take(60)) {
        _warmteLog?.line('[${toestel.isEmpty ? '?' : toestel} $adres] ${kort(r, 800)}');
        n++;
      }
    }
    return _json(req.response, {'ok': true, 'regels': n});
  }

  /// 503 with a sentence a person can read, not a bare status code: on the iPad this is the
  /// difference between "the pc can't do that" and a spinner that never stops.
  Future<void> _unavailable(HttpRequest req, String why) =>
      _json(req.response, {'error': why}, status: HttpStatus.serviceUnavailable);

  Future<void> _onlineSearch(HttpRequest req) async {
    final service = online;
    if (service == null) return _unavailable(req, 'Deze pc kan niet online zoeken.');
    final q = req.uri.queryParameters['q'] ?? '';
    if (q.trim().isEmpty) return _json(req.response, {'results': []});
    try {
      final results = await service.search(q);
      // **De stand van RuTracker reist mee.** Zonder dit stond op de telefoon "RuTracker: niet
      // bevraagd", en dat kló*pte* — maar het ging over de RuTracker van de telefoon, terwijl het
      // zoeken hier op de pc gebeurt. Alles wat de pc wist over waarom er niets binnenkwam bleef op
      // de pc. Zie ook `remote_services.dart`.
      final rt = service.rutracker;
      return _json(req.response, {
        'results': [for (final r in results) r.toJson()],
        'rutracker': {
          'fout': rt.lastError,
          'aantal': rt.laatsteAantal,
          'doorZeef': rt.laatsteDoorZeef,
          'vraag': rt.laatsteVraag,
          'ruimer': rt.laatsteRuimer,
          'geprobeerd': rt.laatstGeprobeerd,
        },
        // En hoe elke bron het deed. Zonder dit staat op de telefoon één getal en is niet te zien
        // welke tracker eraan meebetaald heeft — precies waarom "volgens mij is die bron down" hier
        // niet te bevestigen én niet te weerleggen was.
        'bronnen': {
          for (final e in service.aggregator.standen.entries)
            e.key: {'aantal': e.value.aantal, 'fout': e.value.fout},
        },
      });
    } catch (e) {
      return _unavailable(req, 'Zoeken mislukte op de pc: $e');
    }
  }

  Future<void> _onlineTracklist(HttpRequest req) async {
    final service = online;
    if (service == null) return _unavailable(req, 'Deze pc kan niet online zoeken.');
    final body = await _jsonBody(req);
    if (body == null) return;
    final fout = downloadBronFout(body);
    if (fout != null) return _json(req.response, {'error': fout}, status: HttpStatus.badRequest);
    try {
      final (torrent, files) = await service.tracklist(SearchResult.fromJson(body));
      return _json(req.response, {
        'torrentId': torrent.id,
        'files': [
          for (final f in files)
            {'id': f.id, 'name': f.name, 'shortName': f.shortName, 'size': f.size, 'mimeType': f.mimeType},
        ],
      });
    } catch (e) {
      return _unavailable(req, 'De tracklijst ophalen mislukte: $e');
    }
  }

  Future<void> _onlineDownload(HttpRequest req) async {
    final manager = downloads;
    if (manager == null) return _unavailable(req, 'Deze pc kan niet downloaden.');
    final body = await _jsonBody(req);
    if (body == null) return;
    final teVeel = _quotum(req, kQuotumDownloads);
    if (teVeel != null) return _teVeel(req, teVeel);
    final fout = startTorrentDownload(body);
    if (fout != null) return _json(req.response, {'error': fout}, status: HttpStatus.badRequest);
    return _json(req.response, {'ok': true});
  }

  Future<void> _soulseekSearch(HttpRequest req) async {
    final service = soulseek;
    if (service == null || !service.available) {
      return _unavailable(req, 'Op deze pc is Soulseek niet ingesteld.');
    }
    final q = req.uri.queryParameters['q'] ?? '';
    if (q.trim().isEmpty) return _json(req.response, {'files': []});
    try {
      final files = await service.search(q);
      return _json(req.response, {'files': [for (final f in files) f.toJson()]});
    } catch (e) {
      return _unavailable(req, 'Soulseek zoeken mislukte: $e');
    }
  }

  // ── Starting a download from a request body ────────────────────────────────
  //
  // Public because the queue worker replays exactly these bodies when the PC comes back online
  // after a device asked for something while it was off. Sharing the parsing is the point: a
  // download that was queued must land the same way as one asked for live, including the
  // authority tags — and two copies of this parsing would eventually disagree about that.

  /// The body of `POST /api/online/download`. Null when it started; otherwise why it did not —
  /// a `torrentUrl` that is not RuTracker's or Redacted's own, or something that is not a magnet
  /// (see `downloadbron.dart`). The cloud queue comes through here too, so it gets the same check.
  String? startTorrentDownload(Map<String, dynamic> body) {
    final manager = downloads;
    if (manager == null) return 'Deze pc kan niet downloaden.';
    final fout = downloadBronFout(body);
    if (fout != null) {
      debugPrint('download geweigerd: $fout');
      return fout;
    }
    final fileId = (body['fileId'] as num?)?.toInt();
    // Het gekozen bestand zoals de lijst op het toestel het toonde. Met alleen het nummer koos de
    // pc bij een torrent die via TorBox binnenkomt een ánder liedje — zie `zelfdeBestandIn`. Een
    // toestel van vóór deze versie stuurt dit niet mee; dan zoekt de pc het nummer zelf op.
    final naam = body['fileName'];
    final bestand = fileId != null && naam is String && naam.isNotEmpty
        ? TbFile(fileId, naam, body['fileShortName'] as String?, (body['fileSize'] as num?)?.toInt() ?? 0, null)
        : null;
    // Deliberately not awaited: enqueue starts the work and returns, and the caller watches
    // /api/jobs. Holding a request open for a download would time out long before it finished.
    manager.enqueue(SearchResult.fromJson(body), fileId: fileId, bestand: bestand);
    return null;
  }

  /// The body of `POST /api/soulseek/download`. False when nothing usable was in it.
  Future<bool> startSoulseekDownload(Map<String, dynamic> body) async {
    final manager = downloads;
    if (manager == null) return false;
    final candidates = <SoulseekFile>[];
    for (final c in (body['candidates'] as List? ?? const [])) {
      if (c is! Map<String, dynamic>) continue;
      final f = SoulseekFile.fromJson(c);
      if (f != null) candidates.add(f);
    }
    if (candidates.isEmpty) return false;
    // De handmatige keuze van een Mac of iPad hoort hier net zo hard te gelden als op de pc zelf.
    final gekozen = body['exact'];
    // Niet wachten op de afloop: dit antwoord gaat naar een gsm of iPad, en die stond anders per
    // nummer minuten op een open HTTP-verzoek te wachten. Gemeten: zeven nummers achter elkaar
    // aangevraagd startten twintig tot veertig seconden na elkaar in plaats van tegelijk. De taak
    // staat meteen in `/api/jobs`, dus de aanvrager kan gewoon kijken hoe het loopt.
    return manager.enqueueSoulseekBest(candidates,
        key: body['key'] as String?,
        authority: _authorityOf(body),
        exact: gekozen is Map<String, dynamic> ? SoulseekFile.fromJson(gekozen) : null,
        jouwKeuze: body['jouwKeuze'] == true,
        wachtOpAfloop: false);
  }

  /// The body of `POST /api/soulseek/download-album`. How many tracks were started.
  Future<int> startSoulseekAlbumDownload(Map<String, dynamic> body) async {
    final manager = downloads;
    if (manager == null) return 0;
    final tracks = <List<SoulseekFile>>[];
    for (final t in (body['tracks'] as List? ?? const [])) {
      if (t is! List) continue;
      final files = <SoulseekFile>[];
      for (final c in t) {
        if (c is! Map<String, dynamic>) continue;
        final f = SoulseekFile.fromJson(c);
        if (f != null) files.add(f);
      }
      tracks.add(files);
    }
    if (tracks.isEmpty) return 0;
    // Index-aligned with `tracks`, so a missing entry is a null rather than a shift — a shift
    // would file every remaining track under the previous one's identity.
    final wire = body['authorities'] as List? ?? const [];
    final authorities = <TrackTags?>[
      for (var i = 0; i < tracks.length; i++)
        if (i < wire.length && wire[i] is Map<String, dynamic>)
          TrackTags.fromJson(wire[i] as Map<String, dynamic>)
        else
          null
    ];
    return manager.enqueueSoulseekAlbum(tracks, authorities: authorities);
  }

  /// What the device says this track IS, when it says anything.
  ///
  /// Optional on purpose: a client from before this existed sends no authority, and must keep
  /// working exactly as it did. Soulseek supplies the audio; whoever asked for it supplies the
  /// identity — and if nobody does, placeFileDetailed falls back to the peer's own tags as before.
  static TrackTags? _authorityOf(Map<String, dynamic> body) {
    final a = body['authority'];
    return a is Map<String, dynamic> ? TrackTags.fromJson(a) : null;
  }

  Future<void> _soulseekDownload(HttpRequest req) async {
    final manager = downloads;
    if (manager == null) return _unavailable(req, 'Deze pc kan niet downloaden.');
    final body = await _jsonBody(req);
    if (body == null) return;
    final teVeel = _quotum(req, kQuotumDownloads);
    if (teVeel != null) return _teVeel(req, teVeel);
    try {
      final started = await startSoulseekDownload(body);
      return _json(req.response, {'ok': started});
    } catch (e) {
      return _unavailable(req, '$e');
    }
  }

  /// A whole album at once, asked for by a paired device.
  ///
  /// `tracks` is one list of candidate copies per track, `authorities` runs alongside it by index —
  /// the same shape the local call takes, so the PC does here exactly what it does for itself.
  Future<void> _soulseekDownloadAlbum(HttpRequest req) async {
    final manager = downloads;
    if (manager == null) return _unavailable(req, 'Deze pc kan niet downloaden.');
    final body = await _jsonBody(req);
    if (body == null) return;
    final teVeel = _quotum(req, kQuotumDownloads, (body['tracks'] as List?)?.length ?? 1);
    if (teVeel != null) return _teVeel(req, teVeel);
    try {
      final started = await startSoulseekAlbumDownload(body);
      return _json(req.response, {'started': started});
    } catch (e) {
      return _unavailable(req, '$e');
    }
  }

  Future<void> _jobCancel(HttpRequest req) async {
    final manager = downloads;
    if (manager == null) return _unavailable(req, 'Deze pc kan niet downloaden.');
    final body = await _jsonBody(req);
    if (body == null) return;
    final key = body['key'] as String?;
    final name = body['name'] as String?;
    // By key when there is one, otherwise by name: a loose search hit has no track identity, and
    // its row still needs a stop button that works.
    final job = key != null
        ? manager.jobByKey(key)
        : manager.jobs.cast<DownloadJob?>().firstWhere((j) => j?.name == name, orElse: () => null);
    if (job != null) manager.cancelJob(job);
    return _json(req.response, {'ok': job != null});
  }

  /// "Niet meer proberen" vanaf een ander toestel.
  ///
  /// Moet hier terechtkomen en niet op de telefoon blijven hangen: de wenslijst staat op DEZE pc, en
  /// een knop die alleen de rij op je telefoon weghaalt terwijl de pc doorzoekt is een knop die
  /// liegt. Zelfde manier van aanwijzen als [_jobCancel] — op sleutel als die er is, anders op naam.
  Future<void> _jobStopWens(HttpRequest req) async {
    final manager = downloads;
    if (manager == null) return _unavailable(req, 'Deze pc kan niet downloaden.');
    final body = await _jsonBody(req);
    if (body == null) return;
    final key = body['key'] as String?;
    final name = body['name'] as String?;
    final job = key != null
        ? manager.jobByKey(key)
        : manager.jobs.cast<DownloadJob?>().firstWhere((j) => j?.name == name, orElse: () => null);
    if (job != null) await manager.stopWens(job);
    return _json(req.response, {'ok': job != null});
  }

  /// De RuTracker-aanmelding van een toestel overnemen op de pc.
  ///
  /// **Waarom dit moet bestaan.** Het aanmeldvenster staat op het toestel waar je het opent — meestal
  /// je telefoon. Het zoeken en het downloaden gebeuren op de pc. Die twee zaten niet aan elkaar
  /// vast: je meldde je op je telefoon aan, en de pc had nog steeds geen sessie, dus vroeg hij
  /// RuTracker niet eens. Op het scherm was dat niet te onderscheiden van "RuTracker heeft niets".
  ///
  /// Het koekje reist over je eigen netwerk, naar je eigen pc, op jouw verzoek. Het wordt hier
  /// meteen beproefd met [RuTrackerService.verify]: een sessie bewaren zonder hem te proberen is
  /// precies hoe je er pas bij de volgende zoekopdracht achter komt dat hij niets deed.
  ///
  /// **Let op de User-Agent.** Die hoort onlosmakelijk bij het koekje: `cf_clearance` zit vast aan
  /// het kenmerk van de browser die hem gekregen heeft. Zonder dat kenmerk mee te sturen is het
  /// koekje op slag waardeloos.
  Future<void> _rutrackerSessie(HttpRequest req) async {
    final service = online;
    if (service == null) return _unavailable(req, 'Deze pc kan niet online zoeken.');
    final body = await _jsonBody(req);
    if (body == null) return;
    final cookie = (body['cookie'] as String?)?.trim() ?? '';
    final ua = (body['ua'] as String?)?.trim() ?? '';
    if (!cookie.contains('bb_session=')) {
      return _json(req.response, {
        'ok': false,
        'reden': 'Daar zat geen bb_session in — dat is het koekje dat zegt dat je ingelogd bent.',
      });
    }
    final settings = service.settings;
    final vorigeCookie = settings.rutrackerCookie;
    final vorigeUa = settings.rutrackerUa;
    settings.rutrackerCookie = cookie;
    if (ua.isNotEmpty) settings.rutrackerUa = ua;
    if (await service.rutracker.verify()) {
      await settings.save();
      return _json(req.response, {'ok': true, 'reden': 'De pc is aangemeld bij RuTracker.'});
    }
    // Niet bewaren wat aantoonbaar niet werkt: dan staat er een dode instelling op de pc die elke
    // zoekopdracht stil laat mislukken.
    settings.rutrackerCookie = vorigeCookie;
    settings.rutrackerUa = vorigeUa;
    return _json(req.response, {
      'ok': false,
      'reden': 'De pc kreeg het koekje wel, maar RuTracker herkende de sessie daar niet. '
          'Cloudflare bindt de doorgang aan het IP-adres, en dat van je pc is een ander dan dat van '
          'je telefoon. Meld je op de pc zelf aan bij Instellingen → RuTracker.',
    });
  }

  Future<void> _jobsClear(HttpRequest req) async {
    final manager = downloads;
    if (manager == null) return _unavailable(req, 'Deze pc kan niet downloaden.');
    if (req.method != 'POST') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      return req.response.close();
    }
    manager.clearFinished();
    return _json(req.response, {'ok': true});
  }

  /// Metadata edited on another device, applied HERE.
  ///
  /// The album is named by the id this PC issued, so there is no guessing about which "Millennium"
  /// was meant when the library holds two pressings of it. The change lands in the same
  /// [LibraryStore] the PC itself edits, which means it reaches every device the ordinary way:
  /// the catalogue fingerprint changes and the next poll picks it up.
  /// The read-only API keys a paired device needs to look things up for itself.
  ///
  /// Only these two, and that is the whole rule: a Discogs token and a Last.fm key read public
  /// databases and are revoked in one click. Passwords are NOT here — the Soulseek and RuTracker
  /// logins sign into accounts, and the calls that need them already run on this machine anyway.
  ///
  /// Sent on every connect rather than once at pairing, so changing a token here reaches the
  /// devices by itself instead of leaving them on a key that stopped working.
  Future<void> _config(HttpRequest req) async {
    final config = settings;
    if (config == null) return _json(req.response, const {});
    return _json(req.response, {
      'discogsToken': config.discogsToken,
      'lastfmKey': config.lastfmKey,
      // Zodat ook de telefoon bij TheAudioDB de volle tracklijst krijgt — "Uitgave kiezen" en
      // "Metadata corrigeren" vragen daar zelf.
      'audiodbKey': config.audiodbKey,
    });
  }

  /// Op welke adressen is deze pc te bereiken als je NIET op dit netwerk zit?
  ///
  /// In de praktijk: Tailscale. `isRemoteReachable` in `net.dart` weet welke adressen de voordeur
  /// overleven; hier worden ze doorgegeven aan een toestel dat al binnen is, zodat het ze heeft
  /// vóórdat het ze nodig heeft. Zie `uitwijk.dart` voor waarom dat het verschil maakt.
  ///
  /// **Achter de sleutel en niet bij `/health`.** Dit is het adres van deze machine op een privé
  /// netwerk. `/health` is met opzet open — zo stelt een toestel vast dat het de juiste machine te
  /// pakken heeft — en wie op een vreemde wifi poorten afgaat hoort daar niet het tailnet-adres van
  /// deze pc te vinden. Een toestel dat al een geldige sleutel heeft, mag het weten.
  ///
  /// Vers opgevraagd bij elke aanvraag, en dat is goedkoop: het is één opsomming van de
  /// netwerkkaarten. Bewaren zou betekenen dat Tailscale aanzetten pas na een herstart aankomt.
  Future<void> _uitwijk(HttpRequest req) async {
    List<String> overal = const [];
    List<String> thuis = const [];
    try {
      final a = await addressesByReach();
      overal = a.overal;
      thuis = a.thuis;
    } catch (e) {
      // Geen netwerkkaarten kunnen opsommen is geen reden om het verzoek te laten mislukken; dan
      // weten we alleen niets, en een lege lijst zegt dat precies.
      debugPrint('Uitwijkadressen niet op te maken: $e');
    }
    final c = certificaat;
    return _json(req.response, {
      'urls': [for (final ip in overal) 'http://$ip:$port'],
      // Ook de adressen op het eigen netwerk, apart (een oudere app leest alleen `urls`). Zonder deze
      // kende een toestel dat via Tailscale koppelde zijn pc thuis alleen via Tailscale: gemeten
      // 14-10-2026, op wifi won telkens 100.97.101.113 en deed 192.168.0.117 niet eens mee.
      'thuis': [for (final ip in thuis) 'http://$ip:$port'],
      // De pin is geen geheim: hij zegt alleen welk certificaat bij deze pc hoort. Een toestel leert
      // hem hier, thuis of via Tailscale, en vertrouwt daarna alleen dat certificaat.
      if (c != null) 'pin': c.pin,
      if (c != null && _tls != null) 'tlsPoort': _tls!.port,
    });
  }

  /// Deze pc bijwerken omdat een gekoppeld toestel erom vraagt. Zie `pc_bijwerker.dart`.
  ///
  /// **Waarom dit een eigen weg is en niet een bewerking bij [_corrections].** Die weg gaat over de
  /// bibliotheek: hij zoekt een album op, hij faalt met "dat album staat hier niet (meer)", en alles
  /// eraan is geschreven vanuit "verander iets aan de muziek". Dit verandert de app zelf. Een pc die
  /// deze weg nog niet kent antwoordt 404, en dat leest de telefoon als "kan het niet" — precies wat
  /// er dan ook aan de hand is.
  Future<void> _update(HttpRequest req, [Ingang ingang = Ingang.http]) async {
    final body = await _jsonBody(req);
    if (body == null) return;
    final op = (body['op'] ?? 'status') as String;
    if (ingang == Ingang.tlsBuiten && op == 'start') {
      return _json(req.response, {'error': 'Je pc bijwerken kan alleen thuis of via Tailscale.'}, status: HttpStatus.forbidden);
    }
    // Alleen de versienaam, zonder het buildnummer erachter: `version` is hier `3.9.236+11471` en
    // dat is niet wat er straks naast een knop hoort te staan.
    final hier = version.split('+').first;
    return _json(req.response,
        op == 'start' ? await bijwerker.start(hier) : await bijwerker.stand(hier));
  }

  /// De radio van een gekoppeld toestel, in vier vragen op één weg.
  ///
  /// Vier `op`-waarden en geen vier routes, precies zoals `/api/update` het al doet: het gaat om één
  /// voorziening, en vier ingangen zouden vier keer dezelfde bewaking en dezelfde foutafhandeling
  /// nodig hebben.
  ///
  /// * `begin` — mag deze pc ophalen? Neemt bij ja meteen de ene Soulseek-aanmelding vast.
  /// * `einde` — die aanmelding weer los.
  /// * `haal` — ga dit nummer halen. Keert METEEN terug met een nummer om naar te vragen.
  /// * `stand` — hoe staat het met dat nummer?
  Future<void> _radio(HttpRequest req) async {
    final body = await _jsonBody(req);
    if (body == null) return;
    final op = (body['op'] ?? '') as String;
    switch (op) {
      case 'begin':
        final tegen = radiohaler.begin();
        return _json(req.response, {'ok': tegen == null, if (tegen != null) 'reden': tegen});
      case 'einde':
        radiohaler.einde();
        return _json(req.response, {'ok': true});
      case 'staak':
        // Ophouden met halen, maar de aanmelding vasthouden: dit komt langs als er op het toestel
        // een NIEUWE radio begint, en die heeft die aanmelding meteen weer nodig.
        radiohaler.staak();
        return _json(req.response, {'ok': true});
      case 'haal':
        final artiest = (body['artiest'] ?? '') as String;
        final titel = (body['titel'] ?? '') as String;
        if (titel.trim().isEmpty) return _unavailable(req, 'Zonder titel valt er niets te halen.');
        final teVeelHaal = _quotum(req, kQuotumDownloads);
        if (teVeelHaal != null) return _teVeel(req, teVeelHaal);
        final h = radiohaler.haal(
          artiest: artiest,
          titel: titel,
          seconden: (body['seconden'] as num?)?.toInt(),
          jaar: (body['jaar'] as num?)?.toInt(),
        );
        return _json(req.response, {'id': h.id});
      case 'stand':
        return _json(req.response, radiohaler.stand((body['id'] ?? '') as String));
      case 'vergeetwens':
        // Het WISSEN van het bestand loopt over `/api/library/edit` — dat kan de telefoon al. Wat ze
        // niet zelf kan is de verlanglijst hier opschonen, en zonder dat haalt `sweepLosslessWants`
        // twintig minuten later alsnog de FLAC van een nummer dat je net met rood hebt weggedaan.
        await downloads?.vergeetWens(
          (body['artiest'] ?? '') as String,
          (body['titel'] ?? '') as String,
        );
        return _json(req.response, {'ok': true});
      case 'plan':
        // De AI-sleutel blijft op de pc, precies zoals de TorBox-sleutel dat doet. Een telefoon hoeft
        // hem dan niet te kennen, en er is één plek waar hij staat.
        final config = settings;
        if (config == null) return _unavailable(req, 'Deze pc kan geen radioplan maken.');
        final teVeelPlan = _quotum(req, kQuotumRadioplan);
        if (teVeelPlan != null) return _teVeel(req, teVeelPlan);
        try {
          final o = await AiService(() => config.anthropicKey,
                  werkruimteVan: () => config.anthropicWorkspace)
              .maakRadioplan((body['zin'] ?? '') as String);
          return _json(req.response, {
            'genre': o.genre,
            'aantal': o.aantal,
            'aantalGenoemd': o.aantalGenoemd,
            'zaadArtiesten': o.zaadArtiesten,
            if (o.jaarVan != null) 'jaarVan': o.jaarVan,
            if (o.jaarTot != null) 'jaarTot': o.jaarTot,
            'stemming': o.stemming,
          });
        } on AiFout catch (e) {
          return _unavailable(req, e.uitleg);
        } catch (e) {
          return _unavailable(req, '$e');
        }
    }
    return _unavailable(req, 'Onbekende radio-opdracht.');
  }

  Future<void> _corrections(HttpRequest req) async {
    final config = settings;
    if (config == null) return _unavailable(req, 'Deze pc kan geen wijzigingen aannemen.');
    final body = await _jsonBody(req);
    if (body == null) return;

    final op = (body['op'] ?? '') as String;
    final vanBuiten = _ingangVan[req] == Ingang.tlsBuiten;
    // Van buiten: een adres dat de pc later zelf ophaalt, alleen naar het internet. Zie [adresVanBuitenMag].
    if (vanBuiten && body['url'] is String && !adresVanBuitenMag(body['url'] as String)) {
      _koppelLog?.line('BEWERKING VAN BUITEN geweigerd: $op met een adres dat niet naar het internet wijst');
      return _json(req.response, {'error': 'Van buitenaf kan alleen een https-adres op het internet.'},
          status: HttpStatus.forbidden);
    }
    final album = body['albumId'] is String ? catalog.album(body['albumId'] as String) : null;
    // Twee bewerkingen gaan niet OVER een album: nummers weghalen noemt losse nummers, en een
    // artiestfoto hoort bij de artiest. Zonder deze uitzondering kreeg de telefoon hier "Dat album
    // staat hier niet (meer)" terug op iets waar ze nooit een album bij gestuurd heeft.
    // `albumArtRole` hoort ook in deze uitzondering: rollen hangen aan artiest|titel en niet aan een
    // album-id, net als een artiestportret. Zonder deze uitzondering kreeg elke rolwijziging van een
    // client een 404 op een album dat de client niet meestuurt.
    if (op != 'removeTracks' &&
        op != 'artistArt' &&
        op != 'albumArtRole' &&
        op != 'renumber' &&
        op != 'assignRows' &&
        album == null) {
      // The client is looking at a catalogue this PC has moved on from — say so, rather than
      // silently editing the wrong record.
      return _json(req.response, {'error': 'Dat album staat hier niet (meer).'},
          status: HttpStatus.notFound);
    }

    try {
      switch (op) {
        case 'correction':
          final coverB64 = body['cover'] as String?;
          await library.applyCorrection(
            album!,
            config,
            artist: body['artist'] as String?,
            albumTitle: body['albumTitle'] as String?,
            title: body['title'] as String?,
            coverBytes: coverB64 == null || coverB64.isEmpty ? null : base64Decode(coverB64),
            discogsRelease: (body['discogsRelease'] as num?)?.toInt(),
            mbid: body['mbid'] as String?,
          );
        case 'correctionTracks':
          // Eén nummer uit een album op zijn eigen plaat zetten — zie [LibraryStore.applyCorrection].
          //
          // Een eigen naam en niet `correction` met een veld erbij: een pc die dit nog niet kent zou
          // dat veld negeren en de correctie op ALLE nummers toepassen. Nu belandt hij in de
          // `default` hieronder en zegt hij eerlijk dat hij het niet kan.
          final teDoen = _tracksFor(body['trackIds']);
          if (teDoen.isEmpty) {
            return _json(req.response, {'error': 'Geen nummers opgegeven.'},
                status: HttpStatus.badRequest);
          }
          final hoesB64Nummer = body['cover'] as String?;
          await library.applyCorrection(
            album!,
            config,
            artist: body['artist'] as String?,
            albumTitle: body['albumTitle'] as String?,
            title: body['title'] as String?,
            coverBytes: hoesB64Nummer == null || hoesB64Nummer.isEmpty
                ? null
                : base64Decode(hoesB64Nummer),
            discogsRelease: (body['discogsRelease'] as num?)?.toInt(),
            mbid: body['mbid'] as String?,
            alleen: teDoen,
          );
        case 'merge':
          await library.mergeEditions(album!);
        case 'unmerge':
          await library.unmergeEditions(album!);
        case 'artistArt':
          final artist = (body['artist'] ?? '') as String;
          if (artist.isEmpty) {
            return _json(req.response, {'error': 'Geen artiest opgegeven.'},
                status: HttpStatus.badRequest);
          }
          await library.setArtistArt(
              artist, (body['kind'] ?? 'portrait') as String, (body['url'] ?? '') as String);
        case 'renumber':
          // Hernummeren namens een ander toestel. Kon hier niet aankomen: op een client schreef dit
          // alleen `corrections.json` op dát toestel, terwijl de bibliotheek daar uit de catalogus
          // van deze pc komt. De nummering veranderde even op het scherm en was bij de volgende
          // synchronisatie weer weg.
          //
          // Op NUMMER-ids en niet op een album, want dat is wat hernummeren raakt — vandaar ook de
          // uitzondering op de albumcontrole hierboven, net als bij `removeTracks`.
          final totaal = (body['total'] as num?)?.toInt() ?? 0;
          final stappen = <({String path, int no, String? title})>[];
          for (final rauw in (body['steps'] as List? ?? const [])) {
            if (rauw is! Map) continue;
            final t = catalog.track('${rauw['trackId']}');
            final no = (rauw['no'] as num?)?.toInt();
            if (t == null || no == null) continue;
            stappen.add((path: t.path, no: no, title: rauw['title'] as String?));
          }
          if (stappen.isEmpty) {
            return _json(req.response, {'error': 'Geen nummers gevonden om te hernummeren.'},
                status: HttpStatus.badRequest);
          }
          await library.hernummer(stappen, totaal);
        case 'albumCover':
          // Een hoes die op een ander toestel gekozen is. Kwam hier nooit aan: `setAlbumCover`
          // schreef alleen naar het geheugen en de cache van dát toestel. Corrigeerde je de hoes op
          // de Mac, dan bleef de telefoon de oude tonen — die haalt hem immers hier vandaan.
          //
          // BYTES en geen adres, want een gekozen hoes komt niet altijd van het web: hij kan uit een
          // bestand of uit de tags komen. Zodra hij hier staat beweegt `artTag`, dus de ETag, en
          // halen de andere toestellen hem vanzelf op.
          final hoesB64 = (body['cover'] ?? '') as String;
          if (hoesB64.isEmpty) {
            return _json(req.response, {'error': 'Geen hoes meegestuurd.'},
                status: HttpStatus.badRequest);
          }
          await library.setAlbumCover(album!, config, base64Decode(hoesB64));
        case 'albumArtRole':
          // Een scan die de eigenaar op een ander toestel aanwees. Kwam hier nooit aan: dit stond
          // alleen in `album_art_roles.json` op dát toestel, zodat een cd die je op de iPad koos
          // voor de pc en de tv niet bestond.
          //
          // Op artiest en titel, want zo zijn rollen gesleuteld — [LibraryStore.albumArtKey]. De
          // client leest die twee uit dezelfde catalogus die deze pc gestuurd heeft, dus ze komen
          // altijd op dezelfde sleutel uit.
          final rolArtiest = (body['artist'] ?? '') as String;
          final rolAlbum = (body['album'] ?? '') as String;
          if (rolArtiest.isEmpty || rolAlbum.isEmpty) {
            return _json(req.response, {'error': 'Geen album opgegeven.'},
                status: HttpStatus.badRequest);
          }
          if (body['clear'] == true) {
            await library.clearAlbumArtRoles(rolArtiest, rolAlbum);
          } else {
            await library.setAlbumArtRole(rolArtiest, rolAlbum, (body['role'] ?? '') as String,
                (body['url'] ?? '') as String);
          }
        case 'assignRows':
          // "Nummers toewijzen" namens een ander toestel.
          //
          // **Dit ontbrak, en daardoor werkte dat venster alleen op de pc.** De client stuurde al
          // een bewerking, maar er was niets dat hem aannam: hij belandde in de `default` hieronder
          // en kreeg "Onbekende bewerking" terug. Op de gsm sleepte je een nummer naar een rij en
          // er gebeurde niets. Gemeld op 06-09-2026.
          //
          // Op NUMMER-ids, net als `renumber` en `removeTracks` — vandaar ook de uitzondering op de
          // albumcontrole hierboven: een toewijzing hangt aan bestanden, niet aan een album-id.
          final keuzes = <String, String?>{};
          for (final rauw in (body['rows'] as List? ?? const [])) {
            if (rauw is! Map) continue;
            final t = catalog.track('${rauw['trackId']}');
            if (t == null) continue;
            // Een lege rij is een geldige keuze: dat is "geef de beslissing terug aan de app".
            final rij = rauw['row'] as String?;
            keuzes[t.path] = (rij == null || rij.isEmpty) ? null : rij;
          }
          if (keuzes.isEmpty) {
            return _json(req.response, {'error': 'Geen nummers gevonden om toe te wijzen.'},
                status: HttpStatus.badRequest);
          }
          await library.wijsRijenToe(keuzes);
        case 'removeTracks':
          final paths = <String>[];
          for (final id in (body['trackIds'] as List? ?? const [])) {
            final t = id is String ? catalog.track(id) : null;
            if (t != null) paths.add(t.path);
          }
          if (paths.isEmpty) return _json(req.response, {'ok': false, 'reason': 'niets gevonden'});
          final vanSchijf = body['fromDisk'] == true;
          // Van buiten gaat er nooit iets definitief weg: altijd de prullenbak, en zonder prullenbak
          // alleen thuis. Een gestolen gsm kan zo hoogstens iets in de prullenbak zetten.
          if (vanBuiten && vanSchijf) {
            if (!prullenbakAanwezig()) {
              return _json(req.response,
                  {'error': 'Van buitenaf gaat verwijderen alleen naar de prullenbak, en deze pc heeft er geen.'},
                  status: HttpStatus.forbidden);
            }
            final teVeel = _quotum(req, kQuotumPrullenbak, paths.length);
            if (teVeel != null) return _teVeel(req, teVeel);
          }
          await library.removeTracks(paths,
              fromDisk: vanSchijf,
              naarPrullenbak: body['naarPrullenbak'] == true || (vanBuiten && vanSchijf));
        default:
          return _json(req.response, {'error': 'Onbekende bewerking: $op'},
              status: HttpStatus.badRequest);
      }
    } catch (e) {
      return _unavailable(req, 'De pc kon dat niet toepassen: $e');
    }
    return _json(req.response, {'ok': true});
  }

  /// What moving these tracks would do on disk — worked out HERE, where the files are.
  ///
  /// Its own call before anything is applied, because the dialog on the other device exists to say
  /// what will happen to which file. A client cannot work that out: it has no folders, no idea
  /// which copy is better, and no way to know that a name is already taken.
  Future<void> _movePlan(HttpRequest req) async {
    final body = await _jsonBody(req);
    if (body == null) return;
    final target = body['albumId'] is String ? catalog.album(body['albumId'] as String) : null;
    if (target == null) {
      return _json(req.response, {'error': 'Dat album staat hier niet (meer).'},
          status: HttpStatus.notFound);
    }
    final tracks = _tracksFor(body['trackIds']);
    if (tracks.isEmpty) return _json(req.response, {'items': []});
    final plan = library.planMove(tracks, target);
    // Built once and turned round: the plan is keyed by track, the client speaks in ids, and doing
    // this lookup per item would walk the whole library for every file being moved.
    final idByPath = {for (final e in catalog.snapshot().trackById.entries) e.value.path: e.key};
    return _json(req.response, {
      'folder': target.tracks.isEmpty ? null : File(target.tracks.first.path).parent.path,
      'items': [
        for (final p in plan)
          {
            'trackId': idByPath[p.track.path],
            'from': p.from,
            'to': p.to,
            'fate': p.fate.name,
          },
      ],
    });
  }

  /// Apply the plan the user actually read.
  ///
  /// The approved `to` and `fate` come back with the request, and the PC works the plan out AGAIN
  /// and compares. Nothing moves unless every item is exactly what this machine would do itself.
  ///
  /// **Waarom vergelijken en niet gewoon aannemen.** Tot 14-10-2026 werd `to` letterlijk uitgevoerd:
  /// wie een sleutel had, kon een bestand uit de bibliotheek naar elke plek op de pc laten schrijven
  /// (`C:\Users\…\Opstarten`, een andere schijf). Opnieuw plannen zonder te vergelijken zou dat
  /// dichten, maar dan verhuist er misschien iets anders dan wat op het scherm stond — precies wat
  /// het meesturen van het plan moest voorkomen. Vergelijken doet beide: wat afwijkt wordt geweigerd
  /// (409), en het toestel vraagt het plan dan opnieuw op.
  Future<void> _moveApply(HttpRequest req) async {
    final config = settings;
    if (config == null) return _unavailable(req, 'Deze pc kan geen wijzigingen aannemen.');
    final body = await _jsonBody(req);
    if (body == null) return;
    final target = body['albumId'] is String ? catalog.album(body['albumId'] as String) : null;
    if (target == null) {
      return _json(req.response, {'error': 'Dat album staat hier niet (meer).'},
          status: HttpStatus.notFound);
    }

    final byId = catalog.snapshot().trackById;
    final approved = <MovePlan>[];
    for (final item in (body['plan'] as List? ?? const [])) {
      if (item is! Map<String, dynamic>) continue;
      final track = byId[item['trackId'] as String? ?? ''];
      if (track == null) continue;
      approved.add(MovePlan(
        track,
        track.path,
        item['to'] as String?,
        MoveFate.values.firstWhere((f) => f.name == item['fate'], orElse: () => MoveFate.moves),
      ));
    }
    final tracks = approved.isNotEmpty
        ? [for (final p in approved) p.track]
        : _tracksFor(body['trackIds']);
    if (tracks.isEmpty) return _json(req.response, {'moved': 0});

    // Het plan van deze pc zelf, voor precies deze nummers. Alleen wat daar letterlijk mee
    // overeenkomt, mag verhuizen; anders wordt het plan van deze pc uitgevoerd en niet dat van het
    // verzoek.
    List<MovePlan>? uitTeVoeren;
    if (approved.isNotEmpty) {
      final eigen = {for (final p in library.planMove(tracks, target)) p.track.path: p};
      final afwijkend = approvedAfwijkend(approved, eigen);
      if (afwijkend > 0) {
        return _json(
            req.response,
            {
              'error': 'Wat er op de pc zou gebeuren is intussen anders dan wat je zag '
                  '($afwijkend ${afwijkend == 1 ? 'bestand' : 'bestanden'}). Er is niets verplaatst — '
                  'open het verplaatsen opnieuw.',
              'afwijkend': afwijkend,
            },
            status: HttpStatus.conflict);
      }
      uitTeVoeren = [for (final p in approved) eigen[p.track.path]!];
    }

    try {
      final moved = await library.moveTracksToAlbum(tracks, target, config,
          moveFiles: body['moveFiles'] != false, plan: uitTeVoeren);
      return _json(req.response, {'moved': moved});
    } catch (e) {
      return _unavailable(req, 'De pc kon dat niet verplaatsen: $e');
    }
  }

  List<Track> _tracksFor(Object? ids) {
    final out = <Track>[];
    for (final id in (ids as List? ?? const [])) {
      final t = id is String ? catalog.track(id) : null;
      if (t != null) out.add(t);
    }
    return out;
  }

  /// Verkleinde hoezen, op verwijzing + plafond + merkteken van het origineel.
  ///
  /// **Op bytes begrensd en niet op aantal, en de oudst GEBRUIKTE valt eruit.** Eerst stonden hier
  /// tweehonderd plekken met "de eerst ingevoegde eruit". Bij 544 hoezen die in vaste volgorde
  /// langskomen is dat het slechtste geval dat er bestaat: aan het begin van de tweede ronde zitten
  /// hoes 345 tot 544 erin, mist het verzoek om hoes 1, en gooit die precies de hoes eruit die zo
  /// aan de beurt is. Trefkans vrijwel nul, en "eenmalig rekenen" werd elke ronde opnieuw rekenen.
  ///
  /// Tellen op items klopte ook niet: bij `?w=2048` is een item een veelvoud van de 120 KB waar de
  /// rekensom op stond.
  ///
  /// **De grens moet BOVEN de werkverzameling liggen, anders is LRU net zo slecht als FIFO.** Dat
  /// is precies wat er met 48 MiB gebeurde: de verkleinde bibliotheek is 55,4 MiB, dus paste 87
  /// procent erin, en bij een vaste doorloopvolgorde gooit elke misser de hoes eruit die zo aan de
  /// beurt is. Nagebouwd met 43 sleutels van samen 56,6 MiB: tweede ronde nul treffers, 43 missers,
  /// drieënveertig seconden opnieuw rekenen. Zesennegentig is bijna tweemaal de 55,4 MiB die geteld
  /// is — ruimte voor een bibliotheek die groeit en voor een tweede formaat ernaast.
  ///
  /// Het gaat om geheugen dat er in zekere zin al is: `catalog.artwork` geeft de hoes uit de
  /// catalogus, en die 172,4 MiB aan originelen staat sowieso in het geheugen van de pc-app.
  final _kleineHoezen = <String, Uint8List?>{};
  var _kleineHoezenBytes = 0;
  static const _kleineHoezenMaxBytes = 96 * 1024 * 1024;

  /// Wat een plek in de cache minstens weegt.
  ///
  /// **Anders is een leeg antwoord onsterfelijk.** Een hoes die niet kleiner wordt levert null op,
  /// en `null?.length ?? 0` is nul: zulke plekken kwamen nooit in het vizier van de uitwerplus. Bij
  /// het huidige gebruik zijn het er acht en merkt niemand het, maar `?w=` staat 1921 waarden toe —
  /// wie er een tweede formaat bij zet vermenigvuldigt dat meteen, en dan is de grens geen grens.
  static const _kleineHoesMinBytes = 64 * 1024;

  /// Wat er NU berekend wordt, op sleutel. Twee toestellen die tegelijk synchroniseren vroegen
  /// anders elke hoes dubbel op en zetten twee volledige verkleiningen in dezelfde rij.
  final _hoesBezig = <String, Future<Uint8List?>>{};

  static int _weegt(Uint8List? w) =>
      (w?.length ?? 0) < _kleineHoesMinBytes ? _kleineHoesMinBytes : w!.length;

  Future<Uint8List?> _kleineHoes(String sleutel, Uint8List bron, int plafond) {
    if (_kleineHoezen.containsKey(sleutel)) {
      // Opnieuw invoegen, zodat de volgorde van de map de volgorde van GEBRUIK is.
      final w = _kleineHoezen.remove(sleutel);
      _kleineHoezen[sleutel] = w;
      return Future.value(w);
    }
    final loopt = _hoesBezig[sleutel];
    if (loopt != null) return loopt;
    final werk = verkleindeHoesBuitenDeTekendraad(bron, plafond).then((klein) {
      // **Ook een leeg antwoord wordt onthouden.** Een hoes die niet kleiner wordt gaf anders bij
      // elk volgend verzoek opnieuw een volledige decode plus hercodering, voor altijd.
      _kleineHoezen[sleutel] = klein;
      _kleineHoezenBytes += _weegt(klein);
      while (_kleineHoezenBytes > _kleineHoezenMaxBytes && _kleineHoezen.length > 1) {
        final oudste = _kleineHoezen.keys.first;
        _kleineHoezenBytes -= _weegt(_kleineHoezen.remove(oudste));
      }
      return klein;
    });
    _hoesBezig[sleutel] = werk;
    // Een BLOKlichaam en geen pijl: met een pijl geeft de opruimer terug wat `remove` teruggeeft, en
    // dat is op een map van futures de future zelf. Zie `lan/transcode.dart` voor de keer dat dat
    // een wachter voor altijd liet wachten.
    return werk.whenComplete(() {
      _hoesBezig.remove(sleutel);
    });
  }

  Future<void> _art(HttpRequest req) async {
    final ref = Uri.decodeComponent(req.uri.pathSegments.last);
    var bytes = catalog.artwork(ref);
    final res = req.response;
    if (bytes == null || bytes.isEmpty) {
      // Not an error: a cover the enricher hasn't reached yet simply isn't there, and the client
      // shows its placeholder.
      res.statusCode = HttpStatus.notFound;
      return res.close();
    }
    // Een merkteken van de bytes die hier NU liggen, en niet van wat de eigenaar bewust gekozen
    // heeft.
    //
    // **Waarom dat verschil ertoe doet.** `AlbumDto.artTag` is er alleen voor een bewuste keuze —
    // met opzet, want die reist in de vingerafdruk van de catalogus mee en zou anders bij het
    // verrijken van een verse bibliotheek honderden keren gaan bewegen. Maar daardoor kon een
    // toestel niet nagaan of de hoes die het al maanden in zijn cache heeft nog steeds is wat de pc
    // toont: zonder bewuste keuze is er niets om tegenaan te houden. Zo hielden de Mac en de pc
    // hardnekkig twee verschillende hoezen van hetzelfde album vast.
    //
    // Hier kost het niets: dit is één antwoord op één verzoek, geen veld dat elke catalogus naar elk
    // toestel duwt. Het toestel kan met `If-None-Match` in één goedkope 304 te horen krijgen dat het
    // gelijk had — en anders krijgt het meteen de juiste bytes.
    final merk = CoverEnricher.hoesMerk(bytes);

    // **`?w=` — een plafond in pixels.** Zie `verkleindeHoes` in `artwork.dart` voor de meting die
    // hierachter zit: 544 albums, 541 hoezen van samen 172,4 MiB, met een staart tot 14,7 MiB, naar
    // een tegel van 390 pixels. Wie geen plafond meegeeft krijgt onveranderd wat hij altijd al
    // kreeg — een oudere app, de pc zelf, en elk toestel dat het origineel wil.
    //
    // Het merkteken telt het plafond MEE. Zonder dat zou een toestel dat de volle hoes al in zijn
    // cache heeft een 304 krijgen op een verzoek om de kleine, en dus voor altijd de grote houden.
    final gevraagd = int.tryParse(req.uri.queryParameters['w'] ?? '');
    var plafond = gevraagd != null && gevraagd >= 128
        ? (gevraagd > 2048 ? 2048 : gevraagd)
        : null;
    // Van buiten telt alleen een verkleining die nog niet klaarligt, en een geraakt plafond geeft het
    // origineel (met zijn eigen merkteken, zodat het toestel later alsnog de kleine vraagt).
    if (plafond != null &&
        _ingangVan[req] == Ingang.tlsBuiten &&
        !_kleineHoezen.containsKey('$ref|$plafond|$merk') &&
        !_hoesBezig.containsKey('$ref|$plafond|$merk') &&
        _quotum(req, kQuotumHoezen) != null) {
      plafond = null;
    }
    final etag = plafond == null ? '"$merk"' : '"$merk-w$plafond"';

    // **De 304 gaat VOOR het verkleinen, en dat is geen microseconde-werk.** Het merkteken hangt aan
    // de bron en aan het plafond, en die zijn hier allebei al bekend — er is niets uit de verkleinde
    // bytes voor nodig. Stond dit erna, dan betaalde de pc voor elk leeg antwoord een volledige
    // decode plus hercodering: een telefoon die opstart vraagt elke hoes na, dat zijn 544 lege 304's,
    // en dat was gemeten 292 ms per stuk in plaats van 2.
    if (req.headers.value(HttpHeaders.ifNoneMatchHeader) == etag) {
      res.statusCode = HttpStatus.notModified;
      res.headers.set(HttpHeaders.etagHeader, etag);
      return res.close();
    }

    if (plafond != null) {
      final klein = await _kleineHoes('$ref|$plafond|$merk', bytes, plafond);
      if (klein != null) bytes = klein;
    }

    res.statusCode = HttpStatus.ok;
    res.headers
      ..set(HttpHeaders.contentTypeHeader, _imageType(bytes))
      ..set(HttpHeaders.etagHeader, etag)
      // `must-revalidate` en geen uur meer: een tussenliggende cache die dit een uur vasthoudt zou
      // precies de vraag onbeantwoord laten die we hierboven stellen.
      ..set(HttpHeaders.cacheControlHeader, 'private, max-age=0, must-revalidate');
    res.headers.contentLength = bytes.length;
    if (req.method != 'HEAD') res.add(bytes);
    return res.close();
  }

  /// [status] is a parameter and not always 200 because it used to be hardcoded here, which
  /// quietly turned every error body into a successful empty answer: a client asking a PC that
  /// cannot search got `{"error": "..."}` with a 200, read no results in it, and showed "niets
  /// gevonden" instead of the reason.
  /// Een JSON-antwoord, met de statuscode die de aanroeper wil.
  ///
  /// **[status] is bewust nullable, en dat is een reparatie.** Hier stond
  /// `{int status = HttpStatus.ok}` met een onvoorwaardelijke `res.statusCode = status`. Wie de code
  /// ERVOOR zette — en dat deden zes plekken in dit bestand — zag hem stil op 200 terugvallen. Op
  /// 16-09-2026 kwam Saber daardoor zijn telefoon niet meer binnen: `/pair-cloud` antwoordde
  ///
  ///     HTTP 200  {"error":"Je pc is niet ingelogd. Log op de pc in met hetzelfde account."}
  ///
  /// terwijl er in de code `statusCode = HttpStatus.forbidden` boven stond. De telefoon zag een
  /// GESLAAGD antwoord zonder sleutel erin en zei *"De pc gaf geen sleutel terug"* — een zin die
  /// nergens heen wijst, terwijl de pc precies verteld had wat eraan scheelde.
  ///
  /// Niets meegeven laat de code staan die er al stond; dat kan geen enkele weigering meer
  /// wegpoetsen. De zes plekken hieronder geven hem nu expliciet mee.
  Future<void> _json(HttpResponse res, Object body, {int? status}) async {
    final bytes = utf8.encode(jsonEncode(body));
    if (status != null) res.statusCode = status;
    res.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
    res.headers.contentLength = bytes.length;
    res.add(bytes);
    return res.close();
  }

  /// Covers come from tags and from the web, so they are whatever the source was. Sniff the magic
  /// bytes rather than assume JPEG — a PNG served as JPEG renders as nothing on some clients.
  static String _imageType(List<int> b) {
    if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return 'image/png';
    if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49) return 'image/gif';
    if (b.length > 11 && b[8] == 0x57 && b[9] == 0x45) return 'image/webp';
    return 'image/jpeg';
  }

  /// The URLs to hand to the other devices, best first.
  Future<List<String>> addresses() async =>
      [for (final ip in await lanAddresses()) 'http://$ip:$port'];
}

/// Hoeveel items van een meegestuurd verplaatsplan NIET exact zijn wat deze pc zelf zou doen.
///
/// Een item zonder eigen tegenhanger telt als afwijkend; `to` en `fate` moeten allebei gelijk zijn.
/// Apart en openbaar zodat de toets de regel zelf kan raken, naast de route.
@visibleForTesting
int approvedAfwijkend(List<MovePlan> approved, Map<String, MovePlan> eigen) {
  var n = 0;
  for (final p in approved) {
    final e = eigen[p.track.path];
    if (e == null || e.to != p.to || e.fate != p.fate) n++;
  }
  return n;
}

/// A fresh access token. Generated once and kept, so a device stays paired across restarts.
String generateLanToken() {
  final rnd = Random.secure();
  return List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../ai.dart';
import '../album_facts.dart';
import '../cloud/device_identity.dart';
import '../album_facts_resolver.dart';
import '../enrichment.dart';
import '../library.dart';
import '../models.dart';
import '../musicbrainz.dart';
import '../online.dart';
import '../organize.dart';
import '../paths.dart';
import '../warm_log.dart';
import '../settings.dart';
import '../soulseek.dart';
import '../torbox.dart';
import 'cast_manager.dart';
import 'radiohaler.dart';
import 'catalog.dart';
import 'dtos.dart';
import 'net.dart';
import 'pairing.dart';
import 'pc_bijwerker.dart';
import 'range.dart';
import 'state_store.dart';
import 'tokens.dart';
import 'transcode.dart';
import 'upnp.dart';

/// The port the other devices look for. Fixed on purpose — an ephemeral port would mean every
/// restart hands out a different address, and anything a client saved would go stale.
const int kLanPort = 47820;

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
    GrantStore? grants,
  })  : grants = grants ?? GrantStore(),
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
  }

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

  bool get running => _http != null;

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
    } on SocketException catch (e) {
      return e.osError?.errorCode == 10048 || e.osError?.errorCode == 48
          ? 'Poort $port is al in gebruik door een ander programma.'
          : 'Kon niet starten op poort $port: ${e.osError?.message ?? e.message}';
    }
    _http!.autoCompress = false; // audio and covers are already compressed
    _meldStand();
    unawaited(_serve(_http!));
    return null;
  }

  Future<void> stop() async {
    final http = _http;
    _http = null;
    await http?.close(force: true);
  }

  /// Stop for good. Separate from [stop] so switching sharing off and on again doesn't leave the
  /// catalogue detached from the library and quietly serving a frozen snapshot.
  Future<void> dispose() async {
    await stop();
    cast.dispose();
    catalog.dispose();
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      // One bad request must never take the server — and with it the whole app — down.
      unawaited(_handle(request).catchError((Object e, StackTrace s) {
        debugPrint('LAN request failed (${request.uri.path}): $e');
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.close();
        } catch (_) {/* already closed or hung up */}
      }));
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Headers', 'Authorization, Content-Type, Range, If-None-Match')
      ..set('Access-Control-Allow-Methods', 'GET, POST, HEAD, OPTIONS')
      // Without this a browser client can't read the range headers it just asked for.
      ..set('Access-Control-Expose-Headers', 'Content-Range, Accept-Ranges, Content-Length, ETag');

    if (req.method == 'OPTIONS') {
      res.statusCode = HttpStatus.noContent;
      await res.close();
      return;
    }

    final path = req.uri.path;

    // Unauthenticated on purpose: this is how a device confirms it found the right machine, and
    // how the app itself checks whether a second copy is already running.
    if (path == '/health') {
      return _json(res, {
        'status': 'ok',
        'name': 'debridmusic-desktop',
        'version': version,
        'deviceName': deviceName(),
        'trackCount': library.tracks.length,
        'albumCount': library.albums.length,
      });
    }

    // Also unauthenticated, necessarily — this is how a device that has no token gets one.
    if (path == '/pair') return _pair(req);

    if (!await _authorizedOfHerstel(req)) {
      res.statusCode = HttpStatus.unauthorized;
      return res.close();
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
        return _castControl(req);
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
      case '/api/corrections':
        return _corrections(req);
      case '/api/move/plan':
        return _movePlan(req);
      case '/api/move/apply':
        return _moveApply(req);
      case '/api/update':
        return _update(req);
      case '/api/radio':
        return _radio(req);
    }

    if (path.startsWith('/stream/')) return _stream(req);
    if (path.startsWith('/art/')) return _art(req);

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

  Future<bool> _authorizedOfHerstel(HttpRequest req) async {
    if (_authorized(req, stil: true)) return true;
    // Nog één kans, en alleen de eerste keer: opnieuw inlezen en het aanbod nog eens toetsen.
    if (await _herlaadKoppelingen() && _authorized(req, stil: true)) return true;
    _authorized(req); // nu mét de regel in het logboek
    return false;
  }

  bool _authorized(HttpRequest req, {bool stil = false}) {
    final header = req.headers.value(HttpHeaders.authorizationHeader) ?? '';
    final bearer = header.startsWith('Bearer ') ? header.substring(7).trim() : '';
    // The query form is not laziness: a UPnP renderer and an <audio> tag both fetch the URL
    // themselves and have nowhere to put a header.
    final query = req.uri.queryParameters['token'] ?? '';
    final offered = bearer.isNotEmpty ? bearer : query;
    if (offered.isEmpty) return false;

    // A per-device grant, or the one shared token this used to have. The legacy check stays and is
    // NOT rotated on upgrade: a device paired yesterday must keep working the moment this ships,
    // and unpairing everything at once is exactly what the old design was stuck with.
    if (grants.accepts(offered)) {
      if (grants.touch(offered)) unawaited(grants.save());
      return true;
    }
    // De gedeelde sleutel, en bij twijfel die uit de instellingen.
    //
    // Dit veld wordt gezet door `applySettings`. Loopt dat mis of te laat, dan staat hier een lege
    // tekst en weigert de server ook de sleutel die gewoon in `settings.json` staat — zonder dat er
    // iets te zien is. Wat er op schijf staat is de waarheid; dit is dezelfde sleutel, niet een
    // tweede.
    final gedeeld = token.isNotEmpty ? token : (settings?.lanToken ?? '');
    if (gedeeld.isNotEmpty && _constantTimeEquals(offered, gedeeld)) return true;
    if (!stil) _noteerWeigering(req, offered);
    return false;
  }

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
        facts = await resolveAlbumFacts(album,
            uid: uid,
            trackSetHash: hash,
            mb: mb,
            settings: s,
            pinnedMbid: library.pinnedMbid(album),
            pinned: library.pinnedRelease(album));
        library.facts.put(facts, folder: library.sidecarFolderFor(album));
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

  /// Trade a six-digit code for the access token.
  ///
  /// Answers exactly the same way for a wrong code and for pairing not being open at all, so
  /// nothing on the network can work out whether a code is currently on screen.
  Future<void> _pair(HttpRequest req) async {
    if (req.method != 'POST') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      return req.response.close();
    }
    final body = await utf8.decoder.bind(req).join();
    final decoded = jsonDecode(body.isEmpty ? '{}' : body);
    final map = decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
    if (!pairing.redeem((map['code'] ?? '').toString())) {
      req.response.statusCode = HttpStatus.forbidden;
      return req.response.close();
    }
    return _json(req.response, {
      'token': token,
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
      req.response.statusCode = HttpStatus.badRequest;
      return _json(req.response, {'error': '$e'});
    }
  }

  /// Dezelfde nummers in een andere volgorde, terwijl het lopende nummer doorspeelt.
  Future<void> _castRequeue(HttpRequest req) async {
    if (req.method != 'POST') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      return req.response.close();
    }
    final map = await _body(req);
    try {
      await cast.requeue(
        (map['deviceId'] ?? '') as String,
        [for (final id in (map['trackIds'] as List? ?? const [])) id.toString()],
        (map['index'] as int?) ?? 0,
      );
      return _json(req.response, {'ok': true});
    } catch (e) {
      req.response.statusCode = HttpStatus.badRequest;
      return _json(req.response, {'error': '$e'});
    }
  }

  Future<void> _castControl(HttpRequest req) async {
    if (req.method != 'POST') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      return req.response.close();
    }
    final map = await _body(req);
    try {
      await cast.control(
        (map['deviceId'] ?? '') as String,
        (map['action'] ?? '') as String,
        value: map['value'] as int?,
      );
      return _json(req.response, {'ok': true});
    } catch (e) {
      req.response.statusCode = HttpStatus.badRequest;
      return _json(req.response, {'error': '$e'});
    }
  }

  Future<Map<String, dynamic>> _body(HttpRequest req) async {
    final text = await utf8.decoder.bind(req).join();
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
    final body = await utf8.decoder.bind(req).join();
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
    final grens = castGrenzen(
      sampleRate: track.sampleRate,
      bits: track.bitsPerSample,
      maxSampleRate: maxRate ?? 0,
      maxBitDepth: maxBits ?? 0,
    );
    if (grens.omzetten) {
      // Een gekoppeld toestel vraagt om KLEIN (het gaat over iemands databundel), een speaker om
      // SNEL (de kopie wordt na het spelen weggegooid). Zie [Omzetrecept].
      final vanSpeaker = req.uri.queryParameters['cast'] == '1';
      return _streamResampled(req, file, grens.rate, grens.bits <= 0 ? 24 : grens.bits,
          recept: vanSpeaker ? receptCast : receptStroom);
    }
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
      {Omzetrecept recept = receptCast}) async {
    final map = recept.naam == receptCast.naam ? 'cast_cache' : 'stream_cache';
    final klaar = await transcoder.resampleToFile(file,
        maxSampleRate: maxRate,
        maxBits: maxBits,
        recept: recept,
        cacheDir: Directory('$appDir${Platform.pathSeparator}$map'));
    return serveFile(req, klaar ?? file, contentType: 'audio/flac');
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
    final text = await utf8.decoder.bind(req).join();
    final decoded = jsonDecode(text.isEmpty ? '{}' : text);
    return decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
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
    startTorrentDownload(body);
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

  /// The body of `POST /api/online/download`.
  void startTorrentDownload(Map<String, dynamic> body) {
    final manager = downloads;
    if (manager == null) return;
    final fileId = (body['fileId'] as num?)?.toInt();
    // Deliberately not awaited: enqueue starts the work and returns, and the caller watches
    // /api/jobs. Holding a request open for a download would time out long before it finished.
    manager.enqueue(SearchResult.fromJson(body), fileId: fileId);
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
    });
  }

  /// Deze pc bijwerken omdat een gekoppeld toestel erom vraagt. Zie `pc_bijwerker.dart`.
  ///
  /// **Waarom dit een eigen weg is en niet een bewerking bij [_corrections].** Die weg gaat over de
  /// bibliotheek: hij zoekt een album op, hij faalt met "dat album staat hier niet (meer)", en alles
  /// eraan is geschreven vanuit "verander iets aan de muziek". Dit verandert de app zelf. Een pc die
  /// deze weg nog niet kent antwoordt 404, en dat leest de telefoon als "kan het niet" — precies wat
  /// er dan ook aan de hand is.
  Future<void> _update(HttpRequest req) async {
    final body = await _jsonBody(req);
    if (body == null) return;
    final op = (body['op'] ?? 'status') as String;
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
        try {
          final o = await AiService(() => config.anthropicKey,
                  werkruimteVan: () => config.anthropicWorkspace)
              .maakRadioplan((body['zin'] ?? '') as String);
          return _json(req.response, {
            'genre': o.genre,
            'aantal': o.aantal,
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
        case 'removeTracks':
          final paths = <String>[];
          for (final id in (body['trackIds'] as List? ?? const [])) {
            final t = id is String ? catalog.track(id) : null;
            if (t != null) paths.add(t.path);
          }
          if (paths.isEmpty) return _json(req.response, {'ok': false, 'reason': 'niets gevonden'});
          await library.removeTracks(paths, fromDisk: body['fromDisk'] == true);
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
  /// The approved `to` and `fate` come back with the request rather than being worked out again:
  /// re-planning here would let the folder change between the screen someone agreed to and the
  /// files that move.
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

    try {
      final moved = await library.moveTracksToAlbum(tracks, target, config,
          moveFiles: body['moveFiles'] != false,
          plan: approved.isEmpty ? null : approved);
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

  Future<void> _art(HttpRequest req) async {
    final ref = Uri.decodeComponent(req.uri.pathSegments.last);
    final bytes = catalog.artwork(ref);
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
    final etag = '"${CoverEnricher.hoesMerk(bytes)}"';
    if (req.headers.value(HttpHeaders.ifNoneMatchHeader) == etag) {
      res.statusCode = HttpStatus.notModified;
      res.headers.set(HttpHeaders.etagHeader, etag);
      return res.close();
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
  Future<void> _json(HttpResponse res, Object body, {int status = HttpStatus.ok}) async {
    final bytes = utf8.encode(jsonEncode(body));
    res.statusCode = status;
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

/// A fresh access token. Generated once and kept, so a device stays paired across restarts.
String generateLanToken() {
  final rnd = Random.secure();
  return List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

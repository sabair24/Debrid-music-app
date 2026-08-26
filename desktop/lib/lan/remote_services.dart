/// Searching and downloading, from a device that does none of it itself.
///
/// On a Mac or an iPad there is no TorBox key, no Soulseek login, and — on the iPad — nowhere to
/// put a music library. So these ask the PC to do the work: the search runs there, the download
/// lands there, and the finished album reaches every device through the catalogue that already
/// syncs. One set of credentials, on the machine that already had them.
///
/// They SUBCLASS the real services rather than implementing an interface beside them. That is
/// deliberate: the screens hold `OnlineService`, `SoulseekService` and `DownloadManager` in forty
/// odd places, and a subclass slots into every one of them without a line of UI changing. The
/// inherited fields (a TorBox client, an aggregator) are simply never reached — every method that
/// would use them is overridden here.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../cloud/queue.dart';
import '../online.dart';
import '../organize.dart';
import '../soulseek.dart';
import '../torbox.dart';
import 'client.dart';

/// The one thing all three need: a call to the PC that either answers or says why not.
///
/// The endpoint is read at call time rather than captured, because these are built before the
/// pairing screen has been through — and after pairing the very same objects have to start
/// working, without the provider tree being rebuilt underneath the UI.
class _Rpc {
  _Rpc(this._endpointOf, {http.Client? client}) : _http = client ?? http.Client();

  final RemoteEndpoint? Function() _endpointOf;
  final http.Client _http;

  RemoteEndpoint get endpoint {
    final e = _endpointOf();
    if (e == null) throw const RemoteWorkException('Nog niet gekoppeld met je pc.');
    return e;
  }

  Map<String, String> get _headers => {'Authorization': 'Bearer ${endpoint.token}'};

  Future<Map<String, dynamic>> get(String path,
      {Map<String, String>? query, Duration timeout = const Duration(seconds: 90)}) async {
    // Ninety seconds: a torrent search fans out over several trackers, and the PC answers when
    // the slowest one has. Anything shorter gives up on searches that were about to succeed.
    final res = await _http
        .get(endpoint.baseUrl.replace(path: path, queryParameters: query), headers: _headers)
        .timeout(timeout);
    return _decode(res);
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 60)}) async {
    final res = await _http
        .post(endpoint.baseUrl.replace(path: path),
            headers: {..._headers, 'Content-Type': 'application/json'}, body: jsonEncode(body))
        .timeout(timeout);
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    final decoded = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    if (res.statusCode == 200) return map;
    // The PC puts a readable sentence in `error`; use it rather than a status code, because this
    // ends up in front of someone holding an iPad.
    throw RemoteException(
      (map['error'] as String?) ?? 'De pc antwoordde met ${res.statusCode}.',
      statusCode: res.statusCode,
    );
  }

  void close() => _http.close();
}

class RemoteOnlineService extends OnlineService {
  RemoteOnlineService(super.settings, RemoteEndpoint? Function() endpointOf, {http.Client? client})
      : _rpc = _Rpc(endpointOf, client: client);

  final _Rpc _rpc;

  /// True: the PC is the one that needs a key, and it would not have answered the pairing if it
  /// were not running. A false here would grey out the search box on the iPad forever.
  @override
  bool get torboxReady => true;

  @override
  Future<List<SearchResult>> search(String query,
      {void Function(List<SearchResult>)? onPartial}) async {
    final j = await _rpc.get('/api/online/search', query: {'q': query});
    final results = [
      for (final r in (j['results'] as List? ?? const []))
        if (r is Map<String, dynamic>) SearchResult.fromJson(r),
    ];
    // De stand van de RuTracker VAN DE PC overnemen. Het zoeken gebeurt daar, dus daar staat ook wat
    // er misging. Zonder dit las het scherm de RuTracker van dít toestel — die nooit bevraagd wordt —
    // en dan staat er eeuwig "niet bevraagd" terwijl de echte reden op de pc ligt.
    final rt = j['rutracker'];
    if (rt is Map) {
      rutracker.lastError = (rt['fout'] as String?) ?? '';
      rutracker.laatsteAantal = (rt['aantal'] as num?)?.toInt() ?? -1;
      rutracker.laatsteDoorZeef = (rt['doorZeef'] as num?)?.toInt() ?? -1;
    }
    // The PC streams nothing back mid-search, so the partial callback fires once, with everything.
    // The screens use it to fill the list as results arrive; getting them all at once is a slower
    // first paint, not a broken one.
    onPartial?.call(results);
    return results;
  }

  /// De RuTracker-aanmelding van dít toestel doorgeven aan de pc.
  ///
  /// **Waarom dit nodig is.** Het aanmeldvenster staat op de telefoon; het zoeken en het downloaden
  /// gebeuren op de pc. Die twee zaten niet aan elkaar vast, dus meldde je je op je telefoon aan
  /// terwijl de pc geen sessie had en RuTracker niet eens bevroeg. Op het scherm was dat niet te
  /// onderscheiden van "RuTracker heeft niets".
  ///
  /// De pc probeert het koekje meteen; wat eruit komt is de zin die je te lezen krijgt.
  Future<({bool ok, String reden})> stuurRutrackerSessie(String cookie, String ua) async {
    try {
      final j = await _rpc.post('/api/rutracker/sessie', {'cookie': cookie, 'ua': ua});
      return (ok: j['ok'] == true, reden: (j['reden'] as String?) ?? '');
    } catch (e) {
      return (ok: false, reden: 'De pc antwoordde niet: $e');
    }
  }

  @override
  Future<(TbTorrent, List<TbFile>)> tracklist(SearchResult r,
      {void Function(double, String)? onProgress}) async {
    // The PC reports nothing while it waits for TorBox to cache the torrent, so the one progress
    // call here is what stops the dialog opening at a frozen 0%.
    //
    // Eerlijk over wat dit is: één regel, en daarna drie minuten stilte. De pc kent de stand van
    // TorBox wél — hij zit ernaar te kijken — maar er is nog geen weg om die hierheen te sturen.
    // Zeg dus wat er gebeurt in plaats van te doen alsof het zo klaar is.
    onProgress?.call(
        0,
        'De pc haalt de tracklijst op bij TorBox. Staat de torrent daar nog niet klaar, '
        'dan moet de pc hem eerst zelf binnenhalen en kan dit even duren.');
    final j = await _rpc.post('/api/online/tracklist', r.toJson(),
        timeout: const Duration(minutes: 3));
    final files = [
      for (final f in (j['files'] as List? ?? const []))
        if (f is Map<String, dynamic>)
          TbFile((f['id'] as num?)?.toInt() ?? 0, (f['name'] ?? '') as String,
              f['shortName'] as String?, (f['size'] as num?)?.toInt() ?? 0, f['mimeType'] as String?),
    ];
    return (TbTorrent.fromJson({'id': j['torrentId'], 'files': const []}), files);
  }

  /// Playing an online result straight through, without downloading it, would mean streaming from
  /// TorBox with the PC's key. Not offered: the key stays on the PC, and the thing you actually
  /// want on a Mac or an iPad — the record in your library — is what a download gives you.
  @override
  Future<String> resolveStreamUrl(SearchResult r) =>
      throw const RemoteWorkException(
          'Online meespelen kan alleen op de pc. Download het nummer; het verschijnt daarna vanzelf hier.');

  @override
  Future<String> resolveTrackUrl(int torrentId, int fileId) =>
      throw const RemoteWorkException(
          'Online meespelen kan alleen op de pc. Download het nummer; het verschijnt daarna vanzelf hier.');

  /// Radio resolves an online stream per track, which is the same thing again. Null rather than a
  /// throw: the radio queue treats it as "this one could not be found" and moves on, which is
  /// exactly right — the local tracks in the queue keep playing.
  @override
  Future<String?> resolveRadio(String artist, String title, {bool instantOnly = true}) async => null;

  void dispose() => _rpc.close();
}

class RemoteSoulseekService extends SoulseekService {
  RemoteSoulseekService(super.settings, RemoteEndpoint? Function() endpointOf, {http.Client? client})
      : _rpc = _Rpc(endpointOf, client: client);

  final _Rpc _rpc;

  /// Whether the PC has a Soulseek login is not knowable from here without asking, and asking on
  /// every rebuild is not worth it. Assume yes; a search against a PC without one comes back with
  /// the PC's own sentence saying so, which is more useful than a greyed-out button.
  @override
  bool get available => true;

  @override
  bool get blocked => false;

  @override
  Duration? get blockedFor => null;

  /// [gebruikteVraag] meldt hier altijd de vraag zoals hij gesteld is: de trappenladder van
  /// [zoekLadder] wordt aan de PC-kant afgelopen, en welke trede het geworden is komt niet over de
  /// lijn terug. Liever niets melden dan iets melden dat niet klopt — het scherm zegt dan gewoon
  /// niets over een ruimere zoekopdracht.
  @override
  Future<List<SoulseekFile>> search(String query,
      {void Function(List<SoulseekFile>)? onPartial,
      void Function(String)? gebruikteVraag}) async {
    gebruikteVraag?.call(query.trim().replaceAll(RegExp(r'\s+'), ' '));
    final j = await _rpc.get('/api/soulseek/search', query: {'q': query});
    final files = <SoulseekFile>[];
    for (final f in (j['files'] as List? ?? const [])) {
      if (f is! Map<String, dynamic>) continue;
      final parsed = SoulseekFile.fromJson(f);
      if (parsed != null) files.add(parsed);
    }
    onPartial?.call(files);
    return files;
  }

  void dispose() => _rpc.close();
}

/// The job list, mirrored from the PC.
///
/// [jobs] is the very list the progress rows read, refilled from what the PC reports. Rebuilt in
/// place rather than replaced, because the base class exposes it as a `final List`.
class RemoteDownloadManager extends DownloadManager {
  RemoteDownloadManager(
    super.online,
    super.soulseek,
    super.musicRoot,
    super.onLibraryChanged,
    RemoteEndpoint? Function() endpointOf, {
    http.Client? client,
  }) : _rpc = _Rpc(endpointOf, client: client);

  final _Rpc _rpc;
  Timer? _poll;

  /// The last thing the PC said went wrong, for a screen that wants to show it.
  String? lastError;

  /// Where a request goes when the PC does not answer. Null when this device is not signed in, and
  /// then an unreachable PC is simply a failure, exactly as before.
  QueueBackend? queue;

  /// Name of this device, written into the queue item so the PC's list can say who asked.
  String requestedBy = '';

  /// Put a request in the queue instead of failing. Returns false when there is no queue to put it
  /// in, so the caller can report the original problem rather than a silent success.
  Future<bool> _enqueueForLater(String kind, String title, Map<String, dynamic> payload) async {
    final q = queue;
    if (q == null) return false;
    try {
      await q.put(QueueItem(
        id: newQueueId(),
        kind: kind,
        title: title,
        payload: payload,
        requestedBy: requestedBy,
        requestedAt: DateTime.now().toUtc(),
      ));
      lastError = null;
      notifyListeners();
      return true;
    } catch (e) {
      lastError = 'Kon niet in de wachtrij zetten: $e';
      notifyListeners();
      return false;
    }
  }

  /// Poll while anything is running, and slowly when nothing is. A download that takes twenty
  /// minutes should not cost twenty minutes of two-second requests once it is done.
  void startWatching() {
    // Idempotent: it is hung off a ChangeNotifier that fires more than once, and restarting the
    // timer on every notification would mean the list never settles.
    if (_poll != null) return;
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(refresh()));
    unawaited(refresh());
  }

  Future<void> refresh() async {
    try {
      final res = await _rpc.get('/api/jobs', timeout: const Duration(seconds: 15));
      lastError = null;
      _adopt(res['jobs'] as List? ?? const []);
    } catch (e) {
      lastError = e.toString();
    }
  }

  void _adopt(List<dynamic> wire) {
    final before = _fingerprint();
    jobs.clear();
    for (final j in wire) {
      if (j is! Map<String, dynamic>) continue;
      jobs.add(DownloadJob((j['name'] ?? '') as String, key: j['key'] as String?)
        ..progress = (j['progress'] as num?)?.toDouble() ?? 0
        ..status = (j['status'] ?? 'queued') as String
        ..detail = j['detail'] as String?
        ..queuePlace = (j['queuePlace'] as num?)?.toInt() ?? 0
        ..canCancel = j['canCancel'] == true
        // Zie de opmerking bij LanServer.jobsSnapshot: hiermee leest een gestopte download als
        // "Gestopt" en niet als "Mislukt".
        ..cancelled = j['cancelled'] == true
        ..trackKey = j['trackKey'] as String?);
    }
    // Only notify when something actually moved. This polls every two seconds, and rebuilding the
    // downloads screen on every tick makes a list that will not hold still under a finger.
    if (_fingerprint() != before) notifyListeners();
  }

  String _fingerprint() =>
      [for (final j in jobs) '${j.key ?? j.name}|${j.status}|${j.progress.toStringAsFixed(3)}|${j.detail ?? ''}']
          .join(';');

  /// [klaar] wordt hier bewust genegeerd. Het is een torrent die de PC-kant al heeft laten
  /// voorbereiden bij TorBox; over de lijn heeft dat geen betekenis, want de PC bereidt hem daar
  /// zelf voor en kent zijn eigen TorBox-sessie. Meesturen zou een tweede waarheid zijn.
  @override
  void enqueue(SearchResult result, {int? fileId, TbTorrent? klaar}) {
    unawaited(() async {
      final payload = {...result.toJson(), 'fileId': fileId};
      try {
        await _rpc.post('/api/online/download', payload);
        await refresh();
      } catch (e) {
        // The PC is off or unreachable: keep the request rather than losing it. It runs by itself
        // the moment the PC comes back — which is the whole point of asking from an iPad.
        if (await _enqueueForLater(QueueKind.torrent, result.name, payload)) return;
        lastError = e.toString();
        notifyListeners();
      }
    }());
  }

  @override
  Future<bool> enqueueSoulseekBest(List<SoulseekFile> candidates,
      {String? key, TrackTags? authority, SoulseekFile? exact, bool wachtOpAfloop = true}) async {
    final payload = <String, dynamic>{
      'candidates': [for (final c in candidates) c.toJson()],
      'key': key,
        // Without this the PC files the download under the UPLOADER's tags: their track number,
        // their idea of how many tracks the record has, their year. A wrong number collides with
        // one the album already uses, and a collision is what the library reads as two pressings —
        // which is how a single album ends up as four tiles.
      if (authority != null) 'authority': authority.toJson(),
      // Reist mee, anders zou de pc een handmatige keuze van de iPad alsnog herrangschikken.
      if (exact != null) 'exact': exact.toJson(),
    };
    try {
      final res = await _rpc.post('/api/soulseek/download', payload);
      await refresh();
      return res['ok'] == true;
    } catch (e) {
      // Queued rather than lost. The title comes from the authority when there is one — the
      // peer's own filename is whatever they happened to call it.
      final title = authority?.title ?? candidates.first.filename.split(RegExp(r'[\\/]')).last;
      if (await _enqueueForLater(QueueKind.soulseek, title, payload)) return true;
      lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// A whole album, downloaded BY THE PC.
  ///
  /// Without this override the base class runs here, on the Mac — and Soulseek allows exactly one
  /// login per account, so the client would either fail outright or fight the PC for the session.
  /// The two lists travel index-aligned, the same shape the local call takes.
  @override
  Future<int> enqueueSoulseekAlbum(List<List<SoulseekFile>> tracks,
      {List<TrackTags?> authorities = const []}) async {
    final payload = <String, dynamic>{
      'tracks': [
        for (final t in tracks) [for (final f in t) f.toJson()]
      ],
      'authorities': [
        for (var i = 0; i < tracks.length; i++)
          i < authorities.length ? authorities[i]?.toJson() : null
      ],
    };
    try {
      final res = await _rpc.post('/api/soulseek/download-album', payload);
      await refresh();
      return (res['started'] as num?)?.toInt() ?? 0;
    } catch (e) {
      // One queue item for the whole album, not one per track: the PC replays the same request it
      // would have received, so the tracks arrive together and share their authorities.
      final title = authorities.firstOrNull?.album ?? 'Album';
      if (await _enqueueForLater(QueueKind.soulseekAlbum, title, payload)) return tracks.length;
      lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  @override
  void cancelJob(DownloadJob job) {
    unawaited(() async {
      try {
        await _rpc.post('/api/jobs/cancel', {'key': job.key, 'name': job.name});
        await refresh();
      } catch (_) {/* the row stays as it is; the next poll tells the truth */}
    }());
  }

  /// De wenslijst staat op de pc, dus daar hoort dit ook te landen — zie `_jobStopWens`.
  @override
  Future<void> stopWens(DownloadJob job) async {
    try {
      await _rpc.post('/api/jobs/stopwens', {'key': job.key, 'name': job.name});
      await refresh();
    } catch (_) {/* de rij blijft staan; de volgende peiling vertelt de waarheid */}
  }

  @override
  void clearFinished() {
    unawaited(() async {
      try {
        await _rpc.post('/api/jobs/clear', const {});
        await refresh();
      } catch (_) {}
    }());
  }

  /// Nothing to resume here — whatever was running is running on the PC, and the next poll shows
  /// it. Returning 0 keeps the startup path identical on both.
  @override
  Future<int> resumePending({bool start = true}) async => 0;

  @override
  void dispose() {
    _poll?.cancel();
    _rpc.close();
    super.dispose();
  }
}

/// Thrown when a device asks for something only the machine with the files can do. Carries the
/// sentence to put in front of the user.
class RemoteWorkException implements Exception {
  final String message;
  const RemoteWorkException(this.message);
  @override
  String toString() => message;
}

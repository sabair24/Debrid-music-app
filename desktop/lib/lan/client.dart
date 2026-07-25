/// The other side of `server.dart`: this app talking to a PC that owns the music.
///
/// On the Mac and the iPad there is no music folder to scan, so the library comes from
/// `GET /api/catalog` instead. Everything else in the app is unchanged — see
/// [LibraryStore.loadRemote], which turns what this returns into the very same `Track` and `Album`
/// objects a disk scan produces.
///
/// Two ways of carrying the token, on purpose:
///   • API calls send `Authorization: Bearer` — the ordinary thing.
///   • `/stream/` and `/art/` put it in the query, because the things that fetch those URLs are
///     libmpv, `Image.network`, a Sonos and a KEF, and none of them can be told to set a header.
/// The server accepts both. Anything in the query is also in the server's log, which is the price;
/// it is a token for a music library on a home network, and the alternative is that nothing plays.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'dtos.dart';

/// A paired PC: where it is and what proves we may talk to it.
class RemoteEndpoint {
  /// `http://192.168.0.216:47820` — no trailing slash, no path.
  final Uri baseUrl;
  final String token;

  /// What the PC calls itself, for the settings screen. Not used to reach it.
  final String? name;

  const RemoteEndpoint({required this.baseUrl, required this.token, this.name});

  /// Accepts what a person types: `192.168.0.216`, `192.168.0.216:47820`, or a full URL.
  /// Returns null when there is nothing usable in it, so the caller can say so plainly.
  static Uri? parseHost(String input, {int defaultPort = 47820}) {
    var text = input.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'http://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    return Uri(
      scheme: uri.scheme.isEmpty ? 'http' : uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : defaultPort,
    );
  }

  Map<String, dynamic> toJson() =>
      {'baseUrl': baseUrl.toString(), 'token': token, 'name': name};

  static RemoteEndpoint? fromJson(Map<String, dynamic> j) {
    final url = Uri.tryParse((j['baseUrl'] ?? '').toString());
    final token = (j['token'] ?? '').toString();
    if (url == null || url.host.isEmpty || token.isEmpty) return null;
    return RemoteEndpoint(baseUrl: url, token: token, name: j['name'] as String?);
  }

  @override
  bool operator ==(Object other) =>
      other is RemoteEndpoint && other.baseUrl == baseUrl && other.token == token;

  @override
  int get hashCode => Object.hash(baseUrl, token);
}

/// A catalogue plus the ETag it came with. [catalog] is null when the PC answered 304, which means
/// "nothing changed" — the client keeps what it has rather than rebuilding an identical library.
class CatalogResponse {
  final CatalogDto? catalog;
  final String? etag;
  const CatalogResponse(this.catalog, this.etag);

  bool get unchanged => catalog == null;
}

/// What a PC says about itself before any pairing has happened.
class ServerHealth {
  final String name;
  final String version;
  final int trackCount;
  const ServerHealth({this.name = '', this.version = '', this.trackCount = 0});
}

/// A speaker, a television, or anything else on the network that can be handed a URL.
class CastDevice {
  const CastDevice({
    required this.id,
    required this.name,
    required this.kind,
    this.model = '',
    this.maxSampleRate = 0,
  });

  final String id;
  final String name;
  final String model;

  /// The highest rate this thing will accept, or 0 for no ceiling. A Sonos stops at 48 kHz, so a
  /// 24/96 record is converted on the way — worth saying before you press play rather than
  /// afterwards.
  final int maxSampleRate;

  /// `shield` for a device running this app, anything else for a UPnP renderer. The difference is
  /// worth showing: only the first plays the file untouched — a speaker takes what its own decoder
  /// will accept, and the PC converts to meet it.
  final String kind;

  bool get playsUntouched => kind == 'shield';

  static CastDevice fromJson(Map<String, dynamic> j) => CastDevice(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? 'Onbekend').toString(),
        kind: (j['kind'] ?? 'upnp').toString(),
        model: (j['model'] ?? '').toString(),
        maxSampleRate: (j['maxSampleRate'] as num?)?.toInt() ?? 0,
      );
}

class RemoteException implements Exception {
  final String message;

  /// 401/403 mean the pairing is no longer good — worth telling the user to pair again, rather
  /// than showing the same "kon de pc niet bereiken" as a pulled network cable.
  final int? statusCode;
  const RemoteException(this.message, {this.statusCode});

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

class RemoteClient {
  final RemoteEndpoint endpoint;
  final http.Client _http;

  /// Long enough for a big library over wifi, short enough that a PC which went to sleep does not
  /// leave the app on a spinner forever.
  final Duration timeout;

  RemoteClient(this.endpoint, {http.Client? client, this.timeout = const Duration(seconds: 30)})
      : _http = client ?? http.Client();

  Uri _api(String path, [Map<String, String>? query]) =>
      endpoint.baseUrl.replace(path: path, queryParameters: query);

  Map<String, String> get _headers => {'Authorization': 'Bearer ${endpoint.token}'};

  /// The library. Pass the ETag from last time and the PC answers 304 when nothing changed, which
  /// is the ordinary case on every poll — the fingerprint is over the CONTENT, so enriching a
  /// cover does not re-push twelve thousand tracks.
  Future<CatalogResponse> catalog({String? etag}) async {
    final res = await _get('/api/catalog', etag: etag);
    if (res.statusCode == 304) return CatalogResponse(null, etag);
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const RemoteException('De pc stuurde geen bibliotheek terug.');
    }
    return CatalogResponse(
      CatalogDto.fromJson(decoded),
      res.headers['etag'],
    );
  }

  /// The URL to hand libmpv. It carries the file extension because that is how players — and
  /// AVFoundation on the Apple side — work out the format; a URL ending in an opaque id gets
  /// refused before a byte is read.
  Uri streamUrl(TrackDto t, {int? maxSampleRate}) => endpoint.baseUrl.replace(
        path: t.streamPath,
        queryParameters: {
          'token': endpoint.token,
          if (maxSampleRate != null) 'maxRate': '$maxSampleRate',
        },
      );

  /// Add the token to a URL that was stored without one — what [LibraryStore] keeps in
  /// `Track.path`, handed over at the moment of playback.
  ///
  /// Anything not pointing at our own PC is returned untouched. A Radio queue mixes library tracks
  /// with resolved TorBox streams, and appending our pairing token to someone else's URL would
  /// both fail and hand the token to a stranger.
  String authorized(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host != endpoint.baseUrl.host || uri.port != endpoint.baseUrl.port) {
      return url;
    }
    return uri.replace(queryParameters: {...uri.queryParameters, 'token': endpoint.token})
        .toString();
  }

  /// Cover art. Same query-token reason as [streamUrl]: `Image.network` sets no headers.
  Uri artUrl(String ref) =>
      endpoint.baseUrl.replace(path: '/art/$ref', queryParameters: {'token': endpoint.token});

  /// Fetch a cover. Null rather than throwing when there simply isn't one — an album without art
  /// is normal, not a failure, and the caller would only swallow the exception anyway.
  Future<Uint8List?> art(String ref) async {
    try {
      final res = await _http.get(artUrl(ref)).timeout(timeout);
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  /// The read-only keys the PC is willing to share, so this device can look things up itself.
  /// Empty rather than throwing when the PC has none: that is a PC without a Discogs token, which
  /// is a perfectly ordinary thing to be.
  /// The speakers and televisions the PC can see.
  ///
  /// Asked of the PC rather than discovered here, and that is deliberate: SSDP is multicast, which
  /// an iPad may not send without an Apple entitlement, and the audio has to leave from the PC
  /// anyway. One implementation, on the machine that holds the music.
  Future<List<CastDevice>> castDevices() async {
    try {
      final res = await _get('/api/cast/devices');
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j is! List) return const [];
      return [
        for (final e in j)
          if (e is Map<String, dynamic>) CastDevice.fromJson(e),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Send a queue to one of them. The PC does the sending; this only says what and where.
  Future<bool> castPlay(String deviceId, List<String> trackIds, int index) =>
      _castPost('/api/cast/play', {'deviceId': deviceId, 'trackIds': trackIds, 'index': index});

  /// pause | resume | next | prev | stop | volume (with [value] 0-100).
  Future<bool> castControl(String deviceId, String action, {int? value}) => _castPost(
        '/api/cast/control',
        {'deviceId': deviceId, 'action': action, if (value != null) 'value': value},
      );

  Future<bool> _castPost(String path, Map<String, dynamic> body) async {
    try {
      final res = await _http
          .post(_api(path),
              headers: {..._headers, 'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(timeout);
      return res.statusCode == 200;
    } catch (_) {
      // A speaker that did not take it is a speaker that stays silent; the picker says so rather
      // than throwing into a build.
      return false;
    }
  }

  Future<Map<String, String>> config() async {
    try {
      final res = await _get('/api/config');
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j is! Map) return const {};
      return {
        for (final e in j.entries)
          if (e.value is String) '${e.key}': e.value as String,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Ask the PC to change something about the library.
  ///
  /// The album is named by the id the PC issued, not by its title: the library can hold two
  /// pressings of one record, and a title would be ambiguous exactly where it matters most.
  Future<void> edit(Map<String, dynamic> operation) async {
    final http.Response res;
    try {
      res = await _http
          .post(_api('/api/corrections'),
              headers: {..._headers, 'Content-Type': 'application/json'},
              body: jsonEncode(operation))
          .timeout(timeout);
    } catch (e) {
      throw RemoteException('Kon de pc niet bereiken: $e');
    }
    if (res.statusCode == 200) return;
    final decoded = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    throw RemoteException(
      (decoded is Map ? decoded['error'] as String? : null) ??
          'De pc weigerde de wijziging (${res.statusCode}).',
      statusCode: res.statusCode,
    );
  }

  /// Ask the PC a question whose answer is a JSON object. Same shape as [edit], but the body
  /// matters — a move plan is the whole point of the call.
  Future<Map<String, dynamic>> ask(String path, Map<String, dynamic> body) async {
    final http.Response res;
    try {
      res = await _http
          .post(_api(path),
              headers: {..._headers, 'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(timeout);
    } catch (e) {
      throw RemoteException('Kon de pc niet bereiken: $e');
    }
    final decoded = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    if (res.statusCode == 200) return map;
    throw RemoteException(
      (map['error'] as String?) ?? 'De pc antwoordde met ${res.statusCode}.',
      statusCode: res.statusCode,
    );
  }

  Future<http.Response> _get(String path, {String? etag, Map<String, String>? query}) async {
    final http.Response res;
    try {
      res = await _http
          .get(_api(path, query), headers: {
            ..._headers,
            if (etag != null) 'If-None-Match': etag,
          })
          .timeout(timeout);
    } catch (e) {
      throw RemoteException('Kon de pc niet bereiken: $e');
    }
    if (res.statusCode == 304 || res.statusCode == 200) return res;
    throw RemoteException(
      res.statusCode == 401 || res.statusCode == 403
          ? 'De koppeling met de pc is niet meer geldig. Koppel opnieuw.'
          : 'De pc antwoordde met ${res.statusCode}.',
      statusCode: res.statusCode,
    );
  }

  void close() => _http.close();

  // ── Before there is an endpoint ────────────────────────────────────────────
  //
  // Static, because pairing is exactly the moment when you do not have a token yet.

  /// Ask a PC who it is. Null when nothing at that address answers like our server — used by the
  /// pairing screen to tell "wrong address" apart from "wrong code".
  static Future<ServerHealth?> health(Uri baseUrl,
      {http.Client? client, Duration timeout = const Duration(seconds: 4)}) async {
    final c = client ?? http.Client();
    try {
      final res = await c.get(baseUrl.replace(path: '/health')).timeout(timeout);
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body);
      if (j is! Map || j['status'] != 'ok') return null;
      return ServerHealth(
        name: (j['name'] ?? j['deviceName'] ?? '').toString(),
        version: (j['version'] ?? '').toString(),
        trackCount: (j['trackCount'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    } finally {
      if (client == null) c.close();
    }
  }

  /// Redeem the six digits shown on the PC. Throws with a message meant to be read by the person
  /// holding the iPad, not by a log.
  static Future<RemoteEndpoint> pair(
    Uri baseUrl,
    String code, {
    required String deviceName,
    http.Client? client,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final c = client ?? http.Client();
    try {
      final res = await c
          .post(
            baseUrl.replace(path: '/pair'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'code': code, 'deviceName': deviceName}),
          )
          .timeout(timeout);
      if (res.statusCode == 403) {
        throw const RemoteException(
          'Die code klopt niet, of hij is verlopen. Vraag op de pc een nieuwe.',
          statusCode: 403,
        );
      }
      if (res.statusCode != 200) {
        throw RemoteException('Koppelen mislukte (${res.statusCode}).', statusCode: res.statusCode);
      }
      final j = jsonDecode(res.body);
      final token = (j is Map ? j['token'] : null)?.toString() ?? '';
      if (token.isEmpty) throw const RemoteException('De pc gaf geen sleutel terug.');
      return RemoteEndpoint(
        baseUrl: baseUrl,
        token: token,
        name: (j as Map)['name']?.toString(),
      );
    } on RemoteException {
      rethrow;
    } catch (e) {
      throw RemoteException('Kon de pc niet bereiken: $e');
    } finally {
      if (client == null) c.close();
    }
  }
}

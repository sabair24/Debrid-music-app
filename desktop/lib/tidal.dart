import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'settings.dart';

/// A TIDAL catalog track — used only as metadata to drive the torrent/Soulseek
/// source search (TIDAL itself can't be streamed by a third-party native app).
class TidalTrack {
  final String id;
  final String title;
  final String artist;
  const TidalTrack(this.id, this.title, this.artist);
  String get sourceQuery => artist.isEmpty ? title : '$artist $title';
  String get label => artist.isEmpty ? title : '$artist — $title';
}

/// TIDAL official developer API (openapi.tidal.com):
/// OAuth 2.1 Authorization-Code + PKCE via a loopback redirect, then catalog search.
/// No direct playback — full-track streaming isn't permitted for third-party native apps.
class TidalService {
  final AppSettings settings;
  TidalService(this.settings);

  static const _authorizeUrl = 'https://login.tidal.com/authorize';
  static const _tokenUrl = 'https://auth.tidal.com/v1/oauth2/token';
  static const _apiBase = 'https://openapi.tidal.com/v2';
  static const port = 8971;
  static const redirectUri = 'http://localhost:$port/tidal/callback';
  static const _scopes = 'user.read collection.read playlists.read search.read recommendations.read';

  bool get configured => settings.tidalClientId.isNotEmpty;
  bool get connected => settings.tidalAccessToken.isNotEmpty && settings.tidalRefreshToken.isNotEmpty;
  String get _country => settings.tidalCountry.isEmpty ? 'NL' : settings.tidalCountry;

  String _b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  /// Interactive login: opens the browser to TIDAL, catches the redirect on
  /// localhost, and exchanges the code (PKCE) for tokens. The user's password
  /// is only ever entered on TIDAL's own page.
  Future<void> login() async {
    if (settings.tidalClientId.isEmpty) throw 'Vul eerst je TIDAL Client ID in (Instellingen).';
    final rnd = Random.secure();
    final verifier = _b64url(List<int>.generate(32, (_) => rnd.nextInt(256)));
    final challenge = _b64url(sha256.convert(ascii.encode(verifier)).bytes);
    final state = _b64url(List<int>.generate(8, (_) => rnd.nextInt(256)));

    HttpServer server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    } catch (e) {
      throw 'Kan poort $port niet openen voor de TIDAL-login: $e';
    }
    final codeC = Completer<String>();
    final sub = server.listen((req) async {
      final code = req.uri.queryParameters['code'];
      final err = req.uri.queryParameters['error'];
      req.response.headers.contentType = ContentType.html;
      req.response.write(
        '<html><body style="background:#0C0D12;color:#eee;font-family:Segoe UI,sans-serif;text-align:center;padding-top:90px">'
        '<h2 style="color:#7C5CFF">DebridMusic</h2>'
        '<p>${code != null ? "TIDAL verbonden — je kan dit venster sluiten." : "Login mislukt: ${err ?? "geen code"}"}</p>'
        '</body></html>');
      await req.response.close();
      if (code != null) {
        if (!codeC.isCompleted) codeC.complete(code);
      } else if (!codeC.isCompleted) {
        codeC.completeError(err ?? 'geen code ontvangen');
      }
    });

    final authUri = Uri.parse(_authorizeUrl).replace(queryParameters: {
      'response_type': 'code',
      'client_id': settings.tidalClientId,
      'redirect_uri': redirectUri,
      'scope': _scopes,
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
      'state': state,
    });
    await _openBrowser(authUri.toString());

    String code;
    try {
      code = await codeC.future.timeout(const Duration(minutes: 5));
    } finally {
      await sub.cancel();
      await server.close(force: true);
    }
    await _exchange(code, verifier);
    await _fetchProfile();
  }

  Future<void> _openBrowser(String url) async {
    try {
      await Process.start('rundll32', ['url.dll,FileProtocolHandler', url]);
    } catch (_) {
      try {
        await Process.start('cmd', ['/c', 'start', '', url]);
      } catch (_) {}
    }
  }

  Future<void> _exchange(String code, String verifier) async {
    final body = {
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'client_id': settings.tidalClientId,
      'code_verifier': verifier,
    };
    if (settings.tidalClientSecret.isNotEmpty) body['client_secret'] = settings.tidalClientSecret;
    final r = await http
        .post(Uri.parse(_tokenUrl), headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: body)
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw 'Token-uitwisseling mislukt (${r.statusCode}): ${r.body}';
    _storeToken(jsonDecode(r.body) as Map<String, dynamic>);
    await settings.save();
  }

  void _storeToken(Map<String, dynamic> j) {
    settings.tidalAccessToken = (j['access_token'] ?? '') as String;
    final rt = (j['refresh_token'] ?? '') as String;
    if (rt.isNotEmpty) settings.tidalRefreshToken = rt;
    final expiresIn = (j['expires_in'] ?? 3600) as int;
    settings.tidalExpiry = DateTime.now().millisecondsSinceEpoch + expiresIn * 1000;
  }

  Future<String?> _validToken() async {
    if (settings.tidalAccessToken.isEmpty) return null;
    if (DateTime.now().millisecondsSinceEpoch < settings.tidalExpiry - 60000) return settings.tidalAccessToken;
    if (settings.tidalRefreshToken.isEmpty) return null;
    final body = {
      'grant_type': 'refresh_token',
      'refresh_token': settings.tidalRefreshToken,
      'client_id': settings.tidalClientId,
    };
    if (settings.tidalClientSecret.isNotEmpty) body['client_secret'] = settings.tidalClientSecret;
    try {
      final r = await http
          .post(Uri.parse(_tokenUrl), headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: body)
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      _storeToken(jsonDecode(r.body) as Map<String, dynamic>);
      await settings.save();
      return settings.tidalAccessToken;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _get(String path, Map<String, String> query) async {
    final tok = await _validToken();
    if (tok == null) throw 'Niet verbonden met TIDAL (log opnieuw in).';
    final uri = Uri.parse('$_apiBase$path').replace(queryParameters: query.isEmpty ? null : query);
    final r = await http.get(uri, headers: {
      'Authorization': 'Bearer $tok',
      'Accept': 'application/vnd.api+json',
    }).timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) {
      final body = r.body.length > 300 ? r.body.substring(0, 300) : r.body;
      throw 'TIDAL API ${r.statusCode}: $body';
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _fetchProfile() async {
    try {
      final j = await _get('/users/me', {});
      final data = j?['data'];
      if (data is Map) {
        settings.tidalUserId = (data['id'] ?? '').toString();
        final attr = data['attributes'];
        if (attr is Map) {
          final c = (attr['country'] ?? attr['countryCode']) as String?;
          if (c != null && c.isNotEmpty) settings.tidalCountry = c;
        }
      }
    } catch (_) {}
    if (settings.tidalCountry.isEmpty) settings.tidalCountry = 'NL';
    await settings.save();
  }

  /// Search the TIDAL catalog for tracks (title + primary artist), to feed the
  /// torrent/Soulseek source search.
  Future<List<TidalTrack>> searchTracks(String query) async {
    final j = await _get('/searchResults/${Uri.encodeComponent(query)}', {
      'countryCode': _country,
      'include': 'tracks,tracks.artists',
    });
    return j == null ? [] : parseTracks(j);
  }

  /// Parse a JSON:API searchResults response (with tracks + tracks.artists included)
  /// into TidalTracks. Static + defensive so it can be unit-tested without the network.
  static List<TidalTrack> parseTracks(Map<String, dynamic> j) {
    final included = (j['included'] as List?) ?? const [];
    final artistName = <String, String>{};
    for (final it in included) {
      if (it is Map && it['type'] == 'artists') {
        artistName[it['id'].toString()] = ((it['attributes']?['name']) ?? '') as String;
      }
    }
    final tracks = <TidalTrack>[];
    for (final it in included) {
      if (it is Map && it['type'] == 'tracks') {
        final attr = (it['attributes'] as Map?) ?? const {};
        final title = (attr['title'] ?? '') as String;
        String artist = '';
        final rel = it['relationships']?['artists']?['data'];
        if (rel is List && rel.isNotEmpty) artist = artistName[rel.first['id'].toString()] ?? '';
        if (title.isNotEmpty) tracks.add(TidalTrack(it['id'].toString(), title, artist));
      }
    }
    return tracks;
  }

  void disconnect() {
    settings.tidalAccessToken = '';
    settings.tidalRefreshToken = '';
    settings.tidalExpiry = 0;
    settings.tidalUserId = '';
    settings.save();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'json_body.dart';
import 'settings.dart';
import 'paths.dart';

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

/// Een plaat uit de TIDAL-catalogus.
///
/// Net zo mager als [TidalTrack] en met opzet: het enige dat er werkelijk toe doet is het id, want
/// dáármee haalt tiddl de plaat op. [jaar] staat erbij omdat er van veel platen een heruitgave
/// náást het origineel in de lijst komt, en de titel dan twee keer hetzelfde zegt.
class TidalAlbum {
  final String id;
  final String title;
  final String artist;
  final String jaar;
  const TidalAlbum(this.id, this.title, this.artist, [this.jaar = '']);
  String get sourceQuery => artist.isEmpty ? title : '$artist $title';
  String get label => artist.isEmpty ? title : '$artist — $title';
}

/// Wat één zoekopdracht oplevert: platen én losse nummers.
///
/// Uit dezelfde vraag, want TIDAL stuurt ze in één antwoord mee. Twee keer zoeken voor iets wat in
/// één keer terugkomt is twee keer wachten.
class TidalZoekResultaat {
  final List<TidalAlbum> albums;
  final List<TidalTrack> tracks;
  const TidalZoekResultaat(this.albums, this.tracks);
  bool get leeg => albums.isEmpty && tracks.isEmpty;
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
  // TIDAL rejects http/localhost redirects, so we use the registered custom scheme.
  // A Windows URI-scheme handler (added by the installer) writes the callback URL
  // to tidal_cb.txt, which the app polls.
  static const redirectUri = 'debridmusic://tidal/callback';
  static const _scopes = 'user.read collection.read playlists.read search.read recommendations.read';

  String? _pendingVerifier; // held between opening the browser and the redirect coming back

  bool get configured => settings.tidalClientId.isNotEmpty;
  bool get connected => settings.tidalAccessToken.isNotEmpty && settings.tidalRefreshToken.isNotEmpty;
  String get _country => settings.tidalCountry.isEmpty ? 'NL' : settings.tidalCountry;

  String _b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  static String _dataDir() => appDir;

  File _callbackFile() => File('${_dataDir()}${Platform.pathSeparator}tidal_cb.txt');

  /// Extract the auth code from a callback URL / pasted text (or a bare code).
  static String? extractCode(String text) {
    final t = text.replaceAll('"', '').trim();
    final q = t.indexOf('?');
    if (q >= 0) {
      try {
        return Uri.splitQueryString(t.substring(q + 1))['code'];
      } catch (_) {}
    }
    return (t.isEmpty || t.contains(' ') || t.contains('://')) ? null : t; // else treat as a bare code
  }

  /// Interactive login: opens the browser to TIDAL, then polls the file that the
  /// registered debridmusic:// URI-scheme handler writes. The user's password is
  /// only ever entered on TIDAL's own page.
  Future<void> login() async {
    if (settings.tidalClientId.isEmpty) throw 'Vul eerst je TIDAL Client ID in (Instellingen).';
    final rnd = Random.secure();
    final verifier = _b64url(List<int>.generate(32, (_) => rnd.nextInt(256)));
    final challenge = _b64url(sha256.convert(ascii.encode(verifier)).bytes);
    final state = _b64url(List<int>.generate(8, (_) => rnd.nextInt(256)));
    _pendingVerifier = verifier;

    final cb = _callbackFile();
    try {
      if (await cb.exists()) await cb.delete();
    } catch (_) {}

    // Build the query manually so spaces in scope become %20 (TIDAL can reject '+').
    final params = <String, String>{
      'response_type': 'code',
      'client_id': settings.tidalClientId,
      'redirect_uri': redirectUri,
      'scope': _scopes,
      'code_challenge_method': 'S256',
      'code_challenge': challenge,
      'state': state,
    };
    final authUrl = '$_authorizeUrl?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
    // Debug: write the exact URL so it can be inspected if TIDAL errors.
    try {
      await File('${_dataDir()}${Platform.pathSeparator}tidal_auth_url.txt').writeAsString(authUrl);
    } catch (_) {}
    await _openBrowser(authUrl);

    String? code;
    for (var i = 0; i < 600; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (connected) return; // completed via manual paste
      if (await cb.exists()) {
        try {
          code = extractCode(await cb.readAsString());
          await cb.delete();
        } catch (_) {}
        if (code != null) break;
      }
    }
    if (code == null) {
      throw 'Geen TIDAL-code ontvangen. Klik "Openen" als je browser dat vraagt, of plak de debridmusic://-URL handmatig.';
    }
    await _exchange(code, verifier);
    await _fetchProfile();
  }

  /// Manual fallback: exchange a code the user pasted (full callback URL or bare code).
  Future<void> completeManual(String pasted) async {
    final code = extractCode(pasted);
    if (code == null || code.isEmpty) throw 'Geen geldige code gevonden in wat je plakte.';
    final verifier = _pendingVerifier;
    if (verifier == null) throw 'Klik eerst "Verbind TIDAL" (dan opent de browser).';
    await _exchange(code, verifier);
    await _fetchProfile();
  }

  /// Open the Tidal sign-in page in the user's browser.
  ///
  /// url_launcher rather than spawning rundll32: the Windows-only commands did nothing on a Mac,
  /// and on iOS there is no process to spawn at all — the OAuth flow would simply hang with no
  /// page ever appearing.
  Future<void> _openBrowser(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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
    if (r.statusCode != 200) {
      try {
        await File('${_dataDir()}${Platform.pathSeparator}tidal_error.txt').writeAsString('exchange ${r.statusCode}: ${r.body}');
      } catch (_) {}
      throw 'Token-uitwisseling mislukt (${r.statusCode}): ${r.body}';
    }
    _storeToken(jsonBody(r) as Map<String, dynamic>);
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
      _storeToken(jsonBody(r) as Map<String, dynamic>);
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
    return jsonBody(r) as Map<String, dynamic>;
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

  /// Zoeken naar platen én nummers in één vraag.
  ///
  /// **Waarom hier een terugval in zit.** `albums,albums.artists,tracks,tracks.artists` is meer dan
  /// deze app tot nu toe vroeg. Weigert TIDAL dat ooit — een grens op het aantal relaties, een
  /// hernoemde relatie — dan komt er een 4xx terug en zou het zoeken in één klap helemaal stuk
  /// zijn. Dus valt hij dan terug op de smalle vraag die er al stond: geen platen, maar de nummers
  /// doen het nog. Is er werkelijk iets mis (geen verbinding, verlopen aanmelding), dan gooit
  /// [searchTracks] dezelfde fout alsnog naar het scherm.
  Future<TidalZoekResultaat> search(String query) async {
    Map<String, dynamic>? j;
    try {
      j = await _get('/searchResults/${Uri.encodeComponent(query)}', {
        'countryCode': _country,
        'include': 'albums,albums.artists,tracks,tracks.artists',
      });
    } catch (_) {
      j = null;
    }
    if (j == null) return TidalZoekResultaat(const [], await searchTracks(query));
    return TidalZoekResultaat(parseAlbums(j), parseTracks(j));
  }

  /// Artiest-id → naam, uit het `included`-blok.
  ///
  /// Twee parsers lopen dezelfde lijst af; dit is de helft die ze delen.
  static Map<String, String> _artiestNamen(List<dynamic> included) {
    final namen = <String, String>{};
    for (final it in included) {
      if (it is Map && it['type'] == 'artists') {
        namen[it['id'].toString()] = ((it['attributes']?['name']) ?? '') as String;
      }
    }
    return namen;
  }

  /// Parse a JSON:API searchResults response (with tracks + tracks.artists included)
  /// into TidalTracks. Static + defensive so it can be unit-tested without the network.
  static List<TidalTrack> parseTracks(Map<String, dynamic> j) {
    final included = (j['included'] as List?) ?? const [];
    final artistName = _artiestNamen(included);
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

  /// Hetzelfde als [parseTracks], maar voor de platen.
  ///
  /// Een antwoord zónder albums levert een lege lijst op en geen fout. Dat is precies wat er
  /// gebeurt als TIDAL de bredere `include` niet honoreert, en dan hoort de nummerlijst het gewoon
  /// te blijven doen.
  static List<TidalAlbum> parseAlbums(Map<String, dynamic> j) {
    final included = (j['included'] as List?) ?? const [];
    final namen = _artiestNamen(included);
    final albums = <TidalAlbum>[];
    for (final it in included) {
      if (it is! Map || it['type'] != 'albums') continue;
      final attr = (it['attributes'] as Map?) ?? const {};
      final title = (attr['title'] ?? '').toString();
      if (title.isEmpty) continue;
      var artist = '';
      final rel = it['relationships']?['artists']?['data'];
      if (rel is List && rel.isNotEmpty) artist = namen[rel.first['id'].toString()] ?? '';
      // releaseDate is "1982-11-30"; alleen het jaar is bruikbaar, en het veld mag ontbreken.
      final datum = (attr['releaseDate'] ?? '').toString();
      albums.add(TidalAlbum(it['id'].toString(), title, artist,
          datum.length >= 4 ? datum.substring(0, 4) : ''));
    }
    return albums;
  }

  void disconnect() {
    settings.tidalAccessToken = '';
    settings.tidalRefreshToken = '';
    settings.tidalExpiry = 0;
    settings.tidalUserId = '';
    settings.save();
  }
}

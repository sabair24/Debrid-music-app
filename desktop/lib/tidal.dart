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
import 'warm_log.dart';

/// Eén regel in start.log per stap van het inloggen.
///
/// **Waarom dit erbij moest.** Het inloggen bleef hangen zonder dat er íéts omviel: geen fout in het
/// logboek, geen antwoord van Tidal op schijf, en de app draaide vrolijk door met zijn scans. Dan
/// blijft er niets over dan raden welke van de vijf stappen niet terugkwam — en dat is drie ronden
/// lang precies wat er gebeurde.
///
/// Nooit de code of het token zelf: alleen hoe lang iets was en wat de statuscode was. Een logboek
/// dat je aan iemand wil kunnen sturen mag geen sleutels bevatten.
void _spoor(String regel) {
  try {
    WarmLog('$appDir${Platform.pathSeparator}start.log').line('tidal: $regel');
  } catch (_) {/* een spoor dat niet lukt mag nooit de weg blokkeren die het volgt */}
}

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
/// OAuth 2.1 Authorization-Code + PKCE via een https-terugkoppeling, dan catalogus doorzoeken.
/// No direct playback — full-track streaming isn't permitted for third-party native apps.
class TidalService {
  final AppSettings settings;
  TidalService(this.settings);

  static const _authorizeUrl = 'https://login.tidal.com/authorize';
  static const _tokenUrl = 'https://auth.tidal.com/v1/oauth2/token';
  static const _apiBase = 'https://openapi.tidal.com/v2';
  /// Waar TIDAL je browser naartoe stuurt als het inloggen gelukt is.
  ///
  /// **Waarom dit tidal.com is en geen adres van deze app.** Er stond hier `debridmusic://tidal/
  /// callback`, en het dashboard van TIDAL neemt zo'n adres ook gewoon aan — maar de inlogdienst
  /// stuurt er niet naartoe. Hij logt je in en zet je op zijn eigen "Login successful"-pagina,
  /// zonder één woord over wat er misging. Aan deze kant zag je dus een knop die eeuwig bleef
  /// draaien, terwijl in de browser alles gelukt leek.
  ///
  /// Met een https-adres gebeurt het wél: je landt op tidal.com met `?code=…` in de adresbalk. Dat
  /// is ook wat andere bureaublad-spelers doen. De prijs is dat er niets automatisch terugkomt —
  /// tidal.com is niet van ons, dus die code moet je zelf uit de adresbalk plakken. Eén keer, en
  /// dan nooit meer.
  ///
  /// Dit moet **letterlijk** overeenkomen met wat er in het dashboard bij Redirect URIs staat, hier
  /// én bij het inwisselen van de code.
  static const redirectUri = 'https://www.tidal.com';
  static const _scopes = 'user.read collection.read playlists.read search.read recommendations.read';

  String? _pendingVerifier; // held between opening the browser and the redirect coming back

  bool get configured => settings.tidalClientId.isNotEmpty;
  bool get connected => settings.tidalAccessToken.isNotEmpty && settings.tidalRefreshToken.isNotEmpty;
  String get _country => settings.tidalCountry.isEmpty ? 'NL' : settings.tidalCountry;

  String _b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  static String _dataDir() => appDir;

  /// Het pad van een zoekopdracht: de zoekterm ís de bron-id.
  ///
  /// **Kleingeschreven, en dat is geen smaak.** Hier stond `/searchResults/`, en TIDAL antwoordde
  /// daarop met `400 INVALID_RESOURCE_ID` met de vinger bij `data/id` — dus niet "dit pad bestaat
  /// niet" maar "die id deugt niet". In TIDAL's eigen voorbeelden staat het pad kleingeschreven, en
  /// een REST-pad is hoofdlettergevoelig.
  ///
  /// De zoekterm gaat er gecodeerd in: een spatie wordt `%20`. Dat is wat TIDAL's eigen voorbeeld
  /// ook doet, en een kale spatie in een pad is sowieso geen geldig adres.
  static String zoekPad(String query) => '/searchresults/${Uri.encodeComponent(query.trim())}';

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

  /// Stap 1: de browser openen op TIDAL's inlogpagina, en de verifier onthouden.
  ///
  /// Geeft meteen terug. Er komt hier **niets** vanzelf terug: TIDAL zet je na het inloggen op
  /// tidal.com, en die pagina is niet van ons. Wat er daar in de adresbalk staat gaat via
  /// [completeManual] naar binnen. Zie [redirectUri] voor waarom dat zo is.
  ///
  /// Je wachtwoord tik je alleen op TIDAL's eigen pagina in; deze app ziet het nooit.
  Future<void> login() async {
    if (settings.tidalClientId.isEmpty) throw 'Vul eerst je TIDAL Client ID in (Instellingen).';
    final rnd = Random.secure();
    final verifier = _b64url(List<int>.generate(32, (_) => rnd.nextInt(256)));
    final challenge = _b64url(sha256.convert(ascii.encode(verifier)).bytes);
    final state = _b64url(List<int>.generate(8, (_) => rnd.nextInt(256)));
    _pendingVerifier = verifier;

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
    _spoor('stap 1 — browser openen (scopes: ${_scopes.split(" ").length}, redirect: $redirectUri)');
    await _openBrowser(authUrl);
    _spoor('stap 1 klaar — browser is gevraagd te openen; nu wacht hij op jouw plakwerk');
  }

  /// Stap 2: de code inwisselen die je uit de adresbalk plakte (het hele adres mag).
  Future<void> completeManual(String pasted) async {
    _spoor('stap 2 — geplakt (${pasted.length} tekens)');
    final code = extractCode(pasted);
    if (code == null || code.isEmpty) {
      _spoor('stap 2 gestopt — geen code in wat er geplakt is');
      throw 'Geen geldige code gevonden in wat je plakte.';
    }
    final verifier = _pendingVerifier;
    if (verifier == null) {
      _spoor('stap 2 gestopt — geen verifier; stap 1 is in deze sessie niet geklikt');
      throw 'Klik eerst op "Stap 1 · Inloggen bij TIDAL" — de app moet die knop in dezelfde '
          'sessie gezien hebben, anders mist hij het geheim dat bij jouw code hoort.';
    }
    _spoor('code gevonden (${code.length} tekens), inwisselen...');
    await _exchange(code, verifier);
    await _fetchProfile();
    _spoor('verbonden ✓');
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
    _spoor('token-antwoord: ${r.statusCode}');
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
      // Het pad erbij, zonder het token. Bij een 400 op een zoekopdracht is de vraag altijd "wat
      // stuurde hij dan?", en daar was tot nu toe niets over terug te vinden.
      _spoor('API ${r.statusCode} op $path (${query['include'] ?? "geen include"})');
      throw 'TIDAL API ${r.statusCode}: $body';
    }
    return jsonBody(r) as Map<String, dynamic>;
  }

  Future<void> _fetchProfile() async {
    _spoor('token bewaard, profiel ophalen...');
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
    final j = await _get(zoekPad(query), {
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
      j = await _get(zoekPad(query), {
        'countryCode': _country,
        'include': 'tracks,tracks.artists,tracks.albums,albums,albums.artists',
      });
    } catch (e) {
      _spoor('brede zoekvraag geweigerd ($e) — terugvallen op alleen nummers');
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

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Local, on-device settings (API tokens / logins). Stored as JSON in
/// %APPDATA%\DebridMusic\settings.json — never committed to the repo.
class AppSettings extends ChangeNotifier {
  String discogsToken = '';
  String torboxToken = '';
  String lastfmKey = '';
  String soulseekUser = '';
  String soulseekPass = '';
  String rutrackerUser = '';
  String rutrackerPass = '';
  String rutrackerCookie = ''; // bb_session cookie, kept so we don't re-login (or re-captcha) each run
  // TIDAL: client id/secret entered by the user; the rest is managed by the OAuth flow.
  String tidalClientId = '';
  String tidalClientSecret = '';
  String tidalAccessToken = '';
  String tidalRefreshToken = '';
  int tidalExpiry = 0; // epoch ms when the access token expires
  String tidalUserId = '';
  String tidalCountry = '';

  static File file() {
    final base = Platform.environment['APPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    final sep = Platform.pathSeparator;
    return File('$base${sep}DebridMusic${sep}settings.json');
  }

  Future<void> load() async {
    try {
      final f = file();
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        discogsToken = (m['discogs_token'] ?? '') as String;
        torboxToken = (m['torbox_token'] ?? '') as String;
        lastfmKey = (m['lastfm_key'] ?? '') as String;
        soulseekUser = (m['soulseek_user'] ?? '') as String;
        soulseekPass = (m['soulseek_pass'] ?? '') as String;
        rutrackerUser = (m['rutracker_user'] ?? '') as String;
        rutrackerPass = (m['rutracker_pass'] ?? '') as String;
        rutrackerCookie = (m['rutracker_cookie'] ?? '') as String;
        tidalClientId = (m['tidal_client_id'] ?? '') as String;
        tidalClientSecret = (m['tidal_client_secret'] ?? '') as String;
        tidalAccessToken = (m['tidal_access_token'] ?? '') as String;
        tidalRefreshToken = (m['tidal_refresh_token'] ?? '') as String;
        tidalExpiry = (m['tidal_expiry'] ?? 0) as int;
        tidalUserId = (m['tidal_user_id'] ?? '') as String;
        tidalCountry = (m['tidal_country'] ?? '') as String;
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> save() async {
    try {
      final f = file();
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({
        'discogs_token': discogsToken,
        'torbox_token': torboxToken,
        'lastfm_key': lastfmKey,
        'soulseek_user': soulseekUser,
        'soulseek_pass': soulseekPass,
        'rutracker_user': rutrackerUser,
        'rutracker_pass': rutrackerPass,
        'rutracker_cookie': rutrackerCookie,
        'tidal_client_id': tidalClientId,
        'tidal_client_secret': tidalClientSecret,
        'tidal_access_token': tidalAccessToken,
        'tidal_refresh_token': tidalRefreshToken,
        'tidal_expiry': tidalExpiry,
        'tidal_user_id': tidalUserId,
        'tidal_country': tidalCountry,
      }));
    } catch (_) {}
    notifyListeners();
  }
}

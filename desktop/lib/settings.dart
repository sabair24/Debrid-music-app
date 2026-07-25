import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'paths.dart';

/// Local, on-device settings (API tokens / logins). Stored as settings.json in the app's own
/// folder (see paths.dart) — never committed to the repo.
class AppSettings extends ChangeNotifier {
  String discogsToken = '';
  String torboxToken = '';
  String lastfmKey = '';
  String soulseekUser = '';
  String soulseekPass = '';
  /// Port we LISTEN on for incoming Soulseek peers. Soulseek only delivers a firewalled peer's
  /// search results if we are reachable, so 0 (= don't listen) loses most results. Use the same
  /// port the native client uses, since the router already forwards it.
  int soulseekPort = 0;
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
  // Sharing this library with the Mac, the iPad and the Shield. The token is generated once and
  // then kept: it is what a paired device authenticates with, so regenerating it would silently
  // unpair everything.
  bool lanEnabled = true;
  int lanPort = 47820;
  String lanToken = '';

  /// This PC's own id in the cloud, so a device knows which machine it asked. Generated once and
  /// kept: changing it would orphan every grant handed out under the old one.
  String serverId = '';
  /// Where the music lives. Only the machine that owns the files sets this.
  String musicRoot = '';

  static File file() {
    return appFile('settings.json');
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
        soulseekPort = (m['soulseek_port'] ?? 0) as int;
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
        lanEnabled = (m['lan_enabled'] ?? true) as bool;
        lanPort = (m['lan_port'] ?? 47820) as int;
        lanToken = (m['lan_token'] ?? '') as String;
        serverId = (m['server_id'] ?? '') as String;
        musicRoot = (m['music_root'] ?? '') as String;
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
        'soulseek_port': soulseekPort,
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
        'lan_enabled': lanEnabled,
        'lan_port': lanPort,
        'lan_token': lanToken,
        'server_id': serverId,
        'music_root': musicRoot,
      }));
    } catch (_) {}
    notifyListeners();
  }
}

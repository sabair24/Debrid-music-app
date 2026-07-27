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

  /// Let the PC look records up in the background instead of waiting for you to open them.
  ///
  /// Only the owner acts on this. Off means the app behaves as it did: the first visit to a record
  /// pays for the lookup, every visit after that is free.
  bool warmFacts = true;

  static File file() {
    return appFile('settings.json');
  }

  /// The last copy that parsed. This file holds the only passwords the app has and they exist
  /// nowhere else — so there is always a second one.
  static File backupFile() => appFile('settings.bak.json');

  /// Set when the file on disk exists but could not be read.
  ///
  /// While this is true [save] refuses to write. A truncated file used to parse as "every field is
  /// empty", and the next save — from a TIDAL token refresh, a rescan, anything — made that the
  /// truth. Reading a broken file is recoverable; overwriting a broken file with blanks is not.
  bool loadFailed = false;

  /// Why, in a sentence, for the settings screen to show.
  String loadError = '';

  /// A probe. [_testAll] builds a throwaway AppSettings to check one service without touching the
  /// real one; if anything down that path ever calls [save], it would write an object that has
  /// never seen your TIDAL tokens, your LAN token or your music folder straight over the real file.
  bool readOnly = false;

  Future<void> load() async {
    final f = file();
    final backup = backupFile();
    loadFailed = false;
    loadError = '';
    try {
      if (await f.exists()) {
        try {
          _apply(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
          // A file that parsed AND is at least as complete as the spare becomes the new spare.
          //
          // Parsing is not enough on its own. A file full of empty strings is perfectly valid JSON:
          // it loads without complaint, `loadFailed` stays false, and the spare is then replaced by
          // those blanks — so the protection against an unreadable file does nothing against a
          // readable file with nothing in it. That is exactly what a stray `AppSettings().save()`
          // produces, and it is the shape the near-miss on Windows would have taken.
          try {
            if (await _atLeastAsComplete(backup)) await f.copy(backup.path);
          } catch (_) {/* a spare we could not write is not a reason to fail the start */}
          notifyListeners();
          return;
        } catch (e) {
          loadError = '$e';
        }
      } else if (!await backup.exists()) {
        notifyListeners();
        return; // a first run, not a loss
      }

      // Gone, or there and unreadable. Either way the spare is what it is FOR.
      //
      // A missing file used to take the branch above and stop: "a first run, not a loss". But a
      // settings.json that has been deleted — a cleanup tool, a sync conflict, a restored profile —
      // is not a first run, and next to it sat a spare holding every token. The app started blank
      // and asked for credentials it already had. Worse, filling the dialog in then wrote a file
      // covering only the fields that dialog owns: the LAN token, the server id, the music folder
      // and the TIDAL tokens are not on it, so the "repair" completed the loss. Reading the spare
      // first means the object is whole by the time anyone presses Save.
      if (await backup.exists()) {
        try {
          _apply(jsonDecode(await backup.readAsString()) as Map<String, dynamic>);
          debugPrint(loadError.isEmpty
              ? 'settings.json is gone — recovered from settings.bak.json'
              : 'settings.json unreadable ($loadError) — recovered from settings.bak.json');
          // Recovered, so saving is safe again: what is in memory is a real set of settings.
          loadFailed = false;
          loadError = '';
          // Put the primary back, or every start from here on runs on the spare and the file the
          // user (and every other tool) looks at stays missing. Safe precisely because the object is
          // whole again — that is what the branch above just established.
          try {
            if (!await f.exists()) await backup.copy(f.path);
          } catch (_) {/* running from the spare still works; this is only tidiness */}
          notifyListeners();
          return;
        } catch (_) {/* both gone; fall through */}
      }

      // Nothing readable anywhere. Keep the broken file — it is the only trace of the passwords —
      // and refuse to save over it.
      loadFailed = true;
      debugPrint('settings.json unreadable and no usable backup: $loadError');
    } catch (e) {
      loadFailed = true;
      loadError = '$e';
    }
    notifyListeners();
  }

  /// How many credentials are actually filled in. The measure of "worth keeping".
  static int _filled(Map<String, dynamic> m) => [
        'discogs_token', 'torbox_token', 'lastfm_key', 'soulseek_user', 'soulseek_pass',
        'rutracker_user', 'rutracker_pass', 'tidal_client_id', 'tidal_client_secret',
        'tidal_refresh_token', 'lan_token', 'music_root',
      ].where((k) => (m[k] ?? '').toString().isNotEmpty).length;

  /// Is what was just loaded at least as complete as the spare on disk?
  ///
  /// Equal counts still refresh the spare, so ordinary edits keep it current. Only a file that has
  /// LOST credentials is refused — and then the older, fuller copy stays exactly where it is.
  Future<bool> _atLeastAsComplete(File backup) async {
    try {
      if (!await backup.exists()) return true;
      final old = jsonDecode(await backup.readAsString());
      if (old is! Map<String, dynamic>) return true;
      final before = _filled(old);
      final now = _filled(toJson());
      if (now >= before) return true;
      debugPrint('Keeping settings.bak.json: it holds $before credentials and this file has $now');
      return false;
    } catch (_) {
      return true; // an unreadable spare is worth replacing
    }
  }

  /// The user has typed their settings again and pressed Save, so writing is wanted after all.
  ///
  /// [save] refuses while [loadFailed] — the broken file is the only trace of the passwords, and
  /// blanks over it would be final. That protection has to end somewhere, and this is the somewhere:
  /// an explicit save from the settings screen, where the values on screen are the ones the user
  /// just entered rather than the empty defaults of a failed load.
  void forgetLoadFailure() {
    loadFailed = false;
    loadError = '';
  }

  /// Take a settings map as [toJson] produces it. Public so the account copy can be merged in
  /// without this file needing to know anything about Firestore.
  void applyJson(Map<String, dynamic> m) {
    _apply(m);
    notifyListeners();
  }

  void _apply(Map<String, dynamic> m) {
    {
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
        warmFacts = (m['warm_facts'] ?? true) as bool;
    }
  }

  /// Everything worth writing down, as it goes into the file.
  Map<String, dynamic> toJson() => {
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
        'warm_facts': warmFacts,
      };

  /// Write the settings down.
  ///
  /// Through a temp file and a rename, like every other state file in this app
  /// (`lan/tokens.dart`, `lan/state_store.dart`, `album_facts.dart`). It used to be a bare
  /// `writeAsString`, so a crash or a power cut mid-write truncated the one file holding the
  /// passwords — and the truncated file then read back as "everything is empty".
  Future<void> save() async {
    if (readOnly) {
      debugPrint('Refusing to save a probe AppSettings over the real one');
      return;
    }
    if (loadFailed) {
      // The file on disk is broken and we could not recover it. What is in memory is defaults, and
      // writing defaults over the only copy of the passwords is how the loss becomes permanent.
      debugPrint('Refusing to save: settings.json could not be read ($loadError)');
      return;
    }
    try {
      final f = file();
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(toJson()));
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('settings.json not written: $e');
    }
    notifyListeners();
  }
}

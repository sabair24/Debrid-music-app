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
      }));
    } catch (_) {}
    notifyListeners();
  }
}

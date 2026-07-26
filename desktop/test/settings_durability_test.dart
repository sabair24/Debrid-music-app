/// The one file with the passwords in it.
///
/// `settings.json` holds the Soulseek and RuTracker logins, the TorBox key and the TIDAL tokens,
/// and they exist nowhere else. It used to be written with a bare `writeAsString` — no temp file,
/// no rename — while every other state file in the app does it properly. And reading it swallowed
/// every error, so a truncated file came back as "every field is empty" and the next save made that
/// permanent.
///
/// Same shape of bug as the one that emptied `corrections.json`, on a file that is worse to lose.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_settings_');
    setAppDirForTest(scratch.path);
  });

  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<AppSettings> seeded() async {
    final s = AppSettings()
      ..soulseekUser = 'saber'
      ..soulseekPass = 'geheim'
      ..rutrackerUser = 'saber'
      ..rutrackerPass = 'ookgeheim'
      ..rutrackerCookie = 'bb_session=abc123'
      ..torboxToken = 'tb-key'
      ..musicRoot = r'D:\Flac music 2024';
    await s.save();
    return s;
  }

  group('an ordinary life', () {
    test('what you type comes back', () async {
      await seeded();
      final again = AppSettings();
      await again.load();

      expect(again.soulseekUser, 'saber');
      expect(again.soulseekPass, 'geheim');
      expect(again.rutrackerCookie, 'bb_session=abc123');
      expect(again.musicRoot, r'D:\Flac music 2024');
    });

    test('a first run is not a failure', () async {
      final s = AppSettings();
      await s.load();
      expect(s.loadFailed, isFalse, reason: 'geen bestand is nieuw, niet stuk');
      expect(s.soulseekUser, isEmpty);
      // And saving works, because there is nothing to lose.
      s.soulseekUser = 'saber';
      await s.save();
      expect(AppSettings.file().existsSync(), isTrue);
    });

    test('the write leaves no temp file behind', () async {
      await seeded();
      final leftovers =
          scratch.listSync().whereType<File>().where((f) => f.path.endsWith('.tmp')).toList();
      expect(leftovers, isEmpty);
    });
  });

  group('a file that got cut in half', () {
    test('is recovered from the spare, and nothing is lost', () async {
      await seeded();
      // The spare is written on every successful load, so read once to make one.
      await AppSettings().load();
      expect(AppSettings.backupFile().existsSync(), isTrue);

      final whole = AppSettings.file().readAsStringSync();
      AppSettings.file().writeAsStringSync(whole.substring(0, whole.length ~/ 2));

      final after = AppSettings();
      await after.load();

      expect(after.soulseekPass, 'geheim', reason: 'dit bestaat nergens anders');
      expect(after.rutrackerPass, 'ookgeheim');
      expect(after.loadFailed, isFalse, reason: 'hersteld, dus bewaren mag weer');
    });

    test('with no spare, it refuses to write blanks over your passwords', () async {
      await seeded();
      final whole = AppSettings.file().readAsStringSync();
      AppSettings.file().writeAsStringSync(whole.substring(0, 20));
      // No backup exists: nothing ever loaded successfully on this machine.
      expect(AppSettings.backupFile().existsSync(), isFalse);

      final after = AppSettings();
      await after.load();
      expect(after.loadFailed, isTrue);
      expect(after.loadError, isNotEmpty);

      // This is the moment the loss used to become permanent — any save from anywhere.
      await after.save();

      expect(AppSettings.file().readAsStringSync(), whole.substring(0, 20),
          reason: 'het kapotte bestand is het enige spoor van de wachtwoorden — laat het staan');
    });

    test('and it says so, instead of looking like a fresh install', () async {
      AppSettings.file().writeAsStringSync('{niet eens json');
      final s = AppSettings();
      await s.load();
      expect(s.loadFailed, isTrue,
          reason: 'stil terugvallen op lege velden is precies hoe dit onopgemerkt bleef');
    });
  });

  group('a probe must not become the truth', () {
    test('a read-only copy never reaches the disk', () async {
      await seeded();

      // What the "Test verbindingen" button builds: a throwaway carrying only the two fields it is
      // checking. It has never seen the TIDAL tokens, the LAN token or the music folder.
      final probe = AppSettings()
        ..readOnly = true
        ..rutrackerUser = 'iemand anders';
      await probe.save();

      final real = AppSettings();
      await real.load();
      expect(real.rutrackerUser, 'saber');
      expect(real.musicRoot, r'D:\Flac music 2024', reason: 'de probe kende dit veld niet eens');
    });
  });

  group('what the file actually holds', () {
    test('every credential round-trips', () async {
      final s = await seeded();
      s
        ..discogsToken = 'dg'
        ..lastfmKey = 'lf'
        ..tidalAccessToken = 'ta'
        ..tidalRefreshToken = 'tr'
        ..tidalExpiry = 123
        ..soulseekPort = 2234
        ..lanToken = 'lan'
        ..serverId = 'srv';
      await s.save();

      final raw = jsonDecode(AppSettings.file().readAsStringSync()) as Map<String, dynamic>;
      final again = AppSettings();
      await again.load();

      for (final key in raw.keys) {
        expect(jsonDecode(jsonEncode(again.toJson()))[key], raw[key], reason: key);
      }
    });
  });
}

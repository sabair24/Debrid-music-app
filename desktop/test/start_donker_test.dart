/// Het startscherm van Android is zo donker als de app (18-10-2026: op de Shield een witte flits bij
/// elke start, in een donkere woonkamer).
library;

import 'dart:io';

import 'package:debridmusic/ui/kleuren.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const res = 'android/app/src/main/res';

  test('het startscherm en het venster hebben de kleur van de app, nergens wit', () {
    final kleuren = File('$res/values/colors.xml').readAsStringSync();
    final hex = kAchtergrond.toARGB32().toRadixString(16).toUpperCase().padLeft(8, '0');
    expect(kleuren, contains('<color name="dm_achtergrond">#$hex</color>'),
        reason: 'dezelfde kleur als kAchtergrond, anders flitst er bij het eerste beeld een rand');
    for (final f in ['drawable/launch_background.xml', 'drawable-v21/launch_background.xml']) {
      final xml = File('$res/$f').readAsStringSync();
      expect(xml, contains('@color/dm_achtergrond'), reason: f);
      expect(xml, isNot(contains('@android:color/white')), reason: f);
    }
    for (final f in ['values/styles.xml', 'values-night/styles.xml']) {
      expect(File('$res/$f').readAsStringSync(),
          contains('<item name="android:windowBackground">@color/dm_achtergrond</item>'), reason: f);
    }
  });

  test('de hoezen op het scherm gaan voor', () {
    final lib = File('lib/library.dart').readAsStringSync();
    expect(lib, contains('if (c == null && album != null) hoesVoorrang(album);'),
        reason: 'spelerbalk, verderbalk en wachtrij vragen hun hoes via coverForTrack');
    final hoofd = File('lib/main.dart').readAsStringSync();
    expect(hoofd, contains('if (a.cover == null) context.read<LibraryStore>().hoesVoorrang(a);'), reason: 'Albums');
    expect(hoofd, contains('if (albums[i].cover == null) context.read<LibraryStore>().hoesVoorrang(albums[i]);'),
        reason: 'de rijen op Start');
  });
}

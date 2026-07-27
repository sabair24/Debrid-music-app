// De reservekopie is er voor een settings.json die WEG is, niet alleen voor een kapotte.
//
// Een verdwenen settings.json nam de tak "a first run, not a loss" en stopte daar, terwijl er
// pal naast een settings.bak.json lag met elk token erin. De app startte blanco en vroeg om
// gegevens die hij al had. En dat was niet het einde: het inlogvenster in Instellingen dekt maar
// een deel van de velden — het LAN-token, het server-id, de muziekmap en de TIDAL-tokens staan er
// niet op — dus het "herstellen" schreef een bestand dat de rest definitief kwijt was.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_setrec_');
    setAppDirForTest(scratch.path);
  });

  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  File main_() => File('${scratch.path}${Platform.pathSeparator}settings.json');
  File spare() => File('${scratch.path}${Platform.pathSeparator}settings.bak.json');

  /// Een volledige set, zoals hij op schijf staat na normaal gebruik.
  String vol() => jsonEncode({
        'discogs_token': 'dg',
        'torbox_token': 'tb',
        'soulseek_user': 'iemand',
        'soulseek_pass': 'geheim',
        'lan_token': 'lan-abc',
        'music_root': r'D:\Flac music 2024',
        'tidal_refresh_token': 'tidal-xyz',
      });

  test('een verdwenen settings.json wordt uit de reservekopie hersteld', () async {
    await spare().writeAsString(vol());
    // main ontbreekt: weggegooid door een opruimtool, een sync-conflict, een teruggezet profiel.

    final s = AppSettings();
    await s.load();

    expect(s.soulseekUser, 'iemand', reason: 'dit stond in de reservekopie en was op te halen');
    expect(s.lanToken, 'lan-abc');
    expect(s.musicRoot, r'D:\Flac music 2024');
    expect(s.loadFailed, isFalse, reason: 'er is niets mislukt: het is hersteld');
  });

  test('en de primaire komt terug, zodat de volgende start niet op de kopie draait', () async {
    await spare().writeAsString(vol());
    await AppSettings().load();
    expect(await main_().exists(), isTrue);
    expect(jsonDecode(await main_().readAsString())['lan_token'], 'lan-abc');
  });

  test('velden die het inlogvenster niet kent blijven staan na Opslaan', () async {
    // Dit was de kern van de schade: het venster zet acht velden en save() schrijft ALLES. Zonder
    // herstel stonden lan_token, music_root en de TIDAL-tokens leeg in het geheugen en werden ze
    // dus als leeg weggeschreven.
    await spare().writeAsString(vol());
    final s = AppSettings();
    await s.load();

    s.discogsToken = 'nieuw-dg';
    s.forgetLoadFailure();
    await s.save();

    final op = jsonDecode(await main_().readAsString()) as Map<String, dynamic>;
    expect(op['discogs_token'], 'nieuw-dg');
    expect(op['lan_token'], 'lan-abc', reason: 'niet gewist door een Opslaan die dit veld niet kent');
    expect(op['music_root'], r'D:\Flac music 2024');
    expect(op['tidal_refresh_token'], 'tidal-xyz');
  });

  test('echt niets op schijf blijft een verse start', () async {
    final s = AppSettings();
    await s.load();
    expect(s.loadFailed, isFalse);
    expect(s.soulseekUser, isEmpty);
  });

  test('een kapotte primaire met een goede kopie herstelt nog steeds', () async {
    await main_().writeAsString('{"discogs_token": "dg"');
    await spare().writeAsString(vol());

    final s = AppSettings();
    await s.load();
    expect(s.loadFailed, isFalse);
    expect(s.soulseekUser, 'iemand');
  });

  test('kapot en geen kopie: niets overschrijven', () async {
    await main_().writeAsString('{kapot');
    final voor = await main_().readAsString();

    final s = AppSettings();
    await s.load();
    expect(s.loadFailed, isTrue, reason: 'de enige sporen van de wachtwoorden staan in dat bestand');

    await s.save();
    expect(await main_().readAsString(), voor, reason: 'de weigering houdt');
  });
}

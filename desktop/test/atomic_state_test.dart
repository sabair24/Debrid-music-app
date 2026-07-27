// De zes JSON-bestanden van LibraryStore mogen nooit half op schijf staan.
//
// `writeAsString` kapt het bestand eerst af en vult het daarna. Alles wat dat venster onderbreekt —
// een volle schijf, een antivirus of sync-tool die de handle vasthoudt, een proces dat verdwijnt —
// laat afgebroken JSON achter. Zes bestanden werden zo geschreven, waaronder corrections.json: elke
// handmatige aanpassing in deze bibliotheek. De fout werd volledig geslikt, dus het venster zei dat
// de correctie was opgeslagen terwijl er niets op schijf stond.
//
// En de tegenhanger: een corrections.json die er WEL is maar niet te lezen, mag niet rustig worden
// overschreven met de bijna-lege map uit het geheugen. Eén slechte leesactie was genoeg om alles
// kwijt te zijn bij de volgende bewerking. Let op: een LEEG bestand is normaal bij een verse
// installatie, dus leegte is niet het signaal — een mislukte parse is dat.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

void main() {
  late Directory scratch;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_atomic_');
    setAppDirForTest(scratch.path);
  });

  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  File f(String name) => File('${scratch.path}${Platform.pathSeparator}$name');

  test('hidden.json wordt via een tmp geschreven en blijft geldige JSON', () async {
    final lib = LibraryStore();
    await lib.removeTracks(['X:\\a\\01.flac'], fromDisk: false);
    final h = f('hidden.json');
    expect(await h.exists(), isTrue);
    expect(jsonDecode(await h.readAsString()), contains('X:\\a\\01.flac'));
    // Het tijdelijke bestand mag niet blijven rondslingeren.
    expect(await File('${h.path}.tmp').exists(), isFalse);
  });

  test('album_styles.json idem', () async {
    final lib = LibraryStore();
    await lib.rememberStyles('Adele', '21', ['Soul', 'Pop']);
    final s = f('album_styles.json');
    expect(await s.exists(), isTrue);
    expect(jsonDecode(await s.readAsString()), isA<Map<String, dynamic>>());
    expect(await File('${s.path}.tmp').exists(), isFalse);
  });

  test('album_art_roles.json idem', () async {
    final lib = LibraryStore();
    await lib.setAlbumArtRole('Adele', '21', 'back', 'http://x/back.jpg');
    final r = f('album_art_roles.json');
    expect(await r.exists(), isTrue);
    expect(await r.readAsString(), contains('back.jpg'));
    expect(await File('${r.path}.tmp').exists(), isFalse);
  });

  test('artist_art_choice.json idem', () async {
    final lib = LibraryStore();
    await lib.setArtistArt('Adele', 'photo', 'http://x/foto.jpg');
    final a = f('artist_art_choice.json');
    expect(await a.exists(), isTrue);
    expect(await a.readAsString(), contains('foto.jpg'));
    expect(await File('${a.path}.tmp').exists(), isFalse);
  });

  test('een onleesbare corrections.json wordt NIET overschreven', () async {
    // Precies het scenario dat maanden werk kostte: het bestand is er, maar kapot.
    final c = f('corrections.json');
    await c.writeAsString('{"X:\\\\a\\\\01.flac": {"artist": "Adele"');
    final voor = await c.readAsString();

    final lib = LibraryStore();
    await lib.loadCorrections();
    expect(lib.correctionsUnreadable, isTrue,
        reason: 'de app moet weten dat ze op een kapot bestand kijkt');

    // Een nieuwe correctie mag er niet overheen. Zonder deze weigering schreef de app hier een
    // map met één regel over alles wat er stond.
    lib.tracks.add(Track(
        path: 'X:\\a\\02.flac', title: 'twee', artist: 'Iemand', album: 'Ergens', trackNo: 2));
    lib.rebuildAlbums();
    await lib.applyCorrection(lib.albums.first, AppSettings(), artist: 'Andere');

    expect(await c.readAsString(), voor,
        reason: 'het kapotte bestand is intact gelaten in plaats van vervangen');
  });

  test('een leesbare corrections.json wordt gewoon bijgewerkt', () async {
    // De weigering mag niet doorslaan: leeg of geldig is geen reden om te stoppen.
    final c = f('corrections.json');
    await c.writeAsString('{}');

    final lib = LibraryStore();
    await lib.loadCorrections();
    expect(lib.correctionsUnreadable, isFalse, reason: 'een leeg bestand is een verse installatie');

    lib.tracks.add(Track(
        path: 'X:\\a\\03.flac', title: 'drie', artist: 'Iemand', album: 'Ergens', trackNo: 3));
    lib.rebuildAlbums();
    await lib.applyCorrection(lib.albums.first, AppSettings(), artist: 'Andere');

    expect(await c.readAsString(), contains('Andere'));
  });

  test('een ontbrekende corrections.json is geen storing', () async {
    final lib = LibraryStore();
    await lib.loadCorrections();
    expect(lib.correctionsUnreadable, isFalse);
  });

  test('de Discogs-nummering wordt uit de sleutel gehouden bij het verhuizen', () async {
    // "Adele (3)" is hoe Discogs een artiest met een naamgenoot teruggeeft. De correctie slaat
    // "Adele" op; de verhuizing van styles, scans en hoes gebruikte de RUWE naam en zette alles
    // onder een sleutel die geen enkel deel van de app opvraagt.
    final lib = LibraryStore();
    lib.tracks.add(
        Track(path: 'X:\\a\\04.flac', title: 'vier', artist: 'Adele', album: '21', trackNo: 1));
    lib.rebuildAlbums();
    await lib.rememberStyles('Adele', '21', ['Soul']);
    await lib.setAlbumArtRole('Adele', '21', 'disc', 'http://x/disc.jpg');

    await lib.applyCorrection(lib.albums.first, AppSettings(), artist: 'Adele (3)');

    // Na de correctie heet de artiest "Adele", en daar moeten de gegevens ook staan.
    expect(lib.albumArtRoles('Adele', '21')['disc'], 'http://x/disc.jpg',
        reason: 'de scan is meeverhuisd naar de sleutel die de app echt gebruikt');
    expect(lib.albumArtRoles('Adele (3)', '21'), isEmpty,
        reason: 'niets mag achterblijven onder de ongeschoonde naam');
  });

  test('een gewone artiestnaam verhuist net zo goed', () async {
    final lib = LibraryStore();
    lib.tracks.add(
        Track(path: 'X:\\a\\05.flac', title: 'vijf', artist: 'Oude', album: 'Plaat', trackNo: 1));
    lib.rebuildAlbums();
    await lib.setAlbumArtRole('Oude', 'Plaat', 'back', 'http://x/b.jpg');

    await lib.applyCorrection(lib.albums.first, AppSettings(), artist: 'Nieuwe');

    expect(lib.albumArtRoles('Nieuwe', 'Plaat')['back'], 'http://x/b.jpg');
  });
}

/// Eén hoes opvragen mag de hele catalogus niet opnieuw laten bouwen.
///
/// **Waarom dit bestaat.** Een gekoppelde telefoon haalt zijn hoezen bij de pc op, één verzoek per
/// hoes. Dat verzoek liep via `snapshot()`, en die bouwt bij de kleinste wijziging in de bibliotheek
/// de HELE catalogus opnieuw: een `AlbumDto` per plaat — inclusief `pinnedRelease`, `stylesOf`,
/// `albumArtRoles` en een hash over de hoesbytes — plus een `TrackDto` per nummer.
///
/// De vuilvlag gaat aan bij ELKE melding van de bibliotheek: een hoes die binnenkomt, een download
/// die landt, een verrijking die klaar is. Een telefoon die zijn nu-speelt-scherm opent vraagt
/// meerdere hoezen kort na elkaar, precies terwijl de pc bezig is — en dan betaalde elke hoes een
/// volledige herbouw. Gemeld op 27-08-2026: *"de covers laden heel traag in, en daarom ook het
/// skippen naar volgende nummer"*.
///
/// De reparatie is een eigen, kleine index met dezelfde id-berekening. Deze toets bewaakt allebei de
/// kanten: dat hij dezelfde antwoorden geeft, en dat hij de momentopname met rust laat.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/lan/catalog.dart';
import 'package:debridmusic/lan/ids.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/organize.dart';
import 'package:debridmusic/paths.dart';
import 'package:flutter_test/flutter_test.dart';

Track _t(String path, String title, String artist, String album, {int no = 1}) => Track(
      path: path,
      title: title,
      artist: artist,
      album: album,
      trackNo: no,
      trackTotal: 2,
      duration: const Duration(seconds: 240),
      isFlac: true,
      sizeBytes: 4096,
      sampleRate: 44100,
      bitsPerSample: 16,
      year: 1994,
    );

/// Het id waarmee een hoesverzoek binnenkomt — dezelfde berekening als in `_build`.
String refVoor(Album a) => albumIdFor(artistKey(a.artist), normKey(a.title), a.edition);

void main() {
  late Directory scratch;
  late LibraryStore pc;
  late LanCatalog catalog;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_hoes_');
    setAppDirForTest(scratch.path);
    pc = LibraryStore()
      ..rootPath = scratch.path
      ..configDirOverride = scratch.path;
    pc.tracks.addAll([
      _t('${scratch.path}/a1.flac', 'Circle of Life', 'Elton John', 'The Lion King'),
      _t('${scratch.path}/a2.flac', 'Hakuna Matata', 'Elton John', 'The Lion King', no: 2),
      _t('${scratch.path}/b1.flac', 'Larger Than Life', 'Backstreet Boys', 'Millennium'),
    ]);
    pc.rebuildAlbums();
    catalog = LanCatalog(pc);
  });

  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } on FileSystemException {/* een achtergebleven map is geen gezakte toets waard */}
  });

  group('DE KERN: dezelfde antwoorden als vóór de reparatie', () {
    test('een plaat-id levert de hoes van die plaat', () {
      final plaat = pc.albums.firstWhere((a) => a.title == 'The Lion King');
      plaat.embeddedCover = Uint8List.fromList([1, 2, 3, 4]);
      expect(catalog.artwork(refVoor(plaat)), [1, 2, 3, 4]);
    });

    test('twee platen halen elkaar niet door elkaar', () {
      final leeuw = pc.albums.firstWhere((a) => a.title == 'The Lion King')
        ..embeddedCover = Uint8List.fromList([1]);
      final bsb = pc.albums.firstWhere((a) => a.title == 'Millennium')
        ..embeddedCover = Uint8List.fromList([2]);
      expect(catalog.artwork(refVoor(leeuw)), [1]);
      expect(catalog.artwork(refVoor(bsb)), [2]);
    });

    test('DE KERN: een hoes die NA het bouwen van de index binnenkomt telt gewoon mee', () {
      // De index bewaart de PLAAT en niet de bytes. Dat is met opzet: de verrijker vult hoezen aan
      // terwijl de app draait, en een index die de bytes had gekopieerd zou een telefoon eeuwig het
      // lege vakje blijven sturen voor een plaat waarvan de hoes intussen wél binnen is.
      final plaat = pc.albums.firstWhere((a) => a.title == 'Millennium');
      expect(catalog.artwork(refVoor(plaat)), isNull);
      plaat.enriched = Uint8List.fromList([5, 5]);
      expect(catalog.artwork(refVoor(plaat)), [5, 5]);
    });

    test('een artiest-id levert het portret', () {
      pc.artistImages['Elton John'] = Uint8List.fromList([9, 9]);
      expect(catalog.artwork('artist-${artistIdFor(artistKey('Elton John'))}'), [9, 9]);
    });

    test('een onbekend id geeft null, geen uitzondering', () {
      // De server maakt daar een 404 van en het toestel toont zijn eigen vakje. Een uitzondering
      // zou een lege 500 worden, en dat leest als "de pc is stuk".
      expect(catalog.artwork('bestaat-niet'), isNull);
      expect(catalog.artwork('artist-bestaat-niet'), isNull);
      expect(catalog.artwork(''), isNull);
    });
  });

  group('DE KERN: de momentopname wordt met rust gelaten', () {
    test('een hoesverzoek bouwt de catalogus niet', () {
      // Zo is dat van buiten te zien. Een verse [LanCatalog] heeft nog geen momentopname. Bouwt
      // `artwork` er een, dan staat de vuilvlag daarna uit en is die momentopname bewaard — en dan
      // ziet een verandering die dáárna zonder melding gebeurt er niet meer in.
      final plaat = pc.albums.firstWhere((a) => a.title == 'Millennium');
      expect(catalog.artwork(refVoor(plaat)), isNull);

      // Zonder melding een plaat weghalen.
      pc.albums.removeWhere((a) => a.title == 'The Lion King');

      final titels = catalog.snapshot().catalog.albums.map((a) => a.title).toList();
      expect(titels, isNot(contains('The Lion King')),
          reason: 'artwork() had de momentopname al gebouwd, en dat hoort niet');
      expect(titels, contains('Millennium'));
    });

    test('en andersom: een gebouwde momentopname breekt de hoesindex niet', () {
      final plaat = pc.albums.firstWhere((a) => a.title == 'The Lion King')
        ..embeddedCover = Uint8List.fromList([3]);
      catalog.snapshot();
      expect(catalog.artwork(refVoor(plaat)), [3]);
    });
  });
}

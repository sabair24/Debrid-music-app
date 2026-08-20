/// De bibliotheek op het toestel zelf, voor als er geen pc en geen internet is.
///
/// **Waarom dit bestaat.** Er was al een kopie in de cloud, en die dekt "de pc staat uit". Hij dekt
/// niet het geval waarvoor offline bewaren gemaakt is: de auto, de metro, het vliegtuig — pc uit
/// én geen bereik. De muziek stond dan op het toestel, de LIJST niet, en zonder lijst is er geen
/// album om op te tikken. Gemeld op 20-08-2026, met een plaat die aantoonbaar opgehaald was: *"ik
/// vind ze echt nergens"*.
///
/// Getoetst wordt de belofte, niet de vorm: wat er na een herstart zonder netwerk op het scherm
/// staat is DEZELFDE bibliotheek die de pc serveert — met dezelfde albums, dezelfde persingen en
/// dezelfde nummervolgorde. Een vereenvoudigde kopie zou er netter uitzien en fout zijn.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/catalogus_kopie.dart';
import 'package:debridmusic/lan/catalog.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';

Track _t(String path, String title, String artist, String album, {int no = 1, int total = 0}) =>
    Track(
      path: path,
      title: title,
      artist: artist,
      album: album,
      trackNo: no,
      trackTotal: total,
      duration: const Duration(seconds: 240),
      isFlac: true,
      sizeBytes: 4096,
      sampleRate: 44100,
      bitsPerSample: 16,
      year: 1994,
    );

void main() {
  late Directory scratch;
  late LibraryStore pc;
  late LanCatalog catalog;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_kopie_');
    setAppDirForTest(scratch.path);
    pc = LibraryStore()
      ..rootPath = scratch.path
      ..configDirOverride = scratch.path;
    pc.tracks.addAll([
      _t('${scratch.path}/a1.flac', 'Circle of Life', 'Elton John', 'The Lion King',
          no: 1, total: 2),
      _t('${scratch.path}/a2.flac', 'Hakuna Matata', 'Elton John', 'The Lion King',
          no: 2, total: 2),
      // Twee persingen van één plaat: precies wat een vereenvoudigde kopie zou platslaan.
      _t('${scratch.path}/b1.flac', 'Larger Than Life', 'Backstreet Boys', 'Millennium',
          no: 1, total: 12),
      _t('${scratch.path}/c1.flac', 'Larger Than Life', 'Backstreet Boys', 'Millennium',
          no: 1, total: 16),
    ]);
    pc.rebuildAlbums();
    catalog = LanCatalog(pc);
  });

  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } on FileSystemException {/* een achtergebleven map is geen gezakte toets waard */}
  });

  /// Een telefoon: gekoppeld aan een pc, verder leeg.
  LibraryStore telefoon() => LibraryStore()
    ..remote = RemoteClient(
        RemoteEndpoint(baseUrl: Uri.parse('http://192.168.0.117:47820'), token: 't'));

  /// Wat iemand van een album ziet, in een vorm waarop twee bibliotheken te vergelijken zijn.
  List<String> vorm(LibraryStore s) => [
        for (final a in s.albums)
          '${a.title} · ${a.artist} · ${a.edition ?? '-'} · '
              '${a.tracks.map((t) => '${t.trackNo} ${t.title}').join('|')}'
      ];

  const kopie = CatalogusKopie();

  /// Wat de pc over de lijn stuurt, als kaart. `snapshot().json` zijn de bytes die de server
  /// verstuurt; dit is precies wat een client ervan maakt voordat hij hem inleest.
  Map<String, dynamic> vanDePc() =>
      jsonDecode(utf8.decode(catalog.snapshot().json)) as Map<String, dynamic>;

  group('de lijst blijft op het toestel', () {
    test('dezelfde albums, persingen en volgorde als op de pc', () async {
      await kopie.bewaar(vanDePc());

      // Een nieuwe start, zonder netwerk: niets dan wat er op de schijf van het toestel ligt.
      final terug = await kopie.lees();
      expect(terug, isNotNull);

      final gsm = telefoon();
      expect(gsm.adoptMirror(terug!.json, updatedAt: terug.bijgewerkt, vanToestel: true), isTrue);

      expect(vorm(gsm), vorm(pc));
      expect(gsm.tracks.length, pc.tracks.length);
      expect(gsm.albums.where((a) => a.title == 'Millennium').length, 2,
          reason: 'twee persingen horen twee platen te blijven');
    });

    test('en het scherm weet dat dit de kopie van het toestel is', () async {
      await kopie.bewaar(vanDePc());
      final gsm = telefoon();
      final terug = await kopie.lees();
      gsm.adoptMirror(terug!.json, vanToestel: true);

      // Waarom allebei: `fromCloudMirror` is wat de balk bovenaan aanzet ("je pc reageert niet"),
      // en `kopieVanToestel` is het verschil tussen "dit kwam over internet" en "dit lag hier al".
      expect(gsm.fromCloudMirror, isTrue);
      expect(gsm.kopieVanToestel, isTrue);
    });

    test('zonder kopie is er niets, en dat is geen fout', () async {
      expect(await kopie.lees(), isNull);
    });
  });

  group('wat er niet mag gebeuren', () {
    test('een half weggeschreven bestand overschrijft het goede niet', () async {
      await kopie.bewaar(vanDePc());

      // Wat een app die middenin het schrijven wordt weggehaald achterlaat — en Android doet dat
      // ongevraagd. Omdat er ernaast geschreven wordt en pas daarna hernoemd, is dit rommel die
      // niemand ooit leest in plaats van een lijst die er goed uitziet en afgekapt is.
      File('${scratch.path}/catalogus.json.tmp').writeAsStringSync('{"albums":[{"ti');

      final terug = await kopie.lees();
      expect(terug, isNotNull);
      final gsm = telefoon();
      expect(gsm.adoptMirror(terug!.json, vanToestel: true), isTrue);
      expect(vorm(gsm), vorm(pc));
    });

    test('een onleesbare kopie is een lege kopie, geen kapotte app', () async {
      File('${scratch.path}/catalogus.json').writeAsStringSync('dit is geen json');
      expect(await kopie.lees(), isNull);
    });

    test('ontkoppelen laat de inhoudsopgave van die pc niet achter', () async {
      await kopie.bewaar(vanDePc());
      await kopie.wis();

      expect(await kopie.lees(), isNull);
      expect(File('${scratch.path}/catalogus.json').existsSync(), isFalse);
    });
  });
}

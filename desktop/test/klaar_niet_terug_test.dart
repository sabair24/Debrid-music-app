/// "Klaar om te kiezen" vraagt niet steeds hetzelfde (Saber, 05-11-2026: "bij klaar om te kiezen komen vaak dezelfde
/// liedjes steeds terug ?? … ik heb al heel veel moeten kiezen voor adele en andere").
///
/// Gemeten op de pc die dag:
/// - Gala (drie nummers) en Kings Of Leon kwamen als twijfel van dezelfde uploader en uit dezelfde map als hun
///   vinylversie van 31-10; Bewaren gaf daarna "bit voor bit dezelfde als je versie". De volgende jachtronde: weer.
/// - Een weggegooide kopie werd onthouden op zijn grootte en het pad van het nummer: dezelfde opname bij een andere
///   uploader (andere tags) kwam terug, en ook alles na een verhuizing.
/// - Adele — To Be Loved stond in "30 (cd) (cd)" met een versie in "30 (cd) (cd) (cd)": de cd-versie werd op artiest en
///   titel gevonden als "het nummer", en zijn versie kreeg er nog een " (cd)" bij.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/kopiesoort.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/organize.dart' show TrackTags;
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:debridmusic/twijfel.dart';
import 'package:debridmusic/versie_opbergen.dart' show versieAlbumnaam;
import 'package:debridmusic/versies.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een FLAC met alleen een kop (STREAMINFO): genoeg voor "dezelfde samples?" ([zelfdeSamples] kijkt naar de kop).
File _flac(String pad, {required int som, int extra = 0, int totaal = 441000}) {
  const sr = 44100, ch = 2, bps = 16;
  final s = Uint8List(34);
  s[0] = 0x10;
  s[2] = 0x10;
  s[10] = (sr >> 12) & 0xff;
  s[11] = (sr >> 4) & 0xff;
  s[12] = ((sr & 0x0f) << 4) | (((ch - 1) & 0x07) << 1) | (((bps - 1) >> 4) & 0x01);
  s[13] = ((bps - 1) & 0x0f) << 4;
  ByteData.sublistView(s).setUint32(14, totaal);
  for (var i = 18; i < 34; i++) {
    s[i] = som;
  }
  final b = BytesBuilder()
    ..add('fLaC'.codeUnits)
    ..add([0x80, 0, 0, 34])
    ..add(s)
    ..add(List.filled(extra, 7));
  return File(pad)
    ..createSync(recursive: true)
    ..writeAsBytesSync(b.toBytes());
}

void main() {
  group('mappen en albumnamen van versies krijgen nooit twee achtervoegsels', () {
    test('versieMap', () {
      expect(versieMap('D:/M/Adele/30', Kopiesoort.cd), 'D:/M/Adele/30 (cd)');
      expect(versieMap('D:/M/Adele/30 (cd)', Kopiesoort.cd), 'D:/M/Adele/30 (cd)');
      expect(versieMap('D:/M/Adele/30 (cd) (cd)', Kopiesoort.studio), 'D:/M/Adele/30 (studio)');
      expect(zonderSoortAchtervoegsel('Discovery (vinyl) (cd)'), 'Discovery');
      expect(zonderSoortAchtervoegsel('Come Into My Life (The Album)'), 'Come Into My Life (The Album)',
          reason: 'alleen studio, cd en vinyl');
    });
    test('de albumnaam', () {
      expect(versieAlbumnaam('30', Kopiesoort.cd), '30 (cd)');
      expect(versieAlbumnaam('30 (cd)', Kopiesoort.studio), '30 (studio)');
      expect(versieAlbumnaam('Spice (vinyl)', Kopiesoort.vinyl), 'Spice (vinyl)');
    });
  });

  group('weggooien onthoudt het geluid, per nummer', () {
    late Directory map;
    setUp(() => map = Directory.systemTemp.createTempSync('dm_klaar_'));
    tearDown(() => map.deleteSync(recursive: true));

    test('dezelfde opname met een andere grootte en op een ander pad blijft weg, ook na een herstart', () async {
      final l = Twijfellijst('${map.path}/twijfel.json');
      l.zet(const Twijfelgeval(
          id: 'a',
          pad: 'D:/M/Adele/30/11 - To Be Loved.flac',
          kandidaat: 'D:/M/_twijfel/a.flac',
          bron: 'Soulseek Ichraew',
          score: .89,
          kwaliteit: 'FLAC 24/192',
          ms: 1,
          grootte: 100,
          gezag: {'artist': 'Adele', 'title': 'To Be Loved'},
          md5: 'abc'));
      l.verwijder('D:/M/Adele/30/11 - To Be Loved.flac', nee: true);
      expect(l.afgewezenGeluid('Adele', 'To Be Loved', 'abc'), isTrue);
      expect(l.afgewezenGeluid('ADELE', 'To Be Loved!', 'abc'), isTrue, reason: 'los van hoofdletters en leestekens');
      expect(l.afgewezenGeluid('Adele', 'To Be Loved', 'def'), isFalse, reason: 'een andere opname mag');
      await l.bewaar();
      final weer = Twijfellijst('${map.path}/twijfel.json');
      await weer.laad();
      expect(weer.afgewezenGeluid('Adele', 'To Be Loved', 'abc'), isTrue);
    });
  });

  group('de jacht', () {
    late Directory map;
    late DownloadManager d;
    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_klaar_jacht_');
      d = DownloadManager(OnlineService(AppSettings()), SoulseekService(AppSettings()), map.path, () async {})
        ..twijfel = Twijfellijst('${map.path}/twijfel.json');
      DownloadManager.prullenbak = (paden) async {
        for (final p in paden) {
          File(p).deleteSync();
        }
        return paden.toSet();
      };
    });
    tearDown(() {
      versies.wis();
      DownloadManager.prullenbak = (_) async => {};
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('DE KERN: wat sample voor sample een versie van je is, wordt geen twijfel', () async {
      final eigen = _flac('${map.path}/Albums/Gala/Come Into My Life (The Album)/10 - Freed From Desire.flac', som: 1);
      final vinyl =
          _flac('${map.path}/Albums/Gala/Come Into My Life (The Album) (vinyl)/10 - Freed From Desire.flac', som: 2);
      versies.voegToe(eigen.path,
          Versie(pad: vinyl.path, soort: Kopiesoort.vinyl, persing: 'LP 1997', bron: r'music\Gala\0110 Freed From Desire.flac'),
          ankerSoort: Kopiesoort.cd);
      // Dezelfde samples als de vinyl, met andere tags (dus een andere grootte).
      final binnen = _flac('${map.path}/_keuring/a/Freed From Desire.flac', som: 2, extra: 500);
      expect(await d.bewaarAlsTwijfel(binnen, eigen.path, .84, 'Soulseek koii', null), isTrue);
      expect(d.twijfel!.van(eigen.path), isNull, reason: 'niet gevraagd: je hebt hem al');
      expect(binnen.existsSync(), isFalse, reason: 'weg uit de keuringsmap');

      final ander = _flac('${map.path}/_keuring/b/Freed From Desire.flac', som: 3);
      expect(await d.bewaarAlsTwijfel(ander, eigen.path, .84, 'Soulseek x', null), isTrue);
      expect(d.twijfel!.van(eigen.path), isNotNull, reason: 'een andere opname wel');
      expect(d.twijfel!.van(eigen.path)!.md5, '03' * 16);
    });

    test('wat je weggooide, komt niet terug als dezelfde opname bij een andere uploader', () async {
      final eigen = _flac('${map.path}/Albums/Adele/30/11 - To Be Loved.flac', som: 1);
      const gezag = TrackTags(title: 'To Be Loved', artist: 'Adele', album: '30', albumArtist: 'Adele', trackNo: 11);
      final eerste = _flac('${map.path}/_keuring/a/To Be Loved.flac', som: 9);
      await d.bewaarAlsTwijfel(eerste, eigen.path, .89, 'Soulseek Ichraew', gezag);
      expect(d.twijfel!.van(eigen.path), isNotNull);
      await d.gooiTwijfelWeg(eigen.path);
      final weer = _flac('${map.path}/_keuring/b/To Be Loved.flac', som: 9, extra: 1234);
      expect(await d.bewaarAlsTwijfel(weer, eigen.path, .89, 'Soulseek yukioh', gezag), isTrue);
      expect(d.twijfel!.van(eigen.path), isNull, reason: 'zelfde samples, andere grootte: toch weg');
    });

    test('hetzelfde bestand bij de uploader als je versie, of een weggegooide grootte: niet nog eens binnenhalen', () {
      const anker = 'D:/M/Albums/Gala/Come Into My Life (The Album)/03 - Suddenly.flac';
      versies.voegToe(
          anker,
          const Versie(
              pad: 'D:/M/Albums/Gala/Come Into My Life (The Album) (vinyl)/03 - Suddenly.flac',
              soort: Kopiesoort.vinyl,
              persing: 'LP 1997',
              bron: r'music\Gala\Come Into My Life (1997)\0103 Suddenly.flac'),
          ankerSoort: Kopiesoort.cd);
      SoulseekFile f(String pad, int grootte) => SoulseekFile(username: 'koii', filename: pad, size: grootte);
      expect(d.alGekend(f(r'music\Gala\Come Into My Life (1997)\0103 Suddenly.flac', 84846062), anker),
          'je versie vinyl LP 1997');
      expect(d.alGekend(f('MUSIC/gala/Come Into My Life (1997)/0103 Suddenly.flac', 1), anker), isNotNull,
          reason: 'los van hoofdletters en de richting van de streep');
      expect(d.alGekend(f(r'other\Suddenly.flac', 1), anker), isNull);
      expect(d.alGekend(f(r'other\Suddenly.flac', 1), null), isNull, reason: 'zonder nummer valt niets te zeggen');
    });
  });

  test('aangesloten: altijd het nummer (nooit een versie), en de jacht slaat bekend over vóór het binnenhalen', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(main, contains('      return p == null ? null : (versies.ankerVan(p) ?? p);\n'));
    final online = File('lib/online.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final jacht = online.substring(online.indexOf('  Future<void> _chaseUpgrade('));
    final over = jacht.indexOf('if (alGekend(f, anker) case final wat?) {');
    final halen = jacht.indexOf('res = await _rawTransfer(session, f, shadow');
    expect(over, greaterThan(0));
    expect(halen, greaterThan(over), reason: 'eerst kijken, dan pas binnenhalen');
  });
}

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

    test('wat er al wachtte en je al hebt, ruimt de pc zelf op; een andere opname en wat je zelf vroeg, blijven', () async {
      final sep = Platform.pathSeparator;
      final eigen = _flac('${map.path}/Albums/Gala/C/03 - Suddenly.flac', som: 1);
      final vinyl = _flac('${map.path}/Albums/Gala/C (vinyl)/03 - Suddenly.flac', som: 2);
      versies.voegToe(eigen.path, Versie(pad: vinyl.path, soort: Kopiesoort.vinyl), ankerSoort: Kopiesoort.cd);
      final dubbel = _flac('${map.path}$sep$twijfelMap${sep}d1.flac', som: 2, extra: 99);
      final eigen2 = _flac('${map.path}/Albums/Gala/C/10 - Freed From Desire.flac', som: 4);
      final ander = _flac('${map.path}$sep$twijfelMap${sep}d2.flac', som: 5);
      final eigen3 = _flac('${map.path}/Albums/Gala/C/08 - Come Into My Life.flac', som: 6);
      final gevraagd = _flac('${map.path}$sep$twijfelMap${sep}d3.flac', som: 6);
      Twijfelgeval g(String id, File eigen, File k, {Kopiesoort? soort}) => Twijfelgeval(
          id: id, pad: eigen.path, kandidaat: k.path, bron: 'Soulseek koii', score: .87, kwaliteit: 'FLAC 24/96',
          ms: 1, grootte: k.lengthSync(), soort: soort);
      d.twijfel!
        ..zet(g('d1', eigen, dubbel))
        ..zet(g('d2', eigen2, ander))
        ..zet(g('d3', eigen3, gevraagd, soort: Kopiesoort.studio));
      expect(await d.ruimBekendeTwijfelsOp(), 1);
      expect(d.twijfel!.van(eigen.path), isNull, reason: 'zijn eigen vinylversie');
      expect(dubbel.existsSync(), isFalse);
      expect(d.twijfel!.van(eigen2.path), isNotNull, reason: 'een andere opname blijft wachten');
      expect(d.twijfel!.van(eigen3.path), isNotNull, reason: 'wat je zelf vroeg, beslis jij');
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

    // Saber, 12-11-2026: "Deze blijven maar terugkomen om te kiezen??? Is heel ambetant" — drie van de vijf waren bit voor
    // bit een kopie uit _dubbel (Shiny Happy People er zelfs twee keer), die de blijvende jacht weer binnenhaalde.
    test('DE KERN (12-11): wat al eens bij je stond en verloor (_dubbel), wordt geen twijfel — ook niet na het legen', () async {
      final sep = Platform.pathSeparator;
      final eigen = _flac('${map.path}/Albums/R.E.M/Out Of Time/06 - Shiny Happy People.flac', som: 1);
      final studio = _flac('${map.path}/Albums/R.E.M/Out Of Time (studio)/06 - Shiny Happy People.flac', som: 2);
      versies.voegToe(eigen.path, Versie(pad: studio.path, soort: Kopiesoort.studio), ankerSoort: Kopiesoort.cd);
      final dubbel =
          _flac('${map.path}${sep}DebridMusic Downloads${sep}_dubbel$sep(2) 06 - Shiny Happy People.flac', som: 9, extra: 3);
      const gezag = TrackTags(
          title: 'Shiny Happy People', artist: 'R.E.M.', album: 'Out Of Time', albumArtist: 'R.E.M.', trackNo: 6);
      final binnen = _flac('${map.path}/_keuring/a/06 - Shiny Happy People.flac', som: 9);
      expect(await d.bewaarAlsTwijfel(binnen, eigen.path, .88, 'Soulseek hubberb', gezag), isTrue);
      expect(d.twijfel!.van(eigen.path), isNull, reason: 'stond al eens bij je en verloor: niet vragen');
      expect(binnen.existsSync(), isFalse, reason: 'weg uit de keuringsmap');
      expect(dubbel.existsSync(), isTrue, reason: '_dubbel zelf blijft onaangeroerd');
      expect(d.twijfel!.afgewezenGeluid('R.E.M.', 'Shiny Happy People', '09' * 16), isTrue, reason: 'onthouden op het geluid');

      // _dubbel na 30 dagen geleegd: dezelfde rip bij nog een uploader blijft toch weg.
      dubbel.deleteSync();
      final weer = _flac('${map.path}/_keuring/b/06 - Shiny Happy People.flac', som: 9, extra: 77);
      expect(await d.bewaarAlsTwijfel(weer, eigen.path, .88, 'Soulseek willhub', gezag), isTrue);
      expect(d.twijfel!.van(eigen.path), isNull);

      final ander = _flac('${map.path}/_keuring/c/06 - Shiny Happy People.flac', som: 5);
      expect(await d.bewaarAlsTwijfel(ander, eigen.path, .88, 'Soulseek x', gezag), isTrue);
      expect(d.twijfel!.van(eigen.path), isNotNull, reason: 'een andere opname mag je wel kiezen');
    });

    test('_alEensVerloren: ook onder de naam van de uploader (binnengekomen), maar nooit met andere samples of lengte',
        () async {
      final sep = Platform.pathSeparator;
      final dub = '${map.path}${sep}DebridMusic Downloads${sep}_dubbel';
      final eigen = _flac('${map.path}/Albums/Daft Punk/RAM/08 - Get Lucky.flac', som: 1);
      _flac('$dub${sep}binnengekomen${sep}Daft Punk - Get Lucky (feat. Pharrell Williams).flac', som: 7, extra: 48);
      _flac('$dub${sep}08 - Get Lucky.flac', som: 8, totaal: 441001);
      final zelfde = _flac('${map.path}/_keuring/a/Get Lucky.flac', som: 7);
      expect(await d.alEensVerlorenVoorToets(zelfde.path, eigen.path), contains('_dubbel'),
          reason: 'zoals de uploader hem noemde, zelfde samples');
      final langer = _flac('${map.path}/_keuring/b/Get Lucky.flac', som: 8);
      expect(await d.alEensVerlorenVoorToets(langer.path, eigen.path), isNull,
          reason: 'zelfde naam, maar één sample verschil in lengte: een andere kopie');
      final nieuw = _flac('${map.path}/_keuring/c/Get Lucky.flac', som: 3);
      expect(await d.alEensVerlorenVoorToets(nieuw.path, eigen.path), isNull);
    });

    test('wat er al wachtte en al eens verloor, ruimt de pc bij het opstarten op — en onthoudt het als weggegooid', () async {
      final sep = Platform.pathSeparator;
      final eigen = _flac('${map.path}/Albums/Marvin Gaye/Favorites/07 - Ain\'t No Mountain High Enough.flac', som: 1);
      _flac("${map.path}${sep}DebridMusic Downloads${sep}_dubbel$sep(2) 07 - Ain't No Mountain High Enough.flac", som: 6);
      final wacht = _flac('${map.path}$sep$twijfelMap${sep}m1.flac', som: 6, extra: 340);
      d.twijfel!.zet(Twijfelgeval(
          id: 'm1',
          pad: eigen.path,
          kandidaat: wacht.path,
          bron: 'Soulseek Duane.M',
          score: .88,
          kwaliteit: 'FLAC 24/192',
          ms: 1,
          grootte: wacht.lengthSync(),
          gezag: const {'artist': 'Marvin Gaye & Tammi Terrell', 'title': "Ain't No Mountain High Enough"},
          md5: '06' * 16));
      expect(await d.ruimBekendeTwijfelsOp(), 1);
      expect(d.twijfel!.van(eigen.path), isNull);
      expect(wacht.existsSync(), isFalse);
      expect(d.twijfel!.afgewezenGeluid('Marvin Gaye & Tammi Terrell', "Ain't No Mountain High Enough", '06' * 16), isTrue);
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
    expect(main, contains('      downloads.twijfel = twijfels;\n'
        '      // Wat er wacht en je al hebt (je eigen versie, sample voor sample), hoef je niet te kiezen (05-11-2026).\n'
        '      unawaited(downloads.ruimBekendeTwijfelsOp());\n'),
        reason: 'bij het opstarten: wat er nog van vroeger wachtte');
    final online = File('lib/online.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final jacht = online.substring(online.indexOf('  Future<void> _chaseUpgrade('));
    final over = jacht.indexOf('if (alGekend(f, anker) case final wat?) {');
    final halen = jacht.indexOf('res = await _rawTransfer(session, f, shadow');
    expect(over, greaterThan(0));
    expect(halen, greaterThan(over), reason: 'eerst kijken, dan pas binnenhalen');
  });
}

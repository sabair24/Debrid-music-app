// Twijfelgevallen, aangesloten (Saber, 25-10-2026): de keuring bewaart een twijfelkopie in plaats van haar weg te gooien,
// de albumpagina toont het label met beluisteren/vervangen/weggooien, en een toestel doet hetzelfde via de pc.
import 'dart:io';

import 'package:debridmusic/lan/dtos.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/twijfel.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  test('de keuring: bij twijfel en bewezen beter bewaren, niet weggooien — bij Soulseek, TIDAL, torrents en wensen', () {
    final online = _bron('lib/online.dart');
    // _keurVoorWens: wensen, TIDAL-beter en torrents.
    expect(online, contains('        opname == Opnameoordeel.twijfel &&\n        !nietBeter &&\n'
        '        await bewaarAlsTwijfel(staged, bestaand, score!, bron, w.authority)) {'));
    // De Soulseek-jacht op beter.
    expect(online, contains('                opname == Opnameoordeel.twijfel &&\n'
        '                firstIsBetter(staged, File(bestaand)) &&\n'
        "                await bewaarAlsTwijfel(staged, bestaand, score!, 'Soulseek \${f.username}', job.authority)) {"));
    // Een gewone vervanging maakt een twijfelkopie achterhaald.
    expect(online, contains('      if (bestaand != null) await _vergeetTwijfel(bestaand);'));
    expect(online, contains('            if (how == Placement.moved && bestaand != null) await _vergeetTwijfel(bestaand);'));
  });

  test('de bibliotheek slaat de twijfelmap over', () {
    expect(_bron('lib/library.dart'),
        contains("    if (e.path.contains('\${Platform.pathSeparator}\$twijfelMap\${Platform.pathSeparator}')) continue;"));
  });

  test('naar een toestel: per nummer mee met de catalogus, en telt mee in de vingerafdruk', () {
    const met = TrackDto(
        id: 't', albumId: 'a', artistId: 'b', title: 'Nightvision', artistName: 'Daft Punk', albumTitle: 'Discovery',
        streamPath: '/stream/t.flac', ext: 'flac',
        twijfel: {'id': 'x1', 'bron': 'Soulseek a', 'score': 0.858, 'kwaliteit': 'FLAC 24/96', 'ext': 'flac'});
    expect(TrackDto.fromJson(met.toJson()).twijfel?['kwaliteit'], 'FLAC 24/96');
    const zonder = TrackDto(
        id: 't', albumId: 'a', artistId: 'b', title: 'Nightvision', artistName: 'Daft Punk', albumTitle: 'Discovery',
        streamPath: '/stream/t.flac', ext: 'flac');
    expect(zonder.toJson().containsKey('twijfel'), isFalse, reason: 'null voor bijna alles: de catalogus blijft klein');
    final catalog = _bron('lib/lan/catalog.dart');
    expect(catalog, contains("      if (t.twijfel != null) fingerprint.add('T\${t.twijfel!['id']}');"));
    expect(catalog, contains('    twijfelUitgave.addListener(_markDirty);'));
    expect(_bron('lib/library.dart'), contains('    zetTwijfelVanPc(\n        pad,'));
  });

  test('de pc: beluisteren op id (nooit een pad), vervangen en weggooien als opdracht; ook via de doorgever', () {
    final server = _bron('lib/lan/server.dart');
    expect(server, contains("    if (path.startsWith('/kandidaat/')) return _kandidaat(req);"));
    expect(server, contains('    final g = downloads?.twijfel?.metId(id);'));
    expect(server, contains("      case '/api/twijfel':\n        return _twijfel(req);"));
    expect(server, contains("    '/api/twijfel',\n"));
    expect(server, contains("'/stream/', '/groei/', '/kandidaat/',"));
    expect(_bron('lib/lan/doorgever.dart'), contains("!pad.startsWith('/kandidaat/')"));
  });

  test('de albumpagina: het label naast de kwaliteit, en de keuzes bovenaan het menu van de rij (ook op de tv)', () {
    final main = _bron('lib/main.dart');
    expect(main, contains('              _echtheidMerk(t),\n              _twijfelMerk(t),\n              _qualityBadge(_trackQuality(t)),'));
    expect(main, contains('      if (twijfel != null) _twijfelRegels(context, t, twijfel),'));
    expect(main, contains("'Twijfelkopie gebruiken (vervangen)'"));
    expect(main, contains("'Twijfelkopie weggooien…'"));
    expect(main, contains("'http://\$kPcHost/kandidaat/\${tw.id}.\${tw.ext}'"));
    expect(main, contains('      downloads.twijfel = twijfels;'));
  });

  group('weggooien', () {
    late Directory map;
    late DownloadManager d;
    final naarBak = <String>[];
    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_twijfel_weg_');
      d = DownloadManager(OnlineService(AppSettings()), SoulseekService(AppSettings()), map.path, () async {})
        ..twijfel = Twijfellijst('${map.path}/twijfel.json');
      naarBak.clear();
      DownloadManager.prullenbak = (paden) async {
        naarBak.addAll(paden);
        for (final p in paden) {
          File(p).deleteSync();
        }
        return paden.toSet();
      };
    });
    tearDown(() {
      DownloadManager.prullenbak = (_) async => {};
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('naar de prullenbak, je eigen kopie blijft, en dezelfde kandidaat komt niet terug', () async {
      final eigen = File('${map.path}/Albums/Daft Punk/Discovery/06 - Nightvision.flac')..createSync(recursive: true);
      final kandidaat = File('${map.path}/$twijfelMap/x1.flac')
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(100, 1));
      d.twijfel!.zet(Twijfelgeval(
          id: 'x1', pad: eigen.path, kandidaat: kandidaat.path, bron: 'Soulseek a', score: 0.858,
          kwaliteit: 'FLAC 24/96', ms: 1, grootte: 100));
      expect(twijfelVoor(eigen.path), isNotNull);
      final zin = await d.gooiTwijfelWeg(eigen.path);
      expect(zin, contains('je eigen kopie blijft'));
      expect(naarBak, [kandidaat.path]);
      expect(eigen.existsSync(), isTrue);
      expect(twijfelVoor(eigen.path), isNull, reason: 'het label verdwijnt');
      expect(d.twijfel!.afgewezen(eigen.path, 100), isTrue);
      expect(await d.gooiTwijfelWeg(eigen.path), contains('geen twijfelkopie meer'));
    });

    test('bewaren: de kopie gaat naar de twijfelmap, één per nummer, en een weggegooide komt niet terug', () async {
      final eigen = File('${map.path}/Albums/Daft Punk/Discovery/06 - Nightvision.flac')..createSync(recursive: true);
      File binnen(String naam, int grootte) =>
          File('${map.path}/_keuring/$naam/06 Nightvision.flac')
            ..createSync(recursive: true)
            ..writeAsBytesSync(List.filled(grootte, 2));
      final eerste = binnen('a', 300);
      expect(await d.bewaarAlsTwijfel(eerste, eigen.path, 0.858, 'torrent "Discovery 24/96"', null), isTrue);
      expect(eerste.existsSync(), isFalse, reason: 'weg uit de keuringsmap');
      final g = d.twijfel!.van(eigen.path)!;
      expect(File(g.kandidaat).existsSync(), isTrue);
      expect(g.kandidaat.replaceAll('\\', '/'), contains('/$twijfelMap/'));
      expect(g.score, 0.858);
      expect(twijfelVoor(eigen.path)?.bron, 'torrent "Discovery 24/96"');

      final tweede = binnen('b', 400);
      expect(await d.bewaarAlsTwijfel(tweede, eigen.path, 0.86, 'Soulseek b', null), isTrue);
      expect(tweede.existsSync(), isFalse);
      expect(d.twijfel!.van(eigen.path)!.bron, 'torrent "Discovery 24/96"', reason: 'het eerste geval blijft staan');

      await d.gooiTwijfelWeg(eigen.path);
      final weer = binnen('c', 300);
      expect(await d.bewaarAlsTwijfel(weer, eigen.path, 0.858, 'torrent "Discovery 24/96"', null), isTrue);
      expect(d.twijfel!.van(eigen.path), isNull, reason: 'dezelfde kandidaat (zelfde grootte) komt niet terug');
      expect(weer.existsSync(), isFalse);
    });

    test('zonder twijfellijst (een toestel, een toets): niets bewaard — dan is het "een andere opname" zoals voorheen',
        () async {
      d.twijfel = null;
      final f = File('${map.path}/_keuring/z/x.flac')..createSync(recursive: true);
      expect(await d.bewaarAlsTwijfel(f, '${map.path}/x.flac', 0.8, 'Soulseek z', null), isFalse);
      expect(f.existsSync(), isTrue);
    });

    test('vervangen zonder kopie op schijf: het geval is voorbij, niets verandert', () async {
      final eigen = File('${map.path}/Albums/x.flac')..createSync(recursive: true);
      d.twijfel!.zet(Twijfelgeval(
          id: 'y', pad: eigen.path, kandidaat: '${map.path}/$twijfelMap/y.flac', bron: 'TIDAL 1', score: 0.8,
          kwaliteit: 'FLAC 24/44,1', ms: 1, grootte: 5));
      expect(await d.vervangDoorTwijfel(eigen.path), contains('staat er niet meer'));
      expect(twijfelVoor(eigen.path), isNull);
      expect(eigen.existsSync(), isTrue);
    });
  });
}

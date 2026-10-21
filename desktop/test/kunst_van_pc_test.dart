// De cd en de achterkant meteen: een toestel vraagt ze eerst aan de pc (Saber, 21-10-2026, over Azizam op de
// gsm: "het duurde even voor ik de afbeelding van de cd zag … Ook na updates of koude start of wissel van
// toestel moet die er direct staan").
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

Uint8List _b(int n, [int lengte = 400]) => Uint8List.fromList(List.filled(lengte, n));

void main() {
  group('kunstNaarJson / kunstUitJson', () {
    test('heen en terug, met herkomst en of het af is', () {
      final a = ReleaseArt(front: _b(1), back: _b(2), disc: _b(3), bron: 'dz:1', formaat: 'CD');
      final v = kunstUitJson(kunstNaarJson(a, klaar: true))!;
      expect(v.klaar, isTrue);
      expect(v.art.front, a.front);
      expect(v.art.back, a.back);
      expect(v.art.disc, a.disc);
      expect(v.art.bron, 'dz:1');
      expect(v.art.formaat, 'CD');
      final alleenCd = kunstUitJson(kunstNaarJson(ReleaseArt(disc: _b(3)), klaar: false))!;
      expect(alleenCd.klaar, isFalse);
      expect(alleenCd.art.front, isNull);
      expect(alleenCd.art.disc, _b(3));
    });

    test('leeg of rommel: null', () {
      expect(kunstUitJson(null), isNull);
      expect(kunstUitJson('x'), isNull);
      expect(kunstUitJson({'klaar': true}), isNull);
      expect(kunstUitJson({'disc': '%%% geen base64'}), isNull);
    });
  });

  group('de keten vraagt eerst de pc', () {
    late Directory krab;
    setUp(() {
      krab = Directory.systemTemp.createTempSync('dm_kunstpc_');
      setAppDirForTest(krab.path);
    });
    tearDown(() {
      DiscogsArtwork.vanDePc = null;
      try {
        krab.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('heeft de pc het af, dan is dat het antwoord: meteen op het scherm en op schijf', () async {
      final vanPc = ReleaseArt(front: _b(1), back: _b(2), disc: _b(3), bron: 'rel:42');
      final gevraagd = <String>[];
      DiscogsArtwork.vanDePc = (artist, album) async {
        gevraagd.add('$artist|$album');
        return (art: vanPc, klaar: true);
      };
      final tussen = <ReleaseArt>[];
      // Een aangewezen voorkant (rol) houdt de digitale zoektocht en dus het net buiten deze toets.
      const rollen = {'front': 'https://voorbeeld.invalid/voor.jpg'};
      final dienst = DiscogsService(AppSettings());
      final art = await dienst.releaseArt('Ed Sheeran', 'Azizam', expectedTracks: 1, roles: rollen, tussenstand: tussen.add);
      expect(gevraagd, ['Ed Sheeran|Azizam']);
      expect(art?.disc, vanPc.disc);
      expect(art?.back, vanPc.back);
      expect(tussen, isNotEmpty, reason: 'de cd staat er meteen, ook als de rest nog loopt');
      // En de volgende keer van schijf, zonder de pc: na een koude start meteen.
      DiscogsArtwork.vanDePc = (artist, album) async => fail('niet nog eens vragen');
      final opnieuw = await dienst.cachedReleaseArt('Ed Sheeran', 'Azizam', expectedTracks: 1, roles: rollen);
      expect(opnieuw?.disc, vanPc.disc);
      expect(await dienst.hasReleaseArt('Ed Sheeran', 'Azizam', expectedTracks: 1, roles: rollen), isTrue);
    });
  });

  group('aangesloten', () {
    test('het toestel zet de haak, de pc heeft het eindpunt, en de pc gooit de scans niet meer weg', () {
      String lees(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
      final main = lees('lib/main.dart');
      expect(main, contains('DiscogsArtwork.vanDePc = (artist, album) async {'));
      expect(main, contains('return kunstUitJson(await c.releaseArtJson(id));'));
      final server = lees('lib/lan/server.dart');
      expect(server, contains("case '/api/releaseart':\n        return _releaseArt(req);"));
      expect(server, contains("    '/api/releaseart',\n  };"), reason: 'ook van buitenaf: het zijn alleen plaatjes');
      final eindpunt = server.substring(server.indexOf('  Future<void> _releaseArt(HttpRequest req) async {'));
      expect(eindpunt.substring(0, eindpunt.indexOf('\n  }\n')), isNot(contains('verkleindeHoes')),
          reason: 'op volle resolutie (Saber: "worden die nooit op volle resolutie getoond dan ???")');
      expect(server, contains('return _json(req.response, kunstNaarJson(art, klaar: klaar));'));
      final discogs = lees('lib/discogs.dart');
      expect(discogs, contains('_vanPcOfVers(artist, album, expectedTracks, pinned, pinnedMbid, roles, dir, trace, freeOnly, meld)'));
      final snoei = lees('lib/cache_snoei.dart');
      expect(snoei, contains("'releaseart': 3 * 1024 * 1024 * 1024,"));
    });
  });
}

// Bestaat de studio officieel? TIDAL vragen (26-11-2026).
//
// Saber, bij Ricky Martin "Maria" ("Studio · 24/48" van Soulseek, een gedecodeerde Opus-stream): "Laat de app
// controleren via qobuz en tidal of dit daadwerkelijk studio bestaat". De regels hieronder zijn wat tidalers zoekhulpje
// die avond op de pc gaf voor "Ricky Martin Maria" (hoesadressen weggelaten).
import 'dart:io';

import 'package:debridmusic/studio_op_tidal.dart';
import 'package:debridmusic/tidal_beter.dart' show tidalStereoNummers;
import 'package:flutter_test/flutter_test.dart';

const _uitvoer = '''
{"soort": "artiest", "id": "535", "naam": "Ricky Martin"}
{"soort": "album", "id": "468869211", "artiest": "Ricky Martin", "titel": "Maria (KAAZE Remix)", "jaar": "2025", "aantal": 1, "tags": ["LOSSLESS", "HIRES_LOSSLESS"]}
{"soort": "track", "id": "11337147", "artiest": "Ricky Martin", "titel": "María (Pablo Flores Spanglish Radio Edit)", "seconden": 271, "nummer": 14, "schijf": 1, "album": "Ricky Martin", "albumId": "11337146", "stereo": true, "tags": ["LOSSLESS"]}
{"soort": "track", "id": "13163745", "artiest": "Ricky Martin", "titel": "María", "seconden": 263, "nummer": 3, "schijf": 1, "album": "A Medio Vivir", "albumId": "13163692", "stereo": true, "tags": ["LOSSLESS"]}
{"soort": "track", "id": "1720283", "artiest": "Ricky Martin", "titel": "María (MTV Unplugged Version)", "seconden": 331, "nummer": 3, "schijf": 1, "album": "Ricky Martin MTV Unplugged", "albumId": "1720280", "stereo": true, "tags": ["LOSSLESS"]}
{"soort": "track", "id": "14508583", "artiest": "Ricky Martin", "titel": "María (Spanglish Extended)", "seconden": 475, "nummer": 3, "schijf": 1, "album": "It's Alright", "albumId": "28204", "stereo": true, "tags": ["LOSSLESS"]}
{"soort": "track", "id": "468869212", "artiest": "Ricky Martin", "titel": "Maria (KAAZE Remix)", "seconden": 156, "nummer": 1, "schijf": 1, "album": "Maria (KAAZE Remix)", "albumId": "468869211", "stereo": true, "tags": ["LOSSLESS", "HIRES_LOSSLESS"]}
{"soort": "track", "id": "377088629", "artiest": "Ricky Martin", "titel": "Maria (Spanglish Radio Edit)", "seconden": 243, "nummer": 24, "schijf": 1, "album": "Verano Éxitos de los 90", "albumId": "377088605", "stereo": true, "tags": ["LOSSLESS", "HIRES_LOSSLESS"]}
{"soort": "track", "id": "1", "artiest": "Luciano Pavarotti", "titel": "We Are The World (Live)", "seconden": 351, "album": "Pavarotti & Friends", "stereo": true, "tags": ["LOSSLESS"]}
''';

StudioOpTidal maria({String artiest = 'Ricky Martin', String titel = 'Maria', required int seconden}) =>
    studioOpTidal(artiest: artiest, titel: titel, seconden: seconden, nummers: tidalStereoNummers(_uitvoer));

String bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('wat TIDAL van precies deze opname heeft', () {
    test('DE KERN: Maria van 271 s — TIDAL noemt hem "María (Pablo Flores Spanglish Radio Edit)", alleen LOSSLESS', () {
      expect(maria(seconden: 271), StudioOpTidal.alleenCd);
      expect(maria(seconden: 269), StudioOpTidal.alleenCd, reason: 'je cd-single: 2 s korter, nog dezelfde opname');
    });

    test('een andere edit die WEL in hi-res bestaat: hi-res — maar alleen bij zijn eigen lengte', () {
      expect(maria(titel: 'Maria (Spanglish Radio Edit)', seconden: 243), StudioOpTidal.hires);
      expect(maria(seconden: 244), StudioOpTidal.hires);
      expect(maria(seconden: 266), StudioOpTidal.onbekend, reason: 'drie seconden naast elke edit: niet dezelfde opname');
    });

    test('het origineel van A Medio Vivir (263 s, streng gelijke titel): alleen cd', () {
      expect(maria(titel: 'María', seconden: 263), StudioOpTidal.alleenCd);
    });

    test('wat een andere opname noemt telt niet: unplugged, remix', () {
      expect(maria(seconden: 331), StudioOpTidal.onbekend, reason: '"MTV Unplugged Version" is niet je studio-opname');
      expect(maria(seconden: 156), StudioOpTidal.onbekend, reason: 'de KAAZE-remix');
      expect(maria(titel: 'Maria (MTV Unplugged)', seconden: 331), StudioOpTidal.alleenCd,
          reason: 'tenzij jouw titel het ook zegt');
    });

    test('een andere artiest, of geen lengte: niets bewezen', () {
      expect(maria(artiest: 'Santana', seconden: 271), StudioOpTidal.onbekend);
      expect(maria(seconden: 0), StudioOpTidal.onbekend);
      expect(maria(titel: '', seconden: 271), StudioOpTidal.onbekend);
    });

    test('de kern van een titel: zonder haakjes, staart en accenten', () {
      expect(studioTitelKern('María (Pablo Flores Spanglish Radio Edit)'), studioTitelKern('Maria'));
      expect(studioTitelKern('Maria - Radio Edit'), studioTitelKern('Maria'));
      expect(studioTitelKern('Maria (feat. X)'), studioTitelKern('Maria'));
    });
  });

  group('de vraag aan TIDAL', () {
    test('wat TIDAL zei, onthoudt hij: twee kopieën van hetzelfde nummer, één vraag', () async {
      var vragen = <String>[];
      final vraag = studioOpTidalVraag(zoek: (v) async {
        vragen.add(v);
        return _uitvoer;
      });
      expect(await vraag('Ricky Martin', 'Maria', 271), StudioOpTidal.alleenCd);
      expect(await vraag('Ricky Martin', 'Maria', 271), StudioOpTidal.alleenCd);
      expect(vragen, ['Ricky Martin Maria']);
    });

    test('geen antwoord (of een fout) wordt niet onthouden: de volgende keer opnieuw', () async {
      var keer = 0;
      final vraag = studioOpTidalVraag(zoek: (v) async {
        keer++;
        if (keer == 1) return null;
        if (keer == 2) throw StateError('netwerk');
        return _uitvoer;
      });
      expect(await vraag('Ricky Martin', 'Maria', 271), StudioOpTidal.geenAntwoord);
      expect(await vraag('Ricky Martin', 'Maria', 271), StudioOpTidal.geenAntwoord);
      expect(await vraag('Ricky Martin', 'Maria', 271), StudioOpTidal.alleenCd);
    });

    test('na het geheugen vraagt hij opnieuw: TIDAL voegt hi-res toe', () async {
      var nu = DateTime(2026, 11, 26);
      var keer = 0;
      final vraag = studioOpTidalVraag(
          zoek: (v) async {
            keer++;
            return _uitvoer;
          },
          klok: () => nu);
      await vraag('Ricky Martin', 'Maria', 271);
      nu = nu.add(const Duration(hours: 13));
      await vraag('Ricky Martin', 'Maria', 271);
      expect(keer, 2);
    });
  });

  group('de studioversies die er al staan', () {
    late Directory map;
    setUp(() => map = Directory.systemTemp.createTempSync('studio_op_tidal_'));
    tearDown(() {
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    StudioTeKijken item(String naam, int sec) =>
        (versie: 'D:/m/$naam (studio)/01.flac', anker: 'D:/m/$naam/01.flac', artiest: 'X', titel: naam, seconden: sec);

    test('wat TIDAL alleen in cd heeft gaat weg, hi-res blijft, en het geheugen overleeft een herstart', () async {
      var nu = DateTime(2026, 11, 26, 22);
      final weg = <String>[];
      final lijst = [item('Maria', 271), item('Echt', 200), item('Onbekend', 100)];
      StudioNakijker maak() => StudioNakijker(
            bestand: '${map.path}${Platform.pathSeparator}studio_op_tidal.json',
            teKijken: () => lijst,
            vraag: (a, t, s) async => switch (t) {
              'Maria' => StudioOpTidal.alleenCd,
              'Echt' => StudioOpTidal.hires,
              _ => StudioOpTidal.onbekend,
            },
            weg: (s) async => weg.add(s.versie),
            klok: () => nu,
          );
      final n = maak();
      expect(await n.stap(), StudioOpTidal.alleenCd);
      expect(await n.stap(), StudioOpTidal.hires);
      expect(await n.stap(), StudioOpTidal.onbekend);
      expect(await n.stap(), isNull, reason: 'alles net nagekeken');
      expect(weg, ['D:/m/Maria (studio)/01.flac']);

      final na = maak();
      await na.laad();
      expect(na.van('D:/m/Echt (studio)/01.flac')?.k, StudioOpTidal.hires);
      expect(await na.stap(), isNull);
      nu = nu.add(const Duration(days: 8));
      expect(na.volgende()?.titel, 'Onbekend', reason: 'onbekend na een week opnieuw, de rest pas na een maand');
    });

    test('geen antwoord: na een dag opnieuw, en niets weggegooid', () async {
      var nu = DateTime(2026, 11, 26, 22);
      final weg = <String>[];
      final n = StudioNakijker(
        bestand: '${map.path}${Platform.pathSeparator}s.json',
        teKijken: () => [item('Maria', 271)],
        vraag: (a, t, s) async => StudioOpTidal.geenAntwoord,
        weg: (s) async => weg.add(s.versie),
        klok: () => nu,
      );
      expect(await n.stap(), StudioOpTidal.geenAntwoord);
      expect(await n.stap(), isNull);
      nu = nu.add(const Duration(hours: 25));
      expect(n.volgende(), isNotNull);
      expect(weg, isEmpty);
    });

    test('zonder lengte niet te vragen', () {
      final n = StudioNakijker(
          bestand: '${map.path}${Platform.pathSeparator}s.json',
          teKijken: () => [item('Maria', 0)],
          vraag: (a, t, s) async => StudioOpTidal.alleenCd,
          weg: (s) async {});
      expect(n.volgende(), isNull);
    });
  });

  group('aangesloten', () {
    test('bij binnenkomst: de studioversie (jacht en gewone weg) en de soortvraag vragen TIDAL', () {
      final o = bron('lib/online.dart');
      expect(o, contains('      return await vraag(artiest, titel, sec) == StudioOpTidal.alleenCd ? kGeenStudioOpTidal : null;\n'));
      expect(o, contains('    if (plan.soort == Kopiesoort.studio) {\n      final eigen = gezag == null ? readFlacTags(File(plan.anker)) : null;\n'));
      expect(o, contains('      if (await geenStudioVolgensTidal(staged, artiest: v.artiest, titel: v.titel) case final geen?) return weg(geen);\n'));
    });

    test('de pc zet de vraag en de nakijker, en gooit alleen een studioversie weg naast een nummer dat er nog is', () {
      final m = bron('lib/main.dart');
      expect(m, contains('      DownloadManager.studioOpTidalVraag = studioVraag;\n'));
      final i = m.indexOf('      final studioNakijker = StudioNakijker(\n');
      expect(i, greaterThan(0));
      final stuk = m.substring(i, m.indexOf('      unawaited(studioNakijker.start()', i));
      expect(stuk, contains('if (v == null || anker == null || v.soort != Kopiesoort.studio) continue;'));
      expect(stuk, contains('          final zin = await gooiVersieWeg(library, anker, s.versie);\n'));
    });
  });
}

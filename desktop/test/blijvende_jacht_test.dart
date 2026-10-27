// De blijvende jacht op een betere kopie (Saber, 27-10-2026: "eigelijk mag de jacht niet stoppen, ten ware er echt 100
// procent bewezen is dat die plaat of nummer gewoon niet bestaat in betere kwaliteit ... maar we moeten rekening houden
// dat we niet geblokkeerd worden"). Hij koos: na een bewijs nog maandelijks, alles onder de top, _dubbel na 30 dagen
// naar de prullenbak, tien zoekopdrachten per vijf minuten.
import 'dart:io';

import 'package:debridmusic/blijvende_jacht.dart';
import 'package:debridmusic/dubbel_opruimer.dart';
import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/tidal.dart' show TidalKwaliteit, TidalTrack;
import 'package:debridmusic/tidal_beter.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

Track _t(String pad, {int bits = 16, int hz = 44100, String album = 'Discovery', int sec = 235, int added = 0}) => Track(
    path: pad,
    title: pad.split('/').last.replaceAll('.flac', ''),
    artist: 'Daft Punk',
    album: album,
    duration: Duration(seconds: sec),
    isFlac: true,
    bitsPerSample: bits,
    sampleRate: hz,
    addedMs: added);

Echtheidsoordeel _o({Bovenband boven = Bovenband.onbekend, Bandbreedte band = Bandbreedte.doorlopend, int bits = 16}) =>
    Echtheidsoordeel(bits: Bitdiepte.spreektNietTegen, boven: boven, band: band, gebruikteBits: bits, vensters: 700);

Afwijzing _a(String u, int s, String dag, [Kopieuitslag uit = Kopieuitslag.gelijk]) =>
    (uploader: u, grootte: s, dag: dag, uit: uit);

void main() {
  group('wat bewezen is', () {
    test('DE KERN: echt 24/96 met klank boven 24,5 kHz is de top; zonder die klank niet', () {
      final t = _t('D:/M/a.flac', bits: 24, hz: 96000);
      expect(bewijsVoor(t, o: _o(boven: Bovenband.vol, bits: 24)), Jachtbewijs.top);
      expect(bewijsVoor(t, o: _o(boven: Bovenband.onbekend, bits: 24)), Jachtbewijs.geen, reason: 'niet gemeten boven 24,5');
      expect(bewijsVoor(t, o: _o(boven: Bovenband.vol, bits: 16)), Jachtbewijs.geen, reason: 'opgeblazen tot 24 bit');
      expect(bewijsVoor(_t('D:/M/b.flac', bits: 24, hz: 48000), o: _o(boven: Bovenband.vol, bits: 24)), Jachtbewijs.geen,
          reason: '48 kHz: een 96 kan nog');
      expect(bewijsVoor(t), Jachtbewijs.geen, reason: 'zonder meting niets bewezen');
    });

    test('officieel het beste: TIDAL heeft precies deze opname alleen in cd-kwaliteit, en de jouwe is een echte', () {
      final cd = _t('D:/M/c.flac');
      expect(bewijsVoor(cd, o: _o(), tidalHoogste: TidalKwaliteit.cd), Jachtbewijs.officieel);
      expect(bewijsVoor(cd, o: _o(band: Bandbreedte.vermoedelijk), tidalHoogste: TidalKwaliteit.cd), Jachtbewijs.officieel,
          reason: 'een muur rond 20,9 kHz is bijna altijd het cd-filter');
      expect(bewijsVoor(cd, o: _o(), tidalHoogste: TidalKwaliteit.hires), Jachtbewijs.geen, reason: 'er bestaat hi-res');
      expect(bewijsVoor(cd, o: _o(), tidalHoogste: null), Jachtbewijs.geen, reason: 'TIDAL kent hem niet: niets bewezen');
      expect(
          bewijsVoor(cd,
              o: const Echtheidsoordeel(bits: Bitdiepte.onbekend, boven: Bovenband.onbekend, band: Bandbreedte.afgekapt),
              tidalHoogste: TidalKwaliteit.cd),
          Jachtbewijs.geen,
          reason: 'een transcode is nooit het beste');
      final mp3 = Track(
          path: 'D:/M/d.mp3', title: 'd', artist: 'x', album: 'y', duration: const Duration(seconds: 200), sampleRate: 44100);
      expect(bewijsVoor(mp3, o: _o(), tidalHoogste: TidalKwaliteit.cd), Jachtbewijs.geen);
    });

    test('eensgezind: drie echte kopieën van drie uploaders op twee dagen, geen enkele beter', () {
      final t = _t('D:/M/e.flac');
      expect(bewijsVoor(t, nee: [_a('a', 1, '2026-10-27'), _a('b', 2, '2026-10-27'), _a('c', 3, '2026-10-28')]),
          Jachtbewijs.eensgezind);
      expect(bewijsVoor(t, nee: [_a('a', 1, '2026-10-27'), _a('b', 2, '2026-10-27'), _a('c', 3, '2026-10-27')]),
          Jachtbewijs.geen, reason: 'één dag: wie vandaag online is, deelt vaak hetzelfde bestand');
      expect(bewijsVoor(t, nee: [_a('a', 1, '2026-10-27'), _a('A', 2, '2026-10-28'), _a('b', 3, '2026-10-28')]),
          Jachtbewijs.geen, reason: 'twee uploaders');
      expect(
          bewijsVoor(t,
              nee: [_a('a', 1, '2026-10-27'), _a('b', 2, '2026-10-28'), _a('c', 3, '2026-10-28', Kopieuitslag.nep)]),
          Jachtbewijs.geen,
          reason: 'een vervalsing bewijst niets over wat er echt bestaat');
    });
  });

  group('het ritme', () {
    test('DE KERN: na je klik een uur, drie, acht, een dag …; na een bewijs een maand', () {
      Duration w(int r, {bool g = true, Jachtbewijs b = Jachtbewijs.geen}) =>
          jachtWacht(Jachtstand(rondes: r, gevraagd: g), b);
      expect(w(0), Duration.zero);
      expect(w(1), const Duration(hours: 1));
      expect(w(2), const Duration(hours: 3));
      expect(w(3), const Duration(hours: 8));
      expect(w(4), const Duration(days: 1, hours: 20), reason: 'een dag, en een ander uur van de dag');
      expect(w(7), kJachtDaarna + const Duration(hours: 11));
      expect(w(1, g: false), const Duration(days: 2, hours: 5), reason: 'de rest van de bibliotheek: rustiger');
      expect(w(1, b: Jachtbewijs.officieel), kJachtNaBewijs + const Duration(hours: 5));
      expect(jachtAanDeBeurt(null, 0, Jachtbewijs.top), isTrue, reason: 'nog nooit gezocht: meteen');
    });
  });

  group('het geheugen', () {
    late Directory map;
    setUp(() => map = Directory.systemTemp.createTempSync('dm_blijvend_'));
    tearDown(() => map.deleteSync(recursive: true));

    test('je klik is de eerste ronde; een kopie die al binnen was, komt nooit terug; alles blijft na een herstart', () async {
      final j = BlijvendeJachten('${map.path}/blijvende_jacht.json');
      j.vraag(['D:\\M\\Discovery\\01.flac'], 1000);
      expect(j.van('d:/m/discovery/01.flac')?.rondes, 1);
      expect(j.van('D:/M/Discovery/01.flac')?.gevraagd, isTrue);
      j.ronde('D:/M/Discovery/01.flac', 5000);
      expect(j.van('D:/M/Discovery/01.flac')?.laatsteMs, 5000);
      j.noteer('D:/M/Discovery/01.flac', 'Uploader', 123, Kopieuitslag.gelijk, DateTime(2026, 10, 27));
      j.noteer('D:/M/Discovery/01.flac', 'uploader', 123, Kopieuitslag.gelijk, DateTime(2026, 10, 28));
      j.noteer('D:/M/Discovery/01.flac', 'x', 9, Kopieuitslag.beter, DateTime(2026, 10, 28));
      expect(j.isAfgewezen('D:/M/Discovery/01.flac', 'UPLOADER', 123), isTrue);
      expect(j.isAfgewezen('D:/M/Discovery/01.flac', 'uploader', 124), isFalse, reason: 'een ander bestand');
      expect(j.van('D:/M/Discovery/01.flac')!.nee, hasLength(1), reason: 'twee keer hetzelfde is één; beter onthoudt niets');
      await j.bewaar();
      final terug = BlijvendeJachten('${map.path}/blijvende_jacht.json');
      await terug.laad();
      final s = terug.van('D:/M/Discovery/01.flac')!;
      expect((s.rondes, s.laatsteMs, s.gevraagd), (2, 5000, true));
      expect(s.nee.single, (uploader: 'Uploader', grootte: 123, dag: '2026-10-27', uit: Kopieuitslag.gelijk));
    });

    test('de volgende plaat: wat je vroeg, dan wat nog nooit gezocht is (nieuwst eerst), dan wat het langst wacht', () {
      final j = BlijvendeJachten('${map.path}/x.json');
      final a1 = _t('D:/M/Albums/Daft Punk/Discovery/01.flac', added: 1);
      final a2 = _t('D:/M/Albums/Daft Punk/Discovery/02.flac', added: 1);
      final b1 = _t('D:/M/Albums/Daft Punk/Homework/01.flac', album: 'Homework', added: 5);
      final s1 = _t('D:/M/Singles/Daft Punk/Get Lucky.flac', album: 'Random Access Memories', added: 9);
      final alle = [a1, a2, b1, s1];
      Jachtbewijs geen(Track t, Jachtstand? s) => Jachtbewijs.geen;
      bool niets(Track t) => false;
      var p = volgendePlaat(alle, j, nuMs: 100, bewijs: geen, overslaan: niets)!;
      expect(p.nummers, [s1], reason: 'nooit gezocht, het nieuwst; een single staat voor zich');
      expect(p.album, '');
      j.ronde(s1.path, 100);
      p = volgendePlaat(alle, j, nuMs: 100, bewijs: geen, overslaan: niets)!;
      expect(p.nummers, [b1]);
      j.ronde(b1.path, 100);
      p = volgendePlaat(alle, j, nuMs: 100, bewijs: geen, overslaan: niets)!;
      expect(p.nummers, [a1, a2], reason: 'één zoekopdracht voor de hele plaat');
      expect(p.album, 'Discovery');
      j.vraag([a1.path, a2.path], 100);
      expect(volgendePlaat(alle, j, nuMs: 100, bewijs: geen, overslaan: niets), isNull, reason: 'alles net gezocht');
      final straks = 100 + const Duration(hours: 1).inMilliseconds;
      expect(volgendePlaat(alle, j, nuMs: straks, bewijs: geen, overslaan: niets)!.nummers, [a1, a2],
          reason: 'je klik: na een uur weer');
      expect(volgendePlaat(alle, j, nuMs: straks, bewijs: geen, overslaan: (t) => t.path.contains('Discovery')), isNull);
    });

    test('de ronde: telt alleen als er gezocht kon worden, en zoekt niets als het niet mag', () async {
      final j = BlijvendeJachten('${map.path}/r.json');
      final t = _t('D:/M/Singles/x.flac', album: '');
      var mag = false, uitslag = Jachtronde.nietGezocht;
      final gezocht = <Jachtplaat>[];
      final r = BlijvendeJachtRonde(
        jachten: j,
        nummers: () => [t],
        bewijs: (t, s) => Jachtbewijs.geen,
        jaag: (p) async {
          gezocht.add(p);
          return uitslag;
        },
        kan: () => mag,
        overslaan: (_) => false,
        klok: () => DateTime(2026, 10, 27, 9),
      );
      expect(await r.stap(), isNull, reason: 'Soulseek zwijgt, of de rij met jachten is vol');
      expect(gezocht, isEmpty);
      mag = true;
      expect(await r.stap(), isNull);
      expect(gezocht, hasLength(1));
      expect(j.van(t.path), isNull, reason: 'niet gezocht: telt niet');
      uitslag = Jachtronde.gezocht;
      expect((await r.stap())?.nummers, [t]);
      expect(j.van(t.path)?.rondes, 1);
      expect(File('${map.path}/r.json').existsSync(), isTrue);
    });

    test('wat het kwaliteitsblad zegt', () {
      final nu = DateTime(2026, 10, 27, 9);
      final t = _t('D:/M/x.flac', bits: 24, hz: 96000);
      expect(jachtZin(t, null, Jachtbewijs.top, nu: nu), startsWith('Bewezen het beste: echt 24/96'));
      expect(jachtZin(t, null, Jachtbewijs.geen, nu: nu), 'Nog niet gezocht: dit nummer komt vanzelf aan de beurt.');
      final s = Jachtstand(
          rondes: 2, laatsteMs: nu.millisecondsSinceEpoch, gevraagd: true, nee: [_a('a', 1, '2026-10-27')]);
      expect(jachtZin(t, s, Jachtbewijs.geen, nu: nu),
          'Zoekt verder naar een betere kopie: 2 keer gezocht, 1 kopie binnengehaald en niet beter. Volgende keer vandaag om 12:00.');
    });
  });

  group('TIDAL: het beste dat er van deze opname is', () {
    test('hi-res, cd, of niets — alleen van dezelfde opname', () {
      final t = _t('D:/M/Discovery/01 - One More Time.flac', sec: 320);
      TidalTrack x(String titel, int sec, TidalKwaliteit k, {String artiest = 'Daft Punk'}) =>
          TidalTrack('1', titel, artiest, seconden: sec, kwaliteit: k);
      expect(hoogsteOpTidal(t, [x('01 - One More Time', 321, TidalKwaliteit.cd)]), TidalKwaliteit.cd);
      expect(
          hoogsteOpTidal(t, [x('01 - One More Time', 321, TidalKwaliteit.cd), x('01 - One More Time', 320, TidalKwaliteit.hires)]),
          TidalKwaliteit.hires);
      expect(hoogsteOpTidal(t, [x('01 - One More Time', 400, TidalKwaliteit.hires)]), isNull, reason: 'een andere snit');
      expect(hoogsteOpTidal(t, [x('01 - One More Time', 320, TidalKwaliteit.hires, artiest: 'Iemand Anders')]), isNull);
    });

    test('het geheugen van de ronde onthoudt het, ook na een herstart', () async {
      final map = Directory.systemTemp.createTempSync('dm_tidal_max_');
      addTearDown(() => map.deleteSync(recursive: true));
      final g = TidalBeterGeheugen('${map.path}/tidal_beter.json')
        ..zet('D:/M/a.flac', TidalBeterUitslag.geen, 1, hoogste: TidalKwaliteit.cd)
        ..zet('D:/M/a.flac', TidalBeterUitslag.mislukt, 2);
      expect(g.hoogsteVan('d:/m/a.flac'), TidalKwaliteit.cd, reason: 'een mislukte ronde weet niets nieuws');
      await g.bewaar();
      final terug = TidalBeterGeheugen('${map.path}/tidal_beter.json');
      await terug.laad();
      expect(terug.hoogsteVan('D:/M/a.flac'), TidalKwaliteit.cd);
    });
  });

  group('_dubbel: na 30 dagen naar de prullenbak', () {
    late Directory map;
    setUp(() => map = Directory.systemTemp.createTempSync('dm_dubbel_'));
    tearDown(() => map.deleteSync(recursive: true));

    test('DE KERN: geteld vanaf de eerste keer gezien, niet op de bestandsdatum; een nieuwer bestand blijft', () async {
      final dubbel = Directory('${map.path}/_dubbel')..createSync();
      final oud = File('${dubbel.path}/(2) 01 - 7 Years.flac')
        ..writeAsBytesSync(List.filled(100, 1))
        ..setLastModifiedSync(DateTime(2019));
      final g = DubbelGeheugen('${map.path}/dubbel_gezien.json');
      final weg = <String>[];
      Future<Set<String>> bak(List<String> p) async {
        weg.addAll(p);
        for (final x in p) {
          File(x).deleteSync();
        }
        return p.toSet();
      }

      final dag0 = DateTime(2026, 10, 27);
      expect((await ruimDubbelOp(map: dubbel, geheugen: g, prullenbak: bak, nu: dag0)).bestanden, 0,
          reason: 'een kopie van 2019 die gisteren opzij ging, gaat niet meteen weg');
      final nieuw = File('${dubbel.path}/binnengekomen/x.flac')
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(50, 2));
      await ruimDubbelOp(map: dubbel, geheugen: g, prullenbak: bak, nu: dag0.add(const Duration(days: 20)));
      final r = await ruimDubbelOp(map: dubbel, geheugen: g, prullenbak: bak, nu: dag0.add(const Duration(days: 30)));
      expect(r.bestanden, 1);
      expect(r.bytes, 100);
      expect(weg.single.replaceAll(r'\', '/'), oud.path.replaceAll(r'\', '/'));
      expect(nieuw.existsSync(), isTrue, reason: 'pas twintig dagen');
      // Na een herstart weet hij nog wanneer hij het nieuwe bestand zag.
      final terug = DubbelGeheugen('${map.path}/dubbel_gezien.json');
      await terug.laad();
      expect(terug.aantal, 1);
      expect((await ruimDubbelOp(map: dubbel, geheugen: terug, prullenbak: bak, nu: dag0.add(const Duration(days: 50)))).bestanden,
          1);
    });

    test('lukt de prullenbak niet, dan blijft het bestand staan en blijft hij het onthouden', () async {
      final dubbel = Directory('${map.path}/_dubbel')..createSync();
      final f = File('${dubbel.path}/a.flac')..writeAsBytesSync(List.filled(10, 1));
      final g = DubbelGeheugen('${map.path}/g.json');
      Future<Set<String>> kapot(List<String> p) async => <String>{};
      await ruimDubbelOp(map: dubbel, geheugen: g, prullenbak: kapot, nu: DateTime(2026));
      final r = await ruimDubbelOp(map: dubbel, geheugen: g, prullenbak: kapot, nu: DateTime(2026, 3));
      expect(r.bestanden, 0);
      expect(f.existsSync(), isTrue);
      expect(g.aantal, 1);
    });
  });

  test('aangesloten: de ronde in de downloadbeheerder, de jacht onthoudt elke kopie, een verliezende download gaat weg', () {
    final online = _bron('lib/online.dart');
    expect(online, contains('hits = await soulseek.search(vraag, achtergrond: true, extra: kHiresZoekwoorden, eigenRem: _jachtRem);'));
    expect(online, contains('      jachten.vraag([for (final t in te) t.path], DateTime.now().millisecondsSinceEpoch);'));
    expect(online, contains('!(jachten?.isAfgewezen(t.path, k.username, k.size) ?? false)'));
    expect(online, contains('blijvend != null && soulseek.available && !soulseek.client.serverZwijgt && _jachten.wachtend == 0;'));
    final jacht = online.substring(online.indexOf('  Future<void> _chaseUpgrade('));
    expect(jacht, contains('parkeerAltijd: parkeerAltijd, parkeerBinnenkomend: false);'));
    expect(jacht, contains('bijUitslag?.call(f, Kopieuitslag.anders);'));
    expect(jacht, contains('                    ? Kopieuitslag.beter\n                    : nepKopie'));
    final main = _bron('lib/main.dart');
    expect(main, contains('        jaag: downloads.jaagBlijvend,'));
    expect(main, contains('        kan: () => downloads.kanBlijvendJagen,'));
    expect(main, contains('            !(t.isFlac || isVerliesvrij(t.ext)) ||'), reason: 'mp3: de verlanglijst loopt al');
    expect(main, contains('                prullenbak: naarPrullenbak);'));
  });
}

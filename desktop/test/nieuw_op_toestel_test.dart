// Wat er op de pc binnenkomt, vanzelf op dit toestel (Saber, 02-11-2026: "ik wil dan ook een liedje die binnenkomt op de pc
// dus, direct lokaal kunnen opslaan op men gsm, ook buitenshuis en automatisch, met limiet van 150 GB"). Gekozen: nieuwe
// downloads en betere kopieën, geen radionummers; vol = een waarschuwing met "Ruimte maken" en "Limiet verhogen".
import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/nieuw_op_toestel.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/toestel_redenen.dart';
import 'package:flutter_test/flutter_test.dart';

final _sinds = DateTime(2026, 11, 2, 8).millisecondsSinceEpoch;

Track _t(String naam,
        {int rate = 44100, int bits = 16, int ms = 200000, int? toegevoegd, String ext = 'flac', int bytes = 30000000}) =>
    Track(
      path: 'D:/Muziek/A/$naam.$ext',
      title: naam,
      artist: 'A',
      album: 'Plaat',
      sampleRate: rate,
      bitsPerSample: bits,
      duration: Duration(milliseconds: ms),
      addedMs: toegevoegd ?? _sinds + 3600000,
      sizeBytes: bytes,
    );

void main() {
  group('de handtekening van het geluid', () {
    test('een hoes of tags veranderen hem niet; een andere kopie wel', () {
      final cd = _t('Bad');
      expect(geluidVan(_t('Bad', toegevoegd: _sinds + 999999, bytes: 31000000)), geluidVan(cd),
          reason: 'een hoes erin: andere tijd en grootte, zelfde geluid');
      expect(geluidVan(_t('Bad', ms: 200011)), isNot(geluidVan(cd)), reason: 'een andere rip: 11 ms langer');
      expect(geluidVan(_t('Bad', rate: 96000, bits: 24)), isNot(geluidVan(cd)), reason: 'een opwaardering');
      expect(geluidVan(_t('Bad', ext: 'mp3')), isNot(geluidVan(cd)));
    });
  });

  group('wat nieuw is', () {
    test('DE KERN: wat de pc heeft en dit toestel niet kende — zonder radio op proef, versies of verhuisde oude bestanden',
        () {
      final oud = _t('Oud');
      final nieuw1 = _t('Nieuw 1', toegevoegd: _sinds + 1000);
      final nieuw2 = _t('Nieuw 2', toegevoegd: _sinds + 5000);
      final radio = _t('Van de radio');
      final versie = _t('Vinyl');
      final verhuisd = _t('Verhuisd naar (cd)', toegevoegd: DateTime(2025, 2, 26).millisecondsSinceEpoch);
      final uit = nieuweNummers(
        bibliotheek: [oud, nieuw1, radio, versie, verhuisd, nieuw2],
        bekend: {oud.path},
        sindsMs: _sinds,
        opProef: {'id-radio'},
        idVan: (p) => p == radio.path ? 'id-radio' : 'id-$p',
        isVersie: (p) => p == versie.path,
      );
      expect([for (final t in uit) t.title], ['Nieuw 2', 'Nieuw 1'], reason: 'het nieuwste eerst');
    });

    test('een bestand van vlak vóór het begin telt nog mee (een dag speling)', () {
      final net = _t('Net ervoor', toegevoegd: _sinds - 3600000);
      expect(nieuweNummers(bibliotheek: [net], bekend: const {}, sindsMs: _sinds), [net]);
    });
  });

  group('de grens', () {
    int omvang(Track t) => t.sizeBytes;

    test('wat er al om "nieuw" staat blijft altijd; van de rest wat past; de rest telt als niet meer', () {
      final al = _t('Al hier', bytes: 50);
      final a = _t('A', bytes: 30), b = _t('B', bytes: 30), c = _t('C', bytes: 10);
      final r = binnenGrens(nieuw: [al, a, b, c], al: {al.path}, bezet: 100, grens: 145, omvang: omvang);
      expect([for (final t in r.houden) t.title], ['Al hier', 'A', 'C'], reason: 'B past niet meer, C nog wel');
      expect(r.nietMeer, 1);
    });

    test('ruim genoeg: alles, en niets "niet meer"', () {
      final r = binnenGrens(nieuw: [_t('A', bytes: 30)], al: const {}, bezet: 0, grens: 150000000000, omvang: omvang);
      expect(r.houden, hasLength(1));
      expect(r.nietMeer, 0);
    });
  });

  group('wat dit toestel al kende', () {
    late Directory map;
    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_bekend_op_pc_');
      setAppDirForTest(map.path);
    });
    tearDown(() {
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('de eerste keer alles wat de pc nu heeft, één keer; wat je zelf weghaalt komt erbij; het overleeft een herstart',
        () async {
      final b = BekendOpPc(bestandsnaam: 'b.json');
      expect(await b.begin([_t('Een'), _t('Twee')], nu: DateTime.fromMillisecondsSinceEpoch(_sinds)), isTrue);
      expect(await b.begin([_t('Drie')]), isFalse, reason: 'niet opnieuw: anders is er nooit iets nieuw');
      await b.voegToe([_t('Zelf weggehaald').path]);
      final na = BekendOpPc(bestandsnaam: 'b.json');
      await na.laad();
      expect(na.sinds, _sinds);
      expect(na.paden, {_t('Een').path, _t('Twee').path, _t('Zelf weggehaald').path});
      expect(jsonDecode(File('${map.path}${Platform.pathSeparator}b.json').readAsStringSync()), isA<Map>());
    });

    test('zelf van het toestel gehaald: geen reden meer (ook niet "nieuw"), en het telt als gekend', () async {
      final p = _t('Weg').path;
      await toestelRedenen.voegToe([p], kRedenNieuw);
      await zelfVanToestel([p]);
      expect(toestelRedenen.redenenVan(p), isEmpty);
      expect(bekendOpPc.paden, contains(p), reason: 'anders komt hij bij de volgende ronde vanzelf terug');
    });
  });

  test('aangesloten: het bijhouden, de grens, betere kopieën, zelf weghalen, de pc en de deur naar buiten', () {
    String bron(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
    final main = bron('lib/main.dart');
    expect(main, contains('          gewenst[kRedenNieuw] = b.houden;\n'));
    expect(main, contains('        final r = await houdLijstenBij(redenen: toestelRedenen, offline: offline, gewenst: gewenst, geluidVan: geluidHier);\n'));
    expect(main, contains('                  libraryPath: o.path, title: t.title, artist: t.artist, album: t.album, geluid: g, vervang: true));\n'));
    expect(main, contains('    settings.addListener(houdBij);\n'));
    expect('zelfVanToestel('.allMatches(main), hasLength(4), reason: 'drie keer weghalen, en Alles weghalen');
    expect(main, contains('      s.radioOpProef = () => [for (final g in radio.opProef) g.pad];\n'));
    final server = bron('lib/lan/server.dart');
    expect(server, contains("      case '/api/radio/opproef':"));
    expect(server, contains("    '/api/radio/opproef',\n"), reason: 'ook van buitenaf: alleen id\'s');
    expect(kRedenNieuw, 'nieuw');
  });
}

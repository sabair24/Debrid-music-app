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

  group('wachten op de keuring van de pc (Saber, 02-11-2026: "Wachten tot de keuring af is")', () {
    const min = 60000;
    test('de eerste twee minuten altijd; daarna zolang de pc bezig is, maar nooit langer dan een halfuur', () {
      const nu = 100 * min;
      expect(wachtOpDePc(toegevoegdMs: nu - 1 * min, nuMs: nu, bezig: false), isTrue,
          reason: 'net geland: de pc keurt nog (de nep van Got My Mind Set On You werd na 15 s betrapt)');
      expect(wachtOpDePc(toegevoegdMs: nu - 3 * min, nuMs: nu, bezig: false), isFalse);
      expect(wachtOpDePc(toegevoegdMs: nu - 3 * min, nuMs: nu, bezig: true), isTrue, reason: 'de jacht loopt nog');
      expect(wachtOpDePc(toegevoegdMs: nu - 29 * min, nuMs: nu, bezig: true), isTrue);
      expect(wachtOpDePc(toegevoegdMs: nu - 30 * min, nuMs: nu, bezig: true), isFalse, reason: 'op zijn laatst na 30 min');
    });

    test('aangesloten: de pc zegt wat hij nog keurt, de gsm wacht, en wat al op de gsm staat blijft', () {
      String bron(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
      final online = bron('lib/online.dart');
      expect(online, contains('      if (ok && better.isNotEmpty) _queueUpgrade(better, job, behandeld: padVanWatErLigt);\n'));
      expect(online, contains('    if (pad != null) _jachtVoor[pad] = (_jachtVoor[pad] ?? 0) + 1;\n'));
      expect(online, contains('    _naLandenBezig.addAll(g.paden);\n'));
      expect(online, contains('      _naLandenBezig.removeAll(g.paden);\n'));
      final server = bron('lib/lan/server.dart');
      expect(server, contains("      case '/api/toestel/nogbezig':"));
      expect(server, contains("    '/api/toestel/nogbezig',\n"), reason: 'ook van buitenaf: alleen id\'s');
      final main = bron('lib/main.dart');
      expect(main, contains('          bezigOpPc = await (library.remote?.nogBezig() ?? Future.value(const <String>{}));\n'));
      expect(main, contains('              if (!alNieuw.contains(t.path) &&\n'
          '                  wachtOpDePc(toegevoegdMs: t.addedMs, nuMs: nuMs, bezig: bezigOpPc.contains(library.gedeeldId(t.path))))\n'));
      expect(main, contains('            nieuw.removeWhere((t) => wacht.contains(t.path));\n'));
      expect(main, contains('            } else if (o.geluid != g && bezigOpPc.contains(library.gedeeldId(o.path))) {\n'),
          reason: 'ook een betere kopie pas als de pc klaar is met zoeken');
    });
  });

  group('een betere kopie onderweg (Saber, 03-11-2026: "Pas thuis op wifi")', () {
    test('thuis op wifi altijd; onderweg alleen als wat hier staat echt slecht is', () {
      expect(beterNuOphalen(thuisOpWifi: true, oudGeluid: '44100/16/200000/flac'), isTrue);
      expect(beterNuOphalen(thuisOpWifi: false, oudGeluid: '44100/16/200000/flac'), isFalse,
          reason: 'een cd-kopie: de 24/96 van de pc wordt hier toch weer cd — wacht op wifi');
      expect(beterNuOphalen(thuisOpWifi: false, oudGeluid: '44100/0/200000/mp3'), isTrue, reason: 'een mp3: meteen');
      expect(beterNuOphalen(thuisOpWifi: false, oudGeluid: '22050/16/200000/flac'), isTrue, reason: 'onder cd: meteen');
      expect(beterNuOphalen(thuisOpWifi: false, oudGeluid: null), isTrue, reason: 'niets geweten: zoals vroeger');
    });

    test('aangesloten: de pass van de betere kopieën, de onzekere netsoort, en "thuis" na een netwerkwissel', () {
      String bron(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
      final main = bron('lib/main.dart');
      expect(main, contains('            } else if (o.geluid != g &&\n                !beterNuOphalen(\n'
          '                    thuisOpWifi: !netStore.onderweg && (!Platform.isAndroid || netStore.net == Netsoort.wifi),\n'));
      expect(main, contains('    netStore.addListener(houdBij);\n'), reason: 'thuis op wifi: wat wachtte, nu');
      expect(main, contains('        if (netOnzeker()) return;\n'), reason: 'vanzelf opslaan wacht op een bekende netsoort');
      expect(main, contains('    if (alleenHierNu() || netOnzeker()) return;\n'), reason: 'vooruithalen ook');
      expect(main, contains(
          '  bool netOnzeker() => !mode.owner && !isTv && Platform.isAndroid && netStore.net == Netsoort.onbekend;\n'));
      final sessie = bron('lib/lan/client_session.dart');
      final i = sessie.indexOf('  Future<void> netwerkVeranderd(String waarom) async {');
      expect(sessie.substring(i, i + 1600), contains('        _pcZegtThuis = null;\n'),
          reason: 'van de thuiswifi naar mobiel via dezelfde deur: niet meer thuis tot de pc het weer zegt');
    });
  });

  test('zoeken online op mobiele data: eerst op je gsm, dan spelen (Saber, 02-11-2026)', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(main, contains('    final opGsm = lib.remote != null && !isTv && _misschien<NetsoortStore>(context)?.net == Netsoort.mobiel\n'));
    expect(main, contains('        if (klaar || opGsm != null || !magNog()) return;\n'),
        reason: 'niet al laten klinken van de pc terwijl hij binnenkomt');
    final i = main.indexOf('        if (opGsm != null) {\n          final pad = t.path;\n');
    expect(i, greaterThan(0));
    expect(main.substring(i, i + 700), contains('if (!await opGsm.haalEnWacht(libraryPath: pad, title: t.title'));
    expect(i, lessThan(main.indexOf('        final klinkendAdres = vroeg?.adres ?? elders?.pad;\n')),
        reason: 'eerst op de gsm, pas dan spelen');
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

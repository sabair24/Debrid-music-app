// Het schudlogboek (Saber, 25-10-2026): "hou vanaf nu ook een log bij van alle shuffels die ik doe van de hele
// bibliotheek, dan kunnen we oordelen wat goed gaat en wat niet, of minder goed".
import 'dart:io';

import 'package:debridmusic/lan/server.dart' show weigerVanBuiten;
import 'package:debridmusic/models.dart';
import 'package:debridmusic/schudlog.dart';
import 'package:debridmusic/schudvolgorde.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

Track _t(int i, {String? artiest}) =>
    Track(path: 'p$i', title: 'Nummer $i', artist: artiest ?? 'Artiest ${i % 50}', album: 'A');

void main() {
  final bib = [for (var i = 0; i < 1000; i++) _t(i)];
  final nu = DateTime(2026, 10, 25, 11, 2, 13);
  late List<String> regels;
  late SchudLogboek log;

  setUp(() {
    regels = [];
    log = SchudLogboek(
      schrijf: regels.addAll,
      bibliotheek: () => bib.length,
      // De eerste 300 al eens gehoord, de rest nooit.
      speelstand: (t) {
        final i = int.parse(t.path.substring(1));
        return i < 300 ? Speelstand(aantal: 2, laatstMs: nu.subtract(const Duration(days: 3)).millisecondsSinceEpoch) : null;
      },
      klok: () => nu,
    );
  });

  test('DE KERN: een shuffle van de hele bibliotheek krijgt een kop met wat er in zit, en de eerste dertig', () {
    log.geschud(List.of(bib.reversed), hoe: 'Shuffle alles', generatie: 1);
    expect(regels, hasLength(2));
    final kop = regels.first;
    expect(kop, startsWith('SCHUD 25-10-2026 11:02:13 #'));
    expect(kop, contains('(Shuffle alles): 1000 van 1000 nummers in de bibliotheek'));
    expect(kop, contains('1000 verschillend, 0 dubbel'));
    expect(kop, contains('nooit gehoord 700 (in de eerste 100: 100)'), reason: 'achterstevoren: vooraan alleen nooit gehoorde');
    expect(kop, contains('eerste shuffle sinds de start'));
    expect(kop, contains('zelfde artiest direct na elkaar in de eerste 500: 0'));
    expect(regels[1], contains('eerste 30: 1. Artiest 49 — Nummer 999 [nooit] · 2. '));
    expect(RegExp(r'\d+\. ').allMatches(regels[1]).length, 30);
  });

  test('DE KERN: "niet altijd dezelfde" — hoeveel van de eerste honderd ook vooraan stonden bij de vorige', () {
    log.geschud(bib, hoe: 'Shuffle alles', generatie: 1);
    regels.clear();
    // Dezelfde eerste vijftig, daarna andere.
    final tweede = [...bib.take(50), ...bib.skip(500), ...bib.skip(50).take(450)];
    log.geschud(tweede, hoe: 'Shuffle alles', generatie: 2);
    expect(regels.firstWhere((r) => r.startsWith('SCHUD')),
        contains('van de eerste 100 stonden er 50 ook vooraan bij de vorige shuffle'));
  });

  test('dubbele vallen op', () {
    log.geschud([...bib.take(950), ...bib.take(50)], hoe: 'Shuffle alles', generatie: 1);
    expect(regels.first, contains('950 verschillend, 50 dubbel'));
  });

  test('DE GRENS: een album of artiest schudden komt er niet in — alleen de hele bibliotheek (90 %)', () {
    log.geschud(bib.take(899).toList(), hoe: 'Shuffle alles', generatie: 1);
    expect(regels, isEmpty);
    log.geschud(bib.take(900).toList(), hoe: 'Shuffle alles', generatie: 2);
    expect(regels, isNotEmpty);
  });

  test('DE KERN: per nummer gehoord of overgeslagen, en een slotregel bij de volgende shuffle', () {
    log.geschud(bib, hoe: 'Shuffle alles', generatie: 7);
    regels.clear();
    void voorbij(int plek, int sec, {int generatie = 7, bool shuffle = true}) => log.voorbij(bib[plek],
        plek: plek,
        lengte: 1000,
        shuffle: shuffle,
        generatie: generatie,
        geluisterd: Duration(seconds: sec),
        duur: const Duration(minutes: 4));
    voorbij(0, 240);
    voorbij(1, 12);
    voorbij(2, 130);
    expect(regels[0], endsWith(' 1/1000 Artiest 0 — Nummer 0: gehoord 4:00 van 4:00'));
    expect(regels[1], endsWith(' 2/1000 Artiest 1 — Nummer 1: overgeslagen na 0:12 van 4:00'));
    expect(regels[2], contains('gehoord 2:10'), reason: 'de helft, of twee minuten');
    // Niet van deze shuffle: een andere trekking, of shuffle uit.
    voorbij(3, 200, generatie: 6);
    voorbij(4, 200, shuffle: false);
    expect(regels, hasLength(3));
    log.geschud(List.of(bib.reversed), hoe: 'shuffle-knop', vanaf: 10, generatie: 8);
    expect(regels[3], contains('klaar: 3 nummers voorbij, 2 gehoord, 1 overgeslagen (33 %), 6 min geluisterd'));
    expect(regels[4], contains('(shuffle-knop): 1000 van 1000 nummers'));
    expect(regels[4], contains('de eerste 10 blijven staan'));
  });

  test('zelfde artiest direct na elkaar tellen', () {
    expect(zelfdeArtiestNaElkaar([_t(1, artiest: 'A'), _t(2, artiest: 'a'), _t(3, artiest: 'B'), _t(4, artiest: 'A')]), 1);
  });

  group('de zender van een toestel', () {
    testWidgets('bundelt, en houdt vast wat niet aankwam tot het wel lukt', (t) async {
      final aangekomen = <String>[];
      var pcWeg = true;
      final z = SchudZender((r) async {
        if (pcWeg) throw StateError('geen pc');
        aangekomen.addAll(r);
      });
      z.voegToe(['a', 'b']);
      z.voegToe(['c']);
      await t.pump(kSchudBundel);
      expect(aangekomen, isEmpty);
      expect(z.wachtend, 3, reason: 'bewaard');
      pcWeg = false;
      await t.pump(kSchudOpnieuw);
      expect(aangekomen, ['a', 'b', 'c']);
      expect(z.wachtend, 0);
      z.dispose();
    });

    // Saber, 26-10-2026: "Ik heb vandaag op de gsm verschillende keer gesnuffeld" — en schud.log stond stil sinds gisteren.
    testWidgets('wat niet aankwam overleeft een herstart van de app (op het toestel bewaard)', (t) async {
      final map = Directory.systemTemp.createTempSync('dm_schud_wacht_');
      addTearDown(() => map.deleteSync(recursive: true));
      final f = File('${map.path}${Platform.pathSeparator}schud_wacht.json');
      final eerste = SchudZender((_) async => throw StateError('onderweg: de deur weigerde'), bewaar: f);
      eerste.voegToe(['SCHUD 26-10-2026 09:12', '#abc 1/1769 Oasis — Wonderwall: gehoord 4:18 van 4:18']);
      await t.pump(kSchudBundel);
      eerste.dispose(); // de app gaat dicht
      expect(f.existsSync(), isTrue);
      final aangekomen = <String>[];
      final tweede = SchudZender((r) async => aangekomen.addAll(r), bewaar: f);
      expect(tweede.wachtend, 2, reason: 'opnieuw gestart: wat wachtte is er nog');
      await t.pump(kSchudBundel);
      expect(aangekomen, hasLength(2));
      expect(f.existsSync(), isFalse, reason: 'aangekomen = niets meer te bewaren');
      tweede.dispose();
    });

    test('de pc neemt het schudlogboek ook van buiten aan (onderweg schudt Saber ook)', () {
      expect(weigerVanBuiten('/api/diag/schud', 'POST'), isNull);
      expect(_bron('lib/main.dart'), contains("      }, bewaar: appFile('schud_wacht.json')).voegToe;"));
    });

    testWidgets('niet eindeloos: hoogstens $kSchudWachtrij regels', (t) async {
      final z = SchudZender((_) async => throw StateError('geen pc'));
      z.voegToe([for (var i = 0; i < kSchudWachtrij + 50; i++) '$i']);
      expect(z.wachtend, kSchudWachtrij);
      z.dispose();
    });
  });

  test('aangesloten: de speler meldt schudden en elk nummer, de pc schrijft alles in één schud.log', () {
    final speler = _bron('lib/player.dart');
    expect(speler, contains('      bijNummerVoorbij?.call(vorig,\n          plek: _telPlek,'));
    expect(speler, contains('    final generatie = ++_schudGeneratie;'));
    expect(speler, contains("    await _openCurrent();\n    bijSchudden?.call(shuffled, hoe: 'Shuffle alles', generatie: generatie);"));
    expect(speler, contains("      bijSchudden?.call(_order, hoe: 'shuffle-knop', vanaf: _index, generatie: _schudGeneratie);"));
    expect(speler, contains('    if (_geteld || !telMeeAlsGespeeld(geluisterd: _geluisterd, duur: duurErgens)) return;'),
        reason: 'na het meetellen door: hoe lang je echt luisterde');
    final telMee = speler.substring(speler.indexOf('  void _telMee(Duration nu) {'));
    expect(telMee.substring(0, 200), contains('    if (vorig == null) return;\n'),
        reason: 'niet stoppen met optellen zodra het meetelde');
    final main = _bron('lib/main.dart');
    expect(main, contains("          await c.ask('/api/diag/schud', {'toestel': warmteToestel(await ik), 'regels': regels});"));
    expect(main, contains('    player.bijSchudden = schudLog.geschud;\n    player.bijNummerVoorbij = schudLog.voorbij;'));
    expect(main, contains("final log = WarmLog('\$logDir\${Platform.pathSeparator}schud.log', maxBytes: kSchudLogBytes);"));
    final server = _bron('lib/lan/server.dart');
    expect(server, contains("      case '/api/diag/schud':\n        return _schud(req);"));
    expect(server, contains("schud.log', maxBytes: kSchudLogBytes);"));
  });
}

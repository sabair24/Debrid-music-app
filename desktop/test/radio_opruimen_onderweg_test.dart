// Onderweg opruimen (plan A4). Saber, 08-10-2026: wat geen groen krijgt gaat 20 nummers nadat het voorbij was weg — geen
// schijfplafond. 23-10-2026, op de vraag of "Past niet" dan ook meegaat: "Na 20 nummers, ook Past niet". Alleen wat je
// houdt blijft (Houden, favoriet, afspeellijst): dezelfde regel als het overzicht bij "Radio afsluiten".
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart' show setAppDirForTest;
import 'package:debridmusic/player.dart';
import 'package:debridmusic/radio.dart';
import 'package:debridmusic/radioladder.dart';
import 'package:debridmusic/radiovoorraad.dart' show Haalstand;

class _Speler implements PlayerStore {
  final rij = <RadioItem>[];
  int index = 0;

  @override
  Future<List<RadioItem>> Function()? radioExtend;
  @override
  void Function(List<RadioItem> gespeeld)? bijRadioEinde;
  @override
  void Function(RadioItem item, {required bool bestand})? bijRadioOverslaan;
  @override
  List<RadioItem> get radioQueue => rij;
  @override
  int get radioIndex => index;
  @override
  bool get playing => true;
  @override
  bool get radioDroog => false;
  @override
  bool get wilVerder => false;
  @override
  Duration duration = Duration.zero;
  @override
  Duration get positieErgens => Duration.zero;

  @override
  Future<void> playRadio(List<RadioItem> items, {int start = 0}) async {
    rij
      ..clear()
      ..addAll(items);
    index = 0;
  }

  @override
  void voegToeAanRadio(List<RadioItem> meer) => rij.addAll(meer);

  final uitDeRij = <String>[];

  @override
  Future<bool> haalUitRadio(String pad) async {
    uitDeRij.add(pad);
    // Zoals [PlayerStore.haalUitRadio]: het spelende nummer blijft het spelende, ook als er iets vóór weggaat.
    final hier = index < rij.length ? rij[index] : null;
    rij.removeWhere((r) => r.local?.path == pad);
    final terug = hier == null ? -1 : rij.indexOf(hier);
    index = terug >= 0 ? terug : rij.length - 1;
    return true;
  }

  @override
  void addListener(void Function() listener) {}
  @override
  void removeListener(void Function() listener) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bron implements Radiobron {
  _Bron(this.antwoord);
  final Track? Function(Radioplek p) antwoord;
  final weg = <String>[];
  bool lukt = true;

  @override
  Future<String?> begin() async => null;
  @override
  void einde() {}
  @override
  void staak() {}
  @override
  Future<Track?> haal(Radioplek p) async => antwoord(p);
  @override
  Future<bool> vergeet({required String pad, required String artiest, required String titel}) async {
    if (!lukt) return false;
    weg.add(titel);
    return true;
  }
}

Track _t(String titel) => Track(
    path: '${Directory.systemTemp.path}${Platform.pathSeparator}opruim - $titel.flac',
    title: titel,
    artist: 'Artiest $titel',
    album: '');

Future<void> _totAllesTerug(RadioBesturing r) async {
  for (var i = 0; i < 400; i++) {
    if (!r.plan.any((p) => p.stand == Haalstand.onderweg || p.stand == Haalstand.wacht)) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    r.tikVoorToets();
  }
}

Opruimplek _p(String? pad, {bool door = true, bool zaad = false, bool reserve = false, int? voorbij}) =>
    (pad: pad, doorRadio: door, zaad: zaad, reserve: reserve, voorbijOp: voorbij);

void main() {
  group('de regel', () {
    bool nooit(String _) => false;

    test('DE KERN: twintig voorbij en niet gehouden — weg; negentien niet', () {
      expect(teOpruimen([_p('a', voorbij: 1), _p('b', voorbij: 2)], voorbijteller: 21, rijVanaf: {}, houdt: nooit), ['a']);
      expect(kOpruimNa, 20);
    });

    test('wat je houdt, het zaad, de reserve en wat niet van de radio is blijven', () {
      expect(teOpruimen([_p('a', voorbij: 1)], voorbijteller: 50, rijVanaf: {}, houdt: (p) => p == 'a'), isEmpty);
      expect(teOpruimen([_p('a', voorbij: 1, zaad: true)], voorbijteller: 50, rijVanaf: {}, houdt: nooit), isEmpty);
      expect(teOpruimen([_p('a', voorbij: 1, reserve: true)], voorbijteller: 50, rijVanaf: {}, houdt: nooit), isEmpty);
      expect(teOpruimen([_p('a', voorbij: 1, door: false)], voorbijteller: 50, rijVanaf: {}, houdt: nooit), isEmpty);
      expect(teOpruimen([_p(null, voorbij: 1)], voorbijteller: 50, rijVanaf: {}, houdt: nooit), isEmpty);
    });

    test('een herhaling die nog moet komen houdt het bestand vast; het spelende en wat komt ook', () {
      expect(teOpruimen([_p('a', voorbij: 1), _p('a')], voorbijteller: 50, rijVanaf: {}, houdt: nooit), isEmpty,
          reason: 'dezelfde opname staat nog eens in het plan, en die is nog niet voorbij');
      expect(teOpruimen([_p('a', voorbij: 1), _p('a', voorbij: 40)], voorbijteller: 50, rijVanaf: {}, houdt: nooit),
          isEmpty, reason: 'het LAATSTE exemplaar telt');
      expect(teOpruimen([_p('a', voorbij: 1)], voorbijteller: 50, rijVanaf: {'a'}, houdt: nooit), isEmpty);
      expect(teOpruimen([_p('a', voorbij: 1)], voorbijteller: 50, rijVanaf: {}, houdt: nooit, bezig: {'a'}), isEmpty);
    });

    test('hoogstens een bundel van vijf per keer', () {
      final plan = [for (var i = 0; i < 9; i++) _p('p$i', voorbij: 1)];
      expect(teOpruimen(plan, voorbijteller: 30, rijVanaf: {}, houdt: nooit), hasLength(kOpruimBundel));
    });
  });

  group('in de radio', () {
    late Directory wortel;
    setUp(() {
      wortel = Directory.systemTemp.createTempSync('dm_opruim_');
      setAppDirForTest(wortel.path);
    });
    tearDown(() {
      try {
        wortel.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<({RadioBesturing r, _Speler s, _Bron b, Map<String, Track> t})> maak({bool aan = true}) async {
      final tracks = {for (var i = 1; i <= 30; i++) '$i': _t('$i')};
      final s = _Speler();
      final b = _Bron((p) => tracks[p.titel]);
      final r = RadioBesturing(speler: s, bron: b)
        ..opruimenOnderweg = (() => aan)
        ..houdt = ((pad) => pad == tracks['2']!.path);
      await r.start([
        Radioplek(artiest: 'Zaad', titel: 'Zaad', eigen: _t('zaad'), zaad: true),
        for (var i = 1; i <= 30; i++) Radioplek(artiest: 'Artiest $i', titel: '$i'),
      ]);
      await _totAllesTerug(r);
      return (r: r, s: s, b: b, t: tracks);
    }

    Future<void> speelDoor(RadioBesturing r, _Speler s, int stappen) async {
      for (var i = 0; i < stappen; i++) {
        if (s.index + 1 < s.rij.length) s.index++;
        r.tikVoorToets();
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    test('DE KERN: twintig nummers later naar de prullenbak — niet wat je hield, niet het zaad, niet wat komt', () async {
      final m = await maak();
      addTearDown(m.r.stop);
      final eerste = m.s.rij.map((it) => it.local?.title).take(3).toList();
      expect(eerste.first, 'zaad');
      await speelDoor(m.r, m.s, 19);
      expect(m.b.weg, isEmpty, reason: 'nog geen twintig voorbij');
      await speelDoor(m.r, m.s, 3);
      expect(m.b.weg, isNotEmpty);
      // Verder, tot ook 2 en 3 ruim twintig voorbij zijn: anders zegt "2 blijft" niets.
      await speelDoor(m.r, m.s, 4);
      expect(m.b.weg, contains('3'), reason: 'zijn buurman, net zo lang voorbij, ging wel');
      expect(m.b.weg, isNot(contains('2')), reason: 'Houden blijft altijd');
      expect(m.b.weg, isNot(contains('zaad')));
      expect(m.b.weg.first, '1');
      expect(m.s.uitDeRij, contains(m.t['1']!.path), reason: 'ook uit de rij — op een speaker uit die van de speaker');
      expect(m.r.doorDezeRadio(m.t['1']!.path), isFalse);
      expect(m.r.opgeruimd, m.b.weg.length);
      final spelend = m.s.rij[m.s.index].local!.path;
      expect([for (final t in m.b.weg) m.t[t]?.path], isNot(contains(spelend)));
      m.r.stop();
      expect([for (final g in m.r.openstaand?.gehaald ?? const []) g.pad], isNot(contains(m.t['1']!.path)),
          reason: 'wat al weg is, staat niet meer in het overzicht');
    });

    test('lukt de prullenbak niet, dan blijft het voor het overzicht', () async {
      final m = await maak();
      addTearDown(m.r.stop);
      m.b.lukt = false;
      await speelDoor(m.r, m.s, 23);
      expect(m.r.opgeruimd, 0);
      expect(m.r.doorDezeRadio(m.t['1']!.path), isTrue);
      m.r.stop();
      expect([for (final g in m.r.openstaand!.gehaald) g.pad], contains(m.t['1']!.path));
    });

    test('waar het niet mag (tv, geen prullenbak), gebeurt er niets', () async {
      final m = await maak(aan: false);
      addTearDown(m.r.stop);
      await speelDoor(m.r, m.s, 25);
      expect(m.b.weg, isEmpty);
    });
  });

  test('aangesloten: de regel van het overzicht, niet op tv, en de zin in het paneel', () {
    final m = File('lib/main.dart').readAsStringSync();
    expect(m, contains('if (oordelen.vanTrack(t) == Oordeel.omhoog || favorieten.isFavorietTrack(t)) return true;'));
    expect(m, contains('return id != null && lijsten.lijsten.any((l) => l.trackIds.contains(id));'));
    expect(m, contains('radio.opruimenOnderweg = () => !isTv && (library.isRemote || heeftPrullenbak);'));
    expect(m, contains("'Wat je niet houdt, gaat \$kOpruimNa nummers later naar de prullenbak"));
    final r = File('lib/radio.dart').readAsStringSync();
    expect(r, contains('    _stempel();\n    _ruimOnderwegOp(sessie);'));
    expect(r, contains('if (herhaald != null && _klok().difference(herhaald) < kOpruimNaHerhaling) return;'));
  });
}

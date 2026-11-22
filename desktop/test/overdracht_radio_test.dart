/// Een radio die naar een andere zone gaat, speelt niet ook hier verder (Saber, 22-11-2026, van de Mac naar de tv in de
/// woonkamer: *"dan stopt hij niet op mac, en spelen ze beide, dat mag niet"*).
///
/// Gemeten in zones.log van de pc: om 10:59:32 de overdracht ("radio rond Tamino"), om 10:59:45 de opdracht 'verplaatst'
/// naar de Mac, en om 11:00:04 drukte Saber zelf op stop. In radio.log vroeg de radio van de Mac om 10:59:56 nog het
/// model om raad: hij liep door, en een nummer dat binnenkwam kon de muziek weer aanzetten.
library;

import 'dart:io';

import 'package:debridmusic/main.dart' show radioNaOvername;
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/radio.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

/// Alleen wat de radio van de speler gebruikt, en of hij de radio verliet.
class _Speler implements PlayerStore {
  final rij = <RadioItem>[];
  var verlaten = false;

  @override
  Future<List<RadioItem>> Function()? radioExtend;
  @override
  void Function(List<RadioItem> gespeeld)? bijRadioEinde;
  @override
  void Function(RadioItem item, {required bool bestand})? bijRadioOverslaan;
  @override
  bool get playing => true;
  @override
  bool get radioDroog => false;
  @override
  bool get wilVerder => false;
  @override
  List<RadioItem> get radioQueue => rij;
  @override
  int get radioIndex => 0;
  @override
  Duration duration = Duration.zero;
  @override
  Duration get positieErgens => Duration.zero;
  @override
  Future<void> playRadio(List<RadioItem> items, {int start = 0}) async {
    rij
      ..clear()
      ..addAll(items);
  }

  @override
  void voegToeAanRadio(List<RadioItem> meer) => rij.addAll(meer);
  @override
  Future<bool> haalUitRadio(String pad) async => true;
  @override
  bool vervangInRadio(RadioItem oud, RadioItem? nieuw) => false;
  @override
  Future<void> verlaatRadio() async => verlaten = true;
  @override
  void addListener(void Function() listener) {}
  @override
  void removeListener(void Function() listener) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bron implements Radiobron {
  @override
  Future<String?> begin() async => null;
  @override
  void einde() {}
  @override
  void staak() {}
  @override
  Future<Track?> haal(Radioplek p) async => null;
  @override
  Future<bool> vergeet({required String pad, required String artiest, required String titel}) async => true;
}

Track _t(String titel) => Track(
    path: '${Directory.systemTemp.path}${Platform.pathSeparator}$titel.flac', title: titel, artist: 'Tamino', album: '');

void main() {
  late Directory wortel;
  setUp(() {
    wortel = Directory.systemTemp.createTempSync('dm_overdracht_');
    setAppDirForTest(wortel.path);
  });
  tearDown(() {
    try {
      wortel.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> start(RadioBesturing radio, {Radiospeler? naar}) => radio.start([
        Radioplek(artiest: 'Tamino', titel: 'Indigo Night', eigen: _t('Indigo Night'), zaad: true),
        Radioplek(artiest: 'Tamino', titel: 'Habibi'),
      ], naar: naar);

  test('DE KERN: de muziek ging naar een andere zone — de radio hier gaat dicht, en de speler verlaat hem', () async {
    final speler = _Speler();
    final radio = RadioBesturing(speler: speler, bron: _Bron());
    addTearDown(radio.stop);
    await start(radio);
    expect(radio.loopt, isTrue);
    expect(radioNaOvername(radio, speler), isTrue);
    expect(radio.loopt, isFalse, reason: 'geen radio die hier doorhaalt');
    expect(speler.verlaten, isTrue, reason: 'een nummer dat nog landt, zet de muziek niet meer aan');
  });

  test('zonder radio hier: niets te doen', () {
    final speler = _Speler();
    final radio = RadioBesturing(speler: speler, bron: _Bron());
    expect(radioNaOvername(radio, speler), isFalse);
    expect(speler.verlaten, isFalse);
  });

  test('een radio die de pc op een speaker draait, hoort bij die speaker: die blijft', () async {
    final speler = _Speler();
    final radio = RadioBesturing(speler: speler, bron: _Bron());
    addTearDown(radio.stop);
    await start(radio, naar: _Speler());
    expect(radio.opAndereUitgang, isTrue);
    expect(radioNaOvername(radio, speler), isFalse);
    expect(radio.loopt, isTrue);
  });

  test('aangesloten: bij elke overname en elke verplaatsing, en een pauze tijdens het openen telt', () {
    final m = _bron('lib/main.dart');
    expect(m, contains('  verder.bijOvername = (id) {\n'
        '    // Een radio die hier speelde, ging mee: hier dicht, niet alleen gepauzeerd ([radioNaOvername]).\n'
        '    radioNaOvername(radio, player);'));
    expect(m, contains('    verplaatst: (_) => verder.isVerplaatst(),'));
    final v = _bron('lib/verder_luisteren.dart');
    expect(v, contains('    bron.pauzeer();\n    bijOvername?.call(null);'), reason: 'verplaatst gaat langs dezelfde haak');
    final p = _bron('lib/player.dart');
    expect(p, contains('    _wilVerder = false;\n'
        '    // En niet als er net een radionummer opent: dan is [playing] nog onwaar en deed de pauze niets ([_pauzeGen]).\n'
        '    _pauzeGen++;'));
    expect(p, contains('        final pauze = _pauzeGen;\n        await _player.open(Media(bron), play: true);'));
    expect(p, contains('        if (pauze != _pauzeGen || !radioMode) {\n          if (gen == _radioGen) await _player.pause();'));
    expect(p, contains('    if (!radioMode) return;\n    _pauzeGen++;\n    radioMode = false;'));
  });
}

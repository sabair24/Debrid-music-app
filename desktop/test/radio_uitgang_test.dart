/// De radio kiest bij elke start zijn uitgang (Saber, 22-10-2026: radio op een speaker — "pc draait, speaker
/// speelt"): de speler van dit toestel, of een speaker die de pc stuurt.
///
/// Wat hier vastligt: zonder uitgang speelt hij waar hij altijd speelde; met een uitgang daar, en de vorige
/// uitgang valt stil (één radio tegelijk); terug naar dit toestel laat de speaker stilvallen; de haken
/// (einde, overslaan) hangen aan de uitgang die speelt, niet meer aan de vorige.
library;

import 'dart:io';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/radio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een uitgang die opschrijft wat de radio vraagt.
class _Uitgang extends ChangeNotifier implements Radiospeler {
  _Uitgang(this.naam);
  final String naam;
  final rij = <RadioItem>[];
  final log = <String>[];

  @override
  Future<List<RadioItem>> Function()? radioExtend;
  @override
  void Function(List<RadioItem> gespeeld)? bijRadioEinde;
  @override
  void Function(RadioItem item, {required bool bestand})? bijRadioOverslaan;
  @override
  bool get playing => false;
  @override
  bool get radioDroog => false;
  @override
  bool get wilVerder => false;
  @override
  List<RadioItem> get radioQueue => rij;
  @override
  int get radioIndex => 0;
  @override
  Duration get duration => Duration.zero;
  @override
  Duration get positieErgens => Duration.zero;

  @override
  Future<void> playRadio(List<RadioItem> items, {int start = 0}) async {
    log.add('playRadio ${items.map((i) => i.title).join(',')}');
    rij
      ..clear()
      ..addAll(items);
  }

  @override
  void voegToeAanRadio(List<RadioItem> meer) => rij.addAll(meer);
  @override
  Future<bool> haalUitRadio(String pad) async => false;
  @override
  RadioItem? wordtLokaalInRadio(RadioItem oud, Track t) => null;
  @override
  Future<void> verlaatRadio() async => log.add('verlaatRadio');
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

Track _t(String titel) =>
    Track(path: '${Directory.systemTemp.path}${Platform.pathSeparator}$titel.flac', title: titel, artist: titel, album: '');

void main() {
  late Directory wortel;
  setUp(() {
    wortel = Directory.systemTemp.createTempSync('dm_uitgang_');
    setAppDirForTest(wortel.path);
  });
  tearDown(() {
    try {
      wortel.deleteSync(recursive: true);
    } catch (_) {}
  });

  List<Radioplek> plan() => [Radioplek(artiest: 'Corona', titel: 'Rhythm', eigen: _t('Rhythm'))];

  test('zonder uitgang speelt hij op dit toestel; met een uitgang daar, en dit toestel valt stil', () async {
    final hier = _Uitgang('pc'), move = _Uitgang('Move');
    final radio = RadioBesturing(speler: hier, bron: _Bron());
    addTearDown(radio.stop);

    await radio.start(plan());
    expect(hier.log, ['playRadio Rhythm']);
    expect(radio.opAndereUitgang, isFalse);
    expect(hier.bijRadioEinde, isNotNull);

    await radio.start(plan(), naar: move);
    expect(move.log, ['playRadio Rhythm']);
    expect(hier.log, ['playRadio Rhythm', 'verlaatRadio'], reason: 'één radio tegelijk');
    expect(radio.opAndereUitgang, isTrue);
    expect(identical(radio.speler, move), isTrue);
    expect(move.bijRadioEinde, isNotNull, reason: 'de haken hangen aan de uitgang die speelt');
    expect(hier.bijRadioEinde, isNull);
    expect(hier.bijRadioOverslaan, isNull);

    // Nog een radio op dezelfde speaker: geen wissel, gewoon opnieuw.
    await radio.start(plan(), naar: move);
    expect(move.log, ['playRadio Rhythm', 'playRadio Rhythm']);
    expect(hier.log.where((r) => r == 'verlaatRadio').length, 1);

    // Terug naar dit toestel: de speaker valt stil.
    await radio.start(plan());
    expect(move.log.last, 'verlaatRadio');
    expect(hier.log.last, 'playRadio Rhythm');
    expect(radio.opAndereUitgang, isFalse);
  });

  test('het einde van de radio op de speaker stopt de radio, niet een einde op de oude uitgang', () async {
    final hier = _Uitgang('pc'), move = _Uitgang('Move');
    final radio = RadioBesturing(speler: hier, bron: _Bron());
    addTearDown(radio.stop);
    await radio.start(plan(), naar: move);
    expect(radio.loopt, isTrue);
    move.bijRadioEinde!(const []);
    expect(radio.loopt, isFalse);
  });
}

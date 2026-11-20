/// De verbeteringen na de radiometing van 20-11-2026 (radio Cher op de Shield, 78 minuten live gevolgd).
///
/// Saber: *"Ok nu doe alle verbeteringen, morgen doen we een nieuwe radio sessie."* Gemeten: de zoekrem was de rem (101
/// keer gewacht, tot 583 s), met loos verbruik — zoektochten voor nummers die al binnen waren, en de 24bit-jacht die
/// doorliep; 170 744 geweigerde binnenkomende verbindingen; "Radio afsluiten" liet de muziek doorspelen; en geen knop om
/// een radionummer meteen te houden als de radio op een ander toestel speelt.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/discogs.dart' show kunstUitBytes;
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/radio.dart';

import 'package:debridmusic/soulseek.dart';
import 'package:debridmusic/zone_opdracht.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

class _Speler implements PlayerStore {
  final rij = <RadioItem>[];
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
  Duration duration = Duration.zero;
  @override
  Duration get positieErgens => Duration.zero;
  @override
  Future<void> playRadio(List<RadioItem> items, {int start = 0}) async => rij
    ..clear()
    ..addAll(items);
  @override
  void voegToeAanRadio(List<RadioItem> meer) => rij.addAll(meer);
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
  @override
  Future<String?> begin() async => null;
  @override
  void einde() {}
  @override
  void staak() {}
  @override
  Future<Track?> haal(Radioplek p) async => antwoord(p);
  @override
  Future<bool> vergeet({required String pad, required String artiest, required String titel}) async => true;
}

void main() {
  group('verbindingen sneller dicht', () {
    test('DE KERN: een zoekantwoord (code 9) herkennen, en niets anders', () {
      expect(isZoekantwoord(Uint8List.fromList([9, 0, 0, 0, 1, 2])), isTrue);
      expect(isZoekantwoord(Uint8List.fromList([9, 0, 0, 1])), isFalse, reason: 'code 16777225, geen 9');
      expect(isZoekantwoord(Uint8List.fromList([4, 0, 0, 0])), isFalse);
      expect(isZoekantwoord(Uint8List.fromList([9, 0])), isFalse, reason: 'te kort');
      expect(kInitGeduld, const Duration(seconds: 10));
    });

    test('na een zoekantwoord gaat de verbinding meteen dicht', () {
      final s = _bron('lib/soulseek.dart');
      expect(s, contains('        owner._onFramed(payload);\n'
          '        // Een zoekantwoord is af ([isZoekantwoord])'));
      expect(s, contains('        if (isZoekantwoord(payload)) {\n          _drop();\n          return;\n        }'));
      expect(s, contains('    _bump(alleenVerwacht ? kBovenGrensKijktijd : kInitGeduld);'));
    });
  });

  group('zoekbudget', () {
    test('de varianten van een radiohaal vervallen als het nummer binnen is', () {
      final o = _bron('lib/online.dart');
      expect(o, contains('        nogNodig: _radiohalen.contains(job) ? () => _radiohalen.contains(job) && !job.cancelled : null,'));
    });

    test('de blijvende jacht wacht zolang er een radio loopt, en laat proefnummers van elders liggen', () {
      final m = _bron('lib/main.dart');
      expect(m, contains('        kan: () => downloads.kanBlijvendJagen && !radio.loopt && '
          '!(sharing.server?.radiohaler.inGebruik ?? false),'));
      expect(m, contains('            (sharing.server?.state.radioOpProefIds.contains(library.gedeeldId(t.path)) ?? false) ||'));
      expect(_bron('lib/lan/radiohaler.dart'), contains('  bool get inGebruik => _los != null;'));
    });

    test('de proeflijst van de pc wordt één keer uitgerekend, en volgt elke verandering', () async {
      final map = Directory.systemTemp.createTempSync('dm_na_meting_');
      final staat = LanStateStore(File('${map.path}${Platform.pathSeparator}state.json'));
      addTearDown(() async {
        await staat.dispose();
        try {
          map.deleteSync(recursive: true);
        } catch (_) {}
      });
      staat.applyOps([
        {'type': 'radioOpProef', 'ids': ['a']}
      ], deviceId: 'shield');
      final eerst = staat.radioOpProefIds;
      expect(identical(staat.radioOpProefIds, eerst), isTrue, reason: 'niet per nummer van de jacht opnieuw');
      staat.applyOps([
        {'type': 'radioOpProef', 'ids': ['b']}
      ], deviceId: 'shield');
      expect(staat.radioOpProefIds, {'b'});
      staat.applyOps([
        {'type': 'radioOpProef', 'ids': <String>[]}
      ], deviceId: 'shield');
      expect(staat.radioOpProefIds, isEmpty);
    });
  });

  group('houden', () {
    late Directory wortel;
    setUp(() {
      wortel = Directory.systemTemp.createTempSync('dm_houden_');
      setAppDirForTest(wortel.path);
    });
    tearDown(() {
      try {
        wortel.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('DE KERN: wat je hield, staat niet meer op proef — en mag dus naar de gsm', () async {
      final t = Track(path: '${wortel.path}${Platform.pathSeparator}stardust.flac', title: 'Music Sounds Better', artist: 'Stardust', album: '');
      final radio = RadioBesturing(speler: _Speler(), bron: _Bron((_) => t));
      addTearDown(radio.stop);
      radio.idVanPad = (p) => 'id-stardust';
      await radio.start([Radioplek(artiest: 'Stardust', titel: 'Music Sounds Better')]);
      for (var i = 0; i < 100 && radio.opProef.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect([for (final g in radio.opProef) g.pad], [t.path], reason: 'net gehaald: op proef');
      var gehouden = false;
      radio.gehouden = (p) => gehouden && p == t.path;
      gehouden = true;
      expect(radio.opProef, isEmpty, reason: 'gehouden: niet meer op proef');
    });

    test('een oordeel van een ander toestel bereikt de radio hier', () async {
      final s = _Speler();
      final ontvangen = <(String, String)>[];
      final u = ZoneUitvoerder(
          speler: s,
          rij: s,
          nummer: (_) => null,
          radioOordeel: (wat, id) async {
            ontvangen.add((wat, id));
            return null;
          });
      expect(await u.voerUit({'cmd': 'radioOordeel', 'wat': 'houden', 'trackId': 'stardust'}), isNull);
      expect(ontvangen, [('houden', 'stardust')]);
      final zonder = ZoneUitvoerder(speler: s, rij: s, nummer: (_) => null);
      expect(await zonder.voerUit({'cmd': 'radioOordeel', 'wat': 'houden', 'trackId': 'x'}), 'Hier kan dat niet');
    });

    test('de knop staat op Nu speelt, voor de radio hier en die van een zone, en draait niet om', () {
      final m = _bron('lib/main.dart');
      expect(m, contains('      if (t != null) _HoudenKnop(track: t, naast: zij),'));
      expect(m, contains("        houd = () => zone.radioOordeel('houden');"));
      expect(m, contains('      houd = () => radioHoudenVast(oordelen, lib, dm, t);'));
      expect(m, contains('  if (oordelen.vanTrack(t) == Oordeel.omhoog) return;\n  await radioHouden(oordelen, lib, dm, t);'));
      expect(m, contains("      if (wat != 'houden') return 'Dat kan alleen op het toestel zelf';"));
    });

    test('houden of favoriet maken wordt meteen aan de pc gemeld', () {
      final m = _bron('lib/main.dart');
      expect(m, contains('      oordelen.addListener(() => unawaited(meldOpProef()));'));
      expect(m, contains('      favorieten.addListener(() => unawaited(meldOpProef()));'));
      expect(m, contains('    return t != null && (oordelen.vanTrack(t) == Oordeel.omhoog || favorieten.isFavorietTrack(t));'),
          reason: 'onbekend is niet gehouden');
    });
  });

  test('"Radio afsluiten" stopt ook de muziek — op elke knop, en op afstand', () {
    final m = _bron('lib/main.dart');
    expect(m, contains('  if (radio.loopt) radio.stop(naar: naar);\n  unawaited(speler.verlaatRadio());'));
    expect('radioAfsluiten('.allMatches(m).length, 4, reason: 'de functie, twee knoppen en de opdracht van een zone');
    expect(m, contains('    radioStop: ({door}) => radioAfsluiten(radio, player, naar: door),'));
  });

  group('de Shield hapert niet bij een landing', () {
    test('DE KERN: de scans van de pc buiten de UI-draad omzetten — en wat stuk is, is niets', () {
      final body = Uint8List.fromList(utf8.encode(jsonEncode({'front': base64Encode([1, 2, 3]), 'klaar': true})));
      final k = kunstUitBytes(body);
      expect(k?.art.front, [1, 2, 3]);
      expect(k?.klaar, isTrue);
      expect(kunstUitBytes(Uint8List.fromList([0x7b, 0x22])), isNull, reason: 'half antwoord');
      final m = _bron('lib/main.dart');
      expect(m, contains('      return body == null ? null : compute(kunstUitBytes, body);'));
    });

    test('de index van je bibliotheek voor het radioplan wordt bewaard, en volgt elke wijziging', () {
      final m = _bron('lib/main.dart');
      expect(m, contains('  final index = _radioIndexVoor(lib);'));
      expect(m, contains('  final stand = (lib, lib.standVersie, lib.tracks.length);\n  if (stand == _radioIndexVan) return _radioIndex;'));
      expect(_bron('lib/library.dart'), contains('  void notifyListeners() {\n    _standVersie++;'));
    });
  });
}

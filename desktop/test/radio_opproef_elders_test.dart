/// Radionummers op proef van een radio op een ánder toestel gaan niet vanzelf naar de gsm (20-11-2026).
///
/// Saber, met TiK ToK "Op dit toestel · 25 MB" op zijn gsm terwijl de radio op de Shield liep: *"Kan het zijn dat hij
/// de nummers opslaat op men gsm ?? Dat mag niet e voor de nummers die ik nog niet heb in men bibliotheek. Enkel na men
/// beslissing als ik ze hou of niet"*. De pc kende alleen de proefnummers van zijn eigen radio.
library;

import 'dart:io';

import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/nieuw_op_toestel.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  late Directory map;
  late LanStateStore staat;
  setUp(() {
    map = Directory.systemTemp.createTempSync('dm_opproef_');
    staat = LanStateStore(File('${map.path}${Platform.pathSeparator}state.json'));
  });
  tearDown(() async {
    await staat.dispose();
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('DE KERN: wat de radio op een toestel op proef heeft, kent de pc — van elk toestel', () {
    staat.applyOps([
      {'type': 'radioOpProef', 'ids': ['tiktok', 'barbie']}
    ], deviceId: 'shield');
    staat.applyOps([
      {'type': 'radioOpProef', 'ids': ['crush']}
    ], deviceId: 'mac');
    expect(staat.radioOpProefIds, {'tiktok', 'barbie', 'crush'});
  });

  test('een nieuwe melding vervangt de vorige; leeg = niets meer op proef', () {
    staat.applyOps([
      {'type': 'radioOpProef', 'ids': ['tiktok', 'barbie']}
    ], deviceId: 'shield');
    staat.applyOps([
      {'type': 'radioOpProef', 'ids': ['barbie']}
    ], deviceId: 'shield');
    expect(staat.radioOpProefIds, {'barbie'}, reason: 'TiK ToK gehouden: dan mag het naar de gsm');
    staat.applyOps([
      {'type': 'radioOpProef', 'ids': <String>[]}
    ], deviceId: 'shield');
    expect(staat.radioOpProefIds, isEmpty);
  });

  test('geen nieuwe staat voor de toestellen bij elke landing, wel op schijf', () async {
    final rev = staat.rev;
    staat.applyOps([
      {'type': 'radioOpProef', 'ids': ['tiktok']}
    ], deviceId: 'shield');
    expect(staat.rev, rev, reason: 'anders haalt elk toestel bij elke landing de hele staat opnieuw');
    // Het uitgestelde wegschrijven (twee seconden), zoals in het echt — niet met de hand.
    await Future<void>.delayed(const Duration(milliseconds: 2600));
    final terug = LanStateStore(File('${map.path}${Platform.pathSeparator}state.json'));
    await terug.load();
    expect(terug.radioOpProefIds, {'tiktok'}, reason: 'een herstart van de pc vergeet het niet');
    await terug.dispose();
  });

  test('zonder toestel-id telt het niet', () {
    staat.applyOps([
      {'type': 'radioOpProef', 'ids': ['tiktok']}
    ]);
    expect(staat.radioOpProefIds, isEmpty);
  });

  test('en de gsm laat wat op proef is liggen', () {
    final nu = DateTime.now().millisecondsSinceEpoch;
    Track t(String id) => Track(path: '/m/$id.flac', title: id, artist: 'a', album: 'b', addedMs: nu);
    final nieuw = nieuweNummers(
        bibliotheek: [t('tiktok'), t('gewoon')],
        bekend: const {},
        sindsMs: nu - 1000,
        opProef: {'tiktok'},
        idVan: (p) => p.split('/').last.split('.').first,
        isVersie: (_) => false);
    expect([for (final x in nieuw) x.title], ['gewoon']);
  });

  group('aangesloten', () {
    test('de pc geeft de proefnummers van elk toestel door', () {
      final s = _bron('lib/lan/server.dart');
      expect(s, contains('            ...state.radioOpProefIds,'));
    });

    test('een toestel meldt wat zijn radio op proef heeft', () {
      final m = _bron('lib/main.dart');
      expect(m, contains("            {'type': 'radioOpProef', 'ids': ids}"));
      expect(m, contains('      radio.addListener(() => unawaited(meldOpProef()));'));
    });
  });
}

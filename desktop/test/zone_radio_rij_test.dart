/// De radio van een zone op afstand, zichtbaar op een ander toestel (20-11-2026).
///
/// Saber, met een radio op de Shield en de gsm als afstandsbediening: *"Oei begint al goed, hij laadt niets ?????"* en
/// *"ik zie wat er speelt op shield maar niet de wachtrij"*. De Shield had tien nummers klaarstaan, maar een radio meldde
/// alleen het spelende nummer als rij — de gsm kon niets anders tonen.
library;

import 'dart:io';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/zone_opdracht.dart';
import 'package:flutter_test/flutter_test.dart';

Track _t(String naam) => Track(path: naam, title: naam, artist: 'Artiest $naam', album: '');
RadioItem _i(String naam, {bool voorstel = false}) =>
    RadioItem(artist: 'Artiest $naam', title: naam, local: voorstel ? null : _t(naam), voorstel: voorstel);

/// Alleen wat de uitvoerder van de speler gebruikt.
class _Speler implements PlayerStore {
  _Speler(this.radioQueue, this.radioIndex);

  @override
  bool radioMode = true;
  @override
  final List<RadioItem> radioQueue;
  @override
  int radioIndex;
  final inRadio = <int>[];
  final gewoon = <int>[];

  @override
  Future<void> springInRadio(int plek) async => inRadio.add(plek);
  @override
  Future<void> springNaar(int plek) async => gewoon.add(plek);
  @override
  List<Track> get queueTracks => [_t('W1'), _t('W2'), _t('W3')];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('wat een radio als rij meldt', () {
    test('DE KERN: de hele radio, met de plek van het spelende nummer — zonder voorstellen', () {
      final m = radioMelding([_i('A'), _i('V', voorstel: true), _i('B'), _i('C')], 2);
      expect([for (final t in m.rij) t.title], ['A', 'B', 'C']);
      expect(m.index, 1, reason: 'B speelt');
    });

    test('staat de radio droog op een voorstel, dan op het laatste nummer ervoor', () {
      final m = radioMelding([_i('A'), _i('B'), _i('V', voorstel: true)], 2);
      expect(m.index, 1);
      final leeg = radioMelding(const [], -1);
      expect(leeg.rij, isEmpty);
      expect(leeg.index, 0);
    });

    test('en terug: de gemelde plek wordt de plek in de radio', () {
      final radio = [_i('A'), _i('V', voorstel: true), _i('B'), _i('C')];
      expect(radioPlekUitMelding(radio, 0), 0);
      expect(radioPlekUitMelding(radio, 1), 2);
      expect(radioPlekUitMelding(radio, 2), 3);
      expect(radioPlekUitMelding(radio, 3), -1);
    });
  });

  group('een tik op een ander toestel', () {
    ZoneUitvoerder uitvoerder(_Speler s) =>
        ZoneUitvoerder(speler: s, rij: s, nummer: (_) => null, idVan: (t) => t.path);

    test('DE KERN: in een radio springt hij binnen die radio, op het juiste nummer', () async {
      final s = _Speler([_i('A'), _i('V', voorstel: true), _i('B'), _i('C')], 0);
      expect(await uitvoerder(s).voerUit({'cmd': 'jump', 'plek': 2, 'trackId': 'C'}), isNull);
      expect(s.inRadio, [3]);
      expect(s.gewoon, isEmpty, reason: 'niet de gewone wachtrij van dit toestel');
    });

    test('het nummer op zijn naam terugvinden als de radio intussen opschoof', () async {
      final s = _Speler([_i('A'), _i('B'), _i('C')], 1);
      await uitvoerder(s).voerUit({'cmd': 'jump', 'plek': 0, 'trackId': 'C'});
      expect(s.inRadio, [2]);
    });

    test('zonder radio: de gewone wachtrij, zoals voorheen', () async {
      final s = _Speler(const [], 0)..radioMode = false;
      await uitvoerder(s).voerUit({'cmd': 'jump', 'plek': 1, 'trackId': 'W2'});
      expect(s.gewoon, [1]);
      expect(s.inRadio, isEmpty);
    });
  });

  group('aangesloten', () {
    test('de speler meldt de radiorij', () {
      final p = _bron('lib/player.dart');
      expect(p, contains('        final m = radioMelding(_radio, _radioIndex);\n'
          '        onProgress?.call(t, positieNauwkeurig, playing, m.rij.isEmpty ? [t] : m.rij, m.index);'));
    });

    test('het paneel toont de radio van een zone als radio', () {
      final m = _bron('lib/main.dart');
      expect(m, contains('    final zoneRadio = p is ZoneSpeler && p.radioMode;\n    final rijRadio = radio || zoneRadio;'));
      expect(m, contains('        regel: rijRadio ? regels[i] : null,'));
      expect(m, contains('            if (rijRadio || tv)\n'), reason: 'geen greep en geen kruisje');
      expect(m, contains('              onPressed: () => unawaited(zoneOpAfstand.radioStop()),'));
    });
  });
}

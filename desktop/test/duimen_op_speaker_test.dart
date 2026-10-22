/// De duimen ook als de radio van de pc op een speaker speelt (Saber, 22-10-2026, een radio vanaf Tamino op de KEF:
/// "wat ik wel nie zie is men duim omhoog of omlaag tijdens het spelen … duim zowel in de wachtrij venster als in de
/// now playing bar en scherm").
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/cast_manager.dart';
import 'package:debridmusic/lan/catalog.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/speaker_radio.dart';

String _lees(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

/// Het stuk van [tekst] vanaf [van] tot [tot].
String _stuk(String tekst, String van, String tot) {
  final a = tekst.indexOf(van);
  expect(a, greaterThanOrEqualTo(0), reason: 'niet gevonden: $van');
  final b = tekst.indexOf(tot, a);
  expect(b, greaterThan(a), reason: 'niet gevonden: $tot');
  return tekst.substring(a, b);
}

void main() {
  test('een speakerradio herkent de zone van zijn speaker, en alleen die', () {
    final catalog = LanCatalog(LibraryStore());
    final cast = CastManager(catalog: catalog, token: 't', port: 47820);
    addTearDown(() {
      cast.dispose();
      catalog.dispose();
    });
    final uit = SpeakerRadio(cast: cast, speaker: '192.168.0.100', idVan: (_) => null, naam: () => 'Radio Tamino');
    expect(uit.speeltOpZone('spk:192.168.0.100'), isTrue, reason: 'zo heet de zone van een speaker (lan/zones.dart)');
    expect(uit.speeltOpZone('spk:192.168.0.20'), isFalse, reason: 'een andere speaker');
    expect(uit.speeltOpZone('dev:pc-Saber'), isFalse, reason: 'een toestel');
    expect(_lees('lib/lan/zones.dart'), contains(r"id: 'spk:${s.id}',"));
  });

  group('aangesloten', () {
    final main = _lees('lib/main.dart');

    test('de duimen volgen een gekozen zone alleen als daar de radio van dit toestel speelt', () {
      final hier = _stuk(main, 'bool _radioOpGekozenZone(BuildContext context', '\n}\n');
      expect(hier, contains('return radio.loopt && uit is SpeakerRadio && uit.speeltOpZone(zone.zoneId);'));
      expect(_stuk(main, 'bool _radioHier(BuildContext context) {', '\n}\n'),
          contains('return zone == null || _radioOpGekozenZone(context);'));
    });

    test('het speelscherm: "Past in deze radio?" en "Houden of weg?" ook op de speaker', () {
      final oordeel = _stuk(main, 'class _RadioOordeel extends StatelessWidget {', "kop('Past in deze radio?')");
      expect(oordeel, contains('if (!_radioHier(context)) return const SizedBox.shrink();'));
      expect(oordeel, isNot(contains('?.opAfstand != null) return const SizedBox.shrink();')),
          reason: 'dat verborg ze bij elke gekozen zone, ook de KEF met de radio van de pc');
    });

    test('de wachtrij: de rij van de speaker krijgt de kleine duimen', () {
      final rij = _stuk(main, 'class _WachtrijRij extends StatelessWidget {', '\nclass ');
      expect(rij, contains('if (!isTv && (r != null ? r.eigen : _radioOpGekozenZone(context, luister: false)))'),
          reason: 'zonder luisteren: anders bouwt elke regel elke seconde opnieuw');
    });

    test('de balk, breed en smal: alleen 👍 houden — "weg" naast het hart en de speelknop is te makkelijk geraakt', () {
      const balkDuim = '_radioHier(context)) _RijDuimen(track: t, alleenHouden: true, maat: 26),';
      expect(balkDuim.allMatches(main).length, 2);
      final breed = _stuk(main, 'class PlayerBar extends StatelessWidget {', 'Widget _compactBar(');
      expect(breed.indexOf(balkDuim), greaterThan(breed.indexOf('_HartKnop(track: t),')), reason: 'naast het hart');
      final smal = _stuk(main, 'Widget _compactBar(', '\n}\n');
      expect(smal.indexOf(balkDuim), lessThan(smal.indexOf('icon: SpeelPauzeIcoon(speelt: x.playing, maat: 30),')));
      final duimen = _stuk(main, 'class _RijDuimen extends StatelessWidget {', '\n}\n');
      expect(duimen, contains('if (!alleenHouden) ...['), reason: 'de rode duim alleen in het volle paar');
    });
  });
}

/// De gewone volumeknop van een groep (zijknoppen, Nu speelt) stuurt ook wie meespeelt, naar verhouding.
///
/// Saber, 27-11-2026: "Volume liep soms niet gelijk van de groep". Om 11:37:40–43 kreeg alleen de Sonos opdrachten (60,
/// 66, 34); de tv, die de Sonos volgde, bleef op 45 staan. Alleen de groepsschuif op de zonekaart stuurde iedereen.
library;

import 'dart:io';

import 'package:debridmusic/lan/zones.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/zone_lijst.dart';
import 'package:debridmusic/zone_speler.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

const _nu = 10000000;
const _sonos = 'spk:192.168.0.188';
const _tv = 'dev:shield-1';

Track _t(String id) => Track(path: 'http://pc.invalid/stream/$id.flac', title: 'Nummer $id', artist: 'X', album: 'A');

ZoneStaat _groep({int sonos = 34, int tv = 45, int opMs = _nu, bool metTv = true}) => ZoneStaat(
      id: _sonos,
      soort: ZoneSoort.speaker,
      naam: 'Sonos Move',
      online: true,
      playing: true,
      trackId: 'b',
      titel: 'Titel',
      positionMs: 60000,
      durationMs: 240000,
      opMs: opMs,
      volume: sonos,
      leden: [
        ZoneLid(id: _sonos, naam: 'Sonos Move', soort: ZoneSoort.speaker, volume: sonos),
        if (metTv) ZoneLid(id: _tv, naam: 'Shield', soort: ZoneSoort.tv, volume: tv),
      ],
    );

ZoneLijst _lijst(ZoneStaat z, {required int Function() klok}) =>
    ZoneLijst(hier: 'dev:gsm-1', klok: klok)..zet({'nu': _nu, 'zones': [z.toJson()]});

({ZoneSpeler speler, List<int> leider, Map<String, List<int>> leden, ZoneLijst lijst}) _opzet(ZoneStaat z,
    {required int Function() klok}) {
  final leider = <int>[];
  final leden = <String, List<int>>{};
  final lijst = _lijst(z, klok: klok);
  final s = ZoneSpeler(
    lijst: lijst,
    zoneId: _sonos,
    nummer: _t,
    idVan: (t) => t.title,
    hoesVan: (_) => null,
    stuur: (op) async {
      if (op['cmd'] == 'volume') leider.add(op['waarde'] as int);
      return null;
    },
    stuurLid: (lid, op) async {
      if (op['cmd'] == 'volume') (leden[lid] ??= []).add(op['waarde'] as int);
      return null;
    },
    klok: klok,
  );
  return (speler: s, leider: leider, leden: leden, lijst: lijst);
}

void main() {
  group('volgerVolume', () {
    test('naar verhouding met de leider, op 0 stil, nooit boven 100', () {
      expect(volgerVolume(45, leider: 34, doel: 40), 53);
      expect(volgerVolume(45, leider: 34, doel: 0), 0);
      expect(volgerVolume(45, leider: 34, doel: 34), 45);
      expect(volgerVolume(90, leider: 50, doel: 80), 100);
      expect(volgerVolume(20, leider: 40, doel: 10), 5);
    });

    test('een stille leider: het lid krijgt de stand zelf', () {
      expect(volgerVolume(45, leider: 0, doel: 30), 30);
      expect(volgerVolume(45, leider: -1, doel: 30), 30);
    });
  });

  group('de volumeknop van een groep', () {
    test('Sonos 34 en tv 45: de knop naar 40 zet de Sonos op 40 en de tv op 53', () {
      fakeAsync((fa) {
        final o = _opzet(_groep(), klok: () => _nu);
        o.speler.setVolume(40);
        fa.elapse(const Duration(milliseconds: 200));
        expect(o.leider, [40]);
        expect(o.leden.keys, [_tv], reason: 'de leider zelf krijgt zijn opdracht via stuur, niet nog eens als lid');
        expect(o.leden[_tv], [53]);
        o.speler.dispose();
      });
    });

    test('naar 0: allebei stil', () {
      fakeAsync((fa) {
        final o = _opzet(_groep(), klok: () => _nu);
        o.speler.setVolume(0);
        fa.elapse(const Duration(milliseconds: 200));
        expect(o.leider, [0]);
        expect(o.leden[_tv], [0]);
        o.speler.dispose();
      });
    });

    test('tijdens één beweging blijft de verhouding die van het begin, ook als de leider al terugmeldt', () {
      fakeAsync((fa) {
        var klok = _nu;
        final o = _opzet(_groep(), klok: () => klok);
        o.speler.setVolume(36);
        fa.elapse(const Duration(milliseconds: 100));
        klok += 100;
        // De Sonos meldt zijn nieuwe stand al, de tv nog niet: een half bijgewerkt paar.
        o.lijst.zet({'nu': klok, 'zones': [_groep(sonos: 36, tv: 45, opMs: klok).toJson()]});
        o.speler.setVolume(40);
        fa.elapse(const Duration(milliseconds: 100));
        klok += 100;
        expect(o.leider, [36, 40]);
        expect(o.leden[_tv], [48, 53], reason: '45 × 40 / 34 = 53, niet 45 × 40 / 36 = 50');
        o.speler.dispose();
      });
    });

    test('een nieuwe beweging na een pauze neemt de standen van dan', () {
      fakeAsync((fa) {
        var klok = _nu;
        final o = _opzet(_groep(), klok: () => klok);
        o.speler.setVolume(40);
        fa.elapse(const Duration(milliseconds: 100));
        klok += kZoneVolumeBeweging.inMilliseconds + 500;
        // Intussen zette iemand de tv zelf op 30.
        o.lijst.zet({'nu': klok, 'zones': [_groep(sonos: 40, tv: 30, opMs: klok).toJson()]});
        fa.elapse(const Duration(seconds: 4));
        o.speler.setVolume(20);
        fa.elapse(const Duration(milliseconds: 100));
        expect(o.leden[_tv], [53, 15]);
        o.speler.dispose();
      });
    });

    test('zonder groep, of zonder stuurLid: alleen de leider', () {
      fakeAsync((fa) {
        final o = _opzet(_groep(metTv: false), klok: () => _nu);
        o.speler.setVolume(40);
        fa.elapse(const Duration(milliseconds: 200));
        expect(o.leider, [40]);
        expect(o.leden, isEmpty);
        o.speler.dispose();

        final leider = <int>[];
        final s = ZoneSpeler(
          lijst: _lijst(_groep(), klok: () => _nu),
          zoneId: _sonos,
          nummer: _t,
          idVan: (t) => t.title,
          hoesVan: (_) => null,
          stuur: (op) async {
            leider.add(op['waarde'] as int);
            return null;
          },
        );
        s.setVolume(40);
        fa.elapse(const Duration(milliseconds: 200));
        expect(leider, [40]);
        s.dispose();
      });
    });

    test('de app geeft de zonespeler de weg naar de andere leden mee', () {
      final bron = File('lib/main.dart').readAsStringSync();
      final bouw = bron.indexOf('ZoneSpeler(');
      expect(bouw, greaterThan(0));
      expect(bron.substring(bouw, bouw + 1500), contains('stuurLid: stuurNaarZone'));
    });

    test('een lid dat geen volume meldt (-1) krijgt niets', () {
      fakeAsync((fa) {
        final o = _opzet(_groep(tv: -1), klok: () => _nu);
        o.speler.setVolume(40);
        fa.elapse(const Duration(milliseconds: 200));
        expect(o.leden, isEmpty);
        o.speler.dispose();
      });
    });
  });
}

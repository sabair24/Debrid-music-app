/// Welke stroomstand er nu geldt, en hoeveel er vooruit gelezen wordt.
///
/// Twee regels, allebei zuiver, allebei het soort som dat je nergens tussen de schermcode wilt
/// hebben staan omdat een fout erin niet omvalt maar stilletjes het verkeerde doet.
library;

import 'dart:io';

import 'package:debridmusic/lan/stroomstand.dart';
import 'package:debridmusic/lan/verbindingsstand.dart' show Verbindingsweg;
import 'package:debridmusic/netsoort.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Stroomstand stand({
    Stroomstand thuis = Stroomstand.max,
    Stroomstand onderweg = Stroomstand.cd,
    bool adaptief = true,
    Netsoort net = Netsoort.wifi,
    Verbindingsweg? weg,
    bool noodstand = false,
    bool tv = false,
  }) =>
      welkeStand(
          thuis: thuis,
          onderweg: onderweg,
          adaptief: adaptief,
          net: net,
          weg: weg,
          noodstand: noodstand,
          tv: tv);

  group('regel A: de netsoort kiest de sport', () {
    test('op wifi geldt wat je thuis wilt', () {
      expect(stand(net: Netsoort.wifi), Stroomstand.max);
    });

    test('op mobiel geldt wat je onderweg wilt', () {
      expect(stand(net: Netsoort.mobiel), Stroomstand.cd);
    });

    test('DE KERN: onbekend valt naar THUIS en niet naar onderweg', () {
      // De dure kant, met opzet. Een mislukte meting mag je thuis nooit stilletjes je hi-res kosten
      // — dat merk je niet en zoek je nooit. Een gemiste meting onderweg kost je een keer meer data
      // dan je wilde, en dát zie je.
      expect(stand(net: Netsoort.onbekend), Stroomstand.max);
    });

    test('staat adaptief uit, dan geldt thuis altijd', () {
      expect(stand(adaptief: false, net: Netsoort.mobiel), Stroomstand.max);
      expect(stand(adaptief: false, net: Netsoort.onbekend), Stroomstand.max);
    });

    test('de twee standen zijn vrij te kiezen, ook andersom', () {
      // Niemand houdt je tegen om onderweg juist méér te willen. Rare keuze, maar geen fout.
      expect(stand(thuis: Stroomstand.cd, onderweg: Stroomstand.max, net: Netsoort.mobiel),
          Stroomstand.max);
    });
  });

  group('de weg naar de pc (21-10-2026: Wonderwall als origineel op mobiele data)', () {
    test('niet thuis verbonden is onderweg, ook als de netsoort nog onbekend is of wifi zegt', () {
      expect(stand(net: Netsoort.onbekend, weg: Verbindingsweg.rechtstreeks), Stroomstand.cd,
          reason: 'koude start of midden in een wissel: Android zegt nog niets, de weg is al bekend');
      expect(stand(net: Netsoort.onbekend, weg: Verbindingsweg.tailscale), Stroomstand.cd);
      expect(stand(net: Netsoort.wifi, weg: Verbindingsweg.rechtstreeks), Stroomstand.cd,
          reason: 'een wifi die niet de jouwe is (op het werk)');
    });

    test('thuis verbonden blijft thuis; zonder weg beslist de netsoort zoals voorheen', () {
      expect(stand(net: Netsoort.wifi, weg: Verbindingsweg.thuis), Stroomstand.max);
      expect(stand(net: Netsoort.onbekend, weg: Verbindingsweg.thuis), Stroomstand.max);
      expect(stand(net: Netsoort.onbekend), Stroomstand.max);
      expect(stand(net: Netsoort.mobiel, weg: Verbindingsweg.thuis), Stroomstand.cd);
    });

    test('een tv blijft thuis, en adaptief uit blijft thuis', () {
      expect(stand(tv: true, weg: Verbindingsweg.rechtstreeks), Stroomstand.max);
      expect(stand(adaptief: false, weg: Verbindingsweg.rechtstreeks), Stroomstand.max);
    });

    test('de noodstand geldt ook onderweg op een vreemde wifi', () {
      expect(
          stand(net: Netsoort.wifi, weg: Verbindingsweg.rechtstreeks, noodstand: true, onderweg: Stroomstand.hoog),
          Stroomstand.cd);
    });

    test('NetsoortStore gebruikt de weg van de sessie', () {
      final s = NetsoortStore()..wegNu = () => Verbindingsweg.rechtstreeks;
      expect(s.onderweg, isTrue);
      s.wegNu = () => Verbindingsweg.thuis;
      expect(s.onderweg, isFalse);
    });

    test('aangesloten: de sessie geeft haar weg, en het vooruithalen volgt onderweg', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(main, contains('netStore.wegNu = () => session.wegVoorStroom;'));
      expect(main, contains('opMobiel: netStore.onderweg,'));
    });
  });

  group('regel B: hapert het, dan één sport lager', () {
    test('precies één sport, niet twee', () {
      expect(eenSportLager(Stroomstand.max), Stroomstand.hoog);
      expect(eenSportLager(Stroomstand.hoog), Stroomstand.cd);
    });

    test('en nooit onder de onderste', () {
      // Er is niets onder cd zonder lossy te gaan coderen, en dat gebeurt hier niet.
      expect(eenSportLager(Stroomstand.cd), Stroomstand.cd);
      expect(eenSportLager(eenSportLager(eenSportLager(Stroomstand.max))), Stroomstand.cd);
    });

    test('onderweg werkt de noodstand op de sport die op dat moment geldt', () {
      expect(stand(net: Netsoort.mobiel, noodstand: true), Stroomstand.cd);
      expect(stand(net: Netsoort.mobiel, onderweg: Stroomstand.max, noodstand: true),
          Stroomstand.hoog);
    });

    test('de noodstand klimt nooit vanzelf terug', () {
      // Zolang de grendel staat blijft hij staan; hem laten opklimmen na een geslaagd nummer lokt
      // precies de hapering uit die hij net oploste.
      final een = stand(net: Netsoort.mobiel, onderweg: Stroomstand.hoog, noodstand: true);
      final twee = stand(net: Netsoort.mobiel, onderweg: Stroomstand.hoog, noodstand: true);
      expect(een, twee);
      expect(een, Stroomstand.cd);
    });

    test('DE KERN: thuis zakt het nooit — één kapot bestand is geen zwakke lijn', () {
      // 10-10-2026 op de Shield: "Stromae – Sommeil" van 0,1 MB brak af, de noodstand ging aan, en de
      // rest van de avond ging elk hi-res nummer als 24/48 de deur uit. Thuis lost een lagere sport
      // niets op; onderweg wel.
      expect(stand(net: Netsoort.wifi, noodstand: true), Stroomstand.max);
      expect(stand(net: Netsoort.onbekend, noodstand: true), Stroomstand.max);
      expect(stand(net: Netsoort.wifi, thuis: Stroomstand.hoog, noodstand: true), Stroomstand.hoog,
          reason: 'wat je thuis zelf koos blijft staan, niet lager');
    });
  });

  group('DE KERN: een televisie zit thuis', () {
    test('ook als Android zijn netwerk "beperkt" noemt (een VPN), en ook na een hapering', () {
      expect(stand(tv: true, net: Netsoort.mobiel), Stroomstand.max);
      expect(stand(tv: true, net: Netsoort.mobiel, noodstand: true), Stroomstand.max);
      expect(stand(tv: true, net: Netsoort.wifi, noodstand: true), Stroomstand.max);
    });

    test('wat je op de tv als thuisstand koos, blijft het', () {
      expect(stand(tv: true, thuis: Stroomstand.hoog, net: Netsoort.mobiel), Stroomstand.hoog);
    });

    test('de winkel geeft de tv mee', () {
      final bron = File('lib/netsoort.dart').readAsStringSync();
      expect(bron.contains('        tv: isTv,\n'), isTrue);
    });
  });

  group('vooruitlezen', () {
    test('op wifi blijft het driehonderd seconden', () {
      // Dat is de reparatie van 15-08-2026 voor draadloos Android Auto. Niet aankomen.
      expect(vooruitleesSeconden(Netsoort.wifi), 300);
    });

    test('bij onbekend ook, om dezelfde reden als bij de stand', () {
      expect(vooruitleesSeconden(Netsoort.onbekend), 300);
    });

    test('op mobiel korter, want vooruitlezen is daar niet gratis', () {
      // 300 s op de cd-stand is ~34 MB per nummer. Skip je na twintig seconden door, dan gooi je
      // ~32 MB weg waar je voor betaald hebt.
      expect(vooruitleesSeconden(Netsoort.mobiel), 90);
      expect(vooruitleesSeconden(Netsoort.mobiel),
          lessThan(vooruitleesSeconden(Netsoort.wifi)));
    });
  });
}

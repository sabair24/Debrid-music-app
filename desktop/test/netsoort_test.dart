/// Welke stroomstand er nu geldt, en hoeveel er vooruit gelezen wordt.
///
/// Twee regels, allebei zuiver, allebei het soort som dat je nergens tussen de schermcode wilt
/// hebben staan omdat een fout erin niet omvalt maar stilletjes het verkeerde doet.
library;

import 'package:debridmusic/lan/stroomstand.dart';
import 'package:debridmusic/netsoort.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Stroomstand stand({
    Stroomstand thuis = Stroomstand.max,
    Stroomstand onderweg = Stroomstand.cd,
    bool adaptief = true,
    Netsoort net = Netsoort.wifi,
    bool noodstand = false,
  }) =>
      welkeStand(
          thuis: thuis, onderweg: onderweg, adaptief: adaptief, net: net, noodstand: noodstand);

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

    test('de noodstand werkt op de sport die op dat moment geldt', () {
      expect(stand(net: Netsoort.wifi, noodstand: true), Stroomstand.hoog);
      expect(stand(net: Netsoort.mobiel, noodstand: true), Stroomstand.cd);
    });

    test('de noodstand klimt nooit vanzelf terug', () {
      // Zolang de grendel staat blijft hij staan; hem laten opklimmen na een geslaagd nummer lokt
      // precies de hapering uit die hij net oploste.
      final een = stand(noodstand: true);
      final twee = stand(noodstand: true);
      expect(een, twee);
      expect(een, Stroomstand.hoog);
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

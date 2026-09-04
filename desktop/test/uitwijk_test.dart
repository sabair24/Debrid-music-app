/// Welk adres probeert de telefoon als je niet thuis bent?
///
/// Gevraagd op 04-09-2026: *"ik heb tailscale op men smartphone, dus moet lukken als ik op de baan
/// ben ook."* Een fout in deze volgorde valt niet op als een fout maar als traagheid — elke poging
/// naar een adres dat niemand opneemt kost seconden voordat je je muziek ziet. Daarom staat de
/// beslissing apart in `lib/lan/uitwijk.dart` en staat deze toets eromheen.
import 'package:debridmusic/lan/uitwijk.dart';
import 'package:flutter_test/flutter_test.dart';

Uri u(String s) => Uri.parse(s);

void main() {
  group('weguitVolgorde', () {
    test('het onthouden adres gaat voorop', () {
      // Dat is het adres dat de vórige keer werkte. De aanroeper legt vast welk adres het werd, dus
      // deze volgorde corrigeert zichzelf: lukt het op de baan via Tailscale, dan staat dát adres
      // de volgende keer vooraan -- en thuis werkt het ook.
      final rij = weguitVolgorde(
        onthouden: u('http://192.168.0.117:47820'),
        uitwijk: [u('http://100.101.42.7:47820')],
        gevondenOpNetwerk: [u('http://192.168.0.9:47820')],
      );
      expect(rij.first, u('http://192.168.0.117:47820'));
    });

    test('uitwijk komt vóór het lokale netwerk afzoeken', () {
      // Op de baan staat je pc niet op dit netwerk. Eerst zoeken kost seconden en levert per
      // definitie niets op.
      final rij = weguitVolgorde(
        onthouden: u('http://192.168.0.117:47820'),
        uitwijk: [u('http://100.101.42.7:47820')],
        gevondenOpNetwerk: [u('http://192.168.0.9:47820')],
      );
      expect(rij.map((e) => e.host).toList(),
          ['192.168.0.117', '100.101.42.7', '192.168.0.9']);
    });

    test('zonder uitwijkadressen blijft het zoals het was', () {
      final rij = weguitVolgorde(
        onthouden: u('http://192.168.0.117:47820'),
        gevondenOpNetwerk: [u('http://192.168.0.9:47820')],
      );
      expect(rij.map((e) => e.host).toList(), ['192.168.0.117', '192.168.0.9']);
    });

    test('hetzelfde adres wordt niet twee keer geprobeerd', () {
      // De pc roept zichzelf om op het netwerk en staat ook in wat we onthouden hebben. Dat is één
      // machine, en twee keer bellen kost alleen tijd.
      final rij = weguitVolgorde(
        onthouden: u('http://192.168.0.117:47820'),
        uitwijk: [u('http://100.101.42.7:47820'), u('http://192.168.0.117:47820')],
        gevondenOpNetwerk: [u('http://192.168.0.117:47820')],
      );
      expect(rij.length, 2);
    });

    test('twee servers op dezelfde machine zijn twee adressen', () {
      // Op poort, niet alleen op host: een tweede app op dezelfde pc is een andere server.
      final rij = weguitVolgorde(
        onthouden: u('http://192.168.0.117:47820'),
        gevondenOpNetwerk: [u('http://192.168.0.117:47821')],
      );
      expect(rij.length, 2);
    });

    test('hetzelfde adres met een ander schema is hetzelfde adres', () {
      final rij = weguitVolgorde(
        onthouden: u('http://192.168.0.117:47820'),
        uitwijk: [u('https://192.168.0.117:47820')],
      );
      expect(rij.length, 1);
    });

    test('zonder onthouden adres blijft de rest gewoon staan', () {
      final rij = weguitVolgorde(
        onthouden: null,
        uitwijk: [u('http://100.101.42.7:47820')],
      );
      expect(rij.map((e) => e.host).toList(), ['100.101.42.7']);
    });

    test('een adres zonder host gaat er niet in', () {
      // Anders wordt er een verzoek gestuurd naar niets, en dat kost een timeout.
      final rij = weguitVolgorde(
        onthouden: u('http://192.168.0.117:47820'),
        uitwijk: [Uri.parse('nergens')],
      );
      expect(rij.length, 1);
    });

    test('helemaal niets levert een lege rij op en geen fout', () {
      expect(weguitVolgorde(onthouden: null), isEmpty);
    });
  });

  group('leesAdressen', () {
    test('leest wat de pc opschrijft', () {
      final rij = leesAdressen(['http://100.101.42.7:47820', 'http://100.64.0.3:47820']);
      expect(rij.map((e) => e.host).toList(), ['100.101.42.7', '100.64.0.3']);
      expect(rij.first.port, 47820);
    });

    test('één rare regel maakt de rest niet onbruikbaar', () {
      // Een pc van een andere versie mag hier een regel neerzetten die wij niet begrijpen. Dan valt
      // die regel weg, niet de lijst -- en dat is precies het adres waarmee je op de baan binnenkomt.
      final rij = leesAdressen(['', '   ', 'nergens', 'http://100.101.42.7:47820']);
      expect(rij.map((e) => e.host).toList(), ['100.101.42.7']);
    });

    test('niets is niets', () {
      expect(leesAdressen(const []), isEmpty);
    });
  });
}

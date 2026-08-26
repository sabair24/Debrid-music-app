/// Wat TorBox aan het doen is, in één zin die waar is.
///
/// **Waarom hier een toets op staat.** In het nummerkeuzevenster stond een vaste regel:
///
/// > Niet-gecachte torrents met weinig seeders kunnen even duren.
///
/// Altijd, ongeacht wat er gebeurde. Gemeld op een torrent met **veertig** seeders — dan zegt het
/// scherm dus iets dat aantoonbaar onwaar is, en ga je de vertraging zoeken waar hij niet zit.
///
/// De waarheid was er allang: `_pollReady` krijgt bij elke peiling status, voortgang, seeders en
/// grootte binnen en gaf die ook door. Het venster gooide alles behalve het percentage weg.
///
/// Een zin die uit een meting komt kan stil verkeerd gaan zodra iemand er een geval bij zet. Vandaar
/// deze toets: hij legt vast wat er NIET mag staan, net zo goed als wat er wel hoort te staan.
library;

import 'package:debridmusic/torbox_stand.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DE KERN: nooit meer een uitspraak over seeders die niet gemeten is', () {
    test('veertig seeders heet niet "weinig"', () {
      final zin = torboxStand(
          gecacht: false, deel: 0.12, status: 'downloading', seeds: 40, grootte: 416000000);
      expect(zin, contains('40 seeders'));
      expect(zin.toLowerCase().contains('weinig'), isFalse);
    });

    test('de regel eronder legt uit waarom je wacht, zonder te gokken', () {
      final waarom = torboxWaarom(gecacht: false);
      expect(waarom, contains('cache'));
      expect(waarom.toLowerCase().contains('seeder'), isFalse,
          reason: 'die uitspraak hoort in de gemeten zin, niet in een vaste regel');
    });

    test('en bij een gecachte bron staat er niets uit te leggen', () {
      expect(torboxWaarom(gecacht: true), isEmpty);
      expect(torboxStand(gecacht: true, deel: 1, status: 'cached', seeds: 0, grootte: 1),
          contains('klaarstaan'));
    });
  });

  group('de stand zelf', () {
    test('bezig met binnenhalen toont percentage en seeders', () {
      expect(
          torboxStand(
              gecacht: false, deel: 0.61, status: 'downloading', seeds: 3, grootte: 554000000),
          'TorBox haalt hem binnen — 61% · 3 seeders.');
    });

    test('één seeder is enkelvoud', () {
      expect(
          torboxStand(gecacht: false, deel: 0.04, status: 'downloading', seeds: 1, grootte: 100),
          contains('1 seeder.'));
    });

    test('nul procent en geen seeders, maar wel een grootte: gewoon de stand', () {
      final zin =
          torboxStand(gecacht: false, deel: 0, status: 'metadl', seeds: 0, grootte: 554000000);
      expect(zin, startsWith('TorBox zoekt de bestandslijst op'));
      expect(zin.contains('%'), isFalse, reason: 'nul procent is geen voortgang om te melden');
    });

    test('DE KERN: geen grootte én geen seeders is een dode zwerm, geen trage download', () {
      // Gemeten geval uit de code: 2,5 uur "checking", size -1, seeds 0. Daar komt niets meer van,
      // en dat hoort meteen gezegd te worden in plaats van na een half uur wachten.
      final zin = torboxStand(gecacht: false, deel: 0, status: 'checking', seeds: 0, grootte: -1);
      expect(zin, contains('nog geen enkele seeder'));
      expect(zin, contains('index van de tracker'),
          reason: 'want dát is waar het getal in de zoeklijst vandaan komt');
    });

    test('een status die we niet kennen wordt getoond, niet verzonnen', () {
      final zin =
          torboxStand(gecacht: false, deel: 0.5, status: 'iets_nieuws', seeds: 2, grootte: 10);
      expect(zin, contains('iets_nieuws'));
    });

    test('een lege status verzint ook niets', () {
      expect(torboxStand(gecacht: false, deel: 0.5, status: '', seeds: 2, grootte: 10),
          startsWith('Bezig bij TorBox'));
    });
  });

  group('open announce-adressen aan een kale magneet', () {
    const kaal = 'magnet:?xt=urn:btih:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa&dn=Iets';

    test('DE KERN: een magneet zonder trackers krijgt ze erbij', () {
      // Zonder announce moet wie hem oppakt de zwerm via DHT zien te vinden, en dat lukt lang niet
      // altijd. Dat verschil is in deze app gemeten: als magneet 2,5 uur niets, als .torrent 61% in
      // twee minuten.
      final uit = magneetMetAnnounce(kaal);
      expect(uit, startsWith(kaal));
      for (final t in kOpenTrackers) {
        expect(uit, contains(Uri.encodeComponent(t)));
      }
    });

    test('en een magneet die er al heeft blijft ongemoeid', () {
      // De trackers van de bron zelf weten beter waar die zwerm zit dan een algemene lijst.
      const met = '$kaal&tr=udp%3A%2F%2Feigen.tracker%3A80%2Fannounce';
      expect(magneetMetAnnounce(met), met);
    });

    test('wat geen magneet is blijft wat het is', () {
      expect(magneetMetAnnounce('https://ergens/iets.torrent'), 'https://ergens/iets.torrent');
      expect(magneetMetAnnounce(''), '');
    });

    test('de adressen zijn ontsnapt, anders breekt de magneet', () {
      // Een announce bevat : en /, en die horen niet rauw in een queryparameter.
      expect(magneetMetAnnounce(kaal).contains('&tr=udp://'), isFalse);
    });
  });
}

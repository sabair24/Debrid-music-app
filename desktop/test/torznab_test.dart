/// Je eigen indexers via Torznab: het adres en wat er terugkomt.
///
/// **Waarom dit bestaat.** De bronnen in deze app staan vast in de code. Valt er een tracker om — en
/// dat gebeurt om de paar maanden — dan is er een nieuwe bouw nodig om hem te vervangen. Met Jackett
/// of Prowlarr op de eigen pc bepaalt de gebruiker de lijst, en komt er geen bouw meer aan te pas.
///
/// Twee stukken kunnen hier stil fout gaan, en allebei zijn ze zonder Jackett en zonder net te
/// meten: het adres dat opgebouwd wordt, en het uitpluizen van het antwoord. Een indexer die zijn
/// infohash ergens anders neerzet dan verwacht levert anders "geen resultaten" op, zonder dat er
/// iets kapot lijkt.
library;

import 'package:debridmusic/torznab.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een antwoord zoals Jackett het geeft: drie items die elk hun infohash op een ándere plek zetten.
/// Dat is geen bedacht randgeval — indexers verschillen daar echt in.
const _antwoord = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:torznab="http://torznab.com/schemas/2015/feed">
  <channel>
    <item>
      <title>P!nk - Beautiful Trauma (2017) FLAC 24-96</title>
      <size>1148903424</size>
      <enclosure url="magnet:?xt=urn:btih:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&amp;dn=Trauma" />
      <torznab:attr name="seeders" value="47" />
      <torznab:attr name="peers" value="59" />
    </item>
    <item>
      <title>Gala - Come Into My Life (2022) FLAC</title>
      <size>612000000</size>
      <torznab:attr name="infohash" value="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" />
      <torznab:attr name="seeders" value="8" />
    </item>
    <item>
      <title>Iemand - Iets (1998) APE</title>
      <link>magnet:?xt=urn:btih:cccccccccccccccccccccccccccccccccccccccc</link>
      <torznab:attr name="seeders" value="3" />
    </item>
    <item>
      <title>Zonder infohash, dus onbruikbaar</title>
      <link>https://ergens/pagina.html</link>
      <torznab:attr name="seeders" value="99" />
    </item>
  </channel>
</rss>''';

void main() {
  group('DE KERN: de infohash wordt overal gevonden waar hij kan staan', () {
    test('uit de enclosure, uit een eigen veld, en uit de link', () {
      final uit = leesTorznab(_antwoord);
      expect(uit.map((r) => r.hash), [
        'a' * 40,
        'b' * 40,
        'c' * 40,
      ]);
    });

    test('een rij zonder infohash valt af, want daar valt niets mee te halen', () {
      // TorBox kent een torrent bij zijn hash, en de zoekverdeler ontdubbelt erop. Zo'n rij is geen
      // halve treffer maar geen treffer — hem tóch tonen levert een download die nooit begint.
      final uit = leesTorznab(_antwoord);
      expect(uit.length, 3);
      expect(uit.any((r) => r.name.contains('onbruikbaar')), isFalse);
    });

    test('een item zonder magneet krijgt er zelf een uit zijn hash', () {
      final tweede = leesTorznab(_antwoord)[1];
      expect(tweede.magnet, contains('urn:btih:${'b' * 40}'));
    });
  });

  group('de getallen', () {
    test('grootte en seeders komen mee', () {
      final eerste = leesTorznab(_antwoord).first;
      expect(eerste.size, 1148903424);
      expect(eerste.seeders, 47);
    });

    test('peers telt seeders mee, dus leechers is het verschil', () {
      // Wie `peers` rechtstreeks als leechers overneemt laat een torrent met 47 seeders drukker
      // lijken dan hij is.
      expect(leesTorznab(_antwoord).first.leechers, 12);
    });

    test('een item zonder seeders is nul, geen fout', () {
      expect(leesTorznab(_antwoord)[2].seeders, 3);
    });
  });

  group('wat geen Torznab is', () {
    test('rommel geeft een lege lijst in plaats van een uitzondering', () {
      expect(leesTorznab('dit is geen xml'), isEmpty);
      expect(leesTorznab(''), isEmpty);
      expect(leesTorznab('<rss><channel></channel></rss>'), isEmpty);
    });
  });

  group('het adres', () {
    const sleutel = 'abc123';

    test('DE KERN: alle indexers tegelijk, en de sleutel gaat mee', () {
      // `all` is het adres van Jackett dat élke indexer bevraagt die je erin gezet hebt. Dat is
      // precies de bedoeling: één bron in de app, zoveel trackers erachter als je wil.
      final u = torznabZoekAdres('http://127.0.0.1:9117', sleutel, 'pink trauma');
      expect(u.path, '/api/v2.0/indexers/all/results/torznab/api');
      expect(u.queryParameters['apikey'], sleutel);
      expect(u.queryParameters['q'], 'pink trauma');
      expect(u.queryParameters['cat'], kTorznabAudio);
      expect(u.queryParameters['t'], 'search');
    });

    test('een adres zonder http ervoor werkt ook', () {
      // Mensen typen "127.0.0.1:9117". Daar hoort geen foutmelding op te volgen.
      expect(torznabZoekAdres('127.0.0.1:9117', sleutel, 'x').scheme, 'http');
      expect(torznabZoekAdres('127.0.0.1:9117', sleutel, 'x').port, 9117);
    });

    test('een schuine streep te veel verandert niets', () {
      expect(torznabZoekAdres('http://pc:9117///', sleutel, 'x').path,
          '/api/v2.0/indexers/all/results/torznab/api');
    });

    test('DE KERN: een geplakt volledig adres krijgt zijn pad niet twee keer', () {
      // Mensen kopiëren het hele adres uit Jackett, inclusief pad en sleutel. Twee keer een pad
      // geeft een 404 en verder geen enkele aanwijzing waarom.
      final u = torznabZoekAdres(
          'http://127.0.0.1:9117/api/v2.0/indexers/all/results/torznab/api?apikey=oud',
          sleutel,
          'x');
      expect(u.path, '/api/v2.0/indexers/all/results/torznab/api');
      expect(u.queryParameters['apikey'], sleutel, reason: 'de ingevulde sleutel wint');
      expect('$u'.contains('oud'), isFalse);
    });

    test('geen adres geeft geen adres', () {
      expect(torznabZoekAdres('', sleutel, 'x').toString(), isEmpty);
      expect(torznabZoekAdres('   ', sleutel, 'x').toString(), isEmpty);
    });
  });
}

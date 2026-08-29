/// Redacted uitpluizen: één album met vier uitgaven wordt vier treffers.
///
/// **Waarom dit los getoetst wordt.** Redacted is besloten — zonder account kan niemand hier
/// naartoe, ook een toets niet. Wat wél te toetsen valt is de vorm van hun antwoord, en juist daar
/// gaat het stil mis: één veld dat anders heet levert geen foutmelding op maar een lege lijst, en
/// dan lijkt het alsof de tracker niets heeft.
///
/// De vorm hieronder is die van `ajax.php?action=browse`: groepen (een album) met daarin `torrents`
/// (de uitgaven ervan — FLAC, 24bit, MP3, vinyl). Elke uitgave is een eigen keuze voor de gebruiker
/// en dus een eigen treffer.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/redacted.dart';

const _antwoord = '''
{"status":"success","response":{"results":[
  {"groupId":1,"groupName":"Discovery","artist":"Daft Punk","groupYear":2001,
   "torrents":[
     {"torrentId":11,"format":"FLAC","encoding":"Lossless","media":"CD","size":419430400,
      "seeders":42,"leechers":3,"hasLog":true,"logScore":100},
     {"torrentId":12,"format":"FLAC","encoding":"24bit Lossless","media":"Vinyl","size":1073741824,
      "seeders":7,"leechers":0,"hasLog":false,"logScore":0},
     {"torrentId":13,"format":"MP3","encoding":"320","media":"WEB","size":146800640,
      "seeders":120,"leechers":1}
   ]},
  {"groupId":2,"groupName":"Homework","artist":"Daft Punk","groupYear":1997,
   "torrents":[
     {"torrentId":21,"format":"FLAC","encoding":"Lossless","media":"WEB","size":377487360,
      "seeders":9,"leechers":0}
   ]}
]}}''';

void main() {
  group('het zoekantwoord', () {
    test('elke uitgave wordt een eigen treffer', () {
      final uit = leesZoekantwoord(_antwoord);

      expect(uit.length, 4);
      expect(uit.first.name, contains('Daft Punk'));
      expect(uit.first.name, contains('Discovery'));
      expect(uit.first.seeders, 42);
      expect(uit.first.size, 419430400);
    });

    test('de naam draagt wat je nodig hebt om te kiezen', () {
      // Formaat, codering en bron staan erin, want dat IS het verschil tussen die vier regels. De
      // kwaliteitszeef van de app leest bovendien mee in deze naam.
      final uit = leesZoekantwoord(_antwoord);

      expect(uit[0].name, contains('FLAC'));
      expect(uit[0].name, contains('Lossless'));
      expect(uit[0].name, contains('[CD]'));
      expect(uit[1].name, contains('24bit Lossless'));
      expect(uit[1].name, contains('[Vinyl]'));
      expect(uit[2].name, contains('MP3'));
      expect(uit[2].name, contains('320'));
    });

    test('een perfecte rip krijgt zijn keurmerk mee', () {
      // hasLog + logScore 100 is op Redacted het teken dat de schijf foutloos gelezen is.
      expect(leesZoekantwoord(_antwoord)[0].name, contains('keurmerk'));
      expect(leesZoekantwoord(_antwoord)[1].name, isNot(contains('keurmerk')));
    });

    test('het adres wijst naar het torrentbestand van díé uitgave', () {
      final uit = leesZoekantwoord(_antwoord);

      expect(uit[0].torrentUrl, contains('action=download'));
      expect(uit[0].torrentUrl, endsWith('id=11'));
      expect(uit[3].torrentUrl, endsWith('id=21'));
    });

    test('er komt geen magneet en geen infohash mee, en dat hoort', () {
      // Redacted geeft die niet in `browse`. De app rekent de hash straks zelf uit het bestand —
      // zie `TorrentInhoud.infohash`. Een verzonnen magneet zou hier een torrent opleveren die
      // nergens te vinden is.
      final uit = leesZoekantwoord(_antwoord);

      expect(uit[0].magnet, isEmpty);
      expect(uit[0].hash, isEmpty);
      expect(uit[0].source, 'Redacted');
    });

    test('een mislukking levert een lege lijst op, geen halve treffers', () {
      expect(leesZoekantwoord('{"status":"failure","error":"bad credentials"}'), isEmpty);
      expect(leesZoekantwoord('<html>login</html>'), isEmpty);
      expect(leesZoekantwoord(''), isEmpty);
    });

    test('een uitgave zonder id valt af', () {
      // Zonder torrentId valt er niets op te halen; zo'n regel is geen halve treffer maar geen.
      const zonder = '{"status":"success","response":{"results":[{"groupName":"X","artist":"Y",'
          '"torrents":[{"format":"FLAC","encoding":"Lossless"}]}]}}';

      expect(leesZoekantwoord(zonder), isEmpty);
    });
  });

  group('het adres herkennen', () {
    test('een Redacted-adres vraagt om de sleutel, niet om een koekje', () {
      expect(isRedactedAdres('https://redacted.sh/ajax.php?action=download&id=11'), isTrue);
      // De oude naam werkt ook nog: er staan links van jaren terug in omloop.
      expect(isRedactedAdres('https://redacted.ch/ajax.php?action=download&id=11'), isTrue);
      expect(isRedactedAdres('https://rutracker.org/forum/dl.php?t=123'), isFalse);
      expect(isRedactedAdres(''), isFalse);
    });

    test('en het id komt er heel uit', () {
      expect(redactedIdUit('https://redacted.sh/ajax.php?action=download&id=4905993'), 4905993);
      expect(redactedIdUit('https://redacted.sh/ajax.php?action=download'), 0);
    });
  });
}

/// Een plaat van Tidal halen met tiddl.
///
/// Vier stukken die zonder Python, zonder abonnement en zonder netwerk vastliggen: waar het
/// programma gezocht wordt, wat er van een geplakte link overblijft, hoe de opdrachtregel eruitziet,
/// en wat er van een mislukking op het scherm komt.
///
/// De opdrachtregel is de belangrijkste. Twee dingen daarin zijn met het oog niet na te kijken en
/// allebei fout te krijgen zonder dat er iets rood wordt.
library;

import 'package:debridmusic/tiddl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('waar tiddl gezocht wordt', () {
    test('PATH staat vooraan, want daar zetten pip en uv hem allebei neer', () {
      expect(tiddlKandidaten(os: 'linux', thuis: '/home/saber').first, 'tiddl');
      expect(tiddlKandidaten(os: 'windows', thuis: r'C:\Users\saber').first, 'tiddl.exe');
    });

    test('en de plekken waar ze hem laten staan als PATH niet bijgewerkt is', () {
      // Na een verse installatie op Windows is dat het gewone geval.
      expect(tiddlKandidaten(os: 'windows', thuis: r'C:\Users\saber'),
          contains(r'C:\Users\saber\.local\bin\tiddl.exe'));
      expect(tiddlKandidaten(os: 'macos', thuis: '/Users/saber'),
          contains('/Users/saber/.local/bin/tiddl'));
      expect(tiddlKandidaten(os: 'macos', thuis: '/Users/saber'), contains('/opt/homebrew/bin/tiddl'));
    });

    test('zonder thuismap blijft alleen PATH over, en dat stort niet in', () {
      expect(tiddlKandidaten(os: 'linux'), ['tiddl', '/opt/homebrew/bin/tiddl', '/usr/local/bin/tiddl']);
      expect(tiddlKandidaten(os: 'windows'), ['tiddl.exe']);
    });
  });

  group('wat er van een geplakte link overblijft', () {
    test('de twee adressen die Tidal zelf gebruikt', () {
      expect(tidalDoel('https://tidal.com/browse/album/103805723'), 'album/103805723');
      expect(tidalDoel('https://listen.tidal.com/album/103805723'), 'album/103805723');
    });

    test('de meelifterij van de deelknop gaat eraf', () {
      // Dit is wat er werkelijk op je klembord staat als je in de Tidal-app op "deel" tikt.
      expect(tidalDoel('https://tidal.com/browse/track/103805726?u'), 'track/103805726');
      expect(tidalDoel('https://listen.tidal.com/album/103805723/'), 'album/103805723');
    });

    test('de korte vorm die tiddl zelf ook aanneemt', () {
      expect(tidalDoel('album/103805723'), 'album/103805723');
      expect(tidalDoel('  track/103805726  '), 'track/103805726');
    });

    test('alle zes de soorten', () {
      for (final soort in ['track', 'album', 'artist', 'playlist', 'mix', 'video']) {
        expect(tidalDoel('https://tidal.com/browse/$soort/123'), '$soort/123',
            reason: 'tiddl kent $soort');
      }
    });

    test('wat niet klopt wordt hier geweigerd, niet door Python', () {
      // Een zin op het scherm is beter dan een rode stapeltrace uit een proces dat je startte om
      // een fout te ontdekken die je al kon zien.
      expect(tidalDoel(''), isNull);
      expect(tidalDoel('   '), isNull);
      expect(tidalDoel('https://open.spotify.com/album/123'), isNull);
      expect(tidalDoel('https://tidal.com/browse/album'), isNull, reason: 'geen id');
      expect(tidalDoel('https://tidal.com/browse/onzin/123'), isNull, reason: 'geen bekende soort');
      expect(tidalDoel('103805723'), isNull, reason: 'een kaal getal zegt niet wát het is');
      expect(tidalDoel('gewoon wat tekst'), isNull);
    });
  });

  group('de opdrachtregel', () {
    List<String> regel({String kwaliteit = 'max'}) => tiddlOpdracht(
          tool: 'tiddl',
          doel: 'album/103805723',
          map: r'D:\Flac music 2024',
          kwaliteit: kwaliteit,
        );

    test('de vlaggen staan vóór url, want download draagt ze', () {
      // `url` is een subopdracht van `download`. Erachter gezet worden de vlaggen niet gelezen, en
      // dan landt de plaat in de standaardmap van tiddl in plaats van in jouw bibliotheek — zonder
      // dat er iets misgaat waar je het aan ziet.
      final r = regel();
      expect(r.indexOf('download'), 1);
      expect(r.indexOf('-p'), lessThan(r.indexOf('url')));
      expect(r.indexOf('-q'), lessThan(r.indexOf('url')));
      expect(r.last, 'album/103805723', reason: 'het doel staat helemaal achteraan');
    });

    test('-err staat erin, anders liegt de afloopcode', () {
      // Zonder deze vlag drukt tiddl een fout in het rood af en stopt met afloopcode 0. De app zou
      // dan "klaar" melden over een download die niet gebeurd is — het groene vinkje boven een
      // onbeantwoorde vraag waar dit project al twee keer op stukliep.
      expect(regel(), contains('-err'));
    });

    test('de muziekmap gaat mee als één argument, ook met spaties erin', () {
      final r = regel();
      expect(r[r.indexOf('-p') + 1], r'D:\Flac music 2024');
    });

    test('de kwaliteit gaat mee zoals tiddl hem schrijft', () {
      expect(regel()[regel().indexOf('-q') + 1], 'max');
      expect(regel(kwaliteit: 'high')[3], 'high');
      // `max` staat vooraan in de lijst: 24 bit is de enige reden om dit te bouwen. `low` en
      // `normal` zijn m4a en slechter dan wat deze bibliotheek al heeft.
      expect(tidalKwaliteiten.first, 'max');
      expect(tidalKwaliteiten, containsAll(['max', 'high', 'normal', 'low']));
    });
  });

  group('wat er van een mislukking op het scherm komt', () {
    test('de kleurcodes van Rich gaan eraf', () {
      const rauw = '\x1B[31mTrack not available in your country\x1B[0m';
      expect(leesbareFout(rauw), 'Track not available in your country');
    });

    test('alleen de laatste regels, want de rest is voortgangsbalk', () {
      final rauw = [for (var i = 1; i <= 20; i++) 'regel $i'].join('\n');
      final uit = leesbareFout(rauw, regels: 3);
      expect(uit, 'regel 18\nregel 19\nregel 20');
    });

    test('regelterugloop telt als een nieuwe regel', () {
      // Rich tekent zijn balkje door telkens terug te springen naar het begin van de regel. Zonder
      // dit is de hele voortgang één onleesbare regel van duizenden tekens.
      expect(leesbareFout('bezig 10%\rbezig 90%\rklaar', regels: 1), 'klaar');
    });

    test('niets is ook een antwoord', () {
      // Een lege uitleg is erger dan een saaie: dan staat er een foutvenster zonder tekst.
      expect(leesbareFout(''), isNotEmpty);
      expect(leesbareFout('   \n \n '), isNotEmpty);
    });
  });
}

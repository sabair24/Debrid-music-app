/// Of een Soulseek-bestand echt het nummer is dat de radio vroeg.
///
/// Gemeten op 26-09-2026, radio vanaf "Freak Out" van 2 Fabiola: van de 27 nummers die de radio in
/// `Singles` zette waren er zes een ander nummer dan hun naam — horrorcore, een gamesoundtrack en
/// Spaanse pop tussen de eurodance. De radio koos op kwaliteit alleen. En "Move On Baby" van Cappella
/// kwam als albumversie van 4:51 terwijl de single 3:40 duurt: "niet original".
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/organize.dart' show TrackTags;
import 'package:debridmusic/radiobestand.dart';

bool klopt(String artiest, String titel, String pad, {int? seconden, int? padSeconden}) =>
    radioBestandKlopt(
        artiest: artiest,
        titel: titel,
        seconden: seconden,
        pad: pad,
        padSeconden: padSeconden);

TrackTags tags(String artiest, String titel) =>
    TrackTags(title: titel, artist: artiest, album: '', trackNo: 0);

void main() {
  group('DE KERN: de zes verkeerde nummers van 26-09-2026 vallen af op de naam', () {
    test('een ander nummer met een woord méér', () {
      expect(
          klopt('RMB', 'Redemption',
              r'@@peer\Music\RMB\Final Fantasy XIV\Masayoshi Soken - Beyond Redemption.flac'),
          isFalse,
          reason: '"beyond" staat nergens anders in het pad — dat is een ander nummer');
    });

    test('een artiest die maar half in het pad staat', () {
      expect(
          klopt('Pat Krimson', 'When The Lights Go Down',
              r'Music\Boondox\Krimson Crow\07 - When The Lights Go Down.mp3'),
          isFalse,
          reason: '"Krimson Crow" is een album van Boondox, niet Pat Krimson — was horrorcore');
    });

    test('een ander nummer met dezelfde titel', () {
      expect(
          klopt("2 Fabiola", "I'm on Fire",
              r"Electronic\Porter Robinson\I'm On Fire (Original Mix).flac"),
          isFalse,
          reason: 'geen "fabiola" in het pad: dit is Porter Robinson');
    });

    test('een naamgenoot van de artiest met een andere titel', () {
      expect(
          klopt('2 Fabiola', 'Break Away',
              r'Metal\Broken Fabiola\Deliverance Through Grace.flac'),
          isFalse);
    });

    test('een artiestnaam die als titel gevonden werd', () {
      expect(
          klopt('RMB', 'Matisse', r'Latino\Matisse\Matisse - Por Si Te Lo Preguntas.flac'),
          isFalse);
    });

    test('een titel waar de helft van ontbreekt', () {
      expect(
          klopt('Pat Krimson', 'We Will Meet Again',
              r'Pat Krimson\A Sound of Thunder - The Golden Age.flac'),
          isFalse);
    });
  });

  group('DE KERN: het goede bestand komt erdoor', () {
    test('artiest in de map, titel in de naam', () {
      expect(klopt('2 Fabiola', 'Freak Out', r'Eurodance\2 Fabiola\01 - Freak Out.flac'), isTrue);
    });

    test('alles in de naam', () {
      expect(klopt('Cappella', 'Move On Baby', r'Downloads\Cappella - Move On Baby.flac'), isTrue);
    });

    test('een radio-edit mag op een gewone plek — bij eurodance is dat de versie die je kent', () {
      expect(
          klopt('Cappella', 'Move On Baby', r'Singles\Cappella - Move On Baby - Radio Edit.flac'),
          isTrue);
      expect(
          klopt('Cappella', 'Move On Baby', r'Singles\Cappella - Move On Baby (Radio Edit).flac'),
          isTrue);
    });

    test('albumwoorden in de naam als het album in de map staat', () {
      expect(
          klopt('Cappella', 'Move On Baby',
              r'Cappella - U Got 2 Know (1994)\Cappella - U Got 2 Know - 05 - Move On Baby.flac'),
          isTrue);
    });

    test('een jaartal of "Remastered" in de naam maakt het geen ander nummer', () {
      expect(
          klopt('Culture Beat', 'Mr. Vain',
              r'90s\Culture Beat - Mr. Vain 1993 Remastered.flac'),
          isTrue);
    });

    test('een gast in de catalogus hoeft niet in het pad', () {
      expect(
          klopt('2 Fabiola feat. Loredana', 'Lift U Up', r'2 Fabiola\2 Fabiola - Lift U Up.flac'),
          isTrue);
    });

    test('"DJ" en "The" tellen niet als artiestwoord', () {
      expect(klopt('DJ Dado', 'X-Files', r'Dado\X-Files.flac'), isTrue);
    });
  });

  group('DE VAL: originelen, geen mixen', () {
    test('een gewone plek krijgt geen Extended, Club of Remix', () {
      for (final naam in [
        'Magic Flight (Extended Club Mix).flac',
        'Magic Flight (Club Mix).flac',
        'Magic Flight (Brainbug Remix).flac',
        'Magic Flight - Extended Mix.flac',
      ]) {
        expect(klopt('Nalin & Kane', 'Magic Flight', 'Nalin & Kane\\$naam'), isFalse, reason: naam);
      }
    });

    test('maar een plek die om een remix VRAAGT krijgt hem', () {
      expect(
          klopt('2 Fabiola', "Freak Out ('97 Remix)",
              r"2 Fabiola\2 Fabiola - Freak Out ('97 Remix).flac"),
          isTrue);
    });

    test('"live" in "Alive" is geen livenummer', () {
      expect(klopt('Mr. President', 'Alive', r'Mr. President\Alive.flac'), isTrue);
    });

    test('een nieuwe versie met een woord naast de titel is het origineel niet, ook met de map erbij',
        () {
      // Letterlijk het bestand van 26-09-2026: "Turbo" staat ook in de mapnaam, en die verklaarde
      // het tot nu toe weg.
      expect(
          klopt('Scooter', 'Friends (Single Edit)',
              r'Scooter - Friends Turbo\Scooter - Friends Turbo - 02 - Friends Turbo.flac'),
          isFalse);
      expect(klopt('Scooter', 'Friends (Single Edit)', r'Scooter\Scooter - Friends (Single Edit).flac'),
          isTrue);
    });

    test('maar een albumnaam in een eigen stuk mag, net als de artiest ná de titel', () {
      expect(
          klopt('Vanessa Chinitor', 'When The Siren Calls',
              r'Like the Wind\08 - When the siren calls - Vanessa Chinitor - Like the wind.mp3'),
          isTrue);
      expect(klopt('2 Fabiola', 'Flashback', r'x\419-2_fabiola-flashback.flac'), isTrue);
    });

    test('een tv-cover en een maxi zijn het origineel niet', () {
      expect(
          klopt('Pat Krimson', 'Silence',
              r'Pat Krimson\Silence (Uit Liefde Voor Muziek).flac'),
          isFalse);
      expect(klopt('Sash!', 'Mysterious Times', r'Sash!\Mysterious Times (Original Maxi).flac'),
          isFalse);
    });
  });

  group('wat de review van 26-09-2026 op echte namen vond', () {
    test('DE KERN: een weggelaten apostrof of accent is hetzelfde nummer', () {
      expect(klopt('Dr. Alban', "It's My Life", r'Dr. Alban - Its My Life (Radio Edit).mp3'), isTrue);
      expect(klopt('E-Rotic', "Max Don't Have Sex With Your Ex",
          r'E-Rotic - Max Dont Have Sex With Your Ex.mp3'), isTrue);
      expect(klopt('Kate Ryan', 'Désenchantée', r'Kate Ryan - Desenchantee.flac'), isTrue);
      expect(klopt('Mylène Farmer', 'Désenchantée', r'Mylene Farmer - Desenchantee.flac'), isTrue);
    });

    test('DE KERN: een artiest aan elkaar geschreven is dezelfde artiest', () {
      expect(klopt('2 Unlimited', 'No Limit', r'2Unlimited - No Limit.mp3'), isTrue);
      expect(klopt('Mo-Do', 'Eins, Zwei, Polizei', r'Modo - Eins Zwei Polizei.mp3'), isTrue);
      expect(klopt('Captain Hollywood Project', 'More and More', r'Captain Hollywood - More And More.mp3'),
          isTrue);
    });

    test('DE VAL: Robin Schulz is Robin S niet', () {
      expect(
          klopt('Robin S', 'Show Me Love', r'Music\Robin Schulz\Uncovered (2017)\05 - Show Me Love.flac',
              seconden: 255, padSeconden: 269),
          isFalse);
      expect(klopt('Robin S', 'Show Me Love', r'Robin S - Show Me Love (Radio Edit).flac'), isTrue);
    });

    test('DE KERN: de versie van 7" en Single Mix is gewoon, een Rmx niet', () {
      expect(klopt('Haddaway', 'What Is Love', r'Haddaway - What Is Love (7” Mix).flac'), isTrue);
      expect(klopt('Haddaway', 'What Is Love', r'05_haddaway_-_what_is_love_(7_inch_mix).flac'), isTrue);
      expect(klopt('Eiffel 65', 'Blue (Da Ba Dee)', r'Eiffel 65 - Blue (Gabry Ponte Rmx).flac'), isFalse);
      expect(klopt('Haddaway', 'What Is Love', r'Haddaway - What Is Love (Acappella).flac'), isFalse);
    });

    test('DE KERN: een versiewoord in de MAP verraadt het bestand', () {
      expect(klopt('2 Unlimited', 'No Limit', r'2 Unlimited - No Limit (Remixes)\03 - No Limit.flac'),
          isFalse);
      expect(klopt('Scooter', 'Hyper Hyper', r'Scooter\Encore - Live And Direct (2002)\05 - Hyper Hyper.flac'),
          isFalse);
      expect(
          klopt('Haddaway', 'What Is Love',
              r'Karaoke Hits\Karaoke - What Is Love (In the Style of Haddaway).mp3'),
          isFalse);
    });

    test('DE KERN: een cover die alleen in de bestandsnaam staat, ook', () {
      expect(klopt('Haddaway', 'What Is Love', r'Haddaway Hits\What Is Love (Made Famous by Haddaway).mp3'),
          isFalse);
    });

    test('DE VAL: de band Live in de mapnaam is geen live-opname', () {
      expect(klopt('Live', 'Lightning Crashes', r'Live - Throwing Copper (1994)\05 - Lightning Crashes.flac'),
          isTrue);
    });

    test('DE VAL: maar "Alive" in de map is geen live, en een verzamelaar mag', () {
      expect(klopt('Mr. President', 'Coco Jamboo', r'Mr. President - Alive (1997)\01 - Coco Jamboo.flac'),
          isTrue);
      expect(
          klopt('Culture Beat', 'Mr. Vain',
              r'Dance Mix 94\CD1\05. Culture Beat - Mr. Vain (Original Radio Edit).flac'),
          isTrue);
    });

    test('DE GRENS: een remix in de TAGS van een gewone plek spreekt het tegen', () {
      expect(radioTagsSprekenTegen('Eiffel 65', 'Blue (Da Ba Dee)',
          tags('Eiffel 65', 'Blue (Da Ba Dee) (Hannover Rmx)')), isTrue);
      expect(radioTagsSprekenTegen('Eiffel 65', 'Blue (Da Ba Dee)',
          tags('Eiffel 65', 'Blue (Da Ba Dee) (Video Edit)')), isFalse);
    });

    test('DE GRENS: de echte lengte na het halen', () {
      expect(radioLengteSpreektTegen(220, 291), isTrue, reason: 'Move On Baby: album voor single');
      expect(radioLengteSpreektTegen(220, 232), isFalse);
      expect(radioLengteSpreektTegen(null, 291), isFalse);
      expect(radioLengteSpreektTegen(220, null), isFalse);
    });
  });

  group('DE GRENS: de lengte', () {
    test('Move On Baby: de albumversie van 4:51 is de single van 3:40 niet', () {
      expect(
          klopt('Cappella', 'Move On Baby', r'Cappella\Move On Baby.flac',
              seconden: 220, padSeconden: 291),
          isFalse);
    });

    test('een paar seconden verschil is dezelfde opname', () {
      expect(
          klopt('Cappella', 'Move On Baby', r'Cappella\Move On Baby.flac',
              seconden: 220, padSeconden: 232),
          isTrue);
      expect(
          klopt('Cappella', 'Move On Baby', r'Cappella\Move On Baby.flac',
              seconden: 220, padSeconden: 236),
          isFalse,
          reason: 'zestien seconden is meer dan de speling van vijftien');
    });

    test('zonder lengte aan een van beide kanten telt de lengte niet', () {
      expect(klopt('Cappella', 'Move On Baby', r'Cappella\Move On Baby.flac', padSeconden: 291),
          isTrue);
      expect(klopt('Cappella', 'Move On Baby', r'Cappella\Move On Baby.flac', seconden: 220),
          isTrue);
    });
  });

  group('het tweede net: de tags na het halen', () {
    test('DE KERN: een andere artiest of titel in de tags spreekt het tegen', () {
      expect(radioTagsSprekenTegen('Pat Krimson', 'When The Lights Go Down',
          tags('Boondox', 'K7-Lethal')), isTrue);
      expect(radioTagsSprekenTegen('RMB', 'Redemption',
          tags('RMB', 'Por Si Te Lo Preguntas')), isTrue);
    });

    test('DE KERN: dezelfde titel van een andere artiest spreekt het ook tegen', () {
      // Het echte geval: een bestand dat "I'm on Fire" heette, en van Porter Robinson was.
      expect(radioTagsSprekenTegen("2 Fabiola", "I'm on Fire",
          tags('Porter Robinson', "I'm On Fire (Original Mix)")), isTrue);
    });

    test('DE VAL: dezelfde artiest en titel, anders geschreven, spreekt niets tegen', () {
      expect(radioTagsSprekenTegen('2 Fabiola', 'Freak Out',
          tags('2 Fabiola feat. Loredana', 'Freak Out (Radio Edit)')), isFalse);
      expect(radioTagsSprekenTegen('Culture Beat', 'Mr. Vain - Radio Edit',
          tags('CULTURE BEAT', 'Mr Vain')), isFalse);
    });

    test('DE KERN: een bestand zonder artiest of titel krijgt ze van de radio', () {
      expect(radioTagsOntbreken(null), isTrue);
      expect(radioTagsOntbreken(tags('', 'Got To Move Your Body')), isTrue);
      expect(radioTagsOntbreken(tags('Lick', '  ')), isTrue);
      expect(radioTagsOntbreken(tags('The Mackenzie', 'Innocence')), isFalse,
          reason: 'wat er wél staat blijft staan');
    });

    test('DE GRENS: zonder tags valt er niets tegen te spreken', () {
      expect(radioTagsSprekenTegen('RMB', 'Redemption', null), isFalse);
      expect(radioTagsSprekenTegen('RMB', 'Redemption', tags('', '')), isFalse);
    });
  });
}

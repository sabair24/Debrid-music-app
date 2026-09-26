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

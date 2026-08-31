/// "Heb ik deze opname al?" — en waarom die vraag ruimer mag zijn dan "zijn deze twee dubbel?".
///
/// **Waarom dit bestaat.** De app houdt een verlanglijst bij van nummers waarvan een mp3 speelt en de
/// FLAC nog moet komen, en loopt die elke twintig minuten af. Een wens vervalt zodra de FLAC in de
/// bibliotheek staat — maar dat werd op de kale tekst vergeleken, en dan is
/// `Drunk in Love (feat. JAY-Z)` iets anders dan `Drunk in Love`. Gevolg: de app blijft jagen op een
/// bestand dat er allang staat, en biedt het bovendien aan om te downloaden.
///
/// Geteld in de bibliotheek op 29-08-2026: 22 bestanden met een `feat.`-toevoeging en 27 met een
/// remaster- of album-version-aanduiding. De voorbeelden hieronder zijn er letterlijk uit overgenomen.
///
/// De grens is de andere kant op net zo belangrijk. Deze sleutel mag NOOIT zeggen "die heb je al"
/// over een andere opname: dan stopt de app met zoeken en merkt niemand het. Vandaar dat elk echt
/// versiemerk blijft scheiden, en dat de lijst neutrale merken kort is.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/organize.dart';

void main() {
  bool zelfde(String a1, String t1, String a2, String t2) =>
      opnameSleutel(a1, t1) == opnameSleutel(a2, t2);

  group('gastartiesten tellen niet mee', () {
    test('in de titel, tussen haakjes — uit de echte bibliotheek', () {
      expect(zelfde('Beyoncé', 'Drunk in Love (feat. JAY-Z)', 'Beyoncé', 'Drunk in Love'), isTrue);
      expect(zelfde('Justin Timberlake', 'Suit & Tie [Feat. Jay-Z]', 'Justin Timberlake', 'Suit & Tie'),
          isTrue);
      expect(zelfde('Missy Elliott', 'Gossip Folks (feat. Ludacris)', 'Missy Elliott', 'Gossip Folks'),
          isTrue);
    });

    test('en in de artiest', () {
      expect(zelfde('Shakira feat. Burna Boy', 'Whenever', 'Shakira', 'Whenever'), isTrue);
      expect(zelfde('Lil Kim ft. Phil Collins', 'In the Air Tonite', 'Lil Kim', 'In the Air Tonite'),
          isTrue);
    });

    test('maar "with" middenin een titel blijft staan', () {
      // Anders verliest "Sing With Me" zijn halve naam en valt hij samen met "Sing".
      expect(zelfde('X', 'Sing With Me', 'X', 'Sing'), isFalse);
    });
  });

  group('haakjes die alleen over de uitgave gaan', () {
    test('een remaster is dezelfde opname', () {
      expect(zelfde('Reboot', 'Caminando (2017 REMASTER)', 'Reboot', 'Caminando'), isTrue);
      expect(zelfde('Fleetwood Mac', 'Second Hand News (2004 Remaster)', 'Fleetwood Mac',
          'Second Hand News'), isTrue);
      expect(zelfde('A', 'B (Remastered)', 'A', 'B'), isTrue);
      expect(zelfde('A', 'B (Digitally Remastered)', 'A', 'B'), isTrue);
    });

    test('"Album Version" en "Original Mix" ook', () {
      expect(zelfde('Michael Jackson', 'Scream (Album Version)', 'Michael Jackson', 'Scream'), isTrue);
      expect(zelfde('X', 'Transfiguration (Original Mix)', 'X', 'Transfiguration'), isTrue);
    });
  });

  group('DE GRENS: een andere opname blijft een andere opname', () {
    test('live, remix, radio edit, instrumentaal', () {
      expect(zelfde('X', 'Trein (instrumental)', 'X', 'Trein'), isFalse);
      expect(zelfde('X', 'Children (Live)', 'X', 'Children'), isFalse);
      expect(zelfde('X', 'Umbrella (Radio Edit)', 'X', 'Umbrella'), isFalse);
      expect(zelfde('X', 'One More Time (Club Mix)', 'X', 'One More Time'), isFalse);
      expect(zelfde('X', 'Shout (Extended Version)', 'X', 'Shout'), isFalse);
      expect(zelfde('X', 'Fable (Dream Version)', 'X', 'Fable'), isFalse);
    });

    test('een remix MET een gastartiest blijft ook een remix', () {
      // Uit de bibliotheek: "MORNING DEW (DONK) REMIX FEAT JAŸ-Z". De gast valt weg, de remix niet.
      expect(zelfde('X', 'Morning Dew Remix feat Jay-Z', 'X', 'Morning Dew'), isFalse);
      expect(zelfde('X', 'Morning Dew Remix feat Jay-Z', 'X', 'Morning Dew Remix'), isTrue);
    });

    test('en een ander nummer van dezelfde artiest al helemaal', () {
      expect(zelfde('Daft Punk', 'Aerodynamic', 'Daft Punk', 'Digital Love'), isFalse);
      expect(zelfde('Daft Punk', 'One More Time', 'Justice', 'One More Time'), isFalse);
    });
  });

  group('en wat de oude sleutel al kon blijft werken', () {
    test('accenten vallen samen', () {
      expect(zelfde('Beyoncé', 'Halo', 'Beyonce', 'Halo'), isTrue);
      expect(zelfde('Céline Dion', "S'il suffisait d'aimer", 'Celine Dion', "S'il suffisait d'aimer"),
          isTrue);
    });

    test('leestekens worden spaties — en dat is een BEKENDE ondergrens', () {
      // `AC/DC` wordt "ac dc" en `ACDC` blijft "acdc": die twee vinden elkaar niet. Dat zit in
      // `normKey` en geldt voor de hele app, niet alleen hier. Het staat vastgelegd omdat het een
      // grens is die je moet kennen, niet omdat het goed is: wie hem wil oprekken moet weten dat
      // spaties weglaten ook titels samenvoegt die niets met elkaar te maken hebben.
      expect(zelfde('AC/DC', 'T.N.T.', 'ACDC', 'TNT'), isFalse);
      // Wat wél werkt: hetzelfde leesteken aan beide kanten.
      expect(zelfde('AC/DC', 'T.N.T.', 'AC-DC', 'T N T'), isTrue);
    });

    test('hoofdletters en dubbele spaties', () {
      expect(zelfde('DAFT PUNK', 'One  More   Time', 'daft punk', 'One More Time'), isTrue);
    });
  });

  group('strenger blijft strenger waar dat hoort', () {
    test('trackIdentity scheidt nog steeds wat opnameSleutel samenvoegt', () {
      // Dit is met opzet zo. `trackIdentity` beslist of twee BESTANDEN dubbel zijn — daar hoort geen
      // ruimte, want wie te ruim vergelijkt gooit een opname weg die je wilde houden.
      expect(trackIdentity('Beyoncé', 'Drunk in Love (feat. JAY-Z)'),
          isNot(trackIdentity('Beyoncé', 'Drunk in Love')));
      expect(opnameSleutel('Beyoncé', 'Drunk in Love (feat. JAY-Z)'),
          opnameSleutel('Beyoncé', 'Drunk in Love'));
    });
  });
}

/// De plek op de plaat is geen artiestnaam — maar sommige artiesten heten wél zo.
///
/// Gemeld op 04-09-2026: het album *X* van INXS stond er als "1 nummers", en "Suicide Blonde" —
/// kant A, nummer 1 — werd gemeld als een nummer dat niet op die uitgave staat. Beide klachten
/// kwamen uit één ding: `ARTIST=A1.INXS`, waardoor elk nummer zijn eigen "artiest" had en de plaat
/// uiteenviel in losse tegels.
///
/// Het gevaar van de reparatie is niet dat hij te weinig opruimt maar te veel. A1, D12, B12, H2O en
/// B2K zijn echte namen, en die halveren is een fout die je pas merkt als een groep verdwenen is
/// onder een naam die je niet kent. Daarom staan ze hier allemaal.
import 'package:debridmusic/kantnummer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('de plek op de plaat gaat eraf', () {
    test('het gemelde geval', () {
      expect(zonderKantnummer('A1.INXS'), 'INXS');
    });

    test('elke kant en elk scheidingsteken dat rippers gebruiken', () {
      expect(zonderKantnummer('A1. INXS'), 'INXS');
      expect(zonderKantnummer('A2 INXS'), 'INXS');
      expect(zonderKantnummer('B1 - INXS'), 'INXS');
      expect(zonderKantnummer('B12_INXS'), 'INXS');
      expect(zonderKantnummer('C3) INXS'), 'INXS');
      expect(zonderKantnummer('D4: INXS'), 'INXS');
      // Kleine letters, want de ene ripper schrijft het zo en de andere zo.
      expect(zonderKantnummer('a1.inxs'), 'inxs');
    });

    test('de kanten van een dubbelalbum', () {
      for (final kant in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H']) {
        expect(zonderKantnummer('${kant}1.INXS'), 'INXS', reason: 'kant $kant');
      }
      // De 12"-kanten die met twee letters geschreven worden.
      expect(zonderKantnummer('AA1.INXS'), 'INXS');
      expect(zonderKantnummer('BB2.INXS'), 'INXS');
    });

    test('spaties eromheen doen niet mee', () {
      expect(zonderKantnummer('  A1.INXS  '), 'INXS');
    });

    test('een naam van meerdere woorden blijft heel', () {
      expect(zonderKantnummer('A1.Depeche Mode'), 'Depeche Mode');
      expect(zonderKantnummer('B3 - The Rolling Stones'), 'The Rolling Stones');
    });
  });

  group('echte namen blijven staan', () {
    test('een naam die alleen uit een letter en een cijfer bestaat', () {
      // Dit is de hele reden dat er een scheidingsteken moet staan. A1 is een Britse groep, D12 een
      // Amerikaanse; halveren kan hier niet eens, maar wissen wél als de regel losser zou zijn.
      for (final naam in ['A1', 'D12', 'B12', 'C2', 'H8']) {
        expect(zonderKantnummer(naam), naam, reason: naam);
      }
    });

    test('een naam waar het cijfer middenin staat', () {
      // Geen scheidingsteken achter het cijfer, dus dit is één naam en geen plek op een plaat.
      for (final naam in ['H2O', 'B2K', 'B1A4', 'D12x', 'A1B2']) {
        expect(zonderKantnummer(naam), naam, reason: naam);
      }
    });

    test('een kantletter die niet bestaat', () {
      // Verder dan H komt geen plaat. Elke letter erbij is een echte naam die we kapot kunnen maken.
      for (final naam in ['S1.Music', 'M1 - Blackout', 'T2 Featuring Jodie', 'Z1.Iets']) {
        expect(zonderKantnummer(naam), naam, reason: naam);
      }
    });

    test('een gewone artiest zonder cijfers', () {
      for (final naam in ['INXS', 'Missy Elliott', 'Beyoncé', 'The Rolling Stones']) {
        expect(zonderKantnummer(naam), naam, reason: naam);
      }
    });

    test('wat overblijft moet op een naam lijken', () {
      // Anders zou "A1.2" een artiest worden die "2" heet.
      expect(zonderKantnummer('A1.2'), 'A1.2');
      expect(zonderKantnummer('A1.X'), 'A1.X'); // te kort om een naam te zijn
      expect(zonderKantnummer('A1.'), 'A1.');
      expect(zonderKantnummer('A1 '), 'A1');
    });

    test('leeg blijft leeg', () {
      expect(zonderKantnummer(''), '');
      expect(zonderKantnummer('   '), '');
    });

    test('twee of meer cijfers achter elkaar zijn geen plek meer', () {
      // Kant A nummer 123 bestaat niet; dit is een naam.
      expect(zonderKantnummer('A123.Iets'), 'A123.Iets');
    });
  });

  group('de plaat komt weer bij elkaar', () {
    test('twaalf verschillende "artiesten" worden er weer één', () {
      // Dit is precies wat de bibliotheek deed struikelen: elk van deze regels was voor het
      // groeperen een andere artiest, en dus een andere plaat.
      const rauw = [
        'A1.INXS', 'A2.INXS', 'A3.INXS', 'A4.INXS', 'A5.INXS', 'A6.INXS',
        'B1.INXS', 'B2.INXS', 'B3.INXS', 'B4.INXS', 'B5.INXS', 'B6.INXS',
      ];
      expect(rauw.map(zonderKantnummer).toSet(), {'INXS'});
    });

    test('een bestand dat de artiest wél goed had hoort in dezelfde groep', () {
      // Op het scherm stonden ze naast elkaar: de albumpagina zei INXS, de balk eronder A1.INXS.
      expect(zonderKantnummer('A1.INXS'), zonderKantnummer('INXS'));
    });
  });
  artiestUitNaam();
  titelUitNaam();
}

/// De titel die uit een BESTANDSNAAM komt, zonder de plek op de plaat ervoor.
///
/// Gevonden bij het doorlichten van de bibliotheek op 05-09-2026: zes bestanden zónder enige tag
/// stonden als "B3. Mary Jane", "G1. Tiesto feat. Kirsty Hawkshaw - Just Be" en "08. Enzo - opzij
/// opzij" in de lijst. De app leidt de titel dan uit de bestandsnaam af, inclusief de kant.
void titelUitNaam() {
  group('titelUitBestandsnaam', () {
    test('DE KERN: de gevallen uit de bibliotheek', () {
      expect(titelUitBestandsnaam('B3. Mary Jane'), 'Mary Jane');
      expect(titelUitBestandsnaam('B1. Fair Game'), 'Fair Game');
      expect(titelUitBestandsnaam('G1. Tiesto feat. Kirsty Hawkshaw - Just Be'),
          'Tiesto feat. Kirsty Hawkshaw - Just Be');
      expect(titelUitBestandsnaam('08. Enzo - opzij opzij'), 'Enzo - opzij opzij');
    });

    test('DE GRENS: een titel zonder scheidingsteken blijft heel', () {
      // Het scheidingsteken is de hele veiligheid, net als bij zonderKantnummer.
      expect(titelUitBestandsnaam('99 Luftballons'), '99 Luftballons');
      expect(titelUitBestandsnaam('7 Seconds'), '7 Seconds');
      expect(titelUitBestandsnaam('B2 Unit'), 'B2 Unit');
    });

    test('en wat overblijft moet op een naam lijken', () {
      expect(titelUitBestandsnaam('A1.2'), 'A1.2');
      expect(titelUitBestandsnaam('01. 2'), '01. 2');
    });

    test('een gewone titel verandert niet', () {
      for (final t in ['Mary Jane', 'Just Be', 'Smooth Criminal', '']) {
        expect(titelUitBestandsnaam(t), t, reason: t);
      }
    });
  });
}

/// Artiest én titel uit een bestandsnaam, voor bestanden die GEEN artiest hebben.
///
/// Gemeten op 05-09-2026: 8 van de 1255 bestanden hebben er geen, en vier daarvan dragen hem gewoon
/// in hun naam. Zonder artiest kan zo'n bestand nergens bij horen — niet gegroepeerd, geen hoes, op
/// geen enkele tracklijst te vinden. Een naam uit de bestandsnaam is dan geen gok tegenover een
/// feit, maar een gok tegenover niets.
void artiestUitNaam() {
  group('artiestEnTitelUitBestandsnaam', () {
    test('DE KERN: de vier gevallen uit de bibliotheek', () {
      expect(artiestEnTitelUitBestandsnaam('G1. Tiesto feat. Kirsty Hawkshaw - Just Be'),
          (artiest: 'Tiesto feat. Kirsty Hawkshaw', titel: 'Just Be'));
      expect(artiestEnTitelUitBestandsnaam('B1. Tiesto feat. BT - Love Comes Again'),
          (artiest: 'Tiesto feat. BT', titel: 'Love Comes Again'));
      expect(artiestEnTitelUitBestandsnaam('08. Enzo - opzij opzij'),
          (artiest: 'Enzo', titel: 'opzij opzij'));
      expect(
          artiestEnTitelUitBestandsnaam(
              "Alex Carrena, Franck Minaro & Fily - Don't Lose Your Mind (Rachel Ellektra Epic Mix)"),
          (
            artiest: 'Alex Carrena, Franck Minaro & Fily',
            titel: "Don't Lose Your Mind (Rachel Ellektra Epic Mix)"
          ));
    });

    test('DE GRENS: op de EERSTE streep, niet de laatste', () {
      // "Artiest - Titel - Remix" is een titel met een streepje erin, geen artiest die
      // "Artiest - Titel" heet.
      expect(artiestEnTitelUitBestandsnaam('Moby - Porcelain - Radio Edit'),
          (artiest: 'Moby', titel: 'Porcelain - Radio Edit'));
    });

    test('een koppelteken in een naam doet niets', () {
      // Spaties rondom de streep zijn verplicht.
      expect(artiestEnTitelUitBestandsnaam('Jean-Jacques Goldman'), isNull);
      expect(artiestEnTitelUitBestandsnaam('Mary Jane'), isNull);
    });

    test('en allebei de helften moeten op een naam lijken', () {
      expect(artiestEnTitelUitBestandsnaam('A - B'), isNull);
      expect(artiestEnTitelUitBestandsnaam('12 - 34'), isNull);
    });
  });
}

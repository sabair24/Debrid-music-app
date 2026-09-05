/// De nummering mag een albumversie nooit het nummer van een remix geven.
///
/// **Gemeld op 05-09-2026** met een schermafdruk van "Nummering overnemen" op Christina Milians
/// *Dip It Low (Mixes)*. Voorgesteld werd:
///
///     2 → 1   Dip It Low (Full Intention Dub)
///     2 → 2   Dip It Low (Full Intention Club)
///
/// Saber heeft die twee remixen niet. Hij heeft de albumversie (3:14) en die met Fabolous (3:38),
/// allebei getagd als kaal "Dip It Low". Zijn reactie: *"hij haalt overal die 2 zelfde titels."*
///
/// **De oorzaak was een tweede antwoord op één vraag.** [matchOfficial] scoorde op woordgelijkenis
/// plus een looptijdbonus en kende géén regel over versiemerken; `sameTitle` in `completeness.dart`
/// kende die regel wél. Drie gedeelde woorden van de zes is 0,50, plus 0,25 omdat de looptijden
/// toevallig dicht bij elkaar lagen — 0,75, ruim boven de drempel van 0,55. De doc-comment van
/// [matchOfficial] beloofde nota bene dat album-download en nummeringsdialoog het eens zijn over wat
/// hetzelfde nummer is. Dat was niet zo; nu wel, via [zelfdeVersiemerken].
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/editions.dart';
import 'package:debridmusic/organize.dart';

/// De persing uit de schermafdruk: vier nummers, waarvan twee remixen.
const mixes = [
  ChoiceTrack('1', 'Dip It Low (Full Intention Dub)', 200),
  ChoiceTrack('2', 'Dip It Low (Full Intention Club)', 220),
  ChoiceTrack('3', 'Dip It Low', 198),
  ChoiceTrack('4', 'Dip It Low', 220),
];

void main() {
  group('matchOfficial laat versiemerken meetellen', () {
    test('DE KERN: een kale titel wordt nooit een remix', () {
      // 194s ligt binnen twaalf seconden van de Dub (200s), dus de looptijd pleitte er zelfs vóór.
      final hit = matchOfficial(
          const [ChoiceTrack('1', 'Dip It Low (Full Intention Dub)', 200)], 'Dip It Low', 194);
      expect(hit, isNull);
    });

    test('en hij kiest de kale rij als die er is', () {
      final hit = matchOfficial(mixes, 'Dip It Low', 194);
      expect(hit?.title, 'Dip It Low');
      expect(hit?.position, '3', reason: 'de rij van 198s, niet die van 220s');
    });

    test('een remix die je WEL hebt vindt zijn eigen rij', () {
      // De regel snijdt beide kanten op: hij weigert niet alles met haakjes.
      final hit = matchOfficial(mixes, 'Dip It Low (Full Intention Club)', 219);
      expect(hit?.position, '2');
    });

    test('een nepmerk blijft doorgelaten', () {
      // "(Album Version)" is geen ander nummer. `versionMarkers` zeeft die al weg, en dat moet zo
      // blijven — anders kost deze regel treffers in plaats van dat hij ze redt.
      final hit =
          matchOfficial(const [ChoiceTrack('1', 'Escape', 240)], 'Escape (Album Version)', 240);
      expect(hit?.title, 'Escape');
    });

    test('en een tikfout in een merk blijft vergeven', () {
      // Technotronic: de persing schrijft "(Morales Spinster mix)", de rip "(Morales Spineter Mix)".
      final hit = matchOfficial(
          const [ChoiceTrack('2', 'Trip on This (Morales Spinster mix)', 300)],
          'Trip on This (Morales Spineter Mix)',
          300);
      expect(hit, isNotNull);
    });
  });

  group('zelfdeVersiemerken', () {
    test('kaal tegen een merk is niet hetzelfde', () {
      expect(zelfdeVersiemerken('Dip It Low', 'Dip It Low (Full Intention Dub)'), isFalse);
    });

    test('twee verschillende merken ook niet', () {
      expect(
          zelfdeVersiemerken(
              'Dip It Low (Full Intention Dub)', 'Dip It Low (Full Intention Club)'),
          isFalse);
    });

    test('hetzelfde merk wel, ongeacht de schrijfwijze van de haakjes', () {
      expect(zelfdeVersiemerken('Song (Radio Edit)', 'Song [radio edit]'), isTrue);
    });

    test('en een nepmerk telt niet mee', () {
      expect(zelfdeVersiemerken('Escape (Album Version)', 'Escape'), isTrue);
    });

    test('"mix" en "remix" blijven verschillend', () {
      // Te kort om een tikfout in te herkennen, en het verschil is echt.
      expect(zelfdeVersiemerken('Song (Club Mix)', 'Song (Club Remix)'), isFalse);
    });
  });
  mainVersion();
}

/// "(Main Version)" is de gewone plaatopname, geen aparte versie.
///
/// Gevonden bij het doorlichten van de hele bibliotheek op 05-09-2026: Britney Spears' *Blackout*
/// komt als "Gimme More (Main Version)", "Piece of Me (Main Version)" en "Radar (Main Version)",
/// terwijl de persing ze kaal noemt. Alle drie stonden ze onder "Niet op deze uitgave". Na deze
/// wijziging: 144 losse bestanden in de bibliotheek werden er 141.
void mainVersion() {
  group('(Main Version) is geen ander nummer', () {
    test('DE KERN: hij vindt de kale rij', () {
      expect(zelfdeVersiemerken('Gimme More (Main Version)', 'Gimme More'), isTrue);
      expect(matchOfficial(const [ChoiceTrack('1', 'Gimme More', 250)],
              'Gimme More (Main Version)', 250)
          ?.title,
          'Gimme More');
    });

    test('DE GRENS: "(Main Mix)" blijft wél een aparte versie', () {
      // In dansmuziek is de main mix één specifieke mix naast de radio-edit en de dub — zie
      // "Los Chicanos (Main Mix)" in diezelfde doorlichting.
      expect(zelfdeVersiemerken('Los Chicanos (Main Mix)', 'Los Chicanos'), isFalse);
    });

    test('en de rest van de merken verandert niet', () {
      expect(zelfdeVersiemerken('Song (Single Version)', 'Song'), isFalse);
      expect(zelfdeVersiemerken('Song (Original Mix)', 'Song'), isFalse);
      expect(zelfdeVersiemerken('Song (Album Version)', 'Song'), isTrue);
    });
  });
}

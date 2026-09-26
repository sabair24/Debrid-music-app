/// Het taalmodel als samensteller: wat er van zijn voorstel geloofd wordt.
///
/// Saber op 26-09-2026: de radio mocht niet langer alleen op Deezer leunen. Het model noemt nu
/// concrete nummers; deze toetsen houden vast dat alleen wat bestaat, in de juiste uitvoering,
/// erdoor komt.
library;

import 'package:debridmusic/aanbevelingplan.dart' show SmaakProfiel;
import 'package:debridmusic/radiolijst.dart';
import 'package:debridmusic/radiosmaak.dart';
import 'package:flutter_test/flutter_test.dart';

typedef T = ({String artiest, String titel, int rang, int seconden});

void main() {
  group('het antwoord lezen', () {
    test('DE KERN: dubbels, lege titels en zinnen als artiest vallen weg', () {
      final uit = leesNummers({
        'nummers': [
          {'artiest': 'Cappella', 'titel': 'Move On Baby', 'jaar': 1994, 'bekend': true},
          {'artiest': 'CAPPELLA', 'titel': 'Move on baby!', 'jaar': 1994, 'bekend': true},
          {'artiest': 'Dune', 'titel': '', 'jaar': 1995, 'bekend': false},
          {'artiest': 'Lionel Richie is al genoemd: Al Jarreau', 'titel': 'X', 'jaar': 1985},
          {'artiest': 'T-Spoon', 'titel': 'Sex on the Beach', 'jaar': '1997', 'bekend': false},
        ],
      });
      expect([for (final n in uit) '${n.artiest} — ${n.titel}'],
          ['Cappella — Move On Baby', 'T-Spoon — Sex on the Beach']);
      expect(uit.last.jaar, 1997, reason: 'een jaartal als tekst wordt gelezen');
      expect(uit.first.bekend, isTrue);
    });

    test('DE VAL: een jaartal dat er geen is valt weg, het nummer niet', () {
      final uit = leesNummers({
        'nummers': [
          {'artiest': 'Dune', 'titel': 'Hardcore Vibes', 'jaar': 95, 'bekend': false},
        ],
      });
      expect(uit.single.jaar, isNull);
    });

    test('DE GRENS: nooit meer dan het plafond, en onzin is een lege lijst', () {
      final veel = {
        'nummers': [
          for (var i = 0; i < 100; i++) {'artiest': 'A$i', 'titel': 'T$i', 'jaar': 1995, 'bekend': false}
        ],
      };
      expect(leesNummers(veel), hasLength(kMaxModelNummers));
      expect(leesNummers('geen json'), isEmpty);
      expect(leesNummers({'nummers': 'geen lijst'}), isEmpty);
    });
  });

  group('de vraag', () {
    const profiel = SmaakProfiel(
        topArtiesten: ['Beyoncé (40)'], perDecennium: {2010: 500}, gespeeld: ['Scooter'], genres: []);

    test('DE KERN: het zaad mét wat Discogs ervan weet, en de stijl eerst', () {
      final v = nummersPrompt(
          artiest: '2 Fabiola',
          titel: "Freak Out ('97 Remix)",
          jaar: 1997,
          stijlen: ['Euro House', 'Trance'],
          profiel: profiel);
      expect(v, contains("2 Fabiola - Freak Out ('97 Remix) (uit 1997, stijl Euro House, Trance)"));
      expect(v, contains('Blijf in het genre en het tijdvak van DIT'));
      expect(v, contains('geen remixen'));
      expect(v, contains('Hoogstens twee nummers van 2 Fabiola'));
      expect(v, contains('niet om de stijl te kiezen'),
          reason: 'het profiel trok de radio op 26-09-2026 naar Donna Summer en Dimitri Vegas');
    });

    test('DE KERN: Bekend en Ontdekken vragen iets anders', () {
      final bekend = nummersPrompt(artiest: 'X', profiel: profiel, smaak: Radiosmaak.bekend);
      final ontdekken = nummersPrompt(artiest: 'X', profiel: profiel, smaak: Radiosmaak.ontdekken);
      expect(bekend, contains('hits die iedereen'));
      expect(ontdekken, contains('NIET de grootste hits'));
    });

    test('DE GRENS: wat al op de radio staat wordt genoemd, en anders niet', () {
      expect(nummersPrompt(artiest: 'X', profiel: profiel, alGekozen: ['Cappella - Move On Baby']),
          contains('Cappella - Move On Baby'));
      expect(nummersPrompt(artiest: 'X', profiel: profiel), isNot(contains('staan al op de radio')));
    });

    test('DE GRENS: het schema zonder getalgrenzen — de API weigert die', () {
      final s = nummersSchema().toString();
      expect(s, isNot(contains('minimum')));
      expect(s, isNot(contains('maxItems')));
    });
  });

  group('welke Deezer-treffer het is', () {
    // Uit de review van 26-09-2026 op echte Deezer-antwoorden: bij 9 van 25 bekende hits koos de
    // radio de albumversie, een remix of een latere heropname, terwijl de single ertussen stond.
    test('DE KERN: de single gaat voor de albumversie met dezelfde kale titel', () {
      final t = <T>[
        (artiest: 'Culture Beat', titel: 'Mr. Vain', rang: 626305, seconden: 336),
        (artiest: 'Culture Beat', titel: 'Mr. Vain (Original Radio Edit)', rang: 400000, seconden: 257),
      ];
      expect(besteTreffer(t, 'Culture Beat', 'Mr. Vain'), 1);
    });

    test('DE KERN: een heropname, een Rmx en een "Reloaded" zijn het origineel niet', () {
      final t = <T>[
        (artiest: 'Haddaway', titel: 'What Is Love - Reloaded (Radio Edit)', rang: 900000, seconden: 178),
        (artiest: 'Haddaway', titel: 'What Is Love (7” Mix)', rang: 800000, seconden: 267),
      ];
      expect(besteTreffer(t, 'Haddaway', 'What Is Love'), 1,
          reason: 'de 7” Mix met een gekrulde ” is de single; Reloaded is een remake');
      final blue = <T>[
        (artiest: 'Eiffel 65', titel: 'Blue (Da Ba Dee) (Hannover Rmx)', rang: 900000, seconden: 383),
        (artiest: 'Eiffel 65', titel: 'Blue (Da Ba Dee) (Video Edit)', rang: 700000, seconden: 220),
      ];
      expect(besteTreffer(blue, 'Eiffel 65', 'Blue (Da Ba Dee)'), 1);
      final alban = <T>[
        (artiest: 'Dr. Alban', titel: "It's My Life (2011 Version)", rang: 900000, seconden: 240),
        (artiest: 'Dr. Alban', titel: "It's My Life (Radio Edit)", rang: 500000, seconden: 240),
      ];
      expect(besteTreffer(alban, 'Dr. Alban', "It's My Life"), 1);
    });

    test('DE KERN: gewoon en radio zijn even goed — de bekendste van de juiste lengte wint', () {
      final t = <T>[
        (artiest: 'Double Vision', titel: 'All Right (Radio Version)', rang: 181627, seconden: 227),
        (artiest: 'Double Vision', titel: 'All Right', rang: 200233, seconden: 358),
        (artiest: 'Double Vision', titel: 'All Right - Radio Edit', rang: 200000, seconden: 227),
      ];
      expect(besteTreffer(t, 'Double Vision', 'All Right'), 2);
    });

    test('DE VAL: bestaat het alleen als remix of als cover, dan is het niets', () {
      expect(
          besteTreffer(<T>[(artiest: 'Cappella', titel: 'Move On Baby (Extended Mix)', rang: 9, seconden: 391)],
              'Cappella', 'Move On Baby'),
          isNull,
          reason: 'het model vroeg het origineel; een remix is dan geen treffer maar een vergissing');
      expect(
          besteTreffer(<T>[
            (artiest: 'Double Vision', titel: 'All Right (Originally Performed By Double Vision)', rang: 9, seconden: 223)
          ], 'Double Vision', 'All Right'),
          isNull);
    });

    test('DE KERN: een obscure live-opname van single-lengte wint niet van de bekende versie', () {
      // Kwaliteitscontrole van 26-09-2026: "Stayin' Alive" uit Tokio (3:55, rang 29.823) won van de
      // Saturday Night Fever-versie (rang 722.791), alleen omdat hij korter was.
      final t = <T>[
        (artiest: 'Bee Gees', titel: "Stayin' Alive", rang: 29823, seconden: 235),
        (artiest: 'Bee Gees', titel: "Stayin' Alive", rang: 722791, seconden: 285),
      ];
      expect(besteTreffer(t, 'Bee Gees', "Stayin' Alive"), 1);
    });

    test('DE KERN: een onbekende toevoeging verliest van de radio-edit', () {
      final t = <T>[
        (artiest: 'Mo-Do', titel: 'Eins, Zwei, Polizei (Einstein Dr. Dj Konzept)', rang: 189368, seconden: 242),
        (artiest: 'Mo-Do', titel: 'Eins, Zwei, Polizei (Radio Edit)', rang: 144731, seconden: 202),
      ];
      expect(besteTreffer(t, 'Mo-Do', 'Eins, Zwei, Polizei'), 1);
    });

    test('DE VAL: alleen een lange versie is beter dan niets', () {
      final t = <T>[(artiest: 'Faithless', titel: 'Insomnia', rang: 9, seconden: 526)];
      expect(besteTreffer(t, 'Faithless', 'Insomnia'), 0);
    });

    test('DE KERN: een verzonnen titel vindt niets', () {
      final t = <T>[(artiest: 'Cappella', titel: 'U Got 2 Know', rang: 900, seconden: 240)];
      expect(besteTreffer(t, 'Cappella', 'Move Your Body Baby'), isNull);
    });

    test('DE VAL: een duo onder één naam is hetzelfde nummer — Robin Schulz is Robin S niet', () {
      expect(
          besteTreffer(<T>[
            (artiest: 'Niels Destadsbader', titel: 'De Wereld Draait Voor Jou', rang: 1, seconden: 200)
          ], 'Niels Destadsbader & Regi', 'De Wereld Draait Voor Jou'),
          0);
      expect(
          besteTreffer(<T>[(artiest: 'SNAP!', titel: 'Rhythm Is a Dancer', rang: 1, seconden: 225)], 'Snap!',
              'Rhythm Is a Dancer'),
          0);
      expect(
          besteTreffer(<T>[(artiest: 'Robin Schulz', titel: 'Show Me Love', rang: 611063, seconden: 210)],
              'Robin S', 'Show Me Love'),
          isNull);
    });

    test('DE GRENS: een lidwoord of een accent maakt het geen ander liedje', () {
      expect(
          besteTreffer(<T>[(artiest: 'Corona', titel: 'The Rhythm Of The Night', rang: 1, seconden: 264)],
              'Corona', 'Rhythm of the Night'),
          0);
      expect(
          besteTreffer(<T>[(artiest: 'Kate Ryan', titel: 'Désenchantée', rang: 629694, seconden: 214)],
              'Kate Ryan', 'Desenchantee'),
          0);
    });
  });
}

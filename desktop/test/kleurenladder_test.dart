/// De grijstrap moet een trap blijven.
///
/// **Waarom deze toets bestaat.** De vorige trap had tussen "paneel" en "actief" een verschil van
/// ΔL* 4,0 — onder wat een oog op een donker scherm ziet. Dat is niet ontstaan doordat iemand een
/// slechte kleur koos, maar doordat er nooit iets was dat het TEGENSPRAK: je zet één hexcijfer bij,
/// de app bouwt, en de melding "dit is geselecteerd" is stilletjes onzichtbaar geworden.
///
/// Vanaf nu is "even het paneel wat lichter" een gezakte toets.
///
/// **Twee trappen sinds 18-10-2026.** Het lichte thema is geen omgekeerde donkere trap. Op donker
/// komt alles wat hoger ligt lichter naar voren; op licht ligt een kaart wit op gebroken wit, zakt een
/// zoekveld donkerder weg, en is "actief" een donkerder tint van het paneel — net als op een Mac. De
/// regels die voor allebei gelden (tekst leesbaar op elke laag, actief valt op) staan één keer en
/// draaien twee keer.
library;

import 'package:debridmusic/ui/kleuren.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<(String, Color)> _trap() => [
      ('achtergrond', kAchtergrond),
      ('verzonken', kVerzonken),
      ('paneel', kPaneel),
      ('actief', kPaneelHoog),
      ('bovenop', kBovenop),
    ];

void main() {
  tearDown(() => Thema.licht = false);

  group('donker', () {
    setUp(() => Thema.licht = false);

    test('elke trede is lichter dan de vorige', () {
      final trap = _trap();
      for (var i = 1; i < trap.length; i++) {
        final vorige = sterrenL(trap[i - 1].$2);
        final deze = sterrenL(trap[i].$2);
        expect(deze, greaterThan(vorige),
            reason: '${trap[i].$1} moet lichter zijn dan ${trap[i - 1].$1}');
      }
    });

    test('elke stap is groot genoeg om te zien', () {
      // Drie is de ondergrens waaronder twee náást elkaar liggende donkere vlakken op een gewoon
      // scherm in elkaar overlopen. De trap is ontworpen op 3,3 tot 6,5; deze grens vangt het geval
      // waarin iemand er eentje dichterbij schuift.
      final trap = _trap();
      for (var i = 1; i < trap.length; i++) {
        final stap = sterrenL(trap[i].$2) - sterrenL(trap[i - 1].$2);
        expect(stap, greaterThanOrEqualTo(3.0),
            reason: '${trap[i - 1].$1} → ${trap[i].$1} is maar ΔL* '
                '${stap.toStringAsFixed(1)}');
      }
    });

    test('de lijn ligt boven de laag waar hij meestal op valt', () {
      expect(sterrenL(kLijn), greaterThan(sterrenL(kPaneel)));
      expect(sterrenL(kLijnZacht), greaterThan(sterrenL(kAchtergrond)));
    });

    test('de inkt voor een waas is wit', () {
      expect(kInkt, const Color(0xFFFFFFFF));
    });
  });

  group('licht', () {
    setUp(() => Thema.licht = true);

    test('een kaart ligt lichter dan de pagina, een veld zakt erin weg, een menu is het lichtst', () {
      // Drie is dezelfde ondergrens als op donker: daaronder ziet een oog geen twee vlakken meer.
      expect(sterrenL(kPaneel) - sterrenL(kAchtergrond), greaterThanOrEqualTo(3.0), reason: 'paneel op de pagina');
      expect(sterrenL(kAchtergrond) - sterrenL(kVerzonken), greaterThanOrEqualTo(3.0), reason: 'verzonken in de pagina');
      expect(sterrenL(kBovenop), greaterThanOrEqualTo(sterrenL(kPaneel)), reason: 'een menu ligt nooit donkerder dan een kaart');
    });

    test('de lijn ligt ónder de laag waar hij op valt — op licht is een lijn donkerder', () {
      expect(sterrenL(kLijn), lessThan(sterrenL(kPaneel)));
      expect(sterrenL(kLijnZacht), lessThan(sterrenL(kAchtergrond)));
    });

    test('warm gebroken wit, geen grijs en geen blauw', () {
      // Saber, 18-10-2026: "warm gebroken wit". Rood boven blauw in de achtergrond, en niet wit.
      final a = kAchtergrond;
      expect(a.r, greaterThan(a.b), reason: 'warm: meer rood dan blauw');
      expect(a, isNot(const Color(0xFFFFFFFF)));
    });

    test('de inkt voor een waas is zwart', () {
      expect(kInkt, const Color(0xFF000000));
    });
  });

  for (final licht in [false, true]) {
    group(licht ? 'licht en donker: licht' : 'licht en donker: donker', () {
      setUp(() => Thema.licht = licht);

      test('de "dit is actief"-stap is de stap die het meest moet doen', () {
        // De reden dat de hele trap ooit verschoven is. Hij stond op 4,0 en hoort ruim boven de rest
        // te liggen: dit is de enige stap die een MEDEDELING is en niet alleen een laag. Op licht
        // ligt hij donkerder dan het paneel, op donker lichter — de afstand telt.
        final stap = (sterrenL(kPaneelHoog) - sterrenL(kPaneel)).abs();
        expect(stap, greaterThanOrEqualTo(5.5), reason: 'actief moet opvallen, niet alleen bestaan');
      });

      test('gewone tekst is leesbaar op élke laag', () {
        for (final (naam, laag) in _trap()) {
          expect(contrast(kTekst, laag), greaterThanOrEqualTo(4.5), reason: 'kTekst op $naam');
        }
      });

      test('gedempte tekst haalt de grens voor grote tekst op élke laag', () {
        // 3:1 en niet 4,5:1, met opzet: dit is de kleur van artiestnamen, tijden en tellingen, en die
        // op tekstwit zetten maakt het onderscheid tussen hoofd- en bijzaak kapot. Wat hier bewaakt
        // wordt is dat hij niet ONDER de grens zakt zodra de lagen verschuiven.
        for (final (naam, laag) in _trap()) {
          expect(contrast(kGedempt, laag), greaterThanOrEqualTo(3.0), reason: 'kGedempt op $naam');
        }
      });

      test('het merkpaars is leesbaar op de pagina, een kaart en een veld, en wit erop ook', () {
        // Het paars blijft in allebei (Saber). Op licht een tint donkerder, anders verdwijnt een
        // paarse link op gebroken wit. Niet op "actief" en "bovenop": op donker haalt het paars op
        // een menu 2,98 (gemeten 18-10-2026), en dat donkere palet blijft zoals het is.
        for (final (naam, laag) in _trap().take(3)) {
          expect(contrast(kAccent, laag), greaterThanOrEqualTo(3.0), reason: 'kAccent op $naam');
        }
        // Knopletters zijn vet en minstens 14 punten: "grote tekst", grens 3:1. Op donker haalt wit op
        // het paars 4,35 (gemeten 18-10-2026); het lichte paars moet de strenge 4,5 halen.
        expect(contrast(const Color(0xFFFFFFFF), kAccent), greaterThanOrEqualTo(licht ? 4.5 : 3.0),
            reason: 'witte tekst op een paarse knop');
      });
    });
  }
}

/// De grijstrap moet een trap blijven.
///
/// **Waarom deze toets bestaat.** De vorige trap had tussen "paneel" en "actief" een verschil van
/// ΔL* 4,0 — onder wat een oog op een donker scherm ziet. Dat is niet ontstaan doordat iemand een
/// slechte kleur koos, maar doordat er nooit iets was dat het TEGENSPRAK: je zet één hexcijfer bij,
/// de app bouwt, en de melding "dit is geselecteerd" is stilletjes onzichtbaar geworden.
///
/// Vanaf nu is "even het paneel wat lichter" een gezakte toets.
library;

import 'package:debridmusic/ui/kleuren.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const trap = <(String, Color)>[
    ('achtergrond', kAchtergrond),
    ('verzonken', kVerzonken),
    ('paneel', kPaneel),
    ('actief', kPaneelHoog),
    ('bovenop', kBovenop),
  ];

  test('elke trede is lichter dan de vorige', () {
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
    for (var i = 1; i < trap.length; i++) {
      final stap = sterrenL(trap[i].$2) - sterrenL(trap[i - 1].$2);
      expect(stap, greaterThanOrEqualTo(3.0),
          reason: '${trap[i - 1].$1} → ${trap[i].$1} is maar ΔL* '
              '${stap.toStringAsFixed(1)}');
    }
  });

  test('de "dit is actief"-stap is de stap die het meest moet doen', () {
    // De reden dat de hele trap verschoven is. Hij stond op 4,0 en hoort ruim boven de rest te
    // liggen: dit is de enige stap die een MEDEDELING is en niet alleen een laag.
    final stap = sterrenL(kPaneelHoog) - sterrenL(kPaneel);
    expect(stap, greaterThanOrEqualTo(5.5), reason: 'actief moet opvallen, niet alleen bestaan');
  });

  test('gewone tekst is leesbaar op élke laag', () {
    for (final (naam, laag) in trap) {
      expect(contrast(kTekst, laag), greaterThanOrEqualTo(4.5),
          reason: 'kTekst op $naam');
    }
  });

  test('gedempte tekst haalt de grens voor grote tekst op élke laag', () {
    // 3:1 en niet 4,5:1, met opzet: dit is de kleur van artiestnamen, tijden en tellingen, en die
    // op tekstwit zetten maakt het onderscheid tussen hoofd- en bijzaak kapot. Wat hier bewaakt
    // wordt is dat hij niet ONDER de grens zakt zodra de lagen verschuiven.
    for (final (naam, laag) in trap) {
      expect(contrast(kGedempt, laag), greaterThanOrEqualTo(3.0), reason: 'kGedempt op $naam');
    }
  });

  test('de lijn ligt boven de laag waar hij meestal op valt', () {
    expect(sterrenL(kLijn), greaterThan(sterrenL(kPaneel)));
    expect(sterrenL(kLijnZacht), greaterThan(sterrenL(kAchtergrond)));
  });
}

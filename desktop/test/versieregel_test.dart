/// Welke uitgave draait hier? De regel die dat op het scherm zet.
///
/// **Waarom dit bestaat.** Onder de diagnoseregel bij het zoeken stond het buildnummer, zodat een
/// schermafdruk te lezen is: "die melding zit nog niet in jouw bouw" is anders niet te
/// onderscheiden van "die melding werkt niet".
///
/// Alleen: op Windows komt dat getal uit `pubspec.yaml` en staat het sinds april stil op 343,
/// terwijl de Android-bouw wél meeloopt. Op 26-08-2026 stond er op een schermafdruk van de pc
/// "bouw 343" onder een melding die dagen later gebouwd was. Het getal dat een ronde moest besparen
/// kostte er juist een.
///
/// Het VERSIEnummer komt op alle platformen uit de tag en is overal waar. Dat gaat dus voorop.
library;

import 'package:debridmusic/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DE KERN: de versie gaat voorop', () {
    test('allebei bekend: versie met de bouw erachter', () {
      expect(versieRegel('3.9.220', '11408'), '3.9.220 (11408)');
    });

    test('het vaste Windows-getal maakt de regel niet waardeloos', () {
      // 343 zegt niets, 3.9.220 alles. Zolang de versie er staat is de afdruk te lezen.
      expect(versieRegel('3.9.220', '343'), '3.9.220 (343)');
    });
  });

  group('als er iets ontbreekt', () {
    test('geen buildnummer: dan alleen de versie', () {
      expect(versieRegel('3.9.220', ''), '3.9.220');
      expect(versieRegel('3.9.220', '  '), '3.9.220');
    });

    test('geen versie: dan is de bouw beter dan niets', () {
      expect(versieRegel('', '11408'), '11408');
    });

    test('helemaal niets geeft niets, en niet een leeg haakje', () {
      // De aanroeper toont deze regel alleen als hij niet leeg is. Een '()' zou daar doorheen
      // glippen en op het scherm staan als een fout die er niet is.
      expect(versieRegel('', ''), isEmpty);
      expect(versieRegel('  ', '  '), isEmpty);
    });

    test('twee keer hetzelfde wordt niet herhaald', () {
      expect(versieRegel('11408', '11408'), '11408');
    });
  });
}

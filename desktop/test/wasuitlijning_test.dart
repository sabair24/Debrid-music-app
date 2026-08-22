/// De was van de schil en die van de albumpagina moeten op elkaar passen.
///
/// **Waarom deze toets bestaat: drie standen, en alle drie hadden ze iets mis.**
///
/// 1. Eerst tekende de albumpagina de was over zijn EIGEN vak. Dat gaf een harde rand op de grens
///    met de bovenbalk: die balk staat buiten de navigator waar de pagina in leeft, dus het verloop
///    begon daar opnieuw, bovenaan op de volle tint, terwijl de schil daar al een stuk verder was.
/// 2. Toen deed de schil het over de volle hoogte en werd de pagina doorzichtig. De kleur liep
///    prachtig door — maar tijdens een paginawissel zag je de pagina eronder er dwars doorheen:
///    hoes, titel, knoppen en chips zweefden over het albumraster. Spookbeelden, op pc en Mac.
/// 3. Nu allebei, met hetzelfde recept: de pagina tekent de was over een vak zo hoog als het
///    VENSTER en schuift dat omhoog met precies de hoogte van de bovenbalk. Dan is de pagina weer
///    dicht — geen spookbeelden — en liggen de twee verlopen op elke hoogte op dezelfde kleur.
///
/// Die derde stand staat of valt bij twee getallen: de verschuiving en de hoogte van dat vak. Zet
/// iemand daar de hoogte van de PAGINA neer in plaats van die van het venster, dan is er weer een
/// rand — en dat is nou juist niet iets wat een bouw ziet.
library;

import 'package:debridmusic/ui/kleuren.dart';
import 'package:debridmusic/ui/vlak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const venster = 1000.0;
  const balk = 64.0;
  final basis = wasBasis(0xFF8A2B2B)!;

  /// Welke kleur een verloop geeft op [y] punten onder de bovenrand van het SCHERM, gegeven waar
  /// het geschilderde vak begint en hoe hoog het is. Dit is wat een `LinearGradient` doet, en het
  /// staat hier uitgeschreven zodat de twee vakken naast elkaar te leggen zijn.
  Color kleurOpScherm(double y, {required double vakTop, required double vakHoogte}) {
    final verloop = kleurWas(basis)!;
    final f = ((y - vakTop) / vakHoogte).clamp(0.0, 1.0);
    final stops = verloop.stops!;
    for (var i = 1; i < stops.length; i++) {
      if (f <= stops[i]) {
        final deel = (f - stops[i - 1]) / (stops[i] - stops[i - 1]);
        return Color.lerp(verloop.colors[i - 1], verloop.colors[i], deel)!;
      }
    }
    return verloop.colors.last;
  }

  /// Het vak dat de PAGINA schildert, uitgedrukt in schermpunten, volgens de regel die in
  /// `main.dart` staat: `Positioned(top: -balk, height: <vensterhoogte>)` binnen een pagina die zelf
  /// op `balk` punten onder de bovenrand van het scherm begint.
  ({double top, double hoogte}) paginaVak(double balkHoogte) =>
      (top: balkHoogte + -balkHoogte, hoogte: venster);

  group('de twee verlopen vallen samen', () {
    test('op elke hoogte dezelfde kleur, ook precies op de grens', () {
      final vak = paginaVak(balk);
      for (final y in [balk, balk + 1, 100.0, 340.0, 700.0, 999.0]) {
        expect(
          kleurOpScherm(y, vakTop: vak.top, vakHoogte: vak.hoogte),
          kleurOpScherm(y, vakTop: 0, vakHoogte: venster),
          reason: 'op $y punten geeft de pagina een andere kleur dan de schil — dat is een rand',
        );
      }
    });

    test('zonder bovenbalk verandert er niets', () {
      // Televisie en telefoon: daar staat er geen bovenbalk en begint de pagina bovenaan het
      // venster. Dezelfde regel moet dan gewoon nul verschuiven.
      final vak = paginaVak(0);
      expect(vak.top, 0);
      expect(vak.hoogte, venster);
    });
  });

  group('de faalstanden, vastgelegd zodat niemand er per ongeluk naar terugkeert', () {
    test('het eigen vak van de pagina nemen geeft meteen een rand', () {
      // Stand 1. Het verloop begint dan bovenaan de pagina opnieuw op de volle tint.
      expect(
        kleurOpScherm(balk, vakTop: balk, vakHoogte: venster - balk),
        isNot(kleurOpScherm(balk, vakTop: 0, vakHoogte: venster)),
        reason: 'precies dit verschil was de rand dwars over het scherm',
      );
    });

    test('wél verschuiven maar de paginahoogte nemen loopt verderop uiteen', () {
      // De subtiele variant: de bovenkant klopt dan, maar het verloop is uitgerekt en zakt op elke
      // andere hoogte af. Juist die zou je op een schermafbeelding pas laat opmerken.
      expect(
        kleurOpScherm(500, vakTop: 0, vakHoogte: venster - balk),
        isNot(kleurOpScherm(500, vakTop: 0, vakHoogte: venster)),
      );
    });
  });

  group('de was zelf', () {
    test('begint gekleurd en eindigt op de gewone achtergrond', () {
      final v = kleurWas(basis)!;
      expect(v.colors.first, isNot(kAchtergrond));
      expect(v.colors.last, kAchtergrond,
          reason: 'onderaan moet hij de vloer raken, anders staat er een rand waar hij ophoudt');
    });

    test('geen plaat, geen was — en dan is er ook niets uit te lijnen', () {
      expect(wasBasis(null), isNull);
      expect(kleurWas(null), isNull);
    });
  });
}

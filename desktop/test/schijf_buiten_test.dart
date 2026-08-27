/// Het herkennen van een cd-scan gebeurt niet meer op de tekendraad.
///
/// **Waarom dit een toets waard is.** `looksLikeDisc` ontcijfert een plaatje met `package:image` —
/// pure Dart — en verkleint het daarna naar 128×128. Dat is tientallen milliseconden per scan, en
/// het gebeurde tot zes keer per uitgave, voor élke rij die in de uitgavekiezer in beeld kwam, in
/// een lus die doorloopt zolang dat venster openstaat. De tekendraad stond daardoor vrijwel
/// onafgebroken stil. Gemeld op 27-08-2026: *"ik wil dit instant zien veranderen … nu zit er
/// behoorlijk wat tijd tussen waardoor ik soms twijfel of hij het wel heeft aangepast"*.
///
/// Het werk zelf is niet veranderd — `looksLikeDisc` en `assignRoles` staan er nog precies zo. Wat
/// veranderde is WAAR het draait, en dat is juist het soort wijziging dat stilletjes stukgaat: een
/// closure naar een isolate neemt zijn hele omgeving mee, en gaat er iets onverzendbaars in mee, dan
/// gooit de verzending. In deze app is dat al eens gebeurd (zie `library.dart`, de scan die de
/// bibliotheek leeg opleverde) en het is van buiten niet te zien: er komt geen melding, er komt
/// alleen géén antwoord.
///
/// Daarom meet dit vooral de OVERTOCHT: geeft de weg buiten de tekendraad exact hetzelfde antwoord
/// als de rechtstreekse, ook als er meerdere tegelijk onderweg zijn over de gedeelde wachtrij.
///
/// `artwork_test.dart` toetst wat een schijf ís; die staat niet in `build-release.yml` en draait dus
/// nooit. Deze wél — zie de lijst daar.
library;

import 'dart:typed_data';

import 'package:debridmusic/artwork.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _png(img.Image im) => Uint8List.fromList(img.encodePng(im));

/// Een schijf: lichte ondergrond, donker bedrukt vlak, licht gaatje in het midden.
Uint8List _schijf() {
  final im = img.Image(width: 300, height: 300);
  img.fill(im, color: img.ColorRgb8(250, 250, 250));
  img.fillCircle(im, x: 150, y: 150, radius: 145, color: img.ColorRgb8(20, 20, 20));
  img.fillCircle(im, x: 150, y: 150, radius: 22, color: img.ColorRgb8(250, 250, 250));
  return _png(im);
}

/// Een hoes: bedrukking tot in alle vier de hoeken.
Uint8List _hoes(int tint) {
  final im = img.Image(width: 300, height: 300);
  img.fill(im, color: img.ColorRgb8(tint, tint, tint));
  return _png(im);
}

/// Een vlak met een echte kleur erin.
///
/// Nodig omdat de twee maaksels hierboven grijs zijn, en `dominantColour` grijs juist overslaat —
/// die zoekt de kleur van een hoes en niet zijn helderheid. Voor het meten van de wachtrij is een
/// vlak dat wél een antwoord geeft het scherpste geval.
Uint8List _kleurvlak() {
  final im = img.Image(width: 300, height: 300);
  img.fill(im, color: img.ColorRgb8(200, 40, 40));
  return _png(im);
}

void main() {
  late Uint8List schijf;
  late Uint8List hoes;

  setUpAll(() {
    schijf = _schijf();
    hoes = _hoes(15);
    // Als dit al niet klopt zegt de rest van dit bestand niets.
    expect(looksLikeDisc(schijf), isTrue, reason: 'het maaksel moet als schijf lezen');
    expect(looksLikeDisc(hoes), isFalse, reason: 'het maaksel moet NIET als schijf lezen');
  });

  group('eersteSchijf: de volgorde beslist', () {
    test('de eerste die als schijf leest wint, niet de laatste', () {
      // Dit is de regel die uit de lus in discogs.dart hierheen verhuisde: een plaat kan meer dan
      // één ronde scan hebben — de cd zelf en een boekjespagina met een bleke kern — en alleen de
      // eerste kan achter de hoes vandaan schuiven.
      expect(eersteSchijf([hoes, schijf, schijf]), 1);
      expect(eersteSchijf([schijf, schijf]), 0);
    });

    test('scans die niet binnenkwamen worden overgeslagen', () {
      expect(eersteSchijf([null, null, schijf]), 2);
    });

    test('geen enkele schijf geeft null', () {
      expect(eersteSchijf([hoes, hoes]), isNull);
      expect(eersteSchijf([null, null]), isNull);
      expect(eersteSchijf(const []), isNull);
    });

    test('rommel telt niet als schijf en gooit niet', () {
      expect(eersteSchijf([Uint8List.fromList([1, 2, 3]), schijf]), 1);
    });
  });

  group('DE KERN: de overtocht naar de andere isolate geeft hetzelfde antwoord', () {
    test('een lijst met een schijf erin', () async {
      expect(await eersteSchijfBuitenDeTekendraad([hoes, schijf]), eersteSchijf([hoes, schijf]));
      expect(await eersteSchijfBuitenDeTekendraad([hoes, schijf]), 1);
    });

    test('een lijst zonder schijf', () async {
      expect(await eersteSchijfBuitenDeTekendraad([hoes, hoes]), isNull);
    });

    test('een lege lijst komt terug en blijft niet hangen', () async {
      expect(await eersteSchijfBuitenDeTekendraad(const []), isNull);
    });

    test('nulls overleven de overtocht als nulls', () async {
      expect(await eersteSchijfBuitenDeTekendraad([null, schijf]), 1);
    });
  });

  group('DE KERN: de rolverdeling geeft buiten de tekendraad hetzelfde', () {
    test('voorkant, achterkant en schijf komen op dezelfde plekken uit', () async {
      final primary = [true, false, false];
      final ratios = [1.0, 1.3, 1.0];
      final datas = <Uint8List?>[hoes, hoes, schijf];
      final hier = assignRoles(primary, ratios, datas);
      final daar = await rollenBuitenDeTekendraad(primary, ratios, datas);
      expect(daar.front, hier.front);
      expect(daar.back, hier.back);
      expect(daar.disc, hier.disc);
      expect(daar.front, 0, reason: 'de "primary" van Discogs is de voorkant');
      expect(daar.disc, 2);
    });

    test('een uitgave zonder scans geeft niets terug in plaats van te gooien', () async {
      final leeg = await rollenBuitenDeTekendraad(const [], const [], const []);
      expect(leeg.front, isNull);
      expect(leeg.back, isNull);
      expect(leeg.disc, isNull);
    });
  });

  group('DE WACHTRIJ: alles tegelijk vragen levert alles op', () {
    test('acht vragen door elkaar komen allemaal en allemaal goed terug', () async {
      // Zo gaat het er in de uitgavekiezer echt aan toe: elke rij die in beeld komt vraagt het
      // zijne, en ze staan door elkaar. De rij mag ze serialiseren, maar niet er eentje laten
      // vallen of vastlopen — en een gedeelde rij die op een fout klapt sleept de rest mee.
      final vragen = [
        for (var i = 0; i < 8; i++)
          eersteSchijfBuitenDeTekendraad(i.isEven ? [hoes, schijf] : [hoes, hoes]),
      ];
      final uit = await Future.wait(vragen);
      expect(uit, [1, null, 1, null, 1, null, 1, null]);
    });

    test('de kleurberekening deelt die rij en blijft werken', () async {
      // Kleur en schijf zitten expres in ÉÉN wachtrij (zie `_opDeRij`): twee rijen naast elkaar
      // zijn geen rij. Dus moeten ze ook door elkaar heen kunnen lopen.
      //
      // Let op WAT hier gemeten wordt: dat alle vier de vragen antwoord geven. Een grijze plaat
      // hoort GEEN kleur op te leveren — `dominantColour` slaat bijna-zwart, bijna-wit en alles
      // onder een verzadiging van .22 over, en dat is precies waar mijn maaksels uit bestaan. De
      // eerste versie van deze toets verwachtte daar een getal en zakte terecht.
      final uit = await Future.wait<Object?>([
        kleurBuitenDeTekendraad(_kleurvlak()),
        eersteSchijfBuitenDeTekendraad([schijf]),
        kleurBuitenDeTekendraad(schijf),
        eersteSchijfBuitenDeTekendraad([hoes]),
      ]);
      expect(uit[0], isA<int>(), reason: 'een verzadigd vlak heeft wél een hoofdkleur');
      expect(uit[1], 0);
      expect(uit[2], isNull, reason: 'grijs heeft geen hoofdkleur — en dat mag de rij niet breken');
      expect(uit[3], isNull);
    });

    test('een mislukte berekening laat de volgende ongemoeid', () async {
      // Rommel erin: `looksLikeDisc` vangt dat zelf af, maar de rij moet er hoe dan ook doorheen —
      // een staart die op een fout blijft staan zou elke volgende vraag laten hangen.
      await eersteSchijfBuitenDeTekendraad([Uint8List.fromList([9, 9, 9])]);
      expect(await eersteSchijfBuitenDeTekendraad([schijf]), 0);
    });
  });
}

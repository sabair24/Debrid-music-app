/// De kop van een artiestpagina: slim uitgesneden op de gezichten, en zelf in te stellen per scherm.
///
/// Saber, 17-10-2026: "ook op de hero bij artist detail, wordt vaak afgekapt … vooral een groep zoals
/// Nsync of Backstreet Boys … het moet altijd automatisch fitten", en daarna: "volle breedte, slim
/// uitgesneden, maar ik kan nog aanpassen". Wat hier vastligt is gemeten op 77 echte artiestfoto's van
/// de pc (scratchpad/brandpunt): de foto's zelf staan niet in de repository, de regels die eruit
/// kwamen wel.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:debridmusic/beeldvorm.dart';
import 'package:debridmusic/gezichten.dart';
import 'package:debridmusic/ui/kopfoto.dart';

/// Een RGBA-afbeelding van [b] × [h] in één kleur.
Uint8List effen(int b, int h, int r, int g, int bl) {
  final d = Uint8List(b * h * 4);
  for (var i = 0; i < b * h; i++) {
    d[i * 4] = r;
    d[i * 4 + 1] = g;
    d[i * 4 + 2] = bl;
    d[i * 4 + 3] = 255;
  }
  return d;
}

void main() {
  group('de instelling per scherm', () {
    test('schrijven en weer lezen geeft hetzelfde', () {
      const i = KopInstelling(fx: .62, fy: .31, zoom: 1.25, hoogte: 380);
      expect(i.schrijf(), '0.620,0.310,1.250,380');
      expect(KopInstelling.lees(i.schrijf()), i);
      expect(KopInstelling.lees('0.5,0.4,1'), const KopInstelling(fx: .5, fy: .4));
    });

    test('wat geen instelling is, wordt er geen — ook geen half verzonnen', () {
      for (final fout in [null, '', 'https://i.discogs.com/foto.jpg', '1,2', '0.5,x,1', '0.5,0.5,1,hoog', 'NaN,0.5,1', '1,2,3,4,5']) {
        expect(KopInstelling.lees(fout), isNull, reason: '"$fout"');
      }
    });

    test('buiten de grenzen wordt binnen de grenzen', () {
      final i = KopInstelling.lees('-1,7,99,20')!;
      expect(i.fx, 0);
      expect(i.fy, 1);
      expect(i.zoom, KopInstelling.kZoomTot);
      expect(i.hoogte, KopInstelling.kHoogteVanaf, reason: 'een kop van 20 punten past de naam niet');
    });

    test('elk scherm zijn eigen soort, en alle drie reizen ze mee met de catalogus', () {
      expect({for (final s in KopScherm.values) kopSoort(s)}, {'kop_pc', 'kop_tv', 'kop_gsm'});
      for (final s in KopScherm.values) {
        expect(kArtSoorten, contains(kopSoort(s)), reason: 'anders komt de ${s.name}-kop nooit op dat toestel aan');
      }
    });
  });

  group('kopPlek: waar de foto in de kop komt', () {
    const tv = Size(960, 435);

    test('de foto vult de kop altijd — nooit een rand, waar het punt ook ligt', () {
      for (final beeld in const [Size(599, 688), Size(1280, 720), Size(400, 1200), Size(3000, 300)]) {
        for (final p in const [Brandpunt(0, 0), Brandpunt(1, 1), Brandpunt(.5, .3), Brandpunt(.9, .05)]) {
          for (final zoom in const [1.0, 2.5]) {
            final r = kopPlek(vak: tv, beeld: beeld, punt: p, doel: const Offset(.68, .4), zoom: zoom);
            expect(r.left, lessThanOrEqualTo(0));
            expect(r.top, lessThanOrEqualTo(0));
            expect(r.right, greaterThanOrEqualTo(tv.width - 1e-6));
            expect(r.bottom, greaterThanOrEqualTo(tv.height - 1e-6));
            expect(r.width / r.height, closeTo(beeld.width / beeld.height, 1e-6), reason: 'niet uitgerekt');
          }
        }
      }
    });

    test('DE VAL: een foto die precies past gooit geen fout (1,1e-13 boven nul)', () {
      // Gemeten in de eerste proef: `clamp(vak - w, 0)` met een ondergrens die door afronding een haar
      // boven nul lag, en `clamp` gooit dan een fout in plaats van een getal.
      for (var b = 300; b < 700; b += 7) {
        expect(() => kopPlek(vak: tv, beeld: Size(b.toDouble(), b * 1.15), punt: Brandpunt.midden, doel: const Offset(.68, .4)),
            returnsNormally);
      }
    });

    test('het punt komt op het doel als daar ruimte voor is', () {
      // *NSYNC: staand, 599 × 688. Over de volle breedte is hij 1102 hoog, dus er is ruimte in de hoogte.
      final r = kopPlek(vak: tv, beeld: const Size(599, 688), punt: const Brandpunt(.5, .3), doel: const Offset(.5, .4));
      expect(r.top + .3 * r.height, closeTo(.4 * tv.height, 1e-6));
    });

    test('de hele groep in beeld, met haar en kin, niet alleen het midden', () {
      // De vijf Backstreet Boys op een staande foto: het vak om hun gezichten ligt hoog.
      const gezichten = Rect.fromLTRB(.1, .18, .9, .25);
      final zicht = kopZicht(smal: false, vak: tv, bovenRand: 75);
      final r = kopPlek(
          vak: tv, beeld: const Size(599, 681), punt: const Brandpunt(.5, .2), doel: const Offset(.68, .3),
          gezichten: gezichten, zicht: zicht);
      final ruim = gezichtenMetRuimte(gezichten);
      expect(r.top + ruim.top * r.height, greaterThanOrEqualTo(zicht.top * tv.height - 1e-6),
          reason: 'de kruinen horen onder de balk');
      expect(r.top + ruim.bottom * r.height, lessThanOrEqualTo(zicht.bottom * tv.height + 1e-6),
          reason: 'de kinnen horen boven het donkere verloop');
    });

    test('DE VAL: bij een close-up de ogen in het midden, niet het haar', () {
      // Alicia Keys, staand 423 × 750, met een gezicht van 70 % van de breedte. "De kruin gaat voor"
      // liet hier alleen haar haar zien.
      const gezicht = Rect.fromLTRB(.19, .2, .88, .59);
      const zicht = Rect.fromLTRB(.40, .2, .98, .64);
      final r = kopPlek(
          vak: tv, beeld: const Size(423, 750), punt: const Brandpunt(.54, .40), doel: const Offset(.68, .3),
          gezichten: gezicht, zicht: zicht);
      final ogen = r.top + (gezicht.top + gezicht.height * .42) * r.height;
      expect(ogen, closeTo((zicht.top + zicht.bottom) / 2 * tv.height, 1e-6));
    });

    test('puntOpDoel is het omgekeerde van kopPlek — wat je in de bewerker sleept, blijft staan', () {
      const doel = Offset(.68, .3);
      // Een punt dat niet tegen de rand loopt: daar houdt kopPlek de foto tegen, en dan is er geen weg terug.
      const p = Brandpunt(.6, .37);
      final r = kopPlek(vak: tv, beeld: const Size(600, 900), punt: p, doel: doel, zoom: 1.4);
      final terug = puntOpDoel(vak: tv, plek: r, doel: doel);
      expect(terug.x, closeTo(p.x, 1e-9));
      expect(terug.y, closeTo(p.y, 1e-9));
    });

    test('de gezichten staan hoog genoeg: het verloop is op 58 % van de kop al 86 % donker', () {
      final d = doelInVak(kopDoel(smal: false), tv, 75);
      expect(d.dy, lessThan(.45));
      expect(d.dy, greaterThan(75 / 435), reason: 'en onder de balk');
      expect(kopZicht(smal: false, vak: tv, bovenRand: 75).bottom, lessThanOrEqualTo(.65));
    });
  });

  group('de huidregel', () {
    test('huid is huid, licht en donker', () {
      for (final (r, g, b) in const [(224, 172, 140), (141, 85, 36), (198, 134, 66), (255, 205, 170)]) {
        expect(isHuid(r, g, b), isTrue, reason: '($r, $g, $b)');
      }
    });

    test('DE VAL: rode ballen, een gouden jasje en een roze deur zijn geen huid', () {
      // Alle drie gemeten als "huid" met alleen de YCbCr-regel, en alle drie trokken ze het punt weg.
      expect(isHuid(220, 30, 40), isFalse, reason: 'verzadigd rood');
      expect(isHuid(212, 175, 55), isFalse, reason: 'goud, tint 46°');
      expect(isHuid(240, 222, 216), isFalse, reason: 'roze-wit, haast geen kleur');
    });
  });

  group('waar het onderwerp begint', () {
    test('boven een effen lucht: waar het drukke deel begint', () {
      const b = 60, h = 80;
      final d = effen(b, h, 200, 210, 230);
      for (var y = 40; y < h; y++) {
        for (var x = 0; x < b; x++) {
          final v = (x * 37 + y * 91) % 2 == 0 ? 20 : 230;
          final i = (y * b + x) * 4;
          d[i] = v;
          d[i + 1] = v;
          d[i + 2] = v;
        }
      }
      expect(onderwerpBoven(d, b, h), closeTo(.5, .05));
    });

    test('zonder gezicht nooit ver onder waar het onderwerp begint', () {
      // De man tussen de rode ballen: het oude punt viel op 0,86, en zijn hoofd ging eraf.
      const b = 60, h = 80;
      final d = effen(b, h, 200, 210, 230);
      for (var y = 10; y < h; y++) {
        for (var x = 20; x < 40; x++) {
          final v = (x + y).isEven ? 10 : 240;
          final i = (y * b + x) * 4;
          d[i] = v;
          d[i + 1] = v;
          d[i + 2] = v;
        }
      }
      final blik = ontleedFoto(d, b, h);
      expect(blik.gezichten, isNull);
      expect(blik.punt.y, lessThanOrEqualTo(onderwerpBoven(d, b, h) + .14 + 1e-9));
    });
  });

  group('de gezichtszoeker', () {
    test('het model van OpenCV is heel binnengekomen', () {
      final m = Gezichtsmodel.standaard;
      expect(m.raam, 24);
    });

    test('in een effen vlak en in ruis staat geen gezicht', () {
      final grijs = Uint8List(200 * 150)..fillRange(0, 200 * 150, 128);
      expect(vindGezichten(grijs, 200, 150), isEmpty);
      final ruis = Uint8List.fromList([for (var i = 0; i < 200 * 150; i++) (i * 2654435761) >> 7 & 0xff]);
      expect(vindGezichten(ruis, 200, 150).where((g) => g.buren >= 6), isEmpty);
    });

    test('te klein voor het raam is niets, en geen fout', () {
      expect(vindGezichten(Uint8List(20 * 20), 20, 20), isEmpty);
    });
  });

  group('wat er van een foto bewaard wordt', () {
    test('schrijven en lezen, met en zonder gezichten', () {
      const a = FotoBlik(Brandpunt(.512, .3), Size(599, 688));
      final b = FotoBlik(const Brandpunt(.44, .31), const Size(480, 269), const Rect.fromLTRB(.1, .2, .9, .35));
      expect(FotoBlik.lees(a.schrijf())!.schrijf(), a.schrijf());
      expect(FotoBlik.lees(b.schrijf())!.gezichten!.right, closeTo(.9, 1e-3));
      expect(FotoBlik.lees('kapot'), isNull);
      expect(FotoBlik.lees('0.5,0.5,0,10'), isNull, reason: 'een foto zonder breedte bestaat niet');
    });

    test('de sleutel hangt aan de inhoud, niet aan het object', () {
      final x = Uint8List.fromList(List.generate(5000, (i) => i * 7 & 0xff));
      final y = Uint8List.fromList(x);
      expect(fotoSleutel(x), fotoSleutel(y));
      y[2500] ^= 1;
      expect(fotoSleutel(x), isNot(fotoSleutel(y)));
    });

    test('decodeerbreedte in stappen, nooit boven 1920', () {
      expect(decodeerBreedte(100), 320);
      expect(decodeerBreedte(1233), 1280);
      expect(decodeerBreedte(5000), 1920);
    });
  });

  group('bekijkFoto: decoderen en ontleden in een eigen draad, zoals in de app', () {
    // De proef op 77 foto's riep [ontleedFoto] rechtstreeks aan. De app doet het via `Isolate.run`, en
    // als die afsluiting iets meeneemt dat niet naar een andere draad kan (een `ui.Image`), valt elke
    // foto stil terug op "niets gevonden" — zonder fout op het scherm. Deze toets loopt de echte weg.
    testWidgets('een staande foto komt terug met zijn eigen verhouding, en wordt bewaard', (tester) async {
      final bewaard = <String, String>{};
      FotoBlikGeheugen.lees = (s) => bewaard[s];
      FotoBlikGeheugen.schrijf = (s, w) => bewaard[s] = w;
      addTearDown(() {
        FotoBlikGeheugen.lees = null;
        FotoBlikGeheugen.schrijf = null;
      });
      final foto = Uint8List.fromList(img.encodePng(img.Image(width: 600, height: 690)));
      final blik = await tester.runAsync(() => bekijkFoto(foto));
      expect(blik, isNotNull, reason: 'de weg via de eigen draad gaf niets terug');
      expect(blik!.maat.width / blik.maat.height, closeTo(600 / 690, .01));
      expect(blik.maat.width, lessThanOrEqualTo(kBekijkMaat));
      expect(bewaard, hasLength(1), reason: 'één keer per foto: de tweede keer uit het geheugen');
      // Een ander object met dezelfde bytes (de volgende start): meteen bekend, zonder te kijken.
      expect(bekendeBlik(Uint8List.fromList(foto))?.schrijf(), blik.schrijf());
    });
  });

  group('bedrading (gelezen uit lib/)', () {
    final bron = File('lib/main.dart').readAsStringSync();

    test('de artiestkop tekent zijn foto met KopFoto, met de instelling van dit soort scherm', () {
      expect(bron, contains('child: grijs(KopFoto('));
      expect(bron, contains('uitsnede: lib.kopVoor(widget.artist.name, kopSchermVan(context)),'));
      expect(bron, contains('minHeight: (uitsnede?.hoogte ??'));
      final kop = bron.substring(bron.indexOf('class EditorialeKop '), bron.indexOf('child: grijs(KopFoto('));
      expect(kop, isNot(contains('alignment: const Alignment(0, -.35)')),
          reason: 'de vaste uitlijning die de hoofden afsneed');
    });

    test('Kop aanpassen alleen op pc, Mac en iPad', () {
      expect(bron, contains('if (!isTv && !isCompact(context) && (_keuzeBytes ?? _art?.backdropBytes) != null)'));
    });

    test('wat over een foto bekend is, wordt bewaard — één keer per foto', () {
      expect(bron, contains("await bewaarFotoBlikkenIn(appFile('fotoblikken.json'));"));
    });
  });
}

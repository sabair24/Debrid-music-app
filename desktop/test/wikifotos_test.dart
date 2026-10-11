/// Foto's per periode uit de Engelse Wikipedia, op de artiestpagina.
///
/// **Waarom.** Saber op 11-10-2026: *"algemeen is er te weinig en niet relevante foto's erbij, zoals
/// geboren of kindertijd, moet je als dat kan baby en of kinder afbeeldingen tonen van die artist"*.
/// Naast "Geboren" stond bij Lionel Richie de hoes van "Tuskegee". De gegevens hieronder komen uit
/// een live meting op 11-10-2026 (media-list van de Engelse artikels): Michael Jackson 26 foto's, met
/// de Jackson 5 in 1972 in "Early life"; Lionel Richie drie, geen enkele uit zijn jeugd.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/ui/wikifoto_beeld.dart';
import 'package:debridmusic/wikifotos.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

WikiFoto _f(String bestand, String onderschrift, String sectie) => WikiFoto(
      bestand: bestand,
      url: 'https://upload.wikimedia.org/$bestand',
      onderschrift: onderschrift,
      sectie: sectie,
      jaar: jaarVanFoto(onderschrift, sectie),
      vroeg: vroegeFoto(onderschrift, sectie),
      maker: 'CBS Television',
      licentie: 'Public domain',
    );

final _mj = [
  _f('File:Michael_Jackson_1983_(3x4_cropped)_(contrast).jpg', '', ''),
  _f("File:Michael_Jackson's_birth_house_in_Gary_Indiana.jpg",
      "Jackson's childhood home in Gary, Indiana, as seen in 2014", 'Early life and the Jackson 5 (1958–1975)'),
  _f('File:The_Jackson_5_1972.JPG', 'Jackson (center) as a member of the Jackson 5 in 1972.',
      'Early life and the Jackson 5 (1958–1975)'),
  _f('File:Michael_Jackson_with_Grammy_Awards_in_1984.jpg', 'Jackson at the 26th Grammy Awards',
      'Thriller, Motown 25 and Pepsi incident (1981–1984)'),
  _f('File:Michael_Jackson_Cannes.jpg', 'Jackson at the 1997 Cannes Film Festival',
      'HIStory, second marriage, fatherhood (1995–1997)'),
  _f('File:Michael_Jackson_Star.JPG', "Fans placed flowers on Jackson's star", 'Death'),
];

final _lionel = [
  _f('File:Lionel_Richie_2022_(51930307118)_(cropped).jpg', '', ''),
  _f('File:Lionel_Richie_1984.jpg', 'Richie in 1984', 'Solo career'),
  _f('File:Lionel_Richie_and_Guy_Sebastian.jpg', "Richie and Guy Sebastian during Richie's 2011 tour",
      'Later career'),
];

class _NepDienst extends WikiFotoService {
  _NepDienst(this._b);
  final Uint8List? _b;
  @override
  Future<Uint8List?> bytes(WikiFoto foto) async => _b;
}

void main() {
  group('wat er uit een foto te lezen valt', () {
    test('het jaar: eerst het onderschrift, dan de kop van het hoofdstuk', () {
      expect(jaarVanFoto('the Jackson 5 in 1972.', 'Early life (1958–1975)'), 1972);
      expect(jaarVanFoto('', 'Early life and the Jackson 5 (1958–1975)'), 1958);
      expect(jaarVanFoto('Richie on stage', 'Personal life'), isNull);
    });

    test('uit de jeugd: "Early life" of "childhood"', () {
      expect(vroegeFoto('', 'Early life and the Jackson 5 (1958–1975)'), isTrue);
      expect(vroegeFoto("Jackson's childhood home", 'Legacy'), isTrue);
      expect(vroegeFoto('Richie in 1984', 'Solo career'), isFalse);
    });

    test('geen handtekeningen, logo\'s of geluid', () {
      expect(bruikbareFoto('File:Michael_Jackson_signature.svg'), isFalse);
      expect(bruikbareFoto('File:Queen_logo.png'), isFalse);
      expect(bruikbareFoto('File:Thriller_sample.ogg'), isFalse);
      expect(bruikbareFoto('File:Jackson_family_tree.svg'), isFalse, reason: 'een tekening, geen foto');
      expect(bruikbareFoto('File:The_Jackson_5_1972.JPG'), isTrue);
    });
  });

  group('over welke jaren een hoofdstuk gaat', () {
    test('de koppen van het Nederlandse artikel over Lionel Richie', () {
      expect(periodeVanKop('1949–1968: jeugd'), (van: 1949, tot: 1968));
      expect(periodeVanKop('1982–1987: de eerste drie soloalbums'), (van: 1982, tot: 1987));
      expect(periodeVanKop('Jaren 90: comeback'), (van: 1990, tot: 1999));
      expect(periodeVanKop('Sinds 2000'), (van: 2000, tot: 2100));
      expect(periodeVanKop('Persoonlijk'), isNull);
    });
  });

  group('DE KERN: welke foto bij welk hoofdstuk', () {
    test('bij "Geboren" een kinderfoto — de Jackson 5 in 1972 gaat voor zijn huis gefotografeerd in 2014', () {
      expect(geboortefoto(_mj, geboren: 1958)?.bestand, 'File:The_Jackson_5_1972.JPG');
    });

    test('bij Lionel Richie is er geen jeugdfoto, en dan bij "Geboren" NIETS', () {
      expect(geboortefoto(_lionel, geboren: 1949), isNull,
          reason: 'liever niets dan een volwassen foto of een hoes — dat was "Tuskegee"');
    });

    test('elk hoofdstuk zijn eigen periode, en geen foto twee keer', () {
      final koppen = [
        '1949–1968: jeugd',
        '1968–1981: Commodores',
        '1982–1987: de eerste drie soloalbums',
        'Jaren 90: comeback',
        'Sinds 2000',
        'Persoonlijk',
      ];
      final per = fotosPerHoofdstuk(_lionel, koppen, geboren: 1949);
      expect(per.map((f) => f?.bestand).toList(), [
        null,
        null,
        'File:Lionel_Richie_1984.jpg',
        null,
        'File:Lionel_Richie_and_Guy_Sebastian.jpg',
        null,
      ]);
    });

    test('een hoofdstuk zonder jaartal vindt zijn Engelse tegenhanger op het woord', () {
      final per = fotosPerHoofdstuk(_mj, ['Vroege jeugd', 'Overlijden', 'Huwelijken en kinderen'],
          geboren: 1958);
      expect(per[0]?.bestand, 'File:The_Jackson_5_1972.JPG');
      expect(per[1]?.bestand, 'File:Michael_Jackson_Star.JPG');
      expect(per[2]?.bestand, 'File:Michael_Jackson_Cannes.jpg');
    });

    test('twee hoofdstukken over hetzelfde jaar krijgen niet dezelfde foto', () {
      final per = fotosPerHoofdstuk(_lionel, ['1984: Can\'t Slow Down', '1984: tournee']);
      expect(per[0]?.bestand, 'File:Lionel_Richie_1984.jpg');
      expect(per[1], isNull, reason: 'dezelfde foto naast elk hoofdstuk was precies de klacht');
    });

    test('een foto zonder jaar en zonder passend hoofdstuk staat nergens', () {
      final per = fotosPerHoofdstuk([_mj.first], ['1982–1987: Thriller', 'Persoonlijk']);
      expect(per, [null, null]);
    });
  });

  test('bewaren en teruglezen, met de vermelding die erbij hoort', () {
    final f = _mj[2];
    final terug = WikiFoto.fromJson(f.toJson())!;
    expect(terug.bestand, f.bestand);
    expect(terug.jaar, 1972);
    expect(terug.vroeg, isTrue);
    expect(terug.vermelding, 'Foto: CBS Television · Public domain · Wikimedia Commons');
  });

  group('het beeld op de pagina', () {
    testWidgets('met het onderschrift en wie hem maakte', (t) async {
      final png = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82,
      ]);
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: SizedBox(width: 300, child: WikiFotoBeeld(foto: _mj[2], dienst: _NepDienst(png))))));
      await t.pump();
      await t.pump();
      expect(find.byType(Image), findsOneWidget);
      expect(find.textContaining('Jackson 5 in 1972'), findsOneWidget);
      expect(find.text('Foto: CBS Television · Public domain · Wikimedia Commons'), findsOneWidget);
    });

    testWidgets('lukt het laden niet, dan niets — geen leeg vak', (t) async {
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: SizedBox(width: 300, child: WikiFotoBeeld(foto: _mj[2], dienst: _NepDienst(null))))));
      await t.pump();
      await t.pump();
      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('Wikimedia'), findsNothing);
    });
  });

  test('de artiestpagina neemt bij "Geboren" de jeugdfoto en niet meer het portret', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains('            : punt.soort == Jaarsoort.geboorte\n                ? _geboorteBytes'), isTrue);
    expect(main.contains('if (kopOverJeugd(afdeling.kop)) return null;'), isTrue);
    expect(main.contains("if (_fotoPerKop[afdeling.kop] case final foto?) return WikiFotoBeeld(foto: foto);"),
        isTrue);
    expect(main.contains('final hoes = smal ? 112.0 : kBandHoogte - 56;'), isTrue,
        reason: 'de band laat op een gsm plaats voor de uitleg');
  });
}

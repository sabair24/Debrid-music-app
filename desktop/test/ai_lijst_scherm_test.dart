// Het AI-lijstscherm (Saber, 23-11-2026: alle vier de ontwerpen in één scherm): eerst het voorstel, niets gedownload;
// weghalen, vervangen, toevoegen, bijsturen met eerst het verschil, keuren, de mix — en dan bewaren of afspelen.
import 'package:debridmusic/ai_lijst.dart';
import 'package:debridmusic/ai_lijst_vraag.dart';
import 'package:debridmusic/ui/ai_lijst_scherm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

AiLijstVoorstel _voorstel(String zin) => AiLijstVoorstel(
      naam: 'Kerst · klassiek en modern',
      zin: zin,
      aantal: 3,
      hoeken: const [(naam: 'Klassiekers', aandeel: 50), (naam: 'Modern', aandeel: 50)],
      nummers: [
        LijstNummer(artiest: 'Bing Crosby', titel: 'White Christmas', jaar: 1942, hoek: 'Klassiekers'),
        LijstNummer(artiest: 'Mariah Carey', titel: 'All I Want for Christmas Is You', jaar: 1994, hoek: 'Modern'),
        LijstNummer(artiest: 'Verzonnen', titel: 'Bestaat Niet', hoek: 'Modern'),
      ],
      reserve: [LijstNummer(artiest: 'Wham!', titel: 'Last Christmas', jaar: 1984, hoek: 'Modern')],
    );

void main() {
  late List<String> bewaard;
  late List<String> gespeeld;

  Future<void> natrek(List<LijstNummer> l, void Function() voortgang) async {
    for (final n in l) {
      if (n.bron != LijstBron.bezig) continue;
      n.bron = n.artiest == 'Verzonnen' ? LijstBron.nergens : LijstBron.deezer;
      n.seconden = 200;
    }
    voortgang();
  }

  Widget scherm({AiLijstVrager? vrager}) {
    bewaard = [];
    gespeeld = [];
    return MaterialApp(
      home: AiLijstPagina(
        zin: '3 kerstliedjes',
        vrager: vrager ??
            AiLijstVrager(
              maakLokaal: (zin) async => _voorstel(zin),
              bijsturenLokaal: (v, zin) async => Bijsturing(
                  weg: const [0], erbij: [LijstNummer(artiest: 'Ariana Grande', titel: 'Santa Tell Me', hoek: 'Modern')]),
            ),
        natrekken: natrek,
        opslaan: (v, id) async {
          bewaard.add('${v.naam}|${v.actief.length}|${v.verzameling}');
          return id ?? 'pl1';
        },
        afspelen: (id) async {
          gespeeld.add(id);
          return null;
        },
      ),
    );
  }

  Future<void> laad(WidgetTester tester, {AiLijstVrager? vrager}) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(scherm(vrager: vrager));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('DE KERN: de zin geeft een voorstel; wat niemand kent staat grijs en telt niet; niets is gedownload',
      (tester) async {
    await laad(tester);
    expect(find.text('White Christmas'), findsOneWidget);
    expect(find.text('niet gevonden, misschien verzonnen'), findsOneWidget);
    expect(find.textContaining('2 nummers'), findsOneWidget, reason: 'de verzonnen telt niet mee');
    expect(find.textContaining('1 niet gevonden'), findsOneWidget);
    expect(find.text('pas bij afspelen'), findsNWidgets(2));
  });

  testWidgets('✕ haalt weg, ↻ geeft een ander nummer uit de reserve, toevoegen vraagt "artiest — titel"', (tester) async {
    await laad(tester);
    await tester.tap(find.byTooltip('Uit de lijst').first);
    await tester.pump();
    expect(find.textContaining('1 nummers'), findsOneWidget);
    await tester.tap(find.byTooltip('Ander nummer').at(1));
    await tester.pump();
    expect(find.text('Last Christmas'), findsOneWidget);
    expect(find.text('All I Want for Christmas Is You'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Nummer toevoegen: artiest — titel'), 'zonder streepje');
    await tester.tap(find.text('Toevoegen'));
    await tester.pump();
    expect(find.text('Schrijf het als "artiest — titel".'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Nummer toevoegen: artiest — titel'), 'Brenda Lee — Rockin\' Around the Christmas Tree');
    await tester.tap(find.text('Toevoegen'));
    await tester.pump();
    await tester.pump();
    expect(find.text("Rockin' Around the Christmas Tree"), findsOneWidget);
  });

  testWidgets('Bijsturen: eerst het verschil, pas bij Overnemen verandert de lijst', (tester) async {
    await laad(tester);
    await tester.tap(find.text('Bijsturen').first);
    await tester.pump();
    await tester.tap(find.text('Meer modern'));
    await tester.pump();
    await tester.pump();
    expect(find.text('− Bing Crosby — White Christmas'), findsOneWidget);
    expect(find.text('+ Ariana Grande — Santa Tell Me'), findsOneWidget);
    await tester.tap(find.text('Lijst'));
    await tester.pump();
    expect(find.text('White Christmas'), findsOneWidget, reason: 'nog niets veranderd');
    await tester.tap(find.text('Bijsturen').first);
    await tester.pump();
    await tester.tap(find.text('Overnemen'));
    await tester.pump();
    await tester.tap(find.text('Lijst'));
    await tester.pump();
    expect(find.text('White Christmas'), findsNothing);
    expect(find.text('Santa Tell Me'), findsOneWidget);
  });

  testWidgets('Keuren: weg of houden, één per keer, en aan het einde wat er overblijft', (tester) async {
    await laad(tester);
    await tester.tap(find.text('Keuren'));
    await tester.pump();
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.text('Weg'));
    await tester.pump();
    expect(find.text('1 / 1'), findsOneWidget, reason: 'de volgende schuift op deze plek');
    await tester.tap(find.text('Houden'));
    await tester.pump();
    expect(find.textContaining('1 gehouden, 1 weg'), findsOneWidget);
  });

  testWidgets('Mix: toepassen kiest uit lijst en reserve volgens de hoeken', (tester) async {
    await laad(tester);
    await tester.tap(find.text('Mix'));
    await tester.pump();
    expect(find.text('Klassiekers'), findsOneWidget);
    await tester.tap(find.text('Mix toepassen'));
    await tester.pump();
    expect(find.text('White Christmas'), findsOneWidget);
    expect(find.text('All I Want for Christmas Is You'), findsOneWidget);
  });

  testWidgets('Opslaan bewaart met de naam als verzameling; Speel af bewaart en speelt', (tester) async {
    await laad(tester);
    await tester.tap(find.text('Opslaan als afspeellijst'));
    await tester.pump();
    await tester.pump();
    expect(bewaard, ['Kerst · klassiek en modern|2|Kerst · klassiek en modern']);
    await tester.tap(find.text('Speel af'));
    await tester.pump();
    await tester.pump();
    expect(gespeeld, ['pl1']);
  });

  testWidgets('een fout van de AI staat op het scherm, leesbaar', (tester) async {
    await laad(tester, vrager: AiLijstVrager(maakLokaal: (_) async => throw StateError('Er staat geen AI-sleutel in Instellingen.')));
    expect(find.textContaining('geen AI-sleutel'), findsOneWidget);
    expect(find.text('Maak de lijst'), findsOneWidget);
  });
}

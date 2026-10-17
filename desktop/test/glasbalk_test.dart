/// Van de bovenrand van het venster tot in de pagina: één doorlopend geheel.
///
/// **Wat hier misging.** De vastgezette balk boven de albumpagina schilderde altijd een
/// half-dekkende tint over de was — van boven tot onder, en met een harde rand waar hij ophield. Die
/// tint is de bovenkant van de was en dus een DONKERE kleur, waardoor de strook donkerder werd dan
/// alles eromheen. Op het scherm zag je zo drie banen onder elkaar met zichtbare naden ertussen,
/// terwijl daar één oppervlak hoort te liggen.
///
/// En die baan had geen reden om er te zijn. Wat een vastgezette balk moet doen is verhinderen dat je
/// de tracklijst dwars door de knoppen heen leest. Staat de lijst bovenaan, dan schuift er niets
/// onder — dan is er niets te verbergen.
///
/// Vier beweringen, en ze horen bij elkaar: alleen samen zeggen ze "geen baan, en toch leesbaar".
library;

import 'dart:ui' show ImageFilter;

import 'package:debridmusic/tv.dart';
import 'package:debridmusic/ui/glas.dart';
import 'package:debridmusic/ui/vlak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// De balk zoals de albumpagina hem gebruikt: als `flexibleSpace` van een vastgezette SliverAppBar,
/// met de ruimte van de zwevende balk als inzet bovenaan. Daar zijn de randvoorwaarden LOS.
Widget _inAlbumbalk(Widget glas) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(960, 540), padding: EdgeInsets.only(top: 75)),
        child: Scaffold(
          body: CustomScrollView(slivers: [
            SliverAppBar(pinned: true, flexibleSpace: glas),
            const SliverToBoxAdapter(child: SizedBox(height: 2000)),
          ]),
        ),
      ),
    );

void main() {
  // Shield, 17-10-2026: op de albumpagina liep de beschrijving dwars door de capsule en de terugpijl,
  // ook nadat de strook "dicht" was gezet. Hij tekende niet: 0 hoog in de losse flexibleSpace.
  group('DE VAL: in een echte albumbalk is de strook er ook', () {
    for (final (naam, tv, plat) in [('tv', true, false), ('zonder vervaging (gsm, iPad)', false, true)]) {
      testWidgets(naam, (t) async {
        setTvModeForTest(tv);
        addTearDown(() => setTvModeForTest(false));
        await t.pumpWidget(_inAlbumbalk(balkGlas(const Color(0xFF07080C), 1, dicht: true, plat: plat)));
        final vulling = find.descendant(of: find.byType(SliverAppBar), matching: find.byType(DecoratedBox)).first;
        expect(t.getSize(vulling).height, 131, reason: 'de strook hoort de hele balk te dekken, niet 0 hoog te zijn');
      });
    }
  });

  const tint = Color(0xFF3A1D22);

  tearDown(() => setTvModeForTest(false));

  Future<void> zet(WidgetTester t, double op, {bool dicht = false}) => t.pumpWidget(
        MaterialApp(home: SizedBox(height: 56, child: balkGlas(tint, op, dicht: dicht))),
      );

  /// Het verloop dat de balk werkelijk schildert, of null als hij niets schildert.
  LinearGradient? verloop(WidgetTester t) {
    final vlakken = t.widgetList<DecoratedBox>(find.byType(DecoratedBox));
    for (final v in vlakken) {
      final d = v.decoration;
      if (d is BoxDecoration && d.gradient is LinearGradient) return d.gradient as LinearGradient;
    }
    return null;
  }

  testWidgets('bovenaan de lijst tekent hij helemaal niets', (t) async {
    await zet(t, 0);
    expect(verloop(t), isNull, reason: 'geen vulling, dus geen baan over het scherm');
    expect(find.byType(BackdropFilter), findsNothing,
        reason: 'ook geen vervaging: een BackdropFilter met sigma 0 leest de achtergrond nog steeds, '
            'en dat is op een Shield het duurste wat er op het scherm staat');
  });

  testWidgets('scrollen laat het glas opkomen', (t) async {
    await zet(t, 1);
    final g = verloop(t);
    expect(g, isNotNull);
    expect(g!.colors.first.a, greaterThan(.4), reason: 'bovenaan moet er genoeg dekking zijn om de '
        'knoppen leesbaar te houden boven een doorschuivende lijst');
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('halverwege is hij zwakker dan volledig — geen schakelaar', (t) async {
    await zet(t, .5);
    final half = verloop(t)!.colors.first.a;
    await zet(t, 1);
    final vol = verloop(t)!.colors.first.a;
    expect(half, lessThan(vol));
    expect(half, greaterThan(0));
  });

  testWidgets('de onderrand lost op in plaats van te stoppen', (t) async {
    // DIT is de streep die je zag. Hield de vulling onderaan op een halve dekking op, dan stond er
    // een harde lijn dwars over het scherm precies waar de balk eindigt.
    await zet(t, 1);
    expect(verloop(t)!.colors.last.a, 0,
        reason: 'volledig doorzichtig aan de onderkant, anders is er alsnog een rand');
  });

  testWidgets('de KLEUR groeit mee met het scrollen; de vervaging is het gedeelde filter', (t) async {
    // Tot 16-10-2026 groeide de vervaging mee (24 × op). Maar elk ander getal is een ander filter, en
    // dan worden ze niet samen teruggelezen (ui/glas.dart). Nu loopt de vulling mee, en komt de
    // vervaging pas als er echt iets onder doorschuift.
    await zet(t, 1);
    expect(identical(t.widget<BackdropFilter>(find.byType(BackdropFilter)).filter, glasMat), isTrue);
    final vol = verloop(t)!.colors.first.a;
    await zet(t, .25);
    expect(verloop(t)!.colors.first.a, lessThan(vol), reason: 'de kleur komt geleidelijk op');
    await zet(t, .1);
    expect(find.byType(BackdropFilter), findsNothing, reason: 'nauwelijks iets eronder: alleen kleur');
  });

  testWidgets('op een televisie geen vervaging, wel een dichtere vulling', (t) async {
    // Een BackdropFilter is de enige laag die Flutter niet kan bewaren. Op een Tegra X1 is dat het
    // duurste wat er op het scherm staat, en daar wordt hij dus vervangen door meer dekking.
    setTvModeForTest(true);
    await zet(t, 1);
    expect(find.byType(BackdropFilter), findsNothing);
    final g = verloop(t)!;
    expect(g.colors.first.a, greaterThan(.9));
    // Ook daar geen streep onderaan.
    expect(g.colors.last.a, 0);
  });

  testWidgets('en op een televisie bovenaan de lijst nog steeds niets', (t) async {
    setTvModeForTest(true);
    await zet(t, 0);
    expect(verloop(t), isNull);
  });

  testWidgets('de vulling is GEEN kind van de vervaging', (t) async {
    // **De fout die dit vastlegt, en waarom hij zo lang onzichtbaar bleef.**
    //
    // De vulling stond als kind ván de `BackdropFilter`. Op een pc werkte dat en zag je glas. Op een
    // Android-telefoon liep de albumbeschrijving kraakhelder dwars door de knoppen heen — géén
    // wazigheid en géén kleur.
    //
    // Dat "en géén kleur" was de aanwijzing. Een vulling is een gewoon gekleurd vlak en tekent
    // altijd, tenzij hij niet getekend WORDT. Als kind van een vervaging die het toestel laat vallen
    // — en dat gebeurt op Android met een BackdropFilter binnen de clip van een scrollende lijst —
    // verdwijnt hij mee.
    //
    // Naast elkaar overleeft de kleur het dus als de vervaging sneuvelt. Minder mooi, wel leesbaar,
    // en dat is de goede kant om op te falen. Deze toets bestaat omdat de tien andere allemaal groen
    // stonden terwijl er op het toestel niets te zien was: die keken of de lagen er WAREN, niet hoe
    // ze zich tot elkaar verhouden.
    await zet(t, 1);
    final gekleurd = find.byWidgetPredicate((w) =>
        w is DecoratedBox &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).gradient != null);
    expect(gekleurd, findsOneWidget);
    expect(find.descendant(of: find.byType(BackdropFilter), matching: gekleurd), findsNothing,
        reason: 'valt de vervaging weg, dan gaat de kleur mee — en dan staat er niets');
  });

  group('op een telefoon staat het glas steviger', () {
    // **Waarom daar een ander getal hoort.** Op een pc is deze balk 64 punten hoog boven een breed
    // venster; er schuift per keer weinig onderdoor. Op een telefoon staat de tekst van rand tot
    // rand en is de balk het enige tussen zes witte pictogrammen en een lopende alinea. Gemeld en
    // op het toestel gezien: bij dezelfde dekking las de bovenste regel van de albumbeschrijving
    // gewoon dwars door de knoppen heen.

    testWidgets('meer dekking dan op een breed scherm', (t) async {
      await zet(t, 1);
      final breed = verloop(t)!.colors.first.a;
      await zet(t, 1, dicht: true);
      final smal = verloop(t)!.colors.first.a;
      expect(smal, greaterThan(breed));
      expect(smal, greaterThan(.7), reason: 'genoeg om een alinea eronder te dempen');
    });

    testWidgets('en echte vervaging, want dát is wat letters onleesbaar maakt', (t) async {
      // Alleen dekking erbij zou de knoppen op een BALK zetten, en dat is precies wat er niet mag
      // zijn. Het is de vervaging die het glas maakt — het gedeelde filter, ook hier.
      await zet(t, 1, dicht: true);
      expect(identical(t.widget<BackdropFilter>(find.byType(BackdropFilter)).filter, glasMat), isTrue);
    });

    testWidgets('bij stilstand nog steeds helemaal niets', (t) async {
      // De hele afspraak van deze balk. Steviger glas mag nooit betekenen dat er bovenaan de lijst
      // opeens wél een baan over het scherm staat.
      await zet(t, 0, dicht: true);
      expect(verloop(t), isNull);
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('en de onderrand lost ook daar op', (t) async {
      await zet(t, 1, dicht: true);
      expect(verloop(t)!.colors.last.a, 0);
    });
  });
}

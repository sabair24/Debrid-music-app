/// Het jaarlint moet blijven staan waar het staat als je een sectie openklapt.
///
/// **Waarom dit bestaat.** Het OVER-blok woont in een `SliverToBoxAdapter`, en die geeft zijn kind
/// een ONBEGRENSDE hoogte: alles wat open staat wordt ingedeeld en getekend. Het Nederlandse
/// artikel van Michael Jackson is 37.367 tekens in 26 secties — allemaal tegelijk open is
/// twintigduizend punten tekst onder je vinger.
///
/// Twee ontwerpbeslissingen houden dat in toom, en allebei zijn ze onzichtbaar zodra ze werken:
///
/// * **De volgorde.** Het lint en de beeldband staan BOVEN de secties. Stonden ze eronder, dan duwt
///   één opengeklapte sectie ze duizenden punten naar beneden en van het scherm af — en dan is het
///   ding waar dit blok om draait onbereikbaar zodra je iets leest.
/// * **Eén sectie tegelijk.** Een harmonica begrenst de hoogte per constructie.
///
/// Geen van beide is af te lezen aan een schermafdruk van één stand. Vandaar deze toets: hij meet
/// waar het lint stáát, klapt een sectie open, en meet opnieuw.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/enrichment.dart';
import 'package:debridmusic/jaarlint.dart';
import 'package:debridmusic/overblok.dart';
import 'package:debridmusic/tv.dart';
import 'package:debridmusic/wikipedia.dart';

const _feiten = ArtiestFeiten(
  geboren: '29 augustus 1958 · Gary, Indiana',
  geborenJaar: 1958,
  gestorvenJaar: 2009,
  land: 'Verenigde Staten',
  label: 'Epic',
);

/// Secties met genoeg tekst om het blok merkbaar te laten groeien.
List<WikiAfdeling> _secties(int n) => [
      for (var i = 0; i < n; i++)
        WikiAfdeling(niveau: 2, kop: 'Hoofdstuk $i', tekst: List.filled(60, 'zin $i.').join(' ')),
    ];

const _jaren = <Jaarpunt>[
  Jaarpunt(jaar: 1958, soort: Jaarsoort.geboorte, label: 'Geboren'),
  Jaarpunt(jaar: 1982, soort: Jaarsoort.plaat, label: 'Thriller', plaatSleutel: 'thriller'),
  Jaarpunt(jaar: 1987, soort: Jaarsoort.plaat, label: 'Bad', plaatSleutel: 'bad'),
  Jaarpunt(jaar: 2009, soort: Jaarsoort.overlijden, label: 'Overleden'),
];

/// In een `CustomScrollView` met een `SliverToBoxAdapter`, want dat is waar dit blok echt woont —
/// en juist die combinatie geeft het kind een onbegrensde hoogte.
///
/// Het VENSTER is bewust hoog (zie [_grootScherm]): niet om het makkelijk te maken, maar omdat deze
/// toets meet waar het lint STAAT. Zou er gescrold moeten worden om een kop aan te tikken, dan
/// verschuift het lint door dat scrollen en meet je je eigen scrollbeweging in plaats van het
/// gedrag dat je wilt vastleggen.
const _grootScherm = Size(1240, 3000);

Widget _omhulsel(Widget kind, {bool zonderAnimatie = false}) => MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(size: _grootScherm, disableAnimations: zonderAnimatie),
          child: CustomScrollView(slivers: [SliverToBoxAdapter(child: kind)]),
        ),
      ),
    );

OverBlok _blok({int secties = 6, bool metBeeld = true}) => OverBlok(
      naam: 'Michael Jackson',
      feiten: _feiten,
      jaren: _jaren,
      artikel: WikiArtikel(
        taal: 'nl',
        titel: 'Michael Jackson',
        intro: 'Michael Joseph Jackson was een Amerikaans zanger.\n'
            'Hij geldt als een van de succesvolste artiesten van de 20e eeuw.',
        afdelingen: _secties(secties),
      ),
      // Een stomp: van een jaartal naar een echt beeld komen hoort op de artiestpagina thuis, en
      // dat is precies waarom die bouwer geïnjecteerd wordt.
      beeldVoorJaar: metBeeld
          ? (p, teller) => ColoredBox(
                color: Colors.blue.shade900,
                child: Text('beeld ${p.jaar} tik $teller'),
              )
          : null,
    );

void main() {
  setUp(() => setTvModeForTest(false));

  tearDown(() => setTvModeForTest(false));

  Future<void> pomp(WidgetTester t, Widget kind) async {
    // Binnen de toets teruggezet en niet in een `tearDown`: `setSurfaceSize` staat erop dat er een
    // toets loopt, en een gewone tearDown draait daarbuiten.
    await t.binding.setSurfaceSize(_grootScherm);
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(kind);
    await t.pumpAndSettle();
  }

  testWidgets('DE KERN: ingeklapt staat de feitenstrook, de eerste alinea en de uitklapper', (t) async {
    await pomp(t, _omhulsel(_blok()));

    expect(find.text('GEBOREN'), findsOneWidget);
    expect(find.text('ACTIEF'), findsOneWidget);
    expect(find.text('1958 – 2009'), findsOneWidget);
    expect(find.textContaining('Amerikaans zanger'), findsOneWidget);
    expect(find.text('Meer lezen'), findsOneWidget);

    // En de staart nog niet: geen jaartallen, geen sectiekoppen.
    expect(find.text('1982'), findsNothing,
        reason: 'het jaarlint hoort pas bij het uitklappen te verschijnen');
    expect(find.text('HOOFDSTUK 0'), findsNothing);
  });

  testWidgets('DE KERN: het jaarlint blijft staan als een sectie opengaat', (t) async {
    await pomp(t, _omhulsel(_blok()));
    await t.tap(find.text('Meer lezen'));
    await t.pumpAndSettle();

    expect(find.text('1982'), findsOneWidget, reason: 'het lint hoort er na het uitklappen te staan');
    final voor = t.getTopLeft(find.text('1982')).dy;

    await t.tap(find.text('HOOFDSTUK 3'));
    await t.pumpAndSettle();

    expect(find.textContaining('zin 3.'), findsOneWidget, reason: 'de sectie ging niet open');
    expect(t.getTopLeft(find.text('1982')).dy, voor,
        reason: 'het jaarlint schuift van het scherm zodra je een hoofdstuk opent');
  });

  testWidgets('DE VAL: er staat er hoogstens één open', (t) async {
    await pomp(t, _omhulsel(_blok()));
    await t.tap(find.text('Meer lezen'));
    await t.pumpAndSettle();

    await t.tap(find.text('HOOFDSTUK 1'));
    await t.pumpAndSettle();
    expect(find.textContaining('zin 1.'), findsOneWidget);

    await t.tap(find.text('HOOFDSTUK 4'));
    await t.pumpAndSettle();
    expect(find.textContaining('zin 4.'), findsOneWidget);
    expect(find.textContaining('zin 1.'), findsNothing,
        reason: 'twee open hoofdstukken maken van het blok een muur van tekst');
  });

  testWidgets('DE VAL: dichtklappen sluit ook de open sectie', (t) async {
    // Anders begint de VOLGENDE uitklap met een sectie al open, en dan meet de hoogte-animatie
    // elke frame een kind van duizenden punten.
    await pomp(t, _omhulsel(_blok()));
    await t.tap(find.text('Meer lezen'));
    await t.pumpAndSettle();
    await t.tap(find.text('HOOFDSTUK 2'));
    await t.pumpAndSettle();
    expect(find.textContaining('zin 2.'), findsOneWidget);

    await t.tap(find.text('Minder lezen'));
    await t.pumpAndSettle();
    await t.tap(find.text('Meer lezen'));
    await t.pumpAndSettle();

    expect(find.textContaining('zin 2.'), findsNothing,
        reason: 'elke uitklap hoort schoon te beginnen');
  });

  testWidgets('DE KERN: een jaartal aanwijzen wisselt het beeld', (t) async {
    await pomp(t, _omhulsel(_blok()));
    await t.tap(find.text('Meer lezen'));
    await t.pumpAndSettle();

    expect(find.textContaining('beeld 1987'), findsOneWidget,
        reason: 'de band begint bij de nieuwste plaat, niet bij een leeg vak');

    await t.tap(find.text('1982'));
    await t.pump();
    await t.pump(const Duration(seconds: 7));
    expect(find.textContaining('beeld 1982'), findsOneWidget);
  });

  testWidgets('DE VAL: hetzelfde jaartal opnieuw aanwijzen laat de teller oplopen', (t) async {
    // Dit is wat de cd opnieuw uit de hoes haalt. Zonder oplopende teller gebeurt er bij een
    // tweede klik op hetzelfde jaartal niets, en dan leest het gebaar dood — zie
    // `uitschuif_herhaling_test.dart` voor de andere helft van diezelfde belofte.
    await pomp(t, _omhulsel(_blok()));
    await t.tap(find.text('Meer lezen'));
    await t.pumpAndSettle();

    await t.tap(find.text('1982'));
    await t.pumpAndSettle();
    expect(find.textContaining('beeld 1982 tik 1'), findsOneWidget);

    await t.tap(find.text('1982'));
    await t.pumpAndSettle();
    expect(find.textContaining('beeld 1982 tik 2'), findsOneWidget,
        reason: 'een tweede klik op hetzelfde jaartal komt niet bij de beeldband aan');
  });

  testWidgets('DE GRENS: zonder animaties opent hij in één pomp en laat geen ticker achter', (t) async {
    // `pumpAndSettle` zou hier eeuwig doordraaien als er een controller bleef lopen, en de
    // toetsomgeving klaagt zelf over een ticker die niet opgeruimd is — dat is de halve assertie
    // gratis.
    await pomp(t, _omhulsel(_blok(), zonderAnimatie: true));
    await t.pump();

    await t.tap(find.text('Meer lezen'));
    await t.pump();
    expect(find.text('1982'), findsOneWidget,
        reason: 'met animaties uit hoort het venster meteen open te staan');

    await t.pumpWidget(const SizedBox());
    expect(t.takeException(), isNull);
  });

  testWidgets('DE GRENS: zonder artikel valt hij terug op de oude bron', (t) async {
    await pomp(t, _omhulsel(const OverBlok(
      naam: 'Iemand',
      audiodbTekst: 'Een korte biografie uit TheAudioDB.',
    )));
    expect(find.textContaining('TheAudioDB'), findsOneWidget);
    // En geen bronvermelding van Wikipedia waar geen Wikipedia-tekst staat.
    expect(find.textContaining('CC BY-SA'), findsNothing);
  });

  testWidgets('DE VAL: de bronvermelding staat er zodra er Wikipedia-tekst is', (t) async {
    // CC BY-SA is geen ontwerpkeuze maar een voorwaarde. Verdwijnt deze regel, dan verspreidt de
    // app andermans tekst zonder vermelding.
    await pomp(t, _omhulsel(_blok(secties: 2)));
    await t.tap(find.text('Meer lezen'));
    await t.pumpAndSettle();
    expect(find.textContaining('CC BY-SA'), findsOneWidget);
    expect(find.textContaining('Wikipedia'), findsOneWidget);
  });

  testWidgets('DE GRENS: helemaal leeg tekent niets in plaats van een leeg kader', (t) async {
    await pomp(t, _omhulsel(const OverBlok(naam: 'Niemand')));
    expect(find.text('Meer lezen'), findsNothing);
  });
}

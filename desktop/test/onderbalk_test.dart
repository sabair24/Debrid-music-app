/// De balk onderaan een telefoonscherm, opgemeten.
///
/// **Waarom dit bestaat.** Deze balk is twee keer lager gemaakt zonder dat er op het toestel iets
/// veranderde. Van 66+62 naar 56+56 stond in de code, zat in build 11059, en werd bekeken met
/// "de balk is nog hetzelfde" — terecht, want zestien punten op een stapel van ruim honderdveertig
/// ziet niemand. Het probleem was niet dat het getal niet aankwam maar dat er niet genoeg af ging,
/// en dat verschil was met het blote oog niet te maken.
///
/// Een hoogte onderaan een telefoonscherm valt hier verder niet te controleren: er draait geen
/// Flutter op de machine waar dit geschreven wordt, en de shell eromheen heeft veertien providers
/// en een libmpv die in een toetsrun niet bestaat. [Onderbalk] staat daarom los van de shell — hij
/// krijgt een nummer en een terugroep, geen stores — en dat is precies genoeg om hem op te meten.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/ui/menu_iconen.dart' show MenuIcoon, MenuIcoonSchilder;

import 'package:debridmusic/main.dart';
import 'package:debridmusic/tv.dart';

/// Een Galaxy S26 met veegbediening: 411 punten breed, en onderaan een systeeminzet die de balk
/// zelf moet vrijhouden.
///
/// De [MediaQuery] staat BINNEN de MaterialApp en niet eromheen: die bouwt de zijne uit het venster
/// en zou een die er omheen staat overschrijven. Geen Scaffold, want die haalt onder omstandigheden
/// juist de onderste inzet weg — en dat is hier de helft van de meting. `Material` staat er wel
/// omheen; de knoppen tekenen hun aanraking erin.
Widget omhulsel(Widget kind, {double inzet = 24}) => MaterialApp(
      // `copyWith` en geen verse MediaQueryData: die zou de lettergrootte van het toestel meteen
      // weer op 1.0 zetten, en dat is precies wat de laatste toets hieronder meet.
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: EdgeInsets.only(bottom: inzet),
            viewPadding: EdgeInsets.only(bottom: inzet),
          ),
          child: Material(
            color: const Color(0xFF0B0D14),
            child: Column(children: [const Spacer(), kind]),
          ),
        ),
      ),
    );

void telefoon(WidgetTester tester) {
  tester.view.physicalSize = const Size(411 * 3, 891 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('de balk is 48 hoog, plus de systeeminzet en niets anders', (tester) async {
    telefoon(tester);
    await tester.pumpWidget(omhulsel(Onderbalk(view: 0, onPick: (_) {})));

    // DE meting. Material's NavigationBar hield binnen een opgegeven hoogte zijn eigen maten aan;
    // deze balk niet, en dat is het hele punt van hem zelf tekenen.
    expect(tester.getSize(find.byType(Onderbalk)).height, Onderbalk.hoogte + 24);
  });

  testWidgets('de systeeminzet komt van het toestel en niet uit een vast getal', (tester) async {
    // Een toestel met drie knoppen heeft er ongeveer 48 onder, een met veegbediening 24, en in een
    // venster op een tablet niets. De balk mag die ruimte niet zelf verzinnen en er ook niet
    // doorheen zakken.
    telefoon(tester);

    await tester.pumpWidget(omhulsel(Onderbalk(view: 0, onPick: (_) {}), inzet: 0));
    expect(tester.getSize(find.byType(Onderbalk)).height, Onderbalk.hoogte);

    await tester.pumpWidget(omhulsel(Onderbalk(view: 0, onPick: (_) {}), inzet: 48));
    expect(tester.getSize(find.byType(Onderbalk)).height, Onderbalk.hoogte + 48);
  });

  testWidgets('alle vijf de secties staan erin en vangen een tik', (tester) async {
    telefoon(tester);
    final getikt = <int>[];
    await tester.pumpWidget(omhulsel(Onderbalk(view: 5, onPick: getikt.add)));

    expect(find.byType(MenuIcoon), findsNWidgets(NavSections.balk.length),
        reason: 'de bewegende lijniconen van het menu (17-10-2026)');

    // Elk vak is de volle balk hoog en niet alleen zijn pictogram. Een knop van 26 punten in een
    // balk van 48 laat de helft van wat eruitziet als een knop geen tik vangen, en dat leest als
    // een app die soms niet reageert.
    for (var i = 0; i < NavSections.balk.length; i++) {
      expect(tester.getSize(find.byType(Pressable).at(i)).height, Onderbalk.hoogte);
    }

    // `tap` weigert een plek die geen tik kan vangen, dus dit is meteen de controle dat er niets
    // buiten de balk valt — de fout die op de artiestpagina twee keer gemaakt is.
    for (var i = 0; i < NavSections.balk.length; i++) {
      await tester.tap(find.byType(MenuIcoon).at(i));
    }
    expect(getikt, NavSections.balk);
  });

  testWidgets('kiezen laat het icoon zijn beweging spelen: het blijft hetzelfde icoon', (tester) async {
    // Op de S26 sprong de noot van Tracks nooit (18-10-2026): de pil om het icoon kwam er met een
    // `Container`-decoratie bij, de boom veranderde van vorm en het icoon werd opnieuw gemaakt.
    final tracks = NavSections.balk.indexOf(4);
    await tester.pumpWidget(omhulsel(Onderbalk(view: 0, onPick: (_) {})));
    final voor = tester.state(find.byType(MenuIcoon).at(tracks));
    await tester.pumpWidget(omhulsel(Onderbalk(view: 4, onPick: (_) {})));
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.state(find.byType(MenuIcoon).at(tracks)), same(voor), reason: 'hetzelfde icoon, geen nieuw');
    final schilder = tester
        .widget<CustomPaint>(find.descendant(of: find.byType(MenuIcoon).at(tracks), matching: find.byType(CustomPaint)))
        .painter! as MenuIcoonSchilder;
    expect(schilder.t, lessThan(1), reason: 'de beweging loopt');
    expect(schilder.vul, inExclusiveRange(0, 1), reason: 'hij loopt vol, hij staat niet meteen vol');
    await tester.pumpAndSettle();
  });

  testWidgets('alleen de gekozen sectie draagt zijn naam', (tester) async {
    telefoon(tester);
    await tester.pumpWidget(omhulsel(Onderbalk(view: 3, onPick: (_) {})));

    expect(find.text('Ontdek'), findsOneWidget);
    expect(find.text('Albums'), findsNothing);
    // De korte naam, niet die uit de la: "Online zoeken" past niet onder een pictogram van veertig
    // punten breed.
    expect(find.text('Online zoeken'), findsNothing);
  });

  testWidgets('een sectie uit de la laat de balk nergens naar wijzen', (tester) async {
    telefoon(tester);
    // 6 is "Mijn downloads" en staat niet in de balk. Zet je de aanwijzing dan op de eerste knop,
    // dan wijst hij naar Start terwijl je op Downloads staat.
    await tester.pumpWidget(omhulsel(Onderbalk(view: 6, onPick: (_) {})));

    // Het bijschrift is wat oplicht; staat er geen enkel, dan wijst de balk nergens naar.
    expect(find.byType(Text), findsNothing);
    expect(find.byType(MenuIcoon), findsNWidgets(NavSections.balk.length));
  });

  testWidgets('grotere systeemletters laten de balk niet overlopen', (tester) async {
    telefoon(tester);
    // 1.5 is wat Android's schuifje op de hoogste stand doet. Zonder vangnet wordt het bijschrift
    // dan hoger dan de balk, en tekent Flutter gele strepen dwars over de knoppen.
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(omhulsel(Onderbalk(view: 0, onPick: (_) {})));

    expect(tester.takeException(), isNull);
    // En hij is er niet stilletjes hoger van geworden.
    expect(tester.getSize(find.byType(Onderbalk)).height, Onderbalk.hoogte + 24);
  });
}

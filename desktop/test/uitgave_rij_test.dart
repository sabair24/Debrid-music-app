/// Eén rij van de uitgavekiezer, opgemeten op een telefoon.
///
/// **Waarom dit bestaat.** Deze ene rij is vier keer op rij op precies dezelfde manier misgegaan,
/// en elke keer was er een schermafbeelding van het toestel voor nodig om het te merken:
///
///   1. de knoppen stonden naast drie scans en vielen buiten de rij — onzichtbaar én niet aan te
///      tikken, want `RenderBox.hitTest` slaat alles buiten `size` over;
///   2. de knoppen kregen een eigen regel, maar de tekst stond nog naast de scans en hield er
///      vijfentachtig punten over: de titel was na drie letters op;
///   3. de bordjes ernaast liepen daardoor stuk voor stuk over de rand ("achterkar");
///   4. en het molentje ernaast deed hetzelfde, omdat het in een eigen Row zat die geen
///      breedtegrens meekrijgt.
///
/// Flutter meldt zoiets niet uit zichzelf op een toestel: het tekent gewoon door. In een TOETS
/// doet het dat wel — een overloop is daar een echte fout. Dus is dit een vraag voor de machine,
/// en had hij dat vanaf de eerste keer moeten zijn.
///
/// Wat hier NIET in staat, en wat dus nog steeds ogen vraagt: of het er goed uitziet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/editions.dart';
import 'package:debridmusic/main.dart';

const _plaatje = ChoiceImage('https://x/vol.jpg', 'https://x/klein.jpg');

/// Een uitgave met alles erop en eraan: het langste geval, en dus het krapste.
ReleaseChoice rij({bool volledig = true}) => ReleaseChoice(
      source: EditionSource.discogs,
      releaseId: 22877906,
      format: 'CD',
      label: 'Virgin',
      catno: 'CDV 2812',
      country: 'South Africa',
      year: 1996,
      front: volledig ? _plaatje : null,
      back: volledig ? _plaatje : null,
      disc: volledig ? _plaatje : null,
      detailed: volledig,
    );

/// De breedte die de rij in het echt krijgt.
///
/// De keten: schermbreedte → `Dialog` haalt er 40 punten aan elke kant af (zijn eigen
/// `insetPadding`) → de dialoog haalt er zijn `Padding(20)` aan elke kant af → dat is de lijst.
/// 411 − 80 − 40 = 291; 360 − 80 − 40 = 240.
double lijstbreedte(double scherm) => scherm - 80 - 40;

/// In een ListView, want dat is waar de rij in het echt staat.
///
/// Dat is geen decor. Een ListView geeft zijn kind een VASTE breedte en een onbegrensde hoogte; een
/// Center geeft allebei los, en dan rekt de tekstkolom (een Column met mainAxisSize.max) zich uit
/// tot de volle schermhoogte en staan de knoppen ergens halverwege het niets. De eerste versie van
/// deze toets deed dat, en meldde daardoor een fout in de app die in de TOETS zat.
Widget omhulsel(Widget kind, double scherm) => MaterialApp(
      home: Material(
        color: const Color(0xFF0B0D14),
        child: SizedBox(
          width: lijstbreedte(scherm),
          child: ListView(children: [kind]),
        ),
      ),
    );

void telefoon(WidgetTester tester, {required double breedte, double hoogte = 891}) {
  tester.view.physicalSize = Size(breedte * 3, hoogte * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Ligt [wat] helemaal binnen [kader]?
void binnen(WidgetTester tester, Finder wat, Finder kader, String naam) {
  final k = tester.getRect(kader);
  for (var i = 0; i < tester.widgetList(wat).length; i++) {
    final r = tester.getRect(wat.at(i));
    expect(r.left, greaterThanOrEqualTo(k.left - 0.5), reason: '$naam #$i steekt links uit de rij');
    expect(r.right, lessThanOrEqualTo(k.right + 0.5), reason: '$naam #$i steekt rechts uit de rij');
    expect(r.top, greaterThanOrEqualTo(k.top - 0.5), reason: '$naam #$i steekt boven de rij uit');
    expect(r.bottom, lessThanOrEqualTo(k.bottom + 0.5), reason: '$naam #$i valt onder de rij');
  }
}

UitgaveRij bouw({
  bool volledig = true,
  bool vastgezet = false,
  List<String>? getikt,
}) =>
    UitgaveRij(
      uitgave: rij(volledig: volledig),
      vastgezet: vastgezet,
      onKiezen: () => getikt?.add('kiezen'),
      onScans: () => getikt?.add('scans'),
      onNummering: () => getikt?.add('nummering'),
      onKlaarzetten: (rol, _) => getikt?.add('klaarzetten:$rol'),
    );

void main() {
  for (final breedte in [411.0, 360.0]) {
    group('staand op $breedte punten', () {
      testWidgets('er loopt niets over', (tester) async {
        telefoon(tester, breedte: breedte);
        await tester.pumpWidget(omhulsel(bouw(vastgezet: true), breedte));
        // DE regel. Een overloop is in een toets een echte fout, en dit is precies wat er vier keer
        // is misgegaan zonder dat iets het zei.
        expect(tester.takeException(), isNull);
      });

      testWidgets('alle knoppen liggen binnen de rij en vangen een tik', (tester) async {
        telefoon(tester, breedte: breedte);
        final getikt = <String>[];
        await tester.pumpWidget(omhulsel(bouw(getikt: getikt), breedte));

        binnen(tester, find.byType(IconButton), find.byType(UitgaveRij), 'knop');

        // `tap` weigert een plek die geen tik kan vangen — dus dit is meteen de controle dat een
        // knop niet half buiten de rij ligt. Precies de fout uit ronde 1.
        await tester.tap(find.byIcon(Icons.photo_library_outlined));
        await tester.tap(find.byIcon(Icons.format_list_numbered_rounded));
        expect(getikt, ['scans', 'nummering']);
      });

      testWidgets('de drie scans liggen binnen de rij', (tester) async {
        telefoon(tester, breedte: breedte);
        await tester.pumpWidget(omhulsel(bouw(), breedte));
        for (final naam in ['hoes', 'achter', 'cd']) {
          binnen(tester, find.text(naam), find.byType(UitgaveRij), naam);
        }
      });

      testWidgets('de beschrijving wordt niet tot drie letters geknepen', (tester) async {
        telefoon(tester, breedte: breedte);
        await tester.pumpWidget(omhulsel(bouw(), breedte));
        // Ronde 2: de tekstkolom stond naast de scans en hield 85 punten over, dus stond er
        // "CD · So…" waar "CD · South Africa · CDV 2812 · 1996" hoort te staan. Een derde van de
        // breedte is een ondergrens die daar ruim onder ligt en hier ruim boven.
        final regel = tester.getRect(find.textContaining('CD ·'));
        expect(regel.width, greaterThan(lijstbreedte(breedte) / 2),
            reason: 'de titel krijgt maar ${regel.width} punten');
      });

      testWidgets('een rij die nog op zijn scans wacht loopt ook niet over', (tester) async {
        // Ronde 4: het molentje met "scans ophalen…" zit in een eigen Row, en die geeft zijn
        // kinderen geen breedtegrens.
        telefoon(tester, breedte: breedte);
        await tester.pumpWidget(omhulsel(bouw(volledig: false), breedte));
        expect(tester.takeException(), isNull);
        expect(find.text('scans ophalen…'), findsOneWidget);
      });

      testWidgets('en met grote systeemletters evenmin', (tester) async {
        telefoon(tester, breedte: breedte);
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(omhulsel(bouw(vastgezet: true), breedte));
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('liggend past het op één regel, en ook daar loopt niets over', (tester) async {
    // 915 breed is dezelfde telefoon gedraaid. Daar is `isCompact` onwaar en kiest de rij de
    // eenregelige vorm — die moet het dan ook echt zijn.
    telefoon(tester, breedte: 915, hoogte: 411);
    final getikt = <String>[];
    await tester.pumpWidget(omhulsel(bouw(getikt: getikt), 915));

    expect(tester.takeException(), isNull);
    binnen(tester, find.byType(IconButton), find.byType(UitgaveRij), 'knop');

    // Eén regel: de knop staat naast de scans, niet eronder.
    final hoes = tester.getRect(find.text('hoes'));
    final knop = tester.getRect(find.byIcon(Icons.photo_library_outlined));
    expect(knop.top, lessThan(hoes.bottom), reason: 'liggend hoort alles op één regel te staan');

    await tester.tap(find.byIcon(Icons.format_list_numbered_rounded));
    expect(getikt, ['nummering']);
  });

  testWidgets('een scan aantikken zet hem klaar voor zijn eigen rol', (tester) async {
    telefoon(tester, breedte: 411);
    final getikt = <String>[];
    await tester.pumpWidget(omhulsel(bouw(getikt: getikt), 411));
    await tester.tap(find.text('cd'));
    expect(getikt, ['klaarzetten:disc']);
  });

  testWidgets('wat de gebruiker zelf aanwees gaat vóór de gok van de app', (tester) async {
    telefoon(tester, breedte: 411);
    // Zonder eigen keuze staat er wat Discogs dacht; met eigen keuze die van de gebruiker. Dat is
    // wat "ik wijzig het maar zie het niet" moest oplossen.
    const eigen = ChoiceImage('https://x/schijf.jpg', 'https://x/schijf-klein.jpg');
    await tester.pumpWidget(omhulsel(
      UitgaveRij(
        uitgave: rij(),
        eigenScans: const {'disc': eigen},
        onKiezen: () {},
        onScans: () {},
        onNummering: () {},
        onKlaarzetten: (_, __) {},
      ),
      411,
    ));
    // `cacheWidth` verpakt de bron in een ResizeImage, dus het adres zit een laagje dieper.
    String? adres(ImageProvider p) => p is NetworkImage
        ? p.url
        : p is ResizeImage
            ? adres(p.imageProvider)
            : null;
    final adressen = [
      for (final b in tester.widgetList<Image>(find.byType(Image))) adres(b.image),
    ];
    expect(adressen, contains(eigen.thumb));
  });
}

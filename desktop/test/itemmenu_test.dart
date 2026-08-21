/// Het itemmenu: welke vorm, welke strepen, en wanneer de handeling loopt.
///
/// **Waarom dit bestaat.** Het menu voelde stroef, en dat was geen gevoel maar Flutters standaard:
/// driehonderd milliseconden waarin het menu zichzelf op elk beeld opnieuw indeelt, met de laatste
/// regel die pas rond 280 ms in beeld komt. De reparatie is een blad op een telefoon en een kort
/// menu onder een muis — en dan zijn er drie dingen die stil kunnen misgaan en die je op een
/// schermafbeelding niet ziet:
///
///   1. de vorm die per toestel gekozen wordt;
///   2. een streep die overblijft omdat "Ga naar album" er niet is;
///   3. de handeling die loopt terwijl het menu nog dichtvouwt — precies de fout die er zat.
///
/// De schil is hier niet te pompen (veertien providers, een libmpv die in een toetsrun niet bestaat),
/// dus staat het menu los in `ui/itemmenu.dart`. Dat maakt dit meetbaar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/tv.dart';
import 'package:debridmusic/ui/itemmenu.dart';

MenuRegel _r(String tekst, [VoidCallback? doen]) =>
    MenuRegel(Icons.circle, tekst, doen ?? () {});

ItemMenu _menu({bool metAlbum = true, VoidCallback? opEerste}) => ItemMenu(
      titel: 'Papaoutai',
      ondertitel: 'Stromae',
      blokken: [
        [_r('Favoriet', opEerste)],
        [_r('Hierna spelen'), _r('Toevoegen aan de wachtrij')],
        [
          if (metAlbum) _r('Ga naar album'),
          _r('Ga naar artiest'),
        ],
        [_r('Zoeken met Soulseek'), _r('Verwijderen…')],
      ],
    );

void main() {
  group('welke vorm dit toestel krijgt', () {
    test('een telefoon en een tv krijgen het blad', () {
      expect(menuVorm(compact: true, tv: false), MenuVorm.blad);
      expect(menuVorm(compact: false, tv: true), MenuVorm.blad);
      expect(menuVorm(compact: true, tv: true), MenuVorm.blad);
    });

    test('een breed scherm met een muis krijgt het zwevende menu', () {
      expect(menuVorm(compact: false, tv: false), MenuVorm.zwevend);
    });
  });

  group('de strepen', () {
    test('een leeg blok valt weg, dus er blijft geen streep over', () {
      // Dit is waarom het menu blokken zijn en geen platte lijst met scheidingsposten: een nummer
      // zonder album liet anders een streep achter die nergens tussen stond.
      expect(_menu().gevuld.length, 4);
      expect(_menu(metAlbum: false).gevuld.length, 4, reason: 'blok 3 heeft nog "Ga naar artiest"');

      const kaal = ItemMenu(titel: 'x', blokken: [
        [MenuRegel(Icons.circle, 'een', _niets)],
        [],
        [MenuRegel(Icons.circle, 'twee', _niets)],
      ]);
      expect(kaal.gevuld.length, 2);
      expect(kaal.regels.length, 2);
    });

    test('nooit een streep vooraan, achteraan, of twee achter elkaar', () {
      final posten = itemMenuPosten(_menu());
      expect(posten.first, isNot(isA<PopupMenuDivider>()));
      expect(posten.last, isNot(isA<PopupMenuDivider>()));
      for (var i = 1; i < posten.length; i++) {
        expect(posten[i] is PopupMenuDivider && posten[i - 1] is PopupMenuDivider, isFalse,
            reason: 'twee strepen achter elkaar op $i');
      }
      // Zeven regels, drie strepen ertussen.
      expect(posten.length, _menu().regels.length + _menu().gevuld.length - 1);
    });

    test('een blok dat leegloopt neemt zijn streep mee', () {
      const alleenEen = ItemMenu(titel: 'x', blokken: [
        [MenuRegel(Icons.circle, 'een', _niets)],
        [],
      ]);
      expect(itemMenuPosten(alleenEen).whereType<PopupMenuDivider>(), isEmpty);
    });
  });

  group('het blad', () {
    testWidgets('elke regel staat erop, met de kop erboven', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Material(child: ItemMenuBlad(menu: _menu()))));
      expect(find.text('Papaoutai'), findsOneWidget);
      expect(find.text('Stromae'), findsOneWidget);
      for (final tekst in [
        'Favoriet',
        'Hierna spelen',
        'Toevoegen aan de wachtrij',
        'Ga naar album',
        'Ga naar artiest',
        'Zoeken met Soulseek',
        'Verwijderen…',
      ]) {
        expect(find.text(tekst), findsOneWidget, reason: '"$tekst" hoort in het blad te staan');
      }
    });

    testWidgets('zonder album staat die regel er niet', (tester) async {
      await tester
          .pumpWidget(MaterialApp(home: Material(child: ItemMenuBlad(menu: _menu(metAlbum: false)))));
      expect(find.text('Ga naar album'), findsNothing);
      expect(find.text('Ga naar artiest'), findsOneWidget);
    });

    testWidgets('veertien regels passen op een televisie, en de laatste is bereikbaar',
        (tester) async {
      // De maat waar het om gaat: een Shield is 960 bij 540 en schaalt de tekst 1,35 keer. Zonder
      // `isScrollControlled` knipt Flutter het blad af op 9/16 en zie je er vijf.
      setTvModeForTest(true);
      addTearDown(() => setTvModeForTest(false));
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final lang = ItemMenu(
        titel: 'Een nummer met een lange naam',
        ondertitel: 'Een artiest',
        blokken: [
          for (var b = 0; b < 4; b++)
            [for (var i = 0; i < 4; i++) _r('Toevoegen aan de wachtrij $b$i')],
        ],
      );
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(
            size: Size(960, 540), textScaler: TextScaler.linear(1.35)),
        child: MaterialApp(home: Material(child: ItemMenuBlad(menu: lang))),
      ));

      expect(tester.takeException(), isNull, reason: 'niets mag over de rand lopen');
      await tester.scrollUntilVisible(find.text('Toevoegen aan de wachtrij 33'), 80);
      expect(find.text('Toevoegen aan de wachtrij 33'), findsOneWidget);
    });
  });

  group('pas handelen als het menu weg is', () {
    testWidgets('de handeling loopt NA het sluiten, niet ertijdens', (tester) async {
      // DE fout die erin zat: het oude menu riep de gekozen handeling aan zodra de route gepopt
      // WERD, dus schoof een albumpagina open bovenop een menu dat nog driehonderd milliseconden
      // stond dicht te vouwen.
      var gelopen = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  toonItemMenu(context, _menu(opEerste: () => gelopen = true)),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      // Smal, dus het blad — dat is de vorm waar dit over gaat.
      tester.view.physicalSize = const Size(411, 891);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Favoriet'), findsOneWidget, reason: 'het blad hoort open te staan');

      await tester.tap(find.text('Favoriet'));
      await tester.pump(); // het blad begint te sluiten
      expect(gelopen, isFalse, reason: 'nog niet: het blad schuift nog naar beneden');

      await tester.pumpAndSettle();
      expect(gelopen, isTrue, reason: 'en nu wel, want het blad is echt weg');
    });
  });
}

void _niets() {}

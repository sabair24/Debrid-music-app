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

import 'dart:io';

import 'package:flutter/gestures.dart';
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

    test('een uitgezette regel telt gewoon mee voor de vorm', () {
      // Dat is precies waarom hij uitgezet is en niet weggelaten: bij een ontbrekend nummer werkt de
      // helft van het menu niet, en weglaten zou het menu elke keer een andere vorm geven — dan moet
      // je zoeken waar "Zoeken met Soulseek" nu weer staat.
      const half = ItemMenu(titel: 'x', blokken: [
        [MenuRegel(Icons.circle, 'Hierna spelen', _niets, uit: true)],
        [MenuRegel(Icons.circle, 'Zoeken met Soulseek', _niets)],
      ]);
      expect(half.regels.length, 2);
      expect(itemMenuPosten(half).whereType<PopupMenuDivider>().length, 1);
    });

    test('een uitgezette regel is niet te kiezen', () {
      const half = ItemMenu(titel: 'x', blokken: [
        [
          MenuRegel(Icons.circle, 'Hierna spelen', _niets, uit: true),
          MenuRegel(Icons.circle, 'Zoeken met Soulseek', _niets),
        ],
      ]);
      final posten = itemMenuPosten(half).whereType<PopupMenuItem<MenuRegel>>().toList();
      expect(posten.length, 2);
      expect(posten.first.enabled, isFalse, reason: 'grijs én dood');
      expect(posten.last.enabled, isTrue);
    });

    test('standaard staat een regel gewoon aan', () {
      expect(const MenuRegel(Icons.circle, 'x', _niets).uit, isFalse);
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

  group('bij de muis en nooit leeg (Saber, 29-10-2026)', () {
    const rij = Rect.fromLTWH(20, 300, 1360, 48);

    test('de rechtsklik wint; dan de muis als die op het ding klikte; anders rechts in het midden', () {
      expect(zweefPunt(bij: const Offset(5, 6), muis: const Offset(100, 320), ding: rij), const Offset(5, 6));
      expect(zweefPunt(muis: const Offset(100, 320), ding: rij), const Offset(100, 320),
          reason: '"dat de menu naast de muis komt niet op het einde"');
      expect(zweefPunt(muis: const Offset(100, 700), ding: rij), rij.centerRight,
          reason: 'een klik ergens anders is niet de klik die dit menu opende');
      expect(zweefPunt(ding: rij), rij.centerRight, reason: 'zonder muis (toetsenbord) aan het ding zelf');
    });

    Widget breed(ItemMenu menu) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Padding(
                padding: const EdgeInsets.only(top: 300, left: 20, right: 20),
                child: SizedBox(
                  height: 48,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => toonItemMenu(context, menu),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        );

    void wijd(WidgetTester tester) {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    // Vóór de muisklik: de laatste muisklik blijft twee seconden "vers".
    testWidgets('een tik zonder muis: rechts aan de rij, zoals het was', (tester) async {
      volgMuisVoorMenus();
      wijd(tester);
      await tester.pumpWidget(breed(_menu()));
      await tester.tapAt(const Offset(100, 324));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Favoriet')).dx, greaterThan(1000));
    });

    testWidgets('DE KERN: een muisklik links op een brede rij opent het menu daar, niet aan het eind', (tester) async {
      volgMuisVoorMenus();
      wijd(tester);
      await tester.pumpWidget(breed(_menu()));
      await tester.tapAt(const Offset(100, 324), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.text('Favoriet'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Favoriet')).dx, lessThan(400),
          reason: 'het menu hoort naast de muis (x 100), niet aan de rechterrand van het venster');
    });

    testWidgets('DE VAL: een menu zonder regels gaat niet open (was een lege witte balk)', (tester) async {
      wijd(tester);
      await tester.pumpWidget(breed(const ItemMenu(titel: 'Studio', blokken: [[], []])));
      await tester.tapAt(const Offset(100, 324), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuDivider), findsNothing);
      expect(find.byWidgetPredicate((w) => w.runtimeType.toString().startsWith('_PopupMenu')), findsNothing,
          reason: 'geen leeg zwevend menu');
    });

    test('aangesloten: bij de start, en Versies geeft grijze regels in plaats van een leeg menu', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      final start = main.indexOf('Future<void> main() async {');
      expect(main.substring(start, start + 300), contains('volgMuisVoorMenus();'));
      final versie = main.indexOf('ItemMenu _plaatversieMenu(');
      final lijf = main.substring(versie, main.indexOf('\n}\n', versie));
      expect(lijf, contains("'Is al de standaard voor deze plaat', () {}, uit: true"));
      expect(lijf, contains("'Niet weg te gooien: staat in de albummap', () {}, uit: true"));
    });
  });
}

void _niets() {}

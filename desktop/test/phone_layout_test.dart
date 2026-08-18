/// The phone's section bar, at the sizes it actually has to survive.
///
/// [PhoneNavBar] reads no store — the active section and the download count are handed in — which
/// is the whole reason it can be rendered here at all. Building the real shell would need fourteen
/// providers and a libmpv that does not exist in the test harness, so this is the one piece of the
/// phone frame a test can hold.
///
/// The last test is the important one. The phone frame is chosen by width, and the only way it
/// could ever reach a television is if that width were wrong.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/main.dart';
import 'package:debridmusic/tv.dart';

/// The narrowest Android still in the wild. Everything the bar has to fit, fits here or nowhere.
const _smallPhone = Size(320, 640);

Widget _bar({
  int active = 5,
  int badge = 0,
  ValueChanged<int>? onSelect,
  VoidCallback? onMore,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const Spacer(),
            PhoneNavBar(
              active: active,
              badge: badge,
              onSelect: onSelect ?? (_) {},
              onMore: onMore ?? () {},
            ),
          ],
        ),
      ),
    );

void _sized(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('de balk past op de smalste telefoon', (tester) async {
    _sized(tester, _smallPhone);
    await tester.pumpWidget(_bar());

    // An overflow is reported as an exception rather than thrown, so it has to be asked for.
    expect(tester.takeException(), isNull);

    for (final label in ['Start', 'Albums', 'Artiesten', 'Downloads', 'Meer']) {
      expect(find.text(label), findsOneWidget, reason: '“$label” staat niet op de balk');
    }
  });

  testWidgets('lopende downloads staan op de balk', (tester) async {
    _sized(tester, _smallPhone);
    await tester.pumpWidget(_bar(badge: 3));

    expect(find.text('3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('geen downloads, geen telletje', (tester) async {
    _sized(tester, _smallPhone);
    await tester.pumpWidget(_bar());

    expect(find.text('0'), findsNothing);
  });

  testWidgets('tikken kiest de sectie waarop je tikt', (tester) async {
    _sized(tester, _smallPhone);
    int? chosen;
    await tester.pumpWidget(_bar(onSelect: (id) => chosen = id));

    await tester.tap(find.text('Albums'));
    // 0 is Albums in NavSections.items — nav_sections_test bewaakt dat die id blijft bestaan.
    expect(chosen, 0);
  });

  testWidgets('“Meer” opent het vel en kiest zelf niets', (tester) async {
    _sized(tester, _smallPhone);
    var opened = false;
    int? chosen;
    await tester.pumpWidget(_bar(onSelect: (id) => chosen = id, onMore: () => opened = true));

    await tester.tap(find.text('Meer'));
    expect(opened, isTrue);
    expect(chosen, isNull);
  });

  testWidgets('een sectie uit het vel licht “Meer” op', (tester) async {
    _sized(tester, _smallPhone);
    // 3 is Ontdek: in items, niet op de balk. Zonder deze regel licht er niets op en lijkt de
    // balk kapot zodra je in zo'n sectie zit.
    await tester.pumpWidget(_bar(active: 3));

    expect(tester.takeException(), isNull);
    expect(find.text('Meer'), findsOneWidget);
  });

  testWidgets('een telefoon is smal, een televisie niet', (tester) async {
    Future<bool> ask(Size size) async {
      _sized(tester, size);
      var answer = false;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          answer = isCompact(context);
          return const SizedBox.shrink();
        }),
      ));
      return answer;
    }

    expect(await ask(const Size(412, 915)), isTrue,
        reason: 'een telefoon in portret hoort de telefoonlayout te krijgen');

    // The guard the whole phone layer rests on. A Shield is 960×540; the frame is chosen by width
    // and by nothing else, so this is the assertion that keeps the bottom bar off a television.
    expect(await ask(const Size(960, 540)), isFalse,
        reason: 'de telefoonbalk mag nooit op de Shield verschijnen');

    // An iPad in portrait is 834 and has never had this frame either.
    expect(await ask(const Size(834, 1112)), isFalse);
  });
}

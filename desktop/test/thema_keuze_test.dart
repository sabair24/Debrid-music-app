// Licht, donker of volgens het systeem (Saber, 18-10-2026). Zie lib/ui/thema.dart.
import 'dart:io';
import 'dart:ui' show Brightness;

import 'package:debridmusic/main.dart' show ThemaKeuzeRegel;
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/ui/kleuren.dart';
import 'package:debridmusic/ui/thema.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory map;
  var herbouwd = 0;

  setUp(() {
    map = Directory.systemTemp.createTempSync('dm_thema_');
    setAppDirForTest(map.path);
    ThemaStand.keuze.value = ThemaKeuze.systeem;
    ThemaStand.systeemVoorToets = Brightness.dark;
    herbouwd = 0;
    ThemaStand.herbouwVoorToets = () => herbouwd++;
    Thema.licht = false;
  });

  tearDown(() {
    ThemaStand.systeemVoorToets = null;
    ThemaStand.herbouwVoorToets = null;
    ThemaStand.meld = null;
    ThemaStand.keuze.value = ThemaKeuze.systeem;
    Thema.licht = false;
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('de keuze en het systeem samen', () {
    expect(themaIsLicht(ThemaKeuze.licht, Brightness.dark), isTrue);
    expect(themaIsLicht(ThemaKeuze.donker, Brightness.light), isFalse);
    expect(themaIsLicht(ThemaKeuze.systeem, Brightness.light), isTrue);
    expect(themaIsLicht(ThemaKeuze.systeem, Brightness.dark), isFalse);
  });

  test('zonder bestand: volgens het systeem, en meteen de goede kleuren', () {
    ThemaStand.systeemVoorToets = Brightness.light;
    ThemaStand.laad();
    expect(ThemaStand.keuze.value, ThemaKeuze.systeem);
    expect(Thema.licht, isTrue);
    expect(kAchtergrond, const Color(0xFFF3EFE7), reason: 'warm gebroken wit');
  });

  test('een keuze wordt bewaard en overleeft een herstart', () async {
    await ThemaStand.zet(ThemaKeuze.licht);
    expect(Thema.licht, isTrue);
    expect(herbouwd, 1, reason: 'van donker naar licht: alles opnieuw');
    expect(File('${map.path}${Platform.pathSeparator}thema.json').readAsStringSync(), contains('licht'));

    // "Herstart": geheugen leeg, systeem donker. Het bestand wint.
    ThemaStand.keuze.value = ThemaKeuze.systeem;
    Thema.licht = false;
    ThemaStand.laad();
    expect(ThemaStand.keuze.value, ThemaKeuze.licht);
    expect(Thema.licht, isTrue);
  });

  test('alleen opnieuw bouwen als licht of donker echt verandert', () async {
    final regels = <String>[];
    ThemaStand.meld = regels.add;
    await ThemaStand.zet(ThemaKeuze.donker); // systeem was al donker
    expect(herbouwd, 0);
    await ThemaStand.zet(ThemaKeuze.systeem);
    expect(herbouwd, 0);
    ThemaStand.systeemVoorToets = Brightness.light;
    ThemaStand.pasToe();
    expect(herbouwd, 1, reason: 'het systeem ging naar licht en de keuze volgt het systeem');
    expect(regels, ['thema: licht (systeem)']);
  });

  test('een onleesbaar bestand valt terug op het systeem', () {
    File('${map.path}${Platform.pathSeparator}thema.json').writeAsStringSync('{kapot');
    ThemaStand.laad();
    expect(ThemaStand.keuze.value, ThemaKeuze.systeem);
  });

  testWidgets('de echte herbouw: elke kleur wisselt en de staat blijft', (t) async {
    ThemaStand.herbouwVoorToets = null;
    await t.pumpWidget(const MaterialApp(home: _Teller()));
    await t.tap(find.byKey(const ValueKey('tel')));
    await t.pump();
    expect(find.text('1'), findsOneWidget);
    expect(t.widget<ColoredBox>(find.byKey(const ValueKey('vlak'))).color, const Color(0xFF07080C));

    await t.runAsync(() => ThemaStand.zet(ThemaKeuze.licht));
    await t.pump();
    await t.pump();
    expect(t.widget<ColoredBox>(find.byKey(const ValueKey('vlak'))).color, const Color(0xFFF3EFE7),
        reason: 'het vlak las zijn kleur bij het bouwen; na de wissel moet het opnieuw gebouwd zijn');
    expect(find.text('1'), findsOneWidget, reason: 'een wissel gooit niets weg: de teller staat er nog');
  });

  testWidgets('in Instellingen: drie keuzes, en tikken zet hem om', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: ThemaKeuzeRegel())));
    for (final k in ThemaKeuze.values) {
      expect(find.byKey(ValueKey('thema-${k.name}')), findsOneWidget);
    }
    expect(find.text('Volgens systeem'), findsOneWidget);
    expect(t.widget<ChoiceChip>(find.byKey(const ValueKey('thema-systeem'))).selected, isTrue,
        reason: 'standaard volgens het systeem');
    await t.tap(find.byKey(const ValueKey('thema-licht')));
    await t.pump();
    expect(ThemaStand.keuze.value, ThemaKeuze.licht);
    expect(Thema.licht, isTrue);
    expect(t.widget<ChoiceChip>(find.byKey(const ValueKey('thema-licht'))).selected, isTrue);
  });

  test('aangesloten: vóór runApp geladen, en de keuze staat in Instellingen', () {
    final bron = File('lib/main.dart').readAsStringSync();
    final laad = bron.indexOf('ThemaStand.laad();');
    expect(laad, greaterThan(0));
    expect(laad, lessThan(bron.indexOf('  runApp(')), reason: 'anders flitst een lichte app eerst donker');
    expect(bron, contains('const ThemaKeuzeRegel(),'));
    expect(bron, contains('brightness: Thema.licht ? Brightness.light : Brightness.dark,'));
  });
}

class _Teller extends StatefulWidget {
  const _Teller();

  @override
  State<_Teller> createState() => _TellerState();
}

class _TellerState extends State<_Teller> {
  var _n = 0;

  @override
  Widget build(BuildContext context) => Column(children: [
        SizedBox(width: 50, height: 50, child: ColoredBox(key: const ValueKey('vlak'), color: kAchtergrond)),
        GestureDetector(key: const ValueKey('tel'), onTap: () => setState(() => _n++), child: Text('$_n')),
      ]);
}

/// Wat op dit toestel staat (Saber, 28-10-2026): een merkje in de lijsten, een filter, eerst vragen vóór het
/// weghalen, en de la niet meer met vegen.
///
/// "Ik probeerde dit op te slaan op men gsm maar zie niets staan" — het stond er wel, alleen nergens te zien.
/// "als ik de knop offline dus uitschakel (weer online) dan wordt het nummer van men gsm gewist e ??" — ja, met
/// één tik en zonder te vragen.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:debridmusic/lan/vaste_naam.dart' show normaliseerPcPad;
import 'package:debridmusic/offline.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/ui/op_toestel.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  late Directory map;
  setUp(() {
    map = Directory.systemTemp.createTempSync('dm_toestel_');
    setAppDirForTest(map.path);
  });
  tearDown(() {
    try {
      map.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows houdt soms nog even een greep vast; een achtergebleven tijdelijke map is geen rode toets waard.
    }
  });

  /// Een toestel met één bewaard nummer.
  Future<OfflineStore> metEenNummer(String pad) async {
    final bestand = File('${map.path}${Platform.pathSeparator}kopie.flac')..writeAsBytesSync([1, 2, 3]);
    File('${map.path}${Platform.pathSeparator}offline.json').writeAsStringSync(jsonEncode([
      {'path': pad, 'file': bestand.path, 'bytes': 31000000, 'title': 'Crazy', 'artist': 'Britney Spears', 'album': 'Crazy'},
    ]));
    final o = OfflineStore();
    await o.load();
    return o;
  }

  Widget metWinkel(OfflineStore? o, Widget kind) => MaterialApp(
        home: Scaffold(
          body: o == null ? kind : ChangeNotifierProvider<OfflineStore>.value(value: o, child: kind),
        ),
      );

  testWidgets('het merkje staat er alleen als ALLES op dit toestel staat — en zonder winkel gewoon niets', (t) async {
    final pad = normaliseerPcPad('Britney Spears/Crazy/01 - Crazy.flac');
    final o = await t.runAsync(() => metEenNummer(pad));
    await t.pumpWidget(metWinkel(o, OpToestelMerk(paden: [pad])));
    expect(find.byIcon(Icons.offline_pin_rounded), findsOneWidget);
    await t.pumpWidget(metWinkel(o, OpToestelMerk(paden: [pad, normaliseerPcPad('Britney Spears/Crazy/02 - Ander.flac')])));
    expect(find.byIcon(Icons.offline_pin_rounded), findsNothing, reason: 'een half album is geen album op dit toestel');
    await t.pumpWidget(metWinkel(null, OpToestelMerk(paden: [pad])));
    expect(find.byIcon(Icons.offline_pin_rounded), findsNothing);
    expect(t.takeException(), isNull, reason: 'een toets of de pc heeft geen winkel in de boom');
  });

  testWidgets('eerst vragen: Annuleren laat staan, Weghalen haalt weg', (t) async {
    bool? antwoord;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => antwoord = await vraagVanToestelHalen(context, aantal: 12, bytes: 380000000),
          child: const Text('knop'),
        ),
      ),
    ));
    await t.tap(find.text('knop'));
    await t.pumpAndSettle();
    expect(find.text('Van dit toestel halen?'), findsOneWidget);
    expect(find.textContaining('12 nummers · 380 MB'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('toestel-weg-nee')));
    await t.pumpAndSettle();
    expect(antwoord, isFalse);
    await t.tap(find.text('knop'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('toestel-weg-ja')));
    await t.pumpAndSettle();
    expect(antwoord, isTrue);
  });

  test('de omvang in gewone taal', () {
    expect(toestelOmvang(1, 31000000), '1 nummer · 31 MB');
    expect(toestelOmvang(40, 1240000000), '40 nummers · 1,2 GB');
    expect(toestelOmvang(3, 0), '3 nummers');
  });

  test('aangesloten: de knop vraagt eerst, de la opent niet met vegen, het filter en de merkjes', () {
    final main = _bron('lib/main.dart');
    // De knop op de albumpagina: vragen vóór het weghalen.
    final vraag = main.indexOf('final zeker = await vraagVanToestelHalen(context, aantal: tracks.length,');
    final weg = main.indexOf('await offline.remove(t.path);', vraag);
    expect(vraag, greaterThan(0));
    expect(weg, greaterThan(vraag), reason: 'eerst de vraag, dan pas weghalen');
    expect(main, contains('                if (!zeker) return;\n'));
    // De la: alleen met de drie streepjes.
    expect(main, contains('        drawerEnableOpenDragGesture: false,\n'));
    // Het filter in Albums en Tracks.
    expect(main, contains("    if (_alleenToestel && !(context.read<OfflineStore?>()?.has(t.path) ?? false)) return false;\n"));
    expect(main, contains('            ..._toestelFilter(),\n'));
    expect(main, contains('                ..._toestelFilter(),\n'));
    // De merkjes.
    expect(main, contains('              OpToestelMerk(paden: [t.path], nummer: t),\n              Text(_fmt(t.duration), style: kTekstKlein),'));
    expect(main, contains('OpToestelMerk(paden: [for (final t in a.tracks) t.path], rond: true)'));
    expect(main, contains('                      OpToestelMerk(paden: [t.path], nummer: t),\n                      _qualityBadge(_trackQuality(standaardVersieVan(lib, t))),'),
        reason: 'ook in de eigen rij van Tracks');
  });
}

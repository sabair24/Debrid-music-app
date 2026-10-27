// Het dataverbruik in Instellingen › Info (Saber, 27-10-2026: "ik wil bij instellingen, sectie info wat men data verbruik
// is"). Apart van dataverbruik_test.dart: een bestand met testWidgets kan geen echte HttpClient gebruiken.
import 'package:debridmusic/dataverbruik.dart';
import 'package:debridmusic/lan/verzendteller.dart';
import 'package:debridmusic/netsoort.dart';
import 'package:debridmusic/ui/dataverbruik_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Instellingen › Info', () {
    testWidgets('DE KERN: op een smal scherm alles leesbaar, en per dag uit te klappen', (tester) async {
      final s = DataverbruikStore(bestand: null, logboek: null, netNu: () => Netsoort.mobiel);
      s.tel(Verkeerssoort.muziek, 380 << 20);
      s.tel(Verkeerssoort.hoezen, 12 << 20);
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: DataverbruikInfo(store: s, isPc: false)))));
      expect(find.text('Dataverbruik'), findsOneWidget);
      expect(find.text('Vandaag over mobiel: muziek 380 MB · hoezen 12,0 MB'), findsOneWidget);
      await tester.tap(find.text('Per dag'));
      await tester.pump();
      expect(find.textContaining(RegExp(r'^\d\d-\d\d  mobiel 392 MB')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      s.dispose();
    });

    testWidgets('op de pc: wat hij vandaag naar je toestellen stuurde', (tester) async {
      Verzendteller.vandaag.value = {'buiten|muziek': 2 << 30, 'buiten|hoezen': 114 << 20, 'thuis|catalogus': 373 << 10};
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: DataverbruikInfo(store: null, isPc: true))));
      expect(find.textContaining('Buitenshuis (via de versleutelde deur): 2,11 GB — muziek 2,00 GB · hoezen 114 MB'),
          findsOneWidget);
      expect(find.text('Via Tailscale: niets'), findsOneWidget);
      Verzendteller.vandaag.value = const {};
    });
  });
}

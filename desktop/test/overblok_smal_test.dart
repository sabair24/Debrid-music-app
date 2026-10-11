/// Een opengeklapt hoofdstuk van de biografie past op een gsm.
///
/// **Waarom.** Saber op 11-10-2026: *"bij artist detail de biografie is niet leesbaar op gsm"*. Op de
/// gsm gezien bij Lionel Richie, "Persoonlijk": elke regel liep rechts van het scherm af ("Zijn eers"
/// / "eerste vrouw…"). De tekst stond als niet-buigend kind in een `Row` met een maximum van
/// [kLeesmaat] (820), en een Row geeft zo'n kind geen breedtegrens mee — dus werd hij altijd op de
/// leesmaat van een pc gezet, ook op 411 punten.
library;

import 'package:debridmusic/overblok.dart';
import 'package:debridmusic/tv.dart';
import 'package:debridmusic/wikipedia.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

OverBlok _blok() => OverBlok(
      naam: 'Lionel Richie',
      artikel: WikiArtikel(
        taal: 'nl',
        titel: 'Lionel Richie',
        intro: 'Lionel Brockman Richie Jr. is een Amerikaanse muzikant en popzanger.',
        afdelingen: [
          WikiAfdeling(
              niveau: 2,
              kop: 'Persoonlijk',
              tekst: 'Lionel Richie is tweemaal gehuwd geweest. Zijn eerste vrouw adopteerde hij in '
                  '1983 Nicole Richie. ' * 4),
        ],
      ),
      beeldBijSectie: (afd, i) => const SizedBox(width: 300, height: 300, child: Text('sectiebeeld')),
    );

Future<void> _openOp(WidgetTester t, double breed) async {
  final maat = Size(breed, 3000);
  await t.binding.setSurfaceSize(maat);
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(size: maat),
        child: CustomScrollView(slivers: [SliverToBoxAdapter(child: _blok())]),
      ),
    ),
  ));
  await t.pumpAndSettle();
  await t.tap(find.text('Meer lezen'));
  await t.pumpAndSettle();
  await t.tap(find.text('PERSOONLIJK'));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => setTvModeForTest(false));
  tearDown(() => setTvModeForTest(false));

  for (final breed in [360.0, 411.0]) {
    testWidgets('DE KERN: op $breed punten blijft de tekst binnen het scherm, het beeld eronder',
        (t) async {
      await _openOp(t, breed);
      expect(t.takeException(), isNull, reason: 'geen overloop');
      final tekst = t.getRect(find.textContaining('tweemaal gehuwd'));
      expect(tekst.right, lessThanOrEqualTo(breed),
          reason: 'de tekst liep rechts van het scherm af: $tekst op $breed');
      final beeld = t.getRect(find.text('sectiebeeld'));
      expect(beeld.top, greaterThanOrEqualTo(tekst.bottom), reason: 'het beeld hoort eronder');
    });
  }

  testWidgets('DE GRENS: op een breed venster staat het beeld ernaast', (t) async {
    await _openOp(t, 1400);
    final tekst = t.getRect(find.textContaining('tweemaal gehuwd'));
    final beeld = t.getRect(find.text('sectiebeeld'));
    expect(beeld.left, greaterThan(tekst.right), reason: 'tekst $tekst, beeld $beeld');
    expect(tekst.width, lessThanOrEqualTo(kLeesmaat), reason: 'nooit breder dan de leesmaat');
  });
}

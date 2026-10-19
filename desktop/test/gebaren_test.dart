// Gebaren en kleine extra's die Saber op 16-10-2026 koos: vegen over de minispeler, trekken om te
// verversen, de hoes die meevliegt (ook naar Nu speelt), lang indrukken voor een menu, de kleur van de
// hoes sterker in de balken, en knoppen waarvan je ziet dat je ze intikt.
import 'dart:io';

import 'package:debridmusic/main.dart' show VeegUitkomst, veegUitkomst, kVeegDrempel;
import 'package:debridmusic/ui/kleuren.dart';
import 'package:debridmusic/ui/vlak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('vegen over de minispeler', () {
    test('ver genoeg of snel genoeg naar links: volgende; naar rechts: vorige', () {
      expect(veegUitkomst(-(kVeegDrempel + 1), 0, heeftVolgende: true, heeftVorige: true), VeegUitkomst.volgende);
      expect(veegUitkomst(kVeegDrempel + 1, 0, heeftVolgende: true, heeftVorige: true), VeegUitkomst.vorige);
      expect(veegUitkomst(-20, -900, heeftVolgende: true, heeftVorige: true), VeegUitkomst.volgende,
          reason: 'een snelle korte veeg telt ook');
      expect(veegUitkomst(-20, -100, heeftVolgende: true, heeftVorige: true), VeegUitkomst.terug);
    });

    test('zonder nummer in die richting veert hij terug', () {
      expect(veegUitkomst(-200, -2000, heeftVolgende: false, heeftVorige: true), VeegUitkomst.terug);
      expect(veegUitkomst(200, 2000, heeftVolgende: true, heeftVorige: false), VeegUitkomst.terug);
    });
  });

  group('glasknop', () {
    testWidgets('ingedrukt veert hij in en licht hij op, ook bij een vlugge tik', (t) async {
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: Center(child: GlasKnop(icoon: Icons.shuffle_rounded, label: 'Shuffle alles', onPressed: () {})))));
      double schaal() => t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
      double licht() => t.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;
      expect(schaal(), 1);
      expect(licht(), 0);
      final g = await t.startGesture(t.getCenter(find.text('Shuffle alles')));
      await t.pump(const Duration(milliseconds: 20));
      expect(schaal(), kKnopVeer);
      expect(licht(), 1);
      await g.up();
      await t.pump(const Duration(milliseconds: 30));
      expect(schaal(), kKnopVeer, reason: 'een vlugge tik blijft $kKnopIngedrukt zichtbaar');
      await t.pump(kKnopIngedrukt);
      await t.pumpAndSettle();
      expect(schaal(), 1);
      expect(licht(), 0);
    });

    testWidgets('ook als er tussen neer en los echt tijd verstrijkt (een trage machine)', (t) async {
      // De bouwstraat ving het op 16-10-2026: met een wandklok schoot de knop terug zodra er tussen
      // neerdrukken en loslaten echt meer dan 110 ms zat, ook al liet de toets maar 30 ms verstrijken.
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: Center(child: GlasKnop(icoon: Icons.shuffle_rounded, label: 'Shuffle alles', onPressed: () {})))));
      double schaal() => t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
      final g = await t.startGesture(t.getCenter(find.text('Shuffle alles')));
      await t.pump(const Duration(milliseconds: 20));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 160)));
      await g.up();
      await t.pump(const Duration(milliseconds: 30));
      expect(schaal(), kKnopVeer, reason: 'de nagebootste tijd telt, niet de echte');
      await t.pump(kKnopIngedrukt);
      await t.pumpAndSettle();
      expect(schaal(), 1);
    });

    testWidgets('een uitgeschakelde knop veert niet', (t) async {
      await t.pumpWidget(const MaterialApp(
          home: Scaffold(body: Center(child: GlasKnop(icoon: Icons.shuffle_rounded, label: 'Shuffle alles', onPressed: null)))));
      final g = await t.startGesture(t.getCenter(find.text('Shuffle alles')));
      await t.pump(const Duration(milliseconds: 20));
      expect(t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
      await g.up();
    });
  });

  test('de balken kleuren duidelijk mee met de hoes (38 %, Saber 18-10-2026: "sterker")', () {
    expect(kBalkZweem, .38);
    expect(balkKleur(null), kVerzonken);
    final rood = balkKleur(0xFFCC2222);
    expect(rood, isNot(kVerzonken));
    expect((rood.r - kVerzonken.r).abs(), greaterThan(.08), reason: 'merkbaar, niet een tiende');
  });

  test('aangesloten', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    // Vegen, en de hoes die van de minispeler naar Nu speelt vliegt.
    expect(main, contains('child: _VeegMinispeler(\n                  volgende: x.next,\n                  vorige: x.previous,'));
    expect(main, contains('Hero(tag: kNuSpeeltHoes, child: cover(p.currentCover, size: 40, radius: 6)),'));
    expect(main, contains('heroTag: kNuSpeeltHoes,'));
    // Trekken om te verversen op Start; het knopje alleen nog met een muis.
    expect(main, contains('return RefreshIndicator(\n      onRefresh: _ververs,'));
    expect(main, contains("if (!isTv && !_isTouch)\n                TvLabelled(\n                  label: 'Ververs',"));
    // Eén vlieglabel per rij, en de albumpagina's nemen het over.
    expect(main, contains("final tag = 'hoes:\${context.read<LibraryStore>().uidOf(albums[i])}@\$rij';"));
    expect(main, contains('heroTag: widget.heroTag ?? \'hoes:'));
    expect(main, contains("_localRow(recent.take(15).toList(), rij: 'recent')"));
    expect(main, contains("_catalogRow(_charts.take(20).toList(), rij: 'top')"));
    // De nieuwe releases sinds 19-10-2026 als uitgelichte rijen met brede kaarten (ui/nieuw_kaarten.dart).
    expect(main, contains('groot: () => nieuwNummerKaart(context, nummers.first, nu, groot: true),'));
    // Lang indrukken: een menu op elke tegel van Start.
    expect(main, contains('onLongPress: () => _toonItemMenu(context, _albumMenu(context, albums[i])));'));
    expect(main, contains('_netAlbumMenu(context, hits[i].artist, hits[i].album)'));
    // De onderbalk in de tint van de speler.
    expect(main, contains('builder: (_, was, __) => Onderbalk(view: _view, onPick: _gaNaar, wasKleur: was),'));
    // Shuffle en Speel alles zijn glas en zeggen wat ze deden.
    expect(main, contains("_srcToast(context, 'Shuffle · \${tracks.length}"));
  });
}

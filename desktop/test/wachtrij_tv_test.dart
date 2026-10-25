// De wachtrij op de Shield (Saber, 25-10-2026): "de wachtrij op de shield ik kan die niet bedienen en is niet te zien in
// de now playing screen dit moet." Gekozen: een knop en een paneel van rechts; OK speelt dat nummer, lang OK geeft een
// menu, en "Eerder gespeeld" staat erin.
import 'dart:io';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('de keuzes in het menu', () {
    List<WachtrijKeuze> k(int plek, {int huidig = 3, int lengte = 8, bool radio = false}) =>
        wachtrijKeuzes(plek: plek, huidig: huidig, lengte: lengte, radio: radio);

    test('het eerste van "Hierna": niet omhoog (dan zou het bij "Eerder gespeeld" staan), wel omlaag', () {
      expect(k(4), [WachtrijKeuze.nuSpelen, WachtrijKeuze.omlaag, WachtrijKeuze.eruit]);
    });

    test('midden in "Hierna": omhoog en omlaag', () {
      expect(k(5), [WachtrijKeuze.nuSpelen, WachtrijKeuze.omhoog, WachtrijKeuze.omlaag, WachtrijKeuze.eruit]);
    });

    test('het laatste: niet omlaag', () {
      expect(k(7), [WachtrijKeuze.nuSpelen, WachtrijKeuze.omhoog, WachtrijKeuze.eruit]);
    });

    test('eerder gespeeld: opnieuw spelen of eruit, niet verschuiven', () {
      expect(k(0), [WachtrijKeuze.nuSpelen, WachtrijKeuze.eruit]);
      expect(k(2), [WachtrijKeuze.nuSpelen, WachtrijKeuze.eruit]);
    });

    test('het spelende nummer en een plek die er niet is: niets', () {
      expect(k(3), isEmpty);
      expect(k(-1), isEmpty);
      expect(k(8), isEmpty);
    });

    test('een radio: alleen nu spelen', () {
      expect(k(5, radio: true), [WachtrijKeuze.nuSpelen]);
      expect(k(3, radio: true), isEmpty);
    });

    test('elke keuze klopt met wat de wachtrij er zelf van maakt', () {
      final rij = [for (var i = 0; i < 8; i++) Track(path: 'p$i', title: 't$i', artist: 'a', album: 'b')];
      final w = (origineel: rij, volgorde: rij, index: 3);
      for (var plek = 0; plek < 8; plek++) {
        for (final keuze in k(plek)) {
          final na = plekNaKeuze(keuze, plek: plek, lengte: 8)!;
          switch (keuze) {
            case WachtrijKeuze.omhoog || WachtrijKeuze.omlaag:
              final uit = verplaatsInWachtrijLijst(w, plek, na, shuffle: false);
              expect(uit.volgorde[na].path, 'p$plek', reason: 'de selectie gaat mee met het nummer');
              expect(uit.index, 3, reason: 'binnen "Hierna" blijft wat speelt op zijn plek');
            case WachtrijKeuze.eruit:
              final uit = haalUitWachtrijLijst(w, plek);
              expect(uit.volgorde.length, 7);
              expect(na, plek < 7 ? plek : 6, reason: 'de regel die op die plek kwam, of de laatste');
            case WachtrijKeuze.nuSpelen:
              expect(na, plek);
          }
        }
      }
    });

    test('eruit uit een rij van één: geen plek meer', () {
      expect(plekNaKeuze(WachtrijKeuze.eruit, plek: 0, lengte: 1), isNull);
    });
  });

  group('aangesloten', () {
    final main = _bron('lib/main.dart');

    test('de knop in Nu speelt staat er ook op een tv, en opent daar het paneel van rechts', () {
      expect(main, isNot(contains('] else if (!isTv) ...[\n            // Op een telefoon past het paneel er niet naast')),
          reason: 'de knop was op een tv verborgen');
      expect(main, contains('          ] else ...[\n            // Op een telefoon past het paneel er niet naast'));
      final knop = main.substring(main.indexOf('class _WachtrijKnop extends StatelessWidget {'));
      expect(knop.substring(0, 2500), contains('          if (isTv) {\n            unawaited(toonWachtrijPaneelTv(context));'));
      // Het paneel naast de pagina's was met de pijltjes niet te bereiken: nooit meer op een tv.
      expect(main, contains('if (!isTv && !isCompact(context) && context.watch<WachtrijPaneel>().open)'));
    });

    test('het paneel: van rechts, de tv-weergave, Terug of het kruisje sluit', () {
      final p = main.substring(main.indexOf('Future<void> toonWachtrijPaneelTv(BuildContext context)'));
      final stuk = p.substring(0, 2200);
      expect(stuk, contains('showGeneralDialog<void>('));
      expect(stuk, contains('alignment: Alignment.centerRight,'));
      expect(stuk, contains('tvPaneel: true, opGlas: true, onSluit: () => Navigator.of(paneelContext).maybePop()),'));
      expect(stuk, contains('begin: const Offset(1, 0)'));
    });

    test('de regels: OK speelt, lang OK het menu, geen greep en geen kruisje', () {
      final rij = main.substring(main.indexOf('class _WachtrijRij extends StatelessWidget {'));
      final stuk = rij.substring(0, rij.indexOf('\n// ── Now playing'));
      expect(stuk, contains('    if (tv) {\n      return Pressable(\n        focusNode: focusNode,\n'
          '        onPressed: () => p.springNaar(plek),\n        onLongPress: tvMenu,'));
      expect(stuk, contains(': tv\n                            ? null\n                            : TvLabelled(\n'
          "                        label: 'Uit de wachtrij halen',"));
      expect(main, contains('        sleepIndex: tv ? null : sleep,'));
      // Op een tv een gewone lijst, geen SliverReorderableList: verplaatsen gaat via het menu.
      expect(main, contains('            if (radio || tv)\n              SliverList('));
    });

    test('het menu: de keuzes bovenaan, daaronder wat je met een nummer kunt', () {
      expect(main, contains("WachtrijKeuze.nuSpelen => MenuRegel(Icons.play_arrow_rounded, 'Nu spelen', () => doe(k)),"));
      expect(main, contains("WachtrijKeuze.omhoog => MenuRegel(Icons.arrow_upward_rounded, 'Eén plek omhoog', () => doe(k)),"));
      expect(main,
          contains("WachtrijKeuze.omlaag => MenuRegel(Icons.arrow_downward_rounded, 'Eén plek omlaag', () => doe(k)),"));
      expect(main,
          contains("WachtrijKeuze.eruit => MenuRegel(Icons.playlist_remove_rounded, 'Uit de wachtrij', () => doe(k)),"));
      expect(main, contains('blokken: [wachtrij, ...rest]'));
      // Bij het kiezen opnieuw opgezocht en opnieuw gekeurd: de rij kan intussen verschoven zijn.
      expect(main, contains(
          '      if (i < 0 || !wachtrijKeuzes(plek: i, huidig: p.currentIndex, lengte: lengte, radio: radio).contains(k)) return;'));
      expect(main, contains('      _focusNaar = plekNaKeuze(k, plek: i, lengte: lengte);'));
    });

    test('de selectie: begint op Nu speelt, gaat mee met een nummer, en valt nooit weg', () {
      expect(main, contains("                      key: const ValueKey('wachtrij-nu-tv'),\n"
          '                      focusNode: _nuKnoop,\n                      autofocus: true,'));
      expect(main, contains('    if (tv) _houdSelectie(sleutels, nu);'));
      expect(main, contains('      if (doel == null && i < 0) doel = _focusOpPlek;'));
      expect(main, contains('      if (doel == null && i == nu) doel = nu;'));
      // Een nummer dat een plek opschuift, behoudt zijn regel (en zijn selectie): op sleutel, in beide lijsten.
      expect(main, contains('tv ? (k) => _plekVanSleutel(k, sleutels, (i) => huidig - 1 - i, huidig) : null,'));
      expect(main, contains('tv ? (k) => _plekVanSleutel(k, sleutels, (i) => i - huidig - 1, hierna) : null,'));
      // Snel omlaag: wachten op de regel die nog niet gebouwd is.
      expect(main, contains('    if (tvPijlStap(hier, richting) || tvSchuifVerder(hier, richting)) return KeyEventResult.handled;'));
    });
  });
}

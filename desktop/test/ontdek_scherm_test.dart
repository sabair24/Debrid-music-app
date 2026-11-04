/// Ontdek op het scherm (Saber, 04-11-2026): ▶ en ⬇ zoals elders, wat je ophaalt verdwijnt, opzij vegen = niet voor
/// mij, tegels met ▶ en ⬇ op pc, Mac en iPad — en *"alles moet mooi passen kwa text overal, albumhoezen"*.
library;

import 'dart:io';

import 'package:debridmusic/lan/server.dart' show weigerVanBuiten;
import 'package:debridmusic/main.dart' show OntdekRegel, ontdekKopregel, ontdekZichtbaar;
import 'package:debridmusic/ontdek.dart';
import 'package:debridmusic/recommend.dart' show RecTrack;
import 'package:debridmusic/ui/tegel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

OntdekNummer _n(String artiest, String titel, {String waarom = ''}) =>
    OntdekNummer(RecTrack(artiest, titel, null, seconds: 200), bron: Ontdekbron.deezer, waarom: waarom);

void main() {
  group('wat er op het scherm staat', () {
    test('zonder wat je nu hebt en wat je hier wegtikte, hoogstens 50 — de reserve schuift in', () {
      final lijst = [for (var i = 0; i < 60; i++) _n('A$i', 'T$i')];
      final uit = ontdekZichtbaar(lijst, bezit: {ontdekSleutel('A0', 'T0')}, weg: {ontdekSleutel('A1', 'T1')});
      expect(uit, hasLength(kOntdekGetoond));
      expect(uit.first.nummer.artist, 'A2');
      expect(uit.last.nummer.artist, 'A51', reason: 'de twee die weggingen, worden aangevuld uit de reserve');
    });

    test('de regel onder de kop', () {
      final nu = DateTime(2026, 11, 4, 18);
      expect(
        ontdekKopregel(berekendMs: DateTime(2026, 11, 4, 7).millisecondsSinceEpoch, aantal: 50, nu: nu),
        'Vandaag · 50 nummers',
      );
      expect(
        ontdekKopregel(berekendMs: DateTime(2026, 11, 3, 23).millisecondsSinceEpoch, aantal: 1, nu: nu),
        'Van gisteren · 1 nummer',
      );
      expect(
        ontdekKopregel(berekendMs: DateTime(2026, 10, 30).millisecondsSinceEpoch, aantal: 4, nu: nu),
        'Van 30-10 · 4 nummers',
      );
      expect(ontdekKopregel(berekendMs: 0, aantal: 0, nu: nu, bezig: true), 'Een nieuwe lijst wordt samengesteld…');
      expect(ontdekKopregel(berekendMs: 0, aantal: 0, nu: nu), '');
    });
  });

  group('past op een gsm', () {
    for (final breedte in [360.0, 412.0]) {
      for (final schaal in [1.0, 1.35]) {
        testWidgets('$breedte punten, tekst ×$schaal: lange titel op twee regels, niets loopt over', (t) async {
          t.view.physicalSize = Size(breedte * 3, 900 * 3);
          t.view.devicePixelRatio = 3;
          addTearDown(t.view.reset);
          await t.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(size: Size(breedte, 900), textScaler: TextScaler.linear(schaal)),
                child: Scaffold(
                  body: ListView(
                    children: [
                      for (final n in [
                        _n(
                          "Sinéad O'Connor",
                          "Don't Cry for Me Argentina (Live at the Royal Albert Hall)",
                          waarom: 'Voor wie Céline Dion en Whitney Houston draait',
                        ),
                        _n('Art of Noise feat. Duane Eddy', 'Peter Gunn', waarom: 'Lijkt op Visage en Ultravox'),
                        _n('R.E.M.', 'Drive'),
                      ])
                        OntdekRegel(
                          nummer: n,
                          // Zoals in de app: ▶, radio en ⬇, elk 40 punten (compact).
                          knoppen: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [for (var i = 0; i < 3; i++) const SizedBox(width: 40, height: 40)],
                          ),
                          onTap: () {},
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
          expect(t.takeException(), isNull, reason: 'een overloop is een fout in de toets');
          final titel = t.renderObject<RenderParagraph>(find.byKey(const ValueKey('ontdek-titel')).first);
          final regel = titel.text.style!.fontSize! * schaal * 1.2;
          expect(titel.size.height, lessThanOrEqualTo(regel * 2 + 1), reason: 'hoogstens twee regels');
          expect(titel.size.height, greaterThan(regel * 1.5), reason: 'een lange titel krijgt zijn tweede regel');
          expect(titel.size.width, greaterThan(120), reason: 'de titel houdt ruimte naast de knoppen');
          expect(find.byKey(const ValueKey('ontdek-waarom')), findsNWidgets(2));
        });
      }
    }
  });

  group('de tegel op pc, Mac en iPad', () {
    Future<void> tegel(WidgetTester t, {bool altijd = false, bool knopAltijd = false}) => t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AlbumTegel(
              breedte: 200,
              hoes: (m) => SizedBox(width: m, height: m),
              titel: 'Mandinka',
              onTap: () {},
              onAfspelen: () {},
              knop: const Icon(Icons.download_rounded),
              knoppenAltijd: altijd,
              knopAltijd: knopAltijd,
            ),
          ),
        ),
      ),
    );

    double zicht(WidgetTester t, String sleutel) {
      final o = t.widget<AnimatedOpacity>(
        find.ancestor(of: find.byKey(ValueKey(sleutel)), matching: find.byType(AnimatedOpacity)).first,
      );
      return o.opacity;
    }

    testWidgets('op een aanraakscherm staan ▶ en ⬇ er altijd: daar wijst niemand iets aan', (t) async {
      await tegel(t, altijd: true);
      expect(zicht(t, 'tegel-afspelen'), 1);
      expect(zicht(t, 'tegel-knop'), 1);
    });

    testWidgets('met een muis pas bij het aanwijzen — behalve ⬇ zolang hij haalt', (t) async {
      await tegel(t);
      expect(find.byKey(const ValueKey('tegel-knop')), findsNothing, reason: 'nog niet gebouwd');
      await tegel(t, knopAltijd: true);
      expect(zicht(t, 'tegel-knop'), 1);
    });
  });

  group('aangesloten', () {
    final main = _bron('lib/main.dart');
    final view = main.substring(
      main.indexOf('class _OntdekViewState extends State<OntdekView> {'),
      main.indexOf('Future<void> _playTorrent('),
    );

    test('de pc rekent Ontdek met de drie bronnen; een toestel vraagt het de pc', () {
      expect(
        main,
        contains('    OntdekVoorJou.pc = ontdek;\n    unawaited(ontdek.laad().then((_) => ontdek.start()));\n'),
      );
      expect(main, contains('deezer: deezerOntdekBron(rec, eigen:'));
      expect(main, contains("lastfm: lastfmOntdekBron(_lastfmBron, () => settings.lastfmKey, rec),"));
      expect(main, contains('claude: claudeOntdekBron(AiService('));
      expect(
        main,
        contains(
          '      heb: (a, t) => inBezit(\n          ontdekBezit ??= {\n'
          '            for (final x in library.tracks) ...bezitSleutelsVan(x.artist, x.title),',
        ),
        reason: 'wat je hebt, met elke artiest uit een rij apart, en ook een cover van een lied dat je hebt',
      );
      expect(view, contains('final r = await c.ontdek(ververs: ververs);'));
      expect(
        view,
        contains('if (r.onbekend) {\n          l = await _zelf(lib);'),
        reason: 'een oude pc: zelf, zoals vroeger',
      );
    });

    test('▶ haalt en speelt, ⬇ haalt de beste bron — zoals elders', () {
      expect(view, contains('unawaited(haalTrefferBesteBron(\n'));
      expect(view, contains('sleutel: zoekSleutelVoor(t.artist, t.title)));'));
      expect(view, contains('unawaited(speelGetiktNieuw(context,'));
      expect(view, contains('        SpeelNuKnop(\n'));
      expect(view, contains('_downloadControl(context,\n              jobKey: zoekSleutelVoor(t.artist, t.title)'));
      expect(
        main,
        contains("String _zoekSleutel(CatalogTrackHit t) => zoekSleutelVoor(t.artist, t.title);"),
        reason: 'Online zoeken en Ontdek delen de knop: dezelfde voortgang',
      );
    });

    test('wat je ophaalt verdwijnt: gezeefd tegen de bibliotheek van nu, bij elke verandering', () {
      expect(
        view,
        contains('final lib = context.watch<LibraryStore>();\n    if (!identical(_bezitVan, lib.tracks)) {'),
      );
      expect(view, contains('final zichtbaar = ontdekZichtbaar(_lijst, bezit: _bezit, weg: _wegHier);'));
    });

    test('opzij vegen naar links = niet voor mij, met Ongedaan; ook in het menu, en op de tv via ⋯', () {
      expect(view, contains('direction: DismissDirection.endToStart,\n      onDismissed: (_) => _weg(n),'));
      expect(view, contains("label: 'Ongedaan',"));
      expect(view, contains("MenuRegel(Icons.do_not_disturb_on_outlined, 'Niet voor mij', () => _weg(n))"));
      expect(view, contains("        if (isTv)\n          TvLabelled(\n              label: 'Meer',"));
      expect(view, contains('if (pc != null) return pc.zetWeg('));
      expect(view, contains('remote?.ontdekWeg('));
    });

    test('de tegel: hoes op 1200, ▶ en ⬇ op de hoes, op een aanraakscherm altijd, en de reden telt in de hoogte', () {
      expect(view, contains('final groot = t.cover == null ? null : deezerHoes1200(t.cover!);'));
      expect(view, contains('knoppenAltijd: _isTouch,'));
      expect(view, contains('knopAltijd: haalt,'));
      expect(
        view,
        contains('gridDelegate: tegelRaster(context, c.crossAxisExtent, extra: 2 + tegelRegel(context, kTegelOnder)),'),
      );
    });

    test('van buiten (mobiele data) mag Ontdek ook', () {
      expect(weigerVanBuiten('/api/ontdek', 'GET'), isNull);
      expect(weigerVanBuiten('/api/ontdek/weg', 'POST'), isNull);
      final server = _bron('lib/lan/server.dart');
      expect(
        server,
        contains("{...OntdekLijst(l?.berekendMs ?? 0, d.zichtbaar).toJson(), 'bezig': d.bezig}"),
        reason: 'wat op een ander toestel weggetikt is, ook hier meteen weg',
      );
    });
  });
}

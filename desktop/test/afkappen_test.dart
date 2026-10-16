// Afgekapte teksten op de S26 (Saber, 16-10-2026, zeven schermafdrukken): "I Just Called To S…",
// "Nieuw…" naast een lang grijs bijschrift, "· 2006 · Variété française" vooraan een regel, "had je al
// in minstens even goed…", en een prullenbak twee punten naast afspelen.
import 'dart:io';

import 'package:debridmusic/main.dart' show detailRegels;
import 'package:debridmusic/tv.dart';
import 'package:debridmusic/ui/kop.dart';
import 'package:debridmusic/ui/kopfeiten.dart';
import 'package:debridmusic/ui/tegel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _scherm(Widget kind, {double breed = 384}) => MediaQuery(
      data: MediaQueryData(size: Size(breed, 800)),
      child: MaterialApp(home: Scaffold(body: kind)),
    );

AlbumTegel _tegel(String titel) => AlbumTegel(
      hoes: (m) => SizedBox(width: m, height: m),
      breedte: kTegelHoes,
      titel: titel,
      ondertitel: 'Stevie Wonder',
      onTap: () {},
    );

/// Kapt de tekst [tekst] af? Leest de echte opmaak, niet de string.
bool _afgekapt(WidgetTester t, String tekst) =>
    t.renderObject<RenderParagraph>(find.text(tekst)).didExceedMaxLines;

void main() {
  tearDown(() => setTvModeForTest(false));

  group('tegeltitels', () {
    // Toetsen tekenen met blokjes van 14 punten per teken: tien tekens per regel van 140 punten.
    // "How Deep Is Your" is dus precies twee regels, en werd met één regel afgekapt.
    testWidgets('een lange titel staat op twee regels, helemaal', (t) async {
      await t.pumpWidget(_scherm(Align(alignment: Alignment.topLeft, child: _tegel('How Deep Is Your'))));
      expect(_afgekapt(t, 'How Deep Is Your'), isFalse);
      final regel = t.renderObject<RenderParagraph>(find.text('How Deep Is Your'));
      expect(regel.size.height, greaterThan(30), reason: 'twee regels van 14 pt × 1,35');
    });

    testWidgets('een korte titel houdt dezelfde hoogte, zodat de hoezen op één lijn blijven', (t) async {
      await t.pumpWidget(_scherm(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _tegel('21'),
        _tegel('I Just Called To Say I Love You'),
      ])));
      final kort = t.getSize(find.byType(AlbumTegel).first).height;
      final lang = t.getSize(find.byType(AlbumTegel).last).height;
      expect(kort, lang);
      expect(t.getTopLeft(find.text('Stevie Wonder').first).dy, t.getTopLeft(find.text('Stevie Wonder').last).dy);
    });

    testWidgets('op een tv blijft het één regel', (t) async {
      setTvModeForTest(true);
      expect(kTegelTitelRegels, 1);
      setTvModeForTest(false);
      expect(kTegelTitelRegels, 2);
    });

    testWidgets('in het raster blijft de hoes vierkant, ook met twee regels', (t) async {
      late SliverGridDelegate d;
      await t.pumpWidget(_scherm(Builder(builder: (c) {
        d = tegelRaster(c, 384 - 48, extra: 2);
        return const SizedBox();
      })));
      final g = d as SliverGridDelegateWithFixedCrossAxisCount;
      expect(g.crossAxisCount, 2, reason: 'zoals maxCrossAxisExtent 190 bij 336 punten');
      final cel = (336 - 20) / 2;
      late double tegel;
      await t.pumpWidget(_scherm(Builder(builder: (c) {
        tegel = hoogteVanTegel(c, hoes: cel);
        return const SizedBox();
      })));
      expect(g.mainAxisExtent, closeTo(tegel + 2, .01));
    });
  });

  group('sectiekop', () {
    testWidgets('de titel gaat voor; het bijschrift schuift eronder', (t) async {
      await t.pumpWidget(_scherm(const SectieKop('Nieuw van jouw artiesten', bij: 'de laatste drie maanden en wat eraan komt')));
      expect(_afgekapt(t, 'Nieuw van jouw artiesten'), isFalse);
      final titel = t.getTopLeft(find.text('Nieuw van jouw artiesten'));
      final bij = t.getTopLeft(find.text('de laatste drie maanden en wat eraan komt'));
      expect(bij.dy, greaterThan(titel.dy + 10), reason: 'op 384 punten past het samen niet');
      expect(t.takeException(), isNull);
    });

    testWidgets('past het samen, dan blijft het op één regel', (t) async {
      await t.pumpWidget(_scherm(const SectieKop('Lang niet gedraaid', bij: '12')));
      final titel = t.getRect(find.text('Lang niet gedraaid'));
      final bij = t.getRect(find.text('12'));
      expect(bij.left, greaterThan(titel.right));
      expect((bij.bottom - titel.bottom).abs(), lessThan(6));
    });
  });

  group('kopfeiten', () {
    Widget kop(double breed) => _scherm(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: breed,
            child: const KopFeiten(
              artiest: Text('Emmanuel Moire'),
              artiestTekst: 'Emmanuel Moire',
              feiten: ['2006', 'Variété française', '2 nummers'],
              stijl: TextStyle(fontSize: 14),
            ),
          ),
        ));

    testWidgets('te smal: de feiten op een eigen regel, zonder punt vooraan', (t) async {
      await t.pumpWidget(kop(250));
      final feiten = find.textContaining('2006');
      final tekst = (t.widget<Text>(feiten)).data!;
      expect(tekst.startsWith('·'), isFalse);
      expect(tekst.startsWith(' '), isFalse);
      expect(t.getTopLeft(feiten).dy, greaterThan(t.getTopLeft(find.text('Emmanuel Moire')).dy + 10));
      // Alleen tussen twee feiten mag de regel breken: binnen een feit staat een vaste spatie.
      expect(tekst, contains('Variété française'));
      expect(tekst, contains('2 nummers'));
    });

    testWidgets('breed genoeg: alles op één regel, zoals altijd', (t) async {
      await t.pumpWidget(kop(900));
      expect(find.text(' · 2006 · Variété française · 2 nummers'), findsOneWidget);
    });

    test('de meting', () {
      const s = TextStyle(fontSize: 14);
      expect(kopFeitenOpEenRegel('Live', ['2001', '14 nummers'], s, TextScaler.noScaling, 400), isTrue);
      expect(kopFeitenOpEenRegel('Emmanuel Moire', ['2006', 'Variété française', '2 nummers'], s, TextScaler.noScaling, 200),
          isFalse);
    });
  });

  test('downloadmeldingen: klaar krijgt twee regels, mislukt vier, lopend één', () {
    expect(detailRegels('done'), 2);
    expect(detailRegels('failed'), 4);
    expect(detailRegels('downloading'), 1);
    expect(detailRegels('waiting'), 1);
  });

  test('aangesloten', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    // De prullenbak staat niet meer in de rij van Tracks, wel in het menu.
    final tracks = main.substring(main.indexOf('class TracksView'), main.indexOf('// ── Ontdek (discovery feed)'));
    expect(tracks, isNot(contains("tooltip: 'Nummer verwijderen'")));
    expect(main, contains("MenuRegel(Icons.delete_outline_rounded, 'Verwijderen…',"));
    expect(main, contains('maxLines: detailRegels(job.status),'));
    expect(main, contains('maxLines: detailRegels(j.status),'));
    expect(main, contains("label: isCompact(context) ? 'Bronnen' : 'Bronnen voor album',"));
    expect('KopFeiten('.allMatches(main).length, greaterThanOrEqualTo(2));
    expect(main, isNot(contains("'',\n                        if (album.year != null)")));
    final online = File('lib/online.dart').readAsStringSync();
    expect(online, contains("'had je al, even goed of beter — niet bewaard'"));
  });
}

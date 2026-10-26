/// Nu speelt gestapeld (Saber, 19-10-2026, voorstel goedgekeurd): de artiest één keer, bovenaan met de
/// ronde foto links ervan; onder de titel alleen wie er nog bij komt; kwaliteit en volume in het midden
/// boven de afspeelbalk; alles een stuk hoger.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/luidheid_keuze.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/settings.dart';

Widget _inVak(Widget kind, {double breedte = 420}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>(create: (_) => LibraryStore()),
        ChangeNotifierProvider<AppSettings>(create: (_) => AppSettings()),
      ],
      child: MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: breedte, child: kind)))),
    );

const _stijl = TextStyle(fontSize: 15);

void main() {
  group('de foto naast de kop', () {
    test('drie artiesten op de plaat: drie rondjes, elk met zijn eigen foto', () {
      expect(kopFotoNamen('Elton John, Tim Rice, Hans Zimmer'), ['Elton John', 'Tim Rice', 'Hans Zimmer']);
    });

    test('een groepsnaam met een komma blijft één naam', () {
      for (final groep in ['Earth, Wind & Fire', 'Crosby, Stills & Nash', 'Peter, Paul and Mary', 'Tyler, The Creator']) {
        expect(kopFotoNamen(groep), [groep], reason: groep);
      }
    });

    test('één artiest, een gast eraf, en leeg is leeg', () {
      expect(kopFotoNamen('Justin Timberlake'), ['Justin Timberlake']);
      expect(kopFotoNamen('Justin Timberlake feat. T.I.'), ['Justin Timberlake']);
      expect(kopFotoNamen('  '), isEmpty);
    });
  });

  group('de kop met de foto', () {
    const tekst = TextStyle(fontSize: 22, fontWeight: FontWeight.w800);

    testWidgets('foto en korte naam samen in het midden', (t) async {
      await t.pumpWidget(_inVak(Center(child: kopMetFoto(true, const ['Adele'], const Text('Adele', maxLines: 2, style: tekst)))));
      final rij = t.getRect(find.byKey(const ValueKey('np-kop-met-foto')));
      expect(rij.width, lessThan(200), reason: 'zo breed als foto en naam, niet het hele scherm');
      expect(rij.center.dx, closeTo(t.getRect(find.byType(Scaffold)).center.dx, 1));
      final foto = t.getRect(find.byType(ArtiestRondjes));
      expect(foto.right, lessThanOrEqualTo(t.getRect(find.text('Adele')).left), reason: 'de foto links van de naam');
      expect(foto.width, kKopFoto);
    });

    testWidgets('een lange naam loopt naar twee regels zonder over de rand', (t) async {
      await t.pumpWidget(_inVak(
          kopMetFoto(true, kopFotoNamen('Elton John, Tim Rice, Hans Zimmer'),
              const Text('Elton John, Tim Rice, Hans Zimmer', maxLines: 2, style: tekst)),
          breedte: 300));
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('np-rondje-Elton John')), findsOneWidget, reason: 'Elton John vooraan');
    });

    testWidgets('niet gestapeld: de kop zoals hij was, zonder foto', (t) async {
      await t.pumpWidget(_inVak(kopMetFoto(false, const ['Adele'], const Text('Adele'))));
      expect(find.byType(ArtiestRondjes), findsNothing);
    });
  });

  group('onder de titel alleen wie er nog bij komt', () {
    test('een gast: "met T.I."', () {
      final g = gastenNaastKop(['Justin Timberlake', 'T.I.'], ['Justin Timberlake']);
      expect(g.namen, ['T.I.']);
      expect(g.met, isTrue);
    });

    test('dezelfde artiesten als de plaat: niets', () {
      const lk = 'Elton John, Tim Rice, Hans Zimmer';
      expect(gastenNaastKop([lk], [...kopFotoNamen(lk), lk]).namen, isEmpty);
      expect(gastenNaastKop(['justin timberlake'], ['Justin Timberlake']).namen, isEmpty, reason: 'hoofdletters tellen niet');
    });

    test('een verzamelplaat: de artiest van het nummer, zonder "met"', () {
      final g = gastenNaastKop(['Prince'], ['Various Artists']);
      expect(g.namen, ['Prince']);
      expect(g.met, isFalse);
    });

    test('geen kop: iedereen', () {
      expect(gastenNaastKop(['Portishead'], const []).namen, ['Portishead']);
    });

    testWidgets('de regel zelf: "met T.I." en niet nog eens Justin Timberlake', (t) async {
      await t.pumpWidget(_inVak(const ArtistLine(
          artist: 'Justin Timberlake feat. T.I.', title: 'My Love', style: _stijl, alNoemd: ['Justin Timberlake'])));
      await t.pump();
      expect(find.text('met '), findsOneWidget);
      expect(find.textContaining('T.I.', findRichText: true), findsWidgets);
      expect(find.textContaining('Justin Timberlake', findRichText: true), findsNothing);
      expect(find.byType(ArtiestRondjes), findsNothing, reason: 'de foto staat bovenaan');
    });

    testWidgets('niemand erbij: geen regel', (t) async {
      await t.pumpWidget(
          _inVak(const ArtistLine(artist: 'Adele', title: 'Hello', style: _stijl, alNoemd: ['Adele'])));
      await t.pump();
      expect(find.byType(Text), findsNothing);
      expect(find.byType(RichText), findsNothing);
    });

    testWidgets('zonder kop blijft de regel wat hij was', (t) async {
      await t.pumpWidget(_inVak(const ArtistLine(artist: 'Adele', title: 'Hello', style: _stijl)));
      await t.pump();
      expect(find.textContaining('Adele', findRichText: true), findsWidgets);
    });
  });

  group('de kwaliteitsregel', () {
    testWidgets('in het midden, en leeg is niets', (t) async {
      await t.pumpWidget(_inVak(const KwaliteitsRegel(
        kwaliteit: Text('FLAC · 16/44.1', key: ValueKey('badge')),
        merk: Text('Gelijk · zacht opgenomen', key: ValueKey('merk')),
      ), breedte: 800)); // De toetsletter tekent elk teken 14 breed: samen 542 punten.
      final vak = t.getRect(find.byType(KwaliteitsRegel));
      final links = t.getRect(find.byKey(const ValueKey('badge'))).left - vak.left;
      final rechts = vak.right - t.getRect(find.byKey(const ValueKey('merk'))).right;
      expect((links - rechts).abs(), lessThan(1), reason: 'gecentreerd');
      expect(links, greaterThan(50), reason: 'echt in het midden, niet vullend tot de randen');
      await t.pumpWidget(_inVak(const KwaliteitsRegel()));
      expect(find.byType(Row), findsNothing);
    });

    testWidgets('een lang merk krimpt, de badge blijft heel', (t) async {
      await t.pumpWidget(_inVak(
        KwaliteitsRegel(
          kwaliteit: const SizedBox(width: 100, height: 20, key: ValueKey('badge')),
          merk: Text('Gelijk · ' * 30, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        breedte: 300,
      ));
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byKey(const ValueKey('badge'))).width, 100);
    });
  });

  group('bedrading (gelezen uit lib/main.dart)', () {
    final bron = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');

    test('alleen gestapeld en niet op de tv', () {
      expect(bron, contains('final gestapeld = !zij && !isTv;'));
    });

    test('de kop met de foto, de naam onder de titel alleen bij gasten', () {
      expect(bron, contains('metDeHoes(kopMetFoto(\n                  gestapeld,\n                  kopFotoNamen(artiestVanPlaat),'));
      expect(bron, contains('alNoemd: gestapeld ? kopNamen : null,'));
      expect(bron, contains('final kopNamen = artiestVanPlaat.trim().isEmpty ? const <String>[] : [...kopFotoNamen(artiestVanPlaat), artiestVanPlaat];'));
    });

    test('kwaliteit en volume uit de naamrij, naar boven de afspeelbalk', () {
      // Sinds 26-10-2026 (versies): de kwaliteit van wat klinkt, en naast elkaar een knop (niet op een tv).
      expect(bron, contains('          kwaliteit: !gestapeld && t != null && t.sizeBytes > 0\n'
          '              ? (isTv ? _qualityBadge(_stroomKwaliteit(p, _klinktAls(context, t))) : _kwaliteitKnop(context, p, t, cast))\n'));
      expect(bron, contains('merk: gestapeld || t == null ? null : _luidheidMerk(context, p, t, cast),'));
      final regel = bron.indexOf("key: const ValueKey('np-kwaliteitsregel'),");
      final balk = bron.indexOf('Text(_fmt(position), style: TextStyle(color: _muted, fontSize: 12)),');
      expect(regel, greaterThan(0));
      expect(regel, lessThan(balk), reason: 'vlak boven de afspeelbalk');
      expect(bron.substring(regel, regel + 400), contains('KwaliteitsRegel('));
    });

    test('alles een stuk hoger: minder ruimte boven dan eronder', () {
      expect(bron, contains('Spacer(flex: !gestapeld ? 1 : (isCompact(context) ? 4 : 2)),'));
    });
  });
}

// "Klaar om te kiezen" (Saber, 26-10-2026: "waar zie ik die keuze's ?? nu is dit niet duidelijk" — en: "houd rekening
// met grote en kleine scherm, verticaal en horizontaal. moet gemakkelijk werken zijn. zorg dat het direct overal
// werkt !"). De vijf die op 26-10 klaarstonden, met hun echte titels.
import 'dart:io';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/twijfel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Alleen wat de lijst van de speler leest: speelt er iets, en klinkt B.
class _Speler implements PlayerStore {
  @override
  Track? current;
  @override
  String? vergelijkBron;
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

TwijfelInfo _info(String id, {String? soort, double score = .95, String kwaliteit = 'FLAC 24/44,1'}) =>
    (id: id, bron: 'Soulseek techm_8472', score: score, kwaliteit: kwaliteit, ext: 'flac', soort: soort, luid: null);

final _nummers = [
  Track(path: r'D:\M\Take That\Nobody Else\02 - Back for Good.flac', title: 'Back for Good', artist: 'Take That', album: 'Nobody Else'),
  Track(path: r'D:\M\Take That\Everything Changes\04 - Relight My Fire.flac', title: 'Relight My Fire', artist: 'Take That', album: 'Everything Changes'),
  Track(path: r'D:\M\Daft Punk\Discovery\03 - Digital Love.flac', title: 'Digital Love', artist: 'Daft Punk', album: 'Discovery'),
  Track(path: r'D:\M\Tears For Fears\Songs From The Big Chair\03 - Everybody Wants To Rule The World.flac',
      title: 'Everybody Wants To Rule The World', artist: 'Tears For Fears', album: 'Songs From The Big Chair'),
  Track(path: r'D:\M\Kim Wilde\Kim Wilde\05 - Kids in America.flac', title: 'Kids in America', artist: 'Kim Wilde', album: 'Kim Wilde'),
  Track(path: r'D:\M\Oasis\Morning Glory\03 - Wonderwall.flac', title: 'Wonderwall', artist: 'Oasis', album: 'Morning Glory'),
];

void _zet() {
  zetTwijfelVanPc(_nummers[0].path, _info('a', soort: 'studio'));
  zetTwijfelVanPc(_nummers[1].path, _info('b', soort: 'studio'));
  zetTwijfelVanPc(_nummers[2].path, _info('c', soort: 'cd', kwaliteit: 'FLAC 16/44,1'));
  zetTwijfelVanPc(_nummers[3].path, _info('d', score: .83, kwaliteit: 'FLAC 24/192'));
  zetTwijfelVanPc(_nummers[4].path, _info('e', score: .81, kwaliteit: 'FLAC 24/48'));
}

void _wis() {
  for (final t in _nummers) {
    zetTwijfelVanPc(t.path, null);
  }
}

Widget _scherm(LibraryStore lib) => MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>.value(value: lib),
        ListenableProvider<PlayerStore>.value(value: _Speler()),
      ],
      child: const MaterialApp(home: KlaarOmTeKiezenScherm()),
    );

void main() {
  tearDown(_wis);

  test('DE KERN: alleen wat op je keuze wacht, op artiest en titel', () {
    _zet();
    final k = klaarOmTeKiezen(_nummers);
    expect([for (final x in k) x.t.title],
        ['Digital Love', 'Kids in America', 'Back for Good', 'Relight My Fire', 'Everybody Wants To Rule The World']);
    expect(k.any((x) => x.t.title == 'Wonderwall'), isFalse, reason: 'zonder kopie die wacht');
    zetTwijfelVanPc(_nummers[0].path, null);
    expect(klaarOmTeKiezen(_nummers), hasLength(4), reason: 'gehouden of weg = uit de lijst');
  });

  // Gsm staand en liggend, iPad, pc en tv. Geen overloop, alle drie de knoppen bij elk nummer, en de titel heel.
  for (final (naam, maat) in [
    ('gsm staand', const Size(360, 780)),
    ('gsm liggend', const Size(780, 360)),
    ('iPad', const Size(1024, 768)),
    ('pc 24"', const Size(1920, 1080)),
  ]) {
    testWidgets('$naam: elke kaart heeft zijn drie knoppen, niets loopt over', (tester) async {
      tester.view.physicalSize = maat;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      _zet();
      final lib = LibraryStore()..tracks.addAll(_nummers);
      await tester.pumpWidget(_scherm(lib));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Klaar om te kiezen (5)'), findsOneWidget);
      // In de volgorde van het scherm (op artiest): dan schuift de lijst alleen naar onder.
      for (final t in [for (final x in klaarOmTeKiezen(_nummers)) x.t]) {
        await tester.dragUntilVisible(
            find.byKey(ValueKey('klaar-weg-${t.path}')), find.byKey(const ValueKey('klaar-lijst')), const Offset(0, -120));
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('klaar-luister-${t.path}')), findsOneWidget);
        expect(find.byKey(ValueKey('klaar-houd-${t.path}')), findsOneWidget);
        final titel = tester.widget<Text>(find.text(t.title));
        expect(titel.maxLines, isNull, reason: 'titels niet afkappen');
        expect(titel.overflow, isNot(TextOverflow.ellipsis));
        expect(tester.takeException(), isNull);
        final soort = twijfelVoor(t.path)!.soort;
        expect(
            find.descendant(
                of: find.byKey(ValueKey('klaar-houd-${t.path}')),
                matching: find.text(soort == null ? 'Gebruiken' : 'Houden ($soort)')),
            findsOneWidget);
      }
    });
  }

  testWidgets('leeg: een zin die zegt wat hier komt', (tester) async {
    final lib = LibraryStore()..tracks.addAll(_nummers);
    await tester.pumpWidget(_scherm(lib));
    expect(find.text('Klaar om te kiezen'), findsOneWidget);
    expect(find.textContaining('Niets meer om te kiezen'), findsOneWidget);
  });

  test('aangesloten: op Start (ook op de tv), bij Mijn downloads, en Kiezen in de melding', () {
    final m = _bron('lib/main.dart');
    expect(m, contains('        // Kopieën die op je keuze wachten (studio, cd, vinyl, twijfel): bovenaan, en alleen als er iets wacht.\n'
        '        const _KlaarStrook(),\n'));
    expect(m, contains("                      key: const ValueKey('klaar-knop'),\n"));
    expect(m, contains("        action: SnackBarAction(label: 'Kiezen', onPressed: () => openKlaarOmTeKiezen(context)),\n"));
    expect(m, contains('  void _toonKlaarVanPc() => _toonKlaarMelding(klaarVanPc.value);\n'));
    // Op de tv staat de selectie meteen op de eerste knop.
    expect(m, contains('            autofocus: eerste && isTv,\n'));
    // De keuzes zelf zijn die van het label: één weg voor houden en weggooien.
    expect(m, contains('      final regels = _twijfelRegels(context, nummer, tw);\n'));
  });
}

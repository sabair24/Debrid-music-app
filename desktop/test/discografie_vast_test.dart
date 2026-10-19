// De discografie op de artiestpagina verschoof bij elke bron die binnenkwam: Deezer, dan MusicBrainz,
// dan Discogs, dan de hoezen van het archief, dan de gastoptredens. Saber, 18-10-2026: "pas tonen als
// hij compleet is — maar dan duurt het langer, dus zoek een oplossing om zo snel mogelijk alles te
// laden". De lijst staat er nu één keer, alleen hoezen vullen nog aan; en een vraag die al onderweg
// is, wordt gedeeld in plaats van nog eens op de baan gezet.
import 'dart:io';

import 'package:debridmusic/discography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DiscoRelease plaat(String titel, {String? hoes, String datum = '1990-01-01'}) =>
      DiscoRelease(title: titel, kind: RecordKind.album, firstDate: datum, cover: hoes);

  group('toonVast', () {
    test('een hoes die later binnenkomt, laat geen weggezeefde regel alsnog verschijnen', () {
      final a = plaat('Een', hoes: 'https://x/een.jpg');
      final b = plaat('Twee');
      final vast = bevriesDiscografie([a, b], zeefHoezen: true);
      final voor = toonVast(vast, const {});
      expect(voor.rijen.map((r) => r.title), ['Een']);
      final na = toonVast(vast, {b.key: 'https://x/twee.jpg'});
      expect(na.rijen.map((r) => r.title), ['Een'], reason: 'dan schuift alles eronder op');
      expect(na.zonderHoes, 1);
    });

    test('een getoonde regel zonder hoes krijgt de hoes die binnenkomt, op dezelfde plek', () {
      final a = plaat('Een', hoes: 'https://x/een.jpg');
      final b = plaat('Twee');
      final vast = bevriesDiscografie([a, b], zeefHoezen: false);
      final na = toonVast(vast, {b.key: 'https://x/twee.jpg'});
      expect(na.rijen.map((r) => r.title), ['Een', 'Twee']);
      expect(na.rijen[1].cover, 'https://x/twee.jpg');
      // Een hoes die er al was, wordt niet verdrongen.
      expect(toonVast(vast, {a.key: 'https://x/ander.jpg'}).rijen.first.cover, 'https://x/een.jpg');
    });

    test('"Toon alles" toont de hele vastgezette lijst', () {
      final vast = bevriesDiscografie([plaat('Een', hoes: 'h'), plaat('Twee')], zeefHoezen: true);
      expect(toonVast(vast, const {}, toonAlles: true).rijen, hasLength(2));
    });

    test('heruitgaves worden bij het vastzetten gevouwen, zoals bij het tekenen', () {
      final vast = bevriesDiscografie(
          [plaat('Bad', hoes: 'h', datum: '1987-08-31'), plaat('Bad 25', hoes: 'h', datum: '2012-09-18')],
          zeefHoezen: true);
      expect(vast.samen.firstWhere((r) => r.title == 'Bad 25').kind, RecordKind.albumVersie);
    });
  });

  group('de aansluiting', () {
    String bron(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

    test('de artiestpagina tekent niet per bron, en zet de lijst één keer vast', () {
      final main = bron('lib/main.dart');
      final begin = main.indexOf('final uit = await Future.wait([');
      expect(begin, greaterThan(0));
      final eind = main.indexOf(']);', begin);
      expect(main.substring(begin, eind), isNot(contains('setState')),
          reason: 'elke bron die zelf tekent, verschuift de lijst');
      expect(main, contains('if (eerste) {\n        _vast = bevriesDiscografie(alles, zeefHoezen: zeefHoezen);'));
      expect('_vast = bevriesDiscografie('.allMatches(main).length, 2, reason: 'bewaard, of de eerste keer');
    });

    test('gastoptredens gaan naar schijf en niet op het scherm', () {
      final main = bron('lib/main.dart');
      expect(main, isNot(contains('setState(() => _gasten = gasten);')));
      expect(main, contains('    _gasten = gasten;\n    _bewaar(svc, naam);'));
    });

    test('een halve lijst wordt niet bewaard, en bewaren gaat achter elkaar', () {
      final main = bron('lib/main.dart');
      expect(main,
          contains('_magBewaren = alles.isNotEmpty && !uit.any((u) => u.status == BronStatus.onbereikbaar);'));
      expect(main, contains('_bewaarRij = _bewaarRij.then((_) async {'));
      final dienst = bron('lib/discography_service.dart');
      expect(dienst, contains("if (zeefHoezen != null) 'zeefHoezen': zeefHoezen,"));
      expect(dienst, contains("zeefHoezen: j['zeefHoezen'] is bool ? j['zeefHoezen'] as bool : null,"));
    });

    test('MusicBrainz en Discogs delen een vraag die al onderweg is', () {
      for (final p in ['lib/musicbrainz.dart', 'lib/discogs.dart']) {
        final s = bron(p);
        expect(s, contains('static final Map<String, Future<Map<String, dynamic>?>> _onderweg = {};'), reason: p);
        expect(s, contains('    final bezig = _onderweg[url];\n    if (bezig != null) return bezig;'), reason: p);
        expect(s, contains('      _onderweg.remove(url);\n    }).ignore();'), reason: p);
      }
    });
  });
}

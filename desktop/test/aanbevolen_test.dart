// "Aanbevolen voor jou" (Saber, 16-10-2026): "Laadt heel traag, en moet iets meer relevant zijn met
// men muziek, en ik wil nieuwe muziek ontdekken." Gemeten tegen het echte Deezer met zes van zijn
// artiesten als zaad: 15 nummers van 12 artiesten die hij nog niet had, in 2,9 s (alle zaden tegelijk).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:debridmusic/aanbevolen.dart';
import 'package:debridmusic/nieuwe_releases.dart' show EigenArtiest;
import 'package:debridmusic/organize.dart' show artistKey;
import 'package:debridmusic/recommend.dart' show RecTrack;
import 'package:flutter_test/flutter_test.dart';

RecTrack t(String artiest, String titel, {int rank = 500000, int sec = 210}) =>
    RecTrack(artiest, titel, null, album: 'Plaat', albumId: 1, seconds: sec, rank: rank, artistId: 9);

void main() {
  final nu = DateTime(2026, 10, 16).millisecondsSinceEpoch;

  group('zaden', () {
    test('wat je draait weegt het zwaarst, en groen telt erbij', () {
      final z = kiesZaden([
        const EigenArtiest(naam: 'Weinig', beurten: 1, nummers: 2),
        const EigenArtiest(naam: 'Veel', beurten: 80, nummers: 30),
        const EigenArtiest(naam: 'Groen', beurten: 1, nummers: 2),
      ], nuMs: nu, groen: {artistKey('Groen')}, aantal: 3);
      final g = {for (final x in z) x.naam: x.gewicht};
      expect(g['Veel'], greaterThan(g['Groen']!));
      expect(g['Groen']! - g['Weinig']!, closeTo(kGroenBonus, 1e-9));
    });

    test('een gewogen trekking uit de bovenste twaalf: niet altijd dezelfde zes', () {
      final alle = [for (var i = 0; i < 20; i++) EigenArtiest(naam: 'A$i', beurten: 40 - i, nummers: 10)];
      final a = kiesZaden(alle, nuMs: nu, toeval: math.Random(1)).map((z) => z.naam).toSet();
      final b = kiesZaden(alle, nuMs: nu, toeval: math.Random(2)).map((z) => z.naam).toSet();
      expect(a, hasLength(6));
      expect(a, isNot(b), reason: 'verversen hoort iets anders te geven');
      final boven = {for (var i = 0; i < 12; i++) 'A$i'};
      expect(boven.containsAll(a) && boven.containsAll(b), isTrue, reason: 'nooit van onder de twaalf');
    });
  });

  group('kandidaten', () {
    test('wie door meer van jouw artiesten genoemd wordt, staat hoger; wat je hebt valt weg', () {
      final r = rangschikKandidaten({
        'Backstreet Boys': [(id: 1, naam: 'Westlife'), (id: 2, naam: '*NSYNC'), (id: 3, naam: 'Britney Spears')],
        'Christina Aguilera': [(id: 4, naam: 'Kelly Clarkson'), (id: 2, naam: '*NSYNC')],
      }, gewicht: {'Backstreet Boys': 10, 'Christina Aguilera': 10}, bezit: {artistKey('Britney Spears')});
      expect(r.first.naam, '*NSYNC', reason: 'verwant aan twee van je artiesten');
      expect(r.first.via, ['Backstreet Boys', 'Christina Aguilera']);
      expect([for (final k in r) k.naam], isNot(contains('Britney Spears')), reason: 'die heb je al');
    });

    test('genoemd door twee van je artiesten wint van bovenaan bij één, ook als de som kleiner is', () {
      // Y: bovenaan bij een zwaar zaad (10). X: bovenaan bij twee lichtere (4 + 4 = 8). Zonder de bonus
      // voor overlap wint Y; met de helft erbij per extra zaad (8 × 1,5 = 12) wint X.
      final r = rangschikKandidaten({
        'Zwaar': [(id: 1, naam: 'Y')],
        'Licht1': [(id: 2, naam: 'X')],
        'Licht2': [(id: 2, naam: 'X')],
      }, gewicht: {'Zwaar': 10, 'Licht1': 4, 'Licht2': 4}, bezit: {});
      expect([for (final k in r) k.naam], ['X', 'Y']);
      expect(r.first.score, closeTo(12, 1e-9));
    });

    test('een zaad is zelf nooit een kandidaat', () {
      final r = rangschikKandidaten({
        'Adele': [(id: 5, naam: 'Sam Smith')],
        'Sam Smith': [(id: 6, naam: 'Adele')],
      }, gewicht: {}, bezit: {});
      expect(r, isEmpty);
    });
  });

  group('nummers', () {
    test('geen andere versies, wel een echte ondertitel', () {
      final okt = DateTime(2026, 10, 16);
      expect(goedOmTeOntdekken(t('Kelly Clarkson', "Stronger (What Doesn't Kill You)"), nu: okt), isTrue);
      expect(goedOmTeOntdekken(t('Maroon 5', 'Moves Like Jagger (Studio Recording From "The Voice" Performance)'), nu: okt),
          isFalse);
      expect(goedOmTeOntdekken(t('Mousse T.', 'Horny (YouNotUs Club Version)'), nu: okt), isFalse);
      expect(goedOmTeOntdekken(t('Busta Rhymes', 'I Know What You Want (feat. Flipmode Squad)'), nu: okt), isTrue);
      expect(goedOmTeOntdekken(t('X', 'Intro'), nu: okt), isFalse);
      expect(goedOmTeOntdekken(t('X', 'Kort', sec: 45), nu: okt), isFalse);
    });

    test('kerst pas vanaf half november', () {
      final kerst = t('Mariah Carey', 'All I Want for Christmas Is You');
      expect(goedOmTeOntdekken(kerst, nu: DateTime(2026, 10, 16)), isFalse);
      expect(goedOmTeOntdekken(kerst, nu: DateTime(2026, 11, 20)), isTrue);
      expect(goedOmTeOntdekken(kerst, nu: DateTime(2026, 12, 24)), isTrue);
    });

    test('om de beurt: eerst één van elke kandidaat, hoogstens twee per artiest', () {
      ({Kandidaat kandidaat, List<RecTrack> toppers}) k(int id, String naam, List<RecTrack> top) =>
          (kandidaat: (id: id, naam: naam, score: 10.0 - id, via: const ['z']), toppers: top);
      final uit = kiesNummers([
        k(1, 'A', [t('A', 'a1', rank: 9), t('A', 'a2', rank: 8), t('A', 'a3', rank: 7)]),
        k(2, 'B', [t('B', 'b1', rank: 9), t('B', 'b2', rank: 8)]),
      ], nu: DateTime(2026, 10, 16));
      expect([for (final x in uit) x.title], ['a1', 'b1', 'a2', 'b2']);
    });
  });

  group('bewaren en de dienst', () {
    test('de lijst gaat heen en terug door JSON', () {
      final l = AanbevolenLijst(123, [t('Kelly Clarkson', 'Because of You')]);
      final terug = AanbevolenLijst.fromJson(jsonDecode(jsonEncode(l.toJson())))!;
      expect(terug.berekendMs, 123);
      expect(terug.nummers.single.title, 'Because of You');
      expect(terug.nummers.single.albumId, 1);
      expect(AanbevolenLijst.fromJson({'versie': 0, 'berekendMs': 1}), isNull, reason: 'oude vorm: opnieuw rekenen');
    });

    test('rekent één keer tegelijk, bewaart, en houdt de oude lijst bij een leeg antwoord', () async {
      final map = Directory.systemTemp.createTempSync('dm_aanbevolen_');
      addTearDown(() => map.deleteSync(recursive: true));
      var gevraagd = 0;
      var antwoord = [t('Kelly Clarkson', 'Because of You')];
      final d = AanbevolenVoorJou(
        zoeker: (zaden, bezit) async {
          gevraagd++;
          expect(bezit, {artistKey('Adele')});
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return antwoord;
        },
        artiesten: () => [const EigenArtiest(naam: 'Adele', beurten: 10, nummers: 5)],
        groen: () => {},
        bezit: () => {artistKey('Adele')},
        bestand: File('${map.path}${Platform.pathSeparator}aanbevolen.json'),
      );
      expect(d.verouderd, isTrue);
      await Future.wait([d.ververs(), d.ververs()]);
      expect(gevraagd, 1);
      expect(d.lijst!.nummers.single.title, 'Because of You');
      final opnieuw = AanbevolenVoorJou(
          zoeker: (_, __) async => const [],
          artiesten: () => const [],
          groen: () => {},
          bezit: () => {},
          bestand: File('${map.path}${Platform.pathSeparator}aanbevolen.json'));
      await opnieuw.laad();
      expect(opnieuw.lijst!.nummers.single.title, 'Because of You', reason: 'van schijf, meteen bij het opstarten');
      antwoord = [];
      await d.ververs();
      expect(d.lijst!.nummers, isNotEmpty, reason: 'niets gevonden is geen beter antwoord');
    });
  });

  test('aangesloten: pc rekent, toestel vraagt, Start toont meteen', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(main, contains('AanbevolenVoorJou.pc = aanbevolen;'));
    expect(main, contains('zoeker: (zaden, bezit) => rec.ontdekVoorJou(zaden, bezit),'));
    expect(main, contains('final fyF = _haalAanbevolen(seeds);'));
    expect(main, contains('if (_forYou.isEmpty) unawaited(_aanbevolenUitVoorraad());'));
    expect(main, contains("final r = await client.aanbevolen(ververs: dwing);"));
    final server = File('lib/lan/server.dart').readAsStringSync();
    expect(server, contains("case '/api/aanbevolen':"));
    final rec = File('lib/recommend.dart').readAsStringSync();
    expect(rec, contains('final verwant = await Future.wait(['), reason: 'alle zaden tegelijk, niet na elkaar');
  });
}

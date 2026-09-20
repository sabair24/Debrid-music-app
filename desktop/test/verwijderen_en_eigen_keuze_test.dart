/// Verwijderen is verwijderen, en een eigen keuze mag je terugnemen.
///
/// **Twee klachten van Saber op 20-09-2026, uit één scherm.**
///
/// 1. *"ik wil als ik een liedje verwijder, het naar volgende liedje gaat, nu loopt het liedje
///    verder, maar dat kan toch niet? verwijderen is verwijderen"*. Het wissen zit in de
///    bibliotheek en die kende de speler niet, dus speelde mpv het bestand gewoon uit. Op Windows
///    is dat erger dan vreemd: een bestand dat mpv open heeft laat zich niet wissen, `removeTracks`
///    vangt die fout op — en dan blijft het nummer óók op schijf staan.
/// 2. *"die zijn nog fake? waarom staan die er nog?"*, over twee Madonna-nummers die 24/192
///    beloven en 24/44,1 dragen. Ze staan er nog omdat hij ze zelf koos (een torrent is een vaste
///    keuze), en daar raakt geen enkele automatische regel aan. Gemeten op zijn schijf: 87 van de
///    582 eigen keuzes zijn als nep gemeten. Er was geen enkele weg terug.
library;

import 'dart:io';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/echtheid_oordelen.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/vaste_keuze.dart';
import 'package:flutter_test/flutter_test.dart';

Track _t(String pad, {String titel = 'Nummer', String artiest = 'Artiest'}) =>
    Track(path: pad, title: titel, artist: artiest, album: 'Plaat');

/// Opgeschaald: precies wat de meter van die twee Madonna-nummers zei.
const _opgeschaald = Echtheidsoordeel(
  bits: Bitdiepte.spreektNietTegen,
  boven: Bovenband.leeg,
  band: Bandbreedte.doorlopend,
  vensters: 32,
);

void main() {
  group('1 — de wachtrij zonder de weggegooide nummers', () {
    test('DE KERN: valt er iets vóór het spelende weg, dan speelt hetzelfde nummer door', () {
      // Het spelende nummer staat MIDDEN in de rij, en dat is de hele proef: schuift de index niet
      // mee, dan speelt er ineens een ander nummer. Met c als laatste zou "gewoon blijven staan"
      // toevallig hetzelfde antwoord geven.
      final a = _t('a.flac'), b = _t('b.flac'), c = _t('c.flac'), d = _t('d.flac');
      final uit = rijZonderPaden([a, b, c, d], [a, b, c, d], 2, (p) => p == 'a.flac');
      expect(uit.order.map((t) => t.path), ['b.flac', 'c.flac', 'd.flac']);
      expect(uit.original.map((t) => t.path), ['b.flac', 'c.flac', 'd.flac']);
      expect(uit.index, 1, reason: 'c speelde en speelt nog steeds — op plek 2 staat nu d');
      expect(uit.order[uit.index].path, 'c.flac');
    });

    test('DE KERN: met shuffle verliezen beide lijsten hetzelfde, en de index volgt het nummer', () {
      final a = _t('a.flac'), b = _t('b.flac'), c = _t('c.flac'), d = _t('d.flac');
      final uit = rijZonderPaden([a, b, c, d], [d, a, c, b], 2, (p) => p == 'a.flac');
      expect(uit.original.map((t) => t.path), ['b.flac', 'c.flac', 'd.flac'], reason: 'de plaatvolgorde blijft');
      expect(uit.order.map((t) => t.path), ['d.flac', 'c.flac', 'b.flac'], reason: 'de schudvolgorde blijft');
      expect(uit.index, 1, reason: 'c speelde; op plek 2 staat nu b');
      expect(uit.order[uit.index].path, 'c.flac');
    });

    test('DE VAL: valt het spelende nummer zelf weg, dan blijft de plek staan en gaat hij niet dwalen', () {
      // De speler is er dan al vanaf gestapt (zie `vergeetPaden`); dit is alleen nog de boekhouding.
      final a = _t('a.flac'), b = _t('b.flac'), c = _t('c.flac');
      final uit = rijZonderPaden([a, b, c], [a, b, c], 1, (p) => p == 'b.flac');
      expect(uit.order.map((t) => t.path), ['a.flac', 'c.flac']);
      expect(uit.index, 1, reason: 'op de plek waar b stond staat nu c');
    });

    test('DE GRENS: alles weg is niets meer, en een lege wachtrij blijft leeg', () {
      final a = _t('a.flac');
      expect(rijZonderPaden([a], [a], 0, (_) => true).index, -1);
      expect(rijZonderPaden(const [], const [], -1, (_) => true).index, -1);
    });

    test('DE GRENS: niets weg is niets veranderd', () {
      final a = _t('a.flac'), b = _t('b.flac');
      final uit = rijZonderPaden([a, b], [b, a], 1, (_) => false);
      expect(uit.order.map((t) => t.path), ['b.flac', 'a.flac']);
      expect(uit.index, 1);
    });
  });

  group('2 — eerst de speler, dan pas de schijf', () {
    late Directory wortel;
    setUp(() {
      wortel = Directory.systemTemp.createTempSync('dm_verwijder_');
      setAppDirForTest(wortel.path);
    });
    tearDown(() {
      resetVasteKeuzesForTest();
      resetEchtheidVoorTest();
      try {
        wortel.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('DE KERN: de speler hoort het VOORDAT het bestand weg is', () async {
      final f = File('${wortel.path}${Platform.pathSeparator}weg.flac')..writeAsStringSync('muziek');
      final lib = LibraryStore()..configDirOverride = wortel.path;
      final gemeld = <String>[];
      var bestondNogBijDeMelding = false;
      lib.speelNietMeer = (paden) async {
        gemeld.addAll(paden);
        bestondNogBijDeMelding = f.existsSync();
      };

      final weg = await lib.removeTracks([f.path], fromDisk: true);

      expect(gemeld, [f.path]);
      expect(bestondNogBijDeMelding, isTrue,
          reason: 'anders is mpv het bestand nog aan het spelen en laat Windows het niet wissen');
      expect(weg, 1);
      expect(f.existsSync(), isFalse);
    });

    test('DE VAL: een speler die struikelt houdt het wissen niet tegen', () async {
      final f = File('${wortel.path}${Platform.pathSeparator}weg2.flac')..writeAsStringSync('muziek');
      final lib = LibraryStore()..configDirOverride = wortel.path;
      lib.speelNietMeer = (_) async => throw StateError('speler ligt eruit');

      expect(await lib.removeTracks([f.path], fromDisk: true), 1);
      expect(f.existsSync(), isFalse);
    });

    test('DE GRENS: ook wie alleen uit de bibliotheek haalt, hoort op te houden met spelen', () async {
      final f = File('${wortel.path}${Platform.pathSeparator}blijft.flac')..writeAsStringSync('muziek');
      final lib = LibraryStore()..configDirOverride = wortel.path;
      var gemeld = false;
      lib.speelNietMeer = (_) async => gemeld = true;

      await lib.removeTracks([f.path], fromDisk: false);

      expect(gemeld, isTrue, reason: 'uit je bibliotheek gehaald is ook weg');
      expect(f.existsSync(), isTrue, reason: 'maar het bestand blijft staan, dat is de belofte');
    });
  });

  group('3 — wat je zelf koos, toch laten vervangen', () {
    late Directory wortel;
    setUp(() {
      wortel = Directory.systemTemp.createTempSync('dm_eigenkeuze_');
      setAppDirForTest(wortel.path);
    });
    tearDown(() {
      resetVasteKeuzesForTest();
      resetEchtheidVoorTest();
      try {
        wortel.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('DE KERN: een eigen keuze die nep is staat op de nieuwe lijst, en niet op de oude', () async {
      final eigen = '${wortel.path}${Platform.pathSeparator}madonna.flac';
      final vreemd = '${wortel.path}${Platform.pathSeparator}soulseek.flac';
      final lib = LibraryStore()..configDirOverride = wortel.path;
      lib.tracks.addAll([_t(eigen, titel: 'Material Girl'), _t(vreemd, titel: 'Toxic')]);
      lib.rebuildAlbums();
      onthoudOordeelVanPc(eigen, _opgeschaald);
      onthoudOordeelVanPc(vreemd, _opgeschaald);
      await onthoudVasteKeuze(eigen);

      expect(lib.eigenKeuzesDieNepZijn().map((r) => r.track.path), [eigen]);
      expect(lib.teVervangenBestanden().map((r) => r.track.path), [vreemd],
          reason: 'de oude knop laat een eigen keuze met rust — dat blijft zo');
    });

    test('DE KERN: vrijgeven haalt de bescherming eraf, en dan telt hij gewoon mee', () async {
      final eigen = '${wortel.path}${Platform.pathSeparator}madonna.flac';
      final lib = LibraryStore()..configDirOverride = wortel.path;
      lib.tracks.add(_t(eigen, titel: 'Like A Virgin'));
      lib.rebuildAlbums();
      onthoudOordeelVanPc(eigen, _opgeschaald);
      await onthoudVasteKeuze(eigen);

      expect(await lib.geefEigenKeuzeVrij([lib.tracks.single]), 1);

      expect(isVasteKeuze(eigen), isFalse);
      expect(lib.eigenKeuzesDieNepZijn(), isEmpty);
      expect(lib.teVervangenBestanden().map((r) => r.track.path), [eigen],
          reason: 'nu mag de jacht er wel aan');
    });

    test('DE GRENS: een eigen keuze die NIET nep is blijft met rust gelaten', () async {
      final goed = '${wortel.path}${Platform.pathSeparator}echt.flac';
      final lib = LibraryStore()..configDirOverride = wortel.path;
      lib.tracks.add(_t(goed));
      lib.rebuildAlbums();
      await onthoudVasteKeuze(goed);
      expect(lib.eigenKeuzesDieNepZijn(), isEmpty, reason: 'ongemeten of schoon: niets aan de hand');
      expect(await lib.geefEigenKeuzeVrij(lib.tracks), 1);
    });
  });

  group('4 — de app sluit het ook echt aan', () {
    String lees(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
    final main = lees('lib/main.dart');
    final player = lees('lib/player.dart');

    test('DE KERN: main.dart hangt de speler aan het verwijderen', () {
      expect(main, contains('library.speelNietMeer = player.vergeetPaden'));
    });

    test('DE KERN: de Kwaliteitspagina heeft de knop en vraagt het eerst', () {
      expect(main, contains("label: Text('Ook wat je zelf koos ("));
      expect(main, contains('onPressed: _vervangOokEigenKeuzes'));
      final i = main.indexOf('Future<void> _vervangOokEigenKeuzes()');
      final lijf = main.substring(i, main.indexOf('\n  }\n', i));
      expect(lijf, contains('showDialog'), reason: 'dit haalt een bescherming weg die je zelf aanzette');
      expect(lijf.indexOf('geefEigenKeuzeVrij'), lessThan(lijf.indexOf('wensEchteVersies')),
          reason: 'eerst vrijgeven, anders slaat de wens hem over');
    });

    test('DE VAL: vergeetPaden stapt eerst van het spelende nummer af, dan pas uit de lijst', () {
      final i = player.indexOf('Future<void> vergeetPaden(');
      final lijf = player.substring(i, player.indexOf('\n  }\n', i));
      expect(lijf.indexOf('await next()'), greaterThan(0));
      expect(lijf.indexOf('await next()'), lessThan(lijf.indexOf('rijZonderPaden(')),
          reason: 'anders laat mpv het bestand niet los en lukt het wissen op Windows niet');
      expect(lijf, contains('_player.stop()'), reason: 'zonder volgende: stoppen, niet doorspelen');
    });
  });
}

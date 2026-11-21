/// Het opruimen na een radio laat staan wat nog in een rij staat (21-11-2026).
///
/// Live gemeten op de Shield: een radio op de Mac, naar de tv verplaatst met zijn rij; daarna vanaf de Mac een nieuwe
/// radio op de tv. Op de Mac sloot de eerste radio af en het overzicht gooide zijn proefnummers weg — Louis Armstrong,
/// "Can Anyone Explain?", en Chet Baker — terwijl Louis Armstrong nog in de rij van de tv stond: 404, overgeslagen, en
/// twee minuten later nog eens. Saber: "ja" op "proefnummers die worden opgeruimd terwijl ze nog in de rij staan".
library;

import 'dart:io';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/radiosessie.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('staatNogInEenRij', () {
    test('DE KERN: wat nog komt of nu speelt telt; wat al gespeeld is niet', () {
      final rijen = [(rij: ['a', 'b', 'c', 'd'], index: 2)];
      expect(staatNogInEenRij('c', rijen), isTrue, reason: 'speelt nu');
      expect(staatNogInEenRij('d', rijen), isTrue, reason: 'komt nog');
      expect(staatNogInEenRij('b', rijen), isFalse, reason: 'al gespeeld: mag weg');
      expect(staatNogInEenRij('x', rijen), isFalse);
    });

    test('elke rij telt mee, ook een tweede toestel; leeg en een plek onder nul', () {
      final rijen = [
        (rij: ['a'], index: 0),
        (rij: ['p', 'q'], index: 1),
      ];
      expect(staatNogInEenRij('q', rijen), isTrue);
      expect(staatNogInEenRij('p', rijen), isFalse);
      expect(staatNogInEenRij('', [(rij: [''], index: 0)]), isFalse, reason: 'een nummer zonder id is geen treffer');
      expect(staatNogInEenRij('a', [(rij: ['a'], index: -1)]), isTrue, reason: 'nog niets gespeeld: alles komt nog');
    });
  });

  group('de bibliotheek', () {
    late Directory wortel;
    setUp(() => wortel = Directory.systemTemp.createTempSync('dm_inderij_'));
    tearDown(() {
      try {
        wortel.deleteSync(recursive: true);
      } catch (_) {}
    });

    LibraryStore bibliotheek(List<File> bestanden) => LibraryStore()
      ..configDirOverride = wortel.path
      ..heeftPrullenbak = true
      ..prullenbak = (paden) async {
        for (final p in paden) {
          File(p).deleteSync();
        }
        return paden.toSet();
      }
      ..tracks.addAll([
        for (final f in bestanden) Track(path: f.path, title: f.uri.pathSegments.last, artist: 'Radio', album: 'Singles'),
      ]);

    test('DE KERN: wat nog in een rij staat blijft staan, de rest gaat naar de prullenbak', () async {
      final louis = File('${wortel.path}${Platform.pathSeparator}Can Anyone Explain.flac')..writeAsStringSync('x');
      final chet = File('${wortel.path}${Platform.pathSeparator}Time After Time.flac')..writeAsStringSync('x');
      final lib = bibliotheek([louis, chet])..inEenRij = (p) => p == louis.path;
      final weg = await lib.removeTracks([louis.path, chet.path],
          fromDisk: true, naarPrullenbak: true, behoudInEenRij: true);
      expect(weg, 1);
      expect(louis.existsSync(), isTrue, reason: 'staat nog in de rij van de tv');
      expect(chet.existsSync(), isFalse);
      expect(lib.tracks.map((t) => t.path), [louis.path]);
    });

    test('zonder de vraag (gewoon verwijderen) gaat alles weg, ook wat in een rij staat', () async {
      final a = File('${wortel.path}${Platform.pathSeparator}a.flac')..writeAsStringSync('x');
      final lib = bibliotheek([a])..inEenRij = (_) => true;
      expect(await lib.removeTracks([a.path], fromDisk: true, naarPrullenbak: true), 1);
      expect(a.existsSync(), isFalse, reason: 'wie zelf verwijdert, bedoelt het');
    });
  });

  group('aangesloten (gelezen uit de bron)', () {
    test('het opruimen na een radio vraagt het, en een toestel geeft de vraag aan de pc mee', () {
      final m = _bron('lib/main.dart');
      expect(m, contains('  final weg = await lib.removeTracks(paden, fromDisk: true, naarPrullenbak: true, behoudInEenRij: true);'));
      final l = _bron('lib/library.dart');
      expect(l, contains("        if (behoudInEenRij) 'behoudInEenRij': true,\n"));
      expect(l, contains('    if (behoudInEenRij) paths = [for (final p in paths) if (!(inEenRij?.call(p) ?? false)) p];\n'
          '    if (isRemote) {'), reason: 'ook op een toestel eerst de eigen rij');
      expect(_bron('lib/lan/server.dart'), contains("              behoudInEenRij: body['behoudInEenRij'] == true);"));
    });

    test('de pc kijkt naar zijn eigen rij én naar de rij die elk toestel het afgelopen uur meldde', () {
      final m = _bron('lib/main.dart');
      final haak = m.substring(m.indexOf('  library.inEenRij = (pad) {'));
      final tot = haak.substring(0, haak.indexOf('  };'));
      expect(tot, contains('? radioMelding(player.radioQueue, player.radioIndex)'), reason: 'bij een radio: de radiorij');
      expect(tot, contains('for (final s in sharing.state.perToestel.values)'));
      expect(tot, contains('if (nu - s.updatedAt < const Duration(hours: 1).inMilliseconds) (rij: s.queue, index: s.index),'));
      expect(tot, contains('if (mode.owner)'), reason: 'alleen de pc kent de rijen van de andere toestellen');
    });
  });
}

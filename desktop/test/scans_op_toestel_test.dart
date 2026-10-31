/// De scans van albums (cd, achterkant) op een toestel binnen een grens (Saber, 31-10-2026: op de Mac stond `releaseart` op
/// 800 MB, want op een toestel werd nooit gesnoeid — "ok, maar ik ga toch alles zien e").
///
/// Ja: de pc bewaart alles en geeft het weer bij het openen. Hier: wat weg gaat is wat het langst niet GETOOND is (niet
/// wat het langst geleden geschreven is), en wat "Op dit toestel" staat, blijft — zonder pc moeten die scans er zijn.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/cache_snoei.dart';
import 'package:debridmusic/organize.dart' show normKey;

String _bron(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  late Directory wortel;
  setUp(() => wortel = Directory.systemTemp.createTempSync('dm_scans_'));
  tearDown(() {
    try {
      wortel.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Een albummapje zoals `releaseart` het schrijft, [dagen] geleden.
  Directory album(String naam, {int kb = 300, int dagen = 0}) {
    final d = Directory('${wortel.path}${Platform.pathSeparator}$naam')..createSync();
    final toen = DateTime.now().subtract(Duration(days: dagen));
    for (final (n, grootte) in [('front', kb ~/ 3), ('disc', kb ~/ 3), ('back', kb ~/ 3), ('done', 0)]) {
      File('${d.path}${Platform.pathSeparator}$n')
        ..writeAsBytesSync(List.filled(grootte * 1024 + 1, 1))
        ..setLastModifiedSync(toen);
    }
    return d;
  }

  File gezien(Directory d) => File('${d.path}${Platform.pathSeparator}gezien');

  group('gezienMerk', () {
    test('schrijft van wie de scans zijn, en hoogstens eens per twaalf uur', () async {
      final d = album('a');
      final nu = DateTime.now();
      await gezienMerk(d, 'Michael Jackson', 'Bad', nu: nu);
      expect(gezien(d).readAsLinesSync(), ['Michael Jackson', 'Bad']);
      final eerst = gezien(d).lastModifiedSync();
      await gezienMerk(d, 'Michael Jackson', 'Bad', nu: nu.add(const Duration(hours: 2)));
      expect(gezien(d).lastModifiedSync(), eerst, reason: 'twee uur later: niet opnieuw schrijven');
      // Dertien uur oud: dan wel.
      final toen = nu.subtract(const Duration(hours: 13));
      gezien(d).setLastModifiedSync(toen);
      await gezienMerk(d, 'Michael Jackson', 'Bad', nu: nu);
      expect(gezien(d).lastModifiedSync().isAfter(toen.add(const Duration(hours: 12))), isTrue);
    });

    test('een map die er niet (meer) is: niets, en geen fout', () async {
      await gezienMerk(Directory('${wortel.path}${Platform.pathSeparator}weg'), 'A', 'B');
      expect(Directory('${wortel.path}${Platform.pathSeparator}weg').existsSync(), isFalse);
    });
  });

  group('snoeien op een toestel', () {
    test('DE KERN: wat je net bekeek blijft, ook al is het het oudst geschreven', () async {
      final oudMaarBekeken = album('oud', dagen: 30);
      final midden = album('midden', dagen: 10);
      final nieuw = album('nieuw', dagen: 1);
      await gezienMerk(oudMaarBekeken, 'A', 'Oud');
      await snoeiMap(wortel, maxBytes: 650 * 1024, perMap: true);
      expect(oudMaarBekeken.existsSync(), isTrue);
      expect(nieuw.existsSync(), isTrue);
      expect(midden.existsSync(), isFalse, reason: 'het langst niet getoond');
    });

    test('wat op dit toestel bewaard is, blijft — ook boven de grens, en het telt mee', () async {
      final bewaard = album('bewaard', dagen: 60);
      await gezienMerk(bewaard, 'Michael Jackson', 'Bad', nu: DateTime.now().subtract(const Duration(days: 60)));
      gezien(bewaard).setLastModifiedSync(DateTime.now().subtract(const Duration(days: 60)));
      final a = album('a', dagen: 5);
      final b = album('b', dagen: 1);
      final hier = {normKey('Bad')};
      await snoeiMap(wortel, maxBytes: 650 * 1024, perMap: true, houd: (m) => gezienVoor(m, hier));
      expect(bewaard.existsSync(), isTrue, reason: 'op dit toestel: zonder pc moet de cd er zijn');
      expect(b.existsSync(), isTrue);
      expect(a.existsSync(), isFalse, reason: 'het bewaarde album neemt zijn plek in de begroting in');
    });
  });

  test('gezienVoor: op de albumtitel; zonder merk of zonder albums niet', () async {
    final d = album('x');
    expect(gezienVoor(d, {normKey('Bad')}), isFalse, reason: 'nog geen merk');
    await gezienMerk(d, 'Michael Jackson', 'BAD');
    expect(gezienVoor(d, {normKey('Bad')}), isTrue);
    expect(gezienVoor(d, {normKey('Thriller')}), isFalse);
    expect(gezienVoor(d, const {}), isFalse);
  });

  test('aangesloten: elke getoonde plaat wordt gemerkt, en elk toestel snoeit met 300 MB', () {
    expect(kReleaseartToestel, 300 * 1024 * 1024);
    final discogs = _bron('lib/discogs.dart');
    expect(discogs, contains('      unawaited(gezienMerk(dir, artist, album));\n      return _metDigitaal(cached, await digitaalF);\n'));
    expect(discogs, contains('            .then((a) async {\n      unawaited(gezienMerk(dir, artist, album));\n'));
    final hoofd = _bron('lib/main.dart');
    expect(hoofd, contains('  if (!mode.owner) {\n    Future<void> snoeiScansHier() async {\n      if (library.tracks.isEmpty) return;\n'));
    expect(hoofd, contains('      if (offline.tracks.isNotEmpty && hier.isEmpty) return;\n'));
    expect(hoofd, contains('maxBytes: kReleaseartToestel, perMap: true, houd: (map) => gezienVoor(map, hier));'));
    expect(hoofd, contains('    Timer.periodic(const Duration(hours: 24), (_) => unawaited(snoeiScansHier()));\n'));
  });
}

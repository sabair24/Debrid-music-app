import 'dart:io';

import 'package:debridmusic/online.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wat bij een herstart opnieuw begint. Gemeten op 21-10-2026: Doechii — Anxiety stond om 23:44 al in
/// 88.2 kHz in de bibliotheek, en na de herstart haalde de pc hem toch nog eens (80,7 MB) — omdat de
/// taak tijdens de jacht op betere kwaliteit in de notitie was gekomen en er nooit meer uit ging.
void main() {
  DownloadJob taak(String status, {bool kandidaten = true}) => DownloadJob('Anxiety', status: status)
    ..candidates = kandidaten
        ? [SoulseekFile(username: 'couchgoblin', filename: '01 - Anxiety.flac', size: 80700000)]
        : const [];

  test('een onderbroken download komt terug', () {
    for (final s in ['queued', 'waiting', 'downloading', 'preparing']) {
      expect(taak(s).hoortInHervatnotitie, isTrue, reason: s);
    }
  });

  test('wat al speelt, komt niet terug — ook niet als hij nog op beter jaagt', () {
    expect(taak('upgrading').busy, isTrue, reason: 'de jacht telt als bezig; daar zat de fout');
    expect(taak('upgrading').hoortInHervatnotitie, isFalse);
    expect(taak('done').hoortInHervatnotitie, isFalse);
    expect(taak('failed').hoortInHervatnotitie, isFalse);
  });

  test('zonder kandidaten valt er niets te hervatten', () {
    expect(taak('downloading', kandidaten: false).hoortInHervatnotitie, isFalse);
  });

  test('de notitie gebruikt die regel', () {
    final bron = File('lib/online.dart').readAsStringSync();
    final begin = bron.indexOf('Future<void> _savePending() async {');
    expect(begin, greaterThan(0));
    final lijf = bron.substring(begin, bron.indexOf('\n  }\n', begin));
    expect(lijf, contains('jobs.where((j) => j.hoortInHervatnotitie)'));
  });
}

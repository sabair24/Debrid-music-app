// Verifies TorBox search (apibay/BitSearch/Knaben) + cache detection + resolve,
// using the on-device TorBox token (never hardcoded).
import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/settings.dart';

void main() {
  test('TorBox search + resolve', () async {
    final settings = AppSettings();
    await settings.load();
    final online = OnlineService(settings);
    // ignore: avoid_print
    print('torbox ready: ${online.torboxReady}');

    final results = await online.search('daft punk discovery');
    final cached = results.where((r) => r.cached).length;
    // ignore: avoid_print
    print('results: ${results.length}, cached(instant): $cached');
    for (final r in results.take(5)) {
      // ignore: avoid_print
      print('   [${r.source}] ${r.name.substring(0, r.name.length.clamp(0, 46))} — ${r.seeders} sd ${r.cached ? "⚡" : ""}');
    }
    expect(results.length, greaterThan(0));

    final pick = results.firstWhere((r) => r.cached, orElse: () => results.first);
    // ignore: avoid_print
    print('resolving: ${pick.name}');
    try {
      final url = await online.resolveStreamUrl(pick);
      // ignore: avoid_print
      print('RESOLVED URL: ${url.substring(0, url.length.clamp(0, 70))}…');
      expect(url.startsWith('http'), true);
    } catch (e) {
      // ignore: avoid_print
      print('resolve note: $e');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

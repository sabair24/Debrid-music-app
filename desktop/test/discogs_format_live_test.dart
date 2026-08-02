@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/discography.dart';
import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

/// Welke soort hoort bij een Discogs-MASTER?
///
/// Van Sia's 244 regels stonden er 51 in "Overig". GEMETEN: 95 van haar 162 eigen Discogs-regels
/// zijn masters, en een master draagt geen `format`-veld — vandaar. Zijn HOOFDPERSING draagt het
/// wel, in `formats[].descriptions`: daar staat letterlijk "Single", "Album", "EP".
///
/// Dat is één extra verzoek per regel op een baan van zestig per minuut. De gratis kandidaat is de
/// tracklijstlengte van de master zelf. Deze meting zet ze naast elkaar op een steekproef, zodat de
/// keuze op cijfers rust en niet op wat een tracklijstlengte "meestal" betekent.
void main() {
  setUpAll(() async {
    HttpOverrides.global = null;
    await initAppPaths();
  });

  /// De gratis kandidaat: soort uit het aantal nummers van de master.
  RecordKind uitLengte(int n) {
    if (n <= 0) return RecordKind.other;
    if (n <= 3) return RecordKind.single;
    if (n <= 6) return RecordKind.ep;
    return RecordKind.album;
  }

  test('METING: tracklijstlengte tegen de echte formaatomschrijving', () async {
    final s = AppSettings();
    await s.load();
    final dg = DiscogsService(s);
    if (!dg.available) {
      // ignore: avoid_print
      print('geen Discogs-token — niets te meten');
      return;
    }
    final client = HttpClient();
    Future<Map<String, dynamic>?> haal(String url) async {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'DebridMusic/1.0');
      req.headers.set('Authorization', 'Discogs token=${s.discogsToken.trim()}');
      final res = await req.close();
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      return jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
    }

    final id = await dg.artistId('Sia');
    final lijst = await haal('https://api.discogs.com/artists/$id/releases'
        '?sort=year&sort_order=desc&per_page=100&page=1');
    final masters = [
      for (final r in (lijst?['releases'] as List? ?? const []))
        if (r is Map && r['role'] == 'Main' && r['type'] == 'master') r
    ];
    // ignore: avoid_print
    print('masters op pagina 1: ${masters.length} — steekproef van 20');

    var eens = 0, oneens = 0, geenWaarheid = 0;
    for (final m in masters.take(20)) {
      final master = await haal('https://api.discogs.com/masters/${m['id']}');
      final lengte = (master?['tracklist'] as List?)?.length ?? 0;
      final hoofd = (m['main_release'] as num?)?.toInt();
      final rel = hoofd == null ? null : await haal('https://api.discogs.com/releases/$hoofd');
      final formats = (rel?['formats'] as List? ?? const []);
      // Precies zoals de artiestenlijst zijn format-veld schrijft: naam plus omschrijvingen.
      final tekst = [
        for (final f in formats)
          if (f is Map) ...[
            (f['name'] ?? '').toString(),
            ...((f['descriptions'] as List? ?? const []).map((d) => d.toString())),
          ]
      ].where((x) => x.isNotEmpty).join(', ');

      final waarheid = kindFromDiscogs(tekst);
      final gok = uitLengte(lengte);
      if (waarheid == RecordKind.other) {
        geenWaarheid++;
      } else if (waarheid == gok) {
        eens++;
      } else {
        oneens++;
        // ignore: avoid_print
        print('  ONEENS: "${m['title']}" lengte=$lengte -> ${gok.name}, '
            'maar formaat "$tekst" -> ${waarheid.name}');
      }
    }
    client.close();

    // ignore: avoid_print
    print('eens: $eens   oneens: $oneens   formaat zei ook niets: $geenWaarheid');
    // ignore: avoid_print
    print(oneens == 0
        ? 'GEVOLG: de lengte volstaat — geen extra verzoek per regel nodig.'
        : 'GEVOLG: de lengte gokt ernaast; de hoofdpersing opvragen is de juiste weg.');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

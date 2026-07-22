@Tags(['live'])
library;
import 'dart:convert';
import 'dart:io';
import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('bsb', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    final f = File([Platform.environment['APPDATA'], 'debridmusic', 'settings.json'].join(Platform.pathSeparator));
    final tok = (jsonDecode(await f.readAsString()) as Map<String, dynamic>)['discogs_token'] as String;
    final d = DiscogsService(AppSettings()..discogsToken = tok);
    final e = await d.edition('Backstreet Boys', 'Backstreet Boys', expectedTracks: 2);
    print('editie: ${e?.format} ${e?.year} ${e?.label} ${e?.catno} ${e?.country}  tracks=${e?.tracklist.length}');
    print('scans: ${e?.images.length}');
    for (var i = 0; i < (e?.images.length ?? 0) && i < 4; i++) {
      final im = e!.images[i];
      final r = await http.get(Uri.parse(im.uri), headers: {'User-Agent': 'DebridMusic/1.0', 'Authorization': 'Discogs token=$tok'});
      print('  [$i] ${im.primary ? "primary" : "secondary"} ${im.width}x${im.height} -> HTTP ${r.statusCode} ${r.bodyBytes.length}b');
    }
    final art = await d.releaseArt('Backstreet Boys', 'Backstreet Boys', expectedTracks: 2);
    print('art: front=${art?.front?.length} back=${art?.back?.length} disc=${art?.disc?.length}');
  }, timeout: const Timeout(Duration(minutes: 4)));
}

@Tags(['live'])
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:debridmusic/artwork.dart';
import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Runs the disc detector over the actual scans Discogs holds for a release.
void main() {
  test('Dangerous: which scan is the disc?', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    final f = File([Platform.environment['APPDATA'], 'debridmusic', 'settings.json'].join(Platform.pathSeparator));
    final tok = (jsonDecode(await f.readAsString()) as Map<String, dynamic>)['discogs_token'] as String;
    final d = DiscogsService(AppSettings()..discogsToken = tok);

    final e = await d.edition('Michael Jackson', 'Dangerous', expectedTracks: 14);
    expect(e, isNotNull);
    print('editie: ${e!.format} ${e.year} ${e.label} ${e.catno} ${e.country} — ${e.images.length} scans');
    for (var i = 0; i < e.images.length; i++) {
      final im = e.images[i];
      Uint8List? bytes;
      try {
        final r = await http.get(Uri.parse(im.uri), headers: {'User-Agent': 'DebridMusic/1.0'});
        if (r.statusCode == 200) bytes = r.bodyBytes;
      } catch (_) {}
      final kind = guessKind(i, im.primary, bytes);
      print('  [$i] ${im.width}x${im.height} ${im.primary ? "primary  " : "secondary"} '
          '${bytes == null ? "(niet op te halen)" : "${(bytes.length / 1024).round()} kB"}  ->  $kind');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

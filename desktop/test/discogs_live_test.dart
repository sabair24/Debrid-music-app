@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hits the real Discogs API with the user's own token. Tagged so it doesn't run in the normal
/// suite — it costs rate limit and needs a configured token.
void main() {
  late DiscogsService d;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // flutter_test swaps in a mock HTTP client that answers 400 to everything, so a live test
    // has to hand the real one back.
    HttpOverrides.global = null;
    final f = File([Platform.environment['APPDATA'], 'debridmusic', 'settings.json'].join(Platform.pathSeparator));
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    final s = AppSettings()..discogsToken = (j['discogs_token'] ?? '') as String;
    d = DiscogsService(s);
    print('token aanwezig: ${d.available}');
  });

  test('Discovery: picks an edition and fills the page', () async {
    final id = await d.masterId('Daft Punk', 'Discovery');
    print('  master id: $id');
    final e = await d.edition('Daft Punk', 'Discovery', expectedTracks: 14);
    print('  editie   : ${e == null ? "GEEN" : e.format}');
    expect(e, isNotNull);
    print('  jaar     : ${e!.year}   land: ${e.country}');
    print('  label    : ${e.label}  ${e.catno}');
    print('  genres   : ${e.genres.join(', ')}');
    print('  styles   : ${e.styles.join(', ')}');
    print('  tracks   : ${e.tracklist.length}');
    print('  eerste 3 : ${e.tracklist.take(3).map((t) => '${t.position} ${t.title} (${t.duration})').join(' | ')}');
    print('  covers   : ${e.images.length}');
    expect(e.tracklist.length, greaterThanOrEqualTo(12));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('Daft Punk: profile, members, photos', () async {
    final a = await d.artist('Daft Punk');
    expect(a, isNotNull);
    print('  naam     : ${a!.name}');
    print('  leden    : ${a.members.join(', ')}');
    print('  aliassen : ${a.aliases.take(4).join(', ')}');
    print('  fotos    : ${a.images.length}  (portret ${a.portraits.length}, breed ${a.backdrops.length})');
    final p = a.profile;
    print('  profiel  : ${p.substring(0, p.length < 200 ? p.length : 200)}...');
    expect(p, isNot(contains('[a=')), reason: 'markup must be stripped');
    expect(a.images, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('Bad: the album master, not the promo single of the same name', () async {
    final e = await d.edition('Michael Jackson', 'Bad', expectedTracks: 11);
    expect(e, isNotNull);
    print('  editie   : ${e!.format}  ${e.year}  ${e.label} ${e.catno} ${e.country}');
    print('  tracks   : ${e.tracklist.length}');
    expect(e.tracklist.length, greaterThanOrEqualTo(9),
        reason: 'a promo 7 inch has two tracks; the album has eleven');
  }, timeout: const Timeout(Duration(minutes: 3)));
}

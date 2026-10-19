@Tags(['live'])
library;

import 'dart:io';

import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/discography.dart';
import 'package:debridmusic/discography_service.dart';
import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// METING (Saber, 19-10-2026: "vaak merk ik dat er singles staan bij albums, bij veel artiesten").
///
/// Telt per artiest de tegels in het blok Albums die openen op een plaat die Deezer zelf een single of
/// EP noemt — het album "Taking Chances" dat de hoes en de twee nummers van de single "Taking Chances"
/// draagt. En omgekeerd de prijs van uit elkaar houden: albumtegels die daardoor geen Deezer-link meer
/// hebben terwijl er wel een Deezer-plaat met die titel is.
///
/// Draaien: `flutter test --tags live test/singles_bij_albums_live_test.dart`
void main() {
  setUpAll(() async {
    HttpOverrides.global = null;
    await initAppPaths();
  });

  test('METING: albumtegels die op een single openen', () async {
    final s = AppSettings();
    await s.load();
    final svc = DiscographyService(CatalogService(), MusicBrainzService(), DiscogsService(s));
    const artiesten = [
      'Alabina', 'Céline Dion', 'Ricky Martin', 'P!nk', 'Madonna', 'Westlife', 'Kate Ryan', 'Faithless', 'Janet Jackson',
    ];
    var totaalAlbums = 0, totaalFout = 0, totaalZonderDeezer = 0, totaalSingles = 0;
    for (final naam in artiesten) {
      final dz = await svc.vanDeezer(naam);
      final mb = await svc.vanMusicBrainz(naam);
      final dg = await svc.vanDiscogs(naam);
      final klein = {
        for (final r in dz.releases)
          if (r.kind == RecordKind.single || r.kind == RecordKind.ep) r.refs[DiscoSource.deezer]?.id: r,
      };
      final dzSleutels = {for (final r in dz.releases) r.key};
      final samen = mergeDiscography([dz.releases, mb.releases, dg.releases]);
      final albums = samen.where((r) => r.blok == RecordKind.album).toList();
      final fout = albums.where((r) => klein.containsKey(r.refs[DiscoSource.deezer]?.id)).toList();
      final zonder = albums.where((r) => r.refs[DiscoSource.deezer] == null && dzSleutels.contains(r.key)).toList();
      totaalAlbums += albums.length;
      totaalSingles += samen.where((r) => r.blok == RecordKind.single || r.blok == RecordKind.ep).length;
      totaalFout += fout.length;
      totaalZonderDeezer += zonder.length;
      // ignore: avoid_print
      print('$naam: ${albums.length} albums, ${fout.length} openen op een single/ep'
          '${fout.isEmpty ? '' : ': ${fout.map((r) => '"${r.title}" ${r.year}').join(', ')}'}'
          ' | ${zonder.length} zonder Deezer-link terwijl Deezer de titel kent'
          '${zonder.isEmpty ? '' : ': ${zonder.map((r) => '"${r.title}" ${r.sources.map((s) => s.name).join('+')}'
              '${(vulHoezenAan([r], dg.hoezen).first.cover ?? '').isEmpty ? ' GEEN HOES' : ' hoes'}').join(', ')}'}');
    }
    // ignore: avoid_print
    print('SAMEN: $totaalAlbums albums, $totaalFout openen op een single/ep, '
        '$totaalZonderDeezer zonder Deezer-link, $totaalSingles singles en ep\'s');
  }, timeout: const Timeout(Duration(minutes: 20)));
}

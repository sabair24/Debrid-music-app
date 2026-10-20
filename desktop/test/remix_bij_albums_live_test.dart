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

/// METING (Saber, 20-10-2026: "dit staat ook vaak tussen albums ?? remixen enzo", bij Madonna).
/// Telt per artiest de tegels in het blok Albums, en wat het nakijken van de nummers verplaatst
/// (`DiscographyService.nakijken`, alleen wat alleen Deezer kent).
///
/// Draaien: `flutter test --run-skipped --tags live test/remix_bij_albums_live_test.dart`, met
/// `ARTIESTEN=Madonna,Kylie Minogue` om er een paar te kiezen en `SPOOR=deeper and deeper,rain` om te zien
/// waar een titel terechtkomt.
void main() {
  setUpAll(() async {
    HttpOverrides.global = null;
    await initAppPaths();
  });

  test('METING: remixuitgaven tussen de albums', () async {
    final s = AppSettings();
    await s.load();
    final svc = DiscographyService(CatalogService(), MusicBrainzService(), DiscogsService(s));
    final artiesten = (Platform.environment['ARTIESTEN'] ??
            'Madonna,Kylie Minogue,Britney Spears,Céline Dion,Michael Jackson,Faithless')
        .split(',');
    final spoor = (Platform.environment['SPOOR'] ?? '').split(',').where((x) => x.isNotEmpty).toSet();
    for (final naam in artiesten) {
      final dz = await svc.vanDeezer(naam);
      final mb = await svc.vanMusicBrainz(naam);
      final dg = await svc.vanDiscogs(naam);
      final samen = mergeDiscography([dz.releases, mb.releases, dg.releases]);
      final nagekeken = await svc.nakijken(naam, samen);
      // Zoals de artiestpagina: nagekeken, zonder gasten, en gevouwen (bevriesDiscografie).
      final na = vouwHeruitgaves([
        for (final r in samen)
          if (!nagekeken.gasten.contains(r.key))
            metNagekekenSoort(r, singles: nagekeken.maxisingles, remixen: nagekeken.remixAlbums),
      ]);
      final albums = na.where((r) => r.blok == RecordKind.album).toList()
        ..sort((a, b) => (a.firstDate ?? '').compareTo(b.firstDate ?? ''));
      String titels(Set<int> ids) =>
          [for (final r in samen) if (ids.contains(r.refs[DiscoSource.deezer]?.intId)) r.title].join(', ');
      final alleenDz = samen.where((r) => r.sources.length == 1 && r.sources.contains(DiscoSource.deezer)).length;
      // ignore: avoid_print
      print('$naam: Deezer ${dz.releases.length} | ${albums.length} albums | '
          '${na.where((r) => r.blok == RecordKind.remix).length} remixen | $alleenDz alleen-Deezer nagekeken');
      // ignore: avoid_print
      print('   naar singles: ${titels(nagekeken.maxisingles)}');
      // ignore: avoid_print
      print('   naar remixen (nummers): ${titels(nagekeken.remixAlbums)}');
      for (final r in samen) {
        if (!spoor.contains(r.key)) continue;
        // ignore: avoid_print
        print('   SPOOR "${r.title}" ${r.kind.name} ${r.sources.map((x) => x.name).join('+')} '
            'dz=${r.refs[DiscoSource.deezer]?.id}');
      }
      // ignore: avoid_print
      print('   albums: ${albums.map((r) => '${r.title} ${r.year ?? '?'}').join(' | ')}');
      // ignore: avoid_print
      print('   uitgaven: ${na.where((r) => r.blok == RecordKind.albumVersie).map((r) => r.title).join(' | ')}');
    }
  }, timeout: const Timeout(Duration(minutes: 25)));
}

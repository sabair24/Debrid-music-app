@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/discography.dart';
import 'package:debridmusic/discography_service.dart';
import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

/// De andere helft van de discografie: de échte netwerkpaden. Buiten de gewone run gehouden.
///
/// `discography_test.dart` toetst het samenvoegen en sorteren zonder netwerk, en dat is waar de
/// lastige beslissingen zitten. Maar het zegt niets over of Deezer, MusicBrainz en Discogs
/// daadwerkelijk antwoorden, of de naamcontrole een naamgenoot tegenhoudt, en of alle drie samen
/// méér opleveren dan één — en juist dat laatste is de reden dat deze functie er is.
///
/// Draaien: `flutter test --tags live test/discography_live_test.dart`
void main() {
  setUpAll(() async {
    HttpOverrides.global = null;
    await initAppPaths();
  });

  Future<DiscographyService> maak() async {
    final s = AppSettings();
    await s.load();
    return DiscographyService(CatalogService(), MusicBrainzService(), DiscogsService(s));
  }

  test('drie bronnen leveren samen meer dan Deezer alleen', () async {
    final svc = await maak();
    const naam = 'Michael Jackson';

    final dz = await svc.vanDeezer(naam);
    final mb = await svc.vanMusicBrainz(naam);
    final dg = await svc.vanDiscogs(naam);

    // ignore: avoid_print
    print('Deezer      ${dz.status.name}: ${dz.releases.length}');
    // ignore: avoid_print
    print('MusicBrainz ${mb.status.name}: ${mb.releases.length}');
    // ignore: avoid_print
    print('Discogs     ${dg.status.name}: ${dg.releases.length}');

    expect(dz.releases, isNotEmpty, reason: 'Deezer is de bron die het snelst moet antwoorden');
    expect(mb.releases, isNotEmpty, reason: 'discographyOf is één verzoek en heeft geen token nodig');

    final samen = mergeDiscography([dz.releases, mb.releases, dg.releases]);
    // ignore: avoid_print
    print('samengevoegd: ${samen.length}');
    for (final s in DiscoSource.values) {
      final alleen = samen.where((r) => r.sources.length == 1 && r.sources.contains(s)).length;
      // ignore: avoid_print
      print('${s.name}: kent ${samen.where((r) => r.sources.contains(s)).length}, '
          'alleen hij: $alleen');
    }

    expect(samen.length, greaterThan(dz.releases.length),
        reason: 'als samenvoegen niets toevoegt, is de hele feature zinloos');
    expect(samen.length, lessThan(dz.releases.length + mb.releases.length + dg.releases.length),
        reason: 'en als er niets samenvalt, dedupliceert discoKey niet');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('een plaat die twee bronnen kennen draagt twee merkjes en houdt zijn hoes', () async {
    final svc = await maak();
    final dz = await svc.vanDeezer('Michael Jackson');
    final mb = await svc.vanMusicBrainz('Michael Jackson');
    final samen = mergeDiscography([dz.releases, mb.releases]);

    final thriller = samen.where((r) => r.key == discoKey('Thriller')).firstOrNull;
    expect(thriller, isNotNull, reason: 'Thriller hoort in elke discografie van Michael Jackson');
    expect(thriller!.sources.length, greaterThan(1),
        reason: 'twee catalogi kennen deze plaat, dus twee merkjes');
    expect(thriller.cover, isNotNull,
        reason: 'MusicBrainz heeft geen hoes; die van Deezer moet het samenvoegen overleven');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('een naamgenoot wordt niet voor de gevraagde artiest aangezien', () async {
    // De rem op drie onafhankelijke resolvers. Een naam die niemand draagt hoort een LEGE lijst op te
    // leveren, niet de platen van wie er toevallig het dichtst bij zat.
    final svc = await maak();
    final uit = await svc.vanDeezer('Zzzqqxx Nietbestaandeartiest');
    expect(uit.releases, isEmpty);
    expect(uit.status, anyOf(BronStatus.klaar, BronStatus.andereArtiest));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('de cache leest terug wat erin ging', () async {
    final svc = await maak();
    final dz = await svc.vanDeezer('Daft Punk');
    expect(dz.releases, isNotEmpty);
    await svc.schrijf('Daft Punk', dz.releases);
    final terug = await svc.lees('Daft Punk');
    expect(terug, isNotNull);
    expect(terug!.releases.length, dz.releases.length);
    // De verwijzingen moeten de rondgang overleven, anders opent een regel uit de cache niets.
    expect(terug.releases.first.openRef, isNotNull);
    expect(terug.releases.first.sources, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

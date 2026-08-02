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
import 'package:debridmusic/release_format.dart';
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

  test('METING: hoeveel regels zijn leeg, en waar komen ze vandaan', () async {
    // Saber wees op Sia / "Titans": een regel zonder hoes en zonder tracklijst, die opent op een muur
    // credits van een soundtrack die niet eens van haar is. Deze meting zegt waar de grens moet liggen.
    final svc = await maak();
    const naam = 'Sia';
    final dz = await svc.vanDeezer(naam);
    final mb = await svc.vanMusicBrainz(naam);
    final dg = await svc.vanDiscogs(naam);
    final samen = mergeDiscography([dz.releases, mb.releases, dg.releases]);

    int tel(bool Function(DiscoRelease) p) => samen.where(p).length;
    // ignore: avoid_print
    print('totaal ${samen.length}');
    // ignore: avoid_print
    print('zonder hoes:            ${tel((r) => r.cover == null)}');
    // ignore: avoid_print
    print('zonder jaar:            ${tel((r) => r.firstDate == null)}');
    // ignore: avoid_print
    print('zonder hoes EN jaar:    ${tel((r) => r.cover == null && r.firstDate == null)}');
    // ignore: avoid_print
    print('alleen Discogs:         ${tel((r) => r.sources.length == 1 && r.sources.contains(DiscoSource.discogs))}');
    // ignore: avoid_print
    print('alleen Discogs, geen hoes: '
        '${tel((r) => r.sources.length == 1 && r.sources.contains(DiscoSource.discogs) && r.cover == null)}');
    // ignore: avoid_print
    print('soort "overig":         ${tel((r) => r.kind == RecordKind.other)}');
    for (final r in samen.where((r) => r.kind == RecordKind.other).take(20)) {
      // ignore: avoid_print
      print('  OVERIG: ${r.sources.map((s) => s.name).join(',')} | '
          '${r.firstDate ?? '—'} | ${r.cover == null ? 'geen hoes' : 'hoes'} | ${r.title}');
    }
    // En specifiek het geval dat Saber aanwees.
    for (final r in samen.where((r) => r.key.contains('titans'))) {
      // ignore: avoid_print
      print('  TITANS: ${r.sources.map((s) => s.name).join(',')} | ${r.kind.name} | '
          '${r.firstDate ?? '—'} | ${r.cover == null ? 'geen hoes' : 'hoes'} | '
          '${r.openRef?.source.name} | ${r.title}');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('METING: waar loopt Sia / "Titans" precies vast', () async {
    // De klacht was niet dat de REGEL leeg is — die klopt — maar wat je krijgt als je erop klikt:
    // een lege tracklijst met daarboven het label, het jaar en de credits van een andere plaat.
    // Deze meting scheidt de twee opzoekingen die AlbumBrowsePage doet, want ze zoeken anders: de
    // tracklijst op VERWIJZING, de uitgave-regel op TEKST.
    final svc = await maak();
    final s = AppSettings();
    await s.load();
    final mbSvc = MusicBrainzService();

    final mb = await svc.vanMusicBrainz('Sia');
    final rij = mb.releases.where((r) => r.key == discoKey('Titans')).firstOrNull;
    // ignore: avoid_print
    print('regel: ${rij == null ? "NIET GEVONDEN" : "${rij.title} | ${rij.kind.name} | "
        "${rij.firstDate} | ref=${rij.openRef?.source.name}:${rij.openRef?.id}"}');
    expect(rij, isNotNull, reason: 'zonder de regel valt er niets te openen en niets te meten');

    // 1. De weg die de tracklijst neemt: releasegroep → persingen → nummers.
    final persingen = await mbSvc.editionsOf(rij!.openRef!.id);
    // ignore: avoid_print
    print('persingen via editionsOf: ${persingen.length}');
    var nummers = 0;
    for (final p in MusicBrainzService.orderByPreference(persingen)) {
      // NIET `vol?.tracks.length ?? 0`: dat geeft nul zowel bij een lege tracklijst als bij een
      // aanroep die helemaal niets opleverde, en dat zijn twee verschillende reparaties.
      final vol = await mbSvc.release(p.mbid);
      // ignore: avoid_print
      print('persing ${p.mbid} (${p.format}/${p.country}): '
          '${vol == null ? "AANROEP LEVERDE NIETS" : "${vol.tracks.length} nummers, "
              "track-count zegt ${vol.trackCount}"}');
      if (vol != null && vol.tracks.isNotEmpty) nummers = vol.tracks.length;
    }

    // 2. De weg die de uitgave-regel neemt: artiest + titel als TEKST. Precies zoals de pagina hem
    //    aanriep — met expectedTracks 0, want die gaf hij altijd door.
    final dg = DiscogsService(s);
    if (dg.available) {
      final los = await dg.edition('Sia', 'Titans');
      // ignore: avoid_print
      print('Discogs op tekst, ZONDER aantal: ${los == null ? "niets" : "#${los.releaseId} "
          "${los.year} ${los.label} ${los.country} — ${los.tracklist.length} nummers"}');
      final met = await dg.edition('Sia', 'Titans', expectedTracks: 1);
      // ignore: avoid_print
      print('Discogs op tekst, MET aantal=1: ${met == null ? "niets" : "#${met.releaseId} "
          "${met.year} ${met.label} ${met.country} — ${met.tracklist.length} nummers"}');
    } else {
      // ignore: avoid_print
      print('Discogs: geen token — de tekstweg is hier niet te meten');
    }

    // ignore: avoid_print
    print(nummers == 0
        ? 'GEVOLG: lege tracklijst. De pagina mag dan geen uitgave-regel of credits tonen.'
        : 'GEVOLG: er IS een tracklijst ($nummers) — de pagina hoorde niet leeg te zijn.');

    // Dit is de reparatie: doorlopen tot er één persing nummers geeft, zoals
    // _loadMusicBrainzGroup nu doet. Stoppen bij de eerste is wat de pagina leeg maakte.
    expect(nummers, greaterThan(0),
        reason: 'de tweede persing draagt het nummer wel — de eerste overslaan is de hele fix');

    // En dit is de tweede helft: de tekstweg mag deze plaat niet beschrijven. Eén nummer tegen
    // negenentwintig valt buiten fitsTrackCount, in beide richtingen getoetst.
    expect(fitsTrackCount(29, nummers), isFalse,
        reason: 'een soundtrack van 29 nummers is niet de single waar je naar kijkt');
    // De ondergrens moet blijven werken zoals hij was: minder hebben dan de plaat lang is, is
    // normaal, en daar mag niets op afvallen.
    expect(fitsTrackCount(15, 15), isTrue);
    expect(fitsTrackCount(17, 15), isTrue, reason: 'bonusnummers zijn gewoon');
  }, timeout: const Timeout(Duration(minutes: 3)));

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

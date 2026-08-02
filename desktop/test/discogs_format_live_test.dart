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

/// De drie gaten die Saber aanwees, gemeten na de reparatie.
///
///   1. "Overig" zat vol echte singles — `/artists/{id}/releases` geeft een `type: master` GEEN
///      `format`-veld, dus die regels werden [RecordKind.other].
///   2. Veel regels zonder hoes — die komen van MusicBrainz, dat er op releasegroep-niveau nooit
///      een levert, en de Cover Art Archive daar ook niet (gemeten: 0 van 25).
///   3. "Pavarotti & Friends" tussen de albums van Enrique Iglesias — Deezers albumlijst noemt de
///      hoofdartiest niet, dus een gastoptreden was niet te onderscheiden van eigen werk.
///
/// Deze meting draait de echte weg af en zegt wat er nog over is. Geen mooie getallen: als de
/// reparatie half werkt, hoort dat hier te staan.
void main() {
  setUpAll(() async {
    HttpOverrides.global = null;
    await initAppPaths();
  });

  Future<(DiscographyService, DiscogsService)> maak() async {
    final s = AppSettings();
    await s.load();
    final dg = DiscogsService(s);
    return (DiscographyService(CatalogService(), MusicBrainzService(), dg), dg);
  }

  Future<List<DiscoRelease>> discografie(DiscographyService svc, String naam,
      {bool weerGasten = true}) async {
    final dz = await svc.vanDeezer(naam);
    final mb = await svc.vanMusicBrainz(naam);
    final dg = await svc.vanDiscogs(naam);
    var alles = vulHoezenAan(mergeDiscography([dz.releases, mb.releases, dg.releases]), dg.hoezen);
    if (weerGasten) {
      final gasten = await svc.gastoptredens(naam, alles);
      // ignore: avoid_print
      print('  gastoptredens geweerd: ${gasten.length}');
      alles = alles.where((r) => !gasten.contains(r.key)).toList();
    }
    return alles;
  }

  test('METING: hoeveel staat er nog in Overig, en hoeveel mist een hoes', () async {
    final (svc, _) = await maak();
    for (final naam in ['Sia', 'Céline Dion']) {
      final alles = await discografie(svc, naam, weerGasten: false);
      final overig = alles.where((r) => r.blok == RecordKind.other).length;
      final zonder = alles.where((r) => r.cover == null || r.cover!.isEmpty).length;
      // ignore: avoid_print
      print('$naam: ${alles.length} regels — Overig $overig '
          '(${(100 * overig / alles.length).round()}%), zonder hoes $zonder '
          '(${(100 * zonder / alles.length).round()}%)');
      for (final blok in inBlokken(alles, DiscoSort.datum, const {})) {
        // ignore: avoid_print
        print('   ${blokTitel(blok.soort)}: ${blok.rijen.length}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 8)));

  test('METING: is Pavarotti & Friends weg bij Enrique Iglesias', () async {
    final (svc, _) = await maak();
    const naam = 'Enrique Iglesias';
    final zonder = await discografie(svc, naam, weerGasten: false);
    final met = await discografie(svc, naam);

    bool pav(DiscoRelease r) => r.key.contains('pavarotti');
    // ignore: avoid_print
    print('vóór weren: ${zonder.length} regels, Pavarotti aanwezig: ${zonder.any(pav)}');
    // ignore: avoid_print
    print('ná weren:   ${met.length} regels, Pavarotti aanwezig: ${met.any(pav)}');
    for (final r in zonder.where((z) => !met.any((m) => m.key == z.key))) {
      // ignore: avoid_print
      print('   geweerd: ${r.kind.name} | ${r.firstDate ?? "—"} | ${r.title}');
    }

    expect(zonder.any(pav), isTrue, reason: 'zonder de controle hoort hij er nog te staan');
    expect(met.any(pav), isFalse, reason: 'dit is precies wat Saber aanwees');
    // En de eigen platen moeten blijven staan: een filter dat te veel weghaalt is erger.
    expect(met.any((r) => r.key == discoKey('Euphoria')), isTrue);
    expect(met.any((r) => r.key == discoKey('Escape')), isTrue);
  }, timeout: const Timeout(Duration(minutes: 8)));
}

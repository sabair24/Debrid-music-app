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

  test('METING: wat de zeef weglaat, en wat er van de Albums overblijft', () async {
    // Het getal waar deze hele ronde om draait. Saber zag 44 "albums" van Michael Jackson waarvan de
    // helft live-uitzendingen en tributes waren; de vraag is niet of de code compileert maar hoeveel
    // er wegvalt en of de ECHTE platen blijven staan.
    final (svc, _) = await maak();
    for (final naam in ['Michael Jackson', 'Sia', 'Céline Dion']) {
      final ruw = await discografie(svc, naam, weerGasten: false);
      final samen = vouwHeruitgaves(ruw);
      final zeef = zeefDiscografie(samen);
      // ignore: avoid_print
      print('$naam: ${ruw.length} regels → ${zeef.rijen.length} zichtbaar '
          '(${zeef.verborgen} verborgen: ${zeef.zonderHoes} zonder hoes, '
          '${zeef.perSoort.entries.map((e) => '${e.value} ${blokTitel(e.key).toLowerCase()}').join(', ')})');
      // Hoe scherp de hoezen zijn, want dat was de volgende klacht. Discogs' `thumb` is 150×150 op
      // kwaliteit 40 en zijn `cover_image` 600×601 op kwaliteit 90; Deezer levert altijd 500×500.
      final maten = <String, int>{};
      for (final r in zeef.rijen) {
        final c = r.cover ?? '';
        final w = RegExp(r'/w:(\d+)/').firstMatch(c)?.group(1);
        final dz = RegExp(r'/(\d+)x\d+-').firstMatch(c)?.group(1);
        final k = w != null ? 'discogs ${w}px' : (dz != null ? 'deezer ${dz}px' : 'anders');
        maten[k] = (maten[k] ?? 0) + 1;
      }
      // ignore: avoid_print
      print('   hoezen: ${(maten.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => '${e.value} ${e.key}').join(' · ')}');
      for (final blok in inBlokken(zeef.rijen, DiscoSort.datumOud, const {})) {
        // ignore: avoid_print
        print('   ${blokTitel(blok.soort)}: ${blok.rijen.length}');
      }
      for (final blok in inBlokken(zeef.rijen, DiscoSort.datumOud, const {})) {
        if (blok.soort != RecordKind.album) continue;
        for (final r in blok.rijen) {
          // ignore: avoid_print
          print('      ${r.year ?? '----'}  ${r.title}');
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 12)));

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

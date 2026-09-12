/// Een catalogus die deze plaat niet kent, wordt niet bij élke verversing opnieuw bevraagd.
///
/// **Waarom dit er is.** Saber op 12-09-2026: "er moet ook wat worden gedaan aan de refresh snelheid
/// van de metadata op alle platformen, dat duurt allemaal te lang". Gemeten in `warm.log` van die
/// dag: het uitzoeken van de plaat zelf kostte mediaan 84 ms, maar in één veeg over de bibliotheek
/// stond zesennegentig keer "theaudiodb: GEEN ANTWOORD" — acht seconden tijdslimiet plus drie
/// seconden pauze, telkens opnieuw, want alleen een GEVONDEN antwoord werd bewaard.
///
/// Daarom telt deze toets de VERZOEKEN. Aan het antwoord alleen is niet te zien of er een verzoek
/// uitging, en juist dat is wat tijd kost.
library;

import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/enrichment.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory map;

  setUp(() {
    map = Directory.systemTemp.createTempSync('albuminfo_');
    setAppDirForTest(map.path);
  });

  tearDown(() {
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  List<File> briefjes() {
    final d = Directory('${map.path}${Platform.pathSeparator}albuminfo');
    if (!d.existsSync()) return const [];
    return [for (final f in d.listSync()) if (f is File && f.path.endsWith('.none')) f];
  }

  void verouder(Duration d) {
    for (final f in briefjes()) {
      f.setLastModifiedSync(DateTime.now().subtract(d));
    }
  }

  test('DE KERN: een plaat die de catalogus niet kent, wordt niet opnieuw opgevraagd', () async {
    var verzoeken = 0;
    final enricher = CoverEnricher(AppSettings(), client: MockClient((_) async {
      verzoeken++;
      return http.Response(jsonEncode({'album': null}), 200);
    }));

    expect(await enricher.albumInfo('Camille', 'The Sound of Milk'), isNull);
    expect(verzoeken, 1);

    expect(await enricher.albumInfo('Camille', 'The Sound of Milk'), isNull);
    expect(verzoeken, 1,
        reason: 'elke verversing wachtte opnieuw op een bron die deze plaat niet kent');
  });

  test('DE VAL: een bron die alleen stil bleef, wordt na een dag gewoon weer geprobeerd', () async {
    var verzoeken = 0;
    final enricher = CoverEnricher(AppSettings(), client: MockClient((_) async {
      verzoeken++;
      return http.Response('', 503);
    }));

    expect(await enricher.albumInfo('Camille', 'The Sound of Milk'), isNull);
    expect(verzoeken, 1);
    expect(await enricher.albumInfoGezochtEnLeeg('Camille', 'The Sound of Milk'), isTrue);

    // Een storing van gisteren zegt niets over deze plaat. Twee dagen later hoort hij het opnieuw
    // te proberen — anders kost één slechte minuut veertien dagen blindheid.
    verouder(const Duration(days: 2));
    expect(await enricher.albumInfoGezochtEnLeeg('Camille', 'The Sound of Milk'), isFalse);
  });

  test('DE GRENS: "die plaat kennen we niet" houdt wél veertien dagen', () async {
    final enricher = CoverEnricher(AppSettings(),
        client: MockClient((_) async => http.Response(jsonEncode({'album': []}), 200)));

    expect(await enricher.albumInfo('Camille', 'The Sound of Milk'), isNull);
    verouder(const Duration(days: 2));
    expect(await enricher.albumInfoGezochtEnLeeg('Camille', 'The Sound of Milk'), isTrue);
    verouder(const Duration(days: 20));
    expect(await enricher.albumInfoGezochtEnLeeg('Camille', 'The Sound of Milk'), isFalse,
        reason: 'catalogi krijgen er platen bij; voorgoed zwijgen hoort niet');
  });

  test('DE GRENS: een gevonden antwoord haalt het briefje weg', () async {
    final enricher = CoverEnricher(AppSettings(),
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'album': [
                {'strAlbum': 'The Sound of Milk', 'strDescription': 'Een plaat van Camille.'},
              ],
            }),
            200)));

    await enricher.onthoudGeenAlbumInfo('Camille', 'The Sound of Milk');
    expect(briefjes(), hasLength(1));
    verouder(const Duration(days: 20));

    expect(await enricher.albumInfo('Camille', 'The Sound of Milk'), isNotNull);
    expect(briefjes(), isEmpty,
        reason: 'een oud "niets" bleef naast een gevonden antwoord staan');
  });
}

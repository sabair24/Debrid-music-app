library;

import 'dart:io';

import 'package:debridmusic/rutracker.dart';
import 'package:debridmusic/search.dart';
import 'package:debridmusic/torbox.dart';
import 'package:flutter_test/flutter_test.dart';

/// **GEMETEN OP 13-09-2026.** In de app, na een verse Cloudflare-doorgang en met een curl die het
/// buiten de app wél deed, stond er op het scherm:
///
///     RuTracker deed niet mee - RuTracker was na elf seconden nog bezig; het zoeken wacht niet langer.
///
/// Er lagen DRIE kappen boven elkaar, en alle drie onder de tijd die RuTracker die dag nodig had:
///
///   | waar                 | stond op |
///   |----------------------|----------|
///   | curl `--max-time`    | 20 s     |
///   | `RuTrackerSource`    | 11 s     |
///   | `SearchAggregator`   | 12 s     |
///
/// De opdeling van een enkel verzoek dezelfde dag laat zien dat het de server zelf is - niet de
/// lijn, niet de uitdaging:
///
///     dns 0,03 s | verbinden 0,04 s | tls 0,08 s | EERSTE BYTE 21,0 s | totaal 21,3 s
///
/// Alleen de onderste ophogen zag eruit als een fix en veranderde niets: de twee erboven kapten het
/// alsnog af. Daarom houdt deze toets ze alle drie vast, en houdt hij ook de VOLGORDE vast - de
/// eigen tijdslimiet van RuTracker moet onder zijn kap bij de verdeler blijven, anders leest het
/// scherm "te traag" in plaats van de zin die uitlegt wat er aan de hand is.

/// Een bron die precies zo lang doet als de toets wil, met zijn eigen kap.
class _Traag extends SearchSource {
  _Traag(this.id, {required this.werk, Duration? kap}) : _kap = kap;
  @override
  final String id;
  final Duration werk;
  final Duration? _kap;

  @override
  Duration get kap => _kap ?? super.kap;

  @override
  Future<List<SearchResult>> search(String query) async {
    await Future.delayed(werk);
    return [
      SearchResult(
        name: 'Michael Jackson - Thriller [1982] FLAC',
        hash: '0123456789abcdef0123456789abcdef${id.hashCode.abs()}',
        magnet: 'magnet:?xt=urn:btih:$id',
        seeders: 7,
      ),
    ];
  }
}

/// Het stuk brontekst van RuTrackerSource, waar de twee getallen in staan.
String _rutrackerBlok() {
  final bron = File('lib/search.dart').readAsStringSync();
  final begin = bron.indexOf('class RuTrackerSource');
  expect(begin, greaterThan(0), reason: 'RuTrackerSource bestaat niet meer onder deze naam');
  final eind = bron.indexOf('\nclass ', begin + 1);
  return bron.substring(begin, eind == -1 ? bron.length : eind);
}

int _getal(String blok, RegExp patroon, String wat) {
  final m = patroon.firstMatch(blok);
  expect(m, isNotNull, reason: '$wat staat niet meer in RuTrackerSource');
  return int.parse(m!.group(1)!);
}

void main() {
  group('elke bron zijn eigen kap', () {
    test('DE KERN: de verdeler wacht de kap van de bron zelf af', () async {
      final verdeler = SearchAggregator([
        _Traag('ruim', werk: const Duration(milliseconds: 200), kap: const Duration(seconds: 5)),
        _Traag('krap', werk: const Duration(milliseconds: 2500), kap: const Duration(seconds: 1)),
      ]);

      final uit = await verdeler.search('thriller');

      // Met een vast getal voor alle bronnen (twaalf seconden) zou 'krap' er gewoon door komen.
      expect(verdeler.standen['ruim']!.aantal, 1, reason: 'de ruime bron hoort mee te tellen');
      expect(verdeler.standen['krap']!.aantal, -1, reason: 'de krappe bron hoort eruit te vallen');
      expect(verdeler.standen['krap']!.fout, 'te traag (1 s)',
          reason: 'de melding hoort de kap van DIE bron te noemen, niet een vast getal');
      expect(uit.length, 1);
    });

    test('DE VAL: de vijf limieten lopen op, en alle vijf boven de gemeten eenentwintig', () {
      final blok = _rutrackerBlok();
      final bron = _getal(blok,
          RegExp(r'\.timeout\(const Duration\(seconds: (\d+)\)\)'), 'de eigen limiet van de bron');
      final kap = _getal(blok,
          RegExp(r'Duration get kap => const Duration\(seconds: (\d+)\)'), 'de kap');

      final ladder = <String, int>{
        'curl per verzoek': RuTrackerService.kCurlSeconden,
        'het proces om curl heen': RuTrackerService.kProcesSeconden,
        'het budget voor een hele zoekopdracht': RuTrackerService.kZoekSeconden,
        'deze bron': bron,
        'de kap van de verdeler': kap,
      };

      // Alle vijf boven de tijd die RuTracker op 13-09-2026 nodig had. Eentje eronder is genoeg om
      // de hele bron stil te laten wegvallen, en dat is precies wat er tien uitleveringen lang
      // gebeurde.
      ladder.forEach((wat, s) {
        expect(s, greaterThan(21),
            reason: '$wat staat op $s s; RuTracker deed er die dag 21 over');
      });

      // En ze moeten in de goede volgorde oplopen: wie het EERST afkapt bepaalt wat je op het
      // scherm leest. Kapt de verdeler het eerst af, dan staat er "te traag" en weet je niets.
      expect(RuTrackerService.kProcesSeconden, greaterThan(RuTrackerService.kCurlSeconden),
          reason: 'anders wordt curl onder zijn eigen limiet vandaan getrokken');
      expect(RuTrackerService.kZoekSeconden,
          greaterThanOrEqualTo(RuTrackerService.kCurlSeconden),
          reason: 'een enkel verzoek mag niet langer mogen duren dan de hele zoekopdracht');
      expect(bron, greaterThan(RuTrackerService.kZoekSeconden),
          reason: 'anders leest het scherm "nog bezig" terwijl het zoekbudget het echte probleem is');
      expect(kap, greaterThan(bron),
          reason: 'anders leest het scherm "te traag" in plaats van de zin die zegt wat er mis is');
    });

    // Het zoekbudget dekt TWEE rondes, geen een: eerst de lijst, dan de topicpagina's waar de
    // infohashes in staan. Gemeten op 13-09-2026 met het koekje van de app: de lijst 20,6 s, een
    // topicpagina uit de cache 0,15 s, een topicpagina die opgehaald moest worden 20,5 s.
    test('DE VAL: het zoekbudget dekt de lijst EN de topicpagina\'s', () {
      expect(RuTrackerService.kZoekSeconden, greaterThan(21 * 2 - 4),
          reason: 'met te weinig is het budget al op voordat de lijst binnen is, en dan komt er van '
              'geen enkele rij een infohash - op het scherm achtenvijftig rijen en nul torrents');
    });

    test('DE GRENS: een bron die niets zegt houdt de korte kap', () {
      final gewoon = _Traag('gewoon', werk: Duration.zero);
      expect(gewoon.kap, const Duration(seconds: 12),
          reason: 'een snelle indexer hoort niet mee omhoog te gaan met RuTracker');
    });
  });
}

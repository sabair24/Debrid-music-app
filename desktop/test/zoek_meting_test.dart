/// De meetbank voor het zoeken.
///
/// De gebruiker meldt "zoeken is traag", en er stond nergens een meting. Dit is die meting.
///
/// Wat er per toetsaanslag gebeurt, uit de code gelezen: er is geen debounce, dus élke letter draait
/// een volledige pass over de bibliotheek. Per nummer wordt de ZOEKTERM opnieuw genormaliseerd, en
/// [normKey] bouwt vijf RegExp-objecten per aanroep omdat die in de functie-body staan in plaats van
/// als top-level `final`. Bij 707 nummers komt dat op ongeveer 17.000 verse RegExp's per letter.
///
/// De grens die telt: één beeldje is 16,7 ms op 60 Hz. Blijft een pass daaronder, dan voelt typen
/// direct; erboven mist hij beelden en zie je de letters achterlopen.
///
/// Draaien:  flutter test test/zoek_meting_test.dart --reporter expanded
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/organize.dart';
import 'package:debridmusic/quality.dart';

/// Zoals de bibliotheek er hier uitziet: 707 nummers, 236 albums.
const aantalNummers = 707;

List<({String titel, String artiest, String album})> _bibliotheek() => [
      for (var i = 0; i < aantalNummers; i++)
        (
          titel: 'Nummer $i — Beyoncé’s Café ${i % 7}',
          artiest: 'Artiest ${i % 120}',
          album: 'Album ${i % 236} (Remastered 20${10 + i % 15})',
        ),
    ];

/// Precies wat `_matches` in main.dart doet voor één nummer dat NIET matcht: vier keer normKey
/// (zoekterm + titel + artiest + album) en vier keer searchKey.
bool _raakt(String q, ({String titel, String artiest, String album}) t) {
  final nq = normKey(q);
  if (normKey(t.titel).contains(nq)) return true;
  if (normKey(t.artiest).contains(nq)) return true;
  if (normKey(t.album).contains(nq)) return true;
  final sq = searchKey(q);
  if (searchKey(t.titel).contains(sq)) return true;
  if (searchKey(t.artiest).contains(sq)) return true;
  if (searchKey(t.album).contains(sq)) return true;
  return false;
}

/// Wat `_matches` NU doet: de zoekterm is al genormaliseerd (één keer, in `_leggenZoekterm`), en het
/// kwaliteitsfilter is overgeslagen omdat de pil op "Alles" staat.
bool _raaktNa(String nq, String nqs, ({String titel, String artiest, String album}) t) {
  if (normKey(t.titel).contains(nq)) return true;
  if (normKey(t.artiest).contains(nq)) return true;
  if (normKey(t.album).contains(nq)) return true;
  if (nqs.isEmpty) return false;
  if (searchKey(t.titel).contains(nqs)) return true;
  if (searchKey(t.artiest).contains(nqs)) return true;
  if (searchKey(t.album).contains(nqs)) return true;
  return false;
}

int _meet(String naam, void Function() werk) {
  werk(); // één keer warmdraaien, zodat de JIT niet meegemeten wordt
  final klok = Stopwatch()..start();
  werk();
  final us = klok.elapsedMicroseconds;
  // ignore: avoid_print
  print('  ${naam.padRight(46)}${(us / 1000).toStringAsFixed(2).padLeft(8)} ms'
      '${us > 16700 ? "   <- mist een beeldje op 60 Hz" : ""}');
  return us;
}

void main() {
  final lib = _bibliotheek();

  test('wat één toetsaanslag kost', () {
    // ignore: avoid_print
    print('\n── één pass over $aantalNummers nummers ──');
    _meet('typen van "b"', () {
      for (final t in lib) {
        _raakt('b', t);
      }
    });
    _meet('typen van "backstreet"', () {
      for (final t in lib) {
        _raakt('backstreet', t);
      }
    });

    // ignore: avoid_print
    print('\n── de bouwstenen, los ──');
    _meet('normKey  × $aantalNummers', () {
      for (var i = 0; i < aantalNummers; i++) {
        normKey('Beyoncé’s Café — Remastered');
      }
    });
    _meet('searchKey × $aantalNummers', () {
      for (var i = 0; i < aantalNummers; i++) {
        searchKey('Beyoncé’s Café — Remastered');
      }
    });

    // ignore: avoid_print
    print('\n── het kwaliteitsfilter, dat OOK draait als de pil op "Alles" staat ──');
    _meet('qualityFromFile × $aantalNummers', () {
      for (var i = 0; i < aantalNummers; i++) {
        qualityFromFile(
          name: 'Nummer $i — Beyoncé’s Café',
          ext: 'flac',
          isFlac: true,
          durationSec: 210,
          size: 30000000,
        );
      }
    });

    // ignore: avoid_print
    print('\n── het hele woord uittypen: "backstreet", 10 letters ──');
    final woord = 'backstreet';
    _meet('ZONDER debounce: 10 volle passes', () {
      for (var n = 1; n <= woord.length; n++) {
        final q = woord.substring(0, n);
        for (final t in lib) {
          _raakt(q, t);
        }
      }
    });
    _meet('MET debounce + zoekterm één keer: 1 pass', () {
      final nq = normKey(woord);
      final nqs = searchKey(woord);
      for (final t in lib) {
        _raaktNa(nq, nqs, t);
      }
    });
  });

  test('normaliseren blijft doen wat het deed', () {
    // De snelheidsreparatie mag de uitkomst niet veranderen. Dit zijn de gevallen waar normKey en
    // searchKey voor bestaan.
    //
    // **Eén uitkomst is sinds 05-09-2026 wél veranderd, en met opzet.** Hier stond
    // 'backstreet s back': elk leesteken werd een spatie, ook de apostrof, terwijl die juist MIDDEN
    // in een woord staat. Daardoor stond "Driver's Seed" naast "Drivers Seed" in de artiestenlijst
    // als twee acts. `searchKey` hieronder deed het al goed -- die geeft 'backstreetsback' -- dus
    // deze regel haalt normKey bij zijn buurman, in plaats van er iets nieuws te bedenken.
    expect(normKey('Backstreet’s Back'), 'backstreets back');
    expect(normKey('Beyoncé'), 'beyonce');
    expect(normKey('A—B'), 'a b');
    expect(normKey('  dubbele   spaties  '), 'dubbele spaties');
    expect(normKey('“Quoted”'), 'quoted');
    expect(searchKey("Backstreet's Back"), 'backstreetsback');
    expect(searchKey('Beyoncé'), 'beyonc', reason: 'searchKey vouwt geen accenten — ongewijzigd');
  });
}

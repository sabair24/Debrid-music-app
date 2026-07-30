/// Tekst repareren die één keer te veel gecodeerd is.
library;

import 'dart:convert';

/// De 27 tekens die Windows-1252 in het bereik 0x80-0x9F heeft en latin1 niet.
///
/// Dit bereik is precies waarom de reparatie een tabel nodig heeft: een verminkte ’ bestaat uit
/// `â`, `€` en `™`, en die laatste twee bestaan alleen in cp1252. Met latin1 alleen zou de weg terug
/// halverwege stranden.
const _cp1252 = {
  0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85,
  0x2020: 0x86, 0x2021: 0x87, 0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A,
  0x2039: 0x8B, 0x0152: 0x8C, 0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92,
  0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97,
  0x02DC: 0x98, 0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B, 0x0153: 0x9C,
  0x017E: 0x9E, 0x0178: 0x9F,
};

/// Hoeveel titels de reparatie deze sessie heeft rechtgezet.
///
/// Staat hier zodat het aantal in het log kan: als dit getal bij een verse bibliotheek boven nul
/// blijft komen, dan schrijft iets nog steeds verminkte tekst weg en is de reparatie een pleister
/// over een lek. Bij oude data hoort het één keer op te lopen en daarna nul te blijven.
int mojibakeHersteld = 0;

/// Maak van "Nobodyâ€™s Business" weer "Nobody’s Business".
///
/// Een ’ is in UTF-8 de bytereeks E2 80 99. Wordt die als cp1252 gelezen en daarna weer als UTF-8
/// weggeschreven, dan staan er drie tekens waar er één hoorde. De weg terug is exact: schrijf de
/// tekens terug naar hun cp1252-byte en lees die bytes als UTF-8.
///
/// Gemeten in de eigen bibliotheek: 124 van zulke reeksen in album_facts.json, over 41 albums, terwijl
/// de caches van MusicBrainz en Discogs schoon waren -- daar stond `TEXAS HOLD ’EM` gewoon goed.
///
/// Drie voorwaarden voordat er iets verandert, want een verkeerde "reparatie" van een echte Franse
/// titel is erger dan de kwaal:
///  * elk teken moet naar één byte terug kunnen (anders was het geen cp1252-misser);
///  * die bytes moeten SAMEN geldige UTF-8 zijn, zonder toegeeflijkheid;
///  * het resultaat moet korter zijn, want dubbele codering maakt tekst altijd langer.
///
/// Een gewone accentletter valt bij de tweede voorwaarde af: "café" wordt E9 als losse byte, en dat
/// is geen geldige UTF-8-reeks, dus de tekst blijft ongemoeid.
String unmojibake(String s) {
  var verdacht = false;
  final bytes = <int>[];
  for (final r in s.runes) {
    if (r < 0x80) {
      bytes.add(r);
      continue;
    }
    verdacht = true;
    if (r < 0x100) {
      bytes.add(r);
      continue;
    }
    final b = _cp1252[r];
    if (b == null) return s; // geen cp1252-teken: dit was nooit een misdecodering
    bytes.add(b);
  }
  if (!verdacht) return s;
  try {
    final terug = utf8.decode(bytes); // niet toegeeflijk: half geldig is niet geldig
    if (terug.runes.length >= s.runes.length) return s;
    mojibakeHersteld++;
    return terug;
  } catch (_) {
    return s;
  }
}

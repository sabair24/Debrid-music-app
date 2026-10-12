/// Hoe groot een scan is, in pixels — zonder hem helemaal op te halen.
///
/// **Waarom dit er is.** Saber op 04-10-2026, bij "Uitgave kiezen": *"ik wil graag de resolutie groter
/// zien, nu moet ik blind kiezen zonder ik weet welke resolutie het is."* De hoes van de uitgave die je
/// kiest wordt je albumhoes, en de kiezer liet per uitgave drie miniaturen van 58 punten zien — of de
/// scan erachter 600 of 3000 pixels breed is, stond nergens.
///
/// Discogs geeft de afmetingen zelf mee (zie [ChoiceImage.breedte]); de Cover Art Archive van
/// MusicBrainz niet. Daarvoor haalt dit de eerste 64 kB van het bestand op en leest de maat uit de kop
/// ([imageSize] in booklet.dart). Staat de maat daar niet in — een JPEG met een groot ingesloten
/// voorbeeldje vooraan — dan nog één keer tot een megabyte. Nooit het hele bestand op hoop van zegen.
///
/// **En waarom hij soms ontbrak.** Saber op 12-10-2026: *"resolutie staat ook niet altijd vermeld"*.
/// Gemeten bij Thriller: van twintig scans gaf archive.org er drie tot acht een 500 of 502 terug, na
/// 0,4 tot 11 seconden. Die "nee" bleef de hele sessie staan, ook al gaf dezelfde scan een paar tellen
/// later gewoon zijn maat. Nu wordt een tijdelijke fout opnieuw geprobeerd ([kScanMaatPogingen]), en
/// blijft wat gemeten is op schijf ([bewaarScanmatenIn]) — een scan verandert nooit van maat.
///
/// Minder tegelijk vragen hielp NIET, en dat is ook gemeten: 24 scans met hooguit 4 tegelijk gaven 4
/// fouten en duurden 40 s, met 8 tegelijk 6 fouten en 25 s, alle 24 tegelijk 1 fout en 6 s. De fouten
/// hangen aan het archief, niet aan de drukte. [kScanMaatTegelijk] is er alleen als rem voor wie snel
/// door een lijst van honderden persingen bladert.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import 'booklet.dart' show imageSize;
import 'editions.dart' show ChoiceImage;

typedef Maat = ({int w, int h});

final Map<String, Future<Maat?>> _maten = {};

/// Hoeveel scans er hooguit tegelijk gemeten worden. Ruim genoeg voor alles wat er op één scherm staat
/// (acht rijen van drie); zie de uitleg bovenaan waarom dit niet lager hoeft.
const kScanMaatTegelijk = 24;

/// Hoe vaak een meting geprobeerd wordt als de server "straks" bedoelt (5xx, 429, een time-out of een
/// weggevallen verbinding). Een 404 of een bestand zonder leesbare kop is een antwoord en wordt niet
/// herhaald.
const kScanMaatPogingen = 3;

/// Hoeveel gemeten maten er op schijf bewaard blijven. Een regel is zo'n honderd bytes.
const kScanmatenBewaard = 4000;

/// Hoe er gewacht wordt tussen twee pogingen. Een toets zet hier een klok zonder wachten neer.
@visibleForTesting
Future<void> Function(Duration) scanMaatWacht = Future<void>.delayed;

/// De maat van [img]: meteen als de catalogus hem gaf, anders uit de kop van de scan. Null als het niet
/// te zeggen valt — en dan zegt het scherm niets, liever dan een getal te verzinnen.
///
/// Een [ChoiceImage.alleenMiniatuur] wordt NIET gemeten: zijn [ChoiceImage.uri] is het miniatuur van 150
/// pixels zelf, en "150×150" zou over de echte scan liegen.
Future<Maat?> scanMaatVan(ChoiceImage img, {http.Client? client}) {
  if (img.breedte > 0 && img.hoogte > 0) return Future.value((w: img.breedte, h: img.hoogte));
  if (img.alleenMiniatuur || img.uri.isEmpty) return Future.value(null);
  return _maten[img.uri] ??= _meet(img.uri, client);
}

/// Wat er al bekend is, zonder te wachten — voor de eerste tekening.
Maat? bekendeMaat(ChoiceImage img) =>
    img.breedte > 0 && img.hoogte > 0 ? (w: img.breedte, h: img.hoogte) : null;

Future<Maat?> _meet(String url, http.Client? client) async {
  final bewaard = (await _schijf())[url];
  if (bewaard != null) return bewaard;
  for (var poging = 1;; poging++) {
    await _beurt();
    final ({Maat? maat, bool opnieuw}) r;
    try {
      r = await _haal(url, client);
    } finally {
      _vrij();
    }
    final m = r.maat;
    if (m != null) {
      _onthoud(url, m);
      return m;
    }
    if (!r.opnieuw) return null;
    if (poging >= kScanMaatPogingen) {
      // Geen uitspraak over de scan, alleen over dit moment: de volgende tekening mag het opnieuw vragen.
      _maten.remove(url);
      return null;
    }
    await scanMaatWacht(Duration(seconds: poging));
  }
}

/// Eén poging. [opnieuw] zegt of een nieuwe poging zin heeft.
Future<({Maat? maat, bool opnieuw})> _haal(String url, http.Client? gegeven) async {
  final client = gegeven ?? http.Client();
  try {
    for (final eind in const [65535, 1048575]) {
      final r = await client
          .get(Uri.parse(url), headers: {'Range': 'bytes=0-$eind'}).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200 && r.statusCode != 206) {
        final s = r.statusCode;
        return (maat: null, opnieuw: s == 408 || s == 429 || s >= 500);
      }
      final m = imageSize(r.bodyBytes);
      if (m != null && m.w > 0 && m.h > 0) return (maat: m, opnieuw: false);
      // Het hele bestand kwam al (de server negeerde de reeks, of het is klein): verder zoeken heeft
      // geen zin.
      if (r.statusCode == 200 || r.bodyBytes.length <= eind) return (maat: null, opnieuw: false);
    }
    return (maat: null, opnieuw: false);
  } catch (_) {
    // Een netwerkhik of een time-out is geen uitspraak over de scan.
    return (maat: null, opnieuw: true);
  } finally {
    if (gegeven == null) client.close();
  }
}

// ── Hooguit [kScanMaatTegelijk] tegelijk ────────────────────────────────────────────────────────────

var _bezig = 0;
final _wachtenden = <Completer<void>>[];

Future<void> _beurt() async {
  if (_bezig < kScanMaatTegelijk) {
    _bezig++;
    return;
  }
  final c = Completer<void>();
  _wachtenden.add(c);
  await c.future; // [_vrij] geeft zijn plek door; _bezig blijft gelijk
}

void _vrij() {
  if (_wachtenden.isNotEmpty) {
    _wachtenden.removeAt(0).complete();
  } else {
    _bezig--;
  }
}

// ── Op schijf ────────────────────────────────────────────────────────────────────────────────────────

File? _bestand;
Future<Map<String, Maat>>? _opSchijf;
Timer? _schrijfKlok;

/// Waar gemeten maten bewaard worden, zodat een volgende keer "Uitgave kiezen" ze meteen toont en het
/// archief niet opnieuw gevraagd wordt. Gezet bij het starten van de app; zonder (zoals in toetsen)
/// blijft alles in het geheugen.
void bewaarScanmatenIn(File? f) {
  _bestand = f;
  _opSchijf = null;
}

Future<Map<String, Maat>> _schijf() => _opSchijf ??= _lees(_bestand);

Future<Map<String, Maat>> _lees(File? f) async {
  final uit = <String, Maat>{};
  if (f == null) return uit;
  try {
    if (!await f.exists()) return uit;
    final j = jsonDecode(await f.readAsString());
    if (j is! Map) return uit;
    for (final e in j.entries) {
      final v = e.value;
      if (e.key is String && v is List && v.length == 2 && v[0] is int && v[1] is int && v[0] > 0 && v[1] > 0) {
        uit[e.key as String] = (w: v[0] as int, h: v[1] as int);
      }
    }
  } catch (_) {/* een kapot bestand is een lege kaart, geen reden om niets te tonen */}
  return uit;
}

void _onthoud(String url, Maat m) {
  if (_bestand == null) return;
  unawaited(_schijf().then((kaart) {
    // Achteraan is het jongst; vooraan valt eraf als het bestand vol is.
    kaart
      ..remove(url)
      ..[url] = m;
    while (kaart.length > kScanmatenBewaard) {
      kaart.remove(kaart.keys.first);
    }
    // Eén schrijfbeurt per golf metingen, niet één per scan.
    _schrijfKlok?.cancel();
    _schrijfKlok = Timer(const Duration(seconds: 2), () => unawaited(_schrijf(kaart)));
  }));
}

Future<void> _schrijf(Map<String, Maat> kaart) async {
  final f = _bestand;
  if (f == null) return;
  try {
    // Eerst ernaast, dan erover: een app die midden in het schrijven sluit, laat het oude bestand heel.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(
        jsonEncode({for (final e in kaart.entries) e.key: [e.value.w, e.value.h]}),
        flush: true);
    await tmp.rename(f.path);
  } catch (_) {/* niet kunnen bewaren kost alleen een meting de volgende keer */}
}

/// Voor de toetsen: schrijf nu, zonder op de klok te wachten.
@visibleForTesting
Future<void> schrijfScanmatenNu() async {
  _schrijfKlok?.cancel();
  _schrijfKlok = null;
  if (_bestand == null) return;
  await _schrijf(await _schijf());
}

/// Voor de toetsen: alles wat in het geheugen staat weg, ook de wachtrij. Het bestand blijft liggen.
void resetScanmatenVoorTest() {
  _maten.clear();
  _opSchijf = null;
  _schrijfKlok?.cancel();
  _schrijfKlok = null;
  _bezig = 0;
  _wachtenden.clear();
}

/// Hoe de maat op het scherm komt: "1400×1400", en of hij scherp genoeg is voor een albumhoes.
///
/// Drie standen, omdat dat het enige is wat je hier wilt weten: haarscherp op elk scherm (vanaf 1000),
/// bruikbaar (500–999), of wazig zodra hij groter dan een postzegel getoond wordt (onder de 500).
enum Scherpte { scherp, bruikbaar, klein }

Scherpte scherpteVan(Maat m) {
  final kort = m.w < m.h ? m.w : m.h;
  if (kort >= 1000) return Scherpte.scherp;
  if (kort >= 500) return Scherpte.bruikbaar;
  return Scherpte.klein;
}

String maatTekst(Maat m) => '${m.w}×${m.h}';

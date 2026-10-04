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
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import 'booklet.dart' show imageSize;
import 'editions.dart' show ChoiceImage;

typedef Maat = ({int w, int h});

final Map<String, Future<Maat?>> _maten = {};

/// De maat van [img]: meteen als de catalogus hem gaf, anders uit de kop van de scan. Null als het niet
/// te zeggen valt — en dan zegt het scherm niets, liever dan een getal te verzinnen.
///
/// Een [ChoiceImage.alleenMiniatuur] wordt NIET gemeten: zijn [ChoiceImage.uri] is het miniatuur van 150
/// pixels zelf, en "150×150" zou over de echte scan liegen.
Future<Maat?> scanMaatVan(ChoiceImage img, {http.Client? client}) {
  if (img.breedte > 0 && img.hoogte > 0) return Future.value((w: img.breedte, h: img.hoogte));
  if (img.alleenMiniatuur || img.uri.isEmpty) return Future.value(null);
  return _maten[img.uri] ??= _haal(img.uri, client);
}

/// Wat er al bekend is, zonder te wachten — voor de eerste tekening.
Maat? bekendeMaat(ChoiceImage img) =>
    img.breedte > 0 && img.hoogte > 0 ? (w: img.breedte, h: img.hoogte) : null;

Future<Maat?> _haal(String url, http.Client? gegeven) async {
  final client = gegeven ?? http.Client();
  try {
    for (final eind in const [65535, 1048575]) {
      final r = await client
          .get(Uri.parse(url), headers: {'Range': 'bytes=0-$eind'}).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200 && r.statusCode != 206) return null;
      final m = imageSize(r.bodyBytes);
      if (m != null && m.w > 0 && m.h > 0) return m;
      // Het hele bestand kwam al (de server negeerde de reeks, of het is klein): verder zoeken heeft
      // geen zin.
      if (r.statusCode == 200 || r.bodyBytes.length <= eind) return null;
    }
    return null;
  } catch (_) {
    // Een netwerkhik is geen uitspraak over de scan: de volgende keer opnieuw proberen.
    _maten.remove(url);
    return null;
  } finally {
    if (gegeven == null) client.close();
  }
}

/// Voor de toetsen.
void resetScanmatenVoorTest() => _maten.clear();

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

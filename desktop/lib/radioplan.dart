/// Een radio uit een zin: wat het taalmodel terugstuurt, en wat daarvan geloofd wordt.
///
/// **Waarom het model geen liedjes noemt.** Vijfhonderd tracktitels uit het hoofd van een taalmodel
/// zijn voor een deel verzonnen — plausibele namen van nummers die niet bestaan, en dan zoekt de radio
/// een half uur naar niets. Veertig eurodance-acts uit de jaren negentig zijn dat niet: dat is
/// algemene kennis, en een verkeerde naam valt meteen op. Dus geeft het model een klein setje VELDEN
/// terug — genre, jaren, aantal, en een handvol ZAADARTIESTEN — en komt de echte nummerlijst van
/// Deezer, die weet wat er bestaat. De zaadartiesten zíjn het tijdvak: de toppers van 2 Unlimited en
/// Culture Beat zijn jaren negentig.
///
/// **Waarom [leesRadioOpdracht] bestaat en waarom er een toets op staat.** De Messages-API weigert
/// getalgrenzen in een JSON-schema — `minimum` en `maximum` leveren een 400 op. Er is dus geen enkele
/// grens aan wat er terug kan komen behalve deze functie. Zegt het model per ongeluk 100000, dan is
/// dit het enige wat tussen die vergissing en honderdduizend Soulseek-downloads staat.
library;

/// Hoeveel nummers een radio hoogstens groot mag zijn.
///
/// Vijfhonderd is wat er gevraagd is, en dat is al ruim: ongeveer 33 uur muziek en enkele gigabytes.
/// Het is een PLAFOND op wat opgehaald mag worden, geen belofte dat het er ook zoveel worden.
const int kMaxRadio = 500;

/// Boven dit aantal wordt er eerst bevestigd, in gewone taal en met uren en gigabytes erbij.
const int kVraagBovenaantal = 100;

/// Wat er standaard komt als niemand een aantal noemt.
const int kStandaardAantal = 50;

/// Wat het model van jouw zin gemaakt heeft.
class RadioOpdracht {
  const RadioOpdracht({
    required this.genre,
    required this.aantal,
    required this.zaadArtiesten,
    this.jaarVan,
    this.jaarTot,
    this.stemming = '',
  });

  final String genre;
  final int aantal;

  /// De artiesten waarmee de radio begint. Nooit leeg als deze opdracht bruikbaar is.
  final List<String> zaadArtiesten;

  final int? jaarVan;
  final int? jaarTot;
  final String stemming;

  /// Is hier een radio van te maken? Zonder zaadartiesten valt er niets op te zoeken.
  bool get bruikbaar => zaadArtiesten.isNotEmpty;

  /// Hoe de radio heet, in gewone taal.
  String get naam {
    final delen = <String>[
      if (genre.isNotEmpty) genre,
      if (jaarVan != null && jaarTot != null)
        _jaren(jaarVan!, jaarTot!)
      else if (jaarVan != null)
        'vanaf $jaarVan',
      if (stemming.isNotEmpty) stemming,
    ];
    return delen.isEmpty ? 'Radio' : delen.join(' · ');
  }

  static String _jaren(int van, int tot) {
    // "jaren 90" leest beter dan "1990–1999", en dat is ook precies hoe de vraag gesteld werd.
    if (van % 10 == 0 && tot == van + 9) {
      return 'jaren ${(van % 100).toString().padLeft(2, '0')}';
    }
    return van == tot ? '$van' : '$van–$tot';
  }
}

/// Het schema dat met de vraag meegaat.
///
/// Drie regels, en op alle drie is deze functie een keer gestruikeld:
///
/// 1. `additionalProperties: false` is verplicht.
/// 2. **Élk veld moet in `required` staan.** Dat is wat een 400 opleverde bij de eerste echte
///    poging: `jaarVan`, `jaarTot` en `stemming` stonden er wel in `properties` maar niet in
///    `required`, en dan weigert de API het hele schema — dus komt er geen antwoord, niet eens een
///    half antwoord. Iets dat mag ontbreken wordt daarom een `anyOf` met `null`, en niet een veld
///    dat je weglaat.
/// 3. Getalgrenzen staan er BEWUST niet in: `minimum`/`maximum` worden geweigerd. Het klemmen
///    gebeurt in [leesRadioOpdracht].
Map<String, dynamic> radioSchema() => {
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'genre': {
          'type': 'string',
          'description': 'Het genre in één of twee woorden, zoals de gebruiker het noemde.',
        },
        'jaarVan': {
          'anyOf': [
            {'type': 'integer'},
            {'type': 'null'}
          ],
          'description': 'Eerste jaar van het tijdvak, of null als de gebruiker er niets over zei.',
        },
        'jaarTot': {
          'anyOf': [
            {'type': 'integer'},
            {'type': 'null'}
          ],
          'description': 'Laatste jaar van het tijdvak, of null als de gebruiker er niets over zei.',
        },
        'aantal': {
          'type': 'integer',
          'description': 'Hoeveel nummers de gebruiker vroeg. Hoogstens $kMaxRadio.',
        },
        'zaadArtiesten': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              'Twintig tot veertig BESTAANDE artiesten die precies bij dit genre en tijdvak horen. '
                  'Alleen namen van artiesten, nooit titels van nummers.',
        },
        'stemming': {
          'type': 'string',
          'description': 'Eén woord over de sfeer, of leeg als de gebruiker daar niets over zei.',
        },
      },
      // Alles, en niet alleen wat verplicht voelt. Zie de kop hierboven: een veld dat in
      // `properties` staat maar niet hier, laat de API het hele schema weigeren.
      'required': ['genre', 'jaarVan', 'jaarTot', 'aantal', 'zaadArtiesten', 'stemming'],
    };

/// De vraag aan het model.
///
/// Kort, en met de reden erbij waarom er geen nummers gevraagd worden — een model dat weet waaróm het
/// artiesten moet noemen, houdt zich daar beter aan dan een model dat alleen het verbod krijgt.
String radioPrompt(String zin) => '''
Iemand wil een radio in zijn muziekapp. Dit is wat hij typte:

"$zin"

Vul het schema in. Noem GEEN titels van nummers — de app zoekt die zelf op bij een muziekcatalogus,
en verzonnen titels leveren daar niets op. Noem in plaats daarvan twintig tot veertig artiesten die
echt bestaan en die precies in dit genre en dit tijdvak thuishoren; die artiesten bepalen wat de radio
wordt.

Drie dingen die je in de gaten moet houden bij die namen, want de app kan ze niet meer rechtzetten:

1. Elke artiest moet in dit genre thuishoren, niet er vlakbij. Eén rockband tussen de dansplaten
   levert een radio op die halverwege van kleur verschiet, en dat valt meer op dan tien goede keuzes.
2. Schrijf de naam zoals hij in een muziekcatalogus staat, voluit en zonder toevoegingen. Een naam
   die daar niet gevonden wordt, levert niets op.
3. Vermijd namen die je met één teken verschil met een veel bekendere artiest kunt verwarren, tenzij
   ze werkelijk in dit genre horen.

Noemt hij geen aantal, kies dan $kStandaardAantal.''';

/// Wat er van het antwoord geloofd wordt.
///
/// **Dit is de grens.** De API weigert `minimum`/`maximum` in het schema, dus alles wat hier niet
/// geklemd wordt, is ongeklemd. Elke regel hieronder houdt iets tegen dat anders echt gebeurt:
///
/// * een aantal van honderdduizend, of nul;
/// * een jaartal van 19 of 20250, of een tijdvak dat achteruit loopt;
/// * dezelfde artiest zes keer, met een hoofdletter verschil;
/// * een lege naam, of een naam van vierhonderd tekens;
/// * geen enkele artiest — en dan valt er niets op te zoeken.
RadioOpdracht leesRadioOpdracht(Object? json) {
  final m = json is Map ? json : const {};

  final artiesten = <String>[];
  final gezien = <String>{};
  final rauw = m['zaadArtiesten'];
  for (final a in (rauw is List ? rauw : const [])) {
    if (a is! String) continue;
    final naam = a.trim();
    if (naam.isEmpty || naam.length > 80) continue;
    if (!gezien.add(naam.toLowerCase())) continue;
    artiesten.add(naam);
    if (artiesten.length >= 60) break;
  }

  return RadioOpdracht(
    genre: _kort(m['genre']),
    stemming: _kort(m['stemming']),
    aantal: _getal(m['aantal'], standaard: kStandaardAantal, laag: 1, hoog: kMaxRadio),
    jaarVan: _jaar(m['jaarVan']),
    jaarTot: _naJaar(_jaar(m['jaarTot']), _jaar(m['jaarVan'])),
    zaadArtiesten: artiesten,
  );
}

String _kort(Object? v) {
  if (v is! String) return '';
  final s = v.trim();
  return s.length <= 40 ? s : s.substring(0, 40).trim();
}

int _getal(Object? v, {required int standaard, required int laag, required int hoog}) {
  final n = v is num ? v.toInt() : int.tryParse('${v ?? ''}');
  if (n == null) return standaard;
  return n < laag ? laag : (n > hoog ? hoog : n);
}

/// Een jaartal, of null. Buiten deze eeuwen is het geen jaartal maar een verschrijving.
int? _jaar(Object? v) {
  final n = v is num ? v.toInt() : int.tryParse('${v ?? ''}');
  if (n == null || n < 1900 || n > 2100) return null;
  return n;
}

/// Het eindjaar mag niet vóór het beginjaar liggen. Dan is het tijdvak leeg en levert de radio niets.
int? _naJaar(int? tot, int? van) {
  if (tot == null || van == null) return tot;
  return tot < van ? van : tot;
}

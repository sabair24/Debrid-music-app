/// De vraag aan Claude voor Ontdek (Saber, 04-11-2026: "Claude: op je hele smaakprofiel"; zie `ontdek.dart`).
///
/// Zelfde afspraak als bij de radio en `aanbevelingplan.dart`: het model kiest, Deezer bewijst. Elk voorstel wordt
/// nageslagen (`RecommendService.lijstOpDeezer`), en wat daar niet gevonden wordt, valt weg. Hier mag het model wél
/// nummers noemen — dat is wat Ontdek toont — maar een verzonnen titel levert niets op.
///
/// Geen IO: de vraag, het schema en het uitlezen, zodat het na te rekenen is.
library;

/// Zoveel nummers vragen: genoeg voor een dag met een paar keer verversen (een derde van de lijst komt van Claude).
const int kOntdekVragen = 40;

/// Zoveel daarvan iets verder van de gewone smaak (Saber: "1 op 5 iets verder").
const int kOntdekVragenVerder = 8;

/// Wat het model over de luisteraar hoort.
class OntdekProfiel {
  const OntdekProfiel({
    this.zwaarst = const [],
    this.recent = const [],
    this.groen = const [],
    this.hoeken = const {},
    this.decennia = const {},
    this.weggetikt = const [],
  });

  /// De artiesten die het zwaarst wegen (gedraaid, bezit, duimen), zwaarst eerst.
  final List<String> zwaarst;

  /// Wat hij de laatste twee weken draaide (artiest — titel).
  final List<String> recent;

  /// Nummers met een groene duim of een hartje (artiest — titel).
  final List<String> groen;

  /// Het aandeel van elke hoek van de bibliotheek, in procent: {"popsoul": 44, "Nederlandstalig": 8, …}.
  final Map<String, int> hoeken;

  /// Het aandeel per decennium, in procent: {1990: 29, 2000: 29, …}.
  final Map<int, int> decennia;

  /// Wat hij in Ontdek wegtikte (artiest — titel): daar wil hij niet meer van.
  final List<String> weggetikt;

  bool get leeg => zwaarst.isEmpty && recent.isEmpty;
}

/// Eén voorstel.
typedef OntdekVoorstel = ({String artiest, String titel, String reden, bool verder});

/// Het antwoordschema. Elk veld in `properties` staat ook in `required`, anders weigert de API het hele schema.
Map<String, dynamic> ontdekSchema() => {
  'type': 'object',
  'additionalProperties': false,
  'properties': {
    'nummers': {
      'type': 'array',
      'description': 'Ongeveer $kOntdekVragen nummers, elke artiest hoogstens één keer.',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          'artiest': {'type': 'string', 'description': 'De artiest, zoals die algemeen gespeld wordt.'},
          'titel': {
            'type': 'string',
            'description': 'De titel van een BESTAAND nummer van die artiest, zonder "(Remastered)" of "(Live)".',
          },
          'reden': {
            'type': 'string',
            'description':
                'Waarom het bij hem past, in het Nederlands, hoogstens zes woorden. '
                'Bijvoorbeeld: "Voor wie Sade en Seal draait".',
          },
          'verder': {
            'type': 'boolean',
            'description': 'true voor de $kOntdekVragenVerder nummers die een stap buiten zijn gewone smaak gaan.',
          },
        },
        'required': ['artiest', 'titel', 'reden', 'verder'],
      },
    },
  },
  'required': ['nummers'],
};

/// De vraag. Met de redenen erbij: een model dat weet waaróm een regel er is, houdt zich er beter aan.
String ontdekPrompt(OntdekProfiel p) {
  String procent(Map<Object, int> m) => (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
      .where((e) => e.value > 0)
      .map((e) => '${e.key is int ? '${e.key}s' : e.key} ${e.value}%')
      .join(', ');
  return '''
Iemand gebruikt een muziekapp en wil elke dag nieuwe nummers ontdekken die passen bij zijn bibliotheek.

Zijn smaak:
- Wie hij het meest draait en heeft: ${p.zwaarst.take(30).join(', ')}
- Wat hij de laatste weken draaide: ${p.recent.take(15).join('; ')}
- Waar hij een duim of hartje op zette: ${p.groen.take(15).join('; ')}
- Zijn bibliotheek naar hoek: ${procent(p.hoeken)}
- Naar decennium: ${procent(p.decennia)}
${p.weggetikt.isEmpty ? '' : '- Wat hij wegtikte als "niet voor mij": ${p.weggetikt.take(15).join('; ')}\n'}
Noem ongeveer $kOntdekVragen NUMMERS die hij waarschijnlijk nog niet heeft.

Wat er echt toe doet:
1. Alleen nummers die BESTAAN, met de titel zoals hij op de plaat staat. Elk voorstel wordt opgezocht in een
   muziekcatalogus; een verzonnen titel verdwijnt.
2. Elke artiest hoogstens één keer: hij wil variatie.
3. Volg de verhouding van zijn bibliotheek: ongeveer evenveel uit elke hoek en elk decennium als hierboven staat. Als
   er Nederlandstalige, Franse of Latijnse muziek in staat, hoort daar iets bij.
4. Vooral dichtbij zijn smaak. Precies $kOntdekVragenVerder nummers gaan een stap verder (een aangrenzend genre of
   tijdvak dat aansluit bij wat hij draait): zet daar "verder" op true, bij de rest op false.
5. Artiesten die hij al heeft mogen, maar dan met een nummer dat niet bij hun grootste hits hoort (die heeft hij
   waarschijnlijk al). Liever artiesten die hij nog niet heeft.
6. Geen remixes, live-opnames, covers of kerstnummers.
7. De reden in het Nederlands, hoogstens zes woorden, met iets uit zijn smaak ("Voor wie Sade en Seal draait").
''';
}

/// Het antwoord uitlezen. Wat niet klopt valt stil weg; dezelfde artiest twee keer: de eerste blijft.
List<OntdekVoorstel> leesOntdekVoorstellen(Object? json) {
  if (json is! Map || json['nummers'] is! List) return const [];
  final uit = <OntdekVoorstel>[];
  final gezien = <String>{};
  for (final v in json['nummers'] as List) {
    if (v is! Map) continue;
    final artiest = '${v['artiest'] ?? ''}'.trim();
    final titel = '${v['titel'] ?? ''}'.trim();
    if (artiest.isEmpty || titel.isEmpty) continue;
    if (!gezien.add(artiest.toLowerCase())) continue;
    var reden = '${v['reden'] ?? ''}'.trim();
    // Hoogstens zes woorden gevraagd; wat langer is, past niet op één regel van een gsm.
    final woorden = reden.split(RegExp(r'\s+'));
    if (woorden.length > 8) reden = '${woorden.take(8).join(' ')}…';
    uit.add((artiest: artiest, titel: titel, reden: reden, verder: v['verder'] == true));
  }
  return uit;
}

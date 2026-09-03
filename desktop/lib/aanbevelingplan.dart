/// Van een smaakprofiel naar een handvol aanbevelingen, gevraagd aan een taalmodel.
///
/// **Waarom hier een model bij komt.** De startpagina leunt volledig op Deezers "verwante
/// artiesten": van jouw artiest naar zijn buren, en van die buren hun toppers. Dat werkt, maar het
/// blijft dicht bij huis en het weet niets van jouw eigen mengsel. Wie 448 nummers uit de jaren 90
/// heeft, een Belgische hoek (Clouseau, Pommelien Thijs), Franse chanson én raï van Khaled, krijgt
/// van "verwant aan Michael Jackson" nooit een suggestie die dát verband ziet. Saber vroeg er op
/// 02-09-2026 zelf om: *"gebruik niet enkel deezer daarvoor maar AI ook"*.
///
/// **Wat het model wél en niet doet.** Het noemt ARTIEST en ALBUM, en een reden in het Nederlands.
/// Meer niet. Precies zoals `radioplan.dart` alleen artiesten laat noemen: een model dat titels van
/// nummers verzint, verzint ook titels die niet bestaan, en dan staat er een tegel die nergens heen
/// gaat. Alles wat hier terugkomt wordt daarom eerst bij Deezer nageslagen — bestaat de artiest,
/// bestaat het album? — en wat daar niet gevonden wordt valt weg. Het model kiest; Deezer bewijst.
///
/// **De reden is geen sier.** Het was de klacht dat de aanbevelingen niets met zijn muziek te maken
/// leken te hebben. Een rij die erbij zet waaróm iets wordt voorgesteld, is te controleren — en dat
/// is precies wat een rij zonder uitleg niet is.
library;

/// Wat het model over deze bibliotheek te horen krijgt.
///
/// Een PROFIEL en niet de bibliotheek zelf: 1239 nummers passen niet in één vraag, en ze zijn ook
/// niet nodig. Wat telt is de vorm — wie er bovenaan staat, uit welke jaren het komt, en wat er de
/// laatste tijd gedraaid is.
class SmaakProfiel {
  /// De artiesten met de meeste nummers, veel eerst: "Michael Jackson (80)".
  final List<String> topArtiesten;

  /// Hoeveel nummers per decennium: {1990: 448, 2000: 374, …}.
  final Map<int, int> perDecennium;

  /// Wie er de laatste tijd werkelijk gedraaid is, meest eerst.
  final List<String> gespeeld;

  /// De genres zoals de bibliotheek ze noemt.
  final List<String> genres;

  const SmaakProfiel({
    this.topArtiesten = const [],
    this.perDecennium = const {},
    this.gespeeld = const [],
    this.genres = const [],
  });

  bool get leeg => topArtiesten.isEmpty && gespeeld.isEmpty;
}

/// Eén voorstel van het model.
class AiVoorstel {
  final String artiest;
  final String album;

  /// Waarom dit wordt voorgesteld, in één korte Nederlandse zin. Komt onder de tegel te staan.
  final String reden;
  const AiVoorstel(this.artiest, this.album, this.reden);
}

/// Hoogstens zoveel voorstellen vragen.
///
/// Twaalf en niet twintig: alles wordt hierna bij Deezer nageslagen, en elk voorstel kost daar twee
/// verzoeken uit hetzelfde budget dat de rest van de pagina ook gebruikt. Zie `deezerbaan.dart`.
const int kMaxVoorstellen = 12;

/// Het antwoordschema.
///
/// Elk veld dat in `properties` staat moet ook in `required` staan, anders weigert de API het hele
/// schema — dezelfde regel als bij `radioSchema`, en dezelfde 400 als je het vergeet.
Map<String, dynamic> aanbevelingSchema() => {
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'voorstellen': {
          'type': 'array',
          'description': 'Hoogstens $kMaxVoorstellen albums die bij deze smaak passen.',
          'items': {
            'type': 'object',
            'additionalProperties': false,
            'properties': {
              'artiest': {
                'type': 'string',
                'description': 'De naam van een BESTAANDE artiest, zoals die algemeen gespeld wordt.',
              },
              'album': {
                'type': 'string',
                'description': 'De titel van een BESTAAND album van die artiest.',
              },
              'reden': {
                'type': 'string',
                'description':
                    'Eén korte zin in het Nederlands waarom dit bij deze luisteraar past. '
                        'Verwijs naar iets uit zijn profiel, bijvoorbeeld een artiest of een periode. '
                        'Hoogstens tien woorden.',
              },
            },
            'required': ['artiest', 'album', 'reden'],
          },
        },
      },
      'required': ['voorstellen'],
    };

/// De vraag aan het model.
///
/// Met de reden erbij waarom er geen nummers gevraagd worden en waarom bekende platen niet hoeven:
/// een model dat weet waaróm een regel er is, houdt zich er beter aan dan een model dat alleen het
/// verbod krijgt. Dezelfde ervaring als bij `radioPrompt`.
String aanbevelingPrompt(SmaakProfiel p) {
  final decennia = (p.perDecennium.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)))
      .take(4)
      .map((e) => '${e.key}s: ${e.value}')
      .join(', ');
  return '''
Iemand gebruikt een muziekapp en wil albums ontdekken die hij nog niet heeft.

Dit is zijn bibliotheek, in het kort:
- Meeste muziek van: ${p.topArtiesten.take(30).join(', ')}
- Nummers per decennium: $decennia
- Genres die in zijn tags staan: ${p.genres.take(10).join(', ')}
- Wat hij de laatste tijd draaide: ${p.gespeeld.take(10).join(', ')}

Noem hoogstens $kMaxVoorstellen ALBUMS die hierbij passen en die er nog niet in staan.

Drie dingen die er echt toe doen:
1. Noem alleen artiesten en albums die BESTAAN. Elk voorstel wordt nageslagen in een muziekcatalogus,
   en wat daar niet te vinden is verdwijnt — een verzonnen titel levert dus niets op.
2. Noem geen artiest die hierboven al in zijn bibliotheek staat. Hij zoekt iets nieuws.
3. Kijk naar het VERBAND in zijn smaak, niet alleen naar losse namen. Als er Belgische en
   Nederlandstalige muziek in staat, of Franse chanson, of raï, dan hoort daar iets bij dat een
   lijst met "verwante artiesten" nooit zou vinden. Dat is precies waarvoor je gevraagd wordt.

Schrijf de reden in het Nederlands, kort, en verwijs naar iets uit zijn profiel.
''';
}

/// Het antwoord van het model uitpakken.
///
/// Alles wat niet klopt valt stil weg in plaats van de hele rij te laten mislukken: één voorstel
/// zonder titel is geen reden om de andere elf weg te gooien. Dat is dezelfde afweging als in
/// `leesRadioOpdracht`.
List<AiVoorstel> leesVoorstellen(Object? json) {
  if (json is! Map) return const [];
  final lijst = json['voorstellen'];
  if (lijst is! List) return const [];
  final uit = <AiVoorstel>[];
  final gezien = <String>{};
  for (final v in lijst) {
    if (v is! Map) continue;
    final artiest = '${v['artiest'] ?? ''}'.trim();
    final album = '${v['album'] ?? ''}'.trim();
    if (artiest.isEmpty || album.isEmpty) continue;
    // Twee keer hetzelfde album voorstellen gebeurt, en dan staat het twee keer in de rij.
    if (!gezien.add('${artiest.toLowerCase()}|${album.toLowerCase()}')) continue;
    uit.add(AiVoorstel(artiest, album, '${v['reden'] ?? ''}'.trim()));
    if (uit.length >= kMaxVoorstellen) break;
  }
  return uit;
}

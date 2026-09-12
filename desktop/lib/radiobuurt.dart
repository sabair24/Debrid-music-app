/// Wie er naast de zaadartiest in een radio hoort, gevraagd aan een taalmodel.
///
/// **Waarom dit erbij komt.** Saber op 12-09-2026, na een radio van twee uur rond Michael Jackson -
/// Billie Jean: *"er zijn toch nog meer varianten? ik wil de maximum variatie, dat ik ook nieuwe
/// maar ook bekende liedjes kan ontdekken (...) het moet beter"* dan Deezer en Tidal.
///
/// Hij heeft gelijk, en het getal is hard. Deezers `artist/<id>/related` geeft per artiest precies
/// TWINTIG verwante namen en nooit meer — nagemeten op 12-09-2026 met `limit=4`, `20`, `50` en
/// `100`: `total` is elke keer 20. Dat is de hele horizon van een Deezer-radio. Voor Michael Jackson
/// zijn dat Stevie Wonder, Diana Ross, Prince, Barry White, Whitney Houston, Lionel Richie, Kool &
/// The Gang, George Michael, George Benson, The Jacksons, Chaka Khan, Commodores, Earth Wind & Fire,
/// Donna Summer, Simply Red, Lisa Stansfield, Patti LaBelle, Billy Ocean, Jermaine Jackson en Bee
/// Gees. Keurig, en volstrekt voorspelbaar: geen Quincy Jones-lijn, geen Minneapolis-hoek, geen
/// enkele artiest uit zijn eigen 1273 nummers die er toevallig naast past.
///
/// **Wat het model wél en niet doet.** Het noemt ARTIESTEN, geen liedjes. Dat is dezelfde regel als
/// in `radioplan.dart` en `aanbevelingplan.dart`, en om dezelfde reden: een model dat tracktitels uit
/// zijn hoofd opsomt verzint er een deel bij, en dan zoekt de radio een half uur naar nummers die
/// niet bestaan. Artiestnamen zijn algemene kennis en een verzinsel valt meteen om bij Deezer.
///
/// Het model kiest; Deezer bewijst. Alles wat hier terugkomt wordt opgezocht, en wat daar niet
/// bestaat valt weg.
library;

import 'aanbevelingplan.dart';

/// Hoeveel namen er hoogstens gevraagd worden.
///
/// Vierentwintig, tegen de vier die de radio tot nu toe gebruikte. Elke naam kost bij Deezer twee
/// verzoeken (opzoeken plus toppers), en die komen uit hetzelfde budget als de rest van de app; zie
/// `deezerbaan.dart`. Vierentwintig namen à vijf toppers is ruim honderd kandidaten, en dat is meer
/// dan een radio van vijf uur nodig heeft.
const int kMaxBuren = 24;

/// Hoeveel daarvan uit zijn EIGEN kast mogen komen.
///
/// "Ik wil ook bekende liedjes ontdekken" is een aparte wens dan ontdekken. Een radio die alleen
/// vreemde namen speelt is een ontdekmachine; een radio die alleen bekende speelt is een shuffle.
/// Een derde bekend is de verhouding waar het model om gevraagd wordt.
const int kBekendDeel = 8;

/// Eén naam die het model voorstelt.
class Buurman {
  final String artiest;

  /// Staat hij in zijn kast (of kent hij hem zeker), of is dit juist iets nieuws?
  final bool bekend;

  /// Waarom deze naast dit nummer hoort, in één korte Nederlandse zin. Voor het logboek en later
  /// eventueel op het scherm — een radio die kan uitleggen waarom iets speelt is te controleren.
  final String reden;

  const Buurman(this.artiest, this.bekend, this.reden);
}

/// Het antwoordschema.
///
/// Elk veld in `properties` moet ook in `required` staan, anders weigert de API het hele schema met
/// een 400 — dezelfde regel als bij `radioSchema` en `aanbevelingSchema`, en dezelfde fout als je
/// het vergeet. Getalgrenzen mogen er niet in; die staan daarom in [leesBuurt].
Map<String, dynamic> buurtSchema() => {
      'type': 'object',
      'properties': {
        'buren': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'artiest': {'type': 'string', 'description': 'De naam zoals die op een plaat staat.'},
              'bekend': {
                'type': 'boolean',
                'description': 'True als dit iets is wat hij waarschijnlijk al kent of in zijn kast '
                    'heeft staan; false als dit juist een ontdekking is.',
              },
              'reden': {
                'type': 'string',
                'description': 'Eén korte Nederlandse zin: waarom hoort dit naast dit nummer? '
                    'Noem iets concreets - een producer, een scene, een jaartal, een klank.',
              },
            },
            'required': ['artiest', 'bekend', 'reden'],
            'additionalProperties': false,
          },
        },
      },
      'required': ['buren'],
      'additionalProperties': false,
    };

/// De vraag zoals hij de deur uitgaat.
///
/// Apart en zuiver, zodat na te lezen is wat er verstuurd wordt zonder er een aanroep voor te doen.
/// [deezerBuren] gaat mee om het model te vertellen wat het NIET hoeft te herhalen: dat is precies de
/// twintig namen die de radio toch al had, en de winst zit in wat daarnaast staat.
String buurtPrompt({
  required String artiest,
  String? titel,
  required SmaakProfiel profiel,
  List<String> deezerBuren = const [],
}) {
  final decennia = (profiel.perDecennium.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)))
      .take(4)
      .map((e) => '${e.key}s (${e.value})')
      .join(', ');
  final zaad = titel == null || titel.trim().isEmpty ? artiest : '$artiest - $titel';
  return '''
Je stelt een radio samen rond: $zaad

Dit weet ik van de luisteraar:
- Meest in zijn kast: ${profiel.topArtiesten.take(25).join(', ')}
- Zwaartepunt per decennium: ${decennia.isEmpty ? 'onbekend' : decennia}
- Recent gedraaid: ${profiel.gespeeld.take(10).join(', ')}
- Genres in zijn kast: ${profiel.genres.take(12).join(', ')}

Deezer noemt als verwante artiesten al: ${deezerBuren.isEmpty ? '(niets)' : deezerBuren.join(', ')}
Die heb ik dus al. Noem ze niet opnieuw.

Geef $kMaxBuren artiesten die naast dit nummer horen en die daar NIET bij staan. Zoek de verbanden
die een lijst met verwante artiesten niet ziet: dezelfde producer of arrangeur, dezelfde studio of
scene, hetzelfde jaar en dezelfde klank, een artiest die dit nummer gesampled heeft of erdoor
gevormd is, of juist de bron waar dit nummer zelf uit komt.

Ongeveer $kBekendDeel ervan moeten namen zijn die hij waarschijnlijk al kent of in zijn kast heeft
staan (zet bekend op true) - want hij wil ook oude bekenden terugvinden. De rest moet juist nieuw
voor hem zijn (bekend op false). Beide horen bij dit nummer te passen: verrassend mag, willekeurig
niet.

Alleen artiesten die echt bestaan en die op streamingdiensten te vinden zijn. Schrijf de naam zoals
die op een plaat staat. Geen liedjestitels, alleen artiesten.
''';
}

/// Wat er van het antwoord geloofd wordt.
///
/// **Dit is de enige grens.** De Messages-API weigert `minItems`/`maxItems` in een schema, net als
/// getalgrenzen elders — zegt het model per ongeluk driehonderd namen, dan is dit het enige wat
/// tussen die vergissing en zeshonderd Deezer-verzoeken staat. Zelfde rol als [leesRadioOpdracht]
/// in `radioplan.dart`.
///
/// Een naam die leeg is, of die de zaadartiest zelf is, of die er al staat, valt weg: de eerste is
/// ruis, de tweede is wat de radio al doet, en de derde kost een dubbel verzoek voor niets.
List<Buurman> leesBuurt(Object? json, {String zaadArtiest = ''}) {
  if (json is! Map) return const [];
  final lijst = json['buren'];
  if (lijst is! List) return const [];
  final zaad = zaadArtiest.trim().toLowerCase();
  final gezien = <String>{};
  final uit = <Buurman>[];
  for (final v in lijst) {
    if (uit.length >= kMaxBuren) break;
    if (v is! Map) continue;
    final naam = '${v['artiest'] ?? ''}'.trim();
    if (naam.isEmpty || naam.length > 120) continue;
    final sleutel = naam.toLowerCase();
    if (sleutel == zaad || !gezien.add(sleutel)) continue;
    final reden = '${v['reden'] ?? ''}'.trim();
    uit.add(Buurman(naam, v['bekend'] == true, reden.length > 200 ? reden.substring(0, 200) : reden));
  }
  return uit;
}

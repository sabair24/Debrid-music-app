/// Het taalmodel als samensteller: concrete NUMMERS in de stijl en het tijdvak van het zaad.
///
/// **Waarom nummers en niet alleen artiesten.** Tot 26-09-2026 noemde het model artiestnamen, en
/// van elk daarvan nam de radio Deezers top vier. Dat maakt Deezer toch weer de rechter: welke
/// nummers, welke versie, en of het wel een nummer uit dat tijdvak is. Saber: *"dit is gelimiteerd
/// aan deezer, maar moet combinatie zijn van AI, discogs eventueel, the audiodatabase."*
///
/// Een model verzint soms een titel. Daarom wordt elk nummer daarna opgezocht (bestaat het, en hoe
/// lang duurt het) en gekeurd op stijl en tijdvak — zie `radiostijl.dart`. Wat het model zegt is een
/// voorstel, geen feit.
library;

import 'aanbevelingplan.dart' show SmaakProfiel;
import 'radiobuurt.dart' show lijktOpArtiest;
import 'radiokeuze.dart';
import 'radiosmaak.dart';

/// Hoeveel nummers het model mag noemen. Genoeg voor een uur of twee naast wat Deezer geeft.
const int kMaxModelNummers = 36;

/// Eén voorstel van het model.
class AiNummer {
  const AiNummer(this.artiest, this.titel, {this.jaar, this.bekend = false});
  final String artiest;
  final String titel;

  /// Het jaar volgens het model. Een hint, geen feit: Discogs gaat voor.
  final int? jaar;

  /// Kent de luisteraar deze artiest waarschijnlijk al?
  final bool bekend;
}

/// Het JSON-schema van het antwoord. Zonder getalgrenzen: de Messages-API weigert `minimum` en
/// `maxItems`, en een geweigerd schema levert helemaal niets op. [leesNummers] is de grens.
Map<String, dynamic> nummersSchema() => {
      'type': 'object',
      'properties': {
        'nummers': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'artiest': {'type': 'string', 'description': 'De naam zoals die op de plaat staat.'},
              'titel': {
                'type': 'string',
                'description': 'De titel zoals op de single, zonder "Remix", "Extended" of "Live".',
              },
              'jaar': {'type': 'integer', 'description': 'Het jaar waarin het nummer uitkwam.'},
              'bekend': {
                'type': 'boolean',
                'description': 'True als de luisteraar deze artiest waarschijnlijk al kent.',
              },
            },
            'required': ['artiest', 'titel', 'jaar', 'bekend'],
            'additionalProperties': false,
          },
        },
      },
      'required': ['nummers'],
      'additionalProperties': false,
    };

/// Wat de stand van Bekend ↔ Ontdekken van het model vraagt.
String _smaakZin(Radiosmaak smaak) => switch (smaak) {
      Radiosmaak.bekend =>
        'Kies vooral de hits die iedereen van die tijd kent: de grote singles, geen albumnummers.',
      Radiosmaak.gemengd =>
        'Meng bekende hits met minder bekende singles van dezelfde scene, ongeveer half om half.',
      Radiosmaak.ontdekken =>
        'Kies juist NIET de grootste hits: minder bekende singles, b-kantjes van hitartiesten en '
            'artiesten uit dezelfde scene die weinig mensen nog kennen.',
    };

/// De vraag aan het model.
///
/// [stijlen] en [jaar] komen van Discogs (de uitgave van het zaadnummer), [genre] van TheAudioDB —
/// zo weet het model wat voor plaat het zaad IS, en hoeft het dat niet uit de naam te raden.
String nummersPrompt({
  required String artiest,
  String? titel,
  int? jaar,
  List<String> stijlen = const [],
  String? genre,
  required SmaakProfiel profiel,
  Radiosmaak smaak = Radiosmaak.gemengd,
  List<String> alGekozen = const [],
}) {
  final zaad = titel == null || titel.trim().isEmpty ? artiest : '$artiest - $titel';
  final feiten = [
    if (jaar != null) 'uit $jaar',
    if (stijlen.isNotEmpty) 'stijl ${stijlen.join(', ')}',
    if (genre != null && genre.trim().isNotEmpty) 'genre $genre',
  ].join(', ');
  return '''
Je stelt een radio samen rond: $zaad${feiten.isEmpty ? '' : ' ($feiten)'}

Geef $kMaxModelNummers nummers die op deze radio horen. Blijf in het genre en het tijdvak van DIT
nummer: ongeveer dezelfde jaren, dezelfde klank, dezelfde scene. Bijvoorbeeld: rond een
eurodanceplaat uit de jaren negentig horen eurodance, dance en happy hardcore uit die jaren - geen
disco uit de jaren zeventig, geen EDM uit de jaren 2010, en geen zanger alleen omdat hij uit hetzelfde
land komt.

${_smaakZin(smaak)}

Altijd de originele of de radioversie: geen remixen, extended mixes, covers, live-opnames of
karaoke. Hoogstens twee nummers van $artiest zelf, en hoogstens twee per andere artiest.
${alGekozen.isEmpty ? '' : '\nDeze staan al op de radio, noem ze niet opnieuw: ${alGekozen.take(60).join('; ')}\n'}
Wat ik van de luisteraar weet - alleen om "bekend" in te vullen, niet om de stijl te kiezen:
- Meest in zijn kast: ${profiel.topArtiesten.take(25).join(', ')}
- Recent gedraaid: ${profiel.gespeeld.take(10).join(', ')}

Alleen nummers die echt bestaan en op streamingdiensten staan. Schrijf artiest en titel zoals op de
plaat.
''';
}

/// Wat er van het antwoord geloofd wordt. Dit is de enige grens — zie [nummersSchema].
///
/// Dubbels weg (zelfde artiest en titel, anders geschreven), niets dat geen artiestnaam kan zijn,
/// geen lege titels, en een jaartal alleen als het er een kán zijn.
List<AiNummer> leesNummers(Object? json) {
  if (json is! Map) return const [];
  final lijst = json['nummers'];
  if (lijst is! List) return const [];
  String plat(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  final gezien = <String>{};
  final uit = <AiNummer>[];
  for (final v in lijst) {
    if (uit.length >= kMaxModelNummers) break;
    if (v is! Map) continue;
    final artiest = '${v['artiest'] ?? ''}'.trim();
    final titel = '${v['titel'] ?? ''}'.trim();
    if (!lijktOpArtiest(artiest) || titel.isEmpty || titel.length > 120) continue;
    if (!gezien.add('${plat(artiest)}|${plat(titel)}')) continue;
    final j = v['jaar'];
    final jaar = j is num ? j.toInt() : int.tryParse('$j');
    uit.add(AiNummer(artiest, titel,
        jaar: jaar != null && jaar >= 1900 && jaar <= 2100 ? jaar : null, bekend: v['bekend'] == true));
  }
  return uit;
}

/// Duurt dit zo lang als een single? Tweeënhalve tot viereneenhalve minuut.
///
/// Gemeten op 26-09-2026: voor "Culture Beat — Mr. Vain" koos de radio de versie van 5:36, voor
/// "Sash! — Ecuador" 5:55 en voor "Technotronic — Pump Up The Jam" 5:22 — de gewone titel, maar de
/// albumversie. Singles en radio-edits uit die tijd zitten vrijwel altijd onder de vierenhalve
/// minuut. Zonder lengte (0) weten we het niet, en dat telt niet als single.
bool heeftSinglelengte(int seconden) => seconden >= 150 && seconden <= 270;

/// Welke Deezer-treffer is het nummer dat het model bedoelde? De index, of null als er geen is.
///
/// Zelfde artiest (gasten tellen niet), zelfde liedje (op [basisTitel]), en nooit een bewerking of
/// een cover — het model vroeg om het origineel of de radioversie. Van wat overblijft eerst wat zo
/// lang duurt als een single ([heeftSinglelengte]), dan de gewoonste uitvoering, en bij gelijke
/// stand de bekendste. Geen treffer is een antwoord: dan bestond het nummer niet zoals het model het
/// noemde, en dat is precies wat deze toets moet vangen.
int? besteTreffer(List<({String artiest, String titel, int rang, int seconden})> treffers,
    String artiest, String titel) {
  final t = basisTitel(titel);
  if (t.isEmpty || artiestDelen(artiest).isEmpty) return null;
  int? beste;
  for (var i = 0; i < treffers.length; i++) {
    final x = treffers[i];
    // Een duo dat Deezer onder één naam zet ("Niels Destadsbader" voor "Niels Destadsbader & Regi")
    // is hetzelfde nummer — zie [zelfdeArtiest]; Robin S en Robin Schulz niet.
    if (!zelfdeArtiest(x.artiest, artiest) || basisTitel(x.titel) != t) continue;
    final u = uitvoeringVan(x.titel);
    if (u == Uitvoering.bewerking || nooitOpRadio(x.titel)) continue;
    final b = beste;
    if (b == null) {
      beste = i;
      continue;
    }
    // Gewoon en radio zijn hier even goed — het model vroeg om het origineel OF de radioversie. De
    // lengte beslist: gemeten op 26-09-2026 was bij 9 van 25 bekende hits de gewone titel de
    // albumversie en de "(Radio Edit)" de single.
    final sx = heeftSinglelengte(x.seconden), sb = heeftSinglelengte(treffers[b].seconden);
    if (sx != sb) {
      if (sx) beste = i;
      continue;
    }
    if (x.rang > treffers[b].rang) beste = i;
  }
  return beste;
}

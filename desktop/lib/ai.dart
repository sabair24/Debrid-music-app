/// Eén vraag aan een taalmodel: van jouw zin naar een radio-opdracht.
///
/// Rauwe HTTP en geen SDK — voor Dart is er geen officiële Anthropic-bibliotheek, en `package:http`
/// staat hier al in. Het gaat om precies één aanroep, dus dat is geen gemis.
///
/// **Wat het model wél en niet doet** staat in `radioplan.dart`: het noemt artiesten, geen liedjes, en
/// alles wat het terugstuurt gaat door [leesRadioOpdracht] voordat er iets mee gebeurt. Die functie is
/// de enige grens — de API weigert getalgrenzen in een schema.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'radioplan.dart';

/// Het model. Klein werk, dus lage inspanning; zie [anthropicBody].
const String kRadioModel = 'claude-opus-5';

/// Ruim, en dat is nodig: denken staat standaard aan en die tekens tellen mee in `max_tokens`. Te
/// krap betekent `stop_reason: max_tokens` en een half antwoord dat niet te lezen valt.
const int kRadioMaxTokens = 4000;

/// De vraag zoals hij de deur uitgaat.
///
/// Apart en zuiver, zodat wat er verstuurd wordt na te kijken is zonder er een aanroep voor te doen.
/// Drie dingen die er bewust NIET in staan, elk goed voor een 400: `budget_tokens` (afgeschaft op dit
/// model), een assistent-bericht om het antwoord voor te bakken (mag niet samen met een schema), en
/// getalgrenzen in het schema zelf.
Map<String, dynamic> anthropicBody(String zin) => {
      'model': kRadioModel,
      'max_tokens': kRadioMaxTokens,
      'output_config': {
        // Dit is opzoekwerk en geen puzzel: een genre herkennen en veertig namen opnoemen. Hoge
        // inspanning kost hier alleen tijd en geld.
        'effort': 'low',
        'format': {'type': 'json_schema', 'schema': radioSchema()},
      },
      'messages': [
        {'role': 'user', 'content': radioPrompt(zin)}
      ],
    };

/// Haal de JSON uit een antwoord van de Messages-API.
///
/// Met een schema staat het antwoord gewoon in de tekstblokken; ze worden aan elkaar geplakt omdat
/// een lang antwoord over meer dan één blok kan lopen. Levert dat geen geldige JSON op, dan wordt er
/// nog één keer gekeken of er ergens een `{…}` in zit — een model dat toch een zin eromheen zet is
/// zeldzaam maar niet onmogelijk, en daarvoor een hele radio laten mislukken is zonde.
Object? jsonUitAntwoord(Object? antwoord) {
  if (antwoord is! Map) return null;
  final buf = StringBuffer();
  for (final blok in (antwoord['content'] is List ? antwoord['content'] as List : const [])) {
    if (blok is Map && blok['type'] == 'text' && blok['text'] is String) {
      buf.write(blok['text'] as String);
    }
  }
  final tekst = buf.toString().trim();
  if (tekst.isEmpty) return null;
  try {
    return jsonDecode(tekst);
  } catch (_) {/* hieronder nog één poging */}
  final open = tekst.indexOf('{');
  final dicht = tekst.lastIndexOf('}');
  if (open < 0 || dicht <= open) return null;
  try {
    return jsonDecode(tekst.substring(open, dicht + 1));
  } catch (_) {
    return null;
  }
}

/// De uitleg die de API zelf bij een fout meestuurt, of leeg.
String _reden(List<int> bytes) {
  try {
    final j = jsonDecode(utf8.decode(bytes));
    if (j is Map && j['error'] is Map) {
      final m = (j['error'] as Map)['message'];
      if (m is String && m.trim().isNotEmpty) return m.trim();
    }
  } catch (_) {/* geen JSON; dan is het getal alles wat er is */}
  return '';
}

/// Wat er misging, in gewone taal.
class AiFout implements Exception {
  const AiFout(this.uitleg);
  final String uitleg;
  @override
  String toString() => uitleg;
}

/// De vraag stellen.
class AiService {
  AiService(this.sleutelVan, {http.Client? client}) : _http = client ?? http.Client();

  /// De sleutel, als functie: hij komt uit de instellingen en die kunnen tijdens het draaien wijzigen.
  final String Function() sleutelVan;
  final http.Client _http;

  bool get beschikbaar => sleutelVan().trim().isNotEmpty;

  /// Van een zin naar een opdracht. Gooit [AiFout] met een leesbare reden.
  Future<RadioOpdracht> maakRadioplan(String zin) async {
    final sleutel = sleutelVan().trim();
    if (sleutel.isEmpty) {
      throw const AiFout('Er staat geen AI-sleutel in Instellingen. Zonder die kan de app je zin niet '
          'omzetten in een radio.');
    }
    if (zin.trim().isEmpty) throw const AiFout('Typ eerst wat je wil horen.');

    http.Response res;
    try {
      res = await _http
          .post(
            Uri.parse('https://api.anthropic.com/v1/messages'),
            headers: {
              'content-type': 'application/json',
              'x-api-key': sleutel,
              'anthropic-version': '2023-06-01',
            },
            body: jsonEncode(anthropicBody(zin)),
          )
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      throw AiFout('Kon het taalmodel niet bereiken: $e');
    }

    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const AiFout('Die AI-sleutel wordt niet geaccepteerd. Kijk hem na in Instellingen.');
    }
    if (res.statusCode == 429) {
      throw const AiFout('Het taalmodel heeft het even te druk. Probeer het zo nog eens.');
    }
    if (res.statusCode != 200) {
      // MET de reden erbij. Dit stond er als kaal "antwoordde met 400", en dat is precies het
      // antwoord waar niemand iets mee kan: de API zegt er zelf bij wát er mis is met het verzoek —
      // een veld dat niet in `required` staat, een schema dat geweigerd wordt — en die zin werd hier
      // weggegooid. Een fout die je niet kunt lezen kost een uur zoeken.
      throw AiFout('Het taalmodel antwoordde met ${res.statusCode}. ${_reden(res.bodyBytes)}'.trim());
    }

    Object? body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw const AiFout('Het antwoord van het taalmodel was niet te lezen.');
    }
    // Een weigering levert een 200 op met `stop_reason: refusal`, en dan klopt het antwoord niet met
    // het schema. Zonder deze regel zou dat als "ik snapte je zin niet" leiden.
    if (body is Map && body['stop_reason'] == 'refusal') {
      throw const AiFout('Het taalmodel wilde hier niet op antwoorden. Probeer het anders te zeggen.');
    }
    final opdracht = leesRadioOpdracht(jsonUitAntwoord(body));
    if (!opdracht.bruikbaar) {
      throw const AiFout('Ik heb er geen artiesten uit kunnen halen. Probeer het wat concreter — '
          'bijvoorbeeld "eurodance uit de jaren 90, 200 nummers".');
    }
    return opdracht;
  }
}

/// Een AI-lijst vragen (ai_lijst.dart) — op de pc rechtstreeks, op een toestel via de pc: daar staat de AI-sleutel.
///
/// Een lijst van tweehonderd nummers met reserve is een antwoord van een paar minuten. Eén HTTP-vraag die zo lang
/// openstaat, breekt onderweg (een gsm die van wifi wisselt, een time-out). Dus vraagt het toestel een taak aan
/// (`/api/ailijst`, op `maak` of `bijsturen`) en peilt het om de [kAiLijstPeiling] (`stand`) tot het antwoord er is.
library;

import 'ai_lijst.dart';

/// Om de zoveel vraagt een toestel of het antwoord er al is.
const Duration kAiLijstPeiling = Duration(seconds: 3);

/// Zo lang wacht een toestel hoogstens (de pc zelf geeft de vraag acht minuten).
const Duration kAiLijstGeduld = Duration(minutes: 9);

/// Hoe de app een AI-lijst vraagt. [lokaal]: de vragen rechtstreeks (op de pc); [ask]: via de pc (een toestel).
class AiLijstVrager {
  AiLijstVrager({this.maakLokaal, this.bijsturenLokaal, this.ask, Duration? peiling, Duration? geduld})
      : peiling = peiling ?? kAiLijstPeiling,
        geduld = geduld ?? kAiLijstGeduld;

  final Future<AiLijstVoorstel> Function(String zin)? maakLokaal;
  final Future<Bijsturing> Function(AiLijstVoorstel v, String zin)? bijsturenLokaal;
  final Future<Map<String, dynamic>> Function(String pad, Map<String, dynamic> body)? ask;
  final Duration peiling;
  final Duration geduld;

  /// Een nieuwe lijst uit [zin]. Gooit met een leesbare reden.
  Future<AiLijstVoorstel> maak(String zin) async {
    final l = maakLokaal;
    if (l != null) return l(zin);
    final uit = await _viaPc({'op': 'maak', 'zin': zin});
    final v = AiLijstVoorstel.fromJson(uit['voorstel']);
    if (v == null) throw StateError('De pc gaf geen lijst terug.');
    return v;
  }

  /// [v] bijsturen met [zin]: eerst het verschil.
  Future<Bijsturing> bijsturen(AiLijstVoorstel v, String zin) async {
    final l = bijsturenLokaal;
    if (l != null) return l(v, zin);
    final uit = await _viaPc({'op': 'bijsturen', 'zin': zin, 'voorstel': v.toJson()});
    return Bijsturing.fromJson(uit['bijsturing']);
  }

  Future<Map<String, dynamic>> _viaPc(Map<String, dynamic> vraag) async {
    final a = ask;
    if (a == null) throw StateError('Er staat geen AI-sleutel in Instellingen.');
    final start = await a('/api/ailijst', vraag);
    if (start['fout'] is String) throw StateError(start['fout'] as String);
    final taak = start['taak'];
    if (taak == null) throw StateError('De pc nam de vraag niet aan.');
    final tot = DateTime.now().add(geduld);
    while (DateTime.now().isBefore(tot)) {
      await Future<void>.delayed(peiling);
      final s = await a('/api/ailijst', {'op': 'stand', 'taak': taak});
      if (s['fout'] is String) throw StateError(s['fout'] as String);
      if (s['klaar'] == true) return s;
    }
    throw StateError('De AI deed er te lang over. Probeer het zo nog eens, of vraag minder nummers.');
  }
}

/// De pc-kant van `/api/ailijst`: de taken die lopen, en hun antwoord. [doe] voert een vraag uit (`maak` of `bijsturen`)
/// en geeft het antwoord als JSON. Een antwoord wordt één keer opgehaald; wat na [kAiLijstGeduld] niemand ophaalde,
/// verdwijnt.
class AiLijstTaken {
  AiLijstTaken(this.doe, {this.haalAlles});
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> vraag) doe;

  /// "Op dit toestel houden" op een AI-lijst (Saber: "aan = de gsm haalt de hele lijst bij de pc"): de pc haalt alles wat
  /// nog ontbreekt, op de achtergrond. Null: deze pc kan dat niet.
  final void Function(String lijstId)? haalAlles;
  final Map<String, ({DateTime sinds, Map<String, dynamic>? uit})> _taken = {};
  int _nr = 0;

  Map<String, dynamic> beantwoord(Map<String, dynamic> body) {
    final op = '${body['op'] ?? ''}';
    if (op == 'stand') {
      final id = '${body['taak'] ?? ''}';
      final t = _taken[id];
      if (t == null) return {'fout': 'Die vraag kent de pc niet (meer) — misschien is hij herstart. Vraag het opnieuw.'};
      if (t.uit == null) return {'klaar': false};
      _taken.remove(id);
      return {'klaar': true, ...t.uit!};
    }
    if (op == 'haalAlles') {
      final id = '${body['id'] ?? ''}';
      final h = haalAlles;
      if (h == null || id.isEmpty) return {'fout': 'Deze pc kan de lijst niet halen.'};
      h(id);
      return {'gestart': true};
    }
    if (op != 'maak' && op != 'bijsturen') return {'fout': 'Onbekende vraag.'};
    final nu = DateTime.now();
    _taken.removeWhere((_, t) => nu.difference(t.sinds) > kAiLijstGeduld);
    final id = '${++_nr}';
    _taken[id] = (sinds: nu, uit: null);
    doe(body).then((uit) {
      _taken[id] = (sinds: DateTime.now(), uit: uit);
    }, onError: (Object e) {
      _taken[id] = (sinds: DateTime.now(), uit: {'fout': '$e'});
    });
    return {'taak': id};
  }
}

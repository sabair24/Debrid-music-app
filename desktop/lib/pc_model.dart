/// Het taalmodel van de pc, voor een radio op een toestel (plan "eindeloos en lerend", C2).
///
/// **Waarom.** De AI-sleutel staat alleen op de pc — net als de TorBox-sleutel, en zo hoort het. Een radio op
/// de gsm kreeg daardoor nooit een lijst van het model en geen sfeeroordeel: alleen Deezer en de keuring. Sinds
/// uitlevering 2 zoekt de radio op de pc onderweg verder met het model; met dit stuk doet die op de gsm dat ook.
///
/// **Hoe.** Het toestel stelt de vraag aan de pc (`/api/radio`, `modelvraag`) en krijgt meteen een nummer
/// terug; het antwoord haalt het daarna op (`modelstand`). Zo, en niet in één verzoek, want een lijst duurt
/// 25–30 s en het toestel geeft een verzoek er hoogstens 30 (`client.dart`). De pc houdt het budget bij
/// (`modelbudget.dart`), over zijn eigen radio's en die van elk toestel samen.
library;

import 'dart:async';
import 'dart:math';

import 'aanbevelingplan.dart' show SmaakProfiel;
import 'ai.dart';
import 'modelbudget.dart';
import 'radiolijst.dart';
import 'radiosmaak.dart';
import 'tempo.dart' show Radiotempo;

// ------------------------------------------------------------------------------------------------- de draad

List<Map<String, String>> _paren(List<({String artiest, String titel})> l) => [
  for (final n in l) {'a': n.artiest, 't': n.titel},
];

List<({String artiest, String titel})> _parenUit(Object? l) => [
  if (l is List)
    for (final m in l)
      if (m is Map) (artiest: '${m['a'] ?? ''}', titel: '${m['t'] ?? ''}'),
];

List<String> _tekstenUit(Object? l) => [
  if (l is List)
    for (final s in l) '$s',
];

Map<String, dynamic> _profielNaar(SmaakProfiel p) => {
  'top': p.topArtiesten,
  'gespeeld': p.gespeeld,
  'genres': p.genres,
  'decennia': {for (final e in p.perDecennium.entries) '${e.key}': e.value},
};

SmaakProfiel _profielUit(Object? j) {
  if (j is! Map) return const SmaakProfiel();
  final d = j['decennia'];
  return SmaakProfiel(
    topArtiesten: _tekstenUit(j['top']),
    gespeeld: _tekstenUit(j['gespeeld']),
    genres: _tekstenUit(j['genres']),
    perDecennium: {
      if (d is Map)
        for (final e in d.entries)
          if (int.tryParse('${e.key}') case final k? when e.value is num) k: (e.value as num).toInt(),
    },
  );
}

// ------------------------------------------------------------------------------------------------- de pc

/// Op de pc: de modelvragen van toestellen, met het budget. Eén per server.
class Modelvragen {
  Modelvragen({
    required this.model,
    required this.budget,
    this.tempo,
    this.spoor,
    DateTime Function()? klok,
    Random? toeval,
  })  : _klok = klok ?? DateTime.now,
        _toeval = toeval ?? Random();

  /// Het tempo van zaad en kandidaten, voor de sfeervraag (`tempo.dart`); null: zonder tempo.
  final Radiotempo? tempo;

  /// Het model van de pc, of null als er geen sleutel staat.
  final AiService? Function() model;
  final Modelbudget budget;

  /// Het radiologboek van de pc: wie wat vroeg, en wat het kostte.
  final void Function(String regel)? spoor;
  final DateTime Function() _klok;
  final Random _toeval;

  final Map<String, ({DateTime op, Map<String, dynamic>? uit})> _vragen = {};

  /// Hoe lang een antwoord blijft liggen voor het opgehaald wordt.
  static const kBewaar = Duration(minutes: 10);

  /// Een vraag beginnen. Geeft `{id}`, of meteen `{fout}` (geen sleutel, budget op, onbekende soort).
  Map<String, dynamic> begin(Map<String, dynamic> v, {String toestel = '?'}) {
    _vragen.removeWhere((_, w) => _klok().difference(w.op) > kBewaar);
    final m = model();
    if (m == null) return {'fout': 'Op de pc staat geen AI-sleutel.'};
    final soort = v['soort'];
    final start = v['start'] == true;
    final radio = '$toestel:${v['radio'] ?? ''}';
    final artiest = '${v['artiest'] ?? ''}';
    final titel = v['titel'] is String && (v['titel'] as String).isNotEmpty ? v['titel'] as String : null;
    final jaar = v['jaar'] is num ? (v['jaar'] as num).toInt() : null;
    final stijlen = _tekstenUit(v['stijlen']);
    final pastNiet = _parenUit(v['pastNiet']), pastWel = _parenUit(v['pastWel']);
    final Future<Map<String, dynamic>> werk;
    if (soort == 'lijst') {
      if (!start) {
        final b = budget.lijst(radio);
        if (!b.mag) return {'fout': 'Het model wacht even: ${b.waarom}.'};
      }
      werk = m
          .maakRadiolijst(
            artiest: artiest,
            titel: titel,
            jaar: jaar,
            stijlen: stijlen,
            profiel: _profielUit(v['profiel']),
            smaak: Radiosmaak.uit('${v['smaak'] ?? ''}'),
            alGekozen: _tekstenUit(v['alGekozen']),
            pastNiet: pastNiet,
            pastWel: pastWel,
            dieper: v['dieper'] == true,
            perAanroep: () => budget.lijstGevraagd(radio, start: start),
          )
          .then(
            (l) => <String, dynamic>{
              'nummers': [
                for (final n in l) {'artiest': n.artiest, 'titel': n.titel, 'jaar': n.jaar, 'bekend': n.bekend},
              ],
            },
          );
    } else if (soort == 'sfeer') {
      if (!start) {
        final b = budget.sfeer();
        if (!b.mag) return {'fout': 'Het model wacht even: ${b.waarom}.'};
      }
      budget.sfeerGevraagd(start: start);
      final kandidaten = _parenUit(v['kandidaten']);
      werk = () async {
        // Het tempo van het zaad en van elke kandidaat, uit het Deezer-fragment — een toestel kan dat niet meten.
        final t = tempo;
        double? zaadBpm;
        var bpm = const <double?>[];
        if (t != null) {
          try {
            final alle = await t
                .vanRij([
                  (artiest: artiest, titel: titel ?? '', pad: null, seconden: null),
                  for (final k in kandidaten) (artiest: k.artiest, titel: k.titel, pad: null, seconden: null),
                ])
                .timeout(const Duration(seconds: 40));
            zaadBpm = titel == null ? null : alle.first;
            bpm = alle.sublist(1);
          } catch (_) {/* zonder tempo vraagt het model zoals voorheen */}
        }
        final weg = await m.weesSfeer(
          artiest: artiest,
          titel: titel,
          jaar: jaar,
          stijlen: stijlen,
          kandidaten: kandidaten,
          pastNiet: pastNiet,
          pastWel: pastWel,
          zaadBpm: zaadBpm,
          bpm: bpm,
        );
        return <String, dynamic>{'weg': weg.toList()..sort()};
      }();
    } else {
      return {'fout': 'Onbekende modelvraag.'};
    }
    final id = '${_klok().millisecondsSinceEpoch.toRadixString(36)}${_toeval.nextInt(1 << 30).toRadixString(36)}';
    _vragen[id] = (op: _klok(), uit: null);
    spoor?.call(
      'radio-model voor $toestel: $soort${start ? ' (start)' : ''} — "$artiest${titel == null ? '' : ' — $titel'}"',
    );
    unawaited(
      werk.then((uit) => uit, onError: (Object e) => <String, dynamic>{'fout': '$e'}).then((uit) {
        if (_vragen.containsKey(id)) _vragen[id] = (op: _vragen[id]!.op, uit: uit);
      }),
    );
    return {'id': id};
  }

  /// Waar vraag [id] staat: `{klaar: false}`, of `{klaar: true, …antwoord}` (dan is hij weg).
  Map<String, dynamic> stand(String id) {
    final w = _vragen[id];
    if (w == null) return {'klaar': true, 'fout': 'Die vraag kent de pc niet (meer).'};
    final uit = w.uit;
    if (uit == null) return {'klaar': false};
    _vragen.remove(id);
    return {'klaar': true, ...uit};
  }
}

// ------------------------------------------------------------------------------------------------- het toestel

/// Op een toestel: hetzelfde als [AiService], maar de pc stelt de vraag. [vraag] is `client.ask('/api/radio', …)`.
///
/// [radio] noemt de radio (zijn sessie), zodat de pc per radio kan tellen. [perAanroep] wordt hier genegeerd: de
/// pc telt zelf.
class PcModel extends AiService {
  PcModel(
    this.vraag, {
    required this.radio,
    this.wacht = const Duration(seconds: 2),
    this.geduld = const Duration(seconds: 120),
  }) : super(_pc);

  static String _pc() => 'pc';

  final Future<Map<String, dynamic>> Function(Map<String, dynamic> body) vraag;
  final int Function() radio;
  final Duration wacht, geduld;

  Future<Map<String, dynamic>> _vraag(Map<String, dynamic> v) async {
    final begin = await vraag({'op': 'modelvraag', 'radio': radio(), ...v});
    if (begin['fout'] is String) throw AiFout(begin['fout'] as String);
    final id = begin['id'];
    if (id is! String) throw const AiFout('De pc begon de vraag niet.');
    final tot = DateTime.now().add(geduld);
    while (DateTime.now().isBefore(tot)) {
      await Future<void>.delayed(wacht);
      final s = await vraag({'op': 'modelstand', 'id': id});
      if (s['klaar'] != true) continue;
      if (s['fout'] is String) throw AiFout(s['fout'] as String);
      return s;
    }
    throw const AiFout('De pc gaf op tijd geen antwoord van het model.');
  }

  @override
  Future<List<AiNummer>> maakRadiolijst({
    required String artiest,
    String? titel,
    int? jaar,
    List<String> stijlen = const [],
    String? genre,
    required SmaakProfiel profiel,
    Radiosmaak smaak = Radiosmaak.gemengd,
    List<String> alGekozen = const [],
    List<({String artiest, String titel})> pastNiet = const [],
    List<({String artiest, String titel})> pastWel = const [],
    void Function()? perAanroep,
    bool dieper = false,
    bool start = false,
  }) async {
    if (artiest.trim().isEmpty) return const [];
    final s = await _vraag({
      'soort': 'lijst',
      'start': start,
      'artiest': artiest,
      if (titel != null) 'titel': titel,
      if (jaar != null) 'jaar': jaar,
      'stijlen': stijlen,
      'profiel': _profielNaar(profiel),
      'smaak': smaak.name,
      'alGekozen': alGekozen.take(kModelAlGekozen).toList(),
      'pastNiet': _paren(pastNiet),
      'pastWel': _paren(pastWel),
      'dieper': dieper,
    });
    // Dezelfde grens als een antwoord van het model zelf.
    return leesNummers({'nummers': s['nummers']});
  }

  @override
  Future<Set<int>> weesSfeer({
    required String artiest,
    String? titel,
    int? jaar,
    List<String> stijlen = const [],
    required List<({String artiest, String titel})> kandidaten,
    List<({String artiest, String titel})> pastNiet = const [],
    List<({String artiest, String titel})> pastWel = const [],
    bool start = false,
    double? zaadBpm,
    List<double?> bpm = const [],
  }) async {
    if (kandidaten.isEmpty) return const {};
    // Het tempo meet de pc zelf (`tempo.dart`): een toestel heeft geen ffmpeg.
    final s = await _vraag({
      'soort': 'sfeer',
      'start': start,
      'artiest': artiest,
      if (titel != null) 'titel': titel,
      if (jaar != null) 'jaar': jaar,
      'stijlen': stijlen,
      'kandidaten': _paren(kandidaten),
      'pastNiet': _paren(pastNiet),
      'pastWel': _paren(pastWel),
    });
    final weg = s['weg'];
    return {
      if (weg is List)
        for (final v in weg)
          if (v is num && v >= 0 && v < kandidaten.length) v.toInt(),
    };
  }
}

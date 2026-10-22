// Het taalmodel van de pc voor een radio op een toestel (plan "eindeloos en lerend", C2): het toestel stelt de
// vraag, de pc doet hem met zijn eigen sleutel en houdt het budget bij — over zijn eigen radio's en die van elk
// toestel samen.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/aanbevelingplan.dart' show SmaakProfiel;
import 'package:debridmusic/ai.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/modelbudget.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/pc_model.dart';
import 'package:debridmusic/radiolijst.dart';
import 'package:debridmusic/radiosmaak.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/tempo.dart';

/// Een model zonder netwerk: onthoudt wat het gevraagd werd, en antwoordt als [klaar] dat zegt.
class _Model extends AiService {
  _Model() : super(() => 'sk-ant-toets');
  final lijsten = <Map<String, Object?>>[];
  final sfeervragen = <List<({String artiest, String titel})>>[];
  final tempi = <({double? zaad, List<double?> rij})>[];
  Completer<void> klaar = Completer<void>()..complete();
  Object? fout;

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
    perAanroep?.call();
    lijsten.add({
      'artiest': artiest,
      'titel': titel,
      'jaar': jaar,
      'top': profiel.topArtiesten,
      'decennia': profiel.perDecennium,
      'smaak': smaak,
      'alGekozen': alGekozen,
      'pastNiet': pastNiet,
      'dieper': dieper,
    });
    await klaar.future;
    if (fout != null) throw fout!;
    return const [
      AiNummer('Pommelien Thijs', 'Lisa', jaar: 2023),
      AiNummer('Metejoor', '1 Op Een Miljoen', bekend: true),
    ];
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
    sfeervragen.add(kandidaten);
    tempi.add((zaad: zaadBpm, rij: bpm));
    await klaar.future;
    return {
      for (var i = 0; i < kandidaten.length; i++)
        if (kandidaten[i].artiest == 'K3') i,
    };
  }
}

/// Een tempo zonder ffmpeg: geeft wat [antwoord] zegt.
class _NepTempo extends Radiotempo {
  _NepTempo(this.antwoord) : super(meter: Tempometer(), fragment: (a, t, s) async => null);
  final List<double?> Function(List<({String artiest, String titel, String? pad, int? seconden})> rij) antwoord;

  @override
  Future<List<double?>> vanRij(List<({String artiest, String titel, String? pad, int? seconden})> rij,
          {int tegelijk = 4}) async =>
      antwoord(rij);
}

const _profiel = SmaakProfiel(topArtiesten: ['Clouseau (40)'], perDecennium: {1990: 448}, gespeeld: ['Bazart']);

void main() {
  group('de pc', () {
    late _Model model;
    late Modelbudget budget;
    late Modelvragen mv;
    var nu = DateTime(2026, 10, 22, 10, 0);
    setUp(() {
      nu = DateTime(2026, 10, 22, 10, 0);
      model = _Model();
      budget = Modelbudget(klok: () => nu);
      mv = Modelvragen(model: () => model, budget: budget, klok: () => nu);
    });

    test('DE KERN: een vraag krijgt een nummer, het antwoord komt later, en daarna is hij weg', () async {
      model.klaar = Completer<void>();
      final b = mv.begin({
        'soort': 'lijst',
        'radio': 3,
        'start': true,
        'artiest': 'Niels Destadsbader',
      }, toestel: 'gsm');
      final id = b['id'] as String;
      expect(mv.stand(id), {'klaar': false});
      model.klaar.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final s = mv.stand(id);
      expect(s['klaar'], isTrue);
      expect([for (final n in s['nummers'] as List) (n as Map)['titel']], ['Lisa', '1 Op Een Miljoen']);
      expect(mv.stand(id)['fout'], contains('kent de pc niet'));
    });

    test('het budget geldt ook voor een toestel: per radio van dat toestel, en een start mag altijd', () async {
      for (var i = 0; i < 2; i++) {
        mv.begin({'soort': 'lijst', 'radio': 3, 'artiest': 'X'}, toestel: 'gsm');
        nu = nu.add(const Duration(minutes: 20));
      }
      // Een radio op de pc vroeg er intussen ook een: samen drie in het uur.
      budget.lijstGevraagd(99);
      nu = nu.add(const Duration(minutes: 19));
      expect(mv.begin({'soort': 'lijst', 'radio': 3, 'artiest': 'X'}, toestel: 'gsm')['fout'], contains('3 per uur'));
      expect(mv.begin({'soort': 'lijst', 'radio': 3, 'start': true, 'artiest': 'X'}, toestel: 'gsm')['id'], isNotNull);
      expect(model.lijsten, hasLength(3));
      // Per radio van dit toestel: twaalf.
      for (var i = 0; i < 9; i++) {
        mv.begin({'soort': 'lijst', 'radio': 3, 'start': true, 'artiest': 'X'}, toestel: 'gsm');
      }
      nu = nu.add(const Duration(hours: 2));
      expect(mv.begin({'soort': 'lijst', 'radio': 3, 'artiest': 'X'}, toestel: 'gsm')['fout'], contains('12 lijsten'));
      expect(
        mv.begin({'soort': 'lijst', 'radio': 3, 'artiest': 'X'}, toestel: 'ipad')['id'],
        isNotNull,
        reason: 'radio 3 van een ander toestel is een andere radio',
      );
    });

    test('een sfeervraag van een toestel: de pc meet het tempo (het toestel heeft geen ffmpeg)', () async {
      final gemeten = <String>[];
      final metTempo = Modelvragen(
        model: () => model,
        budget: budget,
        klok: () => nu,
        tempo: _NepTempo((r) {
          gemeten.addAll([for (final x in r) x.titel]);
          return [142, 94, null];
        }),
      );
      final b = metTempo.begin({
        'soort': 'sfeer',
        'start': true,
        'artiest': 'Petra',
        'titel': 'Ik Leef Voor Jou',
        'kandidaten': [
          {'a': 'Benny Neyman', 't': 'Waarom fluister ik je naam nog'},
          {'a': 'Eddy Wally', 't': 'Chérie'},
        ],
      }, toestel: 'gsm');
      for (var i = 0; i < 5 && metTempo.stand(b['id'] as String)['klaar'] != true; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(gemeten, ['Ik Leef Voor Jou', 'Waarom fluister ik je naam nog', 'Chérie']);
      expect(model.tempi.single.zaad, 142);
      expect(model.tempi.single.rij, [94, null]);
    });

    test('zonder sleutel of met een onbekende vraag: meteen een fout, en het model wordt niet gevraagd', () {
      final zonder = Modelvragen(model: () => null, budget: budget);
      expect(zonder.begin({'soort': 'lijst', 'artiest': 'X'})['fout'], contains('geen AI-sleutel'));
      expect(mv.begin({'soort': 'iets', 'artiest': 'X'})['fout'], contains('Onbekende'));
      expect(model.lijsten, isEmpty);
    });
  });

  group('aangesloten', () {
    test('de pc beantwoordt toestellen; een toestel vraagt de pc als die het kan, en telt dan zelf niet', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      final sessie = File('lib/lan/client_session.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(main.contains('      s.modelvragen = Modelvragen(\n'), isTrue);
      expect(main.contains('  final viaPc = remote != null && context.read<ClientSession>().pcHeeftModel;'), isTrue);
      expect(main.contains("        ? PcModel((v) => remote.ask('/api/radio', v), radio: () => radio.sessie)"), isTrue);
      expect(main.contains('    ..budget = viaPc ? null : _modelbudget\n'), isTrue);
      expect(sessie.contains("      pcHeeftModel = shared['radioModel'] == 'ja';"), isTrue);
    });
  });

  group('het toestel, via de echte server', () {
    late Directory map;
    late LanServer server;
    late _Model model;
    late RemoteClient c;

    setUp(() async {
      map = Directory.systemTemp.createTempSync('dm_pcmodel_');
      setAppDirForTest(map.path);
      model = _Model();
      server = LanServer(
        library: LibraryStore()
          ..rootPath = map.path
          ..configDirOverride = map.path,
        token: 'sleutel',
        state: LanStateStore(File('${map.path}/state.json')),
        pairing: PairingStore(),
        settings: AppSettings()..anthropicKey = 'sk-ant-toets',
        port: 0,
      )..modelvragen = Modelvragen(model: () => model, budget: Modelbudget());
      expect(await server.start(), isNull);
      c = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://127.0.0.1:${server.boundPort}'), token: 'sleutel'));
    });

    tearDown(() async {
      await server.dispose();
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    PcModel pc() => PcModel((v) => c.ask('/api/radio', v), radio: () => 7, wacht: const Duration(milliseconds: 5));

    test('DE KERN: een lijst en een sfeeroordeel van de pc, met alles wat het model nodig heeft', () async {
      expect((await c.config())['radioModel'], 'ja');
      final lijst = await pc().maakRadiolijst(
        artiest: 'Niels Destadsbader',
        titel: 'Vuur en vlam',
        jaar: 2026,
        profiel: _profiel,
        smaak: Radiosmaak.ontdekken,
        alGekozen: const ['Bazart - Goud'],
        pastNiet: const [(artiest: 'K3', titel: 'Dromen')],
        dieper: true,
      );
      expect(
        [for (final n in lijst) '${n.artiest} – ${n.titel} ${n.jaar} ${n.bekend}'],
        ['Pommelien Thijs – Lisa 2023 false', 'Metejoor – 1 Op Een Miljoen null true'],
      );
      final v = model.lijsten.single;
      expect(v['titel'], 'Vuur en vlam');
      expect(v['jaar'], 2026);
      expect(v['top'], ['Clouseau (40)']);
      expect(v['decennia'], {1990: 448});
      expect(v['smaak'], Radiosmaak.ontdekken);
      expect(v['alGekozen'], ['Bazart - Goud']);
      expect(v['pastNiet'], [(artiest: 'K3', titel: 'Dromen')]);
      expect(v['dieper'], isTrue);
      final weg = await pc().weesSfeer(
        artiest: 'Niels Destadsbader',
        kandidaten: const [(artiest: 'Bazart', titel: 'Goud'), (artiest: 'K3', titel: 'Dromen')],
      );
      expect(weg, {1});
    });

    test('een fout van het model komt als AiFout aan, zodat de radio doet als zonder model', () async {
      model.fout = const AiFout('Het taalmodel heeft het even te druk.');
      await expectLater(pc().maakRadiolijst(artiest: 'X', profiel: _profiel), throwsA(isA<AiFout>()));
    });

    test('zonder sleutel op de pc zegt de config "nee"', () async {
      server.settings!.anthropicKey = '';
      expect((await c.config())['radioModel'], 'nee');
    });
  });
}

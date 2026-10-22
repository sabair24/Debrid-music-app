// Wat de radio het taalmodel mag vragen (plan "eindeloos en lerend", uitlevering 2): lijsten hoogstens drie per
// uur over alle radio's, twintig minuten ertussen, twaalf per radio; sfeervragen twaalf per uur. Een start mag
// altijd. Geteld per API-aanroep — ook de tweede poging van een lijst.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:debridmusic/aanbevelingplan.dart' show SmaakProfiel;
import 'package:debridmusic/ai.dart';
import 'package:debridmusic/modelbudget.dart';
import 'package:debridmusic/radiolijst.dart';

void main() {
  late Directory map;
  setUp(() => map = Directory.systemTemp.createTempSync('dm_budget_'));
  tearDown(() {
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('lijsten', () {
    test('DE KERN: drie per uur, twintig minuten ertussen, en na een uur weer', () {
      var nu = DateTime(2026, 10, 22, 10, 0);
      final b = Modelbudget(klok: () => nu);
      expect(b.lijst(1).mag, isTrue);
      b.lijstGevraagd(1);
      nu = nu.add(const Duration(minutes: 19));
      expect(b.lijst(1).mag, isFalse);
      expect(b.lijst(1).waarom, contains('20 min'));
      nu = nu.add(const Duration(minutes: 1));
      expect(b.lijst(1).mag, isTrue);
      b.lijstGevraagd(1);
      nu = nu.add(const Duration(minutes: 20));
      b.lijstGevraagd(2); // een andere radio telt mee: de grens is over alle radio's
      nu = nu.add(const Duration(minutes: 19, seconds: 59)); // 10:59:59: drie in het laatste uur
      expect(b.lijst(1).mag, isFalse);
      expect(b.lijst(1).waarom, '3 per uur (volgende om 11:00)');
      nu = DateTime(2026, 10, 22, 11, 0, 1);
      expect(b.lijst(1).mag, isTrue, reason: 'de eerste is een uur oud');
    });

    test('een start telt voor de radio, niet voor het uur', () {
      var nu = DateTime(2026, 10, 22, 10, 0);
      final b = Modelbudget(klok: () => nu);
      for (var i = 0; i < 5; i++) {
        b.lijstGevraagd(7, start: true);
      }
      expect(b.lijst(7).mag, isTrue, reason: 'vijf starts in een uur: onderweg mag er nog altijd een');
      for (var i = 0; i < 7; i++) {
        b.lijstGevraagd(7, start: true);
        nu = nu.add(const Duration(hours: 1));
      }
      expect(b.lijst(7).mag, isFalse);
      expect(b.lijst(7).waarom, '12 lijsten voor deze radio');
      expect(b.lijst(8).mag, isTrue, reason: 'een nieuwe radio begint opnieuw');
    });

    test('DE VAL: een herstart vergeet niets (modelbudget.json), en een kapot bestand blokkeert niets', () {
      var nu = DateTime(2026, 10, 22, 10, 0);
      final pad = '${map.path}${Platform.pathSeparator}modelbudget.json';
      final b = Modelbudget(pad: pad, klok: () => nu);
      b.lijstGevraagd(1);
      nu = nu.add(const Duration(minutes: 5));
      final na = Modelbudget(pad: pad, klok: () => nu);
      expect(na.lijst(1).mag, isFalse, reason: 'de twintig minuten lopen door over een herstart');
      File(pad).writeAsStringSync('{kapot');
      expect(Modelbudget(pad: pad, klok: () => nu).lijst(1).mag, isTrue);
    });
  });

  group('sfeer', () {
    test('twaalf per uur; een start telt niet mee', () {
      var nu = DateTime(2026, 10, 22, 10, 0);
      final b = Modelbudget(klok: () => nu);
      for (var i = 0; i < 30; i++) {
        b.sfeerGevraagd(start: true);
      }
      for (var i = 0; i < 12; i++) {
        expect(b.sfeer().mag, isTrue, reason: 'vraag ${i + 1}');
        b.sfeerGevraagd();
        nu = nu.add(const Duration(minutes: 1));
      }
      expect(b.sfeer().mag, isFalse);
      expect(b.sfeer().waarom, '12 per uur (volgende om 11:00)');
      nu = DateTime(2026, 10, 22, 11, 0, 1);
      expect(b.sfeer().mag, isTrue);
    });
  });

  group('aangesloten', () {
    test('de start telt voor de radio, onderweg binnen het budget; de buurt op sfeer alleen met een model', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      bool heeft(String s) => main.contains(s);
      expect(heeft('perAanroep: () => _modelbudget.lijstGevraagd(sessie, start: true),'), isTrue, reason: 'de start');
      expect(heeft('perAanroep: () => _modelbudget.lijstGevraagd(s),'), isTrue, reason: 'een vervolglijst');
      expect(heeft('                  : _modelbudget.lijst(radio.sessie),'), isTrue,
          reason: 'op de pc het eigen budget; via de pc telt de pc');
      expect(
        heeft('vraagSfeer: ai == null ? null : (plekken) => keuring.vraagSfeer(plekken, onderweg: true),'),
        isTrue,
      );
      expect(
        heeft('    if (onderweg && b != null) {\n      final mag = b.sfeer();\n      if (!mag.mag) {'),
        isTrue,
        reason: 'een sfeervraag onderweg moet binnen het budget passen',
      );
      expect(heeft('    b?.sfeerGevraagd(start: !onderweg);'), isTrue);
      expect(
        heeft("..bijGebruik = (soort, inT, uitT) => log.line('radio-model: \$soort, \$inT in / \$uitT uit tokens')"),
        isTrue,
      );
    });
  });

  group('het model telt elke aanroep', () {
    http.Response antwoord(int aantal, String stop) => http.Response(
      jsonEncode({
        'content': [
          {
            'type': 'text',
            'text': jsonEncode({
              'nummers': [
                for (var i = 0; i < aantal; i++)
                  {'artiest': 'Artiest $i', 'titel': 'Nummer $i', 'jaar': 1995, 'bekend': true},
              ],
            }),
          },
        ],
        'stop_reason': stop,
        'usage': {'input_tokens': 2140, 'output_tokens': 3880},
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

    test('DE KERN: de tweede poging telt ook, en het logboek krijgt de tokens', () async {
      var vragen = 0;
      String? prompt;
      final ai = AiService(
        () => 'sk-ant-toets',
        client: MockClient((v) async {
          vragen++;
          prompt = (((jsonDecode(v.body) as Map)['messages'] as List).first as Map)['content'] as String;
          return vragen == 1 ? antwoord(1, 'max_tokens') : antwoord(20, 'end_turn');
        }),
      );
      final gebruik = <String>[];
      ai.bijGebruik = (soort, i, u) => gebruik.add('$soort $i/$u');
      var geteld = 0;
      await ai.maakRadiolijst(
        artiest: 'Regi',
        profiel: const SmaakProfiel(),
        perAanroep: () => geteld++,
        dieper: true,
        alGekozen: ['A - B'],
      );
      expect(geteld, 2);
      expect(gebruik, ['lijst 2140/3880', 'lijst 2140/3880']);
      expect(prompt, contains(kDieperZin));
    });

    test('een vervolglijst zegt "dieper", een start niet; en hij ziet tot 150 eerdere keuzes', () {
      final al = [for (var i = 0; i < 200; i++) 'Artiest $i - Nummer $i'];
      final start = nummersPrompt(artiest: 'Regi', profiel: const SmaakProfiel(), alGekozen: al);
      expect(start, isNot(contains(kDieperZin)));
      expect(start, contains('Artiest 149 - Nummer 149'));
      expect(start, isNot(contains('Artiest 150 - Nummer 150')));
      expect(nummersPrompt(artiest: 'Regi', profiel: const SmaakProfiel(), dieper: true), contains(kDieperZin));
    });
  });
}

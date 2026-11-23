// Een AI-lijst vragen vanaf een toestel (Saber, 23-11-2026): de AI-sleutel staat op de pc, en een lijst van 200 nummers
// duurt minuten — dus een taak en een peiling in plaats van één lange vraag. Hier: de pc-kant (AiLijstTaken) en de
// toestelkant (AiLijstVrager) samen, zonder netwerk.
import 'dart:async';

import 'package:debridmusic/ai_lijst.dart';
import 'package:debridmusic/ai_lijst_vraag.dart';
import 'package:flutter_test/flutter_test.dart';

AiLijstVoorstel _voorstel(String zin) => AiLijstVoorstel(
      naam: 'Kerst',
      zin: zin,
      hoeken: const [(naam: 'Klassiekers', aandeel: 100)],
      nummers: [LijstNummer(artiest: 'Bing Crosby', titel: 'White Christmas', hoek: 'Klassiekers')],
      reserve: [],
    );

void main() {
  test('DE KERN: het toestel vraagt een taak, peilt, en krijgt de lijst van de pc', () async {
    final klaar = Completer<void>();
    final pc = AiLijstTaken((vraag) async {
      await klaar.future;
      return {'voorstel': _voorstel('${vraag['zin']}').toJson()};
    });
    var peilingen = 0;
    final vrager = AiLijstVrager(
      ask: (pad, body) async {
        expect(pad, '/api/ailijst');
        if (body['op'] == 'stand' && ++peilingen == 2) klaar.complete();
        return pc.beantwoord(body);
      },
      peiling: const Duration(milliseconds: 5),
    );
    final v = await vrager.maak('kerstliedjes').timeout(const Duration(seconds: 5));
    expect(v.zin, 'kerstliedjes');
    expect(v.nummers.single.titel, 'White Christmas');
    expect(peilingen, greaterThanOrEqualTo(2), reason: 'gepeild tot het antwoord er was');
    expect(pc.beantwoord({'op': 'stand', 'taak': '1'})['fout'], isA<String>(), reason: 'een antwoord haal je één keer op');
  });

  test('bijsturen gaat net zo, en het verschil komt heel over', () async {
    final pc = AiLijstTaken((vraag) async {
      final v = AiLijstVoorstel.fromJson(vraag['voorstel'])!;
      expect(v.nummers.single.artiest, 'Bing Crosby');
      return {
        'bijsturing': Bijsturing(weg: const [0], erbij: [LijstNummer(artiest: 'Wham!', titel: 'Last Christmas', hoek: 'Modern')], naam: 'Kerst modern').toJson()
      };
    });
    final vrager = AiLijstVrager(ask: (_, body) async => pc.beantwoord(body), peiling: const Duration(milliseconds: 5));
    final b = await vrager.bijsturen(_voorstel('x'), 'meer modern').timeout(const Duration(seconds: 5));
    expect(b.weg, [0]);
    expect(b.erbij.single.titel, 'Last Christmas');
    expect(b.erbij.single.hoek, 'Modern');
    expect(b.naam, 'Kerst modern');
  });

  test('een fout van de AI komt als leesbare fout bij het toestel', () async {
    final pc = AiLijstTaken((_) async => throw StateError('Er staat geen AI-sleutel in Instellingen.'));
    final vrager = AiLijstVrager(ask: (_, body) async => pc.beantwoord(body), peiling: const Duration(milliseconds: 5));
    await expectLater(vrager.maak('x'), throwsA(predicate((e) => '$e'.contains('geen AI-sleutel'))));
  });

  test('DE GRENS: te lang is een fout, geen eeuwig wachten; zonder pc en zonder sleutel ook', () async {
    final pc = AiLijstTaken((_) => Completer<Map<String, dynamic>>().future);
    final vrager = AiLijstVrager(
        ask: (_, body) async => pc.beantwoord(body),
        peiling: const Duration(milliseconds: 5),
        geduld: const Duration(milliseconds: 40));
    await expectLater(vrager.maak('x'), throwsA(predicate((e) => '$e'.contains('te lang'))));
    await expectLater(AiLijstVrager().maak('x'), throwsA(isA<StateError>()));
    expect(pc.beantwoord({'op': 'iets'})['fout'], isA<String>());
  });

  test('op de pc zelf: rechtstreeks, zonder taak', () async {
    final vrager = AiLijstVrager(maakLokaal: (zin) async => _voorstel(zin));
    expect((await vrager.maak('lokaal')).zin, 'lokaal');
  });
}

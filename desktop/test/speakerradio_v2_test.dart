// Speakerradio v2 (23-10-2026): de radio van de pc op een speaker, bediend vanaf elk toestel.
//
// Een radio op de KEF draait op de pc. Op de gsm stond wel "radio …" bij de zone, maar zonder knoppen: geen "Past" of
// "Houden" bij een mooi nummer, geen "Radio afsluiten", en niets over wat de radio deed. En "Radio afsluiten" op de pc
// liet de speaker zijn rij uitspelen. Hier: wat de zone meestuurt, wat een toestel stuurt, en wat de pc ermee doet.
import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/zones.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/zone_lijst.dart';
import 'package:debridmusic/zone_speler.dart';

const _nu = 10000000;

String _lees(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

ZoneStaat _kef({String radio = 'Tamino', String status = '', String past = '', bool gehaald = false, bool houden = false}) =>
    ZoneStaat(
      id: 'spk:192.168.0.100',
      soort: ZoneSoort.speaker,
      naam: 'LS50',
      online: true,
      playing: true,
      trackId: 'nr7',
      titel: 'Indigo Night',
      artiest: 'Tamino',
      positionMs: 1000,
      durationMs: 240000,
      opMs: _nu,
      lengte: 5,
      radio: radio,
      radioStatus: status,
      radioPast: past,
      radioGehaald: gehaald,
      radioHouden: houden,
    );

void main() {
  test('de zone draagt wat de radio doet en wat er over het nummer gezegd is — heen en terug', () {
    final z = _kef(status: 'Zoekt het volgende nummer…', past: 'past', gehaald: true, houden: true);
    final terug = ZoneStaat.fromJson(z.toJson());
    expect(terug.radioStatus, 'Zoekt het volgende nummer…');
    expect(terug.radioPast, 'past');
    expect(terug.radioGehaald, isTrue);
    expect(terug.radioHouden, isTrue);
    expect(terug, z);
    expect(terug == _kef(), isFalse, reason: 'een ander oordeel is een andere stand: anders gaat hij niet rond');
    for (final ander in [_kef(status: 's'), _kef(past: 'past'), _kef(gehaald: true), _kef(houden: true)]) {
      expect(ander == _kef(), isFalse, reason: 'elk veld apart telt: ${ander.toJson()}');
    }
    // Van een oude pc: niets erover — gewoon leeg.
    final oud = ZoneStaat.fromJson({'id': 'spk:x', 'soort': 'speaker', 'naam': 'Move', 'radio': 'Sade'});
    expect((oud.radioStatus, oud.radioPast, oud.radioGehaald, oud.radioHouden), ('', '', false, false));
    expect(_kef().toJson().containsKey('radioStatus'), isFalse, reason: 'leeg reist niet mee');
  });

  group('op de pc', () {
    late Directory map;
    late LanStateStore staat;
    late ZoneRegister reg;

    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_spkradio_reg_');
      staat = LanStateStore(File('${map.path}/state.json'));
      reg = ZoneRegister(state: staat, pcId: 'pc-THUIS', pcNaam: 'THUIS');
    });

    tearDown(() async {
      await reg.dispose();
      await staat.dispose();
      map.deleteSync(recursive: true);
    });

    SpeakerStand stand(String radio) => (
          id: '192.168.0.100',
          naam: 'LS50',
          trackId: 'nr7',
          index: 0,
          lengte: 5,
          speelt: true,
          positieMs: 0,
          duurMs: 240000,
          opMs: _nu,
          volume: 30,
          radio: radio,
        );

    test('een speaker met de radio van de pc vraagt main wat erover te zeggen valt; zonder radio niet', () {
      final gevraagd = <String>[];
      reg.radioOpSpeaker = (speaker, trackId) {
        gevraagd.add('$speaker|$trackId');
        return (status: 'Even stil: Soulseek antwoordt niet', past: 'pastNiet', gehaald: true, houden: false);
      };
      reg.zetSpeakers([stand('Tamino')]);
      final z = reg.lijst().firstWhere((z) => z.id == 'spk:192.168.0.100');
      expect(gevraagd, contains('192.168.0.100|nr7'));
      expect(z.radioStatus, 'Even stil: Soulseek antwoordt niet');
      expect(z.radioPast, 'pastNiet');
      expect(z.radioGehaald, isTrue);

      gevraagd.clear();
      reg.zetSpeakers([stand('')]);
      final zonder = reg.lijst().firstWhere((z) => z.id == 'spk:192.168.0.100');
      expect(gevraagd, isEmpty, reason: 'geen radio: niets te vragen');
      expect(zonder.radioStatus, isEmpty);
    });

    test('herzie stuurt opnieuw rond', () async {
      var keer = 0;
      final sub = reg.veranderd.listen((_) => keer++);
      reg.herzie();
      await Future<void>.delayed(Duration.zero);
      expect(keer, 1);
      await sub.cancel();
    });
  });

  group('op een toestel', () {
    test('de knoppen sturen een opdracht met het spelende nummer; afsluiten ook', () {
      fakeAsync((fa) {
        final lijst = ZoneLijst(hier: 'dev:gsm-1', klok: () => _nu)
          ..zet({
            'nu': _nu,
            'zones': [_kef().toJson()],
          });
        final gestuurd = <Map<String, dynamic>>[];
        final z = ZoneSpeler(
          lijst: lijst,
          zoneId: 'spk:192.168.0.100',
          nummer: (_) => null,
          idVan: (t) => t.title,
          hoesVan: (_) => null,
          stuur: (op) async {
            gestuurd.add(op);
            return null;
          },
          klok: () => _nu,
        );
        expect(z.radioVanDePc, isTrue);
        String? fout = 'x';
        unawaited(z.radioOordeel('past').then((f) => fout = f));
        fa.flushMicrotasks();
        expect(gestuurd.last, {'cmd': 'radioOordeel', 'wat': 'past', 'trackId': 'nr7'});
        expect(fout, isNull);
        unawaited(z.radioStop());
        fa.flushMicrotasks();
        expect(gestuurd.last, {'cmd': 'radioStop'});

        // Geen radio meer: dan zijn het ook geen radioknoppen.
        lijst.zet({
          'nu': _nu,
          'zones': [_kef(radio: '').toJson()],
        });
        expect(z.radioVanDePc, isFalse);
        z.dispose();
      });
    });

    test('een toestelzone met een radio is niet de radio van de pc', () {
      final lijst = ZoneLijst(hier: 'dev:gsm-1', klok: () => _nu)
        ..zet({
          'nu': _nu,
          'zones': [
            const ZoneStaat(id: 'dev:ipad', soort: ZoneSoort.tablet, naam: 'iPad', online: true, trackId: 'a', radio: 'Sade')
                .toJson(),
          ],
        });
      final z = ZoneSpeler(
          lijst: lijst,
          zoneId: 'dev:ipad',
          nummer: (_) => null,
          idVan: (t) => t.title,
          hoesVan: (_) => null,
          stuur: (_) async => null);
      expect(z.radioMode, isTrue);
      expect(z.radioVanDePc, isFalse, reason: 'die radio draait op de iPad zelf');
      z.dispose();
    });
  });

  group('over de lijn', () {
    late Directory map;
    late LanServer server;
    late RemoteClient c;

    setUp(() async {
      map = Directory.systemTemp.createTempSync('dm_spkradio_cmd_');
      server = LanServer(
        library: LibraryStore()..rootPath = map.path,
        token: 'sleutel',
        state: LanStateStore(File('${map.path}/state.json')),
        pairing: PairingStore(),
        port: 0,
      );
      expect(await server.start(), isNull);
      c = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://127.0.0.1:${server.boundPort}'), token: 'sleutel'));
    });

    tearDown(() async {
      c.close();
      await server.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      map.deleteSync(recursive: true);
    });

    test('de opdracht komt bij main met de speaker, de soort en het nummer; een reden komt terug als 409', () async {
      final kreeg = <String>[];
      server.bijSpeakerRadioOpdracht = (speaker, cmd, op) async {
        kreeg.add('$speaker|$cmd|${op['wat'] ?? ''}|${op['trackId'] ?? ''}');
        return op['wat'] == 'weg' ? 'Dat nummer haalde de radio niet: het blijft staan.' : null;
      };
      final a = await c.ask('/api/zone/cmd', {'zone': 'spk:192.168.0.100', 'cmd': 'radioOordeel', 'wat': 'houden', 'trackId': 'nr7'});
      expect(a['bezorgd'], 1);
      await c.ask('/api/zone/cmd', {'zone': 'spk:192.168.0.100', 'cmd': 'radioStop'});
      expect(kreeg, ['192.168.0.100|radioOordeel|houden|nr7', '192.168.0.100|radioStop||']);
      await expectLater(
        c.ask('/api/zone/cmd', {'zone': 'spk:192.168.0.100', 'cmd': 'radioOordeel', 'wat': 'weg', 'trackId': 'nr7'}),
        throwsA(isA<RemoteException>().having((e) => e.statusCode, 'status', 409)),
      );
    });

    test('een pc zonder die haak zegt dat hij bijgewerkt moet worden', () async {
      await expectLater(
        c.ask('/api/zone/cmd', {'zone': 'spk:192.168.0.100', 'cmd': 'radioStop'}),
        throwsA(isA<RemoteException>()
            .having((e) => e.statusCode, 'status', 409)
            .having((e) => '$e', 'tekst', contains('werk hem bij'))),
      );
    });
  });

  test('aangesloten: de pc vult de zone en voert de opdrachten uit; het scherm toont knoppen, status en afsluiten', () {
    final m = _lees('lib/main.dart');
    expect(m, contains('s.bijSpeakerRadioOpdracht = (speaker, cmd, op) => bedienSpeakerRadio('));
    expect(m, contains('s.zones.radioOpSpeaker = (speaker, trackId) => radioOpSpeakerVan('));
    expect(m, contains('radio.addListener(herzieRadioInZone);'));
    expect(m, contains('radioSfeer.addListener(herzieRadioInZone);'));
    expect(m, contains('oordelen.addListener(herzieRadioInZone);'));
    // Dezelfde handelingen als de knoppen op het scherm van de pc.
    final bedien = m.substring(m.indexOf('Future<String?> bedienSpeakerRadio({'));
    final lijf = bedien.substring(0, bedien.indexOf('\n}\n'));
    for (final s in [
      'await radioPast(radio, sfeer, t);',
      'await radioPastNiet(radio, sfeer, t);',
      'await radioHouden(oordelen, lib, dm, t);',
      'await radioWeg(radio, oordelen, t, opAfstand: false);',
      'radio.stop();',
    ]) {
      expect(lijf, contains(s));
    }
    expect(m, contains('final zin = await radioPastNiet(context.read<RadioBesturing>(), context.read<RadioSfeer>(), t);'));
    expect(m, contains('if (zone != null && !isTv && !_radioOpGekozenZone(context)) return _ZoneRadioOordeel(zone: zone, naast: naast);'));
    expect(m, contains('onPressed: () => unawaited(zone.radioStop()),'));
    expect(m, contains("final s = p.radioVanDePc ? p.zone?.radioStatus ?? '' : '';"));
  });
}

// Nu speelt op de gsm (Saber, 20-10-2026): de kwaliteit aantikken toont wat je echt hoort en wat het
// bestand echt is; de volumezin staat daar en niet naast de badge; de streamknop staat naast de kwaliteit
// en alleen als er een toestel is; en de bedieningsrij staat in het midden.
import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/kwaliteit_blad.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/luidheid_keuze.dart';
import 'package:debridmusic/speakers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

RemoteClient _pc(List<Map<String, Object>> toestellen, List<String> vragen) => RemoteClient(
      RemoteEndpoint(baseUrl: Uri.parse('http://127.0.0.1:1'), token: 'x'),
      client: MockClient((r) async {
        vragen.add(r.url.path);
        return http.Response(jsonEncode(toestellen), 200, headers: {'content-type': 'application/json'});
      }),
    );

void main() {
  group('de streamknop alleen als er een toestel is', () {
    test('DE KERN: geen toestellen, geen knop; wel toestellen, wel knop', () async {
      final leeg = SpeakerTarget()..client = _pc(const [], []);
      await leeg.kijkRond();
      expect(leeg.heeftToestellen, isFalse);

      final vol = SpeakerTarget()..client = _pc(const [{'id': 'sonos-1', 'name': 'Huiskamer', 'kind': 'upnp'}], []);
      var gemeld = 0;
      vol.addListener(() => gemeld++);
      await vol.kijkRond();
      expect(vol.heeftToestellen, isTrue);
      expect(vol.gevonden.single.name, 'Huiskamer');
      expect(gemeld, 1, reason: 'de knop luistert met watch en moet het horen');
    });

    test('de pc wordt hoogstens eens per tien minuten gevraagd: zoeken is drie seconden SSDP', () async {
      final vragen = <String>[];
      final s = SpeakerTarget()..client = _pc(const [], vragen);
      await Future.wait([s.kijkRond(), s.kijkRond()]);
      await s.kijkRond();
      expect(vragen, ['/api/cast/devices']);
    });

    test('zonder koppeling met de pc wordt er niets gevraagd', () async {
      final s = SpeakerTarget();
      await s.kijkRond();
      expect(s.heeftToestellen, isFalse);
    });
  });

  group('de kwaliteitsregel', () {
    testWidgets('de streamknop staat achteraan, en het geheel in het midden', (t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: KwaliteitsRegel(
                kwaliteit: SizedBox(width: 120, height: 24, key: ValueKey('badge')),
                naast: SizedBox(width: 48, height: 48, key: ValueKey('stream')),
              ),
            ),
          ),
        ),
      ));
      final vak = t.getRect(find.byType(KwaliteitsRegel));
      final badge = t.getRect(find.byKey(const ValueKey('badge')));
      final stream = t.getRect(find.byKey(const ValueKey('stream')));
      expect(stream.left, greaterThanOrEqualTo(badge.right), reason: 'naast de kwaliteit');
      expect(((badge.left - vak.left) - (vak.right - stream.right)).abs(), lessThan(1), reason: 'gecentreerd');
    });
  });

  group('het kwaliteitsblad', () {
    test('onderweg: wat de pc stuurt, en wat het bestand is', () {
      final zin = nuHoorZin(nu: 'FLAC · 16/44.1', bestand: 'FLAC · 24/96', omgezet: true);
      expect(zin, contains('16/44.1 in plaats van FLAC · 24/96'));
      expect(zin, contains('Thuis op wifi'));
    });

    test('DE KERN: thuis op wifi hoor je het bestand zoals het is', () {
      expect(nuHoorZin(nu: 'FLAC · 24/96', bestand: 'FLAC · 24/96', omgezet: false), 'Je hoort het bestand zoals het is.');
    });

    test('bij streamen: naar welk toestel', () {
      expect(nuHoorZin(nu: 'x', bestand: 'x', omgezet: false, speaker: 'Huiskamer'), 'Speelt op Huiskamer.');
    });

    test('wat het bestand echt is: ook als het nog niet gemeten is, staat dat er', () {
      expect(bestandRegels(null, kopSampleRate: 44100, kopBits: 16).single, startsWith('Nog niet gemeten'));
    });

    test('een beschadigd bestand zegt het als eerste', () {
      const o = Echtheidsoordeel(
          bits: Bitdiepte.onbekend, boven: Bovenband.onbekend, band: Bandbreedte.doorlopend, integriteit: Integriteit.fout);
      expect(bestandRegels(o, kopSampleRate: 44100, kopBits: 16).first, startsWith('Beschadigd'));
    });

    test('opgeschaald: wat erin zit, en de controlesom', () {
      const o = Echtheidsoordeel(
          bits: Bitdiepte.spreektNietTegen,
          gebruikteBits: 24,
          boven: Bovenband.leeg,
          band: Bandbreedte.doorlopend,
          integriteit: Integriteit.klopt);
      final r = bestandRegels(o, kopSampleRate: 96000, kopBits: 24);
      expect(r.first, startsWith('Wat erin zit: 24/44'));
      expect(r.last, startsWith('Controlesom klopt'));
    });

    test('een muur rond 20 kHz: met "niet zeker"', () {
      const o = Echtheidsoordeel(
          bits: Bitdiepte.onbekend, boven: Bovenband.onbekend, band: Bandbreedte.vermoedelijk, afkapHz: 20200);
      expect(bestandRegels(o, kopSampleRate: 44100, kopBits: 16).first, contains('niet zeker'));
    });
  });

  group('bedrading (gelezen uit lib/main.dart)', () {
    final bron = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');

    test('de badge is de knop naar het blad, de streamknop staat ernaast, de volumezin niet meer', () {
      expect(bron, contains('kwaliteit: t.sizeBytes > 0 ? _kwaliteitKnop(context, p, t, cast) : null,\n'
          '            naast: const _SpeakerButton(iconSize: 22),'));
      expect(bron, contains('onPressed: () => _toonKwaliteitBlad(context, p, t, cast),'));
      expect(bron, contains("kop('Gelijk volume'),"), reason: 'de volumezin staat in het blad');
    });

    test('de streamknop toont zich alleen met een toestel', () {
      expect(bron, contains('unawaited(target.kijkRond());\n    if (!target.heeftToestellen) return const SizedBox.shrink();'));
    });

    test('DE KERN: gestapeld staat de afspeelknop in het midden en de streamknop niet in de rij', () {
      expect(bron, contains('          if (gestapeld) ...[\n            const Visibility(\n              visible: false,'));
      expect(bron, contains('              child: _WachtrijKnop(maat: 24),'));
      expect(bron, contains('          if (!gestapeld) ...[\n            const SizedBox(width: 12),\n            const _SpeakerButton(iconSize: 24),'));
    });
  });
}

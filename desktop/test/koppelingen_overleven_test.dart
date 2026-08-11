/// Wat er nooit meer mag gebeuren: dat je hele huis vol toestellen buiten staat.
///
/// **Het incident, 11-08-2026.** Op de telefoon stond "je pc staat uit — afspelen niet", terwijl de
/// pc gewoon antwoordde: ping 13 ms, `/health` 200 vanaf datzelfde toestel. Nagemeten gaven ALLE 19
/// koppelingen uit `grants.json` een 401 op `/api/catalog`, op localhost, op het LAN-adres én via
/// Tailscale. Na de pc-app te herstarten werkte dezelfde sleutel meteen weer.
///
/// In de code is er geen enkel pad dat de kaarten binnen één proces leegt — `revokeAll()` heeft nul
/// aanroepers. Wat er wél kan: het inlezen mislukt stil, of een tweede kopie van de app schrijft met
/// een lege winkel over het bestand heen. Deze toetsen dichten allebei die gaten.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/tokens.dart';

void main() {
  late Directory krab;
  late File bestand;

  setUp(() {
    krab = Directory.systemTemp.createTempSync('dm_koppel_');
    bestand = File('${krab.path}${Platform.pathSeparator}grants.json');
  });
  tearDown(() {
    try {
      krab.deleteSync(recursive: true);
    } catch (_) {}
  });

  GrantStore winkel() => GrantStore(file: bestand);

  void schrijfKoppelingen(int aantal) {
    bestand.writeAsStringSync(jsonEncode([
      for (var i = 0; i < aantal; i++)
        {
          'deviceId': 'toestel$i',
          'deviceName': 'Toestel $i',
          'token': 'sleutel$i',
          'platform': 'android',
          'grantedAt': 1000 + i,
        }
    ]));
  }

  test('een lege winkel schrijft NOOIT over bestaande koppelingen heen', () async {
    // Dit is de kern. Een tweede kopie van de app die niet aan de poort kwam maar wél naar dezelfde
    // map schrijft, had met één `save()` negentien koppelingen kunnen wissen — en dan staat elk
    // toestel in huis buiten zonder dat iemand iets ingetrokken heeft.
    schrijfKoppelingen(19);

    final leeg = winkel(); // nooit geladen: precies de toestand van zo'n tweede kopie
    expect(leeg.all, isEmpty);
    await leeg.save();

    final naOpSchijf = jsonDecode(bestand.readAsStringSync()) as List;
    expect(naOpSchijf.length, 19, reason: 'de negentien horen er nog te staan');
  });

  test('maar een lege winkel op een leeg bestand mag wel schrijven', () async {
    // Anders zou een verse installatie nooit zijn eerste bestand aanmaken.
    bestand.writeAsStringSync('[]');
    await winkel().save();
    expect(jsonDecode(bestand.readAsStringSync()), isEmpty);
  });

  test('een gevulde winkel schrijft gewoon', () async {
    schrijfKoppelingen(3);
    final w = winkel();
    await w.load();
    w.mint(deviceId: 'nieuw', deviceName: 'Nieuw', platform: 'ios');
    await w.save();
    expect((jsonDecode(bestand.readAsStringSync()) as List).length, 4);
  });

  group('het inlezen meldt wat het deed', () {
    test('gelukt: het aantal staat in het logboek', () async {
      schrijfKoppelingen(19);
      final regels = <String>[];
      final w = winkel()..meldlog = regels.add;
      await w.load();
      expect(w.all.length, 19);
      expect(regels.join('\n'), contains('19'));
    });

    test('een onleesbaar bestand MELDT dat, in plaats van stil alles te weigeren', () async {
      // Dit is wat een avond zoeken kostte: het enige spoor was een debugPrint, en die gooit een
      // release-build weg. Van buitenaf is "het inlezen mislukte" niet te onderscheiden van "deze
      // koppeling is ingetrokken".
      bestand.writeAsStringSync('{dit is geen lijst');
      final regels = <String>[];
      final w = winkel()..meldlog = regels.add;
      await w.load();
      expect(w.all, isEmpty);
      expect(regels.join('\n').toLowerCase(), contains('geweigerd'),
          reason: 'het logboek moet zeggen dat hierdoor élk toestel buiten staat');
    });

    test('geen bestand is geen fout, maar wordt wel gemeld', () async {
      final regels = <String>[];
      await (winkel()..meldlog = regels.add).load();
      expect(regels, isNotEmpty);
    });
  });

  test('opnieuw inlezen na een mislukking herstelt de koppelingen', () async {
    // De winkel mag na een mislukte lees niet in een kapotte toestand blijven staan.
    bestand.writeAsStringSync('kapot');
    final w = winkel();
    await w.load();
    expect(w.all, isEmpty);

    schrijfKoppelingen(5);
    await w.load();
    expect(w.all.length, 5);
  });
}

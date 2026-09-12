/// Koppelingen die blijven staan, ook als er twee kopieën van de app draaien.
///
/// **Waarom dit er is.** Saber op 12-09-2026: "ik ben het beu om na elke update weer te moeten
/// ontkoppelen van de pc en weer te koppelen". Diezelfde ochtend gemeten: twee kopieën van de app
/// tegelijk — de tweede kreeg de poort niet (10048) maar schreef wél naar dezelfde map — `grants.json`
/// ging van 45 koppelingen naar 35, en de telefoon werd een ochtend lang geweigerd met een sleutel
/// die hij een dag eerder van deze pc had gekregen.
///
/// Drie regels houden dat tegen: opslaan voegt samen met wat er op schijf staat, een toestel houdt
/// zijn vorige sleutels, en een kopie zonder poort schrijft niets. Wat je met opzet ontkoppelt,
/// blijft ontkoppeld — anders doet die knop niets.
library;

import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/lan/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory map;
  late File bestand;

  setUp(() {
    map = Directory.systemTemp.createTempSync('koppelingen_');
    bestand = File('${map.path}${Platform.pathSeparator}grants.json');
  });

  tearDown(() {
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  void schrijf(List<Map<String, dynamic>> lijst) => bestand.writeAsStringSync(jsonEncode(lijst));

  List<Map<String, dynamic>> gelezen() => [
        for (final e in jsonDecode(bestand.readAsStringSync()) as List)
          (e as Map).cast<String, dynamic>(),
      ];

  Map<String, dynamic> koppeling(String id, String token, {int grantedAt = 1}) => {
        'deviceId': id,
        'deviceName': id,
        'token': token,
        'platform': 'android',
        'grantedAt': grantedAt,
      };

  test('DE KERN: opslaan verliest geen toestel dat alleen op schijf staat', () async {
    schrijf([koppeling('telefoon', 'aaa')]);
    final winkel = GrantStore(file: bestand);
    await winkel.load();

    // Ondertussen zet een tweede kopie van de app er een toestel bij dat deze winkel niet kent.
    schrijf([koppeling('telefoon', 'aaa'), koppeling('tv', 'bbb')]);
    await winkel.save();

    expect(gelezen().map((e) => e['deviceId']), containsAll(<String>['telefoon', 'tv']),
        reason: 'de tv is zijn koppeling kwijt en moet opnieuw koppelen');
    expect(winkel.accepts('bbb'), isTrue);
  });

  test('DE KERN: een vorige sleutel van hetzelfde toestel blijft geldig', () async {
    // Twee regels voor één toestel: zo zag het bestand eruit nadat twee gescheiden lijsten
    // samengevoegd waren.
    schrijf([
      koppeling('telefoon', 'oud', grantedAt: 1),
      koppeling('telefoon', 'nieuw', grantedAt: 2),
    ]);
    final winkel = GrantStore(file: bestand);
    await winkel.load();

    expect(winkel.byDevice('telefoon')!.token, 'nieuw');
    expect(winkel.accepts('nieuw'), isTrue);
    expect(winkel.accepts('oud'), isTrue,
        reason: 'de telefoon heeft die sleutel nog, en moet dus opnieuw koppelen');

    await winkel.save();
    final terug = gelezen();
    expect(terug, hasLength(1), reason: 'één toestel hoort één regel te zijn');
    expect(terug.single['oudereTokens'], ['oud']);
  });

  test('DE VAL: wat je ontkoppelt komt niet terug via het samenvoegen', () async {
    schrijf([koppeling('telefoon', 'aaa'), koppeling('tv', 'bbb')]);
    final winkel = GrantStore(file: bestand);
    await winkel.load();

    expect(winkel.revoke('tv'), isTrue);
    await winkel.save();

    expect(gelezen().map((e) => e['deviceId']), ['telefoon'],
        reason: 'ontkoppelen doet niets als opslaan het toestel van schijf terughaalt');
    expect(winkel.accepts('bbb'), isFalse);
  });

  test('DE GRENS: een kopie zonder poort schrijft niets', () async {
    schrijf([koppeling('telefoon', 'aaa'), koppeling('tv', 'bbb')]);
    final winkel = GrantStore(file: bestand)..alleenLezen = true;
    await winkel.load();
    // Eén toestel ontkoppelen, niet alles: bij een LEGE winkel grijpt de oudere klep al in
    // ("leeg schrijft nooit over gevuld"), en dan bewijst deze toets niets over alleen-lezen.
    winkel.revoke('tv');
    await winkel.save();

    expect(gelezen(), hasLength(2),
        reason: 'de tweede kopie zette haar eigen beeld over de echte lijst heen');
  });

  test('DE GRENS: leeg schrijft nooit over gevuld', () async {
    schrijf([koppeling('telefoon', 'aaa')]);
    final winkel = GrantStore(file: bestand); // niets geladen: leeg geheugen
    await winkel.save();
    expect(gelezen(), hasLength(1));
  });
}

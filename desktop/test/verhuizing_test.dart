/// De verhuizing die hoort bij het weghalen van de macOS-sandbox.
///
/// **Waarom dit bestaat.** De Mac-app kon zichzelf niet bijwerken: binnen de sandbox mag hij niet
/// buiten zijn eigen container schrijven, en een script dat hij start erft die beperking. Dus is de
/// sandbox eraf gegaan — en daarmee verhuist `getApplicationSupportDirectory` naar een heel andere
/// map. Zonder deze stap komt de app op alsof hij nooit gekoppeld was: geen pc, geen login, geen
/// hoezen, en een lege wachtrij.
///
/// Het gaat om zo'n tweehonderd megabyte en om de enige kopie die er is, dus de twee dingen die
/// echt moeten kloppen zijn: nooit over bestaande gegevens heen, en één keer.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/paths.dart';

void main() {
  late Directory tijdelijk;

  setUp(() => tijdelijk = Directory.systemTemp.createTempSync('verhuis'));
  tearDown(() => tijdelijk.deleteSync(recursive: true));

  Directory map(String naam, {String? met}) {
    final d = Directory('${tijdelijk.path}/$naam')..createSync(recursive: true);
    if (met != null) File('${d.path}/paired_server.json').writeAsStringSync(met);
    return d;
  }

  test('het pad van vroeger klopt met waar de sandbox het zette', () {
    expect(
      sandboxPad('/Users/ik'),
      '/Users/ik/Library/Containers/com.debridmedia.music/Data/Library/'
      'Application Support/com.debridmedia.music/DebridMusic',
    );
  });

  test('de oude map gaat mee, met alles erin', () async {
    final oud = map('oud', met: 'de koppeling');
    final nieuw = Directory('${tijdelijk.path}/nieuw/DebridMusic');

    expect(await verhuisMap(oud, nieuw), isTrue);
    expect(await File('${nieuw.path}/paired_server.json').readAsString(), 'de koppeling');
    // Hernoemd en niet gekopieerd: er blijft geen tweede kopie van 200 MB achter.
    expect(await oud.exists(), isFalse);
  });

  test('nooit over bestaande gegevens heen', () async {
    final oud = map('oud', met: 'oud');
    final nieuw = map('nieuw', met: 'wat er al stond');

    expect(await verhuisMap(oud, nieuw), isFalse);
    expect(await File('${nieuw.path}/paired_server.json').readAsString(), 'wat er al stond');
    // En de oude blijft staan, zodat er niets onbereikbaar wordt.
    expect(await oud.exists(), isTrue);
  });

  test('een lege map op de nieuwe plek blokkeert de verhuizing niet', () async {
    // Zo'n map blijft over als een eerdere start halverwege stopte. Zou die tellen als "er staat
    // al iets", dan kwam de verhuizing nooit meer aan de beurt en was alles voorgoed weg.
    final oud = map('oud', met: 'de koppeling');
    final nieuw = map('nieuw');

    expect(await verhuisMap(oud, nieuw), isTrue);
    expect(await File('${nieuw.path}/paired_server.json').readAsString(), 'de koppeling');
  });

  test('een tweede keer doet niets meer', () async {
    final oud = map('oud', met: 'de koppeling');
    final nieuw = Directory('${tijdelijk.path}/nieuw/DebridMusic');

    expect(await verhuisMap(oud, nieuw), isTrue);
    expect(await verhuisMap(oud, nieuw), isFalse);
  });

  test('zonder oude map gebeurt er niets', () async {
    // Het gewone geval voor iedereen die de app na deze wijziging voor het eerst installeert.
    expect(
      await verhuisMap(
        Directory('${tijdelijk.path}/bestaat-niet'),
        Directory('${tijdelijk.path}/nieuw'),
      ),
      isFalse,
    );
  });
}

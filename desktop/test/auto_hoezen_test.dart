/// De afspraak tussen de hoezenschrijver hier en de provider in Kotlin.
///
/// **Waarom dit een toets verdient.** `HoesProvider.kt` accepteert precies één vorm — zestien
/// hexcijfers en `.jpg` — en weigert al het andere met een FileNotFoundException. Er is geen
/// toetsraamwerk dat Dart en Kotlin tegelijk draait, dus de enige plek waar die afspraak
/// gecontroleerd kán worden is hier. Wijkt de naam af, dan is er geen foutmelding en geen rode
/// toets: de tegels in de auto blijven gewoon grijs, en dat merk je pas achter het stuur.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/auto_hoezen.dart';

/// Dezelfde uitdrukking als `NAAM` in HoesProvider.kt. Verandert de ene, dan moet de andere mee.
final regexUitKotlin = RegExp(r'^[0-9a-f]{16}\.jpg$');

Uint8List hoes(int zaad, {int lengte = 400}) =>
    Uint8List.fromList([for (var i = 0; i < lengte; i++) (zaad + i * 7) % 256]);

void main() {
  test('de naam heeft precies de vorm die de provider accepteert', () {
    expect(hoesNaamVoor(hoes(1)), matches(regexUitKotlin));
  });

  test('dezelfde hoes levert dezelfde naam — ook in een volgend proces', () {
    // Genoemd naar de inhoud, met md5. NIET met Object.hash: dat krijgt bij elke start van Dart een
    // andere zaadwaarde, en dan schrijft elke sessie de hele platenkast opnieuw weg.
    expect(hoesNaamVoor(hoes(42)), hoesNaamVoor(hoes(42)));
    // Deze waarde is buiten Dart uitgerekend (node, md5 over dezelfde bytes). Dat is het hele punt:
    // een getal dat in een ánder proces bepaald is, kan niet meebewegen met een zaadwaarde die per
    // start verschilt.
    expect(hoesNaamVoor(hoes(42)), '943d0928ddf9826e.jpg');
  });

  test('twee verschillende hoezen botsen niet', () {
    expect(hoesNaamVoor(hoes(1)), isNot(hoesNaamVoor(hoes(2))));
  });

  group('wat er geen naam krijgt', () {
    test('niets', () => expect(hoesNaamVoor(null), isNull));

    test('een leeg plaatje', () => expect(hoesNaamVoor(Uint8List(0)), isNull));

    test('een plaatje dat te klein is om er een te zijn', () {
      // Een tegel zonder hoes is netter dan een gebroken plaatje.
      expect(hoesNaamVoor(hoes(3, lengte: 99)), isNull);
      expect(hoesNaamVoor(hoes(3, lengte: 100)), isNotNull);
    });
  });

  test('zonder authority geen URI', () {
    // initAutoHoezen() draait alleen op Android. Op de pc en in een toets bestaat de provider niet,
    // en een content-URI die nergens heen wijst toont een gebroken plaatje in plaats van een lege
    // tegel — erger dan geen hoes.
    expect(autoHoesUri(hoes(9)), isNull);
  });
}

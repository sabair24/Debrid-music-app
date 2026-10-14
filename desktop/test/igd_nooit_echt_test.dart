/// Een toets vindt nooit de echte modem: zonder vast adres (de nep-modem) zoekt Igd niet op het netwerk.
/// Zie `igd.dart` en de mutatieproef van 14-10-2026, waar een toets bijna de echte modem aansprak.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/igd.dart';

void main() {
  test('onder flutter test: geen SSDP, dus geen modem', () async {
    expect(Platform.environment.containsKey('FLUTTER_TEST'), isTrue, reason: 'anders bewijst deze toets niets');
    final klok = Stopwatch()..start();
    expect(await Igd().zoek(zoektijd: const Duration(seconds: 2)), isNull);
    expect(klok.elapsedMilliseconds, lessThan(1500), reason: 'er werd niet eens gewacht op antwoorden');
  });
}

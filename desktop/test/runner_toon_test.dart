/// Dat de Windows-runner een venster dat al open staat niet terugzet op zijn herstelmaat.
///
/// **Waarom dit bestaat.** Na elke update via Instellingen → "Bijwerken" opende de pc-app klein:
/// 1240x820 midden op het scherm in plaats van gemaximaliseerd. De meting uit 3.9.436 heeft het op
/// 05-10-2026 laten zien, bij vier installerstarts op rij (3.9.439, .440, .442, .444): main.dart
/// maximaliseert om +594 ms, Flutter tekent om +719 ms zijn eerste beeld, en dan doet
/// `Win32Window::Show()` `ShowWindow(SW_SHOWNORMAL)` op een venster dat al zichtbaar én
/// gemaximaliseerd is — "Ervoor: zichtbaar=1 gemaximaliseerd=1 … Erna: gemaximaliseerd=0".
///
/// De runner is C++ en draait hier niet; de bouwstraat compileert hem alleen. Dus leest deze toets
/// de bron: een terugval naar de oude regel is één regel code en valt verder door niets op.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Het lijf van `Win32Window::Show()`, met de regeleinden gelijkgetrokken (een verse werkboom op
/// Windows krijgt CRLF).
String _lijfVanShow() {
  final bron = File('windows/runner/win32_window.cpp').readAsStringSync().replaceAll('\r\n', '\n');
  final begin = bron.indexOf('bool Win32Window::Show() {');
  expect(begin, isNonNegative, reason: 'Win32Window::Show() staat niet meer in win32_window.cpp');
  final eind = bron.indexOf('\n}\n', begin);
  expect(eind, greaterThan(begin));
  return bron.substring(begin, eind);
}

/// De code zonder commentaar, zodat een uitleg die "SW_SHOWNORMAL" noemt niet meetelt.
String _zonderCommentaar(String code) =>
    code.split('\n').map((r) => r.replaceFirst(RegExp(r'//.*$'), '')).join('\n');

void main() {
  test('DE KERN: een venster dat al open staat gaat terug zonder ShowWindow', () {
    final lijf = _zonderCommentaar(_lijfVanShow());
    final zichtbaar = lijf.indexOf('if (was_zichtbaar)');
    final tonen = lijf.indexOf('ShowWindow(');
    expect(zichtbaar, isNonNegative,
        reason: 'Show() kijkt niet meer of het venster al open staat — dan zet SW_SHOWNORMAL een '
            'gemaximaliseerd venster na elke update terug op 1240x820');
    expect(tonen, greaterThan(zichtbaar),
        reason: 'ShowWindow staat vóór de controle op een open venster');
    final tak = lijf.substring(zichtbaar, tonen);
    expect(tak, contains('return true;'),
        reason: 'de tak voor een open venster loopt door naar ShowWindow in plaats van terug te gaan');
  });

  test('DE VAL: geen ShowWindow met een vaste SW_SHOWNORMAL', () {
    final lijf = _zonderCommentaar(_lijfVanShow());
    expect(RegExp(r'ShowWindow\([^)]*SW_SHOWNORMAL').hasMatch(lijf), isFalse,
        reason: 'een vaste SW_SHOWNORMAL haalt de maximalisatie weg van een venster dat nog dicht '
            'maar al wel gemaximaliseerd is');
  });

  test('DE GRENS: een dicht maar gemaximaliseerd venster gaat gemaximaliseerd open', () {
    final lijf = _zonderCommentaar(_lijfVanShow());
    expect(lijf, contains('was_gemaximaliseerd ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL'),
        reason: 'een venster dat nog niet getoond is maar al gemaximaliseerd, opent dan klein');
  });
}

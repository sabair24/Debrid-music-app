/// Dat de pc met Skia tekent en niet met Impeller.
///
/// **Waarom dit bestaat.** Flutter 3.47 zette Windows standaard op Impeller. Op Sabers pc kostte Nu
/// speelt openen of sluiten daarmee een paar seconden lang 15 tot 20 GB werkgeheugen en 6 tot 9 GB
/// videogeheugen, met 65 tot 123 ms per beeld (18-10-2026: "heel stroef"). Gemeten op vier bouwen
/// met dezelfde proef: 3.9.504 (Flutter 3.41, Skia) bleef op 1,2 GB en 2,3 ms per beeld; de bouw met
/// alleen de overstap naar 3.47 had het al.
///
/// De runner is C++ en draait hier niet; de bouwstraat compileert hem alleen. Dus leest deze toets
/// de bron: de regel valt bij een volgende Flutter-overstap of een vers gegenereerde runner anders
/// stil weg, en dan merk je het pas aan een pc die vastloopt.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('de Windows-runner zet Impeller uit, vóór het venster gemaakt wordt', () {
    final bron = File('windows/runner/main.cpp').readAsStringSync().replaceAll('\r\n', '\n');
    // Zonder commentaarregels: een uitleg die de regel noemt telt niet mee.
    final code = bron.split('\n').where((r) => !r.trimLeft().startsWith('//')).join('\n');
    final uit = code.indexOf('project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);');
    expect(uit, isNonNegative, reason: 'Impeller staat niet meer uit in windows/runner/main.cpp');
    final venster = code.indexOf('FlutterWindow window(project);');
    expect(venster, greaterThan(uit), reason: 'de keuze moet gezet zijn voor de engine start');
  });
}

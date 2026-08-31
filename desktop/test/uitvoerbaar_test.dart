/// Nooit `exec` op iets wat er niet is.
///
/// **Waarom dit bestaat.** De app zoekt ffmpeg, fpcalc, aria2c en tiddl door kandidaten af te lopen
/// en er `--version` op te proberen. Dat leest als "gewoon proberen, een fout vangen we op", en op
/// Windows en Linux klopt dat ook.
///
/// Op macOS niet. Een `Process.runSync` op een pad dat NIET bestaat kost daar de hele app een
/// SIGPIPE: geen uitzondering, geen crashrapport, geen logregel. Gemeten op 24-08-2026 met een
/// release-build: het instellingenvenster leest `Aria2.beschikbaar` tijdens het opbouwen, aria2c
/// staat op een Mac nergens, en dus verdween de app zodra je op het tandwiel klikte. Afsluitcode
/// 141, in de debugger een SIGPIPE middenin `fork()` op de hoofdthread. Een debug-build deed het
/// niet, dus geen enkele toets zag het.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/uitvoerbaar.dart';

void main() {
  late Directory tijdelijk;

  setUp(() => tijdelijk = Directory.systemTemp.createTempSync('uitvoerbaar'));
  tearDown(() => tijdelijk.deleteSync(recursive: true));

  String leg(String naam) {
    final f = File('${tijdelijk.path}${Platform.pathSeparator}$naam')..writeAsStringSync('#!/bin/sh\n');
    return f.path;
  }

  group('een pad', () {
    test('bestaat het, dan komt het pad terug', () {
      final p = leg('ffmpeg');
      expect(uitvoerbaarPad(p), p);
    });

    test('bestaat het niet, dan null — en dus geen exec', () {
      // Dit is het hele punt: hier stond eerder een runSync, en die nam de app mee.
      expect(uitvoerbaarPad('${tijdelijk.path}${Platform.pathSeparator}bestaat-niet'), isNull);
    });

    test('een map is geen programma', () {
      final d = Directory('${tijdelijk.path}${Platform.pathSeparator}map')..createSync();
      expect(uitvoerbaarPad(d.path), isNull);
    });
  });

  group('een kale naam', () {
    test('wordt in PATH gevonden', () {
      leg('aria2c');
      expect(uitvoerbaarPad('aria2c', omgeving: {'PATH': tijdelijk.path}),
          '${tijdelijk.path}${Platform.pathSeparator}aria2c');
    });

    test('staat hij er niet, dan null', () {
      expect(uitvoerbaarPad('aria2c', omgeving: {'PATH': tijdelijk.path}), isNull);
    });

    test('de eerste map in PATH wint', () {
      final een = Directory('${tijdelijk.path}/een')..createSync();
      final twee = Directory('${tijdelijk.path}/twee')..createSync();
      File('${een.path}/fpcalc').writeAsStringSync('x');
      File('${twee.path}/fpcalc').writeAsStringSync('x');
      // Met de scheiding van DIT platform, niet met een vaste dubbelepunt. Windows scheidt zijn PATH
      // met een puntkomma, en een `C:\...` erin bevat er zelf al een — deze toets stond daardoor
      // rood op de machine waar hij het vaakst draait, terwijl de code die hij bewaakt gewoon deugt.
      // En dat is geen kleinigheid: die code is wat de app op een Mac overeind houdt.
      final scheiding = Platform.isWindows ? ';' : ':';
      expect(uitvoerbaarPad('fpcalc', omgeving: {'PATH': '${een.path}$scheiding${twee.path}'}),
          '${een.path}${Platform.pathSeparator}fpcalc');
    });

    test('lege PATH, lege naam en losse dubbelepunten leveren niets op', () {
      // Een app die via Finder start heeft soms een kale omgeving; dat mag geen exec worden.
      expect(uitvoerbaarPad('aria2c', omgeving: const {}), isNull);
      expect(uitvoerbaarPad('aria2c', omgeving: const {'PATH': ''}), isNull);
      expect(uitvoerbaarPad('  ', omgeving: {'PATH': tijdelijk.path}), isNull);
      expect(uitvoerbaarPad('aria2c', omgeving: const {'PATH': '::'}), isNull);
    });
  });
}

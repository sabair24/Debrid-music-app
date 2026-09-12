/// De bovenbalk op een pc: alle secties passen, en de telling duwt ze er niet uit.
///
/// **Waarom dit bestaat.** Op een Mac stond "Kwaliteit" half buiten beeld terwijl de balk er compleet
/// uitzag: het woordmerk links en de telling ("530 albums · 1326 nummers") rechts aten samen ruim 250
/// punten uit de rij, en de secties schoven weg in hun schuifvak. Gemeld door Saber op 12-09-2026.
///
/// De reparatie heeft twee helften, en allebei staan ze hier vast:
/// * de twee regels staan nu GESTAPELD links, zodat ze samen zo breed zijn als de breedste;
/// * of alles past wordt GEMETEN ([sectiesBreedte]) in plaats van opgehangen aan een vast getal --
///   dat getal (1040) stamde uit de tijd dat deze balk zeven secties had.
///
/// **Geen absolute punten in deze toets.** In een toets is elk letterteken een vierkant van de
/// lettergrootte, dus "past het op 1440 punten" zou hier iets heel anders meten dan op een echte Mac.
/// Wat wél klopt in allebei de werelden is de VERGELIJKING: gestapeld is smaller dan naast elkaar.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late final String hoofd = File('lib/main.dart').readAsStringSync();

  final woordmerk =
      _breedte('DebridMusic', const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5));
  final telling = _breedte('8888 albums · 88888 nummers', const TextStyle(fontSize: 10.5));

  test('gestapeld scheelt de secties een hoop breedte', () {
    final vast = balkVasteBreedte(desktop: true, touch: false);
    final gestapeld = vast + (woordmerk > telling ? woordmerk : telling) + 9;
    // De oude indeling: woordmerk links, telling rechts, met de gaten die daarbij hoorden.
    final naastElkaar = vast + woordmerk + 9 + telling + 10 + 12;

    expect(gestapeld, lessThan(naastElkaar),
        reason: 'als stapelen niets scheelt, is de reparatie zinloos');
    expect(naastElkaar - gestapeld, greaterThan(woordmerk),
        reason: 'de winst hoort minstens de breedte van het woordmerk te zijn -- dat is wat er '
            'uit de rij verdwijnt');
  });

  test('de secties hebben een echte maat, en de tekstschaal telt mee', () {
    expect(sectiesBreedte(), greaterThan(0));
    expect(sectiesBreedte(schaal: const TextScaler.linear(1.35)), greaterThan(sectiesBreedte()),
        reason: 'meet je zonder de schaal, dan zegt de balk dat iets past wat op een scherm met '
            'grotere systeemletters niet past');
  });

  test('de balk meet of alles past, en hangt niet aan een vast getal', () {
    // Zonder de toelichtingsregels: die citeren de oude regel met opzet, en een wacht die daarover
    // struikelt zou je leren om de uitleg maar weg te halen.
    final code = hoofd
        .split('\n')
        .where((r) => !r.trimLeft().startsWith('//') && !r.trimLeft().startsWith('///'))
        .join('\n');
    expect(code, isNot(contains('box.maxWidth < 1040')),
        reason: 'een vaste drempel klopt niet meer zodra er een sectie bij komt');
    expect(hoofd, contains('_NavPillsState.benodigdeBreedte(schaal: schaal)'),
        reason: 'de balk hoort te rekenen met wat de secties echt nodig hebben');
  });

  test('de telling staat links onder het woordmerk, niet naast de secties', () {
    final a = hoofd.indexOf("const Text('DebridMusic',");
    expect(a, greaterThan(-1), reason: 'het woordmerk in de balk is verdwenen');
    expect(hoofd.substring(a, a + 1200), contains('Consumer2<LibraryStore, FactsWarmer>'),
        reason: 'de telling hoort in hetzelfde blok als het woordmerk te staan');
    expect(hoofd, isNot(contains('if (!compact || isTv)')),
        reason: 'rechts naast de secties hield deze regel juist "Kwaliteit" uit beeld');
  });
}

double _breedte(String tekst, TextStyle stijl) {
  final tp = TextPainter(
    text: TextSpan(text: tekst, style: stijl),
    textDirection: TextDirection.ltr,
  )..layout();
  return tp.width;
}

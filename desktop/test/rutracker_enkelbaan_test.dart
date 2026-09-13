/// Eén verversing tegelijk, want vier tegelijk maakte het erger dan het was.
///
/// **De meting.** Saber drukte op 13-09-2026 op "Test verbindingen". In `rutracker.log` stond:
///
///     13:47:21  verversen: vraag aan FlareSolverr
///     13:47:40  verversen: vraag aan FlareSolverr
///     13:47:57  verversen: vraag aan FlareSolverr
///     13:48:20  verversen: vraag aan FlareSolverr
///     13:49:08  toets: tracker.php gaf 0
///     13:49:08  MISLUKT, terugdraaien
///
/// Vier verversingen door elkaar. Elk schrijft zijn eigen `cf_clearance` in de instellingen en
/// toetst hem daarna — maar tegen die tijd staat die van een ander erin, gebonden aan een andere
/// User-Agent. Dus faalde elke toets, en draaide elk zijn eigen verouderde momentopname terug. De
/// eindstand was slechter dan het begin: `cf_clearance` verdween helemaal en de User-Agent sprong
/// terug naar die van een oud plaksel. Eén druk, een half uur eerder, werkte foutloos.
///
/// Deze toets zet een nep-FlareSolverr op een echte socket en vraagt twee keer tegelijk. Er mag er
/// maar ÉÉN aankomen.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/rutracker.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer nep;
  late int aantalVragen;

  setUp(() async {
    aantalVragen = 0;
    nep = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    nep.listen((req) async {
      aantalVragen++;
      await req.drain<void>();
      // Even wachten, zodat een tweede aanroep de eerste écht overlapt.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      // Een geldig antwoord ZONDER cf_clearance: dan stopt de verversing daar, en raakt deze toets
      // het echte RuTracker niet aan.
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'status': 'ok',
          'solution': {
            'cookies': [
              {'name': 'bb_guid', 'value': 'x'}
            ],
            'userAgent': 'Mozilla/5.0 (test)',
            'status': 200,
          }
        }));
      await req.response.close();
    });
  });

  tearDown(() async => nep.close(force: true));

  RuTrackerService dienst() => RuTrackerService(AppSettings()
    ..flaresolverrUrl = 'http://127.0.0.1:${nep.port}'
    ..rutrackerCookie = 'bb_session=oud'
    ..rutrackerUa = 'oude-ua');

  test('DE KERN: twee tegelijk leveren één vraag aan FlareSolverr', () async {
    final rt = dienst();

    final beide = await Future.wait([rt.ververViaFlareSolverr(), rt.ververViaFlareSolverr()]);

    expect(aantalVragen, 1, reason: 'vier browsers tegelijk is wat het stukmaakte');
    expect(beide[0].ok, beide[1].ok, reason: 'beide aanroepers horen dezelfde uitkomst te krijgen');
  });

  test('DE VAL: ná afloop mag er weer een nieuwe', () async {
    // De grendel moet weer open, anders werkt verversen na één poging nooit meer.
    final rt = dienst();
    await rt.ververViaFlareSolverr();
    await rt.ververViaFlareSolverr();

    expect(aantalVragen, 2);
  });

  test('DE GRENS: het koekje blijft staan als er niets te halen valt', () async {
    // Dit antwoord heeft geen cf_clearance. Dan is er niets te verversen, en dan hoort er ook
    // niets weggeschreven te worden - dat is precies hoe de sessie verloren ging.
    final s = AppSettings()
      ..flaresolverrUrl = 'http://127.0.0.1:${nep.port}'
      ..rutrackerCookie = 'bb_session=oud; cf_clearance=goud'
      ..rutrackerUa = 'oude-ua';

    await RuTrackerService(s).ververViaFlareSolverr();

    expect(s.rutrackerCookie, contains('cf_clearance=goud'));
    expect(s.rutrackerUa, 'oude-ua');
  });

  group('de toets repareert niet', () {
    // Met de grendel erbij werd dit meteen gevaarlijk: verify() liep via _haal, en die weg heeft
    // ingebouwd "bij een 403 even een vers koekje halen". Maar verify() wordt zelf aangeroepen
    // VANUIT die verversing - dus kreeg hij de verversing terug waar hij in zat. Werk dat op
    // zichzelf wacht, tot curl er na twintig seconden mee ophield:
    //
    //   14:13:09  verversen: antwoord binnen - clearance=true ua=111
    //   14:13:29  toets: tracker.php gaf 0
    //   14:13:29  MISLUKT, terugdraaien
    //
    // Niet met een nepclient te beproeven - de dienst maakt zijn eigen curl-proces - en het is
    // precies het soort regel die stil terugvalt naar de gemakkelijke weg.
    test('DE VAL: verify gaat niet langs de weg die zelf ververst', () {
      final bron = File('lib/rutracker.dart').readAsStringSync();
      final begin = bron.indexOf('Future<bool> verify() async {');
      expect(begin, greaterThan(0), reason: 'verify bestaat niet meer onder deze naam');
      final blok = bron.substring(begin, begin + 400);

      expect(blok, contains('_haalMetCurl'),
          reason: 'de toets hoort kaal te toetsen wat er ligt');
      expect(blok, isNot(contains('await _haal(')),
          reason: 'die weg ververst bij een 403 en roept dus zichzelf aan');
    });
  });

  group('de tijdslimiet van curl', () {
    // Eerst leek dit alleen de eerste vraag na een verse doorgang te treffen: drie keer op rij
    // stond in rutracker.log exact twintig seconden na het antwoord van FlareSolverr "toets gaf 0
    // -> MISLUKT, terugdraaien", en daarmee ging de net gehaalde doorgang weer verloren.
    //
    // Op 13-09-2026 bleek het breder. De opdeling van een enkel verzoek:
    //
    //   dns 0,03 s | verbinden 0,04 s | tls 0,08 s | EERSTE BYTE 21,0 s | totaal 21,3 s
    //
    // Niet de verbinding en niet de uitdaging dus - RuTracker zelf laat twintig seconden niets
    // horen. Ook `index.php`, dat helemaal niet uitgedaagd wordt, deed er 20,6 s over, terwijl
    // GitHub en Deezer op datzelfde moment in 0,13 s antwoordden. Drie zoekopdrachten na elkaar:
    // 20,55 s, 20,65 s, 20,65 s - alle drie geslaagd, alle drie net binnen een limiet van 20.
    //
    // Een limiet hoort dus boven het waargenomen ergste geval te liggen, met marge, en op elke
    // weg dezelfde - een aparte ruime limiet voor de toets repareert alleen het verversen en laat
    // zoeken stuk.
    test('DE KERN: elk verzoek krijgt de ruime limiet', () {
      final a = RuTrackerService.curlArgumenten('u', 'c', 'ua', 'uit');
      expect(a[a.indexOf('--max-time') + 1], '${RuTrackerService.kCurlSeconden}');
      expect(RuTrackerService.kCurlSeconden, greaterThanOrEqualTo(30),
          reason: 'onder de dertig sneuvelt een zoekopdracht van 21 s alsnog');
    });

    // De storing die hierachter zit was dat verify() zijn eigen ruime getal meekreeg terwijl de
    // rest op twintig bleef staan. Dan verschijnt in het logboek "GELUKT, bewaren" en geeft de
    // zoekopdracht er meteen daarna nul treffers - het lastigste soort storing, want de app meldt
    // dat alles in orde is.
    test('DE VAL: nergens blijft een eigen, krapper getal staan', () {
      final bron = File('lib/rutracker.dart').readAsStringSync();

      expect(bron, isNot(contains('maxSeconden: 20')),
          reason: 'een aanroep met twintig kapt een verzoek van 21 s af');
      expect(bron, isNot(contains('maxSeconden = 20')),
          reason: 'de standaard hoort de ruime limiet te zijn, niet twintig');
      expect('maxSeconden = kCurlSeconden'.allMatches(bron).length, 2,
          reason: 'beide wegen (_haalMetCurl en curlArgumenten) delen een getal');
    });

    test('DE GRENS: een eigen limiet komt er nog steeds in te staan', () {
      final a = RuTrackerService.curlArgumenten('u', 'c', 'ua', 'uit', maxSeconden: 7);
      expect(a[a.indexOf('--max-time') + 1], '7');
    });
  });
}

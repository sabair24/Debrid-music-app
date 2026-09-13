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
    // Drie keer op rij hetzelfde in rutracker.log, exact twintig seconden na het antwoord van
    // FlareSolverr:
    //
    //   14:38:19  verversen: antwoord binnen - clearance=true
    //   14:38:39  toets: tracker.php gaf 0
    //   14:38:39  MISLUKT, terugdraaien
    //
    // Met de hand nagemeten met dezelfde verse doorgang: status 200, tijd 20,7 seconden. Cloudflare
    // laat curl er dus door, maar het eerste verzoek na een nieuwe doorgang kost tientallen
    // seconden. De limiet zat een halve seconde te krap, en het gevolg was niet "traag" maar
    // "mislukt, alles terugdraaien" - inclusief het verlies van de doorgang die net gehaald was.
    test('DE KERN: gewone verzoeken houden hun korte limiet', () {
      final a = RuTrackerService.curlArgumenten('u', 'c', 'ua', 'uit');
      expect(a[a.indexOf('--max-time') + 1], '20');
    });

    test('DE VAL: de toets na een verse doorgang krijgt ruim de tijd', () {
      final bron = File('lib/rutracker.dart').readAsStringSync();
      final begin = bron.indexOf('Future<bool> verify() async {');
      final blok = bron.substring(begin, begin + 400);

      expect(blok, contains('maxSeconden: 45'),
          reason: 'met twintig seconden sneuvelt de toets op iets dat 20,7 s duurt');
    });

    test('DE GRENS: de limiet komt er ook echt in te staan', () {
      final a = RuTrackerService.curlArgumenten('u', 'c', 'ua', 'uit', maxSeconden: 45);
      expect(a[a.indexOf('--max-time') + 1], '45');
    });
  });
}

/// De accountdatabase niet leegtrekken als er niets gebeurt.
///
/// **De klacht, op 31-08-2026, met een schermafdruk van het inlogscherm.** *"Firestore antwoordde
/// met 429: Quota exceeded.."* — en daarmee kwam niemand er meer in. *"wat is dit nou weer"*.
///
/// **Wat het was.** De gratis daglimiet van Firestore, opgemaakt door twee klokken die liepen ook
/// als er niets te doen was:
///
/// * de pc schreef zijn serverregel elke 30 seconden volledig opnieuw weg. Onvoorwaardelijk, want
///   er stond `lastSeenAt: nu` in en die verschilt altijd — 2880 schrijfbeurten per dag voor een pc
///   die stilstond, op een limiet van 20 000;
/// * de wachtrijwerker vroeg elke 20 seconden de hele wachtrij op, ook als die dagenlang leeg was:
///   4320 leesbeurten per dag.
///
/// Precies dezelfde fout als "twee klokken die te snel liepen" van 28-08-2026, alleen kostte deze
/// niets op de pc zelf en dus viel hij pas op toen de deur op slot ging.
///
/// **Waarom dit een toets is en geen kwestie van kijken.** Het verschil tussen 2880 en 1440 schrijf-
/// beurten per dag zie je nergens aan de app af. Je merkt het pas als het te laat is, en dan duurt
/// het tot middernacht.
library;

import 'package:debridmusic/cloud/firestore.dart';
import 'package:debridmusic/cloud/zuinig.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een serverregel zoals de hartslag hem opstelt, zonder tijdstempel.
Map<String, dynamic> regel({
  String naam = 'Saber-PC',
  int poort = 8080,
  List<String> adressen = const ['192.168.0.10'],
  int nummers = 1238,
}) =>
    {
      'name': naam,
      'platform': 'windows',
      'port': poort,
      'urls': adressen,
      'online': true,
      'trackCount': nummers,
    };

void main() {
  group('de serverregel wordt alleen geschreven als het moet', () {
    test('is er nog niets, dan moet er sowieso geschreven worden', () {
      expect(serverRegelVeranderd(null, regel()), isTrue);
    });

    test('twee keer hetzelfde is geen verandering', () {
      expect(serverRegelVeranderd(regel(), regel()), isFalse);
    });

    test('en dat geldt ook voor de lijst met adressen', () {
      // `==` op twee lijsten vergelijkt identiteit, niet inhoud. Zonder de waardevergelijking zou
      // ELKE slag "veranderd" heten en verandert er dus niets aan het aantal schrijfbeurten.
      expect(
          serverRegelVeranderd(
              regel(adressen: ['192.168.0.10', '10.0.0.4']),
              regel(adressen: ['192.168.0.10', '10.0.0.4'])),
          isFalse);
    });

    test('een nieuw adres is wél een verandering', () {
      // Dit is het geval waarvoor de hartslag bestaat: een laptop die van wifi naar kabel gaat.
      // Wachten met dat adres betekent "Geen pc gevonden" op je telefoon.
      expect(serverRegelVeranderd(regel(), regel(adressen: ['192.168.0.99'])), isTrue);
    });

    test('een andere poort of een ander aantal nummers ook', () {
      expect(serverRegelVeranderd(regel(), regel(poort: 9000)), isTrue);
      expect(serverRegelVeranderd(regel(), regel(nummers: 1240)), isTrue);
    });

    test('een tijdstempel telt NIET mee', () {
      // Precies het veld dat de hele vergelijking zinloos maakte.
      final oud = {...regel(), 'lastSeenAt': DateTime(2026, 8, 31, 20)};
      final nieuw = {...regel(), 'lastSeenAt': DateTime(2026, 8, 31, 21)};
      expect(serverRegelVeranderd(oud, nieuw), isFalse);
    });
  });

  group('wanneer er geschreven wordt', () {
    test('een verandering gaat er meteen door', () {
      expect(
          moetServerSchrijven(veranderd: true, sindsLaatsteSchrijf: Duration.zero), isTrue);
    });

    test('en zonder verandering pas na het ritme', () {
      expect(
          moetServerSchrijven(veranderd: false, sindsLaatsteSchrijf: const Duration(seconds: 5)),
          isFalse);
      expect(
          moetServerSchrijven(
              veranderd: false, sindsLaatsteSchrijf: kHartslagRitme - const Duration(seconds: 1)),
          isFalse);
      expect(
          moetServerSchrijven(veranderd: false, sindsLaatsteSchrijf: kHartslagRitme), isTrue);
    });

    test('er blijft speling voor één gemiste slag', () {
      // Dit is de som waar het getal uit volgt, en de toets die hem bewaakte: bij 90 seconden kwam
      // ritme + tik op precies 120 uit, en dan flikkert een pc na één mislukte slag offline op het
      // koppelscherm. Erger dan het probleem dat hier opgelost wordt.
      expect(kHartslagRitme, lessThan(kOnlineVenster));
      expect(kHartslagRitme + kHartslagTik, lessThan(kOnlineVenster));
    });

    test('en het is minstens twee keer zuiniger dan het was', () {
      // 30 seconden was 2880 schrijfbeurten per dag, op een gratis limiet van 20 000.
      const dag = Duration(days: 1);
      final was = dag.inSeconds / 30;
      final wordt = dag.inSeconds / kHartslagRitme.inSeconds;
      expect(wordt * 2, lessThanOrEqualTo(was));
      expect(wordt, lessThan(2000));
    });
  });

  group('de wachtrij wordt trager nagekeken als het stil is', () {
    test('vlak na werk blijft het snel', () {
      expect(wachtrijRitme(Duration.zero), kSnelRitme);
      expect(wachtrijRitme(const Duration(minutes: 4)), kSnelRitme);
    });

    test('na lange stilte wordt het traag', () {
      expect(wachtrijRitme(kStilteVoorTraag), kTraagRitme);
      expect(wachtrijRitme(const Duration(hours: 9)), kTraagRitme);
    });

    test('traag is nog altijd binnen een minuut', () {
      // Er staat iemand op te wachten. Een download die pas na vijf minuten begint zou de winst
      // niet waard zijn.
      expect(kTraagRitme, lessThanOrEqualTo(const Duration(minutes: 1)));
    });
  });

  group('wat er op het scherm komt te staan', () {
    test('429 legt uit wat het is én wat je nu kunt doen', () {
      final s = firestoreUitleg(429, 'Quota exceeded.');
      expect(s, contains('daglimiet'));
      expect(s, contains('Koppelen met een code'),
          reason: 'zonder een uitweg is het alleen een mededeling dat je moet wachten');
      expect(s, isNot(contains('Firestore')), reason: 'een merknaam zegt niemand iets');
      expect(s, isNot(contains('429')));
    });

    test('een verlopen sessie blijft zeggen wat het was', () {
      expect(firestoreUitleg(403, ''), contains('geweigerd'));
    });

    test('en iets onbekends citeert de bron nog gewoon', () {
      // Verzinnen is erger dan citeren. Zie `kapot_bestand.dart`, om dezelfde reden.
      expect(firestoreUitleg(418, 'ik ben een theepot'), contains('ik ben een theepot'));
    });
  });
}

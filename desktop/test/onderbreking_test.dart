/// Wat er met de muziek gebeurt als iets anders geluid wil maken.
///
/// **Waarom dit een toets verdient.** Wat hiervoor in de app stond was één regel: bij élke
/// onderbreking pauzeren, en nooit meer hervatten. In een auto is dat de ergernis die je elke rit
/// hebt — de navigatiestem zegt "sla rechtsaf", de muziek valt stil en komt niet terug. Het systeem
/// stuurt het onderscheid gewoon mee; er keek alleen niemand naar.
///
/// De randgevallen hieronder zijn geen bedenksels: het zijn precies de gevallen waarin muziek uit
/// zichzelf begint te spelen in een stille auto, of juist stil blijft terwijl je hem terug verwacht.
library;

import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/now_playing.dart';

void main() {
  group('er komt iets doorheen', () {
    test('een korte stem zet de muziek zachter, niet uit', () {
      // Pauzeren voor twee seconden navigatie is te veel: je hoort een gat in plaats van een stem
      // over de muziek heen.
      expect(
        bijOnderbreking(
            begint: true,
            soort: AudioInterruptionType.duck,
            speelt: true,
            zelfGepauzeerd: false),
        Onderbreking.dempen,
      );
    });

    test('en daarna weer terug op je eigen stand', () {
      expect(
        bijOnderbreking(
            begint: false,
            soort: AudioInterruptionType.duck,
            speelt: true,
            zelfGepauzeerd: false),
        Onderbreking.ontdempen,
      );
    });

    test('een gesprek pauzeert', () {
      expect(
        bijOnderbreking(
            begint: true,
            soort: AudioInterruptionType.pause,
            speelt: true,
            zelfGepauzeerd: false),
        Onderbreking.pauzeren,
      );
    });

    test('en na het gesprek loopt hij verder', () {
      expect(
        bijOnderbreking(
            begint: false,
            soort: AudioInterruptionType.pause,
            speelt: false,
            zelfGepauzeerd: true),
        Onderbreking.hervatten,
      );
    });
  });

  group('wanneer er juist NIETS mag gebeuren', () {
    test('wie zelf op pauze drukte krijgt zijn muziek niet terug', () {
      // Anders begint de muziek na een gesprek alsnog te spelen terwijl jij hem zelf had stilgezet.
      expect(
        bijOnderbreking(
            begint: false,
            soort: AudioInterruptionType.pause,
            speelt: false,
            zelfGepauzeerd: false),
        Onderbreking.niets,
      );
    });

    test('bij "onbekend" blijft het stil', () {
      // We weten niet waarom het stopte. Uit zichzelf weer beginnen is erger dan stil blijven: dat
      // is muziek die opeens aangaat in een stille auto.
      expect(
        bijOnderbreking(
            begint: false,
            soort: AudioInterruptionType.unknown,
            speelt: false,
            zelfGepauzeerd: true),
        Onderbreking.niets,
      );
    });

    test('wat al stil was wordt niet nog eens gepauzeerd', () {
      for (final s in AudioInterruptionType.values) {
        expect(
          bijOnderbreking(begint: true, soort: s, speelt: false, zelfGepauzeerd: false),
          Onderbreking.niets,
          reason: 'bij $s',
        );
      }
    });
  });

  group('na een blijvend verlies: wachten op stilte', () {
    // Nagespeeld op 22-09-2026 met de buds in: YouTube Shorts vraagt de focus blijvend (`req=1`)
    // en geeft hem na het verlaten van de app niet terug. Zonder deze wacht bleef de muziek stil tot
    // je zelf op spelen drukte — 101 van de 129 blijvende verliezen in dertig dagen waren zo.
    final t0 = DateTime(2026, 9, 22, 18, 0, 51);
    DateTime na(int s) => t0.add(Duration(seconds: s));

    test('DE KERN: speelt niemand meer, dan komt de muziek na zes stille seconden terug', () {
      final w = StilteWacht();
      expect(w.begin(t0), isTrue);
      // Een halve minuut Shorts: de andere app speelt.
      for (var s = 1; s <= 30; s++) {
        expect(w.tik(na(s), andereSpeelt: true, wijSpelen: false), NaVerlies.wachten);
      }
      // Je verlaat YouTube, en het wordt stil.
      for (var s = 31; s < 37; s++) {
        expect(w.tik(na(s), andereSpeelt: false, wijSpelen: false), NaVerlies.wachten,
            reason: 'na ${s - 31} s stilte is het nog te vroeg');
      }
      expect(w.tik(na(37), andereSpeelt: false, wijSpelen: false), NaVerlies.hervatten,
          reason: 'de muziek wacht op een eindbericht dat na een blijvend verlies nooit komt');
      expect(w.wacht, isFalse);
    });

    test('DE VAL: het gat tussen twee Shorts is geen stilte', () {
      // Pakte de muziek de focus in zo'n gat terug, dan pauzeert de video die je aan het kijken bent.
      final w = StilteWacht()..begin(t0);
      for (var s = 1; s <= 120; s++) {
        final gat = s % 10 == 0; // elke tien seconden valt het geluid een tel weg
        expect(w.tik(na(s), andereSpeelt: !gat, wijSpelen: false), NaVerlies.wachten,
            reason: 'op $s s nam de muziek de focus terug midden in je video\'s');
      }
    });

    test('DE VAL: een app die pas na een paar tellen begint te spelen', () {
      // De focus komt eerst, het geluid een tel later — en de stilte telt daarna opnieuw vanaf nul.
      final w = StilteWacht()..begin(t0);
      for (var s = 1; s <= 3; s++) {
        expect(w.tik(na(s), andereSpeelt: false, wijSpelen: false), NaVerlies.wachten);
      }
      expect(w.tik(na(4), andereSpeelt: true, wijSpelen: false), NaVerlies.wachten);
      for (var s = 5; s < 11; s++) {
        expect(w.tik(na(s), andereSpeelt: false, wijSpelen: false), NaVerlies.wachten,
            reason: 'de stilte van vóór het geluid telde nog mee');
      }
      expect(w.tik(na(11), andereSpeelt: false, wijSpelen: false), NaVerlies.hervatten);
    });

    test('DE VAL: vlak na een uitgangswissel is het de auto, en dan blijft het stil', () {
      // 22-09-2026: de Renault kwam om 16:39:13 en 16:39:18 erbij, de focus viel om 16:39:24 weg.
      final w = StilteWacht();
      expect(w.begin(t0, laatsteUitgangswissel: t0.subtract(const Duration(seconds: 6))), isFalse,
          reason: 'muziek die opeens aangaat in een stille auto');
      expect(w.wacht, isFalse);
      expect(w.tik(na(10), andereSpeelt: false, wijSpelen: false), NaVerlies.opgeven);
      expect(w.begin(t0, laatsteUitgangswissel: t0.subtract(const Duration(minutes: 5))), isTrue,
          reason: 'een wissel van vijf minuten geleden zegt niets over dit verlies');
    });

    test('DE GRENS: wie zelf weer op spelen drukt, krijgt geen tweede start', () {
      final w = StilteWacht()..begin(t0);
      expect(w.tik(na(3), andereSpeelt: false, wijSpelen: true), NaVerlies.opgeven);
      expect(w.wacht, isFalse);
    });

    test('DE GRENS: speelt er na tien minuten nog iets anders, dan ben je overgestapt', () {
      final w = StilteWacht()..begin(t0);
      for (var s = 1; s <= 600; s++) {
        w.tik(na(s), andereSpeelt: true, wijSpelen: false);
      }
      expect(w.tik(na(601), andereSpeelt: false, wijSpelen: false), NaVerlies.opgeven,
          reason: 'na een uur Spotify begint DebridMusic niet opeens te spelen');
      expect(w.waarom, contains('10 min'));
    });

    test('DE GRENS: gestopt is gestopt', () {
      final w = StilteWacht()..begin(t0);
      w.stop('uitgang veranderde');
      expect(w.tik(na(20), andereSpeelt: false, wijSpelen: false), NaVerlies.opgeven);
      expect(w.waarom, 'uitgang veranderde');
    });

    test('DE VAL: de app houdt op met wachten bij elke uitgangswissel', () {
      // De veiligheid zit in de aansluiting, niet in de klasse: alleen een wacht die bij een
      // wisseling van uitgang STOPT, laat de auto en de buds met rust. Zonder platformkanaal is die
      // aansluiting niet te draaien, dus hier gelezen uit de bron — zonder de commentaarregels.
      final bron = File('lib/now_playing.dart')
          .readAsLinesSync()
          .where((r) => !r.trimLeft().startsWith('//'))
          .join('\n');
      final ruis = bron.indexOf('session.becomingNoisyEventStream.listen');
      final wissel = bron.indexOf('session.devicesChangedEventStream.listen');
      expect(ruis, greaterThan(0));
      expect(wissel, greaterThan(0));
      expect(bron.indexOf("stopWacht('uitgang viel weg')", ruis), greaterThan(ruis),
          reason: 'buds uit het oor en de muziek begint uit de telefoonluidspreker');
      expect(bron.indexOf("stopWacht('uitgang veranderde')", wissel), greaterThan(wissel),
          reason: 'de auto verbindt en de muziek begint uit zichzelf te spelen');
      expect(bron, contains('if (event.type == AudioInterruptionType.unknown) startWacht();'),
          reason: 'alleen na een BLIJVEND verlies wachten; een tijdelijk verlies heeft zijn eigen eind');
      expect(bron, contains('if (!Platform.isAndroid || isTv) return;'));
    });
  });

  test('onbekend pauzeert wél, want het is geen kort geluid', () {
    // Alleen `duck` is kort. Al het andere hoort de muziek stil te zetten; het verschil zit in wat
    // er daarna gebeurt.
    expect(
      bijOnderbreking(
          begint: true,
          soort: AudioInterruptionType.unknown,
          speelt: true,
          zelfGepauzeerd: false),
      Onderbreking.pauzeren,
    );
  });
}

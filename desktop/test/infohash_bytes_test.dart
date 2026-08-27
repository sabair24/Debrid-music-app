/// De infohash uit een topicpagina halen zonder die pagina eerst te ontcijferen.
///
/// **Waarom dit een toets waard is.** Een zoekopdracht bij RuTracker levert een lijstpagina waarin
/// de infohashes meestal ontbreken, dus haalt de app er tot zestig topicpagina's bij. Elke pagina is
/// een half tot een heel megabyte Russische tekst met alle reacties eronder, en die werd volledig
/// uit windows-1251 omgezet naar een Dart-tekst voordat er een regex overheen ging. Zestig keer, op
/// de tekendraad. Gemeld op 27-08-2026: *"als ik dan bij de resultaten ben van de album gaat het ook
/// moeizaam, blijft de app ook even bevriezen"*.
///
/// Een infohash is veertig hextekens en dus per definitie ASCII — geen enkele Cyrillische byte kan
/// er deel van uitmaken. De omzetting was daarom niet duur maar overbodig.
///
/// Wat hier nagemeten wordt is dat de nieuwe weg PRECIES hetzelfde antwoord geeft als de regex die
/// er stond, inclusief de randen waar zo'n handgeschreven zoeker het op verliest: een hash die op
/// het einde van de pagina staat, hoofdletters, en een `urn:btih:` waar niets bruikbaars achter
/// staat terwijl de echte verderop ligt.
///
/// Zuiver en zonder netwerk, dus na te meten zonder toestel.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:debridmusic/cp1251.dart';
import 'package:debridmusic/rutracker.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wat er vroeger gebeurde: hele pagina omzetten, dan een regex. De maatstaf voor elke toets hier.
String? viaDeOudeWeg(List<int> bytes) =>
    RegExp(r'urn:btih:([a-fA-F0-9]{40})').firstMatch(cp1251Tekst(bytes))?.group(1)?.toLowerCase();

/// Een topicpagina zoals RuTracker hem stuurt: Cyrillisch in windows-1251, met een magneet erin.
Uint8List pagina(String hash, {String staart = ''}) {
  final kop = 'Скачать торрент — Кино. Группа крови (1988) [FLAC]';
  final magneet = '<a href="magnet:?xt=urn:btih:$hash&amp;tr=http://bt.t-ru.org/ann">магнет</a>';
  final bytes = <int>[
    for (final r in kop.runes) cp1251Byte(r)!,
    ...ascii.encode(magneet),
    for (final r in 'Комментарии участников$staart'.runes) cp1251Byte(r) ?? 0x3F,
  ];
  return Uint8List.fromList(bytes);
}

void main() {
  const echt = '0123456789abcdef0123456789abcdef01234567';

  group('DE KERN: dezelfde uitslag als de regex, zonder de pagina om te zetten', () {
    test('een gewone topicpagina', () {
      final b = pagina(echt);
      expect(infohashUitBytes(b), echt);
      expect(infohashUitBytes(b), viaDeOudeWeg(b), reason: 'moet gelijk zijn aan de oude weg');
    });

    test('hoofdletters worden kleine letters', () {
      const hoofd = 'ABCDEF0123456789ABCDEF0123456789ABCDEF01';
      final b = pagina(hoofd);
      expect(infohashUitBytes(b), hoofd.toLowerCase());
      expect(infohashUitBytes(b), viaDeOudeWeg(b));
    });

    test('staat er geen hash in, dan null', () {
      final b = Uint8List.fromList(ascii.encode('<html>geen enkele magneet hier</html>'));
      expect(infohashUitBytes(b), isNull);
      expect(viaDeOudeWeg(b), isNull);
    });

    test('een lege pagina geeft null en geen uitzondering', () {
      expect(infohashUitBytes(Uint8List(0)), isNull);
      expect(infohashUitBytes(Uint8List.fromList(ascii.encode('urn:btih:'))), isNull);
    });
  });

  group('DE RANDEN, waar een eigen zoeker het op verliest', () {
    test('een hash die precies op het einde van de pagina staat', () {
      // Geen enkele byte over na de veertigste. Wie hier een marge inbouwt, mist hem.
      final b = Uint8List.fromList(ascii.encode('xx urn:btih:$echt'));
      expect(infohashUitBytes(b), echt);
      expect(infohashUitBytes(b), viaDeOudeWeg(b));
    });

    test('één byte te kort is geen hash', () {
      final b = Uint8List.fromList(ascii.encode('urn:btih:${echt.substring(1)}'));
      expect(infohashUitBytes(b), isNull);
      expect(viaDeOudeWeg(b), isNull);
    });

    test('een loze urn:btih: eerder op de pagina slaat de echte niet over', () {
      // Dit is het geval waarop een naïeve "zoek de naald, lees veertig tekens" stukloopt: hij
      // vindt de eerste, ziet dat het niets is, en geeft op.
      final b = Uint8List.fromList(
          ascii.encode('<b>urn:btih:</b> nog niets, later: urn:btih:$echt einde'));
      expect(infohashUitBytes(b), echt);
      expect(infohashUitBytes(b), viaDeOudeWeg(b));
    });

    test('een hash met een niet-hexteken erin telt niet, de goede erna wel', () {
      const stuk = '0123456789abcdefzzzz56789abcdef01234567x';
      final b = Uint8List.fromList(ascii.encode('urn:btih:$stuk en dan urn:btih:$echt'));
      expect(infohashUitBytes(b), echt);
      expect(infohashUitBytes(b), viaDeOudeWeg(b));
    });

    test('meer dan veertig hextekens: de eerste veertig, net als de regex', () {
      final b = Uint8List.fromList(ascii.encode('urn:btih:${echt}abcdef'));
      expect(infohashUitBytes(b), echt);
      expect(infohashUitBytes(b), viaDeOudeWeg(b));
    });

    test('URN:BTIH: met hoofdletters telt niet — precies zoals de regex het deed', () {
      final b = Uint8List.fromList(ascii.encode('URN:BTIH:$echt'));
      expect(infohashUitBytes(b), isNull);
      expect(viaDeOudeWeg(b), isNull);
    });
  });

  group('Cyrillisch onderweg verandert niets', () {
    test('bytes boven 0x7F rondom de hash laten hem heel', () {
      final b = pagina(echt, staart: ' — раздача обновлена');
      expect(infohashUitBytes(b), echt);
      expect(infohashUitBytes(b), viaDeOudeWeg(b));
    });

    test('een Cyrillische byte kan nooit als hexteken gelezen worden', () {
      // 0xC0..0xFF is А..я. Zou zo'n byte als hex meetellen, dan zou hier een hash uitkomen.
      final b = Uint8List.fromList([
        ...ascii.encode('urn:btih:'),
        for (var i = 0; i < 40; i++) 0xC0 + (i % 32),
      ]);
      expect(infohashUitBytes(b), isNull);
      expect(viaDeOudeWeg(b), isNull);
    });
  });

  group('cp1251Tekst blijft doen wat hij deed', () {
    test('ASCII, Cyrillisch en de leestekens op 0x80–0xBF', () {
      // De omzetting loopt nu via een Uint16List in plaats van een StringBuffer. Eén teken per
      // byte, dus de lengte moet gelijk blijven aan het aantal bytes.
      final bytes = <int>[
        ...ascii.encode('Kino '),
        ...'Группа крови'.runes.map((r) => cp1251Byte(r)!),
        cp1251Byte(0x2116)!, // №
        cp1251Byte(0x00A9)!, // ©
      ];
      final uit = cp1251Tekst(bytes);
      expect(uit, 'Kino Группа крови№©');
      expect(uit.length, bytes.length, reason: 'één teken per byte, dat is de hele aanname');
    });

    test('lege bytes geven lege tekst', () => expect(cp1251Tekst(const []), ''));
  });
}

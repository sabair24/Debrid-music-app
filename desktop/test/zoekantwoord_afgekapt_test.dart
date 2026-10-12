/// Een afgekapt of verminkt zoekantwoord van een peer mag de app nooit meer laten struikelen.
///
/// **De storing.** In start.log, om 18:23:41 op vermoedelijk 07-10-2026 (de regels dragen geen datum;
/// het is het dagblok waarin 3.9.453 geïnstalleerd werd):
///
///     ONGEVANGEN: RangeError (length): Invalid value: Not in inclusive range 0..11866: 11867
///       #0  _R.u32
///       #1  SoulseekClient._parseAny (soulseek.dart:1268)
///       #2  SoulseekClient._onFramed (soulseek.dart:615)
///       #3  _Inbound._onData (soulseek.dart:400)
///
/// Regel 1268 was in 3.9.453 het aantal kenmerken: naam en grootte waren nog binnen, daarna hield het
/// antwoord op. De ontleder keek alleen aan het begin van elke bestandsregel of er nog vijf bytes
/// waren, en las de rest blind — in een stroomluisteraar waar niemand iets opvangt.
///
/// Wat hier vastligt: een afgekapt antwoord geeft de bestanden terug die al helemaal binnen waren en
/// gooit nooit; een halve regel wordt geen bestand. De bestandsnamen eindigen op `.mp3` met opzet:
/// bij lossless namen schrijft de ontleder voorbeelden naar het echte `soulseek.log`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:debridmusic/soulseek.dart';
import 'package:flutter_test/flutter_test.dart';

/// Little-endian, zoals een peer het op de lijn zet.
class _Lijn {
  final _b = BytesBuilder();
  int get plek => _b.length;
  void u8(int v) => _b.addByte(v & 0xFF);
  void u32(int v) {
    for (var s = 0; s < 32; s += 8) {
      _b.addByte((v >> s) & 0xFF);
    }
  }

  void u64(int v) {
    u32(v & 0xFFFFFFFF);
    u32(v >> 32);
  }

  void str(String s) {
    final b = utf8.encode(s);
    u32(b.length);
    _b.add(b);
  }

  void ruw(List<int> b) => _b.add(b);
  Uint8List bytes() => _b.toBytes();
}

typedef _Bestand = ({String naam, int grootte, Map<int, int> kenmerken});

/// Waar in het antwoord elke bestandsregel zit: een plek midden in de naam, midden in de grootte,
/// midden in het aantal kenmerken, midden in de kenmerken, en het eind.
typedef _Regel = ({int inNaam, int inGrootte, int inAantal, int inKenmerken, int eind});

const _ticket = 0x1234ABCD;

/// Een volledig FileSearchResponse, uitgepakt, met de staart (vrije plaats, snelheid, wachtrij).
({Uint8List bytes, List<_Regel> regels}) _antwoord(List<_Bestand> bestanden) {
  final w = _Lijn()
    ..str('nep-peer')
    ..u32(_ticket)
    ..u32(bestanden.length);
  final regels = <_Regel>[];
  for (final b in bestanden) {
    w.u8(1);
    final naamBytes = utf8.encode(b.naam).length;
    final inNaam = w.plek + 4 + naamBytes ~/ 2;
    w.str(b.naam);
    final inGrootte = w.plek + 3;
    w.u64(b.grootte);
    w.str('mp3');
    final inAantal = w.plek + 2;
    w.u32(b.kenmerken.length);
    final inKenmerken = w.plek + 8 + 5;
    for (final e in b.kenmerken.entries) {
      w.u32(e.key);
      w.u32(e.value);
    }
    regels.add((inNaam: inNaam, inGrootte: inGrootte, inAantal: inAantal, inKenmerken: inKenmerken, eind: w.plek));
  }
  w
    ..u8(1) // vrije plaats
    ..u32(123456) // snelheid
    ..u32(7); // wachtrij
  return (bytes: w.bytes(), regels: regels);
}

final _drie = <_Bestand>[
  (naam: r'@@muziek\Prince\Purple Rain\01 - Let’s Go Crazy.mp3', grootte: 11234567, kenmerken: {0: 320, 1: 280, 2: 0}),
  (naam: r'@@muziek\Prince\Purple Rain\02 - Take Me With U.mp3', grootte: 9345678, kenmerken: {0: 320, 1: 234, 2: 0}),
  (
    naam: r'@@muziek\Prince\Purple Rain\03 - The Beautiful Ones — Ünïcode.mp3',
    grootte: 12000000000,
    kenmerken: {0: 256, 1: 314, 2: 1}
  ),
];

Uint8List _tot(Uint8List b, int n) => Uint8List.sublistView(b, 0, n);

void _zelfdeBestanden(List<SoulseekFile> kregen, List<_Bestand> verwacht) {
  expect(kregen.map((f) => f.filename).toList(), verwacht.map((b) => b.naam).toList());
  expect(kregen.map((f) => f.size).toList(), verwacht.map((b) => b.grootte).toList());
  expect(kregen.map((f) => f.bitrate).toList(), verwacht.map((b) => b.kenmerken[0]).toList());
  expect(kregen.map((f) => f.durationSec).toList(), verwacht.map((b) => b.kenmerken[1]).toList());
}

void main() {
  final heel = _antwoord(_drie);

  group('ontleedZoekantwoord', () {
    test('een heel antwoord komt volledig terug, met de staart', () {
      final (ticket, files) = ontleedZoekantwoord(heel.bytes);
      expect(ticket, _ticket);
      _zelfdeBestanden(files, _drie);
      expect(files.map((f) => f.username).toSet(), {'nep-peer'});
      expect(files.last.isVbr, isTrue);
      expect(files.map((f) => (f.freeSlots, f.speed, f.queueLength)).toSet(), {(true, 123456, 7)});
    });

    test('afgekapt midden in een bestandsnaam: de twee bestanden ervoor, en geen halve naam', () {
      final (ticket, files) = ontleedZoekantwoord(_tot(heel.bytes, heel.regels[2].inNaam));
      expect(ticket, _ticket);
      _zelfdeBestanden(files, _drie.take(2).toList());
    });

    test('afgekapt in de grootte: alleen het eerste bestand', () {
      final (_, files) = ontleedZoekantwoord(_tot(heel.bytes, heel.regels[1].inGrootte));
      _zelfdeBestanden(files, _drie.take(1).toList());
    });

    test('afgekapt in het aantal kenmerken, de plek uit start.log: de bestanden ervoor', () {
      final (_, files) = ontleedZoekantwoord(_tot(heel.bytes, heel.regels[2].inAantal));
      _zelfdeBestanden(files, _drie.take(2).toList());
    });

    test('afgekapt in de kenmerken: de twee bestanden ervoor', () {
      final (_, files) = ontleedZoekantwoord(_tot(heel.bytes, heel.regels[2].inKenmerken));
      _zelfdeBestanden(files, _drie.take(2).toList());
    });

    test('zonder staart staan vrije plaats, snelheid en wachtrij op nul, niet op een stuk regel', () {
      final (_, files) = ontleedZoekantwoord(_tot(heel.bytes, heel.regels[2].inKenmerken));
      expect(files.map((f) => (f.freeSlots, f.speed, f.queueLength)).toSet(), {(false, 0, 0)});
    });

    test('op elke plek afgekapt: nooit een fout, en precies de regels die helemaal binnen waren', () {
      for (var n = 0; n <= heel.bytes.length; n++) {
        final List<SoulseekFile> files;
        try {
          files = ontleedZoekantwoord(_tot(heel.bytes, n)).$2;
        } catch (e) {
          fail('afgekapt na $n van ${heel.bytes.length} bytes gooide: $e');
        }
        final binnen = heel.regels.where((r) => r.eind <= n).length;
        expect(files.map((f) => f.filename).toList(), _drie.take(binnen).map((b) => b.naam).toList(),
            reason: 'afgekapt na $n bytes');
      }
    });

    test('meer dan tien kenmerken schuiven de volgende regel niet scheef', () {
      // Er werden er hooguit tien gelezen; de rest werd dan gelezen als de kop van het volgende bestand.
      final veel = <int, int>{for (var t = 0; t < 12; t++) t: 1000 + t}
        ..[0] = 320
        ..[1] = 200
        ..[4] = 44100
        ..[5] = 16;
      final twee = <_Bestand>[
        (naam: r'@@muziek\A\01 - veel kenmerken.mp3', grootte: 5000000, kenmerken: veel),
        (naam: r'@@muziek\A\02 - daarna.mp3', grootte: 6000000, kenmerken: {0: 192, 1: 180}),
      ];
      final (_, files) = ontleedZoekantwoord(_antwoord(twee).bytes);
      _zelfdeBestanden(files, twee);
      expect(files.first.sampleRate, 44100);
      expect(files.first.bitDepth, 16);
      expect(files.last.freeSlots, isTrue, reason: 'en de staart staat weer op zijn plek');
    });

    test('verminkte bytes gooien nooit', () {
      final kans = Random(20261012);
      for (var i = 0; i < 3000; i++) {
        final lengte = kans.nextInt(400);
        final rommel = Uint8List.fromList([for (var j = 0; j < lengte; j++) kans.nextInt(256)]);
        // De helft begint met een echte kop, zodat de rommel ook in de bestandsregels terechtkomt.
        final b = i.isEven
            ? rommel
            : (_Lijn()
                  ..str('p')
                  ..u32(_ticket)
                  ..u32(3)
                  ..ruw(rommel))
                .bytes();
        expect(() => ontleedZoekantwoord(b), returnsNormally, reason: 'poging $i, $lengte bytes');
      }
    });

    test('belachelijke lengtes uit een verminkt antwoord: niets, en geen fout', () {
      final naamTeLang = (_Lijn()
            ..str('p')
            ..u32(_ticket)
            ..u32(1)
            ..u8(1)
            ..u32(0xFFFFFFFF))
          .bytes();
      expect(ontleedZoekantwoord(naamTeLang).$2, isEmpty);
      final kenmerkenTeVeel = (_Lijn()
            ..str('p')
            ..u32(_ticket)
            ..u32(1)
            ..u8(1)
            ..str('x.mp3')
            ..u64(1)
            ..str('mp3')
            ..u32(0xFFFFFFFF))
          .bytes();
      expect(ontleedZoekantwoord(kenmerkenTeVeel).$2, isEmpty);
    });
  });

  test('via de luisterpoort: een nep-peer met een afgekapt antwoord laat niets doorvallen', () async {
    // De weg van de storing zelf: _Inbound._onData → _onFramed → de ontleder. Viel daar een fout,
    // dan komt hij in deze toets als ongevangen fout terug, en kwamen de bestanden nooit aan.
    final c = SoulseekClient();
    final vrij = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    final poort = vrij.port;
    await vrij.close();
    c.listenPort = poort;
    expect(await c.ensureListening(), poort);
    addTearDown(c.stopListening);

    final aangekomen = Completer<List<SoulseekFile>>();
    c.zetZoekkaartjeVoorTest(_ticket, (f) {
      if (!aangekomen.isCompleted) aangekomen.complete(f);
    });

    final sock = await Socket.connect(InternetAddress.loopbackIPv4, poort);
    addTearDown(sock.destroy);
    // PeerInit: [lengte][1]["nep-peer"]["P"][token]
    final init = (_Lijn()
          ..u8(1)
          ..str('nep-peer')
          ..str('P')
          ..u32(0))
        .bytes();
    sock.add((_Lijn()
          ..u32(init.length)
          ..ruw(init))
        .bytes());
    // FileSearchResponse (code 9), ingepakt zoals een peer het stuurt, afgekapt in de derde naam.
    final ingepakt = ZLibCodec().encode(_tot(heel.bytes, heel.regels[2].inNaam));
    sock.add((_Lijn()
          ..u32(4 + ingepakt.length)
          ..u32(9)
          ..ruw(ingepakt))
        .bytes());
    await sock.flush();

    final files = await aangekomen.future.timeout(const Duration(seconds: 10));
    _zelfdeBestanden(files, _drie.take(2).toList());
  });
}

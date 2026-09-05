/// De speelduur van een MP3, uit de kop van het bestand zelf.
///
/// **Waarom dit bestaat.** Gemeten op 05-09-2026 over de hele bibliotheek: van 1221 nummers hadden
/// er drie geen looptijd. Eén daarvan is een echt kapotte FLAC — ffprobe leest hem ook niet — maar
/// de andere twee waren gewone MP3's die ffprobe moeiteloos leest: "Ik Leef Voor Jou" van Petra
/// (223,4 s) en "opzij opzij" van Enzo (209,1 s).
///
/// Ze hebben geen `Xing`-blok. Bijna elke MP3 van een moderne encoder draagt dat vooraan, met het
/// exacte aantal frames erin, en dáár leest een ontleder de duur uit. Een oudere CBR-codering heeft
/// het niet, want bij een vaste bitsnelheid is de duur één deling — en juist die deling ontbrak.
///
/// Een duur van nul is niet alleen lelijk: de hele albumpagina rekent ermee. Welk bestand op welke
/// rij hoort weegt de looptijd met 2 van de 5, en een nummer zonder duur doet daar niet aan mee.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/mp3_duur.dart';

/// Een MPEG-1 Laag III framekop, stereo, zonder CRC.
///
/// `0xFF 0xFB` = sync + MPEG-1 + Laag III; daarna de bitsnelheid- en frequentie-index.
List<int> frameKop({int bitIndex = 14, int rateIndex = 0}) => [
      0xFF,
      0xFB,
      (bitIndex << 4) | (rateIndex << 2),
      0x00, // stereo
    ];

/// Een ID3v2.4-kop die zegt: er komt [maat] byte aan tag na deze tien bytes.
List<int> id3Kop(int maat) => [
      0x49, 0x44, 0x33, 0x04, 0x00, 0x00, //
      (maat >> 21) & 0x7F, (maat >> 14) & 0x7F, (maat >> 7) & 0x7F, maat & 0x7F,
    ];

File schrijf(Directory d, String naam, List<int> bytes) {
  final f = File('${d.path}${Platform.pathSeparator}$naam');
  f.writeAsBytesSync(Uint8List.fromList(bytes));
  return f;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('mp3duur'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('DE KERN: een CBR-bestand zonder Xing-blok wordt gewoon uitgerekend', () {
    // 320 kbit/s = 40000 byte/s. 400000 byte geluid is dus precies 10 seconden.
    final f = schrijf(tmp, 'cbr.mp3', [
      ...id3Kop(100),
      ...List.filled(100, 0),
      ...frameKop(),
      ...List.filled(400000 - 4, 0),
    ]);
    expect(readMp3Duur(f)!.inMilliseconds, 10000);
  });

  test('de ID3-tag telt niet mee als geluid', () {
    // Dezelfde 400000 byte geluid, maar met een tag van 50000 byte ervoor. Zou die meetellen, dan
    // kwam er 11,25 seconde uit.
    final f = schrijf(tmp, 'tag.mp3', [
      ...id3Kop(50000),
      ...List.filled(50000, 0),
      ...frameKop(),
      ...List.filled(400000 - 4, 0),
    ]);
    expect(readMp3Duur(f)!.inMilliseconds, 10000);
  });

  test('en een ID3v1-staart evenmin', () {
    final f = schrijf(tmp, 'v1.mp3', [
      ...frameKop(),
      ...List.filled(400000 - 4, 0),
      0x54, 0x41, 0x47, // "TAG"
      ...List.filled(125, 0),
    ]);
    expect(readMp3Duur(f)!.inMilliseconds, 10000);
  });

  test('een Xing-blok wint, want dat is exact', () {
    // 383 frames × 1152 monsters ÷ 44100 = 10,004 seconde. De bestandsgrootte zegt hier iets heel
    // anders, en juist daarom bewijst deze toets welke bron voorgaat.
    const frames = 383;
    final f = schrijf(tmp, 'xing.mp3', [
      ...frameKop(),
      ...List.filled(32, 0), // side-info, stereo MPEG-1
      0x58, 0x69, 0x6E, 0x67, // "Xing"
      0, 0, 0, 0x01, // vlaggen: alleen "frames"
      (frames >> 24) & 0xFF, (frames >> 16) & 0xFF, (frames >> 8) & 0xFF, frames & 0xFF,
      ...List.filled(90000, 0),
    ]);
    expect(readMp3Duur(f)!.inMilliseconds, closeTo(10004, 2));
  });

  test('een andere bitsnelheid geeft een andere duur', () {
    // 128 kbit/s = 16000 byte/s, dus 400000 byte is 25 seconden.
    final f = schrijf(tmp, 'traag.mp3', [
      ...frameKop(bitIndex: 9),
      ...List.filled(400000 - 4, 0),
    ]);
    expect(readMp3Duur(f)!.inMilliseconds, 25000);
  });

  group('en het zwijgt liever dan te gokken', () {
    test('een bestand zonder framekop', () {
      final f = schrijf(tmp, 'geen.mp3', List.filled(20000, 0x11));
      expect(readMp3Duur(f), isNull);
    });

    test('een ongeldige bitsnelheid-index', () {
      // 15 is "ongeldig" in de norm, en 0 is "vrij" — allebei geen getal om mee te delen.
      expect(readMp3Duur(schrijf(tmp, 'x.mp3', [...frameKop(bitIndex: 15), ...List.filled(9999, 0)])),
          isNull);
      expect(readMp3Duur(schrijf(tmp, 'y.mp3', [...frameKop(bitIndex: 0), ...List.filled(9999, 0)])),
          isNull);
    });

    test('een te klein bestand', () {
      expect(readMp3Duur(schrijf(tmp, 'kort.mp3', [0xFF, 0xFB])), isNull);
    });

    test('en een bestand dat er niet is', () {
      expect(readMp3Duur(File('${tmp.path}${Platform.pathSeparator}bestaatniet.mp3')), isNull);
    });
  });
}

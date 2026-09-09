/// WavPack en DSD moeten hun eigen kop en tekst kunnen lezen.
///
/// **Waarvoor dit bestaat.** Gemeld op 09-09-2026 met één schermafdruk: *"wat is WV, 0:00 min
/// ????"* — Snap! *The Power*, 228 MB op de schijf, en de app zette er `WV` en `0:00` achter. De
/// tagontleder kent APEv2 en las de titel wél; wat ontbrak is alles wat over het GELUID gaat, en dat
/// staat in de blokkop. Gemeten aan dat echte bestand: 65.881.600 monsters op 192 kHz = 5:43,
/// 32-bits zwevende komma, stereo.
///
/// En bij DSD las [readDsfKop] wel de duur maar niet de tekst — een bewuste grens die op dezelfde
/// dag is opgeheven, want een SACD-rip die als "Onbekende artiest" binnenkomt is net zo verloren.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/dsd_kop.dart';
import 'package:debridmusic/id3v2_kop.dart';
import 'package:debridmusic/wavpack_kop.dart';

/// Een WavPack-blokkop van 32 bytes, met de velden die ertoe doen.
Uint8List _wvKop({
  required int totalSamples,
  required int rateIndex,
  bool mono = false,
  bool zwevend = false,
  int magnitude = 15, // 15 -> 16 bits
  int versie = 0x410,
}) {
  final b = Uint8List(32);
  b.setRange(0, 4, 'wvpk'.codeUnits);
  b[8] = versie & 0xFF;
  b[9] = versie >> 8;
  b[11] = (totalSamples >> 32) & 0xFF;
  final laag = totalSamples & 0xFFFFFFFF;
  for (var i = 0; i < 4; i++) {
    b[12 + i] = (laag >> (8 * i)) & 0xFF;
  }
  final vlaggen = 3 | // vier bytes per monster
      (mono ? 4 : 0) |
      (zwevend ? 0x80 : 0) |
      ((magnitude & 0x1F) << 18) |
      ((rateIndex & 0xF) << 23);
  for (var i = 0; i < 4; i++) {
    b[24 + i] = (vlaggen >> (8 * i)) & 0xFF;
  }
  return b;
}

/// Een APEv2-blok met alleen een voettekst, zoals rippers het achter een `.wv` plakken.
Uint8List _apeBlok(Map<String, String> velden) {
  final items = <int>[];
  velden.forEach((k, v) {
    final waarde = v.codeUnits;
    for (var i = 0; i < 4; i++) {
      items.add((waarde.length >> (8 * i)) & 0xFF);
    }
    items.addAll([0, 0, 0, 0]); // vlaggen
    items.addAll(k.codeUnits);
    items.add(0);
    items.addAll(waarde);
  });
  final maat = items.length + 32; // inclusief de voettekst
  final voet = <int>[];
  voet.addAll('APETAGEX'.codeUnits);
  void u32(int x) {
    for (var i = 0; i < 4; i++) {
      voet.add((x >> (8 * i)) & 0xFF);
    }
  }

  u32(2000);
  u32(maat);
  u32(velden.length);
  u32(0);
  voet.addAll(List.filled(8, 0));
  return Uint8List.fromList([...items, ...voet]);
}

/// Een ID3v2.3-blok met tekstframes.
Uint8List _id3(Map<String, String> frames) {
  final body = <int>[];
  frames.forEach((id, tekst) {
    final t = [3, ...tekst.codeUnits]; // codering 3 = UTF-8
    body.addAll(id.codeUnits);
    body.addAll([(t.length >> 24) & 0xFF, (t.length >> 16) & 0xFF, (t.length >> 8) & 0xFF, t.length & 0xFF]);
    body.addAll([0, 0]);
    body.addAll(t);
  });
  final maat = body.length;
  return Uint8List.fromList([
    ...'ID3'.codeUnits, 3, 0, 0, //
    (maat >> 21) & 0x7F, (maat >> 14) & 0x7F, (maat >> 7) & 0x7F, maat & 0x7F,
    ...body,
  ]);
}

late Directory _tmp;
File _schrijf(String naam, List<int> bytes) =>
    File('${_tmp.path}${Platform.pathSeparator}$naam')..writeAsBytesSync(bytes);

void main() {
  setUp(() => _tmp = Directory.systemTemp.createTempSync('wvdsd'));
  tearDown(() {
    try {
      _tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('de kop van een WavPack', () {
    test('het echte geval: 192 kHz, zwevende komma, 5:43', () {
      // Precies de getallen uit Sabers bestand.
      final f = _schrijf('the power.wv',
          _wvKop(totalSamples: 65881600, rateIndex: 14, zwevend: true, magnitude: 24));
      final k = readWvKop(f)!;
      expect(k.sampleRate, 192000);
      expect(k.duration!.inSeconds, 343);
      expect(k.bitsPerSample, 32, reason: 'zwevende komma is per definitie 32 bits');
      expect(k.channels, 2);
      expect(k.zwevend, isTrue);
    });

    test('een gewone cd-rip in WavPack', () {
      final f = _schrijf('x.wv', _wvKop(totalSamples: 44100 * 200, rateIndex: 9, magnitude: 15));
      final k = readWvKop(f)!;
      expect(k.sampleRate, 44100);
      expect(k.bitsPerSample, 16);
      expect(k.duration, const Duration(seconds: 200));
    });

    test('mono telt als één kanaal', () {
      final f = _schrijf('m.wv', _wvKop(totalSamples: 44100, rateIndex: 9, mono: true));
      expect(readWvKop(f)!.channels, 1);
    });

    test('een onbekend totaal geeft GEEN 0:00', () {
      // Een stroom die nog liep toen hij ingepakt werd zegt 0xFFFFFFFF. Dat is "ik weet het niet",
      // en niet "nul seconden" — een verkeerde duur stuurt zowel het filen als het vergelijken aan.
      final f = _schrijf('s.wv', _wvKop(totalSamples: 0xFFFFFFFF, rateIndex: 9));
      expect(readWvKop(f)!.duration, isNull);
    });

    test('geen WavPack is null, en dat is geen fout', () {
      expect(readWvKop(_schrijf('n.wv', List.filled(64, 0))), isNull);
      expect(readWvKop(File('${_tmp.path}/bestaat-niet.wv')), isNull);
    });
  });

  group('de APEv2-tekst erachter', () {
    test('titel, artiest, album, nummer, jaar en genre', () {
      final f = _schrijf('t.wv', [
        ..._wvKop(totalSamples: 44100, rateIndex: 9),
        ..._apeBlok({
          'Title': 'The Power',
          'Artist': 'Snap!',
          'Album': 'World Power',
          'Track': '1/10',
          'Year': '1990-03-12',
          'Genre': 'Dance',
        }),
      ]);
      final t = readApeTags(f)!;
      expect(t.title, 'The Power');
      expect(t.artist, 'Snap!');
      expect(t.album, 'World Power');
      expect(t.trackNo, 1);
      expect(t.trackTotal, 10);
      expect(t.year, 1990, reason: 'alleen het jaartal uit een hele datum');
      expect(t.genre, 'Dance');
    });

    test('een ID3v1-staartje erachter verbergt het blok niet', () {
      // Veel rippers plakken er nog 128 bytes ID3v1 achter; dan staat de voettekst niet helemaal
      // achteraan en zou een lezer die alleen daar kijkt niets vinden.
      final f = _schrijf('u.wv', [
        ..._wvKop(totalSamples: 44100, rateIndex: 9),
        ..._apeBlok({'Title': 'The Power', 'Artist': 'Snap!'}),
        ...List.filled(128, 0),
      ]);
      expect(readApeTags(f)?.title, 'The Power');
    });

    test('zonder blok geen tags, en geen uitzondering', () {
      expect(readApeTags(_schrijf('v.wv', _wvKop(totalSamples: 1, rateIndex: 9))), isNull);
    });
  });

  group('de tekst van een SACD-rip', () {
    test('een DSF wijst naar zijn ID3v2-blok en dat wordt gelezen', () {
      final id3 = _id3({
        'TIT2': 'Adagio',
        'TPE1': 'Karajan',
        'TALB': 'Albinoni',
        'TRCK': '3/9',
        'TYER': '1985',
        'TCON': '(32)Classical',
      });
      // Een minimale DSF: de DSD-brok met de wijzer, dan een fmt-brok, dan het blok.
      final kop = Uint8List(80);
      kop.setRange(0, 4, 'DSD '.codeUnits);
      const meta = 80;
      for (var i = 0; i < 4; i++) {
        kop[20 + i] = (meta >> (8 * i)) & 0xFF;
      }
      kop.setRange(28, 32, 'fmt '.codeUnits);
      void le32(int at, int v) {
        for (var i = 0; i < 4; i++) {
          kop[at + i] = (v >> (8 * i)) & 0xFF;
        }
      }

      le32(52, 2); // kanalen
      le32(56, 2822400); // DSD64
      le32(60, 1); // bits
      le32(64, 2822400 * 30); // dertig seconden
      final f = _schrijf('a.dsf', [...kop, ...id3]);

      final k = readDsfKop(f)!;
      expect(k.duration, const Duration(seconds: 30));
      expect(k.sampleRate, 2822400);
      expect(k.metaBegin, meta);

      final t = readId3v2(f, vanaf: k.metaBegin)!;
      expect(t.title, 'Adagio');
      expect(t.artist, 'Karajan');
      expect(t.album, 'Albinoni');
      expect(t.trackNo, 3);
      expect(t.trackTotal, 9);
      expect(t.year, 1985);
      expect(t.genre, 'Classical', reason: 'het oude nummer tussen haakjes hoort er niet bij');
    });

    test('alleen een nummer als genre levert liever niets op dan een gok', () {
      final f = _schrijf('b.dsf', _id3({'TIT2': 'X', 'TCON': '(17)'}));
      expect(readId3v2(f)!.genre, isNull);
    });

    test('een blok dat er niet is, is geen fout', () {
      expect(readId3v2(_schrijf('c.dsf', List.filled(64, 0))), isNull);
      expect(readId3v2(_schrijf('d.dsf', _id3({'TIT2': 'X'})), vanaf: 9999), isNull);
    });
  });
}

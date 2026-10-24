// WAV wordt weer aangeboden en bij binnenkomst FLAC (Saber, 24-10-2026: "WAV halen, omzetten naar FLAC").
//
// Tot dan liet de app WAV helemaal weg (no_wav_download_test): een WAV kan de tags van deze app niet dragen, en zes
// WAV's landden als naamloze singles onder "Onbekende artiest". Maar veel vinyl- en studio-rips staan alleen als WAV.
// Nu zet `keurOverdracht` elke binnengekomen WAV verliesvrij om naar FLAC, vóór al het andere.
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/ffmpeg.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:debridmusic/wav_naar_flac.dart';
import 'package:flutter_test/flutter_test.dart';

SoulseekFile f(String naam, {int size = 30000000, bool freeSlots = true, int speed = 500}) => SoulseekFile(
      username: 'iemand',
      filename: 'C:\\muziek\\$naam',
      size: size,
      speed: speed,
      queueLength: 0,
      freeSlots: freeSlots,
    );

/// Een echte WAV: [seconden] stilte met een toon erin, 16 of 24 bit.
File _wav(String pad, {int bits = 24, int rate = 44100, double seconden = .5}) {
  final n = (rate * seconden).round();
  final bytes = bits ~/ 8;
  final data = ByteData(n * 2 * bytes);
  for (var i = 0; i < n; i++) {
    final v = ((i % 100) - 50) * (bits == 24 ? 40000 : 300);
    for (var k = 0; k < 2; k++) {
      final o = (i * 2 + k) * bytes;
      for (var b = 0; b < bytes; b++) {
        data.setUint8(o + b, (v >> (8 * b)) & 0xff);
      }
    }
  }
  final kop = ByteData(44)
    ..setUint32(0, 0x52494646, Endian.big)
    ..setUint32(4, 36 + data.lengthInBytes, Endian.little)
    ..setUint32(8, 0x57415645, Endian.big)
    ..setUint32(12, 0x666d7420, Endian.big)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 2, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2 * bytes, Endian.little)
    ..setUint16(32, 2 * bytes, Endian.little)
    ..setUint16(34, bits, Endian.little)
    ..setUint32(36, 0x64617461, Endian.big)
    ..setUint32(40, data.lengthInBytes, Endian.little);
  return File(pad)
    ..writeAsBytesSync([...kop.buffer.asUint8List(), ...data.buffer.asUint8List()]);
}

void main() {
  group('aangeboden', () {
    test('een WAV komt weer in de lijst: na FLAC, vóór mp3', () {
      final uit = sortSoulseek([
        f('c.mp3', speed: 9000),
        f('b.wav'),
        f('a.flac', speed: 10),
        f('d.WAV', speed: 100),
      ]);
      expect(uit.map((x) => x.ext), ['flac', 'wav', 'wav', 'mp3']);
    });

    test('ook als hij de enige aanbieding is', () {
      expect(sortSoulseek([f('01 - Nummer.wav')]).map((x) => x.ext), ['wav']);
    });

    test('niet-audio blijft geweerd', () {
      expect(sortSoulseek([f('hoes.jpg'), f('lees.nfo'), f('a.flac')]).map((x) => x.ext), ['flac']);
    });
  });

  group('omgezet bij binnenkomst', () {
    late Directory map;
    setUp(() => map = Directory.systemTemp.createTempSync('dm_wav_'));
    tearDown(() {
      DownloadManager.wavOmzetter = null;
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('keurOverdracht maakt van een WAV een FLAC, en een WAV die niet om te zetten is een mislukte poging',
        () async {
      final wav = _wav('${map.path}${Platform.pathSeparator}01 - Nummer.wav');
      DownloadManager.wavOmzetter = (p) async {
        expect(p, wav.path);
        final uit = p.replaceAll('.wav', '.flac');
        File(uit).writeAsStringSync('flac');
        return uit;
      };
      final r = await DownloadManager.keurOverdracht(SlskDone(wav.path));
      expect(r, isA<SlskDone>());
      expect((r as SlskDone).path, endsWith('01 - Nummer.flac'));

      final wav2 = _wav('${map.path}${Platform.pathSeparator}02 - Nummer.wav');
      DownloadManager.wavOmzetter = (_) async => null;
      final r2 = await DownloadManager.keurOverdracht(SlskDone(wav2.path));
      expect(r2, isA<SlskFail>(), reason: 'de race probeert dan de volgende peer');

      DownloadManager.wavOmzetter = (_) async => fail('een FLAC wordt niet omgezet');
      final flac = File('${map.path}${Platform.pathSeparator}03.flac')..writeAsStringSync('x');
      final r3 = await DownloadManager.keurOverdracht(SlskDone(flac.path));
      expect(r3, isA<SlskDone>());
    });

    test('echt omgezet met ffmpeg: verliesvrij, dezelfde diepte, de WAV weg', () async {
      final ffmpeg = Ffmpeg().pad;
      if (ffmpeg == null) {
        markTestSkipped('geen ffmpeg op deze machine');
        return;
      }
      for (final bits in [16, 24]) {
        final wav = _wav('${map.path}${Platform.pathSeparator}toon $bits.wav', bits: bits);
        final flac = await wavNaarFlac(wav.path);
        expect(flac, isNotNull, reason: '$bits bit');
        expect(File(flac!).existsSync(), isTrue);
        expect(flac, endsWith('toon $bits.flac'));
        expect(wav.existsSync(), isFalse, reason: 'de WAV gaat weg na een gelukte omzetting');
        final kop = File(flac).readAsBytesSync();
        expect(String.fromCharCodes(kop.sublist(0, 4)), 'fLaC');
        // STREAMINFO: bits per sample staan in byte 12–13 van het blok (na de 4 bytes "fLaC" en de 4 van de blokkop).
        final b = ((kop[8 + 12] & 0x01) << 4 | (kop[8 + 13] >> 4)) + 1;
        expect(b, bits, reason: 'dezelfde diepte als de WAV');
      }
    });

    test('lukt het niet (kapotte WAV), dan blijft de WAV staan en komt er null terug', () async {
      if (Ffmpeg().pad == null) {
        markTestSkipped('geen ffmpeg op deze machine');
        return;
      }
      final kapot = File('${map.path}${Platform.pathSeparator}kapot.wav')..writeAsStringSync('geen wav');
      expect(await wavNaarFlac(kapot.path), isNull);
      expect(kapot.existsSync(), isTrue);
      expect(map.listSync().whereType<File>().where((x) => x.path.endsWith('.deel')), isEmpty,
          reason: 'geen halve FLAC achtergelaten');
    });
  });
}

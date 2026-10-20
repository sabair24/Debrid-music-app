// De frame-lezer van flac_frames.dart, op een zelfgebouwde FLAC: STREAMINFO, opvulling, en frames met
// CONSTANT-subframes. De waarde 0xFFF8 in de audio legt overal valse synchronisatiecodes neer — die mogen
// nooit als frame tellen. De echte proef (libmpv, een nummer uit de bibliotheek) staat in de kladmap.
import 'dart:typed_data';

import 'package:debridmusic/flac_frames.dart';
import 'package:flutter_test/flutter_test.dart';

int _crc8(List<int> b) {
  var crc = 0;
  for (final x in b) {
    crc ^= x;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 0x80) != 0 ? ((crc << 1) ^ 0x07) & 0xFF : (crc << 1) & 0xFF;
    }
  }
  return crc;
}

List<int> _utf8Getal(int n) {
  if (n < 0x80) return [n];
  if (n < 0x800) return [0xC0 | (n >> 6), 0x80 | (n & 0x3F)];
  return [0xE0 | (n >> 12), 0x80 | ((n >> 6) & 0x3F), 0x80 | (n & 0x3F)];
}

/// Eén frame van 4096 monsters, stereo, 16 bit, 44,1 kHz, met constante waarden — en [vulling] bytes
/// erachter, zodat het zo groot is als een echt frame (de lezer kijkt alleen naar koppen).
List<int> _frame(int n, int waarde, {int vulling = 0}) {
  final kop = [0xFF, 0xF8, 0xC9, 0x18, ..._utf8Getal(n)];
  kop.add(_crc8(kop));
  return [
    ...kop, 0x00, waarde >> 8, waarde & 0xFF, 0x00, waarde >> 8, waarde & 0xFF,
    for (var i = 0; i < vulling; i++) i % 97 == 0 ? 0xFF : (i % 97 == 1 ? 0xF8 : 0x55),
    0x00, 0x00,
  ];
}

({Uint8List bytes, int audioBegin, List<int> frameBegin}) _flac(
    {int frames = 60, bool opvulling = true, int vulling = 0}) {
  final si = ByteData(34)
    ..setUint16(0, 4096)
    ..setUint16(2, 4096)
    ..setUint64(10, (44100 << 44) | (1 << 41) | (15 << 36) | (frames * 4096));
  final b = BytesBuilder()
    ..add('fLaC'.codeUnits)
    ..add([opvulling ? 0x00 : 0x80, 0, 0, 34])
    ..add(si.buffer.asUint8List());
  if (opvulling) {
    b
      ..add([0x81, 0, 0x10, 0x00])
      ..add(Uint8List(4096));
  }
  final audioBegin = b.length;
  final begin = <int>[];
  for (var n = 0; n < frames; n++) {
    begin.add(b.length);
    // Om en om een waarde met een valse synchronisatiecode erin.
    b.add(_frame(n, n.isEven ? 0xFFF8 : 0x1234, vulling: vulling));
  }
  return (bytes: b.toBytes(), audioBegin: audioBegin, frameBegin: begin);
}

void main() {
  final f = _flac();
  final si = flacStroominfo(f.bytes)!;
  Uint8List lees(Uint8List b, int v, int n) => Uint8List.sublistView(b, v, v + n > b.length ? b.length : v + n);

  test('STREAMINFO en de blokken', () {
    expect((si.minBlok, si.maxBlok, si.frequentie, si.kanalen, si.bits, si.monsters), (4096, 4096, 44100, 2, 16, 60 * 4096));
    final blokken = flacBlokken(f.bytes)!;
    expect([for (final b in blokken) b.soort], [0, 1]);
    expect(blokken.last.begin + 4 + blokken.last.lengte, f.audioBegin);
    expect(flacBlokken(Uint8List.sublistView(f.bytes, 0, 100)), isNull, reason: 'kop nog niet compleet');
  });

  test('een framekop: geldig op het begin, niet in de audio, niet met een verkeerde CRC', () {
    final fr = flacFrameKop(f.bytes, f.frameBegin[7], si, vast: true)!;
    expect((fr.monster, fr.blok), (7 * 4096, 4096));
    var vals = 0;
    for (var i = f.audioBegin; i < f.bytes.length - 6; i++) {
      if (f.frameBegin.contains(i)) continue;
      if (flacFrameKop(f.bytes, i, si, vast: true) != null) vals++;
    }
    expect(vals, 0, reason: 'de 0xFFF8 in de audio is geen frame');
    final kapot = Uint8List.fromList(f.bytes);
    kapot[f.frameBegin[7] + 5] ^= 0x01; // de CRC-8
    expect(flacFrameKop(kapot, f.frameBegin[7], si, vast: true), isNull);
  });

  test('het frame bij een monster: begin, midden, grens, laatste — en niets voorbij wat er is', () {
    FlacFrame? bij(int doel, {int? einde}) => flacFrameBij(doel,
        audioBegin: f.audioBegin, einde: einde ?? f.bytes.length, si: si, lees: (v, n) => lees(f.bytes, v, n));
    expect(bij(0)!.byte, f.frameBegin[0]);
    expect(bij(30 * 4096 + 17)!.byte, f.frameBegin[30]);
    expect(bij(31 * 4096)!.byte, f.frameBegin[31], reason: 'precies op de grens: het frame dat daar begint');
    expect(bij(31 * 4096 - 1)!.byte, f.frameBegin[30]);
    expect(bij(59 * 4096 + 4000)!.byte, f.frameBegin[59]);
    expect(bij(40 * 4096, einde: f.frameBegin[20]), isNull, reason: 'frame 40 is nog niet binnen');
  });

  test('een bestand van 12 MB: halveren vindt het frame met een paar leesbeurten', () {
    final groot = _flac(frames: 2000, opvulling: false, vulling: 6000);
    final g = flacStroominfo(groot.bytes)!;
    var beurten = 0;
    final fr = flacFrameBij(1345 * 4096 + 5,
        audioBegin: groot.audioBegin,
        einde: groot.bytes.length,
        si: g,
        lees: (v, n) {
          beurten++;
          return lees(groot.bytes, v, n);
        })!;
    expect(fr.byte, groot.frameBegin[1345]);
    expect(beurten, lessThan(40));
  });
}

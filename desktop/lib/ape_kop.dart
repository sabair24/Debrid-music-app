/// De kop van een Monkey's Audio-bestand (`.ape`): frequentie, diepte en duur.
///
/// **Waarom dit er is.** Op 06-10-2026 stond *Mr. Vain* van Culture Beat in de catalogus als
/// `ape 0/0`: geen frequentie, geen diepte. De tekst kwam wél binnen (het APEv2-blok achteraan leest
/// `wavpack_kop.dart` al), maar over het GELUID wist de app niets. Een telefoon op 5G in de cd-stand
/// liet het bestand daardoor ongemoeid — er was niets "aantoonbaar te hoog" — en kreeg 216 MB op
/// 24/192 over de lijn in plaats van zo'n 30 MB op 16/44.1.
///
/// Zelfde vorm als `wavpack_kop.dart` en `dsd_kop.dart`: één keer openen, een kop lezen, altijd
/// sluiten. Een handvat dat open blijft maakt een bestand op Windows de rest van de sessie
/// onverplaatsbaar.
library;

import 'dart:io';

import 'kapot_bestand.dart' show id3TagLengte;

/// Wat er in de kop van een APE staat.
class ApeKop {
  /// Hoe lang het stuk duurt, of null als de kop geen frames telt.
  final Duration? duration;

  /// Monsters per seconde.
  final int sampleRate;

  /// Bits per monster: 8, 16, 24 of 32.
  final int bitsPerSample;

  final int channels;

  const ApeKop({
    required this.duration,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.channels,
  });
}

/// Leest de kop van [f], of null als het geen Monkey's Audio is.
///
/// Twee vormen. Vanaf versie 3.98 (`3980`) eerst een beschrijving van minstens 52 bytes, en pas
/// dáárachter de eigenlijke kop; ouder is één kop met de diepte als vlaggen. Een ID3v2-blok vooraan
/// wordt overgeslagen, zoals bij `flacBegin`. Gemeten op *Mr. Vain*: versie 3990, beschrijving 52
/// bytes, 878 frames van 73.728 monsters, de laatste 442, 24 bit, 2 kanalen, 192 kHz — 5:36,77,
/// precies wat ffprobe zegt.
ApeKop? readApeKop(File f) {
  RandomAccessFile? raf;
  try {
    raf = f.openSync();
    var begin = 0;
    for (var i = 0; i < 3; i++) {
      raf.setPositionSync(begin);
      final n = id3TagLengte(raf.readSync(10));
      if (n == null) break;
      begin += n;
    }
    raf.setPositionSync(begin);
    final b = raf.readSync(128);
    if (b.length < 32) return null;
    if (String.fromCharCodes(b.sublist(0, 4)) != 'MAC ') return null;
    int u16(int i) => b[i] | (b[i + 1] << 8);
    int u32(int i) => b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);

    final versie = u16(4);
    final int bits, kanalen, hz, frames, laatste, perFrame;
    if (versie >= 3980) {
      final beschrijving = u32(8);
      final h = beschrijving;
      if (beschrijving < 52 || h + 24 > b.length) return null;
      perFrame = u32(h + 4);
      laatste = u32(h + 8);
      frames = u32(h + 12);
      bits = u16(h + 16);
      kanalen = u16(h + 18);
      hz = u32(h + 20);
    } else {
      final compressie = u16(6);
      final vlaggen = u16(8);
      kanalen = u16(10);
      hz = u32(12);
      frames = u32(24);
      laatste = u32(28);
      // De diepte als vlaggen: 1 = 8 bit, 8 = 24 bit, anders 16.
      bits = (vlaggen & 1) != 0 ? 8 : ((vlaggen & 8) != 0 ? 24 : 16);
      // En de framegrootte uit de versie, zoals Monkey's Audio hem zelf afleidt.
      perFrame = versie >= 3950
          ? 73728 * 4
          : (versie >= 3900 || (versie >= 3800 && compressie == 4000) ? 73728 : 9216);
    }
    if (hz <= 0 || hz > 1536000) return null;
    final monsters = frames <= 0 ? 0 : (frames - 1) * perFrame + laatste;
    return ApeKop(
      duration: monsters <= 0 ? null : Duration(milliseconds: (monsters * 1000 / hz).round()),
      sampleRate: hz,
      bitsPerSample: bits >= 8 && bits <= 32 ? bits : 0,
      channels: kanalen,
    );
  } catch (_) {
    return null;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {/* een bestand dat al weg is hoeft niet dicht */}
  }
}

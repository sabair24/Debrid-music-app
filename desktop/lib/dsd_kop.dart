/// De kop van een DSF-bestand — een SACD-rip.
///
/// **Waarom dit er is.** DSD is geen PCM en geen enkele tagontleder die deze app gebruikt kent het.
/// Zo'n bestand kwam dus binnen als een naamloze regel met `0:00` erachter, en dat is precies de
/// klacht van 31-08-2026. De speelduur staat er nochtans gewoon in, in een kop van 80 bytes die elk
/// DSF-bestand moet hebben: de decoder kan het geluid anders niet afspelen.
///
/// **Wat hier NIET gebeurt.** Een DSF kan ook een ID3v2-blok dragen — de DSD-brok wijst met een
/// pointer naar het einde van het bestand. Dat wordt hier niet gelezen. Titel en artiest komen dus
/// nog altijd uit de bestandsnaam. Dat is een bewuste grens: de duur is er ALTIJD en is één simpele
/// deling, een ID3-ontleder is een heel ander verhaal, en een halve ontleder die af en toe iets
/// verkeerds leest is erger dan geen.
///
/// **En `.dff` ook niet.** DSDIFF is een andere doos, IFF-stijl en big-endian. Die valt terug op
/// `0:00`, en dat staat er liever dan een verzonnen getal.
library;

import 'dart:io';

/// Wat er in de kop van een DSF staat.
class DsdKop {
  /// Hoe lang het stuk duurt. Null als de kop het niet zegt.
  final Duration? duration;

  /// Monsters per seconde: 2822400 voor DSD64, 5644800 voor DSD128.
  final int sampleRate;

  /// Bij DSD altijd 1 — één bit per monster, dat ís het formaat.
  final int bitsPerSample;

  /// 2 voor stereo, 6 voor een meerkanaals-SACD.
  final int channels;

  const DsdKop({
    required this.duration,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.channels,
  });
}

/// Leest de kop van [f], of null als het geen DSF is of de kop niet klopt.
///
/// Opent het bestand één keer, leest tachtig bytes en sluit het weer — ook als er iets misgaat. Dat
/// laatste is hier geen beleefdheid: een handvat dat open blijft maakt het bestand op Windows de rest
/// van de sessie onverplaatsbaar en onverwijderbaar. Zie `tagParserWouldClaim`.
DsdKop? readDsfKop(File f) {
  RandomAccessFile? raf;
  try {
    raf = f.openSync();
    // De DSD-brok: "DSD " gevolgd door 24 bytes. Daarna begint de fmt-brok.
    if (String.fromCharCodes(raf.readSync(4)) != 'DSD ') return null;
    raf.setPositionSync(28);
    if (String.fromCharCodes(raf.readSync(4)) != 'fmt ') return null;

    // De rest van de fmt-brok: 48 bytes, alles little-endian. Index i hieronder staat op
    // brokpositie i + 4.
    final d = raf.readSync(48);
    if (d.length < 48) return null;
    int le32(int at) => d[at] | (d[at + 1] << 8) | (d[at + 2] << 16) | (d[at + 3] << 24);

    final channels = le32(20); // brokpositie 24: channel num
    final sampleRate = le32(24); // brokpositie 28: sampling frequency
    final bits = le32(28); // brokpositie 32: bits per sample
    // Brokpositie 36: het aantal monsters PER KANAAL, acht bytes. De bovenste vier tellen pas mee
    // vanaf ongeveer vierhonderd jaar muziek, maar ze overslaan zou het getal stilzwijgend afkappen.
    final laag = le32(32) & 0xFFFFFFFF;
    final hoog = le32(36);
    final totalSamples = laag + hoog * 0x100000000;

    if (sampleRate <= 0 || totalSamples <= 0) return null;
    final seconden = totalSamples / sampleRate;
    // Een kop die iets onmogelijks beweert is een kapotte kop, en dan is niets weten beter dan dit
    // geloven: de duur stuurt zowel `fileOfRecording` als `firstIsBetter` aan.
    if (seconden > 24 * 3600) return null;

    return DsdKop(
      duration: Duration(milliseconds: (seconden * 1000).round()),
      sampleRate: sampleRate,
      bitsPerSample: bits > 0 ? bits : 1,
      channels: channels > 0 ? channels : 2,
    );
  } catch (_) {
    return null;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
}

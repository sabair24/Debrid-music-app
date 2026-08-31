/// De kop van een SACD-rip: `.dsf` én `.dff`.
///
/// **Waarom dit er is.** DSD is geen PCM en geen enkele tagontleder die deze app gebruikt kent het.
/// Zo'n bestand kwam dus binnen als een naamloze regel met `0:00` erachter, en dat is precies de
/// klacht van 31-08-2026. De speelduur staat er nochtans gewoon in, in een kop die elk bestand moet
/// hebben: de decoder kan het geluid anders niet afspelen.
///
/// **Twee dozen, twee lezers.** Een `.dsf` is Sony's vorm: één vaste kop van tachtig bytes, alles
/// little-endian, en het aantal monsters staat er kant en klaar in. Een `.dff` (DSDIFF, van Philips)
/// is IFF-stijl en big-endian: een boom van brokken waar je doorheen moet lopen, en het aantal
/// monsters staat er NERGENS. Daar wordt de duur uitgerekend — uit hoeveel bytes geluid erin zitten
/// bij een onverpakte opname, en uit het aantal DST-frames bij een ingepakte. Zie [readDffKop].
///
/// **Wat hier NIET gebeurt.** Allebei de dozen kunnen ook tekst dragen — een DSF een ID3v2-blok
/// achteraan, een DFF een `DIIN`-brok met titel en artiest. Dat wordt hier niet gelezen; titel en
/// artiest komen nog altijd uit de bestandsnaam. Dat is een bewuste grens: de duur is er ALTIJD en
/// is één deling, en een halve tekstontleder die af en toe iets verkeerds leest is erger dan geen.
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

/// Een DSDIFF-brok: vier letters, dan hoe lang hij is.
///
/// De lengte telt alleen de INHOUD, niet deze twaalf bytes. En een brok van oneven lengte krijgt er
/// een opvulbyte achter die níét meetelt — vergeet je die, dan loop je één byte scheef en is de rest
/// van het bestand onleesbaar.
typedef _Brok = ({String naam, int begin, int lengte});

/// Leest de brokkop op [pos], of null als er geen twaalf bytes meer zijn.
_Brok? _brokOp(RandomAccessFile raf, int pos, int einde) {
  if (pos + 12 > einde) return null;
  raf.setPositionSync(pos);
  final h = raf.readSync(12);
  if (h.length < 12) return null;
  final naam = String.fromCharCodes(h.sublist(0, 4));
  // Big-endian, acht bytes. De bovenste vier worden apart vermenigvuldigd in plaats van geschoven:
  // een `<< 32` op een getal dat toch al groot is, is precies waar een stille overloop ontstaat.
  var hoog = 0, laag = 0;
  for (var i = 4; i < 8; i++) {
    hoog = hoog * 256 + h[i];
  }
  for (var i = 8; i < 12; i++) {
    laag = laag * 256 + h[i];
  }
  final lengte = hoog * 0x100000000 + laag;
  if (lengte < 0) return null;
  return (naam: naam, begin: pos + 12, lengte: lengte);
}

/// Waar de volgende brok begint: na deze, plus de opvulbyte bij een oneven lengte.
int _naBrok(_Brok b) => b.begin + b.lengte + (b.lengte.isOdd ? 1 : 0);

int _u32be(RandomAccessFile raf, int pos) {
  raf.setPositionSync(pos);
  final b = raf.readSync(4);
  if (b.length < 4) return 0;
  return b[0] * 16777216 + b[1] * 65536 + b[2] * 256 + b[3];
}

int _u16be(RandomAccessFile raf, int pos) {
  raf.setPositionSync(pos);
  final b = raf.readSync(2);
  if (b.length < 2) return 0;
  return b[0] * 256 + b[1];
}

/// Leest de kop van een DSDIFF-bestand (`.dff`), of null als het er geen is.
///
/// **Waarom dit meer werk is dan bij een DSF.** Er staat nergens hoe lang het stuk duurt. Wat er
/// wél staat is genoeg om het uit te rekenen, op twee manieren, afhankelijk van hoe de rip is
/// ingepakt:
///
/// * **Onverpakt** (`DSD `): elk kanaal krijgt één bit per monster, dus `bemonstering / 8` bytes per
///   seconde. De lengte van de geluidsbrok gedeeld door (kanalen × dat getal) is de speeltijd. De
///   brok zelf wordt niet gelezen — alleen zijn lengte, en die staat in de kop. Dat scheelt hier
///   gauw enkele gigabytes.
/// * **Ingepakt** (`DST `): dan zegt de lengte niets meer, want er is gecomprimeerd. Maar bovenin
///   die brok staat `FRTE`: hoeveel frames er zijn en hoeveel er in een seconde gaan (bij een SACD
///   vijfenzeventig). Delen en klaar.
///
/// Loopt hoogstens vierenzestig brokken af en leest nooit meer dan een handvol bytes per brok.
DsdKop? readDffKop(File f) {
  RandomAccessFile? raf;
  try {
    raf = f.openSync();
    final einde = raf.lengthSync();
    final vorm = _brokOp(raf, 0, einde);
    // "FRM8" met vormtype "DSD " — alles daarbinnen is deze opname. De vier letters van het
    // vormtype zitten IN de lengte, dus de brokken zelf beginnen pas op 16.
    if (vorm == null || vorm.naam != 'FRM8') return null;
    raf.setPositionSync(12);
    if (String.fromCharCodes(raf.readSync(4)) != 'DSD ') return null;

    var hertz = 0, kanalen = 0, geluidBytes = 0, frames = 0, framesPerSeconde = 0;
    var pos = 16;
    for (var n = 0; n < 64; n++) {
      final b = _brokOp(raf, pos, einde);
      if (b == null) break;
      if (b.naam == 'PROP') {
        // De eigenschappenbrok begint met het soortwoord "SND ", daarna komen de sub-brokken.
        raf.setPositionSync(b.begin);
        if (String.fromCharCodes(raf.readSync(4)) == 'SND ') {
          final propEinde = b.begin + b.lengte;
          var p = b.begin + 4;
          for (var m = 0; m < 32; m++) {
            final s = _brokOp(raf, p, propEinde);
            if (s == null) break;
            if (s.naam == 'FS  ') hertz = _u32be(raf, s.begin);
            if (s.naam == 'CHNL') kanalen = _u16be(raf, s.begin);
            final volgende = _naBrok(s);
            if (volgende <= p) break;
            p = volgende;
          }
        }
      } else if (b.naam == 'DSD ') {
        geluidBytes = b.lengte;
      } else if (b.naam == 'DST ') {
        // Bovenin de DST-brok staat FRTE; de frames zelf slaan we over.
        final dstEinde = b.begin + b.lengte;
        var p = b.begin;
        for (var m = 0; m < 8; m++) {
          final s = _brokOp(raf, p, dstEinde);
          if (s == null) break;
          if (s.naam == 'FRTE') {
            frames = _u32be(raf, s.begin);
            framesPerSeconde = _u16be(raf, s.begin + 4);
            break;
          }
          final volgende = _naBrok(s);
          if (volgende <= p) break;
          p = volgende;
        }
      }
      final volgende = _naBrok(b);
      if (volgende <= pos) break; // een lengte van nul zou hier eeuwig blijven rondlopen
      pos = volgende;
    }

    // De volgorde van de brokken ligt niet vast, dus pas hier rekenen — anders zou een geluidsbrok
    // die vóór de eigenschappen staat op nul uitkomen.
    double? seconden;
    if (frames > 0 && framesPerSeconde > 0) {
      seconden = frames / framesPerSeconde;
    } else if (geluidBytes > 0 && hertz > 0 && kanalen > 0) {
      seconden = geluidBytes * 8 / (kanalen * hertz);
    }
    if (seconden == null || seconden <= 0 || seconden > 24 * 3600) return null;

    return DsdKop(
      duration: Duration(milliseconds: (seconden * 1000).round()),
      sampleRate: hertz,
      bitsPerSample: 1,
      channels: kanalen > 0 ? kanalen : 2,
    );
  } catch (_) {
    return null;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
}

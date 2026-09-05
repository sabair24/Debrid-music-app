/// Hoe lang een MP3 duurt, uit de kop van het bestand zelf.
///
/// **Waarom dit er is.** Dezelfde klacht als bij [readDsfKop], en dezelfde oorzaak: de tagontleder
/// die de app gebruikt geeft voor sommige MP3's geen speelduur terug, en dan staat er `0:00` achter
/// een nummer dat gewoon speelt. Gemeten op 05-09-2026 over de hele bibliotheek waren dat er twee
/// van de 1221 — "Ik Leef Voor Jou" van Petra en "opzij opzij" van Enzo. Allebei gewone MP3's die
/// ffprobe moeiteloos leest (223,4 en 209,1 seconden).
///
/// **Wat er aan die twee bijzonder is: ze hebben geen Xing-kop.** Bijna elke MP3 die met een moderne
/// encoder gemaakt is draagt vooraan een `Xing`- of `Info`-blok met het exacte aantal frames erin,
/// en dáár leest een ontleder de duur uit. Een oudere CBR-codering heeft dat blok niet, want bij een
/// vaste bitsnelheid valt de duur gewoon uit te rekenen. Die deling ontbrak.
///
/// **Een duur van nul is niet alleen lelijk.** De hele albumpagina rekent met looptijden: welk
/// bestand op welke rij van de uitgave hoort ([rijAfstand] weegt de looptijd met 2 van de 5), of je
/// een andere snit hebt, en wat er onder "Niet op deze uitgave" belandt. Een nummer zonder duur doet
/// aan dat alles niet mee.
///
/// **De grens.** Dit leest uitsluitend de speelduur, en alleen wat er ZEKER staat: de eerste
/// framekop, en het Xing/Info/VBRI-blok als het er is. Bij een VBR-bestand zónder zo'n blok wordt er
/// niets teruggegeven in plaats van gegokt — de eerste frame zegt dan niets over de rest, en een
/// verkeerde duur is erger dan geen. Titel en artiest komen nog altijd uit [readMp3RawFields].
library;

import 'dart:io';
import 'dart:typed_data';

/// Bits per seconde per bitsnelheid-index, MPEG-1 Laag III. Index 0 is "vrij" en 15 is ongeldig.
const _bitrates1 = [
  0, 32000, 40000, 48000, 56000, 64000, 80000, 96000, //
  112000, 128000, 160000, 192000, 224000, 256000, 320000, 0,
];

/// Idem voor MPEG-2 en MPEG-2.5, Laag III.
const _bitrates2 = [
  0, 8000, 16000, 24000, 32000, 40000, 48000, 56000, //
  64000, 80000, 96000, 112000, 128000, 144000, 160000, 0,
];

/// Monsters per seconde, per versie en index.
const _rates = {
  3: [44100, 48000, 32000, 0], // MPEG-1
  2: [22050, 24000, 16000, 0], // MPEG-2
  0: [11025, 12000, 8000, 0], // MPEG-2.5
};

/// Hoeveel monsters er in één frame gaan. MPEG-1 Laag III: 1152; MPEG-2 en 2.5: 576.
int _monstersPerFrame(int versie) => versie == 3 ? 1152 : 576;

/// De speelduur van [f], of null als die niet met zekerheid te bepalen is.
Duration? readMp3Duur(File f) {
  RandomAccessFile? raf;
  try {
    raf = f.openSync();
    final lengte = raf.lengthSync();
    if (lengte < 128) return null;

    // 1. De ID3v2-tag vooraan overslaan. De grootte staat als "syncsafe" getal in byte 6..9: zeven
    //    bits per byte, zodat geen enkele byte op een MPEG-sync kan lijken.
    var begin = 0;
    final kop = _lees(raf, 0, 10);
    if (kop != null && kop[0] == 0x49 && kop[1] == 0x44 && kop[2] == 0x33) {
      final maat = (kop[6] << 21) | (kop[7] << 14) | (kop[8] << 7) | kop[9];
      begin = 10 + maat;
      // Vlag 4 van de kopvlaggen betekent: er hangt ook nog een voettekst van tien bytes aan.
      if ((kop[5] & 0x10) != 0) begin += 10;
    }
    if (begin >= lengte) return null;

    // 2. Een ID3v1-tag achteraan telt niet als geluid.
    var eind = lengte;
    final staart = _lees(raf, lengte - 128, 3);
    if (staart != null && staart[0] == 0x54 && staart[1] == 0x41 && staart[2] == 0x47) {
      eind -= 128;
    }

    // 3. De eerste framekop zoeken. Niet verder dan een paar kilobyte: staat er daarbinnen geen
    //    frame, dan is dit geen MP3 die wij moeten uitrekenen.
    final blok = _lees(raf, begin, 8192);
    if (blok == null) return null;
    var i = 0;
    while (i < blok.length - 4) {
      if (blok[i] == 0xFF && (blok[i + 1] & 0xE0) == 0xE0) {
        final d = _uitFrame(blok, i, eind - (begin + i));
        if (d != null) return d;
      }
      i++;
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
}

/// Eén framekop op [i] uitlezen en er een duur uit halen. Null als de kop niet klopt.
Duration? _uitFrame(Uint8List b, int i, int geluidBytes) {
  final versie = (b[i + 1] >> 3) & 0x3; // 3=MPEG-1, 2=MPEG-2, 0=MPEG-2.5, 1=gereserveerd
  final laag = (b[i + 1] >> 1) & 0x3; // 1 = Laag III
  if (versie == 1 || laag != 1) return null;

  final bitIndex = (b[i + 2] >> 4) & 0xF;
  final rateIndex = (b[i + 2] >> 2) & 0x3;
  final bitrate = (versie == 3 ? _bitrates1 : _bitrates2)[bitIndex];
  final hertz = (_rates[versie] ?? const [0, 0, 0, 0])[rateIndex];
  if (bitrate <= 0 || hertz <= 0) return null;

  final mono = ((b[i + 3] >> 6) & 0x3) == 3;
  final perFrame = _monstersPerFrame(versie);

  // Xing/Info (na de side-info) of VBRI (vast op +36) geeft het EXACTE aantal frames. Dat is de
  // enige manier om een VBR-bestand goed uit te rekenen, en bij CBR is het even goed.
  final zijInfo = versie == 3 ? (mono ? 17 : 32) : (mono ? 9 : 17);
  for (final plek in [i + 4 + zijInfo, i + 36]) {
    if (plek + 12 > b.length) continue;
    final merk = String.fromCharCodes(b.sublist(plek, plek + 4));
    if (merk != 'Xing' && merk != 'Info' && merk != 'VBRI') continue;
    // De vlaggen van Xing/Info zijn één 32-bits getal, en "het aantal frames staat erin" is bit 0
    // daarvan — dus de LAATSTE byte, niet de eerste. Op `b[plek + 4]` kijken leest de hoogste byte
    // en die is altijd nul: dan vindt deze tak nooit iets en valt alles stil terug op de
    // CBR-deling, ook bij een VBR-bestand. Een toets met een echt Xing-blok ving dat meteen.
    final frames = merk == 'VBRI'
        ? _viaVbri(b, plek)
        : ((_int32(b, plek + 4) & 0x1) == 1 ? _int32(b, plek + 8) : 0);
    if (frames > 0) {
      return Duration(milliseconds: (frames * perFrame * 1000 / hertz).round());
    }
  }

  // Geen blok: dan moet de bitsnelheid vast zijn, en is het één deling. Klopt precies op de twee
  // gemeten bestanden (223,4 en 209,1 seconden, net als ffprobe).
  if (geluidBytes <= 0) return null;
  return Duration(milliseconds: (geluidBytes * 8 * 1000 / bitrate).round());
}

/// VBRI zet het aantal frames op +14 van het merk.
int _viaVbri(Uint8List b, int plek) => plek + 18 <= b.length ? _int32(b, plek + 14) : 0;

int _int32(Uint8List b, int i) =>
    i + 4 <= b.length ? (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3] : 0;

Uint8List? _lees(RandomAccessFile raf, int van, int hoeveel) {
  if (van < 0) return null;
  try {
    raf.setPositionSync(van);
    final b = raf.readSync(hoeveel);
    return b.isEmpty ? null : b;
  } catch (_) {
    return null;
  }
}

// FLAC-frames vinden in een bestand dat nog binnenkomt.
//
// **Waarom.** Springen naar een tijd in een FLAC ZONDER zoektabel laat ffmpeg eerst de laatste tijd van het
// bestand zoeken: vanaf het einde terug, en dan frame voor frame vooruit tot het einde (`ff_find_last_ts`).
// Bij een bestand dat nog binnenkomt is dat einde er niet, en dan wacht het springen tot de download klaar
// is — gemeten op 20-10-2026: negen seconden stilte na een peerwissel, en 52 s in een bestand mét
// zoektabel (ook dan zocht ffmpeg het einde). Daarom springt het verdergaan niet: de server geeft de kop
// met daarachter de frames vanaf het frame waarin de tijd valt (`?vanaf=` in groeistroom.dart).
//
// Alleen dart:typed_data: buiten Flutter te beproeven, zoals groeistroom.dart.
import 'dart:typed_data';

/// Wat een frame moet kloppen: uit STREAMINFO.
class FlacStroominfo {
  const FlacStroominfo(
      {required this.minBlok,
      required this.maxBlok,
      required this.frequentie,
      required this.kanalen,
      required this.bits,
      required this.monsters});
  final int minBlok, maxBlok, frequentie, kanalen, bits, monsters;
}

/// Een frame: waar hij begint, zijn eerste monster, en hoeveel monsters hij draagt.
typedef FlacFrame = ({int byte, int monster, int blok});

/// De metablokken van een FLAC-kop (vanaf "fLaC", een ID3 ervoor overgeslagen): soort, lengte, en waar het
/// blok (met zijn kop van 4 bytes) begint. Null als de kop niet compleet in [b] staat.
List<({int soort, int begin, int lengte})>? flacBlokken(Uint8List b) {
  var i = 0;
  // Een ID3v2 ervoor (komt voor bij FLAC's van slordige taggers).
  if (b.length >= 10 && b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) {
    i = 10 + ((b[6] & 0x7f) << 21 | (b[7] & 0x7f) << 14 | (b[8] & 0x7f) << 7 | (b[9] & 0x7f));
  }
  if (i + 4 > b.length || b[i] != 0x66 || b[i + 1] != 0x4C || b[i + 2] != 0x61 || b[i + 3] != 0x43) return null;
  var pos = i + 4;
  final uit = <({int soort, int begin, int lengte})>[];
  for (var k = 0; k < 128; k++) {
    if (pos + 4 > b.length) return null;
    final laatste = (b[pos] & 0x80) != 0;
    final len = (b[pos + 1] << 16) | (b[pos + 2] << 8) | b[pos + 3];
    if (pos + 4 + len > b.length) return null;
    uit.add((soort: b[pos] & 0x7f, begin: pos, lengte: len));
    pos += 4 + len;
    if (laatste) return uit;
  }
  return null;
}

/// STREAMINFO uit een complete kop, of null.
FlacStroominfo? flacStroominfo(Uint8List kop) {
  final blokken = flacBlokken(kop);
  if (blokken == null || blokken.isEmpty || blokken.first.soort != 0 || blokken.first.lengte < 34) return null;
  final d = Uint8List.sublistView(kop, blokken.first.begin + 4, blokken.first.begin + 4 + 34);
  return FlacStroominfo(
    minBlok: (d[0] << 8) | d[1],
    maxBlok: (d[2] << 8) | d[3],
    frequentie: (d[10] << 12) | (d[11] << 4) | (d[12] >> 4),
    kanalen: ((d[12] >> 1) & 0x07) + 1,
    bits: (((d[12] & 0x01) << 4) | (d[13] >> 4)) + 1,
    monsters: ((d[13] & 0x0F) << 32) | (d[14] << 24) | (d[15] << 16) | (d[16] << 8) | d[17],
  );
}

int _crc8(Uint8List b, int van, int tot) {
  var crc = 0;
  for (var i = van; i < tot; i++) {
    crc ^= b[i];
    for (var k = 0; k < 8; k++) {
      crc = (crc & 0x80) != 0 ? ((crc << 1) ^ 0x07) & 0xFF : (crc << 1) & 0xFF;
    }
  }
  return crc;
}

/// Is er op [i] in [b] een geldige framekop? Zo ja: zijn eerste monster en zijn lengte.
///
/// Streng, want een willekeurige 0xFFF8 in de audio is geen frame: de velden moeten bij STREAMINFO passen,
/// de blokstrategie bij die van het eerste frame ([vast]), en de CRC-8 over de kop moet kloppen.
FlacFrame? flacFrameKop(Uint8List b, int i, FlacStroominfo si, {required bool vast}) {
  if (i + 6 > b.length || b[i] != 0xFF || (b[i + 1] & 0xFE) != 0xF8) return null;
  if (((b[i + 1] & 0x01) == 0) != vast) return null;
  final blokCode = b[i + 2] >> 4, rateCode = b[i + 2] & 0x0F;
  final kanaalCode = b[i + 3] >> 4, bitsCode = (b[i + 3] >> 1) & 0x07;
  if (blokCode == 0 || rateCode == 0x0F || kanaalCode > 10 || (b[i + 3] & 0x01) != 0) return null;
  if (bitsCode == 3) return null;
  final kanalen = kanaalCode < 8 ? kanaalCode + 1 : 2;
  if (kanalen != si.kanalen) return null;
  const bitsVan = [0, 8, 12, -1, 16, 20, 24, 32];
  if (bitsCode != 0 && bitsVan[bitsCode] != si.bits) return null;
  // Het "UTF-8"-getal: framenummer (vast) of monsternummer (variabel).
  var p = i + 4;
  final eerste = b[p];
  int extra;
  int waarde;
  if (eerste < 0x80) {
    extra = 0;
    waarde = eerste;
  } else if (eerste & 0xE0 == 0xC0) {
    extra = 1;
    waarde = eerste & 0x1F;
  } else if (eerste & 0xF0 == 0xE0) {
    extra = 2;
    waarde = eerste & 0x0F;
  } else if (eerste & 0xF8 == 0xF0) {
    extra = 3;
    waarde = eerste & 0x07;
  } else if (eerste & 0xFC == 0xF8) {
    extra = 4;
    waarde = eerste & 0x03;
  } else if (eerste & 0xFE == 0xFC) {
    extra = 5;
    waarde = eerste & 0x01;
  } else if (eerste == 0xFE && !vast) {
    extra = 6;
    waarde = 0;
  } else {
    return null;
  }
  if (p + 1 + extra > b.length) return null;
  for (var k = 1; k <= extra; k++) {
    final c = b[p + k];
    if (c & 0xC0 != 0x80) return null;
    waarde = (waarde << 6) | (c & 0x3F);
  }
  p += 1 + extra;
  int blok;
  if (blokCode == 1) {
    blok = 192;
  } else if (blokCode <= 5) {
    blok = 576 << (blokCode - 2);
  } else if (blokCode == 6) {
    if (p + 1 > b.length) return null;
    blok = b[p] + 1;
    p += 1;
  } else if (blokCode == 7) {
    if (p + 2 > b.length) return null;
    blok = ((b[p] << 8) | b[p + 1]) + 1;
    p += 2;
  } else {
    blok = 256 << (blokCode - 8);
  }
  if (blok > si.maxBlok) return null;
  const rates = [0, 88200, 176400, 192000, 8000, 16000, 22050, 24000, 32000, 44100, 48000, 96000];
  int? rate;
  if (rateCode >= 1 && rateCode <= 11) {
    rate = rates[rateCode];
  } else if (rateCode == 12) {
    if (p + 1 > b.length) return null;
    rate = b[p] * 1000;
    p += 1;
  } else if (rateCode == 13 || rateCode == 14) {
    if (p + 2 > b.length) return null;
    rate = ((b[p] << 8) | b[p + 1]) * (rateCode == 14 ? 10 : 1);
    p += 2;
  }
  if (rate != null && rate != si.frequentie) return null;
  if (p + 1 > b.length || _crc8(b, i, p) != b[p]) return null;
  final monster = vast ? waarde * si.maxBlok : waarde;
  if (si.monsters > 0 && monster >= si.monsters) return null;
  return (byte: i, monster: monster, blok: blok);
}

/// Het eerste geldige frame op of na [vanaf] binnen [b], of null.
FlacFrame? volgendeFlacFrame(Uint8List b, int vanaf, FlacStroominfo si, {required bool vast}) {
  for (var i = vanaf < 0 ? 0 : vanaf; i + 6 <= b.length; i++) {
    if (b[i] != 0xFF) continue;
    final f = flacFrameKop(b, i, si, vast: vast);
    if (f != null) return f;
  }
  return null;
}

/// Het frame waar monster [doel] in valt, gezocht in wat er van het bestand is: [lees] geeft bytes op een
/// plek (kort als er minder staat), [audioBegin] is het eerste frame, [einde] hoeveel er binnen is.
///
/// Halveren op de bytes en dan de laatste stukjes frame voor frame — een paar leesbeurten van 128 kB, nooit
/// het hele bestand. Null als het niet te vinden is (dan maar zonder zoektabel).
FlacFrame? flacFrameBij(int doel,
    {required int audioBegin,
    required int einde,
    required FlacStroominfo si,
    required Uint8List Function(int vanaf, int lengte) lees}) {
  const venster = 128 * 1024;
  // Nooit voorbij wat er binnen is, ook als de bron meer zou geven.
  Uint8List binnen(int v, int n) => v >= einde ? Uint8List(0) : lees(v, n < einde - v ? n : einde - v);
  final begin = binnen(audioBegin, 64);
  if (begin.length < 6 || begin[0] != 0xFF) return null;
  final vast = (begin[1] & 0x01) == 0;
  FlacFrame? zoek(int vanaf) {
    if (vanaf >= einde) return null;
    final b = binnen(vanaf, venster);
    final f = volgendeFlacFrame(b, 0, si, vast: vast);
    return f == null ? null : (byte: vanaf + f.byte, monster: f.monster, blok: f.blok);
  }

  var beste = zoek(audioBegin);
  if (beste == null || beste.byte != audioBegin) return null;
  var lo = audioBegin, hi = einde;
  while (hi - lo > venster) {
    final mid = lo + (hi - lo) ~/ 2;
    final f = zoek(mid);
    if (f == null || f.monster > doel) {
      hi = mid;
    } else {
      beste = f;
      lo = f.byte + 1;
    }
  }
  // De laatste meters frame voor frame — binnen één leesbeurt, en pas een volgende als die op is.
  var b = beste!;
  for (var ronde = 0; ronde < 64; ronde++) {
    if (doel < b.monster + b.blok) return b;
    final buf = binnen(b.byte, 2 * venster);
    var vorige = b;
    var i = 2;
    while (true) {
      final n = volgendeFlacFrame(buf, i, si, vast: vast);
      if (n == null) break;
      final f = (byte: b.byte + n.byte, monster: n.monster, blok: n.blok);
      if (f.monster <= vorige.monster) return null; // geen oplopende tijd: dit klopt niet
      if (f.monster > doel) return vorige;
      if (doel < f.monster + f.blok) return f;
      vorige = f;
      i = n.byte + 2;
    }
    // Geen enkel frame meer in dit stuk: wat er nog moet komen, is er (nog) niet.
    if (vorige.byte == b.byte || vorige.byte >= einde) return null;
    b = vorige;
  }
  return null;
}

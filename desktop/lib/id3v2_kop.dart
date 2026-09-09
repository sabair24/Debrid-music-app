/// Een ID3v2-blok lezen — genoeg ervan om te weten hoe een nummer heet.
///
/// **Waarvoor dit er is.** Een SACD-rip in Sony's doos (`.dsf`) draagt zijn tekst in een ID3v2-blok
/// achteraan, en de kop wijst er zelfs naar. [dsd_kop.dart] las dat bewust niet: *"een halve
/// tekstontleder die af en toe iets verkeerds leest is erger dan geen"*. Op 09-09-2026 gevraagd om
/// het alsnog te doen — een DSD-rip die als "Onbekende artiest" binnenkomt is niet minder verloren
/// dan een die niet binnenkomt.
///
/// **Waarom dit wél te doen is zonder halve ontleder.** Er zijn maar zeven velden nodig en die zijn
/// allemaal tekstframes met dezelfde vorm: één byte codering, dan de tekst. Alles wat ingewikkeld is
/// aan ID3 — plaatjes, teksten met taalcode, tellers, hoofdstukken — wordt hier overgeslagen in
/// plaats van half begrepen. Wat niet gelezen kan worden levert null op, en dan blijft de
/// bestandsnaam gelden, precies zoals daarvoor.
library;

import 'dart:convert';
import 'dart:io';

/// Wat er uit een ID3v2-blok kwam. Alles kan ontbreken.
class Id3Tags {
  final String? title, artist, album, albumArtist, genre;
  final int trackNo, trackTotal;
  final int? year;

  const Id3Tags({
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.genre,
    this.trackNo = 0,
    this.trackTotal = 0,
    this.year,
  });

  bool get leeg => (title ?? '').isEmpty && (artist ?? '').isEmpty && (album ?? '').isEmpty;
}

/// Leest het ID3v2-blok dat op [vanaf] in [f] begint, of null.
///
/// [vanaf] is nul voor een bestand dat met "ID3" begint (mp3, aiff), en bij een `.dsf` het getal dat
/// de kop zelf noemt.
Id3Tags? readId3v2(File f, {int vanaf = 0}) {
  RandomAccessFile? raf;
  try {
    raf = f.openSync();
    if (vanaf < 0 || vanaf + 10 > raf.lengthSync()) return null;
    raf.setPositionSync(vanaf);
    final kop = raf.readSync(10);
    if (kop.length < 10 || String.fromCharCodes(kop.sublist(0, 3)) != 'ID3') return null;
    final groot = kop[3];
    if (groot < 2 || groot > 4) return null;
    // De maat staat "synchsafe": zeven bits per byte, zodat er nooit een reeks enen in staat die een
    // decoder voor een geluidsframe aanziet.
    final maat = (kop[6] << 21) | (kop[7] << 14) | (kop[8] << 7) | kop[9];
    if (maat <= 0 || maat > 8 * 1024 * 1024) return null;
    // Een uitgebreide kop staat vóór de frames; hem overslaan is genoeg, lezen hoeft niet.
    var p = 0;
    final blok = raf.readSync(maat);
    if ((kop[5] & 0x40) != 0 && blok.length >= 4) {
      final extra = groot >= 4
          ? (blok[0] << 21) | (blok[1] << 14) | (blok[2] << 7) | blok[3]
          : ((blok[0] << 24) | (blok[1] << 16) | (blok[2] << 8) | blok[3]) + 4;
      p = extra.clamp(0, blok.length);
    }

    final velden = <String, String>{};
    // ID3v2.2 gebruikt drie letters en drie maatbytes; 2.3 en 2.4 vier en vier.
    final idLengte = groot == 2 ? 3 : 4;
    final kopLengte = groot == 2 ? 6 : 10;
    while (p + kopLengte <= blok.length) {
      final id = String.fromCharCodes(blok.sublist(p, p + idLengte));
      if (id.trim().isEmpty || id.codeUnitAt(0) == 0) break; // opvulling: hier houdt het op
      int lengte;
      if (groot == 2) {
        lengte = (blok[p + 3] << 16) | (blok[p + 4] << 8) | blok[p + 5];
      } else if (groot == 4) {
        lengte = (blok[p + 4] << 21) | (blok[p + 5] << 14) | (blok[p + 6] << 7) | blok[p + 7];
      } else {
        lengte = (blok[p + 4] << 24) | (blok[p + 5] << 16) | (blok[p + 6] << 8) | blok[p + 7];
      }
      final begin = p + kopLengte;
      if (lengte <= 0 || begin + lengte > blok.length) break;
      if (id.startsWith('T')) {
        final tekst = _tekstVan(blok.sublist(begin, begin + lengte));
        if (tekst != null && tekst.isNotEmpty) velden[id] = tekst;
      }
      p = begin + lengte;
    }
    if (velden.isEmpty) return null;

    (int, int) nummer(String? s) {
      if (s == null || s.isEmpty) return (0, 0);
      final d = s.split('/');
      return (int.tryParse(d.first.trim()) ?? 0,
          d.length > 1 ? (int.tryParse(d[1].trim()) ?? 0) : 0);
    }

    String? veld(String v24, String v22) => velden[v24] ?? velden[v22];
    final t = nummer(veld('TRCK', 'TRK'));
    // 2.3 heeft TYER (jaar) en TDAT; 2.4 vervangt beide door TDRC met een hele datum.
    final jaar = velden['TDRC'] ?? velden['TYER'] ?? velden['TYE'];
    return Id3Tags(
      title: veld('TIT2', 'TT2'),
      artist: veld('TPE1', 'TP1'),
      album: veld('TALB', 'TAL'),
      albumArtist: veld('TPE2', 'TP2'),
      genre: _genre(veld('TCON', 'TCO')),
      trackNo: t.$1,
      trackTotal: t.$2,
      year: jaar == null || jaar.length < 4 ? null : int.tryParse(jaar.substring(0, 4)),
    );
  } catch (_) {
    return null;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
}

/// De eerste byte zegt in welke codering de rest staat. Alles daarna tot de eerste afsluiter.
String? _tekstVan(List<int> b) {
  if (b.isEmpty) return null;
  final codering = b[0];
  final rest = b.sublist(1);
  String uit;
  switch (codering) {
    case 1: // UTF-16 met een byte-volgordeteken
    case 2: // UTF-16 big-endian, zonder teken
      uit = _utf16(rest, standaardGroot: codering == 2);
      break;
    case 3:
      uit = utf8.decode(rest, allowMalformed: true);
      break;
    default: // 0 — latin-1, byte voor byte
      uit = String.fromCharCodes(rest);
  }
  final nul = uit.indexOf(String.fromCharCode(0));
  return (nul < 0 ? uit : uit.substring(0, nul)).trim();
}

String _utf16(List<int> b, {required bool standaardGroot}) {
  var groot = standaardGroot;
  var i = 0;
  if (b.length >= 2 && ((b[0] == 0xFE && b[1] == 0xFF) || (b[0] == 0xFF && b[1] == 0xFE))) {
    groot = b[0] == 0xFE;
    i = 2;
  }
  final eenheden = <int>[];
  for (; i + 1 < b.length; i += 2) {
    eenheden.add(groot ? (b[i] << 8) | b[i + 1] : b[i] | (b[i + 1] << 8));
  }
  return String.fromCharCodes(eenheden);
}

/// "(17)" en "(17)Rock" zijn ID3v1-nummers uit een tabel van dertig jaar oud. Staat er een naam
/// achter, dan telt die; staat er alleen een nummer, dan is een leeg genre eerlijker dan een gok.
String? _genre(String? s) {
  if (s == null || s.isEmpty) return null;
  final m = RegExp(r'^\((\d+)\)\s*(.*)$').firstMatch(s);
  if (m == null) return s;
  final rest = m.group(2)!.trim();
  return rest.isEmpty ? null : rest;
}

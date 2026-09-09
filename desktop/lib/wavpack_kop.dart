/// De kop van een WavPack-bestand (`.wv`), en de APEv2-tags die erachter kunnen staan.
///
/// **Waarom dit er is.** Gemeld op 09-09-2026 met één schermafdruk: *"wat is WV, 0:00 min ????"* —
/// Snap! *The Power*, 228 MB, en de app zette er `WV` en `0:00` achter. WavPack stond wél in
/// [audioSoorten], dus het bestand kwam binnen, maar geen enkele lezer hier kende de doos: geen duur,
/// geen bemonstering, geen titel. Terwijl het er allemaal in staat — de kop van dat bestand zegt
/// 65.881.600 monsters op 192 kHz, oftewel 5:43.
///
/// Zelfde vorm en zelfde grens als [dsd_kop.dart]: één keer openen, een kop lezen, altijd sluiten.
/// Een handvat dat open blijft maakt een bestand op Windows de rest van de sessie onverplaatsbaar.
///
/// **Waarom APEv2 er hier wél bij hoort en ID3 bij DSD apart staat.** WavPack draagt zijn tekst
/// bijna altijd in een APEv2-blok áchteraan, en dat blok is eenvoudig genoeg om zonder halve
/// ontleder te lezen: een voettekst met een magisch woord, en daarvoor een rij sleutel/waarde-paren
/// in UTF-8. Datzelfde blok zit ook op `.ape`-bestanden, en die kent de tagontleder hier evenmin.
library;

import 'dart:convert';
import 'dart:io';

/// Wat er in de blokkop van een WavPack staat.
class WvKop {
  /// Hoe lang het stuk duurt, of null als de kop het niet zegt (een stroom zonder totaal).
  final Duration? duration;

  /// Monsters per seconde, of 0 als de kop naar een metablok verwijst in plaats van naar de tabel.
  final int sampleRate;

  /// Bits per monster. Bij een zwevendekommabestand altijd 32 — dat ís de vorm.
  final int bitsPerSample;

  /// 1 of 2. WavPack kan meer kanalen, maar die staan in een metablok en niet in deze vlaggen.
  final int channels;

  /// Zwevende komma in plaats van gehele getallen.
  final bool zwevend;

  const WvKop({
    required this.duration,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.channels,
    required this.zwevend,
  });
}

/// De vaste tabel met bemonsteringen. Index 15 betekent "staat in een metablok", niet "onbekend
/// formaat" — dan is er nog steeds muziek, alleen geen getal.
const _snelheden = [
  6000, 8000, 9600, 11025, 12000, 16000, 22050, 24000, //
  32000, 44100, 48000, 64000, 88200, 96000, 192000,
];

/// Leest de kop van [f], of null als het geen WavPack is.
WvKop? readWvKop(File f) {
  RandomAccessFile? raf;
  try {
    raf = f.openSync();
    final b = raf.readSync(32);
    if (b.length < 32) return null;
    if (String.fromCharCodes(b.sublist(0, 4)) != 'wvpk') return null;

    final versie = b[8] | (b[9] << 8);
    int u32(int i) => b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);

    // Vanaf versie 4.10 dragen twee losse bytes de HOGE acht bits van de tellers, zodat een bestand
    // langer dan vier miljard monsters ook klopt. Bij oudere bestanden zijn die bytes nul.
    final laag = u32(12);
    final totaal = versie >= 0x410 ? (b[11] << 32) | laag : laag;
    final vlaggen = u32(24);

    final index = (vlaggen >> 23) & 0xF;
    final hz = index < _snelheden.length ? _snelheden[index] : 0;
    final zwevend = (vlaggen & 0x80) != 0;
    // De "magnitude" is de hoogste bit die gebruikt wordt, dus één minder dan de diepte. Bij
    // zwevende komma zegt dat veld iets anders en is de vorm per definitie 32 bits.
    final bits = zwevend ? 32 : ((vlaggen >> 18) & 0x1F) + 1;

    // `0xFFFFFFFF` is WavPacks manier om "ik weet het niet" te zeggen — een stroom die nog liep toen
    // hij ingepakt werd. Dat is iets anders dan nul, en mag geen 0:00 opleveren.
    final onbekend = laag == 0xFFFFFFFF;
    return WvKop(
      duration: (onbekend || totaal <= 0 || hz <= 0)
          ? null
          : Duration(milliseconds: (totaal * 1000 / hz).round()),
      sampleRate: hz,
      bitsPerSample: bits >= 1 && bits <= 32 ? bits : 0,
      channels: (vlaggen & 4) != 0 ? 1 : 2,
      zwevend: zwevend,
    );
  } catch (_) {
    return null;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {/* een bestand dat al weg is hoeft niet dicht */}
  }
}

/// Wat er in een APEv2-blok stond. Alles kan ontbreken; dat is geen fout.
class ApeTags {
  final String? title, artist, album, albumArtist, genre;
  final int trackNo, trackTotal;
  final int? year;

  const ApeTags({
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.genre,
    this.trackNo = 0,
    this.trackTotal = 0,
    this.year,
  });

  bool get leeg =>
      (title ?? '').isEmpty && (artist ?? '').isEmpty && (album ?? '').isEmpty;
}

const _apeMagie = 'APETAGEX';

/// Leest het APEv2-blok achter [f], of null als er geen staat.
///
/// Kijkt op twee plekken: helemaal achteraan, en 128 bytes eerder — daar staat de voettekst als er
/// ná het APE-blok nog een ID3v1-staartje van 128 bytes geplakt is, wat veel rippers doen.
ApeTags? readApeTags(File f) {
  RandomAccessFile? raf;
  try {
    raf = f.openSync();
    final lengte = raf.lengthSync();
    for (final vanaf in [lengte - 32, lengte - 32 - 128]) {
      if (vanaf < 32) continue;
      raf.setPositionSync(vanaf);
      final voet = raf.readSync(32);
      if (voet.length < 32) continue;
      if (String.fromCharCodes(voet.sublist(0, 8)) != _apeMagie) continue;
      int u32(List<int> x, int i) =>
          x[i] | (x[i + 1] << 8) | (x[i + 2] << 16) | (x[i + 3] << 24);
      final maat = u32(voet, 12); // inclusief deze voettekst, exclusief een kop vooraan
      final aantal = u32(voet, 16);
      if (maat <= 32 || maat > 4 * 1024 * 1024 || aantal <= 0 || aantal > 4096) continue;
      final begin = vanaf + 32 - maat;
      if (begin < 0) continue;
      raf.setPositionSync(begin);
      final blok = raf.readSync(maat - 32);
      return _leesApeItems(blok, aantal);
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

ApeTags? _leesApeItems(List<int> blok, int aantal) {
  final velden = <String, String>{};
  var p = 0;
  for (var i = 0; i < aantal && p + 8 <= blok.length; i++) {
    final maat = blok[p] | (blok[p + 1] << 8) | (blok[p + 2] << 16) | (blok[p + 3] << 24);
    p += 8; // maat + vlaggen
    final eind = blok.indexOf(0, p);
    if (eind < 0 || maat < 0 || eind + 1 + maat > blok.length) break;
    final sleutel = String.fromCharCodes(blok.sublist(p, eind)).toLowerCase();
    // Een waarde mag meerdere delen bevatten, gescheiden door een nulbyte. Alleen het eerste deel:
    // twee artiesten in één regel plakken maakt van "Snap!" en "Turbo B" één onvindbare naam.
    final ruw = blok.sublist(eind + 1, eind + 1 + maat);
    final nul = ruw.indexOf(0);
    velden[sleutel] = utf8.decode(nul < 0 ? ruw : ruw.sublist(0, nul), allowMalformed: true).trim();
    p = eind + 1 + maat;
  }
  if (velden.isEmpty) return null;

  (int, int) nummer(String? s) {
    if (s == null || s.isEmpty) return (0, 0);
    final d = s.split('/');
    return (int.tryParse(d.first.trim()) ?? 0,
        d.length > 1 ? (int.tryParse(d[1].trim()) ?? 0) : 0);
  }

  final t = nummer(velden['track']);
  final jaar = velden['year'] ?? velden['date'];
  return ApeTags(
    title: velden['title'],
    artist: velden['artist'],
    album: velden['album'],
    albumArtist: velden['album artist'] ?? velden['albumartist'],
    genre: velden['genre'],
    trackNo: t.$1,
    trackTotal: t.$2 != 0 ? t.$2 : nummer(velden['tracktotal']).$1,
    // "1990" en "1990-03-12" komen allebei voor; alleen het jaartal telt.
    year: jaar == null || jaar.length < 4 ? null : int.tryParse(jaar.substring(0, 4)),
  );
}

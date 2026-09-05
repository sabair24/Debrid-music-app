import 'dart:typed_data';

import 'organize.dart' show artistKey, normKey;

/// One playable track. Covers are NOT stored per-track (memory) — they live on the
/// Album. Only a queued/playing track carries its cover, passed via the player.
class Track {
  final String path;
  final String title;
  final String artist;
  final String album; // empty tag => treated as a single
  final int trackNo;

  /// How many tracks the release this file came from holds — 0 when the ripper didn't say. It is
  /// what separates two EDITIONS of one album, which otherwise merge and collide on track numbers.
  final int trackTotal;
  final Duration? duration;
  final bool isFlac;
  final int? year;
  final String? genre;

  /// File modified time (ms since epoch) — used for "recently added" sorting + the home screen.
  final int addedMs;

  /// File size in bytes — with the duration this yields the effective bitrate, so we can show
  /// whether a FLAC is CD-quality (16/44) or hi-res (24-bit).
  final int sizeBytes;

  /// Samples per second and bits per sample, straight from the file header (0 when unknown).
  /// Beyond the hi-res badge these decide where a track can go: Sonos plays FLAC only up to
  /// 48 kHz and silently SKIPS anything above, so the cast path has to know before it sends.
  final int sampleRate;
  final int bitsPerSample;

  Track({
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    this.trackNo = 0,
    this.trackTotal = 0,
    this.duration,
    this.isFlac = false,
    this.year,
    this.genre,
    this.addedMs = 0,
    this.sizeBytes = 0,
    this.sampleRate = 0,
    this.bitsPerSample = 0,
  });

  /// Do these two read the same on screen?
  ///
  /// The question the player asks after a correction, and it is deliberately narrow: only the
  /// fields something actually renders. Not duration, not size, not addedMs — those come back
  /// slightly different from a re-stat of a file nobody touched, and treating that as a change
  /// would rebuild the player bar every time the library so much as looked at the disk.
  bool sameDisplayAs(Track o) =>
      title == o.title &&
      artist == o.artist &&
      album == o.album &&
      trackNo == o.trackNo &&
      trackTotal == o.trackTotal &&
      year == o.year;

  /// Effective bitrate in kbit/s, worked out from the size and the duration (a FLAC has no
  /// single stated bitrate — it varies with the music).
  int? get bitrateKbps {
    final ms = duration?.inMilliseconds ?? 0;
    if (ms <= 0 || sizeBytes <= 0) return null;
    return (sizeBytes * 8 / ms).round();
  }

  /// File extension (lowercase, no dot), e.g. "flac", "mp3".
  String get ext {
    final i = path.lastIndexOf('.');
    return i < 0 ? '' : path.substring(i + 1).toLowerCase();
  }
}

/// A group of tracks sharing an artist + album (or a single, when there's no album tag).
class Album {
  final String title;
  final String artist;
  final List<Track> tracks;
  final bool isSingle;

  /// Which pressing this is, when the library holds more than one of the same record and had to
  /// split them. Without it the six Backstreet Boys tiles are indistinguishable, and you cannot
  /// choose which to merge if you cannot tell them apart.
  String? edition;

  /// Cover embedded in the audio file (read once per album).
  Uint8List? embeddedCover;

  /// Web-fetched cover (Deezer/Discogs/MusicBrainz), set by the enricher.
  Uint8List? enriched;

  /// The sleeve of a pressing we actually IDENTIFIED — a release the user pinned, or the one the
  /// album page resolved and is showing right now.
  ///
  /// Separate from [enriched] because the two are not equally trustworthy. [enriched] is the answer
  /// to "search the web for this artist and title", which for a common name is a guess, and a guess
  /// must not overrule the picture inside the file. This one answers "give me the art of release
  /// 12345", which is a fact.
  ///
  /// Without it the album page and the rest of the app disagreed on screen: the page resolved the
  /// right sleeve and handed it back to the library, the library filed it under [enriched], and
  /// [cover] handed the grid the wrong embedded one it already had. Right album, right sleeve, one
  /// step back and the old one again.
  Uint8List? resolvedCover;

  /// Which release [resolvedCover] came from — `rel:12345` or `mb:<uuid>`.
  String? resolvedFrom;

  /// User-picked cover via the manual metadata editor — wins over everything and
  /// survives rescans (a wrong embedded cover must not come back).
  Uint8List? correctedCover;

  /// Staat de hoes in de bestanden ook op een ANDERE plaat, van een andere artiest?
  ///
  /// **Dan is het geen hoes van deze plaat.** Gevonden op 05-09-2026 en nagemeten door het plaatje
  /// met ffmpeg uit de FLAC's te trekken: Christina Aguilera's *Christina Aguilera (Expanded
  /// Edition)* en \*NSYNC's *No Strings Attached* dragen exact dezelfde 58944 bytes, en dat plaatje
  /// is de hoes van **BRAVO Hits 00's**. George Michael's *Patience* en Whitney Houston's *Whitney
  /// The Greatest Hits* delen die van **Sublime Top 1000**. Nummers die uit een verzamelrip komen
  /// dragen de hoes van die verzamelplaat mee, en die reisde ongemerkt mee naar de echte plaat.
  ///
  /// De bestanden zijn fout, maar de app maakte het erger: [cover] liet die ingebakken hoes vóór de
  /// hoes gaan die de verrijker opzoekt. Beide eisen tellen. Alleen "andere artiest" zou een
  /// verzamelplaat slopen die per artiest in tegels uiteenvalt (*Thunderdome XXIII* staat er twee
  /// keer, met dezelfde titel en terecht dezelfde hoes); alleen "andere titel" zou de single naast
  /// zijn album slopen (*Pon De Replay* bij *Music Of The Sun*).
  ///
  /// Gezet door [markeerVreemdeHoezen], want alleen die ziet alle platen tegelijk.
  bool embeddedIsVanEenAndere = false;

  Album(this.title, this.artist, this.tracks, {this.isSingle = false});

  /// De hoes die op het scherm hoort.
  ///
  /// Een verdachte ingebakken hoes zakt onder [enriched] maar blijft wél de laatste terugval: is er
  /// niets beters, dan is een verkeerde hoes nog altijd zichtbaarder dan een leeg vlak, en zodra de
  /// verrijker de goede binnenhaalt wint die vanzelf. Zo kan deze regel niets kwijtmaken.
  Uint8List? get cover => zekereHoes ?? embeddedCover;

  /// De hoes waarvan we durven zeggen dát het deze plaat is — dus zónder de terugval hierboven.
  ///
  /// **Twee vragen, en ze zijn niet dezelfde.** "Wat teken ik?" mag eindigen bij een verdachte hoes;
  /// "moet ik er nog een zoeken?" mag dat niet. Met één getter voor allebei sloeg de verrijker die
  /// platen over — `album.cover` gaf immers iets terug — en zakte de verdachte hoes wel, maar kwam
  /// er nooit een goede voor in de plaats. Precies gemeten: vier platen bleven de hoes van *BRAVO
  /// Hits 00's* en *Sublime Top 1000* dragen.
  Uint8List? get zekereHoes =>
      correctedCover ??
      resolvedCover ??
      (embeddedIsVanEenAndere ? enriched : (embeddedCover ?? enriched));

  int? get year {
    for (final t in tracks) {
      if (t.year != null) return t.year;
    }
    return null;
  }

  String? get genre {
    for (final t in tracks) {
      if (t.genre != null && t.genre!.isNotEmpty) return t.genre;
    }
    return null;
  }

  /// Most recent file time among the tracks — "recently added".
  /// Eén keer uitgerekend, want dit werd per beeld honderden keren doorlopen.
  ///
  /// **Wat het kostte.** Dit was een gewone getter die alle nummers van het album afliep. Hij wordt
  /// gebruikt om op "onlangs toegevoegd" te SORTEREN, op Start en op Albums, en die sortering staat
  /// in `build()`. Een sortering vraagt de sleutel twee keer per vergelijking, dus bij tweehonderd
  /// albums van veertien nummers was dat tienduizenden lussen — per frame, en juist tijdens het
  /// verrijken wanneer er per vierentwintig hoezen opnieuw getekend wordt.
  ///
  /// `late final` mag hier omdat [tracks] vastligt zodra het album bestaat: nergens in de app wordt
  /// er achteraf een nummer aan toegevoegd of uit verwijderd. Een scan, een correctie of een
  /// samenvoeging bouwt NIEUWE albumobjecten, en die rekenen dus vanzelf opnieuw.
  late final int addedMs = () {
    var m = 0;
    for (final t in tracks) {
      if (t.addedMs > m) m = t.addedMs;
    }
    return m;
  }();
}

/// Zet [Album.embeddedIsVanEenAndere] voor elke plaat wiens ingebakken hoes óók op een plaat staat
/// die én anders heet én van een andere artiest is.
///
/// **Beide eisen tellen, en allebei om een gemeten reden.** Alleen "andere artiest" zou een
/// verzamelplaat slopen die per artiest in tegels uiteenvalt — *Thunderdome XXIII* staat twee keer
/// in de bibliotheek, onder "DJ Promo" en onder "The Stunned Guys & DJ Paul", met dezelfde titel en
/// terecht dezelfde hoes. Alleen "andere titel" zou de single naast zijn album slopen: *Pon De
/// Replay* draagt de hoes van *Music Of The Sun*, en dat hoort zo.
///
/// Vergelijkt op de eerste en laatste 256 bytes plus de lengte in plaats van op de hele afbeelding:
/// dat scheelt megabytes rondsjouwen bij elke herbouw, en twee JPEG's die daarin gelijk zijn maar
/// verderop verschillen bestaan in de praktijk niet.
void markeerVreemdeHoezen(List<Album> albums) {
  final perBeeld = <String, List<Album>>{};
  for (final a in albums) {
    a.embeddedIsVanEenAndere = false;
    final c = a.embeddedCover;
    if (c == null || c.length < 512) continue;
    final kop = c.take(256).join(',');
    final staart = c.skip(c.length - 256).join(',');
    perBeeld.putIfAbsent('${c.length}|$kop|$staart', () => []).add(a);
  }
  for (final zelfde in perBeeld.values) {
    if (zelfde.length < 2) continue;
    for (final a in zelfde) {
      final vreemd = zelfde.any((b) =>
          artistKey(b.artist) != artistKey(a.artist) && normKey(b.title) != normKey(a.title));
      if (vreemd) a.embeddedIsVanEenAndere = true;
    }
  }
}

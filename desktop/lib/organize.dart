import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import 'editions.dart';
import 'flac_tags.dart';
import 'mp3_tags.dart';
import 'echtheid.dart';
import 'echtheid_oordelen.dart';
import 'vaste_keuze.dart';

/// Where a downloaded release belongs in the folder tree.
enum RelKind { album, single, compilation }

/// Album/artist/track names as the user typed them differ in punctuation ("Backstreet's Back"
/// with a curly ’ vs a straight ') — which used to split ONE album into two. Normalise for
/// COMPARISON only (never for display): unify quotes/dashes, drop punctuation, fold whitespace.
/// De patronen als top-level `final`, niet in de body van [normKey].
///
/// Ze stonden binnenin, en dan bouwt Dart bij ELKE aanroep vijf nieuwe RegExp-objecten en compileert
/// het patroon opnieuw. Deze functie draait per toetsaanslag over de hele bibliotheek en zit ook in
/// de binnenlus van [redundantAlbums] — dat werd zo een paar duizend verse regexen per letter.
/// De rest van dit bestand deed het al goed (`_featRe`, `_compilationRe`, `_variousRe`); deze vijf
/// waren over het hoofd gezien.
final _krulQuote = RegExp(r'[‘’ʼ´`]');
final _dubbelQuote = RegExp(r'[“”]');
final _langStreepje = RegExp(r'[‐-―−]');
final _nietAlfanumeriek = RegExp(r'[^a-z0-9]+');
final _spaties = RegExp(r'\s+');

String normKey(String s) {
  final unified = _fold(s
      .toLowerCase()
      .replaceAll(_krulQuote, "'")
      .replaceAll(_dubbelQuote, '"')
      .replaceAll(_langStreepje, '-'));
  final stripped = unified.replaceAll(_nietAlfanumeriek, ' ');
  return stripped.trim().replaceAll(_spaties, ' ');
}

/// Accented letters folded to their plain form, so "Beyoncé" and "Beyonce" are one name.
/// Without this the accent is stripped as punctuation ("beyonc") and the two never match.
const _accents = <String, String>{
  'a': 'àáâãäåāăą',
  'e': 'èéêëēĕėęě',
  'i': 'ìíîïĩīĭįı',
  'o': 'òóôõöøōŏő',
  'u': 'ùúûüũūŭůűų',
  'c': 'çćĉċč',
  'n': 'ñńņň',
  'y': 'ýÿŷ',
  'z': 'żźž',
  's': 'šśŝş',
  'd': 'ďđð',
  'g': 'ğĝģ',
  't': 'ťţ',
  'r': 'ŕř',
  'l': 'łľĺļ',
  'ae': 'æ',
  'oe': 'œ',
  'ss': 'ß',
};

final Map<int, String> _foldMap = {
  for (final e in _accents.entries)
    for (final ch in e.value.runes) ch: e.key,
};

String _fold(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final plain = _foldMap[r];
    if (plain != null) {
      b.write(plain);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

/// "feat." and friends, as they appear in an artist tag or a title.
/// Deliberately NOT "&" or "and": "Simon & Garfunkel" and "Hall & Oates" are single acts, and
/// splitting those would invent artists that don't exist.
final _featRe = RegExp(
  r'\s*[\(\[]?\s*\b(feat\.?|ft\.?|featuring|met|w/)\b\s*\.?\s*',
  caseSensitive: false,
);

/// Inside the featured PART, these do separate names — "feat. Beyoncé & Kanye" is two people.
final _featSplitRe = RegExp(r'\s*(?:,|&|\+|\band\b|\ben\b|\bx\b)\s*', caseSensitive: false);

/// The main artist and everyone featured on the track.
///
/// A track credited "Lady Gaga feat. Beyoncé" belongs on Lady Gaga's album — so the MAIN artist
/// is what the library groups and files by, and the featured names ride along for display.
/// The credit hides in either field depending on the ripper: sometimes the artist tag carries it,
/// sometimes the title does ("Telephone (feat. Beyoncé)").
({String main, List<String> featured}) splitFeatured(String artist, String title) {
  final featured = <String>[];
  var main = artist.trim();

  void harvest(String s) {
    for (final part in s.split(_featRe).skip(1)) {
      final cleaned = part.replaceAll(RegExp(r'[\)\]]\s*$'), '').trim();
      for (final name in cleaned.split(_featSplitRe)) {
        final n = name.trim();
        if (n.isEmpty || n.length > 60) continue;
        if (featured.any((f) => artistKey(f) == artistKey(n))) continue;
        featured.add(n);
      }
    }
  }

  if (_featRe.hasMatch(main)) {
    harvest(main);
    main = main.split(_featRe).first.trim();
  }
  if (_featRe.hasMatch(title)) harvest(title);

  // Never list the main artist as their own guest.
  featured.removeWhere((f) => artistKey(f) == artistKey(main));
  return (main: main.isEmpty ? artist.trim() : main, featured: featured);
}

/// The title without its "(feat. …)" tail — for display next to a separate featured-artist line.
String titleWithoutFeat(String title) {
  if (!_featRe.hasMatch(title)) return title;
  final cut = title.split(_featRe).first.trim();
  return cut.replaceAll(RegExp(r'[\(\[]\s*$'), '').trim();
}

/// Comparison key for an ARTIST. On top of [normKey] it drops a leading "the", because "The
/// Doors" and "Doors" are one act. Deliberately artist-only: for an ALBUM the leading word is
/// part of the title ("The Wall" is not "Wall").
String artistKey(String s) {
  final k = normKey(s);
  return k.startsWith('the ') ? k.substring(4) : k;
}

/// Given every spelling of one artist found in the library (spelling → how many tracks use it),
/// pick the one to SHOW. Most-used wins; ties go to the tidiest capitalisation, so "Lady Gaga"
/// beats "Lady GaGa" rather than the winner depending on alphabetical luck.
String canonicalName(Map<String, int> spellings) {
  final names = spellings.keys.toList();
  if (names.length == 1) return names.first;
  names.sort((a, b) {
    final byCount = (spellings[b] ?? 0).compareTo(spellings[a] ?? 0);
    if (byCount != 0) return byCount;
    final byOdd = _oddCaps(a).compareTo(_oddCaps(b)); // fewer mid-word capitals first
    if (byOdd != 0) return byOdd;
    final byShape = _shapeScore(b).compareTo(_shapeScore(a)); // avoid ALL CAPS / all lowercase
    if (byShape != 0) return byShape;
    return a.compareTo(b); // last resort: stable
  });
  return names.first;
}

/// Capital letters that don't start a word — the mark of an odd spelling like "GaGa".
int _oddCaps(String s) {
  var odd = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    final isUpper = c.toUpperCase() == c && c.toLowerCase() != c;
    if (!isUpper) continue;
    final prev = i == 0 ? ' ' : s[i - 1];
    if (RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(prev)) odd++;
  }
  return odd;
}

/// 2 = looks deliberately capitalised, 1 = all lowercase, 0 = ALL CAPS.
int _shapeScore(String s) {
  final letters = s.replaceAll(RegExp(r'[^A-Za-zÀ-ÿ]'), '');
  if (letters.isEmpty) return 1;
  final caps = letters.split('').where((c) => c.toUpperCase() == c && c.toLowerCase() != c).length;
  if (caps == letters.length) return 0;
  if (caps == 0) return 1;
  return 2;
}

/// Even looser key, for SEARCH only: drop every non-alphanumeric character entirely (instead of
/// turning it into a space). normKey("Backstreet's Back") is "backstreet s back", so someone
/// typing "backstreets back" would find nothing; squashed, both become "backstreetsback".
final _nietAlfanumeriekLos = RegExp(r'[^a-z0-9]');

String searchKey(String s) => s.toLowerCase().replaceAll(_nietAlfanumeriekLos, '');

/// Album names that mean "this is a compilation", not a studio album. Deliberately narrow — a
/// wrong guess only misfiles, and the user explicitly wants Live/Best-of/compilations KEPT as
/// their own releases rather than merged away.
final _compilationRe = RegExp(
  r'\b(greatest hits|best of|the hits|the essential|essential|collection|anthology|'
  r'compilation|verzamel|megamix|top \d+|hitzone|now that s what|absolute (dance|music)|'
  r'club sounds|the very best|singles collection|b sides|rarities)\b',
);

const _variousArtists = 'Various Artists';
final _variousRe = RegExp(r'^(various|various artists|va|verschillende|diverse)', caseSensitive: false);

/// Classify one downloaded track's release from its tags.
/// [trackCount] is het aantal volgens een OFFICIËLE uitgave; [totaalVolgensTags] is wat het bestand
/// zelf beweert. Bewust twee dingen: de regel "één of twee nummers is een single" mag alleen op het
/// eerste af. Ze in één parameter gooien maakte van een opwaardering met TRACKTOTAL=2 in de tags
/// ineens een single, en dat brak een bestaande test — terecht.
RelKind classifyRelease(
    {required String album,
    required String artist,
    String? albumArtist,
    int trackCount = 0,
    int totaalVolgensTags = 0}) {
  if (album.trim().isEmpty) return RelKind.single;
  final a = normKey(album);
  if (_compilationRe.hasMatch(a)) return RelKind.compilation;
  if (_variousRe.hasMatch(artist.trim())) return RelKind.compilation;
  // DE ALBUMARTIEST TELT OOK, en dat ontbrak. Hierboven staat alleen de artiest van het NUMMER, en die
  // is bij een greep uit een verzamelbox gewoon de echte zanger. Gemeten geval: zoeken op "Khaled Didi"
  // leverde een bestand met ARTIST=Khaled maar ALBUMARTIST=Various Artists, TRACKTOTAL=1001 en
  // ALBUM="1001 Songs You Must Hear Before You Die". Dat werd een ALBUM van Khaled met één nummer 779
  // erin. Precies wat Saber bedoelde met "de tags die met Soulseek meekomen zijn meestal niet de goeie".
  if (_variousRe.hasMatch((albumArtist ?? '').trim())) return RelKind.compilation;
  // Geen enkele plaat heeft honderden nummers; zo'n getal komt uit een box. Ruim boven een dubbel- of
  // driedubbelalbum gelegd, want die bestaan wél en horen album te blijven.
  if (trackCount > 60 || totaalVolgensTags > 60) return RelKind.compilation;
  // A "release" of one or two tracks is a single/EP, not an album.
  if (trackCount > 0 && trackCount <= 2) return RelKind.single;
  return RelKind.album;
}

/// Make one path segment safe on Windows (and not absurdly long).
///
/// Also CANONICALISES the typography first: tags for the same album disagree about apostrophes
/// and dashes ("Backstreet's Back" vs "Backstreet’s Back"), which otherwise creates two folders
/// for one album — the same duplicate problem the library grouping had.
String safeSeg(String s) {
  var out = s
      .trim()
      .replaceAll(RegExp(r"[‘’ʼ´`]"), "'")
      .replaceAll(RegExp(r'[“”]'), '"')
      .replaceAll(RegExp(r'[‐-―−]'), '-');
  out = out.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '-');
  out = out.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'[. ]+$'), '');
  if (out.isEmpty) out = 'Onbekend';
  return out.length <= 80 ? out : out.substring(0, 80).trim();
}

/// Tags we need to file a track away.
///
/// The extra three are optional because the only source that knows them is an official release —
/// a peer's file has whatever its ripper felt like writing. When they ARE known this is the
/// authority a download is filed and retagged by, instead of the peer's own idea of the record.
class TrackTags {
  final String title, artist, album;
  final int trackNo;

  /// Who the RECORD is by, which is not always who the track is by: a duet's ARTIST is both names,
  /// its ALBUMARTIST is whose album it is. Without it a guest credit scatters an album in Roon.
  final String? albumArtist;

  /// How many tracks the release holds, and what year it came out.
  final int trackTotal;
  final int? year;

  /// Komen deze tags uit het BESTAND zelf in plaats van uit een officiële uitgave?
  ///
  /// Dit onderscheid was er niet, en werd afgeleid uit "draagt hij albumartiest/totaal/jaar?" — wat
  /// klopte zolang [readTags] die drie velden niet las. Zodra dat wél nodig werd (een greep uit een
  /// verzamelbox is alleen aan ALBUMARTIST te herkennen) viel die afleiding om: een bestand van een
  /// uploader zou ineens "gezaghebbend" heten en [stampTags] zou zijn eigen tags over zichzelf heen
  /// gaan schrijven. Daarom nu een expliciet vlaggetje in plaats van een gok.
  final bool vanBestand;

  const TrackTags({
    required this.title,
    required this.artist,
    required this.album,
    required this.trackNo,
    this.albumArtist,
    this.trackTotal = 0,
    this.year,
    this.vanBestand = false,
  });

  /// True when this came from an official release rather than from a downloaded file's own tags.
  bool get isAuthoritative => !vanBestand && (trackTotal > 0 || year != null || albumArtist != null);

  Map<String, dynamic> toJson() => {
        'title': title,
        'artist': artist,
        'album': album,
        'trackNo': trackNo,
        if (albumArtist != null) 'albumArtist': albumArtist,
        if (trackTotal > 0) 'trackTotal': trackTotal,
        if (year != null) 'year': year,
      };

  static TrackTags? fromJson(Map<String, dynamic> j) {
    final title = (j['title'] ?? '').toString();
    if (title.isEmpty) return null;
    return TrackTags(
      title: title,
      artist: (j['artist'] ?? '').toString(),
      album: (j['album'] ?? '').toString(),
      trackNo: (j['trackNo'] as num?)?.toInt() ?? 0,
      albumArtist: j['albumArtist']?.toString(),
      trackTotal: (j['trackTotal'] as num?)?.toInt() ?? 0,
      year: (j['year'] as num?)?.toInt(),
    );
  }

  /// The Vorbis comments this authority dictates. Only these; everything else in the file stays.
  /// Both spellings of the total, always together.
  ///
  /// Vorbis never settled on one: rippers write TRACKTOTAL, TOTALTRACKS, or both. Writing only
  /// TRACKTOTAL and leaving a stale TOTALTRACKS behind puts two different answers in one file, and
  /// which one you get depends on the reader. Measured on the real Backstreet's Back after the
  /// first normalisation: TRACKTOTAL=16 beside TOTALTRACKS=11 in the same file. This app read 16 and
  /// showed one tile; Roon or a phone reading the other field would still see the record split.
  Map<String, String?> get vorbisFields => {
        'TITLE': title,
        'ARTIST': artist,
        if ((albumArtist ?? '').isNotEmpty) 'ALBUMARTIST': albumArtist,
        'ALBUM': album,
        if (trackNo > 0) 'TRACKNUMBER': '$trackNo',
        if (trackTotal > 0) 'TRACKTOTAL': '$trackTotal',
        if (trackTotal > 0) 'TOTALTRACKS': '$trackTotal',
        if (year != null) 'DATE': '$year',
      };
}

/// An official release, used to decide what each downloaded file IS.
///
/// Soulseek serves one song under a dozen names — "13 Anywhere for You", "19. Backstreet Boys -
/// Anywhere For You", "…The Essential Backstreet Boys - 01 - Anywhere for You" — and each carries
/// its own tags to match. Rather than trusting any of them, the record itself says which track this
/// is; the peer only supplies the audio.
class ReleaseAuthority {
  final String artist, album;
  final String? albumArtist;
  final int? year;

  /// The official tracklist, in order.
  final List<ChoiceTrack> tracks;

  const ReleaseAuthority({
    required this.artist,
    required this.album,
    required this.tracks,
    this.albumArtist,
    this.year,
  });

  TrackTags forTrack(ChoiceTrack t, int trackNo) => TrackTags(
        title: t.title,
        artist: artist,
        album: album,
        albumArtist: albumArtist ?? artist,
        trackNo: trackNo,
        trackTotal: tracks.length,
        year: year,
      );

  /// Which official track a peer's file is, or null when nothing matches well enough.
  ///
  /// Matched on the NAME and the running time — never on the number in the filename, which is the
  /// thing that is wrong. A file from a compilation says "01" for what is track 2 of this record.
  TrackTags? match(String filename, int durationSec) {
    final hit = matchOfficial(tracks, baseName(filename), durationSec);
    if (hit == null) return null;
    return forTrack(hit, tracks.indexOf(hit) + 1);
  }
}

/// The official track that [name] (a filename or a title) and [durationSec] describe, or null.
///
/// Shared so the album download and the "take this numbering" dialog agree about what counts as
/// the same song — two answers to that question would be one answer too many.
ChoiceTrack? matchOfficial(List<ChoiceTrack> official, String name, int durationSec) {
  ChoiceTrack? best;
  var bestScore = 0.0;
  final words = fileWords(name);
  for (final o in official) {
    var score = wordSim(words, fileWords(o.title));
    if (normKey(name) == normKey(o.title)) score = 1;
    // A running time within twelve seconds corroborates a name that merely reads alike; a wildly
    // different one is reason to doubt it ("Get Down" against "Get Down (Extended Club Mix)").
    if (durationSec > 0 && (o.seconds ?? 0) > 0) {
      score += (durationSec - o.seconds!).abs() <= 12 ? .25 : -.25;
    }
    if (score > bestScore) {
      bestScore = score;
      best = o;
    }
  }
  // Below this the two are not the same song, and guessing would misfile the record.
  return bestScore < .55 ? null : best;
}

/// Read the tags of a downloaded file (falls back to the filename for the title).
///
/// FLAC is read with our own parser FIRST, and not only because the package chokes on values like
/// a vinyl "A3" track number: when it throws it leaves the file HANDLE OPEN, so that track can
/// never be moved or deleted again for the rest of the session — a download would sit stuck in the
/// staging folder forever. Avoiding the throwing path is the only way to avoid the leak.
TrackTags? readTags(File f) {
  final base = f.uri.pathSegments.last;
  final noExt = base.contains('.') ? base.substring(0, base.lastIndexOf('.')) : base;

  // De ALBUMARTIEST hoort erbij, en dat is geen detail: een greep uit een verzamelbox is aan niets
  // anders te herkennen. De artiest van het nummer is dan gewoon de echte zanger (Khaled), en pas
  // ALBUMARTIST verraadt "Various Artists". Zonder dit veld werd zo'n bestand een album van Khaled met
  // één nummer 779 erin. [vanBestand] houdt intussen overeind dat dit géén officiële uitgave is.
  String? albumArtistVan(File g) {
    try {
      final rauw = g.path.toLowerCase().endsWith('.flac')
          ? readFlacRawFields(g)
          : readMp3RawFields(g).map((k, v) => MapEntry(k, v ?? ''));
      final v = (rauw['albumartist'] ?? '').trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  if (base.toLowerCase().endsWith('.flac')) {
    final v = readFlacTags(f);
    if (v != null && (v.title != null || v.artist != null || v.album != null)) {
      return TrackTags(
        title: v.title ?? noExt,
        artist: v.artist ?? '',
        album: v.album ?? '',
        trackNo: v.trackNo,
        albumArtist: albumArtistVan(f),
        trackTotal: v.trackTotal,
        vanBestand: true,
      );
    }
  }
  // Zelfde vangnet voor mp3 als hierboven voor FLAC, en het ontbrak precies waar het nodig was.
  //
  // Gemeten geval: één bestand in de wortel van de bibliotheek werd bij het opbergen overgeslagen
  // met "geen tags te lezen", terwijl de eigen ID3-lezer er zes velden uit haalt -- artiest, titel,
  // album en drie die vol reclame stonden. Het pakket claimt hem niet, en voor FLAC staat er wel een
  // terugval en voor mp3 stond er niets. Dezelfde scheefheid als bij het SCHRIJVEN: de mp3-schrijver
  // was ook op alles aangesloten behalve op de weg die hem het meest gebruikt.
  //
  // Bewust NA het pakket en niet ervoor. Het pakket leest ook ID3v1, en deze lezer heeft een
  // v2-kop nodig; ervoor zetten zou dus voor élke mp3 gaan gelden en een v1-only bestand juist
  // slechter af maken. Als vangnet raakt hij alleen de bestanden die nu helemaal niets opleveren.
  TrackTags? viaEigenId3() {
    if (!base.toLowerCase().endsWith('.mp3')) return null;
    final raw = readMp3RawFields(f);
    final titel = raw['title']?.trim() ?? '';
    final artiest = raw['artist']?.trim() ?? '';
    final album = raw['album']?.trim() ?? '';
    if (titel.isEmpty && artiest.isEmpty && album.isEmpty) return null;
    return TrackTags(
      title: titel.isEmpty ? noExt : titel,
      artist: artiest,
      album: album,
      trackNo: int.tryParse(raw['tracknumber'] ?? '') ?? 0,
      albumArtist: (raw['albumartist'] ?? '').trim().isEmpty ? null : raw['albumartist']!.trim(),
      trackTotal: int.tryParse(raw['tracktotal'] ?? '') ?? 0,
      vanBestand: true,
    );
  }

  // A staged download the package cannot parse would otherwise lock itself into the staging
  // folder: the handle it keeps on the refusal makes the file un-renameable for good.
  if (!tagParserWouldClaim(f)) return viaEigenId3();
  try {
    final m = readMetadata(f, getImage: false);
    return TrackTags(
      title: (m.title?.trim().isNotEmpty ?? false) ? m.title!.trim() : noExt,
      artist: (m.artist?.trim().isNotEmpty ?? false) ? m.artist!.trim() : '',
      album: m.album?.trim() ?? '',
      trackNo: m.trackNumber ?? 0,
      albumArtist: albumArtistVan(f),
      trackTotal: m.trackTotal ?? 0,
      vanBestand: true,
    );
  } catch (_) {
    return viaEigenId3();
  }
}

/// The tidy relative location for a track: `<Artist>/<Albums|Singles|Compilaties>/…`.
/// Compilations by many artists are grouped under one "Various Artists" tree so the release
/// stays together instead of being scattered over every guest artist.
String relativePathFor(TrackTags t, {RelKind? kind, required String ext}) {
  final k = kind ??
      classifyRelease(
          album: t.album,
          artist: t.artist,
          albumArtist: t.albumArtist,
          totaalVolgensTags: t.trackTotal);
  final artist = t.artist.trim().isEmpty ? 'Onbekende artiest' : t.artist.trim();
  final num = t.trackNo > 0 ? t.trackNo.toString().padLeft(2, '0') : null;
  final sep = Platform.pathSeparator;

  switch (k) {
    case RelKind.single:
      return ['Singles', safeSeg(artist), safeSeg('${t.title}$ext')].join(sep);
    case RelKind.compilation:
      final va = _variousRe.hasMatch(artist) ? _variousArtists : artist;
      final file = num != null ? '$num - $artist - ${t.title}$ext' : '$artist - ${t.title}$ext';
      return ['Compilaties', safeSeg(va), safeSeg(t.album), safeSeg(file)].join(sep);
    case RelKind.album:
      final file = num != null ? '$num - ${t.title}$ext' : '${t.title}$ext';
      return ['Albums', safeSeg(artist), safeSeg(t.album), safeSeg(file)].join(sep);
  }
}

/// A track's identity for duplicate detection. Keeps version markers ("(Live)", "(Radio Edit)")
/// so ONLY true duplicates collapse — different versions stay separate, as the user asked.
String trackIdentity(String artist, String title) => '${normKey(artist)}|${normKey(title)}';

/// Rank of an audio format — higher wins when two copies of the same track exist.
///
/// FLAC/ALAC/APE sit ABOVE WAV even though all four are lossless. WAV is uncompressed, so it is
/// always the bigger file and on size alone would evict a FLAC of the same audio — and it carries
/// no tags this app can write (the tag writer is FLAC-only), so a WAV that wins lands untagged and
/// scans as a nameless "Onbekende artiest" single. For a library headed to Roon a WAV is strictly
/// worse than the identical FLAC, so it never beats one.
///
/// New downloads no longer offer WAV at all — see [sortSoulseek], which drops it before anything gets
/// to choose. Ranking it low was not enough: where no FLAC was on offer a WAV still won, and won a
/// copy the app could never label. This ranking still matters for what is ALREADY on disk, which is
/// what the duplicate sweep compares.
int formatRank(String path) {
  final e = path.toLowerCase();
  if (e.endsWith('.flac') || e.endsWith('.ape') || e.endsWith('.alac')) return 4;
  if (e.endsWith('.wav')) return 3; // lossless, but uncompressed and untaggable
  if (e.endsWith('.m4a') || e.endsWith('.aac') || e.endsWith('.ogg') || e.endsWith('.opus')) return 2;
  return 1; // mp3 and friends
}

/// Which of two copies of the SAME track to keep. Format first, then stereo over surround, and
/// only then size.
///
/// The stereo rule matters because a 5.1 rip is always the bigger file: on size alone it would
/// evict a proper stereo master, both here and when tidying the downloads folder — the exact
/// opposite of "best quality" on a stereo system.
/// Wat [firstIsBetter] moet weten en niet uit een bestand kan lezen: welke bestanden de gebruiker
/// zelf koos, en welke bewezen nep zijn.
///
/// Bestaat om deze afweging in een ISOLATE te kunnen draaien. Allebei die feiten staan in een kaart
/// in het geheugen (`vaste_keuze.dart`, `echtheid_oordelen.dart`), en een isolate begint met een lege
/// kopie van alle globale staat. Zonder dit zou daar élk bestand lezen als "niet gekozen, niet nep",
/// en dan vallen de twee regels weg die bóven de kwaliteitsgronden staan — stil, met een andere
/// winnaar als enig spoor.
///
/// Null betekent "vraag het de winkels zelf", en dat is wat elke aanroeper op de hoofdisolate doet.
typedef Voorkennis = ({Set<String> vast, Set<String> nep});

bool firstIsBetter(File a, File b, {Voorkennis? kennis}) {
  // WAT DE GEBRUIKER ZELF KOOS VERLIEST NIET. Boven alle drie de gronden hieronder, want die gaan
  // over kwaliteit en dit gaat over iets anders: bij Joe Dassin / L'été indien is de beste kopie een
  // ánder nummer, en de handmatig gekozen 3:37 verloor van een 4:16 op de laatste grond — grootte.
  //
  // Hier en niet bij de aanroepers, want dit is het enige punt waar élke opruimweg langskomt: het
  // filen van een download, Opruimen, de dubbelveger per album en die over de hele bibliotheek. Vijf
  // plekken kun je vergeten, één niet.
  //
  // Koos hij ze allebéi, dan valt er geen voorkeur af te lezen en beslist de gewone regel.
  final va = kennis == null ? isVasteKeuze(a.path) : kennis.vast.contains(sleutelVoor(a.path));
  final vb = kennis == null ? isVasteKeuze(b.path) : kennis.vast.contains(sleutelVoor(b.path));
  if (va != vb) return va;
  final ra = formatRank(a.path), rb = formatRank(b.path);
  if (ra != rb) return ra > rb;
  final ma = _isMultichannelFile(a), mb = _isMultichannelFile(b);
  if (ma != mb) return mb; // the stereo one wins
  // WAT GEMETEN IS ALS NEP VERLIEST — vlak boven de grootte, want dáár gaat het mis.
  //
  // Een mp3 die naar FLAC is omgezet is vaak GROTER dan het origineel: mp3-artefacten comprimeren
  // slecht. Gemeten met een eigen proef: origineel 34 MB, dezelfde muziek via 320 kbps terug naar FLAC
  // 76 MB. De regel hieronder koos dus stelselmatig de nep-kopie, en precies dat was Sabers vraag.
  //
  // Alleen wat BEWEZEN is telt; een ongemeten bestand mag nooit verliezen van een gemeten, anders
  // herordent het draaien van een veegbeurt de halve bibliotheek. En vlak boven de grootte, zodat deze
  // regel uitsluitend vuurt in het geval waar de grootte anders zou beslissen — niets daarbuiten.
  final na = kennis == null ? bewezenNep(a.path) : kennis.nep.contains(echtheidSleutelVoor(a.path));
  final nb = kennis == null ? bewezenNep(b.path) : kennis.nep.contains(echtheidSleutelVoor(b.path));
  if (na != nb) return nb;
  return a.lengthSync() > b.lengthSync();
}

/// Why [keep] beat [drop], read off the same three grounds [firstIsBetter] decides on and in that
/// order — so the sentence can never say one thing while the choice says another.
String whyBetter(File keep, File drop) {
  String ext(File f) {
    final n = f.path;
    final i = n.lastIndexOf('.');
    return i < 0 ? '?' : n.substring(i + 1).toUpperCase();
  }

  // In dezelfde volgorde als [firstIsBetter] beslist, dus ook deze grond hoort vooraan te staan —
  // anders zegt het scherm "32.4 MB tegen 29.1 MB" terwijl de grootte er niets mee te maken had.
  if (isVasteKeuze(keep.path) != isVasteKeuze(drop.path)) {
    return isVasteKeuze(keep.path) ? 'door jou zelf gekozen' : 'jouw eigen keuze blijft staan';
  }
  final rk = formatRank(keep.path), rd = formatRank(drop.path);
  if (rk != rd) return '${ext(keep)} boven ${ext(drop)}';
  if (_isMultichannelFile(keep) != _isMultichannelFile(drop)) return 'stereo boven surround';
  // Zelfde gronden, zelfde volgorde als [firstIsBetter] — anders zegt het scherm "32,4 MB tegen
  // 29,1 MB" terwijl de grootte er niets mee te maken had.
  if (bewezenNep(keep.path) != bewezenNep(drop.path)) {
    final o = gemeten(drop.path);
    return o == null ? 'de echte boven de nagemaakte' : 'de echte — de andere: ${waarom(o)}';
  }
  try {
    String mb(File f) => '${(f.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${mb(keep)} tegen ${mb(drop)}';
  } catch (_) {
    return 'groter bestand';
  }
}

/// De namen die surround verraden, één keer samengesteld.
///
/// Hij stond in de body van [surroundLabel], en dat was op de telefoon te VOELEN. Die functie hangt
/// in de rangschikking van de bronnenlijst, en die draait bij zevenduizend Soulseek-treffers
/// tienduizenden keren per keer tekenen. Een `RegExp` in een body wordt bij élke aanroep opnieuw
/// vertaald — precies het soort kosten dat nergens opvalt behalve als haperend scrollen.
final _surroundInNaam = RegExp(
    r'(\b5[\._ ]1\b|\b7[\._ ]1\b|surround|multi[\- ]?channel|quadraphonic|quad\b|atmos)',
    caseSensitive: false);

/// Wat een naam zegt over het aantal kanalen: `5.1`, `7.1`, `Atmos`, … of null voor gewoon stereo.
///
/// Een LABEL en geen ja/nee, want dit is bedoeld om te tonen. Bij een zoekresultaat is de naam alles wat
/// er is — Soulseek meldt het kanaalaantal niet — en dan is "5.1" een bruikbaar antwoord en "surround"
/// een vaag antwoord. Beide zijn beter dan het verschil niet zien.
///
/// **Dit is een aanwijzing, geen meting.** Een surroundbestand dat zichzelf niet zo noemt glipt hier
/// doorheen; pas als het bestand op schijf staat leest [_isMultichannelFile] het echte kanaalaantal uit
/// de FLAC-kop. Daarom staat die weg er nog steeds naast en gaat de naam alleen vóór als er niets beters
/// is.
String? surroundLabel(String naam) {
  final m = _surroundInNaam.firstMatch(naam);
  if (m == null) return null;
  final gevonden = m.group(0)!.toLowerCase();
  if (gevonden.startsWith('5')) return '5.1';
  if (gevonden.startsWith('7')) return '7.1';
  if (gevonden.startsWith('atmos')) return 'Atmos';
  if (gevonden.startsWith('quad')) return 'quad';
  return 'surround';
}

/// Surround by its own header, or by a release name that says so (covers non-FLAC too).
/// Onthouden wat er in een bestand stond, want dit kost een volledige FLAC-kopparse.
///
/// [firstIsBetter] roept dit voor BEIDE bestanden aan, en die draait in de binnenlus van
/// [redundantAlbums] — dat is elk kandidaat-albumpaar maal elk nummer, op de tekendraad, tijdens de
/// scan. `explainWinner` vraagt het daarna nog eens voor hetzelfde paar.
///
/// De sleutel is `(pad, mtime, grootte)` en niet alleen het pad: bij het opruimen wordt op hetzelfde
/// pad een ander bestand neergezet, en dan zou een geheugen op alleen het pad het oude antwoord
/// blijven geven — precies bij de beslissing welke kopie je houdt.
final Map<String, bool> _surroundGeheugen = {};

bool _isMultichannelFile(File f) {
  String? sleutel;
  try {
    final st = f.statSync();
    sleutel = '${f.path}|${st.modified.millisecondsSinceEpoch}|${st.size}';
    final bewaard = _surroundGeheugen[sleutel];
    if (bewaard != null) return bewaard;
  } catch (_) {/* niet te statten: gewoon lezen, en niets onthouden */}

  final tags = readFlacTags(f);
  final uit = tags != null && tags.channels > 0 ? tags.multichannel : surroundLabel(f.path) != null;
  if (sleutel != null) {
    // Een bovengrens, want dit is een geheugen voor de duur van de sessie en een opruimbeurt over een
    // grote bibliotheek mag geen map van tienduizenden regels achterlaten.
    if (_surroundGeheugen.length > 4000) _surroundGeheugen.clear();
    _surroundGeheugen[sleutel] = uit;
  }
  return uit;
}

/// What happened to a file we tried to file away.
enum Placement {
  moved, // filed in the tidy tree
  duplicate, // the same recording was already there and the better copy was kept
  stuck, // couldn't read or move it — still at its original path
}

class PlaceOutcome {
  final String path;
  final Placement how;
  const PlaceOutcome(this.path, this.how);
}

/// Move [src] into the tidy tree under [root]. Returns the final path (or the original on
/// failure — never loses the file). If the SAME RECORDING is already there, the better copy wins
/// and the loser is dropped; a different recording that happens to tag identically (a live take,
/// a remix whose version marker only lives in the filename) is kept alongside it.
Future<PlaceOutcome> placeFileDetailed(File src, String root,
    {RelKind? kind, TrackTags? tags, String? Function(String artist, String title)? staatAl}) async {
  final t = tags ?? readTags(src);
  if (t == null) return PlaceOutcome(src.path, Placement.stuck);
  final base = src.uri.pathSegments.last;
  final ext = base.contains('.') ? base.substring(base.lastIndexOf('.')) : '';
  // A version marker lifted out of the peer's filename is useful when the filename is all we have,
  // and noise when we already know which track of which release this is. The candidate was matched
  // on title AND running time before it was ever downloaded, so a live take of a different length
  // never gets this far — which is the job _carryVersion was doing here.
  final named = t.isAuthoritative ? t : _carryVersion(t, base);
  final volledig = relativePathFor(named, kind: kind, ext: ext);

  // Heb je deze opname al? Dan gaat de nieuwe daar NAARTOE, en niet naar een map die uit zijn eigen
  // albumtag volgt.
  //
  // Dit is het verschil tussen opwaarderen en verzamelen. Een 24/192 van Thriller draagt `ALBUM =
  // Thriller`, terwijl de negen die je al hebt `ALBUM = Thriller (MFSL One Step)` dragen — twee uitgaves
  // volgens de tags, dus twee mappen, dus twee albums in de bibliotheek. En omdat de vervangingsregel
  // alleen binnen één map kijkt, kwam die er nooit aan te pas: het betere bestand landde ernaast en het
  // mindere bleef staan.
  //
  // Met dit ene lijntje valt alles op zijn plek. De bestemming wordt het bestaande bestand, waarna
  // [firstIsBetter] hieronder gewoon zijn werk doet: de hoogste resolutie blijft, de vorige gaat naar
  // `_dubbel` (nooit weg), en er komt geen tweede album bij.
  //
  // De prijs is echt en de aanroeper moet hem willen: twee persingen náást elkaar bewaren kan hiermee
  // niet meer op dit pad. Vandaar dat het een parameter is en geen vaste regel — alleen de downloadweg
  // geeft hem mee.
  // [staatAl] geeft het PAD van het bestand dat er al ligt, niet alleen de map. Dat verschil is de hele
  // reparatie. Met alleen de map werd de bestandsnaam alsnog uit de tags van de uploader afgeleid, en
  // die schrijft geen tracknummer -- dus kwam "Bailamos.flac" naast "10 - Bailamos.flac" te liggen. Twee
  // bestanden van hetzelfde nummer, want ze botsten nergens, en dan komt de vervangingsregel er nooit
  // aan te pas. Gemeten op Enrique: twee opwaarderingen die er netjes NAAST kwamen te staan.
  //
  // De extensie blijft die van de BRON: een FLAC die een mp3 opvolgt hoort .flac te heten, en dan vindt
  // [_sameTrackOtherFormat] hieronder de mp3 als de kopie die vervangen wordt.
  final bestaand = staatAl?.call(named.artist, named.title);
  final elders = bestaand == null ? null : File(bestaand).parent.path;
  final rel = bestaand == null
      ? _reuseExistingFolders(root, volledig)
      : _zelfdeNaamAndereExtensie(bestaand, volledig);
  var dest = File(bestaand == null ? '$root${Platform.pathSeparator}$rel' : rel);
  if (dest.path == src.path) return PlaceOutcome(src.path, Placement.moved);
  try {
    await dest.parent.create(recursive: true);

    bool newWins(File rival) => firstIsBetter(src, rival);

    // With an authority the destination path was built from the official tags, so it IS this
    // track's identity — a file already there can only be the same song, a better copy the sweep
    // found. Fuzzy-matching the peer's raw staging name against the clean filed name is what wrongly
    // read the two as different takes and dropped the upgrade beside the original as a "(2)".
    //
    // `elders != null` doet hetzelfde voor de tweede weg hierheen, en dát was het overgebleven gat.
    // Het staat er wanneer [staatAl] een bestaand bestand aanwees en `dest` daarnaartoe is gebogen
    // (zie hierboven): de bibliotheek heeft dan al gezegd dat dit die opname IS. Wie daarna alsnog de
    // bestandsnamen laat beslissen, laat een uploader beslissen — en die schrijft "(Remastered 2011)"
    // of "(Single Version)" waar jouw gefilede kopie kaal "02 - Titel.flac" heet. [_sameRecording]
    // leest dat als een andere opname, en dan gebeurt er iets ergers dan naast elkaar zetten: in die
    // tak blijft `losers` leeg, dus de oude kopie wordt NIET geparkeerd. Gemeld en nagegaan op
    // Rihanna — Where Have You Been, waar de slechte gewoon bleef staan met de goede ernaast als "(2)".
    bool same(File a, File b) => t.isAuthoritative || elders != null || _sameRecording(a, b);

    final losers = <File>[];
    if (await dest.exists()) {
      if (same(src, dest)) {
        if (!newWins(dest)) {
          final gone = src.parent.path;
          await src.delete().catchError((_) => src);
          await pruneVacated(gone, root);
          return PlaceOutcome(dest.path, Placement.duplicate);
        }
        losers.add(dest);
      } else {
        dest = _sidestep(dest); // different take — both are worth keeping, so make room
      }
    } else {
      // The destination name carries the SOURCE's extension, so upgrading an MP3 to FLAC lands on
      // a DIFFERENT path — without this the two would sit side by side forever. Same track under
      // another extension counts as the copy being replaced.
      final rival = _sameTrackOtherFormat(dest);
      if (rival != null && same(src, rival)) {
        if (!newWins(rival)) {
          final gone = src.parent.path;
          await src.delete().catchError((_) => src);
          await pruneVacated(gone, root);
          return PlaceOutcome(rival.path, Placement.duplicate);
        }
        losers.add(rival);
      }
    }
    final srcDir = src.parent.path;
    final loserDirs = [for (final l in losers) l.parent.path];
    // Alleen parkeren als we NAAR een bestaand album zijn gestuurd: dan is de verliezer een bestand dat
    // al in de bibliotheek stond, en dat is van jou. Op de gewone weg is de verliezer iets wat deze
    // download zelf net ophaalde, en dat mag gewoon weg.
    final landed = await _install(src, dest, losers,
        parkeerIn: elders == null ? null : '$root${Platform.pathSeparator}$parkeerMap');
    // Soulseek delivered the audio; the record's identity comes from here. Without this the file
    // sits under the right name in the right folder while its TAGS still say it is track 1 of
    // "The Essential Backstreet Boys" — and the tags are what the library and Roon actually read.
    //
    // En bij het vóégen bij een bestaand album: neem de albumnaam van de buren over. Dat is niet
    // cosmetisch. De bibliotheek groepeert op de ALBUM-tag en niet op de map, en elke peer schrijft een
    // andere: gemeten kwamen er voor Thriller drie varianten binnen -- "Thriller", "Thriller (MFSL One
    // Step)" en "Thriller (Epic, Mjj Productions - 88875143731, Eu)". Zonder dit staat het betere
    // bestand netjes in de goede map en tóch als apart album in beeld, wat precies de klacht was.
    //
    // Overgenomen van een buurbestand en niet van de uitgave die de download koos: het gaat erom dat
    // deze negen bij elkáár horen, en de buren zijn de enigen die weten onder welke naam dat is.
    await stampTags(File(landed), t);
    if (elders != null) {
      // Rechtstreeks die velden, en niet via [stampTags]: die schrijft met opzet niets als de tags
      // niet van een officiële uitgave komen, en die van een peer zijn dat nooit. Precies daarom hield
      // het binnengekomen bestand zijn eigen albumnaam en stond het album alsnog dubbel in beeld.
      //
      // TRACKTOTAL gaat mee om dezelfde reden, maar tegen een ander soort dubbel: de bibliotheek
      // splitst een album op dat getal zodra twee nummers hetzelfde tracknummer claimen. Een uploader
      // ripte van een andere persing en schrijft 11 of 17 waar jouw plaat 13 zegt, en dan breekt één
      // vervangen nummer de plaat in stukken. Zie [_burenZeggen].
      // En de ARTIEST, maar alleen als de buren dezelfde artiest VOLLEDIGER schrijven. De bibliotheek
      // groepeert ook op artiest, dus een bestand dat "Enrique" zegt tussen buren die "Enrique
      // Iglesias" zeggen blijft een eigen tegel — ook al staat het in de goede map met de goede
      // albumnaam. Gemeten op Escape: 7 nummers en 1.
      //
      // De dekkingstoets is de rem. Zonder die toets zou "Enrique Iglesias feat. Whitney Houston"
      // worden platgeslagen tot "Enrique Iglesias" en was je de gastcredit kwijt — een echte fout,
      // en eentje die je pas maanden later merkt.
      final buren = _burenZeggen(elders, landed);
      final velden = <String, String?>{
        if (buren.album != null) 'ALBUM': buren.album,
        if (buren.totaal != null) 'TRACKTOTAL': '${buren.totaal}',
        if (buren.totaal != null) 'TOTALTRACKS': '${buren.totaal}',
        if (buren.artiest != null && _naamDekt(buren.artiest!, named.artist)) 'ARTIST': buren.artiest,
      };
      if (velden.isNotEmpty) await writeTagFields(File(landed), velden);
    }
    // The folder the file came from, and the folder a replaced copy came from, are often empty now:
    // the per-peer staging folder always, and an album folder whose last track was superseded.
    for (final d in {srcDir, ...loserDirs}) {
      await pruneVacated(d, root);
    }
    return PlaceOutcome(landed, Placement.moved);
  } catch (_) {
    return PlaceOutcome(src.path, Placement.stuck); // cross-device or locked — the scan still finds it
  }
}

/// Write an official release's identity into a landed file. No-op unless [t] is authoritative.
///
/// FLAC and MP3, through [writeTagFields]. Both are rewritten by this app's own writers, which
/// rebuild only the tag and copy every other byte — the reason it is safe to do at all. Anything
/// else is left alone and lets its correct filename and folder speak, because the tag writers on
/// offer for those containers drop every field they do not model.
///
/// Runs in an isolate: parsing a stranger's file is exactly where a throw would otherwise leak the
/// handle and leave the track unmovable for the rest of the session.
Future<bool> stampTags(File f, TrackTags t) async {
  if (!t.isAuthoritative) return false;
  return writeTagFields(f, t.vorbisFields);
}

/// Write an explicit set of Vorbis fields into a FLAC. A null value deletes that field.
///
/// The same writer [stampTags] uses; the difference is that the caller says what the fields are
/// instead of deriving them from a release. Undoing a rewrite needs exactly that: it has to be able
/// to put back "this field was not here", which no [TrackTags] can express.
///
/// Runs in an isolate: parsing a stranger's file is exactly where a throw would otherwise leak the
/// handle and leave the track unmovable for the rest of the session.
/// [waarom] krijgt, als het misgaat, één zin in gewone taal. Zonder dat verdween de reden hier in
/// een `catch (_)`, en bleef er op het scherm "3 niet gelukt" over — terwijl het commentaar bij die
/// melding beloofde dat je zou weten waaróm. Een bestand dat openstaat in een andere speler en een
/// bestand op een volle schijf zijn heel verschillende problemen, en alleen het eerste los je op
/// door iets dicht te doen.
Future<bool> writeTagFields(
  File f,
  Map<String, String?> fields, {
  void Function(String)? waarom,
}) async {
  final path = f.path;
  final mp3 = path.toLowerCase().endsWith('.mp3');
  if (!mp3 && !path.toLowerCase().endsWith('.flac')) {
    waarom?.call('alleen FLAC en MP3 worden geschreven');
    return false;
  }
  try {
    // The one place the format is decided, because it is also the one place undoing goes through.
    // Both writers keep the same promise: rebuild only the tag, copy every other byte, land through
    // a temporary file, and refuse rather than guess.
    final gelukt = await Isolate.run(() => mp3
            ? writeMp3Fields(File(path), fields)
            : writeFlacFields(File(path), fields))
        // Dertig seconden is ruim: een volledige herschrijving van 723 MB op 32/384 -- het grootste
        // dat hier binnenkomt -- gemeten op 3 seconden. Dit kapt een vastgelopen schrijver af, geen
        // eerlijke kopie.
        .timeout(const Duration(seconds: 30));
    // De schrijver zegt zelf nee. Dat is geen uitzondering maar een oordeel: hij weigert liever dan
    // te gokken op een tag die hij niet begrijpt.
    if (!gelukt) waarom?.call('de schrijver herkende de tag in dit bestand niet');
    return gelukt;
  } on TimeoutException {
    waarom?.call('het schrijven liep vast en is na 30 seconden afgekapt');
    return false;
  } catch (e) {
    waarom?.call(schrijffoutUitleg(e));
    return false; // the file is still filed correctly; only its tags stayed as they were
  }
}

/// Een schrijffout in gewone taal, en met wat eraan te doen valt.
///
/// De drie die werkelijk voorkomen staan er met naam bij. De rest valt terug op wat het besturings-
/// systeem zei -- lelijk, maar nog altijd oneindig veel meer dan niets.
String schrijffoutUitleg(Object e) {
  if (e is FileSystemException) {
    final code = e.osError?.errorCode;
    // 32 op Windows (ERROR_SHARING_VIOLATION) en 16 op macOS/Linux (EBUSY, "resource busy"): een
    // ander programma houdt het bestand vast. Verreweg de gewoonste, en de enige die je zelf oplost.
    if (code == 32 || code == 16) {
      return 'het bestand is in gebruik door een ander programma';
    }
    if (code == 13 || code == 5) return 'geen toestemming om dit bestand te wijzigen';
    if (code == 28) return 'geen ruimte meer op de schijf';
    if (code == 2) return 'het bestand staat er niet meer';
    final os = e.osError?.message.trim() ?? '';
    final bericht = e.message.trim();
    // Allebei leeg kan: `FileSystemException('')` bestaat. Dan liever de kale uitzondering dan een
    // lege melding — want leeg is precies de stand waar dit ding vanaf moest.
    if (bericht.isEmpty && os.isEmpty) return '$e';
    if (os.isEmpty) return bericht;
    return bericht.isEmpty ? os : '$bericht: $os';
  }
  return '$e';
}

/// For callers that only care where the file ended up.
Future<String> placeFile(File src, String root, {RelKind? kind, TrackTags? tags}) async =>
    (await placeFileDetailed(src, root, kind: kind, tags: tags)).path;

/// Carry a version marker from the source filename into the title, when the tags dropped it.
///
/// Uploaders write "(Live Version)" in the filename while the title tag stays plain, so filing a
/// track purely by its tags throws that away — and then the live take and the studio take want the
/// exact same destination. Keeping the marker in the name means they simply land side by side,
/// it's obvious in Explorer which is which, and a second copy of that same live take still
/// recognises its twin.
TrackTags _carryVersion(TrackTags t, String filename) {
  final title = t.title.toLowerCase();
  final extra = versionMarkers(filename).where((m) => !title.contains(m)).toList()..sort();
  if (extra.isEmpty) return t;
  return TrackTags(
    title: '${t.title} (${extra.join(') (')})',
    artist: t.artist,
    album: t.album,
    trackNo: t.trackNo,
  );
}

/// Words that mark a filename as a particular VERSION of a track.
final _versionWordRe = RegExp(
    r'\b(live|remix|rmx|edit|extended|radio|demo|instrumental|ac+ap+ell?a|acoustic|reprise|'
    r'unplugged|version|mix|remaster(ed)?|alternate|alt take|session|karaoke|dub|bonus|'
    r'single|club|original|mono|stereo)\b');
final _bracketRe = RegExp(r'[(\[]([^)\]]{1,60})[)\]]');
final _partRe = RegExp(r'\b(?:part|pt\.?)\s*(\d+|[ivx]+)\b', caseSensitive: false);

/// Het deelnummer in een titel, Romeins of Arabisch, altijd als hetzelfde getal.
///
/// Gemeten op Rihanna's Loud: MusicBrainz schrijft "Love the Way You Lie (Part II)" en het bestand
/// heet "Love the Way You Lie, Pt. 2" -- zelfde nummer, allebei 4:56 -- en die twee hielden elkaar
/// buiten de deur omdat het ene merk "part 2" heette en het andere niets.
String? _partNumber(String s) {
  final m = _partRe.firstMatch(s);
  if (m == null) return null;
  final ruw = m.group(1)!.toLowerCase();
  final arabisch = int.tryParse(ruw);
  if (arabisch != null) return arabisch > 0 ? '$arabisch' : null;
  const waarde = {'i': 1, 'v': 5, 'x': 10};
  var totaal = 0, hoogste = 0;
  for (var i = ruw.length - 1; i >= 0; i--) {
    final v = waarde[ruw[i]];
    if (v == null) return null;
    if (v < hoogste) {
      totaal -= v;
    } else {
      totaal += v;
      hoogste = v;
    }
  }
  return totaal > 0 ? '$totaal' : null;
}

/// De titel zonder alles wat een VERSIE aanduidt: de versie-haakjes en een "Part 2" of "Pt. II".
///
/// Voor het vergelijken van títels. Merken worden apart vergeleken, dus ze ook nog in de woorden
/// laten staan straft hetzelfde verschil twee keer af -- en dat is genoeg om een treffer te missen.
String withoutVersionText(String title) {
  var out = title;
  for (final merk in versionBrackets(title)) {
    out = out.replaceAll(
        RegExp('[(\\[]\\s*${RegExp.escape(merk)}\\s*[)\\]]', caseSensitive: false), ' ');
  }
  return out.replaceAll(_partRe, ' ');
}

/// Bracketed woorden die GEEN versie aanduiden maar juist de gewone albumopname.
///
/// "(Album Version)" betekent letterlijk: de versie die op het album staat. Een catalogus schrijft
/// die zelden mee, een ripper vaak wel, en dat verschil liet de plaat er onvolledig uitzien.
///
/// Gemeten over de hele bibliotheek: Rihanna's Loud verloor er drie nummers aan ("What's My Name?
/// (Album Version)" tegen een kale rij) en "Te Amo" één, met dezelfde looptijd aan beide kanten. Het
/// omgekeerde komt ook voor -- daar staat het merk juist op de UITGAVE en niet op het bestand.
///
/// Bewust alleen dit. "single version", "original mix" en "club mix" schelen ook maar een woord en
/// zijn wel degelijk andere opnames; "album" is het enige woord dat de standaardversie aanwijst.
const _geenEchtMerk = {'album version', 'album mix'};

/// Elk haakje dat over een VERSIE gaat, ook de haakjes die geen onderscheid maken.
///
/// [versionMarkers] zeeft de nep-merken hieruit weg, want die mogen twee opnames niet scheiden. De
/// titelvergelijking wil ze juist allemaal kwijt: "(Album Version)" hoort niet bij de naam van het
/// nummer, dus het mag ook niet meewegen in hoeveel woorden twee titels delen.
Set<String> versionBrackets(String filename) {
  final base = filename.toLowerCase().replaceAll(RegExp(r'\.[a-z0-9]{2,5}$'), '');
  final out = <String>{};
  for (final m in _bracketRe.allMatches(base)) {
    final seg = m.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (_versionWordRe.hasMatch(seg)) out.add(seg);
  }
  return out;
}

/// The version markers a filename claims: `D.A.N.C.E. (Live Version).flac` → `{live version}`.
/// Only bracketed segments that actually contain a version word count, so noise like `(2021)`,
/// `(WWW)` or `[PMEDIA]` doesn't masquerade as a different take.
/// De titel zonder de haakjes die GEEN andere opname aanwijzen — en met alle andere er nog in.
///
/// Voor het HERKENNEN van een opname die je al hebt. `Escape (Album Version)` en `Escape` zijn
/// hetzelfde nummer; `Escape (Live)` en `Escape` niet. Die eerste gelijkstelling ontbrak, en dat is
/// duurder dan het klinkt: [LibraryStore.recordingElsewhere] vond het bestaande bestand niet, dus
/// wist de downloadweg niet dat er iets te VERVANGEN viel, en kwam de betere kopie ernaast te liggen
/// als een tweede album. Gemeten op Enrique's Escape: twee tegels, 7 nummers en 1.
///
/// Bewust via [versionMarkers] en niet met een eigen zeef. Die functie kent het verschil tussen een
/// echt merk en een nepmerk al; hier wordt alleen zijn oordeel gebruikt. Staat er ook maar één echt
/// merk in de titel, dan blijft de titel ongemoeid — liever een treffer mislopen dan twee verschillende
/// opnames op één hoop.
String withoutFakeVersion(String title) =>
    versionMarkers(title).isEmpty ? withoutVersionText(title) : title;

Set<String> versionMarkers(String filename) {
  final out = versionBrackets(filename).where((s) => !_geenEchtMerk.contains(s)).toSet();
  final base = filename.toLowerCase().replaceAll(RegExp(r'\.[a-z0-9]{2,5}$'), '');
  final deel = _partNumber(base);
  if (deel != null) out.add('part $deel');
  return out;
}

/// Wijst de versie-aanduiding in [titel] naar de UITGAVE waar dit bestand in ligt?
///
/// **Het gemelde geval.** Op *My Songs* van Sting heet nummer 7 "Fields of Gold (My Songs
/// Version)" — een heropname uit 2019, niet de plaat uit 1993. Op Soulseek heet dat bestand bij
/// iedereen gewoon `07 Fields of Gold.flac`, want bínnen dat album is er niets om van te
/// onderscheiden. Het onderscheid zit in de MAP: `Sting - My Songs (2019)`.
///
/// [fileOffersTitle] keek alleen naar de bestandsnaam, en dan is "(My Songs Version)" drie woorden
/// die het bestand niet heeft. Zo werd juist de goede kopie geweigerd, en bleef alleen de gewone
/// versie over — precies waar de gebruiker nooit aan de heropname geraakte.
///
/// **Waarom dit veilig is en niet alles doorlaat.** Er wordt niet gezegd "haakjes tellen niet mee".
/// Er wordt gezegd: het merk moet de map BENOEMEN. Van "my songs version" blijft na het generieke
/// woord ("version") "my songs" over, en die woorden moeten dan in het pad staan. Bij "Fields of
/// Gold (Live)" blijft er niets over om te bewijzen, dus die gaat hier NIET doorheen — en dat hoort,
/// want een live-opname is een andere opname, waar hij ook ligt.
///
/// De looptijd blijft er in [fileOffersTitle] achteraan als tweede slot: een heropname uit 2019 en
/// de plaat uit 1993 lopen zelden even lang.
bool versieVolgtUitMap(String titel, String pad) {
  final merken = versionMarkers(titel);
  if (merken.isEmpty) return false;
  final mapWoorden = fileWords(
      pad.substring(0, pad.length - baseName(pad).length).replaceAll(RegExp(r'[\\/]'), ' '));
  if (mapWoorden.isEmpty) return false;
  for (final merk in merken) {
    // Het generieke woord eraf — "version", "mix", "edit". Wat overblijft is de naam waar het merk
    // naar wijst, en díé moet in het pad staan.
    final rest = fileWords(merk).where((w) => !_versionWordRe.hasMatch(w)).toSet();
    if (rest.isEmpty) return false;
    if (!rest.every(mapWoorden.contains)) return false;
  }
  return true;
}

/// Are these two files the same RECORDING (as opposed to two takes of the same song)?
///
/// The FILENAME decides first, because that is where the difference usually survives: an uploader
/// writes "(Live Version)" in the name while the title tag stays plain "D.A.N.C.E.". Two files
/// claiming different versions are different recordings even if they happen to run equally long.
/// Only when the names claim the same thing does the duration break the tie.
bool _sameRecording(File a, File b) {
  final ma = versionMarkers(a.uri.pathSegments.last);
  final mb = versionMarkers(b.uri.pathSegments.last);
  if (!_setEquals(ma, mb)) return false;
  final da = readFlacTags(a)?.duration, db = readFlacTags(b)?.duration;
  if (da == null || db == null) return true; // can't tell — fall back to the old dedup behaviour
  return (da - db).abs() <= const Duration(seconds: sameRecordingSlack);
}

/// How far two files of one title may drift and still be one recording.
///
/// Tighter than the [matchAlbumTracks] tolerance on purpose: that one compares a file against a
/// catalogue entry that may describe a different pressing, while this compares two files a user
/// actually holds. Rips of one master differ by a second or two; a radio edit and the album cut
/// differ by far more, and collapsing those loses music. Shared so the library and the filer
/// cannot answer the same question differently.
const sameRecordingSlack = 5;

bool _setEquals(Set<String> a, Set<String> b) => a.length == b.length && a.every(b.contains);

const _audioExts = {'.flac', '.mp3', '.m4a', '.ogg', '.opus', '.wav', '.aac', '.alac', '.ape'};

/// The same track already filed under a DIFFERENT extension, if there is one.
///
/// Matched on the name with its leading track number stripped, so "06 - Telephone.mp3" and
/// "1-06 - Telephone.flac" still recognise each other — rips disagree about disc prefixes.
/// Only ever matches ACROSS formats: within one format two files named alike are a two-disc set
/// repeating a title, and deleting one of those would lose a track.
File? _sameTrackOtherFormat(File dest) {
  final sep = Platform.pathSeparator;
  final parent = Directory(dest.path.substring(0, dest.path.lastIndexOf(sep)));
  final destName = dest.path.split(sep).last;
  final wanted = trackNameKey(destName);
  final destExt = _extOf(destName);
  if (wanted.isEmpty) return null;
  try {
    for (final e in parent.listSync(followLinks: false)) {
      if (e is! File || e.path == dest.path) continue;
      final name = e.path.split(sep).last;
      final ext = _extOf(name);
      if (!_audioExts.contains(ext) || ext == destExt) continue;
      if (trackNameKey(name) == wanted) return e;
    }
  } catch (_) {/* folder not there yet */}
  return null;
}

String _extOf(String filename) {
  final dot = filename.lastIndexOf('.');
  return dot < 0 ? '' : filename.substring(dot).toLowerCase();
}

/// A filename reduced to just the track: extension gone, a leading "06 - " / "1-06. " gone,
/// then normalised. Empty when nothing but a number remains.
///
/// The track number is only stripped when a SEPARATOR follows it. An earlier version allowed a
/// second run of digits there, which silently ate numbers belonging to the title: "10 - 99
/// Problems" collapsed to "problems" and so matched an unrelated "05 - Problems" — and the
/// caller deletes what it matches.
String trackNameKey(String filename) {
  final dot = filename.lastIndexOf('.');
  var stem = dot > 0 ? filename.substring(0, dot) : filename;
  stem = stem.replaceFirst(RegExp(r'^\s*(?:\d{1,2}[-.])?\d{1,3}\s*[-._]\s*'), '');
  return normKey(stem);
}

/// `03 - D.A.N.C.E..flac` → `03 - D.A.N.C.E. (2).flac`, first free number.
File _sidestep(File dest) {
  final p = dest.path;
  final dot = p.lastIndexOf('.');
  final stem = dot > 0 ? p.substring(0, dot) : p;
  final ext = dot > 0 ? p.substring(dot) : '';
  for (var n = 2; n < 50; n++) {
    final f = File('$stem ($n)$ext');
    if (!f.existsSync()) return f;
  }
  return dest;
}

/// Rewrite the FOLDER parts of [rel] to match folders that already exist, when they differ only
/// in spelling. A second spelling of an artist ("Beyoncé" after "Beyonce") would otherwise build
/// a parallel tree next to the first, splitting one artist over two folders.
/// The filename itself is left alone — two files are not the same file.
String _reuseExistingFolders(String root, String rel) {
  final sep = Platform.pathSeparator;
  final parts = rel.split(sep);
  var dir = root;
  for (var i = 0; i < parts.length - 1; i++) {
    final wanted = normKey(parts[i]);
    if (wanted.isEmpty) continue;
    try {
      for (final e in Directory(dir).listSync(followLinks: false)) {
        if (e is! Directory) continue;
        final name = e.path.split(sep).last;
        if (name != parts[i] && normKey(name) == wanted) {
          parts[i] = name; // an existing folder means the same thing — use it
          break;
        }
      }
    } catch (_) {/* folder doesn't exist yet — nothing to reuse */}
    dir = '$dir$sep${parts[i]}';
  }
  return parts.join(sep);
}

/// Put [src] at [dest] and only then drop the copies it supersedes.
///
/// Order matters: deleting first and moving second means a failed move (locked file, disk full)
/// leaves you with NEITHER — the copy you had is gone and the new one is stranded in staging.
/// De albumnaam die de buren in deze map dragen, of null als er niets te leren valt.
///
/// De bibliotheek groepeert op de ALBUM-tag en niet op de map. Landt er een bestand in een map waar de
/// rest een andere albumnaam heeft, dan staat het als apart album in beeld — hoe netjes het op schijf
/// ook staat. Gemeten kwamen er voor Thriller drie varianten binnen: "Thriller", "Thriller (MFSL One
/// Step)" en "Thriller (Epic, Mjj Productions - 88875143731, Eu)".
///
/// De meest vóórkomende naam wint, niet de eerste die we tegenkomen: bij een album dat half vervangen
/// is, hoort de meerderheid te beslissen en niet de alfabetische volgorde.
/// Het pad van [bestaand], maar met de extensie van [bron].
///
/// Zo landt een FLAC die een mp3 opvolgt op `10 - Bailamos.flac` naast `10 - Bailamos.mp3`, waar
/// [_sameTrackOtherFormat] hem herkent als dezelfde opname in een ander formaat en de mp3 laat wijken.
/// Was de extensie die van het bestaande bestand, dan zou een FLAC als `.mp3` worden weggeschreven --
/// een bestand dat over zichzelf liegt, en dat is erger dan het probleem.
String _zelfdeNaamAndereExtensie(String bestaand, String bron) {
  String ext(String p) {
    final i = p.lastIndexOf('.');
    final s = p.lastIndexOf(Platform.pathSeparator);
    return i > s ? p.substring(i) : '';
  }

  final e = ext(bron);
  if (e.isEmpty) return bestaand;
  final i = bestaand.lastIndexOf('.');
  final s = bestaand.lastIndexOf(Platform.pathSeparator);
  return i > s ? '${bestaand.substring(0, i)}$e' : '$bestaand$e';
}

/// Wat de buren in deze map over hun plaat zeggen: onder welke NAAM ze staan, en van hoeveel nummers
/// hun uitgave is.
///
/// Die tweede is er later bij gekomen, en niet voor de sier. De bibliotheek splitst een album zodra
/// twee nummers hetzelfde tracknummer claimen én een verschillend TRACKTOTAL opgeven — zie
/// `LibraryStore.editionSplit`. Dat is een goede regel: zo blijven twee echte persingen uit elkaar.
///
/// Maar bij het VERVANGEN van een nummer werkt hij averechts. De betere kopie komt van een willekeurige
/// uploader, en die ripte van een andere persing: hij zegt 11 of 17 waar jouw plaat 13 zegt. Eén zo'n
/// bestand is genoeg om het album in drieën te breken. Gemeten op Backstreet's Back: 12 nummers onder
/// "13 nummers", 1 onder "11 nummers" en 2 onder "17 nummers" — drie tegels van één plaat.
///
/// Het gaat er hier niet om van welke persing dit bestand kwam, maar bij welke plaat het hoort. De buren
/// zijn de enigen die dat weten, en de meerderheid beslist — bij een half vervangen album hoort niet de
/// toevallige eerste te winnen.
/// Dekt [ruimer] de naam [smaller] volledig, op hele woorden?
///
/// "Enrique Iglesias" dekt "Enrique", maar "Amy" wordt niet gedekt door "Amy Winehouse" andersom te
/// lezen — daar zou je de ene artiest voor de andere aanzien. Hele woorden dus, met spaties eromheen.
///
/// Staat hier en niet in library.dart, waar `LibraryStore._artistCovers` hetzelfde doet: dit bestand
/// zit LAGER in de stapel, library.dart importeert organize.dart en andersom zou een kring worden.
/// Dezelfde reden als bij [parkeerMap].
bool _naamDekt(String ruimer, String smaller) {
  final a = ' ${ruimer.toLowerCase().trim()} ';
  final b = ' ${smaller.toLowerCase().trim()} ';
  return b.trim().isNotEmpty && a.contains(b);
}

({String? album, int? totaal, String? artiest}) _burenZeggen(String map, String zelf) {
  final namen = <String, int>{};
  final totalen = <int, int>{};
  final artiesten = <String, int>{};
  var buren = 0;
  try {
    for (final f in Directory(map).listSync().whereType<File>()) {
      if (f.path == zelf) continue;
      final tags = readTags(f);
      if (tags != null) buren++;
      final naam = tags?.album.trim() ?? '';
      if (naam.isNotEmpty) namen[naam] = (namen[naam] ?? 0) + 1;
      final art = tags?.artist.trim() ?? '';
      if (art.isNotEmpty) artiesten[art] = (artiesten[art] ?? 0) + 1;
      // Voor het TOTAAL rechtstreeks de FLAC-lezer, want [readTags] geeft een [TrackTags] terug en die
      // draagt alleen titel, artiest, album en tracknummer -- `trackTotal` staat daar altijd op 0. Dat
      // is geen bug in TrackTags: dat type beschrijft wat er GESCHREVEN mag worden bij het opbergen.
      // Hier wordt gelezen, en dan is de volledige kop de juiste bron.
      final totaal = readFlacTags(f)?.trackTotal ?? 0;
      if (totaal > 0) totalen[totaal] = (totalen[totaal] ?? 0) + 1;
    }
  } catch (_) {
    return (album: null, totaal: null, artiest: null); // map niet te lezen: alles blijft zoals het was
  }
  return (
    album: namen.isEmpty ? null : namen.entries.reduce((a, b) => b.value > a.value ? b : a).key,
    totaal: totalen.isEmpty ? null : totalen.entries.reduce((a, b) => b.value > a.value ? b : a).key,
    // De ARTIEST alleen bij een STEVIGE meerderheid, en dat is hier strenger dan bij de albumnaam.
    // Een albumnaam die afwijkt is hooguit lelijk; een artiestnaam die afwijkt verandert onder wiens
    // naam je muziek staat. Unanimiteit alleen is te zwak: `_burenZeggen` slaat het bestand zelf over,
    // dus in een map met twee nummers is één buur per definitie unaniem. Vandaar de ondergrens.
    artiest: (buren >= 3 && artiesten.length == 1) ? artiesten.keys.single : null,
  );
}

/// Waar een kopie heen gaat die het aflegt tegen een betere: opzij, niet weg.
///
/// Staat hier en niet in library.dart omdat dit bestand lager in de stapel zit — library.dart
/// importeert organize.dart, andersom zou een kring worden. `dupeFolder` daar wijst hierheen, zodat er
/// één naam is en niet twee die kunnen gaan verschillen.
const parkeerMap = '_dubbel';

Future<String> _install(File src, File dest, List<File> losers, {String? parkeerIn}) async {
  if (losers.isEmpty) return _move(src, dest);
  // Land beside the target first, so nothing is destroyed until the new file is really here.
  final tmp = File('${dest.path}.incoming');
  final landed = await _move(src, tmp);
  for (final l in losers) {
    try {
      // Wat de app zelf net binnenhaalde en meteen weer verloor, mag weg -- dat is afval van deze
      // download. Maar een bestand dat AL in de bibliotheek stond is van de gebruiker, en dat wordt
      // geparkeerd in plaats van gewist. Zo werkt Opruimen ook: de mindere gaat naar `_dubbel`, nooit
      // de vuilnisbak in.
      if (parkeerIn != null) {
        final naam = l.uri.pathSegments.last;
        final dir = Directory(parkeerIn);
        await dir.create(recursive: true);
        var doel = File('$parkeerIn${Platform.pathSeparator}$naam');
        for (var n = 2; await doel.exists(); n++) {
          doel = File('$parkeerIn${Platform.pathSeparator}($n) $naam');
        }
        await _move(l, doel);
      } else {
        await l.delete();
      }
    } catch (_) {/* couldn't remove the old copy — the new one still lands */}
  }
  try {
    final at = (await File(landed).rename(dest.path)).path;
    // Deze hernoeming loopt NIET langs [_move] — het is de laatste stap van "eerst ernaast landen, dan
    // pas op zijn plek". De markering van een handmatige keuze hangt aan het pad en zou anders op het
    // tijdelijke `.incoming` blijven staan, waar hij niets meer beschermt. Zelfde voor de meting.
    herNoemVasteKeuze(landed, at);
    herNoemOordeel(landed, at);
    return at;
  } catch (_) {
    return landed; // still on disk under .incoming; the scan picks it up
  }
}

/// Move with a couple of retries, then a copy+delete fallback.
/// A freshly downloaded file often gets touched briefly by something else on the machine — a
/// virus scanner, the search indexer, a music server watching the folder — and a rename that
/// lands in that window fails outright. Giving up there strands the track in staging.
///
/// Public because merging an album moves files that have been sitting in the library for months,
/// where that same window is if anything wider: the player may hold one open, and a plain rename
/// that loses the race would leave half a record moved.
Future<String> moveWithRetry(File src, File dest) => _move(src, dest);

Future<String> _move(File src, File dest) async {
  // De bescherming van een handmatige keuze hangt aan het PAD, en dit is de enige plek in de app waar
  // een muziekbestand van pad verandert. Zonder deze regel gold zo'n keuze precies één keer: het filen
  // van een download verplaatst het bestand van de landingsmap naar `Albums/…`, en daarna wees de
  // lijst naar iets wat er niet meer is. Dezelfde reden dat de bescherming zelf in [firstIsBetter]
  // zit: één doorgang die niet te vergeten is.
  void volgMee(String naar) {
    herNoemVasteKeuze(src.path, naar);
    // De meting hangt ook aan het pad, en om precies dezelfde reden: zonder dit geldt een
    // echtheidsmeting maar één keer, want het filen verplaatst het bestand.
    herNoemOordeel(src.path, naar);
  }

  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final at = (await src.rename(dest.path)).path;
      volgMee(at);
      return at;
    } catch (_) {
      if (attempt < 2) await Future.delayed(Duration(milliseconds: 250 * (attempt + 1)));
    }
  }
  // Still no: copy instead, and only drop the original once the copy is safely in place.
  await src.copy(dest.path);
  try {
    await src.delete();
  } catch (_) {/* copy stands; the staging leftover gets cleaned up later */}
  volgMee(dest.path);
  return dest.path;
}

/// Result of tidying a folder.
class TidyReport {
  int moved = 0, duplicates = 0, skipped = 0;
  @override
  String toString() => '$moved verplaatst · $duplicates dubbel opgeruimd · $skipped overgeslagen';
}

/// Re-file every loose audio file under [downloadsRoot] into the tidy tree, and remove exact
/// duplicates (same artist+title, keeping the best format/size). Only ever touches files
/// INSIDE [downloadsRoot] — the user's own collection elsewhere is never moved.
Future<TidyReport> tidyDownloads(String downloadsRoot) async {
  final report = TidyReport();
  final dir = Directory(downloadsRoot);
  if (!await dir.exists()) return report;

  const audio = {'.flac', '.mp3', '.m4a', '.ogg', '.opus', '.wav', '.aac', '.alac', '.ape'};
  final files = <File>[];
  await for (final e in dir.list(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final p = e.path.toLowerCase();
    final dot = p.lastIndexOf('.');
    if (dot < 0 || !audio.contains(p.substring(dot))) continue;
    files.add(e);
  }

  // File everything and let placeFileDetailed decide about duplicates. It compares only against
  // what is already in the SAME album folder, which is the only place a real duplicate can be.
  //
  // This used to dedupe on artist+title across the whole tree, which quietly deleted different
  // RELEASES of one song: the live take on "Live @ Mezzanine" and the studio take on "†" both tag
  // as "Justice | D.A.N.C.E." — only the album differs — so the live version was thrown away.
  for (final f in files) {
    final before = f.path;
    final out = await placeFileDetailed(f, downloadsRoot);
    switch (out.how) {
      case Placement.moved:
        if (out.path != before) report.moved++;
      case Placement.duplicate:
        report.duplicates++;
      case Placement.stuck:
        report.skipped++;
    }
  }

  // Sweep up the now-empty folders left behind.
  await sweepEmptyFolders(dir.path);
  return report;
}

/// The files Windows and macOS drop into a folder by themselves. A folder holding nothing but
/// these was emptied by us; the user never put them there.
const _osJunk = {'thumbs.db', 'desktop.ini', '.ds_store'};

/// True when [child] sits strictly below [root] — never [root] itself.
bool _under(String child, String root) {
  if (root.trim().isEmpty) return false;
  final sep = Platform.pathSeparator;
  String norm(String p) {
    var s = p.replaceAll('/', sep).replaceAll('\\', sep);
    while (s.length > 1 && s.endsWith(sep)) {
      s = s.substring(0, s.length - 1);
    }
    return Platform.isWindows ? s.toLowerCase() : s;
  }

  final c = norm(child), r = norm(root);
  return c.length > r.length + 1 && c.startsWith('$r$sep');
}

/// Remove the folder a file just left, and every parent that empties with it, stopping below
/// [root]. Called from each place that moves a file OUT of a folder.
///
/// Cover art is deliberately not treated as junk. A folder still holding folder.jpg keeps standing,
/// because deleting a picture the user put there is not what "clean up empty folders" means — only
/// the OS's own droppings are swept along.
Future<void> pruneVacated(String vacated, String root) async {
  var dir = Directory(vacated);
  // Eight hops is far more than the tree is deep (root/Albums/Artist/Album/dubbel) and stops a
  // symlink loop from walking the disk.
  for (var hop = 0; hop < 8; hop++) {
    if (!_under(dir.path, root)) return;
    List<FileSystemEntity> kids;
    try {
      if (!await dir.exists()) {
        dir = dir.parent;
        continue;
      }
      kids = await dir.list(followLinks: false).toList();
    } catch (_) {
      return;
    }
    final onlyJunk = kids.every((e) => e is File && _osJunk.contains(e.uri.pathSegments.last.toLowerCase()));
    if (!onlyJunk) return; // something real is still in there
    try {
      for (final k in kids) {
        await k.delete();
      }
      await dir.delete();
    } catch (_) {
      return; // in use, or no permission — leave it and stop climbing
    }
    dir = dir.parent;
  }
}

/// Sweep every empty folder under [root]. Deepest first, so an artist folder whose only album
/// folder just went goes with it in the same pass.
///
/// Walks the whole tree, so this is a once-per-launch or once-per-tidy job — the everyday case is
/// [pruneVacated], which only looks at the folder a file just left.
Future<void> sweepEmptyFolders(String root) async {
  if (root.trim().isEmpty) return;
  try {
    final dirs = <Directory>[];
    await for (final e in Directory(root).list(recursive: true, followLinks: false)) {
      if (e is Directory) dirs.add(e);
    }
    dirs.sort((a, b) => b.path.length.compareTo(a.path.length)); // deepest first
    for (final d in dirs) {
      if (!_under(d.path, root)) continue; // never the root itself
      try {
        final kids = await d.list(followLinks: false).toList();
        if (!kids.every((e) => e is File && _osJunk.contains(e.uri.pathSegments.last.toLowerCase()))) {
          continue;
        }
        for (final k in kids) {
          await k.delete();
        }
        await d.delete();
      } catch (_) {/* in use — leave this one */}
    }
  } catch (_) {}
}

/// Significant words of a download filename (lowercased, no extension, no bare track numbers) —
/// used to recognise the SAME track offered by different peers, who all name their files
/// differently ("02 Aerodynamic.flac", "Daft Punk - Aerodynamic.flac", "2. Aerodynamic.flac").
/// The number a pressing's stated position means, counted across the whole record.
///
/// A pressing does not always number in integers, and the two exceptions both collide if you just
/// read the first digit:
///   - Vinyl numbers per SIDE — "A3" and "B3" are both "3", and taking that literally puts two
///     tracks on number three and leaves the rest of the record unnumbered.
///   - A double CD numbers per DISC — "1-04" and "2-04" are both "4".
///
/// So a position is resolved by its place in the pressing's own list. That is the one reading that
/// is right for every format, including the plain integer case where it agrees with the number.
int trackNoFromPosition(String position, int disc, List<ChoiceTrack> all) {
  // "1-04": disc-qualified. Take the part after the dash as the within-disc number.
  final dashed = RegExp(r'^(\d+)\s*[-.]\s*(\d+)$').firstMatch(position.trim());
  final plain = dashed == null ? int.tryParse(position.trim()) : int.tryParse(dashed.group(2)!);

  // Single medium and a plain integer: the pressing already says what we want.
  if (plain != null && all.every((t) => t.disc == disc)) return plain;

  // Anything else — a vinyl side, a second disc — is resolved by position in the whole list, which
  // is the number a listener would count to.
  final at = all.indexWhere((t) => t.position == position && t.disc == disc);
  if (at >= 0) return at + 1;
  return plain ?? 0;
}

Set<String> fileWords(String displayName) {
  final noExt = displayName.toLowerCase().replaceAll(RegExp(r'\.[a-z0-9]{2,4}$'), '');
  final words = noExt.split(RegExp(r'[^a-z0-9]+')).where((w) => w.length > 1).toSet();
  words.removeWhere((w) => RegExp(r'^\d{1,3}$').hasMatch(w)); // drop bare track numbers
  return words;
}

/// Containment similarity of two word sets (0..1) — high when one filename's words are a
/// near-subset of the other's, which tolerates "01 - Everybody" vs "Artist - Everybody".
double wordSim(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final inter = a.intersection(b).length;
  final m = a.length < b.length ? a.length : b.length;
  return inter / m;
}

/// The last segment of a peer's path — the filename as a human would read it.
String baseName(String path) {
  final cut = path.lastIndexOf(RegExp(r'[\\/]'));
  return cut < 0 ? path : path.substring(cut + 1);
}

/// Words one name has and the other doesn't, that the other file's FOLDERS don't account for.
///
/// Peers disagree about whether the artist and album belong in the filename, so "Aerodynamic.flac"
/// and "Daft Punk - Discovery - 02 - Aerodynamic.flac" are the same track — but only because
/// "daft", "punk" and "discovery" are right there in the first file's folders. Words that appear
/// nowhere in the other file's path are a different song's title, not a naming habit.
Set<String> _unexplained(Set<String> mine, Set<String> theirs, String theirPath) {
  final context = fileWords(theirPath.replaceAll(RegExp(r'[\\/]'), ' '));
  return mine.difference(theirs).where((w) => !context.contains(w)).toSet();
}

/// Are two offered files the same recording, given how differently peers name things?
/// Both arguments are FULL peer paths — the folders are evidence, not noise.
///
/// Two real downloads went wrong here before this was tight enough. "Aerodynamic" scores a perfect
/// 1.0 against "One More Time + Aerodynamic", because the shorter name sits entirely inside the
/// longer one, and a 3:27 click fetched a 6:10 medley of 268 MB. Tightening on running time then
/// let through "Aerodynamic Beats + Forget About the World", which is 3:31 — four seconds from the
/// real track, so no clock can separate them. What separates them is that "beats", "forget" and
/// "world" appear nowhere in the other file's folders, while "daft" and "punk" always do.
bool sameRecording(String pathA, int? durA, String pathB, int? durB) {
  final a = fileWords(baseName(pathA)), b = fileWords(baseName(pathB));
  if (wordSim(a, b) < 0.8) return false;
  // A word that announces a different take — "remix", "live", "edit" — settles it first, however
  // close the running times, and they can be close: the Slum Village remix of Aerodynamic is 3:35
  // against the original's 3:27.
  if (a.difference(b).union(b.difference(a)).any(_versionWordRe.hasMatch)) return false;
  if (_unexplained(b, a, pathA).isNotEmpty) return false;
  if (_unexplained(a, b, pathB).isNotEmpty) return false;
  final da = durA ?? 0, db = durB ?? 0;
  if (da > 0 && db > 0) return (da - db).abs() <= 12;
  return true;
}

/// Bieden twee peers hetzelfde BESTAND aan — niet dezelfde opname, hetzelfde bestand?
///
/// Nadrukkelijk strenger dan [sameRecording], en met een andere opdracht. Die functie is bewust ruim:
/// hij zoekt kopieën van hetzelfde nummer, want voor een automatische download geldt hoe meer peers
/// hoe beter. Deze is er juist voor het geval dat de gebruiker ZELF een regel heeft aangeklikt. Dan is
/// "een andere rip van hetzelfde nummer" geen bruikbaar alternatief maar precies de overrule die hij
/// wilde wegnemen — bij Joe Dassin leverde de ruime regel een ánder nummer op.
///
/// Vier eisen, en elk van de vier is een keer nodig geweest:
/// * dezelfde basisnaam MET extensie — mapnamen verschillen per peer, de bestandsnaam niet;
/// * dezelfde extensie — een mp3 en een flac met dezelfde naam zijn niet hetzelfde bestand;
/// * grootte binnen 2% of 1 MB, wat het ruimst is — tags en een ingesloten hoes schelen makkelijk een
///   halve megabyte, dus byte-gelijkheid eisen zou elke echte kopie afwijzen;
/// * speelduur binnen 2 seconden als beide hem melden. Niet de twaalf van [sameRecording]: die marge
///   bestaat juist om verschillende rips te overbruggen, en dat is hier het tegenovergestelde.
///
/// Meldt een peer niets (grootte 0, duur onbekend), dan blijft alleen naam en extensie over. Liever
/// een korte terugvallijst dan een verkeerd bestand: als er niets overblijft hoort de app dat te
/// zeggen, niet iets anders te halen.
bool zelfdeBestand(String pathA, int sizeA, int? durA, String pathB, int sizeB, int? durB) {
  final a = baseName(pathA).trim().toLowerCase();
  final b = baseName(pathB).trim().toLowerCase();
  if (a.isEmpty || b.isEmpty) return false;
  if (normKey(a) != normKey(b)) return false;
  if (_ext(a) != _ext(b)) return false;
  if (sizeA > 0 && sizeB > 0) {
    final tweeProcent = (sizeA * 0.02).round();
    final speling = tweeProcent > 1024 * 1024 ? tweeProcent : 1024 * 1024;
    if ((sizeA - sizeB).abs() > speling) return false;
  }
  final da = durA ?? 0, db = durB ?? 0;
  if (da > 0 && db > 0 && (da - db).abs() > 2) return false;
  return true;
}

String _ext(String name) {
  final i = name.lastIndexOf('.');
  return i <= 0 || i == name.length - 1 ? '' : name.substring(i + 1);
}

/// Does [path] offer the track called [title] by [artist]?
///
/// Unlike [sameRecording] this compares a bare catalogue title against a peer's path, so there is
/// no second filename to explain the extra words — the artist's own name does that job instead.
bool fileOffersTitle(String title, int? titleDur, String artist, String path, int? fileDur) {
  // Wat de titel over de VERSIE zegt, kan in de map staan in plaats van in de bestandsnaam. Zie
  // [versieVolgtUitMap]: op *My Songs* heet nummer 7 bij elke peer gewoon "07 Fields of Gold.flac",
  // en het merk "(My Songs Version)" staat één laag hoger. Zonder deze uitzondering werd juist de
  // goede kopie geweigerd en bleef alleen de gewone versie over.
  final uitMap = versieVolgtUitMap(title, path);
  final vergelijkbaar = uitMap ? withoutVersionText(title) : title;
  final tw = fileWords(vergelijkbaar), fw = fileWords(baseName(path));
  if (tw.isEmpty || fw.isEmpty) return false;
  if (tw.intersection(fw).length / tw.length < 0.75) return false;
  if (tw.difference(fw).union(fw.difference(tw)).any(_versionWordRe.hasMatch)) return false;
  // Anything the filename says beyond the title must be the artist, the album, or the folders it
  // sits in — otherwise it is another song sharing a word with this one.
  final known = fileWords('$artist ${path.replaceAll(RegExp(r'[\\/]'), ' ')}'.replaceAll(baseName(path), ''));
  if (fw.difference(tw).any((w) => !known.contains(w))) return false;
  final a = titleDur ?? 0, b = fileDur ?? 0;
  if (a > 0 && b > 0) return (a - b).abs() <= 12;
  return true;
}

/// A Soulseek search query for one track — broad enough to be found, so the precise matching can
/// be left to [fileOffersTitle] afterwards.
///
/// Soulseek matches folded tokens and does badly with apostrophes and bracketed asides: a query
/// for `Get Down (You're the One for Me)` returns far fewer peers than `get down` does, and can
/// return none while live copies plainly exist — a peer that names the file `You're` tokenises to
/// `you re`, which the term `youre` never matches. So the brackets and punctuation come off here,
/// the strong words stay, and the full title still decides which results are really this song.
String soulseekQuery(String artist, String title) {
  List<String> tok(String s) =>
      s.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.length > 1).toList();
  // Drop "(You're the One for Me)"-style asides; they hurt the search and are recovered by the
  // title filter. If a title is ALL aside — "(Everything I Do)" — keep it rather than search blank.
  final body = tok(title.replaceAll(RegExp(r'[(\[{][^)\]}]*[)\]}]'), ' '));
  return [...tok(artist), ...(body.isEmpty ? tok(title) : body)].join(' ');
}

/// A name with Discogs' bookkeeping stripped off.
///
/// Discogs has to keep artists apart who share a name, so it appends a number — "Adele (3)" — and
/// marks a name variation with a trailing asterisk — "Kim 'Kay*". Neither is part of anyone's name.
/// Taking a Discogs credit at face value put eighteen of those into the library, and "Adele (3)"
/// ended up on the now-playing bar.
String cleanArtistName(String name) {
  var s = name.trim();
  s = s.replaceAll(RegExp(r'\s*\(\d{1,3}\)$'), '');
  s = s.replaceAll(RegExp(r'\*+$'), '');
  final out = s.trim();
  return out.isEmpty ? name.trim() : out;
}

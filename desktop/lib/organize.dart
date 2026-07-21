import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import 'flac_tags.dart';

/// Where a downloaded release belongs in the folder tree.
enum RelKind { album, single, compilation }

/// Album/artist/track names as the user typed them differ in punctuation ("Backstreet's Back"
/// with a curly ’ vs a straight ') — which used to split ONE album into two. Normalise for
/// COMPARISON only (never for display): unify quotes/dashes, drop punctuation, fold whitespace.
String normKey(String s) {
  final unified = _fold(s
      .toLowerCase()
      .replaceAll(RegExp(r'[‘’ʼ´`]'), "'")
      .replaceAll(RegExp(r'[“”]'), '"')
      .replaceAll(RegExp(r'[‐-―−]'), '-'));
  final stripped = unified.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  return stripped.trim().replaceAll(RegExp(r'\s+'), ' ');
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
String searchKey(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

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
RelKind classifyRelease({required String album, required String artist, int trackCount = 0}) {
  if (album.trim().isEmpty) return RelKind.single;
  final a = normKey(album);
  if (_compilationRe.hasMatch(a)) return RelKind.compilation;
  if (_variousRe.hasMatch(artist.trim())) return RelKind.compilation;
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
class TrackTags {
  final String title, artist, album;
  final int trackNo;
  const TrackTags({required this.title, required this.artist, required this.album, required this.trackNo});
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

  if (base.toLowerCase().endsWith('.flac')) {
    final v = readFlacTags(f);
    if (v != null && (v.title != null || v.artist != null || v.album != null)) {
      return TrackTags(
        title: v.title ?? noExt,
        artist: v.artist ?? '',
        album: v.album ?? '',
        trackNo: v.trackNo,
      );
    }
  }
  try {
    final m = readMetadata(f, getImage: false);
    return TrackTags(
      title: (m.title?.trim().isNotEmpty ?? false) ? m.title!.trim() : noExt,
      artist: (m.artist?.trim().isNotEmpty ?? false) ? m.artist!.trim() : '',
      album: m.album?.trim() ?? '',
      trackNo: m.trackNumber ?? 0,
    );
  } catch (_) {
    return null;
  }
}

/// The tidy relative location for a track: `<Artist>/<Albums|Singles|Compilaties>/…`.
/// Compilations by many artists are grouped under one "Various Artists" tree so the release
/// stays together instead of being scattered over every guest artist.
String relativePathFor(TrackTags t, {RelKind? kind, required String ext}) {
  final k = kind ?? classifyRelease(album: t.album, artist: t.artist);
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
int formatRank(String path) {
  final e = path.toLowerCase();
  if (e.endsWith('.flac') || e.endsWith('.wav') || e.endsWith('.ape') || e.endsWith('.alac')) return 3;
  if (e.endsWith('.m4a') || e.endsWith('.aac') || e.endsWith('.ogg') || e.endsWith('.opus')) return 2;
  return 1; // mp3 and friends
}

/// Which of two copies of the SAME track to keep. Format first, then stereo over surround, and
/// only then size.
///
/// The stereo rule matters because a 5.1 rip is always the bigger file: on size alone it would
/// evict a proper stereo master, both here and when tidying the downloads folder — the exact
/// opposite of "best quality" on a stereo system.
bool firstIsBetter(File a, File b) {
  final ra = formatRank(a.path), rb = formatRank(b.path);
  if (ra != rb) return ra > rb;
  final ma = _isMultichannelFile(a), mb = _isMultichannelFile(b);
  if (ma != mb) return mb; // the stereo one wins
  return a.lengthSync() > b.lengthSync();
}

/// Surround by its own header, or by a release name that says so (covers non-FLAC too).
bool _isMultichannelFile(File f) {
  final tags = readFlacTags(f);
  if (tags != null && tags.channels > 0) return tags.multichannel;
  return RegExp(r'(\b5[\._ ]1\b|\b7[\._ ]1\b|surround|multi[\- ]?channel|quadraphonic|atmos)',
          caseSensitive: false)
      .hasMatch(f.path);
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
Future<PlaceOutcome> placeFileDetailed(File src, String root, {RelKind? kind, TrackTags? tags}) async {
  final t = tags ?? readTags(src);
  if (t == null) return PlaceOutcome(src.path, Placement.stuck);
  final base = src.uri.pathSegments.last;
  final ext = base.contains('.') ? base.substring(base.lastIndexOf('.')) : '';
  final rel = _reuseExistingFolders(root, relativePathFor(_carryVersion(t, base), kind: kind, ext: ext));
  var dest = File('$root${Platform.pathSeparator}$rel');
  if (dest.path == src.path) return PlaceOutcome(src.path, Placement.moved);
  try {
    await dest.parent.create(recursive: true);

    bool newWins(File rival) => firstIsBetter(src, rival);

    final losers = <File>[];
    if (await dest.exists()) {
      if (_sameRecording(src, dest)) {
        if (!newWins(dest)) {
          await src.delete().catchError((_) => src);
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
      if (rival != null && _sameRecording(src, rival)) {
        if (!newWins(rival)) {
          await src.delete().catchError((_) => src);
          return PlaceOutcome(rival.path, Placement.duplicate);
        }
        losers.add(rival);
      }
    }
    return PlaceOutcome(await _install(src, dest, losers), Placement.moved);
  } catch (_) {
    return PlaceOutcome(src.path, Placement.stuck); // cross-device or locked — the scan still finds it
  }
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
final _partRe = RegExp(r'\b(?:part|pt\.?)\s*(\d+)\b');

/// The version markers a filename claims: `D.A.N.C.E. (Live Version).flac` → `{live version}`.
/// Only bracketed segments that actually contain a version word count, so noise like `(2021)`,
/// `(WWW)` or `[PMEDIA]` doesn't masquerade as a different take.
Set<String> versionMarkers(String filename) {
  final base = filename.toLowerCase().replaceAll(RegExp(r'\.[a-z0-9]{2,5}$'), '');
  final out = <String>{};
  for (final m in _bracketRe.allMatches(base)) {
    final seg = m.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (_versionWordRe.hasMatch(seg)) out.add(seg);
  }
  final part = _partRe.firstMatch(base);
  if (part != null) out.add('part ${part.group(1)}');
  return out;
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
  return (da - db).abs() <= const Duration(seconds: 5);
}

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
Future<String> _install(File src, File dest, List<File> losers) async {
  if (losers.isEmpty) return _move(src, dest);
  // Land beside the target first, so nothing is destroyed until the new file is really here.
  final tmp = File('${dest.path}.incoming');
  final landed = await _move(src, tmp);
  for (final l in losers) {
    try {
      await l.delete();
    } catch (_) {/* couldn't remove the old copy — the new one still lands */}
  }
  try {
    return (await File(landed).rename(dest.path)).path;
  } catch (_) {
    return landed; // still on disk under .incoming; the scan picks it up
  }
}

/// Move with a couple of retries, then a copy+delete fallback.
/// A freshly downloaded file often gets touched briefly by something else on the machine — a
/// virus scanner, the search indexer, a music server watching the folder — and a rename that
/// lands in that window fails outright. Giving up there strands the track in staging.
Future<String> _move(File src, File dest) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      return (await src.rename(dest.path)).path;
    } catch (_) {
      if (attempt < 2) await Future.delayed(Duration(milliseconds: 250 * (attempt + 1)));
    }
  }
  // Still no: copy instead, and only drop the original once the copy is safely in place.
  await src.copy(dest.path);
  try {
    await src.delete();
  } catch (_) {/* copy stands; the staging leftover gets cleaned up later */}
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
  await _pruneEmptyDirs(dir);
  return report;
}

Future<void> _pruneEmptyDirs(Directory root) async {
  try {
    final dirs = <Directory>[];
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is Directory) dirs.add(e);
    }
    dirs.sort((a, b) => b.path.length.compareTo(a.path.length)); // deepest first
    for (final d in dirs) {
      try {
        if (await d.list().isEmpty) await d.delete();
      } catch (_) {}
    }
  } catch (_) {}
}

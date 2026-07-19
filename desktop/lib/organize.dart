import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

/// Where a downloaded release belongs in the folder tree.
enum RelKind { album, single, compilation }

/// Album/artist/track names as the user typed them differ in punctuation ("Backstreet's Back"
/// with a curly ’ vs a straight ') — which used to split ONE album into two. Normalise for
/// COMPARISON only (never for display): unify quotes/dashes, drop punctuation, fold whitespace.
String normKey(String s) {
  final unified = s
      .toLowerCase()
      .replaceAll(RegExp(r'[‘’ʼ´`]'), "'")
      .replaceAll(RegExp(r'[“”]'), '"')
      .replaceAll(RegExp(r'[‐-―−]'), '-');
  final stripped = unified.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  return stripped.trim().replaceAll(RegExp(r'\s+'), ' ');
}

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
String safeSeg(String s) {
  var out = s.trim().replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '-');
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
TrackTags? readTags(File f) {
  try {
    final m = readMetadata(f, getImage: false);
    final base = f.uri.pathSegments.last;
    final noExt = base.contains('.') ? base.substring(0, base.lastIndexOf('.')) : base;
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

/// Move [src] into the tidy tree under [root]. Returns the final path (or the original on
/// failure — never loses the file). If a file is already there, the better copy wins and the
/// loser is left where it is for the caller to deal with.
Future<String> placeFile(File src, String root, {RelKind? kind, TrackTags? tags}) async {
  final t = tags ?? readTags(src);
  if (t == null) return src.path;
  final base = src.uri.pathSegments.last;
  final ext = base.contains('.') ? base.substring(base.lastIndexOf('.')) : '';
  final rel = relativePathFor(t, kind: kind, ext: ext);
  final dest = File('$root${Platform.pathSeparator}$rel');
  if (dest.path == src.path) return src.path;
  try {
    await dest.parent.create(recursive: true);
    if (await dest.exists()) {
      // Already have this track filed — keep the better copy, drop the other.
      final keepNew = formatRank(src.path) > formatRank(dest.path) ||
          (formatRank(src.path) == formatRank(dest.path) &&
              await src.length() > await dest.length());
      if (!keepNew) {
        await src.delete().catchError((_) => src);
        return dest.path;
      }
      await dest.delete().catchError((_) => dest);
    }
    final moved = await src.rename(dest.path);
    return moved.path;
  } catch (_) {
    return src.path; // cross-device or locked — leave it, the scan still picks it up
  }
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

  // Best copy per track identity first, so the winner is the one we keep.
  final best = <String, File>{};
  final losers = <File>[];
  for (final f in files) {
    final t = readTags(f);
    if (t == null) {
      report.skipped++;
      continue;
    }
    final id = trackIdentity(t.artist, t.title);
    final cur = best[id];
    if (cur == null) {
      best[id] = f;
      continue;
    }
    final fWins = formatRank(f.path) > formatRank(cur.path) ||
        (formatRank(f.path) == formatRank(cur.path) && await f.length() > await cur.length());
    if (fWins) {
      losers.add(cur);
      best[id] = f;
    } else {
      losers.add(f);
    }
  }

  for (final f in best.values) {
    final before = f.path;
    final after = await placeFile(f, downloadsRoot);
    if (after != before) report.moved++;
  }
  for (final f in losers) {
    try {
      await f.delete();
      report.duplicates++;
    } catch (_) {
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

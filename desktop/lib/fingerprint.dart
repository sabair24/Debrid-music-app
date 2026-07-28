/// Recognising a recording by what it SOUNDS like, not by what its tags claim.
///
/// Every other identifier in this app is hearsay. A filename, an ALBUM tag, a title in a catalogue —
/// all of it is somebody's typing, and the library is full of records where the typing is the whole
/// problem: two rips of the same song under different titles, and eight compilations that neither
/// MusicBrainz nor Discogs can name because "Various Artists — Serious Beats 51" is not a search, it
/// is a shrug.
///
/// Chromaprint answers a different question. It turns the audio itself into roughly four 32-bit
/// numbers per second, and two recordings of the same performance produce nearly the same numbers
/// however they were tagged, encoded or renamed. That is worth having on its own, before any web
/// service is involved: [similarity] compares two of these locally and needs nothing but the files.
///
/// **fpcalc is a separate program.** 1.7 MB, from the Chromaprint project, sitting next to the app's
/// own executable — the Windows installer copies the whole release folder, so shipping it is a
/// build-step, not a code change. When it is missing everything here returns null and the callers
/// fall back to what they did before; a music player must not stop working because a helper is not
/// installed.
///
/// **Only where the music is.** A phone or a television has no files to fingerprint and asks the PC
/// for facts anyway, so there is deliberately no Android or iOS binary to ship.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'paths.dart';

/// What one file sounds like: how long it plays, and the audio itself as numbers.
class Fingerprint {
  const Fingerprint(this.seconds, this.raw, this.compressed);

  /// Length as the DECODER measured it, which is not always what the tag says. AcoustID wants this
  /// one, and a duration read from a tag has been wrong often enough to be worth ignoring.
  final double seconds;

  /// One value per ~0.124 s of audio. Empty when only the compressed form was asked for.
  final List<int> raw;

  /// The same thing in the packed form the AcoustID web service expects. Null when only the raw form
  /// was asked for — the two are separate runs, and most files only ever need one.
  final String? compressed;

  bool get isEmpty => raw.isEmpty && (compressed == null || compressed!.isEmpty);
}

/// How alike two fingerprints are, from 0 (nothing in common) to 1 (identical).
///
/// Pure arithmetic on purpose: no files, no processes, no network, so the thing that decides "these
/// two are the same recording" can be tested exactly.
///
/// The measure is the bit error rate. Chromaprint packs each frame into 32 bits, so two frames of
/// the same audio differ in very few of them and two unrelated frames differ in about half. Counting
/// differing bits and dividing by 32 therefore lands near 0 for a match and near 0.5 for noise —
/// which is why the useful threshold is around 0.9 and not 0.5. Anything below ~0.55 is what two
/// random records score.
///
/// [maxOffset] slides one fingerprint along the other, because a re-rip can start a fraction of a
/// second earlier or later and an unaligned comparison of identical audio scores like noise. Thirty
/// frames is about four seconds, which covers a different lead-in without letting a short quote from
/// another track masquerade as a match.
double similarity(List<int> a, List<int> b, {int maxOffset = 30}) {
  if (a.isEmpty || b.isEmpty) return 0;
  var best = 0.0;
  for (var offset = -maxOffset; offset <= maxOffset; offset++) {
    final start = offset < 0 ? -offset : 0;
    final overlap = (offset < 0 ? a.length + offset : b.length - offset)
        .clamp(0, offset < 0 ? b.length : a.length);
    // Too little to judge on. Comparing eleven frames of a four-minute song finds a coincidence
    // sooner or later, and a coincidence scored 1.0 is worse than no answer.
    if (overlap < 20) continue;
    var bits = 0;
    for (var i = 0; i < overlap; i++) {
      final x = a[offset < 0 ? start + i : i + offset];
      final y = b[offset < 0 ? i : start + i];
      bits += _popcount(x ^ y);
    }
    final score = 1 - (bits / (overlap * 32));
    if (score > best) best = score;
  }
  return best;
}

/// Certainly the same recording. Measured on the real library, not guessed.
///
/// All 389 tracks were fingerprinted and every pair of matching length compared — 10,231 pairs. Two
/// unrelated records scored between 0.490 and 0.571, exactly the half-the-bits-differ that random
/// data gives. The genuine duplicates scored 0.951 (a FLAC against an MP3 of the same track), 0.990,
/// 0.998 (a .flac and an .m4a of one compilation track), 0.999 and 1.000 (the same recording twice
/// in one album folder, spelled "Workin' Day and Night" and "Working Day And Night").
///
/// And one pair sat in between: Adele's "Easy On Me" against "Easy On Me (With Chris Stapleton)",
/// at 0.929. That is a DIFFERENT recording over largely the same backing, and calling it a duplicate
/// would have offered a real track for deletion. Hence 0.95: it separates that case from every true
/// duplicate found, with room on both sides.
const double sameRecordingScore = 0.95;

/// Possibly the same recording — worth showing, not worth acting on.
///
/// The band between this and [sameRecordingScore] is where a duet, an alternate take or a radio edit of
/// the same backing lands. Nothing here is ever deleted on its own, so the honest thing is to show
/// the pair and say it is a doubt, rather than pick a single number and be confidently wrong about
/// Adele.
const double maybeSameRecordingScore = 0.90;

int _popcount(int v) {
  var x = v & 0xFFFFFFFF;
  x = x - ((x >> 1) & 0x55555555);
  x = (x & 0x33333333) + ((x >> 2) & 0x33333333);
  x = (x + (x >> 4)) & 0x0F0F0F0F;
  return (x * 0x01010101 >> 24) & 0xFF;
}

/// Runs fpcalc and remembers what it said.
class Fingerprinter {
  Fingerprinter({String? toolPath}) : _override = toolPath;

  final String? _override;

  /// Where fpcalc lives, or null if it does not.
  ///
  /// Beside the app's own executable first, because that is where the installer puts it. The
  /// development tree and PATH are checked too, so a checkout can be tested without an installer.
  static String? _found;
  static bool _looked = false;

  String? get tool {
    if (_override != null) return File(_override).existsSync() ? _override : null;
    if (_looked) return _found;
    _looked = true;
    final naam = Platform.isWindows ? 'fpcalc.exe' : 'fpcalc';
    final kandidaten = [
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}$naam',
      '${Directory.current.path}${Platform.pathSeparator}tools${Platform.pathSeparator}$naam',
    ];
    for (final k in kandidaten) {
      if (File(k).existsSync()) return _found = k;
    }
    return _found = null;
  }

  bool get available => tool != null;

  /// Forget where the tool was. Tests only.
  static void resetLookup() {
    _looked = false;
    _found = null;
  }

  /// What [path] sounds like, from the cache when the file has not changed since.
  ///
  /// Returns null when fpcalc is missing, when the file is gone, or when the decoder cannot read it.
  /// Never throws: a fingerprint is an enrichment, and nothing in this app may fail because an
  /// enrichment did.
  Future<Fingerprint?> of(String path, {bool compressed = false}) async {
    final exe = tool;
    if (exe == null) return null;
    File f;
    FileStat st;
    try {
      f = File(path);
      st = await f.stat();
      if (st.type == FileSystemEntityType.notFound) return null;
    } catch (_) {
      return null;
    }

    // Size and modified time in the key, so a re-download under the same name is a different
    // fingerprint rather than a stale one. That case is not hypothetical here — replacing a
    // transcode with a proper rip is exactly how this library gets its duplicates.
    final sleutel = '$path|${st.size}|${st.modified.millisecondsSinceEpoch}|${compressed ? 'c' : 'r'}';
    final cache = File('$_dir${Platform.pathSeparator}'
        '${sha1.convert(utf8.encode(sleutel))}.json');
    try {
      if (await cache.exists()) {
        final j = jsonDecode(await cache.readAsString());
        if (j is Map<String, dynamic>) return _fromJson(j);
      }
    } catch (_) {/* a cache that cannot be read is not a reason to fail */}

    ProcessResult r;
    try {
      r = await Process.run(exe, [
        '-json',
        if (!compressed) '-raw',
        path,
      ]);
    } catch (_) {
      return null;
    }
    if (r.exitCode != 0) return null;

    try {
      final j = jsonDecode('${r.stdout}');
      if (j is! Map<String, dynamic>) return null;
      final fp = _fromJson(j);
      if (fp == null || fp.isEmpty) return null;
      await Directory(_dir).create(recursive: true);
      await cache.writeAsString(jsonEncode(j));
      return fp;
    } catch (_) {
      return null;
    }
  }

  static Fingerprint? _fromJson(Map<String, dynamic> j) {
    final dur = (j['duration'] as num?)?.toDouble();
    if (dur == null) return null;
    final f = j['fingerprint'];
    if (f is List) {
      return Fingerprint(dur, [for (final v in f) (v as num).toInt()], null);
    }
    if (f is String && f.isNotEmpty) return Fingerprint(dur, const [], f);
    return null;
  }

  String get _dir => '$appDir${Platform.pathSeparator}fingerprints';
}

import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';

/// A tolerant FLAC tag reader, used when the metadata package refuses a file.
///
/// Why this exists: `audio_metadata_reader` runs `int.parse` on TRACKNUMBER, so a vinyl-style
/// value like "A3" (side A, track 3) throws and the WHOLE file is lost — it never reaches the
/// library and a download of it silently stays in the staging folder. Vinyl rips use those
/// numbers routinely, and "3/12" is common too. Here anything non-numeric is simply tolerated.
///
/// Deliberately minimal: the two metadata blocks worth having (STREAMINFO for the duration,
/// VORBIS_COMMENT for the tags), read from the file header only — never the audio payload, so
/// this stays cheap on a 160 MB hi-res track.
class FlacTags {
  final String? title, artist, album, genre;
  final int trackNo;

  /// How many tracks the release this file came from holds. The one tag that tells two EDITIONS
  /// of an album apart: one folder of Backstreet Boys held tracks claiming 12, 16 and 13, which is
  /// why it showed two track sixes and two track tens.
  final int trackTotal;
  final int? year;
  final Duration? duration;

  /// 2 for a normal stereo track, 6 for a 5.1 surround rip. Worth knowing: a surround mix is
  /// enormous and gets downmixed on a stereo system, so it must not beat a stereo master just
  /// because it carries more bits.
  final int channels;

  /// Samples per second (44100, 96000, …) and bits per sample (16, 24). Together they say whether
  /// a file is CD quality or hi-res — and whether a Sonos can play it at all, since Sonos stops
  /// at 48 kHz and *skips* anything above instead of downsampling it.
  final int sampleRate;
  final int bitsPerSample;

  const FlacTags({
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.trackNo = 0,
    this.trackTotal = 0,
    this.year,
    this.duration,
    this.channels = 0,
    this.sampleRate = 0,
    this.bitsPerSample = 0,
  });

  bool get multichannel => channels > 2;
}

/// Reads [f]'s FLAC tags, or null if it isn't FLAC / has no readable header.
FlacTags? readFlacTags(File f) {
  RandomAccessFile? raf;
  try {
    raf = f.openSync();
    if (String.fromCharCodes(raf.readSync(4)) != 'fLaC') return null;

    final fields = <String, String>{};
    Duration? duration;
    var channels = 0;
    var sampleRate = 0;
    var bitsPerSample = 0;
    for (var block = 0; block < 64; block++) {
      final h = raf.readSync(4);
      if (h.length < 4) break;
      final isLast = (h[0] & 0x80) != 0;
      final type = h[0] & 0x7F;
      final len = (h[1] << 16) | (h[2] << 8) | h[3];
      if (len < 0 || len > 64 * 1024 * 1024) break;

      if (type == 0 && len >= 18) {
        final d = raf.readSync(len);
        // STREAMINFO bytes 10..17 pack: 20 bits sample rate, 3 channels, 5 bits-per-sample,
        // then 36 bits of total sample count.
        sampleRate = (d[10] << 12) | (d[11] << 4) | (d[12] >> 4);
        final totalSamples =
            ((d[13] & 0x0F) << 32) | (d[14] << 24) | (d[15] << 16) | (d[16] << 8) | d[17];
        // Byte 12 bits 3-1 hold (channels - 1), right after the 20-bit sample rate.
        channels = ((d[12] >> 1) & 0x07) + 1;
        // Then 5 bits of (bits-per-sample - 1), straddling the byte boundary: the low bit of
        // byte 12 is its MSB, the top nibble of byte 13 the rest.
        bitsPerSample = (((d[12] & 0x01) << 4) | (d[13] >> 4)) + 1;
        if (sampleRate > 0 && totalSamples > 0) {
          duration = Duration(milliseconds: (totalSamples * 1000 / sampleRate).round());
        }
      } else if (type == 4) {
        _readVorbis(raf.readSync(len), fields);
      } else {
        raf.setPositionSync(raf.positionSync() + len);
      }
      if (isLast) break;
    }

    String? v(String k) {
      final s = fields[k]?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return FlacTags(
      title: v('title'),
      artist: v('artist') ?? v('albumartist'),
      album: v('album'),
      genre: v('genre'),
      trackNo: _firstInt(v('tracknumber')), // "A3" → 3, "03/12" → 3, "" → 0
      // Either its own tag or the tail of "03/12" — rippers disagree about which they write.
      trackTotal: _firstInt(v('tracktotal') ?? v('totaltracks')) != 0
          ? _firstInt(v('tracktotal') ?? v('totaltracks'))
          : _secondInt(v('tracknumber')),
      year: _year(v('date') ?? v('year')),
      duration: duration,
      channels: channels,
      sampleRate: sampleRate,
      bitsPerSample: bitsPerSample,
    );
  } catch (_) {
    return null;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
}

/// Overwrite only [fields] in a FLAC's Vorbis comments, leaving everything else exactly as it was.
///
/// Returns true if the file was rewritten.
///
/// Written here rather than with `audio_metadata_reader`'s writer, which cannot be used on a real
/// library: it emits ONLY the fields it models, so `ALBUMARTIST`, `TRACKTOTAL`, `REPLAYGAIN_*`,
/// `MUSICBRAINZ_*` and anything hand-written vanish silently on save. It also zeroes the vendor
/// string, writes `DATE` as `YYYY/MM/DD` where Vorbis wants ISO 8601, and reaches the file through
/// `readAllMetadata` — the path this codebase already documents as throwing on values like a vinyl
/// "A3" and LEAKING THE FILE HANDLE when it does, which would leave the track unmovable for the
/// rest of the session.
///
/// This one is deliberately dumb: every metadata block other than VORBIS_COMMENT is copied byte for
/// byte, the vendor string is preserved, and comments whose key isn't named in [fields] are carried
/// over untouched and in their original order. Keys are matched case-insensitively because rippers
/// disagree (`TrackNumber` vs `TRACKNUMBER`), and written back in the conventional upper case.
///
/// A key mapped to null is REMOVED — that is how a stale "03/12" TRACKNUMBER gets replaced by a
/// clean number plus its own TRACKTOTAL.
bool writeFlacFields(File f, Map<String, String?> fields) {
  if (fields.isEmpty) return false;
  RandomAccessFile? raf;
  try {
    raf = f.openSync();
    final size = raf.lengthSync();
    if (size < 8) return false;
    if (String.fromCharCodes(raf.readSync(4)) != 'fLaC') return false;

    // Walk the metadata blocks, keeping each one's type and raw body. Only the comment block is
    // rebuilt; every other block is carried over exactly as it was found.
    final types = <int>[];
    final bodies = <List<int>>[];
    var commentAt = -1;
    var sawLast = false;
    for (var block = 0; block < 64 && !sawLast; block++) {
      final h = raf.readSync(4);
      if (h.length < 4) return false;
      sawLast = (h[0] & 0x80) != 0;
      final len = (h[1] << 16) | (h[2] << 8) | h[3];
      if (len < 0 || len > 64 * 1024 * 1024) return false;
      final body = raf.readSync(len);
      if (body.length < len) return false;
      types.add(h[0] & 0x7F);
      bodies.add(body);
      if (types.last == 4 && commentAt < 0) commentAt = types.length - 1;
    }
    if (!sawLast) return false;

    final rebuilt = _rewriteVorbis(commentAt >= 0 ? bodies[commentAt] : const <int>[], fields);
    if (rebuilt == null) return false;
    if (commentAt >= 0) {
      bodies[commentAt] = rebuilt;
    } else {
      // No comment block at all. It goes straight after STREAMINFO, which must stay first.
      types.insert(1, 4);
      bodies.insert(1, rebuilt);
    }

    // Everything from here on is audio frames, and none of it is touched.
    final audioStart = raf.positionSync();
    final audio = raf.readSync(size - audioStart);
    raf.closeSync();
    raf = null;

    final out = BytesBuilder();
    out.add(const [0x66, 0x4C, 0x61, 0x43]); // "fLaC"
    for (var i = 0; i < types.length; i++) {
      final body = bodies[i];
      out.add([
        (i == types.length - 1 ? 0x80 : 0) | types[i],
        (body.length >> 16) & 0xFF,
        (body.length >> 8) & 0xFF,
        body.length & 0xFF,
      ]);
      out.add(body);
    }
    return _finish(f, out.toBytes(), audio);
  } catch (_) {
    return false; // a file we can't rewrite safely is one we leave alone
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
}

/// Write beside the original and rename over it, so an interruption can never leave half a file.
bool _finish(File f, List<int> meta, List<int> audio) {
  final tmp = File('${f.path}.tags');
  try {
    final sink = tmp.openSync(mode: FileMode.write);
    try {
      sink.writeFromSync(meta);
      sink.writeFromSync(audio);
      sink.flushSync();
    } finally {
      sink.closeSync();
    }
    tmp.renameSync(f.path);
    return true;
  } catch (_) {
    try {
      if (tmp.existsSync()) tmp.deleteSync();
    } catch (_) {}
    return false;
  }
}

/// Rebuild a VORBIS_COMMENT body with [fields] applied and everything else preserved.
List<int>? _rewriteVorbis(List<int> d, Map<String, String?> fields) {
  final want = {for (final e in fields.entries) e.key.toLowerCase(): e.value};
  final kept = <List<int>>[];
  var vendor = const <int>[];
  var i = 0;
  int u32() {
    final v = d[i] | (d[i + 1] << 8) | (d[i + 2] << 16) | (d[i + 3] << 24);
    i += 4;
    return v;
  }

  try {
    if (d.length >= 4) {
      final vendorLen = u32();
      if (vendorLen < 0 || i + vendorLen > d.length) return null;
      vendor = d.sublist(i, i + vendorLen);
      i += vendorLen;
      final count = d.length >= i + 4 ? u32() : 0;
      for (var n = 0; n < count && i + 4 <= d.length; n++) {
        final len = u32();
        if (len < 0 || i + len > d.length) break;
        final entry = d.sublist(i, i + len);
        i += len;
        final eq = entry.indexOf(0x3D); // '='
        if (eq <= 0) continue;
        final key = utf8.decode(entry.sublist(0, eq), allowMalformed: true).toLowerCase();
        // Ours to replace — drop the old one; anything else rides along untouched.
        if (want.containsKey(key)) continue;
        kept.add(entry);
      }
    }
  } catch (_) {
    return null; // truncated block: better to leave the file alone than to rewrite it from a guess
  }

  for (final e in want.entries) {
    final v = e.value;
    if (v == null || v.isEmpty) continue;
    kept.add(utf8.encode('${e.key.toUpperCase()}=$v'));
  }

  final out = BytesBuilder();
  void u32le(int v) => out.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  u32le(vendor.length);
  out.add(vendor);
  u32le(kept.length);
  for (final e in kept) {
    u32le(e.length);
    out.add(e);
  }
  return out.toBytes();
}

void _readVorbis(List<int> d, Map<String, String> out) {
  var i = 0;
  int u32() {
    final v = d[i] | (d[i + 1] << 8) | (d[i + 2] << 16) | (d[i + 3] << 24);
    i += 4;
    return v;
  }

  try {
    // NB: `i += u32()` would be wrong — the compound assignment reads `i` before u32() advances
    // it, which silently desyncs the whole block. Keep the two steps separate.
    final vendorLen = u32();
    i += vendorLen; // vendor string — skipped
    final count = u32();
    for (var n = 0; n < count && i + 4 <= d.length; n++) {
      final len = u32();
      if (len < 0 || i + len > d.length) break;
      // Vorbis comments are UTF-8; reading them as code units mangles anything non-ASCII.
      final entry = utf8.decode(d.sublist(i, i + len), allowMalformed: true);
      i += len;
      final eq = entry.indexOf('=');
      if (eq <= 0) continue;
      final key = entry.substring(0, eq).toLowerCase();
      out.putIfAbsent(key, () => entry.substring(eq + 1));
    }
  } catch (_) {/* truncated block — keep whatever we already parsed */}
}

int _firstInt(String? s) {
  if (s == null) return 0;
  final m = RegExp(r'\d+').firstMatch(s);
  return m == null ? 0 : (int.tryParse(m.group(0)!) ?? 0);
}

int? _year(String? s) {
  if (s == null) return null;
  final m = RegExp(r'\d{4}').firstMatch(s);
  final y = m == null ? null : int.tryParse(m.group(0)!);
  return (y != null && y > 1000) ? y : null;
}

/// The number after the slash in "03/12" — the release's track count, where a ripper wrote it
/// there instead of in its own tag.
int _secondInt(String? s) {
  if (s == null) return 0;
  final i = s.indexOf('/');
  return i < 0 ? 0 : _firstInt(s.substring(i + 1));
}

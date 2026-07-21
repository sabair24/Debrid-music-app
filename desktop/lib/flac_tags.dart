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
  final int? year;
  final Duration? duration;

  /// 2 for a normal stereo track, 6 for a 5.1 surround rip. Worth knowing: a surround mix is
  /// enormous and gets downmixed on a stereo system, so it must not beat a stereo master just
  /// because it carries more bits.
  final int channels;

  const FlacTags({
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.trackNo = 0,
    this.year,
    this.duration,
    this.channels = 0,
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
        final sampleRate = (d[10] << 12) | (d[11] << 4) | (d[12] >> 4);
        final totalSamples =
            ((d[13] & 0x0F) << 32) | (d[14] << 24) | (d[15] << 16) | (d[16] << 8) | d[17];
        // Byte 12 bits 3-1 hold (channels - 1), right after the 20-bit sample rate.
        channels = ((d[12] >> 1) & 0x07) + 1;
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
      year: _year(v('date') ?? v('year')),
      duration: duration,
      channels: channels,
    );
  } catch (_) {
    return null;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
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

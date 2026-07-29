/// Rewriting an MP3's ID3v2 tag without destroying what we did not put there.
///
/// The app refused to write MP3 tags at all until now, and that refusal was right for the writers on
/// offer. Measured on this library's ten MP3s, a wholesale rebuild — which is what every Dart tag
/// package appears to do, and none of them documents otherwise — would throw away:
///
/// * `APIC`  — the embedded cover, in five of the ten;
/// * `SERA`/`PLAY` — Serato's cue points and beat grids;
/// * `RVAD`/`RGAD` — ReplayGain, so everything plays at the wrong level afterwards;
/// * `SMPB`/`PGAP`/`NORM` — iTunes' gapless data;
/// * `UFID`, `PRIV`, `GEOB`, `TXXX` — whatever else a decade of tools has attached.
///
/// So this takes the same shape as [writeFlacFields]: deliberately dumb, byte-exact, and it REFUSES
/// rather than guesses. Every frame we are not asked to change is copied across untouched and in its
/// original order; the audio after the tag is never read, only appended; the result lands atomically
/// through a temporary file and a rename.
///
/// The refusals matter as much as the writes. Unsynchronisation, an extended header, and ID3v2.2 —
/// which has three-byte frame ids and a different header — are each a different layout, and a writer
/// that half-understands a layout is how a library gets quietly corrupted. Those files come back
/// `false` and the caller reports them by name, exactly as a file held open by the player does.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// What a caller may set, mapped from the app's own words to the ID3v2 frame that holds them.
///
/// Only the handful the app actually writes. Anything else in the file is somebody's, not ours.
const Map<String, String> kMp3Frames = {
  'TITLE': 'TIT2',
  'ARTIST': 'TPE1',
  'ALBUM': 'TALB',
  'ALBUMARTIST': 'TPE2',
  'TRACKNUMBER': 'TRCK',
  'DATE': 'TDRC', // v2.4 spelling; v2.3 uses TYER and is mapped below
};

/// Vorbis keeps the track number and the track total in two fields; ID3 keeps them in one, written
/// `6/18`. Callers speak Vorbis — [writeMp3Fields] and [readMp3RawFields] do the joining and the
/// splitting, so nothing above this file has to know which container it is talking to.
///
/// Without this, normalising an MP3 wrote the number and quietly dropped the total, which is exactly
/// the half-answer that made albums disagree about their own length in the first place.
const String kTrackTotal = 'TRACKTOTAL';

/// The v2.3 spelling for frames that were renamed in v2.4.
const Map<String, String> _v23 = {'TDRC': 'TYER'};

/// ID3v2.2 spells every frame in three letters. Not an abbreviation of the later names — a separate
/// vocabulary that has to be mapped, which is half the reason v2.2 was refused outright at first.
const Map<String, String> _v22 = {
  'TIT2': 'TT2',
  'TPE1': 'TP1',
  'TPE2': 'TP2',
  'TALB': 'TAL',
  'TRCK': 'TRK',
  'TDRC': 'TYE',
  'TYER': 'TYE',
};

/// The frame id this version uses for a v2.4-spelled name.
String _idFor(String id, int major) =>
    major == 2 ? (_v22[id] ?? id) : (major == 3 ? (_v23[id] ?? id) : id);

/// One ID3v2 tag, as far as we need to understand it.
class Id3Header {
  const Id3Header(this.major, this.revision, this.flags, this.size);

  /// 3 for v2.3.0, 4 for v2.4.0.
  final int major;
  final int revision;
  final int flags;

  /// Bytes of tag body AFTER the ten-byte header, padding included.
  final int size;

  bool get unsynchronised => flags & 0x80 != 0;

  /// Bit 6, and it does not mean the same thing in every version: an extended header in v2.3/v2.4,
  /// whole-tag COMPRESSION in v2.2 — where the spec simply says a reader should ignore the tag.
  /// Either way it is a layout this does not model, so either way it is a refusal.
  bool get awkward => flags & 0x40 != 0;

  /// Bytes of frame header: id + size (+ flags, which v2.2 does not have).
  int get frameHeaderSize => major == 2 ? 6 : 10;

  /// Letters in a frame id. Three in v2.2, four after.
  int get idSize => major == 2 ? 3 : 4;

  /// Can this file be rewritten safely at all?
  ///
  /// v2.2, v2.3 and v2.4, none of them carrying a flag whose layout is not modelled here. Anything
  /// else is a different format, and "probably close enough" is not a standard this file is written
  /// to — a writer that half-understands a layout is how a library gets quietly corrupted.
  bool get writable => major >= 2 && major <= 4 && !unsynchronised && !awkward;
}

/// Read the tag header, or null when the file does not start with one.
Id3Header? readId3Header(File f) {
  RandomAccessFile? raf;
  try {
    raf = f.openSync();
    final h = raf.readSync(10);
    if (h.length < 10) return null;
    if (h[0] != 0x49 || h[1] != 0x44 || h[2] != 0x33) return null; // "ID3"
    // A syncsafe integer: seven bits per byte, so no byte can look like an MPEG sync word.
    final size = ((h[6] & 0x7F) << 21) |
        ((h[7] & 0x7F) << 14) |
        ((h[8] & 0x7F) << 7) |
        (h[9] & 0x7F);
    return Id3Header(h[3], h[4], h[5], size);
  } catch (_) {
    return null;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
}

/// Every text frame in the tag, by frame id, as the app's own field names where it knows them.
///
/// Used to read the values back BEFORE a write so they can be undone — the same contract
/// `readFlacRawFields` has, and the reason a field that was absent must come back as absent.
Map<String, String?> readMp3RawFields(File f) {
  final out = <String, String?>{};
  final h = readId3Header(f);
  if (h == null || !h.writable) return out;
  try {
    final raf = f.openSync();
    Uint8List body;
    try {
      raf.setPositionSync(10);
      body = raf.readSync(h.size);
    } finally {
      raf.closeSync();
    }
    for (final fr in _frames(body, h.major)) {
      if (!fr.id.startsWith('T')) continue;
      final naam = kMp3Frames.entries
          .where((e) => _idFor(e.value, h.major) == fr.id)
          .map((e) => e.key)
          .firstOrNull;
      if (naam == null) continue;
      final waarde = _decodeText(body.sublist(fr.dataStart, fr.dataEnd));
      if (fr.id == _idFor('TRCK', h.major) && waarde != null && waarde.contains('/')) {
        final d = waarde.split('/');
        out['tracknumber'] = d[0].trim();
        out[kTrackTotal.toLowerCase()] = d[1].trim();
        continue;
      }
      out[naam.toLowerCase()] = waarde;
    }
  } catch (_) {/* an unreadable tag is not a reason to fail the caller */}
  return out;
}

class _Frame {
  const _Frame(this.id, this.start, this.dataStart, this.dataEnd);

  final String id;

  /// Where the ten-byte frame header begins, so the whole frame can be copied verbatim.
  final int start;
  final int dataStart, dataEnd;
}

/// Walk the frames of a tag body. Stops at padding (a zero byte where an id should be), at a frame
/// that runs past the end, or at anything that is not a plausible frame id — all three mean "the
/// rest of this is not something to reason about", and stopping is the safe answer.
List<_Frame> _frames(Uint8List body, int major) {
  final out = <_Frame>[];
  final idLen = major == 2 ? 3 : 4;
  final headLen = major == 2 ? 6 : 10;
  final b = body;
  var i = 0;
  while (i + headLen <= body.length) {
    if (b[i] == 0) break; // padding
    final id = String.fromCharCodes(b.sublist(i, i + idLen));
    if (!RegExp('^[A-Z0-9]{$idLen}\$').hasMatch(id)) break;
    // Three shapes, and getting them confused lands mid-frame with everything after it garbage:
    // v2.2 is three plain bytes, v2.3 four plain bytes, v2.4 four SYNCSAFE bytes. That last change
    // is the one implementations trip over, because a v2.4 size read as plain still looks like a
    // number.
    final int size;
    if (major == 2) {
      size = (b[i + 3] << 16) | (b[i + 4] << 8) | b[i + 5];
    } else if (major == 4) {
      size = ((b[i + 4] & 0x7F) << 21) |
          ((b[i + 5] & 0x7F) << 14) |
          ((b[i + 6] & 0x7F) << 7) |
          (b[i + 7] & 0x7F);
    } else {
      size = (b[i + 4] << 24) | (b[i + 5] << 16) | (b[i + 6] << 8) | b[i + 7];
    }
    if (size < 0 || i + headLen + size > body.length) break;
    out.add(_Frame(id, i, i + headLen, i + headLen + size));
    i += headLen + size;
  }
  return out;
}

/// Read a text frame's payload. Null when the encoding is one we do not model.
String? _decodeText(Uint8List data) {
  if (data.isEmpty) return null;
  final enc = data[0];
  final bytes = data.sublist(1);
  if (bytes.isEmpty) return '';
  try {
    // Decode FIRST, trim the terminator afterwards. Stripping trailing zero BYTES before decoding is
    // wrong for UTF-16 and wrong in a way that hides itself: "Voodoo" ends in 6F 00, so eating the
    // zeros takes half of the final 'o', leaves an odd number of bytes, and the last character
    // silently disappears. Measured on the real files — every value came back one letter short,
    // "Nunca Feat. Pat Krimso", "202" — which reads like a truncated tag rather than a decoder bug.
    final String s;
    switch (enc) {
      case 0: // ISO-8859-1
        s = String.fromCharCodes(bytes);
      case 1: // UTF-16 with BOM
        s = _utf16(bytes);
      case 2: // UTF-16BE, no BOM (v2.4)
        s = _utf16(bytes, bigEndian: true, hasBom: false);
      case 3: // UTF-8 (v2.4)
        s = utf8.decode(bytes, allowMalformed: true);
      default:
        return null;
    }
    var end = s.length;
    while (end > 0 && s.codeUnitAt(end - 1) == 0) {
      end--;
    }
    return s.substring(0, end);
  } catch (_) {}
  return null;
}

String _utf16(Uint8List b, {bool bigEndian = false, bool hasBom = true}) {
  var i = 0;
  var be = bigEndian;
  if (hasBom && b.length >= 2) {
    if (b[0] == 0xFF && b[1] == 0xFE) {
      be = false;
      i = 2;
    } else if (b[0] == 0xFE && b[1] == 0xFF) {
      be = true;
      i = 2;
    }
  }
  final units = <int>[];
  for (; i + 1 < b.length; i += 2) {
    units.add(be ? (b[i] << 8) | b[i + 1] : (b[i + 1] << 8) | b[i]);
  }
  return String.fromCharCodes(units);
}

/// Build a text frame's payload, choosing the narrowest encoding that can carry [text].
///
/// ISO-8859-1 where it fits, because it is the one encoding every player since 1998 reads. Only when
/// the text needs more does this reach for UTF-16 with a BOM (v2.3) or UTF-8 (v2.4) — Dutch titles
/// with a "ë" are common enough here that getting this wrong would be visible immediately.
Uint8List _encodeText(String text, int major) {
  final latin1Fits = text.codeUnits.every((c) => c <= 0xFF);
  if (latin1Fits) {
    return Uint8List.fromList([0, ...text.codeUnits, 0]);
  }
  if (major == 4) {
    return Uint8List.fromList([3, ...utf8.encode(text), 0]);
  }
  final out = <int>[1, 0xFF, 0xFE];
  for (final u in text.codeUnits) {
    out..add(u & 0xFF)..add(u >> 8);
  }
  out..add(0)..add(0);
  return Uint8List.fromList(out);
}

/// Does Windows have this file marked read-only? False everywhere else, and false when we cannot
/// tell — a guess here would turn a real error into a misleading one.
bool _readOnly(File f) {
  if (!Platform.isWindows) return false;
  try {
    final r = Process.runSync('cmd', ['/c', 'attrib', f.path]);
    final out = '${r.stdout}';
    // attrib prints the flags before the path: "A  R   C:\...".
    final i = out.toUpperCase().indexOf(f.path.toUpperCase());
    return i > 0 && out.substring(0, i).contains('R');
  } catch (_) {
    return false;
  }
}

Uint8List _frameHeader(String id, int size, int major) {
  if (major == 2) {
    // Six bytes: three letters, three size bytes, and no flags at all.
    final b = Uint8List(6);
    b.setRange(0, 3, id.codeUnits);
    b[3] = (size >> 16) & 0xFF;
    b[4] = (size >> 8) & 0xFF;
    b[5] = size & 0xFF;
    return b;
  }
  final b = Uint8List(10);
  b.setRange(0, 4, id.codeUnits);
  if (major == 4) {
    b[4] = (size >> 21) & 0x7F;
    b[5] = (size >> 14) & 0x7F;
    b[6] = (size >> 7) & 0x7F;
    b[7] = size & 0x7F;
  } else {
    b[4] = (size >> 24) & 0xFF;
    b[5] = (size >> 16) & 0xFF;
    b[6] = (size >> 8) & 0xFF;
    b[7] = size & 0xFF;
  }
  return b;
}

/// Overwrite only [fields] in an MP3's ID3v2 tag, leaving every other frame exactly as it was.
///
/// Keys are the app's own names (`ARTIST`, `TITLE`, …); a key mapped to null removes that frame.
/// Returns false — and changes nothing — when the file has no ID3v2 tag, uses a layout this does not
/// fully model, or cannot be replaced because something else holds it open.
/// Why a write did not happen, when a caller wants to know.
///
/// Every silent `catch` in this session turned out to be hiding something worth reading, so this one
/// has a way out from the start rather than after an evening of guessing.
bool writeMp3Fields(File f, Map<String, String?> fields, {void Function(String)? trace}) {
  final h = readId3Header(f);
  if (h == null) {
    trace?.call('geen ID3v2-kop');
    return false;
  }
  if (!h.writable) {
    trace?.call('v2.${h.major} vlaggen=0x${h.flags.toRadixString(16)} — niet volledig gemodelleerd');
    return false;
  }

  final wanted = <String, String?>{};
  for (final e in fields.entries) {
    final id = kMp3Frames[e.key.toUpperCase()];
    if (id == null) continue;
    wanted[_idFor(id, h.major)] = e.value;
  }
  // Join the number and the total the way ID3 wants them. The total on its own is not a frame, so a
  // caller that sets only TRACKTOTAL needs the number the file already carries to write it at all.
  final totaalGevraagd = fields.keys.any((k) => k.toUpperCase() == kTrackTotal);
  if (totaalGevraagd) {
    final totaal = fields.entries.firstWhere((e) => e.key.toUpperCase() == kTrackTotal).value;
    final trck = _idFor('TRCK', h.major);
    final nummer = wanted.containsKey(trck)
        ? wanted[trck]
        : readMp3RawFields(f)['tracknumber'];
    wanted[trck] = (nummer == null || nummer.isEmpty)
        ? null
        : (totaal == null || totaal.isEmpty) ? nummer : '$nummer/$totaal';
  }
  if (wanted.isEmpty) {
    trace?.call('geen van de gevraagde velden hoort bij een frame dat we schrijven');
    return false;
  }

  RandomAccessFile? raf;
  try {
    raf = f.openSync();
    raf.setPositionSync(10);
    final body = raf.readSync(h.size);
    final audio = raf.readSync(raf.lengthSync() - 10 - h.size);
    raf.closeSync();
    raf = null;

    final out = BytesBuilder();
    final done = <String>{};
    for (final fr in _frames(body, h.major)) {
      if (wanted.containsKey(fr.id)) {
        done.add(fr.id);
        final v = wanted[fr.id];
        if (v == null || v.isEmpty) continue; // removed
        final data = _encodeText(v, h.major);
        out..add(_frameHeader(fr.id, data.length, h.major))..add(data);
        continue;
      }
      // Everything else, byte for byte, header included — cue points, artwork, the lot.
      out.add(body.sublist(fr.start, fr.dataEnd));
    }
    // Frames the file did not have yet.
    for (final e in wanted.entries) {
      if (done.contains(e.key)) continue;
      final v = e.value;
      if (v == null || v.isEmpty) continue;
      final data = _encodeText(v, h.major);
      out..add(_frameHeader(e.key, data.length, h.major))..add(data);
    }

    // A little padding, so the NEXT edit can often be done without moving the audio at all — which
    // is the whole reason the format allows it.
    final frames = out.toBytes();
    const padding = 1024;
    final newSize = frames.length + padding;

    final tmp = File('${f.path}.dmtmp');
    final w = tmp.openSync(mode: FileMode.write);
    try {
      final head = Uint8List(10);
      head.setRange(0, 3, 'ID3'.codeUnits);
      head[3] = h.major;
      head[4] = h.revision;
      head[5] = 0; // no unsynchronisation, no extended header — we only got here because there were none
      head[6] = (newSize >> 21) & 0x7F;
      head[7] = (newSize >> 14) & 0x7F;
      head[8] = (newSize >> 7) & 0x7F;
      head[9] = newSize & 0x7F;
      w..writeFromSync(head)..writeFromSync(frames)..writeFromSync(Uint8List(padding))..writeFromSync(audio);
    } finally {
      w.closeSync();
    }
    // Rename over the original. Fails when the player holds the file, which is the case the caller
    // reports by name rather than counting as success.
    tmp.renameSync(f.path);
    return true;
  } catch (e) {
    // "Access denied" on the rename has two very different causes and the message does not say
    // which. One of this library's ten mp3s carries the Windows read-only attribute, and a rename
    // over a read-only file fails exactly like a rename over a file the player is holding. Telling
    // them apart is the difference between "close the player" and "clear the read-only tick", and
    // the app is not going to flip a flag the user set.
    if (e is PathAccessException && _readOnly(f)) {
      trace?.call('het bestand staat op alleen-lezen');
    } else {
      trace?.call('$e');
    }
    try {
      final tmp = File('${f.path}.dmtmp');
      if (tmp.existsSync()) tmp.deleteSync();
    } catch (_) {}
    return false;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
}

import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Stable, content-free ids, so a rescan produces the same id for the same file.
///
/// Same scheme as the Kotlin server's `server/src/main/kotlin/com/debridmusic/server/util/Ids.kt`
/// — SHA-256 of `"kind:value"`, first 12 bytes as hex. Keeping the scheme is not cosmetic: the
/// Android/TV client stores these ids on its own rows, and a favourite or a playlist entry that
/// points at an id nobody issues any more is simply lost.
String idOf(String kind, String value) {
  final digest = sha256.convert(utf8.encode('$kind:${value.toLowerCase().trim()}'));
  return digest.bytes.take(12).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// A file's identity: its path RELATIVE to the music root, with separators normalised.
///
/// Relative on purpose. The absolute path carries the drive letter and the root folder's name,
/// so moving the library from `D:\Flac music 2024` to `E:\Music` — or serving it from a second
/// machine — would re-issue every id and detach every favourite from its track.
String trackIdFor(String path, String root) => idOf('track', relPathOf(path, root));

/// [path] relative to [root], forward-slashed. Falls back to the file name when the path lies
/// outside the root (a track added from elsewhere), which is still stable for that file.
String relPathOf(String path, String root) {
  final p = path.replaceAll('\\', '/');
  final r = root.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  if (r.isNotEmpty && p.toLowerCase().startsWith('${r.toLowerCase()}/')) {
    return p.substring(r.length + 1);
  }
  return p.split('/').last;
}

/// An album's identity. The edition is part of it: a record the library had to split into two
/// pressings is two albums to every client, and they must not collide on one id.
String albumIdFor(String artistKey, String normTitle, String? edition) =>
    idOf('album', '$artistKey|$normTitle|${edition ?? ''}');

String artistIdFor(String artistKey) => idOf('artist', artistKey);

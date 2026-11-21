import 'dart:convert';
import 'package:crypto/crypto.dart';

import '../verzameling.dart' show relZonderVerzameling;

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
///
/// Een bestand dat naar een verzameling verhuisde, houdt zijn id: het pad telt zonder het stuk van de verzameling
/// ([relZonderVerzameling], verzameling.dart). Anders raakten je favorieten, lijsten en wat je draaide los.
String trackIdFor(String path, String root) => idOf('track', relZonderVerzameling(relPathOf(path, root)));

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
///
/// [verzameling]: hetzelfde album in een verzameling is een ander album dan dat in je bibliotheek — anders voegt een
/// toestel ze weer samen (het groepeert op dit id). Zonder verzameling blijft elk id wat het was.
String albumIdFor(String artistKey, String normTitle, String? edition, {String? verzameling}) =>
    idOf('album', '$artistKey|$normTitle|${edition ?? ''}${verzameling == null ? '' : '|v:${verzameling.toLowerCase()}'}');

String artistIdFor(String artistKey) => idOf('artist', artistKey);

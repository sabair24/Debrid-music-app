import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/metadata.dart';
import 'package:debridmusic/settings.dart';

void main() {
  test('Deezer album search returns cover+artist', () async {
    final r = await MetadataSearch(AppSettings()).search('Deezer', 'Michael Jackson Bad');
    print('Deezer albums: ${r.length}');
    for (final m in r.take(3)) {
      print('  ${m.artist} — ${m.album}  cover=${m.coverUrl != null}');
    }
    expect(r.isNotEmpty, true);
    expect(r.first.coverUrl != null, true);
  });

  test('Deezer track search (for a single) returns artist+album', () async {
    final r = await MetadataSearch(AppSettings()).search('Deezer', 'Voodoo Radio Mix', track: true);
    print('Deezer tracks for "Voodoo": ${r.length}');
    for (final m in r.take(6)) {
      print('  ${m.artist} — ${m.title}  (album=${m.album}, cover=${m.coverUrl != null})');
    }
    expect(r.isNotEmpty, true);
  });

  test('MusicBrainz search returns releases', () async {
    final r = await MetadataSearch(AppSettings()).search('MusicBrainz', 'Daft Punk Discovery');
    print('MusicBrainz: ${r.length}; first=${r.isEmpty ? "-" : "${r.first.artist} — ${r.first.album}"}');
    expect(r.isNotEmpty, true);
  });
}

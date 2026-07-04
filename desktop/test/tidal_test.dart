// Unit-tests the TIDAL JSON:API track parser + config flags. The live OAuth login
// can't run headless (it opens the browser), so it's verified in the app by the user.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/tidal.dart';
import 'package:debridmusic/settings.dart';

void main() {
  test('config flags + redirect uri', () {
    final s = AppSettings();
    final t = TidalService(s);
    expect(t.configured, false);
    expect(t.connected, false);
    expect(TidalService.redirectUri, 'http://localhost:8971/tidal/callback');
    s.tidalClientId = 'abc';
    expect(TidalService(s).configured, true);
  });

  test('parseTracks maps title + primary artist from JSON:API', () {
    final json = jsonDecode('''
    {
      "data": {"id":"q","type":"searchResults",
        "relationships":{"tracks":{"data":[{"id":"t1","type":"tracks"},{"id":"t2","type":"tracks"}]}}},
      "included": [
        {"id":"t1","type":"tracks","attributes":{"title":"Billie Jean"},
          "relationships":{"artists":{"data":[{"id":"a1","type":"artists"}]}}},
        {"id":"t2","type":"tracks","attributes":{"title":"Thriller"},
          "relationships":{"artists":{"data":[{"id":"a1","type":"artists"}]}}},
        {"id":"a1","type":"artists","attributes":{"name":"Michael Jackson"}}
      ]
    }''') as Map<String, dynamic>;
    final tracks = TidalService.parseTracks(json);
    expect(tracks.length, 2);
    expect(tracks[0].title, 'Billie Jean');
    expect(tracks[0].artist, 'Michael Jackson');
    expect(tracks[0].sourceQuery, 'Michael Jackson Billie Jean');
    expect(tracks[1].title, 'Thriller');
  });

  test('parseTracks tolerates missing artist / empty include', () {
    expect(TidalService.parseTracks({'data': {}}).length, 0);
    final noArtist = jsonDecode('{"included":[{"id":"t1","type":"tracks","attributes":{"title":"Solo"}}]}') as Map<String, dynamic>;
    final t = TidalService.parseTracks(noArtist);
    expect(t.length, 1);
    expect(t[0].artist, '');
    expect(t[0].sourceQuery, 'Solo');
  });
}

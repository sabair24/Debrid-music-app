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
    // Moet letterlijk overeenkomen met wat er in het TIDAL-dashboard bij Redirect URIs staat, en
    // het moet https zijn: naar een eigen adresschema (debridmusic://) stuurt de inlogdienst niet
    // door. Hij logt je dan in, toont "Login successful" en dat is het — geen foutmelding, geen
    // code, en aan onze kant een knop die eeuwig draait. Vandaar dat dit vastligt.
    expect(TidalService.redirectUri, 'https://www.tidal.com');
    expect(TidalService.redirectUri, startsWith('https://'));
    s.tidalClientId = 'abc';
    expect(TidalService(s).configured, true);
  });

  test('extractCode from callback url / bare code', () {
    // Dit is werkelijk wat er in de adresbalk staat als het gelukt is: tidal.com met de code als
    // vraagteken-stuk. De code zelf is een JWT en zit dus vol punten en streepjes.
    expect(TidalService.extractCode('https://tidal.com/?code=eyJhbGc.eyJ1aWQ.sHWC-3bN_f0&state=R3F7'),
        'eyJhbGc.eyJ1aWQ.sHWC-3bN_f0');
    expect(TidalService.extractCode('"https://tidal.com/?code=ABC123&state=x"'), 'ABC123');
    expect(TidalService.extractCode('https://www.tidal.com/?code=XYZ'), 'XYZ');
    expect(TidalService.extractCode('ABC123'), 'ABC123');
    expect(TidalService.extractCode('https://tidal.com/'), null, reason: 'geen code erin');
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

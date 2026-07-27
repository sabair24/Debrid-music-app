// Een query hoort in de query, niet in het pad.
//
// `_api` bouwt de URL met `baseUrl.replace(path: path)`, en Dart percent-encodeert een `?` die in een
// pad staat. Eén aanroep gaf zijn parameters mee als deel van het pad, dus de pc kreeg
// `/api/cast/status%3FdeviceId=…` binnen. Die route bestaat niet, hij antwoordde 404, en de catch
// maakte daar `null` van — precies hetzelfde antwoord als "de speaker gaf geen status". Gevolg: op
// een Mac, iPad of telefoon die naar een speaker cast waren er nooit positie, volume of speelstatus,
// en de bediening leek dood.
//
// Deze test bewijst wat Dart doet, en houdt de bouwer eraan.
import 'package:flutter_test/flutter_test.dart';

/// Hetzelfde als LanClient._api, zodat de regel getest kan worden zonder een pc aan de andere kant.
Uri api(Uri base, String path, [Map<String, String>? query]) =>
    base.replace(path: path, queryParameters: query);

void main() {
  final base = Uri.parse('http://192.168.0.10:8080');

  test('een ? in het pad wordt geen scheiding maar tekst', () {
    final u = api(base, '/api/cast/status?deviceId=abc&volume=1');
    expect(u.path, contains('%3F'), reason: 'dit is de fout, zwart op wit');
    expect(u.queryParameters, isEmpty, reason: 'de server ziet geen enkele parameter');
    expect(u.path, isNot('/api/cast/status'), reason: 'dus matcht de route niet en volgt een 404');
  });

  test('via query komt alles op de juiste plek', () {
    final u = api(base, '/api/cast/status', {'deviceId': 'abc', 'volume': '1'});
    expect(u.path, '/api/cast/status');
    expect(u.queryParameters, {'deviceId': 'abc', 'volume': '1'});
    expect(u.toString(), isNot(contains('%3F')));
  });

  test('een apparaat-id met tekens die geëncodeerd moeten worden overleeft de reis', () {
    // UPnP-id's bevatten dubbele punten en schuine strepen.
    const id = 'uuid:5f9ec1b3-ed59/RenderingControl';
    final u = api(base, '/api/cast/status', {'deviceId': id});
    expect(u.queryParameters['deviceId'], id,
        reason: 'de bouwer encodeert en de ontvanger decodeert; het id komt heel aan');
  });

  test('zonder volume blijft de parameter weg in plaats van leeg', () {
    final u = api(base, '/api/cast/status', {'deviceId': 'abc'});
    expect(u.queryParameters.containsKey('volume'), isFalse);
  });

  test('een pad zonder query blijft ongemoeid', () {
    expect(api(base, '/api/catalog').toString(), 'http://192.168.0.10:8080/api/catalog');
  });
}

/// De knop "Sleutel proberen" naast de AI-sleutel, en vooral: wat hij ZEGT.
///
/// **Waarom dit bestaat.** Saber op 12-09-2026, met een schermafdruk van zijn Anthropic-console
/// erbij: *"maar ik heb nog maar een nieuwe gemaakt net ????"*. De sleutel in de app eindigde op
/// `UwAA`, de enige sleutel in zijn Console op `mgAA`. Een oude, verwijderde sleutel dus — en het
/// enige wat de app daarover zei was, diep in een radio, "wordt niet geaccepteerd". Welke sleutel
/// er geprobeerd werd stond nergens, en dat verschil was alleen te vinden door het bestand op
/// schijf naast de Console te leggen.
///
/// Daarom gaan deze toetsen niet over "werkt de aanroep" maar over de ZIN die eruit komt: die moet
/// altijd de laatste vier tekens noemen, want dat is het enige waarmee je hem naast je Console kunt
/// leggen.
library;

import 'package:debridmusic/ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Een sleutel met een herkenbare staart, zoals de Console hem toont.
const _sleutel = 'sk-ant-api03-verzonnen-maar-goed-gevormd-UwAA';

void main() {
  test('DE KERN: een werkende sleutel meldt dat, met zijn laatste vier tekens', () async {
    final ai = AiService(() => _sleutel,
        client: MockClient((_) async => http.Response(
            '{"content":[{"type":"text","text":"ok"}],"stop_reason":"end_turn"}', 200)));

    final uit = await ai.proef();

    expect(uit.ok, isTrue);
    expect(uit.reden, contains('…UwAA'),
        reason: 'zonder de staart kun je hem niet naast je Console leggen');
  });

  test('DE KERN: een geweigerde sleutel noemt zijn staart en wijst naar de Console', () async {
    var verzoeken = 0;
    final ai = AiService(() => _sleutel, client: MockClient((_) async {
      verzoeken++;
      return http.Response(
          '{"type":"error","error":{"type":"authentication_error","message":"API key is invalid."}}',
          401);
    }));

    final uit = await ai.proef();

    expect(verzoeken, 1);
    expect(uit.ok, isFalse);
    expect(uit.reden, contains('…UwAA'));
    expect(uit.reden.toLowerCase(), contains('console'),
        reason: 'dit is precies het geval waarin je in de Console moet kijken');
  });

  test('DE VAL: een leeg veld kost geen verzoek', () async {
    var verzoeken = 0;
    final ai = AiService(() => '   ', client: MockClient((_) async {
      verzoeken++;
      return http.Response('{}', 200);
    }));

    final uit = await ai.proef();

    expect(uit.ok, isFalse);
    expect(verzoeken, 0, reason: 'niets versturen als er niets in het veld staat');
    expect(uit.reden, contains('nog geen sleutel'),
        reason: '"ziet er niet uit als een sleutel" is verwarrend als het veld gewoon leeg is');
  });

  test('DE GRENS: iets wat geen Anthropic-sleutel is wordt herkend zonder verzoek', () async {
    // Een gekopieerde Discogs- of TorBox-sleutel in het verkeerde veld: dat hoeft Anthropic niet
    // te beoordelen.
    var verzoeken = 0;
    final ai = AiService(() => 'zomaar-iets-1234', client: MockClient((_) async {
      verzoeken++;
      return http.Response('{}', 200);
    }));

    final uit = await ai.proef();

    expect(uit.ok, isFalse);
    expect(uit.reden, contains('sk-ant-'));
    expect(verzoeken, 0);
  });
}

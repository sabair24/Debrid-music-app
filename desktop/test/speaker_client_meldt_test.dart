// De speakerknop in de spelerbalk verscheen na een koude start niet (Shield, 19-10-2026, proef b12071):
// de koppeling met de pc kwam een tel na het eerste beeld, en `SpeakerTarget.client` was een kaal veld
// dat niemand liet weten dat hij er nu wel was. Nu Speelt (later gebouwd) had de knop wel.
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/speakers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

RemoteClient _pc() => RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://127.0.0.1:1'), token: 'x'));

void main() {
  test('een nieuwe client meldt zich; dezelfde nog eens niet', () {
    final s = SpeakerTarget();
    var meldingen = 0;
    s.addListener(() => meldingen++);
    final c = _pc();
    s.client = c;
    expect(meldingen, 1);
    s.client = c;
    expect(meldingen, 1, reason: 'de sessie zet hem bij elke wissel opnieuw; dat hoeft niet te herbouwen');
    s.client = null;
    expect(meldingen, 2);
  });

  testWidgets('DE KERN: een knop die met watch kijkt, verschijnt als de koppeling later komt', (t) async {
    final s = SpeakerTarget();
    await t.pumpWidget(ChangeNotifierProvider<SpeakerTarget>.value(
      value: s,
      child: MaterialApp(
        home: Builder(
          builder: (context) => context.watch<SpeakerTarget>().client == null
              ? const SizedBox.shrink()
              : const Icon(Icons.speaker_group_rounded),
        ),
      ),
    ));
    expect(find.byIcon(Icons.speaker_group_rounded), findsNothing);
    // De koppeling komt na het eerste beeld (zie main.dart: `speakers.client = library.remote` in de
    // luisteraar van de sessie).
    s.client = _pc();
    await t.pump();
    expect(find.byIcon(Icons.speaker_group_rounded), findsOneWidget);
  });
}

// Een AI-lijst natrekken (Saber, 23-11-2026): eerst je eigen bibliotheek, dan Deezer, dan iTunes; wat niemand kent wordt
// "niet gevonden, misschien verzonnen". Met hoes, lengte en een fragment van 30 s, voor er iets gedownload wordt.
import 'package:debridmusic/ai_lijst.dart';
import 'package:debridmusic/ai_lijst_natrekken.dart';
import 'package:debridmusic/aanbevolen.dart' show recTrackNaarJson, recTrackUitJson;
import 'package:debridmusic/recommend.dart' show RecTrack;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DE KERN: eigen eerst, dan Deezer (met id en fragment), dan iTunes; niemand = nergens', () async {
    final nummers = [
      LijstNummer(artiest: 'Bing Crosby', titel: 'White Christmas'),
      LijstNummer(artiest: 'Mariah Carey', titel: 'All I Want for Christmas Is You'),
      LijstNummer(artiest: 'Plaza', titel: 'Yo-Yo'),
      LijstNummer(artiest: 'Verzonnen Artiest', titel: 'Bestaat Niet'),
    ];
    final eigen = eigenIndex([(artiest: 'Bing Crosby', titel: 'White Christmas (Remastered)', id: 'eigen1')]);
    var stappen = 0;
    List<String>? gevraagd;
    await trekLijstNa(nummers, eigenId: eigen, bijVoortgang: () => stappen++, trekNa: (lijst, voortgang) async {
      gevraagd = [for (final n in lijst) n.titel];
      final uit = <RecTrack?>[
        const RecTrack('Mariah Carey', 'All I Want for Christmas Is You', 'https://deezer/c.jpg',
            album: 'Merry Christmas', seconds: 241, deezerId: 7, preview: 'https://deezer/p.mp3'),
        const RecTrack('Plaza', 'Yo-Yo', 'https://itunes/c.jpg', seconds: 200, preview: 'https://itunes/p.m4a'),
        null,
      ];
      voortgang(3, uit);
      return uit;
    });
    expect(gevraagd, ['All I Want for Christmas Is You', 'Yo-Yo', 'Bestaat Niet'], reason: 'wat je hebt, wordt niet opgezocht');
    expect((nummers[0].bron, nummers[0].eigenId), (LijstBron.eigen, 'eigen1'), reason: 'remaster telt als hetzelfde nummer');
    expect((nummers[1].bron, nummers[1].deezerId, nummers[1].fragment, nummers[1].seconden, nummers[1].album),
        (LijstBron.deezer, 7, 'https://deezer/p.mp3', 241, 'Merry Christmas'));
    expect((nummers[2].bron, nummers[2].fragment), (LijstBron.itunes, 'https://itunes/p.m4a'));
    expect(nummers[3].bron, LijstBron.nergens);
    expect(stappen, greaterThanOrEqualTo(3), reason: 'de lijst vult zich terwijl je kijkt');
  });

  test('tussendoor blijft wat nog niet klaar is "bezig", geen voortijdig "nergens"', () async {
    final nummers = [LijstNummer(artiest: 'A', titel: 'x'), LijstNummer(artiest: 'B', titel: 'y')];
    final tussen = <LijstBron>[];
    await trekLijstNa(nummers, eigenId: (_, __) => null, trekNa: (lijst, voortgang) async {
      voortgang(1, [const RecTrack('A', 'x', null, deezerId: 1), null]);
      tussen.addAll(nummers.map((n) => n.bron));
      return [const RecTrack('A', 'x', null, deezerId: 1), null];
    });
    expect(tussen, [LijstBron.deezer, LijstBron.bezig]);
    expect(nummers[1].bron, LijstBron.nergens);
  });

  test('wat al nagetrokken is, gaat niet nog eens', () async {
    final nummers = [LijstNummer(artiest: 'A', titel: 'x', bron: LijstBron.deezer)];
    var gevraagd = false;
    await trekLijstNa(nummers, eigenId: (_, __) => null, trekNa: (lijst, voortgang) async {
      gevraagd = true;
      return [];
    });
    expect(gevraagd, isFalse);
  });

  test('Ontdek naar het toestel: het Deezer-id en het fragment gaan mee', () {
    final t = recTrackUitJson(recTrackNaarJson(
        const RecTrack('Metejoor', 'Wie ga ik zijn', null, seconds: 208, deezerId: 99, preview: 'https://deezer/p.mp3')))!;
    expect((t.deezerId, t.preview, t.seconds), (99, 'https://deezer/p.mp3', 208));
    expect(recTrackUitJson(recTrackNaarJson(const RecTrack('A', 'B', null)))!.preview, isNull);
  });
}

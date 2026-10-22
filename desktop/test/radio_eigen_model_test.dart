// Wat het model noemt en Deezer niet kent, maar jij wél hebt, speelt mee. Gemeten op 22-10-2026, radio vanaf Petra —
// Ik Leef Voor Jou: het model noemde "Plaza — Yo Yo" (Sabers eigen voorbeeld: "yo yo van plaza past hier ook perfect
// bij"), en die viel af als "niet gevonden" terwijl "Yo-Yo (Dance Version)" in zijn bibliotheek staat.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/models.dart' show Track;
import 'package:debridmusic/radiolijst.dart';
import 'package:debridmusic/recommend.dart';

Track _t(String artiest, String titel, {int seconden = 230}) => Track(
  path: 'C:/m/$artiest - $titel.mp3',
  title: titel,
  artist: artiest,
  album: '',
  duration: Duration(seconds: seconden),
);

void main() {
  group('uit je eigen bibliotheek', () {
    test('DE KERN: "Plaza — Yo Yo" vindt "Yo-Yo (Dance Version)", met jouw titel en lengte', () {
      final vind = eigenVoorModel([
        _t('Plaza', 'Yo-Yo (Dance Version)', seconden: 241),
        _t('Petra', 'Ik Leef Voor Jou'),
      ]);
      final r = vind(AiNummer('Plaza', 'Yo Yo'))!;
      expect((r.artist, r.title, r.seconds), ('Plaza', 'Yo-Yo (Dance Version)', 241));
      expect(vind(AiNummer('Plaza', 'Love You Again')), isNull);
      expect(vind(AiNummer('Plazaa', 'Yo Yo')), isNull, reason: 'een andere artiest is een ander nummer');
    });

    test('het origineel liever dan een bewerking; nooit wat niet op de radio hoort', () {
      final vind = eigenVoorModel([
        _t('Get Ready!', 'Diep (Remix)'),
        _t('Get Ready!', 'Diep'),
        _t('Get Ready!', 'Dromen (Karaoke Version)'),
      ]);
      expect(vind(AiNummer('Get Ready!', 'Diep'))!.title, 'Diep');
      expect(vind(AiNummer('Get Ready!', 'Dromen')), isNull, reason: 'een karaokeversie speelt de radio nooit');
    });
  });

  group('lijstOpDeezer', () {
    RecommendService deezer() => RecommendService(adem: Duration.zero, haal: (url) async => {'data': <Object>[]});

    test('DE KERN: niet op Deezer maar wel van jou telt mee, en het logboek zegt het', () async {
      final log = <String>[];
      final uit = await deezer().lijstOpDeezer(
        [AiNummer('Plaza', 'Yo Yo'), AiNummer('Bart Kaëll', 'Viva Hollandia')],
        spoor: log.add,
        vanJou: eigenVoorModel([_t('Plaza', 'Yo-Yo (Dance Version)')]),
      );
      expect([for (final t in uit) t.title], ['Yo-Yo (Dance Version)']);
      expect(log.last, contains('niet op Deezer, wel van jou: Plaza — Yo-Yo (Dance Version)'));
      expect(log.last, contains('niet gevonden: Bart Kaëll — Viva Hollandia'));
    });

    test('zonder opzoeker zoals voorheen', () async {
      final log = <String>[];
      expect(await deezer().lijstOpDeezer([AiNummer('Plaza', 'Yo Yo')], spoor: log.add), isEmpty);
      expect(log.last, contains('niet gevonden: Plaza — Yo Yo'));
    });

    test('aangesloten: alle vier de plekken waar de radio een lijst namen opzoekt, kijken ook bij jou', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(
        'vanJou: eigenVoorModel(lib.tracks)'.allMatches(main).length,
        5,
        reason: 'de startlijst, de vervolglijst, het afstemmen, Last.fm bij de start en Last.fm onderweg',
      );
      // Twee zonder, met reden: de rij "Vroeger veel gespeeld, nog niet van jou" zoekt per definitie wat je níét hebt,
      // en de genretag van een radio uit een zin gaat daarna door `_radioplan`, die je eigen exemplaar al vindt.
      expect(RegExp(r'lijstOpDeezer\(').allMatches(main).length, 7, reason: 'geen achtste zonder opzoeker');
      expect(main, contains("van: 'je Last.fm');"));
    });
  });
}

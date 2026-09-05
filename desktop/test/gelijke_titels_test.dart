/// Twee rijen met dezelfde titel: welke is welke?
///
/// **Gemeld op 05-09-2026 met Christina Milians *Dip It Low (Mixes)*.** Twee nummers, allebei
/// "Dip It Low", allebei getagd als "Christina Milian" — terwijl de plaat rij 2 als *feat. Fabolous*
/// uitgeeft. Saber: *"ik krijg het maar niet goed e, de ene moet dip it low zijn, de ander dip it
/// low feat fabulous."*
///
/// Het verrassende deel: de bestanden stonden al op de JUISTE rij. De looptijden beslisten dat
/// (3:14 tegen 3:18, 3:38 tegen 3:40), en de toewijzing is eenduidig in beide bestandsvolgordes.
/// Wat ontbrak was elke manier om dat op het scherm te zien.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/completeness.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/organize.dart';

/// De echte tracklijst zoals de app hem in album_facts.json heeft staan — zonder credits.
const kaal = [
  ChoiceTrack('1', 'Dip It Low', 198),
  ChoiceTrack('2', 'Dip It Low', 220),
];

/// Dezelfde persing bij MusicBrainz (GB, barcode 602498624852) — mét credits.
const metCredit = [
  ChoiceTrack('1', 'Dip It Low', 198, artist: 'Christina Milian'),
  ChoiceTrack('2', 'Dip It Low', 220, artist: 'Christina Milian feat. Fabolous'),
];

Track bestand(String naam, int ms) => Track(
      path: 'D:\\m\\$naam.flac',
      title: 'Dip It Low',
      artist: 'Christina Milian',
      album: 'Dip It Low (Mixes)',
      isFlac: true,
      duration: Duration(milliseconds: ms),
    );

void main() {
  group('de toewijzing zelf', () {
    test('DE KERN: de looptijd beslist, en dat doet ze onafhankelijk van de volgorde', () {
      final solo = bestand('05 - Dip It Low', 194220); // 3:14
      final duet = bestand('Christina Milian & Fabolous - Dip It Low', 218640); // 3:38

      for (final volgorde in [
        [solo, duet],
        [duet, solo]
      ]) {
        final c = matchAlbumTracks(kaal, volgorde, 'Christina Milian');
        expect(c.slots, hasLength(2));
        expect(c.slots[0].track?.path, solo.path, reason: 'rij 1 is de solo van 3:18');
        expect(c.slots[1].track?.path, duet.path, reason: 'rij 2 is die met Fabolous, 3:40');
        expect(c.slots.where((s) => s.index < 0), isEmpty);
      }
    });

    test('en de credit van de uitgave verandert daar niets aan', () {
      // Het bijschrift mag nooit de indeling gaan sturen: dan zou het aanvullen van credits stil
      // bestanden kunnen verplaatsen.
      final solo = bestand('a', 194220);
      final duet = bestand('b', 218640);
      final zonder = matchAlbumTracks(kaal, [solo, duet], 'Christina Milian');
      final met = matchAlbumTracks(metCredit, [solo, duet], 'Christina Milian');
      expect([for (final s in met.slots) s.track?.path],
          [for (final s in zonder.slots) s.track?.path]);
    });
  });

  group('wat de rij toont', () {
    // De rij zelf tekenen vraagt een PlayerStore, en die start media_kit op. De twee regels die
    // hier werkelijk iets beslissen staan daarom apart, en worden hier zuiver gemeten.
    test('DE KERN: de gast van de UITGAVE komt erbij als jouw tags hem niet noemen', () {
      // Het bestand noemt Fabolous nergens — niet in ARTIST, niet in de titel.
      expect(gastenVoorDeRij('Christina Milian', 'Dip It Low', ['Fabolous']), ['Fabolous']);
    });

    test('en een gast die het bestand zélf al noemt komt niet dubbel', () {
      expect(
          gastenVoorDeRij('Christina Milian', 'Dip It Low (feat. Fabolous)', ['Fabolous']),
          ['Fabolous']);
    });

    test('jouw eigen spelling wint', () {
      // Schrijft de uitgave "JAY-Z" en jouw bestand "Jay-Z", dan blijft die van jou staan; anders
      // verspringt een naam op het scherm zonder dat er iets aan je bestand veranderde.
      expect(gastenVoorDeRij('Beyoncé feat. Jay-Z', 'Crazy in Love', ['JAY-Z']), ['Jay-Z']);
    });

    test('zonder credit van de uitgave verandert er niets', () {
      expect(gastenVoorDeRij('Christina Milian', 'Dip It Low', const []), isEmpty);
      expect(gastenVoorDeRij('Missy Elliott', 'One Minute Man (Feat Ludacris)', const []),
          ['Ludacris']);
    });

    test('DE KERN: de looptijd hoort erbij als de uitgave de titel twee keer noemt', () {
      // Dan is die looptijd wat de rij aanwees, en zonder dat getal is de indeling niet na te
      // rekenen — precies waar Saber op vastliep.
      expect(titelKomtVakerVoor(kaal, kaal[0]), isTrue);
      expect(titelKomtVakerVoor(kaal, kaal[1]), isTrue);
    });

    test('en niet bij een gewone plaat', () {
      // Anders staat er bij élke rij een tweede getal, en dan zegt het niets meer.
      const gewoon = [
        ChoiceTrack('1', 'Get Ur Freak On', 227),
        ChoiceTrack('2', 'One Minute Man', 275),
      ];
      expect(titelKomtVakerVoor(gewoon, gewoon[0]), isFalse);
      expect(titelKomtVakerVoor(gewoon, gewoon[1]), isFalse);
    });

    test('een lege titel telt niet als dubbel', () {
      const leeg = [ChoiceTrack('1', '', 100), ChoiceTrack('2', '', 200)];
      expect(titelKomtVakerVoor(leeg, leeg[0]), isFalse);
    });
  });
}

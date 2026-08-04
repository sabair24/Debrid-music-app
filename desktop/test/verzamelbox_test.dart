/// Een greep uit een verzamelbox mag geen album van de zanger worden.
///
/// Gemeten op 04-08-2026: zoeken op "Khaled Didi" via Direct zoeken leverde een bestand dat landde als
/// `Albums/Khaled/1001 Songs You Must Hear Before You Die/779 - Didi.flac`, met deze tags van de
/// uploader er onaangeroerd op:
///
///     TRACKNUMBER  = 779
///     TRACKTOTAL   = 1001
///     ALBUM        = 1001 Songs You Must Hear Before You Die
///     album_artist = Various Artists
///
/// Saber: "de tags die met Soulseek worden meegegeven zijn meestal niet de goeie". Zo is het. Er stond
/// nu een album van Khaled in de bibliotheek met één nummer erin, en dat nummer heette 779.
///
/// De oorzaak was niet dat de indeler het fout deed, maar dat hij het niet kón zien: `classifyRelease`
/// kreeg alleen de artiest van het NUMMER, en die is bij zo'n box gewoon de echte zanger. Alleen
/// ALBUMARTIST verraadt "Various Artists" — en juist dat veld werd door `readTags` niet gelezen.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/organize.dart';

void main() {
  group('classifyRelease kijkt ook naar de albumartiest', () {
    test('het gemeten Khaled-geval wordt een verzamelaar, geen album', () {
      expect(
        classifyRelease(
          album: '1001 Songs You Must Hear Before You Die',
          artist: 'Khaled',
          albumArtist: 'Various Artists',
          totaalVolgensTags: 1001,
        ),
        RelKind.compilation,
      );
    });

    test('zónder die albumartiest gaat het wél mis — dat is precies wat er miste', () {
      // Deze test legt de OUDE uitkomst vast en bewijst daarmee dat het veld het verschil maakt. Zou
      // de titelregel of het aantal het al vangen, dan was er niets te repareren geweest en zou de
      // reparatie hierboven niets betekenen.
      expect(
        classifyRelease(album: '1001 Songs You Must Hear Before You Die', artist: 'Khaled'),
        RelKind.album,
        reason: 'de titel "1001 Songs…" alleen is niet genoeg; ALBUMARTIST is het bewijs',
      );
    });

    test('een absurd totaal verraadt een box, ook zonder Various Artists', () {
      expect(
        classifyRelease(album: 'Een of andere box', artist: 'Khaled', totaalVolgensTags: 1001),
        RelKind.compilation,
      );
    });

    test('een echt dubbel- of driedubbelalbum blijft een album', () {
      // De grens ligt bewust ruim boven wat een gewone plaat kan hebben. Deze app nummert dubbelalbums
      // DOORLOPEND, dus 30 of 40 nummers in één record is normaal en mag niet omvallen.
      expect(classifyRelease(album: 'The Wall', artist: 'Pink Floyd', totaalVolgensTags: 26), RelKind.album);
      expect(
          classifyRelease(album: 'Sandinista!', artist: 'The Clash', totaalVolgensTags: 36), RelKind.album);
      expect(
        classifyRelease(
            album: 'Iets groots', artist: 'Iemand', albumArtist: 'Iemand', totaalVolgensTags: 58),
        RelKind.album,
        reason: 'net onder de grens, en met een echte albumartiest',
      );
    });

    test('het totaal uit de TAGS mag de "één of twee nummers"-regel NIET aansturen', () {
      // Dit brak een bestaande test toen ik beide getallen door één parameter stuurde: een
      // opwaardering met TRACKTOTAL=2 in de tags van de uploader werd ineens een single en landde in
      // Singles/ in plaats van bij het album. Het aantal van een ECHTE uitgave mag dat wel.
      expect(
        classifyRelease(album: 'Backstreet Back', artist: 'Backstreet Boys', totaalVolgensTags: 2),
        RelKind.album,
      );
      expect(
        classifyRelease(album: 'Een single', artist: 'Iemand', trackCount: 2),
        RelKind.single,
      );
    });

    test('een gewoon album van één artiest blijft gewoon een album', () {
      expect(
        classifyRelease(
            album: 'Carpe Diem', artist: 'Lara Fabian', albumArtist: 'Lara Fabian', totaalVolgensTags: 13),
        RelKind.album,
      );
    });

    test('de bestaande regels blijven staan', () {
      expect(classifyRelease(album: '', artist: 'Wie dan ook'), RelKind.single);
      expect(classifyRelease(album: 'Iets', artist: 'Various Artists'), RelKind.compilation);
      expect(classifyRelease(album: 'Iets', artist: 'Iemand', trackCount: 2), RelKind.single);
    });
  });

  group('tags uit een bestand zijn nooit gezaghebbend', () {
    // De rem op de reparatie hierboven. `readTags` levert nu wél albumartiest en totaal, en de oude
    // afleiding "draagt hij die velden? dan komt hij van een officiële uitgave" zou daardoor omslaan:
    // een bestand van een uploader zou ineens gezaghebbend heten en `stampTags` zou zijn eigen tags
    // over zichzelf heen schrijven. Vandaar een expliciet vlaggetje in plaats van een gok.

    test('mét albumartiest en totaal, maar uit een bestand: niet gezaghebbend', () {
      const t = TrackTags(
        title: 'Didi',
        artist: 'Khaled',
        album: '1001 Songs You Must Hear Before You Die',
        trackNo: 779,
        albumArtist: 'Various Artists',
        trackTotal: 1001,
        vanBestand: true,
      );
      expect(t.isAuthoritative, isFalse);
    });

    test('dezelfde velden uit een uitgave: wél gezaghebbend', () {
      const t = TrackTags(
        title: 'Didi',
        artist: 'Khaled',
        album: 'Sahra',
        trackNo: 3,
        albumArtist: 'Khaled',
        trackTotal: 11,
      );
      expect(t.isAuthoritative, isTrue);
    });

    test('zonder die drie velden verandert er niets', () {
      const t = TrackTags(title: 'Didi', artist: 'Khaled', album: 'Sahra', trackNo: 3);
      expect(t.isAuthoritative, isFalse);
    });
  });

  group('waar het bestand terechtkomt', () {
    test('de box-greep gaat naar Compilaties, niet naar Albums van de zanger', () {
      const t = TrackTags(
        title: 'Didi',
        artist: 'Khaled',
        album: '1001 Songs You Must Hear Before You Die',
        trackNo: 779,
        albumArtist: 'Various Artists',
        trackTotal: 1001,
        vanBestand: true,
      );
      final pad = relativePathFor(t, ext: '.flac');
      expect(pad, startsWith('Compilaties'));
      expect(pad, isNot(contains('Albums')));
    });

    test('een gewoon album blijft waar het hoort', () {
      const t = TrackTags(
        title: 'Leïla',
        artist: 'Lara Fabian',
        album: 'Carpe Diem',
        trackNo: 3,
        albumArtist: 'Lara Fabian',
        trackTotal: 13,
      );
      expect(relativePathFor(t, ext: '.flac'), startsWith('Albums'));
    });
  });
}

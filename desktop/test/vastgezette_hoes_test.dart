/// Een persing die je zelf hebt vastgezet, houdt zijn hoes.
///
/// **De klacht, op 31-08-2026, met twee schermafdrukken erbij.** Op de albumpagina stond netjes
/// "Jouw uitgave: cd · EK 40600 · Canada" en in de uitgavekiezer stond die cd aangevinkt — en toch
/// prijkte de hoes van een héél andere persing op het scherm. *"Waarom blijft hij mijn fronthoes
/// veranderen? Dit had ik niet gekozen en toch staat deze erop."*
///
/// **Hoe dat kon.** `adoptAlbumCover` beschermde precies één ding: een hoes die je met de hand in de
/// bewerker had gekozen (`correctedCover`). Een VASTGEZETTE PERSING niet, terwijl dat net zo goed
/// een keuze is. En de achtergrondverwarmer loopt elke plaat af: kan hij jouw persing niet ophalen,
/// dan valt de opzoeker terug op een andere — en die schreef er ongehinderd overheen.
///
/// **Waarom een toets en niet even kijken.** Dit is met het oog niet na te gaan. Op de albumpagina
/// zie je in beide gevallen íets, en pas een scan later — of pas de volgende ochtend — blijkt welke
/// hoes er bleef staan. Precies het soort fout waar deze app al twee keer in getrapt is.
library;

import 'dart:typed_data';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Onderscheidbaar, en ruim boven de ondergrens van 500 bytes die `adoptAlbumCover` aanhoudt.
Uint8List hoes(int merk) => Uint8List.fromList(List<int>.filled(800, merk));

/// Een album met één nummer, en de pin die eraan hangt.
LibraryStore metAlbum({int? release, String? mbid}) {
  final t = Track(
    path: r'C:\Muziek\Michael Jackson\Bad\01 - Bad.flac',
    title: 'Bad',
    artist: 'Michael Jackson',
    album: 'Bad',
  );
  final album = Album('Bad', 'Michael Jackson', [t])..embeddedCover = hoes(1);
  final store = LibraryStore()..albums = [album];
  store.seedCorrectionForTest(t.path, {
    if (release != null) 'release': '$release',
    if (mbid != null) 'mbid': mbid,
  });
  return store;
}

Album enige(LibraryStore s) => s.albums.single;

void main() {
  group('zonder pin blijft alles zoals het was', () {
    test('een gevonden persing gaat vóór de bestanden', () {
      final s = metAlbum();
      expect(s.adoptAlbumCover('Michael Jackson', 'Bad', hoes(2), from: 'rel:15580823'), isTrue);
      expect(enige(s).cover, hoes(2), reason: 'een aangewezen persing is een feit over de plaat');
      expect(enige(s).resolvedFrom, 'rel:15580823');
    });

    test('een gok op naam blijft onder de bestanden', () {
      final s = metAlbum();
      s.adoptAlbumCover('Michael Jackson', 'Bad', hoes(2));
      expect(enige(s).cover, hoes(1), reason: 'zonder herkomst is het een gok, en die verliest');
    });
  });

  group('met een vastgezette Discogs-persing', () {
    test('de hoes van JOUW persing gaat vóór de bestanden', () {
      final s = metAlbum(release: 15580823);
      expect(s.adoptAlbumCover('Michael Jackson', 'Bad', hoes(2), from: 'rel:15580823'), isTrue);
      expect(enige(s).cover, hoes(2));
    });

    test('een ANDERE persing verdringt hem niet meer', () {
      // Dit is de gemelde fout. De verwamer viel terug op een andere uitgave en schreef die hoes
      // over de jouwe heen — zonder één woord, en blijvend, want hij ging ook naar schijf.
      final s = metAlbum(release: 15580823);
      s.adoptAlbumCover('Michael Jackson', 'Bad', hoes(9), from: 'rel:999999');
      expect(enige(s).resolvedCover, isNull, reason: 'een vreemde persing hoort hier niet te landen');
      expect(enige(s).cover, hoes(1), reason: 'dan liever de hoes uit je eigen bestanden');
    });

    test('en hij verdringt ook een hoes die er al stond niet', () {
      final s = metAlbum(release: 15580823);
      s.adoptAlbumCover('Michael Jackson', 'Bad', hoes(2), from: 'rel:15580823');
      s.adoptAlbumCover('Michael Jackson', 'Bad', hoes(9), from: 'rel:999999');
      expect(enige(s).cover, hoes(2), reason: 'jouw persing blijft staan');
      expect(enige(s).resolvedFrom, 'rel:15580823');
    });

    test('de vreemde hoes is niet weggegooid, alleen gedegradeerd', () {
      // Hij landt in `enriched` en blijft daarmee onder de bestanden. Bruikbaar voor een plaat
      // zonder eigen hoes, machteloos tegenover de jouwe.
      final s = metAlbum(release: 15580823);
      enige(s).embeddedCover = null;
      s.adoptAlbumCover('Michael Jackson', 'Bad', hoes(9), from: 'rel:999999');
      expect(enige(s).enriched, hoes(9));
      expect(enige(s).cover, hoes(9), reason: 'beter dan een lege tegel');
    });

    test('`dg:` telt net zo goed als `rel:`', () {
      // De uitgavekiezer schrijft de ene vorm, de hoezenweg de andere. Zie `persingUitHerkomst`.
      final s = metAlbum(release: 15580823);
      expect(s.adoptAlbumCover('Michael Jackson', 'Bad', hoes(2), from: 'dg:15580823'), isTrue);
      expect(enige(s).cover, hoes(2));
    });
  });

  group('met een vastgezette MusicBrainz-persing', () {
    const mbid = '3f2b6c2a-0000-4444-8888-aaaabbbbcccc';

    test('die van jou gaat voor', () {
      final s = metAlbum(mbid: mbid);
      expect(s.adoptAlbumCover('Michael Jackson', 'Bad', hoes(2), from: 'mb:$mbid'), isTrue);
      expect(enige(s).cover, hoes(2));
    });

    test('een andere niet', () {
      final s = metAlbum(mbid: mbid);
      s.adoptAlbumCover('Michael Jackson', 'Bad', hoes(9), from: 'mb:99999999-0000-0000-0000-0000');
      expect(enige(s).cover, hoes(1));
    });

    test('een Discogs-persing verdringt een MusicBrainz-pin evenmin', () {
      // De twee pinnen staan los van elkaar; een treffer op de ene as zegt niets over de andere.
      final s = metAlbum(mbid: mbid);
      s.adoptAlbumCover('Michael Jackson', 'Bad', hoes(9), from: 'rel:15580823');
      expect(enige(s).cover, hoes(1));
    });
  });

  group('wat er niet verandert', () {
    test('een hoes die je zelf koos blijft boven alles staan', () {
      final s = metAlbum(release: 15580823);
      enige(s).correctedCover = hoes(7);
      s.adoptAlbumCover('Michael Jackson', 'Bad', hoes(2), from: 'rel:15580823');
      expect(enige(s).cover, hoes(7), reason: 'zelfs jouw eigen persing wint hier niet van');
    });

    test('te kleine bytes zijn geen hoes', () {
      final s = metAlbum(release: 15580823);
      expect(
          s.adoptAlbumCover('Michael Jackson', 'Bad', Uint8List.fromList(List<int>.filled(100, 3)),
              from: 'rel:15580823'),
          isFalse);
    });
  });
}

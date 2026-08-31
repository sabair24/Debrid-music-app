/// De artiestcredit moet de gang naar de schijf overleven.
///
/// **Waarom dit bestaat.** `matchAlbumTracks` kan sinds #156 een gastartiest herkennen doordat
/// MusicBrainz die náást de titel zet: de rij heet "Crazy in Love" en de credit ernaast luidt
/// "Beyoncé feat. JAY-Z". Dat is precies wat een rip met "(feat. Jay-Z)" ín de titel verbindt met
/// diezelfde rij — en wat Adele's duet er juist buiten houdt.
///
/// Alleen: de albumpagina leest zijn uitgave niet van MusicBrainz maar van het bestandje naast de
/// muziek, en dáár werd de credit niet in opgeschreven. Alles ertussenin klopte; de laatste meter
/// ontbrak.
///
/// **Gemeten op 01-09-2026** met tien bestanden van *Dangerously In Love* op schijf, na een verse
/// ophaalronde: vier op de uitgave, zes onder "Niet op deze uitgave" — en dat waren exact de zes met
/// een gast in de titel. Een reparatie die de schijf niet haalt, is voor de gebruiker geen
/// reparatie.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/album_facts.dart';
import 'package:debridmusic/completeness.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/models.dart';

void main() {
  test('DE KERN: de credit staat er na opslaan en teruglezen nog', () {
    final voor = AlbumFacts(
      uid: 'x',
      trackSetHash: 'h',
      source: 'MusicBrainz',
      tracklist: const [
        ChoiceTrack('1', 'Crazy in Love', 235, artist: 'Beyoncé feat. JAY-Z'),
        ChoiceTrack('2', 'Naughty Girl', 208),
      ],
    );

    final na = AlbumFacts.fromJson(voor.toJson());
    expect(na, isNotNull);
    expect(na!.tracklist.first.artist, 'Beyoncé feat. JAY-Z');
    expect(na.tracklist[1].artist, isEmpty, reason: 'wie geen gast heeft krijgt er ook geen');
  });

  test('en daarmee vindt het bestand mét de gast in de titel zijn rij terug', () {
    // De hele keten in één keer: van schijf terug, en dan door de vergelijker.
    final opSchijf = AlbumFacts.fromJson(AlbumFacts(
      uid: 'x',
      trackSetHash: 'h',
      tracklist: const [ChoiceTrack('1', 'Crazy in Love', 235, artist: 'Beyoncé feat. JAY-Z')],
    ).toJson())!;

    final uit = matchAlbumTracks(opSchijf.tracklist, [
      Track(
        path: r'D:\muziek\01 - Crazy In Love (Featuring Jay-Z).flac',
        title: 'Crazy In Love (Featuring Jay-Z)',
        artist: 'Beyoncé',
        album: 'Dangerously In Love',
        isFlac: true,
        duration: const Duration(seconds: 236),
        trackNo: 1,
      ),
    ], 'Beyoncé');

    expect(uit.matched, 1, reason: 'dit is nummer 1 van de plaat, geen weeskind');
  });

  test('een bestandje van de oude vorm wordt opnieuw opgehaald', () {
    // Zonder deze regel houden de 476 platen die er al liggen hun oude gegevens, en verandert er
    // voor de gebruiker niets — de reparatie zou dan alleen werken voor muziek die hij nog moet
    // binnenhalen.
    final oud = AlbumFacts(uid: 'x', trackSetHash: 'h', schema: kAlbumFactsSchema - 1);
    expect(oud.staleFor('h'), isTrue);

    final nieuw = AlbumFacts(uid: 'x', trackSetHash: 'h');
    expect(nieuw.staleFor('h'), isFalse);
  });
}

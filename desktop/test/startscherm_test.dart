/// De twee regels waar het startscherm op leunde zonder ze te hebben.
///
/// De balk "NIEUWE RELEASE" toonde albums uit 2011 en 2016 — er zat helemaal geen jaarfilter op — en
/// "Aanbevolen voor jou" hield zijn uitkomst nergens tegen de bibliotheek, dus stond er muziek in die
/// je allang had. Allebei losse functies gemaakt, zodat ze hier uitgeschreven kunnen worden in plaats
/// van dat je ze in de app moet zitten bekijken.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/catalog.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/recommend.dart';

CatalogAlbumHit _album(String titel, String? datum) =>
    CatalogAlbumHit(CatalogAlbum(1, titel, null, datum, 10, 'album'), 'A');

void main() {
  group('alleen wat dit jaar uitkwam', () {
    test('houdt dit jaar en laat de rest vallen', () {
      final uit = uitJaar([
        _album('nu', '2026-03-14'),
        _album('vorig jaar', '2025-12-31'),
        _album('lang geleden', '2011-06-01'),
      ], 2026);
      expect(uit.map((h) => h.album.title), ['nu']);
    });

    test('een ontbrekende of onleesbare datum valt weg, en telt niet als jaar nul', () {
      // Deezer laat release_date weg bij oude of onvolledige uitgaves. Die sorteerden voorheen als
      // lege tekst naar onderen maar bléven staan; hier horen ze gewoon niet thuis.
      final uit = uitJaar([
        _album('zonder datum', null),
        _album('leeg', ''),
        _album('rommel', 'binnenkort'),
        _album('goed', '2026-01-02'),
      ], 2026);
      expect(uit.map((h) => h.album.title), ['goed']);
    });

    test('niets van dit jaar geeft een lege lijst, geen uitzondering', () {
      expect(uitJaar([_album('oud', '2011-01-01')], 2026), isEmpty);
      expect(uitJaar(const [], 2026), isEmpty);
    });
  });

  group('aanbevelingen die je nog niet hebt', () {
    Track bezit(String artiest, String titel) =>
        Track(path: '$artiest-$titel.flac', title: titel, artist: artiest, album: 'X');

    test('wat je hebt valt weg, de rest blijft staan', () {
      final mijn = bezitSleutels([bezit('Adele', 'Hello')]);
      final uit = nogNietInBezit(const [
        RecTrack('Adele', 'Hello', null),
        RecTrack('Adele', 'Skyfall', null),
      ], mijn);
      expect(uit.map((r) => r.title), ['Skyfall']);
    });

    test('een andere versie van hetzelfde nummer telt óók als in bezit', () {
      // DE reden dat dit de losse normalisatie gebruikt en niet die van ownedTrack. Heb je het nummer,
      // dan hoef je het niet aanbevolen te krijgen omdat er "(Radio Edit)" achter staat.
      final mijn = bezitSleutels([bezit('Adele', 'Hello')]);
      final uit = nogNietInBezit(const [
        RecTrack('Adele', 'Hello (Radio Edit)', null),
        RecTrack('Adele', 'Hello [2015 Remaster]', null),
        RecTrack('Adele', 'Hello feat. Iemand', null),
      ], mijn);
      expect(uit, isEmpty);
    });

    test('een artiest die je kent mag met ander werk gewoon langskomen', () {
      // Er wordt op nummers gefilterd en niet op artiesten: dat je iemand hebt, betekent niet dat hij
      // nooit meer iets nieuws mag aandragen.
      final mijn = bezitSleutels([bezit('Adele', 'Hello')]);
      final uit = nogNietInBezit(const [RecTrack('Adele', 'Easy On Me', null)], mijn);
      expect(uit.length, 1);
    });

    test('een lege bibliotheek houdt niets tegen', () {
      final uit = nogNietInBezit(const [RecTrack('X', 'Y', null)], bezitSleutels(const []));
      expect(uit.length, 1);
    });
  });
}

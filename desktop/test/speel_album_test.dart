// ▶ tagt het bestand met het album waarop je het nummer zag.
//
// Saber, 21-10-2026: Jordy — Dur Dur D'être Bébé, met ▶ uit de zoekuitslag (Deezer: "Pochette Surprise"),
// stond als "Foute Cd 11 Cd2" in de bibliotheek, met de hoes van die verzamelaar — de albumtag van de
// uploader. "het moet echt de originele hoes zijn".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/online.dart';

String _lees(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('gezagVoorHaal', () {
    test('met een album: ALBUM en ALBUMARTIST, en dus schrijft stampTags', () {
      final t = DownloadManager.gezagVoorHaal(
          artiest: 'Jordy', titel: "Dur Dur d'être bébé !", album: 'Pochette Surprise', seconden: 205);
      expect(t.album, 'Pochette Surprise');
      expect(t.albumArtist, 'Jordy');
      expect(t.isAuthoritative, isTrue, reason: 'zonder dat schrijft stampTags niets en blijft "Foute Cd 11 Cd2"');
      expect(t.vorbisFields['ALBUM'], 'Pochette Surprise');
      expect(t.vorbisFields['ALBUMARTIST'], 'Jordy');
      expect(t.vorbisFields.containsKey('TRACKNUMBER'), isFalse);
    });

    test('zonder album (de radio): zoals het was', () {
      final t = DownloadManager.gezagVoorHaal(artiest: 'Jordy', titel: 'Dur Dur', seconden: 205);
      expect(t.album, '');
      expect(t.albumArtist, isNull);
      expect(t.isAuthoritative, isFalse);
      final metJaar = DownloadManager.gezagVoorHaal(artiest: 'Jordy', titel: 'Dur Dur', jaar: 1992, album: '  ');
      expect(metJaar.album, '');
      expect(metJaar.albumArtist, isNull);
      expect(metJaar.year, 1992);
    });

    test('een verzamelaar als album telt niet', () {
      for (final a in ['Foute Cd 11 Cd2', 'NOW 121', 'Bravo Hits 00\'s']) {
        final t = DownloadManager.gezagVoorHaal(artiest: 'Jordy', titel: 'Dur Dur', album: a);
        expect(t.album, '', reason: a);
        expect(t.albumArtist, isNull, reason: a);
      }
    });
  });

  group('aangesloten', () {
    test('▶ geeft het album mee, op de pc en via de pc', () {
      final main = _lees('lib/main.dart');
      expect(main, contains('final plek = Radioplek(artiest: artiest, titel: titel, seconden: seconden, album: album);'));
      final radio = _lees('lib/radio.dart');
      expect(radio, contains('              losVanDeRadio: los,\n              album: plek.album,'));
      final server = _lees('lib/lan/server.dart');
      expect(server, contains("album: body['album'] is String ? body['album'] as String : null,"));
      final online = _lees('lib/online.dart');
      expect(online,
          contains('final gezag = gezagVoorHaal(artiest: artiest, titel: titel, album: album, jaar: jaar, seconden: seconden);'));
      expect(online, contains('vroeg: vroeg, zoekBeter: zoekDaarnaBeter, album: album);'));
    });
  });
}

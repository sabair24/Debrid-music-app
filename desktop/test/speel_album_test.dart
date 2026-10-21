// ▶ tagt het bestand met het album waarop je het nummer zag.
//
// Saber, 21-10-2026: Jordy — Dur Dur D'être Bébé, met ▶ uit de zoekuitslag (Deezer: "Pochette Surprise"),
// stond als "Foute Cd 11 Cd2" in de bibliotheek, met de hoes van die verzamelaar — de albumtag van de
// uploader. "het moet echt de originele hoes zijn".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/enrichment.dart' show nummerOpAlbum, plekUitDeezerNummer;
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

  group('nummering en jaar van de uitgave', () {
    final gezag = DownloadManager.gezagVoorHaal(
        artiest: 'Jordy', titel: "Dur Dur d'être bébé !", album: 'Pochette Surprise', seconden: 205);

    test('een verzamelrip: het nummer en jaar van deze uitgave, de rest van de andere weg', () {
      final v = DownloadManager.veldenNaHaal(gezag,
          eigenAlbum: 'Foute Cd 11 Cd2', plek: (jaar: 1992, nummer: 1, schijf: 1));
      expect(v['TRACKNUMBER'], '1');
      expect(v['DISCNUMBER'], '1');
      expect(v['DATE'], '1992', reason: 'was 2012, het jaar van de Foute CD');
      expect(v.containsKey('TRACKTOTAL') && v['TRACKTOTAL'] == null, isTrue);
      expect(v['ALBUM'], 'Pochette Surprise');
      expect(v['ALBUMARTIST'], 'Jordy');
    });

    test('weet Deezer het niet: nummer en jaar van de andere uitgave weg', () {
      final v = DownloadManager.veldenNaHaal(gezag, eigenAlbum: 'Foute Cd 11 Cd2');
      for (final k in ['TRACKNUMBER', 'DISCNUMBER', 'DATE', 'TRACKTOTAL']) {
        expect(v.containsKey(k) && v[k] == null, isTrue, reason: k);
      }
      expect(v['ALBUM'], 'Pochette Surprise');
    });

    test('al hetzelfde album: zijn eigen nummering blijft', () {
      final v = DownloadManager.veldenNaHaal(gezag,
          eigenAlbum: 'pochette surprise', plek: (jaar: 1992, nummer: 1, schijf: 1));
      expect(v.containsKey('TRACKNUMBER'), isFalse);
      expect(v.containsKey('DATE'), isFalse);
      expect(v['ALBUM'], 'Pochette Surprise');
    });

    test('de radio (geen album): zoals stampTags het deed', () {
      final radio = DownloadManager.gezagVoorHaal(artiest: 'Jordy', titel: 'Dur Dur', jaar: 1992);
      expect(DownloadManager.veldenNaHaal(radio, eigenAlbum: 'Foute Cd 11 Cd2'), radio.vorbisFields);
      final zonder = DownloadManager.gezagVoorHaal(artiest: 'Jordy', titel: 'Dur Dur');
      expect(DownloadManager.veldenNaHaal(zonder, eigenAlbum: 'Foute Cd 11 Cd2'), isEmpty);
    });

    test('de jacht op beter tagt met hetzelfde nummer en jaar', () {
      final t = DownloadManager.metPlek(gezag, (jaar: 1992, nummer: 1, schijf: 1));
      expect(t.trackNo, 1);
      expect(t.year, 1992);
      expect(t.album, 'Pochette Surprise');
      expect(DownloadManager.metPlek(gezag, null), same(gezag));
    });

    test('Deezer: het nummer op precies dat album, geen karaoke of verzamelaar', () {
      final data = [
        {'id': 9, 'title': "Dur Dur D'être Bébé (Originally Performed by Jordy) [Karaoke Version]",
          'artist': {'name': 'The Karaoke Channel'}, 'album': {'title': 'Pochette Surprise'}},
        {'id': 8, 'title': "Dur Dur d'être bébé !", 'artist': {'name': 'Jordy'}, 'album': {'title': 'Foute CD 11'}},
        {'id': 3068705921, 'title': "Dur Dur d'être bébé !", 'artist': {'name': 'Jordy'},
          'album': {'title': 'Pochette Surprise'}},
      ];
      expect(nummerOpAlbum(data, 'Jordy', "Dur Dur d'être bébé !", 'Pochette Surprise'), 3068705921);
      expect(nummerOpAlbum(data, 'Jordy', "Dur Dur d'être bébé !", 'Iets Anders'), isNull);
      // Zoals /track/3068705921 het op 21-10-2026 gaf.
      final p = plekUitDeezerNummer({
        'track_position': 1,
        'disk_number': 1,
        'release_date': '1992-01-01',
        'album': {'title': 'Pochette Surprise', 'release_date': '1992-01-01'},
      });
      expect(p, (jaar: 1992, nummer: 1, schijf: 1));
      expect(plekUitDeezerNummer({'release_date': '0000-00-00'}), (jaar: null, nummer: 0, schijf: 0));
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
      expect(online, contains('final velden = veldenNaHaal(gezag,'));
      expect(online, contains('gezag: metPlek(gezag, plek),'));
      expect(main, contains('if (mode.owner) DownloadManager.plekOpAlbum = deezerPlekOpAlbum;'));
    });
  });
}

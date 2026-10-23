// ▶ tagt het bestand met het album waarop je het nummer zag.
//
// Saber, 21-10-2026: Jordy — Dur Dur D'être Bébé, met ▶ uit de zoekuitslag (Deezer: "Pochette Surprise"),
// stond als "Foute Cd 11 Cd2" in de bibliotheek, met de hoes van die verzamelaar — de albumtag van de
// uploader. "het moet echt de originele hoes zijn".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/enrichment.dart'
    show albumIsDeSingle, deezerSingleUit, nummerOpAlbum, origineleUitgaveUit, plekUitDeezerNummer;
import 'package:debridmusic/metadata.dart' show MetaResult, studioVoorop;
import 'package:debridmusic/musicbrainz.dart' show MbRecording;
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

  group('zonder album: de oorspronkelijke uitgave uit MusicBrainz (Saber, 23-10-2026: "Ja")', () {
    Map<String, dynamic> uitgave(String titel, String soort,
            {List<String> ook = const [], String datum = '', String status = 'Official'}) =>
        {
          'id': 'id-$titel-$soort-$datum',
          'title': titel,
          'status': status,
          'date': datum,
          'release-group': {'primary-type': soort, 'secondary-types': ook},
        };
    MbRecording opname(String titel, String artiest, int ms, List<Map<String, dynamic>> uitgaven, {String eerste = ''}) =>
        MbRecording.from({
          'id': 'rec-$titel-$ms',
          'title': titel,
          'length': ms,
          'first-release-date': eerste,
          'artist-credit': [
            {'name': artiest}
          ],
          'releases': uitgaven,
        });

    // Zoals MusicBrainz het op 23-10-2026 gaf voor artist:"Ellie Goulding" AND recording:"Hate Me".
    final hateMe = [
      opname('Hate Me (acoustic)', 'Ellie Goulding', 183450, [uitgave('EG.0', 'Album', ook: ['Compilation'], datum: '2026-10-16')]),
      opname('Hate Me', 'Ellie Goulding', 182000,
          [uitgave('Promo Only: Mainstream Radio, August 2019', 'Album', ook: ['Compilation'], datum: '2019-07', status: 'Promotion')]),
      opname('Hate Me', 'Ellie Goulding', 205000,
          [uitgave('Brightest Blue', 'Album', datum: '2020-07-17'), uitgave('Hate Me', 'Single', datum: '2019-07-17')]),
      opname('Hate Me', 'Ellie Goulding', 186226, [
        uitgave('EG.0', 'Album', ook: ['Compilation'], datum: '2026-10-16'),
        uitgave('Sad Songs of 2022', 'Album', ook: ['Compilation']),
        uitgave('Brightest Blue', 'Album'),
      ], eerste: '2019-06-26'),
    ];

    test('DE KERN: Hate Me hoort bij Brightest Blue — niet bij EG.0 of een andere verzamelaar', () {
      final o = origineleUitgaveUit(hateMe, artiest: 'Ellie Goulding & Juice WRLD', titel: 'Hate Me', seconden: 186);
      expect(o?.album, 'Brightest Blue');
      expect(o?.jaar, 2020, reason: 'het jaar van de plaat (2020-07-17), niet de eerste datum van de opname (2019)');
    });

    test('dance: geen MusicBrainz-album, wel een Deezer-single die naar het nummer heet', () {
      // Zoals Deezer het op 23-10-2026 gaf.
      final tomcraft = [
        {'title': 'Loneliness (Radio Cut)', 'duration': 227, 'artist': {'name': 'Tomcraft'}, 'album': {'title': 'Loneliness'}},
        {'title': 'Loneliness', 'duration': 163, 'artist': {'name': 'Hardwell'}, 'album': {'title': 'Loneliness'}},
      ];
      expect(deezerSingleUit(tomcraft, 'Tomcraft', 'Loneliness (Radio Cut)', seconden: 227), 'Loneliness');
      expect(deezerSingleUit(tomcraft, 'Tomcraft', 'Loneliness (Radio Cut)', seconden: 300), isNull,
          reason: 'een andere lengte');
      final cafe = [
        {
          'title': "Café Del Mar (Three 'N One Radio Edit)",
          'duration': 229,
          'artist': {'name': 'Energy 52'},
          'album': {'title': 'Café Del Mar: The Best of the Remixes'}
        },
      ];
      expect(deezerSingleUit(cafe, 'Energy 52', "Café Del Mar (Three 'N One Radio Edit)"), isNull,
          reason: 'een plaat met een andere naam is geen single — en een "best of" al helemaal niet');
    });

    test('het album gaat voor de single, ook als de single eerder uitkwam', () {
      final o = origineleUitgaveUit([hateMe[2]], artiest: 'Ellie Goulding', titel: 'Hate Me');
      expect(o, (album: 'Brightest Blue', jaar: 2020));
    });

    test('alleen een single: dan de single', () {
      final o = origineleUitgaveUit([
        opname('Close To Me', 'Ellie Goulding', 183000, [
          uitgave('Close To Me', 'Single', datum: '2018-10-24'),
          uitgave('Now 101', 'Album', ook: ['Compilation'], datum: '2018-11-01'),
        ])
      ], artiest: 'Ellie Goulding', titel: 'Close To Me', seconden: 183);
      expect(o, (album: 'Close To Me', jaar: 2018));
    });

    test('alleen verzamelaars, live of promo: geen album — dan blijft het zoals het was', () {
      expect(origineleUitgaveUit([hateMe[0], hateMe[1]], artiest: 'Ellie Goulding', titel: 'Hate Me'), isNull);
      final live = opname('Hate Me', 'Ellie Goulding', 186000, [uitgave('Live at the O2', 'Album', ook: ['Live'], datum: '2021')]);
      expect(origineleUitgaveUit([live], artiest: 'Ellie Goulding', titel: 'Hate Me'), isNull);
      final bootleg = opname('Hate Me', 'Ellie Goulding', 186000, [uitgave('Hate Me', 'Single', datum: '2019', status: 'Bootleg')]);
      expect(origineleUitgaveUit([bootleg], artiest: 'Ellie Goulding', titel: 'Hate Me'), isNull);
    });

    test('een andere lengte is een andere versie, en een andere artiest een ander nummer', () {
      expect(origineleUitgaveUit([hateMe[2]], artiest: 'Ellie Goulding', titel: 'Hate Me', seconden: 186), isNull,
          reason: '205 s tegen 186 s');
      final karaoke = opname('Hate Me', 'The Karaoke Channel', 186000, [uitgave('Karaoke Hits', 'Album', datum: '2020')]);
      expect(origineleUitgaveUit([karaoke], artiest: 'Ellie Goulding', titel: 'Hate Me'), isNull);
    });

    test('de single als album: dan toch het studioalbum zoeken (radiotest van 23-10-2026)', () {
      expect(albumIsDeSingle("Summer Of '69", "Summer Of '69"), isTrue);
      expect(albumIsDeSingle('Loneliness', 'Loneliness (Radio Cut)'), isTrue);
      expect(albumIsDeSingle("Summer Of '69 (Remastered)", "Summer Of '69"), isTrue);
      expect(albumIsDeSingle('Reckless', "Summer Of '69"), isFalse);
      expect(albumIsDeSingle('', 'Luka'), isFalse);
    });

    test('een album van de artiest zelf gaat voor een soundtrack en voor "Various Artists"', () {
      Map<String, dynamic> met(String titel, String soort, String artiest, {List<String> ook = const [], String datum = ''}) =>
          {
            ...uitgave(titel, soort, ook: ook, datum: datum),
            'artist-credit': [
              {'name': artiest}
            ],
          };
      final lald = opname('Live and Let Die', 'Paul McCartney', 193000, [
        met('The In-Laws (Music From the Motion Picture)', 'Album', 'Various Artists', ook: ['Soundtrack'], datum: '2003'),
        met('Live and Let Die', 'Album', 'George Martin', ook: ['Soundtrack'], datum: '2003-06-02'),
        met('Red Rose Speedway', 'Album', 'Paul McCartney & Wings', datum: '2018-12-07'),
        met('SWF 3 Club Collection Oldies', 'Album', 'Various Artists', datum: '1999'),
      ]);
      expect(origineleUitgaveUit([lald], artiest: 'Paul McCartney', titel: 'Live And Let Die', seconden: 193)?.album,
          'Red Rose Speedway');
      final alleenVerzamelaar = opname('Live and Let Die', 'Paul McCartney', 193000,
          [met('SWF 3 Club Collection Oldies', 'Album', 'Various Artists', datum: '1999')]);
      expect(origineleUitgaveUit([alleenVerzamelaar], artiest: 'Paul McCartney', titel: 'Live And Let Die'), isNull,
          reason: 'een verzamelaar die MusicBrainz niet zo noemt, telt niet');
    });

    test('"Uitgave kiezen…" bij een los nummer: de studioalbums bovenaan, verder in dezelfde volgorde', () {
      const a = MetaResult(title: 'Summer of 69', artist: 'Bryan Adams', album: "Summer of '69");
      const b = MetaResult(title: 'x', artist: 'Bryan Adams', album: 'Live at Slane Castle');
      const c = MetaResult(title: 'x', artist: 'Bryan Adams', album: 'Reckless', studioalbum: true);
      const d = MetaResult(title: 'x', artist: 'Bryan Adams', album: 'Greatest Hits Live');
      expect([for (final m in studioVoorop([a, b, c, d])) m.album],
          ['Reckless', "Summer of '69", 'Live at Slane Castle', 'Greatest Hits Live']);
      final m = _lees('lib/main.dart');
      expect(m, contains('track: widget.album.isSingle && !los,'), reason: 'ook op welke platen dit nummer staat');
      expect(m, contains('List<MetaResult> orden(List<MetaResult> r) => los ? studioVoorop(r) : r;'));
      final meta = _lees('lib/metadata.dart');
      expect(meta, contains("studioalbum: rel.isStudioAlbum && (rel.status.isEmpty || rel.status == 'Official'),"));
      expect(meta, contains('mb.searchRecordings(song, artist: artist, max: 25, alleenAlbums: true),'));
    });

    test('een remixplaat alleen voor een remix', () {
      final remixen = opname('Close To Me (Red Velvet Remix)', 'Ellie Goulding', 191000,
          [uitgave('Close To Me (Remixes)', 'EP', ook: ['Remix'], datum: '2018-12-07')]);
      expect(origineleUitgaveUit([remixen], artiest: 'Ellie Goulding', titel: 'Close To Me (Red Velvet Remix)'),
          (album: 'Close To Me (Remixes)', jaar: 2018));
      final gewoon = opname('Close To Me', 'Ellie Goulding', 183000, [uitgave('Close To Me (Remixes)', 'EP', ook: ['Remix'])]);
      expect(origineleUitgaveUit([gewoon], artiest: 'Ellie Goulding', titel: 'Close To Me'), isNull);
    });
  });

  group('aangesloten', () {
    test('zonder album zoekt de pc de oorspronkelijke uitgave op en tagt daarmee', () {
      final online = _lees('lib/online.dart');
      expect(online, contains('? origineleUitgave?.call(artiest, titel, seconden).then'));
      expect(online, contains('final gevonden =\n                origineelF == null ? null : await origineelF.timeout('));
      expect(online, contains('final alsSingle = gezag.album.isNotEmpty && albumIsDeSingle(gezag.album, titel);'));
      expect(online, contains('final origineelF = gezag.album.isEmpty || alsSingle'));
      expect(online, contains('              gezag = gezagVoorHaal(\n                  artiest: artiest,\n                  titel: titel,\n                  album: origineel.album,'));
      final main = _lees('lib/main.dart');
      expect(main, contains('DownloadManager.origineleUitgave = (artiest, titel, seconden) => origineleUitgaveVan('));
    });

    test('▶ geeft het album mee, op de pc en via de pc', () {
      final main = _lees('lib/main.dart');
      expect(main, contains('final plek = Radioplek(artiest: artiest, titel: titel, seconden: seconden, album: album);'));
      final radio = _lees('lib/radio.dart');
      expect(radio, contains('              losVanDeRadio: los,\n              album: plek.album,'));
      final server = _lees('lib/lan/server.dart');
      expect(server, contains("album: body['album'] is String ? body['album'] as String : null,"));
      final online = _lees('lib/online.dart');
      expect(online,
          contains('var gezag = gezagVoorHaal(artiest: artiest, titel: titel, album: album, jaar: jaar, seconden: seconden);'));
      expect(online, contains('vroeg: vroeg, zoekBeter: zoekDaarnaBeter, album: album);'));
      expect(online, contains('final velden = veldenNaHaal(gezag,'));
      expect(online, contains('gezag: metPlek(gezag, plek),'));
      expect(main, contains('if (mode.owner) DownloadManager.plekOpAlbum = deezerPlekOpAlbum;'));
    });
  });
}

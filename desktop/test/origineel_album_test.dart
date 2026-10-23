// Het oorspronkelijke album van een radionummer, en de tag die er ook echt in komt (23-10-2026).
//
// Gemeten bij een radio vanaf Suzanne Vega — Luka: van 48 opgehaalde nummers kregen er 28 geen album en 3 een verkeerd.
// Twee oorzaken. De zoekvraag op opnames geeft bij MusicBrainz vooral heruitgaven (Linger op Bury the Hatchet, What's
// Love Got to Do with It op de deluxe van Break Every Rule, Luka op de heropname van 2010). En bij een nummer dat al
// speelde terwijl het binnenkwam mislukte het schrijven stil (Luka, Cathedral Song).
import 'dart:io';

import 'package:debridmusic/enrichment.dart'
    show deezerAlbumsMetNummer, albumsMetNummerUitOpnames, studioalbumUitGroepen, zonderEditie;
import 'package:debridmusic/musicbrainz.dart' show MbRecording, MbReleaseGroup;
import 'package:debridmusic/online.dart';
import 'package:debridmusic/organize.dart' show writeTagFields;
import 'package:debridmusic/paths.dart' show setAppDirForTest;
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

MbReleaseGroup _plaat(String id, String titel, String datum, {List<String> ook = const []}) =>
    MbReleaseGroup(id, titel, 'x', 'x', 'Album', secondaryTypes: ook, firstDate: datum);

String? _album(({String album, int? jaar})? o) => o == null ? null : '${o.album} ${o.jaar}';

void main() {
  group('het oudste studioalbum', () {
    test('DE KERN: Linger hoort bij Everybody Else Is Doing It (1993), niet bij Bury the Hatchet (1999)', () {
      final o = studioalbumUitGroepen([
        (titel: 'Bury the Hatchet', groep: 'g-bth'),
        (titel: "Everybody Else Is Doing It, So Why Can't We?", groep: ''), // Deezer: alleen de titel
      ], [
        _plaat('g-bth', 'Bury the Hatchet', '1999-04-19'),
        _plaat('g-ee', 'Everybody Else Is Doing It, So Why Can’t We?', '1993-03-01'),
        _plaat('g-best', 'Stars: The Best of 1992–2002', '2002-09-16', ook: ['Compilation']),
      ]);
      expect(_album(o), 'Everybody Else Is Doing It, So Why Can’t We? 1993', reason: 'met de schrijfwijze van MusicBrainz');
    });

    test('een deluxe met bonusnummers telt pas als er niets anders is', () {
      final plaatjes = [
        _plaat('g-pd', 'Private Dancer', '1984-05-29'),
        _plaat('g-ber', 'Break Every Rule', '1986-09-24'),
        _plaat('g-fa', 'Foreign Affair', '1989-09-12'),
      ];
      expect(
          _album(studioalbumUitGroepen([
            (titel: 'Break Every Rule (Deluxe Edition)', groep: 'g-ber'),
            (titel: 'Private Dancer', groep: 'g-pd'),
          ], plaatjes)),
          'Private Dancer 1984');
      expect(
          _album(studioalbumUitGroepen([
            (titel: 'Break Every Rule (Deluxe Edition)', groep: 'g-ber'),
            (titel: 'Foreign Affair', groep: 'g-fa'),
          ], plaatjes)),
          'Foreign Affair 1989',
          reason: 'de deluxe van een vroegere plaat draagt vaak de hits van een latere');
      expect(_album(studioalbumUitGroepen([(titel: 'Break Every Rule (Deluxe Edition)', groep: '')], plaatjes)),
          'Break Every Rule 1986',
          reason: 'zonder andere kandidaat: de plaat zelf, zonder "(Deluxe Edition)"');
      expect(_album(studioalbumUitGroepen([(titel: 'Private Dancer (30th Anniversary Issue)', groep: '')], plaatjes)),
          'Private Dancer 1984');
    });

    test('twee studioalbums met dezelfde naam: op de titel alleen geen gok, op het id wel', () {
      final plaatjes = [
        _plaat('g-dd81', 'Duran Duran', '1981-06-15'),
        _plaat('g-dd93', 'Duran Duran', '1993-02-11'),
      ];
      expect(studioalbumUitGroepen([(titel: 'Duran Duran', groep: '')], plaatjes), isNull,
          reason: 'Ordinary World staat op die van 1993, niet op het debuut van 1981');
      expect(_album(studioalbumUitGroepen([(titel: 'Duran Duran', groep: 'g-dd93')], plaatjes)), 'Duran Duran 1993');
    });

    test('in hetzelfde jaar wint de plaat die MusicBrainz én Deezer noemen (Carnival: Tigerlily)', () {
      final o = studioalbumUitGroepen([
        (titel: 'Garden Lillies', groep: 'g-gl'),
        (titel: 'Tigerlily', groep: 'g-tl'),
        (titel: 'Tigerlily', groep: ''),
      ], [
        _plaat('g-gl', 'Garden Lillies', '1995'),
        _plaat('g-tl', 'Tigerlily', '1995-06-16'),
      ]);
      expect(_album(o), 'Tigerlily 1995');
      // Elk regeltje apart: de bronnen beslissen ook bij even precieze datums, en de precisie als de bronnen gelijk zijn.
      expect(
          _album(studioalbumUitGroepen([
            (titel: 'Garden Lillies', groep: 'g-gl'),
            (titel: 'Tigerlily', groep: 'g-tl'),
            (titel: 'Tigerlily', groep: ''),
          ], [
            _plaat('g-gl', 'Garden Lillies', '1995-01-01'),
            _plaat('g-tl', 'Tigerlily', '1995-06-16'),
          ])),
          'Tigerlily 1995');
      expect(
          _album(studioalbumUitGroepen([
            (titel: 'Garden Lillies', groep: 'g-gl'),
            (titel: 'Tigerlily', groep: 'g-tl'),
          ], [
            _plaat('g-gl', 'Garden Lillies', '1995'),
            _plaat('g-tl', 'Tigerlily', '1995-06-16'),
          ])),
          'Tigerlily 1995');
    });

    test('alleen een studioalbum: een verzamelaar, live-plaat of soundtrack telt niet', () {
      expect(
          studioalbumUitGroepen([
            (titel: 'Magnolia', groep: 'g-m'),
            (titel: 'Greatest Hits', groep: 'g-gh'),
          ], [
            _plaat('g-m', 'Magnolia', '1999-12-07', ook: ['Soundtrack']),
            _plaat('g-gh', 'Greatest Hits', '2004', ook: ['Compilation']),
          ]),
          isNull);
    });

    test('de editie eraf', () {
      expect(zonderEditie('Private Dancer (30th Anniversary Issue)'), 'Private Dancer');
      expect(zonderEditie('Rumours (2004 Remaster)'), 'Rumours');
      expect(zonderEditie('Woodface - Remastered'), 'Woodface');
      expect(zonderEditie("Summer Of '69 - Single"), "Summer Of '69");
      expect(zonderEditie('Close-Up, Volume 2: People & Places'), 'Close-Up, Volume 2: People & Places');
      expect(zonderEditie('Relish'), 'Relish');
    });
  });

  group('de kandidaten', () {
    Map<String, dynamic> deezer(String artiest, String titel, String album, int duur) => {
          'title': titel,
          'artist': {'name': artiest},
          'album': {'title': album},
          'duration': duur,
        };

    test('Deezer: zonder lengte — de radio-edit van 4:24 staat als 5:24 op het album', () {
      final data = [
        deezer('Sheryl Crow', 'If It Makes You Happy', 'Sheryl Crow', 324),
        deezer('Sheryl Crow', 'If It Makes You Happy (Live)', 'Live from Central Park', 280),
        deezer('MSQ', 'If It Makes You Happy', 'MSQ Performs Sheryl Crow', 264),
      ];
      expect([for (final c in deezerAlbumsMetNummer(data, 'Sheryl Crow', 'If It Makes You Happy', seconden: 264)) c.titel],
          ['Sheryl Crow'],
          reason: 'niet de live-versie en niet een ander die het speelt');
    });

    test('MusicBrainz: ±8 s, want een heropname is een andere opname (Solsbury Hill op New Blood)', () {
      MbRecording opname(int ms, String album) => MbRecording.from({
            'id': 'rec-$album',
            'title': 'Solsbury Hill',
            'length': ms,
            'artist-credit': [
              {'name': 'Peter Gabriel', 'artist': {'id': 'pg'}}
            ],
            'releases': [
              {
                'id': 'r-$album',
                'title': album,
                'status': 'Official',
                'release-group': {'id': 'g-$album', 'primary-type': 'Album', 'secondary-types': <String>[]},
              }
            ],
          });
      final c = albumsMetNummerUitOpnames([opname(273000, 'New Blood'), opname(262000, 'Peter Gabriel')],
          artiest: 'Peter Gabriel', titel: 'Solsbury Hill', seconden: 261);
      expect([for (final k in c) '${k.titel}/${k.groep}'], ['Peter Gabriel/g-Peter Gabriel'],
          reason: 'het id van de plaat gaat mee');
      expect(opname(1, 'x').artistMbid, 'pg', reason: 'het id van de artiest staat in de opname');
    });
  });

  group('de tag komt er ook in', () {
    late Directory map;
    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_tags_later_');
      setAppDirForTest(map.path);
    });
    tearDown(() {
      DownloadManager.tagSchrijver = writeTagFields;
      DownloadManager.naLateTags = null;
      DownloadManager.tagsLaterTussen = const Duration(seconds: 30);
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    DownloadManager beheer() {
      final cfg = AppSettings();
      return DownloadManager(OnlineService(cfg), SoulseekService(cfg), map.path, () async {});
    }

    test('DE KERN: lukt het niet meteen (het nummer speelt), dan later — en dan leest de bibliotheek het opnieuw', () async {
      final f = File('${map.path}${Platform.pathSeparator}Cathedral Song.flac')..writeAsStringSync('x');
      var pogingen = 0;
      final opnieuw = <String>[];
      DownloadManager.tagsLaterTussen = const Duration(milliseconds: 5);
      DownloadManager.tagSchrijver = (file, velden, {waarom}) async {
        pogingen++;
        if (pogingen < 3) {
          waarom?.call('het bestand is in gebruik');
          return false;
        }
        expect(velden['ALBUM'], 'Ancient Heart');
        return true;
      };
      DownloadManager.naLateTags = (pad) async => opnieuw.add(pad);
      final meteen = await beheer().schrijfRadioTags(f.path, {'ALBUM': 'Ancient Heart'}, 'Tanita Tikaram — Cathedral Song');
      expect(meteen, isFalse);
      for (var i = 0; i < 200 && opnieuw.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(pogingen, 3);
      expect(opnieuw, [f.path]);
    });

    test('meteen gelukt: geen tweede poging en geen herlezing; weg bestand: ophouden', () async {
      final f = File('${map.path}${Platform.pathSeparator}Luka.flac')..writeAsStringSync('x');
      var pogingen = 0;
      final opnieuw = <String>[];
      DownloadManager.tagsLaterTussen = const Duration(milliseconds: 5);
      DownloadManager.naLateTags = (pad) async => opnieuw.add(pad);
      DownloadManager.tagSchrijver = (file, velden, {waarom}) async {
        pogingen++;
        return true;
      };
      expect(await beheer().schrijfRadioTags(f.path, {'ALBUM': 'Solitude Standing'}, 'Suzanne Vega — Luka'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(pogingen, 1);
      expect(opnieuw, isEmpty);

      pogingen = 0;
      DownloadManager.tagSchrijver = (file, velden, {waarom}) async {
        pogingen++;
        if (pogingen == 1) f.deleteSync();
        return false;
      };
      expect(await beheer().schrijfRadioTags(f.path, {'ALBUM': 'Solitude Standing'}, 'Suzanne Vega — Luka'), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(pogingen, 1, reason: 'het bestand is weg: niet twintig keer verder proberen');
    });

    test('beide radiowegen schrijven zo, en de TIDAL-weg zoekt het origineel ook op', () {
      final bron = File('lib/online.dart').readAsStringSync();
      expect(RegExp(r'await schrijfRadioTags\(uit\.path, velden, ').allMatches(bron).length, 2,
          reason: 'Soulseek en TIDAL');
      final tidal = bron.substring(bron.indexOf('Future<String?> _radioViaTidal('));
      final romp = tidal.substring(0, tidal.indexOf('\n  }\n'));
      expect(romp, contains('origineleUitgave?.call(artiest, titel, seconden)'));
      expect(romp, contains('album: gevonden.album,'));
      expect(File('lib/main.dart').readAsStringSync(), contains('await library.voegBestandToe(pad);'));
    });
  });
}

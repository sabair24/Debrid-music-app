/// "Uitgave kiezen" en "Metadata bewerken" laden niet langer dan nodig.
///
/// **Waarom.** Saber op 12-10-2026: *"het laden van metadata van musicbrainz bij het kiezen van uitgave
/// en bewerken metadata, gaat echt heel traag"*. Gemeten met een lege cache tegen de echte diensten:
///
/// 1. De uitgavekiezer vroeg Discogs pas als MusicBrainz HELEMAAL klaar was, scans van elke persing
///    inbegrepen: 10,7 s bij Monkey Business, 21,8 s bij Thriller. Discogs zelf had 1,8 tot 2,9 s nodig
///    voor zijn eerste rijen.
/// 2. Van de 40 persingen van Thriller zei MusicBrainz bij 9 zelf al "geen scans"; die werden toch
///    allemaal bij het archief nagevraagd (allemaal 404).
/// 3. Het archief gaf 2 van de 40 scanlijsten terug als 500; zo'n persing stond dan een uur als "geen
///    scans", terwijl hij er 23 had.
/// 4. "Metadata bewerken" toonde niets tot de traagste bron klaar was (Discogs, 5,5 s), terwijl
///    MusicBrainz, Deezer en TheAudioDB er na 0,2 tot 1,3 s al waren.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/metadata.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

/// Een persing zoals de bladerlijst hem geeft. [aantal] is het totaal aantal scans; standaard drie
/// (voorkant, achterkant en nog één), zodat de scanlijst nodig is voor een mogelijke cd-scan.
Map<String, dynamic> _persing(String id,
        {required bool scans, String land = 'US', bool voor = true, bool achter = true, int aantal = 3}) =>
    {
      'id': id,
      'title': 'Thriller',
      'date': '1982-11-30',
      'country': land,
      'status': 'Official',
      'media': [
        {'format': 'CD', 'track-count': 9}
      ],
      'cover-art-archive': {
        'artwork': scans,
        'front': scans && voor,
        'back': scans && achter,
        'count': scans ? aantal : 0,
        'darkened': false,
      },
    };

/// De scanlijst van het archief: een voorkant en een cd.
Map<String, dynamic> _scans(String id) => {
      'images': [
        {
          'image': 'https://coverartarchive.org/release/$id/1.jpg',
          'thumbnails': {'250': 'https://coverartarchive.org/release/$id/1-250.jpg', '1200': 'https://coverartarchive.org/release/$id/1-1200.jpg'},
          'types': ['Front'],
          'front': true,
          'back': false,
        },
        {
          'image': 'https://coverartarchive.org/release/$id/3.jpg',
          'thumbnails': {'250': 'https://coverartarchive.org/release/$id/3-250.jpg', '1200': 'https://coverartarchive.org/release/$id/3-1200.jpg'},
          'types': ['Medium'],
          'front': false,
          'back': false,
        },
      ]
    };

/// Een MusicBrainz met één plaatgroep en de gegeven persingen. Telt wat er bij het archief gevraagd wordt.
MockClient _mb(List<Map<String, dynamic>> persingen, List<String> archief,
        {int Function(String id)? archiefStatus, Future<void>? archiefWacht}) =>
    MockClient((r) async {
      final u = r.url.toString();
      if (u.contains('/release-group/?query=')) {
        return _json({
          'release-groups': [
            {'id': 'rg1', 'title': 'Thriller', 'primary-type': 'Album', 'artist-credit': [{'name': 'Michael Jackson'}]}
          ]
        });
      }
      if (u.contains('/ws/2/release?release-group=rg1')) {
        return _json({'releases': persingen, 'release-count': persingen.length});
      }
      if (r.url.host == 'coverartarchive.org') {
        final id = r.url.pathSegments.last;
        archief.add(id);
        if (archiefWacht != null) await archiefWacht;
        final s = archiefStatus?.call(id) ?? 200;
        return s == 200 ? _json(_scans(id)) : http.Response('fout', s);
      }
      return http.Response('niet nagebootst: $u', 404);
    });

/// Een nagemaakte cd: witte ondergrond, donkere opdruk tot net binnen de rand, een wit gat.
Uint8List _cdPng() {
  final im = img.Image(width: 150, height: 150);
  img.fill(im, color: img.ColorRgb8(250, 250, 250));
  img.fillCircle(im, x: 75, y: 75, radius: 73, color: img.ColorRgb8(30, 30, 30));
  img.fillCircle(im, x: 75, y: 75, radius: 12, color: img.ColorRgb8(250, 250, 250));
  return Uint8List.fromList(img.encodePng(im));
}

void main() {
  setUp(() {
    setAppDirForTest(Directory.systemTemp.createTempSync('dm_uitgaveladen_').path);
    MusicBrainzService.resetLanes();
    MusicBrainzService.busyWacht = (_) async {};
  });
  tearDown(() => MusicBrainzService.busyWacht = Future<void>.delayed);

  group('MusicBrainz zegt zelf welke scans een persing heeft', () {
    test('het veld wordt gelezen; verduisterd telt als geen', () {
      expect(MbRelease.from(_persing('a', scans: true)).heeftScans, isTrue);
      expect(MbRelease.from(_persing('b', scans: false)).heeftScans, isFalse);
      final donker = _persing('c', scans: true)..['cover-art-archive'] = {'artwork': true, 'darkened': true};
      expect(MbRelease.from(donker).heeftScans, isFalse);
      expect(MbRelease.from(_persing('d', scans: true)..remove('cover-art-archive')).heeftScans, isNull,
          reason: 'zonder het veld weten we het niet, en dan wordt het archief gewoon gevraagd');
    });

    test('wanneer de scanlijst iets kan toevoegen: alleen als er meer is dan voor- en achterkant', () {
      bool nodig(Map<String, dynamic> p) => MbRelease.from(p).scanlijstNodig;
      expect(nodig(_persing('a', scans: true, aantal: 3)), isTrue);
      expect(nodig(_persing('b', scans: true, aantal: 2)), isFalse, reason: 'voor + achter = 2');
      expect(nodig(_persing('c', scans: true, achter: false, aantal: 1)), isFalse);
      expect(nodig(_persing('d', scans: true, achter: false, aantal: 2)), isTrue, reason: 'de tweede kan de cd zijn');
      expect(nodig(_persing('e', scans: false)), isFalse);
      expect(nodig(_persing('f', scans: true)..remove('cover-art-archive')), isTrue);
      expect(nodig(_persing('g', scans: true)..['cover-art-archive'] = {'artwork': true, 'front': true}), isTrue,
          reason: 'zonder aantal: vragen');
    });

    test('DE KERN: een persing zonder scans wordt niet bij het archief nagevraagd', () async {
      final archief = <String>[];
      late List<ReleaseChoice> uit;
      await http.runWithClient(() async {
        uit = await MusicBrainzService().editionChoices('Michael Jackson', 'Thriller');
      }, () => _mb([_persing('met', scans: true), _persing('zonder', scans: false, land: 'GB')], archief));
      expect(archief, ['met'], reason: 'bij Thriller waren dat er 9 van de 40, allemaal 404');
      final zonder = uit.firstWhere((c) => c.mbid == 'zonder');
      expect(zonder.detailed, isTrue, reason: 'beantwoord: kruisjes, geen molentje');
      expect(zonder.front, isNull);
      expect(uit.firstWhere((c) => c.mbid == 'met').front, isNotNull);
    });

    test('alleen een voor- en achterkant: ook dan hoeft het archief niets te zeggen', () async {
      final archief = <String>[];
      late List<ReleaseChoice> uit;
      await http.runWithClient(() async {
        uit = await MusicBrainzService().editionChoices('Michael Jackson', 'Thriller');
      }, () => _mb([_persing('twee', scans: true, aantal: 2)], archief));
      expect(archief, isEmpty);
      final r = uit.single;
      expect(r.detailed, isTrue);
      expect(r.front?.uri, 'https://coverartarchive.org/release/twee/front-1200');
      expect(r.front?.thumb, 'https://coverartarchive.org/release/twee/front-250');
      expect(r.back?.uri, 'https://coverartarchive.org/release/twee/back-1200');
      expect(r.disc, isNull, reason: 'er is geen derde scan, dus ook geen cd');
    });

    test('DE KERN: de hoes staat er meteen, nog vóór de scanlijst — en houdt daarna zijn adres', () async {
      final archief = <String>[];
      final lijstMag = Completer<void>();
      final delen = <List<ReleaseChoice>>[];
      late List<ReleaseChoice> uit;
      await http.runWithClient(() async {
        final f = MusicBrainzService().editionChoices('Michael Jackson', 'Thriller', onPartial: delen.add);
        // Pas de lijst geven als de eerste rijen er al zijn.
        while (delen.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        lijstMag.complete();
        uit = await f;
      }, () => _mb([_persing('drie', scans: true)], archief, archiefWacht: lijstMag.future));
      final eerst = delen.first.single;
      expect(eerst.front?.uri, 'https://coverartarchive.org/release/drie/front-1200',
          reason: 'op het vaste adres, zonder op archive.org te wachten');
      expect(eerst.detailed, isFalse, reason: 'de cd is nog niet bekend');
      final klaar = uit.single;
      expect(klaar.front?.uri, eerst.front?.uri, reason: 'een klaargezette hoes wisselt niet van adres');
      expect(klaar.disc?.uri, 'https://coverartarchive.org/release/drie/3-1200.jpg', reason: 'de cd uit de lijst');
    });

    test('geeft het archief niets, dan staat de voorkant er toch', () async {
      final archief = <String>[];
      late List<ReleaseChoice> uit;
      await http.runWithClient(() async {
        uit = await MusicBrainzService().editionChoices('Michael Jackson', 'Thriller');
      }, () => _mb([_persing('stuk', scans: true)], archief, archiefStatus: (_) => 500));
      expect(uit.single.front?.uri, 'https://coverartarchive.org/release/stuk/front-1200');
      expect(uit.single.back?.uri, 'https://coverartarchive.org/release/stuk/back-1200');
    });

    test('DE GRENS: zonder het veld wordt hij wél gevraagd', () async {
      final archief = <String>[];
      await http.runWithClient(() async {
        await MusicBrainzService().editionChoices('Michael Jackson', 'Thriller');
      }, () => _mb([_persing('onbekend', scans: true)..remove('cover-art-archive')], archief));
      expect(archief, ['onbekend']);
    });
  });

  group('het archief zegt "fout" waar het "straks" bedoelt', () {
    test('DE KERN: een 500 van het archief wordt opnieuw gevraagd, en dan is de cd-scan er', () async {
      final archief = <String>[];
      late List<ReleaseChoice> uit;
      await http.runWithClient(() async {
        uit = await MusicBrainzService().editionChoices('Michael Jackson', 'Thriller');
      }, () => _mb([_persing('wankel', scans: true)], archief, archiefStatus: (_) => archief.length == 1 ? 500 : 200));
      expect(archief, ['wankel', 'wankel']);
      expect(uit.single.disc, isNotNull, reason: 'zonder herkansing stond hij een uur als "geen cd-scan"');
    });

    test('ook een 502 en een 504', () async {
      for (final s in [502, 504]) {
        MusicBrainzService.resetLanes();
        setAppDirForTest(Directory.systemTemp.createTempSync('dm_uitgaveladen_').path);
        final archief = <String>[];
        await http.runWithClient(() async {
          await MusicBrainzService().editionChoices('Michael Jackson', 'Thriller');
        }, () => _mb([_persing('x', scans: true)], archief, archiefStatus: (_) => archief.length == 1 ? s : 200));
        expect(archief, hasLength(2), reason: '$s');
      }
    });

    test('DE GRENS: niet eindeloos', () async {
      final archief = <String>[];
      await http.runWithClient(() async {
        await MusicBrainzService().editionChoices('Michael Jackson', 'Thriller');
      }, () => _mb([_persing('stuk', scans: true)], archief, archiefStatus: (_) => 500));
      expect(archief, hasLength(MusicBrainzService.kBusyPogingen));
    });

    test('DE GRENS: een 404 is een antwoord', () async {
      final archief = <String>[];
      await http.runWithClient(() async {
        await MusicBrainzService().editionChoices('Michael Jackson', 'Thriller');
      }, () => _mb([_persing('leeg', scans: true)], archief, archiefStatus: (_) => 404));
      expect(archief, hasLength(1));
    });

    test('DE GRENS: op de MusicBrainz-baan zelf blijft een 500 één vraag, zoals in 3.9.469', () async {
      var vragen = 0;
      await http.runWithClient(() async {
        await MusicBrainzService().searchArtists('Serge Gainsbourg', max: 5);
      }, () => MockClient((r) async {
            vragen++;
            return http.Response('fout', 500);
          }));
      expect(vragen, 1);
    });
  });

  group('de volgorde in de kiezer, nu beide catalogussen tegelijk laden', () {
    ReleaseChoice mb(String id) => ReleaseChoice(source: EditionSource.musicbrainz, mbid: id, format: 'CD');
    ReleaseChoice dg(int id) => ReleaseChoice(source: EditionSource.discogs, releaseId: id, format: 'CD');
    ReleaseChoice adb(int id) => ReleaseChoice(source: EditionSource.audiodb, audioDbId: '$id', format: 'Album');

    test('DE KERN: een late MusicBrainz-rij komt achter de laatste MusicBrainz-rij, niet onder Discogs', () {
      expect(plekVoorMusicBrainz([mb('a'), mb('b'), dg(1), dg(2), dg(3)]), 2);
    });

    test('staat er nog geen, dan bovenaan — maar onder TheAudioDB', () {
      expect(plekVoorMusicBrainz([dg(1), dg(2)]), 0);
      expect(plekVoorMusicBrainz([adb(1), dg(1), dg(2)]), 1);
      expect(plekVoorMusicBrainz([adb(1), mb('a'), dg(1)]), 2);
      expect(plekVoorMusicBrainz(const []), 0);
    });

    test('de voettekst zegt welke nog bezig is', () {
      expect(nogBezigTekst(musicBrainz: true, discogs: true), 'MusicBrainz en Discogs vullen nog aan…');
      expect(nogBezigTekst(musicBrainz: true, discogs: false), 'MusicBrainz vult nog aan…');
      expect(nogBezigTekst(musicBrainz: false, discogs: true), 'Discogs vult nog aan…');
    });

    test('bedrading: tegelijk, MusicBrainz op zijn plek, Discogs wacht op de eerste MusicBrainz-rijen', () {
      final main = File('lib/main.dart').readAsStringSync();
      final laad = main.substring(main.indexOf('// MusicBrainz en Discogs TEGELIJK'));
      final eind = laad.indexOf('Nieuwe rijen erbij, zonder ooit');
      final blok = laad.substring(0, eind);
      expect(blok, contains('await Future.wait([vanMusicBrainz(), vanDiscogs()]);'));
      expect(RegExp(r'_merge\((l|mb), naMusicBrainz: true\)').allMatches(blok).length, 2);
      expect(blok, contains('dgWacht = l;'), reason: 'Discogs-rijen wachten tot MusicBrainz ze voor is');
      expect(blok, contains('Future<void>.delayed(_dgWachtOpMb)'), reason: 'maar niet eindeloos');
      expect(main, contains('final k = naMusicBrainz ? plekVoorMusicBrainz(huidig) : huidig.length;'));
      expect(main, contains('static const _detailTegelijk = 2;'));
      expect(main, contains("bewaarScanmatenIn(appFile('scanmaten.json'));"));
    });
  });

  group('"Metadata bewerken" toont wat er is, zodra het er is', () {
    test('DE KERN: de snelle bronnen staan er voor de trage klaar is', () async {
      final mbKlaar = Completer<void>();
      final delen = <List<MetaResult>>[];
      var mbAlBinnen = false;
      late List<MetaResult> eind;
      await http.runWithClient(() async {
        eind = await MetadataSearch(AppSettings()).search('Alles', 'Michael Jackson Thriller',
            artist: 'Michael Jackson', album: 'Thriller', onDeel: (l) {
          delen.add(l);
          if (mbKlaar.isCompleted) mbAlBinnen = true;
        });
      }, () => MockClient((r) async {
            if (r.url.host == 'musicbrainz.org') {
              // De trage: pas na de rest.
              await Future<void>.delayed(const Duration(milliseconds: 300));
              if (!mbKlaar.isCompleted) mbKlaar.complete();
              return r.url.path.contains('/release/')
                  ? _json({
                      'releases': [
                        {'id': 'mb1', 'title': 'Thriller', 'artist-credit': [{'name': 'Michael Jackson'}]}
                      ]
                    })
                  : _json({'recordings': []});
            }
            if (r.url.host == 'api.deezer.com') {
              return _json({
                'data': [
                  {'id': 1, 'title': 'Thriller', 'artist': {'name': 'Michael Jackson'}, 'cover_big': 'https://x/c.jpg'}
                ]
              });
            }
            return http.Response('niets', 404);
          }));
      final eerste = delen.firstWhere((l) => l.isNotEmpty);
      expect(eerste.any((m) => m.mbid == 'mb1'), isFalse, reason: 'Deezer stond er al vóór MusicBrainz antwoordde');
      expect(mbAlBinnen, isTrue);
      expect(delen.length, 4, reason: 'één tussenstand per bron');
      expect([for (final m in eind) m.mbid ?? m.album], [for (final m in delen.last) m.mbid ?? m.album],
          reason: 'de laatste tussenstand is het eindantwoord');
      expect(eind.first.mbid, 'mb1', reason: 'en de volgorde blijft: MusicBrainz vóór Deezer');
    });

    test('bedrading: een tussenstand van een oude zoekopdracht overschrijft de nieuwe niet', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('if (mounted && ronde == _zoekRonde) setState(() => _results = totNu);'));
      expect(main, contains('child: _searching && _results.isEmpty'),
          reason: 'de molen alleen zolang er nog niets staat');
    });
  });

  // Op het scherm gezien op de pc, 12-10-2026, bij "1, 2, 3 Soleils": rijen zonder "primary"-beeld bij
  // Discogs toonden hetzelfde beeld als hoes én als achterkant, met "✓ achterkant". Nagevraagd bij
  // Discogs: 16907574 en 4890343 hebben één beeld, 11728335 heeft er vier, allemaal "secondary".
  group('Discogs zonder hoofdbeeld', () {
    Map<String, dynamic> beeld(int n, int w, int h) => {
          'type': 'secondary',
          'uri': 'https://i.discogs.com/$n.jpg',
          'uri150': 'https://i.discogs.com/$n-150.jpg',
          'width': w,
          'height': h,
        };
    Future<ReleaseChoice?> zoekOp(List<Map<String, dynamic>> beelden, {Set<int> cds = const {}}) async {
      late ReleaseChoice? uit;
      await http.runWithClient(() async {
        uit = await DiscogsService(AppSettings()..discogsToken = 'proef')
            .detailOf(ReleaseChoice(source: EditionSource.discogs, releaseId: 42, format: 'CD'));
      }, () => MockClient((r) async {
            if (r.url.path == '/releases/42') {
              return _json({'id': 42, 'title': '1, 2, 3 Soleils', 'images': beelden, 'tracklist': []});
            }
            // De miniaturen voor de cd-herkenning: een nagemaakte cd voor wie in [cds] staat.
            final nr = int.tryParse(RegExp(r'/(\d+)-150\.jpg$').firstMatch(r.url.path)?.group(1) ?? '');
            if (nr != null && cds.contains(nr)) return http.Response.bytes(_cdPng(), 200);
            return http.Response('geen beeld', 404);
          }));
      return uit;
    }

    test('DE KERN: één beeld is de hoes, en er is geen achterkant', () async {
      final d = await zoekOp([beeld(1, 600, 600)]);
      expect(d?.front?.uri, 'https://i.discogs.com/1.jpg');
      expect(d?.front?.breedte, 600);
      expect(d?.back, isNull, reason: 'in 3.9.471 stond hier dezelfde hoes, met "✓ achterkant"');
    });

    test('vier beelden: het eerste is de hoes, de achterkant is een ander', () async {
      final d = await zoekOp([beeld(1, 592, 600), beeld(2, 600, 463), beeld(3, 590, 600), beeld(4, 569, 585)]);
      expect(d?.front?.uri, 'https://i.discogs.com/1.jpg');
      expect(d?.back, isNotNull);
      expect(d?.back?.uri, isNot(d?.front?.uri));
    });

    // Op vorm, zoals de albumpagina: een achterinlay is 1,1 tot 1,5 keer zo breed als de hoes. De kiezer
    // nam "breder dan 1,4" en anders het eerste beeld dat over was. Echte vormen van Discogs, nagekeken op
    // de miniaturen (12-10-2026): telkens is het gekozen beeld de achterinlay met de tracklijst.
    test('DE VAL: Rusland (9321705) — niet de cd, maar de achterinlay', () async {
      final d = await zoekOp([beeld(1, 494, 480), beeld(2, 498, 480), beeld(3, 559, 480)]);
      expect(d?.back?.uri, 'https://i.discogs.com/3.jpg', reason: 'beeld 2 is de roze cd');
    });

    test('DE VAL: Purple Rain (11798563) — niet de binnenkant van het boekje', () async {
      final d = await zoekOp([beeld(1, 600, 597), beeld(2, 600, 596), beeld(3, 600, 471), beeld(4, 600, 450)]);
      expect(d?.back?.uri, 'https://i.discogs.com/3.jpg');
    });

    test('DE VAL: Venezuela (32121567) — niet het opengeklapte doosje van 2,14', () async {
      final d = await zoekOp(
          [{...beeld(1, 600, 517), 'type': 'primary'}, beeld(2, 600, 517), beeld(3, 600, 281), beeld(4, 561, 600)]);
      expect(d?.front?.uri, 'https://i.discogs.com/1.jpg');
      expect(d?.back?.uri, 'https://i.discogs.com/2.jpg');
    });

    test('DE GRENS: een dubbele boekjespagina vóór de inlay is niet de achterkant', () async {
      // Random Access Memories (Discogs 28622347): hoes 1,33, spread 2,04, inlay 1,30 — zie artwork.dart.
      final d = await zoekOp(
          [{...beeld(1, 600, 450), 'type': 'primary'}, beeld(2, 600, 294), beeld(3, 600, 462)]);
      expect(d?.back?.uri, 'https://i.discogs.com/3.jpg');
    });

    test('DE VAL: een cd in zijn doosje (vorm 1,14) is de cd, en niet de achterkant', () async {
      // Discogs 36004678 heeft zo'n foto van 600×525. Werd de achterkant op vorm gekozen vóór er naar
      // cd's gekeken werd, dan was dit de "achterinlay" en kwam hij als cd nooit meer aan bod.
      final d = await zoekOp(
          [{...beeld(1, 600, 600), 'type': 'primary'}, beeld(2, 600, 525), beeld(3, 600, 471)], cds: {2});
      expect(d?.disc?.uri, 'https://i.discogs.com/2.jpg');
      expect(d?.back?.uri, 'https://i.discogs.com/3.jpg');
    });

    test('DE GRENS: met een primary blijft die de hoes', () async {
      final d = await zoekOp([beeld(1, 600, 471), {...beeld(2, 600, 600), 'type': 'primary'}]);
      expect(d?.front?.uri, 'https://i.discogs.com/2.jpg');
      expect(d?.back?.uri, 'https://i.discogs.com/1.jpg');
    });
  });
}

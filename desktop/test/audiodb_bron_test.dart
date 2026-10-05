/// TheAudioDB als bron die je zelf kiest, in "Metadata corrigeren" en "Uitgave kiezen".
///
/// Saber op 04-10-2026, bij *Brave* van Jennifer Lopez: *"waar is the audiodb eigenlijk ?? ik wil
/// daar ook alles kunnen selecteren voor de metadata. dit is ook een heel grote database met hoge
/// resolutie. ik heb ook een api key"*.
///
/// Gemeten die dag: de hoes 700×700, de HQ-hoes 2160×2160 (niet bij elk album), de cd 1000×1000; en
/// `track.php` gaf met de gratis sleutel één nummer van de veertien. De antwoorden hieronder hebben
/// de vorm van wat TheAudioDB die dag echt teruggaf.
///
/// En twee dingen die stil mis zouden gaan zonder deze toets:
///   * bij v1 zit je sleutel IN het adres, en een netwerkfout van het http-pakket zet dat adres in zijn
///     tekst — die tekst mag nergens terechtkomen;
///   * "Uitgave kiezen" haalde alles wat niet van het Cover Art Archive kwam via Discogs, mét je
///     Discogs-token. Een TheAudioDB-scan zou dat token naar TheAudioDB gestuurd hebben.
library;

import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/audiodb.dart';
import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/main.dart' show UitgaveRij;
import 'package:debridmusic/metadata.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _sleutel = 'GEHEIM-PREMIUM-42';

/// *Brave*, zoals `searchalbum.php` het die dag gaf (ingekort tot de velden die ertoe doen).
Map<String, dynamic> _brave({bool hq = false}) => {
      'idAlbum': '2109622',
      'idArtist': '112884',
      'strAlbum': 'Brave',
      'strArtist': 'Jennifer Lopez',
      'intYearReleased': '2007',
      'strGenre': 'Pop',
      'strLabel': 'Epic',
      'strReleaseFormat': 'Album',
      'strAlbumThumb': 'https://r2.theaudiodb.com/images/media/album/thumb/stwxwy1367240457.jpg',
      'strAlbumThumbHQ': hq ? 'https://r2.theaudiodb.com/images/media/album/thumbhq/brave-hq.jpg' : null,
      'strAlbumBack': 'https://r2.theaudiodb.com/images/media/album/back/uruspx1558632528.jpg',
      'strAlbumCDart': 'https://r2.theaudiodb.com/images/media/album/cdart/xtrryq1558632553.png',
      'strAlbumSpine': null,
      'strAlbum3DCase': '',
      'strMusicBrainzID': '5e83a702-05f3-368e-b993-0bd4ac5a48f6',
    };

Map<String, dynamic> _nummer(int cd, int nr, String titel, int ms) => {
      'idTrack': '$cd$nr',
      'strTrack': titel,
      'strArtist': 'Jennifer Lopez',
      'intCD': '$cd',
      'intTrackNumber': '$nr',
      'intDuration': '$ms',
    };

/// Een nagebootste TheAudioDB die bijhoudt wat er gevraagd werd.
MockClient _server(List<http.Request> gevraagd, {bool hq = false}) => MockClient((r) async {
      gevraagd.add(r);
      final pad = r.url.path;
      if (pad.endsWith('/searchalbum.php') || pad.endsWith('/album.php')) {
        return http.Response(jsonEncode({'album': [_brave(hq: hq)]}), 200);
      }
      if (pad.endsWith('/track.php')) {
        return http.Response(
            jsonEncode({
              'track': [
                _nummer(1, 2, 'Do It Well', 185000),
                _nummer(1, 1, 'Stay Together', 210026),
              ]
            }),
            200);
      }
      return http.Response('{}', 404);
    });

AppSettings _met({String sleutel = ''}) => AppSettings()..audiodbKey = sleutel;

void main() {
  group('TheAudioDB lezen', () {
    test('DE KERN: een album wordt een rij met hoes, achterkant en cd — volledig, zonder persing', () {
      final a = AudioDbAlbum.vanJson(_brave())!;
      final k = a.keuze();
      expect(k.source, EditionSource.audiodb);
      expect(k.key, 'adb:2109622', reason: 'zonder eigen sleutel heette elke rij "dg:0" en bleef er één over');
      expect(k.front?.uri, endsWith('stwxwy1367240457.jpg'));
      expect(k.front?.thumb, endsWith('stwxwy1367240457.jpg/small'), reason: '240 pixels voor de rij');
      expect(k.hasBack && k.hasDisc, isTrue);
      expect(k.detailed, isTrue, reason: 'er valt niets na te zoeken: alles stond in het ene antwoord');
      expect(k.releaseId, 0);
      expect(k.mbid, isNull,
          reason: 'het MusicBrainz-nummer van TheAudioDB is van het ALBUM, niet van een persing');
      expect(k.bronNaam, 'TheAudioDB');
      expect(a.regel, 'Album · 2007 · Epic');
    });

    test('de HQ-hoes gaat voor als die er is — 2160 tegen 700', () {
      final a = AudioDbAlbum.vanJson(_brave(hq: true))!;
      expect(a.besteHoes, endsWith('brave-hq.jpg'));
      expect(a.alleScans.map((s) => s.uri), contains(endsWith('stwxwy1367240457.jpg')),
          reason: 'de gewone hoes blijft kiesbaar in "Alle scans"');
    });

    test('DE GRENS: lege velden en "null" als tekst zijn geen scans', () {
      final a = AudioDbAlbum.vanJson({..._brave(), 'strAlbumBack': 'null', 'strAlbumCDart': ''})!;
      expect(a.achter, isNull);
      expect(a.cd, isNull);
      expect(a.alleScans, hasLength(1));
    });
  });

  group('vragen', () {
    test('DE KERN: zonder eigen sleutel de gratis — in het adres, want zo wil v1 het', () async {
      final gevraagd = <http.Request>[];
      final l = await AudioDbService(_met(), client: _server(gevraagd)).zoek('Jennifer Lopez', 'Brave');
      expect(l.single.titel, 'Brave');
      expect(gevraagd.single.url.path, '/api/v1/json/123/searchalbum.php');
      expect(gevraagd.single.url.queryParameters, {'s': 'Jennifer Lopez', 'a': 'Brave'});
    });

    test('met eigen sleutel die', () async {
      final gevraagd = <http.Request>[];
      await AudioDbService(_met(sleutel: _sleutel), client: _server(gevraagd)).zoek('Jennifer Lopez', 'Brave');
      expect(gevraagd.single.url.path, '/api/v1/json/$_sleutel/searchalbum.php');
    });

    test('DE GRENS: zonder artiest of album wordt er niets gevraagd — TheAudioDB geeft dan niets', () async {
      final gevraagd = <http.Request>[];
      final svc = AudioDbService(_met(), client: _server(gevraagd));
      expect(await svc.zoek('', 'Brave'), isEmpty);
      expect(await svc.zoek('Jennifer Lopez', ' '), isEmpty);
      expect(gevraagd, isEmpty);
    });

    test('DE KERN: de tracklijst alleen met eigen sleutel — de gratis gaf er één van de veertien', () async {
      final gevraagd = <http.Request>[];
      expect(() => AudioDbService(_met(), client: _server(gevraagd)).nummers('2109622'),
          throwsA(isA<AudioDbSleutelNodig>()));
      expect(gevraagd, isEmpty, reason: 'niet eens vragen: een lijst van één nummer is erger dan geen');

      final l = await AudioDbService(_met(sleutel: _sleutel), client: _server(gevraagd)).nummers('2109622');
      expect([for (final t in l) '${t.position} ${t.title} ${t.seconds}'],
          ['1 Stay Together 210', '2 Do It Well 185'],
          reason: 'op volgorde, en de duur van milliseconden naar seconden');
    });

    test('twee schijven: 1-1 … 2-1, zoals de rest van de app nummert', () async {
      final svc = AudioDbService(_met(sleutel: _sleutel), client: MockClient((r) async {
        return http.Response(
            jsonEncode({
              'track': [_nummer(2, 1, 'B', 1000), _nummer(1, 1, 'A', 1000)]
            }),
            200);
      }));
      final l = await svc.nummers('1');
      expect([for (final t in l) '${t.position}/${t.disc}'], ['1-1/1', '2-1/2']);
    });

    test('DE VAL: een netwerkfout lekt je sleutel niet — het adres staat nergens in de melding', () async {
      final svc = AudioDbService(_met(sleutel: _sleutel), client: MockClient((r) async {
        throw http.ClientException('verbinding verbroken', r.url);
      }));
      Object? fout;
      try {
        await svc.zoek('Jennifer Lopez', 'Brave');
      } catch (e) {
        fout = e;
      }
      expect(fout, isA<AudioDbFout>());
      expect('$fout', isNot(contains(_sleutel)),
          reason: 'de tekst van een ClientException bevat het adres, en bij v1 zit de sleutel erin');
      expect('$fout', isNot(contains('theaudiodb.com/api')));
    });

    test('een weigering of te veel vragen zegt wat er is, ook zonder sleutel in de tekst', () async {
      for (final (code, woord) in [(429, 'minuut'), (403, 'sleutel'), (500, '500')]) {
        final svc = AudioDbService(_met(sleutel: _sleutel),
            client: MockClient((_) async => http.Response('nee', code)));
        final e = await svc.zoek('a', 'b').then<Object?>((_) => null, onError: (Object e) => e);
        expect('$e', contains(woord));
        expect('$e', isNot(contains(_sleutel)));
      }
    });

    test('de sleutel testen gaat via een KOPREGEL, niet via een adres', () async {
      final gevraagd = <http.Request>[];
      final svc = AudioDbService(_met(sleutel: _sleutel), client: MockClient((r) async {
        gevraagd.add(r);
        return http.Response('{"lookup":[]}', 200);
      }));
      expect(await svc.sleutelWerkt(), isTrue);
      expect(gevraagd.single.headers['X-API-KEY'], _sleutel);
      expect(gevraagd.single.url.toString(), isNot(contains(_sleutel)));
    });
  });

  group('wie een scan ophaalt', () {
    test('DE KERN: elke scan naar zijn eigen dienst', () {
      expect(scanBronVan('https://coverartarchive.org/release/x/front-1200'), ScanBron.coverArtArchive);
      expect(scanBronVan('https://ia800.us.archive.org/x/y.jpg'), ScanBron.coverArtArchive);
      expect(scanBronVan('https://i.discogs.com/abc.jpg'), ScanBron.discogs);
      expect(scanBronVan('https://r2.theaudiodb.com/images/media/album/thumb/x.jpg'), ScanBron.anders);
      expect(scanBronVan('https://discogs.com.ergens-anders.net/x.jpg'), ScanBron.anders,
          reason: 'een adres dat op Discogs LIJKT krijgt het token niet');
    });

    test('DE VAL: Discogs zet zijn token alleen in een vraag aan Discogs', () async {
      final koppen = <String, Map<String, String>>{};
      await http.runWithClient(() async {
        final dg = DiscogsService(AppSettings()..discogsToken = 'DG-TOKEN');
        await dg.fetchImage('https://r2.theaudiodb.com/images/media/album/thumb/x.jpg');
        await dg.fetchImage('https://i.discogs.com/x.jpg');
      }, () => MockClient((r) async {
            koppen[r.url.host] = r.headers;
            return http.Response('', 404);
          }));
      expect(koppen['r2.theaudiodb.com']?['Authorization'], isNull,
          reason: 'je Discogs-token hoort niet bij TheAudioDB terecht te komen');
      expect(koppen['i.discogs.com']?['Authorization'], 'Discogs token=DG-TOKEN');
    });

    test('een TheAudioDB-beeld gaat zonder sleutel en zonder token', () async {
      final gevraagd = <http.Request>[];
      await AudioDbService(_met(sleutel: _sleutel), client: MockClient((r) async {
        gevraagd.add(r);
        return http.Response.bytes(List<int>.filled(800, 1), 200);
      })).beeld('https://r2.theaudiodb.com/images/media/album/thumb/x.jpg');
      expect(gevraagd.single.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
      expect(gevraagd.single.headers.values, isNot(contains(_sleutel)));
    });
  });

  group('"Metadata corrigeren"', () {
    test('DE KERN: TheAudioDB staat in de lijst, Deezer blijft achteraan', () {
      expect(MetadataSearch.providers, contains('TheAudioDB'));
      expect(MetadataSearch.providers.last, 'Deezer');
    });

    test('DE VAL: kies je TheAudioDB, dan vraag je TheAudioDB — niet stil Deezer', () async {
      final gevraagd = <http.Request>[];
      final zoek = MetadataSearch(_met(),
          audiodb: AudioDbService(_met(), client: _server(gevraagd, hq: true)));
      final uit = await zoek.search('TheAudioDB', 'Jennifer Lopez Brave',
          artist: 'Jennifer Lopez', album: 'Brave');
      expect(uit, hasLength(1));
      final m = uit.single;
      expect(m.audioDbId, '2109622');
      expect(m.coverFullUrl, endsWith('brave-hq.jpg'), reason: 'de HQ-hoes is wat bewaard wordt');
      expect(m.coverUrl, endsWith('brave-hq.jpg/small'));
      expect(m.detail, 'TheAudioDB · Album · 2007 · Epic · HQ-hoes');
      expect(m.releaseId, isNull);
      expect(m.mbid, isNull);
      expect(gevraagd.single.url.host, 'www.theaudiodb.com');
    });

    test('een single: de artiest gaat van de zoekregel af', () async {
      final gevraagd = <http.Request>[];
      await MetadataSearch(_met(), audiodb: AudioDbService(_met(), client: _server(gevraagd)))
          .search('TheAudioDB', 'Jennifer Lopez Hold It Don\'t Drop It', track: true, artist: 'Jennifer Lopez');
      expect(gevraagd.single.url.queryParameters, {'s': 'Jennifer Lopez', 'a': 'Hold It Don\'t Drop It'});
    });

    test('de tracklijst van een TheAudioDB-regel komt van TheAudioDB', () async {
      final zoek = MetadataSearch(_met(sleutel: _sleutel),
          audiodb: AudioDbService(_met(sleutel: _sleutel), client: _server([])));
      final l = await zoek.tracklistVan(MetadataSearch.audioDbRegel(AudioDbAlbum.vanJson(_brave())!));
      expect(l.map((t) => t.title), ['Stay Together', 'Do It Well']);
    });

    test('"Alles" vraagt TheAudioDB mee', () {
      final bron = File('lib/metadata.dart').readAsStringSync();
      expect(bron, contains("veilig('TheAudioDB')"));
    });
  });

  group('"Uitgave kiezen"', () {
    testWidgets('DE KERN: een TheAudioDB-rij heet TheAudioDB, niet Discogs, en heeft geen r-nummer',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: SizedBox(
            width: 1000,
            child: ListView(children: [
              UitgaveRij(
                uitgave: AudioDbAlbum.vanJson(_brave())!.keuze(),
                onKiezen: () {},
                onScans: () {},
                onNummering: () {},
                onKlaarzetten: (_, __, ___) {},
              ),
            ]),
          ),
        ),
      ));
      expect(find.text('TheAudioDB'), findsOneWidget);
      expect(find.text('Discogs'), findsNothing);
      expect(find.text('r0'), findsNothing);
    });

    test('DE VAL: geen enkele scan meer via "Cover Art Archive of anders Discogs"', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, isNot(contains("front.uri.contains('coverartarchive.org')")));
      expect(main, isNot(contains('await DiscogsService(settings).fetchImage(c.front!.uri)')));
      expect(RegExp(r'await haalScan\(').allMatches(main).length, greaterThanOrEqualTo(2),
          reason: 'opslaan én kiezen');
      expect(main, contains('EditionSource.audiodb =>'), reason: '"Alle scans" kent TheAudioDB');
    });

    test('de kiezer vraagt TheAudioDB, en zet die rij bovenaan', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('adb.zoek(widget.album.artist, widget.album.title)'));
      expect(main, contains('_merge([for (final a in l) a.keuze()], opIndex: 0)'),
          reason: 'bovenaan, niet waar hij toevallig binnenkwam');
    });

    test('kiezen zet geen persing vast — een album van TheAudioDB is er geen', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('discogsRelease: c.isDiscogs ? c.releaseId : null'));
    });
  });

  group('de sleutel', () {
    test('wordt bewaard en weer gelezen', () {
      final s = AppSettings()..audiodbKey = _sleutel;
      final j = s.toJson();
      expect(j['audiodb_key'], _sleutel);
      final terug = AppSettings()..applyJson(j);
      expect(terug.audiodbKey, _sleutel);
    });

    test('gaat mee naar de telefoon, en weer weg bij ontkoppelen', () {
      final pc = File('lib/lan/server.dart').readAsStringSync();
      final tel = File('lib/lan/client_session.dart').readAsStringSync();
      expect(pc, contains("'audiodbKey': config.audiodbKey"));
      expect(tel, contains("settings.audiodbKey = audiodb"));
      expect(tel, contains("settings.audiodbKey = '';"));
    });
  });

  // Saber op 05-10-2026, bij *Au cœur de moi*: "the audio db vindt niet alles ?". De site toonde het
  // album, de kiezer niet. Gemeten: TheAudioDB kent de artiest als "Amir Haddad", de bibliotheek als
  // "Amir" — en `searchalbum.php?s=Amir&a=Au cœur de moi` gaf `{"album":null}`.
  group('als TheAudioDB de naam anders schrijft', () {
    Map<String, dynamic> auCoeur() => {
          'idAlbum': '2265602',
          'idArtist': '143382',
          'strAlbum': 'Au cœur de moi',
          'strArtist': 'Amir Haddad',
          'intYearReleased': '2016',
          'strAlbumThumb': 'https://r2.theaudiodb.com/images/media/album/thumb/aucoeur.jpg',
          'strMusicBrainzID': 'c5b37466-1e2f-468e-856e-264e7ffcfb38',
        };
    Map<String, dynamic> album(String titel, String id) => {...auCoeur(), 'strAlbum': titel, 'idAlbum': id};

    /// TheAudioDB zoals die dag: alleen "Amir Haddad" vindt het album; "Amir" geeft de artiest terug.
    MockClient amir(List<String> gevraagd, {List<Map<String, dynamic>>? discografie, bool opNaam = true}) =>
        MockClient((r) async {
          final pad = r.url.pathSegments.last;
          final q = r.url.queryParameters;
          gevraagd.add('$pad ${q.values.join('|')}');
          // In UTF-8, zoals TheAudioDB het stuurt: `http.Response(tekst)` codeert als Latin-1, en daar
          // bestaat "œ" niet in.
          http.Response antwoord(Object? v) => http.Response.bytes(utf8.encode(jsonEncode(v)), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
          if (pad == 'searchalbum.php') {
            final raak = opNaam && q['s'] == 'Amir Haddad' && q['a'] == 'Au cœur de moi';
            return antwoord({'album': raak ? [auCoeur()] : null});
          }
          if (pad == 'search.php') {
            return antwoord({
              'artists': [
                {'idArtist': '143382', 'strArtist': 'Amir Haddad'}
              ]
            });
          }
          if (pad == 'album.php' && q['i'] == '143382') {
            return antwoord({'album': discografie ?? [auCoeur()]});
          }
          if (pad == 'album-mb.php') {
            final raak = q['i'] == 'c5b37466-1e2f-468e-856e-264e7ffcfb38';
            return antwoord({'album': raak ? [auCoeur()] : null});
          }
          return http.Response('{}', 404);
        });

    test('DE KERN: "Amir" vindt het album via de naam die TheAudioDB zelf gebruikt', () async {
      final gevraagd = <String>[];
      final l = await AudioDbService(_met(), client: amir(gevraagd)).zoek('Amir', 'Au cœur de moi');
      expect(l.map((a) => a.titel), ['Au cœur de moi'], reason: 'de site had het, de kiezer niet');
      expect(gevraagd, [
        'searchalbum.php Amir|Au cœur de moi',
        'search.php Amir',
        'searchalbum.php Amir Haddad|Au cœur de moi',
      ]);
    });

    test('DE VAL: "coeur" zonder ligatuur vindt "cœur" — via de albums van de artiest', () async {
      final gevraagd = <String>[];
      final l = await AudioDbService(_met(),
              client: amir(gevraagd, discografie: [album('Addictions', '1'), auCoeur()]))
          .zoek('Amir', 'Au coeur de moi');
      expect(l.map((a) => a.id), ['2265602']);
      expect(gevraagd.last, 'album.php 143382');
    });

    test('vindt de eerste vraag iets, dan wordt er niets meer gevraagd', () async {
      final gevraagd = <String>[];
      await AudioDbService(_met(), client: amir(gevraagd)).zoek('Amir Haddad', 'Au cœur de moi');
      expect(gevraagd, hasLength(1));
    });

    test('DE GRENS: zonder haakjes vergelijken, maar alleen als er dan precies één overblijft', () {
      AudioDbAlbum a(String t, String id) => AudioDbAlbum(id: id, artiest: 'X', titel: t);
      expect(AudioDbService.kiesOpTitel([a('Brave (Deluxe)', '1'), a('Rebirth', '2')], 'Brave').map((x) => x.id),
          ['1']);
      expect(AudioDbService.kiesOpTitel([a('Hits (Vol. 1)', '1'), a('Hits (Vol. 2)', '2')], 'Hits'), isEmpty,
          reason: 'twee albums die alleen in het deelnummer verschillen: daar raden we niet tussen');
      expect(AudioDbService.kiesOpTitel([a('Hits (Vol. 1)', '1'), a('Hits (Vol. 2)', '2')], 'Hits (Vol. 2)')
          .map((x) => x.id), ['2'], reason: 'met het deelnummer is het wél één');
      expect(AudioDbService.kiesOpTitel([a('Cœur (Vol. 1)', '1'), a('Cœur (Vol. 2)', '2')], 'Coeur (Vol. 2)')
          .map((x) => x.id), ['2'],
          reason: 'accenten gelijk trekken MET de haakjes erbij — anders zijn het er weer twee');
    });

    test('DE KERN: via het MusicBrainz-nummer doet de naam niet mee', () async {
      final gevraagd = <String>[];
      final l = await AudioDbService(_met(), client: amir(gevraagd, opNaam: false))
          .viaMusicBrainz(['c5b37466-1e2f-468e-856e-264e7ffcfb38', 'c5b37466-1e2f-468e-856e-264e7ffcfb38', ' ']);
      expect(l.map((a) => a.titel), ['Au cœur de moi']);
      expect(gevraagd, hasLength(1), reason: 'hetzelfde nummer twee keer en een leeg nummer: één vraag');
    });

    test('"Uitgave kiezen" vraagt via MusicBrainz zodra die de albumnummers noemt', () {
      final main = File('lib/main.dart').readAsStringSync();
      final mb = File('lib/musicbrainz.dart').readAsStringSync();
      expect(main, contains('onPartial: _merge, onGroepen: viaGroepen'));
      expect(main, contains('adb.viaMusicBrainz(groepen)'));
      expect(mb, contains('onGroepen?.call('));
    });
  });
}

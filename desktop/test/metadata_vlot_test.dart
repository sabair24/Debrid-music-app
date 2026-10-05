/// "Metadata corrigeren moet snel en moeiteloos zijn" — Saber, 05-10-2026.
///
/// **Gemeten die dag.** Op de telefoon stond "Alles" voor Oasis — *(What's The Story) Morning
/// Glory?* — 7 s te zoeken voor er één rij verscheen. Per bron gemeten op de pc, met een lege
/// cache: Deezer en TheAudioDB 0,1–0,5 s, Discogs 3–4 s, MusicBrainz 6,8 s. En MusicBrainz deed in
/// die 6,8 s vooral iets wat niet hoefde: zijn liedjestak wist niet wie de artiest was en probeerde
/// elk begin van de zoekregel als artiestnaam — "Oasis (What's The Story) Morning", "Oasis (What's
/// The Story)", … tot "Oasis" — één vraag per seconde, terwijl "Oasis" in het venster al in het veld
/// Artiest stond. Daarnaast wachtten twee Discogs-vragen die niet over de baan lopen op drie die dat
/// wel doen. Na de reparatie: "Alles" koud in 2,5–3,7 s, met dezelfde rijen (95 voor Oasis).
///
/// Deze toets raakt het net niet: een nagebootst net legt vast wélke vragen er gaan, en in welke
/// volgorde.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:debridmusic/metadata.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

const _artiest = 'Oasis';
const _album = "(What's The Story) Morning Glory?";

/// Elke vraag die de zoeker stelt, in volgorde. Het antwoord is "niets gevonden", tenzij [antwoord]
/// er een heeft.
Future<List<Uri>> _vragen(Future<void> Function() zoek, {Object? Function(Uri)? antwoord}) async {
  final vragen = <Uri>[];
  await http.runWithClient(zoek, () => MockClient((r) async {
        vragen.add(r.url);
        return http.Response(
            jsonEncode(antwoord?.call(r.url) ??
                {'results': [], 'versions': [], 'releases': [], 'recordings': [], 'artists': []}),
            200);
      }));
  return vragen;
}

/// Discogs kent één master van de plaat, met één cd-persing.
Object? _eenPersing(Uri u) {
  if (u.host != 'api.discogs.com') return null;
  if (u.path == '/database/search' && u.queryParameters['type'] == 'master') {
    return {
      'results': [
        {'id': 52220, 'type': 'master', 'title': 'Oasis - $_album', 'format': ['Album']},
      ],
    };
  }
  if (u.path == '/masters/52220/versions') {
    return {
      'pagination': {'pages': 1, 'items': 1},
      'versions': [
        {'id': 368542, 'format': 'CD, Album', 'major_formats': ['CD'], 'country': 'UK', 'catno': 'CRECD 189', 'released': '1995'},
      ],
    };
  }
  return null;
}

void main() {
  setUp(() {
    // Een eigen map per toets: MusicBrainz en Discogs onthouden antwoorden op schijf, ook "niets".
    setAppDirForTest(Directory.systemTemp.createTempSync('dm_vlot_').path);
    MusicBrainzService.resetLanes();
  });

  group('MusicBrainz', () {
    test('DE KERN: staat de artiest al in het venster, dan wordt hij niet geraden', () async {
      final vragen = await _vragen(() => MetadataSearch(AppSettings())
          .search('MusicBrainz', '$_artiest $_album', artist: _artiest, album: _album));
      final paden = vragen.map((u) => u.path).toList();
      expect(paden.where((p) => p.startsWith('/ws/2/artist')), isEmpty,
          reason: 'de liedjestak raadt weer de artiest — één vraag per seconde per woord, 7 s voor '
              'Oasis terwijl "Oasis" al in het veld Artiest stond');
      final opname = vragen.firstWhere((u) => u.path.startsWith('/ws/2/recording'),
          orElse: () => fail('de liedjestak vroeg MusicBrainz niets meer'));
      expect(opname.queryParameters['query'], contains('artist:"Oasis"'),
          reason: 'zonder artiest zoekt hij het hele album als één liedjestitel');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('DE VAL: begint de zoekregel níét met die artiest, dan raadt hij zoals vroeger', () async {
      // Wie de zoekregel zelf herschrijft, bedoelt iets anders dan de velden; "Morning Glory Oasis"
      // mag niet stilletjes als liedje "Morning Glory Oasis" van Oasis gezocht worden.
      final vragen = await _vragen(() => MetadataSearch(AppSettings())
          .search('MusicBrainz', 'Morning Glory Oasis', artist: _artiest, album: _album));
      expect(vragen.where((u) => u.path.startsWith('/ws/2/artist')), isNotEmpty);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('DE GRENS: "Oasisfan Live" is geen zoekregel die met Oasis begint', () async {
      final vragen = await _vragen(() => MetadataSearch(AppSettings())
          .search('MusicBrainz', 'Oasisfan Live', artist: _artiest, album: _album));
      expect(vragen.where((u) => u.path.startsWith('/ws/2/artist')), isNotEmpty,
          reason: 'een woord dat met de artiestnaam begint is nog niet die artiest');
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('Discogs', () {
    test('DE KERN: zoeklijst en liedjesvraag wachten niet op de persingen', () async {
      final vragen = await _vragen(() => MetadataSearch(AppSettings()..discogsToken = 'X')
          .search('Discogs', '$_artiest $_album', artist: _artiest, album: _album));
      int waar(bool Function(Map<String, String> q) past) =>
          vragen.indexWhere((u) => u.host == 'api.discogs.com' && past(u.queryParameters));
      final zoeklijst = waar((q) => q['type'] == 'release' && q['q'] != null);
      final liedje = waar((q) => q['track'] != null);
      // De persingen lopen over de baan van DiscogsService: één vraag per 1,1 s. De laatste daarvan
      // komt dus ruim na de eerste; ervóór horen de twee vragen die niet op die baan hoeven te wachten.
      final laatstePersing = vragen.lastIndexWhere((u) =>
          u.host == 'api.discogs.com' && (u.queryParameters['type'] == 'master' || u.queryParameters['release_title'] != null));
      expect(zoeklijst, isNonNegative);
      expect(liedje, isNonNegative);
      expect(laatstePersing, greaterThan(0));
      expect(zoeklijst, lessThan(laatstePersing),
          reason: 'de zoeklijst wacht weer tot alle persingen binnen zijn — een seconde per vraag');
      expect(liedje, lessThan(laatstePersing),
          reason: 'de liedjesvraag wacht weer tot de albumtak klaar is');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('DE GRENS: zonder persingen blijft de zoeklijst over, en hij wordt maar één keer gevraagd',
        () async {
      final vragen = await _vragen(() => MetadataSearch(AppSettings()..discogsToken = 'X')
          .search('Discogs', '$_artiest $_album', artist: _artiest, album: _album));
      final zoeklijsten = vragen.where((u) =>
          u.host == 'api.discogs.com' && u.queryParameters['type'] == 'release' && u.queryParameters['q'] != null);
      expect(zoeklijsten, hasLength(1),
          reason: 'bij geen persingen werd de zoeklijst een tweede keer opgevraagd');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('DE VAL: mét persingen staan die vooraan, en de vroeg gevraagde zoeklijst wordt gebruikt',
        () async {
      var rijen = const <MetaResult>[];
      final vragen = await _vragen(() async {
        rijen = await MetadataSearch(AppSettings()..discogsToken = 'X')
            .search('Discogs', '$_artiest $_album', artist: _artiest, album: _album);
      }, antwoord: _eenPersing);
      expect(rijen.map((r) => r.releaseId), contains(368542),
          reason: 'de persing die Discogs gaf staat niet in het venster');
      expect(rijen.first.releaseId, 368542, reason: 'de persingen horen vóór de zoeklijst');
      final zoeklijsten = vragen.where((u) =>
          u.host == 'api.discogs.com' && u.queryParameters['type'] == 'release' && u.queryParameters['q'] != null);
      expect(zoeklijsten, hasLength(1),
          reason: 'de zoeklijst werd vooraf gevraagd én na de persingen nog eens — een vraag te veel '
              'uit een budget van zestig per minuut');
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}

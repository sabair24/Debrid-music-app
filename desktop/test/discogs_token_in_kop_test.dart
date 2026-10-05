/// Het Discogs-token hoort in de kop, nooit in het adres.
///
/// **Gevonden op 05-10-2026.** `MetadataSearch` vroeg Discogs op twee plekken als
/// `database/search?type=release&token=<token>&…`: de zoeklijst en de liedjesvraag van "Metadata
/// corrigeren". De rest van de app stuurt het token al als `Authorization: Discogs token=…` mee —
/// `DiscogsService`, de verbindingstoets, de credits. Een adres belandt in logboeken, proxy's en
/// foutmeldingen (een `ClientException` noemt het hele adres, token incluis); een kop niet.
///
/// Deze toets raakt het net niet: een nagebootst net legt elke vraag vast, met adres én koppen. Het
/// token hier is nep — het echte staat alleen in settings.json op het toestel.
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

const _token = 'NEP-DISCOGS-TOKEN-0510';
const _artiest = 'Oasis';
const _album = "(What's The Story) Morning Glory?";

bool _isDiscogs(Uri u) => u.host == 'discogs.com' || u.host.endsWith('.discogs.com');

/// Elke vraag die er gesteld wordt, met adres en koppen. Het antwoord is "niets gevonden", tenzij
/// [antwoord] er een heeft.
Future<List<http.Request>> _vragen(Future<void> Function() doe, {Object? Function(Uri)? antwoord}) async {
  final vragen = <http.Request>[];
  await http.runWithClient(doe, () => MockClient((r) async {
        vragen.add(r);
        return http.Response(
            jsonEncode(antwoord?.call(r.url) ??
                {'results': [], 'versions': [], 'releases': [], 'recordings': [], 'artists': []}),
            200);
      }));
  return vragen;
}

/// Discogs kent één master van de plaat, met één cd-persing — zodat ook de persingentak vraagt.
Object? _eenPersing(Uri u) {
  if (!_isDiscogs(u)) return null;
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

/// Elke Discogs-vraag: geen token in het adres, wél in de kop. En geen enkele andere bron krijgt het.
void _alleenInDeKop(List<http.Request> vragen) {
  final discogs = vragen.where((r) => _isDiscogs(r.url)).toList();
  expect(discogs, isNotEmpty, reason: 'er werd Discogs niets gevraagd — dan bewijst deze toets niets');
  for (final r in discogs) {
    expect(r.url.queryParametersAll.keys.map((k) => k.toLowerCase()), isNot(contains('token')),
        reason: 'het token staat weer in het adres van ${r.url.path}');
    expect(r.url.toString(), isNot(contains(_token)),
        reason: 'het token staat ergens in het adres van ${r.url.path}');
    expect(r.headers['Authorization'], 'Discogs token=$_token',
        reason: '${r.url.path} gaat zonder token in de kop — Discogs weet dan niet wie er vraagt');
  }
  for (final r in vragen.where((r) => !_isDiscogs(r.url))) {
    expect(r.url.toString(), isNot(contains(_token)), reason: 'het Discogs-token ging naar ${r.url.host}');
    expect(r.headers.values.where((v) => v.contains(_token)), isEmpty,
        reason: 'het Discogs-token ging in een kop naar ${r.url.host}');
  }
}

void main() {
  setUp(() {
    // Een eigen map per toets: MusicBrainz en Discogs onthouden antwoorden op schijf, ook "niets".
    setAppDirForTest(Directory.systemTemp.createTempSync('dm_tokenkop_').path);
    MusicBrainzService.resetLanes();
  });

  AppSettings metToken() => AppSettings()..discogsToken = _token;

  test('DE KERN: zoeklijst en liedjesvraag sturen het token als kop, niet in het adres', () async {
    final vragen = await _vragen(() => MetadataSearch(metToken()).search('Discogs', 'Yasmine porselein'));
    final discogs = vragen.where((r) => _isDiscogs(r.url)).map((r) => r.url.queryParameters).toList();
    // Allebei echt gevraagd, anders is "geen token in het adres" een loze bewering.
    expect(discogs.where((q) => q['q'] != null), hasLength(1), reason: 'de zoeklijst werd niet gevraagd');
    expect(discogs.where((q) => q['track'] != null), hasLength(1), reason: 'de liedjesvraag werd niet gevraagd');
    _alleenInDeKop(vragen);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('een single (track: true) loopt alleen over de zoeklijst, en ook die zonder token in het adres',
      () async {
    final vragen =
        await _vragen(() => MetadataSearch(metToken()).search('Discogs', 'Oasis Wonderwall', track: true));
    expect(vragen.where((r) => _isDiscogs(r.url) && r.url.queryParameters['q'] != null), hasLength(1));
    _alleenInDeKop(vragen);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('DE VAL: met artiest en album erbij — persingen, zoeklijst en liedjesvraag samen', () async {
    final vragen = await _vragen(
        () => MetadataSearch(metToken()).search('Discogs', '$_artiest $_album', artist: _artiest, album: _album),
        antwoord: _eenPersing);
    expect(vragen.where((r) => r.url.path == '/masters/52220/versions'), isNotEmpty,
        reason: 'de persingentak werd niet bereikt');
    _alleenInDeKop(vragen);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('"Alles": alleen Discogs krijgt het token, MusicBrainz, TheAudioDB en Deezer niet', () async {
    final vragen = await _vragen(
        () => MetadataSearch(metToken()).search('Alles', '$_artiest $_album', artist: _artiest, album: _album),
        antwoord: _eenPersing);
    expect(vragen.where((r) => !_isDiscogs(r.url)), isNotEmpty, reason: 'de andere bronnen werden niet gevraagd');
    _alleenInDeKop(vragen);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('een persing openklappen of zijn volle hoes halen: ook daar het token alleen in de kop', () async {
    const rij = MetaResult(title: _album, artist: _artiest, album: _album, releaseId: 368542);
    final vragen = await _vragen(() async {
      final zoek = MetadataSearch(metToken());
      await zoek.volleHoes(rij);
      // Een lege persing is een fout ("Discogs gaf deze persing niet terug"); hier telt de vraag.
      await zoek.tracklistVan(rij).then((_) {}, onError: (_) {});
    });
    expect(vragen.where((r) => r.url.path == '/releases/368542'), isNotEmpty,
        reason: 'de persing werd Discogs niet gevraagd');
    _alleenInDeKop(vragen);
  }, timeout: const Timeout(Duration(seconds: 60)));
}

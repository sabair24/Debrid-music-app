import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/cachesleutel.dart';
import 'package:debridmusic/enrichment.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Saber, 08-11-2026, op de pagina van Khaled (raï): de foto en het logo van DJ Khaled.
/// `search.php?s=khaled` geeft DJ Khaled, want die heeft "Khaled" als alternatieve naam. Echte antwoorden hieronder.
const djKhaled = {
  'idArtist': '112356',
  'strArtist': 'DJ Khaled',
  'strArtistAlternate': 'Khaled',
  'strMusicBrainzID': '081a2d60-9791-4e05-a075-f1890355eeee',
  'strGenre': 'Hip-Hop',
  'strCountry': 'Florida, USA',
};
const raiKhaled = {
  'idArtist': '115335',
  'strArtist': 'Khaled',
  'strMusicBrainzID': 'b4a479aa-4384-4acf-88b0-dee9188faeb5',
  'strGenre': 'Singer Songwriter',
  'strCountry': 'Oran, Algérie',
};

void main() {
  MbArtist mbArtiest(String id, String naam) => MbArtist.from({'id': id, 'name': naam});

  Future<Map<String, dynamic>?> kies(
    String naam,
    Map<String, dynamic> rij, {
    MbArtist? kent,
    Map<String, dynamic>? opNummer,
    void Function()? mbGevraagd,
  }) =>
      kiesAudioDbArtiest(naam, rij, mb: (_) async {
        mbGevraagd?.call();
        return kent;
      }, opMb: (_) async => opNummer);

  group('is dit wel deze artiest?', () {
    test('DE KERN: op "Khaled" geeft TheAudioDB DJ Khaled, en de echte komt op zijn MusicBrainz-nummer', () async {
      final uit = await kies('Khaled', djKhaled, kent: mbArtiest('b4a479aa-4384-4acf-88b0-dee9188faeb5', 'Khaled'), opNummer: raiKhaled);
      expect(uit?['idArtist'], '115335');
    });

    test('de alternatieve naam bij TheAudioDB is geen bewijs', () async {
      final uit = await kies('Khaled', djKhaled);
      expect(uit, isNull, reason: 'liever geen foto dan die van een naamgenoot');
    });

    test('heet er niemand precies zo bij MusicBrainz, dan ook geen rij op nummer', () async {
      final uit = await kies('Khaled', djKhaled, kent: mbArtiest('1', 'Khaled Hosseini'), opNummer: raiKhaled);
      expect(uit, isNull);
    });

    test('wel een naam bij MusicBrainz maar geen rij bij TheAudioDB: niets', () async {
      expect(await kies('Khaled', djKhaled, kent: mbArtiest('x', 'Khaled')), isNull);
    });

    test('dezelfde naam of woord voor woord het begin: geen vraag aan MusicBrainz', () async {
      var gevraagd = 0;
      expect(await kies('Adele', {'strArtist': 'Adele'}, mbGevraagd: () => gevraagd++), isNotNull);
      expect(await kies('Beyoncé', {'strArtist': 'Beyonce'}, mbGevraagd: () => gevraagd++), isNotNull);
      expect(await kies('Amir', {'strArtist': 'Amir Haddad'}, mbGevraagd: () => gevraagd++), isNotNull);
      expect(await kies('The Weeknd', {'strArtist': 'Weeknd'}, mbGevraagd: () => gevraagd++), isNotNull);
      expect(gevraagd, 0);
    });

    test('een andere schrijfwijze met hetzelfde nummer is dezelfde: Alice DJ is Alice DeeJay', () async {
      const rij = {'strArtist': 'Alice DeeJay', 'strMusicBrainzID': 'ABC-1'};
      expect(await kies('Alice DJ', rij, kent: mbArtiest('abc-1', 'Alice Deejay')), rij);
    });

    test('A Touch Of Class is ATC, ook al kent MusicBrainz onder die naam een techno-duo', () async {
      const atc = {'strArtist': 'ATC', 'strArtistAlternate': 'A Touch of Class', 'strMusicBrainzID': '408b2a33'};
      var gevraagd = 0;
      expect(await kies('A Touch Of Class', atc, kent: mbArtiest('ander', 'A Touch of Class'), mbGevraagd: () => gevraagd++), atc);
      expect(gevraagd, 0);
    });

    test('geen antwoord van MusicBrainz gooit door, zodat "niets gevonden" niet onthouden wordt', () async {
      await expectLater(
        kiesAudioDbArtiest('Khaled', djKhaled, mb: (_) async => throw const HttpException('weg'), opMb: (_) async => null),
        throwsA(isA<HttpException>()),
      );
    });

    test('woord voor woord: wat voorop staat telt', () {
      expect(naamWoordVoorWoord('Khaled', 'DJ Khaled'), isFalse);
      expect(naamWoordVoorWoord('Khaled', 'Khaled Hadj Ibrahim'), isTrue);
      expect(naamWoordVoorWoord('Sam', 'Samantha Fox'), isFalse);
      expect(naamWoordVoorWoord('', 'Adele'), isFalse);
    });
  });

  group('langs het net', () {
    http.Response antwoord(http.Request r) {
      final u = r.url.toString();
      if (u.contains('/search.php')) return http.Response(jsonEncode({'artists': [djKhaled]}), 200);
      if (u.contains('/artist-mb.php')) {
        expect(u, contains('b4a479aa'));
        return http.Response(jsonEncode({'artists': [raiKhaled]}), 200);
      }
      if (u.contains('musicbrainz.org')) {
        return http.Response(
            jsonEncode({
              'artists': [
                {'id': 'b4a479aa-4384-4acf-88b0-dee9188faeb5', 'name': 'Khaled', 'score': 100},
                {'id': '081a2d60-9791-4e05-a075-f1890355eeee', 'name': 'DJ Khaled', 'score': 81},
              ]
            }),
            200);
      }
      fail('onverwachte vraag: $u');
    }

    test('het genre voor de radio komt van de echte', () async {
      final g = await http.runWithClient(
          () => CoverEnricher.audioDbGenre('Khaled'), () => MockClient((r) async => antwoord(r)));
      expect(g, 'Singer Songwriter');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('wat al in de buffers staat', () {
    late Directory map;
    late String h;
    final sep = Platform.pathSeparator;

    File bestand(String pad) => File('${map.path}$sep$pad');

    setUp(() {
      map = Directory.systemTemp.createTempSync('naamgenoot');
      for (final d in ['artistart', 'bios', 'artistfeiten', 'artists']) {
        Directory('${map.path}$sep$d').createSync();
      }
      h = fnv1a('khaled');
      for (final p in [
        'artistart$sep$h.json',
        'artistart$sep${h}_logo.img',
        'artistart$sep${h}_backdrop.img',
        'artistart$sep${h}_thumb.img',
        'bios$sep$h.txt',
        'artistfeiten$sep$h.json',
        'artists$sep$h.jpg',
        'artistart$sep${fnv1a('adele')}.json',
      ]) {
        bestand(p).writeAsStringSync('oud');
      }
    });

    tearDown(() => map.deleteSync(recursive: true));

    test('de naamgenoot gaat weg, de rest blijft staan', () async {
      await ruimAudioDbNaamgenotenOp(map.path);
      expect(bestand('artistart$sep$h.json').existsSync(), isFalse);
      expect(bestand('artistart$sep${h}_logo.img').existsSync(), isFalse);
      expect(bestand('artistart$sep${h}_backdrop.img').existsSync(), isFalse);
      expect(bestand('artistart$sep${h}_thumb.img').existsSync(), isFalse);
      expect(bestand('bios$sep$h.txt').existsSync(), isFalse);
      expect(bestand('artistfeiten$sep$h.json').existsSync(), isFalse);
      expect(bestand('artists$sep$h.jpg').existsSync(), isFalse);
      expect(bestand('artistart$sep${fnv1a('adele')}.json').existsSync(), isTrue);
    });

    test('maar één keer: wat daarna opnieuw gehaald is, blijft staan', () async {
      await ruimAudioDbNaamgenotenOp(map.path);
      bestand('artistart$sep$h.json').writeAsStringSync('nieuw en juist');
      await ruimAudioDbNaamgenotenOp(map.path);
      expect(bestand('artistart$sep$h.json').readAsStringSync(), 'nieuw en juist');
    });

    test('de lijst wordt opgeruimd vóór de app iets toont', () {
      final bron = File('lib/main.dart').readAsStringSync();
      final init = bron.indexOf('await initAppPaths();');
      final op = bron.indexOf('await ruimAudioDbNaamgenotenOp(appDir);');
      expect(op, greaterThan(init));
      expect(op, lessThan(bron.indexOf('runApp(', init)));
    });
  });

  test('elke vraag op naam bij TheAudioDB gaat langs de keuze', () {
    final e = File('lib/enrichment.dart').readAsStringSync();
    expect('await _audioDbDezeArtiest('.allMatches(e).length, 3, reason: 'beeld, genre en biografie');
    final a = File('lib/audiodb.dart').readAsStringSync();
    expect(a, contains('kiesAudioDbArtiest(wie, Map<String, dynamic>.from(l.first),'));
  });
}

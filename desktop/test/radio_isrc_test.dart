// De ISRC als plafond voor het jaar van het ZAAD (19-10-2026) — dat jaar krijgt het model te zien. In de keuring
// zelf telt het jaar sinds 22-10-2026 niet meer (Saber: "nergens een grens van jaren"); die toetsen zijn weg.
import 'dart:io';

import 'package:debridmusic/isrc.dart';
import 'package:debridmusic/radiostijl.dart';
import 'package:debridmusic/recommend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory map;
  setUp(() => map = Directory.systemTemp.createTempSync('dm_isrc_radio_'));
  tearDown(() {
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  Stijlboek boek({int? isrc, List<String>? gevraagd, int? deezer}) => Stijlboek(
        bestand: File('${map.path}${Platform.pathSeparator}radiostijl.json'),
        audioDbGenre: (_) async => null,
        discogsNummer: (a, t) async => null,
        deezerJaar: deezer == null ? null : (a, t) async => deezer,
        // Zonder ISRC geen haak: anders onthoudt het boek "geen ISRC" voor het volgende boek in dezelfde map.
        isrcJaar: isrc == null && gevraagd == null
            ? null
            : (a, t) async {
          gevraagd?.add('$a — $t');
          return isrc;
        },
      );

  test('het zaad: een te laat jaar zakt ook naar de ISRC', () async {
    final z = await boek(isrc: 1996, deezer: 2026).zaad('Madonna', 'You Must Love Me');
    expect(z.jaar, 1996, reason: 'Deezer gaf de single van 12-10-2026');
  });

  test('RecommendService.isrcJaar: het vroegste van dit liedje, ook van een heruitgave', () async {
    Map<String, dynamic> track(String artiest, String titel, String isrc) => {
          'title': titel,
          'artist': {'name': artiest},
          'album': {'title': 'Iets', 'id': 1},
          'isrc': isrc,
        };
    final r = RecommendService(
        haal: (url) async => {
              'data': [
                track('Garbage', 'Stupid Girl (Remastered 2015)', 'USGF11500408'),
                track('Garbage', 'Stupid Girl', 'USGF19500408'),
                track('Garbage', 'Queer', 'USGF19400001'),
                track('Iemand Anders', 'Stupid Girl', 'GBXX18000001'),
              ]
            },
        adem: Duration.zero);
    expect(await r.isrcJaar('Garbage', 'Stupid Girl'), 1995,
        reason: 'niet "Queer" (ander liedje) en niet de cover van iemand anders');
  });

  test('DE KERN: een live-opname zegt niets over het jaar van het zaad (Luka, 23-10-2026)', () async {
    Map<String, dynamic> track(String titel, String album, String isrc) => {
          'title': titel,
          'artist': {'name': 'Suzanne Vega'},
          'album': {'title': album, 'id': 1},
          'isrc': isrc,
        };
    // Zoals Deezer het gaf: de studio-opname (USAM187…, 1987) en een uitzending met een code uit "60".
    final data = [
      track('Luka', 'RetroSpective: The Best Of Suzanne Vega', 'USAM18704255'),
      track('Luka (Live 1986 Broadcast Remastered)', 'Legendary FM Broadcasts - The Bottom Line', 'GBSMU6079295'),
      track('Luka', 'Legendary FM Broadcasts', 'GBSMU6079296'),
    ];
    final r = RecommendService(haal: (url) async => {'data': data}, adem: Duration.zero);
    expect(await r.isrcJaar('Suzanne Vega', 'Luka'), 1987, reason: 'niet 1960: de radio zocht in het verkeerde tijdvak');
    expect(await r.isrcJaar('Suzanne Vega', 'Luka (Live)'), 1960, reason: 'wie zelf een live-versie kiest, telt die mee');
  });

  test('een ISRC-jaar uit een oudere versie van het geheugen wordt opnieuw gevraagd', () async {
    File('${map.path}${Platform.pathSeparator}radiostijl.json')
        .writeAsStringSync('{"_versie": 6, "i:suzannevega|luka": 1960, "a:suzannevega": "rock"}');
    final gevraagd = <String>[];
    final z = await boek(isrc: 1987, gevraagd: gevraagd, deezer: 1987).zaad('Suzanne Vega', 'Luka');
    expect(gevraagd, ['Suzanne Vega — Luka'], reason: 'de 1960 van vóór versie 7 is weg');
    expect(z.jaar, 1987);
  });

  test('de app geeft de haak echt door aan het stijlboek', () {
    final main = File('lib/main.dart').readAsStringSync();
    final boek = main.substring(main.indexOf('Stijlboek _gedeeldStijlboek(AppSettings cfg) => _stijlboek ??= Stijlboek('));
    expect(boek.substring(0, boek.indexOf(');')), contains('isrcJaar: RecommendService().isrcJaar,'));
  });

  test('isrcJaar', () {
    expect(isrcJaar('USSM19803028'), 1998);
    expect(isrcJaar('GBUM71106457'), 2011);
    expect(isrcJaar(null), isNull);
  });
}

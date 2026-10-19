// De ISRC als plafond voor het jaar in de radiokeuring (19-10-2026). Gemeten over de 61
// tijdvakweigeringen in radio.log: twee waren fout door het jaar van een heruitgave, en de ISRC zegt het
// echte jaar. Bij de andere 59 lag de ISRC even laat of later — oude catalogus kreeg pas een code toen
// hij gedigitaliseerd werd — en dan mag er niets veranderen.
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

  test('Whitney Houston: "uit 2010" door de verzamelaar, de ISRC zegt 1992 — en het zaad is van 1992', () async {
    const zaad = (familie: Stijlfamilie.popsoul, jaar: 1992);
    const titel = "I'm Every Woman (Clivilles & Cole Radio Mix)";
    final zonder = await boek().keur('Whitney Houston', titel, zaad, jaarHint: 2010, familieTelt: false);
    expect(zonder.mag, isFalse, reason: 'zo ging het: "uit 2010, het zaad is van 1992"');
    final met = await boek(isrc: 1992).keur('Whitney Houston', titel, zaad, jaarHint: 2010, familieTelt: false);
    expect(met.mag, isTrue);
  });

  test('Garbage: "uit 2015" door de remaster bij Deezer, de ISRC zegt 1995', () async {
    const zaad = (familie: Stijlfamilie.rock, jaar: 1993);
    final o = await boek(isrc: 1995, deezer: 2015)
        .keur('Garbage', 'Stupid Girl (Remastered 2015)', zaad, familieTelt: false);
    expect(o.mag, isTrue);
  });

  test('een ISRC die later ligt verandert niets ("Sexual Healing", 1982, code uit 1998)', () async {
    const zaad = (familie: Stijlfamilie.popsoul, jaar: 2005);
    int? buiten;
    final o = await boek(isrc: 1998).keur('Marvin Gaye', 'Sexual Healing', zaad,
        jaarHint: 1982, familieTelt: false, buitenJaar: (j) => buiten = j);
    expect(o.mag, isFalse);
    expect(buiten, 1982, reason: 'het jaar van de weigering blijft het echte');
  });

  test('één jaar eerder is geen bewijs: een code wordt soms vóór de uitgave toegekend', () async {
    const zaad = (familie: Stijlfamilie.rock, jaar: 1996);
    final o = await boek(isrc: 2004).keur('X', 'Y', zaad, jaarHint: 2005, familieTelt: false);
    expect(o.mag, isFalse, reason: '1988–2004: 2005 valt erbuiten, ook met een code uit 2004');
  });

  test('alleen gevraagd bij een nee op het tijdvak, en daarna onthouden', () async {
    const zaad = (familie: Stijlfamilie.popsoul, jaar: 1992);
    final gevraagd = <String>[];
    final b = boek(isrc: 1992, gevraagd: gevraagd);
    await b.keur('Seal', 'Kiss From A Rose', zaad, jaarHint: 1994, familieTelt: false);
    expect(gevraagd, isEmpty, reason: 'past al: geen vraag aan Deezer');
    await b.keur('Whitney Houston', 'I Will Always Love You', zaad, jaarHint: 2012, familieTelt: false);
    await b.keur('Whitney Houston', 'I Will Always Love You', zaad, jaarHint: 2012, familieTelt: false);
    expect(gevraagd, hasLength(1));
    final opnieuw = boek(isrc: 1992, gevraagd: gevraagd);
    await opnieuw.keur('Whitney Houston', 'I Will Always Love You', zaad, jaarHint: 2012, familieTelt: false);
    expect(gevraagd, hasLength(1), reason: 'ook na een herstart: het staat in radiostijl.json');
  });

  test('zonder jaar zegt de ISRC alleen niets', () async {
    const zaad = (familie: Stijlfamilie.rock, jaar: 1993);
    final gevraagd = <String>[];
    final o = await boek(isrc: 1960, gevraagd: gevraagd).keur('X', 'Y', zaad, familieTelt: false);
    expect(o.mag, isTrue);
    expect(gevraagd, isEmpty);
  });

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

  test('de app geeft de haak echt door aan het stijlboek', () {
    final main = File('lib/main.dart').readAsStringSync();
    final boek = main.substring(main.indexOf('final stijlboek = _stijlboek ??= Stijlboek('));
    expect(boek.substring(0, boek.indexOf(');')), contains('isrcJaar: RecommendService().isrcJaar,'));
  });

  test('isrcJaar', () {
    expect(isrcJaar('USSM19803028'), 1998);
    expect(isrcJaar('GBUM71106457'), 2011);
    expect(isrcJaar(null), isNull);
  });
}

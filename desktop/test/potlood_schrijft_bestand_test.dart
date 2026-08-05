/// Het potlood moet de tags in het BESTAND zetten, niet alleen in de app.
///
/// Saber: "ik heb de tag bewerkt, maar toch blijven de originele tags erin. Mijn tags moeten
/// overwriten." Dat klopte letterlijk: `applyCorrection` schreef uitsluitend naar `corrections.json`,
/// en de opmerking in library.dart zei het met zoveel woorden — *"Applied to scanned tracks so wrong
/// tags are fixed without touching the files."* De app tóónde zijn tekst, het bestand hield die van de
/// uploader. Zet je de map in Roon of op een telefoon, dan was zijn werk onzichtbaar.
///
/// Deze tests toetsen de twee kanten die tegen elkaar in werken: de bewerking moet in het bestand
/// landen, én er moet een weg terug zijn. Zonder dat tweede is schrijven in andermans bestanden niet
/// te verantwoorden.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/flac_tags.dart';
import 'package:debridmusic/organize.dart';

import 'place_file_test.dart' show buildFlac;

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('potlood_'));
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  File maak(String naam, List<String> tags) {
    final f = File('${root.path}${Platform.pathSeparator}$naam');
    f.writeAsBytesSync(Uint8List.fromList(buildFlac(tags)));
    return f;
  }

  test('een bewerkte artiest en albumtitel landen in het bestand', () async {
    final f = maak('x.flac', ['TITLE=Didi', 'ARTIST=Khaled', 'ALBUM=1001 Songs', 'TRACKNUMBER=779']);

    final ok = await writeTagFields(f, {'ARTIST': 'Cheb Khaled', 'ALBUM': 'Sahra'});
    expect(ok, isTrue);

    final na = readFlacTags(f)!;
    expect(na.artist, 'Cheb Khaled');
    expect(na.album, 'Sahra');
    expect(na.title, 'Didi', reason: 'wat niet bewerkt is blijft staan');
    expect(na.trackNo, 779, reason: 'en het tracknummer ook');
  });

  test('velden die de gebruiker niet invulde blijven ongemoeid', () async {
    // De reden dat er alleen geschreven wordt wat hij typte, en niet de hele set: `stampTags` schrijft
    // acht velden en zou een tracknummer of jaar overschrijven waar niemand om vroeg.
    final f = maak('y.flac', ['TITLE=Aicha', 'ARTIST=Khaled', 'ALBUM=Sahra', 'TRACKNUMBER=3']);
    await writeTagFields(f, {'ARTIST': 'Cheb Khaled'});
    final na = readFlacTags(f)!;
    expect(na.artist, 'Cheb Khaled');
    expect(na.album, 'Sahra');
    expect(na.title, 'Aicha');
    expect(na.trackNo, 3);
  });

  test('de weg terug: de oude waarden zijn te lezen vóór het schrijven, en terug te zetten', () async {
    // Precies wat `applyCorrection` nu doet: eerst de rauwe velden lezen, dan schrijven, en de oude
    // waarden bewaren in _tagUndo. Een veld dat er NIET was komt als null terug, zodat het terugzetten
    // hem wist in plaats van onze waarde te laten staan.
    final f = maak('z.flac', ['TITLE=Aicha', 'ARTIST=Khaled']);

    final rauwVoor = readFlacRawFields(f);
    final voor = {for (final k in ['ARTIST', 'ALBUM']) k: rauwVoor[k.toLowerCase()]};
    expect(voor['ARTIST'], 'Khaled');
    expect(voor['ALBUM'], isNull, reason: 'dit veld bestond niet — dat moet zo vastgelegd worden');

    await writeTagFields(f, {'ARTIST': 'Cheb Khaled', 'ALBUM': 'Sahra'});
    expect(readFlacTags(f)!.album, 'Sahra');

    // Terugzetten.
    await writeTagFields(f, voor);
    final terug = readFlacTags(f)!;
    expect(terug.artist, 'Khaled');
    expect(terug.album, anyOf(isNull, ''), reason: 'een veld dat er niet was hoort weer weg te zijn');
    expect(terug.title, 'Aicha', reason: 'en de rest is nooit aangeraakt');
  });

  test('een bestand dat geen flac of mp3 is wordt geweigerd, niet half geschreven', () async {
    final f = File('${root.path}${Platform.pathSeparator}iets.wav')..writeAsBytesSync([1, 2, 3, 4]);
    expect(await writeTagFields(f, {'ARTIST': 'Wie dan ook'}), isFalse);
    expect(f.readAsBytesSync(), [1, 2, 3, 4], reason: 'onaangeroerd');
  });
}

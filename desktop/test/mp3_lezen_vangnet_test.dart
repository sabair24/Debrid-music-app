/// Een mp3 die het tagpakket niet wil lezen, wordt alsnog gelezen door de app zelf.
///
/// Gemeten geval: één bestand in de wortel van de bibliotheek werd bij het opbergen overgeslagen met
/// "geen tags te lezen", terwijl de eigen ID3-lezer er zes velden uit haalde. Voor FLAC stond die
/// terugval er al, voor mp3 niet -- dezelfde scheefheid als bij het SCHRIJVEN, waar de mp3-schrijver
/// op alles was aangesloten behalve op de weg die hem het meest gebruikt.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/organize.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een ID3v2.3-tag met de opgegeven tekstframes, en daarna vulling in plaats van audio.
///
/// Het reproduceren van de storing zit NIET in de vulling -- het pakket claimt zo'n bestand gewoon.
/// Het zit in een TRCK die geen getal is: het pakket doet daar `int.parse` op en gooit. Dat is precies
/// wat het echte bestand deed, waar het tracknummer "WWW.CLUB-BOX.COM" bleek te zijn. Met een net
/// tracknummer leest het pakket alles zelf en bewijst de test niets -- eerste poging hier deed dat,
/// en die tests waren dus waardeloos zonder dat ze faalden.
Uint8List _id3(Map<String, String> frames) {
  final body = <int>[];
  frames.forEach((id, tekst) {
    final data = <int>[0, ...tekst.codeUnits]; // 0 = ISO-8859-1
    body
      ..addAll(id.codeUnits)
      ..addAll([
        (data.length >> 24) & 0xFF,
        (data.length >> 16) & 0xFF,
        (data.length >> 8) & 0xFF,
        data.length & 0xFF,
      ])
      ..addAll([0, 0])
      ..addAll(data);
  });
  final n = body.length;
  return Uint8List.fromList([
    ...'ID3'.codeUnits,
    3, 0, 0,
    (n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F,
    ...body,
    ...List.filled(64, 0), // geen audio, alleen vulling
  ]);
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('mp3vangnet'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File maak(String naam, Map<String, String> frames) {
    final f = File('${tmp.path}${Platform.pathSeparator}$naam');
    f.writeAsBytesSync(_id3(frames));
    return f;
  }

  /// Het tracknummer dat het pakket laat vallen. Letterlijk wat er in het echte bestand stond.
  const gif = {'TRCK': 'WWW.CLUB-BOX.COM'};

  test('artiest, titel en album komen er alsnog uit', () {
    final f = maak('los bestand.mp3', {
      'TIT2': 'Be The Insomnia',
      'TPE1': 'Steve Angello & Laidback Luke',
      'TALB': 'Mocktime',
      ...gif,
    });
    final t = readTags(f);
    expect(t, isNotNull, reason: 'zonder het vangnet is dit null en wordt het bestand overgeslagen');
    expect(t!.artist, 'Steve Angello & Laidback Luke');
    expect(t.title, 'Be The Insomnia');
    expect(t.album, 'Mocktime');
    expect(t.trackNo, 0, reason: 'een webadres is geen nummer, dus 0 en geen uitzondering');
  });

  test('zonder titel valt hij terug op de bestandsnaam, niet op leeg', () {
    final f = maak('Iemand - Iets.mp3', {'TPE1': 'Iemand', ...gif});
    expect(readTags(f)?.title, 'Iemand - Iets');
  });

  test('een tag zonder één bruikbaar veld levert nog steeds niets op', () {
    // Het vangnet mag geen lege TrackTags verzinnen: dan zou een bestand zonder enige informatie
    // onder "Onbekende artiest" worden opgeborgen in plaats van te worden overgeslagen.
    final f = maak('naamloos.mp3', {'TCON': 'Hardcore', ...gif});
    expect(readTags(f), isNull);
  });

  test('een net tracknummer leest het pakket zelf, en dat blijft zo', () {
    // De grens van het vangnet: hier komt het niet aan te pas, en dat hoort ook zo. Zonder deze test
    // zou een wijziging die het vangnet vóór het pakket zet er ongemerkt doorheen glippen.
    final f = maak('net.mp3', {'TIT2': 'Iets', 'TPE1': 'Iemand', 'TRCK': '7'});
    expect(readTags(f)?.trackNo, 7);
  });

  test('een bestand dat helemaal geen mp3 is blijft geweigerd', () {
    final f = File('${tmp.path}${Platform.pathSeparator}tekst.mp3')
      ..writeAsBytesSync(Uint8List.fromList(List.filled(200, 65)));
    expect(readTags(f), isNull);
  });
}

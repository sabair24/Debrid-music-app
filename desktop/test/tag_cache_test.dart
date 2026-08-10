/// De tagcache van de opstartscan.
///
/// Waarom hij er is staat bij `_laadTagCache` in library.dart, met de meting erbij: de scan las élke
/// start alle 775 bestanden opnieuw, goed voor 9 seconden warm en 17 koud, terwijl er niets aan
/// veranderd was.
///
/// Wat hier vastligt is niet de snelheid maar de VEILIGHEID ervan, want een cache die te lang gelooft
/// wat hij weet is erger dan geen cache: dan staat er een titel op je scherm die niet meer in het
/// bestand staat. De sleutel is `(pad, mtime, grootte)`, en deze toetsen bewaken alle drie de manieren
/// waarop dat mis kan gaan.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/library.dart';

void _schrijfFlac(
  File file, {
  required String title,
  required String artist,
  required String album,
  int vulling = 2048,
}) {
  final streamInfo = List<int>.filled(34, 0);
  const sampleRate = 44100, bits = 16, seconds = 180;
  final packed = (BigInt.from(sampleRate) << 44) |
      (BigInt.from(1) << 41) |
      (BigInt.from(bits - 1) << 36) |
      BigInt.from(sampleRate * seconds);
  for (var i = 0; i < 8; i++) {
    streamInfo[10 + i] = ((packed >> ((7 - i) * 8)) & BigInt.from(0xFF)).toInt();
  }

  final comment = <int>[];
  void u32(int v) => comment.addAll([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  const vendor = 'test';
  u32(vendor.length);
  comment.addAll(vendor.codeUnits);
  final fields = ['TITLE=$title', 'ARTIST=$artist', 'ALBUM=$album', 'TRACKNUMBER=1'];
  u32(fields.length);
  for (final f in fields) {
    u32(f.length);
    comment.addAll(f.codeUnits);
  }

  file.writeAsBytesSync(<int>[
    ...'fLaC'.codeUnits,
    0, 0, 0, streamInfo.length,
    ...streamInfo,
    0x80 | 4, (comment.length >> 16) & 0xFF, (comment.length >> 8) & 0xFF, comment.length & 0xFF,
    ...comment,
    ...List<int>.filled(vulling, 0),
  ]);
}

void main() {
  late Directory muziek;
  late String cachePad;

  setUp(() {
    muziek = Directory.systemTemp.createTempSync('dm_tagcache_');
    cachePad = '${muziek.path}${Platform.pathSeparator}cache${Platform.pathSeparator}tags.json';
  });

  tearDown(() {
    try {
      muziek.deleteSync(recursive: true);
    } catch (_) {}
  });

  File nummer(String naam) => File('${muziek.path}${Platform.pathSeparator}$naam');

  test('de tweede scan leest geen enkel bestand meer', () async {
    _schrijfFlac(nummer('1.flac'), title: 'Een', artist: 'A', album: 'X');
    _schrijfFlac(nummer('2.flac'), title: 'Twee', artist: 'A', album: 'X');

    final eerste = await scanTagsInIsolate(muziek.path, cachePad);
    expect(eerste.gelezen, 2);
    expect(eerste.uitCache, 0);
    expect(File(cachePad).existsSync(), isTrue, reason: 'de map eronder moet zelf aangemaakt worden');

    final tweede = await scanTagsInIsolate(muziek.path, cachePad);
    expect(tweede.uitCache, 2);
    expect(tweede.gelezen, 0);
    expect([for (final r in tweede.rijen) r['title']]..sort(), ['Een', 'Twee']);
  });

  test('een bewerkt bestand wordt WEL opnieuw gelezen', () async {
    // De belangrijkste van de vier. Schrijft de app zelf tags — of doet de gebruiker het met een
    // ander programma — dan verandert de inhoud, en een cache die dat mist toont voor altijd de oude
    // titel bij een bestand dat iets anders zegt.
    _schrijfFlac(nummer('1.flac'), title: 'Oud', artist: 'A', album: 'X');
    await scanTagsInIsolate(muziek.path, cachePad);

    // Andere grootte én een latere mtime — precies wat een tagbewerking oplevert.
    _schrijfFlac(nummer('1.flac'), title: 'Nieuw', artist: 'A', album: 'X', vulling: 4096);
    nummer('1.flac').setLastModifiedSync(DateTime.now().add(const Duration(seconds: 5)));

    final na = await scanTagsInIsolate(muziek.path, cachePad);
    expect(na.gelezen, 1, reason: 'gewijzigd bestand hoort opnieuw open te gaan');
    expect(na.rijen.single['title'], 'Nieuw');
  });

  test('een verwijderd nummer verdwijnt uit de cache in plaats van er te blijven', () async {
    // Anders groeit dit bestand net zo hard aan als album_facts.json, dat op 10 MB stond voor 233
    // albums omdat er nooit iets uit ging.
    _schrijfFlac(nummer('1.flac'), title: 'Blijft', artist: 'A', album: 'X');
    _schrijfFlac(nummer('2.flac'), title: 'Weg', artist: 'A', album: 'X');
    await scanTagsInIsolate(muziek.path, cachePad);

    nummer('2.flac').deleteSync();
    final na = await scanTagsInIsolate(muziek.path, cachePad);
    expect(na.rijen.length, 1);
    expect(File(cachePad).readAsStringSync().contains('Weg'), isFalse);
  });

  test('een onleesbare cache kost één trage scan, geen klap', () async {
    _schrijfFlac(nummer('1.flac'), title: 'Een', artist: 'A', album: 'X');
    await scanTagsInIsolate(muziek.path, cachePad);

    File(cachePad).writeAsStringSync('{dit is geen json');
    final na = await scanTagsInIsolate(muziek.path, cachePad);
    expect(na.gelezen, 1);
    expect(na.rijen.single['title'], 'Een');
  });

  test('een cache van een oudere versie wordt genegeerd, niet half gelezen', () async {
    // De rij heeft er in het verleden velden bij gekregen (sampleRate, bitsPerSample). Een oude rij
    // half overnemen zou nullen opleveren voor nummers die die waarden wél hebben — en dan staat er
    // "FLAC" waar "FLAC · 24/96" hoort.
    _schrijfFlac(nummer('1.flac'), title: 'Een', artist: 'A', album: 'X');
    await scanTagsInIsolate(muziek.path, cachePad);

    final oud = File(cachePad).readAsStringSync().replaceFirst('"v":1', '"v":0');
    File(cachePad).writeAsStringSync(oud);

    final na = await scanTagsInIsolate(muziek.path, cachePad);
    expect(na.uitCache, 0, reason: 'een vreemde versie hoort volledig genegeerd te worden');
    expect(na.gelezen, 1);
  });

  test('zonder cachepad werkt de scan gewoon', () async {
    _schrijfFlac(nummer('1.flac'), title: 'Een', artist: 'A', album: 'X');
    final uit = await scanTagsInIsolate(muziek.path, null);
    expect(uit.rijen.single['title'], 'Een');
    expect(uit.uitCache, 0);
  });
}

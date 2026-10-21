// De gekozen voorkant ook IN het bestand (Saber, 21-10-2026: "doe dit altijd bij allemaal").
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/flac_tags.dart';
import 'package:debridmusic/hoes_in_bestand.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';

/// Een JPEG-kop met maten en wat vulling: genoeg voor [beeldKenmerk] en om te vergelijken.
Uint8List _jpeg(int breedte, int hoogte, int lengte, {int zaad = 1}) {
  final b = Uint8List(max(lengte, 40));
  b.setAll(0, [0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x11, 0x08, hoogte >> 8, hoogte & 0xFF, breedte >> 8, breedte & 0xFF, 0x03]);
  final r = Random(zaad);
  for (var i = 12; i < b.length - 2; i++) {
    b[i] = r.nextInt(256);
  }
  b[b.length - 2] = 0xFF;
  b[b.length - 1] = 0xD9;
  return b;
}

Uint8List _png(int breedte, int hoogte) {
  final b = Uint8List(64);
  b.setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
  b.setAll(16, [breedte >> 24, (breedte >> 16) & 0xFF, (breedte >> 8) & 0xFF, breedte & 0xFF]);
  b.setAll(20, [hoogte >> 24, (hoogte >> 16) & 0xFF, (hoogte >> 8) & 0xFF, hoogte & 0xFF]);
  return b;
}

Uint8List _picture(int soort, Uint8List beeld) {
  final b = BytesBuilder();
  void be32(int v) => b.add([(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]);
  be32(soort);
  be32(10);
  b.add('image/jpeg'.codeUnits);
  be32(0);
  be32(600);
  be32(600);
  be32(24);
  be32(0);
  be32(beeld.length);
  b.add(beeld);
  return b.toBytes();
}

Uint8List _vorbis(Map<String, String> velden) {
  final b = BytesBuilder();
  void le32(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  le32(4);
  b.add('test'.codeUnits);
  le32(velden.length);
  for (final e in velden.entries) {
    final s = '${e.key}=${e.value}'.codeUnits;
    le32(s.length);
    b.add(s);
  }
  return b.toBytes();
}

/// Een FLAC uit [blokken] (soort, lijf) en [audio]; STREAMINFO komt er vanzelf voor.
Uint8List _flac(List<(int, Uint8List)> blokken, Uint8List audio) {
  final alle = [(0, Uint8List(34)), ...blokken];
  final b = BytesBuilder()..add('fLaC'.codeUnits);
  for (var i = 0; i < alle.length; i++) {
    final (soort, lijf) = alle[i];
    b.add([(i == alle.length - 1 ? 0x80 : 0) | soort, (lijf.length >> 16) & 0xFF, (lijf.length >> 8) & 0xFF, lijf.length & 0xFF]);
    b.add(lijf);
  }
  b.add(audio);
  return b.toBytes();
}

Uint8List _audio(int n) {
  final r = Random(7);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

/// Alle platen in een FLAC: (soort, beeld), in volgorde.
List<(int, int)> _platen(File f) {
  final b = f.readAsBytesSync();
  var o = 4;
  final uit = <(int, int)>[];
  var laatste = false;
  while (!laatste) {
    laatste = (b[o] & 0x80) != 0;
    final soort = b[o] & 0x7F;
    final len = (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
    if (soort == 6) uit.add(((b[o + 4] << 24) | (b[o + 5] << 16) | (b[o + 6] << 8) | b[o + 7], len));
    o += 4 + len;
  }
  return uit;
}

void main() {
  late Directory map;
  final vroeger = DateTime(2024, 3, 9, 14, 30, 12);
  setUp(() => map = Directory.systemTemp.createTempSync('dm_hoesbestand_'));
  tearDown(() {
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  File schrijf(String naam, Uint8List bytes) {
    final f = File('${map.path}${Platform.pathSeparator}$naam')..writeAsBytesSync(bytes);
    f.setLastModifiedSync(vroeger);
    return f;
  }

  group('beeldKenmerk', () {
    test('JPEG en PNG, met hun maten; de rest niet', () {
      expect(beeldKenmerk(_jpeg(1200, 1100, 500)), (mime: 'image/jpeg', breedte: 1200, hoogte: 1100));
      expect(beeldKenmerk(_png(700, 700)), (mime: 'image/png', breedte: 700, hoogte: 700));
      expect(beeldKenmerk(Uint8List.fromList(List.filled(80, 7))), isNull);
    });
  });

  group('schrijfVoorkantInFlac', () {
    final audio = _audio(200000);
    final oudeHoes = _jpeg(600, 600, 5000, zaad: 2);
    final tags = _vorbis({'TITLE': 'Dur Dur', 'ARTIST': 'Jordy', 'ALBUM': 'Pochette Surprise'});

    test('past in de oude ruimte: even groot, zelfde datum, zelfde audio, de tags blijven', () {
      final f = schrijf('a.flac', _flac([(4, tags), (6, _picture(3, oudeHoes)), (1, Uint8List(8192))], audio));
      final grootte = f.lengthSync();
      final nieuw = _jpeg(1200, 1200, 9000, zaad: 3);
      final r = schrijfVoorkantInFlac(f.path, nieuw, bewaarOud: '${map.path}${Platform.pathSeparator}oud');
      expect(r.uitkomst, HoesUitkomst.zelfdeGrootte);
      expect(f.lengthSync(), grootte);
      expect(f.lastModifiedSync(), vroeger, reason: '"recent toegevoegd" en alle metingen hangen aan de datum');
      final b = f.readAsBytesSync();
      expect(b.sublist(b.length - audio.length), audio, reason: 'de audio byte voor byte');
      expect(readFlacPicture(f).hoes, nieuw);
      expect(readFlacRawFields(f)['album'], 'Pochette Surprise');
      expect(_platen(f), [(3, 42 + nieuw.length)], reason: 'één plaat: de nieuwe voorkant');
      // De oude voorkant bewaard, één keer.
      expect(r.oud, isNotNull);
      expect(File('${map.path}${Platform.pathSeparator}oud${Platform.pathSeparator}${r.oud}').readAsBytesSync(), oudeHoes);
      expect(File('${f.path}.hoes').existsSync(), isFalse);
    });

    test('past niet: het bestand groeit, met ruimte voor een volgende keer; de audio blijft', () {
      final f = schrijf('b.flac', _flac([(4, tags), (6, _picture(3, oudeHoes)), (1, Uint8List(1000))], audio));
      final grootte = f.lengthSync();
      final nieuw = _jpeg(1200, 1200, 30000, zaad: 4);
      final r = schrijfVoorkantInFlac(f.path, nieuw);
      expect(r.uitkomst, HoesUitkomst.andereGrootte);
      expect(f.lengthSync(), greaterThan(grootte));
      expect(f.lastModifiedSync(), vroeger);
      final b = f.readAsBytesSync();
      expect(b.sublist(b.length - audio.length), audio);
      expect(readFlacPicture(f).hoes, nieuw);
      // Nog eens met een iets grotere hoes: die past nu in de ruimte van daarnet.
      final groter = _jpeg(1200, 1200, 31000, zaad: 5);
      final g2 = f.lengthSync();
      expect(schrijfVoorkantInFlac(f.path, groter).uitkomst, HoesUitkomst.zelfdeGrootte);
      expect(f.lengthSync(), g2);
    });

    test('dezelfde hoes nog eens: niets aangeraakt', () {
      final nieuw = _jpeg(1200, 1200, 9000, zaad: 3);
      final f = schrijf('c.flac', _flac([(4, tags), (6, _picture(3, nieuw)), (1, Uint8List(100))], audio));
      final voor = f.readAsBytesSync();
      expect(schrijfVoorkantInFlac(f.path, nieuw).uitkomst, HoesUitkomst.alGelijk);
      expect(f.readAsBytesSync(), voor);
      expect(f.lastModifiedSync(), vroeger);
    });

    test('een achterkant vooraan blijft, maar de nieuwe voorkant komt ervoor; oude voorkanten weg', () {
      final achter = _jpeg(600, 600, 3000, zaad: 8);
      final f = schrijf(
          'd.flac',
          _flac([
            (4, tags),
            (6, _picture(4, achter)),
            (6, _picture(3, oudeHoes)),
            (6, _picture(0, _jpeg(300, 300, 800, zaad: 9))),
            (1, Uint8List(4096)),
          ], audio));
      final nieuw = _jpeg(1200, 1200, 7000, zaad: 3);
      expect(schrijfVoorkantInFlac(f.path, nieuw).uitkomst, HoesUitkomst.zelfdeGrootte);
      expect(readFlacPicture(f).hoes, nieuw, reason: 'de bibliotheek leest de eerste plaat');
      expect(_platen(f).map((p) => p.$1).toList(), [3, 4]);
    });

    test('alleen in een bestand zonder plaat — als dat gevraagd is', () {
      final nieuw = _jpeg(1200, 1200, 2000, zaad: 3);
      final met = schrijf('e.flac', _flac([(4, tags), (6, _picture(3, oudeHoes))], audio));
      expect(schrijfVoorkantInFlac(met.path, nieuw, alleenAlsLeeg: true).uitkomst, HoesUitkomst.heeftAlEen);
      expect(readFlacPicture(met).hoes, oudeHoes);
      final zonder = schrijf('f.flac', _flac([(4, tags), (1, Uint8List(16384))], audio));
      expect(schrijfVoorkantInFlac(zonder.path, nieuw, alleenAlsLeeg: true).uitkomst, HoesUitkomst.zelfdeGrootte);
      expect(readFlacPicture(zonder).hoes, nieuw);
    });

    test('geen FLAC, of een ID3-kop voor de FLAC: niet aangeraakt', () {
      final nieuw = _jpeg(1200, 1200, 2000);
      final mp3 = schrijf('g.flac', Uint8List.fromList([0x49, 0x44, 0x33, 3, 0, 0, 0, 0, 0, 0, ...audio.take(500)]));
      final voor = mp3.readAsBytesSync();
      expect(schrijfVoorkantInFlac(mp3.path, nieuw).uitkomst, HoesUitkomst.nietTeLezen);
      expect(mp3.readAsBytesSync(), voor);
      final f = schrijf('h.flac', _flac([(4, tags)], audio));
      expect(schrijfVoorkantInFlac(f.path, Uint8List.fromList(List.filled(50, 1))).uitkomst, HoesUitkomst.nietTeLezen,
          reason: 'geen JPEG of PNG');
    });
  });

  group('nieuweBlokken', () {
    final plaat = Uint8List(100);
    final info = (soort: 0, lijf: Uint8List(34));
    test('precies passend: geen opvulblok; 1 à 3 bytes over: ruimte erbij', () {
      final kern = 4 + 34 + 4 + 100;
      expect(nieuweBlokken([info], plaat, kern).map((b) => b.soort), [0, 6]);
      final twee = nieuweBlokken([info], plaat, kern + 2);
      expect(twee.last.soort, 1);
      expect(twee.last.lijf.length, kHoesInBestandRuimte);
      final ruim = nieuweBlokken([info], plaat, kern + 1000);
      expect(ruim.last.lijf.length, 996);
    });
  });

  group('hoesVoorBestanden', () {
    Uint8List b(int n) => Uint8List(200)..[0] = n;
    test('jouw keuze, dan de herkende uitgave; een eigen hoes alleen in nummers zonder plaat; een gok nooit', () {
      final a = Album('Pochette Surprise', 'Jordy', const [])
        ..correctedCover = b(1)
        ..resolvedCover = b(2)
        ..embeddedCover = b(3)
        ..enriched = b(4);
      expect(hoesVoorBestanden(a)?.beeld[0], 1);
      a.correctedCover = null;
      expect(hoesVoorBestanden(a)?.beeld[0], 2);
      expect(hoesVoorBestanden(a)?.alleenAlsLeeg, isFalse);
      a.resolvedCover = null;
      expect(hoesVoorBestanden(a)?.beeld[0], 3);
      expect(hoesVoorBestanden(a)?.alleenAlsLeeg, isTrue);
      a.embeddedIsVanEenAndere = true;
      expect(hoesVoorBestanden(a), isNull, reason: 'de hoes van een verzamelaar geef je niet door');
      a
        ..embeddedIsVanEenAndere = false
        ..embeddedCover = null;
      expect(hoesVoorBestanden(a), isNull, reason: 'een gok op naam gaat niet in je bestanden');
    });
  });

  group('de veger', () {
    test('een echte ronde, met de isolate: de hoes in alle nummers, de oude bewaard, het spelende niet', () async {
      final audio = _audio(50000);
      final oudeHoes = _jpeg(600, 600, 5000, zaad: 2);
      final tags = _vorbis({'TITLE': 'x'});
      final paden = [
        for (final n in ['1.flac', '2.flac', '3.flac'])
          schrijf(n, _flac([(4, tags), (6, _picture(3, oudeHoes)), (1, Uint8List(20000))], audio)).path
      ];
      final gekozen = _jpeg(1200, 1200, 9000, zaad: 3);
      final lib = LibraryStore()..configDirOverride = map.path;
      lib.albums = [
        Album('Pochette Surprise', 'Jordy', [
          for (final p in paden) Track(path: p, title: 'x', artist: 'Jordy', album: 'Pochette Surprise', isFlac: true)
        ])
          ..resolvedCover = gekozen
          ..resolvedFrom = 'dz:664022531',
      ];
      final veger = HoesInBestandVeger(
          library: lib, speeltNu: (p) => p == paden[2], tussenpoos: Duration.zero, startNa: const Duration(hours: 1));
      // Gestart zoals op de pc: dan heeft de veger zijn timers, en een closure die hem meeneemt naar de isolate
      // breekt daarop af (3.9.538: "object is unsendable — _Timer").
      await veger.start();
      await veger.ronde();
      expect(readFlacPicture(File(paden[0])).hoes, gekozen);
      expect(readFlacPicture(File(paden[1])).hoes, gekozen);
      expect(readFlacPicture(File(paden[2])).hoes, oudeHoes, reason: 'wat speelt, wacht');
      expect(File(paden[0]).lastModifiedSync(), vroeger);
      final log = File('${map.path}${Platform.pathSeparator}hoes_in_bestand.log').readAsStringSync();
      expect(log, isNot(contains('MISLUKT')));
      expect(log, contains('2 geschreven (2 even groot, 0 gegroeid)'));
      expect(File('${map.path}${Platform.pathSeparator}hoes_oud${Platform.pathSeparator}index.json').existsSync(), isTrue);
      // De bibliotheek leest bij de volgende start de NIEUWE plaat uit haar cache.
      final st = File(paden[0]).statSync();
      final sleutel = hoesSleutel(paden[0], st.modified.millisecondsSinceEpoch, st.size);
      expect(File('${lib.hoesCacheMap}${Platform.pathSeparator}$sleutel').readAsBytesSync(), gekozen);
      veger.stop();
    });
  });

  group('aangesloten', () {
    test('de pc start de veger, laat hem los bij wissen en verplaatsen, en wacht op de meters', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(main, contains('await hoesVeger.laatLos(paden);'));
      expect(main, contains('bezigElders: () => veger.bezig || echtVeger.bezig,'));
      expect(main, contains('unawaited(hoesVeger.start()'));
      expect(main, contains('enabled: mode.owner,\n        bezigElders: () => veger.bezig || echtVeger.bezig,'));
    });
  });
}

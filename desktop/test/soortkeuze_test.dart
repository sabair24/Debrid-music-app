// Studio, cd of vinyl zelf kiezen (Saber, 25-10-2026): "download in studio kwaliteit, download in cd kwaliteit, en
// download in vinyl ... eerst mag de app doen wat hij wil en als ik dan hoor van hmmm, dit hoor ik niet graag in die
// versie dan kan ik zelf altijd kiezen". Zie kopiesoort.dart, soortjacht.dart en DownloadManager.vraagSoort.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/flac_tags.dart' show readFlacTags;
import 'package:debridmusic/kopiesoort.dart';
import 'package:debridmusic/lan/dtos.dart' show TrackDto;
import 'package:debridmusic/models.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/organize.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/soortjacht.dart';
import 'package:debridmusic/soulseek.dart' show SoulseekFile;
import 'package:debridmusic/tidaler.dart' show Tidaler;
import 'package:debridmusic/twijfel.dart';
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

/// Een minimale FLAC: STREAMINFO met [rate], [bits] en [seconden], en één Vorbis-commentaar.
Uint8List _flac({int rate = 44100, int bits = 16, int seconden = 10, String titel = 'Nightvision'}) {
  final b = BytesBuilder()..add(ascii.encode('fLaC'));
  b.add([0x00, 0x00, 0x00, 0x22]);
  final si = Uint8List(34);
  const kanalen = 2;
  final monsters = rate * seconden;
  si[10] = (rate >> 12) & 0xFF;
  si[11] = (rate >> 4) & 0xFF;
  si[12] = ((rate & 0x0F) << 4) | ((kanalen - 1) << 1) | (((bits - 1) >> 4) & 0x01);
  si[13] = (((bits - 1) & 0x0F) << 4) | ((monsters >> 32) & 0x0F);
  si[14] = (monsters >> 24) & 0xFF;
  si[15] = (monsters >> 16) & 0xFF;
  si[16] = (monsters >> 8) & 0xFF;
  si[17] = monsters & 0xFF;
  b.add(si);
  final v = BytesBuilder();
  List<int> le32(int x) => [x & 0xFF, (x >> 8) & 0xFF, (x >> 16) & 0xFF, (x >> 24) & 0xFF];
  final verkoper = utf8.encode('toets'), commentaar = utf8.encode('TITLE=$titel');
  v
    ..add(le32(verkoper.length))
    ..add(verkoper)
    ..add(le32(1))
    ..add(le32(commentaar.length))
    ..add(commentaar);
  final vb = v.takeBytes();
  b.add([0x84, (vb.length >> 16) & 0xFF, (vb.length >> 8) & 0xFF, vb.length & 0xFF]);
  b.add(vb);
  return b.takeBytes();
}

SoulseekFile _hit(String pad, {int? bits, int? hz, int size = 1000}) =>
    SoulseekFile(username: 'u$size', filename: pad, size: size, durationSec: 200, sampleRate: hz, bitDepth: bits);

void main() {
  setUp(resetSoortenVoorToets);
  tearDown(resetSoortenVoorToets);

  group('wat een kopie is (zijn antwoorden)', () {
    test('DE KERN: vinyl aan zijn bron, studio bij 24 bit, cd bij 16/44,1', () {
      expect(kopiesoortVan(bronpad: r'@@x\Daft Punk - Discovery (Vinyl 24-96)\06.flac', bits: 24, hz: 96000),
          Kopiesoort.vinyl);
      expect(kopiesoortVan(bronpad: r'@@x\PBTHAL rips\Toto - IV\Africa.flac', bits: 16, hz: 44100), Kopiesoort.vinyl,
          reason: 'geen naar 16 bit omgezette vinylrip als cd');
      for (final hz in [44100, 48000, 96000, 192000]) {
        expect(kopiesoortVan(bronpad: r'@@x\Discovery [24-bit]\06.flac', bits: 24, hz: hz), Kopiesoort.studio,
            reason: 'ook 24/44,1 en 24/48 zijn studio ($hz)');
      }
      expect(kopiesoortVan(bronpad: r'@@x\Discovery (CD)\06.flac', bits: 16, hz: 44100), Kopiesoort.cd);
      expect(kopiesoortVan(bronpad: 'TIDAL 12345', bits: 16, hz: 44100), Kopiesoort.cd, reason: 'TIDAL LOSSLESS is cd');
    });

    test('DE GRENS: geen van de drie', () {
      expect(kopiesoortVan(bronpad: 'x.flac', bits: 16, hz: 48000), isNull, reason: '16/48 is geen cd');
      expect(kopiesoortVan(bronpad: 'x.flac', bits: 0, hz: 0), isNull, reason: 'de kop zegt niets');
      expect(kopiesoortVan(bronpad: r'Vinyl rip\x.mp3', bits: 0, hz: 0, verliesvrij: false), isNull,
          reason: 'een mp3 is geen van de drie, ook niet van vinyl');
    });

    test('kan een zoekresultaat de soort zijn: ja, nee, of pas het bestand zegt het', () {
      expect(kanSoortZijn(Kopiesoort.vinyl, bronpad: r'x\(vinyl rip)\a.flac'), isTrue);
      expect(kanSoortZijn(Kopiesoort.vinyl, bronpad: r'x\(CD)\a.flac', bits: 24, hz: 96000), isFalse);
      expect(kanSoortZijn(Kopiesoort.studio, bronpad: r'x\(vinyl rip)\a.flac', bits: 24, hz: 96000), isFalse,
          reason: 'studio is nooit een vinylrip');
      expect(kanSoortZijn(Kopiesoort.studio, bronpad: r'x\a.flac'), isNull, reason: 'diepte niet gemeld');
      expect(kanSoortZijn(Kopiesoort.cd, bronpad: r'x\a.flac', bits: 16, hz: 44100), isTrue);
      expect(kanSoortZijn(Kopiesoort.cd, bronpad: r'x\a.flac', bits: 24, hz: 96000), isFalse);
    });
  });

  group('de kandidaten voor een soort', () {
    test('DE KERN: de soort, de beste eerst, dan wat de uploader niet meldt; nooit je eigen bestand of wat je weggooide', () {
      final k = kandidatenVoorSoort(Kopiesoort.studio, [
        _hit(r'a\Discovery (CD)\06.flac', bits: 16, hz: 44100, size: 1),
        _hit(r'b\Discovery\06.flac', size: 2),
        _hit(r'c\Discovery 24-48\06.flac', bits: 24, hz: 48000, size: 3),
        _hit(r'd\Discovery 24-96 vinyl\06.flac', bits: 24, hz: 96000, size: 4),
        _hit(r'e\Discovery 24-96\06.flac', bits: 24, hz: 96000, size: 5),
        _hit(r'f\Discovery 24-192\06.flac', bits: 24, hz: 192000, size: 6),
        _hit(r'g\Discovery 24-192\06.flac', bits: 24, hz: 192000, size: 7),
      ], eigenGrootte: 6, afgewezen: {3});
      expect(k.map((f) => f.size).toList(), [7, 5, 2],
          reason: '6 is je eigen bestand, 3 gooide je weg, 4 is vinyl, 1 is een cd; 2 meldt geen diepte');
    });

    test('vinyl: alleen vinylrips', () {
      final k = kandidatenVoorSoort(Kopiesoort.vinyl, [
        _hit(r'a\Discovery 24-96\06.flac', bits: 24, hz: 96000, size: 1),
        _hit(r'b\Discovery (needle drop)\06.flac', size: 2),
      ]);
      expect(k.map((f) => f.size), [2]);
    });

    test('zoekwoorden: studio "24bit", vinyl "vinyl", cd de gewone vraag', () {
      expect(zoekwoordenVoorSoort(Kopiesoort.studio), ['24bit']);
      expect(zoekwoordenVoorSoort(Kopiesoort.vinyl), ['vinyl']);
      expect(zoekwoordenVoorSoort(Kopiesoort.cd), isEmpty);
    });
  });

  group('de keuring van een gevraagde kopie', () {
    test('DE KERN: niet "bewezen beter", wel de soort en dezelfde opname — de twijfelzone mag, daaronder nooit', () {
      String? k({Kopiesoort? binnen = Kopiesoort.cd, int? lengte = 200, double? score = .95}) => waaromNietKlaar(
          gevraagd: Kopiesoort.cd, binnen: binnen, lengte: lengte, seconden: 200, score: score, drempel: kTwijfelVanaf);
      expect(k(), isNull);
      expect(k(score: .72), isNull, reason: 'twijfelzone: klaar, met een waarschuwing');
      expect(k(score: null), isNull, reason: 'niet te meten (geen fpcalc): klaar, met een waarschuwing');
      expect(k(score: .55), contains('andere opname'), reason: 'live of remix: nooit');
      expect(k(binnen: Kopiesoort.vinyl), contains('geen cd-kwaliteit maar vinyl'));
      expect(k(binnen: null), contains('geen cd-kwaliteit'));
      expect(k(lengte: 207), contains('andere lengte'));
      expect(k(lengte: 206), isNull);
    });

    test('vinyl mag langer duren (een plaat draait trager)', () {
      expect(
          waaromNietKlaar(
              gevraagd: Kopiesoort.vinyl,
              binnen: Kopiesoort.vinyl,
              lengte: 235,
              seconden: 228,
              score: .86,
              drempel: kTwijfelVanaf),
          isNull,
          reason: 'Mademoiselle chante le blues: 235 s tegen 228 s');
      expect(misschienAndereOpname(.86), isTrue);
      expect(misschienAndereOpname(.93), isFalse);
    });
  });

  group('de soort per nummer, en jouw keuze', () {
    test('DE KERN: koos je cd, dan vanzelf alleen nog een cd', () {
      const pad = r'D:\Muziek\Albums\Daft Punk\Discovery\06 - Nightvision.flac';
      expect(magVanzelf(pad, Kopiesoort.vinyl), isTrue, reason: 'geen keuze: de app doet wat hij wil');
      zetSoort(pad, Kopiesoort.vinyl);
      expect(soortVoor(pad), (soort: Kopiesoort.vinyl, gekozen: false));
      expect(magVanzelf(pad, Kopiesoort.studio), isTrue);
      zetSoort(pad, Kopiesoort.cd, gekozen: true);
      expect(gekozenSoort(pad), Kopiesoort.cd);
      expect(magVanzelf(pad, Kopiesoort.cd), isTrue, reason: 'een betere cd mag');
      expect(magVanzelf(pad, Kopiesoort.vinyl), isFalse, reason: 'nooit vanzelf vinyl');
      expect(magVanzelf(pad, Kopiesoort.studio), isFalse);
      expect(magVanzelf(pad, null), isFalse, reason: 'wat geen soort is, ook niet');
      zetSoort(pad, Kopiesoort.cd);
      expect(gekozenSoort(pad), Kopiesoort.cd, reason: 'een automatische cd laat je keuze staan');
    });

    test('hoofdletters en schuine strepen tellen niet, en een verplaatst bestand neemt zijn soort mee', () {
      zetSoort(r'D:\Muziek\A\x.flac', Kopiesoort.studio, gekozen: true);
      expect(soortVoor('d:/muziek/a/X.FLAC')?.soort, Kopiesoort.studio);
      herNoemSoort(r'D:\Muziek\A\x.flac', r'D:\Muziek\B\x.flac');
      expect(soortVoor(r'D:\Muziek\A\x.flac'), isNull);
      expect(soortVoor(r'D:\Muziek\B\x.flac'), (soort: Kopiesoort.studio, gekozen: true));
      zetSoort(r'D:\Muziek\B\x.flac', null);
      expect(soortVoor(r'D:\Muziek\B\x.flac'), isNull, reason: 'een nieuwe kopie zonder soort erft niets');
    });

    test('op een toestel: wat de pc zegt', () {
      zetSoortVanPc('http://pc.invalid/stream/t1.flac', (soort: Kopiesoort.vinyl, gekozen: false));
      expect(soortVoor('http://pc.invalid/stream/t1.flac')?.soort, Kopiesoort.vinyl);
      zetSoortVanPc('http://pc.invalid/stream/t1.flac', null);
      expect(soortVoor('http://pc.invalid/stream/t1.flac'), isNull);
    });

    test('in een toets nooit naar de echte appmap; met een toetsbestand heen en terug', () async {
      final map = Directory.systemTemp.createTempSync('dm_soorten_');
      addTearDown(() {
        soortenBestandVoorToets = null;
        map.deleteSync(recursive: true);
      });
      soortenBestandVoorToets = '${map.path}/soorten.json';
      zetSoort(r'D:\a.flac', Kopiesoort.cd, gekozen: true);
      zetSoort(r'D:\b.flac', Kopiesoort.vinyl);
      await bewaarSoortenNu();
      resetSoortenVoorToets();
      expect(soortVoor(r'D:\a.flac'), isNull);
      await laadSoorten();
      expect(soortVoor(r'D:\a.flac'), (soort: Kopiesoort.cd, gekozen: true));
      expect(soortVoor(r'D:\b.flac'), (soort: Kopiesoort.vinyl, gekozen: false));
      expect(_bron('lib/kopiesoort.dart'), contains("  if (Platform.environment.containsKey('FLUTTER_TEST')) return null;"));
    });
  });

  group('zien dat er gezocht wordt, ook op een toestel', () {
    test('DE KERN: een vraag op de pc staat in het register, gaat mee met de catalogus, en weg is weg', () async {
      final map = Directory.systemTemp.createTempSync('dm_gezocht_');
      addTearDown(() => map.deleteSync(recursive: true));
      final l = Soortvragen('${map.path}/soortvragen.json');
      const pad = r'D:\Muziek\Albums\Daft Punk\Discovery\03 - Digital Love.flac';
      final v = Soortvraag(pad: pad, soort: Kopiesoort.cd, artiest: 'Daft Punk', titel: 'Digital Love', sindsMs: 1);
      final voor = soortvraagUitgave.value;
      l.zet(v);
      expect(gezochtVoor(pad), Kopiesoort.cd);
      expect(soortvraagUitgave.value, greaterThan(voor), reason: 'de catalogus moet het merken');
      l.herNoem(pad, r'D:\Muziek\Albums\Daft Punk\Discovery\03 - Digital Love (2).flac');
      expect(gezochtVoor(pad), isNull);
      expect(gezochtVoor(r'D:\Muziek\Albums\Daft Punk\Discovery\03 - Digital Love (2).flac'), Kopiesoort.cd);
      l.verwijder(r'D:\Muziek\Albums\Daft Punk\Discovery\03 - Digital Love (2).flac');
      expect(gezochtVoor(r'D:\Muziek\Albums\Daft Punk\Discovery\03 - Digital Love (2).flac'), isNull);
      // En laden zet ze ook in het register: na een herstart van de pc ziet een toestel ze meteen.
      l.zet(Soortvraag(pad: pad, soort: Kopiesoort.cd, artiest: 'Daft Punk', titel: 'Digital Love', sindsMs: 1));
      await l.bewaar();
      l.verwijder(pad);
      await Soortvragen('${map.path}/soortvragen.json').laad();
      expect(gezochtVoor(pad), Kopiesoort.cd);
    });

    test('op een toestel: wat de pc zegt, en de catalogus draagt het', () {
      zetSoortvraagVanPc('http://pc.invalid/stream/t9.flac', Kopiesoort.vinyl);
      expect(gezochtVoor('http://pc.invalid/stream/t9.flac'), Kopiesoort.vinyl);
      zetSoortvraagVanPc('http://pc.invalid/stream/t9.flac', null);
      expect(gezochtVoor('http://pc.invalid/stream/t9.flac'), isNull);
      const met = TrackDto(
          id: 't', albumId: 'a', artistId: 'b', title: 'Digital Love', artistName: 'Daft Punk', albumTitle: 'Discovery',
          streamPath: '/stream/t.flac', ext: 'flac', zoekt: 'cd');
      expect(TrackDto.fromJson(met.toJson()).zoekt, 'cd');
      const zonder = TrackDto(
          id: 't', albumId: 'a', artistId: 'b', title: 'Digital Love', artistName: 'Daft Punk', albumTitle: 'Discovery',
          streamPath: '/stream/t.flac', ext: 'flac');
      expect(zonder.toJson().containsKey('zoekt'), isFalse, reason: 'null voor bijna alles: de catalogus blijft klein');
      final catalog = _bron('lib/lan/catalog.dart');
      expect(catalog, contains('          zoekt: gezochtVoor(t.path)?.naam,'));
      expect(catalog, contains("      if (t.zoekt != null) fingerprint.add('Z\${t.zoekt}');"));
      expect(catalog, contains('    soortvraagUitgave.addListener(_markDirty);'));
      expect(_bron('lib/library.dart'), contains('    zetSoortvraagVanPc(pad, kopiesoortUit(d.zoekt));'));
      final server = _bron('lib/lan/server.dart');
      expect(server, contains("      case '/api/soort/stop':\n        return _soortStop(req);"));
      expect(server, contains("    '/api/soort/stop',\n"));
    });
  });

  group('de staande vraag', () {
    test('opnieuw zoeken: 30 min, 2 u, 6 u, dan elke dag; en heen en terug op schijf', () async {
      expect(soortvraagWacht(1), const Duration(minutes: 30));
      expect(soortvraagWacht(2), const Duration(hours: 2));
      expect(soortvraagWacht(3), const Duration(hours: 6));
      expect(soortvraagWacht(9), const Duration(days: 1));
      final v = Soortvraag(pad: r'D:\a.flac', soort: Kopiesoort.vinyl, artiest: 'Daft Punk', titel: 'Nightvision', sindsMs: 1);
      expect(v.aanDeBeurt(DateTime(2026)), isTrue, reason: 'nog nooit gezocht');
      v
        ..rondes = 1
        ..laatsteMs = DateTime(2026, 10, 25, 12).millisecondsSinceEpoch;
      expect(v.aanDeBeurt(DateTime(2026, 10, 25, 12, 29)), isFalse);
      expect(v.aanDeBeurt(DateTime(2026, 10, 25, 12, 30)), isTrue);
      final map = Directory.systemTemp.createTempSync('dm_soortvragen_');
      addTearDown(() => map.deleteSync(recursive: true));
      final l = Soortvragen('${map.path}/soortvragen.json')..zet(v);
      await l.bewaar();
      final terug = Soortvragen('${map.path}/soortvragen.json');
      await terug.laad();
      expect(terug.van(r'd:/A.flac')?.soort, Kopiesoort.vinyl);
      expect(terug.van(r'D:\a.flac')?.rondes, 1);
    });
  });

  group('op de pc: vragen, klaarzetten, houden en weggooien', () {
    late Directory map;
    late DownloadManager d;
    setUp(() {
      Tidaler.zetVoorToets(pad: null);
      map = Directory.systemTemp.createTempSync('dm_soortkeuze_');
      d = DownloadManager(OnlineService(AppSettings()), SoulseekService(AppSettings()), map.path, () async {})
        ..twijfel = Twijfellijst('${map.path}/twijfel.json')
        ..soortvragen = Soortvragen('${map.path}/soortvragen.json');
      DownloadManager.prullenbak = (paden) async {
        for (final p in paden) {
          File(p).deleteSync();
        }
        return paden.toSet();
      };
    });
    tearDown(() {
      DownloadManager.prullenbak = (_) async => {};
      Tidaler.resetLookup();
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    File eigen({int rate = 96000, int bits = 24, int seconden = 235}) =>
        File('${map.path}/Albums/Daft Punk/Discovery/06 - Nightvision.flac')
          ..createSync(recursive: true)
          ..writeAsBytesSync(_flac(rate: rate, bits: bits, seconden: seconden));

    Soortvraag vraag(File f, Kopiesoort s) =>
        Soortvraag(pad: f.path, soort: s, artiest: 'Daft Punk', titel: 'Nightvision', seconden: 228, sindsMs: 1);

    test('DE KERN: klaarzetten vervangt niets; houden vervangt altijd (ook een "betere" vinyl) en onthoudt je keuze', () async {
      final mijn = eigen(); // een vinylrip van 24/96, 235 s
      zetSoort(mijn.path, Kopiesoort.vinyl);
      final v = vraag(mijn, Kopiesoort.cd);
      d.soortvragen!.zet(v);
      final binnen = File('${map.path}/_keuring/a/06 Nightvision.flac')
        ..createSync(recursive: true)
        ..writeAsBytesSync(_flac(seconden: 228));
      expect(await d.zetKlaarVoorToets(v, binnen, 'Soulseek a', r'@@a\Discovery (CD)\06.flac', .93), isTrue);
      expect(binnen.existsSync(), isFalse, reason: 'weg uit de keuringsmap');
      expect(readFlacTags(mijn)?.bitsPerSample, 24, reason: 'je eigen kopie staat er nog');
      final tw = twijfelVoor(mijn.path)!;
      expect(tw.soort, 'cd');
      expect(tw.kwaliteit, 'FLAC 16/44,1');

      final zin = await d.vervangDoorTwijfel(mijn.path);
      expect(zin, contains('Gehouden: cd'));
      expect(readFlacTags(File(mijn.path))?.bitsPerSample, 16, reason: 'jouw keuze wint van een vinyl van 24/96');
      expect(soortVoor(mijn.path), (soort: Kopiesoort.cd, gekozen: true));
      expect(d.soortvragen!.van(mijn.path), isNull, reason: 'de vraag is beantwoord');
      expect(twijfelVoor(mijn.path), isNull);
      expect(
          map.listSync(recursive: true).any((e) => e is File && e.path.replaceAll(r'\', '/').contains('/$parkeerMap/')),
          isTrue,
          reason: 'de vinyl staat in _dubbel, niet weg');
    });

    test('een gevraagde kopie neemt de plaats in van een twijfelgeval van de app; een twijfel niet van een gevraagde', () async {
      final mijn = eigen();
      final oud = File('${map.path}/$twijfelMap/oud.flac')
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(50, 1));
      d.twijfel!.zet(Twijfelgeval(
          id: 'oud', pad: mijn.path, kandidaat: oud.path, bron: 'Soulseek z', score: .8, kwaliteit: 'FLAC 24/96',
          ms: 1, grootte: 50));
      final v = vraag(mijn, Kopiesoort.studio);
      final binnen = File('${map.path}/_keuring/b/06.flac')
        ..createSync(recursive: true)
        ..writeAsBytesSync(_flac(rate: 48000, bits: 24, seconden: 228));
      expect(await d.zetKlaarVoorToets(v, binnen, 'TIDAL 1', 'TIDAL 1', 0), isTrue);
      expect(oud.existsSync(), isFalse);
      expect(twijfelVoor(mijn.path)?.soort, 'studio');
      final twijfel = File('${map.path}/_keuring/c/06.flac')
        ..createSync(recursive: true)
        ..writeAsBytesSync(_flac(rate: 192000, bits: 24));
      await d.bewaarAlsTwijfel(twijfel, mijn.path, .8, 'Soulseek y', null);
      expect(twijfelVoor(mijn.path)?.soort, 'studio', reason: 'de app duwt jouw vraag niet weg');
    });

    test('weggooien: je eigen kopie blijft, dezelfde komt niet terug, en de vraag zoekt verder', () async {
      final mijn = eigen();
      final v = vraag(mijn, Kopiesoort.vinyl);
      d.soortvragen!.zet(v);
      final binnen = File('${map.path}/_keuring/d/06.flac')
        ..createSync(recursive: true)
        ..writeAsBytesSync(_flac(rate: 96000, bits: 24, seconden: 233));
      final grootte = binnen.lengthSync();
      await d.zetKlaarVoorToets(v, binnen, 'Soulseek d', r'@@d\Discovery (Vinyl)\06.flac', .86);
      final zin = await d.gooiTwijfelWeg(mijn.path);
      expect(zin, contains('zoekt de volgende vinyl-kopie'));
      expect(mijn.existsSync(), isTrue);
      expect(d.twijfel!.afgewezenGroottes(mijn.path), contains(grootte));
      expect(d.soortvragen!.van(mijn.path), isNotNull, reason: 'de vraag blijft staan');
    });

    test('vragen zonder Soulseek of TIDAL: de vraag blijft staan, en een korte melding', () async {
      final mijn = eigen();
      final t = Track(path: mijn.path, title: 'Nightvision', artist: 'Daft Punk', album: 'Discovery',
          duration: const Duration(seconds: 228));
      final zin = await d.vraagSoort([t], Kopiesoort.cd);
      expect(zin, contains('Zoekt cd-kwaliteit voor "Nightvision"'));
      expect(zin, contains('je vervangt pas als jij kiest'));
      expect(d.soortvragen!.van(mijn.path)?.soort, Kopiesoort.cd);
      for (var i = 0; i < 50 && d.klaarMelding.value == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(d.klaarMelding.value, contains('de app blijft zoeken'));
      expect(d.soortvragen!.van(mijn.path)?.rondes, 1);
      expect(File('${map.path}/soortvragen.json').existsSync(), isTrue);
      expect(await d.trekSoortvraagIn(mijn.path), contains('Gestopt'));
      expect(d.soortvragen!.van(mijn.path), isNull);
    });
  });

  test('placeFileDetailed vervangAltijd: jouw keuze wint, ook bij een andere lengte en een "betere" kopie', () async {
    final map = Directory.systemTemp.createTempSync('dm_vervangaltijd_');
    addTearDown(() => map.deleteSync(recursive: true));
    final pad = '${map.path}/Albums/A/B/01 - X.flac';
    File doel() => File(pad)
      ..createSync(recursive: true)
      ..writeAsBytesSync(_flac(rate: 96000, bits: 24, seconden: 235, titel: 'X'));
    File binnen(String n) => File('${map.path}/_keuring/$n/01 X.flac')
      ..createSync(recursive: true)
      ..writeAsBytesSync(_flac(seconden: 228, titel: 'X'));
    doel();
    final zonder = await placeFileDetailed(binnen('a'), map.path,
        staatAl: (a, t, {int? seconds}) => pad, parkeerAltijd: true);
    expect(readFlacTags(File(pad))?.bitsPerSample, 24, reason: 'zonder keuze blijft de 24/96 staan (${zonder.how})');
    final met = await placeFileDetailed(binnen('b'), map.path,
        staatAl: (a, t, {int? seconds}) => pad, parkeerAltijd: true, vervangAltijd: true);
    expect(met.how, Placement.moved);
    expect(readFlacTags(File(met.path))?.bitsPerSample, 16);
    expect(met.verving, isTrue);
  });

  test('aangesloten: landen noteert de soort, de automatische wegen blijven binnen je keuze, de schermen tonen het', () {
    final online = _bron('lib/online.dart');
    expect(online, contains('        if (how == Placement.moved) _noteerSoort(uit.path, from.filename);'));
    expect(online, contains('      if (uit.how == Placement.moved) _noteerSoort(uit.path, bronpad ?? bron);'));
    expect(online, contains('            if (how == Placement.moved) _noteerSoort(uit.path, f.filename);'));
    expect(online, contains("        _noteerSoort(uit.path, 'TIDAL \$id');"));
    expect(online, contains('    if (bestaand != null && !magVanzelf(bestaand, _soortVanBinnen(staged, bronpad ?? bron))) {'));
    expect(online, contains('            if (bestaand != null && !magVanzelf(bestaand, _soortVanBinnen(staged, f.filename))) {'));
    expect(online, contains('    if (keuze != null && keuze != Kopiesoort.studio) return;'));
    expect(online, contains('          vervangAltijd: g.gevraagd);'));
    final organize = _bron('lib/organize.dart');
    expect(organize, contains('    herNoemSoort(src.path, naar);'));
    expect(organize, contains('    herNoemSoort(landed, at);'));
    final main = _bron('lib/main.dart');
    expect(main, contains('              _qualityBadge(_trackQuality(t)),\n              // Studio, cd of vinyl (kopiesoort.dart): alleen bij nieuwe downloads.\n              _soortMerk(t),'));
    expect(main, contains('        ..._soortRegels(context, [t], heeft: soortVoor(t.path)?.soort),'));
    expect(main, contains('        ..._soortRegels(context, nummers, album: a.title),'));
    expect(main, contains("    final los = actie == 'vervang' && speler.current?.path == t.path ? await speler.laatBestandLos() : null;"));
    expect(main, contains('            (gekozenSoort(t.path) ?? Kopiesoort.studio) != Kopiesoort.studio,'));
    expect(main, contains('      downloads.soortvragen = vragen;'));
    expect(main, contains('  if (mode.owner) await laadSoorten();'));
    // Nagelopen op de pc (25-10-2026): Weg terwijl B klonk speelde verder van het weggegooide bestand; de badge zei de
    // kwaliteit van A; een AIFF werd gehaald en daarna afgekeurd; en een lopende vraag was niet te stoppen.
    expect(main, contains("    if (actie == 'weg' && speler.current?.path == t.path && speler.vergelijkBron != null) await speler.vergelijk(null);"));
    expect(main, contains("      return Quality('B · \${tw.kwaliteit}', bits > 16 ? QTier.hires : QTier.lossless);"));
    expect(main, contains("MenuRegel(Icons.search_off_rounded, 'Stop met zoeken naar \${s.voluit}', () => _stopSoortvraag(context, t)),"));
    expect(main, contains("        zin = '\${(await c.ask('/api/soort/stop', {'trackId': id}))['zin'] ?? 'Gestopt'}';"));
    expect(main, contains("          if (zoekt != null) 'zoekt \${zoekt.naam}…',"));
    expect(online, contains("        if (const {'flac', 'wav'}.contains(soortVan(f.filename))) f"));
    expect(online, contains('                maxWait: left < _maxWachtPerPeer ? left : _maxWachtPerPeer,\n'
        '                maxPlaats: _maxWachtrijPlaats);'),
        reason: 'plaats 7360 in een rij hield de hele ronde vast');
    final server = _bron('lib/lan/server.dart');
    expect(server, contains("      case '/api/soort/vraag':\n        return _soortVraag(req);"));
    expect(server, contains("    '/api/twijfel',\n    '/api/soort/vraag',\n"));
    final catalog = _bron('lib/lan/catalog.dart');
    expect(catalog, contains("      if (t.soort != null) fingerprint.add('S\${t.soort}\${t.soortGekozen ? '!' : ''}');"));
    expect(catalog, contains('    soortUitgave.addListener(_markDirty);'));
  });
}

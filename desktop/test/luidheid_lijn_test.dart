/// Gelijk volume — van de pc over de lijn naar de telefoon en de Shield, en de bedrading in de speler.
///
/// **Waarom dit bestaat.** Saber luistert vooral op zijn telefoon, en die meet niets: de pc meet en
/// stuurt het mee in de catalogus. Wat hier vastligt: de telefoon rekent precies dezelfde dB uit als de
/// pc; de catalogus haalt de toestellen niet elke 15 s opnieuw binnen terwijl de pc meet; meerkanaals
/// en mislukt reizen zonder getallen (dan kan geen toestel er iets op zetten); en de speler legt de
/// versterking vast vóór elke open en past hem pas toe in mpv's laadhaak.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/cast_manager.dart' show shieldLijst;
import 'package:debridmusic/lan/catalog.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/luidheid.dart';
import 'package:debridmusic/luidheid_keuze.dart' show luidheidStatusTekst;
import 'package:debridmusic/luidheid_winkel.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';

Track _t(String path, String title, String album, int no, {int grootte = 4096, int tijd = 1700000000000}) =>
    Track(
      path: path,
      title: title,
      artist: 'Artiest',
      album: album,
      trackNo: no,
      trackTotal: 3,
      duration: const Duration(seconds: 240),
      isFlac: true,
      sizeBytes: grootte + no,
      addedMs: tijd + no,
      sampleRate: 44100,
      bitsPerSample: 16,
    );

/// Het lijf van een methode in de broncode, van zijn kop tot de bijbehorende sluitaccolade.
String _lijf(String bron, String kop) {
  final begin = bron.indexOf(kop);
  expect(begin, isNonNegative, reason: '$kop niet gevonden');
  var diepte = 0;
  for (var i = bron.indexOf('{', begin); i < bron.length; i++) {
    if (bron[i] == '{') diepte++;
    if (bron[i] == '}' && --diepte == 0) return bron.substring(begin, i + 1);
  }
  return bron.substring(begin);
}

void main() {
  late Directory scratch;
  late LibraryStore pc;
  late LanCatalog catalog;

  setUp(() {
    resetLuidheidVoorTest();
    scratch = Directory.systemTemp.createTempSync('dm_luidlijn_');
    setAppDirForTest(scratch.path);
    pc = LibraryStore()
      ..rootPath = scratch.path
      ..configDirOverride = scratch.path;
    pc.tracks.addAll([
      _t('${scratch.path}/p1.flac', 'Een', 'Plaat', 1),
      _t('${scratch.path}/p2.flac', 'Twee', 'Plaat', 2),
      _t('${scratch.path}/p3.flac', 'Drie', 'Plaat', 3),
      _t('${scratch.path}/s.flac', 'Los', 'Andere', 1, grootte: 9000),
    ]);
    pc.rebuildAlbums();
    catalog = LanCatalog(pc);
  });

  tearDown(() {
    catalog.dispose();
    try {
      scratch.deleteSync(recursive: true);
    } on FileSystemException {/* een achtergebleven map is geen gezakte toets waard */}
  });

  LibraryStore telefoon() => LibraryStore()
    ..remote = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://192.168.0.117:47820'), token: 't'));

  void meetAlles(List<Luidheidsuitslag> uitslagen, {bool klaar = true}) {
    for (var i = 0; i < pc.tracks.length; i++) {
      zetLuidheidVoorTest(pc.tracks[i], uitslagen[i], klaar: klaar);
    }
  }

  Bijstelling reken(LibraryStore bib, Track t, {required bool alsPlaat}) {
    final album = bib.albumForPath(t.path)!;
    return bijstellingVoorNummer(t,
        rij: alsPlaat ? album.tracks : [t],
        plek: alsPlaat ? album.tracks.indexOf(t) : 0,
        opVolgorde: alsPlaat,
        stand: Luidheidsstand.normaal,
        albumGeheel: true,
        albumVan: bib.albumForPath);
  }

  test('DE KERN: de telefoon rekent hetzelfde uit als de pc — per nummer én als plaat', () {
    meetAlles([
      Gemeten(const Luidheidsmeting(lufs: -9, piek: -1.5)),
      Gemeten(const Luidheidsmeting(lufs: -16, piek: -4)),
      Gemeten(const Luidheidsmeting(lufs: -11, piek: 1.8)),
      Gemeten(const Luidheidsmeting(lufs: -7.5, piek: 0.4)),
    ]);
    publiceerLuidheid(nummers: pc.tracks, ffmpeg: true, kaartOok: true);
    final opPc = {
      for (final t in pc.tracks)
        t.title: (reken(pc, t, alsPlaat: false).db, reken(pc, t, alsPlaat: true).db)
    };
    final json = utf8.decode(catalog.snapshot().json);

    // Nu de telefoon: niets van de pc in het geheugen, alleen wat er over de lijn kwam.
    resetLuidheidVoorTest();
    final gsm = telefoon();
    expect(gsm.adoptMirror(jsonDecode(json) as Map<String, dynamic>, vanToestel: true), isTrue);
    for (final t in gsm.tracks) {
      expect((reken(gsm, t, alsPlaat: false).db, reken(gsm, t, alsPlaat: true).db), opPc[t.title],
          reason: '${t.title}: de telefoon moet dezelfde dB uitrekenen als de pc');
    }
    expect(opPc['Twee']!.$1, isNot(opPc['Twee']!.$2), reason: 'de toets moet album en nummer onderscheiden');
  });

  test('DE KERN: een meting beweegt de ETag pas bij publiceren', () {
    meetAlles(List.filled(4, Gemeten(const Luidheidsmeting(lufs: -10, piek: -3))));
    final voor = catalog.snapshot().etag;
    pc.rebuildAlbums(); // de catalogus wordt herbouwd, maar er is niets gepubliceerd
    expect(catalog.snapshot().etag, voor,
        reason: 'anders haalt elke telefoon tijdens de veegronde elke 15 s de hele catalogus');
    publiceerLuidheid(nummers: pc.tracks, ffmpeg: true, kaartOok: true);
    expect(catalog.snapshot().etag, isNot(voor));
    final opnieuw = catalog.snapshot().etag;
    publiceerLuidheid(nummers: pc.tracks, ffmpeg: true, kaartOok: true);
    expect(catalog.snapshot().etag, opnieuw, reason: 'zelfde publicatie, zelfde ETag');
  });

  test('DE GRENS: zonder winkel blijft de catalogus precies zoals vroeger', () {
    final j = jsonDecode(utf8.decode(catalog.snapshot().json)) as Map<String, dynamic>;
    expect(j.containsKey('luidheid'), isFalse);
    expect((j['tracks'] as List).any((t) => (t as Map).containsKey('luid')), isFalse);
  });

  test('DE KERN: een bijgewerkte pc stuurt meteen een status — vóór de veger begint', () async {
    await laadLuidheid();
    final j = jsonDecode(utf8.decode(catalog.snapshot().json)) as Map<String, dynamic>;
    expect(j['luidheid'], isA<Map>());
    resetLuidheidVoorTest();
    final gsm = telefoon()..adoptMirror(j, vanToestel: true);
    expect(gsm.tracks, isNotEmpty);
    expect(luidheidStatusTekst(eigenaar: false, vanPc: statusVanPc), startsWith('De pc begint zo met meten'),
        reason: 'anders vraagt de telefoon je de pc bij te werken die je net bijwerkte');
    expect(reken(gsm, gsm.tracks.first, alsPlaat: false).bron, Bijstelbron.pcNietKlaar);
  });

  test('DE GRENS: een catalogus zonder status wist de oude status', () {
    zetLuidheidStatusVanPc({'v': 1, 'klaar': true, 'ffmpeg': true, 'gemeten': 3, 'mislukt': 0, 'totaal': 4});
    final j = jsonDecode(utf8.decode(catalog.snapshot().json)) as Map<String, dynamic>;
    telefoon().adoptMirror(j, vanToestel: true);
    expect(statusVanPc, isNull, reason: 'een oudere pc mag geen "klaar" van een andere achterlaten');
  });

  test('DE KERN: meerkanaals en mislukt reizen zonder getallen en geven op de telefoon 0', () {
    meetAlles([
      const Meerkanaals(6),
      const Mislukt('Invalid data'),
      Gemeten(const Luidheidsmeting(lufs: -9, piek: -2)),
      Gemeten(const Luidheidsmeting(lufs: -70, piek: kPiekOndergrens)),
    ]);
    publiceerLuidheid(nummers: pc.tracks, ffmpeg: true, kaartOok: true);
    final bytes = catalog.snapshot().json;
    final j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final luid = {for (final t in j['tracks'] as List) (t as Map)['title']: t['luid']};
    expect(luid['Een'], {'mk': 6});
    expect(luid['Twee'], {'f': 1});
    expect((luid['Los'] as Map)['tp'], kPiekOndergrens, reason: 'een stil nummer breekt de catalogus niet');

    resetLuidheidVoorTest();
    final gsm = telefoon()..adoptMirror(j, vanToestel: true);
    final een = gsm.tracks.firstWhere((t) => t.title == 'Een');
    final drie = gsm.tracks.firstWhere((t) => t.title == 'Drie');
    expect(reken(gsm, een, alsPlaat: true).db, 0);
    expect(reken(gsm, een, alsPlaat: true).bron, Bijstelbron.meerkanaals);
    // Een plaat met een meerkanaals- en een mislukt nummer: de plaatwaarde komt van de rest.
    final d = reken(gsm, drie, alsPlaat: true);
    expect(d.alsAlbum, isTrue, reason: 'mislukt en meerkanaals tellen als definitief');
    expect(d.db, closeTo(-5, 1e-9));
  });

  test('DE GRENS: rommel in het luid-veld is geen meting', () {
    onthoudLuidheidVanPc(sizeBytes: 10, addedMs: 20, luid: {'i': 'x', 'tp': double.nan});
    zetLuidheidStatusVanPc({'v': 1, 'klaar': true});
    final t = Track(path: 'http://pc/stream/a.flac', title: 'a', artist: '', album: '', sizeBytes: 10, addedMs: 20);
    expect(
        bijstellingVoorNummer(t,
                rij: [t],
                plek: 0,
                opVolgorde: false,
                stand: Luidheidsstand.normaal,
                albumGeheel: true,
                albumVan: (_) => null)
            .db,
        0);
  });

  test('DE VAL: op een toestel is een stream-adres gewoon een bibliotheeknummer, geen online radio', () {
    onthoudLuidheidVanPc(sizeBytes: 10, addedMs: 20, luid: {'i': -8.0, 'tp': -2.0});
    zetLuidheidStatusVanPc({'v': 1, 'klaar': true});
    final t = Track(path: 'http://pc:47820/stream/abc.flac', title: 'a', artist: '', album: '', sizeBytes: 10, addedMs: 20);
    final b = bijstellingVoorNummer(t,
        rij: [t], plek: 0, opVolgorde: false, stand: Luidheidsstand.normaal, albumGeheel: true, albumVan: (_) => null);
    expect(b.db, closeTo(-6, 1e-9), reason: 'op de telefoon is elk pad een http-adres van de pc');
  });

  group('na ronde 1 van de beoordelaars', () {
    test('DE KERN: een telefoon bij een oude pc zegt "werk je pc bij", niet "pc meet nog"', () {
      final gsm = telefoon()..adoptMirror(jsonDecode(utf8.decode(catalog.snapshot().json)) as Map<String, dynamic>,
          vanToestel: true);
      expect(statusVanPc, isNull, reason: 'een oude pc stuurt geen status');
      expect(reken(gsm, gsm.tracks.first, alsPlaat: false).bron, Bijstelbron.pcOud);
      zetLuidheidStatusVanPc({'v': 1, 'klaar': false, 'ffmpeg': false, 'gemeten': 0, 'mislukt': 0, 'totaal': 4});
      expect(reken(gsm, gsm.tracks.first, alsPlaat: false).bron, Bijstelbron.pcZonderFfmpeg);
    });

    test('DE GRENS: de pc zonder ffmpeg zegt dat ook', () async {
      await laadLuidheid();
      publiceerLuidheid(nummers: pc.tracks, ffmpeg: false, kaartOok: true);
      expect(reken(pc, pc.tracks.first, alsPlaat: false).bron, Bijstelbron.pcZonderFfmpeg);
    });

    test('DE VAL: vóór de eerste ronde klaar is gaat er geen kaart uit', () {
      meetAlles(List.filled(4, Gemeten(const Luidheidsmeting(lufs: -10, piek: -3))), klaar: false);
      publiceerLuidheid(nummers: pc.tracks, ffmpeg: true, kaartOok: true);
      final j = jsonDecode(utf8.decode(catalog.snapshot().json)) as Map<String, dynamic>;
      expect((j['tracks'] as List).any((t) => (t as Map).containsKey('luid')), isFalse,
          reason: 'een halve kaart = een halve bibliotheek bijgesteld, de rest niet');
      expect((j['luidheid'] as Map)['klaar'], false);
    });

    test('DE KERN: na een herstart staat de bewaarde kaart er meteen, vóór de veger', () async {
      await laadLuidheid();
      meetAlles(List.filled(4, Gemeten(const Luidheidsmeting(lufs: -10, piek: -3))));
      await bewaarLuidheid();
      resetLuidheidVoorTest();
      await laadLuidheid(); // en verder niets: geen publiceerLuidheid, geen veger
      expect(gepubliceerdeLuidheid(pc.tracks.first), {'i': -10.0, 'tp': -3.0},
          reason: 'anders wist de eerste catalogus na een herstart de kopie op elke telefoon');
      expect(gepubliceerdeStatus?.klaar, isTrue);
    });

    test('DE KERN: geschud speelt per nummer, ook op een plaat', () {
      meetAlles([
        Gemeten(const Luidheidsmeting(lufs: -9, piek: -1.5)),
        Gemeten(const Luidheidsmeting(lufs: -16, piek: -4)),
        Gemeten(const Luidheidsmeting(lufs: -11, piek: 1.8)),
        Gemeten(const Luidheidsmeting(lufs: -7.5, piek: 0.4)),
      ]);
      final album = pc.albumForPath(pc.tracks[1].path)!;
      Bijstelling met({required bool volgorde}) => bijstellingVoorNummer(pc.tracks[1],
          rij: album.tracks,
          plek: 1,
          opVolgorde: volgorde,
          stand: Luidheidsstand.normaal,
          albumGeheel: true,
          albumVan: pc.albumForPath);
      expect(met(volgorde: true).alsAlbum, isTrue);
      expect(met(volgorde: false).alsAlbum, isFalse);
    });

    test('DE KERN: een verzamelalbum op volgorde gaat per nummer, en het blad zegt waarom', () {
      final bib = LibraryStore()
        ..rootPath = scratch.path
        ..configDirOverride = scratch.path;
      bib.tracks.addAll([
        for (var i = 1; i <= 3; i++) _t('${scratch.path}/gh$i.flac', 'Hit $i', 'Greatest Hits', i, grootte: 7000),
      ]);
      bib.rebuildAlbums();
      for (final t in bib.tracks) {
        zetLuidheidVoorTest(t, Gemeten(Luidheidsmeting(lufs: -9.0 - t.trackNo, piek: -2)));
      }
      final album = bib.albumForPath(bib.tracks.first.path)!;
      final b = bijstellingVoorNummer(bib.tracks.first,
          rij: album.tracks,
          plek: 0,
          opVolgorde: true,
          stand: Luidheidsstand.normaal,
          albumGeheel: true,
          albumVan: bib.albumForPath);
      expect(b.alsAlbum, isFalse);
      expect(b.verzamelaar, isTrue);
      expect(b.db, closeTo(-4, 1e-9), reason: 'zijn eigen −10 naar −14');
    });

    test('DE VAL: twee bestanden met dezelfde sleutel gaan nooit omhoog', () {
      final a = _t('${scratch.path}/x1.flac', 'X', 'Los1', 1, grootte: 8000);
      final b = _t('${scratch.path}/x2.flac', 'X', 'Los2', 1, grootte: 8000);
      expect(luidheidSleutel(a), luidheidSleutel(b));
      zetLuidheidVoorTest(a, Gemeten(const Luidheidsmeting(lufs: -20, piek: -10)));
      Bijstelling met(Iterable<Track> Function()? bib) => bijstellingVoorNummer(a,
          rij: [a],
          plek: 0,
          opVolgorde: false,
          stand: Luidheidsstand.normaal,
          albumGeheel: true,
          albumVan: (_) => null,
          bibliotheek: bib);
      expect(met(() => [a]).db, closeTo(6, 1e-9));
      final dubbel = met(() => [a, b]);
      expect(dubbel.db, 0, reason: 'de meting kan van het andere bestand zijn');
      expect(dubbel.bron, Bijstelbron.klemNul);
    });
  });

  group('de Shield', () {
    test('DE KERN: shieldLijst houdt de opgave parallel aan de adressen, ook bij een gat', () {
      final a = _t('/a.flac', 'A', 'P', 1), c = _t('/c.flac', 'C', 'P', 3);
      final plekken = <int>[];
      final l = shieldLijst(
        trackIds: ['a', 'b', 'c'],
        tracks: [a, null, c],
        adres: (id, t) => 'http://pc/stream/$id.flac',
        opgave: (t, rij, plek) {
          plekken.add(plek);
          return {'i': -9.0, 'tp': -2.0, 'titel': t.title};
        },
      );
      expect(l.urls, ['http://pc/stream/a.flac', 'http://pc/stream/c.flac']);
      expect([for (final o in l.luidheid) o!['titel']], ['A', 'C'], reason: 'geen verschuiving naar de buurman');
      expect(plekken, [0, 1]);
    });

    test('DE KERN: de ontvanger rekent met de opgave van de zender, ook de plaat en de stand', () {
      const url = 'http://pc:47820/stream/x.flac?token=t';
      onthoudLuidheidVanZender({
        url: {'i': -12.5, 'tp': 2.4, 'alb': true, 'ai': -12.5, 'atp': 2.4, 'stand': 'normaal'},
      });
      final t = Track(path: url, title: 'x', artist: '', album: '');
      final b = bijstellingVoorNummer(t,
          rij: [t], plek: 0, opVolgorde: false, stand: Luidheidsstand.luid, albumGeheel: true, albumVan: (_) => null);
      expect(b.alsAlbum, isTrue);
      expect(b.db, closeTo(-2.9, 1e-9), reason: 'stand van de zender (Gelijk) en de klem met de eigen piek');
      onthoudLuidheidVanZender({url: {'mk': 6}});
      expect(
          bijstellingVoorNummer(t,
                  rij: [t], plek: 0, opVolgorde: false, stand: Luidheidsstand.normaal, albumGeheel: true, albumVan: (_) => null)
              .db,
          0);
    });

    test('DE KERN: de stand van de zender gaat voor, ook boven Uit op de Shield', () {
      const url = 'http://pc:47820/stream/z.flac?token=t';
      onthoudLuidheidVanZender({
        url: {'i': -8.0, 'tp': -3.0, 'stand': 'normaal'},
      });
      final t = Track(path: url, title: 'z', artist: '', album: '');
      final b = bijstellingVoorNummer(t,
          rij: [t], plek: 0, opVolgorde: false, stand: Luidheidsstand.uit, albumGeheel: true, albumVan: (_) => null);
      expect(b.db, closeTo(-6, 1e-9));
      expect(b.vanZender, isTrue, reason: 'het blad toont dan geen keuzes die niets doen');
      onthoudLuidheidVanZender({
        url: {'i': -8.0, 'tp': -3.0, 'stand': 'uit'},
      });
      expect(
          bijstellingVoorNummer(t,
                  rij: [t], plek: 0, opVolgorde: false, stand: Luidheidsstand.normaal, albumGeheel: true, albumVan: (_) => null)
              .db,
          0,
          reason: 'de pc staat op Uit');
    });

    test('DE GRENS: een zender zonder opgave speelt zoals vroeger', () {
      final t = Track(path: 'http://pc/stream/y.flac', title: 'y', artist: '', album: '');
      final b = bijstellingVoorNummer(t,
          rij: [t], plek: 0, opVolgorde: false, stand: Luidheidsstand.normaal, albumGeheel: true, albumVan: (_) => null);
      expect(b.db, 0);
      expect(b.bron, Bijstelbron.online);
    });
  });

  group('de bedrading in de speler', () {
    final speler = File('lib/player.dart').readAsStringSync().replaceAll('\r\n', '\n');

    test('DE KERN: vóór elke open wordt de versterking vastgelegd onder het adres dat opent', () {
      for (final kop in ['Future<void> _openCurrent() async {', 'Future<void> _openRadioCurrent(', 'Future<void> restore(']) {
        final lijf = _lijf(speler, kop);
        final zet = lijf.indexOf('_zetLuidheid(');
        final open = lijf.indexOf('_player.open(Media(bron)');
        expect(zet, isNonNegative, reason: '$kop legt de versterking niet vast');
        expect(open, greaterThan(zet), reason: '$kop: vastleggen hoort vóór het openen');
        expect(lijf.substring(0, zet), contains('final bron = _bron('), reason: '_bron één keer, adres doorgeven');
      }
    });

    test('DE VAL: hervatten na een hapering neemt de lopende waarde over, en rekent niet opnieuw', () {
      final lijf = _lijf(speler, 'Future<void> _hervatOpDezelfdePlek() async {');
      expect(lijf, isNot(contains('_zetLuidheid(')));
      final over = lijf.indexOf('_onthoudLuidheid(bron');
      expect(over, isNonNegative, reason: 'zonder dit sprong een luid nummer halverwege 6–9 dB omhoog');
      expect(lijf.indexOf('_player.open(Media(bron)'), greaterThan(over));
    });

    test('DE KERN: de laadhaak zoekt op mpv\'s eigen pad en schrijft alleen replaygain-fallback', () {
      final lijf = _lijf(speler, 'Future<void> _luidheidHaak() async {');
      expect(lijf, contains("getProperty('path')"));
      expect(lijf, contains('adresSleutel(pad'), reason: 'mpv zegt \\\\?\\D:\\… op Windows');
      expect(lijf, contains("setProperty('replaygain-fallback'"));
      expect(lijf, contains('final db = w?.db ?? 0.0;'), reason: 'onbekend adres → 0 dB, nooit een andere waarde');
      final vang = lijf.substring(lijf.indexOf('} catch (e) {'));
      expect(vang, contains("setProperty('replaygain-fallback', '0.00')"),
          reason: 'faalt de haak, dan bleef de versterking van het vorige nummer staan op dit nummer');
      expect(lijf, isNot(contains("'volume'")));
      expect(lijf, isNot(contains("'af'")));
      final basis = _lijf(speler, 'Future<void> _zetLuidheidBasis() async {');
      expect(basis, contains("setProperty('replaygain', 'no')"));
      expect(basis, contains('onLoadHooks.add(_luidheidHaak)'));
      expect(basis, isNot(contains("setProperty('replaygain-fallback'")),
          reason: 'fallback=0 bij de start kan een vroege eerste waarde overschrijven');
    });

    test('DE GRENS: de demping en het volume blijven onaangeroerd', () {
      expect(_lijf(speler, 'void zetDemping(bool aan) {'), isNot(contains('uidheid')));
      expect(_lijf(speler, 'void setVolume(double v) {'), isNot(contains('uidheid')));
      expect(_lijf(speler, 'String _bron(String path) {'), isNot(contains('uidheid')));
    });

    test('DE KERN: de A/B-wissel schrijft onder het adres dat de haak het laatst toepaste', () {
      final lijf = _lijf(speler, 'Future<void> herzieLuidheid() async {');
      expect(lijf, contains('final adres = _adresNu;'));
      expect(lijf, contains('_luidheidPerAdres[adres] ='));
    });
  });
}

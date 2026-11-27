// Spelen in een groep (Sonos Move + Shield), 27-11-2026. Saber, die ochtend:
//  * "oei nu skipte het liedjes sign of time ? hoe komt dit" — een AIFF van 24/44,1 ging als origineel naar de Sonos en de
//    Shield, en beide sprongen door (A);
//  * "ik bewerkte daarnet de cd afbeelding … op de mac veranderde die maar niet op de shield terwijl die daar speelde?" —
//    een onbediende tv haalt de catalogus hoogstens om de tien minuten (B);
//  * "volume aanpassen moet nog iets vlotter" — schuif stroef, te grove stappen (C);
//  * "tijdens het liedje zelf alsof het vertraagd en weer op tempo komt" — de gelijkloop speelde seconden lang 3 % trager
//    (D).
import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/audioformaten.dart';
import 'package:debridmusic/ffmpeg.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/samen.dart';
import 'package:debridmusic/zone_speler.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

String bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

/// Een speler die bijhoudt wat de volger vraagt, op een plek die de toets zet.
class _Speler implements VolgSpeler {
  _Speler(this.t);
  final Track t;
  Duration plek = Duration.zero;
  final seeks = <Duration>[];

  /// Waar de speler na een sprong landt (zoals mpv: ongeveer waar gevraagd). Null: hij blijft staan.
  Duration Function(Duration doel)? naSprong;
  final snelheden = <double>[];
  @override
  bool playing = true;
  @override
  Track? get current => t;
  @override
  Duration get positieNauwkeurig => plek;
  @override
  List<Track> get queueTracks => [t];
  @override
  void pauzeer() => playing = false;
  @override
  void seek(Duration d) {
    seeks.add(d);
    final n = naSprong;
    if (n != null) plek = n(d);
  }
  @override
  void speelAf() => playing = true;
  @override
  Future<void> zetSnelheid(double v) async => snelheden.add(v);
  @override
  Future<void> neemOver(List<Track> r, int i, Duration positie,
      {bool spelen = true, bool shuffle = false, RepeatMode herhaal = RepeatMode.off}) async {}
  @override
  bool zetRijRondHuidig(List<Track> r, int i) => true;
}

void main() {
  group('A: wat niet elke speler leest, gaat als FLAC', () {
    test('AIFF, WAV, WavPack, APE … wel; FLAC, mp3 en DSD niet', () {
      for (final e in ['aiff', '.AIF', 'aifc', 'wav', 'wv', 'ape', 'tta', 'alac']) {
        expect(alsFlacVersturen(e), isTrue, reason: e);
      }
      for (final e in ['flac', 'mp3', 'm4a', 'dsf', 'dff', 'ogg', '']) {
        expect(alsFlacVersturen(e), isFalse, reason: e);
      }
    });

    final ffmpeg = Ffmpeg().pad;
    test('de pc: catalogus op .flac, en wie .flac vraagt krijgt FLAC — het origineel blijft op .aiff', () async {
      final root = Directory.systemTemp.createTempSync('groep_vlot_');
      final map = Directory('${root.path}/Harry Styles/Harry Styles')..createSync(recursive: true);
      final aiff = File('${map.path}/02 - Sign of the Times.aiff');
      final r = await Process.run(ffmpeg!, [
        '-v', 'error', '-y', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100:duration=3', //
        '-ac', '2', '-c:a', 'pcm_s24be', aiff.path,
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final library = LibraryStore()..rootPath = root.path;
      // Zoals op de pc: de diepte van een AIFF kent de catalogus niet.
      library.tracks.add(Track(
          path: aiff.path,
          title: 'Sign of the Times',
          artist: 'Harry Styles',
          album: 'Harry Styles',
          trackNo: 2,
          duration: const Duration(seconds: 3),
          sizeBytes: aiff.lengthSync(),
          sampleRate: 44100));
      library.rebuildAlbums();
      final server = LanServer(
        library: library,
        token: 'test-token',
        state: LanStateStore(File('${root.path}/state.json')),
        pairing: PairingStore(),
        port: 0,
        version: '1',
      );
      expect(await server.start(), isNull);
      final client = HttpClient();
      Future<HttpClientResponse> get(String pad) async {
        final q = await client.getUrl(Uri.parse('http://127.0.0.1:${server.boundPort}$pad'));
        q.headers.set(HttpHeaders.authorizationHeader, 'Bearer test-token');
        return q.close();
      }

      try {
        final cat = jsonDecode(await (await get('/api/catalog')).transform(utf8.decoder).join()) as Map<String, dynamic>;
        final t = (cat['tracks'] as List).single as Map<String, dynamic>;
        expect(t['streamPath'], endsWith('.flac'));
        expect(t['mime'], 'audio/flac');
        expect(t['ext'], 'aiff', reason: 'wat het bestand is, blijft gezegd');
        final id = t['id'] as String;

        Future<List<int>> kop(String pad) async {
          final res = await get(pad);
          expect(res.statusCode, anyOf(200, 206), reason: pad);
          final b = <int>[];
          await for (final c in res) {
            b.addAll(c);
          }
          return b.take(4).toList();
        }

        expect(ascii.decode(await kop('/stream/$id.flac')), 'fLaC');
        expect(ascii.decode(await kop('/stream/$id.aiff')), 'FORM', reason: 'wie het origineel vraagt, krijgt het');
      } finally {
        client.close(force: true);
        await server.dispose();
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      }
    }, skip: ffmpeg == null ? 'geen ffmpeg' : false);

    test('de speakers krijgen het ook als FLAC, met het audiotype erbij', () {
      final c = bron('lib/lan/cast_manager.dart');
      expect(c, contains("if (alsFlacVersturen(ext) && _transcoder.available) return 'http://\$base:\$port/stream/\$id.flac?token=\$token&cast=1';"));
      expect(c, isNot(contains('mime: mimeForExt(')));
      expect(RegExp(r'mime: _mimeVoor\(').allMatches(c).length, 5);
    });
  });

  group('B: een keuze komt meteen op een onbediende tv', () {
    test('het keuzemerk beweegt bij een aangewezen cd, niet bij een nieuw nummer', () async {
      final root = Directory.systemTemp.createTempSync('groep_keuze_');
      final library = LibraryStore()..rootPath = root.path;
      Track t(String titel, String album) =>
          Track(path: '${root.path}/$album/$titel.flac', title: titel, artist: 'Eminem', album: album, isFlac: true);
      library.tracks.add(t('The Real Slim Shady', 'The Real Slim Shady'));
      library.rebuildAlbums();
      final server = LanServer(
        library: library,
        token: 'test-token',
        state: LanStateStore(File('${root.path}/state.json')),
        pairing: PairingStore(),
        port: 0,
        version: '1',
      );
      expect(await server.start(), isNull);
      final client = HttpClient();
      Future<({String? merk, String? keuze})> vraag() async {
        final q = await client.getUrl(Uri.parse('http://127.0.0.1:${server.boundPort}/api/catalog?alleenMerk=1'));
        q.headers.set(HttpHeaders.authorizationHeader, 'Bearer test-token');
        final res = await q.close();
        await res.drain<void>();
        return (merk: res.headers.value(HttpHeaders.etagHeader), keuze: res.headers.value('x-keuze-merk'));
      }

      try {
        final eerst = await vraag();
        expect(eerst.keuze, isNotNull);

        // Een nieuw nummer (een download die landt): het merkteken beweegt, het keuzemerk niet.
        library.tracks.add(t('Stan', 'The Marshall Mathers LP'));
        library.rebuildAlbums();
        library.notifyListeners();
        final na = await vraag();
        expect(na.merk, isNot(eerst.merk));
        expect(na.keuze, eerst.keuze, reason: 'anders haalt een onbediende tv weer bij elk geland nummer alles');

        // Een cd die je aanwees: het keuzemerk beweegt.
        await library.setAlbumArtRole('Eminem', 'The Real Slim Shady', 'disc', 'https://coverartarchive.org/x.jpg');
        final keuze = await vraag();
        expect(keuze.keuze, isNot(na.keuze));

        // En een andere cd in de plaats van die aangewezen cd: weer een ander merk.
        await library.setAlbumArtRole('Eminem', 'The Real Slim Shady', 'disc', 'https://coverartarchive.org/y.jpg');
        expect((await vraag()).keuze, isNot(keuze.keuze));
      } finally {
        client.close(force: true);
        await server.dispose();
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('het toestel haalt bij een ander keuzemerk meteen de echte catalogus, ook in het venster', () {
      final l = bron('lib/library.dart');
      expect(l, contains('    if (res.uitgesteld && !vers && keuze != null && _keuzeMerk != null && keuze != _keuzeMerk) {\n'));
      expect(l, contains('      return loadRemote(quiet: quiet, vers: true);\n'));
      expect(l, contains('    _keuzeMerk = res.keuzeMerk;\n'));
      final c = bron('lib/lan/client.dart');
      expect(c, contains("    final keuze = res.headers['x-keuze-merk'];\n"));
      expect(c, contains('      return CatalogResponse(null, res.headers[\'etag\'], uitgesteld: true, keuzeMerk: keuze);\n'));
    });
  });

  group('C: het volume van een groep', () {
    test('elk lid naar verhouding: wie luider stond blijft luider, en op 0 is alles stil', () {
      final leden = {'sonos': 38, 'shield': 44};
      expect(groepsVolumes(leden, 41), leden, reason: 'het gemiddelde zelf: niemand springt');
      expect(groepsVolumes(leden, 45), {'sonos': 42, 'shield': 48});
      expect(groepsVolumes(leden, 30), {'sonos': 28, 'shield': 32});
      expect(groepsVolumes(leden, 100), {'sonos': 93, 'shield': 100}, reason: 'niet boven 100');
      expect(groepsVolumes(leden, 0), {'sonos': 0, 'shield': 0}, reason: 'de schuif helemaal links: alles stil');
      expect(groepsVolumes({'a': 0, 'b': 0}, 20), {'a': 20, 'b': 20}, reason: 'vanuit stilte: allemaal de stand zelf');
      expect(groepsVolumes(const {}, 50), isEmpty);
    });

    test('fijnere stappen, en de schuif van de groep gebruikt ze', () {
      expect(kZoneVolumeTussen, const Duration(milliseconds: 40));
      final m = bron('lib/main.dart');
      expect(m, contains('final doelen = groepsVolumes({for (final l in metVolume) l.id: l.volume}, v);'));
      expect(m, contains("opdracht(l.id, {'cmd': 'volume', 'waarde': doelen[l.id] ?? v});"));
    });

    test('een toestel meldt zijn volume pas als het schuiven even stilstaat', () {
      final p = bron('lib/player.dart');
      expect(PlayerStore.kVolumeMeldenNa, const Duration(milliseconds: 250));
      final i = p.indexOf('  void setVolume(double v) {\n    v = v.clamp(0, 100).toDouble();');
      final stuk = p.substring(i, p.indexOf('\n  }\n', i));
      expect(stuk, contains('_volumeMelding = Timer(kVolumeMeldenNa, () => unawaited(_saveProgress(force: true)));'));
      expect(stuk, isNot(contains('unawaited(_saveProgress(force: true));\n')));
    });
  });

  group('D: gelijk blijven zonder hoorbaar vertragen', () {
    test('nooit meer dan 1 % sneller of trager; vanaf 150 ms spoelen', () {
      expect(bijsturing(140).snelheid, closeTo(0.99, 1e-9));
      expect(bijsturing(-140).snelheid, closeTo(1.01, 1e-9));
      expect(bijsturing(160).spoel, isTrue);
      expect(bijsturing(60).spoel, isFalse);
      expect(bijsturing(60, begin: true).spoel, isTrue, reason: 'net begonnen: meteen goedzetten');
      expect(bijsturing(30, begin: true).spoel, isFalse);
    });

    Track nr(String id) => Track(path: '/m/$id.flac', title: id, artist: 'A', album: 'B');
    SamenAnker anker(String id, int positieMs) =>
        SamenAnker(groep: 'spk:move', trackId: id, rij: [id], index: 0, positieMs: positieMs, pcMs: KlokIjk().nuPcMs(), speelt: true);

    test('een nummer dat 200 ms te vroeg begint: één sprong, daarna alleen zacht bijsturen', () {
      fakeAsync((fa) {
        final t = nr('x');
        // Na de sprong 60 ms voor (de marge voor het spoelen zelf): binnen het begin, maar al eens gespoeld.
        final speler = _Speler(t)
          ..plek = const Duration(milliseconds: 2200)
          ..naSprong = (d) => d;
        final v = SamenVolger(
            speler: speler,
            nummer: (_) => t,
            idVan: (x) => x.title,
            klok: KlokIjk(),
            vertragingMs: () => 0,
            nuMs: () => 1000000 + fa.elapsed.inMilliseconds);
        v.opAnker(anker('x', 2000));
        fa.elapse(const Duration(milliseconds: 600));
        expect(speler.seeks, hasLength(1), reason: 'meteen goedzetten, niet zes seconden op 0,97');
        // Ook na de rust van vier seconden niet nog eens: één vroege sprong per nummer.
        fa.elapse(const Duration(seconds: 5));
        expect(speler.seeks, hasLength(1));
        expect(speler.snelheden.where((s) => (s - 1).abs() > 0.0101), isEmpty, reason: 'hoogstens 1 %');
        v.stop(pauzeer: false);
        fa.flushTimers(flushPeriodicTimers: false);
      });
    });

    test('na een pauze 120 ms te vroeg verder: één sprong, zoals bij een nieuw nummer (09:16)', () {
      fakeAsync((fa) {
        final t = nr('p');
        // Elke sprong landt 60 ms verder dan gevraagd: het hervatten 60 ms te vroeg, de sprong daarna (met zijn eigen marge van
        // 60 ms) 120 ms. Dan blijft het bij één vroege sprong, en de rest stuurt zacht bij.
        final speler = _Speler(t)
          ..playing = false
          ..plek = const Duration(seconds: 120)
          ..naSprong = (d) => d + const Duration(milliseconds: 60);
        final v = SamenVolger(
            speler: speler,
            nummer: (_) => t,
            idVan: (x) => x.title,
            klok: KlokIjk(),
            vertragingMs: () => 0,
            nuMs: () => 1000000 + fa.elapsed.inMilliseconds);
        v.opAnker(anker('p', 120000));
        fa.elapse(const Duration(milliseconds: 600));
        expect(speler.seeks, hasLength(2), reason: 'het hervatten, en één sprong om het goed te zetten');
        fa.elapse(const Duration(seconds: 6));
        expect(speler.seeks, hasLength(2), reason: 'daarna alleen nog zacht bijsturen');
        expect(speler.snelheden.where((s) => (s - 1).abs() > 0.0101), isEmpty);
        v.stop(pauzeer: false);
        fa.flushTimers(flushPeriodicTimers: false);
      });
    });

    test('midden in een nummer 100 ms voor: geen sprong, hoogstens 1 % trager', () {
      fakeAsync((fa) {
        final t = nr('y');
        final speler = _Speler(t)..plek = const Duration(milliseconds: 60100);
        final v = SamenVolger(speler: speler, nummer: (_) => t, idVan: (x) => x.title, klok: KlokIjk(), vertragingMs: () => 0);
        v.opAnker(anker('y', 60000));
        fa.elapse(const Duration(seconds: 2));
        expect(speler.seeks, isEmpty);
        expect(speler.snelheden, isNotEmpty);
        expect(speler.snelheden.last, closeTo(0.99, 1e-9));
        v.stop(pauzeer: false);
        fa.flushTimers(flushPeriodicTimers: false);
      });
    });

    test('midden in een nummer 300 ms voor: spoelen', () {
      fakeAsync((fa) {
        final t = nr('z');
        // De sprong komt 200 ms verkeerd uit: toch niet meteen weer springen (rust).
        final speler = _Speler(t)
          ..plek = const Duration(milliseconds: 60300)
          ..naSprong = (d) => d + const Duration(milliseconds: 200);
        final v = SamenVolger(
            speler: speler,
            nummer: (_) => t,
            idVan: (x) => x.title,
            klok: KlokIjk(),
            vertragingMs: () => 0,
            nuMs: () => 1000000 + fa.elapsed.inMilliseconds);
        v.opAnker(anker('z', 60000));
        fa.elapse(const Duration(seconds: 3));
        expect(speler.seeks, hasLength(1), reason: 'niet vaker dan om de vier seconden');
        v.stop(pauzeer: false);
        fa.flushTimers(flushPeriodicTimers: false);
      });
    });
  });
}

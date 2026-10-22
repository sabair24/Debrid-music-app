/// Radio op een speaker (Saber, 22-10-2026: "pc draait, speaker speelt"): de speaker-uitgang van de radio
/// (`speaker_radio.dart`) en de radiosessie van de cast.
///
/// Wat hier vastligt: de rij gaat naar de speaker en de zone draagt de naam van de radio; de uitgang volgt
/// de speaker als hij doorschuift; een droge rij gaat meteen verder zodra de radio aanvult; "volgende" op het
/// laatste nummer zegt "wil verder" en het eerste nieuwe speelt meteen; "hierna" op de speakerzone komt in
/// de rij van de radio (de oude regels blijven dezelfde voorwerpen); weghalen; een andere wachtrij op de
/// speaker beëindigt de radio; loslaten zet de speaker op pauze.
library;

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/cast_manager.dart';
import 'package:debridmusic/lan/catalog.dart';
import 'package:debridmusic/lan/upnp.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/radio.dart';
import 'package:debridmusic/speaker_radio.dart';
import 'package:flutter/foundation.dart';

const _t0 = 1760000000000000; // µs

/// Een Sonos die speelt wat hij krijgt: ~0,4 s na openen begint hij; een nummer duurt 20 s; is er een volgende
/// (SetNext) dan gaat hij daar naadloos naartoe, anders staat hij op STOPPED.
class _Sonos extends UpnpControlPoint {
  _Sonos(this.nu);
  final int Function() nu;
  static const duurUs = 20000000;
  int beginUs = 0;
  String? uri, volgende;
  bool gepauzeerd = false;
  int? stilUs;
  final opdrachten = <String>[];
  String _id(String? u) => u == null ? '-' : RegExp(r'/stream/([^/.?]+)').firstMatch(u)?.group(1) ?? u;
  String get speelt => _id(uri);

  int _p() {
    if (stilUs != null) return stilUs!;
    var p = nu() - beginUs;
    if (p >= duurUs && volgende != null) {
      beginUs += duurUs;
      uri = volgende;
      volgende = null;
      p = nu() - beginUs;
    }
    return p;
  }

  bool get _gestopt => stilUs == null && uri != null && volgende == null && nu() - beginUs >= duurUs;

  @override
  Future<List<Renderer>> discover({Duration timeout = const Duration(seconds: 3)}) async => const [];
  @override
  Future<void> playUrl(Renderer r, String url,
      {required String title, required String artist, required String album, required String mime, String? artUrl, Duration? duration}) async {
    opdrachten.add('open $title');
    uri = url;
    volgende = null;
    stilUs = null;
    gepauzeerd = false;
    beginUs = nu() + 400000;
  }

  @override
  Future<void> setNextUrl(Renderer r, String url,
      {required String title, required String artist, required String album, required String mime, String? artUrl, Duration? duration}) async {
    volgende = url;
  }

  @override
  Future<void> pause(Renderer r) async {
    opdrachten.add('pause');
    stilUs = _p();
    gepauzeerd = true;
  }

  @override
  Future<void> play(Renderer r) async {
    opdrachten.add('play');
    if (gepauzeerd && stilUs != null) {
      beginUs = nu() - stilUs!;
      stilUs = null;
      gepauzeerd = false;
    }
  }

  @override
  Future<int?> getVolume(Renderer r) async => 30;
  @override
  Future<({Duration? position, Duration duration, String? trackUri})?> positionInfo(Renderer r) async {
    final p = _p();
    return (position: Duration(seconds: (p < 0 ? 0 : p) ~/ 1000000), duration: const Duration(seconds: 20), trackUri: uri);
  }

  @override
  Future<TransportState?> transportState(Renderer r) async {
    _p();
    return TransportState(gepauzeerd ? 'PAUSED_PLAYBACK' : (_gestopt ? 'STOPPED' : 'PLAYING'));
  }
}

/// De radio haalt een nummer: na drie seconden is het er (een bibliotheeknummer).
class _Bron implements Radiobron {
  _Bron(this.track);
  final Track Function(Radioplek p) track;
  @override
  Future<String?> begin() async => null;
  @override
  void einde() {}
  @override
  void staak() {}
  @override
  Future<Track?> haal(Radioplek p) async {
    await Future<void>.delayed(const Duration(seconds: 3));
    return track(p);
  }

  @override
  Future<bool> vergeet({required String pad, required String artiest, required String titel}) async => true;
}

/// De speler van de pc: mag in deze keten niets spelen.
class _Pc extends ChangeNotifier implements Radiospeler {
  final log = <String>[];
  @override
  Future<List<RadioItem>> Function()? radioExtend;
  @override
  void Function(List<RadioItem> gespeeld)? bijRadioEinde;
  @override
  void Function(RadioItem item, {required bool bestand})? bijRadioOverslaan;
  @override
  bool get playing => false;
  @override
  bool get radioDroog => false;
  @override
  bool get wilVerder => false;
  @override
  List<RadioItem> get radioQueue => const [];
  @override
  int get radioIndex => 0;
  @override
  Duration get duration => Duration.zero;
  @override
  Duration get positieErgens => Duration.zero;
  @override
  Future<void> playRadio(List<RadioItem> items, {int start = 0}) async => log.add('playRadio');
  @override
  void voegToeAanRadio(List<RadioItem> meer) => log.add('voegToe');
  @override
  Future<bool> haalUitRadio(String pad) async => false;
  @override
  RadioItem? wordtLokaalInRadio(RadioItem oud, Track t) => null;
  @override
  Future<void> verlaatRadio() async => log.add('verlaat');
}

const _move = Renderer(
    id: '192.168.0.188',
    name: 'Sonos Move',
    host: '192.168.0.188',
    avTransportUrl: 'http://192.168.0.188:1400/av',
    manufacturer: 'Sonos, Inc.',
    udn: 'RINCON_MOVE');

void main() {
  late Directory map;
  late LibraryStore library;
  late LanCatalog catalog;
  late List<String> ids;
  late Map<String, Track> perId;

  setUp(() {
    map = Directory.systemTemp.createTempSync('dm_spk_radio_');
    library = LibraryStore()..rootPath = map.path;
    library.tracks.addAll([
      for (final n in ['Een', 'Twee', 'Drie', 'Vier', 'Vijf'])
        Track(
          path: '${map.path}/A/Album/$n.flac',
          title: n,
          artist: 'A',
          album: 'Album',
          trackNo: 1,
          duration: const Duration(seconds: 20),
          isFlac: true,
          sizeBytes: 1000,
          sampleRate: 44100,
          bitsPerSample: 16,
        ),
    ]);
    library.rebuildAlbums();
    catalog = LanCatalog(library);
    final dtos = catalog.snapshot().catalog.tracks.toList()..sort((a, b) => a.title.compareTo(b.title));
    ids = [for (final t in dtos) t.id]; // Drie, Een, Twee, Vier, Vijf
    perId = {for (final id in ids) id: catalog.track(id)!};
  });

  tearDown(() {
    catalog.dispose();
    map.deleteSync(recursive: true);
  });

  ({CastManager cast, _Sonos sonos, SpeakerRadio uit, List<String> einde}) maak(FakeAsync fa) {
    int nu() => _t0 + fa.elapsed.inMicroseconds;
    final sonos = _Sonos(nu);
    final cast = CastManager(
      catalog: catalog,
      token: 't',
      port: 47820,
      upnp: sonos,
      startGrace: Duration.zero,
      klokUs: nu,
      adresVoor: (_) async => '192.168.0.117',
    )..kenSpeakersVoorToets([_move]);
    final padNaarId = {for (final e in perId.entries) e.value.path: e.key};
    final uit = SpeakerRadio(
        cast: cast, speaker: _move.id, idVan: (t) => padNaarId[t.path], naam: () => 'Radio A', klokMs: () => nu() ~/ 1000);
    final einde = <String>[];
    uit.bijRadioEinde = (gespeeld) => einde.add('einde ${gespeeld.length}');
    return (cast: cast, sonos: sonos, uit: uit, einde: einde);
  }

  RadioItem item(String id) => RadioItem(artist: 'A', title: perId[id]!.title, local: perId[id]);
  String titel(String id) => perId[id]!.title;

  test('de rij gaat naar de speaker, de zone draagt de naam; hij volgt de speaker als die doorschuift', () {
    fakeAsync((fa) {
      final m = maak(fa);
      final a = item(ids[0]), b = item(ids[1]);
      unawaited(m.uit.playRadio([a, b]));
      fa.flushMicrotasks();
      expect(m.sonos.opdrachten.first, 'open ${titel(ids[0])}');
      expect(m.cast.laatsteStanden.single.radio, 'Radio A');
      expect(m.uit.radioQueue, [a, b]);
      expect(m.uit.radioIndex, 0);
      // Naadloos naar het tweede (SetNext); de tik ziet het.
      fa.elapse(const Duration(seconds: 26));
      expect(m.sonos.speelt, ids[1]);
      expect(m.uit.radioIndex, 1);
      expect(identical(m.uit.radioQueue[1], b), isTrue, reason: 'dezelfde regel: de radio herkent hem');
      m.cast.dispose();
      fa.flushTimers(flushPeriodicTimers: false);
    });
  });

  test('droog: de rij is op, de sessie blijft open; wat de radio aanvult speelt meteen', () {
    fakeAsync((fa) {
      final m = maak(fa);
      unawaited(m.uit.playRadio([item(ids[0])]));
      fa.flushMicrotasks();
      fa.elapse(const Duration(seconds: 27));
      expect(m.uit.radioDroog, isTrue);
      expect(m.uit.playing, isFalse);
      expect(m.cast.laatsteStanden, isNotEmpty, reason: 'een radio houdt de sessie open');
      expect(m.einde, isEmpty);
      final c = item(ids[2]);
      m.uit.voegToeAanRadio([c]);
      fa.flushMicrotasks();
      expect(m.sonos.opdrachten.last, 'open ${titel(ids[2])}');
      expect(m.uit.radioDroog, isFalse);
      expect(m.uit.radioIndex, 1);
      expect(identical(m.uit.radioQueue[1], c), isTrue);
      m.cast.dispose();
      fa.flushTimers(flushPeriodicTimers: false);
    });
  });

  test('begint de radio zonder iets speelbaars, dan start het eerste dat landt de speaker', () {
    fakeAsync((fa) {
      final m = maak(fa);
      unawaited(m.uit.playRadio(const []));
      fa.flushMicrotasks();
      expect(m.sonos.opdrachten, isEmpty);
      expect(m.cast.rijVan(_move.id), isNull);
      final a = item(ids[0]);
      m.uit.voegToeAanRadio([a]);
      fa.flushMicrotasks();
      expect(m.sonos.opdrachten, ['open ${titel(ids[0])}']);
      expect(m.cast.laatsteStanden.single.radio, 'Radio A');
      expect(identical(m.uit.radioQueue.single, a), isTrue);
      m.cast.dispose();
      fa.flushTimers(flushPeriodicTimers: false);
    });
  });

  test('"volgende" op het laatste nummer: wil verder, en het eerste nieuwe speelt meteen', () {
    fakeAsync((fa) {
      final m = maak(fa);
      unawaited(m.uit.playRadio([item(ids[0])]));
      fa.elapse(const Duration(seconds: 3));
      expect(m.uit.wilVerder, isFalse);
      unawaited(m.cast.control(_move.id, 'next'));
      fa.flushMicrotasks();
      expect(m.uit.wilVerder, isTrue);
      m.uit.voegToeAanRadio([item(ids[3])]);
      fa.flushMicrotasks();
      expect(m.sonos.opdrachten.last, 'open ${titel(ids[3])}');
      expect(m.uit.radioIndex, 1);
      expect(m.uit.wilVerder, isFalse);
      m.cast.dispose();
      fa.flushTimers(flushPeriodicTimers: false);
    });
  });

  test('"hierna" op de speakerzone komt in de rij van de radio; de oude regels blijven dezelfde', () {
    fakeAsync((fa) {
      final m = maak(fa);
      final a = item(ids[0]), b = item(ids[1]);
      unawaited(m.uit.playRadio([a, b]));
      fa.elapse(const Duration(seconds: 2));
      unawaited(m.cast.voegToe(_move.id, [ids[4]], hierna: true));
      fa.flushMicrotasks();
      expect([for (final r in m.uit.radioQueue) r.title], [titel(ids[0]), titel(ids[4]), titel(ids[1])]);
      expect(identical(m.uit.radioQueue[0], a), isTrue);
      expect(identical(m.uit.radioQueue[2], b), isTrue);
      m.cast.dispose();
      fa.flushTimers(flushPeriodicTimers: false);
    });
  });

  test('weghalen: het spelende gaat eerst een verder, en het nummer is uit beide rijen', () {
    fakeAsync((fa) {
      final m = maak(fa);
      final a = item(ids[0]), b = item(ids[1]), c = item(ids[2]);
      unawaited(m.uit.playRadio([a, b, c]));
      fa.elapse(const Duration(seconds: 2));
      bool? weg;
      unawaited(m.uit.haalUitRadio(a.local!.path).then((v) => weg = v));
      fa.flushMicrotasks();
      expect(weg, isTrue);
      expect(m.sonos.opdrachten.last, 'open ${titel(ids[1])}');
      expect([for (final r in m.uit.radioQueue) r.title], [titel(ids[1]), titel(ids[2])]);
      expect(m.cast.rijVan(_move.id)!.rij, [ids[1], ids[2]]);
      m.cast.dispose();
      fa.flushTimers(flushPeriodicTimers: false);
    });
  });

  test('een andere wachtrij op de speaker beëindigt de radio; loslaten zet hem op pauze', () {
    fakeAsync((fa) {
      final m = maak(fa);
      unawaited(m.uit.playRadio([item(ids[0]), item(ids[1])]));
      fa.elapse(const Duration(seconds: 2));
      unawaited(m.cast.play(_move.id, [ids[3]], 0, alsZone: true));
      fa.flushMicrotasks();
      expect(m.einde, ['einde 2']);
      expect(m.uit.playing, isFalse);
      // Een nieuwe radio op dezelfde uitgang, en dan loslaten.
      unawaited(m.uit.playRadio([item(ids[2])]));
      fa.elapse(const Duration(seconds: 2));
      unawaited(m.uit.verlaatRadio());
      fa.flushMicrotasks();
      expect(m.sonos.opdrachten.last, 'pause');
      m.cast.dispose();
      fa.flushTimers(flushPeriodicTimers: false);
    });
  });

  test('de keten: de radio start met de speaker als uitgang; wat later binnenkomt komt in zijn rij; de pc zwijgt', () {
    setAppDirForTest(map.path);
    fakeAsync((fa) {
      final m = maak(fa);
      final pc = _Pc();
      final radio = RadioBesturing(
          speler: pc,
          bron: _Bron((p) => perId[ids[1]]!),
          klok: () => DateTime.fromMicrosecondsSinceEpoch(_t0 + fa.elapsed.inMicroseconds));
      unawaited(radio.start([
        Radioplek(artiest: 'A', titel: titel(ids[0]), eigen: perId[ids[0]], zaad: true),
        // Een andere artiest dan het zaad: anders houdt de afstandsregel van de zaadartiest hem terug tot de rij droog staat.
        Radioplek(artiest: 'B', titel: titel(ids[1])),
      ], naar: m.uit, naam: 'Radio A'));
      fa.flushMicrotasks();
      expect(m.sonos.opdrachten.first, 'open ${titel(ids[0])}');
      expect(m.cast.laatsteStanden.single.radio, 'Radio A');
      // De pc laat zijn radio los (hij speelde er geen: de echte speler doet dan niets) en krijgt geen nummers.
      expect(pc.log, ['verlaat'], reason: 'de pc zwijgt');
      // Het tweede komt binnen en de radio zet het erbij: in de rij van de speaker.
      // Na het landen (3 s) staat het klaar als VOLGENDE, terwijl het eerste nog speelt: zo krijgt de Sonos het
      // mee en gaat hij naadloos over (gemeten in de nabootsing: bij 3 s in de rij, idx 0).
      fa.elapse(const Duration(seconds: 6));
      expect(m.cast.rijVan(_move.id)!.rij, [ids[0], ids[1]]);
      expect(m.cast.rijVan(_move.id)!.index, 0);
      fa.elapse(const Duration(seconds: 20));
      expect(m.sonos.speelt, ids[1], reason: 'naadloos verder');
      expect(m.cast.rijVan(_move.id)!.index, 1);
      expect(m.uit.radioIndex, 1);
      expect(radio.opAndereUitgang, isTrue);
      radio.stop();
      m.cast.dispose();
      fa.flushTimers(flushPeriodicTimers: false);
    });
  });
}

/// Vlak voor het einde van een nummer vraagt de pc een KEF vaker of hij klaar is.
///
/// Saber, 28-11-2026, de Shield in een groep met de KEF LS50: *"In begin van de liedjes verspringt het"*. Gemeten
/// (kef_einde_meten.js): de KEF meldt "stopped" kort na zijn einde, maar de pc vroeg het om de seconde — het volgende
/// nummer begon 0,15–1,15 s na het einde, elke wissel anders. De Shield kon dat niet voorspellen en sprong terug. Nu kijkt
/// de pc de laatste 2,5 s om de 100 ms: het volgende nummer opent telkens binnen ~0,1 s na het einde.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/cast_manager.dart';
import 'package:debridmusic/lan/catalog.dart';
import 'package:debridmusic/lan/kef.dart';
import 'package:debridmusic/lan/upnp.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';

const _t = 1760000000000000; // µs

/// Een KEF zoals gemeten: na de opdracht begint hij na [aanloopUs]; zijn plek (ms) werkt hij eens per ~seconde bij, naar
/// beneden op 48 ms; aan het eind staat hij op "stopped" (hij kent geen volgend nummer).
class _Kef extends KefBediening {
  _Kef(this.nu, this.r);

  final int Function() nu;
  final Random r;
  static const duurUs = 20000000;
  int aanloopUs = 500000;
  int beginUs = 0;
  int? stilUs;
  int? hervatOp;
  String stand = 'stopped';
  String? uri;
  int _bijgewerkt = 0, _volgende = 0, _gemeld = -1;
  final geopend = <int>[];
  final eindes = <int>[];
  /// Hoe vaak de pc vroeg of hij nog speelt (de doorschuiflus; de klok vraagt alleen de plek).
  int vragen = 0;

  int _positie() {
    final t = nu();
    if (hervatOp != null && t >= hervatOp!) {
      beginUs = hervatOp! - stilUs!;
      stilUs = null;
      hervatOp = null;
      _volgende = t;
    }
    if (stilUs != null) return stilUs!;
    final p = t - beginUs;
    if (p >= duurUs && stand == 'playing') {
      stand = 'stopped';
      stilUs = duurUs;
      eindes.add(beginUs + duurUs);
      return duurUs;
    }
    return p;
  }

  int _plekMs() {
    final t = nu();
    final p = _positie();
    if (stand != 'playing') return _gemeld;
    while (t >= _volgende) {
      _bijgewerkt = _volgende;
      _gemeld = ((_bijgewerkt - beginUs) ~/ 48000) * 48;
      _volgende = _bijgewerkt + 1008000 + (r.nextInt(61) - 30) * 1000;
    }
    return p < 0 ? -1 : _gemeld;
  }

  @override
  Future<void> playUrl(Renderer renderer, String url,
      {required String title,
      required String artist,
      required String album,
      required String mime,
      String? artUrl,
      Duration? duration}) async {
    geopend.add(nu());
    uri = url;
    stand = 'playing';
    stilUs = 0;
    hervatOp = nu() + aanloopUs;
    _gemeld = -1;
    _volgende = hervatOp!;
  }

  @override
  Future<int?> getVolume(Renderer r) async => 21;

  @override
  Future<({Duration? position, Duration duration, String? trackUri})?> positionInfo(Renderer r) async {
    await Future<void>.delayed(const Duration(milliseconds: 3));
    final p = _plekMs();
    await Future<void>.delayed(const Duration(milliseconds: 3));
    return (position: p < 0 ? null : Duration(milliseconds: p), duration: const Duration(microseconds: duurUs), trackUri: uri);
  }

  @override
  Future<TransportState?> transportState(Renderer r) async {
    vragen++;
    await Future<void>.delayed(const Duration(milliseconds: 3));
    _positie();
    return TransportState(switch (stand) { 'playing' => 'PLAYING', 'paused' => 'PAUSED_PLAYBACK', _ => 'STOPPED' });
  }
}

final _ls50 = kefRenderer(host: '192.168.0.100', naam: 'LS50 Wireless II-1729d5', model: 'SP4025');

void main() {
  late Directory map;
  late LanCatalog catalog;
  late List<String> ids;

  setUp(() {
    map = Directory.systemTemp.createTempSync('dm_kef_einde_');
    final library = LibraryStore()..rootPath = map.path;
    library.tracks.addAll([
      for (final n in ['Een', 'Twee', 'Drie'])
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
    ids = [for (final t in catalog.snapshot().catalog.tracks) t.id];
  });

  tearDown(() {
    catalog.dispose();
    map.deleteSync(recursive: true);
  });

  /// Hoe lang (ms) na het einde van het eerste nummer de pc het tweede opent, met [aanloopMs] tot de KEF begint (dat
  /// schuift het einde ten opzichte van de tijdklok van de pc, zoals in het echt).
  ({int gat, _Kef kef}) wissel(int aanloopMs, {bool klok = false, int zaad = 1}) {
    late ({int gat, _Kef kef}) uit;
    fakeAsync((fa) {
      int nu() => _t + fa.elapsed.inMicroseconds;
      final kef = _Kef(nu, Random(zaad))..aanloopUs = aanloopMs * 1000;
      final cast = CastManager(
        catalog: catalog,
        token: 't',
        port: 47820,
        upnp: UpnpControlPoint(),
        kef: kef,
        startGrace: Duration.zero,
        klokUs: nu,
        adresVoor: (_) async => '192.168.0.117',
        toeval: Random(zaad),
      )..kenSpeakersVoorToets([_ls50]);
      if (klok) cast.volgKlok(_ls50.id, true);
      unawaited(cast.play(_ls50.id, [ids[0], ids[1], ids[2]], 0, alsZone: true));
      fa.flushMicrotasks();
      // Tot net na het einde van het eerste nummer, dan precies tot het tweede open is.
      fa.elapse(Duration(microseconds: 20000000 + aanloopMs * 1000));
      while (kef.geopend.length < 2 && fa.elapsed < const Duration(seconds: 23)) {
        fa.elapse(const Duration(milliseconds: 10));
      }
      expect(kef.geopend, hasLength(2), reason: 'het tweede nummer is open');
      uit = (gat: (kef.geopend[1] - kef.eindes.first) ~/ 1000, kef: kef);
      // Meteen na het openen: het snelle vragen stopt (één keer per nummer, niet tot de tijd om is).
      fa.elapse(const Duration(milliseconds: 500));
      final open = kef.vragen;
      fa.elapse(const Duration(seconds: 2));
      expect(kef.vragen - open, inInclusiveRange(1, 3), reason: 'na het openen weer om de seconde');
      // Midden in het tweede nummer: om de seconde, niet om de 100 ms.
      fa.elapse(const Duration(seconds: 3));
      final voor = kef.vragen;
      fa.elapse(const Duration(seconds: 5));
      expect(kef.vragen - voor, inInclusiveRange(4, 6), reason: 'midden in een nummer om de seconde');
      cast.dispose();
      fa.flushTimers(flushPeriodicTimers: false);
    });
    return uit;
  }

  test('DE KERN: het volgende nummer opent telkens binnen ~0,1 s na het einde, waar het einde ook valt', () {
    final gaten = [for (var a = 300; a < 1300; a += 70) wissel(a).gat];
    // Om de seconde vragen gaf 0 tot 1000 ms, afhankelijk van waar het einde viel.
    expect(gaten.reduce(max), lessThanOrEqualTo(130), reason: 'gaten $gaten');
    expect(gaten.reduce(min), greaterThanOrEqualTo(0));
  });

  test('ook als iemand meespeelt (dan weet de klok de plek preciezer)', () {
    final gaten = [for (var a = 300; a < 1300; a += 140) wissel(a, klok: true, zaad: 3).gat];
    expect(gaten.reduce(max), lessThanOrEqualTo(130), reason: 'gaten $gaten');
  });

  test('alleen een KEF: een andere speaker wordt niet vaker gevraagd', () {
    final b = File('lib/lan/cast_manager.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(b, contains('    if (!isKef(s.renderer) || s.eindTik != null || s.eindVoor == s.index) return;'));
    // De extra vragen tellen niet mee voor het volume (om de zes gewone tikken).
    expect(b, contains('    if (!tussendoor && ++session.tikken % 6 == 0) unawaited(_haalVolume(session));'));
    expect(b, contains('      if (!tussendoor) _eindInZicht(session, pos?.position, pos?.duration);'));
  });
}

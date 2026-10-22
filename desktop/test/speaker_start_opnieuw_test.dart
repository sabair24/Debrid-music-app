/// Een speaker die een nummer de eerste keer niet aanneemt, krijgt het na een tel nog eens; een start die echt niet
/// lukt, laat geen sessie achter (Saber, 22-10-2026, over de KEF: "bij de eerste keer heeft hij een HTTP fout of
/// zoiets ? … bij de 2de keer pas ging het").
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/cast_manager.dart';
import 'package:debridmusic/lan/catalog.dart';
import 'package:debridmusic/lan/upnp.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';

/// Een speaker die de eerste [weigert] keer een HTTP-fout geeft, zoals de KEF.
class _Weigeraar extends UpnpControlPoint {
  _Weigeraar(this.weigert);
  int weigert;
  final opdrachten = <String>[];

  @override
  Future<List<Renderer>> discover({Duration timeout = const Duration(seconds: 3)}) async => const [];

  @override
  Future<void> playUrl(Renderer renderer, String url,
      {required String title,
      required String artist,
      required String album,
      required String mime,
      String? artUrl,
      Duration? duration}) async {
    if (weigert > 0) {
      weigert--;
      opdrachten.add('geweigerd $title');
      throw const HttpException('KEF weigerde player:player/control (HTTP 500)');
    }
    opdrachten.add('open $title');
  }

  @override
  Future<void> setNextUrl(Renderer renderer, String url,
      {required String title,
      required String artist,
      required String album,
      required String mime,
      String? artUrl,
      Duration? duration}) async {}

  @override
  Future<int?> getVolume(Renderer r) async => 20;

  @override
  Future<({Duration? position, Duration duration, String? trackUri})?> positionInfo(Renderer r) async => null;

  @override
  Future<TransportState?> transportState(Renderer r) async => TransportState('PLAYING');
}

const _speaker = Renderer(
    id: 'uuid:speaker',
    name: 'Speaker',
    host: '192.168.0.30',
    avTransportUrl: 'http://192.168.0.30/av',
    manufacturer: 'Sonos, Inc.',
    udn: 'RINCON_SPEAKER');

void main() {
  late Directory map;
  late LanCatalog catalog;
  late List<String> ids;
  final managers = <CastManager>[];

  setUp(() {
    map = Directory.systemTemp.createTempSync('dm_start_opnieuw_');
    final library = LibraryStore()..rootPath = map.path;
    library.tracks.addAll([
      for (final n in ['Een', 'Twee'])
        Track(
          path: '${map.path}/A/Album/$n.flac',
          title: n,
          artist: 'A',
          album: 'Album',
          trackNo: 1,
          duration: const Duration(seconds: 200),
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
    for (final m in managers) {
      m.dispose();
    }
    managers.clear();
    catalog.dispose();
    map.deleteSync(recursive: true);
  });

  CastManager maak(_Weigeraar speaker) {
    final m = CastManager(
        catalog: catalog,
        token: 't',
        port: 47820,
        upnp: speaker,
        startGrace: Duration.zero,
        adresVoor: (_) async => '192.168.0.10')
      ..kenSpeakersVoorToets([_speaker]);
    managers.add(m);
    return m;
  }

  test('de eerste keer geweigerd: na een tel nog eens, en dan speelt hij', () async {
    final speaker = _Weigeraar(1);
    final cast = maak(speaker);
    final t = Stopwatch()..start();
    await cast.play(_speaker.id, ids, 0, alsZone: true);
    expect(speaker.opdrachten, hasLength(2));
    expect(speaker.opdrachten.first, startsWith('geweigerd '));
    expect(speaker.opdrachten.last, startsWith('open '));
    expect(t.elapsed, greaterThanOrEqualTo(kOpnieuwOpenen));
    expect(cast.rijVan(_speaker.id), isNotNull, reason: 'een gewone sessie');
  });

  test('twee keer geweigerd: een fout voor wie het vroeg, en geen sessie die blijft hangen', () async {
    final speaker = _Weigeraar(2);
    final cast = maak(speaker);
    await expectLater(cast.play(_speaker.id, ids, 0, alsZone: true), throwsA(isA<HttpException>()));
    expect(speaker.opdrachten, hasLength(2), reason: 'één keer opnieuw, niet eindeloos');
    expect(cast.rijVan(_speaker.id), isNull, reason: 'anders staat hij in de zones als bron terwijl hij niets speelt');
    expect(cast.laatsteStanden.where((s) => s.id == _speaker.id), isEmpty);
  });

  test('de pc schrijft de geweigerde overdracht in zones.log', () {
    final server = File('lib/lan/server.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(server, contains(r"_zoneLog.line('overdracht $van → $naar: de speaker nam het niet aan — $e');"));
    final cast = File('lib/lan/cast_manager.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(cast, contains(r"_log?.line('START MISLUKT op ${renderer.name}: $e');"));
  });
}

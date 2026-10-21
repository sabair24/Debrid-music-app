/// De pc stuurt meerdere speakers tegelijk, elk als eigen zone (stap 2.3, Saber 21-10-2026: "Sonos
/// onderling" en "elke Sonos/UPnP-speaker is een zone").
///
/// Wat hier vastligt: twee zones op twee speakers lopen elk hun eigen wachtrij af; de oude speakerkeuze
/// blijft één speaker tegelijk (kies je een andere, dan houdt de vorige op met doorschuiven, zoals altijd);
/// bedienen raakt alleen de speaker die je bedient; en hierna, achteraan en "nu" passen de wachtrij van
/// de speaker aan en geven hem het juiste volgende nummer mee.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/cast_manager.dart';
import 'package:debridmusic/lan/catalog.dart';
import 'package:debridmusic/lan/upnp.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';

/// Een speaker die opschrijft wat hij krijgt, en zegt wat de toets wil.
class _NepUpnp extends UpnpControlPoint {
  final opdrachten = <String>[];
  final stand = <String, String>{}; // renderer-id → PLAYING / STOPPED
  final uri = <String, String?>{};

  String _id(String url) => RegExp(r'/stream/([^/.?]+)').firstMatch(url)?.group(1) ?? url;

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
    opdrachten.add('${renderer.id} open $title');
    stand[renderer.id] = 'PLAYING';
    uri[renderer.id] = url;
  }

  @override
  Future<void> setNextUrl(Renderer renderer, String url,
      {required String title,
      required String artist,
      required String album,
      required String mime,
      String? artUrl,
      Duration? duration}) async {
    opdrachten.add('${renderer.id} volgende $title');
  }

  @override
  Future<void> play(Renderer r) async => opdrachten.add('${r.id} play');
  @override
  Future<void> pause(Renderer r) async => opdrachten.add('${r.id} pause');
  @override
  Future<void> stop(Renderer r) async => opdrachten.add('${r.id} stop');
  @override
  Future<void> setVolume(Renderer r, int volume) async => opdrachten.add('${r.id} volume $volume');
  @override
  Future<int?> getVolume(Renderer r) async => 40;
  @override
  Future<void> seek(Renderer r, Duration to) async => opdrachten.add('${r.id} seek ${to.inSeconds}');

  @override
  Future<({Duration? position, Duration duration, String? trackUri})?> positionInfo(Renderer r) async =>
      (position: const Duration(seconds: 30), duration: const Duration(seconds: 200), trackUri: uri[r.id]);

  @override
  Future<TransportState?> transportState(Renderer r) async => TransportState(stand[r.id] ?? 'STOPPED');

  List<String> van(String id) => [for (final o in opdrachten) if (o.startsWith('$id ')) o.substring(id.length + 1)];
}

const _a = Renderer(id: 'uuid:amp', name: 'Sonos Amp', host: '192.168.0.20', avTransportUrl: 'http://192.168.0.20/av');
const _b = Renderer(id: 'uuid:move', name: 'Sonos Move', host: '192.168.0.21', avTransportUrl: 'http://192.168.0.21/av');

void main() {
  late Directory map;
  late LanCatalog catalog;
  late _NepUpnp upnp;
  late CastManager cast;
  late List<String> ids;
  var meldingen = 0;

  setUp(() {
    map = Directory.systemTemp.createTempSync('dm_cast_zones_');
    final library = LibraryStore()..rootPath = map.path;
    library.tracks.addAll([
      for (final n in ['Een', 'Twee', 'Drie', 'Vier'])
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
    ids.sort((x, y) => catalog.track(x)!.title.compareTo(catalog.track(y)!.title)); // Drie, Een, Twee, Vier
    upnp = _NepUpnp();
    cast = CastManager(catalog: catalog, token: 't', port: 47820, upnp: upnp, startGrace: Duration.zero)
      ..kenSpeakersVoorToets([_a, _b]);
    meldingen = 0;
    cast.bijStand = () => meldingen++;
  });

  tearDown(() {
    cast.dispose();
    catalog.dispose();
    map.deleteSync(recursive: true);
  });

  String titel(String id) => catalog.track(id)!.title;

  test('twee zones op twee speakers lopen elk hun eigen wachtrij af', () async {
    await cast.play(_a.id, [ids[0], ids[1]], 0, alsZone: true);
    await cast.play(_b.id, [ids[2], ids[3]], 0, alsZone: true);
    expect({for (final s in cast.laatsteStanden) s.id: titel(s.trackId!)}, {_a.id: 'Drie', _b.id: 'Twee'});

    // De Amp is klaar met zijn nummer; de Move speelt nog.
    upnp.stand[_a.id] = 'STOPPED';
    await cast.tikVoorToets();
    final na = {for (final s in cast.laatsteStanden) s.id: s};
    expect(titel(na[_a.id]!.trackId!), 'Een', reason: 'de Amp schuift door');
    expect(titel(na[_b.id]!.trackId!), 'Twee', reason: 'de Move speelt gewoon verder');
    expect(na[_a.id]!.volume, 40);

    // Einde van de rij: de sessie van de Amp is klaar, die van de Move niet.
    upnp.stand[_a.id] = 'STOPPED';
    await cast.tikVoorToets();
    expect([for (final s in cast.laatsteStanden) s.id], [_b.id]);
    expect(meldingen, greaterThan(0), reason: 'de zonelijst hoort het');
  });

  test('de oude speakerkeuze blijft één speaker tegelijk; een zone blijft staan', () async {
    await cast.play(_a.id, [ids[0], ids[1]], 0);
    await cast.play(_b.id, [ids[2]], 0);
    expect([for (final s in cast.laatsteStanden) s.id], [_b.id],
        reason: 'een andere speaker gekozen: de vorige schuift niet meer door, zoals altijd');

    await cast.play(_a.id, [ids[0], ids[1]], 0, alsZone: true);
    await cast.play(_b.id, [ids[3]], 0);
    expect({for (final s in cast.laatsteStanden) s.id}, {_a.id, _b.id}, reason: 'de zone op de Amp blijft');
  });

  test('een zone starten laat de gsm die naar een andere speaker cast, gewoon doorgaan', () async {
    await cast.play(_a.id, [ids[0], ids[1]], 0); // de oude speakerkeuze, vanaf een gsm
    await cast.play(_b.id, [ids[2]], 0, alsZone: true);
    expect({for (final s in cast.laatsteStanden) s.id}, {_a.id, _b.id});
  });

  test('bedienen raakt alleen de speaker die je bedient', () async {
    await cast.play(_a.id, [ids[0], ids[1]], 0, alsZone: true);
    await cast.play(_b.id, [ids[2], ids[3]], 0, alsZone: true);
    upnp.opdrachten.clear();
    await cast.control(_b.id, 'next');
    await cast.control(_a.id, 'volume', value: 25);
    expect(upnp.van(_b.id), ['open Vier']);
    expect(upnp.van(_a.id), ['volume 25']);
    final s = {for (final x in cast.laatsteStanden) x.id: x};
    expect(titel(s[_a.id]!.trackId!), 'Drie');
    expect(s[_a.id]!.volume, 25);
  });

  test('hierna, achteraan en nu: de wachtrij van de speaker, met het juiste volgende nummer', () async {
    await cast.play(_a.id, [ids[0], ids[1]], 0, alsZone: true); // Drie, Een
    upnp.opdrachten.clear();
    await cast.voegToe(_a.id, [ids[3]], hierna: true); // Drie, Vier, Een
    expect(upnp.van(_a.id), ['volgende Vier'], reason: 'de speaker krijgt het nieuwe volgende nummer mee');
    expect(cast.laatsteStanden.single.lengte, 3);

    upnp.opdrachten.clear();
    await cast.voegToe(_a.id, [ids[2]], hierna: false); // Drie, Vier, Een, Twee
    expect(upnp.van(_a.id), isEmpty, reason: 'achteraan verandert het volgende nummer niet');

    await cast.voegToe(_a.id, [ids[2]], hierna: true); // al in de rij: verhuist naar hierna
    expect(cast.laatsteStanden.single.lengte, 4);

    upnp.opdrachten.clear();
    await cast.speelNu(_a.id, ids[1]); // Een meteen
    expect(upnp.van(_a.id).first, 'open Een');
    expect(titel(cast.laatsteStanden.single.trackId!), 'Een');

    await expectLater(cast.voegToe(_b.id, [ids[0]], hierna: true), throwsStateError,
        reason: 'een speaker zonder sessie heeft geen wachtrij');
  });

  test('weghalen, verplaatsen en springen in de wachtrij van de speaker (stap 2.4)', () async {
    await cast.play(_a.id, [ids[0], ids[1], ids[2], ids[3]], 0, alsZone: true); // Drie, Een, Twee, Vier
    expect([for (final i in cast.rijVan(_a.id)!.rij) titel(i)], ['Drie', 'Een', 'Twee', 'Vier']);

    upnp.opdrachten.clear();
    await cast.haalUit(_a.id, 1, trackId: ids[1]); // Een eruit: Drie, Twee, Vier
    expect([for (final i in cast.rijVan(_a.id)!.rij) titel(i)], ['Drie', 'Twee', 'Vier']);
    expect(upnp.van(_a.id), ['volgende Twee'], reason: 'het volgende nummer was weg: het nieuwe meegeven');

    await cast.verplaats(_a.id, 2, 1, trackId: ids[3]); // Vier naar voren: Drie, Vier, Twee
    expect([for (final i in cast.rijVan(_a.id)!.rij) titel(i)], ['Drie', 'Vier', 'Twee']);

    // Met een plek die intussen niet meer klopt: het nummer zelf telt.
    upnp.opdrachten.clear();
    await cast.springNaar(_a.id, 1, trackId: ids[2]);
    expect(upnp.van(_a.id).first, 'open Twee');
    expect(cast.rijVan(_a.id)!.index, 2);
    await expectLater(cast.haalUit(_a.id, 2, trackId: ids[2]), throwsStateError, reason: 'het spelende nummer niet');
  });
}

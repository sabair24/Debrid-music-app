// Kwaliteit op de gsm toont de pc (Saber, 18-10-2026). Op de gsm liep een eigen, lege verlanglijst:
// de strook van de vervangjacht verscheen er nooit, "Laat de app zoeken" zette wensen op een lijst
// waar niemand naar zocht, en omdat je eigen keuzes op de pc staan, telde de gsm andere getallen.
//
// Over een echte socket tegen een echte LanServer, zoals remote_work_test.dart: het gaat om de lijn.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/dtos.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/remote_services.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/vaste_naam.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/organize.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:debridmusic/vaste_keuze.dart';
import 'package:debridmusic/vervangjacht.dart';

/// De downloader van de pc: onthoudt wat er gewenst werd, en kent een vaste jachtstand.
class _NepDownloads extends DownloadManager {
  _NepDownloads(super.online, super.soulseek, super.musicRoot, super.onLibraryChanged);

  final List<Track> gewenst = [];

  @override
  Future<void> ververJachtStand() async {}

  @override
  Future<int> wensEchteVersies(Iterable<Track> nummers, {TrackTags Function(Track)? gezag}) async {
    gewenst.addAll(nummers);
    return nummers.length;
  }
}

void main() {
  late Directory map;
  late LibraryStore library;
  late _NepDownloads downloads;
  late LanServer server;
  late RemoteEndpoint endpoint;
  late Map<String, String> ids;

  setUp(() async {
    map = Directory.systemTemp.createTempSync('dm_kwal_');
    setAppDirForTest(map.path);
    final settings = AppSettings();
    library = LibraryStore()
      ..rootPath = map.path
      ..configDirOverride = map.path;
    for (final titel in ['Anja', 'Bad']) {
      final f = File('${map.path}/$titel.flac')..writeAsBytesSync(List.filled(64, 1));
      library.tracks.add(Track(
          path: f.path, title: titel, artist: 'Gorki', album: 'Gorki', isFlac: true, sizeBytes: 64));
    }
    library.rebuildAlbums();
    // Op de pc zelf gekozen, vóór de catalogus gebouwd wordt.
    await onthoudVasteKeuze(library.tracks.last.path);
    final online = OnlineService(settings);
    final soulseek = SoulseekService(settings);
    downloads = _NepDownloads(online, soulseek, map.path, () async {});
    server = LanServer(
      library: library,
      token: 'sleutel',
      state: LanStateStore(File('${map.path}/state.json')),
      pairing: PairingStore(),
      port: 0,
      online: online,
      soulseek: soulseek,
      downloads: downloads,
    );
    expect(await server.start(), isNull);
    endpoint = RemoteEndpoint(baseUrl: Uri.parse('http://127.0.0.1:${server.boundPort}'), token: 'sleutel');
    ids = {
      for (final t in server.catalog.snapshot().catalog.tracks) t.title: t.streamPath,
    };
  });

  tearDown(() async {
    await server.dispose();
    await vergeetVasteKeuze(library.tracks.last.path);
    map.deleteSync(recursive: true);
  });

  RemoteDownloadManager gsm() => RemoteDownloadManager(
      OnlineService(AppSettings()), SoulseekService(AppSettings()), map.path, () async {}, () => endpoint);

  /// Een nummer zoals de gsm het kent: de vaste naam van zijn stream, niet het bestand op de pc.
  Track opGsm(String titel) =>
      Track(path: vastePcNaam(ids[titel]!), title: titel, artist: 'Gorki', album: 'Gorki', isFlac: true);

  test('de strook op de gsm is de jacht van de pc', () async {
    downloads.jacht.value = VervangJacht(
      opDeLijst: 7,
      dezeBeurt: 3,
      gedaan: 1,
      bezigMet: 'Gorki — Anja',
      regel: 'Drie peers zeiden nee',
      binnen: 2,
      volgendeOm: DateTime.fromMillisecondsSinceEpoch(1800000000000),
    );
    final dm = gsm();
    expect(dm.jacht.value.opDeLijst, 0, reason: 'vóór de vraag weet de gsm niets');
    await dm.ververJachtStand();
    final j = dm.jacht.value;
    expect(j.opDeLijst, 7);
    expect(j.loopt, isTrue);
    expect(j.bezigMet, 'Gorki — Anja');
    expect(j.regel, 'Drie peers zeiden nee');
    expect(j.binnen, 2);
    expect(j.volgendeOm, DateTime.fromMillisecondsSinceEpoch(1800000000000));
  });

  test('"Laat de app zoeken" op de gsm zet de wens op de verlanglijst van de pc', () async {
    final nieuw = await gsm().wensEchteVersies([opGsm('Anja')]);
    expect(nieuw, 1);
    expect(downloads.gewenst.map((t) => t.path), [library.tracks.first.path],
        reason: 'de pc hoort zijn eigen bestand te wensen, niet de stream-naam van de gsm');
  });

  test('"Ook wat je zelf koos" geeft de keuze op de pc vrij', () async {
    final bad = library.tracks.last.path;
    expect(isVasteKeuze(bad), isTrue);
    final u = await gsm().wensOpPc([opGsm('Bad')], vrijgeven: true);
    expect(u.vrij, 1);
    expect(u.nieuw, 1);
    expect(isVasteKeuze(bad), isFalse);
  });

  test('de catalogus zegt welke nummers je zelf koos, en de gsm onthoudt dat zonder schijf', () async {
    final dto = server.catalog.snapshot().catalog.tracks.firstWhere((t) => t.title == 'Bad');
    expect(dto.vast, isTrue);
    expect(TrackDto.fromJson(dto.toJson()).vast, isTrue);
    expect(server.catalog.snapshot().catalog.tracks.firstWhere((t) => t.title == 'Anja').toJson(),
        isNot(contains('vast')), reason: 'niets meesturen als er niets te melden valt');

    final pad = vastePcNaam(ids['Anja']!);
    expect(isVasteKeuze(pad), isFalse);
    zetVasteKeuzeVanPc(pad, true);
    expect(isVasteKeuze(pad), isTrue);
    final schijf = File('${map.path}${Platform.pathSeparator}vaste_keuzes.json');
    expect(schijf.existsSync() ? schijf.readAsStringSync() : '', isNot(contains('stream')),
        reason: 'de pc is de eigenaar; een kopie op de gsm veroudert stil');
    zetVasteKeuzeVanPc(pad, false);
    expect(isVasteKeuze(pad), isFalse);
  });

  test('VervangJacht heen en terug', () {
    const leeg = VervangJacht(opDeLijst: 0);
    final terug = VervangJacht.fromJson(leeg.toJson());
    expect(terug.opDeLijst, 0);
    expect(terug.volgendeOm, isNull);
    expect(terug.loopt, isFalse);
  });

  test('de pagina: meten en terugzetten alleen op de pc, de rest via de pc', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(main, contains('    final opPc = !lib.isRemote;'));
    expect(main, contains('            else if (opPc)\n              TextButton.icon(\n                onPressed: _meet,'));
    expect(main, contains('            else if (!_bezig && opPc)'));
    expect(main, contains('final u = await dm.wensOpPc(rijen.map((r) => r.track), vrijgeven: true);'));
    expect(main, contains('if (dm is RemoteDownloadManager) unawaited(dm.ververJachtStand());'));
  });
}

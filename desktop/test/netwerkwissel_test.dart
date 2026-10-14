/// Een netwerkwissel van het toestel laat de app meteen opnieuw kiezen, met een verse verbinding.
/// Stap 4.2 van "verbinden zoals Roon ARC" (14-10-2026); zie `lib/netwerkwissel.dart`.
library;

import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/client_session.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/netwerkwissel.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

const _wifi = NetwerkGebeurtenis(soort: 'standaard-beschikbaar', transport: 'wifi', gevalideerd: true);
const _weg = NetwerkGebeurtenis(soort: 'standaard-weg', transport: 'onbekend');
const _mobiel = NetwerkGebeurtenis(soort: 'standaard-beschikbaar', transport: 'mobiel', gevalideerd: true);

void main() {
  group('NetwerkGebeurtenis', () {
    test('wat het kanaal stuurt', () {
      final g = NetwerkGebeurtenis.uit(
          {'soort': 'fysiek-weg', 'netwerk': '101', 'transport': 'wifi', 'gevalideerd': false});
      expect(g?.soort, 'fysiek-weg');
      expect(g?.toString(), 'fysiek-weg wifi (nog niet gevalideerd) [101]');
      expect(NetwerkGebeurtenis.uit('rommel'), isNull);
      expect(NetwerkGebeurtenis.uit({'soort': ''}), isNull);
    });
  });

  group('Netwerkwacht', () {
    test('de beginstand telt niet, een reeks is één wissel, en alles komt in het logboek', () {
      fakeAsync((t) {
        final bron = StreamController<NetwerkGebeurtenis>();
        final wissels = <String>[];
        final log = <String>[];
        Netwerkwacht(bron: bron.stream, log: log.add, bijWissel: (w) async => wissels.add(w)).start();

        bron.add(_wifi); // bij het aanmelden: het netwerk dat er al is
        t.elapse(const Duration(seconds: 1));
        expect(wissels, isEmpty, reason: 'de beginstand is geen wissel');

        // De voordeur: wifi weg, mobiel erbij, vlak na elkaar.
        bron.add(_weg);
        t.elapse(const Duration(milliseconds: 100));
        bron.add(_mobiel);
        t.elapse(const Duration(milliseconds: 499));
        expect(wissels, isEmpty, reason: 'nog geen halve seconde rust');
        t.elapse(const Duration(milliseconds: 2));
        expect(wissels, [_mobiel.toString()], reason: 'één keuze, op het laatste netwerk');
        expect(log.where((r) => r.startsWith('netwerk: standaard')), hasLength(3));
        expect(log, contains('netwerk: beginstand (${_wifi.toString()})'));
      });
    });

    test('een wissel tijdens een keuze gaat niet verloren', () {
      fakeAsync((t) {
        final bron = StreamController<NetwerkGebeurtenis>();
        final wissels = <String>[];
        Completer<void>? bezig;
        Netwerkwacht(
          bron: bron.stream,
          bijWissel: (w) {
            wissels.add(w);
            bezig = Completer<void>();
            return bezig!.future;
          },
        ).start();
        bron.add(_wifi);
        t.elapse(const Duration(seconds: 1));
        bron.add(_mobiel);
        t.elapse(const Duration(seconds: 1));
        expect(wissels, hasLength(1));
        // Terwijl die keuze loopt, komt het wifi terug.
        bron.add(_wifi);
        t.elapse(const Duration(seconds: 1));
        expect(wissels, hasLength(1), reason: 'niet twee keuzes tegelijk');
        bezig!.complete();
        t.flushMicrotasks();
        expect(wissels, hasLength(2), reason: 'na afloop nog één, op het nieuwe netwerk');
        expect(wissels.last, _wifi.toString());
        bezig!.complete();
      });
    });
  });

  group('aan de sessie', () {
    late Directory scratch, pcRoot;
    late LanServer server;
    late Uri adres;

    setUp(() async {
      scratch = Directory.systemTemp.createTempSync('dm_netwissel_');
      setAppDirForTest(scratch.path);
      pcRoot = Directory.systemTemp.createTempSync('dm_netwissel_pc_');
      final map = Directory('${pcRoot.path}/Portishead/Dummy')..createSync(recursive: true);
      final f = File('${map.path}/01.flac')..writeAsBytesSync(List<int>.filled(1024, 0));
      final lib = LibraryStore()..tracks.add(Track(path: f.path, title: 'Mysterons', artist: 'Portishead', album: 'Dummy'));
      lib.albums = [Album('Dummy', 'Portishead', lib.tracks.toList())];
      server = LanServer(
        library: lib,
        token: 'sleutel',
        state: LanStateStore(File('${pcRoot.path}/state.json')),
        pairing: PairingStore(),
        port: 0,
        settings: AppSettings()..serverId = 'pc-saber-0001',
      );
      expect(await server.start(), isNull);
      adres = Uri.parse('http://127.0.0.1:${server.boundPort}');
    });

    tearDown(() async {
      await server.dispose();
      for (final m in [pcRoot, scratch]) {
        try {
          m.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('na een wissel een verse verbinding, ook als het adres hetzelfde blijft', () async {
      final lib = LibraryStore();
      final s = ClientSession(
          library: lib, settings: AppSettings(), owner: false, applyMediaResolver: (_) {}, zoekOpNetwerk: () async => const []);
      addTearDown(s.dispose);
      await s.connect(RemoteEndpoint(baseUrl: adres, token: 'sleutel', serverId: 'pc-saber-0001'));
      final oud = lib.remote;
      expect(oud, isNotNull);

      await s.netwerkVeranderd('test: wifi weg, mobiel erbij');

      expect(s.endpoint?.baseUrl, adres);
      expect(identical(lib.remote, oud), isFalse,
          reason: 'de open verbindingen van het verdwenen netwerk hielden alles dertig seconden vast');
      expect(lib.tracks, isNotEmpty);
      final log = File('${scratch.path}${Platform.pathSeparator}verbinding.log').readAsStringSync();
      expect(log, contains('netwerk gewisseld (test: wifi weg, mobiel erbij)'));
      expect(log, contains('met een verse verbinding'));
    });
  });

  group('waar het aan het toestel vastzit', () {
    String lees(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

    test('Android: één keer per proces, met de applicatiecontext, en alleen echte wissels', () {
      final kt = lees('android/app/src/main/kotlin/com/debridmusic/app/MainActivity.kt');
      expect(kt, contains('EventChannel(flutterEngine.dartExecutor.binaryMessenger, "debridmusic/netwerk")'));
      expect(kt, contains('if (netwerkGeregistreerd) return'));
      expect(kt, contains('context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE)'));
      expect(kt, contains('registerDefaultNetworkCallback'));
      expect(kt, contains('if (laatste[sleutel] == stand) return'),
          reason: 'anders wordt elke verandering in signaalsterkte een nieuwe keuze');
    });

    test('iOS en macOS: dezelfde naam, dezelfde wacht', () {
      for (final p in ['ios/Runner/AppDelegate.swift', 'macos/Runner/MainFlutterWindow.swift']) {
        final swift = lees(p);
        expect(swift, contains('name: "debridmusic/netwerk"'), reason: p);
        expect(swift, contains('NWPathMonitor()'), reason: p);
        expect(swift, contains('if stand == zelf.laatste { return }'), reason: p);
      }
    });

    test('Dart luistert op die naam, en de wacht hangt aan de sessie', () {
      expect(lees('lib/netwerkwissel.dart'), contains("EventChannel('debridmusic/netwerk')"));
      final hoofd = lees('lib/main.dart');
      expect(hoofd, contains('bron: netwerkGebeurtenissen(),'));
      expect(hoofd, contains('await session.netwerkVeranderd(waarom);'));
    });
  });
}

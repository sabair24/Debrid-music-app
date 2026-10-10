/// Dat de metingen van een toestel in `warmte.log` op de pc belanden. Zie `warmtemeter_test.dart`
/// voor de meetlat zelf.
///
/// **Een eigen bestand, en dat is geen netheid.** In een bestand met widgettoetsen zet Flutter een
/// nep-HttpClient neer die op álles 400 antwoordt — dan "slaagt" een toets die een weigering
/// verwacht ook als de server nooit gesproken heeft. Hier praat RemoteClient met een echte LanServer.
library;

import 'dart:io';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/tokens.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DE KERN: de regels komen in warmte.log op de pc', () {
    late Directory krab;
    late LanServer server;
    const token = 'toets-token';
    setUp(() async {
      krab = Directory.systemTemp.createTempSync('dm_warmte_');
      setAppDirForTest(krab.path);
      final library = LibraryStore()
        ..rootPath = krab.path
        ..configDirOverride = krab.path;
      server = LanServer(
        library: library,
        token: token,
        settings: AppSettings(),
        state: LanStateStore(File('${krab.path}/state.json')),
        pairing: PairingStore(),
        port: 0,
        grants: GrantStore(file: File('${krab.path}/grants.json')),
      );
      expect(await server.start(), isNull);
    });
    tearDown(() async {
      await server.dispose();
      try {
        krab.deleteSync(recursive: true);
      } catch (_) {}
    });

    RemoteClient client(String sleutel) => RemoteClient(RemoteEndpoint(
        baseUrl: Uri.parse('http://127.0.0.1:${server.boundPort}'), token: sleutel));

    test('via dezelfde weg als de app: RemoteClient.ask', () async {
      final c = client(token);
      final j = await c.ask('/api/diag/warmte', {
        'toestel': 'iPad van Saber (ios, 2732×2048 px, 120 Hz)',
        'regels': ['120.0 beelden/s | animaties: cd (LangzameDraai)', 'tweede\nregel'],
      });
      c.close();
      expect(j['regels'], 2);
      final log = File('${krab.path}/warmte.log').readAsStringSync();
      expect(log.contains('[iPad van Saber (ios, 2732×2048 px, 120 Hz) 127.0.0.1] 120.0 beelden/s'),
          isTrue, reason: log);
      expect(log.contains('tweede regel'), isTrue, reason: 'een regeleinde breekt het logboek niet');
    });

    test('hoogstens 60 regels per keer', () async {
      final c = client(token);
      final j = await c.ask('/api/diag/warmte', {
        'toestel': 'x',
        'regels': [for (var i = 0; i < 75; i++) 'regel $i'],
      });
      c.close();
      expect(j['regels'], 60);
    });

    test('zonder geldige sleutel komt er niets in', () async {
      final c = client('fout');
      await expectLater(
        c.ask('/api/diag/warmte', {'regels': ['x']}),
        throwsA(isA<RemoteException>().having((e) => e.statusCode, 'status', 401)),
      );
      c.close();
      expect(File('${krab.path}/warmte.log').existsSync(), isFalse);
    });
  });

  test('de app sluit de meetlat aan op een toestel dat met een pc praat', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains("await c.ask('/api/diag/warmte'"), isTrue);
    expect(main.contains('if (!mode.owner) {\n    final ik = thisDevice();\n    Warmtemeter('), isTrue,
        reason: 'alleen op een toestel dat met een pc praat');
    final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(swift.contains('"debridmusic/warmte"'), isTrue);
    expect(swift.contains('ProcessInfo.processInfo.thermalState.rawValue'), isTrue);
  });
}

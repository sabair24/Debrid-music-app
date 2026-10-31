/// De Shield vindbaar terwijl hij slaapt, en wekken als er muziek naartoe gaat (Saber, 31-10-2026: "zoals sonos kan
/// dit, en dan wekt hij de shield als ik er naar wil streamen").
///
/// Het wekken zelf gebeurt op Android (Ontvanger.kt) en is pas op de Shield na te gaan. Hier: de regel eromheen (wel of
/// niet wekken, en wachten tot hij wakker is), welke zone-opdrachten wekken, en dat alles aangesloten is.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart' show Rijbediening, Speelbron;
import 'package:debridmusic/wekker.dart';
import 'package:debridmusic/zone_opdracht.dart';

String _bron(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('wekVoorMuziek', () {
    test('wakker: niet wekken en niet wachten', () async {
      var gewekt = 0;
      final klok = Stopwatch()..start();
      final sliep = await wekVoorMuziek(
        slaapt: () async => false,
        wek: () async => gewekt++,
        rust: const Duration(seconds: 5),
      );
      expect(sliep, isFalse);
      expect(gewekt, 0);
      expect(klok.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('slaapt: één keer wekken, wachten tot hij wakker is, en dan nog even voor de tv', () async {
      var gewekt = 0;
      var vragen = 0;
      final regels = <String>[];
      final klok = Stopwatch()..start();
      final sliep = await wekVoorMuziek(
        // Wakker vanaf de vierde vraag na het wekken.
        slaapt: () async => gewekt == 0 || ++vragen < 4,
        wek: () async => gewekt++,
        stap: const Duration(milliseconds: 5),
        rust: const Duration(milliseconds: 300),
        log: regels.add,
      );
      expect(sliep, isTrue);
      expect(gewekt, 1);
      expect(klok.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 300)),
          reason: 'de tv krijgt zijn tijd voor de muziek begint');
      expect(regels.single, startsWith('gewekt in '));
    });

    test('wordt niet wakker: na het geduld toch verder, zonder de extra rust', () async {
      final regels = <String>[];
      final klok = Stopwatch()..start();
      final sliep = await wekVoorMuziek(
        slaapt: () async => true,
        wek: () async => null,
        geduld: const Duration(milliseconds: 80),
        stap: const Duration(milliseconds: 5),
        rust: const Duration(seconds: 5),
        log: regels.add,
      );
      expect(sliep, isTrue);
      expect(klok.elapsed, lessThan(const Duration(seconds: 3)), reason: 'de muziek moet toch beginnen');
      expect(regels.single, startsWith('NIET wakker'));
    });
  });

  test('alleen opdrachten die muziek laten beginnen, wekken', () {
    for (final c in ['play', 'speel', 'nu', 'radio', 'neemOver', 'jump', 'tussendoor']) {
      expect(wektToestel(c), isTrue, reason: c);
    }
    for (final c in ['pause', 'stop', 'volume', 'hierna', 'achteraan', 'samen', 'meet', 'seek', 'remove']) {
      expect(wektToestel(c), isFalse, reason: c);
    }
  });

  group('een zone-opdracht naar een slapende Shield', () {
    final een = Track(path: 'een.flac', title: 'Een', artist: 'A', album: 'X', isFlac: true);

    ZoneUitvoerder uitvoerder(List<String> gedaan, {Future<void> Function()? wek}) => ZoneUitvoerder(
          speler: _GeenSpeler(),
          rij: _Rij(gedaan),
          nummer: (id) => id == 'een' ? een : null,
          wek: wek ?? () async => gedaan.add('wek'),
        );

    test('"speel": eerst wekken, dan pas de muziek', () async {
      final gedaan = <String>[];
      expect(await uitvoerder(gedaan).voerUit({'cmd': 'speel', 'ids': ['een'], 'plek': 0}), isNull);
      expect(gedaan, ['wek', 'speel Een']);
    });

    test('pauze, volume en hierna wekken niemand', () async {
      final gedaan = <String>[];
      final u = uitvoerder(gedaan);
      await u.voerUit({'cmd': 'pause'});
      await u.voerUit({'cmd': 'volume', 'waarde': 40});
      await u.voerUit({'cmd': 'hierna', 'ids': ['een']});
      expect(gedaan, ['hierna Een']);
    });

    test('wekken mislukt: de muziek begint toch', () async {
      final gedaan = <String>[];
      final u = uitvoerder(gedaan, wek: () async => throw StateError('geen scherm'));
      expect(await u.voerUit({'cmd': 'speel', 'ids': ['een'], 'plek': 0}), isNull);
      expect(gedaan, ['speel Een']);
    });
  });

  group('aangesloten', () {
    test('Android: een voorgronddienst die luistert, ook na een herstart of update, alleen op een tv', () {
      final manifest = _bron('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('android:name=".OntvangerDienst"\n            android:foregroundServiceType="connectedDevice"'));
      expect(manifest, contains('<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE"/>'));
      expect(manifest, contains('<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>'));
      expect(manifest, contains('<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>'));
      expect(manifest, contains('android:name=".OntvangerStart"'));
      expect(manifest, contains('<action android:name="android.intent.action.BOOT_COMPLETED"/>'));
      expect(manifest, contains('<action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>'));

      final kt = _bron('android/app/src/main/kotlin/com/debridmusic/app/Ontvanger.kt');
      expect(kt, contains('startForeground(MELDING, melding, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)'));
      expect(kt, contains('override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY'));
      expect(kt, contains('            if (!isTv(context)) return\n'));
      expect(kt, contains('Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> OntvangerDienst.start(context)'));
      // Zonder scherm de engine zelf, en dan moet "isTv" ook zonder MainActivity antwoorden (lib/tv.dart).
      expect(kt, contains('val engine = AudioServicePlugin.getFlutterEngine(applicationContext)'));
      expect(kt, contains('if (nieuw) registreerToestelZonderScherm(applicationContext, boodschapper)'));
      expect(kt, contains('"isTv" -> result.success(OntvangerDienst.isTv(app))'));
      expect(kt, contains('hoofd.postDelayed({ if (draait) zorgVoorEngine() }, 3000)'));
      // Wekken: het scherm, en de app vooraan via de startopdracht (geen tweede venster).
      expect(kt, contains('PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP'));
      expect(kt, contains('pkg.getLeanbackLaunchIntentForPackage(context.packageName)'));
      expect(kt, contains('MethodChannel(boodschapper, "debridmusic/wekker")'));

      final activiteit = _bron('android/app/src/main/kotlin/com/debridmusic/app/MainActivity.kt');
      expect(activiteit, contains('        registreerWekker(applicationContext, flutterEngine.dartExecutor.binaryMessenger)\n'
          '        OntvangerDienst.start(applicationContext)\n'));
    });

    test('Dart: dezelfde kanaalnaam, en de ontvanger, de zone en de lijn wekken of blijven open', () {
      expect(_bron('lib/wekker.dart'), contains("const _kanaal = MethodChannel('debridmusic/wekker');"));
      final hoofd = _bron('lib/main.dart');
      expect(hoofd, contains('      slaapt: toestelSlaapt,\n      wek: wekVoorDeMuziek,\n'));
      expect(hoofd, contains('    wek: isTv ? wekVoorDeMuziek : null,\n'));
      expect(hoofd, contains('if (voor || isTv || player.playing || gekozenZone.opAfstand != null) {'));
      expect(hoofd, contains(
          '    session.rust = () => !player.playing && WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;\n'));
      expect(hoofd, contains('        await session.refreshNow().timeout(const Duration(seconds: 5));\n'));
      expect(_bron('lib/lan/client_session.dart'), contains('      if (rust?.call() ?? false) return;\n      _refresh();\n'));
    });
  });
}

class _GeenSpeler implements Speelbron {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _Rij implements Rijbediening {
  _Rij(this.gedaan);
  final List<String> gedaan;

  @override
  Future<void> playQueue(List<Track> queue, int index, {cover}) async =>
      gedaan.add('speel ${queue.map((t) => t.title).join(',')}');

  @override
  Future<void> shuffleAll(List<Track> tracks) async => gedaan.add('schud');

  @override
  void speelHierna(List<Track> nummers) => gedaan.add('hierna ${nummers.map((t) => t.title).join(',')}');

  @override
  void zetAchteraan(List<Track> nummers) => gedaan.add('achteraan');

  @override
  Future<void> speelNuMetRest(Track t) async => gedaan.add('nu ${t.title}');
}

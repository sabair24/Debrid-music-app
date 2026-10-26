// Tussendoor beluisteren uit "Klaar om te kiezen" (Saber, 26-10-2026: "als ik op beluisteren knop klik … mag het wel
// niet men wachtrij weggooien, ik wil kunnen beluisteren men actuele liedje stopt dan even om te beluisteren, dan klik
// ik op gebruiken of weg, en dan moet men liedje hervatten en men wachtrij moet er nog staan. Plus als de muziek speelt
// op de gsm, moet het op de gsm gebeuren en als ik luister op de kef op de kef … op de zone die actief is").
import 'dart:io';

import 'package:debridmusic/lan/cast_manager.dart';
import 'package:debridmusic/lan/catalog.dart';
import 'package:debridmusic/lan/upnp.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart' show TussendoorStand;
import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/zone_opdracht.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een speaker die opschrijft wat hij moet doen, en een vaste plek meldt.
class _Speaker extends UpnpControlPoint {
  final opdrachten = <String>[];
  Duration plek = const Duration(seconds: 95);

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
  Future<void> seek(Renderer r, Duration to) async => opdrachten.add('spoel ${to.inSeconds}');

  @override
  Future<void> pause(Renderer r) async => opdrachten.add('pauze');

  @override
  Future<int?> getVolume(Renderer r) async => 20;

  @override
  Future<({Duration? position, Duration duration, String? trackUri})?> positionInfo(Renderer r) async =>
      (position: plek, duration: const Duration(seconds: 200), trackUri: null);

  @override
  Future<TransportState?> transportState(Renderer r) async => TransportState('PLAYING');
}

const _kef = Renderer(
    id: 'uuid:kef', name: 'KEF', host: '192.168.0.100', avTransportUrl: 'http://192.168.0.100/av', manufacturer: 'KEF');

void main() {
  group('op een speaker (de pc stuurt hem)', () {
    late Directory map;
    late LanCatalog catalog;
    late List<String> ids;
    late CastManager cast;
    late _Speaker kef;

    setUp(() {
      map = Directory.systemTemp.createTempSync('dm_tussendoor_');
      final library = LibraryStore()..rootPath = map.path;
      library.tracks.addAll([
        for (final n in ['Een', 'Twee', 'Drie'])
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
              bitsPerSample: 16),
      ]);
      library.rebuildAlbums();
      catalog = LanCatalog(library)
        ..extraTrack = (id) => id == '${kKandidaatId}x'
            ? Track(path: '${map.path}/_twijfel/Een.flac', title: 'Een', artist: 'A', album: 'Album', isFlac: true)
            : null;
      ids = [for (final t in catalog.snapshot().catalog.tracks) t.id];
      kef = _Speaker();
      cast = CastManager(
          catalog: catalog,
          token: 't',
          port: 47820,
          upnp: kef,
          startGrace: Duration.zero,
          spoelNa: const Duration(milliseconds: 10),
          adresVoor: (_) async => '192.168.0.10')
        ..kenSpeakersVoorToets([_kef]);
    });

    tearDown(() {
      cast.dispose();
      catalog.dispose();
      map.deleteSync(recursive: true);
    });

    test('DE KERN: de kopie klinkt, de rij blijft bewaard, en daarna terug op het nummer en de seconde', () async {
      await cast.play(_kef.id, ids, 1, alsZone: true);
      kef.opdrachten.clear();
      // Wat de speaker meldt: hij is op 1:35 van nummer twee.
      await cast.status(_kef.id);
      await cast.tussendoor(_kef.id, a: ids[1], b: '${kKandidaatId}x');
      expect(kef.opdrachten.last, 'open Een', reason: 'de kopie (B) speelt');
      expect(cast.rijVan(_kef.id)?.rij, ids, reason: 'de rij die terugkomt, niet de kopie');
      expect(cast.rijVan(_kef.id)?.index, 1);
      expect(cast.tussendoorVan(_kef.id)?.opB, isTrue);
      // A/B: het nummer zelf, op dezelfde seconde.
      await cast.tussendoorAB(_kef.id);
      expect(cast.tussendoorVan(_kef.id)?.opB, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(kef.opdrachten, containsAllInOrder(['open Twee', 'spoel 95']));
      kef.opdrachten.clear();
      await cast.tussendoorKlaar(_kef.id);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(kef.opdrachten, ['open Twee', 'spoel 95'], reason: 'terug op nummer twee, op 1:35');
      expect(cast.tussendoorVan(_kef.id), isNull);
      expect(cast.rijVan(_kef.id)?.rij, ids);
    });

    test('wat de radio intussen aanvult, komt in de bewaarde rij; op pauze blijft hij op pauze', () async {
      await cast.play(_kef.id, ids.take(2).toList(), 0, alsZone: true);
      await cast.status(_kef.id);
      await cast.tussendoor(_kef.id, a: ids[0], b: '${kKandidaatId}x');
      await cast.voegToe(_kef.id, [ids[2]], hierna: false);
      expect(cast.rijVan(_kef.id)?.rij, ids, reason: 'de radio hoort niets van de kopie');
      kef.opdrachten.clear();
      await cast.tussendoorKlaar(_kef.id, hervat: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(kef.opdrachten, containsAll(['open Een', 'pauze']));
    });

    test('volgende tijdens het beluisteren: de rij is weer de rij', () async {
      await cast.play(_kef.id, ids, 0, alsZone: true);
      await cast.tussendoor(_kef.id, a: ids[0], b: '${kKandidaatId}x');
      kef.opdrachten.clear();
      await cast.control(_kef.id, 'next');
      expect(cast.tussendoorVan(_kef.id), isNull);
      expect(kef.opdrachten.last, 'open Twee');
    });
  });

  group('op een toestel (een zone-opdracht)', () {
    final een = Track(path: '/m/Een.flac', title: 'Een', artist: 'A', album: 'Album');

    test('tussendoor, A/B en klaar gaan naar de speler van dat toestel', () async {
      final gedaan = <String>[];
      final u = ZoneUitvoerder(
        speler: _GeenSpeler(),
        rij: _GeenRij(),
        nummer: (id) => id == 'een' ? een : null,
        tussendoor: (t) async {
          gedaan.add('tussendoor ${t.title}');
          return null;
        },
        tussendoorAB: () async => gedaan.add('ab'),
        tussendoorKlaar: ({required bool hervat}) async => gedaan.add('klaar $hervat'),
      );
      expect(await u.voerUit({'cmd': 'tussendoor', 'trackId': 'een'}), isNull);
      expect(await u.voerUit({'cmd': 'tussendoorAB'}), isNull);
      expect(await u.voerUit({'cmd': 'tussendoorKlaar', 'hervat': false}), isNull);
      expect(gedaan, ['tussendoor Een', 'ab', 'klaar false']);
      expect(await u.voerUit({'cmd': 'tussendoor', 'trackId': 'onbekend'}), contains('niet in de bibliotheek'));
    });
  });

  group('wat het scherm bijhoudt', () {
    tearDown(() => TussendoorStand.nu.stop());

    test('stoppen ruimt op', () async {
      TussendoorStand.nu.zetVoorToets('/m/Een.flac', zone: 'spk:kef', waar: 'KEF');
      expect(TussendoorStand.nu.bezig, isTrue);
      expect(await TussendoorStand.nu.stop(), isFalse);
      expect(TussendoorStand.nu.bezig, isFalse);
      expect(await TussendoorStand.nu.wissel(), isFalse, reason: 'niets om te wisselen');
    });
  });

  test('aangesloten: beluisteren gooit de wachtrij niet meer weg; de zone en de speaker kennen het', () {
    String bron(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
    final m = bron('lib/main.dart');
    final menu = m.substring(m.indexOf('List<MenuRegel> _twijfelRegels('), m.indexOf('class TussendoorStand'));
    expect(menu, isNot(contains('speler.playQueue(')), reason: 'de hele plaat als nieuwe wachtrij');
    expect(menu, isNot(contains('speler.playUrl(')), reason: 'een rij van één');
    expect(menu, contains('final laterVerder = stand.pad == t.path ? await stand.stop(hervat: false) : false;'));
    expect(menu, contains('if (laterVerder) speler.speelAf();'));
    expect(m, contains("    tussendoor: (t) async {\n      if (player.naarSpeaker) return 'Hier speelt een speaker"));
    expect(m, contains('    if (TussendoorStand.nu.bezig) unawaited(TussendoorStand.nu.stop());'));
    final p = bron('lib/player.dart');
    expect(p, contains('final p = _proef ??= Player();'), reason: 'een tweede speler: de eerste houdt zijn rij');
    expect(p, contains('    // Een ander nummer dan wat je tussendoor beluisterde: dat stopt ([tussendoor]); jij koos iets anders.'));
    final s = bron('lib/lan/server.dart');
    expect(s, contains("await cast.tussendoor(speaker, a: tid, b: '\$kKandidaatId\${g.id}');"));
    expect(s, contains('    catalog.extraTrack = _kandidaatAlsNummer;'));
  });
}

class _GeenSpeler implements Speelbron {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _GeenRij implements Rijbediening {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

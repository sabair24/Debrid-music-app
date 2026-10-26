// ⬇ met een vroege start (online.dart, `SoulseekService.zoekVroeg`), zoals ▶ al deed. Saber, 20-10-2026:
// "doe ook maar voor download". Gemeten op de pc (3.9.526): ⬇ Please Please Please 12 s, waarvan 5 s zoeken;
// Indigo Night 21 s, waarvan 8 s zoeken.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/kandidatenzeef.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/remote_services.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/soulseek.dart';

void main() {
  SoulseekFile f(String peer, {bool vrij = true, int sec = 186, bool flac = true, String? map}) => SoulseekFile(
      username: peer,
      filename: '${map ?? 'Muziek'}\\Sabrina Carpenter\\02. Please Please Please.${flac ? 'flac' : 'mp3'}',
      size: flac ? 25000000 : 7000000,
      freeSlots: vrij,
      speed: 2000000,
      durationSec: sec,
      sampleRate: 44100,
      bitDepth: flac ? 16 : null,
      bitrate: flac ? null : 320);

  test('genoeg = acht zekere kopieën: lossless, vrije plek, de officiële lengte', () {
    final acht = [for (var i = 0; i < 8; i++) f('p$i')];
    expect(vroegGenoeg(acht, 186), isTrue);
    expect(vroegGenoeg(acht.sublist(1), 186), isFalse, reason: 'zeven is te mager: dan de hele uitslag');
    expect(vroegGenoeg([for (var i = 0; i < 8; i++) f('p$i', vrij: false)], 186), isFalse,
        reason: 'een wachtrij is geen vroege start');
    expect(vroegGenoeg([for (var i = 0; i < 8; i++) f('p$i', flac: false)], 186), isFalse, reason: 'geen mp3');
    expect(vroegGenoeg([for (var i = 0; i < 8; i++) f('p$i', sec: 196)], 186), isFalse,
        reason: '10 s langer is niet de officiële lengte');
    expect(vroegGenoeg([for (var i = 0; i < 8; i++) f('p$i', sec: 196)], null), isTrue,
        reason: 'zonder officiële lengte telt de lengte niet');
    expect(kVroegGenoeg, 8);
  });

  group('naspelen met een nagebootste zoekopdracht', () {
    Future<List<SoulseekFile>> zeefAlles(List<SoulseekFile> l) async => l;

    test('genoeg in de tussenstand na 1,2 s: die lijst, zonder op het einde te wachten', () async {
      final s = _Zoeker([
        (const Duration(milliseconds: 300), [for (var i = 0; i < 9; i++) f('vroeg$i')]),
        (const Duration(milliseconds: 1500), [for (var i = 0; i < 9; i++) f('vroeg$i')]),
      ], einde: const Duration(seconds: 5), alles: [for (var i = 0; i < 20; i++) f('laat$i')]);
      final klok = Stopwatch()..start();
      final lijst = await s.zoekVroeg('x', zeef: zeefAlles, seconden: 186);
      expect(klok.elapsed, lessThan(const Duration(seconds: 3)), reason: 'niet de 5 s van de hele uitslag');
      expect(klok.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 1200)), reason: 'niet vóór 1,2 s');
      expect(lijst.first.username, 'vroeg0');
    });

    test('te weinig in de tussenstand: de hele uitslag, zoals voorheen', () async {
      final s = _Zoeker([
        (const Duration(milliseconds: 1300), [for (var i = 0; i < 3; i++) f('vroeg$i')]),
      ], einde: const Duration(milliseconds: 1800), alles: [for (var i = 0; i < 5; i++) f('alles$i')]);
      final lijst = await s.zoekVroeg('x', zeef: zeefAlles, seconden: 186);
      expect(lijst.map((k) => k.username), [for (var i = 0; i < 5; i++) 'alles$i']);
    });
  });

  group('op de gsm: de pc zoekt en stopt vroeg (Saber, 20-10-2026: "en het snellere downloaden ook e")', () {
    late Directory map;
    late LanServer server;
    late RemoteSoulseekService gsm;
    late _Zoeker pc;

    setUp(() async {
      map = Directory.systemTemp.createTempSync('dm_gsmvroeg_');
      setAppDirForTest(map.path);
      // Op de pc: vanaf 0,3 s (en weer na 1,5 s) negen goede kopieën en één van een ander nummer; de hele
      // uitslag pas na 5 s.
      final tussenstand = [
          for (var i = 0; i < 9; i++) f('vroeg$i'),
          SoulseekFile(
              username: 'ander',
              filename: 'Muziek\Sabrina Carpenter\05. Espresso.flac',
              size: 25000000,
              freeSlots: true,
              speed: 2000000,
              durationSec: 175,
              sampleRate: 44100,
              bitDepth: 16),
      ];
      pc = _Zoeker([
        (const Duration(milliseconds: 300), tussenstand),
        (const Duration(milliseconds: 1500), tussenstand),
      ], einde: const Duration(seconds: 5), alles: [for (var i = 0; i < 20; i++) f('laat$i')], kan: true);
      server = LanServer(
        library: LibraryStore()
          ..rootPath = map.path
          ..configDirOverride = map.path,
        token: 'sleutel',
        state: LanStateStore(File('${map.path}/state.json')),
        pairing: PairingStore(),
        port: 0,
        soulseek: pc,
      );
      expect(await server.start(), isNull);
      final endpoint = RemoteEndpoint(baseUrl: Uri.parse('http://127.0.0.1:${server.boundPort}'), token: 'sleutel');
      gsm = RemoteSoulseekService(AppSettings(), () => endpoint);
    });

    tearDown(() async {
      gsm.dispose();
      await server.dispose();
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<List<SoulseekFile>> zeef(List<SoulseekFile> l) =>
        zeefKandidaten(l, titel: 'Please Please Please', seconden: 186, artiest: 'Sabrina Carpenter');

    test('met wat de zeef zoekt: na 1,2 s de goede kopieën, zonder op de hele uitslag te wachten', () async {
      final klok = Stopwatch()..start();
      final lijst = await gsm.zoekVroeg('Sabrina Carpenter Please Please Please',
          seconden: 186,
          zeef: zeef,
          zeefOp: (titel: 'Please Please Please', artiest: 'Sabrina Carpenter', album: null));
      expect(klok.elapsed, lessThan(const Duration(seconds: 3)), reason: 'niet de 5 s van de hele uitslag');
      expect(lijst.map((k) => k.username).toSet(), {for (var i = 0; i < 9; i++) 'vroeg$i'},
          reason: 'de pc zeefde al: Espresso kwam niet over de lijn');
      expect(pc.vragen, ['Sabrina Carpenter Please Please Please']);
    });

    test('zonder (een ouder toestel, of een zoekopdracht zonder nummer): de hele uitslag', () async {
      final lijst = await gsm.search('Sabrina Carpenter Please Please Please');
      expect(lijst.map((k) => k.username), [for (var i = 0; i < 20; i++) 'laat$i']);
    });
  });

  test('aangesloten: ⬇ in Online zoeken en een ontbrekend nummer zoeken vroeg, door dezelfde zeef', () {
    final online = File('lib/online.dart').readAsStringSync();
    final z = online.substring(online.indexOf('  Future<List<SoulseekFile>> zoekVroeg('));
    expect(z, contains('if (uit.isCompleted || bezig || klok.elapsed < DownloadManager.kVroegZoeken) return;'));
    expect(z, contains('if (!uit.isCompleted && vroegGenoeg(z, seconden)) uit.complete(z);'));
    expect(z, contains("search(vraag, onPartial: (l) => unawaited(kijk(l)), extra: extra).then((alles) async {"),
        reason: 'anders de hele uitslag');
    final main = File('lib/main.dart').readAsStringSync();
    final hit = main.substring(main.indexOf('Future<void> _downloadHit('));
    expect(hit, contains('zoek: () => soulseek.zoekVroeg(soulseekQuery(t.artist, t.title, album: t.album),'));
    expect(hit, contains('zeefOp: (titel: t.title, artiest: t.artist, album: t.album),'),
        reason: 'op de gsm zoekt de pc, en die moet weten waarop hij zeeft');
    expect(main, contains('zeefOp: (titel: t.title, artiest: widget.artistName, album: widget.album.title),'));
    expect(main, contains('for (final f in await soulseek.zoekVroeg(soulseekQuery(widget.artistName, t.title, album: widget.album.title),'));
  });
}

/// Een zoekopdracht die op vaste momenten tussenstanden meldt, en na [einde] de hele uitslag geeft.
class _Zoeker extends SoulseekService {
  _Zoeker(this.tussen, {required this.einde, required this.alles, this.kan = false}) : super(AppSettings());
  final List<(Duration, List<SoulseekFile>)> tussen;
  final Duration einde;
  final List<SoulseekFile> alles;
  final bool kan;
  final vragen = <String>[];

  @override
  bool get available => kan || super.available;

  @override
  Future<List<SoulseekFile>> search(String query,
      {void Function(List<SoulseekFile>)? onPartial,
      void Function(String)? gebruikteVraag,
      bool achtergrond = false,
      List<String> extra = const [],
      bool terugval = true,
      bool Function()? nogNodig}) async {
    vragen.add(query);
    final klok = Stopwatch()..start();
    for (final (wanneer, lijst) in tussen) {
      final nog = wanneer - klok.elapsed;
      if (nog > Duration.zero) await Future<void>.delayed(nog);
      onPartial?.call(lijst);
    }
    final nog = einde - klok.elapsed;
    if (nog > Duration.zero) await Future<void>.delayed(nog);
    return alles;
  }
}

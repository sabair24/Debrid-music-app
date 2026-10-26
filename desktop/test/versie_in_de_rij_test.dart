// Een nummerregel met versies (Saber, 26-10-2026, de albumpagina van All Saints op de gsm: "Vindt het wel verwarrend, wat
// is dit ? Ik heb 2 cd kwaliteit, en ik heb studio als standaard maar zie de minder goed cd kwaliteit?"). Drie dingen
// stonden scheef: de regel toonde de kwaliteit, de meting en de soort van de cd terwijl Studio speelt; op de gsm knepen
// "tot 20,9 kHz?", "cd" en de rest de titel tot niets; en "CD · andere kopie" was sample voor sample de cd uit de
// albummap, van een andere uploader.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/echtheid_meter.dart';
import 'package:debridmusic/echtheid_oordelen.dart';
import 'package:debridmusic/kopiesoort.dart';
import 'package:debridmusic/lan/catalog.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/versies.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Een FLAC-kop met STREAMINFO (en desgewenst de controlesom van de samples), tags en wat bytes erachter.
Uint8List _flac({required int hz, required int bits, int sec = 200, String md5 = '', Map<String, String> tags = const {}}) {
  final out = BytesBuilder()..add(ascii.encode('fLaC'));
  void blok(int type, List<int> body, bool laatste) {
    out.add([(laatste ? 0x80 : 0) | type, (body.length >> 16) & 0xFF, (body.length >> 8) & 0xFF, body.length & 0xFF]);
    out.add(body);
  }

  final si = Uint8List(34);
  final totaal = hz * sec;
  si[10] = (hz >> 12) & 0xFF;
  si[11] = (hz >> 4) & 0xFF;
  si[12] = ((hz & 0x0F) << 4) | (1 << 1) | (((bits - 1) >> 4) & 1);
  si[13] = (((bits - 1) & 0x0F) << 4) | ((totaal >> 32) & 0x0F);
  si[14] = (totaal >> 24) & 0xFF;
  si[15] = (totaal >> 16) & 0xFF;
  si[16] = (totaal >> 8) & 0xFF;
  si[17] = totaal & 0xFF;
  for (var i = 0; i < md5.length ~/ 2; i++) {
    si[18 + i] = int.parse(md5.substring(2 * i, 2 * i + 2), radix: 16);
  }
  blok(0, si, false);
  final b = BytesBuilder();
  void u32(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  final ven = utf8.encode('reference libFLAC 1.4.3');
  u32(ven.length);
  b.add(ven);
  u32(tags.length);
  for (final e in tags.entries) {
    final c = utf8.encode('${e.key}=${e.value}');
    u32(c.length);
    b.add(c);
  }
  blok(4, b.toBytes(), false);
  blok(1, List.filled(64, 0), true);
  out.add(List.filled(4096, 0x5A));
  return out.toBytes();
}

/// Alleen wat een nummerregel van de speler leest: speelt dit nummer.
class _Speler implements PlayerStore {
  @override
  Track? current;
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

/// De meting van de cd in de albummap op 26-10-2026 (echtheid_oordelen.json): een muur op 20,9 kHz, met vraagteken.
final _muur = Echtheidsoordeel.fromJson({
  'v': 2,
  'bits': 'onbekend',
  'boven': 'onbekend',
  'band': 'vermoedelijk',
  'gebruikteBits': 16,
  'afkapHz': 20900,
  'wandDb': 33.5,
  'vensters': 700,
  'integriteit': 'geenControlesom',
})!;

const _a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  late Directory root, config;
  late String sep, anker, studio;

  void schrijf(String pad, Uint8List bytes) {
    File(pad)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  }

  setUpAll(() => setAppDirForTest(Directory.systemTemp.createTempSync('dm_versie_rij_app_').path));

  setUp(() {
    root = Directory.systemTemp.createTempSync('dm_versie_rij_');
    config = Directory.systemTemp.createTempSync('dm_versie_rij_cfg_');
    sep = Platform.pathSeparator;
    final map = '${root.path}${sep}Albums${sep}All Saints${sep}All Saints';
    anker = '$map${sep}01 - Never Ever.flac';
    studio = '$map (studio)${sep}01 - Never Ever.flac';
    final tags = {'ARTIST': 'All Saints', 'DATE': '1998', 'TITLE': 'Never Ever', 'TRACKNUMBER': '1'};
    schrijf(anker, _flac(hz: 44100, bits: 16, tags: {...tags, 'ALBUM': 'All Saints'}));
    schrijf(studio, _flac(hz: 96000, bits: 24, tags: {...tags, 'ALBUM': 'All Saints (studio)'}));
    versies.wis();
    resetSoortenVoorToets();
    resetEchtheidVoorTest();
    versies.voegToe(anker, Versie(pad: studio, soort: Kopiesoort.studio, sindsMs: DateTime.now().millisecondsSinceEpoch),
        ankerSoort: Kopiesoort.cd);
  });
  tearDown(() {
    versies.wis();
    resetSoortenVoorToets();
    resetEchtheidVoorTest();
    root.deleteSync(recursive: true);
    config.deleteSync(recursive: true);
  });

  Future<LibraryStore> pc() async {
    final lib = LibraryStore()
      ..configDirOverride = config.path
      ..rootPath = root.path;
    await lib.scan();
    return lib;
  }

  group('de regel toont wat er speelt', () {
    test('DE KERN: Studio standaard voor de plaat → de regel leest de studioversie; zonder keuze het nummer zelf', () async {
      final lib = await pc();
      final t = lib.trackByPath(anker)!;
      expect(standaardVersieVan(lib, t).path, anker, reason: 'zonder keuze speelt het nummer zelf');
      versies.kies(anker, versieSleutel(Kopiesoort.studio, ''), bereik: VersieBereik.plaat);
      final k = standaardVersieVan(lib, t);
      expect(k.path, studio);
      expect((k.bitsPerSample, k.sampleRate), (24, 96000));
      expect(standaardVersieVan(lib, Track(path: 'x', title: 'x', artist: 'y', album: 'z')).path, 'x');
    });

    test('een toestel kent ook de meting van een versie, onder de naam die ze daar heeft', () async {
      final lib = await pc();
      onthoudOordeelVanPc(studio, _muur);
      final snap = LanCatalog(lib).snapshot();
      final dto = snap.catalog.tracks.firstWhere((d) => d.title == 'Never Ever');
      final v = (dto.versies!['lijst'] as List).single as Map;
      expect(v['echt'], isA<Map>(), reason: 'de pc stuurt haar meting mee');
      final gsm = LibraryStore()
        ..remote = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://192.168.0.117:47820'), token: 't'));
      expect(gsm.adoptMirror(jsonDecode(utf8.decode(snap.json)) as Map<String, dynamic>), isTrue);
      final t = gsm.tracks.single;
      final vt = gsm.versiesVan(t).firstWhere((x) => !x.anker).track;
      expect(vt.path, contains('/stream/'));
      expect(gemeten(vt.path)?.afkapHz, 20900, reason: 'zonder dit toont de regel op de gsm niets, of die van de cd');
    });
  });

  group('op een gsm staat de titel er helemaal', () {
    Future<void> rij(WidgetTester tester, LibraryStore lib, double breed) async {
      tester.view.physicalSize = Size(breed, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final t = lib.trackByPath(anker)!;
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryStore>.value(value: lib),
          ListenableProvider<PlayerStore>.value(value: _Speler()),
        ],
        child: MaterialApp(home: Scaffold(body: ListView(children: [TrackRow(track: t, index: 0, queue: [t])]))),
      ));
      await tester.pump();
    }

    late LibraryStore lib;
    setUp(() async {
      lib = await pc();
      zetSoortVanPc(anker, (soort: Kopiesoort.cd, gekozen: false));
      zetSoortVanPc(studio, (soort: Kopiesoort.studio, gekozen: false));
      onthoudOordeelVanPc(anker, _muur);
    });

    for (final breed in [360.0, 411.0]) {
      testWidgets('DE KERN: op $breed punten staan de merkjes onder de titel, en de titel loopt tot de kwaliteit',
          (tester) async {
        await rij(tester, lib, breed);
        final titel = tester.getRect(find.text('Never Ever'));
        final kolom = tester.getRect(find.ancestor(of: find.text('Never Ever'), matching: find.byType(Column)).first);
        final soort = tester.getRect(find.text('cd'));
        final muur = tester.getRect(find.text('tot 20,9 kHz?'));
        expect(soort.top, greaterThanOrEqualTo(titel.bottom - 1), reason: 'soort $soort, titel $titel');
        expect(muur.top, greaterThanOrEqualTo(titel.bottom - 1), reason: 'meting $muur, titel $titel');
        expect(muur.left, closeTo(kolom.left, 1), reason: 'in lijn met de titel');
        // Rechts van de titel alleen nog de kwaliteit: niets anders dat er ruimte van afsnoept.
        final badge = tester.getRect(find.textContaining('16/44.1'));
        expect(badge.left - kolom.right, lessThan(30), reason: 'kolom $kolom, kwaliteit $badge');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Studio standaard: de regel toont de studioversie, niet de cd en niet de meting van de cd', (tester) async {
      versies.kies(anker, versieSleutel(Kopiesoort.studio, ''), bereik: VersieBereik.plaat);
      await rij(tester, lib, 411);
      expect(find.textContaining('24/96'), findsOneWidget);
      expect(find.textContaining('16/44.1'), findsNothing);
      expect(find.text('studio'), findsOneWidget);
      expect(find.text('cd'), findsNothing);
      expect(find.text('tot 20,9 kHz?'), findsNothing, reason: 'die meting hoort bij de cd, en die speelt niet');
    });

    testWidgets('DE GRENS: op een breed scherm blijven de merkjes naast de titel', (tester) async {
      await rij(tester, lib, 1200);
      final titel = tester.getRect(find.text('Never Ever'));
      final muur = tester.getRect(find.text('tot 20,9 kHz?'));
      expect(muur.left, greaterThan(titel.right - 1));
      expect((muur.center.dy - titel.center.dy).abs(), lessThan(4));
    });
  });

  group('bit voor bit wat je al hebt', () {
    late String a, b;
    setUp(() {
      a = '${root.path}${sep}a.flac';
      b = '${root.path}${sep}b.flac';
    });

    test('DE KERN: dezelfde controlesom in beide koppen → hetzelfde geluid; een andere → niet', () async {
      schrijf(a, _flac(hz: 44100, bits: 16, md5: _a, tags: {'TITLE': 'Never Ever'}));
      schrijf(b, _flac(hz: 44100, bits: 16, md5: _a, tags: {'TITLE': 'Never Ever', 'ALBUM': 'All Hits'}));
      expect(await zelfdeSamples(a, b), isTrue, reason: 'alleen de tags verschillen');
      schrijf(b, _flac(hz: 44100, bits: 16, md5: _b));
      expect(await zelfdeSamples(a, b), isFalse);
    });

    test('DE GRENS: andere lengte, diepte of bemonstering is nooit hetzelfde — ook niet met dezelfde controlesom', () async {
      schrijf(a, _flac(hz: 44100, bits: 16, md5: _a));
      schrijf(b, _flac(hz: 44100, bits: 16, sec: 201, md5: _a));
      expect(await zelfdeSamples(a, b), isFalse);
      schrijf(b, _flac(hz: 44100, bits: 24, md5: _a));
      expect(await zelfdeSamples(a, b), isFalse);
      schrijf(b, _flac(hz: 48000, bits: 16, md5: _a));
      expect(await zelfdeSamples(a, b), isFalse);
    });

    test('zonder controlesom en zonder ffmpeg, of zonder FLAC-kop: nee — liever een kopie te veel', () async {
      schrijf(a, _flac(hz: 44100, bits: 16));
      schrijf(b, _flac(hz: 44100, bits: 16));
      expect(await zelfdeSamples(a, b, ffmpegPad: '${root.path}${sep}geen-ffmpeg.exe'), isFalse);
      File(b).writeAsStringSync('geen flac');
      expect(await zelfdeSamples(a, b), isFalse);
    });

    test('de pc noemt wat je al hebt: je nummer, of de versie ernaast', () async {
      schrijf(anker, _flac(hz: 44100, bits: 16, md5: _a));
      final kopie = '${root.path}${sep}All Saints (cd andere kopie)${sep}01 - Never Ever.flac';
      schrijf(kopie, _flac(hz: 44100, bits: 16, md5: _b));
      versies.voegToe(anker, Versie(pad: kopie, soort: Kopiesoort.cd, persing: 'andere kopie'));
      final cfg = AppSettings();
      final dm = DownloadManager(OnlineService(cfg), SoulseekService(cfg), root.path, () async {});
      schrijf(a, _flac(hz: 44100, bits: 16, md5: _a));
      expect(await dm.zelfdeAlsWatJeHebtVoorToets(a, anker), 'je nummer');
      schrijf(a, _flac(hz: 44100, bits: 16, md5: _b));
      expect(await dm.zelfdeAlsWatJeHebtVoorToets(a, anker), 'je versie cd andere kopie');
      schrijf(a, _flac(hz: 44100, bits: 16, md5: 'cccccccccccccccccccccccccccccccc'));
      expect(await dm.zelfdeAlsWatJeHebtVoorToets(a, anker), isNull);
    });

    test('aangesloten: de jacht op een soort, en "Bewaren (als versie)"', () {
      final online = File('lib/online.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(online, contains("    if (await _zelfdeAlsWatJeHebt(staged.path, v.pad) case final wat?) return weg('bit voor bit dezelfde als \$wat');"));
      expect(online, contains('    if (await _zelfdeAlsWatJeHebt(f.path, pad) case final wat?) {'));
    });
  });
}

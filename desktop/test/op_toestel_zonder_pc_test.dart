// Shuffle op "Op dit toestel" zonder pc (Saber, 29-10-2026: "vandaag als ik muziek speelde online, en dan lokaal omdat ik
// geen internet had, liep het fout, hij bleef de online sessie shuffelen, terwijl ik de lokale muziek shuffle knop had
// gedrukt"). Gemeten op zijn gsm: om 15:42:46 viel het netwerk weg en zocht de verbinding meteen ("Zoekt je pc… 0 s");
// om 15:42:59 schudde de knop alle 1841 nummers (schud.log op de pc), want de bibliotheek wist nog van niets.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/lan/client_session.dart';
import 'package:debridmusic/lan/verbindingsstand.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/offline.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/ui/op_toestel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Alleen wat de knoppen doen: welke lijst er geschud of gespeeld wordt.
class _Speler implements PlayerStore {
  final geschud = <List<String>>[];
  final gespeeld = <List<String>>[];
  @override
  Track? current;
  @override
  bool radioMode = false;
  @override
  Future<void> shuffleAll(List<Track> tracks) async => geschud.add([for (final t in tracks) t.path]);
  @override
  Future<void> playQueue(List<Track> tracks, int index, {Uint8List? cover}) async =>
      gespeeld.add([for (final t in tracks) t.path]);
  @override
  List<Track> get queueTracks => const [];
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

/// De verbinding met de pc, zoals de regel bovenin hem kent.
class _Sessie implements ClientSession {
  _Sessie(this.verbinding);
  @override
  Verbindingsstand verbinding;
  @override
  bool get owner => false;
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

Track _t(String pad, String titel, String album, {int nr = 1}) =>
    Track(path: pad, title: titel, artist: 'Prince', album: album, trackNo: nr);

void main() {
  final hier1 = _t('P/1999/01 - 1999.flac', '1999', '1999');
  final hier2 = _t('P/Purple Rain/03 - Purple Rain.flac', 'Purple Rain', 'Purple Rain', nr: 3);
  final pc1 = _t('P/1999/02 - Little Red Corvette.flac', 'Little Red Corvette', '1999', nr: 2);
  final pc2 = _t('P/Sign o the Times/01 - Sign o the Times.flac', 'Sign o the Times', 'Sign o the Times');
  final hier = {hier1.path, hier2.path};
  final alles = {hier1.path, hier2.path, pc1.path, pc2.path};

  group('pcWeg kijkt ook naar de verbinding', () {
    final nu = DateTime(2026, 10, 29, 15, 42, 59);
    LibraryStore toestel() => LibraryStore()
      ..remote = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://192.168.0.117:47820'), token: 't'));

    test('DE KERN: 13 s "Zoekt je pc…" en de bibliotheek weet nog van niets = de pc is weg', () {
      final zoekt = Verbindingsstand.zoekt(DateTime(2026, 10, 29, 15, 42, 46));
      expect(toestel().geenVerbinding, isNull, reason: 'zo stond het om 15:42:59 op de gsm');
      expect(pcWeg(toestel(), verbinding: zoekt, nu: nu), isTrue);
      expect(pcWeg(toestel(), nu: nu), isFalse, reason: 'zonder de verbinding wist niemand het: zo schudde hij 1841 nummers');
    });

    test('kort zoeken na een netwerkwissel is nog geen "weg"; vanaf kZoektAlsWeg wel', () {
      expect(verbindingWeg(Verbindingsstand.zoekt(nu.subtract(const Duration(milliseconds: 900))), nu: nu), isFalse);
      expect(verbindingWeg(Verbindingsstand.zoekt(nu.subtract(kZoektAlsWeg)), nu: nu), isTrue);
      expect(verbindingWeg(const Verbindingsstand.weg(Waarom.geenInternet), nu: nu), isTrue);
      expect(verbindingWeg(const Verbindingsstand.weg(Waarom.onbekend), nu: nu), isTrue);
      expect(verbindingWeg(const Verbindingsstand.verbonden(Verbindingsweg.rechtstreeks), nu: nu), isFalse);
      expect(verbindingWeg(null, nu: nu), isFalse, reason: 'geen sessie (een toets) zegt niets');
    });

    test('de bibliotheek die het al weet, blijft gelden; de pc zelf is nooit "weg"', () {
      final l = toestel()..geenVerbinding = GeenVerbinding.pcStil;
      expect(pcWeg(l, verbinding: const Verbindingsstand.verbonden(Verbindingsweg.thuis), nu: nu), isTrue);
      expect(pcWeg(LibraryStore(), verbinding: const Verbindingsstand.weg(Waarom.onbekend), nu: nu), isFalse,
          reason: 'de pc leest de pc niet uit');
    });
  });

  group('het echte scherm', () {
    late Directory scratch;
    late OfflineStore offline;

    setUp(() {
      scratch = Directory.systemTemp.createTempSync('dm_toestel_zonder_pc_');
      setAppDirForTest(scratch.path);
      File('${scratch.path}${Platform.pathSeparator}offline.json').writeAsStringSync(jsonEncode([
        for (final (i, t) in [hier1, hier2].indexed)
          OfflineTrack(
                  path: t.path,
                  file: '${scratch.path}/kopie$i.flac',
                  bytes: 30000000,
                  title: t.title,
                  artist: t.artist,
                  album: t.album,
                  savedAt: DateTime(2026, 10, 29, 8 + i))
              .toJson(),
      ]));
      offline = OfflineStore();
    });

    tearDown(() {
      try {
        scratch.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<({_Speler speler, _Sessie sessie})> bouw(WidgetTester tester, Verbindingsstand stand) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.runAsync(offline.load);
      expect(offline.tracks, hasLength(2));
      final lib = LibraryStore()
        ..tracks.addAll([hier1, pc1, hier2, pc2])
        ..rebuildAlbums()
        ..remote = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://192.168.0.117:47820'), token: 't'));
      final speler = _Speler();
      final sessie = _Sessie(stand);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryStore>.value(value: lib),
          ChangeNotifierProvider<OfflineStore>.value(value: offline),
          ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
          ListenableProvider<PlayerStore>.value(value: speler),
          ListenableProvider<ClientSession>.value(value: sessie),
        ],
        child: const MaterialApp(home: Scaffold(body: OpDitToestelView())),
      ));
      await tester.pump();
      return (speler: speler, sessie: sessie);
    }

    testWidgets('DE KERN: de verbinding zoekt al 13 s, de bibliotheek weet nog van niets: Shuffle schudt alleen wat hier staat',
        (tester) async {
      final r = await bouw(tester, Verbindingsstand.zoekt(DateTime.now().subtract(const Duration(seconds: 13))));
      expect(find.text('Zonder pc spelen Shuffle en Alles afspelen alleen wat op dit toestel staat.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toestel-shuffle')));
      await tester.pump();
      expect(r.speler.geschud.single.toSet(), hier, reason: 'de 136 van de gsm, niet de 1841 van de pc');
      await tester.pump(const Duration(seconds: 4)); // de melding
    });

    testWidgets('Alles afspelen zonder internet: alleen wat hier staat', (tester) async {
      final r = await bouw(tester, const Verbindingsstand.weg(Waarom.geenInternet));
      await tester.tap(find.byKey(const ValueKey('toestel-alles')));
      await tester.pump();
      expect(r.speler.gespeeld.single.toSet(), hier);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('met de pc bereikbaar: de hele bibliotheek (Saber, 29-10-2026)', (tester) async {
      final r = await bouw(tester, const Verbindingsstand.verbonden(Verbindingsweg.rechtstreeks));
      expect(find.text('Shuffle en Alles afspelen spelen je hele bibliotheek zolang je pc bereikbaar is.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toestel-shuffle')));
      await tester.pump();
      expect(r.speler.geschud.single.toSet(), alles);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('bij de tik gevraagd, niet bij het tekenen: verbonden getekend, weg getikt = alleen wat hier staat',
        (tester) async {
      final r = await bouw(tester, const Verbindingsstand.verbonden(Verbindingsweg.rechtstreeks));
      r.sessie.verbinding = const Verbindingsstand.weg(Waarom.onbekend); // zonder melding: niets tekent opnieuw
      await tester.tap(find.byKey(const ValueKey('toestel-shuffle')));
      await tester.pump();
      expect(r.speler.geschud.single.toSet(), hier);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('grijs wat niet hier staat zodra de verbinding weg is, ook als de bibliotheek nog van niets weet',
        (tester) async {
      await tester.runAsync(offline.load);
      final lib = LibraryStore()
        ..remote = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://192.168.0.117:47820'), token: 't'));
      final sessie = _Sessie(const Verbindingsstand.verbonden(Verbindingsweg.thuis));
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryStore>.value(value: lib),
          ChangeNotifierProvider<OfflineStore>.value(value: offline),
          ListenableProvider<ClientSession>.value(value: sessie),
        ],
        child: MaterialApp(
            home: Column(children: [
          NietHierGrijs(paden: [pc1.path], child: const Text('van de pc')),
          NietHierGrijs(paden: [hier1.path], child: const Text('hier')),
        ])),
      ));
      expect(find.byType(Opacity), findsNothing, reason: 'met de pc speelt alles');
      sessie.verbinding = const Verbindingsstand.weg(Waarom.geenInternet);
      // Een nieuwe boom: de nep-sessie meldt zich niet, de echte wel (notifyListeners in _zetStand).
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryStore>.value(value: lib),
          ChangeNotifierProvider<OfflineStore>.value(value: offline),
          ListenableProvider<ClientSession>.value(value: sessie),
        ],
        child: MaterialApp(
            home: Column(children: [
          NietHierGrijs(paden: [pc1.path], child: const Text('van de pc')),
          NietHierGrijs(paden: [hier1.path], child: const Text('hier')),
        ])),
      ));
      expect(find.ancestor(of: find.text('van de pc'), matching: find.byType(Opacity)), findsOneWidget);
      expect(find.ancestor(of: find.text('hier'), matching: find.byType(Opacity)), findsNothing);
    });

    testWidgets('een tik in Nummers (de hele bibliotheek) zonder pc: alleen wat hier staat, en niets van de pc',
        (tester) async {
      final r = await bouw(tester, Verbindingsstand.zoekt(DateTime.now().subtract(const Duration(seconds: 13))));
      final lib = tester.element(find.byType(OpDitToestelView)).read<LibraryStore>();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<LibraryStore>.value(value: lib),
          ChangeNotifierProvider<OfflineStore>.value(value: offline),
          ChangeNotifierProvider<AppSettings>.value(value: AppSettings()),
          ListenableProvider<PlayerStore>.value(value: r.speler),
          ListenableProvider<ClientSession>.value(value: r.sessie),
        ],
        child: const MaterialApp(home: Scaffold(body: TracksView(kop: false))),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Sign o the Times'), findsWidgets, reason: 'Nummers toont ook wat alleen op de pc staat');
      await tester.tap(find.text('1999').first);
      await tester.pump();
      expect(r.speler.gespeeld.single.toSet(), hier, reason: 'zonder pc speelt alleen wat hier staat');
      await tester.tap(find.text('Sign o the Times').first);
      await tester.pump();
      expect(r.speler.gespeeld, hasLength(1), reason: 'staat niet hier en de pc is weg: niets');
      expect(find.text('Staat niet op dit toestel, en je pc is nu niet bereikbaar'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  test('aangesloten: de tik in elke lijst kijkt naar de verbinding, en speelt zonder pc op dit toestel', () {
    final main = _bron('lib/main.dart');
    final tik = main.indexOf('Future<void> speelGetikt(BuildContext context');
    final eind = main.indexOf('\n}\n', tik);
    final stuk = main.substring(tik, eind);
    expect(stuk, contains('pcWeg(context.read<LibraryStore>(), verbinding: _misschien<ClientSession>(context)?.verbinding)'));
    expect(stuk, contains('  final afstand = zonderPc ? null : _misschien<GekozenZone>(context)?.opAfstand;'),
        reason: 'een zone bereik je alleen via de pc');
    final pagina = main.substring(main.indexOf('class _OpDitToestelViewState'), main.indexOf('class _Overzetten'));
    expect(pagina, contains(': (lijst: alleHier, speler: context.read<PlayerStore>());'),
        reason: 'zonder pc op dit toestel, ook als er een zone gekozen is');
    expect(pagina, isNot(contains('lib.geenVerbinding == null')), reason: 'de oude regel keek alleen naar de bibliotheek');
    final grijs = _bron('lib/ui/op_toestel.dart');
    expect(grijs, contains('(pcWeg(l) || (l.isRemote && losVanPc))'), reason: 'grijs zodra de verbinding weg is');
  });
}

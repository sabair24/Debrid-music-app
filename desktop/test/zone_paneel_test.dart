/// Waar de zones staan, stap 4 (Saber, 23-10-2026): "Groot scherm (pc 24", iPad liggend, Mac): een paneel aan de
/// zijkant dat open kan blijven. Op de gsm blijft het een blad van onderen." En op de Shield: "de zones als paneel
/// zoals op pc en Mac, maar tv-vriendelijk".
///
/// Wat hier vastligt:
/// - op een groot scherm opent de knop een paneel naast de pagina's, en sluit hij het weer; de wachtrij gaat dan dicht;
/// - een zone kiezen in dat paneel laat het open (het blad op de gsm gaat dicht, zoals altijd);
/// - op een gsm blijft het een blad van onderen;
/// - op de Shield schuift een paneel van rechts binnen, de markering staat op de zone die je bedient, de pijltjes
///   blijven erin, en Terug sluit het.
library;

import 'dart:io';

import 'package:debridmusic/lan/zones.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart'
    show ZoneBlad, ZoneWeergave, kZonePaneelTv, toonZoneBlad, zoneKnoppenMetWoord, zonePaneelNaast;
import 'package:debridmusic/models.dart';
import 'package:debridmusic/player.dart' show RepeatMode, WachtrijPaneel, ZonePaneel;
import 'package:debridmusic/tv.dart' show setTvModeForTest;
import 'package:debridmusic/verder_luisteren.dart';
import 'package:debridmusic/zone_lijst.dart';
import 'package:debridmusic/zone_speler.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Bron implements VerderBron {
  @override
  String get mijnId => 'gsm-1';

  @override
  bool get ikSpeel => false;

  @override
  Track? nummer(String id) =>
      Track(path: 'http://pc.invalid/stream/$id.flac', title: 'Nummer $id', artist: 'X', album: 'A');

  @override
  Future<({Map<String, dynamic>? stand, Map<String, dynamic>? verzoek})?> haal() async => null;

  @override
  Future<void> speel(List<Track> rij, int index, Duration positie,
      {required bool spelen, required bool shuffle, required RepeatMode herhaal, String? radioArtiest}) async {}

  @override
  void pauzeer() {}
}

const _nu = 1000000;

ZoneStaat _zone(String id, String naam, {ZoneSoort soort = ZoneSoort.gsm, bool playing = false, String trackId = ''}) =>
    ZoneStaat(
      id: id,
      soort: soort,
      naam: naam,
      online: true,
      playing: playing,
      trackId: trackId,
      positionMs: 60000,
      durationMs: 240000,
      opMs: _nu - 5000,
      volume: playing ? 40 : -1,
      kanGroeperen: true,
    );

final _pc = _zone('dev:pc-THUIS', 'Pc', soort: ZoneSoort.pc, playing: true, trackId: 'b');
final _amp = _zone('spk:amp', 'Sonos Amp', soort: ZoneSoort.speaker, playing: true, trackId: 'c');
final _gsm = _zone('dev:gsm-1', 'Galaxy');

void main() {
  tearDown(() {
    zoneKnoppenMetWoord = null;
    setTvModeForTest(false);
  });

  group('waar het paneel past', () {
    test('DE KERN: een groot scherm — waar Nu speelt naast elkaar staat', () {
      expect(zonePaneelNaast(const Size(1920, 1040), compact: false), isTrue, reason: 'pc 24"');
      expect(zonePaneelNaast(const Size(1600, 867), compact: false), isTrue, reason: 'de Mac');
      expect(zonePaneelNaast(const Size(1194, 834), compact: false), isTrue, reason: 'iPad liggend');
    });

    test('DE GRENS: een gsm, een iPad staand en een smal venster krijgen het blad', () {
      expect(zonePaneelNaast(const Size(411, 915), compact: true), isFalse);
      expect(zonePaneelNaast(const Size(834, 1194), compact: false), isFalse, reason: 'iPad staand');
      expect(zonePaneelNaast(const Size(1000, 800), compact: false), isFalse);
    });
  });

  Future<({ZonePaneel zones, WachtrijPaneel wachtrij, GekozenZone gekozen})> pomp(WidgetTester t,
      {required Size scherm, required Widget Function(BuildContext) inhoud}) async {
    t.view.physicalSize = scherm;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final v = VerderLuisteren(_Bron(), klok: () => _nu);
    final lijst = ZoneLijst(hier: 'dev:gsm-1', klok: () => _nu)
      ..zet({'nu': _nu, 'zones': [for (final z in [_pc, _amp, _gsm]) z.toJson()]})
      ..stuur = (zone, op) async {
        return null;
      }
      ..verplaats = (van, naar) async {
        return null;
      };
    final gekozen = GekozenZone(
      lijst: lijst,
      bewaar: (_) {},
      maak: (id) => ZoneSpeler(
          lijst: lijst, zoneId: id, nummer: v.bron.nummer, idVan: (t) => t.title, hoesVan: (_) => null, stuur: (_) async => null),
    );
    addTearDown(gekozen.dispose);
    final zones = ZonePaneel();
    final wachtrij = WachtrijPaneel();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>(create: (_) => LibraryStore()),
        ChangeNotifierProvider<VerderLuisteren>.value(value: v),
        ChangeNotifierProvider<ZoneLijst>.value(value: lijst),
        ChangeNotifierProvider<GekozenZone>.value(value: gekozen),
        ChangeNotifierProvider<ZonePaneel>.value(value: zones),
        ChangeNotifierProvider<WachtrijPaneel>.value(value: wachtrij),
      ],
      // "Animaties verminderen": de balkjes op een spelende kaart staan dan stil ([_Balkjes]), en anders komt
      // pumpAndSettle nooit tot rust.
      child: MaterialApp(
        builder: (c, kind) => MediaQuery(data: MediaQuery.of(c).copyWith(disableAnimations: true), child: kind!),
        home: Scaffold(body: Builder(builder: inhoud)),
      ),
    ));
    await t.pump(const Duration(milliseconds: 100));
    return (zones: zones, wachtrij: wachtrij, gekozen: gekozen);
  }

  Widget knop(BuildContext context) =>
      Center(child: TextButton(onPressed: () => toonZoneBlad(context), child: const Text('Zones')));

  testWidgets('DE KERN: op een groot scherm een paneel aan de zijkant, en de wachtrij gaat dicht', (t) async {
    final o = await pomp(t, scherm: const Size(1920, 1040), inhoud: knop);
    o.wachtrij.wissel();
    expect(o.wachtrij.open, isTrue);
    await t.tap(find.text('Zones'));
    await t.pumpAndSettle();
    expect(o.zones.open, isTrue);
    expect(o.wachtrij.open, isFalse, reason: 'één paneel tegelijk aan de zijkant');
    expect(find.byType(BottomSheet), findsNothing, reason: 'geen blad van onderen op een pc');
    await t.tap(find.text('Zones'));
    await t.pump();
    expect(o.zones.open, isFalse, reason: 'nog eens drukken sluit het');
  });

  testWidgets('DE GRENS: op een gsm het blad van onderen, zoals altijd', (t) async {
    final o = await pomp(t, scherm: const Size(411, 900), inhoud: knop);
    await t.tap(find.text('Zones'));
    await t.pumpAndSettle();
    expect(o.zones.open, isFalse);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(ZoneBlad), findsOneWidget);
    // Een zone kiezen sluit het blad.
    await t.tap(find.byKey(const ValueKey('zone-kies-dev:pc-THUIS')));
    await t.pumpAndSettle();
    expect(o.gekozen.gekozen, 'dev:pc-THUIS');
    expect(find.byType(ZoneBlad), findsNothing);
    o.gekozen.kies('dev:gsm-1');
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('DE VAL: een zone kiezen in het paneel laat het open — het blijft tot je het sluit', (t) async {
    zoneKnoppenMetWoord = false;
    // Op een geopende pagina: zou een keuze toch "terug" doen, dan ging die pagina dicht.
    final o = await pomp(t,
        scherm: const Size(1920, 1040),
        inhoud: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                          body: Align(
                            alignment: Alignment.centerRight,
                            child: SizedBox(width: 380, height: 900, child: ZoneBlad(weergave: ZoneWeergave.paneel)),
                          ),
                        ))),
                child: const Text('Pagina'),
              ),
            ));
    await t.tap(find.text('Pagina'));
    await t.pumpAndSettle();
    o.zones.wissel();
    // De kaarten staan onder elkaar, het paneel vult zijn hoogte.
    expect(t.getSize(find.byType(ZoneBlad)).height, 900);
    await t.tap(find.byKey(const ValueKey('zone-kies-dev:pc-THUIS')));
    await t.pump(const Duration(milliseconds: 400));
    expect(o.gekozen.gekozen, 'dev:pc-THUIS');
    expect(find.byType(ZoneBlad), findsOneWidget, reason: 'het paneel aan de zijkant gaat niet dicht na een keuze');
    expect(find.textContaining('Je bedient: Pc', findRichText: true), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('zone-paneel-dicht')));
    await t.pump();
    expect(o.zones.open, isFalse);
    o.gekozen.kies('dev:gsm-1');
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('op de Shield: een paneel van rechts, de markering erin, en Terug sluit het', (t) async {
    setTvModeForTest(true);
    final o = await pomp(t, scherm: const Size(960, 540), inhoud: knop);
    await t.tap(find.text('Zones'));
    await t.pumpAndSettle();
    expect(o.zones.open, isFalse, reason: 'geen paneel naast de pagina op een tv');
    final paneel = find.byKey(const ValueKey('zone-paneel-tv'));
    expect(paneel, findsOneWidget);
    expect(t.getSize(paneel).width, kZonePaneelTv);
    expect(t.getTopRight(paneel).dx, 960 - 48, reason: 'binnen de overscanrand, tegen de rechterkant');

    bool focusIn(Finder f) {
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx == null) return false;
      final doel = t.element(f);
      var binnen = false;
      ctx.visitAncestorElements((e) {
        if (e == doel) binnen = true;
        return !binnen;
      });
      return binnen || ctx == doel;
    }

    expect(focusIn(find.byKey(const ValueKey('zone-kies-dev:gsm-1'))), isTrue,
        reason: 'de markering start op de zone die je bedient');
    // Omlaag loopt door het paneel en blijft erin.
    for (var i = 0; i < 6; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump(const Duration(milliseconds: 100));
      expect(focusIn(paneel), isTrue, reason: 'na ${i + 1}× omlaag');
    }
    // Terug sluit het.
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(paneel, findsNothing);
    expect(find.text('Zones'), findsOneWidget);
  });

  group('bedrading (gelezen uit lib/main.dart)', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');

    test('de schil zet het paneel naast de pagina\'s, waar het past', () {
      expect(main, contains('                        child: ZoneBlad(weergave: ZoneWeergave.paneel),'));
      expect(main, contains('zonePaneelNaast(MediaQuery.sizeOf(context), compact: isCompact(context)))'));
    });

    test('Nu speelt zet de zones in het vak van de wachtrij', () {
      expect(main, contains("? const ZoneBlad(key: ValueKey('np-zonepaneel'), weergave: ZoneWeergave.paneel)"));
      expect(main, contains('_volgVak(zones: naast && !isTv && (_misschien<ZonePaneel>(context, luister: true)?.open ?? false));'));
    });

    test('de wachtrijknop sluit de zones; de zoneknop sluit de wachtrij', () {
      expect(main, contains('            if (!paneel.open) _misschien<ZonePaneel>(context)?.sluit();\n            paneel.wissel();'));
      expect(main, contains('    if (!paneel.open) _misschien<WachtrijPaneel>(context)?.sluit();\n    paneel.wissel();'));
    });

    test('op de Shield de zoneknop in de balk en "Speelt op …" in Nu speelt', () {
      expect(main, isNot(contains('if (!isTv) const ZoneKiesKnop(alsIcoon: true),')));
      expect(main, contains("return isTv ? TvLabelled(label: 'Zones', child: knop) : knop;"));
      expect(main, contains('      if (isTv && naast) ...[\n        const Align(alignment: Alignment.centerLeft, child: ZoneKiesKnop()),'));
    });

    test('na een keuze gaat alleen het blad of het tv-paneel dicht', () {
      final zones = main.substring(main.indexOf('class ZoneBlad'), main.indexOf('class _HartKnop'));
      // Alleen _naKeuzeInZones zelf mag nog poppen.
      expect(RegExp(r'^\s*(nav|Navigator\.of\(context\))\.maybePop\(\);', multiLine: true).allMatches(zones).length, 0,
          reason: 'elke keuze in de zones loopt via _naKeuzeInZones');
      expect(zones, contains('  return () => nav.maybePop();'));
      expect(main, contains('  if (w == ZoneWeergave.paneel) return () {};'));
    });
  });
}

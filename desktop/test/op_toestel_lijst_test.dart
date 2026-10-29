// "Op dit toestel" los van "Mijn downloads", met tabs, Alles afspelen/Shuffle en een eigen zoekveld (Saber, 29-10-2026:
// "downloads en op een toestel opslaan zijn 2 verschillende dingen e … moet ik kunnen shuffelen en allemaal spelen
// kunnen doen, plus ook een zoek functie"). Hier: wat er in welke volgorde staat ([opToestelLijst]), en de bedrading.
import 'dart:io';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/offline.dart';
import 'package:debridmusic/ui/op_toestel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Track _t(String pad, String titel, String artiest, String album, {int nr = 1}) =>
    Track(path: pad, title: titel, artist: artiest, album: album, trackNo: nr);

OfflineTrack _o(Track t, DateTime wanneer) => OfflineTrack(
    path: t.path, file: '/kopie/${t.path}', bytes: 1000, title: t.title, artist: t.artist, album: t.album, savedAt: wanneer);

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final crazy = _t('b/crazy.flac', 'Crazy', 'Britney Spears', 'Crazy');
  final toxic = _t('b/toxic.flac', 'Toxic', 'Britney Spears', 'In the Zone', nr: 6);
  final angie = _t('r/angie.flac', 'Angie', 'The Rolling Stones', 'Goats Head Soup', nr: 5);
  final nietHier = _t('r/doom.flac', 'Doo Doo Doo', 'The Rolling Stones', 'Goats Head Soup', nr: 1);
  final albums = [
    Album('Crazy', 'Britney Spears', [crazy]),
    Album('In the Zone', 'Britney Spears', [toxic]),
    Album('Goats Head Soup', 'The Rolling Stones', [nietHier, angie]),
  ];
  final perPad = {for (final t in [crazy, toxic, angie, nietHier]) t.path: t};
  // Zoals OfflineStore.tracks: nieuwste eerst.
  final opgeslagen = [
    _o(angie, DateTime(2026, 10, 29, 9)),
    _o(crazy, DateTime(2026, 10, 28, 20)),
    _o(toxic, DateTime(2026, 10, 27, 12)),
  ];
  ({List<Track> nummers, List<Album> albums}) lijst({String zoek = '', bool az = false}) =>
      opToestelLijst(opgeslagen: opgeslagen, nummerVan: (p) => perPad[p], albums: albums, zoek: zoek, az: az);

  test('DE KERN: laatst opgeslagen eerst, voor nummers en voor platen', () {
    final l = lijst();
    expect([for (final t in l.nummers) t.title], ['Angie', 'Crazy', 'Toxic']);
    expect([for (final a in l.albums) a.title], ['Goats Head Soup', 'Crazy', 'In the Zone'],
        reason: 'een plaat waarvan maar één nummer hier staat, hoort er ook bij — die helft speelt');
  });

  test('A–Z: op artiest (zonder "The"), dan plaat, dan nummer', () {
    final l = lijst(az: true);
    expect([for (final t in l.nummers) t.title], ['Crazy', 'Toxic', 'Angie']);
    expect([for (final a in l.albums) a.title], ['Crazy', 'In the Zone', 'Goats Head Soup']);
  });

  test('zoeken: alleen wat hier staat, op titel, artiest en album, elk woord', () {
    expect([for (final t in lijst(zoek: 'britney').nummers) t.title], ['Crazy', 'Toxic']);
    expect([for (final t in lijst(zoek: 'zone').nummers) t.title], ['Toxic']);
    expect([for (final t in lijst(zoek: 'rolling doo').nummers) t.title], isEmpty,
        reason: '"Doo Doo Doo" staat niet op dit toestel');
    expect([for (final a in lijst(zoek: 'goats').albums) a.title], ['Goats Head Soup']);
    expect([for (final t in lijst(zoek: 'CRÄZY').nummers) t.title], ['Crazy'], reason: 'hoofdletters en accenten tellen niet');
  });

  test('een nummer dat de bibliotheek niet kent, valt weg in plaats van de lijst te breken', () {
    final l = opToestelLijst(
        opgeslagen: [...opgeslagen, _o(_t('x/weg.flac', 'Weg', 'X', 'Y'), DateTime(2026, 10, 29, 10))],
        nummerVan: (p) => perPad[p],
        albums: albums);
    expect(l.nummers, hasLength(3));
  });

  test('DE KERN: Mijn downloads toont niet meer wat op dit toestel staat; Op dit toestel heeft alles', () {
    final main = _bron('lib/main.dart');
    expect(main, isNot(contains('_OfflineSection')), reason: 'downloads en op een toestel opslaan zijn 2 verschillende dingen');
    final pagina = main.substring(main.indexOf('class _OpDitToestelViewState'), main.indexOf('class _Overzetten'));
    for (final k in ['toestel-shuffle', 'toestel-alles', 'toestel-zoek', 'toestel-volgorde', 'toestel-alles-weg']) {
      expect(pagina, contains("ValueKey('$k')"), reason: k);
    }
    expect(pagina, contains('final teSpelen = pcBereikbaar ? lib.tracks : alleHier;'),
        reason: 'Saber: met de pc bereikbaar de hele bibliotheek, zonder pc alleen wat hier staat');
    expect(pagina, contains('_Overzetten(rand: rand)'), reason: 'wat onderweg is naar dit toestel, staat hier');
    for (final tab in ['albums', 'nummers', 'artiesten', 'afspeellijsten', 'favorieten']) {
      expect(main, contains('_ToestelTab.$tab'), reason: tab);
    }
  });

  group('hoe groot het wordt (Saber, 29-10-2026: "voor ik begin met downloaden wil ik ook al zien hoeveel ruimte")', () {
    Track m(String pad, {int bytes = 0, int hz = 0, int bits = 0, int sec = 0}) => Track(
        path: pad, title: 't', artist: 'a', album: 'b', sizeBytes: bytes, sampleRate: hz, bitsPerSample: bits,
        duration: sec > 0 ? Duration(seconds: sec) : null);

    test('DE KERN: hi-res komt als cd, dus de grootte zakt met de bitstroom', () {
      // 24/96 → 16/44,1: 44100×16 / (96000×24) = 0,30625.
      expect(geschatteOmvang([m('x.flac', bytes: 100000000, hz: 96000, bits: 24)], cd: true), 30625000);
      expect(geschatteOmvang([m('x.flac', bytes: 100000000, hz: 96000, bits: 24)], cd: false), 100000000,
          reason: 'Origineel gekozen: zoals hij is');
    });

    test('wat al cd is of lager, en lossy, blijft zoals het is', () {
      expect(geschatteOmvang([m('x.flac', bytes: 30000000, hz: 44100, bits: 16)], cd: true), 30000000);
      expect(geschatteOmvang([m('x.mp3', bytes: 9000000, hz: 48000, bits: 0)], cd: true), 9000000,
          reason: 'een mp3 wordt niet omgezet');
      expect(geschatteOmvang([m('x.flac', bytes: 40000000, hz: 48000, bits: 16)], cd: true), 36750000,
          reason: '16/48 is boven cd: × 44100/48000');
    });

    test('zonder bekende grootte: de duur maal 110 kB/s, en het totaal telt op', () {
      expect(geschatteOmvang([m('x.flac', sec: 200)], cd: true), 22000000);
      expect(
          geschatteOmvang([m('x.flac', sec: 200), m('y.flac', bytes: 5000000, hz: 44100, bits: 16)], cd: true), 27000000);
      expect(geschatteOmvang(const [], cd: true), 0);
    });

    test('de maat leest zoals de vraag hem toont', () {
      expect(toestelMaat(380 * 1000 * 1000), '380 MB');
      expect(toestelMaat(1200 * 1000 * 1000), '1,2 GB');
      expect(toestelOmvang(12, 380 * 1000 * 1000), '12 nummers · 380 MB');
    });

    test('de vrije ruimte komt van Android, iOS en macOS, en Opslaan kan niet als het niet past', () {
      final ui = _bron('lib/ui/op_toestel.dart');
      expect(ui, contains("const MethodChannel('debridmusic/device').invokeMethod<Object>('vrijeRuimte')"));
      expect(ui, contains("const MethodChannel('debridmusic/ruimte').invokeMethod<Object>('vrij')"));
      expect(ui, contains('            onPressed: teVeel ? null : () => Navigator.pop(ctx, true),\n'));
      expect(_bron('android/app/src/main/kotlin/com/debridmusic/app/MainActivity.kt'),
          contains('try { StatFs(filesDir.path).availableBytes } catch (e: Exception) { -1L }'));
      for (final f in ['ios/Runner/AppDelegate.swift', 'macos/Runner/MainFlutterWindow.swift']) {
        final s = _bron(f);
        expect(s, contains('name: "debridmusic/ruimte"'), reason: f);
        expect(s, contains('volumeAvailableCapacityForImportantUsage'), reason: f);
      }
    });
  });

  group('de vraag vóór het opslaan', () {
    Future<bool?> vraag(WidgetTester tester, {required int bytes, required int vrij}) async {
      bool? uit;
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => TextButton(
                  onPressed: () async => uit = await vraagOpToestelZetten(context, aantal: 12, bytes: bytes, vrij: vrij),
                  child: const Text('open')))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return uit;
    }

    testWidgets('toont de grootte en wat er nog vrij is, en Opslaan zegt ja', (tester) async {
      await vraag(tester, bytes: 380 * 1000 * 1000, vrij: 12 * 1000 * 1000 * 1000);
      expect(find.text('12 nummers, ongeveer 380 MB — nog 12,0 GB vrij op dit toestel.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toestel-op-ja')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('past het niet, dan zegt hij het en kan Opslaan niet', (tester) async {
      await vraag(tester, bytes: 2 * 1000 * 1000 * 1000, vrij: 500 * 1000 * 1000);
      expect(find.textContaining('niet genoeg ruimte'), findsOneWidget);
      final knop = tester.widget<FilledButton>(find.byKey(const ValueKey('toestel-op-ja')));
      expect(knop.onPressed, isNull);
    });
  });

  group('onder cd-kwaliteit: gewoon zo, met een merkje (Saber, 29-10-2026)', () {
    Track m(String pad, {int hz = 0, int bits = 0, bool flac = false}) =>
        Track(path: pad, title: 't', artist: 'a', album: 'b', sampleRate: hz, bitsPerSample: bits, isFlac: flac);

    test('DE KERN: mp3 en aac zijn onder cd; cd en hi-res niet', () {
      expect(onderCd(m('x.mp3', hz: 44100)), isTrue);
      expect(onderCd(m('x.ogg')), isTrue);
      expect(onderCd(m('x.flac', hz: 44100, bits: 16)), isFalse);
      expect(onderCd(m('x.flac', hz: 96000, bits: 24)), isFalse, reason: 'hi-res komt als cd');
      expect(onderCd(m('x.flac')), isFalse, reason: 'zonder kop: een flac telt als cd');
    });

    test('verliesvrij onder 16/44,1 is ook onder cd; m4a hangt aan de diepte', () {
      expect(onderCd(m('x.flac', hz: 22050, bits: 16)), isTrue);
      expect(onderCd(m('x.wav', hz: 44100, bits: 8)), isTrue);
      expect(onderCd(m('x.m4a', hz: 44100, bits: 16)), isFalse, reason: 'ALAC');
      expect(onderCd(m('x.m4a', hz: 44100)), isTrue, reason: 'AAC');
    });

    testWidgets('de vraag zegt hoeveel er onder cd zijn', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => TextButton(
                  onPressed: () => vraagOpToestelZetten(context, aantal: 12, bytes: 1000, vrij: 5000, onderCdAantal: 3),
                  child: const Text('open')))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('3 daarvan zijn onder cd-kwaliteit'), findsOneWidget);
    });

    test('aangesloten: het merkje in de rijen, het nummermenu en de ruimte op de albumknop', () {
      final main = _bron('lib/main.dart');
      expect(main, contains("      aantal: nieuw.length, bytes: bytes, onderCdAantal: komen.where(onderCd).length);\n"));
      expect(main, contains("              ? MenuRegel(Icons.offline_pin_rounded, 'Van dit toestel halen…',\n"
          "                  () => unawaited(_haalVanToestel(context, [t])))\n"));
      expect(main, contains("              : MenuRegel(Icons.download_for_offline_outlined, 'Op dit toestel…',\n"
          "                  () => unawaited(_zetOpToestel(context, [t]))),\n"));
      expect(main, contains("  final offline = lib.isRemote && !isTv ? context.read<OfflineStore?>() : null;\n"),
          reason: 'niet op de pc en niet op tv');
      expect(main, contains(r"? 'Op dit toestel · ${toestelMaat(offline.bytesVan([for (final t in tracks) t.path]))}'"));
      final weg = main.indexOf('Future<bool> _haalVanToestel(');
      expect(main.indexOf('vraagVanToestelHalen(', weg), lessThan(main.indexOf('await offline.remove(p);', weg)),
          reason: 'eerst de vraag, dan pas weghalen');
    });
  });

  group('zonder pc: alles zichtbaar, grijs wat niet hier staat (Saber, 29-10-2026)', () {
    final a = _t('a.flac', 'A', 'X', 'P', nr: 1);
    final b = _t('b.flac', 'B', 'X', 'P', nr: 2);
    final c = _t('c.flac', 'C', 'X', 'P', nr: 3);
    final d = _t('d.flac', 'D', 'X', 'P', nr: 4);
    bool hier(String p) => p != 'b.flac' && p != 'd.flac';

    test('DE KERN: een tik speelt alleen wat hier staat, vanaf het getikte', () {
      final uit = alleenHier([a, b, c, d], 2, hier)!;
      expect(uit.lijst, [a, c]);
      expect(uit.index, 1, reason: 'c was plek 2 en is nu plek 1');
      expect(alleenHier([a, b, c, d], 0, hier)!.index, 0);
    });

    test('staat het getikte er niet, dan speelt er niets', () {
      expect(alleenHier([a, b, c, d], 1, hier), isNull);
      expect(alleenHier([a, b], 5, hier), isNull);
    });

    testWidgets('zonder bibliotheek of winkel in de boom (de pc, een toets) nooit grijs', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: NietHierGrijs(paden: ['a.flac'], child: Text('rij'))));
      expect(find.byType(Opacity), findsNothing);
      expect(tester.takeException(), isNull);
    });

    test('aangesloten: rijen, tegels, de tik, en de bibliotheek meldt als de pc terug is', () {
      final main = _bron('lib/main.dart');
      expect(main, contains('  Widget build(BuildContext context) => NietHierGrijs(paden: [widget.track.path], child: _bouw(context));\n'),
          reason: 'de rij van een album');
      expect(main, contains('                child: NietHierGrijs(\n                paden: [t.path],\n                child: Builder(\n'),
          reason: 'de rij van Tracks');
      expect(main, contains('        return NietHierGrijs(\n          paden: [for (final t in a.tracks) t.path],\n'),
          reason: 'de tegel op Albums en Start');
      final tik = main.indexOf('Future<void> speelGetikt(BuildContext context');
      expect(main.indexOf('    final hier = alleenHier(lijst, index, hierAlleen.has);\n', tik), greaterThan(tik));
      expect(main.indexOf('    (lijst, index) = (hier.lijst, hier.index);\n', tik),
          lessThan(main.indexOf('  final afstand = _misschien<GekozenZone>(context)?.opAfstand;', tik)),
          reason: 'eerst filteren, dan pas spelen');
      final lib = _bron('lib/library.dart');
      expect(lib, contains('    final wasWeg = geenVerbinding != null;\n    geenVerbinding = null;\n    if (wasWeg) notifyListeners();\n'),
          reason: 'anders blijft alles grijs na een stille ronde die op 304 eindigt');
    });
  });
}

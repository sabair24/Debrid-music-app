/// Een eigen smaak per verzameling en de verzameling op de gsm (21-11-2026). Saber koos voor de smaak "Alleen binnen de
/// verzameling", en voor de gsm "Alleen als ik het kies": een verzameling gaat niet vanzelf mee, wel met één tik.
library;

import 'dart:io';

import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart'
    show VerzamelingPagina, meerVanVerzameling, verzamelZaden, verzamelingLijstId, verzamelingVanLijstId;
import 'package:debridmusic/models.dart';
import 'package:debridmusic/recommend.dart';
import 'package:debridmusic/verzamelingen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

Track _t(String artiest, String titel, {String map = r'D:\m\DebridMusic Downloads\Verzamelingen\Vocal jazz\Singles'}) =>
    Track(path: '$map\\$titel.flac', title: titel, artist: artiest, album: '');

/// Een bibliotheek met vaste id's (zoals een toestel ze uit het stroomadres haalt).
class _Lib extends LibraryStore {
  @override
  String? gedeeldId(String path) => 'id:${path.split(r'\').last}';
}

/// Telt wat er gevraagd werd, en geeft wat de toets wil.
class _Rec extends RecommendService {
  _Rec(this.antwoord) : super(haal: (_) async => null);
  final List<RecTrack> antwoord;
  final vragen = <(List<String>, Set<String>)>[];

  @override
  Future<List<RecTrack>> ontdekVoorJou(List<({String naam, double gewicht})> zaden, Set<String> bezit,
      {int kandidaten = 150, int max = 200, int verder = 4}) async {
    vragen.add(([for (final z in zaden) z.naam], bezit));
    return antwoord;
  }
}

void main() {
  test('DE KERN: de smaak van een verzameling zijn haar artiesten, gewogen naar hoeveel je van elk hebt', () {
    final z = verzamelZaden([
      for (var i = 0; i < 4; i++) _t('Nancy Wilson', 'n$i'),
      _t('Nancy Wilson feat. Cannonball Adderley', 'save'),
      for (var i = 0; i < 2; i++) _t('Sarah Vaughan', 's$i'),
      _t('Ella Fitzgerald', 'e'),
    ]);
    expect([for (final x in z) (x.naam, x.gewicht)],
        [('Nancy Wilson', 1.0), ('Sarah Vaughan', .4), ('Ella Fitzgerald', .2)],
        reason: 'een gast maakt het geen andere artiest');
    expect(verzamelZaden([for (var i = 0; i < 12; i++) _t('A$i', 't$i')]), hasLength(8));
    expect(verzamelZaden(const []), isEmpty);
  });

  test('DE KERN: "Meer …" vraagt met alleen de verzameling als smaak, en weert wat je al hebt — ook buiten haar', () async {
    final rec = _Rec([const RecTrack('Diana Krall', 'The Look of Love', null)]);
    final lijst = await meerVanVerzameling('Vocal jazz (toets 1)', [_t('Nancy Wilson', 'a'), _t('Sarah Vaughan', 'b')],
        {'sade', 'nancy wilson'},
        rec: rec);
    expect(lijst.single.artist, 'Diana Krall');
    expect(rec.vragen.single.$1, ['Nancy Wilson', 'Sarah Vaughan']);
    expect(rec.vragen.single.$2, {'sade', 'nancy wilson'});
  });

  test('DE GRENS: een uur lang hetzelfde antwoord, daarna opnieuw', () async {
    final rec = _Rec(const []);
    var nu = 1000000;
    Future<void> vraag() =>
        meerVanVerzameling('Vocal jazz (toets 2)', [_t('Nancy Wilson', 'a')], const {}, rec: rec, nuMs: () => nu);
    await vraag();
    nu += const Duration(minutes: 59).inMilliseconds;
    await vraag();
    expect(rec.vragen, hasLength(1));
    nu += const Duration(minutes: 2).inMilliseconds;
    await vraag();
    expect(rec.vragen, hasLength(2));
  });

  test('een lege verzameling vraagt niets', () async {
    final rec = _Rec(const []);
    expect(await meerVanVerzameling('Leeg (toets)', const [], const {}, rec: rec), isEmpty);
    expect(rec.vragen, isEmpty);
  });

  test('op dit toestel: een eigen id naast de afspeellijsten, en terug naar de naam', () {
    expect(verzamelingLijstId('Vocal jazz'), 'verz:vocal jazz');
    expect(verzamelingVanLijstId('verz:vocal jazz', ['Crooners & standards', 'Vocal jazz']), 'Vocal jazz');
    expect(verzamelingVanLijstId('verz:kerst', ['Vocal jazz']), isNull, reason: 'opgeheven: dan gaat ze eraf');
    expect(verzamelingVanLijstId('a1b2c3', ['Vocal jazz']), isNull, reason: 'een afspeellijst');
    expect(verzamelingVanLijstId('vocal jazz', ['Vocal jazz']), isNull, reason: 'zonder voorvoegsel: een afspeellijst');
  });

  testWidgets('DE KERN: de tab "Meer …" toont wat erbij past', (tester) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lib = _Lib()
      ..tracks.addAll([_t('Nancy Wilson', 'Guess Who I Saw Today', map: r'D:\m\DebridMusic Downloads\Singles')])
      ..rebuildAlbums();
    final verz = Verzamelingen()
      ..winkel = LanStateStore(File('${Directory.systemTemp.createTempSync('dm_meer_').path}${Platform.pathSeparator}s.json'));
    await tester.runAsync(() => verz.koppel('Jazzzangers', ['id:Guess Who I Saw Today.flac']));
    // Wat Deezer zou zeggen, alvast in de voorraad van de pagina.
    await tester.runAsync(() => meerVanVerzameling('Jazzzangers', [lib.tracks.single], const {},
        rec: _Rec([const RecTrack('Diana Krall', 'The Look of Love', null), const RecTrack('Stacey Kent', 'Ces Petits Riens', null)])));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>.value(value: lib),
        ChangeNotifierProvider<Verzamelingen>.value(value: verz),
      ],
      child: const MaterialApp(home: VerzamelingPagina(naam: 'Jazzzangers')),
    ));
    await tester.pump();
    expect(find.text('Meer Jazzzangers'), findsOneWidget);
    await tester.tap(find.text('Meer Jazzzangers'));
    await tester.pump();
    // De voorraad kwam uit de echte wereld (runAsync): daar komt ook het antwoord binnen.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.text('The Look of Love'), findsOneWidget);
    expect(find.text('Stacey Kent'), findsOneWidget);
    expect(find.textContaining('Een tik start een radio erbinnen'), findsOneWidget);
    // De hoezen (zonder adres) en de knoppen laten uitlopen.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  test('aangesloten: de gsm houdt een verzameling bij zoals een afspeellijst, en hernoemen en opheffen gaan mee', () {
    final m = _bron('lib/main.dart');
    expect(m, contains("            if (id.startsWith('verz:'))\n"
        '              redenLijst(id): switch (verzamelingVanLijstId(id, alleVerzamelingNamen(library, verzamelingen))) {'));
    expect(m, contains('    verzamelingen.addListener(houdBij);'));
    expect(m, contains('                if (lib.isRemote && !isTv) _VerzamelingOpToestel(naam: _naam, nummers: nummers),'));
    expect(m, contains('      await toestelRedenen.zetLijst(verzamelingLijstId(schoon), true);'));
    expect(m, contains('    await toestelRedenen.zetLijst(verzamelingLijstId(_naam), false);\n    if (mounted) nav.pop();'));
    expect(m, contains("                  if (nummers.isNotEmpty) (_VerzamelingTab.meer, 'Meer \$_naam'),"));
    expect(m, contains('                        onTap: () => unawaited(startRadio(context, t.artist,\n'
        '                            titel: t.title, seconden: t.seconds > 0 ? t.seconds : null, verzameling: widget.naam)),'));
  });
}

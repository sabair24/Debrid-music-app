/// Gelijk volume op Nu speelt: het merk past, zegt in elke toestand iets begrijpelijks, en de
/// eenmalige aankondiging gedraagt zich.
///
/// **Waarom dit bestaat.** Saber is kritisch en merkt het als iets zachter klinkt. Een kaal "−3,4 dB"
/// naast "FLAC · 24/96" leest als verlies; een merk dat de artiestnaam van een telefoonscherm drukt is
/// precies de regressie waartegen nu_speelt_namen_test.dart bestaat; en een aankondiging die "zet je
/// volume een stap hoger" zegt bij een nummer dat juist OMHOOG gaat, is fout. Getoetst op de widgets
/// zelf (NuSpeeltNaamrij, LuidheidMerk), want Nu speelt is zonder libmpv niet te bouwen.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:debridmusic/library.dart';
import 'package:debridmusic/luidheid.dart';
import 'package:debridmusic/luidheid_keuze.dart';
import 'package:debridmusic/main.dart' show ArtistNames;
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/ui/speelvlak.dart';

const drie = ['At The Villa People', 'Etienne Vandewiele', 'Bruno Quatresous'];

/// Zoals `_qualityBadge` in main.dart: marge 8+8, binnenruimte 7+7, 11 pt.
Widget _badge(String s) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(border: Border.all(color: Colors.amber), borderRadius: BorderRadius.circular(6)),
      child: Text(s, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
    );

Widget _echt() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 8),
    child: Text('tot 17,2 kHz', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)));

/// Met het ECHTE lettertype van de app. Het toetslettertype tekent elk teken als een blokje van de
/// volle hoogte en meet daardoor ~2× te breed; daarmee liep zelfs de oude naamrij (zonder merk) al
/// 7,3 punt over op 320 punt. Met Inter meet de toets wat het scherm doet.
Widget _vak(Widget kind, {required double breedte, double schaal = 1}) => MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryStore>(create: (_) => LibraryStore()),
        ChangeNotifierProvider<AppSettings>(create: (_) => AppSettings()),
      ],
      child: MaterialApp(
        theme: ThemeData(fontFamily: 'Inter'),
        home: MediaQuery(
          data: MediaQueryData(size: const Size(1200, 900), textScaler: TextScaler.linear(schaal)),
          child: Scaffold(body: Center(child: SizedBox(width: breedte, child: kind))),
        ),
      ),
    );

String get _langste {
  final alle = alleLuidheidMerkTeksten();
  return alle.reduce((a, b) => a.length >= b.length ? a : b);
}

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      inter.addFont(Future.value(ByteData.sublistView(File('fonts/Inter-$w.ttf').readAsBytesSync())));
    }
    await inter.load();
  });

  group('het merk past', () {
    testWidgets('DE KERN: telefoon staand (320 punt) — eigen regel, de namen blijven even breed', (tester) async {
      expect(merkEigenRegel(kolom: 320, tv: false), isTrue);
      NuSpeeltNaamrij rij(Widget? merk) => NuSpeeltNaamrij(
            zij: false,
            merkInDeRij: !merkEigenRegel(kolom: 320, tv: false),
            naam: const ArtistNames(names: drie, style: TextStyle(fontSize: 15), omvouwen: true),
            echtheid: _echt(),
            kwaliteit: _badge('FLAC · 24/192'),
            merk: merk,
          );
      await tester.pumpWidget(_vak(rij(null), breedte: 320));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'de oude rij hoort met het echte lettertype te passen');
      final zonder = tester.getSize(find.byType(ArtistNames)).width;

      await tester.pumpWidget(_vak(rij(LuidheidMerk(tekst: _langste, onPressed: () {})), breedte: 320));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'een overloop knipt in een release stil de artiest weg');
      expect(find.text(drie.first), findsOneWidget);
      expect(tester.getSize(find.byType(ArtistNames)).width, zonder,
          reason: 'het merk op zijn eigen regel mag de artiestnaam geen punt smaller maken');
    });

    testWidgets('DE KERN: tv (540 punt, tekst 1,35×) — merk in de rij, zonder overloop', (tester) async {
      expect(merkEigenRegel(kolom: 540, tv: true), isFalse, reason: 'de hoogte op de Shield is krap tot op de punt');
      final kort = alleLuidheidMerkTeksten(kort: true).reduce((a, b) => a.length >= b.length ? a : b);
      await tester.pumpWidget(_vak(
        NuSpeeltNaamrij(
          zij: false,
          merkInDeRij: true,
          naam: const ArtistNames(names: drie, style: TextStyle(fontSize: 15), omvouwen: true),
          echtheid: _echt(),
          kwaliteit: _badge('FLAC · 24/192'),
          merk: LuidheidMerk(tekst: kort, onPressed: () {}),
        ),
        breedte: 540,
        schaal: 1.35,
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(ArtistNames)).width, greaterThan(100));
    });

    testWidgets('DE GRENS: zonder merk (stand Uit) is de rij precies de oude rij', (tester) async {
      await tester.pumpWidget(_vak(
        NuSpeeltNaamrij(
          zij: true,
          merkInDeRij: false,
          naam: const Text('Artiest'),
          kwaliteit: _badge('FLAC · 16/44.1'),
        ),
        breedte: 320,
      ));
      expect(find.byType(Column), findsNothing, reason: 'geen merk, geen extra regel');
    });

    test('DE GRENS: een breed scherm houdt het merk in de rij', () {
      expect(merkEigenRegel(kolom: 520, tv: false), isFalse);
      expect(merkEigenRegel(kolom: 328, tv: false), isTrue);
    });
  });

  group('de teksten', () {
    test('DE KERN: elke toestand zegt iets, met een woord erbij', () {
      String tekst(Bijstelbron b, {double db = -3.4, bool album = false, bool her = false}) =>
          luidheidMerkTekst(Bijstelling(db, b, alsAlbum: album, netBewerkt: her));
      expect(tekst(Bijstelbron.nummer), 'Gelijk −3,4 dB');
      expect(tekst(Bijstelbron.nummer, db: 2.1), 'Gelijk +2,1 dB');
      expect(tekst(Bijstelbron.album, album: true), 'Album −3,4 dB');
      expect(tekst(Bijstelbron.opDoel, db: 0), 'Gelijk ±0 dB');
      expect(tekst(Bijstelbron.klemNul, db: 0), 'Gelijk · ongemoeid');
      expect(tekst(Bijstelbron.klemNul, db: 0, album: true), 'Album · ongemoeid',
          reason: 'midden in een plaat hoort er geen "Gelijk" te staan');
      expect(tekst(Bijstelbron.klemExtra, db: -2.9, album: true), 'Album −2,9 dB',
          reason: 'de klem die extra verlaagt toont het getal, niet "ongemoeid"');
      expect(tekst(Bijstelbron.geenRuimte, db: 0), 'Gelijk · zacht opgenomen');
      expect(tekst(Bijstelbron.ongemeten, db: 0), 'Gelijk · nog niet gemeten');
      expect(tekst(Bijstelbron.ongemeten, db: 0, her: true), 'Gelijk · net bewerkt');
      expect(tekst(Bijstelbron.meerkanaals, db: 0), 'Gelijk · meerkanaals, ongemoeid');
      expect(tekst(Bijstelbron.online, db: 0), 'Gelijk · niet gemeten (online)');
      expect(tekst(Bijstelbron.onbekendAdres, db: 0), 'Gelijk · niet toegepast');
      expect(tekst(Bijstelbron.mpvWeigert, db: 0), 'Gelijk · werkt hier niet');
      expect(tekst(Bijstelbron.pcNietKlaar, db: 0), 'Gelijk · pc meet nog');
      expect(luidheidMerkTekst(const Bijstelling(0, Bijstelbron.pcNietKlaar), opPc: true, voortgang: 'meten… 40 van 100'),
          'Gelijk · meten… 40 van 100');
      expect(luidheidMerkTekst(const Bijstelling(-3.4, Bijstelbron.nummer), speaker: true),
          'Gelijk · niet op deze speaker');
      expect(luidheidMerkTekst(const Bijstelling(0, Bijstelbron.shield)), 'Gelijk · op de Shield',
          reason: 'de Shield rekent met de stand van de pc; een getal van hier kon een ander zijn');
      expect(tekst(Bijstelbron.pcOud, db: 0), 'Gelijk · werk je pc bij',
          reason: '"pc meet nog" bij een pc die nooit gaat meten is een belofte die niet uitkomt');
      expect(tekst(Bijstelbron.pcZonderFfmpeg, db: 0), 'Gelijk · pc mist ffmpeg');
      expect(luidheidMerkTekst(const Bijstelling(0, Bijstelbron.pcZonderFfmpeg), opPc: true), 'Gelijk · ffmpeg ontbreekt');
      expect(luidheidMerkTekst(Bijstelling.nul), '', reason: 'bij Uit staat er niets');
    });

    test('DE KERN: het blad legt de klem in gewone taal uit, zonder het woord "klem"', () {
      final nul = luidheidUitleg(const Bijstelling(0, Bijstelbron.klemNul,
          meting: Luidheidsmeting(lufs: -13, piek: 2.0)));
      expect(nul, contains('pieken boven 0 dB'));
      expect(nul.toLowerCase(), isNot(contains('klem')));
      final extra = luidheidUitleg(const Bijstelling(-2.9, Bijstelbron.klemExtra, alsAlbum: true, albumDb: -1.5));
      expect(extra, contains('1,4 dB zachter dan de rest van de plaat'));
      expect(extra, isNot(contains('+')), reason: '"+1,4 dB zachter" leest tegenstrijdig');
      expect(luidheidUitleg(const Bijstelling(0, Bijstelbron.ongemeten, netBewerkt: true)),
          contains('wordt zo opnieuw gemeten'));
      expect(luidheidUitleg(const Bijstelling(0, Bijstelbron.shield)), contains('niet die van dit toestel'));
      expect(luidheidUitleg(const Bijstelling(0, Bijstelbron.shield), opPc: true),
          contains('Een wijziging hier geldt de volgende keer dat je naar de Shield cast'));
      expect(luidheidUitleg(const Bijstelling(-3, Bijstelbron.nummer, vanZender: true)),
          contains('De stand komt van je pc'));
      expect(luidheidUitleg(const Bijstelling(-3, Bijstelbron.nummer, verzamelaar: true)),
          contains('Verzamelalbum — elk nummer apart.'));
      expect(luidheidUitleg(const Bijstelling(0, Bijstelbron.pcOud)), contains('werk hem bij'));
      expect(luidheidUitleg(const Bijstelling(0, Bijstelbron.pcOud)), isNot(contains('meet je bibliotheek nog')));
    });

    test('DE GRENS: de aankondiging spreekt alleen over zachter', () {
      expect(luidheidAankondigingTekst(-6.2), contains('6,2 dB zachter'));
      expect(luidheidAankondigingTekst(-6.2), contains('Zet je volume een stap hoger'));
    });

    test('DE GRENS: de status op een toestel zegt waarom er (nog) niets gebeurt', () {
      expect(luidheidStatusTekst(eigenaar: false, vanPc: null), 'Je pc doet nog niet mee — werk hem bij.');
      expect(luidheidStatusTekst(eigenaar: true, ffmpeg: false), startsWith('ffmpeg ontbreekt'));
      expect(luidheidStatusTekst(eigenaar: false, werktNiet: true), contains('speler te oud'));
    });
  });

  group('het blad', () {
    Future<void> open(WidgetTester tester, Bijstelling b) async {
      final settings = AppSettings();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => toonLuidheidBlad(context, b: b, settings: settings),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('DE KERN: bij een eigen nummer staan de keuzes erin — de A/B-knop', (tester) async {
      await open(tester, const Bijstelling(-3, Bijstelbron.nummer));
      expect(find.byType(ChoiceChip), findsNWidgets(3));
    });

    testWidgets('DE VAL: op de Shield bij een nummer van de pc geen keuzes die niets doen', (tester) async {
      await open(tester, const Bijstelling(-3, Bijstelbron.nummer, vanZender: true));
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.textContaining('De stand komt van je pc'), findsOneWidget);
    });
  });

  group('de aankondiging', () {
    Future<({List<String> gebeurd})> toon(WidgetTester tester, {required bool voorgrond, bool luiderAl = false}) async {
      final gebeurd = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => toonLuidheidAankondiging(
                context,
                db: -6.2,
                onLuider: luiderAl ? null : () => gebeurd.add('luider'),
                onUit: () => gebeurd.add('uit'),
                opGezien: () => gebeurd.add('gezien'),
                telAfloop: () => voorgrond,
              ),
              child: const Text('nu'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('nu'));
      // De SnackBar schuift eerst in beeld; pas daarna staan de knoppen waar ze horen, en pas dan
      // begint zijn klok van twintig seconden.
      await tester.pumpAndSettle();
      return (gebeurd: gebeurd);
    }

    testWidgets('DE KERN: drie knoppen, en Luider zet Luider aan', (tester) async {
      final r = await toon(tester, voorgrond: true);
      expect(find.textContaining('6,2 dB zachter'), findsOneWidget);
      expect(find.text('Luider'), findsOneWidget);
      expect(find.text('Uit'), findsOneWidget);
      expect(find.text('Oké'), findsOneWidget);
      await tester.tap(find.text('Luider'));
      await tester.pumpAndSettle();
      expect(r.gebeurd, ['luider', 'gezien']);
    });

    testWidgets('DE VAL: aflopen telt niet als de app niet op de voorgrond stond', (tester) async {
      final r = await toon(tester, voorgrond: false);
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();
      expect(find.textContaining('6,2 dB zachter'), findsNothing, reason: 'hij is wel weg');
      expect(r.gebeurd, isEmpty, reason: 'niet gezien → de volgende keer opnieuw');
    });

    testWidgets('DE VAL: wegvegen telt als gezien — anders komt hij bij elke keer Nu speelt terug', (tester) async {
      final r = await toon(tester, voorgrond: false);
      // Een zwevende SnackBar veegt je naar beneden weg (SnackBar.dismissDirection).
      await tester.fling(find.textContaining('6,2 dB zachter'), const Offset(0, 300), 2000);
      await tester.pumpAndSettle();
      expect(find.textContaining('6,2 dB zachter'), findsNothing);
      expect(r.gebeurd, ['gezien']);
    });

    testWidgets('DE GRENS: staat Luider al aan, dan is er geen Luider-knop', (tester) async {
      await toon(tester, voorgrond: true, luiderAl: true);
      expect(find.text('Luider'), findsNothing);
      expect(find.text('Uit'), findsOneWidget);
      expect(find.text('Oké'), findsOneWidget);
    });

    testWidgets('DE GRENS: aflopen op de voorgrond telt als gezien', (tester) async {
      final r = await toon(tester, voorgrond: true);
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();
      expect(r.gebeurd, ['gezien']);
    });

    test('DE GRENS: Nu speelt kondigt alleen een verlaging aan, en niet op de tv', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      final begin = main.indexOf('void _misschienAankondigen(PlayerStore p) {');
      expect(begin, isNonNegative);
      final lijf = main.substring(begin, main.indexOf('\n  }\n', begin));
      expect(lijf, contains('if (_aankondigingGedaan || isTv) return;'));
      expect(lijf, contains('b.db >= 0) return;'), reason: 'een ophoging is geen reden om de volumeknop aan te raken');
      expect(lijf, contains('settings.luidheidUitgelegd'));
      expect(lijf, contains('onLuider: luidheidsstandUit(settings.luidheid) == Luidheidsstand.luid'),
          reason: 'bij Luider geen knop die niets doet');
    });

    test('DE VAL: gecast naar de Shield toont het merk geen getal van dit toestel', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      final begin = main.indexOf('Widget _luidheidMerk(');
      expect(begin, isNonNegative);
      final lijf = main.substring(begin, main.indexOf('\n}\n', begin));
      expect(lijf, contains('? const Bijstelling(0, Bijstelbron.shield)'));
      expect(lijf, contains('if (eigenUit && !shield && !b.vanZender) return const SizedBox.shrink();'),
          reason: 'een Shield die zelf op Uit staat speelt een gecast nummer met de stand van de pc; '
              'zonder merk werd het dan zachter zonder te zien waarom');
      expect(lijf.indexOf('eigenUit &&'), greaterThan(lijf.indexOf('final b = shield')));
      expect(lijf, isNot(contains('luidheidVoor')),
          reason: 'met de stand van dít toestel en per nummer: een ander getal dan wat de tv speelt');
    });

    test('DE GRENS: de instelling op de tv zegt dat casts de pc volgen', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      final begin = main.indexOf('class _LuidheidSectie');
      expect(main.substring(begin, main.indexOf('\n}\n', begin)), contains('isTv ?'));
      expect(main.substring(begin, main.indexOf('\n}\n', begin)), contains('kLuidheidOpDeShield'));
      expect(kLuidheidOpDeShield, contains('volgt de instelling van de pc'));
    });

    test('DE GRENS: op de tv staat het merk in de naamrij, en de aankondiging is geen kind van de kolom', () {
      final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(main, contains('merkInDeRij: !merkEigenRegel(kolom: kolom, tv: isTv),'));
      // De aankondiging is een overlay (SnackBar) en wordt alleen na het tekenen getoond, nooit als
      // regel in de kolom: precies één aanroep, binnen een post-frame-callback.
      expect('toonLuidheidAankondiging('.allMatches(main).length, 1);
      final aanroep = main.indexOf('toonLuidheidAankondiging(');
      expect(main.lastIndexOf('addPostFrameCallback', aanroep), greaterThan(main.lastIndexOf('void _misschienAankondigen', aanroep)));
    });
  });
}

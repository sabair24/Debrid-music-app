/// Kiezen en bijhouden (Saber, 28-10-2026): "ik moet kunnen opslaan op men gsm vanaf tracks, kunnen selecteren",
/// en in één keer afspeellijsten, favorieten, een hele artiest en zoekresultaten. Haal je iets uit een favoriet of
/// lijst, dan "vanzelf weg" — tenzij het er ook om een andere reden staat.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/offline.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/toestel_bijhouden.dart';
import 'package:debridmusic/toestel_redenen.dart';
import 'package:debridmusic/ui/nummerkeuze.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

Track _t(String pad) => Track(path: pad, title: pad, artist: 'Artiest', album: 'Album');

void main() {
  late Directory map;
  setUp(() {
    map = Directory.systemTemp.createTempSync('dm_kiezen_');
    setAppDirForTest(map.path);
  });
  tearDown(() {
    try {
      map.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows houdt soms nog even een greep vast.
    }
  });

  group('kiezen', () {
    test('lang drukken begint, tikken wisselt, alles kiezen kiest de lijst (of alles weer uit), stoppen wist', () {
      final k = NummerKeuze();
      final lijst = [_t('a'), _t('b'), _t('c')];
      k.begin(lijst[0], alles: () => lijst);
      expect(k.actief, isTrue);
      expect(k.aantal, 1);
      k.wissel(lijst[1]);
      expect(k.isGekozen('b'), isTrue);
      k.wissel(lijst[1]);
      expect(k.isGekozen('b'), isFalse);
      k.kiesAlles();
      expect(k.aantal, 3, reason: 'de zoekresultaten van Tracks, of de nummers van het album');
      k.kiesAlles();
      expect(k.aantal, 0, reason: 'alles al aan: dan alles weer uit');
      k.stop();
      expect(k.actief, isFalse);
      expect(k.kanAllesKiezen, isFalse);
    });
  });

  group('redenen', () {
    test('pas weg als er geen reden meer is; wat er al stond (zonder reden) was zelf bewaard', () async {
      final r = ToestelRedenen();
      await r.voegToe(['a'], kRedenFavoriet);
      await r.voegToe(['a'], redenLijst('feest'));
      expect(await r.haalWeg(['a'], kRedenFavoriet), isEmpty, reason: 'nog in de lijst');
      expect(await r.haalWeg(['a'], redenLijst('feest')), ['a']);
      // Al op het toestel zonder reden: een hartje erop en eraf neemt hem niet mee.
      await r.voegToe(['oud'], kRedenFavoriet, alOpToestel: (_) => true);
      expect(r.redenenVan('oud'), {kRedenZelf, kRedenFavoriet});
      expect(await r.haalWeg(['oud'], kRedenFavoriet), isEmpty);
      // Een pad dat hier nooit stond, blijft: dat was zelf bewaard.
      expect(await r.haalWeg(['onbekend'], kRedenFavoriet), isEmpty);
    });

    test('overleeft een herstart, met de lijsten die je op dit toestel houdt', () async {
      final r = ToestelRedenen();
      await r.voegToe(['a', 'b'], kRedenZelf);
      await r.zetLijst('feest', true);
      final weer = ToestelRedenen();
      await weer.laad();
      expect(weer.redenenVan('a'), {kRedenZelf});
      expect(weer.houdtLijst('feest'), isTrue);
    });
  });

  group('bijhouden', () {
    Future<OfflineStore> toestelMet(List<String> paden) async {
      final bestanden = [
        for (final p in paden) File('${map.path}${Platform.pathSeparator}$p.flac')..writeAsBytesSync([1]),
      ];
      File('${map.path}${Platform.pathSeparator}offline.json').writeAsStringSync(jsonEncode([
        for (var i = 0; i < paden.length; i++)
          {'path': paden[i], 'file': bestanden[i].path, 'bytes': 1, 'title': paden[i], 'artist': 'A', 'album': 'B'},
      ]));
      final o = OfflineStore()..magOphalen = () => false; // de rij blijft staan: dit gaat over wat erin komt
      await o.load();
      return o;
    }

    test('een nieuwe favoriet gaat in de rij, een weggehaalde gaat van het toestel', () async {
      final o = await toestelMet(['fav']);
      final r = ToestelRedenen();
      // De eerste ronde: "fav" staat er al (zelf bewaard), "nieuw" komt erbij.
      var uit = await houdLijstenBij(redenen: r, offline: o, gewenst: {kRedenFavoriet: [_t('fav'), _t('nieuw')]});
      expect(uit.erbij, 1);
      expect(o.wachtend, 1, reason: '"nieuw" wacht in de rij (op wifi)');
      expect(r.redenenVan('fav'), {kRedenZelf, kRedenFavoriet});
      // Het hartje eraf: "fav" blijft (zelf bewaard), "nieuw" gaat weg.
      uit = await houdLijstenBij(redenen: r, offline: o, gewenst: {kRedenFavoriet: []});
      expect(o.has('fav'), isTrue, reason: 'zelf bewaard, dus niet vanzelf weg');
      expect(r.redenenVan('nieuw'), isEmpty);
    });

    test('een lijst die je niet meer op dit toestel houdt, neemt zijn nummers mee', () async {
      final o = await toestelMet(['l1', 'l2']);
      final r = ToestelRedenen();
      await r.voegToe(['l1', 'l2'], redenLijst('feest'));
      final uit = await houdLijstenBij(redenen: r, offline: o, gewenst: {kRedenFavoriet: []});
      expect(uit.weg, 2);
      expect(o.has('l1'), isFalse);
      expect(o.has('l2'), isFalse);
    });
  });

  test('aangesloten: kiezen in Tracks en op een album, de balk, TERUG, en het bijhouden wacht op de pc', () {
    final main = _bron('lib/main.dart');
    expect(main, contains('onTap: () => nummerKeuze.actief ? nummerKeuze.wissel(t) : speelGetikt(context, tracks, i),'));
    expect(main, contains(': (_isTouch ? () => nummerKeuze.begin(t, alles: () => tracks) : null),'));
    expect(main, contains(': (_isTouch ? () => nummerKeuze.begin(t, alles: () => widget.queue) : null),'));
    expect(main, contains('              child: const _NummerKeuzeBalk(),\n'));
    expect(main, contains('        if (nummerKeuze.actief) {\n          nummerKeuze.stop();\n          return;\n        }'),
        reason: 'TERUG stopt eerst het kiezen');
    expect(main, contains('canPop: !nummerKeuze.actief && terugVanaf('));
    expect(main, contains('        if (library.tracks.isEmpty || !favorieten.gehoord || !lijsten.gehoord) return;\n'),
        reason: 'anders lijkt elke favoriet verdwenen en gaat alles van je gsm');
    expect(main, contains("key: const ValueKey('lijst-op-toestel'),"));
    expect(main, contains("key: const ValueKey('artiest-op-toestel'),"));
    expect(main, contains('  Future<void> _fetch() => _zetOpToestel(context, widget.album.tracks, album: widget.album.title);\n'));
  });

  test('aangesloten: elke knop die op dit toestel zet, vraagt eerst met de grootte en de vrije ruimte', () {
    final main = _bron('lib/main.dart');
    expect(main, contains('    if (!await _zetOpToestel(context, nummers)) return;\n'), reason: 'de keuzebalk');
    expect(main, contains('                          if (!await _zetOpToestel(context, nummers)) return;\n'),
        reason: 'de artiestpagina');
    expect(main, contains('                    } else if (!await _magOpToestel(context, nummers)) {\n'), reason: 'een afspeellijst');
    expect(main, contains('  await toestelRedenen.voegToe([for (final t in nummers) t.path], kRedenZelf);\n'));
    expect(main, contains('  if (!await _magOpToestel(context, nummers)) return false;\n'),
        reason: 'de vraag komt vóór de reden en de rij');
    expect(main, contains("  final bytes = geschatteOmvang(komen, cd: context.read<AppSettings>().offlineKwaliteit == 'cd');\n"),
        reason: 'dezelfde regel als offline.adresVoor');
    expect(RegExp(r'offline\.bewaarAlles\(\[').allMatches(main).length, 1,
        reason: 'alleen _zetOpToestel zet nog zelf in de rij — een nieuwe knop die het zelf doet, slaat de vraag over');
  });
}

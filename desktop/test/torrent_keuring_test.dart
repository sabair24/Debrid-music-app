/// Een torrent komt eerst in de keuringsmap, en pas wat de keuring doorstaat gaat de bibliotheek in.
///
/// De klacht van 29-09-2026, bij Blood On The Dance Floor: *"ik kon zweren, dat ik alle liedjes in beste
/// kwaliteit had … en nu staan er een paar afgekapt en in mindere kwaliteit"*, en daarna: *"kunnen we niet
/// downloaden virtueel zeg maar voor dat het op de pc bibliotheek wordt gezet, zodanig dat er eerst een
/// controle is voor het goedgekeurd wordt, en dit door heel de app."*
///
/// Tot die dag schreef een torrent in `DebridMusic Downloads\<torrent>\`, een map die de bibliotheek
/// inleest: een afgekapte FLAC stond er dus in zodra hij binnen was, en pas daarna werd er vergeleken —
/// waarbij de torrent als "jouw keuze" ook nog van alles won. Nu wacht hij in `_keuring`, en:
///
///  * kapot → `_dubbel`, niet de bibliotheek in;
///  * niet bewezen beter dan wat er ligt → `_dubbel`, en wat je had blijft staan;
///  * wat heel is maar niet op te bergen → terug naar de zichtbare map, zoals vroeger.
library;

import 'dart:io';

import 'package:debridmusic/audioformaten.dart' show kMinimumBytes;
import 'package:debridmusic/ffmpeg.dart';
import 'package:debridmusic/integriteit.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/organize.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/vaste_keuze.dart';
import 'package:flutter_test/flutter_test.dart';

import 'place_file_test.dart' show buildFlac;

void main() {
  final sep = Platform.pathSeparator;
  late Directory wortel;
  late String downloads;

  setUp(() {
    wortel = Directory.systemTemp.createTempSync('dm_torrentkeuring_');
    setAppDirForTest('${wortel.path}${sep}app');
    Directory('${wortel.path}${sep}app').createSync();
    resetIntegriteitVoorTest();
    resetVasteKeuzesForTest();
    downloads = '${wortel.path}${sep}DebridMusic Downloads';
  });

  tearDown(() {
    resetIntegriteitVoorTest();
    resetVasteKeuzesForTest();
    try {
      wortel.deleteSync(recursive: true);
    } catch (_) {}
  });

  String keuring(String torrent) => '$downloads$sep$keuringMap$sep$torrent';

  File leg(String map, String naam, List<int> bytes) {
    final f = File('$map$sep$naam');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes);
    return f;
  }

  List<String> alles(String map) => Directory(map).existsSync()
      ? [
          for (final e in Directory(map).listSync(recursive: true))
            if (e is File) e.path.substring(map.length + 1),
        ]
      : const [];

  List<int> flac(String titel, {int nr = 1, int seconden = 200}) => buildFlac(
      ['TITLE=$titel', 'ARTIST=Michael Jackson', 'ALBUM=Blood On The Dance Floor', 'TRACKNUMBER=$nr'],
      seconds: seconden);

  group('opbergen met een keuring', () {
    test('DE KERN: wat de keuring tegenhoudt gaat naar _dubbel, niet de bibliotheek in', () async {
      final kapot = leg(keuring('BOTDF'), '05 - Is It Scary.flac', flac('Is It Scary', nr: 5));
      leg(keuring('BOTDF'), '06 - Scream Louder.flac', flac('Scream Louder', nr: 6));

      final r = await bergMapOp(keuring('BOTDF'), downloads,
          keur: (f) async => f.path == kapot.path ? 'kapot bestand (afgekapt)' : null);

      expect(r.afgekeurd, 1);
      expect(r.moved, 1);
      expect(r.tegengehouden, {kapot.path});
      expect(r.uitkomst[kapot.path], contains('kapot bestand (afgekapt)'));
      expect(r.uitkomst[kapot.path], contains('niet in je bibliotheek'),
          reason: 'de downloadlijst moet zeggen dat hij er NIET in staat');
      // In een eigen submap: wat de keuring afkeurde was nooit van jou, en hoort niet tussen wat er
      // ooit vervangen werd (zie [parkeerAfgekeurd]).
      expect(alles('$downloads$sep$parkeerMap'), ['$parkeerAfgekeurd${sep}05 - Is It Scary.flac']);
      final gefiled = alles('$downloads${sep}Albums');
      expect(gefiled.single, endsWith('Scream Louder.flac'));
      expect(gefiled.where((p) => p.contains('Is It Scary')), isEmpty,
          reason: 'precies zo stond een afgekapte FLAC in je bibliotheek');
    });

    test('DE VAL: een map ÍN de keuringsmap wordt wél opgeborgen', () async {
      // De regel die de werkmappen van de app overslaat keek naar het hele pad. Met de torrent in
      // `_keuring` telde dan élk bestand als werkmap, en kwam er nooit iets uit: "0 verplaatst".
      leg(keuring('BOTDF'), '06 - Scream Louder.flac', flac('Scream Louder', nr: 6));
      final r = await bergMapOp(keuring('BOTDF'), downloads);
      expect(r.moved, 1, reason: 'anders blijft elke torrent onzichtbaar in de keuringsmap staan');
      expect(alles(keuring('BOTDF')), isEmpty);
    });

    test('DE GRENS: "Opruimen" over de hele downloadmap laat de keuringsmap met rust', () async {
      final wacht = leg(keuring('BOTDF'), '06 - Scream Louder.flac', flac('Scream Louder', nr: 6));
      leg('$downloads${sep}los', 'Earth Song.flac', flac('Earth Song', nr: 3));
      final r = await tidyDownloads(downloads);
      expect(r.moved, 1, reason: 'het losse bestand wel');
      expect(wacht.existsSync(), isTrue, reason: 'wat nog gekeurd moet worden, niet');
    });

    test('een keuring die zelf omvalt houdt niets tegen', () async {
      leg(keuring('BOTDF'), '06 - Scream Louder.flac', flac('Scream Louder', nr: 6));
      final r = await bergMapOp(keuring('BOTDF'), downloads, keur: (f) async => throw 'ffmpeg weg');
      expect(r.afgekeurd, 0);
      expect(r.moved, 1, reason: 'niet weten is niet afkeuren');
    });

    test('elke uitkomst krijgt een zin, zodat "Klaar" niet alles tegelijk betekent', () async {
      final nieuw = leg(keuring('BOTDF'), '06 - Scream Louder.flac', flac('Scream Louder', nr: 6));
      final r = await bergMapOp(keuring('BOTDF'), downloads);
      expect(r.uitkomst[nieuw.path], 'opgeborgen in je bibliotheek');

      // Nog eens hetzelfde nummer, even goed: gelijk is geen winst, dus deze gaat opzij.
      final nogEens = leg(keuring('BOTDF2'), '06 - Scream Louder.flac', flac('Scream Louder', nr: 6));
      final r2 = await bergMapOp(keuring('BOTDF2'), downloads);
      expect(r2.duplicates, 1);
      expect(r2.uitkomst[nogEens.path], contains('minstens even goede kwaliteit'));

      // Een mp3 waar niets uit te lezen valt: dan weet niemand waar hij heen moet.
      final onleesbaar = leg(keuring('BOTDF3'), 'track.mp3', List<int>.filled(4000, 0));
      final r3 = await bergMapOp(keuring('BOTDF3'), downloads);
      expect(r3.skipped, 1);
      expect(r3.uitkomst[onleesbaar.path], contains('niet op te bergen'));
    });
  });

  test('de scanner leest de keuringsmap niet', () async {
    // Opgevuld tot boven [kMinimumBytes]: een kop zonder muziek slaat de scanner terecht over.
    final vulling = List<int>.filled(kMinimumBytes + 1000, 0);
    leg(keuring('BOTDF'), '05 - Is It Scary.flac', [...flac('Is It Scary', nr: 5), ...vulling]);
    leg('$downloads${sep}Albums', '06 - Scream Louder.flac', [...flac('Scream Louder', nr: 6), ...vulling]);
    final uit = await scanTagsInIsolate(wortel.path, null);
    final titels = [for (final r in uit.rijen) r['title']];
    expect(titels, ['Scream Louder'], reason: 'wat nog gekeurd wordt hoort niet in je bibliotheek te staan');
  });

  group('de downloadmotor sluit het aan', () {
    // De torrentweg zelf zit tussen TorBox, aria2 en het netwerk en is niet los te draaien. Deze
    // toetsen kijken naar de brontekst, zodat een verhuizing de keuring niet stil kan laten verdwijnen.
    final bron = File('lib/online.dart').readAsStringSync().replaceAll('\r\n', '\n');
    String lijf(String kop) {
      final i = bron.indexOf(kop);
      expect(i, greaterThan(0), reason: '$kop is weg');
      return bron.substring(i, bron.indexOf('\n  }\n', i));
    }

    test('DE KERN: een torrent komt binnen in de keuringsmap, niet in een map die de bibliotheek leest', () {
      final e = lijf('  void enqueue(SearchResult result');
      expect(e, contains(r'$keuringMap${Platform.pathSeparator}$naamMap'));
      expect(e, isNot(contains(r"DebridMusic Downloads${Platform.pathSeparator}${_sanitize(torrent.name)}")),
          reason: 'zo stond het tot 29-09-2026, en toen stond een afgekapte FLAC meteen in je bibliotheek');
    });

    test('DE KERN: het opbergen keurt elk bestand', () {
      expect(lijf('  Future<TidyReport?> _bergTorrentOp('), contains('keur: _keurVoorBibliotheek'));
      final k = lijf('  Future<String?> _keurVoorBibliotheek(');
      expect(k, contains('controleerHeel(f.path)'), reason: 'de decodeerproef op de binnenkomer');
      expect(k, contains('controleerHeel(bestaand)'),
          reason: 'en op wat er ligt: een kapotte eigen kopie hoort te verliezen, maar dat moet bekend zijn');
    });

    test('DE VAL: TorBox schrijft in een .part, en pas heel krijgt hij zijn naam', () {
      final d = lijf('  Future<void> _download(int torrentId');
      final schrijf = d.indexOf('part.openWrite()');
      final hernoem = d.indexOf('await part.rename(dest.path)');
      expect(schrijf, greaterThan(0));
      expect(hernoem, greaterThan(d.indexOf("throw 'incompleet")),
          reason: 'hernoemen vóór de lengtecheck zou een half bestand een hele naam geven');
    });

    test('DE VAL: klaar is pas klaar na de keuring', () {
      // "Klaar" zette de download zelf, vóór er iets gekeurd was.
      expect(lijf('  Future<void> _download(int torrentId'), isNot(contains("job.status = 'done'")));
      expect(bron, contains("j.status = (u != null && u.afgekeurd)"));
    });

    test('bij het opstarten wordt een achtergebleven keuring afgemaakt', () {
      final main = File('lib/main.dart').readAsStringSync();
      final koppel = main.indexOf('downloads.mapVanBestaande = library.fileOfRecording;');
      final hervat = main.indexOf('downloads.hervatKeuring()');
      expect(koppel, greaterThan(0));
      expect(hervat, greaterThan(koppel), reason: 'de keuring vraagt de bibliotheek wat er al ligt');
    });
  });

  group('een achtergebleven torrent, echt gekeurd', () {
    final ffmpeg = Ffmpeg().pad;
    final zonder = ffmpeg == null ? 'geen ffmpeg op deze machine' : false;

    Future<File> echt(String map, String naam, String titel, {int nr = 1}) async {
      final f = File('$map$sep$naam');
      f.parent.createSync(recursive: true);
      final r = await Process.run(ffmpeg!, [
        '-nostdin', '-v', 'error', '-f', 'lavfi', '-i', 'anoisesrc=d=12:c=pink:r=44100:a=0.3:seed=$nr',
        '-metadata', 'title=$titel', '-metadata', 'artist=Michael Jackson',
        '-metadata', 'album=Blood On The Dance Floor', '-metadata', 'track=$nr',
        '-c:a', 'flac', f.path,
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      return f;
    }

    void kap(File f) {
      final b = f.readAsBytesSync();
      f.writeAsBytesSync(b.sublist(0, b.length * 4 ~/ 10));
    }

    DownloadManager manager({String? Function(String a, String t, {int? seconds, String? nietIn})? bestaat}) {
      final cfg = AppSettings()
        ..soulseekUser = 'toets'
        ..soulseekPass = 'toets';
      return DownloadManager(OnlineService(cfg), SoulseekService(cfg), wortel.path, () async {})
        ..mapVanBestaande = bestaat;
    }

    test('DE KERN: kapot naar _dubbel, heel naar zijn plek, half weg, de rest weer zichtbaar', () async {
      final map = keuring('BOTDF');
      await echt(map, '06 - Scream Louder.flac', 'Scream Louder', nr: 6);
      kap(await echt(map, '05 - Is It Scary.flac', 'Is It Scary', nr: 5));
      leg(map, 'info.txt', 'rip log'.codeUnits);
      leg(map, '07 - Ghosts.flac', const []); // een reservering zonder inhoud
      leg(map, '07 - Ghosts.flac.part', List<int>.filled(4000, 1)); // een download die niet afkwam

      expect(await manager().hervatKeuring(), 1);

      expect(alles('$downloads$sep$parkeerMap'), ['$parkeerAfgekeurd${sep}05 - Is It Scary.flac'],
          reason: 'de afgekapte hoort niet in je bibliotheek');
      expect(alles('$downloads${sep}Albums').single, endsWith('06 - Scream Louder.flac'));
      expect(alles('$downloads${sep}BOTDF'), ['info.txt'],
          reason: 'heel maar niet op te bergen: terug waar het vroeger stond');
      expect(Directory(map).existsSync(), isFalse, reason: 'en de keuringsmap is leeg en weg');
      expect(alles(downloads).where((p) => p.contains('Ghosts')), isEmpty, reason: 'het halve bestand is weg');
    }, skip: zonder);

    test('DE GRENS: lukt het parkeren niet, dan wordt een kapot bestand tóch niet zichtbaar', () async {
      // Een BESTAND op de plek waar de map voor afgekeurde bestanden had moeten komen: parkeren kan dan
      // niet. Dan blijft hij in de keuringsmap — en "de rest terug naar de zichtbare map" mag hem niet
      // meenemen, want dan stond hij alsnog in je bibliotheek.
      leg('$downloads$sep$parkeerMap', parkeerAfgekeurd, 'in de weg'.codeUnits);
      final map = keuring('BOTDF');
      kap(await echt(map, '05 - Is It Scary.flac', 'Is It Scary', nr: 5));

      await manager().hervatKeuring();

      expect(alles('$downloads${sep}BOTDF'), isEmpty, reason: 'afgekeurd hoort nooit zichtbaar te worden');
      expect(File('$map${sep}05 - Is It Scary.flac').existsSync(), isTrue, reason: 'hij wacht in de keuringsmap');
    }, skip: zonder);

    test('DE KERN: wat je al had en even goed is, blijft — de nieuwe gaat opzij', () async {
      final oud = await echt('$downloads${sep}Albums${sep}MJ', '05 - Is It Scary.flac', 'Is It Scary', nr: 5);
      final inhoud = oud.readAsBytesSync();
      await echt(keuring('BOTDF'), '05 - Is It Scary.flac', 'Is It Scary', nr: 50);

      await manager(bestaat: (a, t, {seconds, nietIn}) => t == 'Is It Scary' ? oud.path : null).hervatKeuring();

      expect(oud.readAsBytesSync(), inhoud, reason: 'jouw bestand is niet aangeraakt');
      expect(alles('$downloads$sep$parkeerMap'), ['$parkeerBinnenkomer${sep}05 - Is It Scary.flac'],
          reason: 'gelijk is geen winst');
    }, skip: zonder);

    test('DE VAL: een kapotte eigen kopie verliest — maar alleen omdat de keuring hem óók meet', () async {
      // Zonder de decodeerproef op wat er AL lag, geldt jouw afgekapte kopie als heel, is het gelijk,
      // en blijft de kapotte staan terwijl er een hele binnenkwam.
      final oud = await echt('$downloads${sep}Albums${sep}MJ', '05 - Is It Scary.flac', 'Is It Scary', nr: 5);
      kap(oud);
      await echt(keuring('BOTDF'), '05 - Is It Scary.flac', 'Is It Scary', nr: 50);

      await manager(bestaat: (a, t, {seconds, nietIn}) => t == 'Is It Scary' ? oud.path : null).hervatKeuring();

      expect((await controleerHeel(oud.path))!.heel, isTrue, reason: 'op jouw plek staat nu de hele');
      expect(alles('$downloads$sep$parkeerMap'), ['05 - Is It Scary.flac'], reason: 'de kapotte staat opzij');
      expect(bekendKapot('$downloads$sep$parkeerMap${sep}05 - Is It Scary.flac'), isTrue);
    }, skip: zonder);

    test('TIDAL: dezelfde keuring, en wat je ophaalde telt als jouw keuze', () async {
      final d = manager();
      final map = d.keuringsmapVoor('TIDAL album 103805723');
      expect(map.path, contains('$sep$keuringMap$sep'), reason: 'tiddl schreef tot 29-09-2026 in de muziekmap');
      // Terwijl tiddl nog schrijft, is dit geen restant van de vorige keer.
      await echt(map.path, 'Blood On The Dance Floor.flac', 'Blood On The Dance Floor', nr: 1);
      expect(await d.hervatKeuring(), 0, reason: 'een download die nog binnenkomt, laat de opstartronde met rust');
      kap(await echt(map.path, 'Morphine.flac', 'Morphine', nr: 2));

      final r = await d.keurBinnengekomen(map, 'TIDAL album 103805723', zichtbaar: d.tidalRest);

      expect(r!.moved, 1);
      expect(r.afgekeurd, 1);
      expect(r.keuringZin, '1 opgeborgen · 1 afgekeurd (kapot)');
      expect(alles('$downloads$sep$parkeerMap'), ['$parkeerAfgekeurd${sep}Morphine.flac']);
      expect(Directory(map.path).existsSync(), isFalse);
      // Zelf opgehaald, dus bij gelijke kwaliteit wint hij straks van wat er al lag.
      final gefiled = alles('$downloads${sep}Albums').single;
      expect(isVasteKeuze('$downloads${sep}Albums$sep$gefiled'), isTrue);
    }, skip: zonder);
  });

  group('TIDAL wordt aangesloten', () {
    final main = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');

    test('DE KERN: tiddl schrijft in de keuringsmap en er wordt daarna gekeurd', () {
      final i = main.indexOf('  Future<void> _ophalen() async {');
      expect(i, greaterThan(0));
      final lijf = main.substring(i, main.indexOf('\n  }\n', i));
      expect(lijf, contains('haalVanTidal(doel: doel, map: keuring.path'));
      expect(lijf, isNot(contains('map: map,')), reason: 'zo stond het: rechtstreeks in de muziekmap');
      final haal = lijf.indexOf('await haalVanTidal(');
      final keur = lijf.indexOf('await dm.keurBinnengekomen(');
      expect(keur, greaterThan(haal));
      // En vóór de foutafhandeling: bij een fout halverwege is er toch iets binnengekomen.
      expect(keur, lessThan(lijf.indexOf('if (uitslag.fout != null)')));
    });
  });
}

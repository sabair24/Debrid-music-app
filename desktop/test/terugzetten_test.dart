/// Terugzetten uit `_dubbel` wat er onder de regel van 29-09-2026 nooit uit had gemoeten.
///
/// Saber die dag, over Blood On The Dance Floor: *"ik kon zweren, dat ik alle liedjes in beste kwaliteit
/// had … en nu staan er een paar afgekapt en in mindere kwaliteit. … moet mijn betere kwaliteit die ik
/// al had blijven."* Gemeten: van de 95 kopieën in `_dubbel` hadden er 47 een opvolger met een lager
/// label. Is It Scary was een opgeschaalde 24/96 die plaats had gemaakt voor een eerlijke 24/48 —
/// dezelfde muziek, geen winst. Material Girl was een opgeschaalde 24/192 die plaats had gemaakt voor
/// een echte 24/96 — wél winst. Het eerste hoort terug, het tweede niet.
///
/// Drie bewijzen per kopie, anders geen voorstel: heel, dezelfde opname (vingerafdruk), en wat er nu
/// staat is niet bewezen beter.
library;

import 'dart:io';

import 'package:debridmusic/ffmpeg.dart';
import 'package:debridmusic/fingerprint.dart';
import 'package:debridmusic/flac_tags.dart';
import 'package:debridmusic/integriteit.dart';
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
  late String dubbel;

  // **Aan het eind alles nog eens wissen, tot het weg blijft.** De decodeerproef bewaart zijn uitslagen
  // zonder erop te wachten (`integriteit.json`), en die late schrijfbeurt houdt de map open of zet hem
  // terug: gemeten op 29-09-2026 bleven er zo 170 mappen in %TEMP% achter na een dag toetsen. Niet per
  // toets wachten — dat verschoof ooit de timing van een poorttoets —, maar één keer aan het eind.
  final teWissen = <Directory>[];
  tearDownAll(() async {
    for (var ronde = 0; ronde < 30 && teWissen.any((d) => d.existsSync()); ronde++) {
      for (final d in teWissen) {
        try {
          if (d.existsSync()) d.deleteSync(recursive: true);
        } catch (_) {/* nog in gebruik; volgende ronde */}
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  });
  setUp(() {
    wortel = Directory.systemTemp.createTempSync('dm_terugzetten_');
    teWissen.add(wortel);
    Directory('${wortel.path}${sep}app').createSync();
    setAppDirForTest('${wortel.path}${sep}app');
    resetIntegriteitVoorTest();
    resetVasteKeuzesForTest();
    downloads = '${wortel.path}${sep}DebridMusic Downloads';
    dubbel = '$downloads$sep$parkeerMap';
  });

  tearDown(() {
    resetIntegriteitVoorTest();
    resetVasteKeuzesForTest();
    try {
      wortel.deleteSync(recursive: true);
    } catch (_) {}
  });

  File leg(String map, String naam, List<int> bytes) {
    final f = File('$map$sep$naam');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes);
    return f;
  }

  List<String> alles(String map) => Directory(map).existsSync()
      ? ([
          for (final e in Directory(map).listSync(recursive: true))
            if (e is File) e.path.substring(map.length + 1),
        ]..sort())
      : const [];

  String album(String map) => '$downloads${sep}Albums$sep$map';

  group('een kopie terugzetten', () {
    List<int> flac(String titel, String albumnaam) => buildFlac(
        ['TITLE=$titel', 'ARTIST=Michael Jackson', 'ALBUM=$albumnaam', 'TRACKNUMBER=5'],
        seconds: 336);

    test('DE KERN: de oude komt op zijn plek, de huidige gaat opzij — niets weg', () async {
      final huidig = leg(album('BOTDF'), '05 - Is It Scary.flac', [...flac('Is It Scary', 'BOTDF'), 1]);
      final oud = leg(dubbel, '05 - Is It Scary.flac', [...flac('Is It Scary', 'BOTDF'), 2, 2]);
      final opzij = '$dubbel$sep$parkeerBinnenkomer';

      final uit = await zetGeparkeerdeTerug(oud, huidig, parkeerIn: opzij);

      expect(uit, huidig.path);
      expect(File(huidig.path).readAsBytesSync().last, 2, reason: 'op jouw plek staat nu de oude');
      expect(alles(opzij), ['05 - Is It Scary.flac'], reason: 'en de huidige staat opzij, niet weg');
      expect(oud.existsSync(), isFalse);
    });

    test('DE VAL: een ander formaat krijgt zijn eigen extensie, op dezelfde plek', () async {
      // Earth Song: een WavPack verving een FLAC. Terug moet het "…Earth Song.flac" heten, niet .wv.
      final huidig = leg(album('BOTDF'), '11 - Earth Song.wv', List<int>.filled(5000, 7));
      final oud = leg(dubbel, '11 - Earth Song.flac', flac('Earth Song', 'BOTDF'));

      final uit = await zetGeparkeerdeTerug(oud, huidig, parkeerIn: '$dubbel$sep$parkeerBinnenkomer');

      expect(uit, '${album('BOTDF')}${sep}11 - Earth Song.flac');
      expect(File(uit!).existsSync(), isTrue);
      expect(huidig.existsSync(), isFalse);
      expect(alles('$dubbel$sep$parkeerBinnenkomer'), ['11 - Earth Song.wv']);
    });

    test('DE GRENS: staat er onder de nieuwe naam al iets anders, dan gebeurt er niets', () async {
      final huidig = leg(album('BOTDF'), '11 - Earth Song.wv', List<int>.filled(5000, 7));
      final ander = leg(album('BOTDF'), '11 - Earth Song.flac', List<int>.filled(4000, 9));
      final oud = leg(dubbel, '11 - Earth Song.flac', flac('Earth Song', 'BOTDF'));

      expect(await zetGeparkeerdeTerug(oud, huidig, parkeerIn: '$dubbel$sep$parkeerBinnenkomer'), isNull);
      expect(huidig.existsSync(), isTrue);
      expect(ander.readAsBytesSync().first, 9, reason: 'niet overschreven');
      expect(oud.existsSync(), isTrue, reason: 'en de geparkeerde staat er nog');
    });

    test('hij neemt de albumnaam van de buren over, anders staat hij er als apart album', () async {
      for (final (nr, titel) in [(1, 'Blood On The Dance Floor'), (2, 'Morphine'), (3, 'Superfly Sister')]) {
        leg(album('BOTDF'), '0$nr - $titel.flac',
            buildFlac(['TITLE=$titel', 'ARTIST=Michael Jackson', 'ALBUM=Blood On The Dance Floor', 'TRACKNUMBER=$nr']));
      }
      final huidig = leg(album('BOTDF'), '05 - Is It Scary.flac', flac('Is It Scary', 'Blood On The Dance Floor'));
      final oud = leg(dubbel, '05 - Is It Scary.flac', flac('Is It Scary', 'Blood On The Dance Floor (HIStory In The Mix)'));

      final uit = await zetGeparkeerdeTerug(oud, huidig, parkeerIn: '$dubbel$sep$parkeerBinnenkomer');

      expect(readFlacTags(File(uit!))!.album, 'Blood On The Dance Floor');
    });
  });

  group('zoeken wat terug hoort, echt gemeten', () {
    final ffmpeg = Ffmpeg().pad;
    final fp = Fingerprinter().available;
    final zonder = ffmpeg == null
        ? 'geen ffmpeg op deze machine'
        : (!fp ? 'geen fpcalc op deze machine' : false);

    // Ruis in plaats van een sinus: een sinus leest de muurproef als "afgekapt", en dan zou alles hier
    // "omgezet uit een mp3" heten. Zelfde zaad = dezelfde opname; ander zaad = een andere.
    Future<File> echt(String map, String naam, {int zaad = 1, int rate = 44100}) async {
      final f = File('$map$sep$naam');
      f.parent.createSync(recursive: true);
      final r = await Process.run(ffmpeg!, [
        '-nostdin', '-v', 'error', '-f', 'lavfi',
        '-i', 'anoisesrc=d=30:c=pink:r=44100:a=0.3:seed=$zaad',
        '-metadata', 'title=Is It Scary', '-metadata', 'artist=Michael Jackson',
        '-metadata', 'album=Blood On The Dance Floor', '-metadata', 'track=5',
        if (rate != 44100) ...['-ar', '$rate'],
        '-c:a', 'flac', f.path,
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      return f;
    }

    DownloadManager manager(String Function() huidig) {
      final cfg = AppSettings()
        ..soulseekUser = 'toets'
        ..soulseekPass = 'toets';
      return DownloadManager(OnlineService(cfg), SoulseekService(cfg), wortel.path, () async {})
        ..mapVanBestaande = (a, t, {seconds, nietIn}) => t == 'Is It Scary' ? huidig() : null;
    }

    test('DE KERN: even goed, dezelfde opname — hij hoort terug, en daarna niet nog eens', () async {
      final huidig = await echt(album('BOTDF'), '05 - Is It Scary.flac', zaad: 5);
      await echt(dubbel, '05 - Is It Scary.flac', zaad: 5, rate: 96000); // "24/96", opgeschaald
      final d = manager(() => huidig.path);

      final v = await d.zoekTerugzettingen();
      expect(v, hasLength(1), reason: 'de vervanging was geen winst');
      expect(v.single.reden, contains('geen winst'));

      expect(await d.zetTerug(v), 1);
      expect(alles(dubbel), ['$parkeerBinnenkomer${sep}05 - Is It Scary.flac']);
      // En geen heen-en-weer: wat opzij ging staat in de submap, en een tweede ronde vindt niets.
      expect(await d.zoekTerugzettingen(), isEmpty, reason: 'anders wisselen twee even goede kopieën eindeloos');
    }, skip: zonder);

    test('DE VAL: zelfde titel, andere opname — geen voorstel', () async {
      final huidig = await echt(album('BOTDF'), '05 - Is It Scary.flac', zaad: 5);
      await echt(dubbel, '05 - Is It Scary.flac', zaad: 77);
      expect(await manager(() => huidig.path).zoekTerugzettingen(), isEmpty,
          reason: 'van zes vervangers die ooit binnenkwamen waren er zes een radio-edit');
    }, skip: zonder);

    test('DE GRENS: een kapotte kopie komt nooit terug', () async {
      final huidig = await echt(album('BOTDF'), '05 - Is It Scary.flac', zaad: 5);
      final oud = await echt(dubbel, '05 - Is It Scary.flac', zaad: 5);
      final b = oud.readAsBytesSync();
      oud.writeAsBytesSync(b.sublist(0, b.length * 4 ~/ 10));
      expect(await manager(() => huidig.path).zoekTerugzettingen(), isEmpty);
    }, skip: zonder);

    test('DE GRENS: niet te zeggen of hij heel is — dan ook niet terug', () async {
      // Zonder ffmpeg geeft de decodeerproef null. De kwaliteitsvergelijking weet dan evenmin dat hij
      // kapot is, en zou bij gelijk "terug" zeggen. Niet bewezen heel is geen ja.
      final huidig = await echt(album('BOTDF'), '05 - Is It Scary.flac', zaad: 5);
      await echt(dubbel, '05 - Is It Scary.flac', zaad: 5);
      final d = manager(() => huidig.path)..decodeerproef = (_) async => null;
      expect(await d.zoekTerugzettingen(), isEmpty);
    }, skip: zonder);

    test('DE GRENS: wat je zelf koos wint bij gelijk, en blijft', () async {
      final huidig = await echt(album('BOTDF'), '05 - Is It Scary.flac', zaad: 5);
      await echt(dubbel, '05 - Is It Scary.flac', zaad: 5);
      await onthoudVasteKeuze(huidig.path);
      expect(await manager(() => huidig.path).zoekTerugzettingen(), isEmpty);
    }, skip: zonder);

    test('wat binnenkwam en verloor was nooit van jou, en komt dus ook niet terug', () async {
      final huidig = await echt(album('BOTDF'), '05 - Is It Scary.flac', zaad: 5);
      await echt('$dubbel$sep$parkeerBinnenkomer', '05 - Is It Scary.flac', zaad: 5);
      await echt('$dubbel$sep$parkeerAfgekeurd', '05 - Is It Scary.flac', zaad: 5);
      expect(await manager(() => huidig.path).zoekTerugzettingen(), isEmpty);
    }, skip: zonder);
  });
}

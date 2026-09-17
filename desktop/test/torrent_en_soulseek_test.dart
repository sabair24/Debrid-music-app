/// Soulseek en torrent houden rekening met elkaar.
///
/// **Waarom dit bestaat.** Saber meldde op 17-09-2026: *"ik denk dat soulseek en torrent geen
/// rekening houdt met elkaar … soulseek blijft zoeken naar een betere kwaliteit … plus torrent
/// vervangt de soulseek download niet, en anders om ook niet?"*
///
/// Allebei waar, en nagemeten op zijn eigen schijf:
///
/// * **Culture Beat — Mr. Vain.** In `Albums\Culture Beat\Serenity\` stond een Soulseek-kopie,
///   gemeten als opgeblazen (96/24 zonder bovenband). Op 14-09 kwam er een schone 24/192 van een
///   torrent binnen, in Monkey's Audio. Die bleef liggen in `DebridMusic Downloads\Culture Beat\`,
///   en drie dagen later jaagde Soulseek er nog steeds op.
/// * In `downloads.log` stond in de hele geschiedenis **nul** keer "vervallen — die FLAC staat al".
///
/// Twee oorzaken, en elk hieronder vastgehouden:
///
/// 1. `hasLossless` telde alleen `.flac` — `isFlac` is letterlijk `ext == 'flac'`. Een verliesvrije
///    torrent in APE of WavPack kon een wens dus nooit laten vallen.
/// 2. Een torrent werd nooit opgeborgen. Een Soulseek-nummer gaat bij binnenkomst door
///    `placeFileDetailed`; een torrent bleef naast de bibliotheek staan tot iemand op een knop drukte.
///    De twee kwamen dus nooit tegenover elkaar te staan.
///
/// **Een derde vermoeden bleek niet waar, en dat staat er met opzet bij.** De Culture Beat-APE bleef
/// óók met de knop "Opruimen" liggen, en het lag voor de hand dat `readTags` APE niet kon lezen. Er
/// is een eigen APE-lezer voor gebouwd — en de mutatieproef betrapte hem: weghalen veranderde niets.
/// De tagbibliotheek leest APEv2 al, voor `.ape` én `.wv`. Dat bestand bleef liggen omdat er
/// helemaal GEEN tags in stonden. Groep 2 hieronder houdt vast dat die lezing blijft werken, want
/// het opbergen van een torrent hangt er nu van af.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/echtheid_oordelen.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/organize.dart';
import 'package:debridmusic/paths.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een geldige FLAC-kop met STREAMINFO (voor de looptijd) en tags, zonder geluid.
Uint8List flac(List<String> tags, {int seconden = 337, int opvulling = 0}) {
  const rate = 44100;
  final b = BytesBuilder();
  b.add(ascii.encode('fLaC'));
  b.add([0x00, 0x00, 0x00, 0x22]);
  final totaal = seconden * rate;
  final si = Uint8List(34);
  si[10] = (rate >> 12) & 0xFF;
  si[11] = (rate >> 4) & 0xFF;
  si[12] = ((rate & 0x0F) << 4) | (1 << 1); // stereo, zodat geen van beide "surround" is
  si[13] = (totaal >> 32) & 0x0F;
  si[14] = (totaal >> 24) & 0xFF;
  si[15] = (totaal >> 16) & 0xFF;
  si[16] = (totaal >> 8) & 0xFF;
  si[17] = totaal & 0xFF;
  b.add(si);
  final v = BytesBuilder();
  List<int> le32(int x) => [x & 0xFF, (x >> 8) & 0xFF, (x >> 16) & 0xFF, (x >> 24) & 0xFF];
  final vendor = utf8.encode('toets');
  v.add(le32(vendor.length));
  v.add(vendor);
  v.add(le32(tags.length));
  for (final c in tags) {
    final bytes = utf8.encode(c);
    v.add(le32(bytes.length));
    v.add(bytes);
  }
  final vb = v.takeBytes();
  b.add([0x84, (vb.length >> 16) & 0xFF, (vb.length >> 8) & 0xFF, vb.length & 0xFF]);
  b.add(vb);
  // Grootte telt in [firstIsBetter] als laatste grond; zo is te sturen welke kopie groter is.
  if (opvulling > 0) b.add(Uint8List(opvulling));
  return b.takeBytes();
}

/// Een Monkey's Audio-bestand met een APEv2-blok achteraan, zoals rippers het leveren.
Uint8List ape(Map<String, String> velden) {
  final items = <int>[];
  velden.forEach((k, v) {
    final waarde = utf8.encode(v);
    for (var i = 0; i < 4; i++) {
      items.add((waarde.length >> (8 * i)) & 0xFF);
    }
    items.addAll([0, 0, 0, 0]);
    items.addAll(k.codeUnits);
    items.add(0);
    items.addAll(waarde);
  });
  final maat = items.length + 32;
  final voet = <int>[...'APETAGEX'.codeUnits];
  void u32(int x) {
    for (var i = 0; i < 4; i++) {
      voet.add((x >> (8 * i)) & 0xFF);
    }
  }

  u32(2000);
  u32(maat);
  u32(velden.length);
  u32(0);
  voet.addAll(List.filled(8, 0));
  // 'MAC ' vooraan en wat ruimte, zodat het er als een bestand uitziet en niet als alleen een blok.
  return Uint8List.fromList([...'MAC '.codeUnits, ...List.filled(4096, 0), ...items, ...voet]);
}

/// Opgeblazen: precies wat de Soulseek-kopie van Mr. Vain op Sabers schijf was.
const _opgeblazen = Echtheidsoordeel(
  bits: Bitdiepte.spreektNietTegen,
  boven: Bovenband.leeg,
  band: Bandbreedte.onbekend,
  vensters: 32,
);

const _mrVain = ['TITLE=Mr. Vain', 'ARTIST=Culture Beat', 'ALBUM=Serenity', 'TRACKNUMBER=2'];

void main() {
  late Directory wortel;
  late String downloads;
  final sep = Platform.pathSeparator;

  setUp(() {
    wortel = Directory.systemTemp.createTempSync('dm_torrent_slsk_');
    setAppDirForTest(wortel.path);
    downloads = '${wortel.path}${sep}DebridMusic Downloads';
    Directory(downloads).createSync(recursive: true);
  });

  tearDown(() {
    resetEchtheidVoorTest();
    try {
      wortel.deleteSync(recursive: true);
    } catch (_) {}
  });

  File schrijf(String relatief, Uint8List bytes) {
    final f = File('$downloads$sep${relatief.replaceAll('/', sep)}');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes);
    return f;
  }

  List<File> alles(String onder) => Directory(onder).existsSync()
      ? Directory(onder).listSync(recursive: true).whereType<File>().where((f) {
          final n = f.path.toLowerCase();
          return n.endsWith('.flac') || n.endsWith('.ape');
        }).toList()
      : <File>[];

  group('1 — een verliesvrije kopie in ELK formaat stopt de jacht', () {
    Track nummer(String pad, {bool flac = false}) => Track(
          path: pad,
          title: 'Mr. Vain',
          artist: 'Culture Beat',
          album: 'Serenity',
          isFlac: flac,
          sizeBytes: 30 * 1024 * 1024,
        );

    test('DE KERN: een APE-kopie laat de wens vallen', () {
      final lib = LibraryStore()..tracks.add(nummer('$downloads${sep}Culture Beat${sep}Mr.Vain.ape'));
      expect(lib.hasLossless('Culture Beat', 'Mr. Vain'), isTrue,
          reason: 'dit was Sabers torrent: een schone 24/192 in APE, en Soulseek bleef zoeken');
    });

    test('DE KERN: WavPack en ALAC tellen net zo goed', () {
      for (final ext in ['wv', 'alac', 'wav']) {
        final lib = LibraryStore()..tracks.add(nummer('$downloads${sep}x.$ext'));
        expect(lib.hasLossless('Culture Beat', 'Mr. Vain'), isTrue, reason: '.$ext is verliesvrij');
      }
    });

    test('DE VAL: een mp3 laat hem NIET vallen', () {
      // Daar is de wens juist voor.
      final lib = LibraryStore()..tracks.add(nummer('$downloads${sep}Mr. Vain.mp3'));
      expect(lib.hasLossless('Culture Beat', 'Mr. Vain'), isFalse);
    });

    test('DE GRENS: een als nep gemeten APE telt ook niet', () {
      // De regel voor FLAC geldt voor elk verliesvrij formaat: bewezen nep is geen "die heb ik".
      final pad = '$downloads${sep}Culture Beat${sep}Mr.Vain.ape';
      final lib = LibraryStore()..tracks.add(nummer(pad));
      onthoudOordeelVanPc(pad, _opgeblazen);
      expect(lib.hasLossless('Culture Beat', 'Mr. Vain'), isFalse);
    });
  });

  group('2 — een getagde APE of WavPack is op te bergen', () {
    test('DE KERN: de tags uit het APE-blok worden gelezen', () {
      // Een bewaker, geen reparatie: dit werkte al (zie de kop). Maar het opbergen van een torrent
      // hangt er nu van af, en RuTracker levert veel in APE en WavPack.
      final f = schrijf('Culture Beat/02. Side 1 - Mr.Vain.ape',
          ape({'Title': 'Mr. Vain', 'Artist': 'Culture Beat', 'Album': 'Serenity', 'Track': '2/12'}));
      final t = readTags(f);
      expect(t, isNotNull, reason: 'anders blijft hij als "vastgelopen" in de landingsmap liggen');
      expect(t!.title, 'Mr. Vain');
      expect(t.artist, 'Culture Beat');
      expect(t.album, 'Serenity');
    });

    test('DE KERN: en ook bij WavPack, dat met `wvpk` begint en niet met `MAC `', () {
      // Hier twijfelde ik: de tagbibliotheek herkent APE aan `MAC `, en WavPack begint anders.
      // Nagemeten — hij leest het blok toch.
      final kop = [...'wvpk'.codeUnits, ...List.filled(28, 0)];
      final blok = ape({'Title': 'Mr. Vain', 'Artist': 'Culture Beat', 'Album': 'Serenity'});
      final f = schrijf('Culture Beat/Mr. Vain.wv', Uint8List.fromList([...kop, ...blok.sublist(4)]));
      final t = readTags(f);
      expect(t, isNotNull);
      expect(t!.artist, 'Culture Beat');
    });

    test('DE GRENS: een APE zonder tags levert null, en geen verzonnen naam', () {
      // Precies het bestand dat op Sabers schijf lag: geen enkele tag. Dan liever blijven liggen
      // dan opgeborgen worden onder "Onbekende artiest".
      final f = schrijf('Culture Beat/02. Side 1 - Mr.Vain.ape',
          Uint8List.fromList([...'MAC '.codeUnits, ...List.filled(4096, 0)]));
      final t = readTags(f);
      expect(t == null || t.artist.isEmpty, isTrue);
    });
  });

  group('3 — een torrent wordt opgeborgen en vervangt een mindere kopie', () {
    /// Wat `library.fileOfRecording` doet, maar dan binnen deze toets: het bestaande bestand van
    /// deze opname, alleen als de looptijd klopt (de Sting-reparatie). Houdt bij wat hij kreeg.
    late List<int?> gevraagdeLooptijden;
    String? Function(String, String, {int? seconds}) staatAlVoor(String bestaand, int looptijd) =>
        (artist, title, {int? seconds}) {
          gevraagdeLooptijden.add(seconds);
          if (artist != 'Culture Beat' || title != 'Mr. Vain') return null;
          if (seconds != null && (seconds - looptijd).abs() > 3) return null;
          return bestaand;
        };

    setUp(() => gevraagdeLooptijden = []);

    test('DE KERN: een echte torrent vervangt de nep Soulseek-kopie', () async {
      final oud = schrijf('Albums/Culture Beat/Serenity/02 - Mr. Vain.flac', flac(_mrVain, opvulling: 900000));
      onthoudOordeelVanPc(oud.path, _opgeblazen);
      final torrentMap = '$downloads${sep}Culture Beat';
      schrijf('Culture Beat/02. Mr. Vain.flac', flac(_mrVain));

      final r = await bergMapOp(torrentMap, downloads, staatAl: staatAlVoor(oud.path, 337));

      expect(r.moved + r.duplicates, 1);
      // Op de plek van de oude staat nu de torrentkopie — de kleinere, want de nep-kopie was groter
      // gemaakt. Grootte wint dus NIET van "bewezen nep", en dat is precies het punt.
      expect(File(oud.path).existsSync(), isTrue);
      expect(File(oud.path).lengthSync(), lessThan(900000),
          reason: 'de opgeblazen kopie was groter en had op grootte gewonnen');
      final dubbel = alles('$downloads$sep$parkeerMap');
      expect(dubbel, hasLength(1), reason: 'de verliezer gaat naar _dubbel, niet weg');
      expect(dubbel.single.lengthSync(), greaterThan(900000));
      expect(Directory(torrentMap).existsSync(), isFalse,
          reason: 'de losse torrentmap naast de bibliotheek hoort weg te zijn');
    });

    test('DE KERN: de looptijd uit het bestand gaat mee naar staatAl', () async {
      // Zonder looptijd antwoordt staatAl op artiest + titel alleen — het Sting-geval, waar een
      // heropname als mindere dubbel van de plaat uit 1993 verdween.
      schrijf('Culture Beat/02. Mr. Vain.flac', flac(_mrVain, seconden: 337));
      await bergMapOp('$downloads${sep}Culture Beat', downloads,
          staatAl: staatAlVoor('niet-gebruikt', 337));
      expect(gevraagdeLooptijden, isNotEmpty);
      expect(gevraagdeLooptijden.first, 337);
    });

    test('DE VAL: een andere versie (andere looptijd) vervangt niets', () async {
      final oud = schrijf('Albums/Culture Beat/Serenity/02 - Mr. Vain.flac', flac(_mrVain, seconden: 337));
      onthoudOordeelVanPc(oud.path, _opgeblazen);
      // Dezelfde titel, maar anderhalve minuut korter: een radio-edit, geen betere kopie.
      schrijf('Culture Beat/Mr. Vain.flac', flac(_mrVain, seconden: 250));

      await bergMapOp('$downloads${sep}Culture Beat', downloads, staatAl: staatAlVoor(oud.path, 337));

      expect(alles('$downloads$sep$parkeerMap'), isEmpty,
          reason: 'een radio-edit mag de albumversie nooit wegduwen');
    });

    test('DE VAL: een nep torrent verdrijft een echte FLAC niet', () async {
      // De andere richting. RuTracker is meestal goed, maar niet altijd.
      final oud = schrijf('Albums/Culture Beat/Serenity/02 - Mr. Vain.flac', flac(_mrVain));
      final nieuw = schrijf('Culture Beat/02. Mr. Vain.flac', flac(_mrVain, opvulling: 900000));
      onthoudOordeelVanPc(nieuw.path, _opgeblazen);

      await bergMapOp('$downloads${sep}Culture Beat', downloads, staatAl: staatAlVoor(oud.path, 337));

      expect(File(oud.path).lengthSync(), lessThan(900000), reason: 'de echte bleef staan');
      // Zelfde beleid als voor een Soulseek-download, en dat staat zo in `placeFileDetailed`: wat al
      // in je bibliotheek stond en verliest gaat naar `_dubbel`, want dat is van jou. Wat deze
      // download zelf net ophaalde en verliest, mag weg. In `downloads.log` staat dat al maanden als
      // "schoon, maar draagt minder dan wat er ligt — weggegooid".
      expect(nieuw.existsSync(), isFalse, reason: 'de mindere binnenkomende kopie wordt niet bewaard');
      expect(alles('$downloads$sep$parkeerMap'), isEmpty,
          reason: '_dubbel is voor wat JIJ had, niet voor wat er net binnenkwam');
    });

    test('DE GRENS: zonder leesbare looptijd wordt staatAl niet gebruikt', () async {
      // Een APE heeft hier geen looptijdlezer. Dan liever opbergen op de eigen albumtag dan een
      // gok die "dit is dezelfde opname" zegt en een bestand kost.
      schrijf('Culture Beat/02. Mr. Vain.ape',
          ape({'Title': 'Mr. Vain', 'Artist': 'Culture Beat', 'Album': 'Serenity', 'Track': '2'}));
      await bergMapOp('$downloads${sep}Culture Beat', downloads,
          staatAl: staatAlVoor('mag-niet-gebruikt-worden', 337));
      expect(gevraagdeLooptijden, isEmpty, reason: 'staatAl hoort hier niet eens gevraagd te worden');
      expect(alles('$downloads${sep}Albums'), hasLength(1),
          reason: 'maar opgeborgen wordt hij wel, op zijn eigen tags');
    });

    test('DE GRENS: een torrent zonder tags blijft liggen waar hij lag', () async {
      final f = schrijf('Culture Beat/02. Side 1 - Mr.Vain.ape',
          Uint8List.fromList([...'MAC '.codeUnits, ...List.filled(4096, 0)]));
      final r = await bergMapOp('$downloads${sep}Culture Beat', downloads, staatAl: staatAlVoor('x', 337));
      expect(r.moved + r.duplicates, 0);
      expect(f.existsSync(), isTrue, reason: 'niet kunnen lezen is geen reden om iets weg te zetten');
    });

    test('DE GRENS: een Deluxe Edition vervangt de gewone plaat niet zonder staatAl-treffer', () async {
      // Twee uitgaven horen twee mappen te blijven. Alleen als staatAl zegt "dit IS die opname"
      // wordt er vervangen.
      final oud = schrijf('Albums/Culture Beat/Serenity/02 - Mr. Vain.flac', flac(_mrVain));
      schrijf('Culture Beat/Mr. Vain.flac',
          flac(['TITLE=Mr. Vain', 'ARTIST=Culture Beat', 'ALBUM=Serenity (Deluxe Edition)', 'TRACKNUMBER=2']));

      await bergMapOp('$downloads${sep}Culture Beat', downloads,
          staatAl: (a, t, {int? seconds}) => null);

      expect(File(oud.path).existsSync(), isTrue);
      expect(alles('$downloads$sep$parkeerMap'), isEmpty);
      expect(alles('$downloads${sep}Albums'), hasLength(2), reason: 'twee uitgaven, twee kopieën');
    });
  });

  group('4 — de downloadmotor roept het ook werkelijk aan', () {
    // Alles hierboven toetst [bergMapOp]. Maar de storing was nu juist dat het opbergen er WEL was —
    // als knop in Instellingen — en de torrentweg het nooit aanriep. Die aansluiting zit diep in de
    // downloadmotor, tussen aria2 en TorBox, en is niet los te draaien. Dus kijkt deze toets naar de
    // brontekst, zodat een verhuizing of opschoning hem niet stil kan laten verdwijnen.
    final bron = File('lib/online.dart').readAsStringSync().replaceAll('\r\n', '\n');

    test('DE KERN: na het knippen van de images wordt de torrent opgeborgen', () {
      final knip = bron.indexOf('await _knipImages(destDir, nieuwe);');
      final berg = bron.indexOf('await _bergTorrentOp(destDir, torrent.name);');
      expect(knip, greaterThan(0));
      expect(berg, greaterThan(knip),
          reason: 'zonder deze aanroep blijft een torrent naast de bibliotheek liggen, zoals voorheen');
      // En direct erna, niet ergens anders: vóór het knippen is een image met cue nog één groot
      // bestand, en dat hoort niet als één nummer in je bibliotheek te belanden.
      expect(bron.substring(knip, berg).split('\n').where((r) => r.trim().startsWith('await')).length, 1,
          reason: 'er hoort niets tussen het knippen en het opbergen te gebeuren');
    });

    test('DE VAL: het opbergen geeft staatAl mee, net als een Soulseek-download', () {
      final i = bron.indexOf('Future<void> _bergTorrentOp(');
      expect(i, greaterThan(0));
      final lijf = bron.substring(i, bron.indexOf('\n  }\n', i));
      expect(lijf, contains('staatAl: mapVanBestaande'),
          reason: 'zonder staatAl landt een betere kopie NAAST de oude in plaats van erop');
    });

    test('DE VAL: en de jacht stopt meteen, niet pas bij de volgende veegbeurt', () {
      final i = bron.indexOf('Future<void> _bergTorrentOp(');
      final lijf = bron.substring(i, bron.indexOf('\n  }\n', i));
      expect(lijf, contains('await vergeetWatErAlIs()'),
          reason: 'anders haalt Soulseek er in de tussentijd nog een kopie van binnen');
    });
  });
}

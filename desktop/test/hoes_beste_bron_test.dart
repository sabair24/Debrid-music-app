// Per beeld de beste bron (Saber, 20-10-2026): "front is meestal de digitale versie het beste 1200x1200 of
// bij the audiodb 700x700, voor de cd afbeelding meestal the audiodb ook 1000x1000, en achterkant of
// musicbrainz of discogs hoogste resolutie wel."
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/deezerbaan.dart';
import 'package:debridmusic/discogs.dart' show grootsteBeeld;
import 'package:debridmusic/enrichment.dart';
import 'package:debridmusic/musicbrainz.dart';

void main() {
  group('voorkant', () {
    test('Deezer op 1200: gemeten op de CDN, en een ander adres blijft zoals het is', () {
      expect(
          deezerHoes1200(
              'https://cdn-images.dzcdn.net/images/cover/0fd6e3b346b959a8781ccfa89b63607a/1000x1000-000000-80-0-0.jpg'),
          'https://cdn-images.dzcdn.net/images/cover/0fd6e3b346b959a8781ccfa89b63607a/1200x1200-000000-80-0-0.jpg');
      expect(deezerHoes1200('https://cdn-images.dzcdn.net/images/cover/abc/500x500-000000-80-0-0.jpg'),
          endsWith('/1200x1200-000000-80-0-0.jpg'));
      const ander = 'https://r2.theaudiodb.com/images/media/album/thumb/x.jpg';
      expect(deezerHoes1200(ander), ander);
    });

    test('TheAudioDB 700 als tweede keus: het veld overleeft de schijf, en alleen een voorkant is niet leeg', () {
      const info = AlbumInfo(frontUrl: 'https://r2.theaudiodb.com/images/media/album/thumb/x.jpg');
      expect(AlbumInfo.fromJson(info.toJson()).frontUrl, info.frontUrl);
      expect(info.isEmpty, isFalse);
    });

    test('aangesloten: eerst Deezer op 1200 (met 1000 als terugval), dan TheAudioDB, dan Discogs en het archief', () {
      final e = File('lib/enrichment.dart').readAsStringSync();
      final find = e.substring(e.indexOf('  Future<Uint8List?> _find(String artistRaw, String albumRaw) async {'));
      final deezer = find.indexOf('final groot = deezerHoes1200(deezer);');
      final tadb = find.indexOf('final u = (await albumInfo(artist, album))?.frontUrl;');
      final discogs = find.indexOf('if (settings.discogsToken.isNotEmpty) {');
      final mb = find.indexOf('return await _musicbrainzCover(');
      expect([deezer, tadb, discogs, mb].every((i) => i > 0), isTrue);
      expect(deezer < tadb && tadb < discogs && discogs < mb, isTrue);
      expect(find, contains('?? await _download(deezer)'), reason: 'geen 1200: dan de 1000 van cover_xl');
      expect(e, contains("frontUrl: s('strAlbumThumb'),"));
      expect(e, contains("fnv1a('v3|"), reason: 'een nieuw veld in een bewaard record: de sleutel omhoog');
    });
  });

  test('aangesloten: na een ▶ de achterkant en de cd alvast, met de sleutel van Nu speelt, alleen gratis bronnen', () {
    final m = File('lib/main.dart').readAsStringSync();
    final s = m.substring(m.indexOf('  Future<void> speelNummer(BuildContext context,'));
    final voor = s.substring(0, s.indexOf('final klinkendAdres = vroeg?.adres ?? elders?.pad;'));
    expect(voor, contains('final v = albumArtVooruit(lib, landAl);'));
    expect(voor, contains('roles: v.roles, freeOnly: true)'), reason: 'vooraf: nooit het Discogs-budget');
  });

  group('cd en achterkant', () {
    // Saber, 21-10-2026: "over het algemeen wil ik theaudioDB voor de hoezen, voorkant, cd en achterkant, maar
    // vooral de achterkant zit er niet altijd bij … een vangnet … musicbrainz of discogs, wie de hoogste
    // resolutie heeft".
    test('aangesloten: TheAudioDB eerst voor cd én achterkant; de achterkant daarna de scherpste van archief en Discogs', () {
      final d = File('lib/discogs.dart').readAsStringSync();
      expect(d, contains('back: saidBack ?? tadb?.back ?? found.back,'));
      expect(d, contains('(saidBack != null || tadb?.back != null || scherp(found.back)) &&'),
          reason: 'pas klaar als TheAudioDB het had, of het archief al scherp genoeg was');
      expect(d, contains('back: grootsteBeeld(caa?.back, at(guessed.back)),'));
      expect(d, contains('final voor = grootsteBeeld(caa?.front, at(guessed.front));'));
      // Tegelijk met het archief gevraagd, niet erna.
      final keten = d.substring(d.indexOf('    final tadbF ='));
      expect(keten.indexOf('final exactF ='), lessThan(keten.indexOf('tadb = await Future.any([')));
    });

    // Saber, 22-10-2026: "ik zou eerder the audiodb nemen voor de afbeelding van cd, die staat er direct, en is meestal
    // de mooiste en hoogste res, dan discogs en dan de rest".
    test('aangesloten: de cd van TheAudioDB, dan Discogs, dan het archief — niet meer de scherpste', () {
      final d = File('lib/discogs.dart').readAsStringSync();
      expect(d, contains('disc: saidDisc ?? tadb?.disc ?? discogsCd ?? found.disc,'));
      expect(d, contains('(saidDisc != null || tadb?.disc != null || discogsCd != null || scherp(found.disc));'),
          reason: 'een cd van Discogs is genoeg: niet meer op het archief wachten (Anouk — Girl: 35–77 s)');
      expect(d, contains('disc: disc ?? caa?.disc,'));
      expect(d, isNot(contains('disc: grootsteBeeld(caa?.disc, disc),')));
      final keten = d.substring(d.indexOf('    tadb = await Future.any(['));
      expect(keten, contains('discogsCd = disc;'));
      // Elk vroeg antwoord met een cd uit het archief wacht eerst even op die van Discogs.
      expect('await wachtOpDiscogsCd();'.allMatches(keten).length, 3);
      expect(keten.indexOf('await wachtOpDiscogsCd();'), lessThan(keten.indexOf('final art = said(exact);')));
    });

    test('aangesloten: Discogs wacht niet op een TheAudioDB die zwijgt (live: 16,7 s en dan niets)', () {
      final d = File('lib/discogs.dart').readAsStringSync();
      final keten = d.substring(d.indexOf('    tadb = await Future.any(['));
      expect(keten, contains('Future<({Uint8List? back, Uint8List? disc})?>.delayed(kTadbGeduld, () => null),'));
      expect(keten.indexOf('final discogsVoorafF ='), lessThan(keten.indexOf('      tadb = await tadbF;')),
          reason: 'Discogs begint al terwijl TheAudioDB nog zoekt');
      expect(keten.indexOf('if (discogsBeeldenF != null) {'), lessThan(keten.indexOf('      tadb = await tadbF;')),
          reason: 'en zijn tussenstand wacht er evenmin op');
      expect(keten, contains('      tadb = await tadbF;\n      tadbTussen();'), reason: 'komt TheAudioDB later, dan wint zijn cd');
    });

    test('de grootste achterkant wint; bij gelijke maat het archief of Discogs (live: ANTI 540×475 tegen 700×700)', () {
      Uint8List png(int w, int h, int merk) {
        final b = Uint8List(40);
        b.setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
        final d = ByteData.sublistView(b)
          ..setUint32(16, w)
          ..setUint32(20, h);
        d.setUint8(39, merk);
        return b;
      }

      final archief = png(540, 475, 1), tadb = png(700, 700, 2), gelijk = png(540, 475, 3);
      expect(grootsteBeeld(archief, tadb), same(tadb));
      expect(grootsteBeeld(archief, gelijk), same(archief));
      expect(grootsteBeeld(null, tadb), same(tadb));
      expect(grootsteBeeld(archief, null), same(archief));
    });

    test('aangesloten: een tussenstand zodra TheAudioDB antwoordt (live: 0,23 s tegen 5,8–10,8 s voor de keten)', () {
      final d = File('lib/discogs.dart').readAsStringSync();
      final keten = d.substring(d.indexOf('    tadb = await Future.any(['));
      expect(keten.indexOf('tussen(said(const ReleaseArt()));'), lessThan(keten.indexOf('final exact = await exactF;')),
          reason: 'vóór het archief, niet erna');
      // En die van Discogs ook (22-10-2026, Anouk — Girl: Discogs had 4 beelden, het archief deed er 35–77 s over).
      final discogs = keten.indexOf('tussen(said(ReleaseArt(back: back, disc: disc)));');
      expect(discogs, greaterThan(0));
      expect(discogs, lessThan(keten.indexOf('final exact = await exactF;')));
      expect(discogs, lessThan(keten.indexOf('await _artFromMusicBrainz(artist, album, expectedTracks)')));
      expect(d, contains('if (tussenstand != null) (_artTussen[lane] ??= []).add(tussenstand);'),
          reason: 'ook wie meelift op een keten die al loopt');
      final m = File('lib/main.dart').readAsStringSync();
      final load = m.substring(m.indexOf('  Future<void> _load() async {'));
      expect(load, contains('tussenstand: (t) {'));
      expect(load, contains('disc: nu?.disc ?? t.disc,'), reason: 'wat er al staat, blijft staan');
    });

    test('aangesloten: Discogs zoekt al naast het archief als TheAudioDB geen cd heeft (live: archief 4,1–4,6 s)', () {
      final d = File('lib/discogs.dart').readAsStringSync();
      final keten = d.substring(d.indexOf('    tadb = await Future.any(['));
      final vooraf = keten.indexOf('final discogsVoorafF = !freeOnly && pinned == null && !enough(const ReleaseArt())');
      expect(vooraf, greaterThan(0),
          reason: 'niet voor de opwarmer, niet bij een aangewezen persing, niet als TheAudioDB cd en achterkant al had');
      expect(vooraf, lessThan(keten.indexOf('await _artFromMusicBrainz(artist, album, expectedTracks)')),
          reason: 'vóór de andere persingen, niet erna');
      expect(keten, contains('e = await (discogsVoorafF ?? _quickRelease(artist, album));'),
          reason: 'de stap die Discogs vraagt, neemt het vooraf gestarte antwoord');
    });

    test('aangesloten: Nu speelt schrijft de weg van zijn hoezen in kunst.log, op elk toestel', () {
      // Op de gsm kwam de echte cd 20 tot 30 s na de tik (21-10-2026), en daar stond niets van in een log.
      final m = File('lib/main.dart').readAsStringSync();
      final load = m.substring(m.indexOf('  Future<void> _load() async {'));
      expect(load.substring(0, load.indexOf('tussenstand: (t) {')), contains('trace: spoor,'));
      final hoofd = m.substring(m.indexOf('Future<void> main() async {'));
      final zet = hoofd.indexOf('kunstSpoor = (r) => Timer.run(() => kunstLog.line(r));');
      expect(zet, greaterThan(0));
      expect(zet, lessThan(hoofd.indexOf('runApp(')), reason: 'vóór het eerste scherm');
    });

    test('aangesloten: de achterkant uit het archief op zijn grootst', () {
      final d = File('lib/discogs.dart').readAsStringSync();
      expect(d, contains('if (back == null && i.isBack) back = await mb.fetchGrootste(i);'));
      expect(d, contains("k == 'back' ? mb.fetchGrootste(want[k]!) : mb.fetchImage(want[k]!.full)"));
    });

    group('fetchGrootste', () {
      late HttpServer server;
      late Map<String, List<int>> bestanden;
      setUp(() async {
        bestanden = {};
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((req) async {
          final b = bestanden[req.uri.path];
          if (b == null) {
            req.response.statusCode = 404;
          } else {
            req.response.contentLength = b.length;
            req.response.add(b);
          }
          await req.response.close();
        });
      });
      tearDown(() => server.close(force: true));

      String adres(String p) => 'http://127.0.0.1:${server.port}$p';
      MbImage beeld() => MbImage(adres('/origineel.jpg'), adres('/250.jpg'), adres('/1200.jpg'), const ['Back'], false, true);

      test('het origineel als het binnen de grens blijft', () async {
        bestanden['/origineel.jpg'] = List.filled(3000, 1);
        bestanden['/1200.jpg'] = List.filled(1000, 2);
        expect(await MusicBrainzService().fetchGrootste(beeld(), maxBytes: 5000), Uint8List.fromList(List.filled(3000, 1)));
      });

      test('te groot of weg: de 1200', () async {
        bestanden['/origineel.jpg'] = List.filled(9000, 1);
        bestanden['/1200.jpg'] = List.filled(1000, 2);
        expect(await MusicBrainzService().fetchGrootste(beeld(), maxBytes: 5000), Uint8List.fromList(List.filled(1000, 2)));
        bestanden.remove('/origineel.jpg');
        expect(await MusicBrainzService().fetchGrootste(beeld(), maxBytes: 5000), Uint8List.fromList(List.filled(1000, 2)));
      });
    });
  });
}

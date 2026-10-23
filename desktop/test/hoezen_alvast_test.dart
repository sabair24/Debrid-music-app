// De hoezen van een plaat beginnen zodra het nummer begint binnen te komen, en zijn er meteen als het landt.
//
// Saber, 23-10-2026: *"En nog altijd niet direct de cd afbeelding?? … het moet direct, eigenlijk vanaf het moment dat
// het liedje begint te downloaden moet die hoes, cd afbeelding en achterkant al beginnen"*. Gemeten bij de radio vanaf
// Luka: Hounds of Love landde om 12:29:01, de feiten kwamen om 12:33:27 en de voorkant om 12:35:42 — de veeg was met
// andere platen bezig. Cd en achterkant kwamen bij andere platen pas in de volledige ronde, tot een uur later.
import 'dart:io';

import 'package:debridmusic/album_facts.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/facts_warmer.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory scratch;
  late LibraryStore library;
  late AppSettings settings;
  late List<String> gevraagd; // wat de feitenzoeker kreeg
  late List<String> scans; // wat de scans kregen: artiest|album|aantal|mbid|gratis
  late List<String> voorkanten;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_alvast_');
    setAppDirForTest(scratch.path);
    settings = AppSettings();
    library = LibraryStore()
      ..configDirOverride = scratch.path
      ..rootPath = scratch.path;
    gevraagd = [];
    scans = [];
    voorkanten = [];
  });
  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  FactsWarmer warmer({bool enabled = true}) => FactsWarmer(
        voorkant: (artist, album, titels) async {
          voorkanten.add('$artist|$album|${titels.join(",")}');
          return null;
        },
        volledigTussen: Duration.zero,
        library: library,
        settings: settings,
        mb: MusicBrainzService(),
        enabled: enabled,
        resolve: (album, {required uid, required trackSetHash, required mb, required settings, pinnedMbid, pinned,
            discogs}) async {
          gevraagd.add('${album.artist}|${album.title}|'
              '${[for (final t in album.tracks) '${t.title}/${t.duration?.inSeconds}'].join(",")}|uid=$uid');
          return AlbumFacts(
            uid: uid,
            trackSetHash: trackSetHash,
            source: 'MusicBrainz',
            mbid: 'mb-hounds',
            tracklist: const [ChoiceTrack('1', 'Running Up That Hill', 300), ChoiceTrack('4', 'Cloudbusting', 310)],
          );
        },
        warmArt: (artist, album,
            {required expectedTracks, pinned, pinnedMbid, required roles, required settings, freeOnly = true, trace}) async {
          scans.add('$artist|$album|$expectedTracks|$pinnedMbid|${freeOnly ? 'gratis' : 'discogs'}');
          return null;
        },
      );

  test('DE KERN: alvast — feiten met het nummer dat straks landt, de voorkant, en de scans, ook via Discogs', () async {
    final w = warmer();
    await w.alvast('Kate Bush', 'Hounds of Love', titel: 'Cloudbusting', seconden: 310);
    expect(gevraagd, ['Kate Bush|Hounds of Love|Cloudbusting/310|uid='],
        reason: 'met hetzelfde nummer kiest de feitenzoeker straks dezelfde persing, en dus dezelfde map voor de scans');
    expect(voorkanten, ['Kate Bush|Hounds of Love|Cloudbusting']);
    expect(scans, [
      'Kate Bush|Hounds of Love|2|mb-hounds|gratis',
      'Kate Bush|Hounds of Love|2|mb-hounds|discogs',
    ], reason: 'de cd en de achterkant meteen, niet pas in de volledige ronde');
    // Eén keer per plaat per sessie: een tweede nummer van dezelfde plaat vraagt niets opnieuw.
    await w.alvast('Kate Bush', 'Hounds of Love', titel: 'Running Up That Hill', seconden: 300);
    expect(gevraagd, hasLength(1));
    w.dispose();
  });

  test('alvast doet niets op een toestel, of zonder album', () async {
    final w = warmer(enabled: false);
    await w.alvast('Kate Bush', 'Hounds of Love', titel: 'Cloudbusting');
    final w2 = warmer();
    await w2.alvast('Kate Bush', '  ');
    expect(gevraagd, isEmpty);
    expect(scans, isEmpty);
    w.dispose();
    w2.dispose();
  });

  test('DE KERN: voorrang — na het landen díe plaat meteen, met haar echte uid, en de feiten bewaard', () async {
    final t = Track(
        path: '${scratch.path}/Singles/Kate Bush/Cloudbusting.flac',
        title: 'Cloudbusting',
        artist: 'Kate Bush',
        album: 'Hounds of Love',
        duration: const Duration(seconds: 310));
    library.tracks.add(t);
    library.rebuildAlbums();
    final album = library.albums.single;
    final uid = library.uidOf(album);
    expect(uid, isNotEmpty);
    final w = warmer();
    await w.voorrang(t.path);
    expect(gevraagd, ['Kate Bush|Hounds of Love|Cloudbusting/310|uid=$uid']);
    expect(library.facts.get(uid)?.mbid, 'mb-hounds', reason: 'de veeg hoeft hem daarna niet meer');
    expect(scans.first, 'Kate Bush|Hounds of Love|2|mb-hounds|gratis', reason: 'dezelfde sleutel als alvast');
    w.dispose();
  });

  test('voorrang slaat een losse single (zonder albumtag) over', () async {
    final t = Track(path: '${scratch.path}/Singles/X/Y.flac', title: 'Y', artist: 'X', album: '');
    library.tracks.add(t);
    library.rebuildAlbums();
    final w = warmer();
    await w.voorrang(t.path);
    expect(gevraagd, isEmpty);
    w.dispose();
  });

  test('de downloader meldt het album: meteen als het bekend is, of zodra het oorspronkelijke gevonden is', () async {
    final gemeld = <String>[];
    DownloadManager.albumBekend = (a, b, t, s) => gemeld.add('$a|$b|$t|$s');
    addTearDown(() => DownloadManager.albumBekend = null);
    // Al bekend (▶ op een plaat): meteen.
    DownloadManager.meldAlbum('Kate Bush', 'Cloudbusting', 310, album: 'Hounds of Love');
    expect(gemeld, ['Kate Bush|Hounds of Love|Cloudbusting|310']);
    // De radio: zodra het oorspronkelijke album gevonden is — en niets als er geen is.
    DownloadManager.meldAlbum('Crowded House', 'Weather With You', 224,
        origineel: Future.value((album: 'Woodface', jaar: 1991)));
    DownloadManager.meldAlbum('Duran Duran', 'Ordinary World', 340, origineel: Future.value(null));
    await Future<void>.delayed(Duration.zero);
    expect(gemeld, ['Kate Bush|Hounds of Love|Cloudbusting|310', 'Crowded House|Woodface|Weather With You|224']);
    // En zo aangesloten: beide radiowegen melden, de app warmt alvast, en elke landing krijgt voorrang.
    final bron = File('lib/online.dart').readAsStringSync();
    expect(RegExp(r'meldAlbum\(artiest, titel, seconden,').allMatches(bron).length, 2, reason: 'Soulseek en TIDAL');
    final app = File('lib/main.dart').readAsStringSync();
    expect(app, contains('warmer.alvast(artiest, album, titel: titel, seconden: seconden)'));
    expect(app, contains('naLanding: (pad) => unawaited(warmer.voorrang(pad))'));
    expect(app, contains('      await library.voegBestandToe(pad);\n      unawaited(warmer.voorrang(pad));'));
    expect(File('lib/radio.dart').readAsStringSync(), contains('if (t != null) naLanding?.call(t.path);'));
  });
}

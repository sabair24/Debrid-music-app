/// Looking records up before they are asked for.
///
/// The loop itself is easy. What is not easy is what happens when the network goes away: a lookup
/// that finds nothing writes `failedMs` and blinds that album for twenty-four hours, and once the
/// miss cache is warm it answers instantly — so an offline sweep can march through a whole library
/// in seconds and blind all of it. That is the difference between a feature and a liability, and
/// it is what most of this file tests.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/album_facts.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/facts_warmer.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';

void main() {
  late Directory scratch;
  late LibraryStore library;
  late AppSettings settings;
  late List<String> asked;

  /// What the warmer pulled the scans for, so the test can hold onto the one thing that makes an
  /// album page instant: the artwork is warmed under the SAME key the page will ask with.
  late List<String> warmedArt;

  Track track(String album, int i, {int addedMs = 0}) => Track(
        path: '/m/$album/$i.flac',
        title: 'nr $i',
        artist: 'Portishead',
        album: album,
        trackNo: i,
        addedMs: addedMs,
      );

  void seedLibrary(List<String> albums, {Map<String, int> added = const {}}) {
    library.tracks.clear();
    for (final a in albums) {
      for (var i = 1; i <= 2; i++) {
        library.tracks.add(track(a, i, addedMs: added[a] ?? 0));
      }
    }
    library.rebuildAlbums();
  }

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('dm_warm_');
    setAppDirForTest(scratch.path);
    settings = AppSettings();
    library = LibraryStore()
      ..configDirOverride = scratch.path
      ..rootPath = scratch.path;
    asked = [];
    warmedArt = [];
  });

  tearDown(() {
    try {
      scratch.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// A resolver that answers however the test says, and records what it was asked.
  FactsWarmer warmer({
    required bool Function(String uid) found,
    bool enabled = true,
  }) =>
      FactsWarmer(
        library: library,
        settings: settings,
        mb: MusicBrainzService(),
        enabled: enabled,
        rearmDelay: const Duration(milliseconds: 20),
        outageBackoff: const Duration(milliseconds: 50),
        resolve: (album, {required uid, required trackSetHash, required mb, required settings,
            pinnedMbid, pinned, discogs}) async {
          asked.add(uid);
          return AlbumFacts(
            uid: uid,
            trackSetHash: trackSetHash,
            updatedMs: 1730000000000,
            source: found(uid) ? 'MusicBrainz' : '',
            tracklist: found(uid) ? const [ChoiceTrack('1', 'Mysterons', 306)] : const [],
            failedMs: found(uid) ? null : 1730000000000,
          );
        },
        warmArt: (artist, album,
            {required expectedTracks, pinned, pinnedMbid, required roles, required settings}) async {
          warmedArt.add('$artist|$album|$expectedTracks');
        },
      );

  group('who warms', () {
    test('not a phone, not a television', () async {
      seedLibrary(['Dummy']);
      final w = warmer(found: (_) => true, enabled: false);
      await w.start();
      expect(asked, isEmpty);
      w.dispose();
    });

    test('turning it off mid-sweep stops it', () async {
      seedLibrary([for (var i = 0; i < 20; i++) 'Album$i']);
      late FactsWarmer w;
      w = FactsWarmer(
        library: library,
        settings: settings,
        mb: MusicBrainzService(),
        enabled: true,
        resolve: (album, {required uid, required trackSetHash, required mb, required settings,
            pinnedMbid, pinned, discogs}) async {
          asked.add(uid);
          if (asked.length == 2) w.stop();
          return AlbumFacts(
            uid: uid,
            trackSetHash: trackSetHash,
            source: 'MusicBrainz',
            tracklist: const [ChoiceTrack('1', 'Mysterons', 306)],
          );
        },
        warmArt: (artist, album,
            {required expectedTracks, pinned, pinnedMbid, required roles, required settings}) async {
          warmedArt.add('$artist|$album|$expectedTracks');
        },
      );

      await w.start();

      expect(asked.length, lessThan(20), reason: 'stoppen betekent stoppen, niet afmaken');
      w.dispose();
    });
  });

  group('what gets looked up', () {
    test('an album that is already known is left alone', () async {
      seedLibrary(['Dummy', 'Third']);
      final known = library.albums.firstWhere((a) => a.title == 'Dummy');
      library.facts.put(AlbumFacts(
        uid: library.uidOf(known),
        trackSetHash: library.trackSetHashFor(known),
        source: 'MusicBrainz',
        tracklist: const [ChoiceTrack('1', 'Mysterons', 306)],
      ));

      final w = warmer(found: (_) => true);
      await w.start();

      expect(asked, hasLength(1));
      expect(asked.single, library.uidOf(library.albums.firstWhere((a) => a.title == 'Third')));
      w.dispose();
    });

    test('newest first — the record that just landed is the one you are about to open', () async {
      seedLibrary(['Oud', 'Nieuw', 'Midden'],
          added: {'Oud': 1000, 'Midden': 2000, 'Nieuw': 3000});
      final w = warmer(found: (_) => true);
      await w.start();

      final titles = [
        for (final uid in asked)
          library.albums.firstWhere((a) => library.uidOf(a) == uid).title,
      ];
      expect(titles, ['Nieuw', 'Midden', 'Oud']);
      w.dispose();
    });

    test('de scans worden ook gewarmd, en onder de sleutel die de pagina straks vraagt', () async {
      // Waar het om begonnen was. De tracklijst werd al gewarmd, de hoes/achterkant/cd niet -- en
      // dat is het langzame deel. Op ANTI stond na dertig seconden op de pagina de achterkant en de
      // cd er nog niet, en kwamen ze pas op een tweede bezoek uit de schijfcache die het eerste
      // bezoek had gevuld nadat de gebruiker al was weggeklikt.
      //
      // expectedTracks zit IN de cachesleutel. Warm je onder een ander aantal, dan haalt de pagina
      // hem alsnog op en is het warmen weggegooid werk. De persing die net is opgelost telt hier
      // één nummer, dus dat is wat er moet staan -- niet het aantal bestanden.
      seedLibrary(['Dummy']); // twee bestanden, en de persing zegt één nummer
      final w = warmer(found: (_) => true);
      await w.start();

      expect(warmedArt, hasLength(1));
      expect(warmedArt.single, endsWith('|Dummy|1'),
          reason: 'het aantal van de persing, niet van de bestanden');
      w.dispose();
    });

    test('de artwork-lus wacht op de feiten in plaats van meteen op te geven', () async {
      // De race die dit blootlegde: de twee lussen lopen naast elkaar, dus de artwork-lus kan zijn
      // eerste ronde doen vóór er ook maar één tracklijst binnen is. Zonder signaal ziet hij dan
      // niets te doen, geen lopende feitenveeg, en stopt hij — voordat de feitenveeg is begonnen.
      seedLibrary(['Traag']);
      late FactsWarmer w;
      w = FactsWarmer(
        library: library,
        settings: settings,
        mb: MusicBrainzService(),
        enabled: true,
        rearmDelay: const Duration(milliseconds: 5),
        resolve: (album, {required uid, required trackSetHash, required mb, required settings,
            pinnedMbid, pinned, discogs}) async {
          // Traag, zodat de artwork-lus zeker een ronde doet met een lege feitenkast.
          await Future.delayed(const Duration(milliseconds: 120));
          asked.add(uid);
          return AlbumFacts(
            uid: uid,
            trackSetHash: trackSetHash,
            source: 'MusicBrainz',
            tracklist: const [ChoiceTrack('1', 'Mysterons', 306)],
          );
        },
        warmArt: (artist, album,
            {required expectedTracks, pinned, pinnedMbid, required roles, required settings}) async {
          warmedArt.add('$artist|$album|$expectedTracks');
        },
      );

      await w.start();

      expect(asked, hasLength(1));
      expect(warmedArt, hasLength(1),
          reason: 'de scans komen alsnog, ook al was de feitenkast bij de eerste ronde leeg');
      w.dispose();
    });

    test('een album waarvan de feiten AL klaar zijn krijgt alsnog zijn scans', () async {
      // Het gat dat de meting zichtbaar maakte. De eerste versie warmde de scans binnen de
      // feitenlus, en die lus bezoekt alleen albums die nog feiten nodig hebben. Na de eerste veeg
      // heeft bijna elk album die al, dus juist de platen waar de klacht over ging -- bekende
      // tracklijst, geen scans -- werden nooit bereikt. Bij het starten kwam er precies één map in
      // de artwork-cache en daarna niets meer.
      seedLibrary(['Bekend']);
      final a = library.albums.single;
      library.facts.put(AlbumFacts(
        uid: library.uidOf(a),
        trackSetHash: library.trackSetHashFor(a),
        source: 'MusicBrainz',
        tracklist: const [ChoiceTrack('1', 'Mysterons', 306)],
      ));

      final w = warmer(found: (_) => true);
      await w.start();

      expect(asked, isEmpty, reason: 'de feiten hoefden niet opgehaald te worden');
      expect(warmedArt, hasLength(1), reason: 'de scans wel');
      expect(w.artWarmed, 1);
      w.dispose();
    });

    test('een album zonder tracklijst krijgt ook geen scans gewarmd', () async {
      // Niets gevonden betekent dat we niet weten welke persing dit is. Dan is er geen sleutel om
      // onder te warmen, en zou het een zoekopdracht op naam worden -- precies de gok die de
      // verkeerde hoes oplevert.
      seedLibrary(['Onbekend']);
      final w = warmer(found: (_) => false);
      await w.start();

      expect(asked, hasLength(1));
      expect(warmedArt, isEmpty);
      w.dispose();
    });

    test('a single is skipped, and the sweep still ends', () async {
      // A single is never resolved by the album page either, so nothing is ever written for it —
      // leave it in and the sweep picks it again every pass, forever.
      library.tracks.add(Track(path: '/m/los.flac', title: 'Los', artist: 'X', album: ''));
      library.rebuildAlbums();

      final w = warmer(found: (_) => true);
      await w.start();

      expect(asked, isEmpty);
      expect(w.running, isFalse);
      w.dispose();
    });

    test('and it finishes', () async {
      seedLibrary(['A', 'B', 'C']);
      final w = warmer(found: (_) => true);
      await w.start();
      expect(asked, hasLength(3));
      expect(w.running, isFalse);
      expect(w.done, 3);
      w.dispose();
    });
  });

  group('when the network is gone', () {
    test('it stops instead of blinding the whole library', () async {
      seedLibrary([for (var i = 0; i < 40; i++) 'Album$i']);
      final w = warmer(found: (_) => false);

      await w.start();

      expect(asked.length, lessThanOrEqualTo(3),
          reason: 'niet veertig — drie leges op rij is een storing, geen bibliotheek vol onbekende platen');
      for (final uid in asked) {
        expect(library.facts.get(uid), isNull,
            reason: 'niets mag failedMs krijgen, anders is elk album een etmaal blind');
      }
      expect(w.running, isFalse);
      w.dispose();
    });

    test('a real answer proves the misses were real, and they are kept', () async {
      seedLibrary(['A', 'B', 'C'], added: {'C': 3000, 'B': 2000, 'A': 1000});
      // C and B find nothing, A does. Two blanks is under the outage threshold, so the two are
      // held and then written once A proves the network is there.
      final w = warmer(found: (uid) => uid == library.uidOf(library.albums.firstWhere((a) => a.title == 'A')));

      await w.start();

      for (final a in library.albums) {
        expect(library.facts.get(library.uidOf(a)), isNotNull, reason: a.title);
      }
      final b = library.albums.firstWhere((a) => a.title == 'B');
      expect(library.facts.get(library.uidOf(b))!.failedMs, isNotNull);
      w.dispose();
    });

    test('an album that found nothing is not asked twice in one session', () async {
      seedLibrary(['A', 'B']);
      final w = warmer(found: (_) => false);
      await w.start();
      final first = List.of(asked);

      await w.start();

      expect(asked, first, reason: 'geen tweede ronde over dezelfde platen');
      w.dispose();
    });
  });

  group('the switch', () {
    test('off means nothing is looked up', () async {
      seedLibrary(['A', 'B']);
      settings.warmFacts = false;
      final w = warmer(found: (_) => true);
      await w.start();
      expect(asked, isEmpty);
      w.dispose();
    });
  });
}

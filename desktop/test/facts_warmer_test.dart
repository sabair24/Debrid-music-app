/// Looking records up before they are asked for.
///
/// The loop itself is easy. What is not easy is what happens when the network goes away: a lookup
/// that finds nothing writes `failedMs` and blinds that album for twenty-four hours, and once the
/// miss cache is warm it answers instantly — so an offline sweep can march through a whole library
/// in seconds and blind all of it. That is the difference between a feature and a liability, and
/// it is what most of this file tests.
library;

import 'dart:async';
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
    // Of a lege uitkomst een STORING is of "nooit van gehoord". Alleen het eerste hoort de veeg stil
    // te leggen; het tweede is een normale bibliotheek en kwam elf keer op rij voor.
    bool brokenNetwork = false,
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
            networkFailed: !found(uid) && brokenNetwork,
          );
        },
        warmArt: (artist, album,
            {required expectedTracks, pinned, pinnedMbid, required roles, required settings, freeOnly = true, trace}) async {
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
            {required expectedTracks, pinned, pinnedMbid, required roles, required settings, freeOnly = true, trace}) async {
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

      // Op de sleutel, niet op het aantal. De stub schrijft geen done-markering, dus de
      // Discogs-naveeg ziet het album als onafgemaakt en probeert het nog eens -- wat in de echte app
      // juist klopt, want daar staat die markering er wel. Waar deze test over gaat is de sleutel.
      expect(warmedArt, isNotEmpty);
      expect(warmedArt.first, endsWith('|Dummy|1'),
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
            {required expectedTracks, pinned, pinnedMbid, required roles, required settings, freeOnly = true, trace}) async {
          warmedArt.add('$artist|$album|$expectedTracks');
        },
      );

      await w.start();

      expect(asked, hasLength(1));
      expect(warmedArt, isNotEmpty,
          reason: 'de scans komen alsnog, ook al was de feitenkast bij de eerste ronde leeg');
      w.dispose();
    });

    test('een plaat die MIDDEN in de ronde binnenkomt krijgt zijn scans in dezelfde ronde', () async {
      // "Van zodra dat een track binnen is van Soulseek moet dat instant gebeuren." De lijst waar de
      // artwork-ronde overheen loopt is een momentopname: een album dat binnenkomt terwijl die ronde
      // halverwege is, stáát er niet in. Eén ronde liet hem daardoor liggen tot een volgende
      // bibliotheekwijziging de warmer toevallig weer wakker maakte.
      seedLibrary(['Eerste']);
      var toegevoegd = false;
      late FactsWarmer w;
      w = FactsWarmer(
        library: library,
        settings: settings,
        mb: MusicBrainzService(),
        enabled: true,
        rearmDelay: const Duration(milliseconds: 5),
        resolve: (album, {required uid, required trackSetHash, required mb, required settings,
            pinnedMbid, pinned, discogs}) async {
          asked.add(uid);
          return AlbumFacts(
            uid: uid,
            trackSetHash: trackSetHash,
            source: 'MusicBrainz',
            tracklist: const [ChoiceTrack('1', 'Mysterons', 306)],
          );
        },
        warmArt: (artist, album,
            {required expectedTracks, pinned, pinnedMbid, required roles, required settings, freeOnly = true, trace}) async {
          warmedArt.add('$artist|$album|$expectedTracks');
          // De download landt terwijl de ronde bezig is met de plaat ervoor.
          if (!toegevoegd) {
            toegevoegd = true;
            library.tracks.add(track('Binnengekomen', 1));
            library.tracks.add(track('Binnengekomen', 2));
            library.rebuildAlbums();
            library.notifyListeners(); // wat een afgeronde download ook doet
          }
        },
      );

      await w.start();
      // Zo lang duurt de herwek-timer plus de veeg die eruit volgt. Niets in deze test praat met het
      // netwerk, dus als het na een tiende seconde niet gebeurd is, gebeurt het niet meer.
      await Future.delayed(const Duration(milliseconds: 100));

      expect(warmedArt.map((s) => s.split('|')[1]), contains('Binnengekomen'),
          reason: 'de plaat die tijdens de ronde binnenkwam hoort zijn scans nog te krijgen, '
              'zonder dat er iets anders in de bibliotheek verandert');
      w.dispose();
    });

    test('een plaat die blijft hangen houdt de rest van de rij niet tegen', () async {
      // Op de echte bibliotheek: "Vlaamse Diva's" stond drie kwartier op 4/29 -- geen cachebestand
      // geschreven, geen socket open naar musicbrainz.org, niets te zien. De scanronde heeft sinds
      // dag één een tijdslimiet en loopt daarom wél door; deze had er geen.
      seedLibrary(['Eerste', 'Blijft hangen', 'Derde'],
          added: {'Eerste': 3000, 'Blijft hangen': 2000, 'Derde': 1000});

      final w = FactsWarmer(
        library: library,
        settings: settings,
        mb: MusicBrainzService(),
        enabled: true,
        rearmDelay: const Duration(seconds: 30),
        factsDeadline: const Duration(milliseconds: 150),
        resolve: (album, {required uid, required trackSetHash, required mb, required settings,
            pinnedMbid, pinned, discogs}) async {
          asked.add(uid);
          if (album.title == 'Blijft hangen') {
            await Completer<void>().future; // komt nooit terug, precies zoals in het echt
          }
          return AlbumFacts(
            uid: uid,
            trackSetHash: trackSetHash,
            source: 'MusicBrainz',
            tracklist: const [ChoiceTrack('1', 'Mysterons', 306)],
          );
        },
        warmArt: (artist, album,
            {required expectedTracks, pinned, pinnedMbid, required roles, required settings, freeOnly = true, trace}) async {},
      );

      await w.start();

      final titels = [
        for (final uid in asked)
          library.albums.firstWhere((a) => library.uidOf(a) == uid).title,
      ];
      expect(titels, contains('Derde'),
          reason: 'de plaat achter de vastgelopene hoort gewoon aan de beurt te komen');
      w.dispose();
    });

    test('een schijfscan onderbreekt de ronde niet, hij zet hem stil', () async {
      // Op de echte bibliotheek ging dit elke start mis: de eerste ronde stierf vijftig seconden ver
      // op "scan=true", de naveeg van start() een milliseconde later op dezelfde vlag, en er warmde
      // niets meer tot een herwek-timer toevallig langskwam. En een afgeronde Soulseek-download IS
      // precies wat een herscan aanzet -- dus het moment waarop de scans het hardst nodig zijn was
      // het moment waarop de ronde het opgaf.
      seedLibrary(['Een', 'Twee', 'Drie']);
      for (final a in library.albums) {
        library.facts.put(AlbumFacts(
          uid: library.uidOf(a),
          trackSetHash: library.trackSetHashFor(a),
          updatedMs: 1730000000000,
          source: 'MusicBrainz',
          tracklist: const [ChoiceTrack('1', 'Mysterons', 306)],
        ));
      }

      late FactsWarmer w;
      w = FactsWarmer(
        library: library,
        settings: settings,
        mb: MusicBrainzService(),
        enabled: true,
        rearmDelay: const Duration(seconds: 30), // geen timer die dit alsnog redt
        scanWait: const Duration(seconds: 5),
        resolve: (album, {required uid, required trackSetHash, required mb, required settings,
            pinnedMbid, pinned, discogs}) async =>
            library.facts.get(uid)!,
        warmArt: (artist, album,
            {required expectedTracks, pinned, pinnedMbid, required roles, required settings, freeOnly = true, trace}) async {
          warmedArt.add('$artist|$album|$expectedTracks');
          // Na de eerste plaat begint er een scan, zoals bij een binnengekomen download.
          if (warmedArt.length == 1) {
            library.scanning = true;
            Future.delayed(const Duration(milliseconds: 600), () => library.scanning = false);
          }
        },
      );

      await w.start();

      expect(warmedArt, hasLength(3),
          reason: 'de ronde hoort na de scan gewoon verder te gaan, niet af te breken');
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
      expect(warmedArt, isNotEmpty, reason: 'de scans wel');
      expect(w.artWarmed, greaterThan(0));
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
      final w = warmer(found: (_) => false, brokenNetwork: true);

      await w.start();

      expect(asked.length, lessThanOrEqualTo(3),
          reason: 'niet veertig — drie gebroken opzoekingen op rij is een storing');
      for (final uid in asked) {
        expect(library.facts.get(uid), isNull,
            reason: 'niets mag failedMs krijgen, anders is elk album een etmaal blind');
      }
      expect(w.running, isFalse);
      w.dispose();
    });

    test('een bibliotheek vol onbekende platen legt de veeg NIET stil', () async {
      // Dit is de vastloper zoals hij zich in het echt voordeed: de teller sprong naar 15 van de 26
      // en bleef daar staan, elke run, ook een hele nacht. Elf platen die MusicBrainz noch Discogs
      // kent, achter elkaar, werden gelezen als een dode netwerkverbinding. De veeg gooide de
      // gevonden antwoorden weg, zette een nieuwe poging een uur later, en stopte -- met alles erna,
      // inclusief al het artwork, nooit bereikt.
      seedLibrary([for (var i = 0; i < 20; i++) 'Album$i']);
      final w = warmer(found: (_) => false); // niets gevonden, maar niets brak

      await w.start();

      expect(asked, hasLength(20), reason: 'alle twintig bekeken, niet gestopt na drie');
      expect(w.running, isFalse);
      w.dispose();
    });

    test('een enkele storing tussen onbekende platen legt hem ook niet stil', () async {
      // De guard mag alleen afgaan op een REEKS storingen. Eén hikje tussen platen die simpelweg
      // niet bestaan is geen storing, en de teller in de hoek moet doorlopen.
      seedLibrary([for (var i = 0; i < 12; i++) 'Album$i']);
      var n = 0;
      late FactsWarmer w;
      w = FactsWarmer(
        library: library,
        settings: settings,
        mb: MusicBrainzService(),
        enabled: true,
        rearmDelay: const Duration(milliseconds: 5),
        resolve: (album, {required uid, required trackSetHash, required mb, required settings,
            pinnedMbid, pinned, discogs}) async {
          asked.add(uid);
          final stuk = (++n == 4); // precies één gebroken opzoeking
          return AlbumFacts(
              uid: uid, trackSetHash: trackSetHash, source: '', networkFailed: stuk);
        },
        warmArt: (artist, album,
            {required expectedTracks, pinned, pinnedMbid, required roles, required settings, freeOnly = true, trace}) async {},
      );

      await w.start();

      expect(asked, hasLength(12));
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

/// De hoezen trekken zichzelf gelijk, zonder dat je elk album hoeft te openen.
///
/// **Wat hier half af was.** Een hoes mét aangewezen persing gaat vóór de hoes die in de bestanden
/// zit — dat is wat `adoptAlbumCover` doet met een `from`. Maar die toeëigening gebeurde alleen in
/// `AlbumArt._load`, en dat widget leeft op de albumpagina. Een plaat kwam dus pas op zijn plek als
/// je hem één keer opende, en met 336 albums is dat geen reparatie maar een lijst huiswerk.
///
/// De achtergrondverwarmer loopt precies diezelfde platen al af en haalt precies dezelfde scans op.
/// Hij gooide het antwoord alleen weg.
///
/// **Waarom dit een toets waard is.** Het verschil tussen "hij neemt de hoes over" en "hij neemt de
/// hoes over en zet hem vóór de bestanden" is met het oog niet na te kijken: in beide gevallen zie je
/// op de albumpagina de goede hoes. Pas op Start blijkt of het gelukt is, en pas na een herstart of
/// het ook bleef. Dat is precies de soort fout die deze app twee keer op rij gemaakt heeft.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/album_facts.dart';
import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/facts_warmer.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Onderscheidbaar, en ruim boven de ondergrens van 500 bytes die `adoptAlbumCover` aanhoudt.
Uint8List bytesVan(int vulling) => Uint8List.fromList(List.filled(2000, vulling));

void main() {
  late Directory krab;
  late LibraryStore library;
  late AppSettings settings;

  /// De hoes die in de BESTANDEN zit — bij een verkeerd getagde rip is dat de verkeerde plaat.
  final uitDeBestanden = bytesVan(11);

  /// Wat de verwarmer vindt.
  final gevonden = bytesVan(22);

  setUp(() {
    krab = Directory.systemTemp.createTempSync('dm_overname_');
    setAppDirForTest(krab.path);
    settings = AppSettings();
    library = LibraryStore()
      ..configDirOverride = krab.path
      ..rootPath = krab.path;
    for (var i = 1; i <= 2; i++) {
      library.tracks.add(Track(
        path: '${krab.path}${Platform.pathSeparator}$i.flac',
        title: 'nr $i',
        artist: 'Céline Dion',
        album: "D'Eux",
        trackNo: i,
      ));
    }
    library.rebuildAlbums();
    library.albums.single.embeddedCover = uitDeBestanden;
  });

  tearDown(() {
    // Windows houdt na een schrijfactie nog even een handvat open; opruimen mag geen toets laten
    // zakken.
    try {
      krab.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// De plaat waar het om gaat. Een functie en geen getter: binnen een functielichaam mag geen
  /// getter gedeclareerd worden.
  Album plaat() => library.albums.single;

  /// Een verwarmer die [antwoord] teruggeeft voor elke plaat.
  ///
  /// De feiten worden vooraf neergezet, want zonder tracklijst slaat de verwarmer een album over —
  /// hij wacht dan op de feitenveeg. Dat is bestaand gedrag en geen onderdeel van wat hier getoetst
  /// wordt.
  FactsWarmer verwarmer(ReleaseArt? antwoord) {
    final uid = library.uidOf(plaat());
    library.facts.put(AlbumFacts(
      uid: uid,
      trackSetHash: library.trackSetHashFor(plaat()),
      source: 'MusicBrainz',
      tracklist: const [ChoiceTrack('1', 'Pour que tu m’aimes encore', 260)],
    ));
    return FactsWarmer(
      library: library,
      settings: settings,
      mb: MusicBrainzService(),
      enabled: true,
      rearmDelay: const Duration(milliseconds: 20),
      resolve: (a, {required uid, required trackSetHash, required mb, required settings,
              pinnedMbid, pinned, discogs}) async =>
          AlbumFacts(
        uid: uid,
        trackSetHash: trackSetHash,
        source: 'MusicBrainz',
        tracklist: const [ChoiceTrack('1', 'Pour que tu m’aimes encore', 260)],
      ),
      warmArt: (artist, alb, {required expectedTracks, pinned, pinnedMbid, required roles,
              required settings, freeOnly = true, trace}) async =>
          antwoord,
    );
  }

  test('een hoes MET persing gaat vóór de hoes in de bestanden', () async {
    // Het geval waar dit allemaal om begonnen is. D'Eux, van Soulseek, draagt de hoes van een
    // verzamelaar in zijn bestanden. De verwarmer vindt de echte en zegt van welke persing.
    final w = verwarmer(ReleaseArt(front: gevonden, bron: 'mb:0f5be2b5'));
    await w.start();
    w.dispose();

    expect(plaat().resolvedCover, gevonden);
    expect(plaat().resolvedFrom, 'mb:0f5be2b5');
    expect(plaat().cover, gevonden, reason: 'dit is wat er op Start staat');
    expect(w.hoezenOvergenomen, 1);
  });

  test('een hoes ZONDER persing wint niet, en dat is het hele punt', () async {
    // De belangrijkste van de vijf. Een treffer op naam is een gok, geen feit over de plaat — die
    // hoort in `enriched` te landen en van de bestanden te verliezen. Zou hij tóch voorgaan, dan
    // overschrijft één slechte match een hoes die gewoon goed was, op schijf, voorgoed.
    final w = verwarmer(ReleaseArt(front: gevonden));
    await w.start();
    w.dispose();

    expect(plaat().resolvedCover, isNull);
    expect(plaat().enriched, gevonden);
    expect(plaat().cover, uitDeBestanden, reason: 'de bestanden winnen van een gok');
    expect(w.hoezenOvergenomen, 0, reason: 'er is niets veranderd aan wat je ziet');
  });

  test('een hoes die je zelf koos blijft staan', () async {
    final eigen = bytesVan(33);
    plaat().correctedCover = eigen;

    final w = verwarmer(ReleaseArt(front: gevonden, bron: 'mb:0f5be2b5'));
    await w.start();
    w.dispose();

    expect(plaat().cover, eigen);
    expect(plaat().resolvedCover, isNull, reason: 'een eigen keuze wordt niet overschreven');
  });

  test('een leeg antwoord verandert niets', () async {
    // Geen scans gevonden is geen reden om iets te doen. Zou hier een lege overname geteld worden,
    // dan zegt het getal in het logboek niets meer.
    final w = verwarmer(const ReleaseArt());
    await w.start();
    w.dispose();

    expect(plaat().cover, uitDeBestanden);
    expect(w.hoezenOvergenomen, 0);
  });

  test('geen antwoord verandert ook niets', () async {
    final w = verwarmer(null);
    await w.start();
    w.dispose();

    expect(plaat().cover, uitDeBestanden);
    expect(w.hoezenOvergenomen, 0);
  });

  test('alleen een achterkant is geen hoes', () async {
    // `bron` hoort bij de VOORKANT. Een persing die alleen een achterkant leverde zegt niets over
    // de hoes die straks op Start staat, en mag daar dus ook niets aan veranderen.
    final w = verwarmer(ReleaseArt(back: gevonden, bron: 'mb:0f5be2b5'));
    await w.start();
    w.dispose();

    expect(plaat().cover, uitDeBestanden);
    expect(w.hoezenOvergenomen, 0);
  });
}

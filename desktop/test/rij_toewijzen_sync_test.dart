/// "Nummers toewijzen" moet ook op de telefoon en de Mac werken, niet alleen op de pc.
///
/// **Wat er misging, gemeld op 06-09-2026.** Saber: *"nummers wijzen werkt enkel op pc, moet ook
/// werken op de andere platforms, uitgenomen shield tv niet."* De knop stónd er — hij is alleen op
/// een tv verborgen — maar er ontbraken twee dingen, en allebei zijn ze stil:
///
///   * De client verstuurde een bewerking `assignRow` die op de pc **niet bestond**. Die belandde in
///     de `default` van de opdrachtenlijst en kwam terug als "Onbekende bewerking". Je sleepte een
///     nummer naar een rij en er gebeurde niets.
///   * En zelfs als hij had bestaan: de keuze staat in `corrections.json` op de PC, en een telefoon
///     leest zijn eigen lege exemplaar. Er was geen veld in de catalogus, dus kwam de toewijzing
///     nooit terug op het scherm dat erom vroeg.
///
/// Dezelfde twee kanten als bij de scanrollen, en om dezelfde reden allebei nodig: aankomen én
/// terugkomen. Deze toets doet ze over een echte server en een echte HTTP-ronde, want dat is waar
/// het bij beide de vorige keer op stukliep.
library;

import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/completeness.dart';
import 'package:debridmusic/editions.dart';
import 'package:debridmusic/lan/dtos.dart';
import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/tokens.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  late Directory krab;
  late Directory wortel;
  late LibraryStore library;
  late LanServer server;
  late Uri basis;
  late String padA;
  late String padB;

  const token = 'toets-token';
  const artiest = 'James Brown';
  const titel = 'The Best Of';

  /// De uitgave zoals de albumpagina hem toont: twee rijen die op elkaar lijken.
  const uitgave = [
    ChoiceTrack('1', 'I Got You (I Feel Good)', 167),
    ChoiceTrack('2', 'Get Up (I Feel Like Being a) Sex Machine, Pt. 1', 316),
  ];

  setUp(() async {
    krab = Directory.systemTemp.createTempSync('dm_rij_');
    setAppDirForTest(krab.path);
    wortel = Directory.systemTemp.createTempSync('dm_rij_muziek_');
    final map = Directory('${wortel.path}/$artiest/$titel')..createSync(recursive: true);
    padA = '${map.path}/01.flac';
    padB = '${map.path}/02.flac';
    for (final p in [padA, padB]) {
      File(p).writeAsBytesSync(const [1, 2, 3, 4]);
    }

    library = LibraryStore()
      ..rootPath = wortel.path
      ..configDirOverride = wortel.path;
    library.tracks
      ..add(Track(
        path: padA,
        title: 'Get Up (I Feel Like Being a) Sex Machine',
        artist: artiest,
        album: titel,
        trackNo: 1,
        isFlac: true,
        sizeBytes: 4,
        duration: const Duration(seconds: 316),
      ))
      ..add(Track(
        path: padB,
        title: 'I Got You',
        artist: artiest,
        album: titel,
        trackNo: 2,
        isFlac: true,
        sizeBytes: 4,
        duration: const Duration(seconds: 167),
      ));
    library.rebuildAlbums();

    server = LanServer(
      library: library,
      token: token,
      settings: AppSettings(),
      state: LanStateStore(File('${wortel.path}/state.json')),
      pairing: PairingStore(),
      port: 0,
      grants: GrantStore(file: File('${krab.path}/grants.json')),
    );
    expect(await server.start(), isNull);
    basis = Uri.parse('http://127.0.0.1:${server.boundPort}');
  });

  tearDown(() async {
    await server.dispose();
    wortel.deleteSync(recursive: true);
    krab.deleteSync(recursive: true);
  });

  Future<http.Response> bewerk(Map<String, dynamic> op) => http.post(
        basis.replace(path: '/api/corrections'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode(op),
      );

  Future<({List<TrackDto> tracks, String? etag})> catalogus() async {
    final res = await http.get(basis.replace(path: '/api/catalog'),
        headers: {'Authorization': 'Bearer $token'});
    expect(res.statusCode, 200);
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (
      tracks: [for (final t in (j['tracks'] as List)) TrackDto.fromJson(t as Map<String, dynamic>)],
      etag: res.headers['etag'],
    );
  }

  test('DE KERN: een toewijzing van een ander toestel komt aan én komt terug', () async {
    final voor = await catalogus();
    expect(voor.tracks.every((t) => t.rij == null), isTrue,
        reason: 'zonder keuze hoort er niets te staan');

    // Het nummer dat op rij 2 hoort, met de id die de PC zelf heeft uitgegeven — precies wat een
    // telefoon meestuurt, want daar heet dit bestand een stream-URL.
    final sexMachine = voor.tracks.firstWhere((t) => t.title.startsWith('Get Up'));

    final res = await bewerk({
      'op': 'assignRows',
      'rows': [
        {'trackId': sexMachine.id, 'row': rijSleutel(uitgave[1])},
      ],
    });
    expect(res.statusCode, 200, reason: 'de pc hoort deze bewerking te kennen: ${res.body}');

    final na = await catalogus();
    final terug = na.tracks.firstWhere((t) => t.id == sexMachine.id);
    expect(terug.rij, rijSleutel(uitgave[1]),
        reason: 'zonder dit veld ziet een telefoon nooit terug wat ze zelf aanwees');
    expect(na.etag, isNot(voor.etag),
        reason: 'beweegt de ETag niet, dan krijgt elk toestel een 304 en hoort het nooit dat er '
            'iets veranderd is');
  });

  test('en dan legt de albumpagina het bestand ook echt op die rij', () async {
    // De hele reden dat dit venster bestaat: de twee rijen lijken op elkaar, en JOUW keuze gaat
    // vóór elke automatische vergelijking.
    final voor = await catalogus();
    final sexMachine = voor.tracks.firstWhere((t) => t.title.startsWith('Get Up'));
    await bewerk({
      'op': 'assignRows',
      'rows': [
        {'trackId': sexMachine.id, 'row': rijSleutel(uitgave[1])},
      ],
    });

    final album = library.albums.single;
    final c = matchAlbumTracks(uitgave, album.tracks, album.artist,
        album: album.title, handmatig: library.rijToewijzingen(album.tracks));
    expect(c.slots[1].track?.path, padA);
  });

  test('een lege rij geeft de beslissing terug aan de app', () async {
    final voor = await catalogus();
    final sexMachine = voor.tracks.firstWhere((t) => t.title.startsWith('Get Up'));
    await bewerk({
      'op': 'assignRows',
      'rows': [
        {'trackId': sexMachine.id, 'row': rijSleutel(uitgave[1])},
      ],
    });
    expect((await catalogus()).tracks.firstWhere((t) => t.id == sexMachine.id).rij, isNotNull);

    await bewerk({
      'op': 'assignRows',
      'rows': [
        {'trackId': sexMachine.id, 'row': null},
      ],
    });
    expect((await catalogus()).tracks.firstWhere((t) => t.id == sexMachine.id).rij, isNull);
  });

  test('meer dan één in één ronde, want dat is wat de opslaanknop stuurt', () async {
    final voor = await catalogus();
    final a = voor.tracks.firstWhere((t) => t.title.startsWith('Get Up'));
    final b = voor.tracks.firstWhere((t) => t.title.startsWith('I Got You'));

    final res = await bewerk({
      'op': 'assignRows',
      'rows': [
        {'trackId': a.id, 'row': rijSleutel(uitgave[1])},
        {'trackId': b.id, 'row': rijSleutel(uitgave[0])},
      ],
    });
    expect(res.statusCode, 200);

    final na = await catalogus();
    expect(na.tracks.firstWhere((t) => t.id == a.id).rij, rijSleutel(uitgave[1]));
    expect(na.tracks.firstWhere((t) => t.id == b.id).rij, rijSleutel(uitgave[0]));
  });

  test('DE VAL: er wordt GEEN albumId meegestuurd, en dat mag geen 404 geven', () async {
    // Een toewijzing hangt aan bestanden, niet aan een album — net als hernummeren en verwijderen.
    // Zonder de uitzondering op de albumcontrole geeft de pc hier "Dat album staat hier niet (meer)"
    // terug, en dan is er niets aan te zien behalve dat er niets gebeurt.
    final voor = await catalogus();
    final res = await bewerk({
      'op': 'assignRows',
      'rows': [
        {'trackId': voor.tracks.first.id, 'row': rijSleutel(uitgave[0])},
      ],
    });
    expect(res.statusCode, 200, reason: res.body);
  });

  test('en een onbekend nummer levert een nette weigering, geen stilte', () async {
    final res = await bewerk({
      'op': 'assignRows',
      'rows': [
        {'trackId': 'bestaat-niet', 'row': 'x'},
      ],
    });
    expect(res.statusCode, HttpStatus.badRequest);
  });
}

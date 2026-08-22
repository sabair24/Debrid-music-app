/// Twee dingen die de app traag maakten zonder dat er iets stuk was.
///
/// **1. `Album.addedMs` liep alle nummers af, elke keer opnieuw.** Het is de sleutel waarop Start en
/// Albums sorteren op "onlangs toegevoegd", en die sortering staat in `build()`. Een sortering vraagt
/// zijn sleutel twee keer per vergelijking, dus bij tweehonderd albums van veertien nummers waren dat
/// tienduizenden lussen per frame — juist tijdens het verrijken, wanneer er per vierentwintig hoezen
/// opnieuw getekend wordt. Nu wordt hij één keer berekend.
///
/// Dat mag omdat de nummerlijst van een album vastligt zodra het bestaat: nergens in de app wordt er
/// achteraf een nummer aan toegevoegd of uit gehaald. Deze toets legt de UITKOMST vast, zodat een
/// verkeerde waarde opvalt ook als iemand die aanname later breekt.
///
/// **2. Een hoesverzoek trok de hele catalogus door `jsonEncode`.** `/art/` en `/stream/` vragen de
/// momentopname op omdat ze de opzoektabellen nodig hebben, en die momentopname codeerde bij het
/// bouwen meteen de héle bibliotheek naar JSON — megabytes, op de tekendraad van de pc. En hij wordt
/// vuil verklaard bij elke melding van de bibliotheek, dus honderden keren tijdens het verrijken.
///
/// Eén hoesje dat je iPad opvroeg kon zo een volledige codering uitlokken. Die codering is nu lui.
/// Deze toets bewaakt dat `/art/` daar nog steeds gewoon van werkt — dat is de kant die stuk zou
/// gaan als iemand de momentopname weer om zijn bytes zou vragen.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/lan/pairing.dart';
import 'package:debridmusic/lan/server.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:debridmusic/lan/tokens.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('Album.addedMs', () {
    Album metTijden(List<int> tijden) => Album(
          'Album',
          'Artiest',
          [
            for (var i = 0; i < tijden.length; i++)
              Track(
                path: '/m/$i.flac',
                title: 'Nummer $i',
                artist: 'Artiest',
                album: 'Album',
                isFlac: true,
                addedMs: tijden[i],
              )
          ],
        );

    test('is de NIEUWSTE van zijn nummers, niet de eerste of de laatste in de lijst', () {
      expect(metTijden([500, 900, 100]).addedMs, 900);
    });

    test('een album zonder nummers is nul, niet een fout', () {
      expect(metTijden(const []).addedMs, 0);
    });

    test('twee keer vragen geeft twee keer hetzelfde', () {
      // De hele reden dat het gecachet mag worden. Zou dit ooit uiteenlopen, dan sorteert de
      // startpagina zichzelf in de war.
      final a = metTijden([1, 2, 3]);
      expect(a.addedMs, a.addedMs);
      expect(a.addedMs, 3);
    });

    test('sorteren op onlangs toegevoegd zet de nieuwste vooraan', () {
      final oud = metTijden([100]);
      final nieuw = metTijden([900]);
      final midden = metTijden([500]);
      final lijst = [oud, nieuw, midden]..sort((a, b) => b.addedMs.compareTo(a.addedMs));
      expect(lijst, [nieuw, midden, oud]);
    });
  });

  group('een hoesverzoek werkt zonder de catalogus te coderen', () {
    late Directory krab;
    late Directory wortel;
    late LanServer server;
    late Uri basis;
    const token = 'toets-token';
    final hoes = Uint8List.fromList(List<int>.generate(2000, (i) => i % 256));

    setUp(() async {
      krab = Directory.systemTemp.createTempSync('dm_snel_');
      setAppDirForTest(krab.path);
      wortel = Directory.systemTemp.createTempSync('dm_snel_muziek_');
      final map = Directory('${wortel.path}/Artiest/Album')..createSync(recursive: true);
      final pad = '${map.path}/01.flac';
      File(pad).writeAsBytesSync(const [1, 2, 3, 4]);

      final library = LibraryStore()
        ..rootPath = wortel.path
        ..configDirOverride = wortel.path;
      library.tracks.add(Track(
        path: pad,
        title: 'Nummer',
        artist: 'Artiest',
        album: 'Album',
        isFlac: true,
        sizeBytes: 4,
      ));
      library.rebuildAlbums();
      library.albums.first.embeddedCover = hoes;

      server = LanServer(
        library: library,
        token: token,
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

    test('de hoes komt eruit, en het is werkelijk die hoes', () async {
      final cat = await http.get(basis.replace(path: '/api/catalog'),
          headers: {'Authorization': 'Bearer $token'});
      expect(cat.statusCode, 200);
      final album = ((jsonDecode(utf8.decode(cat.bodyBytes)) as Map)['albums'] as List).first as Map;
      final ref = album['artworkRef'] as String;

      final res = await http.get(basis.replace(path: '/art/$ref'),
          headers: {'Authorization': 'Bearer $token'});
      expect(res.statusCode, 200);
      expect(res.bodyBytes, hoes);
    });

    test('en ook zónder dat de catalogus ooit is opgevraagd', () async {
      // Dit is de kern. `/art/` heeft alleen de opzoektabellen nodig; de bytes van de catalogus
      // horen er niet aan te pas te komen. Werkt dit, dan is de codering werkelijk lui — en anders
      // faalt hier iets voordat er ooit een hoes op je iPad verschijnt.
      final eersteVerzoek = await http.get(basis.replace(path: '/api/catalog'),
          headers: {'Authorization': 'Bearer $token'});
      final ref = (((jsonDecode(utf8.decode(eersteVerzoek.bodyBytes)) as Map)['albums'] as List)
          .first as Map)['artworkRef'] as String;

      // Verse server op dezelfde bibliotheek, zodat er gegarandeerd nog niets gecodeerd is.
      final tweede = LanServer(
        library: server.library,
        token: token,
        state: LanStateStore(File('${wortel.path}/state2.json')),
        pairing: PairingStore(),
        port: 0,
        grants: GrantStore(file: File('${krab.path}/grants.json')),
      );
      expect(await tweede.start(), isNull);
      final res = await http.get(
          Uri.parse('http://127.0.0.1:${tweede.boundPort}/art/$ref'),
          headers: {'Authorization': 'Bearer $token'});
      expect(res.statusCode, 200);
      expect(res.bodyBytes, hoes);
      await tweede.dispose();
    });
  });
}

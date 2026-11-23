// Een AI-lijst in de gedeelde winkel (Saber, 23-11-2026): het voorstel met de regels die nog niet gehaald zijn, naast de
// nummers die je al hebt. Een toestel dat het veld niet kent, ziet een gewone lijst met je eigen nummers.
import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/ai_lijst.dart';
import 'package:debridmusic/lan/state_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late LanStateStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dm_ailijst_');
    store = LanStateStore(File('${dir.path}/state.json'));
  });

  tearDown(() async {
    await store.dispose();
    dir.deleteSync(recursive: true);
  });

  Map<String, dynamic> voorstel(String naam) => AiLijstVoorstel(
        naam: naam,
        zin: '200 kerstliedjes',
        hoeken: const [(naam: 'Klassiekers', aandeel: 60), (naam: 'Modern', aandeel: 40)],
        nummers: [
          LijstNummer(artiest: 'Bing Crosby', titel: 'White Christmas', bron: LijstBron.eigen, eigenId: 'eigen1'),
          LijstNummer(artiest: 'Mariah Carey', titel: 'All I Want for Christmas Is You', bron: LijstBron.deezer, deezerId: 7),
        ],
        reserve: [LijstNummer(artiest: 'Wham!', titel: 'Last Christmas')],
      ).toJson();

  test('DE KERN: playlist.ai bewaart het voorstel, de naam en je eigen nummers — en overleeft de schijf', () async {
    store.applyOps([
      {'type': 'playlist.create', 'id': 'p1', 'name': 'Nieuwe lijst', 'trackIds': <String>[], 'at': 1},
      {'type': 'playlist.ai', 'id': 'p1', 'ai': voorstel('Kerst'), 'name': 'Kerst', 'trackIds': ['eigen1'], 'at': 2},
    ]);
    await store.save();
    final weer = LanStateStore(File('${dir.path}/state.json'));
    await weer.load();
    final p = weer.playlists['p1']!;
    expect(p.name, 'Kerst');
    expect(p.trackIds, ['eigen1']);
    final v = AiLijstVoorstel.fromJson(p.ai)!;
    expect(v.nummers.map((n) => n.titel), ['White Christmas', 'All I Want for Christmas Is You']);
    expect(v.nummers.last.deezerId, 7);
    expect(v.reserve.single.artiest, 'Wham!');
    await weer.dispose();
  });

  test('laatste schrijver wint, zoals setTracks; een gewone lijst heeft geen ai-veld', () {
    store.applyOps([
      {'type': 'playlist.create', 'id': 'p1', 'name': 'x', 'trackIds': <String>[], 'at': 1},
      {'type': 'playlist.ai', 'id': 'p1', 'ai': voorstel('Nieuw'), 'name': 'Nieuw', 'at': 5},
      {'type': 'playlist.ai', 'id': 'p1', 'ai': voorstel('Oud'), 'name': 'Oud', 'at': 3},
      {'type': 'playlist.create', 'id': 'p2', 'name': 'gewoon', 'trackIds': ['a'], 'at': 1},
    ]);
    expect(store.playlists['p1']!.name, 'Nieuw', reason: 'een oudere bewerking van een toestel dat uit stond, telt niet');
    expect(store.playlists['p2']!.ai, isNull);
    expect(store.playlists['p2']!.toJson().containsKey('ai'), isFalse);
  });

  test('een oud toestel leest dezelfde lijst als een gewone: alleen trackIds, en het ai-veld stoort niet', () {
    final p = Playlist(id: 'p', name: 'Kerst', trackIds: ['eigen1'], updatedAt: 1, ai: voorstel('Kerst'));
    final ruw = jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>;
    // Zoals de oude fromJson: alleen de bekende velden.
    final trackIds = [for (final t in (ruw['trackIds'] as List)) t.toString()];
    expect(trackIds, ['eigen1']);
    expect(ruw['ai'], isA<Map>());
  });
}

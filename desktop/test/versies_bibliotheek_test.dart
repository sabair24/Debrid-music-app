// Versies in de bibliotheek, de catalogus en op een toestel (Saber, 26-10-2026): één tegel, de versies bij het nummer.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/kopiesoort.dart';
import 'package:debridmusic/lan/catalog.dart';
import 'package:debridmusic/lan/client.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/main.dart' show plaatversies;
import 'package:debridmusic/models.dart';
import 'package:debridmusic/versies.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _flac({required int hz, required int bits, int sec = 200, required Map<String, String> tags}) {
  final out = BytesBuilder()..add(ascii.encode('fLaC'));
  void blok(int type, List<int> body, bool laatste) {
    out.add([(laatste ? 0x80 : 0) | type, (body.length >> 16) & 0xFF, (body.length >> 8) & 0xFF, body.length & 0xFF]);
    out.add(body);
  }

  final si = Uint8List(34);
  final totaal = hz * sec;
  si[10] = (hz >> 12) & 0xFF;
  si[11] = (hz >> 4) & 0xFF;
  si[12] = ((hz & 0x0F) << 4) | (1 << 1) | (((bits - 1) >> 4) & 1);
  si[13] = (((bits - 1) & 0x0F) << 4) | ((totaal >> 32) & 0x0F);
  si[14] = (totaal >> 24) & 0xFF;
  si[15] = (totaal >> 16) & 0xFF;
  si[16] = (totaal >> 8) & 0xFF;
  si[17] = totaal & 0xFF;
  blok(0, si, false);
  final b = BytesBuilder();
  void u32(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  final ven = utf8.encode('reference libFLAC 1.4.3');
  u32(ven.length);
  b.add(ven);
  u32(tags.length);
  for (final e in tags.entries) {
    final c = utf8.encode('${e.key}=${e.value}');
    u32(c.length);
    b.add(c);
  }
  blok(4, b.toBytes(), false);
  blok(1, List.filled(64, 0), true);
  out.add(List.filled(4096, 0x5A));
  return out.toBytes();
}

void main() {
  late Directory root, config;
  late String sep, anker1, anker2, vinyl1;

  void schrijf(String pad, {required int hz, required int bits, required Map<String, String> tags}) {
    final f = File(pad)..parent.createSync(recursive: true);
    f.writeAsBytesSync(_flac(hz: hz, bits: bits, tags: tags));
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('dm_versies_bib_');
    config = Directory.systemTemp.createTempSync('dm_versies_bib_cfg_');
    sep = Platform.pathSeparator;
    final map = '${root.path}${sep}Albums${sep}Spice Girls${sep}Spice';
    anker1 = '$map${sep}01 - Wannabe.flac';
    anker2 = '$map${sep}02 - Say You Will Be There.flac';
    vinyl1 = '$map (vinyl LP 1996)${sep}01 - Wannabe.flac';
    final tags = {'ARTIST': 'Spice Girls', 'ALBUM': 'Spice', 'DATE': '1996'};
    schrijf(anker1, hz: 44100, bits: 16, tags: {...tags, 'TITLE': 'Wannabe', 'TRACKNUMBER': '1'});
    schrijf(anker2, hz: 44100, bits: 16, tags: {...tags, 'TITLE': 'Say You Will Be There', 'TRACKNUMBER': '2'});
    schrijf(vinyl1,
        hz: 96000, bits: 24, tags: {...tags, 'ALBUM': 'Spice (vinyl LP 1996)', 'TITLE': 'Wannabe', 'TRACKNUMBER': '1'});
    versies.wis();
    resetSoortenVoorToets();
    versies.voegToe(anker1,
        Versie(pad: vinyl1, soort: Kopiesoort.vinyl, persing: 'LP 1996', sindsMs: DateTime.now().millisecondsSinceEpoch,
            verschuivingMs: 1830, snelheid: 1.0015),
        ankerSoort: Kopiesoort.cd);
  });
  tearDown(() {
    versies.wis();
    resetSoortenVoorToets();
    root.deleteSync(recursive: true);
    config.deleteSync(recursive: true);
  });

  Future<LibraryStore> pc() async {
    final lib = LibraryStore()
      ..configDirOverride = config.path
      ..rootPath = root.path;
    await lib.scan();
    return lib;
  }

  test('DE KERN: een versie hoort bij geen album — één tegel, en de versie staat bij het nummer', () async {
    final lib = await pc();
    expect(lib.tracks.map((t) => t.title), unorderedEquals(['Wannabe', 'Say You Will Be There']),
        reason: 'de vinylrip is geen eigen nummer, ook al staat hij in de bibliotheek');
    expect(lib.albums, hasLength(1), reason: 'geen tweede tegel "Spice (vinyl LP 1996)"');
    final t = lib.trackByPath(anker1)!;
    final vs = lib.versiesVan(t);
    expect([for (final v in vs) v.label], ['CD · 16/44.1', 'Vinyl · LP 1996 · 24/96']);
    expect(vs.first.anker && vs.first.standaard, isTrue, reason: 'zonder keuze: het nummer zelf');
    expect(vs.last.verschuivingMs, 1830);
    expect(lib.trackByPath(vinyl1)?.bitsPerSample, 24, reason: 'de speler vraagt de luidheid van de versie op');
    expect(lib.versiesVan(lib.trackByPath(anker2)!), isEmpty);
    expect(lib.metVersies, hasLength(3), reason: 'gelijk volume meet de versie ook');
  });

  test('kiezen: de standaard verschuift, en wat er speelt volgt', () async {
    final lib = await pc();
    final t = lib.trackByPath(anker1)!;
    expect(lib.speelPadVoor(anker1), anker1);
    versies.kies(anker1, versieSleutel(Kopiesoort.vinyl, 'LP 1996'), bereik: VersieBereik.plaat);
    expect(lib.speelPadVoor(anker1), vinyl1);
    expect(lib.versiesVan(t).firstWhere((v) => v.standaard).track.path, vinyl1);
    expect(lib.speelPadVoor(anker2), anker2, reason: 'zonder vinylversie speelt het nummer zelf');
  });

  test('nieuwe versies op Start, en Recent toegevoegd blijft de dag dat de plaat binnenkwam', () async {
    final lib = await pc();
    final nv = lib.nieuweVersies();
    expect(nv.single.album.title, 'Spice');
    expect(nv.single.label, 'vinyl LP 1996');
    expect(lib.nieuweVersies(nu: DateTime.now().add(const Duration(days: 31))), isEmpty);
    // Een opgewaardeerd nummer krijgt vandaag een nieuwe tijd; de plaat blijft zo oud als ze is.
    final oud = DateTime(2024, 3, 1);
    File(anker2).setLastModifiedSync(oud);
    File(anker1).setLastModifiedSync(DateTime.now());
    await lib.scan();
    expect(lib.albums.single.addedMs, oud.millisecondsSinceEpoch);
  });

  test('DE KERN: de catalogus geeft de versies mee, en een toestel kent ze daarna', () async {
    final lib = await pc();
    final catalog = LanCatalog(lib);
    final snap = catalog.snapshot();
    final dto = snap.catalog.tracks.firstWhere((d) => d.title == 'Wannabe');
    final v = (dto.versies!['lijst'] as List).single as Map;
    expect(v['s'], 'vinyl');
    expect(v['p'], 'LP 1996');
    expect(v['v'], 1830);
    expect(snap.trackById[v['id']]?.path, vinyl1, reason: 'speelbaar onder een eigen id, via /stream/');
    expect(dto.versies!['s'], 'cd');
    expect(dto.versies!.containsKey('kies'), isFalse);
    final etag = snap.etag;
    versies.kies(anker1, versieSleutel(Kopiesoort.vinyl, 'LP 1996'), bereik: VersieBereik.nummer);
    final na = catalog.snapshot();
    expect(na.etag, isNot(etag), reason: 'een keuze verandert geen nummer — zonder dit hoort geen toestel ervan');
    expect(na.catalog.tracks.firstWhere((d) => d.title == 'Wannabe').versies!['kies'], v['id']);

    final gsm = LibraryStore()
      ..remote = RemoteClient(RemoteEndpoint(baseUrl: Uri.parse('http://192.168.0.117:47820'), token: 't'));
    expect(gsm.adoptMirror(jsonDecode(utf8.decode(na.json)) as Map<String, dynamic>), isTrue);
    expect(gsm.tracks, hasLength(2));
    final t = gsm.tracks.firstWhere((x) => x.title == 'Wannabe');
    final vs = gsm.versiesVan(t);
    expect([for (final x in vs) x.label], ['CD · 16/44.1', 'Vinyl · LP 1996 · 24/96']);
    expect(gsm.speelPadVoor(t.path), vs.last.track.path, reason: 'de keuze van de pc');
    expect(gsm.speelPadVoor(t.path), contains('/stream/'));
    expect(gsm.trackByPath(vs.last.track.path)?.sampleRate, 96000);
    expect(soortVoor(vs.last.track.path)?.soort, Kopiesoort.vinyl, reason: 'het label naast de kwaliteit in Nu speelt');
    expect(gsm.nieuweVersies().single.label, 'vinyl LP 1996');
  });

  test('het blok op de albumpagina: per soort, met hoeveel nummers', () async {
    final lib = await pc();
    final a = lib.albums.single;
    final pv = plaatversies(a.tracks, lib.versiesVan);
    expect([for (final x in pv) '${x.soort?.naam} ${x.persing} ${x.nummers} ${x.standaard}'], ['cd  1 1', 'vinyl LP 1996 1 0']);
    expect(pv.first.anker, isTrue);
    expect(pv.last.kwaliteit, {'24/96'});
  });

  test('wordt het nummer weggegooid, dan wordt de beste versie het nummer (en komt hij weer in beeld)', () async {
    final lib = await pc();
    File(anker1).deleteSync();
    await lib.scan();
    expect(versies.isVersie(vinyl1), isFalse);
    expect(lib.tracks.map((t) => t.path), contains(vinyl1));
  });

  test('alleen een album met versies krijgt het blok; [Track] blijft het anker in de rij', () {
    final t = Track(path: 'x', title: 'x', artist: 'y', album: 'z');
    expect(plaatversies([t], (_) => const []), isEmpty);
  });

  test('DE KERN: hoogstens drie regels — studio, cd, vinyl — wat er ook in de albummap staat (Saber 27-10-2026)', () {
    // Discovery toonde er negen: per persing een regel, en de cd twee keer (als nummer en als versie).
    Track t(String n) => Track(path: n, title: n, artist: 'Daft Punk', album: 'Discovery');
    final a = t('a'), b = t('b'), c = t('c');
    VersieInfo vi(String pad, Kopiesoort s, {String persing = '', bool anker = false}) =>
        VersieInfo(track: t(pad), soort: s, persing: persing, anker: anker, standaard: anker);
    final lijsten = {
      'a': [vi('a', Kopiesoort.studio, anker: true), vi('a-cd', Kopiesoort.cd), vi('a-v', Kopiesoort.vinyl, persing: 'LP 2001')],
      'b': [vi('b', Kopiesoort.cd, anker: true), vi('b-v', Kopiesoort.vinyl, persing: 'LP 2021')],
      'c': [vi('c', Kopiesoort.cd, anker: true), vi('c-v', Kopiesoort.vinyl, persing: 'LP 2001')],
    };
    final pv = plaatversies([a, b, c], (x) => lijsten[x.path]!);
    expect([for (final x in pv) x.soort], [Kopiesoort.studio, Kopiesoort.cd, Kopiesoort.vinyl]);
    expect([for (final x in pv) x.nummers], [1, 3, 3]);
    expect(pv[1].anker, isFalse, reason: 'twee in de albummap, één versie: één regel');
    expect(pv[1].standaard, 2);
    expect(pv[2].persing, 'LP 2001, LP 2021');
    expect(pv[0].anker, isTrue);
  });
}

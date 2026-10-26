// De oude kopieën in _dubbel terug als versie (Saber, 26-10-2026: "_dubbel nakijken en terugzetten").
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/fingerprint.dart';
import 'package:debridmusic/kopiesoort.dart';
import 'package:debridmusic/organize.dart' show readTags;
import 'package:debridmusic/versie_terugzetter.dart';
import 'package:debridmusic/versies.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _flac({required int hz, required int bits, required Map<String, String> tags, int vulling = 4096}) {
  final out = BytesBuilder()..add(ascii.encode('fLaC'));
  void blok(int type, List<int> body, bool laatste) {
    out.add([(laatste ? 0x80 : 0) | type, (body.length >> 16) & 0xFF, (body.length >> 8) & 0xFF, body.length & 0xFF]);
    out.add(body);
  }

  final si = Uint8List(34);
  final totaal = hz * 200;
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
  out.add(List.filled(vulling, 0x5A));
  return out.toBytes();
}

/// Alles klinkt hetzelfde, behalve wat in [anders] staat.
class _NepVingerafdruk extends Fingerprinter {
  _NepVingerafdruk({this.anders = const {}});
  final Set<String> anders;
  @override
  bool get available => true;
  @override
  Future<Fingerprint?> of(String path, {bool compressed = false, bool heel = false}) async =>
      Fingerprint(200, [for (var i = 0; i < 400; i++) anders.contains(path) ? i * 7919 : i * 31], null);
}

void main() {
  late Directory root, config;
  late String sep, anker, dubbelCd;
  const tags = {'ARTIST': 'Toto', 'ALBUM': 'Toto IV', 'TITLE': 'Africa', 'TRACKNUMBER': '10'};

  File schrijf(String pad, {required int hz, required int bits, int vulling = 4096}) {
    final f = File(pad)..parent.createSync(recursive: true);
    f.writeAsBytesSync(_flac(hz: hz, bits: bits, tags: tags, vulling: vulling));
    return f;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('dm_terug_');
    config = Directory.systemTemp.createTempSync('dm_terug_cfg_');
    sep = Platform.pathSeparator;
    anker = '${root.path}${sep}Albums${sep}Toto${sep}Toto IV${sep}10 - Africa.flac';
    dubbelCd = '${root.path}$sep${'_dubbel'}$sep${'10 - Africa.flac'}';
    versies.wis();
    resetSoortenVoorToets();
  });
  tearDown(() {
    versies.wis();
    resetSoortenVoorToets();
    root.deleteSync(recursive: true);
    config.deleteSync(recursive: true);
  });

  VersieTerugzetter zetter({Set<String> anders = const {}}) => VersieTerugzetter(
        wortel: root.path,
        nummerVan: (a, t, {int? seconden}) => t == 'Africa' ? anker : null,
        klaar: () async {},
        bestand: '${config.path}${sep}versies_dubbel.json',
        vingerafdruk: _NepVingerafdruk(anders: anders),
      );

  test('DE KERN: de cd die een vinylrip verving, wordt weer het nummer; de vinylrip een versie', () async {
    // Vandaag (26-10-2026): een torrent verving de cd door een vinylrip van 24/96 — de cd staat in _dubbel.
    schrijf(anker, hz: 96000, bits: 24, vulling: 40000);
    zetSoort(anker, Kopiesoort.vinyl);
    schrijf(dubbelCd, hz: 44100, bits: 16, vulling: 20000);
    final uit = await zetter().ronde();
    expect(uit.nummers, 1);
    expect(File(dubbelCd).existsSync(), isFalse);
    expect(readFlacKop(anker), (16, 44100), reason: 'de cd staat weer op de plek van het nummer');
    final vinyl = '${root.path}${sep}Albums${sep}Toto${sep}Toto IV (vinyl)${sep}10 - Africa.flac';
    expect(File(vinyl).existsSync(), isTrue);
    expect(versies.ankerVan(vinyl), anker);
    expect(readTags(File(vinyl))?.album, 'Toto IV (vinyl)');
  });

  test('dezelfde versie (twee cd-rips) blijft in _dubbel, en wordt niet nog eens bekeken', () async {
    schrijf(anker, hz: 44100, bits: 16, vulling: 30000);
    schrijf(dubbelCd, hz: 44100, bits: 16, vulling: 20000);
    final z = zetter();
    expect((await z.ronde()).bleven, 1);
    expect(File(dubbelCd).existsSync(), isTrue, reason: 'niets wordt gewist');
    expect(versies.isLeeg, isTrue);
    expect((await z.ronde()).bekeken, 0, reason: 'al nagekeken');
  });

  test('een cd die een studiokopie verving: de cd komt terug als versie', () async {
    schrijf(anker, hz: 96000, bits: 24, vulling: 40000);
    schrijf(dubbelCd, hz: 44100, bits: 16, vulling: 20000);
    final uit = await zetter().ronde();
    expect(uit.versies, 1);
    final cd = '${root.path}${sep}Albums${sep}Toto${sep}Toto IV (cd)${sep}10 - Africa.flac';
    expect(File(cd).existsSync(), isTrue);
    expect(versies.ankerVan(cd), anker);
  });

  test('DE KERN: een "studiokopie" die van een cd verloor, komt niet terug — die was opgeschaald', () async {
    schrijf(anker, hz: 44100, bits: 16, vulling: 20000);
    final studio = '${root.path}$sep${'_dubbel'}$sep${'(2) 10 - Africa.flac'}';
    schrijf(studio, hz: 96000, bits: 24, vulling: 40000);
    final besluiten = <String>[];
    final z = VersieTerugzetter(
      wortel: root.path,
      nummerVan: (a, t, {int? seconden}) => anker,
      klaar: () async {},
      bestand: '${config.path}${sep}versies_dubbel.json',
      vingerafdruk: _NepVingerafdruk(),
      bijBesluit: (p, b) => besluiten.add(b),
    );
    expect((await z.ronde()).bleven, 1);
    expect(besluiten.single, 'verloor eerder (studio tegen cd)');
    expect(File(studio).existsSync(), isTrue);
  });

  test('vinyl alsnog uit downloads.log: "[LP][24/192]" in de torrentnaam, en het bestand is nog dat bestand', () async {
    schrijf(anker, hz: 192000, bits: 24, vulling: 40000);
    final log = File('${config.path}${sep}downloads.log')
      ..writeAsStringSync('10:40:51.576  "Toto — Africa": vervangen door de kopie uit torrent '
          '"(Pop, Rock) [LP][24/192] Toto - IV - 1982, FLAC (tracks+.cue), lossless"\n'
          '10:41:10.891  "Toto — Rosanna": vervangen door de kopie uit torrent "Toto - IV [24-96]"\n');
    final z = VersieTerugzetter(
      wortel: root.path,
      nummerVan: (a, t, {int? seconden}) => t == 'Africa' ? anker : null,
      klaar: () async {},
      bestand: '${config.path}${sep}versies_dubbel.json',
      vingerafdruk: _NepVingerafdruk(),
      logboek: log.path,
    );
    expect(z.vinylUitLogboek(), 1);
    expect(soortVoor(anker)?.soort, Kopiesoort.vinyl);
    // Sindsdien vervangen door een cd van 16/44,1: dan zegt de regel niets meer over dit bestand.
    resetSoortenVoorToets();
    schrijf(anker, hz: 44100, bits: 16);
    expect(z.vinylUitLogboek(), 0);
    expect(soortVoor(anker), isNull);
    // En een soort die je zelf koos, blijft.
    schrijf(anker, hz: 192000, bits: 24);
    zetSoort(anker, Kopiesoort.studio, gekozen: true);
    expect(z.vinylUitLogboek(), 0);
  });

  test('een andere opname (de vingerafdruk) blijft staan', () async {
    schrijf(anker, hz: 96000, bits: 24);
    zetSoort(anker, Kopiesoort.vinyl);
    schrijf(dubbelCd, hz: 44100, bits: 16);
    expect((await zetter(anders: {dubbelCd}).ronde()).bleven, 1);
    expect(File(dubbelCd).existsSync(), isTrue);
  });

  test('kapot is kapot: _dubbel/afgekeurd komt niet terug', () async {
    schrijf(anker, hz: 96000, bits: 24);
    zetSoort(anker, Kopiesoort.vinyl);
    schrijf('${root.path}$sep${'_dubbel'}$sep${'afgekeurd'}$sep${'10 - Africa.flac'}', hz: 44100, bits: 16);
    expect((await zetter().ronde()).bekeken, 0);
  });
}

/// Diepte en frequentie uit de kop.
(int, int) readFlacKop(String pad) {
  final b = File(pad).readAsBytesSync();
  final hz = (b[18] << 12) | (b[19] << 4) | (b[20] >> 4);
  final bits = (((b[20] & 1) << 4) | (b[21] >> 4)) + 1;
  return (bits, hz);
}

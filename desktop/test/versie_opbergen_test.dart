// Versies bewaren in plaats van vervangen (Saber, 26-10-2026): "Behoud ik alles e, cd, studio, en vinyl".
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/kopiesoort.dart';
import 'package:debridmusic/organize.dart' show readTags;
import 'package:debridmusic/versie_opbergen.dart';
import 'package:debridmusic/versies.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een kleine maar echte FLAC: STREAMINFO met [hz], [bits] en [sec] seconden, de tags, en wat "audio" ([vulling] maakt
/// hem groter of kleiner).
Uint8List _flac({required int hz, required int bits, int sec = 200, required Map<String, String> tags, int vulling = 4096}) {
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
  out.add(List.filled(vulling, 0x5A));
  return out.toBytes();
}

const _tags = {'TITLE': 'Wannabe', 'ARTIST': 'Spice Girls', 'ALBUM': 'Spice', 'TRACKNUMBER': '1', 'DATE': '1996'};

void main() {
  late Directory root;
  late String sep, anker;

  File schrijf(String pad, Uint8List bytes) {
    final f = File(pad);
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes);
    return f;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('dm_versie_opbergen_');
    sep = Platform.pathSeparator;
    anker = '${root.path}${sep}Albums${sep}Spice Girls${sep}Spice${sep}01 - Wannabe.flac';
    schrijf(anker, _flac(hz: 44100, bits: 16, tags: _tags, vulling: 20000));
    versies.wis();
    resetSoortenVoorToets();
  });
  tearDown(() {
    versies.wis();
    resetSoortenVoorToets();
    root.deleteSync(recursive: true);
  });

  test('het besluit, zuiver: zelfde versie gewoon, lager een versie, hoger het nummer', () {
    expect(versiebesluit(soort: Kopiesoort.cd, persing: '', ankerSoort: Kopiesoort.cd, ankerPersing: '').besluit,
        Versiebesluit.gewoon);
    expect(versiebesluit(soort: Kopiesoort.vinyl, persing: 'LP', ankerSoort: Kopiesoort.cd, ankerPersing: '').besluit,
        Versiebesluit.nieuweVersie);
    expect(versiebesluit(soort: Kopiesoort.studio, persing: '', ankerSoort: Kopiesoort.cd, ankerPersing: '').besluit,
        Versiebesluit.ankerOpzij);
    expect(versiebesluit(soort: Kopiesoort.cd, persing: '', ankerSoort: Kopiesoort.vinyl, ankerPersing: 'LP').besluit,
        Versiebesluit.ankerOpzij, reason: 'vandaag vervingen vinylrips je cd\'s: een cd die langskomt, wordt weer het nummer');
    final v = Versie(pad: 'x', soort: Kopiesoort.vinyl, persing: 'LP 1996');
    final b = versiebesluit(
        soort: Kopiesoort.vinyl, persing: '', ankerSoort: Kopiesoort.cd, ankerPersing: '', bestaande: [v]);
    expect(b.besluit, Versiebesluit.vervangVersie);
    expect(b.vervangt, v);
    expect(versiebesluit(soort: null, persing: '', ankerSoort: Kopiesoort.cd, ankerPersing: '').besluit,
        Versiebesluit.gewoon, reason: 'een mp3 is geen versie');
  });

  test('DE KERN: een vinylrip wordt een versie in zijn eigen map; het nummer blijft', () async {
    final binnen = schrijf('${root.path}$sep${'_keuring'}${sep}x${sep}A1 Wannabe.flac',
        _flac(hz: 96000, bits: 24, sec: 207, tags: {'TITLE': 'Wannabe', 'ARTIST': 'Spice Girls'}));
    final plan = versieplanVoor(binnen, anker, r'PBTHAL rips\Spice Girls\1996 - Spice (Vinyl 24-96)\A1 Wannabe.flac');
    expect(plan.besluit, Versiebesluit.nieuweVersie);
    expect(plan.soort, Kopiesoort.vinyl);
    expect(plan.ankerSoort, Kopiesoort.cd, reason: 'uit de kop van het nummer: 16/44,1');
    expect(plan.persing, 'LP 1996 PBTHAL');
    final uit = await bergOpAlsVersie(binnen, plan, root: root.path, nu: () => DateTime(2026, 10, 26, 14));
    final verwacht = '${root.path}${sep}Albums${sep}Spice Girls${sep}Spice (vinyl LP 1996 PBTHAL)${sep}01 - Wannabe.flac';
    expect(uit?.pad, verwacht);
    expect(uit?.werdAnker, isFalse);
    expect(File(verwacht).existsSync(), isTrue);
    expect(File(anker).existsSync(), isTrue, reason: 'het nummer blijft staan');
    expect(binnen.existsSync(), isFalse);
    expect(versies.ankerVan(verwacht), anker);
    expect(versies.versie(verwacht)?.sindsMs, DateTime(2026, 10, 26, 14).millisecondsSinceEpoch);
    expect(readTags(File(verwacht))?.album, 'Spice (vinyl LP 1996 PBTHAL)', reason: 'een eigen album, ook in Roon');
    expect(readTags(File(anker))?.album, 'Spice');
    expect(soortVoor(verwacht)?.soort, Kopiesoort.vinyl);
  });

  test('DE KERN: een echte studiokopie wordt het nummer; de cd gaat opzij als versie', () async {
    final binnen = schrijf('${root.path}$sep${'_keuring'}${sep}y${sep}01 Wannabe.flac',
        _flac(hz: 96000, bits: 24, tags: {'TITLE': 'Wannabe', 'ARTIST': 'Spice Girls'}, vulling: 40000));
    final plan = versieplanVoor(binnen, anker, r'Spice Girls\Spice [24-96]\01 Wannabe.flac');
    expect(plan.besluit, Versiebesluit.ankerOpzij);
    final uit = await bergOpAlsVersie(binnen, plan, root: root.path);
    expect(uit?.werdAnker, isTrue);
    expect(uit?.pad, anker, reason: 'op de plek van het nummer');
    final cd = '${root.path}${sep}Albums${sep}Spice Girls${sep}Spice (cd)${sep}01 - Wannabe.flac';
    expect(File(cd).existsSync(), isTrue);
    expect(versies.ankerVan(cd), anker);
    expect(versies.versie(cd)?.soort, Kopiesoort.cd);
    expect(versies.groep(anker)?.soort, Kopiesoort.studio);
    expect(readTags(File(cd))?.album, 'Spice (cd)');
    expect(readTags(File(anker))?.album, 'Spice', reason: 'het nummer hoort bij zijn album');
    expect(soortVoor(anker)?.soort, Kopiesoort.studio);
    expect(soortVoor(cd)?.soort, Kopiesoort.cd);
  });

  test('een tweede kopie van dezelfde vinylpersing: alleen de betere blijft', () async {
    final eerste = schrijf('${root.path}$sep${'_keuring'}${sep}a${sep}A1.flac',
        _flac(hz: 96000, bits: 24, tags: {'TITLE': 'Wannabe', 'ARTIST': 'Spice Girls'}, vulling: 30000));
    final p1 = versieplanVoor(eerste, anker, r'X\Spice (Vinyl LP 24-96)\A1.flac');
    final v1 = await bergOpAlsVersie(eerste, p1, root: root.path);
    final mindere = schrijf('${root.path}$sep${'_keuring'}${sep}b${sep}A1.flac',
        _flac(hz: 44100, bits: 16, tags: {'TITLE': 'Wannabe', 'ARTIST': 'Spice Girls'}, vulling: 9000));
    final p2 = versieplanVoor(mindere, anker, r'Y\Spice [vinyl rip]\A1.flac');
    expect(p2.besluit, Versiebesluit.vervangVersie);
    final v2 = await bergOpAlsVersie(mindere, p2, root: root.path);
    expect(v2?.verloor, isTrue);
    expect(mindere.existsSync(), isFalse, reason: 'twee rips van dezelfde persing: de mindere gaat weg');
    expect(versies.versiesVan(anker).single.pad, v1!.pad);
  });

  test('een andere vinylpersing (een ander jaar) is een tweede versie', () async {
    final a = schrijf('${root.path}$sep${'_keuring'}${sep}a${sep}A1.flac',
        _flac(hz: 96000, bits: 24, tags: {'TITLE': 'Wannabe', 'ARTIST': 'Spice Girls'}));
    await bergOpAlsVersie(a, versieplanVoor(a, anker, r'X\1996 - Spice (Vinyl 24-96)\A1.flac'), root: root.path);
    final b = schrijf('${root.path}$sep${'_keuring'}${sep}b${sep}A1.flac',
        _flac(hz: 96000, bits: 24, tags: {'TITLE': 'Wannabe', 'ARTIST': 'Spice Girls'}));
    final p = versieplanVoor(b, anker, r'Y\Spice (2016 Vinyl Reissue) [24-96]\A1.flac');
    expect(p.besluit, Versiebesluit.nieuweVersie);
    await bergOpAlsVersie(b, p, root: root.path);
    expect([for (final v in versies.versiesVan(anker)) v.persing], ['LP 1996', 'LP 2016 Reissue']);
  });
}

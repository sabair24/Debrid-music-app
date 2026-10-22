// De gekozen voorkant ook in mp3, AIFF, WavPack en Monkey's Audio (Saber, 21-10-2026: "doe dit altijd bij
// allemaal"). Elke toets leest het resultaat ook terug met audio_metadata_reader, de lezer van de bibliotheek.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/hoes_in_bestand.dart';
import 'package:debridmusic/hoes_in_bestand_anders.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';

Uint8List _jpeg(int breedte, int hoogte, int lengte, {int zaad = 1}) {
  final b = Uint8List(max(lengte, 40));
  b.setAll(0, [0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x11, 0x08, hoogte >> 8, hoogte & 0xFF, breedte >> 8, breedte & 0xFF, 0x03]);
  final r = Random(zaad);
  for (var i = 12; i < b.length - 2; i++) {
    b[i] = r.nextInt(256);
  }
  b[b.length - 2] = 0xFF;
  b[b.length - 1] = 0xD9;
  return b;
}

Uint8List _bytes(int n, {int zaad = 7, List<int> begin = const []}) {
  final r = Random(zaad);
  return Uint8List.fromList([...begin, ...List.generate(n - begin.length, (_) => r.nextInt(256))]);
}

List<int> _be(int v) => [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
List<int> _le(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
List<int> _ss(int v) => [(v >> 21) & 0x7F, (v >> 14) & 0x7F, (v >> 7) & 0x7F, v & 0x7F];
int _ssLees(List<int> d, int i) => (d[i] << 21) | (d[i + 1] << 14) | (d[i + 2] << 7) | d[i + 3];

Uint8List _frame(int versie, String id, List<int> data) =>
    Uint8List.fromList([...id.codeUnits, ...(versie == 4 ? _ss(data.length) : _be(data.length)), 0, 0, ...data]);

Uint8List _tekst(int versie, String id, String s) => _frame(versie, id, [0, ...s.codeUnits]);

/// Een APIC; met [utf16] een omschrijving in UTF-16 met BOM (twee nullen erachter).
Uint8List _apic(int versie, int soort, Uint8List beeld, {bool utf16 = false}) => _frame(versie, 'APIC', [
      utf16 ? 1 : 0,
      ...'image/jpeg'.codeUnits,
      0,
      soort,
      if (utf16) ...[0xFF, 0xFE, 0x41, 0x00, 0x00, 0x00] else ...'hoes'.codeUnits,
      if (!utf16) 0,
      ...beeld,
    ]);

Uint8List _id3(int versie, List<Uint8List> frames, int opvulling, {int vlaggen = 0}) {
  final lijf = [for (final f in frames) ...f, ...List.filled(opvulling, 0)];
  return Uint8List.fromList([0x49, 0x44, 0x33, versie, 0, vlaggen, ..._ss(lijf.length), ...lijf]);
}

/// De APIC-frames van de ID3-kop in [b] vanaf [o]: (soort, beeldlengte), in volgorde; plus de andere frame-ids.
({List<(int, int)> platen, List<String> ids}) _id3Inhoud(Uint8List b, [int o = 0]) {
  final versie = b[o + 3];
  final eind = o + 10 + _ssLees(b, o + 6);
  final platen = <(int, int)>[];
  final ids = <String>[];
  var i = o + 10;
  while (i + 10 <= eind && b[i] != 0) {
    final id = String.fromCharCodes(b, i, i + 4);
    final n = versie == 4
        ? _ssLees(b, i + 4)
        : (b[i + 4] << 24) | (b[i + 5] << 16) | (b[i + 6] << 8) | b[i + 7];
    ids.add(id);
    if (id == 'APIC') {
      var p = i + 11;
      while (b[p] != 0) {
        p++;
      }
      platen.add((b[p + 1], n));
    }
    i += 10 + n;
  }
  return (platen: platen, ids: ids);
}

Uint8List _chunk(String id, List<int> data) =>
    Uint8List.fromList([...id.codeUnits, ..._be(data.length), ...data, if (data.length.isOdd) 0]);

Uint8List _aiff(List<Uint8List> chunks, {List<int> staart = const []}) {
  final lijf = [...'AIFF'.codeUnits, for (final c in chunks) ...c];
  return Uint8List.fromList([...'FORM'.codeUnits, ..._be(lijf.length), ...lijf, ...staart]);
}

Uint8List _apeItem(String sleutel, List<int> waarde, {int vlaggen = 0}) =>
    Uint8List.fromList([..._le(waarde.length), ..._le(vlaggen), ...sleutel.codeUnits, 0, ...waarde]);

Uint8List _ape(List<Uint8List> items, {int versie = 2000}) {
  final lijf = [for (final i in items) ...i];
  List<int> rand(int vlaggen) => [
        ...'APETAGEX'.codeUnits, ..._le(versie), ..._le(lijf.length + 32), ..._le(items.length), ..._le(vlaggen),
        ...List.filled(8, 0),
      ];
  return Uint8List.fromList([...rand(0xA0000000), ...lijf, ...rand(0x80000000)]);
}

/// De items van het APEv2-blok in [b] (vóór een eventuele ID3v1): sleutel en waarde.
List<(String, Uint8List)> _apeItems(Uint8List b) {
  var eind = b.length;
  if (String.fromCharCodes(b, eind - 128, eind - 125) == 'TAG') eind -= 128;
  final v = ByteData.sublistView(b);
  final lengte = v.getUint32(eind - 20, Endian.little), aantal = v.getUint32(eind - 16, Endian.little);
  var p = eind - lengte;
  final uit = <(String, Uint8List)>[];
  for (var k = 0; k < aantal; k++) {
    final n = v.getUint32(p, Endian.little);
    var q = p + 8;
    while (b[q] != 0) {
      q++;
    }
    uit.add((String.fromCharCodes(b, p + 8, q), Uint8List.sublistView(b, q + 1, q + 1 + n)));
    p = q + 1 + n;
  }
  return uit;
}

void main() {
  late Directory map;
  final vroeger = DateTime(2024, 3, 9, 14, 30, 12);
  setUp(() => map = Directory.systemTemp.createTempSync('dm_hoesanders_'));
  tearDown(() {
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  File schrijf(String naam, Uint8List bytes) {
    final f = File('${map.path}${Platform.pathSeparator}$naam')..writeAsBytesSync(bytes);
    f.setLastModifiedSync(vroeger);
    return f;
  }

  String oudMap() => '${map.path}${Platform.pathSeparator}hoes_oud';
  Uint8List? eerstePlaat(File f) {
    final m = readMetadata(f, getImage: true);
    return m.pictures.isEmpty ? null : m.pictures.first.bytes;
  }

  final oudeHoes = _jpeg(600, 600, 5000, zaad: 2);
  final achter = _jpeg(600, 600, 900, zaad: 4);
  final nieuw = _jpeg(1200, 1200, 3000, zaad: 3);
  // MPEG-1 laag 3, 128 kb/s, 44,1 kHz (FF FB 90 64: 417 bytes per frame) met ruis erin: de "audio" die byte
  // voor byte mee moet.
  final mp3Audio = Uint8List.fromList([
    for (var i = 0; i < 140; i++) ..._bytes(417, zaad: i, begin: [0xFF, 0xFB, 0x90, 0x64])
  ]);

  test('welke schrijver bij welk bestand', () {
    expect(hoesbakVan(r'C:\m\a.FLAC'), Hoesbak.flac);
    expect(hoesbakVan(r'C:\m\a.mp3'), Hoesbak.id3);
    expect(hoesbakVan(r'C:\m\a.aif'), Hoesbak.aiff);
    expect(hoesbakVan(r'C:\m\a.aiff'), Hoesbak.aiff);
    expect(hoesbakVan(r'C:\m\a.wv'), Hoesbak.ape);
    expect(hoesbakVan(r'C:\m\a.ape'), Hoesbak.ape);
    expect(hoesbakVan(r'C:\m\a.m4a'), isNull);
    expect(hoesbakVan(r'C:\R.E.M\nummer'), isNull, reason: 'een punt in een mapnaam is geen extensie');
    final m4a = schrijf('x.m4a', _bytes(500));
    expect(schrijfVoorkant(m4a.path, nieuw).uitkomst, HoesUitkomst.nietTeLezen);
  });

  group('mp3', () {
    test('past in de oude kop: even groot, zelfde datum, zelfde audio, de andere frames blijven', () {
      final titel = _tekst(3, 'TIT2', 'Halo');
      final eigen = _tekst(3, 'TXXX', '\u0000SERATO');
      final kop = _id3(3, [titel, _apic(3, 3, oudeHoes), eigen], 2000);
      final f = schrijf('a.mp3', Uint8List.fromList([...kop, ...mp3Audio]));
      final voor = f.lengthSync();
      final r = schrijfVoorkantInMp3(f.path, nieuw, bewaarOud: oudMap());
      expect(r.uitkomst, HoesUitkomst.zelfdeGrootte);
      final b = f.readAsBytesSync();
      expect(b.length, voor);
      expect(f.lastModifiedSync(), vroeger);
      expect(b.sublist(kop.length), mp3Audio, reason: 'de audio byte voor byte');
      final inhoud = _id3Inhoud(b);
      expect(inhoud.ids, ['TIT2', 'APIC', 'TXXX'], reason: 'de nieuwe plaat op de plek van de oude, de rest in volgorde');
      expect(inhoud.platen, [(3, 1 + 11 + 2 + nieuw.length)]);
      // De frames die we niet aanraken: byte voor byte.
      expect(b.sublist(10, 10 + titel.length), titel);
      expect(eerstePlaat(f), nieuw, reason: 'wat de bibliotheek leest');
      expect(readMetadata(f).title, 'Halo');
      expect(File('${oudMap()}${Platform.pathSeparator}${r.oud}').readAsBytesSync(), oudeHoes);
      expect(File('${f.path}.hoes').existsSync(), isFalse);
    });

    test('ID3v2.4 met syncsafe maten; past niet: het bestand groeit, met ruimte voor een volgende keer', () {
      final groot = _jpeg(1200, 1200, 40000, zaad: 5);
      final kop = _id3(4, [_tekst(4, 'TIT2', 'x'), _apic(4, 3, oudeHoes)], 100);
      final f = schrijf('b.mp3', Uint8List.fromList([...kop, ...mp3Audio]));
      expect(schrijfVoorkantInMp3(f.path, groot).uitkomst, HoesUitkomst.andereGrootte);
      final b = f.readAsBytesSync();
      final lengte = 10 + _ssLees(b, 6);
      expect(b.sublist(lengte), mp3Audio);
      expect(lengte - 10 - ((10 + 2) + (10 + 1 + 11 + 2 + groot.length)), kHoesInBestandRuimte);
      expect(eerstePlaat(f), groot);
      expect(schrijfVoorkantInMp3(f.path, groot).uitkomst, HoesUitkomst.alGelijk, reason: 'nog eens: niets');
    });

    test('zonder ID3-kop: er komt er een vooraan, de audio schuift alleen op', () {
      final f = schrijf('c.mp3', mp3Audio);
      expect(schrijfVoorkantInMp3(f.path, nieuw).uitkomst, HoesUitkomst.andereGrootte);
      final b = f.readAsBytesSync();
      final lengte = 10 + _ssLees(b, 6);
      expect(b[3], 3, reason: 'v2.3');
      expect(b.sublist(lengte), mp3Audio);
      expect(eerstePlaat(f), nieuw);
    });

    test('een achterkant blijft, de nieuwe voorkant komt ervoor; oude voorkanten weg (ook in UTF-16)', () {
      final kop = _id3(3, [_apic(3, 4, achter, utf16: true), _apic(3, 3, oudeHoes, utf16: true), _apic(3, 0, oudeHoes)], 500);
      final f = schrijf('d.mp3', Uint8List.fromList([...kop, ...mp3Audio]));
      expect(schrijfVoorkantInMp3(f.path, nieuw).uitkomst, isNot(HoesUitkomst.mislukt));
      final p = _id3Inhoud(f.readAsBytesSync()).platen;
      expect(p.map((e) => e.$1), [3, 4]);
      expect(eerstePlaat(f), nieuw);
      final m = readMetadata(f, getImage: true);
      expect(m.pictures[1].bytes, achter);
    });

    test('alleen in een bestand zonder plaat — als dat gevraagd is', () {
      final met = schrijf('e.mp3', Uint8List.fromList([..._id3(3, [_apic(3, 3, oudeHoes)], 100), ...mp3Audio]));
      final voor = met.readAsBytesSync();
      expect(schrijfVoorkantInMp3(met.path, nieuw, alleenAlsLeeg: true).uitkomst, HoesUitkomst.heeftAlEen);
      expect(met.readAsBytesSync(), voor);
      final zonder = schrijf('f.mp3', Uint8List.fromList([..._id3(3, [_tekst(3, 'TIT2', 'x')], 100), ...mp3Audio]));
      expect(schrijfVoorkantInMp3(zonder.path, nieuw, alleenAlsLeeg: true).uitkomst, isNot(HoesUitkomst.heeftAlEen));
      expect(eerstePlaat(zonder), nieuw);
    });

    test('weigeren in plaats van gokken: v2.2, vlaggen, een frame te lang, iets anders dan een mp3', () {
      final gevallen = {
        'v22.mp3': Uint8List.fromList([0x49, 0x44, 0x33, 2, 0, 0, ..._ss(20), ...List.filled(20, 0), ...mp3Audio]),
        'unsync.mp3': Uint8List.fromList([..._id3(3, [_tekst(3, 'TIT2', 'x')], 50, vlaggen: 0x80), ...mp3Audio]),
        'te_lang.mp3': Uint8List.fromList([
          0x49, 0x44, 0x33, 3, 0, 0, ..._ss(30), ...'TIT2'.codeUnits, ..._be(500), 0, 0, ...List.filled(20, 1),
          ...mp3Audio
        ]),
        'rommel.mp3': _bytes(5000, begin: [0x52, 0x49, 0x46, 0x46]),
      };
      for (final e in gevallen.entries) {
        final f = schrijf(e.key, e.value);
        expect(schrijfVoorkantInMp3(f.path, nieuw).uitkomst, HoesUitkomst.nietTeLezen, reason: e.key);
        expect(f.readAsBytesSync(), e.value, reason: e.key);
      }
    });

    test('alleen-lezen: niet aangeraakt', () {
      final f = schrijf('ro.mp3', Uint8List.fromList([..._id3(3, [_apic(3, 3, oudeHoes)], 100), ...mp3Audio]));
      if (Platform.isWindows) {
        Process.runSync('attrib', ['+R', f.path]);
      } else {
        Process.runSync('chmod', ['444', f.path]);
      }
      addTearDown(() => Platform.isWindows
          ? Process.runSync('attrib', ['-R', f.path])
          : Process.runSync('chmod', ['644', f.path]));
      final voor = f.readAsBytesSync();
      expect(schrijfVoorkantInMp3(f.path, nieuw).uitkomst, HoesUitkomst.alleenLezen);
      expect(f.readAsBytesSync(), voor);
    });
  });

  group('AIFF', () {
    final comm = _chunk('COMM', [0, 2, 0, 0, 0x10, 0, 0, 16, 0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0]);
    final ssnd = _chunk('SSND', [0, 0, 0, 0, 0, 0, 0, 0, ..._bytes(40000)]);
    int formLengte(Uint8List b) => (b[4] << 24) | (b[5] << 16) | (b[6] << 8) | b[7];
    Uint8List? aiffPlaat(File f) {
      final raf = f.openSync();
      try {
        final m = AiffParser(fetchImage: true).parse(raf);
        return m.pictures.isEmpty ? null : m.pictures.first.bytes;
      } finally {
        try {
          raf.closeSync();
        } catch (_) {/* de lezer sluit hem zelf */}
      }
    }

    test('met een ID3-chunk die past: even groot, de FORM klopt, COMM en SSND byte voor byte', () {
      final tag = _id3(4, [_tekst(4, 'TIT2', 'Halo'), _apic(4, 3, oudeHoes)], 1000);
      final f = schrijf('a.aif', _aiff([comm, ssnd, _chunk('ID3 ', tag)]));
      final voor = f.lengthSync();
      expect(schrijfVoorkantInAiff(f.path, nieuw).uitkomst, HoesUitkomst.zelfdeGrootte);
      final b = f.readAsBytesSync();
      expect(b.length, voor);
      expect(formLengte(b) + 8, b.length);
      expect(b.sublist(12, 12 + comm.length + ssnd.length), [...comm, ...ssnd]);
      expect(aiffPlaat(f), nieuw);
      expect(f.lastModifiedSync(), vroeger);
    });

    test('zonder ID3-chunk: er komt er een achteraan, de FORM groeit mee', () {
      final f = schrijf('b.aiff', _aiff([comm, ssnd]));
      expect(schrijfVoorkantInAiff(f.path, nieuw).uitkomst, HoesUitkomst.andereGrootte);
      final b = f.readAsBytesSync();
      expect(formLengte(b) + 8, b.length);
      expect(b.sublist(12, 12 + comm.length + ssnd.length), [...comm, ...ssnd]);
      expect(String.fromCharCodes(b, 12 + comm.length + ssnd.length, 16 + comm.length + ssnd.length), 'ID3 ');
      expect(aiffPlaat(f), nieuw);
    });

    test('een oneven kop krijgt zijn opvulbyte; een byte na de FORM blijft staan (Greyhound)', () {
      final oneven = _id3(3, [_tekst(3, 'TIT2', 'x')], 3); // 10 + 12 + 3 = 25
      expect(oneven.length.isOdd, isTrue);
      final f = schrijf('c.aif', _aiff([comm, ssnd, _chunk('ID3 ', oneven)], staart: [0]));
      expect(schrijfVoorkantInAiff(f.path, nieuw).uitkomst, HoesUitkomst.andereGrootte);
      final b = f.readAsBytesSync();
      expect(formLengte(b) + 8 + 1, b.length, reason: 'de byte erna blijft erna');
      expect(b.last, 0);
      expect(aiffPlaat(f), nieuw);
      expect(schrijfVoorkantInAiff(f.path, nieuw).uitkomst, HoesUitkomst.alGelijk);
    });

    test('afgekapt (Bow Wow: de FORM belooft meer dan er staat): niet aangeraakt', () {
      final heel = _aiff([comm, ssnd, _chunk('ID3 ', _id3(4, [_apic(4, 3, oudeHoes)], 100))]);
      final f = schrijf('d.aiff', Uint8List.sublistView(heel, 0, heel.length - 2000));
      final voor = f.readAsBytesSync();
      expect(schrijfVoorkantInAiff(f.path, nieuw).uitkomst, HoesUitkomst.nietTeLezen);
      expect(f.readAsBytesSync(), voor);
    });
  });

  group('WavPack en Monkey\'s Audio (APEv2)', () {
    final wv = _bytes(50000, begin: 'wvpk'.codeUnits);
    final id3v1 = Uint8List.fromList(['T'.codeUnitAt(0), 'A'.codeUnitAt(0), 'G'.codeUnitAt(0), ...List.filled(125, 32)]);

    test('de nieuwe voorkant als eerste item; tekst en achterkant blijven, de oude voorkant weg, ID3v1 achteraan', () {
      final titel = _apeItem('Title', 'Earth Song'.codeUnits);
      final f = schrijf(
          'a.wv',
          Uint8List.fromList([
            ...wv,
            ..._ape([
              titel,
              _apeItem('Cover Art (front)', [...'a.jpg'.codeUnits, 0, ...oudeHoes], vlaggen: 2),
              _apeItem('Cover Art (Back)', [...'b.jpg'.codeUnits, 0, ...achter], vlaggen: 2),
            ]),
            ...id3v1,
          ]));
      final r = schrijfVoorkantInApe(f.path, nieuw, bewaarOud: oudMap());
      expect(r.uitkomst, HoesUitkomst.andereGrootte);
      final b = f.readAsBytesSync();
      expect(b.sublist(0, wv.length), wv, reason: 'de audio byte voor byte');
      expect(b.sublist(b.length - 128), id3v1);
      final items = _apeItems(b);
      expect(items.map((e) => e.$1), ['Cover Art (Front)', 'Title', 'Cover Art (Back)']);
      expect(items[1].$2, 'Earth Song'.codeUnits);
      expect(eerstePlaat(f), nieuw, reason: 'wat de bibliotheek leest');
      expect(readMetadata(f).title, 'Earth Song');
      expect(File('${oudMap()}${Platform.pathSeparator}${r.oud}').readAsBytesSync(), oudeHoes);
      expect(f.lastModifiedSync(), vroeger);
      expect(schrijfVoorkantInApe(f.path, nieuw).uitkomst, HoesUitkomst.alGelijk);
    });

    test('Monkey\'s Audio zonder tag: er komt een APEv2-blok achteraan', () {
      final ape = _bytes(30000, begin: 'MAC '.codeUnits);
      final f = schrijf('b.ape', ape);
      expect(schrijfVoorkantInApe(f.path, nieuw).uitkomst, HoesUitkomst.andereGrootte);
      final b = f.readAsBytesSync();
      expect(b.sublist(0, ape.length), ape);
      expect(eerstePlaat(f), nieuw);
    });

    test('APEv1 of items die niet kloppen: niet aangeraakt; alleen-als-leeg met een plaat ook niet', () {
      for (final (naam, bytes) in [
        ('v1.wv', Uint8List.fromList([...wv, ..._ape([_apeItem('Title', 'x'.codeUnits)], versie: 1000)])),
        (
          'kapot.wv',
          Uint8List.fromList([
            ...wv,
            ...(_ape([_apeItem('Title', 'xyz'.codeUnits)])..[32] = 200)
          ])
        ),
      ]) {
        final f = schrijf(naam, bytes);
        expect(schrijfVoorkantInApe(f.path, nieuw).uitkomst, HoesUitkomst.nietTeLezen, reason: naam);
        expect(f.readAsBytesSync(), bytes, reason: naam);
      }
      final met = Uint8List.fromList([
        ...wv,
        ..._ape([_apeItem('Cover Art (Front)', [...'a.jpg'.codeUnits, 0, ...oudeHoes], vlaggen: 2)])
      ]);
      final f = schrijf('met.wv', met);
      expect(schrijfVoorkantInApe(f.path, nieuw, alleenAlsLeeg: true).uitkomst, HoesUitkomst.heeftAlEen);
      expect(f.readAsBytesSync(), met);
    });
  });

  group('nieuweId3', () {
    test('precies passend of met ruimte: de lengte die gevraagd is, anders 64 KB erbij', () {
      final apic = _apic(3, 3, nieuw);
      final t = _tekst(3, 'TIT2', 'x');
      final frames = id3Frames(_id3(3, [t], 0))!.frames;
      final kern = 10 + t.length + apic.length;
      expect(nieuweId3(versie: 3, revisie: 0, frames: frames, apic: apic, doel: kern).length, kern);
      expect(nieuweId3(versie: 3, revisie: 0, frames: frames, apic: apic, doel: kern + 77).length, kern + 77);
      expect(nieuweId3(versie: 3, revisie: 0, frames: frames, apic: apic, doel: kern - 1).length,
          kern + kHoesInBestandRuimte);
    });
  });

  group('de veger', () {
    test('een ronde met mp3, AIFF en WavPack — via de isolate; een m4a telt als "nog niet"', () async {
      final mp3 = schrijf('1.mp3', Uint8List.fromList([..._id3(3, [_apic(3, 3, oudeHoes)], 100), ...mp3Audio]));
      final aif = schrijf('2.aif', _aiff([_chunk('SSND', _bytes(4000))]));
      final wv = schrijf('3.wv', _bytes(9000, begin: 'wvpk'.codeUnits));
      final m4a = schrijf('4.m4a', _bytes(900));
      final lib = LibraryStore()..configDirOverride = map.path;
      lib.albums = [
        Album('Until Now', 'Swedish House Mafia', [
          for (final f in [mp3, aif, wv, m4a])
            Track(path: f.path, title: 'x', artist: 'Swedish House Mafia', album: 'Until Now', isFlac: false)
        ])
          ..resolvedCover = nieuw
          ..resolvedFrom = 'dz:1',
      ];
      final veger = HoesInBestandVeger(library: lib, tussenpoos: Duration.zero, startNa: const Duration(hours: 1));
      await veger.start();
      await veger.ronde();
      veger.stop();
      final log = File('${map.path}${Platform.pathSeparator}hoes_in_bestand.log').readAsStringSync();
      expect(log, contains('ronde: 3 nummers in 1 albums na te kijken (1 in een formaat dat nog niet kan, zoals m4a)'));
      expect(log, contains('3 geschreven'));
      expect(log, isNot(contains('MISLUKT')));
      expect(eerstePlaat(mp3), nieuw);
      expect(eerstePlaat(wv), nieuw);
      expect(m4a.lengthSync(), 900);
    });
  });
}

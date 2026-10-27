// De nultoets (Saber, 27-10-2026, bij D'Eux van Céline Dion: "volgens bronnen zou het album nooit in high res uitgekomen
// zijn … toch staan er liedjes bij van 24bit"): "24 bit" wint alleen nog als je 16-bitkopie die 24 bit IS, afgerond.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/echtheid_oordelen.dart';
import 'package:debridmusic/flac_tags.dart' show readFlacTags;
import 'package:debridmusic/kopiesoort.dart';
import 'package:debridmusic/nultoets.dart';
import 'package:debridmusic/nultoets_meter.dart';
import 'package:debridmusic/versie_opbergen.dart';
import 'package:debridmusic/versies.dart';
import 'package:flutter_test/flutter_test.dart';

Nulpunt _p(int v, double g, double rel, double abs) =>
    (verschuiving: v, versterkingDb: g, restDb: rel, restDbfs: abs);

/// Een kleine maar echte FLAC-kop: STREAMINFO met [hz], [bits] en [sec] seconden, en een paar tags.
Uint8List _flac({required int hz, required int bits, int sec = 200, List<int>? md5}) {
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
  if (md5 != null) si.setRange(18, 34, md5);
  blok(0, si, false);
  final b = BytesBuilder();
  void u32(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  final ven = utf8.encode('reference libFLAC 1.4.3');
  u32(ven.length);
  b.add(ven);
  final tags = {'TITLE': 'Pour que tu m\'aimes encore', 'ARTIST': 'Céline Dion', 'ALBUM': 'D\'Eux', 'TRACKNUMBER': '1'};
  u32(tags.length);
  for (final e in tags.entries) {
    final c = utf8.encode('${e.key}=${e.value}');
    u32(c.length);
    b.add(c);
  }
  blok(4, b.toBytes(), true);
  out.add(List.filled(4096, 0x5A));
  return out.toBytes();
}

const _zestien = Echtheidsoordeel(
    bits: Bitdiepte.onbekend, boven: Bovenband.onbekend, band: Bandbreedte.doorlopend, gebruikteBits: 16, afkapHz: 21100);
const _vierentwintig = Echtheidsoordeel(
    bits: Bitdiepte.spreektNietTegen,
    boven: Bovenband.onbekend,
    band: Bandbreedte.doorlopend,
    gebruikteBits: 24,
    afkapHz: 21450);

/// "Muziek": een paar tonen met een langzaam wisselend volume, en ruis — deterministisch.
Float32List _muziek(int seconden, {int zaad = 1}) {
  final r = math.Random(zaad);
  final n = seconden * kNulRate;
  final x = Float32List(n);
  for (var i = 0; i < n; i++) {
    final t = i / kNulRate;
    final env = 0.6 + 0.4 * math.sin(2 * math.pi * 0.13 * t);
    x[i] = env *
            (0.12 * math.sin(2 * math.pi * 220 * t) +
                0.08 * math.sin(2 * math.pi * 331.3 * t + 1) +
                0.05 * math.sin(2 * math.pi * 1187 * t)) +
        0.05 * (r.nextDouble() * 2 - 1);
  }
  return x;
}

Float32List _afgerond16(Float32List x) =>
    Float32List.fromList([for (final v in x) (v * 32768).round() / 32768]);

void main() {
  group('het oordeel, op de getallen van Sabers bibliotheek (72 paren, 27-10-2026)', () {
    test('DE KERN: de echte bron — je 16 bit is de 24 bit, afgerond', () {
      // Ellie Goulding — Close To Me (Explicit), TIDAL HIRES tegen TIDAL LOSSLESS.
      expect(nuluitkomst([_p(-156, -0.1, -93.1, -97.8), _p(-156, -0.1, -92.6, -97.7), _p(-156, -0.1, -93.1, -97.7)]),
          Nuluitkomst.bron);
      // TIDAL LOSSLESS ligt 0,2 dB onder HIRES (Hate Me, Sixteen, Slow Grenade …).
      expect(nuluitkomst([_p(0, 0.2, -81.1, -91.4), _p(0, 0.2, -81.9, -91.4), _p(0, 0.2, -85.2, -91.3)]),
          Nuluitkomst.bron);
      // Yummy en Habibi: ruisvorming in de cd, de vloer ligt hoger.
      expect(nuluitkomst([_p(-182, 0, -69.2, -83.0), _p(-182, 0, -74.8, -83.1), _p(-182, 0, -75.6, -83.2)]),
          Nuluitkomst.bron);
      expect(nuluitkomst([_p(0, 0, -77.5, -86.5), _p(0, 0, -77.8, -86.5), _p(0, 0, -75.9, -86.3)]), Nuluitkomst.bron);
    });

    test('Pijnstiller: het beste punt telt — in de stille stukken is de cd de 24 bit, in de luide begrensd', () {
      expect(nuluitkomst([_p(0, -0.02, -23.9, -31.0), _p(0, 0, -86.5, -96.0), _p(0, 0, -59.9, -72.8)]),
          Nuluitkomst.bron);
    });

    test('DE KERN: D\'Eux 01 — je cd, 0,83 dB verzet, is geen bron', () {
      expect(nuluitkomst([_p(-15552, -0.83, -66.0, -78.0), _p(-15553, -0.829, -71.2, -82.9), _p(-15552, -0.829, -66.3, -78.2)]),
          Nuluitkomst.bewerkt);
      // Mart Hoogkamer — Ik Ga Zwemmen (Orkestband): +0,8 dB.
      expect(nuluitkomst([_p(10168, 0.796, -75.1, -82.3), _p(10168, 0.796, -74.7, -81.4), _p(10168, 0.796, -74.2, -80.7)]),
          Nuluitkomst.bewerkt);
      // Bit voor bit je cd (een 24-bitjasje zonder iets erin): ook geen bron.
      final leeg = _p(0, 0, double.negativeInfinity, double.negativeInfinity);
      expect(nuluitkomst([leeg, leeg]), Nuluitkomst.bewerkt);
      // Je cd met alleen 24-bitruis erbij: onder de 16-bitvloer.
      expect(nuluitkomst([_p(0, 0, -120, -130), _p(0, 0, -121, -131)]), Nuluitkomst.bewerkt);
    });

    test('DE KERN: precies de voorloop van een aac-encoder achter je cd — een gedecodeerde stream', () {
      // Destin (1024) en Like Glue (2112, iTunes).
      expect(nuluitkomst([_p(-1024, -0.165, -20.2, -29.7), _p(-1024, -0.283, -16.7, -25.8)]), Nuluitkomst.lossy);
      expect(nuluitkomst([_p(-2112, -0.018, -31.0, -39.6), _p(-2112, -0.022, -30.0, -40.2)]), Nuluitkomst.lossy);
      // Je cd die zelf 1024 monsters later begint, maakt de kopie niet lossy.
      expect(nuluitkomst([_p(1024, 0, -20, -30), _p(1024, 0, -20, -30)]), Nuluitkomst.anders);
    });

    test('een andere master of mix: niets bewezen', () {
      // Christine (297 monsters, rest −32 dB), Who's That Girl (1034: bijna, maar niet de voorloop).
      expect(nuluitkomst([_p(297, -0.136, -32.2, -41.8), _p(297, -0.197, -31.6, -39.4)]), Nuluitkomst.anders);
      expect(nuluitkomst([_p(-1034, -0.6, -17.2, -25.2), _p(-1034, -0.6, -18.6, -27.0)]), Nuluitkomst.anders);
      expect(nuluitkomst(const []), Nuluitkomst.anders);
    });

    test('meetplekken: drie, verspreid, met ruimte om te schuiven', () {
      expect(meetplekken(240), [40, 100, 150]);
      expect(meetplekken(60), [12, 27, 42]);
      expect(meetplekken(20), isEmpty);
    });
  });

  group('de meting op de monsters', () {
    final master = _muziek(30);
    final cd = _afgerond16(master);

    test('de verschuiving: een kopie met 15552 monsters meer vooraan ligt op −15552', () {
      final later = Float32List(cd.length + 15552)..setRange(15552, 15552 + cd.length, cd);
      expect(verschuivingVan(later, cd, 10 * kNulRate), -15552);
      expect(verschuivingVan(cd, cd, 10 * kNulRate), 0);
    });

    test('DE KERN: de master tegen zijn cd is een bron; de cd luider gezet niet', () {
      final o = nultoetsOp(master, cd, [5, 15])!;
      expect(o.uitkomst, Nuluitkomst.bron, reason: nulZin(o));
      final luider = Float32List.fromList([for (final v in cd) v * 0.909]);
      final b = nultoetsOp(luider, cd, [5, 15])!;
      expect(b.uitkomst, Nuluitkomst.bewerkt, reason: nulZin(b));
      expect(nulZin(b), contains('0,8 dB in volume verzet'));
    });

    test('DE KERN: 1024 monsters later en met ruis erop — lossy; een ander nummer — anders', () {
      final r = math.Random(7);
      final stream = Float32List(cd.length + 1024);
      for (var i = 0; i < cd.length; i++) {
        stream[i + 1024] = cd[i] + 0.004 * (r.nextDouble() * 2 - 1);
      }
      final o = nultoetsOp(stream, cd, [5, 15])!;
      expect(o.uitkomst, Nuluitkomst.lossy, reason: nulZin(o));
      expect(nulZin(o), contains('precies 1024 monsters achter je cd'));
      expect(nultoetsOp(_muziek(30, zaad: 9), cd, [5, 15])?.uitkomst, Nuluitkomst.anders);
    });

    test('stilte zegt niets', () {
      expect(nultoetsOp(Float32List(30 * kNulRate), Float32List(30 * kNulRate), [5, 15]), isNull);
    });
  });

  group('aangesloten op de keuring en het opbergen', () {
    late Directory root;
    late String sep, anker, cd;

    File schrijf(String pad, Uint8List bytes) {
      final f = File(pad);
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(bytes);
      return f;
    }

    setUp(() {
      root = Directory.systemTemp.createTempSync('dm_nultoets_');
      sep = Platform.pathSeparator;
      anker = '${root.path}${sep}Albums${sep}Céline Dion${sep}D\'Eux${sep}01 - Pour que tu m\'aimes encore.flac';
      cd = '${root.path}${sep}Albums${sep}Céline Dion${sep}D\'Eux (cd)${sep}01 - Pour que tu m\'aimes encore.flac';
      versies.wis();
      resetSoortenVoorToets();
      resetEchtheidVoorTest();
      resetNultoetsVoorTest();
    });
    tearDown(() {
      versies.wis();
      resetSoortenVoorToets();
      resetEchtheidVoorTest();
      resetNultoetsVoorTest();
      root.deleteSync(recursive: true);
    });

    String dubbel() => '${root.path}${sep}_dubbel';
    List<File> inDubbel() => Directory(dubbel()).existsSync()
        ? Directory(dubbel()).listSync(recursive: true).whereType<File>().toList()
        : const [];

    /// Het nummer in 24 bit ("studio"), je cd als versie ernaast.
    void deEux() {
      schrijf(anker, _flac(hz: 44100, bits: 24, md5: List.generate(16, (i) => i + 1)));
      schrijf(cd, _flac(hz: 44100, bits: 16, sec: 201, md5: List.generate(16, (i) => 100 + i)));
      onthoudOordeelVanPc(anker, _vierentwintig);
      onthoudOordeelVanPc(cd, _zestien);
      zetSoort(anker, Kopiesoort.studio);
      versies.voegToe(anker, Versie(pad: cd, soort: Kopiesoort.cd, persing: '', sindsMs: 1),
          ankerSoort: Kopiesoort.studio);
      zetSoort(cd, Kopiesoort.cd);
    }

    Future<Nuloordeel?> Function(String, String) zegt(Nuluitkomst u, List<String> gevraagd) => (k, c) async {
          gevraagd.add('$k>$c');
          return (uitkomst: u, punten: [_p(-15552, -0.83, -71.2, -82.9), _p(-15552, -0.83, -66.3, -78.2)]);
        };

    test('DE KERN: D\'Eux 01 — het nummer is je cd, bewerkt: naar _dubbel, en je cd is weer het nummer', () async {
      deEux();
      final gevraagd = <String>[];
      meetNultoets = zegt(Nuluitkomst.bewerkt, gevraagd);
      final regels = <String>[];
      final r = await eenPerSoort(dubbel: dubbel(), log: regels.add);
      expect(gevraagd, ['$anker>$cd'], reason: 'de 24 bit tegen de 16 bit, één keer');
      expect(r.nultoets, 1);
      expect(readFlacTags(File(anker))?.bitsPerSample, 16, reason: 'de cd op de plek van het nummer');
      expect(soortVoor(anker)?.soort, Kopiesoort.cd);
      expect(versies.versiesVan(anker), isEmpty);
      expect(inDubbel(), hasLength(1), reason: 'niets gewist: 30 dagen in _dubbel');
      expect(readFlacTags(inDubbel().single)?.bitsPerSample, 24);
      expect(regels.join('\n'), contains('bewerkt (nultoets) — naar _dubbel'));
      expect(regels.join('\n'), contains('0,8 dB in volume verzet'));
      // Een tweede keer: niets meer te doen, en niets opnieuw gemeten.
      gevraagd.clear();
      expect((await eenPerSoort(dubbel: dubbel())).nultoets, 0);
      expect(gevraagd, isEmpty);
    });

    test('een echte bron blijft het nummer, en niet gemeten verandert er niets', () async {
      deEux();
      meetNultoets = zegt(Nuluitkomst.bron, []);
      expect((await eenPerSoort(dubbel: dubbel())).nultoets, 0);
      expect(readFlacTags(File(anker))?.bitsPerSample, 24);
      expect(versies.versiesVan(anker), hasLength(1));
      resetNultoetsVoorTest();
      expect((await eenPerSoort(dubbel: dubbel())).nultoets, 0, reason: 'geen meter: niets gemeten, niets verplaatst');
      expect(readFlacTags(File(anker))?.bitsPerSample, 24);
    });

    test('Le Ballet: je cd is het nummer, de "studio" een gedecodeerde stream — die versie naar _dubbel', () async {
      final studio = '${root.path}${sep}Albums${sep}Céline Dion${sep}D\'Eux (studio)${sep}02 - Le Ballet.flac';
      anker = '${root.path}${sep}Albums${sep}Céline Dion${sep}D\'Eux${sep}02 - Le Ballet.flac';
      schrijf(anker, _flac(hz: 44100, bits: 16, md5: List.generate(16, (i) => i + 1)));
      schrijf(studio, _flac(hz: 44100, bits: 24, md5: List.generate(16, (i) => 50 + i)));
      onthoudOordeelVanPc(anker, _zestien);
      onthoudOordeelVanPc(studio, _vierentwintig);
      zetSoort(anker, Kopiesoort.cd);
      versies.voegToe(anker, Versie(pad: studio, soort: Kopiesoort.studio, persing: '', sindsMs: 1),
          ankerSoort: Kopiesoort.cd);
      zetSoort(studio, Kopiesoort.studio);
      meetNultoets = zegt(Nuluitkomst.lossy, []);
      final r = await eenPerSoort(dubbel: dubbel());
      expect(r.nultoets, 1);
      expect(readFlacTags(File(anker))?.bitsPerSample, 16, reason: 'je cd blijft het nummer');
      expect(versies.versiesVan(anker), isEmpty);
      expect(File(studio).existsSync(), isFalse);
      expect(inDubbel(), hasLength(1));
    });

    test('binnenkomst: een 24 bit die je cd blijkt, is die cd — geen eigen "studio"-versie', () {
      schrijf(anker, _flac(hz: 44100, bits: 16));
      zetSoort(anker, Kopiesoort.cd);
      final nieuw = schrijf('${root.path}$sep.incoming${sep}01.flac', _flac(hz: 44100, bits: 24, md5: List.filled(16, 7)));
      final bron = r'music\Céline Dion\D’eux (1995)\01 - Pour que tu m’aimes encore.flac';
      expect(versieplanVoor(nieuw, anker, bron).soort, Kopiesoort.studio, reason: 'zonder nultoets: "studio"');
      onthoudNultoets(nieuw.path, anker, Nuluitkomst.bewerkt);
      final plan = versieplanVoor(nieuw, anker, bron);
      expect(plan.soort, Kopiesoort.cd);
      expect(plan.besluit, Versiebesluit.gewoon, reason: 'dan beslist de keuring binnen de soort cd — en hij verliest');
    });

    test('de uitslag hoort bij het geluid: na verhuizen en hertaggen geldt hij nog', () {
      final a = schrijf('${root.path}${sep}a.flac', _flac(hz: 44100, bits: 24, md5: List.filled(16, 3)));
      final b = schrijf('${root.path}${sep}b.flac', _flac(hz: 44100, bits: 16, md5: List.filled(16, 4)));
      onthoudNultoets(a.path, b.path, Nuluitkomst.lossy);
      final elders = a.renameSync('${root.path}${sep}_dubbel.flac');
      expect(nultoetsUitslag(elders.path, b.path), Nuluitkomst.lossy);
      expect(nultoetsUitslag(b.path, elders.path), isNull, reason: 'de volgorde telt: eerst de 24 bit');
    });
  });

  test('aangesloten: elke weg die keurt, meet eerst; de pc meet en onthoudt', () {
    String bron(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
    final online = bron('lib/online.dart');
    expect(RegExp(r'await bereidNultoets\(').allMatches(online), hasLength(4));
    expect(online, contains('    await bereidNultoets(nieuw.path, bestaand, log: (z) => _log.line(\'   \$z\'));\n'
        '    return bestaand;'));
    expect(online, contains('      await nultoetsTussen(f.path, c, log: (z) => _log.line(\'   \$z\'));\n'
        '      if (firstIsBetter(f, File(c))) continue;'));
    expect(bron('lib/versie_terugzetter.dart'), contains('      await bereidNultoets(f.path, anker);\n'));
    final main = bron('lib/main.dart');
    expect(main, contains(r"    await laadNultoetsen('$appDir${Platform.pathSeparator}nultoets.json');"));
    expect(main, contains('    meetNultoets = Nultoetser().meet;'));
    expect(bron('lib/library.dart'), contains('nul: alleNultoetsen()'));
  });
}

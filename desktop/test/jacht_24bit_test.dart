// "24bit" mee bij de jacht op beter, en het plafond van 5000 dat bij gelijke pasvorm op kwaliteit kiest.
//
// Saber, 24-10-2026, na de proef (scratchpad merk_proef.js): "24bit" achter de vraag vond hi-res die de gewone
// zoekopdracht niet had (Phil Collins +89, Lionel Richie +57, Daft Punk +41). Zijn keuze: alleen "24bit" meezoeken
// bij de jacht (Zoek hi-res, de jacht na ▶/downloaden, de FLAC-wens). En zijn vraag: "ik ga nu toch evenveel
// resultaten hebben dan vroeger e ?? das wel belangrijk" — ja: de gewone vraag blijft, "24bit" komt erbij.
// Over het plafond: "voor het zelfde geldt zijn er voorbij die 5000 resultaten wel goeie kwaliteit tussen".
import 'dart:io';

import 'package:debridmusic/soulseek.dart';
import 'package:debridmusic/zoekladder.dart';
import 'package:debridmusic/zoekplafond.dart';
import 'package:flutter_test/flutter_test.dart';

SoulseekFile _f(String pad,
        {int? rate, int? bits, int size = 30000000, int speed = 500, bool vrij = true, int? kbps, int? sec}) =>
    SoulseekFile(
        username: 'u$pad',
        filename: pad,
        size: size,
        speed: speed,
        freeSlots: vrij,
        sampleRate: rate,
        bitDepth: bits,
        bitrate: kbps,
        durationSec: sec);

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('de extra vraag', () {
    test('"24bit" komt in de eerste ronde bij de gewone vragen; de terugval blijft zoals hij was', () {
      final rondes = zoekRondes('Phil Collins In the Air Tonight (Remastered)');
      final met = metExtraWoorden(rondes, kHiresZoekwoorden);
      expect(met.first.take(rondes.first.length), rondes.first, reason: 'de gewone vragen blijven, vooraan');
      expect(met.first.last, 'Phil Collins In the Air Tonight (Remastered) 24bit');
      expect(met.skip(1), rondes.skip(1), reason: 'de terugval op de eerste twee woorden blijft');
      expect(metExtraWoorden(rondes, const []), rondes);
    });

    test('staat het woord al in de vraag, dan geen tweede keer', () {
      final r = metExtraWoorden(zoekRondes('Daft Punk Discovery 24bit'), kHiresZoekwoorden);
      expect(r.first, ['Daft Punk Discovery 24bit']);
    });

    test('alleen "24bit": niet "vinyl" (alleen als hij kiest), niet "24-bit" of "wav" (gemeten: vinden bijna niets)', () {
      expect(kHiresZoekwoorden, ['24bit']);
    });

    test('bedrading: de vier jachtplekken zoeken mee, de radio en direct zoeken niet', () {
      final online = _bron('lib/online.dart');
      expect(online, contains('hits = await soulseek.search(w.query, achtergrond: true, extra: kHiresZoekwoorden);'),
          reason: 'de FLAC-wens');
      expect(online, contains('extra: zoekBeter ? kHiresZoekwoorden : const [],'), reason: '▶ met opwaarderen, de radio niet');
      expect('achtergrond: true, extra: kHiresZoekwoorden);'.allMatches(online).length, 3,
          reason: 'de wens, en Zoek hi-res voor een album en voor een nummer');
      final main = _bron('lib/main.dart');
      expect('extra: kHiresZoekwoorden,'.allMatches(main).length, 2, reason: 'een nummer downloaden (twee plekken)');
      expect(main, contains("soulseek.search(widget.query, gebruikteVraag:"), reason: 'direct zoeken blijft zonder extra');
      // De pc meldt de gewone vraag als "gebruikt", niet die met 24bit — anders zei het scherm "ruimer gezocht".
      expect(online, contains('gebruikteVraag?.call(gewoon[i].last);'));
    });

    test('een toestel stuurt de woorden mee, en de pc neemt alleen gewone woorden aan, hoogstens drie', () {
      final r = _bron('lib/lan/remote_services.dart');
      expect(r, contains("if (extra.isNotEmpty) 'extra': extra.join(','),"));
      final s = _bron('lib/lan/server.dart');
      expect(s, contains(r"if (RegExp(r'^[A-Za-z0-9-]{2,12}$').hasMatch(w.trim())) w.trim(),"));
      expect(s, contains('].take(3).toList();'));
      expect(s, contains('? await service.search(q, extra: extra)'));
    });
  });

  group('het plafond van 5000', () {
    test('bij gelijke pasvorm valt het slechtst klinkende af, niet de hi-res bij een trage peer', () {
      final vraag = 'Phil Collins In the Air Tonight';
      // In de volgorde van sortSoulseek: FLAC, vrije plek, snelheid. De 600 hi-res kopieën staan achteraan.
      final cd = [
        for (var i = 0; i < 5000; i++)
          _f('Phil Collins\\Face Value\\$i In the Air Tonight.flac', rate: 44100, bits: 16, speed: 9000),
      ];
      final hires = [
        for (var i = 0; i < 600; i++)
          _f('Phil Collins\\Face Value 24\\$i In the Air Tonight.flac', rate: 96000, bits: 24, speed: 10, vrij: false),
      ];
      final uit = beperkZoekuitslag(vraag, [...cd, ...hires]);
      expect(uit, hasLength(kZoekPlafond));
      expect(uit.where((f) => f.bitDepth == 24), hasLength(600), reason: 'geen enkele hi-res kopie valt af');
    });

    test('een mp3 valt eerder af dan een FLAC, ook als hij vooraan stond', () {
      final vraag = 'Bonnie Tyler Secret Dreams';
      final mp3 = [for (var i = 0; i < 10; i++) _f('Bonnie Tyler\\$i Secret Dreams.mp3', kbps: 320, sec: 240, size: 9600000)];
      final flac = [for (var i = 0; i < 5000; i++) _f('Bonnie Tyler\\$i Secret Dreams.flac', rate: 44100, bits: 16)];
      final uit = beperkZoekuitslag(vraag, [...mp3, ...flac]);
      expect(uit.where((f) => f.ext == 'mp3'), isEmpty);
    });

    test('pasvorm gaat nog altijd voor: een hi-res die de vraag slechter dekt, valt eerder af', () {
      final vraag = 'Lionel Richie Hello';
      final goed = [for (var i = 0; i < 5000; i++) _f('Lionel Richie\\Can\'t Slow Down\\$i Hello.flac', rate: 44100, bits: 16)];
      final ander = [for (var i = 0; i < 10; i++) _f('Lionel Richie\\Live\\$i Medley.flac', rate: 96000, bits: 24)];
      final uit = beperkZoekuitslag(vraag, [...ander, ...goed]);
      expect(uit.where((f) => f.filename.contains('Medley')), isEmpty);
    });

    test('onder het plafond verandert er niets, ook de volgorde niet', () {
      final l = [_f('a\\x.mp3', kbps: 128), _f('a\\x.flac', rate: 96000, bits: 24)];
      expect(beperkZoekuitslag('x', l), same(l));
    });

    test('zoekKwaliteit: 24/96 boven 16/44,1 boven een mp3 van 320', () {
      final h = zoekKwaliteit(_f('a.flac', rate: 96000, bits: 24));
      final c = zoekKwaliteit(_f('a.flac', rate: 44100, bits: 16));
      final m = zoekKwaliteit(_f('a.mp3', kbps: 320, sec: 240, size: 9600000));
      expect(h, greaterThan(c));
      expect(c, greaterThan(m));
      expect(zoekKwaliteit(_f('a.wav', rate: 96000, bits: 24)), h, reason: 'een WAV telt als verliesvrij');
    });
  });
}

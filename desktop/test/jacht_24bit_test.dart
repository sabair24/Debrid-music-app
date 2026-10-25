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
    test('"<de volledige vraag> 24bit" als eigen zoekopdracht; staat het woord er al in, dan niet', () {
      expect(extraVragen('Phil Collins In the Air Tonight (Remastered)', kHiresZoekwoorden),
          ['Phil Collins In the Air Tonight (Remastered) 24bit']);
      expect(extraVragen('Daft Punk Discovery 24bit', kHiresZoekwoorden), isEmpty);
      expect(extraVragen('Daft Punk Discovery', const []), isEmpty);
    });

    test('na de gewone ronde, in een eigen venster, en samengevoegd zonder dubbels', () {
      // Gemeten 24-10-2026 (Phil Collins): meegestuurd in hetzelfde venster 9 bestanden met "24bit", als eigen
      // zoekopdracht 112 — het venster van de brede vraag sluit na 3,9 s, de smalle antwoorden komen later.
      final online = _bron('lib/online.dart');
      final s = online.substring(online.indexOf('  Future<List<SoulseekFile>> search(String query,'));
      final lijf = s.substring(0, s.indexOf('\n  }\n'));
      expect(lijf, contains('final gevonden = await _searchOnce(ronde, deel, achtergrond: achtergrond, nogNodig: nogNodig);'));
      expect(lijf, contains('if (i == 0 && !stil) {'), reason: 'alleen na de volledige vraag, niet na de terugval, en niet als de server zwijgt');
      expect(lijf, contains('for (final v in extraVragen(ronde.first, extra)) {'));
      expect(lijf, contains('await _searchOnce([v], null, achtergrond: achtergrond)'), reason: 'een eigen venster');
      expect(lijf, contains("if (al.add('\${f.username}|\${f.filename}')) samen.add(f);"), reason: 'de gewone eerst, geen dubbels');
      expect(lijf, contains('gebruikteVraag?.call(ronde.last);'), reason: 'het scherm meldt de gewone vraag');
    });

    test('alleen "24bit": niet "vinyl" (alleen als hij kiest), niet "24-bit" of "wav" (gemeten: vinden bijna niets)', () {
      expect(kHiresZoekwoorden, ['24bit']);
    });

    test('bedrading: alleen waar niemand wacht — de wens en Zoek hi-res; ▶, downloaden, de radio en direct zoeken niet', () {
      final online = _bron('lib/online.dart');
      expect(online, contains('hits = await soulseek.search(w.query, achtergrond: true, extra: kHiresZoekwoorden);'),
          reason: 'de FLAC-wens');
      expect('achtergrond: true, extra: kHiresZoekwoorden);'.allMatches(online).length, 2,
          reason: 'de wens, en Zoek hi-res (album en nummer delen één zoekregel)');
      // ▶ wacht op de volledige uitslag als er niet meteen een bron is: "24bit" erachter maakte dat 8 s trager.
      final radio = online.substring(online.indexOf('    final zoek = soulseek.search(zoekvraagVoorNummer(titel, artist: artiest),'));
      expect(radio.substring(0, radio.indexOf(');\n')), isNot(contains('extra:')));
      final main = _bron('lib/main.dart');
      expect(main, isNot(contains('extra: kHiresZoekwoorden')), reason: 'downloaden en direct zoeken zonder extra');
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

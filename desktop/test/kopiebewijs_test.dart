// Het kopiebewijs (Saber, 27-10-2026: "Amai, weer een foute meting, zorg er eens voor dat dit goed werkt, daarnet ook al
// bij Céline Dion"): een muur die een andere kopie van dezelfde opname weerlegt, is afgekapt — en wat bewezen nep is naast
// een echte kopie, gaat naar _dubbel.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/echtheid_oordelen.dart';
import 'package:debridmusic/flac_tags.dart' show readFlacTags;
import 'package:debridmusic/keuring.dart';
import 'package:debridmusic/kopiesoort.dart';
import 'package:debridmusic/nultoets_meter.dart' show resetNultoetsVoorTest;
import 'package:debridmusic/versie_opbergen.dart';
import 'package:debridmusic/versies.dart';
import 'package:flutter_test/flutter_test.dart';

Echtheidsoordeel _o(Bandbreedte band, double hz, double db,
        {Bovenband boven = Bovenband.onbekend, Bitdiepte bits = Bitdiepte.spreektNietTegen}) =>
    Echtheidsoordeel(bits: bits, boven: boven, band: band, afkapHz: hz, wandDb: db, gebruikteBits: 24);

/// Een kleine maar echte FLAC-kop: STREAMINFO met [hz], [bits] en [sec] seconden.
Uint8List _flac({required int hz, required int bits, int sec = 200}) {
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
  final tags = {'TITLE': 'Nothing Compares 2 U', 'ARTIST': 'Sinéad O\'Connor', 'ALBUM': 'I Do Not Want', 'TRACKNUMBER': '6'};
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

void main() {
  group('het bewijs zelf', () {
    // De twee gevallen van 27-10-2026, zoals ze in echtheid_oordelen.json stonden.
    final cdDestin = _o(Bandbreedte.doorlopend, 21250, 9.8, bits: Bitdiepte.onbekend);
    final destin = _o(Bandbreedte.doorlopend, 17150, 22.7);
    final cdNc2u = _o(Bandbreedte.doorlopend, 20950, 32.3, bits: Bitdiepte.onbekend);
    final studioNc2u = _o(Bandbreedte.vermoedelijk, 20350, 41.5);
    final vinylNc2u = _o(Bandbreedte.doorlopend, 17500, 7.2, boven: Bovenband.vol);

    test('DE KERN: Destin en Nothing Compares 2 U — je cd loopt verder door dan hun muur', () {
      expect(muurBewezenDoor(destin, cdDestin), isTrue, reason: '22,7 dB op 17,15 kHz; je cd tot 21,25 kHz');
      expect(muurBewezenDoor(studioNc2u, cdNc2u), isTrue, reason: 'vermoedelijk op 20,35 kHz; je cd tot 20,95 kHz');
      expect(muurBewijsZin(cdNc2u, 'cd'), 'je cd loopt door tot 20,95 kHz');
      // En in de keuring: de studio verliest van je cd.
      final k = kwaliteitUit(verliesvrij: true, kopRate: 48000, formaat: 4, oordeel: studioNc2u);
      expect(metMuurBewijs(k, studioNc2u, cdNc2u).klasse, Klasse.uitLossy);
      final kd = kwaliteitUit(verliesvrij: true, kopRate: 44100, formaat: 4, oordeel: destin);
      expect(metMuurBewijs(kd, destin, cdDestin).klasse, Klasse.uitLossy);
    });

    test('DE GRENS: een zachte afloop, je eigen cd-filter of een nep-getuige bewijzen niets', () {
      expect(muurBewezenDoor(vinylNc2u, cdNc2u), isFalse, reason: 'een vinyl die zacht afloopt (7 dB) heeft geen muur');
      expect(muurBewezenDoor(cdNc2u, _o(Bandbreedte.doorlopend, 21600, 5, boven: Bovenband.vol)), isFalse,
          reason: 'het filter van een cd op 21 kHz hoort bij de cd');
      expect(muurBewezenDoor(studioNc2u, _o(Bandbreedte.afgekapt, 21500, 40)), isFalse, reason: 'een nep-getuige telt niet');
      expect(muurBewezenDoor(studioNc2u, _o(Bandbreedte.doorlopend, 20700, 5)), isFalse, reason: 'minder dan 500 Hz verder');
      expect(muurBewezenDoor(_o(Bandbreedte.doorlopend, 17150, 15), cdDestin), isFalse, reason: 'onder 20 dB: geen muur');
    });

    test('het oordeel draagt het bewijs mee, ook na bewaren en inlezen', () {
      final b = studioNc2u.bewezenDoor('je cd loopt door tot 20,95 kHz');
      expect(b.band, Bandbreedte.afgekapt);
      expect(b.isNep, isTrue);
      expect(waarom(b), 'muur op 20,4 kHz, en je cd loopt door tot 20,95 kHz: omgezet uit een lossy bestand');
      final terug = Echtheidsoordeel.fromJson(b.toJson())!;
      expect(terug.bewijs, 'je cd loopt door tot 20,95 kHz');
      expect(terug.isNep, isTrue);
      expect(echteResolutie(terug, kopSampleRate: 48000, kopBits: 24), 'tot 20,4 kHz', reason: 'zonder vraagteken');
    });
  });

  group('de opruiming: één per soort, en geen nep naast een echte kopie', () {
    late Directory root;
    late String sep, anker;

    File schrijf(String pad, Uint8List bytes) {
      final f = File(pad);
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(bytes);
      return f;
    }

    setUp(() {
      root = Directory.systemTemp.createTempSync('dm_kopiebewijs_');
      sep = Platform.pathSeparator;
      anker = '${root.path}${sep}Albums${sep}Sinéad O\'Connor${sep}I Do Not Want${sep}06 - Nothing Compares 2 U.flac';
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
    String versie(String map, Kopiesoort soort, int hz, int bits, Echtheidsoordeel o, {Kopiesoort ankerSoort = Kopiesoort.cd}) {
      final pad = '${root.path}${sep}Albums${sep}Sinéad O\'Connor$sep$map${sep}06 - Nothing Compares 2 U.flac';
      schrijf(pad, _flac(hz: hz, bits: bits, sec: 310 + bits));
      versies.voegToe(anker, Versie(pad: pad, soort: soort, persing: '', sindsMs: 1), ankerSoort: ankerSoort);
      zetSoort(pad, soort);
      onthoudOordeelVanPc(pad, o);
      return pad;
    }

    test('DE KERN: Nothing Compares 2 U — de "studio" bewezen door je cd naar _dubbel; cd en vinyl blijven', () async {
      schrijf(anker, _flac(hz: 44100, bits: 16, sec: 310));
      zetSoort(anker, Kopiesoort.cd);
      onthoudOordeelVanPc(anker, _o(Bandbreedte.doorlopend, 20950, 32.3, bits: Bitdiepte.onbekend));
      final studio = versie('I Do Not Want (studio)', Kopiesoort.studio, 48000, 24, _o(Bandbreedte.vermoedelijk, 20350, 41.5));
      final vinyl = versie('I Do Not Want (vinyl)', Kopiesoort.vinyl, 192000, 24,
          _o(Bandbreedte.doorlopend, 17500, 7.2, boven: Bovenband.vol));
      versies.kies(anker, versieSleutel(Kopiesoort.studio, ''), bereik: VersieBereik.nummer);
      final regels = <String>[];
      final r = await eenPerSoort(dubbel: dubbel(), log: regels.add);
      expect(r.kopiebewijs, 1);
      expect(r.nep, 1);
      expect(File(studio).existsSync(), isFalse);
      expect(inDubbel(), hasLength(1), reason: 'niets gewist: 30 dagen in _dubbel');
      expect(gemeten(inDubbel().single.path)?.bewijs, 'je cd loopt door tot 20,95 kHz',
          reason: 'het bewijs verhuist mee, en staat zo in _dubbel');
      expect([for (final v in versies.versiesVan(anker)) v.pad], [vinyl]);
      expect(readFlacTags(File(anker))?.bitsPerSample, 16, reason: 'je cd blijft het nummer');
      expect(regels.join('\n'), contains('kopiebewijs'));
      expect(regels.join('\n'), contains('naar _dubbel — muur op 20,4 kHz, en je cd loopt door tot 20,95 kHz'));
      // Een tweede keer: niets meer te doen.
      final r2 = await eenPerSoort(dubbel: dubbel());
      expect((r2.kopiebewijs, r2.nep, r2.naarDubbel), (0, 0, 0));
    });

    test('een nep-nummer naast een echte studio-versie: de studio wordt het nummer', () async {
      // Lisa Stansfield — All Around the World: het nummer afgekapt, een eerlijke studio ernaast.
      schrijf(anker, _flac(hz: 44100, bits: 16, sec: 310));
      zetSoort(anker, Kopiesoort.cd);
      onthoudOordeelVanPc(anker, _o(Bandbreedte.afgekapt, 16000, 60, bits: Bitdiepte.onbekend));
      versie('I Do Not Want (studio)', Kopiesoort.studio, 96000, 24, _o(Bandbreedte.doorlopend, 21800, 5, boven: Bovenband.vol));
      final regels = <String>[];
      final r = await eenPerSoort(dubbel: dubbel(), log: regels.add);
      expect(r.nep, 1);
      expect(readFlacTags(File(anker))?.sampleRate, 96000, reason: 'de studio op de plek van het nummer');
      expect(versies.versiesVan(anker), isEmpty);
      expect(inDubbel(), hasLength(1));
      expect(regels.join('\n'), contains('het nummer is'));
    });

    test('DE GRENS: zonder echte kopie ernaast blijft alles staan', () async {
      schrijf(anker, _flac(hz: 44100, bits: 16, sec: 310));
      zetSoort(anker, Kopiesoort.cd);
      onthoudOordeelVanPc(anker, _o(Bandbreedte.afgekapt, 16000, 60, bits: Bitdiepte.onbekend));
      final studio = versie('I Do Not Want (studio)', Kopiesoort.studio, 48000, 24, _o(Bandbreedte.afgekapt, 17300, 31));
      final r = await eenPerSoort(dubbel: dubbel());
      expect((r.nep, r.naarDubbel), (0, 0));
      expect(File(studio).existsSync(), isTrue);
      expect(File(anker).existsSync(), isTrue);
    });

    test('bij binnenkomst: wat je cd weerlegt, is afgekapt vóór de keuring beslist', () async {
      schrijf(anker, _flac(hz: 44100, bits: 16, sec: 310));
      zetSoort(anker, Kopiesoort.cd);
      onthoudOordeelVanPc(anker, _o(Bandbreedte.doorlopend, 21250, 9.8, bits: Bitdiepte.onbekend));
      final binnen = schrijf('${root.path}$sep.incoming${sep}07 - Destin.flac', _flac(hz: 44100, bits: 24, sec: 254));
      onthoudOordeelVanPc(binnen.path, _o(Bandbreedte.doorlopend, 17150, 22.7));
      await bereidNultoets(binnen.path, anker);
      expect(bewezenNep(binnen.path), isTrue);
      expect(gemeten(binnen.path)?.bewijs, 'je cd loopt door tot 21,25 kHz');
    });
  });

  test('aangesloten: de jacht bergt geen nep op als versie; elke keuring doet eerst het kopiebewijs', () {
    String bron(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
    final online = bron('lib/online.dart');
    expect(online, contains(r'''      _log.line('   $bron: "$naam" is ${waarom(oordeel)} — geen versie, weggegooid');'''));
    expect(online, contains('x.soort == soort && !bewezenNep(x.pad)'));
    expect(bron('lib/versie_opbergen.dart'), contains('  await merkKopiebewijs(kandidaat, anderen, log: log);'));
  });
}

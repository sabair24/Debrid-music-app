// Versies bewaren in plaats van vervangen (Saber, 26-10-2026): "Behoud ik alles e, cd, studio, en vinyl" — en per nummer
// hoogstens één van elke soort (27-10-2026): "Das teveel, enkel studio, cd of vinyl drie soorten".
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/kopiesoort.dart';
import 'package:debridmusic/flac_tags.dart' show readFlacTags;
import 'package:debridmusic/organize.dart' show readTags, writeTagFields;
import 'package:debridmusic/versie_opbergen.dart';
import 'package:debridmusic/versies.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een kleine maar echte FLAC: STREAMINFO met [hz], [bits] en [sec] seconden, de tags, en wat "audio" ([vulling] maakt
/// hem groter of kleiner).
Uint8List _flac(
    {required int hz,
    required int bits,
    int sec = 200,
    required Map<String, String> tags,
    int vulling = 4096,
    List<int>? md5}) {
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
    final verwacht = '${root.path}${sep}Albums${sep}Spice Girls${sep}Spice (vinyl)${sep}01 - Wannabe.flac';
    expect(uit?.pad, verwacht);
    expect(uit?.werdAnker, isFalse);
    expect(File(verwacht).existsSync(), isTrue);
    expect(File(anker).existsSync(), isTrue, reason: 'het nummer blijft staan');
    expect(binnen.existsSync(), isFalse);
    expect(versies.ankerVan(verwacht), anker);
    expect(versies.versie(verwacht)?.sindsMs, DateTime(2026, 10, 26, 14).millisecondsSinceEpoch);
    expect(readTags(File(verwacht))?.album, 'Spice (vinyl)', reason: 'een eigen album per soort, ook in Roon');
    expect(versies.versie(verwacht)?.persing, 'LP 1996 PBTHAL', reason: 'de persing blijft in het label');
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
        // Een seconde langer dan de cd: een vinylrip is nooit tot op het sample even lang (anders is hij een tweeling).
        _flac(hz: 44100, bits: 16, sec: 201, tags: {'TITLE': 'Wannabe', 'ARTIST': 'Spice Girls'}, vulling: 9000));
    final p2 = versieplanVoor(mindere, anker, r'Y\Spice [vinyl rip]\A1.flac');
    expect(p2.besluit, Versiebesluit.vervangVersie);
    final v2 = await bergOpAlsVersie(mindere, p2, root: root.path);
    expect(v2?.verloor, isTrue);
    expect(mindere.existsSync(), isFalse, reason: 'twee rips van dezelfde persing: de mindere gaat weg');
    expect(versies.versiesVan(anker).single.pad, v1!.pad);
  });

  test('een andere vinylpersing is geen tweede versie meer: één vinyl, de bewezen betere (Saber 27-10-2026)', () async {
    final a = schrijf('${root.path}$sep${'_keuring'}${sep}a${sep}A1.flac',
        _flac(hz: 96000, bits: 24, tags: {'TITLE': 'Wannabe', 'ARTIST': 'Spice Girls'}));
    await bergOpAlsVersie(a, versieplanVoor(a, anker, r'X\1996 - Spice (Vinyl 24-96)\A1.flac'), root: root.path);
    final b = schrijf('${root.path}$sep${'_keuring'}${sep}b${sep}A1.flac',
        _flac(hz: 96000, bits: 24, sec: 201, tags: {'TITLE': 'Wannabe', 'ARTIST': 'Spice Girls'}));
    final p = versieplanVoor(b, anker, r'Y\Spice (2016 Vinyl Reissue) [24-96]\A1.flac');
    expect(p.besluit, Versiebesluit.vervangVersie);
    final uit = await bergOpAlsVersie(b, p, root: root.path);
    expect(uit?.verloor, isTrue, reason: 'niet bewezen beter: wat er al was, blijft');
    expect([for (final v in versies.versiesVan(anker)) v.persing], ['LP 1996']);
  });

  test('bewaren wat jij koos (dwing): de versie van dezelfde soort gaat naar _dubbel, ook als de nieuwe niet beter is', () async {
    final a = schrijf('${root.path}$sep${'_keuring'}${sep}a${sep}A1.flac',
        _flac(hz: 96000, bits: 24, tags: {'TITLE': 'Wannabe', 'ARTIST': 'Spice Girls'}));
    final oud = (await bergOpAlsVersie(a, versieplanVoor(a, anker, r'X\Spice (Vinyl 24-96)\A1.flac'), root: root.path))!.pad;
    final b = schrijf('${root.path}$sep${'_keuring'}${sep}b${sep}A1.flac',
        _flac(hz: 96000, bits: 24, sec: 199, tags: {'TITLE': 'Wannabe', 'ARTIST': 'Spice Girls'}));
    final p = versieplanVoor(b, anker, r'Y\Spice [vinyl rip]\A1.flac');
    expect(p.besluit, Versiebesluit.vervangVersie);
    final uit = await bergOpAlsVersie(b, p, root: root.path, dwing: true);
    expect(uit?.verloor, isFalse);
    expect(versies.versiesVan(anker), hasLength(1));
    expect(readFlacTags(File(versies.versiesVan(anker).single.pad))?.duration?.inSeconds, 199, reason: 'de gekozen kopie');
    expect(File(oud).existsSync() && readFlacTags(File(oud))?.duration?.inSeconds == 200, isFalse,
        reason: 'de vorige staat niet meer als versie');
    final dubbel = Directory('${root.path}${sep}_dubbel');
    expect(dubbel.existsSync() && dubbel.listSync(recursive: true).whereType<File>().isNotEmpty, isTrue);
  });


  group('tweeling: dezelfde rip onder een ander etiket (27-10-2026: Cutting Crew, Voyager)', () {
    test('zelfde kop en een van beide vinyl; digitaal alleen met dezelfde controlesom; nooit bij een andere kop', () {
      File f(String n, {int bits = 24, int sec = 279, List<int>? md5, int vulling = 4096}) =>
          schrijf('${root.path}${sep}t${sep}$n.flac', _flac(hz: 96000, bits: bits, sec: sec, tags: _tags, md5: md5, vulling: vulling));
      final a = f('a'), b = f('b', vulling: 9000), c = f('c', bits: 16), d = f('d', sec: 280);
      expect(isTweeling(a.path, Kopiesoort.studio, b.path, Kopiesoort.vinyl), isTrue, reason: 'Dymokust zonder COMMENT');
      expect(isTweeling(a.path, Kopiesoort.studio, b.path, Kopiesoort.cd), isFalse,
          reason: 'een studiokopie en de cd van één master zijn even lang — zonder controlesom geen bewijs');
      expect(isTweeling(a.path, Kopiesoort.studio, c.path, Kopiesoort.vinyl), isFalse, reason: 'een andere diepte');
      expect(isTweeling(a.path, Kopiesoort.studio, d.path, Kopiesoort.vinyl), isFalse, reason: 'een seconde langer');
      final x = f('x', md5: List.filled(16, 7)), y = f('y', md5: List.filled(16, 7)), z = f('z', md5: List.filled(16, 8));
      expect(isTweeling(x.path, Kopiesoort.studio, y.path, Kopiesoort.cd), isTrue, reason: 'bit voor bit (Voyager)');
      expect(isTweeling(x.path, Kopiesoort.studio, z.path, Kopiesoort.cd), isFalse);
    });

    test('een "studio" die je nummer zelf is (een vinylrip): gewoon vergelijken — het nummer gaat niet opzij', () {
      schrijf(anker, _flac(hz: 96000, bits: 24, sec: 207, tags: _tags));
      zetSoort(anker, Kopiesoort.vinyl);
      final tweeling = schrijf('${root.path}$sep${'_keuring'}${sep}s${sep}01.flac',
          _flac(hz: 96000, bits: 24, sec: 207, tags: {'TITLE': 'Wannabe', 'ARTIST': 'Spice Girls'}));
      final p = versieplanVoor(tweeling, anker, r'floresnico\Spice [24-96]\01.flac');
      expect(p.soort, Kopiesoort.vinyl);
      expect(p.besluit, Versiebesluit.gewoon, reason: 'anders: studio boven vinyl, en je nummer ging opzij voor zichzelf');
    });

    test('DE KERN: een "studio" die je vinylrip is, verliest van die vinylrip — je cd blijft het nummer', () async {
      final vinylBinnen = schrijf('${root.path}$sep${'_keuring'}${sep}v${sep}A1.flac',
          _flac(hz: 96000, bits: 24, sec: 207, tags: {'TITLE': 'Wannabe', 'ARTIST': 'Spice Girls'}, vulling: 30000));
      final vinyl =
          await bergOpAlsVersie(vinylBinnen, versieplanVoor(vinylBinnen, anker, r'RUTRACKER\Spice (Vinyl 24-96)\A1.flac'), root: root.path);
      // Dezelfde rip, zonder vinyl in pad of tags: hij zou "studio" heten en je cd opzij zetten.
      final tweeling = schrijf('${root.path}$sep${'_keuring'}${sep}s${sep}01.flac',
          _flac(hz: 96000, bits: 24, sec: 207, tags: {'TITLE': 'Wannabe', 'ARTIST': 'Spice Girls'}, vulling: 30000));
      const bron = r'floresnico\Spice [24-96]\01.flac';
      expect(soortVanBestand(tweeling.path, bron), Kopiesoort.studio, reason: 'zo kwam hij binnen');
      final p = versieplanVoor(tweeling, anker, bron);
      expect(p.soort, Kopiesoort.vinyl);
      expect(p.besluit, Versiebesluit.vervangVersie);
      expect(p.vervangt?.pad, vinyl!.pad);
      final uit = await bergOpAlsVersie(tweeling, p, root: root.path);
      expect(uit?.verloor, isTrue);
      expect(versies.groep(anker)?.soort, Kopiesoort.cd);
      expect(readFlacTags(File(anker))?.sampleRate, 44100, reason: 'je cd staat nog op zijn plek');
    });
  });

  group('eenPerSoort: wat er al dubbel lag', () {
    String dubbel() => '${root.path}${sep}_dubbel';
    String versie(String map, Kopiesoort soort, String persing,
        {int hz = 96000, int bits = 24, int sec = 200, int sinds = 0, Kopiesoort ankerSoort = Kopiesoort.cd}) {
      final pad = '${root.path}${sep}Albums${sep}Spice Girls$sep$map${sep}01 - Wannabe.flac';
      schrijf(pad, _flac(hz: hz, bits: bits, sec: sec, tags: {..._tags, 'ALBUM': map}));
      versies.voegToe(anker, Versie(pad: pad, soort: soort, persing: persing, sindsMs: sinds), ankerSoort: ankerSoort);
      zetSoort(pad, soort);
      return pad;
    }

    List<File> inDubbel() => Directory(dubbel()).existsSync()
        ? Directory(dubbel()).listSync(recursive: true).whereType<File>().toList()
        : const [];

    test('DE KERN: Discovery — drie vinyls bij één nummer: één blijft, in "Spice (vinyl)"; de rest naar _dubbel', () async {
      zetSoort(anker, Kopiesoort.cd);
      final a = versie('Spice (vinyl LP 2001)', Kopiesoort.vinyl, 'LP 2001', sinds: 1);
      versie('Spice (vinyl LP 2021)', Kopiesoort.vinyl, 'LP 2021', sec: 201, sinds: 2);
      versie('Spice (vinyl LP 2001 andere kopie)', Kopiesoort.vinyl, 'LP 2001 andere kopie', sec: 202, sinds: 3);
      final regels = <String>[];
      final r = await eenPerSoort(dubbel: dubbel(), log: regels.add);
      expect(r.naarDubbel, 2);
      expect(r.verhuisd, 1);
      final blijft = versies.versiesVan(anker).single;
      expect(blijft.pad, '${root.path}${sep}Albums${sep}Spice Girls${sep}Spice (vinyl)${sep}01 - Wannabe.flac');
      expect(blijft.persing, 'LP 2001', reason: 'gelijkspel: de oudste blijft');
      expect(readFlacTags(File(blijft.pad))?.duration?.inSeconds, 200);
      expect(readTags(File(blijft.pad))?.album, 'Spice (vinyl)');
      expect(soortVoor(blijft.pad)?.soort, Kopiesoort.vinyl);
      expect(File(a).existsSync(), isFalse);
      expect(Directory(File(a).parent.path).existsSync(), isFalse, reason: 'de lege persingmap is weg');
      expect(inDubbel(), hasLength(2), reason: 'niets gewist: 30 dagen in _dubbel');
      expect(File(anker).existsSync(), isTrue);
      expect(regels.where((x) => x.contains('naar _dubbel')), hasLength(2));
    });

    test('bij gelijkspel blijft de versie die je koos', () async {
      versie('Spice (vinyl LP 2001)', Kopiesoort.vinyl, 'LP 2001', sinds: 1);
      versie('Spice (vinyl LP 2021)', Kopiesoort.vinyl, 'LP 2021', sec: 201, sinds: 2);
      versies.kies(anker, versieSleutel(Kopiesoort.vinyl, 'LP 2021'), bereik: VersieBereik.nummer);
      await eenPerSoort(dubbel: dubbel());
      final blijft = versies.versiesVan(anker).single;
      expect(blijft.persing, 'LP 2021');
      expect(versies.speelVersie(anker)?.pad, blijft.pad, reason: 'je keuze blijft gelden');
    });

    test('DE KERN: het nummer is een tweeling van je vinylversie — naar _dubbel, en je cd is weer het nummer', () async {
      // Cutting Crew, 27-10-2026: floresnico's "studio" 32/384 was Dymokust's vinylrip; je cd ging opzij als versie.
      schrijf(anker, _flac(hz: 96000, bits: 24, sec: 279, tags: _tags));
      zetSoort(anker, Kopiesoort.studio);
      versie('Spice (vinyl)', Kopiesoort.vinyl, '', sec: 279, sinds: 1, ankerSoort: Kopiesoort.studio);
      versie('Spice (cd)', Kopiesoort.cd, '', hz: 44100, bits: 16, sec: 280, sinds: 2, ankerSoort: Kopiesoort.studio);
      final regels = <String>[];
      final r = await eenPerSoort(dubbel: dubbel(), log: regels.add);
      expect(r.tweelingen, 1);
      expect(readFlacTags(File(anker))?.sampleRate, 44100, reason: 'de cd op de plek van het nummer');
      expect(readTags(File(anker))?.album, 'Spice', reason: 'het nummer hoort bij zijn album');
      expect(versies.groep(anker)?.soort, Kopiesoort.cd);
      expect(soortVoor(anker)?.soort, Kopiesoort.cd);
      expect([for (final v in versies.versiesVan(anker)) v.soort], [Kopiesoort.vinyl], reason: 'de echte vinylrip blijft');
      expect(inDubbel().single.lengthSync(), greaterThan(0), reason: 'de tweeling in _dubbel, niet gewist');
      expect(regels.single, contains('dezelfde rip'));
      expect(Directory('${root.path}${sep}Albums${sep}Spice Girls${sep}Spice (cd)').existsSync(), isFalse,
          reason: 'de versiemap van de cd bleef leeg achter (Cutting Crew)');
    });

    test('al in de map van zijn soort, maar de albumnaam draagt nog een persing: rechtgezet (Voyager)', () async {
      final pad = versie('Spice (vinyl)', Kopiesoort.vinyl, 'LP 2022', sinds: 1);
      await writeTagFields(File(pad), {'ALBUM': 'Spice (vinyl LP 2022)'});
      final r = await eenPerSoort(dubbel: dubbel());
      expect(r.albumnaam, 1);
      expect(readTags(File(pad))?.album, 'Spice (vinyl)');
      expect((await eenPerSoort(dubbel: dubbel())).albumnaam, 0, reason: 'een tweede keer niets: geen tags herschrijven');
    });

    test('wat speelt, blijft tot de volgende start', () async {
      versie('Spice (vinyl LP 2001)', Kopiesoort.vinyl, 'LP 2001', sinds: 1);
      versie('Spice (vinyl LP 2021)', Kopiesoort.vinyl, 'LP 2021', sec: 201, sinds: 2);
      final r = await eenPerSoort(dubbel: dubbel(), inGebruik: (p) => p == anker);
      expect(r.overgeslagen, 1);
      expect(versies.versiesVan(anker), hasLength(2));
      expect(inDubbel(), isEmpty);
    });

    test('één per soort en al in de map van zijn soort: niets te doen', () async {
      versie('Spice (vinyl)', Kopiesoort.vinyl, 'LP 2001', sinds: 1);
      final r = await eenPerSoort(dubbel: dubbel());
      expect((r.naarDubbel, r.verhuisd, r.tweelingen, r.albumnaam), (0, 0, 0, 0));
    });
  });
}

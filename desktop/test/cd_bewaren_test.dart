// De cd-kwaliteit blijft bij elk nummer (Saber, 05-11-2026): "kunnen we ervoor zorgen dat zoiezo bij alle liedjes de cd
// kwaliteit wordt bijgehouden. dus wel nog betere versies zoeken, maar de cd kwaliteit mag zoiezo blijven, uitgenomen als
// die wordt afgekapt, dan blijven zoeken naar een niet afgekapte cd kwaliteit versie."
//
// Gemeten die dag: 1241 van de 1961 nummers hadden een schone cd. Bruno Mars — Locked out of Heaven verloor zijn cd om
// 12:56: een 24/96 die zich vinyl noemde maar digitaal bleek, telde als cd en won op zijn diepte.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/echtheid_oordelen.dart';
import 'package:debridmusic/fingerprint.dart';
import 'package:debridmusic/flac_tags.dart' show readFlacTags;
import 'package:debridmusic/kopiesoort.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/organize.dart' show readTags;
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/soortjacht.dart';
import 'package:debridmusic/tidaler.dart' show Tidaler;
import 'package:debridmusic/twijfel.dart';
import 'package:debridmusic/versie_opbergen.dart';
import 'package:debridmusic/versie_terugzetter.dart';
import 'package:debridmusic/versies.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een kleine maar echte FLAC: STREAMINFO met [hz], [bits] en [sec] seconden, de tags, en wat "audio".
Uint8List _flac({required int hz, required int bits, int sec = 200, Map<String, String> tags = const {}, int vulling = 4096}) {
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

Echtheidsoordeel _o(Bandbreedte band, {Integriteit integriteit = Integriteit.onbekend}) => Echtheidsoordeel(
    bits: Bitdiepte.spreektNietTegen,
    boven: Bovenband.onbekend,
    band: band,
    afkapHz: band == Bandbreedte.afgekapt ? 16000 : 21000,
    wandDb: 10,
    gebruikteBits: 16,
    integriteit: integriteit);

/// Alles klinkt hetzelfde (1,00), behalve wat in _dubbel staat met [dubbelBits] andere bits per 32: 4 geeft 0,875 (een
/// andere mastering), 8 geeft 0,75.
class _NepVingerafdruk extends Fingerprinter {
  _NepVingerafdruk({this.dubbelBits = 0});
  final int dubbelBits;
  @override
  bool get available => true;
  @override
  Future<Fingerprint?> of(String path, {bool compressed = false, bool heel = false}) async {
    final anders = path.contains('_dubbel') ? (1 << dubbelBits) - 1 : 0;
    // Willekeurig ogende waarden: een andere verschuiving past dan nergens (~0,5), alleen de juiste.
    return Fingerprint(200, [for (var i = 0; i < 400; i++) ((i * 2654435761) & 0xFFFFFFFF) ^ anders], null);
  }
}

(int, int) _kop(String pad) {
  final k = readFlacTags(File(pad));
  return (k?.bitsPerSample ?? 0, k?.sampleRate ?? 0);
}

void main() {
  late Directory root;
  late String sep;

  File schrijf(String pad,
      {required int hz, required int bits, Map<String, String> tags = const {}, int vulling = 4096, int sec = 200}) {
    final f = File(pad)..parent.createSync(recursive: true);
    f.writeAsBytesSync(_flac(hz: hz, bits: bits, sec: sec, tags: tags, vulling: vulling));
    return f;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('dm_cd_bewaren_');
    sep = Platform.pathSeparator;
    versies.wis();
    resetSoortenVoorToets();
    resetEchtheidVoorTest();
    Tidaler.zetVoorToets(pad: null);
  });
  tearDown(() {
    versies.wis();
    resetSoortenVoorToets();
    resetEchtheidVoorTest();
    Tidaler.resetLookup();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  String album(String map, String naam) => '${root.path}${sep}Albums${sep}Bruno Mars$sep$map$sep$naam';

  group('je cd raakt niet meer weg', () {
    test('DE KERN (Bruno Mars, 05-11-2026): een 24-bitkopie die als cd geteld werd, is studio — je cd gaat opzij als versie',
        () {
      final anker = schrijf(album('Unorthodox Jukebox', 'Locked out of Heaven.flac'), hz: 44100, bits: 16).path;
      final nieuw = schrijf('${root.path}$sep${'_keuring'}${sep}a${sep}Locked.flac', hz: 96000, bits: 24);
      // Zo noteerde het vinylspoor hem: "noemt zich vinyl, maar is digitaal — telt als cd".
      zetSoort(nieuw.path, Kopiesoort.cd);
      final plan = versieplanVoor(nieuw, anker, r'@@fiatchd\Bruno Mars [Vinyl 24-96]\02.flac');
      expect(plan.soort, Kopiesoort.studio, reason: 'studio = alles 24 bit digitaal');
      expect(plan.besluit, Versiebesluit.ankerOpzij, reason: 'niet "gewoon": dan won hij en ging je cd naar _dubbel');
    });

    test('een digitale "vinyl": in 24 bit studio, in 16 bit cd', () {
      final a = schrijf('${root.path}${sep}a.flac', hz: 96000, bits: 24).path;
      final b = schrijf('${root.path}${sep}b.flac', hz: 44100, bits: 16).path;
      expect(digitaleSoort(a), Kopiesoort.studio);
      expect(digitaleSoort(b), Kopiesoort.cd);
    });

    test('een cd naast een gezond nummer zonder soort (16/48, AIFF) blijft als versie; naast een afgekapt nummer vervangt hij',
        () {
      expect(
          versiebesluit(soort: Kopiesoort.cd, persing: '', ankerSoort: null, ankerPersing: '', ankerSchoonZonderSoort: true)
              .besluit,
          Versiebesluit.nieuweVersie);
      expect(versiebesluit(soort: Kopiesoort.cd, persing: '', ankerSoort: null, ankerPersing: '').besluit,
          Versiebesluit.gewoon, reason: 'zonder de vlag zoals altijd: de keuring beslist');
      final oud = Versie(pad: 'x', soort: Kopiesoort.cd);
      final b = versiebesluit(
          soort: Kopiesoort.cd,
          persing: '',
          ankerSoort: null,
          ankerPersing: '',
          bestaande: [oud],
          ankerSchoonZonderSoort: true);
      expect(b.besluit, Versiebesluit.vervangVersie, reason: 'één cd per nummer');
      expect(b.vervangt, oud);

      final web = schrijf(album('Doo-Wops', 'Grenade.flac'), hz: 48000, bits: 16).path;
      final cd = schrijf('${root.path}$sep${'_keuring'}${sep}b${sep}Grenade.flac', hz: 44100, bits: 16);
      final plan = versieplanVoor(cd, web, r'@@x\Doo-Wops (CD)\Grenade.flac');
      expect(plan.besluit, Versiebesluit.nieuweVersie, reason: 'je 16/48 blijft, de cd komt erbij');

      final mp3cd = schrijf(album('Doo-Wops', 'Just the Way You Are.flac'), hz: 44100, bits: 16).path;
      onthoudOordeelVanPc(mp3cd, _o(Bandbreedte.afgekapt));
      final schoon = schrijf('${root.path}$sep${'_keuring'}${sep}c${sep}Just.flac', hz: 44100, bits: 16);
      expect(versieplanVoor(schoon, mp3cd, r'@@y\Doo-Wops\Just.flac').besluit, Versiebesluit.gewoon,
          reason: 'een afgekapte cd mag weg: de schone neemt zijn plaats in');
    });
  });

  group('een schone cd', () {
    test('16/44,1 verliesvrij als cd, niet afgekapt en niet kapot — het nummer zelf of een versie', () {
      final cd = schrijf(album('A', '1.flac'), hz: 44100, bits: 16).path;
      expect(heeftSchoneCd(cd), isTrue);
      onthoudOordeelVanPc(cd, _o(Bandbreedte.afgekapt));
      expect(heeftSchoneCd(cd), isFalse, reason: 'afgekapt: bewezen uit een mp3');
      onthoudOordeelVanPc(cd, _o(Bandbreedte.doorlopend, integriteit: Integriteit.fout));
      expect(heeftSchoneCd(cd), isFalse, reason: 'kapot: de controlesom klopt niet');
      onthoudOordeelVanPc(cd, _o(Bandbreedte.vermoedelijk));
      expect(heeftSchoneCd(cd), isTrue, reason: 'een muur rond 20 kHz zonder bewijs is meestal het filter van de cd zelf');

      final studio = schrijf(album('B', '1.flac'), hz: 96000, bits: 24).path;
      expect(heeftSchoneCd(studio), isFalse);
      final versie = schrijf(album('B (cd)', '1.flac'), hz: 44100, bits: 16).path;
      versies.voegToe(studio, Versie(pad: versie, soort: Kopiesoort.cd), ankerSoort: Kopiesoort.studio);
      expect(heeftSchoneCd(studio), isTrue);

      final vinyl = schrijf(album('C', '1.flac'), hz: 44100, bits: 16).path;
      zetSoort(vinyl, Kopiesoort.vinyl);
      expect(heeftSchoneCd(vinyl), isFalse, reason: 'een vinylrip naar 16 bit is geen cd');
      final web = schrijf(album('D', '1.flac'), hz: 48000, bits: 16).path;
      expect(heeftSchoneCd(web), isFalse);
    });
  });

  group('de cd-jacht', () {
    late DownloadManager d;
    late List<Track> nummers;

    setUp(() {
      nummers = [];
      d = DownloadManager(OnlineService(AppSettings()), SoulseekService(AppSettings()), root.path, () async {})
        ..twijfel = Twijfellijst('${root.path}${sep}twijfel.json')
        ..soortvragen = Soortvragen('${root.path}${sep}soortvragen.json')
        ..cdjacht = Soortvragen('${root.path}${sep}cdjacht.json', toon: false)
        ..cdjachtNummers = (() => nummers)
        ..cdjachtVanaf = DateTime(2000);
    });

    Track nummer(String pad, String titel, {String plaat = 'Unorthodox Jukebox'}) =>
        Track(path: pad, title: titel, artist: 'Bruno Mars', album: plaat, duration: const Duration(seconds: 200));

    test('DE KERN: wie geen schone cd heeft, krijgt een stille vraag; wie er een kreeg, telt mee', () async {
      final cd = schrijf(album('Unorthodox Jukebox', '01.flac'), hz: 44100, bits: 16).path;
      final studio = schrijf(album('Unorthodox Jukebox', '02.flac'), hz: 96000, bits: 24).path;
      final mp3 = schrijf(album('Unorthodox Jukebox', '03.flac'), hz: 44100, bits: 16).path;
      onthoudOordeelVanPc(mp3, _o(Bandbreedte.afgekapt));
      nummers = [nummer(cd, 'Young Girls'), nummer(studio, 'Locked out of Heaven'), nummer(mp3, 'Gorilla')];
      final r = await d.cdjachtVegen();
      expect(r.nieuw, 2);
      expect(d.cdjacht!.van(cd), isNull, reason: 'heeft al een schone cd');
      final v = d.cdjacht!.van(studio)!;
      expect(v.vanzelf, isTrue);
      expect(v.soort, Kopiesoort.cd);
      expect(v.gezag?['title'], 'Locked out of Heaven');
      expect(d.cdjacht!.van(mp3), isNotNull, reason: 'afgekapt: hij zoekt een schone');
      expect(gezochtVoor(studio), isNull, reason: 'geen "zoekt cd" bij honderden nummers op het scherm');
      expect(d.cdjachtStand.value.zin, 'Cd erbij: 0 · zoekt nog 2');

      final versie = schrijf(album('Unorthodox Jukebox (cd)', '02.flac'), hz: 44100, bits: 16).path;
      versies.voegToe(studio, Versie(pad: versie, soort: Kopiesoort.cd), ankerSoort: Kopiesoort.studio);
      final r2 = await d.cdjachtVegen();
      expect(r2.binnen, 1);
      expect(d.cdjacht!.van(studio), isNull);
      expect(d.cdjachtStand.value.zin, 'Cd erbij: 1 · zoekt nog 1');

      // Bewaard: na een herstart weet hij het nog.
      final terug = Soortvragen('${root.path}${sep}cdjacht.json', toon: false);
      await terug.laad();
      expect(terug.binnen, 1);
      expect(terug.van(mp3)?.vanzelf, isTrue);
    });

    test('één plaat per ronde; zonder vondst over 2 dagen opnieuw, en niet vóór het opstarten klaar is', () async {
      final a1 = schrijf(album('Unorthodox Jukebox', '02.flac'), hz: 96000, bits: 24).path;
      final a2 = schrijf(album('Unorthodox Jukebox', '04.flac'), hz: 96000, bits: 24).path;
      final b1 = schrijf(album('Doo-Wops', '01.flac'), hz: 96000, bits: 24).path;
      nummers = [nummer(a1, 'Locked out of Heaven'), nummer(a2, 'Treasure'), nummer(b1, 'Grenade', plaat: 'Doo-Wops')];
      d.cdjachtVanaf = DateTime.now().add(const Duration(minutes: 5));
      await d.cdjachtRonde();
      expect(d.cdjacht!.alle, isEmpty, reason: 'vóór het opstarten klaar is, doet hij niets');
      d.cdjachtVanaf = DateTime(2000);
      await d.cdjachtRonde();
      expect(d.cdjacht!.alle.length, 3);
      final gezocht = [for (final v in d.cdjacht!.alle) if (v.rondes > 0) v];
      expect(gezocht.length, anyOf(1, 2));
      expect({for (final v in gezocht) v.album}.length, 1, reason: 'één plaat per ronde');
      for (final v in gezocht) {
        expect(v.aanDeBeurt(DateTime.now().add(const Duration(days: 1))), isFalse);
        expect(v.aanDeBeurt(DateTime.now().add(const Duration(days: 2, minutes: 1))), isTrue);
      }
    });

    test('wat de cd-jacht van 3.9.716 weggooide (een andere mastering), haalt hij één keer opnieuw', () async {
      final pad = '${root.path}${sep}cdjacht.json';
      Map<String, dynamic> vraag() => Soortvraag(
              pad: 'p', soort: Kopiesoort.cd, artiest: 'Haddaway', titel: 'Life', sindsMs: 1, vanzelf: true, nee: {77})
          .toJson()
        ..['rondes'] = 1
        ..['laatste'] = 5;
      File(pad).writeAsStringSync(jsonEncode({'versie': 1, 'binnen': 3, 'vragen': [vraag()]}));
      final oud = Soortvragen(pad, toon: false);
      await oud.laad();
      expect(oud.van('p')!.nee, isEmpty, reason: 'de zeven kopieën van 0,86–0,87 mogen weer');
      expect(oud.van('p')!.rondes, 0);
      expect(oud.binnen, 3, reason: 'de teller blijft');
      await oud.bewaar();
      final j = jsonDecode(File(pad).readAsStringSync()) as Map;
      expect(j['versie'], 2);
      File(pad).writeAsStringSync(jsonEncode({'versie': 2, 'vragen': [vraag()]}));
      final nieuw = Soortvragen(pad, toon: false);
      await nieuw.laad();
      expect(nieuw.van('p')!.nee, {77}, reason: 'daarna blijft onthouden wat weg moest');
      final eigen = Soortvragen(pad);
      File(pad).writeAsStringSync(jsonEncode({'versie': 1, 'vragen': [vraag()]}));
      await eigen.laad();
      expect(eigen.van('p')!.rondes, 1, reason: 'jouw eigen vragen raakt het niet');
    });

    test('het ritme: na 2, 4 en 7 dagen, dan om de 14 — om de 30 als TIDAL hem niet kent', () {
      expect(cdjachtWacht(1), const Duration(days: 2));
      expect(cdjachtWacht(2), const Duration(days: 4));
      expect(cdjachtWacht(3), const Duration(days: 7));
      expect(cdjachtWacht(9), const Duration(days: 14));
      expect(cdjachtWacht(9, tidalKentHemNiet: true), const Duration(days: 30));
      expect(cdjachtWacht(2, tidalKentHemNiet: true), const Duration(days: 4), reason: 'de eerste rondes gewoon');
      final v = Soortvraag(
          pad: 'p', soort: Kopiesoort.cd, artiest: 'a', titel: 't', sindsMs: 1, vanzelf: true, nee: {123}, tidalKentHemNiet: true);
      final terug = Soortvraag.fromJson(jsonDecode(jsonEncode(v.toJson())))!;
      expect(terug.vanzelf, isTrue);
      expect(terug.nee, {123});
      expect(terug.tidalKentHemNiet, isTrue);
      expect(Soortvraag.fromJson(Soortvraag(pad: 'p', soort: Kopiesoort.cd, artiest: 'a', titel: 't', sindsMs: 1).toJson())!
          .vanzelf, isFalse);
    });

    test('een gevonden cd blijft als versie, telt mee, en laat jouw eigen vraag om vinyl staan', () async {
      final studio = schrijf(album('Unorthodox Jukebox', '02 - Locked out of Heaven.flac'), hz: 96000, bits: 24).path;
      zetSoort(studio, Kopiesoort.studio);
      d.soortvragen!.zet(Soortvraag(pad: studio, soort: Kopiesoort.vinyl, artiest: 'Bruno Mars', titel: 'Locked', sindsMs: 1));
      final v = Soortvraag(
          pad: studio, soort: Kopiesoort.cd, artiest: 'Bruno Mars', titel: 'Locked', seconden: 200, sindsMs: 1, vanzelf: true);
      d.cdjacht!.zet(v);
      final binnen = schrijf('${root.path}$sep${'_keuring'}${sep}a${sep}02.flac', hz: 44100, bits: 16);
      expect(await d.zetKlaarVoorToets(v, binnen, 'Soulseek a', r'@@a\Unorthodox Jukebox (CD)\02.flac', .95), isTrue);
      expect(await d.houdCdMeteenVoorToets(v), isNotNull);
      expect(_kop(studio), (24, 96000), reason: 'je studio blijft het nummer');
      final cd = versies.versiesVan(studio).single;
      expect(cd.soort, Kopiesoort.cd);
      expect(soortVoor(cd.pad)?.gekozen, isNot(true), reason: 'niet jouw keuze: de app blijft naar betere zoeken');
      expect(d.cdjacht!.van(studio), isNull);
      expect(d.cdjacht!.binnen, 1);
      expect(d.soortvragen!.van(studio)?.soort, Kopiesoort.vinyl, reason: 'jouw vraag om vinyl liep nog');
      expect(twijfelVoor(studio), isNull, reason: 'niets te kiezen');
    });

    test('bij een nummer met alleen vinyl wordt de cd wat je hoort (Saber: "Cd wordt standaard"); de vinyl blijft', () async {
      final vinyl = schrijf(album('24K Magic', '03 - Versace on the Floor.flac'), hz: 96000, bits: 24).path;
      zetSoort(vinyl, Kopiesoort.vinyl);
      expect(d.cdWordtStandaard(vinyl), isTrue);
      final v = Soortvraag(
          pad: vinyl, soort: Kopiesoort.cd, artiest: 'Bruno Mars', titel: 'Versace', seconden: 200, sindsMs: 1, vanzelf: true);
      d.cdjacht!.zet(v);
      final binnen = schrijf('${root.path}$sep${'_keuring'}${sep}b${sep}03.flac', hz: 44100, bits: 16);
      expect(await d.zetKlaarVoorToets(v, binnen, 'Soulseek b', r'@@b\24K Magic (CD)\03.flac', .95), isTrue);
      expect(await d.houdCdMeteenVoorToets(v), isNotNull);
      final hoort = versies.speelVersie(vinyl);
      final speelt = hoort?.pad ?? vinyl;
      expect(_kop(speelt), (16, 44100), reason: 'de cd speelt');
      final alle = [vinyl, for (final x in versies.versiesVan(vinyl)) x.pad];
      expect(alle.where((p) => _kop(p) == (24, 96000)).length, 1, reason: 'de vinyl is er nog');
    });

    test('niet standaard als je zelf vinyl koos, of bij een studio', () {
      final vinyl = schrijf(album('X', '1.flac'), hz: 96000, bits: 24).path;
      zetSoort(vinyl, Kopiesoort.vinyl, gekozen: true);
      expect(d.cdWordtStandaard(vinyl), isFalse);
      final studio = schrijf(album('Y', '1.flac'), hz: 96000, bits: 24).path;
      expect(d.cdWordtStandaard(studio), isFalse);
    });

    test('aangesloten: geen melding, niets in Klaar om te kiezen bij twijfel, TIDAL begrensd, de teller ook op een toestel', () {
      final online = File('lib/online.dart').readAsStringSync();
      expect(online, contains('if (v.vanzelf && !cdAlsVersieGoed(score ?? 0, lengte: lengte, seconden: v.seconden)) {'));
      expect(online, contains('      if (v.vanzelf || cdMeteenHouden(v.soort, score ?? 0)) {'));
      expect(online, contains('if (g.soort == Kopiesoort.cd && (g.vanzelf || cdMeteenHouden(Kopiesoort.cd, g.score)) && '));
      expect(online, contains('if (!v.vanzelf) _meldKlaar(zin);'));
      expect(online, contains('if (v.rondes == 1 && !v.vanzelf) nietGevonden.add(v.titel);'));
      expect(online, contains('max: kCdjachtTidalPerUur'));
      expect(online, contains('afgewezen: {...?twijfel?.afgewezenGroottes(v.pad), ...v.nee})'));
      expect(online, contains('zetSoort(uit.path, s, gekozen: !g.vanzelf);'));
      expect(online, contains('    // En de cd-jacht, als er verder niets zoekt.\n    await cdjachtRonde();'));
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains("Soortvragen('\$appDir\${Platform.pathSeparator}cdjacht.json', toon: false)"));
      expect(main, contains('cdNodig: (anker) => !heeftSchoneCd(anker),'));
      expect(main, contains('valueListenable: context.read<DownloadManager>().cdjachtStand,'));
      expect(File('lib/lan/server.dart').readAsStringSync(), contains("'cd': manager.cdjachtStand.value.toJson()"));
      expect(File('lib/lan/remote_services.dart').readAsStringSync(),
          contains("if (res['cd'] case final Map<String, dynamic> cd) cdjachtStand.value = CdjachtStand.fromJson(cd);"));
    });
  });

  group('een andere mastering (Saber, 05-11-2026: "Bewaren vanaf 0,80, lengte ±3 s")', () {
    test('zeker dezelfde opname altijd; vanaf 0,80 alleen als hij even lang is; daaronder nooit', () {
      expect(cdAlsVersieGoed(.91), isTrue);
      expect(cdAlsVersieGoed(.83, lengte: 289, seconden: 289), isTrue, reason: 'Wicked Game: cd naast de 24/88,2');
      expect(cdAlsVersieGoed(.88, lengte: 289, seconden: 287), isTrue);
      expect(cdAlsVersieGoed(.88, lengte: 291, seconden: 287), isFalse, reason: '4 s: een andere versie');
      expect(cdAlsVersieGoed(.79, lengte: 200, seconden: 200), isFalse, reason: 'onder 0,80');
      expect(cdAlsVersieGoed(.85), isFalse, reason: 'zonder lengte alleen de zekere');
      expect(cdAlsVersieGoed(.85, lengte: 200), isFalse);
    });

    test('DE KERN: een cd in _dubbel van een andere mastering (0,875) komt terug als het nummer geen cd heeft', () async {
      const tags = {'ARTIST': 'Chris Isaak', 'ALBUM': 'Heart Shaped World', 'TITLE': 'Wicked Game', 'TRACKNUMBER': '5'};
      final anker = '${root.path}${sep}Albums${sep}Chris Isaak${sep}Heart Shaped World${sep}05 - Wicked Game.flac';
      final dubbel = '${root.path}$sep${'_dubbel'}$sep${'05 - Wicked Game.flac'}';
      schrijf(anker, hz: 88200, bits: 24, tags: tags, vulling: 40000, sec: 289);
      zetSoort(anker, Kopiesoort.studio);
      VersieTerugzetter zetter({int bits = 4, bool metCd = true, String naam = 'versies_dubbel.json'}) => VersieTerugzetter(
            wortel: root.path,
            nummerVan: (a, t, {int? seconden}) => t == 'Wicked Game' ? anker : null,
            klaar: () async {},
            bestand: '${root.path}$sep$naam',
            cdNodig: metCd ? (a) => !heeftSchoneCd(a) : null,
            vingerafdruk: _NepVingerafdruk(dubbelBits: bits),
          );
      schrijf(dubbel, hz: 44100, bits: 16, tags: tags, vulling: 20000, sec: 293);
      expect((await zetter(naam: 'a.json').ronde()).versies, 0, reason: '4 s langer: een andere versie');
      schrijf(dubbel, hz: 44100, bits: 16, tags: tags, vulling: 20000, sec: 289);
      expect((await zetter(bits: 8, naam: 'b.json').ronde()).versies, 0, reason: '0,75: geen zelfde opname');
      expect((await zetter(metCd: false, naam: 'c.json').ronde()).versies, 0,
          reason: 'zonder cd-nood blijft de strenge maat (0,90)');
      final uit = await zetter(naam: 'd.json').ronde();
      expect(uit.versies, 1);
      final cd = '${root.path}${sep}Albums${sep}Chris Isaak${sep}Heart Shaped World (cd)${sep}05 - Wicked Game.flac';
      expect(File(cd).existsSync(), isTrue);
      expect(_kop(anker), (24, 88200), reason: 'je studio blijft het nummer');
    });
  });

  group('cd\'s uit _dubbel terug', () {
    test('DE KERN: een cd die al nagekeken was, komt terug zodra zijn nummer geen cd meer heeft', () async {
      const tags = {'ARTIST': 'Chris Isaak', 'ALBUM': 'Heart Shaped World', 'TITLE': 'Wicked Game', 'TRACKNUMBER': '5'};
      final anker = '${root.path}${sep}Albums${sep}Chris Isaak${sep}Heart Shaped World${sep}05 - Wicked Game.flac';
      final dubbel = '${root.path}$sep${'_dubbel'}$sep${'05 - Wicked Game.flac'}';
      schrijf(anker, hz: 44100, bits: 16, tags: tags, vulling: 30000);
      schrijf(dubbel, hz: 44100, bits: 16, tags: tags, vulling: 20000);
      VersieTerugzetter zetter({bool metCd = true}) => VersieTerugzetter(
            wortel: root.path,
            nummerVan: (a, t, {int? seconden}) => t == 'Wicked Game' ? anker : null,
            klaar: () async {},
            bestand: '${root.path}${sep}versies_dubbel.json',
            cdNodig: metCd ? (a) => !heeftSchoneCd(a) : null,
            vingerafdruk: _NepVingerafdruk(),
          );
      expect((await zetter().ronde()).bleven, 1, reason: 'twee cd\'s: dezelfde versie');
      expect((await zetter().ronde()).bekeken, 0, reason: 'zolang je nummer een cd is: al nagekeken');
      // Later werd het nummer een studio (zonder cd ernaast): nu hoort die cd terug.
      schrijf(anker, hz: 96000, bits: 24, tags: tags, vulling: 40000);
      expect((await zetter(metCd: false).ronde()).bekeken, 0, reason: 'zonder de regel bleef hij liggen');
      final uit = await zetter().ronde();
      expect(uit.versies, 1);
      final cd = '${root.path}${sep}Albums${sep}Chris Isaak${sep}Heart Shaped World (cd)${sep}05 - Wicked Game.flac';
      expect(File(cd).existsSync(), isTrue);
      expect(versies.ankerVan(cd), anker);
      expect(heeftSchoneCd(anker), isTrue);
    });
  });

  group('een nummer in een versiemap', () {
    test('DE KERN (Adele, 05-11-2026): "30 (cd) (cd)" terug naar "30", met ALBUM 30; de cd-versie blijft in "30 (cd)"',
        () async {
      String pad(String map, String naam) => '${root.path}${sep}Albums${sep}Adele$sep$map$sep$naam';
      schrijf(pad('30', '10 - Hold On.flac'), hz: 96000, bits: 24, tags: {'ALBUM': '30', 'TITLE': 'Hold On'});
      final scheef = schrijf(pad('30 (cd) (cd)', '11 - To Be Loved.flac'), hz: 44100, bits: 24,
          tags: {'ALBUM': '30 (cd)', 'TITLE': 'To Be Loved', 'ARTIST': 'Adele'}).path;
      final cd = schrijf(pad('30 (cd)', '11 - To Be Loved.flac'), hz: 44100, bits: 16,
          tags: {'ALBUM': '30 (cd)', 'TITLE': 'To Be Loved', 'ARTIST': 'Adele'}).path;
      versies.voegToe(scheef, Versie(pad: cd, soort: Kopiesoort.cd), ankerSoort: Kopiesoort.studio);
      final regels = <String>[];
      expect(await zetScheveAnkersRecht(log: regels.add), 1);
      final goed = pad('30', '11 - To Be Loved.flac');
      expect(File(goed).existsSync(), isTrue);
      expect(File(scheef).existsSync(), isFalse);
      expect(Directory(pad('30 (cd) (cd)', '')).existsSync(), isFalse, reason: 'de lege map is weg');
      expect(readTags(File(goed))?.album, '30');
      expect(versies.versiesVan(goed).single.pad, cd, reason: 'het register verhuisde mee');
      expect(readTags(File(cd))?.album, '30 (cd)', reason: 'de cd-versie blijft een eigen album');
      expect(regels.single, contains('terug in "30"'));
      expect(await zetScheveAnkersRecht(), 0, reason: 'een tweede keer is er niets meer te doen');
    });

    test('staat er al iets op die plek, of speelt hij, dan blijft alles staan', () async {
      String pad(String map) => '${root.path}${sep}Albums${sep}Adele$sep$map${sep}11 - To Be Loved.flac';
      final scheef = schrijf(pad('30 (cd) (cd)'), hz: 44100, bits: 24).path;
      versies.voegToe(scheef, Versie(pad: pad('30 (cd)'), soort: Kopiesoort.cd), ankerSoort: Kopiesoort.studio);
      expect(await zetScheveAnkersRecht(inGebruik: (p) => true), 0);
      schrijf(pad('30'), hz: 44100, bits: 16);
      expect(await zetScheveAnkersRecht(), 0);
      expect(File(scheef).existsSync(), isTrue);
    });
  });
}

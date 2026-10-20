// De radio die een nummer al laat klinken terwijl het binnenkomt (Saber, 20-10-2026: "als ik een paar
// liedjes skip, die ik niet wil horen op het moment, dat het volgende liedje wel al kan beginnen").
//
// Met een echte groeistroom (groeistroom.dart) en een echte EigenRadiobron; alleen de Soulseek-haal is
// nagebootst: hij schrijft een bestand, meldt het aan de groei, en landt pas als de toets dat zegt.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/groeistroom.dart';
import 'package:debridmusic/library.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/radio.dart';
import 'package:debridmusic/radiovoorraad.dart';
import 'package:debridmusic/settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Alleen wat de radio van de speler gebruikt — plus het omzetten van een stroomregel.
class _Speler implements PlayerStore {
  final rij = <RadioItem>[];
  bool droog = true;

  @override
  Future<List<RadioItem>> Function()? radioExtend;
  @override
  void Function(List<RadioItem> gespeeld)? bijRadioEinde;
  @override
  void Function(RadioItem item, {required bool bestand})? bijRadioOverslaan;
  @override
  List<RadioItem> get radioQueue => rij;
  @override
  int get radioIndex => rij.length - 1;
  @override
  bool get playing => false;
  @override
  bool get radioDroog => droog;
  @override
  bool get wilVerder => false;
  @override
  Duration duration = Duration.zero;
  @override
  Duration get positieErgens => Duration.zero;
  @override
  Future<void> playRadio(List<RadioItem> items, {int start = 0}) async => rij
    ..clear()
    ..addAll(items);
  @override
  void voegToeAanRadio(List<RadioItem> meer) {
    rij.addAll(meer);
    droog = false;
  }

  @override
  RadioItem? wordtLokaalInRadio(RadioItem oud, Track t) {
    final i = rij.indexOf(oud);
    if (i < 0) return null;
    return rij[i] = RadioItem(artist: oud.artist, title: oud.title, local: t);
  }

  @override
  void addListener(void Function() listener) {}
  @override
  void removeListener(void Function() listener) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// De haal: schrijft het hele bestand meteen (dan is hij binnen één tik speelbaar), en landt pas op
/// [landen]. Met [mislukt] landt hij nooit.
class _Groeiend extends DownloadManager {
  _Groeiend(super.online, super.soulseek, super.musicRoot, super.onLibraryChanged, this.map);
  final String map;
  final landen = Completer<void>();
  bool mislukt = false;
  Groei? gekregen;
  bool? zoekBeterGevraagd;

  @override
  Future<String?> haalEnLaatHoren(
      {required String artiest,
      required String titel,
      int? seconden,
      int? jaar,
      Groei? vroeg,
      bool zoekDaarnaBeter = false}) async {
    gekregen = vroeg;
    zoekBeterGevraagd = zoekDaarnaBeter;
    final pad = '$map${Platform.pathSeparator}in.flac';
    File(pad).writeAsBytesSync(Uint8List(300 * 1024));
    vroeg?.poging(pad: pad, totaal: 300 * 1024);
    vroeg?.goedgekeurd(const Duration(seconds: 30));
    await landen.future;
    if (mislukt) {
      vroeg?.afgebroken();
      return null;
    }
    await vroeg?.binnen();
    final bib = '$map${Platform.pathSeparator}bib.flac';
    File(pad).renameSync(bib);
    vroeg?.geland(bib);
    return bib;
  }
}

class _Bibliotheek extends LibraryStore {
  @override
  Future<Track?> voegBestandToe(String pad) async => Track(path: pad, title: 'Freak Out', artist: '2 Fabiola', album: '');
}

Future<void> _totDat(bool Function() klopt) async {
  for (var i = 0; i < 400; i++) {
    if (klopt()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('wachtte te lang');
}

void main() {
  late Directory wortel;
  setUp(() {
    wortel = Directory.systemTemp.createTempSync('dm_radiostroom_');
    setAppDirForTest(wortel.path);
  });
  tearDown(() {
    try {
      wortel.deleteSync(recursive: true);
    } catch (_) {}
  });

  ({RadioBesturing radio, _Speler speler, _Groeiend haal}) maak({bool aan = true}) {
    final cfg = AppSettings()
      ..soulseekUser = 'toets'
      ..soulseekPass = 'toets';
    final haal = _Groeiend(OnlineService(cfg), SoulseekService(cfg), wortel.path, () async {}, wortel.path);
    final speler = _Speler();
    final radio = RadioBesturing(
      speler: speler,
      bron: EigenRadiobron(downloads: haal, soulseek: SoulseekService(cfg), library: _Bibliotheek(), instellingen: cfg),
    )..vroegLuisteren = () => aan;
    return (radio: radio, speler: speler, haal: haal);
  }

  test('DE KERN: staat de radio stil, dan klinkt wat onderweg is al — en landt het in DEZELFDE regel', () async {
    final m = maak();
    addTearDown(m.radio.stop);
    await m.radio.start([Radioplek(artiest: '2 Fabiola', titel: 'Freak Out')]);
    await _totDat(() => m.speler.rij.isNotEmpty);
    final stroom = m.speler.rij.single;
    expect(Groeistroom.isAdres(stroom.url ?? ''), isTrue, reason: 'het adres van de groeistroom, niet een bestand');
    expect(stroom.local, isNull);
    expect(m.radio.plan.single.stand, Haalstand.onderweg, reason: 'hij komt nog binnen');

    m.haal.landen.complete();
    await _totDat(() => m.speler.rij.single.local != null);
    expect(m.speler.rij, hasLength(1), reason: 'geen tweede regel voor hetzelfde nummer');
    expect(m.speler.rij.single.local!.path, endsWith('bib.flac'));
    expect(m.radio.plan.single.stand, Haalstand.inRij);
  });

  test('DE VAL: klonk het al en landt het niet, dan is die regel een gat dat overgeslagen wordt', () async {
    final m = maak();
    addTearDown(m.radio.stop);
    m.haal.mislukt = true;
    await m.radio.start([Radioplek(artiest: '2 Fabiola', titel: 'Freak Out')]);
    await _totDat(() => m.speler.rij.isNotEmpty);
    m.haal.landen.complete();
    await _totDat(() => m.radio.plan.single.stand == Haalstand.mislukt);
    expect(m.speler.rij.single.failed, isTrue);
    expect(await m.haal.gekregen!.speelbaarVanaf(const Duration(seconds: 10)), isFalse,
        reason: 'de speler die op een volgende uploader wacht, hoort dat er geen komt');
  });

  test('DE GRENS: speelt de radio nog (niet droog), dan wacht het gewoon tot het geland is', () async {
    final m = maak();
    addTearDown(m.radio.stop);
    m.speler.droog = false;
    await m.radio.start([Radioplek(artiest: '2 Fabiola', titel: 'Freak Out')]);
    await _totDat(() => m.haal.gekregen?.kanKlinken ?? false);
    expect(m.haal.zoekBeterGevraagd, isFalse,
        reason: 'de radio zelf zoekt niet verder naar beter — alleen ▶, en bij een 👍 (Saber, 20-10-2026)');
    m.radio.tikVoorToets();
    expect(m.speler.rij, isEmpty, reason: 'er speelt nog iets: niets onderbreken');
    m.haal.landen.complete();
    await _totDat(() => m.radio.plan.single.stand != Haalstand.onderweg);
    m.radio.tikVoorToets();
    expect(m.speler.rij.single.local, isNotNull, reason: 'gewoon geland, als je eigen nummer');
  });

  test('DE SCHAKELAAR: uit = geen groeistroom, zoals voorheen', () async {
    final m = maak(aan: false);
    addTearDown(m.radio.stop);
    await m.radio.start([Radioplek(artiest: '2 Fabiola', titel: 'Freak Out')]);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(m.haal.gekregen, isNull);
    expect(m.speler.rij, isEmpty);
    m.haal.landen.complete();
  });

  test('de speler: de stroomregel wordt het nummer zonder te heropenen, en een opgegeven stroom slaat over', () {
    final player = File('lib/player.dart').readAsStringSync();
    final omzet = player.substring(player.indexOf('  RadioItem? wordtLokaalInRadio('));
    expect(omzet.substring(0, omzet.indexOf('\n  }\n')), isNot(contains('_open')),
        reason: 'mpv speelt door uit het geheugen van de groeistroom');
    final hervat = player.substring(player.indexOf('  Future<void> _hervatGroei('));
    expect(hervat, contains("unawaited(_radioOverslaan('geen andere uploader', bestand: false));"));
  });
}

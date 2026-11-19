/// De manuele radio (19-11-2026), stap 2 na de vlotte wachtrij.
///
/// Saber: *"als ik een radio start van een nummer, album of artiest, dat hij nummers laad van men bibliotheek en dan
/// van liedjes dat ik nog niet heb, maar zonder ze te downloaden maar dat ik ze wel zie, en dan beslis ik of ik ze wil
/// of nie, dan pas mogen ze downloaden."* Zijn keuzes: een niet-gekozen voorstel wordt overgeslagen, wat je haalt
/// blijft voor altijd en klinkt op zijn plek in de radio, en ✕ is "past niet in deze radio".
library;

import 'dart:async';
import 'dart:io';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/radio.dart';
import 'package:debridmusic/radiovoorraad.dart';
import 'package:flutter_test/flutter_test.dart';

/// Alleen wat de radio van de speler gebruikt, met een plek die de toets kan verzetten.
class _Speler implements PlayerStore {
  final rij = <RadioItem>[];
  int plek = 0;

  @override
  Future<List<RadioItem>> Function()? radioExtend;

  @override
  void Function(List<RadioItem> gespeeld)? bijRadioEinde;

  @override
  void Function(RadioItem item, {required bool bestand})? bijRadioOverslaan;

  bool speelt = false;

  @override
  bool get playing => speelt;

  @override
  bool get radioDroog => false;

  @override
  bool get wilVerder => false;

  @override
  List<RadioItem> get radioQueue => rij;

  @override
  int get radioIndex => plek;

  @override
  Duration duration = Duration.zero;

  @override
  Duration get positieErgens => Duration.zero;

  @override
  Future<void> playRadio(List<RadioItem> items, {int start = 0}) async {
    rij
      ..clear()
      ..addAll(items);
  }

  @override
  void voegToeAanRadio(List<RadioItem> meer) => rij.addAll(meer);

  @override
  Future<bool> haalUitRadio(String pad) async {
    rij.removeWhere((r) => r.local?.path == pad);
    return true;
  }

  // Dezelfde rekensom als de echte speler.
  @override
  bool vervangInRadio(RadioItem oud, RadioItem? nieuw) {
    final p = vervangInRij(rij, plek, oud, nieuw);
    if (p == null) return false;
    plek = p;
    return true;
  }

  @override
  void addListener(void Function() listener) {}
  @override
  void removeListener(void Function() listener) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bron implements Radiobron {
  _Bron(this.antwoord);
  final Future<Track?> Function(Radioplek p) antwoord;
  final gehaald = <String>[];

  @override
  Future<String?> begin() async => null;

  @override
  void einde() {}

  @override
  void staak() {}

  @override
  Future<Track?> haal(Radioplek p) {
    gehaald.add(p.titel);
    return antwoord(p);
  }

  @override
  Future<bool> vergeet({required String pad, required String artiest, required String titel}) async => true;
}

Track _t(String titel, {String? artiest}) => Track(
    path: '${Directory.systemTemp.path}${Platform.pathSeparator}$titel.flac',
    title: titel,
    artist: artiest ?? titel,
    album: '');

Future<void> _totAllesTerug(RadioBesturing r) async {
  for (var i = 0; i < 200; i++) {
    if (!r.plan.any((p) => p.stand == Haalstand.onderweg)) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  late Directory wortel;
  setUp(() {
    wortel = Directory.systemTemp.createTempSync('dm_manueel_');
    setAppDirForTest(wortel.path);
  });
  tearDown(() {
    try {
      wortel.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('het plan', () {
    test('DE KERN: een voorstel komt meteen in de rij, telt niet mee en wordt nooit gestart', () {
      final b = voorraadPlan([Haalstand.klaar, Haalstand.voorstel, Haalstand.wacht], vooruitNu: 0);
      expect(b.inRij, containsAll([0, 1]));
      expect(b.vooruit, 1, reason: 'alleen het eigen nummer klinkt');
      expect(b.starten, [2]);
      expect(voorraadPlan([Haalstand.voorstel], vooruitNu: 0).starten, isEmpty);
    });

    test('DE KERN: een voorstel vult de rij niet — de eigen muziek vult tot zes speelbare', () {
      final b = voorraadPlan([for (var i = 0; i < 4; i++) Haalstand.voorstel, for (var i = 0; i < 8; i++) Haalstand.klaar],
          vooruitNu: 0, artiesten: [for (var i = 0; i < 12; i++) 'Artiest $i']);
      expect(b.inRij.where((i) => i < 4).length, 4);
      expect(b.inRij.where((i) => i >= 4).length, kMinVooruit);
    });

    test('DE GRENS: evenveel voorstellen als speelbare nummers, en minstens vier', () {
      List<Haalstand> wacht(int n) => [for (var i = 0; i < n; i++) Haalstand.wacht];
      int mag(List<Haalstand> s) => s.where((x) => x == Haalstand.wacht).length;
      expect(mag(manueelBegrensd(wacht(10), gekozen: const [], voorstellenVooruit: 0, speelbaar: 0)),
          kManueelVoorstellen);
      expect(mag(manueelBegrensd(wacht(10), gekozen: const [], voorstellenVooruit: 0, speelbaar: 6)), 6);
      expect(mag(manueelBegrensd(wacht(10), gekozen: const [], voorstellenVooruit: 3, speelbaar: 0)), 1,
          reason: 'wat al in de rij op je keuze wacht telt mee');
      expect(
          mag(manueelBegrensd([Haalstand.onderweg, Haalstand.voorstel, ...wacht(8)],
              gekozen: const [], voorstellenVooruit: 0, speelbaar: 0)),
          2,
          reason: 'ook wat nu gekeurd wordt of net klaar is');
    });

    test('DE GRENS: wat je koos wordt altijd gehaald en telt niet mee', () {
      final s = manueelBegrensd([Haalstand.onderweg, for (var i = 0; i < 9; i++) Haalstand.wacht],
          gekozen: [true, ...List.filled(8, false), true], voorstellenVooruit: 4, speelbaar: 0);
      expect(s.first, Haalstand.onderweg);
      expect(s.last, Haalstand.wacht, reason: 'gekozen: nooit weggedrukt');
      expect(s.where((x) => x == Haalstand.wacht).length, 1, reason: 'de vier voorstellen in de rij vullen de grens');
    });

    test('afstemmen laat wat je koos staan, en een voorstel buiten de rij niet', () {
      final gekozen = Radioplek(artiest: 'A', titel: 'a')..gekozen = true;
      final voorstel = Radioplek(artiest: 'B', titel: 'b')..stand = Haalstand.voorstel;
      final nieuw = stemPlanAf([gekozen, voorstel], [Radioplek(artiest: 'C', titel: 'c')]);
      expect(nieuw, contains(gekozen));
      expect(nieuw, isNot(contains(voorstel)));
    });
  });

  group('de radio', () {
    test('DE KERN: niets wordt vanzelf gehaald; ⬇ haalt, op de plek van het voorstel, en het blijft', () async {
      final zaad = _t('Zaadnummer', artiest: 'Zaad'), b = _t('B', artiest: 'Artiest B');
      final speler = _Speler();
      final bron = _Bron((p) async => p.titel == 'B' ? b : null);
      final radio = RadioBesturing(speler: speler, bron: bron);
      addTearDown(radio.stop);
      await radio.start([
        Radioplek(artiest: 'Zaad', titel: 'Zaadnummer', eigen: zaad, zaad: true),
        Radioplek(artiest: 'Artiest B', titel: 'B'),
        Radioplek(artiest: 'Artiest C', titel: 'C'),
      ], manueel: true);
      await _totAllesTerug(radio);

      expect(bron.gehaald, isEmpty, reason: '"zonder ze te downloaden"');
      expect([for (final it in speler.rij) (it.title, it.voorstel)], [('Zaadnummer', false), ('B', true), ('C', true)]);
      expect(radio.onderweg, 0, reason: 'keuren is geen halen');

      final itB = speler.rij[1];
      expect(radio.voorstelStand(itB), Voorstelstand.kies);
      expect(radio.haalVoorstel(itB), isTrue);
      expect(radio.voorstelStand(itB), Voorstelstand.bezig);
      expect(radio.haalVoorstel(itB), isFalse, reason: 'twee keer tikken haalt hem één keer');
      await _totAllesTerug(radio);

      expect(bron.gehaald, ['B']);
      expect(speler.rij[1].local?.path, b.path, reason: 'op zijn plek in de radio');
      expect(speler.rij.length, 3);
      expect(radio.plan[1].doorRadio, isFalse, reason: 'blijft voor altijd');
      expect(radio.gehaald, 0);

      final itC = speler.rij[2];
      expect(radio.wegVoorstel(itC), isTrue);
      expect([for (final it in speler.rij) it.title], ['Zaadnummer', 'B']);
      expect(radio.plan[2].stand, Haalstand.mislukt);
      expect(radio.plan[2].weer, Weerreden.sfeer, reason: 'past niet in deze radio');
      expect(bron.gehaald, ['B']);

      radio.stop();
      expect([for (final g in radio.openstaand?.gehaald ?? const []) g.pad], isNot(contains(b.path)),
          reason: 'wat je koos, komt niet in het opruimoverzicht');
    });

    test('DE KERN: een voorstel gaat eerst door de keuring — één keer', () async {
      final speler = _Speler();
      final bron = _Bron((p) async => null);
      final radio = RadioBesturing(speler: speler, bron: bron);
      addTearDown(radio.stop);
      final gekeurd = <String>[];
      await radio.start([
        Radioplek(artiest: 'Zaad', titel: 'Z', eigen: _t('Z'), zaad: true),
        Radioplek(artiest: 'Goed', titel: 'Goed'),
        Radioplek(artiest: 'Fout', titel: 'Fout'),
      ], keur: (p) async {
        gekeurd.add(p.titel);
        return p.titel != 'Fout';
      }, manueel: true);
      await _totAllesTerug(radio);
      expect([for (final it in speler.rij) if (it.voorstel) it.title], ['Goed']);
      expect(bron.gehaald, isEmpty);

      radio.haalVoorstel(speler.rij.firstWhere((it) => it.voorstel));
      await _totAllesTerug(radio);
      expect(bron.gehaald, ['Goed']);
      expect(gekeurd.where((t) => t == 'Goed').length, 1, reason: 'wat je koos is al gekeurd');
    });

    test('keuren is geen halen: de kop telt het niet als onderweg', () async {
      final oordeel = Completer<bool>();
      final radio = RadioBesturing(speler: _Speler(), bron: _Bron((p) async => null));
      addTearDown(radio.stop);
      await radio.start([
        Radioplek(artiest: 'Zaad', titel: 'Z', eigen: _t('Z'), zaad: true),
        Radioplek(artiest: 'Nieuw', titel: 'N'),
      ], keur: (p) => oordeel.future, manueel: true);
      expect(radio.plan[1].stand, Haalstand.onderweg);
      expect(radio.onderweg, 0);
      oordeel.complete(true);
      await _totAllesTerug(radio);
      expect(radio.plan[1].stand, Haalstand.inRij);
    });

    test('DE KERN: wat niemand koos telt niet als wat er komt — de radio vult op tijd bij', () async {
      final speler = _Speler()..speelt = true;
      var rondes = 0;
      final radio = RadioBesturing(speler: speler, bron: _Bron((p) async => null));
      addTearDown(radio.stop);
      await radio.start([
        Radioplek(artiest: 'Zaad', titel: 'Z', eigen: _t('Z'), zaad: true),
        for (var i = 0; i < 400; i++) Radioplek(artiest: 'Nieuw $i', titel: 'N$i'),
      ], bijvul: (s, r, v) async {
        rondes++;
        return 0;
      }, manueel: true);
      await _totAllesTerug(radio);
      radio.tikVoorToets();
      expect(rondes, greaterThan(0),
          reason: 'vierhonderd voorstellen zijn geen vierhonderd nummers: er klinkt niets na het zaad');
    });

    test('een voorstel houdt eigen muziek van dezelfde artiest niet tegen — het klinkt niet', () async {
      final speler = _Speler();
      final radio = RadioBesturing(speler: speler, bron: _Bron((p) async => null));
      addTearDown(radio.stop);
      final oa = _t('OA', artiest: 'A');
      await radio.start([
        Radioplek(artiest: 'Zaad', titel: 'Z', eigen: _t('Z', artiest: 'Zaad'), zaad: true),
        for (var i = 1; i <= 6; i++) Radioplek(artiest: 'B$i', titel: 'B$i', eigen: _t('B$i')),
        Radioplek(artiest: 'A', titel: 'NA'),
        Radioplek(artiest: 'A', titel: 'OA', eigen: oa),
      ], manueel: true);
      await _totAllesTerug(radio);
      expect([for (final it in speler.rij) it.title], ['Z', 'B1', 'B2', 'B3', 'B4', 'B5', 'NA', 'B6']);
      speler.plek = 1;
      radio.tikVoorToets();
      expect([for (final it in speler.rij) it.local?.path], contains(oa.path));
    });

    test('het zaad dat je niet hebt wordt wel gehaald — je koos het — en het blijft', () async {
      final z = _t('Z', artiest: 'Zaad');
      final speler = _Speler();
      final bron = _Bron((p) async => p.titel == 'Z' ? z : null);
      final radio = RadioBesturing(speler: speler, bron: bron);
      addTearDown(radio.stop);
      await radio.start([
        Radioplek(artiest: 'Zaad', titel: 'Z', zaad: true),
        Radioplek(artiest: 'X', titel: 'X'),
      ], manueel: true);
      await _totAllesTerug(radio);
      radio.tikVoorToets();
      expect(bron.gehaald, ['Z']);
      expect(radio.plan.first.doorRadio, isFalse);
      expect([for (final it in speler.rij) it.local?.path], contains(z.path));
      expect([for (final it in speler.rij) if (it.voorstel) it.title], ['X']);
    });

    test('DE KERN: de eigen muziek vult bij op wat werkelijk klinkt, niet op de voorstellen', () async {
      final speler = _Speler();
      final radio = RadioBesturing(speler: speler, bron: _Bron((p) async => null));
      addTearDown(radio.stop);
      await radio.start([
        for (var i = 0; i < 14; i++) Radioplek(artiest: 'Eigen $i', titel: 'E$i', eigen: _t('E$i', artiest: 'Eigen $i')),
        for (var i = 0; i < 4; i++) Radioplek(artiest: 'Nieuw $i', titel: 'N$i'),
      ], manueel: true);
      await _totAllesTerug(radio);
      speler.plek = 3; // drie nummers verder
      radio.tikVoorToets();
      final vooruit = speler.rij.skip(speler.plek + 1);
      expect(vooruit.where((it) => !it.voorstel).length, kMinVooruit);
      expect(vooruit.where((it) => it.voorstel).length, 4);
    });

    test('een gekozen nummer dat niet te vinden is: de regel zegt het, en ✕ haalt hem weg zonder oordeel', () async {
      final speler = _Speler();
      final radio = RadioBesturing(speler: speler, bron: _Bron((p) async => null));
      addTearDown(radio.stop);
      await radio.start([
        Radioplek(artiest: 'Zaad', titel: 'Z', eigen: _t('Z'), zaad: true),
        Radioplek(artiest: 'Weg', titel: 'Weg'),
      ], manueel: true);
      await _totAllesTerug(radio);
      final it = speler.rij.firstWhere((x) => x.voorstel);
      radio.haalVoorstel(it);
      await _totAllesTerug(radio);
      expect(radio.voorstelStand(it), Voorstelstand.mislukt);
      expect(radio.wegVoorstel(it), isTrue);
      expect(radio.plan[1].weer, Weerreden.nietGevonden, reason: 'niet gevonden is geen "past niet"');
      expect(speler.rij.where((x) => x.voorstel), isEmpty);
    });
  });

  group('de rij', () {
    RadioItem i(String t, {bool v = false}) => RadioItem(artist: t, title: t, voorstel: v);

    test('DE KERN: vóór je ter plaatse, al voorbij meteen na wat speelt', () {
      final a = i('A'), v = i('V', v: true), b = i('B'), c = i('C'), n = i('N');
      final vooruit = [a, v, b];
      expect(vervangInRij(vooruit, 0, v, n), 0);
      expect(vooruit, [a, n, b]);

      final voorbij = [a, v, b, c];
      expect(vervangInRij(voorbij, 2, v, n), 1, reason: 'B speelt nog, nu op plek 1');
      expect(voorbij, [a, b, n, c]);

      final droog = [a, v];
      expect(vervangInRij(droog, 1, v, n), 1);
      expect(droog, [a, n]);
    });

    test('weghalen laat de radio op hetzelfde nummer', () {
      final a = i('A'), v = i('V', v: true), b = i('B'), c = i('C');
      final rij = [a, v, b, c];
      expect(vervangInRij(rij, 2, v, null), 1, reason: 'B speelt nog, nu op plek 1');
      expect(rij, [a, b, c]);
      final eind = [a, v];
      expect(vervangInRij(eind, 1, v, null), 0);
      expect(vervangInRij([a], 0, v, null), isNull);
    });

    test('een voorstel staat niet als mislukt in het paneel, en heeft een vaste sleutel', () {
      final v = i('V', v: true);
      expect(v.failed, isTrue, reason: 'de speler stapt eroverheen');
      final r = radioAlsRij([v, i('S')..failed = true]);
      expect(r.first.mislukt, isFalse);
      expect(r.first.voorstel, Voorstelstand.kies);
      expect(r.first.nummer.path, startsWith('voorstel:'));
      expect(r.last.mislukt, isTrue);
      expect(r.last.voorstel, isNull);
      expect(radioAlsRij([v], voorstel: (_) => Voorstelstand.bezig).first.voorstel, Voorstelstand.bezig);
    });

    test('de kop telt de voorstellen apart', () {
      expect(radioKop(hierna: 6, onderweg: 1, loopt: true, voorstellen: 4), '6 hierna · 1 onderweg · 4 voorstellen');
      expect(radioKop(hierna: 6, onderweg: 0, loopt: true, voorstellen: 1), '6 hierna · 1 voorstel');
      expect(radioKop(hierna: 6, onderweg: 0, loopt: true), '6 hierna');
    });
  });

  group('aangesloten', () {
    test('"Manuele radio" naast elke radio in de menu\'s, en altijd op dit toestel', () {
      final m = _bron('lib/main.dart');
      expect("MenuRegel(Icons.radio_outlined, 'Manuele radio',".allMatches(m).length, 8);
      expect(m, contains('final afstand = hier || manueel ? null : _misschien<GekozenZone>(context)?.opAfstand;'));
      expect(m, contains('      manueel: manueel,\n      bijStart: (s) {'));
    });

    test('het paneel toont de stand en telt wat klinkt', () {
      final m = _bron('lib/main.dart');
      expect(m, contains('radioAlsRij(lokaal.radioQueue, voorstel: context.read<RadioBesturing>().voorstelStand)'));
      expect(m, contains('hierna: hierna - nietSpeelbaar,'));
      expect(m, contains('                _VoorstelKnoppen(item: it, stand: v)'));
      expect(m, contains('        if (!r[k].voorstel) r[k].local == null ? null : bib.coverForTrack(r[k].local!),'),
          reason: 'de hoezenstapel van Nu speelt toont wat klinkt');
    });

    test('de speler gebruikt dezelfde rekensom', () {
      final p = _bron('lib/player.dart');
      expect(p, contains('    final plek = vervangInRij(_radio, _radioIndex, oud, nieuw);'));
      expect(p, contains('      : failed = voorstel;'));
    });
  });
}

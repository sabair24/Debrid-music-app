/// De radio houdt niet meer op — de besturing (plan van 08-10-2026, delen A1 en A3).
///
/// Met een nagespeelde speler en bron, zoals `radiolanding_test`: wat voorbij kwam wordt geteld, een
/// droge radio vult binnen één tik iets bij, een ronde die niet afkomt voegt later niets meer toe, en
/// de reserve speelt alleen mee als het krap wordt.
library;

import 'dart:async';
import 'dart:io';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/radio.dart';
import 'package:debridmusic/radioladder.dart';
import 'package:debridmusic/radiovoorraad.dart';
import 'package:flutter_test/flutter_test.dart';

/// Alleen wat de radio van de speler gebruikt — en zoals de echte speler: een landing in een droge
/// rij speelt meteen.
class _Speler implements PlayerStore {
  final rij = <RadioItem>[];
  int index = 0;
  bool speelt = true;
  bool droog = false;
  bool verder = false;

  @override
  Future<List<RadioItem>> Function()? radioExtend;

  @override
  void Function(List<RadioItem> gespeeld)? bijRadioEinde;

  @override
  void Function(RadioItem item, {required bool bestand})? bijRadioOverslaan;

  @override
  List<RadioItem> get radioQueue => rij;

  @override
  int get radioIndex => index;

  @override
  bool get playing => speelt;

  @override
  bool get radioDroog => droog;

  @override
  bool get wilVerder => verder;

  @override
  Duration duration = Duration.zero;

  @override
  Duration get positieErgens => Duration.zero;

  @override
  Future<void> playRadio(List<RadioItem> items, {int start = 0}) async {
    rij
      ..clear()
      ..addAll(items);
    index = 0;
  }

  @override
  void voegToeAanRadio(List<RadioItem> meer) {
    final was = rij.length;
    rij.addAll(meer);
    if ((droog || verder) && meer.isNotEmpty) {
      droog = false;
      verder = false;
      index = was;
    }
  }

  @override
  Future<bool> haalUitRadio(String pad) async {
    rij.removeWhere((r) => r.local?.path == pad);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bron implements Radiobron {
  _Bron([Future<Track?> Function(Radioplek p)? antwoord]) : antwoord = antwoord ?? ((_) => Completer<Track?>().future);
  final Future<Track?> Function(Radioplek p) antwoord;

  @override
  Future<String?> begin() async => null;

  @override
  void einde() {}

  @override
  void staak() {}

  @override
  Future<Track?> haal(Radioplek p) => antwoord(p);

  @override
  Future<bool> vergeet({required String pad, required String artiest, required String titel}) async => true;
}

Track _t(String artiest, String titel) => Track(
    path: '${Directory.systemTemp.path}${Platform.pathSeparator}$artiest - $titel.flac',
    title: titel,
    artist: artiest,
    album: '');

Radioplek _eigen(String artiest, String titel) => Radioplek(artiest: artiest, titel: titel, eigen: _t(artiest, titel));

Future<void> _totAllesTerug(RadioBesturing r) async {
  for (var i = 0; i < 200; i++) {
    if (!r.plan.any((p) => p.stand == Haalstand.onderweg)) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late Directory wortel;
  var nu = DateTime(2026, 10, 8, 18);
  setUp(() {
    wortel = Directory.systemTemp.createTempSync('dm_nooitstil_');
    setAppDirForTest(wortel.path);
    nu = DateTime(2026, 10, 8, 18);
  });
  tearDown(() {
    try {
      wortel.deleteSync(recursive: true);
    } catch (_) {}
  });

  RadioBesturing maak(_Speler s, {Radiobron? bron}) => RadioBesturing(speler: s, bron: bron ?? _Bron(), klok: () => nu);

  group('wat voorbij kwam', () {
    test('DE KERN: elk nummer vóór het spelende krijgt een stempel, ook wat je oversloeg', () async {
      final s = _Speler();
      final r = maak(s);
      await r.start([for (final t in 'abcde'.split('')) _eigen('Artiest $t', t)]);
      expect(s.rij, hasLength(5));
      s.index = 1;
      r.tikVoorToets();
      expect(r.plan[0].voorbijOp, 1);
      expect(r.voorbijteller, 1);
      r.stop();
    });

    test('een sprong is één stap, en terug haalt de stempel van het spelende weg', () async {
      final s = _Speler();
      final r = maak(s);
      await r.start([for (final t in 'abcde'.split('')) _eigen('Artiest $t', t)]);
      s.index = 1;
      r.tikVoorToets();
      s.index = 4; // van regel 2 naar regel 5 getikt
      r.tikVoorToets();
      expect([for (final p in r.plan.take(4)) p.voorbijOp], [1, 2, 2, 2]);
      expect(r.voorbijteller, 2);
      s.index = 2; // "vorige", twee keer
      r.tikVoorToets();
      expect(r.plan[2].voorbijOp, isNull, reason: 'wat weer speelt is niet voorbij');
      r.stop();
    });

    test('beluisterd staat in het logboek, met wat het was', () async {
      final s = _Speler();
      final r = maak(s);
      final log = <String>[];
      await r.start([_eigen('Bazart', 'Goud')], spoor: log.add);
      r.gehoord(r.plan.first.eigen!);
      expect(log, contains('radio-gehoord #1: "Bazart — Goud" (eigen)'));
      r.stop();
    });
  });

  group('een droge radio', () {
    test('DE KERN: droog en niets klaar — binnen één tik speelt er iets', () async {
      final s = _Speler();
      final r = maak(s);
      final log = <String>[];
      final zaad = _t('Niels Destadsbader', 'Pa');
      r.eigenVanZaad = () => [zaad];
      await r.start([_eigen('A', 'a'), _eigen('B', 'b'), _eigen('C', 'c')], spoor: log.add, zaadArtiest: 'Niels Destadsbader');
      s
        ..index = 2
        ..speelt = false
        ..droog = true;
      r.tikVoorToets();
      expect(s.droog, isFalse, reason: 'het vangnet landde in de droge rij en speelt');
      expect(s.rij.last.local?.path, zaad.path);
      // Nog nooit gespeeld in deze radio: een eigen nummer, geen "opnieuw".
      expect(s.rij.last.herhaling, isFalse);
      expect(log.where((l) => l.startsWith('radio-nood:')), hasLength(1));
      expect(log.any((l) => l.startsWith('radio-vangnet: "Niels Destadsbader — Pa"')), isTrue);
      r.stop();
    });

    test('een herhaling die je oversloeg komt niet nog eens', () async {
      final s = _Speler();
      final r = maak(s);
      await r.start([_eigen('A', 'a'), _eigen('B', 'b')]);
      r.gehoord(r.plan[0].eigen!);
      r.gehoord(r.plan[1].eigen!);
      s.index = 1;
      r.tikVoorToets();
      for (var i = 0; i < 30; i++) {
        r.voegBij(r.sessie, [_eigen('Vul $i', 'v')]);
        r.tikVoorToets();
        s.index = s.rij.length - 1;
      }
      final voor = r.plan.length;
      r.voegHerhalingBij(r.sessie, 1);
      final eerst = r.plan.sublist(voor).single;
      expect(eerst.artiest, 'A');
      // A komt in de rij, en je slaat hem over (niet gehoord).
      r.tikVoorToets();
      s.index = s.rij.length - 1;
      for (var i = 0; i < 30; i++) {
        r.voegBij(r.sessie, [_eigen('Meer $i', 'm')]);
        r.tikVoorToets();
        s.index = s.rij.length - 1;
      }
      final daarna = r.plan.length;
      r.voegHerhalingBij(r.sessie, 2);
      expect(r.plan.sublist(daarna).map((p) => p.artiest), isNot(contains('A')));
      r.stop();
    });

    test('de vraag aan de bijvuller telt de reserve mee die net de rij in ging', () async {
      final s = _Speler();
      final r = maak(s);
      final vragen = <Bijvulvraag>[];
      await r.start([_eigen('A', 'a'), for (var i = 0; i < 8; i++) Radioplek(artiest: 'B$i', titel: 'b$i')],
          bijvul: (_, __, v) async {
        vragen.add(v);
        return 0;
      });
      for (final t in 'wx'.split('')) {
        r.voegReserveBij(r.sessie, [Radioplek(artiest: 'Eigen $t', titel: t, eigen: _t('Eigen $t', t), reserve: true)]);
      }
      s
        ..speelt = false
        ..droog = true;
      r.tikVoorToets();
      expect(vragen, hasLength(1));
      expect(vragen.single.nood, isFalse, reason: 'acht onderweg, net droog: nog geen nood');
      // Acht onderweg × 0,25 = 2, plus de twee reservenummers die nu in de rij staan.
      expect(vragen.single.verwacht, closeTo(4, 1e-9));
      r.stop();
    });

    test('de zaadartiest ook bij het herhalen hoogstens één op de tien', () async {
      final s = _Speler();
      final r = maak(s);
      await r.start([_eigen('Niels Destadsbader', 'n1'), _eigen('X', 'x1')], zaadArtiest: 'Niels Destadsbader');
      r.gehoord(r.plan[0].eigen!);
      r.gehoord(r.plan[1].eigen!);
      s.index = 1;
      r.tikVoorToets(); // n1 voorbij
      for (var i = 0; i < 30; i++) {
        r.voegBij(r.sessie, [_eigen('Vul $i', 'v')]);
        r.tikVoorToets();
        s.index = s.rij.length - 1;
      }
      // Nu klinkt Niels opnieuw (een nieuw nummer van hem): n1 is wel het langst geleden, maar te dichtbij.
      r.voegBij(r.sessie, [_eigen('Niels Destadsbader', 'n2')]);
      r.tikVoorToets();
      s.index = s.rij.length - 1;
      // Vier anderen erna: Niels staat dan binnen de laatste tien, maar niet meer in de laatste drie
      // (die houdt de gewone "net geklonken"-regel al tegen).
      for (var i = 0; i < 4; i++) {
        r.voegBij(r.sessie, [_eigen('Na $i', 'n')]);
        r.tikVoorToets();
        s.index = s.rij.length - 1;
      }
      r.tikVoorToets();
      expect(s.rij[s.rij.length - 5].artist, 'Niels Destadsbader');
      final voor = r.plan.length;
      r.voegHerhalingBij(r.sessie, 1);
      expect(r.plan.sublist(voor).single.artiest, 'X');
      r.stop();
    });

    test('wat je hoorde komt terug als "opnieuw" — wat je oversloeg niet', () async {
      final s = _Speler();
      final r = maak(s);
      final log = <String>[];
      await r.start([for (final t in 'abcdef'.split('')) _eigen('Artiest $t', t)], spoor: log.add);
      // a en b gehoord, c tot en met e overgeslagen, f speelt.
      r.gehoord(r.plan[0].eigen!);
      r.gehoord(r.plan[1].eigen!);
      s.index = 5;
      r.tikVoorToets();
      // Daarna laat de teller oplopen: dertig keer iets anders voorbij.
      for (var i = 0; i < 30; i++) {
        r.voegBij(r.sessie, [_eigen('Vul $i', 'v')]);
        r.tikVoorToets();
        s.index = s.rij.length - 1;
      }
      r.tikVoorToets();
      final voor = r.plan.length;
      r.voegHerhalingBij(r.sessie, 3);
      final nieuw = r.plan.sublist(voor);
      expect({for (final p in nieuw) p.artiest}, {'Artiest a', 'Artiest b'});
      expect(nieuw.every((p) => p.herhaling), isTrue);
      expect(log.where((l) => l.startsWith('radio-herhaling: ')), hasLength(2));
      r.gehoord(nieuw.first.eigen!);
      expect(log.last, contains('(herhaling)'));
      r.stop();
    });

    test('DE VAL: bij nood speelt de reserve — hoogstens twee, en geen herhalingen erbovenop', () async {
      final s = _Speler();
      final r = maak(s);
      final log = <String>[];
      r.eigenVanZaad = () => [_t('Niels Destadsbader', 'Pa')];
      await r.start([_eigen('A', 'a')], spoor: log.add);
      // Precies twee: allebei de rij in, en dan staat er geen reserve meer klaar. Het besluit "herhalen
      // of niet" moet dus kijken naar wat er vóór de vulling klaarstond.
      for (final t in 'wx'.split('')) {
        r.voegReserveBij(r.sessie, [Radioplek(artiest: 'Eigen $t', titel: t, eigen: _t('Eigen $t', t), reserve: true)]);
      }
      s
        ..speelt = false
        ..droog = true;
      final voor = s.rij.length;
      r.tikVoorToets();
      final erbij = s.rij.sublist(voor);
      expect(erbij, hasLength(2));
      expect(erbij.every((it) => it.artist.startsWith('Eigen ')), isTrue);
      expect(log.where((l) => l.startsWith('radio-herhaling') || l.startsWith('radio-vangnet')), isEmpty);
      r.stop();
    });

    test('droog met haaltjes onderweg: na acht seconden toch nood', () async {
      final s = _Speler();
      final r = maak(s);
      final log = <String>[];
      r.eigenVanZaad = () => [_t('Niels Destadsbader', 'Pa')];
      // Acht te halen plekken die nooit landen (de bron antwoordt niet): onderweg 8 × 0,25 = 2.
      await r.start([_eigen('A', 'a'), for (var i = 0; i < 8; i++) Radioplek(artiest: 'B$i', titel: 'b$i')],
          spoor: log.add);
      s
        ..speelt = false
        ..droog = true;
      r.tikVoorToets();
      expect(log.where((l) => l.startsWith('radio-nood')), isEmpty, reason: 'nog geen acht seconden');
      // Net niet de volle vijf seconden (zo gaat het in het echt: de droogte wordt aan het eind van een
      // tik vastgelegd): dat telt als vijf.
      nu = nu.add(const Duration(milliseconds: kDroogTotNood * 1000 - 10));
      r.tikVoorToets();
      expect(log.where((l) => l.startsWith('radio-nood')), hasLength(1));
      expect(s.droog, isFalse);
      r.stop();
    });

    test('nood is flankgestuurd: twee tikken, één noodvulling — en na dertig seconden weer', () async {
      final s = _Speler();
      final r = maak(s);
      final log = <String>[];
      await r.start([_eigen('A', 'a')], spoor: log.add);
      s
        ..speelt = false
        ..droog = true;
      r.tikVoorToets();
      r.tikVoorToets();
      expect(log.where((l) => l.startsWith('radio-nood:')), hasLength(1));
      nu = nu.add(const Duration(seconds: 31));
      r.tikVoorToets();
      expect(log.where((l) => l.startsWith('radio-nood:')), hasLength(2));
      r.stop();
    });

    test('de droogte en het hervatten staan in het logboek', () async {
      final s = _Speler();
      final r = maak(s);
      final log = <String>[];
      await r.start([_eigen('A', 'a')], spoor: log.add);
      s
        ..speelt = false
        ..droog = true;
      r.tikVoorToets();
      expect(log.any((l) => l.startsWith('radio droog: rij leeg')), isTrue);
      s.droog = false;
      nu = nu.add(const Duration(seconds: 41));
      r.tikVoorToets();
      expect(log, contains('radio hervat na 41 s'));
      r.stop();
    });

    test('DE GRENS: gepauzeerd midden in een nummer — niets', () async {
      final s = _Speler()..speelt = false;
      final r = maak(s);
      final log = <String>[];
      var rondes = 0;
      await r.start([_eigen('A', 'a')], spoor: log.add, bijvul: (_, __, ___) async {
        rondes++;
        return 0;
      });
      r.tikVoorToets();
      expect(rondes, 0);
      expect(log.where((l) => l.startsWith('radio-nood')), isEmpty);
      r.stop();
    });
  });

  group('de rondes', () {
    test('DE KERN: een ronde die niet afkomt telt niet meer, en wat hij later brengt valt weg', () async {
      final s = _Speler()
        ..speelt = false
        ..droog = true;
      final r = maak(s)..bijvulGeduld = const Duration(milliseconds: 30);
      final klaar = Completer<int>();
      int? zijnRonde;
      int? zijnSessie;
      await r.start([_eigen('A', 'a')], bijvul: (sessie, ronde, _) {
        zijnSessie = sessie;
        zijnRonde = ronde;
        return klaar.future;
      });
      r.tikVoorToets();
      expect(zijnRonde, 1);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(r.bijvulRonde, isNot(zijnRonde), reason: 'de time-out schoof de ronde door');
      expect(r.voegBij(zijnSessie!, [Radioplek(artiest: 'Laat', titel: 'te laat')], ronde: zijnRonde), 0);
      expect(r.plan.any((p) => p.artiest == 'Laat'), isFalse);
      // Een ronde die wél geldt, komt erin.
      expect(r.voegBij(zijnSessie!, [Radioplek(artiest: 'Op tijd', titel: 'x')], ronde: r.bijvulRonde), 1);
      klaar.complete(0);
      r.stop();
    });

    test('de vraag zegt of er nood is en of de reserve mag — na een minuut zonder landing', () async {
      final s = _Speler();
      final r = maak(s, bron: _Bron());
      final vragen = <Bijvulvraag>[];
      await r.start([_eigen('A', 'a'), Radioplek(artiest: 'B', titel: 'b')], bijvul: (_, __, v) async {
        vragen.add(v);
        return 0;
      });
      r.tikVoorToets();
      expect(vragen, hasLength(1));
      expect(vragen.last.nood, isFalse);
      expect(vragen.last.reserveNodig, 0, reason: 'nog geen landing en nog geen minuut');
      await pumpEventQueue(); // de ronde komt af
      nu = nu.add(kBijvulAdem + const Duration(seconds: 1));
      r.tikVoorToets();
      expect(vragen, hasLength(2));
      expect(vragen.last.reserveNodig, kReserve);
      r.stop();
    });

    test('DE KERN: een radio uit een zin stopt bij zijn aantal — ook als er iets te herhalen valt', () async {
      final s = _Speler();
      final r = maak(s);
      final log = <String>[];
      var rondes = 0;
      r.eigenVanZaad = () => [_t('2 Unlimited', 'No Limit')];
      await r.start([_eigen('A', 'a'), _eigen('B', 'b'), _eigen('C', 'c')], aantal: 3, spoor: log.add,
          bijvul: (_, __, ___) async {
        rondes++;
        return 0;
      });
      for (final p in r.plan) {
        r.gehoord(p.eigen!);
      }
      r.voegReserveBij(r.sessie, [Radioplek(artiest: 'Eigen', titel: 'r', eigen: _t('Eigen', 'r'), reserve: true)]);
      s
        ..index = 2
        ..speelt = false
        ..droog = true;
      nu = nu.add(const Duration(minutes: 5));
      r.tikVoorToets();
      nu = nu.add(const Duration(seconds: 31));
      r.tikVoorToets();
      expect(r.aantalBereikt, isTrue);
      expect(r.aantalOp, isTrue);
      expect(rondes, 0);
      expect(s.droog, isTrue, reason: 'geen herhaling, geen reserve: hij stopt, met Ga door');
      expect(log.where((l) => l.startsWith('radio-nood') || l.startsWith('radio-herhaling') || l.startsWith('radio-vangnet')),
          isEmpty);
      r.gaDoor();
      expect(r.aantalBereikt, isFalse);
      expect(rondes, 1);
      r.stop();
    });

    test('het aantal telt geen herhalingen en geen reserve', () async {
      final s = _Speler();
      final r = maak(s);
      await r.start([_eigen('A', 'a'), _eigen('B', 'b')], aantal: 3);
      r.voegReserveBij(r.sessie, [Radioplek(artiest: 'Eigen', titel: 'r', eigen: _t('Eigen', 'r'), reserve: true)]);
      expect(r.aantalBereikt, isFalse);
      r.stop();
    });

    test('"Ga door" na het stoppen doet niets', () async {
      final s = _Speler();
      var rondes = 0;
      final log = <String>[];
      final r = maak(s);
      await r.start([_eigen('A', 'a')], aantal: 1, spoor: log.add, bijvul: (_, __, ___) async {
        rondes++;
        return 0;
      });
      r.stop();
      r.gaDoor();
      expect(rondes, 0);
      expect(log.any((l) => l.contains('gaat door')), isFalse, reason: 'een gestopte radio gaat niet door');
      expect(r.aantal, 1);
    });

    test('het aantal is pas "op" als er niets meer onderweg is', () async {
      final s = _Speler();
      final r = maak(s);
      // De bron antwoordt nooit: B blijft onderweg.
      await r.start([_eigen('A', 'a'), Radioplek(artiest: 'B', titel: 'b')], aantal: 2);
      expect(r.plan.firstWhere((p) => p.artiest == 'B').stand, Haalstand.onderweg);
      expect(r.aantalBereikt, isTrue);
      expect(r.aantalOp, isFalse, reason: 'B komt nog: "de radio stopt hier" zou liegen');
      r.stop();
    });
  });

  group('de reserve', () {
    test('DE KERN: achteraan, en pas in de rij als er minder dan twee vooruit staan', () async {
      final s = _Speler();
      final r = maak(s);
      final sessie = await r.start([for (final t in 'abcde'.split('')) _eigen('Artiest $t', t)]).then((_) => r.sessie);
      final reserve = Radioplek(artiest: 'Eigen', titel: 'reserve', eigen: _t('Eigen', 'reserve'), reserve: true);
      expect(r.voegReserveBij(sessie, [reserve]), 1);
      expect(r.plan.last, same(reserve));
      s.index = 1; // drie vooruit
      r.tikVoorToets();
      expect(reserve.stand, Haalstand.klaar);
      s.index = 3; // één vooruit
      r.tikVoorToets();
      expect(reserve.stand, Haalstand.inRij);
      expect(s.rij.last.local?.path, reserve.eigen!.path);
      r.stop();
    });

    test('geen reserve-plek zonder eigen bestand', () async {
      final s = _Speler();
      final r = maak(s);
      await r.start([_eigen('A', 'a')]);
      expect(r.voegReserveBij(r.sessie, [Radioplek(artiest: 'X', titel: 'x', reserve: true)]), 0);
      r.stop();
    });
  });

  group('waarom een plek geweerd werd', () {
    test('DE KERN: wat de keuring als reden gaf blijft staan', () async {
      final s = _Speler();
      final r = maak(s);
      await r.start([_eigen('A', 'a'), Radioplek(artiest: 'Clouseau', titel: 'Vonken')], keur: (p) async {
        p.weer = Weerreden.tijdvak;
        p.buitenJaar = 2001;
        return false;
      });
      await _totAllesTerug(r);
      final c = r.plan.firstWhere((p) => p.artiest == 'Clouseau');
      expect(c.stand, Haalstand.mislukt);
      expect(c.weer, Weerreden.tijdvak, reason: 'een ruimer venster moet deze weigering later terugvinden');
      expect(c.buitenJaar, 2001);
      r.stop();
    });

    test('zonder reden van de keuring is het stijl', () async {
      final s = _Speler();
      final r = maak(s);
      await r.start([_eigen('A', 'a'), Radioplek(artiest: 'K3', titel: 'Oya lele')], keur: (_) async => false);
      await _totAllesTerug(r);
      expect(r.plan.firstWhere((p) => p.artiest == 'K3').weer, Weerreden.stijl);
      r.stop();
    });

    test('het vangnet hoort bij de start die het werd', () {
      final scherm = File('lib/main.dart').readAsStringSync();
      final i = scherm.indexOf('      bijStart: (s) {\n    gestart = s;');
      expect(i, greaterThanOrEqualTo(0));
      expect(scherm.substring(i, i + 600).contains('radio.eigenVanZaad = () => ['), isTrue);
      expect(scherm.contains('bijStart: (_) => radio.eigenVanZaad = () => ['), isTrue, reason: 'ook de zin-radio');
    });

    test('de keuring in main.dart geeft de reden door, en het plafond telt met venster', () {
      final scherm = File('lib/main.dart').readAsStringSync();
      // Ja/nee en geen `contains` op het hele bestand: dat drukt bij een fout heel main.dart af.
      expect(scherm.contains('buitenJaar: (j) {\n          p.weer = Weerreden.tijdvak;\n          p.buitenJaar = j;'), isTrue,
          reason: 'de keuring moet het tijdvak als reden op de plek zetten');
      expect(scherm.contains("NEE — past niet in de sfeer (het model)');\n        p.weer = Weerreden.sfeer;"), isTrue,
          reason: 'en de sfeer');
      expect(scherm.contains('al: [for (final p in radio.plan) p.artiest]'), isFalse,
          reason: 'het plafond zonder venster staat er weer');
      expect(RegExp(r'al: artiestenVoorPlafond\(radio\.plan, voorbijteller: radio\.voorbijteller\)').allMatches(scherm).length,
          greaterThanOrEqualTo(4));
    });
  });

  group('herhalen en herkansen', () {
    test('een verdwenen bestand komt niet terug — een ander wel', () async {
      final s = _Speler();
      final r = maak(s);
      await r.start([_eigen('A', 'a'), _eigen('B', 'b'), _eigen('C', 'c')]);
      s.bijRadioOverslaan!(s.rij[0], bestand: true);
      expect(r.plan[0].weer, Weerreden.verdwenen);
      r.gehoord(r.plan[0].eigen!);
      r.gehoord(r.plan[1].eigen!);
      s.index = 2;
      r.tikVoorToets(); // a en b voorbij (stap 1)
      // Lang geleden: laat de teller oplopen zonder dat a of b opnieuw speelt.
      for (var i = 0; i < 30; i++) {
        r.voegBij(r.sessie, [_eigen('Vul $i', 'v')]);
      }
      for (var i = 0; i < 30; i++) {
        r.tikVoorToets();
        s.index = s.rij.length - 1;
      }
      r.tikVoorToets();
      final voor = r.plan.length;
      final n = r.voegHerhalingBij(r.sessie, 2);
      final nieuw = r.plan.sublist(voor);
      expect(n, nieuw.length);
      expect(nieuw.map((p) => p.eigen!.path), isNot(contains(r.plan[0].eigen!.path)));
      expect(nieuw.map((p) => p.artiest), contains('B'));
      expect(nieuw.every((p) => p.herhaling && p.stand == Haalstand.geland), isTrue);
      r.stop();
    });

    test('onbereikbaar gebleven (overgeslagen na de tweede poging) komt ook niet terug', () async {
      final s = _Speler();
      final r = maak(s);
      await r.start([_eigen('A', 'a'), _eigen('B', 'b'), _eigen('C', 'c')]);
      s.bijRadioOverslaan!(s.rij[0], bestand: false);
      expect(r.plan[0].weer, Weerreden.nietGevonden);
      r.gehoord(r.plan[0].eigen!);
      s.index = 2;
      r.tikVoorToets();
      for (var i = 0; i < 30; i++) {
        r.voegBij(r.sessie, [_eigen('Vul $i', 'v')]);
        r.tikVoorToets();
        s.index = s.rij.length - 1;
      }
      final voor = r.plan.length;
      r.voegHerhalingBij(r.sessie, 2);
      expect(r.plan.sublist(voor).map((p) => p.artiest), isNot(contains('A')));
      r.stop();
    });

    test('DE KERN: niet gevonden krijgt na een half uur één herkansing', () async {
      final s = _Speler();
      final r = maak(s, bron: _Bron((_) async => null));
      await r.start([_eigen('A', 'a'), Radioplek(artiest: 'B', titel: 'b')]);
      await _totAllesTerug(r);
      final b = r.plan.firstWhere((p) => p.artiest == 'B');
      expect(b.stand, Haalstand.mislukt);
      expect(b.weer, Weerreden.nietGevonden);
      expect(r.herkans(r.sessie, ronde: r.bijvulRonde), 0, reason: 'nog geen half uur');
      nu = nu.add(const Duration(minutes: 31));
      expect(r.herkans(r.sessie, ronde: r.bijvulRonde), 1);
      expect(b.stand, Haalstand.wacht);
      b
        ..stand = Haalstand.mislukt
        ..weer = Weerreden.nietGevonden;
      nu = nu.add(const Duration(minutes: 31));
      expect(r.herkans(r.sessie, ronde: r.bijvulRonde), 0, reason: 'één keer');
      r.stop();
    });
  });
}

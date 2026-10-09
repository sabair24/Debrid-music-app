/// Het bijvullen zonder model (plan van 08-10-2026, uitlevering 1).
///
/// De grens die hier vastligt: zonder sfeeroordeel vult de radio alleen uit de toppers van de
/// zaadartiest en van zijn `/related` — nooit uit de artiestenradio van Deezer. Gemeten die dag: in
/// de artiestenradio van Niels Destadsbader zitten K3, Kinderen Voor Kinderen en Katastroof; in
/// `/related` niet.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/player.dart';
import 'package:debridmusic/radio.dart';
import 'package:debridmusic/radiobijvuller.dart';
import 'package:debridmusic/radiokeuze.dart';
import 'package:debridmusic/radiovoorraad.dart';
import 'package:debridmusic/recommend.dart';
import 'package:flutter_test/flutter_test.dart';

class _Speler implements PlayerStore {
  final rij = <RadioItem>[];
  @override
  Future<List<RadioItem>> Function()? radioExtend;
  @override
  void Function(List<RadioItem> gespeeld)? bijRadioEinde;
  @override
  void Function(RadioItem item, {required bool bestand})? bijRadioOverslaan;
  @override
  List<RadioItem> get radioQueue => rij;
  @override
  int get radioIndex => 0;
  @override
  bool get playing => false;
  @override
  bool get radioDroog => false;
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
  void voegToeAanRadio(List<RadioItem> meer) => rij.addAll(meer);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bron implements Radiobron {
  @override
  Future<String?> begin() async => null;
  @override
  void einde() {}
  @override
  void staak() {}
  @override
  Future<Track?> haal(Radioplek p) => Completer<Track?>().future;
  @override
  Future<bool> vergeet({required String pad, required String artiest, required String titel}) async => true;
}

/// Een nagespeeld Deezer: de zaadartiest, zijn `/related`, en per artiest [perArtiest] toppers.
class _Deezer {
  _Deezer({this.perArtiest = 25});
  final int perArtiest;
  final bronVragen = <(String, bool)>[];
  final toppersVragen = <(int, int)>[];

  static const zaad = (id: 1, naam: 'Niels Destadsbader');
  static const verwant = [
    (id: 108271532, naam: 'Camille'),
    (id: 2, naam: 'Bazart'),
    (id: 3, naam: 'Natalia'),
    (id: 4, naam: 'Regi'),
  ];

  Radiodeezer get als => Radiodeezer(
        bronArtiesten: (a, metVerwant) async {
          bronVragen.add((a, metVerwant));
          if (a == zaad.naam) return (id: zaad.id, naam: zaad.naam, verwant: metVerwant ? verwant : const <Bronartiest>[]);
          final i = a.hashCode & 0xffff;
          return (id: 1000 + i, naam: a, verwant: const <Bronartiest>[]);
        },
        toppers: (id, naam, limit, index) async {
          toppersVragen.add((id, index));
          final n = (perArtiest - index).clamp(0, limit);
          return [
            for (var k = 0; k < n; k++)
              RecTrack(naam, '$naam nummer ${index + k + 1}', null, seconds: 200, rank: 1000 - k, artistId: id)
          ];
        },
      );
}

Track _t(String artiest, String titel) => Track(
    path: '${Directory.systemTemp.path}${Platform.pathSeparator}$artiest - $titel.flac',
    title: titel,
    artist: artiest,
    album: '');

List<Radioplek> _plan(List<RecTrack> recs) => [
      for (final i in spreidArtiesten([for (final r in recs) r.artist]))
        Radioplek(
            artiest: recs[i].artist,
            titel: recs[i].title,
            seconden: recs[i].seconds,
            bron: 'buren',
            deezerArtiest: recs[i].artistId)
    ];

const _vraag = (nood: false, verwacht: 5.0, reserveNodig: 0, reserveKlaar: 0);

void main() {
  late Directory wortel;
  setUp(() {
    wortel = Directory.systemTemp.createTempSync('dm_bijvul_');
    setAppDirForTest(wortel.path);
  });
  tearDown(() {
    try {
      wortel.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<RadioBesturing> radio() async {
    final r = RadioBesturing(speler: _Speler(), bron: _Bron());
    await r.start([Radioplek(artiest: 'Niels Destadsbader', titel: 'Vuur en vlam', eigen: _t('Niels Destadsbader', 'Vuur en vlam'), zaad: true)],
        zaadArtiest: 'Niels Destadsbader');
    return r;
  }

  group('de grens: alleen de buurt die we kunnen vertrouwen', () {
    test('DE KERN: geen artiestenradio, en dus geen K3', () async {
      final r = await radio();
      final d = _Deezer();
      final b = Radiobijvuller(radio: r, deezer: d.als, ankers: const ['Niels Destadsbader'], metVerwant: true, maakPlan: _plan, toeval: Random(1));
      final n = await b(r.sessie, r.bijvulRonde, _vraag);
      expect(n, greaterThan(0));
      final artiesten = {for (final p in r.plan) artiestSleutel(p.artiest)};
      expect(artiesten, isNot(contains(artiestSleutel('K3'))));
      expect(artiesten.difference({for (final a in ['Niels Destadsbader', 'Camille', 'Bazart', 'Natalia', 'Regi']) artiestSleutel(a)}), isEmpty);
      r.stop();
    });

    test('de bijvuller kent geen weg naar de artiestenradio — ook niet in main.dart', () {
      // Zonder commentaar: daar staat juist uitgelegd waaróm niet.
      final bron = File('lib/radiobijvuller.dart')
          .readAsLinesSync()
          .where((r) => !r.trimLeft().startsWith('//'))
          .join('\n');
      expect(bron, isNot(contains('artistRadio')));
      expect(bron, isNot(contains('/radio')));
      final scherm = File('lib/main.dart').readAsStringSync();
      final blokken = RegExp(r'Radiodeezer\(([\s\S]*?)\n\s*\),').allMatches(scherm).map((m) => m.group(1)!).toList();
      expect(blokken, hasLength(2), reason: 'een radio vanaf een artiest en een radio uit een zin');
      for (final blok in blokken) {
        expect(blok, isNot(contains('artistRadio')));
        expect(blok, isNot(contains('mixRadio')));
      }
    });

    test('Camille gaat op het id uit de buurt, nooit op naam', () async {
      final r = await radio();
      final d = _Deezer();
      final b = Radiobijvuller(radio: r, deezer: d.als, ankers: const ['Niels Destadsbader'], metVerwant: true, maakPlan: _plan, toeval: Random(1));
      await b(r.sessie, r.bijvulRonde, _vraag);
      expect(d.bronVragen, [('Niels Destadsbader', true)], reason: 'één naam opgezocht: de zaadartiest');
      expect(d.toppersVragen.map((v) => v.$1), contains(108271532));
      final camille = r.plan.where((p) => p.artiest == 'Camille');
      expect(camille, isNotEmpty);
      expect(camille.every((p) => p.deezerArtiest == 108271532), isTrue);
      r.stop();
    });

    test('DE VAL: de reserve krijgt alleen de zaadartiest en zijn /related', () async {
      final r = await radio();
      Set<String>? gevraagd;
      final b = Radiobijvuller(
        radio: r,
        deezer: _Deezer().als,
        ankers: const ['Niels Destadsbader'],
        metVerwant: true,
        maakPlan: _plan,
        reserveKandidaten: (a) {
          gevraagd = a;
          return const [];
        },
      );
      await b.vulReserve(r.sessie, 6);
      expect(gevraagd, {for (final a in ['Niels Destadsbader', 'Camille', 'Bazart', 'Natalia', 'Regi']) artiestSleutel(a)});
      r.stop();
    });
  });

  group('de buren', () {
    test('DE KERN: per artiest hoogstens drie, en een volgende ronde gaat verder waar hij was', () async {
      final r = await radio();
      final d = _Deezer();
      final b = Radiobijvuller(radio: r, deezer: d.als, ankers: const ['Niels Destadsbader'], metVerwant: true, maakPlan: _plan, toeval: Random(1));
      await b(r.sessie, r.bijvulRonde, _vraag);
      final tel = <String, int>{};
      for (final p in r.plan.where((p) => p.bron == 'buren')) {
        tel[p.artiest] = (tel[p.artiest] ?? 0) + 1;
      }
      expect(tel.values.every((n) => n <= kMaxPerArtiest), isTrue, reason: '$tel');
      final eerste = {for (final p in r.plan) p.titel};
      // De eerste lading telt niet meer mee (niet te vinden): dan mag dezelfde artiest weer, met zijn
      // VOLGENDE nummers — niet opnieuw dezelfde.
      for (final p in r.plan.where((p) => p.bron == 'buren')) {
        p.stand = Haalstand.mislukt;
      }
      final voor = r.plan.length;
      await b(r.sessie, r.bijvulRonde, _vraag);
      final tweede = [for (final p in r.plan.sublist(voor)) p.titel];
      expect(tweede, isNotEmpty);
      expect(tweede.where(eerste.contains), isEmpty, reason: 'geen nummer twee keer');
      r.stop();
    });

    test('wat al in de radio staat telt mee en wordt niet nog eens aangeboden', () async {
      final r = await radio();
      r.voegBij(r.sessie, [Radioplek(artiest: 'Bazart', titel: 'Bazart nummer 1')]);
      final b = Radiobijvuller(radio: r, deezer: _Deezer().als, ankers: const ['Niels Destadsbader'], metVerwant: true, maakPlan: _plan, toeval: Random(1));
      await b(r.sessie, r.bijvulRonde, _vraag);
      final bazart = [for (final p in r.plan) if (p.artiest == 'Bazart') p.titel];
      expect(bazart, ['Bazart nummer 1', 'Bazart nummer 2', 'Bazart nummer 3'],
          reason: 'twee plekken over onder het plafond, en die gaan naar nummers die er nog niet zijn');
      r.stop();
    });

    test('eigen nummers uit de buurt pas na de keuring', () async {
      final r = await radio();
      final d = _Deezer(perArtiest: 3);
      final gekeurd = <String>[];
      final b = Radiobijvuller(
        radio: r,
        deezer: d.als,
        ankers: const ['Niels Destadsbader'],
        metVerwant: true,
        toeval: Random(1),
        maakPlan: (recs) => [
          for (final p in _plan(recs))
            p.artiest == 'Bazart' ? Radioplek(artiest: p.artiest, titel: p.titel, eigen: _t(p.artiest, p.titel)) : p
        ],
        keurEigen: (p) async {
          gekeurd.add(p.titel);
          return p.titel.endsWith('1');
        },
      );
      await b(r.sessie, r.bijvulRonde, _vraag);
      await pumpEventQueue();
      expect(gekeurd, hasLength(3));
      final bazart = [for (final p in r.plan) if (p.artiest == 'Bazart') p.titel];
      expect(bazart, ['Bazart nummer 1']);
      r.stop();
    });

    test('een ingehaalde ronde voegt niets toe', () async {
      final r = await radio();
      final b = Radiobijvuller(radio: r, deezer: _Deezer().als, ankers: const ['Niels Destadsbader'], metVerwant: true, maakPlan: _plan);
      final voor = r.plan.length;
      expect(await b(r.sessie, r.bijvulRonde + 1, _vraag), 0);
      expect(r.plan.length, voor);
      r.stop();
    });

    test('DE VAL: als de buurt op is herhaalt hij in dezelfde ronde, en de trap gaat dicht', () async {
      final r = await radio();
      final log = <String>[];
      final zaad = _t('Niels Destadsbader', 'Pa');
      r.eigenVanZaad = () => [zaad];
      final d = _Deezer(perArtiest: 0);
      final b = Radiobijvuller(
          radio: r,
          deezer: d.als,
          ankers: const ['Niels Destadsbader'],
          metVerwant: true,
          maakPlan: _plan,
          spoor: log.add);
      const krap = (nood: false, verwacht: 1.0, reserveNodig: 0, reserveKlaar: 0);
      expect(await b(r.sessie, r.bijvulRonde, krap), greaterThan(0));
      expect(r.plan.last.eigen?.path, zaad.path, reason: 'het vangnet, in dezelfde ronde');
      expect(log.last, contains('de buurt is nu op'));
      expect(r.bijvulStand, isNotNull);
      // De volgende ronde vraagt Deezer niets meer: de buurt is op, en wordt over een half uur opnieuw bekeken.
      final vragen = d.toppersVragen.length;
      await b(r.sessie, r.bijvulRonde, _vraag);
      expect(d.toppersVragen.length, vragen);
      expect(log.last, contains('[herhaal]'));
      expect(log.last, contains('opnieuw bekeken om'));
      r.stop();
    });

    test('DE KERN: een vol plafond is wachten, geen lege buurt', () async {
      final r = await radio();
      final log = <String>[];
      final d = _Deezer();
      final b = Radiobijvuller(radio: r, deezer: d.als, ankers: const ['Niels Destadsbader'], metVerwant: true, maakPlan: _plan, spoor: log.add);
      // Elke bronartiest staat al drie keer in wat er nog komt.
      for (final a in ['Niels Destadsbader', 'Camille', 'Bazart', 'Natalia', 'Regi']) {
        r.voegBij(r.sessie, [for (var i = 0; i < 3; i++) Radioplek(artiest: a, titel: '$a al $i')]);
      }
      await b(r.sessie, r.bijvulRonde, _vraag);
      expect(log.last, contains('aan hun plafond'));
      expect(log.last, contains('[buren]'), reason: 'niet "op": zodra er iets voorbij is, kan het weer');
      r.stop();
    });

    test('bijvullen gaat achteraan, niet tussen de startlijst', () async {
      final r = await radio();
      r.voegBij(r.sessie, [Radioplek(artiest: 'Model', titel: 'gekeurd 1'), Radioplek(artiest: 'Model', titel: 'gekeurd 2')]);
      final b = Radiobijvuller(radio: r, deezer: _Deezer().als, ankers: const ['Niels Destadsbader'], metVerwant: true, maakPlan: _plan, toeval: Random(1));
      await b(r.sessie, r.bijvulRonde, _vraag);
      final i1 = r.plan.indexWhere((p) => p.titel == 'gekeurd 1');
      final i2 = r.plan.indexWhere((p) => p.titel == 'gekeurd 2');
      final eersteBuur = r.plan.indexWhere((p) => p.bron == 'buren');
      expect(eersteBuur, greaterThan(i2));
      expect(i2, greaterThan(i1));
      r.stop();
    });

    test('een /related die niet antwoordde wordt de volgende ronde opnieuw gevraagd', () async {
      final r = await radio();
      var keer = 0;
      final deezer = Radiodeezer(
        bronArtiesten: (a, verwant) async {
          keer++;
          return (id: 1, naam: a, verwant: keer == 1 ? const <Bronartiest>[] : const [(id: 2, naam: 'Bazart')]);
        },
        toppers: (id, naam, limit, index) async => index > 0
            ? const <RecTrack>[]
            : [for (var k = 0; k < 3; k++) RecTrack(naam, '$naam $k', null, artistId: id)],
      );
      final b = Radiobijvuller(radio: r, deezer: deezer, ankers: const ['Niels Destadsbader'], metVerwant: true, maakPlan: _plan);
      expect(await b.bronnen(), hasLength(1));
      expect(await b.bronnen(), hasLength(2));
      expect(keer, 2);
      expect(await b.bronnen(), hasLength(2));
      expect(keer, 2, reason: 'eenmaal compleet: niet meer vragen');
      r.stop();
    });

    test('bij nood herhaalt de bijvuller niet nog eens — dat deed de noodvulling al', () async {
      final r = await radio();
      r.eigenVanZaad = () => [_t('Niels Destadsbader', 'Pa')];
      final b = Radiobijvuller(
          radio: r, deezer: _Deezer(perArtiest: 0).als, ankers: const ['Niels Destadsbader'], metVerwant: true, maakPlan: _plan);
      const nood = (nood: true, verwacht: 0.0, reserveNodig: 0, reserveKlaar: 0);
      expect(await b(r.sessie, r.bijvulRonde, nood), 0);
      expect(r.plan.where((p) => p.bron == 'vangnet' || p.herhaling), isEmpty);
      r.stop();
    });

    test('"Herhaalt…" verdwijnt als er niets meer te herhalen valt', () async {
      final r = await radio();
      r.eigenVanZaad = () => [_t('Niels Destadsbader', 'Pa')];
      final b = Radiobijvuller(
          radio: r, deezer: _Deezer(perArtiest: 0).als, ankers: const ['Niels Destadsbader'], metVerwant: true, maakPlan: _plan);
      const krap = (nood: false, verwacht: 1.0, reserveNodig: 0, reserveKlaar: 0);
      await b(r.sessie, r.bijvulRonde, krap);
      expect(r.bijvulStand, isNotNull, reason: 'het vangnet kwam erin');
      // Het vangnet staat er nu al: er valt niets meer te herhalen.
      await b(r.sessie, r.bijvulRonde, krap);
      expect(r.bijvulStand, isNull, reason: 'dan zoekt hij, en zegt hij niet dat hij herhaalt');
      r.stop();
    });

    test('een radio uit een zin: de genoemde artiesten zelf, zonder /related', () async {
      final r = await radio();
      final d = _Deezer();
      final b = Radiobijvuller(radio: r, deezer: d.als, ankers: const ['2 Unlimited', 'Culture Beat'], metVerwant: false, maakPlan: _plan);
      await b(r.sessie, r.bijvulRonde, _vraag);
      expect(d.bronVragen, [('2 Unlimited', false), ('Culture Beat', false)]);
      expect({for (final p in r.plan.where((p) => p.bron == 'buren')) p.artiest}, {'2 Unlimited', 'Culture Beat'});
      r.stop();
    });
  });

  group('de reserve', () {
    test('DE KERN: hoogstens wat nodig is, gekeurd, achteraan', () async {
      final r = await radio();
      final eigen = [for (var i = 0; i < 20; i++) _t('Artiest ${i % 10}', 'Eigen $i')];
      final b = Radiobijvuller(
        radio: r,
        deezer: _Deezer().als,
        ankers: const ['Niels Destadsbader'],
        metVerwant: true,
        maakPlan: _plan,
        reserveKandidaten: (_) => eigen,
        keurEigen: (p) async => !p.titel.endsWith('3'),
        toeval: Random(2),
      );
      await b.vulReserve(r.sessie, 4);
      final reserve = r.plan.where((p) => p.reserve).toList();
      expect(reserve, hasLength(4));
      expect(reserve.every((p) => p.stand == Haalstand.klaar && p.eigen != null), isTrue);
      expect(r.plan.skip(r.plan.length - 4).every((p) => p.reserve), isTrue);
      expect(reserve.where((p) => p.titel.endsWith('3')), isEmpty);
      r.stop();
    });

    test('DE VAL: wat de keuring weert komt er niet in — ook niet als er te weinig is', () async {
      final r = await radio();
      // Acht kandidaten, allemaal geprobeerd (hoogstens vier keer wat nodig is), en maar twee mogen.
      final eigen = [for (var i = 0; i < 8; i++) _t('Bazart', 'Eigen $i')];
      final b = Radiobijvuller(
        radio: r,
        deezer: _Deezer().als,
        ankers: const ['Niels Destadsbader'],
        metVerwant: true,
        maakPlan: _plan,
        reserveKandidaten: (_) => eigen,
        keurEigen: (p) async => p.titel == 'Eigen 0' || p.titel == 'Eigen 5',
      );
      await b.vulReserve(r.sessie, 4);
      expect({for (final p in r.plan.where((p) => p.reserve)) p.titel}, {'Eigen 0', 'Eigen 5'});
      r.stop();
    });

    test('DE VAL: de zaadartiest hoogstens één keer in de reserve, de rest twee', () async {
      final r = await radio();
      final eigen = [
        for (var i = 0; i < 10; i++) _t('Niels Destadsbader', 'Niels $i'),
        for (var i = 0; i < 10; i++) _t('Bazart', 'Bazart $i'),
      ];
      final b = Radiobijvuller(
        radio: r,
        deezer: _Deezer().als,
        ankers: const ['Niels Destadsbader'],
        metVerwant: true,
        maakPlan: _plan,
        reserveKandidaten: (_) => eigen,
        toeval: Random(3),
      );
      // Het zaad zelf speelt nog: dan geen Niels in de reserve.
      await b.vulReserve(r.sessie, 6);
      var reserve = r.plan.where((p) => p.reserve).toList();
      expect(reserve.where((p) => p.artiest == 'Niels Destadsbader'), isEmpty);
      expect(reserve.where((p) => p.artiest == 'Bazart'), hasLength(2));
      // Lang geleden voorbij: dan één.
      r.plan.first.voorbijOp = -100;
      await b.vulReserve(r.sessie, 6);
      reserve = r.plan.where((p) => p.reserve).toList();
      expect(reserve.where((p) => p.artiest == 'Niels Destadsbader'), hasLength(1));
      expect(reserve, hasLength(3), reason: 'meer dan één Niels en twee Bazart is er niet');
      r.stop();
    });

    test('wat al in de radio staat komt er niet nog eens bij', () async {
      final r = await radio();
      final b = Radiobijvuller(
        radio: r,
        deezer: _Deezer().als,
        ankers: const ['Niels Destadsbader'],
        metVerwant: true,
        maakPlan: _plan,
        reserveKandidaten: (_) => [_t('Niels Destadsbader', 'Vuur en vlam')],
      );
      await b.vulReserve(r.sessie, 6);
      expect(r.plan.where((p) => p.reserve), isEmpty);
      r.stop();
    });
  });

  group('Deezer zelf', () {
    test('een topper draagt het id van zijn artiest mee', () async {
      final rec = RecommendService(haal: (url) async {
        if (url.contains('/artist/108271532/top')) {
          return {
            'data': [
              {
                'title': 'Vuurwerk',
                'duration': 190,
                'rank': 500000,
                'artist': {'id': 108271532, 'name': 'Camille'},
                'album': {'id': 9, 'title': 'Vuurwerk'},
              }
            ]
          };
        }
        return null;
      });
      final t = await rec.toppers(108271532, 'Camille', limit: 25);
      expect(t.single.artistId, 108271532);
    });

    test('bronArtiesten: de artiest en zijn /related met ids', () async {
      final rec = RecommendService(haal: (url) async {
        if (url.contains('/search/artist')) {
          return {
            'data': [
              {'id': 1, 'name': 'Niels Destadsbader', 'nb_fan': 10}
            ]
          };
        }
        if (url.contains('/artist/1/related')) {
          return {
            'data': [
              {'id': 108271532, 'name': 'Camille'},
              {'id': 2, 'name': 'Bazart'},
              {'name': 'zonder id'},
            ]
          };
        }
        return null;
      });
      final b = await rec.bronArtiesten('Niels Destadsbader');
      expect(b?.id, 1);
      expect(b?.verwant, [(id: 108271532, naam: 'Camille'), (id: 2, naam: 'Bazart')]);
      final zonder = await rec.bronArtiesten('Niels Destadsbader', metVerwant: false);
      expect(zonder?.verwant, isEmpty);
    });
  });
}

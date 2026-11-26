/// Aanbevolen voor jou en Ontdek, 26-11-2026. Saber, met een schermafdruk van de rij (15 nummers, half raï): *"de rij
/// aanbevolen voor jou is nog niets veranderd ?? teveel rai, en ik wil daar zeker 200 liedjes zien. plus de ververs
/// button bij ontdek werkt niet , daar moeten ook zeker 200 liedjes."*
///
/// Gemeten die ochtend: de pc rekende wel 200 aanbevolen nummers zonder raï, maar de startpagina vroeg ze nooit op —
/// het ophalen hing aan "de rij is leeg", en de rij werd bij het openen gevuld met de lijst op schijf (van vóór 21-11).
/// Elke berekening meldde "nog 0 nieuw": de voorraad was te smal. En Ontdek verversen rekende 35–56 s, terwijl een
/// toestel het na 30 s opgaf.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:debridmusic/aanbevolen.dart';
import 'package:debridmusic/nieuwe_releases.dart' show EigenArtiest;
import 'package:debridmusic/ontdek.dart';
import 'package:debridmusic/organize.dart' show artistKey;
import 'package:debridmusic/recommend.dart' show RecTrack;
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');
RecTrack _t(String artiest, String titel) => RecTrack(artiest, titel, null, seconds: 200);
OntdekNummer _n(String artiest, String titel, {Ontdekbron bron = Ontdekbron.deezer}) =>
    OntdekNummer(_t(artiest, titel), bron: bron);
final _nu = DateTime(2026, 11, 26, 7);
final _nuMs = _nu.millisecondsSinceEpoch;
bool _niets(String _, String __) => false;

void main() {
  group('de startpagina vraagt de lijst echt op', () {
    test('DE KERN: wat er van schijf staat, houdt het ophalen niet meer tegen', () {
      final m = _bron('lib/main.dart');
      expect(m, contains('    if (!_seedsRequested && artists.isNotEmpty && !_StartCache.persoonlijkGeladen) {\n'));
      expect(m, isNot(contains('if (!_seedsRequested && artists.isNotEmpty && _StartCache.forYou.isEmpty) {')));
      expect(m, contains('    _StartCache.persoonlijkGeladen = true;\n    _StartCache.opgehaaldMs'));
      expect(m, contains('    uitgezocht = [];\n    persoonlijkGeladen = false;\n'), reason: 'Ververs en verlopen: opnieuw');
    });

    test('de rij toont ze allemaal, en het zijn er meer dan 200', () {
      expect(kAanbevolenInRij, kAanbevolenNummers);
      expect(kAanbevolenNummers, greaterThan(200), reason: 'een toestel zeeft er nog uit wat het zelf heeft');
    });
  });

  group('aanbevolen: een trekking', () {
    test('DE KERN: hoogstens twee per artiest', () {
      final voorraad = [
        for (var i = 0; i < 5; i++) _t('Veel', 'V$i'),
        for (var i = 0; i < 5; i++) _t('Ander $i', 'A$i'),
      ];
      final uit = trekUitVoorraad(voorraad, const {}, aantal: 6, nuMs: _nuMs);
      expect(uit.where((t) => t.artist == 'Veel'), hasLength(kAanbevolenPerArtiest));
      expect(uit, hasLength(6));
    });

    test('ook bij het aanvullen met wat al gezien was', () {
      final voorraad = [for (var i = 0; i < 6; i++) _t('Veel', 'V$i'), _t('B', 'b')];
      final getoond = {for (final t in voorraad) aanbevolenSleutel(t): _nuMs - 1000};
      final uit = trekUitVoorraad(voorraad, getoond, aantal: 5, nuMs: _nuMs);
      expect(uit.where((t) => t.artist == 'Veel'), hasLength(2));
      expect(uit.map((t) => t.artist), contains('B'));
    });

    test('de voorraad is breed: veel meer artiesten en nummers dan één lijst', () {
      expect(kAanbevolenVoorraad, greaterThanOrEqualTo(5 * kAanbevolenNummers));
      expect(kAanbevolenKandidaten * kAanbevolenVoorraadPerArtiest, greaterThanOrEqualTo(kAanbevolenVoorraad));
      expect(kAanbevolenZaden, greaterThanOrEqualTo(40));
      final r = _bron('lib/recommend.dart');
      expect(r, contains('_top(k.id, k.naam, limit: kAanbevolenToppers)'));
      expect(r, contains('max: max, perArtiest: kAanbevolenVoorraadPerArtiest);'));
    });
  });

  group('aanbevolen: bijvullen', () {
    late Directory map;
    setUp(() => map = Directory.systemTemp.createTempSync('dm_aanb_bij_'));
    tearDown(() {
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('DE KERN: na een ververs vult de pc de voorraad aan, maar de lijst die je kreeg blijft staan', () async {
      var ronde = 0;
      final d = AanbevolenVoorJou(
        zoeker: (zaden, bezit) async {
          ronde++;
          return [for (var i = 0; i < 400; i++) _t('R$ronde-A$i', 'T$i')];
        },
        artiesten: () => [for (var i = 0; i < 50; i++) EigenArtiest(naam: 'E$i', beurten: 60 - i, nummers: 10)],
        groen: () => {},
        bezit: () => {},
        bestand: File('${map.path}${Platform.pathSeparator}aanbevolen.json'),
      );
      await d.ververs();
      await d.volgende();
      final getrokken = [for (final t in d.lijst!.nummers) aanbevolenSleutel(t)];
      for (var i = 0; i < 100 && ronde < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      for (var i = 0; i < 20 && d.bezig; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(ronde, 2, reason: 'minder dan een lijst nieuw over: bijrekenen');
      expect([for (final t in d.lijst!.nummers) aanbevolenSleutel(t)], getrokken,
          reason: 'de lijst die je net kreeg, verandert niet onder je handen');
      expect(d.nogVers, greaterThanOrEqualTo(kAanbevolenNummers), reason: 'de nieuwe voorraad is nog ongezien');
    });
  });

  group('ontdek: de voorraad en een trekking', () {
    test('DE KERN: één per artiest en één per lied, eerst wat je nog niet zag', () {
      final voorraad = [
        _n('A', 'a1'),
        _n('A', 'a2'),
        _n('B', 'The Rhythm Of The Night'),
        _n('C', 'The Rhythm of the Night'),
        _n('D', 'd1'),
        _n('E', 'e1'),
      ];
      final getoond = {ontdekSleutel('D', 'd1'): _nuMs - 1000};
      final uit = trekOntdek(voorraad, getoond, aantal: 10, nuMs: _nuMs);
      expect(uit.map((n) => n.nummer.title), ['a1', 'The Rhythm Of The Night', 'e1', 'd1'],
          reason: 'A één keer, het lied één keer, D (gezien) achteraan');
    });

    test('wat nu niet meer mag (opgehaald, weggetikt), valt eruit', () {
      final voorraad = [_n('A', 'a'), _n('B', 'b'), _n('C', 'c')];
      final uit = trekOntdek(voorraad, const {}, aantal: 3, nuMs: _nuMs, bruikbaar: (n) => n.nummer.artist != 'B');
      expect(uit.map((n) => n.nummer.artist), ['A', 'C']);
    });

    test('de voorraad mag meer nummers per artiest hebben; een lijst niet', () {
      final perBron = {
        Ontdekbron.deezer: [for (var a = 0; a < 3; a++) for (var i = 0; i < 4; i++) _n('A$a', 't$a-$i')],
      };
      final voorraad = stelOntdekSamen(perBron, heb: _niets, nuMs: _nuMs, verderElke: 0, perArtiest: 3);
      expect(voorraad.where((n) => n.nummer.artist == 'A0'), hasLength(3));
      final lijst = stelOntdekSamen(perBron, heb: _niets, nuMs: _nuMs, verderElke: 0);
      expect(lijst.where((n) => n.nummer.artist == 'A0'), hasLength(1), reason: 'standaard één per artiest');
      expect(kOntdekGetoond, 200);
      expect(kOntdekTrekking, greaterThan(kOntdekGetoond), reason: 'met een reserve');
      expect(kOntdekLengte, greaterThanOrEqualTo(4 * kOntdekTrekking));
    });
  });

  group('ontdek: verversen', () {
    late Directory map;
    setUp(() => map = Directory.systemTemp.createTempSync('dm_ontdek_vv_'));
    tearDown(() {
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    OntdekVoorJou dienst(List<int> rondes, {int artiesten = 900}) => OntdekVoorJou(
          artiesten: (_) => [for (var i = 0; i < 20; i++) OntdekArtiest(naam: 'E$i', gewicht: 5, hoek: 'popsoul')],
          heb: _niets,
          bestand: File('${map.path}/ontdek.json'),
          wegBestand: File('${map.path}/ontdek_weg.json'),
          deezer: (_) async {
            rondes.add(1);
            final r = rondes.length;
            return [for (var i = 0; i < artiesten; i++) _n('R$r-A$i', 't$i')];
          },
          klok: () => _nu,
          toeval: math.Random(7),
        );

    test('DE KERN: verversen geeft meteen een nieuwe lijst van 200, zonder opnieuw te rekenen', () async {
      final rondes = <int>[];
      final d = dienst(rondes);
      await d.ververs();
      expect(rondes, hasLength(1));
      final eerst = {for (final n in d.lijst!.nummers.take(kOntdekGetoond)) n.sleutel};
      expect(eerst, hasLength(kOntdekGetoond));
      final t0 = DateTime.now();
      await d.volgende();
      expect(DateTime.now().difference(t0), lessThan(const Duration(seconds: 2)));
      final tweede = {for (final n in d.lijst!.nummers.take(kOntdekGetoond)) n.sleutel};
      expect(tweede, hasLength(kOntdekGetoond));
      expect(tweede.intersection(eerst), isEmpty, reason: 'elke ververs andere nummers');
      expect(rondes, hasLength(1), reason: 'uit de voorraad, niet opnieuw bij Deezer');
      final artiesten = {for (final n in d.lijst!.nummers) ontdekArtiest(n.nummer.artist)};
      expect(artiesten, hasLength(d.lijst!.nummers.length), reason: 'één per artiest');
    });

    test('raakt de voorraad op, dan rekent de pc bij — en de lijst die je kreeg blijft staan', () async {
      final rondes = <int>[];
      final d = dienst(rondes, artiesten: 400);
      await d.ververs();
      await d.volgende();
      final getrokken = [for (final n in d.lijst!.nummers) n.sleutel];
      for (var i = 0; i < 100 && rondes.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      for (var i = 0; i < 20 && d.bezig; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(rondes, hasLength(2), reason: 'minder dan een lijst nieuws over');
      expect([for (final n in d.lijst!.nummers) n.sleutel], getrokken);
      expect(d.nogVers, greaterThanOrEqualTo(kOntdekTrekking));
    });

    test('de voorraad houdt tot drie nummers per artiest: een volgende lijst kan van dezelfde artiest een ánder nummer',
        () async {
      final rondes = <int>[];
      final d = OntdekVoorJou(
        artiesten: (_) => [for (var i = 0; i < 20; i++) OntdekArtiest(naam: 'E$i', gewicht: 5, hoek: 'popsoul')],
        heb: _niets,
        bestand: File('${map.path}/ontdek.json'),
        wegBestand: File('${map.path}/ontdek_weg.json'),
        deezer: (_) async {
          rondes.add(1);
          return [for (var j = 0; j < 3; j++) for (var i = 0; i < 300; i++) _n('A$i', 't$i-$j')];
        },
        klok: () => _nu,
        toeval: math.Random(7),
      );
      await d.ververs();
      expect(d.nogVers, 300, reason: 'alle 300 artiesten hebben nog een ongezien nummer');
      await d.volgende();
      expect(rondes, hasLength(1), reason: 'genoeg in de voorraad: niet bijrekenen');
    });

    test('de voorraad blijft over een herstart', () async {
      final rondes = <int>[];
      final d = dienst(rondes);
      await d.ververs();
      final eerst = {for (final n in d.lijst!.nummers.take(kOntdekGetoond)) n.sleutel};
      final na = dienst(rondes);
      await na.laad();
      await na.volgende();
      expect(rondes, hasLength(1), reason: 'de voorraad kwam van schijf');
      expect({for (final n in na.lijst!.nummers.take(kOntdekGetoond)) n.sleutel}.intersection(eerst), isEmpty);
    });

    test('na de update: een lijst zonder voorraad krijgt er bij de start meteen een, en de lijst blijft staan', () async {
      final rondes = <int>[];
      final d = dienst(rondes);
      await d.ververs();
      final f = File('${map.path}/ontdek.json');
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>..remove('voorraad');
      f.writeAsStringSync(jsonEncode(j));
      final na = dienst(rondes);
      await na.laad();
      final lijst = [for (final n in na.lijst!.nummers) n.sleutel];
      na.start(eerst: Duration.zero);
      for (var i = 0; i < 100 && rondes.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      for (var i = 0; i < 20 && na.bezig; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      na.stop();
      expect(rondes, hasLength(2), reason: 'meteen een voorraad, zodat de eerste ververs niet wacht');
      expect([for (final n in na.lijst!.nummers) n.sleutel], lijst);
      expect(na.nogVers, greaterThan(0));
    });

    test('een toestel kijkt na verversen nog eens zolang de pc rekent', () {
      final m = _bron('lib/main.dart');
      expect(m, contains("          if (j['bezig'] == true) {\n            Timer(const Duration(seconds: 25), () {"));
      expect(_bron('lib/aanbevolen.dart'), contains('      } else if (_voorraad.length < kAanbevolenVoorraad ~/ 2) {'));
    });

    test('aangesloten: de server en het scherm trekken meteen; de Deezer-bron is breder', () {
      expect(_bron('lib/lan/server.dart'),
          contains('      l = await d.volgende().timeout(const Duration(seconds: 25), onTimeout: () => d.lijst);'));
      expect(_bron('lib/main.dart'), contains('        if (ververs) {\n'));
      expect(_bron('lib/ontdek_bronnen.dart'),
          contains('eigen: eigen?.call() ?? const {}, kandidaten: kOntdekKandidaten, verderVan: kOntdekVerderVan),'));
      expect(kOntdekZaden, greaterThanOrEqualTo(30));
      expect(artistKey('A'), isNotEmpty);
    });
  });
}

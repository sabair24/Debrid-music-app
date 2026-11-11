// Een naamgenoot bij TheAudioDB, nagekeken op de achtergrond.
//
// Saber, 11-11-2026, na een testronde: de pagina van de Belgische Natalia toonde "geboren 1982, Sanlúcar de Barrameda, Spain"
// — TheAudioDB kent alleen de Spaanse (135583), en dezelfde naam werd als bewijs genomen. Zijn keuze: de foto blijft meteen
// komen; blijkt het achteraf een naamgenoot, dan vallen foto en feiten weg en wordt dat onthouden.
//
// Gemeten op dezelfde avond over de 475 artiesten uit de bibliotheek met dezelfde naam bij TheAudioDB: 465 hetzelfde
// MusicBrainz-nummer, 8 anders. Bij Eve, Mya en Jordy koos MusicBrainz zelf een naamgenoot; daarom moet ook Wikidata het
// oneens zijn. Live nagekeken: Natalia, Khaled (DJ Khaled) en Amine (Aminé uit Portland) naamgenoot; Eve, Mya, Jordy, Betty,
// Dave, Milow, The Jacksons en Lula klopt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/cachesleutel.dart';
import 'package:debridmusic/enrichment.dart';
import 'package:debridmusic/musicbrainz.dart';
import 'package:debridmusic/paths.dart';

const _spaans = 'a900f340-3ebf-4b4f-89b9-b59a6e9d5337', _belgisch = 'b1b1b1b1-0000-4000-8000-000000000001';

Map<String, dynamic> _rij({String naam = 'Natalia', String id = '135583', String mb = _spaans}) =>
    {'strArtist': naam, 'idArtist': id, 'strMusicBrainzID': mb, 'strCountry': 'Sanlúcar de Barrameda, Spain'};

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  setUp(() {
    setAppDirForTest(Directory.systemTemp.createTempSync('naamgenoot').path);
    AudioDbOordelen.vergeet();
  });

  group('de keuze bij het tonen', () {
    test('DE KERN: dezelfde naam met een nummer: meteen aangenomen, en op de achtergrond nagekeken', () async {
      final nagekeken = <String>[];
      final uit = await kiesAudioDbArtiest('Natalia', _rij(),
          mb: (_) async => throw 'niet nodig: de foto komt meteen',
          opMb: (_) async => null,
          oordeel: AudioDbOordelen.oordeel,
          nakijken: (n, _) => nagekeken.add(n));
      expect(uit?['idArtist'], '135583');
      expect(nagekeken, ['Natalia']);
    });

    test('een bewezen naamgenoot gaat langs MusicBrainz: de juiste rij, of niets', () async {
      await AudioDbOordelen.zet('Natalia', '135583', kOordeelNaamgenoot);
      final uit = await kiesAudioDbArtiest('Natalia', _rij(),
          mb: (_) async => const MbArtist(_belgisch, 'Natalia'),
          opMb: (_) async => null, // TheAudioDB kent de Belgische niet
          oordeel: AudioDbOordelen.oordeel,
          nakijken: (_, __) => fail('al nagekeken'));
      expect(uit, isNull, reason: 'liever de foto van Deezer dan die van de Spaanse');
    });

    test('al nagekeken en goed: geen tweede keer', () async {
      await AudioDbOordelen.zet('Eve', '111767', kOordeelKlopt);
      final uit = await kiesAudioDbArtiest('Eve', _rij(naam: 'Eve', id: '111767', mb: 'eve-rapper'),
          mb: (_) async => throw 'niet nodig',
          opMb: (_) async => null,
          oordeel: AudioDbOordelen.oordeel,
          nakijken: (_, __) => fail('al nagekeken'));
      expect(uit?['idArtist'], '111767');
    });

    test('zonder nummer valt er niets na te kijken', () async {
      var nagekeken = false;
      final uit = await kiesAudioDbArtiest('Lula', {'strArtist': 'Lula', 'idArtist': '174228'},
          mb: (_) async => null, opMb: (_) async => null, oordeel: AudioDbOordelen.oordeel, nakijken: (_, __) => nagekeken = true);
      expect(uit, isNotNull);
      expect(nagekeken, isFalse);
    });

    test('het oordeel blijft bewaard, ook na een herstart', () async {
      await AudioDbOordelen.zet('Natalia', '135583', kOordeelNaamgenoot);
      AudioDbOordelen.vergeet();
      expect(await AudioDbOordelen.oordeel('natalia', '135583'), kOordeelNaamgenoot);
      expect(await AudioDbOordelen.oordeel('Natalia', '999'), isNull, reason: 'per rij');
    });
  });

  group('het nakijken', () {
    Future<String?> kijk(Map<String, dynamic> rij,
            {MbArtist? kent, String? huidig, Map<String, dynamic>? echt, List<String>? wikidata = const ['x']}) =>
        CoverEnricher.kijkNaamgenootNa('${rij['strArtist']}', rij,
            mb: (_) async => kent, opMb: (_) async => echt, huidigMb: (_) async => huidig, wikidata: (_) async => wikidata);

    test('DE KERN: MusicBrainz én Wikidata kennen onder die naam iemand anders: een naamgenoot, en de buffers weg', () async {
      final h = fnv1a('natalia');
      final feiten = File('$appDir${Platform.pathSeparator}artistfeiten${Platform.pathSeparator}$h.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"land":"Spain"}');
      String? gehoord;
      void luister() => gehoord = CoverEnricher.naamgenootGevonden.value;
      CoverEnricher.naamgenootGevonden.addListener(luister);
      addTearDown(() => CoverEnricher.naamgenootGevonden.removeListener(luister));
      final o = await kijk(_rij(), kent: const MbArtist(_belgisch, 'Natalia'), wikidata: const [_belgisch]);
      expect(o, kOordeelNaamgenoot);
      expect(await AudioDbOordelen.oordeel('Natalia', '135583'), kOordeelNaamgenoot);
      expect(feiten.existsSync(), isFalse, reason: 'geen "geboren 1982, Spain" meer');
      expect(gehoord, 'Natalia', reason: 'de open pagina hoort het');
    });

    test('DE VAL: kiest alleen MusicBrainz iemand anders, en zegt Wikidata hetzelfde als TheAudioDB, dan klopt hij (Mya)', () async {
      final o = await kijk(_rij(naam: 'Mya', id: '117044', mb: 'mya-rnb'),
          kent: const MbArtist('mya-argentijns-duo', 'MYA'), wikidata: const ['mya-rnb']);
      expect(o, kOordeelKlopt);
    });

    test('een andere naam bij MusicBrainz bewijst niets ("Betty Everett" bij "Betty")', () async {
      final o = await kijk(_rij(naam: 'Betty', id: '121755', mb: 'betty-ny'),
          kent: const MbArtist('betty-everett', 'Betty Everett'), wikidata: const ['iemand-anders']);
      expect(o, kOordeelKlopt);
    });

    test('hetzelfde nummer, een samengevoegd nummer, of dezelfde rij onder het andere nummer: klopt', () async {
      expect(await kijk(_rij(), kent: const MbArtist(_spaans, 'Natalia')), kOordeelKlopt);
      AudioDbOordelen.vergeet();
      expect(await kijk(_rij(id: '1'), kent: const MbArtist(_belgisch, 'Natalia'), huidig: _belgisch), kOordeelKlopt,
          reason: 'het oude nummer is in het nieuwe opgegaan');
      expect(await kijk(_rij(id: '2'), kent: const MbArtist(_belgisch, 'Natalia'), echt: {'idArtist': '2'}), kOordeelKlopt,
          reason: 'TheAudioDB kent hem ook onder het nummer van MusicBrainz');
    });

    test('geen Wikipedia-artikel: niets om tegen te houden, dus klopt; Wikimedia zwijgt: geen oordeel', () async {
      expect(await kijk(_rij(id: '3'), kent: const MbArtist(_belgisch, 'Natalia'), wikidata: const []), kOordeelKlopt);
      expect(await kijk(_rij(id: '4'), kent: const MbArtist(_belgisch, 'Natalia'), wikidata: null), isNull);
      expect(await AudioDbOordelen.oordeel('Natalia', '4'), isNull, reason: 'een volgende keer opnieuw');
    });
  });

  group('bedrading', () {
    test('beide aanroepers van TheAudioDB kijken na, en de artiestpagina luistert', () {
      final e = _bron('lib/enrichment.dart');
      expect(e, contains('mb: audioDbMbVoor, opMb: audioDbOpMb, oordeel: AudioDbOordelen.oordeel, nakijken: nakijkenOpAchtergrond);'));
      final a = _bron('lib/audiodb.dart');
      expect(a, contains('        oordeel: AudioDbOordelen.oordeel,\n        nakijken: CoverEnricher.nakijkenOpAchtergrond);'));
      final m = _bron('lib/main.dart');
      expect(m, contains('    CoverEnricher.naamgenootGevonden.addListener(_naamgenoot);'));
      expect(m, contains('    CoverEnricher.naamgenootGevonden.removeListener(_naamgenoot);'));
      expect(m, contains('      _art = null;\n      _deezerFoto = null;\n      _bio = null;\n      _feiten = null;'));
    });
  });
}

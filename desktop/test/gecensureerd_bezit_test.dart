/// "Work B**ch" is "Work Bitch": wat je al hebt, telt ook als het met sterretjes geschreven is.
///
/// Saber, 28-11-2026: *"bij ontdek zie ik staan work bitch van britney spears, maar die heb ik al dus dat klopt niet,
/// de app moet beter controleren wat ik heb staan in men bibliotheek."* In zijn bibliotheek heet het "Work B**ch";
/// `recNorm` maakte daar "workbch" van en van de aanbeveling "workbitch". Daarbij hield Ontdek een lijst vast tot de
/// volgende trekking, ook als het nummer intussen wel van hem was.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:debridmusic/models.dart';
import 'package:debridmusic/ontdek.dart';
import 'package:debridmusic/recommend.dart';
import 'package:flutter_test/flutter_test.dart';

RecTrack _t(String artiest, String titel) => RecTrack(artiest, titel, null, seconds: 200);
Track _eigen(String artiest, String titel) => Track(path: '/m/$titel.flac', title: titel, artist: artiest, album: 'A');
final _nu = DateTime(2026, 11, 28, 9);

void main() {
  group('ontsensureer', () {
    test('elk sterretje is één letter, en het woord moet bekend zijn', () {
      expect(ontsensureer('work b**ch'), 'work bitch');
      expect(ontsensureer('Work B***h'), 'Work bitch');
      expect(ontsensureer('f**k you'), 'fuck you');
      expect(ontsensureer('sh*t'), 'shit');
      expect(ontsensureer('n****s in paris'), 'niggas in paris');
      expect(ontsensureer('p***y'), 'pussy');
      expect(ontsensureer('mother****er'), 'motherfucker');
    });

    test('wat niet past, blijft staan; zonder sterretje verandert er niets', () {
      expect(ontsensureer('l*ve'), 'l*ve', reason: 'geen bekend woord met dit patroon');
      expect(ontsensureer('b*ch'), 'b*ch', reason: 'te kort voor bitch: een sterretje is één letter');
      expect(ontsensureer('Work Bitch'), 'Work Bitch');
      expect(ontsensureer('***'), '***');
    });

    test('recNorm: gecensureerd en voluit geven dezelfde sleutel', () {
      expect(recNorm('Work B**ch'), recNorm('Work Bitch'));
      expect(recNorm('F**kin\' Perfect'), isNot(recNorm('Fuckin\' Perfect')),
          reason: 'fuckin staat niet in de lijst: dan liever een gemist bezit dan een verkeerd');
      expect(recNorm('Sh*t (Remix)'), recNorm('Shit'));
    });
  });

  test('Aanbevolen: "Work Bitch" valt weg als je "Work B**ch" hebt, en andersom', () {
    final bezit = bezitSleutels([_eigen('Britney Spears', 'Work B**ch')]);
    expect(nogNietInBezit([_t('Britney Spears', 'Work Bitch'), _t('Britney Spears', 'Toxic')], bezit).map((r) => r.title),
        ['Toxic']);
    final omgekeerd = bezitSleutels([_eigen('Britney Spears', 'Work Bitch')]);
    expect(nogNietInBezit([_t('Britney Spears', 'Work B**ch')], omgekeerd), isEmpty);
  });

  test('Ontdek: inBezit met de sleutels van je eigen nummers', () {
    final bezit = {...bezitSleutelsVan('Britney Spears', 'Work B**ch')};
    expect(inBezit(bezit, 'Britney Spears', 'Work Bitch'), isTrue);
    expect(inBezit(bezit, 'Britney Spears', 'Womanizer'), isFalse);
  });

  test('Ontdek: wat je intussen hebt, is meteen weg uit de lijst — niet pas bij de volgende trekking', () async {
    final map = Directory.systemTemp.createTempSync('gecensureerd_');
    try {
      final eigen = <String>{};
      final d = OntdekVoorJou(
        artiesten: (_) => [for (var i = 0; i < 5; i++) OntdekArtiest(naam: 'E$i', gewicht: 5, hoek: 'popsoul')],
        heb: (a, t) => eigen.contains('$a|$t'),
        bestand: File('${map.path}/ontdek.json'),
        wegBestand: File('${map.path}/ontdek_weg.json'),
        deezer: (_) async => [
          for (var i = 0; i < 40; i++) OntdekNummer(_t('A$i', 'T$i'), bron: Ontdekbron.deezer),
        ],
        klok: () => _nu,
        toeval: math.Random(3),
      );
      await d.ververs();
      final voor = d.zichtbaar.length;
      expect(voor, greaterThan(5));
      final eerste = d.zichtbaar.first.nummer;
      eigen.add('${eerste.artist}|${eerste.title}');
      expect(d.zichtbaar.length, voor - 1);
      expect(d.zichtbaar.any((n) => n.nummer.title == eerste.title && n.nummer.artist == eerste.artist), isFalse);
    } finally {
      map.deleteSync(recursive: true);
    }
  });

  test('Start: Aanbevolen verschijnt zodra het er is, en meldt aan de pc hoe lang het duurde', () {
    final m = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final begin = m.indexOf('  Future<void> _loadSeeds(List<String> seeds) async {');
    final lijf = m.substring(begin, m.indexOf('\n  }\n', begin));
    final haal = lijf.indexOf('final fyF = _haalAanbevolen(seeds);');
    final dan = lijf.indexOf('unawaited(fyF.then((fy) {');
    final wachtRest = lijf.indexOf('genreLijst = await genreF;');
    expect(haal, greaterThan(0));
    expect(dan, greaterThan(haal));
    expect(dan, lessThan(wachtRest), reason: 'de rij komt vóór het wachten op de andere rijen');
    final tak = lijf.substring(dan, lijf.indexOf('}, onError:', dan));
    expect(tak, contains('setState(() => _forYou = schoon);'));
    expect(tak, contains("_meldStart('aanbevolen: "));
    expect(lijf, contains('if (fy.isNotEmpty) _StartCache.forYou ='), reason: 'een fout maakt de rij niet leeg');
    expect(m, contains("_meldMeting?.call(['[start] \$regel'])"));
  });
}

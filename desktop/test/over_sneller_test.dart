// "Over …" op de artiestpagina (pc, 18-10-2026): op de gsm stond "Over 2 Fabiola" meteen, op de pc
// kwam het er niet. De bio stond achteraan de TheAudioDB-rij (drie seconden per vraag, en de pc vroeg
// bij elke start opnieuw naar elke artiest die TheAudioDB niet kent), Wikipedia wachtte daarop, en een
// haperend Wikipedia werd zeven dagen als "geen artikel" onthouden. Het werk gaat over het net; deze
// toets legt de bedrading vast.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String bron(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

  test('Wikipedia vertrekt vóór TheAudioDB, en de artiestpagina krijgt voorrang op de rij', () {
    final hoofd = bron('lib/main.dart');
    final begin = hoofd.indexOf('  Future<void> _loadBio() async {');
    expect(begin, greaterThan(0));
    final lijf = hoofd.substring(begin, begin + 2600);
    final wiki = lijf.indexOf('final wikiKomt = WikipediaService().artikel(naam, mbid: _mbid)');
    final bio = lijf.indexOf('bio ??= await enricher.fetchArtistBio(naam, voorrang: true);');
    expect(wiki, greaterThan(0));
    expect(bio, greaterThan(wiki), reason: 'Wikipedia wacht niet op TheAudioDB');
    expect(lijf, contains('await enricher.artistFeiten(naam, voorrang: true);'));
  });

  test('TheAudioDB: voorrang buiten de rij, een "niets" veertien dagen onthouden, een kapot bestand stopt niets', () {
    final e = bron('lib/enrichment.dart');
    expect(e, contains('await (voorrang ? _audioDbVoorrang() : _audioDbSlot());'));
    expect(e, contains('static const _bioMisDuur = Duration(days: 14);'));
    expect('await _onthoudGeenBio(name);'.allMatches(e).length, 2, reason: 'geen artiest én geen bio');
    final cached = e.indexOf('Future<String?> cachedBio(String name) async {');
    expect(e.substring(cached, cached + 500), contains('} catch (_) {'));
  });

  test('Wikipedia: een hapering is geen "geen artikel"', () {
    final w = bron('lib/wikipedia.dart');
    expect(w, contains('await _schrijf(f, _misteken(nietGevonden: !_haperde));'));
    expect('_haperde = true;'.allMatches(w).length, 2);
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Online zoeken toont wat Deezer vond zodra het er is, ook als Discogs en MusicBrainz nog bezig zijn.
///
/// Gemeten op 21-10-2026 op de gsm ("Tate McRae Revolving door"): de drie Deezer-lijsten waren er na
/// 451 ms (deezer.log), maar het scherm toonde een draaiwiel tot 4,2–4,6 s — tot ook MusicBrainz, één
/// vraag per 1,1 s, klaar was. Het draaiwiel hing aan de bezig-vlag van het hele zoeken.
void main() {
  final bron = File('lib/main.dart').readAsStringSync();
  final begin = bron.indexOf('  Widget _browseResults() {');
  final lijf = bron.substring(begin, bron.indexOf('\n  }\n', begin));

  test('het draaiwiel alleen zolang er nog niets te tonen is', () {
    expect(begin, greaterThan(0));
    expect(lijf, contains('if (_browseBusy && leeg) return Center(child: CircularProgressIndicator('));
    expect(lijf, isNot(contains('if (_browseBusy) return')));
  });

  test('wat nog aanvult, staat als dun streepje boven de uitslag', () {
    expect(lijf, contains('child: _browseBusy\n              ? LinearProgressIndicator(minHeight: 2'));
  });

  test('de bezig-vlag gaat pas uit na Discogs en MusicBrainz — daarom mag het scherm er niet op wachten', () {
    final zoek = bron.substring(bron.indexOf('  Future<void> _searchBrowse(String q) async {'));
    final deezer = zoek.indexOf('_onthoudBladeren();\n      if (mounted) setState(() {});');
    expect(deezer, greaterThan(0));
    expect(deezer, lessThan(zoek.indexOf('await _addDiscogsAlbums(q, geldig);')));
    expect(zoek.indexOf('await _addMusicBrainzHits(q, geldig);'),
        lessThan(zoek.indexOf('setState(() => _browseBusy = false);')));
  });
}

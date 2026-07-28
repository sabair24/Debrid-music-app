/// Twee bestanden van één plaat die dezelfde opname bevatten, beslist op de audio.
///
/// De titels waren hier tot nu toe het enige bewijs, en juist de titels zijn wat er mis is. Deze
/// tests leggen de twee gevallen vast die op de echte bibliotheek gemeten zijn, en die de titelregel
/// allebei verkeerd deed: één dubbele die hij niet zag, en één paar dat hij ten onrechte aanwees.
library;

import 'package:debridmusic/completeness.dart';
import 'package:debridmusic/models.dart';
import 'package:flutter_test/flutter_test.dart';

Track t(String pad, String titel, {int secs = 253}) => Track(
      path: pad,
      title: titel,
      artist: 'Michael Jackson',
      album: 'Off The Wall',
      trackNo: 3,
      duration: Duration(seconds: secs),
      isFlac: true,
    );

/// Een reeks die zich als audio gedraagt: geen regelmaat die de bittelling zou vertekenen.
List<int> reeks(int n, {int zaad = 1}) {
  final out = <int>[];
  var x = zaad;
  for (var i = 0; i < n; i++) {
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    out.add(x & 0xFFFFFFFF);
  }
  return out;
}

void main() {
  // Wie er wint doet er hier niet toe; deze tests gaan over WELKE paren gevonden worden.
  List<SameRecordingPair> paren(List<Track> ts, {Map<String, List<int>> prints = const {}}) =>
      sameRecordingPairs(ts, better: (a, b) => true, prints: prints);

  test('zonder afdrukken beslist de titel, en die mist de dubbele van Off The Wall', () {
    // Gemeten geval: dezelfde opname staat twee keer in één albummap, gespeld als "Workin' Day and
    // Night" en "Working Day And Night". Drie van de vier woorden gedeeld, dus onder de vier vijfde
    // die sameTitle eist -- en de plaat hield twee kopieën van één nummer.
    final ts = [
      t(r"C:\m\03 - Workin' Day and Night.flac", "Workin' Day and Night"),
      t(r'C:\m\03 - Working Day And Night.flac', 'Working Day And Night'),
    ];
    expect(paren(ts), isEmpty, reason: 'dit is precies wat de titelregel niet ziet');
  });

  test('met afdrukken wordt hij wel gevonden, hoe hij ook gespeld is', () {
    final a = reeks(400);
    final ts = [
      t(r"C:\m\03 - Workin' Day and Night.flac", "Workin' Day and Night"),
      t(r'C:\m\03 - Working Day And Night.flac', 'Working Day And Night'),
    ];
    expect(paren(ts, prints: {ts[0].path: a, ts[1].path: a}), hasLength(1));
  });

  test('de audio spreekt de titel ook TEGEN — de duetversie blijft staan', () {
    // Het gevaarlijke geval. Adele's "Easy On Me" en "Easy On Me (With Chris Stapleton)" hebben
    // bijna dezelfde titel en bijna dezelfde lengte, maar de audio scoort 0,929: dezelfde
    // begeleiding, een andere uitvoering. Zonder te luisteren was dat een verwijdering geweest.
    final a = reeks(400);
    final anders = reeks(400, zaad: 77);
    final ts = [
      t(r'C:\m\02 - Easy On Me.flac', 'Easy On Me', secs: 224),
      t(r'C:\m\15 - Easy On Me.flac', 'Easy On Me', secs: 224),
    ];
    expect(paren(ts), hasLength(1), reason: 'op titel en lengte alleen is dit een paar');
    expect(paren(ts, prints: {ts[0].path: a, ts[1].path: anders}), isEmpty,
        reason: 'de audio hoort de titel te overrulen, ook als dat een paar wegneemt');
  });

  test('één afdruk is geen bewijs — dan geldt de titelregel gewoon', () {
    final ts = [
      t(r'C:\m\a.flac', 'Rock With You'),
      t(r'C:\m\b.flac', 'Rock With You'),
    ];
    // Alleen de eerste is afgedrukt; vergelijken kan dus niet, en de titel beslist zoals voorheen.
    expect(paren(ts, prints: {ts[0].path: reeks(400)}), hasLength(1));
  });
}

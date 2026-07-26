// The line that names WHICH copy of the record is on screen.
//
// It read "Uitgave: cd · 88725453152 · Canada" after the French CD was chosen in the gallery. The pin
// was written correctly and MusicBrainz agreed the pressing was French; the panel simply never asked
// it. It built the line from whatever Discogs had matched by name — a pressing nobody chose — and
// then called it "Uitgave" rather than "Jouw uitgave", which is the app being politely honest about
// having ignored you.
import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/editions.dart';

const _cdFr = (format: 'CD', catno: '88725453152', country: 'FR', year: 2012);
const _cdCa = (format: 'CD', catno: '88725453152', country: 'Canada', year: 2012);

void main() {
  test('a pinned pressing decides every field', () {
    final line = pressingFacts(pinned: _cdFr, guessed: _cdCa, recordYear: 2012);
    expect(line, contains('FR'));
    expect(line, isNot(contains('Canada')), reason: 'the country of a pressing nobody chose');
  });

  test('without a pin the matched pressing is used', () {
    final line = pressingFacts(guessed: _cdCa, recordYear: 2012);
    expect(line, contains('Canada'));
  });

  test('a pin with gaps does not fall back field by field', () {
    // Half of MusicBrainz's French pressing and half of Discogs's Canadian one would describe a
    // record that does not exist. The pin is a whole answer or it is not the answer.
    final line = pressingFacts(
      pinned: (format: 'CD', catno: null, country: 'FR', year: 2012),
      guessed: _cdCa,
      recordYear: 2012,
    );
    expect(line, contains('FR'));
    expect(line, isNot(contains('88725453152')), reason: 'that catalogue number is Discogs\'s');
  });

  test('the pressing year is dropped when it repeats the album year', () {
    expect(pressingFacts(pinned: _cdFr, recordYear: 2012), isNot(contains('2012')));
    expect(pressingFacts(pinned: _cdFr, recordYear: 1995), contains('2012'),
        reason: 'a 2012 reissue of a 1995 record is worth saying');
  });

  test('"none" is not a catalogue number', () {
    final line = pressingFacts(pinned: (format: 'CD', catno: 'none', country: 'BE', year: null));
    expect(line, isNot(contains('none')));
    expect(line, contains('BE'));
  });

  test('empty fields are left out rather than printed blank', () {
    final line =
        pressingFacts(pinned: (format: '', catno: '  ', country: '', year: null));
    expect(line, isEmpty);
  });

  test('nothing known means no line at all', () {
    expect(pressingFacts(), isEmpty);
  });

  test('the format label is applied, and only to the format', () {
    final line = pressingFacts(
      pinned: (format: 'File', catno: 'CK 80219', country: 'CA', year: 1995),
      recordYear: 1995,
      formatLabel: (f) => f == 'File' ? 'digitaal' : f.toLowerCase(),
    );
    expect(line.first, 'digitaal', reason: '"File" reads as nothing at all to a person');
    expect(line, contains('CK 80219'));
  });

  test('the order is format, year, catalogue number, country', () {
    expect(
      pressingFacts(pinned: (format: 'cd', catno: 'CK 80219', country: 'CA', year: 2009),
          recordYear: 1995),
      ['cd', '2009', 'CK 80219', 'CA'],
    );
  });
}

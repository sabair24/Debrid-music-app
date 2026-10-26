// Titels van losse tekens (Saber, 26-10-2026, Steps — Step One: "5,6,7,8 van steps, herkend soulseek niet,
// waarschijnlijk door die nummers met comma ?? … er zijn namelijk in de muziek wereld heel veel rare titels, en
// tekens"). De app vond nul bronnen; één zoekopdracht "Steps Step One" op de pc gaf 68 treffers, waarvan 36
// verliesvrij — de bestandsnamen hieronder komen uit die meting (26-10-2026 06:40).
import 'package:debridmusic/kandidatenzeef.dart';
import 'package:debridmusic/lossless_want.dart';
import 'package:debridmusic/organize.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:flutter_test/flutter_test.dart';

SoulseekFile _f(String gebruiker, String pad, int sec) =>
    SoulseekFile(username: gebruiker, filename: pad, size: 26000000, durationSec: sec, sampleRate: 44100, bitDepth: 16);

final _gemeten = [
  _f('Myst1714', r'@@dsqfh\[05] Music\Steps\Step One\5, 6, 7, 8 - Steps.flac', 202),
  _f('pickelpounder', r'Soul1\Steps\Step One\Steps - Step One - 05 - 5, 6, 7, 8.flac', 203),
  _f('minimagical', r'Tidal\Steps - Step One (1998) [FLAC]\Step One\03. 5, 6, 7, 8.flac', 202),
  _f('Radamski', r'music-16-bit\Steps\Step One [Bonus Track]\03 - 5, 6, 7, 8.flac', 203),
  _f('huggies15', r'shared\Steps\Step One (1998)\Steps - Step One - 03 - 5, 6, 7, 8.flac', 202),
  _f('nononono', r'@@zsttx\Music\Steps\Step One\03 5, 6, 7, 8.flac', 202),
  _f('minimagical', r'Tidal\Steps - Step One (1998)\03. Steps - 5, 6, 7, 8.flac', 202),
  _f('plexmediashare', r'Music\Steps\(1998) Step One\103 - 5, 6, 7, 8.flac', 203),
  _f('DD102', r'music\Steps\Step One (1998) - 03 - 5, 6, 7, 8.flac', 203),
  _f('drfsupercenter', r'@@ovldw\WCD\Steps - Step One (1998) - CD FLAC\03. 5, 6, 7, 8.flac', 203),
  _f('mitskilover123', r'music\Steps\Step_One\3._5,_6,_7,_8.m4a', 202),
  _f('dazeruk', r'music\Steps\Step One (2000)\Steps - Step One - 05 - 5, 6, 7, 8.mp3', 203),
];

bool _past(String titel, String pad, {String artiest = 'Steps', String? album = 'Step One', int? sec}) =>
    fileOffersTitle(titel, sec, artiest, pad, sec, album: album);

void main() {
  test('DE KERN: "5, 6, 7, 8" past op de echte bestandsnamen van Soulseek', () {
    for (final f in _gemeten) {
      expect(_past('5, 6, 7, 8', f.filename), isTrue, reason: f.filename);
    }
    final zeef = zeefKandidatenNu(_gemeten, titel: '5, 6, 7, 8', seconden: 203, artiest: 'Steps', album: 'Step One');
    expect(zeef, hasLength(_gemeten.length));
  });

  test('en niet op een ander nummer, een remix of live', () {
    for (final pad in [
      r'music\Steps\Step One (1998)\02 - Last Thing on My Mind.flac',
      r'music\Steps\Step One (1998)\Steps - Step One - 04 - One for Sorrow.flac',
      r'music\Steps\Remixes\5, 6, 7, 8 (Euro Step Mix).flac',
      r'music\Steps\Live\5, 6, 7, 8 (Live).flac',
      r'music\Steps\Gold\5, 6, 7, 8 (Tropical Remix).flac',
      r'music\Steps\Step One\5, 6, 7.flac',
      r'music\Steps\Step One\8, 7, 6, 5.flac',
      r'music\Kidzone\Kidz Steps\03 - 5, 6, 7, 8 Karaoke.flac',
    ]) {
      expect(_past('5, 6, 7, 8', pad), isFalse, reason: pad);
    }
  });

  test('andere titels van losse tekens: "3", "22", "1-2-3", "U"', () {
    expect(_past('3', r'music\Britney Spears\The Singles Collection\Britney Spears - 3.flac',
        artiest: 'Britney Spears', album: 'The Singles Collection'), isTrue);
    expect(_past('3', r'music\Britney Spears\The Singles Collection\24 - 3.flac',
        artiest: 'Britney Spears', album: 'The Singles Collection'), isTrue);
    expect(_past('3', r'music\Britney Spears\Circus\3 - Womanizer.flac', artiest: 'Britney Spears', album: 'Circus'),
        isFalse, reason: 'het volgnummer is niet de titel');
    expect(_past('3', r'music\Britney Spears\Circus\03 - Circus.flac', artiest: 'Britney Spears', album: 'Circus'),
        isFalse);
    expect(_past('22', r'music\Taylor Swift\Red\06 - 22.flac', artiest: 'Taylor Swift', album: 'Red'), isTrue);
    expect(_past('22', r'music\Taylor Swift\Red\22 - Begin Again.flac', artiest: 'Taylor Swift', album: 'Red'), isFalse);
    expect(_past('1-2-3', r'music\Gloria Estefan\Let It Loose\05 - 1-2-3.flac',
        artiest: 'Gloria Estefan', album: 'Let It Loose'), isTrue);
    expect(_past('1-2-3', r'music\Gloria Estefan\Let It Loose\05 - 123.flac',
        artiest: 'Gloria Estefan', album: 'Let It Loose'), isTrue, reason: 'samen als één woord');
    expect(_past('U', r'music\Prince\Hits\Prince - U.flac', artiest: 'Prince', album: 'Hits'), isTrue);
    expect(_past('U', r'music\Prince\Hits\Prince - U Got the Look.flac', artiest: 'Prince', album: 'Hits'), isFalse);
  });

  test('gewone titels veranderen niet', () {
    expect(_past('Last Thing on My Mind', r'music\Steps\Step One (1998)\02 - Last Thing on My Mind.flac'), isTrue);
    expect(_past('Last Thing on My Mind', r'music\Steps\Step One (1998)\03 - 5, 6, 7, 8.flac'), isFalse);
    expect(_past('Tragedy', r'music\Steps\Steptacular\01 - Tragedy.flac', album: 'Steptacular'), isTrue);
  });

  test('de zoekvraag: zo\'n titel zoekt op artiest en plaat, want Soulseek negeert woorden van één teken', () {
    expect(titelZonderZoekwoord('5, 6, 7, 8'), isTrue);
    expect(titelZonderZoekwoord('3'), isTrue);
    expect(titelZonderZoekwoord('U'), isTrue);
    expect(titelZonderZoekwoord('22'), isFalse, reason: 'twee tekens vindt Soulseek wel');
    expect(titelZonderZoekwoord('Tragedy'), isFalse);
    expect(soulseekQuery('Steps', '5, 6, 7, 8', album: 'Step One'), 'steps step one');
    expect(soulseekQuery('Steps', '5, 6, 7, 8'), 'steps', reason: 'zonder plaat zoals vroeger');
    expect(soulseekQuery('Steps', 'Tragedy', album: 'Steptacular'), 'steps tragedy');
    expect(zoekvraagVoorNummer('5, 6, 7, 8', artist: 'Steps', album: 'Step One'), 'Steps Step One');
    expect(zoekvraagVoorNummer('Tragedy', artist: 'Steps', album: 'Steptacular'), 'Steps Tragedy');
    expect(const LosslessWant(artist: 'Steps', title: '5, 6, 7, 8', album: 'Step One').query, 'Steps Step One');
  });
}

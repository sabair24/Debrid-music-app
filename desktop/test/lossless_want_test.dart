/// De staande wens: FLAC is koning, en de app mag het niet opgeven.
///
/// Het gaat hier om het GEDRAG van de lijst, zonder één peer aan te spreken. Wat er misging is
/// gemeten: één jacht van tien minuten die na twintig seconden dood was omdat de enige lossless bron
/// het account geband had, en een dag later stond er wél iemand online.
library;

import 'dart:io';

import 'package:debridmusic/lossless_want.dart';
import 'package:flutter_test/flutter_test.dart';

const _uur = 3600 * 1000;

LosslessWant _w(String artist, String title, {int tries = 0, int lastTryMs = 0, int sinceMs = 0}) =>
    LosslessWant(artist: artist, title: title, tries: tries, lastTryMs: lastTryMs, sinceMs: sinceMs);

void main() {
  group('het ritme', () {
    test('de eerste poging mag meteen', () {
      expect(wachtVoor(0), Duration.zero);
      expect(wensIsAanDeBeurt(_w('a', 'b'), 1000), isTrue);
    });

    test('het wordt ruimer, want de reden beweegt langzaam', () {
      expect(wachtVoor(1), const Duration(minutes: 20));
      expect(wachtVoor(2), const Duration(hours: 2));
      expect(wachtVoor(3), const Duration(hours: 8));
    });

    test('maar het loopt niet eindeloos op — een dag blijft een dag', () {
      // "Over een maand" is hetzelfde als opgeven, en opgeven is precies wat hier niet mag.
      expect(wachtVoor(4), const Duration(days: 1));
      expect(wachtVoor(40), const Duration(days: 1));
      expect(wachtVoor(4000), const Duration(days: 1));
    });

    test('binnen het venster is hij niet aan de beurt, erna wel', () {
      final w = _w('a', 'b', tries: 1, lastTryMs: 0);
      expect(wensIsAanDeBeurt(w, const Duration(minutes: 19).inMilliseconds), isFalse);
      expect(wensIsAanDeBeurt(w, const Duration(minutes: 20).inMilliseconds), isTrue);
    });
  });

  group('de lijst', () {
    late Directory tmp;
    late LosslessWants lijst;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('wensen');
      lijst = LosslessWants('${tmp.path}${Platform.pathSeparator}lossless_wanted.json');
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    test('dezelfde wens twee keer blijft één wens, met zijn eigen ritme', () {
      expect(lijst.want(_w('Sabien Tiels', 'Trein')), isTrue);
      // Zonder dit zou elke nieuwe mp3 van hetzelfde nummer de teller terugzetten, en dan zoekt de
      // app elke twintig minuten opnieuw bij een peer die hem toch niet geeft.
      lijst.update(lijst.all.single.met(tries: 3, lastTryMs: 5 * _uur));
      expect(lijst.want(_w('sabien tiels', 'trein')), isFalse, reason: 'zelfde nummer, andere spelling');
      expect(lijst.all.single.tries, 3, reason: 'het ritme blijft staan');
    });

    test('wie het langst wacht is eerst aan de beurt', () {
      lijst.want(_w('A', 'oud', sinceMs: 1000));
      lijst.want(_w('B', 'nieuw', sinceMs: 9000));
      expect(lijst.due(10 * _uur).map((w) => w.title), ['oud', 'nieuw']);
    });

    test('een wens die nog moet wachten staat niet in de rij', () {
      lijst.want(_w('A', 'net geprobeerd', tries: 2, lastTryMs: 10 * _uur));
      expect(lijst.due(10 * _uur + 1000), isEmpty);
      expect(lijst.due(13 * _uur).length, 1);
    });

    test('een FLAC die je al hebt laat de wens vallen, ook van buiten de app', () {
      // Het echte geval: de gebruiker haalde hem met de native client binnen, in een map die naar de
      // peer heet en onder een andere albumnaam. Zonder deze controle jaagt de app eeuwig op iets wat
      // al op schijf staat.
      lijst.want(_w('Sabien Tiels', 'Trein'));
      lijst.want(_w('Rihanna', 'Loud'));
      final weg = lijst.forgetWhatWeHave((a, t) => t.toLowerCase() == 'trein');
      expect(weg, hasLength(1));
      expect(lijst.all.single.title, 'Loud');
    });

    test('overleeft een herstart, met ritme en geweigerde peers', () async {
      lijst.want(_w('Sabien Tiels', 'Trein', sinceMs: 42));
      lijst.update(lijst.all.single.met(tries: 2, lastTryMs: 7 * _uur, refused: {'DANY2905': 'banned'}));
      await lijst.save();

      final opnieuw = LosslessWants('${tmp.path}${Platform.pathSeparator}lossless_wanted.json');
      await opnieuw.load();
      final w = opnieuw.all.single;
      expect(w.title, 'Trein');
      expect(w.tries, 2);
      expect(w.sinceMs, 42);
      expect(w.refused['DANY2905'], 'banned');
    });

    test('een lege lijst laat geen bestand achter', () async {
      lijst.want(_w('A', 'B'));
      await lijst.save();
      expect(File('${tmp.path}${Platform.pathSeparator}lossless_wanted.json').existsSync(), isTrue);
      lijst.forget(lijst.all.single.key);
      await lijst.save();
      expect(File('${tmp.path}${Platform.pathSeparator}lossless_wanted.json').existsSync(), isFalse);
    });

    test('rommel op schijf betekent geen wensen, geen uitzondering', () async {
      final f = File('${tmp.path}${Platform.pathSeparator}lossless_wanted.json');
      f.writeAsStringSync('{ dit is geen lijst');
      await lijst.load();
      expect(lijst.count, 0);
    });

    test('een regel zonder artiest of titel wordt overgeslagen', () async {
      final f = File('${tmp.path}${Platform.pathSeparator}lossless_wanted.json');
      f.writeAsStringSync('[{"artist":"","title":"Trein"},{"artist":"A","title":"B"}]');
      await lijst.load();
      expect(lijst.count, 1, reason: 'zonder naam valt er niets te zoeken');
    });

    test('de zoekvraag is wat de gebruiker zelf zou typen', () {
      expect(_w('Sabien Tiels', 'Trein').query, 'Sabien Tiels Trein');
    });
  });
}

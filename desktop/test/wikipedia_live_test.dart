/// De hele weg naar een echt artikel, één keer, tegen de echte Wikipedia.
///
/// **Draait NIET mee in CI.** Hij staat niet in de lijst in `build-release.yml` en hij is getagd
/// `live`, dus een gewone `flutter test` slaat hem over. Draai hem met de hand:
///
///     flutter test test/wikipedia_live_test.dart
///
/// `wikipedia_afdelingen_test.dart` bewaakt het knipwerk zonder netwerk. Wat DEZE toets erbij doet
/// is het enige wat een ontleder nooit kan zeggen: dat de vorm die eruit komt ook de vorm is die de
/// bron werkelijk stuurt — de veldnamen, de titelweg over Wikidata, en of het artikel dat we
/// terugkrijgen bij de artiest hoort die we bedoelden.
///
/// Slaat zichzelf over als Wikimedia zwijgt: een rood dat "de bron was even niet bereikbaar"
/// betekent zegt niets over deze weg. Dezelfde afspraak als bij `metadata_test.dart` en
/// `artiestbeeld_accenten_test.dart`.
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/musicbrainz.dart';
import 'package:debridmusic/paths.dart';
import 'package:debridmusic/wikipedia.dart';

void main() {
  setUpAll(() {
    // Nooit in de echte appmap schrijven: daar staan maanden aan eigen caches.
    setAppDirForTest(Directory.systemTemp.createTempSync('wiki_live').path);
  });

  test('Michael Jackson: van MBID naar Wikidata naar het Nederlandse artikel', () async {
    const mbid = 'f27ec8db-af05-4f36-916e-3d57f91ecf5e';

    final q = await MusicBrainzService().wikidataId(mbid);
    if (q == null) {
      markTestSkipped('MusicBrainz antwoordde niet — niet nagekeken, geen defect');
      return;
    }
    expect(q, 'Q2831', reason: 'de weg naar het artikel loopt over dit nummer, niet over de naam');

    final a = await WikipediaService().artikel('Michael Jackson', mbid: mbid);
    if (a == null) {
      markTestSkipped('Wikipedia antwoordde niet — niet nagekeken, geen defect');
      return;
    }

    expect(a.taal, 'nl', reason: 'Nederlands gaat voor, en dat artikel bestaat');
    expect(a.titel, 'Michael Jackson');
    expect(a.intro, contains('Jackson'),
        reason: 'de inleiding is wat er ingeklapt te zien is; die mag niet leeg zijn');

    // GEMETEN op 10-09-2026: 27.847 tekens tegen 2.357 uit TheAudioDB. Ruim onder de helft zou
    // betekenen dat we het verkeerde veld lezen of dat het uittreksel afgekapt binnenkomt.
    final totaal = a.intro.length + a.afdelingen.fold<int>(0, (s, x) => s + x.tekst.length);
    expect(totaal, greaterThan(10000),
        reason: 'we lezen een afgekapt uittreksel in plaats van het hele artikel');

    expect(a.afdelingen.length, greaterThan(3),
        reason: 'zonder secties wordt het uitklapvenster één muur van negen A4\'tjes');
    for (final s in a.afdelingen) {
      expect(s.tekst.trim(), isNotEmpty,
          reason: '"${s.kop}" klapt open naar niets — dat leest als een storing');
      expect(s.kop, isNot(contains('=')), reason: 'opmaak lekt naar het scherm');
    }

    // ignore: avoid_print
    print('nl/${a.titel}: $totaal tekens, ${a.afdelingen.length} secties '
        '(${a.afdelingen.take(6).map((s) => s.kop).join(' · ')})');
    // ignore: avoid_print
    print('beeld: ${a.beeldBreedte}x${a.beeldHoogte} ${a.beeldUrl}');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('een act zonder artikel levert null, niet een artikel van iemand anders', () async {
    // De naamtucht: alleen een titel aannemen die na normKey gelijk is aan de naam. Zonder die
    // regel wordt een verzonnen naam het best scorende artikel dat toevallig een woord deelt.
    final a = await WikipediaService().artikel('Qxzv Nietbestaandeband 4471');
    expect(a, isNull, reason: 'een willekeurig artikel onder de naam van je artiest is erger dan geen');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

// Een echte cd-kopie mag een verdacht bestand vervangen als zij bewijst dat het afgekapt is.
//
// Saber, 21-10-2026, over Snoop Dogg — Beautiful (24/48, muur op 20,0 kHz, "niet zeker"): "Zoek hi-res" vond
// "geen betere kopie", want een echte 16/44,1 is op papier lager en hoogstens gelijk in de keuring. Gevraagd
// of een kopie die voorbij die muur doorloopt als bewijs telt: "Ja, dat telt als bewijs."
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/keuring.dart';
import 'package:debridmusic/models.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/soulseek.dart';

Echtheidsoordeel _o(Bandbreedte band, double? afkap) =>
    Echtheidsoordeel(bits: Bitdiepte.onbekend, boven: Bovenband.onbekend, band: band, afkapHz: afkap);

void main() {
  // Zoals gemeten op de pc: de 24/48 van Snoop Dogg en de 16/44,1 radio-edit van Pharrell.
  final snoop = _o(Bandbreedte.vermoedelijk, 20000);
  final echt = _o(Bandbreedte.doorlopend, 21200);
  final cd48 = kwaliteitUit(verliesvrij: true, kopRate: 48000, formaat: 4, oordeel: snoop);
  final cd44 = kwaliteitUit(verliesvrij: true, kopRate: 44100, formaat: 4, oordeel: echt);

  group('metMuurBewijs', () {
    test('zonder bewijs gelijk: wat er stond blijft staan', () {
      expect(cd48.klasse, Klasse.cd);
      expect(vergelijkKwaliteit(cd44, cd48), 0);
    });

    test('loopt de andere kopie voorbij de muur door, dan is de verdachte afgekapt', () {
      final oud = metMuurBewijs(cd48, snoop, echt);
      expect(oud.klasse, Klasse.uitLossy);
      expect(vergelijkKwaliteit(metMuurBewijs(cd44, echt, snoop), oud), greaterThan(0),
          reason: 'de echte cd-kopie wint');
    });

    test('net boven de muur is geen bewijs; een andere verdachte ook niet', () {
      expect(metMuurBewijs(cd48, snoop, _o(Bandbreedte.doorlopend, 20300)).klasse, Klasse.cd,
          reason: 'minder dan kMuurBewijsHz erboven');
      expect(metMuurBewijs(cd48, snoop, _o(Bandbreedte.vermoedelijk, 21500)).klasse, Klasse.cd);
      expect(metMuurBewijs(cd48, snoop, null).klasse, Klasse.cd);
    });

    test('een echt bestand verliest nooit door een andere kopie', () {
      expect(metMuurBewijs(cd44, echt, _o(Bandbreedte.doorlopend, 22000)).klasse, Klasse.cd);
      final hires = kwaliteitUit(
          verliesvrij: true,
          kopRate: 96000,
          formaat: 4,
          oordeel: const Echtheidsoordeel(bits: Bitdiepte.onbekend, boven: Bovenband.vol, band: Bandbreedte.vermoedelijk, afkapHz: 20000));
      expect(metMuurBewijs(hires, snoop, echt).klasse, Klasse.hires,
          reason: 'bewezen muziek boven 22 kHz telt zwaarder');
    });
  });

  group('beterDanWatErLigt bij een verdacht bestand', () {
    final mijn = Track(
        path: r'D:\Muziek\Snoop Dogg\Paid Tha Cost To Be Da Bo$$\08 - Beautiful.flac',
        title: 'Beautiful',
        artist: 'Snoop Dogg',
        album: 'Paid Tha Cost To Be Da Bo\$\$',
        trackNo: 8,
        duration: const Duration(seconds: 298),
        isFlac: true,
        sizeBytes: 65910311,
        sampleRate: 48000,
        bitsPerSample: 24);
    SoulseekFile kopie(String peer, {int sec = 298}) => SoulseekFile(
        username: peer,
        filename: 'Muziek\\Snoop Dogg - Paid Tha Cost To Be Da Bo\$\$\\08 - Beautiful.flac',
        size: 35000000,
        freeSlots: true,
        speed: 2000000,
        durationSec: sec,
        sampleRate: 44100,
        bitDepth: 16);

    test('gewoon: een cd-kopie is op papier niet beter dan een 24/48', () {
      expect(DownloadManager.beterDanWatErLigt(mijn, [kopie('a')]), isEmpty);
    });

    test('verdacht: ook echte cd-kopieën, maar alleen van dezelfde lengte en hoogstens zes', () {
      final hits = [for (var i = 0; i < 9; i++) kopie('p$i'), kopie('lang', sec: 330)];
      final beter = DownloadManager.beterDanWatErLigt(mijn, hits, verdacht: true);
      expect(beter, hasLength(DownloadManager.kVerdachtKandidaten));
      expect(beter.map((k) => k.username), isNot(contains('lang')));
    });
  });
}

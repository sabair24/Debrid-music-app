/// De fotokiezer moet weten wélke vorm een foto heeft, en dat wist hij niet.
///
/// **Waarom dit bestaat.** Het venster "Foto kiezen" toonde elke foto als een VIERKANT: één raster
/// op `childAspectRatio: .82`, en elke tegel door `_netCover`, dat `width`, `height` en
/// `BoxFit.cover` vastlegt. Je koos dus blind — of een foto liggend of staand was bleek pas als hij
/// op de pagina stond.
///
/// Daaronder zat een tweede, ergere fout. De twee TheAudioDB-urls die de kiezer aan de lijst
/// toevoegde werden gebouwd als `DiscogsImage(url, url, 0, 0, false)` — breedte en hoogte op NUL.
/// `DiscogsImage.isWide` doet `height > 0 && width / height > 1.4`, dus die zei bij álle
/// TheAudioDB-beelden nee, ook bij de fanart van 1280×720. Dat is precies het beeld dat als
/// achtergrond hoort te dienen, en het kwam bij de staande terecht.
///
/// Beide zeven zijn puur, dus ze horen hier. En juist omdat ze puur zijn kan er stil een verkeerd
/// getal in blijven zitten: niets wordt rood, je ziet alleen een venster met foto's in het
/// verkeerde vak.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/discogs.dart';
import 'package:debridmusic/enrichment.dart';

DiscogsImage foto(int w, int h, {bool primair = false, String naam = ''}) =>
    DiscogsImage('https://ergens/$naam${w}x$h.jpg', 'https://ergens/thumb.jpg', w, h, primair);

void main() {
  group('de nominale maat van een TheAudioDB-veld', () {
    test('DE VAL: een fanart levert een vorm waarvoor isWide WAAR is', () {
      // Dit is de regressiewacht op de 0x0-fout. Zonder deze maat kwam de fanart -- het breedste
      // beeld dat een van beide bronnen heeft -- in het vak STAAND terecht.
      final m = CoverEnricher.audioDbNominaal('backdrop');
      expect(foto(m.breedte, m.hoogte).isWide, isTrue,
          reason: 'de fanart van deze artiest belandt bij de staande foto\'s');
      expect(m.breedte / m.hoogte, closeTo(16 / 9, .01),
          reason: 'de fanart is 16:9 en hoort dus vooraan in het liggende vak te sorteren');
    });

    test('DE KERN: elke soort krijgt de vorm die erbij hoort', () {
      bool liggend(String soort) {
        final m = CoverEnricher.audioDbNominaal(soort);
        return foto(m.breedte, m.hoogte).isWide;
      }

      expect(liggend('backdrop'), isTrue);
      expect(liggend('clearart'), isTrue, reason: 'clearart is 1000x562, dezelfde gedachte liggend');
      expect(liggend('logo'), isTrue, reason: 'een woordmerk is breder dan hoog');
      expect(liggend('thumb'), isFalse, reason: 'het portret is vierkant en hoort bij staand');
      expect(liggend('cutout'), isFalse);
    });

    test('DE GRENS: een onbekende soort verzint geen maat', () {
      final m = CoverEnricher.audioDbNominaal('ietsnieuws');
      expect(m.breedte, 0);
      expect(m.hoogte, 0);
    });
  });

  group('splitsen op vorm', () {
    test('DE KERN: liggend en staand komen in hun eigen vak', () {
      final r = splitsOpVorm([foto(1280, 720), foto(1000, 1000), foto(1725, 2096)]);
      expect(r.liggend.length, 1);
      expect(r.staand.length, 2);
    });

    test('DE VAL: een banner is liggend, maar sorteert ACHTERAAN', () {
      // Een banner van 1000x185 is verhouding 5,4 -- hij haalt elke "is dit breed"-poort, en op
      // breedte gesorteerd zou hij vooraan staan. Als achtergrond is hij onbruikbaar: hij vult een
      // vak van 16:9 alleen door tachtig procent weg te snijden.
      final r = splitsOpVorm([foto(1000, 185, naam: 'banner'), foto(1280, 720, naam: 'fanart')]);
      expect(r.liggend.length, 2);
      expect(r.liggend.first.uri, contains('fanart'),
          reason: 'de banner staat vooraan en dat is de eerste foto die je aanklikt');
      expect(r.liggend.last.uri, contains('banner'));
    });

    test('DE GRENS: 4:3 en een regel zonder afmetingen vallen naar de VEILIGE kant', () {
      // 1,33 is noch squarish noch wide. In een staand vak is dat een nette uitsnede; in een band
      // van 2,5:1 is het dat niet -- dus staand.
      final r = splitsOpVorm([foto(1000, 750), foto(800, 0)]);
      expect(r.liggend, isEmpty);
      expect(r.staand.length, 2,
          reason: 'een foto zonder afmetingen hoort niet als achtergrond voorgesteld te worden');
    });

    test('DE VAL: bij staand blijft primary vooraan', () {
      // Daar zegt Discogs zelf iets over, en dat is meer dan een vormgok.
      final r = splitsOpVorm([
        foto(1000, 1000, naam: 'gewoon'),
        foto(900, 1200, primair: true, naam: 'primair'),
      ]);
      expect(r.staand.first.uri, contains('primair'));
    });

    test('DE GRENS: een lege lijst geeft twee lege vakken, geen uitzondering', () {
      final r = splitsOpVorm([]);
      expect(r.liggend, isEmpty);
      expect(r.staand, isEmpty);
    });
  });
}

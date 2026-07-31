import 'package:flutter_test/flutter_test.dart';
import 'package:debridmusic/quality.dart';

void main() {
  test('torrent name → quality/tier', () {
    expect(qualityFromName('Michael Jackson - Thriller [FLAC]').tier, QTier.lossless);
    final hires = qualityFromName('MJ - Thriller (24bit-96kHz) FLAC');
    expect(hires.tier, QTier.hires);
    print('hires label = ${hires.label}');
    expect(qualityFromName('MJ - Thriller [SACD-R] DSD').tier, QTier.hires);
    final mp3 = qualityFromName('MJ - Thriller Mp3 320kbps');
    expect(mp3.tier, QTier.lossy);
    print('mp3 label = ${mp3.label}');
    expect(qualityFromName('MJ - Thriller (Remastered) 1982').tier, QTier.unknown);
    print('24/192 label = ${qualityFromName('Thriller 24-192 FLAC').label}');
  });

  test('Soulseek file → quality (effective bitrate)', () {
    // 16-bit FLAC: ~10MB, 60s → ~1333 kbps → lossless
    final cd = qualityFromFile(name: 'x.flac', ext: 'flac', isFlac: true, durationSec: 60, size: 10 * 1000 * 1000);
    print('cd flac = ${cd.label} ${cd.tier}');
    expect(cd.lossless, true);
    // 24-bit FLAC: ~30MB, 60s → ~4000 kbps → hires
    final hr = qualityFromFile(name: 'x.flac', ext: 'flac', isFlac: true, durationSec: 60, size: 30 * 1000 * 1000);
    expect(hr.tier, QTier.hires);
    print('hires flac = ${hr.label}');
    final mp3 = qualityFromFile(name: 'x.mp3', ext: 'mp3', isFlac: false, bitrate: 320);
    expect(mp3.tier, QTier.lossy);
    print('mp3 = ${mp3.label}');
  });

  test('filters match the right tiers', () {
    final flac = qualityFromName('album FLAC');
    final mp3 = qualityFromName('album MP3 320');
    final hires = qualityFromName('album FLAC 24/96');
    expect(QFilter.lossless.matches(flac), true);
    expect(QFilter.lossless.matches(mp3), false);
    expect(QFilter.hires.matches(flac), false);
    expect(QFilter.hires.matches(hires), true);
    expect(QFilter.mp3.matches(mp3), true);
    expect(QFilter.all.matches(mp3), true);
  });

  /// Waarom dit bestaat: het Hi-Res-filter in de bibliotheek meldde "niets binnen dit filter" terwijl
  /// er 102 van die nummers stonden — en in dezelfde lijst gouden badges. Het filter raadde uit de titel
  /// en de duur, en een titel zegt zelden "24bit/96kHz".
  group('hi-res van een bestand dat hier staat', () {
    test('boven 48 kHz is hi-res, ongeacht hoe het nummer heet', () {
      expect(isHiRes(sampleRate: 96000, bitsPerSample: 24), isTrue);
      expect(isHiRes(sampleRate: 88200, bitsPerSample: 24), isTrue);
      expect(isHiRes(sampleRate: 192000, bitsPerSample: 24), isTrue);
      expect(isHiRes(sampleRate: 176400, bitsPerSample: 24), isTrue);
    });

    test('cd-kwaliteit is dat niet, ook niet als het nummer druk gemasterd is', () {
      // De oude weg keek naar de bitrate, en een luid gemasterde 44,1/16 haalt ook boven de 1500 kbit/s.
      expect(isHiRes(sampleRate: 44100, bitsPerSample: 16), isFalse);
      expect(isHiRes(sampleRate: 48000, bitsPerSample: 16), isFalse);
    });

    test('24 bit op 48 kHz telt ook mee', () {
      expect(isHiRes(sampleRate: 48000, bitsPerSample: 24), isTrue);
    });

    test('niets bekend is geen hi-res', () {
      expect(isHiRes(sampleRate: 0, bitsPerSample: 0), isFalse);
    });

    test('het etiket schrijft de rate zoals hij op de hoes staat', () {
      expect(depthRateLabel(sampleRate: 96000, bitsPerSample: 24), '24/96');
      expect(depthRateLabel(sampleRate: 192000, bitsPerSample: 24), '24/192');
      // 88,2 en 176,4 zijn geen 88 en 176: dat zijn de veelvouden van de cd-rate en die decimaal is
      // precies waaraan je ze herkent.
      expect(depthRateLabel(sampleRate: 88200, bitsPerSample: 24), '24/88.2');
      expect(depthRateLabel(sampleRate: 176400, bitsPerSample: 24), '24/176.4');
      expect(depthRateLabel(sampleRate: 44100, bitsPerSample: 24), '24/44.1');
    });

    test('cd-kwaliteit krijgt hetzelfde etiket, want één notatie leest als één lijst', () {
      expect(depthRateLabel(sampleRate: 44100, bitsPerSample: 16), '16/44.1');
      expect(depthRateLabel(sampleRate: 48000, bitsPerSample: 16), '16/48');
    });
  });

  /// De zoekresultaten van Soulseek stonden in de volgorde waarin de peers toevallig antwoordden. Een
  /// bestand van 212 MB kon daardoor onder een van 30 MB staan, en dan zie je niet dat er iets tussen
  /// zit dat veel beter is dan wat je al hebt.
  group('het beste bestand bovenaan', () {
    test('een peer die de bitrate niet meldt, wordt op grootte en duur gerekend', () {
      // Soulseek-peers laten dit geregeld weg. Zonder deze omweg viel zo'n bestand op nul terug en
      // belandde het onderaan — juist de FLAC's waar het om gaat.
      expect(effectieveBitrate(bitrate: 320), 320);
      // 212 MB over 4:20 — de orde van grootte van de 6511k die op het scherm stond.
      expect(effectieveBitrate(durationSec: 260, size: 212 * 1024 * 1024), 6840);
      expect(effectieveBitrate(), 0, reason: 'niets bekend is niet nul-als-getal maar onbekend');
    });

    test('geen enkele mp3 haalt een FLAC in', () {
      // Een 320k mp3 hoort onder een 900k FLAC te staan en niet erboven; daarom een eigen laag in
      // plaats van één doorlopende schaal.
      expect(kwaliteitsRang(lossless: true, kbps: 900),
          greaterThan(kwaliteitsRang(lossless: false, kbps: 320)));
    });

    test('binnen lossless wint de hoogste bitrate — 24/192 boven 24/96', () {
      // Precies het geval uit de bibliotheek: 6511k (24/192) tegen 2900k (24/96).
      expect(kwaliteitsRang(lossless: true, kbps: 6511),
          greaterThan(kwaliteitsRang(lossless: true, kbps: 2900)));
    });

    test('surround zakt onder ELK stereobestand, hoe groot hij ook is', () {
      // DE test. Een 5.1-bestand is groot omdat het zes kanalen draagt, niet omdat het beter klinkt —
      // op een stereo-installatie wordt het teruggemengd. Op bitrate alleen sorteren zet het dus precies
      // verkeerd om: hoe onbruikbaarder, hoe hoger.
      final surroundFlac = kwaliteitsRang(lossless: true, kbps: 8638, stereo: false);
      expect(surroundFlac, lessThan(kwaliteitsRang(lossless: true, kbps: 900)));
      expect(surroundFlac, lessThan(kwaliteitsRang(lossless: false, kbps: 128)),
          reason: 'zelfs een magere mp3 in stereo is bruikbaarder dan een 5.1-mix');
    });

    test('meer dan twee kanalen is te BEWIJZEN, niet te raden', () {
      // Een FLAC is nooit groter dan onbewerkt. Onbewerkt stereo op 24/96 is 4608 kbit/s, dus een
      // bestand dat 24/96 meldt en 10958 meet kan onmogelijk stereo zijn. Dit stond bovenaan de
      // zoekresultaten, zonder "5.1" in de naam.
      expect(meerDanStereo(sampleRate: 96000, bitDepth: 24, kbps: 10958), isTrue);
      // En een echte 24/96 stereo zit er ruim onder: comprimeren maakt kleiner.
      expect(meerDanStereo(sampleRate: 96000, bitDepth: 24, kbps: 3182), isFalse);
      // 24/192 stereo mag tot 9216 gaan — precies het gebied waar de oude vaste grens van 6500 echte
      // stereobestanden ten onrechte wegdrukte.
      expect(meerDanStereo(sampleRate: 192000, bitDepth: 24, kbps: 6511), isFalse);
      // En andersom: een 5.1 op cd-kwaliteit zit ónder die 6500 en glipte er dus doorheen.
      expect(meerDanStereo(sampleRate: 44100, bitDepth: 16, kbps: 2600), isTrue);
    });

    test('zonder de getallen valt er niets te bewijzen', () {
      // Dan blijft de naamherkenning over; hier hoort geen gok uit te komen.
      expect(meerDanStereo(sampleRate: null, bitDepth: null, kbps: 10958), isFalse);
      expect(meerDanStereo(sampleRate: 96000, bitDepth: 24, kbps: 0), isFalse);
    });

    test('een gemeld formaat en een gemeten bitrate horen op DEZELFDE schaal', () {
      // De fout die hieronder zat: 24/192 werd op ruwe capaciteit afgerekend (4608) en een bestand
      // zonder gemeld formaat op wat het INGEPAKT gebruikt. Dat scheelt een derde, en dus won elk
      // onbekend bestand van zijn eigen gelijke.
      expect(capaciteitOpEenSchaal(sampleRate: 192000, bitDepth: 24, kbps: 5430, lossless: true), 4608,
          reason: 'meldt de peer het formaat, dan telt dat en niet de gemeten bitrate');
      // Dezelfde 16/44.1, één keer gemeld en één keer gemeten: die horen nu naast elkaar te liggen.
      final gemeld = capaciteitOpEenSchaal(sampleRate: 44100, bitDepth: 16, kbps: 900, lossless: true);
      final gemeten = capaciteitOpEenSchaal(kbps: 900, lossless: true);
      expect((gemeld - gemeten).abs(), lessThan(60),
          reason: 'stelselmatig 900 tegen 705 was juist het probleem');
    });

    test('een onbekende cd-rip verslaat geen gemelde 24/96 meer', () {
      // Het geval uit de zoekresultaten: een FLAC waarvan de peer niets meldt en die 3195 kbit/s meet,
      // is een 24/96 — en hoort dus NIET boven een gemelde 24/192 te staan.
      final onbekend = capaciteitOpEenSchaal(kbps: 3195, lossless: true);
      expect(onbekend, lessThan(capaciteitOpEenSchaal(sampleRate: 192000, bitDepth: 24, kbps: 0, lossless: true)));
      expect(onbekend, greaterThan(capaciteitOpEenSchaal(sampleRate: 44100, bitDepth: 16, kbps: 0, lossless: true)));
    });

    test('bij lossy blijft de bitrate zelf staan', () {
      // Ruwe capaciteit zegt niets over een mp3; daar IS de bitrate het getal dat telt.
      expect(capaciteitOpEenSchaal(kbps: 320, lossless: false), 320);
      expect(capaciteitOpEenSchaal(kbps: 0, lossless: true), 0, reason: 'onbekend blijft onbekend');
    });

    test('binnen surround geldt dezelfde rangorde', () {
      // Blijft er niets anders over, dan wil je nog steeds de beste van de slechte groep bovenaan.
      expect(kwaliteitsRang(lossless: true, kbps: 8638, stereo: false),
          greaterThan(kwaliteitsRang(lossless: false, kbps: 320, stereo: false)));
    });
  });
}

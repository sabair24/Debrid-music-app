// De volle echtheidsmeting (20-10-2026): het oordeel op spectra zoals de meter ze opbouwt, met de vormen die
// op de ijkset gemeten zijn. Saber: "ik wil dit met 100 procent zekerheid weten … eerlijkheid".
//
// De meting zelf op echte bestanden staat in echtheid_vol_live_test.dart (alleen op de pc).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/keuring.dart';
import 'package:flutter_test/flutter_test.dart';

/// Een spectrum in banden van 50 Hz: [niveau] dB tot [tot] Hz (met [helling] dB per kHz erboven op
/// gerekend vanaf 5 kHz), daarboven [vloer]. [lek] legt tussen [tot] en [lekTot] een tussenniveau.
Spectrumstaat staat({
  required double tot,
  int sr = 44100,
  double niveau = -20,
  double vloer = -130,
  double helling = 0,
  double? lek,
  double lekTot = 0,
  double? afloop,
  int luid = 400,
}) {
  final n = (sr / 2 / 50).floor();
  final b = Float64List(n);
  for (var k = 0; k < n; k++) {
    final hz = k * 50.0;
    final boven = niveau - helling * math.max(0, tot - 5000) / 1000;
    b[k] = hz <= tot
        ? niveau - helling * math.max(0, hz - 5000) / 1000
        : afloop != null
            ? math.max(vloer, boven - afloop * (hz - tot) / 1000)
            : (lek != null && hz <= lekTot ? lek : vloer);
  }
  return Spectrumstaat(sampleRate: sr, bandHz: 50, gemiddeld: b, p95: b, luid: luid);
}

Echtheidsoordeel oordeelVan(Spectrumstaat s, {int bits = 16, int gebruikt = 16, Integriteit i = Integriteit.klopt}) =>
    oordeelVol(s: s, kopSampleRate: s.sampleRate, kopBits: bits, gebruikteBits: gebruikt, nietNulSamples: 5000000, integriteit: i);

void main() {
  group('lossy-oorsprong: de muur', () {
    test('DE KERN: een muur op 16,8 kHz (mp3 128) is bewezen afgekapt', () {
      final o = oordeelVan(staat(tot: 16800));
      expect(o.band, Bandbreedte.afgekapt);
      expect(o.isNep, isTrue);
      expect(waarom(o), contains('mp3 128'));
    });

    test('een muur op 20,2 kHz (mp3 320 of Opus) is vermoedelijk, geen nep', () {
      final o = oordeelVan(staat(tot: 20200));
      expect(o.band, Bandbreedte.vermoedelijk);
      expect(o.isNep, isFalse, reason: 'een 20 kHz-filter in de master ziet er zo uit');
      expect(echteResolutie(o, kopSampleRate: 44100, kopBits: 16), endsWith('kHz?'));
    });

    test('DE GRENS: de echte bronnen van de ijkset hadden een val van hooguit 13 dB', () {
      // Een natuurlijke roll-off naar Nyquist, zoals "Freak Out ('97 Remix)".
      final o = oordeelVan(staat(tot: 21900, helling: 1.5));
      expect(o.band, Bandbreedte.doorlopend);
      expect(o.isNep, isFalse);
      expect(o.isVermoedelijk, isFalse);
    });

    test('DE GRENS: een zachte val van 20 dB is geen muur', () {
      final o = oordeelVan(staat(tot: 18000, vloer: -40));
      expect(o.band, Bandbreedte.doorlopend);
    });

    test('DE GRENS: een steile maar geleidelijke afloop (18 dB/kHz) is geen muur', () {
      // De val over de afkap is dan ~21 dB: boven wat de echte bronnen haalden (13), onder wat elke mp3
      // haalde (23 en meer). Precies de ruimte waar [volMuurDb] = 25 voor staat.
      final o = oordeelVan(staat(tot: 16000, afloop: 18, vloer: -130));
      expect(o.wandDb, inInclusiveRange(15, 24.9));
      expect(o.band, Bandbreedte.doorlopend);
    });

    test('te weinig luide vensters: geen uitspraak over de band', () {
      expect(oordeelVan(staat(tot: 16800, luid: 20)).band, Bandbreedte.onbekend);
    });
  });

  group('opgeschaald', () {
    test('DE KERN: 96 kHz met boven 24,5 kHz digitale stilte (soxr) is opgeschaald', () {
      final o = oordeelVan(staat(tot: 21500, sr: 96000, vloer: -140), bits: 24, gebruikt: 24);
      expect(o.boven, Bovenband.leeg);
      expect(o.isNep, isTrue);
      expect(o.ultraDb, lessThan(-90));
    });

    test('96 kHz met een muur op 22 kHz en wat lek tot 25 kHz (ffmpeg) is opgeschaald', () {
      final o = oordeelVan(staat(tot: 21500, sr: 96000, lek: -75, lekTot: 24800, vloer: -100), bits: 24, gebruikt: 24);
      expect(o.boven, Bovenband.leeg);
    });

    test('DE GRENS: een echte 96 kHz met inhoud die tot 34 kHz uitloopt is ECHT', () {
      // A-ha "Take On Me (MTV Unplugged)": de oude meting noemde dit opgeschaald (89 zulke bestanden).
      final o = oordeelVan(staat(tot: 34000, sr: 96000, helling: 2.2, vloer: -120), bits: 24, gebruikt: 24);
      expect(o.boven, Bovenband.vol);
      expect(o.isNep, isFalse);
    });

    test('DE GRENS: een ultrasone vloer rond -75 dB zonder muur is echt, niet opgeschaald', () {
      // Het grijze gebied (-60 tot -90): in de bibliotheek zaten daar ~40 hi-res bestanden. Zonder een
      // muur van 15 dB is alleen "vrijwel digitale stilte" (-90) bewijs.
      final o = oordeelVan(staat(tot: 20000, sr: 96000, afloop: 12.5, vloer: -95), bits: 24, gebruikt: 24);
      expect(o.ultraDb, inInclusiveRange(-89, -61));
      expect(o.boven, Bovenband.vol);
    });

    test('DE GRENS: weinig ultrasone inhoud, maar zonder muur, is geen bewijs', () {
      // -70 dB boven 24,5 kHz en geleidelijk: zo zag een groot deel van de echte hi-res eruit.
      final o = oordeelVan(staat(tot: 40000, sr: 96000, helling: 1.6, vloer: -120), bits: 24, gebruikt: 24);
      expect(o.ultraDb, greaterThan(-90));
      expect(o.boven, Bovenband.vol);
    });
  });

  group('de bits en de controlesom', () {
    test('24 bit in de kop met 16 gebruikt over ALLE samples: opgeblazen', () {
      final o = oordeelVan(staat(tot: 21900, helling: 1.5), bits: 24, gebruikt: 16);
      expect(o.bits, Bitdiepte.opgeblazen);
      expect(o.isNep, isTrue);
    });

    test('DE KERN: een foute controlesom is kapot, en dat zegt ook de keuring', () {
      final o = oordeelVan(staat(tot: 21900, helling: 1.5), i: Integriteit.fout);
      expect(o.isKapot, isTrue);
      expect(waarom(o), startsWith('beschadigd'));
      expect(kwaliteitUit(verliesvrij: true, kopRate: 44100, formaat: 5, oordeel: o).klasse, Klasse.kapot);
    });

    test('een kloppende controlesom is gewoon in orde', () {
      final o = oordeelVan(staat(tot: 21900, helling: 1.5));
      expect(o.isKapot, isFalse);
      expect(kwaliteitUit(verliesvrij: true, kopRate: 44100, formaat: 5, oordeel: o).klasse, Klasse.cd);
    });
  });

  group('bewaren', () {
    test('heen en terug, met de controlesom en de ultrasone maat', () {
      final o = oordeelVan(staat(tot: 21500, sr: 96000, vloer: -140), bits: 24, gebruikt: 24, i: Integriteit.fout);
      final terug = Echtheidsoordeel.fromJson(o.toJson())!;
      expect(terug.integriteit, Integriteit.fout);
      expect(terug.boven, Bovenband.leeg);
      expect(terug.ultraDb, closeTo(o.ultraDb!, 0.001));
    });

    test('DE KERN: een oordeel van de oude meting wordt niet geloofd', () {
      final oud = {'bits': 'onbekend', 'boven': 'leeg', 'band': 'onbekend', 'vensters': 32};
      expect(Echtheidsoordeel.fromJson(oud), isNull, reason: 'dan meet de veger hem opnieuw');
      expect(Echtheidsoordeel.fromJson({...oud, 'v': echtheidsVersie}), isNotNull);
    });
  });

  group('aansluiting', () {
    String bron(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

    test('de pc start de veger, en wissen of verplaatsen laat hem los', () {
      final main = bron('lib/main.dart');
      expect(main, contains('final echtVeger = EchtheidVeger(library: library, enabled: mode.owner, bezigElders: () => veger.bezig);'));
      expect(main, contains('await echtVeger.laatLos(paden);'));
      expect(main, contains('library.laatLos = laatAllesLos;'));
      expect(main, contains('voorVerplaatsen = laatAllesLos;'));
      expect(main, contains('unawaited(echtVeger.start()'));
    });

    test('de meter meet het hele bestand, in een isolate, met de MD5', () {
      final m = bron('lib/echtheid_meter.dart');
      expect(m, contains('await Isolate.spawn('));
      expect(m, contains('md5.startChunkedConversion('));
      expect(m, isNot(contains("'-ss'")), reason: 'geen grepen meer: van begin tot eind');
    });

    test('een beschadigd bestand komt vooraan in de jacht, een vermoedelijk niet', () {
      final lib = bron('lib/library.dart');
      expect(lib, contains('if (o == null || !(o.isNep || o.isKapot) || isVasteKeuze(t.path)) continue;'));
      expect(lib, contains('o.band == Bandbreedte.afgekapt || o.band == Bandbreedte.vermoedelijk'),
          reason: 'vermoedelijk staat wel op het Kwaliteit-scherm, om zelf te kiezen');
    });
  });
}

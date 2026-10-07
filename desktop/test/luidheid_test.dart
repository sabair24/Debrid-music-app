/// Gelijk volume — de rekensom, zonder speler, schijf of netwerk.
///
/// **Waarom dit bestaat.** Saber op 07-10-2026: *"hoe we het volume over alle liedjes gelijk kunnen
/// krijgen, maar dit zonder enige verlies van kwaliteit en ook dat de liedjes zeker niet te still
/// worden."* Gemeten: 8,8 dB spreiding tussen het 10e en 90e percentiel van zijn bibliotheek, en 82 van
/// 149 nummers met een ware piek boven 0 dBTP. Wat hier vastligt is precies het stuk waar een fout niet
/// omvalt maar stil verkeerd klinkt: een nummer dat afknipt, of een zacht nummer dat nóg zachter wordt.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/luidheid.dart';

Luidheidsmeting m(double i, double p) => Luidheidsmeting(lufs: i, piek: p);

void main() {
  group('één nummer', () {
    test('DE KERN: een luid nummer gaat zachter', () {
      final g = versterking(m(-8.7, -1.0), -14);
      expect(g.db, closeTo(-5.3, 1e-9));
      expect(g.bron, Bijstelbron.nummer);
    });

    test('DE KERN: een zacht nummer gaat omhoog tot −1 dBTP en niet verder', () {
      final g = versterking(m(-17.9, -3.5), -14);
      expect(g.db, closeTo(2.5, 1e-9), reason: 'de piek mag op hooguit −1 dBTP eindigen');
    });

    test('DE GRENS: een zacht nummer zonder ruimte blijft zoals het is', () {
      final g = versterking(m(-15, 0.2), -14);
      expect(g.db, 0, reason: 'een zacht nummer nog zachter maken is precies "te stil"');
      expect(g.bron, Bijstelbron.geenRuimte);
    });

    test('DE VAL: een kleine verlaging met pieken boven 0 laat het nummer ongemoeid', () {
      // −13 LUFS / +2,0 dBTP: het doel vraagt −1, maar dan staat de piek op +1,0 en knipt mpv's
      // float-klem. Kiezen tussen 0 (afstand 1) en −2,5 (afstand 1,5): 0.
      final g = versterking(m(-13, 2.0), -14);
      expect(g.db, 0, reason: 'mpv ≤ 0.37 knipt bij elke versterking ≠ 0 alles boven vol bereik af');
      expect(g.bron, Bijstelbron.klemNul);
    });

    test('DE VAL: een grotere verlaging met pieken gaat net iets verder, zodat niets afknipt', () {
      // −11 / +1,6: doel vraagt −3 → piek −1,4 ok. Maar −12,5 / +2,4: vraagt −1,5 → piek +0,9;
      // kiezen tussen 0 (1,5) en −2,9 (1,4): −2,9.
      expect(versterking(m(-11, 1.6), -14).db, closeTo(-3, 1e-9));
      final g = versterking(m(-12.5, 2.4), -14);
      expect(g.db, closeTo(-2.9, 1e-9));
      expect(g.bron, Bijstelbron.klemExtra);
    });

    test('DE GRENS: nooit meer dan +10 dB erbij', () {
      expect(versterking(m(-40, -30), -14).db, 10);
    });

    test('DE VAL: stilte wordt niet opgeblazen', () {
      final g = versterking(m(-70, kPiekOndergrens), -14);
      expect(g.db, 0);
      expect(g.bron, Bijstelbron.stilte);
    });

    test('DE GRENS: minder dan 0,05 dB is 0 — dan blijft het bit-gelijk', () {
      final g = versterking(m(-14.03, -3), -14);
      expect(g.db, 0);
      expect(g.bron, Bijstelbron.opDoel);
    });

    test('DE KERN: over een raster van luidheid en piek knipt niets ooit af', () {
      for (var i = -30.0; i <= -3.0; i += 0.25) {
        for (var p = -12.0; p <= 4.0; p += 0.15) {
          for (final doel in [-14.0, -11.0]) {
            final g = versterking(m(i, p), doel).db;
            if (g == 0) continue;
            expect(p + g, lessThanOrEqualTo(kKlemMarge + 1e-9),
                reason: 'I $i, P $p, doel $doel: versterking $g laat de piek boven −0,5 dBTP');
            if (g > 0) {
              expect(p + g, lessThanOrEqualTo(kPiekPlafond + 1e-9),
                  reason: 'een ophoging hoort op hooguit −1 dBTP te eindigen');
            }
          }
        }
      }
    });
  });

  group('een plaat', () {
    Albumdeel deel(double? i, double? p, {bool definitief = false, int s = 200}) => (
          meting: i == null ? null : m(i, p!),
          definitief: definitief,
          duur: Duration(seconds: s),
        );

    test('DE KERN: vermogensgemiddelde naar duur, piek = de hoogste', () {
      final a = albumMeting([deel(-10, -3), deel(-20, 1.5)])!;
      expect(a.lufs, closeTo(-12.6, 0.05));
      expect(a.piek, 1.5);
    });

    test('DE GRENS: stille nummers tellen mee voor de piek maar niet voor de luidheid', () {
      final a = albumMeting([deel(-10, -3), deel(-70, -2)])!;
      expect(a.lufs, closeTo(-10, 1e-9));
      expect(a.piek, -2);
    });

    test('DE GRENS: zolang een nummer nog gemeten moet worden is er geen albumwaarde', () {
      expect(albumMeting([deel(-10, -3), deel(null, null)]), isNull);
    });

    test('DE GRENS: mislukt of meerkanaals telt als definitief, maar niet mee', () {
      final a = albumMeting([deel(-10, -3), deel(null, null, definitief: true)])!;
      expect(a.lufs, closeTo(-10, 1e-9));
    });

    test('DE VAL: geen klem op plaatniveau — één piekerig nummer bepaalt niet de hele plaat', () {
      // Voorbeeld van de beoordelaar: Gelijk, plaat −12,5, één nummer +2,4, de rest ≤ −0,5.
      final g = albumVersterking(m(-12.5, 2.4), -14);
      expect(g, closeTo(-1.5, 1e-9));
      expect(perNummerInAlbum(g, m(-12, -0.8)).db, closeTo(-1.5, 1e-9),
          reason: 'met de albumklem kwam de hele plaat 1,4 dB onder het doel');
      expect(perNummerInAlbum(g, m(-12, 2.4)).db, closeTo(-2.9, 1e-9));
      // Luider, plaat −9,6, één nummer +2,6.
      final l = albumVersterking(m(-9.6, 2.6), -11);
      expect(perNummerInAlbum(l, m(-9, -1)).db, closeTo(-1.4, 1e-9));
      expect(perNummerInAlbum(l, m(-9, 2.6)).db, 0);
    });

    test('DE KERN: per nummer in een plaat knipt ook niets af', () {
      for (var ia = -25.0; ia <= -5.0; ia += 0.5) {
        for (var pa = -10.0; pa <= 4.0; pa += 0.5) {
          final g = albumVersterking(m(ia, pa), -14);
          for (var pi = -12.0; pi <= pa; pi += 0.25) {
            final d = perNummerInAlbum(g, m(-14, pi)).db;
            if (d == 0) continue;
            expect(pi + d, lessThanOrEqualTo(kKlemMarge + 1e-9));
            if (d > 0) expect(pi + d, lessThanOrEqualTo(kPiekPlafond + 1e-9));
          }
        }
      }
    });

    test('DE GRENS: geen eigen meting in een plaat is 0', () {
      expect(perNummerInAlbum(-4, null).db, 0);
    });
  });

  group('wanneer als plaat', () {
    bool als({bool geheel = true, bool volgorde = true, bool single = false, bool verzamel = false,
            int reeks = 3, int lengte = 12}) =>
        speeltAlsAlbum(
            albumGeheel: geheel,
            opVolgorde: volgorde,
            isSingle: single,
            isVerzamelaar: verzamel,
            reeks: reeks,
            plaatLengte: lengte);

    test('DE KERN: een plaat op volgorde speelt als plaat', () => expect(als(), isTrue));
    test('DE GRENS: geschud of radio speelt per nummer', () => expect(als(volgorde: false), isFalse));
    test('DE GRENS: een los paar in een afspeellijst speelt per nummer', () => expect(als(reeks: 2), isFalse));
    test('DE GRENS: een plaat van twee die helemaal speelt is een plaat', () => expect(als(reeks: 2, lengte: 2), isTrue));
    test('DE VAL: een verzamelalbum gaat altijd per nummer', () => expect(als(verzamel: true), isFalse));
    test('DE GRENS: een single en de schakelaar uit gaan per nummer', () {
      expect(als(single: true), isFalse);
      expect(als(geheel: false), isFalse);
    });

    test('DE KERN: de reeks telt alleen plekken die telkens met 1 stijgen', () {
      expect(aaneengeslotenReeks([0, 1, 2, 3], 2), 4);
      expect(aaneengeslotenReeks([3, 2, 1, 0], 1), 1, reason: 'aflopend is geen plaat luisteren');
      expect(aaneengeslotenReeks([0, 1, null, 2, 3], 1), 2);
      expect(aaneengeslotenReeks([0, 2, 3, 4], 2), 3, reason: 'een overgeslagen nummer breekt de reeks');
      expect(aaneengeslotenReeks([null, 5], 0), 0);
    });
  });

  group('ffmpeg lezen', () {
    const echt = '''
Input #0, flac, from 'D:\\Flac music 2024\\x.flac':
  Duration: 00:03:37.00, start: 0.000000, bitrate: 1018 kb/s
  Stream #0:0: Audio: flac, 44100 Hz, stereo, s16
  Stream #0:1: Video: mjpeg (Baseline), yuvj420p(pc, bt470bg/unknown/unknown), 500x500, 90k tbr, 90k tbn (attached pic)
Stream mapping:
  Stream #0:0 -> #0:0 (flac (native) -> pcm_s16le (native))
Output #0, null, to 'pipe:':
  Stream #0:0: Audio: pcm_s16le, 44100 Hz, 5.1, s16, 1411 kb/s
[Parsed_ebur128_0 @ 000001] Summary:

  Integrated loudness:
    I:         -11.5 LUFS
    Threshold: -21.6 LUFS

  Loudness range:
    LRA:         5.8 LU
    Threshold: -31.6 LUFS
    LRA low:   -14.9 LUFS
    LRA high:   -9.1 LUFS

  Sample peak:
    Peak:       -0.0 dBFS

  True peak:
    Peak:        0.3 dBFS
''';

    test('DE KERN: luidheid, beide pieken en het aantal kanalen van de INVOER', () {
      final u = leesEbur128(echt);
      expect(u.lufs, -11.5);
      expect(u.monsterpiek, -0.0);
      expect(u.warePiek, 0.3);
      expect(u.kanalen, 2, reason: 'het uitvoerblok zegt 5.1 en de hoes is een videostroom');
      final s = uitslagUit(u) as Gemeten;
      expect(s.meting.lufs, -11.5);
      expect(s.meting.piek, closeTo(0.35, 1e-9), reason: 'ffmpeg rondt op één decimaal; +0,05 marge');
    });

    test('DE VAL: −inf wordt een eindige ondergrens, en JSON blijft slagen', () {
      final u = leesEbur128(echt.replaceAll('-0.0 dBFS', '-inf dBFS').replaceAll('0.3 dBFS', '-inf dBFS')
          .replaceAll('-11.5 LUFS', '-70.0 LUFS'));
      final s = uitslagUit(u) as Gemeten;
      expect(s.meting.piek.isFinite, isTrue);
      expect(() => jsonEncode(s.meting.toJson()), returnsNormally,
          reason: 'één oneindig getal in de catalogus brak hem voor alle toestellen');
      expect(versterking(s.meting, -14).db, 0);
    });

    test('DE GRENS: inf, nan, afgebroken uitvoer en rommel zijn Mislukt', () {
      expect(uitslagUit(leesEbur128(echt.replaceAll('-11.5 LUFS', 'nan LUFS'))), isA<Mislukt>());
      expect(uitslagUit(leesEbur128(echt.substring(0, echt.indexOf('Summary:')))), isA<Mislukt>());
      expect(uitslagUit(leesEbur128('Invalid data found when processing input'),
          kanalenUitKop: 2), isA<Mislukt>());
    });

    test('DE KERN: meer dan twee kanalen bewaart geen getallen', () {
      final vijf = echt.replaceFirst('44100 Hz, stereo, s16\n', '48000 Hz, 5.1(side), s32\n');
      expect(uitslagUit(leesEbur128(vijf)), isA<Meerkanaals>());
      expect(uitslagUit(leesEbur128(echt), kanalenUitKop: 6), isA<Meerkanaals>(),
          reason: 'de kop van de FLAC gaat voor de streamregel');
    });

    test('DE GRENS: de kanalentabel, en onbekend telt als meer dan twee', () {
      expect(kanalenUitStroom('flac, 44100 Hz, stereo, s16'), 2);
      expect(kanalenUitStroom('ape (APE  / 0x20455041), 192000 Hz, stereo, s32p (24 bit)'), 2);
      expect(kanalenUitStroom('aac (LC) (mp4a / 0x6134706D), 44100 Hz, stereo, fltp, 256 kb/s'), 2);
      expect(kanalenUitStroom('pcm_s16be, 48000 Hz, mono, s16, 768 kb/s'), 1);
      expect(kanalenUitStroom('flac, 96000 Hz, 5.1(side), s32 (24 bit)'), 6);
      expect(kanalenUitStroom('dsd_lsbf, 352800 Hz, 3 channels, flt'), 3);
      expect(kanalenUitStroom('wavpack, 44100 Hz, downmix, fltp'), 99, reason: 'onbekend = de veilige kant');
      expect(kanalenUitStroom('zonder frequentie'), 99);
    });

    test('DE GRENS: een meting zonder geldige getallen uit JSON is geen meting', () {
      expect(Luidheidsmeting.fromJson({'mk': 6}), isNull);
      expect(Luidheidsmeting.fromJson({'f': 1}), isNull);
      expect(Luidheidsmeting.fromJson({'i': 'x', 'tp': 1}), isNull);
      expect(Luidheidsmeting.fromJson({'i': -10.7, 'tp': 0.3}), m(-10.7, 0.3));
    });
  });

  group('één adres, aan beide kanten hetzelfde', () {
    test('DE KERN: het Windows-voorvoegsel van media_kit valt weg', () {
      const bron = r"D:\Flac music 2024\Céline Dion\D'Eux\01 - Pour.flac";
      const mpv = r"\\?\D:\Flac music 2024\Céline Dion\D'Eux\01 - Pour.flac";
      const genormaliseerd = "D:/Flac music 2024/Céline Dion/D'Eux/01 - Pour.flac";
      final s = adresSleutel(bron, kleineLetters: true);
      expect(adresSleutel(mpv, kleineLetters: true), s,
          reason: 'zonder dit vond de haak op de pc nooit iets en speelde alles op 0 dB');
      expect(adresSleutel(genormaliseerd, kleineLetters: true), s);
    });

    test('DE GRENS: spaties, accenten, # en % blijven gelijk', () {
      const a = r'D:\Muziek\Ëlla #1 100% (live)\01 x.flac';
      expect(adresSleutel(r'\\?\' + a, kleineLetters: true), adresSleutel(a, kleineLetters: true));
    });

    test('DE GRENS: een UNC-pad', () {
      expect(adresSleutel(r'\\?\UNC\server\share\x.flac', kleineLetters: true),
          adresSleutel(r'\\server\share\x.flac', kleineLetters: true));
      expect(adresSleutel(r'\\server\share\x.flac', kleineLetters: true), '//server/share/x.flac');
    });

    test('DE GRENS: een stream-adres blijft een adres', () {
      const url = 'http://100.97.101.113:80/stream/abc.flac?token=geheim&maxRate=44100&maxBits=16';
      final s = adresSleutel(url, kleineLetters: true);
      expect(adresSleutel(Uri.parse(url).toString(), kleineLetters: true), s);
      expect(adresSleutel('http://pc/stream/caf%c3%a9.flac', kleineLetters: true),
          adresSleutel(Uri.parse('http://pc/stream/caf%c3%a9.flac').toString(), kleineLetters: true));
    });

    test('DE GRENS: een Android-pad blijft zoals het is, en rommel gooit niet', () {
      const p = '/data/user/0/com.debridmusic.app/files/offline/X.flac';
      expect(adresSleutel(p, kleineLetters: false), p);
      expect(() => adresSleutel('http://[::1', kleineLetters: true), returnsNormally);
    });
  });

  test('DE GRENS: de standen en hun doelen', () {
    expect(luidheidsstandUit('uit'), Luidheidsstand.uit);
    expect(luidheidsstandUit('luid'), Luidheidsstand.luid);
    expect(luidheidsstandUit('normaal'), Luidheidsstand.normaal);
    expect(luidheidsstandUit('iets nieuws'), Luidheidsstand.normaal,
        reason: 'een onbekende waarde mag de functie niet stilletjes uitzetten');
    expect(doelVoor(Luidheidsstand.normaal), -14);
    expect(doelVoor(Luidheidsstand.luid), -11);
  });
}

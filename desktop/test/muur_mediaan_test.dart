// De muurproef ook op de MEDIAAN per band (26-11-2026).
//
// Ricky Martin "Maria", binnen als "Studio · 24/48" (Soulseek lordzeezus, uit het album "Ricky Martin" van 1999 — dat
// bestaat alleen in 16/44,1). Een Opus-muur op precies 20,0 kHz, erboven leeg; maar 2665 afgekapte monsters strooiden
// in de luide vensters over het hele spectrum, en in het vermogensgemiddelde wegen juist die vensters het zwaarst: de
// meter mat 23,7 dB, net onder de 25, en noemde hem "doorlopend". Saber: "Ja maar waarom liet de app die door, ik wil
// geen nep in de app, dus zoek uit om dit te verbeteren".
import 'dart:io';
import 'dart:typed_data';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/echtheid_meter.dart';
import 'package:debridmusic/ffmpeg.dart';
import 'package:debridmusic/kopiesoort.dart';
import 'package:flutter_test/flutter_test.dart';

/// Banden van 50 Hz: [niveau] tot en met [tot] Hz, daarboven [erboven].
Float64List banden({int sr = 48000, required double tot, double niveau = -20, double erboven = -120}) {
  final n = (sr / 2 / 50).floor();
  return Float64List.fromList([for (var k = 0; k < n; k++) k * 50.0 <= tot ? niveau : erboven]);
}

Echtheidsoordeel oordeel({
  required Float64List gemiddeld,
  Float64List? mediaan,
  int sr = 48000,
  int bits = 24,
  int luid = 400,
}) =>
    oordeelVol(
      s: Spectrumstaat(sampleRate: sr, bandHz: 50, gemiddeld: gemiddeld, p95: gemiddeld, luid: luid, mediaan: mediaan),
      kopSampleRate: sr,
      kopBits: bits,
      gebruikteBits: bits,
      nietNulSamples: 5000000,
      integriteit: Integriteit.klopt,
    );

String bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('de muurproef op de mediaan', () {
    // Wat Maria liet zien: in het gewone venster een muur van 100 dB op 20 kHz, in het gemiddelde spetters op −50.
    final gespetterd = banden(tot: 20000, erboven: -50);
    final gewoon = banden(tot: 20000);

    test('DE KERN: afgekapte pieken boven een 20 kHz-muur — het gemiddelde zag hem niet, de mediaan wel', () {
      final zonder = oordeel(gemiddeld: gespetterd);
      expect(zonder.band, Bandbreedte.doorlopend, reason: 'zo liet de app Maria door');
      final met = oordeel(gemiddeld: gespetterd, mediaan: gewoon);
      expect(met.band, Bandbreedte.vermoedelijk);
      expect(met.mediaan, isTrue);
      expect(met.afkapHz, inInclusiveRange(19800, 20200));
      expect(met.wandDb, greaterThan(volMuurDb));
      expect(studioTegengesproken(met), isTrue, reason: 'dan mag hij geen studio heten');
    });

    test('bij een cd verandert er niets: daar beslist de muur geen soort', () {
      final cd = oordeel(
          gemiddeld: banden(sr: 44100, tot: 20000, erboven: -50), mediaan: banden(sr: 44100, tot: 20000), sr: 44100, bits: 16);
      expect(cd.band, Bandbreedte.doorlopend);
      expect(cd.mediaan, isFalse);
    });

    test('wie meer dan cd belooft: meer dan 16 bit, of meer dan 44,1 kHz', () {
      expect(mediaanNodig(kopSampleRate: 44100, kopBits: 16), isFalse);
      expect(mediaanNodig(kopSampleRate: 44100, kopBits: 24), isTrue);
      expect(mediaanNodig(kopSampleRate: 48000, kopBits: 16), isTrue);
      expect(mediaanNodig(kopSampleRate: 96000, kopBits: 24), isTrue);
    });

    test('de mediaan maakt een oordeel nooit milder', () {
      final o = oordeel(gemiddeld: banden(tot: 16800), mediaan: banden(tot: 24000));
      expect(o.band, Bandbreedte.afgekapt);
      expect(o.afkapHz, inInclusiveRange(16500, 17000));
    });

    test('een muur onder 19,4 kHz die alleen de mediaan ziet: vermoedelijk, niet bewezen — maar wel geen studio', () {
      // "Children (Radio Edit)": op de mediaan afgekapt op 16,15 kHz, maar die val zit in de officiële TIDAL-master.
      final o = oordeel(gemiddeld: banden(tot: 16800, erboven: -50), mediaan: banden(tot: 16800));
      expect(o.band, Bandbreedte.vermoedelijk);
      expect(o.isNep, isFalse);
      expect(studioTegengesproken(o), isTrue);
    });

    test('echte hi-res, doorlopend tot 24 kHz in allebei: doorlopend', () {
      final vol = banden(tot: 24000);
      final o = oordeel(gemiddeld: vol, mediaan: vol);
      expect(o.band, Bandbreedte.doorlopend);
      expect(o.mediaan, isTrue);
      expect(studioTegengesproken(o), isFalse);
    });

    test('te weinig luide vensters: geen uitspraak over de band, maar wel gemeten — geen eindeloos opnieuw meten', () {
      final o = oordeel(gemiddeld: gespetterd, mediaan: gewoon, luid: 10);
      expect(o.band, Bandbreedte.onbekend);
      expect(o.mediaan, isTrue);
      expect(o.mistMediaan(48000, 24), isFalse);
    });

    test('een mediaan van een andere lengte telt niet', () {
      final s = Spectrumstaat(
          sampleRate: 48000, bandHz: 50, gemiddeld: gespetterd, p95: gespetterd, luid: 400, mediaan: Float64List(3));
      expect(s.alsMediaan, isNull);
      expect(Spectrumstaat(sampleRate: 48000, bandHz: 50, gemiddeld: gespetterd, p95: gespetterd, luid: 400).alsMediaan,
          isNull);
    });
  });

  group('bewaard, en opnieuw gemeten wat de mediaan nog mist', () {
    test('heen en terug; een oud oordeel van een hi-res bestand meet de veger opnieuw, een cd niet', () {
      final o = oordeel(gemiddeld: banden(tot: 24000), mediaan: banden(tot: 24000));
      final terug = Echtheidsoordeel.fromJson(o.toJson())!;
      expect(terug.mediaan, isTrue);
      expect(terug.mistMediaan(48000, 24), isFalse);
      final oud = Echtheidsoordeel.fromJson({...o.toJson()..remove('med')})!;
      expect(oud.mediaan, isFalse);
      expect(oud.mistMediaan(48000, 24), isTrue);
      expect(oud.mistMediaan(44100, 24), isTrue);
      expect(oud.mistMediaan(96000, 24), isTrue);
      expect(oud.mistMediaan(44100, 16), isFalse);
      expect(o.bewezenDoor('x').mediaan, isTrue);
      const niets = Echtheidsoordeel(bits: Bitdiepte.onbekend, boven: Bovenband.onbekend, band: Bandbreedte.onbekend);
      expect(niets.mistMediaan(48000, 24), isFalse, reason: 'niets te meten blijft niets te meten');
    });
  });

  group('een studioversie die de meter tegenspreekt', () {
    const schoon = Echtheidsoordeel(bits: Bitdiepte.onbekend, boven: Bovenband.onbekend, band: Bandbreedte.doorlopend);
    const muur = Echtheidsoordeel(bits: Bitdiepte.spreektNietTegen, boven: Bovenband.onbekend, band: Bandbreedte.vermoedelijk);
    const opgeschaald = Echtheidsoordeel(bits: Bitdiepte.spreektNietTegen, boven: Bovenband.leeg, band: Bandbreedte.doorlopend);
    const cdMetMuur = Echtheidsoordeel(bits: Bitdiepte.onbekend, boven: Bovenband.onbekend, band: Bandbreedte.vermoedelijk);
    const niets = Echtheidsoordeel(bits: Bitdiepte.onbekend, boven: Bovenband.onbekend, band: Bandbreedte.onbekend);

    test('een muur rond 20 kHz naast een schoon gemeten cd: weg — dezelfde maat als bij binnenkomst', () {
      expect(nepStudioVersieWeg(muur, schoon), isTrue);
    });

    test('bewezen nep: altijd weg', () {
      expect(nepStudioVersieWeg(opgeschaald, schoon), isTrue);
      expect(nepStudioVersieWeg(opgeschaald, cdMetMuur), isTrue);
      expect(nepStudioVersieWeg(opgeschaald, null), isTrue);
    });

    test('je nummer heeft dezelfde twijfel, of is niet gemeten: hij blijft (All Saints, Jorja Smith)', () {
      expect(nepStudioVersieWeg(muur, cdMetMuur), isFalse);
      expect(nepStudioVersieWeg(muur, null), isFalse);
      expect(nepStudioVersieWeg(muur, niets), isFalse);
      expect(nepStudioVersieWeg(muur, opgeschaald), isFalse);
    });

    test('een schone studio blijft', () {
      expect(nepStudioVersieWeg(schoon, schoon), isFalse);
    });
  });

  group('aangesloten', () {
    test('de meter rekent de mediaan per band over dezelfde luide vensters en geeft hem aan het oordeel', () {
      final m = bron('lib/echtheid_meter.dart');
      expect(m, contains('      mediaanBand[k] = kolom[(kolom.length * 0.5).floor().clamp(0, kolom.length - 1)];\n'));
      expect(m, contains('        mediaan: luid.isEmpty ? null : mediaanBand),\n'));
      expect(m, contains('      final cache = await _cacheBestand(pad, kopSampleRate, kopBits);\n'));
      // Een eigen merk in de cachesleutel: een oude uitslag zonder mediaan wordt niet meer gelezen.
      expect(m, contains(r"mediaanNodig(kopSampleRate: kopSampleRate, kopBits: kopBits) ? 'm' : ''}';"));
    });

    test('het oordeel neemt de zwaarste van de twee, en onthoudt dat de mediaan liep', () {
      final e = bron('lib/echtheid.dart');
      expect(e, contains('      final mb = c.band == Bandbreedte.afgekapt ? Bandbreedte.vermoedelijk : c.band;\n'));
      expect(e, contains('      if (_gewicht(mb) > _gewicht(band)) {\n'));
      expect(e, contains('    mediaan: m != null,\n'));
    });

    test('de veger meet opnieuw wat de mediaan mist, en meldt een tegengesproken studio', () {
      final v = bron('lib/echtheid_veger.dart');
      expect(v, contains('    return o == null || _mistIets(o, t);'));
      expect(v, contains('      o.mistSpiegel(t.sampleRate) || o.mistMediaan(t.sampleRate, t.bitsPerSample);'));
      expect(v, contains('        final vers = moetVersGemeten(t.path) || (oud != null && _mistIets(oud, t));\n'));
      expect(v, contains('          } else if (studioTegengesproken(o)) {\n            final weg = bijTegengesprokenStudio;\n'));
    });

    test('de pc gooit alleen een STUDIOversie weg, naast een nummer dat er nog is, als nepStudioVersieWeg ja zegt', () {
      final m = bron('lib/main.dart');
      final i = m.indexOf('    echtVeger.bijTegengesprokenStudio = (versie, o) async {\n');
      expect(i, greaterThan(0));
      final stuk = m.substring(i, m.indexOf('    };\n', i));
      expect(stuk, contains('v.soort != Kopiesoort.studio || !File(ankerPad).existsSync()) return;'));
      expect(stuk, contains('      if (!nepStudioVersieWeg(o, gemeten(ankerPad))) {\n'));
      expect(stuk, contains('      final zin = await gooiVersieWeg(library, anker, versie.path);\n'));
    });
  });

  // Op echte audio, met echte ffmpeg (de bouwstraat heeft /usr/bin/ffmpeg): wat er met Maria gebeurde, nagedaan — een
  // harde muur op 20 kHz zoals Opus hem zet, en daarna de luide stukken afgekapt bij het wegschrijven.
  group('op echte audio', () {
    final ffmpeg = Ffmpeg().pad;
    late Directory map;
    setUpAll(() => map = Directory.systemTemp.createTempSync('muur_mediaan_'));
    tearDownAll(() {
      try {
        map.deleteSync(recursive: true);
      } catch (_) {}
    });

    Future<File> maak(String naam, {required bool muur, int sr = 48000, int bits = 24}) async {
      final f = File('${map.path}${Platform.pathSeparator}$naam.flac');
      final filters = [
        if (muur) "firequalizer=gain='if(lt(f,20000),0,-150)':delay=0.02:accuracy=20",
        "volume='if(lt(mod(t,4),0.6),12,1)':eval=frame",
      ].join(',');
      final r = await Process.run(ffmpeg!, [
        '-v', 'error', '-y', //
        '-f', 'lavfi', '-i', 'anoisesrc=color=pink:sample_rate=$sr:duration=35:amplitude=0.25:seed=7',
        '-ac', '2', '-af', filters, '-c:a', 'flac',
        '-sample_fmt', bits > 16 ? 's32' : 's16', if (bits > 16) ...['-bits_per_raw_sample', '$bits'],
        f.path,
      ]);
      if (r.exitCode != 0) throw StateError('ffmpeg maakte $naam niet: ${r.stderr}');
      return f;
    }

    Future<Echtheidsoordeel?> meet(File f, {int sr = 48000, int bits = 24}) =>
        meetHeelBestand(exe: ffmpeg!, pad: f.path, kopSampleRate: sr, kopBits: bits, duurSeconden: 35);

    test('een 24/48 met een harde 20 kHz-muur en afgekapte pieken: vermoedelijk, dus geen studio', () async {
      final o = (await meet(await maak('muur_klip', muur: true)))!;
      expect(o.mediaan, isTrue);
      expect(o.band, Bandbreedte.vermoedelijk, reason: 'muur ${o.afkapHz} Hz, ${o.wandDb} dB');
      expect(studioTegengesproken(o), isTrue);
    }, skip: ffmpeg == null ? 'geen ffmpeg' : false);

    test('even hard afgekapt, maar doorlopend tot 24 kHz: geen vals alarm', () async {
      final o = (await meet(await maak('vol_klip', muur: false)))!;
      expect(o.mediaan, isTrue);
      expect(o.band, Bandbreedte.doorlopend, reason: 'muur ${o.afkapHz} Hz, ${o.wandDb} dB');
    }, skip: ffmpeg == null ? 'geen ffmpeg' : false);

    test('een cd (16/44,1) met dezelfde muur: de mediaan meet niet mee', () async {
      final o = (await meet(await maak('cd_klip', muur: true, sr: 44100, bits: 16), sr: 44100, bits: 16))!;
      expect(o.mediaan, isFalse);
    }, skip: ffmpeg == null ? 'geen ffmpeg' : false);
  });
}

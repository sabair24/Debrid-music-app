// De spiegeltest (spiegel.dart): is een 24/48 opgeschaald vanaf 44,1 kHz? Saber, 25-11-2026, bij Chris Isaak "Blue
// Hotel" ("FLAC · 24/48 · studio"): "Kan je deze 2 eens controleren op de echtheid van de resolutie of het 100 procent
// klopt ?" — het liep door tot 24 kHz, maar wat boven 22,05 kHz zat was het spiegelbeeld van 20–22 kHz.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:debridmusic/echtheid.dart';
import 'package:debridmusic/keuring.dart';
import 'package:debridmusic/spiegel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Witte ruis (gelijkverdeeld), vast zaad.
Float64List ruis(int n, int zaad) {
  final r = math.Random(zaad);
  return Float64List.fromList([for (var i = 0; i < n; i++) (r.nextDouble() - 0.5) * 0.5]);
}

/// [x] (44,1 kHz) naar 48 kHz met lineaire interpolatie: een onvolmaakt filter, dat de spiegeling laat staan.
Float64List opschalen(Float64List x, int n48) {
  final y = Float64List(n48);
  for (var n = 0; n < n48; n++) {
    final t = n * 44100 / 48000;
    final i = t.floor(), f = t - i;
    y[n] = i + 1 < x.length ? x[i] * (1 - f) + x[i + 1] * f : 0;
  }
  return y;
}

/// De meter over [y] zoals echtheid_meter.dart hem voedt: vensters op een vaste stap die GEEN veelvoud van 160 is, zodat
/// de draaiing per plek ([Spiegelmeter.venster], 147·n0 mod 160) er echt toe doet.
double? meet(Float64List y, {int stap = 5333}) {
  final m = Spiegelmeter();
  for (var n0 = 0; n0 + kSpiegelN <= y.length; n0 += stap) {
    m.venster(Float64List.sublistView(y, n0, n0 + kSpiegelN), n0);
  }
  return m.uitslag;
}

Spectrumstaat staat({int sr = 48000}) {
  final n = (sr / 2 / 50).floor();
  final b = Float64List(n);
  for (var k = 0; k < n; k++) {
    b[k] = k * 50.0 <= 21000 ? -20 : -110;
  }
  return Spectrumstaat(sampleRate: sr, bandHz: 50, gemiddeld: b, p95: b, luid: 400);
}

Echtheidsoordeel oordeel({int sr = 48000, double? spiegel}) => oordeelVol(
    s: staat(sr: sr),
    kopSampleRate: sr,
    kopBits: 24,
    gebruikteBits: 24,
    nietNulSamples: 5000000,
    integriteit: Integriteit.klopt,
    spiegel: spiegel);

String bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('de spiegelmeter', () {
    test('DE KERN: een 44,1-bron opgeschaald naar 48 kHz hangt vast aan zijn spiegelbeeld', () {
      final x = ruis(44100 * 14, 1);
      final y = opschalen(x, 48000 * 14);
      final u = meet(y)!;
      // Witte ruis tot 22,05 kHz: de spiegeling van 18–20 kHz vouwt ook terug in de meetband en verdunt (gemeten 0,57);
      // muziek, zoals de ijking, gaf 0,83.
      expect(u, greaterThan(0.5), reason: 'lineaire interpolatie');
      expect(u, greaterThan(kSpiegelOpgeschaald));
    });

    test('echte inhoud boven 22 kHz (ruis op 48 kHz) hangt nergens aan vast', () {
      final u = meet(ruis(48000 * 14, 2))!;
      expect(u, lessThan(0.05));
      expect(u, lessThan(kSpiegelOpgeschaald));
    });

    test('de draaiing per plek is nodig: zonder ze valt de samenhang weg', () {
      // Zelfde opgeschaalde ruis, maar elk venster met n0 = 0 doorgegeven: dan klopt de fase niet meer.
      final y = opschalen(ruis(44100 * 14, 3), 48000 * 14);
      final m = Spiegelmeter();
      for (var n0 = 0; n0 + kSpiegelN <= y.length; n0 += 5333) {
        m.venster(Float64List.sublistView(y, n0, n0 + kSpiegelN), 0);
      }
      expect(m.uitslag!, lessThan(0.2));
      expect(meet(y)!, greaterThan(0.5));
    });

    test('te weinig vensters: geen uitspraak', () {
      expect(meet(ruis(48000 * 2, 4)), isNull);
    });
  });

  group('het oordeel bij 48 kHz', () {
    test('DE KERN: gespiegeld = opgeschaald (Bovenband.leeg), dus nep, met een zin die zegt waarom', () {
      final o = oordeel(spiegel: 0.96);
      expect(o.boven, Bovenband.leeg);
      expect(o.isNep, isTrue);
      expect(o.gespiegeld, isTrue);
      expect(waarom(o), contains('spiegelbeeld'));
      expect(waarom(o), contains('opgeschaald vanaf 44,1 kHz'));
      expect(echteWaarden(o, kopSampleRate: 48000, kopBits: 24).rate, 44100);
    });

    test('geen spiegelbeeld: niets bewezen, geen nep', () {
      final o = oordeel(spiegel: 0.006);
      expect(o.boven, Bovenband.onbekend);
      expect(o.isNep, isFalse);
      expect(o.gespiegeld, isFalse);
    });

    test('alleen bij 48 kHz: op 44,1 kHz telt de spiegel niet', () {
      final o = oordeel(sr: 44100, spiegel: 0.96);
      expect(o.boven, Bovenband.onbekend);
      expect(o.isNep, isFalse);
    });

    test('bewaard en teruggelezen; een oud oordeel bij 48 kHz meet de veger opnieuw', () {
      final o = oordeel(spiegel: 0.96);
      final terug = Echtheidsoordeel.fromJson(o.toJson())!;
      expect(terug.spiegel, closeTo(0.96, 1e-9));
      expect(terug.boven, Bovenband.leeg);
      final oud = Echtheidsoordeel.fromJson({...o.toJson()..remove('spiegel'), 'boven': 'onbekend'})!;
      expect(oud.mistSpiegel(48000), isTrue);
      expect(oud.mistSpiegel(44100), isFalse);
      expect(terug.mistSpiegel(48000), isFalse);
      expect(o.bewezenDoor('x').spiegel, closeTo(0.96, 1e-9));
    });

    test('de keuring: een gespiegelde 24/48 liegt in zijn kop, telt niet als diep en is niet schoon', () {
      final k = kwaliteitUit(verliesvrij: true, kopRate: 48000, formaat: 1, oordeel: oordeel(spiegel: 0.96));
      expect(k.kopLiegt, isTrue);
      expect(k.diep, isFalse);
      expect(k.schoon, isFalse);
      final echt = kwaliteitUit(verliesvrij: true, kopRate: 48000, formaat: 1, oordeel: oordeel(spiegel: 0.006));
      expect(echt.kopLiegt, isFalse);
    });
  });

  group('aangesloten', () {
    test('de meter voedt de spiegel met het eerste kanaal en de plek van het venster, en geeft hem aan het oordeel', () {
      final m = bron('lib/echtheid_meter.dart');
      expect(m, contains('final spiegel = sr == 48000 ? Spiegelmeter() : null;'));
      expect(m, contains('          sluitVenster();\n          spiegel?.venster(buf[0], volgendeStart);\n'));
      expect(m, contains('    spiegel: spiegel?.uitslag,\n'));
      expect(m, contains(r"final merk = '${kopSampleRate == 48000 ? 's' : ''}${mediaanNodig(kopSampleRate: kopSampleRate, kopBits: kopBits) ? 'm' : ''}';"));
    });

    test('de veger meet ook de versies, en opnieuw wat bij 48 kHz nog geen spiegel had', () {
      final v = bron('lib/echtheid_veger.dart');
      expect(v, contains('        for (final t in library.metVersies)\n'));
      expect(v, contains('    return o == null || _mistIets(o, t);'));
      expect(v, contains('      o.mistSpiegel(t.sampleRate) || o.mistMediaan(t.sampleRate, t.bitsPerSample);'));
      expect(v, contains('        if (!_moetMeten(t) || _isGeblokkeerd(t.path) || !File(t.path).existsSync()) continue;'));
      expect(v, contains('            if (weg != null) await weg(t, o);'));
    });

    test('de pc gooit alleen een gespiegelde STUDIOversie weg, naast een nummer dat er nog is', () {
      final m = bron('lib/main.dart');
      expect(m, contains('    echtVeger.bijGespiegeldeVersie = (versie, o) async {\n'));
      expect(m, contains('if (ankerPad == null || v == null || v.soort != Kopiesoort.studio || !File(ankerPad).existsSync()) return;'));
      expect(m, contains('      final zin = await gooiVersieWeg(library, anker, versie.path);\n'));
    });
  });
}

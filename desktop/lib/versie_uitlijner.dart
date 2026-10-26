/// Waar in een versie hetzelfde moment van de muziek valt (versies.dart).
///
/// Wisselen "op dezelfde seconde" (Saber, 26-10-2026: "vloeiend kunnen springen van cd, naar studio of vinyl") lukt pas
/// als de app weet waar die seconde in het andere bestand ligt. Een vinylrip begint vaak een paar seconden later dan de cd
/// (de naald, de aanloopgroef), en een draaitafel draait zelden precies op toeren: na vier minuten loopt hij soms een
/// halve seconde voor of achter. Een remaster heeft soms een andere aanloop.
///
/// Zo: eerst grof met de vingerafdruk (op een achtste seconde), dan op de milliseconde met een kruiscorrelatie van twee
/// stukjes geluid — rond een vijfde en rond vier vijfde van het nummer. Uit die twee volgt de verschuiving én de snelheid.
/// Lukt de fijne meting niet (te weinig overeenkomst), dan blijft de grove staan; lukt ook die niet, dan niets — dan
/// wisselt de speler op dezelfde seconde.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'ffmpeg.dart';
import 'fft.dart';
import 'fingerprint.dart';
import 'versies.dart';
import 'warm_log.dart';

/// Hoe lang één item van een ruwe vingerafdruk duurt: chromaprint werkt op 11.025 Hz met vensters van 4096 en een derde
/// overlap.
const double kVingerafdrukItemMs = 4096 / 3 / 11025 * 1000;

/// De frequentie van de stukjes voor de fijne meting: genoeg voor een halve milliseconde, klein genoeg om snel te zijn.
const int kUitlijnHz = 8000;

/// Een fijne meting telt pas boven deze genormaliseerde overeenkomst: zelfde opname, andere master, en bij vinyl ruis.
const double kUitlijnDrempel = 0.2;

/// De kruiscorrelatie van [a] (anker) met [b] (versie), allebei mono op dezelfde frequentie: bij welke verschuiving [lag]
/// (in samples; positief = in b komt het later) b het best op a past, en hoe goed (genormaliseerd, 0–1). [b] mag langer
/// zijn dan [a]: dan wordt alleen gezocht waar a er helemaal in past, plus [rand] samples aan beide kanten.
///
/// Via de FFT: anders is dit honderd miljoen vermenigvuldigingen per stukje.
({int lag, double kwaliteit}) kruiscorrelatie(Float64List a, Float64List b, {int rand = 0}) {
  if (a.isEmpty || b.isEmpty) return (lag: 0, kwaliteit: 0);
  var n = 1;
  while (n < a.length + b.length) {
    n <<= 1;
  }
  final ar = Float64List(n), ai = Float64List(n), br = Float64List(n), bi = Float64List(n);
  ar.setAll(0, a);
  br.setAll(0, b);
  fft(ar, ai);
  fft(br, bi);
  // conj(A) · B, en terug (een inverse via de geconjugeerde).
  final cr = Float64List(n), ci = Float64List(n);
  for (var i = 0; i < n; i++) {
    cr[i] = ar[i] * br[i] + ai[i] * bi[i];
    ci[i] = -(ar[i] * bi[i] - ai[i] * br[i]);
  }
  fft(cr, ci);
  // cr[k] / n = Σ a[i]·b[i+k] (k ≥ 0); negatieve k staan achteraan.
  final energieA = a.fold<double>(0, (s, x) => s + x * x);
  // De energie van b over elk venster zo lang als a: met een lopende som.
  final kwadraat = Float64List(b.length + 1);
  for (var i = 0; i < b.length; i++) {
    kwadraat[i + 1] = kwadraat[i] + b[i] * b[i];
  }
  var beste = 0.0, besteLag = 0;
  for (var k = -rand; k <= b.length - a.length + rand; k++) {
    final van = k.clamp(0, b.length), tot = (k + a.length).clamp(0, b.length);
    final eb = kwadraat[tot] - kwadraat[van];
    if (eb <= 0 || energieA <= 0) continue;
    final idx = k >= 0 ? k : n + k;
    final r = cr[idx] / n;
    final ncc = r / math.sqrt(energieA * eb);
    if (ncc > beste) {
      beste = ncc;
      besteLag = k;
    }
  }
  return (lag: besteLag, kwaliteit: beste);
}

/// Uit twee metingen ([t1], [o1]) en ([t2], [o2]) — op ankertijd t valt de versie o later — de verschuiving bij 0 en de
/// snelheid. Een snelheid buiten ±3 % is een meetfout: dan alleen de eerste meting, op snelheid 1.
({int verschuivingMs, double snelheid}) uitTweeMetingen(int t1, int o1, int t2, int o2) {
  if (t2 == t1) return (verschuivingMs: o1, snelheid: 1.0);
  final snelheid = 1 + (o2 - o1) / (t2 - t1);
  if ((snelheid - 1).abs() > 0.03) return (verschuivingMs: o1, snelheid: 1.0);
  // v = verschuiving + t·snelheid, en v(t1) = t1 + o1.
  final verschuiving = (t1 + o1 - t1 * snelheid).round();
  return (verschuivingMs: verschuiving, snelheid: double.parse(snelheid.toStringAsFixed(6)));
}

/// Een stukje van [pad] vanaf [vanafMs], [duurMs] lang, als mono op [kUitlijnHz], gemiddelde eraf. Null als ffmpeg het
/// niet kan.
Future<Float64List?> leesStukje(String ffmpeg, String pad, int vanafMs, int duurMs) async {
  try {
    final p = await Process.start(ffmpeg, [
      '-nostdin', '-hide_banner', '-loglevel', 'error', //
      '-ss', (math.max(0, vanafMs) / 1000).toStringAsFixed(3),
      '-t', (duurMs / 1000).toStringAsFixed(3),
      '-i', pad,
      '-map', '0:a:0', '-ac', '1', '-ar', '$kUitlijnHz', '-f', 's16le', 'pipe:1',
    ]);
    unawaited(p.stderr.drain<void>());
    final bytes = BytesBuilder(copy: false);
    await for (final stuk in p.stdout.timeout(const Duration(seconds: 30))) {
      bytes.add(stuk);
    }
    if (await p.exitCode.timeout(const Duration(seconds: 10)) != 0) return null;
    final b = bytes.takeBytes();
    final n = b.length ~/ 2;
    if (n < kUitlijnHz) return null;
    final data = ByteData.sublistView(b);
    final uit = Float64List(n);
    var som = 0.0;
    for (var i = 0; i < n; i++) {
      uit[i] = data.getInt16(i * 2, Endian.little).toDouble();
      som += uit[i];
    }
    final gem = som / n;
    for (var i = 0; i < n; i++) {
      uit[i] -= gem;
    }
    return uit;
  } catch (_) {
    return null;
  }
}

/// De uitlijning van [versie] tegen [anker]: grof met de vingerafdruk, fijn met twee kruiscorrelaties. Null als het niet
/// te meten valt (geen ffmpeg of fpcalc, of de twee lijken niet op elkaar).
Future<({int verschuivingMs, double snelheid, String hoe})?> meetUitlijning(String anker, String versie,
    {String? ffmpeg, Fingerprinter? vingerafdruk}) async {
  final fp = vingerafdruk ?? Fingerprinter();
  final a = await fp.of(anker), b = await fp.of(versie);
  if (a == null || b == null || a.raw.isEmpty || b.raw.isEmpty) return null;
  final grof = bestePassing(a.raw, b.raw, maxOffset: 160);
  if (grof.score < 0.6) return null;
  final grofMs = (grof.verschuiving * kVingerafdrukItemMs).round();
  final exe = ffmpeg ?? Ffmpeg().pad;
  if (exe == null) return (verschuivingMs: grofMs, snelheid: 1.0, hoe: 'vingerafdruk');
  final duurMs = (a.seconds * 1000).round();
  // Twee plekken in het nummer, ver uit elkaar maar niet in de stilte aan het begin of de uitloop.
  final plekken = duurMs > 60000 ? [math.max(15000, duurMs ~/ 5), duurMs * 4 ~/ 5] : [duurMs ~/ 3];
  const stuk = 8000, marge = 1500;
  final metingen = <(int, int)>[];
  for (final t in plekken) {
    final x = await leesStukje(exe, anker, t, stuk);
    final y = await leesStukje(exe, versie, t + grofMs - marge, stuk + 2 * marge);
    if (x == null || y == null) continue;
    final k = kruiscorrelatie(x, y);
    if (k.kwaliteit < kUitlijnDrempel) continue;
    metingen.add((t, grofMs - marge + (k.lag * 1000 / kUitlijnHz).round()));
  }
  if (metingen.isEmpty) return (verschuivingMs: grofMs, snelheid: 1.0, hoe: 'vingerafdruk');
  if (metingen.length == 1) return (verschuivingMs: metingen.first.$2, snelheid: 1.0, hoe: 'één meting');
  final u = uitTweeMetingen(metingen[0].$1, metingen[0].$2, metingen[1].$1, metingen[1].$2);
  return (verschuivingMs: u.verschuivingMs, snelheid: u.snelheid, hoe: 'twee metingen');
}

/// Op de pc, op de achtergrond: elke versie die nog niet uitgelijnd is, één voor één — bij de start, en kort na elke
/// nieuwe versie.
class VersieUitlijnRonde {
  VersieUitlijnRonde({required this.log, this.wacht = const Duration(seconds: 30)});

  final WarmLog log;
  final Duration wacht;
  Timer? _klok;
  bool _bezig = false;
  bool _weg = false;

  void start() {
    versies.uitgave.addListener(_straks);
    _straks();
  }

  void stop() {
    _weg = true;
    _klok?.cancel();
    versies.uitgave.removeListener(_straks);
  }

  void _straks() {
    if (_weg || _bezig) return;
    _klok?.cancel();
    _klok = Timer(wacht, () => unawaited(ronde()));
  }

  Future<int> ronde() async {
    if (_bezig || _weg) return 0;
    _bezig = true;
    var gemeten = 0;
    try {
      final teDoen = [
        for (final g in versies.groepen)
          for (final v in g.versies)
            if (v.verschuivingMs == null) (anker: g.anker, versie: v.pad),
      ];
      for (final x in teDoen) {
        if (_weg) break;
        final u = await meetUitlijning(x.anker, x.versie);
        if (u == null) {
          log.line('uitlijnen: niet te meten — ${x.versie}');
          // Op de seconde: dan wordt hij niet bij elke ronde opnieuw geprobeerd.
          versies.zetUitlijning(x.versie, verschuivingMs: 0, snelheid: 1.0);
          continue;
        }
        versies.zetUitlijning(x.versie, verschuivingMs: u.verschuivingMs, snelheid: u.snelheid);
        gemeten++;
        log.line('uitlijnen: ${u.verschuivingMs} ms, snelheid ${u.snelheid} (${u.hoe}) — ${x.versie}');
      }
    } finally {
      _bezig = false;
    }
    return gemeten;
  }
}

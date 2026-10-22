/// Het tempo van een nummer, gemeten uit de audio zelf.
///
/// **Waarom.** Saber, 22-10-2026, over een radio vanaf Petra — Ik Leef Voor Jou: *"is wat meer up-tempo e, maar eens
/// een trager liedje mag wel natuurlijk"* — en: *"Is er iets anders dat het tempo kan kennen/meten?"* Deezer gaf voor
/// dat nummer `bpm: 0`; Spotify sloot zijn tempogegevens eind 2024 af voor nieuwe apps; AcousticBrainz verzamelt
/// sinds 2022 niets meer; van Sabers 1729 nummers hebben er 299 een BPM-tag. Wat we wél hebben: elk bestand, en van
/// elk nummer bij Deezer een fragment van 30 seconden (dat haalt de versiecontrole al, `versiecontrole.dart`).
///
/// **Hoe.** Mono op 11025 Hz via ffmpeg; spectrale flux (venster 1024, stap 256 — 43 metingen per seconde), met
/// de bas tot ~250 Hz drie keer zo zwaar (de kickdrum draagt de tel); de langzame trend eraf; autocorrelatie van
/// 50 tot 220 BPM met een kam (de tel, en ook twee, drie en vier tellen verder) en een lichte voorkeur rond 120
/// (Ellis, 2007). Van een heel nummer drie vensters van 30 s (op 20, 45 en 70 %), opgeteld.
///
/// **Geijkt** op 22-10-2026 op de 154 nummers met een bruikbare BPM-tag: 81 % precies (±4 %), 7 % het dubbele of
/// de helft, 3 % 3:2, 10 % ernaast — waarvan een deel foute tags: Shape Of You staat op 129 (het is 96), The
/// Greatest op 192 (96). Petra — Ik Leef Voor Jou: 143,5. Zwakte: reggae meet hij dubbel (de afterbeat).
///
/// Een meter vergist zich dus soms met een factor twee. Daarom stuurt dit getal de radio niet alleen: het gaat als
/// gegeven mee naar het sfeeroordeel van het model, dat de nummers zelf ook kent.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'ffmpeg.dart';
import 'paths.dart';

/// Wat de meter zegt: het tempo, hoeveel aanslagen per seconde (dichtheid), en de energie (dB).
typedef Tempo = ({double bpm, double aanslagen, int energie});

const int kTempoSr = 11025;
const int _n = 1024, _hop = 256;
const double _fr = kTempoSr / _hop;

void _fft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final a = -2 * math.pi / len, wr = math.cos(a), wi = math.sin(a);
    final half = len >> 1;
    for (var i = 0; i < n; i += len) {
      var cr = 1.0, ci = 0.0;
      for (var k = 0; k < half; k++) {
        final ur = re[i + k], ui = im[i + k];
        final xr = re[i + k + half], xi = im[i + k + half];
        final vr = xr * cr - xi * ci, vi = xr * ci + xi * cr;
        re[i + k] = ur + vr;
        im[i + k] = ui + vi;
        re[i + k + half] = ur - vr;
        im[i + k + half] = ui - vi;
        final t = cr * wr - ci * wi;
        ci = cr * wi + ci * wr;
        cr = t;
      }
    }
  }
}

/// Eén venster: per BPM (50–220, stap 0,5) de score, genormaliseerd op de hoogste; plus aanslagen en energie.
/// Null als het venster korter is dan acht seconden.
({Map<double, double> scores, double aanslagen, double energie})? _venster(Float32List x) {
  final frames = (x.length - _n) ~/ _hop;
  if (frames < _fr * 8) return null;
  final venster = Float64List(_n);
  for (var i = 0; i < _n; i++) {
    venster[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / _n);
  }
  final flux = Float64List(frames);
  var vorige = Float64List(_n ~/ 2);
  var energie = 0.0;
  final re = Float64List(_n), im = Float64List(_n);
  for (var f = 0; f < frames; f++) {
    for (var i = 0; i < _n; i++) {
      final s = x[f * _hop + i];
      re[i] = s * venster[i];
      im[i] = 0;
      energie += s * s;
    }
    _fft(re, im);
    final mag = Float64List(_n ~/ 2);
    var som = 0.0;
    for (var k = 1; k < _n ~/ 2; k++) {
      mag[k] = math.log(1 + 1000 * math.sqrt(re[k] * re[k] + im[k] * im[k]));
      final d = mag[k] - vorige[k];
      // De bas tot ~250 Hz (k < 24 bij 11025/1024) telt drie keer: de kickdrum draagt de tel.
      if (d > 0) som += k < 24 ? 3 * d : d;
    }
    flux[f] = som;
    vorige = mag;
  }
  final w = _fr.round();
  final env = Float64List(frames);
  var lopend = 0.0;
  for (var f = 0; f < frames; f++) {
    lopend += flux[f] - (f >= w ? flux[f - w] : 0);
    final gem = lopend / math.min(f + 1, w);
    env[f] = math.max(0, flux[f] - gem);
  }
  double ac(double lag) {
    final l0 = lag.floor(), fr = lag - l0;
    if (l0 + 2 >= frames) return 0;
    var a = 0.0;
    for (var f = 0; f + l0 + 1 < frames; f++) {
      a += env[f] * (env[f + l0] * (1 - fr) + env[f + l0 + 1] * fr);
    }
    return a / (frames - l0);
  }

  final scores = <double, double>{};
  var hoogste = 0.0;
  for (var b = 100; b <= 440; b++) {
    final bpm = b / 2;
    final lag = 60 * _fr / bpm;
    var s = 0.0;
    for (var k = 1; k <= 4; k++) {
      s += ac(k * lag) / k;
    }
    final l = math.log(bpm / 120) / math.ln2 / 0.9;
    s *= math.exp(-0.5 * l * l);
    scores[bpm] = s;
    if (s > hoogste) hoogste = s;
  }
  if (hoogste > 0) {
    for (final k in scores.keys.toList()) {
      scores[k] = scores[k]! / hoogste;
    }
  }
  var gemEnv = 0.0;
  for (final v in env) {
    gemEnv += v;
  }
  gemEnv /= frames;
  var pieken = 0;
  for (var f = 1; f + 1 < frames; f++) {
    if (env[f] > 1.5 * gemEnv && env[f] >= env[f - 1] && env[f] > env[f + 1]) pieken++;
  }
  return (scores: scores, aanslagen: pieken / (frames / _fr), energie: energie / (frames * _n));
}

/// Het tempo van [x] (mono, [kTempoSr] Hz). Is het langer dan 100 s, dan drie vensters van 30 s op 20, 45 en 70 %;
/// anders het geheel. Null als er geen acht seconden zijn. Pure functie — zie de toetsen.
Tempo? meetTempo(Float32List x) {
  final duur = x.length / kTempoSr;
  final stukken = duur > 100
      ? [
          for (final f in const [0.2, 0.45, 0.7])
            Float32List.sublistView(
              x,
              (math.max(0, duur * f - 15) * kTempoSr).round(),
              math.min(x.length, ((math.max(0, duur * f - 15) + 30) * kTempoSr).round()),
            ),
        ]
      : [x];
  final som = <double, double>{};
  ({Map<double, double> scores, double aanslagen, double energie})? laatste;
  var aanslagen = 0.0, energie = 0.0, n = 0;
  for (final s in stukken) {
    final v = _venster(s);
    if (v == null) continue;
    laatste = v;
    n++;
    aanslagen += v.aanslagen;
    energie += v.energie;
    for (final e in v.scores.entries) {
      som[e.key] = (som[e.key] ?? 0) + e.value;
    }
  }
  if (laatste == null || som.isEmpty) return null;
  var best = som.keys.first;
  for (final e in som.entries) {
    if (e.value > som[best]!) best = e.key;
  }
  return (
    bpm: best,
    aanslagen: double.parse((aanslagen / n).toStringAsFixed(2)),
    energie: (10 * math.log(energie / n + 1e-12) / math.ln10).round(),
  );
}

/// [meetTempo] in een eigen isolate: een nummer van vier minuten is drie vensters FFT.
///
/// Op het hoogste niveau, en dat is geen smaak: een closure die in een methode van [Tempometer] gemaakt wordt, neemt
/// die mee naar de isolate, met zijn timer — en dan breekt het af ("unsendable", zie `hoes_in_bestand.dart`).
Future<Tempo?> meetTempoApart(Float32List x) => Isolate.run(() => meetTempo(x));

/// Meet bestanden en fragmenten, met een geheugen op schijf (`tempo.json`, per pad, grootte en datum).
class Tempometer {
  Tempometer({Ffmpeg? ffmpeg, String? geheugen})
    : _ffmpeg = ffmpeg ?? Ffmpeg(),
      _geheugenPad = geheugen ?? '$appDir${Platform.pathSeparator}tempo.json';

  final Ffmpeg _ffmpeg;
  final String _geheugenPad;
  Map<String, dynamic>? _geheugen;
  final Map<String, Future<Tempo?>> _bezig = {};

  bool get kan => _ffmpeg.available;

  Map<String, dynamic> _lees() {
    final al = _geheugen;
    if (al != null) return al;
    try {
      final f = File(_geheugenPad);
      if (f.existsSync()) {
        final j = jsonDecode(f.readAsStringSync());
        if (j is Map<String, dynamic>) return _geheugen = j;
      }
    } catch (_) {
      /* een kapot geheugen is een leeg geheugen */
    }
    return _geheugen = <String, dynamic>{};
  }

  Timer? _bewaarKlok;
  void _bewaar() {
    _bewaarKlok?.cancel();
    _bewaarKlok = Timer(const Duration(seconds: 2), () {
      try {
        File(_geheugenPad).writeAsStringSync(jsonEncode(_geheugen));
      } catch (_) {}
    });
  }

  /// Het tempo van het bestand op [pad], of null (geen ffmpeg, onleesbaar, te kort).
  Future<Tempo?> van(String pad) async {
    FileStat st;
    try {
      st = await File(pad).stat();
    } catch (_) {
      return null;
    }
    final sleutel = '${pad.toLowerCase()}|${st.size}|${st.modified.millisecondsSinceEpoch}';
    final al = _lees()[sleutel];
    if (al is Map) {
      return (
        bpm: (al['b'] as num).toDouble(),
        aanslagen: (al['a'] as num).toDouble(),
        energie: (al['e'] as num).toInt(),
      );
    }
    return _bezig[sleutel] ??= _meet(pad).then((t) {
      _bezig.remove(sleutel);
      if (t != null) {
        _lees()[sleutel] = {'b': t.bpm, 'a': t.aanslagen, 'e': t.energie};
        _bewaar();
      }
      return t;
    });
  }

  Future<Tempo?> _meet(String pad) async {
    final ff = _ffmpeg.pad;
    if (ff == null) return null;
    try {
      final r = await Process.run(ff, [
        '-v',
        'error',
        '-i',
        pad,
        '-ac',
        '1',
        '-ar',
        '$kTempoSr',
        '-f',
        'f32le',
        '-',
      ], stdoutEncoding: null);
      if (r.exitCode != 0) return null;
      final bytes = r.stdout as List<int>;
      final b = Uint8List.fromList(bytes);
      final x = Float32List.view(b.buffer, 0, b.lengthInBytes ~/ 4);
      return await meetTempoApart(x);
    } catch (_) {
      return null;
    }
  }
}

/// Het tempo van een nummer voor de radio: uit het bestand als dat er is, anders uit het Deezer-fragment van 30 s
/// (gemeten op 22-10-2026: bij 49 van 56 nummers hetzelfde tempo als het hele bestand, nooit een factor twee).
class Radiotempo {
  Radiotempo({required this.meter, required this.fragment});

  final Tempometer meter;

  /// Het fragment van dit nummer (`Versiecontrole.fragment`), of null.
  final Future<String?> Function(String artiest, String titel, int? seconden) fragment;

  Future<double?> van(String artiest, String titel, {String? pad, int? seconden}) async {
    if (!meter.kan) return null;
    try {
      final p = pad != null && pad.isNotEmpty && File(pad).existsSync() ? pad : await fragment(artiest, titel, seconden);
      if (p == null) return null;
      return (await meter.van(p))?.bpm;
    } catch (_) {
      return null;
    }
  }

  /// Van een hele rij, [tegelijk] tegelijk — in dezelfde volgorde terug.
  Future<List<double?>> vanRij(List<({String artiest, String titel, String? pad, int? seconden})> rij,
      {int tegelijk = 4}) async {
    final uit = List<double?>.filled(rij.length, null);
    var volgende = 0;
    Future<void> werker() async {
      while (volgende < rij.length) {
        final i = volgende++;
        final r = rij[i];
        uit[i] = await van(r.artiest, r.titel, pad: r.pad, seconden: r.seconden);
      }
    }

    await Future.wait([for (var k = 0; k < tegelijk; k++) werker()]);
    return uit;
  }
}

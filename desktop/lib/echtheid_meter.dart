/// De meting zelf: ffmpeg draaien, de samples binnenhalen, en [oordeelVol] laten spreken.
///
/// Vorm van [Fingerprinter] in fingerprint.dart, en om dezelfde redenen: `available` om vooraf te
/// vragen, een cache op (pad, grootte, wijzigingsmoment), en **nooit hard falen**. Een meting is een
/// verrijking; niets in deze app mag stukgaan omdat een verrijking dat deed.
///
/// **Het hele bestand, beide kanalen** (20-10-2026). Dit nam drie grepen van vier seconden uit één
/// kanaal, en dat gaf op Sabers bibliotheek ~180 verkeerde antwoorden — zie echtheid.dart. Nu decodeert
/// ffmpeg alles van begin tot eind, en in dezelfde stroom:
///   * de OR van ALLE samples (proef A, rekenkundig zeker);
///   * de MD5 van de samples tegen die in de FLAC-kop (RFC 9639): bit-voor-bit-bewijs van beschadiging;
///   * tot 700 vensters per kanaal, verspreid over het hele nummer, als spectrum in 50 Hz-banden.
/// Het rekenwerk draait in een eigen isolate, zodat het scherm niet hapert; het ffmpeg-proces meldt zijn
/// nummer terug ([van] `opStart`), zodat wissen en verplaatsen hem kunnen afbreken.
///
/// WAAROM NIET `astats`: het uitvoerformaat verandert per ffmpeg-versie en het gaat naar stderr tussen
/// andere regels door. De samples zelf inspecteren is exacter, en de PCM is er toch voor de FFT.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'echtheid.dart';
import 'ffmpeg.dart';
import 'fft.dart';

/// Vensters van 8192 met Hann: zo is de meting geijkt (echtheid.dart). Bij 44,1 kHz is een bin 5,4 Hz.
const int _vensterN = 8192;

/// Hoeveel vensters per kanaal hoogstens, gelijk verdeeld over het nummer.
const int _maxVensters = 700;

/// Banden van 50 Hz voor het opgeslagen spectrum.
const double _bandHz = 50;

/// Een meting die niet binnen deze tijd klaar is, wordt afgebroken (een uur durende DJ-mix in 32/192).
const Duration _tijdslimiet = Duration(minutes: 5);

/// De STREAMINFO uit de FLAC-kop: kanalen, bits, het aantal samples en de MD5 van de samples.
///
/// Zoekt "fLaC" in de eerste megabyte: een ID3-tag ervoor is niet volgens de standaard maar komt voor
/// (gemeten op 20-10-2026 bij David Guetta, Dr. Alban, Sean Paul); wie alleen op byte 0 keek, vond de kop
/// niet en zou een controlesom "fout" noemen die gewoon klopt.
({int sr, int kanalen, int bps, int totaal, String md5})? leesStreaminfo(String pad) {
  RandomAccessFile? f;
  try {
    f = File(pad).openSync();
    final kop = f.readSync(1 << 20);
    var p = -1;
    for (var i = 0; i + 4 <= kop.length; i++) {
      if (kop[i] == 0x66 && kop[i + 1] == 0x4C && kop[i + 2] == 0x61 && kop[i + 3] == 0x43) {
        p = i;
        break;
      }
    }
    if (p < 0 || p + 42 > kop.length || (kop[p + 4] & 0x7f) != 0) return null;
    final s = Uint8List.sublistView(kop, p + 8, p + 8 + 34);
    final sr = (s[10] << 12) | (s[11] << 4) | (s[12] >> 4);
    final kanalen = ((s[12] >> 1) & 0x07) + 1;
    final bps = (((s[12] & 0x01) << 4) | (s[13] >> 4)) + 1;
    final totaal = (s[13] & 0x0f) * 4294967296 + ByteData.sublistView(s).getUint32(14);
    final md5 = [for (final b in s.sublist(18, 34)) b.toRadixString(16).padLeft(2, '0')].join();
    return (sr: sr, kanalen: kanalen, bps: bps, totaal: totaal, md5: md5);
  } catch (_) {
    return null;
  } finally {
    f?.closeSync();
  }
}

class Echtheidsmeter {
  /// [cacheMap] wordt door de app op `appDir/echtheid` gezet. Bewust een parameter en geen import van
  /// `paths.dart`: die trekt Flutter mee, en dan is dit bestand niet meer met een kaal `dart run` te
  /// draaien — precies wat het kalibratiescript nodig heeft.
  Echtheidsmeter({String? ffmpegPad, this.cacheMap}) : _ffmpeg = Ffmpeg(pad: ffmpegPad);
  final Ffmpeg _ffmpeg;
  final String? cacheMap;

  bool get available => _ffmpeg.available;

  Future<File?> _cacheBestand(String pad) async {
    final map = cacheMap;
    if (map == null) return null;
    try {
      final f = File(pad);
      final st = await f.stat();
      // De versie in de sleutel: een uitslag van de oude meting wordt niet meer gelezen.
      final sleutel = sha1
          .convert(utf8.encode('$pad|${st.size}|${st.modified.millisecondsSinceEpoch}|v$echtheidsVersie'))
          .toString();
      return File('$map${Platform.pathSeparator}$sleutel.json');
    } catch (_) {
      return null;
    }
  }

  /// Meet [pad]. Geeft `null` als er niets te meten viel — nooit een uitzondering.
  ///
  /// [opStart] krijgt het procesnummer van ffmpeg, zodat wie een bestand wil wissen of verplaatsen hem
  /// kan afbreken ([Process.killPid]): Windows houdt een bestand vast zolang ffmpeg het open heeft.
  Future<Echtheidsoordeel?> van(
    String pad, {
    required int kopSampleRate,
    required int kopBits,
    required double duurSeconden,
    bool gebruikCache = true,
    void Function(int pid)? opStart,
  }) async {
    try {
      final cache = await _cacheBestand(pad);
      if (gebruikCache && cache != null && await cache.exists()) {
        final j = jsonDecode(await cache.readAsString());
        if (j is Map<String, dynamic>) {
          final uit = Echtheidsoordeel.fromJson(j);
          if (uit != null) return uit;
        }
      }

      final uit = await _meet(pad,
          kopSampleRate: kopSampleRate, kopBits: kopBits, duurSeconden: duurSeconden, opStart: opStart);
      if (uit != null && cache != null) {
        try {
          await cache.parent.create(recursive: true);
          await cache.writeAsString(jsonEncode(uit.toJson()));
        } catch (_) {/* bewaren is mooi meegenomen, niet noodzakelijk */}
      }
      return uit;
    } catch (e) {
      laatsteFout = '$pad: $e';
      return null;
    }
  }

  /// Waar de laatste meting op stukliep. Nooit stil falen — zie `WarmLog.laatsteFout`.
  static String? laatsteFout;

  Future<Echtheidsoordeel?> _meet(
    String pad, {
    required int kopSampleRate,
    required int kopBits,
    required double duurSeconden,
    void Function(int pid)? opStart,
  }) async {
    final exe = _ffmpeg.pad;
    if (exe == null) return null;
    // Te kort voor een betrouwbare vloer, en onder 44,1 kHz degenereert elke drempel.
    if (duurSeconden < 30 || kopSampleRate < 44100) return null;

    final antwoord = ReceivePort();
    final fout = ReceivePort();
    final klaar = Completer<Object?>();
    late final StreamSubscription<Object?> luister;
    luister = antwoord.listen((m) {
      if (m is int) {
        opStart?.call(m);
      } else if (!klaar.isCompleted) {
        klaar.complete(m);
      }
    });
    fout.listen((m) {
      if (!klaar.isCompleted) klaar.complete({'fout': '$m'});
    });
    try {
      await Isolate.spawn(
        _meetInIsolate,
        [antwoord.sendPort, exe, pad, kopSampleRate, kopBits, duurSeconden],
        onError: fout.sendPort,
        onExit: fout.sendPort,
      );
      final m = await klaar.future.timeout(_tijdslimiet + const Duration(seconds: 30), onTimeout: () => null);
      if (m is! Map) return null;
      if (m['fout'] != null) {
        laatsteFout = '$pad: ${m['fout']}';
        return null;
      }
      return Echtheidsoordeel.fromJson(Map<String, dynamic>.from(m['oordeel'] as Map));
    } finally {
      await luister.cancel();
      antwoord.close();
      fout.close();
    }
  }
}

/// In de isolate: decodeert het hele bestand en stuurt eerst het procesnummer, dan het oordeel terug.
Future<void> _meetInIsolate(List<Object?> args) async {
  final terug = args[0] as SendPort;
  try {
    final r = await meetHeelBestand(
      exe: args[1] as String,
      pad: args[2] as String,
      kopSampleRate: args[3] as int,
      kopBits: args[4] as int,
      duurSeconden: args[5] as double,
      opStart: terug.send,
    );
    terug.send(r == null ? {'fout': 'niets te meten'} : {'oordeel': r.toJson()});
  } catch (e) {
    terug.send({'fout': '$e'});
  }
}

/// Meldingen van ffmpeg over de hoes of andere metadata: zeggen niets over de audio. Gemeten op
/// 20-10-2026: "Attached picture metadata block too short", "not enough bytes remaining in EXIF".
final _metadataMelding = RegExp(r'Attached picture|mjpeg|EXIF|mimetype|png @|Last message repeated', caseSensitive: false);

/// De meting zelf, zonder isolate (en dus ook los te toetsen met een echt bestand).
Future<Echtheidsoordeel?> meetHeelBestand({
  required String exe,
  required String pad,
  required int kopSampleRate,
  required int kopBits,
  required double duurSeconden,
  void Function(int pid)? opStart,
}) async {
  final info = leesStreaminfo(pad);
  // Zonder FLAC-kop weten we het aantal kanalen niet: dan het eerste kanaal letterlijk, nooit een
  // downmix — L+R kan hoge inhoud in tegenfase uitdoven en dan meet je een afkap die er niet is.
  final kanalen = info?.kanalen ?? 1;
  final bps = info?.bps ?? (kopBits > 0 ? kopBits : 16);
  final sr = info?.sr ?? kopSampleRate;
  if (sr < 44100) return null;
  final verwachtFrames = info != null && info.totaal > 0 ? info.totaal : (duurSeconden * sr).round();
  final metMd5 = info != null && info.md5 != '00000000000000000000000000000000';

  final p = await Process.start(exe, [
    '-hide_banner', '-v', 'error', '-nostdin', //
    '-i', pad, '-map', '0:a:0',
    if (info == null) ...['-af', 'pan=mono|c0=c0'],
    // NOOIT `-ar`: dat zet ffmpegs resampler aan, die een muur op 22,05 kHz legt.
    '-f', 's32le', '-acodec', 'pcm_s32le', '-',
  ]);
  opStart?.call(p.pid);
  final meldingen = <String>[];
  final err = p.stderr.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen((l) {
    if (meldingen.length < 40 && l.trim().isNotEmpty) meldingen.add(l.trim());
  });

  // De MD5 over de samples in hun eigen breedte, zoals de encoder hem rekende.
  final md5Uit = _DigestVanger();
  final md5In = md5.startChunkedConversion(md5Uit);
  final bytesPer = (bps + 7) ~/ 8;
  final schuif = 32 - bps;
  final nat = Uint8List(1 << 20);
  var np = 0;

  var masker = 0, nietNul = 0, frames = 0;
  final stride = math.max(_vensterN, verwachtFrames ~/ _maxVensters);
  var volgendeStart = math.max(0, stride ~/ 2 - _vensterN ~/ 2);
  var inVenster = -1;
  final buf = [for (var c = 0; c < kanalen; c++) Float64List(_vensterN)];
  final hann = Float64List(_vensterN);
  for (var i = 0; i < _vensterN; i++) {
    hann[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (_vensterN - 1));
  }
  final nBanden = (sr / 2 / _bandHz).floor();
  final binsPerBand = _bandHz / (sr / _vensterN);
  final re = Float64List(_vensterN), im = Float64List(_vensterN);
  final vensterRms = <double>[];
  final vensterBanden = <List<Float32List>>[];

  void sluitVenster() {
    var rmsSom = 0.0;
    final banden = <Float32List>[];
    for (var c = 0; c < kanalen; c++) {
      final x = buf[c];
      for (var i = 0; i < _vensterN; i++) {
        rmsSom += x[i] * x[i];
        re[i] = x[i] * hann[i];
        im[i] = 0;
      }
      fft(re, im);
      final b = Float32List(nBanden);
      for (var k = 0; k < nBanden; k++) {
        final a = (k * binsPerBand).round(), z = math.min(((k + 1) * binsPerBand).round(), _vensterN ~/ 2 + 1);
        var s = 0.0;
        for (var i = a; i < z; i++) {
          s += re[i] * re[i] + im[i] * im[i];
        }
        b[k] = dB(s / math.max(1, z - a) + 1e-30);
      }
      banden.add(b);
    }
    vensterRms.add(dB(rmsSom / (_vensterN * kanalen) + 1e-30));
    vensterBanden.add(banden);
  }

  var rest = Uint8List(0);
  final frameBytes = 4 * kanalen;
  final klaar = p.stdout.listen((stuk) {
    final data = rest.isEmpty ? Uint8List.fromList(stuk) : (BytesBuilder(copy: false)..add(rest)..add(stuk)).takeBytes();
    final heel = data.length - data.length % frameBytes;
    rest = Uint8List.fromList(data.sublist(heel));
    final bd = ByteData.sublistView(data, 0, heel);
    final n = heel ~/ 4;
    for (var i = 0; i < n; i++) {
      final v = bd.getInt32(i * 4, Endian.little);
      masker |= v;
      if (v != 0) nietNul++;
      if (metMd5) {
        final w = v >> schuif;
        for (var b = 0; b < bytesPer; b++) {
          nat[np++] = (w >> (8 * b)) & 0xff;
        }
        if (np > nat.length - 8) {
          md5In.add(Uint8List.fromList(nat.sublist(0, np)));
          np = 0;
        }
      }
      final c = i % kanalen;
      if (c == 0 && inVenster < 0 && frames + i ~/ kanalen >= volgendeStart) inVenster = 0;
      if (inVenster >= 0) {
        buf[c][inVenster] = v / 2147483648.0;
        if (c == kanalen - 1 && ++inVenster == _vensterN) {
          sluitVenster();
          inVenster = -1;
          volgendeStart += stride;
        }
      }
    }
    if (metMd5 && np > 0) {
      md5In.add(Uint8List.fromList(nat.sublist(0, np)));
      np = 0;
    }
    frames += n ~/ kanalen;
  }).asFuture<void>();

  final code = await p.exitCode.timeout(_tijdslimiet, onTimeout: () {
    p.kill();
    return -1;
  });
  await klaar.timeout(const Duration(seconds: 10), onTimeout: () {});
  await err.cancel();
  if (code == -1) return null;
  md5In.close();

  // ── Integriteit: alleen wat bewezen is ──
  final audioMeldingen = [for (final m in meldingen) if (!_metadataMelding.hasMatch(m)) m];
  final teKort = verwachtFrames > 0 && frames < verwachtFrames - sr;
  var integriteit = Integriteit.onbekend;
  if (metMd5) {
    integriteit = md5Uit.digest?.toString() == info.md5 ? Integriteit.klopt : Integriteit.fout;
  } else if (info != null) {
    integriteit = Integriteit.geenControlesom;
  }
  if (teKort || (integriteit != Integriteit.klopt && audioMeldingen.isNotEmpty && frames < verwachtFrames)) {
    integriteit = Integriteit.fout;
  }

  // ── Het spectrum over de luide vensters (boven de mediaan, niet stil) ──
  var gebruikt = 0;
  if (masker != 0) {
    var m = masker, nul = 0;
    while (m & 1 == 0) {
      m >>= 1;
      nul++;
    }
    gebruikt = 32 - nul;
  }
  final gesorteerd = [...vensterRms]..sort();
  final mediaan = gesorteerd.isEmpty ? -300.0 : gesorteerd[gesorteerd.length ~/ 2];
  final luid = [
    for (var i = 0; i < vensterRms.length; i++)
      if (vensterRms[i] >= mediaan && vensterRms[i] > -60) vensterBanden[i],
  ];
  final gemiddeld = Float64List(nBanden), p95 = Float64List(nBanden);
  if (luid.isNotEmpty) {
    final kolom = Float64List(luid.length * kanalen);
    for (var k = 0; k < nBanden; k++) {
      var s = 0.0, j = 0;
      for (final v in luid) {
        for (var c = 0; c < kanalen; c++) {
          final d = v[c][k];
          s += math.pow(10, d / 10);
          kolom[j++] = d;
        }
      }
      gemiddeld[k] = dB(s / (luid.length * kanalen));
      kolom.sort();
      p95[k] = kolom[(kolom.length * 0.95).floor().clamp(0, kolom.length - 1)];
    }
  }

  return oordeelVol(
    s: Spectrumstaat(sampleRate: sr, bandHz: _bandHz, gemiddeld: gemiddeld, p95: p95, luid: luid.length * kanalen),
    kopSampleRate: kopSampleRate > 0 ? kopSampleRate : sr,
    kopBits: kopBits > 0 ? kopBits : bps,
    gebruikteBits: gebruikt,
    nietNulSamples: nietNul,
    integriteit: integriteit,
  );
}

/// Vangt de ene [Digest] die `md5.startChunkedConversion` aan het eind aflevert.
class _DigestVanger implements Sink<Digest> {
  Digest? digest;
  @override
  void add(Digest data) => digest = data;
  @override
  void close() {}
}

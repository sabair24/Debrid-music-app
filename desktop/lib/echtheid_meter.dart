/// De meting zelf: ffmpeg draaien, de samples binnenhalen, en [oordeel] laten spreken.
///
/// Vorm van [Fingerprinter] in fingerprint.dart, en om dezelfde redenen: `available` om vooraf te
/// vragen, een cache op (pad, grootte, wijzigingsmoment), en **nooit hard falen**. Een meting is een
/// verrijking; niets in deze app mag stukgaan omdat een verrijking dat deed.
///
/// WAAROM NIET `astats`, dat dit deels gratis zou geven: het uitvoerformaat verandert per ffmpeg-versie
/// ("Bit depth: 16" werd "16/16"), het gaat naar stderr tussen andere regels door, het decodeert het
/// HELE bestand, en een stderr-parser is alleen te toetsen tegen de ffmpeg die toevallig op deze pc
/// staat. De samples zelf inspecteren is exacter, sneller, en de PCM hebben we toch al nodig voor de FFT.
/// Eén decode, twee proeven.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'echtheid.dart';
import 'ffmpeg.dart';
import 'fft.dart';

/// Hoeveel seconden per greep, en waar in het nummer.
///
/// Drie losse grepen in plaats van één lang stuk: één aaneengesloten fragment kan volledig in een stille
/// passage vallen, en dan is er niets te meten. Drie processtarts kosten ongeveer 150 ms; het hele
/// bestand decoderen kost op een grote FLAC meer.
const int _seconden = 4;
const List<double> _grepen = [0.25, 0.5, 0.75];

/// Van alle vensters alleen de luide, want een afkap is alleen zichtbaar waar signaal is.
const double _luidheidsmargeDb = 12;
const int _maxVensters = 32, _minVensters = 8;
const int _vensterN = 4096;

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
      final sleutel =
          sha1.convert(utf8.encode('$pad|${st.size}|${st.modified.millisecondsSinceEpoch}')).toString();
      return File('$map${Platform.pathSeparator}$sleutel.json');
    } catch (_) {
      return null;
    }
  }

  /// Meet [pad]. Geeft `null` als er niets te meten viel — nooit een uitzondering.
  Future<Echtheidsoordeel?> van(
    String pad, {
    required int kopSampleRate,
    required int kopBits,
    required double duurSeconden,
    bool gebruikCache = true,
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
          kopSampleRate: kopSampleRate, kopBits: kopBits, duurSeconden: duurSeconden);
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
  }) async {
    final exe = _ffmpeg.pad;
    if (exe == null) return null;
    // Te kort om drie grepen uit te nemen, en te kort voor een betrouwbare vloer.
    if (duurSeconden < 30 || kopSampleRate < 44100) return null;

    final blokken = <Float64List>[];
    var nietNul = 0;
    var masker = 0;

    for (final deel in _grepen) {
      final start = (duurSeconden * deel).clamp(0, duurSeconden - _seconden - 1);
      final r = await Process.run(
        exe,
        [
          '-hide_banner', '-loglevel', 'error', '-nostdin',
          '-ss', start.toStringAsFixed(2),
          '-t', '$_seconden',
          '-i', pad,
          // Eén kanaal LETTERLIJK overnemen, geen downmix: L+R kan hoge inhoud in tegenfase uitdoven
          // en dan meet je een afkap die er niet is.
          '-af', 'pan=mono|c0=c0',
          // NOOIT `-ar` meegeven. Dat zet ffmpegs eigen resampler aan, die een muur op 22,05 kHz legt —
          // en dan meldt de app élk hi-res bestand als nep. De gevaarlijkste val in dit hele bestand.
          '-f', 's32le', '-',
        ],
        stdoutEncoding: null,
        stderrEncoding: null,
      );
      if (r.exitCode != 0) continue;
      final bytes = r.stdout as List<int>;
      // Zelfcontrole zonder ffprobe: klopt het aantal bytes niet met de kop, dan is er hersampeld of
      // liegt de kop. Dan liever geen oordeel dan een verkeerd oordeel.
      final verwacht = _seconden * kopSampleRate * 4;
      if (bytes.length < verwacht * 0.9) continue;

      final samples = Int32List.view(
          Uint8List.fromList(bytes).buffer, 0, bytes.length ~/ 4);
      for (final s in samples) {
        if (s != 0) {
          nietNul++;
          masker |= s;
        }
      }
      for (var i = 0; i + _vensterN <= samples.length; i += _vensterN) {
        final blok = Float64List(_vensterN);
        for (var k = 0; k < _vensterN; k++) {
          blok[k] = samples[i + k] / 2147483648.0;
        }
        blokken.add(blok);
      }
    }

    if (blokken.isEmpty) return null;

    // Alleen de luide vensters: waar niets klinkt valt niets af te kappen.
    final rms = <double>[];
    for (final b in blokken) {
      var som = 0.0;
      for (final v in b) {
        som += v * v;
      }
      rms.add(dB(som / b.length));
    }
    final luidste = rms.reduce((a, b) => a > b ? a : b);
    final gekozen = <Float64List>[];
    for (var i = 0; i < blokken.length && gekozen.length < _maxVensters; i++) {
      if (luidste - rms[i] <= _luidheidsmargeDb) gekozen.add(blokken[i]);
    }
    if (gekozen.length < _minVensters) return null;

    var gebruikte = 0;
    if (masker != 0) {
      var m = masker, nullen = 0;
      while (m & 1 == 0) {
        m >>= 1;
        nullen++;
      }
      gebruikte = 32 - nullen;
    }

    final spec = gemiddeldVermogensspectrum(gekozen, blackmanHarris(_vensterN));
    return oordeel(
      spectrum: spec,
      sampleRate: kopSampleRate,
      kopSampleRate: kopSampleRate,
      kopBits: kopBits,
      gebruikteBits: gebruikte,
      vensters: gekozen.length,
      nietNulSamples: nietNul,
    );
  }
}

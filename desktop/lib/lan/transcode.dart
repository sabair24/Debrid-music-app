import 'dart:io';

import '../uitvoerbaar.dart';

import 'package:flutter/foundation.dart';

/// Converts a track on the fly when a speaker cannot take the original.
///
/// This exists for one reason: **Sonos plays FLAC to 24 bit but only to 48 kHz, and skips a file
/// above that instead of downsampling it.** No error is raised anywhere — the track simply does
/// not play, and a hi-res album goes quiet song by song. Converting to 24/48 keeps the best
/// quality Sonos will actually accept.
///
/// Only ever used for a speaker with a stated ceiling. The Shield, the KEF and this app all get
/// the untouched file.
/// Hoe er omgezet wordt: welke vlaggen bij welk doel horen.
///
/// **Waarom dit een ding is en geen paar losse parameters.** Er zijn nu twee afnemers van dezelfde
/// omzetter met tegengestelde wensen. Een speaker krijgt een weggooikopie en wil hem SNEL; een
/// telefoon op mobiele data wil hem KLEIN en bewaart hem even. Die twee met één set vlaggen
/// bedienen betekent dat de een altijd de verkeerde krijgt.
///
/// De [naam] gaat mee in de cachesleutel. Zonder dat zou een wijziging aan de vlaggen hieronder
/// stilzwijgend oude bestanden blijven serveren die met de vórige vlaggen gemaakt zijn — en dat is
/// precies het soort fout dat maanden meegaat.
class Omzetrecept {
  const Omzetrecept({required this.naam, required this.compressie, required this.bewaar});

  /// Kort, en uniek per set vlaggen. Gaat in de cachesleutel.
  final String naam;

  /// FLAC-compressieniveau. Hoger is kleiner en trager.
  final int compressie;

  /// Hoeveel omgezette bestanden er in deze map bewaard blijven.
  final int bewaar;
}

/// Voor een speaker: snelheid boven grootte, want de kopie wordt na het spelen weggegooid.
const receptCast = Omzetrecept(naam: 'c0', compressie: 0, bewaar: 24);

/// Voor een gekoppeld toestel: grootte boven snelheid, want elke byte gaat over iemands databundel.
///
/// Niveau 5 scheelt tegenover 0 ruwweg acht tot twaalf procent, en dat is precies waar deze stroom
/// voor bestaat. Meer bewaren dan bij cast, want dit is een ALBUM dat iemand aan het luisteren is en
/// niet één nummer op een speaker: vierentwintig is minder dan één plaat.
const receptStroom = Omzetrecept(naam: 's5', compressie: 5, bewaar: 60);

/// De opdracht voor ffmpeg. Zuiver, want hier zitten de fouten die je pas op het toestel hoort.
///
/// **`-sample_fmt` volgt de bitdiepte, en dat is een reparatie.** Hier stond altijd `s32`, met een
/// commentaar dat zelf al waarschuwde dat die vlag alleen zegt in welk vak de monsters staan. Voor
/// een speaker maakte dat niets uit — dat pad ging nooit onder 24 bit. Voor de cd-stand van de
/// stroom wél: de FLAC-codeerder leidt de opgeslagen diepte af uit het monsterformaat, dus met
/// `s32` schrijf je een 24-bits stroom waar `-bits_per_raw_sample 16` niets aan verandert. Je
/// stuurt dan ruwweg anderhalf keer te veel bytes onder het etiket "16 bit".
///
/// **Dither, en alleen bij het zakken naar 16 bit.** 24 naar 16 zonder dither is afkappen, en dat
/// hoor je in stille passages als korrel. `triangular_hp` is de gebruikelijke keuze en kost niets.
/// Boven 16 bit heeft het geen zin en blijft het weg.
///
/// **Gewone `aresample` en NIET `resampler=soxr`.** Veel ffmpeg-bouwsels komen zonder soxr, en er
/// dan om vragen laat de hele filterketen mislukken: "Requested resampling engine is unavailable",
/// niets geschreven, en een lege stroom bij de speaker.
///
/// **`-f flac` is niet optioneel.** ffmpeg kiest de doos op de EXTENSIE van het uitvoerbestand, en
/// die is hier `.tmp` — een naam die hij niet kent. Zonder deze regel stopt hij met "Unable to
/// choose an output format" en schrijft hij niets. Gemeten op deze pc: exitcode 127 zonder, 0 met.
List<String> omzetArgumenten({
  required String bronPad,
  required String doelPad,
  required int maxSampleRate,
  required int maxBits,
  required Omzetrecept recept,
}) {
  final naarZestien = maxBits <= 16;
  final keten = StringBuffer('aresample=$maxSampleRate:filter_size=256');
  if (naarZestien) keten.write(':out_sample_fmt=s16:dither_method=triangular_hp');
  return [
    '-hide_banner', '-loglevel', 'error',
    '-y',
    '-i', bronPad,
    '-af', keten.toString(),
    '-sample_fmt', naarZestien ? 's16' : 's32',
    // De bitdiepte UITSPREKEN in plaats van ffmpeg hem laten kiezen.
    '-bits_per_raw_sample', '$maxBits',
    '-c:a', 'flac',
    '-compression_level', '${recept.compressie}',
    '-f', 'flac',
    doelPad,
  ];
}

class Transcoder {
  Transcoder({String? ffmpegPath}) : _explicitPath = ffmpegPath;

  final String? _explicitPath;
  String? _resolved;
  bool _looked = false;

  /// Where ffmpeg is, or null when it isn't installed.
  String? get path {
    if (_looked) return _resolved;
    _looked = true;
    _resolved = _explicitPath ?? _find();
    return _resolved;
  }

  bool get available => path != null;

  static String? _find() {
    final candidates = Platform.isWindows
        ? const [
            r'ffmpeg.exe',
            r'C:\Program Files\ffmpeg\bin\ffmpeg.exe',
            r'C:\ffmpeg\bin\ffmpeg.exe',
          ]
        : const ['/opt/homebrew/bin/ffmpeg', '/usr/local/bin/ffmpeg', '/usr/bin/ffmpeg', 'ffmpeg'];
    for (final candidate in candidates) {
      try {
        final echt = uitvoerbaarPad(candidate);
        if (echt == null) continue;
        final result = Process.runSync(echt, ['-version']);
        if (result.exitCode == 0) return echt;
      } catch (_) {/* not there — try the next */}
    }
    return null;
  }

  /// Convert [file] to a FILE at [maxSampleRate], and hand back where it landed.
  ///
  /// A file, not a pipe, and that is the whole point. Measured against the Sonos Amp in the living
  /// room on 2026-08-08: piped through `resample` the speaker accepts the URL, reports PLAYING, and
  /// its reported track length keeps creeping up (0:21, 0:26, ...) while the position never leaves
  /// 0:00:00. It never renders a note. The same speaker plays an ordinary 44.1 kHz file from the
  /// same server perfectly, position advancing 0:04, 0:09, 0:14 — so it is not the network, the
  /// token, the address or the metadata.
  ///
  /// The difference is the shape of the response. A pipe has no Content-Length, so the server sends
  /// it chunked, and FLAC coming out of a pipe carries an unknown sample count in its header. Sonos
  /// reads that as an endless radio stream. Written to disk first, the file has a length, a real
  /// header, and Range support — and it plays.
  ///
  /// The cost is honest: the first play of a hi-res track waits for the conversion, which at
  /// compression level 0 is a second or two. The second play is instant, because the result is
  /// kept. Cheaper than a track that never plays.
  Future<File?> resampleToFile(File file,
      {required int maxSampleRate,
      required Directory cacheDir,
      int maxBits = 24,
      Omzetrecept recept = receptCast}) {
    final naam = '${_sleutel(file, maxSampleRate, maxBits, recept)}.flac';
    final uit = File('${cacheDir.path}${Platform.pathSeparator}$naam');
    // Al omgezet, en geen restant van een half afgebroken poging.
    if (uit.existsSync() && uit.lengthSync() > 1024) return Future.value(uit);
    // **Eén omzetting tegelijk per uitkomst.**
    //
    // Zodra er twee vragers voor hetzelfde bestand zijn — en die komen er: mpv doet een verkennend
    // verzoek vóór het echte, en de speler zet het volgende nummer vast klaar — startten hier twee
    // ffmpegs die naar dezelfde tijdelijke naam schrijven en allebei hernoemen. De uitkomst is
    // beschadigd geluid dat zich nooit laat herhalen. Wie als tweede komt, wacht op de eerste.
    final lopend = _bezig[uit.path];
    if (lopend != null) return lopend;
    final werk = _zetOm(file, uit, maxSampleRate, maxBits, recept, cacheDir)
        .whenComplete(() => _bezig.remove(uit.path));
    _bezig[uit.path] = werk;
    return werk;
  }

  /// Wat er loopt, op uitvoerpad. Zie [resampleToFile].
  final Map<String, Future<File?>> _bezig = {};

  /// Oplopend, zodat twee omzettingen nooit dezelfde tijdelijke naam kiezen.
  static int _teller = 0;

  Future<File?> _zetOm(File file, File uit, int maxSampleRate, int maxBits, Omzetrecept recept,
      Directory cacheDir) async {
    final ffmpeg = path;
    if (ffmpeg == null) return null;
    try {
      if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
      final tijdelijk = File('${uit.path}.${pid}_${_teller++}.tmp');
      final result = await Process.run(
          ffmpeg,
          omzetArgumenten(
            bronPad: file.path,
            doelPad: tijdelijk.path,
            maxSampleRate: maxSampleRate,
            maxBits: maxBits,
            recept: recept,
          ));
      if (result.exitCode != 0 || !tijdelijk.existsSync()) {
        debugPrint('ffmpeg kon niet omzetten: ${result.stderr}');
        if (tijdelijk.existsSync()) tijdelijk.deleteSync();
        return null;
      }
      // Hernoemen als laatste, zodat een half geschreven bestand nooit voor een af bestand doorgaat.
      tijdelijk.renameSync(uit.path);
      _snoei(cacheDir, recept.bewaar);
      return uit;
    } catch (e) {
      debugPrint('omzetten mislukt: $e');
      return null;
    }
  }

  /// Zelfde bron, zelfde plafond en zelfde recept geeft hetzelfde bestand — dus opzoeken in plaats
  /// van opnieuw maken.
  ///
  /// **Het recept hoort erin.** Er zijn nu twee sets vlaggen (zie [Omzetrecept]), en zonder de naam
  /// in de sleutel zou een omzetting die voor de speaker gemaakt is doorgaan voor eentje voor de
  /// telefoon. Ook een toekomstige wijziging aan de vlaggen valt er dan buiten: je blijft dan tot in
  /// lengte van dagen bestanden serveren die met de oude vlaggen gemaakt zijn.
  ///
  /// **En de wijzigingstijd, niet alleen de grootte.** FLAC houdt met opzet een PADDING-blok vrij
  /// zodat het hertaggen van een bestand de bytelengte gelijk kan laten. Op grootte alleen zou een
  /// hernoemd album dus de oude omzetting terugkrijgen, met de oude labels erin.
  static String _sleutel(File file, int rate, int bits, Omzetrecept recept) {
    final st = file.statSync();
    return '${recept.naam}_${file.path.hashCode.toUnsigned(32).toRadixString(16)}'
        '_${st.size}_${st.modified.millisecondsSinceEpoch}_${rate}_$bits';
  }

  /// De nieuwste [bewaar] omzettingen houden en de rest weggooien.
  ///
  /// Een omgezet 24/48-nummer is tientallen megabytes en dit zijn kopieën; zonder grens vult een
  /// lange luisteravond stilletjes de schijf waar de muziek op staat. Hoeveel er blijven staan hangt
  /// af van waarvoor ze gemaakt zijn — zie [Omzetrecept.bewaar].
  static void _snoei(Directory dir, int bewaar) {
    try {
      final bestanden = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.flac')).toList();
      if (bestanden.length <= bewaar) return;
      bestanden.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      for (final f in bestanden.skip(bewaar)) {
        try {
          f.deleteSync();
        } catch (_) {/* in gebruik; volgende keer weer */}
      }
    } catch (_) {/* opruimen mag nooit het afspelen breken */}
  }
}

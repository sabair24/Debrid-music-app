// WAV wordt FLAC bij binnenkomst.
//
// Saber, 24-10-2026: "WAV halen, omzetten naar FLAC". Tot nu toe liet de app WAV bij Soulseek helemaal weg
// (`sortSoulseek`): een WAV kan de tags van deze app niet dragen — `stampTags` schrijft alleen FLAC — en zes WAV's
// landden destijds als naamloze singles onder "Onbekende artiest". Maar veel vinyl- en studio-rips staan alleen als
// WAV. FLAC is verliesvrij: dezelfde monsters, kleiner, en met tags en hoes. `keurOverdracht` in online.dart zet een
// binnengekomen WAV om, na de decodeerproef en vóór al het andere, dus elke weg (gewoon, handmatig, album, jacht,
// wens, radio) krijgt een FLAC te zien.
import 'dart:async';
import 'dart:io';

import 'ffmpeg.dart';

/// Hoe lang een omzetting mag duren. Een uur 24/192 is ruim 2 GB WAV; ffmpeg doet dat in een halve minuut.
const Duration kWavOmzetGeduld = Duration(minutes: 5);

/// Zet [wav] verliesvrij om naar FLAC naast het origineel, en gooit de WAV weg. Geeft het pad van de FLAC terug,
/// of null als het niet lukte (geen ffmpeg, een kapot bestand, een vorm die FLAC niet kent) — dan blijft de WAV
/// staan en beslist de aanroeper.
///
/// ffmpeg kiest zelf de diepte: 16 bit blijft 16, 24 bit wordt 24 (`s32` met 24 gebruikte bits). Alleen het geluid
/// (`-map 0:a:0`): een WAV met een ingebed plaatje of een tweede spoor zou anders een fout geven.
Future<String?> wavNaarFlac(String wav, {String? ffmpeg, Duration geduld = kWavOmzetGeduld}) async {
  final exe = ffmpeg ?? Ffmpeg().pad;
  if (exe == null) return null;
  final punt = wav.lastIndexOf('.');
  final basis = punt > 0 ? wav.substring(0, punt) : wav;
  var uit = '$basis.flac';
  for (var i = 2; File(uit).existsSync(); i++) {
    uit = '$basis ($i).flac';
  }
  final deel = '$uit.deel';
  Process? p;
  try {
    p = await Process.start(exe, [
      '-nostdin', '-hide_banner', '-loglevel', 'error', '-y', //
      '-i', wav, '-map', '0:a:0', '-c:a', 'flac', '-compression_level', '5', '-f', 'flac', deel,
    ]);
    unawaited(p.stdout.drain<void>());
    unawaited(p.stderr.drain<void>());
    final code = await p.exitCode.timeout(geduld);
    final f = File(deel);
    if (code != 0 || !f.existsSync() || f.lengthSync() == 0) {
      _weg(deel);
      return null;
    }
    await f.rename(uit);
  } catch (_) {
    p?.kill();
    _weg(deel);
    return null;
  }
  _weg(wav);
  return uit;
}

void _weg(String pad) {
  try {
    final f = File(pad);
    if (f.existsSync()) f.deleteSync();
  } catch (_) {/* in gebruik; de opruimer van de wachtmap neemt hem later mee */}
}

/// De Shield wekken als er muziek naartoe gaat terwijl hij slaapt (Saber, 31-10-2026: *"zoals sonos kan dit, en dan
/// wekt hij de shield als ik er naar wil streamen"* en *"dat hij de app start en na het wekken muziek begint te
/// spelen"*).
///
/// Vindbaar blijven doet de voorgronddienst op Android (`Ontvanger.kt`): die houdt het netwerk van de app open in de
/// slaap. Hier zit het andere stuk: vóór de muziek begint het scherm aan (de Shield zet dan zelf via HDMI-CEC de tv
/// aan), de app vooraan, en even wachten tot dat gebeurd is — wie meteen speelt terwijl de tv nog opstart, mist het
/// begin van het nummer.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

const _kanaal = MethodChannel('debridmusic/wekker');

/// Slaapt dit toestel (scherm uit)? Onwaar waar dat niet te vragen is: dan valt er ook niets te wekken.
Future<bool> toestelSlaapt() async {
  if (!Platform.isAndroid) return false;
  try {
    return await _kanaal.invokeMethod<bool>('slaapt') ?? false;
  } catch (_) {
    return false;
  }
}

/// Scherm aan en de app vooraan. Wat Android zei (`sliep`, `wakker`, `vooraan`, `magVoorgrond`), of null.
Future<Map<String, dynamic>?> wekToestel() async {
  if (!Platform.isAndroid) return null;
  try {
    return (await _kanaal.invokeMethod<Map<Object?, Object?>>('wek'))?.cast<String, dynamic>();
  } catch (_) {
    return null;
  }
}

/// De opdrachten van een andere zone die muziek laten beginnen: daarvoor moet een slapende tv wakker. Pauze, volume
/// of "hierna" wekken niemand.
const kWekOpdrachten = {'play', 'speel', 'nu', 'radio', 'neemOver', 'jump', 'tussendoor'};

bool wektToestel(String cmd) => kWekOpdrachten.contains(cmd);

/// Hoe lang na het wakker worden nog wachten voor de muziek begint: de tv gaat via HDMI-CEC aan en neemt pas daarna
/// geluid aan.
///
/// Gemeten op de Shield, 31-10-2026 ("screen on OneTouchPlay success" in `dumpsys hdmi_control`, na het wakker
/// worden): 8,1 s, 5,1 s, 6,9 s en 3,3 s. De Shield vraagt de tv om de twee seconden of hij al aan is, dus de tv is
/// tot twee seconden eerder aan dan dat. Met 3 s begon Bad 4,5 s voor de tv er was; met 7 s mis je hoogstens een
/// seconde, en wacht je nooit langer dan de tv zelf.
const kNaWekken = Duration(seconds: 7);

/// Hoe lang er hoogstens gewacht wordt tot het scherm echt aan is.
const kWekGeduld = Duration(seconds: 4);

/// Wekt het toestel als het slaapt, en wacht tot het wakker is plus [rust]. Waar of het sliep.
///
/// Wordt het niet wakker binnen [geduld], dan toch verder: de muziek moet beginnen, ook als de tv niet meewerkt — die
/// zet je dan zelf aan.
Future<bool> wekVoorMuziek({
  required Future<bool> Function() slaapt,
  required Future<Object?> Function() wek,
  Duration geduld = kWekGeduld,
  Duration rust = kNaWekken,
  Duration stap = const Duration(milliseconds: 100),
  void Function(String)? log,
}) async {
  if (!await slaapt()) return false;
  final klok = Stopwatch()..start();
  final antwoord = await wek();
  while (klok.elapsed < geduld && await slaapt()) {
    await Future<void>.delayed(stap);
  }
  final wakker = !await slaapt();
  log?.call(wakker
      ? 'gewekt in ${klok.elapsedMilliseconds} ms ($antwoord), nog ${rust.inMilliseconds} ms voor de tv'
      : 'NIET wakker na ${geduld.inSeconds} s ($antwoord) — speelt toch');
  if (wakker) await Future<void>.delayed(rust);
  return true;
}

// De openbare map voor wat je op dit toestel bewaart (Saber, 28-10-2026): "ik moet ook direct naar de map kunnen
// gaan" — een echte map in Bestanden, met de indeling van de pc. Op een gsm Muziek/Debrid Music, op een iPad de
// map van de app in Bestanden (Op mijn iPad › Debrid Music, via UIFileSharingEnabled in Info.plist).
//
// Op Android is daar "Toegang tot alle bestanden" voor nodig (Saber koos dat: dan kan de app die map ook na een
// herinstallatie herkennen, vervangen en opruimen). De app vraagt het; jij zet het zelf aan.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

const _kanaal = MethodChannel('debridmusic/bestanden');

/// De openbare map zolang de app erin mag schrijven, of null (geen toestemming, of een pc of tv). Gezet door main;
/// het scherm "Op dit toestel" kijkt ernaar.
final ValueNotifier<Directory?> openbareMapNu = ValueNotifier(null);

/// Mag de app in de openbare map schrijven? Op een iPad altijd; elders (pc, tv) niet van toepassing.
Future<bool> magOpenbaarBewaren() async {
  if (Platform.isIOS) return true;
  if (!Platform.isAndroid) return false;
  try {
    return await _kanaal.invokeMethod<bool>('mag') ?? false;
  } catch (_) {
    return false;
  }
}

/// Het scherm waar je "Toegang tot alle bestanden" aanzet (alleen Android).
Future<void> vraagOpenbaarBewaren() async {
  if (!Platform.isAndroid) return;
  try {
    await _kanaal.invokeMethod<void>('vraag');
  } catch (_) {/* geen scherm: dan blijft het zoals het was */}
}

/// De openbare map zelf, of null op een toestel zonder (pc, tv). Bestaat hij nog niet, dan wordt hij gemaakt.
Future<Directory?> openbareMuziekMap() async {
  try {
    if (Platform.isAndroid) {
      final pad = await _kanaal.invokeMethod<String>('muziekMap');
      return pad == null ? null : Directory(pad);
    }
    if (Platform.isIOS) return await getApplicationDocumentsDirectory();
  } catch (_) {}
  return null;
}

/// Laat Android [pad] (opnieuw) inlezen, zodat Bestanden en andere spelers het zien.
void scanBestand(String pad) {
  if (!Platform.isAndroid) return;
  unawaited(_kanaal.invokeMethod<void>('scan', {'pad': pad}).catchError((_) {}));
}

/// Open [map] in de bestandsbeheerder van het toestel. Onwaar als dat niet lukte.
Future<bool> openInBestanden(String map) async {
  try {
    if (Platform.isAndroid) return await _kanaal.invokeMethod<bool>('open', {'pad': map}) ?? false;
    if (Platform.isIOS) return await launchUrl(Uri.parse('shareddocuments://${Uri.encodeFull(map)}'));
  } catch (_) {}
  return false;
}

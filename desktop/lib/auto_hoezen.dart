/// De albumhoezen die Android Auto te zien krijgt.
///
/// **Waarom dit nodig is.** Auto draait in een ander proces (Google's Gearhead) en laadt de `artUri`
/// van een bladeritem zélf. Een `file:`-pad in de privémap van deze app kan hij niet openen — dat
/// levert grijze vlakken op waar je platenkast hoort te staan. Het speelscherm werkt wél met een
/// `file:`-URI, want dáár laadt `audio_service` de bytes binnen ons eigen proces en geeft het een
/// Bitmap door. Twee verschillende wegen, en die tweede was er niet.
///
/// Dus: de bytes naar een bestand in een map die een `FileProvider` deelt, en een `content:`-URI
/// terug. Zie `android/app/src/main/res/xml/auto_hoezen.xml` voor de map en de afweging eromheen.
///
/// **Genoemd naar de inhoud.** Dezelfde hoes levert hetzelfde bestand: een album dat twee keer
/// langskomt schrijft de tweede keer niets, en de map kan niet groeien voorbij één bestand per
/// unieke hoes. Precies de truc die `_artFile` in now_playing.dart al gebruikt.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'paths.dart';

/// De authority uit het manifest. Moet gelijk blijven aan `${applicationId}.hoezen`.
const _authority = 'com.debridmusic.app.hoezen';

/// De naam van het pad uit auto_hoezen.xml. Het eerste segment van de content-URI.
const _padNaam = 'hoezen';

/// De submap onder [appDir]. Moet overeenkomen met `path=` in auto_hoezen.xml.
const _map = 'autohoezen';

/// Waar de hoezen staan. Publiek zodat een opruimer hem kan vinden.
Directory autoHoesMap() => appSubdir(_map);

/// Schrijf [bytes] weg en geef de content-URI die Auto kan openen. Null als er niets te schrijven is.
///
/// Alleen op Android: op de pc en op iOS bestaat deze provider niet, en een content-URI die nergens
/// heen wijst is erger dan geen hoes — dan toont het systeem een gebroken plaatje in plaats van een
/// nette lege tegel.
Uri? autoHoesUri(Uint8List? bytes) {
  if (bytes == null || bytes.length < 100 || !Platform.isAndroid) return null;
  try {
    final naam = '${md5.convert(bytes).toString().substring(0, 16)}.jpg';
    final f = File('${autoHoesMap().path}${Platform.pathSeparator}$naam');
    if (!f.existsSync()) f.writeAsBytesSync(bytes);
    return Uri.parse('content://$_authority/$_padNaam/$naam');
  } catch (e) {
    // Geen hoes is een schoonheidsfout; de titel staat er nog. Nooit een reden om het bladeren te
    // laten mislukken — dan zie je in de auto een lege lijst in plaats van een grijze tegel.
    debugPrint('autohoes niet weggeschreven: $e');
    return null;
  }
}

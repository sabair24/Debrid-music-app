/// De albumhoezen die Android Auto te zien krijgt.
///
/// **Waarom dit nodig is.** Auto draait in een ander proces (Google's Gearhead) en laadt de `artUri`
/// van een bladeritem zélf. Een `file:`-pad in de privémap van deze app kan hij niet openen — dat
/// levert grijze vlakken op waar je platenkast hoort te staan. Het speelscherm werkt wél met een
/// `file:`-URI, want dáár laadt `audio_service` de bytes binnen ons eigen proces en geeft er een
/// Bitmap van door. Twee verschillende wegen, en die tweede was er niet.
///
/// Dus: de bytes naar een bestand, en een `content:`-URI terug die door
/// `android/app/src/main/kotlin/com/debridmusic/app/HoesProvider.kt` bediend wordt.
///
/// **Niet de FileProvider van androidx.** Die weigert geëxporteerd te worden, en niet met een
/// waarschuwing maar met een crash van het hele proces bij élke start van de app:
/// `SecurityException: Provider must not be exported`. Groen gebouwd, groene toetsen, APK
/// geïnstalleerd — en pas dán zei de telefoon het. De uitgeleverde versie was daarmee stukker dan
/// die zónder hoezen.
///
/// **Genoemd naar de inhoud.** Dezelfde hoes levert hetzelfde bestand: een album dat twee keer
/// langskomt schrijft de tweede keer niets, en de map kan niet groeien voorbij één bestand per
/// unieke hoes. Precies de truc die `_artFile` in now_playing.dart al gebruikt.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'paths.dart';

/// De submap onder [appDir]. Moet overeenkomen met `MAP` in HoesProvider.kt.
const _map = 'autohoezen';

/// Waar de hoezen staan. Publiek zodat een opruimer hem kan vinden.
Directory autoHoesMap() => appSubdir(_map);

/// De authority van de provider, of null zolang [initAutoHoezen] niet gedraaid heeft.
String? _authority;

/// Zoek de authority op. Eén keer, vroeg in `main()`.
///
/// **Niet hardgecodeerd**, en dat is met opzet: de foutbouw draait onder `com.debridmusic.app.dev`
/// (`applicationIdSuffix` in build.gradle), en een authority die daar niet bij past levert geen
/// foutmelding op maar stille grijze tegels — het soort mislukking dat je pas in de auto ziet.
Future<void> initAutoHoezen() async {
  if (!Platform.isAndroid) return;
  try {
    _authority = '${(await PackageInfo.fromPlatform()).packageName}.hoezen';
  } catch (e) {
    // Dan geen hoezen in de auto. Nooit een reden om het opstarten te laten mislukken.
    debugPrint('autohoezen: authority onbekend ($e)');
  }
}

/// De bestandsnaam voor deze hoes, of null als er niets te bewaren valt.
///
/// Apart van [autoHoesUri] omdat dit de afspraak met de Kotlin-kant ís: `HoesProvider` accepteert
/// uitsluitend zestien hexcijfers plus `.jpg`, en weigert al het andere. Er is geen toets die beide
/// kanten tegelijk kan draaien, dus staat de vorm hier in een pure functie waar er wél een toets op
/// past.
///
/// De ondergrens van 100 bytes zeeft lege en stukke plaatjes eruit: een tegel zonder hoes is netter
/// dan een gebroken plaatje.
String? hoesNaamVoor(List<int>? bytes) {
  if (bytes == null || bytes.length < 100) return null;
  return '${md5.convert(bytes).toString().substring(0, 16)}.jpg';
}

/// Schrijf [bytes] weg en geef de content-URI die Auto kan openen. Null als dat niet kan.
///
/// Alleen op Android: op de pc en op iOS bestaat deze provider niet, en een content-URI die nergens
/// heen wijst is erger dan geen hoes — dan toont het systeem een gebroken plaatje in plaats van een
/// nette lege tegel.
Uri? autoHoesUri(List<int>? bytes) {
  final naam = hoesNaamVoor(bytes);
  if (naam == null || _authority == null || !Platform.isAndroid) return null;
  try {
    final f = File('${autoHoesMap().path}${Platform.pathSeparator}$naam');
    if (!f.existsSync()) f.writeAsBytesSync(bytes!);
    return Uri.parse('content://$_authority/$naam');
  } catch (e) {
    // Geen hoes is een schoonheidsfout; de titel staat er nog. Nooit een reden om het bladeren te
    // laten mislukken — dan zie je in de auto een lege lijst in plaats van een grijze tegel.
    debugPrint('autohoes niet weggeschreven: $e');
    return null;
  }
}

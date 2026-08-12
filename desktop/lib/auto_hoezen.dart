/// De albumhoezen die Android Auto te zien krijgt.
///
/// **Waarom dit nodig is.** Auto draait in een ander proces (Google's Gearhead) en laadt de `artUri`
/// van een bladeritem zélf. Een `file:`-pad in de privémap van deze app kan hij niet openen — dat
/// levert grijze vlakken op waar je platenkast hoort te staan. Het speelscherm werkt wél met een
/// `file:`-URI, want dáár laadt `audio_service` de bytes binnen ons eigen proces en geeft het een
/// Bitmap door. Twee verschillende wegen, en die tweede was er niet.
///
/// **En waarom het er nog niet is.** De weg leek: bytes naar een bestand in een map die een
/// `FileProvider` deelt, en een `content:`-URI terug. Dat kan niet met de provider van androidx.
/// Die weigert geëxporteerd te worden, en niet met een waarschuwing maar met een crash van het hele
/// proces, bij élke start van de app:
///
/// ```
/// java.lang.RuntimeException: Unable to get provider androidx.core.content.FileProvider
/// Caused by: java.lang.SecurityException: Provider must not be exported
///     at androidx.core.content.FileProvider.attachInfo
/// ```
///
/// Het bouwen was groen, de toetsen waren groen, de APK installeerde. Pas de telefoon zei het, en
/// pas nadat hij al geïnstalleerd stond. De uitgeleverde versie was daarmee stukker dan de versie
/// zónder hoezen: geen muziek in plaats van tegels zonder plaatje.
///
/// **Wat er wél kan**, allebei platformcode en allebei nog te doen:
///
/// 1. `exported="false"` houden en Gearhead per URI toestemming geven met `grantUriPermission()`,
///    op het moment dat Auto bladert. Netjes, maar het moet lopen in het proces van de
///    `MediaBrowserService` — en die is van `audio_service`, niet van ons.
/// 2. Een eigen `ContentProvider` in Kotlin. Die kent de controle van androidx niet, dus mag hij
///    wél geëxporteerd zijn, en hij werkt ook als de app zelf niet draait.
///
/// Tot een van die twee er is geeft [autoHoesUri] `null` terug: grijze tegels met de juiste titels,
/// en een app die start.
library;

import 'dart:io';

import 'paths.dart';

/// De submap waar de hoezen zouden komen te staan.
const _map = 'autohoezen';

/// Waar de hoezen staan. Publiek zodat een opruimer hem kan vinden.
Directory autoHoesMap() => appSubdir(_map);

/// De hoes van een bladeritem, als URI die Android Auto kan openen. Voorlopig altijd `null`.
///
/// Null en niet "schrijf hem toch maar weg": een `content:`-URI zonder provider erachter is érger
/// dan geen hoes — dan toont het systeem een gebroken plaatje in plaats van een nette lege tegel.
/// En bestanden wegschrijven die niemand kan lezen is alleen maar schijfruimte.
///
/// Zie de uitleg boven aan dit bestand voor wat hier moet komen.
Uri? autoHoesUri(List<int>? bytes) => null;

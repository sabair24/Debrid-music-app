/// Bestaat dit hulpprogramma, en mag het aan `Process.runSync` gevoerd worden?
///
/// **Waarom dit bestaat.** De app zoekt ffmpeg, fpcalc, aria2c en tiddl door een lijstje kandidaten
/// af te lopen en er `--version` op te proberen; wat een nulcode teruggeeft is de goede. Dat leest
/// als "probeer het gewoon, een fout vangen we op", en op Windows en Linux werkt het ook zo.
///
/// Op macOS niet. Een `Process.runSync` op een pad dat NIET bestaat kost daar de hele app een
/// SIGPIPE — geen uitzondering die je kunt vangen, geen crashrapport, geen regel in enig logboek.
/// Het proces is weg. Gemeten op 24-08-2026 met een release-build: het instellingenvenster leest
/// `Aria2.beschikbaar` tijdens het opbouwen, aria2c staat op een Mac nergens, en dus verdween de app
/// zodra je op het tandwiel klikte. Afsluitcode 141, en in de debugger een SIGPIPE middenin `fork()`
/// op de hoofdthread. In een debug-build gebeurt het niet, dus het overleefde elke test.
///
/// Vandaar: eerst kijken of er iets te starten valt, en pas dan starten.
library;

import 'dart:io';

/// Het pad waarop [kandidaat] echt te starten is, of null.
///
/// Een kandidaat met een mapscheiding erin is een pad: die moet bestaan. Een kale naam is bedoeld
/// als "zoek maar in PATH", en dat zoeken doen we hier zelf — juist om de mislukte exec te vermijden
/// die we anders aan het systeem zouden overlaten.
String? uitvoerbaarPad(String kandidaat, {Map<String, String>? omgeving}) {
  final naam = kandidaat.trim();
  if (naam.isEmpty) return null;

  if (naam.contains(Platform.pathSeparator) || naam.contains('/')) {
    return _bruikbaar(naam) ? naam : null;
  }

  final pad = (omgeving ?? Platform.environment)['PATH'] ?? '';
  if (pad.isEmpty) return null;
  final scheiding = Platform.isWindows ? ';' : ':';
  for (final map in pad.split(scheiding)) {
    if (map.isEmpty) continue;
    final vol = '$map${Platform.pathSeparator}$naam';
    if (_bruikbaar(vol)) return vol;
  }
  return null;
}

/// Bestaat het, en is het geen map?
///
/// De uitvoerbaarheidsvlag wordt bewust NIET gecontroleerd: dat kost een extra systeemaanroep per
/// kandidaat, en een bestand dat er wel is maar niet uitvoerbaar levert een nette ProcessException
/// op — dat is precies het geval dat de aanroeper al opvangt.
bool _bruikbaar(String pad) => FileSystemEntity.isFileSync(pad);

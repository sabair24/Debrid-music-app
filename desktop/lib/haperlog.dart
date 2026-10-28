/// Wanneer de tekendraad vastzat, en welk zwaar werk er op dat moment liep: `haper.log`.
///
/// **Waarom (28-10-2026).** Saber: *"ik merk soms happering, meet terwijl ik navigeer"*. Van buitenaf gemeten
/// (processortijd per draad, vijf keer per seconde) zat de tekendraad van de pc in 5,5 minuut 21 keer 0,25 tot 2 s
/// volledig vast — vaak zonder één logregel op dat moment, zodat niet te zeggen was WAT. Daarvoor is dit:
/// - [haperVast]: elke stilstand vanaf [kHaperVanafMs], vanuit de klok van 100 ms in `warmtemeter.dart`;
/// - [traagMeten]: zwaar werk op de tekendraad met zijn eigen duur, vanaf een eigen drempel.
///
/// Dezelfde tijdstempels als de andere logboeken ([WarmLog]), dus naast elkaar te leggen. Een stilstand wordt
/// pas gezien als hij voorbij is: de regel staat op het EINDE, met de duur erbij.
library;

import 'dart:io';

import 'paths.dart';
import 'warm_log.dart';

/// Vanaf hoeveel ms te laat de klok van 100 ms een stilstand heet. Een beeld op 144 Hz duurt 7 ms; 120 ms is een
/// merkbare hapering, en de klok zelf loopt op Windows tot ~16 ms uit.
const int kHaperVanafMs = 120;

/// Alleen de app zet dit aan (main.dart, op de pc). Uit = niets schrijven: een toets die toevallig traag draait,
/// schrijft zo nooit in de echte appmap.
bool haperlogAan = false;

WarmLog? _haper;
WarmLog get _log => _haper ??= WarmLog('$logDir${Platform.pathSeparator}haper.log');

/// De tekendraad stond [ms] stil (gemeten door een klok die zoveel te laat afging).
void haperVast(int ms) {
  if (haperlogAan) _log.line('VAST $ms ms');
}

/// [werk] uitvoeren en het noteren als het [vanafMs] of langer duurde. Alleen voor synchroon werk: wat na een
/// `await` gebeurt, valt erbuiten.
T traagMeten<T>(String naam, T Function() werk, {int vanafMs = 30}) {
  if (!haperlogAan) return werk();
  final klok = Stopwatch()..start();
  try {
    return werk();
  } finally {
    final ms = klok.elapsedMilliseconds;
    if (ms >= vanafMs) _log.line('traag: $naam $ms ms');
  }
}

/// Eén beeld dat [bouwenMs] bouwde en [rasterenMs] rasterde, als een van beide 25 ms of meer was.
void haperBeeld(int bouwenMs, int rasterenMs) {
  if (haperlogAan) _log.line('BEELD bouwen $bouwenMs ms, rasteren $rasterenMs ms');
}

/// Wat de navigator deed: een pagina erop of eraf. Zo is na een hapering, of bij een pagina die niet meer reageert,
/// te zien welke pagina er bovenop lag.
void haperNav(String s) {
  if (haperlogAan) _log.line('nav: $s');
}

/// Een verzoek van een toestel aan de pc dat [ms] duurde (alleen het pad).
void haperVerzoek(String pad, int ms) {
  if (haperlogAan) _log.line('verzoek: $pad $ms ms');
}

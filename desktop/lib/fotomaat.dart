/// Hoe scherp een artiestfoto in de kop komt te staan — voor "Foto kiezen".
///
/// **Waarom (Saber, 19-10-2026: "de foto's zijn vaak niet scherp").** GEMETEN over de 29 foto's die
/// hij voor de gsm koos: 28 worden meer dan 2,5 keer opgerekt. Niet door de app (die decodeert tot
/// 1920 breed), maar door de bron: Discogs levert 200 tot 600 pixels (Alabina 339×510, 4,2 keer),
/// TheAudioDB 1280×720 (2,7 keer in een staande kop), Deezer 1000×1000 (2 keer). Saber koos de maat
/// in de kiezer te tonen, de scherpste eerst, met een merk bij wat op de gsm onscherp wordt.
library;

import 'dart:math' as math;

import 'discogs.dart' show DiscogsImage;

/// De kop van de artiestpagina op een gsm in pixels: de S26 is 1440 breed, en de kop met de foto
/// achter de statusbalk ongeveer 1960 hoog (gemeten op het scherm, 19-10-2026).
const kGsmKopBreedte = 1440, kGsmKopHoogte = 1960;

/// Een brede kop op de pc (een venster van 2560 breed, de kop ongeveer 1000 hoog): alleen om de
/// liggende foto's op scherpte te sorteren.
const kPcKopBreedte = 2560, kPcKopHoogte = 1000;

/// Vanaf hoeveel keer oprekken het merk "onscherp op je gsm" erbij staat. Deezers 1000×1000 (2 keer)
/// valt er net onder; TheAudioDB's 1280×720 (2,7 keer) en elke Discogs-foto erboven.
const kOnscherpVanaf = 2.5;

/// Hoeveel keer een foto van [b]×[h] opgerekt wordt om een vak van [vakB]×[vakH] te vullen
/// (`BoxFit.cover`). Null als de maat onbekend is.
double? oprek(int b, int h, {required int vakB, required int vakH}) =>
    b <= 0 || h <= 0 ? null : math.max(vakB / b, vakH / h);

double? oprekOpGsm(int b, int h) => oprek(b, h, vakB: kGsmKopBreedte, vakH: kGsmKopHoogte);

/// Wordt deze foto op een gsm onscherp? Onbekende maat: geen merk (dat zou gokken zijn).
bool onscherpOpGsm(int b, int h) => (oprekOpGsm(b, h) ?? 0) > kOnscherpVanaf;

/// De scherpste eerst: wat het minst opgerekt wordt in de kop waar dit vak voor is. Een onbekende
/// maat achteraan, en verder blijft de volgorde zoals hij was (stabiel).
List<DiscogsImage> opScherpte(List<DiscogsImage> beelden, {required bool breed}) {
  double sleutel(DiscogsImage i) =>
      (breed
          ? oprek(i.width, i.height, vakB: kPcKopBreedte, vakH: kPcKopHoogte)
          : oprekOpGsm(i.width, i.height)) ??
      double.infinity;
  final genummerd = [for (var n = 0; n < beelden.length; n++) (n, beelden[n])];
  genummerd.sort((a, b) {
    final c = sleutel(a.$2).compareTo(sleutel(b.$2));
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final g in genummerd) g.$2];
}

/// Waar een foto vandaan komt, voor onder de tegel.
String fotoBron(String url) {
  final h = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (h.contains('discogs')) return 'Discogs';
  if (h.contains('theaudiodb')) return 'TheAudioDB';
  if (h.contains('dzcdn') || h.contains('deezer')) return 'Deezer';
  if (h.contains('wikimedia') || h.contains('wikipedia')) return 'Wikipedia';
  return 'eigen foto';
}

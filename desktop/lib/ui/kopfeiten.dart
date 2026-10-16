/// De regel onder een albumtitel: de artiest, en dan jaar, genre en aantal nummers.
///
/// **Waarom.** Dit was een `Wrap` met twee kinderen: de artiest, en één tekst die begon met " · ".
/// Paste het samen niet, dan schoof die hele tekst naar de volgende regel — en die begon dan met een
/// punt. Saber op de S26, 16-10-2026: "Emmanuel Moire" en daaronder "· 2006 · Variété française ·
/// 2 nummers".
///
/// Nu wordt eerst gemeten. Past alles op één regel, dan staat het er zoals altijd ("Live · 2001 ·
/// 14 nummers"). Past het niet, dan staat de artiest op de eerste regel en de feiten eronder, zonder
/// punt vooraan; de feiten mogen zelf doorlopen, maar breken nooit midden in een feit.
library;

import 'package:flutter/material.dart';

/// Past "[artiest] · [feiten]" op één regel van [breedte]? Publiek voor de toets.
bool kopFeitenOpEenRegel(String artiest, List<String> feiten, TextStyle stijl, TextScaler schaal, double breedte) {
  final tp = TextPainter(
    text: TextSpan(text: [artiest, ...feiten].join(' · '), style: stijl),
    textScaler: schaal,
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final past = tp.width <= breedte;
  tp.dispose();
  return past;
}

/// Hoe lang een feit mag zijn om nog als één geheel te breken.
const kKopFeitVastTot = 24;

/// [feit] met vaste spaties als het kort is, anders zoals het is. Zie [KopFeiten].
String kopFeitVast(String feit) => feit.length <= kKopFeitVastTot ? feit.replaceAll(' ', ' ') : feit;

class KopFeiten extends StatelessWidget {
  const KopFeiten({
    super.key,
    required this.artiest,
    required this.artiestTekst,
    required this.feiten,
    required this.stijl,
  });

  /// De artiest zoals hij getekend wordt (meestal een aanklikbare naam).
  final Widget artiest;

  /// Dezelfde naam als platte tekst, om te meten.
  final String artiestTekst;

  /// Jaar, genre, aantal — lege worden overgeslagen.
  final List<String> feiten;

  final TextStyle stijl;

  @override
  Widget build(BuildContext context) {
    final f = [for (final x in feiten) if (x.trim().isNotEmpty) x.trim()];
    if (f.isEmpty) return artiest;
    return LayoutBuilder(builder: (context, c) {
      final schaal = MediaQuery.textScalerOf(context);
      if (!c.hasBoundedWidth || kopFeitenOpEenRegel(artiestTekst, f, stijl, schaal, c.maxWidth)) {
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: artiest),
          Text(' · ${f.join(' · ')}', style: stijl, maxLines: 1),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        artiest,
        const SizedBox(height: 2),
        // Een vaste spatie in een kort feit ("2 nummers", "Variété française") en een gewone na elke
        // punt: zo breekt de regel alleen tússen twee feiten, en begint een nieuwe regel nooit met " · ".
        // Een lang feit (een genrelijst) mag wél tussen zijn woorden breken: onbreekbaar brak Flutter
        // hem midden in een woord, "Br|eakbeat" (Shield, 16-10-2026). Zie [kopFeitVast].
        Text(
          [for (final x in f) kopFeitVast(x)].join(' · '),
          style: stijl,
        ),
      ]);
    });
  }
}

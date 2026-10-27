// Het logo van een artiest in de kop van zijn pagina, in de kleur van de tekst.
//
// Saber, 27-10-2026: "de naam van de artist is te groot, en die mag vervangen worden door de iconen naam
// die ook in de now playing wordt gebruikt als die beschikbaar is bij de TheaudioDB". In het ontwerp
// koos hij het logo in de kleur van de tekst: de logo's van TheAudioDB zijn bijna altijd wit, en wit op
// de lichte pagina zie je niet.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Heeft dit beeld doorzichtige pixels? Alleen dan kan een logo in de kleur van de tekst: het kleuren
/// vult elke pixel die er staat, en een logo op een dichte achtergrond (een JPEG, een PNG zonder alfa)
/// wordt zo een egaal blok. Zo'n logo valt terug op de naam in letters.
///
/// Gelezen uit de kop van het bestand, zonder te decoderen: een PNG met alfa (kleursoort 4 of 6) of
/// met een tRNS-blok vóór de beelddata, en een WebP met de alfavlag (VP8X) of verliesvrij (VP8L).
bool heeftDoorzichtigheid(Uint8List b) {
  bool staat(int van, String tekst) {
    if (b.length < van + tekst.length) return false;
    for (var i = 0; i < tekst.length; i++) {
      if (b[van + i] != tekst.codeUnitAt(i)) return false;
    }
    return true;
  }

  if (b.length > 33 && b[0] == 0x89 && staat(1, 'PNG')) {
    final soort = b[25];
    if (soort == 4 || soort == 6) return true;
    // Grijs, RGB of een palet: doorzichtig alleen met een tRNS-blok, en dat staat vóór IDAT.
    var i = 8;
    while (i + 8 <= b.length) {
      final lengte = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
      if (staat(i + 4, 'tRNS')) return true;
      if (staat(i + 4, 'IDAT') || staat(i + 4, 'IEND') || lengte < 0) return false;
      i += 12 + lengte;
    }
    return false;
  }
  if (staat(0, 'RIFF') && staat(8, 'WEBP')) {
    if (staat(12, 'VP8X')) return b.length > 20 && (b[20] & 0x10) != 0;
    return staat(12, 'VP8L');
  }
  return false;
}

/// Het logo, links uitgelijnd, hoogstens [hoogte] hoog en [breedte] breed, in [kleur]. Kan het niet
/// getekend worden (een kapot bestand), dan [terugval] — de naam in letters.
class KopLogo extends StatelessWidget {
  const KopLogo({
    super.key,
    required this.logo,
    required this.kleur,
    required this.hoogte,
    required this.breedte,
    required this.terugval,
  });

  final Uint8List logo;
  final Color kleur;
  final double hoogte, breedte;
  final Widget terugval;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: hoogte, maxWidth: breedte),
      child: Image.memory(
        logo,
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        color: kleur,
        colorBlendMode: BlendMode.srcIn,
        // De HOOGTE begrenst, niet de breedte: een woordmerk is breed en laag (zie ook het logo in Nu speelt).
        cacheHeight: (hoogte * dpr).ceil(),
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => terugval,
      ),
    );
  }
}

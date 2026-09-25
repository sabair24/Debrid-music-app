/// Een plaat zonder hoes, als ontworpen vlak in plaats van een grijs vak met een schijfje.
///
/// **Waarom dit bestaat.** Op 25-09-2026 wees Saber de LIVE-sectie van Oasis aan: tweehonderd tegels,
/// waarvan 191 hetzelfde grijze vak met een schijfje — "dit oogt echt heel lelijk". De meeste krijgen
/// sindsdien een hoes uit het Cover Art Archive, en de rest wordt standaard verborgen. Maar wie
/// "Toon alles" aanzet, ziet ze wél, en daar hoort geen rij identieke lege vakken te staan: bij een
/// radiosessie of een concertopname is de TITEL juist wat hem onderscheidt ("1994-02-06: Gleneagles
/// Hotel, Glasgow"). Dus die titel groot, op een eigen kleur per plaat.
///
/// **Een vaste kleur per titel, en niet per keer.** Uit [fnv1aVan] en niet uit `hashCode`: dat laatste
/// verschilt per keer dat de app start, en dan krijgt dezelfde plaat morgen een andere kleur. Zie
/// `cachesleutel.dart`.
library;

import 'package:flutter/material.dart';

import '../cachesleutel.dart' show fnv1aVan;
import 'kleuren.dart';

/// De kleur van een tegel zonder hoes, vast per titel.
///
/// Dezelfde lichtheid voor elke tint, zodat witte tekst er altijd op leesbaar is, en een gematigde
/// verzadiging: een raster vol felle vakken schreeuwt harder dan de hoezen ernaast.
Color tegelKleur(String titel) {
  final h = fnv1aVan(titel.trim().toLowerCase());
  return HSLColor.fromAHSL(1, (h % 360).toDouble(), .42, .30).toColor();
}

class PlaatTegel extends StatelessWidget {
  const PlaatTegel({super.key, required this.titel, this.jaar, required this.maat, this.hoek = 12});

  final String titel;
  final String? jaar;
  final double maat;
  final double hoek;

  @override
  Widget build(BuildContext context) {
    final basis = tegelKleur(titel);
    return Container(
      width: maat,
      height: maat,
      padding: EdgeInsets.all(maat * .09),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(hoek),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [basis, Color.lerp(basis, kAchtergrond, .55)!],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              titel,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: maat * .115,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: Colors.white,
              ),
            ),
          ),
          if (jaar != null && jaar!.isNotEmpty)
            Text(
              jaar!,
              style: TextStyle(
                fontSize: maat * .08,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: .7),
              ),
            ),
        ],
      ),
    );
  }
}

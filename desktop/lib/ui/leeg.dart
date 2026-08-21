/// Wat er staat als er niets is.
///
/// **Waarom dit bestand er is.** Er staan **24** lege toestanden in de app, en het zijn alle 24 één
/// grijs zinnetje midden op zwart. Dat leest niet als "hier is nog niets", dat leest als kapot — en
/// het laat je bovendien staan zonder te zeggen wat je nu zou moeten doen.
///
/// Vier onderdelen, en de vierde is de belangrijkste: een pictogram (zodat er íets is), een kop in
/// gewone tekstkleur (zodat het geen foutmelding lijkt), één regel uitleg, en een knop naar wat je
/// hierna zou willen. Die knop mag ontbreken — niet elk leeg scherm heeft een volgende stap.
library;

import 'package:flutter/material.dart';

import 'kleuren.dart';
import 'maten.dart';
import 'typografie.dart';
import 'vlak.dart';

/// Een leeg scherm dat zegt wat het is en wat je kunt doen.
class LeegVlak extends StatelessWidget {
  const LeegVlak({
    super.key,
    required this.teken,
    required this.kop,
    required this.uitleg,
    this.knop,
    this.opKnop,
    this.gecentreerd = true,
  });

  final IconData teken;
  final String kop;
  final String uitleg;

  /// Het label van de knop. Leeg laten betekent geen knop.
  final String? knop;
  final VoidCallback? opKnop;

  /// Verticaal in het midden van de ruimte die er is.
  ///
  /// **Zet dit uit in een `ListView`.** Daar is de hoogte ONBEGRENSD, en dan probeert een `Center`
  /// oneindig hoog te worden — dat is geen scheve opmaak maar een rode fout over het hele scherm.
  /// Uit betekent: neem precies de hoogte die de inhoud nodig heeft, en blijf horizontaal in het
  /// midden staan.
  final bool gecentreerd;

  @override
  Widget build(BuildContext context) => Align(
        alignment: gecentreerd ? Alignment.center : Alignment.topCenter,
        heightFactor: gecentreerd ? null : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: kGoot, vertical: kRuimte32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: paneelDecoratie(Niveau.hoog, radius: kHoekRond),
                child: Icon(teken, size: 24, color: kGedempt),
              ),
              const SizedBox(height: kRuimte16),
              Text(
                kop,
                textAlign: TextAlign.center,
                style: kKopKlein,
              ),
              const SizedBox(height: kRuimte6),
              // Een lege toestand die over de volle breedte van een pc-scherm loopt is één lange
              // regel en leest niet meer als een zin.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Text(
                  uitleg,
                  textAlign: TextAlign.center,
                  style: kTekstBij,
                ),
              ),
              if (knop != null && opKnop != null) ...[
                const SizedBox(height: kRuimte16),
                FilledButton(onPressed: opKnop, child: Text(knop!)),
              ],
            ],
          ),
        ),
      );
}

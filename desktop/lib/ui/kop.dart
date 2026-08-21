/// De kop boven een sectie of een lijst.
///
/// **Waarom dit bestand er is.** Er staan vijf van deze koppen in de app en ze staan alle vijf op
/// een andere marge. De ergste is die op Start: de kop staat op `fromLTRB(28, 22, 28, 12)` en de rij
/// hoezen eronder op `symmetric(horizontal: 24)`. Vier punten scheefstand tussen een kop en zijn
/// eigen inhoud, over de volle hoogte van het startscherm — dat is letterlijk wat "het rammelt"
/// betekent, en het is een wijziging van twee tekens.
library;

import 'package:flutter/material.dart';

import 'maten.dart';
import 'typografie.dart';

/// De kop van een sectie, met eventueel een telling of een knop rechts.
class SectieKop extends StatelessWidget {
  const SectieKop(
    this.titel, {
    super.key,
    this.bij,
    this.rechts,
    this.eerste = false,
  });

  final String titel;

  /// Wat naast de titel hoort: een aantal, een jaartal.
  final String? bij;

  /// Wat helemaal rechts staat: "Toon alles", een sorteerkiezer.
  final Widget? rechts;

  /// De eerste kop op een pagina krijgt minder lucht boven zich — daar zit de balk al.
  final bool eerste;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
          kGoot,
          eerste ? kRuimte16 : kRuimte24,
          kGoot,
          kRuimte12,
        ),
        child: Row(
          children: [
            Flexible(
              child: Text(
                titel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: kKopKlein,
              ),
            ),
            if (bij != null) ...[
              const SizedBox(width: kRuimte8),
              Text(bij!, style: kTekstKlein),
            ],
            if (rechts != null) ...[const Spacer(), rechts!],
          ],
        ),
      );
}

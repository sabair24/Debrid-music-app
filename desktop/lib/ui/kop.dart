/// De kop boven een sectie of een lijst.
///
/// **Waarom dit bestand er is.** Er staan vijf van deze koppen in de app en ze staan alle vijf op
/// een andere marge. De ergste is die op Start: de kop staat op `fromLTRB(28, 22, 28, 12)` en de rij
/// hoezen eronder op `symmetric(horizontal: 24)`. Vier punten scheefstand tussen een kop en zijn
/// eigen inhoud, over de volle hoogte van het startscherm — dat is letterlijk wat "het rammelt"
/// betekent, en het is een wijziging van twee tekens.
library;

import 'package:flutter/material.dart';

import 'kleuren.dart';
import 'maten.dart';
import 'typografie.dart';

/// De grote titel boven een sectie op een gsm. Hij scrolt mee weg, en dan staat de titel klein in de
/// balk erboven (Saber, 18-10-2026: "één keer de titel", als grote kop die inklapt, zoals in Apple
/// Music). Eerst stond de naam van de sectie in de balk én nog eens als kop op de pagina.
class GroteKop extends StatelessWidget {
  const GroteKop(this.titel, {super.key});

  final String titel;

  /// Hoe ver de kop weg moet zijn voor de titel in de balk verschijnt: als hij grotendeels onder de
  /// balk verdwenen is.
  static const inklapGrens = 30.0;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(kGoot, 2, kGoot, 4),
        child: Text(
          titel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -.6, height: 1.15, color: kTekst),
        ),
      );
}

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
            // **De titel gaat voor.** Het grijze bijschrift nam eerst zijn volle breedte en de titel
            // kreeg de rest: op de S26 (16-10-2026) stond er "Nieuw…" naast "de laatste drie maanden
            // en wat eraan komt". Nu schuift het bijschrift onder de titel zodra ze samen niet passen.
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: kRuimte8,
                runSpacing: 2,
                children: [
                  Text(
                    titel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: kKopKlein,
                  ),
                  if (bij != null)
                    Padding(
                      // Op de grondlijn van de titel, niet tegen de onderkant van zijn regel.
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(bij!, style: kTekstKlein),
                    ),
                ],
              ),
            ),
            if (rechts != null) ...[const SizedBox(width: kRuimte8), rechts!],
          ],
        ),
      );
}

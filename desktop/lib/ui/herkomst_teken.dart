// Waar het nummer dat nu speelt vandaan komt (Saber, 02-11-2026: "ik zou het ergens ook duidelijk moeten zien met een
// icontje of ik online of offline stream"). Drie standen: van je pc thuis, van je pc via internet, van dit toestel.
import 'package:flutter/material.dart';

import '../player.dart' show Herkomst;
import '../tv.dart';
import 'kleuren.dart';

/// Het icoontje bij [herkomst]: een huisje (van je pc, thuis), een wolk (van je pc via internet) of het teken van "Op dit
/// toestel" ([toestel] is hoe de tekst dit toestel noemt: "je gsm", "je iPad"). [metWoord] bij Nu speelt; in de minispeler
/// alleen het icoontje. Niets zonder [herkomst] (een zone op afstand, de pc zelf) en op een tv (die staat altijd thuis).
class HerkomstTeken extends StatelessWidget {
  const HerkomstTeken({super.key, required this.herkomst, required this.toestel, this.metWoord = false});

  final Herkomst? herkomst;
  final String toestel;
  final bool metWoord;

  /// Icoon, woordje, uitleg en kleur van [h].
  static (IconData, String, String, Color) vorm(Herkomst h, String toestel) => switch (h) {
        Herkomst.thuis => (Icons.home_rounded, 'thuis', 'Van je pc, thuis', kGedempt),
        Herkomst.internet =>
          (Icons.cloud_rounded, 'via internet', 'Van je pc, via internet', leesbaar(const Color(0xFFE8C36A))),
        Herkomst.toestel => (Icons.offline_pin_rounded, 'op $toestel', 'Van $toestel, zonder internet', kAccent2),
      };

  @override
  Widget build(BuildContext context) {
    final h = herkomst;
    if (h == null || isTv) return const SizedBox.shrink();
    final (icoon, woord, uitleg, kleur) = vorm(h, toestel);
    return Semantics(
      label: uitleg,
      child: Padding(
        padding: EdgeInsets.only(left: metWoord ? 10 : 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icoon, size: metWoord ? 16 : 14, color: kleur),
          if (metWoord) ...[
            const SizedBox(width: 4),
            Text(woord, style: TextStyle(color: kleur, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
    );
  }
}

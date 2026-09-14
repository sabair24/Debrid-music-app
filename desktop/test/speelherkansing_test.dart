library;

import 'package:debridmusic/player.dart';
import 'package:flutter_test/flutter_test.dart';

/// **NAGEMETEN OP 14-09-2026, nadat dit getal korter was gemaakt en weer teruggedraaid.**
///
/// De aanleiding was goed: over 23 dagen `speler.log` van de telefoon staan 116 losse openingen die
/// mislukten, zo'n vijf per actieve dag. Het voorstel was om alleen vier tellen te wachten als de
/// pc stond om te zetten, en anders na zevenhonderd milliseconden terug te komen - een verse
/// verbinding naar de pc kost thuis immers 5 tot 17 ms.
///
/// Het logboek zei het omgekeerde. Van alle 69 herkansingen nagegaan of dezelfde titel binnen twee
/// minuten opnieuw omviel:
///
///     oorzaak                            hield stand   weer fout
///     `maxRate` (pc zet om)                   43           3     -> 93 % raak
///     adres zonder `maxRate`                   9           5     -> 64 %
///     helemaal geen adres (tcp-time-out)       0           9     ->  0 %
///
/// Versnellen zou precies de twee onderste groepen raken - die waar de herkansing het al het
/// slechtst deed - en de bovenste, de enige die bijna altijd lukt, zijn vier tellen laten houden.
///
/// En er is maar EEN herkansing per nummer. Vuurt die terwijl de pc nog wakker wordt, dan is de
/// enige kans op en blijft het nummer dood op 0:00 staan. Opeenvolgende time-outs op hetzelfde
/// nummer lagen 6, 8, 9 en 12 seconden uit elkaar; daar is 700 ms niets. De meting van 5 tot 17 ms
/// was niet van toepassing: die is thuis gedaan met een wakkere pc, terwijl er bij een time-out
/// juist geen pc heeft geantwoord.
///
/// Deze toets bestaat om dat niet nog eens te doen.
void main() {
  group('de tweede poging op een nummer dat niet openging', () {
    test('DE KERN: vier tellen, en niet korter', () {
      expect(kHerkansingNa, const Duration(seconds: 4));
    });

    test('DE VAL: ruim boven de tijd die een time-out zelf al kost', () {
      // Opeenvolgende `Connection timed out` op hetzelfde nummer lagen 6, 8, 9 en 12 s uit elkaar.
      // Een herkansing die binnen die cyclus valt vraagt het aan een pc die nog steeds niet
      // antwoordt, en verbrandt daarmee de enige poging die er is.
      expect(kHerkansingNa.inMilliseconds, greaterThanOrEqualTo(2000),
          reason: 'onder de twee seconden krijg je gegarandeerd dezelfde fout terug');
    });

    test('DE GRENS: en niet zo lang dat het een storing lijkt', () {
      // Boven een seconde of tien geeft de app geen teken van leven meer en lijkt hij kapot in
      // plaats van geduldig.
      expect(kHerkansingNa.inSeconds, lessThanOrEqualTo(10));
    });
  });
}

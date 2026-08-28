/// Duim omhoog of omlaag — op elk toestel hetzelfde.
///
/// Naar het model van `favorieten.dart`, en om dezelfde reden: op de pc gaat het rechtstreeks in de
/// gedeelde winkel, op een telefoon dezelfde op over de lijn naar `/api/state/ops`. Eén weg, dus geen
/// tweede waarheid die kan gaan afwijken.
///
/// **Waarom dit iets anders is dan een hartje.** Een favoriet is een lijst waar je zelf naar kijkt.
/// Een duim omlaag is een OPDRACHT: dat nummer mag straks van je schijf. Dat is de enige knop in deze
/// app die een bestand weggooit, en daarom wordt hij hier alleen maar OPGESCHREVEN — het wissen zelf
/// gebeurt pas als je de radio afsluit, en met een overzicht ervóór. Zie `radiosessie.dart`.
library;

import 'package:flutter/foundation.dart';

import 'gedeelde_ops.dart';
import 'models.dart';

/// Wat je van een nummer vindt.
enum Oordeel {
  omhoog('up'),
  omlaag('down');

  const Oordeel(this.opNaam);

  /// Hoe het in de gedeelde staat heet. Een korte vaste naam en niet `toString()`: dit gaat over de
  /// lijn en in een bestand, en `Oordeel.omhoog` hernoemen zou dan stilletjes elk opgeslagen oordeel
  /// ongeldig maken.
  final String opNaam;

  static Oordeel? vanNaam(String? s) => switch (s) {
        'up' => Oordeel.omhoog,
        'down' => Oordeel.omlaag,
        _ => null,
      };
}

/// Hoeveel een oordeel meeweegt bij het schudden.
///
/// **Waarom groen zwaarder telt dan een gewoon nummer en rood niet nul is.** Groen is "hier wil ik
/// meer van", en dat mag te horen zijn. Rood is bij een nummer dat je HOUDT (het stond al in je
/// bibliotheek, dus de radio ruimt het niet op) geen "gooi weg" maar "liever niet nu" — en dan is nul
/// te hard: een nummer dat je één keer wegtikte zou je nooit meer horen, ook niet over een jaar.
///
/// Vermenigvuldigt met het gewicht uit `schudvolgorde.dart`, dus dit is een factor en geen getal op
/// zichzelf.
double oordeelBonus(Oordeel? o) => switch (o) {
      Oordeel.omhoog => 2.0,
      Oordeel.omlaag => 0.15,
      null => 1.0,
    };

/// De oordelen, gedeeld over al je toestellen.
class Oordelen extends GedeeldeOps {
  Oordelen();

  /// Van een pad naar het gedeelde id.
  ///
  /// `library.gedeeldId` en geen eigen wortel, om precies de reden die bij `Speelstanden` staat: een
  /// wortel wordt alleen op de pc gezet, en dan geeft dit op elke telefoon null — en zijn de duimen
  /// daar stil dood, terwijl er juist daar geluisterd wordt.
  String? Function(String pad)? idVanPad;

  /// Wat een client van de pc heeft gekregen. Op de pc blijft dit leeg en wordt [winkel] gelezen.
  final Map<String, String> _vanPc = {};

  /// Zet wat de pc meldt. Alleen op een client; de pc is zijn eigen bron.
  void vanServer(Map<String, dynamic> oordelen) {
    final nieuw = <String, String>{
      for (final e in oordelen.entries)
        if (e.value is String) e.key: e.value as String,
    };
    if (mapEquals(_vanPc, nieuw)) return;
    _vanPc
      ..clear()
      ..addAll(nieuw);
    notifyListeners();
  }

  String? idVanTrack(Track t) => idVanPad?.call(t.path);

  Oordeel? van(String? id) {
    if (id == null) return null;
    final w = winkel;
    return Oordeel.vanNaam(w != null ? w.ratings[id] : _vanPc[id]);
  }

  Oordeel? vanTrack(Track t) => van(idVanTrack(t));

  /// Zetten of weghalen. [naar] null is "ik vind er toch niets van".
  Future<void> zet(String id, Oordeel? naar) async {
    if (id.isEmpty) return;
    final was = van(id);
    if (was == naar) return;
    await pasToe(
      [
        {
          'type': 'rating',
          'trackId': id,
          'value': naar?.opNaam ?? '',
          'at': nu,
        }
      ],
      vooruit: () => naar == null ? _vanPc.remove(id) : _vanPc[id] = naar.opNaam,
      terug: () => was == null ? _vanPc.remove(id) : _vanPc[id] = was.opNaam,
    );
  }

  /// Aantikken: dezelfde duim nog eens haalt hem weer weg.
  ///
  /// Dat er een weg terug is, is hier geen gemak maar een eis. Rood betekent "dit mag van mijn
  /// schijf"; een rode duim die je per ongeluk raakte en niet meer kwijtraakt is een knop waar je
  /// bang voor wordt.
  Future<Oordeel?> wissel(Track t, Oordeel duim) async {
    final id = idVanTrack(t);
    if (id == null) return null;
    final naar = van(id) == duim ? null : duim;
    await zet(id, naar);
    return naar;
  }

  int get aantal => winkel?.ratings.length ?? _vanPc.length;
}

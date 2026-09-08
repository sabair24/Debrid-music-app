/// Wat de jacht op echte vervangers op dit moment doet — in getallen die op het scherm passen.
///
/// **Waarom dit bestaat.** De knop "Laat de app zoeken" zette 173 nummers op de verlanglijst en zei
/// daarna niets meer. Alles wat er daarna gebeurde stond alleen in `downloads.log`: welke wens aan
/// de beurt was, welke peer leverde, en dat er twee vervalsingen betrapt en weggegooid waren. Van
/// buiten was een app die hard aan het werk was niet te onderscheiden van een app die niets deed.
///
/// Bewust een eigen bestand en geen veld op `DownloadManager`: zo kan het scherm het tonen en een
/// toets het narekenen zonder dat er een Soulseek-verbinding of een downloadmap aan te pas komt.
library;

import 'package:flutter/foundation.dart';

@immutable
class VervangJacht {
  const VervangJacht({
    required this.opDeLijst,
    this.dezeBeurt = 0,
    this.gedaan = 0,
    this.poging = 0,
    this.maxPoging = 0,
    this.bezigMet,
    this.regel,
    this.binnen = 0,
    this.weggegooid = 0,
    this.volgendeOm,
  });

  /// Hoeveel wensen er nog op de verlanglijst staan — het getal dat moet dalen.
  final int opDeLijst;

  /// Hoeveel wensen deze veegbeurt aanpakt, en hoeveel daarvan af zijn.
  final int dezeBeurt, gedaan;

  /// De hoeveelste kandidaat van de huidige wens, en hoeveel het er hoogstens worden. Zonder dit
  /// staat de balk twintig minuten stil terwijl er wél gewerkt wordt: één wens kan zes peers kosten.
  final int poging, maxPoging;

  /// "Gorki — Anja", of leeg als er niets loopt.
  final String? bezigMet;

  /// De laatste uitkomst in gewone taal. Dit is de regel die verklaart waarom een balk stilstaat.
  final String? regel;

  /// Wat er sinds het opstarten uit is gekomen: vervangers binnen, en vervalsingen die bij
  /// binnenkomst betrapt en weggegooid zijn.
  final int binnen, weggegooid;

  /// Wanneer de volgende veegbeurt aan de beurt is. Zonder dit leest "niets aan het doen" als
  /// "kapot", terwijl de app gewoon op zijn ritme wacht.
  final DateTime? volgendeOm;

  bool get loopt => dezeBeurt > 0;

  /// Hoe vol de balk staat, of null zolang er niets loopt.
  ///
  /// De lopende wens telt fractioneel mee. Anders springt de balk zes keer en staat hij daartussen
  /// minutenlang stil — precies het beeld waar dit tegen gebouwd is. `poging - 1`, want een poging
  /// die net begonnen is heeft nog niets opgeleverd.
  double? get deel {
    if (dezeBeurt <= 0) return null;
    final binnenWens = maxPoging <= 0 ? 0.0 : ((poging - 1).clamp(0, maxPoging)) / maxPoging;
    return ((gedaan + binnenWens) / dezeBeurt).clamp(0.0, 1.0);
  }

  VervangJacht met({
    int? opDeLijst,
    int? dezeBeurt,
    int? gedaan,
    int? poging,
    int? maxPoging,
    String? bezigMet,
    String? regel,
    int? binnen,
    int? weggegooid,
    DateTime? volgendeOm,
  }) =>
      VervangJacht(
        opDeLijst: opDeLijst ?? this.opDeLijst,
        dezeBeurt: dezeBeurt ?? this.dezeBeurt,
        gedaan: gedaan ?? this.gedaan,
        poging: poging ?? this.poging,
        maxPoging: maxPoging ?? this.maxPoging,
        bezigMet: bezigMet ?? this.bezigMet,
        regel: regel ?? this.regel,
        binnen: binnen ?? this.binnen,
        weggegooid: weggegooid ?? this.weggegooid,
        volgendeOm: volgendeOm ?? this.volgendeOm,
      );

  /// De beurt is voorbij: de balk weg, de tellers en het ritme blijven staan.
  VervangJacht klaar({required int opDeLijst, String? regel}) => VervangJacht(
        opDeLijst: opDeLijst,
        binnen: binnen,
        weggegooid: weggegooid,
        volgendeOm: volgendeOm,
        regel: regel ?? this.regel,
      );
}

/// Een wachttijd zoals je hem uitspreekt: "20 min", "2 uur", "een dag".
///
/// Het logboek heeft zijn eigen korte vorm (`20m0s`) en die is daar prima — compact en precies.
/// Op het scherm las hij als een foutcode.
String duurTekst(Duration d) {
  if (d.inMinutes < 1) return '${d.inSeconds} sec';
  if (d.inHours < 1) return '${d.inMinutes} min';
  if (d.inHours < 24) return d.inHours == 1 ? 'een uur' : '${d.inHours} uur';
  final dagen = d.inDays;
  return dagen == 1 ? 'een dag' : '$dagen dagen';
}

/// "over 12 min", "over een halve minuut", of leeg als het moment al voorbij is.
///
/// Zuiver en met een meegegeven `nu`, zodat een toets er niet op een echte klok hoeft te wachten.
String overTijd(DateTime? moment, DateTime nu) {
  if (moment == null) return '';
  final over = moment.difference(nu);
  if (over.isNegative || over.inSeconds < 5) return '';
  if (over.inMinutes < 1) return 'over ${over.inSeconds} sec';
  if (over.inMinutes == 1) return 'over een minuut';
  if (over.inMinutes < 60) return 'over ${over.inMinutes} min';
  final u = over.inHours;
  return 'over $u uur';
}

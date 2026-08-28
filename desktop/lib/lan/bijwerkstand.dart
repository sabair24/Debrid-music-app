/// Wat de pc over zijn eigen bijwerken meldt, en wat je telefoon daarvan tekent.
///
/// **Waarom dit bestaat.** Gevraagd op 28-08-2026, en de aanleiding was concreet: een uitgave stond
/// klaar, de pc stond aan, en er was geen manier om er vanaf een telefoon iets mee te doen. De pc
/// kán zichzelf al bijwerken — `updater.dart` haalt de installer en start hem, en de installer
/// sluit de app en start hem daarna weer op. Er ontbrak alleen een knop op afstand.
///
/// **Waarom dit een eigen, zuiver bestand is.** Wat er op het scherm komt te staan hangt van zes
/// dingen af — kan deze pc het, wat draait er, wat staat er klaar, hoe groot is het, waar is hij mee
/// bezig, en ging er iets mis — en elke fout daarin is er een die niet omvalt maar stilletjes het
/// verkeerde zegt. Een knop die "bijwerken" aanbiedt terwijl er niets nieuws is, of die verdwijnt
/// terwijl de pc aan het binnenhalen is, kost je vertrouwen in precies het scherm dat je op afstand
/// gebruikt. Hier staat die som één keer, en de bouwstraat kan hem nameten.
library;

import 'package:flutter/foundation.dart';

/// Waar de pc mee bezig is. Reist als tekst over de lijn, zoals elke andere keuze in deze app:
/// een naam overleeft het bijwerken van één van de twee kanten beter dan een volgnummer.
enum Bijwerkfase { stil, halen, installeren, mislukt }

/// Een onbekende of ontbrekende naam is [Bijwerkfase.stil] en geen fout: een pc van vóór deze
/// versie stuurt hier niets, en dan valt er ook niets te melden.
Bijwerkfase faseUitNaam(String? naam) => switch ((naam ?? '').trim()) {
      'halen' => Bijwerkfase.halen,
      'installeren' => Bijwerkfase.installeren,
      'mislukt' => Bijwerkfase.mislukt,
      _ => Bijwerkfase.stil,
    };

String naamVanFase(Bijwerkfase f) => f.name;

/// Megabytes, afgerond, of leeg als het onbekend is.
///
/// Afgerond en niet met een komma: dit staat naast een knop om te zeggen of het even duurt, niet in
/// een boekhouding. "41 MB" leest, "41,3 MB" doet alsof het nauwkeurig is.
String megabytes(int bytes) => bytes <= 0 ? '' : '${(bytes / (1024 * 1024)).round()} MB';

/// Alles wat het paneel op de telefoon nodig heeft, en niets meer.
@immutable
class Bijwerkbeeld {
  const Bijwerkbeeld({required this.regel, this.knop, this.balk, this.fout = false});

  /// De zin die er altijd staat, ook als er niets te doen is.
  final String regel;

  /// Wat er op de knop staat, of null als er geen knop hoort te zijn.
  final String? knop;

  /// De voortgangsbalk: een waarde tussen 0 en 1, of null voor geen balk. Een balk die er is maar
  /// waarvan de waarde onbekend is, loopt onbepaald — daarvoor is [balkOnbepaald].
  final double? balk;

  /// Er ging iets mis; de regel is dan de melding van de pc.
  final bool fout;

  /// Een balk zonder waarde: hij is er wel, maar er valt niets te tellen. Zo tijdens het
  /// installeren, want dan zwijgt de installer tot hij klaar is.
  bool get balkOnbepaald => balk != null && balk! < 0;

  @override
  bool operator ==(Object other) =>
      other is Bijwerkbeeld &&
      other.regel == regel &&
      other.knop == knop &&
      other.balk == balk &&
      other.fout == fout;

  @override
  int get hashCode => Object.hash(regel, knop, balk, fout);
}

// **Elk veld wordt gewogen in plaats van gecast.** Dit is een kaart die van een ANDERE machine komt,
// met mogelijk een andere versie van deze app erop — ouder of nieuwer. Een `as String?` op een veld
// dat daar een getal blijkt te zijn gooit midden in een `build`, en dan is het paneel wég in plaats
// van dat er "kan het niet" staat. Precies het soort fout waar deze hele zeef voor bedoeld is.
String _tekst(Object? v) => v is String ? v.trim() : '';
int _getal(Object? v) => v is num ? v.toInt() : 0;
double _komma(Object? v) => v is num ? v.toDouble() : 0;

/// De som. Zie de kop van dit bestand voor waarom hij hier staat en niet tussen de schermcode.
///
/// [j] is letterlijk wat `/api/update` teruggaf. Alles erin is optioneel: een pc die deze
/// voorziening nog niet kent stuurt een lege boel, en dan hoort hier "kan het niet" uit te komen —
/// geen knop die niets doet.
Bijwerkbeeld bijwerkbeeldVan(Map<String, dynamic> j) {
  final fase = faseUitNaam(_tekst(j['fase']));
  final fout = _tekst(j['fout']);

  // **De fout eerst, vóór de vraag of deze pc het kan.** Een mislukking is het enige antwoord dat
  // je niet mag inslikken: hij is het gevolg van iets wat je zélf hebt aangeraakt, en zonder deze
  // volgorde zou een pc die halverwege "kan: false" begint te sturen jouw mislukking wegpoetsen.
  if (fase == Bijwerkfase.mislukt) {
    return Bijwerkbeeld(
      regel: fout.isEmpty ? 'Het bijwerken is misgegaan.' : fout,
      knop: 'Opnieuw proberen',
      fout: true,
    );
  }

  if (fase == Bijwerkfase.halen) {
    final p = _komma(j['voortgang']);
    final deel = p.clamp(0.0, 1.0).toDouble();
    return Bijwerkbeeld(regel: 'Binnenhalen op de pc… ${(deel * 100).round()}%', balk: deel);
  }

  if (fase == Bijwerkfase.installeren) {
    // Geen percentage: de installer draait stil en zegt onderweg niets. Een balk die op 99% blijft
    // hangen is erger dan een balk die gewoon loopt.
    return const Bijwerkbeeld(
      regel: 'Installeren — de pc sluit de app en start hem zo weer op.',
      balk: -1,
    );
  }

  if (j['kan'] != true) {
    // Twee gevallen, één zin: een pc die te oud is voor deze voorziening, en een pc waar niets te
    // vervangen valt. Voor wie ernaar kijkt is het verschil er niet: je moet er zelf heen.
    return const Bijwerkbeeld(regel: 'Deze pc kan zichzelf niet op afstand bijwerken.');
  }

  final hier = _tekst(j['versie']);
  final daar = _tekst(j['nieuw']);

  if (daar.isEmpty) {
    return Bijwerkbeeld(
      regel: hier.isEmpty ? 'De pc is bij.' : 'De pc draait $hier — dat is de nieuwste.',
    );
  }

  final groot = megabytes(_getal(j['bytes']));
  return Bijwerkbeeld(
    regel: hier.isEmpty
        ? 'Er staat $daar klaar${groot.isEmpty ? '' : ' ($groot)'}.'
        : 'De pc draait $hier. Er staat $daar klaar${groot.isEmpty ? '' : ' ($groot)'}.',
    // Het versienummer OP de knop, en dat is de halve bevestiging: je ziet wat je installeert
    // voordat je erop drukt, op een pc waar je niet bij kunt.
    knop: 'Pc bijwerken naar $daar',
  );
}

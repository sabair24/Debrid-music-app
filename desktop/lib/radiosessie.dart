/// Wat een radio heeft opgehaald, en wat daarvan mag blijven.
///
/// **Dit is de gevaarlijkste functie in de app.** [opruimplan] beslist welke bestanden er van je
/// schijf gaan, en wissen heeft geen weg terug. Daarom staat hij hier apart, zonder IO, zonder
/// bibliotheek en zonder netwerk: puur een lijst in en twee lijsten uit, zodat er een toets op kan
/// die elke regel afdwingt in plaats van dat er op het toestel gekeken moet worden.
///
/// Drie regels, en ze zijn allemaal een kant op streng:
///
/// 1. **Alleen wat DEZE radio ophaalde.** Muziek die je zelf verzameld hebt komt hier niet eens in de
///    lijst — zie `Radioplek.doorRadio` en de eigendomstoets in `DownloadManager.haalVoorRadio`.
/// 2. **Bij twijfel blijft het staan.** Een favoriet, een nummer in een afspeellijst, of een nummer
///    dat je bij het afsluiten hebt teruggehaald: die blijven, ook als er een rode duim op staat. Ten
///    onrechte iets bewaren kost schijfruimte; ten onrechte iets wissen kost het nummer.
/// 3. **Zonder oordeel gaat het weg.** Dat is met zoveel woorden gekozen: alleen groen blijft. De
///    radio is een manier om muziek te PROBEREN, en wat je niet hebt aangewezen heb je niet gekozen.
library;

import 'oordelen.dart';

/// Eén nummer dat deze radio heeft opgehaald.
class Gehaald {
  const Gehaald({
    required this.pad,
    required this.artiest,
    required this.titel,
    this.id,
    this.bytes = 0,
  });

  /// Waar het bestand staat, op de machine die de muziek houdt.
  final String pad;

  /// Het gedeelde id, om het oordeel bij te zoeken. Null als het pad geen id opleverde.
  final String? id;

  final String artiest;
  final String titel;

  /// Hoe groot het is, zodat het overzicht kan zeggen wat er vrijkomt. 0 = onbekend.
  final int bytes;

  Map<String, dynamic> toJson() => {
        'pad': pad,
        'artiest': artiest,
        'titel': titel,
        if (id != null) 'id': id,
        if (bytes > 0) 'bytes': bytes,
      };

  static Gehaald? fromJson(Object? j) {
    if (j is! Map) return null;
    final pad = j['pad'];
    if (pad is! String || pad.isEmpty) return null;
    return Gehaald(
      pad: pad,
      artiest: j['artiest'] is String ? j['artiest'] as String : '',
      titel: j['titel'] is String ? j['titel'] as String : '',
      id: j['id'] is String ? j['id'] as String : null,
      bytes: j['bytes'] is num ? (j['bytes'] as num).toInt() : 0,
    );
  }
}

/// Eén radio, zoals hij een herstart overleeft.
///
/// **Waarom dit op schijf moet.** Je legt je telefoon weg terwijl er een radio loopt. Zonder deze
/// notitie is bij de volgende start niet meer te achterhalen wélke bestanden die radio heeft
/// binnengehaald — en dan blijven ze voor altijd staan zonder dat iemand weet waar ze vandaan komen.
/// Met deze notitie komt het overzicht van gisteren gewoon alsnog.
class RadioSessie {
  RadioSessie({required this.naam, required this.begonnenMs, List<Gehaald>? gehaald})
      : gehaald = gehaald ?? [];

  final String naam;
  final int begonnenMs;
  final List<Gehaald> gehaald;

  bool get leeg => gehaald.isEmpty;

  Map<String, dynamic> toJson() => {
        'naam': naam,
        'begonnenMs': begonnenMs,
        'gehaald': [for (final g in gehaald) g.toJson()],
      };

  static RadioSessie? fromJson(Object? j) {
    if (j is! Map) return null;
    final lijst = j['gehaald'];
    final uit = <Gehaald>[];
    for (final e in (lijst is List ? lijst : const [])) {
      final g = Gehaald.fromJson(e);
      if (g != null) uit.add(g);
    }
    return RadioSessie(
      naam: j['naam'] is String ? j['naam'] as String : '',
      begonnenMs: j['begonnenMs'] is num ? (j['begonnenMs'] as num).toInt() : 0,
      gehaald: uit,
    );
  }
}

/// Wat er blijft en wat er weg mag.
typedef Opruimplan = ({List<Gehaald> blijft, List<Gehaald> weg});

/// Het opruimplan van één radio.
///
/// De verweren staan bewust vóór de rode duim: een nummer dat je favoriet gemaakt hebt of in een
/// afspeellijst hebt gezet, blijft — ook als er ergens ook een duim omlaag op staat. Die twee kunnen
/// alleen samen voorkomen als je van gedachten veranderd bent, en dan is bewaren het antwoord dat
/// terug te draaien is.
///
/// [gered] zijn de paden die je bij het afsluiten hebt teruggehaald met "Toch houden".
Opruimplan opruimplan({
  required List<Gehaald> gehaald,
  Oordeel? Function(Gehaald)? oordeel,
  bool Function(Gehaald)? isFavoriet,
  bool Function(Gehaald)? inAfspeellijst,
  Set<String> gered = const {},
}) {
  final blijft = <Gehaald>[];
  final weg = <Gehaald>[];
  final gezien = <String>{};
  for (final g in gehaald) {
    // Twee keer hetzelfde pad zou het twee keer in het overzicht zetten en, erger, twee keer laten
    // wissen. Dat kan: een haal die mislukte en later alsnog landde staat er twee keer in.
    if (!gezien.add(g.pad)) continue;
    final houden = gered.contains(g.pad) ||
        (isFavoriet?.call(g) ?? false) ||
        (inAfspeellijst?.call(g) ?? false) ||
        oordeel?.call(g) == Oordeel.omhoog;
    (houden ? blijft : weg).add(g);
  }
  return (blijft: blijft, weg: weg);
}

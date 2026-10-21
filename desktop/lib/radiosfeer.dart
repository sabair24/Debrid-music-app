/// "Past / past niet in deze radio" — een oordeel over de SFEER van een radio, niet over het nummer.
///
/// Saber, 21-10-2026: *"bij de radio gaan we een functie toevoegen dit liedje past of past niet, net zoals
/// roon doet … maar dan moet de app daar absoluut rekening mee houden."* En: *"het mag weer in een radio,
/// maar het moet gewoon passen in de radio. bv. als er een radio van de vengaboys speelt, moet daar niet een
/// liedje van sade die traag en meer jazz is in komen … maar als er een radio is van michael bublé, dan mag
/// sade daar wel weer inkomen met een jazzy nummer."*
///
/// Daarom draagt elk oordeel zijn context: de artiest waarop de radio startte (of de zin van een radio uit
/// een zin) en de sfeerfamilie ([Stijlfamilie]: dans, popsoul, jazz, …). Het geldt voor radio's met dezelfde
/// zaadartiest OF dezelfde familie; op een radio met een andere sfeer telt het niet.
///
/// Op artiest en titel en niet op een bestand: de radio weert een nummer ook vóór het gedownload is. De titel
/// voluit (genormaliseerd), want een akoestische versie heeft een andere sfeer dan het origineel.
///
/// Los van "Houden / Weg" (het BESTAND, zie `RadioBesturing.gooiWeg`): Saber koos twee paar knoppen.
library;

import 'gedeelde_ops.dart';
import 'organize.dart' show normKey;
import 'radiokeuze.dart' show artiestSleutel;

enum Sfeeroordeel {
  past('past'),
  pastNiet('pastniet');

  const Sfeeroordeel(this.opNaam);

  final String opNaam;

  static Sfeeroordeel? vanNaam(Object? s) => switch (s) {
        'past' => Sfeeroordeel.past,
        'pastniet' => Sfeeroordeel.pastNiet,
        _ => null,
      };
}

/// Wie een nummer is, voor dit oordeel.
String sfeerNummer(String artiest, String titel) => '${artiestSleutel(artiest)}|${normKey(titel)}';

/// De context: een artiest, of een radio uit een zin (`zin:…`).
String sfeerZaad(String zaad) {
  final z = zaad.trim();
  if (z.startsWith('zin:')) return 'zin:${normKey(z.substring(4))}';
  return artiestSleutel(z);
}

/// De sleutel van één oordeel: nummer en context samen. Hetzelfde nummer kan in een dansradio niet passen
/// en in een jazzradio wel.
String sfeerSleutel(String artiest, String titel, {required String zaad, required String familie}) =>
    '${sfeerNummer(artiest, titel)}|${sfeerZaad(zaad)}|${familie.trim()}';

class RadioSfeer extends GedeeldeOps {
  RadioSfeer();

  /// Wat de pc zei, op een toestel dat de muziek niet bezit. Op de pc zelf staat het in [winkel].
  final Map<String, Map<String, dynamic>> _vanPc = {};

  Map<String, Map<String, dynamic>> get _regels => winkel?.radioSfeer ?? _vanPc;

  void vanServer(Map<String, dynamic> regels) {
    _vanPc
      ..clear()
      ..addAll({
        for (final e in regels.entries)
          if (e.value is Map) e.key: (e.value as Map).cast<String, dynamic>(),
      });
    notifyListeners();
  }

  /// Wat je vond van dit nummer in een radio als deze: dezelfde zaadartiest of dezelfde familie. Het
  /// laatste oordeel wint.
  Sfeeroordeel? oordeel({
    required String artiest,
    required String titel,
    required String zaad,
    required String familie,
  }) {
    final nummer = sfeerNummer(artiest, titel);
    final z = sfeerZaad(zaad);
    final f = familie.trim();
    Map<String, dynamic>? laatst;
    for (final r in _regels.values) {
      if (r['n'] != nummer) continue;
      final zelfdeZaad = z.isNotEmpty && r['z'] == z;
      final zelfdeFamilie = f.isNotEmpty && r['f'] == f;
      if (!zelfdeZaad && !zelfdeFamilie) continue;
      if (laatst == null || ((r['at'] as num?) ?? 0) > ((laatst['at'] as num?) ?? 0)) laatst = r;
    }
    return Sfeeroordeel.vanNaam(laatst?['v']);
  }

  bool pastNiet({required String artiest, required String titel, required String zaad, required String familie}) =>
      oordeel(artiest: artiest, titel: titel, zaad: zaad, familie: familie) == Sfeeroordeel.pastNiet;

  /// Het oordeel geven, of weghalen ([naar] null). Op de pc meteen in de gedeelde staat, op een toestel
  /// als op naar de pc (zie [GedeeldeOps]).
  Future<void> zet({
    required String artiest,
    required String titel,
    required String zaad,
    required String familie,
    Sfeeroordeel? naar,
  }) async {
    final sleutel = sfeerSleutel(artiest, titel, zaad: zaad, familie: familie);
    final was = _vanPc[sleutel];
    final at = nu;
    final regel = <String, dynamic>{
      'v': naar?.opNaam ?? '',
      'n': sfeerNummer(artiest, titel),
      'a': artiest,
      't': titel,
      'z': sfeerZaad(zaad),
      'f': familie.trim(),
      'at': at,
    };
    await pasToe(
      [
        {
          'type': 'radio.sfeer',
          'key': sleutel,
          ...regel,
        }
      ],
      vooruit: () => _vanPc[sleutel] = regel,
      terug: () => was == null ? _vanPc.remove(sleutel) : _vanPc[sleutel] = was,
    );
  }

  /// Voorbeelden voor de sfeerkeuring en de lijstvraag aan het model: wat in radio's als deze wel of niet
  /// paste, het nieuwste eerst.
  List<({String artiest, String titel})> voorbeelden({
    required String zaad,
    required String familie,
    required Sfeeroordeel soort,
    int max = 20,
  }) {
    final z = sfeerZaad(zaad);
    final f = familie.trim();
    final passend = [
      for (final r in _regels.values)
        if (r['v'] == soort.opNaam && ((z.isNotEmpty && r['z'] == z) || (f.isNotEmpty && r['f'] == f))) r
    ]..sort((a, b) => ((b['at'] as num?) ?? 0).compareTo((a['at'] as num?) ?? 0));
    return [
      for (final r in passend.take(max)) (artiest: '${r['a'] ?? ''}', titel: '${r['t'] ?? ''}'),
    ];
  }

  int get aantal => _regels.values.where((r) => '${r['v'] ?? ''}'.isNotEmpty).length;
}

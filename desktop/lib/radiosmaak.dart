/// Bekend of minder bekend: hoe diep een radio in het werk van een artiest graaft.
///
/// **Waarom dit er is.** Saber op 26-09-2026: *"ik wil ergens een keuze maken dat de radio bekende of
/// minder bekende liedjes neemt, functie bekend in youtube music."* YouTube Music noemt het "je
/// radio afstemmen": populair of juist diepere nummers. Hier zijn het drie standen, en de middelste
/// is wat de radio tot nu toe deed.
///
/// **Waar "bekend" vandaan komt.** Deezer geeft de toppers van een artiest op volgorde van
/// populariteit (`/artist/{id}/top`, met `index` om er een stuk van over te slaan), en elk nummer
/// draagt een `rank`. Bekend neemt de kop van die lijsten, Ontdekken slaat de grootste hits over en
/// graaft verder — en neemt van de namen die het taalmodel noemt eerst de artiesten die je nog NIET
/// kent.
///
/// Geen IO: alleen de maten en de keuzes, zodat het na te rekenen is.
library;

/// De drie standen, van bekend naar onbekend.
enum Radiosmaak {
  bekend('Bekend'),
  gemengd('Gemengd'),
  ontdekken('Ontdekken');

  const Radiosmaak(this.label);

  /// Zoals hij op het scherm staat.
  final String label;

  /// Uit wat er in de instellingen staat. Onbekend of leeg is [gemengd]: de radio zoals hij was.
  static Radiosmaak uit(String? s) {
    for (final m in values) {
      if (m.name == s) return m;
    }
    return gemengd;
  }
}

/// Hoeveel er waarvandaan komt, per stand.
///
/// `vanaf` is Deezers `index`: hoeveel toppers er overgeslagen worden. `aantal` is `limit`.
typedef Smaakmaat = ({
  int zaadVanaf,
  int zaadAantal,
  int buren,
  int burenVanaf,
  int burenAantal,
  int modelVanaf,
  int modelAantal,
});

/// De maten van [smaak].
///
/// [Radiosmaak.gemengd] is exact wat de radio vóór deze keuze deed: vijftien toppers van de
/// zaadartiest, vier buren met elk hun top vijf, en van de modelnamen de top vier.
Smaakmaat maatVan(Radiosmaak smaak) => switch (smaak) {
      Radiosmaak.bekend => (
          zaadVanaf: 0,
          zaadAantal: 10,
          buren: 4,
          burenVanaf: 0,
          burenAantal: 4,
          modelVanaf: 0,
          modelAantal: 3,
        ),
      Radiosmaak.gemengd => (
          zaadVanaf: 0,
          zaadAantal: 15,
          buren: 4,
          burenVanaf: 0,
          burenAantal: 5,
          modelVanaf: 0,
          modelAantal: 4,
        ),
      // De vijf grootste hits van de zaadartiest over, en van elke buur de drie grootste: wat je
      // dan hoort zijn albumnummers en b-kantjes van dezelfde mensen. En meer buren, want minder
      // bekend is ook: meer verschillende namen.
      Radiosmaak.ontdekken => (
          zaadVanaf: 5,
          zaadAantal: 20,
          buren: 6,
          burenVanaf: 3,
          burenAantal: 6,
          modelVanaf: 2,
          modelAantal: 5,
        ),
    };

/// Van Deezers artiestenradio de helft die bij [smaak] past, in de volgorde waarin hij kwam.
///
/// Die lijst is al door elkaar en draagt per nummer een [rang] (Deezers `rank`, hoger is
/// bekender). Bekend houdt de bovenste helft, Ontdekken de onderste; bij een oneven aantal krijgt
/// Bekend de middelste erbij. Een rang van nul — de bron zei niets — telt als onbekend.
List<T> radioHelft<T>(List<T> lijst, int Function(T) rang, Radiosmaak smaak) {
  if (smaak == Radiosmaak.gemengd || lijst.length < 2) return List<T>.from(lijst);
  final volgorde = List<int>.generate(lijst.length, (i) => i)
    ..sort((a, b) {
      final c = rang(lijst[b]).compareTo(rang(lijst[a]));
      return c != 0 ? c : a.compareTo(b);
    });
  final boven = (lijst.length + 1) ~/ 2;
  final houden = (smaak == Radiosmaak.bekend
          ? volgorde.take(boven)
          : volgorde.skip(boven))
      .toSet();
  return [
    for (var i = 0; i < lijst.length; i++)
      if (houden.contains(i)) lijst[i]
  ];
}

/// De namen van het taalmodel in de volgorde die bij [smaak] past.
///
/// Het model zegt per naam of je die artiest waarschijnlijk al KENT (uit je luistergedrag). Bekend
/// zet die vooraan, Ontdekken juist de namen die nieuw voor je zijn. Binnen elke groep blijft de
/// volgorde van het model staan; er valt niets weg — hoeveel er gebruikt worden beslist de
/// aanroeper.
List<T> modelVolgorde<T>(List<T> namen, bool Function(T) kentJe, Radiosmaak smaak) {
  if (smaak == Radiosmaak.gemengd) return List<T>.from(namen);
  final voor = smaak == Radiosmaak.bekend;
  return [
    for (final n in namen)
      if (kentJe(n) == voor) n,
    for (final n in namen)
      if (kentJe(n) != voor) n,
  ];
}

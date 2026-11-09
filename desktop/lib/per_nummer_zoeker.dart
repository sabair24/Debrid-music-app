/// Op een albumpagina per nummer zoeken, op de achtergrond.
///
/// **Waarom.** Saber, 09-11-2026: *"waarom vindt ik meer resultaten bij doo wop single, dan op de album ??"* en *"daarom mis ik
/// wel heel veel resultaten"*. Het getal naast een nummer kwam uit één zoekopdracht op artiest + album: Doo Wop 53, terwijl
/// dezelfde Doo Wop bij het downloaden 226 kandidaten gaf. Soulseek sluit na de eerste paar honderd bestanden, en een
/// albumvraag vindt alleen wat in een map met de naam van het album staat. Hij koos: per nummer, op de achtergrond.
///
/// Elke vraag gaat langs de zoekrem als achtergrondwerk (`Zoekrem`), dus de grens van Soulseek blijft bewaakt. Ga je weg, dan
/// gaan de vragen die nog niet weg zijn niet meer uit.
library;

/// Zoveel nummers tegelijk: genoeg om een album in een halve minuut rond te hebben, en de rem doet de rest.
const int kPerNummerTegelijk = 3;

/// Bij een box van honderd nummers niet elk nummer: een tik op een nummer zoekt toch zelf.
const int kPerNummerMax = 30;

/// Roept [zoek] aan voor elk nummer waarvoor [nodig] waar is, in volgorde, met hoogstens [tegelijk] tegelijk. Stopt zodra
/// [nogNodig] onwaar is. Een fout bij één nummer laat de rest gewoon doorgaan: dan blijft daar het getal van de albumvraag.
Future<void> zoekPerNummer<T>(
  List<T> nummers, {
  required bool Function(T nummer) nodig,
  required Future<void> Function(T nummer) zoek,
  required bool Function() nogNodig,
  int tegelijk = kPerNummerTegelijk,
  int max = kPerNummerMax,
}) async {
  final rij = nummers.where(nodig).take(max).iterator;
  Future<void> werker() async {
    while (nogNodig() && rij.moveNext()) {
      try {
        await zoek(rij.current);
      } catch (_) {/* dit nummer niet; de volgende wel */}
    }
  }

  await Future.wait([for (var i = 0; i < tegelijk; i++) werker()]);
}

/// De kopieën uit de albumvraag plus die uit de vraag per nummer, zonder dubbele. Wat de albumvraag vond blijft vooraan.
List<F> samenPerNummer<F>(List<F> uitAlbum, List<F>? perNummer, String Function(F kopie) sleutel) {
  if (perNummer == null || perNummer.isEmpty) return uitAlbum;
  final gezien = {for (final f in uitAlbum) sleutel(f)};
  return [
    ...uitAlbum,
    for (final f in perNummer)
      if (gezien.add(sleutel(f))) f,
  ];
}

/// Op een albumpagina per nummer zoeken, op de achtergrond.
///
/// **Waarom.** Saber, 09-11-2026: *"waarom vindt ik meer resultaten bij doo wop single, dan op de album ??"* en *"daarom mis ik
/// wel heel veel resultaten"*. Het getal naast een nummer kwam uit één zoekopdracht op artiest + album: Doo Wop 53, terwijl
/// dezelfde Doo Wop bij het downloaden 226 kandidaten gaf. Soulseek sluit na de eerste paar honderd bestanden, en een
/// albumvraag vindt alleen wat in een map met de naam van het album staat. Hij koos: per nummer, op de achtergrond.
///
/// Elke vraag gaat langs de zoekrem als het laagste werk van de app (`telling` in `Zoekrem.neem`): één zoekopdracht per nummer,
/// alleen in wat de achtergrond overlaat, dus de grens van Soulseek blijft bewaakt en niets anders wacht erop. Ga je weg,
/// dan gaan de vragen die nog niet weg zijn niet meer uit.
///
/// **Tot 3.9.723 was dat niet zo.** Gemeten op 11-11-2026: vanaf de gsm telden de vragen per nummer op de pc als jouw eigen
/// vragen, twee per nummer. "Milow You Don't Know" — de single die Saber net opende — wachtte 78 s in de zoekrem, en ⬇
/// "Scared of Yourself" 20 s, achter de tellingen van de plaat ervoor.
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

/// Zo lang is wat de albumpagina voor een nummer vond vers genoeg om ⬇ er meteen mee te laten beginnen ([meteenMetTelling]).
/// Een uploader die tien minuten geleden een vrije plek had, heeft die meestal nog; de race probeert er twintig tegelijk.
const kTellingVers = Duration(minutes: 10);

/// Mag ⬇ meteen beginnen met wat de pagina al vond, zonder nieuwe zoekopdracht? Alleen als het vers is ([kTellingVers]) en
/// er genoeg zeker goede kopieën bij zitten ([genoeg]: `vroegGenoeg` — waar een nieuwe zoekopdracht anders ook als eerste
/// op wacht voor de race begint).
///
/// **Waarom.** ⬇ zocht altijd opnieuw, ook naast een telling van een minuut oud: twee zoekopdrachten erbij, en op 11-11-2026
/// wachtte die vraag 20 s in de zoekrem voor "Scared of Yourself" van Zornik (soulseek_login.log, 21:16:27).
bool meteenMetTelling({required DateTime? gevondenOp, required DateTime nu, required bool genoeg}) =>
    genoeg && gevondenOp != null && !nu.isBefore(gevondenOp) && nu.difference(gevondenOp) <= kTellingVers;

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

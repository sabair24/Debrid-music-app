/// "A1.INXS" is geen artiest die zo heet.
///
/// **Wat er gemeld werd, op 04-09-2026.** Een schermafdruk van het album *X* van INXS: "1 nummers".
/// En op diezelfde plaat stond "Suicide Blonde" bij de nummers die er *niet* op zouden staan —
/// terwijl dat kant A, nummer 1 is. *"ik snap er niets van??"*
///
/// **Wat er aan de hand was.** Op de albumpagina stond als artiest `INXS`; in de balk onderaan
/// speelde hetzelfde nummer met als artiest `A1.INXS`. Die twee komen uit hetzelfde veld, dus dat
/// ze verschilden bewees dat het twee bestanden waren met twee verschillende artiestnamen.
///
/// De `A1` is de plek op de vinyl: kant A, eerste nummer. Sommige tagprogramma's plakken die plek
/// aan de artiestnaam vast, en de app leest dat veld rauw in. Groeperen gaat op artiest + album
/// (`library.dart`, `_basisSleutel`), dus twaalf nummers met twaalf verschillende "artiesten"
/// worden twaalf platen van één nummer.
///
/// En daarmee kwam de tweede klacht er gratis bij: elke tegel ziet alleen zijn eigen scherfje van
/// de plaat, dus alles wat in een ándere scherf zit heet "niet op deze uitgave". Eén oorzaak, twee
/// klachten die niets met elkaar te maken leken te hebben.
///
/// **Waarom dit een eigen bestand met een toets is.** Het gevaar zit niet in het opschonen maar in
/// het te véél opschonen: er zijn echte artiesten die A1, B12, D12 of H2O heten, en die mogen hier
/// niet gehalveerd worden. Zo'n fout is stil — een groep verdwijnt uit je bibliotheek onder een
/// naam die je niet kent — en daarom staat de regel hier één keer, met de namen die hem moeten
/// overleven als toets ernaast.
library;

/// De plek op de plaat vooraan een artiestnaam weghalen: `A1.INXS` wordt `INXS`.
///
/// **De regel is met opzet streng, en die strengheid zit in het scheidingsteken.** Er moet iets
/// tússen de plek en de naam staan — een punt, een streepje, een haakje of een spatie. Een naam die
/// alleen maar uit een letter en een cijfer bestaat wordt dus nooit aangeraakt:
///
/// * `A1` (de Britse groep) → blijft `A1`;
/// * `D12`, `B12`, `H2O`, `B2K`, `B1A4` → blijven zoals ze zijn, want er komt geen scheidingsteken
///   achter het cijfer maar gewoon de rest van de naam.
///
/// Wat overblijft moet bovendien op een naam lijken: minstens twee tekens, en er moet een letter in
/// zitten. `A1.2` levert dus niets op en blijft staan.
///
/// Alleen de kanten A tot en met H. Een dubbelalbum heeft vier kanten, een driedubbel zes; verder
/// dan H komt geen plaat, en elke letter die we erbij nemen is een echte naam die we kapot kunnen
/// maken. `S1`, `M1` en `T2` blijven daarmee vanzelf buiten schot.
///
/// Kleine letters tellen mee (`a1. inxs`), want de ene ripper schrijft het zo en de andere zo.
String zonderKantnummer(String artiest) {
  final s = artiest.trim();
  final m = _kantnummer.firstMatch(s);
  if (m == null) return s;
  final rest = (m.group(1) ?? '').trim();
  if (rest.length < 2) return s;
  if (!_bevatLetter.hasMatch(rest)) return s;
  return rest;
}

/// Kant (A-H, hoogstens twee letters voor de 12"-kanten AA en BB), nummer (één of twee cijfers),
/// een scheidingsteken, en dan pas de naam.
final RegExp _kantnummer = RegExp(
  r'^[A-H]{1,2}[0-9]{1,2}(?:\s*[.\-_:)\]]+\s*|\s+)(.+)$',
  caseSensitive: false,
);

final RegExp _bevatLetter = RegExp(r'[A-Za-z]');

/// De TITEL die uit een bestandsnaam komt, zonder de plek op de plaat ervoor.
///
/// **Waarom dit apart staat van [zonderKantnummer].** Die regel op élke titel loslaten is niet
/// veilig: `B2 Unit` is een echte plaat en `1. Outside` een echt album. Maar een titel die uit de
/// BESTANDSNAAM komt, komt daar alleen terecht omdat het bestand géén titel-tag heeft — en dan is
/// een `B3. ` of een `08. ` vooraan een ripartefact en geen naam. Alleen op die weg wordt dit dus
/// gebruikt; een bestand mét tags gaat er nooit langs.
///
/// **Gevonden bij het doorlichten van de bibliotheek op 05-09-2026.** Zes bestanden zonder enige tag
/// stonden als "B3. Mary Jane", "G1. Tiesto feat. Kirsty Hawkshaw - Just Be" en "08. Enzo - opzij
/// opzij" in de lijst — allemaal met de kant of het nummer erin, en allemaal zonder hoes.
///
/// **En strenger dan [zonderKantnummer] op één punt: een kale spatie telt hier niet.** Die regel
/// laat `A1 INXS` toe, want een artiestnaam begint zelden met een letter-cijfercombinatie. Een
/// TITEL doet dat wel: `B2 Unit` is een plaat van Ryuichi Sakamoto en `7 Seconds` een nummer van
/// Youssou N'Dour. Er moet dus een leesteken tussen staan -- een punt, een streepje, een haakje.
/// Een toets ving dit: `B2 Unit` werd `Unit`.
///
/// Wat overblijft moet bovendien op een naam lijken: minstens twee tekens, en er moet een letter in
/// zitten.
String titelUitBestandsnaam(String naam) {
  final s = naam.trim();
  final m = _plekVoorTitel.firstMatch(s);
  if (m == null) return s;
  final rest = (m.group(1) ?? '').trim();
  if (rest.length < 2 || !_bevatLetter.hasMatch(rest)) return s;
  return rest;
}

/// De plek op de plaat vooraan een TITEL: een vinylkant (`B3.`) of een spoornummer (`08.`), gevolgd
/// door een verplicht leesteken.
final RegExp _plekVoorTitel = RegExp(
  r'^(?:[A-H]{1,2}[0-9]{1,2}|[0-9]{1,2})\s*[.\-_:)\]]+\s*(.+)$',
  caseSensitive: false,
);

/// Artiest én titel uit een bestandsnaam van de vorm `Artiest - Titel`.
///
/// **Alleen voor een bestand dat GEEN artiest heeft.** Dat is de hele rechtvaardiging: bij zo'n
/// bestand staat er nu "Onbekende artiest", en dan kan het nergens bij horen -- niet gegroepeerd,
/// geen hoes, op geen enkele tracklijst te vinden. Een naam uit de bestandsnaam is dan geen gok
/// tegenover een feit maar een gok tegenover niets.
///
/// **Gemeten op 05-09-2026:** 8 van de 1255 bestanden hebben geen artiest, en 4 daarvan dragen hem
/// in hun naam:
///
///     G1. Tiesto feat. Kirsty Hawkshaw - Just Be   ->  Tiesto feat. Kirsty Hawkshaw | Just Be
///     B1. Tiesto feat. BT - Love Comes Again       ->  Tiesto feat. BT              | Love Comes Again
///     08. Enzo - opzij opzij                       ->  Enzo                         | opzij opzij
///     Alex Carrena, Franck Minaro & Fily - Don't … ->  Alex Carrena, Franck Minaro & Fily | Don't …
///
/// De plek op de plaat gaat er eerst af via [titelUitBestandsnaam], anders wordt "08. Enzo" de
/// artiest.
///
/// **Op de EERSTE " - " en niet de laatste.** "Artiest - Titel - Remix" is een titel met een
/// streepje erin, geen artiest die "Artiest - Titel" heet. Rondom spaties verplicht, zodat een
/// koppelteken in een naam ("Jean-Jacques") niets doet.
({String artiest, String titel})? artiestEnTitelUitBestandsnaam(String naam) {
  final schoon = titelUitBestandsnaam(naam);
  final m = _streepjeMetSpaties.firstMatch(schoon);
  if (m == null) return null;
  final artiest = schoon.substring(0, m.start).trim();
  final titel = schoon.substring(m.end).trim();
  // Allebei moeten op een naam lijken. Anders levert "A - B" twee letters op en is de bibliotheek
  // een artiest rijker die niet bestaat.
  if (artiest.length < 2 || titel.length < 2) return null;
  if (!_bevatLetter.hasMatch(artiest) || !_bevatLetter.hasMatch(titel)) return null;
  return (artiest: artiest, titel: titel);
}

final RegExp _streepjeMetSpaties = RegExp(r'\s+[-–]\s+');

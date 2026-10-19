/// Het jaar in een ISRC: "USWB19600603" → 1996, "USWB12604176" → 2026. Twee cijfers, dus vanaf '40 de
/// vorige eeuw (een opname van vóór 1940 heeft zelden een ISRC, en die van na 2039 bestaan nog niet).
///
/// Het is het jaar waarin de CODE werd uitgegeven: bij nieuwe muziek het jaar van de opname, bij oude
/// catalogus vaak het jaar van het digitaliseren. Zie `oudeOpnamen` (nieuwe releases) en
/// `Stijlboek.isrcJaar` (radio).
int? isrcJaar(String? isrc) {
  final m = RegExp(r'^[A-Z]{2}[A-Z0-9]{3}(\d{2})\d{5}$').firstMatch((isrc ?? '').trim().toUpperCase());
  if (m == null) return null;
  final jj = int.parse(m.group(1)!);
  return jj >= 40 ? 1900 + jj : 2000 + jj;
}

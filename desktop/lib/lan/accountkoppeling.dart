/// Inloggen is genoeg: de pc herkent een toestel aan het account, zonder Firestore.
///
/// **Waarom dit er moest komen.** Op 02-09-2026, na drie dagen: *"dit ben ik echt beu, dit moet
/// gefixed."* Op het inlogscherm stond dat de accountdatabase zijn daglimiet had bereikt — en daarmee
/// kwam hij nergens meer binnen. Terwijl er niets mis was: zijn wachtwoord klopte, het inloggen zélf
/// werkte, en zijn pc stond twee meter verderop op hetzelfde wifi.
///
/// De oorzaak is de weg, niet de storing. Na het inloggen vroeg het toestel aan **Firestore** welke
/// pc's er onder dit account staan, en de pc schreef via Firestore een sleutel terug. Ligt die ene
/// dienst eruit — of is zijn gratis daglimiet op — dan is er geen enkele andere manier meer, ook al
/// staan die twee apparaten naast elkaar. Eén dienst die hapert sloot je buiten je eigen muziek.
///
/// **De uitweg staat er al, hij werd alleen niet gebruikt.** Twee dingen zijn onafhankelijk van
/// Firestore:
///
/// * de pc roept zichzelf om op het lokale netwerk (`discovery.dart`), dus een toestel kan hem zelf
///   vinden;
/// * inloggen gaat via Identity Toolkit, een ándere dienst met een eigen quotum. Die kan ook nog
///   iets anders: aan een sleutel vertellen van wélk account hij is.
///
/// Samen is dat genoeg. Het toestel vindt de pc op het netwerk en laat zijn verse inlogsleutel zien;
/// de pc vraagt bij Google wiens sleutel dat is en vergelijkt dat met zijn eigen account. Klopt het,
/// dan krijgt het toestel toegang. Geen zes cijfers, geen Firestore.
///
/// **Waarom deze beslissing een eigen, zuiver bestand krijgt.** Dit is een deur. Alles wat hier fout
/// gaat geeft een vreemde toegang tot je hele bibliotheek, en zulke fouten zien er in code precies
/// zo uit als de goede versie. Hier staat de regel één keer, met een toets eromheen.
library;

/// Mag een toestel dat deze sleutel toont bij deze pc naar binnen?
///
/// **Alleen bij een letterlijke gelijkenis van het account.** Geen "leeg telt als gelijk", geen
/// hoofdletterongevoeligheid, geen deelvergelijking — dit zijn geen namen die mensen typen maar
/// id's die Google uitdeelt, en elke soepelheid hier is een gat.
///
/// [uidVanSleutel] is wat Google zegt dat de sleutel is: het antwoord van de opzoeking, en NOOIT
/// iets dat het toestel zelf beweert. Een toestel dat gewoon een uid meestuurt, stuurt de uid van de
/// pc mee zodra het die kent.
///
/// [uidVanPc] is het account waarmee de pc zelf is ingelogd. Is dat leeg, dan is de pc niet
/// ingelogd en valt er niets te vergelijken — dan hoort het antwoord nee te zijn en niet "vooruit
/// dan maar".
bool magKoppelenOpAccount({required String uidVanSleutel, required String uidVanPc}) {
  final a = uidVanSleutel.trim();
  final b = uidVanPc.trim();
  if (a.isEmpty || b.isEmpty) return false;
  return a == b;
}

/// Waarom een aanvraag geweigerd werd, in gewone taal, voor het scherm van het TOESTEL.
///
/// De pc stuurt dit mee terug. Zonder zo'n zin staat er op de telefoon alleen "403", en dan weet je
/// niet of je het verkeerde account gebruikt, of dat je pc simpelweg nog niet ingelogd is — twee
/// heel verschillende dingen, met twee heel verschillende oplossingen.
String koppelweigering({required String uidVanSleutel, required String uidVanPc}) {
  if (uidVanPc.trim().isEmpty) {
    return 'Je pc is niet ingelogd. Log op de pc in met hetzelfde account.';
  }
  if (uidVanSleutel.trim().isEmpty) {
    return 'Je inlogsleutel kon niet nagekeken worden. Log opnieuw in en probeer het nog eens.';
  }
  return 'Deze pc hoort bij een ander account. Log op allebei in met hetzelfde account.';
}

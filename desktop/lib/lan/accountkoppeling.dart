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

import 'dart:convert';

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
    // **Met de uitweg erbij, en dat is een reparatie van 16-09-2026.** Deze zin klopte al, maar hij
    // liet je staan met één weg die dicht zat. Terwijl de zes cijfers er náást liggen en wél werken:
    // die hangen aan de gedeelde sleutel en niet aan een account. Saber probeerde die ochtend zeven
    // keer te koppelen; met deze zin op zijn scherm was hij er in één keer in geweest.
    return 'Je pc is niet ingelogd. Log op de pc in met hetzelfde account, '
        'of koppel met de zes cijfers uit Instellingen op de pc.';
  }
  if (uidVanSleutel.trim().isEmpty) {
    return 'Je inlogsleutel kon niet nagekeken worden. Log opnieuw in en probeer het nog eens.';
  }
  return 'Deze pc hoort bij een ander account. Log op allebei in met hetzelfde account.';
}

/// Klopt deze inlogsleutel op het eerste gezicht? Null als ja, anders waarom niet.
///
/// **Vóór de vraag aan Google, niet in plaats daarvan.** Dit leest alleen wat er in de sleutel
/// staat — voor welk project (`aud`), van wie uitgegeven (`iss`), tot wanneer geldig (`exp`) — en
/// controleert (nog) GEEN handtekening; wie wil kan zo'n sleutel dus namaken. Het beslist daarom
/// nooit "ja": dat doet Google. Het zegt alleen vroeg "nee" tegen rommel, zodat die geen opzoeking
/// kost en het dagbudget van `/pair-cloud` (zie `remming.dart`) niet opmaakt. De handtekening zelf
/// komt erbij in stap 5 van het plan, samen met de bibliotheek die het certificaat maakt.
String? inlogsleutelFout(String sleutel, {required String project, DateTime? nu}) {
  final delen = sleutel.trim().split('.');
  if (delen.length != 3 || delen.any((d) => d.isEmpty)) return 'geen inlogsleutel';
  final Map<String, dynamic> inhoud;
  try {
    final j = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(delen[1]))));
    if (j is! Map<String, dynamic>) return 'onleesbare inlogsleutel';
    inhoud = j;
  } catch (_) {
    return 'onleesbare inlogsleutel';
  }
  if (inhoud['aud'] != project) return 'inlogsleutel voor een ander project';
  if (inhoud['iss'] != 'https://securetoken.google.com/$project') return 'inlogsleutel van een andere uitgever';
  final exp = inhoud['exp'];
  final sub = inhoud['sub'];
  if (exp is! num) return 'inlogsleutel zonder vervaldatum';
  final tijd = (nu ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  if (exp <= tijd) return 'verlopen inlogsleutel';
  if (sub is! String || sub.isEmpty || sub.length > 128) return 'inlogsleutel zonder account';
  return null;
}

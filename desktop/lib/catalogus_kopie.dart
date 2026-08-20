/// De bibliotheek, bewaard op dit toestel zelf.
///
/// **Waarom dit naast de kopie in de cloud bestaat.** Er was er al één — `CatalogMirror` — en die
/// doet precies waarvoor hij bedoeld is: met de pc uit kun je bladeren en downloads klaarzetten.
/// Maar hij komt van Firestore, en dus vraagt hij internet.
///
/// Dat laat één gat open, en juist het gat waarvoor offline bewaren bestaat: in de auto, in de
/// metro, in een vliegtuig. Daar staat de pc uit én is er geen bereik. De muziek stond dan wel op
/// het toestel — de bytes in `offline/` — maar de LIJST niet, en een lijst die er niet is heeft
/// geen albums om op te tikken. Gemeld op 20-08-2026, na het ophalen van een hele plaat: *"ik vind
/// ze echt nergens"*.
///
/// Wat hier ligt is dezelfde catalogus die de pc serveert, onbewerkt weggeschreven. Hij wordt door
/// dezelfde `LibraryStore.adoptMirror` ingelezen als de cloudkopie, dus de albums, persingen en
/// hoezen komen er identiek uit. Het verschil met de cloudkopie is alleen waar hij vandaan komt en
/// dat hij er ALTIJD is.
///
/// Wat er NIET in staat: muziek. Dit is een inhoudsopgave van een paar megabyte; wat je echt kunt
/// afspelen is wat `OfflineStore` heeft opgehaald.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'paths.dart';

class CatalogusKopie {
  const CatalogusKopie();

  File get _bestand => appFile('catalogus.json');

  /// Ernaast, zodat een half weggeschreven bestand nooit het echte overschrijft.
  File get _tijdelijk => appFile('catalogus.json.tmp');

  /// Leg deze catalogus vast. Gooit nooit: een kopie die niet geschreven kon worden is een
  /// teleurstelling in de auto, geen reden om een werkende bibliotheek te laten struikelen.
  Future<void> bewaar(Map<String, dynamic> json) async {
    try {
      // Schrijven en dan pas op zijn plek zetten. Een app die halverwege het schrijven wordt
      // weggehaald -- en Android doet dat ongevraagd -- zou anders een afgekapt bestand achterlaten
      // dat er precies zo uitziet als een goed bestand, en dat is de ene uitkomst waar niemand iets
      // aan heeft: geen lijst, en ook geen melding dat er iets mis is.
      await _tijdelijk.writeAsString(jsonEncode(json), flush: true);
      await _tijdelijk.rename(_bestand.path);
    } catch (e) {
      debugPrint('Catalogus niet bewaard: $e');
    }
  }

  /// Wat er ligt, met wanneer het geschreven is. Null als er niets is of het onleesbaar is.
  Future<({Map<String, dynamic> json, DateTime bijgewerkt})?> lees() async {
    try {
      final f = _bestand;
      if (!await f.exists()) return null;
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      return (json: decoded, bijgewerkt: await f.lastModified());
    } catch (e) {
      // Een onleesbare kopie is een lege kopie. Hij wordt bij de eerstvolgende verbinding met de pc
      // gewoon opnieuw geschreven.
      debugPrint('Catalogus op dit toestel onleesbaar: $e');
      return null;
    }
  }

  /// Weg ermee. Hoort bij ontkoppelen: wie zegt "vergeet die pc" bedoelt niet "maar hou de
  /// inhoudsopgave van mijn muziek nog even".
  Future<void> wis() async {
    for (final f in [_bestand, _tijdelijk]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {/* niets op te ruimen */}
    }
  }
}

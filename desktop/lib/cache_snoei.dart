import 'dart:io';

import 'package:flutter/foundation.dart';

/// Een bovengrens op een cachemap, want geen van deze mappen had er een.
///
/// **Wat er stond, gemeten op 10-08-2026 in `%APPDATA%\DebridMusic`:**
///
///     releaseart    590,1 MB    3501 bestanden      <- voor 236 albums
///     cast_cache     96,2 MB       2 bestanden
///     discogs        61,3 MB    3438 bestanden
///     musicbrainz      47 MB    2962 bestanden
///     covers         37,2 MB     297 bestanden
///     ...                                          samen ruim 1 GB
///
/// Geen enkele daarvan kende een verval-, evictie- of maximumregel. Dat kost geen starttijd — ze
/// worden lui gelezen — maar het is wel jouw schijf, en `releaseart` alleen groeide tot bijna 600 MB.
///
/// **Nieuwste blijft, oudste gaat.** Niet willekeurig en niet op grootte: wat je vandaag bekijkt is
/// wat morgen weer gevraagd wordt, en een hoes die twee jaar geleden één keer opgehaald is heeft geen
/// enkele reden om de plek te bezetten. Een bestand dat weggegooid wordt kost hooguit één keer
/// opnieuw ophalen.
///
/// Draait op de achtergrond na het opstarten, nooit ervoor: dit mag nooit tussen jou en je muziek
/// staan.
Future<int> snoeiMap(Directory map, {required int maxBytes}) async {
  try {
    if (!map.existsSync()) return 0;
    final bestanden = <({File f, int grootte, DateTime tijd})>[];
    var totaal = 0;
    await for (final e in map.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      try {
        final st = e.statSync();
        bestanden.add((f: e, grootte: st.size, tijd: st.modified));
        totaal += st.size;
      } catch (_) {/* net weggehaald door iemand anders */}
    }
    if (totaal <= maxBytes) return 0;

    // Nieuwste eerst, dan naar beneden lopen tot de begroting op is.
    bestanden.sort((a, b) => b.tijd.compareTo(a.tijd));
    var gehouden = 0, bevrijd = 0;
    for (final b in bestanden) {
      if (gehouden + b.grootte <= maxBytes) {
        gehouden += b.grootte;
        continue;
      }
      try {
        b.f.deleteSync();
        bevrijd += b.grootte;
      } catch (_) {/* in gebruik; volgende keer weer */}
    }
    if (bevrijd > 0) {
      debugPrint('${map.path}: ${(bevrijd / 1048576).round()} MB opgeruimd '
          '(was ${(totaal / 1048576).round()} MB, grens ${(maxBytes / 1048576).round()} MB)');
    }
    return bevrijd;
  } catch (e) {
    debugPrint('snoeiMap ${map.path}: $e');
    return 0; // opruimen mag nooit iets breken
  }
}

/// De grenzen per map, en waarom juist die.
///
/// Bewust NIET in deze lijst:
///
/// * `discogs` en `musicbrainz` — dat zijn antwoorden van API's met een verzoekenlimiet. Ze weggooien
///   ruilt schijfruimte in voor netwerkverkeer tegen een muur waar je op kunt lopen, en het zijn
///   duizenden kleine bestanden die samen nog geen tiende van `releaseart` beslaan.
/// * `hoescache` — die ruimt zichzelf al op: hij wordt na elke scan teruggebracht tot precies de
///   bestanden die de bibliotheek nú heeft.
/// * `covers`, `fixcovers`, `resolved`, `artists`, `artistart` — die horen één-op-één bij een album of
///   een artiest die je hebt, dus ze groeien met je bibliotheek mee en niet daarbuiten.
const cacheGrenzen = <String, int>{
  // Alle uitgaves die een albumpagina ooit liet zien, niet alleen de gekozen. Verreweg de grootste,
  // en het enige dat echt losstaat van hoeveel muziek je hebt.
  'releaseart': 300 * 1024 * 1024,
  // Omgezette kopieën voor de Sonos: wegwerpwerk dat zichzelf in een seconde of twee terugmaakt.
  // Er stond al een grens van 24 bestanden, maar één omgezette 24/48 is tientallen MB — dus 24
  // stuks kan 1 GB zijn. Dit is de tweede, echte grens.
  'cast_cache': 200 * 1024 * 1024,
  // Scans van boekjes bij een album. Groeit met wat je opent, niet met wat je hebt.
  'booklets': 100 * 1024 * 1024,
};

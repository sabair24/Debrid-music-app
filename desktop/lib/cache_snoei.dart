import 'dart:io';

import 'package:flutter/foundation.dart';

import 'organize.dart' show normKey;

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
///
/// [perMap] gooit hele ONDERMAPPEN weg in plaats van losse bestanden, en dat is geen detail maar de
/// reparatie van een bug die de cd van albums liet verdwijnen.
///
/// **Wat er misging.** `releaseart` bewaart per album een mapje met `front`, `back`, `disc` en een
/// merkteken `done`. Dat merkteken is 1 byte en wordt als LAATSTE geschreven, dus het heeft altijd
/// de nieuwste tijd. Deze snoei sorteerde nieuwste eerst en gooide per bestand weg — dus `done`
/// overleefde gegarandeerd, terwijl `disc.jpg` van een paar honderd kB als eerste sneuvelde.
///
/// Wat er dan overblijft is een map die zegt "hier is alles al opgehaald", zonder cd erin. En
/// `releaseArt` kijkt naar precies dat merkteken en slaat de hele zoektocht over. Eén snoeibeurt en
/// de cd was **voorgoed** weg — er is geen vervaltijd en niets dat die map ooit ongeldig verklaart.
///
/// Een mapje is dus één ondeelbaar ding: helemaal houden of helemaal weg. Weg kost één keer opnieuw
/// ophalen, precies zoals de bedoeling was.
///
/// [houd] (alleen met [perMap]): een ondermap die hierop waar geeft, blijft altijd — ook boven de grens. Voor de scans van
/// albums die op een toestel bewaard zijn ([gezienVoor]): zonder pc moeten die er nog staan.
Future<int> snoeiMap(Directory map, {required int maxBytes, bool perMap = false, bool Function(Directory map)? houd}) async {
  try {
    if (!map.existsSync()) return 0;
    final bestanden = <({FileSystemEntity f, int grootte, DateTime tijd})>[];
    var totaal = 0, beschermd = 0;
    if (perMap) {
      await for (final sub in map.list(followLinks: false)) {
        if (sub is! Directory) continue;
        var grootte = 0;
        DateTime? nieuwste;
        try {
          await for (final e in sub.list(recursive: true, followLinks: false)) {
            if (e is! File) continue;
            final st = e.statSync();
            grootte += st.size;
            // De NIEUWSTE tijd in het mapje telt. Het mapje is één ding, en het is zo vers als het
            // laatst geschreven bestand erin.
            if (nieuwste == null || st.modified.isAfter(nieuwste)) nieuwste = st.modified;
          }
        } catch (_) {/* net weggehaald door iemand anders */}
        if (nieuwste == null) continue;
        totaal += grootte;
        // Wat blijft, telt wel mee in het totaal maar staat niet in de rij van wat weg kan.
        if (houd != null && houd(sub)) {
          beschermd += grootte;
          continue;
        }
        bestanden.add((f: sub, grootte: grootte, tijd: nieuwste));
      }
    } else {
      await for (final e in map.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        try {
          final st = e.statSync();
          bestanden.add((f: e, grootte: st.size, tijd: st.modified));
          totaal += st.size;
        } catch (_) {/* net weggehaald door iemand anders */}
      }
    }
    if (totaal <= maxBytes) return 0;

    // Nieuwste eerst, dan naar beneden lopen tot de begroting op is.
    bestanden.sort((a, b) => b.tijd.compareTo(a.tijd));
    var gehouden = beschermd, bevrijd = 0;
    for (final b in bestanden) {
      if (gehouden + b.grootte <= maxBytes) {
        gehouden += b.grootte;
        continue;
      }
      try {
        final f = b.f;
        if (f is Directory) {
          f.deleteSync(recursive: true);
        } else {
          f.deleteSync();
        }
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
  //
  // 3 GB sinds 21-10-2026: met 300 MB had de pc de scans van 339 van de 811 albums, de rest was al weg —
  // en een toestel dat de cd van de pc vraagt (`DiscogsArtwork.vanDePc`) kreeg dan niets. Gemeten: een
  // album kost ~1,1 MB (voorkant, achterkant, cd), de hele bibliotheek dus ~0,9 GB; de rest is ruimte voor
  // de uitgaves die je in de galerij bekijkt. Op deze pc is er 1,3 TB vrij.
  'releaseart': 3 * 1024 * 1024 * 1024,
  // Omgezette kopieën voor de Sonos: wegwerpwerk dat zichzelf in een seconde of twee terugmaakt.
  // Er stond al een grens van 24 bestanden, maar één omgezette 24/48 is tientallen MB — dus 24
  // stuks kan 1 GB zijn. Dit is de tweede, echte grens.
  'cast_cache': 200 * 1024 * 1024,
  // Omgezette kopieën voor een gekoppeld toestel op mobiele data. Een eigen map naast `cast_cache`,
  // en niet omdat de bytes zouden botsen: een avond casten mag niet het album wegdrukken waar de
  // telefoon halverwege in zit, en andersom net zo. Ruimer dan cast, want dit is een hele plaat die
  // iemand aan het luisteren is en niet één nummer op een speaker.
  'stream_cache': 400 * 1024 * 1024,
  // Scans van boekjes bij een album. Groeit met wat je opent, niet met wat je hebt.
  'booklets': 100 * 1024 * 1024,
};

/// De grens voor `releaseart` op een TOESTEL (gsm, iPad, Mac, Shield) — op de pc is het [cacheGrenzen].
///
/// **Waarom (Saber, 31-10-2026).** Op de Mac stond `releaseart` op 800 MB: op een toestel werd er nooit gesnoeid, alleen op
/// de pc (na de scan). Saber: *"ok, maar ik ga toch alles zien e"* — ja: de pc bewaart alles (3 GB, de hele bibliotheek is
/// ~0,9 GB), en een album dat hier weg is, vraagt het toestel bij het openen weer aan de pc (`DiscogsArtwork.vanDePc`,
/// altijd op volle grootte). Wat weg gaat is wat het langst niet getoond is ([gezienMerk]); wat op dit toestel bewaard
/// is, blijft ([gezienVoor]). ~1,1 MB per album, dus zo'n 270 albums blijven hier staan.
const kReleaseartToestel = 300 * 1024 * 1024;

/// Wanneer de scans in [map] het laatst getoond werden, en van welk album ze zijn: het bestandje `gezien`
/// (artiest, een nieuwe regel, album). [snoeiMap] houdt per map de nieuwste tijd aan, dus wat je net bekeek, staat
/// vooraan.
///
/// Hoogstens eens per twaalf uur opnieuw geschreven: een albumpagina vraagt de scans bij elke hertekening.
Future<void> gezienMerk(Directory map, String artiest, String album, {DateTime? nu}) async {
  try {
    if (!await map.exists()) return;
    final f = File('${map.path}${Platform.pathSeparator}gezien');
    final tijd = nu ?? DateTime.now();
    if (await f.exists() && tijd.difference(await f.lastModified()) < const Duration(hours: 12)) return;
    await f.writeAsString('$artiest\n$album');
  } catch (_) {/* niet kunnen merken is geen reden om de hoes niet te tonen */}
}

/// Hoort [map] bij een van [albums] (genormaliseerde albumtitels, [normKey])? Op de titel alleen: een album met dezelfde
/// titel van iemand anders blijft dan ook staan, en dat kost hooguit een megabyte. Zonder `gezien` (van vóór 31-10-2026):
/// onbekend, dus niet beschermd.
bool gezienVoor(Directory map, Set<String> albums) {
  if (albums.isEmpty) return false;
  try {
    final f = File('${map.path}${Platform.pathSeparator}gezien');
    if (!f.existsSync()) return false;
    final regels = f.readAsLinesSync();
    return regels.length > 1 && albums.contains(normKey(regels[1]));
  } catch (_) {
    return false;
  }
}

/// Welke van die mappen per ONDERMAP gesnoeid moeten worden in plaats van per bestand.
///
/// `releaseart/<sleutel>/{front,back,disc,done}` en `booklets/<sleutel>/<bladzijden>` zijn allebei
/// sets die alleen als geheel iets betekenen. Losse bestanden eruit trekken laat een map achter die
/// beweert compleet te zijn maar het niet is — en bij `releaseart` betekende dat een album dat
/// voorgoed zonder cd zat. Zie [snoeiMap].
///
/// `cast_cache` en `stream_cache` staan er bewust niet in: dat zijn losse omgezette bestanden zonder
/// onderling verband.
const cachePerMap = <String>{'releaseart', 'booklets'};

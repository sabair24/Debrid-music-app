/// De regels waarmee de startpagina zijn rijen vult.
///
/// **Waarom een eigen bestand.** Deze regels zaten verspreid: een stukje in `catalog.dart`, een
/// stukje in `recommend.dart`, en het meeste helemaal niet — het stond als `.take(15)` midden in
/// `main.dart`, waar geen test bij kan. Ze zijn zuiver, ze gaan alleen over lijsten, en ze horen
/// dus op een plek waar een test ze kan uitschrijven zonder een venster te bouwen. Dezelfde
/// afweging als bij `schudvolgorde.dart`.
///
/// `catalog.dart` blijft daarmee wat het is: kaal HTTP zonder `dart:io`.
library;

import 'catalog.dart';
import 'organize.dart' show artistKey;

/// Hoogstens [max] regels per artiest, in de volgorde waarin ze binnenkwamen.
///
/// **Waarom dit moest bestaan.** Op de startpagina stond nergens een rantsoen. Geteld op een
/// schermafdruk van 02-09-2026: van de 17 tegels onder "Aanbevolen voor jou" kwamen er 9 van vier
/// artiesten (Captain Hollywood Project 3×, 2 Brothers On The 4th Floor 2×, Acda en de Munnik 2×,
/// Enrique Iglesias 2×), en onder "Nieuw van jouw artiesten" kwamen 17 van de 18 tegels van vier
/// artiesten (Timmy Trumpet 5×, Slimane 4×, Shakira 4×, Dr. Alban 4×). Dat is wat "te weinig
/// variatie" in getallen is.
///
/// De oorzaak lag op twee plekken: `latestFromArtists` nam vier albums per artiest en
/// `RecommendService.discover` zes toptracks per verwante artiest, en daarna ontdubbelde geen van
/// beide op ARTIEST — alleen op titel. Eén artiest die je nog niet bezit kon dus de hele rij vullen.
///
/// Via [artistKey], want die vouwt accenten en hoofdletters weg: "Beyonce" en "Beyoncé" zijn hier
/// één artiest, anders telt dezelfde persoon twee keer mee tegen het rantsoen.
///
/// De VOLGORDE blijft staan. Wie hier sorteert of schudt haalt de rangschikking weg die de
/// aanroeper er net in heeft gelegd — bij een hitlijst is dat de hitlijst zelf.
List<T> maxPerArtiest<T>(List<T> regels, String Function(T) artiestVan, int max) {
  if (max <= 0) return const [];
  final geteld = <String, int>{};
  final uit = <T>[];
  for (final r in regels) {
    final sleutel = artistKey(artiestVan(r));
    // Een lege artiestnaam krijgt geen eigen emmer: dan zou "" één rantsoen delen met alles wat
    // ongeïdentificeerd binnenkomt, en dat is precies waar zo'n rij vol mee kan lopen.
    if (sleutel.isEmpty) continue;
    final n = geteld[sleutel] ?? 0;
    if (n >= max) continue;
    geteld[sleutel] = n + 1;
    uit.add(r);
  }
  return uit;
}

/// Weg met een rugcatalogus die in één klap opnieuw bij de dienst is aangeleverd.
///
/// **Dit is de Dr. Alban-regel, en hij bestaat omdat een jaarfilter hier niet genoeg is.**
///
/// Gemeld op 02-09-2026: onder "Nieuw van jouw artiesten" stonden vier platen van Dr. Alban, een
/// artiest uit de jaren 90. Het jaarfilter [uitJaar] leek de oplossing — maar nagemeten bij Deezer
/// (`/artist/999/albums`) staat er dit:
///
///     It's My Life           album  2026-01-28
///     Look Who's Talking     album  2026-01-28
///     One Love               album  2026-01-28
///     Look Who's Talking     ep     2026-01-28
///
/// Zijn hele catalogus draagt de datum van de dag waarop hij opnieuw is aangeleverd. Een jaarfilter
/// laat die dus gewoon door, en er staat geen "remaster" of "reissue" in de titel om op te vangen.
///
/// Wat een herlevering wél verraadt, is het BLOK: drie of meer uitgaven van één artiest op exact
/// dezelfde dag. Een echte nieuwe plaat staat alleen op zijn datum — nagemeten bij Backstreet Boys
/// (2025-11-07 één regel, 2025-07-11 één regel) en Michael Jackson (2025-09-23 één regel).
///
/// **Drempel drie en niet twee**, en dat is met opzet: Beyoncé heeft twee singles op 2024-02-09 en
/// dat is een gewone dubbele uitgave, geen dump.
///
/// Tel over ALLE soorten — album, ep én single. Dr. Alban heeft er op die ene dag drie albums, twee
/// ep's en een single staan; wie eerst de singles wegfiltert telt er nog maar drie en haalt de
/// drempel net niet. Deze functie hoort dus vóór elk soortfilter te draaien.
List<CatalogAlbumHit> zonderHerlevering(List<CatalogAlbumHit> hits, {int drempel = 3}) {
  final perDag = <String, int>{};
  for (final h in hits) {
    final datum = h.album.releaseDate;
    if (datum == null || datum.isEmpty) continue;
    final sleutel = '${artistKey(h.artist)}|$datum';
    perDag[sleutel] = (perDag[sleutel] ?? 0) + 1;
  }
  return [
    for (final h in hits)
      if ((perDag['${artistKey(h.artist)}|${h.album.releaseDate ?? ''}'] ?? 0) < drempel) h,
  ];
}

/// Alleen wat in [jaren] is uitgekomen.
///
/// Naast [uitJaar], dat op één jaar filtert en door de hero-carrousel gebruikt wordt. De rij
/// "Nieuw van jouw artiesten" wil er twee: op alleen het huidige jaar houd je er in januari geen
/// enkele over, en dan staat er een lege plek waar de kop "Nieuw" belooft.
List<CatalogAlbumHit> uitJaren(List<CatalogAlbumHit> hits, Set<int> jaren) =>
    [for (final h in hits) if (jaren.contains(int.tryParse(h.album.year ?? ''))) h];

/// De sleutel waaronder een plaat als "die heb ik al" telt: artiest en titel, allebei gevouwen.
String bezitssleutel(String artiest, String titel) => '${artistKey(artiest)}|${artistKey(titel)}';

/// Deezers genrenummers, zoals `GET /genre` ze op 02-09-2026 teruggaf.
///
/// Als namen en niet als losse getallen, want `chart/113` zegt niemand iets en `dance` wel.
class Genre {
  static const pop = 132;
  static const dance = 113;
  static const electro = 106;
  static const rnb = 165;
  static const soulFunk = 169;
  static const rock = 152;
  static const alternative = 85;
  static const rap = 116;
  static const chanson = 52;
  static const reggae = 144;
  static const latin = 197;
  static const metal = 464;
  static const afrikaans = 2;
  static const arabisch = 12;
  static const nederlandstalig = 518;
  static const jazz = 129;
  static const klassiek = 98;
  static const blues = 153;
  static const folk = 466;
}

/// Van een genretag of Discogs-stijl naar het genre waar Deezer een hitlijst voor heeft.
///
/// **Waarom een tabel en geen slimmigheid.** De tags in deze bibliotheek komen uit twee werelden:
/// wat de ripper in het bestand zette (1063 van de 1239 nummers hebben er een) en de stijlen die
/// Discogs per album levert. Die schrijven hetzelfde anders — "R&B", "Contemporary R&B",
/// "Soul / Funk / R&B" — en Deezer kent maar vijfentwintig genres. Een tabel is hier eerlijker dan
/// een regel: je kunt hem nalezen en er iets aan zien.
///
/// **De regel over "Hardcore" gaat tegen zijn eigen woord in, en dat is met opzet.** In deze
/// bibliotheek staan 85 nummers met die tag, naast 129 Discogs-stijlen "Electronic", 21 "Euro
/// House" en 21 "Eurodance". Dat is hardcore TECHNO, niet metal. Zonder deze regel wordt de op één
/// na grootste tag van de gebruiker een metal-hitlijst, en dan gaat de rij nog verder van hem af
/// staan dan hij al stond.
int? deezerGenre(String tag) {
  final t = tag.toLowerCase().trim();
  if (t.isEmpty) return null;
  bool bevat(List<String> woorden) => woorden.any(t.contains);

  // Volgorde telt: het meest specifieke eerst. "Contemporary R&B" moet R&B worden en niet
  // struikelen over een bredere regel erboven.
  if (bevat(['nederlandstalig', 'nederpop', 'levenslied'])) return Genre.nederlandstalig;
  if (bevat(['chanson', 'variété', 'variete', 'française', 'francaise'])) return Genre.chanson;
  if (bevat(['raï', 'rai ', 'arabic', 'arabisch', 'maghreb'])) return Genre.arabisch;
  if (bevat(['afrobeat', 'african', 'afrikaans', 'soukous'])) return Genre.afrikaans;
  if (bevat(['r&b', 'rnb', 'rhythm and blues'])) return Genre.rnb;
  if (bevat(['soul', 'funk', 'disco', 'motown'])) return Genre.soulFunk;
  if (bevat(['hip hop', 'hip-hop', 'rap', 'trap', 'grime'])) return Genre.rap;
  if (bevat(['reggae', 'dancehall', 'ragga', 'ska'])) return Genre.reggae;
  if (bevat(['latin', 'salsa', 'reggaeton', 'bachata', 'merengue'])) return Genre.latin;
  if (bevat(['jazz', 'bebop', 'swing'])) return Genre.jazz;
  if (bevat(['blues'])) return Genre.blues;
  if (bevat(['folk', 'country', 'americana'])) return Genre.folk;
  if (bevat(['classical', 'klassiek', 'opera', 'baroque'])) return Genre.klassiek;
  // Hardcore vóór metal, en vóór de brede dance-regel: zie de uitleg hierboven.
  if (bevat(['hardcore', 'gabber', 'hardstyle'])) return Genre.dance;
  if (bevat(['metal', 'thrash', 'doom', 'sludge'])) return Genre.metal;
  if (bevat(['house', 'trance', 'techno', 'dance', 'eurodance', 'garage', 'club'])) {
    return Genre.dance;
  }
  if (bevat(['electro', 'electronic', 'synth', 'downtempo', 'ambient', 'idm'])) {
    return Genre.electro;
  }
  if (bevat(['alternative', 'indie', 'grunge', 'shoegaze'])) return Genre.alternative;
  if (bevat(['rock', 'punk', 'new wave'])) return Genre.rock;
  if (bevat(['pop'])) return Genre.pop;
  return null;
}

/// Het decennium waar deze bibliotheek zijn zwaartepunt heeft.
///
/// **Waarom dit een rij waard is.** Gemeten in deze bibliotheek: 6 nummers uit de jaren 60, 17 uit
/// de 70, 70 uit de 80, **448 uit de 90**, 374 uit de jaren 2000, 203 uit de 10 en 92 uit de 20.
/// Dat is geen vlakke verdeling maar een duidelijk midden, en een rij die dat midden aanspreekt
/// raakt vaker doel dan welke aanbeveling ook.
///
/// [overslaan] laat de aanroeper om de beurt een ander decennium tonen: eerst de 90, dan de 2000,
/// dan de 10. Anders staat er elke keer dezelfde rij, en dan is het een stempel in plaats van een
/// suggestie.
///
/// Null als er te weinig is om iets over te zeggen — bij minder dan [drempel] nummers in het
/// grootste decennium is "jouw jaren 90" een bewering die de bibliotheek niet draagt.
int? zwaartepuntDecennium(Iterable<int?> jaren, {int drempel = 20, int overslaan = 0}) {
  final telling = <int, int>{};
  for (final j in jaren) {
    if (j == null || j < 1900 || j > 2100) continue;
    final d = (j ~/ 10) * 10;
    telling[d] = (telling[d] ?? 0) + 1;
  }
  final gesorteerd = telling.entries.where((e) => e.value >= drempel).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (gesorteerd.isEmpty) return null;
  return gesorteerd[overslaan % gesorteerd.length].key;
}

/// De genres waar deze bibliotheek werkelijk over gaat, zwaarste eerst.
///
/// **Waarom uit de bibliotheek en niet uit Deezer.** "Top van dit moment" haalde letterlijk
/// `chart/0/albums` op: Deezers algemene hitlijst, zonder één woord over de gebruiker. Vandaar dat
/// er bij iemand met 448 nummers uit de jaren 90 en een kast vol pop, R&B en dance een sludge-
/// metalband en twee musicalopnamen in die rij stonden.
///
/// Dit profiel kost nul verzoeken: het telt de tags die er al liggen. [perGenre] is er zodat een
/// enkel raar album de rij niet kan kapen — één plaat met een tag wordt geen genre.
List<int> genreProfiel(Iterable<String?> tags, {int max = 6, int drempel = 3}) {
  final telling = <int, int>{};
  for (final tag in tags) {
    final g = deezerGenre(tag ?? '');
    if (g == null) continue;
    telling[g] = (telling[g] ?? 0) + 1;
  }
  final uit = [
    for (final e in telling.entries)
      if (e.value >= drempel) e,
  ]..sort((a, b) => b.value.compareTo(a.value));
  return [for (final e in uit.take(max)) e.key];
}

/// De hele rij "Nieuw van jouw artiesten", van rauwe Deezer-oogst naar wat er op het scherm hoort.
///
/// **Eén regel op één plek, en dat is het punt.** De losse zeven bestonden al of zijn hierboven
/// gebouwd, maar ze werden nergens toegepast: `main.dart` gaf de rauwe lijst rechtstreeks aan de rij
/// door. Zolang die stap los blijft, kan de volgende bewerking hem weer overslaan.
///
/// De volgorde is niet vrij:
///
/// 1. **[zonderHerlevering] eerst, vóór het singlefilter.** Dr. Alban heeft op zijn herleverdatum
///    drie albums, twee ep's en een single staan. Wie eerst de singles wegzeeft telt er nog maar
///    drie en haalt de drempel nét niet — dan glipt de hele dump er alsnog doorheen.
/// 2. dan de jaren, want pas daarna gaat het over "nieuw";
/// 3. dan de singles eruit — een rij albumtegels hoort geen losse singles te tonen;
/// 4. dan wat je al hebt;
/// 5. en als laatste het rantsoen per artiest, zodat het rantsoen over de OVERGEBLEVEN platen gaat
///    en niet over platen die er toch al uit vielen.
List<CatalogAlbumHit> nieuwVanJouwArtiesten(
  List<CatalogAlbumHit> ruw, {
  required Set<int> jaren,
  Set<String> alInBezit = const {},
  int perArtiest = 1,
}) {
  var uit = zonderHerlevering(ruw);
  uit = uitJaren(uit, jaren);
  uit = [for (final h in uit) if (!h.album.isSingle) h];
  if (alInBezit.isNotEmpty) {
    uit = [
      for (final h in uit)
        if (!alInBezit.contains(bezitssleutel(h.artist, h.album.title))) h,
    ];
  }
  return maxPerArtiest(uit, (h) => h.artist, perArtiest);
}

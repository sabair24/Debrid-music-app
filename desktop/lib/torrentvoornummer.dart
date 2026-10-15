/// Hoort een torrent bij het nummer of het album waaronder hij staat?
///
/// **Waarom dit er is.** Gemeld op 15-10-2026, onder Céline Dions "Bonjour, Pardon, Merci (Bon
/// Entendeur Remix)": *"die geven gewoon alles van Céline Dion, dat is niet de bedoeling."* Gemeten:
/// RuTracker zoekt alleen in torrentnamen, vond op de hele vraag niets, zocht toen ruimer op
/// "Céline Dion" en gaf 50 torrents terug. Alle 46 die de lijst haalden waren ándere platen — de
/// soundtrack van *I Am: Celine Dion*, *A New Day Has Come*, een verzameling singles van 1990–2003.
/// Geen enkele kon een remix van september 2026 bevatten, en de bovenste (gecacht, 24/192) zag er het
/// best uit van allemaal.
///
/// **Wat blijft staan.** Een torrent die het nummer of de plaat bij naam noemt, en een discografie of
/// verzameling van de artiest waarvan de jaren het nummer kúnnen bevatten. Heeft TorBox de torrent al,
/// dan beslist zijn bestandenlijst: het nummer staat erin of niet.
///
/// **Wat verdwijnt, verdwijnt niet stil.** Het scherm zegt hoeveel er verborgen zijn en waarom, met een
/// knop om ze toch te zien — een tracker mag een plaat anders noemen dan de catalogus.
///
/// Zuiver: tekst in, oordeel uit. Geen netwerk, geen scherm.
library;

import 'audioformaten.dart' show isAudioBestand;
import 'discogs.dart' show DiscogsService;
import 'organize.dart' show fileOffersTitle, normKey, versionMarkers, withoutVersionText;

enum TorrentPast {
  /// De bestandenlijst (van TorBox) heeft een bestand dat dit nummer is.
  bevat,

  /// De naam noemt het nummer, met zijn versie.
  nummer,

  /// De naam noemt de plaat waar het nummer op staat.
  album,

  /// Een discografie of verzameling van de artiest, en de jaren sluiten het nummer niet uit.
  verzameling,

  /// Iets anders van dezelfde artiest — of van iemand anders.
  anders,

  /// De bestandenlijst is bekend en het nummer staat er niet in.
  mist,
}

extension TorrentPastZicht on TorrentPast {
  bool get zichtbaar => this != TorrentPast.anders && this != TorrentPast.mist;
}

/// Woorden die niets zeggen over welke plaat het is, en die een tracker vaak anders schrijft.
const _vulwoorden = {'and', 'the', 'en', 'et', 'und', 'y', 'feat', 'ft', 'featuring', 'with'};

/// De woorden van een naam, met dezelfde vouwing als overal: geen accenten, geen leestekens.
Set<String> _woorden(String s) => {
      for (final w in normKey(s).split(' '))
        if ((w.length > 1 || RegExp(r'\d').hasMatch(w)) && !_vulwoorden.contains(w)) w,
    };

/// Staat [w] in [naam] — ook als meervoud of vervoeging ("remix" in "remixes", "remixed")?
bool _dekt(Set<String> naam, String w) =>
    naam.contains(w) ||
    (w.length >= 4 && naam.any((n) => n.length > w.length && n.length - w.length <= 3 && n.startsWith(w)));

/// Noemt [naam] deze titel? Alle woorden van de titel zonder versie, en — als de titel een versie
/// draagt — minstens één woord van die versie. "Bonjour, Pardon, Merci - Single" noemt de remix dus
/// níét; "Bonjour, Pardon, Merci (Remixes)" wel.
bool _noemt(Set<String> naam, String titel) {
  final basis = _woorden(withoutVersionText(titel));
  if (basis.isEmpty || !basis.every((w) => _dekt(naam, w))) return false;
  final merken = versionMarkers(titel);
  if (merken.isEmpty) return true;
  return merken.expand((m) => _woorden(m)).any((w) => _dekt(naam, w));
}

/// De hoofdartiest, zonder gasten: "Lil' Kim feat. Phil Collins" → "Lil' Kim".
String _hoofdartiest(String artiest) => artiest
    .split(RegExp(r'\s+(?:feat\.?|ft\.?|featuring|with|&|x|vs\.?)\s+|,', caseSensitive: false))
    .first
    .trim();

/// Noemt [naam] de artiest? Eén woord van drie letters of meer volstaat: trackers schrijven "Céline
/// Dion / Celine Dion", "Dion, Celine" of alleen de achternaam.
bool _noemtArtiest(Set<String> naam, String artiest) {
  final w = _woorden(_hoofdartiest(artiest)).where((w) => w.length >= 3).toSet();
  return w.isEmpty || w.any((x) => _dekt(naam, x));
}

/// Een discografie, een verzameling, een box: iets dat veel platen van één artiest draagt.
///
/// Op de RUWE naam en niet na [normKey]: daar verdwijnt het Cyrillisch, en RuTracker schrijft
/// "Дискография" en "Коллекция".
///
/// Ook een best-of: "The Very Best Of Celine Dion - 1999" noemt "My Heart Will Go On" niet, maar
/// draagt hem wel. Het jaartal houdt hem weg bij wat later verscheen.
final _verzamelwoord = RegExp(
    r'(discograph|дискограф|коллекци|collection|complete|anthology|\bsingles\b|\balbums\b|'
    r'альбом|сборник|box\s*set|boxset|best\s+of|greatest|\bhits\b|essential)',
    caseSensitive: false);

/// Een versie zonder de zanger, of door iemand anders gezongen.
final _zonderStem = RegExp(
    r'\b(instrumental|karaoke|a ?capp?ella|backing track|minus one|in the style of|tribute to|piano version)\b',
    caseSensitive: false);

/// Een vinylrip per kant: "01. Side A.flac", "Kant B".
final _kant = RegExp(r'\b(side|kant|face|seite)\s*[a-h1-8]\b', caseSensitive: false);

/// Het laatste jaar dat een naam noemt — "(1990-2003)" → 2003 — of null.
int? laatsteJaar(String naam) {
  int? hoogste;
  for (final m in RegExp(r'(?<!\d)(19[5-9]\d|20[0-4]\d)(?!\d)').allMatches(naam)) {
    final j = int.parse(m.group(1)!);
    if (hoogste == null || j > hoogste) hoogste = j;
  }
  return hoogste;
}

/// Het oordeel over één torrent.
///
/// [titel] is het nummer (null op de albumlijst), [album] de plaat, [jaar] het jaar van de plaat.
/// [bestanden] is wat TorBox over de inhoud weet, of null als dat niet bekend is.
TorrentPast torrentVoorNummer(
  String naam, {
  required String artiest,
  String? titel,
  int? seconden,
  String? album,
  int? jaar,
  List<String>? bestanden,
}) {
  final t = titel?.trim() ?? '';
  // De bestandenlijst gaat voor alles: dat is geen vermoeden over de naam, dat is de inhoud.
  if (bestanden != null && t.isNotEmpty) {
    final audio = bestanden.where(isAudioBestand).toList();
    if (audio.any((p) => fileOffersTitle(t, seconden, artiest, p, null, album: album))) {
      return TorrentPast.bevat;
    }
    // "Mist" alleen als de bestanden nummers zíjn. Eén groot bestand met een cue erbij, of een
    // vinylrip per kant ("01. Side A.flac" — zo staat de gecachte *I Am* bij TorBox), draagt de
    // titels niet in zijn namen; dan beslist de naam van de torrent, net als zonder lijst.
    final ondoorzichtig = audio.isEmpty ||
        bestanden.any((p) => p.toLowerCase().endsWith('.cue')) ||
        audio.any((p) => _kant.hasMatch(p.split('/').last));
    if (!ondoorzichtig) return TorrentPast.mist;
  }
  final woorden = _woorden(naam);
  final artiestErin = _noemtArtiest(woorden, artiest);
  // Een instrumentale of karaokeversie is een ander nummer, tenzij je die zelf zoekt. Gezien op de pc
  // (15-10-2026) onder "My Heart Will Go On": "Céline Dion - My Heart Will Go On (Instrumental).mp3".
  // Remixen en "Mixes" niet: zo'n cd-single draagt meestal ook het origineel.
  if (_zonderStem.hasMatch(naam) && !_zonderStem.hasMatch(t)) return TorrentPast.anders;
  if (t.isNotEmpty && artiestErin && _noemt(woorden, t)) return TorrentPast.nummer;
  final a = album?.trim() ?? '';
  if (a.isNotEmpty && artiestErin && _noemt(woorden, DiscogsService.plainTitle(a))) {
    return TorrentPast.album;
  }
  if (artiestErin && _verzamelwoord.hasMatch(naam)) {
    final tot = laatsteJaar(naam);
    // Een verzameling tot 2003 kan een plaat uit 2026 niet dragen. Zonder jaren valt het niet uit te
    // sluiten, en dan blijft hij staan.
    if (jaar != null && tot != null && tot < jaar) return TorrentPast.anders;
    return TorrentPast.verzameling;
  }
  return TorrentPast.anders;
}

/// Hoe hoog een oordeel in de lijst staat. Binnen een oordeel blijft de volgorde van de zoektocht
/// (gecacht eerst, dan seeders) staan.
int torrentPastRang(TorrentPast p) => p.index;

/// [lijst] op oordeel, en binnen een oordeel in de volgorde waarin hij binnenkwam.
///
/// Zelf stabiel gemaakt: `List.sort` in Dart belooft dat niet, en dan wisselen twee even goede
/// torrents per keer tekenen van plaats.
List<T> opTorrentRang<T>(List<T> lijst, TorrentPast Function(T) oordeel) {
  final metPlaats = [for (var i = 0; i < lijst.length; i++) (i, lijst[i])];
  metPlaats.sort((a, b) {
    final r = torrentPastRang(oordeel(a.$2)).compareTo(torrentPastRang(oordeel(b.$2)));
    return r != 0 ? r : a.$1.compareTo(b.$1);
  });
  return [for (final p in metPlaats) p.$2];
}

/// De regel boven de lijst als er torrents verborgen zijn. [mist] is het deel waarvan TorBox' lijst
/// zegt dat het nummer er niet in staat; [nummer] is onwaar op de albumlijst.
String verborgenTorrentsZin(int aantal, {int mist = 0, bool nummer = true}) {
  final wat = nummer ? 'dit nummer' : 'deze plaat';
  final noemen = aantal - mist;
  final kop = '$aantal ${aantal == 1 ? 'torrent' : 'torrents'} verborgen';
  final een = aantal == 1;
  if (mist == 0) return '$kop — ${een ? 'hij noemt' : 'ze noemen'} $wat niet.';
  if (noemen == 0) return '$kop — volgens TorBox zit $wat er niet in.';
  return '$kop: $noemen ${noemen == 1 ? 'noemt' : 'noemen'} $wat niet, '
      'bij $mist zegt TorBox dat het er niet in zit.';
}

/// Het merkje op een torrent in de lijst, of null.
String? torrentMerk(TorrentPast p, {bool nummer = true}) => switch (p) {
      TorrentPast.bevat => '✓ bevat dit nummer',
      TorrentPast.mist => 'zit er niet in',
      TorrentPast.anders => nummer ? 'noemt dit nummer niet' : 'noemt deze plaat niet',
      _ => null,
    };

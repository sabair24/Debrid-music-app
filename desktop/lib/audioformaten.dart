/// Welke bestanden deze app als muziek beschouwt — op één plek.
///
/// **Waarom dit bestand er is.** Deze vraag werd op VIJF plekken los van elkaar beantwoord, en de
/// vijf antwoorden waren alle vijf anders: de bibliotheekscan, twee lijsten in `organize.dart`,
/// `TbFile.isAudio` en `TorrentBestand.isAudio`. Dat is niet netjes-maar-onschuldig; elk verschil is
/// een manier waarop muziek verdwijnt zonder één woord:
///
/// * stond een soort niet in de scanlijst, dan kwam het bestand nooit in je bibliotheek — het stond
///   wél op je schijf. Dat was de `.ape`/`.wv`-lek van 29-08-2026.
/// * stond hij niet in `isAudio`, dan weigerde de app de hele torrent met "geen afspeelbare audio".
///   Een DSD-rip van vinyl kreeg dat te horen ná vier en een halve minuut wachten.
/// * stond hij niet in de opruimlijst van `organize.dart`, dan bleef het bestand voor eeuwig in je
///   downloadmap liggen in plaats van in de nette boom te belanden.
///
/// **De maatstaf om erin te staan** is niet "bestaat dit formaat" maar: kan de app het AFSPELEN en
/// kan hij het OMZETTEN voor een speaker. Het eerste doet libmpv, het tweede ffmpeg, en die lezen
/// allebei alles wat hieronder staat. Hoorspelen en gesproken boeken (`.m4b`, `.aax`) staan er met
/// opzet niet in: die horen niet tussen je platen.
library;

/// Formaten die geen enkel bit van het origineel weggooien.
///
/// `m4a` staat hier NIET, en dat is geen vergissing: die doos kan zowel ALAC (verliesvrij) als AAC
/// (verliesgevend) bevatten, en aan de naam is niet te zien welke. Raden zou het gouden merkje op
/// een gewone AAC plakken.
const Set<String> verliesvrijeSoorten = {
  'flac',
  'alac',
  'ape', // Monkey's Audio
  'wv', // WavPack
  'tta', // True Audio
  'tak',
  'als', // MPEG-4 ALS
  'shn', // Shorten — oude live-opnames
  'wav',
  'aiff',
  'aif',
  'aifc',
  // DSD, oftewel een SACD-rip. Geen PCM, maar zeker niets weggegooid.
  'dsf',
  'dff',
};

/// Formaten die wél iets weggooien, plus dozen waarvan de inhoud niet aan de naam te zien is.
const Set<String> verliesgevendeSoorten = {
  'mp3',
  'mp2',
  'm4a',
  'aac',
  'ogg',
  'oga',
  'opus',
  'wma',
  'mpc', // Musepack
  'spx', // Speex
  'ac3',
  'dts',
  'mka', // Matroska-audio: kan van alles bevatten, dus nooit een verliesvrij merkje
};

/// Alles bij elkaar, zonder punt, kleine letters.
final Set<String> audioSoorten = {...verliesvrijeSoorten, ...verliesgevendeSoorten};

/// Alles bij elkaar, mét punt — de vorm waarin paden vergeleken worden.
final Set<String> audioExtensies = {for (final s in audioSoorten) '.$s'};

/// De extensie van [padOfNaam], mét punt en in kleine letters. Leeg als er geen punt in staat.
///
/// Geen `RegExp` hierbinnen, met opzet: dit draait één keer per bestand per scan, en dat zijn er
/// hier duizenden. Twee keer `lastIndexOf` doet hetzelfde werk zonder een patroon op te bouwen.
String extensieVan(String padOfNaam) {
  final i = padOfNaam.lastIndexOf('.');
  if (i < 0) return '';
  // Een punt in een MAPNAAM is geen extensie: "C:\Muziek\R.E.M\track" heeft er geen.
  final schuin = padOfNaam.lastIndexOf('/');
  final terug = padOfNaam.lastIndexOf(r'\');
  if (i < (schuin > terug ? schuin : terug)) return '';
  return padOfNaam.substring(i).toLowerCase();
}

/// De extensie zonder punt — wat `quality.dart` en de torrentlijsten gebruiken.
String soortVan(String padOfNaam) {
  final e = extensieVan(padOfNaam);
  return e.isEmpty ? '' : e.substring(1);
}

/// Is dit een bestand dat de app kan afspelen?
bool isAudioBestand(String padOfNaam) => audioSoorten.contains(soortVan(padOfNaam));

/// Gooit dit formaat gegarandeerd niets weg?
bool isVerliesvrij(String soortOfExtensie) {
  final s = soortOfExtensie.toLowerCase();
  return verliesvrijeSoorten.contains(s.startsWith('.') ? s.substring(1) : s);
}

// Hi-res uit torrents bij "Zoek hi-res" op een plaat.
//
// Saber, 25-10-2026: "ook via torrents moet worden gezocht, wel losse tracks". Op de plaat Stadium Arcadium van Red Hot
// Chili Peppers stonden bij de torrents "(2006 PBTHAL LP 24-96)", "[24 bit FLAC] vinyl", "[LP] [24/192] … FLAC
// (image+cue)" en "(vinyl 24/96) … FLAC (tracks)" — hi-res die Soulseek niet had. Deze regels kiezen welke torrents
// het proberen waard zijn; online.dart (`_zoekHiresInTorrents`) haalt er per nummer één bestand uit en keurt het
// zoals elke andere kandidaat (echt, even lang, dezelfde opname, bewezen beter).
//
// Alleen wat TorBox al heeft ("Instant"): dan staat het bestand er meteen en kost een torrent die niets oplevert
// alleen een lijst opvragen. Alleen torrents met losse nummers: een image met een cue moet eerst helemaal binnen en
// geknipt worden, en dat is een hele plaat halen voor één nummer.

import 'audioformaten.dart' show isAudioBestand;
import 'organize.dart' show surroundLabel;
import 'quality.dart';
import 'torbox.dart' show SearchResult;
import 'torrentvoornummer.dart';
import 'vinyl.dart' show isVinylRip;

/// Hoeveel torrents er hoogstens geprobeerd worden per plaat.
const int kTorrentHiresHoogstens = 3;

/// Hoe een torrent zijn muziek bewaart.
enum TorrentIndeling {
  /// Eén bestand per nummer: daar is er één uit te halen.
  losseNummers,

  /// Eén groot bestand (per schijf) met een cue erbij: eerst helemaal halen en knippen.
  image,

  /// Niet te zeggen (geen lijst, of geen muziek erin).
  onbekend,
}

final _imageTitel = RegExp(r'image\s*\+?\s*\.?\s*cue|\bimg\s*\+\s*\.?\s*cue|\(image\)|\[image\]', caseSensitive: false);
final _tracksTitel = RegExp(r'[(\[]\s*tracks\s*[)\]]|\btracks?\s*\+\s*\.?\s*cue', caseSensitive: false);

/// Wat de naam van de torrent zegt. RuTracker zegt het er altijd bij: "FLAC (tracks)" of "FLAC (image+.cue)".
TorrentIndeling indelingUitTitel(String titel) {
  if (_imageTitel.hasMatch(titel)) return TorrentIndeling.image;
  if (_tracksTitel.hasMatch(titel)) return TorrentIndeling.losseNummers;
  return TorrentIndeling.onbekend;
}

/// Wat de bestandenlijst zegt: twee of meer muziekbestanden, en minder cues dan muziekbestanden, zijn losse nummers.
/// Een image per schijf heeft een cue per bestand ("CD1.flac" + "CD1.cue").
TorrentIndeling indelingUitBestanden(Iterable<String> paden) {
  final audio = paden.where(isAudioBestand).length;
  final cues = paden.where((p) => p.toLowerCase().endsWith('.cue')).length;
  if (audio == 0) return TorrentIndeling.onbekend;
  if (audio >= 2 && cues < audio) return TorrentIndeling.losseNummers;
  return TorrentIndeling.image;
}

/// "24-96", "24bit", "96 kHz" in een naam zonder formaatwoord. "Red Hot Chili Peppers - Stadium Arcadium (2006 PBTHAL LP
/// 24-96)" noemt geen FLAC en kreeg in de lijst een "?" ([qualityFromName]); 24-bit bestaat alleen verliesvrij, en wat
/// er werkelijk in zit, meet de keuring.
final _hiresNaam =
    RegExp(r'\b24[ ._/\-]?(44|48|88|96|176|192)\b|24[ ._/\-]?bit|\b(88[.,]2|96|176[.,]4|192)\s?khz', caseSensitive: false);

/// Hi-res volgens de naam: wat [qualityFromName] hi-res noemt, of een naam zonder formaat met 24-bit-tekens.
bool hiresVolgensNaam(String naam) {
  final q = qualityFromName(naam);
  return q.label != 'DSD' && (q.tier == QTier.hires || (q.tier == QTier.unknown && _hiresNaam.hasMatch(naam)));
}

/// De torrents die voor de plaat [album] van [artiest] het proberen waard zijn, in de volgorde waarin ze geprobeerd
/// worden.
///
/// Erin: wat TorBox al heeft, de plaat zelf noemt ([torrentVoorNummer] → album; geen discografie), verliesvrij is en —
/// als [hiresNodig] — hi-res volgens de naam, in stereo, zonder DSD, en niet als image. Volgorde: een digitale uitgave
/// vóór vinyl (zoals bij Soulseek, `vinylAchteraan`), hi-res vóór cd-kwaliteit, daarbinnen zoals de zoektocht ze gaf
/// (seeders).
List<SearchResult> torrentsVoorHires(List<SearchResult> treffers,
    {required String artiest, required String album, int? jaar, required bool hiresNodig}) {
  final goed = <(int, SearchResult)>[];
  for (var i = 0; i < treffers.length; i++) {
    final r = treffers[i];
    if (!r.cached) continue;
    final q = qualityFromName(r.name);
    final hires = hiresVolgensNaam(r.name);
    if (q.label == 'DSD' || !(q.lossless || hires)) continue;
    if (hiresNodig && !hires) continue;
    if (surroundLabel(r.name) != null) continue;
    if (indelingUitTitel(r.name) == TorrentIndeling.image) continue;
    if (torrentVoorNummer(r.name, artiest: artiest, album: album, jaar: jaar) != TorrentPast.album) continue;
    goed.add((i, r));
  }
  int rang((int, SearchResult) e) => (isVinylRip(e.$2.name) ? 2 : 0) + (hiresVolgensNaam(e.$2.name) ? 0 : 1);
  goed.sort((a, b) {
    final r = rang(a).compareTo(rang(b));
    return r != 0 ? r : a.$1.compareTo(b.$1);
  });
  return [for (final e in goed) e.$2];
}

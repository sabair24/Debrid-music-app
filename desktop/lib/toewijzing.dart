/// Welk bestand hoort op welke rij van de uitgave — als één som, niet als een reeks gokjes.
///
/// **Waarom dit bestaat.** De bestaande [matchAlbumTracks] werkt met volgordelijke passen: rij 1
/// pakt het eerste bestand dat past, rij 2 het volgende, enzovoort. Dat is gulzig, en gulzig is
/// aantoonbaar fout zodra twee rijen op elkaar lijken. Gemeld op 05-09-2026 met Christina Milians
/// *Dip It Low (Mixes)*: het bestand van 3:14 belandde op "Dip It Low (Full Intention Dub)" omdat
/// die rij eerder aan de beurt was, terwijl de rij van 3:18 er beter bij paste.
///
/// **Waar dit op gebaseerd is.** Saber vroeg om "het beste taggersysteem, zoek online hoe zij het
/// doen". Dat is [beets](https://beets.readthedocs.io/en/stable/reference/config.html), en die doet
/// twee dingen die hier ontbraken:
///
///   1. **Eén afstandsfunctie met gewichten** in plaats van losse regels per pas. beets weegt
///      `track_title` 3,0 · `track_length` 2,0 · `track_artist` 2,0 · `track_index` 1,0. Die
///      verhouding is hier overgenomen.
///   2. **Een globaal optimale toewijzing.** `assign_items()` bouwt een kostenmatrix van álle
///      (bestand × rij)-paren en lost die op met een LAP-solver (`lap.lapjv`, het Hongaarse
///      algoritme). Niet het eerste dat past wint, maar de indeling met de laagste TOTALE afstand.
///
/// **Wat hier strenger is dan bij beets, en met opzet.** Een versiemerk dat maar aan één kant staat
/// is hier geen straf maar een VETO: een radio-edit wordt nooit de albumversie, hoe goed de rest ook
/// past. Die regel bestond al ([zelfdeVersiemerken]) en beschermt echt gedrag — zie
/// `nummering_remix_test.dart`. Een gewicht zou hem wegdrukken zodra de looptijden toevallig kloppen,
/// en dat is precies het geval dat gemeld werd.
library;

import 'dart:math' as math;

import 'editions.dart';
import 'models.dart';
import 'organize.dart';

/// Seconden die twee opnames mogen schelen zonder dat het meetelt.
///
/// beets noemt dit `track_length_grace`. Een gedrukte tijd is afgerond en een rip begint of eindigt
/// een tel eerder; daar hoort geen straf op te staan.
const double kSpeling = 10;

/// Voorbij dit verschil is de looptijdstraf maximaal. beets' `track_length_max`.
const double kMaxVerschil = 30;

/// Wat een ontbrekende rij en een overtollig bestand kosten. beets: 0,9 en 0,6.
const double kOntbrekend = 0.9;
const double kOvertollig = 0.6;

/// Boven deze afstand wordt een paar niet meer gekoppeld.
///
/// Zonder deze grens legt een optimale toewijzing ÁLLES ergens neer -- ook een bestand dat op geen
/// enkele rij hoort. Dat is het verschil tussen "de beste indeling" en "een juiste indeling", en het
/// is precies waarom [matchAlbumTracks] weeskinderen kent.
const double kMaxAfstand = 0.6;

/// Verschilt de KERN van de titel meer dan dit, dan is het een ander nummer -- ongeacht de rest.
/// Zie de tweede harde grens in [rijAfstand] voor de meting die dit getal afdwong.
const double kMaxKern = 0.4;

/// Onbereikbaar: dit paar mag nooit gekoppeld worden.
const double _veto = 1e9;

/// Levenshtein, met een rij van twee in plaats van een volle matrix.
int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var vorige = List<int>.generate(b.length + 1, (i) => i);
  var nu = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    nu[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final kost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      nu[j + 1] = math.min(math.min(nu[j] + 1, vorige[j + 1] + 1), vorige[j] + kost);
    }
    final t = vorige;
    vorige = nu;
    nu = t;
  }
  return vorige[b.length];
}

/// De titel zonder ALLES tussen haakjes — de kern waar het nummer aan te herkennen is.
String _kern(String s) => s.replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ');

/// Alleen wat er tussen haakjes stond, achter elkaar.
String _haakjes(String s) => RegExp(r'[\(\[]([^\)\]]*)[\)\]]')
    .allMatches(s)
    .map((m) => m.group(1) ?? '')
    .join(' ');

/// Kale tekstafstand van 0 (gelijk) tot 1 (niets gemeen), op de genormaliseerde tekst.
double _ruweAfstand(String a, String b) {
  final x = normKey(a).trim(), y = normKey(b).trim();
  if (x.isEmpty && y.isEmpty) return 0;
  if (x.isEmpty || y.isEmpty) return 1;
  if (x == y) return 0;
  return math.min(1, _levenshtein(x, y) / math.max(x.length, y.length));
}

/// Een staart achter een streepje weg: "More And More - Single Version" wordt "More And More".
String _zonderStaart(String s) => s.replaceFirst(RegExp(r'\s+[-–]\s+.*$'), '');

/// Hoeveel de KERN van twee titels verschilt — de identiteit van het nummer.
///
/// **Het GUNSTIGSTE van de lezingen telt, en dat moest wel.** Een eerste versie vergeleek alleen
/// kern tegen kern, en dat strafte precies de gevallen waarvoor de haakjesweging bedoeld was: de rij
/// "Beyoncé (interlude)" heeft als kern "Beyoncé", en dat lijkt te weinig op het bestand "Beyoncé
/// Interlude" dat helemaal geen haakjes gebruikt. Gemeten: drie treffers die de OUDE toewijzing wél
/// maakte gingen erop verloren.
///
/// Dus wordt elke titel in drie lezingen gezet — voluit, zonder haakjes, en zonder de staart achter
/// een streepje — en telt de kleinste afstand tussen welke twee dan ook. Een gastcredit gaat er aan
/// beide kanten af, want "Promises" en "Promises ft. Calvin Harris" zijn hetzelfde nummer.
///
/// Losser maakt dit de regel niet waar het op aankomt: "Queen Of Mine" en "Operation Coup De Poing"
/// liggen in élke lezing ver uit elkaar, en dat is het geval waar deze grens voor bestaat.
double kernAfstand(String a, String b) {
  List<String> lezingen(String s) {
    final v = withoutVersionText(s);
    return [zonderFeat(v), zonderFeat(_kern(v)), zonderFeat(_zonderStaart(v))]
        .map((x) => x.trim())
        .where((x) => x.isNotEmpty)
        .toSet()
        .toList();
  }

  final la = lezingen(a), lb = lezingen(b);
  if (la.isEmpty || lb.isEmpty) return 1;
  var beste = 1.0;
  for (final x in la) {
    for (final y in lb) {
      var d = _ruweAfstand(x, y);
      // **Begint de ene titel met de andere, dan is het dezelfde naam met een aanhangsel.**
      //
      // Dezelfde gedachte als het lichter wegen van haakjes, maar dan voor de helft van de
      // bibliotheek die géén haakjes gebruikt: "'Hold On To The Vision' Lionshare Mix 87" tegen de
      // rij "Hold on to the Vision", of "Party @ (Extended Mix)" tegen een rij waar het haakje
      // sneuvelde. Op tekstafstand alleen zijn dat grote verschillen en sneuvelt de treffer;
      // gemeten waren dat drie koppelingen die de oude toewijzing wél maakte.
      //
      // Alleen VOORAAN, niet ergens in het midden: "Love" zit ook in "Endless Love", en dat zijn
      // twee nummers. En dit verlaagt alleen het VETO — in de gewogen som telt het volle
      // titelverschil onverminderd mee, dus bij twee kandidaten wint nog steeds de beste.
      final nx = normKey(x), ny = normKey(y);
      if (nx.isNotEmpty && ny.isNotEmpty && (nx.startsWith(ny) || ny.startsWith(nx))) {
        d = math.min(d, 0.2);
      }
      if (d < beste) beste = d;
    }
  }
  return beste;
}

/// Hoe ver twee titels uit elkaar liggen, van 0 (gelijk) tot 1 (niets gemeen).
///
/// **De haakjes wegen lichter, en dat is de truc die beets gebruikt.** Een ondertitel of een credit
/// tussen haakjes staat vaak maar aan één kant — "Morphine" tegen "Morphine (feat. Slash)", "Ce Rêve
/// Bleu" tegen "Ce rêve bleu (Le Thème d'Aladdin)". Op de kale tekst afgerekend zijn dat grote
/// verschillen, en dan mist de app treffers die overduidelijk kloppen. Op de KERN afgerekend zijn ze
/// nul, en zegt het haakje alleen nog iets fluisterend.
///
/// De versiemerken gaan er eerst helemaal af: die worden apart en veel strenger beoordeeld, zie het
/// veto in [rijAfstand]. Hetzelfde verschil twee keer afrekenen is precies genoeg om een treffer te
/// missen — die afweging staat ook in `completeness.dart` bij `_words`.
double tekstAfstand(String a, String b) {
  final x = withoutVersionText(a), y = withoutVersionText(b);
  return 0.8 * _ruweAfstand(_kern(x), _kern(y)) + 0.2 * _ruweAfstand(_haakjes(x), _haakjes(y));
}

/// Zijn de versiemerken van deze twee titels gelijkwaardig, gegeven de plaat waar ze op staan?
///
/// Strenger dan [tekstAfstand] en losser dan [zelfdeVersiemerken], met twee uitzonderingen die
/// allebei uit een METING komen — zonder hen plaatste de nieuwe toewijzing minder dan de oude:
///
///   * **Alleen de haakjes verschillen.** *Dangerously in Love* noemt rij 13 "Beyoncé (interlude)"
///     en het bestand heet "Beyoncé Interlude". Dezelfde twee woorden, één keer gehaakt en één keer
///     niet. Staat het merk als gewone tekst in de andere titel, dan is er geen verschil.
///   * **Het merk herhaalt de albumtitel.** "Crazy In Love (Homecoming Live)" op *HOMECOMING: THE
///     LIVE ALBUM* is geen andere opname maar dezelfde naam met de plaat erbij. Dat oordeel staat al
///     in [versieNoemtDeUitgave] en wordt hier niet nagebouwd — het is dezelfde regel die
///     `matchAlbumTracks` sinds 3.9.298 gebruikt.
bool _merkenGelijkwaardig(String a, String b, String album) {
  if (zelfdeVersiemerken(a, b)) return true;
  if (album.isNotEmpty &&
      (versieNoemtDeUitgave(a, album) || versieNoemtDeUitgave(b, album))) {
    return true;
  }
  // Elk merk dat maar aan één kant staat moet als gewone tekst in de ándere titel voorkomen.
  bool gedektDoor(Set<String> merken, String andere) {
    final woorden = normKey(andere);
    for (final m in merken) {
      if (!woorden.contains(normKey(m))) return false;
    }
    return true;
  }

  final ma = versionMarkers(a), mb = versionMarkers(b);
  return gedektDoor(ma.difference(mb), b) && gedektDoor(mb.difference(ma), a);
}

/// De afstand tussen één rij van de uitgave en één bestand.
///
/// Gewogen als bij beets. Nul betekent "dit is het"; boven [kMaxAfstand] wordt het paar niet meer
/// gelegd. [_veto] betekent: nooit, ongeacht de rest.
double rijAfstand(ChoiceTrack rij, Track bestand, {String album = ''}) {
  // HARDE GRENS 1. Zie de klasse-uitleg: een versiemerk aan één kant is een andere opname.
  if (!_merkenGelijkwaardig(bestand.title, rij.title, album)) return _veto;

  // HARDE GRENS 2: de KERN van de titel moet lijken.
  //
  // **Gemeten, en het is de reden dat deze grens bestaat.** Zonder hem legde de toewijzing op
  // *2 Belgen* het bestand "Operation Coup De Poing" op de rij "Queen Of Mine", en bij France Gall
  // "Diego, Libre Dans Sa Tete" op "Les Rubans et la Fleur". Twee totaal verschillende nummers,
  // allebei doorgelaten omdat de LOOPTIJD toevallig klopte: een titelafstand van 0,8 gedeeld door
  // vijf gewichtseenheden komt onder de drempel uit. Een gewogen som alleen is dus niet genoeg —
  // de titel is de identiteit van een nummer, de looptijd is hooguit bevestiging.
  if (kernAfstand(bestand.title, rij.title) > kMaxKern) return _veto;

  // HARDE GRENS 3: een looptijd die geen andere SNIT meer kan zijn.
  //
  // Dezelfde marge die `matchAlbumTracks` al hanteert (een derde, en hooguit anderhalve minuut):
  // ruim genoeg voor een single-edit naast een albumversie, veel te krap voor een andere opname.
  // Zonder deze grens kwam op *Serious Beats 100* een dj-mix van 1493 seconden op een rij van 411 te
  // liggen, want de titels waren identiek.
  final oSec = rij.seconds ?? 0, bSec = bestand.duration?.inSeconds ?? 0;
  if (oSec > 0 && bSec > 0) {
    final gat = (oSec - bSec).abs();
    if (gat > 90 || gat > oSec / 3) return _veto;
  }

  var som = 0.0, gewicht = 0.0;

  // Titel, gewicht 3.
  som += 3.0 * tekstAfstand(bestand.title, rij.title);
  gewicht += 3.0;

  // Looptijd, gewicht 2. Alleen als beide kanten er een hebben -- anders zwijgt dit veld in plaats
  // van te gokken.
  final os = rij.seconds ?? 0, bs = bestand.duration?.inSeconds ?? 0;
  if (os > 0 && bs > 0) {
    final verschil = math.max(0.0, (os - bs).abs() - kSpeling);
    som += 2.0 * math.min(1.0, verschil / kMaxVerschil);
    gewicht += 2.0;
  }

  // De artiestcredit van de rij, gewicht 2. Alleen als de uitgave er een noemt; op een gewone plaat
  // staat bij elke rij dezelfde naam en zegt dit veld niets.
  final credit = rij.artist.trim();
  if (credit.isNotEmpty) {
    som += 2.0 * tekstAfstand(gastcredit(splitFeatured(bestand.artist, bestand.title).main,
            splitFeatured(bestand.artist, bestand.title).featured), credit);
    gewicht += 2.0;
  }

  // De plek, gewicht 1. Het nummer in de tag is vaak fout -- daarom weegt het licht -- maar als het
  // klopt is het wel bewijs.
  final positie = int.tryParse(rij.position.replaceAll(RegExp(r'[^0-9]'), ''));
  if (positie != null && positie > 0 && bestand.trackNo > 0) {
    som += 1.0 * (positie == bestand.trackNo ? 0.0 : 1.0);
    gewicht += 1.0;
  }

  return gewicht == 0 ? 1 : som / gewicht;
}

/// De goedkoopste toewijzing van bestanden aan rijen, over de hele plaat tegelijk.
///
/// Geeft per RIJ de index van het bestand dat erop hoort, of null. Een bestand dat nergens onder
/// [kMaxAfstand] past blijft over -- dat is een weeskind, en dat hoort zo.
///
/// Het Hongaarse algoritme (Jonker-Volgenant met potentialen), O(n³). Een plaat heeft hooguit
/// enkele tientallen rijen, dus dat is ruim genoeg.
List<int?> besteToewijzing(List<ChoiceTrack> rijen, List<Track> bestanden,
    {String album = ''}) {
  final n = rijen.length, m = bestanden.length;
  if (n == 0 || m == 0) return List<int?>.filled(n, null);

  // Vierkant maken met een kolom "niet toegewezen", zodat een rij leeg mag blijven.
  final maat = math.max(n, m);
  final kosten = List.generate(
    maat,
    (i) => List<double>.generate(maat, (j) {
      if (i >= n || j >= m) return kMaxAfstand;
      final d = rijAfstand(rijen[i], bestanden[j], album: album);
      // Boven de grens even duur als niets: dan kiest de oplossing liever leeg.
      return d > kMaxAfstand ? kMaxAfstand : d;
    }),
  );

  // e-maxx' Jonker-Volgenant, 1-geïndexeerd.
  const inf = 1e18;
  final u = List<double>.filled(maat + 1, 0);
  final v = List<double>.filled(maat + 1, 0);
  final p = List<int>.filled(maat + 1, 0); // p[kolom] = rij
  final weg = List<int>.filled(maat + 1, 0);

  for (var i = 1; i <= maat; i++) {
    p[0] = i;
    var j0 = 0;
    final minv = List<double>.filled(maat + 1, inf);
    final gebruikt = List<bool>.filled(maat + 1, false);
    do {
      gebruikt[j0] = true;
      final i0 = p[j0];
      var delta = inf;
      var j1 = 0;
      for (var j = 1; j <= maat; j++) {
        if (gebruikt[j]) continue;
        final cur = kosten[i0 - 1][j - 1] - u[i0] - v[j];
        if (cur < minv[j]) {
          minv[j] = cur;
          weg[j] = j0;
        }
        if (minv[j] < delta) {
          delta = minv[j];
          j1 = j;
        }
      }
      for (var j = 0; j <= maat; j++) {
        if (gebruikt[j]) {
          u[p[j]] += delta;
          v[j] -= delta;
        } else {
          minv[j] -= delta;
        }
      }
      j0 = j1;
    } while (p[j0] != 0);
    do {
      final j1 = weg[j0];
      p[j0] = p[j1];
      j0 = j1;
    } while (j0 != 0);
  }

  final uit = List<int?>.filled(n, null);
  for (var j = 1; j <= maat; j++) {
    final rij = p[j] - 1, bestand = j - 1;
    if (rij < 0 || rij >= n || bestand >= m) continue;
    // De vulkolommen kostten kMaxAfstand; een paar dat daar niet onder komt is geen paar.
    if (rijAfstand(rijen[rij], bestanden[bestand], album: album) > kMaxAfstand) continue;
    uit[rij] = bestand;
  }
  return uit;
}

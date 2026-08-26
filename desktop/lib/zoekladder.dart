/// De zoekopdrachten voor één nummer, van precies naar ruim.
///
/// **Waarom dit bestaat.** Soulseek eist dat ÉLK woord in het pad van de peer voorkomt. Voor
/// "Sting Fields of Gold (My Songs Version)" heeft niemand dat allemaal in zijn padnaam staan, dus
/// die vraag komt leeg terug. Wat er daarna gebeurde was het probleem: de app viel in één stap
/// terug op de eerste twee woorden — **"Sting Fields"** — en dat is de titel kwijt. Je kreeg dus
/// een lijst met bronnen voor een ánder nummer dan je aantikte, zonder dat er iets over gezegd
/// werd, en de heropname was op geen enkele manier te bereiken.
///
/// De tussenstap die ontbrak is precies de nuttigste: dezelfde vraag zónder de haakjes. "Sting
/// Fields of Gold" vindt wél iedereen die het album *My Songs* deelt, en dan kan
/// `fileOffersTitle` (met de map als bewijs) er de goede uit halen.
///
/// Zuivere functies, geen netwerk: hier draait geen Flutter en geen toestel, dus dit is het enige
/// stuk van deze weg dat vóór het uitgeven na te meten is.
library;

import 'organize.dart' show baseName, fileWords;

/// De haakjes met wat erin staat: "(My Songs Version)", "[Radio Edit]", "{2019}".
final _haakjes = RegExp(r'[(\[{][^)\]}]*[)\]}]');

/// De patronen van [vraagScore] en [woordenOpVolgorde], één keer gebouwd.
///
/// Ze stonden in de body, en die twee functies draaien PER AANGEBODEN BESTAND per zoekopdracht —
/// bij Soulseek zijn dat er honderden. Het patroon voor het kale tracknummer stond bovendien binnen
/// een `where`, dus het werd per WOORD opnieuw gebouwd en gecompileerd. Zie de uitleg boven de
/// gelijksoortige lijst in `organize.dart`; dit is dezelfde fout in het bestand ernaast.
///
/// Eigen namen per bestand: dit bestand importeert al `baseName` en `fileWords` uit `organize.dart`,
/// en top-level namen mogen daar niet mee botsen.
final _padScheiding = RegExp(r'[\\/]');
final _extensie = RegExp(r'\.[a-z0-9]{2,4}$');
final _woordScheiding = RegExp(r'[^a-z0-9]+');
final _kaalNummer = RegExp(r'^\d{1,3}$');

/// De vragen die geprobeerd mogen worden, van precies naar ruim, zonder herhalingen.
///
/// Altijd minstens één element zolang [vraag] iets bevat. De aanroeper stopt bij de eerste die
/// treffers oplevert; komt er niets, dan is de laatste wat er getoond werd.
///
/// Drie treden, en niet meer:
///
/// 1. **de volledige vraag** — het meest precies, en vaak meteen raak;
/// 2. **zonder de haakjes** — de trede die ontbrak. Hier gaat "(My Songs Version)" eraf en blijft
///    "Sting Fields of Gold" over: nog steeds hetzelfde nummer, alleen zonder het stuk dat geen
///    enkele peer in zijn bestandsnaam zet;
/// 3. **de eerste twee woorden** — het oude gedrag, meestal de artiest. Bewust nog steeds de
///    laatste tree en niet geschrapt: bij een nummer dat écht nergens onder zijn eigen titel te
///    vinden is, is "iets van deze artiest" beter dan een leeg scherm. Maar het is nu wat het hoort
///    te zijn — een laatste redmiddel in plaats van de eerste terugval.
List<String> zoekLadder(String vraag) => zoekRondes(vraag).expand((r) => r).toList();

/// Diezelfde treden, maar gebundeld per RONDE — en dít is wat er de deur uit gaat.
///
/// **Waarom er rondes nodig waren.** De ladder werd trede voor trede afgelopen en stopte bij de
/// eerste die íéts opleverde. Dat klinkt zuinig en was het niet. Gemeten geval: via het menu
/// "Zoeken met Soulseek" op *Plaza – Yo-Yo (Dance Version)* gaf trede 1 dertien treffers, dus stopte
/// het daar. Wie zélf `yo-yo dance version` intikte kreeg er tientallen, met een echte 24/96 ertussen
/// die via het menu onbereikbaar was. Dertien is "iets", maar het is niet wat er te halen valt.
///
/// **Wat er verandert.** De twee treden die over HETZELFDE nummer gaan — de volledige vraag en
/// dezelfde vraag zonder de haakjes — gaan nu samen in één ronde. Dat kost geen seconde extra:
/// `SlskSession.search` neemt een lijst vragen aan en zet ze als losse tickets in hetzelfde venster
/// van acht seconden. De resultaten komen op één hoop, en de rangschikking bepaalt wat bovenaan
/// staat.
///
/// **Wat er niet verandert.** De eerste twee woorden — meestal alleen de artiest — blijven een eigen
/// ronde, en die gaat alleen de deur uit als de eerste ronde helemaal niets opleverde. Zou die
/// meegaan met de rest, dan stond de lijst vol met ander werk van dezelfde artiest.
List<List<String>> zoekRondes(String vraag) {
  final heel = vraag.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (heel.isEmpty) return const [];
  final precies = <String>[heel];

  final zonder = heel.replaceAll(_haakjes, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  // Niet als er niets overblijft: een titel die HELEMAAL tussen haakjes staat — "(Everything I Do)
  // I Do It for You" bestaat, en "(Reprise)" ook — mag geen lege vraag worden.
  if (zonder.isNotEmpty && zonder != heel) precies.add(zonder);

  final uit = <List<String>>[precies];
  final woorden = zonder.isEmpty ? heel.split(' ') : zonder.split(' ');
  if (woorden.length >= 3) {
    final twee = woorden.take(2).join(' ');
    if (!precies.contains(twee)) uit.add([twee]);
  }
  return uit;
}

/// Hoort er bij de resultaten verteld te worden dat er ruimer gezocht is?
///
/// Zodra er niet op de eerste trede gezocht is, gaat de lijst over een ándere vraag dan die je
/// stelde. Dat stilhouden is hoe iemand een uur lang de verkeerde opname staat te downloaden zonder
/// te snappen waarom — precies wat er gebeurde.
bool ruimerGezocht(String gevraagd, String gebruikt) =>
    gevraagd.trim().replaceAll(RegExp(r'\s+'), ' ') != gebruikt;


/// Hoe goed past het pad [pad] bij wat er letterlijk getypt is in [vraag]?
///
/// 0 betekent: geen enkel woord uit de vraag komt in dit pad voor. 1 betekent: alles wat je typte
/// staat in de BESTANDSNAAM. Daartussenin telt een woord dat alleen in een mapnaam staat half mee.
///
/// **Waarom dit nodig is.** Bij direct zoeken zat er tot nu toe géén enkele zeef tussen wat de
/// bronnen teruggeven en wat je ziet, en de rangschikking keek alleen naar geluidskwaliteit. Wat je
/// typte kwam in de volgorde helemaal niet voor. Twee dingen maakten dat erger:
///
/// - Soulseek eist zijn woorden in het HELE pad, niet in de bestandsnaam. Een treffer op een
///   mapnaam sleept dus elk nummer in die map mee.
/// - De app stuurt naast je vraag ook een variant met een sterretje ervoor, omdat Soulseek soms het
///   eerste teken laat vallen. Dat is een echt jokerteken: bij "Rain" ging `*ain` mee en dat vindt
///   ook Brain, Spain en Train. Dat gaat bij één woord niet meer mee (zie [jokerHelpt]), maar bij
///   een vraag van meer woorden nog wel — en dan kan één van die woorden nog steeds meeliften.
///
/// De bestandsnaam telt zwaarder dan de map, en dat is precies het onderscheid dat ontbrak: "Rain"
/// in de titel is wat je zocht, "Rain" in de artiestenmap is context.
///
/// Zuiver en zonder netwerk, dus na te meten zonder toestel.
double vraagScore(String vraag, String pad) {
  final gevraagd = fileWords(vraag);
  if (gevraagd.isEmpty) return 0;
  final naam = fileWords(baseName(pad));
  final rest = pad.substring(0, pad.length - baseName(pad).length);
  final map = fileWords(rest.replaceAll(_padScheiding, ' '));
  var punten = 0.0;
  for (final w in gevraagd) {
    if (naam.contains(w)) {
      punten += 1;
    } else if (map.contains(w)) {
      punten += 0.5;
    }
  }
  return punten / gevraagd.length;
}

/// Zegt dit resultaat helemaal niets over wat er gevraagd is?
///
/// Alleen bij score nul, en dat is met opzet streng noch soepel maar FEITELIJK: er komt dan geen
/// enkel woord uit je vraag in het hele pad voor. Bij Soulseek kan dat niet van een echte treffer
/// komen — de server eist elk woord ergens in het pad — dus dit is per definitie ruis van de
/// jokervariant. Wegzeven kan daar niets kosten wat je gevraagd hebt.
bool volslagenAnders(String vraag, String pad) => vraagScore(vraag, pad) == 0;


/// De woorden van [s] in VOLGORDE, met dezelfde regels als [fileWords].
///
/// Die functie levert een verzameling, en voor "staat dit achter elkaar?" is de volgorde juist het
/// hele punt. Dezelfde zeef: kleingeschreven, de extensie eraf, alles wat geen letter of cijfer is
/// als scheiding, losse letters weg en kale tracknummers weg.
List<String> woordenOpVolgorde(String s) => s
    .toLowerCase()
    .replaceAll(_extensie, '')
    .split(_woordScheiding)
    .where((w) => w.length > 1 && !_kaalNummer.hasMatch(w))
    .toList();

/// Hoeveel van de vraag ACHTER ELKAAR in de bestandsnaam staat, als deel van het geheel.
///
/// **Waarom dekking alleen niet genoeg is.** [vraagScore] telt hoeveel van je woorden érgens
/// voorkomen, en dat maakt geen verschil tussen een treffer en een toevalstreffer. Op
/// "mackenzie you all i need" gemeten:
///
/// | bestand | dekking | reeks |
/// |---|---|---|
/// | `YORK feat. Ginger Mackenzie - I Need You (Remix)` | 0,75 | 0,25 |
/// | `Mackenzie - You're All I Need` | 1,00 | 0,50 |
///
/// De tweede is wat je zocht, en het verschil in dekking is één woord. In de reeks is het verschil
/// twee keer zo groot: "mackenzie you" en "all need" staan daar in de volgorde waarin je ze typte,
/// terwijl de eerste ze verspreid door de naam heeft staan.
///
/// Alleen de bestandsnaam, niet de mappen: een mapnaam die toevallig jouw woorden op volgorde bevat
/// zegt iets over het album, niet over dit nummer.
double reeksScore(String vraag, String pad) {
  final v = woordenOpVolgorde(vraag);
  if (v.isEmpty) return 0;
  final n = woordenOpVolgorde(baseName(pad));
  if (n.isEmpty) return 0;
  var langste = 0;
  for (var i = 0; i < v.length; i++) {
    for (var j = 0; j < n.length; j++) {
      var k = 0;
      while (i + k < v.length && j + k < n.length && v[i + k] == n[j + k]) {
        k++;
      }
      if (k > langste) langste = k;
    }
  }
  return langste / v.length;
}

/// Mag er naast [vraag] ook een variant met een sterretje ervoor de deur uit?
///
/// **Waar dat sterretje vandaan komt.** De app stuurt naast je vraag al jaren ook `*ain` voor
/// "Rain", omdat Soulseek soms het eerste teken van een vraag laat vallen. Dat is een echt
/// jokerteken, en het vindt dus ook Brain, Spain en Train.
///
/// **Waarom het bij één woord niet meer meegaat.** Soulseek eist élk woord van je vraag ergens in
/// het pad. Bij "sting fields of gold" wordt de jokervariant `*ting fields of gold`, en die drie
/// overige woorden houden de ruis vanzelf tegen — daar kost het niets. Bij één woord is er niets
/// dat hem tegenhoudt: `*ain` is dan de hele vraag, en alles wat de peer heeft dat op "ain"
/// eindigt komt binnen. Precies de ruis waar je last van had.
///
/// De variant gaat NAAST de gewone vraag mee in dezelfde ronde, niet erna. Dat is met opzet:
/// achteraf sturen zou een tweede ronde van ruim acht seconden kosten, en juist op een vraag die
/// niets oplevert loopt de app die ladder al tot drie keer af.
bool jokerHelpt(String vraag) {
  final woorden = vraag.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  // Minder dan twee woorden: niets houdt de joker tegen.
  if (woorden.length < 2) return false;
  // Het sterretje vervangt het eerste teken van het EERSTE woord. Is dat woord te kort, dan blijft
  // er van dat woord niets over om op te zoeken — `*` plus één letter is geen vraag meer.
  return woorden.first.length >= 3;
}

/// Hoeveel woorden er in de vraag zitten die meetellen — voor "3 van de 4 woorden" op het scherm.
int telbareWoorden(String vraag) => fileWords(vraag).length;

/// Hoeveel van die woorden dit pad dekt, afgerond op hele woorden.
int gedekteWoorden(String vraag, String pad) =>
    (vraagScore(vraag, pad) * telbareWoorden(vraag)).round();

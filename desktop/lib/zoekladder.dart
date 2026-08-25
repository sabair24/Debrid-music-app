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
List<String> zoekLadder(String vraag) {
  final heel = vraag.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (heel.isEmpty) return const [];
  final uit = <String>[heel];

  final zonder = heel.replaceAll(_haakjes, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  // Niet als er niets overblijft: een titel die HELEMAAL tussen haakjes staat — "(Everything I Do)
  // I Do It for You" bestaat, en "(Reprise)" ook — mag geen lege vraag worden.
  if (zonder.isNotEmpty && zonder != heel) uit.add(zonder);

  final woorden = zonder.isEmpty ? heel.split(' ') : zonder.split(' ');
  if (woorden.length >= 3) {
    final twee = woorden.take(2).join(' ');
    if (!uit.contains(twee)) uit.add(twee);
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
/// - De app stuurt naast je vraag ook een variant met een sterretje ervoor — `*ain` voor "Rain" —
///   omdat Soulseek soms het eerste teken laat vallen. Dat is een echt jokerteken: het vindt ook
///   Brain, Spain en Train, en die treffers werden op één hoop gegooid met de echte.
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
  final map = fileWords(rest.replaceAll(RegExp(r'[\\/]'), ' '));
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

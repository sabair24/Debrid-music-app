/// De hash die cachebestanden hun naam geeft. Eén keer, want elke kopie kan stil gaan afwijken.
///
/// **Waarom dit bestaat.** Deze functie bepaalt bestandsnamen op schijf: `covers/<fnv>.jpg`,
/// `bios/<fnv>.txt`, `artistart/<fnv>.json`, `albuminfo/<fnv>.json`, `discography/<fnv>.json`,
/// `wikipedia/<fnv>.json` en de merkbestanden in `hoescache`. Verandert de uitkomst ook maar voor
/// één invoer, dan is niet één bestand onvindbaar maar de héle bewaarde cache van de gebruiker: de
/// app ziet overal een gat en haalt honderden bestanden opnieuw op, over gelimiteerde banen.
/// `hoesMerk` gaat bovendien als ETag over de lijn naar de telefoon, dus een afwijking daar laat
/// élk toestel élke hoes opnieuw ophalen.
///
/// Ze stond zes keer los in `desktop/lib`: `album_facts.dart`, `discography_service.dart`, twee maal
/// in `enrichment.dart`, `library.dart` en `wikipedia.dart`. Zes kopieën die alle zes hetzelfde
/// moeten blijven rekenen is geen afspraak die zichzelf handhaaft — vandaar één plek, en
/// `test/cachesleutel_test.dart` die de uitkomsten vastlegt.
///
/// **De val: `codeUnits`, nooit `runes`.** Ze zien er inwisselbaar uit en geven voor gewone tekst —
/// ook voor `Beyoncé` — hetzelfde antwoord, dus een verwisseling overleeft een vluchtige blik. Bij
/// een teken buiten de BMP lopen ze uiteen: `x🎵y` geeft `b856b61f` met `codeUnits` en `15c1eadd`
/// met `runes`. Alle zes de kopieën gebruikten `codeUnits`; dat is dus wat er op schijf staat.
///
/// **En nooit `hashCode` of `Object.hash`.** Die zijn per proces geseed, dus dezelfde invoer krijgt
/// bij de volgende start een andere naam. Zie de meting bij [hoesSleutel] in `library.dart`: dat
/// heeft de app ooit 17,4 seconden per start gekost.
library;

/// Het startgetal van FNV-1a, 32 bit.
const int fnvBegin = 0x811c9dc5;

const int _fnvPriem = 0x01000193;

/// FNV-1a over de UTF-16 code units van [s], voortbouwend op [h].
///
/// De vorm met een meegegeven [h] is er voor de aanroepers die meer dan één stuk achter elkaar
/// hashen — een lijst bestandsnamen, of een lengte gevolgd door de bytes zelf.
int fnv1aVan(String s, [int h = fnvBegin]) {
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * _fnvPriem) & 0xFFFFFFFF;
  }
  return h;
}

/// FNV-1a over rauwe bytes, voortbouwend op [h].
///
/// De `& 0xff` blijft staan: de aanroeper geeft een `List<int>`, en die belooft niet uit zichzelf
/// dat elke waarde in een byte past.
int fnv1aBytes(Iterable<int> bytes, [int h = fnvBegin]) {
  for (final b in bytes) {
    h ^= b & 0xff;
    h = (h * _fnvPriem) & 0xFFFFFFFF;
  }
  return h;
}

/// De hexvorm van [s], zoals elke cachenaam hem draagt.
String fnv1a(String s) => fnv1aVan(s).toRadixString(16);

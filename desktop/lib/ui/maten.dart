/// De maten van de app: ruimte, hoeken, diepte en tijd.
///
/// **Waarom dit bestand er is.** Een telling over alle 101 bestanden gaf: **15** verschillende
/// rondingen (waarvan zeven tussen 6 en 12, met het oog niet uit elkaar te houden), **29**
/// verschillende witruimtewaarden waarvan 73% buiten elk raster valt, en `fromLTRB` met **55**
/// verschillende viertallen. Dat is precies wat "slordig" betekent als je het probeert te meten:
/// niet dat een enkele waarde fout is, maar dat er geen twee widgets zijn die het over dezelfde
/// waarde eens zijn.
///
/// De oplossing is niet "alles vervangen" — dat zijn 715 kansen om stilletjes iets te verschuiven
/// zonder dat de bouw er iets van zegt. De oplossing is dat er vanaf nu iets bestáát om naar te
/// wijzen, en dat elke nieuwe of herbouwde widget er uitsluitend uit put. `test/maten_test.dart`
/// bewaakt dat voor de gedeelde widgets.
library;

import 'package:flutter/material.dart';

// ── Ruimte ───────────────────────────────────────────────────────────────────
//
// Acht stappen, en niet meer. De 715 losse waarden vielen bij natelling in zes clusters met elk een
// eigen bedoeling: regelscheiding (2–4), binnenwerk van een badge (4–6), het gat onder een hoes
// (8–9), vulling van een kaart (10–12), de marge onder een sectiekop (16), en de zijmarge van een
// pagina (20–28). Die laatste twee uitersten vallen samen in [kGoot]: 20 en 28 bestonden allebei
// alleen doordat niemand ze naast elkaar zag.

/// Tussen twee regels in dezelfde lijst.
const double kRuimte2 = 2;

/// Binnenwerk van iets kleins: een merkje, een telling.
const double kRuimte4 = 4;

/// Tussen een pictogram en zijn label.
const double kRuimte6 = 6;

/// Onder een hoes, boven de titel die erbij hoort.
const double kRuimte8 = 8;

/// De standaardvulling van een kaart, en de tussenruimte in een rij tegels.
const double kRuimte12 = 12;

/// Onder een sectiekop.
const double kRuimte16 = 16;

/// Tussen twee secties, en de zijmarge van elke pagina — zie [kGoot].
const double kRuimte24 = 24;

/// Boven de eerste sectie, en onder de laatste.
const double kRuimte32 = 32;

/// De zijmarge van élke pagina. Eén waarde, en dat is het hele punt.
///
/// De sectiekoppen op Start stonden op 28 en hun eigen inhoud op 24 (`main.dart`, `_section` tegen
/// `_localRow`). Vier punten scheefstand, over de volle hoogte van het startscherm, en het is
/// letterlijk wat er met "het rammelt" bedoeld wordt.
const double kGoot = kRuimte24;

// ── Hoeken ───────────────────────────────────────────────────────────────────

/// Skeletbalkjes en andere hele kleine vlakjes.
const double kHoek4 = 4;

/// Binnenwerk: badges, de achtergrond van een nummerregel, een tekstveld.
const double kHoek8 = 8;

/// De standaard: kaarten, hoezen, panelen.
const double kHoek12 = 12;

/// Grote vlakken: dialogen, bladen, de hoes op het speelscherm.
const double kHoek18 = 18;

/// Een pil: navigatieknoppen, de zoekbalk, de afspeelknop.
const double kHoekRond = 999;

/// De ronding van iets dat mét vulling ín iets anders ligt.
///
/// Een hoes van 12 in een kaart van 12 met 8 vulling loopt niet concentrisch: de binnenhoek is dan
/// visueel te rond. Buitenhoek min vulling wél — dat is de enige regel hier die na te meten is, en
/// [kHoek4] staat als bodem zodat er nooit een scherpe hoek uit komt.
double binnenHoek(double buiten, double vulling) =>
    (buiten - vulling).clamp(kHoek4, kHoek18);

// ── Diepte ───────────────────────────────────────────────────────────────────
//
// Als `List<BoxShadow>` en niet als Materials `elevation`: die tekent één diffuse wolk, en op een
// bijna zwarte achtergrond is dat vrijwel niets. Elk recept hier heeft twee lagen — een korte
// contactschaduw die de rand láát raken, en een wijde die optilt. Dat verschil is wat je ziet.

/// In rust: een kaart ligt op de pagina in plaats van de pagina te zíjn.
const List<BoxShadow> kSchaduw1 = [
  BoxShadow(color: Color(0x4D000000), blurRadius: 3, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x38000000), blurRadius: 12, offset: Offset(0, 3)),
];

/// Aangewezen of gemarkeerd.
///
/// De wijde laag is exact de bestaande hoverschaduw van `AlbumCard` (zwart op .45, blur 22, 10
/// omlaag). Die klopte al; wat ontbrak was dat er in rust iéts onder lag om vanaf te tillen.
const List<BoxShadow> kSchaduw2 = [
  BoxShadow(color: Color(0x47000000), blurRadius: 5, offset: Offset(0, 2)),
  BoxShadow(color: Color(0x73000000), blurRadius: 22, offset: Offset(0, 10)),
];

/// Wat over de app heen ligt: een blad, een menu, een dialoog.
const List<BoxShadow> kSchaduw3 = [
  BoxShadow(color: Color(0x4D000000), blurRadius: 6, offset: Offset(0, 2)),
  BoxShadow(color: Color(0x85000000), blurRadius: 36, offset: Offset(0, 14)),
];

/// Geen schaduw. Bestaat als naam zodat de tv-uitweg leesbaar is.
const List<BoxShadow> kGeenSchaduw = <BoxShadow>[];

// ── Tijd ─────────────────────────────────────────────────────────────────────

/// Indrukken, een kleur die omslaat, een menu dat opengaat.
const Duration kSnel = Duration(milliseconds: 120);

/// Muisaanwijzing en tv-markering.
///
/// **170, en dat blijft zo.** Dit is de duur die overal in de app op tegels staat en die op het
/// toestel goedgekeurd is. Hij staat hier om vindbaar te zijn, niet om bijgesteld te worden.
const Duration kGebaar = Duration(milliseconds: 170);

/// Een pagina die in- of uitschuift, een blad dat opkomt.
const Duration kOvergang = Duration(milliseconds: 260);

/// De kleurwas die van de ene hoes naar de andere loopt.
const Duration kWas = Duration(milliseconds: 420);

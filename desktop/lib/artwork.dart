import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

/// De kleur waar een hoes naar neigt, als ARGB — of null als er niets uitspringt.
///
/// Voor de was achter een albumpagina. Een plat gemiddelde over alle pixels is hiervoor onbruikbaar:
/// dat wordt bruin. Rood en groen naast elkaar middelen tot modder, en een hoes met veel wit of zwart
/// trekt het gemiddelde naar grijs — precies de kleuren waar je géén achtergrond van wil.
///
/// Dus niet middelen maar STEMMEN. Elke pixel die iets van een kleur is, stemt op zijn emmer in een
/// grof raster (4 bits per kanaal), en zijn stem weegt zo zwaar als hij verzadigd is. De zwaarste emmer
/// wint en geeft het gemiddelde van zijn eigen pixels terug — een echte kleur uit de hoes, niet een
/// mengsel dat er nergens in voorkomt.
///
/// Drie soorten pixels stemmen niet mee, en dat is waar de kleur vandaan blijft komen:
///  * bijna zwart — daar is elke kleurmeting ruis;
///  * bijna wit — hetzelfde, plus het is meestal papier of achtergrond;
///  * vrijwel grijs — dat is de definitie van "geen kleur".
///
/// Blijft er dan niets over, dan **null**: een zwart-witte hoes hoort geen gekleurde was te krijgen, en
/// een flauw grijsje is lelijker dan helemaal geen was.
///
/// Draait op 64×64 en niet op de volle hoes: kleur overleeft dat verkleinen ruimschoots, en dit wordt
/// per album gedaan terwijl iemand naar het scherm kijkt.
int? dominantColour(Uint8List bytes) {
  img.Image? im;
  try {
    im = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (im == null || im.width < 8 || im.height < 8) return null;
  const n = 64;
  final t = img.copyResize(im, width: n, height: n);

  final emmers = <int, _Emmer>{};
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final p = t.getPixel(x, y);
      final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
      final hoog = r > g ? (r > b ? r : b) : (g > b ? g : b);
      final laag = r < g ? (r < b ? r : b) : (g < b ? g : b);
      if (hoog < 40 || laag > 215) continue; // bijna zwart, of bijna wit
      final verzadiging = (hoog - laag) / hoog; // hoog > 0, want hoog >= 40
      if (verzadiging < .22) continue; // grijs
      final sleutel = ((r ~/ 16) << 8) | ((g ~/ 16) << 4) | (b ~/ 16);
      (emmers[sleutel] ??= _Emmer()).stem(r, g, b, verzadiging);
    }
  }

  _Emmer? beste;
  for (final e in emmers.values) {
    if (beste == null || e.gewicht > beste.gewicht) beste = e;
  }
  // Een handvol pixels is een compressie-artefact of een stofje op de scan, geen kleur van de hoes.
  if (beste == null || beste.aantal < 10) return null;
  return 0xFF000000 |
      ((beste.r / beste.aantal).round() << 16) |
      ((beste.g / beste.aantal).round() << 8) |
      (beste.b / beste.aantal).round();
}

/// Eén emmer van het kleurenraster: hoe zwaar er op gestemd is, en het gemiddelde eronder.
class _Emmer {
  double gewicht = 0, r = 0, g = 0, b = 0;
  int aantal = 0;

  void stem(double pr, double pg, double pb, double verzadiging) {
    gewicht += verzadiging;
    r += pr;
    g += pg;
    b += pb;
    aantal++;
  }
}

/// What a scan of a release actually shows.
///
/// Discogs says only "primary" or "secondary". A CD release's secondaries are the back of the
/// sleeve, the disc itself, the inlay and the booklet, in no fixed order and with no labels — so
/// the app has to work it out from the pixels, and the user gets the last word in the picker.
enum ArtKind { front, back, disc, other }

/// Is this a scan of a disc?
///
/// Een cd is een ronde schijf op een ondergrond. Drie dingen samen, gemeten in [meetSchijf]:
///  * **de rand** — net binnen de rand van het beeld (90 en 95 % van de halve breedte) is het de
///    schijf, en daarbuiten, in de vier hoeken, de ondergrond; die twee verschillen (`rand > 10`);
///  * **de naaf** — rond het midden, iets verder dan het gat (9 tot 16 %), is een cd egaal: het gat,
///    de doorzichtige naaf, de stapelring. Een hoes of boekje heeft daar druk (`naaf < 15`);
///  * **de ondergrond** — alles buiten de cirkel is even egaal: scannerdeksel, wit vel, zwart doek
///    (`achtergrond < 30`). Een rechthoekige scan loopt met zijn druk door tot in de hoeken.
///
/// **Waarom niet meer "het gat".** Tot 13-10-2026 eiste dit een volkomen vlak gat (spreiding ≤ 4 op
/// een cirkeltje van 6 %). Op de miniaturen waar de uitgavekiezer mee werkt — 150 pixels, JPEG van
/// lage kwaliteit — haalt zelfs een gewone cd-scan dat vaak niet, en een cd die in zijn doosje
/// gefotografeerd is nooit (Saber, 12-10-2026: de roze cd van Discogs 9321705 werd niet herkend,
/// spreiding ±49). Gemeten op twee sets met bekend antwoord:
///  * 138 Discogs-miniaturen, met het oog gelabeld: oud 19 van 41 cd's, 1 keer ten onrechte; nu 28 van
///    41, 0 keer ten onrechte;
///  * 201 scans uit het Cover Art Archive, daar door mensen gelabeld ("Medium" = de cd; twee die als
///    "Spine" of zonder type geüpload waren, bleken ook cd's): oud 51 van 73, 2 keer ten onrechte; nu
///    62 van 73, 0 keer ten onrechte.
/// De drempels zijn op de Discogs-set gekozen en gaven op de andere set dezelfde uitslag; een kleine
/// verschuiving van elke drempel geeft 25–28 en 56–63 cd's, met 0–2 valse. Wat nog gemist wordt, is
/// vooral een cd die scheef of klein in een foto staat, en de zilveren onderkant — die laatste is als
/// draaiende cd ook niet gewenst.
///
/// Nog altijd voorzichtig. Calling a back cover a disc would spin the wrong picture out from behind
/// the sleeve, which looks broken; failing to spot one only costs the animation.
bool looksLikeDisc(Uint8List bytes) {
  final s = meetSchijf(bytes);
  if (s == null) return false;
  return s.rand > 10 && s.naaf < 15 && s.achtergrond < 30;
}

/// Is this shape a plausible rear inlay, given the sleeve it belongs to?
///
/// Wider than tall, because a CD's rear inlay wraps around the spine of the jewel case. But not
/// ANY width: two booklet pages photographed side by side come out near double, and that is a
/// spread, not a back cover. Measured on Random Access Memories (Discogs release 28622347): the
/// sleeve is 1.33, the inlay 1.30, and four of the fourteen scans sit at about 2.0.
///
/// The upper bound is the only thing being added here. Ordering still decides between the
/// candidates that pass, because on real releases the back cover is listed early and no measurement
/// separates it from a single booklet page of the same shape. That is what the picker is for.
///
/// Openbaar sinds 12-10-2026: de uitgavekiezer (`DiscogsService._detail`) koos de achterkant op "breder
/// dan 1,4", en een achterinlay is 1,2 tot 1,3 — dus vrijwel nooit op vorm, en dan won het eerste beeld
/// dat over was. Bij Rusland (Discogs 9321705) was dat de cd, bij Purple Rain (11798563) de binnenkant van
/// het boekje, bij Venezuela (32121567) een foto van het opengeklapte doosje. Met deze regel was het
/// bij alle drie de achterinlay met de tracklijst; bij vijftien andere uitgaves veranderde er niets.
bool kanAchterinlayZijn(double ratio, double sleeve) => ratio > 1.1 && ratio <= sleeve * 1.5;

bool _couldBeInlay(double ratio, double sleeve) => kanAchterinlayZijn(ratio, sleeve);

/// A back cover, as opposed to a front cover.
///
/// There is no reliable pixel-level tell — plenty of back covers are as busy as the front. What
/// there IS: Discogs marks exactly one image primary, and the rear inlay is shaped almost like the
/// sleeve. So this is a measurement of shape, not a certainty, and the picker exists because
/// measurements are wrong sometimes.
ArtKind guessKind(int index, bool primary, Uint8List? bytes) {
  if (primary) return ArtKind.front;
  if (bytes != null && looksLikeDisc(bytes)) return ArtKind.disc;
  return index == 1 ? ArtKind.back : ArtKind.other;
}

/// Which scan is the front, the back and the disc, across a whole release.
///
/// Deciding image by image was not enough on real data: *Dangerous* has 31 scans, and three of them
/// read as a disc — the CD itself and two booklet pages with pale margins. Only one can slide out
/// from behind the sleeve, so the first wins.
///
/// The back cover gets a better signal than "second in the list": a CD's rear inlay wraps around
/// the spine of the jewel case, so it is measurably WIDER than tall where everything else on a CD
/// release is square. Dangerous's is 600×474 among a stack of 600×598s.
///
/// [ratios] and [datas] are parallel to the release's own image order. A null entry in [datas] is
/// an image that couldn't be fetched; it simply can't be the disc.
({int? front, int? back, int? disc}) assignRoles(
  List<bool> primary,
  List<double> ratios,
  List<Uint8List?> datas,
) {
  int? front, back, disc;
  for (var i = 0; i < primary.length; i++) {
    if (front == null && primary[i]) front = i;
  }
  // Geen enkel beeld als "primary" aangewezen: dan is het eerste de voorkant, en dat staat vast
  // VÓÓR de achterkant gekozen wordt. Dit stond onderaan, en dan was het eerste beeld nog vrij toen de
  // achterkant werd gezocht: bij een uitgave met één beeld werd dat ene beeld hoes én achterkant
  // (Discogs 16907574 en 4890343, "1, 2, 3 Soleils", 12-10-2026), en bij vier beelden zonder primary
  // (11728335) zat beeld 1 in beide vakjes.
  front ??= primary.isEmpty ? null : 0;
  // The sleeve's own shape, which is what a rear inlay is measured against.
  final sleeve = (front != null && front < ratios.length) ? ratios[front] : 1.0;
  for (var i = 0; i < primary.length; i++) {
    if (i == front) continue;
    final d = datas.length > i ? datas[i] : null;
    if (disc == null && d != null && looksLikeDisc(d)) {
      disc = i;
      continue;
    }
    if (back == null && ratios.length > i && _couldBeInlay(ratios[i], sleeve)) back = i;
  }
  // No inlay-shaped scan: fall back to the convention, skipping anything already spoken for.
  if (back == null) {
    for (var i = 0; i < primary.length; i++) {
      if (i != front && i != disc) {
        back = i;
        break;
      }
    }
  }
  return (front: front, back: back, disc: disc);
}

/// De drie metingen waarop [looksLikeDisc] beslist. Zie daar waarom juist deze.
@visibleForTesting
typedef SchijfMeting = ({double rand, double naaf, double achtergrond});

/// Meet een plaatje zoals [looksLikeDisc] het bekijkt, of null als het niet te lezen is.
///
/// Op 128×128 en in helderheid. Ringen met 72 punten rond het midden; "buiten" is alles buiten de
/// ingeschreven cirkel (de vier hoeken samen).
@visibleForTesting
SchijfMeting? meetSchijf(Uint8List bytes) {
  img.Image? im;
  try {
    im = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (im == null || im.width < 32 || im.height < 32) return null;
  const n = 128;
  final t = img.copyResize(im, width: n, height: n);

  double lum(int x, int y) {
    final p = t.getPixel(x.clamp(0, n - 1), y.clamp(0, n - 1));
    return .299 * p.r + .587 * p.g + .114 * p.b;
  }

  /// Gemiddelde en spreiding van de helderheid op een cirkel op [deel] van de halve breedte.
  (double, double) ring(double deel) {
    const stappen = 72;
    final r = deel * n / 2;
    var som = 0.0, kwad = 0.0;
    for (var i = 0; i < stappen; i++) {
      final a = i * 2 * math.pi / stappen;
      final v = lum((n / 2 + r * math.cos(a)).round(), (n / 2 + r * math.sin(a)).round());
      som += v;
      kwad += v * v;
    }
    final gem = som / stappen;
    return (gem, math.sqrt(math.max(0.0, kwad / stappen - gem * gem)));
  }

  var som = 0.0, kwad = 0.0, aantal = 0;
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final dx = x - n / 2 + .5, dy = y - n / 2 + .5;
      if (dx * dx + dy * dy <= (n / 2 * 1.02) * (n / 2 * 1.02)) continue;
      final v = lum(x, y);
      som += v;
      kwad += v * v;
      aantal++;
    }
  }
  final buiten = aantal == 0 ? 0.0 : som / aantal;
  final buitenSpreiding = aantal == 0 ? 0.0 : math.sqrt(math.max(0.0, kwad / aantal - buiten * buiten));

  final (rand90, _) = ring(.90);
  final (rand95, _) = ring(.95);
  final (_, naaf09) = ring(.09);
  final (_, naaf12) = ring(.12);
  final (_, naaf16) = ring(.16);
  return (
    rand: (math.max(rand90, rand95) - buiten).abs(),
    naaf: math.min(naaf09, math.min(naaf12, naaf16)),
    achtergrond: buitenSpreiding,
  );
}

/// How many pixels wide this artwork actually needs to be decoded at.
///
/// Every Image in this file decoded at the source resolution, and the sources are big: the covers
/// this app stores are 1200x1200, some originals over 3000. Decoded, a 1200px sleeve is 1200 x 1200 x
/// 4 bytes — 5.8 MB of bitmap — and a 120px grid tile needs 57 KB of that. A hundred and twenty-five
/// albums on screen therefore ask for far more than Flutter's image cache holds, so it evicts and
/// re-decodes while you scroll: the work is done again and again for pictures that were already
/// there.
///
/// A hint, not a resize: `cacheWidth` tells the decoder how small it may go, and BoxFit still does
/// the layout. Multiplied by the screen's pixel ratio so a 2x display gets a sharp image rather than
/// a soft one, and clamped because a hint derived from a wrong ratio should cost a little sharpness,
/// never correctness.
int decodeWidth(double logicalSize) {
  var dpr = 1.0;
  try {
    dpr = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
  } catch (_) {/* no view yet — the default is fine for a hint */}
  if (!dpr.isFinite || dpr < 1) dpr = 1;
  if (dpr > 4) dpr = 4;
  // Never below 64: a hint smaller than that makes even a list thumbnail visibly mushy.
  final w = (logicalSize * dpr).round();
  return w < 64 ? 64 : w;
}

/// De vorige zware beeldberekening, wat voor eentje het ook was. Zie [_opDeRij].
Future<void> _vorigeBeeldberekening = Future<void>.value();

/// Eén zware beeldberekening tegelijk, over ALLE soorten heen.
///
/// **Waarom één gedeelde rij en niet één per soort.** De reden staat uitgeschreven bij
/// [kleurBuitenDeTekendraad]: verse isolates die tegelijk grote plaatjes kopiëren brachten de
/// Windows-engine zes keer om. Twee rijen naast elkaar zijn geen rij — dan lopen er alsnog twee
/// isolates tegelijk, en precies dat is wat vermeden moet worden. Dus zit de kleurberekening van een
/// hoes in dezelfde wachtrij als het herkennen van een schijf.
///
/// De staart van de rij is expres een `Future<void>` die NOOIT met een fout eindigt: een mislukte
/// berekening mag de volgende niet meeslepen, en een niet-afgevangen fout in een veld dat nergens
/// meer bekeken wordt is een melding in het log die niemand kan plaatsen.
Future<T> _opDeRij<T>(Future<T> Function() doen) {
  final volgende = _vorigeBeeldberekening.then((_) => doen());
  _vorigeBeeldberekening = volgende.then((_) {}, onError: (_) {});
  return volgende;
}

/// Welke van deze scans er als eerste als een schijf uitziet, of null als geen enkele dat doet.
///
/// De VOLGORDE beslist en niet wie het snelst klaar is — een plaat kan meer dan één ronde scan
/// hebben (een boekjespagina met een bleke kern haalt het soms), en dan is de eerste de juiste.
/// Precies wat de lus deed die hier stond; nu op één plek, zodat hij in één keer de isolate in kan.
int? eersteSchijf(List<Uint8List?> scans) {
  for (var i = 0; i < scans.length; i++) {
    final b = scans[i];
    if (b != null && looksLikeDisc(b)) return i;
  }
  return null;
}

/// [eersteSchijf], maar buiten de tekendraad.
///
/// **Waarom dit moest.** `looksLikeDisc` ontcijfert een plaatje met `package:image` — pure Dart —
/// en verkleint het daarna naar 128×128. Dat is tientallen milliseconden per scan, en het gebeurde
/// tot ZES keer per uitgave, voor élke rij die in beeld kwam, in een lus die doorloopt zolang de
/// uitgavekiezer openstaat. Op een telefoon stond de tekendraad daardoor vrijwel onafgebroken stil:
/// je tikte een scan aan om hem als hoes te kiezen en het paarse randje verscheen pas een tel later.
/// Gemeld op 27-08-2026: *"ik wil dit instant zien veranderen … nu zit er behoorlijk wat tijd
/// tussen waardoor ik soms twijfel of hij het wel heeft aangepast"*.
///
/// Alles in ÉÉN oversteek: zes miniaturen van een paar kilobyte kosten samen minder dan zes keer
/// een isolate opstarten, en de volgorde blijft binnen de isolate bewaard.
Future<int?> eersteSchijfBuitenDeTekendraad(List<Uint8List?> scans) =>
    _opDeRij(() => Isolate.run(() => eersteSchijf(scans)));

/// [assignRoles], maar buiten de tekendraad. Zelfde reden als hierboven — en hier weegt het zwaarder,
/// want een boekje van een plaat kan dertig scans hebben en die gingen er allemaal doorheen.
Future<({int? front, int? back, int? disc})> rollenBuitenDeTekendraad(
  List<bool> primary,
  List<double> ratios,
  List<Uint8List?> datas,
) =>
    _opDeRij(() => Isolate.run(() => assignRoles(primary, ratios, datas)));

/// De hoeskleur uitrekenen in een isolate — en dit MOET buiten elke klasse staan.
///
/// Een closure neemt zijn hele omgeving mee, en de omgeving van een instantiemethode bevat `this`. Zet
/// je `Isolate.run(() => dominantColour(bytes))` in een State, dan gaat die State mee de isolate in, en
/// daaraan hangt de complete widgetboom. Dart weigert dat terecht:
///
///     object is unsendable - Class: _AsyncCompleter
///      <- Instance of '_AlbumDetailPageState'
///      <- _AlbumDetailPageState._kleurUitHoes.<anonymous closure>
///
/// Het venijnige is dat het van buiten niet te zien is: er verschijnt geen melding, de achtergrond
/// blijft gewoon zwart, en de reparatie lijkt niet te werken terwijl elk onderdeel los wél werkt. Ik heb
/// hem in een los Dart-programma getest — daar zit geen `this` omheen en daar wérkte het. Pas een
/// logregel in de app zelf gaf de uitzondering te zien.
///
/// Hier omheen zit geen klasse, dus vangt de closure alleen [bytes], en dat is een Uint8List: verzendbaar.
///
/// **En hier, in artwork.dart, en niet in main.dart.** Er zijn inmiddels drie plekken die dit nodig
/// hebben — de albumpagina, het speelscherm en de spelerbalk — en de rij hieronder werkt alleen als
/// ze hem ALLEMAAL delen: drie eigen rijen zijn geen rij.
///
/// De hoofdkleur van een hoes, buiten de tekendraad — maar ÉÉN TEGELIJK.
///
/// **Waarom die rij, en niet gewoon `Isolate.run` per hoes.** De pc-app crashte deze week zes keer
/// uit zichzelf. Windows noteert elke keer hetzelfde:
///
///     Naam van foutmodule: flutter_windows.dll
///     Uitzonderingscode: 0xc0000005      (toegangsfout)
///     Foutoffset: 0x1cda0
///
/// Geen Dart-uitzondering dus, maar de engine zelf. En het laatste wat de app opschreef, telkens
/// binnen een minuut voor de klap, was een reeks van deze berekeningen:
///
///     21:54:20  was "James Blunt - Back To Bedlam": 5021648 bytes → #685539
///     21:55:19  was "Notre-Dame De Paris": 85817 bytes → #471716
///
/// Elke aanroep startte een verse isolate en kopieerde de hele hoes erin — vijf megabyte per stuk,
/// meerdere per seconde als je door een album bladert of als de verrijker hoezen binnenhaalt. Ze op
/// een rij zetten haalt die piek weg: hooguit één isolate tegelijk, en de kopie van de vorige is
/// opgeruimd voor de volgende begint.
///
/// **Eerlijk over wat dit is:** de correlatie is sterk (zes crashes, alle zes vlak na zo'n reeks) en
/// het mechanisme past, maar bewezen is het niet — de engine valt om zonder te zeggen waaróm. Blijft
/// hij crashen, dan staat in `ui.log` opnieuw wat er vlak daarvoor gebeurde, en is de volgende
/// verdachte niet meer deze.
Future<int?> kleurBuitenDeTekendraad(Uint8List bytes) =>
    _opDeRij(() => Isolate.run(() => dominantColour(bytes)));

/// Hoeveel pixel een hoes hoogstens breed of hoog hoeft te zijn om naar een toestel te sturen.
///
/// De grootste plek waar een hoes op een telefoon van 1440 pixels terechtkomt is het nu-spelend
/// venster: daar is hij ongeveer 975 pixels breed. Duizendvierentwintig is daar net boven en is een
/// macht van twee, wat het schalen op de GPU niets extra kost.
const int kHoesPlafond = 1024;

/// Een hoes klein genoeg om over een mobiel netwerk te sturen. Null als er niets te winnen valt.
///
/// **Waarom dit bestaat.** Geteld op 13-09-2026 over de hele bibliotheek van deze pc — 544 albums,
/// waarvan er 541 een hoes teruggeven, samen **172,4 MiB**. De mediaan is 120,6 KiB en de mediane
/// langste zijde 600 pixels; dat is prima. De staart niet:
///
///     14,70 MiB   2780x2780  png
///     14,65 MiB   4000x4000  jpg
///      2,63 MiB   1024x1024  png   <- niet te groot, wel de verkeerde vorm
///
/// Honderdzesenvijftig hoezen (29 %) zitten boven 1024 pixels. Een telefoon haalt die op volle
/// resolutie op voor een tegel van 390 pixels, over 5G. Wat je op het scherm ziet is een raster met
/// titels en zwarte vlakken.
///
/// **Waar de winst zit, geteld en niet geschat.** Die 156 hoezen boven het plafond gaan samen van
/// 127,0 naar 30,5 MiB — dat is 96,5 van de ruim honderd MiB die dit oplevert. Verkleinen is dus
/// het leeuwendeel.
///
/// Maar er wordt ALTIJD als JPEG teruggegeven, ook als er niet verkleind hoeft te worden: er staan
/// maar zeven PNG's in deze bibliotheek en die wegen samen 32,6 MiB tegen 1,3 MiB als JPEG.
/// Gemiddeld 4,66 MiB per PNG tegen 261 KiB per JPEG — achttien keer zo zwaar bij dezelfde
/// afmeting.
///
/// **Eerlijk over wat dat kost: JPEG is verliesgevend.** De afmeting blijft, de pixels niet. Van die
/// 1024x1024-PNG naar JPEG op kwaliteit 82 is nagemeten op 40,4 dB PSNR, en een hoes van 600 pixels
/// die al JPEG was op 42,7 dB. Dat is ruim boven de grens waar iemand het op een tegel van 390
/// pixels ziet, maar het is geen kopie. Wie het origineel wil vraagt zonder plafond, en dat blijft
/// bit voor bit wat het was.
///
/// **Twee instellingen die niet de standaard van `package:image` zijn, allebei nagemeten.**
///
/// `yuv420` en niet `yuv444`: zonder chroma-subsampling is voor een foto weggegooide ruimte — het
/// oog ziet kleurdetail veel grover dan helderheid, en 533 van de 541 hoezen hier ZIJN al JPEG en
/// dus vrijwel zeker al 4:2:0. Over de hele bibliotheek geteld: 70,1 MiB met yuv444 tegen 57,0 met
/// yuv420.
///
/// `Interpolation.average` en niet de standaard `nearest`: die laatste gooit bij 2400 naar 1024
/// tweeëntachtig procent van de pixels weg zonder te middelen. Dat geeft karteling op fijn detail —
/// op een streepjespatroon bleef de standaardafwijking 120,0 tegen 60,0 bij `average` — én duurdere
/// bestanden, want karteling is hoogfrequent en dat is precies wat JPEG slecht kan. Gemeten op een
/// hoes van 2400 pixels: nearest 44 KB tegen average 28 KB. Het kost 34 ms per hoes extra, en over
/// de hele bibliotheek scheelt het 57,0 tegen 55,4 MiB — plus de karteling die niemand wil zien.
///
/// **Doorzichtigheid gaat als PNG mee, niet als niets.** JPEG kent geen alfakanaal en zou er wit
/// van maken: een hoes die op de pc doorzichtig over de achtergrond ligt, zou op de telefoon op een
/// wit vlak staan. Hem dan maar helemaal overslaan is echter een klif — een hoes van 4000x4000 met
/// ÉÉN pixel op alfa 254 ging daarmee van 26 KB naar 28 MB, een factor elfhonderd, en er zou niets
/// over gemeld worden. Een afgeronde hoek of een anti-aliased rand is al genoeg. Dus wordt zo'n hoes
/// wél verkleind en als PNG teruggegeven: dezelfde doorzichtigheid, dezelfde pixels, en voor die
/// 4000x4000 nog altijd megabytes minder.
///
/// **Null betekent "laat het origineel staan".** Niet te ontcijferen, het resultaat werd niet
/// kleiner, of een van deze twee:
///
///  * **Er zit beweging in** (een GIF met meer dan één beeld): `encodeJpg` schrijft er stil het
///    eerste beeld van en de rest is weg.
///  * **De verhouding is zo extreem dat er een zijde van niets overblijft.** `copyResize(height:)`
///    rekent de breedte uit als `round(maxZijde * b/h)`, en bij 8x20000 is dat nul. Dat leverde een
///    geldige JPEG van nul pixels breed op, die kleiner was dan de bron en dus verstuurd werd.
Uint8List? verkleindeHoes(Uint8List bytes, int maxZijde) {
  try {
    final im = img.decodeImage(bytes);
    if (im == null || im.width < 8 || im.height < 8) return null;
    if (im.frames.length > 1) return null;
    final doorzichtig = im.hasAlpha && _heeftEchteDoorzichtigheid(im);

    final grootste = im.width > im.height ? im.width : im.height;
    final t = grootste <= maxZijde
        ? im
        : (im.width >= im.height
            ? img.copyResize(im, width: maxZijde, interpolation: img.Interpolation.average)
            : img.copyResize(im, height: maxZijde, interpolation: img.Interpolation.average));
    if (t.width < 8 || t.height < 8) return null;

    final uit = Uint8List.fromList(doorzichtig
        ? img.encodePng(t)
        : img.encodeJpg(t, quality: 82, chroma: img.JpegChroma.yuv420));
    return uit.length < bytes.length ? uit : null;
  } catch (_) {
    // **Alles eromheen, en niet alleen het ontcijferen.** `copyResize` en `bakeOrientation` kunnen
    // er ook uit stappen, en dan liep de fout door de isolate en door de server heen tot een 500 —
    // waarna het toestel de hoes als mislukt telde en niets toonde, terwijl het origineel gewoon
    // verstuurd had kunnen worden.
    return null;
  }
}

/// Is er ook maar één pixel die niet volledig dekkend is?
///
/// `hasAlpha` zegt alleen dat er een kanaal is, niet dat het gebruikt wordt — en de meeste PNG's met
/// een alfakanaal zijn van rand tot rand dekkend. Die willen we juist wél omzetten: zij zijn de
/// zwaarste bestanden in de bibliotheek.
bool _heeftEchteDoorzichtigheid(img.Image im) {
  final max = im.maxChannelValue;
  for (final p in im) {
    if (p.a < max) return true;
  }
  return false;
}

/// [verkleindeHoes], buiten de tekendraad en op dezelfde rij als de rest. Zie [_opDeRij]: een verse
/// isolate per hoes kopieert megabytes en dat viel samen met zes crashes van de engine.
Future<Uint8List?> verkleindeHoesBuitenDeTekendraad(Uint8List bytes, int maxZijde) =>
    _opDeRij(() => Isolate.run(() => verkleindeHoes(bytes, maxZijde)));

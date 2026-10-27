// De foto in de kop van een artiestpagina: over de volle breedte, slim uitgesneden op de mensen erin,
// en door jou bij te stellen (Saber, 17-10-2026: "volle breedte, slim uitgesneden, maar ik kan nog
// aanpassen, zelf de hero van hoogte veranderen, bijknippen, in en uit zoomen").
//
// Waarom slim uitsnijden: de kop is op een tv 960 × 435 punten, en een gekozen foto is vaak staand
// (die van *NSYNC: 599 × 688). Over de volle breedte getrokken valt daar bijna 60 % van weg, en met
// een vaste uitlijning stonden de gezichten half achter het menu.
//
// Hoe: eerst gezichten zoeken (`gezichten.dart`, op vorm), en alleen als er geen gevonden wordt op
// huidkleur en detail. Gemeten op 77 echte artiestfoto's van de pc (17-10-2026): op kleur alleen viel
// het brandpunt bij een oranje muur, baksteen, rode ballen of een publiek naast de mensen; de
// gezichtszoeker vond de groep bij 2 Be 3 (3), Backstreet Boys (5), Duran Duran (5) en *NSYNC.
import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../beeldvorm.dart' show KopInstelling;
import '../gezichten.dart';

/// Waar de mensen in een foto staan: het punt (0..1, 0..1) waar de uitsnede omheen gelegd wordt.
@immutable
class Brandpunt {
  const Brandpunt(this.x, this.y);
  final double x, y;

  /// Als er niets te vinden is: het midden, iets boven het midden — daar staan in een persfoto de
  /// hoofden het vaakst.
  static const midden = Brandpunt(.5, .32);

  @override
  String toString() => 'Brandpunt(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
}

/// Wat er van een foto bekend is na één keer kijken.
///
/// [maat] is de verhouding ZOALS HIJ GETEKEND WORDT (een JPEG die rechtop gedraaid moet worden, heeft
/// in zijn kop de maten van liggend — de decoder draait hem, de kop niet). [gezichten] is het vak om
/// alle gevonden gezichten samen, als deel van de foto (0..1), of null als er geen gevonden zijn.
@immutable
class FotoBlik {
  const FotoBlik(this.punt, this.maat, [this.gezichten]);
  final Brandpunt punt;
  final Size maat;
  final Rect? gezichten;

  /// "0.512,0.300,599,688" of met het gezichtenvak erachter: "…,0.10,0.14,0.92,0.31".
  String schrijf() => [
        punt.x.toStringAsFixed(3),
        punt.y.toStringAsFixed(3),
        maat.width.round(),
        maat.height.round(),
        if (gezichten case final g?) ...[g.left, g.top, g.right, g.bottom].map((v) => v.toStringAsFixed(3)),
      ].join(',');

  static FotoBlik? lees(String? s) {
    if (s == null) return null;
    final d = s.split(',').map(double.tryParse).toList();
    if ((d.length != 4 && d.length != 8) || d.any((v) => v == null || !v.isFinite)) return null;
    if (d[2]! <= 0 || d[3]! <= 0) return null;
    return FotoBlik(
      Brandpunt(d[0]!.clamp(0.0, 1.0), d[1]!.clamp(0.0, 1.0)),
      Size(d[2]!, d[3]!),
      d.length == 8 ? Rect.fromLTRB(d[4]!, d[5]!, d[6]!, d[7]!) : null,
    );
  }

  @override
  String toString() => 'FotoBlik(${schrijf()})';
}

/// Hoe groot een foto bekeken wordt: de lange zijde op 480. Groot genoeg voor de vijf gezichten van
/// een groepsfoto (bij de Backstreet Boys 33 tot 46 punten breed; de zoeker begint bij 24), klein
/// genoeg voor een paar honderd milliseconden in een eigen draad.
const int kBekijkMaat = 480;

/// Wat een foto laat zien: gezichten, en anders het bovenste stuk huid of detail. Zuiver en zonder
/// Flutter, zodat het in een `Isolate.run` past. [rgba] is [breed] × [hoog], vier bytes per punt.
@visibleForTesting
FotoBlik ontleedFoto(Uint8List rgba, int breed, int hoog) {
  final maat = Size(breed.toDouble(), hoog.toDouble());
  if (breed <= 0 || hoog <= 0 || rgba.length < breed * hoog * 4) return FotoBlik(Brandpunt.midden, maat);
  final n = breed * hoog;
  final grijs = Uint8List(n);
  var kleur = 0.0;
  for (var i = 0; i < n; i++) {
    final r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2];
    grijs[i] = (r * 77 + g * 150 + b * 29) >> 8;
    kleur += (r - g).abs() + (g - b).abs();
  }
  final inKleur = kleur / n >= 10;
  // Minstens zes ramen die het eens zijn. Met vier of vijf kwamen er valse gezichten door: de borst van
  // Michael Jackson onder een spot, een struik bloemen naast Alicia Keys, een stuk mouw bij James Blunt
  // (gemeten op 77 foto's, 17-10-2026). Wat daardoor wegvalt, is meestal een gezicht dat half wegdraait,
  // en dat vangt de terugval op huid en detail hieronder goed op.
  var gezichten = [for (final g in vindGezichten(grijs, breed, hoog)) if (g.buren >= 6) g];
  if (inKleur) {
    // In een kleurenfoto heeft een echt gezicht huid. Zonder deze toets telde een vak in een struik
    // rode bloemen en een stuk lege roze muur als gezicht (gezien bij Alicia Keys en Alabina).
    gezichten = [for (final g in gezichten) if (_huidIn(rgba, breed, g) >= .15) g];
  }
  if (gezichten.isNotEmpty) {
    // De groep: wat op de rij van het duidelijkste gezicht staat en niet veel kleiner is. Een klein
    // gezicht ver onder of boven de rest is vaker een vergissing (of een poster op de achtergrond)
    // dan een bandlid.
    final beste = gezichten.reduce((a, b) => a.buren * a.breedte >= b.buren * b.breedte ? a : b);
    final groep = [
      for (final g in gezichten)
        if (g.breedte >= beste.breedte * .5 &&
            ((g.boven + g.hoogte / 2) - (beste.boven + beste.hoogte / 2)).abs() <= beste.hoogte * .9)
          g,
    ];
    var l = double.infinity, t = double.infinity, r = -double.infinity, o = -double.infinity;
    for (final g in groep) {
      l = math.min(l, g.links);
      t = math.min(t, g.boven);
      r = math.max(r, g.rechts);
      o = math.max(o, g.onder);
    }
    final vak = Rect.fromLTRB(l / breed, t / hoog, r / breed, o / hoog);
    return FotoBlik(Brandpunt(vak.center.dx, vak.center.dy), maat, vak);
  }
  // Nooit lager dan net onder waar het onderwerp begint: zonder gezicht viel het punt anders op rode
  // ballen aan iemands voeten of op het publiek voor een gitarist, en dan ging het hoofd eraf.
  final p = brandpuntVan(rgba, breed, hoog);
  return FotoBlik(Brandpunt(p.x, math.min(p.y, onderwerpBoven(rgba, breed, hoog) + .14)), maat);
}

/// Waar het onderwerp begint, als deel van de hoogte: de eerste rij die druk is (veel verschil met de
/// buren) tegenover de drukste rijen. Boven een effen lucht of studiomuur is dat de kruin; bij een
/// drukke achtergrond (baksteen, keien) is het de bovenrand, en dan wint gewoon de bovenkant.
@visibleForTesting
double onderwerpBoven(Uint8List rgba, int breed, int hoog) {
  if (breed < 2 || hoog < 4 || rgba.length < breed * hoog * 4) return 0;
  double luma(int i) => .299 * rgba[i * 4] + .587 * rgba[i * 4 + 1] + .114 * rgba[i * 4 + 2];
  final rij = List<double>.filled(hoog, 0);
  for (var y = 0; y < hoog - 1; y++) {
    var t = 0.0;
    for (var x = 0; x < breed - 1; x++) {
      final i = y * breed + x;
      final l = luma(i);
      t += (l - luma(i + 1)).abs() + (l - luma(i + breed)).abs();
    }
    rij[y] = t / breed;
  }
  // Over drie rijen gemiddeld, zodat één streep (een kabel, een horizon) niet telt.
  final glad = [for (var y = 0; y < hoog; y++) (rij[math.max(0, y - 1)] + rij[y] + rij[math.min(hoog - 1, y + 1)]) / 3];
  final gesorteerd = [...glad]..sort();
  final drempel = gesorteerd[(gesorteerd.length * .8).floor().clamp(0, gesorteerd.length - 1)] * .35;
  for (var y = 0; y < hoog; y++) {
    if (glad[y] >= drempel && drempel > 0) return y / hoog;
  }
  return 0;
}

/// Welk deel van een gezichtsvak huidkleurig is (de ruime YCbCr-regel: belichting op een podium
/// maakt een gezicht vaak te rood of te geel voor [isHuid]).
double _huidIn(Uint8List rgba, int breed, Gezicht g) {
  var huid = 0, alles = 0;
  final x0 = g.links.floor(), y0 = g.boven.floor();
  for (var y = y0; y < (g.onder).ceil(); y++) {
    for (var x = x0; x < (g.rechts).ceil(); x++) {
      final i = (y * breed + x) * 4;
      if (i < 0 || i + 2 >= rgba.length || x >= breed) continue;
      alles++;
      final r = rgba[i], gr = rgba[i + 1], b = rgba[i + 2];
      final cb = 128 - .168736 * r - .331264 * gr + .5 * b;
      final cr = 128 + .5 * r - .418688 * gr - .081312 * b;
      if (cb >= 77 && cb <= 127 && cr >= 133 && cr <= 173) huid++;
    }
  }
  return alles == 0 ? 0 : huid / alles;
}

/// De terugval als er geen gezicht gevonden wordt (een profiel, een hoofd dat naar beneden kijkt): het
/// brandpunt van een RGBA-afbeelding van [breed] × [hoog] op huid en detail.
///
/// **Huid.** Een punt telt als huid volgens [isHuid]. Van alle huid kiezen we het BOVENSTE deel: armen
/// en halzen zijn ook huid, gezichten staan erboven. Het brandpunt is het zwaartepunt van de huid in
/// een band rond het bovenste kwart.
///
/// **Anders detail.** Een zwart-witfoto heeft geen kleur om huid aan te herkennen. Dan telt waar het
/// beeld het drukst is (verschil met de buren), met de bovenkant zwaarder dan de onderkant — een
/// gezicht heeft meer detail dan een egale achtergrond, en ligt in een persfoto zelden onderaan.
Brandpunt brandpuntVan(Uint8List rgba, int breed, int hoog) {
  if (breed <= 0 || hoog <= 0 || rgba.length < breed * hoog * 4) return Brandpunt.midden;
  final n = breed * hoog;
  var kleur = 0.0;
  for (var i = 0; i < n; i++) {
    final r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2];
    kleur += (r - g).abs() + (g - b).abs();
  }
  if (kleur / n >= 10) {
    final huidY = <int>[];
    final huidX = <int>[];
    for (var y = 0; y < hoog; y++) {
      for (var x = 0; x < breed; x++) {
        final i = (y * breed + x) * 4;
        if (isHuid(rgba[i], rgba[i + 1], rgba[i + 2])) {
          huidY.add(y);
          huidX.add(x);
        }
      }
    }
    if (huidY.length >= n * .006) {
      final gesorteerd = [...huidY]..sort();
      final bovenkant = gesorteerd[(gesorteerd.length * .25).floor()];
      final band = math.max(2, (hoog * .18).round());
      var sx = 0.0, sy = 0.0, k = 0;
      for (var j = 0; j < huidY.length; j++) {
        if ((huidY[j] - bovenkant).abs() <= band) {
          sx += huidX[j];
          sy += huidY[j];
          k++;
        }
      }
      if (k > 0) return Brandpunt((sx / k + .5) / breed, (sy / k + .5) / hoog);
    }
  }
  double luma(int x, int y) {
    final i = (y * breed + x) * 4;
    return .299 * rgba[i] + .587 * rgba[i + 1] + .114 * rgba[i + 2];
  }

  final rijGewicht = List<double>.filled(hoog, 0);
  var sx = 0.0, totaal = 0.0;
  for (var y = 0; y < hoog - 1; y++) {
    final voorkeur = 1.0 - .6 * (y / hoog); // boven 1, onder 0,4
    for (var x = 0; x < breed - 1; x++) {
      final l = luma(x, y);
      final w = ((l - luma(x + 1, y)).abs() + (l - luma(x, y + 1)).abs()) * voorkeur;
      rijGewicht[y] += w;
      sx += w * x;
      totaal += w;
    }
  }
  if (totaal <= 0) return Brandpunt.midden;
  // Verticaal: waar de eerste 35 % van al het detail bereikt is — het bovenste drukke deel.
  var opgeteld = 0.0, yy = 0;
  for (; yy < hoog; yy++) {
    opgeteld += rijGewicht[yy];
    if (opgeteld >= totaal * .35) break;
  }
  return Brandpunt(((sx / totaal) + .5) / breed, (yy + .5) / hoog);
}

/// Of één punt huid is: in YCbCr in het huidgebied (Cb 77–127, Cr 133–173) én in RGB de tint van huid
/// — rood boven groen boven blauw, tint 0–38°, verzadigd 12–78 %. Die tweede regel kwam erbij na de
/// eerste meting: YCbCr alleen nam ook een goudkleurig jasje (tint 46°) en een roze deur (haast geen
/// kleur) voor huid. De bovengrens staat op 78 % en niet lager: donkere huid is verzadigder dan lichte
/// (141, 85, 36 is 74 %), en die viel er bij 68 % uit.
@visibleForTesting
bool isHuid(int r, int g, int b) {
  final luma = .299 * r + .587 * g + .114 * b;
  if (luma < 40 || luma > 240) return false;
  final cb = 128 - .168736 * r - .331264 * g + .5 * b;
  final cr = 128 + .5 * r - .418688 * g - .081312 * b;
  if (cb < 77 || cb > 127 || cr < 133 || cr > 173) return false;
  if (r < g + 6 || g < b - 4) return false;
  final spreiding = r - math.min(g, b);
  if (spreiding <= 0) return false;
  final verzadiging = spreiding / r;
  if (verzadiging < .12 || verzadiging > .78) return false;
  final tint = 60 * (g - b) / spreiding; // r is de hoogste, dus tint = 60° × (g − b) / (max − min)
  return tint >= -6 && tint <= 38;
}

/// Waar wat over foto's bekend is bewaard blijft tussen twee starts. De app plugt dit in (zie
/// `main.dart`), zodat dit bestand zelf geen schijf kent en in een toets niets wegschrijft.
///
/// Zo is het echt "één keer per foto" (Saber koos: offline, één keer per foto): de tweede keer dat je
/// een artiest opent staat de foto meteen goed, zonder dat hij eerst nog even verschuift.
abstract final class FotoBlikGeheugen {
  static String? Function(String sleutel)? lees;
  static void Function(String sleutel, String waarde)? schrijf;

  /// Een regel voor kop.log: hoe lang het kijken duurde, en waar. Zie `main()`.
  static void Function(String regel)? meld;
}

/// De sleutel van een foto in [FotoBlikGeheugen]: de lengte en een FNV-1a over alle bytes, met de
/// versie van het kijken ervoor — verandert [ontleedFoto], dan telt wat er bewaard is niet meer.
@visibleForTesting
String fotoSleutel(Uint8List b) {
  var h = 0x811c9dc5;
  for (var i = 0; i < b.length; i++) {
    h = ((h ^ b[i]) * 0x01000193) & 0xffffffff;
  }
  return 'g1:${b.length.toRadixString(36)}:${h.toRadixString(36)}';
}

/// Wat er van een foto bekend is, één keer uitgerekend per foto en daarna uit het geheugen (en uit
/// [FotoBlikGeheugen]). Null als de foto niet te lezen is.
Future<FotoBlik?> bekijkFoto(Uint8List beeld) {
  final al = bekendeBlik(beeld);
  if (al != null) return Future.value(al);
  // Een blok en geen pijl: `=> _blikBezig[beeld] = null` geeft de toewijzing terug, en dat hoort
  // hier niet de waarde van de future te worden.
  return _blikBezig[beeld] ??= _bekijkVers(beeld).whenComplete(() {
    _blikBezig[beeld] = null;
  });
}

/// Wat al bekend is, zonder te wachten — voor het eerste beeld.
FotoBlik? bekendeBlik(Uint8List beeld) {
  final al = _blikken[beeld];
  if (al != null) return al;
  final lees = FotoBlikGeheugen.lees;
  if (lees == null) return null;
  final klok = Stopwatch()..start();
  final bewaard = FotoBlik.lees(lees(_sleutels[beeld] ??= fotoSleutel(beeld)));
  if (bewaard != null) _blikken[beeld] = bewaard;
  FotoBlikGeheugen.meld?.call('kop: ${beeld.length ~/ 1024} KB ${bewaard == null ? 'nog niet bekeken' : 'uit het geheugen'} '
      '(sleutel ${klok.elapsedMicroseconds} µs)');
  return bewaard;
}

/// Per foto-object, en weg zodra de foto weg is.
final _blikken = Expando<FotoBlik>('fotoblik');
final _blikBezig = Expando<Future<FotoBlik?>>('fotoblik-bezig');
final _sleutels = Expando<String>('fotosleutel');

Future<FotoBlik?> _bekijkVers(Uint8List beeld) async {
  final klok = Stopwatch()..start();
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(beeld);
    final beschrijving = await ui.ImageDescriptor.encoded(buffer);
    final lang = math.max(beschrijving.width, beschrijving.height);
    final breedte = lang > kBekijkMaat ? (beschrijving.width * kBekijkMaat / lang).round() : beschrijving.width;
    beschrijving.dispose();
    buffer.dispose();
    final codec = await ui.instantiateImageCodec(beeld, targetWidth: math.max(1, breedte));
    final img = (await codec.getNextFrame()).image;
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final w = img.width, h = img.height;
    img.dispose();
    codec.dispose();
    if (data == null || w <= 0 || h <= 0) return null;
    final rgba = data.buffer.asUint8List();
    final gelezen = klok.elapsedMilliseconds;
    // In een eigen draad: op een Shield duurt dit een paar honderd milliseconden, en in de hoofddraad
    // zou de pagina daar net bij het openen op haperen.
    final blik = await Isolate.run(() => ontleedFoto(rgba, w, h));
    FotoBlikGeheugen.meld?.call('kop: bekeken ${beeld.length ~/ 1024} KB als ${w}×$h — decoderen $gelezen ms, '
        'zoeken ${klok.elapsedMilliseconds - gelezen} ms · ${blik.gezichten == null ? 'geen gezicht' : 'gezichten'}');
    _blikken[beeld] = blik;
    FotoBlikGeheugen.schrijf?.call(_sleutels[beeld] ??= fotoSleutel(beeld), blik.schrijf());
    return blik;
  } catch (_) {
    return null;
  }
}

/// Waar de foto in een vak van [vak] komt te staan: geschaald tot hij het vak vult (cover), keer
/// [zoom], en zo verschoven dat [punt] op [doel] (als deel van het vak) valt — zonder dat er ooit
/// een rand vrijkomt. Zuiver, voor de toets en voor de bewerker.
///
/// Met [gezichten] (het vak om alle gezichten, als deel van de foto) en [zicht] (een vak in de kop,
/// als deel ervan) schuift hij daarna nog zo weinig mogelijk bij, tot de gezichten met hun haar en kin
/// ([gezichtenMetRuimte]) helemaal in [zicht] vallen: de hele groep, niet alleen het midden ervan.
/// Past dat niet, dan de gezichten zelf, in het midden van [zicht]; en is zelfs één gezicht groter
/// dan [zicht] (een close-up), dan de ogen in het midden. Eerst stond hier "de kruin gaat voor", en
/// bij een close-up van Alicia Keys zag je dan alleen haar haar (gemeten op 17-10-2026).
///
/// [opzij] is hoeveel van de breedte van het vak de foto opzij mag vrijlaten (zie [kOpzijVrij]): 0 is
/// altijd vullend, zoals de app zelf kiest.
Rect kopPlek({
  required Size vak,
  required Size beeld,
  required Brandpunt punt,
  required Offset doel,
  double zoom = 1,
  Rect? gezichten,
  Rect? zicht,
  double opzij = 0,
}) {
  if (beeld.width <= 0 || beeld.height <= 0 || vak.isEmpty || !vak.isFinite) return Offset.zero & vak;
  final s = math.max(vak.width / beeld.width, vak.height / beeld.height) *
      zoom.clamp(1.0, KopInstelling.kZoomTot);
  final w = beeld.width * s, h = beeld.height * s;
  var links = doel.dx * vak.width - punt.x * w;
  var boven = doel.dy * vak.height - punt.y * h;
  if (gezichten != null && zicht != null) {
    final ruim = gezichtenMetRuimte(gezichten);
    // Eén as tegelijk: [van]–[tot] is het ruime vak, [kern] het gezichtenvak zelf, [ogen] de hoogte
    // van de ogen erin — alles al in punten van de geschaalde foto, vanaf zijn eigen rand.
    double schuif(double plek, double van, double tot, double kernVan, double kernTot, double ogen,
        double zichtVan, double zichtTot) {
      if (tot - van <= zichtTot - zichtVan) {
        if (plek + van < zichtVan) return zichtVan - van;
        if (plek + tot > zichtTot) return zichtTot - tot;
        return plek;
      }
      final midden = (zichtVan + zichtTot) / 2;
      if (kernTot - kernVan <= zichtTot - zichtVan) return midden - (kernVan + kernTot) / 2;
      return midden - ogen;
    }

    links = schuif(links, ruim.left * w, ruim.right * w, gezichten.left * w, gezichten.right * w,
        gezichten.center.dx * w, zicht.left * vak.width, zicht.right * vak.width);
    boven = schuif(boven, ruim.top * h, ruim.bottom * h, gezichten.top * h, gezichten.bottom * h,
        (gezichten.top + gezichten.height * .42) * h, zicht.top * vak.height, zicht.bottom * vak.height);
  }
  // De ondergrens met `min(…, 0)`: past de foto precies, dan is `vak - w` door afronding soms een
  // haar boven nul (gemeten: 1,1e-13 bij een foto van 600 breed), en `clamp` met een ondergrens
  // boven de bovengrens gooit een fout in plaats van een getal.
  final vrij = opzij * vak.width;
  links = links.clamp(math.min(vak.width - w, 0.0) - vrij, vrij).toDouble();
  boven = boven.clamp(math.min(vak.height - h, 0.0), 0.0).toDouble();
  return Rect.fromLTWH(links, boven, w, h);
}

/// Hoeveel van de breedte een foto die je zelf instelt opzij mag vrijlaten. Saber, 27-10-2026: "het moet
/// ook zijdelings verschoven kunnen worden" — zonder dat kon een liggende foto in een brede kop alleen op
/// en neer, want vullend is hij precies zo breed als de kop. Wat vrijkomt loopt zacht over in de
/// achtergrond ([zachteRanden]). Op en neer blijft hij vullend: daar zou vrijlaten lege ruimte zijn.
const double kOpzijVrij = .4;

/// [kind] met zachte zijranden: [links] en [rechts] zijn het deel van zijn breedte dat naar doorzichtig
/// loopt. Een masker en geen kleurverloop erover: de foto staat in een grijsfilter, en een verloop in de
/// kleur van de achtergrond werd daar grijs.
Widget zachteRanden(Widget kind, {required double links, required double rechts}) => ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) => LinearGradient(
        colors: const [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
        stops: [0, links.clamp(0.0, .5), 1 - rechts.clamp(0.0, .5), 1],
      ).createShader(r),
      child: kind,
    );

/// Hoe breed de zachte rand is aan een kant waar de foto niet tot de rand van het vak komt — 0 waar hij
/// dat wel doet. Als deel van de breedte van de foto, voor [zachteRanden].
({double links, double rechts}) randenVan(Rect plek, Size vak) {
  if (plek.width <= 0) return (links: 0, rechts: 0);
  final rand = (vak.width * .11).clamp(40.0, 160.0);
  return (
    links: plek.left > .5 ? rand / plek.width : 0,
    rechts: plek.right < vak.width - .5 ? rand / plek.width : 0,
  );
}

/// Het omgekeerde van [kopPlek]: welk punt van de foto er op [doel] staat als de foto op [plek]
/// ligt. Voor de bewerker — slepen verschuift de plek, en bewaard wordt het punt.
///
/// Opzij mag het punt buiten de foto liggen (zie [kOpzijVrij]): dan staat de foto naast de vaste plek.
Brandpunt puntOpDoel({required Size vak, required Rect plek, required Offset doel}) => Brandpunt(
      ((doel.dx * vak.width - plek.left) / plek.width).clamp(KopInstelling.kFxVanaf, KopInstelling.kFxTot),
      ((doel.dy * vak.height - plek.top) / plek.height).clamp(0.0, 1.0),
    );

/// Waar in de kop het brandpunt hoort, als deel van het vak onder [KopFoto.bovenRand].
///
/// Op een breed scherm rechts van de naam (die staat links, op het verloop) en in de bovenste helft
/// (onderaan wordt de foto donker voor de knoppen). Op een gsm in het midden en hoog: daar staat de
/// naam onder de foto, niet ernaast.
///
/// Hoog genoeg: het verloop dat de naam en de knoppen draagt is op 58 % van de kop al 86 % donker, dus
/// een gezicht dat daar staat, zie je nauwelijks. Eerst stond het doel op 40 % onder de balk (de helft
/// van de kop) en lagen de gezichten in het donker.
Offset kopDoel({required bool smal}) => smal ? const Offset(.5, .28) : const Offset(.68, .28);

/// Het doel van [kopDoel] binnen het hele vak, met [bovenRand] erboven (het stuk achter de balk).
Offset doelInVak(Offset doel, Size vak, double bovenRand) {
  if (!vak.isFinite || vak.height <= 0) return doel;
  final rand = bovenRand.clamp(0.0, vak.height * .5);
  return Offset(doel.dx, (rand + doel.dy * (vak.height - rand)) / vak.height);
}

/// Het stuk van de kop waar gezichten goed te zien zijn, als deel van het vak: onder de balk, boven
/// het donkere verloop onderaan, en op een breed scherm rechts van de naam.
Rect kopZicht({required bool smal, required Size vak, double bovenRand = 0}) {
  if (!vak.isFinite || vak.height <= 0) return const Rect.fromLTRB(0, 0, 1, 1);
  final boven = ((bovenRand + 6) / vak.height).clamp(0.0, .5);
  return smal ? Rect.fromLTRB(.04, boven, .96, .62) : Rect.fromLTRB(.40, boven, .98, .64);
}

/// Het vak om de gezichten heen dat in beeld moet blijven: met het haar erboven en de kin eronder.
Rect gezichtenMetRuimte(Rect g) => Rect.fromLTRB(
      (g.left - g.width * .08).clamp(0.0, 1.0),
      (g.top - g.height * .35).clamp(0.0, 1.0),
      (g.right + g.width * .08).clamp(0.0, 1.0),
      (g.bottom + g.height * .20).clamp(0.0, 1.0),
    );

/// De foto van de kop, op zijn plek: [instelling] als jij hem hebt ingesteld, anders de gevonden
/// gezichten (en zonder gezichten het gevonden brandpunt).
///
/// [bovenRand] is het stuk van het vak dat achter de zwevende balk ligt: de foto loopt daar door, maar
/// het brandpunt hoort eronder — een gezicht achter de tabbladen is geen goed uitgesneden kop.
class KopFoto extends StatelessWidget {
  const KopFoto({
    super.key,
    required this.beeld,
    required this.smal,
    this.bronMaat,
    this.instelling,
    this.bovenRand = 0,
    this.direct = false,
  });

  final Uint8List beeld;

  /// Gsm-vorm (naam onder de foto) of breed (naam links ernaast) — zie [kopDoel] en [kopZicht].
  final bool smal;

  /// De maat uit de kop van het bestand (`imageSize`), voor het eerste beeld. Daarna telt de maat
  /// van de gedecodeerde foto (zie [FotoBlik]).
  final Size? bronMaat;
  final KopInstelling? instelling;
  final double bovenRand;

  /// Zonder overgang — in de bewerker volgt de foto je vinger, niet een animatie.
  final bool direct;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return _MetBlik(
      beeld: beeld,
      builder: (blik) => LayoutBuilder(builder: (_, c) {
        final vak = c.biggest;
        final maat = blik?.maat ?? bronMaat;
        if (maat == null || !vak.isFinite || vak.isEmpty) {
          // Nog niets bekend: zoals de kop altijd was, tot de foto bekeken is.
          return Image.memory(beeld,
              fit: BoxFit.cover,
              alignment: const Alignment(0, -.35),
              cacheWidth: decodeerBreedte(vak.width.isFinite ? vak.width * dpr : 1920),
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox());
        }
        final plek = plekVoor(vak: vak, maat: maat, blik: blik, instelling: instelling, smal: smal, bovenRand: bovenRand);
        Widget foto = Image.memory(beeld,
            fit: BoxFit.fill,
            cacheWidth: decodeerBreedte(plek.width * dpr),
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const SizedBox());
        final randen = randenVan(plek, vak);
        if (randen.links > 0 || randen.rechts > 0) {
          foto = zachteRanden(foto, links: randen.links, rechts: randen.rechts);
        }
        return ClipRect(
          child: Stack(fit: StackFit.expand, children: [
            if (direct)
              Positioned.fromRect(rect: plek, child: foto)
            else
              // Een korte overgang als de foto bekeken is, in plaats van een sprong.
              AnimatedPositioned.fromRect(
                rect: plek,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: foto,
              ),
          ]),
        );
      }),
    );
  }

  /// Waar de foto in [vak] komt — één som voor de kop en de bewerker, zodat wat je instelt ook is wat
  /// je daarna ziet.
  static Rect plekVoor({
    required Size vak,
    required Size maat,
    required FotoBlik? blik,
    required KopInstelling? instelling,
    required bool smal,
    double bovenRand = 0,
  }) {
    final doel = doelInVak(kopDoel(smal: smal), vak, bovenRand);
    final i = instelling;
    if (i != null) {
      return kopPlek(vak: vak, beeld: maat, punt: Brandpunt(i.fx, i.fy), doel: doel, zoom: i.zoom, opzij: kOpzijVrij);
    }
    final g = blik?.gezichten;
    return kopPlek(
      vak: vak,
      beeld: maat,
      punt: blik?.punt ?? Brandpunt.midden,
      doel: doel,
      gezichten: g,
      zicht: g == null ? null : kopZicht(smal: smal, vak: vak, bovenRand: bovenRand),
    );
  }
}

/// Hoe breed een kopfoto gedecodeerd wordt: zo breed als hij getekend wordt (een staande foto over de
/// volle breedte is breder dan het venster), in stappen van 320 zodat zoomen niet bij elke stap
/// opnieuw decodeert, en tot 1920 — zie de uitleg bij [EditorialeKop] over Michael Jacksons 1920 brede
/// achtergrond. Groter dan de bron decodeert Flutter toch niet (`allowUpscaling` staat uit).
int decodeerBreedte(double px) => ((px / 320).ceil() * 320).clamp(320, 1920);

/// Bouwt opnieuw zodra de foto bekeken is. Klein en apart, zodat de kop zelf stateless blijft.
class _MetBlik extends StatefulWidget {
  const _MetBlik({required this.beeld, required this.builder});
  final Uint8List beeld;
  final Widget Function(FotoBlik? blik) builder;

  @override
  State<_MetBlik> createState() => _MetBlikState();
}

class _MetBlikState extends State<_MetBlik> {
  FotoBlik? _blik;

  @override
  void initState() {
    super.initState();
    _zoek();
  }

  @override
  void didUpdateWidget(_MetBlik oud) {
    super.didUpdateWidget(oud);
    if (!identical(oud.beeld, widget.beeld)) _zoek();
  }

  void _zoek() {
    _blik = bekendeBlik(widget.beeld);
    if (_blik != null) return;
    final beeld = widget.beeld;
    unawaited(bekijkFoto(beeld).then((b) {
      if (mounted && identical(beeld, widget.beeld) && b != null) setState(() => _blik = b);
    }));
  }

  @override
  Widget build(BuildContext context) => widget.builder(_blik);
}

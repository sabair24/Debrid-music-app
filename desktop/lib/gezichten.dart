/// Gezichten vinden in een foto — offline, zonder native code, op elk toestel hetzelfde.
///
/// **Waarom.** De kop van een artiestpagina snijdt een foto bij tot een brede band (op een tv
/// 960 × 435). Saber, 17-10-2026: "ook op de hero bij artist detail, wordt vaak afgekapt … vooral een
/// groep zoals Nsync of Backstreet Boys … het moet altijd automatisch fitten". Eerst is geprobeerd de
/// mensen op HUIDKLEUR te vinden; gemeten op 77 echte artiestfoto's ging dat te vaak mis: een oranje
/// muur, baksteen, rode ballen, een publiek en een goudkleurig jasje zijn ook huidkleurig. Een gezicht
/// herken je op VORM: twee donkere ogen boven een lichtere wang, een neusrug ertussen.
///
/// **Hoe.** De methode van Viola en Jones (2001): een raam van 24 × 24 schuift over de foto op steeds
/// kleinere schaal, en per plek beslist een reeks trappen van eenvoudige licht-donkerproeven of hier
/// een gezicht zit. Bijna elk raam valt al in de eerste trap af (negen proeven), dus dit is snel. Het
/// getrainde model is dat van OpenCV (`haarcascade_frontalface_default.xml`, Rainer Lienhart, Intel
/// License — zie `gezichtsmodel.dart`), omgezet naar een blok van 76 KB.
///
/// **Wat het niet kan.** Alleen gezichten van voren (tot ongeveer 30° gedraaid). Een profiel, een
/// hoofd dat naar beneden kijkt of een gezicht achter een zonnebril valt vaak af — daarvoor staat in
/// `ui/kopfoto.dart` een terugval op huid en detail.
///
/// Zuiver en zonder Flutter, zodat het in een `Isolate.run` kan (op een Shield is dat het verschil
/// tussen een vloeiende pagina en een hapering) en in een toets zonder widgetboom.
library;

import 'dart:convert' show base64Decode;
import 'dart:math' as math;
import 'dart:typed_data';

import 'gezichtsmodel.dart';

/// Een gevonden gezicht, in punten van de grijze afbeelding die [vindGezichten] kreeg.
class Gezicht {
  const Gezicht(this.links, this.boven, this.breedte, this.hoogte, this.buren);
  final double links, boven, breedte, hoogte;

  /// Hoeveel ramen op ongeveer deze plek een gezicht zagen. Een echt gezicht wordt op een paar schalen
  /// en verschuivingen gevonden; een toevalstreffer in een baksteenmuur zelden meer dan één of twee keer.
  final int buren;

  double get rechts => links + breedte;
  double get onder => boven + hoogte;

  @override
  String toString() =>
      'Gezicht(${links.round()},${boven.round()} ${breedte.round()}×${hoogte.round()}, $buren buren)';
}

/// Het model, gelezen uit het blok in `gezichtsmodel.dart`.
///
/// Indeling (little-endian): 'HAAR', breedte en hoogte van het raam (u16, u16), het aantal trappen
/// (u16), per trap de drempel (f32) en het aantal beslissers (u16), per beslisser het kenmerk (u16),
/// de drempel (f32) en de twee bladwaarden (f32, f32); daarna het aantal kenmerken (u16) en per
/// kenmerk het aantal vakken (u8) met per vak x, y, breedte, hoogte (u8) en gewicht (i8).
class Gezichtsmodel {
  Gezichtsmodel._(this.raam, this._trapDrempel, this._trapEinde, this._kenmerk, this._drempel,
      this._links, this._rechts, this._vakBegin, this._vakken);

  final int raam;
  final Float32List _trapDrempel;
  final Int32List _trapEinde; // index na de laatste beslisser van elke trap
  final Uint16List _kenmerk;
  final Float32List _drempel, _links, _rechts;
  final Int32List _vakBegin; // per kenmerk: waar zijn vakken beginnen in [_vakken] (en het volgende eindigt)
  final Int32List _vakken; // x, y, b, h, gewicht

  static Gezichtsmodel? _standaard;

  /// Het frontale model van OpenCV, één keer gelezen (per isolate).
  static Gezichtsmodel get standaard => _standaard ??= lees(base64Decode(kGezichtsmodel));

  static Gezichtsmodel lees(Uint8List blok) {
    final d = ByteData.sublistView(blok);
    if (String.fromCharCodes(blok, 0, 4) != 'HAAR') throw const FormatException('geen gezichtsmodel');
    var o = 4;
    final raam = d.getUint16(o, Endian.little);
    o += 4;
    final trappen = d.getUint16(o, Endian.little);
    o += 2;
    final trapDrempel = Float32List(trappen);
    final trapEinde = Int32List(trappen);
    final kenmerk = <int>[], drempel = <double>[], links = <double>[], rechts = <double>[];
    for (var t = 0; t < trappen; t++) {
      trapDrempel[t] = d.getFloat32(o, Endian.little);
      final n = d.getUint16(o + 4, Endian.little);
      o += 6;
      for (var i = 0; i < n; i++) {
        kenmerk.add(d.getUint16(o, Endian.little));
        drempel.add(d.getFloat32(o + 2, Endian.little));
        links.add(d.getFloat32(o + 6, Endian.little));
        rechts.add(d.getFloat32(o + 10, Endian.little));
        o += 14;
      }
      trapEinde[t] = kenmerk.length;
    }
    final kenmerken = d.getUint16(o, Endian.little);
    o += 2;
    final vakBegin = Int32List(kenmerken + 1);
    final vakken = <int>[];
    for (var k = 0; k < kenmerken; k++) {
      vakBegin[k] = vakken.length;
      final n = blok[o++];
      for (var i = 0; i < n; i++) {
        vakken
          ..add(blok[o])
          ..add(blok[o + 1])
          ..add(blok[o + 2])
          ..add(blok[o + 3])
          ..add(d.getInt8(o + 4));
        o += 5;
      }
    }
    vakBegin[kenmerken] = vakken.length;
    return Gezichtsmodel._(raam, trapDrempel, trapEinde, Uint16List.fromList(kenmerk), Float32List.fromList(drempel),
        Float32List.fromList(links), Float32List.fromList(rechts), vakBegin, Int32List.fromList(vakken));
  }
}

/// De gezichten in een grijze afbeelding van [breed] × [hoog] (één byte per punt).
///
/// [schaalStap] en [minBuren] zijn die van OpenCV's `detectMultiScale` (1,1 en 3); hier 1,15 en 3,
/// omdat het om de plek van de groep gaat en niet om elk gezicht in een menigte. [kleinste] is de
/// kleinste gezichtsbreedte in punten van deze afbeelding.
List<Gezicht> vindGezichten(
  Uint8List grijs,
  int breed,
  int hoog, {
  Gezichtsmodel? model,
  double schaalStap = 1.15,
  int minBuren = 3,
}) {
  final m = model ?? Gezichtsmodel.standaard;
  final r = m.raam;
  if (breed < r || hoog < r || grijs.length < breed * hoog) return const [];
  final kandidaten = <List<double>>[];
  for (var schaal = 1.0;; schaal *= schaalStap) {
    final b = (breed / schaal).floor(), h = (hoog / schaal).floor();
    if (b < r || h < r) break;
    final beeld = schaal == 1.0 ? grijs : _verklein(grijs, breed, hoog, b, h);
    final som = Int32List((b + 1) * (h + 1));
    final kwadraat = Float64List((b + 1) * (h + 1));
    for (var y = 0; y < h; y++) {
      var rij = 0, rijK = 0.0;
      for (var x = 0; x < b; x++) {
        final v = beeld[y * b + x];
        rij += v;
        rijK += v * v;
        final i = (y + 1) * (b + 1) + x + 1;
        som[i] = som[i - b - 1] + rij;
        kwadraat[i] = kwadraat[i - b - 1] + rijK;
      }
    }
    final w = b + 1;
    // Stap 2 op de fijne schalen en 1 op de grove, zoals OpenCV.
    final stap = schaal > 2 ? 1 : 2;
    const binnen = 22; // het normvak: het raam min één punt rondom
    for (var y = 0; y + r <= h; y += stap) {
      for (var x = 0; x + r <= b; x += stap) {
        // Licht en contrast van dit raam, zodat een donkere en een lichte foto hetzelfde antwoord geven.
        final a = (y + 1) * w + x + 1, e = (y + 1 + binnen) * w + x + 1 + binnen;
        final s = som[e] - som[a + binnen] - som[e - binnen] + som[a];
        final q = kwadraat[e] - kwadraat[a + binnen] - kwadraat[e - binnen] + kwadraat[a];
        var norm = binnen * binnen * q - s.toDouble() * s;
        norm = norm > 0 ? math.sqrt(norm) : 1;
        if (_isGezicht(m, som, w, x, y, 1 / norm)) {
          kandidaten.add([x * schaal, y * schaal, r * schaal, r * schaal]);
        }
      }
    }
  }
  return _groepeer(kandidaten, minBuren);
}

bool _isGezicht(Gezichtsmodel m, Int32List som, int w, int x, int y, double inv) {
  var begin = 0;
  for (var t = 0; t < m._trapDrempel.length; t++) {
    final einde = m._trapEinde[t];
    var totaal = 0.0;
    for (var i = begin; i < einde; i++) {
      final k = m._kenmerk[i];
      var waarde = 0;
      for (var v = m._vakBegin[k]; v < m._vakBegin[k + 1]; v += 5) {
        final vx = x + m._vakken[v], vy = y + m._vakken[v + 1];
        final vb = m._vakken[v + 2], vh = m._vakken[v + 3];
        final a = vy * w + vx, e = (vy + vh) * w + vx + vb;
        waarde += m._vakken[v + 4] * (som[e] - som[a + vb] - som[e - vb] + som[a]);
      }
      totaal += waarde * inv < m._drempel[i] ? m._links[i] : m._rechts[i];
    }
    if (totaal < m._trapDrempel[t]) return false;
    begin = einde;
  }
  return true;
}

/// Verkleinen door te middelen over het vak dat elk nieuw punt dekt (zoals `INTER_AREA`).
Uint8List _verklein(Uint8List bron, int bb, int bh, int nb, int nh) {
  final uit = Uint8List(nb * nh);
  final sx = bb / nb, sy = bh / nh;
  for (var y = 0; y < nh; y++) {
    final y0 = (y * sy).floor(), y1 = math.max(y0 + 1, ((y + 1) * sy).floor()).clamp(1, bh);
    for (var x = 0; x < nb; x++) {
      final x0 = (x * sx).floor(), x1 = math.max(x0 + 1, ((x + 1) * sx).floor()).clamp(1, bb);
      var t = 0;
      for (var yy = y0; yy < y1; yy++) {
        for (var xx = x0; xx < x1; xx++) {
          t += bron[yy * bb + xx];
        }
      }
      uit[y * nb + x] = t ~/ ((y1 - y0) * (x1 - x0));
    }
  }
  return uit;
}

/// OpenCV's `groupRectangles` (eps 0,2): ramen die bijna samenvallen worden één gezicht, en alleen
/// wat door meer dan [minBuren] ramen gezien is telt. Daarna valt een klein gezicht binnen een groter
/// weg — dat is een oog of een mond die zelf ook op een gezicht leek.
List<Gezicht> _groepeer(List<List<double>> r, int minBuren) {
  final n = r.length;
  final ouder = List<int>.generate(n, (i) => i);
  int wortel(int i) {
    while (ouder[i] != i) {
      ouder[i] = ouder[ouder[i]];
      i = ouder[i];
    }
    return i;
  }

  bool lijkt(List<double> a, List<double> b) {
    final delta = .2 * (math.min(a[2], b[2]) + math.min(a[3], b[3])) * .5;
    return (a[0] - b[0]).abs() <= delta &&
        (a[1] - b[1]).abs() <= delta &&
        (a[0] + a[2] - b[0] - b[2]).abs() <= delta &&
        (a[1] + a[3] - b[1] - b[3]).abs() <= delta;
  }

  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      if (lijkt(r[i], r[j])) {
        final a = wortel(i), b = wortel(j);
        if (a != b) ouder[a] = b;
      }
    }
  }
  final groepen = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    groepen.putIfAbsent(wortel(i), () => []).add(i);
  }
  final gezichten = <Gezicht>[];
  for (final g in groepen.values) {
    if (g.length <= minBuren) continue;
    var x = 0.0, y = 0.0, b = 0.0, h = 0.0;
    for (final i in g) {
      x += r[i][0];
      y += r[i][1];
      b += r[i][2];
      h += r[i][3];
    }
    gezichten.add(Gezicht(x / g.length, y / g.length, b / g.length, h / g.length, g.length));
  }
  // Een gezicht dat binnen een groter ligt, en minder gezien is: weg.
  return [
    for (final a in gezichten)
      if (!gezichten.any((b) =>
          !identical(a, b) &&
          b.breedte > a.breedte * 1.2 &&
          a.links >= b.links - b.breedte * .1 &&
          a.rechts <= b.rechts + b.breedte * .1 &&
          a.boven >= b.boven - b.hoogte * .1 &&
          a.onder <= b.onder + b.hoogte * .1 &&
          b.buren >= a.buren * .5))
        a,
  ];
}

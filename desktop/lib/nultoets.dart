/// De nultoets: draagt een 24-bitkopie méér dan je 16-bitkopie van hetzelfde nummer, of is ze je cd in een groter jasje?
///
/// **Waarom dit bestaat.** Saber, 27-10-2026: *"volgens bronnen zou het album D'Eux van Céline Dion nooit in high res
/// uitgekomen zijn, enkel cd, toch staan er liedjes bij van 24bit"*. Zijn bronnen klopten. Sinds 23-10-2026 wint een
/// kopie met meer dan 16 bits in gebruik van een cd (keuring.dart, "de bits als scheidsrechter") — maar dat bewijst
/// niets: elke bewerking vult de lage bits. Gemeten die dag, tegen zijn eigen cd:
///
/// * D'Eux 01 was zijn cd, 0,83 dB stiller gezet en als 24 bit bewaard;
/// * Destin lag precies 1024 monsters achter zijn cd: de voorloop van een aac-encoder, een gedecodeerde stream (met een
///   Spotify-link in de tags);
/// * Like Glue en Get Busy (Sean Paul) lagen precies 2112 monsters achter: de voorloop van iTunes-aac.
///
/// Alle drie wonnen ze als "24 bit" en duwden ze de cd opzij.
///
/// **De toets.** Schuif de 24-bitkopie tegen je 16-bitkopie tot ze samenvallen ([verschuivingVan]), reken de
/// versterking terug, trek af, en meet wat er overblijft ([nulpuntOp]) — relatief tot de muziek en absoluut (dBFS).
/// Gemeten op 72 paren 24/44,1 tegen 16/44,1 in Sabers bibliotheek:
///
/// * **De echte bron** (TIDAL HIRES tegen TIDAL LOSSLESS, en 24 andere): ergens een nul van −76 tot −94 dB, en wat
///   overblijft ligt op −83 tot −101 dBFS — precies de ruis van afronden tot 16 bit. Je cd ÍS deze kopie, afgerond;
///   de 24 bits zijn dus echt méér. Versterking 0,0 of 0,2 dB.
/// * **Bewerkt** (D'Eux 01, Mart Hoogkamer — Ik Ga Zwemmen): dezelfde master tot −71/−75 dB, maar 0,8 dB in volume
///   verzet. Niet méér dan je cd.
/// * **Lossy**: precies 1024 of 2112 monsters achter je cd, met een grote rest (−17 tot −36 dB).
/// * **Anders**: een andere master, een andere mix, een opname die uit de pas loopt — rest boven −50 dB.
///
/// En Pijnstiller (Suzan & Freek) leerde dat het BESTE punt telt, niet het gemiddelde: in de stille stukken was de cd tot
/// op −96 dBFS de 24-bitkopie, in de luide stukken week hij 24 dB af — daar is de cd begrensd. Dat is een echte master
/// met een cd die ervan gemaakt is, en geen bewerkte cd.
///
/// Puur en zonder `dart:io`: het decoderen en onthouden staat in `nultoets_meter.dart`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'fft.dart';

/// Wat de nultoets over een 24-bitkopie zegt, tegenover een 16-bitkopie van hetzelfde nummer.
enum Nuluitkomst {
  /// Je 16-bitkopie is deze kopie, afgerond tot 16 bit: wat overblijft is de ruis van dat afronden. De bits zijn echt
  /// méér — alleen dan telt de diepte (keuring.dart).
  bron,

  /// Dezelfde master, maar verzet in volume of door iets gehaald: je cd, bewerkt. Niet méér dan je cd.
  bewerkt,

  /// Precies [kVoorloop] monsters achter je cd: een gedecodeerde stream.
  lossy,

  /// Een andere master of mix, of een opname die uit de pas loopt: niets bewezen.
  anders,
}

/// Wat er op één plek in het nummer overbleef. [verschuiving]: zoveel monsters valt de kopie later dan je cd (negatief:
/// ze heeft er vooraan zoveel meer). [restDb]: wat overblijft tegenover de muziek, [restDbfs]: absoluut.
typedef Nulpunt = ({int verschuiving, double versterkingDb, double restDb, double restDbfs});

/// Het volle oordeel, met de punten waarop het rust (voor het logboek).
typedef Nuloordeel = ({Nuluitkomst uitkomst, List<Nulpunt> punten});

/// Onder deze rest (ergens in het nummer) is het dezelfde master. Een andere master of mix bleef boven −38 dB.
const double kZelfdeMaster = -50;

/// Onder deze rest is de nul diep genoeg om een bron te heten. Lossy komt daar nergens: zijn ruis ligt 17 tot 36 dB
/// onder de muziek. De echte bronnen gaven −76 tot −94.
const double kDiepeNul = -70;

/// Het venster van de 16-bitvloer: de ruis van afronden tot 16 bit (gemeten −83 tot −101 dBFS, met en zonder
/// ruisvorming). Lager is je cd met wat 24-bitruis erbij — niets wat je cd niet had.
const double kVloerVan = -104, kVloerTot = -80;

/// Zoveel mag de versterking schelen voor een bron: TIDAL LOSSLESS ligt 0,2 dB onder HIRES. D'Eux 01 en Ik Ga Zwemmen
/// waren 0,8 dB verzet.
const double kMaxVerzet = 0.3;

/// De voorloop van een aac-encoder, in monsters op 44,1 kHz: 1024 (Destin, Le Ballet) en 2112 bij iTunes (Like Glue,
/// Get Busy).
const List<int> kVoorloop = [1024, 2112];

/// Waaronder een stuk te stil is om iets over te zeggen (dBFS).
const double kTeStil = -50;

/// Bemonstering waarop gemeten wordt (ffmpeg zet alles om).
const int kNulRate = 44100;

/// Lengte van het stuk dat vergeleken wordt, en hoe ver er geschoven mag worden (seconden).
const int kStukSeconden = 6, kZoekSeconden = 5;

/// Waar in een nummer van [seconden] gemeten wordt: drie plekken, verspreid, met ruimte om te schuiven.
List<int> meetplekken(double seconden) {
  final marge = kStukSeconden + kZoekSeconden + 1;
  final vast = [40, 100, 150].where((t) => t + marge <= seconden).toList();
  if (vast.length >= 3) return vast;
  return [
    for (final f in const [0.2, 0.45, 0.7])
      if (seconden * f >= kZoekSeconden && seconden * f + marge <= seconden) (seconden * f).floor(),
  ];
}

/// Hoeveel monsters [b] (je cd) verschoven ligt tegenover [a] (de kopie) rond monster [start]: `b[start + i + v] ≈
/// a[start + i]`. Via kruiscorrelatie, met de grootste piek in absolute waarde (een omgekeerde fase telt ook).
int verschuivingVan(Float32List a, Float32List b, int start) {
  const stuk = kStukSeconden * kNulRate, zoek = kZoekSeconden * kNulRate;
  var n = 1;
  while (n < stuk + 2 * zoek + stuk) {
    n <<= 1;
  }
  final re1 = Float64List(n), im1 = Float64List(n), re2 = Float64List(n), im2 = Float64List(n);
  for (var i = 0; i < stuk; i++) {
    final j = start + i;
    re1[i] = j < a.length ? a[j] : 0;
  }
  for (var i = 0; i < stuk + 2 * zoek; i++) {
    final j = start - zoek + i;
    re2[i] = j >= 0 && j < b.length ? b[j] : 0;
  }
  fft(re1, im1);
  fft(re2, im2);
  // B · conj(A), en terug via de FFT van het complex toegevoegde: het reële deel is de correlatie (maal n).
  for (var i = 0; i < n; i++) {
    final r = re2[i] * re1[i] + im2[i] * im1[i];
    final m = im2[i] * re1[i] - re2[i] * im1[i];
    re2[i] = r;
    im2[i] = -m;
  }
  fft(re2, im2);
  var beste = 0.0, bi = 0;
  for (var i = 0; i <= 2 * zoek; i++) {
    final w = re2[i].abs();
    if (w > beste) {
      beste = w;
      bi = i;
    }
  }
  return bi - zoek;
}

/// Wat er overblijft van [a] min `g·b` rond monster [start], bij verschuiving [v], met de beste versterking `g`. Null als
/// het stuk te stil is of buiten [b] valt.
Nulpunt? nulpuntOp(Float32List a, Float32List b, int start, int v) {
  const stuk = kStukSeconden * kNulRate;
  if (start < 0 || start + stuk > a.length || start + v < 0 || start + v + stuk > b.length) return null;
  var ab = 0.0, bb = 0.0, aa = 0.0;
  for (var i = 0; i < stuk; i++) {
    final x = a[start + i], y = b[start + i + v];
    ab += x * y;
    bb += y * y;
    aa += x * x;
  }
  if (bb <= 0 || aa <= 0) return null;
  final muziek = 10 * math.log(aa / stuk) / math.ln10;
  if (muziek < kTeStil) return null;
  final g = ab / bb;
  var rr = 0.0;
  for (var i = 0; i < stuk; i++) {
    final d = a[start + i] - g * b[start + i + v];
    rr += d * d;
  }
  double db(double x) => x <= 0 ? double.negativeInfinity : 10 * math.log(x) / math.ln10;
  return (
    verschuiving: v,
    versterkingDb: g == 0 ? double.negativeInfinity : 20 * math.log(g.abs()) / math.ln10,
    restDb: db(rr / aa),
    restDbfs: db(rr / stuk),
  );
}

/// De nultoets op de monsters zelf: [kandidaat] (de 24-bitkopie) tegen [cd], beide mono op [kNulRate], op [plekken]
/// (in seconden). Null als er geen twee plekken te meten waren.
///
/// Per plek eerst de verschuiving; dan, omdat één plek zich kan vergissen in een herhalend stuk (D'Eux 01 op 30 s: 206
/// monsters ernaast), de verschuiving die op ALLE plekken het best past — met één monster speling.
Nuloordeel? nultoetsOp(Float32List kandidaat, Float32List cd, List<int> plekken) {
  final starts = [for (final t in plekken) t * kNulRate];
  final kandidaten = <int>{for (final s in starts) verschuivingVan(kandidaat, cd, s)};
  List<Nulpunt>? beste;
  double besteScore = double.infinity;
  for (final v in kandidaten) {
    final punten = <Nulpunt>[];
    for (final s in starts) {
      Nulpunt? p;
      for (final d in const [-1, 0, 1]) {
        final q = nulpuntOp(kandidaat, cd, s, v + d);
        if (q != null && (p == null || q.restDb < p.restDb)) p = q;
      }
      if (p != null) punten.add(p);
    }
    if (punten.length < 2) continue;
    final score = _mediaan([for (final p in punten) p.restDb]);
    if (score < besteScore) {
      besteScore = score;
      beste = punten;
    }
  }
  if (beste == null) return null;
  return (uitkomst: nuluitkomst(beste), punten: beste);
}

/// Het oordeel uit de punten (zie de inleiding van dit bestand voor de ijking).
Nuluitkomst nuluitkomst(List<Nulpunt> punten) {
  if (punten.isEmpty) return Nuluitkomst.anders;
  var diepste = punten.first;
  for (final p in punten) {
    if (p.restDb < diepste.restDb) diepste = p;
  }
  final verzet = _mediaan([for (final p in punten) p.versterkingDb]).abs();
  if (diepste.restDb < kZelfdeMaster) {
    final opDeVloer = diepste.restDbfs >= kVloerVan && diepste.restDbfs <= kVloerTot;
    return diepste.restDb < kDiepeNul && opDeVloer && verzet <= kMaxVerzet ? Nuluitkomst.bron : Nuluitkomst.bewerkt;
  }
  final v = _mediaan([for (final p in punten) p.verschuiving.toDouble()]).round();
  if (kVoorloop.contains(-v)) return Nuluitkomst.lossy;
  return Nuluitkomst.anders;
}

// ── Over bemonsteringen heen (25-11-2026) ──
//
// Saber, 25-11-2026, bij Modjo "Lady (Hear Me Tonight)" ("FLAC · 24/48 · studio"): *"of het 100 procent klopt ?"*. Het
// was zijn cd — tot op het monster gelijk in de tijd, op 0,00 dB — door een codec gehaald en als 24/48 bewaard: per
// lijn een rest van −18 dB (0,25–1 kHz) tot −10 dB (4–12 kHz), boven 16 kHz alleen nog ruis met dezelfde sterkte, en een
// muur op 20,0 kHz waar zijn cd doorliep tot 22 kHz. De nultoets mat het niet: hij weigerde een andere bemonstering
// ("het omzetten zelf laat een rest achter"). De bibliotheek gaf er die dag nog drie: Destiny's Child "Girl", Jennifer
// Lopez "Do It Well" en "I'm Real" — dezelfde muur op 20,0–20,1 kHz (Opus kapt op 20 kHz en decodeert op 48 kHz).
//
// Over bemonsteringen heen zegt de toets daarom NOOIT bron of bewerkt — een echte 24/48 en de cd die ervan gemaakt is
// mogen in volume schelen (Céline Dion "Bonjour, Pardon, Merci": 0,6 dB, verder tot op −69 dB gelijk) —, alleen lossy of
// anders. Lossy vraagt alles tegelijk ([isCodecOverRates]).

/// De banden van [samenhangPerBand]: 60–250, 250–1000, 1000–4000 en 4000–8000 Hz.
const List<(double, double)> kSamenhangBanden = [(60, 250), (250, 1000), (1000, 4000), (4000, 8000)];

/// Wat de samenhang per lijn tussen kandidaat en cd zegt: per band van [kSamenhangBanden] de verhouding signaal/rest
/// (dB, uit het gemiddelde van γ² over de lijnen) en de energie van de kandidaat tegenover de cd (dB); en hoeveel er
/// tussen 20,5 en 21,5 kHz zit tegenover 1–5 kHz, bij elk van de twee (dB).
typedef Samenhang = ({List<double> snrDb, List<double> verhoudingDb, double hoogKandidaat, double hoogCd});

/// Codecvingerafdruk: hoogstens zoveel signaal/rest tussen 1 en 4 kHz. Modjo 15, Girl 16, Do It Well 15, I'm Real 15;
/// echte paren 26 en meer (Confessions 40, Céline Dion: geen rest te meten).
const double kCodecSnrHoogstens = 24;

/// En het laag zoveel beter dan 1–4 kHz: codecruis groeit naar boven toe (Modjo 26 tegen 15, Do It Well 21 tegen 15).
const double kCodecLaagBeter = 2;

/// Zoveel mag een hogere band beter zijn dan de band eronder (dB): codecruis groeit naar boven toe.
const double kCodecStijgtNiet = 3;

/// Zoveel mag de energie per band (250 Hz–8 kHz) schelen: een codec houdt de energie, een andere mastering niet.
const double kCodecVlakDb = 0.5;

/// Zoveel minder tussen 20,5 en 21,5 kHz dan je cd: de kandidaat is de smalle, niet je cd (Modjo 30, Girl 31, Do It
/// Well 18, I'm Real 22 dB).
const double kCodecSmallerDb = 6;

/// De samenhang per lijn tussen [kandidaat] en [cd] (beide mono op [kNulRate]) over de [plekken] (seconden), bij
/// verschuiving [v] (`cd[i + v] ≈ kandidaat[i]`). Vensters van 4096 met Hann, om de 2048.
Samenhang samenhangPerBand(Float32List kandidaat, Float32List cd, List<int> plekken, int v) {
  const n = 4096, k2 = n ~/ 2, stuk = kStukSeconden * kNulRate;
  final hann = Float64List(n);
  for (var i = 0; i < n; i++) {
    hann[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
  }
  final sxx = Float64List(k2), syy = Float64List(k2), sr = Float64List(k2), si = Float64List(k2);
  final xr = Float64List(n), xi = Float64List(n), yr = Float64List(n), yi = Float64List(n);
  for (final t in plekken) {
    final start = t * kNulRate;
    for (var s = start; s + n <= start + stuk; s += n ~/ 2) {
      if (s < 0 || s + n > kandidaat.length || s + v < 0 || s + v + n > cd.length) continue;
      for (var i = 0; i < n; i++) {
        xr[i] = cd[s + v + i] * hann[i];
        yr[i] = kandidaat[s + i] * hann[i];
        xi[i] = 0;
        yi[i] = 0;
      }
      fft(xr, xi);
      fft(yr, yi);
      for (var k = 1; k < k2; k++) {
        sxx[k] += xr[k] * xr[k] + xi[k] * xi[k];
        syy[k] += yr[k] * yr[k] + yi[k] * yi[k];
        sr[k] += yr[k] * xr[k] + yi[k] * xi[k];
        si[k] += yi[k] * xr[k] - yr[k] * xi[k];
      }
    }
  }
  double db(double x) => x <= 0 ? -300 : 10 * math.log(x) / math.ln10;
  final hz = kNulRate / n;
  final snr = <double>[], verh = <double>[];
  for (final (lo, hi) in kSamenhangBanden) {
    var som = 0.0, aantal = 0, ex = 0.0, ey = 0.0;
    for (var k = (lo / hz).ceil(); k * hz < hi; k++) {
      ex += sxx[k];
      ey += syy[k];
      if (sxx[k] <= 0 || syy[k] <= 0) continue;
      som += (sr[k] * sr[k] + si[k] * si[k]) / (sxx[k] * syy[k]);
      aantal++;
    }
    final c = aantal == 0 ? 0.0 : som / aantal;
    snr.add(c >= 1 ? 90 : db(c / (1 - c)));
    verh.add(db(ey) - db(ex));
  }
  double band(Float64List s, double lo, double hi) {
    var e = 0.0;
    for (var k = (lo / hz).ceil(); k * hz < hi; k++) {
      e += s[k];
    }
    return e;
  }

  return (
    snrDb: snr,
    verhoudingDb: verh,
    hoogKandidaat: db(band(syy, 20500, 21500)) - db(band(syy, 1000, 5000)),
    hoogCd: db(band(sxx, 20500, 21500)) - db(band(sxx, 1000, 5000)),
  );
}

/// De codecvingerafdruk over bemonsteringen heen: zelfde volume ([kMaxVerzet]), zelfde energie per band
/// ([kCodecVlakDb]), maar tussen 1 en 4 kHz een rest die een verliesvrije omzetting nooit laat ([kCodecSnrHoogstens]),
/// beter in het laag ([kCodecLaagBeter]), en de kandidaat smaller dan je cd ([kCodecSmallerDb]).
bool isCodecOverRates(Samenhang s, {required double verzetDb}) =>
    verzetDb.abs() <= kMaxVerzet &&
    [for (var i = 1; i < s.verhoudingDb.length; i++) s.verhoudingDb[i]].every((d) => d.abs() <= kCodecVlakDb) &&
    s.snrDb[2] <= kCodecSnrHoogstens &&
    s.snrDb[0] >= s.snrDb[2] + kCodecLaagBeter &&
    // En nergens terug omhoog: codecruis groeit naar boven toe. Een andere zangopname (clean tegenover explicit: Hozier
    // "Too Sweet", Sabrina Carpenter "Taste") wijkt alleen in de zangbanden af en is daarboven weer gelijk (90 dB).
    s.snrDb[1] <= s.snrDb[0] + kCodecStijgtNiet &&
    s.snrDb[2] <= s.snrDb[1] + kCodecStijgtNiet &&
    s.snrDb[3] <= s.snrDb[2] + kCodecStijgtNiet &&
    s.hoogCd - s.hoogKandidaat >= kCodecSmallerDb;

/// De nultoets over bemonsteringen heen: [kandidaat] (bv. 24/48) tegen [cd], beide al met soxr naar [kNulRate] gerekend.
/// Alleen [Nuluitkomst.lossy] ([isCodecOverRates]) of [Nuluitkomst.anders] — nooit bron of bewerkt.
Nuloordeel? nultoetsOverRates(Float32List kandidaat, Float32List cd, List<int> plekken) {
  final basis = nultoetsOp(kandidaat, cd, plekken);
  if (basis == null) return null;
  final v = _mediaan([for (final p in basis.punten) p.verschuiving.toDouble()]).round();
  final verzet = _mediaan([for (final p in basis.punten) p.versterkingDb]);
  final s = samenhangPerBand(kandidaat, cd, plekken, v);
  final lossy = isCodecOverRates(s, verzetDb: verzet);
  return (uitkomst: lossy ? Nuluitkomst.lossy : Nuluitkomst.anders, punten: basis.punten);
}

double _mediaan(List<double> x) {
  final s = [...x]..sort();
  return s[s.length ~/ 2];
}

/// Eén regel voor het logboek: "dezelfde master tot −71 dB, 0,8 dB verzet" en zo.
String nulZin(Nuloordeel o) {
  String getal(double x, [int d = 0]) => x.isInfinite ? '−∞' : x.toStringAsFixed(d).replaceAll('.', ',').replaceAll('-', '−');
  var diepste = o.punten.first;
  for (final p in o.punten) {
    if (p.restDb < diepste.restDb) diepste = p;
  }
  final verzet = _mediaan([for (final p in o.punten) p.versterkingDb]);
  return switch (o.uitkomst) {
    Nuluitkomst.bron => 'je cd is deze kopie, afgerond tot 16 bit (rest ${getal(diepste.restDbfs)} dBFS) — echte 24 bit',
    Nuluitkomst.bewerkt =>
      'je cd, bewerkt: dezelfde master tot ${getal(diepste.restDb)} dB, ${getal(verzet.abs(), 1)} dB in volume verzet — '
          'niet méér dan je cd',
    Nuluitkomst.lossy => kVoorloop.contains(-diepste.verschuiving)
        ? 'precies ${-diepste.verschuiving} monsters achter je cd: een gedecodeerde stream'
        : 'zelfde opname, volume en timing als je cd, maar door een codec gehaald — een muur rond 20 kHz waar je cd '
            'doorloopt: een gedecodeerde stream',
    Nuluitkomst.anders => 'een andere master of mix (rest ${getal(diepste.restDb)} dB) — niets bewezen',
  };
}

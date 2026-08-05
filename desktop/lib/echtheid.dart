/// Is dit bestand écht wat het beweert te zijn?
///
/// Saber: "hoe weet ik dat een FLAC echt een FLAC is en niet een mp3 die naar FLAC is omgezet? Hoe weet
/// ik dat ik echt lossless of hi-res binnenhaal?" Tot nu toe wist de app dat niet: [isHiRes] gelooft de
/// FLAC-kop, of bij een zoekresultaat wat een wildvreemde peer meldt, onvoorwaardelijk — en geeft daar
/// een gouden badge voor.
///
/// DRIE PROEVEN, en het scheiden ervan is de belangrijkste keuze in dit bestand:
///
///   A  bitdiepte     zijn de onderste acht bits ooit gebruikt?    tegenspraak
///   B  bovenband     staat er iets boven 22,05 kHz?               zo goed als tegenspraak
///   C  bandbreedte   staat er een muur in het spectrum?           statistisch
///
/// A en B beantwoorden "is dit hi-res", C beantwoordt "is dit een transcode". **Alleen C kan vals alarm
/// geven.** Door ze uit elkaar te houden zit het hele risico in één van de drie, en blijven de andere
/// twee hard.
///
/// A BEWIJST ALLEEN HET NEGATIEVE. Zijn de onderste acht bits in een half miljoen samples nooit gebruikt,
/// dan is de inhoud met zekerheid niet meer dan zestien bit. Zijn ze wél gebruikt, dan bewijst dat
/// niets — een omzetting van 16 naar 24 mét dither vult ze ook. De uitslag heet daarom
/// [Bitdiepte.spreektNietTegen] en nooit "echt 24 bits".
///
/// WAAROM B ERBIJ MOET, terwijl de vraag er niet naar vroeg: een 16/44,1 die met een resampler naar
/// 24/96 is getild heeft wél volle onderste bits — interpolatie vult ze. Proef A mist hem dus volledig.
/// Maar boven 22,05 kHz is hij absoluut leeg, terwijl een echte 96 kHz-opname daar altijd iets heeft:
/// microfoonruis, omzetterruis. Zonder B ontsnapt precies de meest voorkomende soort nep-hi-res.
///
/// Puur en zonder `dart:io`, zodat alles hieronder met verzonnen spectra te toetsen is. Het draaien van
/// ffmpeg staat in `echtheid_meter.dart`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'fft.dart';

// ── De drempels ────────────────────────────────────────────────────────────
// Elk getal met de redenering erboven, zoals `sameRecordingScore` in fingerprint.dart. Ze zijn
// beredeneerd en daarna aan de echte bibliotheek getoetst met tool/echtheid_proef.dart.

/// Hoe steil de val moet zijn om een MUUR te heten, gemeten over 1,5 kHz.
///
/// 35 dB over 1,5 kHz is ruim 23 dB/kHz. Geen akoestische of analoge oorzaak haalt dat in dit gebied:
/// een derde-orde analoog filter op 15 kHz geeft 18 dB per octaaf, dus ongeveer 1,2 dB/kHz tussen 15 en
/// 30 kHz, en tapebandruis rolt af met enkele dB's per kHz. Alleen een digitaal filter valt zo. Onder
/// deze drempel is het antwoord GEEN oordeel, hoe laag de afkap ook ligt.
const double wandDrempelDb = 35;
const double wandSpan = 1500, wandGat = 200;

/// Onder deze frequentie doen we geen uitspraak.
///
/// Daaronder leven 78-toerenplaten, cassettetransfers, AM-opnames en gerestaureerde mono's. De kans op
/// vals alarm is daar hoog en het belang laag.
const double laagsteAfkapHz = 14000;

/// Er moet ruimte zijn om de val te MÉTEN, dus de afkap mag niet tegen Nyquist aan liggen.
///
/// Bij 44,1 kHz betekent dat: alleen afkappen tot 20,05 kHz zijn beoordeelbaar. Een transcode van 320
/// kbps kapt rond 20,5 kHz en valt daar soms net buiten. Dat is de juiste prijs: liever een gemiste
/// transcode dan een beschuldigde plaat.
const double randNyquistHz = 2000;

/// En boven deze frequentie zoeken we niet, hoe hoog de bemonstering ook is.
///
/// Dit vond de test, en het is geen detail: op een 96 kHz-bestand loopt het zoekgebied anders door tot
/// 46 kHz, en dáár zit het anti-aliasfilter van de omzetter. Dat is een volkomen normale, steile val die
/// élke echte hi-res opname heeft — hij werd als mp3-afkap gelezen en maakte van iedere 96 kHz-plaat een
/// transcode. De afkap die wij zoeken komt van een mp3- of aac-encoder, en die woont tussen 14 en 21 kHz;
/// hoger dan dat kapt geen enkele lossy encoder. Een 96 kHz-bestand dat uit een mp3 komt heeft zijn muur
/// nog steeds rond 20 kHz en valt dus gewoon binnen het bereik.
const double hoogsteAfkapHz = 21000;

/// Boven de muur moet het écht leeg zijn, gemeten tegen de band waar de muziek zit.
const double stilteOnderDb = 55;

/// En onder de muur moet er breedbandige energie zijn, anders is het daar ook al stil en valt er niets
/// af te kappen — dan is de opname gewoon dof.
const double inhoudBovenDb = 25;

/// Hoeveel samples er minstens niet-nul moeten zijn voor de bitdiepteproef.
const int minNietNulSamples = 200000;

// ── De uitslagen ───────────────────────────────────────────────────────────

enum Bitdiepte { spreektNietTegen, opgeblazen, onbekend }

enum Bovenband { vol, leeg, onbekend }

enum Bandbreedte { doorlopend, afgekapt, onbekend }

class Echtheidsoordeel {
  final Bitdiepte bits;
  final int? gebruikteBits;
  final Bovenband boven;
  final Bandbreedte band;
  final double? afkapHz, wandDb;
  final int vensters;

  const Echtheidsoordeel({
    required this.bits,
    required this.boven,
    required this.band,
    this.gebruikteBits,
    this.afkapHz,
    this.wandDb,
    this.vensters = 0,
  });

  /// Alleen wat BEWEZEN is telt. `onbekend` is nadrukkelijk geen "nep" — zie [isOnbekend].
  bool get isNep =>
      bits == Bitdiepte.opgeblazen || boven == Bovenband.leeg || band == Bandbreedte.afgekapt;

  /// Er viel niets te zeggen. Een volwaardig antwoord, geen stille `false`.
  bool get isOnbekend =>
      !isNep &&
      bits == Bitdiepte.onbekend &&
      boven == Bovenband.onbekend &&
      band == Bandbreedte.onbekend;

  Map<String, dynamic> toJson() => {
        'bits': bits.name,
        'boven': boven.name,
        'band': band.name,
        if (gebruikteBits != null) 'gebruikteBits': gebruikteBits,
        if (afkapHz != null) 'afkapHz': afkapHz,
        if (wandDb != null) 'wandDb': wandDb,
        'vensters': vensters,
      };

  static Echtheidsoordeel? fromJson(Map<String, dynamic> j) {
    T? lees<T extends Enum>(List<T> waarden, String sleutel) {
      final s = j[sleutel]?.toString();
      for (final w in waarden) {
        if (w.name == s) return w;
      }
      return null;
    }

    final b = lees(Bitdiepte.values, 'bits');
    final v = lees(Bovenband.values, 'boven');
    final n = lees(Bandbreedte.values, 'band');
    if (b == null || v == null || n == null) return null;
    return Echtheidsoordeel(
      bits: b,
      boven: v,
      band: n,
      gebruikteBits: (j['gebruikteBits'] as num?)?.toInt(),
      afkapHz: (j['afkapHz'] as num?)?.toDouble(),
      wandDb: (j['wandDb'] as num?)?.toDouble(),
      vensters: (j['vensters'] as num?)?.toInt() ?? 0,
    );
  }
}

// ── Proef A: de bitdiepte ──────────────────────────────────────────────────

/// Hoeveel bits er werkelijk in gebruik zijn, uit samples die als 32-bit links uitgelijnd binnenkomen.
///
/// ffmpeg legt bij `s32le` een 16-bit sample in de bovenste zestien bits en een 24-bit sample in de
/// bovenste vierentwintig. De onderste bits zijn dus precies de vraag. Werkt op tweecomplement zonder
/// omweg: negeren behoudt het aantal nullen achteraan, en samples die nul zijn beïnvloeden een OR niet —
/// digitale stilte vervuilt de meting dus niet.
int gebruikteBitsVan(Int32List samples) {
  var masker = 0;
  for (final s in samples) {
    masker |= s;
  }
  if (masker == 0) return 0;
  var nullenAchteraan = 0;
  while (masker & 1 == 0) {
    masker >>= 1;
    nullenAchteraan++;
  }
  return 32 - nullenAchteraan;
}

// ── Proef C: de afkap ──────────────────────────────────────────────────────

/// De frequentie waar de val het steilst is, en hoe steil.
///
/// Bewust een VERSCHIL van twee gemiddelden en niet "de hoogste frequentie boven een drempel". Een
/// absolute drempel vraagt een referentieniveau, en dat verschilt per genre met tientallen dB's; erger,
/// hij kan een natuurlijke roll-off niet van een muur onderscheiden, want beide eindigen ergens. Een
/// verschil is niveau-onafhankelijk en meet precies wat telt: de steilheid.
({double hz, double db})? afkapVan(Float64List spectrum, int sampleRate) {
  if (spectrum.isEmpty) return null;
  final perBin = sampleRate / 2 / spectrum.length;
  double gemiddeldDb(double vanHz, double totHz) {
    final a = (vanHz / perBin).round().clamp(0, spectrum.length - 1);
    final b = (totHz / perBin).round().clamp(0, spectrum.length - 1);
    if (b <= a) return dB(spectrum[a]);
    var som = 0.0;
    for (var i = a; i < b; i++) {
      som += dB(spectrum[i]);
    }
    return som / (b - a);
  }

  final nyquist = sampleRate / 2;
  final bovengrens = math.min(nyquist - randNyquistHz, hoogsteAfkapHz);
  if (bovengrens <= laagsteAfkapHz) return null;

  double besteHz = 0, besteDb = -1e9;
  for (var f = laagsteAfkapHz; f <= bovengrens; f += perBin) {
    final onder = gemiddeldDb(f - wandSpan, f - wandGat);
    final boven = gemiddeldDb(f + wandGat, f + wandSpan + wandGat);
    final val = onder - boven;
    if (val > besteDb) {
      besteDb = val;
      besteHz = f;
    }
  }
  if (besteHz == 0) return null;
  return (hz: besteHz, db: besteDb);
}

// ── Het oordeel ────────────────────────────────────────────────────────────

/// [sampleRate] is die van de DECODER, [kopSampleRate]/[kopBits] wat het bestand bewéért.
Echtheidsoordeel oordeel({
  required Float64List spectrum,
  required int sampleRate,
  required int kopSampleRate,
  required int kopBits,
  required int gebruikteBits,
  required int vensters,
  required int nietNulSamples,
}) {
  const geenIdee = Echtheidsoordeel(
      bits: Bitdiepte.onbekend, boven: Bovenband.onbekend, band: Bandbreedte.onbekend);

  // Onder 44,1 kHz ligt Nyquist onder 22 kHz en degenereert elke drempel.
  if (sampleRate < 44100 || spectrum.isEmpty) return geenIdee;

  // ── A ──
  var bits = Bitdiepte.onbekend;
  if (nietNulSamples >= minNietNulSamples && kopBits > 16) {
    bits = gebruikteBits <= 16 ? Bitdiepte.opgeblazen : Bitdiepte.spreektNietTegen;
  }

  final perBin = sampleRate / 2 / spectrum.length;
  double gemiddeldDb(double vanHz, double totHz) {
    final a = (vanHz / perBin).round().clamp(0, spectrum.length - 1);
    final b = (totHz / perBin).round().clamp(0, spectrum.length - 1);
    if (b <= a) return dB(spectrum[a]);
    var som = 0.0;
    for (var i = a; i < b; i++) {
      som += dB(spectrum[i]);
    }
    return som / (b - a);
  }

  final muziekband = gemiddeldDb(500, 5000);

  // ── B: is er iets boven 22,05 kHz? Alleen zinvol als het bestand méér dan 48 kHz beweert. ──
  var boven = Bovenband.onbekend;
  if (kopSampleRate > 48000 && sampleRate > 48000) {
    final bovenband = gemiddeldDb(22050, sampleRate / 2 - randNyquistHz);
    boven = (muziekband - bovenband) >= stilteOnderDb ? Bovenband.leeg : Bovenband.vol;
  }

  // ── C: staat er een muur? ──
  var band = Bandbreedte.onbekend;
  double? afkapHz, wandDb;
  final gevonden = afkapVan(spectrum, sampleRate);
  if (gevonden != null && vensters >= 8) {
    afkapHz = gevonden.hz;
    wandDb = gevonden.db;
    final erboven = gemiddeldDb(afkapHz + wandGat, (sampleRate / 2) - 200);
    final eronder = gemiddeldDb(afkapHz - 4000, afkapHz - 500);
    final steil = wandDb >= wandDrempelDb;
    final echtLeegErboven = (muziekband - erboven) >= stilteOnderDb;
    final inhoudEronder = (eronder - erboven) >= inhoudBovenDb;
    band = (steil && echtLeegErboven && inhoudEronder) ? Bandbreedte.afgekapt : Bandbreedte.doorlopend;
  }

  return Echtheidsoordeel(
    bits: bits,
    gebruikteBits: nietNulSamples >= minNietNulSamples ? gebruikteBits : null,
    boven: boven,
    band: band,
    afkapHz: afkapHz,
    wandDb: wandDb,
    vensters: vensters,
  );
}

/// Waarom, in dezelfde volgorde als [oordeel] beslist — zodat het scherm nooit iets anders zegt dan de
/// meting. Zelfde afspraak als `whyBetter` in organize.dart.
String waarom(Echtheidsoordeel o) {
  if (o.bits == Bitdiepte.opgeblazen) {
    return 'zegt meer dan 16 bits, maar gebruikt er ${o.gebruikteBits} — opgeblazen';
  }
  if (o.boven == Bovenband.leeg) {
    return 'niets boven 22 kHz — opgeschaald, geen echte hi-res';
  }
  if (o.band == Bandbreedte.afgekapt) {
    final k = (o.afkapHz! / 1000).toStringAsFixed(1);
    return 'harde afkap op $k kHz — dit kwam uit een mp3';
  }
  if (o.isOnbekend) return 'niet te beoordelen';
  final stukken = <String>[];
  if (o.bits == Bitdiepte.spreektNietTegen) stukken.add('${o.gebruikteBits} bits in gebruik');
  if (o.boven == Bovenband.vol) stukken.add('inhoud boven 22 kHz');
  if (o.band == Bandbreedte.doorlopend) stukken.add('geen afkap gevonden');
  return stukken.isEmpty ? 'niet te beoordelen' : stukken.join(' · ');
}

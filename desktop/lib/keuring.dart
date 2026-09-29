/// De keuring: mag een binnenkomer de bibliotheek in, en is hij BEWEZEN beter dan wat er al ligt?
///
/// **Waarom dit bestaat.** Saber, 29-09-2026, bij Blood On The Dance Floor: *"ik kon zweren dat ik alle
/// liedjes in beste kwaliteit had, en nu staan er een paar afgekapt en in mindere kwaliteit. Als er
/// een slechtere binnenkomt dan wat ik heb moet die weg, en moet mijn betere kwaliteit blijven."*
///
/// Gemeten die dag: van de 95 bestanden in `_dubbel` hadden er 47 een opvolger met lagere getallen op
/// de badge. Een deel was terecht — een nep-24/192 die plaats maakte voor een GEMETEN echte 24/96, een
/// uit mp3 opgeblazen FLAC voor een echte cd. Maar het grootste deel was een ruil zonder winst: een
/// 24/96 die boven 22 kHz leeg was (dus eigenlijk een cd) tegen een eerlijke 24/48 of 24/44,1 die nooit
/// gemeten was. De oude regel (`firstIsBetter`) keek naar "bewezen nep" en daarna naar de GROOTTE, dus
/// won het ongemeten bestand van het gemeten, en bij gelijke kwaliteit
/// won de grootste.
///
/// **De regel nu, in één zin: alleen wat bewezen beter is, vervangt; bij gelijk blijft wat er stond.**
///
/// De klassen, van slecht naar goed:
///
///   kapot           decodeert niet tot het eind — zie [beoordeelDecode]
///   lossy           mp3, aac, ogg, opus
///   uitLossy        een verliesvrij bestand met een muur in het spectrum: omgezet uit een mp3
///   cd              verliesvrij, en wat het beweert boven 48 kHz is niet bewezen
///   onbewezenHires  verliesvrij, beweert meer dan 48 kHz, nooit gemeten — vergelijkt als "weet niet"
///   hires           verliesvrij, en de meter zág muziek boven 22,05 kHz
///
/// **Waarom 48 kHz bij de cd hoort.** Proef B (de bovenband) draait pas boven de 48 kHz; op een 24/48 of
/// 24/44,1 is er niets te bewijzen boven de cd. Een eerlijke 24/48 is daarom niet bewezen beter dan een
/// opgeschaalde 24/96 die eigenlijk een cd is, en dus blijft die van jou staan. Precies Is It Scary.
///
/// **Waarom de bits niet tellen.** Proef A bewijst alleen het negatieve: "deze 24 bits zijn er 16". Dat
/// ze er écht 24 zijn, bewijst geen enkele meting — zie `Bitdiepte.spreektNietTegen`. Een 24/44,1 is dus
/// niet bewezen beter dan een 16/44,1, en ook dan blijft wat er stond.
///
/// Puur en zonder `dart:io`: elke regel hieronder staat met de gemeten gevallen in
/// `test/keuring_test.dart`.
library;

import 'echtheid.dart';

/// Hoe goed een bestand BEWEZEN is. De volgorde van de waarden is de rangorde.
enum Klasse { kapot, lossy, uitLossy, cd, onbewezenHires, hires }

/// Wat de keuring van één bestand weet. [rate] is de bemonstering uit de kop — alleen van belang
/// tussen twee bewezen hires-bestanden. [formaat] is `formatRank` uit organize.dart: binnen dezelfde
/// klasse gaat een FLAC voor een WAV, en een aac voor een mp3.
typedef Kwaliteit = ({Klasse klasse, int rate, int formaat});

/// De klasse van een bestand uit wat er over bekend is.
///
/// [verliesvrij]: het formaat (niet de meting) is verliesvrij. [kapot]: de decodeerproef zei nee —
/// onbekend telt als heel, want een proef die niet kon draaien mag niets weigeren.
Kwaliteit kwaliteitUit(
    {required bool verliesvrij,
    required int kopRate,
    required int formaat,
    Echtheidsoordeel? oordeel,
    bool kapot = false}) {
  Klasse k;
  if (kapot) {
    k = Klasse.kapot;
  } else if (!verliesvrij) {
    k = Klasse.lossy;
  } else if (oordeel?.band == Bandbreedte.afgekapt) {
    k = Klasse.uitLossy;
  } else if (kopRate <= 48000) {
    // Niets te bewijzen boven de cd, en een onbekende kop (0) hoort hier ook.
    k = Klasse.cd;
  } else if (oordeel?.boven == Bovenband.vol) {
    k = Klasse.hires;
  } else if (oordeel?.boven == Bovenband.leeg) {
    k = Klasse.cd; // opgeschaald: wat het draagt is een cd
  } else {
    k = Klasse.onbewezenHires;
  }
  return (klasse: k, rate: kopRate, formaat: formaat);
}

/// Groter dan nul als [a] BEWEZEN beter is dan [b], kleiner dan nul als [b] het is, nul als het gelijk
/// is of niet te zeggen valt.
///
/// **Nul is het belangrijkste antwoord.** Bij nul blijft wat er stond; zo kan een download die niets
/// bewijst nooit iets van jou wegduwen.
int vergelijkKwaliteit(Kwaliteit a, Kwaliteit b) {
  final ka = a.klasse, kb = b.klasse;
  // Een onbewezen hires-claim is niet te vergelijken met een cd of met bewezen hires: meten zou het
  // antwoord zijn, en zonder meting is het "weet niet". Wél beter dan alles onder de cd.
  if (ka == Klasse.onbewezenHires || kb == Klasse.onbewezenHires) {
    final ra = ka == Klasse.onbewezenHires ? Klasse.cd : ka;
    final rb = kb == Klasse.onbewezenHires ? Klasse.cd : kb;
    if (ra.index < Klasse.cd.index || rb.index < Klasse.cd.index) {
      return ra.index.compareTo(rb.index);
    }
    return 0;
  }
  if (ka != kb) return ka.index.compareTo(kb.index);
  // Twee bewezen hires-bestanden: de hoogste bewezen bemonstering.
  if (ka == Klasse.hires && a.rate != b.rate) return a.rate.compareTo(b.rate);
  // Zelfde klasse: het formaat, en alleen als dat een echt verschil is (FLAC boven WAV, aac boven mp3).
  // Een WavPack is geen stap vooruit tegen een FLAC en andersom ook niet: beide [formatRank] 4.
  return a.formaat.compareTo(b.formaat);
}

/// Hoe een klasse op het scherm en in het logboek heet.
String kwaliteitZin(Kwaliteit k) => switch (k.klasse) {
      Klasse.kapot => 'kapot',
      Klasse.lossy => 'lossy',
      Klasse.uitLossy => 'omgezet uit een mp3',
      Klasse.cd => 'cd-kwaliteit',
      Klasse.onbewezenHires => 'hi-res volgens de kop, niet gemeten',
      Klasse.hires => 'echte hi-res (${_khz(k.rate)} kHz)',
    };

String _khz(int rate) =>
    rate % 1000 == 0 ? '${rate ~/ 1000}' : (rate / 1000).toStringAsFixed(1);

// ── Heel of kapot ─────────────────────────────────────────────────────────────

/// Wat een volledige decodeerproef zegt: heel, of kapot met de reden.
typedef Heelheid = ({bool heel, String? reden});

/// Woorden waarmee ffmpeg schade IN de audio meldt. Gemeten op 29-09-2026 aan de bestanden die op 14-09
/// als echt kapot bleken: Just Dance en Moules frites "invalid residual", Give Me Some Love
/// "qlevel … not supported".
final RegExp _schade = RegExp(r'residual|qlevel|subframe|corrupt|overread|md5', caseSensitive: false);

/// Kon het bestand niet eens geopend worden of draagt het geen geluid? Niet op "Invalid data found"
/// alleen: dat staat ook achter elke "Decoding error", en die telt [beoordeelDecode] apart.
final RegExp _onopenbaar = RegExp(
    r'Error opening input|does not contain any stream',
    caseSensitive: false);

/// Hoeveel een decodering korter mag uitvallen dan de kop belooft, in seconden.
///
/// Een laatste frame dat half vol is, of een encoder die zijn totaal naar boven afrondt, scheelt
/// honderdsten. De echte gevallen scheelden 49,8 s (Just Dance), 154 s en 218 s. Eén seconde laat alle
/// ruis door en vangt elk afgekapt bestand.
const double kToegestaanTekort = 1.0;

/// Heel of kapot, uit wat `ffmpeg -loglevel level+error … -f null -` zei.
///
/// [foutregels] zijn de regels met `[error]` erin. [kopSeconden] is wat het bestand zegt te duren,
/// [gedecodeerdSeconden] hoe ver de decodering werkelijk kwam (`out_time_us` van `-progress`).
///
/// **Waarom niet gewoon "ffmpeg mopperde".** Op 14-09-2026 gaf dat 25 valse alarmen op 1404 bestanden:
/// een ID3v1-tag van 128 bytes áchter de FLAC-frames geeft precies één keer "invalid sync code /
/// invalid frame header / decode_frame() failed / Decoding error". Gemeten op 29-09-2026 op Janet
/// Jackson — Son Of A Gun: vier foutregels, ID3v1 achteraan, en de decodering haalt de volle 356,3 s.
/// Heel. Give Me Some Love haalt óók de volle lengte, maar met 22 mislukte pakketten: rot in het
/// midden. Kapot.
///
/// Dus: kapot als het niet te openen is, als de decodering duidelijk korter uitvalt dan de kop, als
/// ffmpeg schade in de frames noemt ([_schade]), of als meer dan één pakket mislukte.
Heelheid beoordeelDecode(
    {required int exitCode,
    required List<String> foutregels,
    double? kopSeconden,
    double? gedecodeerdSeconden}) {
  for (final r in foutregels) {
    if (_onopenbaar.hasMatch(r.trim())) {
      return (heel: false, reden: 'niet te openen');
    }
  }
  if (kopSeconden != null && kopSeconden > 0 && gedecodeerdSeconden != null) {
    final tekort = kopSeconden - gedecodeerdSeconden;
    if (tekort > kToegestaanTekort) {
      return (
        heel: false,
        reden: 'afgekapt: speelt ${gedecodeerdSeconden.toStringAsFixed(1)} van '
            '${kopSeconden.toStringAsFixed(1)} s'
      );
    }
  }
  final schade = foutregels.where(_schade.hasMatch).toList();
  if (schade.isNotEmpty) {
    return (heel: false, reden: 'beschadigd: ${_kern(schade.first)}');
  }
  final mislukt = foutregels.where((r) => r.contains('Decoding error')).length;
  if (mislukt > 1) {
    return (heel: false, reden: 'beschadigd: $mislukt stukken niet te decoderen');
  }
  // Een ffmpeg die zelf struikelde (geen geheugen, afgebroken) zonder een foutregel te geven: dan is
  // er niets bewezen, en niets bewezen is heel.
  return (heel: true, reden: null);
}

/// Het deel van een ffmpeg-regel dat iets zegt: zonder `[flac @ 0x…] [error]`.
String _kern(String regel) {
  final i = regel.lastIndexOf('] ');
  return (i < 0 ? regel : regel.substring(i + 2)).trim();
}

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
/// **De bits als scheidsrechter (sinds 23-10-2026).** Tot dan telden ze niet: Proef A bewijst alleen het
/// negatieve ("deze 24 bits zijn er 16"), en dat ze er écht 24 zijn bewijst geen meting — zie
/// `Bitdiepte.spreektNietTegen`. Maar Saber, na Ellie Goulding — Close To Me (Solo) van TIDAL: *"ellie lukt in
/// 24bit, maar tidal vervangt slechtere kwaliteit nog niet, daarmee ik bleef de 16 bit zien"*. De 24-bitkopie
/// (alle 24 bits in gebruik, md5 in orde, "consistent") ging als "gelijk" opzij, want beide waren jouw keuze.
///
/// Nu: bij verder gelijke kwaliteit wint wat volgens Proef A MEER dan 16 bits gebruikt ([Kwaliteit.diep]) van wat
/// er 16 heeft — maar alleen bij een spectrum dat bewezen doorloopt (Proef C: [Bandbreedte.doorlopend]) en niet
/// opgeschaald is (Proef B: niet [Bovenband.leeg]). Want elke bewerking vult de lage bits: een opgeschaalde cd en
/// een mp3 die tot 24 bit gedecodeerd is gebruiken ze ook allemaal. Een opgeblazen 16 bit telt nooit als diep;
/// in het ergste geval (een 16-bitmaster met een volumeaanpassing) is het dezelfde muziek in een groter bestand.
///
/// **En sinds 27-10-2026 alleen nog met bewijs tegen je eigen 16-bitkopie: de nultoets (nultoets.dart).** Saber, bij
/// D'Eux van Céline Dion: *"volgens bronnen zou het album nooit in high res uitgekomen zijn … toch staan er liedjes bij
/// van 24bit"*. Het "ergste geval" hierboven was precies wat er gebeurde: zijn cd, 0,8 dB verzet en als 24 bit
/// bewaard, duwde de cd opzij; en een gedecodeerde stream (precies 1024 monsters achter de cd) ook. Nu telt de diepte
/// alleen als de nultoets zegt dat je 16-bitkopie deze kopie IS, afgerond ([Nuluitkomst.bron]) — zie [metNultoets].
/// Een bewerkte cd verliest bij gelijke stand van het origineel ([Kwaliteit.bewerkt]), een gedecodeerde stream telt als
/// [Klasse.uitLossy], en wat niet gemeten is, bewijst niets.
///
/// **En sinds 28-10-2026: een eerlijke kopie wint van een kop die liegt ([Kwaliteit.kopLiegt]).** Tot dan bleef een
/// opgeschaalde 24/96 staan tegenover een eerlijke cd of 24/44,1 — beide "cd", dus gelijk (zie Is It Scary hierboven).
/// Saber, bij een "studio" van Lil' Kim die een mp3 bleek: *"Ik wil geen fake enkel echt … liever cd kwaliteit dan fake
/// studio!"* Nu verliest een opgeschaalde of opgeblazen kopie bij verder gelijke stand van een die gemeten is en schoon:
/// doorlopend, zonder muur, en zelf niet opgeschaald of opgeblazen ([Kwaliteit.schoon]). Tegen een kopie met een muur
/// rond 20 kHz blijft het gelijk: die kan een mp3 zijn, en een opgeschaalde cd is in elk geval verliesvrij.
///
/// Puur en zonder `dart:io`: elke regel hieronder staat met de gemeten gevallen in
/// `test/keuring_test.dart`.
library;

import 'echtheid.dart';
import 'nultoets.dart';

/// Hoe goed een bestand BEWEZEN is. De volgorde van de waarden is de rangorde.
enum Klasse { kapot, lossy, uitLossy, cd, onbewezenHires, hires }

/// Wat de keuring van één bestand weet. [rate] is de bemonstering uit de kop — alleen van belang
/// tussen twee bewezen hires-bestanden. [formaat] is `formatRank` uit organize.dart: binnen dezelfde
/// klasse gaat een FLAC voor een WAV, en een aac voor een mp3. [diep]: Proef A zag meer dan 16 bits in gebruik, in
/// een doorlopend en niet opgeschaald spectrum — zie hierboven, "de bits als scheidsrechter". [bewerkt]: de nultoets
/// zag dat dit een andere kopie is, verzet in volume of door iets gehaald ([Nuluitkomst.bewerkt]). [kopLiegt]: de kop
/// belooft meer dan erin zit — opgeschaald ([Bovenband.leeg]) of opgeblazen ([Bitdiepte.opgeblazen]). [schoon]: gemeten,
/// doorlopend, en niets van dat alles — de eerlijke kopie waarvan een [kopLiegt] verliest (28-10-2026).
typedef Kwaliteit = ({Klasse klasse, int rate, int formaat, bool diep, bool bewerkt, bool kopLiegt, bool schoon});

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
  // De volle echtheidsmeting bewijst het ook: de MD5 van de samples klopt niet met de FLAC-kop.
  if (kapot || (oordeel?.isKapot ?? false)) {
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
  // Elke bewerking vult de lage bits: opschalen, en een mp3 die tot 24 bit gedecodeerd is ook. Daarom telt de
  // diepte alleen bij een spectrum dat bewezen doorloopt en niet opgeschaald is.
  final diep = oordeel != null &&
      oordeel.bits == Bitdiepte.spreektNietTegen &&
      (oordeel.gebruikteBits ?? 0) > 16 &&
      oordeel.band == Bandbreedte.doorlopend &&
      oordeel.boven != Bovenband.leeg;
  final kopLiegt = oordeel != null && (oordeel.bits == Bitdiepte.opgeblazen || oordeel.boven == Bovenband.leeg);
  final schoon = oordeel != null && k.index >= Klasse.cd.index && oordeel.band == Bandbreedte.doorlopend && !oordeel.isNep;
  return (klasse: k, rate: kopRate, formaat: formaat, diep: diep, bewerkt: false, kopLiegt: kopLiegt, schoon: schoon);
}

/// Hoeveel verder een andere kopie van dezelfde opname echt moet doorlopen om te bewijzen dat de muur van de
/// eerste geen filter in de master was — zie [metMuurBewijs].
const kMuurBewijsHz = 500.0;

/// Zo diep moet een muur onder [zekerAfkapTot] minstens zijn om door een andere kopie bewezen te kunnen worden, ook als
/// de meter hem op zichzelf te ondiep vond (die wil er 25). Destin (27-10-2026): 22,7 dB op 17,15 kHz. Een natuurlijke
/// afloop zakt over een kilohertz geen 20 dB: in de bibliotheek lagen 506 van de 552 "doorlopende" bestanden met hun
/// steilste val onder 19,4 kHz onder 10 dB.
const kKopieWandDb = 20.0;

/// Bewijst [ob] (een andere kopie van dezelfde opname) dat de muur in [oa] niet in de master zat? Dat is zo als [oa] een
/// verdachte muur heeft — [Bandbreedte.vermoedelijk], of een doorlopend oordeel met een muur van minstens [kKopieWandDb]
/// onder [zekerAfkapTot] (waar een studio niet filtert) — en [ob] bewezen doorloopt tot minstens [kMuurBewijsHz] verder.
bool muurBewezenDoor(Echtheidsoordeel? oa, Echtheidsoordeel? ob) {
  if (oa == null || ob == null || ob.isNep || ob.band != Bandbreedte.doorlopend) return false;
  final xa = oa.afkapHz, xb = ob.afkapHz;
  if (xa == null || xb == null || xb < xa + kMuurBewijsHz) return false;
  return oa.band == Bandbreedte.vermoedelijk ||
      (oa.band == Bandbreedte.doorlopend && (oa.wandDb ?? 0) >= kKopieWandDb && xa < zekerAfkapTot);
}

/// Wat [ob] bewees, voor [Echtheidsoordeel.bewijs]: "je cd loopt door tot 21,3 kHz". [wie]: hoe de andere kopie heet.
String muurBewijsZin(Echtheidsoordeel ob, String wie) =>
    'je $wie loopt door tot ${((ob.afkapHz ?? 0) / 1000).toStringAsFixed(2).replaceAll('.', ',')} kHz';

/// [a] met wat een ANDERE kopie van dezelfde opname over zijn muur bewijst.
///
/// **Waarom (Saber, 21-10-2026, Snoop Dogg — Beautiful).** Zijn 24/48 heeft een muur op 20,0 kHz: "past bij
/// mp3 320 of Opus, maar ook bij een 20 kHz-filter in de master; niet zeker" ([Bandbreedte.vermoedelijk]).
/// Dat telt als cd, en dan is een echte cd-kopie hooguit gelijk — en blijft het verdachte bestand staan.
/// Maar loopt een andere kopie van dezelfde opname wél door, tot ver voorbij die muur
/// ([Bandbreedte.doorlopend], minstens [kMuurBewijsHz] hoger), dan zat die muur niet in de master: dan is
/// bewezen dat [a] afgekapt is, en telt het als [Klasse.uitLossy]. Saber: "Ja, dat telt als bewijs."
///
/// Sinds 27-10-2026 ook een te ondiepe muur in de mp3-zone ([muurBewezenDoor]): Destin.
Kwaliteit metMuurBewijs(Kwaliteit a, Echtheidsoordeel? oa, Echtheidsoordeel? ob) {
  if (a.klasse != Klasse.cd && a.klasse != Klasse.onbewezenHires) return a;
  if (!muurBewezenDoor(oa, ob)) return a;
  return (
      klasse: Klasse.uitLossy,
      rate: a.rate,
      formaat: a.formaat,
      diep: a.diep,
      bewerkt: a.bewerkt,
      kopLiegt: a.kopLiegt,
      schoon: false);
}

/// [a] met wat de nultoets over hem zei ([nul]: [a] tegen [b]), als zijn diepte tegen [b] zou beslissen — [a] is
/// [Kwaliteit.diep] en [b] niet.
///
/// Drie gevallen, en het derde hardop beslist:
/// * [Nuluitkomst.bron]: je 16-bitkopie is [a], afgerond — de diepte telt, zoals sinds 23-10-2026.
/// * [Nuluitkomst.bewerkt]: je cd, verzet of door iets gehaald — geen diepte, en bij gelijke stand verliest hij van het
///   origineel. [Nuluitkomst.lossy]: een gedecodeerde stream — [Klasse.uitLossy].
/// * [Nuluitkomst.anders] en niet gemeten (null): niets bewezen, dus geen diepte. Een andere master in 24 bit kan
///   beter zijn, maar ook een opname door een geluidskaart; "24 bits in gebruik" zegt dat niet.
Kwaliteit metNultoets(Kwaliteit a, Kwaliteit b, Nuluitkomst? nul) {
  if (!a.diep || b.diep) return a;
  return switch (nul) {
    Nuluitkomst.bron => a,
    Nuluitkomst.lossy => (
        klasse: Klasse.uitLossy,
        rate: a.rate,
        formaat: a.formaat,
        diep: false,
        bewerkt: false,
        kopLiegt: a.kopLiegt,
        schoon: false),
    Nuluitkomst.bewerkt => (
        klasse: a.klasse,
        rate: a.rate,
        formaat: a.formaat,
        diep: false,
        bewerkt: true,
        kopLiegt: a.kopLiegt,
        schoon: a.schoon),
    Nuluitkomst.anders || null => (
        klasse: a.klasse,
        rate: a.rate,
        formaat: a.formaat,
        diep: false,
        bewerkt: false,
        kopLiegt: a.kopLiegt,
        schoon: a.schoon),
  };
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
  // Verder gelijk en verliesvrij: wat meer dan 16 bits in gebruik heeft, wint van 16 bit ([Kwaliteit.diep]).
  if ((ka == Klasse.cd || ka == Klasse.hires) && a.diep != b.diep) return a.diep ? 1 : -1;
  // Een kopie die de nultoets als bewerkt zag, verliest van wat ze bewerkte ([metNultoets]).
  if (a.bewerkt != b.bewerkt) return a.bewerkt ? -1 : 1;
  // Een kop die liegt (opgeschaald, opgeblazen) verliest van een eerlijke kopie die schoon gemeten is — niet van een
  // met een muur rond 20 kHz: die kan een mp3 zijn, en wat hier ligt is in elk geval verliesvrij (28-10-2026).
  if (a.kopLiegt != b.kopLiegt && (a.kopLiegt ? b : a).schoon) return a.kopLiegt ? -1 : 1;
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

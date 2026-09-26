/// Welke versie van een liedje de radio speelt, en hoeveel bewerkingen erbij mogen.
///
/// **Het probleem waar dit over gaat.** De lijst van een radio komt van Deezer: per zaadartiest de
/// toppers. Bij dance uit de jaren negentig zijn dat er zelden tien verschillende liedjes — het zijn
/// twee of drie liedjes in acht uitvoeringen. "Rhythm Is a Dancer", en daarnaast de Extended Mix, de
/// Club Mix, de 12" en een instrumentale. Wie die lijst ongefilterd afspeelt hoort een uur lang
/// varianten van hetzelfde, en dat is precies wat er gemeld werd: *"meer de originele en radio edits
/// dan remixen, het mag wel maar het is te veel nu."*
///
/// Twee regels, en verder niets:
///
/// 1. **Van één liedje één uitvoering**, en wel de gewoonste die er is. Staat de gewone versie
///    ertussen, dan verdwijnt de Club Mix; staat hij er niet, dan blijft de Club Mix staan. Deze
///    regel kost je dus nooit een liedje, alleen een dubbel.
/// 2. **Een rantsoen voor de rest.** Wat er na regel 1 nog aan bewerkingen over is — een remix van
///    iets waar geen gewone versie van bestaat — mag hoogstens twee op de tien zijn. "Het mag wel,
///    maar niet te veel." Deze regel kan er dus wél een laten vallen: bij een radio van driehonderd
///    is er ruimte voor zestig, en wie er tachtig aanbiedt houdt er zestig over.
///
/// Geen IO en geen toeval, want dit is een oordeel over smaak en dat hoort na te rekenen te zijn.
library;

/// Wat voor uitvoering een titel aankondigt.
///
/// De volgorde IS de rangorde: lager is liever. [origineel] is een titel die niets aankondigt — de
/// gewone plaatversie. [radio] is de versie die op de radio ging, en die is hier expres net zo
/// welkom: bij dance uit de jaren negentig ís de radio-edit vaak de versie die iedereen kent.
enum Uitvoering { origineel, radio, bewerking }

/// Alles wat de titel over de UITVOERING zegt: tussen haakjes, en achter een gedachtestreepje.
///
/// Deezer schrijft het allebei. "Mr. Vain (Radio Edit)" en "Mr. Vain - Radio Edit" zijn hetzelfde
/// nummer, en één van de twee vormen herkennen is hetzelfde als geen van beide herkennen.
String _staart(String titel) => _staartDelen(titel).join(' ');

/// De delen van [_staart] los: elk paar haakjes apart, en wat er achter de streep staat.
List<String> _staartDelen(String titel) {
  titel = _gewoneTekens(titel);
  final streep = titel.indexOf(' - ');
  return [
    for (final m in _haakjes.allMatches(titel)) (m.group(1) ?? '').toLowerCase(),
    if (streep > 0) titel.substring(streep + 3).toLowerCase(),
  ];
}

final _haakjes = RegExp(r'[\(\[]([^\)\]]*)[\)\]]');

/// Een gast, tot het eind van zijn haakjes — of tot een woord dat weer over de uitvoering gaat.
///
/// Gemeten in de eindbeoordeling van 26-09-2026: "(feat. Culture Club)" telde als clubmix en
/// "(feat. Oliver Heldens)" als live-opname — "club" en "o-live-r" stonden er letterlijk in — en
/// allebei werden ze geweerd als bewerking. "(feat. X Remix)" blijft wel een remix.
final _gast = RegExp(r'\b(feat\.?|ft\.?|featuring)\s.*?(?=\s(remix|rmx|mix|edit|version|dub|live)\b|$)');

/// "with" als gast alleen vooraan in de haakjes — "(with Ellie Goulding)"; in "(Dance With Me)" is
/// het een woord van de titel. Ook hier tot een versiewoord: "(with X Remix)" blijft een remix.
final _metGast = RegExp(r'^\s*with\s.*?(?=\s(remix|rmx|mix|edit|version|dub|live)\b|$)');

/// De staart zonder gasten, per deel — zie [_gast] en [_metGast].
///
/// Behalve een orkest of strijkers: "(with The Royal Philharmonic Orchestra)" is geen gast maar een
/// nieuwe opname, en die hoort als bewerking te tellen ([_eerstAnders]) en niet als het origineel
/// (tweede beoordeling van 26-09-2026).
///
/// En zonder filmnaam ([_uitFilm]): in `- From "The Breakfast Club" Soundtrack` stond "club", en
/// dan werd "Don't You (Forget About Me)" een clubmix (derde beoordeling van 26-09-2026).
List<String> _delenZonderGast(String titel) => [
      for (final d in _staartDelen(titel))
        (_orkest.hasMatch(d) ? d : d.replaceFirst(_metGast, '').replaceAll(_gast, ' '))
            .replaceAll(_uitFilm, ' ')
    ];

final _orkest = RegExp(r'\b(orchestra|orchestral|philharmonic|symphonic|strings|choir)\b');

String _staartZonderGast(String titel) => _delenZonderGast(titel).join(' ');

/// Een filmnaam achter "from": `- From "Saturday Night Fever" Soundtrack`. De naam van de film zegt
/// niets over de uitvoering — het is juist de bekendste — dus die woorden tellen niet als onbekend.
final _uitFilm = RegExp(r'\bfrom\b.*\b(soundtrack|motion picture|film|movie|ost|musical|series)\b.*$');

/// Typografische tekens terug naar gewone, en een laag streepje naar een spatie.
///
/// Gemeten op 26-09-2026: Deezer schrijft "What Is Love (7” Mix)" met een gekrulde ” (U+201D), en
/// dan herkende niets hier de 7"-versie — hij telde als remix. Soulseek schrijft
/// "what_is_love_(7_inch_mix)".
String _gewoneTekens(String s) => s
    .replaceAll(RegExp('[“”„″]'), '"')
    .replaceAll(RegExp('[‘’´`]'), "'")
    .replaceAll('_', ' ');

/// Accenten weg, letters blijven: "Désenchantée" is "desenchantee", "Blümchen" is "blumchen".
///
/// Voorheen verdwenen ze helemaal — "Désenchantée" werd "dsenchante" — en dan was een bestand dat
/// ze zonder accenten schreef een ander nummer.
String vouw(String s) {
  const van = 'àáâãäåāçćčèéêëēėęìíîïīñńòóôõöøōùúûüūýÿžźżšśł';
  const naar = 'aaaaaaaccceeeeeeeiiiiinnoooooooouuuuuyyzzzssl';
  final buf = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final l = c.toLowerCase();
    final i = van.indexOf(l);
    if (i >= 0) {
      buf.write(naar[i]);
    } else if (l == 'æ') {
      buf.write('ae');
    } else if (l == 'ß') {
      buf.write('ss');
    } else {
      buf.write(c);
    }
  }
  return buf.toString();
}

/// Wat een ANDERE versie aankondigt, ook als er "radio" of "edit" bij staat — daarom vóór [_gewoon].
///
/// Gemeten op 26-09-2026 op Deezer: "What Is Love - Reloaded (Radio Edit)" (een latere heropname),
/// "It's My Life (2011 Version)", "Blue (Da Ba Dee) (Hannover Rmx)". Ze telden alle drie als de
/// gewone versie.
///
/// En een repetitie, een demo, een sessie of een live-opname — ook met "Radio" erbij: gemeten in de
/// kwaliteitscontrole van 26-09-2026 golden "Losing My Religion (Live From … BBC Radio 1)" en
/// "The Man Who Sold the World (Rehearsal)" als de gewone versie.
final RegExp _eerstAnders = RegExp(r'\b(rmx|remix|remixes|reloaded|redux|re-recorded|rerecorded|'
    r'sped up|slowed|acoustic|megamix|medley|mashup|christmas|xmas|a cappella|acapella|acappella|'
    r'a-pella|live|demos?|rehearsals?|sessions?|boom ?box|outtakes?|take \d+|'
    r'orchestra|orchestral|philharmonic|symphonic|strings|choir)\b|'
    r'\b(19|20)\d\d (version|mix|edit)\b');

/// Radioversies die anders heten dan "Radio Edit". Gemeten op 26-09-2026: "(Airplay Mix)",
/// "(Video Edit)" (Eiffel 65 — Blue), "(Single Mix)", en 7" in al zijn spellingen.
final RegExp _gewoonExtra = RegExp(r'\b(airplay|video (edit|mix|version)|single mix|'
    r'short (cut|mix|edit|version))\b|\b7\s*("|' "''" r'|inch|in\b)|\b7 (mix|edit|version)\b');

/// Zegt de staart met zoveel woorden dat dit de gewone of de radioversie is?
///
/// Deze staat VÓÓR de bewerkingen in [uitvoeringVan], want "Radio Mix" draagt het woord "mix" en zou
/// anders als remix gelden — terwijl het juist de versie is die gevraagd werd.
const List<String> _gewoon = [
  'radio edit',
  'radio version',
  'radio mix',
  'radio cut',
  'single version',
  'single edit',
  'original version',
  'original mix',
  'album version',
  '7"',
  "7''",
  '7 inch',
];

/// En dit is er iets anders mee gedaan.
///
/// "mix" staat er als laatste en dus als grofste vangnet: alles wat "… Mix" heet en hierboven niet
/// als gewone versie herkend is, is een bewerking. Live, instrumentaal en karaoke horen niet in een
/// remixlijst thuis maar wel in dit vakje: het zijn evenmin de versie die je verwacht.
const List<String> _anders = [
  'remix',
  'extended',
  'club',
  'dub',
  'bootleg',
  'rework',
  'remake',
  'vip',
  'instrumental',
  'a cappella',
  'acapella',
  'acappella',
  // "Kickin' Hard (Klubb-A-Pella)" van Klubbheads, gezien op 26-09-2026: een a-cappellaversie.
  'a-pella',
  'apella',
  'karaoke',
  // Geen "live" hier: als losse tekst stond het in "Oliver" en "Olive", en de echte live-opname vangt
  // [_eerstAnders] al als heel woord.
  'unplugged',
  'cover',
  // Een tv-programma waarin artiesten elkaars liedjes zingen. Gezien op 26-09-2026: drie keer Pat
  // Krimson "… - Uit Liefde Voor Muziek" in een eurodanceradio — geen enkel origineel.
  'uit liefde voor muziek',
  'liefde voor muziek',
  'tribute',
  // "(Original Maxi)": de maxisingle, de lange versie. Het woord "original" maakt hem niet de gewone
  // — Sash! Mysterious Times duurt zo zes minuten in plaats van drieënhalf.
  'maxi',
  '12"',
  "12''",
  '12 inch',
  'mix',
];

/// Wat NOOIT op de radio hoort, ook niet als er geen andere versie van is: iemand anders die
/// andermans liedje zingt.
///
/// Gemeten op 26-09-2026: in de Deezer-top van 2 Fabiola staan vier nummers van Pat Krimson uit het
/// tv-programma *Uit Liefde Voor Muziek* — Pat Krimson is een van de twee, en Deezer rekent ze dus
/// mee. Een bewerking mag in het rantsoen (twee op de tien), maar dit is geen bewerking van een
/// origineel dat er ook had kunnen staan; het is een cover. Saber: "ik wil vooral originele nummers
/// horen."
final RegExp _nooit = RegExp(
    r'\b(uit liefde voor muziek|liefde voor muziek|tribute|karaoke|cover|in the style of|'
    r'originally performed|made famous)\b');

/// Hoort dit nummer nooit op een radio? Zie [_nooit].
bool nooitOpRadio(String titel) => _nooit.hasMatch(_staart(titel));

/// Wat voor uitvoering dit is, alleen op de titel af. Een gast telt niet mee — zie [_gast].
Uitvoering uitvoeringVan(String titel) {
  final s = _staartZonderGast(titel);
  if (s.trim().isEmpty) return Uitvoering.origineel;
  if (_eerstAnders.hasMatch(s)) return Uitvoering.bewerking;
  for (final m in _gewoon) {
    if (s.contains(m)) return Uitvoering.radio;
  }
  if (_gewoonExtra.hasMatch(s)) return Uitvoering.radio;
  // "(Radio)" op zichzelf, als heel woord. Niet als losse tekst, want dan telt "(Radiohead Remix)"
  // ook mee en dat is nu juist een remix.
  if (RegExp(r'\bradio\b').hasMatch(s)) return Uitvoering.radio;
  for (final m in _anders) {
    if (s.contains(m)) return Uitvoering.bewerking;
  }
  // Een kale "edit" of "short version" is een radioversie en geen bewerking — maar pas hier, ná de
  // bewerkingen, zodat "Remix Edit" niet als radio-edit doorgaat.
  if (s.contains('edit') || s.contains('short version')) return Uitvoering.radio;
  return Uitvoering.origineel;
}

/// Woorden die een staart mag bevatten zonder iets onbekends te zeggen.
///
/// Ook wat een film of een heruitgave aankondigt: `- From "Saturday Night Fever" Soundtrack` is de
/// bekendste "Stayin' Alive" die er is, en "(Deluxe Edition)" of "(US Radio Edit)" is geen andere
/// uitvoering (eindbeoordeling van 26-09-2026).
const Set<String> _bekendeStaart = {
  'radio', 'edit', 'version', 'single', 'mix', 'original', 'album', 'remaster', 'remastered',
  'inch', 'short', 'cut', 'airplay', 'video', 'mono', 'stereo', 'clean', 'explicit', 'main', 'lp',
  'from', 'the', 'of', 'a', 'digital', 'bonus', 'track', 'uncut', 'vocal', 'full', 'length',
  'soundtrack', 'theme', 'motion', 'picture', 'ost', 'film', 'movie', 'edition', 'deluxe',
  'digitally', 'expanded', 'anniversary', 'us', 'uk', 'radioversion', 'singleversion',
  'albumversion', 'and', 'in',
};

final _woordgrens = RegExp(r'[^a-z0-9]+');
final _getal = RegExp(r'^\d+$');

/// Zegt de staart iets wat geen bekende versieaanduiding is — een naam, een "Konzept"?
///
/// Gemeten in de kwaliteitscontrole van 26-09-2026: "Eins, Zwei, Polizei (Einstein Dr. Dj Konzept)"
/// telde als de gewone versie en won van "(Radio Edit)" omdat hij iets bekender was. Een gast
/// ("feat. …", zie [_gast]) telt niet als onbekend, en een woord dat in [gevraagd] staat evenmin: dan
/// hoort het bij de naam van het liedje — "Sweet Dreams (Are Made of This)".
bool vreemdeStaart(String titel, {String gevraagd = ''}) {
  final eigen = {for (final w in _gewoneTekens(gevraagd).toLowerCase().split(_woordgrens)) w};
  // Zonder gasten en zonder filmnaam: zie [_delenZonderGast].
  for (final w in _staartZonderGast(titel).split(_woordgrens)) {
    if (w.isEmpty || _bekendeStaart.contains(w) || eigen.contains(w) || _getal.hasMatch(w)) continue;
    return true;
  }
  return false;
}

/// De titel zonder wat er over de uitvoering in staat: waarop twee versies hetzelfde LIEDJE zijn.
///
/// Een lidwoord vooraan telt niet: "Rhythm of the Night" en "The Rhythm Of The Night" zijn één
/// liedje (Corona, gemeten op 26-09-2026 — zonder "The" vond de radio het niet).
String basisTitel(String titel) {
  var x = _gewoneTekens(titel);
  final streep = x.indexOf(' - ');
  if (streep > 0) x = x.substring(0, streep);
  x = x.replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ').trim();
  x = x.replaceFirst(RegExp(r'^(the|a|an)\s+', caseSensitive: false), '');
  return _plat(x);
}

/// Alleen letters en cijfers, klein — ook die van een ander schrift (Кино, Μαρινέλλα). Anders werden
/// al zulke namen dezelfde lege sleutel: één liedje per radio, en elke artiest "de zaadartiest".
///
/// Altijd ALLE letters, na het vouwen van accenten: alleen terugvallen als er geen Latijnse letter is
/// maakte van "Би-2" een "2", en van "Часть 2" en "Глава 2" hetzelfde liedje (review van 26-09-2026).
String _plat(String s) => vouw(s).toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

/// Eén regel uit het aanbod: genoeg om te oordelen, niet meer.
typedef Aanbod = ({String artiest, String titel});

/// Hoeveel bewerkingen er per tien nummers hoogstens mogen staan.
///
/// Twee, en dat is een smaakoordeel dat ergens vandaan moet komen. Nul is te streng: van sommige
/// dansplaten bestáát alleen een clubversie, en die zou dan nooit meer langskomen. Vijf is wat er nu
/// gebeurt en dat was te veel.
const int kBewerkingPerTien = 2;

/// Duurt dit zo lang als een single? Tweeënhalve tot viereneenhalve minuut.
///
/// Gemeten op 26-09-2026: voor "Culture Beat — Mr. Vain" koos de radio de versie van 5:36, voor
/// "Sash! — Ecuador" 5:55 en voor "Technotronic — Pump Up The Jam" 5:22 — de gewone titel, maar de
/// albumversie. Singles en radio-edits uit die tijd zitten vrijwel altijd onder de vierenhalve
/// minuut. Zonder lengte (0) weten we het niet, en dat telt niet als single.
bool heeftSinglelengte(int seconden) => seconden >= 150 && seconden <= 270;

/// Eén uitvoering van een liedje, om uit te kiezen. [rang] is hoe bekend hij is (Deezer; hoger is
/// bekender, 0 als het niet bekend is), [seconden] hoe lang (0 als het niet bekend is).
typedef Versie = ({String titel, int rang, int seconden});

/// Welke van [versies] — allemaal hetzelfde liedje — de radio speelt. De index.
///
/// Eén keuze voor elke weg waarlangs de radio nummers krijgt: de Deezer-lijst ([kiesNummers]) en de
/// lijst van het model (`besteTreffer`). Met twee eigen volgordes kreeg hetzelfde liedje langs de
/// ene weg een andere uitvoering dan langs de andere (tweede beoordeling van 26-09-2026).
///
/// 1. **Singlelengte** ([heeftSinglelengte]) — behalve bij een titel die niets over de uitvoering
///    zegt en minder dan half zo bekend is als de bekendste: zonder die grens won een live-opname
///    uit Tokio van 3:55 (rang 29.823), kaal getiteld, van de Saturday Night Fever-versie van
///    "Stayin' Alive" (722.791). Een versie die zichzelf "Radio Edit" of "7" Version" noemt, telt
///    altijd: bij de eerste controle koos de radio in 9 van de 25 nummers de albumversie.
/// 2. **De bekendste** — maar een onbekende toevoeging ([vreemdeStaart], met [gevraagd] als de
///    gevraagde titel) wijkt voor een versie zonder, zolang die minstens half zo bekend is. Alleen
///    dan: bekendheid is juist wat een naam als "Einstein Konzept" niet heeft.
/// 3. Bij gelijke bekendheid de gewone titel vóór de radio-edit, en dan de eerste.
///
/// In stappen en niet paarsgewijs, zodat de volgorde van [versies] niets uitmaakt.
int kiesUitvoering(List<Versie> versies, {String gevraagd = ''}) {
  if (versies.length < 2) return 0;
  int hoogste(Iterable<int> ii) => ii.map((i) => versies[i].rang).reduce((a, b) => a > b ? a : b);
  final alle = [for (var i = 0; i < versies.length; i++) i];
  final max = hoogste(alle);
  bool single(int i) =>
      heeftSinglelengte(versies[i].seconden) &&
      (uitvoeringVan(versies[i].titel) == Uitvoering.radio || versies[i].rang * 2 >= max);
  final singles = [for (final i in alle) if (single(i)) i];
  final kandidaten = singles.isEmpty ? alle : singles;
  final top = hoogste(kandidaten);
  final kanshebbers = [for (final i in kandidaten) if (versies[i].rang * 2 >= top) i];
  final zonder = [
    for (final i in kanshebbers)
      if (!vreemdeStaart(versies[i].titel, gevraagd: gevraagd)) i
  ];
  final uit = zonder.isEmpty ? kanshebbers : zonder;
  return uit.reduce((a, b) {
    if (versies[b].rang != versies[a].rang) return versies[b].rang > versies[a].rang ? b : a;
    return uitvoeringVan(versies[b].titel).index < uitvoeringVan(versies[a].titel).index ? b : a;
  });
}

/// Welke regels uit [aanbod] de radio in mogen, in dezelfde volgorde.
///
/// Geeft INDEXEN terug en geen nieuwe lijst, zodat de aanroeper zijn eigen soort behoudt en er
/// niets van de gegevens verloren gaat onderweg.
///
/// [seconden] en [rang] mogen erbij, in dezelfde volgorde — zie [kiesUitvoering]. Deezer noemt
/// "Mr. Vain" ook in de albumversie van 5:36.
List<int> kiesNummers(List<Aanbod> aanbod,
    {int bewerkingPerTien = kBewerkingPerTien, List<int>? seconden, List<int>? rang}) {
  int op(List<int>? l, int i) => l == null || i >= l.length ? 0 : l[i];

  // 1. Per liedje één uitvoering, en dezelfde als het model zou krijgen: zie [kiesUitvoering]. Eerst
  //    had deze weg een eigen volgorde, en dan kreeg "Stayin' Alive" van Deezer een obscure
  //    live-opname en van het model de Saturday Night Fever-versie (tweede beoordeling van
  //    26-09-2026). Een bewerking alleen als er van dat liedje niets anders is.
  //    Per artiest zoals de afwisseling hem telt ([artiestSleutel]): "Freak Out" van "2 Fabiola" en
  //    van "2 Fabiola feat. Loredana" is één liedje (eindbeoordeling van 26-09-2026).
  final groepen = <String, List<int>>{};
  for (var i = 0; i < aanbod.length; i++) {
    if (nooitOpRadio(aanbod[i].titel)) continue;
    (groepen['${artiestSleutel(aanbod[i].artiest)}|${basisTitel(aanbod[i].titel)}'] ??= []).add(i);
  }
  final houden = <int>{};
  for (final g in groepen.values) {
    final gewoon = [for (final i in g) if (uitvoeringVan(aanbod[i].titel) != Uitvoering.bewerking) i];
    final uit = gewoon.isEmpty ? g : gewoon;
    houden.add(uit[kiesUitvoering(
        [for (final i in uit) (titel: aanbod[i].titel, rang: op(rang, i), seconden: op(seconden, i))])]);
  }

  // 2. En dan het rantsoen. De toets is `(bewerkingen + 1) * 10 <= (erin + 1) * perTien`: pas als er
  //    genoeg gewone nummers staan mag er weer een bewerking bij. Daardoor begint een radio nooit
  //    met een remix, ook al stond die vooraan.
  final uit = <int>[];
  var bewerkingen = 0;
  for (var i = 0; i < aanbod.length; i++) {
    if (!houden.contains(i)) continue;
    if (uitvoeringVan(aanbod[i].titel) == Uitvoering.bewerking) {
      if ((bewerkingen + 1) * 10 > (uit.length + 1) * bewerkingPerTien) continue;
      bewerkingen++;
    }
    uit.add(i);
  }
  return uit;
}

// ── Afwisseling ─────────────────────────────────────────────────────────────────────────────────

/// De losse artiesten van een naam: "Niels Destadsbader & Regi" is {nielsdestadsbader, regi}.
///
/// Voor het vergelijken van twee schrijfwijzen van een duo. Een voorvoegsel is daar geen goede maat
/// — gemeten op 26-09-2026 was "robins" (Robin S) een voorvoegsel van "robinschulz" (Robin Schulz),
/// en "sash" (Sash!) van "sasha". Hele delen wel.
Set<String> artiestDelen(String artiest) => {
      for (final d in artiestDelenTekst(artiest))
        if (_plat(d) case final k when k.isNotEmpty) k
    };

final _gastWoord = RegExp(r'\s(feat\.?|ft\.?|featuring|with|vs\.?|versus)\s', caseSensitive: false);
// Een schuine streep alleen met ruimte eromheen: "AC/DC" is één band, en viel anders uiteen in "ac"
// en "dc" (eindbeoordeling van 26-09-2026).
// En "and the" net als "& the": "Prince and The Revolution" is Prince, zoals "Prince & The
// Revolution" dat al was (vierde beoordeling van 26-09-2026 — anders speelde het zaad "Purple Rain"
// een tweede keer, en telde het niet mee voor het plafond van de zaadartiest).
final _samen =
    RegExp(r'\s+x\s+|\s*[&,+]\s*|\s+/\s*|\s*/\s+|\s+and\s+the\s+', caseSensitive: false);

/// De losse artiesten van een naam, als tekst, de hoofdartiest eerst.
///
/// In twee stappen: eerst "feat.", "with" en "vs", dan pas " x ", "&" en komma's. In één keer
/// splitste "Lil Nas X feat. Jack Harlow" op " X " en werd de hoofdartiest "Lil Nas" (review van
/// 26-09-2026); een X aan het eind van een naam heeft geen spatie erachter en blijft zo staan.
///
/// Een lidwoord vooraan valt weg: "The Smashing Pumpkins" en "Smashing Pumpkins" zijn één band
/// (kwaliteitscontrole van 26-09-2026 — de radio vond "1979" niet).
List<String> artiestDelenTekst(String artiest) => [
      for (final stuk in artiest.toLowerCase().split(_gastWoord))
        for (final d in stuk.split(_samen))
          if (d.trim().replaceFirst(RegExp(r'^the\s+'), '') case final t when t.isNotEmpty) t
    ];

/// Zijn dit dezelfde artiest, of een duo met hem erin? Zie [artiestDelen].
///
/// En als elk woord van de kortste naam een heel woord is van de langste — maar alleen bij minstens
/// twee woorden: "Hall & Oates" is "Daryl Hall & John Oates", "Queen" is geen "Queen Latifah", en
/// "Robin S" geen "Robin Schulz" (de "s" is daar geen woord).
///
/// Maar niet als de langste naam er een naspeler van maakt: "Smashing Pumpkins Tribute" en "The
/// Nirvana Experience" zijn andere artiesten die dezelfde liedjes zingen, en de coverwacht kijkt
/// alleen naar de titel (eindbeoordeling van 26-09-2026). Zie [_naspeler].
bool zelfdeArtiest(String a, String b) {
  if (artiestDelen(a).intersection(artiestDelen(b)).isNotEmpty) return true;
  // Zonder lidwoorden en "and": "Hall and Oates" is {hall, oates}, net als "Hall & Oates" — eerst
  // telde "and" als een woord van de naam en vond Soulseeks meest gewone spelling niets (derde
  // beoordeling van 26-09-2026). "of" blijft: zie hieronder.
  List<String> woordenVan(String deel) => [
        for (final w in deel.split(RegExp(r'\s+')))
          if (_plat(w) case final k when k.isNotEmpty && !_lidwoord.contains(k)) k
      ];
  Set<String> woorden(String s) => {for (final d in artiestDelenTekst(s)) ...woordenVan(d)};
  final wa = woorden(a), wb = woorden(b);
  final kortIsA = wa.length <= wb.length;
  final kort = kortIsA ? wa : wb, lang = kortIsA ? wb : wa;
  if (kort.length < 2 || !lang.containsAll(kort)) return false;
  // Echte bands die zo heten als een naspeler ([_echteBand]) zijn gewoon die artiest.
  if (_echteBand.contains(artiestSleutel(kortIsA ? b : a))) return true;
  if (lang.difference(kort).any(_naspeler.contains)) return false;
  // "Rumours of Fleetwood Mac": een "of" dat de kortste naam niet heeft, is een naspeler die zegt
  // wíe hij naspeelt.
  if (lang.contains('of') && !kort.contains('of')) return false;
  // En per deel van de langste naam dat iets met de kortste deelt, hoogstens één woord erbij — en
  // dan vooraan (een voornaam: "Daryl Hall") of "band"/"group". "The Australian Pink Floyd Show"
  // heeft er twee; "Bon Jovi Forever", "The Pink Floyd Project" en "Fleetwood Mac UK" hebben er één
  // áchter, en zijn andere groepen (tweede en derde beoordeling van 26-09-2026). Een deel dat niets
  // deelt telt niet mee: "Nick Cave and the Bad Seeds" is Nick Cave.
  for (final deel in (kortIsA ? b : a).toLowerCase().split(_deelGrens)) {
    final w = woordenVan(deel);
    if (!w.any(kort.contains)) continue;
    final erbij = [for (var i = 0; i < w.length; i++) if (!kort.contains(w[i])) i];
    if (erbij.length > 1) return false;
    if (erbij.length == 1) {
      final i = erbij.single;
      final vooraan = i < w.indexWhere(kort.contains);
      if (!vooraan && !_groepWoord.contains(w[i])) return false;
      // Een land vooraan is geen voornaam: "Australian Pink Floyd", "UK Foo Fighters" (vierde
      // beoordeling van 26-09-2026).
      if (vooraan && _landWoord.contains(w[i])) return false;
    }
  }
  return true;
}

final _deelGrens = RegExp(
    r'\s(feat\.?|ft\.?|featuring|with|vs\.?|versus|and)\s|\s+x\s+|\s*[&,+]\s*|\s+/\s*|\s*/\s+');
const Set<String> _lidwoord = {'the', 'a', 'an', 'and', 'de', 'het'};
const Set<String> _groepWoord = {'band', 'group'};
const Set<String> _landWoord = {
  'australian', 'aussie', 'uk', 'us', 'usa', 'brit', 'british', 'american', 'dutch', 'german',
  'italian', 'canadian', 'belgian', 'french', 'swedish', 'irish', 'scottish', 'danish',
};

/// Bands die een [_naspeler]-woord in hun eigen naam dragen, als [artiestSleutel]. "The Jimi Hendrix
/// Experience" is Jimi Hendrix, en geen naspeler van hem (vierde beoordeling van 26-09-2026).
const Set<String> _echteBand = {
  'jimihendrixexperience', 'davebrubeckquartet', 'modernjazzquartet', 'electriclightorchestra',
  'yellowmagicorchestra', 'orchestralmanoeuvresinthedark', 'budapestfestivalorchestra',
};

/// Woorden waarmee een naam zegt dat hij andermans muziek speelt. Zie [zelfdeArtiest].
///
/// Geen "band": "Dave Matthews" is de Dave Matthews Band.
const Set<String> _naspeler = {
  'tribute', 'tributes', 'karaoke', 'cover', 'covers', 'experience', 'orchestra', 'quartet',
  'ensemble', 'players', 'singers', 'allstars', 'lullaby', 'show', 'story', 'legacy', 'revival',
  'legends', 'salute', 'homage', 'celebration',
};

/// Is dit het liedje waar de radio vanaf begon — en dus niet nog eens welkom?
///
/// Van de zaadartiest zelf altijd: dat is hetzelfde nummer in een andere uitvoering. Van een ander
/// alleen bij een titel die zo eigen is dat het een cover moet zijn — minstens drie woorden. Tori
/// Amos' "Smells Like Teen Spirit" hoort niet in een Nirvana-radio, maar "Alive" van Sia wel in een
/// Pearl Jam-radio en "Creep" van Stone Temple Pilots in een Radiohead-radio: andere liedjes met
/// dezelfde naam (eindbeoordeling van 26-09-2026 — eerst viel elke gelijke titel weg).
bool isZaadlied(String artiest, String titel, {required String zaadArtiest, required String zaadTitel}) {
  final t = basisTitel(titel);
  if (t.isEmpty || t != basisTitel(zaadTitel)) return false;
  if (zelfdeArtiest(artiest, zaadArtiest)) return true;
  return _titelWoorden(zaadTitel) >= 3;
}

/// Hoeveel woorden de naam van het liedje heeft, zonder wat er over de uitvoering achter staat.
int _titelWoorden(String titel) {
  var x = _gewoneTekens(titel);
  final streep = x.indexOf(' - ');
  if (streep > 0) x = x.substring(0, streep);
  // Zonder apostrof: "Don't Cry" is twee woorden, geen drie ("don", "t", "cry").
  x = x.replaceAll(_haakjes, ' ').replaceAll("'", '');
  return RegExp(r'[\p{L}\p{N}]+', unicode: true).allMatches(x).length;
}

/// Wie een nummer maakt, zoals de afwisseling dat telt: "2 Fabiola feat. Loredana" is 2 Fabiola.
///
/// De EERSTE van [artiestDelen]: ook "2 Fabiola & Loredana" en "2 Fabiola x Loredana" zijn 2 Fabiola —
/// eerst telde alleen "feat.", en dan ontliep een duo het plafond van de zaadartiest.
String artiestSleutel(String artiest) {
  final delen = artiestDelen(artiest);
  return delen.isEmpty ? '' : delen.first;
}

/// Tussen twee nummers van dezelfde artiest staan er minstens drie anderen.
const int kArtiestAfstand = 4;

/// De artiest waar de radio omheen gebouwd is: hoogstens één op de tien plekken, en minstens twee.
///
/// Gemeten op 26-09-2026, radio vanaf "Freak Out" van 2 Fabiola: Deezer levert voor de zaadartiest
/// vijftien toppers en daarnaast nog een handvol in de artiestenradio, dus een derde van het plan was
/// 2 Fabiola, twee keer vlak na elkaar. Saber: *"ik hoor nu al heel de tijd 2fabiola, mag maar niet
/// heel de tijd."* Een radio "vanaf" iemand is een radio in zijn buurt, geen verzamelalbum van hem.
const int kZaadPerTien = 1;

/// En van elke andere artiest hoogstens drie.
const int kMaxPerArtiest = 3;

/// Welke regels de radio in mogen en in welke volgorde, zodat er afwisseling in zit.
///
/// Twee dingen:
///
/// 1. **Een plafond per artiest**, in de volgorde waarin ze erin gingen: wie te vaak voorkomt verliest
///    zijn láátste nummers. [zaad] is de artiest waar de radio omheen gebouwd is en krijgt
///    [kZaadPerTien]; de rest [maxPerArtiest]. [al] telt mee — wat er al in de radio staat — zodat
///    een nakomer het plafond niet opnieuw kan beginnen.
/// 2. **Een minimale afstand**: een artiest komt pas terug als er [afstand] − 1 anderen tussen
///    stonden. [ervoor] is wat er direct vóór deze lijst klinkt — bij een radio vanaf een nummer is
///    dat het nummer zelf. Lukt het niet meer (alleen nog één artiest over), dan de regel die het
///    langst weg is: dat is zo min mogelijk dicht op elkaar, en er valt niets extra weg.
///
/// Geeft INDEXEN terug, net als [kiesNummers]. Zonder toeval: het plan is al geschud, en de eerste
/// die past wint.
List<int> spreidArtiesten(
  List<String> artiesten, {
  String? zaad,
  Iterable<String> al = const [],
  Iterable<String> ervoor = const [],
  int afstand = kArtiestAfstand,
  int maxPerArtiest = kMaxPerArtiest,
}) {
  final sleutels = [for (final a in artiesten) artiestSleutel(a)];
  final z = zaad == null ? '' : artiestSleutel(zaad);
  final geteld = <String, int>{};
  for (final a in al) {
    final s = artiestSleutel(a);
    geteld[s] = (geteld[s] ?? 0) + 1;
  }
  final totaal = artiesten.length + geteld.values.fold(0, (a, b) => a + b);
  var zaadMax = (totaal * kZaadPerTien + 9) ~/ 10;
  if (zaadMax < 2) zaadMax = 2;

  // 1. Het plafond.
  final rest = <int>[];
  for (var i = 0; i < sleutels.length; i++) {
    final s = sleutels[i];
    if (s.isNotEmpty) {
      final n = geteld[s] ?? 0;
      if (n >= (s == z ? zaadMax : maxPerArtiest)) continue;
      geteld[s] = n + 1;
    }
    rest.add(i);
  }

  // 2. De afstand.
  final laatst = <String, int>{};
  var plek = 0;
  for (final a in ervoor) {
    laatst[artiestSleutel(a)] = plek++;
  }
  final uit = <int>[];
  while (rest.isNotEmpty) {
    var kies = 0;
    var verst = -1;
    for (var k = 0; k < rest.length; k++) {
      final s = sleutels[rest[k]];
      final vorige = s.isEmpty ? null : laatst[s];
      final weg = vorige == null ? afstand : plek - vorige;
      if (weg >= afstand) {
        kies = k;
        break;
      }
      if (weg > verst) {
        verst = weg;
        kies = k;
      }
    }
    final i = rest.removeAt(kies);
    if (sleutels[i].isNotEmpty) laatst[sleutels[i]] = plek;
    plek++;
    uit.add(i);
  }
  return uit;
}

// ── Wat je al hebt ──────────────────────────────────────────────────────────────────────────────

/// Mag een nummer dat je AL HEBT deze radioplek vullen?
///
/// Tot nu toe telde artiest + titel zonder haakjes: "Freak Out" werd gevuld met je eigen "Freak Out
/// ('97 Remix)", en "Move On Baby" met de albumversie van *U Got 2 Know* — 4:51, terwijl de single
/// die Deezer bedoelde 3:40 duurt (gemeten 26-09-2026). Nu moet het dezelfde soort uitvoering zijn,
/// en ongeveer even lang. [speling] is die van de bibliotheek (`sameRecordingSlack`), zodat de radio
/// en `LibraryStore.fileOfRecording` hetzelfde antwoord geven op "heb je dit al".
bool eigenPastOpPlek({
  required String plekTitel,
  int? plekSeconden,
  required String eigenTitel,
  int? eigenSeconden,
  required int speling,
}) {
  if (uitvoeringVan(eigenTitel) == Uitvoering.bewerking &&
      uitvoeringVan(plekTitel) != Uitvoering.bewerking) {
    return false;
  }
  final a = plekSeconden ?? 0, b = eigenSeconden ?? 0;
  return a <= 0 || b <= 0 || (a - b).abs() <= speling;
}

/// Welk van je eigen nummers is het liedje [titel] van [artiest], als je een radio vanaf een
/// aanbeveling start? De index in [eigen], of null.
///
/// Dezelfde artiest ([zelfdeArtiest]), hetzelfde liedje ([basisTitel]), en een uitvoering die op de
/// plek past ([eigenPastOpPlek]): wie "Radio hieruit" op "Freak Out" drukt, wil niet beginnen met je
/// "Freak Out ('97 Remix)". Nooit iets wat nooit op de radio hoort ([nooitOpRadio]).
int? eigenZaadIndex(List<({String artiest, String titel, int? seconden})> eigen, String artiest,
    String titel,
    {int? seconden, required int speling}) {
  final t = basisTitel(titel);
  if (t.isEmpty) return null;
  for (var i = 0; i < eigen.length; i++) {
    final e = eigen[i];
    if (basisTitel(e.titel) != t || !zelfdeArtiest(e.artiest, artiest) || nooitOpRadio(e.titel)) continue;
    if (eigenPastOpPlek(
        plekTitel: titel,
        plekSeconden: seconden,
        eigenTitel: e.titel,
        eigenSeconden: e.seconden,
        speling: speling)) {
      return i;
    }
  }
  return null;
}

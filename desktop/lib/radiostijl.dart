/// Past dit nummer bij de radio — in stijl en in tijdvak — volgens meer dan één bron?
///
/// **Waarom dit er is.** Saber op 26-09-2026: *"maar altijd met deezer vergelijken ?? er zijn toch
/// andere bronnen ook e, dit is gelimiteerd aan deezer, maar moet combinatie zijn van AI, discogs
/// eventueel, the audiodatabase."* Tot nu toe besliste Deezer alleen: wat er in de radio kwam, en
/// daarmee ook wat er níét bij hoorde. Zo kwamen er in een radio vanaf "Freak Out" van 2 Fabiola
/// (1997, Euro House) nummers van Niels Destadsbader (2021), Donna Summer (1979) en Dimitri Vegas &
/// Like Mike (2010-en) terecht.
///
/// **Wat elke bron weet — gemeten op 26-09-2026.**
///
///     Discogs     per NUMMER: jaar en stijl van de uitgaven. Freak Out → 1997, Electronic, Euro House.
///                 "De Wereld Draait Voor Jou" → 2021, maar óók Electronic/Eurodance (met Regi).
///     TheAudioDB  per ARTIEST: genre. 2 Fabiola en Cappella "Euro Dance", Milk Inc. en Kate Ryan
///                 "Dance", Niels Destadsbader "Pop", Donna Summer "R&B".
///
/// Stijl alleen is dus niet genoeg — Niels had Discogs' Eurodance-label — en het tijdvak alleen ook
/// niet. Samen wel. De regels, en verder niets:
///
/// 1. **Tijdvak.** Weten we het jaar van het zaadnummer en van dit nummer, dan mogen ze hoogstens
///    [kTijdvakSpeling] jaar uit elkaar liggen.
/// 2. **Stijl.** Zet GEEN enkele bron dit nummer in de stijlfamilie van het zaad, terwijl er wél een
///    bron iets over zegt, dan valt het af. Eén bron die "ja" zegt is genoeg: TheAudioDB noemt
///    Vengaboys misschien "Pop", Discogs zet ze bij Electronic — en dan horen ze erbij.
/// 3. **Niets bekend is geen reden om te weigeren.** Een radio die stil valt omdat een bron een
///    obscure artiest niet kent, is erger dan een nummer dat er net naast zit.
///
/// Het rekenwerk staat hier zonder IO, zodat het na te rekenen is; [Stijlboek] haalt de feiten op
/// en onthoudt ze op schijf.
library;

import 'dart:convert';
import 'dart:io';

import 'radiokeuze.dart' show artiestDelenTekst, vouw;

/// Grove families van genres. Grof met opzet: "Euro House" en "Happy Hardcore" zijn voor een radio
/// dezelfde familie, "Pop" en "Euro Dance" niet.
enum Stijlfamilie { dans, popsoul, rock, hiphop, schlager, latin, jazz, klassiek, country, reggae }

/// Welke woorden bij welke familie horen, in volgorde van toetsen. Specifiek vóór algemeen: "Euro
/// Pop" moet "dans" worden voordat "pop" eraan toekomt.
const List<(String, Stijlfamilie)> _woorden = [
  // Eerst wat een dans-, rock- of hiphopwoord BEVAT maar iets anders is. Gemeten op 26-09-2026:
  // Sean Paul staat op 7 van 10 Discogs-uitgaven als "Dancehall", en dat werd "dans".
  ('dancehall', Stijlfamilie.reggae),
  ('rocksteady', Stijlfamilie.reggae),
  ('ragga', Stijlfamilie.reggae),
  ('hardcore hip', Stijlfamilie.hiphop),
  ('post-hardcore', Stijlfamilie.rock),
  ('melodic hardcore', Stijlfamilie.rock),
  ('hardcore punk', Stijlfamilie.rock),
  ('garage rock', Stijlfamilie.rock),
  ('rhythm & blues', Stijlfamilie.popsoul),
  ('trip hop', Stijlfamilie.dans),
  ('euro', Stijlfamilie.dans),
  ('hands up', Stijlfamilie.dans),
  ('gabber', Stijlfamilie.dans),
  ('jumpstyle', Stijlfamilie.dans),
  ('makina', Stijlfamilie.dans),
  ('breakbeat', Stijlfamilie.dans),
  ('breaks', Stijlfamilie.dans),
  ('big beat', Stijlfamilie.dans),
  ('jungle', Stijlfamilie.dans),
  ('garage', Stijlfamilie.dans),
  ('downtempo', Stijlfamilie.dans),
  ('drum and bass', Stijlfamilie.dans),
  ('grunge', Stijlfamilie.rock),
  ('thrash', Stijlfamilie.rock),
  ('swing', Stijlfamilie.jazz),
  ('folk', Stijlfamilie.country),
  ('dance', Stijlfamilie.dans),
  ('electronic', Stijlfamilie.dans),
  ('electro', Stijlfamilie.dans),
  ('house', Stijlfamilie.dans),
  ('techno', Stijlfamilie.dans),
  ('trance', Stijlfamilie.dans),
  ('hardcore', Stijlfamilie.dans),
  ('hardstyle', Stijlfamilie.dans),
  ('hi nrg', Stijlfamilie.dans),
  ('hi-nrg', Stijlfamilie.dans),
  ('italo', Stijlfamilie.dans),
  ('eurobeat', Stijlfamilie.dans),
  ('dubstep', Stijlfamilie.dans),
  ('drum n bass', Stijlfamilie.dans),
  ('drum & bass', Stijlfamilie.dans),
  ('edm', Stijlfamilie.dans),
  ('hip hop', Stijlfamilie.hiphop),
  ('hip-hop', Stijlfamilie.hiphop),
  ('rap', Stijlfamilie.hiphop),
  ('schlager', Stijlfamilie.schlager),
  ('levenslied', Stijlfamilie.schlager),
  ('reggae', Stijlfamilie.reggae),
  ('latin', Stijlfamilie.latin),
  ('jazz', Stijlfamilie.jazz),
  ('classical', Stijlfamilie.klassiek),
  ('country', Stijlfamilie.country),
  ('rock', Stijlfamilie.rock),
  ('metal', Stijlfamilie.rock),
  ('punk', Stijlfamilie.rock),
  ('alternative', Stijlfamilie.rock),
  ('indie', Stijlfamilie.rock),
  ('r&b', Stijlfamilie.popsoul),
  ('rnb', Stijlfamilie.popsoul),
  ('soul', Stijlfamilie.popsoul),
  ('funk', Stijlfamilie.popsoul),
  ('disco', Stijlfamilie.popsoul),
  ('pop', Stijlfamilie.popsoul),
];

/// De familie van één genre- of stijlnaam, of null als het niets zegt ("Stage & Screen", "").
Stijlfamilie? familieVan(String? naam) {
  final s = (naam ?? '').toLowerCase().trim();
  if (s.isEmpty) return null;
  for (final (w, f) in _woorden) {
    if (s.contains(w)) return f;
  }
  return null;
}

/// Alle families die een rijtje namen noemt — de genres en stijlen van een Discogs-uitgave samen.
Set<Stijlfamilie> familiesVan(Iterable<String> namen) => {
      for (final n in namen)
        if (familieVan(n) case final f?) f
    };

/// Binnen rock: alternatief of klassiek? Op de stijlen van één uitgave; null als ze het niet zeggen.
///
/// Gemeten in de kwaliteitscontrole van 26-09-2026: een radio vanaf "Smells Like Teen Spirit" liet
/// Bon Jovi en Bryan Adams door, want "rock" is rock. Op Discogs' stijlen gesplitst landen alle
/// achttien goede buren (Pearl Jam, Soundgarden, Pixies, Hole…) bij alternatief, en Bon Jovi, Bryan
/// Adams, Metallica en Guns N' Roses bij klassiek.
///
/// Een uitgave die van allebei iets zegt, is 'gemengd': "Grunge, Hard Rock, Heavy Metal" is hoe
/// Discogs Alice in Chains, Candlebox en Collective Soul beschrijft, en op een meerderheid van losse
/// stijlen werden ze klassiek en vielen ze uit een Nirvana-radio (eindbeoordeling van 26-09-2026).
/// Gemengd telt wél mee in [meerderheidTak] — als stem voor geen van beide.
String? rockTak(Iterable<String> stijlen) {
  var alt = 0, klassiek = 0;
  for (final s in stijlen) {
    final x = s.toLowerCase();
    if (_altStijl.hasMatch(x)) {
      alt++;
    } else if (_klassiekStijl.hasMatch(x)) {
      klassiek++;
    }
  }
  if (alt > 0 && klassiek > 0) return 'gemengd';
  if (alt > 0) return 'alternatief';
  return klassiek > 0 ? 'klassiek' : null;
}

// Geen "Art Rock" en geen "Experimental": dat is Pink Floyd en Roxy Music net zo goed als
// Radiohead, en die heeft ook "Alternative Rock" (derde beoordeling van 26-09-2026).
final _altStijl = RegExp(r'grunge|alternative|indie|punk|noise|britpop|stoner|'
    r'funk metal|shoegaze|emo|lo-fi');
final _klassiekStijl = RegExp(r'hard rock|glam|heavy metal|thrash|speed metal|aor|soft rock|pop rock|'
    r'blues rock|ballad|arena rock|classic rock|southern rock');

/// Is deze uitgave volgens Discogs een bootleg? Die tellen niet mee voor het jaar of de stijl — zie
/// `DiscogsService.nummerUitgaven`.
bool isBootleg(Iterable<String> formaten) =>
    formaten.any((f) => f.toLowerCase().contains('unofficial'));

/// De tak van één uitgave voor [meerderheidTak]: [rockTak], en een rockuitgave die van geen tak iets
/// zegt ("Prog Rock", "Psychedelic Rock") telt als 'gemengd' — een stem voor geen van beide.
///
/// Anders besliste de minderheid: Pink Floyd met acht uitgaven "Prog Rock" en twee "Prog Rock, Art
/// Rock" werd alternatief op twee van twee, en viel uit een Led Zeppelin-radio (derde beoordeling
/// van 26-09-2026).
String? takVanUitgave(DiscogsUitgave u) {
  final t = rockTak(u.stijlen);
  if (t != null) return t;
  final rock = [...u.genres, ...u.stijlen].any((g) => g.toLowerCase().contains('rock'));
  return rock ? 'gemengd' : null;
}

/// De tak van een nummer: de tak die vaker voorkomt dan de andere, en op minstens een DERDE van
/// alle rockuitgaven staat. Een gemengde of takloze uitgave ([takVanUitgave]) telt mee in dat totaal.
///
/// Geijkt op Discogs, 26-09-2026 — uitgaven klassiek / alternatief / gemengd:
///
///     Bon Jovi — Keep the Faith          4 / 0 / 5    klassiek (en dus uit een Nirvana-radio)
///     Pink Floyd — Comfortably Numb      4 / 0 / 6    klassiek
///     Alice in Chains — Would?           0 / 3 / 7    geen: past overal
///     Nirvana, Pearl Jam, Soundgarden    alles alternatief
///
/// Eerst woog alleen wie een tak had, en dan besliste één zuivere uitgave tussen twintig gemengde
/// (tweede beoordeling). Daarna een meerderheid van ALLES, en toen kwam Bon Jovi weer door (vier van
/// negen is geen helft — gemeten, niet bedacht). Een derde scheidt ze allebei.
String? meerderheidTak(List<String?> perUitgave) {
  final alt = perUitgave.where((t) => t == 'alternatief').length;
  final kl = perUitgave.where((t) => t == 'klassiek').length;
  final rock = alt + kl + perUitgave.where((t) => t == 'gemengd').length;
  if (alt > kl && alt * 3 >= rock) return 'alternatief';
  if (kl > alt && kl * 3 >= rock) return 'klassiek';
  return null;
}

/// De familie die op de MEESTE uitgaven staat, als dat er één is; anders niets.
///
/// Niet alles bij elkaar, en dat was de fout. Gemeten op 26-09-2026: één "Electronic"-remixsingle
/// tussen tien uitgaven maakte "Wannabe", "Wonderwall" en "Smells Like Teen Spirit" dansmuziek — 16
/// van 22 niet-dansnummers uit hetzelfde tijdvak kwamen zo door de keuring. Op de meerderheid bleven
/// alle 29 dansnummers binnen. Een gelijke stand zegt niets, en dan beslist TheAudioDB.
Set<Stijlfamilie> meerderheid(List<Set<Stijlfamilie>> perUitgave) {
  final tel = <Stijlfamilie, int>{};
  for (final u in perUitgave) {
    for (final f in u) {
      tel[f] = (tel[f] ?? 0) + 1;
    }
  }
  if (tel.isEmpty) return const {};
  final hoogste = tel.values.reduce((a, b) => a > b ? a : b);
  final winnaars = [
    for (final e in tel.entries)
      if (e.value == hoogste) e.key
  ];
  return winnaars.length == 1 ? {winnaars.single} : const {};
}

/// Hoeveel jaar een nummer van het zaadnummer mag liggen.
///
/// Acht: vanaf Freak Out (1997) is dat 1989 tot 2005 — de hele eurodance en de nadagen ervan, en
/// niet de disco van 1979 of de EDM van 2013.
const int kTijdvakSpeling = 8;

/// Wat we van het zaadnummer weten.
typedef Zaadstijl = ({Stijlfamilie? familie, int? jaar});

/// Wat de bronnen van één nummer zeggen. [families] is alles wat een bron noemde; leeg is "niets
/// bekend".
typedef Nummerstijl = ({Set<Stijlfamilie> families, int? jaar});

/// Het oordeel, met de reden in gewone taal — voor het logboek.
typedef Stijloordeel = ({bool mag, String waarom});

/// Past [n] bij [zaad]? Zie de drie regels bovenaan.
Stijloordeel keurStijl(Zaadstijl zaad, Nummerstijl n, {int speling = kTijdvakSpeling}) {
  final zj = zaad.jaar, j = n.jaar;
  if (zj != null && j != null && (zj - j).abs() > speling) {
    return (mag: false, waarom: 'uit $j, het zaad is van $zj');
  }
  final zf = zaad.familie;
  if (zf != null && n.families.isNotEmpty && !n.families.contains(zf)) {
    return (mag: false, waarom: 'stijl ${n.families.map((f) => f.name).join('/')}, niet ${zf.name}');
  }
  return (mag: true, waarom: n.families.isEmpty && j == null ? 'niets bekend' : 'past');
}

/// Het vroegste echte jaartal uit een rij. Een heruitgave uit 2015 van een plaat uit 1994 zegt niets
/// over het nummer; de eerste uitgave wel.
int? vroegsteJaar(Iterable<int?> jaren) {
  int? min;
  for (final j in jaren) {
    if (j == null || j < 1900) continue;
    if (min == null || j < min) min = j;
  }
  return min;
}

/// De titel zonder wat tussen haakjes staat en zonder de staart na " - ": waarop Discogs een nummer
/// vindt. "It's My Life (2011 Version)" is "It's My Life".
String kaleTitel(String titel) {
  var x = titel;
  final streep = x.indexOf(' - ');
  if (streep > 0) x = x.substring(0, streep);
  return x.replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Gaat deze Discogs-uitgave ("Snap! - Rhythm Is A Dancer") over [artiest]? Voor de vrije zoekvraag,
/// die ook andermans platen met dezelfde woorden teruggeeft. Het deel vóór " - " moet de artiest
/// bevatten, zonder leestekens.
///
/// Een HELE naam, en geen deel ervan. Gemeten op 26-09-2026: Discogs' artiestveld vond voor "Sash!"
/// ook "Leon Sash" (jazz, 1968), en met "bevat" werd "Stay" van Sash! daardoor een nummer uit 1968.
/// Discogs schrijft een naamvariant met een sterretje ("Snap*") en een naamgenoot met een nummer
/// ("Oasis (2)"); die tellen wel als dezelfde naam.
bool uitgaveVanArtiest(String discogsTitel, String artiest) {
  String plat(String s) => vouw(s)
      .toLowerCase()
      .replaceAll(RegExp(r'\s*\(\d+\)'), '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
  final delen = artiestDelenTekst(artiest);
  final a = delen.isEmpty ? '' : plat(delen.first);
  if (a.isEmpty) return false;
  final streep = discogsTitel.indexOf(' - ');
  final wie = streep > 0 ? discogsTitel.substring(0, streep) : discogsTitel;
  for (final deel in artiestDelenTekst(wie.replaceAll(RegExp(r'\s+and\s+', caseSensitive: false), ' & '))) {
    if (plat(deel) == a) return true;
  }
  return false;
}

/// De [hoeveel] stijlen die het vaakst voorkomen, de meest genoemde eerst.
List<String> meesteStijlen(Iterable<String> stijlen, {int hoeveel = 3}) {
  final tel = <String, int>{};
  for (final s in stijlen) {
    final t = s.trim();
    if (t.isNotEmpty) tel[t] = (tel[t] ?? 0) + 1;
  }
  final lijst = tel.keys.toList()..sort((a, b) => tel[b]!.compareTo(tel[a]!));
  return lijst.take(hoeveel).toList();
}

/// Wat Discogs over één nummer zegt: per gevonden uitgave het jaar, de genres en de stijlen.
typedef DiscogsUitgave = ({int? jaar, List<String> genres, List<String> stijlen});

/// De uitgaven van de twee zoekvragen samen — zie `DiscogsService.nummerUitgaven` — of null als de
/// tweede geen antwoord gaf ([tweede] is null: een 429, een 5xx, een time-out).
///
/// Dan ook NIET de halve lijst van de eerste. Die was bij Mudhoney precies het live-album van 2018,
/// en een [Stijlboek] bewaart wat hij krijgt: "Touch Me I'm Sick" stond dan voorgoed als 2018
/// geboekt, en viel uit elke radio van 1991 (eindbeoordeling van 26-09-2026). Null wordt niet
/// onthouden, dus de volgende keer wordt het opnieuw gevraagd.
List<DiscogsUitgave>? samenUitgaven(List<DiscogsUitgave> eerst, List<DiscogsUitgave>? tweede) =>
    tweede == null ? null : [...eerst, ...tweede];

/// Welke regels het geheugen van [Stijlboek] volgt. Omhoog zodra een regel verandert die bepaalt wat
/// er onthouden wordt — [rockTak], [meerderheid], de filters in `DiscogsService.nummerUitgaven` —
/// want wat onder de oude regels opgezocht is, wordt anders nooit meer opnieuw bekeken.
///
/// 2: [rockTak] telt alleen nog zuivere uitgaven, en een half antwoord van Discogs wordt niet meer
/// bewaard (26-09-2026).
const int kStijlboekVersie = 2;

/// De feiten ophalen en onthouden. De bronnen zijn haken, zodat een toets ze kan invullen.
///
/// Onthouden op schijf, en ook wat NIET gevonden werd: een obscure artiest die TheAudioDB niet kent,
/// kent hij morgen ook niet, en elke vraag kost daar drie seconden (zie `EnrichmentService`).
class Stijlboek {
  Stijlboek({
    required this.bestand,
    required this.audioDbGenre,
    required this.discogsNummer,
    this.deezerJaar,
  });

  /// Waar het geheugen staat.
  final File bestand;

  /// Het genre van een artiest volgens TheAudioDB, of null.
  final Future<String?> Function(String artiest) audioDbGenre;

  /// De uitgaven waarop Discogs dit nummer vindt, of null als Discogs niet mee kan doen.
  final Future<List<DiscogsUitgave>?> Function(String artiest, String titel) discogsNummer;

  /// Het jaar van het Deezer-album waar dit nummer op staat, of null. De LAATSTE bron: een
  /// verzamelaar uit 2015 met een nummer uit 1994 geeft hier 2015, dus alleen als Discogs het nummer
  /// niet kent en het model geen jaar noemde. Gemeten op 26-09-2026: "Kayzo — El Diablo" en "Sandy
  /// Beach — Man! I Feel Like A Woman!" kenden Discogs en TheAudioDB geen van beide; Deezer zei 2026.
  final Future<int?> Function(String artiest, String titel)? deezerJaar;

  // Eén keer inlezen, ook als acht keuringen tegelijk beginnen — anders bouwt elk zijn eigen kaart en
  // raken antwoorden kwijt (review van 26-09-2026). En één schrijver tegelijk op het .tmp-bestand.
  Future<Map<String, dynamic>>? _laden;
  Future<void> _schrijfBeurt = Future<void>.value();

  // Een geheugen van een oudere [kStijlboekVersie]: dan zijn de regels voor een NUMMER veranderd, en
  // een nummer dat al eens opgezocht was zou anders nooit meer onder de nieuwe regels vallen. Alleen
  // die ("n:") weg: het genre van een artiest en het jaar van een Deezer-album zijn nog waar, en elke
  // vraag aan TheAudioDB kost drie seconden — na een update liep zo elke keuring tegen zijn
  // tijdslimiet, en een keuring zonder antwoord laat alles door (tweede beoordeling van 26-09-2026).
  Future<Map<String, dynamic>> _lees() => _laden ??= () async {
        try {
          final j = jsonDecode(await bestand.readAsString());
          if (j is Map<String, dynamic>) {
            if (j['_versie'] != kStijlboekVersie) {
              j.removeWhere((k, _) => k.startsWith('n:'));
              j['_versie'] = kStijlboekVersie;
            }
            return j;
          }
        } catch (_) {/* geen geheugen is een leeg geheugen */}
        return <String, dynamic>{'_versie': kStijlboekVersie};
      }();

  Future<void> _bewaar() {
    final beurt = _schrijfBeurt.then((_) async {
      try {
        final g = await _lees();
        await bestand.parent.create(recursive: true);
        final tmp = File('${bestand.path}.tmp');
        await tmp.writeAsString(jsonEncode(g));
        await tmp.rename(bestand.path);
      } catch (_) {/* het oordeel staat al; onthouden is een gemak */}
    });
    _schrijfBeurt = beurt;
    return beurt;
  }

  // Zonder één Latijnse letter de letters van dat schrift, anders valt alles op één lege sleutel.
  static String _sleutel(String s) =>
      vouw(s).toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

  /// De familie van een artiest volgens TheAudioDB. Null als hij het niet weet.
  ///
  /// Een vraag die al loopt wordt gedeeld: twee keuringen voor dezelfde artiest stellen hem één keer.
  /// Zonder dat stuurde een keuring na een time-out een TWEEDE vraag achter in dezelfde rij.
  Future<Stijlfamilie?> artiest(String naam) {
    final k = 'a:${_sleutel(naam)}';
    // Blok en geen pijl: `remove` geeft de future terug die whenComplete zelf maakt, en daarop
    // wachten loopt vast (zie `pijlvorm-in-whencomplete-loopt-vast`).
    return _bezigArtiest[k] ??= _artiest(naam, k).whenComplete(() {
      _bezigArtiest.remove(k);
    });
  }

  final Map<String, Future<Stijlfamilie?>> _bezigArtiest = {};
  final Map<String, Future<Nummerstijl>> _bezigNummer = {};

  Future<Stijlfamilie?> _artiest(String naam, String k) async {
    final g = await _lees();
    if (g.containsKey(k)) return _alsFamilie(g[k]);
    String? genre;
    try {
      genre = await audioDbGenre(naam);
    } catch (_) {
      return null; // niet onthouden: dit was geen antwoord maar een storing
    }
    final f = familieVan(genre);
    g[k] = f?.name ?? '';
    await _bewaar();
    return f;
  }

  /// Wat Discogs over één nummer zegt.
  Future<Nummerstijl> nummer(String artiest, String titel) {
    final k = 'n:${_sleutel(artiest)}|${_sleutel(titel)}';
    return _bezigNummer[k] ??= _nummer(artiest, titel, k).whenComplete(() {
      _bezigNummer.remove(k);
    });
  }

  Future<Nummerstijl> _nummer(String artiest, String titel, String k) async {
    final g = await _lees();
    final zit = g[k];
    if (zit is Map) {
      return (
        families: {
          for (final f in (zit['f'] as List? ?? const []))
            if (_alsFamilie(f) case final x?) x
        },
        jaar: (zit['j'] as num?)?.toInt(),
      );
    }
    List<DiscogsUitgave>? uit;
    try {
      uit = await discogsNummer(artiest, titel);
    } catch (_) {
      uit = null;
    }
    if (uit == null) return (families: const <Stijlfamilie>{}, jaar: null);
    final n = (
      families: meerderheid([
        for (final u in uit) familiesVan([...u.genres, ...u.stijlen])
      ]),
      jaar: vroegsteJaar([for (final u in uit) u.jaar]),
    );
    g[k] = {
      'f': [for (final f in n.families) f.name],
      'j': n.jaar,
      's': meesteStijlen([for (final u in uit) ...u.stijlen]),
      't': meerderheidTak([for (final u in uit) takVanUitgave(u)]),
    };
    await _bewaar();
    return n;
  }

  /// De rocktak van dit nummer ([rockTak], meerderheid over de uitgaven), of null. Alleen uit het
  /// geheugen: vraag eerst [nummer].
  Future<String?> tak(String artiest, String titel) async {
    final zit = (await _lees())['n:${_sleutel(artiest)}|${_sleutel(titel)}'];
    return zit is Map ? zit['t'] as String? : null;
  }

  /// De stijlnamen die Discogs het vaakst bij dit nummer zet ("Euro House", "Trance") — voor de
  /// vraag aan het taalmodel. Alleen uit het geheugen: vraag eerst [nummer].
  Future<List<String>> stijlnamen(String artiest, String titel) async {
    final zit = (await _lees())['n:${_sleutel(artiest)}|${_sleutel(titel)}'];
    return zit is Map ? [for (final x in (zit['s'] as List? ?? const [])) '$x'] : const [];
  }

  Future<int?> _deezerJaar(String artiest, String titel) async {
    final bron = deezerJaar;
    if (bron == null) return null;
    final g = await _lees();
    final k = 'd:${_sleutel(artiest)}|${_sleutel(titel)}';
    if (g.containsKey(k)) return (g[k] as num?)?.toInt();
    int? j;
    try {
      j = await bron(artiest, titel);
    } catch (_) {
      return null; // geen antwoord is geen jaartal; niet onthouden
    }
    g[k] = j;
    await _bewaar();
    return j;
  }

  static Stijlfamilie? _alsFamilie(Object? v) {
    for (final f in Stijlfamilie.values) {
      if (f.name == v) return f;
    }
    return null;
  }

  /// Wat we van het zaad weten: de artiestfamilie volgens TheAudioDB (anders die van Discogs) en
  /// het jaar — uit je eigen tags als je het nummer hebt, anders van Discogs.
  ///
  /// De stijl eerst van het NUMMER bij Discogs, en pas dan van de artiest bij TheAudioDB. Gemeten op
  /// 26-09-2026: TheAudioDB noemt Aqua "Pop", Discogs zet "Barbie Girl" op 10 van 16 uitgaven bij
  /// Electronic. Met TheAudioDB eerst verwierp een Barbie Girl-radio 17 van 25 eurodancenummers.
  Future<Zaadstijl> zaad(String artiest, String? titel, {int? eigenJaar}) async {
    Stijlfamilie? f;
    int? jaar = eigenJaar != null && eigenJaar > 1900 ? eigenJaar : null;
    if (titel != null && titel.trim().isNotEmpty) {
      final n = await nummer(artiest, titel);
      f = n.families.length == 1 ? n.families.first : null;
      // Het VROEGSTE van je tag en Discogs: een tag zegt vaak het jaar van de verzamelaar waar je het
      // nummer van hebt ("90s Hits", 2012), en dan zou de radio de echte jaren negentig weren.
      jaar = vroegsteJaar([jaar, n.jaar]);
      // En zonder tag en zonder Discogs het Deezer-album: een radio vanaf een aanbeveling heeft geen
      // tag, en zonder jaar van het zaad is er helemaal geen tijdvakkeuring (tweede beoordeling van
      // 26-09-2026).
      jaar ??= await _deezerJaar(artiest, titel);
    }
    f ??= await this.artiest(artiest);
    return (familie: f, jaar: jaar);
  }

  /// Het oordeel over één radioplek.
  ///
  /// Eerst Discogs, want dat weet het jaar én vaak de stijl in één vraag, en dan is TheAudioDB — drie
  /// seconden per vraag — niet meer nodig. Alleen als Discogs de stijl van het zaad niet noemt, wordt
  /// ook de artiest bij TheAudioDB nagevraagd: één bron die "ja" zegt is genoeg.
  ///
  /// [zaadTak]: bij een rockzaad de tak ervan ([rockTak]). Zegt Discogs van dit nummer de ándere tak,
  /// dan valt het af; weet het niets, dan niet.
  Future<Stijloordeel> keur(String artiest, String titel, Zaadstijl zaad,
      {int? jaarHint, String? zaadTak}) async {
    final n = await nummer(artiest, titel);
    final jaar = n.jaar ?? jaarHint ?? (zaad.jaar == null ? null : await _deezerJaar(artiest, titel));
    final eerst = keurStijl(zaad, (families: const {}, jaar: jaar));
    if (!eerst.mag) return eerst;
    final zf = zaad.familie;
    final Stijloordeel o;
    if (zf == null || n.families.contains(zf)) {
      o = keurStijl(zaad, (families: n.families, jaar: jaar));
    } else {
      final a = await this.artiest(artiest);
      o = keurStijl(zaad, (families: {...n.families, if (a != null) a}, jaar: jaar));
    }
    if (!o.mag || zf != Stijlfamilie.rock || zaadTak == null) return o;
    final t = await tak(artiest, titel);
    if (t != null && t != zaadTak) return (mag: false, waarom: 'rock, maar $t en niet $zaadTak');
    return o;
  }
}

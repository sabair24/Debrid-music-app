/// Of een bestand van Soulseek echt het nummer is dat de radio vroeg.
///
/// **Waarom dit bestaat — gemeten op 26-09-2026.** Een radio vanaf "Freak Out ('97 Remix)" van
/// 2 Fabiola. Van de 27 nummers die hij in `Singles` neerzette, waren er zes een heel ander nummer
/// dan hun naam:
///
///     gevraagd                                 wat er in het bestand zat
///     RMB – Redemption                         Masayoshi Soken – Beyond Redemption (FFXIV)
///     Pat Krimson – When The Lights Go Down    Boondox – K7-Lethal (album "Krimson Crow")
///     Pat Krimson – We Will Meet Again         A Sound of Thunder – The Golden Age
///     2 Fabiola – I'm on Fire                  Porter Robinson – I'm On Fire (Original Mix)
///     2 Fabiola – Break Away                   Broken Fabiola – Deliverance Through Grace
///     RMB – Matisse                            Matisse – Por Si Te Lo Preguntas
///
/// De radio koos op kwaliteit alleen — het beste formaat, het grootste bestand — en keek nergens
/// naar titel, artiest of lengte. Vond de zoekvraag met titel niets, dan zocht hij op de artiest
/// alleen, en "Pat Krimson" vindt dan "Krimson". Daar kwam de horrorcore tussen de eurodance
/// vandaan, niet van de aanbeveling.
///
/// **En de versie.** Saber: "ik wil vooral originele nummers horen, niet teveel mixen". Een gewone
/// plek krijgt dus geen Extended, Club of Remix, ook als de zoekvraag er een oplevert, en het bestand
/// moet ongeveer zo lang zijn als de uitvoering die de catalogus noemt. Aan die lengte zie je ook
/// een albumversie die net zo heet als de single: Move On Baby van Cappella is op de single 3:40 en
/// op *U Got 2 Know* 4:51.
///
/// **Waarom niet `fileOffersTitle`.** Die is voor de radio te streng in één richting: hij weigert een
/// "Radio Edit"-bestand voor een gewone plek, en bij dance uit de jaren negentig is de radio-edit
/// juist de versie die iedereen kent. De bouwstenen zijn dezelfde — [fileWords], [baseName] — en de
/// regel "wat de bestandsnaam méér zegt, moet van de artiest of de mappen zijn" ook.
library;

import 'organize.dart' show TrackTags, baseName, fileWords;
import 'radiokeuze.dart'
    show Uitvoering, artiestDelenTekst, nooitOpRadio, uitvoeringVan, vouw, zelfdeArtiest;

/// Woorden die in een artiestnaam niets zeggen over WIE het is. Anders telt "DJ Dado" als gevonden
/// in elk pad met "dj" erin, en "The Mackenzie" in elk pad met "the". "Project": Soulseek schrijft
/// "Captain Hollywood" voor "Captain Hollywood Project".
const Set<String> _loos = {
  'the', 'dj', 'mc', 'feat', 'ft', 'featuring', 'and', 'en', 'de', 'het', 'van', 'vs', 'versus',
  'with', 'met', 'inc', 'band', 'orchestra', 'presents', 'pres', 'project',
};

final _haakjes = RegExp(r'[\(\[]([^\)\]]*)[\)\]]');
final _scheiding = RegExp(r'[\\/]');


/// Woorden die een bestandsnaam mag dragen zonder dat het een ander nummer wordt: hoe de peer zijn
/// bestand noemt ("Radio Edit", "Remastered", "Official Audio"), geen titel. Wat een BEWERKING
/// aankondigt staat hier niet in — "extended", "club", "remix" — en valt dus af op een gewone plek.
const Set<String> _neutraal = {
  'radio', 'edit', 'version', 'single', 'original', 'album', 'mix', 'remaster', 'remastered',
  'official', 'audio', 'video', 'hq', 'hd', 'cd', 'cd1', 'cd2', 'disc', 'track', 'flac', 'mp3',
  'bonus', 'airplay', 'inch',
};

/// Woorden in een MAPNAAM die zeggen dat wat erin staat niet het origineel is. Gemeten op 26-09-2026
/// (review op echte Soulseek-namen): "No Limit (Remixes)\03 - No Limit.flac", "Encore - Live And
/// Direct\05 - Hyper Hyper.flac", "Karaoke Hits\…". Hele woorden: "Alive" is geen live.
///
/// Ook wat de titelkant ([uitvoeringVan]) al geen origineel noemt: een akoestische, unplugged,
/// demo- of sessieplaat (eindbeoordeling van 26-09-2026 — "MTV Unplugged in New York\…" en "BBC
/// Sessions\…" kwamen er zo door). "Live" staat hier NIET: zie [_mapLive].
const Set<String> _mapVerraadt = {
  'remix', 'remixes', 'extended', 'karaoke', 'tribute', 'instrumental', 'instrumentals',
  'cover', 'covers', 'acapella', 'acappella', 'acapellas', 'acoustic', 'unplugged', 'demo',
  'demos', 'session', 'sessions', 'rehearsal', 'rehearsals', 'outtakes', 'megamix',
};

/// Een live-plaat aan zijn mapnaam: het hele woord "live" — "Live After Death", "Live (1992)",
/// "Familiar To Millions (Live)", "Live And Direct" — en "in concert", "concert", "on stage" of
/// KISS' "Alive!".
///
/// Behalve waar "live" een woord is van een studiotitel: Hole's "Live Through This" is een
/// studioplaat, en daar viel elk nummer van af (eindbeoordeling van 26-09-2026). Eerst ving een
/// lijstje vormen ("Live At", "(Live)") de live-platen, en toen glipten "Live After Death", "Live
/// Killers" en "AC-DC - Live (1992)" erdoor (tweede beoordeling). Nu is het andersom: live, tenzij.
/// En "Long Live …" is nooit live: Rainbow's "Long Live Rock 'n' Roll", "Long Live the Angels"
/// (derde beoordeling). Wat van de artiest of de titel zelf is, haalt [_zonderEigen] er eerst uit.
final _mapLive = RegExp(
    r"(?<!long )\blive\b(?!\s+(through this|forever|and let die|and die|to tell|wire|your life|"
    r"like you were dying|it up|it out|a little|and learn|while we're young|to win|and breathe)\b)|"
    r"\bin concert\b|\bconcerts?\b|\bon stage\b|\balive\s*(!|ii+\b|(19|20)\d\d\b)",
    caseSensitive: false);

final _jaarVooraan = RegExp(r'^[\(\[]?(19|20)\d\d[\)\]]?\s*[-–—_.]?\s*');
final _lidwoordVooraan = RegExp(r'^the\s+');

/// [mappen] zonder de naam van de artiest en zonder de titel: de band Live in "Live - Throwing
/// Copper\…", de titel in "Live and Let Die (Single)\…". Een naam van één woord alleen als hele map
/// of vooraan gevolgd door een streep — "Live\Live At The Paradiso\…" blijft een live-plaat, en
/// "Oasis\Familiar To Millions (Live)\…" ook voor "Live Forever". Een langere naam ("2 Live Crew")
/// overal: die kan niets anders betekenen. Een jaartal of "The" vooraan telt niet mee, en elk soort
/// streepje wel ("Live – Throwing Copper", "(1994) Live - …") — derde beoordeling van 26-09-2026.
String _zonderEigen(String mappen, String artiest, String titel) {
  final a = _gewoneTekens(artiest).toLowerCase().trim().replaceFirst(_lidwoordVooraan, '');
  final t = _gewoneTekens(_titelZonderStaart(titel)).toLowerCase().replaceAll(_haakjes, ' ').trim();
  final vooraan = a.isEmpty ? null : RegExp('^${RegExp.escape(a)}' r'\s*[-–—_]+\s*');
  final stukken = [
    for (final m in _gewoneTekens(mappen).toLowerCase().split(_scheiding))
      _zonderArtiestVooraan(m.trim(), a, vooraan)
  ];
  var x = stukken.join('/');
  if (a.contains(' ')) x = _zonderZin(x, a);
  return _zonderZin(x, t);
}

String _zonderArtiestVooraan(String map, String a, RegExp? vooraan) {
  if (vooraan == null) return map;
  final kaal = map.replaceFirst(_jaarVooraan, '').replaceFirst(_lidwoordVooraan, '');
  // "Live (Band)", "Live [US]": wat Soulseek achter een naam zet om hem uit elkaar te houden.
  if (kaal == a || kaal.replaceFirst(_staartHaakjes, '') == a) return '';
  final m = vooraan.firstMatch(kaal);
  final uit = m == null ? map : kaal.substring(m.end);
  // En "The Best Of Live", "Greatest Hits by Live": dat is de naam, geen live-plaat (vierde
  // beoordeling van 26-09-2026).
  return uit.replaceAll(RegExp(r'\b(of|by)\s+' '${RegExp.escape(a)}' r'(?![a-z0-9])'), ' ');
}

final _staartHaakjes = RegExp(r'\s*[\(\[][^\)\]]*[\)\]]\s*$');

/// [s] (klein geschreven) zonder [zin] waar die als hele woorden in staat. Alleen de eerste keer
/// als [eenmaal]: in "Tribute - Tenacious D Tribute.mp3" is de tweede "Tribute" van de peer.
String _zonderZin(String s, String zin, {bool eenmaal = false}) {
  if (zin.isEmpty) return s;
  final r = RegExp('(?<![a-z0-9])${RegExp.escape(zin)}(?![a-z0-9])');
  return eenmaal ? s.replaceFirst(r, ' ') : s.replaceAll(r, ' ');
}

/// De bestandsnaam zonder de titel en de artiest, voor [nooitOpRadio]. "01 - Tribute.flac" van
/// Tenacious D is geen tribute — en werd zo toch geweigerd: achter de streep stond "Tribute", en dat
/// las de coverwacht als een aankondiging (derde controle van 26-09-2026). Wat er dan nog staat,
/// "(Karaoke Version)", is wel van de peer. Elk één keer: de plek van de titel, niet elk woord dat
/// er toevallig op lijkt.
String _naamZonderEigen(String naam, String artiest, String titel) {
  final t = _gewoneTekens(_titelZonderStaart(titel)).toLowerCase().replaceAll(_haakjes, ' ').trim();
  final a = _gewoneTekens(artiest).toLowerCase().trim();
  return _zonderZin(_zonderZin(_gewoneTekens(naam).toLowerCase(), t, eenmaal: true), a, eenmaal: true);
}

String _gewoneTekens(String s) => s.replaceAll(RegExp('[‘’´`]'), "'").replaceAll('_', ' ');

/// Hoeveel seconden een radiobestand van de catalogus mag afwijken. Eén getal voor "mag dit bestand
/// op deze plek" én "heb je dit al" — met twee getallen (15 en 5) werd een bewaard radionummer dat
/// 6 tot 15 seconden afweek bij elke volgende radio opnieuw gehaald (review van 26-09-2026).
const int kRadioSpeling = 15;

final _cijfers = RegExp(r'^\d+$');
final _extensie = RegExp(r'\.[A-Za-z0-9]{2,4}$');

/// Wat de woorden kapotmaakte: een weggelaten apostrof ("Its My Life" tegen "It's My Life") en een
/// accent ("Desenchantee" tegen "Désenchantée"). Beide weg vóór het splitsen.
String _normaal(String s) => vouw(s).replaceAll(RegExp("['’‘´`]"), '');

/// De woorden van [s], zoals [fileWords] ze ziet, maar dan na [_normaal]. Zonder één Latijnse letter
/// de woorden in dat schrift — anders was een Russisch nummer nooit te vinden.
Set<String> _woorden(String s) {
  final w = fileWords(_normaal(s));
  if (w.isNotEmpty) return w;
  return {
    for (final x in s.toLowerCase().split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)))
      if (x.length > 1) x
  };
}

/// Alle tokens, ook die van één teken — voor "Robin S".
List<String> _tokens(String s) => [
      for (final x in _normaal(s).toLowerCase().split(RegExp('[^a-z0-9]+')))
        if (x.isNotEmpty) x
    ];

String _sleutel(String s) => _normaal(s).toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

/// De hoofdartiest: zonder gasten.
String _hoofd(String artiest) {
  final delen = artiestDelenTekst(artiest);
  return delen.isEmpty ? '' : delen.first;
}

/// De woorden van de hoofdartiest, zonder woorden als "DJ" en "The".
Set<String> _artiestWoorden(String artiest) => _woorden(_hoofd(artiest))..removeAll(_loos);

/// Staat de hoofdartiest in dit pad?
///
/// Drie manieren, en elk om een gemeten reden:
/// - Heeft de naam een LOSSE LETTER ("Robin S"), dan moet die reeks letterlijk in het pad staan.
///   Anders was "Robin Schulz\Show Me Love.flac" van Robin S (review van 26-09-2026).
/// - Anders alle woorden van de naam in het pad ("Krimson Crow" is geen Pat Krimson),
/// - of de naam aan elkaar geschreven ergens in het pad: "2Unlimited", "Modo", "Twenty4Seven".
bool _artiestInPad(String artiest, String pad) {
  final hoofd = _hoofd(artiest);
  final tokens = [
    for (final t in _tokens(hoofd))
      if (!_loos.contains(t)) t
  ];
  if (tokens.isEmpty) return true;
  final padTokens = _tokens(pad.replaceAll(_scheiding, ' '));
  if (tokens.any((t) => RegExp(r'^[a-z]$').hasMatch(t))) {
    for (var i = 0; i + tokens.length <= padTokens.length; i++) {
      var ja = true;
      for (var k = 0; k < tokens.length; k++) {
        if (padTokens[i + k] != tokens[k]) {
          ja = false;
          break;
        }
      }
      if (ja) return true;
    }
    return false;
  }
  final woorden = _artiestWoorden(artiest);
  if (woorden.isNotEmpty && woorden.every(_woorden(pad.replaceAll(_scheiding, ' ')).contains)) {
    return true;
  }
  final k = tokens.join();
  if (k.length >= 4 && _sleutel(pad).contains(k)) return true;
  // En een stuk van het pad dat volgens de Deezer-kant dezelfde artiest is ([zelfdeArtiest]): een
  // duo onder zijn korte naam. "Hall & Oates - Greatest Hits\…" voor "Daryl Hall & John Oates" viel
  // hier af, terwijl de lijst van het model hem wel zo noemt (eindbeoordeling van 26-09-2026).
  for (final map in pad.split(_scheiding)) {
    for (final stuk in map.replaceAll(_extensie, '').split(' - ')) {
      if (stuk.trim().isNotEmpty && zelfdeArtiest(stuk, artiest)) return true;
    }
  }
  return false;
}

/// De woorden van [s] zonder wat er tussen haakjes staat.
Set<String> _kaleWoorden(String s) => _woorden(s.replaceAll(_haakjes, ' '));

/// De titel zonder wat hij over de uitvoering zegt: haakjes, en een staart na " - ".
///
/// Alleen voor een CATALOGUStitel. Een bestandsnaam heet vaak "Artiest - Titel", en daar knipt dit
/// de titel juist weg.
String _titelZonderStaart(String titel) {
  final streep = titel.indexOf(' - ');
  return streep > 0 ? titel.substring(0, streep) : titel;
}

/// Kondigt de bestandsnaam tussen haakjes een bewerking aan? Alleen de haakjes: op de hele naam zou
/// "live" in "Alive" en "cover" in "Discover" een bewerking vinden.
bool _bewerkingInHaakjes(String naam) {
  final binnen = _haakjes.allMatches(naam).map((m) => m.group(1) ?? '').join(' ').trim();
  return binnen.isNotEmpty && uitvoeringVan('x ($binnen)') == Uitvoering.bewerking;
}

/// Mag dit Soulseek-bestand op de radioplek "[artiest] – [titel]"?
///
/// [seconden] is wat de catalogus zegt, [padSeconden] wat de peer meldt; zonder een van de twee
/// telt de lengte niet mee.
bool radioBestandKlopt({
  required String artiest,
  required String titel,
  int? seconden,
  required String pad,
  int? padSeconden,
  int speling = kRadioSpeling,
}) {
  final naam = baseName(pad);
  final mappen = pad.substring(0, pad.length - naam.length);
  final gewonePlek = uitvoeringVan(titel) != Uitvoering.bewerking;

  // 1. Een gewone plek krijgt geen bewerking — niet in de naam, en niet als de MAP het zegt. En een
  //    cover of karaoke nergens.
  if (gewonePlek && _bewerkingInHaakjes(naam)) return false;
  if (nooitOpRadio(_naamZonderEigen(naam.replaceAll(_extensie, ''), artiest, titel))) return false;
  final mapWoorden = _woorden(mappen.replaceAll(_scheiding, ' '));
  // Zonder de woorden van de artiest en de titel zelf: "The Acoustic" of "Demo Song" zeggen dan
  // niets over de map. Voor live gaat het preciezer — zie [_zonderEigen].
  final eigenWoorden = {..._woorden(artiest), ..._woorden(titel)};
  if (gewonePlek &&
      (mapWoorden.difference(eigenWoorden).any(_mapVerraadt.contains) ||
          _mapLive.hasMatch(_zonderEigen(mappen, artiest, titel)) ||
          mappen.toLowerCase().contains('in the style of'))) {
    return false;
  }

  // 2. De artiest staat in het pad — zie [_artiestInPad].
  if (!_artiestInPad(artiest, pad)) return false;

  // 3. De titel staat in de naam.
  final titelWoorden = _kaleWoorden(_titelZonderStaart(titel));
  if (titelWoorden.isEmpty) return false;
  final naamWoorden = _kaleWoorden(naam);
  if (titelWoorden.intersection(naamWoorden).length / titelWoorden.length < .75) return false;

  // 4. Wat de naam méér zegt, hoort bij de artiest, de mappen of de gevraagde titel, of het zegt iets
  //    over het bestand zelf. Zo valt "Beyond Redemption" af voor "Redemption" — "beyond" staat
  //    nergens anders — en "Freak Out - Extended Mix" voor "Freak Out". Een versiewoord in de map
  //    verklaart niets.
  // De artiest aan elkaar geschreven ("Modo", "2Unlimited") is ook een woord van de artiest.
  final aaneen = _sleutel(_hoofd(artiest));
  final bekend = {
    ..._woorden(artiest),
    aaneen,
    ..._woorden(titel),
    ...mapWoorden.difference(_mapVerraadt),
    ..._neutraal,
  };
  if (naamWoorden
      .difference(titelWoorden)
      .any((w) => !bekend.contains(w) && !_cijfers.hasMatch(w))) {
    return false;
  }

  // 4b. En in het STUK van de naam waar de titel staat, mag er niets bij dat een andere versie
  //     aankondigt — ook niet als een map het "verklaart". Gezien op 26-09-2026: voor "Scooter —
  //     Friends (Single Edit)" kwam "Scooter - Friends Turbo - 02 - Friends Turbo.flac" binnen, uit
  //     de map "Scooter - Friends Turbo": een latere nieuwe versie. Stukken zijn wat " - " scheidt;
  //     een albumnaam staat in een eigen stuk ("Cappella - U Got 2 Know - 05 - Move On Baby").
  final stukken = naam.replaceAll(_extensie, '').replaceAll(_haakjes, ' ').split(' - ');
  var titelStuk = <String>{};
  var meest = 0;
  for (final st in stukken) {
    final w = _woorden(st);
    final n = w.intersection(titelWoorden).length;
    if (n > meest) {
      meest = n;
      titelStuk = w;
    }
  }
  final eigen = {..._woorden(artiest), aaneen, ..._woorden(titel), ..._neutraal};
  if (titelStuk
      .difference(titelWoorden)
      .any((w) => !eigen.contains(w) && !_cijfers.hasMatch(w))) {
    return false;
  }

  // 5. Ongeveer zo lang als de uitvoering die de catalogus noemt.
  return !radioLengteSpreektTegen(seconden, padSeconden, speling: speling);
}

/// Liggen de lengte van de catalogus en die van het bestand meer dan [speling] seconden uit elkaar?
/// Zonder een van de twee valt er niets tegen te spreken.
///
/// Ook ná het halen, op de echte lengte: een peer meldt die lang niet altijd, en dan telde stap 5
/// van [radioBestandKlopt] niet mee (review van 26-09-2026).
bool radioLengteSpreektTegen(int? seconden, int? bestand, {int speling = kRadioSpeling}) {
  final a = seconden ?? 0, b = bestand ?? 0;
  return a > 0 && b > 0 && (a - b).abs() > speling;
}

/// Mist het binnengehaalde bestand een artiest of een titel in zijn tags?
///
/// Dan staat het als "Onbekende artiest" met de bestandsnaam als titel in de rij en in je
/// bibliotheek — gezien op 26-09-2026 bij "Got To Move Your Body" en "The Mackenzie Feat. Jessy -
/// Innocence". De radio schrijft ze er dan zelf in.
bool radioTagsOntbreken(TrackTags? tags) =>
    tags == null || tags.artist.trim().isEmpty || tags.title.trim().isEmpty;

/// Kan de app de tags van dit bestand schrijven? Alleen FLAC en MP3 — zie `writeTagFields`.
bool radioTagsSchrijfbaar(String pad) {
  final p = pad.toLowerCase();
  return p.endsWith('.flac') || p.endsWith('.mp3');
}

/// Onbruikbaar voor de radio: geen artiest of titel in de tags, en die zijn er ook niet in te zetten.
///
/// Gemeten op 26-09-2026, 17:17: "01 Haddaway - What Is Love.aiff" landde zonder tags, en stond
/// daarna als "What Is Love (7" Mix) — Onbekende artiest" in de rij. De app schrijft alleen FLAC en
/// MP3; een AIFF of WAV zonder tags blijft zo voor altijd naamloos in je bibliotheek.
bool radioZonderTags(TrackTags? tags, String pad) =>
    radioTagsOntbreken(tags) && !radioTagsSchrijfbaar(pad);

/// Zeggen de tags van het binnengehaalde bestand dat het een ander nummer is — of een andere versie?
///
/// Het tweede net, ná het halen: een peer kan een bestand goed noemen en iets anders laten
/// klinken. Alleen wat er STAAT telt — een bestand zonder tags is hiermee niet af te keuren. Zegt de
/// tagtitel "(Hannover Rmx)" terwijl de plek om het origineel vroeg, dan is het een andere versie.
bool radioTagsSprekenTegen(String artiest, String titel, TrackTags? tags) {
  if (tags == null) return false;
  final tagArtiest = _woorden(tags.artist)..removeAll(_loos);
  final gevraagd = _artiestWoorden(artiest);
  if (tagArtiest.isNotEmpty && gevraagd.isNotEmpty && !gevraagd.any(tagArtiest.contains)) {
    return true;
  }
  final tagTitel = _kaleWoorden(tags.title);
  final titelWoorden = _kaleWoorden(_titelZonderStaart(titel));
  if (tagTitel.isNotEmpty && titelWoorden.isNotEmpty) {
    if (titelWoorden.intersection(tagTitel).length / titelWoorden.length < .5) return true;
  }
  if (tags.title.trim().isNotEmpty &&
      uitvoeringVan(titel) != Uitvoering.bewerking &&
      uitvoeringVan(tags.title) == Uitvoering.bewerking) {
    return true;
  }
  return false;
}

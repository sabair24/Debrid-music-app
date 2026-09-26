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
import 'radiokeuze.dart' show Uitvoering, artiestDelenTekst, nooitOpRadio, uitvoeringVan, vouw;

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
const Set<String> _mapVerraadt = {
  'remix', 'remixes', 'extended', 'live', 'karaoke', 'tribute', 'instrumental', 'instrumentals',
  'cover', 'covers', 'acapella', 'acappella', 'acapellas',
};

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
  return k.length >= 4 && _sleutel(pad).contains(k);
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
  if (nooitOpRadio(naam.replaceAll(_extensie, ''))) return false;
  final mapWoorden = _woorden(mappen.replaceAll(_scheiding, ' '));
  if (gewonePlek &&
      (mapWoorden.any(_mapVerraadt.contains) ||
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

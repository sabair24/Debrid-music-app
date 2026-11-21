/// Verzamelingen: een tweede bibliotheek naast de gewone, voor muziek die je apart wilt (21-11-2026).
///
/// Saber, na een radio vanaf Nancy Wilson: *"de radio dat ik geluister heb is echt een speciefieke genre, die zouden
/// eigenlijk in een aparte afspeelijst kunnen in plaats van in men bibliotheek tussen men andere liedjes ... niet een
/// genre die ik wil tussen men bibliotheek maar specifiek als ik er zin in heb"*. Zijn keuzes: een tweede bibliotheek
/// (eigen albums, artiesten, nummers), vindbaar maar niet gemengd, een eigen map op de pc, en een nummer mag ook in
/// meer dan één verzameling (als verwijzing).
///
/// **De map.** Elke verzameling heeft haar map onder `DebridMusic Downloads\Verzamelingen\<Naam>\`, en een bestand
/// houdt daarin het pad dat het had: `DebridMusic Downloads\Albums\X\Y\z.flac` wordt
/// `DebridMusic Downloads\Verzamelingen\Vocal jazz\Albums\X\Y\z.flac`. Wat van buiten de downloadmap komt, staat met
/// zijn volle oude pad onder `_buiten\`.
///
/// **Waarom het oude pad.** Het id van een nummer is het pad ten opzichte van de muziekwortel (`lan/ids.dart`), en
/// daaraan hangen je favorieten, je afspeellijsten, wat je draaide en je duimen. Een verhuizing die het id veranderde,
/// zou dat allemaal losmaken. Het id rekent daarom met [relZonderVerzameling]: hetzelfde bestand, hetzelfde id, waar
/// het ook staat.
library;

/// De downloadmap onder de muziekwortel (zie `DownloadManager.downloadsRoot` in online.dart).
const String downloadsMapNaam = 'DebridMusic Downloads';

/// De map onder de downloadmap met één map per verzameling.
const String verzamelMap = 'Verzamelingen';

/// Binnen een verzameling: wat van buiten de downloadmap kwam, met zijn volle oude pad. Een liggend streepje vooraan,
/// zoals de andere mappen van de app (`_dubbel`, `_keuring`): zo heet geen enkele map van muziek.
const String verzamelBuitenMap = '_buiten';

/// De verzameling van een bestand, uit zijn pad [rel] ten opzichte van de muziekwortel (met `/`), of null.
String? verzamelingUitRel(String rel) {
  final delen = rel.split('/');
  // downloadmap / Verzamelingen / naam / (minstens) het bestand
  if (delen.length < 4) return null;
  if (delen[0].toLowerCase() != downloadsMapNaam.toLowerCase()) return null;
  if (delen[1].toLowerCase() != verzamelMap.toLowerCase()) return null;
  final naam = delen[2].trim();
  return naam.isEmpty ? null : naam;
}

/// De verzameling van een bestand op [pad] (absoluut, op de pc), zonder de muziekwortel te kennen: het eerste stuk
/// `…/DebridMusic Downloads/Verzamelingen/<naam>/…` in het pad. Null op een toestel, waar het pad een stroomadres is.
String? verzamelingUitPad(String pad) {
  final delen = pad.replaceAll('\\', '/').split('/');
  for (var i = 0; i + 3 < delen.length; i++) {
    if (delen[i].toLowerCase() == downloadsMapNaam.toLowerCase() && delen[i + 1].toLowerCase() == verzamelMap.toLowerCase()) {
      final naam = delen[i + 2].trim();
      return naam.isEmpty ? null : naam;
    }
  }
  return null;
}

/// Het pad dat een bestand had vóór het naar zijn verzameling verhuisde ([relInVerzameling]); daarop rust zijn id.
/// Geen verzameling: [rel] zelf.
String relZonderVerzameling(String rel) {
  if (verzamelingUitRel(rel) == null) return rel;
  final delen = rel.split('/');
  final rest = delen.sublist(3);
  if (rest.length > 1 && rest.first.toLowerCase() == verzamelBuitenMap.toLowerCase()) return rest.sublist(1).join('/');
  return [delen[0], ...rest].join('/');
}

/// Waar een bestand met pad [rel] (ten opzichte van de muziekwortel) komt te staan in verzameling [naam]. Het
/// omgekeerde van [relZonderVerzameling], ook voor een bestand dat al in een andere verzameling staat.
String relInVerzameling(String rel, String naam) {
  final oud = relZonderVerzameling(rel).split('/');
  if (oud.length > 1 && oud.first.toLowerCase() == downloadsMapNaam.toLowerCase()) {
    return [oud.first, verzamelMap, naam, ...oud.sublist(1)].join('/');
  }
  return [downloadsMapNaam, verzamelMap, naam, verzamelBuitenMap, ...oud].join('/');
}

/// Een naam die als mapnaam kan dienen: zonder de tekens die Windows weigert, zonder punt of spatie op het eind, en
/// nooit leeg. "AC/DC & co." wordt "AC-DC & co".
String verzamelMapnaam(String naam) {
  var s = naam.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '-').trim();
  s = s.replaceAll(RegExp(r'[. ]+$'), '');
  return s.isEmpty ? 'Verzameling' : s;
}

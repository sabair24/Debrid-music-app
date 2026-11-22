/// "Vanzelf op genre" (Saber, 21-11-2026, bij de verzamelingen): een radio die begint bij muziek die je apart houdt,
/// stelt zelf voor om wat je ervan houdt ook apart te houden — in plaats van tussen je andere liedjes.
///
/// Alleen een voorstel: het radiopaneel toont het met één knop, en zonder tik verandert er niets. Drie redenen, de
/// sterkste eerst:
///
/// 1. **De artiest.** Staat de zaadartiest al in een verzameling, en daar meer dan in je gewone bibliotheek? Dan die
///    verzameling. Een radio vanaf Madeleine Peyroux hoort bij "Vocal jazz" als je haar daar hebt.
/// 2. **Het genre.** Draagt een verzameling vooral het genre van het zaad (minstens [kGenreMinstens] nummers en
///    [kGenreAandeel] ervan), en je bibliotheek minder? Dan die verzameling. Op het genre zoals het in je bestanden
///    staat, en niet op de familie: "Swing" en "Vocal Jazz" zijn allebei jazz, maar Saber wees de bigband op 21-11-2026
///    juist níet bij Vocal jazz in.
/// 3. **Iets nieuws.** Komt het genre van het zaad bijna niet voor in je bibliotheek (hoogstens [kZeldzaamAandeel] van
///    minstens [kZeldzaamVanaf] nummers), en is het een echt genre en geen verzamelbak als "Pop" of "Various"? Dan een
///    nieuwe verzameling met die naam.
///
/// Geen IO: alleen tellen, zodat het na te rekenen is.
library;

import 'radiokeuze.dart' show artiestSleutel;

/// Een nummer zoals het voorstel het ziet.
typedef VoorstelNummer = ({String artiest, String? genre});

/// Het voorstel: [naam] van de verzameling, [waarom] in één zin voor op het scherm, en [nieuw] als die verzameling er
/// nog niet is.
typedef Verzamelvoorstel = ({String naam, String waarom, bool nieuw});

/// Minstens zoveel nummers met het genre van het zaad, wil een verzameling er "vooral" dat genre zijn.
const int kGenreMinstens = 3;

/// En minstens dit deel van de verzameling.
const double kGenreAandeel = .3;

/// Een nieuwe verzameling alleen bij een bibliotheek van minstens zoveel nummers: bij een kleine bibliotheek is alles
/// zeldzaam.
const int kZeldzaamVanaf = 200;

/// Zeldzaam: hoogstens dit deel van je bibliotheek draagt het genre.
const double kZeldzaamAandeel = .02;

/// Genres die niets zeggen over wat apart moet: verzamelbakken, en wat taggers invullen als ze het niet weten.
const Set<String> kGeenEigenGenre = {
  'pop', 'rock', 'pop rock', 'pop/rock', 'rock pop', 'various', 'various artists', 'other', 'others', 'unknown', //
  'misc', 'miscellaneous', 'genre', 'music', 'soundtrack', 'none', 'default', 'blues/rock', 'dance', 'electronic', //
  'alternative', 'indie', 'hits', 'top 40', 'radio', 'compilation', 'world', 'easy listening', 'oldies', 'classic', //
};

/// Een genre om op te vergelijken: klein, `&` en `and` gelijk, zonder leestekens en dubbele spaties. Null voor iets
/// leegs.
String? genreSleutel(String? genre) {
  if (genre == null) return null;
  final s = genre
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9À-ɏ ]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return s.isEmpty ? null : s;
}

/// Het genre dat het meest voorkomt in [nummers] (op [genreSleutel]), met de schrijfwijze die het vaakst voorkomt.
String? meesteGenre(Iterable<VoorstelNummer> nummers) {
  final tel = <String, int>{};
  final schrijf = <String, Map<String, int>>{};
  for (final n in nummers) {
    final k = genreSleutel(n.genre);
    if (k == null) continue;
    tel[k] = (tel[k] ?? 0) + 1;
    final w = schrijf[k] ??= {};
    w[n.genre!.trim()] = (w[n.genre!.trim()] ?? 0) + 1;
  }
  if (tel.isEmpty) return null;
  final beste = (tel.entries.toList()..sort((a, b) => b.value != a.value ? b.value - a.value : a.key.compareTo(b.key))).first.key;
  final w = schrijf[beste]!.entries.toList()..sort((a, b) => b.value != a.value ? b.value - a.value : a.key.compareTo(b.key));
  return w.first.key;
}

/// Het voorstel voor een radio vanaf [zaadArtiest] met genre [zaadGenre] (null: het genre dat het meest voorkomt bij
/// die artiest), gegeven je [verzamelingen] (naam → nummers, ook de lege) en je gewone [bibliotheek] (zonder
/// verzamelingen). Null: niets voor te stellen.
Verzamelvoorstel? verzamelingVoorRadio({
  required String zaadArtiest,
  String? zaadGenre,
  required Map<String, List<VoorstelNummer>> verzamelingen,
  required List<VoorstelNummer> bibliotheek,
}) {
  final wie = artiestSleutel(zaadArtiest);
  if (wie.isEmpty) return null;
  bool vanHem(VoorstelNummer n) => artiestSleutel(n.artiest) == wie;

  // 1. De artiest.
  final thuis = bibliotheek.where(vanHem).length;
  String? besteNaam;
  var besteTal = 0;
  for (final e in verzamelingen.entries) {
    final n = e.value.where(vanHem).length;
    if (n > besteTal || (n == besteTal && n > 0 && e.key.toLowerCase().compareTo(besteNaam!.toLowerCase()) < 0)) {
      besteNaam = e.key;
      besteTal = n;
    }
  }
  if (besteNaam != null && besteTal > thuis) {
    return (
      naam: besteNaam,
      waarom: '$zaadArtiest staat al in “$besteNaam”${thuis == 0 ? '' : ', meer dan in je bibliotheek'}',
      nieuw: false,
    );
  }

  // 2. Het genre.
  final genre = zaadGenre != null && genreSleutel(zaadGenre) != null
      ? zaadGenre.trim()
      : meesteGenre([...bibliotheek.where(vanHem), for (final l in verzamelingen.values) ...l.where(vanHem)]);
  final g = genreSleutel(genre);
  if (g == null) return null;
  bool vanGenre(VoorstelNummer n) => genreSleutel(n.genre) == g;
  final inBib = bibliotheek.where(vanGenre).length;
  String? genreNaam;
  var genreTal = 0;
  for (final e in verzamelingen.entries) {
    if (e.value.isEmpty) continue;
    final n = e.value.where(vanGenre).length;
    if (n < kGenreMinstens || n / e.value.length < kGenreAandeel) continue;
    if (n > genreTal) {
      genreNaam = e.key;
      genreTal = n;
    }
  }
  if (genreNaam != null && genreTal > inBib) {
    return (naam: genreNaam, waarom: '“$genre” staat vooral in “$genreNaam”', nieuw: false);
  }

  // 3. Iets nieuws.
  if (kGeenEigenGenre.contains(g)) return null;
  if (bibliotheek.length < kZeldzaamVanaf || inBib > bibliotheek.length * kZeldzaamAandeel) return null;
  final naam = genre![0].toUpperCase() + genre.substring(1);
  if (verzamelingen.keys.any((k) => k.toLowerCase() == naam.toLowerCase())) {
    return (naam: verzamelingen.keys.firstWhere((k) => k.toLowerCase() == naam.toLowerCase()), waarom: '“$genre” hoort daar', nieuw: false);
  }
  return (
    naam: naam,
    waarom: '“$genre” komt bijna niet voor in je bibliotheek ($inBib van ${bibliotheek.length})',
    nieuw: true,
  );
}

/// Hoort een radio uit een zin ("Zeg wat je wil horen") bij een verzameling? Saber, 22-11-2026: *"de radio functie bij
/// ai moet ook geupdate worden … met de nieuwe en verbeterde functie's"*.
///
/// Noemen [zin] of het [genre] dat het model eruit haalde haar naam (zonder hoofdletters en leestekens; de langste naam
/// wint), dan die, [zeker]: de radio blijft erin, zoals een radio vanuit de verzameling zelf — de vulling met je eigen
/// muziek komt eruit, en wat je houdt gaat erheen. Anders: staan minstens twee en een derde van de [zaadArtiesten] in
/// één verzameling, en daar meer dan in je gewone [bibliotheek], dan die als voorstel. Null: geen van beide.
({String naam, bool zeker, String waarom})? verzamelingVoorZin({
  required String zin,
  required String genre,
  required List<String> zaadArtiesten,
  required Map<String, List<VoorstelNummer>> verzamelingen,
  required List<VoorstelNummer> bibliotheek,
}) {
  final z = ' ${genreSleutel(zin) ?? ''} ';
  final g = genreSleutel(genre);
  String? beste;
  var besteLengte = 0;
  for (final naam in verzamelingen.keys) {
    final k = genreSleutel(naam);
    if (k == null || (k != g && !z.contains(' $k '))) continue;
    if (k.length > besteLengte) {
      beste = naam;
      besteLengte = k.length;
    }
  }
  if (beste != null) return (naam: beste, zeker: true, waarom: 'je zin noemt “$beste”');
  final zaad = {for (final a in zaadArtiesten) artiestSleutel(a)}..remove('');
  if (zaad.isEmpty) return null;
  int hoeveel(List<VoorstelNummer> l) => {for (final n in l) artiestSleutel(n.artiest)}.intersection(zaad).length;
  final inBib = hoeveel(bibliotheek);
  String? naam;
  var tal = 0;
  for (final e in verzamelingen.entries) {
    final n = hoeveel(e.value);
    if (n > tal) {
      naam = e.key;
      tal = n;
    }
  }
  if (naam == null || tal < 2 || tal * 3 < zaad.length || tal <= inBib) return null;
  return (naam: naam, zeker: false, waarom: '$tal van de ${zaad.length} artiesten uit je zin staan in “$naam”');
}

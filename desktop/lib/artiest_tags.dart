/// Taal en stijl in de bibliotheek, uit de tags die luisteraars een artiest geven (Last.fm, artist.getTopTags).
///
/// Saber, 22-10-2026: "doe wat zeker beter zou zijn voor de app … 9". Gemeten die dag op 50 artiesten uit zijn
/// bibliotheek: 46 hebben tags, 16 een taal of streek ("nederlandstalig", "french", "german"). De genres in zijn
/// bestanden zeggen bij 454 van de 1662 nummers alleen "Pop"; zo vind je de Nederlandstalige, de Franse chanson of de
/// eurodance terug die daaronder verdwijnt.
///
/// **Naamgenoten.** Last.fm gooit artiesten met dezelfde naam op één hoop: K3 draagt "progressive metal" (een
/// metalband). Een TAAL is betrouwbaar genoeg; een STIJL vervalt als de genres in je eigen bestanden een heel andere
/// familie zeggen ([stijlPast]).
///
/// Geen IO: alleen de tabel en de indeling, zodat het na te rekenen is.
library;

import 'radiostijl.dart' show Stijlfamilie, familiesVan;

/// Taal of stijl: de taalgroepen staan in de bibliotheek eerst.
enum Groepsoort { taal, stijl }

/// Eén groep: de naam op het scherm, de Last.fm-tags die erbij horen (klein geschreven), en voor een stijl de familie
/// waarmee je eigen genres moeten kloppen.
typedef Taggroep = ({String naam, Groepsoort soort, Set<String> tags, Stijlfamilie? familie});

/// De groepen, in de volgorde waarin ze bij gelijke grootte staan. "belgian" staat bewust nergens: een Belgische
/// artiest zingt net zo goed Frans of Engels.
const List<Taggroep> kTaggroepen = [
  (
    naam: 'Nederlandstalig',
    soort: Groepsoort.taal,
    tags: {'nederlandstalig', 'dutch', 'vlaams', 'flemish', 'nederpop', 'nederlands', 'levenslied', 'smartlap'},
    familie: null,
  ),
  (
    naam: 'Frans',
    soort: Groepsoort.taal,
    tags: {'french', 'chanson', 'chanson francaise', 'french pop', 'variete francaise', 'francais', 'rock francais'},
    familie: null,
  ),
  (
    naam: 'Duits',
    soort: Groepsoort.taal,
    tags: {'german', 'deutsch', 'schlager', 'deutschrap', 'neue deutsche welle', 'deutschland'},
    familie: null,
  ),
  (
    naam: 'Spaans en Latijns',
    soort: Groepsoort.taal,
    tags: {'spanish', 'latin', 'latin pop', 'reggaeton', 'salsa', 'espanol', 'latino'},
    familie: null,
  ),
  (naam: 'Italiaans', soort: Groepsoort.taal, tags: {'italian', 'italiano', 'canzone italiana'}, familie: null),
  (
    naam: 'Arabisch en raï',
    soort: Groepsoort.taal,
    tags: {'arabic', 'rai', 'raï', 'algerian', 'maghreb'},
    familie: null,
  ),
  (naam: 'Turks', soort: Groepsoort.taal, tags: {'turkish', 'turkce', 'türkçe'}, familie: null),
  (
    naam: 'Eurodance',
    soort: Groepsoort.stijl,
    tags: {'eurodance', 'euro house', 'europop', 'eurobeat', 'euro dance'},
    familie: Stijlfamilie.dans,
  ),
  (
    naam: 'Trance',
    soort: Groepsoort.stijl,
    tags: {'trance', 'vocal trance', 'uplifting trance'},
    familie: Stijlfamilie.dans,
  ),
  (
    naam: 'Hardcore en hardstyle',
    soort: Groepsoort.stijl,
    tags: {'happy hardcore', 'gabber', 'hardstyle', 'hardcore techno'},
    familie: Stijlfamilie.dans,
  ),
  (
    naam: 'House',
    soort: Groepsoort.stijl,
    tags: {'house', 'deep house', 'tech house', 'progressive house'},
    familie: Stijlfamilie.dans,
  ),
  (
    naam: 'R&B en soul',
    soort: Groepsoort.stijl,
    tags: {'rnb', 'r&b', 'soul', 'neo-soul', 'contemporary r&b', 'r and b'},
    familie: Stijlfamilie.popsoul,
  ),
  (
    naam: 'Hip-hop',
    soort: Groepsoort.stijl,
    tags: {'hip-hop', 'hip hop', 'rap', 'hiphop'},
    familie: Stijlfamilie.hiphop,
  ),
  (
    naam: 'Reggae',
    soort: Groepsoort.stijl,
    tags: {'reggae', 'dancehall', 'roots reggae', 'ska'},
    familie: Stijlfamilie.reggae,
  ),
  (
    naam: 'Rock',
    soort: Groepsoort.stijl,
    tags: {'rock', 'alternative rock', 'classic rock', 'hard rock', 'indie rock', 'britpop', 'grunge', 'pop rock'},
    familie: Stijlfamilie.rock,
  ),
  (
    naam: 'Metal',
    soort: Groepsoort.stijl,
    tags: {'metal', 'heavy metal', 'progressive metal', 'thrash metal', 'nu metal', 'death metal'},
    familie: Stijlfamilie.rock,
  ),
  (
    naam: 'Jazz',
    soort: Groepsoort.stijl,
    tags: {'jazz', 'smooth jazz', 'vocal jazz', 'swing'},
    familie: Stijlfamilie.jazz,
  ),
];

/// Past stijl [groep] bij een artiest wiens eigen bestanden families [eigen] noemen? Zonder eigen genre: ja. Pop en
/// dance lopen in elkaar over (Kate Ryan staat in haar bestanden als "Pop" en is eurodance), de rest niet: K3 met
/// "Pop" wordt geen Metal.
bool stijlPast(Stijlfamilie groep, Set<Stijlfamilie> eigen) {
  if (eigen.isEmpty || eigen.contains(groep)) return true;
  const zacht = {Stijlfamilie.dans, Stijlfamilie.popsoul};
  return zacht.contains(groep) && eigen.any(zacht.contains);
}

/// Tags die een NATIONALITEIT noemen en geen taal. Gemeten op 22-10-2026 in Sabers bibliotheek: "dutch" zette Alice
/// Deejay bij Nederlandstalig, "german" Masterboy, Maxx en Captain Hollywood Project bij Duits — danceacts die Engels
/// zingen. Zo'n tag telt daarom alleen voor een artiest die geen danceact is ([groepenVan]).
const Set<String> kNationaliteitTags = {
  'dutch', 'flemish', 'french', 'german', 'deutschland', 'italian', 'spanish', 'turkish', 'algerian', //
};

/// De groepen van één artiest, uit zijn Last.fm-[tags] en de genres in je eigen bestanden ([eigenGenres]).
List<String> groepenVan(List<String> tags, Iterable<String?> eigenGenres) {
  final t = {for (final x in tags) x.trim().toLowerCase()};
  final eigen = familiesVan([
    for (final g in eigenGenres)
      if (g != null && g.trim().isNotEmpty) g,
  ]);
  final stijlen = [
    for (final g in kTaggroepen)
      if (g.soort == Groepsoort.stijl && g.tags.any(t.contains) && stijlPast(g.familie!, eigen)) g,
  ];
  final danceact = stijlen.any((g) => g.familie == Stijlfamilie.dans);
  return [
    for (final g in kTaggroepen)
      if (g.soort == Groepsoort.taal)
        if (g.tags.where(t.contains).toList() case final raak when raak.isNotEmpty)
          if (!danceact || !raak.every(kNationaliteitTags.contains)) g.naam,
    for (final g in stijlen) g.naam,
  ];
}

/// De groepen van een hele bibliotheek: per groep de artiesten (gesorteerd), alleen groepen met minstens [minstens]
/// artiesten; talen eerst, daarbinnen de grootste eerst.
List<({String naam, Groepsoort soort, List<String> artiesten})> bibliotheekGroepen(
  Map<String, List<String>> tagsPerArtiest,
  Map<String, List<String?>> genresPerArtiest, {
  int minstens = 5,
}) {
  final leden = <String, List<String>>{};
  tagsPerArtiest.forEach((artiest, tags) {
    for (final g in groepenVan(tags, genresPerArtiest[artiest] ?? const [])) {
      (leden[g] ??= []).add(artiest);
    }
  });
  final soort = {for (final g in kTaggroepen) g.naam: g.soort};
  final volgorde = {for (final (i, g) in kTaggroepen.indexed) g.naam: i};
  final uit =
      [
        for (final e in leden.entries)
          if (e.value.length >= minstens)
            (
              naam: e.key,
              soort: soort[e.key]!,
              artiesten: [...e.value]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
            ),
      ]..sort((a, b) {
        final s = a.soort.index.compareTo(b.soort.index);
        if (s != 0) return s;
        final n = b.artiesten.length.compareTo(a.artiesten.length);
        return n != 0 ? n : volgorde[a.naam]!.compareTo(volgorde[b.naam]!);
      });
  return uit;
}

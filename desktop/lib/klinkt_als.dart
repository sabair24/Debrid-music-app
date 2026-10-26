// "Klinkt als" op de artiestpagina, tot vijftig artiesten.
//
// Saber, 26-10-2026: "klinkt als moet ook meer gevuld worden, tot zeker 50 artiesten". Deezer geeft er hoogstens
// twintig: `/artist/{id}/related` antwoordt met `total: 20`, ook met `limit=50` en met `index=20` (gemeten bij Khaled
// en Daft Punk). Die twintig blijven vooraan. Daarna Last.fm (`artist.getSimilar`, op maat), elk opgezocht bij Deezer
// voor de foto en alleen met exact dezelfde naam ([artistKey]) — een naamgenoot zonder zekerheid liever niet. Is er
// geen Last.fm-sleutel, of geeft dat niet genoeg, dan de verwanten van de eerste verwanten bij Deezer, op hoe vaak ze
// terugkomen.
import 'catalog.dart' show CatalogArtist;
import 'organize.dart' show artistKey;

/// Zoveel artiesten in "Klinkt als".
const int kKlinktAlsDoel = 50;

/// Van zoveel van de eerste verwanten vraagt de terugval hun eigen verwanten op.
const int kKlinktAlsTweedeKring = 5;

/// Zoveel Last.fm-namen tegelijk bij Deezer opzoeken.
const int kKlinktAlsTegelijk = 4;

/// De Last.fm-namen die erbij mogen, in Last.fm-volgorde: niet [artiest] zelf, niet wie er al staat ([alGetoond]), en
/// hoogstens [ruimte].
List<String> klinktAlsNamen(String artiest, Iterable<String> alGetoond, List<({String naam, double maat})> lastfm,
    {required int ruimte}) {
  final gezien = {artistKey(artiest), for (final n in alGetoond) artistKey(n)};
  final uit = <String>[];
  for (final v in [...lastfm]..sort((a, b) => b.maat.compareTo(a.maat))) {
    if (uit.length >= ruimte) break;
    final k = artistKey(v.naam);
    if (k.isEmpty || !gezien.add(k)) continue;
    uit.add(v.naam);
  }
  return uit;
}

/// De verwanten van de verwanten ([lijsten], één per verwante), zonder [artiest] en wie er al staat: wie het vaakst
/// terugkomt eerst, bij gelijkstand wie het eerst opdook. Hoogstens [ruimte].
List<CatalogArtist> verwantenVanVerwanten(String artiest, Iterable<String> alGetoond, List<List<CatalogArtist>> lijsten,
    {required int ruimte}) {
  final weg = {artistKey(artiest), for (final n in alGetoond) artistKey(n)};
  final tel = <String, int>{};
  final eerst = <String, ({int plek, CatalogArtist a})>{};
  var plek = 0;
  for (final l in lijsten) {
    for (final a in l) {
      final k = artistKey(a.name);
      if (k.isEmpty || weg.contains(k)) continue;
      tel[k] = (tel[k] ?? 0) + 1;
      eerst.putIfAbsent(k, () => (plek: plek++, a: a));
    }
  }
  final volgorde = eerst.keys.toList()
    ..sort((x, y) {
      final c = tel[y]!.compareTo(tel[x]!);
      return c != 0 ? c : eerst[x]!.plek.compareTo(eerst[y]!.plek);
    });
  return [for (final k in volgorde.take(ruimte)) eerst[k]!.a];
}

/// De aanvulling op [deezer] (de twintig van Deezer) tot [doel]. [lastfm] geeft de Last.fm-verwanten (null: geen
/// sleutel of geen antwoord), [zoekArtiest] zoekt een naam bij Deezer, [verwanten] geeft de Deezer-verwanten van een id.
/// [tussendoor] krijgt de lijst tot nu toe telkens als er een stuk bij komt, zodat de rij al groeit terwijl er nog
/// gezocht wordt. Geeft alles terug: de twintig en de aanvulling.
Future<List<CatalogArtist>> klinktAlsAanvullen({
  required String artiest,
  required List<CatalogArtist> deezer,
  Future<List<({String naam, double maat})>?> Function()? lastfm,
  required Future<List<CatalogArtist>> Function(String naam) zoekArtiest,
  required Future<List<CatalogArtist>> Function(int id) verwanten,
  int doel = kKlinktAlsDoel,
  void Function(List<CatalogArtist> tussenstand)? tussendoor,
}) async {
  final uit = [...deezer];
  if (uit.length >= doel) return uit;
  List<String> namen() => [for (final a in uit) a.name];

  if (lastfm != null) {
    List<({String naam, double maat})>? lijst;
    try {
      lijst = await lastfm();
    } catch (_) {/* dan de terugval */}
    // Ruim vragen: niet elke naam staat bij Deezer onder precies die naam.
    final te = lijst == null ? const <String>[] : klinktAlsNamen(artiest, namen(), lijst, ruimte: (doel - uit.length) * 2);
    for (var i = 0; i < te.length && uit.length < doel; i += kKlinktAlsTegelijk) {
      final stuk = te.sublist(i, (i + kKlinktAlsTegelijk).clamp(0, te.length));
      final gevonden = await Future.wait([
        for (final n in stuk)
          zoekArtiest(n)
              .then((hits) => hits.where((a) => artistKey(a.name) == artistKey(n)).firstOrNull)
              .catchError((Object _) => null),
      ]);
      final al = {for (final a in uit) artistKey(a.name)};
      for (final a in gevonden) {
        if (a == null || uit.length >= doel || !al.add(artistKey(a.name))) continue;
        uit.add(a);
      }
      tussendoor?.call(List.unmodifiable(uit));
    }
  }

  if (uit.length < doel && deezer.isNotEmpty) {
    final lijsten = await Future.wait([
      for (final a in deezer.take(kKlinktAlsTweedeKring))
        verwanten(a.id).catchError((Object _) => const <CatalogArtist>[]),
    ]);
    final erbij = verwantenVanVerwanten(artiest, namen(), lijsten, ruimte: doel - uit.length);
    if (erbij.isNotEmpty) {
      uit.addAll(erbij);
      tussendoor?.call(List.unmodifiable(uit));
    }
  }
  return uit;
}

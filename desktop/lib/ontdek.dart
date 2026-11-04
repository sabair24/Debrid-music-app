/// Ontdek: nieuwe muziek die past bij je bibliotheek, elke dag een andere lijst van ~50 nummers.
///
/// **Waarom dit opnieuw moest.** Saber, 04-11-2026, met zeven schermafdrukken van Ontdek op de gsm: *"moet er meer
/// variatie in komen en nog meer afgestemd zijn op men bibliotheek, plus ook geen dingen die ik al heb"*. Gemeten in de
/// oude weg (`RecommendService.discover`):
/// - vier WILLEKEURIGE zaden uit de bibliotheek, en van zijn 573 artiesten hebben er 247 maar één nummer: wat hij draait
///   telde niet;
/// - per zaad vier verwanten met elk zes toppers, dus blokken van één hoek: Ultravox, Visage en Dead Or Alive na
///   elkaar, of Maluma, Camilo en Joey Montana;
/// - geen versiezeef: "You Spin Me Round" stond er zes keer in, "Vienna" uit 2008 én uit 2009.
///
/// Zijn keuzes (memory `ontdek-keuzes-04-11`), en waar ze hier staan:
/// - alleen nummers die hij niet heeft; artiesten die hij heeft mogen terugkomen ([stelOntdekSamen], `heb`);
/// - één nummer per artiest in de hele lijst ([stelOntdekSamen]);
/// - afgestemd op wat hij het meest draait, de laatste weken, zijn duimen en favorieten ([ontdekGewicht]), en
///   gespreid zoals zijn bibliotheek: talen, stijlen en jaren ([verdeelZaden], [kiesOntdekZaden]);
/// - vooral dichtbij, één op vijf iets verder ([kVerderElke]);
/// - Deezer, Last.fm en Claude als bronnen, om de beurt;
/// - ~50 nummers ([kOntdekGetoond]), elke dag vers, en wat hij ophaalt verdwijnt en wordt aangevuld uit de reserve;
/// - wegtikken: dat nummer komt nooit meer, en Ontdek leert ervan ([OntdekWeg]).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'aanbevolen.dart' show goedOmTeOntdekken, kGroenBonus, recTrackNaarJson, recTrackUitJson;
import 'artiest_tags.dart' show groepenVan;
import 'nieuwe_releases.dart' show EigenArtiest, EigenNummer, eigenArtiesten, hoofdartiest, relevantie;
import 'ontdekvraag.dart' show OntdekProfiel;
import 'organize.dart' show artistKey;
import 'radiostijl.dart' show familieVan;
import 'recommend.dart' show RecTrack, recNorm;

/// Zoveel nummers staan er op het scherm; de rest van de lijst is reserve voor wat je ophaalt of wegtikt.
const int kOntdekGetoond = 50;

/// Zoveel nummers rekent de pc in één keer uit: [kOntdekGetoond] plus de reserve.
const int kOntdekLengte = 90;

/// Elke zoveelste plek is iets verder van je smaak (Saber: "Vooral dichtbij, 1 op 5 iets verder").
const int kVerderElke = 5;

/// Zoveel zaden per berekening, gespreid over de hoeken van de bibliotheek.
const int kOntdekZaden = 14;

/// Een hoek met minder dan dit deel van de bibliotheek krijgt geen eigen zaad (tenzij er plaats over is).
const double kHoekDrempel = 0.03;

/// Wat een hartje bij een artiest optelt (op een nummer of een album van hem).
const double kFavorietBonus = 2;

/// Wat "de laatste weken gedraaid" erbij doet, bovenop de dertig dagen die [relevantie] al telt.
const double kKortGeledenBonus = 2;
const Duration kKortGeleden = Duration(days: 14);

/// Hoe lang een nummer dat al in een lijst stond (zonder dat er iets mee gebeurde) achteraan gaat.
const Duration kAlGetoond = Duration(days: 14);

/// Twee keer weggetikt van dezelfde artiest: die artiest zolang niet meer.
const Duration kArtiestWeg = Duration(days: 90);

/// Waar een nummer vandaan komt.
enum Ontdekbron { claude, lastfm, deezer }

/// De sleutel van een nummer in Ontdek: hoofdartiest en titel, zonder versie en gast.
String ontdekSleutel(String artiest, String titel) => '${artistKey(hoofdartiest(artiest))}|${recNorm(titel)}';

/// De sleutel van een artiest in Ontdek.
String ontdekArtiest(String artiest) => artistKey(hoofdartiest(artiest));

/// Het LIED achter een titel, over artiesten heen, of null: alleen bij drie woorden of meer. Gemeten op 04-11-2026:
/// "The Rhythm of the Night" stond er twee keer, van twee coverartiesten (Neptunica, Sean Finn) — en een cover van
/// een lied dat je al hebt, hoort er ook niet in. Een korte titel ("Drive", "Love", "Kiss") zegt niets over het lied.
String? ontdekLied(String titel) {
  final kaal = titel.replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ').trim();
  if (kaal.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length < 3) return null;
  final k = recNorm(kaal);
  return k.isEmpty ? null : '♪|$k';
}

/// Staat dit in [bezit] ([bezitSleutelsVan]): hetzelfde nummer van dezelfde artiest, of hetzelfde lange lied.
bool inBezit(Set<String> bezit, String artiest, String titel) {
  if (bezit.contains(ontdekSleutel(artiest, titel))) return true;
  final l = ontdekLied(titel);
  return l != null && bezit.contains(l);
}

/// Eén nummer in de lijst, met waar het vandaan komt en waarom het erin staat.
class OntdekNummer {
  const OntdekNummer(this.nummer, {required this.bron, this.waarom = '', this.verder = false, this.via = ''});

  final RecTrack nummer;
  final Ontdekbron bron;

  /// Eén korte regel onder de artiest: "Lijkt op Sade en Seal", of de reden van Claude.
  final String waarom;

  /// Een stap buiten je gewone smaak ([kVerderElke]).
  final bool verder;

  /// De artiest van jou waaruit dit kwam, of leeg. Wegtikken weegt die hoek daarna minder ([OntdekWeg]).
  final String via;

  String get sleutel => ontdekSleutel(nummer.artist, nummer.title);

  Map<String, dynamic> toJson() => {
    ...recTrackNaarJson(nummer),
    'bron': bron.name,
    if (waarom.isNotEmpty) 'waarom': waarom,
    if (verder) 'verder': true,
    if (via.isNotEmpty) 'via': via,
  };

  static OntdekNummer? fromJson(Object? j) {
    final t = recTrackUitJson(j);
    if (t == null || j is! Map) return null;
    final b = Ontdekbron.values.where((x) => x.name == j['bron']).firstOrNull ?? Ontdekbron.deezer;
    return OntdekNummer(
      t,
      bron: b,
      waarom: (j['waarom'] as String?) ?? '',
      verder: j['verder'] == true,
      via: (j['via'] as String?) ?? '',
    );
  }
}

/// De lijst zoals de pc hem bewaart en doorgeeft.
class OntdekLijst {
  const OntdekLijst(this.berekendMs, this.nummers);
  final int berekendMs;
  final List<OntdekNummer> nummers;

  static const versie = 1;

  Map<String, dynamic> toJson() => {
    'versie': versie,
    'berekendMs': berekendMs,
    'nummers': [for (final n in nummers) n.toJson()],
  };

  static OntdekLijst? fromJson(Object? j) {
    if (j is! Map || j['versie'] != versie) return null;
    final ms = (j['berekendMs'] as num?)?.toInt();
    if (ms == null) return null;
    return OntdekLijst(ms, [for (final n in (j['nummers'] as List? ?? const [])) ?OntdekNummer.fromJson(n)]);
  }
}

// ── Zaden ──────────────────────────────────────────────────────────────────

/// Eén artiest van jou zoals Ontdek hem ziet.
class OntdekArtiest {
  const OntdekArtiest({
    required this.naam,
    required this.gewicht,
    required this.hoek,
    this.nummers = 0,
    this.zaadNummers = const [],
  });

  final String naam;

  /// Hoe zwaar hij meetelt ([ontdekGewicht]).
  final double gewicht;

  /// In welke hoek van de bibliotheek hij staat ([hoekVan]): een taal, een stijl, of een familie.
  final String hoek;

  /// Hoeveel nummers je van hem hebt: daarop wordt de verdeling over de hoeken geteld.
  final int nummers;

  /// Zijn nummers om bij Last.fm "wat lijkt hierop?" te vragen, de beste eerst (groen, veel en recent gedraaid).
  final List<String> zaadNummers;
}

/// Hoe zwaar een artiest weegt in Ontdek: [relevantie] (beurten, bezit, de laatste dertig dagen), plus groen, een
/// hartje en de laatste twee weken, min wat er uit zijn hoek werd weggetikt (hoogstens drie).
double ontdekGewicht(EigenArtiest a, {required int nuMs, bool groen = false, bool favoriet = false, int wegVia = 0}) {
  final kort = a.laatstMs > 0 && nuMs - a.laatstMs < kKortGeleden.inMilliseconds;
  final g =
      relevantie(a, nuMs: nuMs) +
      (groen ? kGroenBonus : 0) +
      (favoriet ? kFavorietBonus : 0) +
      (kort ? kKortGeledenBonus : 0) -
      math.min(3, wegVia);
  return math.max(0, g);
}

/// De hoek van een artiest: zijn eerste groep uit de Last.fm-tags (een taal gaat voor, zie [groepenVan]), anders de
/// familie die zijn eigen genres het vaakst noemen, anders "overig". Zo krijgt de Nederlandstalige en de Franse hoek
/// zijn eigen zaden, ook al staat daar in de bestanden alleen "Pop".
String hoekVan(List<String> tags, Iterable<String?> genres) {
  final g = groepenVan(tags, genres);
  if (g.isNotEmpty) return g.first;
  final tel = <String, int>{};
  for (final x in genres) {
    final f = familieVan(x);
    if (f != null) tel[f.name] = (tel[f.name] ?? 0) + 1;
  }
  if (tel.isEmpty) return 'overig';
  final l = tel.entries.toList()..sort((a, b) => b.value != a.value ? b.value - a.value : a.key.compareTo(b.key));
  return l.first.key;
}

/// Hoeveel zaden elke hoek krijgt: naar zijn aandeel in de bibliotheek (in nummers), met de grootste-rest-methode.
/// Een hoek onder [kHoekDrempel] krijgt alleen iets als er na de rest nog plaats is; elke hoek erboven minstens één,
/// zolang er plaatsen zijn.
Map<String, int> verdeelZaden(Map<String, int> nummersPerHoek, int aantal, {double drempel = kHoekDrempel}) {
  final totaal = nummersPerHoek.values.fold<int>(0, (s, n) => s + n);
  if (totaal == 0 || aantal <= 0) return {};
  final hoeken = nummersPerHoek.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) => b.value != a.value ? b.value - a.value : a.key.compareTo(b.key));
  final uit = <String, int>{};
  // Eerst één voor elke hoek boven de drempel, de grootste eerst.
  var over = aantal;
  for (final e in hoeken) {
    if (over == 0) break;
    if (e.value / totaal >= drempel) {
      uit[e.key] = 1;
      over--;
    }
  }
  if (over == 0) return uit;
  // De rest naar het aandeel, bovenop die eerste.
  // Niet onder nul: een hoek die met zijn eerste al boven zijn aandeel zit, krijgt geen rest (een negatieve breuk
  // leek anders de grootste rest).
  final wil = {for (final e in hoeken) e.key: math.max(0.0, e.value / totaal * aantal - (uit[e.key] ?? 0))};
  final heel = {for (final e in wil.entries) e.key: math.max(0, e.value.floor())};
  var gegeven = heel.values.fold<int>(0, (s, n) => s + n);
  if (gegeven > over) {
    // Kan alleen door afronden bovenop de eerste: neem van de kleinste.
    for (final e in hoeken.reversed) {
      while (gegeven > over && (heel[e.key] ?? 0) > 0) {
        heel[e.key] = heel[e.key]! - 1;
        gegeven--;
      }
    }
  }
  heel.forEach((k, n) {
    if (n > 0) uit[k] = (uit[k] ?? 0) + n;
  });
  over -= gegeven;
  final rest = wil.entries.toList()
    ..sort((a, b) {
      final ra = a.value - a.value.floorToDouble(), rb = b.value - b.value.floorToDouble();
      return rb != ra ? rb.compareTo(ra) : a.key.compareTo(b.key);
    });
  for (final e in rest) {
    if (over == 0) break;
    uit[e.key] = (uit[e.key] ?? 0) + 1;
    over--;
  }
  return uit;
}

/// De zaden van één berekening: per hoek zoveel als [verdeelZaden] zegt, binnen de hoek gewogen getrokken uit zijn
/// zwaarste artiesten (de zwaarste vaker, maar niet altijd dezelfde: verversen geeft andere). Heeft een hoek te weinig
/// artiesten met gewicht, dan vult de rest aan met de zwaarsten van de hele bibliotheek.
List<OntdekArtiest> kiesOntdekZaden(List<OntdekArtiest> alle, {int aantal = kOntdekZaden, math.Random? toeval}) {
  final r = toeval ?? math.Random();
  final perHoek = <String, List<OntdekArtiest>>{};
  final nummers = <String, int>{};
  for (final a in alle) {
    (perHoek[a.hoek] ??= []).add(a);
    nummers[a.hoek] = (nummers[a.hoek] ?? 0) + math.max(1, a.nummers);
  }
  int zwaar(OntdekArtiest a, OntdekArtiest b) {
    final v = b.gewicht.compareTo(a.gewicht);
    return v != 0 ? v : a.naam.compareTo(b.naam);
  }

  final quota = verdeelZaden(nummers, aantal);
  final uit = <OntdekArtiest>[];
  final gekozen = <String>{};
  for (final e in (quota.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) {
    final kandidaten = [
      for (final a in (perHoek[e.key]!..sort(zwaar)).take(math.max(6, e.value * 3)))
        if (a.gewicht > 0) a,
    ];
    for (final a in _trek(kandidaten, e.value, r)) {
      if (gekozen.add(artistKey(a.naam))) uit.add(a);
    }
  }
  if (uit.length < aantal) {
    for (final a in [...alle]..sort(zwaar)) {
      if (uit.length >= aantal) break;
      if (a.gewicht > 0 && gekozen.add(artistKey(a.naam))) uit.add(a);
    }
  }
  return uit;
}

List<OntdekArtiest> _trek(List<OntdekArtiest> uit, int hoeveel, math.Random r) {
  if (uit.length <= hoeveel) return uit;
  final rest = [...uit];
  final getrokken = <OntdekArtiest>[];
  while (getrokken.length < hoeveel && rest.isNotEmpty) {
    final totaal = rest.fold<double>(0, (s, a) => s + a.gewicht);
    var trek = r.nextDouble() * totaal;
    var i = 0;
    for (; i < rest.length - 1; i++) {
      trek -= rest[i].gewicht;
      if (trek <= 0) break;
    }
    getrokken.add(rest.removeAt(i));
  }
  return getrokken;
}

/// Eén nummer van jou, met wat Ontdek erover moet weten. [favoriet] is ook waar als het album een hartje heeft.
typedef OntdekEigen = ({
  String artiest,
  String album,
  String titel,
  String? genre,
  int? jaar,
  int beurten,
  int laatstMs,
  bool groen,
  bool favoriet,
});

/// De sleutels waaronder een nummer van jou "al in bezit" telt: de hoofdartiest, en elke artiest in een rij als
/// "Elton John, Tim Rice, Hans Zimmer" of "Simon & Garfunkel" apart. Anders kwam "Circle Of Life" van Elton John
/// terug terwijl het al op de Lion King-plaat staat.
Iterable<String> bezitSleutelsVan(String artiest, String titel) sync* {
  yield ontdekSleutel(artiest, titel);
  if (ontdekLied(titel) case final l?) yield l;
  final delen = hoofdartiest(
    artiest,
  ).split(RegExp(r'\s*,\s*|\s+&\s+|\s+x\s+|\s+and\s+|\s+en\s+', caseSensitive: false));
  if (delen.length < 2) return;
  for (final d in delen) {
    if (d.trim().isNotEmpty) yield ontdekSleutel(d, titel);
  }
}

/// Je artiesten zoals Ontdek ze weegt ([ontdekGewicht]), met hun hoek ([hoekVan]) en hun beste nummers om bij
/// Last.fm mee te vragen (groen of hartje eerst, dan het meest en het laatst gedraaid).
List<OntdekArtiest> ontdekArtiesten(
  List<OntdekEigen> nummers, {
  required List<String> Function(String artiest) tags,
  required int nuMs,
  OntdekWeg? weg,
  bool Function(String artiest)? overslaan,
}) {
  final eigen = eigenArtiesten([
    for (final n in nummers)
      EigenNummer(artiest: n.artiest, album: n.album, titel: n.titel, beurten: n.beurten, laatstMs: n.laatstMs),
  ], overslaan: overslaan);
  final per = <String, List<OntdekEigen>>{};
  for (final n in nummers) {
    (per[ontdekArtiest(n.artiest)] ??= []).add(n);
  }
  int beste(OntdekEigen a, OntdekEigen b) {
    final la = (a.groen || a.favoriet) ? 1 : 0, lb = (b.groen || b.favoriet) ? 1 : 0;
    if (la != lb) return lb - la;
    if (a.beurten != b.beurten) return b.beurten - a.beurten;
    return b.laatstMs.compareTo(a.laatstMs);
  }

  return [
    for (final a in eigen)
      if (per[artistKey(a.naam)] case final ns?)
        OntdekArtiest(
          naam: a.naam,
          gewicht: ontdekGewicht(
            a,
            nuMs: nuMs,
            groen: ns.any((n) => n.groen),
            favoriet: ns.any((n) => n.favoriet),
            wegVia: weg?.via(a.naam) ?? 0,
          ),
          hoek: hoekVan(tags(a.naam), [for (final n in ns) n.genre]),
          nummers: ns.length,
          zaadNummers: [
            for (final n in ([...ns]..sort(beste)).take(3)) n.titel,
          ],
        ),
  ];
}

/// Het smaakprofiel voor de vraag aan Claude, uit dezelfde gegevens.
OntdekProfiel ontdekProfiel(
  List<OntdekEigen> nummers,
  List<OntdekArtiest> artiesten, {
  required int nuMs,
  List<String> weggetikt = const [],
}) {
  final zwaar = [...artiesten]..sort((a, b) => b.gewicht.compareTo(a.gewicht));
  final recent = [
    for (final n in nummers)
      if (n.laatstMs > 0 && nuMs - n.laatstMs < kKortGeleden.inMilliseconds) n,
  ]..sort((a, b) => b.laatstMs.compareTo(a.laatstMs));
  final groen = [
    for (final n in nummers)
      if (n.groen || n.favoriet) n,
  ]..sort((a, b) => b.laatstMs.compareTo(a.laatstMs));
  Map<K, int> procent<K>(Map<K, int> tel) {
    final totaal = tel.values.fold<int>(0, (s, n) => s + n);
    return totaal == 0 ? {} : {for (final e in tel.entries) e.key: (e.value * 100 / totaal).round()};
  }

  final hoeken = <String, int>{};
  for (final a in artiesten) {
    hoeken[a.hoek] = (hoeken[a.hoek] ?? 0) + math.max(1, a.nummers);
  }
  final decennia = <int, int>{};
  for (final n in nummers) {
    final j = n.jaar;
    if (j != null && j > 1900) decennia[j ~/ 10 * 10] = (decennia[j ~/ 10 * 10] ?? 0) + 1;
  }
  String regel(OntdekEigen n) => '${n.artiest} — ${n.titel}';
  final gezien = <String>{};
  return OntdekProfiel(
    zwaarst: [for (final a in zwaar.take(30)) a.naam],
    recent: [
      for (final n in recent)
        if (gezien.add(regel(n))) regel(n),
    ].take(15).toList(),
    groen: [for (final n in groen) regel(n)].take(15).toList(),
    hoeken: procent(hoeken),
    decennia: procent(decennia),
    weggetikt: weggetikt.take(15).toList(),
  );
}

// ── Samenstellen ───────────────────────────────────────────────────────────

/// De lijst uit wat de bronnen gaven.
///
/// - Weg: geen nummer om mee kennis te maken ([goedOmTeOntdekken]: remix, live, edit, karaoke, intro, te kort, kerst
///   buiten het seizoen); wat je al hebt ([heb]); wat je wegtikte ([weg]); artiesten die je twee keer wegtikte
///   ([wegArtiesten]).
/// - **Eén per artiest**, over de hele lijst.
/// - Om de beurt uit de bronnen, in de volgorde van [Ontdekbron] (Claude, Last.fm, Deezer: wat er is), en elke
///   [kVerderElke]e plek iets verder. Nooit twee na elkaar uit hetzelfde zaad als er een ander klaarstaat.
/// - Wat de laatste [kAlGetoond] al in een lijst stond ([getoondOp], sleutel → ms), gaat achteraan.
List<OntdekNummer> stelOntdekSamen(
  Map<Ontdekbron, List<OntdekNummer>> perBron, {
  required bool Function(String artiest, String titel) heb,
  Set<String> weg = const {},
  Set<String> wegArtiesten = const {},
  Map<String, int> getoondOp = const {},
  required int nuMs,
  int max = kOntdekLengte,
  int verderElke = kVerderElke,
  DateTime? nu,
}) {
  final dag = nu ?? DateTime.fromMillisecondsSinceEpoch(nuMs);
  bool recent(OntdekNummer n) {
    final op = getoondOp[n.sleutel];
    return op != null && nuMs - op < kAlGetoond.inMilliseconds;
  }

  bool bruikbaar(OntdekNummer n) =>
      n.nummer.artist.trim().isNotEmpty &&
      goedOmTeOntdekken(n.nummer, nu: dag) &&
      !weg.contains(n.sleutel) &&
      !wegArtiesten.contains(ontdekArtiest(n.nummer.artist)) &&
      !heb(n.nummer.artist, n.nummer.title);

  // Per bron twee rijen: dichtbij en verder, wat al getoond werd achteraan (in dezelfde volgorde).
  List<OntdekNummer> rij(Iterable<OntdekNummer> ns) {
    final l = ns.where(bruikbaar).toList();
    return [...l.where((n) => !recent(n)), ...l.where(recent)];
  }

  final bronnen = [
    for (final b in Ontdekbron.values)
      if ((perBron[b] ?? const []).isNotEmpty) b,
  ];
  final dichtbij = {for (final b in bronnen) b: rij(perBron[b]!.where((n) => !n.verder))};
  final verder = {for (final b in bronnen) b: rij(perBron[b]!.where((n) => n.verder))};

  final uit = <OntdekNummer>[];
  final artiesten = <String>{};
  // En één per lied ([ontdekLied]): geen twee covers van "The Rhythm of the Night".
  final liederen = <String>{};
  bool alGehad(OntdekNummer n) {
    if (artiesten.contains(ontdekArtiest(n.nummer.artist))) return true;
    final l = ontdekLied(n.nummer.title);
    return l != null && liederen.contains(l);
  }

  var beurtDicht = 0, beurtVer = 0;

  // De eerste bruikbare uit [rijen] (om de beurt vanaf [beurt]), liefst niet uit hetzelfde zaad als de vorige.
  OntdekNummer? neem(Map<Ontdekbron, List<OntdekNummer>> rijen, int beurt) {
    final vorigeVia = uit.isEmpty ? '' : uit.last.via;
    for (final streng in [true, false]) {
      for (var k = 0; k < bronnen.length; k++) {
        final b = bronnen[(beurt + k) % bronnen.length];
        final l = rijen[b]!;
        l.removeWhere(alGehad);
        // Een paar plaatsen vooruitkijken voor een ander zaad; anders de eerste.
        for (var i = 0; i < l.length && i < 4; i++) {
          final n = l[i];
          if (streng && vorigeVia.isNotEmpty && n.via == vorigeVia) continue;
          return l.removeAt(i);
        }
      }
    }
    return null;
  }

  while (uit.length < max) {
    final plek = uit.length + 1;
    final wilVerder = verderElke > 0 && plek % verderElke == 0;
    OntdekNummer? n;
    if (wilVerder) {
      n = neem(verder, beurtVer++);
      n ??= neem(dichtbij, beurtDicht++);
    } else {
      n = neem(dichtbij, beurtDicht++);
      n ??= neem(verder, beurtVer++);
    }
    if (n == null) break;
    artiesten.add(ontdekArtiest(n.nummer.artist));
    if (ontdekLied(n.nummer.title) case final l?) liederen.add(l);
    uit.add(n);
  }
  return uit;
}

// ── Wegtikken ──────────────────────────────────────────────────────────────

/// Wat er weggetikt is (Saber: "dat nummer komt nooit meer"), met wat Ontdek eruit leert: twee van dezelfde artiest
/// in [kArtiestWeg] → die artiest zolang niet, en elk weggetikt nummer weegt het zaad waaruit het kwam één minder
/// ([ontdekGewicht], hoogstens drie).
class OntdekWeg {
  OntdekWeg([Map<String, ({int ms, String artiest, String via, String naam})>? begin]) : _weg = {...?begin};

  final Map<String, ({int ms, String artiest, String via, String naam})> _weg;

  Set<String> get nummers => _weg.keys.toSet();
  int get aantal => _weg.length;

  void zet(String artiest, String titel, {String via = '', required int nuMs}) => _weg[ontdekSleutel(artiest, titel)] =
      (ms: nuMs, artiest: ontdekArtiest(artiest), via: artistKey(via), naam: '$artiest — $titel');

  bool terug(String artiest, String titel) => _weg.remove(ontdekSleutel(artiest, titel)) != null;

  /// De artiesten met twee of meer weggetikte nummers in [kArtiestWeg].
  Set<String> artiesten({required int nuMs}) {
    final tel = <String, int>{};
    for (final w in _weg.values) {
      if (nuMs - w.ms < kArtiestWeg.inMilliseconds) tel[w.artiest] = (tel[w.artiest] ?? 0) + 1;
    }
    return {
      for (final e in tel.entries)
        if (e.value >= 2) e.key,
    };
  }

  /// Wat er weggetikt is, als "artiest — titel", het laatste eerst: voor de vraag aan Claude.
  List<String> namen() => [
    for (final w in (_weg.values.toList()..sort((a, b) => b.ms.compareTo(a.ms))))
      if (w.naam.isNotEmpty) w.naam,
  ];

  /// Hoeveel er weggetikt is dat uit het zaad [artiest] kwam.
  int via(String artiest) {
    final k = artistKey(artiest);
    return _weg.values.where((w) => w.via.isNotEmpty && w.via == k).length;
  }

  Map<String, dynamic> toJson() => {
    'versie': 1,
    'weg': {
      for (final e in _weg.entries)
        e.key: {
          'ms': e.value.ms,
          'a': e.value.artiest,
          if (e.value.via.isNotEmpty) 'v': e.value.via,
          if (e.value.naam.isNotEmpty) 'n': e.value.naam,
        },
    },
  };

  static OntdekWeg fromJson(Object? j) {
    final w = j is Map ? j['weg'] : null;
    if (w is! Map) return OntdekWeg();
    return OntdekWeg({
      for (final e in w.entries)
        if (e.value is Map && (e.value as Map)['ms'] is num)
          '${e.key}': (
            ms: ((e.value as Map)['ms'] as num).toInt(),
            artiest: '${(e.value as Map)['a'] ?? ''}',
            via: '${(e.value as Map)['v'] ?? ''}',
            naam: '${(e.value as Map)['n'] ?? ''}',
          ),
    });
  }
}

// ── De dienst op de pc ─────────────────────────────────────────────────────

/// Eén bron: geeft voor deze zaden zijn nummers, met waar ze vandaan komen.
typedef OntdekBronFn = Future<List<OntdekNummer>> Function(List<OntdekArtiest> zaden);

/// De dienst op de pc: rekent één keer per dag (en op de ververs-knop), bewaart, en geeft meteen wat er ligt. Een
/// toestel krijgt het via `/api/ontdek` en tikt weg via `/api/ontdek/weg`.
class OntdekVoorJou {
  OntdekVoorJou({
    required this.artiesten,
    required this.heb,
    required this.bestand,
    required this.wegBestand,
    required this.deezer,
    this.lastfm,
    this.claude,
    this.log,
    DateTime Function()? klok,
    math.Random? toeval,
  }) : klok = klok ?? DateTime.now,
       _toeval = toeval ?? math.Random();

  /// De dienst van deze pc, als die er is (`server.dart`, het scherm Ontdek).
  static OntdekVoorJou? pc;

  /// Je artiesten, met hun gewicht en hoek. Krijgt [OntdekWeg] mee zodat het gewicht kan zakken.
  final List<OntdekArtiest> Function(OntdekWeg weg) artiesten;
  final bool Function(String artiest, String titel) heb;
  final File bestand;
  final File wegBestand;
  final OntdekBronFn deezer;
  final OntdekBronFn? lastfm;

  /// Claude: duur, dus hoogstens [kClaudePerDag] keer per dag; wat hij gaf blijft die dag liggen ([_pool]).
  final OntdekBronFn? claude;
  final void Function(String regel)? log;
  final DateTime Function() klok;
  final math.Random _toeval;

  static const int kClaudePerDag = 2;

  /// Minder ongetoonde nummers van Claude dan dit, en een ververs mag hem (de tweede keer die dag) opnieuw vragen.
  static const int kPoolVers = 10;

  OntdekLijst? _lijst;
  OntdekLijst? get lijst => _lijst;
  OntdekWeg _weg = OntdekWeg();
  OntdekWeg get weg => _weg;

  /// De lijst zonder wat er weggetikt is (ook de artiesten die twee keer weg gingen): wat een scherm te zien krijgt.
  /// Wat je intussen ophaalde, zeeft het scherm zelf weg, tegen zijn eigen bibliotheek.
  List<OntdekNummer> get zichtbaar {
    final l = _lijst;
    if (l == null) return const [];
    final weg = _weg.nummers, artiesten = _weg.artiesten(nuMs: klok().millisecondsSinceEpoch);
    return [
      for (final n in l.nummers)
        if (!weg.contains(n.sleutel) && !artiesten.contains(ontdekArtiest(n.nummer.artist))) n,
    ];
  }

  /// Wat Claude vandaag gaf, en hoe vaak hij vandaag gevraagd is.
  List<OntdekNummer> _pool = const [];
  String _poolDag = '';
  int _claudeVandaag = 0;

  /// Sleutel → wanneer hij voor het eerst in een lijst stond.
  final Map<String, int> _getoond = {};

  Future<OntdekLijst?>? _bezig;
  bool get bezig => _bezig != null;
  Timer? _klokje;

  static String _dag(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// Van gisteren (of ouder): dan rekent hij opnieuw.
  bool get verouderd {
    final l = _lijst;
    if (l == null) return true;
    return _dag(DateTime.fromMillisecondsSinceEpoch(l.berekendMs)) != _dag(klok());
  }

  Future<void> laad() async {
    try {
      if (await bestand.exists()) {
        final j = jsonDecode(await bestand.readAsString());
        _lijst = OntdekLijst.fromJson(j);
        if (j is Map) {
          _poolDag = (j['poolDag'] as String?) ?? '';
          _claudeVandaag = (j['claudeVandaag'] as num?)?.toInt() ?? 0;
          _pool = [for (final n in (j['pool'] as List? ?? const [])) ?OntdekNummer.fromJson(n)];
          final g = j['getoond'];
          if (g is Map) {
            for (final e in g.entries) {
              if (e.value is num) _getoond['${e.key}'] = (e.value as num).toInt();
            }
          }
        }
      }
    } catch (_) {
      /* kapot of oud: dan rekenen we opnieuw */
    }
    try {
      if (await wegBestand.exists()) _weg = OntdekWeg.fromJson(jsonDecode(await wegBestand.readAsString()));
    } catch (_) {}
  }

  /// Een minuut na de start als de lijst van gisteren is, daarna elk uur kijken of er een nieuwe dag is.
  void start({Duration eerst = const Duration(seconds: 60)}) {
    _klokje?.cancel();
    Timer(eerst, () {
      if (verouderd) unawaited(ververs());
    });
    _klokje = Timer.periodic(const Duration(hours: 1), (_) {
      if (verouderd) unawaited(ververs());
    });
  }

  void stop() => _klokje?.cancel();

  /// Rekent opnieuw; loopt er al een berekening, dan wacht deze daarop.
  Future<OntdekLijst?> ververs() {
    final lopend = _bezig;
    if (lopend != null) return lopend;
    final werk = _reken();
    _bezig = werk;
    return werk.whenComplete(() => _bezig = null);
  }

  /// Wegtikken (of met [terug] ongedaan maken), en bewaren.
  Future<void> zetWeg(String artiest, String titel, {String via = '', bool terug = false}) async {
    if (terug) {
      _weg.terug(artiest, titel);
    } else {
      _weg.zet(artiest, titel, via: via, nuMs: klok().millisecondsSinceEpoch);
    }
    log?.call('ontdek: ${terug ? 'terug' : 'weg'} — $artiest — $titel${via.isEmpty ? '' : ' (via $via)'}');
    try {
      await wegBestand.writeAsString(jsonEncode(_weg.toJson()));
    } catch (_) {}
  }

  Future<OntdekLijst?> _reken() async {
    final t0 = DateTime.now();
    final nu = klok();
    final nuMs = nu.millisecondsSinceEpoch;
    final alle = artiesten(_weg);
    if (alle.isEmpty) {
      log?.call('ontdek: nog geen bibliotheek — over twee minuten opnieuw');
      Timer(const Duration(minutes: 2), () => unawaited(ververs()));
      return _lijst;
    }
    final zaden = kiesOntdekZaden(alle, toeval: _toeval);
    final vandaag = _dag(nu);
    if (_poolDag != vandaag) {
      _poolDag = vandaag;
      _claudeVandaag = 0;
      _pool = const [];
    }
    // Claude één keer per dag, en nog één keer als verversen de pool van vandaag opmaakte (minder dan [kPoolVers] die
    // nog niet getoond zijn).
    final poolVers = _pool
        .where(
          (n) =>
              !heb(n.nummer.artist, n.nummer.title) &&
              !_weg.nummers.contains(n.sleutel) &&
              !_getoond.containsKey(n.sleutel),
        )
        .length;
    final vraagClaude = claude != null && _claudeVandaag < kClaudePerDag && poolVers < kPoolVers;
    Future<List<OntdekNummer>> veilig(OntdekBronFn? f, String naam) async {
      if (f == null) return const [];
      try {
        return await f(zaden);
      } catch (e) {
        log?.call('ontdek: $naam mislukt — $e');
        return const [];
      }
    }

    final (dz, lf, cl) = await (
      veilig(deezer, 'deezer'),
      veilig(lastfm, 'last.fm'),
      vraagClaude ? veilig(claude, 'claude') : Future.value(const <OntdekNummer>[]),
    ).wait;
    if (vraagClaude) {
      _claudeVandaag++;
      if (cl.isNotEmpty) _pool = cl;
    }
    final perBron = {
      Ontdekbron.claude: [..._pool]..shuffle(_toeval),
      Ontdekbron.lastfm: lf,
      Ontdekbron.deezer: dz,
    };
    // Vergeet wat al lang niet meer getoond werd: het mag weer vooraan.
    _getoond.removeWhere((_, ms) => nuMs - ms > kAlGetoond.inMilliseconds);
    final nummers = stelOntdekSamen(
      perBron,
      heb: heb,
      weg: _weg.nummers,
      wegArtiesten: _weg.artiesten(nuMs: nuMs),
      getoondOp: _getoond,
      nuMs: nuMs,
    );
    if (nummers.isEmpty && _lijst != null) {
      log?.call('ontdek: niets gevonden — de vorige lijst blijft');
      return _lijst;
    }
    for (final n in nummers.take(kOntdekGetoond)) {
      _getoond.putIfAbsent(n.sleutel, () => nuMs);
    }
    final l = OntdekLijst(nuMs, nummers);
    _lijst = l;
    try {
      await bestand.writeAsString(
        jsonEncode({
          ...l.toJson(),
          'poolDag': _poolDag,
          'claudeVandaag': _claudeVandaag,
          'pool': [for (final n in _pool) n.toJson()],
          'getoond': _getoond,
        }),
      );
    } catch (_) {}
    final hoeken = <String, int>{};
    for (final z in zaden) {
      hoeken[z.hoek] = (hoeken[z.hoek] ?? 0) + 1;
    }
    int van(Ontdekbron b) => nummers.where((n) => n.bron == b).length;
    log?.call(
      'ontdek: ${math.min(nummers.length, kOntdekGetoond)} + '
      '${math.max(0, nummers.length - kOntdekGetoond)} reserve uit ${zaden.length} zaden '
      '(${hoeken.entries.map((e) => '${e.key} ${e.value}').join(', ')}) — '
      'claude ${van(Ontdekbron.claude)}${vraagClaude ? ' (gevraagd: ${cl.length})' : ''}, '
      'last.fm ${van(Ontdekbron.lastfm)} (van ${lf.length}), deezer ${van(Ontdekbron.deezer)} (van ${dz.length}), '
      '${nummers.where((n) => n.verder).length} verder — ${_weg.aantal} weggetikt — '
      'in ${(DateTime.now().difference(t0).inMilliseconds / 1000).toStringAsFixed(1)} s',
    );
    return l;
  }
}

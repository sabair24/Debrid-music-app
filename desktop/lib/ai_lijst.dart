/// AI-afspeellijsten: een lijst die de AI voorstelt, die je eerst ziet en bewerkt voor er iets gedownload wordt.
///
/// Saber, 23-11-2026, bij "Zeg wat je wil horen" → *"maak me een lijst van 200 kerstliedjes, klasiekers, maar ook
/// modernere liedjes"*: *"ik wil dat AI ook afspeel lijsten kan maken, met op voorhand een lijst zonder iets te
/// downloaden om te kijken wat hij voorstelt, eventueel liedjes eruit haalt of toevoegd"*. Zijn keuzes (zie het
/// geheugen, ai-afspeellijsten-keuzes-23-11):
///  * vooral nieuwe nummers — wat hij al heeft, telt hoogstens voor [kAiLijstEigenAandeel] mee;
///  * hoogstens [kAiLijstPerArtiest] nummers per artiest;
///  * de volgorde is een opbouw van de AI (schudden kan met de gewone knop);
///  * elk nummer krijgt een hoek, voor de mix ([kiesMix]);
///  * een reserve ([AiLijstVoorstel.reserve]) voor ↻ vervangen en de mix, zonder een nieuwe vraag;
///  * bijsturen met een zin geeft eerst het verschil ([Bijsturing]), en pas na "overnemen" verandert de lijst.
///
/// Elk voorstel wordt daarna nagetrokken (Deezer, iTunes, je eigen bibliotheek): wat niemand kent, staat grijs als
/// "niet gevonden, misschien verzonnen" en standaard uit de lijst ([LijstBron.nergens]). Gemeten op 22-10-2026: van
/// acht nummers die geen catalogus kende, had het model er zeven aan de verkeerde artiest gegeven.
library;

import 'radiokeuze.dart' show artiestSleutel, basisTitel;

/// Hoeveel nummers per artiest (Saber: "Hoogstens 2").
const int kAiLijstPerArtiest = 2;

/// Zoveel van de lijst mag hoogstens uit je eigen bibliotheek komen (Saber: "Vooral nieuw").
const double kAiLijstEigenAandeel = 0.1;

/// Zoveel nummers als de zin geen aantal noemt.
const int kAiLijstStandaard = 50;

/// Meer vraagt de app nooit in één keer: het antwoord moet in één keer passen (zie [kAiLijstMaxTokens]).
const int kAiLijstHoogstens = 300;

/// De reserve: de helft van de lijst erbij, minstens 15, hoogstens 100.
int aiLijstReserve(int aantal) => (aantal / 2).round().clamp(15, 100);

/// Ruimte voor het antwoord: een regel kost ~30 tokens; 300 nummers + 100 reserve passen ruim.
const int kAiLijstMaxTokens = 32000;

/// Waar een nummer gevonden werd.
enum LijstBron {
  /// Nog niet nagetrokken.
  bezig,
  deezer,
  itunes,

  /// In je eigen bibliotheek: meteen in jouw kwaliteit.
  eigen,

  /// Alleen op Soulseek (de proef vond hem).
  soulseek,

  /// Niemand kent hem: misschien verzonnen. Standaard uit de lijst.
  nergens,
}

/// Eén regel van een AI-lijst.
class LijstNummer {
  LijstNummer({
    required this.artiest,
    required this.titel,
    this.jaar,
    this.hoek = '',
    this.bron = LijstBron.bezig,
    this.hoes,
    this.seconden = 0,
    this.album = '',
    this.deezerId = 0,
    this.fragment,
    this.eigenId,
    bool? aan,
  }) : aan = aan ?? true;

  final String artiest;
  final String titel;
  final int? jaar;

  /// De hoek volgens de AI ("Klassiekers", "Modern", "Nederlandstalig"…), voor de mix.
  final String hoek;

  LijstBron bron;
  String? hoes;
  int seconden;
  String album;
  int deezerId;

  /// Een fragment van 30 s (Deezer of iTunes), zonder iets te downloaden.
  String? fragment;

  /// Het gedeelde id van het nummer in je bibliotheek, zodra het er is (eigen, of na het halen).
  String? eigenId;

  /// Staat hij in de lijst? Een niet-gevonden nummer staat er standaard uit.
  bool aan;

  String get sleutel => '${artiestSleutel(artiest)}|${basisTitel(titel)}';

  bool get gevonden => bron != LijstBron.bezig && bron != LijstBron.nergens;

  Map<String, dynamic> toJson() => {
        'a': artiest,
        't': titel,
        if (jaar != null) 'j': jaar,
        if (hoek.isNotEmpty) 'h': hoek,
        'b': bron.name,
        if (hoes != null) 'c': hoes,
        if (seconden > 0) 's': seconden,
        if (album.isNotEmpty) 'al': album,
        if (deezerId > 0) 'd': deezerId,
        if (fragment != null) 'f': fragment,
        if (eigenId != null) 'id': eigenId,
        if (!aan) 'uit': true,
      };

  static LijstNummer? fromJson(Object? m) {
    if (m is! Map) return null;
    final a = '${m['a'] ?? ''}'.trim(), t = '${m['t'] ?? ''}'.trim();
    if (a.isEmpty || t.isEmpty) return null;
    return LijstNummer(
      artiest: a,
      titel: t,
      jaar: (m['j'] as num?)?.toInt(),
      hoek: '${m['h'] ?? ''}',
      bron: LijstBron.values.where((b) => b.name == m['b']).firstOrNull ?? LijstBron.bezig,
      hoes: m['c'] as String?,
      seconden: (m['s'] as num?)?.toInt() ?? 0,
      album: '${m['al'] ?? ''}',
      deezerId: (m['d'] as num?)?.toInt() ?? 0,
      fragment: m['f'] as String?,
      eigenId: m['id'] as String?,
      aan: m['uit'] != true,
    );
  }
}

/// Een hoek en zijn aandeel in procenten, zoals de AI hem voorstelde.
typedef LijstHoek = ({String naam, int aandeel});

/// Wat de AI voorstelde: de lijst (in de volgorde van de opbouw) en een reserve.
class AiLijstVoorstel {
  AiLijstVoorstel({
    required this.naam,
    required this.zin,
    required this.hoeken,
    required this.nummers,
    required this.reserve,
    this.aantal = kAiLijstStandaard,
    this.verzameling,
  });

  String naam;

  /// De verzameling waar wat gehaald wordt naartoe gaat (Saber: "In een eigen verzameling"); gezet bij het opslaan.
  String? verzameling;
  final String zin;
  List<LijstHoek> hoeken;
  final List<LijstNummer> nummers;
  final List<LijstNummer> reserve;

  /// Hoeveel nummers de lijst hoort te hebben (wat de zin vroeg).
  int aantal;

  /// Wat er nu in de lijst staat.
  List<LijstNummer> get actief => [for (final n in nummers) if (n.aan) n];

  Map<String, dynamic> toJson() => {
        'naam': naam,
        'zin': zin,
        'aantal': aantal,
        if (verzameling != null) 'verzameling': verzameling,
        'hoeken': [for (final h in hoeken) {'naam': h.naam, 'aandeel': h.aandeel}],
        'nummers': [for (final n in nummers) n.toJson()],
        'reserve': [for (final n in reserve) n.toJson()],
      };

  static AiLijstVoorstel? fromJson(Object? m) {
    if (m is! Map) return null;
    List<LijstNummer> lees(Object? l) =>
        [for (final x in (l is List ? l : const [])) ?LijstNummer.fromJson(x)];
    return AiLijstVoorstel(
      naam: '${m['naam'] ?? ''}',
      zin: '${m['zin'] ?? ''}',
      aantal: (m['aantal'] as num?)?.toInt() ?? kAiLijstStandaard,
      verzameling: m['verzameling'] is String && (m['verzameling'] as String).trim().isNotEmpty ? m['verzameling'] as String : null,
      hoeken: [
        for (final h in (m['hoeken'] is List ? m['hoeken'] as List : const []))
          if (h is Map && '${h['naam'] ?? ''}'.trim().isNotEmpty)
            (naam: '${h['naam']}'.trim(), aandeel: (h['aandeel'] as num?)?.toInt() ?? 0),
      ],
      nummers: lees(m['nummers']),
      reserve: lees(m['reserve']),
    );
  }
}

/// Het schema voor [aiLijstPrompt]. Zonder getalgrenzen: de Messages-API weigert `minimum` en `maxItems`.
Map<String, dynamic> aiLijstSchema() {
  Map<String, dynamic> nummer() => {
        'type': 'object',
        'properties': {
          'artiest': {'type': 'string', 'description': 'De naam zoals op de plaat.'},
          'titel': {'type': 'string', 'description': 'De titel zoals op de plaat, zonder "Remix", "Live" of "Remastered".'},
          'jaar': {'type': 'integer', 'description': 'Het jaar van de oorspronkelijke opname.'},
          'hoek': {'type': 'string', 'description': 'Eén van de hoeken hierboven, letterlijk.'},
        },
        'required': ['artiest', 'titel', 'jaar', 'hoek'],
        'additionalProperties': false,
      };
  return {
    'type': 'object',
    'properties': {
      'naam': {'type': 'string', 'description': 'Een korte, mooie naam voor de lijst, in het Nederlands.'},
      'aantal': {'type': 'integer', 'description': 'Hoeveel nummers de luisteraar vroeg.'},
      'hoeken': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'naam': {'type': 'string'},
            'aandeel': {'type': 'integer', 'description': 'Procent van de lijst.'},
          },
          'required': ['naam', 'aandeel'],
          'additionalProperties': false,
        },
      },
      'nummers': {'type': 'array', 'items': nummer()},
      'reserve': {'type': 'array', 'items': nummer()},
    },
    'required': ['naam', 'aantal', 'hoeken', 'nummers', 'reserve'],
    'additionalProperties': false,
  };
}

/// De vraag voor een nieuwe lijst. [eigen]: een greep uit wat hij al heeft ("artiest — titel"), zodat de AI vooral
/// iets anders kiest.
String aiLijstPrompt(String zin, {List<String> eigen = const []}) => '''
Iemand gebruikt een muziekapp en vraagt om een afspeellijst: "$zin"

Stel die lijst samen.

1. Hoeveel: zoveel als hij vraagt; zegt hij niets, $kAiLijstStandaard. Nooit meer dan $kAiLijstHoogstens. Zet dat getal in "aantal".
2. Alleen nummers die BESTAAN, met de artiest en de titel zoals op de plaat. Elk nummer wordt opgezocht in een
   muziekcatalogus; een verzonnen titel of een nummer bij de verkeerde artiest verdwijnt.
3. Hoogstens $kAiLijstPerArtiest nummers per artiest, in de lijst en de reserve samen.
4. Vooral nummers die hij nog niet heeft. Wat hij al heeft (een greep): ${eigen.isEmpty ? '(onbekend)' : eigen.take(80).join('; ')}
5. Verdeel de lijst in 2 tot 5 hoeken die bij de vraag passen (bijvoorbeeld "Klassiekers", "Modern", "Nederlandstalig"),
   met een aandeel in procenten dat optelt tot 100, en geef elk nummer zijn hoek.
6. De volgorde van "nummers" is de volgorde waarin hij ze hoort: een opbouw die loopt, niet per hoek gegroepeerd en
   niet twee keer dezelfde artiest na elkaar.
7. "reserve": nog ongeveer de helft zoveel andere nummers in dezelfde geest en hoeken — om te vervangen wat hij
   weghaalt. Geen dubbels met "nummers".
8. Geen covers van karaoke- of "tribute"-artiesten, geen live-, remix- of kinderversies tenzij hij daarom vraagt.
9. Een korte naam voor de lijst, in het Nederlands.
''';

/// Een greep uit wat je al hebt ("artiest — titel"), voor [aiLijstPrompt]: gelijk verdeeld over [regels], hoogstens [hoeveel].
List<String> aiLijstEigen(List<String> regels, {int hoeveel = 40}) {
  if (regels.isEmpty) return const [];
  final stap = (regels.length / hoeveel).ceil().clamp(1, regels.length);
  return [for (var i = 0; i < regels.length; i += stap) regels[i]].take(hoeveel).toList();
}

/// Leest het antwoord van [aiLijstPrompt]: dubbels weg, hoogstens [kAiLijstPerArtiest] per artiest (wat erover gaat,
/// schuift naar de reserve), het aantal begrensd. Null als er niets bruikbaars in staat.
AiLijstVoorstel? leesAiLijst(Object? j, {required String zin}) {
  if (j is! Map) return null;
  final gezien = <String>{};
  final perArtiest = <String, int>{};
  List<LijstNummer> lees(Object? l, {List<LijstNummer>? teveel}) {
    final uit = <LijstNummer>[];
    for (final x in (l is List ? l : const [])) {
      if (x is! Map) continue;
      final a = '${x['artiest'] ?? ''}'.trim(), t = '${x['titel'] ?? ''}'.trim();
      if (a.isEmpty || t.isEmpty) continue;
      final n = LijstNummer(artiest: a, titel: t, jaar: (x['jaar'] as num?)?.toInt(), hoek: '${x['hoek'] ?? ''}'.trim());
      if (!gezien.add(n.sleutel)) continue;
      final k = artiestSleutel(a);
      if ((perArtiest[k] ?? 0) >= kAiLijstPerArtiest) {
        teveel?.add(n);
        continue;
      }
      perArtiest[k] = (perArtiest[k] ?? 0) + 1;
      uit.add(n);
    }
    return uit;
  }

  final aantal = ((j['aantal'] as num?)?.toInt() ?? kAiLijstStandaard).clamp(1, kAiLijstHoogstens);
  final teveel = <LijstNummer>[];
  final nummers = lees(j['nummers'], teveel: teveel);
  final reserve = lees(j['reserve']);
  if (nummers.isEmpty) return null;
  // Meer dan gevraagd: de rest is reserve. Minder: zo blijft het.
  if (nummers.length > aantal) reserve.insertAll(0, nummers.sublist(aantal));
  return AiLijstVoorstel(
    naam: '${j['naam'] ?? ''}'.trim().isEmpty ? zin.trim() : '${j['naam']}'.trim(),
    zin: zin,
    aantal: aantal,
    hoeken: [
      for (final h in (j['hoeken'] is List ? j['hoeken'] as List : const []))
        if (h is Map && '${h['naam'] ?? ''}'.trim().isNotEmpty)
          (naam: '${h['naam']}'.trim(), aandeel: ((h['aandeel'] as num?)?.toInt() ?? 0).clamp(0, 100)),
    ],
    nummers: nummers.take(aantal).toList(),
    reserve: reserve,
  );
}

/// Na het natrekken: wat niemand kent, staat uit; van je eigen nummers blijven er hoogstens [kAiLijstEigenAandeel] van
/// de lijst aan — de rest gaat naar het einde van de reserve (Saber: "Vooral nieuw"). Een plek die vrijkomt, vult de
/// reserve aan met wat wél gevonden en nieuw is. Geeft terug hoeveel er vervangen werd.
int pasRegelsToe(AiLijstVoorstel v) {
  final maxEigen = (v.aantal * kAiLijstEigenAandeel).floor();
  var eigen = 0, vervangen = 0;
  for (var i = 0; i < v.nummers.length; i++) {
    final n = v.nummers[i];
    if (n.bron == LijstBron.nergens) n.aan = false;
    if (n.bron != LijstBron.eigen || !n.aan) continue;
    if (eigen < maxEigen) {
      eigen++;
      continue;
    }
    final nieuw = _volgendeUitReserve(v, nietEigen: true);
    if (nieuw == null) continue;
    v.reserve.add(n);
    v.nummers[i] = nieuw;
    vervangen++;
  }
  return vervangen;
}

LijstNummer? _volgendeUitReserve(AiLijstVoorstel v, {bool nietEigen = false, String? hoek}) {
  final per = _perArtiest(v.actief);
  for (var i = 0; i < v.reserve.length; i++) {
    final r = v.reserve[i];
    if (r.bron == LijstBron.nergens) continue;
    if (nietEigen && r.bron == LijstBron.eigen) continue;
    if (hoek != null && r.hoek != hoek) continue;
    if ((per[artiestSleutel(r.artiest)] ?? 0) >= kAiLijstPerArtiest) continue;
    return v.reserve.removeAt(i)..aan = true;
  }
  return null;
}

Map<String, int> _perArtiest(Iterable<LijstNummer> l) {
  final m = <String, int>{};
  for (final n in l) {
    m[artiestSleutel(n.artiest)] = (m[artiestSleutel(n.artiest)] ?? 0) + 1;
  }
  return m;
}

/// ↻: vervang het nummer op plek [i] door het volgende uit de reserve, liefst uit dezelfde hoek. Het oude gaat achteraan
/// de reserve (zo kan hij terugkomen). Null als de reserve leeg is — dan vraagt de app de AI om meer.
LijstNummer? vervang(AiLijstVoorstel v, int i) {
  if (i < 0 || i >= v.nummers.length) return null;
  final oud = v.nummers[i];
  final nieuw = _volgendeUitReserve(v, hoek: oud.hoek, nietEigen: true) ?? _volgendeUitReserve(v, nietEigen: true);
  if (nieuw == null) return null;
  v.nummers[i] = nieuw;
  v.reserve.add(oud..aan = true);
  return nieuw;
}

/// De mix (ontwerp D): kies uit lijst en reserve samen [aantal] nummers volgens [aandelen] (hoek → gewicht), in de volgorde
/// van de opbouw, met hoogstens [kAiLijstPerArtiest] per artiest. Wat er in een hoek tekort is, vult de rest aan.
/// Niet-gevonden nummers doen niet mee.
List<LijstNummer> kiesMix(AiLijstVoorstel v, Map<String, int> aandelen, int aantal) {
  final pool = [
    for (final n in [...v.nummers, ...v.reserve])
      if (n.bron != LijstBron.nergens) n
  ];
  final som = aandelen.values.fold<int>(0, (a, b) => a + b);
  final doel = <String, int>{
    for (final e in aandelen.entries) e.key: som == 0 ? 0 : (aantal * e.value / som).round(),
  };
  final per = <String, int>{};
  final gekozen = <LijstNummer>{};
  bool past(LijstNummer n) => (per[artiestSleutel(n.artiest)] ?? 0) < kAiLijstPerArtiest;
  void neem(LijstNummer n) {
    gekozen.add(n);
    per[artiestSleutel(n.artiest)] = (per[artiestSleutel(n.artiest)] ?? 0) + 1;
  }

  final telHoek = <String, int>{};
  for (final n in pool) {
    if (gekozen.length >= aantal) break;
    final d = doel[n.hoek];
    if (d == null || (telHoek[n.hoek] ?? 0) >= d || !past(n)) continue;
    neem(n);
    telHoek[n.hoek] = (telHoek[n.hoek] ?? 0) + 1;
  }
  // Tekort in een hoek: aanvullen met wat er nog is, in de volgorde van de opbouw — eerst hoeken met een aandeel.
  for (final n in pool) {
    if (gekozen.length >= aantal) break;
    if (gekozen.contains(n) || !past(n) || (aandelen[n.hoek] ?? 1) == 0) continue;
    neem(n);
  }
  // Houd de volgorde van de opbouw: eerst wat al in de lijst stond, dan de reserve.
  return [for (final n in pool) if (gekozen.contains(n)) n];
}

/// Een nummer van de lijst landde (afspelen haalt het): de regel van [artiest] — [titel] krijgt [id], en is voortaan van
/// jou. Geeft terug of er een regel was. Op het liedje en niet de letterlijke titel ("X (Remastered)" is X).
bool regelGeland(AiLijstVoorstel v, String artiest, String titel, String id) {
  final s = LijstNummer(artiest: artiest, titel: titel).sleutel;
  for (final n in v.nummers) {
    if (n.sleutel != s) continue;
    n
      ..eigenId = id
      ..aan = true;
    if (n.bron == LijstBron.nergens || n.bron == LijstBron.bezig) n.bron = LijstBron.soulseek;
    return true;
  }
  return false;
}

/// De gedeelde id's van wat je al hebt in [v], in de volgorde van de lijst — voor `Playlist.trackIds`.
List<String> eigenIdsVan(AiLijstVoorstel v) => [for (final n in v.actief) if (n.eigenId case final id?) id];

/// Wat een zin om bij te sturen voorstelt: wat eruit gaat (plekken in [AiLijstVoorstel.nummers]) en wat erbij komt.
class Bijsturing {
  const Bijsturing({required this.weg, required this.erbij, this.naam});
  final List<int> weg;
  final List<LijstNummer> erbij;

  /// Een nieuwe naam, als de zin daarom vroeg of de lijst er echt anders door wordt.
  final String? naam;

  bool get leeg => weg.isEmpty && erbij.isEmpty;

  Map<String, dynamic> toJson() => {
        'weg': weg,
        'erbij': [for (final n in erbij) n.toJson()],
        if (naam != null) 'naam': naam,
      };

  static Bijsturing fromJson(Object? m) {
    if (m is! Map) return const Bijsturing(weg: [], erbij: []);
    return Bijsturing(
      weg: [for (final i in (m['weg'] is List ? m['weg'] as List : const [])) if (i is num) i.toInt()],
      erbij: [for (final x in (m['erbij'] is List ? m['erbij'] as List : const [])) ?LijstNummer.fromJson(x)],
      naam: m['naam'] is String && (m['naam'] as String).trim().isNotEmpty ? m['naam'] as String : null,
    );
  }
}

/// Het schema voor [bijsturenPrompt].
Map<String, dynamic> bijsturenSchema() {
  Map<String, dynamic> regel(bool metHoek) => {
        'type': 'object',
        'properties': {
          'artiest': {'type': 'string'},
          'titel': {'type': 'string'},
          if (metHoek) 'jaar': {'type': 'integer'},
          if (metHoek) 'hoek': {'type': 'string'},
        },
        'required': ['artiest', 'titel', if (metHoek) 'jaar', if (metHoek) 'hoek'],
        'additionalProperties': false,
      };
  return {
    'type': 'object',
    'properties': {
      'weg': {'type': 'array', 'items': regel(false)},
      'erbij': {'type': 'array', 'items': regel(true)},
      'naam': {'type': 'string', 'description': 'Leeg laten, tenzij de lijst echt een andere naam nodig heeft.'},
    },
    'required': ['weg', 'erbij', 'naam'],
    'additionalProperties': false,
  };
}

/// De vraag om bij te sturen: de lijst zoals hij nu is, en wat de luisteraar wil. Ook "meer zoals dit" is een zin.
String bijsturenPrompt(AiLijstVoorstel v, String zin) => '''
Iemand heeft een afspeellijst "${v.naam}" (gevraagd als: "${v.zin}"). Hij wil hem bijsturen: "$zin"

De lijst nu, in volgorde (artiest — titel [hoek]):
${[for (final n in v.actief) '- ${n.artiest} — ${n.titel} [${n.hoek}]'].join('\n')}

Hoeken: ${v.hoeken.map((h) => '${h.naam} (${h.aandeel}%)').join(', ')}

Zeg wat eruit moet ("weg", letterlijk zoals hierboven) en wat erbij komt ("erbij"). Alleen wat de zin vraagt: de rest
blijft. Wat erbij komt: alleen nummers die BESTAAN, met de titel zoals op de plaat, hoogstens $kAiLijstPerArtiest per
artiest in de hele lijst, niets wat er al in staat, en elk met een hoek (een bestaande, of een nieuwe als de zin
daarom vraagt). Vraagt de zin om meer nummers ("nog 20"), geef er zoveel.
''';

/// Leest het antwoord van [bijsturenPrompt] tegen [v]: wat weg moet, op plek; wat erbij komt, zonder dubbels en binnen
/// [kAiLijstPerArtiest].
Bijsturing leesBijsturing(Object? j, AiLijstVoorstel v) {
  if (j is! Map) return const Bijsturing(weg: [], erbij: []);
  final plek = <String, int>{for (var i = 0; i < v.nummers.length; i++) v.nummers[i].sleutel: i};
  final weg = <int>{};
  for (final x in (j['weg'] is List ? j['weg'] as List : const [])) {
    if (x is! Map) continue;
    final n = LijstNummer(artiest: '${x['artiest'] ?? ''}', titel: '${x['titel'] ?? ''}');
    final i = plek[n.sleutel];
    if (i != null && v.nummers[i].aan) weg.add(i);
  }
  final blijft = [for (var i = 0; i < v.nummers.length; i++) if (v.nummers[i].aan && !weg.contains(i)) v.nummers[i]];
  final per = _perArtiest(blijft);
  final al = {for (final n in blijft) n.sleutel};
  final erbij = <LijstNummer>[];
  for (final x in (j['erbij'] is List ? j['erbij'] as List : const [])) {
    if (x is! Map) continue;
    final a = '${x['artiest'] ?? ''}'.trim(), t = '${x['titel'] ?? ''}'.trim();
    if (a.isEmpty || t.isEmpty) continue;
    final n = LijstNummer(artiest: a, titel: t, jaar: (x['jaar'] as num?)?.toInt(), hoek: '${x['hoek'] ?? ''}'.trim());
    if (!al.add(n.sleutel)) continue;
    if ((per[artiestSleutel(a)] ?? 0) >= kAiLijstPerArtiest) continue;
    per[artiestSleutel(a)] = (per[artiestSleutel(a)] ?? 0) + 1;
    erbij.add(n);
  }
  final naam = '${j['naam'] ?? ''}'.trim();
  return Bijsturing(weg: weg.toList()..sort(), erbij: erbij, naam: naam.isEmpty ? null : naam);
}

/// Neemt [b] over in [v]: wat weg moet, gaat naar de reserve (het kan terugkomen); wat erbij komt, komt op de plek van
/// wat wegging en anders achteraan. Nieuwe hoeken komen bij de hoeken.
void neemBijsturingOver(AiLijstVoorstel v, Bijsturing b) {
  final vrij = [...b.weg];
  for (final i in b.weg) {
    v.reserve.add(v.nummers[i]);
  }
  final nieuw = [...b.erbij];
  // Op de vrijgekomen plekken, in volgorde; de rest achteraan.
  final uit = <LijstNummer>[];
  for (var i = 0; i < v.nummers.length; i++) {
    if (vrij.contains(i)) {
      if (nieuw.isNotEmpty) uit.add(nieuw.removeAt(0));
      continue;
    }
    uit.add(v.nummers[i]);
  }
  uit.addAll(nieuw);
  v.nummers
    ..clear()
    ..addAll(uit);
  for (final n in b.erbij) {
    if (n.hoek.isNotEmpty && !v.hoeken.any((h) => h.naam == n.hoek)) v.hoeken = [...v.hoeken, (naam: n.hoek, aandeel: 0)];
  }
  if (b.naam != null) v.naam = b.naam!;
  v.aantal = v.actief.length;
}

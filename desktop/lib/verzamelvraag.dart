/// De vraag aan Claude om je bibliotheek in te delen in verzamelingen (Saber, 21-11-2026: "gebruik ook ai om de genre
/// te onderscheiden en zo met bestaande music ook te verzamelen"). Het model stelt voor, Saber keurt goed ("Voorstel,
/// ik keur goed"; "AI stelt voor, ik pas aan") — er verhuist niets zonder zijn tik.
///
/// **Kritisch en juist.** Bij de eerste keer, de nummers van een radio vanaf Nancy Wilson, keurde Saber dit onderscheid
/// goed: vocal jazz (Ella, Sarah Vaughan, Nancy Wilson, Madeleine Peyroux) is iets anders dan de crooners en de
/// standards van de traditional pop (Sinatra, Dean Martin, Nat King Cole als zanger), en dat weer iets anders dan
/// soulklassiekers (Sam Cooke, Ben E. King, Etta James). Bigband en swing staan apart, als twijfel. En een popzangeres die
/// een standard zingt (Annie Lennox, Eva Cassidy) hoort in geen van alle: die blijft in de bibliotheek. Die lessen staan
/// in de vraag, met de redenen erbij.
///
/// **Gegevens rechtzetten** ("Ja, met een voorstel"): een genre dat geen genre is (een uploadernaam, "Various"), een
/// jaartal van een heruitgave, twee schrijfwijzen van één artiest. Ook dat alleen als voorstel.
///
/// Geen IO: de vraag, het schema en het uitlezen, zodat het na te rekenen is.
library;

import 'dart:math' as math;

import 'lossless_want.dart' show isVerzamelnaam;

/// Een verzameling is een kleine hoek: hoogstens dit deel van je gewone bibliotheek ([verzamelHoogstens]).
///
/// Saber, 22-11-2026, na de tweede ronde (Eurodance 113, Trance 135, Franse pop 155, Nederlandstalig 75): *"Nee, alleen
/// kleine hoeken"*. Een groter blok is zijn gewone muziek — dat hoort in zijn shuffle en zijn radio. Zijn eerste
/// verzamelingen lagen allemaal onder 2,5 % (Vocal jazz 51 van ~2200, Raï 49, Franse chanson 43).
const double kVerzamelAandeel = .03;

/// En nooit minder dan zoveel, zodat een kleine bibliotheek nog een hoek kan hebben.
const int kVerzamelGrensMinstens = 25;

/// Hoeveel nummers een voorgestelde verzameling hoogstens telt bij een gewone bibliotheek van [bibliotheek] nummers.
int verzamelHoogstens(int bibliotheek) =>
    math.max(kVerzamelGrensMinstens, (bibliotheek * kVerzamelAandeel).floor());

/// Een artiest zoals de vraag hem telt: zijn naam zoals hij in de bestanden staat, zonder hoofdletters. Bewust niet
/// `artiestSleutel` (radiokeuze.dart): die maakt van "Billie Holiday & Her Orchestra" Billie Holiday, en dan kan de
/// correctie die de twee schrijfwijzen samenbrengt er nooit komen.
String vraagSleutel(String artiest) => artiest.trim().toLowerCase();

/// Een verzameling pas vanaf zoveel nummers: minder is geen genre maar een toevalstreffer.
const int kVerzamelMinstens = 8;

/// Hoogstens zoveel correcties per keer: genoeg om te helpen, niet zoveel dat goedkeuren een avond werk is.
const int kCorrectiesHoogstens = 40;

/// Per artiest zoveel titels in de vraag; wie er meer heeft, krijgt er zoveel als voorbeeld.
const int kTitelsPerArtiest = 6;

/// Eén artiest zoals het model hem ziet.
typedef VraagArtiest = ({
  String artiest,
  int aantal,
  List<String> genres,
  List<String> tags,
  int? vanJaar,
  int? totJaar,
  List<String> titels,
});

/// Een bestaande verzameling: de naam en wie erin staat.
typedef VraagVerzameling = ({String naam, List<String> artiesten});

/// Eén artiest in een voorstel: [twijfel] als hij tussen twee verzamelingen of tussen een verzameling en de bibliotheek
/// in valt; [nietDeze]: titels van hem die er níet in horen.
typedef VoorstelArtiest = ({String artiest, bool twijfel, String opmerking, List<String> nietDeze});

/// Eén voorgestelde verzameling.
typedef AiVerzameling = ({String naam, String waarom, List<VoorstelArtiest> artiesten});

/// Eén correctie: [veld] is `genre`, `jaar` of `artiest`; [titel] leeg betekent alle nummers van [artiest].
typedef AiCorrectie = ({String artiest, String titel, String veld, String naar, String waarom});

/// Het antwoordschema. Elk veld in `properties` staat ook in `required`, anders weigert de API het hele schema.
Map<String, dynamic> verzamelSchema() => {
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'verzamelingen': {
          'type': 'array',
          'items': {
            'type': 'object',
            'additionalProperties': false,
            'properties': {
              'naam': {'type': 'string', 'description': 'Kort, zoals "Vocal jazz" of "Crooners & standards".'},
              'waarom': {'type': 'string', 'description': 'In het Nederlands, één zin: wat deze verzameling bijeenhoudt.'},
              'artiesten': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'additionalProperties': false,
                  'properties': {
                    'artiest': {'type': 'string', 'description': 'Precies zoals in de lijst.'},
                    'twijfel': {'type': 'boolean'},
                    'opmerking': {
                      'type': 'string',
                      'description': 'Bij twijfel waarom, in het Nederlands, hoogstens twaalf woorden; anders leeg.',
                    },
                    'nietDeze': {
                      'type': 'array',
                      'description': 'Titels van deze artiest (precies zoals in de lijst) die er NIET in horen.',
                      'items': {'type': 'string'},
                    },
                  },
                  'required': ['artiest', 'twijfel', 'opmerking', 'nietDeze'],
                },
              },
            },
            'required': ['naam', 'waarom', 'artiesten'],
          },
        },
        'correcties': {
          'type': 'array',
          'items': {
            'type': 'object',
            'additionalProperties': false,
            'properties': {
              'artiest': {'type': 'string', 'description': 'Precies zoals in de lijst.'},
              'titel': {'type': 'string', 'description': 'Precies zoals in de lijst, of leeg voor al zijn nummers.'},
              'veld': {
                'type': 'string',
                'enum': ['genre', 'jaar', 'artiest'],
              },
              'naar': {'type': 'string', 'description': 'De juiste waarde. Een jaar als vier cijfers.'},
              'waarom': {'type': 'string', 'description': 'In het Nederlands, hoogstens vijftien woorden.'},
            },
            'required': ['artiest', 'titel', 'veld', 'naar', 'waarom'],
          },
        },
      },
      'required': ['verzamelingen', 'correcties'],
    };

/// Eén regel per artiest: "Nancy Wilson · 6 nummers · genre: Jazz, Vocal Jazz · tags: vocal jazz, jazz, soul ·
/// 1960–1964 · Guess Who I Saw Today; …".
String vraagRegel(VraagArtiest a) {
  final delen = <String>[
    a.artiest,
    '${a.aantal} ${a.aantal == 1 ? 'nummer' : 'nummers'}',
    if (a.genres.isNotEmpty) 'genre: ${a.genres.join(', ')}',
    if (a.tags.isNotEmpty) 'tags: ${a.tags.join(', ')}',
    if (a.vanJaar != null) a.totJaar == null || a.totJaar == a.vanJaar ? '${a.vanJaar}' : '${a.vanJaar}–${a.totJaar}',
    if (a.titels.isNotEmpty) '${a.titels.join('; ')}${a.aantal > a.titels.length ? '; …' : ''}',
  ];
  return delen.join(' · ');
}

/// De vraag. Met de redenen erbij: een model dat weet waaróm een regel er is, houdt zich er beter aan.
String verzamelPrompt(List<VraagArtiest> bibliotheek, List<VraagVerzameling> bestaande,
    {List<String> afgewezen = const [], int? hoogstens}) {
  final grens = hoogstens ?? verzamelHoogstens(bibliotheek.fold<int>(0, (s, a) => s + a.aantal));
  final bib = bibliotheek.map(vraagRegel).join('\n');
  final al = bestaande.isEmpty
      ? '(nog geen)'
      : bestaande.map((v) => '- ${v.naam}: ${v.artiesten.take(15).join(', ')}').join('\n');
  return '''
Iemand gebruikt een muziekapp. Zijn bibliotheek is zijn gewone muziek: die schudt hij, daar draait zijn radio uit.
Sommige muziek wil hij APART: niet tussen zijn andere liedjes, maar om specifiek op te zetten als hij er zin in heeft.
Daarvoor heeft de app verzamelingen. Stel voor welke artiesten uit zijn bibliotheek in een verzameling horen.

Zijn bestaande verzamelingen:
$al

${afgewezen.isEmpty ? '' : 'Voorstellen die hij eerder afwees (stel ze niet opnieuw voor): ${afgewezen.join(', ')}\n\n'}Zijn bibliotheek, één artiest per regel (naam · aantal · genre in zijn bestanden · tags van luisteraars · jaren ·
titels):
$bib

Wat er echt toe doet:
1. Alleen een duidelijke, samenhangende niche die afwijkt van het grootste deel van zijn bibliotheek: een KLEINE hoek,
   vanaf $kVerzamelMinstens en hoogstens $grens nummers (ongeveer drie procent). Een groter blok — zijn eurodance, zijn
   trance en house, zijn Franse of Nederlandstalige pop — IS zijn gewone muziek: dat wil hij in zijn shuffle en zijn
   radio, en dat stel je nooit voor, ook niet als aanvulling van een bestaande verzameling. Hij zei het zelf: "alleen
   kleine hoeken".
2. Wees kritisch en juist in het genre. Hij keurde dit onderscheid al goed, en wil het zo:
   - vocal jazz (Ella Fitzgerald, Sarah Vaughan, Nancy Wilson, Madeleine Peyroux) is iets anders dan
   - crooners en standards uit de traditional pop (Frank Sinatra, Dean Martin, Bing Crosby, Nat King Cole als zanger),
     en dat weer iets anders dan
   - soulklassiekers (Sam Cooke, Ben E. King, Etta James).
   - Bigband en swing (Glenn Miller, Benny Goodman) staan apart; staan ze bij een van de andere, dan als twijfel.
   - Een popzanger of -zangeres die een standard zingt (Annie Lennox, Eva Cassidy, Wayne Newton) hoort in geen van
     alle: laat die weg.
   Valt een artiest tussen twee in, zet "twijfel" op true en zeg waarom.
3. Kijk bij elke artiest ELKE titel na. Een nummer dat niet past bij de rest in de verzameling (een popnummer van een
   crooner, een novelty, een kerstnummer, een cover van een popsong) zet je bij "nietDeze", met de titel precies zoals
   in de lijst. Hij wees al af: Frank Sinatra "Bad, Bad Leroy Brown" (een popnummer van Jim Croce) hoort niet bij de
   crooners, ook al hoort Sinatra er zelf wel bij.
4. Hoort iets bij een bestaande verzameling, gebruik dan precies haar naam; verzin geen tweede naam voor hetzelfde.
   Wat al in een verzameling staat, staat niet in de lijst hierboven.
5. Namen kort en gewoon, zoals "Vocal jazz", "Crooners & standards", "Soul classics", "Raï". Elke artiest in hoogstens
   één verzameling.
6. Correcties: alleen fouten die je zeker weet, hoogstens $kCorrectiesHoogstens.
   - genre: een genre dat geen genre is (een uploadernaam als "Toccara0217", "Various", "Unknown") of dat duidelijk
     niet klopt; zet er het genre van de artiest voor in de plaats.
   - jaar: het jaar van een heruitgave of verzamelaar in plaats van dat van de opname, als je het zeker weet (Etta James
     "At Last!" is van 1960, niet van 1990). Alleen met een titel, en alleen voor een los nummer (een single): bij een
     nummer op een album is het jaar dat van de plaat, en dat klopt dan.
   - artiest: twee schrijfwijzen van één artiest ("Billie Holiday & Her Orchestra" naast "Billie Holiday") naar de
     gewone naam. De juiste naam is de officiële schrijfwijze, mét accenten, hoofdletters en tekens zoals de artiest
     zelf ze schrijft (Hélène Ségara, Édith Piaf, Âme, a-ha, Beyoncé): haal nooit een accent weg — staan beide er, zet
     dan de versie zonder accent recht naar die mét. Zet nooit een Discogs-nummer als "(2)" of een sterretje in een
     naam; eruit halen mag wel ("Dominion (3)" wordt "Dominion"). Laat een gast ("feat. MC Ramon") nooit wegvallen.
   Gebruik artiest en titel precies zoals in de lijst. Liever geen correctie dan een gok.
7. Alles wat je zegt in het Nederlands.
''';
}

/// Het antwoord uitlezen. Alleen artiesten die in de vraag stonden ([bekend], op [vraagSleutel]); een artiest in twee
/// voorstellen blijft in het eerste; een lege of te kleine verzameling valt weg ([aantalVan]: nummers per artiest).
({List<AiVerzameling> verzamelingen, List<AiCorrectie> correcties}) leesVerzamelvoorstel(
  Object? json, {
  required Map<String, String> bekend,
  int Function(String artiest)? aantalVan,
  int vandaagJaar = 2100,
}) {
  final verz = <AiVerzameling>[];
  final corr = <AiCorrectie>[];
  if (json is! Map) return (verzamelingen: verz, correcties: corr);
  String? juist(Object? naam) => bekend[vraagSleutel('${naam ?? ''}')];
  final gezien = <String>{};
  for (final v in (json['verzamelingen'] is List ? json['verzamelingen'] as List : const [])) {
    if (v is! Map) continue;
    final naam = '${v['naam'] ?? ''}'.trim();
    if (naam.isEmpty) continue;
    final artiesten = <VoorstelArtiest>[];
    for (final a in (v['artiesten'] is List ? v['artiesten'] as List : const [])) {
      if (a is! Map) continue;
      final wie = juist(a['artiest']);
      if (wie == null || !gezien.add(vraagSleutel(wie))) continue;
      artiesten.add((
        artiest: wie,
        twijfel: a['twijfel'] == true,
        opmerking: '${a['opmerking'] ?? ''}'.trim(),
        nietDeze: [
          for (final t in (a['nietDeze'] is List ? a['nietDeze'] as List : const []))
            if ('$t'.trim().isNotEmpty) '$t'.trim()
        ],
      ));
    }
    if (artiesten.isEmpty) continue;
    if (aantalVan != null) {
      final n = artiesten.fold<int>(0, (s, a) => s + aantalVan(a.artiest));
      if (n < kVerzamelMinstens) continue;
    }
    verz.add((naam: naam, waarom: '${v['waarom'] ?? ''}'.trim(), artiesten: artiesten));
  }
  for (final c in (json['correcties'] is List ? json['correcties'] as List : const [])) {
    if (c is! Map || corr.length >= kCorrectiesHoogstens) continue;
    final wie = juist(c['artiest']);
    final veld = '${c['veld'] ?? ''}'.trim();
    final naar = '${c['naar'] ?? ''}'.trim();
    final titel = '${c['titel'] ?? ''}'.trim();
    if (wie == null || naar.isEmpty || !const {'genre', 'jaar', 'artiest'}.contains(veld)) continue;
    if (veld == 'jaar') {
      final j = int.tryParse(naar);
      if (j == null || j < 1900 || j > vandaagJaar || titel.isEmpty) continue;
    }
    if (veld == 'artiest') {
      final r = artiestCorrectie(wie, naar, bekend);
      if (r == null) continue;
      corr.add((artiest: r.artiest, titel: titel, veld: veld, naar: r.naar, waarom: '${c['waarom'] ?? ''}'.trim()));
      continue;
    }
    corr.add((artiest: wie, titel: titel, veld: veld, naar: naar, waarom: '${c['waarom'] ?? ''}'.trim()));
  }
  return (verzamelingen: verz, correcties: corr);
}

/// Een naamcorrectie van [wie] naar [naar] nakijken (Saber, 22-11-2026: de eerste ronde maakte van Hélène Ségara
/// "Segara", van a-ha "A-Ha", van DJ Stijn "DJ Stijn (2)", en liet bij Drivers Seed MC Ramon wegvallen). Null: niet
/// voorstellen. Haalt ze een accent weg terwijl de naam mét accent ook in de bibliotheek staat ([bekend]), dan
/// andersom: de versie zonder accent wordt die mét.
///
/// Niet voorstellen: alleen hoofdletters of de vorm van een streepje anders (welke de officiële is, weet de app niet);
/// een Discogs-nummer of sterretje erbij; een gast die verdwijnt; een accent weg dat nergens anders staat.
({String artiest, String naar})? artiestCorrectie(String wie, String naar, Map<String, String> bekend) {
  final a = kaleNaam(wie), b = kaleNaam(naar);
  if (a == b) return null;
  // "Various" of "Verschillende artiesten" is geen naam: daar hoort per nummer de echte artiest, niet een andere
  // verzamelnaam (de tweede ronde maakte van "Various" "Verschillende artiesten").
  if (isVerzamelnaam(wie) || isVerzamelnaam(naar)) return null;
  if (RegExp(r'\(\d+\)|\*').hasMatch(naar)) return null;
  final gast = RegExp(r'\b(?:feat\.?|ft\.?|featuring)\s+(.+)$', caseSensitive: false).firstMatch(wie)?.group(1);
  if (gast != null && !b.contains(kaleNaam(gast).replaceAll('*', '').trim())) return null;
  if (zonderAccenten(a) == zonderAccenten(b) && aantalAccenten(naar) < aantalAccenten(wie)) {
    final andersom = bekend[vraagSleutel(naar)];
    return andersom == null || andersom == wie ? null : (artiest: andersom, naar: wie);
  }
  return (artiest: wie, naar: naar);
}

/// Een naam om te vergelijken: klein, elk soort streepje als "-", rechte aanhalingstekens, één spatie.
String kaleNaam(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[‐-―−]'), '-')
    .replaceAll(RegExp('[‘’‚‛′]'), "'")
    .replaceAll(RegExp('[“”„″]'), '"')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

const String _metAccent = 'àáâãäåāăąçćčďèéêëēęěìíîïīñńňòóôõöøōőŕřśšşťùúûüūůűýÿžźżÀÁÂÃÄÅĀĂĄÇĆČĎÈÉÊËĒĘĚÌÍÎÏĪÑŃŇÒÓÔÕÖØŌŐŔŘŚŠŞŤÙÚÛÜŪŮŰÝŸŽŹŻ';
const String _zonderAccent = 'aaaaaaaaacccdeeeeeeeiiiiinnnoooooooorrssstuuuuuuuyyzzzAAAAAAAAACCCDEEEEEEEIIIIINNNOOOOOOOORRSSSTUUUUUUUYYZZZ';

/// [s] zonder accenten ("Ségara" → "Segara").
String zonderAccenten(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final i = _metAccent.indexOf(c);
    b.write(i < 0 ? c : _zonderAccent[i]);
  }
  return b.toString();
}

/// Hoeveel letters met een accent [s] heeft.
int aantalAccenten(String s) => s.runes.where((r) => _metAccent.contains(String.fromCharCode(r))).length;

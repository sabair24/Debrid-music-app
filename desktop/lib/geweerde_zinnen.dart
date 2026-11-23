/// Zinnen die Soulseek in zoekopdrachten weert, en hoe een zoekopdracht er toch komt.
///
/// Saber, 25-10-2026, bij After Hours: *"oei een groot probleem, soulseek vindt geen sources niet meer ?????"*.
/// Gemeten op de pc via de eigen API: "The Weeknd Alone Again", "The Weeknd Blinding Lights" en "The Weeknd After
/// Hours" gaven na 18–22 s **0** bestanden; "Weeknd Alone Again" 703, "Weeknd Blinding Lights" 1294, en "Daft Punk
/// Digital Love" 1002 in 4 s. De server stuurt na het inloggen een lijst met geweerde zinnen (ExcludedSearchPhrases,
/// bericht 160) — op verzoek van rechthebbenden — en een zoekopdracht met zo'n zin krijgt geen antwoord. De app las
/// dat bericht niet (sinds 3.9.631 wel). **Nagemeten met 3.9.631:** "the weeknd" staat níet op die lijst, en "The
/// Beatles Let It Be" gaf ook 0 tegen 5000 zonder "The" — het netwerk weert die namen op een andere manier. Vandaar
/// [kBekendeGeweerdeZinnen] en de tweede vraag zonder "The" in `SoulseekService.search`.
///
/// Een zin wordt niet zomaar weggelaten: dan zocht "The Weeknd Alone Again" op "Alone Again", en dat is Gilbert
/// O'Sullivan. Wat er van de zin overblijft zonder zijn eerste woorden, mag blijven als dat zelf niet geweerd is:
/// "the weeknd" wordt "weeknd".
///
/// **Zelf leren (23-11-2026).** Saber, bij Nicki Minaj: *"de app vindt niets van Nicki minaj ???? Hoe komt dit ? Blijft
/// maar draaien ook weer ???"*. Elke vraag met haar naam bleef stil, ook niet op lijst 160; "Minaj Starships" gaf 929
/// bestanden in 1,8 s. Vier stille vragen op rij lieten de app bovendien denken dat de server zweeg — tien minuten geen
/// achtergrondzoeken, ook niet de telling op de albumpagina (het draaiende rondje). Elke nieuwe naam vroeg tot dan een
/// nieuwe versie. Nu leert de sessie hem zelf ([geweerdeNaamProef], [geweerdBewezen]): blijft een vraag helemaal stil
/// terwijl de server verder antwoordt, dan één proef zonder het eerste woord; komen er dan bestanden terug met de hele
/// naam in hun pad, dan weert het netwerk die naam, en wordt hij onthouden ([GeleerdeZinnen], `geweerde_zinnen.json`).
library;

import 'dart:convert';
import 'dart:io';

/// Gemeten op 25-10-2026: deze namen met "The" ervoor krijgen geen antwoord, zonder wel. Ze staan NIET op de lijst die
/// de server stuurt (die noemde om 17:40 zes zinnen: bryan adams, from zero, housezzz, look outside your window, paper
/// kingdom, village people) — het netwerk weert ze op een andere manier. "The Police Roxanne" werkte wel. Wat hier niet
/// staat, vangt `SoulseekService.search` op met een tweede vraag zonder "The".
///
/// **"madeleine peyroux" (21-11-2026).** Een radio vanaf Nancy Wilson: alle vijf de vragen met haar naam bleven stil
/// ("Madeleine Peyroux Smile", kaal "Madeleine Peyroux", ook de jokervorm "*adeleine Peyroux …"), terwijl de vragen
/// ervoor en erna antwoord kregen. Niet op lijst 160. Eén proefvraag "Peyroux Smile": 477 bestanden in 5,7 s.
///
/// **"nicki minaj" (23-11-2026).** Starships en Pink Friday: Roman Reloaded op de gsm: alle vragen met haar naam stil
/// ("nicki minaj starships", kaal "Nicki Minaj", "Nicki Minaj Pink Friday"), de server gaf intussen andere vragen wel
/// antwoord. Niet op lijst 160. Eén proefvraag "Minaj Starships": 929 bestanden in 1,8 s.
const Set<String> kBekendeGeweerdeZinnen = {'the weeknd', 'the beatles', 'madeleine peyroux', 'nicki minaj'};

/// Zoveel bestanden met de hele naam in hun pad moet de proef zonder het eerste woord opleveren, voor de naam als geweerd
/// geldt ([geweerdBewezen]). Wie een naam weert, weert de vraag — niet de bestanden: "Nicki Minaj - Starships.flac"
/// staat gewoon bij de uploaders. Een obscure naam die stil bleef omdat niemand hem heeft, levert zonder zijn eerste
/// woord hooguit bestanden van iets anders op.
const int kGeweerdBewijs = 3;

/// De proef voor een vraag die helemaal stil bleef: welke naam het netwerk misschien weert, en de vraag zonder zijn eerste
/// woord. Null: geen proef — de naam is al bekend of al geprobeerd ([nietGeweerd]), de vraag begint niet met twee echte
/// woorden (een joker, één letter), of de server zwijgt of zweeg net nog ([zonderAntwoordOpRij]): dan zegt een stille
/// vraag niets over een naam.
({String naam, String proefvraag})? geweerdeNaamProef(String vraag,
    {required Set<String> geweerd,
    required Set<String> nietGeweerd,
    required bool serverZwijgt,
    required int zonderAntwoordOpRij}) {
  if (serverZwijgt || zonderAntwoordOpRij > 0) return null;
  final w = vraag.trim().split(RegExp(r'\s+'));
  if (w.length < 2) return null;
  bool woord(String s) => s.length >= 2 && !s.contains('*') && RegExp(r'\p{L}', unicode: true).hasMatch(s);
  if (!woord(w[0]) || !woord(w[1])) return null;
  final naam = '${w[0]} ${w[1]}'.toLowerCase();
  if (geweerd.contains(naam) || nietGeweerd.contains(naam)) return null;
  return (naam: naam, proefvraag: w.skip(1).join(' '));
}

String _woordenVan(String s) =>
    ' ${s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim()} ';

/// Staat [naam] als hele woorden in [pad]? "@@x\\Nicki_Minaj\\01 Starships.flac" bevat "nicki minaj".
bool bevatNaam(String pad, String naam) => _woordenVan(pad).contains(_woordenVan(naam));

/// Bewijst de proef dat het netwerk [naam] weert? Minstens [kGeweerdBewijs] bestanden met de hele naam in hun pad.
bool geweerdBewezen(Iterable<String> paden, String naam) => paden.where((p) => bevatNaam(p, naam)).length >= kGeweerdBewijs;

/// De namen die de app zelf leerde ([geweerdeNaamProef]), in `geweerde_zinnen.json` op de pc: na een herstart meteen
/// goed, zonder eerst weer stil te blijven.
class GeleerdeZinnen {
  GeleerdeZinnen(this._pad);
  final String _pad;
  final Map<String, String> _sinds = {};

  Future<Set<String>> laad() async {
    try {
      final f = File(_pad);
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        final z = j is Map ? j['zinnen'] : null;
        if (z is Map) {
          for (final e in z.entries) {
            final naam = '${e.key}'.toLowerCase().trim();
            if (naam.isNotEmpty) _sinds[naam] = '${e.value}';
          }
        }
      }
    } catch (_) {/* een kapot bestand: dan leert hij ze opnieuw — dat kost één stille vraag per naam */}
    return _sinds.keys.toSet();
  }

  Future<void> voegToe(String naam, DateTime op) async {
    final n = naam.toLowerCase().trim();
    if (n.isEmpty || _sinds.containsKey(n)) return;
    _sinds[n] = '${op.year}-${op.month.toString().padLeft(2, '0')}-${op.day.toString().padLeft(2, '0')}';
    try {
      final tmp = File('$_pad.tmp');
      await tmp.writeAsString(jsonEncode({'versie': 1, 'zinnen': _sinds}));
      await tmp.rename(_pad);
    } catch (_) {/* volgende keer opnieuw */}
  }
}

String _plat(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// [vraag] zonder de zinnen uit [geweerd] (klein geschreven): elke geweerde zin wordt het kortste staartstuk dat zelf
/// niet geweerd is ("the weeknd" → "weeknd"), of verdwijnt als er niets overblijft. Hoofdletters en de rest van de
/// vraag blijven zoals ze waren. Blijft er niets over, dan de oorspronkelijke vraag: liever een vraag zonder antwoord
/// dan een lege.
String zonderGeweerdeZinnen(String vraag, Iterable<String> geweerd) {
  final zinnen = {for (final z in geweerd) if (_plat(z).isNotEmpty) _plat(z)}.toList()
    // De langste eerst: "the weeknd" vóór een eventueel los "weeknd".
    ..sort((a, b) => b.length.compareTo(a.length));
  if (zinnen.isEmpty) return vraag;
  bool isGeweerd(String s) => zinnen.contains(_plat(s));
  var uit = vraag;
  for (final z in zinnen) {
    final woorden = z.split(' ');
    // Ook in de jokervorm: "*adeleine Peyroux" bleef net zo stil als "Madeleine Peyroux" (21-11-2026). De joker staat
    // alleen op het eerste woord ([jokerHelpt] in zoekladder.dart: het eerste teken van de vraag wordt "*").
    String woord(int i) {
      final w = RegExp.escape(woorden[i]);
      return i == 0 && woorden[i].length > 1 ? '(?:$w|\\*${RegExp.escape(woorden[i].substring(1))})' : w;
    }

    final patroon = RegExp(
        r'(?<![\p{L}\p{N}*])' + [for (var i = 0; i < woorden.length; i++) woord(i)].join(r'\s+') + r'(?![\p{L}\p{N}])',
        caseSensitive: false,
        unicode: true);
    uit = uit.replaceAllMapped(patroon, (m) {
      final echt = m.group(0)!.split(RegExp(r'\s+'));
      for (var k = 1; k < echt.length; k++) {
        final staart = echt.sublist(k).join(' ');
        if (!isGeweerd(staart)) return staart;
      }
      return '';
    });
  }
  uit = uit.replaceAll(RegExp(r'\s+'), ' ').trim();
  return uit.isEmpty ? vraag : uit;
}

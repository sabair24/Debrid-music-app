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
library;

/// Gemeten op 25-10-2026: deze namen met "The" ervoor krijgen geen antwoord, zonder wel. Ze staan NIET op de lijst die
/// de server stuurt (die noemde om 17:40 zes zinnen: bryan adams, from zero, housezzz, look outside your window, paper
/// kingdom, village people) — het netwerk weert ze op een andere manier. "The Police Roxanne" werkte wel. Wat hier niet
/// staat, vangt `SoulseekService.search` op met een tweede vraag zonder "The".
const Set<String> kBekendeGeweerdeZinnen = {'the weeknd', 'the beatles'};

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
    final patroon = RegExp(r'(?<![\p{L}\p{N}])' + woorden.map(RegExp.escape).join(r'\s+') + r'(?![\p{L}\p{N}])',
        caseSensitive: false, unicode: true);
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

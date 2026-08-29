/// Welke versie van een liedje de radio speelt, en hoeveel bewerkingen erbij mogen.
///
/// **Het probleem waar dit over gaat.** De lijst van een radio komt van Deezer: per zaadartiest de
/// toppers. Bij dance uit de jaren negentig zijn dat er zelden tien verschillende liedjes — het zijn
/// twee of drie liedjes in acht uitvoeringen. "Rhythm Is a Dancer", en daarnaast de Extended Mix, de
/// Club Mix, de 12" en een instrumentale. Wie die lijst ongefilterd afspeelt hoort een uur lang
/// varianten van hetzelfde, en dat is precies wat er gemeld werd: *"meer de originele en radio edits
/// dan remixen, het mag wel maar het is te veel nu."*
///
/// Twee regels, en verder niets:
///
/// 1. **Van één liedje één uitvoering**, en wel de gewoonste die er is. Staat de gewone versie
///    ertussen, dan verdwijnt de Club Mix; staat hij er niet, dan blijft de Club Mix staan. Deze
///    regel kost je dus nooit een liedje, alleen een dubbel.
/// 2. **Een rantsoen voor de rest.** Wat er na regel 1 nog aan bewerkingen over is — een remix van
///    iets waar geen gewone versie van bestaat — mag hoogstens twee op de tien zijn. "Het mag wel,
///    maar niet te veel." Deze regel kan er dus wél een laten vallen: bij een radio van driehonderd
///    is er ruimte voor zestig, en wie er tachtig aanbiedt houdt er zestig over.
///
/// Geen IO en geen toeval, want dit is een oordeel over smaak en dat hoort na te rekenen te zijn.
library;

/// Wat voor uitvoering een titel aankondigt.
///
/// De volgorde IS de rangorde: lager is liever. [origineel] is een titel die niets aankondigt — de
/// gewone plaatversie. [radio] is de versie die op de radio ging, en die is hier expres net zo
/// welkom: bij dance uit de jaren negentig ís de radio-edit vaak de versie die iedereen kent.
enum Uitvoering { origineel, radio, bewerking }

/// Alles wat de titel over de UITVOERING zegt: tussen haakjes, en achter een gedachtestreepje.
///
/// Deezer schrijft het allebei. "Mr. Vain (Radio Edit)" en "Mr. Vain - Radio Edit" zijn hetzelfde
/// nummer, en één van de twee vormen herkennen is hetzelfde als geen van beide herkennen.
String _staart(String titel) {
  final buf = StringBuffer();
  for (final m in RegExp(r'[\(\[]([^\)\]]*)[\)\]]').allMatches(titel)) {
    buf
      ..write(m.group(1) ?? '')
      ..write(' ');
  }
  final streep = titel.indexOf(' - ');
  if (streep > 0) buf.write(titel.substring(streep + 3));
  return buf.toString().toLowerCase();
}

/// Zegt de staart met zoveel woorden dat dit de gewone of de radioversie is?
///
/// Deze staat VÓÓR de bewerkingen in [uitvoeringVan], want "Radio Mix" draagt het woord "mix" en zou
/// anders als remix gelden — terwijl het juist de versie is die gevraagd werd.
const List<String> _gewoon = [
  'radio edit',
  'radio version',
  'radio mix',
  'radio cut',
  'single version',
  'single edit',
  'original version',
  'original mix',
  'album version',
  '7"',
  "7''",
  '7 inch',
];

/// En dit is er iets anders mee gedaan.
///
/// "mix" staat er als laatste en dus als grofste vangnet: alles wat "… Mix" heet en hierboven niet
/// als gewone versie herkend is, is een bewerking. Live, instrumentaal en karaoke horen niet in een
/// remixlijst thuis maar wel in dit vakje: het zijn evenmin de versie die je verwacht.
const List<String> _anders = [
  'remix',
  'extended',
  'club',
  'dub',
  'bootleg',
  'rework',
  'remake',
  'vip',
  'instrumental',
  'a cappella',
  'acapella',
  'karaoke',
  'live',
  'unplugged',
  'cover',
  '12"',
  "12''",
  '12 inch',
  'mix',
];

/// Wat voor uitvoering dit is, alleen op de titel af.
Uitvoering uitvoeringVan(String titel) {
  final s = _staart(titel);
  if (s.trim().isEmpty) return Uitvoering.origineel;
  for (final m in _gewoon) {
    if (s.contains(m)) return Uitvoering.radio;
  }
  // "(Radio)" op zichzelf, als heel woord. Niet als losse tekst, want dan telt "(Radiohead Remix)"
  // ook mee en dat is nu juist een remix.
  if (RegExp(r'\bradio\b').hasMatch(s)) return Uitvoering.radio;
  for (final m in _anders) {
    if (s.contains(m)) return Uitvoering.bewerking;
  }
  // Een kale "edit" of "short version" is een radioversie en geen bewerking — maar pas hier, ná de
  // bewerkingen, zodat "Remix Edit" niet als radio-edit doorgaat.
  if (s.contains('edit') || s.contains('short version')) return Uitvoering.radio;
  return Uitvoering.origineel;
}

/// De titel zonder wat er over de uitvoering in staat: waarop twee versies hetzelfde LIEDJE zijn.
String basisTitel(String titel) {
  var x = titel;
  final streep = x.indexOf(' - ');
  if (streep > 0) x = x.substring(0, streep);
  x = x.replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ');
  return _plat(x);
}

String _plat(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

/// Eén regel uit het aanbod: genoeg om te oordelen, niet meer.
typedef Aanbod = ({String artiest, String titel});

/// Hoeveel bewerkingen er per tien nummers hoogstens mogen staan.
///
/// Twee, en dat is een smaakoordeel dat ergens vandaan moet komen. Nul is te streng: van sommige
/// dansplaten bestáát alleen een clubversie, en die zou dan nooit meer langskomen. Vijf is wat er nu
/// gebeurt en dat was te veel.
const int kBewerkingPerTien = 2;

/// Welke regels uit [aanbod] de radio in mogen, in dezelfde volgorde.
///
/// Geeft INDEXEN terug en geen nieuwe lijst, zodat de aanroeper zijn eigen soort behoudt en er
/// niets van de gegevens verloren gaat onderweg.
List<int> kiesNummers(List<Aanbod> aanbod, {int bewerkingPerTien = kBewerkingPerTien}) {
  // 1. Per liedje de beste uitvoering. De eerste met de laagste rang wint, zodat de volgorde die
  //    erin ging — bij een radio een geschudde volgorde — bewaard blijft.
  final beste = <String, int>{};
  for (var i = 0; i < aanbod.length; i++) {
    final sleutel = '${_plat(aanbod[i].artiest)}|${basisTitel(aanbod[i].titel)}';
    final zit = beste[sleutel];
    if (zit == null ||
        uitvoeringVan(aanbod[i].titel).index < uitvoeringVan(aanbod[zit].titel).index) {
      beste[sleutel] = i;
    }
  }
  final houden = beste.values.toSet();

  // 2. En dan het rantsoen. De toets is `(bewerkingen + 1) * 10 <= (erin + 1) * perTien`: pas als er
  //    genoeg gewone nummers staan mag er weer een bewerking bij. Daardoor begint een radio nooit
  //    met een remix, ook al stond die vooraan.
  final uit = <int>[];
  var bewerkingen = 0;
  for (var i = 0; i < aanbod.length; i++) {
    if (!houden.contains(i)) continue;
    if (uitvoeringVan(aanbod[i].titel) == Uitvoering.bewerking) {
      if ((bewerkingen + 1) * 10 > (uit.length + 1) * bewerkingPerTien) continue;
      bewerkingen++;
    }
    uit.add(i);
  }
  return uit;
}

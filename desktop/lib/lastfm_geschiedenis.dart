/// Je Last.fm-geschiedenis naast je bibliotheek: wat je vroeger veel speelde en nog niet hebt.
///
/// Saber, 22-10-2026: *"ik wil op die manier ook nieuwe nummers leren kennen of bekende liedjes die ik nog niet heb"*,
/// en daarna zijn Last.fm-account. Gemeten die dag: 10.722 scrobbles (2017 tot november 2023) van 4074 nummers en 1937
/// artiesten; van zijn 100 meest gespeelde nummers stonden er 43 niet in zijn bibliotheek (Lauren Daigle — You Say,
/// Chris Isaak — Wicked Game, Toto — Africa, Kiesza — Hideaway). Van zijn top-50-artiesten had hij er 41.
library;

import 'lastfm.dart';
import 'models.dart' show Track;
import 'radiokeuze.dart' show Uitvoering, artiestSleutel, eigenSleutel, nooitOpRadio, uitvoeringVan;

/// Een nummer uit je geschiedenis dat je niet in je bibliotheek hebt.
typedef VroegerGespeeld = ({String artiest, String titel, int keer});

/// Wat je vaker dan [minstens] keer speelde en niet hebt, meest gespeeld eerst. Hetzelfde liedje telt één keer
/// ([eigenSleutel]: artiest en het liedje zonder wat er tussen haakjes staat), en wat nooit op de radio hoort
/// (karaoke, instrumentaal) valt weg.
List<VroegerGespeeld> nogNietVanJou(
  List<LastfmGespeeld> geschiedenis,
  Iterable<Track> bibliotheek, {
  int minstens = 2,
}) {
  final heb = {for (final t in bibliotheek) eigenSleutel(t.artist, t.title)};
  final gezien = <String>{};
  final uit = <VroegerGespeeld>[];
  for (final g in [...geschiedenis]..sort((a, b) => b.keer.compareTo(a.keer))) {
    if (g.keer < minstens || nooitOpRadio(g.titel)) continue;
    final k = eigenSleutel(g.artiest, g.titel);
    if (heb.contains(k) || !gezien.add(k)) continue;
    uit.add((artiest: g.artiest, titel: g.titel, keer: g.keer));
  }
  return uit;
}

/// De bekendste nummers van een artiest (Last.fm, meeste luisteraars eerst) die je nog niet hebt — voor de artiestpagina.
///
/// **Alleen als Last.fm de juiste artiest kent:** minstens één van zijn [toets] bekendste nummers moet al in je
/// bibliotheek staan ([vanArtiest]: wat je van deze artiest hebt). Last.fm gooit naamgenoten op één hoop — bij "Petra"
/// waren de toppers van de Amerikaanse christelijke rockband (Beyond Belief, Creed), terwijl Saber de Vlaamse Petra
/// heeft. Zonder bewijs dus geen rij: liever niets dan de nummers van iemand anders. Bewerkingen (remixen, "midnight
/// mix") horen er niet bij: dit is de rij van de bekende nummers zelf.
List<LastfmTopper> bekendeNummersDieJeMist(
  List<LastfmTopper> top,
  Iterable<Track> vanArtiest, {
  int max = 10,
  int toets = 20,
}) {
  final heb = {for (final t in vanArtiest) eigenSleutel(t.artist, t.title)};
  if (!top.take(toets).any((n) => heb.contains(eigenSleutel(n.artiest, n.titel)))) return const [];
  final gezien = <String>{};
  return [
    for (final n in top)
      if (!nooitOpRadio(n.titel) && uitvoeringVan(n.titel) != Uitvoering.bewerking)
        if (eigenSleutel(n.artiest, n.titel) case final k when !heb.contains(k) && gezien.add(k)) n,
  ].take(max).toList();
}

/// Nieuwe artiesten voor jou: de verwanten (Last.fm, artist.getSimilar) van je meest gespeelde artiesten, opgeteld
/// over die artiesten, zonder wie je al hebt ([jouwArtiesten], als [artiestSleutel]s). Wie bij meer van je artiesten
/// terugkomt, staat hoger; [via] zegt bij wie (voor de uitleg op het scherm).
List<({String naam, double score, List<String> via})> nieuweArtiestenVoorJou(
  Map<String, List<({String naam, double maat})>> verwantPerAnker, {
  required Set<String> jouwArtiesten,
  int max = 15,
}) {
  final ankers = {for (final a in verwantPerAnker.keys) artiestSleutel(a)};
  final score = <String, double>{};
  final naam = <String, String>{};
  final via = <String, List<String>>{};
  verwantPerAnker.forEach((anker, verwant) {
    for (final v in verwant) {
      final k = artiestSleutel(v.naam);
      if (k.isEmpty || jouwArtiesten.contains(k) || ankers.contains(k)) continue;
      score[k] = (score[k] ?? 0) + v.maat;
      naam.putIfAbsent(k, () => v.naam);
      (via[k] ??= []).add(anker);
    }
  });
  final volgorde = score.keys.toList()..sort((a, b) => score[b]!.compareTo(score[a]!));
  return [for (final k in volgorde.take(max)) (naam: naam[k]!, score: score[k]!, via: via[k]!)];
}

/// Uit de bekendste nummers onder een tag (tag.getTopTracks) wat een radio uit een zin erbij neemt: geen covers,
/// karaoke of bewerkingen, hoogstens [perArtiest] per artiest, hoogstens [max]. Gemeten op 22-10-2026: "eurodance" gaf
/// La Bouche, Corona, 2 Brothers on the 4th Floor, Mr. President; "nederpop" De Dijk, Doe Maar, BLØF, Frank Boeijen.
List<({String artiest, String titel})> genreNummersErbij(List<LastfmTopper> tag, {int max = 20, int perArtiest = 2}) {
  final telling = <String, int>{};
  final gezien = <String>{};
  final uit = <({String artiest, String titel})>[];
  for (final n in tag) {
    if (uit.length >= max) break;
    if (nooitOpRadio(n.titel) || uitvoeringVan(n.titel) == Uitvoering.bewerking) continue;
    final a = artiestSleutel(n.artiest);
    if ((telling[a] ?? 0) >= perArtiest || !gezien.add(eigenSleutel(n.artiest, n.titel))) continue;
    telling[a] = (telling[a] ?? 0) + 1;
    uit.add((artiest: n.artiest, titel: n.titel));
  }
  return uit;
}

/// 36681 → "36.681", zoals in het Nederlands — voor het aantal luisteraars op het scherm.
String metPunten(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

/// De hits van een album: welke nummers (hun plaats in [luisteraars], de Last.fm-luisteraars per nummer, null als
/// Last.fm het niet kent) een sterretje krijgen. Hoogstens [max], elk minstens [deel] van het bekendste en minstens
/// [minstens] luisteraars — anders krijgt een plaat van een kleine artiest drie willekeurige sterren.
Set<int> hitsVanAlbum(List<int?> luisteraars, {int max = 3, double deel = 0.3, int minstens = 1000}) {
  final bekend = [
    for (var i = 0; i < luisteraars.length; i++)
      if ((luisteraars[i] ?? 0) >= minstens) (i: i, n: luisteraars[i]!),
  ]..sort((a, b) => b.n.compareTo(a.n));
  if (bekend.isEmpty) return const {};
  final top = bekend.first.n;
  return {
    for (final x in bekend.take(max))
      if (x.n >= top * deel) x.i,
  };
}

/// Je meest gespeelde artiesten volgens Last.fm, voor het smaakprofiel van de radio: alleen namen, meest eerst, zonder
/// dubbels met [al] (wat de app zelf al als meest gespeeld kent).
List<String> geschiedenisArtiesten(
  List<({String naam, int keer})> top, {
  Iterable<String> al = const [],
  int max = 10,
}) {
  final gezien = {for (final a in al) artiestSleutel(a)};
  return [
    for (final a in [...top]..sort((x, y) => y.keer.compareTo(x.keer)))
      if (gezien.add(artiestSleutel(a.naam))) a.naam,
  ].take(max).toList();
}

/// Haalt je geschiedenis op: tot [bladen] bladzijden van 200 meest gespeelde nummers (de buffer van [bron] houdt ze een
/// dag), en je meest gespeelde artiesten. Null als Last.fm niet antwoordde of er geen gebruiker is.
Future<({List<LastfmGespeeld> nummers, List<({String naam, int keer})> artiesten})?> haalGeschiedenis(
  LastfmZoeker bron, {
  required String gebruiker,
  required String sleutel,
  int bladen = 5,
}) async {
  if (gebruiker.trim().isEmpty || sleutel.trim().isEmpty) return null;
  final nummers = <LastfmGespeeld>[];
  for (var b = 1; b <= bladen; b++) {
    final blad = await bron.gebruikerTop(gebruiker, sleutel: sleutel, blad: b);
    if (blad == null) {
      if (b == 1) return null;
      break;
    }
    nummers.addAll(blad);
    if (blad.length < 200) break;
  }
  final artiesten = await bron.gebruikerArtiesten(gebruiker, sleutel: sleutel) ?? const [];
  return (nummers: nummers, artiesten: artiesten);
}

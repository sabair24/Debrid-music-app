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

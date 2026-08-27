/// Zoekresultaten zeven op WAAR ze vandaan komen.
///
/// **Waarom dit er is.** De torrentlijst is één stapel waar vijf bronnen in uitkomen — RuTracker,
/// Knaben, BitSearch, PirateBay en je eigen indexers. Elke rij zegt wel van wie hij is, maar dertig
/// rijen door elkaar zijn niet te overzien als je weet dat je bij één bron moet zijn. Gevraagd op
/// 27-08-2026: *"ook wil ik bij men torrent zoeken resultaten kunnen filteren, enkel rutracker
/// bevoorbeeld of een ander."*
///
/// **Uit de resultaten en niet uit een vaste lijst.** Welke bronnen er zijn hangt af van wat er
/// aanstaat en wat er antwoordde: zonder Discogs-sleutel geen eigen indexers, en een bron die de
/// twaalf seconden niet haalde levert niets. Een vaste rij knoppen zou dus knoppen tonen die niets
/// doen — en precies verzwijgen wat er wél is. Wat hier uitkomt is een afspiegeling van de lijst die
/// eronder staat.
///
/// Zuiver: lijsten in, lijsten uit. Geen netwerk, geen scherm, dus na te meten zonder toestel.
library;

import 'torbox.dart';

/// Welke bronnen er in deze resultaten zitten, en hoeveel er van elk zijn.
///
/// Op aantal aflopend, en bij een gelijk aantal op naam. Die tweede regel is er niet voor de
/// schoonheid: zonder haar wisselt de volgorde van twee even grote bronnen per zoekopdracht, en
/// dan staat de knop waar je net op tikte de volgende keer ergens anders.
List<({String bron, int aantal})> bronnenInResultaten(Iterable<SearchResult> resultaten) {
  final tel = <String, int>{};
  for (final r in resultaten) {
    final naam = r.source.trim();
    if (naam.isEmpty) continue;
    tel[naam] = (tel[naam] ?? 0) + 1;
  }
  final uit = [for (final e in tel.entries) (bron: e.key, aantal: e.value)];
  uit.sort((a, b) => a.aantal != b.aantal ? b.aantal - a.aantal : a.bron.compareTo(b.bron));
  return uit;
}

/// Laat deze treffer door bij deze keuze. Null betekent: alles.
bool pastBijBron(SearchResult r, String? keuze) =>
    keuze == null || r.source.trim() == keuze;

/// De keuze zoals hij NA een nieuwe zoekopdracht nog geldig is.
///
/// Stond de lijst op "alleen RuTracker" en levert de volgende zoekopdracht geen enkele RuTracker-rij
/// op, dan zou je naar een lege lijst kijken met een knop die nergens meer bij hoort. Dan valt de
/// keuze terug op alles — er is niets te kiezen dat nog bestaat.
String? geldigeKeuze(String? keuze, List<({String bron, int aantal})> bronnen) =>
    keuze != null && bronnen.any((b) => b.bron == keuze) ? keuze : null;

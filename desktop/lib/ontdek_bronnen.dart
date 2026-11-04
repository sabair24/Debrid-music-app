/// De drie bronnen van Ontdek (Saber, 04-11-2026: Deezer, Last.fm én Claude; zie `ontdek.dart`).
///
/// Elke bron geeft [OntdekNummer]s met waar ze vandaan komen ([OntdekNummer.via]: de artiest van jou die ernaar
/// wees) en een korte reden voor op het scherm. Wat er niet is (geen sleutel, geen antwoord), geeft een lege lijst:
/// de andere twee dragen de lijst dan.
library;

import 'aanbevolen.dart' show Kandidaat;
import 'ai.dart';
import 'lastfm.dart';
import 'ontdek.dart';
import 'ontdekvraag.dart';
import 'radiolijst.dart' show AiNummer;
import 'recommend.dart';

/// "Lijkt op Sade en Seal": de (hoogstens twee) artiesten van jou die deze kandidaat als verwant noemen.
String lijktOp(List<String> via) => via.isEmpty ? '' : 'Lijkt op ${via.take(2).join(' en ')}';

/// Deezer: de verwanten van je zaden met hun toppers, en de tweede graad als "iets verder"
/// ([RecommendService.ontdekVerwanten]).
///
/// Twee dingen die de meting van 04-11-2026 liet zien (Sabers bibliotheek, 90 nummers):
/// - **Alleen nummers van de kandidaat zelf.** De toppers van Garou geven "Sous le vent" van Céline Dion (hij zingt
///   mee): dan stond er "Céline Dion — Sous le vent · Lijkt op Céline Dion".
/// - **Om de beurt per zaad.** Op score alleen wonnen de zwaarste zaden alles ("Lijkt op Rihanna en P!nk" overal),
///   en de Franse en dance-zaden kwamen pas op plek 66 tot 90. Nu levert elk zaad zijn beste kandidaat voor een zaad
///   zijn tweede geeft.
OntdekBronFn deezerOntdekBron(RecommendService rec, {Set<String> Function()? eigen}) =>
    (zaden) async => deezerNummers(
      await rec.ontdekVerwanten([
        for (final z in zaden) (naam: z.naam, gewicht: z.gewicht),
      ], eigen: eigen?.call() ?? const {}),
    );

/// Wat [RecommendService.ontdekVerwanten] gaf, als nummers voor Ontdek: zie [deezerOntdekBron].
List<OntdekNummer> deezerNummers(
  ({
    List<({Kandidaat kandidaat, List<RecTrack> toppers})> dichtbij,
    List<({String via, String naam, List<RecTrack> toppers})> verder,
  })
  r,
) {
  List<RecTrack> vanZelf(String naam, List<RecTrack> toppers) => [
    for (final t in toppers)
      if (ontdekArtiest(t.artist) == ontdekArtiest(naam)) t,
  ];
  final perZaad = <String, List<List<OntdekNummer>>>{};
  for (final p in r.dichtbij) {
    final via = p.kandidaat.via.isEmpty ? '' : p.kandidaat.via.first;
    final ns = [
      for (final t in vanZelf(p.kandidaat.naam, p.toppers))
        OntdekNummer(t, bron: Ontdekbron.deezer, waarom: lijktOp(p.kandidaat.via), via: via),
    ];
    if (ns.isNotEmpty) (perZaad[via] ??= []).add(ns);
  }
  return [
    ...omDeBeurt(perZaad.values.toList()).expand((ns) => ns),
    for (final p in r.verder)
      for (final t in vanZelf(p.naam, p.toppers))
        OntdekNummer(t, bron: Ontdekbron.deezer, waarom: 'Een stap verder dan ${p.via}', verder: true, via: p.via),
  ];
}

/// [rijen] om de beurt: de eerste van elke rij, dan de tweede, … — zo draagt niet één rij de hele lijst.
List<T> omDeBeurt<T>(List<List<T>> rijen) {
  final uit = <T>[];
  for (var i = 0; rijen.any((r) => i < r.length); i++) {
    for (final r in rijen) {
      if (i < r.length) uit.add(r[i]);
    }
  }
  return uit;
}

/// Hoeveel zaadnummers Last.fm krijgt, en hoeveel voorstellen per zaadnummer er overblijven.
const int kLastfmZaden = kOntdekZaden;
const int kLastfmPerZaad = 5;

/// Last.fm: per zaad zijn beste nummer ([OntdekArtiest.zaadNummers]) en wat luisteraars daarnaast draaien
/// (`track.getSimilar`), om de beurt over de zaden, en dan bij Deezer opgezocht voor hoes, album en lengte.
OntdekBronFn lastfmOntdekBron(LastfmZoeker lastfm, String Function() sleutel, RecommendService rec) => (zaden) async {
  final s = sleutel().trim();
  if (s.isEmpty) return const [];
  final paren = [
    for (final z in [...zaden]..sort((a, b) => b.gewicht.compareTo(a.gewicht)))
      if (z.zaadNummers.isNotEmpty) (zaad: z.naam, titel: z.zaadNummers.first),
  ].take(kLastfmZaden).toList();
  final antwoorden = await Future.wait([
    for (final p in paren) lastfm.vergelijkbaar(p.zaad, p.titel, sleutel: s, limit: 30).catchError((Object _) => null),
  ]);
  // Om de beurt: eerst de eerste van elk zaad, dan de tweede, … — zo draagt niet één zaad de hele bron.
  final rijen = [
    for (var i = 0; i < paren.length; i++)
      (zaad: paren[i].zaad, nummers: (antwoorden[i]?.nummers ?? const <LastfmNummer>[]).take(kLastfmPerZaad).toList()),
  ];
  final voorstellen = <({String zaad, LastfmNummer n})>[];
  final artiesten = <String>{};
  for (var ronde = 0; ronde < kLastfmPerZaad; ronde++) {
    for (final r in rijen) {
      if (ronde >= r.nummers.length) continue;
      final n = r.nummers[ronde];
      if (artiesten.add(ontdekArtiest(n.artiest))) voorstellen.add((zaad: r.zaad, n: n));
    }
  }
  if (voorstellen.isEmpty) return const [];
  final zaadVan = {for (final v in voorstellen) ontdekArtiest(v.n.artiest): v.zaad};
  final gevonden = await rec.lijstOpDeezer([
    for (final v in voorstellen) AiNummer(v.n.artiest, v.n.titel),
  ], van: 'last.fm');
  return [
    for (final t in gevonden)
      if (zaadVan[ontdekArtiest(t.artist)] case final zaad?)
        OntdekNummer(t, bron: Ontdekbron.lastfm, waarom: 'Voor wie $zaad draait', via: zaad),
  ];
};

/// Claude: één vraag met het smaakprofiel ([OntdekProfiel]), en elk voorstel bij Deezer nageslagen. [profiel] wordt
/// pas gebouwd als de vraag echt gaat (hoogstens twee keer per dag, zie [OntdekVoorJou.kClaudePerDag]).
OntdekBronFn claudeOntdekBron(AiService ai, OntdekProfiel Function() profiel, RecommendService rec) => (zaden) async {
  final voorstellen = await ai.maakOntdekLijst(profiel());
  if (voorstellen.isEmpty) return const [];
  final van = {for (final v in voorstellen) ontdekArtiest(v.artiest): v};
  final gevonden = await rec.lijstOpDeezer([
    for (final v in voorstellen) AiNummer(v.artiest, v.titel),
  ], van: 'Claude (ontdek)');
  return [
    for (final t in gevonden)
      if (van[ontdekArtiest(t.artist)] case final v?)
        OntdekNummer(t, bron: Ontdekbron.claude, waarom: v.reden, verder: v.verder),
  ];
};

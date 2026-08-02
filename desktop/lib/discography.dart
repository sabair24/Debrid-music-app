/// Eén discografie uit drie catalogi, samengevoegd tot één regel per plaat.
///
/// Deezer alleen was te mager: regionale uitgaves, EP's en compilaties ontbreken er stelselmatig.
/// MusicBrainz kent die wel maar heeft geen hoezen, en Discogs kent er zoveel dat je door de
/// persingen de plaat niet meer ziet. Elk van de drie is in zijn eentje het verkeerde antwoord.
///
/// Dit bestand is een BLAD: geen http, geen Flutter, geen bestanden. Alleen `catalog.dart` voor
/// [CatalogRef] en `organize.dart` voor [normKey]. Zo staat het samenvoegen los van het ophalen en is
/// het te testen zonder een netwerk na te bootsen — de vorm die de rest van dit project ook aanhoudt.
///
/// Apart bestand en niet in `catalog.dart`, om dezelfde reden waarom `editions.dart` apart staat:
/// `discogs.dart` importeert `catalog.dart` al, dus de afhankelijkheid kan maar één kant op.
library;

import 'catalog.dart';
import 'organize.dart' show normKey;

/// Welke catalogus deze plaat kent. Het merkje op de regel.
///
/// Bewust niet [EditionSource] uit editions.dart hergebruikt: die zegt "welke catalogus beschreef deze
/// PERSING" en kent er twee. Twee tegengestelde betekenissen onder één naam is precies hoe je later
/// niet meer weet wat een veld doet.
enum DiscoSource { deezer, musicbrainz, discogs }

/// Wat voor uitgave dit is.
///
/// Elke bron spelt dit anders — Deezer `album|single|ep|compile` als vrije tekst, MusicBrainz een
/// `primaryType` plus losse `secondaryTypes`, Discogs verstopt het in het formaat. Eén veld met drie
/// spellingen is de reden dat sorteren op type nu niet kan; vandaar één eigen begrip met drie
/// omzetters ernaartoe.
enum RecordKind { album, ep, single, compilation, other }

/// Deezers `record_type`.
RecordKind kindFromDeezer(String recordType) => switch (recordType.trim().toLowerCase()) {
      'album' => RecordKind.album,
      'ep' => RecordKind.ep,
      'single' => RecordKind.single,
      'compile' || 'compilation' => RecordKind.compilation,
      _ => RecordKind.other,
    };

/// MusicBrainz' `primaryType` plus zijn `secondaryTypes`.
///
/// De tweede lijst gaat vóór, en dat is geen detail: een verzamelaar staat daar als
/// `primaryType: Album` met `secondaryTypes: [Compilation]`. Alleen naar het eerste veld kijken zet
/// elke verzamelbox tussen de studioalbums.
RecordKind kindFromMb(String primaryType, List<String> secondaryTypes) {
  final tweede = secondaryTypes.map((s) => s.trim().toLowerCase()).toSet();
  if (tweede.contains('compilation')) return RecordKind.compilation;
  return switch (primaryType.trim().toLowerCase()) {
    'album' => RecordKind.album,
    'ep' => RecordKind.ep,
    'single' => RecordKind.single,
    _ => RecordKind.other,
  };
}

/// Discogs' `format`, dat een opsomming is: "LP, Album, Reissue" of "CD, Single".
RecordKind kindFromDiscogs(String format) {
  final woorden = format.toLowerCase().split(RegExp(r'[,;/]')).map((s) => s.trim()).toSet();
  if (woorden.contains('compilation')) return RecordKind.compilation;
  if (woorden.contains('ep')) return RecordKind.ep;
  if (woorden.contains('single')) return RecordKind.single;
  if (woorden.contains('album') || woorden.contains('lp')) return RecordKind.album;
  return RecordKind.other;
}

/// Woorden die alleen iets zeggen over de UITGAVE en niets over de plaat.
///
/// "30" en "30 (Deluxe Edition)" zijn één plaat; "30" en "30 ans de succès" zijn er twee. Het
/// verschil is dat de eerste staart uitsluitend uit deze woorden bestaat.
const _uitgaveWoorden = {
  'deluxe', 'edition', 'editie', 'expanded', 'remaster', 'remastered', 'reissue', 'anniversary',
  'special', 'limited', 'bonus', 'tracks', 'track', 'version', 'versie', 'the', 'of', 'disc',
  'cd', 'lp', 'vinyl', 'digital', 'explicit', 'clean', 'jubileum',
};

final _staart = RegExp(r'[\(\[\{][^\)\]\}]*[\)\]\}]\s*$');

/// Een jaartal of een rangtelwoord: "2021", "25th", "10e".
///
/// Als één woord, want [normKey] plakt cijfer en achtervoegsel aan elkaar. Ze los in de woordenlijst
/// zetten helpt dus niet — "25th" is nooit "25" plus "th".
final _getalWoord = RegExp(r'^\d+(st|nd|rd|th|e|de|ste)?$');

/// De sleutel waarop twee regels dezelfde plaat zijn.
///
/// Twee lagen. Eerst [normKey] (organize.dart), want dat is de sleutel waarmee de BIBLIOTHEEK
/// vergelijkt — accenten gevouwen, krul- en rechte apostrof gelijk, leestekens weg. Gebruik je hier
/// iets anders, dan is "heb ik dit al" een andere vraag dan "is dit dezelfde plaat", en dat is precies
/// de bestaande scheefheid: `catalog.dart` dedupliceert op `toLowerCase()` terwijl de bezitscontrole
/// `normKey` gebruikt, waardoor "Backstreet's Back" met een krulapostrof twee regels oplevert die
/// allebei als "heb ik" worden afgevinkt.
///
/// Daarna de uitgave-staarten eraf, herhaald, want Discogs levert er graag twee achter elkaar:
/// "30 (Deluxe Edition) [2021 Remaster]".
///
/// Bewust NIET slimmer dan dit. Geen fuzzy titelafstand, geen jaarnabijheid. Een valse samenvoeging
/// VERBERGT een plaat en dat merk je nooit; een dubbele regel zie je meteen. Van die twee fouten is de
/// zichtbare de goede.
String discoKey(String title) {
  var t = title.trim();
  for (var i = 0; i < 3; i++) {
    final m = _staart.firstMatch(t);
    if (m == null) break;
    final binnen = normKey(m.group(0)!).split(' ').where((w) => w.isNotEmpty);
    if (binnen.isEmpty) break;
    // Alleen weghalen als er niets in staat dat over de MUZIEK gaat. Een jaartal telt als
    // uitgave-informatie, "ans de succès" niet.
    if (!binnen.every((w) => _uitgaveWoorden.contains(w) || _getalWoord.hasMatch(w))) break;
    t = t.substring(0, m.start).trim();
  }
  return normKey(t);
}

/// Eén plaat, zoals hij op de artiestpagina staat.
class DiscoRelease {
  /// De titel zoals je hem leest. Vergelijken gebeurt op [key], nooit hierop.
  final String title;

  /// 'YYYY' of 'YYYY-MM-DD', als tekst — net als [CatalogAlbum.releaseDate]. Beide vormen sorteren
  /// als tekst correct ten opzichte van elkaar, en een echte datum invoeren zou de helft van de
  /// bronnen dwingen iets te verzinnen wat ze niet weten.
  final String? firstDate;

  final RecordKind kind;

  /// Null tot een bron er een levert. MusicBrainz heeft er nooit een op dit niveau.
  final String? cover;

  /// 0 = onbekend. Alleen Deezer weet dit; MusicBrainz en Discogs niet op dit niveau.
  final int trackCount;

  /// Welke catalogi deze plaat kennen — het merkje op de regel.
  final Set<DiscoSource> sources;

  /// Per bron de eigen verwijzing. Drie stuks, want ze zijn niet uit elkaar af te leiden.
  final Map<DiscoSource, CatalogRef> refs;

  const DiscoRelease({
    required this.title,
    required this.kind,
    this.firstDate,
    this.cover,
    this.trackCount = 0,
    this.sources = const {},
    this.refs = const {},
  });

  String get key => discoKey(title);

  int? get year {
    final d = firstDate;
    if (d == null || d.length < 4) return null;
    return int.tryParse(d.substring(0, 4));
  }

  /// Waarmee deze regel geopend wordt, in vaste voorkeursvolgorde.
  ///
  /// Deezer eerst, en dat is geen willekeur: alleen die tak haalt een tracklijst in één verzoek. De
  /// MusicBrainz-groep kost een browse plus een release-opzoeking op een baan van 1100 ms, en Discogs
  /// kost versions plus release op een baan van zestig per minuut. Wie het snelste antwoord heeft,
  /// mag de klik hebben.
  CatalogRef? get openRef =>
      refs[DiscoSource.deezer] ?? refs[DiscoSource.musicbrainz] ?? refs[DiscoSource.discogs];

  /// Terug naar de vorm die de albumpagina begrijpt. Die verandert niet mee.
  CatalogAlbum toCatalogAlbum() {
    final r = openRef;
    return CatalogAlbum(
      r != null && r.source == CatalogSource.deezer ? r.intId : 0,
      title,
      cover,
      firstDate,
      trackCount,
      switch (kind) {
        RecordKind.album => 'album',
        RecordKind.ep => 'ep',
        RecordKind.single => 'single',
        RecordKind.compilation => 'compile',
        RecordKind.other => 'album',
      },
      origin: r,
    );
  }

  /// Twee regels over dezelfde plaat tot één.
  ///
  /// Per veld wint de RIJKSTE waarde, niet de laatste: een hoes die er is verslaat null, een bekende
  /// tracktelling verslaat nul, en de VROEGSTE datum wint — Deezer levert bij een heruitgave de
  /// heruitgavedatum, en dan hoort de plaat nog steeds op zijn eigen jaar te staan.
  ///
  /// Daardoor is samenvoegen commutatief: het maakt niet uit in welke volgorde de bronnen binnenkomen.
  /// Dat is geen nettigheid maar de hele reden dat de lijst progressief mag aanvullen zonder onder je
  /// handen te veranderen.
  DiscoRelease mergedWith(DiscoRelease other) {
    String? vroegste(String? a, String? b) {
      if (a == null || a.isEmpty) return b;
      if (b == null || b.isEmpty) return a;
      return a.compareTo(b) <= 0 ? a : b;
    }

    return DiscoRelease(
      // De langste titel houdt de meeste informatie vast ("30" tegen "30 (Deluxe Edition)"), en bij
      // gelijke lengte beslist de tekst zelf zodat het antwoord niet van de volgorde afhangt.
      title: title.length == other.title.length
          ? (title.compareTo(other.title) <= 0 ? title : other.title)
          : (title.length > other.title.length ? title : other.title),
      // Een echt type verslaat `other`; weten twee bronnen het allebei, dan wint de laagste rang —
      // album boven overig, zodat één bron die "overig" zegt een album niet degradeert.
      kind: kind == other.kind
          ? kind
          : (kind == RecordKind.other
              ? other.kind
              : (other.kind == RecordKind.other ? kind : _minKind(kind, other.kind))),
      firstDate: vroegste(firstDate, other.firstDate),
      cover: (cover != null && cover!.isNotEmpty) ? cover : other.cover,
      trackCount: trackCount > 0 ? trackCount : other.trackCount,
      sources: {...sources, ...other.sources},
      refs: {...other.refs, ...refs},
    );
  }
}

/// De volgorde waarin een discografie gelezen wordt.
int kindRank(RecordKind k) => switch (k) {
      RecordKind.album => 0,
      RecordKind.ep => 1,
      RecordKind.single => 2,
      RecordKind.compilation => 3,
      RecordKind.other => 4,
    };

RecordKind _minKind(RecordKind a, RecordKind b) => kindRank(a) <= kindRank(b) ? a : b;

/// Alle regels van alle bronnen tot één lijst, één regel per plaat.
///
/// Neemt de LIJSTEN, niet een lopende toestand. De artiestpagina houdt de drie bronnen apart en roept
/// dit aan bij het tekenen; dan geeft elke hertekening hetzelfde antwoord, ongeacht wie het eerst
/// binnenkwam. Dat is wat progressief aanvullen veilig maakt — en meteen wat het testbaar maakt.
List<DiscoRelease> mergeDiscography(List<List<DiscoRelease>> bronnen) {
  final samen = <String, DiscoRelease>{};
  for (final lijst in bronnen) {
    for (final r in lijst) {
      final k = r.key;
      if (k.isEmpty) continue;
      final bestaand = samen[k];
      samen[k] = bestaand == null ? r : bestaand.mergedWith(r);
    }
  }
  return samen.values.toList();
}

/// Waarop de gebruiker kan sorteren.
enum DiscoSort { datum, bezit, type }

extension DiscoSortX on DiscoSort {
  String get label => switch (this) {
        DiscoSort.datum => 'Release (nieuw→oud)',
        DiscoSort.bezit => 'Wat ik heb',
        DiscoSort.type => 'Album, EP, single',
      };
}

/// Gesorteerd, met een TOTALE orde.
///
/// Elke vergelijking eindigt op de sleutel, zodat twee regels met dezelfde datum nooit tussen twee
/// hertekeningen van plek wisselen. Zonder die laatste stap springt de lijst zichtbaar zodra er een
/// bron bij komt.
///
/// [bezit] bevat de [discoKey]s van wat er in de bibliotheek staat. Bewust een argument en geen veld
/// op [DiscoRelease]: bezit is iets van de bibliotheek, niet van de plaat, en zo blijft samenvoegen
/// puur.
List<DiscoRelease> sortDiscography(List<DiscoRelease> in_, DiscoSort op, Set<String> bezit) {
  // Ongedateerd hoort ACHTERAAN, bij beide richtingen. Een kale tekstvergelijking op '' zet ze bij
  // oplopend juist vooraan — dezelfde val waarvoor `_sortAlbums` elders `?? 9999` gebruikt.
  int opDatum(DiscoRelease a, DiscoRelease b) {
    final da = a.firstDate ?? '', db = b.firstDate ?? '';
    if (da.isEmpty && db.isEmpty) return 0;
    if (da.isEmpty) return 1;
    if (db.isEmpty) return -1;
    return db.compareTo(da); // nieuwste eerst
  }

  final uit = [...in_];
  uit.sort((a, b) {
    switch (op) {
      case DiscoSort.datum:
        final d = opDatum(a, b);
        if (d != 0) return d;
      case DiscoSort.bezit:
        final ha = bezit.contains(a.key), hb = bezit.contains(b.key);
        if (ha != hb) return ha ? -1 : 1;
        final d = opDatum(a, b);
        if (d != 0) return d;
      case DiscoSort.type:
        final t = kindRank(a.kind).compareTo(kindRank(b.kind));
        if (t != 0) return t;
        final d = opDatum(a, b);
        if (d != 0) return d;
    }
    return a.key.compareTo(b.key);
  });
  return uit;
}

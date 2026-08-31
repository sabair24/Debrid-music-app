/// One pressing offered in the picker, whichever catalogue found it.
///
/// This lives in its own file rather than in discogs.dart or musicbrainz.dart because both have to
/// be able to produce one, and discogs.dart already constructs a MusicBrainzService — so the
/// dependency can only run one way without a cycle.
///
/// Knowing a pressing HAS a back cover, a disc scan and a tracklist BEFORE choosing it is the
/// point: five rows reading "30 — Adele" are unchoosable, and picking blind means finding out
/// afterwards that the disc animation has nothing to spin.
library;

enum EditionSource { musicbrainz, discogs }

/// The four things that name a pressing on the album page.
typedef Pressing = ({String format, String? catno, String? country, int? year});

/// "cd · 88725453152 · FR" — the line that says WHICH copy of the record is on screen.
///
/// [pinned] is the pressing the user chose; [guessed] is whatever the app matched for itself. When
/// there is a pin it wins every field, and that is not a preference — it is the only way the line
/// can be true. Choose the French CD in the gallery and the page kept reading
/// "Uitgave: cd · 88725453152 · Canada", because the panel only ever asked Discogs, which has never
/// heard of a MusicBrainz pin. The pin was on disk and correct; the one sentence describing your
/// copy of the record contradicted the choice you had just made.
///
/// [recordYear] is the album's own year. The pressing's year is only worth printing when it differs
/// — otherwise the line just repeats the one above it.
List<String> pressingFacts({
  Pressing? pinned,
  Pressing? guessed,
  int? recordYear,
  String Function(String)? formatLabel,
}) {
  final p = pinned ?? guessed;
  if (p == null) return const [];
  final label = formatLabel ?? (f) => f;
  final catno = (p.catno ?? '').trim();
  final country = (p.country ?? '').trim();
  return <String>[
    if (p.format.trim().isNotEmpty) label(p.format.trim()),
    if (p.year != null && p.year != recordYear) '${p.year}',
    // Discogs writes "none" where a release carries no catalogue number and MusicBrainz "[none]";
    // printing either says less than leaving the field out. Beide vormen via [_geenNummer].
    if (_geenNummer(catno).isNotEmpty) catno,
    if (country.isNotEmpty) country,
  ];
}

/// Hoeveel een rij te vertellen heeft. Er mag nooit voor minder geruild worden.
///
/// **Dit getal is de reparatie van twee fouten die er precies hetzelfde uitzagen.** De kiezer krijgt
/// dezelfde uitgave meer dan eens aangeboden. MusicBrainz levert zijn rijen eerst kaal en daarna
/// nog eens per persing zodra de scans binnen zijn; het nummerveld levert een rij die per definitie
/// nog geen scans heeft. Twee keer dezelfde sleutel dus — en in het ene geval is de nieuwe rij
/// beter, in het andere juist slechter.
///
/// Zonder dit onderscheid ging het altijd mis. De rij domweg overnemen wiste de scans die net waren
/// opgehaald; de rij domweg overslaan liet elke MusicBrainz-uitgave voor eeuwig op "scans ophalen…"
/// staan. Allebei een molentje dat nooit stopt.
///
/// Vier punten voor "er is naar gekeken", want dat is de vraag die de rij zelf stelt; de rest telt
/// wat er gevonden is. Zo verliest een rij die is opgezocht en niets had het nooit van een rij waar
/// nog niemand naar keek.
int rijkdom(ReleaseChoice c) =>
    (c.detailed ? 4 : 0) +
    (c.front != null ? 1 : 0) +
    (c.back != null ? 1 : 0) +
    (c.disc != null ? 1 : 0) +
    (c.tracklist.isNotEmpty ? 1 : 0);

/// Het catalogusnummer, of leeg als de uitgave er geen heeft.
///
/// **Het woord "geen" is geen nummer, en beide catalogussen schrijven het anders.** Discogs zet er
/// `none` neer, MusicBrainz `[none]`. Behandel je dat als een nummer, dan krijgen álle promo's,
/// testpersingen en witlabels uit hetzelfde land dezelfde sleutel — en die zijn dan opeens één rij
/// in plaats van tien. Precies het soort uitgave waarvoor iemand de kiezer opent.
///
/// Eén functie voor beide plekken die dit moesten weten: het ontdubbelen en het tonen. Dat de
/// tonende kant het wél wist en de ontdubbelende niet, is hoe rijen konden verdwijnen zonder dat er
/// iets van te zien was.
String _geenNummer(String? catno) {
  final t = (catno ?? '').trim().toLowerCase();
  // Haken eromheen weg, dan blijft van "[none]" hetzelfde woord over als van "none".
  final kaal = t.replaceAll(RegExp(r'^[\[(]|[\])]$'), '').trim();
  return kaal == 'none' || kaal == 'geen' ? '' : t;
}

class ChoiceImage {
  final String uri, thumb;

  /// Waar: [uri] is in werkelijkheid het MINIATUUR, want de volle scan is nog niet opgevraagd.
  ///
  /// De zoeklijst van Discogs geeft per rij alleen een `uri150` van 150×150. Die werd hier als
  /// `ChoiceImage(thumb, thumb)` neergezet — dus met het miniatuur óók in het `uri`-vak, het vak
  /// waar de rest van de app "de echte scan" leest. Tikte je zo'n rij aan voordat de detail-lookup
  /// binnen was, dan werd een plaatje van 150 pixels je `correctedCover`: de hoogste prioriteit die
  /// er is, weggeschreven naar schijf, en bij elke start weer teruggeladen. Een hoes van 150 pixels
  /// op een scherm dat er 1200 vraagt.
  ///
  /// Met deze vlag kan het opslaan eerst de volle scan ophalen — zie `_save` in de uitgavegalerij.
  final bool alleenMiniatuur;

  const ChoiceImage(this.uri, this.thumb, {this.alleenMiniatuur = false});
}

/// One line of a pressing's tracklist, as the pressing itself states it.
class ChoiceTrack {
  /// Kept as TEXT. This is the authority the library's own tags are wrong about, and a pressing
  /// does not always number in integers: a vinyl side is "A3" and a second disc is "1-04".
  final String position;
  final String title;
  final int? seconds;

  /// 1-based. A double album numbers from 1 on each disc, so the position alone is ambiguous.
  final int disc;

  /// Wie de UITGAVE als artiest van dit nummer opgeeft — "Beyoncé feat. JAY-Z". Leeg als de bron het
  /// niet zegt.
  ///
  /// **Waarom dit erbij moest.** MusicBrainz zet een gastartiest in dit veld en niet in de titel:
  /// de rij heet "Crazy in Love" en de credit staat ernaast. Een rip schrijft hem juist wél in de
  /// titel. Op de titel alleen is dat bestand dus niet te herkennen als datzelfde nummer — en het
  /// belandde onder "Niet op deze uitgave" terwijl het een van de bekendste nummers van de plaat is.
  ///
  /// En het is precies het veld dat dat geval scheidt van het geval dat er NIET op lijkt: heeft de
  /// uitgave "Easy on Me" met alleen Adele erbij, en heet jouw bestand "Easy On Me (With Chris
  /// Stapleton)", dan heb je een andere opname. Zonder dit veld zijn die twee van buiten niet uit
  /// elkaar te houden; mét is het een feit in plaats van een gok. Zie `matchAlbumTracks`.
  final String artist;

  const ChoiceTrack(this.position, this.title, this.seconds,
      {this.disc = 1, this.artist = ''});
}

class ReleaseChoice {
  final EditionSource source;

  /// The Discogs release id, or 0 for a MusicBrainz pressing.
  final int releaseId;

  /// The MusicBrainz release id, or null for a Discogs pressing.
  final String? mbid;

  final String format;
  final String? label, catno, country, barcode;
  final int? year;
  final ChoiceImage? front, back, disc;

  /// What this pressing says its tracks are. Empty when it has not been fetched yet — the picker
  /// only loads tracklists for the first few pressings, since each one costs a request.
  final List<ChoiceTrack> tracklist;

  /// Whether this pressing's scans have actually been looked up.
  ///
  /// A whole master's pressings can be listed off one request, but knowing whether each has a back
  /// or a disc costs a lookup apiece — so they arrive filled in a few at a time. Until then a row
  /// must not claim it HAS no back: it only means nobody has asked yet, and saying otherwise is the
  /// same lie that had this album reporting no CD scans at all.
  final bool detailed;

  const ReleaseChoice({
    required this.source,
    this.releaseId = 0,
    this.mbid,
    this.format = '',
    this.label,
    this.catno,
    this.country,
    this.barcode,
    this.year,
    this.front,
    this.back,
    this.disc,
    this.tracklist = const [],
    this.detailed = true,
  });

  /// The same pressing with its scans filled in.
  /// [tracks] because the lookup that finds the scans returns the tracklist in the same answer.
  ///
  /// It used to be dropped on the floor: a Discogs pressing therefore never had one, and "take this
  /// pressing's numbering" said "Deze uitgave geeft geen nummering" about a release whose tracks
  /// were sitting right there on the screen. Passing null keeps whatever the row already had, so a
  /// caller that only knows about art cannot erase a tracklist by accident.
  ReleaseChoice withArt({
    ChoiceImage? front,
    ChoiceImage? back,
    ChoiceImage? disc,
    List<ChoiceTrack>? tracks,
  }) =>
      ReleaseChoice(
        source: source,
        releaseId: releaseId,
        mbid: mbid,
        format: format,
        label: label,
        catno: catno,
        country: country,
        barcode: barcode,
        year: year,
        front: front ?? this.front,
        back: back,
        disc: disc,
        tracklist: tracks ?? tracklist,
        detailed: true,
      );

  bool get hasBack => back != null;
  bool get hasDisc => disc != null;
  bool get hasTracklist => tracklist.isNotEmpty;
  bool get isMb => source == EditionSource.musicbrainz;

  /// Identity across both catalogues, for marking the pinned row and for deduping.
  String get key => isMb ? 'mb:$mbid' : 'dg:$releaseId';

  /// "CD · Europe · 19439937972 · 2021"
  String get line => [
        if (format.isNotEmpty) format,
        if ((country ?? '').isNotEmpty) country!,
        // Via dezelfde functie als het ontdubbelen. Hier stond alleen de Discogs-schrijfwijze, dus
        // een MusicBrainz-uitgave zette "[none]" op de regel alsof het een nummer was.
        if (_geenNummer(catno).isNotEmpty) catno!.trim(),
        if (year != null && year! > 0) '$year',
      ].join(' · ');

  /// Two entries for the SAME physical pressing, found by two catalogues.
  ///
  /// A barcode is the one identifier both sides mean identically, so it wins outright when both
  /// carry one. Otherwise fall back to what is left — format, country and catalogue number
  /// together are specific enough that a false match is rarer than the duplicate row it prevents.
  String get dedupeKey {
    final b = (barcode ?? '').replaceAll(RegExp(r'\D'), '');
    if (b.length >= 8) return 'bc:$b';
    final ruw = _geenNummer(catno);
    // "none" is geen catalogusnummer maar het WOORD dat Discogs schrijft als er geen is. Het als
    // nummer behandelen maakte van elke promo, elke testpersing en elk witlabel uit hetzelfde land
    // één enkele rij — en dat is nu juist het soort uitgave waarvoor iemand deze kiezer opent. Ze
    // hebben geen nummer; dan valt er ook niets aan te ontdubbelen, en vallen ze terug op [key],
    // waar ze allemaal apart blijven staan.
    //
    // Dezelfde regel staat hierboven in [line] om het niet te TONEN. Dat het daar wel stond en hier
    // niet, is hoe rijen konden verdwijnen zonder dat er iets van te zien was.
    final c = ruw.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (c.isNotEmpty) return 'cn:${(country ?? '').toLowerCase()}|$c';
    // Nothing identifying at all — keep it, rather than collapsing every undocumented stub into one.
    return key;
  }
}

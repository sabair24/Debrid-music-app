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

class ChoiceImage {
  final String uri, thumb;
  const ChoiceImage(this.uri, this.thumb);
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
  const ChoiceTrack(this.position, this.title, this.seconds, {this.disc = 1});
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
        if ((catno ?? '').isNotEmpty && catno!.toLowerCase() != 'none') catno!,
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
    final c = (catno ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (c.isNotEmpty) return 'cn:${(country ?? '').toLowerCase()}|$c';
    // Nothing identifying at all — keep it, rather than collapsing every undocumented stub into one.
    return key;
  }
}

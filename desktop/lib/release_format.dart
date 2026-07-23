/// Which pressing of a record to describe it with, in one place.
///
/// Discogs and MusicBrainz spell formats differently — Discogs says "Vinyl" and "File",
/// MusicBrainz says `12" Vinyl` and "Digital Media" — but the preference behind them is the same
/// preference, and it was arrived at the hard way. Keeping it in one file is what stops the two
/// sources from quietly ranking the same record differently depending on which one answered.
library;

/// CD first, digital LAST.
///
/// Digital led at the start and it was the wrong call twice over. It cost the edition line —
/// digital entries almost never carry a catalogue number or a country, so *Bad* read
/// "digitaal · 2012" instead of "cd · EPC 450290 2 · Switzerland". And it is where the mismatches
/// came from: a digital stub carries so little that there is nothing to check a match against. A
/// pressed disc is a documented physical object, which is what makes it both richer to read and
/// safer to identify.
///
/// Digital stays at the back rather than being dropped: a record that only ever existed as a
/// download would otherwise have no edition at all.
const releaseFormatOrder = ['CD', 'CDr', 'Vinyl', 'Cassette', 'File'];

int releaseFormatRank(String major) {
  final i = releaseFormatOrder.indexOf(major);
  return i < 0 ? releaseFormatOrder.length : i;
}

/// Which of [releaseFormatOrder] a raw format string belongs to.
///
/// MusicBrainz names the physical thing, not the family: `12" Vinyl`, `Enhanced CD`, `Hybrid SACD`,
/// `Digital Media`, `CD-R`. Ranked literally, every one of those would fall off the end of the list
/// and tie with each other — which is how a record ends up described by whichever pressing happened
/// to come back first.
String majorFormat(String raw) {
  final s = raw.toLowerCase();
  if (s.isEmpty) return '';
  // Order matters: "CD-R" contains "cd", and a CD-R is not a CD.
  if (s.contains('cd-r') || s.contains('cdr')) return 'CDr';
  if (s.contains('vinyl') || s.contains('lp') || s.contains('shellac') || s.contains('flexi')) {
    return 'Vinyl';
  }
  if (s.contains('cassette') || s.contains('tape') || s.contains('8-track')) return 'Cassette';
  if (s.contains('digital') || s.contains('file') || s.contains('download') || s.contains('stream')) {
    return 'File';
  }
  // SACD, DualDisc, HDCD, Blu-spec and the rest of the shiny-disc family all read as CD: they hold
  // the same programme and the same artwork, which is all this ranking is deciding between.
  if (s.contains('cd') || s.contains('sacd') || s.contains('dualdisc') || s.contains('minidisc')) {
    return 'CD';
  }
  return '';
}

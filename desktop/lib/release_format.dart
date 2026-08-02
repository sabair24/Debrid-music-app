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

/// Houdt een uitgave met [got] nummers de plaat die [want] nummers lang is?
///
/// Beide richtingen tellen, en er stond er lang maar één. Te weinig betekent een single of een
/// sampler onder de master van het album. Te veel betekent een box of een twee-in-een: zoeken naar
/// *Discovery* landde op een dubbel-cd van dertig nummers die ook Homework bleek te zijn, en *Bad*
/// op een verjaardagsuitgave van tweeëndertig. Bonusnummers zijn normaal, een tweede album niet.
///
/// [want] is het aantal van de PLAAT — de tracklijst van de master, of die van de uitgave die de
/// pagina toont. Nadrukkelijk niet wat de bibliotheek ervan heeft: vier nummers van Demon Days zijn
/// nog steeds Demon Days, en met dat viertal als maatstaf valt elke echte persing van vijftien af.
/// Wie alleen een deelverzameling kent, mag dus alleen op "te weinig" toetsen.
///
/// Staat hier en niet in één van de twee diensten om dezelfde reden als [releaseFormatRank]:
/// Discogs en MusicBrainz stelden allebei deze vraag, allebei met hun eigen kopie van de formule, en
/// twee kopieën van een regel die zo duur betaald is gaan het vroeg of laat oneens worden.
bool fitsTrackCount(int got, int want) => got >= want - 2 && got <= want * 1.5 + 3;

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

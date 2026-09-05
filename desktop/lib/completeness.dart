import 'editions.dart';
import 'fingerprint.dart';
import 'models.dart';
import 'organize.dart';
import 'toewijzing.dart';

/// One line of a record as the album page shows it: what the release says belongs there, and the
/// file — if the file is here at all.
class AlbumSlot {
  /// Position in the official tracklist, or -1 for a file the release doesn't name.
  final int index;

  /// The official entry. Null only for a file the release doesn't name.
  final ChoiceTrack? official;

  /// The copy on disk. Null when this track is missing.
  final Track? track;

  /// Does the release this slot belongs to span more than one disc? A double album numbers from 1
  /// on each disc, so a bare position is ambiguous — and printing it raw put a second "1" after
  /// track 13.
  final bool multiDisc;

  const AlbumSlot({required this.index, this.official, this.track, this.multiDisc = false});

  bool get missing => track == null;

  int get disc => official?.disc ?? 1;

  /// The number to WRITE into the file's tag. Always an integer, and unique within the record:
  /// across discs it counts straight through, because a tag cannot hold "2-1" and two tracks
  /// sharing a number is what tears an album into editions.
  int get number {
    if (multiDisc && index >= 0) return index + 1;
    final p = int.tryParse((official?.position ?? '').trim());
    if (p != null && p > 0) return p;
    if (track != null && track!.trackNo > 0) return track!.trackNo;
    return index + 1;
  }

  /// The number to SHOW. "4" on a single disc, "2-1" on a double — what the sleeve says.
  ///
  /// Blank for a file the pressing doesn't name. It has no place in this run, and borrowing the
  /// number from its own tag put a second "3" underneath track 13 — which reads as the app being
  /// confused rather than as the file simply not being on this record.
  String get label {
    if (index < 0) return '';
    if (!multiDisc) return '$number';
    final pos = (official?.position ?? '').trim();
    return '$disc-${pos.isEmpty ? '${index + 1}' : pos}';
  }

  String get title => official?.title ?? track?.title ?? '';

  /// Staat hier een kopie die duidelijk een ANDERE lengte heeft dan de uitgave opgeeft?
  ///
  /// Bijna altijd een andere snit van hetzelfde nummer: de single-edit naast de albumversie. Dat mag
  /// deze plaats vullen — je hébt dat nummer — maar het hoort niet weggemoffeld te worden, want het
  /// is precies de reden om alsnog de albumversie te halen als je die wilt.
  bool get andereLengte {
    final o = official?.seconds ?? 0;
    final f = track?.duration?.inSeconds ?? 0;
    if (o <= 0 || f <= 0) return false;
    return (o - f).abs() > _slack;
  }

  int? get seconds => official?.seconds ?? track?.duration?.inSeconds;
}

/// A record laid next to what's on disk: every official track, present or not.
class AlbumCompleteness {
  final List<AlbumSlot> slots;

  /// Where the tracklist came from, for the line under the album ('MusicBrainz' / 'Discogs').
  final String source;

  const AlbumCompleteness(this.slots, {this.source = ''});

  /// Counted over the ROWS the page shows, not over the pressing — so a bonus file the release
  /// doesn't list counts towards both, and "3 van 17" always adds up to the list you're reading.
  int get have => slots.where((s) => s.track != null).length;
  int get total => slots.length;
  List<AlbumSlot> get missing => [for (final s in slots) if (s.missing) s];
  bool get complete => missing.isEmpty;

  /// How many of your tracks this pressing NAMES.
  ///
  /// Deliberately not [have]: that counts the rows on the page, and every file you own is always a
  /// row — matched, or appended at the end as one the pressing doesn't name. Comparing pressings on
  /// [have] therefore scores them all identically.
  int get matched => slots.where((s) => s.index >= 0 && s.track != null).length;

  /// Does this pressing name everything on disk? The question the pressing is chosen on.
  bool get namesEverything => slots.every((s) => s.index >= 0 || s.track == null);
}

/// Is this track a marked variant — a radio edit, a live take, a remix?
///
/// Read from the title and the FILENAME only, never the folders: an album that happens to live
/// under "… (Deluxe Edition)" would otherwise mark every one of its tracks as a variant.
bool isVariant(Track t) =>
    versionMarkers(t.title).isNotEmpty ||
    versionMarkers(t.path.split(RegExp(r'[\\/]')).last).isNotEmpty;

/// How many tracks of the RECORD are here — the number a pressing is measured against.
///
/// Not the number of files. A radio edit sitting beside the album cut is a bonus, not a twelfth
/// track, and counting it ruled out every eleven-track pressing of an eleven-track album.
int albumTrackCount(List<Track> tracks) => tracks.where((t) => !isVariant(t)).length;

/// Line a record's official tracklist up with the files actually on disk.
///
/// Owning a track is not the same as holding a file with that name. A peer spells titles its own
/// way, the release may write "Pt. 1" where the ripper wrote "Part 1", and the library can hold a
/// live take under the same title as the studio cut. So: normalised titles first, and where both
/// running times are known they have to agree within [_slack] seconds — the same tolerance every
/// other matcher in this app uses. Anything still unclaimed gets one more pass through
/// [fileOffersTitle], which reads the whole path and can explain away the artist and folder words.
///
/// Files the release doesn't name are never dropped — they come back at the end as slots with
/// index -1. A wrong tracklist must not be able to make music you own disappear from its own page.
/// Wide enough for a wrong printed time AND for a single edit, far too narrow for a different
/// performance.
///
/// Only the last pass of [matchAlbumTracks] uses this, and only on an exact title with a single
/// candidate. Drie getallen, alle drie verdiend:
///
/// * Petra's "Laat Je Gaan" ligt 24 seconden naast een catalogus die 3:10 zegt — een afgeronde of
///   verkeerd overgetypte tijd. Die moet erdoor.
/// * Barry White's "You're The First, The Last, My Everything" staat op *Can't Get Enough* als
///   nummer 2 en duurt daar 4:33; wie de single-edit van 3:25 heeft, heeft dat nummer. Achtenzestig
///   seconden. Onder de oude grens van zestig viel dat buiten de uitgave — en dan meldde de
///   albumpagina "niet op deze uitgave" terwijl de nummeringsdialoog van hetzelfde bestand zei
///   "staat op plaats 2". Twee antwoorden op één vraag, en de gebruiker zag ze allebei.
/// * RENAISSANCE's "Cozy" heeft een live-opname die zes minuten langer is dan de studioversie. Die
///   moet ONTBREKEND blijven, anders verschijnt de download die het echte nummer haalt nooit.
///
/// Een derde én anderhalve minuut: het deel is wat een andere uitvoering verraadt (een live-versie
/// of een extended mix scheelt bijna altijd meer dan een derde), en de seconden beschermen het
/// lange nummer waar een derde alsnog minuten zou zijn.
///
/// Dat een gevonden kopie een andere lengte heeft blijft wel zichtbaar — zie [AlbumSlot.andereLengte].
/// "Je hebt dit nummer, maar niet deze versie" is iets anders dan "je hebt dit nummer niet", en het
/// is ook iets anders dan stilzwijgend doen alsof het dezelfde opname is.
///
/// **Stond als sluiting binnen [matchAlbumTracks] en is naar buiten gehaald**, omdat
/// [waaromGeenPlaatsMet] precies dezelfde vraag moet stellen: die mag een hernoeming alleen
/// voorstellen wanneer de laatste pas het resultaat daarna ook aanneemt. Twee kopieën van deze drie
/// getallen zouden een knop opleveren die iets voorstelt wat daarna alsnog niet past.
bool _looseEnough(int? off, int? file) {
  if (off == null || file == null || off <= 0 || file <= 0) return false;
  final gap = (off - file).abs();
  return gap <= 90 && gap <= off / 3;
}

/// Hoort dit bestand op rij [o], terwijl het enige verschil een versiemerk is dat alleen de
/// ALBUMTITEL herhaalt?
///
/// **Gemeld op 04-09-2026 met a-ha's *MTV Unplugged – Summer Solstice*.** Het bestand heet "Take On
/// Me (MTV Unplugged)", de plaat noemt de rij kaal "Take On Me", en het bestand stond eronder als
/// "niet op deze uitgave". Ik stelde eerst voor om de titel dan maar in te korten — fout: de
/// catalogus kent `"Take On Me (MTV Unplugged)"` als **officiële** titel (4:14, op *Acoustic
/// Classics* en de *Deadpool 2*-soundtrack). Een correcte titel laten wijzigen om een gat in de
/// vergelijking te omzeilen is de verkeerde kant op repareren.
///
/// Drie eisen, en alle drie zijn ze er om iets anders tegen te houden:
///
/// * **het merk moet de PLAAT noemen** — "(MTV Unplugged)" op dat album herhaalt alleen de
///   albumtitel. "(Live)" of "(Radio Edit)" noemt de plaat niet, is een ándere opname, en hoort
///   ontbrekend te blijven: anders verschijnt de download die het echte nummer haalt nooit. Dat
///   oordeel staat al in [versieNoemtDeUitgave] en wordt hier niet nagebouwd;
/// * **de rij zelf mag geen merk dragen** — anders zou een bestand met "(MTV Unplugged)" op een rij
///   "Take On Me (Live)" vallen, want [_words] haalt aan beide kanten de merken weg en dan lijken ze
///   gelijk. Twee verschillende opnames op één rij is precies wat dit niet mag doen;
/// * **de looptijden moeten door [_looseEnough]** — dezelfde marge als de pas hierboven.
bool _merkHerhaaltAlleenHetAlbum(ChoiceTrack o, Track t, String album) {
  if (album.isEmpty || !versieNoemtDeUitgave(t.title, album)) return false;
  if (versionMarkers(o.title).isNotEmpty) return false;
  final mijn = _words(t.title);
  if (mijn.isEmpty) return false;
  final hun = _words(o.title);
  return hun.length == mijn.length &&
      hun.containsAll(mijn) &&
      _looseEnough(o.seconds, t.duration?.inSeconds);
}

AlbumCompleteness matchAlbumTracks(
  List<ChoiceTrack> official,
  List<Track> tracks,
  String artist, {
  String source = '',
  String album = '',

  /// Wat de GEBRUIKER zelf heeft toegewezen: bestandspad → [rijSleutel]. Gaat vóór alles.
  ///
  /// **Gevraagd op 05-09-2026.** Saber, over twee gelijknamige rijen: *"gebruik een functie uit
  /// roon, waar de officiele tracklist wordt geladen en ik de track moet slepen bij de juiste"*.
  /// Tot nu toe kon de app alleen raden — goed raden, maar zonder beroep. Er was ook nergens een
  /// plek waar zo'n keuze bleef staan: correcties kennen titel, nummer, plaat, artiest en persing,
  /// maar geen rij.
  ///
  /// Dezelfde afspraak als bij een handmatig samengevoegde plaat: *the user's word beats the tags*.
  /// Daarom loopt dit vóór elke automatische pas, en niet als laatste redmiddel — anders zou een
  /// titeltreffer de rij al ingepikt hebben voordat jouw keuze aan bod komt.
  Map<String, String> handmatig = const {},
}) {
  final owned = <int, Track>{};
  final claimed = <String>{};
  final multiDisc = official.map((o) => o.disc).toSet().length > 1;

  bool durationsAgree(int? a, int? b) => a == null || b == null || a <= 0 || b <= 0 || (a - b).abs() <= _slack;

  // Wat de gebruiker zelf heeft aangewezen, vóór alles. Zie [handmatig].
  if (handmatig.isNotEmpty) {
    for (var i = 0; i < official.length; i++) {
      final wil = rijSleutel(official[i]);
      for (final t in tracks) {
        if (claimed.contains(t.path)) continue;
        if (handmatig[t.path] != wil) continue;
        owned[i] = t;
        claimed.add(t.path);
        break;
      }
    }
  }

  // **En dan de hele plaat in één keer.**
  //
  // Dit is de kern, en de passen hieronder zijn sindsdien een vangnet. `besteToewijzing` legt ALLE
  // vrije bestanden en ALLE vrije rijen tegelijk op tafel en kiest de indeling met de laagste totale
  // afstand -- het Hongaarse algoritme, zoals beets' `assign_items()`. Zie `toewijzing.dart` voor de
  // gewichten, de vier harde grenzen en de twijfelregel.
  //
  // **Waarom dit vóór de passen staat en niet erna.** Die passen zijn stuk voor stuk gulzig: de
  // eerste rij die aan de beurt is pakt het eerste bestand dat toevallig past. Dat is aantoonbaar
  // fout zodra twee rijen op elkaar lijken -- op *Dip It Low (Mixes)* belandde het bestand van 3:14
  // op "Full Intention Dub" omdat die rij eerder langskwam. Wie eerst gulzig kiest, kan daarna niet
  // meer optimaal zijn.
  //
  // De passen blijven staan omdat ze twee dingen weten die een afstand tussen twee TITELS niet
  // weet: wat er in het PAD staat (`fileOffersTitle`) en de eenzijdige gastartiest van de uitgave.
  // Ze draaien nu alleen nog over wat overblijft.
  //
  // **Gemeten over deze bibliotheek** (426 platen met een geladen tracklijst), oud tegen nieuw in
  // één proces: 975 gevulde rijen werden er 999, en geen enkele rij die eerder gevuld was raakte
  // leeg. De 24 verschillen zijn stuk voor stuk nagekeken -- spellingsvarianten met dezelfde
  // looptijd ("Boss Machine"/"Bass Machine" op Thunderdome), ondertitels die maar aan één kant
  // staan ("Burning Heart (From "Rocky IV" Soundtrack)"), en de accenten van *Ce rêve bleu*.
  {
    final vrijeRijen = [
      for (var i = 0; i < official.length; i++)
        if (!owned.containsKey(i)) i,
    ];
    final vrijeBestanden = [
      for (final t in tracks)
        if (!claimed.contains(t.path)) t,
    ];
    final keuze = besteToewijzing(
        [for (final i in vrijeRijen) official[i]], vrijeBestanden,
        album: album);
    for (var k = 0; k < keuze.length; k++) {
      final j = keuze[k];
      if (j == null) continue;
      owned[vrijeRijen[k]] = vrijeBestanden[j];
      claimed.add(vrijeBestanden[j].path);
    }
  }

  // Exact title first, across the whole list, so a looser match can never steal a file from the
  // entry that names it outright.
  for (var i = 0; i < official.length; i++) {
    // Deze pas was altijd de eerste en had daarom geen reden om te kijken of de rij al bezet was.
    // Sinds [handmatig] ervóór loopt wél: zonder deze regel overschreef een titeltreffer de keuze
    // van de gebruiker, en het bestand dat die keuze had geclaimd verdween dan van de pagina —
    // geclaimd, dus ook niet meer als weeskind. Een toets ving dat meteen.
    if (owned.containsKey(i)) continue;
    final want = normKey(official[i].title);
    if (want.isEmpty) continue;
    for (final t in tracks) {
      if (claimed.contains(t.path)) continue;
      if (normKey(t.title) != want) continue;
      if (!durationsAgree(official[i].seconds, t.duration?.inSeconds)) continue;
      owned[i] = t;
      claimed.add(t.path);
      break;
    }
  }

  // Then the filename, for the ones whose tags were never written or were written wrong — the WAV
  // that scanned as "Onbekende artiest" still has the title in its name.
  for (var i = 0; i < official.length; i++) {
    if (owned.containsKey(i)) continue;
    final o = official[i];
    if (o.title.trim().isEmpty) continue;
    for (final t in tracks) {
      if (claimed.contains(t.path)) continue;
      if (!fileOffersTitle(o.title, o.seconds, artist, t.path, t.duration?.inSeconds)) continue;
      owned[i] = t;
      claimed.add(t.path);
      break;
    }
  }

  // Last, the catalogues' own disagreements. MusicBrainz writes "If You Want It to Be Good Girl"
  // where the ripper wrote "If You Want to Be a Good Girl" — one song, two spellings — and that
  // single title was enough to disqualify the pressing that IS the record.
  //
  // Deliberately last and deliberately narrow: four fifths of the words shared, running times that
  // agree, and the SAME version markers on both sides. That last rule is what stops a pressing's
  // "(radio edit)" from being folded into the album cut, which is a different recording.
  for (var i = 0; i < official.length; i++) {
    if (owned.containsKey(i)) continue;
    final o = official[i];
    for (final t in tracks) {
      if (claimed.contains(t.path)) continue;
      if (!sameTitle(o.title, t.title,
          secondsA: o.seconds, secondsB: t.duration?.inSeconds)) {
        continue;
      }
      owned[i] = t;
      claimed.add(t.path);
      break;
    }
  }

  // Dan de gastartiest die maar aan ÉÉN kant genoemd wordt.
  //
  // **Gemeld op 31-08-2026, met een schermafdruk van *Dangerously in Love*.** Onder "Niet op deze
  // uitgave" stonden "Crazy In Love" en "Baby Boy" — twee nummers die nota bene de bekendste van
  // die plaat zijn. De uitgave schrijft ze als "Crazy in Love (feat. JAY-Z)" en "Baby Boy (feat.
  // Sean Paul)"; de rip schreef de gast in het ARTIEST-veld en liet de titel kaal.
  //
  // Waarom geen van de passen hierboven dat opving: `_words` haalt met opzet alleen VERSIE-merken
  // weg en laat "(feat. …)" staan, omdat daar een echt verschil in kan zitten — Adele's *30* heeft
  // "Easy On Me" én "Easy On Me (With Chris Stapleton)", twee opnames. Gevolg is wel dat drie
  // gedeelde woorden tegen zes gezette woorden op 50% uitkwam, ver onder de vier vijfde.
  //
  // **Deze pas loopt maar ÉÉN kant op, en dat is de hele veiligheid ervan.** De gaststaart mag
  // alleen van de UITGAVE af, nooit van het bestand. De tracklijst van een persing is de autoriteit
  // over wat er op die plaat staat:
  //
  // * noemt de uitgave "Crazy in Love (feat. JAY-Z)" en heet jouw bestand "Crazy In Love", dan héb
  //   je dat nummer — een ripper heeft de credit gewoon niet overgetypt.
  // * noemt de uitgave "Easy on Me" en heet jouw bestand "Easy On Me (With Chris Stapleton)", dan
  //   heb je iets wat die uitgave NIET noemt. Dat is Adele's *30*, waar de solo en het duet twee
  //   opnames van bijna dezelfde lengte zijn. Het duet op de rij van de albumversie leggen zou het
  //   ene nummer verbergen en het andere ten onrechte als binnengehaald tellen.
  //
  // Die tweede kant is met zoveel woorden een toets in `completeness_test.dart`, en die zakte toen
  // deze pas nog symmetrisch was. Van buiten zijn de twee gevallen niet te onderscheiden, dus er
  // valt niets slims te bedenken: één richting is het antwoord.
  //
  // Daarnaast UNICITEIT: de kale titel moet op de uitgave precies één rij opleveren, en er mag
  // precies één vrij bestand op passen. Anders is het een gok tussen twee kandidaten. En de
  // speelduur moet nog steeds kloppen.
  for (var i = 0; i < official.length; i++) {
    if (owned.containsKey(i)) continue;
    final vol = normKey(official[i].title);
    final kaal = normKey(zonderFeat(official[i].title));
    // Noemt deze rij helemaal geen gast, dan valt er niets weg te denken en heeft de exacte pas
    // hierboven het laatste woord al gehad.
    if (kaal.isEmpty || kaal == vol) continue;
    if (official.where((o) => normKey(zonderFeat(o.title)) == kaal).length != 1) continue;
    final passend = [
      for (final t in tracks)
        if (!claimed.contains(t.path) &&
            // `== kaal` en niet `zonderFeat(t.title) == kaal`: het bestand moet zélf kaal zijn.
            // Draagt het een eigen credit, dan is het misschien een andere opname — zie hierboven.
            normKey(t.title) == kaal &&
            durationsAgree(official[i].seconds, t.duration?.inSeconds))
          t,
    ];
    if (passend.length != 1) continue;
    owned[i] = passend.single;
    claimed.add(passend.single.path);
  }

  // En de andere kant: de gast staat in het BESTAND en de uitgave zet hem ergens anders neer.
  //
  // **Waarom dit niet zomaar mag, en hier wél.** Hierboven staat waarom de gaststaart nooit van het
  // bestand af mag op de titel alleen: dan valt Adele's duet op de rij van de albumversie. Maar
  // MusicBrainz zet een gast helemaal niet in de titel — daar heet de rij gewoon "Crazy in Love" en
  // staat "Beyoncé feat. JAY-Z" in de artiestcredit ernaast. Een rip schrijft hem juist wél in de
  // titel. Op de titel alleen zijn die twee gevallen niet te scheiden.
  //
  // Met de credit erbij wél, en dan is het een feit in plaats van een gok: de uitgave moet die gast
  // ZELF noemen. Bij Beyoncé staat JAY-Z in de credit van dat nummer; bij Adele staat er alleen
  // "Adele" en komt Chris Stapleton er niet in voor. Noemt de bron geen credit — Discogs levert hem
  // hier niet — dan is er geen bewijs en gebeurt er niets, precies zoals voorheen.
  for (var i = 0; i < official.length; i++) {
    if (owned.containsKey(i)) continue;
    final o = official[i];
    if (o.artist.trim().isEmpty) continue;
    final rijTitel = normKey(o.title);
    // De uitgave moet zelf een KALE titel hebben; draagt zij de credit ook, dan is de pas hierboven
    // aan zet en heeft die het al bekeken.
    if (rijTitel != normKey(zonderFeat(o.title))) continue;
    if (official.where((x) => normKey(x.title) == rijTitel).length != 1) continue;
    final passend = [
      for (final t in tracks)
        if (!claimed.contains(t.path) &&
            normKey(zonderFeat(t.title)) == rijTitel &&
            _uitgaveNoemtDeGasten(o.artist, t) &&
            durationsAgree(o.seconds, t.duration?.inSeconds))
          t,
    ];
    if (passend.length != 1) continue;
    owned[i] = passend.single;
    claimed.add(passend.single.path);
  }

  // Very last: an EXACT title match that only the running time rejected.
  //
  // Measured on Het Beste Van Petra. The file is `02 - Laat Je Gaan.flac`, in that album's own
  // folder, titled exactly what the pressing calls track 2 — and the catalogue says 3:10 where the
  // file plays 3:34. Twenty-four seconds is well past the slack, so every pass above refused it and
  // the record showed "2 · Laat Je Gaan — niet in bibliotheek" with the file listed underneath as
  // not being on this release. Which is nonsense on its face.
  //
  // Catalogue times for a 1996 CNR compilation are rounded, mistyped, or copied from a different
  // pressing. An exact title on the record's own tracklist is much stronger evidence than a printed
  // duration — but only when nothing else wants either side, which is why this runs after
  // everything else and takes only rows and files that are still free. A radio edit does not reach
  // here at all: its title carries a version marker, so it never matched exactly to begin with.
  for (var i = 0; i < official.length; i++) {
    if (owned.containsKey(i)) continue;
    final want = normKey(official[i].title);
    if (want.isEmpty) continue;
    final passend = [
      for (final t in tracks)
        if (!claimed.contains(t.path) &&
            normKey(t.title) == want &&
            _looseEnough(official[i].seconds, t.duration?.inSeconds))
          t,
    ];
    // Exactly one candidate, or it is a guess again.
    if (passend.length != 1) continue;
    owned[i] = passend.single;
    claimed.add(passend.single.path);
  }

  // Allerlaatst: een bestand waarvan het versiemerk alleen de ALBUMTITEL herhaalt. Zie
  // [_merkHerhaaltAlleenHetAlbum] voor waarom dat een aanvaarde titel is en geen fout.
  //
  // Achter alle andere passen, en alleen op rijen en bestanden die nog vrij zijn: een rij die
  // letterlijk zo heet moet altijd voorgaan.
  //
  // **Beide kanten moeten eenduidig zijn.** Deze lus loopt over de BESTANDEN en niet over de rijen,
  // en dat is geen smaak: andersom geschreven pakte bij twee rijen die er allebei op lijken gewoon
  // de eerste, omdat de vraag dan "welk bestand hoort bij deze rij" is in plaats van "welke rij
  // hoort bij dit bestand". Een toets ving dat. Daarnaast wordt ook de andere kant nagekeken — twee
  // vrije bestanden die allebei op dezelfde rij passen is net zo goed gokken.
  for (final t in tracks) {
    if (claimed.contains(t.path)) continue;
    final rijen = [
      for (var i = 0; i < official.length; i++)
        if (!owned.containsKey(i) && _merkHerhaaltAlleenHetAlbum(official[i], t, album)) i,
    ];
    if (rijen.length != 1) continue;
    final i = rijen.single;
    final ookMogelijk = tracks.any((a) =>
        a.path != t.path &&
        !claimed.contains(a.path) &&
        _merkHerhaaltAlleenHetAlbum(official[i], a, album));
    if (ookMogelijk) continue;
    owned[i] = t;
    claimed.add(t.path);
  }

  return AlbumCompleteness(
    [
      for (var i = 0; i < official.length; i++)
        AlbumSlot(index: i, official: official[i], track: owned[i], multiDisc: multiDisc),
      // Whatever the release doesn't account for, last and still playable.
      for (final t in tracks)
        if (!claimed.contains(t.path)) AlbumSlot(index: -1, track: t),
    ],
    source: source,
  );
}

/// Waarom dit bestand geen plaats op de uitgave kreeg, in gewone taal — en op wélke rij het dan wél
/// had moeten passen.
///
/// **Waarvoor dit bestaat.** "Niet op deze uitgave" is een uitkomst, geen uitleg. Op 31-08-2026
/// stonden "Crazy in Love" en "Baby Boy" eronder — twee van de bekendste nummers van die plaat — en
/// er stond nergens waaróm. Het heeft drie ronden en drie uitgaven gekost om dat uit te zoeken, en
/// elke ronde begon met raden op een schermafdruk. Eén regel onder de rij was elke keer genoeg
/// geweest.
///
/// Het toont ook de RUWE titel als die anders is dan wat de rij laat zien: de nummerrij haalt de
/// "(feat. …)" er met opzet af om hem netjes te tekenen, en juist dat verschil was hier het hele
/// verhaal. Wat je ziet en wat er in het bestand staat mogen niet ongemerkt uit elkaar lopen.
///
/// **Waarom de rij erbij moest.** De uitleg was een doodlopende weg: je las wat er mis was en kon er
/// niets aan doen. Gevraagd op 02-09-2026: *"zorg dat ik er iets aan kan doen, titel aanpassen met
/// suggesties wat het dan wel moet zijn officieel"*. Die suggestie IS de officiële titel — en die
/// stond hier al, in `gelijk.single`, om de zin mee te schrijven. Hij werd alleen weggegooid.
///
/// **Eén vergelijking, twee gebruikers.** De uitleg en de suggestie komen uit precies dezelfde
/// match. Zou de knop zijn eigen vergelijking krijgen, dan kan er een dag komen waarop de regel
/// eronder "de uitgave noemt X" zegt en de knop iets anders voorstelt — en dat is erger dan geen
/// knop, want dan is de uitleg niet meer te vertrouwen.
///
/// **[uitgave] is alleen gevuld waar er werkelijk iets te kiezen valt**, en dat is nauwer dan waar
/// er een rij te vinden is:
///
/// * bij een LENGTEverschil is de titel al gelijk — een knop "titel rechtzetten" zou daar niets
///   veranderen;
/// * bij meer dan één treffer zegt de zin zelf dat niet te bepalen is welke rij het is, en een
///   suggestie zou die zin tegenspreken;
/// * bij een lege tracklijst is er niets om naar te wijzen.
/// [album] is de titel van de PLAAT waar dit bestand op staat. Alleen nodig voor de laatste tak
/// hieronder: die vraagt of een versiemerk in de titel niets anders doet dan de albumtitel
/// herhalen. Leeg laten kan, en dan blijft die tak uit — geen enkele bestaande aanroeper verandert
/// er iets van.
({ChoiceTrack? uitgave, String reden}) waaromGeenPlaatsMet(
    List<ChoiceTrack> official, Track t,
    {String album = ''}) {
  if (official.isEmpty) return (uitgave: null, reden: 'er is geen tracklijst opgehaald');
  final mijn = normKey(t.title);
  final mijnKaal = normKey(zonderFeat(t.title));
  final duur = t.duration?.inSeconds ?? 0;

  String tijd(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  // Zelfde titel, andere lengte: dan heb je het nummer wel maar een andere snit. Het meest
  // voorkomende geval, en het enige waar een getal het antwoord ÍS.
  for (final o in official) {
    if (normKey(o.title) != mijn) continue;
    final os = o.seconds ?? 0;
    if (os > 0 && duur > 0 && (os - duur).abs() > _slack) {
      // **Véél te kort is geen andere snit, dat is een kapot bestand — en dat hoort er te staan.**
      //
      // Gevonden op 05-09-2026 bij het doorlichten van de bibliotheek, en nagemeten met ffprobe
      // op de bestanden zelf: `03 - Don't Stop The Music (2).flac` bevat 109 seconden van een
      // nummer van 4:27, en `60 - ... Do It Again.flac` 128 van 229. Allebei liggen ze naast een
      // volledige kopie, dus de download is halverwege afgebroken.
      //
      // De oude zin ("de uitgave geeft 4:27 op en dit bestand duurt 1:49") klopte wel, maar leest
      // als "je hebt een andere versie" — precies de verkeerde conclusie. Een radio-edit haalt de
      // grens hieronder niet: Barry White's "(Edit)" is 205 van 275 seconden, oftewel 75%.
      if (duur < os * _afgekaptDeel && os - duur >= _afgekaptGat) {
        return (
          uitgave: null,
          reden: 'dit bestand duurt ${tijd(duur)} terwijl de uitgave ${tijd(os)} opgeeft — dat is '
              'een afgebroken download, geen andere snit',
        );
      }
      return (
        uitgave: null,
        reden: 'de uitgave geeft ${tijd(os)} op en dit bestand duurt ${tijd(duur)}',
      );
    }
  }
  final gelijk = official.where((o) => normKey(zonderFeat(o.title)) == mijnKaal).toList();
  if (gelijk.length > 1) {
    return (
      uitgave: null,
      reden: 'de uitgave noemt dit nummer ${gelijk.length} keer — niet te zeggen welke dit is',
    );
  }
  if (gelijk.length == 1) {
    final o = gelijk.single;
    final gasten = splitFeatured(t.artist, t.title).featured;
    if (gasten.isNotEmpty && normKey(o.title) != mijn) {
      return (
        uitgave: o,
        reden: o.artist.trim().isEmpty
            ? 'jouw bestand heet "${t.title}"; de uitgave noemt "${o.title}" en zegt niet wie er '
                'meespeelt'
            : 'jouw bestand heet "${t.title}"; de uitgave noemt "${o.title}" met ${o.artist}',
      );
    }
    return (
      uitgave: o,
      reden: 'jouw bestand heet "${t.title}", de uitgave noemt "${o.title}"',
    );
  }
  // Draagt de titel een merk dat alleen de ALBUMTITEL herhaalt, dan is dat geen fout van jou maar
  // een gat in de vergelijking — en dat wordt in [matchAlbumTracks] gedicht, niet hier met een knop
  // die je vraagt een officiële titel in te korten. Zie [_merkHerhaaltAlleenHetAlbum].
  //
  // Komt een bestand ondanks die pas hier terecht, dan is er iets anders aan de hand (twee
  // kandidaten, of looptijden die te ver uiteenlopen) en zou een hernoeming het óók niet oplossen:
  // die pas stelt precies dezelfde eisen. Vandaar geen rij, en dus geen knop.
  if (album.isNotEmpty && versieNoemtDeUitgave(t.title, album)) {
    return (
      uitgave: null,
      reden: 'jouw bestand heet "${t.title}"; die toevoeging herhaalt alleen de albumtitel, maar '
          'geen enkele rij past er verder bij',
    );
  }
  return (uitgave: null, reden: 'de uitgave noemt geen nummer dat "${t.title}" heet');
}

/// Wat een titelherstel van dit bestand zou máken: de officiële titel, en waar de gastnaam heen gaat.
///
/// **Waarom de artiest hierbij hoort.** De app heeft al een regel dat een persing géén gasten van
/// jouw titel mag afpakken — zie `_behoudTitel`, geschreven voor "Lose Control (feat. Ciara and Fat
/// Man Scoop)", met als reden: *dan is niet meer te zien wie er meedoet*. Een knop die de officiële
/// titel overneemt doet precies dát, tenzij de naam ergens anders terugkomt. Daarom levert deze
/// functie de twee velden samen: los van elkaar zijn ze een verlies, samen zijn ze een verhuizing.
///
/// [artiest] is null als er niets te verhuizen valt — geen gasten, of de officiële titel noemt ze
/// zelf, of het artiestveld zegt het al. Dan verandert alleen de titel.
({String titel, String? artiest}) titelherstel(ChoiceTrack uitgave, Track t) => (
      titel: uitgave.title.trim(),
      artiest: gastNaarArtiest(t, uitgave.title, uitgaveArtiest: uitgave.artist),
    );

/// Welke artiestcredit dit bestand moet krijgen als het voortaan [nieuweTitel] heet.
///
/// Null als er niets te verhuizen valt: geen gasten, of [nieuweTitel] noemt ze zelf nog, of het
/// artiestveld zegt het al. Apart van [titelherstel] omdat het venster hier bij ELKE toetsaanslag
/// om vraagt — typ je zelf een titel die de gast weer noemt, dan hoort de schakelaar meteen te
/// verdwijnen in plaats van de naam er dubbel in te zetten.
String? gastNaarArtiest(Track t, String nieuweTitel, {String uitgaveArtiest = ''}) {
  final gesplitst = splitFeatured(t.artist, t.title);
  // Draagt de nieuwe titel zelf een "(feat. …)", dan blijven de namen daar staan.
  if (gesplitst.featured.isEmpty || featStaart(nieuweTitel.trim()).isNotEmpty) return null;
  // De uitgave gaat vóór onze eigen samenstelling: die credit is wat de plaat zélf zegt, en het is
  // dezelfde tekst die de gebruiker in de uitleg heeft zien staan ("de uitgave noemt X met Y").
  final credit = uitgaveArtiest.trim().isNotEmpty
      ? uitgaveArtiest.trim()
      : gastcredit(gesplitst.main, gesplitst.featured);
  return normKey(credit) == normKey(t.artist) ? null : credit;
}

/// De sleutel waarmee een handmatige toewijzing naar precies één rij van de uitgave wijst.
///
/// Schijf én positie, want een dubbele plaat nummert op elke schijf opnieuw vanaf 1: op de positie
/// alleen zou "2" twee rijen aanwijzen. Tekst, omdat een persing niet altijd in gehele getallen
/// nummert — een vinylkant is "A3".
String rijSleutel(ChoiceTrack o) => '${o.disc}|${o.position}';

/// Noemt de uitgave deze titel meer dan één keer?
///
/// Zo ja, dan is de LOOPTIJD wat bepaald heeft op welke rij een bestand terechtkwam, en hoort dat
/// getal op het scherm te staan — anders is de indeling niet na te rekenen. Precies het geval van
/// *Dip It Low (Mixes)*: twee rijen "Dip It Low" van 3:18 en 3:40, en twee bestanden van 3:14 en
/// 3:38 die daar correct maar onzichtbaar aan gekoppeld werden.
bool titelKomtVakerVoor(List<ChoiceTrack> official, ChoiceTrack rij) {
  final k = normKey(rij.title);
  if (k.isEmpty) return false;
  var n = 0;
  for (final o in official) {
    if (normKey(o.title) == k && ++n > 1) return true;
  }
  return false;
}

/// Hoe ANDERE persingen dit ene nummer noemen, met hoeveel er dat zo doen.
///
/// **Waarvoor.** De persing die de pagina toont is er één van soms tientallen. Noemt die het nummer
/// kaal terwijl jouw bestand een gast noemt, dan is de vraag niet alleen "wat zegt deze uitgave"
/// maar "wat zeggen ze allemaal" — en dan blijkt een andere persing hem vaak wél met de gast te
/// noemen. Gevraagd op 02-09-2026: *"haal officiele titels van discogs of musicbrainz"*.
///
/// Het AANTAL staat erbij omdat één afwijkende persing iets anders betekent dan negen die het eens
/// zijn. Zonder dat getal is een lijst titels een rij gokjes zonder onderscheid.
///
/// **Ook de spelling die jouw bestand al heeft komt terug**, en die weglaten was een fout die pas
/// bij het toetsen bovenkwam. "Negen van de twaalf persingen noemen het net zoals jij" is namelijk
/// het antwoord op de vraag die eronder ligt — *moet ik dit überhaupt veranderen?* — en dat is hier
/// het waarschijnlijkste geval: de getoonde persing laat de gast weg, de rest niet. Deze functie
/// telt daarom álles, en het venster beslist wat het als knop toont en wat als mededeling.
///
/// Vergelijkt op dezelfde manier als [waaromGeenPlaatsMet]: op de titel zonder gastcredit. Een
/// andere vergelijking hier zou rijen binnenhalen die de uitleg op het scherm niet als ditzelfde
/// nummer erkent.
List<({String titel, int persingen})> titelsUitPersingen(
  Iterable<List<ChoiceTrack>> persingen,
  Track t,
) {
  final mijnKaal = normKey(zonderFeat(t.title));
  final telling = <String, int>{};
  final spelling = <String, String>{};
  for (final lijst in persingen) {
    // Per PERSING één keer tellen: een dubbele plaat die het nummer twee keer draagt is nog steeds
    // één bron die het zo noemt.
    final indeze = <String>{};
    for (final o in lijst) {
      if (normKey(zonderFeat(o.title)) != mijnKaal) continue;
      final titel = o.title.trim();
      if (titel.isEmpty) continue;
      final k = normKey(titel);
      if (!indeze.add(k)) continue;
      telling[k] = (telling[k] ?? 0) + 1;
      spelling[k] ??= titel;
    }
  }
  final uit = [
    for (final e in telling.entries) (titel: spelling[e.key]!, persingen: e.value),
  ];
  // Vaakst eerst; bij gelijk spel alfabetisch, zodat dezelfde lijst niet elke keer anders staat.
  uit.sort((a, b) {
    final n = b.persingen.compareTo(a.persingen);
    return n != 0 ? n : a.titel.compareTo(b.titel);
  });
  return uit;
}

/// Eén voorgestelde titelwijziging. Zuiver: er wordt niets geschreven.
///
/// Bewust NIET `TitelStap` genoemd, hoe verleidelijk dat ook is: die klasse bestaat al in
/// `library.dart` en is wat er daadwerkelijk geschréven wordt. Twee namen die één hoofdletter uit
/// elkaar liggen en verschillende kanten van dezelfde bewerking betekenen, gaat een keer mis.
typedef Titelvoorstel = ({Track track, String titel, String? artiest});

/// Wat "alle titels rechtzetten" op deze plaat zou doen.
///
/// Alleen weeskinderen waarvoor [waaromGeenPlaatsMet] één rij van de uitgave heeft kunnen aanwijzen
/// — dezelfde nauwe voorwaarde als bij het losse nummer, zodat het overzicht nooit iets voorstelt
/// wat de regel onder die rij niet beweert. Nummers waar niets aan verandert vallen weg: een lijst
/// met regels die niets doen is een lijst waarin je de echte niet meer ziet.
List<Titelvoorstel> titelVoorstellen(List<ChoiceTrack> official, List<Track> weesjes,
    {String album = ''}) {
  final uit = <Titelvoorstel>[];
  for (final t in weesjes) {
    final rij = waaromGeenPlaatsMet(official, t, album: album).uitgave;
    if (rij == null) continue;
    final v = titelherstel(rij, t);
    if (v.titel.isEmpty) continue;
    if (v.titel == t.title.trim() && v.artiest == null) continue;
    uit.add((track: t, titel: v.titel, artiest: v.artiest));
  }
  return uit;
}

/// Titels die door deze bewerking op elkaar zouden landen — en dan verdwijnt er één uit de lijst.
///
/// **En dit is juist de gewone gang van zaken, niet een randgeval.** `_dedupeTracks` vouwt twee
/// bestanden samen op [trackIdentity], en die is `normKey(artiest)|normKey(titel)` — zonder enige
/// vergevingsgezindheid. (De sleutel die "(feat. …)" wél wegstript is een ándere, voor de vraag "heb
/// ik deze opname al?".) Heeft een plaat zowel "One Minute Man" als "One Minute Man (Feat
/// Ludacris)", dan landen die twee door een titelherstel op dezelfde sleutel en verdwijnt er één van
/// de pagina.
///
/// Waar de schakelaar "gast naar het artiestveld" dus voor een tweede keer zijn nut bewijst: die
/// verandert de ARTIESThelft van de sleutel mee, en houdt de twee daarmee uit elkaar. Vandaar dat
/// [sleutelNa] de voorgestelde artiest meeneemt en niet alleen de titel.
///
/// [opDePlaat] is alles wat de tegel toont, niet alleen wat er verandert: een weesje kan op de titel
/// van een nummer landen dat al netjes op zijn plaats staat, en dat is juist het waarschijnlijke
/// geval. Titels die vóór de bewerking al dubbel waren tellen niet mee — daar zou weigeren de
/// functie blokkeren op precies de rommelige platen waarvoor ze bestaat. Dezelfde afweging als
/// `NormalisePlan.clashList`.
List<String> titelBotsingen(List<Titelvoorstel> stappen, List<Track> opDePlaat) {
  final nieuw = {for (final s in stappen) s.track.path: s};
  String sleutelVoor(Track t) => trackIdentity(t.artist, t.title);
  String sleutelNa(Track t) {
    final s = nieuw[t.path];
    return s == null ? sleutelVoor(t) : trackIdentity(s.artiest ?? t.artist, s.titel);
  }

  final alDubbel = <String>{}, gezien = <String>{};
  for (final t in opDePlaat) {
    if (!gezien.add(sleutelVoor(t))) alDubbel.add(sleutelVoor(t));
  }

  final out = <String>[];
  final eerste = <String, Track>{};
  for (final t in opDePlaat) {
    final k = sleutelNa(t);
    final prev = eerste[k];
    if (prev == null) {
      eerste[k] = t;
      continue;
    }
    if (alDubbel.contains(k)) continue; // stond er al zo in — niet onze schuld
    // Alleen melden als DEZE bewerking het veroorzaakt.
    if (!nieuw.containsKey(t.path) && !nieuw.containsKey(prev.path)) continue;
    final naam = nieuw[t.path]?.titel ?? t.title;
    out.add('"$naam" — ${prev.title} en ${t.title}');
  }
  return out;
}

/// Noemt de artiestcredit van de uitgave élke gast die dit bestand noemt?
///
/// Alle gasten, niet één ervan: heet jouw bestand "Song (feat. A & B)" en zegt de uitgave alleen
/// "X feat. A", dan is dat een andere opname en geen slordige tag. En het moet er minstens één zijn,
/// anders zou een bestand zonder gast langs deze weg binnenkomen — daar is de exacte vergelijking
/// voor.
bool _uitgaveNoemtDeGasten(String uitgaveArtiest, Track t) {
  final gasten = splitFeatured(t.artist, t.title).featured;
  if (gasten.isEmpty) return false;
  final genoemd = splitFeatured(uitgaveArtiest, '').featured.map(artistKey).toSet();
  // Ook de hele credit als losse WOORDEN, want een bron kan "Beyoncé & JAY-Z" schrijven in plaats
  // van "feat." — dan haalt `splitFeatured` er niets uit terwijl de naam er wel degelijk staat.
  //
  // Woorden en geen tekstzoektocht: `contains` zou "Sean" laten passen op een credit waar "seance"
  // in staat, en één valse treffer hier legt twee opnames op dezelfde rij.
  final woorden = normKey(uitgaveArtiest).split(' ').where((w) => w.isNotEmpty).toSet();
  for (final g in gasten) {
    if (genoemd.contains(artistKey(g))) continue;
    final delen = normKey(g).split(' ').where((w) => w.isNotEmpty).toList();
    if (delen.isNotEmpty && delen.every(woorden.contains)) continue;
    return false;
  }
  return true;
}

/// Seconds two timings may differ and still be the same recording. Matches [fileOffersTitle].
const _slack = 12;

/// Wanneer een bestand niet "een andere snit" is maar gewoon afgebroken. Zie [waaromGeenPlaatsMet].
///
/// Twee eisen, want één is niet genoeg. Alleen een PERCENTAGE zou elke korte rij verdacht maken —
/// een interlude van 7 seconden tegenover 10 is ook 70%, en daar is niets mis mee. Alleen een
/// AANTAL seconden zou elke lange remix pakken. Samen laten ze precies de twee gevallen over die de
/// bibliotheek heeft: 41% met 158 seconden weg, en 56% met 101 seconden weg.
const _afgekaptDeel = 0.7;
const _afgekaptGat = 45;

/// De woorden van de SONGTITEL, zonder de merken.
///
/// Merken worden apart vergeleken door [_sameMarkers]. Ze daarnaast ook nog in de woordoverlap laten
/// meetellen straft hetzelfde verschil twee keer af, en dat is precies genoeg om een treffer te
/// missen: "What's My Name? (Album Version)" tegen een kale rij haalde zo 60% -- onder de grens van
/// vier vijfde -- terwijl het over dezelfde drie woorden gaat. Gemeten over de hele bibliotheek kostte
/// dit Rihanna's Loud drie nummers.
///
/// Alleen erkende merken gaan eruit. Een haakje dat GEEN versie aanduidt -- "(feat. JAY-Z)", "(With
/// Chris Stapleton)" -- blijft meetellen, want daar kan het verschil tussen twee opnames in zitten:
/// Adele's 30 heeft "Easy On Me" en het duet met Chris Stapleton allebei, en die mogen niet op één
/// rij vallen.
Set<String> _words(String s) =>
    normKey(withoutVersionText(s)).split(' ').where((w) => w.isNotEmpty).toSet();

/// Are these two titles the same song, allowing for how differently catalogues spell them?
///
/// MusicBrainz writes "If You Want It to Be Good Girl" where the ripper — and another pressing of
/// the same record — writes "If You Want to Be a Good Girl". Judged on exact text those are two
/// songs, which made a complete album look incomplete and then offered the user a track they
/// already owned as a bonus.
///
/// Narrow on purpose: four fifths of the words shared, running times that agree where both are
/// known, and the SAME version markers on both sides — so a "(radio edit)" is never the album cut,
/// however alike the words.
bool sameTitle(String a, String b, {int? secondsA, int? secondsB}) {
  final aw = _words(a), bw = _words(b);
  if (aw.isEmpty || bw.isEmpty) return false;
  if (secondsA != null &&
      secondsB != null &&
      secondsA > 0 &&
      secondsB > 0 &&
      (secondsA - secondsB).abs() > _slack) {
    return false;
  }
  if (!zelfdeVersiemerken(a, b)) return false;
  final shared = aw.intersection(bw).length;
  return shared / (aw.length > bw.length ? aw.length : bw.length) >= .8;
}

/// Two files of one record that hold the same recording.
///
/// Named apart from `sameRecordingScore` in organize.dart on purpose: that one asks whether a peer's
/// offering is the track you clicked, this one asks whether two files you already own are the same
/// song. Same question, opposite side of the download.
class SameRecordingPair {
  /// The copy worth keeping, and the one it beats.
  final Track keep, drop;

  /// Why [keep] wins, in words, from the same grounds [firstIsBetter] decides on.
  final String why;
  const SameRecordingPair(this.keep, this.drop, this.why);
}

/// Files in one album that are the same recording twice.
///
/// Deliberately NOT on running time alone. On Backstreet's Back ten of the pairs fall within
/// [_slack] seconds of each other — 4:23 beside 4:25, 3:30 beside 3:33 — so a length-only rule
/// would call half the record a duplicate. The pair has to agree on the TITLE as well, through the
/// same [sameTitle] the pressing match uses: four fifths of the words, running times that agree,
/// and the SAME version markers, so a radio edit is never folded into the album cut.
///
/// This is the pair the album page could not see. Two rips of "If You Want It to Be Good Girl"
/// landed under different names because they were filed against different pressings, and nothing
/// afterwards ever compared two files in the library with each other.
///
/// [better] decides which copy wins; it reads the files, so it is passed in and the pure part of
/// this stays testable without a disk.
/// [prints] is what the AUDIO says, by file path, and when it has an opinion it is the last word.
///
/// The titles were all this ever had, and titles are the thing that is wrong. Michael Jackson's
/// *Off The Wall* holds one recording twice in one folder, filed as "Workin' Day and Night" and
/// "Working Day And Night": three of four words shared, so [sameTitle] says no and the album kept
/// two copies of one song — which is exactly the kind of clash that splits a record into two tiles.
/// The fingerprints score that pair 1.000.
///
/// It overrules in both directions, and the second one matters more. Adele's *30* has "Easy On Me"
/// and "Easy On Me (With Chris Stapleton)" — near-identical titles, near-identical length — and the
/// audio says 0.929: the same backing, a different performance. Without a listen, that duet was a
/// deletion waiting to be offered.
List<SameRecordingPair> sameRecordingPairs(
  List<Track> tracks, {
  required bool Function(Track a, Track b) better,
  String Function(Track keep, Track drop)? why,
  Map<String, List<int>> prints = const {},
}) {
  final out = <SameRecordingPair>[];
  final spoken = <String>{};
  for (var i = 0; i < tracks.length; i++) {
    final a = tracks[i];
    if (spoken.contains(a.path)) continue;
    final sa = a.duration?.inSeconds ?? 0;
    final fa = prints[a.path];
    // No length and no fingerprint means no evidence — a title alone is not enough to drop a file.
    if (sa <= 0 && fa == null) continue;
    for (var j = i + 1; j < tracks.length; j++) {
      final b = tracks[j];
      if (spoken.contains(b.path)) continue;
      final sb = b.duration?.inSeconds ?? 0;
      final fb = prints[b.path];
      if (sb <= 0 && fb == null) continue;
      if (fa != null && fb != null) {
        // Both were heard. Whatever the tags claim, this decides.
        if (similarity(fa, fb) < sameRecordingScore) continue;
      } else {
        if (sa <= 0 || sb <= 0) continue;
        if (!sameTitle(a.title, b.title, secondsA: sa, secondsB: sb)) continue;
      }
      final aWins = better(a, b);
      final keep = aWins ? a : b, drop = aWins ? b : a;
      out.add(SameRecordingPair(keep, drop, why?.call(keep, drop) ?? ''));
      spoken..add(a.path)..add(b.path);
      break; // one partner per file; a third copy is reported the next time round
    }
  }
  return out;
}

/// Which pressings are worth fetching a tracklist for, cheaply, from their track counts alone.
///
/// Costs nothing — the release-group browse already states every pressing's count — and it is the
/// step that keeps the expensive one bounded: MusicBrainz allows one request per second, and a
/// record can have seventy-five pressings.
///
/// Smallest-that-fits first. A pressing that holds exactly what you own describes the record; a
/// bigger one describes a different edition of it. A pressing SMALLER than what you own cannot be
/// your record at all, so it is only reached when nothing else qualifies — better to describe the
/// album with a near miss than not at all.
///
/// Returns indices into [trackCounts], preserving its order among equal counts, so the caller's
/// existing preference ranking (CD before vinyl, documented, original pressing) breaks ties.
List<int> shortlistPressings(List<int> trackCounts, int owned, {int take = 3}) {
  final fits = <int>[];
  final rest = <int>[];
  for (var i = 0; i < trackCounts.length; i++) {
    if (trackCounts[i] <= 0) continue; // count unstated — nothing to rank on
    (trackCounts[i] >= owned ? fits : rest).add(i);
  }
  int bySize(int a, int b) {
    final c = trackCounts[a].compareTo(trackCounts[b]);
    return c != 0 ? c : a.compareTo(b);
  }

  fits.sort(bySize);
  // The fallbacks are the BIGGEST of the too-small ones — the closest thing to holding it all.
  rest.sort((a, b) => bySize(b, a));
  return [...fits, ...rest].take(take).toList();
}

/// Which of the fetched pressings actually describes this record.
///
/// The rule that matters is containment, not size: a pressing that does not name every track on
/// disk is not the record you own, however well it scores otherwise. Among the ones that do name
/// everything, the smallest wins — for Backstreet's Back that is the eleven-track pressing over the
/// sixteen-track double CD, which is the difference between "complete" and five invented gaps.
///
/// When nothing names everything, the best-covering pressing wins rather than none: a record
/// described by a near miss is more use than a record not described at all. The caller can tell
/// the two apart with [AlbumCompleteness.namesEverything] and say so.
///
/// [candidates] arrives in preference order, so index order is the tiebreak.
int pickPressing(List<AlbumCompleteness> candidates) {
  if (candidates.isEmpty) return -1;
  var best = 0;
  for (var i = 1; i < candidates.length; i++) {
    if (_beats(candidates[i], candidates[best])) best = i;
  }
  return best;
}

bool _beats(AlbumCompleteness a, AlbumCompleteness b) {
  final aAll = a.namesEverything, bAll = b.namesEverything;
  if (aAll != bAll) return aAll;
  if (aAll) return a.missing.length < b.missing.length; // smallest pressing that still holds it
  final byMatched = a.matched.compareTo(b.matched);
  if (byMatched != 0) return byMatched > 0; // covers more of what you own
  return a.missing.length < b.missing.length;
}

/// A track that isn't on your pressing, but is on another one of the same record.
class BonusTrack {
  final ChoiceTrack track;

  /// Which pressing it comes from, as its edition line reads ("CD · US · 1997").
  final String edition;

  const BonusTrack(this.track, this.edition);
}

/// What the other pressings of this record have that you don't.
///
/// Backstreet's Back is eleven tracks in Britain and thirteen in America, plus a Malaysian second
/// disc with a Christmas song on it. None of that is missing from your record — it was never on
/// it — but it is the rest of the record, and worth being able to see and fetch.
///
/// Two things disqualify a track, and BOTH are needed. It must not be on your pressing, and it
/// must not be on your disk: the first pass alone offered the user back the radio edit they
/// already owned, because their pressing doesn't list it. Both comparisons go through [sameTitle],
/// so a pressing that spells a title its own way doesn't produce a phantom bonus — that is exactly
/// how "If You Want to Be a Good Girl" ended up offered to someone who had it as track 10.
List<BonusTrack> bonusTracks(
  List<ChoiceTrack> mine,
  List<Track> onDisk,
  String artist,
  List<(String, List<ChoiceTrack>)> others, {
  /// De titel van de PLAAT. Gaat mee zodat "heb ik dit al?" met dezelfde ogen kijkt als de
  /// tracklijst erboven — zonder dit zou een bestand als "Take On Me (MTV Unplugged)" als bonus
  /// worden aangeboden terwijl het er gewoon staat.
  ///
  /// Benoemd en met een standaardwaarde, net als bij [matchAlbumTracks]: als positionele parameter
  /// brak dit in één klap zes aanroepen in `completeness_test.dart`, en dat is precies het soort
  /// wijziging dat een bestaande aanroeper stil iets anders had laten doen als Dart het had
  /// toegelaten.
  String album = '',
}) {
  final out = <BonusTrack>[];
  for (final (edition, tracks) in others) {
    // "Do I have this?" is asked by running the pressing through the ordinary matcher, so a bonus
    // is judged by exactly the same three passes as the tracklist above it. Titles alone were not
    // enough: the radio edit carries its marker in the FILENAME and not in the tag, so on titles
    // it read as a track the user didn't have — and was offered back to them.
    final c = matchAlbumTracks(tracks, onDisk, artist, album: album);
    for (final s in c.slots) {
      if (s.index < 0 || !s.missing) continue;
      final t = s.official!;
      if (t.title.trim().isEmpty) continue;
      bool same(ChoiceTrack o) =>
          sameTitle(o.title, t.title, secondsA: o.seconds, secondsB: t.seconds);
      if (mine.any(same) || out.any((b) => same(b.track))) continue;
      out.add(BonusTrack(t, edition));
    }
  }
  return out;
}

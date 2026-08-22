/// What we found out about a record, kept instead of found out again.
///
/// Opening an album page costs up to six MusicBrainz requests at 1.1 s apart — search the release
/// group, list its pressings, fetch a tracklist for each of the shortlisted ones, score them. The
/// answer then lived in a `State` field and was thrown away when the page closed, so the next visit
/// paid for it again, and every device in the house paid separately. On top of that a refusal was
/// never remembered at all: one 503 and the whole chain was retried at every open, forever.
///
/// So the OUTCOME gets stored: which pressing this is, what the label pressed, what is missing, what
/// the other pressings have. Worked out once on the PC, handed to every device, and re-derived only
/// when the album's own files change or the user asks.
///
/// Two places, on purpose:
///
/// * **the index** — one file in the app folder, and the only thing read at startup. Twelve thousand
///   little files would be slower to open than the thing it is trying to speed up.
/// * **the sidecar** — a small JSON in the album's own folder. Move the folder and its metadata goes
///   with it; reinstall, or set the app up on another machine, and nothing is lost. Written through,
///   never read on the hot path.
///
/// Conflict rule, deliberately blunt: **in the index, the index wins; not in the index, read the
/// sidecar.** Because every write goes to both, the index cannot be behind on the machine that
/// wrote it — and comparing timestamps across machines is a clock-skew bug waiting to be written.
///
/// These are facts, not corrections. Everything here can be thrown away and fetched again;
/// `corrections.json` cannot, which is why the two are kept apart.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'completeness.dart';
import 'editions.dart';
import 'models.dart';
import 'mojibake.dart';
import 'warm_log.dart';

/// Bumped when the shape below changes in a way that makes stored answers wrong. Everything with an
/// older number is re-derived on sight — the same trick as `ArtistArt.schema` and the `v5` in the
/// Discogs art key, because nothing here expires on its own.
const int kAlbumFactsSchema = 1;

/// Bumped whenever the AUDIO path changes in a way that could turn a "nothing found" into an answer.
///
/// Every record whose lookup came back empty under an older number gets one more turn — see
/// [AlbumFacts.heardVersion]. Deliberately separate from [kAlbumFactsSchema]: that one invalidates
/// stored ANSWERS, this one only re-opens stored FAILURES, which is far cheaper and is the only
/// thing a repair to the fingerprint path actually needs.
///
/// 1 — first release. AcoustID was asked with `meta=recordings+releasegroupids`, a literal plus,
///     which the server reads as one unknown word. Every lookup matched and returned no metadata.
/// 2 — the plus became a space.
const int kSoundVersion = 2;

/// The name of the file dropped next to an album's music.
const String kSidecarName = '.debridmusic-album.json';

/// Everything worth remembering about one record.
@immutable
class AlbumFacts {
  const AlbumFacts({
    required this.uid,
    required this.trackSetHash,
    this.schema = kAlbumFactsSchema,
    this.updatedMs = 0,
    this.source = '',
    this.mbid,
    this.discogsRelease,
    this.bestFit = true,
    this.tracklist = const [],
    this.bonus = const [],
    this.year,
    this.failedMs,
    this.networkFailed = false,
    this.heardVersion = 0,
  });

  /// The album this belongs to — see album_id.dart. Not artist+title, precisely so that correcting
  /// either does not throw this away.
  final String uid;

  /// Which files this was worked out FROM, so a record that gained or lost a track knows to ask
  /// again. Only the filenames: moving the folder is not a change to the record.
  final String trackSetHash;

  final int schema;
  final int updatedMs;

  /// `MusicBrainz`, `Discogs`, or empty when nothing answered.
  final String source;

  /// The pressing this describes. Handed to the artwork so the sleeve, the back and the disc come
  /// from the same pressing as the tracklist.
  final String? mbid;
  final int? discogsRelease;

  /// Did the chosen pressing name every track on disk? When it did not, the page says so instead of
  /// presenting a near miss as the record.
  final bool bestFit;

  /// What the label pressed, and what the OTHER pressings have that this one does not.
  final List<ChoiceTrack> tracklist;
  final List<BonusTrack> bonus;

  /// When the record came out — not when this pressing did.
  final int? year;

  /// When the lookup last came back with nothing. The missing half of the old cache: without it a
  /// server that was down for an hour cost six requests per album open for the rest of time.
  final int? failedMs;

  /// Did the lookup BREAK, rather than answer "never heard of this record"?
  ///
  /// Deliberately not written to disk and not read back: it describes one attempt, not the record.
  /// The warmer's outage guard is the only thing that reads it, and it is what stops eleven obscure
  /// albums in a row from being mistaken for a dead network — which used to freeze the sweep at
  /// fifteen of twenty-six on every run.
  final bool networkFailed;

  /// WHICH version of the audio path has been asked about this record. 0 = none.
  ///
  /// Written to disk, unlike [networkFailed], because it describes what has been TRIED and that
  /// outlives the attempt. It began as a bool, and the bool was not enough — the story is worth
  /// keeping because it is the whole reason this is a number.
  ///
  /// A record neither catalogue can name is stamped with [failedMs] and goes blind for a day. So on
  /// the evening fingerprinting shipped, the eight compilations it was built for were not in the
  /// sweep's to-do list at all: they had failed hours earlier, by title, before there was anything
  /// else to ask. Hence "one fresh attempt once we can listen".
  ///
  /// But that attempt was then spent by a build whose lookup was broken — a plus where AcoustID
  /// wanted a space — and the flag recorded "we listened" for a run that could not hear. The fix
  /// shipped and the records it was for were locked out for a day.
  ///
  /// A version fixes both halves: repairing the audio path earns every stuck record one more turn,
  /// and a record that has already had THIS version's attempt is left alone. The same trick as
  /// [kAlbumFactsSchema] and the `v6` in the artwork key.
  final int heardVersion;

  bool get isEmpty => tracklist.isEmpty;

  /// Has the album itself changed under these facts?
  bool staleFor(String hash) => schema != kAlbumFactsSchema || trackSetHash != hash;

  /// Should a failed lookup be attempted again?
  ///
  /// A day, because the reasons it failed are slow-moving: MusicBrainz does not have the record, or
  /// it was down. Retrying every time the page opens is what made this hurt in the first place.
  bool retryDue(int nowMs) {
    final f = failedMs;
    if (f == null) return false;
    return nowMs - f > const Duration(hours: 24).inMilliseconds;
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'schema': schema,
        'hash': trackSetHash,
        'updatedMs': updatedMs,
        if (source.isNotEmpty) 'source': source,
        if (mbid != null) 'mbid': mbid,
        if (discogsRelease != null) 'release': discogsRelease,
        if (!bestFit) 'bestFit': false,
        if (year != null) 'year': year,
        if (failedMs != null) 'failedMs': failedMs,
        if (heardVersion > 0) 'heard': heardVersion,
        if (tracklist.isNotEmpty)
          'tracks': [
            for (final t in tracklist)
              {'p': t.position, 't': t.title, if (t.seconds != null) 's': t.seconds, 'd': t.disc},
          ],
        if (bonus.isNotEmpty)
          'bonus': [
            for (final b in bonus)
              {
                'e': b.edition,
                'p': b.track.position,
                't': b.track.title,
                if (b.track.seconds != null) 's': b.track.seconds,
                'd': b.track.disc,
              },
          ],
      };

  static AlbumFacts? fromJson(Map<String, dynamic> j) {
    final uid = (j['uid'] ?? '').toString();
    if (uid.isEmpty) return null;
    // Titels komen hier van schijf, en op schijf staat 124 keer een dubbel gecodeerde apostrof of
    // accentletter -- geschreven door een build die er niet meer is, terwijl de caches van
    // MusicBrainz en Discogs schoon zijn. Bij het inlezen rechtzetten is de goedkoopste weg: het
    // hoeft niet opnieuw over de lijn, en de eerstvolgende bewaring schrijft de nette tekst terug.
    ChoiceTrack track(Map m) => ChoiceTrack(
          (m['p'] ?? '').toString(),
          unmojibake((m['t'] ?? '').toString()),
          (m['s'] as num?)?.toInt(),
          disc: (m['d'] as num?)?.toInt() ?? 1,
        );
    return AlbumFacts(
      uid: uid,
      schema: (j['schema'] as num?)?.toInt() ?? 0,
      trackSetHash: (j['hash'] ?? '').toString(),
      updatedMs: (j['updatedMs'] as num?)?.toInt() ?? 0,
      source: (j['source'] ?? '').toString(),
      mbid: j['mbid']?.toString(),
      discogsRelease: (j['release'] as num?)?.toInt(),
      bestFit: j['bestFit'] != false,
      year: (j['year'] as num?)?.toInt(),
      failedMs: (j['failedMs'] as num?)?.toInt(),
      // `true` is what the one build that wrote a bool put there. It means "version 1 was tried",
      // and version 1 is exactly the broken one, so reading it as 1 gives those records their turn.
      heardVersion: j['heard'] == true ? 1 : (j['heard'] as num?)?.toInt() ?? 0,
      tracklist: [
        for (final t in (j['tracks'] as List? ?? const []))
          if (t is Map) track(t),
      ],
      bonus: [
        // Ook de uitgaveregel, en dat was het gat in de eerste versie hiervan: die staat op het
        // scherm onder "Op andere uitgaves" als "CD-R · US · 2022", en het middenpunt daarin was
        // net zo dubbel gecodeerd als de apostrofs in de titels. Op schijf gemeten: 124 verminkte
        // titels weg en toen nog steeds tien "Â·" over, allemaal in dit veld.
        for (final b in (j['bonus'] as List? ?? const []))
          if (b is Map) BonusTrack(track(b), unmojibake((b['e'] ?? '').toString())),
      ],
    );
  }
}

/// Do we have to go and ask, or is what we already know good enough?
///
/// The whole point of this file in one function, so it can be reasoned about and tested rather than
/// living inside a widget's `initState`. Four reasons to ask:
///
/// * nothing is known yet
/// * the album's own files changed, so the answer was about a different record
/// * the user pinned a different pressing — no file changed, but the answer did
/// * the last attempt found nothing and has had a day to think about it
///
/// Everything else is answered from memory, with no spinner and no request. That is the difference
/// between an album page that opens instantly and one that costs six seconds every visit.
bool needsResolve(
  AlbumFacts? known, {
  required String trackSetHash,
  required int nowMs,
  String? pinnedMbid,
  int? pinned,
  bool force = false,
  bool canHear = false,
}) {
  if (force || known == null) return true;
  if (known.staleFor(trackSetHash)) return true;
  // A record that failed BEFORE the audio could be asked gets one more turn, without waiting out the
  // day the miss cache would otherwise impose.
  //
  // Measured, the evening fingerprinting shipped: the eight compilations it was built for had all
  // failed hours earlier by title, so they carried failedMs and the sweep's to-do list came back
  // "25 te doen van 132" — with not one of the eight in it. The feature could not have been tried
  // until the next day. [AlbumFacts.heardVersion] makes that one attempt per version of the audio
  // path — so repairing that path earns a turn, and repeating the same version does not.
  if (canHear && known.isEmpty && known.heardVersion < kSoundVersion) return true;
  // A pin the stored answer does not already describe. Picking a pressing changes no file at all,
  // so the hash above cannot see it — and serving the tracklist of the pressing someone just
  // replaced is the one staleness they would certainly notice.
  if (pinnedMbid != null && pinnedMbid.isNotEmpty && known.mbid != pinnedMbid) return true;
  // Idem voor een vastgezette Discogs-persing — maar mét een rem erop.
  //
  // Deze regel stond er kaal, en dat was de helft van een lus. De oplosser vroeg Discogs alleen als
  // MusicBrainz niets wist, dus bij een plaat die MusicBrainz wél kent werd de pin nooit gehaald en
  // bleef `discogsRelease` leeg — waarop deze regel altijd waar bleef. Elke sweep van de warmer nam
  // dat album opnieuw, en schreef er telkens de zelfgekozen persing overheen.
  //
  // De oplosser honoreert de pin nu wel (zie `resolveAlbumFacts`), en stempelt `failedMs` als het
  // niet lukte. Blijft die pin dus onhaalbaar — een verwijderde release, een token dat weg is — dan
  // is het één poging per dag in plaats van elke ronde.
  if (pinned != null && pinned > 0 && known.discogsRelease != pinned) {
    return known.failedMs == null || known.retryDue(nowMs);
  }
  if (known.isEmpty && known.retryDue(nowMs)) return true;
  return false;
}

/// Which files a record is made of, as one short string.
///
/// Filenames only. Moving the whole folder somewhere tidier does not change what the record IS, and
/// re-deriving six requests' worth of answer because a path changed would defeat the point.
String trackSetHashOf(Iterable<Track> tracks) {
  final names = [for (final t in tracks) _baseName(t.path)]..sort();
  var h = 0x811c9dc5;
  for (final n in names) {
    for (final c in n.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    h ^= 0x2f; // a separator, so ["ab","c"] and ["a","bc"] are not the same record
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return '${names.length}-${h.toRadixString(16)}';
}

String _baseName(String path) {
  final i = path.lastIndexOf(RegExp(r'[\\/]'));
  return i < 0 ? path : path.substring(i + 1);
}

/// Where an album's sidecar goes, or null when there is no sensible place for one.
///
/// The tidy tree is `Albums/<artist>/<album>/`, so the ordinary answer is simply "the folder the
/// tracks are in". A scanned library is not always tidy, hence the two refusals:
///
/// * tracks scattered over several folders — no folder is the record's
/// * a folder holding more than one album, i.e. a flat dump — several albums would fight over one
///   filename, and each would overwrite the last
///
/// Both cases fall back to index-only, which loses portability for those albums and nothing else.
String? albumFolderOf(Album a, Map<String, int> albumsPerDir) {
  if (a.tracks.isEmpty) return null;
  final tally = <String, int>{};
  for (final t in a.tracks) {
    final d = _dirName(t.path);
    if (d.isEmpty) continue;
    tally[d] = (tally[d] ?? 0) + 1;
  }
  if (tally.isEmpty) return null;
  final best = tally.entries.reduce((x, y) => y.value > x.value ? y : x);
  if (best.value * 5 < a.tracks.length * 4) return null; // under four fifths: not one folder
  if ((albumsPerDir[best.key] ?? 1) > 1) return null; // a shared folder
  return best.key;
}

String _dirName(String path) {
  final i = path.lastIndexOf(RegExp(r'[\\/]'));
  return i <= 0 ? '' : path.substring(0, i);
}

/// How many albums have a track in each folder. Computed once per regroup; [albumFolderOf] needs it
/// to recognise a flat dump.
Map<String, int> albumsPerDirOf(Iterable<Album> albums) {
  final out = <String, int>{};
  for (final a in albums) {
    final seen = <String>{};
    for (final t in a.tracks) {
      final d = _dirName(t.path);
      if (d.isEmpty || !seen.add(d)) continue;
      out[d] = (out[d] ?? 0) + 1;
    }
  }
  return out;
}

/// The index, plus write-through to the sidecars.
class AlbumFactsStore extends ChangeNotifier {
  AlbumFactsStore({required this.dir});

  /// The app's own folder. A callback for the same reason as in album_id.dart — a test redirects it
  /// after construction.
  final String Function() dir;

  final Map<String, AlbumFacts> _byUid = {};

  /// uid → the folder its sidecar belongs in, remembered from the last [put].
  final Map<String, String> _folders = {};

  /// Once a write next to the music has failed, stop trying for this session. A read-only mount or
  /// a network share that has gone away must not produce an exception per album.
  bool sidecarsWritable = true;

  Timer? _save;
  bool _dirty = false;
  final _queue = <String>[];
  bool _draining = false;

  File get _indexFile => File('${dir()}${Platform.pathSeparator}album_facts.json');

  int get count => _byUid.length;

  AlbumFacts? get(String uid) => uid.isEmpty ? null : _byUid[uid];

  /// Record what was found. In memory immediately — the page is drawn from this — with the disk
  /// following behind.
  void put(AlbumFacts f, {String? folder}) {
    _byUid[f.uid] = f;
    if (folder != null && folder.isNotEmpty) _folders[f.uid] = folder;
    _dirty = true;
    _scheduleSave();
    if (_folders.containsKey(f.uid) && sidecarsWritable) {
      _queue.add(f.uid);
      unawaited(_drainSidecars());
    }
    notifyListeners();
  }

  /// Drop what is known about an album, so the next look re-derives it.
  void forget(String uid) {
    if (_byUid.remove(uid) == null) return;
    _dirty = true;
    _scheduleSave();
    notifyListeners();
  }

  /// Vergeet wat bij geen enkel album meer hoort. Geeft terug hoeveel er weg ging.
  ///
  /// **Waarom dit er moest komen.** Er ging nooit iets uit: [forget] had in de hele repo geen enkele
  /// aanroeper. Gemeten op 10-08-2026 stond `album_facts.json` op 9,9 MB met ruim 7000 regels — voor
  /// een bibliotheek van 236 albums. Dat bestand wordt bij élke start in één keer geparsed op de
  /// UI-isolate, dus die wezen kostten jank bij het opstarten en verder niets.
  ///
  /// Dat het zo uit de hand liep had één oorzaak: [AlbumUids.prune] vergeleek paden met de verkeerde
  /// schrijfwijze en gooide daardoor bij élke scan het hele pad→uid-register leeg, waarna elke
  /// regroep 236 verse uids muntte. Zie [padSleutel]. **Deze opruimer mag dus pas draaien nu die
  /// reparatie erin zit** — daarvóór had hij precies weggegooid wat je wilde houden.
  ///
  /// Dezelfde veiligheidsklep als bij `corrections.json` en [AlbumUids.prune]: een LEGE verzameling
  /// betekent "ik weet het niet" (de schijf hing er niet, de scan mislukte) en dan gaat er niets weg.
  int prune(Set<String> levendeUids) {
    if (levendeUids.isEmpty) return 0;
    final dood = [for (final u in _byUid.keys) if (!levendeUids.contains(u)) u];
    if (dood.isEmpty) return 0;
    for (final u in dood) {
      _byUid.remove(u);
      _folders.remove(u);
    }
    _dirty = true;
    _scheduleSave();
    return dood.length;
  }

  /// The one read on the startup path.
  Future<void> load() async {
    try {
      if (!await _indexFile.exists()) return;
      final j = jsonDecode(await _indexFile.readAsString());
      if (j is! Map) return;
      _byUid.clear();
      _folders.clear();
      for (final e in (j['facts'] as Map?)?.entries ?? const <MapEntry>[]) {
        if (e.value is! Map) continue;
        final f = AlbumFacts.fromJson(Map<String, dynamic>.from(e.value as Map));
        // A record from an older schema is not read back — it would be shown before being
        // re-derived, and showing a wrong tracklist is worse than showing none.
        if (f != null && f.schema == kAlbumFactsSchema) _byUid[f.uid] = f;
      }
      for (final e in (j['folders'] as Map?)?.entries ?? const <MapEntry>[]) {
        _folders['${e.key}'] = '${e.value}';
      }
      // Eén regel, en hij is de reden dat de reparatie geen pleister is: bij oude data loopt dit
      // getal één keer op en blijft het daarna nul. Blijft het terugkomen, dan schrijft iets nog
      // steeds verminkte tekst weg en is er een echte bron te zoeken.
      //
      // In warm.log en niet via debugPrint, want een release-build gooit debugPrint weg -- en een
      // teller die niemand kan lezen bewijst niets. Precies de les die dat logboek zelf al opschreef.
      if (mojibakeHersteld > 0) {
        WarmLog('${dir()}${Platform.pathSeparator}warm.log')
            .line('feiten: $mojibakeHersteld dubbel gecodeerde teksten rechtgezet bij het inlezen');
        _dirty = true;
        _scheduleSave();
      }
    } catch (e) {
      debugPrint('album_facts.json unusable, starting empty: $e');
    }
  }

  /// Adopt a sidecar for an album the index has never heard of — a folder copied in from elsewhere,
  /// or a fresh install over an existing library. Returns what it found, if anything.
  Future<AlbumFacts?> adoptSidecar(String uid, String folder, String trackSetHash) async {
    if (_byUid.containsKey(uid)) return null; // the index wins
    try {
      final f = File('$folder${Platform.pathSeparator}$kSidecarName');
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return null;
      // The uid in the file is whichever machine wrote it; this library has its own name for the
      // record, and that is the one the rest of the app will ask for.
      final found = AlbumFacts.fromJson({...Map<String, dynamic>.from(j), 'uid': uid});
      if (found == null || found.schema != kAlbumFactsSchema) return null;
      if (found.staleFor(trackSetHash)) return null;
      _byUid[uid] = found;
      _folders[uid] = folder;
      _dirty = true;
      _scheduleSave();
      return found;
    } catch (_) {
      return null;
    }
  }

  void _scheduleSave() {
    _save?.cancel();
    _save = Timer(const Duration(seconds: 2), () => unawaited(flush()));
  }

  /// Write the index. Temp file then rename, so a crash mid-write cannot leave something
  /// half-parsed — which would mean re-deriving the whole library.
  Future<void> flush() async {
    if (!_dirty) return;
    _dirty = false;
    _save?.cancel();
    _save = null;
    try {
      await Directory(dir()).create(recursive: true);
      final tmp = File('${_indexFile.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'facts': {for (final e in _byUid.entries) e.key: e.value.toJson()},
        'folders': _folders,
      }));
      await tmp.rename(_indexFile.path);
    } catch (e) {
      debugPrint('album_facts.json not written: $e');
    }
  }

  /// One sidecar per turn of the event loop. Correcting ten albums in a row should not stall the UI
  /// behind ten writes into the music tree, which may well be a network share.
  Future<void> _drainSidecars() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty && sidecarsWritable) {
        final uid = _queue.removeAt(0);
        final folder = _folders[uid];
        final facts = _byUid[uid];
        if (folder == null || facts == null) continue;
        try {
          final f = File('$folder${Platform.pathSeparator}$kSidecarName');
          await f.writeAsString(jsonEncode(facts.toJson()));
        } on FileSystemException catch (e) {
          // Read-only mount, a share that went away, a permission the user never granted. Not an
          // error worth a dialog: the index still has everything, only portability is lost.
          debugPrint('Sidecar not written to $folder: ${e.osError?.message ?? e.message}');
          sidecarsWritable = false;
        } catch (_) {}
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _draining = false;
    }
  }

  @override
  void dispose() {
    _save?.cancel();
    _save = null;
    super.dispose();
  }
}

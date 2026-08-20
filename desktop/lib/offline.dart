/// Music kept on this device, for when the PC is not there.
///
/// A copy, not a second library. The PC still owns the files, the tags and the grouping — this
/// holds bytes and an index of which library path they belong to, so that everything upstream keeps
/// working from the catalogue the PC serves. Nothing here decides what an album IS.
///
/// The whole point sits in one place: [localFor]. Playback in this app goes through exactly one
/// choke point, [PlayerStore.mediaResolver], so "play the copy if we have it, otherwise stream"
/// is a single decision rather than a branch in every screen.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'paths.dart';

/// One track that lives on this device.
class OfflineTrack {
  const OfflineTrack({
    required this.path,
    required this.file,
    required this.bytes,
    required this.title,
    required this.artist,
    required this.album,
    required this.savedAt,
  });

  /// The library path, exactly as the PC's catalogue gives it. The key to everything: it is what
  /// [Track.path] holds, so a lookup needs no matching on titles.
  final String path;

  /// Where the bytes are on this device.
  final String file;

  final int bytes;
  final String title;
  final String artist;
  final String album;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
        'path': path,
        'file': file,
        'bytes': bytes,
        'title': title,
        'artist': artist,
        'album': album,
        'savedAt': savedAt.toUtc().toIso8601String(),
      };

  static OfflineTrack? fromJson(Map<String, dynamic> j) {
    final path = (j['path'] ?? '').toString();
    final file = (j['file'] ?? '').toString();
    if (path.isEmpty || file.isEmpty) return null;
    return OfflineTrack(
      path: path,
      file: file,
      bytes: (j['bytes'] as num?)?.toInt() ?? 0,
      title: (j['title'] ?? '').toString(),
      artist: (j['artist'] ?? '').toString(),
      album: (j['album'] ?? '').toString(),
      savedAt: DateTime.tryParse((j['savedAt'] ?? '').toString()) ?? DateTime(1970),
    );
  }
}

/// A download in flight, so a screen can show it moving.
class OfflineJob {
  OfflineJob(this.verzoek);

  /// Wat er gevraagd is. Blijft bewaard nadat het misging, want anders valt er niets opnieuw te
  /// proberen zonder dat het scherm het adres en de tokens opnieuw moet bouwen.
  final OfflineRequest verzoek;

  String get path => verzoek.libraryPath;
  String get title => verzoek.title;

  /// 0..1, or null while the server has not said how big the file is.
  double? progress;

  /// Waarom het misging, in gewone taal. Zolang dit gevuld is blijft de taak STAAN — dat is het
  /// hele verschil met vroeger, toen hij op hetzelfde moment werd weggegooid en er dus nooit
  /// iemand achter kwam. Zie [OfflineStore.download].
  String? error;
  bool done = false;

  /// Hoeveel bytes er al staan, en hoeveel het er worden. Voor "1,2 van 4,7 GB" — bij een bestand
  /// van gigabytes is een percentage alleen te weinig om te zien of er iets beweegt.
  int gedaan = 0;
  int totaal = 0;

  /// Staat dit nummer nog in de rij, of loopt het al?
  ///
  /// Het verschil hoort op het scherm: een wieltje dat draait voor iets wat nog niet begonnen is
  /// leest als een download die vastzit.
  bool wacht = false;

  /// Loopt hij nu echt? Een mislukte taak staat er nog, maar doet niets.
  bool get bezig => error == null;
}

/// Eén nummer dat opgehaald moet worden, met alles wat [OfflineStore.download] ervoor nodig heeft.
///
/// Bestaat omdat een album als GEHEEL wordt gevraagd. Zonder zoiets moest de aanvrager de nummers
/// zelf één voor één afwachten, en dat is precies waar het misging: die lus stond in de knop op de
/// albumpagina en stopte zodra je die pagina verliet.
class OfflineRequest {
  const OfflineRequest({
    required this.libraryPath,
    required this.url,
    required this.title,
    required this.artist,
    required this.album,
  });

  final String libraryPath;
  final String url;
  final String title;
  final String artist;
  final String album;
}

/// What this device is holding, and what is on its way.
class OfflineStore extends ChangeNotifier {
  OfflineStore({http.Client? client, this.stilte = const Duration(seconds: 45)})
      : _http = client ?? http.Client();

  final http.Client _http;

  /// Hoe lang er niets mag binnenkomen voordat het ophalen opgegeven wordt.
  ///
  /// **Zonder deze grens hangt het voor altijd.** Een telefoon die van wifi naar 4G springt, of een
  /// pc die in slaap valt, laat de verbinding open staan zonder ooit nog een byte te sturen: geen
  /// fout, geen einde. `await for (chunk in res.stream)` wacht dan tot het einde der tijden, de taak
  /// blijft in [_jobs] staan, en de knop op de albumpagina blijft "Ophalen 0/1" melden — uitgezet,
  /// dus zelfs opnieuw proberen kan niet meer. Dat is precies wat er gemeld werd.
  ///
  /// Vijfenveertig seconden: ruim genoeg voor een pc die een groot bestand van een trage schijf
  /// moet opzoeken, kort genoeg om niet naar een balk te staren die nooit meer beweegt.
  final Duration stilte;

  final Map<String, OfflineTrack> _tracks = {};
  final Map<String, OfflineJob> _jobs = {};

  /// Cancelled by [remove] and by [clear], so a download that is deleted mid-flight stops writing.
  final Set<String> _cancelled = {};

  bool _loaded = false;

  List<OfflineTrack> get tracks {
    final all = _tracks.values.toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return all;
  }

  /// Alles wat loopt, wacht, of misging. Mislukte taken staan er bewust nog bij.
  List<OfflineJob> get jobs => _jobs.values.toList();

  int get bytes => _tracks.values.fold(0, (sum, t) => sum + t.bytes);

  bool has(String path) => _tracks.containsKey(path);

  /// Loopt of wacht dit nummer? **Een mislukte taak is niet bezig.** Anders blijft de knop die
  /// hierop afgaat uitgezet staan en is opnieuw proberen onmogelijk.
  bool isBusy(String path) => _jobs[path]?.bezig ?? false;

  /// Waarom het misging, of null. Wat hier uit komt is bedoeld om op het scherm te zetten.
  String? foutVoor(String path) => _jobs[path]?.error;

  /// De taak van dit nummer, of null. Voor een scherm dat wil laten zien hoever hij is.
  OfflineJob? taakVoor(String path) => _jobs[path];

  /// Nog eens proberen, met wat er al binnen is als beginpunt.
  void opnieuw(String path) {
    final job = _jobs[path];
    if (job == null || job.bezig) return;
    bewaarAlles([job.verzoek]);
  }

  /// Nummers die nog opgehaald moeten worden, in de volgorde waarin ze gevraagd zijn.
  ///
  /// **Waarom deze rij hier staat en niet in de knop.** Een album werd opgehaald door een lus in
  /// `_OfflineAlbumButtonState`, met `if (!mounted) return;` per nummer. Verliet je de albumpagina,
  /// dan viel die lus stil: gemeten op 17-08-2026 met Discovery (14 nummers) — tikken, vier
  /// seconden later terug naar de lijst, en er stonden er 3 op het toestel. Geen melding, geen
  /// mislukte download, niets in de lijst. Later in de auto zijn dat elf nummers die er niet zijn.
  ///
  /// Een winkel leeft langer dan een scherm, dus hier hoort het thuis.
  final List<OfflineRequest> _wachtrij = [];
  bool _pompt = false;

  /// Hoeveel er nog te gaan zijn, voor een scherm dat dat wil zeggen.
  int get wachtend => _wachtrij.length;

  /// Hoeveel er misgingen en nog op een tweede poging wachten.
  int get mislukt => _jobs.values.where((j) => !j.bezig).length;

  /// Zet deze nummers op het toestel. Keert meteen terug; het ophalen loopt door.
  ///
  /// Eén tegelijk, net als voorheen: een telefoonradio wordt er niet sneller van om vijf bestanden
  /// van honderd megabyte door elkaar te trekken, en zo blijft de volgorde die van de plaat.
  void bewaarAlles(Iterable<OfflineRequest> items) {
    var toegevoegd = 0;
    for (final r in items) {
      if (_tracks.containsKey(r.libraryPath)) continue;
      // Wat al loopt of nog wacht laten we met rust. Wat MISGING mag wel opnieuw — dat is de hele
      // bedoeling van een tweede keer tikken, en de vorige versie sloeg het stilletjes over.
      final loopt = _jobs[r.libraryPath];
      if (loopt != null && loopt.bezig) continue;
      _jobs[r.libraryPath] = OfflineJob(r)..wacht = true;
      _wachtrij.add(r);
      toegevoegd++;
    }
    if (toegevoegd == 0) return;
    notifyListeners();
    unawaited(_pomp());
  }

  Future<void> _pomp() async {
    if (_pompt) return;
    _pompt = true;
    try {
      while (_wachtrij.isNotEmpty) {
        final r = _wachtrij.removeAt(0);
        // Nooit gooien: één nummer dat niet lukt mag de rest van de plaat niet meenemen.
        await download(
          libraryPath: r.libraryPath,
          url: r.url,
          title: r.title,
          artist: r.artist,
          album: r.album,
        );
      }
    } finally {
      _pompt = false;
    }
  }

  /// The file on this device for a library path, or null.
  ///
  /// Checks the disk rather than trusting the index: a copy can be gone — Android reclaims an
  /// app's files under storage pressure without telling anybody — and handing libmpv a path to
  /// nothing produces a track that simply refuses to play, with no way to tell why.
  String? localFor(String libraryPath) {
    final t = _tracks[libraryPath];
    if (t == null) return null;
    if (!File(t.file).existsSync()) {
      _tracks.remove(libraryPath);
      unawaited(_save());
      return null;
    }
    return t.file;
  }

  Directory get _dir => appSubdir('offline');
  File get _index => appFile('offline.json');

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = _index;
      if (!await f.exists()) return;
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is! List) return;
      for (final e in decoded) {
        if (e is! Map<String, dynamic>) continue;
        final t = OfflineTrack.fromJson(e);
        if (t != null) _tracks[t.path] = t;
      }
      notifyListeners();
    } catch (e) {
      // An unreadable index is an empty one. The bytes are still there and will simply be fetched
      // again; losing the index must never lose the ability to play from the PC.
      debugPrint('Offline index unreadable: $e');
    }
  }

  Future<void> _save() async {
    try {
      await _index.writeAsString(jsonEncode([for (final t in _tracks.values) t.toJson()]));
    } catch (e) {
      debugPrint('Offline index not saved: $e');
    }
  }

  /// Where a track's bytes go.
  ///
  /// Named from a hash of the library path, not from the title. Titles carry slashes, colons and
  /// characters Android's filesystem refuses, and two pressings of one album share a title — the
  /// path is already unique and the index knows what it means.
  File _fileFor(String libraryPath, String extension) {
    final digest = sha1.convert(utf8.encode(libraryPath)).toString().substring(0, 16);
    final ext = extension.isEmpty ? 'bin' : extension;
    return File('${_dir.path}${Platform.pathSeparator}$digest.$ext');
  }

  /// The extension is what tells a player the format — libmpv and AVFoundation both sniff it
  /// before reading a byte — so it is taken from the library path rather than invented.
  static String _extVan(String libraryPath) {
    final dot = libraryPath.lastIndexOf('.');
    return dot > 0 && dot > libraryPath.length - 6 ? libraryPath.substring(dot + 1) : 'flac';
  }

  File _deelFor(String libraryPath) =>
      File('${_fileFor(libraryPath, _extVan(libraryPath)).path}.part');

  /// Naast het halve bestand: hoe groot het hele hoort te worden.
  ///
  /// Zonder dit is verdergaan gevaarlijk. Een half bestand van gisteren zegt niets over het bestand
  /// dat er vandaag onder dat pad staat; wordt de plaat op de pc vervangen, dan zou verdergaan twee
  /// helften van twee verschillende bestanden aan elkaar plakken. Dat speelt af als ruis, en niets
  /// meldt dat er iets mis is. De maat vergelijken vangt precies dat geval.
  File _stempelFor(String libraryPath) =>
      File('${_fileFor(libraryPath, _extVan(libraryPath)).path}.part.json');

  Future<void> _gooiDeelWeg(String libraryPath) async {
    for (final f in [_deelFor(libraryPath), _stempelFor(libraryPath)]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {/* niets op te ruimen */}
    }
  }

  /// Hoeveel bytes er bruikbaar klaarstaan van een eerdere poging, en hoe groot het geheel hoorde
  /// te worden. Zonder stempel is een half bestand onbruikbaar en gaat het weg.
  Future<({int al, int verwacht})> _deelVan(String libraryPath) async {
    final deel = _deelFor(libraryPath);
    if (!await deel.exists()) return (al: 0, verwacht: 0);
    var verwacht = 0;
    try {
      final j = jsonDecode(await _stempelFor(libraryPath).readAsString());
      if (j is Map && j['totaal'] is num) verwacht = (j['totaal'] as num).toInt();
    } catch (_) {/* geen of onleesbare stempel */}
    if (verwacht <= 0) {
      await _gooiDeelWeg(libraryPath);
      return (al: 0, verwacht: 0);
    }
    return (al: await deel.length(), verwacht: verwacht);
  }

  /// Wat er misging, in woorden waar iemand iets aan heeft.
  ///
  /// `SocketException: Connection reset by peer (OS Error: ...errno = 104)` staat op een telefoon
  /// even ver van de gebruiker af als niets zeggen.
  static String _leesbaar(Object e) {
    final tekst = '$e';
    if (e is TimeoutException) return 'de verbinding viel stil';
    if (tekst.contains('No space left') || tekst.contains('ENOSPC')) {
      return 'geen ruimte meer op dit toestel';
    }
    if (e is SocketException) return 'geen verbinding met de pc';
    if (tekst.contains('HTTP 401') || tekst.contains('HTTP 403')) {
      return 'de pc weigerde de sleutel — opnieuw koppelen';
    }
    if (tekst.contains('HTTP 404')) return 'de pc kent dit bestand niet meer';
    if (e is HttpException) return e.message;
    return tekst;
  }

  /// De volle grootte van het bestand, ook als er maar een stuk gevraagd is.
  static int _geheelUit(http.StreamedResponse res, int al) {
    final cr = res.headers['content-range'];
    if (cr != null) {
      final m = RegExp(r'/(\d+)\s*$').firstMatch(cr);
      if (m != null) return int.parse(m.group(1)!);
    }
    final len = res.contentLength;
    return len == null ? 0 : len + al;
  }

  /// Fetch one track onto this device.
  ///
  /// [url] is the authorised stream URL — this class deliberately knows nothing about tokens or
  /// which PC is which; the caller already has a [RemoteClient] that does.
  Future<bool> download({
    required String libraryPath,
    required String url,
    required String title,
    required String artist,
    required String album,
  }) async {
    if (_tracks.containsKey(libraryPath)) return true;

    // Een taak die al WACHT is er eentje uit [_wachtrij] en wordt hier overgenomen; een taak die al
    // LOOPT is een tweede klik op hetzelfde nummer en hoort niets te doen. Een taak die MISLUKTE
    // staat er nog en mag wél opnieuw.
    final bestaand = _jobs[libraryPath];
    if (bestaand != null && !bestaand.wacht && bestaand.bezig) return true;

    final verzoek = OfflineRequest(
      libraryPath: libraryPath,
      url: url,
      title: title,
      artist: artist,
      album: album,
    );
    final job = bestaand ?? OfflineJob(verzoek);
    job
      ..wacht = false
      ..error = null;
    _jobs[libraryPath] = job;
    _cancelled.remove(libraryPath);
    notifyListeners();

    final target = _fileFor(libraryPath, _extVan(libraryPath));
    final temp = _deelFor(libraryPath);

    // Held outside the try so the failure path can close it. A connection that drops mid-stream
    // makes `res.stream` throw, which skips the close below — and Windows refuses to delete a file
    // that is still open, so the .part survived and the next attempt found a name it thought it
    // already had. On a Mac the same code passes: unlink does not mind an open handle.
    IOSink? sink;
    // Mag het halve bestand blijven staan voor een volgende poging? Alleen als er echt bytes van
    // DIT bestand in staan; bij een 404 of een geweigerde sleutel is er niets om op verder te gaan.
    var deelBewaren = false;
    try {
      final eerder = await _deelVan(libraryPath);
      var al = eerder.al;

      // Verdergaan waar de vorige poging stopte. Bij een plaat als één bestand van 32 bit/384 kHz
      // gaat het om gigabytes: opnieuw beginnen na een wegvallende wifi betekent dat het nooit af
      // komt, omdat elke poging weer van voren af aan begint.
      final req = http.Request('GET', Uri.parse(url));
      if (al > 0) req.headers[HttpHeaders.rangeHeader] = 'bytes=$al-';
      final res = await _http.send(req).timeout(stilte);

      if (al > 0 && res.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        await _gooiDeelWeg(libraryPath);
        throw const HttpException('het bestand op de pc is veranderd — probeer opnieuw');
      }
      if (res.statusCode != HttpStatus.ok && res.statusCode != HttpStatus.partialContent) {
        throw HttpException('HTTP ${res.statusCode}');
      }
      // Een server die het bereik negeert stuurt gewoon alles: dan begint het bestand ook opnieuw.
      if (al > 0 && res.statusCode == HttpStatus.ok) al = 0;

      final total = _geheelUit(res, al);
      if (al > 0 && total > 0 && eerder.verwacht != total) {
        await _gooiDeelWeg(libraryPath);
        throw const HttpException('het bestand op de pc is veranderd — probeer opnieuw');
      }
      if (al == 0 && total > 0) {
        try {
          await _stempelFor(libraryPath).writeAsString(jsonEncode({'totaal': total}));
        } catch (_) {/* dan gaat een volgende poging van voren af aan; erger niet */}
      }

      var written = al;
      job
        ..gedaan = written
        ..totaal = total;
      // Two names for one sink on purpose: `out` is what writes, `sink` is only "there is still a
      // handle to let go of". Nulling `sink` after a clean close is what keeps the failure path
      // below from closing an already-closed sink.
      final out = temp.openWrite(mode: al > 0 ? FileMode.append : FileMode.write);
      sink = out;
      // `timeout` op de stroom is de wachtklok: hij slaat toe als er ZOLANG niets binnenkomt, niet
      // als het geheel lang duurt. Een bestand van vier gigabyte mag uren doen; veertig seconden
      // niets is stuk.
      await for (final chunk in res.stream.timeout(stilte)) {
        if (_cancelled.contains(libraryPath)) {
          await out.close();
          sink = null;
          await _gooiDeelWeg(libraryPath);
          _jobs.remove(libraryPath);
          notifyListeners();
          return false;
        }
        out.add(chunk);
        written += chunk.length;
        deelBewaren = true;
        if (total > 0) {
          final next = written / total;
          // Only when the bar would visibly move. A FLAC is tens of thousands of chunks and a
          // notifyListeners per chunk rebuilds the whole downloads screen thousands of times.
          if (job.progress == null || next - job.progress! >= 0.02) {
            job
              ..progress = next
              ..gedaan = written;
            notifyListeners();
          }
        }
      }
      await out.close();
      sink = null; // closed cleanly — nothing for the failure path below to close again
      job.gedaan = written;

      // The server said how big it would be. Fewer bytes than that means the connection dropped,
      // and a truncated FLAC is worse than no copy at all: it plays and then stops, which sounds
      // like the track is broken rather than like a download that failed.
      if (total > 0 && written < total) {
        throw HttpException('afgebroken bij ${_maat(written)} van ${_maat(total)}');
      }

      // Into place only once it is whole. A half file that a crash left behind would otherwise be
      // indistinguishable from a finished one and would play as a track that stops halfway.
      if (await target.exists()) await target.delete();
      await temp.rename(target.path);
      await _gooiDeelWeg(libraryPath); // de stempel hoort bij het halve bestand, niet bij het hele

      _tracks[libraryPath] = OfflineTrack(
        path: libraryPath,
        file: target.path,
        bytes: written,
        title: title,
        artist: artist,
        album: album,
        savedAt: DateTime.now(),
      );
      await _save();
      job.done = true;
      _jobs.remove(libraryPath);
      notifyListeners();
      return true;
    } catch (e) {
      // **De taak blijft staan.** Vroeger werd hij hier weggegooid op hetzelfde moment dat de fout
      // erin gezet werd, en las niemand hem ooit: de knop sprong terug naar "Offline bewaren" en er
      // stond nergens dat of waarom het mislukt was. Nu blijft hij, met de reden erbij, tot iemand
      // hem opnieuw probeert of weghaalt.
      job.error = _leesbaar(e);
      job.wacht = false;
      // Close before deleting, and swallow what close() rethrows: a sink whose stream errored
      // hands that same error back here, and it is already being reported as job.error.
      try {
        await sink?.close();
      } catch (_) {/* the write already failed — this is only letting go of the handle */}
      if (!deelBewaren) await _gooiDeelWeg(libraryPath);
      notifyListeners();
      debugPrint('Offline download failed for $libraryPath: $e');
      return false;
    }
  }

  /// Bytes in iets wat je kunt uitspreken.
  static String _maat(int bytes) {
    if (bytes >= 1000 * 1000 * 1000) return '${(bytes / 1e9).toStringAsFixed(1)} GB';
    if (bytes >= 1000 * 1000) return '${(bytes / 1e6).round()} MB';
    return '${(bytes / 1000).round()} kB';
  }

  /// Stop a download that is still running.
  void cancel(String libraryPath) {
    final job = _jobs[libraryPath];
    if (job == null) return;
    _cancelled.add(libraryPath);
    // Ook uit de rij halen, anders begint hij alsnog zodra hij aan de beurt is — met een vlag die
    // zegt dat hij geannuleerd was. Dan zou "weghalen" een nummer terugbrengen.
    final wachtte = _wachtrij.indexWhere((r) => r.libraryPath == libraryPath);
    if (wachtte >= 0) _wachtrij.removeAt(wachtte);

    // Een taak die LOOPT ruimt zichzelf op zodra hij de vlag ziet; een taak die wacht of al
    // mislukt is doet niets meer, dus die moet hier weg — anders blijft een mislukking staan
    // nadat je hem hebt weggetikt.
    if (job.wacht || !job.bezig) {
      _jobs.remove(libraryPath);
      unawaited(_gooiDeelWeg(libraryPath));
      notifyListeners();
    }
  }

  /// Take a track off this device. The PC's copy is untouched — this is the whole difference
  /// between "remove the download" and "delete the track", and they must never be confused.
  Future<void> remove(String libraryPath) async {
    cancel(libraryPath);
    final t = _tracks.remove(libraryPath);
    notifyListeners();
    await _gooiDeelWeg(libraryPath);
    if (t == null) return;
    try {
      final f = File(t.file);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('Offline file not deleted: $e');
    }
    await _save();
  }

  /// Everything off.
  Future<void> clear() async {
    final paths = _tracks.keys.toList();
    for (final p in paths) {
      await remove(p);
    }
  }

  @override
  void dispose() {
    _http.close();
    super.dispose();
  }
}

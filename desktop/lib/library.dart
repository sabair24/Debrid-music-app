import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'album_facts.dart';
import 'album_id.dart';
import 'completeness.dart';
import 'editions.dart';
import 'enrichment.dart';
import 'fingerprint.dart';
import 'flac_tags.dart';
import 'lan/client.dart';
import 'lan/dtos.dart';
import 'lan/ids.dart';
import 'models.dart';
import 'mp3_tags.dart';
import 'echtheid.dart';
import 'echtheid_meter.dart';
import 'echtheid_oordelen.dart';
import 'organize.dart';
import 'settings.dart';
import 'vaste_keuze.dart';
import 'paths.dart';

/// Welke bestanden de bibliotheek als muziek beschouwt.
///
/// **`.ape` en `.wv` staan er sinds 29-08-2026 bij, en hun afwezigheid was een stille lek.** De
/// downloadkant nam ze wél aan (`TbFile.isAudio` noemt ape en wv), dus een rip in Monkey's Audio of
/// WavPack — bij Franse en Russische bronnen doodgewoon — kwam netjes binnen, ging netjes naar je
/// schijf, en verscheen nergens. Geen fout, geen regel, niets: "waar is de rest?".
///
/// Ze kunnen ook echt gespeeld worden: libmpv leest allebei, en het omzetten voor een speaker gaat
/// via ffmpeg, die ze ook leest. Dat is dezelfde afspraak als voor `.wma` en `.alac`, die hier al
/// stonden.
const _audioExt = {
  '.flac',
  '.mp3',
  '.m4a',
  '.wav',
  '.ogg',
  '.opus',
  '.aac',
  '.wma',
  '.alac',
  '.ape',
  '.wv',
};

String _ext(String p) {
  final i = p.lastIndexOf('.');
  return i < 0 ? '' : p.substring(i).toLowerCase();
}

String _baseName(String p) {
  final s = p.replaceAll('\\', '/').split('/').last;
  final i = s.lastIndexOf('.');
  return i < 0 ? s : s.substring(0, i);
}

/// Pass 1 (runs in a background isolate): read tags only — fast + low memory.
/// The cover an album already had, carried across a regroup by TRACK PATH.
///
/// A class rather than the list of three this replaced, because the fourth slot brought a String
/// along with it and a `List<Uint8List?>` has nowhere to put that. Naming the fields also means the
/// two places that restore it can no longer disagree about which index was which.
class _Covers {
  const _Covers(this.embedded, this.enriched, this.corrected, this.resolved, this.resolvedFrom);
  final Uint8List? embedded, enriched, corrected, resolved;
  final String? resolvedFrom;

  factory _Covers.of(Album a) =>
      _Covers(a.embeddedCover, a.enriched, a.correctedCover, a.resolvedCover, a.resolvedFrom);

  void applyTo(Album a) {
    a.embeddedCover = embedded;
    a.enriched = enriched;
    a.correctedCover = corrected;
    a.resolvedCover = resolved;
    a.resolvedFrom = resolvedFrom;
  }
}

/// Wat de vorige scan uit elk bestand haalde, zodat het niet elke start opnieuw hoeft.
///
/// **Waarom dit er moest komen.** Gemeten op Sabers pc, 775 audiobestanden op een gewone harde
/// schijf (ST1000DM010):
///
///     scan/tags   koud 16877 ms      warm 9246 ms
///     scan/hoezen koud 11169 ms      warm  686 ms
///
/// Terwijl de schijf zélf, met de hand gemeten, alle 775 koppen warm in **163 ms** levert (koud
/// 6535 ms). Er ging dus negen seconden in het parseren zitten waar niets aan veranderd was: titel,
/// artiest, album, jaar, duur, samplerate en bitdiepte kwamen elke start opnieuw uit dezelfde
/// ongewijzigde bytes.
///
/// De sleutel is `(pad, mtime, grootte)`, en die drie lagen al klaar — de scan doet toch al een
/// `statSync` per bestand (dat kost warm 14 ms voor alle 775). Verandert een bestand, dan verandert
/// mtime of grootte en wordt het gewoon opnieuw gelezen; schrijft de app zelf tags, idem.
///
/// De cache wordt geschreven uit wat DEZE scan zag, dus een verwijderd bestand valt er vanzelf uit
/// en het bestand kan niet ongelimiteerd groeien — anders dan `album_facts.json`, dat op 10 MB stond
/// voor 233 albums.
const _tagCacheVersie = 1;

Map<String, Map<String, dynamic>> _laadTagCache(String? pad) {
  if (pad == null) return const {};
  try {
    final f = File(pad);
    if (!f.existsSync()) return const {};
    final j = jsonDecode(f.readAsStringSync());
    // Een oudere versie wordt weggegooid in plaats van gelezen: de rij heeft er in het verleden
    // velden bij gekregen (bitsPerSample, sampleRate), en een rij van vóór die tijd zou stilletjes
    // nullen opleveren voor nummers die er wél degelijk hebben.
    if (j is! Map || j['v'] != _tagCacheVersie) return const {};
    final rijen = j['rijen'];
    if (rijen is! List) return const {};
    return {
      for (final r in rijen)
        if (r is Map<String, dynamic> && r['path'] is String) r['path'] as String: r,
    };
  } catch (_) {
    return const {}; // een onleesbare cache kost één trage start, geen klap
  }
}

void _schrijfTagCache(String? pad, List<Map<String, dynamic>> rijen) {
  if (pad == null) return;
  try {
    // De map eerst, want die hoeft er nog niet te zijn. Gemeten: bij een verse start bestond
    // `%APPDATA%\DebridMusic` nog niet op het moment dat de scan klaar was — hij wordt pas even
    // later aangemaakt door de eerste bewaaractie met vertraging. Zonder deze regel sloeg de cache
    // de allereerste keer stil over, en dan is precies de start ná een installatie nog traag.
    final map = File(pad).parent;
    if (!map.existsSync()) map.createSync(recursive: true);
    // Via een tijdelijk bestand en een hernoeming: een klap halverwege mag geen half bestand
    // achterlaten dat de volgende start als geldig leest.
    final tmp = File('$pad.tmp');
    tmp.writeAsStringSync(jsonEncode({'v': _tagCacheVersie, 'rijen': rijen}));
    tmp.renameSync(pad);
  } catch (_) {/* niet kunnen bewaren kost snelheid, nooit correctheid */}
}

typedef ScanUitslag = ({List<Map<String, dynamic>> rijen, int uitCache, int gelezen});

/// Een album en zijn nummers, plat genoeg om naar een isolate te sturen.
typedef _PlatTrack = ({String title, String artist, String path, int? durationSec});
typedef _PlatAlbum = ({bool isSingle, String title, String artist, List<_PlatTrack> tracks});
typedef _PlatPaar = ({int bronTrack, int doelTrack, bool dupWint});
typedef _PlatTreffer = ({int bron, int doel, List<_PlatPaar> paren});

/// De dubbelzoeker, los van [LibraryStore] zodat hij op een isolate kan draaien.
///
/// Woord voor woord dezelfde afweging als [LibraryStore.redundantAlbums] — dat is met opzet: er is
/// een toets die beide over de ECHTE bibliotheek draait en eist dat er hetzelfde uit komt. Wijkt er
/// hier iets af, dan valt die om.
///
/// [kennis] draagt wat `firstIsBetter` normaal uit het geheugen leest. Zie [Voorkennis] voor waarom
/// dat mee moet.
List<_PlatTreffer> _zoekDubbels(List<_PlatAlbum> albums, Voorkennis kennis) {
  final doelen = <int>[
    for (var i = 0; i < albums.length; i++)
      if (!albums[i].isSingle &&
          albums[i].tracks.length >= 2 &&
          classifyRelease(album: albums[i].title, artist: albums[i].artist) == RelKind.album)
        i,
  ];
  if (doelen.isEmpty) return const [];

  int? bezitIn(_PlatAlbum doel, _PlatTrack x, {required bool junk}) {
    final xDur = x.durationSec ?? 0;
    if (!junk && normKey(x.title).isNotEmpty) {
      for (var j = 0; j < doel.tracks.length; j++) {
        final y = doel.tracks[j];
        if (normKey(x.title) != normKey(y.title)) continue;
        final yDur = y.durationSec ?? 0;
        if (xDur == 0 || yDur == 0 || (xDur - yDur).abs() <= 12) return j;
      }
    }
    for (var j = 0; j < doel.tracks.length; j++) {
      final y = doel.tracks[j];
      if (fileOffersTitle(y.title, y.durationSec, y.artist, x.path, xDur)) return j;
    }
    return null;
  }

  final uit = <_PlatTreffer>[];
  for (var xi = 0; xi < albums.length; xi++) {
    final x = albums[xi];
    if (!x.isSingle &&
        (classifyRelease(album: x.title, artist: x.artist) == RelKind.compilation ||
            _distinctPerformanceRe.hasMatch(normKey(x.title)))) {
      continue;
    }
    final junk = x.isSingle && (x.artist.trim().isEmpty || artistKey(x.artist) == _unknownArtistKey);

    int? beste;
    List<_PlatPaar>? besteParen;
    for (final yi in doelen) {
      if (yi == xi) continue;
      final y = albums[yi];
      if (y.tracks.length < x.tracks.length) continue;
      if (!junk && artistKey(x.artist) != artistKey(y.artist)) continue;

      final paren = <_PlatPaar>[];
      var heel = true;
      for (var ti = 0; ti < x.tracks.length; ti++) {
        final bezit = bezitIn(y, x.tracks[ti], junk: junk);
        if (bezit == null) {
          heel = false;
          break;
        }
        paren.add((
          bronTrack: ti,
          doelTrack: bezit,
          dupWint: firstIsBetter(File(x.tracks[ti].path), File(y.tracks[bezit].path), kennis: kennis),
        ));
      }
      if (!heel) continue;
      if (beste == null || y.tracks.length > albums[beste].tracks.length) {
        beste = yi;
        besteParen = paren;
      }
    }
    if (beste != null && besteParen != null && besteParen.isNotEmpty) {
      uit.add((bron: xi, doel: beste, paren: besteParen));
    }
  }
  return uit;
}

ScanUitslag _scanTags(String root, String? cachePad) {
  final out = <Map<String, dynamic>>[];
  final cache = _laadTagCache(cachePad);
  var uitCache = 0, gelezen = 0;
  final dir = Directory(root);
  if (!dir.existsSync()) return (rijen: out, uitCache: 0, gelezen: 0);
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is! File || !_audioExt.contains(_ext(e.path))) continue;
    // Skip the download staging folder. Files in there are still arriving — a half-finished 2 MB
    // WAV was showing up as its own album, 0:00 long, until the transfer completed.
    if (e.path.contains('${Platform.pathSeparator}_inkomend${Platform.pathSeparator}')) continue;
    // Skip the parking folder for superseded copies. They are kept on disk as a safety net but are
    // deliberately NOT part of the library — otherwise a parked junk WAV keeps scanning back in as
    // its own single and the duplicate cleanup can never finish.
    if (e.path.contains('${Platform.pathSeparator}$dupeFolder${Platform.pathSeparator}')) continue;
    // En de map waarin de torrentmotor werkt. Daar staan halve bestanden, en bestanden die aria2
    // opnieuw ophaalt omdat een eerdere download ze heeft weggehaald. Zonder deze regel komen die
    // in de bibliotheek — gemeld op 29-08-2026 als "er komen liedjes bij die ik nooit heb
    // aangeklikt". Zie [torrentWerkMap] in `online.dart`.
    if (e.path.contains('${Platform.pathSeparator}$torrentWerkMap${Platform.pathSeparator}')) {
      continue;
    }
    var addedMs = 0, sizeBytes = 0;
    try {
      final st = e.statSync();
      addedMs = st.modified.millisecondsSinceEpoch;
      sizeBytes = st.size;
    } catch (_) {}

    // Onveranderd sinds de vorige scan? Dan hoeft het bestand niet open. Dit is de hele winst.
    //
    // `sizeBytes > 0` als voorwaarde, want een mislukte stat geeft 0/0 terug en zou dan matchen met
    // een even mislukte vorige keer — dan zou een onleesbaar bestand voor eeuwig zijn oude rij
    // houden in plaats van opnieuw geprobeerd te worden.
    if (sizeBytes > 0) {
      final bewaard = cache[e.path];
      if (bewaard != null && bewaard['addedMs'] == addedMs && bewaard['sizeBytes'] == sizeBytes) {
        out.add(bewaard);
        uitCache++;
        continue;
      }
    }
    gelezen++;
    final rij = _rijVoorBestand(e, addedMs: addedMs, sizeBytes: sizeBytes);
    if (rij != null) out.add(rij);
  }
  _schrijfTagCache(cachePad, out);
  return (rijen: out, uitCache: uitCache, gelezen: gelezen);
}

/// De tagrij van ÉÉN bestand, of null als er niets leesbaars in staat.
///
/// Uit [_scanTags] gelicht zodat [leesTagrijInIsolate] precies hetzelfde leest als een volledige
/// scan. Twee lezers die uit elkaar lopen is hier bijzonder naar: een nummer dat via de radio
/// binnenkomt zou dan andere velden krijgen dan datzelfde nummer na een herstart, en dan verspringt
/// het van album zodra je de app opnieuw opent.
Map<String, dynamic>? _rijVoorBestand(File e, {required int addedMs, required int sizeBytes}) {
  // FLAC goes through our own parser first: the package throws on tags it can't parse (a vinyl
  // "A3" track number is enough) and LEAKS THE FILE HANDLE when it does, which would leave that
  // track unmovable and undeletable for the rest of the session. See readTags().
  if (_ext(e.path) == '.flac') {
    final v = readFlacTags(e);
    if (v != null && (v.title != null || v.artist != null || v.album != null)) {
      return {
        'path': e.path,
        'title': v.title ?? _baseName(e.path),
        'artist': v.artist ?? 'Onbekende artiest',
        'album': v.album ?? '',
        'trackNo': v.trackNo,
        'trackTotal': v.trackTotal,
        'durationMs': v.duration?.inMilliseconds ?? 0,
        'isFlac': true,
        'year': v.year,
        'genre': v.genre,
        'addedMs': addedMs,
        'sizeBytes': sizeBytes,
        'sampleRate': v.sampleRate,
        'bitsPerSample': v.bitsPerSample,
      };
    }
  }
  // Never hand the package a file it is going to refuse: it opens before it decides, and the
  // refusal keeps the handle. See tagParserWouldClaim().
  //
  // Maar niet meer WEGGOOIEN als hij het weigert. Hier stond `return null`, en dat is een van de
  // manieren waarop een download "verdwijnt": het bestand staat op je schijf, de speler kan het
  // gewoon afspelen — libmpv leest veel meer dan deze tagontleder — maar het komt de bibliotheek
  // niet in, en er staat nergens waarom. Een rip zonder tags, met tags in een ongewone vorm, of in
  // een doos die deze ontleder niet kent, was daarmee onvindbaar.
  //
  // De prijs is dat er af en toe een regel bij komt die "Onbekende artiest" heet en naar zijn
  // bestandsnaam luistert. Dat is een regel die je ziet en kunt weggooien; het alternatief is muziek
  // die je hebt en niet kunt vinden.
  if (!tagParserWouldClaim(e)) return _kaleRij(e, addedMs: addedMs, sizeBytes: sizeBytes);
  try {
    final m = readMetadata(e, getImage: false);
    return {
      'path': e.path,
      'title': (m.title?.trim().isNotEmpty ?? false) ? m.title!.trim() : _baseName(e.path),
      'artist': (m.artist?.trim().isNotEmpty ?? false) ? m.artist!.trim() : 'Onbekende artiest',
      'album': m.album?.trim() ?? '', // empty => single
      'trackNo': m.trackNumber ?? 0,
      // The generic reader has no track-total, so a non-FLAC file simply doesn't take part in
      // edition splitting — it stays with the plain album, which is where it was anyway.
      'trackTotal': 0,
      'durationMs': m.duration?.inMilliseconds ?? 0,
      'isFlac': _ext(e.path) == '.flac',
      'year': (m.year != null && m.year!.year > 1000) ? m.year!.year : null,
      'genre': (m.genres.isNotEmpty) ? m.genres.first : null,
      'addedMs': addedMs,
      'sizeBytes': sizeBytes,
      'sampleRate': m.sampleRate ?? 0,
      // The generic reader doesn't report bit depth; only the FLAC path above can.
      'bitsPerSample': 0,
    };
  } catch (_) {
    // Ook hier: een ontleder die struikelt is geen reden om het bestand te laten verdwijnen.
    return _kaleRij(e, addedMs: addedMs, sizeBytes: sizeBytes);
  }
}

/// Een muziekbestand waar geen tag uit te lezen viel, op zijn bestandsnaam.
///
/// Alles wat er niet in staat blijft leeg in plaats van geraden: een verzonnen albumnaam zou het bij
/// vreemde buren in het raster zetten, en dan ben je het nóg kwijt.
Map<String, dynamic> _kaleRij(File e, {required int addedMs, required int sizeBytes}) => {
      'path': e.path,
      'title': _baseName(e.path),
      'artist': 'Onbekende artiest',
      'album': '',
      'trackNo': 0,
      'trackTotal': 0,
      'durationMs': 0,
      'isFlac': _ext(e.path) == '.flac',
      'year': null,
      'genre': null,
      'addedMs': addedMs,
      'sizeBytes': sizeBytes,
      'sampleRate': 0,
      'bitsPerSample': 0,
    };

/// Eén bestand lezen, op een andere isolate. Zie [scanTagsInIsolate] voor waarom de closure hier
/// staat en niet in een methode.
///
/// **Waarom niet gewoon op de tekendraad.** Eén bestand lezen kost een paar milliseconden en dat zou
/// je kunnen wegwuiven — maar dit gaat over bestanden van vreemden, en dat is precies het geval waar
/// de ontleder blijft hangen of gooit met een open handvat. Op de tekendraad is dat een bevroren app;
/// hier is het een isolate die omvalt en een null oplevert.
Future<Map<String, dynamic>?> leesTagrijInIsolate(String pad) => Isolate.run(() {
      final f = File(pad);
      var addedMs = 0, sizeBytes = 0;
      try {
        final st = f.statSync();
        addedMs = st.modified.millisecondsSinceEpoch;
        sizeBytes = st.size;
      } catch (_) {
        return null;
      }
      if (!_audioExt.contains(_ext(pad))) return null;
      return _rijVoorBestand(f, addedMs: addedMs, sizeBytes: sizeBytes);
    });

/// Run pass 1 on another isolate.
///
/// The `Isolate.run` closure is built HERE, at top level, and deliberately not inside
/// [LibraryStore.scan]. A closure created inside an instance method carries its enclosing
/// context with it, and that context reaches both `this` and the async method's own completer.
/// Once a widget has attached a listener to the store, that context is unsendable: the send
/// throws, the scan's catch swallows it, and the app comes up with an EMPTY LIBRARY while the
/// music sits untouched on disk. Assigning `rootPath` to a local first is not enough to prevent
/// it — only moving the closure out of the method is.
///
/// Covered by `test/library_isolate_test.dart`, which scans with a listener attached.
/// [cachePad] wordt MEEGEGEVEN in plaats van uit [appDir] gehaald: een isolate krijgt een verse kopie
/// van die globale, dus `setAppDirForTest` geldt daar niet en een test zou in de echte `%APPDATA%`
/// gaan schrijven.
Future<ScanUitslag> scanTagsInIsolate(String root, String? cachePad) =>
    Isolate.run(() => _scanTags(root, cachePad));

/// Pass 2 on another isolate — same reasoning as [scanTagsInIsolate].
Future<Map<String, Uint8List>> readCoversInIsolate(
        List<String> teLezen, String? cacheMap, List<String> alleEerste) =>
    Isolate.run(() => _readCovers(teLezen, cacheMap, alleEerste));

/// Pass 2 (background isolate): read one embedded cover per album.
/// De ingebedde hoezen, bewaard naast de andere staat in plaats van elke start opnieuw opgediept.
///
/// **Waarom een aparte map en niet bij de tags in.** Gemeten: 236 hoezen, gemiddeld 211 KB, samen
/// zo'n 50 MB. Dat door `jsonEncode`/`jsonDecode` halen op de UI-isolate zou erger zijn dan de kwaal
/// — `album_facts.json` doet dat met 10 MB en kost daarmee al 100-250 ms jank. Losse bestanden
/// worden gelezen wat er nodig is, en verder niets.
///
/// **Waarom het toch moet.** De tagpass sláát het PICTURE-blok over (`setPositionSync`), dus die
/// bytes zitten na pass 1 niet in de bestandscache van Windows. Elke hoes is daarna een verse
/// zoekbeweging op een draaiende schijf: gemeten 9066 ms voor 236 albums, oftewel 38 ms per stuk, en
/// dat betaalt de app bij ÉLKE start opnieuw omdat `embeddedCover` na een herstart voor elk album
/// leeg is. De staatmap staat op de SSD; daar kost hetzelfde een fractie.
///
/// De sleutel is dezelfde als bij de tags — `(pad, mtime, grootte)` — dus een bewerkt bestand levert
/// vanzelf een nieuwe lezing op. Een album zónder ingebedde plaat krijgt een leeg merkbestand: dat
/// is 53% van de bibliotheek, en zonder merk zou juist die helft elke start opnieuw opengaan.
String hoesSleutel(String pad, int mtime, int grootte) {
  // FNV-1a met de hand, en NIET `Object.hash`. Die is per proces geseed, dus dezelfde invoer geeft
  // bij de volgende start een andere naam — gemeten met drie processen achter elkaar:
  //
  //     Object.hash  ->  1c67de33 / 1ec744fb / 106b7271     (zelfde pad, mtime en grootte)
  //     hashCode van het pad ->  28c5c741 / 28c5c741 / 28c5c741
  //
  // Met de eerste sloeg deze cache dus alleen binnen één proces aan. Op de meetbank was dat
  // onzichtbaar (drie scans in hetzelfde proces, dus dezelfde seed); de app zelf las bij elke start
  // 238 bestanden opnieuw én schreef er 238 nieuwe, en ruimde de oude daarna op — 17,4 seconden.
  // Zie [groen-is-niet-goed]: de bank was groen en klopte niet.
  //
  // Mtime en grootte hoeven niet gehasht: dat zijn gewoon getallen.
  var h = 0x811c9dc5;
  for (final c in pad.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return '${h.toRadixString(16)}_${grootte.toRadixString(36)}_${mtime.toRadixString(36)}';
}

/// [teLezen] zijn de albums die nog geen hoes hebben; [alleEerste] is het eerste nummer van ÉLK
/// album, en dat is een andere lijst.
///
/// **Waarom die twee uit elkaar moeten.** Het opruimen ging eerst op [teLezen], en dat is bijna altijd
/// een handjevol: bij een herscan — en die volgt op elke voltooide download — dragen de albums hun
/// hoes al in het geheugen mee, dus wordt er alleen naar de nieuwe gevraagd. De opruimregel gooide dan
/// alles weg wat niet in dat handjevol zat. Gemeten op de echte pc: van 236 bestanden en 125 MB naar
/// 76 lege merkbestanden en 0 MB — de hele cache leeg, en de eerstvolgende start weer traag.
Map<String, Uint8List> _readCovers(List<String> teLezen, String? cacheMap, List<String> alleEerste) {
  final paths = teLezen;
  final out = <String, Uint8List>{};
  final map = cacheMap == null ? null : Directory(cacheMap);
  final levend = <String>{};

  // Wat er mag blijven staan wordt bepaald door ALLE albums, niet door wat deze ronde gelezen wordt.
  if (map != null) {
    for (final p in alleEerste) {
      try {
        final st = File(p).statSync();
        final s = hoesSleutel(p, st.modified.millisecondsSinceEpoch, st.size);
        levend..add(s)..add('$s.geen');
      } catch (_) {/* net weg; dan mag zijn hoes ook weg */}
    }
  }
  if (map != null && !map.existsSync()) {
    try {
      map.createSync(recursive: true);
    } catch (_) {}
  }

  for (final p in paths) {
    String? sleutel;
    if (map != null) {
      try {
        final st = File(p).statSync();
        sleutel = hoesSleutel(p, st.modified.millisecondsSinceEpoch, st.size);
      } catch (_) {}
    }
    if (sleutel != null) {
      // `levend` is hierboven al uit ALLE albums gevuld; dit pad zit daar per definitie ook in.
      final bewaard = File('${map!.path}${Platform.pathSeparator}$sleutel');
      if (bewaard.existsSync()) {
        try {
          final b = bewaard.readAsBytesSync();
          if (b.isNotEmpty) out[p] = b;
          continue;
        } catch (_) {}
      }
      // Het merk "hier zit er geen in" telt net zo goed als een antwoord.
      if (File('${map.path}${Platform.pathSeparator}$sleutel.geen').existsSync()) continue;
    }

    final gevonden = _leesHoes(p);
    if (gevonden != null && gevonden.isNotEmpty) out[p] = gevonden;
    if (sleutel != null) {
      try {
        final naam = gevonden != null && gevonden.isNotEmpty ? sleutel : '$sleutel.geen';
        File('${map!.path}${Platform.pathSeparator}$naam')
            .writeAsBytesSync(gevonden ?? Uint8List(0));
      } catch (_) {}
    }
  }

  // Opruimen wat bij geen enkel huidig bestand meer hoort — een hernoemd of bewerkt nummer laat
  // anders zijn oude hoes voorgoed staan.
  if (map != null && levend.isNotEmpty) {
    try {
      for (final f in map.listSync().whereType<File>()) {
        final naam = f.path.split(Platform.pathSeparator).last;
        if (!levend.contains(naam)) f.deleteSync();
      }
    } catch (_) {/* opruimen mag nooit het opstarten breken */}
  }
  return out;
}

/// De hoes uit één bestand halen. Null betekent "geen ingebedde plaat", en dat is een antwoord.
Uint8List? _leesHoes(String p) {
  // FLAC eerst door onze eigen lezer, net als in pass 1: één open, vooruit door de blokken, geen
  // sprongen naar het einde. Zie [readFlacPicture] voor wat het pakket eronder anders zou doen.
  if (_ext(p) == '.flac') {
    final r = readFlacPicture(File(p));
    if (r.gelezen) return r.hoes; // ook null telt — dan zit er gewoon geen plaat in
  }
  // Same guard as pass 1. This pass has no FLAC fast path in front of it, so it is the one that
  // would lock a perfectly good album the day its track number reads "A3".
  if (!tagParserWouldClaim(File(p))) return null;
  try {
    final m = readMetadata(File(p), getImage: true);
    if (m.pictures.isNotEmpty) return m.pictures.first.bytes;
  } catch (_) {}
  return null;
}

/// Waarom de bibliotheek op het scherm niet live is. Zie [LibraryStore.geenVerbinding].
enum GeenVerbinding {
  /// De pc antwoordt niet: hij slaapt, staat uit, of er is geen netwerk.
  pcStil,

  /// De pc antwoordt WEL, maar weigert deze sleutel (401/403).
  sleutelGeweigerd,
}

/// Scans the music folder, groups into albums/singles, reads covers, and enriches.
class LibraryStore extends ChangeNotifier {
  final List<Track> tracks = [];
  List<Album> albums = [];
  bool scanning = false;
  int scanned = 0;
  bool enriching = false;
  bool _rescanQueued = false;
  final Map<String, Uint8List> artistImages = {};
  final Map<String, String> artistBios = {};
  /// Where the music lives. Empty until [AppSettings.musicRoot] is applied in main().
  ///
  /// Empty rather than a path, deliberately. This used to default to one developer's `D:\Flac
  /// music 2024`, and on Windows that is not harmless: `ownsTheMusic` answers true there whatever
  /// the settings say, so a PC with no music folder configured would scan a stranger's path,
  /// find nothing, and show an empty library without a word of explanation. main() now carries
  /// the legacy value over into the settings once, so it is visible and changeable instead of
  /// baked in here.
  String _rootPath = '';
  String get rootPath => _rootPath;

  /// De muziekmap. Wijzigt hij, dan is elk onthouden id ongeldig — zie [gedeeldId].
  set rootPath(String v) {
    if (v == _rootPath) return;
    _rootPath = v;
    _idGeheugen.clear();
  }

  /// Pad → het id waarmee de gedeelde staat dit nummer kent. Zie [gedeeldId].
  ///
  /// **Waarom onthouden.** Het id is een SHA-256, en de shuffle vraagt er bij één druk op de knop
  /// vijfduizend op. Dat is tien tot veertig milliseconden op de tekendraad, elke keer opnieuw —
  /// terwijl het antwoord voor hetzelfde pad nooit verandert. Een halve megabyte geheugen is die
  /// milliseconden waard, en `main.dart` bouwt diezelfde hashes vandaag zelfs ín een `build`.
  final Map<String, String> _idGeheugen = {};

  /// Albums/singles found to be entirely duplicates of a real album you own — recomputed after each
  /// full scan, so the library can offer to tidy them without the user going hunting. Empty until a
  /// scan has run. See the [LibraryDuplicates] extension.
  List<RedundantAlbum> duplicates = const [];

  // [duplicates] wordt gevuld vanuit [scan], via [redundantAlbumsAsync] — op een andere isolate, want
  // deze afweging leest de FLAC-kop en de grootte van beide bestanden van elk kandidaatpaar.

  // Fast lookups for the flat Tracks view (covers) and playback resume (path → track).
  final Map<String, Album> _albumByPath = {};

  /// normalised "artist|title" → the copy we already have. Lets a download be skipped instead of
  /// creating a duplicate. Version markers stay in the key, so "(Live)" / "(Radio Edit)" / a
  /// compilation cut are all still treated as DIFFERENT tracks and download normally.
  final Map<String, Track> _owned = {};

  /// The track we already own that matches this artist+title (null if we don't have it).
  Track? ownedTrack(String artist, String title) => _owned[trackIdentity(artist, title)];

  /// In welke MAP deze opname al staat, of null als je hem nog niet hebt.
  ///
  /// Voor het opbergen van een download: die hoort naar het album te gaan waar de opname al in zit, en
  /// niet naar een nieuwe map die uit zijn eigen albumtag volgt. Anders staat een 24/192 van Thriller
  /// naast je 24/96 in plaats van erin — twee albums in de bibliotheek, en het betere bestand vervangt
  /// het mindere nooit, want die vergelijking kijkt alleen binnen één map.
  ///
  /// Zowel de nauwe als de ruime vraag, in die volgorde: [ownedTrack] is een opzoeking in één stap en
  /// klopt precies, [recordingElsewhere] vangt de gevallen waar de tags net anders geschreven staan.
  String? folderOfRecording(String artist, String title) {
    final t = ownedTrack(artist, title) ?? recordingElsewhere(artist, title);
    if (t == null) return null;
    final i = t.path.lastIndexOf(Platform.pathSeparator);
    return i <= 0 ? null : t.path.substring(0, i);
  }

  /// Het BESTAND waarin deze opname al staat, of null als je hem nog niet hebt.
  ///
  /// De map alleen was niet genoeg, en dat kostte precies de reparatie waarvoor [folderOfRecording]
  /// bedoeld was. De download landde wel in de goede map, maar zijn bestandsnaam werd afgeleid uit de
  /// tags van de uploader — en die schrijft geen tracknummer. Zo kwam "Bailamos.flac" naast
  /// "10 - Bailamos.flac" te staan: twee bestanden van hetzelfde nummer, want ze botsten nergens en de
  /// vervangingsregel kwam er nooit aan te pas.
  ///
  /// Met het volledige pad wordt de bestemming letterlijk het bestand dat er al ligt, en dan doet
  /// [firstIsBetter] zijn werk: de hoogste resolutie blijft, de mindere gaat naar `_dubbel`.
  /// **[seconds] is niet optioneel uit gemak — het is de reparatie.** Zonder looptijd antwoordde
  /// deze functie op niets meer dan artiest + titel, en [ownedTrack] doet dat met een sleutel die
  /// alleen genormaliseerde tekst kent. Gemeld op Sting: *Fields of Gold (My Songs Version)* uit
  /// 2019 (3:47) kreeg dezelfde sleutel als de plaat uit 1993 (3:39) die er al lag. De filer maakte
  /// van dat antwoord de BESTEMMING, en gooide het zojuist gedownloade bestand weg als mindere
  /// dubbel. [recordingElsewhere] paste die grens al toe; hier kwam hij nooit aan.
  ///
  /// Blijft [seconds] leeg — de catalogus zei niets — dan verandert er niets aan het oude gedrag.
  String? fileOfRecording(String artist, String title, {int? seconds}) {
    final eigen = ownedTrack(artist, title);
    if (eigen != null && _zelfdeLengte(eigen, seconds)) return eigen.path;
    return recordingElsewhere(artist, title, seconds: seconds)?.path;
  }

  /// Kan dit bestand de opname van [seconds] zijn?
  ///
  /// Alles onbekend is "ja": een track zonder leesbare looptijd, of een catalogus die er geen gaf,
  /// mag geen download blokkeren én geen download doorlaten die er al is. Alleen als beide getallen
  /// er zijn en ze verder uit elkaar liggen dan [sameRecordingSlack], is dit een andere opname.
  static bool _zelfdeLengte(Track t, int? seconds) {
    final secs = t.duration?.inSeconds ?? 0;
    if (seconds == null || seconds <= 0 || secs <= 0) return true;
    return (secs - seconds).abs() <= sameRecordingSlack;
  }

  /// A copy of this recording ANYWHERE in the library, whatever album it happens to be filed under.
  ///
  /// [ownedTrack] answers a narrower question and missed exactly the case that mattered. It keys on
  /// artist and title exactly, so a rip whose ARTIST tag reads "Daniel Bedingfield, D'N'D
  /// Productions" and whose version is written with a dash instead of brackets never matched the
  /// catalogue's "Daniel Bedingfield" / "(D'n'D radio edit)" — and the album page fetched a second,
  /// byte-identical copy of a file already on disk.
  ///
  /// Normalising the whole title is what closes that gap: [normKey] drops brackets and dashes
  /// alike, so both spellings land on one key without [versionMarkers] having to be widened — that
  /// would change what counts as a variant for the pressing picker and the tracklist matcher too.
  ///
  /// The tolerance is the tight one on purpose. A download wrongly refused is worse than a
  /// duplicate, so a running time that disagrees means "not this recording, fetch it".
  ///
  /// [exclude] holds the paths already on the page — a file cannot be elsewhere than where it is.
  Track? recordingElsewhere(String artist, String title,
      {int? seconds, Set<String> exclude = const {}}) {
    // Eerst de nepmerken eruit. `normKey` haalt haakjes en streepjes weg maar laat de WOORDEN staan,
    // dus "Escape (Album Version)" en "Escape" landen nog steeds op twee sleutels — terwijl het één
    // opname is. Zie [withoutFakeVersion]: die laat een écht merk als "(Live)" juist staan, zodat een
    // live-opname nog altijd niet voor de albumversie doorgaat.
    final wantTitle = normKey(withoutFakeVersion(title));
    if (wantTitle.isEmpty) return null;
    final wantArtist = artistKey(splitFeatured(artist, title).main);
    for (final t in tracks) {
      if (exclude.contains(t.path) || normKey(withoutFakeVersion(t.title)) != wantTitle) continue;
      if (!_artistCovers(artistKey(splitFeatured(t.artist, t.title).main), wantArtist)) continue;
      final secs = t.duration?.inSeconds ?? 0;
      if (seconds != null &&
          seconds > 0 &&
          secs > 0 &&
          (secs - seconds).abs() > sameRecordingSlack) {
        continue;
      }
      return t;
    }
    return null;
  }

  /// Is [mine] the artist [want], allowing for extra names credited alongside?
  ///
  /// Whole words only: a file credited to "Daniel Bedingfield, D'N'D Productions" is still that
  /// artist's, but "Amy Winehouse" must not be answered by a file credited to "Amy".
  static bool _artistCovers(String mine, String want) =>
      mine == want || (want.isNotEmpty && ' $mine '.contains(' $want '));

  /// Keep one copy per RECORDING within an album — the best format, then the longest/biggest — so
  /// a second download of the same song doesn't show up twice in the tracklist.
  ///
  /// Artist and title alone were not enough, and the damage was invisible. A correction that
  /// retitled "Gotta Get Thru This (D'N'D Full Length Version)" to the plain album title gave it
  /// the same identity as the 2:45 album cut sitting beside it; the bigger file won, and the other
  /// vanished from its own album while still counting in the header and still playing from the
  /// Tracks list. [RenumberPlan.titleCollides] refuses to create exactly this situation — the
  /// hand-written correction path had no such guard.
  ///
  /// So the rule is the one [_sameRecording] already applies when filing: the same version, and a
  /// running time that agrees. Asked here of the tags the scan already read, not by reopening both
  /// files — this runs for every track of every album on every regroup.
  List<Track> _dedupeTracks(List<Track> ts) {
    final byId = <String, List<Track>>{};
    for (final t in ts) {
      final takes = byId.putIfAbsent(trackIdentity(t.artist, t.title), () => []);
      final i = takes.indexWhere((other) => _sameTake(other, t));
      if (i < 0) {
        takes.add(t); // a different take of the same title keeps its own row
        continue;
      }
      // Same order as filing uses: format, then stereo over surround, then size — otherwise the
      // album view would show the 5.1 rip while the folder keeps the stereo master.
      if (firstIsBetter(File(t.path), File(takes[i].path))) takes[i] = t;
    }
    return [for (final takes in byId.values) ...takes];
  }

  /// Two files of one title that are the same RECORDING, decided on what the scan already read.
  ///
  /// The filename decides first, for the reason [_sameRecording] gives: an uploader writes
  /// "(Full Length Version)" in the name while the title tag stays plain. Only when both claim the
  /// same thing does the running time break the tie, and a file that never reported one is not
  /// held against itself.
  static bool _sameTake(Track a, Track b) {
    final ma = versionMarkers(_fileName(a.path)), mb = versionMarkers(_fileName(b.path));
    if (ma.length != mb.length || !ma.every(mb.contains)) return false;
    final sa = a.duration?.inSeconds ?? 0, sb = b.duration?.inSeconds ?? 0;
    return sa <= 0 || sb <= 0 || (sa - sb).abs() <= sameRecordingSlack;
  }

  static String _fileName(String path) => path.split(RegExp(r'[\\/]')).last;
  final Map<String, Track> _trackByPath = {};

  /// The album cover for a track (covers live on the Album, not the Track).
  Uint8List? coverForTrack(Track t) => _albumByPath[t.path]?.cover;

  /// The album a playing track belongs to. The now-playing screen needs the album, not just the
  /// track: the pressing the user pinned and the cover they picked both live on it, and without
  /// them that screen went off and resolved its own record — landing on a different artist's album
  /// that happened to share a title.
  Album? albumForPath(String path) => _albumByPath[path];

  /// Resolve a saved file path back to a library track (for resume).
  Track? trackByPath(String path) => _trackByPath[path];

  /// Bumped whenever a track's TEXT changes — its title, artist, album or numbering.
  ///
  /// Deliberately not "bumped whenever anything changes". This store notifies hundreds of times
  /// during startup while covers stream in, and every one of those is a `Track` set that has not
  /// moved at all. Anything that has to react to a real metadata change reads this integer instead
  /// of comparing the tracks themselves — the same split, and for the same reason, as `rev` versus
  /// `progressRev` in LanStateStore.
  ///
  /// Not bumped by: cover work of any kind, art roles, styles, duplicate recomputation.
  int get metaRev => _metaRev;
  int _metaRev = 0;
  void _bumpMeta() => _metaRev++;

  /// A name for each album that a rename does not move. Maintained at the tail of every
  /// [rebuildAlbums]; see album_id.dart for why it exists and why it may only ever observe.
  late final AlbumUids uids = AlbumUids(dir: () => _appDir);

  /// The uid of an album, for anything that wants to remember something about it.
  ///
  /// On a client the PC's album id stands in. Nothing here mints uids — the albums are the PC's and
  /// so is the answer that gets filed against them; a second naming scheme on this side would only
  /// be a way for the two to disagree.
  String uidOf(Album a) => isRemote ? (remoteAlbumId(a) ?? '') : uids.uidOf(a);

  /// What was worked out about each record — which pressing, its tracklist, what is missing. See
  /// album_facts.dart. Reached through the library because that is what knows the albums.
  late final AlbumFactsStore facts = AlbumFactsStore(dir: () => _appDir);

  /// How many albums have a track in each folder, refreshed with the albums. Only used to spot a
  /// flat dump, where a sidecar per album would be several albums fighting over one filename.
  Map<String, int> _albumsPerDir = const {};

  /// Where this album's sidecar belongs, or null when there is no sensible place for one.
  String? sidecarFolderFor(Album a) => albumFolderOf(a, _albumsPerDir);

  /// Read back what a previous install — or another machine — left next to the music.
  ///
  /// Only for albums the index has never heard of, which in the ordinary case is none of them and
  /// costs nothing at all. It is the reinstall, the new PC and the folder copied in from a laptop
  /// that this exists for: without it every one of those would re-derive the whole library from
  /// MusicBrainz, one album at a time, at a request a second.
  ///
  /// After the scan and off the critical path — nothing on screen is waiting for it, and an album
  /// whose facts arrive a moment late simply fills in a moment late.
  Future<void> _adoptSidecars() async {
    var adopted = 0;
    for (final a in albums) {
      final uid = uids.uidOf(a);
      if (uid.isEmpty || facts.get(uid) != null) continue;
      final folder = sidecarFolderFor(a);
      if (folder == null) continue;
      final found = await facts.adoptSidecar(uid, folder, trackSetHashOf(a.tracks));
      if (found != null) adopted++;
      // A breath between albums. This walks the whole library on a fresh install, and it is not
      // more important than the screen the user is looking at.
      await Future<void>.delayed(Duration.zero);
    }
    if (adopted > 0) {
      debugPrint('Adopted $adopted album sidecars from disk');
      notifyListeners();
    }
  }

  /// Which files this record is made of — the signal that facts need working out again.
  String trackSetHashFor(Album a) => trackSetHashOf(a.tracks);

  // Manual metadata corrections (non-destructive): file path -> {title,artist,album}.
  // Applied to scanned tracks so wrong tags are fixed without touching the files.
  final Map<String, Map<String, String>> _corrections = {};

  /// Where this app keeps its own files. Overridable ONLY so a test can be given a scratch folder:
  /// corrections.json is the user's hand-made metadata, and a test run that wrote its two fixtures
  /// over the real one would destroy months of edits.
  @visibleForTesting
  String? configDirOverride;

  String get _appDir {
    final o = configDirOverride;
    if (o != null) return o;
    return appDir;
  }

  /// Where this library's state files live — the same folder [_appDir] resolves to, exposed so
  /// something outside this class (the warmer's log) can write beside them and honour a test's
  /// override rather than scribbling in the real app directory.
  String get configDir => _appDir;

  /// Waar de tagcache van de scan staat. Zie [_laadTagCache] voor het waarom en de meting.
  String get tagCachePad => '$configDir${Platform.pathSeparator}tag_cache.json';

  /// Waar de ingebedde hoezen bewaard blijven. Zie [_hoesSleutel] voor het waarom en de meting.
  String get hoesCacheMap => '$configDir${Platform.pathSeparator}hoescache';

  /// What is recorded against a file, or null. For tests.
  @visibleForTesting
  Map<String, String>? correctionForTest(String path) => _corrections[path];

  /// Record something against a file, as an earlier edit would have. For tests.
  @visibleForTesting
  void seedCorrectionForTest(String path, Map<String, String> c) => _correctionsFor(path).addAll(c);

  File get _correctionsFile => File('$_appDir${Platform.pathSeparator}corrections.json');

  // ── The way back from a tag rewrite ───────────────────────────────────────
  // Writing tags is the one thing this app does that changes files the user already owns, and
  // until now it had no undo at all. Per path, the values those fields carried BEFORE the last
  // write — including the ones that were not there, recorded as null, because "this field did not
  // exist" is a state an undo has to be able to restore.
  //
  // Deliberately not in the album sidecar next to the music: that file is a cache of catalogue
  // facts, thrown away whenever the record changes (AlbumFacts.staleFor). Undo data that a cache
  // sweep can delete is not undo data.
  //
  // One level deep. Normalising the same album twice puts you back to how it was after the first
  // write, not to the beginning — the same as every other undo, and the honest thing to show.
  final Map<String, Map<String, String?>> _tagUndo = {};
  File get _tagUndoFile => File('$_appDir${Platform.pathSeparator}tag_undo.json');

  Future<void> loadTagUndo() async {
    try {
      final f = _tagUndoFile;
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _tagUndo.clear();
      j.forEach((path, v) {
        if (v is Map) {
          _tagUndo[path] = {
            for (final e in v.entries) e.key.toString(): e.value?.toString(),
          };
        }
      });
    } catch (_) {/* unreadable — no undo rather than a crash */}
  }

  Future<void> _saveTagUndo() => _writeJson(_tagUndoFile, _tagUndo);

  // ── Hidden tracks ─────────────────────────────────────────────────────────
  // "Remove from library only" keeps the FILE on disk but excludes it from the library. The
  // paths live in hidden.json so a rescan doesn't bring them straight back.
  final Set<String> _hidden = {};
  File get _hiddenFile => File('$_appDir${Platform.pathSeparator}hidden.json');

  Future<void> loadHidden() async {
    try {
      final f = _hiddenFile;
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as List<dynamic>;
      _hidden
        ..clear()
        ..addAll(j.map((e) => e.toString()));
    } catch (_) {}
  }

  Future<void> _saveHidden() => _writeJson(_hiddenFile, _hidden.toList());

  /// Number of files currently hidden but still on disk (shown in Settings so it's not a
  /// one-way door — the user can always bring them back).
  int get hiddenCount => _hidden.length;

  // ── Merged editions ───────────────────────────────────────────────────────
  // Splitting is a guess made from tags; merging is the user telling us the guess was wrong.
  // Their word is final and has to outlive a rescan, so it is written down like every other
  // correction rather than held in memory.
  final Set<String> _merged = {};
  File get _mergedFile => File('$_appDir${Platform.pathSeparator}merged_albums.json');

  Future<void> loadMerged() async {
    try {
      final f = _mergedFile;
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as List<dynamic>;
      _merged
        ..clear()
        ..addAll(j.map((e) => e.toString()));
    } catch (_) {}
  }

  Future<void> _saveMerged() => _writeJson(_mergedFile, _merged.toList());

  /// Put every edition of this record back together, and keep it that way.
  Future<void> mergeEditions(Album a) async {
    if (isRemote) return _editOnPc({'op': 'merge', 'albumId': remoteAlbumId(a)});
    _merged.add('album::${artistKey(a.artist)}|${normKey(a.title)}');
    await _saveMerged();
    rebuildAlbums();
    notifyListeners();
  }

  /// Undo that, and let the tags decide again.
  Future<void> unmergeEditions(Album a) async {
    if (isRemote) return _editOnPc({'op': 'unmerge', 'albumId': remoteAlbumId(a)});
    _merged.remove('album::${artistKey(a.artist)}|${normKey(a.title)}');
    await _saveMerged();
    rebuildAlbums();
    notifyListeners();
  }

  /// Has the user told us to keep this record together?
  bool isMerged(Album a) => isRemote
      // The merged set lives on the PC, so on a client the answer comes down with the catalogue.
      // Without this the control offers to merge a record that already is.
      ? (_remoteAlbums[a]?.merged ?? false)
      : _merged.contains('album::${artistKey(a.artist)}|${normKey(a.title)}');

  /// The exact Discogs release the user pinned to this album, if they pinned one.
  ///
  /// Their choice is the source for everything after it — edition, label, catalogue number, back
  /// cover and disc — instead of the app going off and picking its own pressing, which is why a
  /// correction changed the front cover and nothing else.
  int? pinnedRelease(Album a) {
    // In client mode the corrections live on the PC and never reach here — the pin comes down with
    // the catalogue instead. Without this the sleeve looks up its disc by artist and title, which
    // finds the wrong pressing for exactly the records that were pinned because it did.
    if (isRemote) return _remoteAlbums[a]?.release;
    for (final t in a.tracks) {
      final id = int.tryParse(_corrections[t.path]?['release'] ?? '');
      if (id != null && id > 0) return id;
    }
    return null;
  }

  /// The MusicBrainz pressing the user pinned, if they pinned one there instead.
  ///
  /// Its own key rather than sharing [pinnedRelease]'s: an MBID is a string and a Discogs id is a
  /// number, and every pin already written to disk is a number. One key for both would have made
  /// those unreadable the first time this shipped.
  String? pinnedMbid(Album a) {
    if (isRemote) return _remoteAlbums[a]?.mbid;
    for (final t in a.tracks) {
      final id = _corrections[t.path]?['mbid'];
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  // ── Which scan is which ───────────────────────────────────────────────────
  // Discogs says only "primary" or "secondary", never what an image SHOWS, so the app works the
  // roles out from shape and pixels — and gets them wrong often enough to be worth a way out.
  // Measured on Random Access Memories: eight of its fourteen scans are wider than tall, and the
  // rule for a rear inlay is "wider than tall", so a booklet spread was being shown as the back.
  //
  // This is where the user's own answer lives. Same shape as the artist art below, and for the
  // same reason: a hand-made choice must outlive a rescan and must never be quietly overruled.
  final Map<String, Map<String, String>> _albumArtRoles = {};
  File get _albumArtRolesFile => File('$_appDir${Platform.pathSeparator}album_art_roles.json');

  Future<void> loadAlbumArtRoles() async {
    try {
      final f = _albumArtRolesFile;
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _albumArtRoles.clear();
      j.forEach((k, v) {
        if (v is Map) _albumArtRoles[k] = v.map((a, b) => MapEntry(a.toString(), b.toString()));
      });
    } catch (_) {}
  }

  static String albumArtKey(String artist, String album) =>
      '${artistKey(artist)}|${normKey(album)}';

  /// The images the user assigned for this record: 'front', 'back' and/or 'disc' → image URL.
  ///
  /// Empty when they never said — which is the normal case, and means the guesses stand.
  ///
  /// Op een telefoon, een iPad, een Mac of de tv komen ze met de CATALOGUS mee in plaats van uit een
  /// bestand op dat toestel. Dat was het gat: `album_art_roles.json` bleef staan waar de keuze
  /// gemaakt was, dus de cd die je op de iPad aanwees bestond nergens anders. Een vastgezette
  /// persing en een samengevoegde editie reisden hier al jaren wel mee.
  ///
  /// Op een client eerst wat de pc zegt, en anders wat hier ligt. Die terugval is er voor een pc die
  /// deze bewerking nog niet kent: dan reist de keuze niet mee, maar hij blijft wél bestaan op het
  /// toestel waar je hem maakte — precies zoals het vóór de synchronisatie werkte.
  Map<String, String> albumArtRoles(String artist, String album) {
    final k = albumArtKey(artist, album);
    if (isRemote) {
      final vanPc = _remoteAlbumRoles[k];
      if (vanPc != null && vanPc.isNotEmpty) return vanPc;
    }
    return _albumArtRoles[k] ?? const {};
  }

  /// De aangewezen scans zoals de pc ze kent, op een toestel dat de muziek niet bezit.
  final Map<String, Map<String, String>> _remoteAlbumRoles = {};

  /// Pin a front cover by hand, and have every screen show it at once.
  ///
  /// Separate from [applyCorrection], which also rewrites titles and the pinned pressing: choosing a
  /// sleeve from one edition while keeping another edition's disc is a picture decision, not a
  /// re-identification of the record.
  ///
  /// Written to [Album.correctedCover] rather than left to the album page to fetch, because that is
  /// what makes it INSTANT everywhere. The grid, the player bar, the now-playing screen and the
  /// Tracks list all read Album.cover, where a corrected cover outranks everything; the notify then
  /// reaches all of them in the same frame. A role alone would only have changed the page you were
  /// standing on.
  Future<void> setAlbumCover(Album a, AppSettings settings, Uint8List bytes) async {
    if (bytes.isEmpty) return;
    // De pc houdt de boeken bij — ook voor de hoes.
    //
    // **Dit ontbrak, en het is precies de klacht "twee verschillende hoezen".** Op een Mac, een
    // iPad of een telefoon schreef dit alleen naar het geheugen en de cache van dát toestel. Kies
    // je de juiste hoes op de Mac, dan blijft hij daar: de pc weet van niets, en je telefoon haalt
    // zijn hoezen van de pc. Twee toestellen, twee antwoorden, en corrigeren hielp niet omdat de
    // correctie nooit aankwam waar hij gelezen wordt.
    //
    // Anders dan bij een rol gaan hier BYTES over de lijn en geen adres, want een gekozen hoes is
    // niet altijd een adres — hij kan uit een bestand of uit de tags komen. Daarom base64 en niet
    // een url.
    //
    // Altijd eerst HIER, dan pas naar de pc. Die volgorde is geen detail: kent de pc deze bewerking
    // nog niet — hij draait een oudere versie, want toestellen werken zich niet tegelijk bij — dan
    // gooit de tweede stap, en zonder de eerste zou je keuze wég zijn. Lokaal is de bodem, de pc is
    // de winst.
    a.correctedCover = bytes;
    try {
      await CoverEnricher(settings).saveFixedCover(a, bytes);
    } catch (e) {
      // The choice already shows; not being able to cache it only costs a fetch next start.
      debugPrint('Could not save the chosen cover: $e');
    }
    _bumpMeta();
    notifyListeners();
    if (isRemote) {
      final id = remoteAlbumId(a);
      if (id == null) return;
      await _editOnPc({'op': 'albumCover', 'albumId': id, 'cover': base64Encode(bytes)});
    }
  }

  /// Say what an image IS. [url] empty clears that role and lets the app guess again.
  Future<void> setAlbumArtRole(String artist, String album, String role, String url) async {
    // Op een client: HIER schrijven én het aan de pc vertellen. In die volgorde, en allebei.
    //
    // **Waarom niet alleen naar de pc.** Dat was de eerste opzet, en het was een terugval. Kent de
    // pc die bewerking niet — hij draait een oudere versie, want toestellen werken zich niet op
    // hetzelfde moment bij — dan gooide dit, en was de keuze wég. Terwijl hij daarvóór gewoon lokaal
    // werkte. Een verbetering die het bij een oudere pc slechter maakt, is geen verbetering.
    //
    // Nu: lokaal is de bodem die er altijd is, de pc is de winst als hij meedoet. Weigert hij, dan
    // komt die reden naar boven — de aanroeper mag weten dat het bij dit toestel blijft — maar de
    // keuze zelf staat er al.
    final k = albumArtKey(artist, album);
    final m = _albumArtRoles.putIfAbsent(k, () => {});
    if (url.isEmpty) {
      m.remove(role);
      if (m.isEmpty) _albumArtRoles.remove(k);
    } else {
      // One image cannot be two things. Assigning it to a second role takes it off the first,
      // rather than leaving the same scan claiming to be both the back and the disc.
      m.removeWhere((_, v) => v == url);
      m[role] = url;
    }
    await _saveAlbumArtRoles();
    notifyListeners();
    if (isRemote) {
      await _editOnPc(
          {'op': 'albumArtRole', 'artist': artist, 'album': album, 'role': role, 'url': url});
    }
  }

  /// Forget every hand-picked scan for this record, so the pressing decides again.
  ///
  /// One write and one notify instead of three: the caller used to set each role to empty in turn,
  /// which saved and rebuilt the whole album grid once per role.
  ///
  /// Called when a whole EDITION is chosen, and that is the point of it. A role outranks the pinned
  /// pressing — that is what makes it an override — so a front cover picked from the digital release
  /// went on winning after you deliberately chose the CD, and choosing an edition looked like it did
  /// nothing. Picking an edition means "use its scans"; picking a single scan is the exception you
  /// make afterwards.
  Future<void> clearAlbumArtRoles(String artist, String album) async {
    // Zelfde verhaal als bij [setAlbumArtRole]: lokaal wissen is de bodem, de pc is de winst.
    //
    // De vroege uitgang is hier bewust weg. Lokaal kan er niets staan terwijl de pc nog wél rollen
    // heeft — dan zou "wis alles" op een client niets doen, en na de eerstvolgende synchronisatie
    // stonden ze er weer.
    _albumArtRoles.remove(albumArtKey(artist, album));
    await _saveAlbumArtRoles();
    notifyListeners();
    if (isRemote) {
      await _editOnPc({'op': 'albumArtRole', 'artist': artist, 'album': album, 'clear': true});
    }
  }

  Future<void> _saveAlbumArtRoles() => _writeJson(_albumArtRolesFile, _albumArtRoles);

  // ── Chosen artist art ─────────────────────────────────────────────────────
  // Which portrait and which backdrop the user picked for an artist. Kept beside the other
  // corrections for the same reason: the choice has to outlive a rescan, and must never be quietly
  // replaced by whatever an automatic source turns up next.
  final Map<String, Map<String, String>> _artistArtChoice = {};
  File get _artistArtChoiceFile => File('$_appDir${Platform.pathSeparator}artist_art_choice.json');

  Future<void> loadArtistArtChoice() async {
    try {
      final f = _artistArtChoiceFile;
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _artistArtChoice.clear();
      j.forEach((k, v) {
        if (v is Map) _artistArtChoice[k] = v.map((a, b) => MapEntry(a.toString(), b.toString()));
      });
    } catch (_) {}
  }

  /// The image URL the user picked for [kind] — 'portrait' or 'backdrop' — or null.
  String? chosenArtistArt(String artist, String kind) {
    // A statement body rather than an arrow: `cond ? a?[k] : b` makes the parser read that second
    // `?` as another conditional, and no amount of bracketing round the map reads well enough to
    // be worth it.
    final choice = isRemote ? _remoteArtistArt[artistKey(artist)] : _artistArtChoice[artistKey(artist)];
    return choice?[kind];
  }

  /// Wie deze artiest IS, in beeld. [url] leeg laat de app weer zelf kiezen.
  ///
  /// **Op een telefoon moet dit naar de pc.** [chosenArtistArt] leest op een client uit
  /// `_remoteArtistArt` — dat komt met de catalogus mee — terwijl dit hier lokaal wegschreef. Een
  /// keuze die je op het toestel maakte belandde dus in een bestandje dat niemand meer las: de foto
  /// sprong meteen terug en het leek alsof de knop niets deed. Precies dezelfde vorm als de
  /// albumhoes, die daarom al over [_editOnPc] gaat.
  Future<void> setArtistArt(String artist, String kind, String url) async {
    if (isRemote) {
      return _editOnPc({'op': 'artistArt', 'artist': artist, 'kind': kind, 'url': url});
    }
    _artistArtChoice.putIfAbsent(artistKey(artist), () => {})[kind] = url;
    await _writeJson(_artistArtChoiceFile, _artistArtChoice);
    notifyListeners();
  }

  // ── Styles ────────────────────────────────────────────────────────────────
  // A Discogs style is far finer than a genre: an album is not just "Electronic" but "House,
  // Disco, Synth-pop". That is what makes browsing by feel possible instead of by category, so
  // styles are remembered as albums are opened and the map fills in as the app gets used.
  final Map<String, List<String>> _styles = {};
  File get _stylesFile => File('$_appDir${Platform.pathSeparator}album_styles.json');

  Future<void> loadStyles() async {
    try {
      final f = _stylesFile;
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _styles.clear();
      j.forEach((k, v) {
        if (v is List) _styles[k] = [for (final x in v) x.toString()];
      });
    } catch (_) {}
  }

  String _styleKey(String artist, String album) => '${artistKey(artist)}|${normKey(album)}';

  List<String> stylesOf(Album a) =>
      isRemote ? (_remoteAlbums[a]?.styles ?? const []) : (_styles[_styleKey(a.artist, a.title)] ?? const []);

  /// Remember what a record sounds like, found while its page was open.
  Future<void> rememberStyles(String artist, String album, List<String> styles) async {
    if (styles.isEmpty) return;
    final k = _styleKey(artist, album);
    if (_styles[k]?.join() == styles.join()) return;
    _styles[k] = styles;
    await _saveStyles();
    notifyListeners();
  }

  Future<void> _saveStyles() => _writeJson(_stylesFile, _styles);

  /// Every style seen so far, most common first — the vocabulary this library actually uses.
  List<MapEntry<String, int>> styleTally() {
    final n = <String, int>{};
    for (final a in albums) {
      for (final st in stylesOf(a)) {
        n.update(st, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    final out = n.entries.toList();
    out.sort((x, y) => y.value.compareTo(x.value));
    return out;
  }

  /// The albums that share a style.
  List<Album> albumsWithStyle(String style) =>
      albums.where((a) => stylesOf(a).any((s) => s.toLowerCase() == style.toLowerCase())).toList();

  /// Heb je dit nummer al lossless, waar in de bibliotheek het ook staat?
  ///
  /// De vraag die een staande FLAC-wens laat vervallen, en hij moet over de HELE bibliotheek gaan --
  /// niet binnen het album waar het nummer voor bedoeld was. Gemeten geval: de gebruiker haalde de
  /// FLAC met de native Soulseek-client binnen, en die landde in een map die naar de peer heet, onder
  /// de albumnaam "De Ultieme Belgie-Holland Top 100" in plaats van de plaat waar de mp3 in staat.
  /// Binnen het album zoeken had hem gemist, en dan blijft de app eeuwig jagen op iets wat al op
  /// schijf staat -- en biedt hij het bovendien aan om te downloaden.
  ///
  /// Via [trackIdentity], dus versiemarkeringen blijven staan: "Trein (instrumentaal)" vervult de wens
  /// naar "Trein" niet. Een verzamelaar waar de artiest-tag "Various Artists" zegt en de uitvoerder in
  /// PERFORMER staat wordt hier niet gevonden; dat is een bekende ondergrens en geen stille aanname.
  bool hasLossless(String artist, String title) {
    final gezocht = trackIdentity(artist, title);
    for (final t in tracks) {
      if (!t.isFlac) continue;
      if (trackIdentity(t.artist, t.title) == gezocht) return true;
    }
    return false;
  }

  /// Hand the library a cover found while an album page was open.
  ///
  /// The album page draws its own sleeve from Discogs, so a wrong embedded cover was corrected
  /// there and nowhere else: opening the album showed the right art, going back to the grid
  /// showed the old one. Now the correction reaches the library the moment it is found.
  ///
  /// Never over one the user picked by hand.
  ///
  /// [from] says which release this is the sleeve OF — `rel:12345`, `mb:<uuid>`. Pass it only when
  /// a pressing was actually identified, and the art is filed as [Album.resolvedCover], which
  /// outranks whatever is embedded in the files. Leave it null for a search-by-name guess, which is
  /// filed as [Album.enriched] and stays below the embedded cover.
  ///
  /// That distinction is the whole fix. Everything used to land in `enriched`, which loses to
  /// `embeddedCover`, so for any record whose files carry a wrong sleeve this method appeared to
  /// work and changed nothing anyone could see: the album page had the right art because it drew
  /// its own, and one step back to the grid showed the old one again.
  /// [settings] is what lets the art be WRITTEN DOWN, and without it this correction lasts exactly
  /// as long as the app stays open. That was the shape of the D'Eux bug: its files carry the sleeve
  /// of a Greatest Hits, opening the album put the real one on the grid, and closing the app threw
  /// it away — so the same record was wrong again every morning and right every time it was checked.
  /// Geeft terug of er werkelijk iets veranderd is.
  ///
  /// **Waarom dat niet vanzelfsprekend is.** Deze methode slaat een album over dat een eigenhandig
  /// gekozen hoes heeft, en ze slaat een hoes over die er al precies zo staat. De aanroeper ziet dat
  /// niet, en de verwarmer schrijft er een regel over in het logboek. Zonder dit antwoord zou daar
  /// "hoes overgenomen" staan voor een plaat waar niets aan veranderd is — en dan is dat logboek
  /// geen bewijs meer maar ruis, precies op de plek waar je het straks nodig hebt om uit te zoeken
  /// wélke plaat van hoes wisselde.
  bool adoptAlbumCover(String artist, String album, Uint8List bytes,
      {String? from, AppSettings? settings}) {
    if (bytes.length < 500) return false;
    var changed = false;
    for (final a in albums) {
      if (a.tracks.isEmpty) continue;
      if (artistKey(a.artist) != artistKey(artist) || normKey(a.title) != normKey(album)) continue;
      if (a.correctedCover != null) continue;
      if (from != null) {
        if (identical(a.resolvedCover, bytes) && a.resolvedFrom == from) continue;
        a.resolvedCover = bytes;
        a.resolvedFrom = from;
        // Only a traced sleeve is kept: it belongs to a named pressing, so it is a fact about the
        // record. A by-name guess is not, and one saved guess would outrank the files forever.
        if (settings != null) {
          unawaited(CoverEnricher(settings).saveResolvedCover(a, bytes, from));
        }
      } else {
        if (identical(a.enriched, bytes)) continue;
        a.enriched = bytes;
      }
      changed = true;
    }
    if (changed) notifyListeners();
    return changed;
  }

  /// Un-hide everything: the files are still on disk, so a rescan restores them.
  Future<void> restoreHidden() async {
    _hidden.clear();
    await _saveHidden();
    await scan();
  }

  /// Remove tracks from the library. With [fromDisk] the files are DELETED permanently;
  /// otherwise they're only excluded from the library and stay on disk.
  /// Returns how many files were actually deleted from disk.
  Future<int> removeTracks(Iterable<String> paths, {required bool fromDisk}) async {
    if (isRemote) {
      final ids = [
        for (final p in paths)
          if (_remoteTrackId(p) case final id?) id,
      ];
      await _editOnPc({'op': 'removeTracks', 'trackIds': ids, 'fromDisk': fromDisk});
      // What the PC deleted from disk is its count to give; the caller only shows it.
      return fromDisk ? ids.length : 0;
    }
    final list = paths.toList();
    var deleted = 0;
    // De mappen waar iets uit weggehaald is. Een map die daardoor leegloopt hoort niet te blijven
    // staan: een radio van vijfhonderd nummers laat anders honderden lege `Singles/<Artiest>`-mappen
    // achter, en die zie je pas als je zelf in je muziekmap gaat kijken.
    final mappen = <String>{};
    if (fromDisk) {
      for (final p in list) {
        try {
          final f = File(p);
          if (await f.exists()) {
            mappen.add(f.parent.path);
            await f.delete();
            deleted++;
            // Het bestand is weg, dus de meting slaat nergens meer op. Zonder dit blijft ze staan
            // en telt "701 onderzocht" spoken mee — en erger: een pad dat later opnieuw gebruikt
            // wordt zou het oordeel van een héél ander bestand erven.
            vergeetOordeel(p);
            // En om precies dezelfde reden de bescherming: een pad dat later opnieuw gebruikt wordt
            // zou anders erven dat JIJ het gekozen had, en dan wint een wildvreemd bestand van alles
            // wat de app erover weet. Sinds een torrentdownload ook een vaste keuze is, is dat geen
            // theoretisch geval meer: die lijst groeit met elk nummer dat je binnenhaalt.
            unawaited(vergeetVasteKeuze(p));
          }
        } catch (_) {/* locked/permission — leave it, it stays visible */}
      }
      // Files are gone, so they can't come back on a rescan; no need to remember them.
      _hidden.removeAll(list);
      for (final m in mappen) {
        // Neemt ook de artiestenmap erboven mee als die daardoor leeg raakt, en stopt bij de wortel.
        try {
          await pruneVacated(m, rootPath);
        } catch (_) {/* een map die niet weg wil is geen reden om het wissen te laten mislukken */}
      }
    } else {
      _hidden.addAll(list);
    }
    await _saveHidden();
    tracks.removeWhere((t) => list.contains(t.path));
    rebuildAlbums();
    _bumpMeta();
    notifyListeners();
    return deleted;
  }

  /// Read the hand-made metadata. Reads only — it never decides anything is gone.
  ///
  /// This used to drop every entry whose file it could not stat, and then write the result back.
  /// With the music drive not mounted — a NAS still waking up, an external disk unplugged, a drive
  /// letter that changed — every path fails that check at once, and months of hand-made metadata is
  /// overwritten with an empty file, silently, before the user has clicked anything. Forgetting is
  /// now [_sweepCorrections]'s job, and it only runs after a scan that actually found music.
  Future<void> loadCorrections() async {
    try {
      final f = _correctionsFile;
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _corrections.clear();
      for (final e in j.entries) {
        final v = e.value;
        if (v is! Map) continue;
        _corrections[e.key] = v.map((k, val) => MapEntry(k.toString(), val.toString()));
      }
      final samengevoegd = _voegHoofdletterDubbelsSamen();
      _correctionsUnreadable = false;
      // Ook wegschrijven, anders staat de dubbele regel er bij de volgende start gewoon weer en is
      // hij alleen in het geheugen opgeruimd. Ná het vrijgeven van [_correctionsUnreadable], want
      // [_saveCorrections] weigert te schrijven zolang die vlag staat — en terecht.
      if (samengevoegd) await _saveCorrections();
    } catch (e) {
      // The file is there and unreadable. Say so, and refuse to write over it — see
      // [_correctionsUnreadable]. Swallowing this is what turned one bad read into total loss: the
      // next edit wrote an almost-empty map over months of work without a word.
      debugPrint('corrections.json unreadable, refusing to overwrite it: $e');
      _correctionsUnreadable = true;
    }
  }

  /// Op Windows en macOS is `Foo.flac` hetzelfde bestand als `foo.flac`; in een tekstvergelijking niet.
  ///
  /// Dat verschil kostte bijna een vastgezette persing. Gemeten in Sabers corrections.json stonden
  /// twee regels voor één bestand — `09 - The Lady in My Life.flac` en `… In My Life.flac` — en de
  /// tweede droeg `release: 2911293`. De eerste was een wees van een hernoeming, en [_sweepCorrections]
  /// vergeleek letterlijk (`live.contains(e.key)`), zag hem niet in de scan en zette er een
  /// `_gone`-stempel op. Negentig dagen later was hij weg geweest. Was de wees toevallig degene met de
  /// pin geweest, dan was díé verdwenen.
  // Eén vouw voor de hele app, in paths.dart. Stond hier als privékopie, en toen [AlbumUids.prune]
  // de andere kant van diezelfde vergelijking werd, had die er geen weet van — dat wiste het hele
  // pad→uid-register bij elke scan.
  static bool get _padenZijnHoofdletterOngevoelig => padenZijnHoofdletterOngevoelig;

  static String _padSleutel(String p) => padSleutel(p);

  /// Twee regels voor hetzelfde bestand samenvoegen tot één, onder de naam die op schijf staat.
  ///
  /// Bij het inlezen, want dan is het één keer werk in plaats van bij elke opzoeking. De schijf beslist
  /// welke schrijfwijze wint: alleen die komt in de scan terug, en een sleutel die de scan nooit ziet
  /// wordt vroeg of laat opgeruimd. Is het bestand er niet meer, dan wint de regel met de meeste
  /// inhoud — dan valt er niets beters te kiezen.
  /// Geeft terug of er iets veranderd is, zodat de aanroeper het ook kan bewaren.
  bool _voegHoofdletterDubbelsSamen() {
    if (!_padenZijnHoofdletterOngevoelig) return false;
    var veranderd = false;
    final perSleutel = <String, List<String>>{};
    for (final p in _corrections.keys) {
      perSleutel.putIfAbsent(_padSleutel(p), () => []).add(p);
    }
    for (final groep in perSleutel.values) {
      if (groep.length < 2) continue;
      // Welke schrijfwijze staat er werkelijk op schijf? `File.existsSync` antwoordt hier op beide
      // ja, dus dat helpt niet — de map opsommen wel.
      String? echt;
      try {
        final map = Directory(File(groep.first).parent.path);
        for (final f in map.listSync()) {
          if (_padSleutel(f.path) == _padSleutel(groep.first)) {
            echt = f.path;
            break;
          }
        }
      } catch (_) {/* map weg: dan beslist de inhoud hieronder */}
      final winnaar = groep.firstWhere((p) => p == echt,
          orElse: () => groep.reduce((a, b) =>
              _corrections[a]!.length >= _corrections[b]!.length ? a : b));
      final samen = <String, String>{};
      for (final p in groep) {
        // De winnaar als laatste, zodat zijn waarden bovenliggen bij een botsing.
        if (p != winnaar) samen.addAll(_corrections[p]!);
      }
      samen.addAll(_corrections[winnaar]!);
      // Het stempel "dit bestand is weg" hoort niet mee te verhuizen: hij stond er juist omdát de
      // andere schrijfwijze niet gevonden werd.
      if (echt != null) samen.remove(_goneKey);
      for (final p in groep) {
        _corrections.remove(p);
      }
      _corrections[winnaar] = samen;
      veranderd = true;
      debugPrint('corrections: ${groep.length} regels samengevoegd tot $winnaar');
    }
    return veranderd;
  }

  /// How long a file may be missing before its correction is forgotten.
  static const int _correctionGraceDays = 90;

  /// When a correction's file was first noticed missing. Inert everywhere else: [_applyCorrection]
  /// and the pin readers ask for named keys, so an extra one changes nothing.
  static const String _goneKey = '_gone';

  /// Forget corrections for files that have been gone for a season.
  ///
  /// An album moved or re-ripped leaves its old corrections behind, and they do cause real
  /// confusion — Adele's 30 had fifteen live pins under one folder and fifteen dead, empty ones
  /// under a deleted Japanese edition. So they do get cleaned up; just never on the evidence of a
  /// single failed stat, and never on a scan that found nothing at all.
  Future<void> _sweepCorrections() async {
    // An empty library is not evidence that the music is gone. It is evidence that we cannot see it.
    if (tracks.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Hidden tracks are excluded from `tracks` but their files are still there — "remove from
    // library only" must not quietly become "forget what I typed about it".
    // Hoofdletterongevoelig op Windows en macOS: daar is één verschil in schrijfwijze geen ander
    // bestand, en een letterlijke vergelijking zou een levend bestand als verdwenen bestempelen.
    final live = <String>{
      for (final t in tracks) _padSleutel(t.path),
      for (final p in _hidden) _padSleutel(p),
    };
    final drop = <String>[];
    var changed = false;
    for (final e in _corrections.entries) {
      if (live.contains(_padSleutel(e.key))) {
        if (e.value.remove(_goneKey) != null) changed = true; // it came back
        continue;
      }
      // Nothing but a timestamp is not a correction worth keeping.
      if (e.value.keys.every((k) => k == _goneKey)) {
        drop.add(e.key);
        continue;
      }
      final since = int.tryParse(e.value[_goneKey] ?? '');
      if (since == null) {
        e.value[_goneKey] = '$now';
        changed = true;
      } else if (now - since > _correctionGraceDays * 86400000) {
        drop.add(e.key);
      }
    }
    for (final p in drop) {
      _corrections.remove(p);
      changed = true;
    }
    if (changed) await _saveCorrections();

    // Same moment, same evidence: this scan saw the music, so a path it did not see is gone rather
    // than merely unreachable. Hidden tracks count as present here too.
    uids.prune(live);

    // En dan de feiten die bij geen enkel album meer horen. NA `uids.prune`, want de uid's van de
    // albums die er nog zijn moeten eerst vaststaan; en alleen als er albums zijn, want een lege
    // lijst is "ik weet het niet", niet "er is niets".
    if (albums.isNotEmpty) {
      final levend = {for (final a in albums) uids.uidOf(a)}..removeWhere((u) => u.isEmpty);
      if (levend.isNotEmpty) {
        final weg = facts.prune(levend);
        if (weg > 0) meetlog?.call('  scan/feiten: $weg wezen opgeruimd, ${levend.length} albums over');
      }
    }
  }

  /// The correction map for a path, created on demand — so an extension can add to it.
  ///
  /// Bestaat er al een regel die alleen in schrijfwijze verschilt, dan is dat DEZELFDE regel: op
  /// Windows en macOS wijzen ze naar één bestand. Zonder deze controle groeit er bij elke hernoeming
  /// een tweede regel aan, en dan hangt het van het toeval af welke van de twee je pin draagt.
  Map<String, String> _correctionsFor(String path) {
    if (_padenZijnHoofdletterOngevoelig && !_corrections.containsKey(path)) {
      final sleutel = _padSleutel(path);
      for (final bestaand in _corrections.keys) {
        if (_padSleutel(bestaand) == sleutel) return _corrections[bestaand]!;
      }
    }
    return _corrections.putIfAbsent(path, () => {});
  }

  /// Carry a file's corrections to where the file now is.
  ///
  /// Corrections are keyed by absolute path, so a move silently orphans them: the entry stays under
  /// the old name, [_applyCorrection] looks under the new one and finds nothing, and
  /// [loadCorrections] deletes it as a dead file at the next start. A track moved into another
  /// album would end up with its FILE in the new folder and its GROUPING back in the old one —
  /// worse than either half alone, and it would have taken the album's pinned release with it.
  void _reKeyCorrection(String from, String to) {
    if (from == to) return;
    // The album's identity is held against its files too, and for the same reason: a move the app
    // performed itself would otherwise read as a brand-new record.
    uids.reKey(from, to);
    final old = _corrections.remove(from);
    if (old == null || old.isEmpty) return;
    _corrections.putIfAbsent(to, () => {}).addAll(old);
  }

  /// Public save, for the move extension.
  Future<void> saveCorrectionsNow() => _saveCorrections();

  /// Re-apply every correction to the in-memory tracks and regroup.
  ///
  /// Public because the extensions in this file write corrections and then need the library to
  /// reflect them; notifyListeners is protected, so an extension cannot do the last step itself.
  void refreshFromCorrections() {
    final corrected = tracks.map(_applyCorrection).toList();
    tracks
      ..clear()
      ..addAll(corrected);
    rebuildAlbums();
    _bumpMeta();
    notifyListeners();
  }

  /// Write one of this store's JSON files so it is never left half-written.
  ///
  /// `writeAsString` truncates first and fills after, so anything that interrupts that window — a
  /// full disk, an antivirus or sync tool holding the handle, the process going away — leaves
  /// truncated JSON behind. Six files were written that way, and one of them is corrections.json:
  /// every hand-made edit in this library, 213 of them here. The failure was swallowed whole, so the
  /// dialog said the correction had been saved while nothing had reached the disk.
  ///
  /// tmp-then-rename is what the rest of the app's state already does — settings.dart, album_id,
  /// album_facts, lan/state_store, lan/tokens — so these six were a forgotten corner, not a choice.
  /// A rename is atomic: either the old file is there or the new one is, never half of either.
  Future<bool> _writeJson(File f, Object data) async {
    try {
      await Directory(_appDir).create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(data));
      await tmp.rename(f.path);
      return true;
    } catch (e) {
      debugPrint('${f.path} not written: $e');
      return false;
    }
  }

  /// Set when corrections.json was there but could not be read.
  ///
  /// The pairing with [_writeJson] is what makes the guarantee whole. Atomic writes stop a crash
  /// from truncating the file; this stops the app from calmly overwriting a file it failed to parse
  /// with the near-empty map it has in memory. One bad read used to be enough to lose the lot on the
  /// next edit. Note that an EMPTY corrections.json is perfectly normal on a fresh install, so
  /// emptiness is not the signal — a failed parse is.
  bool _correctionsUnreadable = false;

  /// True when hand-made corrections exist on disk that this session could not read. The UI can say
  /// so instead of letting the user work on top of a file that is about to be replaced.
  bool get correctionsUnreadable => _correctionsUnreadable;

  Future<void> _saveCorrections() async {
    if (_correctionsUnreadable) {
      debugPrint('Refusing to save: corrections.json could not be read this session');
      return;
    }
    await _writeJson(_correctionsFile, _corrections);
  }

  /// Eén bestand erbij, zonder de hele bibliotheek opnieuw te lezen.
  ///
  /// **Waarom dit bestaat.** Elke download eindigt vandaag op `onLibraryChanged`, en dat is een
  /// volledige [scan]: de hele muziekmap doorlopen, elk bestand statten, alles hergroeperen. Voor een
  /// download per paar minuten is dat prima. Voor een radio die er acht per kwartier binnenhaalt is
  /// het een scan die vrijwel permanent draait, en een scan die permanent draait maakt de app
  /// schokkerig terwijl je juist naar muziek luistert.
  ///
  /// Geeft het nummer terug zoals het in de bibliotheek staat — met correctie erop — of null als er
  /// niets leesbaars in het bestand stond. Een pad dat er al in staat wordt VERVANGEN en niet
  /// toegevoegd: twee rijen met hetzelfde pad breekt elke opzoeking die op pad werkt, en dat zijn er
  /// nogal wat (de hoes, het album, de speeltelling).
  Future<Track?> voegBestandToe(String pad) async {
    // Op een gekoppeld toestel staat de bibliotheek op de pc; daar is niets toe te voegen.
    if (isRemote) return null;
    if (_hidden.contains(pad)) return null;
    Map<String, dynamic>? rij;
    try {
      rij = await leesTagrijInIsolate(pad);
    } catch (_) {
      return null;
    }
    if (rij == null) return null;
    final t = _applyCorrection(_trackFromMap(rij));
    final al = tracks.indexWhere((x) => x.path == pad);
    if (al >= 0) {
      tracks[al] = t;
    } else {
      tracks.add(t);
    }
    scanned = tracks.length;
    rebuildAlbums();
    _bumpMeta();
    notifyListeners();
    return t;
  }

  Track _applyCorrection(Track t) {
    final c = _corrections[t.path];
    if (c == null) return t;
    return Track(
      path: t.path,
      title: c['title'] ?? t.title,
      artist: c['artist'] ?? t.artist,
      album: c.containsKey('album') ? c['album']! : t.album,
      // A number taken from an official pressing. The tags are what these override: a ripper that
      // wrote two number sixes and left a track blank is exactly the case this exists for.
      trackNo: int.tryParse(c['trackNo'] ?? '') ?? t.trackNo,
      trackTotal: int.tryParse(c['trackTotal'] ?? '') ?? t.trackTotal,
      duration: t.duration,
      isFlac: t.isFlac,
      year: t.year,
      genre: t.genre,
      addedMs: t.addedMs,
      sizeBytes: t.sizeBytes,
      sampleRate: t.sampleRate,
      bitsPerSample: t.bitsPerSample,
    );
  }

  /// Apply a manual correction to [target] (artist/album for an album, title for a
  /// single) and optionally a user-picked cover. Persisted + reflected immediately.
  /// Wat de gebruiker typte ook IN HET BESTAND zetten, niet alleen in corrections.json.
  ///
  /// Saber: "ik heb de tag bewerkt, maar toch blijven de originele tags erin." Dat klopte letterlijk.
  /// Het potlood schreef uitsluitend naar `corrections.json`; de app tóónde zijn tekst en het bestand
  /// hield die van de uploader. Zet je de map in Roon of op een telefoon, dan was zijn werk onzichtbaar.
  ///
  /// Alleen de velden die hij daadwerkelijk invulde, en langs dezelfde weg als [applyNormalise] — dus
  /// mét [_tagUndo], zodat de undo-knop ook hier werkt. De correctie blijft óók staan: schrijven kan
  /// mislukken (bestand op slot, of geen `.flac`/`.mp3` — [writeTagFields] weigert de rest), en dan is
  /// de correctie het enige vangnet. Aanvulling, geen vervanging.
  /// Welke velden een correctie mag zetten, gegeven waar hij over gaat.
  ///
  /// **Waarom dit een eigen functie is en geen twee `if`s.** Het is de regel die drie keer voorkomt
  /// — in de tags, in de correctie op schijf en in de naam waaronder de plaat straks komt te staan —
  /// en die op alle drie de plekken hetzelfde moet luiden. Loopt er één uit de pas, dan wordt een
  /// bestand anders getagd dan het in de app heet, en dat merk je pas als je buiten de app kijkt.
  ///
  /// De regel zelf:
  ///
  ///  * ALBUM zetten mag bij een gewone plaat. Bij een single niet: die heeft geen album om te
  ///    zetten. Maar wijst iemand één nummer aan, dan is de plaat juist waar het om gaat — dat is
  ///    de hele reden dat die knop bestaat.
  ///  * TITLE zetten mag bij een single, want daar is er precies één. Bij een meersporig album niet:
  ///    dan zou dezelfde titel op elk nummer landen, en dat is geen bewerking maar schade. Bij één
  ///    aangewezen nummer is er weer precies één, dus dan mag het weer.
  @visibleForTesting
  static ({bool album, bool titel}) veldenBijCorrectie(
          {required bool isSingle, required bool perNummer}) =>
      (album: !isSingle || perNummer, titel: isSingle || perNummer);

  /// De tags die van de OUDE plaat kwamen en na een verhuizing niet meer waar zijn.
  ///
  /// **Waarvoor dit bestaat.** Gemeld op 28-08-2026, met "La Salsa" als voorbeeld: *"hij zet de
  /// track wel ergens anders, maar de metadata gaat mee van de album waar in hij zat, dat klopt
  /// niet. De metadata moet mee veranderen."* Dat klopte letterlijk. De correctie zette ARTIST,
  /// ALBUM en TITLE, en liet alles staan wat de OUDE persing beschreef — dus stond "La Salsa" op
  /// zijn nieuwe tegel als nummer 7 van 14, met het jaartal van *Partir un jour*.
  ///
  /// **Waarom wissen en niet overnemen.** Wat het nummer op zijn nieuwe plaat WÉL is, weet niemand
  /// hier: dat staat in de tracklijst van de persing die je zojuist aanwees, en die is nog niet
  /// opgehaald. Een verkeerd getal laten staan is erger dan geen getal — het splitst de plaat in
  /// twee uitgaven ([editionSplit]), het zet een "14 nummers"-regel onder een tegel met één nummer,
  /// en het bepaalt de volgorde. Nul betekent hier "niet genummerd", en dat is precies wat
  /// [editionSplit] en [rebuildAlbums] al veilig behandelen — een ongetagde rip doet hetzelfde.
  /// Open je daarna de nieuwe tegel, dan haalt de app de tracklijst van de vastgezette persing op
  /// en zet "Tags gelijktrekken" er de échte nummering in.
  ///
  /// **ALBUMARTIST verhuist wél mee**, want die hoort bij de plaat en niet bij de opname. Zonder
  /// deze regel houdt een nummer dat van een verzamelaar wegloopt de artiest van die verzamelaar.
  ///
  /// Alles hier is omkeerbaar: [_schrijfBewerking] legt de oude waarden in [_tagUndo] voordat het
  /// schrijft, dus de undo-knop zet ze terug.
  @visibleForTesting
  static Map<String, String?> veldenVanDeOudePersing(String? nieuweArtiest) => {
        'TRACKNUMBER': null,
        'TRACKTOTAL': null,
        'TOTALTRACKS': null,
        'DISCNUMBER': null,
        'DISCTOTAL': null,
        'TOTALDISCS': null,
        // Het jaartal van de plaat waar het nummer NIET op hoort. De nieuwe tegel leest zijn jaar
        // straks uit de vastgezette persing; dit veld zou daar alleen als verkeerde terugval onder
        // liggen.
        'DATE': null,
        if (nieuweArtiest != null && nieuweArtiest.trim().isNotEmpty)
          'ALBUMARTIST': cleanArtistName(nieuweArtiest),
      };

  Future<({int written, List<String> failed})> _schrijfBewerking(
    Album target, {
    String? artist,
    String? albumTitle,
    String? title,
    List<Track>? alleen,
  }) async {
    // Eén nummer bewerken is iets anders dan een album bewerken, en dat verandert twee regels
    // hieronder. Zie [applyCorrection] voor waarom dit bestaat.
    final mag = veldenBijCorrectie(isSingle: target.isSingle, perNummer: alleen != null);
    final gedeeld = <String, String?>{};
    if (artist != null && artist.trim().isNotEmpty) gedeeld['ARTIST'] = cleanArtistName(artist);
    if (albumTitle != null && albumTitle.trim().isNotEmpty && mag.album) {
      gedeeld['ALBUM'] = albumTitle.trim();
    }
    final losseTitel = title != null && title.trim().isNotEmpty && mag.titel;
    // Verhuist er één nummer, dan gaan de tags van de oude persing mee de deur uit. Zie
    // [veldenVanDeOudePersing] — dít is de reparatie van "de metadata gaat mee van het album waar
    // hij in zat".
    final opruimen =
        alleen == null ? const <String, String?>{} : veldenVanDeOudePersing(artist);
    var written = 0;
    final failed = <String>[];
    if (gedeeld.isEmpty && !losseTitel && opruimen.isEmpty) return (written: 0, failed: failed);

    for (final t in alleen ?? target.tracks) {
      final velden = {...opruimen, ...gedeeld, if (losseTitel) 'TITLE': title.trim()};
      final f = File(t.path);
      // Uit de container die het bestand écht is: een mp3 met de FLAC-lezer komt leeg terug, en "leeg"
      // betekent "dit veld was er niet" — dan zou undo de tags WISSEN in plaats van terugzetten.
      final raw =
          t.path.toLowerCase().endsWith('.mp3') ? readMp3RawFields(f) : readFlacRawFields(f);
      final voor = {for (final k in velden.keys) k: raw[k.toLowerCase()]};
      // Mét reden. Zonder deze stond er op het scherm "3 niet gelukt" en niets meer — terwijl een
      // bestand dat openstaat in een andere speler iets heel anders is dan een volle schijf, en
      // alleen het eerste los je op door iets dicht te doen.
      String? reden;
      if (!await writeTagFields(f, velden, waarom: (w) => reden = w)) {
        failed.add(reden == null ? t.title : '${t.title} — $reden');
        continue;
      }
      written++;
      // Een al bestaande undo-regel WINT: die is ouder en wijst dus naar de oorspronkelijke waarde.
      // Overschrijven zou de weg terug inkorten tot "zoals het een bewerking geleden was".
      _tagUndo[t.path] = {...voor, ...?_tagUndo[t.path]};
    }
    if (written > 0) await _saveTagUndo();
    return (written: written, failed: failed);
  }

  Future<({int written, List<String> failed})> applyCorrection(
    Album target,
    AppSettings settings, {
    String? artist,
    String? albumTitle,
    String? title,
    Uint8List? coverBytes,
    int? discogsRelease,
    String? mbid,
    List<Track>? alleen,
  }) async {
    // Eén nummer uit dit album, in plaats van het hele album.
    //
    // **Waarvoor dit bestaat.** Onder "Niet op deze uitgave" staan de bestanden die je wél hebt maar
    // die niet op de aangewezen persing staan. Vaak horen ze bij een ANDERE plaat die je nog niet
    // hebt — "La Salsa" hoort niet op *Partir un jour* — en dan is er niets om ze naartoe te
    // verplaatsen: "Naar ander album…" kan alleen kiezen uit albums die er al zijn. Gevraagd op
    // 27-08-2026: *"liedjes die niet op de uitgave staan moet ik dan wel kunnen metadata voor
    // zoeken, zodanig dat die wel in de goeie uitgave zit"*.
    //
    // Met een naam in plaats van een bestaand album kan het wél: het nummer krijgt de artiest en de
    // plaat van de uitgave die je aanwijst, en groepeert zich daarmee vanzelf tot zijn eigen tegel.
    //
    // **De bestanden blijven staan.** Dit is dezelfde afspraak als bij het corrigeren van een heel
    // album: de indeling volgt de labels, niet de mappen. Wil je de bestanden óók verhuizen, dan is
    // "Naar ander album…" daarvoor, en die vraagt het netjes.
    final perNummer = alleen != null && alleen.isNotEmpty;
    if (isRemote) {
      await _editOnPc({
        // Een EIGEN naam, en dat is met opzet. Zou dit als gewone `correction` met een extra veld
        // erbij gaan, dan zou een pc die dat veld nog niet kent de correctie op het HELE album
        // toepassen — alle nummers hernoemd terwijl je er één aanwees. Een pc die deze naam niet
        // kent doet niets, en dat is het enige veilige antwoord.
        'op': perNummer ? 'correctionTracks' : 'correction',
        'albumId': remoteAlbumId(target),
        if (perNummer) 'trackIds': [for (final t in alleen) _remoteTrackId(t.path)],
        'artist': artist,
        'albumTitle': albumTitle,
        'title': title,
        if (coverBytes != null && coverBytes.isNotEmpty) 'cover': base64Encode(coverBytes),
        'discogsRelease': discogsRelease,
        'mbid': mbid,
      });
      // De pc doet het echte werk en meldt niets terug over geschreven bestanden; op een telefoon valt
      // er dus niets te tellen.
      return (written: 0, failed: const <String>[]);
    }
    // Eerst naar de bestanden, dán de correctie. Andersom zou een mislukte schrijfbeurt onzichtbaar
    // blijven achter een correctie die het scherm tóch goed laat lijken.
    final doel = perNummer ? alleen : target.tracks;
    final magVeld = veldenBijCorrectie(isSingle: target.isSingle, perNummer: perNummer);
    final uit = await _schrijfBewerking(target,
        artist: artist, albumTitle: albumTitle, title: title, alleen: perNummer ? doel : null);
    for (final t in doel) {
      final c = _corrections.putIfAbsent(t.path, () => {});
      // Discogs numbers artists who share a name and asterisks name variants; neither belongs in
      // a library, let alone on the now-playing bar.
      if (artist != null && artist.trim().isNotEmpty) c['artist'] = cleanArtistName(artist);
      // Dezelfde regel als in [_schrijfBewerking], uit dezelfde functie: wat er in de tags komt en
      // wat er in de correctie komt moet gelijk luiden.
      if (albumTitle != null && albumTitle.trim().isNotEmpty && magVeld.album) {
        c['album'] = albumTitle.trim();
      }
      if (title != null && title.trim().isNotEmpty && magVeld.titel) {
        c['title'] = title.trim();
      }
      // Dezelfde opruiming als in de tags, maar dan in de app — anders zou je pas na een herscan
      // zien dat het klopt, en tot die tijd staat je nummer als "7 van 14" op een plaat waar het
      // niet op stond. Zie [veldenVanDeOudePersing] voor waarom nul en niet een gokje.
      if (perNummer) {
        c['trackNo'] = '0';
        c['trackTotal'] = '0';
      }
      // The exact pressing the user pointed at. Everything else about this album — its edition
      // line, its back cover, its disc — is read from this one release from now on, instead of
      // whichever the app would have picked for itself.
      if (discogsRelease != null && discogsRelease > 0) c['release'] = '$discogsRelease';
      // Picking from a different source replaces the pin rather than layering on top of it: two
      // pressings pinned at once is not a state anything downstream could read sensibly.
      if (mbid != null && mbid.isNotEmpty) {
        c['mbid'] = mbid;
        c.remove('release');
      } else if (discogsRelease != null && discogsRelease > 0) {
        c.remove('mbid');
      }
    }
    await _saveCorrections();

    // Re-apply corrections to the in-memory tracks + regroup. rebuildAlbums() preserves each
    // album's covers across the rebuild, so the grid no longer blanks here.
    final corrected = tracks.map(_applyCorrection).toList();
    tracks
      ..clear()
      ..addAll(corrected);
    rebuildAlbums();

    // Find the regrouped album this correction produced, and attach the new cover.
    //
    // cleanArtistName, exactly as the correction above was written with it. Trimming alone gave a
    // DIFFERENT name — Discogs hands back "Adele (3)" for any artist with a namesake, and the saved
    // correction says "Adele" — so every key derived from it pointed at an album that does not
    // exist. The styles, the assigned back and disc scans, the merge decision and the cover chosen
    // in that same dialog were all lifted off the old key and filed under a dead one: gone, quietly,
    // at the moment the user was told their correction had been applied.
    final newArtist = (artist?.trim().isNotEmpty ?? false) ? cleanArtistName(artist!) : target.artist;
    // Onder welke naam de plaat straks staat — en dat volgt uit dezelfde regel: is het ALBUM-veld
    // gezet, dan is dát de nieuwe naam; anders is het de titel van de single.
    final newTitle = magVeld.album
        ? ((albumTitle?.trim().isNotEmpty ?? false) ? albumTitle!.trim() : target.title)
        : ((title?.trim().isNotEmpty ?? false) ? title!.trim() : target.title);
    final paths = doel.map((t) => t.path).toSet();
    Album? match;
    for (final a in albums) {
      final sameId = a.artist.toLowerCase() == newArtist.toLowerCase() &&
          a.title.toLowerCase() == newTitle.toLowerCase();
      if (sameId || a.tracks.any((t) => paths.contains(t.path))) {
        match = a;
        if (sameId) break;
      }
    }
    if (match != null && coverBytes != null && coverBytes.isNotEmpty) {
      match.correctedCover = coverBytes;
      await CoverEnricher(settings).saveFixedCover(match, coverBytes);
    }
    // Alleen als de HELE plaat verhuist. Bij één aangewezen nummer blijft het oude album gewoon
    // bestaan met de rest erin — zijn hoezen, zijn rollen en zijn samenvoegkeuze meeverhuizen naar
    // de naam van één weggelopen nummer zou dat album leegroven.
    if (!perNummer) {
      await _carryAlbumKeys(settings, target.artist, target.title, newArtist, newTitle);
    }
    _bumpMeta();
    notifyListeners();
    return uit;
  }

  /// Move everything filed under an album's NAME to its new name.
  ///
  /// Three maps and one cached file are keyed on `artist|title`, which is exactly what a correction
  /// changes — so the most ordinary edit in the app silently threw away the scans the user assigned
  /// by hand, the decision to keep two pressings together, the record's styles, and (at the next
  /// start) the cover they picked themselves. None of that was deleted by anyone; the key moved out
  /// from under it.
  ///
  /// Not solved by re-keying these to the album uid, tempting as that is: [albumArtKey] deliberately
  /// ignores the edition, so two split pressings of one record share their scans today. Giving them
  /// separate uids would quietly split that too.
  Future<void> _carryAlbumKeys(AppSettings settings, String oldArtist, String oldTitle,
      String newArtist, String newTitle) async {
    final oldKey = albumArtKey(oldArtist, oldTitle);
    final newKey = albumArtKey(newArtist, newTitle);
    if (oldKey == newKey) return;

    final roles = _albumArtRoles.remove(oldKey);
    if (roles != null && roles.isNotEmpty) {
      _albumArtRoles[newKey] = roles;
      await _saveAlbumArtRoles();
    }

    final styles = _styles.remove(oldKey);
    if (styles != null && styles.isNotEmpty) {
      _styles[newKey] = styles;
      await _saveStyles();
    }

    // The merge set stores the same key with an `album::` prefix.
    if (_merged.remove('album::$oldKey')) {
      _merged.add('album::$newKey');
      await _saveMerged();
    }

    await CoverEnricher(settings).reKeyFixedCover(oldArtist, oldTitle, newArtist, newTitle);
  }

  /// Waar [scan] zijn tussentijden kwijt kan. Null = niets meten, geen kosten.
  ///
  /// Bestaat omdat `start.log` van de scan één getal wist — "scan klaar in 15034ms" — en dat getal
  /// zegt niet WELKE van de zes stappen die tijd opeet. Gemeten op deze pc: de schijf zelf levert de
  /// koppen van alle 775 bestanden in 163 ms warm (6535 ms koud, want D: is een harde schijf). De
  /// rest van die 15 seconden is dus rekenwerk, en zonder deze uitgang is niet te zien welk.
  ///
  /// Dezelfde vorm als `fase()` in main.dart, zodat `start.log` doorzoekbaar blijft.
  void Function(String)? meetlog;

  Future<T> _stap<T>(String naam, Future<T> Function() werk) async {
    final m = meetlog;
    if (m == null) return werk();
    final klok = Stopwatch()..start();
    final uit = await werk();
    m('  scan/$naam klaar in ${klok.elapsed.inMilliseconds}ms');
    return uit;
  }

  T _stapNu<T>(String naam, T Function() werk) {
    final m = meetlog;
    if (m == null) return werk();
    final klok = Stopwatch()..start();
    final uit = werk();
    m('  scan/$naam klaar in ${klok.elapsed.inMilliseconds}ms');
    return uit;
  }

  Future<void> scan() async {
    // Never run two scans at once (a rescan after a download must not race the
    // startup scan over `tracks`). Coalesce concurrent requests into one re-run.
    if (scanning) {
      _rescanQueued = true;
      return;
    }
    scanning = true;
    scanned = 0;
    notifyListeners();

    // Pass 1 — tags, off the UI thread, with a timeout. A single malformed file that
    // makes readMetadata hang must NOT stall the scan forever (that left the app stuck
    // on "scannen… 0" after a download). The current library is kept intact until the
    // new scan succeeds, so a rescan never blanks the UI — the app stays usable.
    List<Map<String, dynamic>> raw;
    try {
      final uitslag = await _stap(
          'tags',
          () => scanTagsInIsolate(rootPath, tagCachePad)
              .timeout(const Duration(seconds: 120)));
      raw = uitslag.rijen;
      meetlog?.call('  scan/tags: ${uitslag.uitCache} uit cache, ${uitslag.gelezen} gelezen');
    } catch (e) {
      // Timed out or failed — keep whatever library we already have loaded. Reported rather
      // than swallowed: this exact failure was silent for a long time, and a silent scan
      // failure is indistinguishable from an empty music folder.
      debugPrint('Library scan failed: $e');
      scanning = false;
      notifyListeners();
      return;
    }
    _stapNu('omzetten', () {
      tracks
        ..clear()
        ..addAll(raw
            .map(_trackFromMap)
            .where((t) => !_hidden.contains(t.path)) // "removed from library only" stays removed
            .map(_applyCorrection));
    });
    scanned = tracks.length;
    _stapNu('groeperen', rebuildAlbums);
    _bumpMeta();
    scanning = false;
    // Look for albums that are wholly duplicates of one you already own. Only after a full scan —
    // it reads file sizes and headers, too heavy to redo on every regroup.
    //
    // Op een andere isolate: dit leest de FLAC-kop en de grootte van beide bestanden van élk
    // kandidaatpaar, en dat stond op de tekendraad. Zie [redundantAlbumsAsync].
    await _stap('dubbels', () async {
      try {
        duplicates = await redundantAlbumsAsync();
      } catch (e) {
        meetlog?.call('  scan/dubbels MISLUKT: $e');
        duplicates = const []; // never let duplicate-hunting break a scan
      }
      // Het AANTAL erbij, want anders is "klaar in 61ms" niet te onderscheiden van "klaar, en niets
      // gevonden omdat er onderweg iets stilviel". De melding op de albumpagina hangt hieraan.
      meetlog?.call('  scan/dubbels: ${duplicates.length} gevonden');
    });
    notifyListeners();

    // Only now may anything be forgotten: this scan saw the music, so a path it did not see is
    // genuinely absent rather than merely unreachable.
    await _stap('correcties', _sweepCorrections);

    // And pick up what previous installs left next to the music.
    unawaited(_adoptSidecars());

    // Pass 2 — one embedded cover per album, off the UI thread. Guarded with a
    // timeout: a malformed file that makes readMetadata hang can never stall
    // startup (which would also block cover enrichment from ever running).
    // Only the albums that do not already have one.
    //
    // This asked for every album's first track every time, and a rescan runs after every finished
    // download — so downloading one song re-opened and re-parsed the metadata of all hundred and
    // thirty-six first tracks to read pictures that were already in memory. rebuildAlbums carries
    // covers across the regroup (see _Covers), so an album that had one still has it; a genuinely new
    // album has null and is read.
    //
    // The trade: art changed inside a file we have already read is not picked up until the cover is
    // corrected by hand. Re-reading everything on the chance that a tag was edited outside the app
    // was paying seconds, on every download, for something that essentially does not happen.
    final firstPaths = [
      for (final a in albums)
        if (a.embeddedCover == null && a.tracks.isNotEmpty) a.tracks.first.path,
    ];
    // Élk album, ook die zijn hoes al in het geheugen heeft. Alleen hiermee mag de cache opgeruimd
    // worden — zie [_readCovers]; op [firstPaths] opruimen wiste hem bij elke herscan bijna leeg.
    final alleEerste = [
      for (final a in albums)
        if (a.tracks.isNotEmpty) a.tracks.first.path,
    ];
    try {
      final covers = await _stap('hoezen (${firstPaths.length})',
          () => readCoversInIsolate(firstPaths, hoesCacheMap, alleEerste)
              .timeout(const Duration(seconds: 30)));
      for (final a in albums) {
        final c = covers[a.tracks.first.path];
        if (c != null && c.isNotEmpty) a.embeddedCover = c;
      }
      notifyListeners();
    } catch (_) {
      // Timed out or failed — cached + web covers still fill in via enrich().
    }

    // A rescan requested while this one was running — run it once now.
    if (_rescanQueued) {
      _rescanQueued = false;
      await scan();
    }
  }

  // ── Client mode: the library comes from a paired PC ────────────────────────
  //
  // The dividing line in this app is not Windows versus Apple, it is "does this device hold the
  // music?". A Mac and an iPad do not, so instead of walking a folder they read /api/catalog from
  // the Windows PC. Everything above this line — every screen, every sort, every cover — is
  // unchanged, because what lands in [tracks] and [albums] is the same shape either way.

  RemoteClient? _remote;

  /// The paired PC, or null on the machine that owns the music.
  RemoteClient? get remote => _remote;

  /// True when this app is reading someone else's library. Screens that WRITE check this.
  bool get isRemote => _remote != null;

  /// The catalogue's ETag from last time, so a poll that finds nothing changed costs one 304
  /// instead of re-sending twelve thousand tracks.
  String? _catalogEtag;

  /// True when what is on screen came from the cloud copy rather than from the PC. Everything is
  /// browsable; nothing is playable, because the files are on a machine that is not answering.
  /// Screens read this to say so, rather than letting a tap on play do nothing.
  /// Waarom de pc niet antwoordde. Null zodra hij het weer doet.
  ///
  /// Twee gevallen die de gebruiker totaal verschillende dingen laten doen, en die tot nu toe als
  /// één melding op het scherm kwamen:
  ///
  /// * [pcStil] — hij slaapt, hij staat uit, of er is geen netwerk. Wachten helpt; de app pikt het
  ///   binnen vijftien seconden vanzelf weer op.
  /// * [sleutelGeweigerd] — de pc ANTWOORDT, maar dit toestel mag er niet meer in. Wachten hielp
  ///   hier nooit: er was geen enkel pad terug naar het koppelscherm, en zelfs een herstart deed
  ///   niets omdat de sleutel gewoon weer van schijf gelezen werd.
  GeenVerbinding? geenVerbinding;

  bool fromCloudMirror = false;

  /// When the PC last copied its library up. Only meaningful while [fromCloudMirror].
  DateTime? mirrorUpdatedAt;

  /// Komt de kopie op het scherm van dit toestel zelf, in plaats van uit de cloud?
  ///
  /// Alleen betekenisvol zolang [fromCloudMirror]. Het verschil zit niet in wat je ziet — het is
  /// dezelfde catalogus — maar in wat je eraan hebt: de kopie op het toestel is er ook zonder
  /// internet, en dan is wat offline bewaard is gewoon te spelen.
  bool kopieVanToestel = false;

  /// De laatste catalogus die van de pc kwam, onbewerkt.
  ///
  /// Staat hier zodat wie hem wil bewaren niet zelf terug hoeft te vertalen naar JSON — zie
  /// `CatalogusKopie`. In het geheugen, niet op schijf: schrijven is de keuze van de aanroeper.
  /// De catalogus zoals de pc hem stuurde, onbewerkt.
  ///
  /// **De BYTES en niet de ontlede vorm.** De kopie op dit toestel is letterlijk deze tekst; hem uit
  /// een ontlede kaart terugcoderen kost `jsonEncode` over megabytes op de tekendraad, elke keer dat
  /// de catalogus verandert — en tijdens een download is dat om de paar seconden. Zie
  /// [CatalogusKopie.bewaarBytes].
  List<int>? laatsteCatalogusBytes;

  set remote(RemoteClient? client) {
    _remote = client;
    _catalogEtag = null;
  }

  /// Fill the library from the paired PC. The counterpart of [scan].
  ///
  /// Returns true when something actually changed, so a caller polling this can skip the work that
  /// follows a real update.
  ///
  /// The album grouping is ADOPTED from the PC, not recomputed here. That is the whole point: the
  /// PC has already split editions, applied the corrections you typed and honoured the pressings
  /// you pinned, and re-deriving any of that from tags would be a second implementation that
  /// drifts. Whatever you see on the PC is what lands here, including next year's grouping rule.
  Future<bool> loadRemote({bool quiet = false, bool naEen304 = false}) async {
    final client = _remote;
    if (client == null) return false;
    if (scanning) {
      _rescanQueued = true;
      return false;
    }
    scanning = !quiet;
    if (!quiet) notifyListeners();

    CatalogResponse res;
    try {
      res = await client.catalog(etag: _catalogEtag);
    } catch (e) {
      // Keep the library we already have. A Mac that loses the PC mid-song should keep showing the
      // record it is playing, not blank the screen — the same reasoning as a failed disk scan.
      //
      // WAAROM het niet lukte wordt nu bewaard. Dit was een kale `catch (e)` met een `return false`,
      // en vanaf hier was er geen 401 meer in het systeem — alleen een bool die óók "niets veranderd"
      // en "er loopt al een scan" betekent. Gevolg op de telefoon: een geweigerde sleutel kwam op het
      // scherm als "je pc staat uit", en dan zoek je een uur naar je netwerk terwijl de pc antwoordt.
      // `RemoteException.isUnauthorized` bestond al en werd nergens uitgelezen.
      geenVerbinding =
          e is RemoteException && e.isUnauthorized ? GeenVerbinding.sleutelGeweigerd : GeenVerbinding.pcStil;
      debugPrint('Remote catalog failed: $e');
      scanning = false;
      notifyListeners();
      return false;
    }
    geenVerbinding = null;
    _catalogEtag = res.etag;
    final catalog = res.catalog;
    if (catalog == null) {
      // 304: niets veranderd. Meestal is dat het einde van het verhaal — behalve als we op de
      // kopie uit de cloud stonden.
      //
      // **Dit is waarom de offlinemelding bleef hangen als de pc terugkwam.** De ETag is van vóór
      // de storing, en de pc heeft in de tussentijd niets aan zijn bibliotheek veranderd, dus komt
      // hier precies het antwoord "hetzelfde als je al had" — en dan viel de afhandeling stil op de
      // regel hieronder. Het scherm bleef de kopie tonen met de balk "Pc offline" erboven, terwijl
      // de pc net had ANTWOORD. Alleen een herstart hielp.
      //
      // Eén keer opnieuw vragen zonder ETag is genoeg: dan komt de levende catalogus terug en zet
      // de gewone weg hieronder [fromCloudMirror] uit. `scanning` moet eerst weer los, anders zet
      // de aanroep zichzelf in de wachtrij in plaats van te lopen.
      // Precies één keer, en dat is [naEen304]. Zonder die rem hangt hier een lus aan een pc die om
      // wat voor reden dan ook 304 blijft antwoorden ook zónder ETag — en dan blijft de telefoon
      // hem bevragen zolang de app open staat. Eén herkansing lost het echte geval op; blijft het
      // daarna 304, dan is er iets anders aan de hand dan een pc die net terugkwam.
      if (fromCloudMirror && !naEen304) {
        _catalogEtag = null;
        scanning = false;
        return loadRemote(quiet: quiet, naEen304: true);
      }
      scanning = false;
      if (!quiet) notifyListeners();
      return false;
    }

    _adoptCatalog(catalog, client);
    laatsteCatalogusBytes = res.bytes;
    // Live again: what is on screen is playable, whatever it was a moment ago.
    fromCloudMirror = false;
    mirrorUpdatedAt = null;
    kopieVanToestel = false;
    scanned = tracks.length;
    scanning = false;
    notifyListeners();

    if (_rescanQueued) {
      _rescanQueued = false;
      await loadRemote(quiet: quiet);
    }
    return true;
  }

  /// Fill the library from the cloud copy, for when the PC is not answering.
  ///
  /// Deliberately the same [_adoptCatalog] the live path uses: the copy IS the catalogue the PC
  /// serves, so the albums, pressings and covers come out identical. What differs is only that
  /// nothing can be played, and [fromCloudMirror] says so.
  ///
  /// Refuses to overwrite a live catalogue. Coming back from a lock screen can land this after the
  /// PC has already answered, and replacing a playable library with an unplayable copy of itself
  /// is the one outcome nobody wants.
  bool adoptMirror(Map<String, dynamic> json, {DateTime? updatedAt, bool vanToestel = false}) {
    if (!isRemote) return false;
    if (!fromCloudMirror && tracks.isNotEmpty) return false;
    final client = _remote;
    if (client == null) return false;
    try {
      _adoptCatalog(CatalogDto.fromJson(json), client);
    } catch (e) {
      debugPrint('Cloud catalogue unusable: $e');
      return false;
    }
    fromCloudMirror = true;
    kopieVanToestel = vanToestel;
    mirrorUpdatedAt = updatedAt;
    scanned = tracks.length;
    notifyListeners();
    return true;
  }

  /// Turn what the PC sent into the very same [Track] and [Album] objects a disk scan produces.
  void _adoptCatalog(CatalogDto catalog, RemoteClient client) {
    // Covers, keyed by track path exactly as [rebuildAlbums] does — a refreshed catalogue makes
    // fresh Album objects, and without this the grid blanks on every poll and then refetches every
    // cover over the network.
    final coversByPath = <String, _Covers>{};
    for (final a in albums) {
      final snap = _Covers.of(a);
      for (final t in a.tracks) {
        coversByPath[t.path] = snap;
      }
    }

    final byAlbum = <String, List<Track>>{};
    tracks.clear();
    for (final dto in catalog.tracks) {
      final t = _trackFromDto(dto, client);
      tracks.add(t);
      byAlbum.putIfAbsent(dto.albumId, () => []).add(t);
    }

    _rebuildCanonicalArtists();

    final built = <Album>[];
    _remoteAlbums.clear();
    for (final dto in catalog.albums) {
      final ts = byAlbum[dto.id];
      // An album whose every track was filtered out (hidden on the PC) is not an album.
      if (ts == null || ts.isEmpty) continue;
      ts.sort((a, b) => a.trackNo.compareTo(b.trackNo));
      final al = Album(dto.title, dto.artistName, ts, isSingle: dto.isSingle)
        ..edition = dto.edition;
      for (final t in ts) {
        final saved = coversByPath[t.path];
        if (saved == null) continue;
        saved.applyTo(al);
        break;
      }
      _remoteAlbums[al] = (
        id: dto.id,
        artRef: dto.artworkRef ?? dto.id,
        artTag: dto.artTag ?? '',
        release: dto.discogsRelease,
        mbid: dto.mbid,
        merged: dto.merged,
        styles: dto.styles,
      );
      built.add(al);
    }
    albums = built..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    // De aangewezen scans, op dezelfde sleutel waarop [albumArtRoles] ze opzoekt.
    _remoteAlbumRoles
      ..clear()
      ..addEntries([
        for (final dto in catalog.albums)
          if (dto.artRoles.isNotEmpty)
            MapEntry(albumArtKey(dto.artistName, dto.title), dto.artRoles),
      ]);

    _remoteArtistArt
      ..clear()
      ..addEntries([
        for (final a in catalog.artists)
          if (a.artChoice.isNotEmpty) MapEntry(artistKey(a.name), a.artChoice),
      ]);

    _rebuildTrackIndexes();
  }

  /// What the PC calls each album we are showing: its id (for a write, in phase C) and the
  /// reference to ask `/art/` for. Keyed by object identity — [Album] has no value equality, and a
  /// refreshed catalogue makes new ones, so this is cleared and refilled with them.
  final Map<Album,
          ({
    String id,
    String artRef,
    String artTag,
    int? release,
    String? mbid,
    bool merged,
    List<String> styles
  })>
      _remoteAlbums = {};

  /// Portraits and backdrops the user picked, by artist key — the same key [chosenArtistArt] uses,
  /// so the lookup is unchanged.
  final Map<String, Map<String, String>> _remoteArtistArt = {};

  /// The PC's id for an album we are showing, or null on the machine that owns the music.
  String? remoteAlbumId(Album a) {
    final recht = _remoteAlbums[a]?.id;
    if (recht != null) return recht;
    // Het object is OUD, niet het album.
    //
    // Deze kaart is gesleuteld op objectidentiteit, en `_adoptCatalog` maakt bij elke verse
    // catalogus nieuwe [Album]-objecten. Een scherm of een venster dat al open stond houdt dan een
    // exemplaar vast dat nergens meer in staat — waarna dit null gaf, de pc geen albumId kreeg, en
    // die antwoordde met "Dat album staat hier niet (meer)". Terwijl het er gewoon staat.
    //
    // En dat is geen randgeval: één bewerking ververst de catalogus al, dus een tweede bewerking uit
    // hetzelfde venster liep er standaard tegenaan.
    //
    // Een pad is wél stabiel. Deel je een nummer met een album dat er nu staat, dan ben je dat
    // album. Alleen op de missende weg, dus het kost niets zolang alles klopt.
    final paden = {for (final t in a.tracks) t.path};
    if (paden.isEmpty) return null;
    for (final e in _remoteAlbums.entries) {
      for (final t in e.key.tracks) {
        if (paden.contains(t.path)) return e.value.id;
      }
    }
    return null;
  }

  /// True everywhere now: a Mac and an iPad edit by asking the PC to, and the result comes back
  /// through the catalogue. Kept as a name rather than inlined, because moving files is still the
  /// PC's alone and this is where that line would move if it ever changes.
  bool get canEdit => true;

  /// Hand an edit to the PC and take its answer as the truth.
  ///
  /// Nothing is changed locally first. The PC applies it to the library everyone reads, the
  /// catalogue fingerprint moves, and [loadRemote] brings back the result — including whatever the
  /// PC decided that we did not, like a regroup that follows from a corrected track count. Editing
  /// optimistically here would mean guessing at that, and being wrong in exactly the cases the
  /// user is trying to fix.
  Future<void> _editOnPc(Map<String, dynamic> operation) async {
    final client = _remote;
    if (client == null) return;
    await client.edit(operation);
    // Straight away rather than on the next poll: the screen that asked is still open, and a
    // correction that takes fifteen seconds to appear reads as one that did not work.
    _catalogEtag = null;
    await loadRemote(quiet: true);
    // En de hoezen erbij halen.
    //
    // `loadRemote` bouwt NIEUWE albumobjecten, en die hebben geen hoes. Zonder deze regel stond het
    // raster na elke bewerking op een client vol lege vakjes — en het kwam ook niet vanzelf goed:
    // de eerstvolgende poll krijgt een 304 (de etag klopt inmiddels), dus `changed` is onwaar en de
    // sweep die dáár aan hangt draait nooit. Pas een herstart haalde de hoezen terug.
    final hoesInstellingen = _hoesInstellingen;
    if (hoesInstellingen != null) unawaited(loadRemoteCovers(hoesInstellingen));
  }

  /// The PC's id for a track we are showing, for anything that has to name tracks TO the PC —
  /// removing them, moving them, or handing a queue to a speaker.
  String? remoteTrackId(String path) => _remoteTrackId(path);

  /// Het id waarmee de PC dit nummer serveert — of het pad nu een stream-URL is of een bestand.
  ///
  /// Twee wegen, omdat er twee soorten pad zijn. Op een telefoon IS het pad de stream-URL en zit het id
  /// erin. Op de pc is het pad een bestand op schijf, en dan moet het id net zo berekend worden als de
  /// server het doet: [trackIdFor] over het pad relatief aan de muziekwortel.
  ///
  /// Zonder die tweede weg gaf dit op de pc voor élk nummer null terug. Gemeten toen de speakerknop daar
  /// net bij was gekomen: de knop verscheen, de speaker werd paars, "Speelt op Sonos Move" stond op het
  /// scherm — en er was in twintig seconden polsen niets naar die speaker gegaan. De muziek liep lokaal
  /// door. Precies de tegenspraak waar de rest van dit bestand tegen gebouwd is.
  String? castTrackId(String path) => gedeeldId(path);

  /// Hetzelfde antwoord als [castTrackId], onder de naam die zegt waar het voor dient: dit is het id
  /// waaronder favorieten, afspeellijsten en de speeltelling van dit nummer in de gedeelde staat
  /// staan. Eén implementatie, want twee zouden uit elkaar lopen.
  String? gedeeldId(String path) {
    final onthouden = _idGeheugen[path];
    if (onthouden != null) return onthouden.isEmpty ? null : onthouden;
    final viaUrl = _remoteTrackId(path);
    // Alleen waar de muziek zelf staat: op een client zou de wortel iets anders betekenen en zou dit
    // een id verzinnen dat de pc niet kent.
    final id = viaUrl ??
        ((remote != null || rootPath.isEmpty) ? null : trackIdFor(path, rootPath));
    // Ook "geen id" wordt onthouden — anders wordt er voor elke radiostroom bij elke trekking
    // opnieuw een URI ontleed. Maar NIET als de wortel simpelweg nog niet gezet is: dat is "nog
    // niet", geen antwoord, en dat vastleggen zou de hele bibliotheek id-loos houden.
    if (id != null || remote != null || rootPath.isNotEmpty) _idGeheugen[path] = id ?? '';
    return id;
  }

  /// The PC's id for a track we are showing. Its path is the stream URL, and the id is in it.
  String? _remoteTrackId(String path) {
    final segments = Uri.tryParse(path)?.pathSegments ?? const [];
    if (segments.length < 2 || segments[segments.length - 2] != 'stream') return null;
    final last = segments.last;
    final dot = last.lastIndexOf('.');
    return dot < 0 ? last : last.substring(0, dot);
  }

  /// A track as the PC describes it. [Track.path] becomes the stream URL WITHOUT the token: it is
  /// the identity key for favourites, playlists and resume, and those must survive re-pairing —
  /// the token is added at the moment of playback instead. The extension is kept because that is
  /// how a player types the stream.
  Track _trackFromDto(TrackDto d, RemoteClient client) {
    final pad = client.endpoint.baseUrl.replace(path: d.streamPath).toString();
    // Het oordeel van de pc onder de naam die het nummer HIER heeft. Zonder deze regel reist de
    // meting wel mee maar vindt niemand haar terug: `gemeten()` sleutelt op pad, en dat pad is op
    // een iPad een stream-URL en geen bestandsnaam.
    final o = d.echt == null ? null : Echtheidsoordeel.fromJson(d.echt!);
    if (o != null) onthoudOordeelVanPc(pad, o);
    return _trackFromDtoMet(d, pad);
  }

  Track _trackFromDtoMet(TrackDto d, String pad) => Track(
        path: pad,
        title: d.title,
        artist: d.artistName,
        album: d.albumTitle,
        trackNo: d.trackNo,
        trackTotal: d.trackTotal,
        duration: d.durationMs > 0 ? Duration(milliseconds: d.durationMs) : null,
        isFlac: d.ext == 'flac',
        year: d.year,
        genre: d.genre,
        addedMs: d.addedMs,
        sizeBytes: d.sizeBytes,
        sampleRate: d.sampleRate ?? 0,
        bitsPerSample: d.bitsPerSample ?? 0,
      );

  /// Covers, over the network, after the grid is already on screen.
  ///
  /// The disk cache is [CoverEnricher]'s own, keyed by artist+title rather than by path, so a Mac
  /// that has seen a record once shows its cover instantly on the next start — and pays for the
  /// fetch only the first time. Deliberately not part of [loadRemote]: the library should appear
  /// immediately, with the covers filling in behind it, rather than the screen staying empty until
  /// the last one has arrived.
  Future<void>? _remoteCoverSweep;

  /// Covers for a library that lives on the paired PC.
  ///
  /// Guarded like [enrichFromWeb], and for the same reason found in the same audit: this is started
  /// from three places in client_session — once on connecting and again on every catalogue change —
  /// and a catalogue changes whenever the PC finishes a download. Two sweeps then walked the same
  /// album list over the same wifi, each setting `enriching` and each clearing it, so the status line
  /// went off while the other was still fetching. Held as the future so a caller can wait for the one
  /// already running instead of starting a second.
  /// De instellingen waarmee de laatste hoezenronde liep.
  ///
  /// Nodig omdat een bewerking op een client de albumlijst vervangt en er dus meteen daarna hoezen
  /// bij gehaald moeten worden — zie [_editOnPc] — terwijl daar geen instellingen voorhanden zijn.
  /// Een verse [AppSettings] verzinnen zou naar de verkeerde cachemap wijzen.
  AppSettings? _hoesInstellingen;

  /// Vraagt iemand een ronde terwijl er al een loopt?
  ///
  /// **Dit was een stille val.** De wacht hieronder gaf de LOPENDE ronde terug, en die loopt over de
  /// albumobjecten van toen hij begon. Maar `_adoptCatalog` bouwt bij elke verse catalogus NIEUWE
  /// objecten: de ronde vult dan albums die niemand meer op het scherm heeft, en de albums die er
  /// wél staan blijven leeg. Precies het geval "de hoezen komen pas na opnieuw inloggen".
  ///
  /// Met deze vlag draait er ná de lopende ronde nog één over de lijst zoals die dán is.
  bool _hoesRondeOpnieuw = false;

  Future<void> loadRemoteCovers(AppSettings settings) {
    _hoesInstellingen = settings;
    final bezig = _remoteCoverSweep;
    if (bezig != null) {
      _hoesRondeOpnieuw = true;
      return bezig;
    }
    return _remoteCoverSweep =
        _hoezenTotHetKlopt(settings).whenComplete(() => _remoteCoverSweep = null);
  }

  Future<void> _hoezenTotHetKlopt(AppSettings settings) async {
    do {
      _hoesRondeOpnieuw = false;
      await _loadRemoteCovers(settings);
    } while (_hoesRondeOpnieuw);
  }

  /// De hoezen ophalen op een toestel dat de muziek niet bezit.
  ///
  /// **Zes tegelijk in plaats van één voor één.** Dit liep strikt serieel: per album twee tot vier
  /// wachtmomenten — het merkteken lezen, de cache lezen, en bij een misser één HTTP-verzoek naar de
  /// pc — en pas als dat album klaar was begon het volgende. Bij een paar honderd albums op wifi is
  /// dat minutenwerk waarin je naar grijze vakjes kijkt, en de lijn staat al die tijd bijna stil:
  /// het wachten is latentie, geen bandbreedte.
  ///
  /// Zes en niet meer. Het gaat om je eigen pc op je eigen netwerk, en die serveert dit uit het
  /// geheugen; tientallen verzoeken tegelijk maken het niet sneller en zetten de pc wel onder druk
  /// terwijl daar ook nog muziek vandaan moet komen.
  Future<void> _loadRemoteCovers(AppSettings settings) async {
    final client = _remote;
    if (client == null) return;
    final enricher = CoverEnricher(settings);
    enriching = true;
    notifyListeners();
    var since = 0;

    // Niet alleen de albums ZONDER hoes.
    //
    // **Hier zat het volgende gat.** De controle hieronder — klopt het merkteken van de hoes die de
    // eigenaar koos nog met wat hier ligt? — was onbereikbaar voor elk album dat al iets liet zien.
    // De wachtrij bevatte immers alleen `cover == null`. Dus: op de pc de juiste hoes, op de Mac de
    // oude, en die kwam er nooit meer af omdat de Mac vond dat hij al klaar was.
    //
    // Een album waar de pc een BEWUSTE keuze voor kent (`artTag` gevuld) gaat er daarom altijd in,
    // ook met een hoes. Dat is een kleine groep — alleen platen waarvan je zelf de hoes hebt gekozen
    // — en juist daar mogen twee toestellen het niet oneens zijn.
    final wachtrij = [
      for (final a in albums)
        if (a.cover == null || (_remoteAlbums[a]?.artTag ?? '').isNotEmpty) a
    ];
    var volgende = 0;
    // Wat het netwerk deed. Zonder deze twee is een hoezenronde die HELEMAAL mislukt niet te
    // onderscheiden van een bibliotheek zonder hoezen: `client.art` slikt alles — geweigerde
    // verbinding, 401, time-out — en geeft null, en de lus slikt die null nog eens. Het gevolg is een
    // scherm vol grijze vakjes waar nergens iets over opgeschreven staat.
    var gevraagd = 0, gelukt = 0;
    // Geeft deze pc merktekens af bij een hoes?
    //
    // Een oudere pc kent `If-None-Match` op `/art/` niet en antwoordt gewoon met de volle bytes.
    // Zou dit blijven navragen, dan haalde elke ronde de héle hoezenverzameling opnieuw over de
    // lijn — precies het tegendeel van wat de navraag moet opleveren. Eén antwoord zonder merkteken
    // is genoeg om te weten dat het hier zinloos is; daarna gedraagt deze ronde zich weer als
    // vroeger.
    var pcKentMerken = true;

    Future<void> werker() async {
      while (true) {
        if (volgende >= wachtrij.length) return;
        final album = wachtrij[volgende++];
        // Het merkteken van de hoes die de eigenaar op de pc GEKOZEN heeft. Wijkt dat af van wat
        // hier in de cache ligt, dan is die cache achterhaald en moet hij wijken.
        //
        // **Dit was het gat.** De cache heet naar `artiest|titel`, en die naam beweegt niet als je
        // een andere afbeelding kiest. Het bestand lag er dus nog, met de goede naam en de foute
        // inhoud, en werd bij élke start opnieuw als waarheid genomen. Gemeten op 13-08-2026: op de
        // pc de juiste Whitney-hoes, op de telefoon het logo van een verzamelaar — telkens weer, hoe
        // vaak de eigenaar het ook corrigeerde.
        final merk = _remoteAlbums[album]?.artTag ?? '';
        final bewaard = await enricher.bewaardMerk(album);
        final verouderd = merk.isNotEmpty && bewaard != merk;
        // Er staat al iets én het klopt: niets te doen. Deze uitgang stond vroeger in de wachtrij
        // zelf, en daarom werd `verouderd` hierboven nooit voor zo'n album berekend.
        if (album.cover != null && !verouderd) continue;
        if (verouderd) {
          // De pc heeft een ANDERE bewuste keuze dan hier ligt, en de pc houdt de boeken bij. Alles
          // wat hier lokaal voorrang had is daarmee achterhaald — laat je dat staan, dan wint het
          // straks weer van de bytes die zo binnenkomen en verandert er zichtbaar niets.
          album.correctedCover = null;
          album.resolvedCover = null;
        }
        final ref = _remoteAlbums[album]?.artRef;
        final cached = verouderd ? null : await enricher.cached(album);

        // Er ligt hier al een hoes. Klopt hij nog met wat de pc toont?
        //
        // **Dit was het laatste gat, en het grootste.** De vorige controle keek naar `artTag`, en die
        // is er alleen bij een BEWUSTE keuze. Kwam de hoes van de pc uit de tags van het bestand of
        // uit het verrijken — het gewone geval — dan stond er nergens iets om het cachebestand
        // tegenaan te houden. Dat bestand heet naar `artiest|titel` en die naam beweegt nooit, dus
        // wat er één keer in beland was bleef er staan. Zo hield de Mac maandenlang een andere
        // clownhoes vast dan de pc, en hielp corrigeren op de pc niets: de Mac keek er niet meer
        // naar.
        //
        // Navragen kost één rit: klopt het, dan komt er een lege 304 terug; klopt het niet, dan
        // meteen de juiste bytes. Dat is niet duurder dan de download die anders zou volgen.
        if (cached != null && ref != null && pcKentMerken) {
          gevraagd++;
          final antwoord = await client.artAls(ref, bewaard);
          // Een lege 304 telt hier als geslaagd, en dat is geen boekhoudkundige truc: de vraag die
          // `hoezenMislukt` stelt is "antwoordt de pc nog?". Een bibliotheek die volledig in de cache
          // staat vraagt hier alleen maar na, krijgt alleen maar 304'jes, en zou anders bij elke
          // start melden dat de pc onbereikbaar is terwijl alles werkt.
          if (antwoord != null) gelukt++;
          if (antwoord != null && antwoord.etag == null) pcKentMerken = false;
          final verse = antwoord?.bytes;
          if (verse != null && verse.isNotEmpty) {
            album.embeddedCover = verse;
            await enricher.putCached(album, verse);
            final versMerk = antwoord!.etag ?? merk;
            if (versMerk.isNotEmpty) await enricher.schrijfMerk(album, versMerk);
            if (++since >= 24) {
              since = 0;
              notifyListeners();
            }
            continue;
          }
          // 304, of geen antwoord. In beide gevallen houden we wat we hebben — een pc die even niet
          // opneemt mag geen hoezen van het scherm halen. Wél het merkteken bijwerken als de pc er
          // een gaf, want dan weten we voortaan wat we vasthouden.
          final gekregen = antwoord?.etag ?? '';
          if (gekregen.isNotEmpty && gekregen != bewaard) {
            await enricher.schrijfMerk(album, gekregen);
          }
        }

        if (cached != null) {
          album.enriched = cached;
          if (++since >= 24) {
            since = 0;
            notifyListeners();
          }
          continue;
        }
        if (ref != null) gevraagd++;
        final antwoord = ref == null ? null : await client.artAls(ref, '');
        if (antwoord != null && antwoord.etag == null) pcKentMerken = false;
        final bytes = antwoord?.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        gelukt++;
        album.embeddedCover = bytes;
        await enricher.putCached(album, bytes);
        // Pas ná het wegschrijven, zodat een afgebroken download geen merkteken achterlaat dat zegt
        // "deze is bij" terwijl er iets ouds op schijf staat.
        //
        // Het merkteken van de pc gaat vóór dat van de bewuste keuze: het beschrijft precies de
        // bytes die hier zojuist geland zijn, ook als de hoes helemaal geen bewuste keuze was. Een
        // oudere pc geeft er geen, en dan valt dit terug op het oude gedrag.
        final teBewaren = antwoord?.etag ?? merk;
        if (teBewaren.isNotEmpty) await enricher.schrijfMerk(album, teBewaren);
        // Gebundeld, net als de tak hierboven: elke melding tekent de startpagina opnieuw. Eén
        // melding per binnenkomende hoes betekende honderden volledige hertekeningen in de eerste
        // minuut op de Shield — precies wanneer je wilt gaan bladeren.
        if (++since >= 24) {
          since = 0;
          notifyListeners();
        }
      }
    }

    await Future.wait([for (var i = 0; i < 6; i++) werker()]);
    // Alles gevraagd, niets gekregen: dat is geen bibliotheek zonder hoezen maar een pc die niet
    // antwoordt of een sleutel die geweigerd wordt. Eén regel is genoeg om het verschil te kunnen
    // zien; zonder die regel is er niets om naar te kijken.
    hoezenMislukt = gevraagd > 0 && gelukt == 0;
    if (hoezenMislukt) {
      debugPrint('hoezen: $gevraagd gevraagd aan de pc, geen enkele gekregen — '
          'staat de pc aan, en klopt het adres nog?');
    }
    enriching = false;
    notifyListeners();
  }

  /// Ging de laatste hoezenronde volledig mis?
  ///
  /// Waar betekent: er is minstens één hoes bij de pc opgevraagd en er kwam er geen enkele terug.
  /// Dat is iets heel anders dan "deze platen hebben geen hoes", en het scherm hoort die twee niet
  /// door elkaar te halen.
  bool hoezenMislukt = false;

  Track _trackFromMap(Map<String, dynamic> m) => Track(
        path: m['path'] as String,
        title: m['title'] as String,
        artist: m['artist'] as String,
        album: m['album'] as String,
        trackNo: m['trackNo'] as int,
        trackTotal: (m['trackTotal'] as int?) ?? 0,
        duration: (m['durationMs'] as int) > 0 ? Duration(milliseconds: m['durationMs'] as int) : null,
        isFlac: m['isFlac'] as bool,
        year: m['year'] as int?,
        genre: m['genre'] as String?,
        addedMs: (m['addedMs'] as int?) ?? 0,
        sizeBytes: (m['sizeBytes'] as int?) ?? 0,
        sampleRate: (m['sampleRate'] as int?) ?? 0,
        bitsPerSample: (m['bitsPerSample'] as int?) ?? 0,
      );

  /// Which album a TRACK belongs to. Derived from the track's own tags, never from an Album's
  /// displayed artist: the two drifted apart once "Nunca feat. Pat Krimson" started displaying as
  /// "Nunca", and the cover snapshot below — stored under one and looked up under the other —
  /// silently dropped that album's covers on every regroup, including a hand-picked one.
  /// Both the snapshot and the grouping go through here so they cannot diverge again.
  /// Which album a track belongs to.
  ///
  /// Artist and title alone merged two EDITIONS of one record: a single Backstreet Boys folder held
  /// tracks claiming 12, 16 and 13 tracks total, so the page showed two number sixes, two number
  /// tens, and "Quit Playing Games" twice. The track total is the one tag that separates them.
  ///
  /// Only when a track total is actually stated. Files without one — untagged rips, and everything
  /// that isn't FLAC, since the generic reader doesn't report it — stay on the plain album key
  /// exactly as before. Guessing which edition those belong to would scatter a library, and being
  /// wrong there is worse than the merging this fixes.
  String _groupKey(Track t) {
    if (t.album.isEmpty) return 'single::${t.path}';
    final base = 'album::${artistKey(t.artist)}|${normKey(t.album)}';
    // The user's word beats the tags: a record they merged stays merged.
    if (_merged.contains(base)) return base;
    return editionSplit(_byBase[base]) ? '$base|${t.trackTotal}' : base;
  }

  /// Tracks of one artist+album title, kept so [_groupKey] can ask whether that title needs
  /// splitting before it answers for any single track.
  final Map<String, List<Track>> _byBase = {};

  /// Every track filed under one artist+title, whatever edition it belongs to.
  List<Track>? editionsOfRecord(String baseKey) => _byBase[baseKey];

  /// Does this pile of tracks hold more than one EDITION of the record?
  ///
  /// Splitting on the stated track total alone was far too eager: every ripper writes its own, so
  /// one artist came out with six identical "Backstreet Boys" tiles, three "Backstreet's Back" and
  /// two "Black & Blue" — worse to look at than the merging it was meant to fix.
  ///
  /// So split only where merging actually breaks something: two tracks claiming the SAME number.
  /// That is the symptom — two number tens, two number sixes, "Quit Playing Games" listed twice —
  /// and where it doesn't happen, differing totals are just sloppy tagging and are left alone.
  static bool editionSplit(List<Track>? group) {
    if (group == null || group.length < 2) return false;
    final seen = <int>{};
    for (final t in group) {
      // A radio edit sitting beside the album cut is a variant of one record, not evidence of two
      // pressings of it. Downloading the album version of a track you only had an edit of is
      // exactly what the missing-track list is for, and doing so used to shatter the album: a
      // second "01 Everybody" turned one Backstreet's Back tile into four.
      if (isVariant(t)) continue;
      if (t.trackNo > 0 && !seen.add(t.trackNo)) {
        // A collision. Only worth splitting if the totals can actually separate them.
        // Zero counts as its own edition here: an untagged rip that collides with a tagged one is
        // demonstrably not from the same pressing, whatever it forgot to say.
        return group.map((x) => x.trackTotal).toSet().length > 1;
      }
    }
    return false;
  }

  /// Regroup tracks into albums. Public so a test can reproduce the "edit one album, another
  /// album loses its cover" regression without going through the on-disk correction path.
  void rebuildAlbums() {
    // Which titles hold more than one edition has to be known BEFORE any track is keyed, including
    // for the cover snapshot below — the two must never disagree about where an album lives.
    _byBase.clear();
    for (final t in tracks) {
      if (t.album.isEmpty) continue;
      _byBase.putIfAbsent('album::${artistKey(t.artist)}|${normKey(t.album)}', () => []).add(t);
    }

    // Snapshot the covers of the CURRENT albums. Rebuilding makes fresh Album objects with null
    // covers, so without this ANY caller (delete, correction, …) would blank the grid until the
    // next scan/enrich. This is the fix for "deleting a track wipes all album covers".
    //
    // Keyed by TRACK PATH, not by group key. The group key is exactly what a regroup changes, so
    // keying on it lost the covers of any album that moved — and correcting a record's numbering
    // moves it by definition: repairing the duplicate numbers is what makes editionSplit() stop
    // splitting, which is the whole point and would have blanked the record it just fixed.
    final coversByPath = <String, _Covers>{};
    for (final a in albums) {
      if (a.tracks.isEmpty) continue;
      final snap = _Covers.of(a);
      for (final t in a.tracks) {
        coversByPath[t.path] = snap;
      }
    }

    final canonical = _rebuildCanonicalArtists();

    final map = <String, List<Track>>{};
    for (final t in tracks) {
      // No album tag => its own single (never grouped under the root folder name).
      // Group on NORMALISED artist+album: "Backstreet's Back" with a curly ’ and with a
      // straight ' are the same album and must not show up twice.
      map.putIfAbsent(_groupKey(t), () => []).add(t);
    }
    albums = map.entries.map((e) {
      final single = e.key.startsWith('single::');
      final ts = single ? e.value : _dedupeTracks(e.value);
      ts.sort((a, b) => a.trackNo.compareTo(b.trackNo));
      final main = splitFeatured(ts.first.artist, ts.first.title).main;
      final artist = canonical[artistKey(main)] ?? main;
      final al = Album(single ? ts.first.title : ts.first.album, artist, ts, isSingle: single);
      // Only where the title actually split — a lone album needs no edition label.
      if (!single && editionSplit(_byBase['album::${artistKey(ts.first.artist)}|${normKey(ts.first.album)}'])) {
        final n = ts.first.trackTotal;
        al.edition = n > 0 ? '$n nummers' : 'zonder nummering';
      }
      // Any of this album's tracks will do — they all carried the same snapshot. Taking the first
      // that still has one survives a track being deleted or moved out from under it.
      for (final t in ts) {
        final saved = coversByPath[t.path];
        if (saved == null) continue;
        saved.applyTo(al);
        break;
      }
      return al;
    }).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    _rebuildTrackIndexes();

    // Put a durable name on whatever grouping just decided. LAST, and reading only — see the header
    // of album_id.dart: the moment identity feeds back into grouping, merge/split/renumber gains a
    // loop where a previous answer constrains the next one.
    uids.reconcile(albums);
    _albumsPerDir = albumsPerDirOf(albums);
  }

  /// ONE spelling per artist. Tags disagree about capitalisation and accents ("Lady Gaga" vs
  /// "Lady GaGa", "Beyoncé" vs "Beyonce"), which used to put the same person in the artist list
  /// twice. Count every spelling across the whole library and show the best one everywhere.
  /// The MAIN artist, not the full credit: "Lady Gaga feat. Beyoncé" is a Lady Gaga track and
  /// belongs on her album — Beyoncé is a guest, not a separate act in your artist list.
  ///
  /// Shared with client mode ([loadRemote]) rather than repeated there: it decides what the artist
  /// list is called, and two copies of that rule would eventually disagree about one artist and be
  /// very hard to see.
  Map<String, String> _rebuildCanonicalArtists() {
    final spellings = <String, Map<String, int>>{};
    for (final t in tracks) {
      final main = splitFeatured(t.artist, t.title).main;
      spellings
          .putIfAbsent(artistKey(main), () => <String, int>{})
          .update(main, (n) => n + 1, ifAbsent: () => 1);
    }
    final canonical = {for (final e in spellings.entries) e.key: canonicalName(e.value)};
    _canonicalArtists
      ..clear()
      ..addAll(canonical);
    return canonical;
  }

  /// The lookups every screen reads: "do I already own this?" (skips duplicate downloads), and
  /// path → album/track (cover per track, and resuming where you left off). Also shared with
  /// client mode, where the paths are stream URLs instead of files.
  void _rebuildTrackIndexes() {
    _owned.clear();
    for (final t in tracks) {
      _owned.putIfAbsent(trackIdentity(t.artist, t.title), () => t);
    }
    _albumByPath.clear();
    _trackByPath.clear();
    for (final a in albums) {
      for (final t in a.tracks) {
        _albumByPath[t.path] = a;
        _trackByPath[t.path] = t;
      }
    }

    // Everything in the flat list that no album claims.
    //
    // These indexes were built from `albums` alone, and [_dedupeTracks] leaves the second copy of a
    // take OUT of its album while the flat list keeps every file. So a folded-away duplicate was
    // visible in Tracks, playable from there, and invisible to all three lookups: no cover
    // (coverForTrack), no album on the now-playing screen (albumForPath), and — the one that stings —
    // no resume, because `player.restore` looks the last-played path up through trackByPath and got
    // null. Close the app on such a track and it simply did not come back.
    //
    // Filed against the album that absorbed it, found by the identity the dedupe folded on, so the
    // cover and the album page are the ones that record actually belongs to.
    final byIdentity = <String, Album>{};
    for (final a in albums) {
      for (final t in a.tracks) {
        byIdentity.putIfAbsent(trackIdentity(t.artist, t.title), () => a);
      }
    }
    for (final t in tracks) {
      if (_trackByPath.containsKey(t.path)) continue;
      _trackByPath[t.path] = t;
      final a = byIdentity[trackIdentity(t.artist, t.title)];
      if (a != null) _albumByPath[t.path] = a;
    }
  }

  /// Fill missing album covers. Phase 1 loads everything already on disk (instant,
  /// can't hang); phase 2 fetches the rest from the web (each call has a timeout).
  Future<void> enrich(AppSettings settings) async {
    final enricher = CoverEnricher(settings);
    // Phase 1 — instant: on-disk cache only, no network. User-corrected covers first
    // (they win over embedded/enriched and must survive a rescan).
    for (final album in albums) {
      final fixed = await enricher.fixedCover(album);
      if (fixed != null) {
        album.correctedCover = fixed;
        continue;
      }
      // A sleeve traced to a pinned pressing on an earlier run. Restored BEFORE the check below,
      // because it has to win against the embedded art rather than fill in for its absence — for a
      // rip tagged with the wrong record, `album.cover` is not null, it is confidently wrong.
      if (album.resolvedCover == null) {
        final traced = await enricher.resolvedCover(album);
        if (traced != null) {
          album.resolvedCover = traced.$1;
          album.resolvedFrom = traced.$2;
        }
      }
      if (album.cover != null) continue;
      final bytes = await enricher.cached(album);
      if (bytes != null) album.enriched = bytes;
    }
    notifyListeners();
    // Phase 2 fills the gaps over the network, and startup does NOT wait for it — see
    // [enrichFromWeb]. Everything on screen comes from phase 1 above.
    unawaited(enrichFromWeb(settings));
  }

  /// The sweep that is running, if one is.
  ///
  /// Nothing stopped a second one before: a rescan, a new Discogs token and the album screen all
  /// call enrich, and two sweeps over the same list each set `enriching` and each cleared it — so
  /// the status line went off while the other was still going, and every album was fetched twice.
  ///
  /// Held as the FUTURE rather than a bool so a caller that wants the finished picture can wait for
  /// the one already in flight. Returning immediately would be a lie of a different kind: "done"
  /// when the work has not happened yet.
  Future<void>? _sweep;

  /// Fetch the covers phase 1 could not find, in the background.
  ///
  /// This used to be awaited inside [enrich], and [enrich] is awaited during startup — so restoring
  /// the queue you left playing and resuming interrupted downloads both sat behind a full network
  /// sweep. Nobody is waiting for a cover that is not on screen yet; they ARE waiting for their
  /// music.
  ///
  /// Fetched a few at a time rather than one after another. Each album is up to three services in
  /// sequence (Deezer, Discogs, the archive) with eight-second timeouts, and doing that strictly in
  /// turn is what made this take half a minute. Six at a time: enough to overlap the waiting,
  /// little enough that the services are not being leaned on.
  Future<void> enrichFromWeb(AppSettings settings) =>
      _sweep ??= _enrichFromWeb(settings).whenComplete(() => _sweep = null);

  Future<void> _enrichFromWeb(AppSettings settings) async {
    enriching = true;
    notifyListeners();
    try {
      final enricher = CoverEnricher(settings);
      // Albums already searched and found to have nothing are skipped entirely — that check is a
      // stat, not a request. See [CoverEnricher.searchedAndEmpty].
      final todo = <Album>[];
      for (final a in albums) {
        if (a.cover != null) continue;
        if (await enricher.searchedAndEmpty(a)) continue;
        todo.add(a);
      }
      const atOnce = 6;
      for (var i = 0; i < todo.length; i += atOnce) {
        final batch = todo.skip(i).take(atOnce).toList();
        await Future.wait([
          for (final album in batch)
            enricher.fetchAndCache(album).then((bytes) {
              if (bytes != null) album.enriched = bytes;
            }).catchError((_) {}),
        ]);
        notifyListeners();
      }
    } finally {
      enriching = false;
      notifyListeners();
    }
  }

  /// Artist photos (Deezer) + bios (TheAudioDB). Phase 1 = disk cache (instant),
  /// phase 2 = network for whatever is still missing.
  Future<void> enrichArtists(AppSettings settings) async {
    final enricher = CoverEnricher(settings);
    // Phase 1 — instant: on-disk cache only.
    for (final name in artists) {
      if (!artistImages.containsKey(name)) {
        final b = await enricher.cachedArtist(name);
        if (b != null) artistImages[name] = b;
      }
      if (!artistBios.containsKey(name)) {
        final bio = await enricher.cachedBio(name);
        if (bio != null) artistBios[name] = bio;
      }
    }
    notifyListeners();
    unawaited(enrichArtistsFromWeb(settings));
  }

  Future<void>? _artistSweep;

  /// Portraits and bios over the network, in the background and a few at a time.
  ///
  /// Same two reasons as [enrichFromWeb]: this was awaited during startup, and every artist was a
  /// photo lookup followed by a bio lookup strictly in turn. With sixty artists that is a hundred
  /// and twenty round trips in single file, at the end of a start nobody thinks is still going.
  Future<void> enrichArtistsFromWeb(AppSettings settings) =>
      _artistSweep ??= _enrichArtistsFromWeb(settings).whenComplete(() => _artistSweep = null);

  Future<void> _enrichArtistsFromWeb(AppSettings settings) async {
    try {
      final enricher = CoverEnricher(settings);
      final todo = [
        for (final n in artists)
          if (!artistImages.containsKey(n) || !artistBios.containsKey(n)) n,
      ];
      const atOnce = 6;
      for (var i = 0; i < todo.length; i += atOnce) {
        await Future.wait([
          for (final name in todo.skip(i).take(atOnce))
            Future(() async {
              if (!artistImages.containsKey(name)) {
                final b = await enricher.fetchArtistImage(name);
                if (b != null) artistImages[name] = b;
              }
              if (!artistBios.containsKey(name)) {
                final bio = await enricher.fetchArtistBio(name);
                if (bio != null) artistBios[name] = bio;
              }
            }).catchError((_) {}),
        ]);
        notifyListeners();
      }
    } finally {
      notifyListeners();
    }
  }

  /// artistKey → the one spelling we show. A Track keeps whatever its tag says (replacing Track
  /// objects would break the player's identity checks), so anything that DISPLAYS a track's
  /// artist runs it through [displayArtist] to stay consistent with the artist list.
  final Map<String, String> _canonicalArtists = {};

  String displayArtist(String raw) {
    final main = splitFeatured(raw, '').main;
    return _canonicalArtists[artistKey(main)] ?? main;
  }

  /// True if this name is an artist you actually own — decides whether tapping it can show a
  /// local page or has to go to the online catalogue.
  bool hasArtist(String name) => _canonicalArtists.containsKey(artistKey(name));

  List<String> get artists {
    final set = <String>{};
    for (final a in albums) {
      set.add(a.artist);
    }
    final list = set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }
}

/// What taking an official pressing's numbering would do to one track.
class RenumberStep {
  final Track track;

  /// What the pressing says this track is. Null when nothing on the pressing matched it — then the
  /// track keeps its tags, which is the only safe answer.
  final ChoiceTrack? official;
  final int? newNo;
  const RenumberStep(this.track, this.official, this.newNo);

  /// De titel die deze stap ZOU opleveren.
  ///
  /// Niet zomaar die van de persing. Zie [titelNaOvername]: draagt jouw titel een versiemerk dat de
  /// persing niet heeft, dan blijft die staan. Anders liet dit venster regels zien als
  /// `7 → 7  Fields Of Gold (My Songs Version) → Fields Of Gold` — het nummer klopte al en het
  /// enige wat er gebeurde was dat er informatie van af ging.
  String get nieuweTitel => titelNaOvername(track.title, official?.title);

  bool get changes => newNo != null && (newNo != track.trackNo || nieuweTitel != track.title);
  bool get unmatched => official == null;
}

/// Everything taking a pressing's numbering would do, so it can be read before it is done.
class RenumberPlan {
  final List<RenumberStep> steps;

  /// The total the pressing states, written alongside so edition splitting stops seeing a record
  /// whose tracks disagree about how long it is.
  final int total;
  const RenumberPlan(this.steps, this.total);

  List<RenumberStep> get changing => steps.where((s) => s.changes).toList();
  List<RenumberStep> get unmatched => steps.where((s) => s.unmatched).toList();

  /// Two tracks landing on one number. Refused rather than applied: the numbering is being fixed
  /// BECAUSE it collides, and swapping one collision for another helps nobody.
  bool get collides {
    final seen = <int>{};
    for (final s in steps) {
      final n = s.newNo;
      if (n != null && !seen.add(n)) return true;
    }
    return false;
  }

  /// Two tracks ending up with one title. [LibraryStore._dedupeTracks] keys on artist+title, so
  /// this would not look like a numbering mistake — it would look like a track disappearing.
  bool get titleCollides {
    final seen = <String>{};
    for (final s in steps) {
      if (!seen.add(normKey(s.nieuweTitel))) return true;
    }
    return false;
  }

  bool get safe => !collides && !titleCollides && changing.isNotEmpty;
}

/// One file's part of a move, so the plan can be shown before anything is touched.
class MovePlan {
  final Track track;
  final String from;

  /// Where it would land, or null when the target album's folder can't be worked out — then the
  /// file stays put and only the grouping changes.
  final String? to;

  /// What happens to this file, in one word, so the dialog can say it rather than imply it.
  final MoveFate fate;
  const MovePlan(this.track, this.from, this.to, [this.fate = MoveFate.moves]);

  bool get movesFile => to != null && to != from;

  /// The filename, for a plan the user has to read a screenful of.
  String get name => File(from).uri.pathSegments.last;
}

/// Where the superseded copy of a colliding track is parked.
///
/// Not deleted — the user asked to tidy the folder, not to lose a file. Still scanned, and still
/// hidden from the tracklist by [LibraryStore._dedupeTracks], exactly as a duplicate is today.
/// Waar een verslagen kopie geparkeerd wordt. Eén naam, gedefinieerd in organize.dart -- dat bestand
/// zit lager in de stapel en gebruikt hem ook.
const dupeFolder = parkeerMap;

/// What one track's file would do in a gather, and why.
enum MoveFate {
  /// Straight into the target folder under its own name.
  moves,

  /// The name is taken by a better copy, so this one is parked in [dupeFolder].
  toDupes,

  /// Already where it belongs, or there is nowhere to put it.
  stays,
}

/// Everything a merge would do on disk, so it can be read before anything is touched.
class MergePlan {
  /// The folder the record is being gathered into.
  final String? folder;
  final List<MovePlan> items;
  const MergePlan(this.folder, this.items);

  int get moving => items.where((i) => i.fate == MoveFate.moves).length;
  int get parking => items.where((i) => i.fate == MoveFate.toDupes).length;
  int get staying => items.where((i) => i.fate == MoveFate.stays).length;

  /// Nothing to do — every file is already in one folder.
  bool get isNoop => moving == 0 && parking == 0;

  /// "14 verhuizen · 3 naar _dubbel · 1 blijft staan"
  String get summary => [
        if (moving > 0) '$moving ${moving == 1 ? 'verhuist' : 'verhuizen'}',
        if (parking > 0) '$parking naar $dupeFolder',
        if (staying > 0) '$staying ${staying == 1 ? 'blijft' : 'blijven'} staan',
      ].join(' · ');
}

/// What writing one file's tags would change, old value beside new so it can be read first.
class NormaliseStep {
  final Track track;

  /// The pressing entry this file was matched to, or null when nothing matched.
  final ChoiceTrack? official;

  /// The new values. Null means "leave this field alone".
  final String? title;
  final int? trackNo;

  /// Why this file is being skipped, in words, or null when it is not.
  final String? skipped;

  /// Why this file only gets the album fields, in words. Set when the pressing does not recognise
  /// it — its own title and number are left alone.
  final String? note;

  const NormaliseStep(this.track, this.official,
      {this.title, this.trackNo, this.skipped, this.note});

  String get name => File(track.path).uri.pathSegments.last;
  bool get willWrite => skipped == null;

  /// Album, albumartiest, aantal en jaar — but not the title or the number.
  ///
  /// Measured on the real folder: leaving an unrecognised file out entirely got Backstreet's Back
  /// from four tiles down to two, not one. The second rip of track 10 was titled differently, so
  /// the pressing did not know it, so it kept TOTALTRACKS=0 — and one file with a different total
  /// is a tile. We do not know WHICH track it is; we do know which record it is on, because the
  /// user is looking at that record and confirming this album by name.
  bool get albumOnly => skipped == null && official == null;
}

/// Everything that pulling an album's tags into line would do, so it can be shown before it is done.
///
/// The album title and the track total are deliberately NOT per file: they are the two fields that
/// split one record into several tiles, so they get one value for the whole album or the exercise is
/// pointless. Backstreet's Back held thirteen files claiming four different totals and two different
/// apostrophes; that is four tiles for one record.
class NormalisePlan {
  final List<NormaliseStep> steps;

  /// The one spelling every file will carry.
  final String album;
  final String albumArtist;

  /// The one total every file will carry — the length of the pressing.
  final int total;
  final int? year;

  const NormalisePlan(this.steps,
      {required this.album, required this.albumArtist, required this.total, this.year});

  List<NormaliseStep> get writing => steps.where((s) => s.willWrite).toList();
  List<NormaliseStep> get skipped => steps.where((s) => !s.willWrite).toList();

  /// Written, but only the album fields — the pressing did not recognise these.
  List<NormaliseStep> get albumOnly => steps.where((s) => s.albumOnly).toList();

  /// Written in full: title and number come from the pressing.
  List<NormaliseStep> get renamed => steps.where((s) => s.willWrite && !s.albumOnly).toList();

  /// The values on disk today, so the dialog can say what is actually being fixed.
  Set<String> get albumsNow => {for (final s in steps) s.track.album};
  Set<int> get totalsNow => {for (final s in steps) s.track.trackTotal};

  /// Every pair this plan would land on one number or one title, named.
  ///
  /// One definition, so the guard and the message can never disagree. And it names the files: "two
  /// files would collide" without saying WHICH two leaves you nothing to act on — the dialog said
  /// "choose an edition that fits" without a word about where it didn't fit.
  ///
  /// A number collision counts only between files the pressing recognised; a file it did not
  /// recognise keeps the number it already had, which we are not changing.
  ///
  /// A title collision counts only when this plan CREATES it. Two files that already carry the same
  /// title are already folded into one in the tracklist; refusing over that would block the feature
  /// on exactly the messy albums it exists for — two rips of one record, both tagged "Missing You".
  List<({bool number, String text})> get clashList {
    final out = <({bool number, String text})>[];
    final byNo = <int, NormaliseStep>{};
    for (final s in writing) {
      final n = s.trackNo;
      if (n == null) continue;
      final prev = byNo[n];
      if (prev == null) {
        byNo[n] = s;
        continue;
      }
      out.add((number: true, text: 'nummer $n — ${prev.name} en ${s.name}'));
    }

    final already = <String>{}, twice = <String>{};
    for (final s in writing) {
      if (!already.add(normKey(s.track.title))) twice.add(normKey(s.track.title));
    }
    final byTitle = <String, NormaliseStep>{};
    for (final s in writing) {
      final k = normKey(s.title ?? s.track.title);
      final prev = byTitle[k];
      if (prev == null) {
        byTitle[k] = s;
        continue;
      }
      if (twice.contains(k)) continue; // stond er al zo in — niet onze schuld
      out.add((number: false, text: '"${s.title ?? s.track.title}" — ${prev.name} en ${s.name}'));
    }
    return out;
  }

  List<String> get clashes => [for (final c in clashList) c.text];

  bool get collides => clashList.any((c) => c.number);
  bool get titleCollides => clashList.any((c) => !c.number);

  bool get safe => !collides && !titleCollides && writing.isNotEmpty;
}

extension LibraryNormalise on LibraryStore {
  /// What pulling this album's tags into line would do. Nothing is written.
  ///
  /// This is the one operation here that changes the FILES rather than working around them. Until
  /// now the app had three ways to paper over disagreeing tags — a correction in memory, a renumber
  /// into corrections.json, and merging editions by hand — and the tags on disk stayed as wrong as
  /// they were. Anything else reading that folder (Roon, a phone, the next rescan on another
  /// machine) still saw four records.
  ///
  /// Matched on TITLE and running time like [planRenumber], never on the existing number: that
  /// number is the broken input.
  /// Every file of this record, including the ones the app split off into their own tiles.
  ///
  /// Planning over the clicked tile alone cannot work, and the GUI showed it straight away: that
  /// tile held 8 of the 13 files, all agreeing on 11, so there was nothing to reconcile INSIDE it.
  /// The disagreement lives BETWEEN the tiles — which is why there are tiles. [_groupKey] splits on
  /// the track total but keeps one base key per artist+title, and normKey already folds the curly
  /// apostrophe into a straight one, so that key gathers all four.
  List<Track> recordTracks(Album album) {
    final first = album.tracks.firstOrNull;
    if (first == null || first.album.isEmpty) return album.tracks;
    final all = editionsOfRecord('album::${artistKey(first.artist)}|${normKey(first.album)}');
    if (all == null || all.isEmpty) return album.tracks;
    // The clicked tile's own order first, so the list reads like the page it was opened from.
    final seen = {for (final t in album.tracks) t.path};
    return [...album.tracks, ...all.where((t) => !seen.contains(t.path))];
  }

  NormalisePlan planNormalise(Album album, List<ChoiceTrack> official, {String? albumTitle, int? year}) {
    final pool = [...official];
    final steps = <NormaliseStep>[];
    for (final t in recordTracks(album)) {
      // FLAC and MP3. Anything else this app has no writer for, and a writer that drops the fields
      // it does not model is worse than leaving the file alone — so those are named here rather
      // than quietly skipped.
      //
      // The MP3 half was added later, and this line was missed the first time round: `writeTagFields`
      // and `applyRecognised` had both learned about ID3 while the plan still refused every mp3
      // before it got that far. The one route that writes tags in bulk therefore never used the new
      // writer at all, which is exactly the sort of half-landed change a screenshot catches and a
      // green test suite does not.
      final laag = t.path.toLowerCase();
      if (!laag.endsWith('.flac') && !laag.endsWith('.mp3')) {
        steps.add(NormaliseStep(t, null,
            skipped: 'alleen FLAC en MP3 kan de app veilig herschrijven'));
        continue;
      }
      final best = matchOfficial(pool, t.title, t.duration?.inSeconds ?? 0);
      if (best == null) {
        // Not "leave it alone": see [NormaliseStep.albumOnly] for why that left two tiles standing.
        steps.add(NormaliseStep(t, null,
            note: 'niet herkend in deze persing — alleen album en aantal, titel en nummer blijven'));
        continue;
      }
      pool.remove(best);
      // Dezelfde regel als bij de nummering, en hier is hij het belangrijkst: DEZE weg schrijft de
      // titel echt in het bestand. Zie [titelNaOvername] — een persing mag geen versiemerk van jouw
      // kopie afhalen.
      final titel = titelNaOvername(t.title, best.title);
      steps.add(NormaliseStep(t, best,
          title: titel.trim().isEmpty ? null : titel.trim(),
          trackNo: trackNoFromPosition(best.position, best.disc, official)));
    }
    return NormalisePlan(
      steps,
      album: (albumTitle ?? album.title).trim(),
      albumArtist: album.artist.trim(),
      total: official.length,
      year: year ?? album.year,
    );
  }

  /// Write the plan into the files.
  ///
  /// Each file goes through [stampTags] → `writeFlacFields`, which rebuilds only the comment block
  /// and copies every other block byte for byte — so the embedded cover, the ReplayGain values and
  /// anything hand-written survive — and lands atomically via tmp-then-rename.
  ///
  /// Returns what was written AND what was not. A file the player has open cannot be replaced —
  /// the rename fails — and that is not rare: normalising the record you are listening to hits it
  /// every time. Measured here: the dialog promised twelve files, eleven landed, and the one that
  /// did not was the track playing at that moment. A count alone hides that; "11 written" reads
  /// like success when twelve were asked for.
  Future<({int written, List<String> failed})> applyNormalise(NormalisePlan plan) async {
    var written = 0;
    final failed = <String>[];
    for (final s in plan.writing) {
      final tags = TrackTags(
        title: s.title ?? s.track.title,
        artist: s.track.artist,
        album: plan.album,
        trackNo: s.trackNo ?? s.track.trackNo,
        albumArtist: plan.albumArtist,
        trackTotal: plan.total,
        year: plan.year,
      );
      // What is in the file right now, for exactly the fields about to be overwritten. Read before
      // the write or there is nothing to go back to; a field that is absent is recorded as null so
      // the undo deletes it again instead of leaving our value behind.
      // Read from the container the file actually is, or the undo has nothing to put back: an mp3
      // read with the FLAC reader comes back empty, and "empty" means "this field was absent", which
      // would make undoing DELETE the tags instead of restoring them.
      final raw = s.track.path.toLowerCase().endsWith('.mp3')
          ? readMp3RawFields(File(s.track.path))
          : readFlacRawFields(File(s.track.path));
      final before = {for (final k in tags.vorbisFields.keys) k: raw[k.toLowerCase()]};
      if (!await stampTags(File(s.track.path), tags)) {
        failed.add(s.name);
        continue;
      }
      written++;
      _tagUndo[s.track.path] = before;
      // The file now says the right thing, so a correction saying the same thing is a second truth
      // that can only drift. Cleared for the files that were ACTUALLY written, and only the fields
      // this just wrote — a pinned pressing or a corrected artist is the user's and stays.
      final c = _corrections[s.track.path];
      if (c != null) {
        c.remove('trackNo');
        c.remove('trackTotal');
        c.remove('title');
        if (c.isEmpty) _corrections.remove(s.track.path);
      }
    }
    if (written > 0) {
      await _saveTagUndo();
      await saveCorrectionsNow();
      await scan();
    }
    return (written: written, failed: failed);
  }

  /// Write what the AUDIO says a file is into the file itself: artist and title, nothing else.
  ///
  /// The narrowest possible write, on purpose. AcoustID answers "which recording is this", and that
  /// is exactly two fields — it says nothing about which album this copy came from, which track
  /// number it had there, or what year that pressing is, so this touches none of them. A record
  /// tagged "Various Artists — Jij Bent Zo Mooi" becomes "Petra — Jij bent zo mooi" and stays in the
  /// same folder, on the same album, under the same number.
  ///
  /// Same guarantees as [applyNormalise], because it is the same machinery: the previous values are
  /// read BEFORE the write so [undoTagWrites] can put them back, a field that was absent is recorded
  /// as null so undoing deletes it again rather than leaving ours behind, and a file the player has
  /// open comes back in `failed` instead of being silently skipped.
  Future<({int written, List<String> failed})> applyRecognised(
      Map<Track, ({String artist, String title})> naming) async {
    var written = 0;
    final failed = <String>[];
    for (final e in naming.entries) {
      final t = e.key;
      final naam = t.path.split(Platform.pathSeparator).last;
      final laag = t.path.toLowerCase();
      final mp3 = laag.endsWith('.mp3');
      if (!mp3 && !laag.endsWith('.flac')) {
        failed.add('$naam — alleen FLAC en MP3 kan de app veilig herschrijven');
        continue;
      }
      final raw = mp3 ? readMp3RawFields(File(t.path)) : readFlacRawFields(File(t.path));
      final velden = <String, String?>{
        'ARTIST': e.value.artist.isEmpty ? null : e.value.artist,
        'TITLE': e.value.title.isEmpty ? null : e.value.title,
      }..removeWhere((_, v) => v == null);
      if (velden.isEmpty) continue;
      final before = {for (final k in velden.keys) k: raw[k.toLowerCase()]};
      // The reason travels with the failure. "Could not write" sends someone looking for a bug;
      // "the file is read-only" and "ID3v2.2, not fully modelled" are things a person can act on,
      // and both of those are real files in this library.
      final redenen = <String>[];
      final ok = mp3
          ? writeMp3Fields(File(t.path), velden, trace: redenen.add)
          : writeFlacFields(File(t.path), velden, trace: redenen.add);
      if (!ok) {
        failed.add(redenen.isEmpty ? naam : '$naam — ${redenen.join('; ')}');
        continue;
      }
      written++;
      _tagUndo[t.path] = before;
      // A correction saying the artist or title is something else is now a second truth that can
      // only drift away from the file. The rest of the user's corrections stay theirs.
      final c = _corrections[t.path];
      if (c != null) {
        c..remove('title')..remove('artist');
        if (c.isEmpty) _corrections.remove(t.path);
      }
    }
    if (written > 0) {
      await _saveTagUndo();
      await saveCorrectionsNow();
      await scan();
    }
    return (written: written, failed: failed);
  }

  /// The same recording held twice in this record, across every tile it was split into.
  ///
  /// Reads the files to decide which copy wins — a handful of pairs per album, so cheap enough to
  /// ask for on opening a page, and the answer is what the user needs before they can act on it.
  List<SameRecordingPair> duplicateRecordings(Album album, {Map<String, List<int>> prints = const {}}) =>
      sameRecordingPairs(
        recordTracks(album),
        better: (a, b) => firstIsBetter(File(a.path), File(b.path)),
        why: (keep, drop) => whyBetter(File(keep.path), File(drop.path)),
        prints: prints,
      );

  /// Every pair of files in the WHOLE library that hold the same recording.
  ///
  /// [duplicateRecordings] only ever looks inside one record, and the duplicates that cost the most
  /// disk are not there. Measured over 389 files: one track sitting loose in the root as well as
  /// filed under its album, the same recording downloaded twice into two different Soulseek folders,
  /// and one compilation track held as both .flac and .m4a. None of those share a record, so none of
  /// them were findable before.
  ///
  /// Length first, fingerprints second. Comparing all 389 against each other is 75,000 pairs; only
  /// comparing those already within [_dupeSlack] seconds of each other brings it to about 10,000,
  /// and a pair whose lengths disagree by more than that is not the same recording anyway.
  ///
  /// Fingerprints only — deliberately no title fallback. Across records the titles are worth nothing:
  /// "Intro" appears on nine albums, and a name-based rule here would offer real music for deletion.
  /// [tool] is injected only by tests: outside the installed app there is no executable next to
  /// [Platform.resolvedExecutable], so a test that does not pass it silently measures nothing.
  Future<List<SameRecordingPair>> duplicatesEverywhere({
    void Function(int done, int total)? onProgress,
    String? tool,
  }) async {
    final fp = Fingerprinter(toolPath: tool);
    if (!fp.available) return const [];

    final prints = <String, List<int>>{};
    final secs = <String, double>{};
    final all = tracks.where((t) => t.path.isNotEmpty).toList();
    for (var i = 0; i < all.length; i++) {
      final a = await fp.of(all[i].path);
      if (a != null && a.raw.isNotEmpty) {
        prints[all[i].path] = a.raw;
        secs[all[i].path] = a.seconds;
      }
      onProgress?.call(i + 1, all.length);
    }

    final heard = all.where((t) => prints.containsKey(t.path)).toList()
      ..sort((x, y) => secs[x.path]!.compareTo(secs[y.path]!));
    final out = <SameRecordingPair>[];
    final spoken = <String>{};
    for (var i = 0; i < heard.length; i++) {
      final a = heard[i];
      if (spoken.contains(a.path)) continue;
      // Sorted by length, so the moment the gap opens past the slack every later file is further
      // still. That turns the inner loop from "the rest of the library" into a handful.
      for (var j = i + 1; j < heard.length; j++) {
        final b = heard[j];
        if (secs[b.path]! - secs[a.path]! > _dupeSlack) break;
        if (spoken.contains(b.path)) continue;
        if (similarity(prints[a.path]!, prints[b.path]!) < sameRecordingScore) continue;
        final aWins = firstIsBetter(File(a.path), File(b.path));
        final keep = aWins ? a : b, drop = aWins ? b : a;
        out.add(SameRecordingPair(keep, drop, whyBetter(File(keep.path), File(drop.path))));
        spoken..add(a.path)..add(b.path);
        break;
      }
    }
    return out;
  }

  /// Meet elk FLAC-bestand door: is het écht wat het zegt te zijn?
  ///
  /// Saber's vraag: "hoe weet ik dat een FLAC echt een FLAC is en niet een mp3 die naar FLAC is
  /// omgezet?" Drie proeven — de onderste bits, inhoud boven 22 kHz, en een harde afkap in het
  /// spectrum. Zie `echtheid.dart`; daar staat ook waarom alleen de derde vals alarm kan geven en welke
  /// vier vangnetten daaromheen zitten.
  ///
  /// Gemeten over deze bibliotheek: 676 bestanden in ruim een minuut, 124 ms per stuk. Daarna komt het
  /// uit de cache en is het onmiddellijk.
  ///
  /// Alleen FLAC. Bij een mp3 is een afkap de definitie en geen bevinding, en voor ALAC/APE/WAV zijn er
  /// geen betrouwbare kopgetallen om iets tegen te spreken.
  Future<({int onderzocht, int betrapt, int onbeoordeelbaar})> meetEchtheid({
    void Function(int done, int total)? onProgress,
  }) async {
    final meter = Echtheidsmeter(cacheMap: '$_appDir${Platform.pathSeparator}echtheid');
    final lijst = tracks.where((t) => t.isFlac && t.path.isNotEmpty).toList();
    var betrapt = 0, onbeoordeelbaar = 0;
    if (!meter.available) {
      return (onderzocht: 0, betrapt: 0, onbeoordeelbaar: lijst.length);
    }
    for (var i = 0; i < lijst.length; i++) {
      final t = lijst[i];
      final o = await meter.van(t.path,
          kopSampleRate: t.sampleRate,
          kopBits: t.bitsPerSample,
          duurSeconden: (t.duration?.inSeconds ?? 0).toDouble());
      if (o == null || o.isOnbekend) {
        onbeoordeelbaar++;
      } else {
        await onthoudOordeel(t.path, o);
        if (o.isNep) betrapt++;
      }
      onProgress?.call(i + 1, lijst.length);
    }
    // Publiek en het meldt zich — `notifyListeners` is beschermd en deze functie woont in een
    // uitbreiding. Zonder deze regel blijven de merkjes in de spelerbalk en de lijsten weg tot er
    // toevallig om een andere reden hertekend wordt.
    refreshFromCorrections();
    return (onderzocht: lijst.length, betrapt: betrapt, onbeoordeelbaar: onbeoordeelbaar);
  }

  /// Wat een vervanger van [t] moet gaan heten — de tags van het bestand dat vervangen wordt.
  ///
  /// Saber, eerder: *"ik heb de tag bewerkt, maar toch blijven de originele tags erin, mijn tags
  /// moeten overwriten. De tags die met Soulseek worden meegegeven zijn meestal niet de goeie."*
  /// Dat is hier de hele bedoeling: de peer levert het geluid, dit bestand levert de identiteit. Wat
  /// jij met de hand hebt rechtgezet blijft dus staan, ook als de vervanger van een uploader komt
  /// die er "13 - track13.flac" van maakt.
  ///
  /// De albumartiest komt van de plaat waar het nummer onder ligt en niet uit het bestand: bij een
  /// duet is ARTIST beide namen en ALBUMARTIST van wie de plaat is, en dat verschil is precies wat
  /// een gastbijdrage anders over een halve bibliotheek uitsmeert.
  ///
  /// LET OP — [TrackTags.isAuthoritative] is pas waar met `trackTotal > 0` of een jaartal. Een
  /// bestand dat geen van beide draagt levert een niet-gezaghebbende tagset, en dan valt
  /// `placeFileDetailed` terug op zijn gewone gelijkenistoets in plaats van "dit pad ÍS de
  /// identiteit". Dat is geen achteruitgang — zo gedraagt elke andere download zich ook — maar het
  /// betekent dat de vervanging dan naast het origineel kan landen in plaats van erop.
  TrackTags tagsVoorVervanger(Track t) => TrackTags(
        title: t.title,
        artist: t.artist,
        album: t.album,
        trackNo: t.trackNo,
        albumArtist: albumForPath(t.path)?.artist.trim(),
        trackTotal: t.trackTotal,
        year: t.year,
      );

  /// Alleen de bestanden die uit een MP3 komen, het ergste eerst.
  ///
  /// Dit is een andere vraag dan [betrapteBestanden], en het verschil is precies wat de gebruiker
  /// wilde weten: "zijn die dan ten minste cd-kwaliteit?" Een opgeblazen bestand — 16 bits in een
  /// 24-bits jasje, of 44,1 opgetild naar 96 — IS cd-kwaliteit; daar is niets aan te winnen door het
  /// opnieuw te halen, je krijgt exact hetzelfde geluid terug in een kleiner pak. Een afgekapt
  /// bestand is dat níét: daar staat een muur in het spectrum en wat erboven zat is weg.
  ///
  /// Gesorteerd op de plaats van die muur, oplopend. Hoe lager de muur, hoe minder er nog over is —
  /// gemeten liep dat op deze bibliotheek van 15,6 kHz (ongeveer 128 kbps) tot 21 kHz (320 of hoger),
  /// en dat is het verschil tussen "dat hoor je" en "dat hoor je niet". Het ergste hoort bovenaan.
  List<({Track track, Echtheidsoordeel oordeel})> uitMp3Bestanden() {
    final uit = <({Track track, Echtheidsoordeel oordeel})>[];
    for (final t in tracks) {
      final o = gemeten(t.path);
      if (o != null && o.band == Bandbreedte.afgekapt) uit.add((track: t, oordeel: o));
    }
    // `afkapHz` kan bij een afgekapt oordeel niet null zijn — de afkap IS wat het oordeel maakt —
    // maar sorteren mag daar niet op vertrouwen: een oud bestand op schijf uit een vorige versie
    // zou de hele lijst laten crashen in plaats van één rij verkeerd te zetten.
    uit.sort((a, b) => (a.oordeel.afkapHz ?? 0).compareTo(b.oordeel.afkapHz ?? 0));
    return uit;
  }

  /// Alles wat de proef niet doorstond, met de reden erbij — voor het overzicht na de veegbeurt.
  List<({Track track, Echtheidsoordeel oordeel})> betrapteBestanden() {
    final uit = <({Track track, Echtheidsoordeel oordeel})>[];
    for (final t in tracks) {
      final o = gemeten(t.path);
      if (o != null && o.isNep) uit.add((track: t, oordeel: o));
    }
    uit.sort((a, b) => '${a.track.artist}${a.track.album}${a.track.trackNo}'
        .compareTo('${b.track.artist}${b.track.album}${b.track.trackNo}'));
    return uit;
  }

  /// How far two lengths may differ before they cannot be the same recording. Twelve seconds is the
  /// same slack every other matcher in this app uses.
  static const double _dupeSlack = 12;

  /// The same, after actually LISTENING to the record's files.
  ///
  /// Two hundred milliseconds per track the first time and nothing ever after, so a dozen-track
  /// album costs a couple of seconds once. Worth it: on the real library the titles alone missed
  /// "Workin' Day and Night" against "Working Day And Night" — one recording, twice, in one folder —
  /// and would have offered Adele's duet for deletion. Falls straight back to the title rule when
  /// fpcalc is not installed.
  Future<List<SameRecordingPair>> duplicateRecordingsHeard(Album album) async {
    final fp = Fingerprinter();
    if (!fp.available) return duplicateRecordings(album);
    final prints = <String, List<int>>{};
    for (final t in recordTracks(album)) {
      final f = await fp.of(t.path);
      if (f != null && f.raw.isNotEmpty) prints[t.path] = f.raw;
    }
    return duplicateRecordings(album, prints: prints);
  }

  /// Move the lesser copy of each pair into the parking folder beside the album.
  ///
  /// Never deleted, only moved out of the way: the scan skips [dupeFolder], so the record stops
  /// holding the same song twice while the file itself is still there if the judgement was wrong.
  /// The same safety net [consolidate] already uses.
  Future<int> parkDuplicates(List<SameRecordingPair> pairs) async {
    final sep = Platform.pathSeparator;
    var moved = 0;
    for (final p in pairs) {
      try {
        final from = File(p.drop.path);
        final dest = File('${from.parent.path}$sep$dupeFolder$sep${from.uri.pathSegments.last}');
        if (await dest.exists()) continue; // already a copy parked there — leave this one alone
        await dest.parent.create(recursive: true);
        final at = await moveWithRetry(from, dest);
        _reKeyCorrection(p.drop.path, at);
        _tagUndo.remove(p.drop.path); // its undo target is gone from the library
        moved++;
      } catch (_) {/* in use or across volumes — the pair is simply reported again next time */}
    }
    if (moved > 0) {
      await _saveTagUndo();
      await saveCorrectionsNow();
      await scan();
    }
    return moved;
  }

  /// How many files of this record could be put back as they were.
  int undoableTagWrites(Album album) =>
      recordTracks(album).where((t) => _tagUndo.containsKey(t.path)).length;

  /// Put this record's tags back to the values they had before the last rewrite.
  ///
  /// Restores through the same writer, so a field recorded as absent is DELETED again rather than
  /// left standing with our value — [writeFlacFields] already treats null that way. A file the
  /// player holds open fails here for the same reason it fails on the way out, and is named.
  Future<({int restored, List<String> failed})> undoTagWrites(Album album) async {
    var restored = 0;
    final failed = <String>[];
    for (final t in recordTracks(album)) {
      final before = _tagUndo[t.path];
      if (before == null) continue;
      String? reden;
      if (!await writeTagFields(File(t.path), before, waarom: (w) => reden = w)) {
        final naam = File(t.path).uri.pathSegments.last;
        failed.add(reden == null ? naam : '$naam — $reden');
        continue;
      }
      _tagUndo.remove(t.path);
      restored++;
      // DE CORRECTIE MOET MEE TERUG, anders klopt het scherm niet meer met het bestand.
      //
      // Gemeten meteen na het uitleveren van het potlood-schrijven: het bestand ging netjes terug naar
      // ALBUM=Hafla, maar de app bleef "Hafla (Live)" tonen — want die naam stond óók nog in
      // corrections.json, en die wint bij het inlezen. Dan lopen bestand en scherm weer uiteen, en dat
      // is precies de klacht waarvoor dit alles gebouwd is.
      //
      // Alleen de velden die dit terugzetten daadwerkelijk raakte. Een vastgezette persing, een
      // gekozen hoes of een gecorrigeerde artiest die hier niet in zat blijft van de gebruiker.
      final c = _corrections[t.path];
      if (c != null) {
        for (final veld in before.keys) {
          c.remove(const {'ARTIST': 'artist', 'ALBUM': 'album', 'TITLE': 'title'}[veld] ?? veld);
        }
        if (c.isEmpty) _corrections.remove(t.path);
      }
    }
    if (restored > 0) {
      await _saveTagUndo();
      await saveCorrectionsNow();
      await scan();
    }
    return (restored: restored, failed: failed);
  }
}

extension LibraryRenumber on LibraryStore {
  /// What taking [official] as this record's numbering would do. Nothing is written.
  ///
  /// Matched on TITLE and running time, never on the existing number — that number is the broken
  /// input. An album whose tags say 1, 1, 2, ?, 4, 6, 6, 7 … cannot be lined up positionally
  /// either, so the title is the only thing both sides can be trusted to agree on.
  RenumberPlan planRenumber(Album album, List<ChoiceTrack> official) {
    // A pool, so one official entry cannot claim two of our files: whichever matches it best takes
    // it and the other is reported as unmatched rather than silently duplicating a number.
    final pool = [...official];
    final steps = <RenumberStep>[];
    for (final t in album.tracks) {
      // The same matcher the album download uses — see matchOfficial in organize.dart. Two answers
      // to "is this the same song?" would be one too many.
      final best = matchOfficial(pool, t.title, t.duration?.inSeconds ?? 0);
      if (best == null) {
        steps.add(RenumberStep(t, null, null));
        continue;
      }
      pool.remove(best);
      steps.add(RenumberStep(t, best, trackNoFromPosition(best.position, best.disc, official)));
    }
    return RenumberPlan(steps, official.length);
  }

  /// Write a plan. The user's edit wins over the tags from here on, and outlives a rescan.
  Future<void> applyRenumber(RenumberPlan plan) async {
    // Op een client doet de PC het werk, net als bij een correctie.
    //
    // **Dit ontbrak volledig.** Het schreef `corrections.json` op het toestel zelf — maar op een
    // client komt de bibliotheek uit de catalogus van de pc, en die correcties worden daar nooit
    // gelezen. De nummering veranderde dus even op het scherm en was bij de eerstvolgende
    // synchronisatie weer weg. "Mijn nummering wil er ook niet bij komen."
    if (isRemote) {
      final stappen = <Map<String, dynamic>>[];
      for (final s in plan.steps) {
        final no = s.newNo;
        final id = remoteTrackId(s.track.path);
        if (no == null || id == null) continue;
        stappen.add({'trackId': id, 'no': no, 'title': s.nieuweTitel});
      }
      if (stappen.isEmpty) return;
      return _editOnPc({'op': 'renumber', 'total': plan.total, 'steps': stappen});
    }
    await hernummer(
      [
        for (final s in plan.steps)
          if (s.newNo != null) (path: s.track.path, no: s.newNo!, title: s.nieuweTitel)
      ],
      plan.total,
    );
  }

  /// De nummering van losse nummers vastleggen — de vorm die ook over de lijn past.
  ///
  /// Apart van [applyRenumber] omdat de pc dit namens een ander toestel moet kunnen doen, en die
  /// heeft geen `RenumberPlan` maar een lijst met paden en nummers.
  Future<void> hernummer(
      List<({String path, int no, String? title})> stappen, int total) async {
    for (final s in stappen) {
      final c = _correctionsFor(s.path);
      c['trackNo'] = '${s.no}';
      if (total > 0) c['trackTotal'] = '$total';
      final title = s.title;
      if (title != null && title.trim().isNotEmpty) c['title'] = title.trim();
    }
    await saveCorrectionsNow();
    refreshFromCorrections();
  }
}

extension LibraryMove on LibraryStore {
  /// What moving [tracks] into [target] would do on disk. Nothing is touched.
  ///
  /// Shown before the move because this is the one operation here that rewrites the folder tree,
  /// and a wrong guess scatters a library rather than tidying it.
  /// What moving these tracks would do — the version a screen can await.
  ///
  /// On the machine with the files this is [planMove] with a Future round it. On a Mac or an iPad
  /// the PC works it out, because nothing here knows the folders, which copy is better, or that a
  /// name is already taken. Either way the dialog gets a real answer before anyone agrees to
  /// anything, which is what that dialog is for.
  Future<({String? folder, List<MovePlan> items})> planMoveAsync(
      List<Track> tracks, Album target) async {
    final client = _remote;
    if (client == null) {
      return (
        folder: target.tracks.isEmpty ? null : File(target.tracks.first.path).parent.path,
        items: planMove(tracks, target),
      );
    }
    final byId = {for (final t in tracks) _remoteTrackId(t.path): t};
    final res = await client.ask('/api/move/plan', {
      'albumId': remoteAlbumId(target),
      'trackIds': [for (final t in tracks) _remoteTrackId(t.path)],
    });
    final items = <MovePlan>[];
    for (final item in (res['items'] as List? ?? const [])) {
      if (item is! Map<String, dynamic>) continue;
      final track = byId[item['trackId'] as String?];
      if (track == null) continue;
      items.add(MovePlan(
        track,
        // The PC's real path, which is what the dialog should show — a stream URL would tell
        // nobody where the file is now.
        (item['from'] as String?) ?? track.path,
        item['to'] as String?,
        MoveFate.values.firstWhere((f) => f.name == item['fate'], orElse: () => MoveFate.moves),
      ));
    }
    return (folder: res['folder'] as String?, items: items);
  }

  List<MovePlan> planMove(List<Track> tracks, Album target) {
    final anchor = target.tracks.isEmpty ? null : File(target.tracks.first.path).parent.path;
    return anchor == null
        ? [for (final t in tracks) MovePlan(t, t.path, null, MoveFate.stays)]
        : _gather(tracks, anchor).items;
  }

  /// Every track of this RECORD, across editions — which is what a merge is about.
  ///
  /// An Album is one edition; the tile beside it is another. Planning from `album.tracks` alone
  /// would gather one half of a split record and leave the other exactly where it was.
  List<Track> recordTracks(Album album) {
    if (album.isSingle || album.tracks.isEmpty) return album.tracks;
    final t = album.tracks.first;
    return editionsOfRecord('album::${artistKey(t.artist)}|${normKey(t.album)}') ?? album.tracks;
  }

  /// Where the files of [album] would go if it were gathered into one folder. Nothing is touched.
  MergePlan planMerge(Album album) {
    final ts = recordTracks(album);
    final folder = _homeFolder(ts, album.title);
    if (folder == null) {
      return MergePlan(null, [for (final t in ts) MovePlan(t, t.path, null, MoveFate.stays)]);
    }
    return _gather(ts, folder);
  }

  /// The folder this record already mostly lives in.
  ///
  /// Whichever holds the most of its tracks: that is the least traffic, and for a record split by
  /// an edition it is the original rip rather than the one file Soulseek dropped somewhere else.
  /// A tie goes to the folder whose name reads most like the album's — so a merge lands in
  /// "Black & Blue" and not in whatever the downloader happened to call it.
  String? _homeFolder(List<Track> tracks, String title) {
    if (tracks.isEmpty) return null;
    final n = <String, int>{};
    for (final t in tracks) {
      n.update(File(t.path).parent.path, (v) => v + 1, ifAbsent: () => 1);
    }
    final want = normKey(title);
    final ranked = n.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        final an = normKey(a.key.split(Platform.pathSeparator).last);
        final bn = normKey(b.key.split(Platform.pathSeparator).last);
        final match = (bn == want ? 1 : 0) - (an == want ? 1 : 0);
        return match != 0 ? match : a.key.compareTo(b.key);
      });
    return ranked.first.key;
  }

  /// Work out, without touching anything, where each of [tracks] would land in [folder].
  MergePlan _gather(List<Track> tracks, String folder) {
    final sep = Platform.pathSeparator;
    // Names already spoken for in the target folder, and by which file. Seeded from the tracks that
    // are already there so two arrivals can't both claim one name.
    final taken = <String, String>{};
    for (final t in tracks) {
      final f = File(t.path);
      if (f.parent.path == folder) taken[f.uri.pathSegments.last.toLowerCase()] = t.path;
    }
    try {
      for (final e in Directory(folder).listSync(followLinks: false)) {
        if (e is File) taken.putIfAbsent(e.uri.pathSegments.last.toLowerCase(), () => e.path);
      }
    } catch (_) {/* folder unreadable — treat it as empty and let the move itself fail loudly */}

    final items = <MovePlan>[];
    // Tracks already dealt with because a better copy took their name. Without this a tenant bumped
    // before the loop reached it would be planned TWICE — once into _dubbel and once as staying —
    // and a plan that lists a file twice is a plan nobody can check.
    final bumped = <String>{};
    for (final t in tracks) {
      if (bumped.contains(t.path)) continue;
      final src = File(t.path);
      final name = src.uri.pathSegments.last;
      if (src.parent.path == folder) {
        items.add(MovePlan(t, t.path, null, MoveFate.stays));
        continue;
      }
      final holder = taken[name.toLowerCase()];
      if (holder == null) {
        taken[name.toLowerCase()] = t.path;
        items.add(MovePlan(t, t.path, '$folder$sep$name', MoveFate.moves));
        continue;
      }
      // The name is taken. Whichever copy is worse goes to the duplicates folder — same rule the
      // tracklist already uses to decide which of two copies you actually hear.
      // Only OUR tracks can be bumped; a stranger's file in the folder is left alone and we step aside.
      final tenant = tracks.where((x) => x.path == holder).firstOrNull;
      if (tenant != null && firstIsBetter(src, File(holder))) {
        final at = items.indexWhere((i) => i.track.path == holder);
        final aside = MovePlan(tenant, holder, '$folder$sep$dupeFolder$sep$name', MoveFate.toDupes);
        at >= 0 ? items[at] = aside : items.add(aside);
        bumped.add(holder);
        taken[name.toLowerCase()] = t.path;
        items.add(MovePlan(t, t.path, '$folder$sep$name', MoveFate.moves));
        continue;
      }
      items.add(MovePlan(t, t.path, '$folder$sep$dupeFolder$sep$name', MoveFate.toDupes));
    }
    return MergePlan(folder, items);
  }

  /// Carry out a plan. Returns, per source path, where that file actually ended up.
  ///
  /// Only files that really moved are in the map. Guessing afterwards from `File(to).exists()`
  /// would be wrong in the one case that matters: a destination that was already occupied is
  /// skipped, and the track's own file is then still at its old path — keying its correction to the
  /// stranger's path would leave the track ungrouped.
  ///
  /// Never overwrites. The correction naming this track's album is re-keyed to where the file
  /// landed — see [LibraryStore._reKeyCorrection] for what forgetting that used to cost.
  Future<Map<String, String>> _apply(List<MovePlan> plan) async {
    final landed = <String, String>{};
    final vacated = <String>{};
    for (final p in plan) {
      if (!p.movesFile) continue;
      try {
        final dest = File(p.to!);
        if (await dest.exists()) continue;
        await dest.parent.create(recursive: true);
        final from = File(p.from).parent.path;
        final at = await moveWithRetry(File(p.from), dest);
        _reKeyCorrection(p.from, at);
        landed[p.from] = at;
        vacated.add(from);
      } catch (_) {/* locked, or across volumes — the file stays put and stays in the library */}
    }
    // Gathering an album empties the folders it was scattered over. Those are exactly the leftovers
    // the user was deleting by hand.
    for (final d in vacated) {
      await pruneVacated(d, rootPath);
    }
    return landed;
  }

  /// Move [tracks] into [target]: retag them into that album, and optionally carry the files along.
  ///
  /// The correction is what actually regroups them, so it is applied whether or not the file can
  /// be moved. A file that can't be moved — locked, or a name already taken — leaves the track
  /// grouped correctly and the file where it was, which is the safe half of the job.
  Future<int> moveTracksToAlbum(List<Track> tracks, Album target, AppSettings settings,
      {bool moveFiles = true, List<MovePlan>? plan}) async {
    if (isRemote) {
      final client = _remote!;
      final res = await client.ask('/api/move/apply', {
        'albumId': remoteAlbumId(target),
        'trackIds': [for (final t in tracks) _remoteTrackId(t.path)],
        'moveFiles': moveFiles,
        // The plan the user READ goes back with it. Letting the PC work it out again would let the
        // folder change between the screen they agreed to and the files that move.
        if (plan != null)
          'plan': [
            for (final p in plan)
              {'trackId': _remoteTrackId(p.track.path), 'to': p.to, 'fate': p.fate.name},
          ],
      });
      _catalogEtag = null;
      await loadRemote(quiet: true);
      return (res['moved'] as num?)?.toInt() ?? 0;
    }
    // The plan the user read, when there was one. Re-planning here would let the folder change
    // between the screen they approved and the files that move.
    final steps = plan ?? planMove(tracks, target);
    final landed = moveFiles ? await _apply(steps) : const <String, String>{};
    for (final p in steps) {
      final c = _correctionsFor(landed[p.from] ?? p.from);
      c['artist'] = cleanArtistName(target.artist);
      c['album'] = target.title;
    }
    await saveCorrectionsNow();
    await scan();
    return landed.length;
  }

  /// Gather every edition of [album] into one folder, carrying out [planMerge].
  ///
  /// The tags already say these are one record — that is why they show as one album — so nothing is
  /// retagged here. Only the files move.
  Future<int> gatherAlbumFiles(Album album, {List<MovePlan>? plan}) async {
    final landed = await _apply(plan ?? planMerge(album).items);
    if (landed.isNotEmpty) {
      await saveCorrectionsNow();
      await scan();
    }
    return landed.length;
  }
}

/// One track of a redundant album, matched to the copy already owned in the real album.
class DuplicatePair {
  /// The redundant copy.
  final Track dup;

  /// The copy already in the proper studio album that [dup] duplicates.
  final Track owned;

  /// True when [dup] is the better copy and should take [owned]'s place.
  final bool dupWins;
  const DuplicatePair(this.dup, this.owned, this.dupWins);
}

/// An album or single whose every track is already owned in a fuller studio album.
class RedundantAlbum {
  /// The junk single or fragment album.
  final Album source;

  /// The real album it all duplicates.
  final Album target;
  final List<DuplicatePair> pairs;
  const RedundantAlbum(this.source, this.target, this.pairs);

  /// How many of the redundant copies are actually better and will replace what's owned.
  int get upgrades => pairs.where((p) => p.dupWins).length;
}

/// The placeholder artist a file gets when its tags can't be read — see `_scanTags`.
final String _unknownArtistKey = artistKey('Onbekende artiest');

/// An album title that names a DISTINCT performance or version of a record, not the record itself.
///
/// A live "Gourmandises" is a different recording from the studio one, but the peer often tags the
/// track just "Gourmandises" with no marker — only the album name ("Alizée en concert") says it is
/// live. Folding it into the studio album on the strength of the title would quietly lose the live
/// take. A live album, like a greatest-hits, is a release the user keeps, so it is never a source
/// to clean away.
final RegExp _distinctPerformanceRe = RegExp(
    r'\b(live|concert|unplugged|acoustic|session|sessions|demo|demos|remix|remixes|'
    r'instrumental|karaoke|a ?cappella|acapella|orchestral|symphon)\b');

extension LibraryDuplicates on LibraryStore {
  /// Albums and singles that are entirely duplicates of a real album you already own.
  ///
  /// The two shapes this catches, both stale cruft from before downloads carried their album's
  /// identity: a fragment tagged like its own album ("Backstreet Boys (Special Edition)" holding
  /// only 9, 10, 13), and a junk single whose tags were unreadable so it filed itself under
  /// "Onbekende artiest" with the raw filename as its title.
  ///
  /// The safety is the ALL-of-it rule: a source is only redundant when EVERY one of its tracks is
  /// already in ONE proper studio album. A real greatest-hits spans several studio albums, so it
  /// can never be wholly contained in one and is never touched — which is what keeps a compilation
  /// you actually wanted from being swept away.
  /// Hetzelfde als [redundantAlbums], maar het rekenwerk gebeurt op een andere isolate.
  ///
  /// **Waarom.** [redundantAlbums] draait bij elke scan en doet per kandidaatpaar bestands-I/O:
  /// `firstIsBetter` leest de FLAC-kop van beide bestanden en hun grootte. Dat stond op de tekendraad,
  /// dus terwijl het liep tekende de app niet. Gemeten is het hier 50 ms — geen pijn vandaag, maar het
  /// schaalt met het aantal kandidaatparen en niet met je bibliotheek.
  ///
  /// **Wat er heen moet.** Alleen platte gegevens: albums en nummers als velden, plus de twee
  /// verzamelingen die [firstIsBetter] uit het geheugen leest — wat de gebruiker zelf koos en wat
  /// bewezen nep is. Zonder die twee zou de isolate ze als leeg lezen en stilzwijgend andere winnaars
  /// kiezen; zie [Voorkennis].
  ///
  /// **Wat er terug komt zijn INDICES**, geen objecten. De UI hangt aan de echte [Album]- en
  /// [Track]-instanties uit deze winkel — `consolidate` verplaatst hun bestanden en `identical(x, y)`
  /// moet blijven kloppen. Kopieën die er hetzelfde uitzien zouden dat allebei breken.
  Future<List<RedundantAlbum>> redundantAlbumsAsync() async {
    if (albums.isEmpty) return const [];
    final plat = <_PlatAlbum>[
      for (final a in albums)
        (
          isSingle: a.isSingle,
          title: a.title,
          artist: a.artist,
          tracks: [
            for (final t in a.tracks)
              (
                title: t.title,
                artist: t.artist,
                path: t.path,
                durationSec: t.duration?.inSeconds,
              ),
          ],
        ),
    ];
    final kennis = (vast: vasteKeuzeSleutels(), nep: nepSleutels());

    final aantalBij = albums.length;
    List<_PlatTreffer> gevonden;
    try {
      gevonden = await Isolate.run(() => _zoekDubbels(plat, kennis));
    } catch (e) {
      meetlog?.call('  scan/dubbels: isolate mislukt ($e) — terug naar de hoofddraad');
      return redundantAlbums();
    }
    // De bibliotheek mag onder de berekening niet veranderd zijn: de indices verwijzen naar de lijst
    // zoals hij was. Dit gebeurt echt — `_adoptSidecars` en een herscan na een download draaien er
    // omheen — en zonder deze controle zou een index naar een ANDER album wijzen.
    if (albums.length != aantalBij) {
      meetlog?.call('  scan/dubbels: bibliotheek veranderde tijdens de berekening — overgeslagen');
      return const [];
    }

    // Indices terug naar de echte objecten. Buiten bereik betekent dat de bibliotheek onder de
    // berekening is veranderd — dan is dit antwoord verouderd en gooien we het weg.
    final uit = <RedundantAlbum>[];
    for (final g in gevonden) {
      if (g.bron >= albums.length || g.doel >= albums.length) return const [];
      final x = albums[g.bron], y = albums[g.doel];
      final paren = <DuplicatePair>[];
      for (final p in g.paren) {
        if (p.bronTrack >= x.tracks.length || p.doelTrack >= y.tracks.length) return const [];
        paren.add(DuplicatePair(x.tracks[p.bronTrack], y.tracks[p.doelTrack], p.dupWint));
      }
      if (paren.isNotEmpty) uit.add(RedundantAlbum(x, y, paren));
    }
    return uit;
  }

  List<RedundantAlbum> redundantAlbums() {
    // The real records a duplicate can fold back into: studio albums (not compilations, not
    // singles), with more than a token of tracks.
    final targets = [
      for (final a in albums)
        if (!a.isSingle &&
            a.tracks.length >= 2 &&
            classifyRelease(album: a.title, artist: a.artist) == RelKind.album)
          a
    ];
    if (targets.isEmpty) return const [];

    // Match one redundant track to a copy in [target]. Null when nothing in the target is it.
    //
    // A fragment carries real tags, so its TITLE is the strongest signal — stronger than the
    // filename, which the peer may have written as "09 - Every Time.flac". A junk single has no
    // usable title (its title IS the raw filename), so for that the filename against the target's
    // title is all there is, and fileOffersTitle reads the artist words in it correctly.
    Track? ownedIn(Album target, Track x, {required bool junk}) {
      final xDur = x.duration?.inSeconds ?? 0;
      if (!junk && normKey(x.title).isNotEmpty) {
        for (final y in target.tracks) {
          if (normKey(x.title) != normKey(y.title)) continue;
          final yDur = y.duration?.inSeconds ?? 0;
          // A different VERSION of the same song runs a different length; a couple of seconds is
          // just a different rip, so it is the same recording.
          if (xDur == 0 || yDur == 0 || (xDur - yDur).abs() <= 12) return y;
        }
      }
      for (final y in target.tracks) {
        if (fileOffersTitle(y.title, y.duration?.inSeconds, y.artist, x.path, xDur)) return y;
      }
      return null;
    }

    final out = <RedundantAlbum>[];
    for (final x in albums) {
      // Never fold away a release the user keeps on purpose: a real compilation, or a distinct
      // performance (a live album, a remix set, an unplugged session) whose tracks only look like
      // the studio ones because the marker sits in the album name, not the track title.
      if (!x.isSingle &&
          (classifyRelease(album: x.title, artist: x.artist) == RelKind.compilation ||
              _distinctPerformanceRe.hasMatch(normKey(x.title)))) {
        continue;
      }
      // A single whose artist never got read — the WAV filed under "Onbekende artiest". Its tags
      // are useless, so it is matched by filename against any album; anything with a real artist is
      // matched the cheap way, only against albums by that same artist.
      final junk = x.isSingle && (x.artist.trim().isEmpty || artistKey(x.artist) == _unknownArtistKey);

      Album? best;
      List<DuplicatePair>? bestPairs;
      for (final y in targets) {
        if (identical(x, y)) continue;
        // The target has to be at least as big — the fragment folds into the fuller record, never
        // the other way round. A single (one track) folds into any album that has it.
        if (y.tracks.length < x.tracks.length) continue;
        if (!junk && artistKey(x.artist) != artistKey(y.artist)) continue;

        final pairs = <DuplicatePair>[];
        var whole = true;
        for (final t in x.tracks) {
          final owned = ownedIn(y, t, junk: junk);
          if (owned == null) {
            whole = false;
            break;
          }
          pairs.add(DuplicatePair(t, owned, firstIsBetter(File(t.path), File(owned.path))));
        }
        if (!whole) continue;
        // Prefer the fullest target when several qualify, so a fragment lands in the real album.
        if (best == null || y.tracks.length > best.tracks.length) {
          best = y;
          bestPairs = pairs;
        }
      }
      if (best != null && bestPairs != null && bestPairs.isNotEmpty) {
        out.add(RedundantAlbum(x, best, bestPairs));
      }
    }
    return out;
  }

  /// Carry out a cleanup: keep the best copy of each track in [r.target], park the rest in _dubbel.
  ///
  /// The better copy wins even when it is the one in the fragment — here the Special Edition rips
  /// are the higher bitrate. A winning copy from the fragment moves into the target folder under
  /// its proper name and is retagged to the target's identity; the copy it beats goes to _dubbel.
  Future<void> consolidate(RedundantAlbum r) async {
    final sep = Platform.pathSeparator;
    final targetDir = r.target.tracks.isEmpty ? null : File(r.target.tracks.first.path).parent.path;
    if (targetDir == null) return;
    final dubbel = '$targetDir$sep$dupeFolder';

    Future<void> park(String from) async {
      try {
        final dest = File('$dubbel$sep${File(from).uri.pathSegments.last}');
        if (await dest.exists()) return; // already a copy there — leave this one where it is
        await dest.parent.create(recursive: true);
        final was = File(from).parent.path;
        final at = await moveWithRetry(File(from), dest);
        _reKeyCorrection(from, at);
        await pruneVacated(was, rootPath);
      } catch (_) {/* locked or across volumes — the scan still sorts it out */}
    }

    for (final p in r.pairs) {
      if (!p.dupWins) {
        // The owned copy is as good or better — the duplicate simply goes away.
        await park(p.dup.path);
        continue;
      }
      // The duplicate is better: it takes the owned copy's slot. Park the owned copy first, then
      // move the winner onto its proper name and stamp it with the record's identity.
      await park(p.owned.path);
      final ext = () {
        final n = File(p.dup.path).uri.pathSegments.last;
        final i = n.lastIndexOf('.');
        return i < 0 ? '' : n.substring(i);
      }();
      final name = safeSeg('${p.owned.trackNo.toString().padLeft(2, '0')} - ${p.owned.title}$ext');
      final to = '$targetDir$sep$name';
      try {
        if (!await File(to).exists()) {
          final at = await moveWithRetry(File(p.dup.path), File(to));
          _reKeyCorrection(p.dup.path, at);
          await stampTags(
              File(at),
              TrackTags(
                title: p.owned.title,
                artist: r.target.artist,
                album: r.target.title,
                albumArtist: r.target.artist,
                trackNo: p.owned.trackNo,
                trackTotal: r.target.tracks.length,
                year: p.owned.year ?? r.target.year,
              ));
        }
      } catch (_) {/* couldn't move — leave both; the next scan still shows one via dedup */}
    }

    await saveCorrectionsNow();
    // The source folder is empty now. pruneVacated also takes the artist folder above it when that
    // record was the only one there, and sweeps a Thumbs.db that would otherwise keep an empty
    // folder standing — the old check here required a literally bare folder and stopped at one level.
    final srcDir = r.source.tracks.isEmpty ? null : File(r.source.tracks.first.path).parent.path;
    if (srcDir != null && srcDir != targetDir) await pruneVacated(srcDir, rootPath);
    await scan();
  }
}

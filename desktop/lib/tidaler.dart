/// Muziek van TIDAL halen met `tidaler` (github.com/maya-doshi/tidaler).
///
/// **Waarom tidaler en niet meer tiddl.** Gemeten op 22-10-2026: tiddl kreeg van TIDAL 16 bit / 44,1 kHz, ook als je
/// om de hoogste kwaliteit vroeg — hij logt in met een apparaatcode, en daarmee geeft TIDAL niet meer dan LOSSLESS.
/// tidaler logt in zoals de Android-app (PKCE) en krijgt wél HI_RES_LOSSLESS: Tamino — Indigo Night en Daft Punk —
/// Get Lucky kwamen binnen als FLAC 24 bit / 44,1 kHz, alle 24 bits echt gebruikt, md5 in orde, en de echtheidsmeter
/// zei "consistent". Saber: *"ok tidaler als primair tiddl mag weg e"*. TIDAL blijft de reserve achter Soulseek.
///
/// **Waarom dit klein is en klein hoort te blijven.** tidaler is een programma in Python dat jij op de pc installeert
/// (`uv tool install --python 3.13 tidaler`) en waarmee je één keer zelf inlogt (`tidaler login`, in de browser). De
/// app roept het aan zoals ffmpeg en fpcalc: geen wachtrij, geen eigen scherm. Het bestand landt in een keuringsmap
/// en de keuring beslist of het de bibliotheek in mag.
///
/// **Zoeken.** tidaler heeft geen zoekopdracht. Daarom draait de app een klein hulpje ([kTidalZoekHulp]) in
/// tidalers eigen Python, dat zijn inlog gebruikt en de treffers als JSON teruggeeft — met de volle titel (versie
/// erbij), de eerste artiest en of het een stereonummer is.
///
/// Alleen op de machine die de muziek bezit. Een telefoon heeft geen Python, geen tidaler, en geen muziekmap.
///
/// **Niet te verwarren met `tidal.dart` ernaast.** Dat is `TidalService`: de officiële Tidal-API, die alleen de
/// catalogus doorzoekt om er een zoekvraag voor Soulseek of een torrent van te maken. Dit bestand haalt de muziek
/// wél op, via jouw eigen abonnement.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'uitvoerbaar.dart';

import 'enrichment.dart' show zonderGastTitel;
import 'ffmpeg.dart';
import 'tidal.dart' show TidalAlbum, TidalTrack, TidalZoekResultaat;
import 'organize.dart' show artistKey, normKey;

/// Waar tidaler kan staan, in volgorde van waarschijnlijkheid.
///
/// Anders dan bij ffmpeg en fpcalc levert de bouwstraat dit NIET mee. PATH staat vooraan: daar zetten
/// `uv tool install` en `pip install` hem allebei neer. De rest zijn de plekken waar ze hem laten staan als PATH niet
/// is bijgewerkt, wat na een verse installatie op Windows het gewone geval is.
List<String> tidalerKandidaten({required String os, String? thuis}) {
  final huis = thuis ?? '';
  if (os == 'windows') {
    return [
      'tidaler.exe',
      if (huis.isNotEmpty) ...[
        '$huis\\.local\\bin\\tidaler.exe', // uv
        '$huis\\AppData\\Roaming\\Python\\Scripts\\tidaler.exe', // pip --user
      ],
    ];
  }
  return [
    'tidaler',
    if (huis.isNotEmpty) '$huis/.local/bin/tidaler', // uv en pip --user
    '/opt/homebrew/bin/tidaler',
    '/usr/local/bin/tidaler',
  ];
}

/// Waar de Python van tidaler staat — nodig voor het zoekhulpje ([kTidalZoekHulp]), dat tidalers eigen inlog en
/// tidalapi gebruikt. uv zet elk gereedschap in een eigen omgeving onder zijn toolmap (`UV_TOOL_DIR`, anders
/// `%APPDATA%\uv\tools` op Windows en `~/.local/share/uv/tools` elders); pipx onder `~/.local/pipx/venvs`.
List<String> tidalerPythonKandidaten({required String os, String? thuis, String? appData, String? uvToolDir}) {
  final huis = thuis ?? '';
  final win = os == 'windows';
  String py(String venv) => win ? '$venv\\Scripts\\python.exe' : '$venv/bin/python';
  final s = win ? '\\' : '/';
  return [
    if (uvToolDir != null && uvToolDir.isNotEmpty) py('$uvToolDir${s}tidaler'),
    if (win && appData != null && appData.isNotEmpty) py('$appData\\uv\\tools\\tidaler'),
    if (!win && huis.isNotEmpty) py('$huis/.local/share/uv/tools/tidaler'),
    if (huis.isNotEmpty) py(win ? '$huis\\pipx\\venvs\\tidaler' : '$huis/.local/pipx/venvs/tidaler'),
  ];
}

/// Het programma zelf: één keer zoeken, daarna onthouden.
///
/// Dezelfde vorm als [Fingerprinter] in `fingerprint.dart`, en om dezelfde reden: bij een misser hoort er te staan
/// wáár er gekeken is.
class Tidaler {
  static String? _gevonden, _python;
  static bool _gekeken = false, _pythonGekeken = false;

  /// Waar er gekeken is toen hij niet gevonden werd.
  static String? laatsteFout;

  static String? get pad {
    if (_gekeken) return _gevonden;
    _gekeken = true;
    final geprobeerd = <String>[];
    for (final k in tidalerKandidaten(
        os: Platform.operatingSystem,
        thuis: Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'])) {
      try {
        if (k.contains(Platform.pathSeparator)) {
          if (File(k).existsSync()) return _gevonden = k;
        } else {
          // Kale naam: eerst zelf in PATH zoeken. Een `runSync` op iets wat er niet is kost op macOS de hele app een
          // SIGPIPE — zie uitvoerbaar.dart. Bestaat hij, dan is dat genoeg: `--help` starten kost een tel Python.
          final echt = uitvoerbaarPad(k);
          if (echt != null) return _gevonden = echt;
        }
      } catch (_) {/* niet daar; volgende */}
      geprobeerd.add(k);
    }
    laatsteFout = 'tidaler niet gevonden; geprobeerd: ${geprobeerd.join(", ")}';
    return _gevonden = null;
  }

  /// De Python van tidaler, voor het zoekhulpje. Null: zoeken op TIDAL kan dan niet (halen met een link wel).
  static String? get python {
    if (_pythonGekeken) return _python;
    _pythonGekeken = true;
    final env = Platform.environment;
    for (final k in tidalerPythonKandidaten(
        os: Platform.operatingSystem,
        thuis: env['HOME'] ?? env['USERPROFILE'],
        appData: env['APPDATA'],
        uvToolDir: env['UV_TOOL_DIR'])) {
      try {
        if (File(k).existsSync()) return _python = k;
      } catch (_) {/* volgende */}
    }
    return _python = null;
  }

  static bool get beschikbaar => pad != null;

  /// Draaien we in een toets? Dan nooit echt naar TIDAL — op Sabers pc staat tidaler echt, en een toets die een
  /// Soulseek-storing nabootst zou anders bij TIDAL gaan halen (`flutter test` zet `FLUTTER_TEST`).
  static bool get inToets => Platform.environment['FLUTTER_TEST'] == 'true';

  /// Voor de toetsen, en voor nadat iemand tidaler geïnstalleerd heeft zonder de app te herstarten.
  static void resetLookup() {
    _gekeken = false;
    _gevonden = null;
    _pythonGekeken = false;
    _python = null;
    laatsteFout = null;
  }
}

/// Wat je geplakt hebt, omgezet naar `soort/id`. Null als het onbruikbaar is.
///
/// **Waarom dit hier gebeurt.** Een link uit de Tidal-app draagt van alles mee — `?u`, een land, een verwijzer — en er
/// zijn twee adressen in omloop (`tidal.com/browse/...` en `listen.tidal.com/...`). Dat hier opruimen kost drie regels;
/// het aan tidaler overlaten kost een mislukte download met een foutmelding waar niemand iets aan heeft.
///
/// En het weigert wat niet klopt vóórdat er een proces gestart wordt. Een lege regel of een Spotify-link hoort een zin
/// op te leveren, geen rood scherm uit Python.
String? tidalDoel(String invoer) {
  var s = invoer.trim();
  if (s.isEmpty) return null;
  // Alles vanaf het vraagteken is meelifterij van de deelknop.
  final vraag = s.indexOf('?');
  if (vraag > 0) s = s.substring(0, vraag);
  s = s.replaceAll(RegExp(r'/+$'), '');

  const soorten = ['track', 'album', 'artist', 'playlist', 'mix', 'video'];
  // De korte vorm: `album/103805723`.
  final kort = RegExp('^(${soorten.join("|")})/([A-Za-z0-9-]+)\$').firstMatch(s);
  if (kort != null) return s;

  final uri = Uri.tryParse(s);
  if (uri == null || !uri.hasScheme) return null;
  final gastheer = uri.host.toLowerCase();
  if (gastheer != 'tidal.com' && gastheer != 'www.tidal.com' && gastheer != 'listen.tidal.com') {
    return null;
  }
  // `/browse/album/123` en `/album/123` leiden allebei naar dezelfde plaat.
  final delen = uri.pathSegments.where((d) => d.isNotEmpty && d != 'browse').toList();
  if (delen.length < 2) return null;
  if (!soorten.contains(delen[0])) return null;
  return '${delen[0]}/${delen[1]}';
}

/// Een id uit de TIDAL-API omgezet naar een doel. Null als het onbruikbaar is.
///
/// Bewust via [tidalDoel] en niet met een eigen `'$soort/$id'`: die functie kent de zes soorten al en weigert alles
/// wat er niet uitziet als een id.
String? tidalDoelVanId(String soort, String id) => tidalDoel('$soort/${id.trim()}');

/// Het adres dat tidaler aanneemt: alleen volle links (een kaal id weigert hij met "invalid URL").
String tidalerUrl(String doel) => 'https://tidal.com/browse/$doel';

/// De vier kwaliteiten in het venster, zoals ze daar heten.
///
/// `max` is 24 bit tot 192 kHz en is de enige reden om dit te bouwen. `low` en `normal` zijn m4a van 96 en 320 kbps —
/// slechter dan wat deze bibliotheek al heeft. Ze staan er omdat het abonnement ze kan afdwingen, niet omdat je ze wil.
const tidalKwaliteiten = ['max', 'high', 'normal', 'low'];

/// Hoe tidaler (tidalapi) een kwaliteit uit [tidalKwaliteiten] noemt.
String tidalerKwaliteit(String k) => switch (k) {
      'high' => 'LOSSLESS',
      'normal' => 'HIGH',
      'low' => 'LOW',
      _ => 'HI_RES_LOSSLESS',
    };

/// De instellingen die vóór elke download gezet worden (`tidaler cfg <naam> <waarde>`), in deze volgorde.
///
/// **Waarom via `cfg` en niet met vlaggen.** `tidaler dl` neemt geen map en geen kwaliteit mee; hij leest ze uit zijn
/// instellingenbestand. Daarom wordt dat vlak voor elke download gezet, één download tegelijk ([haalVanTidal]):
/// [map] wordt de downloadmap (een keuringsmap), `skip_existing` gaat uit (anders slaat hij over wat er eerder
/// stond en levert niets), en ffmpeg gaat mee — zonder ffmpeg haalt tidaler de FLAC niet uit TIDALs MP4-verpakking.
List<List<String>> tidalerInstellingen({required String map, required String kwaliteit, String? ffmpeg}) => [
      ['quality_audio', tidalerKwaliteit(kwaliteit)],
      ['download_base_path', map],
      ['skip_existing', 'False'],
      ['extract_flac', 'True'],
      if (ffmpeg != null && ffmpeg.isNotEmpty) ['path_binary_ffmpeg', ffmpeg],
    ];

/// De uitvoer van tidaler leesbaar maken.
///
/// Hij tekent zijn voortgang met Rich, dus wat er terugkomt staat vol stuurtekens en herhaalde regels. Voor een
/// foutmelding op het scherm wil je de laatste paar regels zonder die rommel.
String leesbareFout(String uitvoer, {int regels = 4}) {
  final schoon = uitvoer
      // ANSI-stuurtekens: kleuren en cursorsprongen.
      .replaceAll(RegExp(r'\x1B\[[0-9;?]*[A-Za-z]'), '')
      .replaceAll('\r', '\n');
  final over = [
    for (final r in schoon.split('\n'))
      if (r.trim().isNotEmpty) r.trim(),
  ];
  if (over.isEmpty) return 'tidaler zei niets.';
  return over.sublist(over.length > regels ? over.length - regels : 0).join('\n');
}

/// Het PATH waarmee tidaler gestart wordt, met de map van ffmpeg erbij.
///
/// tidaler krijgt ffmpeg ook via `path_binary_ffmpeg` ([tidalerInstellingen]); dit is het vangnet voor wie hem via
/// PATH zoekt (python-ffmpeg). Vindt de app ffmpeg zelf niet, dan verandert er niets.
String padMetFfmpeg(String? ffmpegPad, String huidigPad, {required bool windows}) {
  if (ffmpegPad == null || ffmpegPad.isEmpty) return huidigPad;
  final scheiding = windows ? '\\' : '/';
  final knip = ffmpegPad.lastIndexOf(scheiding);
  // Een kale naam ('ffmpeg.exe') betekent: gevonden via PATH. Dan staat hij er al.
  if (knip <= 0) return huidigPad;
  final map = ffmpegPad.substring(0, knip);
  final tussen = windows ? ';' : ':';
  if (huidigPad.isEmpty) return map;
  // Niet twee keer, anders groeit dit bij elke aanroep.
  final delen = huidigPad.split(tussen);
  if (delen.any((d) => d.toLowerCase() == map.toLowerCase())) return huidigPad;
  return '$map$tussen$huidigPad';
}

/// Zoals UTF-8, maar hij struikelt niet over een byte die er niet in hoort. Op Windows schrijft Python standaard in
/// de codetabel van de console; `PYTHONIOENCODING` zet dat recht, en dit is het vangnet daaronder.
const _soepelUtf8 = Utf8Codec(allowMalformed: true);

/// "24 bit / 44.1 kHz" uit de STREAMINFO van een FLAC-kop ([kop]: het begin van het bestand). Null: geen FLAC.
String? flacKwaliteit(Uint8List kop) {
  var i = 0;
  // Een ID3v2 ervoor (komt voor bij FLAC's van slordige taggers).
  if (kop.length >= 10 && kop[0] == 0x49 && kop[1] == 0x44 && kop[2] == 0x33) {
    i = 10 + ((kop[6] & 0x7f) << 21 | (kop[7] & 0x7f) << 14 | (kop[8] & 0x7f) << 7 | (kop[9] & 0x7f));
  }
  if (i + 8 + 18 > kop.length) return null;
  if (kop[i] != 0x66 || kop[i + 1] != 0x4C || kop[i + 2] != 0x61 || kop[i + 3] != 0x43) return null;
  if ((kop[i + 4] & 0x7f) != 0) return null; // het eerste blok hoort STREAMINFO te zijn
  final d = i + 8;
  final hz = (kop[d + 10] << 12) | (kop[d + 11] << 4) | (kop[d + 12] >> 4);
  final bits = (((kop[d + 12] & 0x01) << 4) | (kop[d + 13] >> 4)) + 1;
  if (hz <= 0) return null;
  final khz = hz % 1000 == 0 ? '${hz ~/ 1000}' : (hz / 1000).toStringAsFixed(1);
  return '$bits bit / $khz kHz';
}

/// De kwaliteit van wat er werkelijk binnenkwam in [map]: elke verschillende waarde één keer ("24 bit / 44.1 kHz",
/// of twee bij een verzamelaar met gemengde bronnen). Uit de bestanden zelf, niet uit wat tidaler zegt.
Future<String?> kwaliteitInMap(Directory map) async {
  final gevonden = <String>{};
  try {
    await for (final e in map.list(recursive: true, followLinks: false)) {
      if (e is! File || !e.path.toLowerCase().endsWith('.flac')) continue;
      final f = await e.open();
      try {
        final k = flacKwaliteit(await f.read(64 * 1024));
        if (k != null) gevonden.add(k);
      } finally {
        await f.close();
      }
    }
  } catch (_) {/* dan zeggen we niets */}
  return gevonden.isEmpty ? null : gevonden.join(' · ');
}

/// Wat er na een geslaagde download op het scherm komt — met de kwaliteit, want die ontdek je anders pas door naar
/// de bitdiepte van je bestand te kijken. [keuring] is wat de keuring besliste (zie `keuringMap` in paths.dart).
String opgehaaldMelding(String kwaliteit, {String? keuring}) {
  final basis = kwaliteit.isEmpty ? 'Opgehaald' : 'Opgehaald ($kwaliteit)';
  return keuring == null || keuring.isEmpty
      ? '$basis — de bibliotheek wordt opnieuw doorzocht'
      : '$basis en gekeurd: $keuring';
}

/// Hoeveel nummers de radio (en ▶) hoogstens per uur van TIDAL haalt, als Soulseek niet meedoet of het nummer niet
/// heeft. Een uur muziek is zo'n vijftien nummers: de radio houdt zo bij wat je hoort, zonder in een paar minuten
/// tientallen nummers te trekken — dat patroon geeft een geblokkeerd account ("abuse_detected").
const int kTidalRadioPerUur = 15;

/// Eén download tegelijk: tidaler leest zijn map uit één instellingenbestand ([tidalerInstellingen]).
Future<void> _beurt = Future.value();

/// Haal [doel] op naar [map]. [fout] is null als er iets binnenkwam, anders de uitleg; [kwaliteit] komt uit de
/// bestanden zelf ([kwaliteitInMap]).
///
/// **Gelukt is: er staat een bestand.** `tidaler dl` meldt een mislukking alleen als tekst en sluit toch af met 0
/// (gelezen in zijn `cli.py`, 0.1.8). Een groen vinkje boven een download die niet gebeurd is, is precies wat hier
/// niet mag. [zoekMap] bestaat nog voor de aanroepers; tidaler kijkt alleen in zijn eigen downloadmap, en
/// `skip_existing` staat uit.
Future<({String? fout, String? kwaliteit})> haalVanTidal({
  required String doel,
  required String map,
  String kwaliteit = 'max',
  String? zoekMap,
}) {
  final klaar = Completer<({String? fout, String? kwaliteit})>();
  final vorige = _beurt;
  _beurt = klaar.future.then((_) {}, onError: (_) {});
  vorige.whenComplete(() async {
    try {
      klaar.complete(await _haal(doel: doel, map: map, kwaliteit: kwaliteit));
    } catch (e) {
      klaar.complete((fout: 'Kon tidaler niet starten: $e', kwaliteit: null));
    }
  });
  return klaar.future;
}

Future<({String? fout, String? kwaliteit})> _haal({
  required String doel,
  required String map,
  required String kwaliteit,
}) async {
  final tool = Tidaler.pad;
  if (tool == null) {
    return (
      fout: 'tidaler staat niet op deze pc. Installeer hem met "uv tool install --python 3.13 tidaler", en log één '
          'keer zelf in met "tidaler login". ${Tidaler.laatsteFout ?? ""}',
      kwaliteit: null,
    );
  }
  if (map.trim().isEmpty) return (fout: 'Er is nog geen muziekmap ingesteld.', kwaliteit: null);
  final ffmpeg = Ffmpeg().pad;
  final omgeving = {
    'PYTHONIOENCODING': 'utf-8',
    'PYTHONUTF8': '1',
    'COLUMNS': '160',
    'PATH': padMetFfmpeg(ffmpeg, Platform.environment['PATH'] ?? '', windows: Platform.isWindows),
  };
  // Een kale naam ("ffmpeg.exe", via PATH gevonden) laten we aan PATH over.
  final ffVol = ffmpeg != null && ffmpeg.contains(Platform.pathSeparator) ? ffmpeg : null;
  for (final i in tidalerInstellingen(map: map, kwaliteit: kwaliteit, ffmpeg: ffVol)) {
    final r = await Process.run(tool, ['cfg', ...i],
        stdoutEncoding: _soepelUtf8, stderrEncoding: _soepelUtf8, environment: omgeving);
    if (r.exitCode != 0) return (fout: leesbareFout('${r.stdout}\n${r.stderr}'), kwaliteit: null);
  }
  final r = await Process.run(tool, ['dl', tidalerUrl(doel)],
      stdoutEncoding: _soepelUtf8, stderrEncoding: _soepelUtf8, environment: omgeving);
  final uitvoer = '${r.stdout}\n${r.stderr}';
  final binnen = await kwaliteitInMap(Directory(map));
  var iets = false;
  try {
    iets = await Directory(map).list(recursive: true).any((e) => e is File);
  } catch (_) {}
  if (!iets) {
    final niet = RegExp('log ?in|token', caseSensitive: false).hasMatch(uitvoer)
        ? ' Log opnieuw in met "tidaler login".'
        : '';
    return (fout: 'TIDAL leverde niets.$niet\n${leesbareFout(uitvoer)}', kwaliteit: null);
  }
  return (fout: null, kwaliteit: binnen);
}

/// Eén treffer van een zoekopdracht op TIDAL.
typedef TidalTreffer = ({String id, String artiest, String titel});

/// Het zoekhulpje: draait in tidalers eigen Python ([Tidaler.python]) en gebruikt zijn inlog. Elke treffer is één
/// regel JSON; alleen regels die met `{` beginnen tellen (tidaler drukt soms zelf iets af bij het laden).
///
/// De titel krijgt de versie erbij ("Get Lucky (Radio Edit)"): zo heet een nummer ook in een wens. Alleen stereo: de
/// wens is een stereobestand, geen Dolby Atmos.
const kTidalZoekHulp = r'''
import json, sys
# UTF-8, ook op Windows: met -I negeert Python PYTHONIOENCODING, en dan werd "KAYTRAMINÉ" "KAYTRAMIN?".
sys.stdout.reconfigure(encoding="utf-8")
from tidaler.config import Settings, Tidal

vraag, aantal = sys.argv[1], int(sys.argv[2])
alles = len(sys.argv) > 3 and sys.argv[3] == "alles"
t = Tidal(Settings())
if not t.login_token():
    print(json.dumps({"fout": "niet ingelogd"}))
    sys.exit(2)
r = t.session.search(vraag, limit=aantal)
if alles:
    for al in (r.get("albums") or [])[:aantal]:
        naam = al.name or ""
        versie = getattr(al, "version", None)
        if versie:
            naam = f"{naam} ({versie})"
        print(json.dumps({
            "soort": "album",
            "id": str(al.id),
            "artiest": al.artist.name if getattr(al, "artist", None) else "",
            "titel": naam,
            "jaar": str(getattr(al, "year", None) or ""),
        }, ensure_ascii=False))
for tr in (r.get("tracks") or [])[:aantal]:
    modi = getattr(tr, "audio_modes", None) or []
    naam = tr.name or ""
    versie = getattr(tr, "version", None)
    if versie:
        naam = f"{naam} ({versie})"
    print(json.dumps({
        "id": str(tr.id),
        "artiest": tr.artist.name if getattr(tr, "artist", None) else "",
        "titel": naam,
        "seconden": getattr(tr, "duration", None),
        "stereo": (not modi) or ("STEREO" in modi),
        "tags": getattr(tr, "media_metadata_tags", None) or [],
    }, ensure_ascii=False))
''';

/// De treffers uit de uitvoer van [kTidalZoekHulp], elk id één keer, zonder wat niet stereo is.
List<TidalTreffer> tidalZoektreffers(String uitvoer) {
  final uit = <TidalTreffer>[];
  final gezien = <String>{};
  for (final regel in uitvoer.split(RegExp(r'\r\n|\r|\n'))) {
    final r = regel.trim();
    if (!r.startsWith('{')) continue;
    try {
      final j = jsonDecode(r);
      if (j is! Map || j['id'] == null) continue;
      if (j['soort'] == 'album' || j['stereo'] == false) continue;
      final id = '${j['id']}';
      if (!gezien.add(id)) continue;
      uit.add((id: id, artiest: '${j['artiest'] ?? ''}', titel: '${j['titel'] ?? ''}'));
    } catch (_) {/* geen treffer */}
  }
  return uit;
}

/// De ids uit [treffers] die [titel] van [artiest] zijn, in de volgorde van TIDAL, zonder [nee].
///
/// **Streng op de titel, ruim op de artiest.** TIDAL noemt de eerste artiest: de wens "DJ Massiv vs the Rebel — High
/// Volume" heet daar "DJ Massiv". Daarom telt de artiest als de ene naam woord voor woord het begin van de andere is:
/// "DJ Massiv" past, "Sam" past niet op "Samantha Fox". De titel moet gelijk zijn, met of zonder gast ("(feat. …)").
/// Dat is niet het laatste woord: de keuring meet daarna de lengte en of het dezelfde opname is.
List<String> kiesTidalTreffers(
  List<TidalTreffer> treffers, {
  required String artiest,
  required String titel,
  Iterable<String> nee = const [],
}) {
  List<String> woorden(String s) => artistKey(s).split(' ').where((w) => w.isNotEmpty).toList();
  bool artiestPast(List<String> a, List<String> b) {
    final kort = a.length <= b.length ? a : b, lang = identical(kort, a) ? b : a;
    if (kort.isEmpty || kort.join(' ').length < 3) return false;
    for (var i = 0; i < kort.length; i++) {
      if (kort[i] != lang[i]) return false;
    }
    return true;
  }

  final wil = woorden(artiest);
  final t = normKey(titel), tKaal = normKey(zonderGastTitel(titel));
  final weg = nee.toSet();
  return [
    for (final x in treffers)
      if (!weg.contains(x.id) &&
          artiestPast(wil, woorden(x.artiest)) &&
          (normKey(x.titel) == t || normKey(zonderGastTitel(x.titel)) == tKaal))
        x.id,
  ];
}

/// Platen en nummers uit de uitvoer van [kTidalZoekHulp] met "alles" — voor het TIDAL-zoekscherm. Hier ook wat niet
/// stereo is: dat scherm toont de catalogus, en de keuring beslist bij het halen.
TidalZoekResultaat tidalCatalogusUit(String uitvoer) {
  final albums = <TidalAlbum>[], nummers = <TidalTrack>[];
  final gezien = <String>{};
  for (final regel in uitvoer.split(RegExp(r'\r\n|\r|\n'))) {
    final r = regel.trim();
    if (!r.startsWith('{')) continue;
    try {
      final j = jsonDecode(r);
      if (j is! Map || j['id'] == null) continue;
      final album = j['soort'] == 'album';
      if (!gezien.add('${album ? 'a' : 't'}${j['id']}')) continue;
      if (album) {
        albums.add(TidalAlbum('${j['id']}', '${j['titel'] ?? ''}', '${j['artiest'] ?? ''}', '${j['jaar'] ?? ''}'));
      } else {
        nummers.add(TidalTrack('${j['id']}', '${j['titel'] ?? ''}', '${j['artiest'] ?? ''}'));
      }
    } catch (_) {/* geen treffer */}
  }
  return TidalZoekResultaat(albums, nummers);
}

/// Zoek [vraag] in de TIDAL-catalogus met tidalers inlog: platen én nummers, voor het zoekscherm. Null als tidaler
/// (of zijn Python) er niet is of niet antwoordde.
///
/// **Waarom (Saber, 22-10-2026).** *"Niet verbonden met tidal staat er bij zoeken via tidal"* — dat scherm hing aan de
/// officiële API (een eigen app op developer.tidal.com en een tweede login), terwijl tidaler al ingelogd is.
Future<TidalZoekResultaat?> zoekCatalogusOpTidal(String vraag, {int aantal = 20}) async {
  final uit = await _zoekHulp(vraag, aantal, alles: true);
  return uit == null ? null : tidalCatalogusUit(uit);
}

/// Zoek [vraag] op TIDAL. Null als tidaler (of zijn Python) er niet is of niet antwoordde, anders de treffers.
Future<List<TidalTreffer>?> zoekOpTidal(String vraag, {int aantal = 10}) async {
  final uit = await _zoekHulp(vraag, aantal);
  return uit == null ? null : tidalZoektreffers(uit);
}

/// Het zoekhulpje draaien ([kTidalZoekHulp]); de ruwe uitvoer, of null.
Future<String?> _zoekHulp(String vraag, int aantal, {bool alles = false}) async {
  final py = Tidaler.python;
  if (py == null || vraag.trim().isEmpty) return null;
  try {
    final hulp = File('${Directory.systemTemp.path}${Platform.pathSeparator}debridmusic_tidal_zoek.py');
    await hulp.writeAsString(kTidalZoekHulp, flush: true);
    // -I: alleen tidalers eigen pakketten, niets uit de map waar het hulpje staat.
    final p = await Process.start(py, ['-I', hulp.path, vraag.trim(), '$aantal', if (alles) 'alles'],
        environment: {'PYTHONIOENCODING': 'utf-8', 'PYTHONUTF8': '1'});
    await p.stdin.close();
    final uit = p.stdout.transform(_soepelUtf8.decoder).join();
    final fout = p.stderr.transform(_soepelUtf8.decoder).join();
    final code = await p.exitCode.timeout(const Duration(minutes: 1), onTimeout: () {
      p.kill();
      return -1;
    });
    final tekst = await uit;
    await fout;
    if (code != 0) return null;
    return tekst;
  } catch (_) {
    return null;
  }
}

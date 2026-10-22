/// Een plaat van Tidal halen met `tiddl`.
///
/// **Waarom dit klein is en klein hoort te blijven.** Dit is de eerste bron die iets meesleept wat de
/// andere twee niet doen. Soulseek is 1947 regels Dart die het protocol zélf spreekt; TorBox is een
/// REST-koppeling. `tiddl` is een programma in Python dat jij op de pc installeert, en de app roept
/// het aan zoals hij ffmpeg en fpcalc aanroept. Meer dan dat wordt het niet: geen wachtrij, geen
/// eigen scherm, geen tweede downloadbeheer. Het bestand landt in je muziekmap en de bestaande scan
/// pikt het op.
///
/// **En tiddl kan niet zoeken.** Hij neemt alleen een Tidal-link of een id — er is geen zoekopdracht
/// in dat programma. Daarom is dit "plak een link" en geen zoekscherm: een zoekscherm zou betekenen
/// dat de app de Tidal-API zélf gaat spreken, en dat is precies het stuk dat stukgaat zodra Tidal
/// iets verandert.
///
/// Sinds tiddl 3 klopt dat half: `tiddl download search` tekent een tabel met treffers en vraagt dan
/// welke je wil. De FLAC-wens leest die tabel ([zoekOpTidal]) als reserve achter Soulseek; het
/// scherm blijft "plak een link".
///
/// Alleen op de machine die de muziek bezit. Een telefoon heeft geen Python, geen tiddl, en geen
/// muziekmap om iets in te zetten.
///
/// **Niet te verwarren met `tidal.dart` ernaast.** Dat is `TidalService`: de officiële Tidal-API,
/// die alleen de catalogus doorzoekt om er een zoekvraag voor Soulseek of een torrent van te maken —
/// die weg haalt geen enkel bestand van Tidal. Dit bestand doet het omgekeerde: het haalt de muziek
/// wél op, via jouw eigen abonnement, en weet niets van zoeken. Ze horen dus niet samengevoegd te
/// worden, hoe erg de namen ook op elkaar lijken.
library;

import 'dart:convert';
import 'dart:io';

import 'uitvoerbaar.dart';

import 'enrichment.dart' show zonderGastTitel;
import 'ffmpeg.dart';
import 'organize.dart' show artistKey, normKey;

/// Waar tiddl kan staan, in volgorde van waarschijnlijkheid.
///
/// Anders dan bij ffmpeg en fpcalc levert de bouwstraat dit NIET mee — het is een Python-programma
/// dat jij installeert. PATH staat daarom vooraan: dat is waar `pip install tiddl` en
/// `uv tool install tiddl` hem allebei neerzetten. De rest zijn de plekken waar die twee hem laten
/// staan als PATH niet is bijgewerkt, wat na een verse installatie op Windows het gewone geval is.
List<String> tiddlKandidaten({required String os, String? thuis}) {
  final huis = thuis ?? '';
  if (os == 'windows') {
    return [
      'tiddl.exe',
      if (huis.isNotEmpty) ...[
        '$huis\\.local\\bin\\tiddl.exe', // uv
        '$huis\\AppData\\Roaming\\Python\\Scripts\\tiddl.exe', // pip --user
      ],
    ];
  }
  return [
    'tiddl',
    if (huis.isNotEmpty) '$huis/.local/bin/tiddl', // uv en pip --user
    '/opt/homebrew/bin/tiddl',
    '/usr/local/bin/tiddl',
  ];
}

/// Het programma zelf: één keer zoeken, daarna onthouden.
///
/// Dezelfde vorm als [Fingerprinter] in `fingerprint.dart`, en om dezelfde reden: bij een misser
/// hoort er te staan wáár er gekeken is. "tiddl ontbreekt" zonder die lijst laat je nergens komen.
class Tiddl {
  static String? _gevonden;
  static bool _gekeken = false;

  /// Waar er gekeken is toen hij niet gevonden werd.
  static String? laatsteFout;

  static String? get pad {
    if (_gekeken) return _gevonden;
    _gekeken = true;
    final geprobeerd = <String>[];
    for (final k in tiddlKandidaten(
        os: Platform.operatingSystem,
        thuis: Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'])) {
      try {
        if (k.contains(Platform.pathSeparator)) {
          if (File(k).existsSync()) return _gevonden = k;
          // Zonder decoder: hier telt alleen of hij start. Zou de uitvoer wél gelezen worden, dan
          // kan een teken uit de verkeerde codetabel een uitzondering geven, en die zou hier
          // betekenen "tiddl bestaat niet" terwijl hij er gewoon staat.
        } else {
          // Kale naam: eerst zelf in PATH zoeken. Een `runSync` op iets wat er niet is kost op
          // macOS de hele app een SIGPIPE — zie uitvoerbaar.dart.
          final echt = uitvoerbaarPad(k);
          if (echt == null) {
            geprobeerd.add(k);
            continue;
          }
          if (Process.runSync(echt, ['--help'], stdoutEncoding: null, stderrEncoding: null)
                  .exitCode ==
              0) {
            return _gevonden = echt;
          }
        }
      } catch (_) {/* niet daar; volgende */}
      geprobeerd.add(k);
    }
    laatsteFout = 'tiddl niet gevonden; geprobeerd: ${geprobeerd.join(", ")}';
    return _gevonden = null;
  }

  static bool get beschikbaar => pad != null;

  /// Voor de toetsen, en voor nadat iemand tiddl geïnstalleerd heeft zonder de app te herstarten.
  static void resetLookup() {
    _gekeken = false;
    _gevonden = null;
    laatsteFout = null;
  }
}

/// Wat je geplakt hebt, omgezet naar iets dat tiddl aanneemt. Null als het onbruikbaar is.
///
/// **Waarom dit hier gebeurt en niet bij tiddl.** Een link uit de Tidal-app draagt van alles mee —
/// `?u`, een land, een verwijzer — en er zijn twee adressen in omloop (`tidal.com/browse/...` en
/// `listen.tidal.com/...`). Dat hier opruimen kost drie regels; het aan tiddl overlaten kost een
/// mislukte download met een foutmelding waar niemand iets aan heeft.
///
/// En het weigert wat niet klopt vóórdat er een proces gestart wordt. Een lege regel of een
/// Spotify-link hoort een zin op te leveren, geen rood scherm uit Python.
String? tidalDoel(String invoer) {
  var s = invoer.trim();
  if (s.isEmpty) return null;
  // Alles vanaf het vraagteken is meelifterij van de deelknop.
  final vraag = s.indexOf('?');
  if (vraag > 0) s = s.substring(0, vraag);
  s = s.replaceAll(RegExp(r'/+$'), '');

  const soorten = ['track', 'album', 'artist', 'playlist', 'mix', 'video'];
  // De korte vorm die tiddl zelf ook aanneemt: `album/103805723`.
  final kort = RegExp('^(${soorten.join("|")})/([A-Za-z0-9-]+)\$').firstMatch(s);
  if (kort != null) return s;

  final uri = Uri.tryParse(s);
  if (uri == null || !uri.hasScheme) return null;
  final gastheer = uri.host.toLowerCase();
  if (gastheer != 'tidal.com' &&
      gastheer != 'www.tidal.com' &&
      gastheer != 'listen.tidal.com') {
    return null;
  }
  // `/browse/album/123` en `/album/123` leiden allebei naar dezelfde plaat.
  final delen = uri.pathSegments.where((d) => d.isNotEmpty && d != 'browse').toList();
  if (delen.length < 2) return null;
  if (!soorten.contains(delen[0])) return null;
  return '${delen[0]}/${delen[1]}';
}

/// Een id uit de TIDAL-API omgezet naar wat tiddl aanneemt. Null als het onbruikbaar is.
///
/// Bewust via [tidalDoel] en niet met een eigen `'$soort/$id'`: die functie kent de zes soorten al
/// en weigert alles wat er niet uitziet als een id. Twee plekken die allebei beslissen wat een
/// geldig doel is, is er één te veel.
String? tidalDoelVanId(String soort, String id) => tidalDoel('$soort/${id.trim()}');

/// De vier kwaliteiten die tiddl kent, zoals hij ze zelf schrijft.
///
/// `max` is 24 bit tot 192 kHz en is de enige reden om dit te bouwen: het is een bron die levert wat
/// hij zegt. `low` en `normal` zijn m4a van 96 en 320 kbps — slechter dan wat deze bibliotheek al
/// heeft, en dus zinloos. Ze staan er omdat het abonnement ze kan afdwingen, niet omdat je ze wil.
const tidalKwaliteiten = ['max', 'high', 'normal', 'low'];

/// De opdrachtregel voor tiddl.
///
/// **De vlaggen staan vóór `url`, en dat is geen smaak.** `download` is de groep die de vlaggen
/// draagt en `url` is er een subopdracht van; erachter gezet worden ze niet gelezen.
///
/// **`-err` is de belangrijkste vlag hier.** Zonder hem drukt tiddl een fout in het rood af en stopt
/// met afloopcode 0 — de app zou dan "klaar" melden over een download die niet gebeurd is. Precies
/// het groene vinkje boven een onbeantwoorde vraag waar dit project al twee keer op stukliep. De
/// prijs is dat één nummer dat in jouw land niet te krijgen is de hele plaat afbreekt; dat is de
/// mindere van de twee kwaden, en de foutmelding zegt wélk nummer.
///
/// `-p` wijst de map aan zonder aan jouw tiddl-instellingen te komen. Sinds 29-09-2026 is dat een
/// keuringsmap en niet meer de muziekmap: wat tiddl aflevert wordt eerst gedecodeerd en vergeleken met
/// wat je al hebt, en pas daarna opgeborgen (zie `keuringMap` in paths.dart).
///
/// [zoekMap] is waar tiddl kijkt of hij iets al heeft (`--sp`). Zonder die vlag is dat zijn eigen
/// muziekmap, en staat het nummer daar, dan slaat hij het over en stopt hij netjes met afloopcode 0
/// zonder één bestand. De wens geeft daarom zijn verse keuringsmap mee.
List<String> tiddlOpdracht({
  required String tool,
  required String doel,
  required String map,
  String kwaliteit = 'max',
  String? zoekMap,
}) =>
    [
      tool, 'download', '-q', kwaliteit, '-p', map, '-err', //
      if (zoekMap != null) ...['--sp', zoekMap],
      'url', doel,
    ];

/// De uitvoer van tiddl leesbaar maken.
///
/// Hij tekent zijn voortgang met Rich, dus wat er terugkomt staat vol stuurtekens en herhaalde
/// regels. Voor een foutmelding op het scherm wil je de laatste paar regels zonder die rommel —
/// niet drie schermen aan balkjes.
String leesbareFout(String uitvoer, {int regels = 4}) {
  final schoon = uitvoer
      // ANSI-stuurtekens: kleuren en cursorsprongen.
      .replaceAll(RegExp(r'\x1B\[[0-9;?]*[A-Za-z]'), '')
      .replaceAll('\r', '\n');
  final over = [
    for (final r in schoon.split('\n'))
      if (r.trim().isNotEmpty) r.trim(),
  ];
  if (over.isEmpty) return 'tiddl zei niets.';
  return over.sublist(over.length > regels ? over.length - regels : 0).join('\n');
}

/// Het PATH waarmee tiddl gestart wordt, met de map van ffmpeg erbij.
///
/// **Waarom dit nodig is, en het kostte een plaat in de verkeerde kwaliteit om het te zien.** tiddl
/// heeft ffmpeg nodig om de hi-res-stroom van Tidal in elkaar te zetten. Staat ffmpeg niet op het
/// PATH, dan waarschuwt hij één regel — tussen zijn eigen voortgangsbalken door — en levert
/// vervolgens 16 bit / 44,1 kHz af terwijl je om `max` vroeg. Geen fout, geen afloopcode, gewoon
/// een mindere plaat dan je denkt te hebben. Dat is de vervelendste soort: hij ziet er goed uit.
///
/// Deze app wéét waar ffmpeg staat — hij zoekt hem al voor het herbemonsteren en de echtheidsproef,
/// en kijkt óók naast zijn eigen exe. Die map er hier bij zetten kost niets en haalt de val weg.
/// Vindt de app hem zelf niet, dan verandert er niets en blijft het aan jou om hem te installeren.
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

/// Zoals UTF-8, maar hij struikelt niet over een byte die er niet in hoort.
///
/// **Waarom dit nodig is.** Op Windows schrijft Python zijn uitvoer standaard in de codetabel van
/// de console (cp1252), niet in UTF-8. De strenge lezer gooide daar `FormatException: Unexpected
/// extension byte` op — en die vloog eruit ná afloop van het proces, dus terwijl de plaat allang
/// binnengehaald wás meldde de app "Kon tiddl niet starten". Een leesfout in een foutmelding die
/// zich voordoet als een mislukte download.
///
/// Hieronder wordt ook `PYTHONIOENCODING` gezet, zodat er om te beginnen UTF-8 uit komt. Dit is het
/// vangnet daaronder: kapotte tekens worden een vraagteken in plaats van een uitzondering. Tekst
/// die je toch alleen maar leest hoort nooit de reden te zijn dat iets faalt.
const _soepelUtf8 = Utf8Codec(allowMalformed: true);

/// De kwaliteit die tiddl zégt geleverd te hebben, uit zijn eigen uitvoer.
///
/// **Waarom dit uitgelezen wordt in plaats van aangenomen.** De app vraagt om `max`, maar wat er
/// werkelijk binnenkomt bepaalt Tidal — en die levert aan tiddl vaak 16 bit / 44,1 kHz terug terwijl
/// de Tidal-app zelf 24 bit speelt. Dat is een bekende beperking van tiddl (oskvr37/tiddl #395,
/// #379, #333) en niet iets wat hier op te lossen valt. Wél op te lossen: dat je het pas ontdekt
/// door achteraf naar de bitdiepte van je bestand te kijken. Wat hij levert, staat er nu bij.
///
/// Meerdere verschillende waarden bij een plaat betekent meestal een verzamelaar met gemengde
/// bronnen; dan hoor je ze allebei te zien in plaats van de laatste.
String? gemeldeKwaliteit(String uitvoer) {
  final gevonden = <String>{};
  for (final m in RegExp(r'(\d{1,2})-bit,\s*([\d.]+)\s*kHz', caseSensitive: false)
      .allMatches(uitvoer)) {
    gevonden.add('${m.group(1)} bit / ${m.group(2)} kHz');
  }
  return gevonden.isEmpty ? null : gevonden.join(' · ');
}

/// Wat er na een geslaagde download op het scherm komt.
///
/// De kwaliteit staat erbij omdat je die anders pas ontdekt door naar de bitdiepte van je bestand
/// te kijken — en dat is precies hoe het vandaag ontdekt werd dat `max` 16 bit opleverde.
///
/// [keuring] is wat de keuring besliste (zie `keuringMap` in paths.dart): sinds 29-09-2026 komt een
/// plaat van tiddl niet meer rechtstreeks in je muziekmap, maar eerst in de keuringsmap. Dan hoort de
/// melding ook te zeggen wat er níét in je bibliotheek kwam, en waarom.
String opgehaaldMelding(String kwaliteit, {String? keuring}) {
  final basis = kwaliteit.isEmpty ? 'Opgehaald' : 'Opgehaald ($kwaliteit)';
  return keuring == null || keuring.isEmpty
      ? '$basis — de bibliotheek wordt opnieuw doorzocht'
      : '$basis en gekeurd: $keuring';
}

/// Haal [doel] op naar [map]. Null als het lukte, anders de uitleg.
///
/// Geen tijdslimiet: een plaat van 24 bit is honderden megabytes en dat mag duren. Wat er niet mag
/// gebeuren is dat de app "klaar" zegt zonder dat er iets staat — daar is `-err` voor.
Future<({String? fout, String? kwaliteit})> haalVanTidal({
  required String doel,
  required String map,
  String kwaliteit = 'max',
  String? zoekMap,
}) async {
  final tool = Tiddl.pad;
  if (tool == null) {
    return (
      fout: 'tiddl staat niet op deze pc. Installeer hem met "uv tool install tiddl" of '
          '"pip install tiddl", en log één keer in met "tiddl auth login". '
          '${Tiddl.laatsteFout ?? ""}',
      kwaliteit: null,
    );
  }
  if (map.trim().isEmpty) return (fout: 'Er is nog geen muziekmap ingesteld.', kwaliteit: null);
  try {
    final r = await Process.run(
      tool,
      tiddlOpdracht(tool: tool, doel: doel, map: map, kwaliteit: kwaliteit, zoekMap: zoekMap)
          .sublist(1),
      stdoutEncoding: _soepelUtf8,
      stderrEncoding: _soepelUtf8,
      // Python vragen om UTF-8 te schrijven in plaats van de codetabel van de Windows-console.
      // Zonder dit komen accenten in artiestennamen er als rommel uit — en tot vandaag brak het
      // zelfs de hele aanroep af. Plus de map van ffmpeg, zie [padMetFfmpeg].
      environment: {
        'PYTHONIOENCODING': 'utf-8',
        'PYTHONUTF8': '1',
        'PATH': padMetFfmpeg(Ffmpeg().pad, Platform.environment['PATH'] ?? '',
            windows: Platform.isWindows),
      },
    );
    final uitvoer = '${r.stdout}\n${r.stderr}';
    if (r.exitCode == 0) return (fout: null, kwaliteit: gemeldeKwaliteit(uitvoer));
    return (fout: leesbareFout(uitvoer), kwaliteit: null);
  } catch (e) {
    return (fout: 'Kon tiddl niet starten: $e', kwaliteit: null);
  }
}

/// Eén regel uit de zoektabel van tiddl.
typedef TidalTreffer = ({String id, String artiest, String titel});

/// De treffers uit wat `tiddl download search -t track` afdrukt, elk id één keer.
///
/// **Waarom een tabel lezen.** tiddl zoekt alleen voor een mens: hij tekent de treffers en vraagt dan
/// welk nummer je wil. Met een gesloten invoer breekt hij af na de tabel ("Aborted.", afloopcode 1)
/// en haalt hij niets op, dus de tabel is alles wat er te lezen valt. Gemeten op 22-10-2026 met tiddl
/// 3.4.4:
///
///     │ │ 9    │ Track │ DJ Massiv - High Volume [STEREO]             │ 208442464 │ │
///
/// Alleen de eerste artiest staat erin, geen lengte en geen album, en hetzelfde id komt soms twee keer
/// voor. Een titel die niet past loopt door op de volgende regel, met een lege eerste cel. Een
/// nummer dat alleen in Dolby Atmos of 360 staat, valt weg: de wens is een stereobestand.
List<TidalTreffer> tidalZoektreffers(String uitvoer) {
  final uit = <TidalTreffer>[];
  final gezien = <String>{};
  final getal = RegExp(r'^\d+$');
  String? id;
  var tekst = '';
  void sluit() {
    final i = id;
    id = null;
    if (i == null || !gezien.add(i)) return;
    var t = tekst.trim();
    final modus = RegExp(r'\s*\[([A-Z0-9_, ]+)\]$').firstMatch(t);
    if (modus != null) {
      if (!modus.group(1)!.contains('STEREO')) return;
      t = t.substring(0, modus.start).trim();
    }
    final streep = t.indexOf(' - ');
    uit.add(streep < 0
        ? (id: i, artiest: '', titel: t)
        : (id: i, artiest: t.substring(0, streep).trim(), titel: t.substring(streep + 3).trim()));
  }

  final schoon = uitvoer.replaceAll(RegExp(r'\x1B\[[0-9;?]*[A-Za-z]'), '');
  for (final regel in schoon.split(RegExp(r'\r\n|\r|\n'))) {
    final delen = regel.split(RegExp('[│┃|]'));
    // Twee randen links (paneel en tabel), dan #, soort, titel, id, en weer twee randen rechts.
    if (delen.length != 8) continue;
    final c = [for (final d in delen.sublist(2, 6)) d.trim()];
    if (getal.hasMatch(c[0]) && getal.hasMatch(c[3])) {
      sluit();
      id = c[3];
      tekst = c[2];
    } else if (c[0].isEmpty && c[2].isNotEmpty && id != null) {
      tekst = '$tekst ${c[2]}';
    }
  }
  sluit();
  return uit;
}

/// De ids uit [treffers] die [titel] van [artiest] zijn, in de volgorde van tiddl, zonder [nee].
///
/// **Streng op de titel, ruim op de artiest.** tiddl toont alleen de eerste artiest: de wens "DJ
/// Massiv vs the Rebel — High Volume" heet daar "DJ Massiv - High Volume". Daarom telt de artiest
/// als de ene naam woord voor woord het begin van de andere is: "DJ Massiv" past, "Sam" past niet op
/// "Samantha Fox". De titel moet gelijk zijn, met of zonder gast ("(feat. …)"). Dat is niet het
/// laatste woord: de keuring meet daarna de lengte en of het dezelfde opname is als wat je hebt.
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

/// Zoek [vraag] op TIDAL. Null als tiddl er niet is of niet antwoordde, anders de treffers.
///
/// Breed getekend (`COLUMNS`): op de standaard 80 tekens kapt tiddl de soort af en breekt hij lange
/// titels over twee regels. De invoer gaat meteen dicht, zodat de vraag "welk nummer?" niet blijft
/// wachten; een minuut is ruim voor een zoekopdracht van drie seconden.
Future<List<TidalTreffer>?> zoekOpTidal(String vraag, {int aantal = 10}) async {
  final tool = Tiddl.pad;
  if (tool == null || vraag.trim().isEmpty) return null;
  try {
    final p = await Process.start(
      tool,
      ['download', 'search', '-t', 'track', '-n', '$aantal', vraag.trim()],
      environment: {
        'PYTHONIOENCODING': 'utf-8',
        'PYTHONUTF8': '1',
        'COLUMNS': '220',
      },
    );
    await p.stdin.close();
    final uit = p.stdout.transform(_soepelUtf8.decoder).join();
    final fout = p.stderr.transform(_soepelUtf8.decoder).join();
    await p.exitCode.timeout(const Duration(minutes: 1), onTimeout: () {
      p.kill();
      return -1;
    });
    return tidalZoektreffers('${await uit}\n${await fout}');
  } catch (_) {
    return null;
  }
}

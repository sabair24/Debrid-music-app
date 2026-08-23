/// Torrents zelf binnenhalen, zonder tussenpersoon.
///
/// **Waarom dit er is.** De app haalde alles via TorBox: die pakt de torrent op, en de app haalt
/// daarna de bestanden als gewone HTTP-download op. Dat is prachtig zolang TorBox meewerkt. Op
/// 23-08-2026 deed hij dat niet — hun API gaf een uur lang 504's en een omleiding naar hun eigen
/// statuspagina — terwijl dezelfde plaat in µTorrent op 6 MB/s binnenkwam. Dan is er niets stuk aan
/// de torrent; er zit alleen iemand tussen die er die dag niet was.
///
/// aria2 is die tussenpersoon niet: één programma van vijf megabyte, geen venster, aangestuurd over
/// localhost. Hij kan een `.torrent` én een magneet, praat met de tracker uit het bestand (en dat is
/// precies wat een RuTracker-zwerm nodig heeft, zie [SearchResult.torrentUrl]) en schrijft de
/// bestanden waar de app ze toch al verwacht.
///
/// **Wat het kost.** Jouw IP zit dan in de zwerm — dat is nu juist wat een debrid-dienst voor je
/// afschermt. Daarom blijft TorBox de eerste keus voor wat daar al klaarstaat, en is dit de weg voor
/// wat er níét staat of wanneer TorBox eruit ligt.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'paths.dart';
import 'warm_log.dart';

/// Eén bestand binnen een lopende torrent.
///
/// Per bestand, niet alleen per torrent: kies je drie nummers van een plaat, dan hoort de lijst drie
/// regels te tonen die elk hun eigen balk vullen. Eén balk voor de hele torrent laat twee van de drie
/// nummers "0%" melden tot ineens alles klaar is.
class Aria2Bestand {
  /// De nummering uit de torrent, vanaf 1 — dezelfde als [TorrentBestand.index].
  final int index;
  final String pad;
  final int lengte;
  final int gedaan;
  final bool gekozen;

  const Aria2Bestand(this.index, this.pad, this.lengte, this.gedaan, this.gekozen);

  double get voortgang => lengte > 0 ? (gedaan / lengte).clamp(0.0, 1.0) : 0.0;
  bool get klaar => lengte > 0 && gedaan >= lengte;
}

/// Hoe het met één torrent staat volgens aria2.
class Aria2Stand {
  final String gid;

  /// `active`, `waiting`, `paused`, `error`, `complete`, `removed` — de woorden van aria2 zelf.
  final String status;
  final int gedaan;
  final int totaal;
  final int seeders;
  final int verbindingen;
  final String fout;

  /// Wat aria2 op de schijf heeft staan, in dezelfde volgorde als in de torrent.
  final List<Aria2Bestand> bestanden;

  const Aria2Stand({
    required this.gid,
    required this.status,
    required this.gedaan,
    required this.totaal,
    required this.seeders,
    required this.verbindingen,
    required this.fout,
    required this.bestanden,
  });

  /// De gekozen bestanden, in de volgorde van de torrent.
  List<Aria2Bestand> get gekozen => bestanden.where((b) => b.gekozen).toList();

  Aria2Bestand? bestand(int index) =>
      bestanden.cast<Aria2Bestand?>().firstWhere((b) => b?.index == index, orElse: () => null);

  bool get klaar => status == 'complete';
  bool get stuk => status == 'error' || status == 'removed';
  double get voortgang => totaal > 0 ? (gedaan / totaal).clamp(0.0, 1.0) : 0.0;

  /// Niemand om van te halen. Niet meteen fataal — een zwerm kan even wakker moeten worden — maar
  /// wel het verschil tussen "traag" en "er is niets", en dat verschil hoort op het scherm.
  bool get geenBron => seeders <= 0 && verbindingen <= 0 && gedaan == 0;
}

/// Alles weghalen wat aria2 achterlaat, zodra de gekozen nummers uit de map gehaald zijn.
///
/// **Dit is geen netheid, dit is een reparatie.** Gemeten met B.B.E. — Seven Days And One Week,
/// waarbij alléén nummer 1 gekozen was; na afloop stond er in de map:
///
///     01. ... [Radio Edit].flac                      26 MB   <- het gevraagde nummer
///     <torrentnaam>/02. ... [Club Mix].flac           2 kB   <- NIET gevraagd, en toch een bestand
///     <torrentnaam>.aria2                                    <- aria2's eigen administratie
///     <infohash>.torrent                                     <- het aangeboden torrentbestand
///
/// Dat tweede bestand is het gevaarlijke. Torrentstukken trekken zich niets aan van bestandsgrenzen,
/// dus een stuk dat half in nummer 2 valt schrijft daar een paar kilobytes. De scanner slaat deze map
/// niet over — en dan staat er een FLAC van twee kilobyte in je bibliotheek die nergens op lijkt en
/// die je pas hoort als je hem aanklikt.
///
/// Welke mappen weg mogen komt uit aria2's eigen opgave en niet uit de torrentnaam: die twee lopen
/// uiteen zodra er een teken in staat dat Windows niet in een mapnaam duldt.
Future<void> ruimOpNaTorrent(Directory wortel, Aria2Stand? stand) async {
  try {
    final vanAria2 = <String>{};
    for (final b in stand?.bestanden ?? const <Aria2Bestand>[]) {
      final rest = b.pad.replaceAll('/', Platform.pathSeparator);
      if (!rest.startsWith(wortel.path)) continue;
      final staart = rest.substring(wortel.path.length).split(Platform.pathSeparator)
        ..removeWhere((s) => s.isEmpty);
      if (staart.length > 1) vanAria2.add(staart.first);
    }

    for (final naam in vanAria2) {
      final map = Directory('${wortel.path}${Platform.pathSeparator}$naam');
      if (await map.exists()) await map.delete(recursive: true);
    }
    for (final e in wortel.listSync().whereType<File>()) {
      if (e.path.endsWith('.aria2') || e.path.endsWith('.torrent')) await e.delete();
    }
  } catch (_) {
    // Opruimen is nooit een reden om een geslaagde download te laten mislukken.
  }
}

/// De motor: één aria2-proces, aangestuurd over JSON-RPC op localhost.
class Aria2 {
  Aria2({String? pad}) : _opgegeven = pad;
  final String? _opgegeven;

  Process? _proces;
  int _poort = 0;
  String _geheim = '';
  late final WarmLog _log = WarmLog('$logDir${Platform.pathSeparator}aria2.log');

  /// Waar het op stukliep, voor wie het wil weten — zwijgen is niet gratis.
  String? laatsteFout;

  bool get draait => _proces != null;

  // ---------------------------------------------------------------- het programma vinden

  static String? _gevonden;
  static bool _gezocht = false;

  /// Kandidaten, in volgorde van vertrouwen. Naast de app eerst: daar zet de installer hem neer,
  /// net als `fpcalc.exe`. Daarna de eigen map, waar een handmatig neergezette versie mag staan
  /// zonder dat een herinstallatie hem weggooit. En tot slot PATH.
  static List<String> kandidaten({String? naastDeApp, String? eigenMap}) {
    final exe = Platform.isWindows ? 'aria2c.exe' : 'aria2c';
    final naast = naastDeApp ?? File(Platform.resolvedExecutable).parent.path;
    return [
      '$naast${Platform.pathSeparator}$exe',
      if (eigenMap != null && eigenMap.isNotEmpty) '$eigenMap${Platform.pathSeparator}$exe',
      if (!Platform.isWindows) ...['/usr/bin/aria2c', '/usr/local/bin/aria2c', '/opt/homebrew/bin/aria2c'],
      exe, // via PATH
    ];
  }

  String? get pad {
    if (_opgegeven != null && _opgegeven.isNotEmpty) return _opgegeven;
    if (_gezocht) return _gevonden;
    _gezocht = true;
    final geprobeerd = <String>[];
    for (final k in kandidaten(eigenMap: appDir)) {
      try {
        if (Process.runSync(k, ['--version']).exitCode == 0) {
          _gevonden = k;
          return k;
        }
      } catch (_) {
        // niet gevonden of niet uitvoerbaar; volgende
      }
      geprobeerd.add(k);
    }
    laatsteFout = 'aria2c niet gevonden; geprobeerd: ${geprobeerd.join(", ")}';
    return null;
  }

  bool get beschikbaar => pad != null;

  /// Tests delen dit proces; een gevonden pad uit de vorige laat de volgende iets anders meten.
  static void resetLookup() {
    _gevonden = null;
    _gezocht = false;
  }

  // ---------------------------------------------------------------- starten

  /// De opdrachtregel waarmee het proces start. Apart en openbaar omdat elk van deze vlaggen een
  /// reden heeft die je nergens meer terugziet zodra hij eenmaal draait.
  static List<String> argumenten({
    required int poort,
    required String geheim,
    required String map,
    required String logbestand,
    int? stopMetProces,
  }) =>
      [
        '--enable-rpc',
        '--rpc-listen-port=$poort',
        // Alleen deze machine. Een torrentmotor die van buitenaf aanstuurbaar is, is een torrentmotor
        // van iemand anders.
        '--rpc-listen-all=false',
        '--rpc-secret=$geheim',
        // Een torrentbestand gaat als base64 door de RPC heen; de standaard van 2 MB is te krap voor
        // een plaat met veel stukken.
        '--rpc-max-request-size=32M',
        // Niet het aangeboden torrentbestand naast de muziek neerleggen. Staat standaard AAN: er
        // bleef een `<infohash>.torrent` liggen in de map waar de scanner straks doorheen loopt.
        '--rpc-save-upload-metadata=false',
        '--dir=$map',
        // Klaar is klaar: niet blijven seeden met andermans bandbreedte zonder dat iemand daarom
        // vroeg. Wie wél wil seeden zet dit om in de instellingen.
        '--seed-time=0',
        // Vijftien minuten niets binnen is geen trage zwerm meer. Zonder dit blijft een dode torrent
        // eeuwig "actief" heten — precies de klacht die deze hele weg heeft aangezwengeld.
        '--bt-stop-timeout=900',
        // Niet eerst het hele bestand op schijf reserveren: op NTFS kost dat bij een plaat van een
        // gigabyte seconden waarin er zichtbaar niets gebeurt.
        '--file-allocation=none',
        '--continue=true',
        '--summary-interval=0',
        '--console-log-level=warn',
        '--log-level=notice',
        '--log=$logbestand',
        // Sterft de app, dan sterft de motor mee. Anders blijft er een proces achter dat downloadt
        // voor een app die er niet meer is.
        if (stopMetProces != null) '--stop-with-process=$stopMetProces',
      ];

  /// Start het proces als het nog niet draait. Geeft false als aria2 niet gevonden is.
  Future<bool> start({String? downloadMap}) async {
    if (_proces != null) return true;
    final exe = pad;
    if (exe == null) return false;

    _poort = await _vrijePoort();
    _geheim = _geheimpje();
    final map = downloadMap ?? Directory.systemTemp.createTempSync('dm_aria2_').path;
    final logbestand = '$logDir${Platform.pathSeparator}aria2.log';

    try {
      _proces = await Process.start(
          exe, argumenten(poort: _poort, geheim: _geheim, map: map, logbestand: logbestand, stopMetProces: pid),
          // Losgekoppeld ZONDER pijpen. Met `detachedWithStdio` blijven stdout en stderr openstaan,
          // en die twee houden het proces dat ze niet leest in leven: een meting die klaar was bleef
          // vijf minuten hangen tot de wachtklok hem afkapte. aria2 schrijft zijn verhaal toch al in
          // `--log`, dus er valt hier niets te lezen dat we missen.
          mode: ProcessStartMode.detached);
      _log.line('aria2 gestart op poort $_poort ($exe)');
    } catch (e) {
      laatsteFout = 'aria2 startte niet: $e';
      _log.line(laatsteFout!);
      return false;
    }

    // Wachten tot hij luistert. Zonder dit strandt de eerste toevoeging op een dichte poort, en dat
    // leest als "torrent geweigerd" terwijl er alleen nog niemand thuis was.
    for (var i = 0; i < 50; i++) {
      if (await _leeft()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    laatsteFout = 'aria2 luisterde niet binnen vijf seconden op poort $_poort';
    _log.line(laatsteFout!);
    await stop();
    return false;
  }

  Future<bool> _leeft() async {
    try {
      await _roep('aria2.getVersion', []);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    final p = _proces;
    _proces = null;
    if (p == null) return;
    try {
      await _roep('aria2.shutdown', []).timeout(const Duration(seconds: 3));
    } catch (_) {
      // hij luisterde al niet meer; dan maar hard
    }
    p.kill();
  }

  // ---------------------------------------------------------------- de RPC zelf

  /// Het lichaam van één RPC-verzoek. Openbaar zodat een toets de vorm kan vastleggen zonder dat er
  /// een proces aan te pas komt.
  static Map<String, dynamic> verzoek(String methode, List<dynamic> params, String geheim) => {
        'jsonrpc': '2.0',
        'id': 'dm',
        'method': methode,
        'params': [if (geheim.isNotEmpty) 'token:$geheim', ...params],
      };

  Future<dynamic> _roep(String methode, List<dynamic> params) async {
    final r = await http
        .post(Uri.parse('http://127.0.0.1:$_poort/jsonrpc'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(verzoek(methode, params, _geheim)))
        .timeout(const Duration(seconds: 20));
    final j = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
    if (j is Map && j['error'] != null) {
      throw 'aria2: ${(j['error'] as Map)['message'] ?? j['error']}';
    }
    return (j as Map)['result'];
  }

  /// Zet een torrentbestand klaar en begin. [kies] is de nummering uit de torrent (vanaf 1); leeg
  /// betekent alles.
  Future<String?> voegTorrentToe(List<int> torrent,
      {required String map, List<int> kies = const []}) async {
    try {
      final opties = <String, String>{
        'dir': map,
        if (kies.isNotEmpty) 'select-file': kies.join(','),
      };
      final gid = await _roep('aria2.addTorrent', [base64Encode(torrent), <String>[], opties]);
      _log.line('torrent toegevoegd: gid=$gid, kies=${kies.isEmpty ? "alles" : kies.join(",")}, map=$map');
      return gid as String?;
    } catch (e) {
      laatsteFout = '$e';
      _log.line('toevoegen mislukt: $e');
      return null;
    }
  }

  /// Hetzelfde met een magneet. Levert eerst een taak op die alleen de metadata ophaalt; aria2 zet
  /// daarna zélf de echte download klaar, en die krijgt een ANDER gid — vandaar [volgOp].
  Future<String?> voegMagneetToe(String magneet, {required String map}) async {
    try {
      final gid = await _roep('aria2.addUri', [
        [magneet],
        {'dir': map},
      ]);
      _log.line('magneet toegevoegd: gid=$gid');
      return gid as String?;
    } catch (e) {
      laatsteFout = '$e';
      _log.line('magneet toevoegen mislukt: $e');
      return null;
    }
  }

  /// Waar de echte download heen ging nadat een magneet zijn metadata had. aria2 zet het nieuwe gid
  /// in `followedBy`; wie dat niet volgt kijkt voor eeuwig naar een taak die "compleet" heet omdat
  /// het torrentbestand binnen is.
  Future<String?> volgOp(String gid) async {
    try {
      final r = await _roep('aria2.tellStatus', [gid, <String>['followedBy']]);
      final lijst = (r as Map)['followedBy'];
      return (lijst is List && lijst.isNotEmpty) ? lijst.first as String : null;
    } catch (_) {
      return null;
    }
  }

  Future<Aria2Stand?> stand(String gid) async {
    try {
      final r = await _roep('aria2.tellStatus', [
        gid,
        <String>['status', 'totalLength', 'completedLength', 'errorMessage', 'numSeeders', 'connections', 'files'],
      ]) as Map;
      final bestanden = (r['files'] as List?) ?? const [];
      return Aria2Stand(
        gid: gid,
        status: (r['status'] ?? '') as String,
        gedaan: int.tryParse('${r['completedLength'] ?? 0}') ?? 0,
        totaal: int.tryParse('${r['totalLength'] ?? 0}') ?? 0,
        seeders: int.tryParse('${r['numSeeders'] ?? 0}') ?? 0,
        verbindingen: int.tryParse('${r['connections'] ?? 0}') ?? 0,
        fout: (r['errorMessage'] ?? '') as String,
        bestanden: [
          for (final f in bestanden)
            if (f is Map)
              Aria2Bestand(
                int.tryParse('${f['index'] ?? 0}') ?? 0,
                '${f['path']}',
                int.tryParse('${f['length'] ?? 0}') ?? 0,
                int.tryParse('${f['completedLength'] ?? 0}') ?? 0,
                // aria2 antwoordt met de TEKST "true"/"false", niet met een boolean; `== true`
                // vergelijken levert overal false op en dan lijkt er niets gekozen.
                '${f['selected']}' == 'true',
              ),
        ],
      );
    } catch (e) {
      laatsteFout = '$e';
      return null;
    }
  }

  /// Weghalen. `forceRemove` omdat een taak die nog aan het aanmelden is bij de tracker anders
  /// blijft hangen tot die tracker antwoordt — en dat kan minuten duren.
  Future<void> verwijder(String gid) async {
    try {
      await _roep('aria2.forceRemove', [gid]);
    } catch (_) {
      // al weg, of nooit begonnen
    }
    try {
      await _roep('aria2.removeDownloadResult', [gid]);
    } catch (_) {
      // hoeft niet te lukken; dit is opruimen, geen opdracht
    }
  }

  // ---------------------------------------------------------------- kleine dingen

  static Future<int> _vrijePoort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  static String _geheimpje() {
    final r = Random.secure();
    return List.generate(24, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}

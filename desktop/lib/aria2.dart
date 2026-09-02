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

import 'uitvoerbaar.dart';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'paths.dart';
import 'warm_log.dart';

/// Wat er in `select-file` moet komen te staan als [erbij] mee moet doen met [huidig].
///
/// Null betekent: laat het staan zoals het staat.
///
/// **Zuiver en apart, want dit is de regel die stil een download kan afkappen.** Wie de nieuwe
/// selectie schrijft in plaats van de vereniging te nemen, haalt het nummer weg dat al aan het
/// binnenkomen was — die download stopt dan halverwege zonder één woord uitleg. En een LEGE
/// `select-file` betekent bij aria2 "alles": daar iets bij kiezen is niets toevoegen maar juist
/// alles behalve dat ene weggooien.
///
/// Zonder deze functie was dat alleen te toetsen op een machine waar toevallig een aria2 draait.
String? selectieErbij(String huidig, List<int> erbij) {
  if (erbij.isEmpty) return null;
  final nu = <int>{};
  for (final deel in huidig.split(',')) {
    final n = int.tryParse(deel.trim());
    if (n != null) nu.add(n);
  }
  if (nu.isEmpty) return null; // leeg = alles; daar valt niets bij te kiezen
  final voor = nu.length;
  nu.addAll(erbij.where((n) => n > 0));
  if (nu.length == voor) return null; // stond er al in; niets te veranderen
  final samen = nu.toList()..sort();
  return samen.join(',');
}

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

  /// Waar `aria2c` staat, of null.
  ///
  /// **Alleen een GEVONDEN pad wordt onthouden, een misser niet.** Dat verschil is een hele avond
  /// waard. De vorige opzet zette `_gezocht = true` vóór het zoeken en liet dat staan, ook als er
  /// niets uitkwam — en `_gezocht` is statisch, dus dat gold voor de rest van de looptijd van de
  /// app. Eén keer misgrijpen, bijvoorbeeld omdat het bestand net vervangen werd door een
  /// installatie of omdat een virusscanner het even vasthield, en er kwam tot de volgende herstart
  /// geen torrent meer binnen. Zonder melding, want [start] zweeg erover.
  ///
  /// **Gemeten op 02-09-2026.** Saber probeerde twee nummers van Linkin Park te halen; het mislukte
  /// zonder spoor. In `aria2.log` sprong de tijd van 01-09 15:56 naar 02-09 19:11 — zijn hele
  /// sessie van zes uur ertussen, en in al die tijd is aria2 geen enkele keer gestart. Na een
  /// herstart van de app lukte exact dezelfde download meteen.
  ///
  /// Opnieuw zoeken kost een `--version`-aanroep van een paar milliseconden, en alleen wanneer er
  /// iets te downloaden valt. Dat is niets vergeleken met stil niets doen.
  String? get pad {
    if (_opgegeven != null && _opgegeven.isNotEmpty) return _opgegeven;
    if (_gevonden != null) return _gevonden;
    _gezocht = true;
    final geprobeerd = <String>[];
    for (final k in kandidaten(eigenMap: appDir)) {
      try {
        final echt = uitvoerbaarPad(k);
        if (echt == null) continue;
        if (Process.runSync(echt, ['--version']).exitCode == 0) {
          _gevonden = echt;
          return echt;
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
    if (exe == null) {
      // ZEG HET, want dit is de stilste manier waarop het downloaden kan stoppen.
      //
      // Hier stond kaal `return false`. De opdracht kreeg dan wel "Mislukt" op het scherm, maar in
      // `aria2.log` bleef het leeg — en dat is precies het logboek waar je gaat kijken. Op
      // 02-09-2026 leverde dat een sessie van zes uur op waarin geen enkele torrent binnenkwam en
      // nergens stond waarom. Eén regel had dat een minuut gekost in plaats van een avond.
      _log.line(laatsteFout ?? 'aria2c niet gevonden');
      return false;
    }

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
  /// [seedMinuten] overschrijft de standaard "klaar is klaar" voor deze ene torrent.
  ///
  /// **Waarvoor dat nodig is.** Op een open bron maakt het niet uit; op een BESLOTEN tracker als
  /// Redacted heet binnenhalen-en-meteen-stoppen "hit and run", en daar staat verlies van je account
  /// op. Per torrent en niet als startvlag, want in dezelfde app lopen beide soorten door elkaar.
  Future<String?> voegTorrentToe(List<int> torrent,
      {required String map, List<int> kies = const [], int? seedMinuten}) async {
    try {
      final opties = <String, String>{
        'dir': map,
        if (kies.isNotEmpty) 'select-file': kies.join(','),
        if (seedMinuten != null && seedMinuten > 0) 'seed-time': '$seedMinuten',
        // Een half bestand van een vorige poging mag geen blokkade zijn.
        //
        // **Gemeten op 29-08-2026** met Tears For Fears — Songs From The Big Chair. Nummer 1 viel om
        // op een te lang pad; daarna haalde `forceRemove` het `.aria2`-administratiebestand weg maar
        // bleef het halve bestand staan. Elke volgende poging op diezelfde plaat kreeg toen:
        //
        //     "… exists, but a control file(*.aria2) does not exist. Download was canceled in order
        //      to prevent your file from being truncated to 0."
        //
        // Zonder deze vlag is die plaat dus voorgoed dicht voor de app, tot iemand met de hand een
        // map leegmaakt die hij niet kan vinden. aria2 controleert de stukken toch tegen de hashes
        // uit de torrent, dus overschrijven kost hooguit werk, nooit juistheid.
        'allow-overwrite': 'true',
      };
      final gid = await _roep('aria2.addTorrent', [base64Encode(torrent), <String>[], opties]);
      // De beginselectie onthouden, want dit is de enige plek waar hij nog te weten is: zie
      // [kiesErbij] voor wat aria2 er straks van maakt.
      if (gid is String && kies.isNotEmpty) _selectiePerGid[gid] = {...kies.where((n) => n > 0)};
      _log.line('torrent toegevoegd: gid=$gid, kies=${kies.isEmpty ? "alles" : kies.join(",")}, map=$map');
      return gid as String?;
    } catch (e) {
      laatsteFout = '$e';
      _log.line('toevoegen mislukt: $e');
      return null;
    }
  }

  /// Het gid van een torrent die aria2 AL heeft, gezocht op infohash. Null als hij hem niet kent.
  ///
  /// **Waarom dit moest bestaan.** aria2 kent een torrent aan zijn infohash en weigert een tweede
  /// aanmelding van dezelfde plaat. Binnen één opdracht was dat ondervangen — één taak voor de hele
  /// torrent, zie `online.dart` — maar niet tussen twee opdrachten door. Wie nummer 5 van een album
  /// haalt en daarna nummer 9 van hetzelfde album, meldt dezelfde torrent een tweede keer aan, en
  /// krijgt een weigering met de infohash erin. Precies de melding die op 26-08-2026 op het scherm
  /// stond bij "verschillende liedjes van RuTracker".
  ///
  /// Actief én wachtend én gestopt, want alle drie tellen mee voor de weigering: een torrent die
  /// klaar is maar nog in aria2's resultatenlijst staat, blokkeert een nieuwe aanmelding net zo goed.
  Future<String?> zoekGidVoor(String infohash) async {
    final gezocht = infohash.toLowerCase();
    if (gezocht.isEmpty) return null;
    const velden = <String>['gid', 'infoHash'];

    Future<String?> uit(String methode, List<dynamic> params) async {
      try {
        final r = await _roep(methode, params);
        if (r is! List) return null;
        for (final item in r) {
          if (item is! Map) continue;
          if ('${item['infoHash']}'.toLowerCase() == gezocht) return '${item['gid']}';
        }
      } catch (_) {
        // Eén lijst niet kunnen lezen is geen reden om de andere twee over te slaan.
      }
      return null;
    }

    return await uit('aria2.tellActive', <dynamic>[velden]) ??
        await uit('aria2.tellWaiting', <dynamic>[0, 200, velden]) ??
        await uit('aria2.tellStopped', <dynamic>[0, 200, velden]);
  }

  /// Er bestanden bij kiezen in een torrent die al loopt.
  ///
  /// De vereniging, niet de vervanging: wie nummer 9 erbij vraagt terwijl nummer 5 nog binnenkomt,
  /// mag nummer 5 niet uit de selectie duwen — dan stopt die download halverwege zonder een woord.
  ///
  /// Geeft terug of het gelukt is. Niet gelukt betekent dat de aanroeper eerlijk moet melden dat er
  /// niets bij gekozen kon worden, in plaats van te wachten op bestanden die nooit komen.
  Future<bool> kiesErbij(String gid, List<int> erbij) async {
    if (erbij.isEmpty) return true;
    try {
      // WAT WIJ ZELF AL GEKOZEN HEBBEN TELT ZWAARDER DAN WAT ARIA2 TERUGZEGT.
      //
      // `aria2.getOption` geeft `select-file` terug zoals die bij het AANMELDEN is meegegeven, en
      // niet zoals `changeOption` hem daarna heeft gezet. Wie dus twee keer iets bij kiest, begint
      // de tweede keer weer bij de oorspronkelijke lijst -- en gooit de eerste toevoeging eruit.
      //
      // **Gemeten op 31-08-2026, zeven nummers van Beyoncé - Dangerously In Love:**
      //
      //     23:54:18.731  torrent toegevoegd: gid=98e4..., kies=5,19
      //     23:54:18.757  erbij gekozen: 10,19 -> 5,10,19
      //     23:54:18.767  erbij gekozen: 13,19 -> 5,13,19      <- de 10 is weg
      //     23:54:19.151  erbij gekozen:  7,19 -> 5,7,19       <- 10 en 13 allebei weg
      //
      // Er kwamen drie van de zeven bestanden binnen, en de vier andere meldden "0% binnen" over
      // een torrent die verder gewoon liep. Stil, want niets in dit antwoord zegt dat er iets is
      // weggevallen.
      //
      // De app weet zelf wat ze gevraagd heeft, en dat is de betrouwbare bron. aria2's antwoord
      // blijft de terugval voor een gid dat we niet zelf hebben aangemeld.
      final onthouden = _selectiePerGid[gid];
      String huidig;
      if (onthouden != null && onthouden.isNotEmpty) {
        huidig = (onthouden.toList()..sort()).join(',');
      } else {
        final opties = await _roep('aria2.getOption', [gid]);
        huidig = opties is Map ? '${opties['select-file'] ?? ''}' : '';
      }
      final nieuw = selectieErbij(huidig, erbij);
      if (nieuw == null) return true;
      await _roep('aria2.changeOption', [
        gid,
        {'select-file': nieuw},
      ]);
      _selectiePerGid[gid] = {
        for (final deel in nieuw.split(',')) if (int.tryParse(deel) != null) int.parse(deel),
      };
      _log.line('erbij gekozen in $gid: ${erbij.join(",")} -> $nieuw');
      return true;
    } catch (e) {
      laatsteFout = '$e';
      _log.line('erbij kiezen mislukt in $gid: $e');
      return false;
    }
  }

  /// Welke bestandsnummers er per taak gekozen zijn, zoals DEZE app ze heeft opgegeven.
  ///
  /// Zie [kiesErbij] voor waarom dit niet aan aria2 gevraagd kan worden.
  final Map<String, Set<int>> _selectiePerGid = {};

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

  /// Alleen de INHOUDSOPGAVE van een magneet ophalen: welke bestanden zitten erin.
  ///
  /// **Waarom dit apart bestaat.** Een magneet draagt niets dan een infohash. Bij RuTracker halen we
  /// het `.torrent` gewoon bij de site op, maar Knaben en Pirate Bay geven alleen een magneet — en
  /// dáár liep alles op stuk: zonder bestandslijst kon de app niets anders dan het aan TorBox vragen
  /// en wachten. Dat is de "Voorbereiden" die maar bleef staan.
  ///
  /// De metadata is een paar tientallen kilobytes en komt van dezelfde peers als de muziek zelf, dus
  /// wie de zwerm kan bereiken heeft hem binnen enkele seconden. Lukt dat niet, dan wéét je meteen
  /// dat er niets te halen valt — en dat is oneindig veel beter dan een balk die niet beweegt.
  ///
  /// `follow-torrent=false` is hier wezenlijk: anders begint aria2 uit zichzelf de hele plaat te
  /// downloaden zodra de metadata binnen is, en dan haal je vijf gigabyte op om een lijstje te
  /// kunnen tonen.
  Future<List<int>?> haalMetadata(String magneet,
      {required String map, Duration limiet = const Duration(seconds: 30)}) async {
    final gid = await _roep('aria2.addUri', [
      [magneet],
      {
        'dir': map,
        'bt-metadata-only': 'true',
        'bt-save-metadata': 'true',
        'follow-torrent': 'false',
      },
    ]).then((r) => r as String?).catchError((Object e) {
      laatsteFout = '$e';
      return null;
    });
    if (gid == null) return null;

    final tot = DateTime.now().add(limiet);
    try {
      while (DateTime.now().isBefore(tot)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final s = await stand(gid);
        if (s == null) continue;
        if (s.stuk) {
          _log.line('metadata mislukt voor $magneet: ${s.fout}');
          return null;
        }
        if (!s.klaar) continue;

        // aria2 legt hem neer als <infohash>.torrent in de map.
        final hash = _infohashUit(magneet);
        final bestand = File('$map${Platform.pathSeparator}$hash.torrent');
        if (!await bestand.exists()) {
          _log.line('metadata klaar maar geen bestand: ${bestand.path}');
          return null;
        }
        final bytes = await bestand.readAsBytes();
        await bestand.delete().catchError((_) => bestand);
        _log.line('metadata binnen: $hash (${bytes.length} bytes)');
        return bytes;
      }
      _log.line('metadata niet binnen in ${limiet.inSeconds}s: $magneet');
      return null;
    } finally {
      await verwijder(gid);
      // WACHTEN TOT HIJ HEM ÉCHT KWIJT IS.
      //
      // aria2 registreert een metadata-taak op dezelfde infohash als de echte download. Meldt de app
      // de torrent aan terwijl die registratie nog niet opgeruimd is, dan krijgt hij:
      //
      //     errorCode=12 InfoHash 6f948bec… is already registered
      //
      // Gemeten op 29-08-2026 met Tears For Fears, twaalf milliseconden na het opruimen. Twaalf.
      // `forceRemove` keert terug voordat de administratie leeg is, dus even kijken tot het zo is.
      final hash = _infohashUit(magneet);
      if (hash.isNotEmpty) {
        for (var i = 0; i < 30; i++) {
          if (await zoekGidVoor(hash) == null) break;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    }
  }

  /// De infohash uit een magneet, kleingeschreven — zoals aria2 zijn bestand noemt.
  static String _infohashUit(String magneet) {
    final m = RegExp(r'btih:([0-9a-fA-F]{40})', caseSensitive: false).firstMatch(magneet);
    return (m?.group(1) ?? '').toLowerCase();
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
    // Ook onze eigen boekhouding, anders groeit die met elke plaat mee en zou een hergebruikt gid
    // een selectie van een vorige torrent erven.
    _selectiePerGid.remove(gid);
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

/// Bijwerken vanuit de app zelf: kijken of er een nieuwere APK klaarstaat, hem binnenhalen en de
/// installer openen.
///
/// **Waarom dit bestaat.** De oude Kotlin-app had zoiets; die is er in juli uitgehaald en de
/// Flutter-app heeft het nooit teruggekregen. Bijwerken ging sindsdien met de hand: naar GitHub,
/// de juiste release zoeken, de APK downloaden, "installeren uit onbekende bronnen" aanzetten. Op
/// een telefoon is dat zes handelingen voor iets wat er één hoort te zijn, en het gevolg is
/// voorspelbaar — je loopt achter zonder het te weten.
///
/// **Wat hier NIET in zit: een versienummer vergelijken.** Elke APK heet `3.9.74`, want dat getal
/// komt uit `pubspec.yaml` en dat wordt niet per release opgehoogd. Wat wél elke bouw omhoog gaat
/// is het BUILDNUMMER, en dat is toevallig ook precies het getal waar Android zelf op kijkt
/// (`versionCode`): een APK met een lager nummer weigert hij als een stap terug. Dus is dat hier
/// het enige getal dat telt. Vergelijken op de naam zou betekenen dat 11037 en 11014 even nieuw
/// zijn.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'paths.dart';
import 'ui/kleuren.dart';

/// De APK's staan in een APARTE, openbare repo. De broncode-repo was ooit privé en de ingebouwde
/// updater moest zonder in te loggen bij de bestanden kunnen; dat is nog steeds waar deze naar
/// wijst, en verhuizen zou elke telefoon die de app al draagt afsnijden.
const _releasesRepo = 'sabair24/Debrid-music-app-releases';

/// De Windows-installer hangt aan de `win-v`-tag in de BRONCODE-repo, niet in die hierboven. Twee
/// plekken dus, en dat is geen slordigheid: de APK gaat naar buiten met een eigen tag per bouw
/// (`v3.9.74-build11037`) omdat Android op het buildnummer kijkt, en de installer draagt de
/// release-tag zelf (`win-v3.9.141`) omdat Windows op de versienaam kijkt.
const _bronRepo = 'sabair24/Debrid-music-app';

const _kanaal = MethodChannel('debridmusic/updater');

/// Eén klaarstaande APK.
@immutable
class Uitgave {
  final String versie;
  final int buildnummer;
  final Uri apk;
  final int bytes;

  /// Wat er in deze uitgave zit, in gewone zinnen. Leeg als de release het niet meldt.
  ///
  /// Zie [watIsNieuw]: dit zijn de regels onder het kopje "Wat er nieuw is" in de release, en die
  /// worden door de bouwstraat gevuld met de onderwerpsregels van de commits sinds de vorige
  /// uitgave. Die zijn al in gewone taal geschreven, dus er valt niets te vertalen.
  final List<String> nieuw;

  const Uitgave({
    required this.versie,
    required this.buildnummer,
    required this.apk,
    required this.bytes,
    this.nieuw = const [],
  });

  String get naam =>
      buildnummer > 0 ? 'DebridMusic $versie (build $buildnummer)' : 'DebridMusic $versie';

  /// Waaronder "deze versie hoef ik niet" onthouden wordt.
  ///
  /// Een tekst en geen getal, want de twee platformen tellen iets anders: Android het buildnummer,
  /// Windows de versienaam. Vergelijken gebeurt op GELIJKHEID — sla je 11037 over en komt er 11040,
  /// dan hoor je dat te zien.
  String get sleutel => buildnummer > 0 ? 'build$buildnummer' : 'v$versie';

  /// Voor de knop: "40 MB" leest, "41943040 bytes" niet.
  String get grootte => bytes <= 0 ? '' : '${(bytes / (1000 * 1000)).toStringAsFixed(0)} MB';
}

/// Het kopje waaronder de bouwstraat schrijft wat er in een uitgave zit.
///
/// Eén afgesproken regel, aan beide kanten letterlijk zo. Er wordt niet geraden welk stuk van de
/// tekst "de veranderingen" zijn — dat gaat één keer goed en daarna niet meer.
const kopjeNieuw = '## Wat er nieuw is';

/// De regels onder [kopjeNieuw] in de beschrijving van een release.
///
/// **Waarom dit bestaat.** Het updatevenster zei alleen "DebridMusic 3.9.196 (build 11300) staat
/// klaar" — een nummer, en verder niets. Je moest maar aannemen dat het de moeite was, en je kon
/// achteraf niet nakijken wat er nou veranderd was. Nu staat er wat erin zit.
///
/// Leest tot het volgende kopje of tot het eind, gooit de opsommingsstreepjes en lege regels weg,
/// en houdt het bij hooguit [_hoogstensRegels] punten: een venster is geen changelog, en wie meer
/// wil kijkt op de releasepagina.
///
/// Een release die dit kopje niet heeft — alles van vóór deze wijziging — levert een lege lijst.
/// Dat is met opzet geen fout: het venster laat die regel dan gewoon weg.
const _hoogstensRegels = 8;

List<String> watIsNieuw(String? beschrijving) {
  final tekst = beschrijving ?? '';
  if (tekst.isEmpty) return const [];
  final regels = tekst.replaceAll('\r\n', '\n').split('\n');
  final start = regels.indexWhere((r) => r.trim().toLowerCase() == kopjeNieuw.toLowerCase());
  if (start < 0) return const [];
  final uit = <String>[];
  for (final ruw in regels.skip(start + 1)) {
    final r = ruw.trim();
    if (r.startsWith('#')) break; // het volgende kopje: hier houdt het op
    if (r.isEmpty) continue;
    // Het streepje eraf; het venster zet zijn eigen bolletje.
    final zonder = r.startsWith('- ') || r.startsWith('* ')
        ? r.substring(2).trim()
        : (r.startsWith('-') || r.startsWith('*') ? r.substring(1).trim() : r);
    if (zonder.isEmpty) continue;
    uit.add(zonder);
    if (uit.length >= _hoogstensRegels) break;
  }
  return uit;
}

/// Het buildnummer uit de tag van een release.
///
/// De tags zien eruit als `v3.9.74-build11037`; dat is wat `build-release.yml` schrijft. Alles wat
/// daar niet op lijkt levert null, en niet een gok: een verkeerd gelezen nummer is erger dan geen
/// nummer — dan biedt de app een "update" aan die het toestel vervolgens weigert.
int? buildnummerUit(String tag) {
  final m = RegExp(r'build(\d+)$').firstMatch(tag.trim());
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}

/// De versienaam uit dezelfde tag: `v3.9.74-build11037` → `3.9.74`.
String versieUit(String tag) {
  // Het EERSTE getal met punten, waar het ook staat — en niet "vanaf het begin, hooguit een v
  // ervoor". Dat laatste stond hier, en het brak op de tag die Windows draagt: `win-v3.9.141` gaf
  // `win-v3.9.141` terug, wat [vergelijkVersies] leest als 0.9.141. Nul is lager dan alles, dus de
  // pc bood nooit een update aan — stil, want er valt niets te zien aan een venster dat niet komt.
  //
  // Twee vormen moeten er allebei door: `v3.9.74-build11037` (Android) en `win-v3.9.141` (Windows).
  final m = RegExp(r'\d+(?:\.\d+)*').firstMatch(tag.trim());
  return m?.group(0) ?? tag.trim();
}

/// Welk bestand uit een release de APK is.
///
/// Een release kan meer dan één ding dragen. Op naam en op extensie, want een release met alleen
/// een `.txt` erbij mag niet als "geen APK" gelden en andersom mag een `.sha256`-bestand nooit als
/// installatiebestand doorgaan.
Map<String, dynamic>? apkUit(List<dynamic> assets) {
  for (final a in assets) {
    if (a is! Map<String, dynamic>) continue;
    final naam = (a['name'] as String?)?.toLowerCase() ?? '';
    if (naam.endsWith('.apk')) return a;
  }
  return null;
}

/// Is [daar] nieuwer dan wat hier draait?
///
/// Gelijk is niet nieuwer — anders biedt de app zichzelf aan, elke start opnieuw. En lager al
/// helemaal niet: dat gebeurt echt, want er zijn ooit APK's op de pc gebouwd met nummers die vóór
/// de teller van de bouwstraat lagen.
bool isNieuwer({required int hier, required int daar}) => daar > hier;

/// Twee versienamen vergelijken: negatief als [a] ouder is, 0 als ze gelijk zijn, positief als [a]
/// nieuwer is.
///
/// Per getal en niet als tekst, want als tekst is "3.9.9" nieuwer dan "3.9.141" — de 9 wint van de
/// 1. Precies het bereik waar deze app nu in zit, dus geen theoretisch geval.
int vergelijkVersies(String a, String b) {
  List<int> delen(String s) => [
        for (final d in s.trim().replaceAll(RegExp(r'^v'), '').split('.')) int.tryParse(d) ?? 0,
      ];
  final x = delen(a), y = delen(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final l = i < x.length ? x[i] : 0;
    final r = i < y.length ? y[i] : 0;
    if (l != r) return l - r;
  }
  return 0;
}

/// Welk bestand uit een release de Windows-installer is.
Map<String, dynamic>? installerUit(List<dynamic> assets) {
  for (final a in assets) {
    if (a is! Map<String, dynamic>) continue;
    final naam = (a['name'] as String?)?.toLowerCase() ?? '';
    // Op naam én extensie: in dezelfde release hangt ook een `.zip` voor de Mac, en die is geen
    // installer.
    if (naam.endsWith('.exe') && naam.contains('setup')) return a;
  }
  return null;
}

/// Welk bestand uit een release de Mac-zip is.
///
/// Dezelfde release draagt ook de Windows-installer en soms een APK, dus op naam én extensie. De
/// bouwstraat noemt hem `DebridMusic-macOS-3.9.152.zip`; `macos` staat er kleingeschreven in, maar
/// vergelijken gebeurt hier toch al op kleine letters.
Map<String, dynamic>? macZipUit(List<dynamic> assets) {
  for (final a in assets) {
    if (a is! Map<String, dynamic>) continue;
    final naam = (a['name'] as String?)?.toLowerCase() ?? '';
    if (naam.endsWith('.zip') && naam.contains('macos')) return a;
  }
  return null;
}

/// Het app-pakket waar een draaiende Mac-app in zit.
///
/// `Platform.resolvedExecutable` wijst naar `…/DebridMusic.app/Contents/MacOS/DebridMusic`; het
/// pakket is drie mappen daarboven. Null als het daar niet op lijkt — dan draait de app niet uit een
/// pakket (bijvoorbeeld `flutter run`) en valt er niets te ruilen. Liever niets doen dan gokken:
/// wat hierna volgt verplaatst mappen.
String? bundelUit(String uitvoerbaar) {
  final delen = uitvoerbaar.split('/');
  final i = delen.lastIndexWhere((d) => d.endsWith('.app'));
  if (i < 0) return null;
  // Precies `<pakket>/Contents/MacOS/<naam>`, en niet zomaar ergens een `.app` in het pad.
  if (delen.length != i + 4) return null;
  if (delen[i + 1] != 'Contents' || delen[i + 2] != 'MacOS') return null;
  return delen.sublist(0, i + 1).join('/');
}

/// Het scriptje dat de ruil doet nádat deze app is afgesloten.
///
/// Een app kan zichzelf niet vervangen terwijl hij draait: de map waar hij uit leest is precies de
/// map die weg moet. Dus wordt dit weggeschreven, losgekoppeld gestart, en dan sluit de app zichzelf
/// af. Het script wacht tot dat proces echt weg is en doet dan pas iets.
///
/// De oude versie wordt VERPLAATST en niet verwijderd, en pas weggegooid als de nieuwe staat. Gaat
/// het uitpakken mis, dan wordt de oude teruggezet en opgestart. Het ergste wat er dan gebeurd is,
/// is dat je dezelfde versie weer voor je hebt.
String ruilScript({
  required int pid,
  required String pakket,
  required String nieuw,
  required String terzijde,
  String zip = '',
}) {
  // Enkele aanhalingstekens in een pad zouden het script breken. Ze horen niet in een appnaam, maar
  // het pad eromheen is van de gebruiker en die mag alles heten.
  String q(String p) => "'${p.replaceAll("'", r"'\''")}'";
  return '''#!/bin/sh
# Geschreven door DebridMusic om zichzelf te vervangen. Zie updater.dart.
PID=$pid
PAKKET=${q(pakket)}
NIEUW=${q(nieuw)}
TERZIJDE=${q(terzijde)}
ZIP=${q(zip)}

# Wachten tot de app echt weg is. Twintig seconden is ruim; daarna is er iets anders aan de hand en
# is niets doen beter dan een half vervangen pakket.
n=0
while kill -0 "\$PID" 2>/dev/null; do
  n=\$((n + 1))
  if [ "\$n" -gt 200 ]; then exit 1; fi
  sleep 0.1
done

rm -rf "\$TERZIJDE"
mv "\$PAKKET" "\$TERZIJDE" || exit 1

if ditto "\$NIEUW" "\$PAKKET"; then
  xattr -dr com.apple.quarantine "\$PAKKET" 2>/dev/null
  rm -rf "\$TERZIJDE"
else
  rm -rf "\$PAKKET"
  mv "\$TERZIJDE" "\$PAKKET"
fi

open "\$PAKKET"

# En de eigen rommel weg. Het uitgepakte pakket is een TWEEDE .app met dezelfde bundle-id, en zolang
# die ergens staat kan LaunchServices hem registreren en er later naartoe wijzen -- dan opent de Dock
# een kopie in een tijdelijke map in plaats van de app in /Applications. Gemeten op 24-08-2026: een
# dangling verwijzing naar zo'n tweede bundel leverde een proces zonder venster op.
# Niet het script zelf: `sh` leest een script stapsgewijs, en wie de grond onder zijn eigen voeten
# weghaalt terwijl er nog `rm -rf`-regels boven staan, wil dat niet halverwege ontdekken. Het is een
# paar honderd bytes in een tijdelijke map; die veegt macOS zelf weg.
rm -rf "\$NIEUW" "\$ZIP"
''';
}

/// Het buildnummer van de app die nu draait.
Future<int> huidigBuildnummer() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  } catch (_) {
    return 0;
  }
}

/// Waar "deze versie hoef ik niet" bewaard wordt.
///
/// Eén regel JSON naast de rest van de instellingen. Bewust niet in `AppSettings`: dat bestand
/// reist mee met je account naar een nieuwe installatie, en "overgeslagen" is een keuze over dít
/// toestel — op een ander toestel staat een andere versie.
File get _overslaanBestand => File('$appDir${Platform.pathSeparator}updater.json');

Future<String> _overgeslagen() async {
  try {
    final j = jsonDecode(await _overslaanBestand.readAsString());
    if (j is Map && j['overgeslagen'] is String) return j['overgeslagen'] as String;
  } catch (_) {/* niets overgeslagen, of onleesbaar — dan gewoon aanbieden */}
  return '';
}

Future<void> _slaOver(String sleutel) async {
  try {
    await _overslaanBestand.writeAsString(jsonEncode({'overgeslagen': sleutel}));
  } catch (_) {/* niet kunnen onthouden is hinderlijk, geen fout */}
}

/// Kijkt, haalt binnen, en geeft het aan Android door.
class Updater {
  const Updater();

  /// Android, Windows en de Mac. Alleen de iPad valt erbuiten: die krijgt zijn versies via
  /// TestFlight, en daar mag geen app zichzelf vervangen.
  ///
  /// De Mac stond hier eerst ook buiten, met als reden dat er alleen een zip gepubliceerd wordt en
  /// er dus niets te installeren viel. Dat klopte voor de helft: er is inderdaad geen installer,
  /// maar een app-pakket ruilen is een verplaatsing — zie [ruilScript].
  static bool get kanHier => Platform.isAndroid || Platform.isWindows || Platform.isMacOS;

  /// Wat er klaarstaat, of null als dat niets nieuws is.
  ///
  /// Stil bij elke storing. Dit draait bij het opstarten, en "geen internet" of "GitHub is even
  /// traag" is geen bericht waard: dan is er simpelweg geen update te melden.
  Future<Uitgave?> zoek({bool negeerOvergeslagen = false}) async {
    if (!kanHier) return null;
    try {
      final repo = Platform.isAndroid ? _releasesRepo : _bronRepo;
      final r = await http.get(
        Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;

      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map<String, dynamic>) return null;

      final tag = j['tag_name'] as String? ?? '';
      final assets = (j['assets'] as List?) ?? const [];
      final nieuw = watIsNieuw(j['body'] as String?);
      final uitgave = Platform.isAndroid
          ? _android(tag, assets, nieuw)
          : Platform.isMacOS
              ? _mac(tag, assets, nieuw)
              : _windows(tag, assets, nieuw);
      if (uitgave == null) return null;

      if (!await _isNieuwerDanHier(uitgave)) return null;
      if (!negeerOvergeslagen && await _overgeslagen() == uitgave.sleutel) return null;
      return uitgave;
    } catch (_) {
      return null;
    }
  }

  Uitgave? _android(String tag, List<dynamic> assets, List<String> nieuw) {
    final nummer = buildnummerUit(tag);
    if (nummer == null) return null;
    final asset = apkUit(assets);
    final url = asset?['browser_download_url'] as String?;
    if (url == null || url.isEmpty) return null;
    return Uitgave(
      versie: versieUit(tag),
      buildnummer: nummer,
      apk: Uri.parse(url),
      bytes: (asset!['size'] as num?)?.toInt() ?? 0,
      nieuw: nieuw,
    );
  }

  Uitgave? _windows(String tag, List<dynamic> assets, List<String> nieuw) {
    final asset = installerUit(assets);
    final url = asset?['browser_download_url'] as String?;
    if (url == null || url.isEmpty) return null;
    return Uitgave(
      versie: versieUit(tag),
      // Windows kent geen buildnummer dat ergens op slaat: de versienaam ÍS daar het getal dat
      // omhoog gaat, want de installer krijgt hem uit de tag. Nul betekent hier "niet van
      // toepassing"; [_isNieuwerDanHier] en [Uitgave.sleutel] kijken daarop en nemen dan de naam.
      buildnummer: 0,
      apk: Uri.parse(url),
      bytes: (asset!['size'] as num?)?.toInt() ?? 0,
      nieuw: nieuw,
    );
  }

  /// Dezelfde release als Windows, ander bestand.
  ///
  /// Buildnummer nul, net als daar: de Mac-zip hangt aan de `win-v`-tag en het is de VERSIENAAM die
  /// per release omhoog gaat. `CFBundleVersion` telt wel mee in het pakket, maar dat getal komt uit
  /// het runnummer van de bouwstraat en zegt niets over oud of nieuw ten opzichte van een zip die
  /// je met de hand hebt uitgepakt.
  Uitgave? _mac(String tag, List<dynamic> assets, List<String> nieuw) {
    final asset = macZipUit(assets);
    final url = asset?['browser_download_url'] as String?;
    if (url == null || url.isEmpty) return null;
    return Uitgave(
      versie: versieUit(tag),
      buildnummer: 0,
      apk: Uri.parse(url),
      bytes: (asset!['size'] as num?)?.toInt() ?? 0,
      nieuw: nieuw,
    );
  }

  Future<bool> _isNieuwerDanHier(Uitgave u) async {
    if (Platform.isAndroid) {
      return isNieuwer(hier: await huidigBuildnummer(), daar: u.buildnummer);
    }
    try {
      final info = await PackageInfo.fromPlatform();
      return vergelijkVersies(u.versie, info.version) > 0;
    } catch (_) {
      return false;
    }
  }

  /// Deze versie niet meer aanbieden.
  Future<void> sla(Uitgave u) => _slaOver(u.sleutel);

  /// Haalt de APK binnen en meldt onderweg hoever hij is.
  ///
  /// In de cachemap en niet bij de instellingen: dit is veertig megabyte die na het installeren
  /// nergens meer voor dient, en een cachemap is precies de map die Android zelf mag opruimen als
  /// het toestel vol raakt.
  Future<File> haal(Uitgave u, {void Function(double)? voortgang}) async {
    final tijdelijk = await getTemporaryDirectory();
    final map = Directory('${tijdelijk.path}${Platform.pathSeparator}update');
    await map.create(recursive: true);
    // Elk platform zijn eigen naam, want alleen Android krijgt hier een APK.
    //
    // Op de Mac is het een zip die zo meteen door `ditto` gaat; die kijkt naar de inhoud en niet
    // naar de naam, maar een bestand `.apk` noemen dat geen APK is leest verkeerd in elke logregel.
    //
    // Op Windows is het een Inno-installer, en daar is de naam niet alleen cosmetisch. Wat er op
    // 31-08-2026 op schijf stond was `DebridMusic-0.apk` — verkeerde extensie én buildnummer nul,
    // want dat veld hoort bij de Android-uitgave. `Process.start` voert zo'n bestand nog wel uit
    // (CreateProcess kijkt naar de PE-kop, niet naar de extensie), maar de bijwerkpoging sloot die
    // avond de app af zonder iets te installeren; hetzelfde bestand als `.exe` draaien lukte meteen.
    // Een installer die zijn eigen naam niet draagt is bovendien niet te herkennen in %TEMP%, en dat
    // is precies waar je kijkt als een update halverwege blijft steken.
    final doel = File(Platform.isMacOS
        ? '${map.path}${Platform.pathSeparator}DebridMusic-${u.versie}.zip'
        : Platform.isWindows
            ? '${map.path}${Platform.pathSeparator}DebridMusic-Setup-${u.versie}.exe'
            : '${map.path}${Platform.pathSeparator}DebridMusic-${u.buildnummer}.apk');

    // Een half binnengehaald bestand van een vorige poging is geen APK maar ziet er wel zo uit.
    if (await doel.exists()) await doel.delete();

    final client = http.Client();
    try {
      final r = await client.send(http.Request('GET', u.apk));
      if (r.statusCode != 200) {
        throw HttpException('De download gaf ${r.statusCode}', uri: u.apk);
      }
      final totaal = r.contentLength ?? u.bytes;
      var binnen = 0;
      final uit = doel.openWrite();
      await for (final brok in r.stream) {
        uit.add(brok);
        binnen += brok.length;
        if (totaal > 0) voortgang?.call(binnen / totaal);
      }
      await uit.close();

      // Wat er staat moet ook zijn wat er beloofd was. Een afgebroken verbinding levert een kortere
      // APK op die het installatiescherm met "app niet geïnstalleerd" afwijst — en dan lijkt de
      // update stuk terwijl de download het was.
      final geschreven = await doel.length();
      if (totaal > 0 && geschreven != totaal) {
        await doel.delete();
        throw HttpException('Onvolledig binnengehaald ($geschreven van $totaal bytes)', uri: u.apk);
      }
      return doel;
    } finally {
      client.close();
    }
  }

  /// Mag deze app een pakket installeren?
  ///
  /// Sinds Android 8 is dat een recht per app en niet meer één schakelaar voor het hele toestel.
  /// Zonder dit vooraf te vragen opent het installatiescherm en sluit meteen weer, zonder uitleg.
  /// Op Windows bestaat die vraag niet: daar start je gewoon een installer.
  Future<bool> magInstalleren() async {
    // Alleen Android kent dit recht. Op een pc en een Mac start je gewoon iets; kan dat niet
    // — omdat het pakket niet van jou is, bijvoorbeeld — dan zegt [installeer] dat met zoveel
    // woorden. Hier `false` teruggeven zou het Android-scherm openen dat daar niet bestaat.
    if (Platform.isWindows || Platform.isMacOS) return true;
    if (!kanHier) return false;
    try {
      return await _kanaal.invokeMethod<bool>('magInstalleren') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opent het scherm waar dat recht gegeven wordt.
  Future<void> vraagToestemming() async {
    if (!kanHier) return;
    try {
      await _kanaal.invokeMethod('vraagToestemming');
    } catch (_) {/* geen scherm om te openen; de installatie hieronder zegt het dan zelf */}
  }

  /// Geeft het binnengehaalde bestand aan het systeem door.
  ///
  /// Op Android opent het installatiescherm van het toestel; jij tikt daar op Installeren.
  ///
  /// Op Windows gaat het in één keer door, want dat is wat je van een pc-app verwacht: de installer
  /// draait stil, sluit deze app zelf af omdat hij de bestanden vervangt, en start hem daarna weer
  /// op. Die laatste stap is niet vanzelfsprekend — zie het commentaar bij de vlaggen.
  Future<void> installeer(File bestand) async {
    if (Platform.isMacOS) return _installeerMac(bestand);
    if (Platform.isWindows) {
      await Process.start(
        bestand.path,
        innoVlaggen,
        mode: ProcessStartMode.detached,
      );
      return;
    }
    await _kanaal.invokeMethod('installeer', {'pad': bestand.path});
  }

  /// De vlaggen waarmee de Windows-installer draait.
  ///
  /// Apart en openbaar om dezelfde reden als `Aria2.argumenten` in `aria2.dart`: elk van deze
  /// vlaggen heeft een reden die je nergens meer terugziet zodra het werkt, en alleen zó valt er een
  /// test op te zetten.
  static const List<String> innoVlaggen = [
          // Stil, en zonder foutvensters waar niemand bij staat.
          '/SILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
          // Deze twee horen bij elkaar en zijn de kern: CLOSEAPPLICATIONS laat Inno déze app netjes
          // afsluiten (anders staan de bestanden op slot en breekt de installatie halverwege af),
          // en RESTARTAPPLICATIONS start hem daarna weer op.
          '/CLOSEAPPLICATIONS',
          '/RESTARTAPPLICATIONS',
          // EN DE DERDE, WANT ZONDER HEM DEED HET BIJWERKEN NIETS.
          //
          // Naast de app staat `aria2c.exe` in dezelfde map, en die draait zodra er ooit een
          // torrent is gehaald. Inno krijgt zo'n proces niet dicht met een venstermelding -- het
          // heeft er geen -- en meldt dan:
          //
          //     "Setup kon niet alle programma's automatisch afsluiten."
          //
          // Dat is een Abort/Retry/Ignore-vraag, en met `/SUPPRESSMSGBOXES` erbij kiest Inno
          // zwijgend Abort. Gemeten op 31-08-2026 om 00:09: "User canceled the installation
          // process. Rolling back changes." De app was toen al afgesloten en kwam niet terug, en de
          // versie op schijf bleef staan waar hij stond. Van buiten ziet dat eruit als "de update
          // heeft mijn app kapotgemaakt".
          //
          // Met deze vlag beëindigt Inno wat hij niet netjes dicht krijgt. Voor aria2 is dat geen
          // verlies: hij laat zijn `.aria2`-administratie staan en pakt na de herstart op waar hij
          // gebleven was.
          '/FORCECLOSEAPPLICATIONS',
  ];

  /// De Mac: pakket uitpakken, controleren, en de ruil aan een scriptje overlaten.
  ///
  /// Alles wat mis kan gaan wordt hiervóór gecontroleerd, want zodra het script loopt is deze app
  /// weg en staat er niemand meer bij. Elke worp hier komt als melding op het scherm; zie
  /// `_haalEnInstalleer`.
  Future<void> _installeerMac(File zip) async {
    final pakket = bundelUit(Platform.resolvedExecutable);
    if (pakket == null) {
      throw const FileSystemException(
          'Deze app draait niet uit een .app-pakket, dus er valt niets te vervangen.');
    }

    // Kunnen we hier überhaupt schrijven? Staat de app in /Applications en is hij ooit door een
    // beheerder neergezet, dan mag jij hem niet verplaatsen. Dat nu weten is een melding; dat
    // straks pas merken is een halve installatie zonder app.
    final map = Directory(pakket).parent;
    try {
      final proef = File('${map.path}${Platform.pathSeparator}.debridmusic-schrijftest');
      await proef.writeAsString('x');
      await proef.delete();
    } catch (_) {
      throw FileSystemException('Geen schrijfrechten in ${map.path}', pakket);
    }

    final uit = Directory('${zip.parent.path}${Platform.pathSeparator}uitgepakt');
    if (await uit.exists()) await uit.delete(recursive: true);
    await uit.create(recursive: true);

    // `ditto` en niet `unzip`: die eerste hoort bij macOS en houdt rechten, symlinks en de
    // handtekening heel. Met `unzip` komt het pakket er als losse bestanden uit en weigert Gatekeeper
    // het te openen.
    final uitpakken = await Process.run('/usr/bin/ditto', ['-x', '-k', zip.path, uit.path]);
    if (uitpakken.exitCode != 0) {
      throw FileSystemException('Uitpakken mislukte: ${uitpakken.stderr}', zip.path);
    }

    final nieuw = await uit
        .list()
        .where((e) => e is Directory && e.path.endsWith('.app'))
        .cast<Directory>()
        .firstWhere((_) => true, orElse: () => Directory(''));
    if (nieuw.path.isEmpty) {
      throw FileSystemException('Geen .app in de zip', zip.path);
    }
    // Een pakket zonder uitvoerbaar bestand is geen pakket. Zonder deze controle zou het script de
    // werkende versie opzijzetten en er iets kapots voor in de plaats zetten.
    if (!await File('${nieuw.path}/Contents/MacOS/${_naamUit(pakket)}').exists()) {
      throw FileSystemException('Het uitgepakte pakket mist zijn uitvoerbare bestand', nieuw.path);
    }

    final script = File('${zip.parent.path}${Platform.pathSeparator}ruil.sh');
    await script.writeAsString(ruilScript(
      pid: pid,
      pakket: pakket,
      nieuw: nieuw.path,
      terzijde: '${zip.parent.path}${Platform.pathSeparator}vorige.app',
      zip: zip.path,
    ));

    await Process.start('/bin/sh', [script.path], mode: ProcessStartMode.detached);
    // En dan uit de weg. Het script wacht tot dit proces echt weg is voordat het iets verplaatst,
    // dus dit is geen wedloop maar het startsein.
    exit(0);
  }

  /// `…/DebridMusic.app` → `DebridMusic`.
  String _naamUit(String pakket) =>
      pakket.split('/').last.replaceAll(RegExp(r'\.app$'), '');
}

/// Wat er na het binnenhalen gebeurt, per platform.
///
/// Stond hier als één zin over "het installatiescherm van je toestel". Dat is precies wat Android
/// doet en precies wat de andere twee niet doen: op een pc loopt de installer zichzelf, en op een
/// Mac wordt het pakket geruild terwijl de app even weg is. Dat laatste hoort erbij te staan, want
/// een app die uit zichzelf afsluit en terugkomt is schrikken als je het niet ziet aankomen.
String watErGebeurt() {
  if (Platform.isMacOS) {
    return 'Daarna sluit DebridMusic zichzelf af, vervangt zich, en start opnieuw op.';
  }
  if (Platform.isWindows) return 'Daarna installeert hij zichzelf en start opnieuw op.';
  return 'Daarna opent het installatiescherm van je toestel.';
}

/// Het bericht in de app: één keer vragen, en dan doen.
///
/// Bewust géén stille achtergrondinstallatie. Een app die zichzelf vervangt terwijl je muziek
/// luistert, is een app die midden in een nummer verdwijnt.
Future<void> toonUpdate(BuildContext context, Uitgave u, {Updater updater = const Updater()}) async {
  final wil = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      backgroundColor: kPaneel,
      title: const Text('Nieuwe versie'),
      // Meebewegend en scrollbaar: er staan nu regels in die je niet vooraf kunt afmeten, en een
      // venster dat te hoog wordt voor een telefoon toont zijn knoppen niet meer.
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${u.naam} staat klaar.'),
              // WAT ERIN ZIT, en niet alleen welk nummer het is. Er stond een versienummer en verder
              // niets, dus je moest maar aannemen dat het de moeite was. Deze regels komen uit de
              // release zelf — zie [watIsNieuw] — en zijn de onderwerpsregels van wat er gedaan is.
              if (u.nieuw.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Wat er nieuw is',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 4),
                for (final regel in u.nieuw)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(fontSize: 13, height: 1.35)),
                        Expanded(
                          child: Text(regel, style: const TextStyle(fontSize: 13, height: 1.35)),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              Text(
                u.grootte.isEmpty ? watErGebeurt() : 'Hij is ${u.grootte} groot. ${watErGebeurt()}',
                style: const TextStyle(color: Color(0xFF8A90A6), fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
      actions: [
        // "Overslaan" is niet hetzelfde als "Later": deze versie wordt niet meer aangeboden, de
        // volgende wel. Zonder dat onderscheid is de enige manier om van het bericht af te komen
        // het uitvoeren ervan.
        TextButton(onPressed: () => Navigator.pop(d, null), child: const Text('Later')),
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Overslaan')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Bijwerken')),
      ],
    ),
  );

  if (wil == null) return;
  if (wil == false) {
    await updater.sla(u);
    return;
  }
  if (!context.mounted) return;

  if (!await updater.magInstalleren()) {
    if (!context.mounted) return;
    final ga = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: kPaneel,
        title: const Text('Eén keer toestemming'),
        content: const Text(
            'Android laat een app alleen een andere app installeren als je dat per app toestaat. '
            'Zet "Uit deze bron toestaan" aan en kom terug; daarna vraagt hij het nooit meer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuleren')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Instellingen')),
        ],
      ),
    );
    if (ga == true) await updater.vraagToestemming();
    return;
  }

  if (!context.mounted) return;
  await _haalEnInstalleer(context, u, updater);
}

/// De voortgangsbalk, en wat erna komt.
Future<void> _haalEnInstalleer(BuildContext context, Uitgave u, Updater updater) async {
  final voortgang = ValueNotifier<double>(0);
  var afgebroken = false;

  // barrierDismissible staat uit: buiten het venster tikken zou het sluiten terwijl de download
  // doorloopt, en dan gebeurt er straks iets waar niets meer bij staat.
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (d) => AlertDialog(
      backgroundColor: kPaneel,
      title: const Text('Bezig met binnenhalen'),
      content: ValueListenableBuilder<double>(
        valueListenable: voortgang,
        builder: (_, p, __) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: p == 0 ? null : p),
            const SizedBox(height: 10),
            Text('${(p * 100).clamp(0, 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Color(0xFF8A90A6), fontSize: 12.5)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            afgebroken = true;
            Navigator.pop(d);
          },
          child: const Text('Annuleren'),
        ),
      ],
    ),
  ));

  final boodschapper = ScaffoldMessenger.maybeOf(context);
  final navigator = Navigator.of(context);
  try {
    final apk = await updater.haal(u, voortgang: (p) => voortgang.value = p);
    if (afgebroken) {
      await apk.delete().catchError((_) => apk);
      return;
    }
    navigator.pop(); // de voortgangsbalk weg vóór het installatiescherm van Android opent
    await updater.installeer(apk);
  } catch (e) {
    if (afgebroken) return;
    navigator.pop();
    // Wél een melding, anders dan bij het zoeken: hier heb JIJ op een knop gedrukt en moet er iets
    // gebeuren. Stilte zou lezen als een knop die niets doet.
    boodschapper?.showSnackBar(
      SnackBar(content: Text('Bijwerken lukte niet: $e'), duration: const Duration(seconds: 6)),
    );
  } finally {
    voortgang.dispose();
  }
}

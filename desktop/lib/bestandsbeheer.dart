/// Een bestand aanwijzen in de bestandsbeheerder van het besturingssysteem.
///
/// **Waarom dit bestaat.** De app weet precies waar elk nummer staat — dat pad staat in `Track.path`
/// en wordt overal gebruikt om af te spelen, te taggen en te verplaatsen. Maar er was geen enkele
/// weg van "dit nummer" naar "dat bestand": wie het in de Verkenner wilde bekijken, moest de map met
/// de hand terugzoeken.
///
/// **Aanwijzen, niet openen.** `explorer.exe pad` opent het bestand met de standaardtoepassing —
/// dat start een tweede muziekspeler naast deze. `/select,` opent de map mét het bestand
/// geselecteerd, en dat is wat er gevraagd wordt.
///
/// **En daar zit op Windows precies de val.** De eerste versie hiervan deed
/// `Process.run('explorer.exe', ['/select,$pad'])`, wat er in Dart onberispelijk uitziet en op een
/// echte machine de verkeerde map opent. De reden staat een laag dieper: Windows kent geen lijst van
/// argumenten, alleen één opdrachtregel, en Dart bouwt die zelf op — een argument met een spatie
/// erin wordt in aanhalingstekens gezet. Voor `D:\Flac music 2024\...` levert dat
/// `explorer.exe "/select,D:\Flac music 2024\..."`, met de vlag binnen de aanhalingstekens. En
/// explorer leest zijn opdrachtregel niet op de gewone manier: hij herkent `/select,` alleen als het
/// er káál staat. Wat hij hier ziet is één pad dat niet bestaat, en dan opent hij zijn standaardmap.
///
/// Vandaar het batchbestandje. Dat wordt door `cmd` als tekst gelezen, dus de regel komt precies zo
/// bij explorer aan als wanneer je hem zelf zou typen: vlag buiten de aanhalingstekens, pad erbinnen.
/// Dezelfde vorm die de bijwerker op de Mac al gebruikt om een pakket te ruilen.
///
/// **De opdrachten zijn pure functies**, en dat is met opzet: dit zijn details die je één keer
/// opzoekt en daarna nooit meer nakijkt, en ze zijn geen van alle na te kijken zonder de machine in
/// kwestie. `test/bestandsbeheer_test.dart` legt ze vast — inclusief de fout hierboven, zodat
/// niemand er per ongeluk naar terugkeert.
library;

import 'dart:io';

import 'paths.dart';

/// Kan er op dit toestel überhaupt een bestandsbeheerder geopend worden?
///
/// Alleen op een pc. Op Android en iOS is er geen bestandsbeheerder om naartoe te wijzen, en op een
/// televisie is er geen muis om ermee te doen wat je van plan was.
bool get kanBestandTonen => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Hoe deze bestandsbeheerder heet, zodat het menu de naam gebruikt die op het scherm staat.
String get bestandsbeheerNaam => Platform.isWindows
    ? 'Verkenner'
    : Platform.isMacOS
        ? 'Finder'
        : 'de bestandsbeheerder';

/// De regel die in het batchbestand komt te staan.
///
/// Precies wat je in een opdrachtvenster zou typen. Twee dingen zijn hier niet vrijblijvend:
///
///  * `/select,` staat BUITEN de aanhalingstekens en het pad erbinnen. Andersom herkent explorer de
///    vlag niet en opent hij zijn standaardmap — zie de kop van dit bestand.
///  * Een `%` in een bestandsnaam wordt verdubbeld. `cmd` leest een batchbestand als tekst en zou
///    `%iets%` als een omgevingsvariabele uitvouwen; wat er niet is verdwijnt dan spoorloos uit het
///    pad. Zeldzaam in muziekbestanden, maar het is één teken en het scheelt een raadsel.
///
/// De andere tekens die `cmd` bijzonder vindt — `&`, `|`, `^`, `<`, `>` — zijn dat niet binnen
/// aanhalingstekens, dus die hoeven niets.
String windowsBatchRegel(String pad) =>
    'explorer.exe /select,"${pad.replaceAll('%', '%%')}"';

/// De opdracht die [pad] aanwijst op een Mac of onder Linux, of null waar dat niet kan.
///
/// Windows staat hier NIET bij, en dat is de kern van de reparatie: daar kan het niet met een lijst
/// argumenten. Zie [windowsBatchRegel].
List<String>? onthulOpdracht(String pad) => onthulOpdrachtVoor(pad, os: Platform.operatingSystem);

/// Dezelfde opdracht, met het besturingssysteem als antwoord in plaats van als omgeving.
///
/// **Waarom [os] een parameter is.** Met `Platform` er rechtstreeks in kan een toets alleen iets
/// zeggen over de machine waar hij toevallig op draait, en dat is hier de Linux-bouwmachine:
/// precies het enige van de drie dat niemand gebruikt.
List<String>? onthulOpdrachtVoor(String pad, {required String os}) {
  switch (os) {
    case 'macos':
      return ['open', '-R', pad];
    case 'linux':
      // De vrijedesktop-afspraak die elke moderne bestandsbeheerder kent. Lukt dat niet, dan opent
      // [toonInBestandsbeheer] de map zelf — zie daar.
      return [
        'dbus-send',
        '--session',
        '--dest=org.freedesktop.FileManager1',
        '--type=method_call',
        '/org/freedesktop/FileManager1',
        'org.freedesktop.FileManager1.ShowItems',
        'array:string:file://$pad',
        'string:',
      ];
    default:
      // Windows incluis: die loopt over [windowsBatchRegel] en niet over een argumentenlijst.
      return null;
  }
}

/// Wijs [pad] aan in de bestandsbeheerder. Geeft null terug als het lukte, anders de uitleg.
Future<String?> toonInBestandsbeheer(String pad) async {
  if (!kanBestandTonen) return 'Dit kan alleen op een pc.';
  final f = File(pad);
  if (!f.existsSync()) {
    // Dit is de gewone uitkomst op een toestel dat de bibliotheek van de pc leest: het pad klopt,
    // maar het klopt op een andere machine. Dat hoort er te staan in plaats van een lege mislukking.
    return 'Dat bestand staat hier niet: $pad';
  }
  if (Platform.isWindows) return _windowsOnthul(f);
  final opdracht = onthulOpdracht(pad);
  if (opdracht == null) return 'Dit kan alleen op een pc.';
  try {
    final r = await Process.run(opdracht.first, opdracht.sublist(1));
    if (Platform.isLinux && r.exitCode != 0) {
      // Geen bestandsbeheerder die de afspraak kent. Dan de MAP openen — dat is minder dan gevraagd,
      // maar het brengt je wel waar je wilde zijn.
      final map = f.parent.path;
      final t = await Process.run('xdg-open', [map]);
      if (t.exitCode != 0) return 'Geen bestandsbeheerder gevonden om $map mee te openen.';
    }
    return null;
  } catch (e) {
    return 'Kon $bestandsbeheerNaam niet starten: $e';
  }
}

/// Windows, via een batchbestandje. Zie de kop van dit bestand voor waarom dat geen omweg is.
///
/// Eén vaste naam die elke keer overschreven wordt, dus er groeit niets aan. En losgekoppeld
/// gestart: de afloopcode van explorer zegt al twintig jaar niets — hij geeft vrijwel altijd 1 terug
/// terwijl het venster gewoon opent — dus erop wachten levert alleen een verkeerde melding op.
Future<String?> _windowsOnthul(File f) async {
  try {
    final bat = File('$appDir${Platform.pathSeparator}toon-in-verkenner.bat');
    await bat.writeAsString('@echo off\r\n${windowsBatchRegel(f.path)}\r\n');
    await Process.start('cmd.exe', ['/c', bat.path], mode: ProcessStartMode.detached);
    return null;
  } catch (_) {
    // Terugval: dan maar de MAP, zonder het bestand aan te wijzen. Dat is minder dan gevraagd, maar
    // het is wel de goede map — en één kaal pad als enig argument gaat langs de gewone weg wél goed,
    // want dan staat er geen vlag bij die buiten de aanhalingstekens moet blijven.
    try {
      await Process.start('explorer.exe', [f.parent.path], mode: ProcessStartMode.detached);
      return null;
    } catch (e) {
      return 'Kon de Verkenner niet starten: $e';
    }
  }
}

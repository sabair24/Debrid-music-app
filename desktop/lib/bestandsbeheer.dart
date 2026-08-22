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
/// **De opdracht is een pure functie**, en dat is met opzet: de drie besturingssystemen doen dit
/// alle drie anders, en elk van die drie is een detail dat je één keer opzoekt en daarna nooit meer
/// nakijkt. `test/bestandsbeheer_test.dart` legt ze vast, zodat een verschuiving hier opvalt zonder
/// dat er drie machines aan te pas komen.
library;

import 'dart:io';

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

/// De opdracht die [pad] aanwijst, of null op een toestel zonder bestandsbeheerder.
List<String>? onthulOpdracht(String pad) => onthulOpdrachtVoor(pad, os: Platform.operatingSystem);

/// Dezelfde opdracht, met het besturingssysteem als antwoord in plaats van als omgeving.
///
/// **Waarom [os] een parameter is.** Deze drie regels zijn precies het soort ding dat je één keer
/// opzoekt en daarna nooit meer nakijkt — en ze zijn geen van drieën vanzelfsprekend. Met `Platform`
/// er rechtstreeks in kan een toets alleen iets zeggen over de machine waar hij toevallig op draait,
/// en dat is hier de Linux-bouwmachine: precies het enige van de drie dat niemand gebruikt. Zo
/// liggen alle drie vast, waar dan ook.
List<String>? onthulOpdrachtVoor(String pad, {required String os}) {
  switch (os) {
    case 'windows':
      // Géén aanhalingstekens om het pad heen. `Process.run` geeft de argumenten door zonder shell,
      // dus aanhalingstekens zouden onderdeel van de bestandsnaam worden. En `/select,` hoort aan
      // het pad vást te zitten: explorer leest het als één argument, en met een spatie ertussen
      // negeert hij de vlag en OPENT hij het bestand — dat wil zeggen: hij start er een tweede
      // muziekspeler mee naast deze.
      return ['explorer.exe', '/select,$pad'];
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
      return null;
  }
}

/// Wijs [pad] aan in de bestandsbeheerder. Geeft null terug als het lukte, anders de uitleg.
///
/// **Waarom de afloopcode van Windows genegeerd wordt.** `explorer.exe /select,` geeft vrijwel
/// altijd 1 terug, óók als het venster gewoon opent — een bekende eigenaardigheid die al twintig
/// jaar bestaat. Daarop afgaan zou betekenen dat de app elke keer "het lukte niet" meldt terwijl de
/// Verkenner voor je neus staat. Er wordt dus alleen gekeken of het programma te starten viel.
Future<String?> toonInBestandsbeheer(String pad) async {
  if (!kanBestandTonen) return 'Dit kan alleen op een pc.';
  final f = File(pad);
  if (!f.existsSync()) {
    // Dit is de gewone uitkomst op een toestel dat de bibliotheek van de pc leest: het pad klopt,
    // maar het klopt op een andere machine. Dat hoort er te staan in plaats van een lege mislukking.
    return 'Dat bestand staat hier niet: $pad';
  }
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
    return 'Kon ${bestandsbeheerNaam} niet starten: $e';
  }
}

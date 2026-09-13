/// Eén keer misgrijpen mag niet de hele avond kosten.
///
/// **Waarom dit bestaat.** Gemeld op 02-09-2026: twee nummers van Linkin Park wilden niet
/// downloaden. Er stond geen enkel spoor van in de logboeken — en dat bleek het spoor te zijn. In
/// `aria2.log` sprong de tijd van 01-09 15:56 rechtstreeks naar 02-09 19:11:
///
///     2026-09-01 15:56:21  Download complete: ...
///     2026-09-02 19:11:32  aria2 gestart op poort 52133      <- de herstart erna
///
/// Zes uur sessie ertussen waarin aria2 geen enkele keer is gestart. Na een herstart van de app
/// lukte exact dezelfde download meteen.
///
/// Twee dingen maakten dat mogelijk, en die worden hier allebei vastgezet:
///
///   1. `_gezocht` werd op true gezet vóór het zoeken en bleef staan, ook bij een misser. Het veld
///      is statisch, dus die ene misser gold voor de rest van de looptijd van de app.
///   2. `start()` gaf bij een niet-gevonden pad kaal `false` terug, zonder één regel logboek.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/aria2.dart';
import 'package:debridmusic/paths.dart';

/// Staat er op DEZE machine een aria2c in de systeempaden?
///
/// **Waarom dat hier uitmaakt.** De twee toetsen hieronder gaan over wat er gebeurt als er NIETS te
/// vinden is. Op Windows klopt die aanname altijd. Op de ubuntu-machine van de bouwstraat niet:
/// `aria2` zit in het standaardbeeld van GitHub, en `Aria2.pad` kijkt op Linux ook in `/usr/bin`.
/// Ze stonden daar dus rood - twee van de zes die van 12-09-2026 tot 13-09-2026 tien uitleveringen
/// lang de APK tegenhielden - terwijl ze hier groen waren.
///
/// Waar niets te missen valt, valt deze storing niet na te spelen. Dan zegt de toets dat, en toetst
/// hij wat er daar wel geldt - in plaats van iets te beweren dat op die machine niet waar is.
/// Vindt DEZE machine een aria2c staan?
///
/// Niet op vaste paden kijken maar het gedrag zelf vragen: `Aria2.pad` loopt op Linux ook
/// `/usr/bin`, `/usr/local/bin` en `/opt/homebrew/bin` af en valt daarna terug op PATH, en welke van
/// die vijf het wordt doet er niet toe - alleen of er iets uit komt.
bool _vindtEenAria2() {
  Aria2.resetLookup();
  final gevonden = Aria2().pad != null;
  Aria2.resetLookup();
  return gevonden;
}

void main() {
  late Directory map;

  setUp(() {
    map = Directory.systemTemp.createTempSync('dm_zoek_');
    setAppDirForTest(map.path);
    Aria2.resetLookup();
  });

  tearDown(() {
    Aria2.resetLookup();
    try {
      map.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('DE KERN: een mislukte zoektocht wordt niet onthouden', () {
    // Niets te vinden: geen aria2c naast de app, geen aria2c in de eigen map.
    final motor = Aria2();
    if (_vindtEenAria2()) {
      // DE GRENS: hier valt er niets te missen, dus is er ook geen misser om te onthouden. Wat op
      // zo'n machine wel geldt: er komt een echt pad uit, en geen null.
      expect(motor.pad, isNotNull, reason: 'er staat hier een aria2c in de systeempaden');
      return;
    }
    expect(motor.pad, isNull, reason: 'er staat hier niets, dus dit hoort te mislukken');
    expect(motor.laatsteFout, contains('niet gevonden'));

    // En nu komt hij er alsnog. Zou de misser onthouden zijn, dan bleef het antwoord null tot de
    // app herstart — en dat is precies wat er op 02-09 gebeurde.
    final nep = File('${map.path}${Platform.pathSeparator}'
        '${Platform.isWindows ? 'aria2c.exe' : 'aria2c'}');
    nep.writeAsStringSync('geen echt programma');

    // Het pad wordt nu wél opnieuw gezocht. Dat het nog steeds niets oplevert is hier bijzaak --
    // dit bestand is geen uitvoerbaar programma -- waar het om gaat is dat er ECHT opnieuw gekeken
    // is in plaats van een oud antwoord terug te geven.
    expect(motor.laatsteFout, isNotNull);
  });

  test('een gevonden pad wordt WEL onthouden', () {
    // Anders staat er bij elke download een procesaanroep extra, en die kost tijd bij elk nummer.
    final motor = Aria2(pad: r'C:\ergens\aria2c.exe');
    expect(motor.pad, r'C:\ergens\aria2c.exe');
    expect(motor.pad, r'C:\ergens\aria2c.exe', reason: 'tweede keer hetzelfde, zonder zoeken');
  });

  test('en start() zwijgt niet meer als hij niets kan vinden', () async {
    if (_vindtEenAria2()) {
      // Hier zou start() een ECHTE aria2c opstarten. Dat is niet wat deze toets wil weten, en het
      // laat een proces achter op de bouwmachine.
      expect(Aria2().pad, isNotNull, reason: 'er staat hier een aria2c in de systeempaden');
      return;
    }
    final motor = Aria2();
    expect(await motor.start(downloadMap: map.path), isFalse);

    final log = File('${map.path}${Platform.pathSeparator}aria2.log');
    expect(log.existsSync(), isTrue, reason: 'er hoort een logboek te zijn');
    expect(log.readAsStringSync(), contains('niet gevonden'),
        reason: 'zonder deze regel is er niets om naar te kijken als downloaden stil stopt');
  });
}

/// De manieren waarop een besturingssysteem een bestand aanwijst.
///
/// Elk ervan is een detail dat je één keer opzoekt en daarna nooit meer nakijkt, en elk ervan is
/// fout te krijgen zonder dat er iets rood wordt. Hier liggen ze vast — op elke machine, ook op de
/// Linux-bouwmachine die zelf geen van de twee gebruikt waar het om gaat.
///
/// **De fout die deze toets had moeten vangen en niet ving.** De eerste versie deed op Windows
/// `Process.run('explorer.exe', ['/select,$pad'])`, en de toets keurde dat goed omdat hij de
/// verkeerde vraag stelde: hij keek of er géén aanhalingsteken in het argument stond. Dat klopte —
/// maar Windows kent geen lijst argumenten, alleen één opdrachtregel, en Dart zet daar zelf
/// aanhalingstekens omheen zodra er een spatie in zit. Voor `D:\Flac music 2024\…` komt de vlag
/// daarmee BINNEN de aanhalingstekens te staan, explorer herkent hem niet, en die opent zijn
/// standaardmap. Gemeld als "wijst naar het verkeerde pad", en dat was het ook.
///
/// De toets kijkt nu naar wat er werkelijk bij explorer aankomt.
library;

import 'package:debridmusic/bestandsbeheer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pad = r'D:\Flac music 2024\Faithless\Insomnia\01 - Insomnia.flac';

  group('Windows', () {
    test('de vlag staat buiten de aanhalingstekens en het pad erbinnen', () {
      // Dít is de hele reparatie. Andersom — `"/select,D:\…"` — leest explorer als één pad dat niet
      // bestaat, en dan opent hij de map waar hij standaard opent.
      expect(windowsBatchRegel(pad), 'explorer.exe /select,"$pad"');
      expect(windowsBatchRegel(pad), startsWith('explorer.exe /select,"'),
          reason: 'de vlag hoort kaal te staan');
      expect(windowsBatchRegel(pad), endsWith('"'));
    });

    test('/select, blijft eraan vast', () {
      // Met een spatie ertussen negeert explorer de vlag en OPENT hij het bestand — dat wil zeggen:
      // hij start er een tweede muziekspeler mee naast deze.
      expect(windowsBatchRegel(pad), isNot(contains('/select, ')));
    });

    test('een procentteken in de naam wordt verdubbeld', () {
      // `cmd` leest een batchbestand als tekst en zou `%iets%` uitvouwen als omgevingsvariabele.
      // Wat er niet is verdwijnt dan spoorloos uit het pad — een bestand dat niet gevonden wordt,
      // zonder dat iets zegt waarom.
      expect(windowsBatchRegel(r'D:\Muziek\100% Hardcore\01.flac'),
          r'explorer.exe /select,"D:\Muziek\100%% Hardcore\01.flac"');
    });

    test('Windows gaat NIET meer over een argumentenlijst', () {
      // De oude weg. Dat hij hier niets teruggeeft is geen gat maar de reparatie: op Windows kan het
      // niet met een lijst argumenten, omdat Dart die zelf tot één opdrachtregel maakt.
      expect(onthulOpdrachtVoor(pad, os: 'windows'), isNull);
    });
  });

  group('de andere twee', () {
    test('macOS wijst aan met -R', () {
      expect(onthulOpdrachtVoor(pad, os: 'macos'), ['open', '-R', pad]);
    });

    test('Linux vraagt het via de vrijedesktop-afspraak', () {
      final o = onthulOpdrachtVoor(pad, os: 'linux')!;
      expect(o.first, 'dbus-send');
      expect(o, contains('org.freedesktop.FileManager1.ShowItems'));
      expect(o, contains('array:string:file://$pad'));
    });

    test('een telefoon en een televisie krijgen niets', () {
      // Belangrijker dan het lijkt: hierop hangt of de menuregel er überhaupt staat. Zou dit een
      // opdracht teruggeven, dan stond er op een telefoon een knop die niets kan doen.
      expect(onthulOpdrachtVoor(pad, os: 'android'), isNull);
      expect(onthulOpdrachtVoor(pad, os: 'ios'), isNull);
    });
  });

  test('een pad met spaties en haakjes blijft heel', () {
    // Precies het soort naam dat in deze bibliotheek staat — zie "Thunderdome VIII (The Devil In
    // Disguise)". Aan het pad zelf hoort niets ontsnapt te worden; het staat binnen aanhalingstekens
    // en dat is genoeg.
    const raar = r'D:\Muziek\Thunderdome VIII (The Devil In Disguise)\01 - Go Get Busy.flac';
    expect(windowsBatchRegel(raar), contains('"$raar"'));
    expect(onthulOpdrachtVoor(raar, os: 'macos')!.last, raar);
  });
}

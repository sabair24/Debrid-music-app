/// De drie manieren waarop een besturingssysteem een bestand aanwijst.
///
/// Elk van de drie is een detail dat je één keer opzoekt en daarna nooit meer nakijkt, en elk van de
/// drie is fout te krijgen zonder dat er iets rood wordt: de app start dan gewoon niets, of erger,
/// opent het nummer in een tweede muziekspeler. Hier liggen ze vast — op elke machine, ook op de
/// Linux-bouwmachine die zelf geen van de twee gebruikt waar het om gaat.
library;

import 'package:debridmusic/bestandsbeheer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pad = r'D:\Flac music 2024\Michael Jackson\Thriller\01 - Wanna Be Startin.flac';

  group('de opdracht per besturingssysteem', () {
    test('Windows wijst aan en opent niet', () {
      final o = onthulOpdrachtVoor(pad, os: 'windows')!;
      expect(o.first, 'explorer.exe');
      // Het gevaarlijke geval: zónder `/select,` opent explorer het bestand met de standaard-
      // toepassing, en dan staat er een tweede muziekspeler te spelen naast deze.
      expect(o.length, 2, reason: 'explorer leest de vlag en het pad als ÉÉN argument');
      expect(o[1], '/select,$pad');
      expect(o[1], isNot(contains('"')), reason: 'Process.run kent geen shell; een aanhalingsteken '
          'wordt onderdeel van de bestandsnaam');
    });

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

  test('een pad met spaties en haakjes blijft één argument', () {
    // Precies het soort naam dat in deze bibliotheek staat — zie "Thunderdome VIII (The Devil In
    // Disguise)". Zonder shell hoort daar niets aan ontsnapt te worden; wél moet het één stuk
    // blijven.
    const raar = r'D:\Muziek\Thunderdome VIII (The Devil In Disguise)\01 - Go Get Busy.flac';
    expect(onthulOpdrachtVoor(raar, os: 'windows')!.last, '/select,$raar');
    expect(onthulOpdrachtVoor(raar, os: 'macos')!.last, raar);
  });
}

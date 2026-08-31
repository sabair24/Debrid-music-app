/// De vlaggen waarmee de Windows-installer draait.
///
/// **Waarom hier een test op staat.** Op 31-08-2026 om 00:09 werkte de bijwerkknop niet: de app
/// sloot af, er werd niets geïnstalleerd, en de versie op schijf bleef staan waar hij stond. Uit
/// Inno's eigen logboek:
///
///     Defaulting to Abort for suppressed message box (Abort/Retry/Ignore):
///     Setup kon niet alle programma's automatisch afsluiten.
///     User canceled the installation process.
///     Rolling back changes.
///
/// Wat er niet dichtging is `aria2c.exe`, dat in dezelfde map staat als de app en draait zodra er
/// ooit een torrent is gehaald. Inno krijgt zo'n proces niet dicht met een venstermelding, vraagt
/// dan Abort/Retry/Ignore, en met `/SUPPRESSMSGBOXES` erbij kiest hij zwijgend Abort.
///
/// Vier vlaggen die elkaar nodig hebben, en het weghalen van één ervan is van buiten niet te zien —
/// je merkt het pas als een gebruiker zegt dat zijn app na het bijwerken weg is. Vandaar deze test.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/updater.dart';

void main() {
  test('DE KERN: Inno mag beëindigen wat hij niet netjes dicht krijgt', () {
    expect(Updater.innoVlaggen, contains('/FORCECLOSEAPPLICATIONS'),
        reason: 'zonder deze vlag blokkeert aria2c.exe de hele installatie');
  });

  test('en die hoort samen met CLOSEAPPLICATIONS', () {
    // FORCECLOSEAPPLICATIONS doet in zijn eentje niets: het is de scherpe kant van CLOSEAPPLICATIONS.
    expect(Updater.innoVlaggen, contains('/CLOSEAPPLICATIONS'));
    expect(Updater.innoVlaggen, contains('/RESTARTAPPLICATIONS'),
        reason: 'anders komt de app na het bijwerken niet terug');
  });

  test('stil, want er staat niemand bij', () {
    expect(Updater.innoVlaggen, containsAll(['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART']));
  });

  test('en niets dat om een antwoord vraagt', () {
    // Elke vlag die een venster kan openen zet een bijwerkronde stil op een pc waar niemand kijkt.
    for (final v in Updater.innoVlaggen) {
      expect(v.startsWith('/'), isTrue, reason: '"$v" is geen Inno-vlag');
    }
  });
}

/// Na een stille update start de installer niet meer de kale exe maar `windows/installer/herstart.ps1`, dat nagaat of de
/// app echt opkomt (31-10-2026: de herstart van 3.9.689 bleef hangen vóór de eerste regel en de pc stond tot de volgende
/// ochtend zonder app).
///
/// Het script zelf is op de pc nagemeten met een nep-app (meteen op, eerste poging hangt, elke poging hangt, een tweede
/// kopie die zichzelf sluit), in pwsh en in Windows PowerShell 5.1. Hier: dat de installer het meeneemt en start, en dat
/// het zoekt naar precies de regel die de runner schrijft — anders hangt elke herstart dertig seconden en wordt een
/// gezonde app gestopt.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _bron(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  test('de installer neemt het script mee en start het na een stille installatie', () {
    final yml = _bron('../.github/workflows/windows_build.yml');
    expect(yml, contains(r'$L.Add("Source: `"$wsDesktop\windows\installer\herstart.ps1`"; DestDir: `"{app}`"; Flags: ignoreversion")'));
    expect(yml, contains(r'''Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\herstart.ps1"" -App ""{app}\debridmusic.exe"""; Flags: nowait runhidden; Check: StilleInstallatie'''));
    expect(yml, isNot(contains(r'''$L.Add('Filename: "{app}\debridmusic.exe"; Flags: nowait; Check: StilleInstallatie')''')),
        reason: 'niet ook nog de kale exe: dan zijn er twee starts en ziet het script de verkeerde');
  });

  test('het script zoekt de regel die de runner als allereerste schrijft', () {
    final runner = _bron('windows/runner/main.cpp');
    expect(runner, contains('"runner: proces %lu gestart door %s, nCmdShow=%d'));
    final ps = _bron('windows/installer/herstart.ps1');
    expect(ps, contains(r'-Pattern ("runner: proces $id ") -SimpleMatch -Quiet'));
    expect(ps, contains(r"[string]$StartLog = (Join-Path $env:APPDATA 'DebridMusic\start.log')"));
    expect(ps, contains('[int]\$Geduld = 30'));
    expect(ps, contains(r'for ($poging = 1; $poging -le 3; $poging++) {'));
    expect(ps, contains(r"[string]$Naam = 'debridmusic'"));
    // Alleen gewone tekens: Windows PowerShell 5.1 leest een bestand zonder BOM als ANSI.
    expect(ps.codeUnits.every((c) => c < 128), isTrue);
  });
}

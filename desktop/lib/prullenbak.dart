/// Naar de prullenbak in plaats van weg.
///
/// **Waarom dit er is — 26-09-2026.** Bij het starten van een radio kwam het overzicht van de vorige
/// terug, en een klik die voor "Later beslissen" bedoeld was landde op "Afsluiten en 19 opruimen",
/// de knop er vlak boven. Dat was `File.delete()`: dertien radionummers onherroepelijk van de schijf,
/// geen weg terug. Een opruimknop mag zich vergissen — een mens tikt er weleens naast — maar dan
/// moet de vergissing terug te draaien zijn.
///
/// **Hoe.** Windows heeft er één functie voor, `SHFileOperation` met `FOF_ALLOWUNDO`: dat is wat de
/// Verkenner doet als je op Delete drukt. Deze app heeft geen eigen FFI-koppeling naar shell32, dus
/// gaat het via PowerShell, dat hem in één keer voor een hele lijst aanroept. De paden gaan via een
/// bestand en niet via de opdrachtregel: een titel met een apostrof of een aanhalingsteken ("I'm on
/// Fire") hoort niets aan het script te kunnen veranderen.
///
/// **En als het niet lukt, gebeurt er NIETS.** Liever een bestand dat blijft staan dan een dat alsnog
/// definitief weg is: wie om de prullenbak vraagt, vraagt om een weg terug. Op macOS gaat het via
/// de Finder naar de Prullenmand; op andere systemen is er geen prullenbak en kan het niet.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Kan dit systeem iets naar een prullenbak verplaatsen?
bool get heeftPrullenbak => Platform.isWindows || Platform.isMacOS;

/// Het PowerShell-script dat elk pad uit het UTF-8-bestand [lijst] naar de prullenbak verplaatst.
///
/// `FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI`: naar de prullenbak, zonder
/// vragen, zonder voortgangsvenster en zonder foutvenster — een verborgen proces met een venster
/// dat op een klik wacht, wacht voor altijd. [lijst] komt tussen enkele aanhalingstekens, met elke
/// enkele verdubbeld, zoals PowerShell dat wil.
String prullenbakScript(String lijst) {
  final pad = lijst.replaceAll("'", "''");
  return r'''
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DmPrullenbak {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct Op {
    public IntPtr hwnd; public uint wFunc; public string pFrom; public string pTo;
    public ushort fFlags; public bool fAnyOperationsAborted; public IntPtr hNameMappings;
    public string lpszProgressTitle;
  }
  [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
  static extern int SHFileOperation(ref Op op);
  public static int Weg(string pad) {
    var op = new Op();
    op.wFunc = 3;
    op.pFrom = pad + "\0\0";
    op.fFlags = 0x0040 | 0x0010 | 0x0004 | 0x0400;
    return SHFileOperation(ref op);
  }
}
'@
foreach ($p in [System.IO.File]::ReadAllLines(''' "'$pad'" r''', [System.Text.Encoding]::UTF8)) {
  if ($p -and [System.IO.File]::Exists($p)) { [void][DmPrullenbak]::Weg($p) }
}
''';
}

/// [script] zoals `powershell -EncodedCommand` hem wil: UTF-16LE, in base64.
///
/// Zo en niet met `-Command`: dan gaat het script als gewoon argument over de opdrachtregel, en
/// PowerShell 5.1 leest aanhalingstekens daarin anders dan Windows ze doorgeeft. Een gecodeerd
/// script heeft geen aanhalingstekens meer om zich in te vergissen.
String psGecodeerd(String script) {
  final eenheden = script.codeUnits;
  final bytes = Uint8List(eenheden.length * 2);
  for (var i = 0; i < eenheden.length; i++) {
    bytes[2 * i] = eenheden[i] & 0xff;
    bytes[2 * i + 1] = eenheden[i] >> 8;
  }
  return base64.encode(bytes);
}

/// Het AppleScript dat [paden] via de Finder naar de Prullenmand verplaatst, als argumenten voor
/// `osascript`: het script leest ze uit `argv`, dus ook hier komt geen pad in de scripttekst.
List<String> prullenmandArgumenten(List<String> paden) => [
      '-e',
      'on run argv',
      '-e',
      'repeat with p in argv',
      '-e',
      'tell application "Finder" to delete (POSIX file (p as text) as alias)',
      '-e',
      'end repeat',
      '-e',
      'end run',
      ...paden,
    ];

/// Hoe een extern programma gestart wordt. Een haak, zodat een toets kan nagaan wat er gevraagd
/// wordt zonder iets in een echte prullenbak te gooien.
typedef Draaier = Future<ProcessResult> Function(String programma, List<String> argumenten);

Future<ProcessResult> _echt(String programma, List<String> argumenten) =>
    Process.run(programma, argumenten).timeout(const Duration(minutes: 2));

/// Verplaats [paden] naar de prullenbak.
///
/// Geeft de paden terug die daarna werkelijk niet meer op hun plek staan — alleen dáár mag de
/// aanroeper verder mee (uit de bibliotheek, oordelen vergeten). Wat bleef staan, bleef staan.
Future<Set<String>> naarPrullenbak(List<String> paden,
    {Draaier draai = _echt, bool? windows, String? werkmap}) async {
  final bestaand = [
    for (final p in paden)
      if (File(p).existsSync()) p
  ];
  if (bestaand.isEmpty) return {};
  final opWindows = windows ?? Platform.isWindows;
  try {
    if (opWindows) {
      final map = Directory(werkmap ?? Directory.systemTemp.path);
      final lijst = File(
          '${map.path}${Platform.pathSeparator}dm_prullenbak_${DateTime.now().microsecondsSinceEpoch}.txt');
      await lijst.writeAsString(bestaand.join('\r\n'), encoding: utf8);
      try {
        await draai('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-EncodedCommand',
          psGecodeerd(prullenbakScript(lijst.path)),
        ]);
      } finally {
        try {
          await lijst.delete();
        } catch (_) {}
      }
    } else if (Platform.isMacOS) {
      await draai('osascript', prullenmandArgumenten(bestaand));
    } else {
      return {};
    }
  } catch (_) {
    // Niets geforceerd: wat er nog staat, blijft staan. Zie de uitleg bovenaan.
  }
  return {
    for (final p in bestaand)
      if (!File(p).existsSync()) p
  };
}

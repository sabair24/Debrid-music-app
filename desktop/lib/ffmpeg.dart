/// Waar ffmpeg staat, op één plek.
///
/// De resolver stond privé in `lan/transcode.dart`, waar hij alleen bestond om voor een Sonos te
/// herbemonsteren. De echtheidsmeter heeft hem ook nodig, en die is geen LAN-code — een
/// bibliotheekfunctie die `../lan/` importeert is de laag verkeerd om.
///
/// Vorm van [Fingerprinter] in fingerprint.dart: één keer zoeken, statisch onthouden, `available` om te
/// vragen, en nooit een uitzondering naar buiten. Een ontbrekende ffmpeg is geen storing maar een
/// beperking, en de app hoort dat te kunnen melden in plaats van eraan onderdoor te gaan.
library;

import 'dart:io';

import 'uitvoerbaar.dart';

class Ffmpeg {
  Ffmpeg({String? pad}) : _opgegeven = pad;
  final String? _opgegeven;

  static String? _gevonden;
  static bool _gezocht = false;

  /// Kandidaten, in volgorde van vertrouwen.
  ///
  /// Naast de app eerst — zet de gebruiker ffmpeg.exe daar neer, dan is dat een bewuste keuze, net als
  /// bij fpcalc. Daarna de gebruikelijke installatieplekken op Windows, en tot slot PATH.
  static List<String> _kandidaten() {
    final naastDeApp = File(Platform.resolvedExecutable).parent.path;
    final exe = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
    return [
      '$naastDeApp${Platform.pathSeparator}$exe',
      if (Platform.isWindows) ...[
        r'C:\ffmpeg\bin\ffmpeg.exe',
        r'C:\Program Files\ffmpeg\bin\ffmpeg.exe',
      ] else ...[
        '/usr/bin/ffmpeg',
        '/usr/local/bin/ffmpeg',
        '/opt/homebrew/bin/ffmpeg',
      ],
      exe, // via PATH
    ];
  }

  /// Waar het op stukliep, voor wie het wil weten. Zwijgen is niet gratis — dat heeft deze codebase
  /// duur geleerd (zie `WarmLog.laatsteFout`).
  static String? laatsteFout;

  String? get pad {
    if (_opgegeven != null && _opgegeven.isNotEmpty) return _opgegeven;
    if (_gezocht) return _gevonden;
    _gezocht = true;
    final geprobeerd = <String>[];
    for (final k in _kandidaten()) {
      try {
        final echt = uitvoerbaarPad(k);
        if (echt == null) {
          geprobeerd.add(k);
          continue;
        }
        if (Process.runSync(echt, ['-version']).exitCode == 0) {
          _gevonden = echt;
          return echt;
        }
        geprobeerd.add(k);
      } catch (_) {
        geprobeerd.add(k);
      }
    }
    laatsteFout = 'ffmpeg niet gevonden; geprobeerd: ${geprobeerd.join(", ")}';
    return null;
  }

  bool get available => pad != null;

  /// Tests delen dit proces, en een gevonden pad uit de vorige test laat de volgende iets anders meten.
  static void resetLookup() {
    _gevonden = null;
    _gezocht = false;
  }
}

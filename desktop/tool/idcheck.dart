/// Levert de eigen berekening hetzelfde id op als de server serveert?
///
/// De vraag waar de speakerknop op de pc op stond of viel: op de pc is het pad een bestand en niet een
/// stream-URL, dus het id moet berekend worden zoals de server het doet. Klopt dat niet, dan neemt de
/// speaker de wachtrij niet aan en zegt de app toch "Speelt op X".
library;

import 'dart:io';

import 'package:debridmusic/lan/ids.dart';

void main(List<String> args) {
  final root = args.isEmpty ? r'D:\Flac music 2024' : args.first;
  final verwacht = <String, String>{
    'f0992f0532f6a7a0bb21f12c': 'Army Of Hardcore',
    '8486e14071e1de5075472016': 'Hello',
  };
  final gevonden = <String, String>{};
  for (final e in Directory(root).listSync(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final p = e.path.toLowerCase();
    if (!p.endsWith('.flac') && !p.endsWith('.mp3')) continue;
    final id = trackIdFor(e.path, root);
    if (verwacht.containsKey(id)) gevonden[id] = e.path;
  }
  verwacht.forEach((id, naam) {
    final pad = gevonden[id];
    stdout.writeln(pad == null
        ? 'NIET GEVONDEN  $id  ($naam)'
        : 'klopt  $id  ($naam)\n    ${pad.replaceAll(root, '…')}');
  });
}

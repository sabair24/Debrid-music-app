// Acht betrapte nummers uit verschillende albums, met artiest/titel uit het pad.
import 'dart:convert';
import 'dart:io';
void main(List<String> args) {
  final pad = [Platform.environment['APPDATA'], 'DebridMusic', 'echtheid_oordelen.json']
      .join(Platform.pathSeparator);
  final d = jsonDecode(File(pad).readAsStringSync()) as Map<String, dynamic>;
  final uit = <Map<String, dynamic>>[];
  final albums = <String>{};
  final rijen = <MapEntry<String, dynamic>>[];
  d.forEach((p, o) {
    if ((o as Map)['band'] != 'afgekapt') return;
    if (p.contains('_dubbel') || p.contains('_inkomend')) return;
    rijen.add(MapEntry(p, o));
  });
  rijen.sort((a, b) => ((a.value['afkapHz'] ?? 0) as num).compareTo((b.value['afkapHz'] ?? 0) as num));
  for (final e in rijen) {
    final delen = e.key.split(Platform.pathSeparator);
    if (delen.length < 3) continue;
    final album = delen[delen.length - 2], artiest = delen[delen.length - 3];
    if (!albums.add(album)) continue; // hoogstens één per album, voor spreiding over peers
    var titel = delen.last.replaceAll('.flac', '').replaceFirst(RegExp(r'^\d+\s*[-.]\s*'), '');
    uit.add({'artiest': artiest, 'titel': titel, 'pad': e.key, 'afkapHz': e.value['afkapHz']});
    if (uit.length >= int.parse(args[0])) break;
  }
  stdout.writeln(jsonEncode(uit));
}

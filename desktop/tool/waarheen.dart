/// Proefloop: waar zou elk los bestand in de wortel van de bibliotheek terechtkomen?
///
/// Verplaatst niets. Het punt is dat je de verhuizing kunt lezen vóórdat hij gebeurt -- vijftig
/// bestanden tegelijk verzetten op goed vertrouwen is precies het soort actie waar je achteraf niet
/// meer bij kunt.
///
///     dart run tool/waarheen.dart "D:\Flac music 2024" "D:\Flac music 2024\DebridMusic Downloads"
///
/// Het tweede pad is de nette boom. Die staat elders dan de wortel waar de losse bestanden liggen,
/// en dat verschil is precies wat je wilt zien: mikken op de wortel maakt een TWEEDE Albums-map
/// naast de bestaande, en dan staat dezelfde plaat op twee plekken.
library;

import 'dart:io';

import 'package:debridmusic/organize.dart';

const _audio = {'.flac', '.mp3', '.m4a', '.ogg', '.opus', '.wav', '.aac', '.alac', '.ape'};

void main(List<String> args) {
  final wortel = args.isEmpty ? r'D:\Flac music 2024' : args.first;
  final boom = args.length > 1 ? args[1] : wortel;
  final dir = Directory(wortel);
  if (!dir.existsSync()) {
    stderr.writeln('geen map: $wortel');
    exit(1);
  }

  // Alleen het bovenste niveau. Wat al in de nette boom staat blijft ongemoeid.
  final los = dir
      .listSync(followLinks: false)
      .whereType<File>()
      .where((f) {
        final p = f.path.toLowerCase();
        final dot = p.lastIndexOf('.');
        return dot >= 0 && _audio.contains(p.substring(dot));
      })
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final perMap = <String, List<String>>{};
  final onleesbaar = <String>[];
  var bytes = 0;

  for (final f in los) {
    final naam = f.uri.pathSegments.last;
    final t = readTags(f);
    if (t == null) {
      onleesbaar.add(naam);
      continue;
    }
    final ext = naam.contains('.') ? naam.substring(naam.lastIndexOf('.')) : '';
    final rel = relativePathFor(t, ext: ext);
    final sep = Platform.pathSeparator;
    final map = rel.substring(0, rel.lastIndexOf(sep));
    final bestand = rel.substring(rel.lastIndexOf(sep) + 1);
    // Botst hij met een bestand dat er al staat? Dat is het enige geval waarin de echte verhuizing
    // iets zou kunnen weggooien, dus het hoort in de proefloop te staan en niet als verrassing.
    final doel = File('$boom$sep$rel');
    final botst = doel.existsSync() ? '   ⚠ STAAT ER AL' : '';
    perMap.putIfAbsent(map, () => []).add('$bestand   ⟵ $naam$botst');
    bytes += f.lengthSync();
  }

  final namen = perMap.keys.toList()..sort();
  for (final m in namen) {
    final bestaat = Directory('$boom${Platform.pathSeparator}$m').existsSync();
    stdout.writeln('${bestaat ? "[bestaat]" : "[nieuw]  "} $m');
    for (final r in perMap[m]!) {
      stdout.writeln('              $r');
    }
  }
  if (onleesbaar.isNotEmpty) {
    stdout.writeln('\nGEEN TAGS TE LEZEN (${onleesbaar.length}):');
    for (final n in onleesbaar) {
      stdout.writeln('   $n');
    }
  }
  stdout.writeln('\n${los.length} losse bestanden · ${namen.length} doelmappen · '
      '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB');
}

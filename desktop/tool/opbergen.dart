/// Berg de losse bestanden uit de wortel op in de nette boom.
///
/// Bewust NIET `tidyDownloads`: die loopt recursief en zou de hele bibliotheek herindelen, en hij
/// gooit bij een botsing de mindere kopie weg. Hier gebeurt geen van beide. Alleen het bovenste
/// niveau, en een doel dat al bestaat wordt overgeslagen en gemeld -- nooit overschreven.
///
///     dart run tool/opbergen.dart "D:\Flac music 2024" "D:\Flac music 2024\DebridMusic Downloads"
///     dart run tool/opbergen.dart ... --doen        (zonder deze vlag verplaatst hij niets)
library;

import 'dart:io';

import 'package:debridmusic/organize.dart';

const _audio = {'.flac', '.mp3', '.m4a', '.ogg', '.opus', '.wav', '.aac', '.alac', '.ape'};

/// Haal de kop `Albums\` / `Compilaties\` / `Singles\` van het pad af.
///
/// Die laag is van de app; de bibliotheek van de gebruiker is gewoon artiest → album → nummers, en
/// een plaat hoort niet in een andere map te belanden omdat een indeler hem "compilatie" noemt.
String zonderCategorie(String rel) {
  final sep = Platform.pathSeparator;
  final i = rel.indexOf(sep);
  return i < 0 ? rel : rel.substring(i + 1);
}

void main(List<String> args) {
  final echt = args.contains('--doen');
  final paden = args.where((a) => !a.startsWith('--')).toList();
  final wortel = paden.isEmpty ? r'D:\Flac music 2024' : paden.first;
  final boom = paden.length > 1 ? paden[1] : wortel;
  final sep = Platform.pathSeparator;

  final los = Directory(wortel).listSync(followLinks: false).whereType<File>().where((f) {
    final p = f.path.toLowerCase();
    final dot = p.lastIndexOf('.');
    return dot >= 0 && _audio.contains(p.substring(dot));
  }).toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  var verplaatst = 0, overgeslagen = 0;
  final gemist = <String>[];

  for (final f in los) {
    final naam = f.uri.pathSegments.last;
    final zonderExt = naam.substring(0, naam.lastIndexOf('.'));

    // Een FLAC met een cue ernaast is geen nummer maar een hele cd in één bestand. Die losmaken van
    // zijn cue maakt hem onbruikbaar, en als "single van Onbekende artiest" wegzetten is onzin.
    final cue = Directory(wortel)
        .listSync(followLinks: false)
        .whereType<File>()
        .any((c) => c.uri.pathSegments.last.toLowerCase().startsWith('${zonderExt.toLowerCase()} ') &&
            c.path.toLowerCase().endsWith('.cue'));
    if (cue) {
      gemist.add('$naam — cd-image met cue, blijft staan');
      overgeslagen++;
      continue;
    }

    final t = readTags(f);
    if (t == null) {
      gemist.add('$naam — geen tags te lezen');
      overgeslagen++;
      continue;
    }

    final ext = naam.substring(naam.lastIndexOf('.'));
    final doel = File('$boom$sep${zonderCategorie(relativePathFor(t, ext: ext))}');
    if (doel.existsSync()) {
      gemist.add('$naam — er staat daar al een bestand, niets aangeraakt');
      overgeslagen++;
      continue;
    }

    if (!echt) {
      verplaatst++;
      continue;
    }
    try {
      doel.parent.createSync(recursive: true);
      f.renameSync(doel.path);
      verplaatst++;
    } catch (e) {
      gemist.add('$naam — $e');
      overgeslagen++;
    }
  }

  stdout.writeln(echt ? '$verplaatst verplaatst' : '$verplaatst zouden verhuizen (proefloop)');
  stdout.writeln('$overgeslagen overgeslagen');
  for (final g in gemist) {
    stdout.writeln('   $g');
  }
}

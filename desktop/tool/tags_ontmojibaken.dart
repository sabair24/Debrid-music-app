/// Repareert dubbel gecodeerde tekst in de tags van de bestanden zelf.
///
/// Gisteren is dit rechtgezet in `album_facts.json` -- de feitencache -- maar de tags in de FLAC's
/// bleven zoals ze waren. Daar staat bij negen nummers nog `MÃƒÂ¡s es amar` waar *Más es amar* hoort,
/// en dat is wat de scanner leest, dus komt het na elke herscan gewoon terug in de app.
///
/// Waarom een apart gereedschap en geen knop: dit schrijft in bestanden en dat wil je één keer doen,
/// zien wat er gebeurde, en kunnen terugdraaien. Daarom standaard een DROOGLOOP -- hij toont wat hij
/// zou veranderen en raakt niets aan. Pas met `--schrijf` gaat het echt, en dan gaan de oude waarden
/// eerst naar een terugdraaibestand.
///
///     dart run tool/tags_ontmojibaken.dart "D:\Flac music 2024"
///     dart run tool/tags_ontmojibaken.dart "D:\Flac music 2024" --schrijf
///
/// De reparatie zelf komt uit [unmojibake], die drie voorwaarden stelt voordat hij iets verandert --
/// een echte Franse titel als "café" blijft daardoor ongemoeid. Hier wordt hij herhaald toegepast,
/// want tekst kan twee keer verkeerd gecodeerd zijn: `MÃƒÂ¡s` wordt pas `Más` na twee slagen.
library;

import 'dart:convert';
import 'dart:io';

import 'package:debridmusic/flac_tags.dart';
import 'package:debridmusic/mojibake.dart';
import 'package:debridmusic/organize.dart';

/// Blijf herstellen tot er niets meer verandert.
///
/// [unmojibake] maakt tekst per slag korter en stopt uit zichzelf, dus dit eindigt altijd. De grens
/// van vijf is een vangrail, geen verwachting: twee slagen is wat er in deze bibliotheek staat.
String herstelVolledig(String s) {
  var uit = s;
  for (var i = 0; i < 5; i++) {
    final volgende = unmojibake(uit);
    if (volgende == uit) return uit;
    uit = volgende;
  }
  return uit;
}

Future<void> main(List<String> args) async {
  final root = args.isNotEmpty && !args.first.startsWith('--') ? args.first : r'D:\Flac music 2024';
  final schrijven = args.contains('--schrijf');

  final dir = Directory(root);
  if (!dir.existsSync()) {
    stdout.writeln('map bestaat niet: $root');
    exitCode = 1;
    return;
  }

  final terug = <String, Map<String, String>>{}; // pad -> veld -> oude waarde
  var bekeken = 0, geraakt = 0, velden = 0, mislukt = 0;

  await for (final e in dir.list(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final laag = e.path.toLowerCase();
    if (!laag.endsWith('.flac')) continue;
    bekeken++;

    final huidig = readFlacRawFields(e);
    if (huidig.isEmpty) continue;

    final nieuw = <String, String?>{};
    final oud = <String, String>{};
    huidig.forEach((veld, waarde) {
      final beter = herstelVolledig(waarde);
      if (beter != waarde) {
        nieuw[veld.toUpperCase()] = beter;
        oud[veld.toUpperCase()] = waarde;
      }
    });
    if (nieuw.isEmpty) continue;

    geraakt++;
    velden += nieuw.length;
    stdout.writeln(e.path.replaceFirst(root, '...'));
    nieuw.forEach((veld, beter) => stdout.writeln('   $veld: ${oud[veld]}  ->  $beter'));

    if (!schrijven) continue;
    if (await writeTagFields(e, nieuw)) {
      terug[e.path] = oud;
    } else {
      mislukt++;
      stdout.writeln('   !! schrijven mislukt, bestand ongewijzigd');
    }
  }

  stdout.writeln('');
  stdout.writeln('$bekeken bestanden bekeken, $geraakt met verminkte tekst, $velden velden');
  if (!schrijven) {
    stdout.writeln('DROOGLOOP -- er is niets veranderd. Voeg --schrijf toe om het echt te doen.');
    return;
  }
  if (mislukt > 0) stdout.writeln('$mislukt bestanden konden niet geschreven worden');
  if (terug.isEmpty) return;

  final bak = File('$root${Platform.pathSeparator}.tags-voor-ontmojibaken.json');
  await bak.writeAsString(const JsonEncoder.withIndent('  ').convert(terug));
  stdout.writeln('oude waarden bewaard in ${bak.path}');
}

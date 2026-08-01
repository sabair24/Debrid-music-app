/// Trekt binnen elke albummap het TRACKTOTAL gelijk, zodat een plaat niet in stukken uiteenvalt.
///
/// De bibliotheek splitst een album zodra twee nummers hetzelfde tracknummer claimen én een ander
/// TRACKTOTAL opgeven — een goede regel, want zo blijven twee echte persingen uit elkaar. Maar bij een
/// VERVANGEN nummer werkt hij averechts: de betere kopie komt van een uploader die van een andere
/// persing ripte en 11 of 17 schrijft waar jouw plaat 13 zegt. Eén zo'n bestand breekt de hele plaat.
///
/// Gemeten op Backstreet's Back: drie tegels van één album — 12 nummers onder "13 nummers", 1 onder
/// "11 nummers" en 2 onder "17 nummers".
///
/// [placeFileDetailed] doet dit sinds vandaag vanzelf voor nieuwe downloads. Dit gereedschap is voor
/// wat er al ligt.
///
///     dart run tool/zelfde_uitgave.dart "D:\Flac music 2024"        # alleen tonen
///     dart run tool/zelfde_uitgave.dart "D:\Flac music 2024" --doe  # ook schrijven
///
/// De meerderheid beslist. Is een map echt in tweeën verdeeld (even veel van beide), dan blijft hij
/// staan: dan zijn het waarschijnlijk twee persingen die naast elkaar horen te liggen, en dat is een
/// keuze die de gebruiker maakt en niet dit gereedschap.
library;

import 'dart:io';

import 'package:debridmusic/flac_tags.dart';
import 'package:debridmusic/organize.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stdout.writeln('gebruik: dart run tool/zelfde_uitgave.dart <muziekmap> [--doe]');
    exitCode = 1;
    return;
  }
  final root = Directory(args.first);
  final schrijven = args.contains('--doe');
  if (!root.existsSync()) {
    stdout.writeln('bestaat niet: ${root.path}');
    exitCode = 1;
    return;
  }

  final perMap = <String, List<File>>{};
  for (final e in root.listSync(recursive: true, followLinks: false)) {
    if (e is! File || !e.path.toLowerCase().endsWith('.flac')) continue;
    final p = e.path;
    if (p.contains('${Platform.pathSeparator}_dubbel${Platform.pathSeparator}')) continue;
    if (p.contains('${Platform.pathSeparator}_inkomend${Platform.pathSeparator}')) continue;
    perMap.putIfAbsent(e.parent.path, () => []).add(e);
  }

  var gespleten = 0, geschreven = 0, overgeslagen = 0;
  for (final entry in perMap.entries) {
    final tellen = <int, int>{};
    final totaalVan = <String, int>{};
    for (final f in entry.value) {
      final t = readFlacTags(f)?.trackTotal ?? 0;
      totaalVan[f.path] = t;
      if (t > 0) tellen[t] = (tellen[t] ?? 0) + 1;
    }
    // Een ONTBREKEND totaal telt mee als afwijking, ook al is het geen tweede getal. De bibliotheek
    // rekent 0 als een eigen uitgave -- "een untagged rip die botst met een getagde is aantoonbaar
    // niet van dezelfde persing" -- en dus splitst één bestand zonder dat veld de plaat net zo hard.
    // Gemeten op Adele's 30: twaalf bestanden met 12, vier zonder iets, en toch twee tegels.
    //
    // Alleen niet als er niets te leren valt: staat de hele map op 0, dan is er geen meerderheid en
    // blijft alles zoals het is.
    if (tellen.isEmpty) continue;
    final wijktAf = entry.value.where((f) => totaalVan[f.path] != tellen.keys.first).length;
    if (tellen.length < 2 && wijktAf == 0) continue;
    gespleten++;

    final gesorteerd = tellen.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final naam = entry.key.split(Platform.pathSeparator).last;
    stdout.writeln('$naam: ${gesorteerd.map((e) => '${e.key}x${e.value}').join(', ')}');

    // Bij gelijkspel beslist de OUDERDOM, niet de alfabetische toevalligheid. Een half vervangen album
    // staat precies zo: vijf nummers van jouw persing en vijf verse downloads van een andere. De plaat
    // die er al stond hoort te winnen — dat is de plaat die je hebt. En dat is te meten: de bestanden
    // die er al lagen zijn ouder dan die van vanmiddag.
    var wint = gesorteerd.first.key;
    if (gesorteerd.length > 1 && gesorteerd[0].value == gesorteerd[1].value) {
      DateTime oudste(int totaal) {
        var t = DateTime.now();
        for (final f in entry.value) {
          if (totaalVan[f.path] != totaal) continue;
          try {
            final m = f.statSync().modified;
            if (m.isBefore(t)) t = m;
          } catch (_) {}
        }
        return t;
      }

      final a = gesorteerd[0].key, b = gesorteerd[1].key;
      wint = oudste(a).isBefore(oudste(b)) ? a : b;
      stdout.writeln('   gelijkspel — de oudste bestanden winnen, dus $wint');
      overgeslagen++;
    }
    for (final f in entry.value) {
      if (totaalVan[f.path] == wint) continue;
      final was = totaalVan[f.path];
      if (!schrijven) {
        stdout.writeln('   zou ${f.uri.pathSegments.last} van $was naar $wint zetten');
        continue;
      }
      final ok = await writeTagFields(f, {'TRACKTOTAL': '$wint', 'TOTALTRACKS': '$wint'});
      stdout.writeln('   ${f.uri.pathSegments.last}: $was -> $wint  ${ok ? '' : '(MISLUKT)'}');
      if (ok) geschreven++;
    }
  }

  stdout.writeln('');
  stdout.writeln('mappen met meer dan een uitgavetotaal: $gespleten'
      '${overgeslagen > 0 ? ' (waarvan $overgeslagen met gelijkspel overgeslagen)' : ''}');
  if (schrijven) {
    stdout.writeln('bestanden bijgewerkt: $geschreven');
  } else {
    stdout.writeln('niets geschreven — geef --doe mee om het echt te doen');
  }
}

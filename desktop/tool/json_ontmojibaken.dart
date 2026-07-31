/// Repareert dubbel gecodeerde tekst in een JSON-staatbestand van de app.
///
/// Voor `corrections.json`: de correcties die jij zelf hebt gemaakt liggen daar, en ze winnen van de
/// tags in het bestand. Staat er `MÃƒÂ¡s es amar` in, dan blijft de app dat tonen ook al is de FLAC zelf
/// schoon -- en dat was precies de verwarring: het gereedschap dat de tags nakeek vond niets.
///
/// Werkt op elk JSON-bestand van de app, want de reparatie zit in de waarden en niet in de vorm.
/// Sleutels blijven ongemoeid: die zijn identiteit (paden, id's), geen tekst om te lezen.
///
///     dart run tool/json_ontmojibaken.dart "%APPDATA%\DebridMusic\corrections.json"
///     dart run tool/json_ontmojibaken.dart "...corrections.json" --schrijf
///
/// SLUIT DE APP EERST als je schrijft: die houdt dit bestand in geheugen en schrijft het bij de
/// eerstvolgende wijziging weer weg, over de reparatie heen.
library;

import 'dart:convert';
import 'dart:io';

import 'tags_ontmojibaken.dart' show herstelVolledig;

/// Loopt door de hele boom en herstelt elke tekstwaarde.
///
/// Geeft terug wat er veranderde, als paar van voor en na, zodat de aanroeper het kan laten zien in
/// plaats van alleen een aantal te melden. Een reparatie die je niet kunt nalezen is een gok.
Object? herstelBoom(Object? knoop, List<(String, String)> gezien) {
  if (knoop is String) {
    final beter = herstelVolledig(knoop);
    if (beter != knoop) gezien.add((knoop, beter));
    return beter;
  }
  if (knoop is List) return [for (final k in knoop) herstelBoom(k, gezien)];
  if (knoop is Map) {
    return {for (final e in knoop.entries) e.key: herstelBoom(e.value, gezien)};
  }
  return knoop;
}

Future<void> main(List<String> args) async {
  final pad = args.isNotEmpty && !args.first.startsWith('--')
      ? args.first
      : '${Platform.environment['APPDATA']}\\DebridMusic\\corrections.json';
  final schrijven = args.contains('--schrijf');

  final f = File(pad);
  if (!f.existsSync()) {
    stdout.writeln('bestand bestaat niet: $pad');
    exitCode = 1;
    return;
  }

  // Als bytes gelezen en zelf als UTF-8 ontleed: de standaardlezer van Windows zou een BOM-loos
  // UTF-8-bestand als ANSI kunnen lezen, en dan meet dit gereedschap zijn eigen fout in plaats van die
  // van de app. Dat is eerder gebeurd bij het tellen van deze zelfde reeksen.
  final ruw = utf8.decode(await f.readAsBytes());
  final gezien = <(String, String)>[];
  final uit = herstelBoom(jsonDecode(ruw), gezien);

  if (gezien.isEmpty) {
    stdout.writeln('niets verminkt gevonden in $pad');
    return;
  }
  final uniek = {for (final (voor, na) in gezien) '$voor|$na': (voor, na)}.values;
  for (final (voor, na) in uniek) {
    stdout.writeln('  $voor  ->  $na');
  }
  stdout.writeln('');
  stdout.writeln('${gezien.length} waarden, ${uniek.length} verschillende');

  if (!schrijven) {
    stdout.writeln('DROOGLOOP -- er is niets veranderd. Voeg --schrijf toe om het echt te doen.');
    return;
  }

  final stempel = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '').substring(0, 15);
  final bak = File('$pad.bak-$stempel');
  await bak.writeAsBytes(await f.readAsBytes());
  await f.writeAsString(jsonEncode(uit));
  stdout.writeln('geschreven; het oude bestand staat in ${bak.path}');
}

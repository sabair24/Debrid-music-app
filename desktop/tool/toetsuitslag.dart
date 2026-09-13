// Zet de namen van de gevallen toetsen op de samenvattingspagina van een bouw.
//
// **Waarom dit bestaat.** Op 12-09-2026 om 15:51 verscheen de laatste APK: v3.9.367. Daarna tien
// uitleveringen lang niets meer, terwijl de Windows-installer wel elke keer kwam. De grens lag
// exact op win-v3.9.368 - de uitlevering met 6bcb80e erin, die de toetslijst van 140 naar 302
// bestanden bracht. Alle 302 zijn hier groen, op Windows met Flutter 3.35.6; de bouwstraat draait
// Linux met 3.41.9. Welke toets daar viel was van buitenaf niet te zien: daarvoor moest je het
// logboek van de stap openklikken.
//
// Een rode stap zegt alleen DAT het stuk is. Dit zegt WAT. `flutter test --file-reporter` schrijft
// elke toets als een regel JSON weg; dit leest die regels en zet de namen, met bestand en reden, op
// de samenvattingspagina van de bouw - de pagina die je ziet zonder iets open te klikken.
//
// Uitvoer is Markdown op stdout, bedoeld voor `>> "$GITHUB_STEP_SUMMARY"`.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final pad = args.isEmpty ? 'uitslag.json' : args.first;
  final bestand = File(pad);

  // Geen bestand of een leeg bestand betekent dat het stuk liep voordat er ook maar een toets klaar
  // was. Dat is zelf al het antwoord, dus zeg dat in plaats van niets.
  if (!bestand.existsSync() || bestand.lengthSync() == 0) {
    stdout.writeln('## Geen toetsuitslag');
    stdout.writeln();
    stdout.writeln('Er is geen `$pad` geschreven. Dan is het misgegaan voor of tijdens het laden '
        'van de toetsen - denk aan een bestand dat niet compileert.');
    return;
  }

  final namen = <int, String>{};
  final bestanden = <int, String>{};
  final gevallen = <int>[];
  final redenen = <int, String>{};

  for (final regel in bestand.readAsLinesSync()) {
    if (regel.trim().isEmpty) continue;
    final Map<String, dynamic> r;
    try {
      r = jsonDecode(regel) as Map<String, dynamic>;
    } catch (_) {
      continue; // Een halve regel aan het eind is geen reden om niets te melden.
    }
    switch (r['type']) {
      case 'testStart':
        final t = r['test'] as Map<String, dynamic>;
        final id = t['id'] as int;
        final naam = (t['name'] as String?) ?? '(naamloos)';
        final url = (t['url'] as String?) ?? (t['root_url'] as String?) ?? '';
        // Een bestand dat niet compileert krijgt geen url mee: er is dan ook geen toets om bij te
        // horen. Wat er wel is, is een verzonnen toets die "loading <pad>" heet. Juist dat geval is
        // het belangrijkste dat deze stap moet kunnen benoemen, dus haal het bestand daaruit.
        if (url.isEmpty && naam.startsWith('loading ')) {
          namen[id] = 'kon niet geladen worden';
          bestanden[id] = naam.substring(8).split('/').last;
        } else {
          namen[id] = naam;
          bestanden[id] = url.isEmpty ? '(onbekend)' : url.split('/').last;
        }
      case 'testDone':
        if (r['result'] != 'success' && r['skipped'] != true) {
          gevallen.add(r['testID'] as int);
        }
      case 'error':
        final id = r['testID'] as int;
        redenen[id] ??= ((r['error'] as String?) ?? '').trim();
    }
  }

  if (gevallen.isEmpty) {
    stdout.writeln('## Geen gevallen toets');
    stdout.writeln();
    stdout.writeln('Alle toetsen die gedraaid hebben zijn geslaagd. Het is dus in een andere stap '
        'misgegaan, of het proces is onderweg afgebroken.');
    return;
  }

  // Op bestand groeperen: bij tien gevallen toetsen in een bestand is dat het antwoord, en niet
  // tien losse namen.
  final perBestand = <String, List<int>>{};
  for (final id in gevallen) {
    perBestand.putIfAbsent(bestanden[id] ?? '(onbekend)', () => []).add(id);
  }

  stdout.writeln('## ${gevallen.length} toets${gevallen.length == 1 ? '' : 'en'} gevallen, '
      'in ${perBestand.length} bestand${perBestand.length == 1 ? '' : 'en'}');
  stdout.writeln();
  final sleutels = perBestand.keys.toList()..sort();
  for (final b in sleutels) {
    stdout.writeln('### `$b`');
    stdout.writeln();
    for (final id in perBestand[b]!) {
      stdout.writeln('* **${namen[id] ?? id}**');
      final reden = redenen[id];
      if (reden != null && reden.isNotEmpty) {
        // Bij een compileerfout staat de zin die je wilt lezen midden in een regel die begint met
        // "Compilation failed for testPath=<heel lang absoluut pad>". Het bestand staat al in de
        // kop, dus knip alles voor "Error:" weg; wat overblijft is de fout zelf.
        final regels =
            reden.split('\n').map((r) => r.trim()).where((r) => r.isNotEmpty).toList();
        var eerste = regels.isEmpty ? '' : regels.first;
        for (final r in regels) {
          final i = r.indexOf('Error:');
          if (i >= 0) {
            eerste = r.substring(i);
            break;
          }
        }
        stdout.writeln('  <br>`${eerste.length > 160 ? '${eerste.substring(0, 160)}...' : eerste}`');
      }
    }
    stdout.writeln();
  }
}

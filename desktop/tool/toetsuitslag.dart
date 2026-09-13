// Zet de namen van de gevallen toetsen op de samenvattingspagina EN in de annotaties van een bouw.
//
// **Waarom dit bestaat.** Op 12-09-2026 om 15:51 verscheen de laatste APK: v3.9.367. Daarna tien
// uitleveringen lang niets, terwijl de Windows-installer wel elke keer kwam. De grens lag exact op
// win-v3.9.368 - de uitlevering met 6bcb80e erin, die de toetslijst van 140 naar 302 bestanden
// bracht. Alle 302 zijn hier groen, op Windows met Flutter 3.35.6; de bouwstraat draait Linux met
// 3.41.9, en daar vielen er op 13-09-2026 zes: "3140 tests passed, 6 failed, 13 skipped."
//
// **Waarom annotaties en niet alleen de samenvatting.** Van een publieke repo zijn de stapnamen en
// de ANNOTATIES zonder inloggen op te vragen (`/check-runs/<id>/annotations`); het logboek vraagt
// beheerrechten en de samenvattingspagina is nergens als tekst op te halen. Wie er dus niet zelf in
// kan klikken - een assistent bijvoorbeeld - ziet alleen wat er als annotatie uit komt. Vandaar
// allebei: de samenvatting voor wie kijkt, de annotaties voor wie leest.
//
// Bij een bouw schrijft dit naar $GITHUB_STEP_SUMMARY en print het `::error::`-regels; los van een
// bouw komt de Markdown gewoon op stdout, zodat het hier na te meten valt.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final pad = args.isEmpty ? 'uitslag.json' : args.first;
  final bestand = File(pad);
  final md = StringBuffer();
  final meldingen = <String>[];

  // Geen bestand of een leeg bestand betekent dat het stuk liep voordat er ook maar een toets klaar
  // was. Dat is zelf al het antwoord, dus zeg dat in plaats van niets.
  if (!bestand.existsSync() || bestand.lengthSync() == 0) {
    md.writeln('## Geen toetsuitslag');
    md.writeln();
    md.writeln('Er is geen `$pad` geschreven. Dan is het misgegaan voor of tijdens het laden '
        'van de toetsen - denk aan een bestand dat niet compileert.');
    meldingen.add(_melding('geen uitslag', 'Er is geen $pad geschreven; het ging mis voor of '
        'tijdens het laden van de toetsen.'));
    _leverAf(md, meldingen);
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
        // het belangrijkste dat dit moet kunnen benoemen, dus haal het bestand daaruit.
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
    md.writeln('## Geen gevallen toets');
    md.writeln();
    md.writeln('Alle toetsen die gedraaid hebben zijn geslaagd. Het is dus in een andere stap '
        'misgegaan, of het proces is onderweg afgebroken.');
    _leverAf(md, meldingen);
    return;
  }

  // Op bestand groeperen: bij tien gevallen toetsen in een bestand is dat het antwoord, en niet
  // tien losse namen.
  final perBestand = <String, List<int>>{};
  for (final id in gevallen) {
    perBestand.putIfAbsent(bestanden[id] ?? '(onbekend)', () => []).add(id);
  }

  md.writeln('## ${gevallen.length} toets${gevallen.length == 1 ? '' : 'en'} gevallen, '
      'in ${perBestand.length} bestand${perBestand.length == 1 ? '' : 'en'}');
  md.writeln();
  final sleutels = perBestand.keys.toList()..sort();
  for (final b in sleutels) {
    md.writeln('### `$b`');
    md.writeln();
    for (final id in perBestand[b]!) {
      final naam = namen[id] ?? '$id';
      final kort = _kortereReden(redenen[id]);
      md.writeln('* **$naam**');
      if (kort.isNotEmpty) md.writeln('  <br>`$kort`');
      meldingen.add(_melding(b, kort.isEmpty ? naam : '$naam - $kort'));
    }
    md.writeln();
  }

  _leverAf(md, meldingen);
}

/// Een regel is genoeg om te herkennen wat er aan de hand is; de rest staat in het logboek.
///
/// Bij een compileerfout staat de zin die je wilt lezen midden in een regel die begint met
/// `Compilation failed for testPath=...` met een heel lang absoluut pad. Het bestand staat al in
/// de kop, dus knip alles voor "Error:" weg; wat overblijft is de fout zelf.
String _kortereReden(String? reden) {
  if (reden == null || reden.isEmpty) return '';
  final regels = reden.split('\n').map((r) => r.trim()).where((r) => r.isNotEmpty).toList();
  var eerste = regels.isEmpty ? '' : regels.first;
  for (final r in regels) {
    final i = r.indexOf('Error:');
    if (i >= 0) {
      eerste = r.substring(i);
      break;
    }
  }
  return eerste.length > 160 ? '${eerste.substring(0, 160)}...' : eerste;
}

/// Een `::error::`-regel zoals GitHub hem als annotatie oppikt.
String _melding(String titel, String tekst) =>
    '::error title=${_ontsnap(titel, eigenschap: true)}::${_ontsnap(tekst)}';

String _ontsnap(String s, {bool eigenschap = false}) {
  var uit = s.replaceAll('%', '%25').replaceAll('\r', '%0D').replaceAll('\n', '%0A');
  if (eigenschap) uit = uit.replaceAll(':', '%3A').replaceAll(',', '%2C');
  return uit;
}

/// De samenvatting voor wie kijkt, de annotaties voor wie leest.
void _leverAf(StringBuffer md, List<String> meldingen) {
  final sam = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (sam != null && sam.isNotEmpty) {
    File(sam).writeAsStringSync('$md\n', mode: FileMode.append);
  } else {
    stdout.write(md);
  }
  // GitHub toont er hoogstens tien per stap. Meer dan tien gevallen toetsen is trouwens zelf al het
  // antwoord, en dan staat de volledige lijst nog op de samenvattingspagina.
  for (final m in meldingen.take(10)) {
    stdout.writeln(m);
  }
}

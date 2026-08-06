// Kiest nummers waarvan de spectrumproef het antwoord al weet, verspreid over artiesten.
//
//  ECHT  = `boven: vol`  -- er STAAT inhoud boven 22 kHz, en dat laat opschalen nooit achter.
//  NEP   = `boven: leeg` -- claimt boven 48 kHz, maar er is niets boven 22 kHz.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final pad = [Platform.environment['APPDATA'], 'DebridMusic', 'echtheid_oordelen.json']
      .join(Platform.pathSeparator);
  final d = jsonDecode(File(pad).readAsStringSync()) as Map<String, dynamic>;
  final perGroep = <String, List<List<String>>>{'echt': [], 'nep': []};
  final gezien = <String, int>{};

  d.forEach((p, raw) {
    final o = raw as Map<String, dynamic>;
    final groep = o['boven'] == 'vol' ? 'echt' : (o['boven'] == 'leeg' ? 'nep' : null);
    if (groep == null) return;
    final delen = p.split(Platform.pathSeparator);
    if (delen.length < 3) return;
    final artiest = delen[delen.length - 3];
    var titel = delen.last.replaceAll('.flac', '');
    titel = titel.replaceFirst(RegExp(r'^\d+\s*[-.]\s*'), '');
    // Versievarianten weglaten: een remix heeft zijn eigen aanbod en vertroebelt de telling.
    if (titel.contains('(') || titel.contains('remix') || titel.contains('version')) return;
    if (artiest.contains('downloads') || artiest.length < 3) return;
    // Hoogstens twee per artiest, anders meet je vooral één plaat.
    final sleutel = '$groep|$artiest';
    if ((gezien[sleutel] ?? 0) >= 2) return;
    gezien[sleutel] = (gezien[sleutel] ?? 0) + 1;
    perGroep[groep]!.add([artiest, titel, p]);
  });

  final uit = <Map<String, String>>[];
  for (final g in ['echt', 'nep']) {
    for (final r in perGroep[g]!.take(int.parse(args[0]))) {
      uit.add({'groep': g, 'artiest': r[0], 'titel': r[1], 'pad': r[2]});
    }
  }
  stdout.writeln(jsonEncode(uit));
}

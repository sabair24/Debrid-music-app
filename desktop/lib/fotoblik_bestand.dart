/// Wat de kop van een artiestpagina over een foto weet (waar de gezichten staan), bewaard tussen twee
/// starts — zie [FotoBlikGeheugen] in `ui/kopfoto.dart`.
///
/// Apart van `kopfoto.dart`, zodat dat bestand geen schijf kent en een toets er niets mee wegschrijft:
/// alleen `main()` plugt dit in, naar het model van `bewaarScanmatenIn` in `scanmaat.dart`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ui/kopfoto.dart' show FotoBlikGeheugen;

/// Hoeveel foto's er onthouden worden. Een regel is zo'n zeventig bytes; vol valt de oudste eraf.
const kFotoBlikkenBewaard = 3000;

final Map<String, String> _kaart = {};
File? _bestand;
Timer? _schrijfKlok;

/// Lees [f] (als hij er is) en laat de kop daar voortaan in kijken en naar schrijven.
Future<void> bewaarFotoBlikkenIn(File f) async {
  _bestand = f;
  _kaart.clear();
  try {
    if (await f.exists()) {
      final j = jsonDecode(await f.readAsString());
      if (j is Map) {
        for (final e in j.entries) {
          if (e.key is String && e.value is String) _kaart[e.key as String] = e.value as String;
        }
      }
    }
  } catch (_) {/* een kapot bestand is een leeg geheugen: dan wordt er gewoon opnieuw gekeken */}
  FotoBlikGeheugen.lees = (s) => _kaart[s];
  FotoBlikGeheugen.schrijf = (s, w) {
    _kaart.remove(s);
    _kaart[s] = w; // achteraan is het jongst
    while (_kaart.length > kFotoBlikkenBewaard) {
      _kaart.remove(_kaart.keys.first);
    }
    // Samen weggeschreven: een pagina met tien artiesten bekijkt tien foto's in een paar tellen.
    _schrijfKlok?.cancel();
    _schrijfKlok = Timer(const Duration(seconds: 2), _schrijf);
  };
}

Future<void> _schrijf() async {
  final f = _bestand;
  if (f == null) return;
  try {
    final tijdelijk = File('${f.path}.nieuw');
    await tijdelijk.writeAsString(jsonEncode(_kaart), flush: true);
    await tijdelijk.rename(f.path);
  } catch (_) {/* niet bewaard is volgende keer opnieuw kijken, geen fout */}
}

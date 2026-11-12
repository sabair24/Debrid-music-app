/// Nummers waarvoor de cd-jacht geen cd meer zoekt, omdat jij de cd-versie verwijderde die hij vond.
///
/// Saber, 12-11-2026, bij Rachid Taha "Diwân (cd)": *"deze heb ik verwijderd nu al 2 maal, maar blijft terug komen ??
/// ik wil die niet meer"*. Zijn "Ya Rayah" staat in "Diwân" als studio-kopie; de cd-jacht ([cdjachtVegen], zijn regel
/// van 05-11: "de cd kwaliteit mag zoiezo blijven") haalde er een cd bij als versie, in de map "Diwân (cd)". Verwijderde
/// hij dat album, dan had het nummer weer geen cd, en bij de volgende ronde haalde de jacht hem gewoon opnieuw — en de
/// terugzetter kon hem uit _dubbel terugzetten. Nu onthoudt de pc het: een cd-versie die jij weggooit
/// ([LibraryStore.removeTracks]), zoekt de jacht niet opnieuw, en de terugzetter zet hem niet terug.
///
/// **Vraag je zelf om cd-kwaliteit** ("Download in cd-kwaliteit"), dan vervalt het voor die nummers.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'paths.dart';

class CdNietMeer {
  CdNietMeer({this.bestand});

  /// Waar het op schijf staat; null in een toets.
  final File? bestand;

  final Set<String> _paden = {};

  static String _sleutel(String pad) => pad.replaceAll('\\', '/').toLowerCase();

  /// Zoekt de cd-jacht voor dit nummer geen cd meer?
  bool bevat(String pad) => _paden.contains(_sleutel(pad));

  Iterable<String> get alle => _paden;

  /// Deze nummers niet meer: je gooide hun cd-versie weg.
  Future<void> zet(Iterable<String> paden) async {
    final voor = _paden.length;
    _paden.addAll(paden.map(_sleutel));
    if (_paden.length != voor) await bewaar();
  }

  /// Weer wel: je vroeg zelf om cd-kwaliteit.
  Future<void> haalWeg(Iterable<String> paden) async {
    final voor = _paden.length;
    _paden.removeAll(paden.map(_sleutel));
    if (_paden.length != voor) await bewaar();
  }

  Future<void> laad() async {
    final f = bestand;
    if (f == null) return;
    try {
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is List) _paden.addAll([for (final p in j) if (p is String) _sleutel(p)]);
    } catch (e) {
      debugPrint('cd_niet_meer.json onleesbaar: $e');
    }
  }

  Future<void> bewaar() async {
    final f = bestand;
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(_paden.toList()..sort()));
      await tmp.rename(f.path);
    } catch (e) {
      debugPrint('cd_niet_meer.json niet bewaard: $e');
    }
  }
}

/// Het bestand. **In een toets niets naar schijf**: de appmap is daar die van de echte app.
File? cdNietMeerBestand() => Platform.environment.containsKey('FLUTTER_TEST')
    ? null
    : File('$appDir${Platform.pathSeparator}cd_niet_meer.json');

/// Eén voor de hele app (op de pc).
final CdNietMeer cdNietMeer = CdNietMeer(bestand: cdNietMeerBestand());

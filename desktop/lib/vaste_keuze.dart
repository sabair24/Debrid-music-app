/// Welke bestanden de gebruiker ZELF uit de Soulseek-lijst heeft gekozen.
///
/// Er is één regel: zo'n bestand verliest nooit van een automatische regel. Dat klinkt klein, maar het
/// was de helft van een klacht die twee keer terugkwam. Bij Joe Dassin / *L'été indien* is de best
/// gerangschikte kopie een ánder nummer, dus koos Saber er zelf een uit de lijst — en die stond later
/// in `_dubbel`. Niet weg, wel weggeschoven, en zonder dat iemand het merkte.
///
/// De reden is [firstIsBetter], die als laatste grond op GROOTTE beslist. Een 4:16-versie van een
/// ander nummer is nu eenmaal groter dan de 3:37 die je wilde hebben. Elke opruimweg in de app loopt
/// langs die ene functie — het filen van een download, Opruimen, de dubbelvegers per album en over de
/// hele bibliotheek — en dat is precies waarom de bescherming DAAR zit en niet bij de vijf aanroepers.
/// Eén plek is niet te vergeten; vijf wel. Deze sessie is begonnen met een fout die precies zo ontstond.
///
/// Wat dit NIET is: een slot op het bestand. Twee handmatige keuzes onderling worden nog gewoon op
/// kwaliteit vergeleken — dan heeft de gebruiker twee keer gekozen en is er geen voorkeur af te lezen.
/// En [vergeetVasteKeuze] haalt de bescherming er weer af.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'paths.dart';

/// Windows kent geen hoofdlettergevoelige paden en mengt de scheidingstekens, dus vergelijken op de
/// rauwe tekst laat een bestand door de bescherming heen zodra iets het pad anders opschrijft.
String _sleutel(String pad) =>
    pad.replaceAll('/', Platform.pathSeparator).replaceAll('\\', Platform.pathSeparator).toLowerCase();

final Set<String> _keuzes = <String>{};
bool _geladen = false;

File get _bestand => File('$appDir${Platform.pathSeparator}vaste_keuzes.json');

/// Inlezen bij het opstarten. Faalt dit, dan blijft de lijst leeg en gedraagt de app zich als vroeger
/// — vervelend, maar niet erger dan dat.
Future<void> laadVasteKeuzes() async {
  _geladen = true;
  try {
    final f = _bestand;
    if (!await f.exists()) return;
    final raw = jsonDecode(await f.readAsString());
    if (raw is! List) return;
    _keuzes
      ..clear()
      ..addAll(raw.whereType<String>().map(_sleutel));
  } catch (e) {
    debugPrint('vaste_keuzes.json onleesbaar: $e');
  }
}

Future<void> _bewaar() async {
  try {
    final f = _bestand;
    await f.parent.create(recursive: true);
    // Via een tijdelijk bestand: een half geschreven lijst is erger dan geen lijst, want dan
    // verdwijnt de bescherming van bestanden die er wél in stonden.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(_keuzes.toList()..sort()));
    await tmp.rename(f.path);
  } catch (e) {
    debugPrint('vaste_keuzes.json niet te bewaren: $e');
  }
}

/// Heeft de gebruiker dit bestand zelf gekozen?
bool isVasteKeuze(String pad) => _keuzes.contains(_sleutel(pad));

/// Er is er minstens één, dus de bescherming kan ergens aanslaan. Voor de uitleg in de vegers, die
/// anders bij elk paar naar deze lijst zou vragen.
bool get erZijnVasteKeuzes => _keuzes.isNotEmpty;

Future<void> onthoudVasteKeuze(String pad) async {
  if (!_keuzes.add(_sleutel(pad))) return;
  await _bewaar();
}

Future<void> vergeetVasteKeuze(String pad) async {
  if (!_keuzes.remove(_sleutel(pad))) return;
  await _bewaar();
}

/// Het bestand is verplaatst; de bescherming hoort mee te verhuizen.
///
/// Zonder dit was de bescherming precies één keer geldig: het filen van een download verplaatst het
/// bestand van de landingsmap naar `Albums/…`, en daarna wees de lijst naar een pad dat niet meer
/// bestaat. Aangeroepen vanuit de ENE verplaatsfunctie in organize.dart, om dezelfde reden dat de
/// bescherming zelf in [firstIsBetter] zit.
void herNoemVasteKeuze(String van, String naar) {
  if (!_keuzes.remove(_sleutel(van))) return;
  _keuzes.add(_sleutel(naar));
  unawaited(_bewaar());
}

/// Tests delen dit proces, en een gevulde lijst uit de vorige test laat de volgende iets anders meten
/// dan hij denkt.
@visibleForTesting
void resetVasteKeuzesForTest() {
  _keuzes.clear();
  _geladen = false;
}

/// Is de lijst al ingelezen? Zo niet, dan beschermt hij niets — dat hoort een test te kunnen zien.
@visibleForTesting
bool get vasteKeuzesGeladen => _geladen;

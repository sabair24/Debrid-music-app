/// Wat er van elk bestand gemeten is, synchroon op te vragen.
///
/// Nodig omdat [firstIsBetter] synchroon is en er geen ffmpeg mag starten terwijl er een download
/// geplaatst wordt. Dezelfde vorm als `vaste_keuze.dart`: één kaart op moduleniveau, inlezen bij het
/// opstarten, wegschrijven via een tijdelijk bestand, en paden hoofdletterongevoelig vergelijken op
/// Windows en macOS — want daar is `Foo.flac` hetzelfde bestand als `foo.flac`, en dat verschil kostte
/// vandaag bijna een vastgezette persing.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'echtheid.dart';
import 'paths.dart';

String _sleutel(String pad) => (Platform.isWindows || Platform.isMacOS)
    ? pad.replaceAll('/', Platform.pathSeparator).replaceAll('\\', Platform.pathSeparator).toLowerCase()
    : pad;

final Map<String, Echtheidsoordeel> _oordelen = {};
bool _geladen = false;

File get _bestand => File('$appDir${Platform.pathSeparator}echtheid_oordelen.json');

/// Waar het inlezen of bewaren op stukliep. Nooit stil falen.
String? laatsteFout;

Future<void> laadEchtheid() async {
  _geladen = true;
  try {
    final f = _bestand;
    if (!await f.exists()) return;
    final raw = jsonDecode(await f.readAsString());
    if (raw is! Map) return;
    _oordelen.clear();
    for (final e in raw.entries) {
      final v = e.value;
      if (v is! Map) continue;
      final o = Echtheidsoordeel.fromJson(Map<String, dynamic>.from(v));
      if (o != null) _oordelen[_sleutel(e.key.toString())] = o;
    }
  } catch (e) {
    laatsteFout = 'echtheid_oordelen.json onleesbaar: $e';
  }
}

Future<void> _bewaar() async {
  try {
    final f = _bestand;
    await f.parent.create(recursive: true);
    final inhoud = jsonEncode({for (final e in _oordelen.entries) e.key: e.value.toJson()});
    final tmp = File('${f.path}.tmp');
    try {
      await tmp.writeAsString(inhoud);
      await tmp.rename(f.path);
    } catch (_) {
      // Tweede kans langs de weg die het aantoonbaar wél doet. Zie de guard in soulseek.dart: op deze
      // pc is tmp+rename niet altijd betrouwbaar, en een stil verloren meting is erger dan een bestand
      // dat ooit half geschreven wordt.
      await f.writeAsString(inhoud, flush: true);
    }
  } catch (e) {
    laatsteFout = 'echtheid_oordelen.json niet te bewaren: $e';
  }
}

/// Wat er van dit bestand gemeten is, of null als het nooit gemeten is.
Echtheidsoordeel? gemeten(String pad) => _oordelen[_sleutel(pad)];

/// Alleen wat BEWEZEN is. Een ongemeten of onbeoordeelbaar bestand is nadrukkelijk niet nep — anders
/// zou het draaien van een veegbeurt de halve bibliotheek herordenen.
bool bewezenNep(String pad) => _oordelen[_sleutel(pad)]?.isNep ?? false;

int get aantalGemeten => _oordelen.length;
bool get isGeladen => _geladen;

Future<void> onthoudOordeel(String pad, Echtheidsoordeel o) async {
  _oordelen[_sleutel(pad)] = o;
  await _bewaar();
}

/// Het bestand is verplaatst; de meting hoort mee te verhuizen. Uit dezelfde `_move` als
/// [herNoemVasteKeuze], en om dezelfde reden: zonder dit geldt een meting precies één keer.
void herNoemOordeel(String van, String naar) {
  final o = _oordelen.remove(_sleutel(van));
  if (o == null) return;
  _oordelen[_sleutel(naar)] = o;
  unawaited(_bewaar());
}

void vergeetOordeel(String pad) {
  if (_oordelen.remove(_sleutel(pad)) != null) unawaited(_bewaar());
}

/// Tests delen dit proces.
void resetEchtheidVoorTest() {
  _oordelen.clear();
  _geladen = false;
  laatsteFout = null;
}

// Waarom een nummer op dit toestel staat (Saber, 28-10-2026): zelf bewaard, als favoriet, of omdat een
// afspeellijst die je op dit toestel houdt het bevat. Haal je een nummer uit je favorieten of uit zo'n lijst,
// dan gaat het "vanzelf weg" van je gsm — tenzij het er ook om een andere reden staat.
//
// Wat al op het toestel stond voor dit bestond, heeft geen reden: dat telt als zelf bewaard.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'paths.dart';

/// Zelf bewaard: een album, een selectie, een artiest.
const kRedenZelf = 'zelf';

/// Een favoriet (een hartje).
const kRedenFavoriet = 'favoriet';

/// Een afspeellijst die je op dit toestel houdt.
String redenLijst(String id) => 'lijst:$id';

class ToestelRedenen extends ChangeNotifier {
  ToestelRedenen({this.bestandsnaam = 'toestel_redenen.json'});

  final String bestandsnaam;

  /// Per pad de redenen. Een pad zonder regel hier, maar wél op het toestel, is zelf bewaard.
  final Map<String, Set<String>> _redenen = {};

  /// De afspeellijsten die je op dit toestel houdt (hun id's).
  final Set<String> _lijsten = {};

  File get _bestand => appFile(bestandsnaam);

  Future<void> laad() async {
    try {
      final f = _bestand;
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      final r = j['redenen'];
      if (r is Map) {
        r.forEach((k, v) {
          if (k is String && v is List) _redenen[k] = {for (final x in v) '$x'};
        });
      }
      final l = j['lijsten'];
      if (l is List) _lijsten.addAll([for (final x in l) '$x']);
    } catch (e) {
      // Onleesbaar is leeg: dan telt alles op het toestel als zelf bewaard, en gaat er niets vanzelf weg.
      debugPrint('Toestelredenen onleesbaar: $e');
    }
  }

  Future<void> _bewaar() async {
    try {
      await _bestand.writeAsString(jsonEncode({
        'redenen': {for (final e in _redenen.entries) e.key: e.value.toList()..sort()},
        'lijsten': _lijsten.toList()..sort(),
      }));
    } catch (e) {
      debugPrint('Toestelredenen niet bewaard: $e');
    }
  }

  Set<String> redenenVan(String pad) => Set.unmodifiable(_redenen[pad] ?? const <String>{});

  /// [reden] erbij voor [paden].
  ///
  /// [alOpToestel]: staat een pad er al zonder reden (van vóór de redenen), dan was het zelf bewaard — dat komt er
  /// eerst bij. Anders zou een hartje erop en er weer af een nummer meenemen dat je zelf bewaarde.
  Future<void> voegToe(Iterable<String> paden, String reden, {bool Function(String pad)? alOpToestel}) async {
    var veranderd = false;
    for (final p in paden) {
      if (!_redenen.containsKey(p) && reden != kRedenZelf && (alOpToestel?.call(p) ?? false)) {
        _redenen[p] = {kRedenZelf};
      }
      veranderd = (_redenen.putIfAbsent(p, () => {})).add(reden) || veranderd;
    }
    if (!veranderd) return;
    notifyListeners();
    await _bewaar();
  }

  /// [reden] weg voor [paden]. Geeft de paden terug waar daarna GEEN reden meer over is — die mogen van het
  /// toestel. Een pad dat hier niet stond (van vóór de redenen), was zelf bewaard en blijft.
  Future<List<String>> haalWeg(Iterable<String> paden, String reden) async {
    final leeg = <String>[];
    var veranderd = false;
    for (final p in paden) {
      final r = _redenen[p];
      if (r == null || !r.remove(reden)) continue;
      veranderd = true;
      if (r.isEmpty) {
        _redenen.remove(p);
        leeg.add(p);
      }
    }
    if (veranderd) {
      notifyListeners();
      await _bewaar();
    }
    return leeg;
  }

  /// Alles weg voor [paden]: je haalde ze zelf van het toestel.
  Future<void> vergeet(Iterable<String> paden) async {
    var veranderd = false;
    for (final p in paden) {
      veranderd = _redenen.remove(p) != null || veranderd;
    }
    if (!veranderd) return;
    notifyListeners();
    await _bewaar();
  }

  /// Welke paden staan er om [reden]?
  Set<String> padenMet(String reden) => {
        for (final e in _redenen.entries)
          if (e.value.contains(reden)) e.key,
      };

  /// Elke reden die nog ergens in gebruik is.
  Set<String> get alleRedenen => {for (final r in _redenen.values) ...r};

  bool houdtLijst(String id) => _lijsten.contains(id);

  Set<String> get lijsten => Set.unmodifiable(_lijsten);

  Future<void> zetLijst(String id, bool aan) async {
    final veranderd = aan ? _lijsten.add(id) : _lijsten.remove(id);
    if (!veranderd) return;
    notifyListeners();
    await _bewaar();
  }
}

/// De redenen van dit toestel, voor de hele app (zie main en de selectiebalk).
final toestelRedenen = ToestelRedenen();

// Nummers kiezen (Saber, 28-10-2026: "ik moet kunnen opslaan op men gsm vanaf tracks, kunnen selecteren").
//
// Lang drukken op een nummer begint het kiezen (op een aanraakscherm; op een tv blijft lang OK het menu); daarna
// tikt elk nummer zich aan of uit. Bovenaan staat dan een balk met "Op dit toestel", "Van dit toestel halen",
// "Alles kiezen" en, bij één nummer, het menu van dat nummer.
import 'package:flutter/foundation.dart';

import '../models.dart';

class NummerKeuze extends ChangeNotifier {
  final Map<String, Track> _gekozen = {};
  bool _actief = false;

  /// Wat "Alles kiezen" kiest: de lijst die op het scherm stond toen je begon — Tracks met je zoekterm en filter
  /// (de zoekresultaten), of de nummers van een album.
  List<Track> Function()? _alles;

  bool get actief => _actief;
  int get aantal => _gekozen.length;
  bool isGekozen(String pad) => _gekozen.containsKey(pad);
  List<Track> get gekozen => List.unmodifiable(_gekozen.values);
  bool get kanAllesKiezen => _alles != null;

  /// Begin met [t], in de lijst die [alles] geeft.
  void begin(Track t, {List<Track> Function()? alles}) {
    _actief = true;
    _alles = alles;
    _gekozen
      ..clear()
      ..[t.path] = t;
    notifyListeners();
  }

  /// [t] aan of uit.
  void wissel(Track t) {
    if (_gekozen.remove(t.path) == null) _gekozen[t.path] = t;
    notifyListeners();
  }

  /// Alles uit de lijst waarin je begon — of, staat alles al aan, alles weer uit.
  void kiesAlles() {
    final lijst = _alles?.call() ?? const <Track>[];
    if (lijst.isNotEmpty && lijst.every((t) => _gekozen.containsKey(t.path))) {
      _gekozen.clear();
    } else {
      for (final t in lijst) {
        _gekozen[t.path] = t;
      }
    }
    notifyListeners();
  }

  void stop() {
    if (!_actief && _gekozen.isEmpty) return;
    _actief = false;
    _alles = null;
    _gekozen.clear();
    notifyListeners();
  }
}

/// Eén keuze tegelijk, voor de hele app: de balk staat in de schil, de rijen staan in Tracks en op een albumpagina.
final nummerKeuze = NummerKeuze();

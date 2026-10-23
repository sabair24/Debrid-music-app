/// Een radio op een speaker (Saber, 22-10-2026: "pc draait, speaker speelt"): de [Radiospeler] waarop de
/// radio van de pc speelt als hij naar een Sonos of de KEF moet. De pc zelf blijft stil.
///
/// **Hoe.** De radio (`radio.dart`) zoekt, haalt en keurt zoals altijd; wat hij in de rij zet, gaat als id's van
/// de pc naar de cast-sessie van de speaker (`CastManager.play` met `radio:`). De speaker schuift zelf door —
/// naadloos waar hij dat kan — en deze kant volgt hem: de plek, of hij speelt, en de rij. Is de rij op, dan
/// blijft de sessie open ("droog") en vult de radio aan; "volgende" op het laatste nummer zegt "wil verder".
///
/// **Eén rij.** Wie op de speakerzone iets "hierna" zet, verplaatst of weghaalt, verandert de rij van de
/// speaker; die van de radio volgt ([_volgRij]): dezelfde [RadioItem]s waar ze bleven (de radio herkent ze aan
/// wie ze zijn), nieuwe voor wat erbij kwam.
///
/// Spelen terwijl een nummer nog binnenkomt kan hier niet: dat adres bestaat alleen op de pc (127.0.0.1).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'lan/cast_manager.dart';
import 'models.dart';
import 'player.dart';

class SpeakerRadio extends ChangeNotifier implements Radiospeler {
  SpeakerRadio({
    required this.cast,
    required this.speaker,
    required this.idVan,
    required this.naam,
    int Function()? klokMs,
  }) : _klokMs = klokMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final CastManager cast;

  /// Het renderer-id van de speaker.
  final String speaker;

  /// Is [zoneId] de zone van deze speaker (`spk:<id>`, zie `lan/zones.dart`)? Dan gaan de duimen daar over deze radio.
  bool speeltOpZone(String zoneId) => zoneId == 'spk:$speaker';

  /// Het id van een nummer op de pc (zoals de cast het kent), of null als het daar niet staat.
  final String? Function(Track t) idVan;

  /// Hoe de radio heet (voor de zone), gelezen op het moment dat hij begint.
  final String Function() naam;
  final int Function() _klokMs;

  final List<RadioItem> _rij = [];
  final Expando<String> _id = Expando('speaker-radio-id');
  int _index = 0;
  bool _wilVerder = false;
  bool _weg = true;
  StreamSubscription<({String id, bool wilVerder, bool weg})>? _sub;

  @override
  Future<List<RadioItem>> Function()? radioExtend;
  @override
  void Function(List<RadioItem> gespeeld)? bijRadioEinde;
  @override
  void Function(RadioItem item, {required bool bestand})? bijRadioOverslaan;

  @override
  List<RadioItem> get radioQueue => _rij;
  @override
  int get radioIndex => _index;
  @override
  bool get radioDroog => cast.isDroog(speaker);
  @override
  bool get wilVerder => _wilVerder;

  ({bool speelt, int positieMs, int duurMs, int opMs})? get _stand {
    for (final s in cast.laatsteStanden) {
      if (s.id == speaker) return (speelt: s.speelt, positieMs: s.positieMs, duurMs: s.duurMs, opMs: s.opMs);
    }
    return null;
  }

  @override
  bool get playing => !_weg && (_stand?.speelt ?? false) && !radioDroog;
  @override
  Duration get duration => Duration(milliseconds: _stand?.duurMs ?? 0);
  @override
  Duration get positieErgens {
    final s = _stand;
    if (s == null) return Duration.zero;
    return Duration(milliseconds: s.positieMs + (s.speelt ? _klokMs() - s.opMs : 0));
  }

  /// Alleen wat de speaker kan spelen: nummers die op de pc staan.
  List<RadioItem> _speelbaar(List<RadioItem> items) {
    final uit = <RadioItem>[];
    for (final it in items) {
      final t = it.local;
      final id = t == null ? null : idVan(t);
      if (id == null) continue;
      _id[it] = id;
      uit.add(it);
    }
    return uit;
  }

  @override
  Future<void> playRadio(List<RadioItem> items, {int start = 0}) async {
    final speelbaar = _speelbaar(items);
    _rij
      ..clear()
      ..addAll(speelbaar);
    _index = start.clamp(0, speelbaar.isEmpty ? 0 : speelbaar.length - 1);
    _wilVerder = false;
    _weg = false;
    _sub ??= cast.radioGebeurtenis.where((e) => e.id == speaker).listen(_opGebeurtenis);
    if (speelbaar.isEmpty) {
      notifyListeners();
      return;
    }
    await cast.play(speaker, [for (final it in speelbaar) _id[it]!], _index, alsZone: true, radio: naam());
    notifyListeners();
  }

  @override
  void voegToeAanRadio(List<RadioItem> meer) {
    if (_weg) return;
    final speelbaar = _speelbaar(meer);
    if (speelbaar.isEmpty) return;
    final eerste = _rij.length;
    _rij.addAll(speelbaar);
    final wil = _wilVerder;
    _wilVerder = false;
    unawaited(() async {
      try {
        // Begon de radio zonder iets speelbaars (een titel die nog gehaald moest worden), dan is er nog geen
        // sessie op de speaker: het eerste dat landt, start hem.
        if (cast.rijVan(speaker) == null) {
          _index = eerste;
          await cast.play(speaker, [for (final it in speelbaar) _id[it]!], 0, alsZone: true, radio: naam());
          notifyListeners();
          return;
        }
        await cast.voegToe(speaker, [for (final it in speelbaar) _id[it]!], hierna: false);
        // Wie op "volgende" drukte op het laatste nummer, krijgt het eerste nieuwe meteen (een droge rij doet
        // de cast zelf).
        if (wil && !cast.isDroog(speaker)) await cast.springNaar(speaker, eerste, trackId: _id[speelbaar.first]!);
      } catch (_) {
        // De sessie is weg: [_opGebeurtenis] meldt het einde.
      }
    }());
    notifyListeners();
  }

  @override
  Future<bool> haalUitRadio(String pad) async {
    final i = _rij.indexWhere((it) => it.local?.path == pad);
    if (i < 0 || _weg) return false;
    try {
      if (i == _index) {
        if (i < _rij.length - 1) {
          await cast.control(speaker, 'next');
        } else {
          await cast.control(speaker, 'pause');
        }
      }
      final rij = cast.rijVan(speaker);
      if (rij != null) {
        final plek = rij.rij.indexOf(_id[_rij[i]] ?? '');
        if (plek >= 0 && plek != rij.index) await cast.haalUit(speaker, plek, trackId: rij.rij[plek]);
      }
    } catch (_) {}
    _volgRij();
    return true;
  }

  @override
  RadioItem? wordtLokaalInRadio(RadioItem oud, Track t) => null;

  /// Stilvallen en de radio loslaten: de sessie op de speaker gaat dicht, zodat zijn zone niet meer "radio …" zegt.
  ///
  /// **Dicht, niet op pauze (23-10-2026).** Tot 3.9.579 zette dit de speaker op pauze, en de radio "afsluiten" op de
  /// pc kwam hier niet eens langs: de speaker speelde zijn rij uit en bleef daarna "droog" open staan, met "radio
  /// Tamino" bij de zone. Nu sluit [RadioBesturing.stop] hem hier, en een radio die elders begint ook.
  @override
  Future<void> verlaatRadio() async {
    if (_weg) return;
    _weg = true;
    // Niet wachten op het opzeggen: bij deze stroom kwam die belofte nooit (het loslaten bleef hangen).
    unawaited(_sub?.cancel());
    _sub = null;
    try {
      await cast.control(speaker, 'stop');
    } catch (_) {}
    notifyListeners();
  }

  void _opGebeurtenis(({String id, bool wilVerder, bool weg}) e) {
    if (_weg) return;
    if (e.weg) {
      // Een andere wachtrij nam de speaker over (of hij werd gestopt): deze radio is voorbij.
      _weg = true;
      unawaited(_sub?.cancel());
      _sub = null;
      bijRadioEinde?.call(List.of(_rij));
      notifyListeners();
      return;
    }
    if (e.wilVerder) _wilVerder = true;
    _volgRij();
    notifyListeners();
  }

  /// De rij en de plek van de speaker overnemen: dezelfde [RadioItem]s waar ze nog staan (in volgorde, ook bij
  /// een nummer dat twee keer voorkomt), een nieuwe voor wat er op de speakerzone bij kwam.
  void _volgRij() {
    final r = cast.rijVan(speaker);
    if (r == null) return;
    final vrij = <String, List<RadioItem>>{};
    for (final it in _rij) {
      final id = _id[it];
      if (id != null) (vrij[id] ??= []).add(it);
    }
    final nieuw = <RadioItem>[];
    for (final id in r.rij) {
      final kandidaten = vrij[id];
      if (kandidaten != null && kandidaten.isNotEmpty) {
        nieuw.add(kandidaten.removeAt(0));
        continue;
      }
      final t = cast.catalog.track(id);
      if (t == null) continue;
      final it = RadioItem(artist: t.artist, title: t.title, local: t);
      _id[it] = id;
      nieuw.add(it);
    }
    _rij
      ..clear()
      ..addAll(nieuw);
    _index = r.index.clamp(0, nieuw.isEmpty ? 0 : nieuw.length - 1);
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }
}

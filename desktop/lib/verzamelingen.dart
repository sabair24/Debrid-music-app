/// De verzamelingen zelf — op elk toestel dezelfde (21-11-2026). Zie verzameling.dart voor wat een verzameling is.
///
/// Wat er in de MAP van een verzameling staat, hoort er vanzelf bij: dat leest de bibliotheek uit het pad
/// ([LibraryStore.tracksIn]). Hier staat de rest: de naam van een verzameling die nog leeg is, en de nummers die er als
/// verwijzing in staan zonder te verhuizen ([koppelingenVan]) — Saber: "Ja, mag in meerdere". Dezelfde weg als de
/// afspeellijsten ([GedeeldeOps]): op de pc rechtstreeks in de gedeelde staat, op een toestel over de lijn.
library;

import 'gedeelde_ops.dart';
import 'lan/state_store.dart';

class Verzamelingen extends GedeeldeOps {
  /// Wat een toestel van de pc kreeg. Op de pc blijft dit leeg en wordt [winkel] gelezen.
  final Map<String, VerzamelingInfo> _vanPc = {};

  /// Heeft de pc al een keer gezegd welke er zijn? Zie `Afspeellijsten.gehoord`.
  bool gehoord = false;

  void vanServer(Iterable<dynamic> ruw) {
    gehoord = true;
    _vanPc
      ..clear()
      ..addEntries([
        for (final m in ruw)
          if (m is Map<String, dynamic>)
            if (VerzamelingInfo.fromJson(m) case final v when v.naam.trim().isNotEmpty) MapEntry(v.sleutel, v),
      ]);
    notifyListeners();
  }

  Map<String, VerzamelingInfo> get _alle => winkel?.verzamelingen ?? _vanPc;

  /// De namen van wat er bestaat (zonder grafstenen), op alfabet.
  List<String> get namen {
    final uit = [for (final v in _alle.values) if (!v.deleted) v.naam];
    uit.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return uit;
  }

  /// De gekoppelde nummers (gedeelde id's) van verzameling [naam]; leeg als ze er niet is.
  List<String> koppelingenVan(String naam) {
    final v = _alle[naam.toLowerCase()];
    return v == null || v.deleted ? const [] : v.koppelingen;
  }

  /// Staat nummer [id] als verwijzing in een verzameling? Dan welke (de namen).
  List<String> waarGekoppeld(String id) => [
        for (final v in _alle.values)
          if (!v.deleted && v.koppelingen.contains(id)) v.naam,
      ];

  /// Een verzameling aanmaken (of een weggegooide terughalen).
  Future<void> maak(String naam) {
    final n = naam.trim();
    if (n.isEmpty) return Future.value();
    final at = nu;
    return pasToe(
      [
        {'type': 'verzameling.maak', 'naam': n, 'at': at}
      ],
      vooruit: () => _vanPc.putIfAbsent(n.toLowerCase(), () => VerzamelingInfo(naam: n, updatedAt: at)),
      terug: () => _vanPc.remove(n.toLowerCase()),
    );
  }

  /// Nummers [ids] als verwijzing in verzameling [naam] zetten (die er dan ook komt).
  Future<void> koppel(String naam, List<String> ids) => _koppeling('verzameling.koppel', naam, ids);

  /// Nummers [ids] uit verzameling [naam] halen (alleen de verwijzing; een bestand in haar map blijft).
  Future<void> ontkoppel(String naam, List<String> ids) => _koppeling('verzameling.ontkoppel', naam, ids);

  Future<void> _koppeling(String type, String naam, List<String> ids) {
    final n = naam.trim();
    if (n.isEmpty || ids.isEmpty) return Future.value();
    final at = nu;
    final oud = _vanPc[n.toLowerCase()];
    final voor = oud == null ? null : List.of(oud.koppelingen);
    return pasToe(
      [
        {'type': type, 'naam': n, 'ids': ids, 'at': at}
      ],
      vooruit: () {
        final v = _vanPc.putIfAbsent(n.toLowerCase(), () => VerzamelingInfo(naam: n, updatedAt: at));
        if (type == 'verzameling.koppel') {
          final al = v.koppelingen.toSet();
          v.koppelingen = [...v.koppelingen, for (final id in ids) if (al.add(id)) id];
        } else {
          final weg = ids.toSet();
          v.koppelingen = [for (final id in v.koppelingen) if (!weg.contains(id)) id];
        }
      },
      terug: () {
        if (voor == null) {
          _vanPc.remove(n.toLowerCase());
        } else {
          _vanPc[n.toLowerCase()]?.koppelingen = voor;
        }
      },
    );
  }

  /// Verzameling [van] heet voortaan [naar] (de bestanden verhuist de pc apart: [LibraryStore.naarVerzameling]).
  Future<void> hernoem(String van, String naar) {
    final v = van.trim(), n = naar.trim();
    if (v.isEmpty || n.isEmpty || v.toLowerCase() == n.toLowerCase() && v == n) return Future.value();
    final oud = _vanPc.remove(v.toLowerCase());
    final at = nu;
    return pasToe(
      [
        {'type': 'verzameling.hernoem', 'van': v, 'naar': n, 'at': at}
      ],
      vooruit: () => _vanPc[n.toLowerCase()] = VerzamelingInfo(naam: n, koppelingen: [...?oud?.koppelingen], updatedAt: at),
      terug: () {
        _vanPc.remove(n.toLowerCase());
        if (oud != null) _vanPc[v.toLowerCase()] = oud;
      },
    );
  }

  /// De naam (het record) weggooien. De map en haar bestanden regelt de pc apart: dit gooit nooit muziek weg.
  Future<void> weg(String naam) {
    final n = naam.trim().toLowerCase();
    final oud = _vanPc[n];
    final at = nu;
    return pasToe(
      [
        {'type': 'verzameling.weg', 'naam': naam.trim(), 'at': at}
      ],
      vooruit: () => _vanPc.remove(n),
      terug: () {
        if (oud != null) _vanPc[n] = oud;
      },
    );
  }
}

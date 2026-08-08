import 'dart:math';

import 'gedeelde_ops.dart';
import 'lan/state_store.dart';
import 'models.dart';

/// Je eigen lijsten — op elk toestel dezelfde.
///
/// Het model lag er al in [LanStateStore], compleet met tombstones: een afspeellijst die je wist
/// verdwijnt niet uit de lijst maar krijgt een `deletedAt`, want een toestel dat uit stond moet te
/// hóren krijgen dat hij weg is. Een regel die simpelweg verdween zou daar gelezen worden als "die
/// heb ik nog niet" en meteen worden teruggeduwd.
///
/// Alles gaat via [GedeeldeOps], dus op de pc rechtstreeks en op een iPad over de lijn — dezelfde
/// ops, één waarheid.
///
/// **Nummers zitten erin als id, niet als pad.** Een afspeellijst wordt gelezen door toestellen waar
/// jouw `D:\Flac music 2024\...` niet bestaat.
class Afspeellijsten extends GedeeldeOps {
  Afspeellijsten();

  /// Wat een client van de pc kreeg. Op de pc blijft dit leeg en wordt [winkel] gelezen.
  final Map<String, Playlist> _vanPc = {};

  final _random = Random();

  void vanServer(Iterable<dynamic> ruw) {
    _vanPc
      ..clear()
      ..addEntries([
        for (final m in ruw)
          if (m is Map<String, dynamic>) MapEntry(m['id'] as String, Playlist.fromJson(m)),
      ]);
    notifyListeners();
  }

  Map<String, Playlist> get _alle => winkel?.playlists ?? _vanPc;

  /// Alles wat nog bestaat, nieuwste bovenaan. Gewiste lijsten blijven als tombstone in de winkel
  /// staan maar horen nergens getoond te worden.
  List<Playlist> get lijsten {
    final uit = [for (final p in _alle.values) if (!p.deleted) p];
    uit.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return uit;
  }

  Playlist? byId(String id) {
    final p = _alle[id];
    return p == null || p.deleted ? null : p;
  }

  bool get leeg => lijsten.isEmpty;

  /// Een id dat op geen enkel toestel botst.
  ///
  /// Twee toestellen kunnen tegelijk een lijst maken zonder elkaar te kennen; `playlist.create`
  /// negeert een id dat al bestaat (zie [LanStateStore.applyOps]), dus een botsing zou de tweede
  /// lijst stilletjes laten verdwijnen. Tijd plus toeval maakt dat onwaarschijnlijk genoeg.
  String _nieuwId() =>
      'pl${nu.toRadixString(36)}${_random.nextInt(0x100000).toRadixString(36).padLeft(4, '0')}';

  /// Maak een lijst en geef zijn id terug.
  Future<String> maak(String naam, {List<String> nummers = const []}) async {
    final id = _nieuwId();
    final at = nu;
    await pasToe(
      [
        {'type': 'playlist.create', 'id': id, 'name': naam, 'trackIds': nummers, 'at': at}
      ],
      vooruit: () => _vanPc[id] =
          Playlist(id: id, name: naam, trackIds: List.of(nummers), updatedAt: at),
      terug: () => _vanPc.remove(id),
    );
    return id;
  }

  Future<void> hernoem(String id, String naam) async {
    final oud = byId(id)?.name;
    await pasToe(
      [
        {'type': 'playlist.rename', 'id': id, 'name': naam, 'at': nu}
      ],
      vooruit: () => _vanPc[id]?.name = naam,
      terug: () => oud == null ? null : _vanPc[id]?.name = oud,
    );
  }

  /// Nummers erbij. Twee keer hetzelfde nummer in één lijst mag — dat is een echte wens, en de
  /// winkel ontdubbelt daarom ook niet.
  Future<void> voegToe(String id, List<String> nummers) async {
    if (nummers.isEmpty) return;
    await pasToe(
      [
        {'type': 'playlist.add', 'id': id, 'trackIds': nummers, 'at': nu}
      ],
      vooruit: () {
        final p = _vanPc[id];
        if (p != null) p.trackIds = [...p.trackIds, ...nummers];
      },
      terug: () {
        final p = _vanPc[id];
        if (p != null) {
          p.trackIds = [...p.trackIds]..removeRange(p.trackIds.length - nummers.length, p.trackIds.length);
        }
      },
    );
  }

  /// De hele inhoud vervangen — wat een herschikking of een verwijdering uit de lijst oplevert.
  ///
  /// `setTracks` en niet `remove`, want `remove` gooit ELKE kopie van dat id eruit; staat een nummer
  /// twee keer in je lijst en haal je er één weg, dan zouden ze allebei verdwijnen.
  Future<void> zetNummers(String id, List<String> nummers) async {
    final oud = byId(id)?.trackIds;
    await pasToe(
      [
        {'type': 'playlist.setTracks', 'id': id, 'trackIds': nummers, 'at': nu}
      ],
      vooruit: () => _vanPc[id]?.trackIds = List.of(nummers),
      terug: () => oud == null ? null : _vanPc[id]?.trackIds = List.of(oud),
    );
  }

  Future<void> wis(String id) async {
    final at = nu;
    await pasToe(
      [
        {'type': 'playlist.delete', 'id': id, 'at': at}
      ],
      vooruit: () => _vanPc[id]?.deletedAt = at,
      terug: () => _vanPc[id]?.deletedAt = null,
    );
  }

  /// De nummers van een lijst, opgezocht in de bibliotheek.
  ///
  /// Wat niet gevonden wordt valt weg in plaats van als gat te blijven staan: dat is een nummer dat
  /// je verwijderd hebt, en een lege regel in een afspeellijst kun je nergens mee.
  List<Track> nummersVan(Playlist p, Track? Function(String id) zoek) =>
      [for (final id in p.trackIds) if (zoek(id) case final t?) t];
}

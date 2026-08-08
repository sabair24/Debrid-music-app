import 'dart:async';

import 'package:flutter/foundation.dart';

import 'gedeelde_ops.dart';
import 'lan/ids.dart';
import 'lan/state_store.dart';
import 'models.dart';
import 'organize.dart';

/// Wat je mooi vindt — op elk toestel hetzelfde.
///
/// Het model lag er al: [LanStateStore] bewaart `favoriteTracks` en `favoriteAlbums` als
/// verzamelingen van id's, met opslag, tombstones en endpoints. Deze pc was er alleen al de server
/// van voor de iPad en de gsm zonder ze zelf te kunnen tonen of maken.
///
/// **Eén weg voor beide kanten.** Op de pc gaat het rechtstreeks in de winkel; op een iPad of gsm
/// staat die winkel niet, dus gaan dezelfde ops over de lijn naar `/api/state/ops`. Dat is precies
/// het pad dat de andere toestellen al gebruiken, dus synchroniseren komt er gratis bij en er is
/// geen tweede waarheid die kan gaan afwijken.
///
/// **Waarom id's en geen paden.** De gedeelde staat wordt gelezen door toestellen waar jouw
/// `D:\Flac music 2024\...` niet bestaat. Een pad zou daar nergens op slaan; het id dat de catalogus
/// uitgeeft wél. Zie [trackIdFor] en [albumIdFor].
class Favorieten extends GedeeldeOps {
  Favorieten();

  /// De wortel van de bibliotheek — nodig om van een pad een id te maken. Leeg op een client, waar
  /// de id's al uit de catalogus komen.
  String Function()? wortel;

  /// Wat een client van de pc heeft gekregen. Op de pc blijven deze leeg en wordt [winkel] gelezen.
  final Set<String> _vanPc = {};

  /// Zet wat de pc als favoriet meldt. Alleen op een client; de pc is zijn eigen bron.
  void vanServer(Iterable<String> nummers, Iterable<String> albums) {
    final nieuw = {...nummers, ...albums};
    if (setEquals(_vanPc, nieuw)) return;
    _vanPc
      ..clear()
      ..addAll(nieuw);
    notifyListeners();
  }

  String? idVanTrack(Track t) {
    final r = wortel?.call() ?? '';
    if (r.isEmpty) return null;
    return trackIdFor(t.path, r);
  }

  String? idVanAlbum(Album a) => albumIdFor(artistKey(a.artist), normKey(a.title), a.edition);

  bool isFavoriet(String? id) {
    if (id == null) return false;
    final w = winkel;
    if (w != null) return w.favoriteTracks.contains(id) || w.favoriteAlbums.contains(id);
    return _vanPc.contains(id);
  }

  bool isFavorietTrack(Track t) => isFavoriet(idVanTrack(t));
  bool isFavorietAlbum(Album a) => isFavoriet(idVanAlbum(a));

  /// Zet het hartje aan of uit. Geeft terug wat de nieuwe stand is.
  Future<bool> wissel({required String id, required bool album}) async {
    final aan = !isFavoriet(id);
    await pasToe(
      [
        {
          'type': 'favorite',
          'kind': album ? 'album' : 'track',
          'id': id,
          'on': aan,
          'at': nu,
        }
      ],
      vooruit: () => aan ? _vanPc.add(id) : _vanPc.remove(id),
      terug: () => aan ? _vanPc.remove(id) : _vanPc.add(id),
    );
    return aan;
  }

  Future<bool> wisselTrack(Track t) async {
    final id = idVanTrack(t);
    if (id == null) return false;
    return wissel(id: id, album: false);
  }

  Future<bool> wisselAlbum(Album a) async {
    final id = idVanAlbum(a);
    if (id == null) return false;
    return wissel(id: id, album: true);
  }

  /// Alle nummers uit [alles] die favoriet zijn, in de volgorde van je bibliotheek.
  List<Track> nummers(List<Track> alles) =>
      [for (final t in alles) if (isFavorietTrack(t)) t];

  List<Album> albums(List<Album> alles) =>
      [for (final a in alles) if (isFavorietAlbum(a)) a];

  int get aantal => winkel == null
      ? _vanPc.length
      : winkel!.favoriteTracks.length + winkel!.favoriteAlbums.length;
}

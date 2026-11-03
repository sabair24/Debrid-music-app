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

  /// Van pad naar het id van de gedeelde staat (`library.gedeeldId`): op een telefoon uit de
  /// stream-URL, op de pc uit het pad. Zonder dit gaf [idVanTrack] op elke client null en waren
  /// per-nummer favorieten daar stil dood: de pc had er één, de gsm toonde "Nog geen favorieten"
  /// (18-10-2026).
  String? Function(String path)? idVanPad;

  /// Wat een client van de pc heeft gekregen. Op de pc blijven deze leeg en wordt [winkel] gelezen.
  final Set<String> _vanPc = {};

  /// Zet wat de pc als favoriet meldt. Alleen op een client; de pc is zijn eigen bron.
  /// Heeft de pc al een keer gezegd wat je favorieten zijn? Tot dan is "geen favorieten" geen antwoord — en mag
  /// "Op dit toestel" er niets vanzelf om weghalen (main, toestel_bijhouden.dart).
  bool gehoord = false;

  void vanServer(Iterable<String> nummers, Iterable<String> albums) {
    gehoord = true;
    final nieuw = {...nummers, ...albums};
    if (setEquals(_vanPc, nieuw)) return;
    _vanPc
      ..clear()
      ..addAll(nieuw);
    notifyListeners();
  }

  String? idVanTrack(Track t) {
    final via = idVanPad?.call(t.path);
    if (via != null) return via;
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

  /// Een hartje op een tegel die er niet meer is, gaat mee naar de tegel(s) die eruit voortkwamen. Alleen op de pc
  /// (daar staat de winkel); een toestel krijgt het daarna met de gedeelde staat. Geeft het aantal nieuwe hartjes.
  ///
  /// **Waarom.** Het id van een album is artiest, titel en editie ([albumIdFor]). Valt een naam vanzelf uiteen in twee
  /// platen (Marc Lavoine 1985 en 2001, plaat_indeling.dart) of laat je hem per jaar scheiden, dan krijgt elke tegel
  /// een editie — en dus een ander id dan de tegel waar je hart op stond. Zonder dit was het hartje stil weg.
  ///
  /// **Welke tegels.** Een tegel mét editie stamt van het id zonder editie: beide platen van Marc Lavoine krijgen het
  /// hartje, want je gaf het aan de tegel waar ze allebei op stonden. Omgekeerd (weer samengevoegd) krijgt de tegel
  /// zonder editie het hartje van een verdwenen tegel met een editie die zijn nummers dragen: het jaar ervan, of
  /// "12 nummers". Het oude id gaat er pas uit als een tegel het overnam — wie zelf een hartje weghaalt, ziet het niet
  /// terugkomen, want dan is het oude id al weg. Alleen ids die bij geen enkele tegel meer horen tellen mee.
  int volgTegels(List<Album> albums) {
    final w = winkel;
    if (w == null || w.favoriteAlbums.isEmpty || albums.isEmpty) return 0;
    // Bij elke melding van de bibliotheek, en die komen vaak (elke hoes): alleen opnieuw kijken als de tegels of de
    // hartjes veranderden. Een id is een sha256, en dat negenhonderd keer per hoes is zonde.
    if (identical(albums, _gevolgd) && w.favoriteAlbums.length == _gevolgdAantal) return 0;
    _gevolgd = albums;
    _gevolgdAantal = w.favoriteAlbums.length;
    final ids = {for (final a in albums) idVanAlbum(a)};
    final wees = w.favoriteAlbums.where((id) => !ids.contains(id)).toSet();
    if (wees.isEmpty) return 0;
    final aan = <String>{}, overgenomen = <String>{};
    for (final a in albums) {
      final id = idVanAlbum(a);
      if (id == null || w.favoriteAlbums.contains(id)) continue;
      final basis = (artistKey(a.artist), normKey(a.title));
      final kandidaten = a.edition != null
          ? {albumIdFor(basis.$1, basis.$2, null)}
          : {
              for (final t in a.tracks) ...[
                if ((t.year ?? 0) > 0) albumIdFor(basis.$1, basis.$2, '${t.year}'),
                albumIdFor(basis.$1, basis.$2, t.trackTotal > 0 ? '${t.trackTotal} nummers' : 'zonder nummering'),
              ],
            };
      final van = kandidaten.where(wees.contains).toSet();
      if (van.isEmpty) continue;
      aan.add(id);
      overgenomen.addAll(van);
    }
    if (aan.isEmpty) return 0;
    unawaited(pasToe([
      for (final id in aan) {'type': 'favorite', 'kind': 'album', 'id': id, 'on': true, 'at': nu},
      for (final id in overgenomen) {'type': 'favorite', 'kind': 'album', 'id': id, 'on': false, 'at': nu},
    ]));
    _gevolgdAantal = w.favoriteAlbums.length;
    return aan.length;
  }

  List<Album>? _gevolgd;
  int _gevolgdAantal = -1;

  /// Alle nummers uit [alles] die favoriet zijn, in de volgorde van je bibliotheek.
  List<Track> nummers(List<Track> alles) =>
      [for (final t in alles) if (isFavorietTrack(t)) t];

  List<Album> albums(List<Album> alles) =>
      [for (final a in alles) if (isFavorietAlbum(a)) a];

  int get aantal => winkel == null
      ? _vanPc.length
      : winkel!.favoriteTracks.length + winkel!.favoriteAlbums.length;
}

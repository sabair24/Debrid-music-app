import 'gedeelde_ops.dart';
import 'lan/state_store.dart';
import 'models.dart';
import 'schudvolgorde.dart';

/// Hoe vaak en hoe lang geleden je een nummer werkelijk beluisterd hebt.
///
/// **De cijfers lagen er al en werden door niemand gelezen.** [LanStateStore.plays] bewaart sinds
/// maanden `{trackId: {count, lastPlayedMs}}` in `state.json`, gedeeld tussen al je toestellen, met
/// opslag en endpoints. Er was geen enkele lezer: een zoektocht door de hele broncode gaf alleen de
/// winkel zelf en één toets. Dit is die lezer, en tegelijk de schrijver die op een telefoon ontbrak.
///
/// **Twee gaten die hier dichtgaan.** `player.onPlayed` hing alleen ingehangen binnen
/// `if (mode.owner)`, dus een gekoppelde telefoon telde nooit een beluistering — en juist daar wordt
/// het meest geluisterd. En de client haalde `/api/state` wel op maar gooide `plays` weg.
///
/// **Eén weg voor beide kanten**, net als bij `Favorieten`: op de pc rechtstreeks in de winkel, op
/// een telefoon dezelfde op over de lijn naar `/api/state/ops`. Die op (`played`) bestaat al aan de
/// pc-kant, dus dit werkt ook tegen een pc die nog niet bijgewerkt is.
class Speelstanden extends GedeeldeOps {
  Speelstanden();

  /// Van pad naar het id dat de gedeelde staat gebruikt.
  ///
  /// **Ingehangen en niet zelf uitgerekend.** Op de pc is dat een hash over het pad ten opzichte van
  /// de muziekmap; op een telefoon staat het id al ín de stream-URL en valt er niets te rekenen.
  /// `Favorieten.wortel` doet dat laatste niet, en daar is het gevolg dat `idVanTrack` op elke
  /// client null geeft — per-nummer favorieten zijn daar stilletjes dood. Die fout hier niet
  /// herhalen.
  String? Function(String path)? idVanPad;

  /// Wat een client van de pc kreeg. Op de pc blijft dit leeg en wordt [winkel] gelezen.
  final Map<String, Speelstand> _vanPc = {};

  /// Overnemen wat `/api/state` meestuurde. Alleen op een client.
  void vanServer(Map<String, dynamic> plays) {
    final nieuw = <String, Speelstand>{};
    for (final e in plays.entries) {
      final m = e.value;
      if (m is! Map) continue;
      nieuw[e.key] = Speelstand(
        aantal: (m['count'] as num?)?.toInt() ?? 0,
        laatstMs: (m['lastPlayedMs'] as num?)?.toInt() ?? 0,
      );
    }
    // Alleen melden als er werkelijk iets veranderde: dit komt bij elke verversing langs, en een
    // melding hertekent schermen.
    if (nieuw.length == _vanPc.length &&
        nieuw.entries.every((e) =>
            _vanPc[e.key]?.aantal == e.value.aantal &&
            _vanPc[e.key]?.laatstMs == e.value.laatstMs)) {
      return;
    }
    _vanPc
      ..clear()
      ..addAll(nieuw);
    notifyListeners();
  }

  /// Wat er van dit nummer bekend is, of null als het nooit klonk.
  Speelstand? standVan(Track t) {
    final id = idVanPad?.call(t.path);
    if (id == null || id.isEmpty) return null;
    final w = winkel;
    if (w != null) {
      final p = w.plays[id];
      return p == null ? null : Speelstand(aantal: p.count, laatstMs: p.lastPlayedMs);
    }
    return _vanPc[id];
  }

  /// Dit nummer is beluisterd. Zie `schudvolgorde.dart` voor wat "beluisterd" betekent.
  ///
  /// Een stroom (radio, een torrent) heeft geen id in de bibliotheek en telt dus niet mee — daar
  /// valt ook niets aan te wegen, want het staat niet in je shuffle.
  Future<void> meld(Track t) async {
    final id = idVanPad?.call(t.path);
    if (id == null || id.isEmpty) return;
    final nu = this.nu;
    // Stil bij een fout, anders dan bij een hartje: dit is een telling die op de achtergrond
    // meeloopt, en een melding "kon niet tellen" over een nummer dat gewoon speelt is erger dan de
    // gemiste telling zelf. [pasToe] gooit met opzet, dus hier wordt hij opgevangen.
    try {
      await pasToe(
        [
          {'type': 'played', 'trackId': id, 'at': nu}
        ],
        // Meteen zelf ophogen, zodat je eigen luisterbeurt al meeweegt in de volgende trekking en niet
        // pas na de eerstvolgende verversing van de pc.
        vooruit: () {
          final was = _vanPc[id];
          _vanPc[id] = Speelstand(aantal: (was?.aantal ?? 0) + 1, laatstMs: nu);
        },
        terug: () {
          final was = _vanPc[id];
          if (was == null) return;
          if (was.aantal <= 1) {
            _vanPc.remove(id);
          } else {
            _vanPc[id] = Speelstand(aantal: was.aantal - 1, laatstMs: was.laatstMs);
          }
        },
      );
    } catch (_) {
      // De pc nam het niet aan; `terug` heeft de eigen telling al hersteld.
    }
  }
}

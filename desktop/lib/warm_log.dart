/// Het logboek dat de warmer en de feitencache samen volschrijven.
library;

import 'dart:io';

/// A written record of what the warmer decided, in `warm.log` beside the other state files.
///
/// This exists because four attempts at fixing "the counter sticks at 15" were spent guessing. A
/// release build strips [print], so from the outside the warmer is a black box: the only signals
/// were a counter that turns out to count something other than progress, and a cache directory that
/// either grows or does not. Everything else was inference.
///
/// Deliberately blunt: append a line, truncate when it gets long, never throw. A logger that can
/// break the thing it observes is worse than none.
///
/// Staat apart van facts_warmer.dart omdat album_facts.dart hem ook nodig heeft -- en dat bestand
/// wordt juist DOOR de warmer geïmporteerd, dus andersom zou een kring worden. Dat het hier moest
/// landen kwam van een reparatie die zijn eigen teller via debugPrint schreef: in een release-build
/// is dat niets, en een teller die niemand kan lezen bewijst niets.
class WarmLog {
  WarmLog(this._path);
  final String _path;

  /// Kept small enough to read in one go and to never matter on disk. Rewritten from the tail rather
  /// than rotated: there is nothing here worth keeping across sessions.
  static const _maxBytes = 256 * 1024;

  /// Zwijgen is niet gratis, en dat bleek duur.
  ///
  /// Deze `catch` slikte élke fout, en op 04-08-2026 kostte dat een hele avond. Saber sloot de app en
  /// opende hem elf seconden later opnieuw; de nieuwe instantie schreef toen GEEN ENKELE regel — ook
  /// niet de allereerste van `main()`. Op Windows houdt een afsluitend proces zijn bestanden nog even
  /// vast, en `FileMode.append` botst dan op een deelfout. Van buiten leek het alsof het opstarten niet
  /// gelopen was, en daar is uren op gezocht terwijl de app gewoon draaide.
  ///
  /// Nu een paar korte herkansingen. Het uitgangspunt blijft overeind — een logboek mag de zaak die
  /// het observeert nooit breken — maar "nooit breken" is iets anders dan "meteen opgeven".
  void line(String s) {
    final t = DateTime.now().toIso8601String().substring(11, 23);
    for (var poging = 0; poging < 4; poging++) {
      try {
        final f = File(_path);
        if (f.existsSync() && f.lengthSync() > _maxBytes) {
          final keep = f.readAsStringSync();
          f.writeAsStringSync(keep.substring(keep.length ~/ 2), flush: true);
        }
        f.writeAsStringSync('$t  $s\n', mode: FileMode.append, flush: true);
        return;
      } catch (_) {
        // Synchroon wachten: dit gebeurt tijdens het opstarten, waar de aanroeper niet kan awaiten en
        // waar een verloren regel het duurst is. Vier keer 40 ms is onmerkbaar en overbrugt precies
        // het venster waarin het vorige proces zijn greep nog niet heeft losgelaten.
        if (poging < 3) sleep(const Duration(milliseconds: 40));
      }
    }
  }
}

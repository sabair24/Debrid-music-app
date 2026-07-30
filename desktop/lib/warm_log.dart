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

  void line(String s) {
    try {
      final f = File(_path);
      if (f.existsSync() && f.lengthSync() > _maxBytes) {
        final keep = f.readAsStringSync();
        f.writeAsStringSync(keep.substring(keep.length ~/ 2), flush: true);
      }
      final t = DateTime.now().toIso8601String().substring(11, 23);
      f.writeAsStringSync('$t  $s\n', mode: FileMode.append, flush: true);
    } catch (_) {/* observing must never break the observed */}
  }
}

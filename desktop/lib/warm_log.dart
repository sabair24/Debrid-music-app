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
  WarmLog(this._path, {int maxBytes = 256 * 1024}) : _maxBytes = maxBytes;
  final String _path;

  /// Kept small enough to read in one go and to never matter on disk. Rewritten from the tail rather
  /// than rotated: there is nothing here worth keeping across sessions. Een logboek dat over weken moet gaan
  /// (schud.log) krijgt meer.
  final int _maxBytes;

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
  /// De laatste fout, zodat een verdwenen logboek zichzelf kan verklaren.
  ///
  /// Een logboek dat niet schrijft en dat ook niet zegt, is erger dan geen logboek: dan lees je de
  /// afwezigheid van regels als "die code is niet gelopen". Dat is op 04-08-2026 twee keer gebeurd en
  /// heeft een hele avond gekost.
  static String? laatsteFout;

  /// Twee wegen: de snelle, en de weg die het aantoonbaar dóét.
  ///
  /// Gemeten op 04-08-2026 op Sabers pc: één draaiende instantie schreef probleemloos
  /// `resume_pos.json`, de discografiecache en tientallen hoesbestanden naar dezelfde map, maar geen
  /// énkele regel naar start.log, warm.log of soulseek_login.log. Wat die drie gemeen hadden was
  /// `FileMode.append`; wat de werkende bestanden gemeen hadden was een gewone schrijfbeurt die het
  /// bestand opnieuw aanmaakt. Waaróm append daar faalt is niet vastgesteld, en dat hoeft ook niet —
  /// wat telt is dat er een weg is die werkt.
  ///
  /// Append blijft de eerste keus, want het hele bestand herschrijven kost bij warm.log 256 KB lezen
  /// én schrijven per regel, en die krijgt er honderden. Pas als append faalt gaat hij om.
  void line(String s) {
    final t = DateTime.now().toIso8601String().substring(11, 23);
    final regel = '$t  $s\n';
    if (_viaOpenBestand(regel)) return;
    for (var poging = 0; poging < 3; poging++) {
      final f = File(_path);
      try {
        if (f.existsSync() && f.lengthSync() > _maxBytes) {
          final keep = f.readAsStringSync();
          f.writeAsStringSync(keep.substring(keep.length ~/ 2), flush: true);
        }
        f.writeAsStringSync(regel, mode: FileMode.append, flush: true);
        return;
      } catch (e) {
        laatsteFout = 'append $_path: $e';
      }
      try {
        var houden = '';
        if (f.existsSync()) {
          houden = f.readAsStringSync();
          if (houden.length > _maxBytes) houden = houden.substring(houden.length ~/ 2);
        }
        f.writeAsStringSync('$houden$regel', flush: true);
        return;
      } catch (e) {
        laatsteFout = 'herschrijf $_path: $e';
      }
      // Synchroon wachten: dit gebeurt tijdens het opstarten, waar de aanroeper niet kan awaiten en
      // waar een verloren regel het duurst is. Twee keer 40 ms is onmerkbaar.
      if (poging < 2) sleep(const Duration(milliseconds: 40));
    }
  }

  /// Open schrijfbestanden per pad, gedeeld door elke [WarmLog] in deze isolate (er worden er overal los gemaakt).
  ///
  /// **Waarom (28-10-2026).** Saber: *"ik merk soms happering"*. Elke regel opende, schreef, flushte en sloot zijn
  /// bestand, op de tekendraad, en dat kost op deze pc gemeten ~5 ms per regel (open bestand: 0,25 ms mét flush).
  /// Er vallen tientallen regels per seconde: 43 RuTracker-regels in een halve seconde waren zo al 200 ms vast.
  static final Map<String, RandomAccessFile> _open = {};

  /// Alleen de app zet dit aan (main.dart). Uit = elke regel opent en sluit zijn bestand zoals vóór 28-10-2026: een
  /// toets die zijn tijdelijke map opruimt, struikelt dan niet over een bestand dat nog openstaat (Windows).
  static bool houdOpen = false;

  /// Eén regel langs het open bestand, met flush zoals voorheen. Onwaar = de gewone weg hierboven doet het: het
  /// bestand is te groot (die halveert hem), weg, of het openen faalt (zie [laatsteFout]).
  bool _viaOpenBestand(String regel) {
    if (!houdOpen) return false;
    try {
      final f = File(_path);
      var raf = _open[_path];
      // Weggehaald onder een open bestand: dan zou alles in een bestand zonder naam belanden.
      if (raf != null && !f.existsSync()) {
        _sluit();
        raf = null;
      }
      raf ??= _open[_path] = f.openSync(mode: FileMode.append);
      if (raf.lengthSync() > _maxBytes) {
        _sluit();
        return false;
      }
      raf
        ..writeStringSync(regel)
        ..flushSync();
      return true;
    } catch (e) {
      laatsteFout = 'open $_path: $e';
      _sluit();
      return false;
    }
  }

  void _sluit() {
    try {
      _open.remove(_path)?.closeSync();
    } catch (_) {/* dicht is dicht */}
  }

  /// Alle open logbestanden van deze isolate dicht — voor een toets die zijn tijdelijke map wil opruimen (op
  /// Windows gaat een open bestand niet weg). De volgende regel opent ze gewoon weer.
  static void sluitAlles() {
    for (final raf in _open.values) {
      try {
        raf.closeSync();
      } catch (_) {/* dicht is dicht */}
    }
    _open.clear();
  }
}

/// Wat het vergrendelscherm en de melding van de gsm tonen en bedienen (zones, stap 2.6).
///
/// **Wat Saber koos (21-10-2026).** "Wat de gsm zelf speelt gaat voor; pas als hij zelf niets speelt, de
/// gekozen zone." Kies je op je gsm de pc als zone en speelt de gsm zelf niets, dan staat op het
/// vergrendelscherm wat de pc speelt, met knoppen die de pc bedienen, en regelen de volumeknoppen het
/// volume van de app op de pc. Speelt de gsm zelf iets, dan gaat alles over de gsm, zoals altijd.
///
/// Alleen op Android: iOS toont op het vergrendelscherm alleen wat het toestel zelf laat klinken, en de
/// volumeknoppen gaan daar altijd naar het toestel.
library;

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'player.dart' show NowPlayingSource, RepeatMode;
import 'zone_speler.dart';

/// Welke van de twee het vergrendelscherm toont: dit toestel als het zelf speelt of als er geen zone op
/// afstand gekozen is, anders de gekozen zone.
bool volgAfstand({required bool lokaalSpeelt, required bool afstandGekozen}) => afstandGekozen && !lokaalSpeelt;

/// Het volume van wat het vergrendelscherm nu toont, als dat een zone op afstand is.
abstract interface class Afstandsvolume {
  /// Het volume van de app in die zone (0–100), of null: dan regelen de volumeknoppen het toestel zelf.
  int? get afstandsvolume;
  void zetAfstandsvolume(int v);
}

/// De stap van één druk op een volumeknop, voor een zone op afstand.
const kVolumeStap = 5;

/// Volgt dit toestel of de gekozen zone, zie de uitleg bovenaan.
class Volgbron extends ChangeNotifier implements NowPlayingSource, Afstandsvolume {
  Volgbron({required this.lokaal, required this.gekozen, bool Function()? opVoorgrond, int Function()? klok})
      : _opVoorgrond = opVoorgrond ?? (() => true),
        _klok = klok {
    lokaal.addListener(notifyListeners);
    gekozen.addListener(notifyListeners);
  }

  final NowPlayingSource lokaal;
  final GekozenZone gekozen;

  /// Staat de app nu voor (in beeld)? Zie [speeltErgens].
  final bool Function() _opVoorgrond;
  final int Function()? _klok;
  int get _nu => _klok?.call() ?? DateTime.now().millisecondsSinceEpoch;

  /// De app kwam weer in beeld (of iets anders veranderde): opnieuw laten bekijken.
  void herbekijk() => notifyListeners();

  /// De zone op afstand die het vergrendelscherm nu toont, of null.
  ZoneSpeler? get opAfstand {
    final a = gekozen.opAfstand;
    return a != null && volgAfstand(lokaalSpeelt: lokaal.speeltErgens, afstandGekozen: true) ? a : null;
  }

  NowPlayingSource get _actief => opAfstand ?? lokaal;

  @override
  Track? get current => _actief.current;
  @override
  bool get playing => opAfstand == null ? lokaal.playing : speeltErgens;

  /// Toonde het vergrendelscherm de zone als spelend? Dan draait de mediadienst op de voorgrond al.
  bool _getoondSpelend = false;

  /// Tot wanneer een druk van HIER telt als reden om de mediadienst te starten.
  int _eigenDrukTot = 0;

  /// Speelt wat het vergrendelscherm toont — met één grendel voor een zone op afstand.
  ///
  /// **Waarom.** "Speelt" laat audio_service de mediadienst op de voorgrond zetten
  /// (\`startForegroundService\`). Android 12 en later weigert dat als de app in de achtergrond zit,
  /// behalve vlak na een druk op een mediaknop. Begint de zone te spelen omdat een ANDER toestel op play
  /// drukte terwijl de gsm weggestoken is en zijn dienst stillag, dan zou dat een fout geven. Dan toont
  /// het vergrendelscherm de zone nog even als gepauzeerd — tot de app in beeld komt, of tot je hier zelf
  /// op een knop drukt. Draaide de dienst al (de zone speelde al), dan gewoon "speelt".
  @override
  bool get speeltErgens {
    final a = opAfstand;
    if (a == null) return lokaal.speeltErgens;
    if (!a.speeltErgens) {
      _getoondSpelend = false;
      return false;
    }
    if (_getoondSpelend || _opVoorgrond() || _nu < _eigenDrukTot) {
      _getoondSpelend = true;
      return true;
    }
    return false;
  }

  void _eigenDruk() => _eigenDrukTot = _nu + 10000;
  @override
  Duration get position => _actief.position;
  @override
  Duration get duration => _actief.duration;
  @override
  Uint8List? get currentCover => _actief.currentCover;
  @override
  void playPause() {
    _eigenDruk();
    _actief.playPause();
  }

  @override
  void speelAf() {
    _eigenDruk();
    _actief.speelAf();
  }

  @override
  void pauzeer() => _actief.pauzeer();
  @override
  Duration get positieErgens => _actief.positieErgens;
  @override
  Duration get duurErgens => _actief.duurErgens;
  @override
  Future<void> next() => _actief.next();
  @override
  Future<void> prev() => _actief.prev();
  @override
  void seek(Duration d) => _actief.seek(d);
  @override
  bool get shuffle => _actief.shuffle;
  @override
  RepeatMode get repeat => _actief.repeat;
  @override
  void zetShuffle(bool aan) => _actief.zetShuffle(aan);
  @override
  void zetHerhaal(RepeatMode m) => _actief.zetHerhaal(m);

  /// Een navigatiestem of een telefoontje gaat over wat HIER klinkt, nooit over de Sonos in de kamer.
  @override
  void zetDemping(bool aan) => lokaal.zetDemping(aan);

  @override
  int? get afstandsvolume {
    final a = opAfstand;
    return a != null && a.heeftVolume ? a.volume.round() : null;
  }

  @override
  void zetAfstandsvolume(int v) => opAfstand?.setVolume(v.clamp(0, 100).toDouble());

  @override
  void dispose() {
    lokaal.removeListener(notifyListeners);
    gekozen.removeListener(notifyListeners);
    super.dispose();
  }
}

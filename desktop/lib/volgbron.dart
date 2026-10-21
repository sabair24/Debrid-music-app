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
  Volgbron({required this.lokaal, required this.gekozen}) {
    lokaal.addListener(notifyListeners);
    gekozen.addListener(notifyListeners);
  }

  final NowPlayingSource lokaal;
  final GekozenZone gekozen;

  /// De zone op afstand die het vergrendelscherm nu toont, of null.
  ZoneSpeler? get opAfstand {
    final a = gekozen.opAfstand;
    return a != null && volgAfstand(lokaalSpeelt: lokaal.speeltErgens, afstandGekozen: true) ? a : null;
  }

  NowPlayingSource get _actief => opAfstand ?? lokaal;

  @override
  Track? get current => _actief.current;
  @override
  bool get playing => _actief.playing;
  @override
  Duration get position => _actief.position;
  @override
  Duration get duration => _actief.duration;
  @override
  Uint8List? get currentCover => _actief.currentCover;
  @override
  void playPause() => _actief.playPause();
  @override
  void speelAf() => _actief.speelAf();
  @override
  void pauzeer() => _actief.pauzeer();
  @override
  bool get speeltErgens => _actief.speeltErgens;
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

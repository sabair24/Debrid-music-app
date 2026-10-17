/// De mediatoetsen van het toetsenbord en de knoppen in de taakbalk, op Windows (Saber, 17-10-2026:
/// "mijn media toetsen op men toetsenbord moeten er op werken, ik heb een logitech G213 toetsenbord",
/// en "knoppen in de taakbalk").
///
/// **Hoe het loopt.** De pc-app meldt zich bij de mediabediening van Windows (de "System Media
/// Transport Controls", het venstertje met de hoes dat verschijnt als je op een mediatoets drukt) en
/// zet drie knoppen onder het voorbeeld in de taakbalk. Dat gebeurt in de runner, in C++ (zie
/// `windows/runner/mediabediening.cpp`). Hier staat de Dart-kant: wat er speelt gaat naar Windows
/// ([_meld]), en wat er ingedrukt wordt komt terug als "knop" ([mediaKnopActie]).
///
/// **Wie de toets krijgt** als er ook iets in Chrome speelt: dat beslist Windows, en het is wie het
/// laatst speelde. Dat koos Saber; de toetsen zelf afvangen zou ze Chrome en Spotify afpakken.
///
/// Waarom de toetsen het tot nu toe niet deden: de app luisterde alleen naar toetsen zolang zijn
/// venster voor stond, en dan nog alleen in het boekje. Niemand meldde zich bij Windows.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'player.dart';
import 'speakers.dart';

/// Wat een knop van de mediabediening doet.
enum MediaActie { speelPauze, volgende, vorige }

/// De knop [knop] ("afspelen", "pauze", "speelpauze", "stop", "volgende", "vorige") terwijl er wel of
/// niet iets speelt ([speelt]). Null = niets doen: "afspelen" als het al speelt, of een onbekende knop.
///
/// "Stop" pauzeert: een wachtrij weggooien met een toets die je per ongeluk raakt is te veel.
@visibleForTesting
MediaActie? mediaKnopActie(String? knop, {required bool speelt}) => switch (knop) {
      'speelpauze' => MediaActie.speelPauze,
      'afspelen' => speelt ? null : MediaActie.speelPauze,
      'pauze' || 'stop' => speelt ? MediaActie.speelPauze : null,
      'volgende' => MediaActie.volgende,
      'vorige' => MediaActie.vorige,
      _ => null,
    };

/// De verbinding met de mediabediening van Windows. Eén per app, zie [start].
class Mediabediening {
  Mediabediening._(this._speler, this._speaker);

  static const _kanaal = MethodChannel('debridmusic/mediabediening');

  final PlayerStore _speler;
  final SpeakerTarget _speaker;

  String? _pad;
  bool? _speelt;
  Uint8List? _hoes;

  /// Begint met melden en luisteren; alleen op Windows (elders null).
  static Mediabediening? start({required PlayerStore speler, required SpeakerTarget speaker}) {
    if (!Platform.isWindows) return null;
    final m = Mediabediening._(speler, speaker);
    _kanaal.setMethodCallHandler(m._opOproep);
    speler.addListener(m._meld);
    speaker.addListener(m._meld);
    m._meld();
    return m;
  }

  /// Wat er klinkt, waar dan ook: op deze pc of op een speaker ([PlayerStore.speeltErgens]).
  bool get _speeltNu => _speler.speeltErgens;

  Future<void> _opOproep(MethodCall oproep) async {
    if (oproep.method != 'knop') return;
    switch (mediaKnopActie(oproep.arguments as String?, speelt: _speeltNu)) {
      // Als opdracht en niet als schakelaar, op de plek waar de muziek is: zie [PlayerStore.speelAf].
      case MediaActie.speelPauze:
        if (_speler.current == null && !_speaker.isCasting) return;
        _speeltNu ? _speler.pauzeer() : _speler.speelAf();
      case MediaActie.volgende:
        if (_speler.hasNext || _speaker.isCasting) await _speler.next();
      case MediaActie.vorige:
        await _speler.prev();
      case null:
        break;
    }
  }

  /// Vertelt Windows wat er speelt. De speler meldt zich bij elke tik van de klok; alleen een ander
  /// nummer, een andere hoes of afspelen/pauze gaan over het kanaal.
  void _meld() {
    final t = _speler.current;
    final speelt = _speeltNu;
    final hoes = _speler.currentCover;
    final nieuwNummer = t?.path != _pad;
    final nieuweHoes = !identical(hoes, _hoes);
    if (!nieuwNummer && !nieuweHoes && speelt == _speelt) return;
    _pad = t?.path;
    _speelt = speelt;
    _hoes = hoes;
    _kanaal.invokeMethod<void>('stand', <String, Object?>{
      'speelt': speelt,
      'titel': t?.title ?? '',
      'artiest': t?.artist ?? '',
      'album': t?.album ?? '',
      // Alleen als hij veranderde: een hoes is honderden kilobytes, en afspelen/pauze verandert hem niet.
      if ((nieuwNummer || nieuweHoes) && hoes != null) 'hoes': hoes,
    }).catchError((Object _) {});
  }
}

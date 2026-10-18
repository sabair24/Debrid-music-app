/// Wil het systeem dicht glas? (Saber, 18-10-2026: "volgen: dan dicht glas".)
///
/// Wie op zijn toestel "Minder transparantie" aanzet, of de batterijbesparing, krijgt dicht glas: geen
/// vervaging, alleen de vulling. Zo doen Apple en Windows het zelf ook.
///
/// Per platform (het kanaal `debridmusic/systeem`, methode `dichtGlas`):
/// - **Windows** (`flutter_window.cpp`): "Transparantie-effecten" uit in Instellingen > Persoonlijke
///   instellingen > Kleuren, of de batterijbesparing aan.
/// - **iOS** (`AppDelegate.swift`): Toegankelijkheid > "Minder transparantie", of de energiebesparingsmodus.
/// - **macOS** (`MainFlutterWindow.swift`): "Transparantie verminderen", of de energiebesparingsmodus.
/// - **Android** (`MainActivity.kt`): de batterijbesparing, of Samsungs "Transparantie en vervaging
///   verminderen".
///
/// Gevraagd bij het opstarten, als de app weer naar voren komt, en elke minuut. Een oudere bouw of een
/// platform zonder het kanaal antwoordt niet; dan gewoon glas.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'ui/glas.dart';

class SysteemGlas with WidgetsBindingObserver {
  SysteemGlas._();

  static const _kanaal = MethodChannel('debridmusic/systeem');
  static SysteemGlas? _wacht;
  static Timer? _elkeMinuut;

  /// Vraag het nu. Faalt de vraag, dan is het antwoord nee.
  static Future<bool> vraag() async {
    try {
      return await _kanaal.invokeMethod<bool>('dichtGlas') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> _kijk() async => GlasKwaliteit.zetSysteemDicht(await vraag());

  /// Eén keer, na [GlasKwaliteit.inrichten].
  static void start() {
    if (_wacht != null) return;
    final w = _wacht = SysteemGlas._();
    WidgetsBinding.instance.addObserver(w);
    unawaited(_kijk());
    _elkeMinuut = Timer.periodic(const Duration(minutes: 1), (_) => unawaited(_kijk()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_kijk());
  }

  /// Voor toetsen.
  @visibleForTesting
  static void stop() {
    final w = _wacht;
    if (w != null) WidgetsBinding.instance.removeObserver(w);
    _wacht = null;
    _elkeMinuut?.cancel();
    _elkeMinuut = null;
  }
}

/// Wanneer het toestel van netwerk wisselt — wifi naar mobiel, Tailscale aan of uit — en wat de app
/// dan meteen doet.
///
/// **Waarom.** Stap 4 van "verbinden zoals Roon ARC" (plan 14-10-2026). Saber: "zeker als ik het
/// huis verlaat … heb ik ineens geen internet meer". De app merkte zo'n wissel pas als een verzoek
/// vastliep: een poll per vijftien seconden, met dertig seconden geduld per verzoek, en de open
/// verbindingen van het verdwenen wifi hielden alles vast. Nu zeggen Android (ConnectivityManager)
/// en iOS/macOS (NWPathMonitor) het zelf, over het kanaal `debridmusic/netwerk`.
///
/// Wat ermee gebeurt, staat in [Netwerkwacht]: elke melding in `verbinding.log`, en na een halve
/// seconde rust één keer opnieuw een adres kiezen (`ClientSession.netwerkVeranderd`).
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

class NetwerkGebeurtenis {
  const NetwerkGebeurtenis({
    required this.soort,
    this.netwerk = '',
    this.transport = '',
    this.gevalideerd = false,
  });

  /// Wat er gebeurde: `standaard-beschikbaar`, `standaard-weg`, `standaard-eigenschappen`,
  /// `fysiek-beschikbaar`, `fysiek-weg` (Android) of `pad` (iOS/macOS).
  final String soort;
  final String netwerk;

  /// `wifi`, `mobiel`, `vpn`, `kabel`, `weg`, `anders` of `onbekend`.
  final String transport;
  final bool gevalideerd;

  static NetwerkGebeurtenis? uit(Object? j) {
    if (j is! Map) return null;
    final soort = j['soort'];
    if (soort is! String || soort.isEmpty) return null;
    return NetwerkGebeurtenis(
      soort: soort,
      netwerk: '${j['netwerk'] ?? ''}',
      transport: '${j['transport'] ?? ''}',
      gevalideerd: j['gevalideerd'] == true,
    );
  }

  @override
  String toString() => '$soort $transport${gevalideerd ? '' : ' (nog niet gevalideerd)'}'
      '${netwerk.isEmpty ? '' : ' [$netwerk]'}';
}

const _kanaal = EventChannel('debridmusic/netwerk');

/// De meldingen van het toestel. Leeg op een pc (Windows): die wisselt niet van netwerk onderweg,
/// en daar is geen kanaal.
Stream<NetwerkGebeurtenis> netwerkGebeurtenissen() {
  if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) return const Stream.empty();
  return _kanaal
      .receiveBroadcastStream()
      .map(NetwerkGebeurtenis.uit)
      .where((g) => g != null)
      .cast<NetwerkGebeurtenis>()
      // Een kapot kanaal mag nooit de app raken; dan blijft de poll van vijftien seconden.
      .handleError((Object _) {});
}

/// Luistert naar [bron], schrijft elke melding op, en roept na [rust] stilte één keer [bijWissel].
///
/// * **De beginstand telt niet.** Android en iOS melden bij het aanmelden meteen het netwerk dat er
///   al is; dat is geen wissel, en de app is op dat moment zelf nog aan het verbinden.
/// * **Een reeks is één wissel.** Wifi weg, mobiel erbij, VPN opnieuw: dat komen vijf meldingen in
///   een halve seconde. Eén nieuwe keuze, op het eind.
/// * **Wat tijdens een keuze binnenkomt, gaat niet verloren**: dan volgt er nog één, na afloop.
class Netwerkwacht {
  Netwerkwacht({
    required this.bron,
    required this.bijWissel,
    this.log,
    this.rust = const Duration(milliseconds: 500),
  });

  final Stream<NetwerkGebeurtenis> bron;
  final Future<void> Function(String waarom) bijWissel;
  final void Function(String regel)? log;
  final Duration rust;

  StreamSubscription<NetwerkGebeurtenis>? _abonnement;
  Timer? _klok;
  bool _beginstand = true;
  bool _bezig = false;
  bool _nogEen = false;
  String _laatste = '';

  void start() {
    _abonnement ??= bron.listen((g) {
      log?.call('netwerk: $g');
      _laatste = g.toString();
      _klok?.cancel();
      _klok = Timer(rust, _rustig);
    });
  }

  Future<void> _rustig() async {
    if (_beginstand) {
      _beginstand = false;
      log?.call('netwerk: beginstand ($_laatste)');
      return;
    }
    if (_bezig) {
      _nogEen = true;
      return;
    }
    _bezig = true;
    try {
      do {
        _nogEen = false;
        await bijWissel(_laatste);
      } while (_nogEen);
    } catch (e) {
      log?.call('netwerk: opnieuw kiezen mislukte: $e');
    } finally {
      _bezig = false;
    }
  }

  Future<void> stop() async {
    _klok?.cancel();
    await _abonnement?.cancel();
    _abonnement = null;
  }
}

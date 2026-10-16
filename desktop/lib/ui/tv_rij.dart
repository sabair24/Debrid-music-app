/// Een rij tegels die op een tv onthoudt waar je stond.
///
/// **Waarom.** Saber, 16-10-2026, koos "waar je in die rij was", zoals Netflix: kom je van boven of
/// van onder een rij binnen, dan land je op de hoes waar je de vorige keer in die rij stond, en de
/// eerste keer op de eerste. Flutters richtingsnavigatie neemt de hoes die het dichtst bij de vorige
/// selectie ligt — zo landde je van de knop "Bekijken" op de TWEEDE hoes van "Recent toegevoegd",
/// omdat die knop rechts van het midden stond.
///
/// **Hoe.** Een `Focus` om de rij die zelf nooit de selectie neemt, en die meekijkt met de
/// [FocusManager]. Komt de selectie de rij binnen op een andere hoes dan de onthouden, dan gaat hij
/// daar meteen naartoe — in dezelfde beurt, vóór er een beeld getekend wordt, dus je ziet de eerste
/// landing niet. Buiten een tv is dit gewoon [TvRij.child].
library;

import 'package:flutter/widgets.dart';

import '../tv.dart';

class TvRij extends StatefulWidget {
  const TvRij({super.key, required this.child});

  final Widget child;

  @override
  State<TvRij> createState() => _TvRijState();
}

class _TvRijState extends State<TvRij> {
  final _knoop = FocusNode(debugLabel: 'tv-rij', canRequestFocus: false, skipTraversal: true);

  /// Waar je in deze rij het laatst stond.
  FocusNode? _laatste;

  /// Stond de selectie bij de vorige melding al in deze rij?
  bool _binnen = false;

  @override
  void initState() {
    super.initState();
    if (isTv) FocusManager.instance.addListener(_opFocus);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_opFocus);
    _knoop.dispose();
    super.dispose();
  }

  void _opFocus() {
    if (!mounted) return;
    final hier = FocusManager.instance.primaryFocus;
    final binnen = hier != null && hier.ancestors.contains(_knoop);
    if (binnen && !_binnen) {
      _binnen = true;
      final doel = landingInRij(_knoop, _laatste);
      if (doel != null && !identical(doel, hier)) {
        doel.requestFocus();
        return;
      }
    }
    _binnen = binnen;
    if (binnen) _laatste = hier;
  }

  @override
  Widget build(BuildContext context) => isTv
      ? Focus(focusNode: _knoop, canRequestFocus: false, skipTraversal: true, child: widget.child)
      : widget.child;
}

/// Waar de selectie hoort te landen als hij rij [rij] binnenkomt: op [laatste] als die er nog staat,
/// anders op de meest linkse hoes die er is. Publiek voor de toets.
@visibleForTesting
FocusNode? landingInRij(FocusNode rij, FocusNode? laatste) {
  if (laatste != null && laatste.context != null && laatste.canRequestFocus && laatste.ancestors.contains(rij)) {
    return laatste;
  }
  final kandidaten = [
    for (final n in rij.traversalDescendants)
      if (n is! FocusScopeNode && n.canRequestFocus) n,
  ];
  if (kandidaten.isEmpty) return null;
  kandidaten.sort((a, b) => a.rect.left.compareTo(b.rect.left));
  return kandidaten.first;
}

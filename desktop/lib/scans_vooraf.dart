// De hoezen en scans (voorkant, achterkant, cd) van de hele bibliotheek vooraf op dit toestel, thuis op wifi en op volle
// grootte van de pc (Saber, 02-11-2026: "er moet een manier gevonden worden dat de hoezen ook op de gsm staan" — gekozen:
// "Je hele bibliotheek", "Volle resolutie"; en "ik wil wel zeker altijd alle hoezen en afbeelding zien").
//
// **Waarom.** Zonder pc zocht de gsm de scans zelf op internet, op volle grootte: 43 albums op een middag, 5 tot 25 s per
// album, 103 MB mobiele data in twee uur (netstats van de gsm, 02-11-2026). Staan ze er al, dan kost Nu speelt niets.
import 'dart:async';

import 'package:flutter/foundation.dart';

/// Wat [ScansVooraf] bij één album vond.
enum Voorafstand {
  /// Stond er al, af.
  al,

  /// Nu van de pc gehaald.
  gehaald,

  /// De pc heeft (nog) geen scans van dit album: een volgende ronde.
  nietOpPc,

  /// Geen pc: de ronde houdt op.
  geenPc,
}

/// Eén ronde langs alle albums ([albums]), één tegelijk, zolang [mag] waar is (thuis op wifi, de instelling aan).
///
/// Wat er al ligt, kost niets (alleen schijf); de rest vraagt [haal] aan de pc. Een ronde begint opnieuw bij [kijk] —
/// een andere netsoort, een bibliotheek die veranderde — en anders elke [elke].
class ScansVooraf<T> {
  ScansVooraf({
    required this.albums,
    required this.mag,
    required this.haal,
    this.log,
    this.adem = const Duration(milliseconds: 200),
    this.elke = const Duration(hours: 6),
    this.opnieuwNa = const Duration(minutes: 5),
  });

  final List<T> Function() albums;
  final bool Function() mag;
  final Future<Voorafstand> Function(T album) haal;
  final void Function(String regel)? log;

  /// Tussen twee albums die de pc moest geven: de pc is ook nog voor iets anders.
  final Duration adem;
  final Duration elke;

  /// Een ronde die onderbroken werd (geen pc, even geen wifi): zo lang later nog eens, en niet pas na [elke].
  final Duration opnieuwNa;
  Timer? _herkans;

  /// Hoe ver de laatste ronde is: hoeveel albums er af op dit toestel staan, van hoeveel. Null zolang er geen ronde was.
  final ValueNotifier<({int klaar, int totaal})?> stand = ValueNotifier(null);

  Future<void>? _ronde;
  bool _nogEens = false;
  Timer? _klok;

  void start() {
    _klok ??= Timer.periodic(elke, (_) => kijk());
    kijk();
  }

  void stop() {
    _klok?.cancel();
    _klok = null;
    _herkans?.cancel();
    _herkans = null;
  }

  /// Nu een ronde, of meteen na de lopende.
  void kijk() {
    if (_ronde != null) {
      _nogEens = true;
      return;
    }
    if (!mag()) return;
    _ronde = ronde().then((r) {
      if (r.onderbroken) {
        _herkans ??= Timer(opnieuwNa, () {
          _herkans = null;
          kijk();
        });
      }
    }).whenComplete(() {
      _ronde = null;
      if (_nogEens) {
        _nogEens = false;
        kijk();
      }
    });
  }

  /// Eén ronde. Geeft terug wat ze deed.
  @visibleForTesting
  Future<({int al, int gehaald, int nietOpPc, bool onderbroken})> ronde() async {
    final lijst = albums();
    var al = 0, gehaald = 0, nietOpPc = 0;
    var onderbroken = false;
    for (final a in lijst) {
      if (!mag()) {
        onderbroken = true;
        break;
      }
      final Voorafstand s;
      try {
        s = await haal(a);
      } catch (_) {
        nietOpPc++;
        continue;
      }
      switch (s) {
        case Voorafstand.al:
          al++;
        case Voorafstand.gehaald:
          gehaald++;
          if (adem > Duration.zero) await Future<void>.delayed(adem);
        case Voorafstand.nietOpPc:
          nietOpPc++;
        case Voorafstand.geenPc:
          onderbroken = true;
      }
      if (onderbroken) break;
      stand.value = (klaar: al + gehaald, totaal: lijst.length);
    }
    stand.value = (klaar: al + gehaald, totaal: lijst.length);
    if (gehaald > 0 || onderbroken) {
      log?.call('scans vooraf: ${al + gehaald} van ${lijst.length} albums op dit toestel ($gehaald nu van de pc'
          '${nietOpPc > 0 ? ', $nietOpPc heeft de pc nog niet' : ''})${onderbroken ? ' — onderbroken' : ''}');
    }
    return (al: al, gehaald: gehaald, nietOpPc: nietOpPc, onderbroken: onderbroken);
  }
}

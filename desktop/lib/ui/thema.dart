/// Licht, donker of volgens het systeem — per toestel (Saber, 18-10-2026).
///
/// **Waarom een volledige herbouw en geen `Theme.of(context)` overal.** De app leest zijn kleuren
/// uit `ui/kleuren.dart`, op ruim elfhonderd plekken (geteld 18-10-2026), en niet uit het thema van
/// Material. Al die plekken omzetten naar `Theme.of(context)` levert niets anders op dan wat dit
/// bestand in twintig regels doet: bij een wissel zet het [Thema.licht] om en laat het élk element
/// opnieuw bouwen en élk vlak opnieuw tekenen — dezelfde weg die Flutter bij een hot reload neemt.
/// Pagina's, scrollstanden, de speler, open menu's en tekstvelden blijven waar ze waren, want er
/// wordt niets weggegooid; alleen opnieuw gebouwd. Dat kost één zwaar beeld, en het gebeurt alleen
/// als iemand de keuze omzet of het systeem van licht naar donker gaat.
///
/// **Vóór het eerste beeld.** [laad] leest het bestand synchroon, zodat een lichte app niet eerst
/// donker opflitst.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../paths.dart';
import 'kleuren.dart';

/// Wat er in Instellingen gekozen is.
enum ThemaKeuze {
  licht('Licht'),
  donker('Donker'),
  systeem('Volgens systeem');

  const ThemaKeuze(this.label);

  /// Zoals het in Instellingen staat.
  final String label;
}

/// Is het licht, bij deze keuze en deze systeemstand?
bool themaIsLicht(ThemaKeuze keuze, Brightness systeem) => switch (keuze) {
      ThemaKeuze.licht => true,
      ThemaKeuze.donker => false,
      ThemaKeuze.systeem => systeem == Brightness.light,
    };

/// De keuze van dit toestel, en het omzetten.
class ThemaStand {
  ThemaStand._();

  /// Wat er gekozen is. Standaard volgens het systeem (Saber).
  static final keuze = ValueNotifier<ThemaKeuze>(ThemaKeuze.systeem);

  /// Voor een regel in een logboek bij elke wissel.
  static void Function(String regel)? meld;

  /// In een toets: de systeemstand zonder echt scherm.
  @visibleForTesting
  static Brightness? systeemVoorToets;

  /// In een toets: wat er gebeurt in plaats van de echte herbouw.
  @visibleForTesting
  static void Function()? herbouwVoorToets;

  static File get _bestand => appFile('thema.json');
  static _Waarnemer? _waarnemer;

  static Brightness get _systeem => systeemVoorToets ?? PlatformDispatcher.instance.platformBrightness;

  /// Bij de start, vóór `runApp`: de keuze van schijf, en meteen de juiste kleuren.
  static void laad() {
    try {
      final j = jsonDecode(_bestand.readAsStringSync());
      if (j is Map && j['keuze'] is String) {
        keuze.value = ThemaKeuze.values.firstWhere((k) => k.name == j['keuze'], orElse: () => ThemaKeuze.systeem);
      }
    } catch (_) {
      // Geen bestand of onleesbaar: de standaard.
    }
    Thema.licht = themaIsLicht(keuze.value, _systeem);
    _balken();
    if (_waarnemer == null) {
      _waarnemer = _Waarnemer();
      WidgetsBinding.instance.addObserver(_waarnemer!);
    }
  }

  /// Een nieuwe keuze uit Instellingen: bewaren en meteen toepassen.
  static Future<void> zet(ThemaKeuze k) async {
    if (keuze.value == k) return;
    keuze.value = k;
    // Eerst omzetten, dan bewaren: de tik hoort meteen iets te doen.
    pasToe(waarom: 'keuze ${k.name}');
    try {
      await _bestand.writeAsString(jsonEncode({'keuze': k.name}));
    } catch (_) {
      // Niet bewaard: hij geldt nu wel, en bij de volgende start weer de oude.
    }
  }

  /// Kijkt opnieuw en bouwt alles opnieuw op als licht of donker daardoor verandert.
  static void pasToe({String waarom = 'systeem'}) {
    final licht = themaIsLicht(keuze.value, _systeem);
    if (licht == Thema.licht) return;
    Thema.licht = licht;
    _balken();
    meld?.call('thema: ${licht ? 'licht' : 'donker'} ($waarom)');
    final toets = herbouwVoorToets;
    if (toets != null) {
      toets();
      return;
    }
    // Alles opnieuw bouwen en tekenen, zonder iets weg te gooien. Zie de uitleg bovenaan.
    unawaited(WidgetsBinding.instance.reassembleApplication());
  }
}

/// De iconen in de statusbalk en de navigatiebalk van een telefoon: donker op licht, licht op donker.
/// Er staat nergens een AppBar die dat regelt, dus anders stonden ze wit op gebroken wit.
void _balken() {
  if (!(Platform.isAndroid || Platform.isIOS)) return;
  final l = Thema.licht;
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarIconBrightness: l ? Brightness.dark : Brightness.light,
    statusBarBrightness: l ? Brightness.light : Brightness.dark,
    systemNavigationBarIconBrightness: l ? Brightness.dark : Brightness.light,
  ));
}

class _Waarnemer with WidgetsBindingObserver {
  @override
  void didChangePlatformBrightness() => ThemaStand.pasToe();
}

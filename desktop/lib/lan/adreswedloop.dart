/// Alle adressen van de pc tegelijk proberen, en het eerste nemen dat de juiste pc blijkt.
///
/// **Waarom.** Stap 4 van "verbinden zoals Roon ARC" (plan 14-10-2026). Tot nu toe werden de
/// adressen ná elkaar geprobeerd, elk met vier seconden geduld: thuis de deur uit kostte zo eerst
/// een volle poging op het thuisadres dat buiten per definitie niets is, en pas daarna Tailscale.
/// Saber: "zeker als ik het huis verlaat … heb ik ineens geen internet meer". Nu lopen ze naast
/// elkaar: thuis meteen, Tailscale (en straks de eigen deur) een fractie later, drie seconden per
/// poging, en de eerste met de juiste [ServerHealth.serverId] wint.
///
/// **Thuis gaat voor als het snel is.** Antwoordt Tailscale eerst maar staat het thuisadres nog
/// open, dan wacht de wedloop tot [thuisVoorrang] om het thuisadres een kans te geven: thuis is
/// rechtstreeks, Tailscale een omweg. Antwoordt thuis niet binnen die tijd, dan wint Tailscale.
///
/// Zuiver: de vraag aan een adres komt binnen als functie, zodat de toets de klok zelf in de hand
/// heeft (`adreswedloop_test`, met fake_async).
library;

import 'dart:async';

import 'client.dart';

enum AdresSoort { thuis, tailscale, anders }

/// Wat voor adres dit is, uit het adres zelf.
AdresSoort adresSoort(Uri u) {
  final d = u.host.split('.').map(int.tryParse).toList();
  if (d.length == 4 && d.every((x) => x != null)) {
    final (a, b) = (d[0]!, d[1]!);
    if (a == 100 && b >= 64 && b <= 127) return AdresSoort.tailscale;
    if (a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) || a == 127) {
      return AdresSoort.thuis;
    }
    return AdresSoort.anders;
  }
  if (u.host == 'localhost') return AdresSoort.thuis;
  if (u.host.endsWith('.ts.net')) return AdresSoort.tailscale;
  return AdresSoort.anders;
}

class Kandidaat {
  const Kandidaat(this.adres, this.soort, this.start);
  final Uri adres;
  final AdresSoort soort;

  /// Wanneer deze poging begint, na het begin van de wedloop.
  final Duration start;
}

/// Thuis meteen; Tailscale en de rest na [later] (400 ms in het plan). Volgorde van [adressen]
/// blijft binnen een soort bewaard.
List<Kandidaat> kandidatenVoor(List<Uri> adressen, {Duration later = const Duration(milliseconds: 400)}) => [
      for (final u in adressen)
        Kandidaat(u, adresSoort(u), adresSoort(u) == AdresSoort.thuis ? Duration.zero : later),
    ];

class WedloopUitslag {
  const WedloopUitslag(this.winnaar, this.health, this.verloop);

  /// Het adres dat won, of null als geen enkel adres de juiste pc bleek.
  final Uri? winnaar;
  final ServerHealth? health;

  /// Per poging één regel, voor `verbinding.log`: adres, soort, na hoeveel ms, en hoe het afliep.
  final List<String> verloop;
}

/// De wedloop zelf. [vraag] is `RemoteClient.health` met een tijdslimiet; null = geen antwoord.
///
/// [verwachtServerId] leeg: elke pc die antwoordt telt (een koppeling van vóór 14-10-2026, die de
/// id nog moet leren). Anders telt alleen díe pc; een andere die antwoordt, staat als zodanig in
/// het verloop.
Future<WedloopUitslag> adresWedloop(
  List<Kandidaat> kandidaten, {
  required Future<ServerHealth?> Function(Uri adres, Duration tijdslimiet) vraag,
  String verwachtServerId = '',
  Duration perPoging = const Duration(seconds: 3),
  Duration thuisVoorrang = const Duration(milliseconds: 500),
}) {
  final klaar = Completer<WedloopUitslag>();
  final verloop = <String>[];
  if (kandidaten.isEmpty) return Future.value(const WedloopUitslag(null, null, ['geen adressen om te proberen']));

  // Alleen voor de getallen in het verloop. De beslissingen hangen aan timers, niet aan een klok —
  // zo gaat de toets er met nep-tijd doorheen zoals het toestel er in echte tijd doorheen gaat.
  final klok = Stopwatch()..start();
  var open = kandidaten.length;
  var openThuis = kandidaten.where((k) => k.soort == AdresSoort.thuis).length;
  ({Kandidaat k, ServerHealth h})? besteAnder;
  final timers = <Timer>[];
  var voorrangVoorbij = false;

  void sluit(Uri? adres, ServerHealth? h) {
    if (klaar.isCompleted) return;
    for (final t in timers) {
      t.cancel();
    }
    klaar.complete(WedloopUitslag(adres, h, List.unmodifiable(verloop)));
  }

  void besluit() {
    if (klaar.isCompleted) return;
    final b = besteAnder;
    if (b != null && (openThuis == 0 || voorrangVoorbij)) {
      sluit(b.k.adres, b.h);
      return;
    }
    if (open == 0) sluit(null, null);
  }

  // Na [thuisVoorrang] krijgt thuis geen voorrang meer: dan wint wie er al juist antwoordde.
  timers.add(Timer(thuisVoorrang, () {
    voorrangVoorbij = true;
    besluit();
  }));

  for (final k in kandidaten) {
    timers.add(Timer(k.start, () async {
      if (klaar.isCompleted) return;
      final begin = klok.elapsedMilliseconds;
      ServerHealth? h;
      String hoe;
      try {
        h = await vraag(k.adres, perPoging).timeout(perPoging, onTimeout: () => null);
        hoe = h == null ? 'geen antwoord' : 'antwoordt';
      } catch (e) {
        h = null;
        hoe = 'fout (${e.runtimeType})';
      }
      // Streng zodra de id bekend is: ook een antwoord zónder id is dan een andere pc.
      final juist = h != null && (verwachtServerId.isEmpty || h.serverId == verwachtServerId);
      if (h != null && !juist) hoe = 'een andere pc (${h.serverId.isEmpty ? 'zonder id' : h.serverId})';
      verloop.add('${k.adres.authority} [${k.soort.name}] na ${klok.elapsedMilliseconds - begin} ms: $hoe');
      open--;
      if (k.soort == AdresSoort.thuis) openThuis--;
      if (klaar.isCompleted) return;
      if (juist) {
        if (k.soort == AdresSoort.thuis) {
          sluit(k.adres, h);
          return;
        }
        // Niet meteen winnen als thuis nog open is en de voorrang nog loopt: [besluit] wacht dan.
        besteAnder ??= (k: k, h: h);
      }
      besluit();
    }));
  }
  return klaar.future;
}

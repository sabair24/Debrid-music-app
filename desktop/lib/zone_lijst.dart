/// De zones op dit toestel: de lijst zoals de pc hem het laatst stuurde (zie `lan/zones.dart`), en op een
/// gsm, iPad, Mac of Shield de lijn naar de pc die hem bijhoudt.
///
/// **De lijn ([ZoneVerbinding]).** Eén openstaande vraag naar `/api/zones/events`; de pc stuurt elke
/// wijziging meteen. Valt de lijn weg (wifi weg, pc slaapt, ander adres), dan opnieuw: na 1, 2, 4 … tot
/// 30 seconden, en meteen bij een netwerkwissel of als de app terugkomt ([ZoneVerbinding.nuOpnieuw]).
/// Stilte langer dan [kZoneStilte] (de pc pingt om de vijftien seconden) is ook een dode lijn. Een pc van
/// vóór de zones antwoordt 404: dan niets tonen, en om de vijf minuten opnieuw vragen (misschien werd hij
/// net bijgewerkt).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'lan/client.dart' show RemoteClient, RemoteException, rijGeheugen;
import 'lan/zones.dart';

/// Langer stil dan dit: de lijn is dood, ook al zegt het besturingssysteem van niet.
const kZoneStilte = Duration(seconds: 45);

/// Hoe lang een pc zonder zones met rust gelaten wordt.
const kZoneOudePc = Duration(minutes: 5);

/// Een opdracht naar de pc ([vraag]), en één keer opnieuw als de eerste geen antwoord kreeg ([RemoteException] zonder
/// status). Null als ze aankwam, anders waarom niet.
///
/// Gemeten op 27-10-2026 met de gsm als afstandsbediening van de Shield: na vijf minuten op de achtergrond kwam de
/// tik op "volgende" wel in de app aan (logcat 06:14:28.401), maar nooit bij de pc. De eerste vraag na het terugkomen
/// viel op een verbinding die de pc intussen gesloten had en die de gsm nog in voorraad hield; een tweede vraag opent
/// een verse. Het id van de opdracht zorgt dat de pc hem hoogstens één keer uitvoert ([LanServer.zoneOpdracht]), ook
/// als de eerste toch aankwam en alleen het antwoord wegviel. Een antwoord van de pc (een status) wordt niet herhaald.
Future<String?> stuurMetHerkansing(Future<void> Function() vraag) async {
  for (var poging = 1;; poging++) {
    try {
      await vraag();
      return null;
    } on RemoteException catch (e) {
      if (e.statusCode != null || poging >= 2) return e.message;
    }
  }
}

/// Wat dit toestel van de zones weet. Eén per app.
class ZoneLijst extends ChangeNotifier {
  ZoneLijst({required this.hier, this.opDePc = false, int Function()? klok}) : _klok = klok;

  /// De zone van dit toestel (`dev:<id>`).
  final String hier;

  /// Is dit de pc (die de zones zelf bijhoudt, en "Speel daar" kan)?
  final bool opDePc;

  /// De volledige stand van een zone, met de wachtrij — voor "Hier verder". Gezet door main: op de pc uit
  /// zijn eigen server, op een toestel via `/api/zones/stand`.
  Future<Map<String, dynamic>?> Function(String zone)? haalStand;

  /// De muziek van zone `van` naar zone `naar` verplaatsen; null als het lukte, anders waarom niet.
  /// Gezet door main: op de pc rechtstreeks, op een toestel via `/api/zone/transfer`.
  Future<String?> Function(String van, String naar)? verplaats;

  /// Een opdracht naar een zone (`{cmd, …}`), bijvoorbeeld `groepeer`; null als ze aankwam. Gezet door main.
  Future<String?> Function(String zone, Map<String, dynamic> opdracht)? stuur;

  final int Function()? _klok;
  int get _nu => _klok?.call() ?? DateTime.now().millisecondsSinceEpoch;

  ZoneLijstStand? _stand;

  /// Kent de pc zones? Pas waar na de eerste lijst; een pc van vóór de zones blijft op onwaar.
  bool get ondersteund => _stand != null;

  /// Staat de lijn naar de pc nu open (op de pc zelf altijd)?
  bool get verbonden => _verbonden;
  bool _verbonden = false;

  /// Alle zones, dit toestel vooraan.
  List<ZoneStaat> get zones => _stand?.zones ?? const [];

  /// De andere zones.
  Iterable<ZoneStaat> get anderen => zones.where((z) => z.id != hier);

  /// De zone van dit toestel, als de pc hem kent.
  ZoneStaat? get dezeZone => zones.where((z) => z.id == hier).firstOrNull;

  /// Speelt er ergens anders iets?
  bool get eldersSpeeltIets => anderen.any((z) => z.playing);

  /// Hoe laat het nu op de pc is (voor de plek in een nummer op een ander toestel). Zonder lijst: de
  /// eigen klok.
  int nuOpPc() => _stand?.nuOpPc(_nu) ?? _nu;

  /// Een nieuwe lijst van de pc (`{nu, zones}`).
  void zet(Map<String, dynamic> m) {
    final nieuw = ZoneLijstStand.uitJson(m, ontvangenMs: _nu);
    final oud = _stand;
    _stand = nieuw;
    if (oud == null || !listEquals(oud.zones, nieuw.zones)) notifyListeners();
  }

  void zetVerbonden(bool open) {
    if (open == _verbonden) return;
    _verbonden = open;
    notifyListeners();
  }

  /// De pc kent geen zones (meer): niets tonen.
  void vergeet() {
    if (_stand == null && !_verbonden) return;
    _stand = null;
    _verbonden = false;
    notifyListeners();
  }
}

/// De lijn van een toestel naar de zones op de pc. Zie de uitleg bovenaan.
class ZoneVerbinding {
  ZoneVerbinding({
    required this.lijst,
    required this.client,
    required this.toestel,
    required this.naam,
    this.platform = '',
    this.tv = false,
    this.opStand,
    this.opOpdracht,
    this.log,
  });

  final ZoneLijst lijst;

  /// De verbinding met de pc van dit moment, of null zonder pc. Elke poging vraagt hem opnieuw: na een
  /// adreswissel is het een andere.
  final RemoteClient? Function() client;
  final String toestel, naam, platform;
  final bool tv;

  /// De laatste melding van wie dan ook en het laatste "Speel op …" (`{progress, verzoek}`), zodra de pc
  /// ze stuurt: voor "Hier verder luisteren".
  final void Function(Map<String, dynamic>? progress, Map<String, dynamic>? verzoek)? opStand;

  /// Een opdracht voor DIT toestel, van een ander toestel dat het als zone bedient (`{cmd, …}`, zie
  /// zone_opdracht.dart).
  final void Function(Map<String, dynamic> opdracht)? opOpdracht;

  /// Eén regel per verandering van de lijn, voor een logboek. Nooit per bericht.
  final void Function(String)? log;

  bool _loopt = false;

  /// Elke start een nieuwe ronde: een lus van vóór een stop die nog in een wachttijd zat, ziet dat hij
  /// niet meer de huidige is en houdt op (anders liepen er na stop-start twee lijnen).
  int _ronde = 0;
  Completer<void>? _wekker;

  /// Loopt de lijn (of probeert ze het)?
  bool get loopt => _loopt;

  void start() {
    if (_loopt) return;
    _loopt = true;
    unawaited(_lus(++_ronde));
  }

  void stop() {
    if (!_loopt) return;
    _loopt = false;
    _ronde++;
    _sluitLijn();
    _wek();
    lijst.zetVerbonden(false);
  }

  /// Nu meteen opnieuw: een netwerkwissel, de app kwam terug, een ander adres. Een lijn die gewoon
  /// open staat, blijft open; een die wacht, wacht niet langer.
  void nuOpnieuw({bool ookAlsOpen = false}) {
    if (ookAlsOpen) _sluitLijn();
    _wek();
  }

  void _sluitLijn() {
    final k = _klaar;
    if (k != null && !k.isCompleted) k.complete();
  }

  Completer<void>? _klaar;

  void _wek() {
    final w = _wekker;
    _wekker = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<void> _slaap(Duration d) async {
    final w = _wekker = Completer<void>();
    await Future.any([w.future, Future<void>.delayed(d)]);
    _wekker = null;
  }

  Future<void> _lus(int ronde) async {
    bool weg() => ronde != _ronde;
    var wacht = const Duration(seconds: 1);
    while (!weg()) {
      final c = client();
      if (c == null) {
        lijst.zetVerbonden(false);
        await _slaap(const Duration(seconds: 5));
        continue;
      }
      final uitkomst = await _eenLijn(c, weg);
      if (weg()) break;
      lijst.zetVerbonden(false);
      switch (uitkomst) {
        case _Uitkomst.oudePc:
          lijst.vergeet();
          log?.call('zones: de pc kent geen zones (404) — over ${kZoneOudePc.inMinutes} min opnieuw');
          await _slaap(kZoneOudePc);
          wacht = const Duration(seconds: 1);
        case _Uitkomst.wasOpen:
          // Ze stond open en viel weg: snel terug.
          wacht = const Duration(seconds: 1);
          await _slaap(wacht);
        case _Uitkomst.mislukt:
          // Intussen de lijst één keer gewoon vragen: anders staat er tot de lijn terug is een oude.
          try {
            lijst.zet(await c.zones());
          } catch (_) {}
          await _slaap(wacht);
          wacht = Duration(seconds: min(wacht.inSeconds * 2, 30));
      }
    }
  }

  Future<_Uitkomst> _eenLijn(RemoteClient c, bool Function() weg) async {
    final klaar = _klaar = Completer<void>();
    var open = false;
    var uitkomst = _Uitkomst.mislukt;
    Timer? stilte;
    void wakker() {
      stilte?.cancel();
      stilte = Timer(kZoneStilte, () {
        log?.call('zones: ${kZoneStilte.inSeconds} s niets van de pc — opnieuw');
        if (!klaar.isCompleted) klaar.complete();
      });
    }

    wakker();
    final sub = c.zoneStroom(toestel: toestel, naam: naam, platform: platform, tv: tv).listen(
      (e) {
        if (weg() || klaar.isCompleted) return;
        wakker();
        if (!open) {
          open = true;
          uitkomst = _Uitkomst.wasOpen;
          lijst.zetVerbonden(true);
          log?.call('zones: lijn open naar ${c.endpoint.baseUrl.authority}');
        }
        if (e.event == 'ping') return;
        final Object? data;
        try {
          data = jsonDecode(e.data);
        } catch (_) {
          return;
        }
        if (data is! Map) return;
        final m = data.cast<String, dynamic>();
        switch (e.event) {
          case 'zones':
            lijst.zet(m);
          case 'cmd':
            opOpdracht?.call(m);
          case 'stand':
            opStand?.call(rijGeheugen.herstel((m['progress'] as Map?)?.cast<String, dynamic>()),
                (m['verzoek'] as Map?)?.cast<String, dynamic>());
        }
      },
      onError: (Object e) {
        if (e is RemoteException && e.statusCode == 404) uitkomst = _Uitkomst.oudePc;
        if (open) log?.call('zones: lijn weg ($e)');
        if (!klaar.isCompleted) klaar.complete();
      },
      onDone: () {
        if (open) log?.call('zones: lijn dicht');
        if (!klaar.isCompleted) klaar.complete();
      },
      cancelOnError: true,
    );
    await klaar.future;
    stilte?.cancel();
    await sub.cancel();
    if (identical(_klaar, klaar)) _klaar = null;
    return uitkomst;
  }
}

enum _Uitkomst { wasOpen, mislukt, oudePc }

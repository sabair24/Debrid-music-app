/// De deur naar buiten: één toewijzing in de modem, van buitenpoort 47821 (of een vrije) naar 47821 op
/// deze pc — de versleutelde ingang met de witte lijst (`server.dart`, `Ingang.tlsBuiten`).
///
/// Stap 7 van "verbinden zoals Roon ARC" (plan 14-10-2026). **Standaard uit.** Een poort in de modem is
/// een beveiligingsinstelling van Saber; pas als hij "Bereikbaar van buitenaf" zelf aanzet, vraagt de
/// app de modem om de deur. Uitzetten wist hem meteen, en elke ronde kijkt opnieuw na of hij er nog
/// staat, naar deze pc wijst en zijn lease niet verliest.
///
/// Gemeten op de Sagemcom F3896LG (poortproef 14-10-2026): hij rondt een korte lease af naar 900 s en
/// verlengt bij een tweede `AddPortMapping`. Daarom wordt vernieuwd op de lease die hij **geeft**, niet
/// op wat gevraagd werd, en wordt na elke keer nagelezen of de klok terugsprong.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'igd.dart';
import 'poorten.dart';
import 'tokens.dart' show DeviceGrant;

/// Hoe de deur in de modem heet. Zo herkent de app een eigen deur van vroeger (een ander adres na een
/// nieuwe DHCP-lease) en blijft hij van die van anderen af.
const kDeurNaam = 'DebridMusic';

/// Wat gevraagd wordt; de modem mag minder geven (zie [DeurNaarBuiten.toegekend]).
const kDeurLease = 3600;

/// Andere buitenpoorten als 47821 bezet is (718). Nooit 47820 of 47822: die horen nooit van buiten.
const kUitwijkPoorten = [47831, 47832, 47833, 47834, 47835, 47836, 47837, 47838, 47839];

enum DeurStand { uit, bezig, open, mislukt }

/// Is dit een adres op het internet (geen privé-reeks, geen CGNAT)?
bool isPubliekAdres(String ip) {
  final d = ip.split('.').map(int.tryParse).toList();
  if (d.length != 4 || d.any((x) => x == null || x < 0 || x > 255)) return false;
  final (a, b) = (d[0]!, d[1]!);
  if (a == 0 || a == 10 || a == 127 || a >= 224) return false;
  if (a == 100 && b >= 64 && b <= 127) return false; // CGNAT
  if (a == 169 && b == 254) return false;
  if (a == 172 && b >= 16 && b <= 31) return false;
  if (a == 192 && b == 168) return false;
  return true;
}

/// Een publiek adres voor in een logboek: alleen het eerste getal.
String maskeerAdres(String ip) {
  final d = ip.split('.');
  return d.length == 4 ? '${d.first}.x.x.x' : 'x';
}

/// De zin onder "Bereikbaar van buitenaf" op de pc.
String deurTekst({
  required bool aan,
  required DeurStand stand,
  int? poort,
  String? waarom,
  DateTime? laatstVanBuiten,
}) {
  if (!aan) {
    return 'Je pc wordt van het internet bereikbaar, alleen voor je eigen toestellen en versleuteld, zoals '
        'Roon ARC. De app zet daarvoor zelf een deur in je modem (UPnP), en haalt hem weg zodra je dit uitzet.';
  }
  String uur(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  return switch (stand) {
    DeurStand.open => 'Aan: je toestellen komen er van buiten in, rechtstreeks en versleuteld'
        '${poort != null && poort != kPubliekPoort ? ' (via poort $poort, 47821 was bezet)' : ''}.'
        '${laatstVanBuiten == null ? ' Nog geen toestel kwam van buiten binnen.' : ' Laatst via het publieke adres om ${uur(laatstVanBuiten)}.'}'
        ' Uitzetten haalt de deur meteen uit je modem.',
    DeurStand.mislukt => waarom ?? 'De deur in je modem lukt niet.',
    _ => 'Bezig: de deur in je modem zetten…',
  };
}

/// Wanneer een toestel het laatst langs de eigen deur binnenkwam (`lastSeenVia == 'buiten'`), of null.
DateTime? laatstVanBuiten(Iterable<DeviceGrant> toestellen) {
  int? beste;
  for (final g in toestellen) {
    final t = g.lastSeenAt;
    if (g.lastSeenVia == 'buiten' && t != null && (beste == null || t > beste)) beste = t;
  }
  return beste == null ? null : DateTime.fromMillisecondsSinceEpoch(beste);
}

/// De stappen voor de hand als UPnP niet lukt (stap 7.5), voor de Sagemcom van Telenet en de meeste modems.
String deurMetDeHand(String? ditAdres) {
  final pc = ditAdres ?? 'deze pc';
  return 'Met de hand: open je modem (meestal http://192.168.0.1). Geef $pc een vaste plaats '
      '(DHCP-reservering), en maak bij "Port Forwarding" één regel: TCP, buiten 47821 → binnen 47821, naar $pc. '
      'Nooit 47820 of 47822.';
}

class DeurNaarBuiten extends ChangeNotifier {
  DeurNaarBuiten({
    this.internePoort = kPubliekPoort,
    Igd? igd,
    Future<IgdDienst?> Function()? zoekModem,
    this.log,
    DateTime Function()? klok,
    this.ronde = const Duration(minutes: 10),
    this.adresElke = const Duration(minutes: 5),
  })  : igd = igd ?? Igd(),
        _klok = klok ?? DateTime.now {
    _zoek = zoekModem ?? () => this.igd.zoek();
  }

  /// Waar de versleutelde buiteningang op deze pc luistert.
  final int internePoort;
  final Igd igd;
  late final Future<IgdDienst?> Function() _zoek;
  final void Function(String regel)? log;
  final DateTime Function() _klok;

  /// Hoe vaak de deur opnieuw gezet en nagekeken wordt (en nooit later dan de halve lease).
  final Duration ronde;

  /// Hoe vaak het publieke adres opnieuw gevraagd wordt.
  final Duration adresElke;

  bool _aan = false;
  bool get aan => _aan;
  DeurStand stand = DeurStand.uit;

  /// Waarom het niet lukt, in een zin voor het scherm.
  String? waarom;

  /// Het publieke adres van de modem, zodra het een echt publiek adres is.
  String? publiekAdres;

  /// De buitenpoort van de deur (47821, of een vrije als die bezet was).
  int? externePoort;
  DateTime? laatstGezet;

  /// De lease die de modem gaf (seconden), of null zolang er geen deur stond.
  int? toegekend;

  /// De modem kent alleen vaste deuren (725): dan lease 0.
  bool vast = false;

  /// Een deur naar 47820 of 47822 in de modem: die hoort er niet.
  String? rodeMelding;

  IgdDienst? _dienst;
  int? _vorigeUptime;
  DateTime? _adresGevraagd;
  Timer? _volgende;
  Future<void>? _bezig;

  /// Het adres dat de toestellen mogen proberen, of null zolang de deur niet open is.
  Uri? get adresVoorToestellen {
    final ip = publiekAdres;
    final p = externePoort;
    if (stand != DeurStand.open || ip == null || p == null) return null;
    return Uri(scheme: 'https', host: ip, port: p);
  }

  void _log(String r) => log?.call(r);

  /// Aanzetten (Saber zette de schakelaar om): meteen een ronde, daarna op de klok.
  Future<void> zetAan() async {
    if (_aan) return;
    _aan = true;
    stand = DeurStand.bezig;
    notifyListeners();
    _log('deur naar buiten: AAN');
    await nuEenRonde();
  }

  /// Uitzetten: de deur meteen weg uit de modem, en nagekeken dat hij weg is.
  Future<void> zetUit() async {
    final was = _aan || externePoort != null;
    _aan = false;
    _volgende?.cancel();
    _volgende = null;
    await _bezig;
    final d = _dienst;
    final p = externePoort;
    if (d != null && p != null) {
      try {
        await igd.wis(d, p);
        final nog = await igd.lees(d, p);
        _log(nog == null ? 'deur $p gewist (714 bevestigd)' : 'deur $p staat er na het wissen NOG: ${nog.client}:${nog.internePoort}');
      } catch (e) {
        _log('deur $p wissen mislukte: $e');
      }
    }
    externePoort = null;
    toegekend = null;
    stand = DeurStand.uit;
    waarom = null;
    if (was) _log('deur naar buiten: UIT');
    notifyListeners();
  }

  /// Eén ronde nu, en daarna de volgende inplannen. Twee tegelijk kan niet.
  Future<void> nuEenRonde() {
    final lopend = _bezig;
    if (lopend != null) return lopend;
    final werk = _ronde().whenComplete(() {
      _bezig = null;
    });
    _bezig = werk;
    return werk;
  }

  /// Wanneer de volgende ronde komt: [ronde], maar nooit later dan de halve toegekende lease.
  @visibleForTesting
  Duration get tussenpoos {
    final l = toegekend;
    if (vast || l == null || l <= 0) return ronde;
    final half = Duration(seconds: max(30, l ~/ 2));
    return half < ronde ? half : ronde;
  }

  void _plan() {
    _volgende?.cancel();
    if (!_aan) return;
    _volgende = Timer(tussenpoos, () => unawaited(nuEenRonde()));
  }

  Future<void> _ronde() async {
    if (!_aan) return;
    try {
      final d = _dienst ??= await _zoek();
      if (d == null) {
        _mislukt('Geen modem met UPnP gevonden. Zet UPnP aan in je modem, of zet de deur met de hand '
            '(zie de stappen hieronder).');
        return;
      }
      // Is de modem herstart? Dan is elke deur weg en het adres misschien nieuw.
      int? up;
      try {
        up = await igd.uptime(d);
      } catch (_) {/* niet elke modem zegt het */}
      final herstart = up != null && _vorigeUptime != null && up < _vorigeUptime!;
      if (up != null) _vorigeUptime = up;
      if (herstart) _log('modem herstart (uptime $up s): adres en deur opnieuw');

      final nu = _klok();
      final adresOud = _adresGevraagd;
      if (herstart || publiekAdres == null || adresOud == null || nu.difference(adresOud) >= adresElke) {
        final ip = await igd.publiekAdres(d);
        _adresGevraagd = nu;
        if (ip == null || !isPubliekAdres(ip)) {
          publiekAdres = null;
          _mislukt('Je modem heeft zelf geen publiek adres (${ip ?? 'geen'}): er zit nog een router of je '
              'provider tussen (dubbele NAT of CGNAT). Rechtstreeks van buiten kan dan niet; Tailscale blijft werken.');
          return;
        }
        if (ip != publiekAdres) _log('publiek adres ${maskeerAdres(ip)}');
        publiekAdres = ip;
      }

      await _zetDeur(d, herstart: herstart);
      await _controleerAndere(d);
      if (!_aan) return; // intussen uitgezet
      stand = DeurStand.open;
      waarom = null;
      laatstGezet = _klok();
    } on IgdFout catch (f) {
      _mislukt(switch (f.code) {
        606 => 'Je modem laat de app geen deur zetten (UPnP-fout 606). Zet de deur met de hand.',
        501 => 'Je modem weigerde de deur (UPnP-fout 501). Zet de deur met de hand.',
        _ => 'De modem weigerde: $f.',
      });
    } on Object catch (e) {
      // Onbereikbaar of iets onverwachts: volgende ronde opnieuw zoeken.
      _dienst = null;
      _mislukt('De modem antwoordt niet ($e).');
    } finally {
      notifyListeners();
      _plan();
    }
  }

  void _mislukt(String zin) {
    stand = _aan ? DeurStand.mislukt : DeurStand.uit;
    waarom = zin;
    _log('deur naar buiten MISLUKT: $zin');
  }

  bool _vanOns(IgdDeur x, IgdDienst d) => x.internePoort == internePoort && x.client == d.lokaal;

  Future<void> _zetDeur(IgdDienst d, {required bool herstart}) async {
    final kandidaten = <int>{if (externePoort != null) externePoort!, internePoort, ...kUitwijkPoorten}
      ..removeWhere((p) => p == kHttpPoort || p == kTlsPoort);
    for (final ext in kandidaten) {
      var bestaand = await igd.lees(d, ext);
      if (bestaand != null && !_vanOns(bestaand, d)) {
        if (bestaand.naam == kDeurNaam) {
          // Een eigen deur van vroeger, naar een oud adres van deze pc (een nieuwe DHCP-lease): weg ermee.
          _log('oude eigen deur $ext naar ${bestaand.client}:${bestaand.internePoort} — wissen');
          await igd.wis(d, ext);
          bestaand = null;
        } else {
          _log('buitenpoort $ext is van iets anders ("${bestaand.naam}" → ${bestaand.client}:${bestaand.internePoort})');
          continue;
        }
      }
      try {
        await igd.zet(d, extern: ext, intern: internePoort, lease: vast ? 0 : kDeurLease, naam: kDeurNaam);
      } on IgdFout catch (f) {
        if (f.code == 718) {
          _log('buitenpoort $ext bezet (718) — de volgende');
          continue;
        }
        if (f.code != 725 || vast) rethrow;
        vast = true;
        _log('de modem kent alleen vaste deuren (725): lease 0');
        await igd.zet(d, extern: ext, intern: internePoort, lease: 0, naam: kDeurNaam);
      }
      var na = await igd.lees(d, ext);
      if (na == null || !_vanOns(na, d)) throw StateError('de deur $ext staat er na het zetten niet');
      final eerder = toegekend;
      if (!vast && bestaand != null && eerder != null && eerder > 0 && na.lease < eerder - 60) {
        // Niet verlengd: de klok liep door. Wissen en opnieuw, anders gaat hij straks vanzelf dicht.
        _log('lease niet verlengd ($ext: nog ${na.lease} s van $eerder) — wissen en opnieuw zetten');
        await igd.wis(d, ext);
        await igd.zet(d, extern: ext, intern: internePoort, lease: kDeurLease, naam: kDeurNaam);
        na = await igd.lees(d, ext);
        if (na == null || !_vanOns(na, d)) throw StateError('de deur $ext staat er na opnieuw zetten niet');
      }
      if (!vast && (bestaand == null || eerder == null || herstart)) {
        toegekend = na.lease;
        if (na.lease > 0 && na.lease != kDeurLease) _log('de modem gaf een lease van ${na.lease} s (gevraagd $kDeurLease)');
      }
      if (ext != externePoort) _log('deur gezet: buiten $ext → ${d.lokaal}:$internePoort');
      externePoort = ext;
      return;
    }
    throw const IgdFout(718, 'geen vrije buitenpoort');
  }

  /// Een deur naar 47820 of 47822 (door een ander toestel, of met de hand): rood melden. Die twee mogen
  /// nooit van buiten bereikbaar zijn — de witte lijst staat alleen op 47821.
  Future<void> _controleerAndere(IgdDienst d) async {
    String? melding;
    for (final p in const [kHttpPoort, kTlsPoort]) {
      try {
        final x = await igd.lees(d, p);
        if (x != null) {
          melding = 'In je modem staat een deur op poort $p (naar ${x.client}:${x.internePoort}'
              '${x.naam.isEmpty ? '' : ', "${x.naam}"'}). Die hoort er niet: van buiten mag alleen de deur '
              'van DebridMusic. Haal hem weg in je modem.';
          _log('ROOD: deur op buitenpoort $p naar ${x.client}:${x.internePoort} "${x.naam}"');
        }
      } catch (_) {/* niet te lezen is geen melding */}
    }
    rodeMelding = melding;
  }

  @override
  void dispose() {
    _volgende?.cancel();
    super.dispose();
  }
}

/// Voor een toets die op een andere machine draait: het adres waarop deze pc een socket naar [host]
/// opent. Zelfde manier als [Igd.dienstVan].
@visibleForTesting
Future<String> lokaalAdresNaar(String host, int poort) async {
  final s = await Socket.connect(host, poort, timeout: const Duration(seconds: 3));
  final a = s.address.address;
  s.destroy();
  return a;
}

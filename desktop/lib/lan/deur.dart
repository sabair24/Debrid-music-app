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
import 'dart:convert';
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
  bool metDeHand = false,
}) {
  if (!aan) {
    return 'Je pc wordt van het internet bereikbaar, alleen voor je eigen toestellen en versleuteld, zoals '
        'Roon ARC. De app zet daarvoor zelf een deur in je modem (UPnP), en haalt hem weg zodra je dit uitzet.';
  }
  String uur(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final wanneer = laatstVanBuiten == null
      ? ' Nog geen toestel kwam van buiten binnen.'
      : ' Laatst via het publieke adres om ${uur(laatstVanBuiten)}.';
  if (stand == DeurStand.open && metDeHand) {
    return 'Aan, met de hand: de UPnP van je modem antwoordt niet, dus gebruiken je toestellen je eigen regel in de '
        'modem (TCP 47821 → deze pc, en 443 → 47821 als je die tweede regel ook zette).$wanneer';
  }
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
      'Nooit 47820 of 47822. Voor een netwerk dat alleen webverkeer doorlaat (veel bedrijfs- en gastwifi) nog een '
      'tweede regel: TCP, buiten 443 → binnen 47821, naar $pc.';
}

/// De buitenadressen voor de toestellen bij één deur [deur]: de deur zelf, en hetzelfde publieke adres op [kWebPoort]
/// (de tweede regel in de modem, [deurMetDeHand]). Leeg zonder deur. Een toestel probeert ze naast elkaar
/// (`adreswedloop.dart`) en vertrouwt alleen het certificaat van de pc, dus een 443 waar iets anders op zit kost niets.
List<Uri> buitenAdressen(Uri? deur) {
  if (deur == null) return const [];
  return [deur, if (deur.port != kWebPoort) deur.replace(port: kWebPoort)];
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
    this.onthouden,
    this.vraagPubliekAdres,
  })  : igd = igd ?? Igd(),
        _klok = klok ?? DateTime.now {
    _zoek = zoekModem ??
        () async {
          // **Eerst waar hij de vorige keer stond**, zonder zoektocht. Gemeten op 15-10-2026: bij het
          // opstarten van 3.9.486 vond de zoektocht (SSDP) de modem niet, terwijl vijf losse zoektochten
          // daarna en de start van 3.9.487 hem wel vonden — bij het opstarten is de app zo druk dat het
          // antwoord van de modem te laat gelezen wordt. Een vaste vraag naar het bekende adres heeft
          // daar geen last van.
          final l = onthouden?.lees();
          if (l != null) {
            try {
              final d = await this.igd.zoek(locatie: l);
              if (d != null) return d;
            } catch (_) {/* dan zoeken */}
          }
          return this.igd.zoek();
        };
  }

  /// Het publieke adres zonder de modem te vragen ([publiekAdresViaInternet]), voor als UPnP niet werkt — zie
  /// [metDeHand]. Null in een toets: die raakt het internet niet.
  final Future<String?> Function()? vraagPubliekAdres;

  /// Open met de hand: de UPnP van de modem werkt niet, en de toestellen krijgen het publieke adres met 47821 — de
  /// regel die je zelf in de modem zette ([deurMetDeHand]).
  ///
  /// **Waarom.** Op 25-10-2026 antwoordde de UPnP van de Sagemcom met 404, ook na een herstart en met UPnP aan, terwijl
  /// de regel TCP 47821 → 192.168.0.117 al lang met de hand in de modem stond. Het adres voor de toestellen kwam
  /// alleen uit UPnP, dus wist de gsm nergens aan te kloppen: "buitenshuis werkt nog niet, heb de modem daarnet
  /// nochtans herstart ??". Of de regel er staat, valt van binnenuit niet na te gaan; komt een toestel er van buiten
  /// binnen, dan staat dat in de zin eronder.
  bool metDeHand = false;

  /// Waar de modem de vorige keer gevonden werd (een bestand in de app-map). Null in een toets.
  final ({Uri? Function() lees, void Function(Uri locatie) bewaar})? onthouden;

  /// Hoe vaak de ronde na elkaar mislukte: dan sneller opnieuw (30 s, 1, 2, 5 min, dan [ronde]).
  int _mislukt = 0;

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

  /// Alle buitenadressen voor de toestellen: de deur zelf, en hetzelfde adres op [kWebPoort] (443) voor een netwerk dat
  /// alleen webverkeer doorlaat ([buitenAdressen]).
  List<Uri> get adressenVoorToestellen => buitenAdressen(adresVoorToestellen);

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
    metDeHand = false;
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
    if (stand == DeurStand.mislukt && _mislukt > 0) {
      const snel = [Duration(seconds: 30), Duration(minutes: 1), Duration(minutes: 2), Duration(minutes: 5)];
      return _mislukt <= snel.length ? snel[_mislukt - 1] : ronde;
    }
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
      final had = _dienst;
      final IgdDienst? d;
      try {
        d = _dienst ??= await _zoek();
      } on ModemZonderUpnp catch (k) {
        if (await _probeerMetDeHand('de UPnP van de modem antwoordt niet (HTTP ${k.status})')) return;
        _misluktMet('Je modem meldt zich, maar zijn UPnP antwoordt niet (HTTP ${k.status}): het is in de modem '
            'vastgelopen. Herstart je modem, of zet UPnP daar uit en weer aan; daarna zet de pc de deur vanzelf. '
            'Tailscale werkt intussen.');
        return;
      }
      if (d != null && had == null) {
        final l = d.locatie;
        if (l != null) onthouden?.bewaar(l);
      }
      if (d == null) {
        if (await _probeerMetDeHand('geen modem met UPnP gevonden')) return;
        _misluktMet('Geen modem met UPnP gevonden. Zet UPnP aan in je modem, of zet de deur met de hand '
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
          _misluktMet('Je modem heeft zelf geen publiek adres (${ip ?? 'geen'}): er zit nog een router of je '
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
      metDeHand = false;
      waarom = null;
      _mislukt = 0;
      laatstGezet = _klok();
    } on IgdFout catch (f) {
      if ((f.code == 606 || f.code == 501) && await _probeerMetDeHand('de modem weigert UPnP-fout ${f.code}')) return;
      _misluktMet(switch (f.code) {
        606 => 'Je modem laat de app geen deur zetten (UPnP-fout 606). Zet de deur met de hand.',
        501 => 'Je modem weigerde de deur (UPnP-fout 501). Zet de deur met de hand.',
        _ => 'De modem weigerde: $f.',
      });
    } on Object catch (e) {
      // Onbereikbaar of iets onverwachts: volgende ronde opnieuw zoeken.
      _dienst = null;
      _misluktMet('De modem antwoordt niet ($e).');
    } finally {
      notifyListeners();
      _plan();
    }
  }

  /// UPnP lukt niet: open met de hand ([metDeHand]) als het publieke adres zonder de modem te achterhalen is. Waar als
  /// de deur zo open staat. [waarom] komt in het logboek.
  Future<bool> _probeerMetDeHand(String waarom) async {
    final vraag = vraagPubliekAdres;
    if (vraag == null || !_aan) return false;
    final nu = _klok();
    final oud = _adresGevraagd;
    if (!metDeHand || publiekAdres == null || oud == null || nu.difference(oud) >= adresElke) {
      String? ip;
      try {
        ip = await vraag();
      } catch (_) {/* dan niet */}
      _adresGevraagd = nu;
      if (ip == null || !isPubliekAdres(ip)) return false;
      if (ip != publiekAdres || !metDeHand) _log('deur met de hand ($waarom): publiek adres ${maskeerAdres(ip)}, poort $internePoort');
      publiekAdres = ip;
    }
    if (!_aan) return false;
    metDeHand = true;
    externePoort = internePoort;
    toegekend = null;
    stand = DeurStand.open;
    this.waarom = null;
    _mislukt = 0;
    laatstGezet = nu;
    return true;
  }

  void _misluktMet(String zin) {
    _mislukt++;
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

/// Het publieke IPv4-adres van deze aansluiting, gevraagd aan twee eenvoudige diensten die alleen het adres teruggeven
/// waarmee je bij hen aankomt — voor als de modem het via UPnP niet zegt ([DeurNaarBuiten.metDeHand]). Er gaat niets
/// mee: een gewone GET, zoals elke website die je opent je adres ziet. Null als geen van beide antwoordt.
Future<String?> publiekAdresViaInternet() async {
  for (final adres in const ['https://api.ipify.org', 'https://ipv4.icanhazip.com']) {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(adres)).timeout(const Duration(seconds: 8));
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) continue;
      final ip = (await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 8))).trim();
      if (isPubliekAdres(ip)) return ip;
    } catch (_) {
      // de volgende
    } finally {
      client.close(force: true);
    }
  }
  return null;
}

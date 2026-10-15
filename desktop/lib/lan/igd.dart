/// Met de modem praten over UPnP (Internet Gateway Device): een deur zetten, lezen en wissen.
///
/// Stap 7.1 van "verbinden zoals Roon ARC" (plan 14-10-2026). Wat de Sagemcom F3896LG van Saber doet,
/// gemeten met de poortproef van 14-10-2026 (`Bureaublad\poortproef\poortproef.log`):
/// * hij biedt `WANIPConnection:1`, en antwoordt op elke SOAP-vraag over een **nieuwe** verbinding;
/// * hij rondt elke tijdelijke lease af naar **900 s** (gevraagd 600 of 120), en een tweede
///   `AddPortMapping` op dezelfde deur zet de klok terug (VERLENGT);
/// * geen SNAT: wat binnenkomt, draagt het echte publieke adres van de afzender.
///
/// Bewust smal: alleen `GetSpecificPortMappingEntry`, nooit `GetGenericPortMappingEntry` (dat somt
/// elke deur van elk toestel in huis op). Een fout uit de modem komt als [IgdFout] met zijn
/// `errorCode`: 714 = die deur bestaat niet, 718 = de buitenpoort is al van iemand anders, 725 =
/// alleen vaste deuren, 606/501 = niet toegestaan of mislukt.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// De dienst in de modem waar de deuren gezet worden.
class IgdDienst {
  const IgdDienst({required this.controle, required this.soort, required this.lokaal, this.locatie});

  /// Het adres van de SOAP-ingang (`controlURL`).
  final Uri controle;

  /// `urn:schemas-upnp-org:service:WANIPConnection:1` (of :2, of WANPPPConnection:1).
  final String soort;

  /// Het adres van deze pc zoals de modem hem ziet: de `NewInternalClient` van elke deur.
  final String lokaal;

  /// Waar de beschrijving van de modem staat: om te onthouden, zodat de volgende keer geen zoektocht
  /// nodig is (zie `DeurNaarBuiten`).
  final Uri? locatie;
}

/// Een weigering van de modem, met zijn eigen code.
class IgdFout implements Exception {
  const IgdFout(this.code, [this.tekst = '']);
  final int code;
  final String tekst;
  @override
  String toString() => 'UPnP-fout $code${tekst.isEmpty ? '' : ' ($tekst)'}';
}

/// Een deur zoals de modem hem teruggeeft.
class IgdDeur {
  const IgdDeur({required this.internePoort, required this.client, required this.lease, required this.naam});
  final int internePoort;
  final String client;

  /// Wat er nog over is, in seconden. 0 = vast (geen lease).
  final int lease;
  final String naam;
}

/// Welke diensten we nemen, in deze volgorde.
const kIgdDiensten = [
  'urn:schemas-upnp-org:service:WANIPConnection:2',
  'urn:schemas-upnp-org:service:WANIPConnection:1',
  'urn:schemas-upnp-org:service:WANPPPConnection:1',
];

/// Mag de zoektocht naar de modem langs dit adres van deze pc? Alleen het eigen netwerk: geen Tailscale
/// (100.64/10), geen loopback, geen link-local. Zie [Igd._ssdp] voor waarom er per adres gebonden wordt.
bool lanAdresVoorSsdp(InternetAddress a) {
  if (a.type != InternetAddressType.IPv4 || a.isLoopback || a.isLinkLocal) return false;
  final d = a.rawAddress;
  return d[0] == 10 || (d[0] == 172 && d[1] >= 16 && d[1] <= 31) || (d[0] == 192 && d[1] == 168);
}

/// Welk eigen adres bij [host] hoort (de modem): loopback bij loopback (de nep-modem in een toets),
/// anders het eigen adres in hetzelfde /24, en anders in hetzelfde /16. Null als er geen bij past.
///
/// **Waarom niet `Socket.address`.** Dat is in Dart het adres waarmee je verbond — de overkant. Gemeten
/// op 15-10-2026: het gaf 192.168.0.1, het adres van de modem zelf; de deur zou dan naar de modem
/// gewezen hebben in plaats van naar deze pc. De nep-modem in de toetsen zag het niet: op 127.0.0.1 zijn
/// hier en daar hetzelfde.
String? eigenAdresNaar(String host, Iterable<InternetAddress> eigen) {
  final h = InternetAddress.tryParse(host);
  if (h == null || h.type != InternetAddressType.IPv4) return null;
  if (h.isLoopback) return '127.0.0.1';
  final v4 = [for (final a in eigen) if (a.type == InternetAddressType.IPv4 && a.address != host) a];
  for (final n in const [3, 2]) {
    for (final a in v4) {
      var gelijk = true;
      for (var i = 0; i < n; i++) {
        if (a.rawAddress[i] != h.rawAddress[i]) gelijk = false;
      }
      if (gelijk && lanAdresVoorSsdp(a)) return a.address;
    }
  }
  return null;
}

/// De `LOCATION` uit een SSDP-antwoord, of null.
Uri? ssdpLocatie(String antwoord) {
  final m = RegExp(r'^location:\s*(\S+)\s*$', caseSensitive: false, multiLine: true).firstMatch(antwoord);
  return m == null ? null : Uri.tryParse(m.group(1)!);
}

/// De beste dienst uit een apparaatbeschrijving, of null. `controlURL` relatief aan [locatie] (of aan
/// `URLBase` als die erin staat).
({Uri controle, String soort})? dienstUitBeschrijving(String xml, Uri locatie) {
  final basis = Uri.tryParse(RegExp(r'<URLBase>\s*([^<]+?)\s*</URLBase>').firstMatch(xml)?.group(1) ?? '') ?? locatie;
  final gevonden = <String, String>{};
  for (final m in RegExp(r'<service>([\s\S]*?)</service>').allMatches(xml)) {
    final blok = m.group(1)!;
    final soort = RegExp(r'<serviceType>\s*([^<]+?)\s*</serviceType>').firstMatch(blok)?.group(1);
    final ctl = RegExp(r'<controlURL>\s*([^<]+?)\s*</controlURL>').firstMatch(blok)?.group(1);
    if (soort != null && ctl != null) gevonden[soort] = ctl;
  }
  for (final s in kIgdDiensten) {
    final ctl = gevonden[s];
    if (ctl != null) return (controle: (basis.hasScheme ? basis : locatie).resolve(ctl), soort: s);
  }
  return null;
}

class Igd {
  Igd({this.wacht = const Duration(seconds: 5)});

  /// Hoe lang één SOAP-vraag mag duren.
  final Duration wacht;

  /// De modem zoeken: SSDP op het netwerk, of — in een toets — rechtstreeks een beschrijving.
  /// Null als er geen modem met UPnP antwoordt.
  Future<IgdDienst?> zoek({Duration zoektijd = const Duration(seconds: 3), Uri? locatie}) async {
    final locaties = locatie != null ? {locatie: null} : await _ssdp(zoektijd);
    for (final l in locaties.entries) {
      try {
        final d = await dienstVan(l.key, lokaal: l.value?.address);
        if (d != null) return d;
      } catch (_) {/* de volgende */}
    }
    return null;
  }

  /// De dienst achter één beschrijving, met het eigen adres van deze pc ernaartoe: [lokaal] (het adres
  /// waarop de modem op de zoekvraag antwoordde), of anders uit [eigenAdresNaar].
  Future<IgdDienst?> dienstVan(Uri locatie, {String? lokaal}) async {
    final c = HttpClient()..connectionTimeout = wacht;
    try {
      final req = await c.getUrl(locatie).timeout(wacht);
      req.persistentConnection = false;
      final res = await req.close().timeout(wacht);
      final xml = await utf8.decoder.bind(res).join().timeout(wacht);
      final d = dienstUitBeschrijving(xml, locatie);
      if (d == null) return null;
      var eigen = lokaal;
      if (eigen == null) {
        final alle = <InternetAddress>[];
        for (final k in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
          alle.addAll(k.addresses);
        }
        eigen = eigenAdresNaar(d.controle.host, alle);
      }
      // **Nooit een deur naar de modem zelf**, en nooit zonder eigen adres: dan liever geen modem.
      // (Loopback is de nep-modem in een toets: daar zijn hier en daar hetzelfde.)
      if (eigen == null || (eigen == d.controle.host && eigen != '127.0.0.1')) return null;
      return IgdDienst(controle: d.controle, soort: d.soort, lokaal: eigen, locatie: locatie);
    } finally {
      c.close(force: true);
    }
  }

  Future<Map<Uri, InternetAddress>> _ssdp(Duration zoektijd) async {
    // **Nooit vanuit een toets.** Een toets mag de echte modem niet vinden, laat staan er een deur in
    // zetten: dat opent Sabers pc voor het internet. Op 14-10-2026 haalde een mutatie de bewaking in
    // `sharing.dart` weg, en toen zocht een toets op het echte netwerk (nagekeken: er kwam geen deur).
    // Toetsen geven de nep-modem met `locatie` mee; zonder die zoekt er niets.
    if (Platform.environment.containsKey('FLUTTER_TEST')) return const {};
    // **Per adres op het eigen netwerk binden, niet aan anyIPv4.** Gemeten op 15-10-2026 op Sabers pc
    // (Ethernet, Tailscale en een VirtualBox-kaart): gebonden aan anyIPv4 antwoordde er niets, en de
    // deur bleef elke tien minuten "geen modem met UPnP gevonden" zeggen; gebonden aan 192.168.0.117
    // antwoordde de F3896LG meteen. De zoekvraag ging de verkeerde kaart uit. De poortproef van 14-10
    // had het al opgeschreven ("zonder binden vond hij niets") — en toch stond het hier verkeerd.
    final adressen = <InternetAddress>[];
    try {
      for (final k in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        adressen.addAll(k.addresses.where(lanAdresVoorSsdp));
      }
    } catch (_) {/* dan geen */}
    // Per beschrijving het eigen adres waarop het antwoord binnenkwam: dat is het adres van deze pc dat
    // de modem kan bereiken, en dus de NewInternalClient van de deur.
    final gevonden = <Uri, InternetAddress>{};
    await Future.wait([for (final a in adressen) _ssdpVia(a, zoektijd, gevonden)]);
    return gevonden;
  }

  Future<void> _ssdpVia(InternetAddress adres, Duration zoektijd, Map<Uri, InternetAddress> gevonden) async {
    RawDatagramSocket? s;
    try {
      s = await RawDatagramSocket.bind(adres, 0);
      final sock = s;
      sock.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = sock.receive();
        if (d == null) return;
        final l = ssdpLocatie(utf8.decode(d.data, allowMalformed: true));
        if (l != null) gevonden.putIfAbsent(l, () => adres);
      });
      for (final st in const [
        'urn:schemas-upnp-org:device:InternetGatewayDevice:2',
        'urn:schemas-upnp-org:device:InternetGatewayDevice:1',
      ]) {
        final m = 'M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\nMX: 2\r\nST: $st\r\n\r\n';
        sock.send(utf8.encode(m), InternetAddress('239.255.255.250'), 1900);
      }
      await Future<void>.delayed(zoektijd);
    } catch (_) {
      // Geen netwerk of geen multicast op deze kaart: dan via deze geen modem.
    } finally {
      s?.close();
    }
  }

  /// Eén SOAP-vraag, over een eigen verbinding (de F3896LG wil dat zo). Geeft de velden van het
  /// antwoord; een fout van de modem wordt een [IgdFout].
  Future<Map<String, String>> vraag(IgdDienst d, String actie, Map<String, String> args) async {
    final lijf = '<?xml version="1.0"?>\r\n'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>'
        '<u:$actie xmlns:u="${d.soort}">'
        '${args.entries.map((e) => '<${e.key}>${_xml(e.value)}</${e.key}>').join()}'
        '</u:$actie></s:Body></s:Envelope>';
    final c = HttpClient()..connectionTimeout = wacht;
    try {
      final req = await c.postUrl(d.controle).timeout(wacht);
      req.persistentConnection = false;
      req.headers
        ..set(HttpHeaders.contentTypeHeader, 'text/xml; charset="utf-8"')
        ..set('SOAPAction', '"${d.soort}#$actie"');
      final bytes = utf8.encode(lijf);
      req.contentLength = bytes.length;
      req.add(bytes);
      final res = await req.close().timeout(wacht);
      final xml = await utf8.decoder.bind(res).join().timeout(wacht);
      final code = int.tryParse(RegExp(r'<errorCode>\s*(\d+)\s*</errorCode>').firstMatch(xml)?.group(1) ?? '');
      if (code != null) {
        throw IgdFout(code, RegExp(r'<errorDescription>([^<]*)</errorDescription>').firstMatch(xml)?.group(1) ?? '');
      }
      if (res.statusCode != 200) throw IgdFout(res.statusCode, 'HTTP');
      return {
        for (final m in RegExp(r'<(New\w+)>([^<]*)</\1>').allMatches(xml)) m.group(1)!: _vanXml(m.group(2)!),
      };
    } finally {
      c.close(force: true);
    }
  }

  /// Een deur zetten: buiten [extern] → [intern] op deze pc.
  Future<void> zet(IgdDienst d, {required int extern, required int intern, required int lease, required String naam}) =>
      vraag(d, 'AddPortMapping', {
        'NewRemoteHost': '',
        'NewExternalPort': '$extern',
        'NewProtocol': 'TCP',
        'NewInternalPort': '$intern',
        'NewInternalClient': d.lokaal,
        'NewEnabled': '1',
        'NewPortMappingDescription': naam,
        'NewLeaseDuration': '$lease',
      });

  /// De deur op buitenpoort [extern], of null als er geen is (714).
  Future<IgdDeur?> lees(IgdDienst d, int extern) async {
    try {
      final v = await vraag(d, 'GetSpecificPortMappingEntry',
          {'NewRemoteHost': '', 'NewExternalPort': '$extern', 'NewProtocol': 'TCP'});
      return IgdDeur(
        internePoort: int.tryParse(v['NewInternalPort'] ?? '') ?? 0,
        client: v['NewInternalClient'] ?? '',
        lease: int.tryParse(v['NewLeaseDuration'] ?? '') ?? 0,
        naam: v['NewPortMappingDescription'] ?? '',
      );
    } on IgdFout catch (f) {
      if (f.code == 714) return null;
      rethrow;
    }
  }

  /// De deur wissen. Er was er geen (714): ook goed.
  Future<void> wis(IgdDienst d, int extern) async {
    try {
      await vraag(d, 'DeletePortMapping', {'NewRemoteHost': '', 'NewExternalPort': '$extern', 'NewProtocol': 'TCP'});
    } on IgdFout catch (f) {
      if (f.code != 714) rethrow;
    }
  }

  Future<String?> publiekAdres(IgdDienst d) async =>
      (await vraag(d, 'GetExternalIPAddress', const {}))['NewExternalIPAddress'];

  /// Hoe lang de modem al verbonden is. Daalt dat getal, dan is hij herstart.
  Future<int?> uptime(IgdDienst d) async => int.tryParse((await vraag(d, 'GetStatusInfo', const {}))['NewUptime'] ?? '');

  static String _xml(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  static String _vanXml(String s) =>
      s.replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&amp;', '&');
}

/// Which devices may talk to this PC, and with which token.
///
/// Deliberately knows nothing about Firebase. Signing in decides *who you are*; this decides *what
/// you may fetch*, and it is the half that has to keep working with the internet unplugged. A PC
/// whose cloud session has expired must still serve music to every device already holding a grant
/// — so this is a plain file, read at startup, consulted on every request.
///
/// It replaces a single shared secret. Until today every device that ever paired received the same
/// 32 hex characters, which meant "revoke one device" did not exist: the only lever unpaired them
/// all at once.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../paths.dart';

/// One device's permission to use this library.
class DeviceGrant {
  DeviceGrant({
    required this.deviceId,
    required this.deviceName,
    required this.token,
    required this.platform,
    required this.grantedAt,
    this.lastSeenAt,
    this.lastSeenVia,
    this.legacy = false,
  });

  final String deviceId;
  final String deviceName;
  final String token;
  final String platform;
  final int grantedAt;
  int? lastSeenAt;

  /// Langs welke weg dit toestel het laatst binnenkwam: `thuis`, `Tailscale`, `deze pc` of
  /// `buiten`. Voor de toestellenlijst op de pc; zie [toestelWeg].
  String? lastSeenVia;

  /// True for the one synthetic grant that stands in for everything paired before grants existed.
  /// Shown in the device list as a single row the user can revoke on purpose, rather than silently
  /// cutting off an iPad that was working fine yesterday.
  final bool legacy;

  /// Sleutels die dit toestel EERDER van deze pc kreeg, en die geldig BLIJVEN.
  ///
  /// **Waarom ze blijven.** Saber op 12-09-2026: "ik ben het beu om na elke update weer te moeten
  /// ontkoppelen van de pc en weer te koppelen". Eén sleutel per toestel betekent dat elk verlies
  /// aan deze kant — een tweede instantie die dit bestand overschreef, een pc-app die even uit een
  /// andere map las — het toestel buitensluit, terwijl het toestel zelf niets verkeerd doet. Gemeten
  /// op 12-09-2026: van de 45 koppelingen op schijf hield de app er 35 over, en de telefoon werd een
  /// ochtend lang geweigerd met een sleutel die hij een dag eerder had gekregen.
  ///
  /// Hoogstens drie, en ze verdwijnen zodra je het toestel bewust ontkoppelt: [revoke] gooit het
  /// toestel met al zijn sleutels weg.
  List<String> oudereTokens = <String>[];

  /// De VERSLEUTELDE sleutel van dit toestel, voor 47822 (thuis) en 47821 (van buiten). Null zolang het
  /// toestel nog niet geruild heeft ([GrantStore.ruil]).
  ///
  /// **Waarom een tweede sleutel.** [token] reisde onversleuteld (over 47820, en tot 14-10-2026 ook via
  /// Firestore). Wie hem ooit opving, mag daarmee nooit van buiten binnen. Een TLS-sleutel wordt alleen
  /// over een vastgepinde TLS-verbinding uitgegeven en geldt alleen daar; op 47820 wordt hij geweigerd
  /// en ingetrokken (hij reisde dan alsnog onversleuteld). Nooit in [oudereTokens]: een vervangen
  /// TLS-sleutel is meteen ingetrokken.
  String? tlsToken;

  /// Wanneer [tlsToken] uitgegeven werd. Bij het samenvoegen van twee kopieën wint de jongste TLS-sleutel
  /// apart van de rest van de koppeling: een ruil gebeurt na het koppelen, met een eigen tijd.
  int tlsAt = 0;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'token': token,
        'platform': platform,
        'grantedAt': grantedAt,
        'lastSeenAt': lastSeenAt,
        if (lastSeenVia != null) 'lastSeenVia': lastSeenVia,
        'legacy': legacy,
        if (oudereTokens.isNotEmpty) 'oudereTokens': oudereTokens,
        if (tlsToken != null) 'tlsToken': tlsToken,
        if (tlsToken != null) 'tlsAt': tlsAt,
      };

  static DeviceGrant? fromJson(Map<String, dynamic> j) {
    final id = (j['deviceId'] ?? '').toString();
    final token = (j['token'] ?? '').toString();
    if (id.isEmpty || token.isEmpty) return null;
    final g = DeviceGrant(
      deviceId: id,
      deviceName: (j['deviceName'] ?? '').toString(),
      token: token,
      platform: (j['platform'] ?? '').toString(),
      grantedAt: (j['grantedAt'] as num?)?.toInt() ?? 0,
      lastSeenAt: (j['lastSeenAt'] as num?)?.toInt(),
      lastSeenVia: j['lastSeenVia'] as String?,
      legacy: j['legacy'] == true,
    );
    for (final t in (j['oudereTokens'] as List<dynamic>? ?? const [])) {
      if (t is String && t.isNotEmpty && t != token) g.oudereTokens.add(t);
    }
    // De gedeelde sleutel (de rij `legacy`) krijgt nooit een TLS-sleutel, ook niet van schijf.
    final tls = j['tlsToken'];
    if (!g.legacy && tls is String && tls.isNotEmpty && tls != token) {
      g.tlsToken = tls;
      g.tlsAt = (j['tlsAt'] as num?)?.toInt() ?? 0;
    }
    return g;
  }
}

/// 32 hex characters from a secure source. Same shape as the token this replaces, so nothing that
/// carries one — a query string, a Retrofit header, a saved `paired_server.json` — has to change.
String generateDeviceToken() {
  final rnd = Random.secure();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Langs welke weg een verzoek binnenkwam, naar het adres waar het vandaan kwam.
///
/// Loopback is deze pc zelf (zijn eigen speakerclient); 100.64/10 is Tailscale; de privé-reeksen zijn
/// thuis; al de rest is van buiten. Gaat over het ADRES — sinds er later een eigen deur naar buiten
/// bij komt (stap 7 van het plan), beslist de luisteraar over rechten, nooit dit.
String toestelWeg(InternetAddress adres) {
  if (adres.isLoopback) return 'deze pc';
  final a = adres.type == InternetAddressType.IPv6 && adres.address.startsWith('::ffff:')
      ? adres.address.substring(7)
      : adres.address;
  final d = a.split('.').map(int.tryParse).toList();
  if (d.length == 4 && d.every((x) => x != null)) {
    final (x, y) = (d[0]!, d[1]!);
    if (x == 100 && y >= 64 && y <= 127) return 'Tailscale';
    if (x == 10 || (x == 172 && y >= 16 && y <= 31) || (x == 192 && y == 168) || (x == 169 && y == 254)) return 'thuis';
    return 'buiten';
  }
  if (a.toLowerCase().startsWith('fd7a:115c:a1e0:')) return 'Tailscale';
  if (adres.isLinkLocal || a.toLowerCase().startsWith('fc') || a.toLowerCase().startsWith('fd')) return 'thuis';
  return 'buiten';
}

/// Mag dit als toestel-id dienen? Letters, cijfers, `_` en `-`, 8 tot 64 tekens.
///
/// Het id gaat letterlijk een Firestore-pad in (`grants/<id>`) en een logregel; een `/` of een
/// regeleinde hoort daar niet. Een id van deze app is 32 hextekens (`device_identity.dart`). Ook de
/// vaste rij `legacy` valt erbuiten: die staat voor de gedeelde sleutel en krijgt nooit een sleutel
/// van zichzelf.
bool geldigToestelId(String id) => RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(id);

/// Een toestelnaam zoals een toestel hem meestuurt, veilig voor de lijst en voor `koppeling.log`:
/// geen stuurtekens (een regeleinde zou een valse logregel kunnen maken), witruimte samengevoegd,
/// hoogstens 60 tekens. Leeg of geen tekst geeft [leeg].
String schoneToestelnaam(Object? naam, {String leeg = 'Onbekend apparaat'}) {
  if (naam is! String) return leeg;
  var n = naam.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (n.length > 60) n = n.substring(0, 60).trimRight();
  return n.isEmpty ? leeg : n;
}

/// Een nieuwe sleutel is uitgegeven. Voor de melding op de pc, met [Intrekken] erbij.
///
/// **Waarom elke nieuwe sleutel, ook voor een toestel dat er al stond.** Wie je inlogsleutel heeft
/// en het id van je gsm meestuurt, krijgt een sleutel op dié rij — er komt geen nieuwe rij bij, dus
/// ook geen "nieuw toestel". Zonder deze melding gebeurt dat stil. [sleutel] staat erin om precies
/// die ene sleutel te kunnen intrekken; hij wordt nergens getoond.
class SleutelMelding {
  SleutelMelding({
    required this.deviceId,
    required this.deviceName,
    required this.bestaand,
    required this.via,
    required this.van,
    required this.sleutel,
    DateTime? op,
  }) : op = op ?? DateTime.now();

  final String deviceId;
  final String deviceName;

  /// True als dit toestel al een rij had: een NIEUWE sleutel voor een bestaand toestel.
  final bool bestaand;

  /// 'code' of 'account'.
  final String via;

  /// Het adres waar het verzoek vandaan kwam.
  final String van;
  final String sleutel;
  final DateTime op;

  /// "Nieuwe sleutel voor 'S26' (bestaand toestel), via je account, 14:02, van 192.168.0.42".
  String get tekst {
    final tijd = '${op.hour.toString().padLeft(2, '0')}:${op.minute.toString().padLeft(2, '0')}';
    final wie = bestaand ? "Nieuwe sleutel voor '$deviceName' (bestaand toestel)" : "Nieuw toestel gekoppeld: '$deviceName'";
    return '$wie, via ${via == 'code' ? 'de code' : 'je account'}, $tijd, van $van';
  }
}

String _vingerafdruk(String sleutel) => sha256.convert(utf8.encode(sleutel)).toString();

class GrantStore {
  GrantStore({File? file}) : _file = file ?? appFile('grants.json');

  final File _file;
  final Map<String, DeviceGrant> _byDevice = {};

  /// token → deviceId. Rebuilt with the map, so accepting a request is a hash lookup rather than a
  /// walk: this runs on every single HTTP request, including every range request of a stream.
  final Map<String, String> _byToken = {};

  /// TLS-sleutel → deviceId. Apart van [_byToken], zodat [accepts] (47820) een TLS-sleutel nooit kent.
  final Map<String, String> _byTls = {};

  /// Toestellen die je met OPZET hebt ontkoppeld. Zonder dit haalt het samenvoegende opslaan ze
  /// zo weer van schijf terug, en dan doet "ontkoppelen" niets.
  ///
  /// Sinds 14-10-2026 op schijf ([_ingetrokkenBestand]): een herstart, of een tweede kopie van de
  /// app met een oudere `grants.json`, haalde een ingetrokken toestel anders terug.
  final Set<String> _ingetrokken = {};

  /// Sleutels die je los hebt ingetrokken, als vingerafdruk (SHA-256) — niet de sleutel zelf.
  ///
  /// **Waarom per sleutel.** Een nieuwe sleutel voor een bestaand toestel kan van iemand anders
  /// komen (zie [SleutelMelding]). Het hele toestel intrekken sluit dan ook je echte gsm buiten;
  /// alleen die ene sleutel intrekken niet. En het samenvoegen bij [save] mag zo'n sleutel niet via
  /// een oudere kopie op schijf terug in [DeviceGrant.oudereTokens] zetten — daarom staat de
  /// controle in [_neemOp], waar elke sleutel langskomt.
  final Set<String> _ingetrokkenSleutels = {};

  /// Toestellen die na intrekken opnieuw gekoppeld zijn, en nog niet weggeschreven. Anders haalt
  /// [_laadIngetrokken] in [save] ze uit de oude lijst op schijf meteen weer terug als ingetrokken.
  final Set<String> _weerToegelaten = {};

  File get _ingetrokkenBestand =>
      File('${_file.path.replaceFirst(RegExp(r'\.json$'), '')}_ingetrokken.json');

  bool isIngetrokken(String sleutel) =>
      sleutel.isNotEmpty && _ingetrokkenSleutels.contains(_vingerafdruk(sleutel));

  /// De laatst uitgegeven sleutel, voor de melding op de pc. Zie [SleutelMelding].
  final ValueNotifier<SleutelMelding?> nieuweSleutelMelding = ValueNotifier(null);

  /// Waar als deze kopie van de app de poort NIET heeft. Dan schrijft ze geen koppelingen weg.
  ///
  /// **Waarom dit er is.** Een tweede kopie die aan de poort 10048 kreeg, draait gewoon door en kan
  /// via de cloud nog koppelingen bijschrijven — met een winkel die niets van de eerste weet. Eén
  /// `save()` daaruit zet een oudere momentopname over de echte lijst heen. Gemeten op 12-09-2026:
  /// twee kopieën tegelijk, één met achttien koppelingen en één met vijfendertig, en een telefoon
  /// die een ochtend lang geweigerd werd.
  bool alleenLezen = false;

  /// Wat er NU op schijf staat, zonder de winkel in het geheugen aan te raken.
  Future<List<DeviceGrant>> _vanSchijf() async {
    try {
      if (!await _file.exists()) return const [];
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is! List) return const [];
      final uit = <DeviceGrant>[];
      for (final e in decoded) {
        if (e is! Map<String, dynamic>) continue;
        final g = DeviceGrant.fromJson(e);
        if (g != null) uit.add(g);
      }
      return uit;
    } catch (_) {
      return const [];
    }
  }

  /// Eén koppeling erbij, zonder er een kwijt te raken.
  ///
  /// Staat er al iets voor dit toestel, dan wordt de NIEUWSTE de huidige sleutel en verhuist de
  /// andere naar [DeviceGrant.oudereTokens]. Zo sluit inlezen of samenvoegen geen toestel buiten
  /// dat nog netjes met zijn sleutel aanklopt.
  void _neemOp(DeviceGrant g) {
    final oud = _byDevice[g.deviceId];
    final nieuw = oud == null || g.grantedAt >= oud.grantedAt ? g : oud;
    final ander = identical(nieuw, g) ? oud : g;
    if (ander != null) {
      for (final t in [ander.token, ...ander.oudereTokens]) {
        // Een los ingetrokken sleutel komt via een oudere kopie NIET terug.
        if (t != nieuw.token && !nieuw.oudereTokens.contains(t) && !isIngetrokken(t)) {
          nieuw.oudereTokens.add(t);
        }
      }
      if ((ander.lastSeenAt ?? 0) > (nieuw.lastSeenAt ?? 0)) nieuw.lastSeenVia = ander.lastSeenVia ?? nieuw.lastSeenVia;
      nieuw.lastSeenAt = max(nieuw.lastSeenAt ?? 0, ander.lastSeenAt ?? 0);
    }
    nieuw.oudereTokens.removeWhere(isIngetrokken);
    while (nieuw.oudereTokens.length > 3) {
      nieuw.oudereTokens.removeAt(0);
    }
    // De TLS-sleutel apart, op zijn eigen tijd: de jongste wint, de andere is ingetrokken (twee kopieën
    // met elk een andere TLS-sleutel = één geldig, de andere 401). Nooit naar `oudereTokens`.
    DeviceGrant? tlsWinnaar;
    for (final k in [?oud, g]) {
      final t = k.tlsToken;
      if (t == null || isIngetrokken(t)) continue;
      if (tlsWinnaar == null || k.tlsAt > tlsWinnaar.tlsAt) tlsWinnaar = k;
    }
    final tlsSleutel = tlsWinnaar?.tlsToken;
    final tlsTijd = tlsWinnaar?.tlsAt ?? 0;
    for (final k in [?oud, g]) {
      final t = k.tlsToken;
      if (t != null && t != tlsSleutel) {
        _ingetrokkenSleutels.add(_vingerafdruk(t));
        _byTls.remove(t);
      }
    }
    nieuw.tlsToken = tlsSleutel;
    nieuw.tlsAt = tlsSleutel == null ? 0 : tlsTijd;
    if (tlsSleutel != null) _byTls[tlsSleutel] = g.deviceId;
    _byDevice[g.deviceId] = nieuw;
    for (final t in [nieuw.token, ...nieuw.oudereTokens]) {
      if (!isIngetrokken(t)) _byToken[t] = g.deviceId;
    }
  }

  /// Een NIEUWE sleutel voor dit toestel, altijd — ook als het er al een had.
  ///
  /// **Waarom nooit de bestaande teruggeven** (wat [mint] doet). Wie je inlogsleutel en het id van je
  /// gsm heeft, kreeg zo de sleutel die je gsm op dat moment gebruikt. Nu krijgt hij een eigen, en
  /// die is los in te trekken ([trekSleutelIn]) zonder je gsm buiten te sluiten. De vorige sleutels
  /// blijven geldig in [DeviceGrant.oudereTokens] (hoogstens drie, de recentste eerst): een toestel
  /// dat net opnieuw koppelde en zijn antwoord kwijtraakte, mag niet buitengesloten worden.
  ///
  /// Haalt het toestel uit [_ingetrokken]: opnieuw koppelen na ontkoppelen is precies de bedoeling.
  ///
  /// [metTls]: koppelen over 47822 (vastgepinde TLS) geeft er meteen een TLS-sleutel bij. De vorige
  /// TLS-sleutel van dit toestel vervalt altijd: wie opnieuw koppelt, heeft hem doorgaans niet meer (een
  /// nieuwe installatie), en anders zou zijn eerste ruil op 409 stuiten.
  DeviceGrant nieuweSleutel({
    required String deviceId,
    required String deviceName,
    String platform = '',
    bool metTls = false,
  }) {
    final oud = _byDevice[deviceId];
    if (_ingetrokken.remove(deviceId)) _weerToegelaten.add(deviceId);
    final nu = DateTime.now().millisecondsSinceEpoch;
    final grant = DeviceGrant(
      deviceId: deviceId,
      deviceName: deviceName,
      token: generateDeviceToken(),
      platform: platform,
      // Altijd later dan de vorige, ook bij een klok die terugsprong: bij het samenvoegen met een
      // kopie op schijf wint zo deze rij, en verhuist de oude sleutel naar `oudereTokens`.
      grantedAt: max(nu, (oud?.grantedAt ?? 0) + 1),
      lastSeenAt: oud?.lastSeenAt,
      lastSeenVia: oud?.lastSeenVia,
    );
    if (oud != null) {
      for (final t in [oud.token, ...oud.oudereTokens]) {
        if (t.isNotEmpty && !isIngetrokken(t) && !grant.oudereTokens.contains(t)) grant.oudereTokens.add(t);
      }
      while (grant.oudereTokens.length > 3) {
        grant.oudereTokens.removeLast();
      }
      _byToken.remove(oud.token);
      for (final t in oud.oudereTokens) {
        _byToken.remove(t);
      }
    }
    final oudeTls = oud?.tlsToken;
    if (oudeTls != null) {
      _ingetrokkenSleutels.add(_vingerafdruk(oudeTls));
      _byTls.remove(oudeTls);
    }
    if (metTls && deviceId != 'legacy') {
      grant.tlsToken = generateDeviceToken();
      grant.tlsAt = max(nu, (oud?.tlsAt ?? 0) + 1);
      _byTls[grant.tlsToken!] = deviceId;
    }
    _byDevice[deviceId] = grant;
    for (final t in [grant.token, ...grant.oudereTokens]) {
      _byToken[t] = deviceId;
    }
    return grant;
  }

  /// De eenmalige ruil: de huidige HTTP-sleutel van een echt toestel → een TLS-sleutel. Alleen op 47822.
  ///
  /// * 200: [tls] is de nieuwe TLS-sleutel. De HTTP-sleutel blijft geldig op 47820.
  /// * 401: onbekende of ingetrokken sleutel.
  /// * 403: de gedeelde sleutel (rij `legacy`, leesbaar in elke cast-URL) of een sleutel uit
  ///   [DeviceGrant.oudereTokens] — die kunnen nooit omgeruild worden.
  /// * 409: dit toestel heeft al een TLS-sleutel. Kwam die ruil niet van het toestel zelf, dan heeft
  ///   iemand zijn HTTP-sleutel; de server meldt dat (stap 5, "gekaapte ruil").
  ({int status, String? tls, DeviceGrant? grant}) ruil(String httpSleutel) {
    if (httpSleutel.isEmpty || isIngetrokken(httpSleutel)) return (status: 401, tls: null, grant: null);
    final id = _byToken[httpSleutel];
    final g = id == null ? null : _byDevice[id];
    if (g == null) return (status: 401, tls: null, grant: null);
    if (g.legacy || !_constantTimeEquals(httpSleutel, g.token)) return (status: 403, tls: null, grant: g);
    if (g.tlsToken != null) return (status: 409, tls: null, grant: g);
    final tls = generateDeviceToken();
    g.tlsToken = tls;
    g.tlsAt = max(DateTime.now().millisecondsSinceEpoch, g.tlsAt + 1);
    _byTls[tls] = g.deviceId;
    return (status: 200, tls: tls, grant: g);
  }

  /// De controle op 47822 en 47821: alleen een TLS-sleutel, in constante tijd.
  bool acceptsTls(String sleutel) {
    if (sleutel.isEmpty || isIngetrokken(sleutel)) return false;
    final id = _byTls[sleutel];
    final t = id == null ? null : _byDevice[id]?.tlsToken;
    return t != null && _constantTimeEquals(sleutel, t);
  }

  /// Of dit een (geldige) TLS-sleutel is — voor 47820, waar zo'n sleutel nooit hoort te komen.
  bool isTlsSleutel(String sleutel) => sleutel.isNotEmpty && _byTls.containsKey(sleutel);

  /// Precies één sleutel intrekken; de andere sleutels van hetzelfde toestel blijven werken.
  /// Geeft true als deze winkel de sleutel kende.
  bool trekSleutelIn(String sleutel) {
    if (sleutel.isEmpty) return false;
    _ingetrokkenSleutels.add(_vingerafdruk(sleutel));
    final tlsId = _byTls.remove(sleutel);
    if (tlsId != null) {
      final g = _byDevice[tlsId];
      if (g != null && g.tlsToken == sleutel) {
        g
          ..tlsToken = null
          ..tlsAt = 0;
      }
      return g != null;
    }
    final id = _byToken.remove(sleutel);
    final g = id == null ? null : _byDevice[id];
    g?.oudereTokens.remove(sleutel);
    return g != null;
  }

  List<DeviceGrant> get all => _byDevice.values.toList()
    ..sort((a, b) => b.grantedAt.compareTo(a.grantedAt));

  bool get isEmpty => _byDevice.isEmpty;

  /// Waar het inlezen zijn uitkomst kwijt kan. Null = niets melden.
  ///
  /// **Waarom dit er moest komen.** Als dit stil mislukt, weigert de pc voor de rest van de sessie
  /// ÉLK gekoppeld toestel — en het enige spoor was een [debugPrint], die een release-build weggooit.
  /// Op 11-08-2026 kostte precies dat een avond zoeken: negentien koppelingen stonden keurig op
  /// schijf, de app weigerde ze allemaal, en na een herstart werkte dezelfde sleutel meteen weer.
  /// Van buitenaf is dat niet te onderscheiden van een ingetrokken koppeling.
  void Function(String)? meldlog;

  /// Wat er bewust is ingetrokken, van schijf. Vóór de koppelingen, zodat [_neemOp] het al weet.
  Future<void> _laadIngetrokken() async {
    try {
      final f = _ingetrokkenBestand;
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map) return;
      for (final id in (j['toestellen'] as List? ?? const [])) {
        if (id is String && id.isNotEmpty && !_weerToegelaten.contains(id)) _ingetrokken.add(id);
      }
      for (final h in (j['sleutels'] as List? ?? const [])) {
        if (h is String && h.length == 64) _ingetrokkenSleutels.add(h);
      }
    } catch (e) {
      // Onleesbaar: dan weten we niets extra, en gelden de koppelingen zoals ze op schijf staan.
      meldlog?.call('ingetrokken sleutels NIET geladen: $e');
    }
  }

  /// Wat ingetrokken is ook in het GEHEUGEN doorvoeren. Na [_laadIngetrokken] in [save]: een tweede
  /// kopie van de app met een oudere momentopname heeft een ingetrokken sleutel nog gewoon in zijn
  /// rij staan, en zou hem anders bij het opslaan terug op schijf zetten — samen met een lijst
  /// ingetrokken sleutels waar hij niet in staat.
  void _pasIngetrokkenToe() {
    for (final id in _ingetrokken) {
      final g = _byDevice.remove(id);
      if (g == null) continue;
      for (final t in [g.token, ...g.oudereTokens]) {
        _byToken.remove(t);
      }
      if (g.tlsToken != null) _byTls.remove(g.tlsToken);
    }
    for (final g in _byDevice.values) {
      final tls = g.tlsToken;
      if (tls != null && isIngetrokken(tls)) {
        _byTls.remove(tls);
        g
          ..tlsToken = null
          ..tlsAt = 0;
      }
      for (final t in g.oudereTokens.where(isIngetrokken).toList()) {
        _byToken.remove(t);
      }
      g.oudereTokens.removeWhere(isIngetrokken);
      if (isIngetrokken(g.token)) _byToken.remove(g.token);
    }
  }

  Future<void> _schrijfIngetrokken() async {
    if (_ingetrokken.isEmpty && _ingetrokkenSleutels.isEmpty && !await _ingetrokkenBestand.exists()) return;
    final tmp = File('${_ingetrokkenBestand.path}.tmp');
    await tmp.writeAsString(jsonEncode({
      'toestellen': _ingetrokken.toList()..sort(),
      'sleutels': _ingetrokkenSleutels.toList()..sort(),
    }));
    await tmp.rename(_ingetrokkenBestand.path);
    _weerToegelaten.clear();
  }

  Future<void> load() async {
    await _laadIngetrokken();
    try {
      if (!await _file.exists()) {
        meldlog?.call('koppelingen: bestand bestaat niet — 0 geladen');
        return;
      }
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is! List) {
        meldlog?.call('koppelingen: bestand is geen lijst — 0 geladen, ALLE toestellen worden geweigerd');
        return;
      }
      _byDevice.clear();
      _byToken.clear();
      _byTls.clear();
      var overgeslagen = 0;
      for (final e in decoded) {
        if (e is! Map<String, dynamic>) {
          overgeslagen++;
          continue;
        }
        final g = DeviceGrant.fromJson(e);
        if (g == null) {
          overgeslagen++;
          continue;
        }
        if (_ingetrokken.contains(g.deviceId)) continue;
        _neemOp(g);
      }
      meldlog?.call('koppelingen geladen: ${_byDevice.length} van ${decoded.length}'
          '${overgeslagen == 0 ? '' : ' ($overgeslagen onleesbaar)'}');
    } catch (e) {
      // A corrupt file must not lock you out of your own library — the legacy token below still
      // works, and a device can simply be granted again.
      meldlog?.call('koppelingen NIET geladen: $e — alle toestellen worden geweigerd tot de app herstart');
      debugPrint('grants.json unreadable: $e');
    }
  }

  /// De opslagbeurt die nu loopt (of de laatste), zodat de volgende erachter wacht.
  Future<void>? _lopend;

  /// Opslaan, NA de vorige opslagbeurt.
  ///
  /// **Waarom in een rij.** Elk geslaagd verzoek kan er een starten (`touch` → `unawaited(save())`),
  /// en een koppeling ook. Twee tegelijk schreven allebei naar `grants.json.tmp` en hernoemden
  /// dat — op Windows kan de tweede hernoeming dan mislukken op een bestand dat in gebruik is, en
  /// wint de oudste momentopname. En wie afsluit kan met [wachtOpOpslaan] de laatste afwachten.
  Future<void> save() {
    final vorige = _lopend ?? Future<void>.value();
    final deze = vorige.catchError((Object _) {}).then((_) => _slaOp());
    _lopend = deze;
    return deze;
  }

  /// Tot de laatst gestarte opslagbeurt klaar is. Voor het afsluiten van de server.
  Future<void> wachtOpOpslaan() => (_lopend ?? Future<void>.value()).catchError((Object _) {});

  Future<void> _slaOp() async {
    if (alleenLezen) {
      meldlog?.call('koppelingen NIET opgeslagen: deze kopie van de app heeft de poort niet');
      return;
    }
    // Eerst wat er op schijf ingetrokken staat erbij — van deze kopie of een andere — en meteen
    // doorvoeren. Pas daarna samenvoegen en schrijven: zo zet geen enkele kopie een ingetrokken
    // toestel of sleutel terug.
    await _laadIngetrokken();
    _pasIngetrokkenToe();
    try {
      // LEEG SCHRIJFT NOOIT OVER NIET-LEEG. Dezelfde klep als bij corrections.json en de
      // feitencache: een lege verzameling betekent "ik weet het niet", niet "er is niets".
      //
      // Gemeten op 11-08-2026: alle 19 gekoppelde toestellen kregen opeens 401, terwijl er in de
      // hele code geen enkel pad is dat deze kaarten binnen één proces leegt. Wat er WEL kan: een
      // tweede kopie van de app die niet aan de poort kwam (10048) maar wel naar dezelfde map
      // schrijft, met een winkel die nooit geladen is. Eén `save()` daaruit zet een lege lijst — of
      // één verse regel — over de negentien heen, en dan is elk toestel zijn toegang kwijt zonder
      // dat iemand iets ingetrokken heeft.
      //
      // De kosten van deze regel zijn precies één geval: "ik heb zojuist mijn laatste toestel
      // ontkoppeld" wordt niet weggeschreven. Dat is te overzien — [revoke] schrijft zelf, en één
      // regel te veel is oneindig veel beter dan een huis vol toestellen dat er niet meer in kan.
      //
      // Sinds 14-10-2026 met één uitzondering: staat ELKE koppeling op schijf bewust ingetrokken
      // ([_ingetrokken], ook op schijf), dan is leeg wél de waarheid en wordt het weggeschreven. Zo
      // blijft "mijn laatste toestel ontkoppelen" niet langer liggen tot een andere kopie het terugzet.
      if (_byDevice.isEmpty && await _file.exists()) {
        final bestaand = await _file.readAsString();
        final oud = jsonDecode(bestaand);
        final alleBewustIngetrokken = oud is List &&
            oud.every((e) => e is Map && _ingetrokken.contains('${e['deviceId']}'));
        if (oud is List && oud.isNotEmpty && !alleBewustIngetrokken) {
          debugPrint('grants.json NIET overschreven: geheugen leeg, schijf heeft ${oud.length}');
          await _schrijfIngetrokken();
          return;
        }
      }
      // Same tmp-then-rename as the rest of this app's state: a power cut halfway through a write
      // must not leave a truncated file that reads as "no devices".
      //
      // EN: eerst lezen wat er op schijf staat, dan pas schrijven. Anders zet deze kopie haar eigen
      // momentopname over koppelingen heen die zij nooit gezien heeft — van een tweede kopie, of van
      // een bestand dat buitenom is bijgewerkt. Wat je met opzet ontkoppelde komt niet terug, want
      // dat staat in [_ingetrokken].
      var erbij = 0;
      for (final g in await _vanSchijf()) {
        if (_ingetrokken.contains(g.deviceId)) continue;
        if (!_byDevice.containsKey(g.deviceId)) erbij++;
        _neemOp(g);
      }
      if (erbij > 0) {
        meldlog?.call('koppelingen samengevoegd bij het opslaan: $erbij van schijf erbij '
            '(nu ${_byDevice.length})');
      }
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode([for (final g in _byDevice.values) g.toJson()]));
      await tmp.rename(_file.path);
    } catch (e) {
      debugPrint('Could not save grants.json: $e');
    }
    try {
      await _schrijfIngetrokken();
    } catch (e) {
      meldlog?.call('ingetrokken sleutels NIET opgeslagen: $e');
    }
  }

  /// The check on every request. Constant-time on the token so a wrong guess cannot be narrowed
  /// down by timing — cheap here, and the previous `==` had no such property.
  ///
  /// Alleen HTTP-sleutels (47820): een TLS-sleutel staat niet in [_byToken] en valt hier dus af.
  bool accepts(String token) {
    if (token.isEmpty || isIngetrokken(token)) return false;
    final deviceId = _byToken[token];
    if (deviceId == null) return false;
    final g = _byDevice[deviceId];
    if (g == null) return false;
    // Ook een EERDERE sleutel van ditzelfde toestel telt; zie [DeviceGrant.oudereTokens].
    for (final geldig in [g.token, ...g.oudereTokens]) {
      if (_constantTimeEquals(token, geldig)) return true;
    }
    return false;
  }

  /// Het toestel bij een HTTP- of TLS-sleutel. Zegt niets over waar die sleutel geldt: dat beslissen
  /// [accepts] (47820) en [acceptsTls] (47822, 47821).
  DeviceGrant? grantFor(String token) {
    final id = _byToken[token] ?? _byTls[token];
    return id == null ? null : _byDevice[id];
  }

  DeviceGrant? byDevice(String deviceId) => _byDevice[deviceId];

  /// Issue a token for a device. Idempotent per device: asking twice returns the grant that is
  /// already out there rather than minting a second one and orphaning the first.
  DeviceGrant mint({
    required String deviceId,
    required String deviceName,
    String platform = '',
  }) {
    final existing = _byDevice[deviceId];
    if (existing != null) return existing;
    final grant = DeviceGrant(
      deviceId: deviceId,
      deviceName: deviceName,
      token: generateDeviceToken(),
      platform: platform,
      grantedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _byDevice[deviceId] = grant;
    _byToken[grant.token] = deviceId;
    return grant;
  }

  /// Cut off exactly one device. This is the thing that could not be done before.
  bool revoke(String deviceId) {
    final gone = _byDevice.remove(deviceId);
    // Onthouden DAT je ontkoppeld hebt: anders haalt het samenvoegende opslaan dit toestel zo weer
    // van schijf terug, en doet ontkoppelen niets.
    _ingetrokken.add(deviceId);
    _weerToegelaten.remove(deviceId);
    if (gone == null) return false;
    // Ook elke sleutel van dit toestel apart: koppelt het later opnieuw, dan haalt een oudere kopie
    // op schijf zijn oude sleutels niet terug in `oudereTokens`.
    for (final t in [gone.token, ...gone.oudereTokens, ?gone.tlsToken]) {
      _byToken.remove(t);
      _byTls.remove(t);
      if (t.isNotEmpty) _ingetrokkenSleutels.add(_vingerafdruk(t));
    }
    return true;
  }

  void revokeAll() {
    _ingetrokken.addAll(_byDevice.keys);
    for (final g in _byDevice.values) {
      for (final t in [g.token, ...g.oudereTokens, ?g.tlsToken]) {
        if (t.isNotEmpty) _ingetrokkenSleutels.add(_vingerafdruk(t));
      }
    }
    _byDevice.clear();
    _byToken.clear();
    _byTls.clear();
  }

  /// Stand in for everything paired before grants existed, so upgrading does not cut off a device
  /// that was working a minute ago. One row in the list, revocable on purpose.
  void adoptLegacyToken(String token) {
    if (token.isEmpty || _byToken.containsKey(token)) return;
    const id = 'legacy';
    final grant = DeviceGrant(
      deviceId: id,
      deviceName: 'Eerder gekoppelde apparaten',
      token: token,
      platform: '',
      grantedAt: 0,
      legacy: true,
    );
    _byDevice[id] = grant;
    _byToken[token] = id;
  }

  /// Remember that a token was used, for the device list. Debounced to a minute: this is reached
  /// from every range request of a stream, and a disk write per request would be absurd.
  ///
  /// Een andere WEG dan de vorige keer telt meteen, ook binnen de minuut: thuis de deur uit is precies
  /// het moment dat de lijst moet laten zien.
  bool touch(String token, {String? via}) {
    final grant = grantFor(token);
    if (grant == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    final andereWeg = via != null && via != grant.lastSeenVia;
    if (!andereWeg && now - (grant.lastSeenAt ?? 0) < 60000) return false;
    grant.lastSeenAt = now;
    if (via != null) grant.lastSeenVia = via;
    return true;
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

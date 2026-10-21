/// The other side of `server.dart`: this app talking to a PC that owns the music.
///
/// On the Mac and the iPad there is no music folder to scan, so the library comes from
/// `GET /api/catalog` instead. Everything else in the app is unchanged — see
/// [LibraryStore.loadRemote], which turns what this returns into the very same `Track` and `Album`
/// objects a disk scan produces.
///
/// Two ways of carrying the token, on purpose:
///   • API calls send `Authorization: Bearer` — the ordinary thing.
///   • `/stream/` and `/art/` put it in the query, because the things that fetch those URLs are
///     libmpv, `Image.network`, a Sonos and a KEF, and none of them can be told to set a header.
/// The server accepts both. Anything in the query is also in the server's log, which is the price;
/// it is a token for a music library on a home network, and the alternative is that nothing plays.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../album_facts.dart';
import 'dtos.dart';
import 'pin_client.dart';
import 'poorten.dart';
import 'tokens.dart' show toestelWeg;
import 'vaste_naam.dart';
import 'zones.dart' show SseEvent, SseLezer;

/// A paired PC: where it is and what proves we may talk to it.
class RemoteEndpoint {
  /// `http://192.168.0.216:47820` — no trailing slash, no path.
  final Uri baseUrl;
  final String token;

  /// What the PC calls itself, for the settings screen. Not used to reach it.
  final String? name;

  /// De adressen waarop deze pc óók antwoordt als je niet op zijn netwerk bent — in de praktijk
  /// Tailscale. Opgehaald bij elke verbinding en hier bewaard, zodat ze er al zijn op het moment
  /// dat [baseUrl] niet meer werkt. Zie `uitwijk.dart`.
  ///
  /// Leeg is de gewone toestand voor een pc zonder Tailscale, en voor een pc die deze weg nog niet
  /// kent (die antwoordt 404).
  final List<String> uitwijk;

  /// Welke pc dit is: zijn vaste id (`settings.serverId` op de pc), geleerd bij de eerste verbinding.
  /// Leeg voor een koppeling van vóór 14-10-2026 of een pc die hem nog niet meegeeft.
  ///
  /// **Waarom.** Bij het kiezen tussen adressen (`adreswedloop.dart`) wint het eerste dat antwoordt.
  /// Op een vreemd wifi kan op `192.168.0.117:47820` best iets ánders staan; zonder dit id was dat
  /// ook een "pc".
  final String serverId;

  /// De vingerafdruk van het certificaat van de pc (`certificaat.dart`), thuis of via Tailscale geleerd.
  /// Leeg tot dan. Een versleutelde verbinding met een ander certificaat wordt geweigerd.
  final String pin;

  /// De versleutelde sleutel (alleen voor 47822/47821), na de eenmalige ruil of het koppelen over
  /// 47822. Leeg tot dan; [token] blijft de sleutel voor 47820.
  final String tlsToken;

  /// Waar de pc versleuteld luistert (thuis/Tailscale). 0 = nog niet bekend; dan [kTlsPoort].
  final int tlsPoort;

  const RemoteEndpoint({
    required this.baseUrl,
    required this.token,
    this.name,
    this.uitwijk = const [],
    this.serverId = '',
    this.pin = '',
    this.tlsToken = '',
    this.tlsPoort = 0,
  });

  RemoteEndpoint met({
    Uri? baseUrl,
    String? token,
    String? name,
    List<String>? uitwijk,
    String? serverId,
    String? pin,
    String? tlsToken,
    int? tlsPoort,
  }) =>
      RemoteEndpoint(
        baseUrl: baseUrl ?? this.baseUrl,
        token: token ?? this.token,
        name: name ?? this.name,
        uitwijk: uitwijk ?? this.uitwijk,
        serverId: serverId ?? this.serverId,
        pin: pin ?? this.pin,
        tlsToken: tlsToken ?? this.tlsToken,
        tlsPoort: tlsPoort ?? this.tlsPoort,
      );

  /// Praat deze verbinding versleuteld? Dat is zo als het gekozen adres de vastgepinde ingang is
  /// (47822, straks 47821): de wedloop kiest dat zelf zodra [kanVersleuteld]. Zie `adreswedloop.dart`.
  bool get versleuteld => baseUrl.scheme == 'https';

  /// Kan dit toestel versleuteld met de pc praten: een TLS-sleutel en de pin. Stap 8.1.
  bool get kanVersleuteld => pin.isNotEmpty && tlsToken.isNotEmpty;

  /// De gewone ingang op hetzelfde adres (47820), voor de terugval als de versleutelde niet antwoordt.
  Uri get httpBasis => versleuteld ? baseUrl.replace(scheme: 'http', port: kHttpPoort) : baseUrl;

  /// De versleutelde ingang op hetzelfde adres (thuis of Tailscale).
  Uri get tlsBasis =>
      versleuteld ? baseUrl : baseUrl.replace(scheme: 'https', port: tlsPoort > 0 ? tlsPoort : kTlsPoort);

  /// Accepts what a person types: `192.168.0.216`, `192.168.0.216:47820`, or a full URL.
  /// Returns null when there is nothing usable in it, so the caller can say so plainly.
  static Uri? parseHost(String input, {int defaultPort = 47820}) {
    var text = input.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'http://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    return Uri(
      scheme: uri.scheme.isEmpty ? 'http' : uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : defaultPort,
    );
  }

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl.toString(),
        'token': token,
        'name': name,
        if (uitwijk.isNotEmpty) 'uitwijk': uitwijk,
        if (serverId.isNotEmpty) 'serverId': serverId,
        if (pin.isNotEmpty) 'pin': pin,
        if (tlsToken.isNotEmpty) 'tlsToken': tlsToken,
        if (tlsPoort > 0) 'tlsPoort': tlsPoort,
      };

  static RemoteEndpoint? fromJson(Map<String, dynamic> j) {
    final url = Uri.tryParse((j['baseUrl'] ?? '').toString());
    final token = (j['token'] ?? '').toString();
    if (url == null || url.host.isEmpty || token.isEmpty) return null;
    return RemoteEndpoint(
      baseUrl: url,
      token: token,
      name: j['name'] as String?,
      // Ontbreekt in elk `paired_server.json` van vóór 04-09-2026, en dat hoort geen fout te zijn:
      // dan is de lijst leeg en wordt hij bij de eerste verbinding alsnog opgehaald.
      uitwijk: [for (final u in (j['uitwijk'] as List? ?? const [])) '$u'],
      serverId: (j['serverId'] ?? '').toString(),
      pin: (j['pin'] ?? '').toString(),
      tlsToken: (j['tlsToken'] ?? '').toString(),
      tlsPoort: (j['tlsPoort'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RemoteEndpoint && other.baseUrl == baseUrl && other.token == token;

  @override
  int get hashCode => Object.hash(baseUrl, token);
}

/// De client om met de pc achter [e] te praten: versleuteld de pin-client — zonder pin aanvaardt hij
/// niets, nooit "dan maar elk certificaat" — en anders een gewone.
///
/// **Eén regel voor iedereen die met de pc praat.** Op 15-10-2026 bleek de downloaddienst op de gsm
/// (`remote_services.dart`) een eigen `http.Client()` met de HTTP-sleutel te hebben: op de versleutelde
/// weg (sinds 3.9.482) vertrouwde die het certificaat van de pc niet, en zoeken en downloaden mislukten
/// thuis én onderweg, terwijl afspelen gewoon werkte.
http.Client clientVoor(RemoteEndpoint e) =>
    e.versleuteld ? pinClient(pin: e.pin.isEmpty ? '-' : e.pin) : http.Client();

/// De sleutel in de kop voor [e]: versleuteld de TLS-sleutel, anders de HTTP-sleutel. Nooit door elkaar:
/// een TLS-sleutel op 47820 wordt door de pc ingetrokken, een HTTP-sleutel op 47822/47821 geweigerd.
Map<String, String> sleutelKop(RemoteEndpoint e) =>
    {'Authorization': 'Bearer ${e.versleuteld ? e.tlsToken : e.token}'};

/// Het catalogusantwoord van de pc ontleden, op een ANDERE isolate.
///
/// **Waarom dit niet gewoon op de tekendraad mag.** Bij een gekoppeld toestel doet de pc het werk en
/// stuurt hij zijn hele bibliotheek door: bij duizend nummers is dat megabytes JSON. `utf8.decode` en
/// `jsonDecode` daarover kosten op een telefoon honderden milliseconden, en al die tijd tekent er
/// niets.
///
/// Dat viel niet op zolang het zelden gebeurde: de telefoon vraagt elke vijftien seconden of er iets
/// veranderd is, en normaal is het antwoord een lege 304. Maar tijdens een download verandert de
/// bibliotheek van de pc bij élk binnengekomen nummer — dus komt er elke vijftien seconden een
/// volledige catalogus binnen, en stond de telefoon vier keer per minuut stil. Gemeld op 27-08-2026:
/// "vanaf ik download via torrent hapert de app enorm, zelfs roteren is massa's traag". Roteren
/// bouwt de hele boom opnieuw op, en dat kwam er bovenop.
///
/// **De sluiting staat op TOPNIVEAU en met opzet niet in een methode.** Een sluiting die binnen een
/// instantiemethode gemaakt wordt draagt zijn omgeving mee — inclusief `this` en de luisteraars die
/// eraan hangen — en dat is niet verzendbaar: de verzending gooit, en van buiten zie je alleen een
/// lege bibliotheek. Diezelfde uitleg staat bij [scanTagsInIsolate] in `library.dart`, waar het al
/// een keer misging.
Future<Map<String, dynamic>?> ontleedCatalogus(Uint8List bytes) =>
    Isolate.run(() => _ontleedCatalogus(bytes));

Map<String, dynamic>? _ontleedCatalogus(Uint8List bytes) {
  try {
    final d = jsonDecode(utf8.decode(bytes));
    return d is Map<String, dynamic> ? d : null;
  } catch (_) {
    // Een onleesbaar antwoord is geen bibliotheek. De aanroeper maakt er een nette melding van;
    // een uitzondering uit een isolate is dat niet.
    return null;
  }
}

/// A catalogue plus the ETag it came with. [catalog] is null when the PC answered 304, which means
/// "nothing changed" — the client keeps what it has rather than rebuilding an identical library.
class CatalogResponse {
  final CatalogDto? catalog;
  final String? etag;

  /// Wat de pc letterlijk stuurde, onbewerkt.
  ///
  /// Bestaat zodat het toestel de bibliotheek op zijn eigen schijf kan bewaren zonder hem eerst
  /// terug te vertalen naar JSON. Terugvertalen zou een tweede schrijfwijze zijn die van de echte af
  /// kan drijven — en dan leest een volgende versie een kopie die net niet meer klopt.
  ///
  /// **De BYTES, en niet de ontlede kaart die hier eerst stond.** Terugcoderen is `jsonEncode` over
  /// megabytes op de tekendraad, en dat gebeurde elke keer dat de catalogus veranderde. Tijdens een
  /// download is dat om de paar seconden.
  final List<int>? bytes;

  const CatalogResponse(this.catalog, this.etag, {this.bytes});

  bool get unchanged => catalog == null;
}

/// What a PC says about itself before any pairing has happened.
class ServerHealth {
  final String name;
  final String version;
  final int trackCount;

  /// De vaste id van de pc, of leeg bij een pc van vóór 14-10-2026. Zie [RemoteEndpoint.serverId].
  final String serverId;
  const ServerHealth({this.name = '', this.version = '', this.trackCount = 0, this.serverId = ''});
}

/// A speaker, a television, or anything else on the network that can be handed a URL.
class CastDevice {
  const CastDevice({
    required this.id,
    required this.name,
    required this.kind,
    this.model = '',
    this.maxSampleRate = 0,
  });

  final String id;
  final String name;
  final String model;

  /// The highest rate this thing will accept, or 0 for no ceiling. A Sonos stops at 48 kHz, so a
  /// 24/96 record is converted on the way — worth saying before you press play rather than
  /// afterwards.
  final int maxSampleRate;

  /// `shield` for a device running this app, anything else for a UPnP renderer. The difference is
  /// worth showing: only the first plays the file untouched — a speaker takes what its own decoder
  /// will accept, and the PC converts to meet it.
  final String kind;

  bool get playsUntouched => kind == 'shield';

  static CastDevice fromJson(Map<String, dynamic> j) => CastDevice(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? 'Onbekend').toString(),
        kind: (j['kind'] ?? 'upnp').toString(),
        model: (j['model'] ?? '').toString(),
        maxSampleRate: (j['maxSampleRate'] as num?)?.toInt() ?? 0,
      );
}

/// What a speaker is doing, as the speaker itself reports it.
///
/// Nullable throughout, and that is the point: this is read from an embedded UPnP stack that may
/// answer some questions and not others. A missing position means "do not draw a bar", never
/// "back to the start".
class CastStatus {
  const CastStatus({
    required this.casting,
    this.position,
    this.duration,
    this.playing,
    this.volume,
    this.index,
    this.queueLength,
    this.probleem,
  });

  /// True when this speaker is playing a queue THIS pc started. A speaker someone else in the house
  /// is using answers false, and then its position is none of our business.
  final bool casting;
  final Duration? position;
  final Duration? duration;
  final bool? playing;
  final int? volume;
  final int? index;
  final int? queueLength;

  /// Waarom er niets klinkt, als de pc dat weet. Null als er niets aan de hand is.
  final String? probleem;

  bool get hasPrev => (index ?? 0) > 0;
  bool get hasNext => index != null && queueLength != null && index! + 1 < queueLength!;

  static Duration? _ms(Object? v) =>
      v is num ? Duration(milliseconds: v.toInt()) : null;

  static CastStatus fromJson(Map<String, dynamic> j) => CastStatus(
        casting: j['casting'] == true,
        position: _ms(j['positionMs']),
        duration: _ms(j['durationMs']),
        playing: j['playing'] is bool ? j['playing'] as bool : null,
        volume: (j['volume'] as num?)?.toInt(),
        index: (j['index'] as num?)?.toInt(),
        queueLength: (j['queueLength'] as num?)?.toInt(),
        probleem: j['probleem'] as String?,
      );
}

class RemoteException implements Exception {
  final String message;

  /// 401/403 mean the pairing is no longer good — worth telling the user to pair again, rather
  /// than showing the same "kon de pc niet bereiken" as a pulled network cable.
  final int? statusCode;
  const RemoteException(this.message, {this.statusCode});

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

class RemoteClient {
  final RemoteEndpoint endpoint;
  final http.Client _http;

  /// Long enough for a big library over wifi, short enough that a PC which went to sleep does not
  /// leave the app on a spinner forever.
  final Duration timeout;

  /// Versleuteld (`endpoint.versleuteld`): een client die alleen het certificaat met de pin aanvaardt.
  /// Zonder pin aanvaardt hij niets — nooit "dan maar elk certificaat".
  RemoteClient(this.endpoint,
      {http.Client? client, this.timeout = const Duration(seconds: 30), this.viaDoorgever, this.vanDoorgever})
      : _http = client ?? clientVoor(endpoint);

  /// Het adres voor mpv bij een stroom van de pc, als er versleuteld gepraat wordt: de doorgever op dit
  /// toestel (`doorgever.dart`). mpv kan het certificaat van de pc niet vastpinnen, en de sleutel hoort
  /// niet in een adres.
  final Uri Function(Uri pcAdres)? viaDoorgever;

  /// Een adres van de doorgever terug naar de vaste naam van de pc (`pc.invalid`), of null als het er geen is.
  final Uri? Function(Uri adres)? vanDoorgever;

  Uri _api(String path, [Map<String, String>? query]) =>
      endpoint.baseUrl.replace(path: path, queryParameters: query);

  /// Zie [sleutelKop].
  Map<String, String> get _headers => sleutelKop(endpoint);

  /// The library. Pass the ETag from last time and the PC answers 304 when nothing changed, which
  /// is the ordinary case on every poll — the fingerprint is over the CONTENT, so enriching a
  /// cover does not re-push twelve thousand tracks.
  Future<CatalogResponse> catalog({String? etag}) async {
    final res = await _get('/api/catalog', etag: etag);
    if (res.statusCode == 304) return CatalogResponse(null, etag);
    // Op een ANDERE isolate. Zie [ontleedCatalogus] voor waarom dat hier het verschil maakt.
    final decoded = await ontleedCatalogus(res.bodyBytes);
    if (decoded == null) {
      throw const RemoteException('De pc stuurde geen bibliotheek terug.');
    }
    return CatalogResponse(
      CatalogDto.fromJson(decoded),
      res.headers['etag'],
      bytes: res.bodyBytes,
    );
  }

  /// What the PC knows about a record: its pressing, the label's tracklist, what is missing.
  ///
  /// Asked of the PC rather than worked out here, and that is the point. Every device used to run
  /// its own MusicBrainz search on every album open — four devices browsing meant four independent
  /// six-request chains against one anonymous per-second budget, each with a private cache that
  /// helped nobody else. The PC works it out once and hands it round.
  ///
  /// The first ask for a record the PC has not looked at yet takes as long as it always did; every
  /// ask after that, from any device, is instant.
  /// De scans van een album zoals de pc ze heeft (`/api/releaseart`), als JSON — zie `kunstUitJson` in
  /// discogs.dart. Null als de pc ze niet heeft of het niet kent.
  Future<Map<String, dynamic>?> releaseArtJson(String albumId) async {
    final res = await _get('/api/releaseart', query: {'albumId': albumId});
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Future<AlbumFacts?> albumFacts(String albumId, {String? etag, bool force = false}) async {
    // Through [query], never as a string on the path: _api replaces the whole path, so a `?` in
    // there is escaped INTO it and the server sees a route it has never heard of.
    final res = await _get('/api/album/facts',
        etag: etag, query: {'albumId': albumId, if (force) 'force': '1'});
    if (res.statusCode == 304 || res.statusCode == 404) return null;
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map<String, dynamic>) return null;
    return AlbumFacts.fromJson(decoded);
  }

  /// Add the token to a URL that was stored without one — what [LibraryStore] keeps in
  /// `Track.path`, handed over at the moment of playback.
  ///
  /// Anything not pointing at our own PC is returned untouched. A Radio queue mixes library tracks
  /// with resolved TorBox streams, and appending our pairing token to someone else's URL would
  /// both fail and hand the token to a stranger.
  ///
  /// De vaste naam van een nummer (`http://pc.invalid/stream/…`, zie `vaste_naam.dart`) wordt hier
  /// het adres van NU: dat van deze verbinding.
  String authorized(String url) {
    final uri = _naarHier(url);
    if (uri == null) return url;
    // Versleuteld: via de doorgever, en nooit de HTTP-sleutel in het adres.
    if (endpoint.versleuteld) {
      final via = viaDoorgever;
      if (via != null) return via(uri).toString();
      // Geen doorgever (hij startte niet): dan de gewone ingang met de HTTP-sleutel, thuis of via
      // Tailscale. Liever dat dan een nummer dat niet speelt.
      final h = endpoint.httpBasis;
      return uri
          .replace(scheme: h.scheme, port: h.port, queryParameters: {...uri.queryParameters, 'token': endpoint.token})
          .toString();
    }
    return uri.replace(queryParameters: {...uri.queryParameters, 'token': endpoint.token})
        .toString();
  }

  /// [url] als hij naar onze pc wijst, op het adres van deze verbinding; anders null.
  Uri? _naarHier(String url) {
    var uri = Uri.tryParse(url);
    if (uri == null) return null;
    // Een adres dat mpv van de doorgever kreeg (bij "waarom speelt dit niet"): eerst naar `pc.invalid`.
    uri = vanDoorgever?.call(uri) ?? uri;
    final b = endpoint.baseUrl;
    if (uri.host == kPcHost) {
      return uri.replace(scheme: b.scheme, host: b.host, port: b.hasPort ? b.port : null);
    }
    if (uri.host != b.host) return null;
    // Versleuteld praten we met 47822; een adres op de gewone poort van DEZELFDE pc is ook van ons, en
    // gaat dan over dezelfde versleutelde weg. Een ander adres nooit: dat kan een andere machine zijn.
    if (endpoint.versleuteld && uri.port == kHttpPoort) {
      return uri.replace(scheme: b.scheme, port: b.hasPort ? b.port : null);
    }
    if (uri.port != b.port) return null;
    return uri;
  }

  /// Wat de pc over dit nummer te zeggen heeft nadat het openen mislukt is, of null.
  ///
  /// [streamUrl] is de url die aan mpv gegeven is. Wijst die niet naar ONZE pc, dan valt er niets
  /// te vragen: een Radio-wachtrij mengt bibliotheeknummers met opgeloste TorBox-stromen, en de
  /// eigenaar daarvan weet niets van onze catalogus — dezelfde reden als bij [authorized].
  ///
  /// Null bij alles wat misgaat, en dat is met opzet ruim: dit draait NA een mislukking, om een
  /// foutmelding preciezer te maken. Loopt het hier ook mis, dan blijft de melding staan die er al
  /// stond. Een tweede foutmelding over de eerste heen helpt niemand.
  Future<String?> waarom(String streamUrl) async {
    try {
      final uri = _naarHier(streamUrl);
      if (uri == null || !uri.path.startsWith('/stream/')) return null;
      // De sleutel in de kop, niet in het adres (stap 5 van "verbinden zoals Roon ARC"): een adres met een
      // sleutel erin belandt in logboeken, en de versleutelde ingangen nemen hem daar niet eens aan.
      final vraag = endpoint.baseUrl.replace(path: uri.path.replaceFirst('/stream/', '/waarom/'));
      // Kort: dit hangt aan een foutmelding die al op het scherm staat, en een gebruiker die vier
      // seconden op een preciezere zin wacht is slechter af dan een die hem niet krijgt.
      final res = await _http.get(vraag, headers: _headers).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is! Map) return null;
      final reden = body['reden'];
      return reden is String && reden.trim().isNotEmpty ? reden.trim() : null;
    } catch (_) {
      return null;
    }
  }

  /// Cover art. Zonder sleutel in het adres: [art] en [artAls] zetten hem in de kop.
  /// `maxZijde` vraagt de pc om de hoes eerst te verkleinen. Zie `verkleindeHoes` in
  /// `artwork.dart`: 548 hoezen van samen 174 MB, met een staart tot 14,7 MB, voor een tegel van
  /// 390 pixels. Laat je hem weg, dan komt onveranderd het origineel — dat is wat de pc zelf en elk
  /// ouder toestel doen.
  Uri artUrl(String ref, {int? maxZijde}) => endpoint.baseUrl
      .replace(path: '/art/$ref', queryParameters: maxZijde == null ? null : {'w': '$maxZijde'});

  /// Fetch a cover. Null rather than throwing when there simply isn't one — an album without art
  /// is normal, not a failure, and the caller would only swallow the exception anyway.
  Future<Uint8List?> art(String ref) async {
    try {
      final res = await _http.get(artUrl(ref), headers: _headers).timeout(timeout);
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  /// "Ik heb deze hoes al — is hij nog steeds de jouwe?"
  ///
  /// Hetzelfde verzoek als [art], maar met het merkteken van wat er hier op schijf ligt. De pc
  /// antwoordt met een lege 304 als het klopt, en anders meteen met de nieuwe bytes. Eén rit over de
  /// lijn dus, ook in het slechtste geval.
  ///
  /// **Waarom dit er is.** De hoescache van een toestel heet naar `artiest|titel`, en die naam
  /// beweegt niet als de afbeelding verandert. Zonder deze vraag was er voor een hoes die niet uit
  /// een bewuste keuze kwam nergens iets om aan te zien dat het bestand achterhaald was, en bleef de
  /// Mac een andere hoes tonen dan de pc — hoe vaak je het daar ook corrigeerde.
  ///
  /// De uitkomsten: `ongewijzigd` (houden wat je hebt), bytes (vervangen), of null — dat laatste is
  /// "geen antwoord" en betekent uitdrukkelijk NIET dat de hoes weg moet. Een pc die even niet
  /// bereikbaar is mag geen schermen leegmaken.
  ///
  /// `merk` mag leeg zijn: dan is het gewoon een gewoon verzoek, en dient dit alleen om het
  /// merkteken van de pc mee terug te krijgen.
  ///
  /// `etag` is null als de pc er geen meegaf. Dat is een OUDERE pc, en de beller hoort daaruit af te
  /// leiden dat navragen daar zinloos is — anders haalt hij bij elke ronde elke hoes opnieuw op.
  Future<({bool ongewijzigd, Uint8List? bytes, String? etag})?> artAls(
      String ref, String merk, {int? maxZijde}) async {
    try {
      final res = await _http
          .get(artUrl(ref, maxZijde: maxZijde), headers: {..._headers, if (merk.isNotEmpty) 'If-None-Match': '"$merk"'})
          .timeout(timeout);
      final etag = res.headers['etag']?.replaceAll('"', '');
      if (res.statusCode == 304) return (ongewijzigd: true, bytes: null, etag: etag);
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      return (ongewijzigd: false, bytes: res.bodyBytes, etag: etag);
    } catch (_) {
      return null;
    }
  }

  /// The read-only keys the PC is willing to share, so this device can look things up itself.
  /// Empty rather than throwing when the PC has none: that is a PC without a Discogs token, which
  /// is a perfectly ordinary thing to be.
  /// The speakers and televisions the PC can see.
  ///
  /// Asked of the PC rather than discovered here, and that is deliberate: SSDP is multicast, which
  /// an iPad may not send without an Apple entitlement, and the audio has to leave from the PC
  /// anyway. One implementation, on the machine that holds the music.
  Future<List<CastDevice>> castDevices() async {
    try {
      final res = await _get('/api/cast/devices');
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j is! List) return const [];
      return [
        for (final e in j)
          if (e is Map<String, dynamic>) CastDevice.fromJson(e),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Send a queue to one of them. The PC does the sending; this only says what and where.
  Future<bool> castPlay(String deviceId, List<String> trackIds, int index) =>
      _castPost('/api/cast/play', {'deviceId': deviceId, 'trackIds': trackIds, 'index': index});

  /// Een andere volgorde voor wat er nog komt, zonder het lopende nummer opnieuw te beginnen.
  ///
  /// Voor shuffle tijdens het casten. [index] is waar het nummer dat NU speelt in de nieuwe lijst staat.
  Future<bool> castRequeue(String deviceId, List<String> trackIds, int index) =>
      _castPost('/api/cast/requeue', {'deviceId': deviceId, 'trackIds': trackIds, 'index': index});

  /// play | pause | stop | next | previous | volume ([value] 0-100) | seek ([value] in seconds).
  Future<bool> castControl(String deviceId, String action, {int? value}) => _castPost(
        '/api/cast/control',
        {'deviceId': deviceId, 'action': action, if (value != null) 'value': value},
      );

  /// What the speaker is doing: position, length, whether it is playing, and its volume.
  ///
  /// Every field is optional — a renderer that answers some questions and not others is ordinary.
  /// An empty map means "could not ask", which is different from "stopped" and must not be drawn
  /// as a track that jumped back to zero.
  Future<CastStatus?> castStatus(String deviceId, {bool withVolume = false}) async {
    try {
      // Through `query`, not glued into the path. `_api` builds the URL with
      // `baseUrl.replace(path: path)`, and Dart percent-encodes a `?` that appears in a path — so
      // the PC was asked for `/api/cast/status%3FdeviceId=…`, which matches no route. It answered
      // 404, the catch below turned that into null, and null is indistinguishable from "the speaker
      // did not answer". Every status was therefore missing: no position, no volume, no play state.
      // That is why the transport controls went dead the moment a phone or iPad cast to a speaker.
      final res = await _get('/api/cast/status', query: {
        'deviceId': deviceId,
        if (withVolume) 'volume': '1',
      });
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      return j is Map<String, dynamic> ? CastStatus.fromJson(j) : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _castPost(String path, Map<String, dynamic> body) async {
    try {
      final res = await _http
          .post(_api(path),
              headers: {..._headers, 'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(timeout);
      return res.statusCode == 200;
    } catch (_) {
      // A speaker that did not take it is a speaker that stays silent; the picker says so rather
      // than throwing into a build.
      return false;
    }
  }

  /// De adressen waarop deze pc ook van buitenaf antwoordt. Zie `uitwijk.dart`.
  ///
  /// Een lege lijst bij álles wat misgaat, en dat is met opzet: een pc zonder Tailscale, een pc van
  /// vóór deze weg (404) en een pc die net omviel geven hier hetzelfde antwoord — we weten geen
  /// uitwijkadres. Wat we al hadden wordt daarom door de aanroeper NIET weggegooid op een lege
  /// lijst; zie `client_session.dart`.
  Future<List<String>> uitwijkAdressen() async => (await uitwijk()).urls;

  /// Waar deze pc nog meer te bereiken is, en de pin van zijn certificaat en zijn versleutelde poort.
  /// Alles leeg bij álles wat misgaat (zie [uitwijkAdressen]).
  Future<({List<String> urls, String pin, int tlsPoort})> uitwijk() async {
    try {
      final res = await _get('/api/uitwijk');
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j is! Map) return (urls: const <String>[], pin: '', tlsPoort: 0);
      return (
        // Van buiten bereikbaar én thuis: de wedloop deelt elk adres zelf in (thuis meteen, de rest
        // 400 ms later), dus allebei in één lijst.
        urls: [
          for (final u in (j['urls'] as List? ?? const [])) '$u',
          for (final u in (j['thuis'] as List? ?? const [])) '$u',
          // De eigen deur naar buiten (https, alleen met de pin): de wedloop probeert hem alleen versleuteld.
          for (final u in (j['buiten'] as List? ?? const [])) '$u',
        ],
        pin: (j['pin'] ?? '').toString(),
        tlsPoort: (j['tlsPoort'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return (urls: const <String>[], pin: '', tlsPoort: 0);
    }
  }

  Future<Map<String, String>> config() async {
    try {
      final res = await _get('/api/config');
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j is! Map) return const {};
      return {
        for (final e in j.entries)
          if (e.value is String) '${e.key}': e.value as String,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Ask the PC to change something about the library.
  ///
  /// The album is named by the id the PC issued, not by its title: the library can hold two
  /// pressings of one record, and a title would be ambiguous exactly where it matters most.
  Future<void> edit(Map<String, dynamic> operation) async {
    final http.Response res;
    try {
      res = await _http
          .post(_api('/api/corrections'),
              headers: {..._headers, 'Content-Type': 'application/json'},
              body: jsonEncode(operation))
          .timeout(timeout);
    } catch (e) {
      throw RemoteException('Kon de pc niet bereiken: $e');
    }
    if (res.statusCode == 200) return;
    final decoded = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    throw RemoteException(
      (decoded is Map ? decoded['error'] as String? : null) ??
          'De pc weigerde de wijziging (${res.statusCode}).',
      statusCode: res.statusCode,
    );
  }

  /// De balk "Nieuwe release", zoals de pc hem berekende en bewaarde (`nieuwe_releases.dart`).
  ///
  /// [onbekend] is waar als de pc de vraag niet kent — een oudere pc. Dan rekent dit toestel zelf;
  /// bij een pc die gewoon even niet antwoordt niet, want dat kost honderd vragen aan Deezer voor iets
  /// wat de pc straks gewoon heeft.
  /// "Aanbevolen voor jou" van de pc. [onbekend] = de pc kent `/api/aanbevolen` nog niet (oude versie).
  Future<({Map<String, dynamic>? lijst, bool onbekend})> aanbevolen({bool ververs = false}) async {
    try {
      final res = await _get('/api/aanbevolen', query: ververs ? const {'ververs': '1'} : null);
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      return (lijst: j is Map<String, dynamic> ? j : null, onbekend: false);
    } on RemoteException catch (e) {
      return (lijst: null, onbekend: e.statusCode == 404);
    } catch (_) {
      return (lijst: null, onbekend: false);
    }
  }

  /// Met [beideRijen] de twee rijen (nummers, albums & EP's) via `/api/nieuw`; kent de pc die nog niet
  /// (404), dan de oude lijst via `/api/releases`, waar [ReleasesLijst.fromJson] zelf twee rijen van maakt.
  Future<({Map<String, dynamic>? lijst, bool onbekend})> nieuweReleases(
      {bool ververs = false, bool beideRijen = false}) async {
    if (beideRijen) {
      try {
        final res = await _get('/api/nieuw', query: ververs ? const {'ververs': '1'} : null);
        final j = jsonDecode(utf8.decode(res.bodyBytes));
        return (lijst: j is Map<String, dynamic> ? j : null, onbekend: false);
      } on RemoteException catch (e) {
        if (e.statusCode != 404) return (lijst: null, onbekend: false);
      } catch (_) {
        return (lijst: null, onbekend: false);
      }
    }
    try {
      final res = await _get('/api/releases', query: ververs ? const {'ververs': '1'} : null);
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      return (lijst: j is Map<String, dynamic> ? j : null, onbekend: false);
    } on RemoteException catch (e) {
      return (lijst: null, onbekend: e.statusCode == 404);
    } catch (_) {
      return (lijst: null, onbekend: false);
    }
  }

  /// De gedeelde staat van de pc: favorieten, afspeellijsten, telling en positie.
  ///
  /// Een GET en geen [ask], want er valt niets te vragen — dit is gewoon wat er ligt. `since`
  /// bewust weggelaten: dit toestel houdt geen revisie bij, en een volledige momentopname is een
  /// paar kilobytes.
  Future<Map<String, dynamic>> gedeeldeStaat() async {
    final res = await _get('/api/state');
    if (res.statusCode != 200) {
      throw RemoteException('De pc antwoordde met ${res.statusCode}.', statusCode: res.statusCode);
    }
    final decoded = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  /// De speelstand van de pc, en wie wat speelt ("Hier verder luisteren"). Met [sinds] de revisie die
  /// dit toestel kent: dan komt alleen de stand mee zolang er verder niets veranderde. [toestel] en
  /// [naam] zeggen de pc dat dit toestel er is, voor "Speel op …".
  /// Alle zones zoals de pc ze kent (`{nu, zones}`, zie `zones.dart`). 404 op een pc van vóór de zones.
  Future<Map<String, dynamic>> zones() async {
    final res = await _get('/api/zones');
    final decoded = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  /// De volledige melding van één zone, met de wachtrij — voor "Hier verder luisteren" vanaf die zone.
  /// Null als die zone niets meldde.
  Future<Map<String, dynamic>?> zoneStand(String zone) async {
    final http.Response res;
    try {
      res = await _http.get(_api('/api/zones/stand', {'zone': zone}), headers: _headers).timeout(timeout);
    } catch (e) {
      throw RemoteException('Kon de pc niet bereiken: $e');
    }
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw RemoteException('De pc antwoordde met ${res.statusCode}.', statusCode: res.statusCode);
    }
    final decoded = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// Een venster op de wachtrij van een zone (`{index, lengte, van, rij}`, zie `ZoneRegister.rijVenster`),
  /// of null als die zone geen wachtrij meldt.
  Future<Map<String, dynamic>?> zoneRij(String zone) async {
    final http.Response res;
    try {
      res = await _http
          .get(_api('/api/zones/stand', {'zone': zone, 'venster': '1'}), headers: _headers)
          .timeout(timeout);
    } catch (e) {
      throw RemoteException('Kon de pc niet bereiken: $e');
    }
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) {
      throw RemoteException('De pc antwoordde met ${res.statusCode}.', statusCode: res.statusCode);
    }
    final decoded = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// De zones als stroom (`/api/zones/events`): elk bericht zodra de pc het stuurt, en een `ping` bij
  /// elk teken van leven (zodat de aanroeper een dode lijn herkent aan stilte).
  ///
  /// Een EIGEN verbinding, los van de gewone: wie de stroom stopzet, sluit die verbinding, en dan is
  /// de lijn ook echt dicht. Over de gewone zou een openstaande stroom voor altijd een plek bezetten.
  /// Een pc zonder zones antwoordt 404: dan een [RemoteException] met die code.
  ///
  /// Geen `async*`: wie zo'n stroom stopzet terwijl hij op de volgende regel wacht, kreeg de fout van
  /// de dichtgegooide verbinding ("Connection closed while receiving data") als onopgevangen fout. Hier
  /// sluit stoppen de verbinding, en wat er daarna nog binnenkomt, valt stil weg.
  Stream<SseEvent> zoneStroom({
    required String toestel,
    required String naam,
    String platform = '',
    bool tv = false,
  }) {
    late final StreamController<SseEvent> uit;
    final c = clientVoor(endpoint);
    StreamSubscription<String>? regels;
    var dicht = false;

    Future<void> sluit() async {
      if (dicht) return;
      dicht = true;
      final r = regels;
      regels = null;
      c.close();
      try {
        await r?.cancel();
      } catch (_) {}
    }

    void fout(Object e) {
      if (dicht) return;
      uit.addError(e);
      unawaited(sluit());
      unawaited(uit.close());
    }

    uit = StreamController<SseEvent>(
      onListen: () async {
        final req = http.Request(
            'GET',
            _api('/api/zones/events', {
              'toestel': toestel,
              'naam': naam,
              if (platform.isNotEmpty) 'platform': platform,
              if (tv) 'tv': '1',
            }))
          ..headers.addAll({..._headers, 'Accept': 'text/event-stream'});
        final http.StreamedResponse res;
        try {
          res = await c.send(req).timeout(timeout);
        } catch (e) {
          return fout(RemoteException('Kon de pc niet bereiken: $e'));
        }
        if (dicht) return;
        if (res.statusCode != 200) {
          return fout(RemoteException('De pc antwoordde met ${res.statusCode}.', statusCode: res.statusCode));
        }
        final lezer = SseLezer();
        regels = res.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
          (regel) {
            if (dicht) return;
            if (regel.startsWith(':')) {
              uit.add((event: 'ping', data: ''));
              return;
            }
            final e = lezer.regel(regel);
            if (e != null) uit.add(e);
          },
          onError: (Object e) => fout(e),
          onDone: () {
            if (dicht) return;
            unawaited(sluit());
            unawaited(uit.close());
          },
          cancelOnError: true,
        );
      },
      onCancel: sluit,
    );
    return uit.stream;
  }

  Future<Map<String, dynamic>> speelstand({int? sinds, required String toestel, required String naam}) async {
    final res = await _get('/api/state', query: {
      if (sinds != null) 'since': '$sinds',
      'toestel': toestel,
      'naam': naam,
    });
    if (res.statusCode != 200) {
      throw RemoteException('De pc antwoordde met ${res.statusCode}.', statusCode: res.statusCode);
    }
    final decoded = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  /// Ask the PC a question whose answer is a JSON object. Same shape as [edit], but the body
  /// matters — a move plan is the whole point of the call.
  Future<Map<String, dynamic>> ask(String path, Map<String, dynamic> body) async {
    final http.Response res;
    try {
      res = await _http
          .post(_api(path),
              headers: {..._headers, 'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(timeout);
    } catch (e) {
      throw RemoteException('Kon de pc niet bereiken: $e');
    }
    final decoded = res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    final map = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    if (res.statusCode == 200) return map;
    throw RemoteException(
      (map['error'] as String?) ?? 'De pc antwoordde met ${res.statusCode}.',
      statusCode: res.statusCode,
    );
  }

  Future<http.Response> _get(String path, {String? etag, Map<String, String>? query}) async {
    final http.Response res;
    try {
      res = await _http
          .get(_api(path, query), headers: {
            ..._headers,
            if (etag != null) 'If-None-Match': etag,
          })
          .timeout(timeout);
    } catch (e) {
      throw RemoteException('Kon de pc niet bereiken: $e');
    }
    if (res.statusCode == 304 || res.statusCode == 200) return res;
    throw RemoteException(
      res.statusCode == 401 || res.statusCode == 403
          // Sinds 14-10-2026 niet meer "Koppel opnieuw": een geweigerde sleutel herstelt zichzelf via
          // het account zodra de pc bereikbaar is (sleutelherstel.dart). Koppelen met een code is
          // alleen nog nodig als dat niet lukt — en dan staat de knop er.
          ? 'Je pc herkent dit toestel niet meer. Dat lost zich vanzelf op zodra je thuis bent of '
              'Tailscale aanzet, als je pc en dit toestel op hetzelfde account zijn aangemeld.'
          : 'De pc antwoordde met ${res.statusCode}.',
      statusCode: res.statusCode,
    );
  }

  void close() => _http.close();

  // ── Before there is an endpoint ────────────────────────────────────────────
  //
  // Static, because pairing is exactly the moment when you do not have a token yet.

  /// Ask a PC who it is. Null when nothing at that address answers like our server — used by the
  /// pairing screen to tell "wrong address" apart from "wrong code".
  static Future<ServerHealth?> health(Uri baseUrl,
      {http.Client? client, Duration timeout = const Duration(seconds: 4), String pin = ''}) async {
    // Een versleuteld adres alleen met de pin: zonder pin geen antwoord, nooit "elk certificaat".
    if (client == null && baseUrl.scheme == 'https' && pin.isEmpty) return null;
    final c = client ?? (baseUrl.scheme == 'https' ? pinClient(pin: pin) : http.Client());
    try {
      final res = await c.get(baseUrl.replace(path: '/health')).timeout(timeout);
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body);
      if (j is! Map || j['status'] != 'ok') return null;
      return ServerHealth(
        name: (j['name'] ?? j['deviceName'] ?? '').toString(),
        version: (j['version'] ?? '').toString(),
        trackCount: (j['trackCount'] as num?)?.toInt() ?? 0,
        serverId: (j['serverId'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    } finally {
      if (client == null) c.close();
    }
  }

  /// De sleutel uit een koppelantwoord, of een fout met de zin die de pc zelf meestuurde.
  ///
  /// **Waarom dit niet gewoon `j['token']` is.** Een pc kan een weigering met de goede uitleg
  /// erin sturen en tóch status 200 zetten — dat deed hij tot 16-09-2026 bij élke koppelweigering,
  /// zie `_json` in `server.dart`. Kijk je dan alleen naar de sleutel, dan hou je over: *"De pc gaf
  /// geen sleutel terug"*, terwijl er in datzelfde antwoord *"Je pc is niet ingelogd"* stond. Saber
  /// heeft die ochtend zeven keer geprobeerd te koppelen zonder ooit te lezen wat eraan scheelde.
  ///
  /// De pc is gerepareerd, maar een telefoon praat ook met pc's die nog niet bijgewerkt zijn. Deze
  /// kant kijkt daarom eerst of er een `error` in staat, wat de statuscode ook zegt.
  static String _sleutelUit(dynamic body) {
    final map = body is Map ? body : const <String, dynamic>{};
    final uitleg = (map['error'] ?? '').toString().trim();
    if (uitleg.isNotEmpty) throw RemoteException(uitleg);
    final token = (map['token'] ?? '').toString();
    if (token.isEmpty) {
      throw const RemoteException(
        'De pc antwoordde wel, maar gaf geen sleutel en ook geen reden. '
        'Staat er op de pc een nieuwere versie van DebridMusic?',
      );
    }
    return token;
  }

  /// Redeem the six digits shown on the PC. Throws with a message meant to be read by the person
  /// holding the iPad, not by a log.
  static Future<RemoteEndpoint> pair(
    Uri baseUrl,
    String code, {
    required String deviceName,
    // Het eigen id van dit toestel (`thisDevice().id`), zodat de pc één rij per toestel houdt en dit
    // toestel los kan intrekken. Zonder maakt de pc er zelf een.
    String? deviceId,
    String platform = '',
    http.Client? client,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final c = client ?? http.Client();
    try {
      final res = await c
          .post(
            baseUrl.replace(path: '/pair'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': code,
              'deviceName': deviceName,
              if (deviceId != null) 'deviceId': deviceId,
              if (platform.isNotEmpty) 'platform': platform,
            }),
          )
          .timeout(timeout);
      if (res.statusCode == 403) {
        throw const RemoteException(
          'Die code klopt niet, of hij is verlopen. Vraag op de pc een nieuwe.',
          statusCode: 403,
        );
      }
      if (res.statusCode != 200) {
        throw RemoteException('Koppelen mislukte (${res.statusCode}).', statusCode: res.statusCode);
      }
      final j = jsonDecode(res.body);
      return RemoteEndpoint(
        baseUrl: baseUrl,
        token: _sleutelUit(j),
        name: (j is Map ? j['name'] : null)?.toString(),
      );
    } on RemoteException {
      rethrow;
    } catch (e) {
      throw RemoteException('Kon de pc niet bereiken: $e');
    } finally {
      if (client == null) c.close();
    }
  }

  /// Binnenkomen op grond van je ACCOUNT, zonder code en zonder accountdatabase.
  ///
  /// Het toestel laat zijn verse inlogsleutel zien; de pc vraagt bij Google van wie die is en
  /// vergelijkt dat met zijn eigen account. Zie `accountkoppeling.dart` en `server.dart:_pairCloud`.
  ///
  /// **Waarom een weigering hier een fout is en geen `null`.** Een pc die zegt "ik hoor bij een
  /// ander account" of "ik ben zelf niet ingelogd" heeft precies verteld wat er aan de hand is, en
  /// dat is de enige zin die de gebruiker verder helpt. Wie dat wegslikt tot `null` laat op het
  /// scherm "geen pc gevonden" staan terwijl de pc gevonden wérd en antwoordde. `null` betekent
  /// dus alleen: deze machine is geen kandidaat (oudere bouw, kent deze weg nog niet).
  ///
  /// **Sinds uitlevering B alleen nog versleuteld**, over 47822 met de pin van de pc: de inlogsleutel
  /// gaat nooit meer onversleuteld over de lijn. Is de [pin] nog niet bekend (een nieuw toestel), dan
  /// is dit de eerste kennismaking: alleen op een adres thuis of via Tailscale, en als je account een
  /// pin noemt ([verwachtePin]) alleen een pc met precies die. Het antwoord bevat beide sleutels en de
  /// pin. Een pc van vóór uitlevering B luistert niet op 47822: dan een duidelijke zin in plaats van
  /// een stille terugval naar HTTP.
  static Future<RemoteEndpoint?> pairMetAccount(
    Uri baseUrl, {
    required String idToken,
    required String deviceId,
    required String deviceName,
    required String platform,
    String pin = '',
    String verwachtePin = '',
    int tlsPoort = kTlsPoort,
    http.Client? client,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    // Eerste kennismaking alleen thuis of via Tailscale; van buiten koppelen komt pas met uitlevering C.
    final ip = InternetAddress.tryParse(baseUrl.host);
    if (pin.isEmpty && ip != null && toestelWeg(ip) == 'buiten') return null;
    var gezien = '';
    final c = client ?? pinClient(pin: pin, verwacht: verwachtePin, gezien: (p) => gezien = p);
    final tlsBasis = baseUrl.replace(scheme: 'https', port: tlsPoort);
    try {
      final res = await c
          .post(
            tlsBasis.replace(path: '/pair-cloud'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'idToken': idToken,
              'deviceId': deviceId,
              'deviceName': deviceName,
              'platform': platform,
            }),
          )
          .timeout(timeout);

      // Een pc van vóór deze weg kent `/pair-cloud` niet. Geen fout, gewoon geen kandidaat.
      if (res.statusCode == 404) return null;

      if (res.statusCode != 200) {
        // De pc stuurt zijn eigen zin mee, in gewone taal. Die is beter dan alles wat we hier
        // kunnen verzinnen, want alleen de pc weet of hij zelf ingelogd is.
        String uitleg = '';
        try {
          final j = jsonDecode(res.body);
          if (j is Map) uitleg = (j['error'] ?? '').toString();
        } catch (_) {/* geen json terug */}
        throw RemoteException(
          uitleg.isEmpty ? 'De pc liet dit toestel niet toe (${res.statusCode}).' : uitleg,
          statusCode: res.statusCode,
        );
      }

      final j = jsonDecode(res.body);
      final tls = (j is Map ? j['tlsToken'] : null)?.toString() ?? '';
      return RemoteEndpoint(
        baseUrl: baseUrl,
        token: _sleutelUit(j),
        name: (j is Map ? j['name'] : null)?.toString(),
        pin: pin.isNotEmpty ? pin : gezien,
        tlsToken: tls,
        tlsPoort: tlsPoort,
      );
    } on RemoteException {
      rethrow;
    } on HandshakeException {
      // Een ander certificaat dan de pin (of je account) zegt. Geen terugval: wie hier zit, is niet je pc.
      throw const RemoteException('Op dit adres antwoordt een pc met een ander certificaat dan de jouwe. '
          'Klopt het adres? Is je pc opnieuw geïnstalleerd, koppel dan opnieuw met de zes cijfers.');
    } catch (_) {
      // Geen versleutelde ingang. Is het een pc van vóór uitlevering B (47820 antwoordt wel), zeg dat.
      final gewoon = baseUrl.scheme == 'https' ? baseUrl.replace(scheme: 'http', port: kHttpPoort) : baseUrl;
      final h = await health(gewoon, timeout: const Duration(seconds: 3));
      if (h != null) {
        throw RemoteException('${h.name.isEmpty ? 'Je pc' : h.name} heeft een oudere versie van DebridMusic. '
            'Werk de app op je pc bij: koppelen via je account gaat nu versleuteld.');
      }
      // Onbereikbaar, of iets anders dat op die poort luistert. Volgende machine.
      return null;
    } finally {
      if (client == null) c.close();
    }
  }

  /// De eenmalige ruil: de HTTP-sleutel van [huidig] voor een TLS-sleutel, over 47822 met de pin.
  /// Gooit een [RemoteException] met de statuscode als de pc nee zegt (409: al omgeruild).
  static Future<String> ruil(RemoteEndpoint huidig, {http.Client? client}) async {
    if (huidig.pin.isEmpty) throw const RemoteException('Nog geen pin van deze pc.');
    final c = client ?? pinClient(pin: huidig.pin);
    try {
      final res = await c
          .post(huidig.tlsBasis.replace(path: '/api/sleutel/ruil'),
              headers: {'Content-Type': 'application/json'}, body: jsonEncode({'sleutel': huidig.token}))
          .timeout(const Duration(seconds: 10));
      final j = res.body.isEmpty ? null : jsonDecode(res.body);
      if (res.statusCode != 200) {
        final uitleg = (j is Map ? j['error'] : null)?.toString() ?? '';
        throw RemoteException(uitleg.isEmpty ? 'De ruil mislukte (${res.statusCode}).' : uitleg, statusCode: res.statusCode);
      }
      final tls = (j is Map ? j['tlsToken'] : null)?.toString() ?? '';
      if (tls.isEmpty) throw const RemoteException('De pc gaf geen versleutelde sleutel terug.');
      return tls;
    } on RemoteException {
      rethrow;
    } catch (e) {
      throw RemoteException('Geen versleutelde verbinding met de pc: $e');
    } finally {
      if (client == null) c.close();
    }
  }
}

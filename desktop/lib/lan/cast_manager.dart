import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../warm_log.dart';
import 'catalog.dart';
import 'dtos.dart';
import 'net.dart';
import 'transcode.dart';
import 'upnp.dart';

/// The Shield running the DebridMusic TV app.
///
/// Not a UPnP renderer — it takes a plain POST and hands the URL to ExoPlayer, which is the whole
/// reason to send music there rather than to a speaker: bit-perfect FLAC out of the HDMI, with no
/// ceiling on sample rate.
class ShieldTarget {
  const ShieldTarget({required this.host, required this.name});

  final String host;
  final String name;

  /// 8124, not 8123 — the Debrid **Media** app already listens on 8123 on the same Shield.
  static const port = 8124;

  String get id => 'shield:$host';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'model': 'Android TV',
        'manufacturer': 'DebridMusic',
        'kind': 'shield',
        'maxSampleRate': 0,
      };
}

/// The subnets to sweep for a television, from every address this machine has.
///
/// De-duplicated: two addresses on one subnet is one subnet. A plain function so the rule can be
/// stated in a test — the bug this exists for raises nothing and logs nothing, it just returns an
/// empty list as confidently as a correct search would.
Set<String> sweepPrefixes(Iterable<String> addresses) =>
    {for (final a in addresses) a.split('.').take(3).join('.')};

/// Ask one host whether the music receiver is listening, and what it calls itself.
///
/// Null for anything that is not ours: a closed port, some other web server, or the Debrid **Media**
/// app — which lives on the same television and answers the same shape one port down. Offering that
/// as a speaker would start a video player when somebody picked a place to listen.
Future<String?> probeShield(String host, {int port = ShieldTarget.port}) async {
  final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 600);
  try {
    final request = await client.getUrl(Uri.parse('http://$host:$port/ping'));
    final response = await request.close().timeout(const Duration(milliseconds: 900));
    if (response.statusCode != 200) return null;
    final body = await response.transform(utf8.decoder).join();
    if (!body.contains('debridmusic')) return null;
    // The receiver says what the television calls itself. Use it — "Woonkamer" is what the speaker
    // list should read; an address is what you fall back to, not what you show.
    try {
      final name = (jsonDecode(body) as Map)['name'];
      if (name is String && name.trim().isNotEmpty) return name.trim();
    } catch (_) {/* not JSON we understand; the address still identifies it */}
    return 'Shield ($host)';
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Is de MUZIEK een nummer opgeschoven, of alleen de boekhouding van de speaker?
///
/// Een losse functie omdat dit de regel is waar het casten twee keer op stukliep, en een regel die je in
/// een test kunt uitschrijven is een regel die je kunt controleren. Hij wordt pas gesteld als de speaker
/// de volgende-URL al in TrackURI meldt; de vraag hier is of dat ergens op slaat.
///
/// [top] is de hoogste positie die op het huidige nummer gezien is, [positie] wat de speaker nu meldt,
/// [gespeeld] hoe lang geleden dit nummer geopend werd, [lengte] hoe lang het duurt (null = onbekend).
///
/// Twee wegen, want niet elke speaker meldt hetzelfde:
///
/// * **De positie viel terug.** Het echte bewijs. Een speaker die aan een nieuw nummer begint telt weer
///   vanaf nul; zolang zijn klok dóórloopt speelt hetzelfde nummer nog, wat hij verder ook beweert.
/// * **De klok van hier.** Alleen voor speakers die geen bruikbare positie geven. Zwakker -- pauzeren
///   telt gewoon door -- maar het is dan de enige weg die nog open staat.
///
/// [terugval] staat ruim boven het geruis van een embedded klok en ruim onder de lengte van zelfs een kort
/// nummer. Ruim mag: bij de valse melding is de terugval niet klein maar negatief, want de positie stijgt.
({bool ja, String reden}) muziekIsGewisseld({
  required Duration top,
  required Duration gespeeld,
  Duration? positie,
  Duration? lengte,
  Duration terugval = const Duration(seconds: 10),
  Duration speling = const Duration(seconds: 15),
}) {
  // "Meldt deze speaker een positie?" is niet hetzelfde als "staat de positie hoog?". Op die twee door
  // elkaar te halen ging een eerdere versie hiervan alsnog de mist in: vlak na het begin van een nummer
  // staat de klok laag, en dan zou de klokweg het overnemen en meteen ja zeggen.
  if (positie != null && !(positie == Duration.zero && top == Duration.zero)) {
    if (top >= positie + terugval) {
      return (ja: true, reden: 'positie viel terug ${top.inSeconds}s → ${positie.inSeconds}s');
    }
    return (ja: false, reden: 'positie loopt door (top ${top.inSeconds}s, nu ${positie.inSeconds}s)');
  }
  if (lengte == null || lengte <= Duration.zero) {
    return (ja: true, reden: 'geen positie én geen lengte om aan te toetsen');
  }
  if (gespeeld >= lengte - speling) {
    return (ja: true, reden: 'geen positie, maar ${gespeeld.inSeconds}s van ${lengte.inSeconds}s om');
  }
  return (ja: false, reden: 'geen positie, pas ${gespeeld.inSeconds}s van ${lengte.inSeconds}s gespeeld');
}

/// Sends music to a speaker or the TV, and keeps it going.
///
/// The PC does this, not the iPad. Three reasons, in order of how much they matter:
/// the audio then goes straight from here to the speaker instead of being relayed by whatever
/// you happened to tap on; one implementation serves every device in the house; and it sidesteps
/// Apple's multicast entitlement, which SSDP discovery from an iPad would otherwise need.
class CastManager {
  CastManager({
    required this.catalog,
    required this.token,
    required this.port,
    UpnpControlPoint? upnp,
    Transcoder? transcoder,
    String? logPath,
  })  : _upnp = upnp ?? UpnpControlPoint(),
        _transcoder = transcoder ?? Transcoder(),
        _log = logPath == null ? null : WarmLog(logPath);

  final LanCatalog catalog;
  final UpnpControlPoint _upnp;
  final Transcoder _transcoder;
  final int port;
  String token;

  /// Waarom de speaker stil bleef, als hij stil bleef.
  ///
  /// Casten faalt bij uitstek zonder klap: de app zet een album op het scherm, de speaker haalt het
  /// bestand op, kan er niets mee, en zwijgt. Tot nu toe stond er in de hele castlaag geen enkel
  /// foutveld — de app KON het je dus niet vertellen, en het enige spoor was `cast.log` op de pc.
  /// Deze reis mee in de status, zodat de speakerkiezer het gewoon kan zeggen.
  String? probleem;

  /// Wat er tussen de app en de speaker gebeurt, in `cast.log` naast de andere staatbestanden.
  ///
  /// Bestaat omdat casten precies het soort fout heeft waar redeneren op stukloopt: alles speelt door,
  /// niets klapt, er verschijnt geen melding -- alleen staat er een ander album op het scherm dan er
  /// klinkt. Van buitenaf is dat één symptoom voor een handvol oorzaken, en een release-build slikt
  /// [debugPrint]. Twee reparaties zijn zo op een vermoeden gemikt.
  ///
  /// Wat hier in gaat is de WAARNEMING, niet het oordeel: welke URI de speaker meldt, waar de positie
  /// staat, wat de sessie denkt. Dan is achteraf te zien of een regel goed besliste op slechte feiten of
  /// andersom.
  final WarmLog? _log;

  Map<String, Renderer> _renderers = {};
  List<ShieldTarget> _shields = [];

  _Session? _session;
  Timer? _advance;

  /// Every place the music can go, this device excluded.
  Future<List<Map<String, dynamic>>> devices({bool refresh = true}) async {
    if (refresh || _renderers.isEmpty) {
      final found = await _upnp.discover();
      _renderers = {for (final r in found) r.id: r};
      _shields = await _findShields();
    }
    return [
      for (final r in _renderers.values) r.toJson(),
      for (final s in _shields) s.toJson(),
    ];
  }

  /// Ask the LAN whether a Shield running the TV app is listening.
  ///
  /// A direct probe of the /24 rather than mDNS: the Shield's receiver is a bare socket with no
  /// service advertisement, and on a home network 254 parallel pings with a short timeout finish
  /// in under a second.
  ///
  /// EVERY /24 this machine is on, not just the first. A PC with a Hyper-V switch, a VPN adapter or
  /// two network cards has several, and [primaryLanAddress] can only guess which one the television
  /// is on — guess wrong and the sweep runs to completion against a subnet with nothing in it, then
  /// reports no Shield with as much confidence as if it had looked in the right place.
  Future<List<ShieldTarget>> _findShields() async {
    final own = await lanAddresses();
    if (own.isEmpty) return [];
    final mine = own.toSet();
    final prefixes = sweepPrefixes(own);
    final found = <ShieldTarget>[];
    await Future.wait([
      for (final prefix in prefixes)
        for (var i = 1; i < 255; i++)
          () async {
            final host = '$prefix.$i';
            if (mine.contains(host)) return;
            final name = await _pingShield(host);
            if (name != null) found.add(ShieldTarget(host: host, name: name));
          }()
    ]);
    found.sort((a, b) => a.host.compareTo(b.host));
    return found;
  }

  Future<String?> _pingShield(String host) => probeShield(host);

  // ── Playing ──────────────────────────────────────────────────────────────

  /// Start [trackIds] on [deviceId] at [index].
  Future<void> play(String deviceId, List<String> trackIds, int index) async {
    if (trackIds.isEmpty) throw ArgumentError('nothing to play');
    _advance?.cancel();

    final shield = _shields.where((s) => s.id == deviceId).firstOrNull;
    if (shield != null) {
      await _playOnShield(shield, trackIds, index);
      return;
    }

    final renderer = await _renderer(deviceId);
    _log?.line('── start op ${renderer.name}: ${trackIds.length} nummers, vanaf $index ──');
    _session = _Session(renderer: renderer, queue: trackIds, index: index.clamp(0, trackIds.length - 1));
    await _openCurrent();
    // The renderer plays one track; something has to notice it ended and send the next.
    _advance = Timer.periodic(const Duration(seconds: 5), (_) => _maybeAdvance());
  }

  /// The Shield gets the whole queue at once — it has a real player and can manage its own gaps.
  Future<void> _playOnShield(ShieldTarget shield, List<String> trackIds, int index) async {
    final base = await lanAddressFor(shield.host);
    if (base == null) throw StateError('no route to ${shield.host}');
    final tracks = [for (final id in trackIds) catalog.track(id)];
    final urls = <String>[];
    for (var i = 0; i < trackIds.length; i++) {
      final track = tracks[i];
      if (track == null) continue;
      urls.add('http://$base:$port/stream/${trackIds[i]}.${track.ext}?token=$token');
    }
    if (urls.isEmpty) throw StateError('none of those tracks are in the library');

    final first = tracks[index.clamp(0, tracks.length - 1)];
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('http://${shield.host}:${ShieldTarget.port}/play'));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      // Same reason as the SOAP calls: the Shield's receiver reads Content-Length to know how
      // much body to expect, and a chunked request would arrive as an empty one.
      final payload = utf8.encode(jsonEncode({
        'streamUrls': urls,
        'index': index.clamp(0, urls.length - 1),
        'title': first?.title ?? '',
        'artist': first?.artist ?? '',
        'album': first?.album ?? '',
      }));
      request.contentLength = payload.length;
      request.add(payload);
      final response = await request.close().timeout(const Duration(seconds: 8));
      await response.drain<void>();
      if (response.statusCode != 200) {
        throw StateError('de Shield weigerde het (HTTP ${response.statusCode})');
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _openCurrent() async {
    final session = _session;
    if (session == null) return;
    final id = session.queue.elementAtOrNull(session.index);
    final track = id == null ? null : catalog.track(id);
    if (id == null || track == null) return;

    // Stamped BEFORE the SOAP calls, not after. Opening a track is three round trips of up to eight
    // seconds each, and until this line ran the timestamp still described the PREVIOUS track — so
    // the five-second tick arriving mid-open found the grace period long expired, asked a renderer
    // that had not started yet, was told STOPPED, and advanced again. The track being opened was
    // skipped without a sound. It is set again after the calls land, so the grace period is measured
    // from when the speaker actually got the track.
    session.startedAt = DateTime.now();

    final url = await _streamUrlFor(id, track.ext, session.renderer, track.sampleRate);
    await _upnp.playUrl(
      session.renderer,
      url,
      title: track.title,
      artist: track.artist,
      album: track.album,
      mime: mimeForExt(track.ext),
      artUrl: await _artUrlFor(id, session.renderer),
      duration: track.duration,
    );
    session.startedAt = DateTime.now();
    session.currentUrl = url;
    session.nextUrl = null;
    // Een nieuw nummer begint weer bij nul, dus het ijkpunt voor de terugval ook. Zou dit blijven staan,
    // dan zou de vorige lengte de eerstvolgende meting al als "teruggevallen" laten tellen.
    session.hoogstePositie = Duration.zero;
    _log?.line('open idx=${session.index}/${session.queue.length} ${_naam(id)}  (${_idVanUrl(url)})');

    // Hand the renderer the next one straight away, so the gap between two songs is the
    // speaker's own and not a round trip through here.
    await _armNext(session);
  }

  /// Geef de speaker alvast het nummer ná het huidige.
  ///
  /// De URL wordt bewaard, want dit is precies wat de speaker straks zelf gaat spelen zonder het te
  /// melden. Hem terugzien in TrackURI is NODIG om de overgang te zien, maar niet genoeg: een Sonos
  /// meldt hem al zodra hij hem ontvangt. Wat de overgang bewijst staat in [_echtGewisseld].
  Future<void> _armNext(_Session session) async {
    final nextId = session.queue.elementAtOrNull(session.index + 1);
    final nextTrack = nextId == null ? null : catalog.track(nextId);
    if (nextId == null || nextTrack == null) return;
    final nextUrl = await _streamUrlFor(nextId, nextTrack.ext, session.renderer, nextTrack.sampleRate);
    await _upnp.setNextUrl(
      session.renderer,
      nextUrl,
      title: nextTrack.title,
      artist: nextTrack.artist,
      album: nextTrack.album,
      mime: mimeForExt(nextTrack.ext),
      duration: nextTrack.duration,
    );
    session.nextUrl = nextUrl;
    _log?.line('    volgende meegegeven: ${_naam(nextId)}  (${_idVanUrl(nextUrl)})');
  }

  /// Een andere volgorde voor wat er nog komt, zonder het lopende nummer aan te raken.
  ///
  /// Hiervoor bestond alleen [play], en die opent het huidige nummer opnieuw -- dus druk je tijdens het
  /// casten op shuffle, dan zou het liedje van voren af aan beginnen. Zonder deze weg deed de app iets
  /// ergers: ze schudde haar EIGEN lijst en liet die van de speaker staan. De index die de speaker
  /// terugmeldde wees daarna in twee verschillende lijsten, en dan toont het scherm een ander album dan
  /// er klinkt -- zonder dat er iets hapert of een melding verschijnt.
  ///
  /// De aanroeper zet het spelende nummer op [index]; dat is wat de volgorde hier en daar gelijk houdt.
  Future<void> requeue(String deviceId, List<String> trackIds, int index) async {
    final session = _session;
    if (session == null || session.renderer.id != deviceId || trackIds.isEmpty) return;
    session.queue = List.of(trackIds);
    // Waar staat het nummer dat NU klinkt in de nieuwe lijst? Dat is de index -- ongeacht wat de
    // aanroeper meestuurt. De speaker speelt door, dus de boekhouding hoort zich naar het geluid te
    // voegen en niet andersom. Zo kan één verkeerd gerekende index aan de andere kant hier geen
    // scheefstand meer veroorzaken, en als hij tóch afwijkt staat dat in het logboek.
    final huidig = _idVanUrl(session.currentUrl);
    final plek = huidig == null ? -1 : trackIds.indexOf(huidig);
    session.index = plek >= 0 ? plek : index.clamp(0, trackIds.length - 1);
    session.nextUrl = null;
    _log?.line('wachtrij vervangen: ${trackIds.length} nummers, nu op ${session.index} '
        '${_naam(session.queue.elementAtOrNull(session.index))}'
        '${plek >= 0 && plek != index ? '  (aanroeper zei $index)' : ''}'
        '${plek < 0 ? '  (het spelende nummer zit niet in de nieuwe lijst)' : ''}');
    await _armNext(session);
  }

  /// Is de speaker zelf doorgeschoven naar het nummer dat we hem alvast meegaven?
  ///
  /// De naadloze overgang van SetNextAVTransportURI is onzichtbaar in de transportstatus: PLAYING
  /// blijft PLAYING. Wat wél verandert is TrackURI. Zodra die gelijk is aan de URL die we als "volgende"
  /// hebben doorgegeven, weten we dat de speaker een nummer verder is en verhogen we de index -- en
  /// geven we meteen het nummer daarna mee, zodat de keten niet na twee liedjes ophoudt.
  ///
  /// Dit vervangt de STOPPED-weg niet: een speaker die de volgende-URL niet ondersteunt stopt wél, en
  /// dan is [_maybeAdvance] nog steeds wat de wachtrij doorzet.
  Future<bool> _followedRenderer(String? trackUri, Duration? positie) async {
    final session = _session;
    if (session == null) return false;
    // Eerst onthouden, en met de waarde van VOOR deze meting verder rekenen -- anders is de terugval
    // die we zoeken al weggeschreven voordat we hem konden zien.
    final top = session.hoogstePositie;
    if (positie != null && positie > top) session.hoogstePositie = positie;
    if (trackUri == null) return false;
    // Niet binnen de genadeperiode na het openen van een nummer, en dat is niet overdreven
    // voorzichtigheid maar een gemeten fout. Sonos neemt de "volgende"-URL op in zijn EIGEN wachtrij en
    // meldt hem daarna al in TrackURI, terwijl hij nog aan het huidige nummer bezig is. Eén druk op
    // volgende gaf daardoor:
    //
    //     16:09:02  index=4  pos=1s
    //     16:09:04  index=5  pos=1s
    //
    // De positie die dóórloopt in plaats van terug naar nul te springen verraadt het: er wisselde geen
    // nummer, alleen de boekhouding schoof op. Een ECHTE doorschuiving komt altijd aan het eind van een
    // nummer en dus ruim na deze periode, dus dit kost de goede kant niets.
    if (DateTime.now().difference(session.startedAt) < _startGrace) return false;
    final volgende = session.nextUrl;
    if (volgende == null || trackUri != volgende) return false;
    if (session.index + 1 >= session.queue.length) return false;
    if (!_echtGewisseld(session, positie, top)) return false;
    _log?.line('volgt speaker: ${session.index} → ${session.index + 1}  '
        '${_naam(session.queue.elementAtOrNull(session.index + 1))}');
    session.index++;
    session.startedAt = DateTime.now();
    session.currentUrl = volgende;
    session.nextUrl = null;
    session.hoogstePositie = Duration.zero;
    // Alleen de VOLGENDE doorgeven, niet opnieuw openen: de speaker speelt dit nummer al, en er
    // opnieuw een URL op zetten zou hem vanaf nul laten beginnen.
    try {
      await _armNext(session);
    } catch (_) {/* dan stopt de speaker na dit nummer en pakt _maybeAdvance het op */}
    return true;
  }

  /// Is de MUZIEK gewisseld, of alleen de boekhouding van de speaker?
  ///
  /// Dit is de vraag waar het op stukliep. Een Sonos zet de volgende-URL in zijn eigen wachtrij en meldt
  /// hem daarna in TrackURI terwijl het huidige nummer gewoon doorspeelt. "TrackURI is de volgende" was
  /// dus geen bewijs van een overgang maar van een ONTVANGST, en die komt seconden na de start. De
  /// genadeperiode van acht seconden stelde dat alleen maar uit: daarna klopte de voorwaarde nog steeds,
  /// de index schoof op, de app gaf meteen het nummer dáárna mee -- en acht seconden later gebeurde
  /// hetzelfde. Zo wandelde het scherm door de wachtrij terwijl er één nummer speelde. Dat is wat "ik
  /// hoor de Backstreet Boys maar zie Michael Jackson" was.
  ///
  /// Wat een overgang wél verraadt is de positie: die valt terug naar nul. Zolang de klok van de speaker
  /// dóórloopt, speelt hetzelfde nummer nog -- ongeacht welke URI hij noemt.
  bool _echtGewisseld(_Session session, Duration? positie, Duration top) {
    final oordeel = muziekIsGewisseld(
      top: top,
      positie: positie,
      gespeeld: DateTime.now().difference(session.startedAt),
      lengte: catalog.track(session.queue.elementAtOrNull(session.index) ?? '')?.duration,
    );
    if (!oordeel.ja) {
      _zie('nog niet gewisseld: ${oordeel.reden} -- terwijl de speaker de volgende URI al meldt');
      return false;
    }
    _log?.line('wissel gezien: ${oordeel.reden}');
    return true;
  }

  static String _sec(Duration d) => '${d.inSeconds}s';

  /// Hoe een nummer in het logboek heet.
  String _naam(String? id) {
    if (id == null) return '(niets)';
    final t = catalog.track(id);
    return t == null ? id : '${t.artist} - ${t.title}';
  }

  /// De id uit een stream-URL, want de hele URL is drie regels en zegt niet meer.
  String? _idVanUrl(String? url) {
    if (url == null) return null;
    final m = RegExp(r'/stream/([^/.?]+)').firstMatch(url);
    return m?.group(1);
  }

  String _laatsteRegel = '';
  DateTime _laatstGezien = DateTime.fromMillisecondsSinceEpoch(0);

  /// Een waarneming die zichzelf elke twee seconden herhaalt, hooguit twee keer per minuut opschrijven.
  ///
  /// De cijfers eruit gehaald om te vergelijken: "top 12s, nu 12s" en "top 14s, nu 14s" zijn dezelfde
  /// waarneming en horen niet allebei in het logboek. Een gebeurtenis -- een wissel, een opdracht, een
  /// nieuw nummer -- gaat langs deze rem heen, want die is per definitie nieuw.
  void _zie(String regel) {
    final kern = regel.replaceAll(RegExp(r'\d+'), '#');
    final nu = DateTime.now();
    if (kern == _laatsteRegel && nu.difference(_laatstGezien) < const Duration(seconds: 30)) return;
    _laatsteRegel = kern;
    _laatstGezien = nu;
    _log?.line(regel);
  }

  /// The URL to hand the speaker — converted first when the speaker cannot take the original.
  Future<String> _streamUrlFor(String id, String ext, Renderer renderer, int sampleRate) async {
    final base = await lanAddressFor(renderer.host);
    final ceiling = renderer.maxSampleRate;
    // Sonos stops at 48 kHz and SKIPS anything higher — no error, no sound, just nothing. Send
    // it through the converter rather than let a hi-res album play as silence.
    if (ceiling > 0 && sampleRate > ceiling) {
      if (_transcoder.available) {
        probleem = null;
        return 'http://$base:$port/stream/$id.flac?token=$token&maxRate=$ceiling';
      }
      // Hier ging het mis en zei niemand iets. Een Sonos slaat alles boven 48 kHz over zonder
      // foutmelding, dus zonder omzetter stuurden we een bestand waarvan we wisten dat het stil
      // zou blijven. Nu wordt het gezegd — dit is de enige plek die beide helften kent: hoe hoog
      // de plaat is, en dat er niets is om hem mee te verlagen.
      probleem = 'Deze speaker gaat tot ${ceiling ~/ 1000} kHz en dit nummer is '
          '${(sampleRate / 1000).round()} kHz. Zonder ffmpeg op de pc kan ik het niet omzetten, '
          'en dan blijft de speaker stil.';
      _log?.line('GEEN OMZETTER: ${sampleRate}Hz > ${ceiling}Hz en ffmpeg ontbreekt — $id');
    } else {
      probleem = null;
    }
    return 'http://$base:$port/stream/$id.$ext?token=$token';
  }

  Future<String?> _artUrlFor(String id, Renderer renderer) async {
    final track = catalog.track(id);
    if (track == null) return null;
    final snapshot = catalog.snapshot();
    final dto = snapshot.catalog.tracks.where((t) => t.id == id).firstOrNull;
    if (dto?.artworkRef == null) return null;
    final base = await lanAddressFor(renderer.host);
    return 'http://$base:$port/art/${dto!.artworkRef}?token=$token';
  }

  /// True while an advance is in flight, so the five-second tick cannot start a second one.
  ///
  /// Every step of an advance is slow — one state query plus three more round trips to open the next
  /// track, each allowed eight seconds — and the timer kept firing straight through it. Two overlapping
  /// advances each move the index, so the queue walks forward faster than the speaker plays it.
  /// Hoe lang een net geopend nummer met rust wordt gelaten voordat de speaker geloofd wordt.
  ///
  /// Eén constante voor beide vragen die erop leunen -- "is hij gestopt?" en "is hij doorgeschoven?" --
  /// want ze beschermen tegen hetzelfde: een renderer die de eerste seconden nog niets zinnigs meldt.
  /// Een Sonos zegt STOPPED terwijl hij de eerste bytes ophaalt, en meldt de volgende-URL al in
  /// TrackURI terwijl hij nog aan het huidige nummer bezig is. Twee keer uitgeschreven zouden ze
  /// uiteen gaan lopen.
  static const _startGrace = Duration(seconds: 8);

  bool _advancing = false;

  /// Move to the next track once the speaker says it has finished.
  Future<void> _maybeAdvance() async {
    if (_advancing) return;
    final session = _session;
    if (session == null) return;
    // Give the renderer a moment after a start before believing "STOPPED" — a Sonos reports
    // exactly that for a second or two while it fetches the first bytes.
    if (DateTime.now().difference(session.startedAt) < _startGrace) return;

    _advancing = true;
    try {
      // Eerst: is de speaker zelf al doorgeschoven? Dan is er niets te doen behalve bijhouden waar hij
      // is. Deze vraag gaat vóór de transportstatus, want in dat geval staat die nog op PLAYING en zou
      // de rest van deze functie niets doen terwijl de index achterloopt.
      final pos = await _upnp.positionInfo(session.renderer).catchError((_) => null);
      if (await _followedRenderer(pos?.trackUri, pos?.position)) return;

      final state = await _upnp.transportState(session.renderer);
      _zie('kijk: ${state?.state ?? '?'} pos=${_sec(pos?.position ?? Duration.zero)} '
          'top=${_sec(session.hoogstePositie)} idx=${session.index}/${session.queue.length} '
          'uri=${_idVanUrl(pos?.trackUri) ?? '-'} nu=${_idVanUrl(session.currentUrl) ?? '-'} '
          'volgende=${_idVanUrl(session.nextUrl) ?? '-'}');
      if (state == null || !state.isStopped) return;
      if (session.index + 1 >= session.queue.length) {
        _advance?.cancel();
        _session = null;
        return;
      }
      session.index++;
      try {
        await _openCurrent();
      } catch (e) {
        // The index had already moved, and the timer throws the error away — so a renderer that
        // refuses the track (a busy Sonos answers "Transition not available" with an HTTP 500) lost
        // that song silently and the next tick took the one after it. Put the queue back where it
        // was and let the next tick try the same track again.
        session.index--;
        session.startedAt = DateTime.now();
        debugPrint('cast: kon ${session.queue.elementAtOrNull(session.index + 1)} niet openen: $e');
      }
    } finally {
      _advancing = false;
    }
  }

  Future<void> control(String deviceId, String action, {int? value}) async {
    final shield = _shields.where((s) => s.id == deviceId).firstOrNull;
    if (shield != null) {
      if (action == 'stop') await _postShield(shield, '/stop');
      return;
    }
    final renderer = await _renderer(deviceId);
    _log?.line('opdracht $action${value == null ? '' : ' $value'}  '
        '(idx=${_session?.index ?? -1})');
    switch (action) {
      case 'play':
        await _upnp.play(renderer);
      case 'pause':
        await _upnp.pause(renderer);
      case 'stop':
        _advance?.cancel();
        _session = null;
        await _upnp.stop(renderer);
      case 'next':
        final session = _session;
        if (session != null && session.index + 1 < session.queue.length) {
          session.index++;
          await _openCurrent();
        }
      case 'previous':
        final session = _session;
        if (session != null && session.index > 0) {
          session.index--;
          await _openCurrent();
        }
      case 'volume':
        await _upnp.setVolume(renderer, value ?? 50);
      case 'seek':
        // Seconds on the wire rather than a formatted time: the phone has a slider, not a clock,
        // and the H:MM:SS the renderer wants is upnp.dart's business.
        //
        // Het ijkpunt voor de terugval verzetten, want anders is achteruit slepen niet te onderscheiden
        // van een nummer dat afliep: allebei valt de positie terug. Zo verzet slepen de meetlat mee.
        _session?.hoogstePositie = Duration(seconds: value ?? 0);
        await _upnp.seek(renderer, Duration(seconds: value ?? 0));
      default:
        throw ArgumentError('unknown action: $action');
    }
  }

  /// What the speaker is doing, for a device that is holding the remote.
  ///
  /// Everything here is asked of the SPEAKER. A phone that is only steering does not decode the
  /// audio and cannot know the position; the alternative was a bar that crawled along on a guess,
  /// which is a lie you can sit and watch.
  ///
  /// Every field is optional on purpose. A renderer that answers some questions and not others is
  /// ordinary, and "no volume" must not cost you the play button.
  /// [withVolume] because this is polled while a bar moves on screen, and an embedded UPnP stack is
  /// not a web server. Volume almost never changes on its own, so asking for it every two seconds
  /// is a third more traffic to the speaker for an answer that is nearly always the same one.
  Future<Map<String, dynamic>> status(String deviceId, {bool withVolume = false}) async {
    final out = <String, dynamic>{'casting': false, if (probleem != null) 'probleem': probleem};
    // A Shield runs our own receiver and reports through the shared state, not through UPnP.
    if (_shields.any((s) => s.id == deviceId)) return out;

    final Renderer renderer;
    try {
      renderer = await _renderer(deviceId);
    } catch (_) {
      return out; // gone from the network; the caller shows its own last known state
    }
    final session = _session;
    out['casting'] = session != null && session.renderer.id == renderer.id;
    // Alle drie tegelijk gestart en pas daarna afgewacht: drie ronden naar een embedded stack, één na
    // de ander, is bijna een seconde — en dit wordt gepolst terwijl iemand naar een voortgangsbalk kijkt.
    //
    // Bewust drie losse futures en geen Future.wait met een lijst. Die geeft een List<Object?> terug, en
    // dan is elk element een `as`-cast die de compiler niet kan nakijken. Precies dat ging mis toen
    // positionInfo er een veld bij kreeg: de cast bleef op het oude record staan, de analyzer zag niets,
    // en élke statusvraag over een échte speaker klapte met een 500. De app las dat als "niet
    // bereikbaar", en dan vallen volgende en vorige dood terwijl de muziek doorloopt. Zo geschreven
    // klaagt de compiler de volgende keer wél.
    final posF = _upnp.positionInfo(renderer).catchError((_) => null);
    final stateF = _upnp.transportState(renderer).catchError((_) => null);
    final volF = withVolume ? _upnp.getVolume(renderer).catchError((_) => null) : null;
    final pos = await posF;
    final state = await stateF;
    final volume = volF == null ? null : await volF;
    if (pos != null) {
      // Ontbreekt de klok, dan blijft het veld weg in plaats van nul te worden -- de telefoon leest een
      // ontbrekend veld als "onbekend" en een nul als "terug bij het begin".
      final p = pos.position;
      if (p != null) out['positionMs'] = p.inMilliseconds;
      out['durationMs'] = pos.duration.inMilliseconds;
    }
    if (state != null) out['playing'] = state.isPlaying;
    if (volume != null) out['volume'] = volume;

    // Ook hier kijken of de speaker zelf is doorgeschoven, en niet alleen in de tijdklok van vijf
    // seconden. De positie is net al opgehaald, dus dit kost geen ronde extra -- en een telefoon polst
    // elke twee seconden. Gemeten op de KEF: de positie klapte van 209 naar 1 seconde terwijl de index
    // nog op het vorige nummer stond; die achterstand is nu twee tellen in plaats van vijf.
    //
    // Het antwoord wordt NA deze vraag samengesteld: eerst bijwerken, dan vertellen. Andersom zou deze
    // poll nog de oude index melden en pas de volgende de nieuwe.
    await _followGuarded(pos?.trackUri, pos?.position);
    final nu = _session;
    if (nu != null && nu.renderer.id == renderer.id) {
      out['index'] = nu.index;
      out['queueLength'] = nu.queue.length;
      final tid = nu.queue.elementAtOrNull(nu.index);
      out['trackId'] = tid;

      // Wat de speaker niet weet, weet de bibliotheek wel.
      //
      // Een Sonos geeft geen tracklengte terug -- TrackDuration blijft leeg of nul -- en zonder lengte
      // heeft de voortgangsbalk geen eindpunt en valt er niet in te slepen. Gemeten naast elkaar: de
      // KEF meldt hem wel, de Move niet. Dat is geen fout van de app maar wel iets wat de app kan
      // oplossen, want dit is een nummer van deze pc en zijn lengte staat in de catalogus.
      //
      // Alleen INVULLEN wat ontbreekt, nooit overschrijven. Wat de speaker zelf zegt gaat over het
      // bestand zoals hij het ontvangt, en dat kan korter zijn dan het origineel: een hi-res album gaat
      // voor een Sonos door de omzetter heen.
      if (((out['durationMs'] as int?) ?? 0) <= 0) {
        final lengte = tid == null ? null : catalog.track(tid)?.duration;
        if (lengte != null && lengte > Duration.zero) out['durationMs'] = lengte.inMilliseconds;
      }
    }
    return out;
  }

  /// [_followedRenderer] met hetzelfde slot als de tijdklok ervoor.
  ///
  /// Nodig omdat de status door meerdere toestellen tegelijk gepolst wordt: twee overlappende
  /// doorschuivingen verhogen allebei de index en dan loopt de wachtrij sneller dan de speaker speelt --
  /// exact de fout die de tijdklok eerder maakte en waarvoor [_advancing] bestaat.
  Future<void> _followGuarded(String? trackUri, Duration? positie) async {
    // Geen `trackUri == null` meer als afslag hierboven: de positie moet óók onthouden worden als de
    // speaker even geen URI meldt, anders mist de terugval straks zijn ijkpunt.
    if (_advancing) return;
    _advancing = true;
    try {
      await _followedRenderer(trackUri, positie);
    } catch (_) {/* een mislukte doorschuiving mag geen statusvraag laten klappen */} finally {
      _advancing = false;
    }
  }

  Future<void> _postShield(ShieldTarget shield, String path) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('http://${shield.host}:${ShieldTarget.port}$path'));
      final response = await request.close().timeout(const Duration(seconds: 5));
      await response.drain<void>();
    } catch (e) {
      debugPrint('shield $path failed: $e');
    } finally {
      client.close(force: true);
    }
  }

  Future<Renderer> _renderer(String id) async {
    final known = _renderers[id];
    if (known != null) return known;
    await devices();
    final found = _renderers[id];
    if (found == null) throw StateError('Die speaker is niet (meer) op het netwerk.');
    return found;
  }

  void dispose() {
    _advance?.cancel();
    _advance = null;
  }
}

class _Session {
  _Session({required this.renderer, required this.queue, required this.index});

  final Renderer renderer;

  /// Niet final: shuffle tijdens het casten geeft een andere volgorde voor wat er nog komt. Zie
  /// [CastManager.requeue].
  List<String> queue;
  int index;
  DateTime startedAt = DateTime.now();

  /// De URL's die deze speaker gekregen heeft voor het huidige en het volgende nummer.
  ///
  /// Nodig om te ZIEN dat de speaker zelf is doorgeschoven. De app geeft het volgende nummer alvast
  /// mee zodat er geen gat valt tussen twee liedjes, en dan gaat een Sonos van PLAYING naar PLAYING
  /// zonder ooit STOPPED te zeggen. Wie alleen op STOPPED let, loopt vanaf dat moment één nummer
  /// achter: de speaker speelt nummer 2, de app toont nummer 1, en "volgende" gaat naar het nummer dat
  /// al klinkt. Bij één album valt dat nauwelijks op, bij shuffle-all is elk nummer een ander album.
  String? currentUrl, nextUrl;

  /// De hoogste positie die op DIT nummer gezien is.
  ///
  /// Dit is wat een echte nummerwissel verraadt. Een speaker die van nummer wisselt begint opnieuw te
  /// tellen, dus de positie valt terug van bijna-de-hele-lengte naar nul. Zolang die terugval niet is
  /// gezien, klinkt hetzelfde nummer nog -- wat de speaker verder ook beweert.
  ///
  /// Het hoogste in plaats van het laatste, zodat één rare meting tussendoor niets kapotmaakt.
  Duration hoogstePositie = Duration.zero;
}

extension _ElementAtOrNull<E> on List<E> {
  E? elementAtOrNull(int index) => (index >= 0 && index < length) ? this[index] : null;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

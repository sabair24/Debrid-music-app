/// De doorgever op de telefoon: mpv praat gewone HTTP met 127.0.0.1, de doorgever praat versleuteld
/// en vastgepind met de pc.
///
/// Stap 6 van "verbinden zoals Roon ARC" (plan 14-10-2026). **Waarom er iets tussen moet.** mpv
/// (ffmpeg) kan het eigen certificaat van de pc niet vastpinnen, en zonder doorgever moest de sleutel
/// in het adres — waar hij in mpv's eigen meldingen en in logboeken belandt. Hier gaat de sleutel in
/// de kop, en alleen naar het certificaat van de eigen pc.
///
/// **Wat mpv nodig heeft om niet stil te vallen**, en wat dit dus altijd doet:
/// * `Accept-Ranges: bytes` en een exacte `Content-Length`/`Content-Range`, nooit chunked;
/// * bij een storing nooit een 5xx: de aanvraag van mpv aannemen en vasthouden (tot [wachtOpAdres])
///   tot de sessie weer een adres heeft, en dan gewoon antwoorden. Lukt dat niet, dan de verbinding
///   dicht zónder antwoord: ffmpeg probeert dan zelf opnieuw (`reconnect=1`, `kStroomHerstelOpties`
///   in player.dart), en een 5xx zou hij als "kapot" lezen;
/// * valt de pc midden in een nummer weg, of komen er [stilte] lang geen bytes terwijl mpv erop
///   wacht: de verbinding naar mpv dicht. mpv vraagt dan opnieuw vanaf waar hij was (Range);
/// * hervatten met `If-Range` op het merkteken van het eerste antwoord, en het totaal in
///   `Content-Range` moet gelijk blijven. Anders veranderde het nummer op de pc terwijl het speelde,
///   en dan liever stoppen dan twee bestanden aan elkaar plakken ([veranderd]).
///
/// Alleen op 127.0.0.1, een willekeurige poort, en een geheim per run vooraan in het pad: een andere
/// app op de telefoon of een webpagina die 127.0.0.1 probeert, komt er niet in. Alleen `/stream/` en
/// `/art/`.
///
/// [Doorgever] werkt in elke isolate; [DoorgeverIsolaat] draait hem in een eigen isolate, zodat het
/// pompen van bytes nooit met het tekenen van het scherm concurreert.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'certificaat.dart' show pinVan;

/// Waar de pc nu is: het versleutelde adres (`https://192.168.0.117:47822`), de TLS-sleutel en de pin.
class DoorgeverBron {
  const DoorgeverBron({required this.basis, required this.sleutel, required this.pin});
  final Uri basis;
  final String sleutel;
  final String pin;

  Map<String, String> naarBericht() => {'basis': '$basis', 'sleutel': sleutel, 'pin': pin};
  static DoorgeverBron? uitBericht(Object? m) => m is Map
      ? DoorgeverBron(basis: Uri.parse('${m['basis']}'), sleutel: '${m['sleutel']}', pin: '${m['pin']}')
      : null;
}

/// Het adres dat mpv krijgt voor [pcAdres] (een stroom of hoes van de pc, met of zonder sleutel in
/// het adres): zelfde pad en vraag, zonder `token`, op de doorgever.
Uri doorgeverAdres(Uri pcAdres, {required int poort, required String geheim}) {
  final vraag = {...pcAdres.queryParameters}..remove('token');
  return Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: poort,
    path: '/$geheim${pcAdres.path}',
    queryParameters: vraag.isEmpty ? null : vraag,
  );
}

class Doorgever {
  Doorgever({
    this.wachtOpAdres = const Duration(seconds: 20),
    this.stilte = const Duration(seconds: 4),
    this.opnieuw = const Duration(seconds: 1),
    this.wachtOpKop = const Duration(seconds: 30),
    this.log,
    this.storing,
    this.veranderd,
    this.geweigerd,
    String? geheim,
  }) : geheim = geheim ?? _maakGeheim();

  /// Hoe lang een aanvraag van mpv vastgehouden wordt terwijl de pc onbereikbaar is.
  final Duration wachtOpAdres;

  /// Zo lang geen bytes van de pc terwijl mpv erop wacht = de verbinding is dood.
  final Duration stilte;

  /// Hoe vaak het opnieuw geprobeerd wordt binnen [wachtOpAdres].
  final Duration opnieuw;

  /// Hoe lang de pc mag doen over zijn kop (een hi-res nummer omzetten kost seconden).
  final Duration wachtOpKop;

  /// Voor `verbinding.log`.
  final void Function(String regel)? log;

  /// De pc antwoordt niet: de sessie mag een nieuwe wedloop houden (en [zetBron] aanroepen).
  final void Function()? storing;

  /// Dit nummer veranderde op de pc terwijl het speelde (ander merkteken of ander totaal).
  final void Function(String pad)? veranderd;

  /// De pc weigert de sleutel (401).
  final void Function()? geweigerd;

  HttpServer? _server;
  DoorgeverBron? _bron;
  Completer<void> _nieuweBron = Completer<void>();
  late final HttpClient _client = HttpClient(context: SecurityContext(withTrustedRoots: false))
    ..connectionTimeout = const Duration(seconds: 4)
    ..idleTimeout = const Duration(seconds: 15)
    ..autoUncompress = false
    ..badCertificateCallback = (cert, host, port) {
      final pin = _bron?.pin ?? '';
      return pin.isNotEmpty && pinVan(cert.der) == pin;
    };

  /// Het geheim vooraan in elk pad. Per run nieuw; bij een herstart (iOS) hetzelfde, zodat de adressen
  /// die mpv al kreeg blijven werken.
  final String geheim;

  /// Het eerste antwoord per stroom: merkteken en totaal, om een hervatting tegen te controleren.
  final _eerste = <String, ({String? etag, int totaal})>{};

  int get poort => _server?.port ?? 0;
  bool get draait => _server != null;
  DoorgeverBron? get bron => _bron;

  /// Luisteren op 127.0.0.1. [poort] 0 = een vrije; een eerdere poort eerst (iOS na het hervatten:
  /// de adressen die mpv al kreeg blijven dan geldig), en is die bezet een vrije.
  Future<int> start({int poort = 0}) async {
    if (_server != null) return _server!.port;
    HttpServer s;
    try {
      s = await HttpServer.bind(InternetAddress.loopbackIPv4, poort);
    } on SocketException {
      if (poort == 0) rethrow;
      s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    }
    s.autoCompress = false;
    _server = s;
    s.listen((req) => unawaited(_handel(req).catchError((Object e) {
          _log('fout bij ${req.uri.path}: $e');
          try {
            req.response.close();
          } catch (_) {}
        })));
    _log('op 127.0.0.1:${s.port}');
    return s.port;
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }

  /// Waar de pc nu is, of null als hij weg is. Een aanvraag die wacht, gaat meteen verder.
  void zetBron(DoorgeverBron? bron) {
    final oud = _bron;
    _bron = bron;
    if (bron != null && (oud == null || oud.basis != bron.basis)) _log('pc via ${bron.basis.authority}');
    if (bron != null && !_nieuweBron.isCompleted) {
      _nieuweBron.complete();
    }
  }

  /// Het adres voor mpv bij een stroom of hoes van de pc. Zie [doorgeverAdres].
  Uri adresVoor(Uri pcAdres) => doorgeverAdres(pcAdres, poort: poort, geheim: geheim);

  void _log(String regel) => log?.call('doorgever: $regel');

  Future<void> _handel(HttpRequest req) async {
    final res = req.response;
    final delen = req.uri.pathSegments;
    if (delen.isEmpty || !_gelijk(delen.first, geheim)) {
      res.statusCode = HttpStatus.forbidden;
      return res.close();
    }
    final pad = '/${delen.skip(1).join('/')}';
    if (!pad.startsWith('/stream/') && !pad.startsWith('/art/')) {
      res.statusCode = HttpStatus.notFound;
      return res.close();
    }
    if (req.method != 'GET' && req.method != 'HEAD') {
      res.statusCode = HttpStatus.methodNotAllowed;
      return res.close();
    }
    final wat = req.uri.query.isEmpty ? pad : '$pad?${req.uri.query}';
    final range = req.headers.value(HttpHeaders.rangeHeader);
    final eerste = _eerste[wat];
    final klok = Stopwatch()..start();
    final tot = DateTime.now().add(wachtOpAdres);
    var pogingen = 0;
    HttpClientResponse? boven;
    DoorgeverBron? via;
    while (boven == null) {
      final bron = _bron;
      if (bron != null) {
        pogingen++;
        try {
          final r = await _client
              .openUrl(req.method, bron.basis.replace(path: pad, query: req.uri.query.isEmpty ? null : req.uri.query))
              .then((v) {
            v.headers
              ..set(HttpHeaders.authorizationHeader, 'Bearer ${bron.sleutel}')
              ..set(HttpHeaders.acceptEncodingHeader, 'identity');
            if (range != null) {
              v.headers.set(HttpHeaders.rangeHeader, range);
              if (eerste?.etag != null) v.headers.set(HttpHeaders.ifRangeHeader, eerste!.etag!);
            }
            return v.close();
          }).timeout(wachtOpKop);
          if (r.statusCode >= 500) {
            // Nooit een 5xx doorgeven: voor ffmpeg is dat "kapot". Opnieuw, zoals bij een storing.
            _log('pc gaf ${r.statusCode} op $pad (poging $pogingen) — opnieuw');
            await r.drain<void>().catchError((_) {});
          } else {
            boven = r;
            via = bron;
            break;
          }
        } catch (e) {
          _log('pc niet bereikbaar via ${bron.basis.authority} voor $pad (poging $pogingen): ${_kort(e)}');
          if (pogingen == 1 || pogingen % 5 == 0) storing?.call();
        }
      }
      final rest = tot.difference(DateTime.now());
      if (rest <= Duration.zero) {
        _log('${wachtOpAdres.inSeconds} s geen pc voor $pad${range == null ? '' : ' ($range)'} — dicht zonder antwoord');
        return _dichtZonderAntwoord(req);
      }
      if (_nieuweBron.isCompleted) _nieuweBron = Completer<void>();
      await Future.any([_nieuweBron.future, Future<void>.delayed(rest < opnieuw ? rest : opnieuw)]);
    }

    final status = boven.statusCode;
    if (status == HttpStatus.unauthorized) {
      _log('pc weigert de sleutel (401) op $pad');
      geweigerd?.call();
      await boven.drain<void>().catchError((_) {});
      res.statusCode = HttpStatus.unauthorized;
      return res.close();
    }

    // Hoe groot het hele bestand is, volgens dit antwoord.
    final bereik = boven.headers.value(HttpHeaders.contentRangeHeader);
    final totaal = status == HttpStatus.partialContent
        ? int.tryParse(bereik?.split('/').last ?? '') ?? -1
        : (status == HttpStatus.ok ? boven.contentLength : -1);
    final etag = boven.headers.value(HttpHeaders.etagHeader);
    if (status == HttpStatus.ok || status == HttpStatus.partialContent) {
      if (eerste != null &&
          ((range != null && status == HttpStatus.ok) ||
              totaal != eerste.totaal ||
              (eerste.etag != null && etag != eerste.etag))) {
        // Gevraagd om een stuk, en het hele bestand teruggekregen (If-Range klopte niet), of een ander
        // totaal: het nummer is op de pc veranderd. Niet aan elkaar plakken.
        _log('VERANDERD op de pc terwijl het speelde: $pad (totaal ${eerste.totaal} → $totaal)');
        await boven.drain<void>().catchError((_) {});
        veranderd?.call(pad);
        res.statusCode = HttpStatus.preconditionFailed;
        return res.close();
      }
      if (eerste == null && totaal >= 0) {
        _eerste[wat] = (etag: etag, totaal: totaal);
        while (_eerste.length > 64) {
          _eerste.remove(_eerste.keys.first);
        }
      }
    }

    // Een lengte weten we altijd, of we geven niets: chunked leest ffmpeg als een eindeloze stroom.
    if (boven.contentLength < 0 && req.method != 'HEAD' && status != HttpStatus.notModified) {
      _log('pc gaf geen lengte voor $pad — dicht zonder antwoord');
      await boven.drain<void>().catchError((_) {});
      return _dichtZonderAntwoord(req);
    }
    res.statusCode = status;
    for (final k in const [
      HttpHeaders.contentTypeHeader,
      HttpHeaders.contentRangeHeader,
      HttpHeaders.etagHeader,
      HttpHeaders.lastModifiedHeader,
      HttpHeaders.cacheControlHeader,
    ]) {
      final v = boven.headers.value(k);
      if (v != null) res.headers.set(k, v);
    }
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    res.headers.chunkedTransferEncoding = false;
    if (boven.contentLength >= 0) res.contentLength = boven.contentLength;
    if (range != null || pogingen > 1) {
      _log('${req.method} $pad${range == null ? '' : ' $range'} → $status via ${via?.basis.authority}'
          '${pogingen > 1 ? ' na $pogingen pogingen' : ''} (${klok.elapsedMilliseconds} ms)');
    }
    if (req.method == 'HEAD') {
      await boven.drain<void>().catchError((_) {});
      return res.close();
    }
    await _pomp(boven, res, pad);
  }

  /// Van de pc naar mpv, met een wacht op stilte. Zie de uitleg bovenaan.
  Future<void> _pomp(HttpClientResponse boven, HttpResponse naar, String pad) async {
    var laatst = DateTime.now();
    var wachtOpMpv = false;
    var geleverd = 0;
    var klaar = false;
    StreamSubscription<List<int>>? sub;
    late final StreamController<List<int>> c;
    c = StreamController<List<int>>(
      onPause: () {
        wachtOpMpv = true;
        sub?.pause();
      },
      onResume: () {
        wachtOpMpv = false;
        laatst = DateTime.now();
        sub?.resume();
      },
      onCancel: () => sub?.cancel(),
    );
    void breek(String waarom) {
      if (klaar) return;
      klaar = true;
      _log('$waarom na ${(geleverd / 1048576).toStringAsFixed(1)} MB van $pad — naar mpv dicht, mpv vraagt opnieuw');
      unawaited(sub?.cancel());
      // Gewoon sluiten is genoeg: dan kreeg mpv minder bytes dan de beloofde lengte, Dart sluit de
      // verbinding hard, en mpv vraagt opnieuw vanaf waar hij was (de mutatieproef bewees dat een
      // extra fout hier niets toevoegt).
      unawaited(c.close());
    }

    sub = boven.listen(
      (d) {
        laatst = DateTime.now();
        geleverd += d.length;
        c.add(d);
      },
      onError: (Object e) => breek('pc viel weg (${_kort(e)})'),
      onDone: () {
        if (klaar) return;
        klaar = true;
        unawaited(c.close());
      },
      cancelOnError: true,
    );
    final wacht = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!klaar && !wachtOpMpv && DateTime.now().difference(laatst) >= stilte) {
        breek('${stilte.inSeconds} s geen bytes van de pc');
      }
    });
    try {
      await naar.addStream(c.stream);
      await naar.close();
    } catch (_) {
      // Te weinig bytes voor de beloofde lengte: Dart sluit de verbinding hard, en zo hoort mpv het.
      try {
        await naar.close();
      } catch (_) {}
    } finally {
      wacht.cancel();
      unawaited(sub.cancel());
    }
  }

  static Future<void> _dichtZonderAntwoord(HttpRequest req) async {
    try {
      final s = await req.response.detachSocket(writeHeaders: false);
      s.destroy();
    } catch (_) {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  static String _kort(Object e) {
    final t = '$e'.replaceAll(RegExp(r'\s+'), ' ');
    return t.length > 120 ? '${t.substring(0, 120)}…' : t;
  }

  static bool _gelijk(String a, String b) {
    if (a.length != b.length) return false;
    var v = 0;
    for (var i = 0; i < a.length; i++) {
      v |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return v == 0;
  }

  static String _maakGeheim() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}

/// [Doorgever] in een eigen isolate. Zelfde gebruik; de meldingen komen terug op deze isolate.
class DoorgeverIsolaat {
  DoorgeverIsolaat({this.log, this.storing, this.veranderd, this.geweigerd});

  final void Function(String regel)? log;
  final void Function()? storing;
  final void Function(String pad)? veranderd;
  final void Function()? geweigerd;

  Isolate? _isolaat;
  SendPort? _naar;
  ReceivePort? _van;
  int _poort = 0;
  String _geheim = '';

  int get poort => _poort;
  String get geheim => _geheim;
  bool get draait => _naar != null;

  Future<int> start({int poort = 0, String? geheim}) async {
    if (_naar != null) return _poort;
    final van = ReceivePort();
    _van = van;
    final klaar = Completer<void>();
    van.listen((m) {
      if (m is! Map) return;
      switch (m['soort']) {
        case 'klaar':
          _naar = m['naar'] as SendPort;
          _poort = m['poort'] as int;
          _geheim = m['geheim'] as String;
          if (!klaar.isCompleted) klaar.complete();
        case 'fout':
          if (!klaar.isCompleted) klaar.completeError(StateError('${m['tekst']}'));
        case 'log':
          log?.call('${m['tekst']}');
        case 'storing':
          storing?.call();
        case 'veranderd':
          veranderd?.call('${m['pad']}');
        case 'geweigerd':
          geweigerd?.call();
      }
    });
    _isolaat = await Isolate.spawn(_hoofd, (van.sendPort, poort, geheim ?? ''), debugName: 'doorgever');
    await klaar.future;
    return _poort;
  }

  DoorgeverBron? _bron;

  void zetBron(DoorgeverBron? bron) {
    _bron = bron;
    _naar?.send({'soort': 'bron', 'bron': bron?.naarBericht()});
  }

  /// Na het hervatten van de app (iOS sluit soms de sockets van een app in de achtergrond): leeft de
  /// doorgever nog? Zo niet, opnieuw op dezelfde poort en met hetzelfde geheim, en met dezelfde pc.
  /// Geeft terug of er herstart werd.
  Future<bool> nakijken() async {
    if (_naar == null || _poort == 0) return false;
    try {
      final s = await Socket.connect(InternetAddress.loopbackIPv4, _poort, timeout: const Duration(seconds: 1));
      s.destroy();
      return false;
    } catch (_) {/* dood: hieronder opnieuw */}
    final poort = _poort;
    final geheim = _geheim;
    final bron = _bron;
    await stop();
    await start(poort: poort, geheim: geheim);
    zetBron(bron);
    log?.call('doorgever: na het hervatten opnieuw gestart op ${_poort == poort ? 'dezelfde' : 'een andere'} poort');
    return true;
  }

  Uri adresVoor(Uri pcAdres) => doorgeverAdres(pcAdres, poort: _poort, geheim: _geheim);

  /// Voor de toets: de luisterende socket weg terwijl de isolate leeft, zoals iOS dat kan doen met een
  /// app in de achtergrond.
  void doodVoorToets() => _naar?.send({'soort': 'sluitVoorToets'});

  Future<void> stop() async {
    _naar?.send({'soort': 'stop'});
    _naar = null;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _isolaat?.kill(priority: Isolate.beforeNextEvent);
    _isolaat = null;
    _van?.close();
    _van = null;
  }

  static Future<void> _hoofd((SendPort, int, String) beginwaarden) async {
    final (terug, poort, geheim) = beginwaarden;
    final d = Doorgever(
      geheim: geheim.isEmpty ? null : geheim,
      log: (r) => terug.send({'soort': 'log', 'tekst': r}),
      storing: () => terug.send({'soort': 'storing'}),
      veranderd: (p) => terug.send({'soort': 'veranderd', 'pad': p}),
      geweigerd: () => terug.send({'soort': 'geweigerd'}),
    );
    final hier = ReceivePort();
    try {
      final p = await d.start(poort: poort);
      terug.send({'soort': 'klaar', 'naar': hier.sendPort, 'poort': p, 'geheim': d.geheim});
    } catch (e) {
      terug.send({'soort': 'fout', 'tekst': '$e'});
      hier.close();
      return;
    }
    await for (final m in hier) {
      if (m is! Map) continue;
      if (m['soort'] == 'bron') d.zetBron(DoorgeverBron.uitBericht(m['bron']));
      if (m['soort'] == 'sluitVoorToets') await d.stop();
      if (m['soort'] == 'stop') {
        await d.stop();
        hier.close();
      }
    }
  }
}

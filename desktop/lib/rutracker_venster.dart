/// RuTracker-pagina's ophalen dóór het browservenster, want op een telefoon lukt het anders niet.
///
/// **Waarom dit moet bestaan.** In `rutracker.dart` staat een meting van 23-08-2026: met één en
/// hetzelfde geldige koekje, dezelfde koppen en hetzelfde IP-adres antwoordde RuTracker met `200` op
/// `curl` en met `403` op de HTTP-client van deze app. Het verschil zit niet in wat er verstuurd
/// wordt maar in hoe de TLS-verbinding zich voorstelt — de vingerafdruk van de ClientHello, en die
/// van Dart komt er niet door. Geen kop en geen koekje verandert daar iets aan.
///
/// Op Windows en op de Mac is dat opgelost doordat `curl` in het systeem zit. **Op een telefoon niet.**
/// Android levert geen `curl`, dus daar viel alles terug op precies de weg die 403 geeft. Dat is de
/// reden dat er op het toestel geen enkel resultaat binnenkwam terwijl de aanmelding gewoon klopte:
/// niet het koekje was stuk, de verbinding kwam er niet door.
///
/// Dit bestand haalt de pagina's daarom op ín het browservenster dat er toch al is. Dat venster is
/// een échte browser: zijn TLS-vingerafdruk klopt per definitie, hij heeft dezelfde koekjes als het
/// aanmeldvenster (die lade is voor de hele app één), en een Cloudflare-uitdaging lost hij zelf op
/// omdat hij JavaScript draait. Daarmee vernieuwt `cf_clearance` zichzelf ook, zonder dat jij iets
/// hoeft te doen.
///
/// **Eerlijk over wat dit is.** Er wordt niets omzeild wat jou niet toekomt: het is jouw account, en
/// dit is dezelfde pagina die je met de hand ook zou openen — alleen zonder dat je hem hoeft te zien.
///
/// **Waar het niet kan, verandert er niets.** Draagt het toestel geen webview, of lukt het ophalen
/// niet binnen de tijd, dan valt alles terug op de bestaande weg. Nooit slechter dan het was.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'rutracker_login.dart';

/// Het adres waar het onzichtbare venster op geparkeerd wordt.
///
/// Het moet op rutracker.org zelf staan: een `fetch` vanaf een andere herkomst wordt door de browser
/// tegengehouden, en de koekjes zouden niet meegaan.
const kRutrackerThuis = 'https://rutracker.org/forum/index.php';

/// Hoe lang er hoogstens op een bruikbaar venster gewacht wordt.
///
/// Ruim genoeg voor een Cloudflare-uitdaging (die duurt seconden), en kort genoeg om binnen de
/// twaalf seconden te blijven die de zoekverdeler elke bron gunt.
const kVensterGeduld = Duration(seconds: 20);

/// Hoe lang een zoekopdracht hoogstens op het opbouwen van het venster wacht.
///
/// **Waarom dit korter is dan [kVensterGeduld].** De zoekverdeler hakt elke bron na twaalf seconden
/// af en slikt de fout in stilte. Wachtte een zoekopdracht hier de volle twintig seconden, dan werd
/// RuTracker weggegooid vóórdat hij iets kon zeggen — en op het scherm stond "Geen torrents
/// gevonden.", zonder één woord over de reden. Wachten mag, maar niet langer dan er tijd is.
const kZoekGeduld = Duration(seconds: 7);

/// Hoeveel tekens er per keer uit het venster gehaald worden.
///
/// Niet in één keer: een zoekpagina is honderden kilobytes, en die gaan als één brok over de brug
/// tussen Dart en het toestel. Android breekt daarop af (`TransactionTooLargeException`) rond een
/// megabyte, en dat is precies de maat van een volle zoekpagina. In stukken is het simpelweg veilig.
const kStukGrootte = 200000;

/// De titel die Cloudflare toont terwijl hij je uitdaging nakijkt.
const _wachtTitel = 'just a moment';

/// Een onzichtbaar browservenster dat RuTracker-pagina's ophaalt.
///
/// Eén per app: het venster opbouwen kost seconden, en de koekjes zijn toch gedeeld.
class RutrackerVenster {
  RutrackerVenster._();

  static final RutrackerVenster instantie = RutrackerVenster._();

  HeadlessInAppWebView? _venster;
  InAppWebViewController? _web;
  Completer<bool>? _bezigMetOpenen;
  int _teller = 0;

  /// Wat er de laatste keer misging. Leeg als er niets misging.
  String laatsteFout = '';

  /// Is dit toestel er een waar dit kan? Zelfde grens als het aanmeldvenster.
  static bool get kan => rutrackerVensterKan;

  /// Eén zin over hoe het venster ervoor staat, voor op het scherm als het zoeken niets opleverde.
  ///
  /// Dit is het verschil tussen "RuTracker heeft niets" en "de app kwam er niet eens langs", en dat
  /// verschil hoort bij jou te liggen en niet in een logboek dat niemand leest.
  String get stand {
    if (!kan) return 'dit toestel heeft geen ingebouwd browservenster';
    if (_web == null) {
      return _bezigMetOpenen != null
          ? 'het browservenster is nog aan het opstarten — probeer over een paar tellen opnieuw'
          : 'het browservenster kon niet opgebouwd worden';
    }
    return laatsteFout.isEmpty ? 'het browservenster gaf niets terug' : laatsteFout;
  }

  /// Het lichaam van de JavaScript die één pagina ophaalt.
  ///
  /// Apart en zuiver, zodat er een toets op past zonder toestel: wat hier fout in staat is anders
  /// pas op een telefoon te zien, en dan als "geen resultaten".
  ///
  /// Drie dingen liggen hier vast:
  ///
  /// * `redirect: 'manual'` — een omleiding naar `login.php` **is** het antwoord (sessie verlopen).
  ///   Zou de browser hem volgen, dan kwam er een inlogpagina terug met status 200 en las dat als
  ///   "gelukt, maar niets gevonden".
  /// * De bytes gaan als base64 mee en niet als tekst. RuTracker is windows-1251 en een `.torrent`
  ///   is helemaal geen tekst; alles wat de browser zelf zou decoderen is schade.
  /// * Het antwoord wordt onder een eigen nummer geparkeerd, niet op één vaste plek. Er lopen
  ///   meerdere ophaalacties tegelijk, en die zouden elkaars antwoord overschrijven.
  @visibleForTesting
  static const jsHaalLichaam = r'''
try {
  var opties = {credentials: 'include', redirect: 'manual', cache: 'no-store'};
  if (referer) { opties.referrer = referer; }
  var r = await fetch(url, opties);
  window.__rtBuf = window.__rtBuf || {};
  if (r.type === 'opaqueredirect') { window.__rtBuf[id] = ''; return {status: 302, len: 0}; }
  var b = new Uint8Array(await r.arrayBuffer());
  var s = '';
  for (var i = 0; i < b.length; i += 8192) {
    s += String.fromCharCode.apply(null, b.subarray(i, i + 8192));
  }
  window.__rtBuf[id] = btoa(s);
  return {status: r.status, len: window.__rtBuf[id].length};
} catch (e) {
  window.__rtBuf = window.__rtBuf || {};
  window.__rtBuf[id] = '';
  return {status: -1, len: 0, fout: '' + e};
}
''';

  /// Zorg dat er een venster staat dat op RuTracker geparkeerd is.
  ///
  /// Meerdere aanroepen tegelijk wachten op dezelfde opening — anders bouwt elke zoekopdracht zijn
  /// eigen browser op.
  Future<bool> _zorgVoorVenster({Duration geduld = kVensterGeduld}) async {
    // Staat het venster er, dan is het goed genoeg — ook als het de vorige keer niet door Cloudflare
    // kwam. Het staat dan nog steeds op rutracker.org, dus een `fetch` gaat gewoon en levert het
    // eerlijke antwoord op: de pagina, of een 403 die het scherm daarna benoemt. Opnieuw twintig
    // seconden staan wachten bij élke zoekopdracht zou juist het zoeken slopen.
    if (_web != null) return true;
    // Loopt er al een opening, dan meeliften — maar niet langer dan er tijd is. Een zoekopdracht
    // die op een warmloop van twintig seconden blijft hangen wordt zelf weggegooid.
    final bezig = _bezigMetOpenen;
    if (bezig != null) {
      return bezig.future.timeout(geduld, onTimeout: () => false);
    }

    final wacht = Completer<bool>();
    _bezigMetOpenen = wacht;
    try {
      final klaar = Completer<void>();
      final venster = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(kRutrackerThuis)),
        initialSettings: InAppWebViewSettings(
          thirdPartyCookiesEnabled: true,
          javaScriptEnabled: true,
          // Geen eigen kenmerk opleggen: `cf_clearance` hangt vast aan de User-Agent die hem
          // gekregen heeft, en dat moet die van dít venster blijven.
          userAgent: '',
        ),
        onWebViewCreated: (c) => _web = c,
        onLoadStop: (_, __) {
          if (!klaar.isCompleted) klaar.complete();
        },
      );
      await venster.run();
      _venster = venster;

      // Wachten tot de pagina er staat én de wachtpagina van Cloudflare voorbij is. Die stuurt
      // zichzelf door, dus er komt daarna vanzelf nog een `onLoadStop` — maar niet altijd, dus er
      // wordt ook gewoon gekeken.
      final einde = DateTime.now().add(geduld);
      await klaar.future.timeout(geduld, onTimeout: () {});
      while (DateTime.now().isBefore(einde)) {
        if (await _isDoorgelaten()) {
          wacht.complete(true);
          return true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      // Niet binnengekomen. Het venster blijft staan: een volgende poging heeft er baat bij dat de
      // uitdaging inmiddels wél opgelost is.
      wacht.complete(false);
      return false;
    } catch (e) {
      debugPrint('RuTracker-venster kon niet openen: $e');
      await sluit();
      if (!wacht.isCompleted) wacht.complete(false);
      return false;
    } finally {
      _bezigMetOpenen = null;
    }
  }

  /// Staan we op RuTracker en niet op de wachtpagina van Cloudflare?
  Future<bool> _isDoorgelaten() async {
    final web = _web;
    if (web == null) return false;
    try {
      final adres = (await web.getUrl())?.toString() ?? '';
      if (!adres.contains('rutracker')) return false;
      final titel = (await web.getTitle() ?? '').toLowerCase();
      return !titel.contains(_wachtTitel);
    } catch (_) {
      return false;
    }
  }

  /// Het venster alvast opbouwen, zonder op de uitkomst te wachten.
  ///
  /// Aangeroepen bij het opstarten en na een geslaagde aanmelding: het opbouwen kost seconden, en
  /// die horen niet in je eerste zoekopdracht te vallen.
  Future<void> warmOp() async {
    if (!kan) return;
    try {
      await _zorgVoorVenster();
    } catch (_) {/* een venster dat niet wil opent zich straks bij de eerste zoekopdracht opnieuw */}
  }

  /// Eén pagina ophalen. Null als het venster er niet is of het niet lukte.
  Future<({int status, List<int> bytes})?> haal(String url, {String? referer}) async {
    if (!kan) return null;
    if (!await _zorgVoorVenster(geduld: kZoekGeduld)) return null;
    final web = _web;
    if (web == null) return null;

    final id = 'p${_teller++}';
    try {
      laatsteFout = '';
      final antwoord = await web
          .callAsyncJavaScript(
            functionBody: jsHaalLichaam,
            arguments: {'url': url, 'referer': referer ?? '', 'id': id},
          )
          .timeout(kZoekGeduld);
      final waarde = antwoord?.value;
      if (waarde is! Map) {
        laatsteFout = 'het browservenster gaf geen bruikbaar antwoord';
        return null;
      }
      final status = (waarde['status'] as num?)?.toInt() ?? 0;
      final lengte = (waarde['len'] as num?)?.toInt() ?? 0;
      if (status <= 0) {
        laatsteFout = 'het ophalen in het venster mislukte (${waarde['fout']})';
        debugPrint('RuTracker-venster: $laatsteFout');
        return null;
      }
      if (lengte == 0) return (status: status, bytes: const <int>[]);

      final tekst = await _leesInStukken(web, id, lengte);
      if (tekst == null) {
        laatsteFout = 'de pagina kwam maar half uit het venster';
        return null;
      }
      return (status: status, bytes: base64Decode(tekst));
    } catch (e) {
      laatsteFout = 'het venster gaf: $e';
      debugPrint('RuTracker-venster: ophalen mislukte ($e)');
      return null;
    } finally {
      // Opruimen, anders groeit het venster vol met oude pagina's.
      try {
        await web.evaluateJavascript(
            source: 'if (window.__rtBuf) { delete window.__rtBuf["$id"]; }');
      } catch (_) {/* een achtergebleven brok is geen reden om te falen */}
    }
  }

  /// Het antwoord in stukken ophalen. Zie [kStukGrootte] voor waarom niet in één keer.
  Future<String?> _leesInStukken(InAppWebViewController web, String id, int lengte) async {
    final uit = StringBuffer();
    for (var i = 0; i < lengte; i += kStukGrootte) {
      final deel = await web.evaluateJavascript(
          source: '(window.__rtBuf && window.__rtBuf["$id"]) '
              '? window.__rtBuf["$id"].substr($i, $kStukGrootte) : ""');
      if (deel is! String || deel.isEmpty) return null;
      uit.write(deel);
    }
    final tekst = uit.toString();
    return tekst.length == lengte ? tekst : null;
  }

  /// Het venster opruimen. Alleen nodig als de app het bewust wil loslaten.
  Future<void> sluit() async {
    _web = null;
    try {
      await _venster?.dispose();
    } catch (_) {/* een venster dat al weg is hoeft niet weg */}
    _venster = null;
  }
}

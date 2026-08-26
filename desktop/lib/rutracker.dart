import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'cp1251.dart';
import 'settings.dart';
import 'torbox.dart';

/// A CAPTCHA challenge RuTracker returned during login — shown to the user
/// (an image + a text answer), then submitted back with the login.
class RtCaptcha {
  final String imageUrl;
  final String sid;
  final String codeField; // e.g. cap_code_<hash>
  final String cookies; // cookies from the challenge response, resent with the answer
  const RtCaptcha(this.imageUrl, this.sid, this.codeField, this.cookies);
}

class RtLogin {
  final bool ok;
  final String? error;
  final RtCaptcha? captcha;
  const RtLogin.success()
      : ok = true,
        error = null,
        captcha = null;
  const RtLogin.failed(this.error)
      : ok = false,
        captcha = null;
  const RtLogin.needCaptcha(this.captcha)
      : ok = false,
        error = null;
}

/// RuTracker torrent source: form login (with CAPTCHA when asked) → cookie →
/// tracker.php search (scraped). The bb_session cookie is cached in settings.
class RuTrackerService {
  final AppSettings settings;
  RuTrackerService(this.settings);

  static const _base = 'https://rutracker.org/forum';
  static const _host = 'rutracker.org';
  /// **Waarom hier geen "DebridMusic" meer in staat.** RuTracker antwoordde met `403` op de
  /// aanmelding — niet "wachtwoord fout" (dat is een 200 met het formulier er weer bij), maar
  /// "jij niet". De oude waarde was een half nagemaakte browser met `DebridMusic/0.1` erachter
  /// geplakt: precies het soort kenmerk waar een antibot-laag op afgaat.
  ///
  /// Eerlijk over wat dit is: de app doet zich voor als een browser om binnen te komen op een
  /// account dat van jou is. Dat is dezelfde weg die je met de hand ook zou nemen, en er wordt niets
  /// omzeild wat jou niet toekomt.
  static const _uaStandaard = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  /// Het kenmerk dat bij de koekjes hoort, of anders het standaardkenmerk hierboven.
  ///
  /// **Waarom dit niet vast mag staan.** Cloudflare bindt `cf_clearance` aan het IP-adres én aan de
  /// User-Agent die hem gekregen heeft. Plak je een koekje uit Chrome 139 en stuurt de app er
  /// Chrome 131 bij, dan is dat koekje op slag waardeloos en krijg je dezelfde 403 terug — zonder
  /// dat iets uitlegt waarom.
  String get _ua => settings.rutrackerUa.isNotEmpty ? settings.rutrackerUa : _uaStandaard;

  /// Is er iets om mee binnen te komen?
  ///
  /// **Een sessie telt, en dat is de reparatie.** Dit vroeg om een ingetypte gebruikersnaam én
  /// wachtwoord, en `search()` weigerde daarop. Wie zich via het browservenster aanmeldt vult die
  /// twee velden nooit in — daar meldt hij zich immers in de browser aan — dus stond er een geldig
  /// koekje klaar terwijl het zoeken meteen een lege lijst teruggaf. Zonder één woord uitleg, en
  /// Instellingen zei ondertussen "aangemeld", want [verify] kijkt alleen naar het koekje.
  ///
  /// Het koekje ÍS de aanmelding. Naam en wachtwoord zijn er alleen nog voor de oude weg, die zelf
  /// kan inloggen zolang Cloudflare hem doorlaat.
  bool get configured =>
      settings.rutrackerCookie.isNotEmpty ||
      (settings.rutrackerUser.trim().isNotEmpty && settings.rutrackerPass.isNotEmpty);

  /// Kan de app zelf een aanmelding proberen? Daar zijn naam en wachtwoord wél voor nodig.
  bool get kanZelfAanmelden =>
      settings.rutrackerUser.trim().isNotEmpty && settings.rutrackerPass.isNotEmpty;

  /// Eén teken naar zijn byte in windows-1251, of null als die codetabel het niet kent.
  ///
  /// RuTracker is een cp1251-site: `login.php` leest wat je stuurt als windows-1251. Deze app
  /// stuurde UTF-8, en dat is op twee manieren fout. De knopwaarde `вход` kwam aan als twaalf bytes
  /// onzin in plaats van vier, en een wachtwoord met één letter met een accent erin werd verstuurd
  /// als andere bytes dan je intikte — waarna het nooit klopt, hoe zeker je ook van je wachtwoord
  /// bent.
  static int? cp1251Byte(int teken) {
    if (teken < 0x80) return teken; // ASCII is in beide tabellen hetzelfde
    if (teken >= 0x410 && teken <= 0x44F) return 0xC0 + (teken - 0x410); // А..я aaneengesloten
    if (teken == 0x401) return 0xA8; // Ё
    if (teken == 0x451) return 0xB8; // ё
    return null;
  }

  /// Een waarde klaar voor een formulier, op cp1251-bytes. Null als er een teken in staat dat die
  /// codetabel niet kent — dan is er niets te versturen en hoort dat gezegd te worden.
  ///
  /// Alles behalve de onbelaste tekens gaat er procentgecodeerd in, ook de spatie (`%20` en niet
  /// `+`, zodat een wachtwoord met een echte `+` erin niet stiekem een spatie wordt).
  static String? cp1251Form(String waarde) {
    const vrij = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~';
    final uit = StringBuffer();
    for (final teken in waarde.runes) {
      final b = cp1251Byte(teken);
      if (b == null) return null;
      final c = String.fromCharCode(teken);
      if (teken < 0x80 && vrij.contains(c)) {
        uit.write(c);
      } else {
        uit.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return uit.toString();
  }
  /// Hoeveel topicpagina's er hoogstens opgehaald worden om een ontbrekende infohash te vinden.
  ///
  /// Ruim, want de klok eronder is de echte rem — zie [search]. Niet oneindig: een zoekopdracht die
  /// tweehonderd pagina's tegelijk opvraagt is precies het soort burst waar een tracker op afgaat.
  static const _hashRuimte = 60;

  bool get loggedIn => settings.rutrackerCookie.isNotEmpty;

  // ── Het koekje uit je eigen browser ───────────────────────────────────────
  //
  // **Waarom de app niet meer zelf kan inloggen.** Gemeten op 23-08-2026: elk verzoek aan
  // rutracker.org — óók een kale GET van login.php, zonder gegevens — komt terug als
  //
  //     HTTP/1.1 403 Forbidden
  //     Server: cloudflare
  //     Cf-Mitigated: challenge
  //     <title>Just a moment...</title>
  //
  // Dat is de uitdaging die alleen een echte browser oplost (JavaScript plus een Turnstile-widget).
  // Headers nabootsen helpt niet, en dat is niet bij benadering vastgesteld maar uitgeprobeerd:
  // zonder User-Agent 403, met de Chrome-UA van de app 403, en met een volledige Chrome 139 inclusief
  // `sec-ch-ua`, `Sec-Fetch-*` en `Upgrade-Insecure-Requests` óók 403. rutracker.net idem;
  // rutracker.nl geeft wel 200 maar is een geparkeerde advertentiepagina — daar hoort geen
  // wachtwoord heen.
  //
  // Wat overblijft zonder een ingebouwde webview: de gebruiker lost de uitdaging op in zijn eigen
  // browser en geeft de app de koekjes die daaruit komen. `cf_clearance` is HttpOnly, dus
  // `document.cookie` toont hem niet — de bruikbare weg is "Kopieer als cURL" uit de netwerktab,
  // en die draagt het browserkenmerk meteen mee.

  /// Wat er uit een plaksel te halen viel.
  ///
  /// [cookie] is klaar om als `Cookie:`-kop te versturen; [ua] is leeg als het plaksel er geen
  /// bevatte (dan blijft het bestaande kenmerk staan).
  static ({String cookie, String ua, bool heeftClearance, bool heeftSessie})? leesPlaksel(
      String plaksel) {
    final tekst = plaksel.trim();
    if (tekst.isEmpty) return null;

    // Eerst de vorm van "Kopieer als cURL": -H 'cookie: …' of -H "cookie: …", en in de Windows-
    // variant ook ^"cookie: …^". Daarnaast kent curl -b voor koekjes.
    String? uitKop(String naam) {
      final re = RegExp(
          '''-[Hb]\\s+["'^]*\\s*(?:$naam)\\s*:?\\s*([^"'^]+)["'^]''',
          caseSensitive: false);
      return re.firstMatch(tekst)?.group(1)?.trim();
    }

    var koekjes = uitKop('cookie') ?? '';
    final ua = uitKop('user-agent') ?? '';

    // En de vorm die Chrome zelf gebruikt: `-b 'naam=waarde; naam=waarde'`, zónder het woord
    // "cookie" ervoor. Dit is geen randgeval — het is wat "Kopieer als cURL" in Chrome 151
    // uitspuugt, en precies hierop liep de eerste poging stuk: de koekjes zaten in het plaksel,
    // werden niet gevonden, en het scherm zei dat cf_clearance ontbrak terwijl hij er gewoon in
    // stond.
    if (koekjes.isEmpty) {
      final m = RegExp('''-b\\s+["'^]([^"'^]+)["'^]''').firstMatch(tekst);
      if (m != null) koekjes = m.group(1)!.trim();
    }

    // Geen cURL? Dan is het plaksel zelf de koekjesregel, zoals je hem uit de ontwikkelaarshulp of
    // uit een `document.cookie` kopieert.
    if (koekjes.isEmpty && tekst.contains('=') && !tekst.contains('\n-')) {
      koekjes = tekst.replaceAll(RegExp(r'^\s*(cookie|Cookie)\s*:\s*'), '').trim();
    }
    if (koekjes.isEmpty) return null;

    // Alleen naam=waarde-paren houden; wat een browser meestuurt mag er allemaal in blijven, want
    // Cloudflare kijkt naar meer dan alleen cf_clearance.
    final paren = <String>[];
    var clearance = false;
    var sessie = false;
    for (final deel in koekjes.split(';')) {
      final m = RegExp(r'^\s*([A-Za-z0-9_\-\.]+)=(.*)$').firstMatch(deel);
      if (m == null) continue;
      final naam = m.group(1)!;
      final waarde = m.group(2)!.trim();
      if (waarde.isEmpty) continue;
      if (naam == 'cf_clearance') clearance = true;
      if (naam == 'bb_session') sessie = true;
      paren.add('$naam=$waarde');
    }
    if (paren.isEmpty) return null;
    return (
      cookie: paren.join('; '),
      ua: ua,
      heeftClearance: clearance,
      heeftSessie: sessie,
    );
  }

  /// Neem de koekjes uit de browser over en kijk meteen of ze werken.
  ///
  /// Eén handeling, want een koekje dat je bewaart zonder het te proberen is een instelling waarvan
  /// je pas bij de volgende zoekopdracht hoort dat hij niets deed.
  Future<RtLogin> gebruikPlaksel(String plaksel) async {
    final gelezen = leesPlaksel(plaksel);
    if (gelezen == null) {
      return const RtLogin.failed(
          'Daar zat geen koekje in. Plak de hele regel uit "Kopieer als cURL" van je browser, of '
          'de koekjesregel zelf (naam=waarde; naam=waarde).');
    }
    if (!gelezen.heeftSessie) {
      return const RtLogin.failed(
          'Er zit geen bb_session in — dat is het koekje dat zegt dat je ingelogd bent. Log eerst '
          'in op rutracker.org in je browser en kopieer daarna een verzoek naar die site.');
    }

    final vorigeCookie = settings.rutrackerCookie;
    final vorigeUa = settings.rutrackerUa;
    settings.rutrackerCookie = gelezen.cookie;
    if (gelezen.ua.isNotEmpty) settings.rutrackerUa = gelezen.ua;

    if (await verify()) {
      await settings.save();
      lastError = '';
      pendingCaptcha = null;
      return const RtLogin.success();
    }

    // Niet bewaren wat aantoonbaar niet werkt: dan blijft er een dode instelling staan die elke
    // zoekopdracht stil laat mislukken.
    settings.rutrackerCookie = vorigeCookie;
    settings.rutrackerUa = vorigeUa;
    return RtLogin.failed(gelezen.heeftClearance
        ? 'De koekjes kwamen aan, maar RuTracker herkende de sessie niet (meer). Ververs de pagina '
            'in je browser en kopieer het verzoek opnieuw.'
        : 'Er zit geen cf_clearance in het plaksel, en zonder dat koekje houdt Cloudflare de app '
            'tegen. Kopieer een verzoek naar rutracker.org uit de netwerktab van je browser — dat '
            'koekje is HttpOnly en staat dus niet in document.cookie.');
  }

  /// Staat Cloudflare ertussen? Dan is er niets mis met naam, wachtwoord of sessie.
  ///
  /// Drie aanwijzingen, en één is genoeg: de kop die Cloudflare zelf zet, de server die zich noemt,
  /// of de titel van de wachtpagina.
  static bool cloudflareUitdaging(Map<String, String> koppen, String lichaam) {
    if (koppen.keys.any((k) => k.toLowerCase() == 'cf-mitigated')) return true;
    final server = (koppen['server'] ?? '').toLowerCase();
    final laag = lichaam.toLowerCase();
    return server.contains('cloudflare') &&
        (laag.contains('just a moment') ||
            laag.contains('challenges.cloudflare.com') ||
            laag.contains('__cf_chl'));
  }

  // ── Ophalen langs curl ────────────────────────────────────────────────────
  //
  // **Waarom niet gewoon de HTTP-client van de app.** Gemeten op 23-08-2026, met één en hetzelfde
  // geldige koekje, dezelfde koppen en hetzelfde IP-adres:
  //
  //     curl.exe (Windows)                 -> 200
  //     .NET (Invoke-WebRequest, Schannel) -> 403
  //     deze app (Dart, BoringSSL)         -> 403, Cloudflare-uitdaging
  //
  // Het verschil zit dus niet in wat we STUREN maar in hoe de TLS-verbinding zich voorstelt: de
  // vingerafdruk van de ClientHello. Cloudflare weegt die mee, en die van Dart komt er niet door.
  // Geen enkele kop, koekje of instelling verandert daar iets aan — dat is uitgeprobeerd.
  //
  // `curl.exe` zit sinds Windows 10 (1803) in het systeem en staat op macOS en Linux ook gewoon in
  // het pad. Voor RuTracker gaat het verkeer daar dus langs. Is curl er niet, dan valt alles terug
  // op de gewone weg — dan werkt het niet beter dan voorheen, maar ook niet slechter.
  //
  // Eerlijk over wat dit is: een omweg om binnen te komen op een account dat van jou is, langs een
  // deur die je met de hand ook zou openen. Er wordt niets omzeild wat jou niet toekomt, en het kan
  // morgen weer dicht: gaat Cloudflare ook op deze vingerafdruk letten, dan is dit voorbij.

  /// Is er een curl om langs te gaan? Eén keer vastgesteld, daarna onthouden.
  static bool? _curlAanwezig;

  static Future<bool> curlBeschikbaar() async {
    if (_curlAanwezig != null) return _curlAanwezig!;
    try {
      final p = await Process.run('curl', ['--version'])
          .timeout(const Duration(seconds: 5));
      _curlAanwezig = p.exitCode == 0;
    } catch (_) {
      _curlAanwezig = false;
    }
    return _curlAanwezig!;
  }

  @visibleForTesting
  static set curlBeschikbaarVoorTest(bool? v) => _curlAanwezig = v;

  /// De argumenten voor één opgehaalde pagina. Apart, zodat er een toets op past zonder curl.
  ///
  /// `--compressed` staat er NIET bij: het antwoord is windows-1251 en wordt hier als losse bytes
  /// gelezen; een gzip-laag zou daar alleen maar tussen zitten.
  @visibleForTesting
  static List<String> curlArgumenten(String url, String cookie, String ua, String uitPad,
      {String? koppenPad, String? referer}) {
    return [
      '-s',
      '--max-time', '20',
      // Zelf volgen doen we niet: een 302 naar login.php IS het antwoord (sessie verlopen).
      '--no-location',
      '-A', ua,
      // `dl.php` geeft het torrentbestand alleen aan wie van de site zelf lijkt te komen.
      if (referer != null) ...['-e', referer],
      if (cookie.isNotEmpty) ...['-b', cookie],
      if (koppenPad != null) ...['-D', koppenPad],
      '-o', uitPad,
      '-w', '%{http_code}',
      url,
    ];
  }

  /// Ophalen dóór het browservenster. Gezet bij het opstarten van de app; null waar dat niet kan.
  ///
  /// **Waarom dit erbij moest.** `curl` zit in Windows, macOS en Linux, maar **niet op Android**. Op
  /// een telefoon viel alles dus terug op de gewone HTTP-client — precies de weg waarvan hierboven
  /// gemeten staat dat Cloudflare hem met 403 tegenhoudt, óók met een geldig koekje. Dat is de reden
  /// dat er op het toestel geen enkel resultaat binnenkwam terwijl de aanmelding klopte.
  ///
  /// Het staat hier als een losse haak en niet als een `import`, zodat dit bestand geen webview
  /// nodig heeft om te compileren of om getoetst te worden. Zie `rutracker_venster.dart`.
  static Future<({int status, List<int> bytes})?> Function(String url, {String? referer})?
      viaVenster;

  /// Eén zin over hoe het browservenster ervoor staat, voor als het ophalen niet lukte.
  ///
  /// Zonder dit is "het venster gaf niets terug" het enige wat er te zeggen valt, en dat is precies
  /// het soort melding waar je niets aan hebt.
  static String Function()? vensterStand;

  /// Waarom het laatste ophalen niet lukte. Leeg als er niets misging.
  ///
  /// **Waarom dit er moest komen.** `_haal` gaf `null` terug voor drie verschillende dingen — geen
  /// curl, een venster dat niets opleverde, en een verbinding die een uitzondering gooide — en
  /// [search] maakte daar `return []` van zónder een woord. Op het scherm stond dan "Geen torrents
  /// gevonden.", punt. Dat is dezelfde stilte als waar deze hele reeks reparaties over ging, en hij
  /// zat nog één laag dieper.
  String haalReden = '';

  /// Eén GET: langs curl, langs het venster, of langs de gewone client — in die volgorde.
  ///
  /// **De volgorde is het hele punt.** `curl` is op een pc het snelst en bewezen. Komt hij er niet
  /// (403 van Cloudflare) of is hij er niet (een telefoon), dan gaat het door het venster, want dat
  /// is een échte browser en lost de uitdaging zelf op. Pas als er ook geen venster is, blijft de
  /// gewone client over — die werkt dan niet beter dan voorheen, maar ook niet slechter.
  Future<({int status, List<int> bytes})?> _haal(String url, {String? referer}) async {
    haalReden = '';
    final heeftCurl = await curlBeschikbaar();
    final langsCurl = heeftCurl ? await _haalMetCurl(url, referer: referer) : null;
    // Een 403 is hier geen antwoord maar een dichte deur: doorlopen naar het venster.
    if (langsCurl != null && langsCurl.status != 403) return langsCurl;

    final venster = viaVenster;
    if (venster != null) {
      final langsVenster = await venster(url, referer: referer);
      if (langsVenster != null) return langsVenster;
      haalReden = vensterStand?.call() ?? 'het browservenster gaf niets terug';
    } else {
      haalReden = 'dit toestel heeft geen ingebouwd browservenster';
    }
    if (langsCurl != null) return langsCurl;

    try {
      final req = http.Request('GET', Uri.parse(url))
        ..followRedirects = false
        ..headers['Cookie'] = settings.rutrackerCookie
        ..headers['User-Agent'] = _ua;
      final client = http.Client();
      final resp = await http.Response.fromStream(await client.send(req))
          .timeout(const Duration(seconds: 12));
      client.close();
      return (status: resp.statusCode, bytes: resp.bodyBytes);
    } catch (e) {
      // De uitzondering zelf erbij: het verschil tussen een naam die niet opgezocht kan worden en
      // een verbinding die na twaalf seconden opgeeft is precies wat je wil weten.
      final erbij = haalReden.isEmpty ? '' : '$haalReden, en ';
      haalReden = '${erbij}de gewone verbinding gaf: $e';
      return null;
    }
  }

  /// De curl-weg apart, zodat [_haal] de volgorde kan bepalen. Null als curl er niet is of faalde.
  Future<({int status, List<int> bytes})?> _haalMetCurl(String url, {String? referer}) async {
    if (await curlBeschikbaar()) {
      Directory? tijdelijk;
      try {
        tijdelijk = await Directory.systemTemp.createTemp('rt_');
        final uit = '${tijdelijk.path}${Platform.pathSeparator}p';
        final p = await Process.run('curl',
            curlArgumenten(url, settings.rutrackerCookie, _ua, uit, referer: referer))
            .timeout(const Duration(seconds: 25));
        final status = int.tryParse((p.stdout as String).trim()) ?? 0;
        final f = File(uit);
        final bytes = await f.exists() ? await f.readAsBytes() : <int>[];
        return (status: status, bytes: bytes);
      } catch (_) {
        return null;
      } finally {
        try {
          await tijdelijk?.delete(recursive: true);
        } catch (_) {/* een achtergebleven tijdelijk bestand is geen reden om te falen */}
      }
    }
    return null;
  }

  /// De zin die daarbij hoort. Eén plek, want hij hoort overal hetzelfde te zijn.
  static const uitdagingUitleg =
      'Cloudflare houdt de app tegen met een uitdaging die alleen een echte browser kan oplossen — '
      'het ligt niet aan je gebruikersnaam of wachtwoord. Meld je opnieuw aan bij Instellingen → '
      'RuTracker → Aanmelden; dat venster ís een echte browser en lost de uitdaging op.';

  Future<RtLogin> login({String? captchaAnswer, RtCaptcha? captcha}) async {
    // Hier zijn naam en wachtwoord WEL nodig — dit is de weg die zelf een formulier invult. Zie
    // [configured]: dat vraagt sinds kort minder, want een koekje uit het venster is ook een
    // aanmelding, en die heeft geen wachtwoord nodig.
    if (!kanZelfAanmelden) return const RtLogin.failed('Geen RuTracker-login ingevuld');
    try {
      final naam = cp1251Form(settings.rutrackerUser.trim());
      final woord = cp1251Form(settings.rutrackerPass);
      if (naam == null || woord == null) {
        return const RtLogin.failed(
            'Je gebruikersnaam of wachtwoord bevat een teken dat RuTracker niet kent (hij werkt '
            'met de Russische codetabel). Alleen gewone letters, cijfers en leestekens komen daar '
            'ongeschonden aan.');
      }
      // Eerst de inlogpagina ophalen, zoals een browser doet.
      //
      // Dit stond er niet: de app postte blind naar login.php zonder ooit een pagina gezien te
      // hebben. Een site die een sessie-koekje verwacht vóórdat je het formulier opstuurt, wijst
      // zo'n post af — en 403 is precies hoe dat eruitziet. Wat hij terugstuurt aan koekjes gaat
      // mee met de aanmelding.
      final voorafCookies = await _haalInlogpagina();

      var body = 'login_username=$naam&login_password=$woord'
          '&login=${cp1251Form('вход')}';
      final headers = <String, String>{
        // Zonder charset: het lichaam is al procentgecodeerd op cp1251-bytes. Zou hier
        // `; charset=utf-8` bij komen — en dat gebeurt vanzelf als je `..body =` gebruikt in
        // plaats van `..bodyBytes =` — dan vertel je een cp1251-site het tegenovergestelde van
        // wat je stuurt.
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': _ua,
        // Een formulier dat van de site zelf komt heeft deze twee. Ze ontbraken.
        'Referer': '$_base/login.php',
        'Origin': 'https://$_host',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'ru,en;q=0.9',
        if (voorafCookies.isNotEmpty) 'Cookie': voorafCookies,
      };
      if (captcha != null && captchaAnswer != null) {
        final antwoord = cp1251Form(captchaAnswer) ?? '';
        body += '&cap_sid=${cp1251Form(captcha.sid) ?? ''}&${captcha.codeField}=$antwoord';
        // De koekjes van de captcha-uitdaging gaan vóór die van de kale inlogpagina: het antwoord
        // hoort bij díé sessie.
        if (captcha.cookies.isNotEmpty) headers['Cookie'] = captcha.cookies;
      }
      final req = http.Request('POST', Uri.parse('$_base/login.php'))
        ..followRedirects = false
        ..headers.addAll(headers)
        ..bodyBytes = ascii.encode(body);
      final client = http.Client();
      final resp = await http.Response.fromStream(await client.send(req))
          .timeout(const Duration(seconds: 20));
      client.close();

      final setCookie = resp.headers['set-cookie'] ?? '';
      final sess = RegExp(r'bb_session=([^;,\s]+)').firstMatch(setCookie);
      if (sess != null && sess.group(1)!.length > 8) {
        settings.rutrackerCookie = 'bb_session=${sess.group(1)}';
        await settings.save();
        return const RtLogin.success();
      }

      final html = cp1251Tekst(resp.bodyBytes);
      // Eerst Cloudflare, want daar strandt het tegenwoordig al vóór het formulier. Zonder deze
      // regel komt zo'n 403 eruit als "controleer je gegevens" en ga je je wachtwoord zitten
      // nakijken terwijl de app RuTracker nooit gesproken heeft.
      if (cloudflareUitdaging(resp.headers, html)) {
        return const RtLogin.failed(uitdagingUitleg);
      }
      final img = RegExp(r'src="((?:https?:)?//[^"]*captcha[^"]*)"').firstMatch(html);
      final sid = RegExp(r'name="cap_sid"\s+value="([^"]+)"').firstMatch(html);
      final field = RegExp(r'name="(cap_code_[^"]+)"').firstMatch(html);
      if (img != null && sid != null && field != null) {
        var url = img.group(1)!;
        if (url.startsWith('//')) url = 'https:$url';
        return RtLogin.needCaptcha(
            RtCaptcha(url, sid.group(1)!, field.group(1)!, _cookiesFrom(setCookie)));
      }
      // Hieronder stond één zin — "controleer je gegevens" — voor drie totaal verschillende
      // oorzaken: een fout wachtwoord, een blokkadepagina van je provider, en een RuTracker die
      // iets anders terugstuurt dan vroeger. Dat stuurt je precies de verkeerde kant op: je gaat je
      // wachtwoord zitten controleren terwijl de site niet eens bereikt is.
      //
      // Kregen we werkelijk RuTracker aan de lijn? Zijn eigen pagina's noemen zichzelf. Een
      // blokkadepagina van een provider doet dat niet.
      final lijktRuTracker = html.toLowerCase().contains('rutracker') ||
          resp.headers['set-cookie']?.contains('bb_') == true;
      if (!lijktRuTracker) {
        return RtLogin.failed(
            'Er antwoordde iets op $_host, maar het was RuTracker niet (${resp.statusCode}). '
            'Waarschijnlijk blokkeert je provider of je netwerk die site. Kun je '
            'https://$_host in je browser openen? Lukt dat ook niet, dan ligt het daar en niet '
            'aan je wachtwoord.');
      }
      return RtLogin.failed(
          'RuTracker wees de aanmelding af (${resp.statusCode}). Als je gebruikersnaam en '
          'wachtwoord kloppen, vraagt hij mogelijk om iets nieuws dat deze app nog niet meestuurt.');
    } catch (e) {
      // De uitzondering ZELF, en niet "geen verbinding". Het verschil tussen een naam die niet
      // opgezocht kan worden, een certificaat dat niet deugt en een verbinding die na twintig
      // seconden opgeeft is precies wat je wil weten, en dat werd hier weggegooid.
      return RtLogin.failed('Geen verbinding met $_host: $e');
    }
  }

  /// De inlogpagina ophalen om de koekjes te krijgen die een browser ook zou hebben.
  ///
  /// Mislukt dit, dan is dat geen reden om de aanmelding niet te proberen — dan gaat hij zoals
  /// vroeger, blind. Een voorbereidende stap mag nooit de hoofdweg blokkeren.
  Future<String> _haalInlogpagina() async {
    try {
      final client = http.Client();
      final req = http.Request('GET', Uri.parse('$_base/login.php'))
        ..followRedirects = false
        ..headers['User-Agent'] = _ua
        ..headers['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
        ..headers['Accept-Language'] = 'ru,en;q=0.9';
      final resp = await http.Response.fromStream(await client.send(req))
          .timeout(const Duration(seconds: 12));
      client.close();
      return _cookiesFrom(resp.headers['set-cookie'] ?? '');
    } catch (_) {
      return '';
    }
  }

  /// De koekjes uit een antwoord, klaar om terug te sturen.
  ///
  /// **Niet alleen de `bb_`-koekjes.** Dat stond hier, en het is precies de val bij een 403: een
  /// antibot-laag zet iets neer dat `cf_clearance` of `__ddg1` heet, en dat werd weggegooid. Dan
  /// stuur je je aanmelding naar een sessie die de server niet kan thuisbrengen.
  ///
  /// Alleen de naam en de waarde; `Path=`, `Domain=`, `Expires=` en `HttpOnly` horen bij het
  /// antwoord en niet bij wat je terugstuurt.
  String _cookiesFrom(String setCookie) {
    const geenKoekje = {'path', 'domain', 'expires', 'max-age', 'samesite', 'secure', 'httponly'};
    final gezien = <String, String>{};
    for (final m in RegExp(r'([A-Za-z0-9_\-]+)=([^;,\s]*)').allMatches(setCookie)) {
      final naam = m.group(1)!;
      if (geenKoekje.contains(naam.toLowerCase())) continue;
      gezien[naam] = m.group(2)!; // een latere waarde vervangt een eerdere, zoals een browser doet
    }
    return gezien.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// Het `.torrent`-bestand zelf ophalen, ingelogd.
  ///
  /// `dl.php` geeft alleen iets zinnigs terug met een geldige sessie; zonder krijg je een
  /// HTML-pagina in plaats van een torrent. Vandaar de controle op de eerste byte: een bencode-
  /// bestand begint met `d`. Zo komt er nooit een foutpagina als "torrent" bij TorBox terecht.
  Future<List<int>?> haalTorrentBestand(String url) async {
    if (settings.rutrackerCookie.isEmpty) return null;
    final r = await _haal(url, referer: '$_base/index.php');
    if (r == null || r.status != 200 || r.bytes.isEmpty) return null;
    if (r.bytes.first != 0x64) return null; // geen 'd' = geen torrent, maar een pagina
    return r.bytes;
  }

  /// True if the cached cookie still authenticates (tracker.php returns 200, not a 302 to login).
  Future<bool> verify() async {
    if (settings.rutrackerCookie.isEmpty) return false;
    final r = await _haal('$_base/tracker.php');
    return r?.status == 200;
  }

  /// Set when the session died and logging back in needs a human — a captcha.
  ///
  /// Read by the search UI so it can say so. Without it an expired session is indistinguishable
  /// from "RuTracker has nothing", which is exactly what it looked like: you search, you get
  /// nothing, and nowhere does it say you are logged out.
  RtCaptcha? pendingCaptcha;
  String lastError = '';

  /// Hoeveel treffers RuTracker de laatste keer opleverde. **-1 betekent: niet bevraagd.**
  ///
  /// **Waarom dit erbij moest, en waarom -1 apart staat.** Er is een reeks meldingen bijgebouwd voor
  /// élke reden om niets terug te geven, en op het scherm bleef het stil. Dat kan drie dingen
  /// betekenen die van buiten identiek zijn: hij is niet bevraagd, hij gaf nul, of hij gaf treffers
  /// die verderop wegvielen. Zolang die drie hetzelfde lege scherm opleveren blijft elke reparatie
  /// een gok.
  ///
  /// Daarom telt hij nu gewoon, en zegt het scherm het altijd — ook als er niets aan de hand is.
  int laatsteAantal = -1;

  /// Hoeveel daarvan de zeef in `search.dart` overleefden. Zie [laatsteAantal].
  int laatsteDoorZeef = -1;

  Future<List<SearchResult>> search(String query, {bool allowRelogin = true}) async {
    // Niet bevraagd, tot het tegendeel blijkt. Zie [laatsteAantal].
    laatsteAantal = -1;
    laatsteDoorZeef = -1;
    // Zwijgen is hier duur gebleken: een lege lijst leest als "RuTracker heeft niets", terwijl de
    // reden is dat er niets klaarstaat om mee binnen te komen. Zeg het dus.
    if (settings.rutrackerCookie.isEmpty) {
      lastError = kanZelfAanmelden
          ? 'Nog niet aangemeld bij RuTracker — Instellingen → RuTracker → Aanmelden.'
          : 'Geen RuTracker-aanmelding — Instellingen → RuTracker → Aanmelden.';
      return [];
    }
    // Schoon beginnen. Zonder dit blijft de melding van de vórige poging staan nadat je het
    // probleem allang verholpen hebt — en dan zegt het scherm iets dat niet meer waar is.
    lastError = '';
    // Vanaf hier is hij wél bevraagd. Elke uitgang hieronder zet een reden in [lastError]; dit getal
    // maakt daarnaast zichtbaar of er iets binnenkwam.
    laatsteAantal = 0;
    // De zoekverdeler in search.dart hakt elke bron na 12 seconden af, en slikt de fout. Blijf daar
    // met opzet onder: liever een korte lijst die aankomt dan een volledige die weggegooid wordt.
    final deadline = DateTime.now().add(const Duration(milliseconds: 10500));
    try {
      final resp = await _haal('$_base/tracker.php?nm=${Uri.encodeComponent(query)}');
      // **Hier stond `return []` zonder één woord.** Dat is dezelfde stilte als waar deze hele
      // reeks over ging, één laag dieper: het scherm zei "Geen torrents gevonden." terwijl de app
      // RuTracker helemaal niet gesproken had. Zie [haalReden].
      if (resp == null) {
        lastError = haalReden.isEmpty
            ? 'RuTracker antwoordde niet.'
            : 'RuTracker antwoordde niet — $haalReden.';
        return [];
      }
      // Een verlopen cf_clearance ziet er anders uit dan een verlopen sessie: geen omleiding naar
      // login.php, maar dezelfde wachtpagina als bij de deur. Opnieuw inloggen heeft dan geen zin —
      // dat loopt tegen precies dezelfde muur — dus zeg wat er aan de hand is en stop.
      //
      // Op de curl-weg zijn er geen koppen om te wegen, dus daar beslist de wachtpagina zelf.
      if (resp.status == 403) {
        lastError = uitdagingUitleg;
        return [];
      }
      if (resp.status == 302) {
        // The session expired. RuTracker's cookie does not last forever, and nothing renewed it:
        // login() had exactly two callers, the button in Settings and a test. So the cookie was
        // dropped, an empty list came back, and the whole thing read as "it forgot my login".
        //
        // We hold the username and the password, so log in again and do the search over. Once —
        // `allowRelogin` stops a broken login from bouncing between the two forever.
        settings.rutrackerCookie = '';
        await settings.save(); // in memory only left a dead cookie on disk until some other save
        if (!allowRelogin) return [];

        final again = await login();
        if (again.ok) {
          pendingCaptcha = null;
          lastError = '';
          return search(query, allowRelogin: false);
        }
        // A captcha cannot be answered from here — but it CAN be said out loud.
        pendingCaptcha = again.captcha;
        lastError = again.captcha != null
            ? 'RuTracker vraagt om een captcha — log opnieuw in bij Instellingen.'
            : (again.error ?? 'RuTracker-login mislukt.');
        return [];
      }
      final html = cp1251Tekst(resp.bytes);
      // Een 200 hoeft nog geen zoekpagina te zijn. Twee gevallen die er precies zo uitzien als
      // "RuTracker heeft niets", en die alledrie een andere handeling van je vragen.
      if (cloudflareUitdaging(const {}, html)) {
        lastError = uitdagingUitleg;
        return [];
      }
      if (html.contains('login_username') && !html.contains('tracker.php')) {
        settings.rutrackerCookie = '';
        await settings.save();
        lastError = 'Je RuTracker-sessie is verlopen — Instellingen → RuTracker → Aanmelden.';
        return [];
      }
      final rows = _parseRows(html);
      // **Nul rijen uit een pagina die wél binnenkwam.** Dat is iets anders dan "niets gevonden":
      // het kan de zoekpagina zijn die niets had, maar ook een RuTracker die zijn HTML veranderd
      // heeft — en dat laatste is het brooste stuk van deze hele bron. Het aantal bytes erbij, want
      // dat scheidt de twee: een lege uitslag is een halve pagina, een veranderde vorm een hele.
      if (rows.isEmpty) {
        lastError = 'RuTracker antwoordde (${resp.status}, ${resp.bytes.length} bytes) maar er '
            'stond geen enkele resultaatrij in de pagina.';
        return [];
      }
      // De ontbrekende infohashes van de topicpagina halen.
      //
      // **Met een eigen klok, en dat is het verschil tussen resultaten en niets.** De zoekverdeler
      // hakt elke bron na 12 seconden af en slikt de fout in stilte. RuTracker had hier een
      // slechtste geval van 15 seconden voor de lijst plus 12 voor deze pagina's — samen 27, ruim
      // over die grens. Dan viel de hele bron weg en zag je "geen resultaten van RuTracker" terwijl
      // er gewoon een lijst lag.
      //
      // **De klok is de rem, niet een vast getal.** Hier stond `take(12)` bovenop die klok, en dat
      // is er één te veel: op een snelle dag stopte hij bij twaalf terwijl er nog seconden over
      // waren, en op een trage dag deed de klok het werk toch al. Nu is de grens ruim genoeg om
      // niet te binden en beslist de tijd — precies wat er bedoeld werd.
      //
      // Wat er binnen de tijd is, is binnen. De rest valt af zoals hij altijd al afviel: zonder
      // infohash valt er niets op te halen, en de zoekverdeler zeeft ze ook zelf weg (zie
      // `search.dart`, waar op de infohash ontdubbeld wordt).
      final need = rows.where((r) => r.hash == null).take(_hashRuimte).toList();
      final resterend = deadline.difference(DateTime.now());
      if (need.isNotEmpty && !resterend.isNegative) {
        await Future.wait(need.map((r) async => r.hash = await _hashFromTopic(r.topicId)))
            .timeout(resterend, onTimeout: () => const []);
      }
      // Rijen zonder infohash vallen af — daar valt niets mee op te halen. Maar vallen ze ALLEMAAL
      // af, dan heeft RuTracker wel degelijk gevonden wat je zocht en komt het alleen niet bij je
      // aan. Dat hoort iets heel anders op het scherm te zetten dan "geen torrents".
      final metHash = rows.where((r) => r.hash != null).toList();
      if (metHash.isEmpty) {
        lastError = 'RuTracker vond ${rows.length} resultaten, maar van geen enkele kwam de '
            'infohash binnen — de topicpagina\'s haalden de tijd niet.';
        return [];
      }
      laatsteAantal = metHash.length;
      return metHash
          .map((r) => SearchResult(
                name: r.title,
                size: r.size,
                seeders: r.seeders,
                hash: r.hash!,
                magnet:
                    'magnet:?xt=urn:btih:${r.hash}&dn=${Uri.encodeComponent(r.title)}',
                source: 'RuTracker',
                // Het bestand erbij, want de magneet alleen levert hier niets op: de zwerm van
                // RuTracker staat achter hun eigen announce en niet in DHT. Zie
                // [SearchResult.torrentUrl] voor de meting.
                torrentUrl: '$_base/dl.php?t=${r.topicId}',
              ))
          .toList();
    } catch (e) {
      // Ook hier stond een kale `return []`. Een uitzondering die niemand ooit ziet is een fout die
      // je nooit vindt.
      lastError = 'RuTracker liep vast: $e';
      return [];
    }
  }

  List<_Row> _parseRows(String html) {
    final out = <_Row>[];
    for (final m in RegExp(r'<tr[^>]*class="[^"]*hl-tr[^"]*"[\s\S]*?</tr>').allMatches(html)) {
      final h = m.group(0)!;
      final tid = RegExp(r'data-topic_id="(\d+)"').firstMatch(h)?.group(1);
      final title = RegExp(r'class="med tLink[^"]*"[^>]*>([\s\S]*?)</a>').firstMatch(h)?.group(1);
      if (tid == null || title == null) continue;
      final size = int.tryParse(
              RegExp(r'tor-size"[^>]*data-ts_text="(-?\d+)"').firstMatch(h)?.group(1) ?? '') ??
          0;
      final seed =
          int.tryParse(RegExp(r'class="seedmed"[^>]*>(\d+)').firstMatch(h)?.group(1) ?? '') ?? 0;
      final hash =
          RegExp(r'urn:btih:([a-fA-F0-9]{40})').firstMatch(h)?.group(1)?.toLowerCase();
      out.add(_Row(tid, _clean(title), size, seed, hash));
    }
    return out;
  }

  Future<String?> _hashFromTopic(String topicId) async {
    final r = await _haal('$_base/viewtopic.php?t=$topicId');
    if (r == null || r.status != 200) return null;
    final html = cp1251Tekst(r.bytes);
    return RegExp(r'urn:btih:([a-fA-F0-9]{40})').firstMatch(html)?.group(1)?.toLowerCase();
  }

  String _clean(String s) => s
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&nbsp;', ' ')
      .trim();
}

class _Row {
  final String topicId;
  final String title;
  final int size;
  final int seeders;
  String? hash;
  _Row(this.topicId, this.title, this.size, this.seeders, this.hash);
}

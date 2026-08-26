/// Aanmelden bij RuTracker in een écht browservenster.
///
/// **Waarom dit bestaat, gemeten en niet vermoed.** Op 23-08-2026 is vastgesteld dat élk verzoek aan
/// rutracker.org strandt in een Cloudflare-uitdaging — 403, `Cf-Mitigated: challenge`, "Just a
/// moment..." — óók een kale GET van de inlogpagina zonder gegevens. Koppen nabootsen hielp niet:
/// met en zonder User-Agent, en met een volledige Chrome inclusief `sec-ch-ua` en `Sec-Fetch-*`,
/// allemaal 403. De conclusie stond toen al in `main.dart` bij [RuTrackerKoekjeDialoog]: *zolang er
/// geen ingebouwde webview is, is plakken de enige eerlijke weg.*
///
/// Dit is die webview. Het verschil met plakken is niet gemak maar houdbaarheid:
///
/// * `cf_clearance` zit vast aan het IP-adres **én** aan de User-Agent die hem gekregen heeft. Bij
///   plakken moeten die twee met de hand kloppen — en klopt er één niet, dan krijg je dezelfde 403
///   zonder dat iets uitlegt waarom. Hier kán dat niet mislopen: het koekje en het kenmerk komen uit
///   hetzelfde venster, op hetzelfde IP-adres.
/// * Een geplakt koekje verloopt en dan is er geen weg terug zonder opnieuw te plakken. Dit venster
///   kan de app zelf openen zodra de sessie dood is.
///
/// **Eerlijk over wat dit is.** De app doet niets wat jij met je eigen browser niet ook zou doen: er
/// wordt een pagina geopend, jij logt in op je eigen account, en de app leent het koekje dat daaruit
/// komt. Er wordt geen uitdaging omzeild — hij wordt opgelost, door jou, in een echte browser.
///
/// **Niet elk toestel heeft er een.** Zie [rutrackerVensterKan]. Waar het niet kan blijft de
/// plakweg gewoon staan; die wordt niet weggegooid.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Waar de aanmelding begint. `login.php` en niet de voorpagina: dan sta je meteen op het formulier.
const kRutrackerLoginUrl = 'https://rutracker.org/forum/login.php';

/// Draagt dit toestel een ingebouwd browservenster?
///
/// `flutter_inappwebview` noemt Android, iOS, macOS en Windows. Linux staat er niet bij, en web is
/// hier niet aan de orde. Waar dit onwaar is, blijft de plakweg over.
bool get rutrackerVensterKan =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows);

/// Wat er uit het venster komt.
///
/// [cookie] is meteen klaar om als `Cookie:`-kop mee te sturen, in dezelfde vorm die
/// `RuTrackerService` al verwacht. [ua] is het kenmerk van dít venster — dat hoort er onlosmakelijk
/// bij, zie de uitleg bovenaan.
@immutable
class RtSessie {
  const RtSessie({required this.cookie, required this.ua});

  final String cookie;
  final String ua;

  /// Ben je aangemeld? Zonder `bb_session` heb je alleen een Cloudflare-doorgang en geen account.
  bool get heeftSessie => cookie.contains('bb_session=');

  /// Is de Cloudflare-doorgang er ook? Niet altijd nodig — soms laat hij je zonder door — dus dit
  /// is een bijzonderheid om te tonen, geen eis.
  bool get heeftClearance => cookie.contains('cf_clearance=');
}

/// Open het venster en geef terug wat er opgehaald is, of null als er niets bruikbaars kwam.
///
/// Sluit de gebruiker het venster zelf, dan komt eruit wat er op dat moment lag — dat kan een halve
/// oogst zijn (wel clearance, geen sessie), en dat hoort de aanroeper te kunnen zien in plaats van
/// het als "gelukt" te lezen.
Future<RtSessie?> meldAanBijRutracker(BuildContext context) {
  if (!rutrackerVensterKan) return Future.value(null);
  return Navigator.of(context, rootNavigator: true).push<RtSessie>(
    MaterialPageRoute(builder: (_) => const RutrackerLoginPagina(), fullscreenDialog: true),
  );
}

/// De pagina zelf. Openbaar zodat een toets hem kan bouwen zonder de schil eromheen.
class RutrackerLoginPagina extends StatefulWidget {
  const RutrackerLoginPagina({super.key});

  @override
  State<RutrackerLoginPagina> createState() => _RutrackerLoginPaginaState();
}

class _RutrackerLoginPaginaState extends State<RutrackerLoginPagina> {
  InAppWebViewController? _web;
  String _stand = 'Bezig met laden…';
  bool _klaar = false;

  /// Kijk of de oogst binnen is, en sluit als dat zo is.
  ///
  /// Na élke pagina, niet alleen na het formulier: Cloudflare zet zijn koekje op een tussenpagina
  /// die je zelf nooit ziet, en de aanmelding stuurt daarna nog een keer door.
  Future<void> _kijk() async {
    if (_klaar || !mounted) return;
    final sessie = await _oogst();
    if (sessie == null || !mounted) return;
    setState(() => _stand = sessie.heeftSessie ? 'Aangemeld ✓' : 'Cloudflare doorlopen…');
    if (!sessie.heeftSessie) return;
    _klaar = true;
    // Even laten staan, anders knippert het venster weg vóór je gezien hebt dat het gelukt is.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (mounted) Navigator.of(context).pop(sessie);
  }

  /// De koekjes en het kenmerk van dit venster, samen.
  Future<RtSessie?> _oogst() async {
    final web = _web;
    if (web == null) return null;
    try {
      final koekjes =
          await CookieManager.instance().getCookies(url: WebUri('https://rutracker.org'));
      if (koekjes.isEmpty) return null;
      final kop = koekjes.map((c) => '${c.name}=${c.value}').join('; ');
      // Het ECHTE kenmerk van dit venster, niet een dat wij verzinnen. Daar hangt `cf_clearance`
      // aan vast; zie de uitleg bovenaan dit bestand.
      final ua = await web.evaluateJavascript(source: 'navigator.userAgent');
      return RtSessie(cookie: kop, ua: ua is String ? ua : '');
    } catch (e) {
      // Een platform waar de koekjeslade niet bestaat is geen storing maar een beperking. De
      // plakweg staat er nog.
      debugPrint('RuTracker-venster kon de koekjes niet lezen: $e');
      return null;
    }
  }

  /// Wat er meegegeven wordt als de gebruiker zelf sluit: liever een halve oogst dan niets, zodat de
  /// aanroeper kan zeggen wát er ontbreekt.
  Future<void> _sluitZelf() async {
    final sessie = await _oogst();
    if (mounted) Navigator.of(context).pop(sessie);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aanmelden bij RuTracker'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Sluiten',
          onPressed: _sluitZelf,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(_stand, style: const TextStyle(fontSize: 12)),
            ),
          ),
        ),
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(kRutrackerLoginUrl)),
        initialSettings: InAppWebViewSettings(
          // De koekjes zijn het hele doel van dit venster.
          thirdPartyCookiesEnabled: true,
          javaScriptEnabled: true,
          // NIET zelf een kenmerk opleggen. Zou de app hier iets neerzetten, dan is het weer een
          // half nagemaakte browser — precies waar de 403 vandaan kwam.
          userAgent: '',
        ),
        onWebViewCreated: (c) => _web = c,
        onLoadStop: (_, __) => _kijk(),
        onReceivedError: (_, __, fout) {
          if (mounted) setState(() => _stand = 'Kon de pagina niet laden: ${fout.description}');
        },
      ),
    );
  }
}

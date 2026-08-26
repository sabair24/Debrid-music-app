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

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Waar de aanmelding begint. `login.php` en niet de voorpagina: dan sta je meteen op het formulier.
const kRutrackerLoginUrl = 'https://rutracker.org/forum/login.php';

/// De adressen waar de koekjes van RuTracker onder kunnen staan, van smal naar breed.
///
/// **Dit is de reparatie, en hij is klein en beslissend.** Een koekje hoort bij een pad. RuTracker
/// zet `bb_session` onder `/forum/`, want daar staat het hele forum. Vraag je de koekjeslade om
/// `https://rutracker.org` — dus pad `/` — dan geeft hij dat koekje niet terug: het pad past niet.
///
/// Wat je dan ziet is precies wat er gebeurde: je bent aantoonbaar ingelogd (je naam staat
/// linksboven op de pagina), en het venster blijft zeggen dat het aan het laden is. Er kwam namelijk
/// een lege lijst terug, en een lege lijst was "nog niets".
///
/// Daarom wordt er nu op alle drie gekeken en samengevoegd: het forumpad, de wortel, en het adres
/// waar je op dat moment staat.
const kRutrackerKoekjeUrls = <String>[
  'https://rutracker.org/forum/',
  'https://rutracker.org/',
];

/// Voeg koekjeslijsten samen tot één `Cookie:`-kop, zonder herhaling.
///
/// De eerste waarde die voor een naam binnenkomt wint — de lijsten komen van smal naar breed, en het
/// smalste pad is het meest specifieke. Lege waarden tellen niet mee: die zijn een gewiste koekje.
///
/// Apart en zuiver, zodat er een toets op past zonder toestel en zonder webview.
String voegKoekjesSamen(List<List<({String naam, String waarde})>> lijsten) {
  final gezien = <String, String>{};
  for (final lijst in lijsten) {
    for (final k in lijst) {
      if (k.naam.isEmpty || k.waarde.isEmpty) continue;
      gezien.putIfAbsent(k.naam, () => k.waarde);
    }
  }
  return gezien.entries.map((e) => '${e.key}=${e.value}').join('; ');
}

/// Een `document.cookie`-regel uitpluizen naar losse paren.
///
/// Dat is de tweede bron naast de koekjeslade: op sommige toestellen geeft de lade minder terug dan
/// de pagina zelf ziet. Wat HttpOnly is (zoals `cf_clearance`) staat hier niet in — vandaar dat het
/// een aanvulling is en geen vervanging.
List<({String naam, String waarde})> leesDocumentCookie(String regel) {
  final uit = <({String naam, String waarde})>[];
  for (final deel in regel.split(';')) {
    final m = RegExp(r'^\s*([A-Za-z0-9_\-\.]+)=(.*)$').firstMatch(deel);
    if (m == null) continue;
    uit.add((naam: m.group(1)!, waarde: m.group(2)!.trim()));
  }
  return uit;
}

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
  Timer? _klok;

  /// **Waarom er een klok naast `onLoadStop` staat.** De aanmelding zet het koekje soms zonder dat
  /// er nog een pagina geladen wordt — RuTracker stuurt je door met JavaScript, of Cloudflare doet
  /// zijn ding op dezelfde pagina. Hing het uitsluitend aan `onLoadStop`, dan bleef het venster
  /// staan terwijl je allang binnen was. Twee seconden is ruim genoeg en kost niets.
  @override
  void initState() {
    super.initState();
    _klok = Timer.periodic(const Duration(seconds: 2), (_) => _kijk());
  }

  @override
  void dispose() {
    _klok?.cancel();
    super.dispose();
  }

  /// Kijk of de oogst binnen is, en sluit als dat zo is.
  ///
  /// Na élke pagina, niet alleen na het formulier: Cloudflare zet zijn koekje op een tussenpagina
  /// die je zelf nooit ziet, en de aanmelding stuurt daarna nog een keer door.
  Future<void> _kijk() async {
    if (_klaar || !mounted) return;
    final sessie = await _oogst();
    if (!mounted) return;
    // **Altijd zeggen wat er ligt.** Hier stond een stilzwijgende terugkeer bij een lege oogst, en
    // dat is precies hoe "Bezig met laden…" kon blijven staan terwijl je ingelogd op je eigen
    // profielpagina keek. Een stand die niet meebeweegt met wat er gebeurt is erger dan geen stand.
    final nieuw = sessie == null
        ? 'Nog geen koekje gevonden — log in en tik daarna op Klaar'
        : sessie.heeftSessie
            ? 'Aangemeld ✓'
            : sessie.heeftClearance
                ? 'Cloudflare doorlopen — nu nog inloggen'
                : 'Pagina geladen — log in en tik daarna op Klaar';
    if (nieuw != _stand) setState(() => _stand = nieuw);
    if (sessie == null || !sessie.heeftSessie) return;
    _klaar = true;
    _klok?.cancel();
    // Even laten staan, anders knippert het venster weg vóór je gezien hebt dat het gelukt is.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (mounted) Navigator.of(context).pop(sessie);
  }

  /// De koekjes en het kenmerk van dit venster, samen.
  ///
  /// Drie bronnen, samengevoegd: het forumpad, de wortel, en het adres waar je nu staat — plus
  /// `document.cookie` als aanvulling. Zie [kRutrackerKoekjeUrls] voor waarom dat pad het hele
  /// verschil maakte.
  Future<RtSessie?> _oogst() async {
    final web = _web;
    if (web == null) return null;
    try {
      final lade = CookieManager.instance();
      final adressen = <String>[
        ...kRutrackerKoekjeUrls,
        (await web.getUrl())?.toString() ?? '',
      ];
      final lijsten = <List<({String naam, String waarde})>>[];
      for (final adres in adressen) {
        if (adres.isEmpty || !adres.contains('rutracker')) continue;
        try {
          final koekjes = await lade.getCookies(url: WebUri(adres));
          lijsten.add([
            for (final c in koekjes) (naam: c.name, waarde: '${c.value}'),
          ]);
        } catch (_) {
          // Eén adres dat niets oplevert mag de andere twee niet meenemen.
        }
      }
      // De pagina zelf als aanvulling. Wat HttpOnly is staat hier niet in, dus dit vervangt de lade
      // niet — het vult hem aan op toestellen waar de lade karig is.
      try {
        final regel = await web.evaluateJavascript(source: 'document.cookie');
        if (regel is String && regel.isNotEmpty) lijsten.add(leesDocumentCookie(regel));
      } catch (_) {/* geen document.cookie is geen storing */}

      final kop = voegKoekjesSamen(lijsten);
      if (kop.isEmpty) return null;
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
        actions: [
          // **De uitweg die er niet was.** Ziet het venster je aanmelding om welke reden dan ook
          // niet, dan hoor je niet vast te zitten: hiermee neem je mee wat er ligt en sta je terug
          // in de app. Wat er ontbreekt zegt Instellingen daarna alsnog.
          TextButton.icon(
            onPressed: _sluitZelf,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Klaar'),
          ),
        ],
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

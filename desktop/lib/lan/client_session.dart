/// Running as a client: what `main()` starts instead of a disk scan.
///
/// Keeps the library in step with the PC, and owns the one piece of state the UI branches on —
/// whether this device is paired yet.
library;

import 'dart:async';
import 'dart:io' show InternetAddress, Platform;

import 'package:flutter/foundation.dart';

import '../catalogus_kopie.dart';
import '../library.dart';
import '../paths.dart';
import '../settings.dart';
import '../uploaderberichten.dart' show berichtenVanPc;
import '../warm_log.dart';
import 'client.dart';
import 'discovery.dart';
import 'doorgever.dart';
import 'poorten.dart';
import 'vaste_naam.dart' show kPcHost;
import '../cloud/catalog_mirror.dart';
import 'adreswedloop.dart';
import 'client_mode.dart';
import 'tokens.dart' show toestelWeg;
import 'uitwijk.dart';
import 'verbindingsstand.dart';

class ClientSession extends ChangeNotifier {
  ClientSession({
    required this.library,
    required this.settings,
    required this.owner,
    required this.applyMediaResolver,
    RemoteEndpoint? endpoint,
    this.kopie = const CatalogusKopie(),
    this.verseSleutel,
    this.adressenUitAccount,
    this.hartslagUitAccount,
    Future<List<FoundServer>> Function()? zoekOpNetwerk,
  })  : _endpoint = endpoint,
        _zoekOpNetwerk = zoekOpNetwerk ?? LanBrowser.find;

  /// Hoe er op het lokale netwerk naar de pc gezocht wordt. Standaard [LanBrowser.find]; een toets
  /// zet hier iets anders, want op de pc waar hij draait staat vaak de echte app.
  final Future<List<FoundServer>> Function() _zoekOpNetwerk;

  /// Haalt via het account een nieuwe koppeling op voor deze pc (versleuteld, met beide sleutels en de
  /// pin). Null = niet gelukt.
  ///
  /// Een callback en niet de [CloudSession] zelf, om dezelfde reden als [applyMediaResolver]: deze
  /// klasse hoort niets van Firebase te weten, en een toets voor het koppelen hoort geen cloud op
  /// te tuigen.
  final Future<RemoteEndpoint?> Function(RemoteEndpoint huidig)? verseSleutel;

  /// Een waarschuwing voor op dit toestel: iets wat op misbruik van zijn sleutel wijst (een ruil die een
  /// ander toestel al deed), of een pc die opeens een ander certificaat noemt.
  final ValueNotifier<String?> waarschuwing = ValueNotifier(null);

  /// Voor de toetsen: de ruil zelf. Null = [RemoteClient.ruil].
  @visibleForTesting
  Future<String> Function(RemoteEndpoint huidig)? ruilVoorToets;

  /// Hoogstens één ruil per keer dat de app draait. Lukt hij niet, dan de volgende keer weer.
  bool _ruilGeprobeerd = false;

  final LibraryStore library;
  final AppSettings settings;

  /// How the player is told to turn a library path into a fetchable URL. A callback rather than
  /// the player itself: this class has no other business with playback, and taking the whole store
  /// would drag libmpv into everything that wants to test pairing.
  final void Function(String Function(String path)) applyMediaResolver;

  /// True on the machine that holds the music. Then none of this runs.
  final bool owner;

  RemoteEndpoint? _endpoint;
  RemoteEndpoint? get endpoint => _endpoint;

  /// The app shows its normal self when there is nothing left to ask for.
  bool get ready => owner || _endpoint != null;

  /// The user asked for the old six digits instead of logging in. Kept for the case the login
  /// cannot help with: a network with no internet, and a PC two metres away.
  bool preferPairingCode = false;

  void usePairingCode() {
    preferPairingCode = true;
    notifyListeners();
  }

  /// Set once the first catalogue has landed, so the library screen can say "verbinden…" rather
  /// than "geen muziek gevonden" while it is still on its way.
  bool loading = false;

  /// The last thing that went wrong talking to the PC, for the settings screen.
  String? lastError;

  /// The cloud copy of the library, for when the PC does not answer. Null when not signed in, and
  /// then an unreachable PC means an empty screen exactly as it did before.
  CatalogMirror? mirror;

  /// De kopie op dit toestel zelf, voor als er ook geen internet is.
  ///
  /// De cloudkopie hierboven dekt "pc uit". Deze dekt "pc uit én geen bereik" — de auto, de metro,
  /// het vliegtuig, precies waar offline bewaren voor bedoeld is. Zonder hem stond de muziek wel op
  /// het toestel maar was er geen lijst om hem mee te vinden.
  final CatalogusKopie kopie;

  Timer? _poll;

  /// How the PC calls itself, for the settings screen.
  String get serverName => _endpoint?.name ?? _endpoint?.baseUrl.host ?? '';

  /// WELKE VERSIE ER OP DE PC DRAAIT. Leeg tot de eerste verbinding.
  ///
  /// **Waarom dit op het scherm hoort.** Bij een gekoppeld toestel doet de PC het zoeken én het
  /// downloaden; wat je hier ziet zijn zíjn taken en zíjn foutmeldingen, doorgegeven over het net.
  /// De versie in Instellingen is die van DIT toestel, en die zegt dus niets over de code die het
  /// werk deed.
  ///
  /// Op 27-08-2026 kostte dat drie ronden. Op de Mac stond 3.9.223 — de nieuwste, met de reparatie
  /// erin — en toch verscheen een foutmelding die in die versie niet meer te maken is. Hij kwam van
  /// de pc, die achterliep. Van buitenaf was dat op geen enkele manier te zien: het scherm zei
  /// "Verbonden met je pc — Saber · 1024 nummers" en verder niets.
  ///
  /// `/health` gaf dit al terug (zie `sharing.version`); het werd alleen weggegooid.
  String serverVersie = '';

  /// Het onthouden adres, of een ander adres van dezelfde pc als dat niet meer antwoordt.
  ///
  /// Geeft altijd íets terug — bij twijfel het onthouden adres. Niets vinden is geen reden om de
  /// verbinding niet eens te proberen: de pc kan gewoon uit staan, en dan hoort de app de kopie te
  /// tonen en het later opnieuw te proberen, niet om te vallen.
  ///
  /// De sleutel gaat mee naar het nieuwe adres. Dat is dezelfde pc met dezelfde koppeling; alleen
  /// zijn plek op het netwerk is veranderd.
  ///
  /// **De uitwijkadressen doen het werk als je NIET thuis bent.** Op de baan valt er op het lokale
  /// netwerk niets te vinden — je pc staat daar niet. Wat wél werkt is het adres dat de pc zelf
  /// heeft doorgegeven toen je nog verbonden was: zijn Tailscale-adres. Zie `uitwijk.dart` voor de
  /// volgorde en waarom die zichzelf corrigeert.
  ///
  /// **Sinds 14-10-2026 alle adressen tegelijk** (`adreswedloop.dart`): thuis meteen, Tailscale
  /// 400 ms later, drie seconden per poging, en alleen de pc met de onthouden [RemoteEndpoint.serverId]
  /// telt. Voorheen ná elkaar, met vier seconden per adres: thuis de deur uit kostte eerst een volle
  /// poging op het thuisadres. Het zoeken op het lokale netwerk begint meteen mee en telt pas als de
  /// bekende adressen niets opleveren; daarna nog de adressen die de pc in je account zet
  /// ([adressenUitAccount]).
  Future<RemoteEndpoint> _bereikbaarAdres(RemoteEndpoint onthouden) async {
    try {
      final bekend = weguitVolgorde(
        onthouden: onthouden.baseUrl,
        uitwijk: leesAdressen(onthouden.uitwijk),
      );
      // Begint meteen, telt pas als de bekende adressen niets opleveren.
      final opNetwerk = _zoekOpNetwerk().catchError((Object _) => <FoundServer>[]);
      var uitslag = await _wedloop(bekend, onthouden);

      if (uitslag.winnaar == null) {
        final gevonden = [
          for (final s in await opNetwerk)
            if (!bekend.contains(s.baseUrl) &&
                (onthouden.serverId.isEmpty || s.serverId.isEmpty || s.serverId == onthouden.serverId))
              s.baseUrl,
        ];
        if (gevonden.isNotEmpty) uitslag = await _wedloop(gevonden, onthouden);
      }
      if (uitslag.winnaar == null && adressenUitAccount != null) {
        final uitAccount = [
          for (final u in await adressenUitAccount!(onthouden.serverId).catchError((Object _) => <Uri>[]))
            if (!bekend.contains(u)) u,
        ];
        if (uitAccount.isNotEmpty) uitslag = await _wedloop(uitAccount, onthouden);
      }

      final winnaar = uitslag.winnaar;
      _laatsteWinnaar = winnaar;
      if (winnaar == null) {
        if (!_zoektNaWissel) unawaited(_naMislukken(onthouden.serverId));
        return onthouden;
      }
      _zetStand(Verbindingsstand.verbonden(_wegVoor(winnaar)));
      final id = uitslag.health?.serverId ?? '';
      final vers = onthouden.met(baseUrl: winnaar, serverId: id.isEmpty ? null : id);
      if (vers.baseUrl == onthouden.baseUrl && vers.serverId == onthouden.serverId) return onthouden;
      // Meteen vastleggen, anders staat hier bij de volgende start weer het oude adres — en daarmee
      // elke start op de baan opnieuw die ene mislukte poging.
      await savePairedServer(vers);
      return vers;
    } catch (_) {/* zoeken mag nooit tussen jou en je muziek staan */}
    return onthouden;
  }

  /// Elk adres ook versleuteld (47822) als dit toestel dat kan, en elk versleuteld adres ook gewoon
  /// (47820) als terugval. De wedloop kiest, en versleuteld gaat voor (`adreswedloop.dart`). Stap 8.1.
  List<Uri> _metVersleuteld(RemoteEndpoint e, List<Uri> adressen) {
    final uit = <Uri>[];
    final gezien = <String>{};
    void neem(Uri u) {
      if (gezien.add('${u.scheme}://${u.host}:${u.port}')) uit.add(u);
    }

    for (final u in adressen) {
      if (u.scheme == 'https') {
        if (e.kanVersleuteld) neem(u);
        // De eigen deur naar buiten is alleen versleuteld; thuis en Tailscale hebben ook de gewone.
        if (adresSoort(u) != AdresSoort.anders) neem(u.replace(scheme: 'http', port: kHttpPoort));
      } else {
        if (e.kanVersleuteld) neem(u.replace(scheme: 'https', port: e.tlsPoort > 0 ? e.tlsPoort : kTlsPoort));
        neem(u);
      }
    }
    return uit;
  }

  /// De doorgever voor mpv als er versleuteld gepraat wordt (`doorgever.dart`). Eén per sessie, in een
  /// eigen isolate; pas gestart bij de eerste versleutelde verbinding.
  DoorgeverIsolaat? _doorgever;
  @visibleForTesting
  DoorgeverIsolaat? get doorgever => _doorgever;

  /// De doorgever op [e] richten: versleuteld → (één keer) starten en de pc aanwijzen; anders niets meer
  /// doorgeven. Start hij niet, dan speelt alles via de gewone ingang (zie `RemoteClient.authorized`).
  Future<void> _doorgeverVoor(RemoteEndpoint e) async {
    if (!e.versleuteld) {
      _doorgever?.zetBron(null);
      return;
    }
    final d = _doorgever ??= DoorgeverIsolaat(
      log: _log,
      // De pc antwoordt niet meer op het adres van nu, terwijl mpv wacht: opnieuw kiezen. De doorgever
      // houdt mpv intussen vast en gaat verder zodra er een nieuw adres is.
      storing: () => unawaited(netwerkVeranderd('doorgever: de pc antwoordt niet op ${_endpoint?.baseUrl.authority}')),
      veranderd: (_) => waarschuwing.value = 'Dit nummer veranderde op je pc terwijl het speelde. Start het opnieuw.',
    );
    if (!d.draait) {
      try {
        await d.start();
      } catch (x) {
        _log('doorgever start niet ($x) — stromen via de gewone ingang');
        return;
      }
    }
    d.zetBron(DoorgeverBron(basis: e.baseUrl, sleutel: e.tlsToken, pin: e.pin));
  }

  /// Na het hervatten van de app: leeft de doorgever nog (zie [DoorgeverIsolaat.nakijken]).
  Future<void> doorgeverNakijken() async {
    try {
      await _doorgever?.nakijken();
    } catch (x) {
      _log('doorgever nakijken mislukte: $x');
    }
  }

  /// Een adres van de doorgever terug naar de vaste naam van de pc, of null.
  Uri? _vanDoorgever(Uri u) {
    final d = _doorgever;
    if (d == null || !d.draait || u.host != '127.0.0.1' || u.port != d.poort) return null;
    final s = u.pathSegments;
    if (s.length < 2 || s.first != d.geheim) return null;
    return Uri(scheme: 'http', host: kPcHost, path: '/${s.skip(1).join('/')}', query: u.query.isEmpty ? null : u.query);
  }

  /// Een client voor [e]; versleuteld met de doorgever erbij.
  RemoteClient _clientVoor(RemoteEndpoint e) {
    final d = _doorgever;
    return RemoteClient(e,
        viaDoorgever: e.versleuteld && d != null && d.draait ? d.adresVoor : null, vanDoorgever: _vanDoorgever);
  }

  /// Eén wedloop, met zijn verloop in `verbinding.log`.
  Future<WedloopUitslag> _wedloop(List<Uri> adressen, RemoteEndpoint onthouden) async {
    final uitslag = await adresWedloop(
      kandidatenVoor(_metVersleuteld(onthouden, adressen)),
      vraag: (u, limiet) => RemoteClient.health(u, timeout: limiet, pin: onthouden.pin),
      verwachtServerId: onthouden.serverId,
    );
    for (final r in uitslag.verloop) {
      _log('  wedloop: $r');
    }
    _log('  wedloop: ${uitslag.winnaar == null ? 'geen winnaar' : 'winnaar ${uitslag.winnaar!.authority}'}');
    return uitslag;
  }

  /// De adressen die de pc met deze id in je account zette, voor als geen enkel bekend adres
  /// antwoordt (een nieuw Telenet-adres, een nieuwe Tailscale-naam). Null = geen account op dit
  /// toestel. Zie `main.dart`.
  final Future<List<Uri>> Function(String serverId)? adressenUitAccount;

  /// Wat de pc het laatst in je account schreef (`CloudSession.hartslag`), voor de reden als hij niet
  /// antwoordt. Null = geen account op dit toestel; dan zegt de regel alleen "reageert niet".
  final Future<Hartslag?> Function(String serverId)? hartslagUitAccount;

  /// Of dit toestel zelf geen netwerk heeft (de netwerkwacht in `main.dart`, die pas na deze sessie
  /// gemaakt wordt — vandaar een veld en geen parameter).
  bool Function() geenNetwerk = _nooit;
  static bool _nooit() => false;

  /// Of dit toestel nu alleen mobiele data heeft (geen wifi of kabel). Dan loopt een thuisadres dat
  /// antwoordt via Tailscale (een subnetroute), en heet het "Onderweg — via Tailscale", niet "Thuis".
  /// Gemeten 14-10-2026: op mobiel antwoordde 192.168.0.117, en de regel bovenin zei "Thuis".
  bool Function() opMobiel = _nooit;

  Verbindingsweg _wegVoor(Uri adres) {
    final w = wegNaar(adres);
    return w == Verbindingsweg.thuis && opMobiel() ? Verbindingsweg.tailscale : w;
  }

  /// De weg naar de pc, of waarom die er niet is — voor de regel bovenin. Zie `verbindingsstand.dart`.
  ///
  /// Gezet na elke wedloop (een winnaar: verbonden langs zijn weg; geen: de reden halen) en na elke
  /// poll. Begint op "zoekt": tot de eerste wedloop weet niemand iets.
  Verbindingsstand get verbinding => _stand;
  Verbindingsstand _stand = Verbindingsstand.zoekt(DateTime.now());

  /// Wanneer de regel bovenin even mag zeggen langs welke weg het nu loopt: bij een andere weg dan
  /// daarnet (thuis de deur uit), en na een tijd zonder pc. Niet bij elke start — "Thuis" bij elk
  /// openen van de app is ruis.
  DateTime? wegGewisseld;
  Verbindingsweg? _laatsteWeg;

  /// De weg voor de streamkwaliteit: de huidige, of de laatst bekende terwijl er opnieuw gezocht wordt.
  /// Zie `welkeStand` in netsoort.dart.
  ///
  /// **Via de eigen deur, maar thuis, is thuis** — als de pc dat zegt ([_pcZegtThuis], `bronIsThuis` in
  /// tokens.dart). Saber, 21-10-2026: de Mac op de thuiswifi kreeg The Door als 16/44,1, want hij praatte via
  /// de deur naar buiten met de pc en hield zich dus voor onderweg.
  Verbindingsweg? get wegVoorStroom {
    final w = _stand.weg ?? _laatsteWeg;
    return w == Verbindingsweg.rechtstreeks && _pcZegtThuis == true ? Verbindingsweg.thuis : w;
  }

  /// Kan de pc het taalmodel vragen voor een radio op dit toestel (`radioModel` in `/api/config`, zie
  /// `pc_model.dart`)? Onwaar tot hij het zei — een oudere pc zegt het nooit.
  bool pcHeeftModel = false;

  /// Wat de pc het laatst zei: zit dit toestel op zijn thuisnetwerk (`opHetThuisnet` in `/api/config`)?
  /// Null = (nog) niet gevraagd, of de pc is ouder.
  bool? _pcZegtThuis;

  Future<void> _vraagOfThuis() async {
    final c = library.remote;
    if (c == null) return;
    try {
      _zetThuis((await c.config())['opHetThuisnet']);
    } catch (_) {/* dan blijft het zoals het was */}
  }

  void _zetThuis(String? antwoord) {
    final nieuw = antwoord == null ? null : antwoord == 'ja';
    if (nieuw == _pcZegtThuis) return;
    _pcZegtThuis = nieuw;
    _log('de pc zegt: ${nieuw == null ? "weet niet" : nieuw ? "op het thuisnetwerk" : "niet op het thuisnetwerk"}');
    notifyListeners();
  }
  int _verbondenTeller = 0;

  /// Er was een tijd zonder pc sinds de laatste verbinding. Apart onthouden, want een netwerkwissel
  /// zet de stand eerst op "zoekt" — dan is de stand van daarnet niet meer "weg".
  bool _naGeenPc = false;

  void _zetStand(Verbindingsstand nieuw) {
    final oud = _stand;
    _stand = nieuw;
    if (nieuw.soort == Verbindingssoort.verbonden) {
      _verbondenTeller++;
      final vorige = _laatsteWeg;
      if ((vorige != null && vorige != nieuw.weg) || _naGeenPc) {
        wegGewisseld = DateTime.now();
      }
      _laatsteWeg = nieuw.weg;
      _naGeenPc = false;
    } else if (nieuw.soort == Verbindingssoort.weg) {
      _naGeenPc = true;
    }
    if (oud.zelfde(nieuw)) return;
    _log('stand: $nieuw');
    // Langs de eigen deur verbonden: vragen of dit toestel toch thuis zit (zie [wegVoorStroom]).
    if (nieuw.soort == Verbindingssoort.verbonden && nieuw.weg == Verbindingsweg.rechtstreeks) {
      unawaited(_vraagOfThuis());
    }
    notifyListeners();
  }

  /// Wanneer de reden het laatst bepaald is: hoogstens eens per minuut opnieuw, want het kost een
  /// leesbeurt in je account. Een netwerkwissel en "Opnieuw proberen" zetten de stand eerst op
  /// "zoekt", en dan mag het meteen.
  DateTime? _waaromOm;

  /// Geen enkel adres antwoordde: de hartslag van de pc lezen en zeggen waarom. Loopt hij al, dan
  /// wacht een tweede aanvraag op dezelfde (één leesbeurt).
  Future<void> _naMislukken([String? serverId]) =>
      _waaromBezig ??= _bepaalWaarom(serverId).whenComplete(() => _waaromBezig = null);
  Future<void>? _waaromBezig;

  Future<void> _bepaalWaarom(String? serverId) async {
    final nu = DateTime.now();
    final vorige = _waaromOm;
    if (_stand.soort == Verbindingssoort.weg &&
        vorige != null &&
        nu.difference(vorige) < const Duration(minutes: 1)) {
      return;
    }
    _waaromOm = nu;
    final teller = _verbondenTeller;
    Hartslag? hartslag;
    var onbereikbaar = false;
    final haal = hartslagUitAccount;
    if (haal != null && !geenNetwerk()) {
      try {
        hartslag = await haal(serverId ?? _endpoint?.serverId ?? '').timeout(const Duration(seconds: 8));
      } on HartslagOnbereikbaar {
        onbereikbaar = true;
      } catch (_) {/* niet weten: dan "reageert niet" */}
    }
    // Intussen toch verbonden (een poll die wel lukte), of ontkoppeld: dan geen reden meer.
    if (teller != _verbondenTeller || _endpoint == null) return;
    final waarom = waaromNiet(hartslag: hartslag, geenNetwerk: onbereikbaar || geenNetwerk());
    final bij = hartslag?.bijgewerkt;
    final serverNu = hartslag?.serverNu;
    _log('waarom niet: ${waarom.name}'
        '${hartslag == null ? '' : ' (hartslag ${hartslag.online ? 'aan' : 'uit'}'
            '${bij == null || serverNu == null ? '' : ', ${serverNu.difference(bij).inSeconds} s oud'})'}');
    _zetStand(Verbindingsstand.weg(waarom));
  }

  /// De poll kreeg niets van de pc: zoeken, en lukt dat nu niet (te snel na de vorige keer), dan
  /// tenminste de reden.
  void _pcStil() {
    if (_stand.soort == Verbindingssoort.verbonden) _zetStand(Verbindingsstand.zoekt(DateTime.now()));
    unawaited(_zoekAnderAdres().then((liep) {
      if (!liep && !_zoekt) unawaited(_naMislukken());
    }));
  }

  /// Vragen waar deze pc nog meer te bereiken is, en dat bewaren voor de dag dat je weggaat.
  ///
  /// Loopt náást het inladen van de bibliotheek: het antwoord is pas nodig bij een vólgende start,
  /// dus het mag nooit tussen jou en je muziek staan.
  ///
  /// **Een leeg antwoord wist niets.** Een pc van vóór deze weg geeft 404, een pc die net omvalt
  /// geeft niets — allebei komen hier aan als een lege lijst, en die betekent "ik weet het niet",
  /// niet "er zijn er geen". Wat er stond blijft dan staan; dat is het adres waarmee je op de baan
  /// binnenkomt.
  ///
  /// **En niet na het ontkoppelen.** Dit loopt los, dus het antwoord kan binnenkomen nadat je de pc
  /// liet vergeten — en dan schreef het de koppeling gewoon opnieuw weg (client_session_test, rood
  /// op 11-10-2026). Daarom kijkt deze beurt vóór het schrijven of de koppeling nog dezelfde is
  /// ([_koppelRonde], omhoog bij elk [connect] en [unpair]), en wacht [unpair] een beurt die al aan
  /// het schrijven is nog even af.
  Future<void> _onthoudUitwijk(RemoteClient client, RemoteEndpoint endpoint) =>
      _uitwijkBezig = _onthoudUitwijkNu(client, endpoint, _koppelRonde);

  Future<void> _onthoudUitwijkNu(RemoteClient client, RemoteEndpoint endpoint, int ronde) async {
    try {
      final u = await client.uitwijk();
      if (ronde != _koppelRonde) return;
      // Voortbouwen op de koppeling van NU, niet op die van het begin van [connect]: intussen kan de
      // id van de pc geleerd zijn (zie [connect]), en die mag deze beurt niet weer wegschrijven.
      final basis = _endpoint ?? endpoint;
      var bij = basis;
      var veranderd = false;
      // Een leeg antwoord wist niets; en op waarde vergelijken, niet met `==`: twee lijsten met dezelfde
      // inhoud zijn niet hetzelfde object, en dan zou er bij elke start naar schijf geschreven worden.
      if (u.urls.isNotEmpty && u.urls.join('\n') != basis.uitwijk.join('\n')) {
        bij = bij.met(uitwijk: u.urls);
        veranderd = true;
      }
      // De pin van het certificaat, hier geleerd: over 47820, en dat neemt alleen thuis en Tailscale aan.
      // Eenmaal bekend wordt hij nooit stil vervangen — een andere pin is precies wat een tussenpersoon
      // zou sturen. Dan een waarschuwing, en de versleutelde weg blijft dicht tot je opnieuw koppelt.
      if (u.pin.isNotEmpty) {
        if (basis.pin.isEmpty) {
          bij = bij.met(pin: u.pin, tlsPoort: u.tlsPoort > 0 ? u.tlsPoort : null);
          veranderd = true;
          _log('pin van de pc geleerd: ${u.pin.substring(0, 12)}…');
        } else if (basis.pin != u.pin) {
          _log('LET OP: de pc noemt een ander certificaat (${u.pin.substring(0, 12)}…) dan bekend '
              '(${basis.pin.substring(0, 12)}…) — niet overgenomen');
          waarschuwing.value = 'Je pc noemt een ander certificaat dan dit toestel kent. Is DebridMusic op je pc '
              'opnieuw geïnstalleerd, koppel dan opnieuw; anders klopt er iets niet op je netwerk.';
        } else if (u.tlsPoort > 0 && u.tlsPoort != basis.tlsPoort) {
          bij = bij.met(tlsPoort: u.tlsPoort);
          veranderd = true;
        }
      }
      if (veranderd) {
        _endpoint = bij;
        await savePairedServer(bij);
      }
      await _misschienRuilen(ronde);
    } catch (_) {/* volgende keer weer */}
  }

  /// De eenmalige ruil (stap 5.6): zodra dit toestel de pin kent en nog geen versleutelde sleutel heeft,
  /// vanzelf, thuis of via Tailscale. De versleutelde sleutel wordt bewaard naast de gewone en pas
  /// gebruikt als de app op de versleutelde weg overgaat.
  ///
  /// **Een 409** betekent dat een ander toestel deze sleutel al omruilde: iemand had hem. Dan een
  /// waarschuwing, en opnieuw koppelen via het account — dat geeft dit toestel een eigen, nieuwe sleutel.
  Future<void> _misschienRuilen(int ronde) async {
    final e = _endpoint;
    if (e == null || owner || e.pin.isEmpty || e.tlsToken.isNotEmpty || _ruilGeprobeerd) return;
    final ip = InternetAddress.tryParse(e.baseUrl.host);
    if (ip != null && toestelWeg(ip) == 'buiten') return;
    _ruilGeprobeerd = true;
    try {
      final tls = await (ruilVoorToets ?? RemoteClient.ruil)(e);
      final nu = _endpoint;
      if (ronde != _koppelRonde || nu == null) return;
      final met = nu.met(tlsToken: tls);
      _endpoint = met;
      await savePairedServer(met);
      _log('versleutelde sleutel ontvangen (ruil)');
    } on RemoteException catch (x) {
      _log('ruil mislukte: ${x.message}');
      if (x.statusCode == 403) {
        // Dit toestel gebruikt nog de GEDEELDE sleutel (gekoppeld vóór er sleutels per toestel waren). Die kan
        // nooit omgeruild worden — hij staat leesbaar in elke cast-URL. Dus een eigen koppeling halen via je
        // account, versleuteld over 47822 met de net geleerde pin: dat geeft een eigen sleutel én een TLS-sleutel.
        // Gemeten 14-10-2026: Sabers gsm had nog de gedeelde sleutel, en de ruil werd (terecht) geweigerd.
        _log('dit toestel heeft nog de gedeelde sleutel — een eigen koppeling halen via je account');
        _sleutelGevraagd = false;
        unawaited(_vernieuwSleutel(waarom: 'eigen sleutel in plaats van de gedeelde'));
      }
      if (x.statusCode == 409) {
        waarschuwing.value = 'De sleutel van dit toestel werd al door een ander toestel omgeruild. Trek die '
            'sleutel in op je pc. Dit toestel koppelt nu opnieuw via je account.';
        _sleutelGevraagd = false;
        unawaited(_vernieuwSleutel(waarom: 'de ruil was al door een ander toestel gedaan'));
      }
    }
  }

  /// Wat dit toestel met zijn pc deed: met welk adres het verbond, wanneer de pc niet antwoordde of
  /// de sleutel weigerde, welke adressen het daarna probeerde en waar het op overstapte.
  ///
  /// **Waarom dit er is.** Op 06-10-2026 kwam Sabers telefoon op 5G niet meer bij de pc, met
  /// Tailscale aan, en koppelen lukte alleen nog met een code via Chrome Remote Desktop. Op de pc
  /// stond van 07:51 tot 08:22 geen enkele aanvraag; op de telefoon stond nergens iets, want alles
  /// ging naar `debugPrint`, en dat verdwijnt in een vrijgegeven versie. Een sleutel staat er nooit
  /// in, hooguit de eerste vier tekens.
  ///
  /// Het pad wordt elke regel opnieuw bepaald en niet onthouden: [logDir] wordt bij het opstarten
  /// pas vastgelegd, en een vroeg onthouden pad zou dan naar de verkeerde map wijzen.
  static void _log(String regel) {
    try {
      WarmLog('$logDir${Platform.pathSeparator}verbinding.log').line(regel);
    } catch (_) {/* een logboek mag de verbinding nooit in de weg zitten */}
    debugPrint(regel);
  }

  /// De laatst gemelde toestand, zodat een poll die elke vijftien seconden hetzelfde ziet het
  /// logboek niet vult.
  String _gemeld = '';
  void _meldToestand(String toestand) {
    if (toestand == _gemeld) return;
    _gemeld = toestand;
    _log(toestand);
  }

  /// Wanneer er voor het laatst naar een ander adres gezocht is, en of dat nu loopt.
  DateTime? _laatstGezocht;
  bool _zoekt = false;

  /// Of er nu een zoektocht loopt. Voor toetsen: het logboek is daar geen maat, want een sessie van
  /// een vorige toets die nog zoekt, schrijft in hetzelfde bestand.
  @visibleForTesting
  bool get zoektNu => _zoekt;

  /// De pc antwoordt niet op het adres dat we hebben: de andere adressen afgaan en overstappen op
  /// het eerste dat wél antwoordt.
  ///
  /// **Waarom dit er moest komen.** [_bereikbaarAdres] draaide alleen bij een KOUDE start. Een app die
  /// thuis gestart is, verbindt met het thuisadres en blijft dat daarna elke vijftien seconden
  /// proberen — ook als je de deur uit bent en op 5G zit, waar dat adres per definitie niets is. Het
  /// Tailscale-adres stond klaar in [RemoteEndpoint.uitwijk] en werd nooit geprobeerd tot je de app
  /// helemaal afsloot. Gemeten op 06-10-2026: geen enkele aanvraag bij de pc tussen 07:51 en 08:22,
  /// terwijl Tailscale aan stond en de pc via Tailscale gewoon antwoordde.
  ///
  /// Hooguit eens per halve minuut, want een pc die écht uit staat hoort niet elke poll een rondje
  /// adressen te kosten. [refreshNow] — "Opnieuw proberen" en terugkomen in de app — mag meteen.
  Future<bool> _zoekAnderAdres({bool meteen = false}) async {
    final huidig = _endpoint;
    if (huidig == null || owner) return false;
    if (_zoekt) {
      // Er loopt al een zoektocht. Een tik op "Opnieuw proberen" mag die laten zien; de uitkomst
      // komt van die zoektocht zelf (zie [_naZoeken]).
      if (meteen) _zetStand(Verbindingsstand.zoekt(DateTime.now()));
      return false;
    }
    final nu = DateTime.now();
    final vorige = _laatstGezocht;
    if (!meteen && vorige != null && nu.difference(vorige) < const Duration(seconds: 30)) return false;
    _laatstGezocht = nu;
    _zoekt = true;
    // Een tik op "Opnieuw proberen" hoort te zien dat er iets gebeurt; een herhaling elke halve
    // minuut terwijl de reden er al staat niet — dat zou flikkeren.
    if (meteen || _stand.soort == Verbindingssoort.verbonden) _zetStand(Verbindingsstand.zoekt(nu));
    try {
      _log('pc antwoordt niet op ${huidig.baseUrl.authority} — andere adressen proberen'
          ' (${huidig.uitwijk.length} uitwijk)');
      final ander = await _bereikbaarAdres(huidig);
      if (ander.baseUrl == huidig.baseUrl) {
        _log('geen ander adres antwoordt; blijft op ${huidig.baseUrl.authority}');
        return true;
      }
      _log('overgestapt op ${ander.baseUrl.authority}');
      // Via [connect], zodat de speler, de catalogus en het peilen het nieuwe adres krijgen.
      await connect(ander);
      return true;
    } finally {
      _zoekt = false;
      _naZoeken();
    }
  }

  /// Het toestel wisselde van netwerk (`netwerkwissel.dart`): meteen opnieuw kiezen, en altijd met
  /// een VERSE verbinding — ook als het adres hetzelfde blijft.
  ///
  /// **Waarom vers.** De open verbindingen van het netwerk dat net weg is, blijven in de client
  /// hangen; een volgend verzoek gaat daarover en wacht dertig seconden op niets. Dat was het
  /// grootste deel van de "30 tot 45 seconden" na de voordeur. Een lopend nummer merkt hier niets
  /// van: mpv heeft zijn eigen verbinding, en het volgende nummer krijgt het nieuwe adres.
  Future<void> netwerkVeranderd(String waarom) async {
    final huidig = _endpoint;
    if (owner || huidig == null) return;
    if (_zoekt) {
      // Niet weggooien: de zoektocht die nu loopt begon op het netwerk van daarnet, en kan dus niets
      // gevonden hebben op het nieuwe. Zonder deze tweede beurt bleef de app dan tot de volgende
      // poll-zoektocht (hoogstens eens per halve minuut) op "geen pc" staan.
      _wisselWacht = waarom;
      _log('netwerk gewisseld ($waarom) — er wordt al gekozen; daarna opnieuw');
      return;
    }
    final herkansing = waarom.startsWith('herkansing');
    if (!herkansing) {
      _wisselBegon = DateTime.now();
      _wisselWaarom = waarom;
    }
    _zoekt = true;
    try {
      _log('netwerk gewisseld ($waarom) — opnieuw kiezen');
      // De seconden tellen vanaf de wissel zelf, ook over de herkansingen heen.
      _zetStand(Verbindingsstand.zoekt(_wisselBegon ?? DateTime.now()));
      final beste = await _bereikbaarAdres(huidig);
      if (_endpoint != huidig) return; // intussen ontkoppeld of elders verbonden
      if (_laatsteWinnaar == null) {
        // NIET verbinden met een adres dat net niet antwoordde: dat verzoek hangt tot de time-out (30 s)
        // en hield het zoeken zo lang vast. Gemeten 14-10-2026: Tailscale had na wifi → mobiel 8 tot 12 s
        // nodig, en de app zat dan vast op het thuisadres. Nu elke [herkansingNaWissel] opnieuw, tot
        // [zoekNaWissel] na de wissel; pas daarna de reden.
        if (_zoektNaWissel) {
          Timer(herkansingNaWissel, () {
            if (_endpoint == null || _stand.soort == Verbindingssoort.verbonden) return;
            unawaited(netwerkVeranderd('herkansing na: ${_wisselWaarom ?? waarom}'));
          });
        } else {
          _wisselBegon = null;
          _log('na ${zoekNaWissel.inSeconds} s zoeken nog geen pc');
          unawaited(_naMislukken(huidig.serverId));
        }
        return;
      }
      _wisselBegon = null;
      final oud = library.remote;
      _log(beste.baseUrl == huidig.baseUrl
          ? 'blijft op ${beste.baseUrl.authority}, met een verse verbinding'
          : 'overgestapt op ${beste.baseUrl.authority}');
      await connect(beste);
      // De oude client pas na even dicht: wat er nog liep, is op een verdwenen netwerk toch verloren,
      // maar een verzoek dat net klaar was hoort zijn antwoord nog te kunnen lezen.
      if (oud != null && !identical(oud, library.remote)) {
        Timer(const Duration(seconds: 5), oud.close);
      }
    } finally {
      _zoekt = false;
      _naZoeken();
    }
  }

  /// Een netwerkwissel die binnenkwam terwijl er al gezocht werd.
  String? _wisselWacht;

  /// Wie de laatste wedloop won (null = niemand). Voor de herkansing na een netwerkwissel.
  Uri? _laatsteWinnaar;

  /// Wanneer de laatste echte netwerkwissel begon (niet een herkansing), en waarom. Null als er na die
  /// wissel al een pc gevonden is of het zoeken opgegeven.
  DateTime? _wisselBegon;
  String? _wisselWaarom;

  /// Hoe lang er na een netwerkwissel gezocht wordt voor er een reden op het scherm komt.
  @visibleForTesting
  Duration zoekNaWissel = const Duration(seconds: 20);

  bool get _zoektNaWissel {
    final b = _wisselBegon;
    return b != null && DateTime.now().difference(b) < zoekNaWissel;
  }

  /// Hoe lang er na een netwerkwissel zonder winnaar gewacht wordt op de volgende poging.
  ///
  /// **Waarom.** Gemeten 14-10-2026, wifi uit en mobiel erbij: Tailscale had ruim drie seconden nodig
  /// om de weg op het nieuwe netwerk te vinden, en de wedloop gaf er na drie seconden de brui aan. Pas de
  /// volgende poll (tot vijftien seconden later) vond hem dan. Eén herkansing na een seconde vangt dat.
  @visibleForTesting
  Duration herkansingNaWissel = const Duration(seconds: 1);

  /// Na elke zoektocht: een wissel die intussen binnenkwam alsnog afhandelen, en anders nooit op
  /// "zoekt" blijven staan — dan de reden halen.
  void _naZoeken() {
    final wissel = _wisselWacht;
    if (wissel != null) {
      _wisselWacht = null;
      unawaited(netwerkVeranderd('$wissel, na de lopende keuze'));
      return;
    }
    if (_stand.soort == Verbindingssoort.zoekt && !_zoektNaWissel) unawaited(_naMislukken());
  }

  /// Een regel in `verbinding.log`, voor wie naast deze klasse iets over de verbinding te zeggen
  /// heeft (de netwerkwacht in `main.dart`).
  static void logRegel(String regel) => _log(regel);

  /// Hoe vaak [connect] liep. Voor de toetsen: na een netwerkwissel zonder winnaar hoort er níet
  /// verbonden te worden met het adres dat net niet antwoordde.
  @visibleForTesting
  int verbindBeurten = 0;

  /// Wire an endpoint into the app and pull the library in.
  Future<void> connect(RemoteEndpoint endpoint,
      {bool remember = true, Future<void> Function()? zodraErIetsStaat}) async {
    verbindBeurten++;
    // Een ONTHOUDEN adres wordt eerst nagekeken; een vers gekoppeld adres niet.
    //
    // **Waarom dat verschil er moest komen.** Het inlogscherm loopt élk adres af dat de pc publiceert
    // en neemt alleen dat wat antwoordt — een pc met een VPN of Hyper-V heeft er meerdere, en alleen
    // dit toestel weet welke het kan bereiken. Het opstartpad deed dat niet: het pakte blind wat er
    // in `paired_server.json` stond, van de dag dat je koppelde.
    //
    // Verandert dat adres — een ander subnet, een nieuwe lease, een VPN die aan of uit ging — dan
    // mislukt alles stil. De catalogus komt dan uit de kopie op dit toestel, dus je ziet je albums
    // met de juiste namen, maar elke hoes wordt bij een adres opgehaald dat niemand opneemt. Dat is
    // exact het beeld: titels goed, vakjes leeg. En opnieuw inloggen hielp permanent, want dán werd
    // er wél gezocht.
    // **Eerst wat op dit toestel ligt, vóór er één verzoek naar de pc gaat — ook vóór de
    // adrescontrole hieronder**, die bij een zwijgende pc zelf 4 tot 15 seconden wacht. Saber op 11-10-2026:
    // *"op men gsm bij de cold start, laadt de home page met recent toegevoegd enzo verder heel
    // traag"*. In `verbinding.log` van de gsm: 12:43:47 "verbinden met", 12:44:17 "pc antwoordt" —
    // precies dertig seconden, de time-out van één verzoek. De pc-app draaide nog niet, en Windows
    // laat een verzoek aan een dichte poort onbeantwoord in plaats van het te weigeren. De kopie van
    // de catalogus op dit toestel kwam pas NA die dertig seconden op het scherm (in [_refresh]), en
    // tot dan was de startpagina leeg. Met de pc aan gemeten: eerste beeld na 0,24 s, startpagina met
    // hoezen na 2,1 s — het wachten zat alleen in het wachten op een pc die niet antwoordt.
    //
    // [zodraErIetsStaat] (de wachtrij herstellen) mag dan ook meteen: zijn paden wijzen naar de pc en
    // passen op de kopie net zo goed. Zonder dit bleef de spelerbalk even lang leeg als de startpagina.
    // Een nieuwe koppeling: een uitwijk-beurt van de vorige schrijft er niet meer overheen.
    _koppelRonde++;
    var gemeld = false;
    Future<void> meld() async {
      final haak = zodraErIetsStaat;
      if (gemeld || haak == null) return;
      gemeld = true;
      await haak();
    }

    // Met het ONTHOUDEN adres: de paden van de kopie wijzen naar de pc. Blijkt hieronder een ander
    // adres te werken, dan vervangt de catalogus van de pc deze kopie, met de goede paden.
    RemoteClient? voorlopig;
    if (library.tracks.isEmpty) {
      await _doorgeverVoor(endpoint);
      voorlopig = _clientVoor(endpoint);
      library.remote = voorlopig;
      applyMediaResolver(voorlopig.authorized);
      if (await _toonEigenKopie()) unawaited(meld());
    }

    // Ook bij een verse koppeling als er nog "zoekt" staat: anders telt de regel vanaf het moment dat
    // deze sessie gemaakt werd, en wie vijf minuten op het koppelscherm zat, zag "Zoekt je pc… 300 s".
    if (!remember || _stand.soort == Verbindingssoort.zoekt) _zetStand(Verbindingsstand.zoekt(DateTime.now()));
    final werkend = remember ? endpoint : await _bereikbaarAdres(endpoint);
    endpoint = werkend;
    _endpoint = endpoint;
    _gemeld = '';
    _log('verbinden met ${endpoint.baseUrl.authority}'
        ' (sleutel ${endpoint.token.length >= 4 ? endpoint.token.substring(0, 4) : '?'}…,'
        ' ${endpoint.uitwijk.length} uitwijk)');
    if (remember) await savePairedServer(endpoint);

    // Wie er aan de andere kant staat, en met welke code. Zie [serverVersie]: bij een koppeling doet
    // de pc het werk, dus zijn versie is de versie die telt.
    final ronde = _koppelRonde;
    unawaited(RemoteClient.health(endpoint.baseUrl, pin: endpoint.pin).then((h) async {
      if (h == null) return;
      if (h.version.isNotEmpty) {
        serverVersie = h.version;
        notifyListeners();
      }
      // Welke pc dit is, onthouden voor de volgende wedloop (`adreswedloop.dart`). Alleen als hij
      // nog niet bekend is, en alleen als deze koppeling nog dezelfde is.
      final huidig = _endpoint;
      if (h.serverId.isEmpty || huidig == null || huidig.serverId.isNotEmpty || ronde != _koppelRonde) return;
      final met = huidig.met(serverId: h.serverId);
      _endpoint = met;
      await savePairedServer(met);
      _log('pc herkend als ${h.serverId}');
    }).catchError((_) {/* niet weten is geen reden om niet te verbinden */}));

    await _doorgeverVoor(endpoint);
    final client =
        voorlopig != null && voorlopig.endpoint == endpoint ? voorlopig : _clientVoor(endpoint);
    // Waar deze pc nog meer te bereiken is, voor de dag dat dit adres niet meer werkt. Zie
    // [_onthoudUitwijk] — bewust niet afgewacht.
    unawaited(_onthoudUitwijk(client, endpoint));
    library.remote = client;
    // Playing a track means fetching it from the PC, which needs the token — added here, at the
    // last moment, rather than being baked into every stored path.
    applyMediaResolver(client.authorized);
    notifyListeners();

    // The keys the PC is willing to share, so this device can look a record up itself instead of
    // asking the PC for every lookup. Applied in memory and deliberately NOT saved: it is fetched
    // fresh on every connect, so nothing is written to this device's disk, changing a token on the
    // PC reaches here by itself, and unpairing takes it with it.
    //
    // **Niet meer afgewacht.** Ze zijn voor het opzoeken van platen, niet voor de catalogus, en hier
    // stond `await`: een pc die niet antwoordde hield zo de hele start dertig seconden op.
    final sleutels = client.config().then((shared) {
      _zetThuis(shared['opHetThuisnet']);
      pcHeeftModel = shared['radioModel'] == 'ja';
      final discogs = shared['discogsToken'] ?? '';
      final lastfm = shared['lastfmKey'] ?? '';
      final audiodb = shared['audiodbKey'] ?? '';
      if (discogs.isNotEmpty) settings.discogsToken = discogs;
      if (lastfm.isNotEmpty) settings.lastfmKey = lastfm;
      if (audiodb.isNotEmpty) settings.audiodbKey = audiodb;
    });

    loading = true;
    notifyListeners();
    await _refresh(first: true);
    loading = false;
    notifyListeners();

    // Covers after the grid is on screen, not before it.
    unawaited(library.loadRemoteCovers(settings));
    _startPolling();
    await meld();
    // De sleutels zijn er doorgaans al; een pc die niet antwoordde heeft hier al zijn time-out gehad.
    await sleutels.timeout(const Duration(seconds: 2), onTimeout: () {});
  }

  /// Hoogstens één keer per zitting een nieuwe sleutel halen.
  ///
  /// **Waarom hoogstens één keer.** Deze poll draait elke vijftien seconden. Zonder deze klep zou
  /// een pc die je toestel écht heeft ingetrokken elke vijftien seconden een nieuw verzoek in
  /// Firestore krijgen, voor altijd. Eén poging per keer dat de app draait is genoeg: helpt het
  /// niet, dan is er iets aan de hand waar een herhaling niets aan verandert, en dan staat de knop
  /// "Opnieuw koppelen" in de meldingsbalk klaar.
  /// Welke koppeling er nu geldt. Een losse [_onthoudUitwijk] van een vorige schrijft niets meer weg.
  int _koppelRonde = 0;

  /// De lopende [_onthoudUitwijk], die [unpair] even afwacht voor hij de koppeling wist.
  Future<void>? _uitwijkBezig;

  bool _sleutelGevraagd = false;

  Future<void> _vernieuwSleutel({String? waarom}) async {
    final haal = verseSleutel;
    final huidig = _endpoint;
    if (haal == null || huidig == null || _sleutelGevraagd) return;
    // VÓÓR de await. Anders start elke poll er nog een terwijl de eerste nog wacht.
    _sleutelGevraagd = true;
    // Hardop, want op 11-09-2026 ging dit stil: de Shield werd elke vijftien seconden geweigerd, het
    // herstel kreeg niets terug, en in het logboek stond er geen woord over.
    _log('${waarom ?? 'sleutel geweigerd door ${huidig.baseUrl.host}'} — een nieuwe halen…');
    RemoteEndpoint? verse;
    try {
      verse = await haal(huidig);
    } catch (e) {
      _log('verse sleutel halen mislukte: $e');
      return;
    }
    // Dezelfde sleutel terug betekent dat de pc hem nooit had ingetrokken maar kwijt was; opnieuw
    // verbinden lost dat niet op en zou alleen het scherm laten knipperen.
    if (verse == null || verse.token.isEmpty || verse.token == huidig.token) {
      _log('geen nieuwe sleutel gekregen; "Opnieuw proberen" probeert het nog eens');
      return;
    }
    _log('nieuwe sleutel van ${huidig.baseUrl.host} — opnieuw verbinden');
    // Via `connect` en niet met de hand: die legt hem vast, hangt de client aan de bibliotheek,
    // vertelt de speler hoe hij een pad ondertekent en haalt de catalogus opnieuw op. Dat met de
    // hand overdoen is precies hoe je er één vergeet.
    //
    // De uitwijkadressen gaan mee. Een nieuwe sleutel is geen nieuwe pc: zijn Tailscale-adres is
    // hetzelfde gebleven, en dat is het adres waarmee je buitenshuis binnenkomt. Hier stond een
    // `RemoteEndpoint` zonder, en dan was dat adres na het herstel weg — net als de id van de pc,
    // tot 14-10-2026. Nu de hele koppeling: beide nieuwe sleutels, en de pin (geleerd of al bekend).
    await connect(huidig.met(
      token: verse.token,
      tlsToken: verse.tlsToken,
      pin: verse.pin.isEmpty ? null : verse.pin,
      tlsPoort: verse.tlsPoort > 0 ? verse.tlsPoort : null,
    ));
  }

  /// Forget the PC and go back to the pairing screen.
  Future<void> unpair() async {
    _log('pc vergeten (door de gebruiker)');
    _poll?.cancel();
    _poll = null;
    // Eerst de ronde om, zodat een laat uitwijk-antwoord niets meer wegschrijft, en een beurt die al
    // aan het schrijven is even afwachten — anders zet die de koppeling na het wissen hieronder terug.
    // Begrensd: een pc die niet antwoordt mag de knop "Ontkoppelen" niet laten hangen. Zie
    // [_onthoudUitwijk].
    _koppelRonde++;
    await _uitwijkBezig?.timeout(const Duration(seconds: 3), onTimeout: () {}).catchError((_) {});
    await forgetPairedServer();
    // The PC's key does not stay behind after you tell the app to forget the PC.
    //
    // And it is WRITTEN, not merely dropped from memory. "Nothing was written to disk" was only
    // true for a device that had never pressed Save in Settings — the dialog is not owner-only, and
    // its Save button writes the token this device was handed. Clearing without saving left the
    // real token on disk and two blanks in memory, waiting for some unrelated save to persist them.
    settings.discogsToken = '';
    settings.lastfmKey = '';
    settings.audiodbKey = '';
    await settings.save();
    // En de inhoudsopgave van die pc gaat mee. Wie zegt "vergeet die pc" bedoelt niet "maar hou de
    // lijst van mijn muziek nog even".
    await kopie.wis();
    library.laatsteCatalogusBytes = null;
    library.remote = null;
    applyMediaResolver((p) => p);
    _doorgever?.zetBron(null);
    _endpoint = null;
    notifyListeners();
  }

  /// Ask the PC for anything new. Cheap: the ETag means an unchanged library costs a 304.
  Future<void> _refresh({bool first = false}) async {
    try {
      final changed = await library.loadRemote(quiet: !first);
      // Alleen wissen als het ECHT lukte. `loadRemote` gooit niet — hij geeft `false` terug en zet
      // de reden op de winkel. Dit stond er onvoorwaardelijk, dus `lastError` was altijd null en het
      // instellingenscherm bleef groen terwijl elke poll een 401 kreeg.
      if (library.geenVerbinding == null) {
        lastError = null;
        _meldToestand('pc antwoordt op ${_endpoint?.baseUrl.authority}');
        final e = _endpoint;
        if (e != null) _zetStand(Verbindingsstand.verbonden(_wegVoor(e.baseUrl)));
      } else {
        _meldToestand(library.geenVerbinding == GeenVerbinding.sleutelGeweigerd
            ? 'sleutel geweigerd door ${_endpoint?.baseUrl.authority}'
            : 'pc antwoordt niet op ${_endpoint?.baseUrl.authority}');
        // Niet afwachten, net als het sleutelherstel hieronder: een rondje adressen kost seconden.
        if (library.geenVerbinding == GeenVerbinding.pcStil) _pcStil();
        // Een geweigerde sleutel is wél een pc die antwoordt: de weg is er, de melding gaat over de sleutel.
        final e = _endpoint;
        if (library.geenVerbinding == GeenVerbinding.sleutelGeweigerd && e != null) {
          _zetStand(Verbindingsstand.verbonden(_wegVoor(e.baseUrl)));
        }
        lastError = library.geenVerbinding == GeenVerbinding.sleutelGeweigerd
            ? 'De pc antwoordt, maar weigert de sleutel van dit toestel.'
            : 'De pc antwoordde niet.';
        // Een geweigerde sleutel probeert zichzelf te vervangen. NIET afwachten: het toekennen loopt
        // over de hartslag van de pc en duurt tientallen seconden, en zolang blijft deze poll -- en
        // daarmee je hele scherm -- niet staan wachten.
        if (library.geenVerbinding == GeenVerbinding.sleutelGeweigerd) {
          unawaited(_vernieuwSleutel());
        }
      }
      if (changed && !first) {
        // New records may have arrived; only the ones without a cover are fetched.
        unawaited(library.loadRemoteCovers(settings));
      }
      if (library.geenVerbinding == null) unawaited(_haalBerichten());
      // Vers van de pc: leg hem vast op dit toestel. Alleen als er ECHT iets veranderd is — een
      // poll die 304 krijgt hoeft geen bestand van megabytes opnieuw weg te schrijven, en dat
      // gebeurt hier elke vijftien seconden.
      // De BYTES, niet de ontlede vorm. Zie [CatalogusKopie.bewaarBytes]: terugcoderen is
      // `jsonEncode` over megabytes op de tekendraad, en dat gebeurde hier elke keer dat er iets
      // veranderd was — tijdens een download dus om de vijftien seconden.
      final vers = library.laatsteCatalogusBytes;
      if (changed && vers != null) unawaited(kopie.bewaarBytes(vers));
      // Ook de kopie tonen als de pc weigert. "Er staan geen nummers in de lijst" was de vervanger
      // voor "de pc doet het niet", en die twee lopen uiteen zodra er ooit iets geladen is: dan blijft
      // een lijst staan waar je op kunt tikken en die stil niets doet.
      if (library.tracks.isEmpty || library.geenVerbinding != null) await _fillFromMirror();
    } catch (e) {
      lastError = e.toString();
      _meldToestand('pc antwoordt niet: $e');
      _pcStil();
      // The PC did not answer. Show the cloud copy rather than nothing — you can browse, and put
      // downloads in the queue for when it wakes up.
      await _fillFromMirror();
    }
  }

  /// De kopie van de catalogus op dit toestel op het scherm, als die er is en het scherm nog leeg is
  /// (of zelf een kopie toont). Geen netwerk, dus meteen. True als hij er nu staat.
  Future<bool> _toonEigenKopie() async {
    final eigen = await kopie.lees();
    if (eigen == null ||
        !library.adoptMirror(eigen.json, updatedAt: eigen.bijgewerkt, vanToestel: true)) {
      return false;
    }
    // Ook hier de hoezen, want die staan in de cache op dit toestel. Zonder deze aanroep is het een
    // raster van lege vakjes, en dat leest als een kapotte bibliotheek in plaats van als een pc die
    // uit staat.
    unawaited(library.loadRemoteCovers(settings));
    notifyListeners();
    return true;
  }

  /// Fall back to a copy. Only ever fills an empty screen: [adoptMirror] refuses to replace a live
  /// library, so this cannot turn a playable one unplayable.
  ///
  /// **Eerst wat op dit toestel ligt, dan pas de cloud.** Die volgorde is de hele reden dat dit
  /// bestaat. De kopie op het toestel kost geen netwerk en is er dus ook in de auto; de cloudkopie
  /// is vaak verser maar vraagt internet, en juist als dat er niet is heb je die lijst nodig. Wat
  /// hier ligt wordt zo nodig meteen daarna overschreven door de cloud — `adoptMirror` staat dat
  /// toe zolang wat er staat zelf een kopie is.
  Future<void> _fillFromMirror() async {
    await _toonEigenKopie();

    final m = mirror;
    if (m == null) return;
    try {
      final copy = await m.fetch();
      if (copy == null) return;
      if (library.adoptMirror(copy.json, updatedAt: copy.updatedAt)) {
        unawaited(library.loadRemoteCovers(settings));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Cloud catalogue unavailable: $e');
    }
  }

  /// De versie van de berichten van uploaders die dit toestel heeft (uploaderberichten.dart); null: nog niets.
  int? _berichtenVersie;
  bool _berichtenBezig = false;

  /// Een pc van vóór de berichten kent de vraag niet (404): dan deze sessie niet meer vragen.
  bool _berichtenOnbekend = false;

  /// De berichten van uploaders bij de pc ophalen, bij elke ronde van [_refresh]. Meestal is het antwoord alleen de
  /// versie; alleen als er iets bij kwam de lijst.
  Future<void> _haalBerichten() async {
    final c = library.remote;
    if (c == null || _berichtenOnbekend || _berichtenBezig) return;
    _berichtenBezig = true;
    try {
      final eerste = _berichtenVersie == null;
      final a = await c.ask('/api/soulseek/berichten', {if (_berichtenVersie != null) 'versie': _berichtenVersie});
      _berichtenVersie = berichtenVanPc(a, eerste: eerste) ?? _berichtenVersie;
    } on RemoteException catch (e) {
      if (e.statusCode == 404) _berichtenOnbekend = true;
    } catch (_) {
      // De volgende ronde opnieuw.
    } finally {
      _berichtenBezig = false;
    }
  }

  /// Every fifteen seconds. Not a live push: the catalogue only changes when a download lands on
  /// the PC, and a 304 over wifi costs less than keeping a socket open on a sleeping iPad.
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  /// Called when the app comes back to the foreground — an iPad that was in a pocket for an hour
  /// should not wait out the timer before showing what arrived meanwhile.
  ///
  /// En het is de knop "Opnieuw proberen" in de meldingsbalk. Daarom mag het sleutelherstel hier nóg
  /// een keer: na één mislukte poging was die knop anders een knop die de catalogus opnieuw opvroeg
  /// bij een pc die hem net had geweigerd -- en verder niets. Dat dit ook bij terugkomen naar de
  /// voorgrond gebeurt is prima: dat is een handvol keer per dag, niet elke vijftien seconden.
  Future<void> refreshNow() async {
    _sleutelGevraagd = false;
    // Stond de pc als "antwoordt niet", dan eerst de andere adressen — anders was ook deze knop
    // alleen een nieuwe poging op een adres dat op 5G niets is.
    if (library.geenVerbinding == GeenVerbinding.pcStil) await _zoekAnderAdres(meteen: true);
    return _refresh();
  }

  /// Na [dispose] meldt de sessie niets meer. Er loopt veel los van elkaar (de wedloop, de reden uit
  /// de hartslag, een uitgestelde netwerkwissel), en een antwoord dat na het opruimen binnenkomt hoort
  /// stil te vallen in plaats van "used after being disposed" te gooien.
  bool _opgeruimd = false;

  @override
  void notifyListeners() {
    if (_opgeruimd) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _opgeruimd = true;
    _poll?.cancel();
    final d = _doorgever;
    _doorgever = null;
    if (d != null) unawaited(d.stop());
    super.dispose();
  }
}

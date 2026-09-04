/// Running as a client: what `main()` starts instead of a disk scan.
///
/// Keeps the library in step with the PC, and owns the one piece of state the UI branches on —
/// whether this device is paired yet.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../catalogus_kopie.dart';
import '../library.dart';
import '../settings.dart';
import 'client.dart';
import 'discovery.dart';
import '../cloud/catalog_mirror.dart';
import 'client_mode.dart';
import 'uitwijk.dart';

class ClientSession extends ChangeNotifier {
  ClientSession({
    required this.library,
    required this.settings,
    required this.owner,
    required this.applyMediaResolver,
    RemoteEndpoint? endpoint,
    this.kopie = const CatalogusKopie(),
    this.verseSleutel,
  }) : _endpoint = endpoint;

  /// Haalt via de cloud een nieuwe sleutel op voor de pc op dit adres. Null = niet gelukt.
  ///
  /// Een callback en niet de [CloudSession] zelf, om dezelfde reden als [applyMediaResolver]: deze
  /// klasse hoort niets van Firebase te weten, en een toets voor het koppelen hoort geen cloud op
  /// te tuigen.
  final Future<String?> Function(Uri baseUrl)? verseSleutel;

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
  Future<RemoteEndpoint> _bereikbaarAdres(RemoteEndpoint onthouden) async {
    try {
      // Eerst wat we zonder zoeken al weten. Het lokale netwerk afzoeken duurt seconden en levert
      // op de baan per definitie niets op, dus dat komt achteraan.
      for (final adres in weguitVolgorde(
        onthouden: onthouden.baseUrl,
        uitwijk: leesAdressen(onthouden.uitwijk),
      )) {
        if (await RemoteClient.health(adres) == null) continue;
        if (adres == onthouden.baseUrl) return onthouden;
        final vers = onthouden.met(baseUrl: adres);
        // Meteen vastleggen, anders staat hier bij de volgende start weer het oude adres — en
        // daarmee elke start op de baan opnieuw die ene mislukte poging.
        await savePairedServer(vers);
        return vers;
      }

      for (final server in await LanBrowser.find()) {
        if (server.baseUrl == onthouden.baseUrl) continue;
        if (await RemoteClient.health(server.baseUrl) == null) continue;
        final vers = onthouden.met(
          baseUrl: server.baseUrl,
          name: server.name.isEmpty ? onthouden.name : server.name,
        );
        await savePairedServer(vers);
        return vers;
      }
    } catch (_) {/* zoeken mag nooit tussen jou en je muziek staan */}
    return onthouden;
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
  Future<void> _onthoudUitwijk(RemoteClient client, RemoteEndpoint endpoint) async {
    try {
      final verse = await client.uitwijkAdressen();
      if (verse.isEmpty) return;
      // Op waarde vergelijken en niet met `==`: twee lijsten met dezelfde inhoud zijn niet hetzelfde
      // object, en dan zou er bij elke start naar schijf geschreven worden.
      if (verse.join('\n') == endpoint.uitwijk.join('\n')) return;
      final bij = endpoint.met(uitwijk: verse);
      _endpoint = bij;
      await savePairedServer(bij);
    } catch (_) {/* volgende keer weer */}
  }

  /// Wire an endpoint into the app and pull the library in.
  Future<void> connect(RemoteEndpoint endpoint, {bool remember = true}) async {
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
    final werkend = remember ? endpoint : await _bereikbaarAdres(endpoint);
    endpoint = werkend;
    _endpoint = endpoint;
    if (remember) await savePairedServer(endpoint);

    // Wie er aan de andere kant staat, en met welke code. Zie [serverVersie]: bij een koppeling doet
    // de pc het werk, dus zijn versie is de versie die telt.
    unawaited(RemoteClient.health(endpoint.baseUrl).then((h) {
      if (h == null || h.version.isEmpty) return;
      serverVersie = h.version;
      notifyListeners();
    }).catchError((_) {/* niet weten is geen reden om niet te verbinden */}));

    final client = RemoteClient(endpoint);
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
    final shared = await client.config();
    final discogs = shared['discogsToken'] ?? '';
    final lastfm = shared['lastfmKey'] ?? '';
    if (discogs.isNotEmpty) settings.discogsToken = discogs;
    if (lastfm.isNotEmpty) settings.lastfmKey = lastfm;

    loading = true;
    notifyListeners();
    await _refresh(first: true);
    loading = false;
    notifyListeners();

    // Covers after the grid is on screen, not before it.
    unawaited(library.loadRemoteCovers(settings));
    _startPolling();
  }

  /// Hoogstens één keer per zitting een nieuwe sleutel halen.
  ///
  /// **Waarom hoogstens één keer.** Deze poll draait elke vijftien seconden. Zonder deze klep zou
  /// een pc die je toestel écht heeft ingetrokken elke vijftien seconden een nieuw verzoek in
  /// Firestore krijgen, voor altijd. Eén poging per keer dat de app draait is genoeg: helpt het
  /// niet, dan is er iets aan de hand waar een herhaling niets aan verandert, en dan staat de knop
  /// "Opnieuw koppelen" in de meldingsbalk klaar.
  bool _sleutelGevraagd = false;

  Future<void> _vernieuwSleutel() async {
    final haal = verseSleutel;
    final huidig = _endpoint;
    if (haal == null || huidig == null || _sleutelGevraagd) return;
    // VÓÓR de await. Anders start elke poll er nog een terwijl de eerste nog wacht.
    _sleutelGevraagd = true;
    String? verse;
    try {
      verse = await haal(huidig.baseUrl);
    } catch (e) {
      debugPrint('Verse sleutel halen mislukte: $e');
      return;
    }
    // Dezelfde sleutel terug betekent dat de pc hem nooit had ingetrokken maar kwijt was; opnieuw
    // verbinden lost dat niet op en zou alleen het scherm laten knipperen.
    if (verse == null || verse.isEmpty || verse == huidig.token) return;
    // Via `connect` en niet met de hand: die legt hem vast, hangt de client aan de bibliotheek,
    // vertelt de speler hoe hij een pad ondertekent en haalt de catalogus opnieuw op. Dat met de
    // hand overdoen is precies hoe je er één vergeet.
    await connect(RemoteEndpoint(baseUrl: huidig.baseUrl, token: verse, name: huidig.name));
  }

  /// Forget the PC and go back to the pairing screen.
  Future<void> unpair() async {
    _poll?.cancel();
    _poll = null;
    await forgetPairedServer();
    // The PC's key does not stay behind after you tell the app to forget the PC.
    //
    // And it is WRITTEN, not merely dropped from memory. "Nothing was written to disk" was only
    // true for a device that had never pressed Save in Settings — the dialog is not owner-only, and
    // its Save button writes the token this device was handed. Clearing without saving left the
    // real token on disk and two blanks in memory, waiting for some unrelated save to persist them.
    settings.discogsToken = '';
    settings.lastfmKey = '';
    await settings.save();
    // En de inhoudsopgave van die pc gaat mee. Wie zegt "vergeet die pc" bedoelt niet "maar hou de
    // lijst van mijn muziek nog even".
    await kopie.wis();
    library.laatsteCatalogusBytes = null;
    library.remote = null;
    applyMediaResolver((p) => p);
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
      } else {
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
      // The PC did not answer. Show the cloud copy rather than nothing — you can browse, and put
      // downloads in the queue for when it wakes up.
      await _fillFromMirror();
    }
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
    final eigen = await kopie.lees();
    if (eigen != null &&
        library.adoptMirror(eigen.json, updatedAt: eigen.bijgewerkt, vanToestel: true)) {
      // Ook hier de hoezen, want die staan in de cache op dit toestel. Zonder deze aanroep is het
      // een raster van lege vakjes, en dat leest als een kapotte bibliotheek in plaats van als een
      // pc die uit staat.
      unawaited(library.loadRemoteCovers(settings));
      notifyListeners();
    }

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

  /// Every fifteen seconds. Not a live push: the catalogue only changes when a download lands on
  /// the PC, and a 304 over wifi costs less than keeping a socket open on a sleeping iPad.
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  /// Called when the app comes back to the foreground — an iPad that was in a pocket for an hour
  /// should not wait out the timer before showing what arrived meanwhile.
  Future<void> refreshNow() => _refresh();

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}

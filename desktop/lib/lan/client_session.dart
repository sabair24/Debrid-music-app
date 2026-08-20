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
import '../cloud/catalog_mirror.dart';
import 'client_mode.dart';

class ClientSession extends ChangeNotifier {
  ClientSession({
    required this.library,
    required this.settings,
    required this.owner,
    required this.applyMediaResolver,
    RemoteEndpoint? endpoint,
    this.kopie = const CatalogusKopie(),
  }) : _endpoint = endpoint;

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

  /// Wire an endpoint into the app and pull the library in.
  Future<void> connect(RemoteEndpoint endpoint, {bool remember = true}) async {
    _endpoint = endpoint;
    if (remember) await savePairedServer(endpoint);

    final client = RemoteClient(endpoint);
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
    library.laatsteCatalogus = null;
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
      }
      if (changed && !first) {
        // New records may have arrived; only the ones without a cover are fetched.
        unawaited(library.loadRemoteCovers(settings));
      }
      // Vers van de pc: leg hem vast op dit toestel. Alleen als er ECHT iets veranderd is — een
      // poll die 304 krijgt hoeft geen bestand van megabytes opnieuw weg te schrijven, en dat
      // gebeurt hier elke vijftien seconden.
      final vers = library.laatsteCatalogus;
      if (changed && vers != null) unawaited(kopie.bewaar(vers));
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

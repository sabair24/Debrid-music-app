/// Running as a client: what `main()` starts instead of a disk scan.
///
/// Keeps the library in step with the PC, and owns the one piece of state the UI branches on —
/// whether this device is paired yet.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../library.dart';
import '../settings.dart';
import 'client.dart';
import 'client_mode.dart';

class ClientSession extends ChangeNotifier {
  ClientSession({
    required this.library,
    required this.settings,
    required this.owner,
    required this.applyMediaResolver,
    RemoteEndpoint? endpoint,
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

  /// Set once the first catalogue has landed, so the library screen can say "verbinden…" rather
  /// than "geen muziek gevonden" while it is still on its way.
  bool loading = false;

  /// The last thing that went wrong talking to the PC, for the settings screen.
  String? lastError;

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
    library.remote = null;
    applyMediaResolver((p) => p);
    _endpoint = null;
    notifyListeners();
  }

  /// Ask the PC for anything new. Cheap: the ETag means an unchanged library costs a 304.
  Future<void> _refresh({bool first = false}) async {
    try {
      final changed = await library.loadRemote(quiet: !first);
      lastError = null;
      if (changed && !first) {
        // New records may have arrived; only the ones without a cover are fetched.
        unawaited(library.loadRemoteCovers(settings));
      }
    } catch (e) {
      lastError = e.toString();
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

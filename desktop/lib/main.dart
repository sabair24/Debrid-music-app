import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
// Flutter 3.36+ exports a RepeatMode of its own (for RepeatingAnimationBuilder), which collides
// with the player's. Ours is the one this app means everywhere.
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/foundation.dart' show mapEquals;
// For PointerDeviceKind: the nav chip is drag-scrolled with a mouse, which Flutter leaves out of
// the default set on purpose.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
// SpringDescription and SpringSimulation, for the pull-to-close on the now-playing screen.
import 'package:flutter/physics.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'album_facts.dart';
import 'album_facts_resolver.dart';
import 'booklet_view.dart';
import 'catalog.dart';
import 'completeness.dart';
import 'credits.dart';
import 'discogs.dart';
import 'editions.dart';
import 'connectivity.dart';
import 'enrichment.dart';
import 'facts_warmer.dart';
import 'lan/sharing.dart';
import 'lan/tokens.dart';
import 'cloud/catalog_mirror.dart';
import 'cloud/cloud_session.dart';
import 'cloud/queue_store.dart';
import 'cloud/queue_worker.dart';
import 'cloud/settings_sync.dart';
import 'cloud/device_identity.dart';
import 'lan/cast_receiver.dart';
import 'lan/client.dart';
import 'lan/client_mode.dart';
import 'lan/client_session.dart';
import 'lan/remote_services.dart';
import 'now_playing.dart';
import 'login_screen.dart';
import 'pairing_screen.dart';
import 'library.dart';
import 'metadata.dart';
import 'models.dart';
import 'paths.dart';
import 'musicbrainz.dart';
import 'offline.dart';
import 'online.dart';
import 'organize.dart';
import 'player.dart';
import 'quality.dart';
import 'recommend.dart';
import 'release_format.dart';
import 'rutracker.dart';
import 'settings.dart';
import 'speakers.dart';
import 'soulseek.dart';
import 'tidal.dart';
import 'torbox.dart';
import 'tv.dart';

// The phone's chrome — the bar along the bottom, the “Meer” sheet, the top bar that goes with
// them. A part rather than its own library: it re-arranges the frame around the sections
// _HomeShellState already builds, and reads the same private colours as every other screen here.
// Making all of that public for one caller would be a bigger change than the chrome itself.
part 'phone_shell.dart';

/// What a focused Material button looks like: the same ring the rest of the app draws.
///
/// Only `side` and `overlayColor`, so a button that sets its own colour, padding or shape keeps
/// all of it — this adds the one thing that was missing rather than taking the styling over.
final ButtonStyle _focusOutline = ButtonStyle(
  side: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.focused)
      ? BorderSide(color: _accent, width: isTv ? 3 : 2)
      : null),
  overlayColor: WidgetStateProperty.resolveWith((states) =>
      states.contains(WidgetState.focused) ? _accent.withValues(alpha: .22) : null),
);

const _bg = Color(0xFF0C0D12);
const _panel = Color(0xFF181B26);
const _panel2 = Color(0xFF1F2331);
const _line = Color(0xFF272B3A);
const _text = Color(0xFFE8EAF2);
const _muted = Color(0xFF9AA0B4);
const _accent = Color(0xFF7C5CFF);
const _accent2 = Color(0xFF00D4C8);

/// Windows and macOS have windows to manage and one app instance per machine; iOS and Android
/// have neither. Everything below that touches window_manager or the instance lock asks this
/// first — on a phone or tablet those calls do not merely do nothing, they throw.
bool get _isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// True where a finger is the pointer. Hover states are harmless there (they simply never fire),
/// but sizes are not: a control comfortable under a mouse is one you miss with a thumb.
bool get _isTouch => Platform.isIOS || Platform.isAndroid;

/// A loopback port this app holds while it runs. Binding it is the lock; connecting to it is how
/// a second copy says "you're already running, come to the front".
const _instancePort = 47821;

/// Claim the single-instance lock, or hand over to the copy that already holds it.
///
/// Two copies means two Soulseek logins on one account, and Soulseek allows exactly one: they kick
/// each other in turn until the account is refused. That has happened here, so a second launch
/// must never become a second login.
Future<bool> _claimSingleInstance() async {
  if (!_isDesktop) return true; // one app per device already
  try {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, _instancePort);
    server.listen((s) async {
      s.destroy();
      await windowManager.show();
      await windowManager.focus();
    });
    return true;
  } on SocketException {
    try {
      final s = await Socket.connect(InternetAddress.loopbackIPv4, _instancePort,
          timeout: const Duration(seconds: 2));
      s.destroy();
      return false; // somebody answered — it really is us, already running
    } catch (_) {
      // The port belongs to something else entirely. Refusing to start over that would be worse
      // than the duplicate we're guarding against.
      return true;
    }
  }
}

/// Held for the life of the process so the listener is not collected while the app runs.
// ignore: unused_element
AppLifecycleListener? _saveOnLeaving;

/// Everything that is written on a debounce, written now.
///
/// Deliberately not throwing: this runs while the app is being taken away, and a failure here is a
/// slower next start, not something anyone can act on.
Future<void> _flushStores(LibraryStore library) async {
  try {
    await library.facts.flush();
    await library.uids.flush();
  } catch (e) {
    debugPrint('Could not write the album index on the way out: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // Before anything reads a setting or a cache: on iOS the app's own folder cannot be worked out
  // from the environment, it has to be asked for.
  await initAppPaths();
  // Before the first widget: whether this is a television decides focus rings, overscan margins
  // and type sizes, and a layout that changes shape one frame after it appears looks broken.
  await initTvMode();
  // And what this device is called, before it publishes that name anywhere. Same channel, same
  // race — and on Android the alternative is a device list in which every phone reads "localhost".
  await initDeviceName();
  if (_isDesktop) await windowManager.ensureInitialized();
  if (!await _claimSingleInstance()) {
    exit(0);
  }
  if (_isDesktop) {
    // No system title bar: the app draws its own close/minimise/resize buttons into the top bar,
    // so the whole window is the app rather than the app inside a Windows frame. The size below
    // is only what it restores DOWN to — it opens filling the screen.
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1240, 820),
        minimumSize: Size(940, 640),
        center: true,
        title: 'DebridMusic',
        titleBarStyle: TitleBarStyle.hidden,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  final settings = AppSettings();
  await settings.load();
  final library = LibraryStore();
  // Before anything reads it: the download manager captures the root by value, and the LAN
  // server derives every track id from paths relative to it.
  if (settings.musicRoot.trim().isNotEmpty) {
    library.rootPath = settings.musicRoot.trim();
  } else if (Platform.isWindows) {
    // One-time carry-over. `rootPath` used to default to this path in the source, and on Windows
    // `ownsTheMusic` answers true regardless of the settings — so a PC that never set a music
    // folder has been scanning it all along without the setting ever showing that. Write it in, so
    // it appears in Settings and can be changed, and so no other machine inherits it silently.
    const legacy = r'D:\Flac music 2024';
    if (Directory(legacy).existsSync()) {
      settings.musicRoot = legacy;
      library.rootPath = legacy;
      await settings.save();
    }
  }
  // Which of the two this is: the machine that holds the music, or one reading it. Decided once,
  // here, and everything below branches on the answer rather than on the platform.
  final mode = await resolveMode(settings);

  late final PlayerStore player;

  // Where the music comes out. Starts as this device's own output, which is the ordinary case.
  final speakers = SpeakerTarget();

  // Music kept on this device. Loaded before anything can play, because the resolver below asks it
  // on every track and an empty store would stream a copy that is already here.
  final offline = OfflineStore();
  await offline.load();


  final session = ClientSession(
    library: library,
    settings: settings,
    owner: mode.owner,
    // The one place a path becomes something to play, so "the copy if we have it, otherwise the
    // PC" is decided once. No screen, and not the player itself, needs to know that offline
    // copies exist.
    applyMediaResolver: (resolver) => player.mediaResolver = (path) {
      final local = offline.localFor(path);
      if (local != null) return local;
      return resolver(path);
    },
    endpoint: mode.endpoint,
  );

  // Searching and downloading. On a Mac or an iPad these are the same classes as far as every
  // screen is concerned — subclasses that hand the work to the PC, which has the TorBox key, the
  // Soulseek login and somewhere to put the files. The endpoint is read at call time, so pairing
  // for the first time makes these start working without anything being rebuilt.
  final tidal = TidalService(settings);
  final musicbrainz = MusicBrainzService();
  final OnlineService online = mode.owner
      ? OnlineService(settings)
      : RemoteOnlineService(settings, () => session.endpoint);
  final SoulseekService soulseek = mode.owner
      ? SoulseekService(settings)
      : RemoteSoulseekService(settings, () => session.endpoint);
  // How often this pc has logged in to Soulseek lately, and any wait the server imposed. Read
  // before anything can search — the guard exists to survive a restart, and a restart is precisely
  // when it used to be blind. Only here: a client never logs in, it asks the pc to.
  if (mode.owner) await soulseek.client.loadGuard();

  player = PlayerStore()
    ..resolver = online.resolveRadio
    ..coverResolver = library.coverForTrack
    ..trackResolver = library.trackByPath
    // Tapping a track while a speaker has the music sends the queue THERE. Without this the phone
    // started playing it out loud while the KEF carried on with the old queue — which is what
    // "I pressed the next song and it came out of the phone" was.
    ..castQueue = (tracks, index) async {
      final device = speakers.device;
      final client = speakers.client;
      if (device == null || client == null) return false;
      final ids = [
        for (final t in tracks)
          if (library.remoteTrackId(t.path) case final id?) id,
      ];
      // Nothing the pc can serve — a radio stream, say. Let it play here rather than silently
      // dropping it.
      if (ids.isEmpty) return false;
      final at = index.clamp(0, ids.length - 1);
      final ok = await client.castPlay(device.id, ids, at);
      if (ok) unawaited(speakers.refresh(withVolume: true));
      return ok;
    }
    // Last in the cascade: an arrow body swallows whatever follows it, so a `..x = () => y` line
    // in the middle turns the next entry into part of that expression.
    ..metaRevOf = () => library.metaRev;
  // A correction made while the record plays has to reach the player too. Every path that makes one
  // — the release gallery, the metadata editor, a rescan, an edit arriving from another device —
  // ends in notifyListeners(), so this one wire covers all of them.
  //
  // Two calls because they answer two different questions and are guarded differently: the cover is
  // one identity check, the text is a walk of the queue behind a revision counter. Without the
  // first, the bar and the tap-to-zoom kept serving the bytes captured when the track opened.
  // Without the second, the name under them never changed at all.
  library.addListener(() {
    player.refreshCover();
    player.refreshTracks();
  });
  // The lockscreen, Control Center and the media keys. Not awaited on the critical path — the
  // window should not wait on a system service to come up.
  unawaited(initNowPlaying(player, cover: library.coverForTrack));

  // Being cast TO. Only on a television: that is the box wired to the amplifier, and a phone that
  // answered here would start playing whenever somebody in the house picked a speaker.
  //
  // "Stop" pauses rather than tearing the queue down — a sender that stops casting has usually
  // moved the music somewhere else, and coming back to a cleared queue loses your place.
  if (isTv) {
    unawaited(CastReceiver(
      deviceName: _thisDeviceName,
      onPlay: (tracks, index) => player.playQueue(tracks, index),
      onStop: () {
        if (player.playing) player.playPause();
      },
    ).start());
  }

  // What "the library changed" means differs: the PC rescans its disk, a client asks the PC for
  // the catalogue again — which is how a download started from the iPad shows up there.
  Future<void> onLibraryChanged() async {
    if (mode.owner) {
      await library.scan();
      await library.enrich(settings);
    } else {
      await session.refreshNow();
    }
  }

  final DownloadManager downloads = mode.owner
      ? DownloadManager(online, soulseek, library.rootPath, onLibraryChanged)
      : RemoteDownloadManager(
          online, soulseek, library.rootPath, onLibraryChanged, () => session.endpoint);

  // Share this library with the Mac, the iPad and the Shield. Started before the scan finishes:
  // a device probing /health then gets a real answer straight away, and the catalogue fills in
  // by itself as the scan lands.
  // Looking records up before you ask for them. Only the machine holding the music does this — a
  // phone asks the PC for facts, so warming there would be four devices doing one job against one
  // shared budget. Constructed everywhere so the provider tree is the same shape on every platform.
  final warmer = FactsWarmer(
    library: library,
    settings: settings,
    mb: musicbrainz,
    enabled: mode.owner,
  );

  final sharing = LanSharing(
    library: library,
    settings: settings,
    // So a Mac or an iPad can have this PC search and download on its behalf.
    online: mode.owner ? online : null,
    soulseek: mode.owner ? soulseek : null,
    downloads: mode.owner ? downloads : null,
    // And so it can say what a record IS, once, for every device that asks.
    musicbrainz: mode.owner ? musicbrainz : null,
  );
  // Signing in. Restoring a saved session is deliberately NOT awaited before the first frame: a
  // slow network would otherwise hold the whole app on a blank screen, and on the PC it would delay
  // serving music for something that has nothing to do with serving music.
  final cloud = CloudSession();

  // Your service logins, carried by your own account.
  //
  // On Windows and macOS settings.json already survives a reinstall. On a phone it does not — an
  // uninstall takes the whole container — so the account you already sign in with is the only thing
  // that can hand a Soulseek or RuTracker login back to a freshly installed app.
  //
  // Pull fills only what is EMPTY here, so signing in on a working machine can never replace a
  // token in use with an older one from another device. Push is debounced and fingerprinted because
  // AppSettings notifies on load as well as on save, and a TIDAL refresh saves on its own.
  SettingsSync? settingsSync;
  Timer? settingsPush;
  Future<void> syncSettings() async {
    if (!cloud.isSignedIn) {
      settingsSync = null;
      return;
    }
    if (settingsSync == null) {
      final db = await cloud.db();
      if (db == null) return;
      settingsSync = SettingsSync(db: db, uid: cloud.uid);
      final filled = await settingsSync!.pullIntoEmpty(settings);
      if (filled > 0) debugPrint('Restored $filled service keys from your account');
    }
    await settingsSync!.push(settings);
  }

  cloud.addListener(() => unawaited(syncSettings()));
  settings.addListener(() {
    settingsPush?.cancel();
    settingsPush = Timer(const Duration(seconds: 3), () => unawaited(syncSettings()));
  });

  unawaited(cloud.restore().then((_) async {
    if (!mode.owner) return;
    await publishAsOwner(cloud, settings, sharing, library, downloads);
  }));

  // Which build is answering. /health reported an empty version since the field was added — it was
  // never assigned — so the one question you ask a machine you cannot see had no answer.
  unawaited(() async {
    try {
      final info = await PackageInfo.fromPlatform();
      sharing.version = '${info.version}+${info.buildNumber}';
    } catch (_) {
      // Not knowing the version is a worse answer than none, but not a reason to fail to start.
    }
  }());
  if (mode.owner) {
    unawaited(sharing.applySettings());
    // What plays here counts too: the position and the play count go into the same shared state
    // the iPad and the Shield write to, so carrying on elsewhere works in both directions.
    player.onProgress = (track, position, playing, queue, index) {
      sharing.reportProgress(
          track.path, position, playing, [for (final t in queue) t.path], index);
    };
    player.onPlayed = (track) {
      sharing.reportPlayed(track.path);
    };
  }

  // Write what has been learned before the app goes away.
  //
  // Both stores save on a two-second debounce, which is right while the app is running and worth
  // nothing at the moment it closes: on Android the process is killed whenever the system feels
  // like it, and on a desktop the window shuts long before a timer that was set a moment ago. The
  // last few albums somebody opened would be exactly the ones lost.
  //
  // `hidden` and `paused` rather than only `detached`: detached is not reliably delivered on
  // Android, and a backgrounded app that never comes back has simply ended.
  _saveOnLeaving = AppLifecycleListener(
    onHide: () => unawaited(_flushStores(library)),
    onPause: () => unawaited(_flushStores(library)),
    onDetach: () => unawaited(_flushStores(library)),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppSettings>.value(value: settings),
        ChangeNotifierProvider<LibraryStore>.value(value: library),
        ChangeNotifierProvider<FactsWarmer>.value(value: warmer),
        ChangeNotifierProvider<PlayerStore>.value(value: player),
        ChangeNotifierProvider<OfflineStore>.value(value: offline),
        ChangeNotifierProvider<SpeakerTarget>.value(value: speakers),
        Provider<OnlineService>.value(value: online),
        // One instance for the whole app. The 1100 ms spacing MusicBrainz asks for is held in
        // INSTANCE fields, so two widgets each constructing their own would fire unspaced and
        // earn a 503 — and an album page builds three of these panels side by side.
        Provider<MusicBrainzService>.value(value: musicbrainz),
        Provider<SoulseekService>.value(value: soulseek),
        Provider<TidalService>.value(value: tidal),
        ChangeNotifierProvider<DownloadManager>.value(value: downloads),
        ChangeNotifierProvider<LanSharing>.value(value: sharing),
        ChangeNotifierProvider<ClientSession>.value(value: session),
        ChangeNotifierProvider<CloudSession>.value(value: cloud),
      ],
      child: const DebridApp(),
    ),
  );

  // Fill the screen, once there is a frame to fill it with.
  //
  // Asked for inside waitUntilReadyToShow — before OR after show() — Windows quietly keeps the
  // restore size while the window is still being realised, and the app opens in a small frame.
  // Both orderings were tried and both did. So ask after the first frame, and check the answer
  // instead of assuming it: read isMaximized back and retry for about half a second.
  if (_isDesktop) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (var i = 0; i < 6; i++) {
        if (await windowManager.isMaximized()) break;
        await windowManager.maximize();
        await Future.delayed(const Duration(milliseconds: 100));
      }
    });
  }

  // A device that does not hold the music has nothing to scan: its library comes from the PC,
  // where the corrections, the pinned pressings and the chosen covers have already been applied.
  if (!mode.owner) {
    if (downloads is RemoteDownloadManager) {
      // Pairing for the first time goes through the pairing screen, not through the branch below,
      // so the watch is hung off the session rather than started once here.
      session.addListener(() {
        if (session.ready) downloads.startWatching();
        // A speaker is steered through the PC, so the remote to steer with appears when the pairing
        // does. Set here rather than read during a build: reaching for it mid-build made whether the
        // buttons worked depend on which screen had been drawn.
        speakers.client = library.remote;
      });
      speakers.client = library.remote;
      // Where a download goes when the PC does not answer: into the queue, for the PC to pick up
      // when it comes back. Re-read whenever the sign-in changes, so signing out takes the queue
      // with it rather than writing to an account nobody is using.
      final manager = downloads;
      manager.requestedBy = deviceName();
      void refreshQueue() {
        unawaited(cloud.db().then((db) {
          manager.queue = db == null ? null : FirestoreQueue(db: db, uid: cloud.uid);
          // The same account also holds the catalogue copy this device falls back on.
          session.mirror = db == null ? null : CatalogMirror(db: db, uid: cloud.uid);
        }).catchError((Object _) {
          // No queue is a worse experience than a queue, but not worth failing a start over: an
          // unreachable PC then simply reports the failure it always did.
          manager.queue = null;
        }));
      }

      cloud.addListener(refreshQueue);
      refreshQueue();
    }
    () async {
      // What this device was told about its records, BEFORE it connects. Without this the index was
      // written on every album open and never read back, so closing the app threw away everything
      // it had learned and the next start asked the PC for all of it again — which is exactly the
      // loading this store exists to remove. It belongs here and not only on the PC: a phone keeps
      // its own copy of the answers, keyed by the PC's album id.
      await library.facts.load();
      final endpoint = mode.endpoint;
      if (endpoint != null) await session.connect(endpoint, remember: false);
      // Whatever the PC is downloading shows up in "Mijn downloads" here too, progress and all.
      if (downloads is RemoteDownloadManager) downloads.startWatching();
      // The queue is restored either way — the paths in it are stream URLs, and they resolve
      // against whatever library has just landed.
      await player.restore(library.trackByPath);
    }();
    return;
  }

  // Scan, then fill in missing covers + artist photos (cache-first, then web).
  // Wrapped so a scan hiccup can never prevent enrichment from running.
  () async {
    await library.loadCorrections(); // apply manual fixes as tracks are built
    await library.uids.load(); // the names albums keep across a rename — before the first regroup
    await library.facts.load(); // pressings and tracklists already worked out — one file, one read
    await library.loadHidden(); // keep "removed from library only" tracks out
    await library.loadMerged(); // records the user told us to keep together
    await library.loadArtistArtChoice(); // portraits and backdrops the user picked
    await library.loadAlbumArtRoles(); // which scan is the sleeve, the back, the disc
    await library.loadStyles(); // what each record sounds like, for discovery
    try {
      await library.scan();
    } catch (_) {}
    await library.enrich(settings);
    // Reopen the last queue where you left off (paused) — covers are loaded by now.
    await player.restore(library.trackByPath);
    // Downloads that were still running when the app (or the PC) went down. After the scan, so
    // anything that did finish is already in the library and won't be fetched twice.
    try {
      await downloads.resumePending();
    } catch (_) {}
    await library.enrichArtists(settings);
    // Last, deliberately. Everything above this either draws the first screen or fetches something
    // you can see; this is the only part nobody is waiting for. Not awaited either — it runs for as
    // long as there are records it has not looked up yet.
    unawaited(warmer.start());
  }();
}

class DebridApp extends StatelessWidget {
  const DebridApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DebridMusic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          secondary: _accent2,
          surface: _panel,
        ),
        // Every InkWell, ListTile and Material button in the app can already take focus — Flutter
        // gives them that for free, which is why they were reachable with a remote before anything
        // was changed. What they could not do was SAY so: the default focus tint is a whisper of
        // white, and on these panels, from a sofa, it is not there at all. One line rather than
        // twenty-five edits, and a mouse never sees it because a mouse never focuses.
        focusColor: _accent.withValues(alpha: isTv ? .34 : .18),
        // Material's buttons signal focus with a tint of their own foreground colour — about a
        // tenth of white. On the purple "Afspelen" button that is nothing at all, and on a TV a
        // button you cannot tell is selected is a button you press by accident. So they get the
        // same outline every other focusable thing in this app got.
        filledButtonTheme: FilledButtonThemeData(style: _focusOutline),
        textButtonTheme: TextButtonThemeData(style: _focusOutline),
        outlinedButtonTheme: OutlinedButtonThemeData(style: _focusOutline),
        iconButtonTheme: IconButtonThemeData(style: _focusOutline),
        fontFamily: 'Segoe UI',
      ),
      // On a Mac or an iPad that has never met the PC there is no library to show yet, so the
      // pairing screen comes first. Everywhere else — and from the moment it is paired — this is
      // the same app it has always been.
      // On a Mac or an iPad that is not connected to a PC yet there is no library to show, so the
      // login comes first. Everywhere else — and from the moment it is connected — this is the same
      // app it has always been.
      home: Consumer2<ClientSession, CloudSession>(
        builder: (context, session, cloud, _) {
          if (session.ready) return const HomeShell();
          // The pairing code is still reachable, and is the whole screen when this build has no
          // Firebase project: nobody should be stuck behind a login that cannot work.
          if (cloud.state == CloudState.disabled || session.preferPairingCode) {
            return PairingScreen(
              deviceName: _thisDeviceName(),
              onPaired: session.connect,
            );
          }
          if (cloud.state == CloudState.restoring) {
            return const Scaffold(
              backgroundColor: _bg,
              body: Center(child: CircularProgressIndicator(color: _accent)),
            );
          }
          return LoginScreen(
            session: cloud,
            onConnected: session.connect,
            onUseCode: session.usePairingCode,
          );
        },
      ),
    );
  }
}

/// Publish where this PC is, and hand a token to any device that asked.
///
/// This is what replaces discovery for the ordinary case — and what fixes "Geen pc gevonden" when
/// mDNS is blocked. Does nothing until someone is signed in; there is no account to publish under
/// before that.
///
/// A function rather than a few lines inside main() because it has two callers now: the session
/// restored from disk at startup, and the moment someone signs in from Settings. Without the second
/// one, signing in on the PC appeared to do nothing at all until the app was restarted — and the
/// PC has to be published before any Mac or iPad can find it, so that is the very first thing a
/// new account does.
Future<void> publishAsOwner(CloudSession cloud, AppSettings settings, LanSharing sharing,
    LibraryStore library, DownloadManager downloads) async {
  if (!cloud.isSignedIn) return;
  if (settings.serverId.isEmpty) {
    settings.serverId = generateDeviceToken().substring(0, 16);
    await settings.save();
  }
  cloud.startAsOwner(
    serverId: settings.serverId,
    serverName: deviceName(),
    port: settings.lanPort,
    addresses: () => sharing.addresses,
    grants: sharing.grants,
    trackCount: () => library.tracks.length,
  );

  // Work through anything chosen on another device while this PC was off. It replays the very
  // request that device would have sent, into the same DownloadManager — so a queued download
  // lands exactly like a live one, authority tags and all. Started here rather than in main() for
  // the same reason as the rest of this function: signing in from Settings has to start it too.
  final db = await cloud.db();
  final server = sharing.server;
  if (db != null && server != null) {
    _worker?.stop();
    _worker = QueueWorker(
      backend: FirestoreQueue(db: db, uid: cloud.uid),
      server: server,
      downloads: downloads,
      workerId: settings.serverId,
    )..start();

    // Copy the library up so a Mac or an iPad can browse it with this PC asleep. Driven off the
    // catalogue's own fingerprint, so an unchanged library costs one read and no writes — and
    // enriching a cover, which changes no byte of that catalogue, costs nothing at all.
    _mirrorTimer?.cancel();
    final mirror = CatalogMirror(db: db, uid: cloud.uid);
    Future<void> publish() async {
      if (library.tracks.isEmpty) return; // never publish an empty library over a good one
      await mirror.publish(server.catalog.snapshot());
    }

    unawaited(publish());
    _mirrorTimer = Timer.periodic(const Duration(minutes: 5), (_) => unawaited(publish()));
  }
}

/// The catalogue copy, refreshed on a slow timer. Five minutes because the fingerprint check makes
/// an unchanged run nearly free, and a download that just landed should not take an hour to show
/// up on a device that is out of the house.
Timer? _mirrorTimer;

/// The one worker for this process. Held so signing in twice does not leave two of them racing
/// each other for the same items.
QueueWorker? _worker;

/// What the PC lists this device as. Its own name, because "iPad" is what you look for in a list
/// of paired devices — not a serial number.
String _thisDeviceName() {
  try {
    return Platform.localHostname;
  } catch (_) {
    return Platform.isIOS ? 'iPad' : 'Mac';
  }
}

// ── Cover helpers ────────────────────────────────────────────────────────────
Widget cover(Uint8List? bytes, {double size = 160, double radius = 12, bool circle = false}) {
  final shape = circle ? BoxShape.circle : BoxShape.rectangle;
  final br = circle ? null : BorderRadius.circular(radius);
  if (bytes != null) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(shape: shape, borderRadius: br),
      child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
    );
  }
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: shape,
      borderRadius: br,
      gradient: const LinearGradient(colors: [Color(0xFF242838), Color(0xFF1A1D29)]),
    ),
    child: Icon(Icons.music_note_rounded, color: _muted.withValues(alpha: .4), size: size * .34),
  );
}

/// Album ordering options for the Albums view.
enum AlbumSort { titel, artiest, jaarNieuw, jaarOud, toegevoegd }

extension AlbumSortX on AlbumSort {
  String get label => switch (this) {
        AlbumSort.titel => 'Titel (A–Z)',
        AlbumSort.artiest => 'Artiest',
        AlbumSort.jaarNieuw => 'Jaar (nieuw→oud)',
        AlbumSort.jaarOud => 'Jaar (oud→nieuw)',
        AlbumSort.toegevoegd => 'Recent toegevoegd',
      };
}

// ── Home shell ───────────────────────────────────────────────────────────────
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _view = 5; // 0 albums, 1 artists, 2 online, 3 ontdek, 4 tracks, 5 start (default)

  // Library search + quality filter (applies to Albums / Tracks / Artiesten).
  final _searchCtl = TextEditingController();

  /// Skipped when arrowing around on a television, and only entered on purpose.
  ///
  /// A text field takes focus like anything else, and on Android taking focus opens the on-screen
  /// keyboard — which then swallows every arrow press, so the highlight is stuck inside a keyboard
  /// covering half the screen and the album grid below it is unreachable. Pressing down from the
  /// navigation must land on the records, not in a keyboard nobody asked for.
  final _searchFocus = FocusNode(skipTraversal: isTv, debugLabel: 'library search');
  String _q = '';
  QFilter _qFilter = QFilter.all;
  AlbumSort _sort = AlbumSort.titel;

  /// Where BACK goes on a phone.
  ///
  /// A remote gets "anywhere → Start, then out", which is right for a device whose BACK button is
  /// pressed constantly. A phone is not that: the sections sit on a bar you tap between, and a
  /// rule that throws away where you were on every tap makes BACK useless.
  ///
  /// A section appears at most once. Without that, tapping between two sections all evening
  /// builds a list that takes as many presses to leave the app as you made taps — which is the
  /// other half of the mistake the comment in [build] warns about. Distinct entries bound it to
  /// six, one short of the number of sections.
  final _history = <int>[];

  /// Every section change on a phone goes through here, so nothing can move [_view] behind the
  /// history's back. The wide layout feeds it too — it simply never reads it, and keeps the
  /// straight-to-Start rule the television was tested with.
  void _go(int id) {
    if (id == _view) return;
    _history
      ..remove(_view)
      ..add(_view);
    setState(() => _view = id);
  }

  /// A layer inside the current section that BACK must close before the section itself.
  ///
  /// Null when there is none. Held here rather than solved with a second PopScope inside the
  /// section: both would be registered on the same route and BOTH fire on one press of BACK.
  VoidCallback? _popInner;

  /// What that layer is called, for the bar at the top of a phone.
  ///
  /// An artist page reached from Artiesten used to leave the bar saying “Artiesten”, so the one
  /// place on the screen that says where you are said the wrong thing, and the only way back was
  /// an arrow drawn over the photo.
  String? _innerTitle;

  void _setInnerLayer(VoidCallback? pop, {String? title}) {
    if (_popInner == pop && _innerTitle == title) return;
    // During the child's build, so not inside setState — the flag only feeds canPop, which is
    // read on the next frame anyway.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _popInner = pop;
          _innerTitle = title;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// The section's own search box — and only while you are looking at the section.
  ///
  /// An artist page is not a place to search your library from: the box and the four quality
  /// chips took 180 of a phone's 915 points off a page that was already having to fit a portrait,
  /// a name, two buttons and a discography.
  bool get _searchable => (_view == 0 || _view == 1 || _view == 4) && _popInner == null;

  /// Does this track match the current search box + quality filter?
  bool _matches(Track t) {
    if (!_qFilter.matches(qualityFromFile(
        name: t.title, ext: t.isFlac ? 'flac' : 'mp3', isFlac: t.isFlac, durationSec: t.duration?.inSeconds))) {
      return false;
    }
    if (_q.isEmpty) return true;
    final q = normKey(_q);
    if (normKey(t.title).contains(q) || normKey(t.artist).contains(q) || normKey(t.album).contains(q)) {
      return true;
    }
    // Second pass with punctuation squashed out, so "backstreets back" finds "Backstreet's Back".
    final qs = searchKey(_q);
    if (qs.isEmpty) return false;
    return searchKey(t.title).contains(qs) ||
        searchKey(t.artist).contains(qs) ||
        searchKey(t.album).contains(qs);
  }

  /// Frosted pill that sits at the top of every screen. It really does blur what's behind it —
  /// the ambient glow in [_contentArea] gives the glass something to pick up, so it reads as a
  /// pane of glass rather than a flat rounded box.
  Widget _glassPill({required Widget child}) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: .085),
                    Colors.white.withValues(alpha: .028),
                  ],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: .10)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .34),
                    blurRadius: 26,
                    offset: const Offset(0, 9),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      );

  /// The field, with the filters beside it or under it.
  ///
  /// Four chips and a sort button take roughly 390 points. Beside a text field on a 412-point phone
  /// that leaves the field nothing, and its hint printed one letter per line — the same failure as
  /// the album header, in the one place that is on screen the whole time.
  Widget _searchBar(BuildContext context) {
    final narrow = isCompact(context);
    if (!narrow) return _searchBarRow();
    return Column(
      children: [
        _glassPill(child: Row(children: [Expanded(child: _searchField())])),
        const SizedBox(height: 8),
        SizedBox(
          height: 38,
          // Scrolled rather than wrapped: a second row of chips would push the records themselves
          // below the fold on a phone, and these are a filter you set once.
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            children: [..._filterChips(), ..._sortControl()],
          ),
        ),
      ],
    );
  }

  Widget _searchBarRow() => _glassPill(
        child: Row(
          children: [
            Expanded(child: _searchField()),
            const SizedBox(width: 10),
            ..._filterChips(),
            ..._sortControl(),
          ],
        ),
      );

  /// The text field itself, shared by both shapes of the bar.
  Widget _searchField() =>
              // On a television the field is behind a press: the highlight stops on the search
              // bar, OK opens the keyboard, and BACK closes it again. Everywhere else this is the
              // same bare field it always was — a mouse still clicks straight into it.
              MaybePressable(
                enabled: isTv,
                onPressed: () => _searchFocus.requestFocus(),
                borderRadius: BorderRadius.circular(999),
                child: TextField(
                  controller: _searchCtl,
                  focusNode: _searchFocus,
                  onChanged: (v) => setState(() => _q = v.trim()),
                  style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Zoek in je bibliotheek — artiest, album of nummer…',
                  hintStyle: const TextStyle(color: _muted, fontSize: 13.5),
                  prefixIcon: const Icon(Icons.search_rounded, size: 19, color: _muted),
                  suffixIcon: _q.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 17, color: _muted),
                          tooltip: 'Wissen',
                          onPressed: () => setState(() {
                            _q = '';
                            _searchCtl.clear();
                          }),
                        ),
                  // No box of its own: the pill IS the field's surface.
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                ),
              );

  List<Widget> _filterChips() => [
            ...QFilter.values.map((f) {
              final sel = _qFilter == f;
              return Padding(
                padding: const EdgeInsets.only(left: 6),
                // Translucent so the controls sit ON the glass instead of punching holes in it.
                child: ChoiceChip(
                  label: Text(_qFilterLabel(f), style: const TextStyle(fontSize: 12)),
                  selected: sel,
                  onSelected: (_) => setState(() => _qFilter = f),
                  backgroundColor: Colors.white.withValues(alpha: .06),
                  selectedColor: _accent,
                  labelStyle: TextStyle(color: sel ? Colors.white : _muted),
                  side: BorderSide(color: sel ? _accent : Colors.white.withValues(alpha: .12)),
                  shape: const StadiumBorder(),
                  showCheckmark: false,
                ),
              );
            }),
      ];

  /// Sorting, which only the Albums view offers.
  List<Widget> _sortControl() => _view != 0
      ? const []
      : [

              const SizedBox(width: 8),
              PopupMenuButton<AlbumSort>(
                tooltip: 'Sorteren',
                initialValue: _sort,
                onSelected: (s) => setState(() => _sort = s),
                color: _panel,
                position: PopupMenuPosition.under,
                itemBuilder: (_) => AlbumSort.values
                    .map((s) => PopupMenuItem(value: s, child: Text(s.label, style: const TextStyle(fontSize: 13))))
                    .toList(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withValues(alpha: .12)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.sort_rounded, size: 16, color: _muted),
                    const SizedBox(width: 6),
                    Text(_sort.label, style: const TextStyle(fontSize: 12.5, color: _muted)),
                    const Icon(Icons.arrow_drop_down_rounded, size: 18, color: _muted),
                  ]),
                ),
              ),
        ];

  @override
  Widget build(BuildContext context) {
    // Two chromes, one shell.
    //
    // Below 600 points the frame is rebuilt around a thumb: the sections move to a bar along the
    // bottom edge, where a hand holding the phone can reach them without crossing the screen.
    // Everything INSIDE that frame stays what the window and the television show — the same seven
    // sections, the same search, the same detail pages, the same player.
    //
    // The branch is here and not at the one place HomeShell is created, because swapping the
    // widget TYPE up there destroys this subtree every time the phone turns: Start would re-fetch
    // its charts, the online results would empty and the search box would lose what you typed, on
    // every rotation. One State with a branch in build keeps your place.
    final phone = isCompact(context);

    // BACK, on a television, must go back.
    //
    // The seven sections are a number in this state, not routes, so Flutter's navigator has
    // nothing to pop and Android takes BACK as "leave the app". Pressing it on Albums dropped you
    // straight out to the TV launcher — which on a remote, where BACK is the button you reach for
    // constantly, makes the app feel like it crashes.
    //
    // canPop stays true on Start, so a second BACK still leaves. An app you cannot get out of is
    // the other half of this mistake.
    return PopScope(
      canPop: _popInner == null && (phone ? _history.isEmpty : _view == 5),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // The innermost layer first. A section can have one of its own — the artist page is a
        // swapped-in body, not a route — and it has to close before the section does, or BACK
        // from an artist lands on Start and loses your place in the list.
        final inner = _popInner;
        if (inner != null) {
          inner();
          return;
        }
        if (phone && _history.isNotEmpty) {
          setState(() => _view = _history.removeLast());
          return;
        }
        setState(() => _view = 5);
      },
      child: phone ? _phoneScaffold(context) : _wideScaffold(context),
    );
  }

  /// The window, the tablet and the television: the pill strip across the top, the section under
  /// it, the player along the bottom.
  Widget _wideScaffold(BuildContext context) => Scaffold(
        // Televisions overscan: a strip around the edge of the picture falls off the screen, and
        // how much differs per set. The margin goes on the CONTENTS of the bars rather than around
        // the whole app, so the top bar's glass and the player bar's surface still reach the panel
        // edge — a floating panel with a black gutter around it looks like a mistake, and the point
        // was only to keep the things you read and press away from the edge.
        body: Column(
          children: [
            _topBar(),
            const _OfflineBanner(),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: tvOverscan.left),
                child: Column(
                  children: [
                    if (_searchable) _searchBar(context),
                    Expanded(child: _content()),
                  ],
                ),
              ),
            ),
            const PlayerBar(),
          ],
        ),
      );

  /// The phone: the sections along the bottom, everything else unchanged.
  ///
  /// The frame itself lives in phone_shell.dart; what goes inside it is built here, by the same
  /// methods the wide layout uses, so the two can never drift into showing different things.
  Widget _phoneScaffold(BuildContext context) => _PhoneShell(
        view: _view,
        innerTitle: _innerTitle,
        onBack: _popInner,
        searchBar: _searchable ? _searchBar(context) : null,
        content: _content(),
        onSelect: _go,
      );

  /// Brand, the navigation pill bar, and the library count — the old left rail, laid out
  /// horizontally. The soft glow behind it is what the glass has to blur; on a flat panel
  /// frosted glass is indistinguishable from a plain rounded box.
  /// The top bar doubles as the window's title bar.
  ///
  /// With the system frame gone this is the only thing left to grab, so dragging it moves the
  /// window and double-clicking it maximises — the two gestures anyone expects of a title bar. The
  /// controls sitting on it keep working: DragToMoveArea only claims what no child handled.
  /// On an iPad there is no window to drag and no `window_manager` behind these calls — the bar is
  /// just a bar there.
  Widget _topBar() => _isDesktop
      ? DragToMoveArea(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: () async => await windowManager.isMaximized()
                ? windowManager.unmaximize()
                : windowManager.maximize(),
            child: _topBarBody(),
          ),
        )
      : _topBarBody();

  Widget _topBarBody() => SizedBox(
        // The glow keeps running behind the status bar; only the contents move down, so the top of
        // the screen still looks like one piece rather than a black strip above the app.
        height: 64 + (_isTouch ? MediaQuery.viewPaddingOf(context).top : 0),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: -150,
              height: 300,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: .75,
                      colors: [_accent.withValues(alpha: .34), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  18, 11 + (_isTouch ? MediaQuery.viewPaddingOf(context).top : 0), 18, 8),
              // The bar was built for a 1240-point window. An iPad in portrait is 834, and there
              // it would simply overflow. Rather than a second navigation for touch — which is
              // exactly the divergence this whole change is removing — the same bar drops what is
              // decoration (the wordmark, the counts) and lets the sections scroll.
              child: LayoutBuilder(
                builder: (context, box) {
                  final compact = box.maxWidth < 1040;
                  return Row(
                    children: [
                      // The app's real icon, not an impression of it. This used to be a gradient
                      // square with a music note drawn to look like the old mark, so when the
                      // icon was redrawn everywhere else the top bar kept showing the old one.
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset('assets/icon/app_icon.png',
                            width: 28, height: 28, filterQuality: FilterQuality.medium),
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 9),
                        const Text('DebridMusic',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                      ],
                      const SizedBox(width: 10),
                      Expanded(
                        child: Center(
                          // Draggable with a mouse, not only with a wheel or a finger.
                          //
                          // Flutter leaves the mouse out of dragDevices on purpose — on a page, a
                          // mouse-drag is a text selection, not a scroll. Here there is no text to
                          // select and the wheel is the only way to reach a section that does not
                          // fit, which on a narrow window is most of them.
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(context).copyWith(
                              dragDevices: {
                                PointerDeviceKind.touch,
                                PointerDeviceKind.mouse,
                                PointerDeviceKind.stylus,
                                PointerDeviceKind.trackpad,
                              },
                              scrollbars: false,
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              // Every section stays reachable when they no longer fit side by side.
                              // A menu would hide them; scrolling keeps them where they were.
                              child: Consumer<DownloadManager>(
                                builder: (_, dm, __) => _NavPills(
                                  active: _view,
                                  onSelect: _go,
                                  badge: dm.jobs.where((j) => j.busy).length,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (!compact)
                        Consumer2<LibraryStore, FactsWarmer>(
                          builder: (_, lib, warmer, __) => Text(
                            lib.scanning
                                ? 'Scannen… ${lib.scanned}'
                                : (lib.enriching
                                    ? 'Covers ophalen…'
                                    // Fourth state, after the two that were already here. The PC
                                    // works through the records nobody has opened yet; without a
                                    // line saying so it is invisible work that writes files into
                                    // the music folder, which is the kind of thing you find out
                                    // about at the wrong moment.
                                    : (warmer.status.isNotEmpty
                                        ? warmer.status
                                        : '${lib.albums.length} albums · ${lib.tracks.length} nummers')),
                            style: const TextStyle(color: _muted, fontSize: 11.5),
                          ),
                        ),
                      if (!compact) const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.settings_rounded, size: 19),
                        color: _muted,
                        tooltip: 'Instellingen',
                        // 44 points on a touch screen — the smallest thing Apple expects a finger
                        // to hit, and a 19-point icon with default padding is under it.
                        constraints: _isTouch ? const BoxConstraints.tightFor(width: 44, height: 44) : null,
                        onPressed: () =>
                            openSettings(context),
                      ),
                      // Only where there is a window to close: on the iPad these would be three
                      // buttons wired to a plugin that does not exist there.
                      if (_isDesktop) ...[
                        const SizedBox(width: 4),
                        const _WindowButtons(),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );


  Widget _content() {
    if (_view == 5) return const HomeStartView();
    if (_view == 6) return const DownloadsView();
    if (_view == 2) return const OnlineSearchScreen();
    if (_view == 3) return const OntdekView();
    if (_view == 4) return TracksView(match: _matches, query: _q);
    return Consumer<LibraryStore>(
      builder: (_, lib, __) {
        if (lib.scanning && lib.albums.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (lib.albums.isEmpty) {
          // On a Mac or an iPad there is no folder to point at — the library comes from the PC,
          // and naming a drive letter there sends you looking in the wrong place entirely.
          return Center(
            child: Text(
              lib.isRemote
                  ? 'Nog niets van je pc ontvangen. Staat DebridMusic daar open?'
                  : 'Geen muziek gevonden in ${lib.rootPath}',
              style: const TextStyle(color: _muted),
              textAlign: TextAlign.center,
            ),
          );
        }
        // An album stays in view when any of its tracks matches (so searching an artist or a
        // single song still surfaces the album it lives on).
        final albums = lib.albums.where((a) => a.tracks.any(_matches)).toList();
        if (albums.isEmpty) {
          return Center(
            child: Text('Niets gevonden voor “$_q”.', style: const TextStyle(color: _muted)),
          );
        }
        return _view == 0
            ? AlbumsGrid(albums: _sortAlbums(albums), title: _q.isEmpty ? null : '${albums.length} resultaten')
            : ArtistsView(lib: lib, albums: albums, onInnerLayer: _setInnerLayer);
      },
    );
  }

  List<Album> _sortAlbums(List<Album> src) {
    final list = [...src];
    switch (_sort) {
      case AlbumSort.titel:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case AlbumSort.artiest:
        list.sort((a, b) {
          final c = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
          return c != 0 ? c : (a.year ?? 0).compareTo(b.year ?? 0);
        });
      case AlbumSort.jaarNieuw:
        list.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
      case AlbumSort.jaarOud:
        list.sort((a, b) => (a.year ?? 9999).compareTo(b.year ?? 9999));
      case AlbumSort.toegevoegd:
        list.sort((a, b) => b.addedMs.compareTo(a.addedMs));
    }
    return list;
  }

  String _qFilterLabel(QFilter f) => switch (f) {
        QFilter.all => 'Alles',
        QFilter.lossless => 'Lossless',
        QFilter.hires => 'Hi-Res',
        QFilter.mp3 => 'MP3',
      };
}

// ── Top navigation ───────────────────────────────────────────────────────────
/// The sections, as a row of labels inside one glass bar, with a pill that SLIDES to whichever
/// section you're in.
///
/// Item widths are measured from the text rather than read back after layout, so the pill's
/// geometry is known in the same frame it animates in — no first-frame jump, no post-frame
/// measuring pass. That also means the label's weight must not change between states (only its
/// colour does), or the pill would no longer match what it sits behind.
/// Says the library on screen is the cloud copy, not the PC.
///
/// Without it, a tap on play does nothing and there is no way to tell why — the albums are all
/// there, the covers are all there, and the files are on a machine that is asleep.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    if (!lib.fromCloudMirror) return const SizedBox.shrink();
    final when = lib.mirrorUpdatedAt;
    return Container(
      width: double.infinity,
      color: const Color(0xFF2A2416),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      child: Row(children: [
        const Icon(Icons.cloud_off_rounded, size: 17, color: Color(0xFFE8C36A)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Je pc staat uit — dit is de kopie van je bibliotheek'
            '${when == null ? '' : ' van ${_ago(when)}'}. '
            'Bladeren en downloads klaarzetten kan; afspelen niet.',
            style: const TextStyle(color: Color(0xFFE8C36A), fontSize: 12.5),
          ),
        ),
      ]),
    );
  }

  static String _ago(DateTime when) {
    final d = DateTime.now().toUtc().difference(when.toUtc());
    if (d.inMinutes < 2) return 'zojuist';
    if (d.inHours < 1) return '${d.inMinutes} minuten geleden';
    if (d.inDays < 1) return '${d.inHours} uur geleden';
    return '${d.inDays} dagen geleden';
  }
}

class _NavPills extends StatefulWidget {
  final int active;
  final ValueChanged<int> onSelect;
  final int badge; // downloads in progress, shown on "Mijn downloads"
  const _NavPills({required this.active, required this.onSelect, required this.badge});

  @override
  State<_NavPills> createState() => _NavPillsState();
}

/// The seven sections, in one place.
///
/// A phone puts four of them on a bar along the bottom and the rest behind “Meer”; everything
/// wider lays all seven out as pills. All of it reads from here, so a section cannot exist in one
/// navigation and not the other.
class NavSections {
  const NavSections._();

  static const items = <(int, String)>[
    (5, 'Start'),
    (0, 'Albums'),
    (4, 'Tracks'),
    (1, 'Artiesten'),
    (2, 'Online zoeken'),
    (3, 'Ontdek'),
    (6, 'Mijn downloads'),
  ];

  /// The four that get a place of their own on a phone's bottom bar.
  ///
  /// Your own shelf first — a phone is what you browse with while the PC does the work — and then
  /// downloads, which is the one section that changes while you are not looking at it, and
  /// therefore the one that carries the badge.
  ///
  /// A SELECTION over [items] rather than a second list: a section added above turns up under
  /// “Meer” by itself.
  static const phonePrimary = <int>[5, 0, 1, 6];

  /// Everything [phonePrimary] does not carry, by construction — the half that cannot go stale.
  static Iterable<(int, String)> get phoneMore =>
      items.where((e) => !phonePrimary.contains(e.$1));

  /// A section's label, falling back to Start's for an id that is not one of the seven.
  static String labelOf(int id) =>
      items.firstWhere((e) => e.$1 == id, orElse: () => (5, 'Start')).$2;

  /// The same label, shortened to what fits under an icon on the phone's bottom bar.
  ///
  /// A fifth of a 320-point screen is 64 points; “Mijn downloads” is about 85 at this size and
  /// would come out as “Mijn down…”. Falls through to [labelOf], so a section added to [items]
  /// still appears — a missing entry here costs an ellipsis, not a place in the navigation.
  static String shortLabelOf(int id) => switch (id) {
        6 => 'Downloads',
        2 => 'Zoeken',
        _ => labelOf(id),
      };
}

class _NavPillsState extends State<_NavPills> {
  int? _hover;

  static const _items = NavSections.items;

  /// `leadingDistribution: even` is the whole fix for the text sitting high in the pill.
  ///
  /// A line box is taller than the glyphs, and by default all of that slack goes ABOVE the
  /// baseline — so centring the box leaves the letters above the middle of the pill. Even
  /// distribution splits the slack top and bottom, which is what puts them where the eye expects.
  /// A hard-coded nudge would have done it on this font at this size and been wrong on the next.
  static const _style = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static final _padH = _isTouch ? 20.0 : 15.0;
  static const _badgeW = 21.0;

  /// 44 points under a finger, 32 under a mouse. The pill that slides behind the active section
  /// is measured from these, so both have to come from the same place.
  static final _height = _isTouch ? 44.0 : 32.0;

  double _width(int i) {
    final tp = TextPainter(
      text: TextSpan(text: _items[i].$2, style: _style),
      textDirection: TextDirection.ltr,
    )..layout();
    final badge = _items[i].$1 == 6 && widget.badge > 0 ? _badgeW : 0.0;
    return tp.width + _padH * 2 + badge;
  }

  @override
  Widget build(BuildContext context) {
    final widths = [for (var i = 0; i < _items.length; i++) _width(i)];
    final offsets = <double>[];
    var total = 0.0;
    for (final w in widths) {
      offsets.add(total);
      total += w;
    }
    final activeIdx = _items.indexWhere((e) => e.$1 == widget.active);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: .085),
                Colors.white.withValues(alpha: .028),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: .10)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: .34), blurRadius: 26, offset: const Offset(0, 9)),
            ],
          ),
          child: SizedBox(
            height: _height,
            width: total,
            child: Stack(
              children: [
                if (activeIdx >= 0)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    left: offsets[activeIdx],
                    width: widths[activeIdx],
                    top: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: .17),
                            Colors.white.withValues(alpha: .07),
                          ],
                        ),
                        border: Border.all(color: Colors.white.withValues(alpha: .20)),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      SizedBox(
                        width: widths[i],
                        child: MouseRegion(
                          onEnter: (_) => setState(() => _hover = i),
                          onExit: (_) => setState(() => _hover = _hover == i ? null : _hover),
                          child: Pressable(
                            // The row is tight and measured to the pixel; a growing pill would
                            // shove its neighbours sideways as the highlight moves.
                            scaleOnFocus: false,
                            borderRadius: BorderRadius.circular(999),
                            // The first thing a remote should land on. Without it the app starts
                            // with the highlight nowhere and the first press appears to do nothing.
                            autofocus: isTv && i == 0,
                            onPressed: () => widget.onSelect(_items[i].$1),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _items[i].$2,
                                  style: _style.copyWith(
                                    color: _items[i].$1 == widget.active
                                        ? Colors.white
                                        : (_hover == i ? Colors.white70 : _muted),
                                  ),
                                ),
                                if (_items[i].$1 == 6 && widget.badge > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: _accent,
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Text('${widget.badge}',
                                        style: const TextStyle(
                                            fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The music this device is carrying.
///
/// Shown above the PC's own download queue, and only when there is something to show or something
/// on the way — an empty heading on the machine that holds the library would be noise.
class _OfflineSection extends StatelessWidget {
  const _OfflineSection();

  static String _size(int bytes) {
    if (bytes >= 1000 * 1000 * 1000) return '${(bytes / 1e9).toStringAsFixed(1)} GB';
    if (bytes >= 1000 * 1000) return '${(bytes / 1e6).round()} MB';
    return '${(bytes / 1000).round()} kB';
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to manage on a television, because nothing can be put there — see the button on the
    // album page. Kept as a guard rather than assumed: a Shield that carries copies from an older
    // build should still be able to get rid of them.
    final offline = context.watch<OfflineStore>();
    final tracks = offline.tracks;
    final jobs = offline.jobs;
    if (tracks.isEmpty && jobs.isEmpty) return const SizedBox.shrink();

    // A copy on this device keeps the artist and album it was downloaded WITH, and that is the only
    // list in the app a correction never reached: rename a record and its downloads went on calling
    // themselves by the old name forever. So ask the library, by path, and fall back to the stored
    // strings only for a track the library no longer has — where they are all there is.
    final lib = context.watch<LibraryStore>();
    String artistOf(OfflineTrack t) => lib.trackByPath(t.path)?.artist ?? t.artist;
    String albumOf(OfflineTrack t) => lib.trackByPath(t.path)?.album ?? t.album;

    // Grouped by album, because that is how it was put there and how anyone thinks about it.
    final byAlbum = <String, List<OfflineTrack>>{};
    for (final t in tracks) {
      byAlbum.putIfAbsent('${artistOf(t)}|${albumOf(t)}', () => []).add(t);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('Op dit toestel',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -.4)),
          const SizedBox(width: 14),
          Text('${tracks.length} nummers · ${_size(offline.bytes)}',
              style: const TextStyle(color: _muted, fontSize: 12.5)),
          const Spacer(),
          if (tracks.isNotEmpty)
            TextButton.icon(
              onPressed: () async {
                final sure = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: _panel,
                    title: const Text('Alles van dit toestel halen?',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    content: const Text(
                        'Je muziek blijft gewoon op je pc staan. Alleen de kopieën op dit '
                        'toestel gaan weg.',
                        style: TextStyle(color: _muted, height: 1.4)),
                    actions: [
                      TextButton(
                        autofocus: isTv,
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Annuleren'),
                      ),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Alles weghalen')),
                    ],
                  ),
                );
                if (sure == true) await offline.clear();
              },
              icon: const Icon(Icons.delete_sweep_outlined, size: 17),
              label: const Text('Alles weghalen'),
            ),
        ]),
        const SizedBox(height: 12),
        for (final job in jobs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, value: job.progress, color: _accent),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(job.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text(job.progress == null ? '' : '${(job.progress! * 100).round()}%',
                  style: const TextStyle(color: _muted, fontSize: 12.5)),
            ]),
          ),
        for (final entry in byAlbum.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _line),
              ),
              child: Row(children: [
                const Icon(Icons.offline_pin_rounded, size: 18, color: _accent2),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(albumOf(entry.value.first),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                      Text(
                          '${artistOf(entry.value.first)} · ${entry.value.length} nummers · '
                          '${_size(entry.value.fold(0, (n, t) => n + t.bytes))}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 12)),
                    ],
                  ),
                ),
                TvLabelled(
                  label: 'Weghalen',
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    color: _muted,
                    tooltip: 'Van dit toestel halen',
                    onPressed: () async {
                      for (final t in entry.value) {
                        await offline.remove(t.path);
                      }
                    },
                  ),
                ),
              ]),
            ),
          ),
        const SizedBox(height: 26),
      ],
    );
  }
}

/// Put a record on this device, or take it off again.
///
/// One button for a whole album rather than one per track: nobody wants a record where nine of
/// twelve songs play in the car. It reports how far it is, because a lossless album is a few
/// hundred megabytes and silence for two minutes reads as a broken button.
class _OfflineAlbumButton extends StatefulWidget {
  const _OfflineAlbumButton({required this.album});
  final Album album;

  @override
  State<_OfflineAlbumButton> createState() => _OfflineAlbumButtonState();
}

class _OfflineAlbumButtonState extends State<_OfflineAlbumButton> {
  bool _working = false;
  int _done = 0;

  Future<void> _fetch(OfflineStore offline, RemoteClient client) async {
    final tracks = widget.album.tracks;
    setState(() {
      _working = true;
      _done = 0;
    });
    var failed = 0;
    for (final t in tracks) {
      if (!mounted) return;
      final ok = await offline.download(
        libraryPath: t.path,
        // The path IS the URL in client mode — the catalogue hands out stream URLs — but it is
        // stored without the token, which is added at the moment of use and never written down.
        url: client.authorized(t.path),
        title: t.title,
        artist: t.artist,
        album: widget.album.title,
      );
      if (!ok) failed++;
      if (mounted) setState(() => _done++);
    }
    if (!mounted) return;
    setState(() => _working = false);
    if (failed > 0) {
      _srcToast(context, failed == 1
          ? 'Eén nummer is niet opgehaald. Probeer het opnieuw.'
          : '$failed nummers zijn niet opgehaald. Probeer het opnieuw.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final offline = context.watch<OfflineStore>();
    final client = context.watch<LibraryStore>().remote;
    if (client == null) return const SizedBox.shrink();

    final tracks = widget.album.tracks;
    final here = tracks.where((t) => offline.has(t.path)).length;
    final all = here == tracks.length && tracks.isNotEmpty;

    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: all ? _accent2.withValues(alpha: .18) : _panel2,
        foregroundColor: all ? _accent2 : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
      onPressed: _working
          ? null
          : () async {
              if (all) {
                for (final t in tracks) {
                  await offline.remove(t.path);
                }
                return;
              }
              await _fetch(offline, client);
            },
      icon: Icon(
        _working
            ? Icons.downloading_rounded
            : all
                ? Icons.offline_pin_rounded
                : Icons.download_for_offline_outlined,
        size: 20,
      ),
      label: Text(_working
          ? 'Ophalen $_done/${tracks.length}'
          : all
              ? 'Op dit toestel'
              // Partly here is worth saying: it is the state a failed or cancelled run leaves
              // behind, and "Offline" would claim more than is true.
              : here > 0
                  ? 'Offline ($here/${tracks.length})'
                  : 'Offline bewaren'),
    );
  }
}

// ── Albums grid ──────────────────────────────────────────────────────────────
class AlbumsGrid extends StatelessWidget {
  final List<Album> albums;
  final String? title;
  const AlbumsGrid({super.key, required this.albums, this.title});

  @override
  Widget build(BuildContext context) {
    // Only on the real library view (no search title), the app offers to tidy albums it found to be
    // duplicates of one you already own. It never moves anything on its own — this just opens the
    // dry-run.
    final dupes = title == null ? context.watch<LibraryStore>().duplicates : const <RedundantAlbum>[];
    final pad = pagePad(context);
    // A heading that repeats the bar directly above it.
    //
    // On a phone the top bar already says which section this is, in the same words. Printing
    // “Albums” again cost 22 points of padding and a 22-point line — sixty points of a 915-point
    // screen, spent saying nothing that was not already on screen. A search result still gets its
    // line, because “134 resultaten” is not a repeat of anything.
    final heading = title ?? (isCompact(context) ? null : 'Albums');
    return CustomScrollView(
      slivers: [
        if (heading != null)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 22, pad, 8),
            sliver: SliverToBoxAdapter(
              child: Text(heading,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            ),
          ),
        if (dupes.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, heading == null ? 14 : 0, pad, 8),
            sliver: SliverToBoxAdapter(
              child: InkWell(
                onTap: () async {
                  final done = await showDialog<bool>(
                      context: context, builder: (_) => RedundantCleanupDialog(found: dupes));
                  if (done == true && context.mounted) {
                    _srcToast(context, 'Bibliotheek opgeruimd');
                  }
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _accent.withValues(alpha: .4)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.auto_delete_outlined, size: 18, color: _accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        dupes.length == 1
                            ? '1 album is een dubbele van een album dat je al hebt — opruimen?'
                            : '${dupes.length} albums zijn dubbels van albums die je al hebt — opruimen?',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: _muted),
                  ]),
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, heading == null && dupes.isEmpty ? 12 : 0, pad, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190,
              mainAxisSpacing: 20,
              crossAxisSpacing: 20,
              childAspectRatio: .78,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, i) => AlbumCard(album: albums[i]),
              childCount: albums.length,
            ),
          ),
        ),
      ],
    );
  }
}

class AlbumCard extends StatefulWidget {
  final Album album;
  const AlbumCard({super.key, required this.album});
  @override
  State<AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<AlbumCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final a = widget.album;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Pressable(
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => AlbumDetailPage(album: a))),
        borderRadius: BorderRadius.circular(14),
        // The card already grows and lights up on hover, so focus drives that same state rather
        // than adding a second, different animation on top of it. A remote then gets exactly the
        // look a mouse gets, plus the ring that says which card it is.
        scaleOnFocus: false,
        onFocusChange: (v) => setState(() => _hover = v),
        // Grows on hover, like the TV app. 1.06 is deliberate: the grid's 20px gap is wider than
        // the ~6px a card gains per side, so a raised card never collides with its neighbours
        // (grid children paint in order, so an overlap would be drawn OVER the raised card).
        child: AnimatedScale(
          scale: _hover ? 1.06 : 1,
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _hover ? _panel2 : _panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _hover ? Colors.white.withValues(alpha: .16) : _line),
              boxShadow: _hover
                  ? [BoxShadow(color: Colors.black.withValues(alpha: .45), blurRadius: 22, offset: const Offset(0, 10))]
                  : const [],
            ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: LayoutBuilder(builder: (_, c) => cover(a.cover, size: c.maxWidth))),
              const SizedBox(height: 9),
              Text(a.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              Text(
                  // Six identical "Backstreet Boys" tiles are unusable, however correct the split
                  // is. Naming the pressing is what makes them tellable apart — and choosable.
                  a.edition == null ? a.artist : '${a.artist} · ${a.edition}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Album detail ─────────────────────────────────────────────────────────────
class AlbumDetailPage extends StatefulWidget {
  final Album album;
  const AlbumDetailPage({super.key, required this.album});
  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  late Album album = widget.album;

  /// The record as its label pressed it, so the page can show what is MISSING and not only what
  /// happens to be on disk. Empty until it lands — and empty is harmless: the tracklist then
  /// renders exactly what it always did.
  List<ChoiceTrack> _official = const [];
  String _officialFrom = '';
  int? _officialYear;
  bool _officialBusy = false;

  /// What the OTHER pressings of this record hold that yours doesn't — not missing, just elsewhere.
  List<BonusTrack> _officialBonus = const [];
  bool _showBonus = false;

  /// Did the chosen pressing name every track on disk? When it didn't, the page says so rather
  /// than presenting a near miss as the record.
  bool _officialBestFit = true;

  /// The pressing the tracklist above is read from.
  ///
  /// Handed to AlbumArt so the sleeve comes from that same pressing. Without it the art ran its own
  /// search keyed on how many FILES are here, and three files of a sixteen-track album filtered out
  /// every pressing bigger than seven — so the page could only ever find the single's cover, while
  /// the tile on the home screen showed the album's. Two surfaces, two answers, one record.
  String? _officialMbid;

  /// Which album the tracklist above belongs to, so a merge or a re-pick refetches and a rescan
  /// (which hands this page a NEW Album object for the same record) does not.
  String _officialFor = '';

  bool _showMissing = true;

  /// One album-wide Soulseek search, kept for the whole visit. Fifteen missing tracks is fifteen
  /// searches otherwise, on a login that allows exactly one session.
  List<SoulseekFile> _albumSlsk = const [];
  bool _slskLoaded = false;

  @override
  void initState() {
    super.initState();
    // After the first frame: this reads providers, and initState runs before the element is
    // fully mounted in the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOfficial());
  }

  String get _albumKey => '${artistKey(album.artist)}|${normKey(album.title)}';

  /// Ask the PC what this record is.
  ///
  /// Null when the PC cannot say — it is not paired, it went to sleep, or it has no answer. The
  /// page then shows the tracklist it always showed, which is what is actually on disk; a missing
  /// official tracklist costs the "what is missing" section and nothing else.
  Future<AlbumFacts?> _factsFromPc(LibraryStore lib, String uid, String hash,
      {bool force = false}) async {
    final client = lib.remote;
    if (client == null || uid.isEmpty) return null;
    try {
      final f = await client.albumFacts(uid, force: force);
      if (f == null) return null;
      // The PC files this under its own name for the record; on this side the album id IS the name,
      // and the hash is this device's view of the same files.
      return AlbumFacts(
        uid: uid,
        trackSetHash: hash,
        updatedMs: f.updatedMs,
        source: f.source,
        mbid: f.mbid,
        discogsRelease: f.discogsRelease,
        bestFit: f.bestFit,
        tracklist: f.tracklist,
        bonus: f.bonus,
        year: f.year,
        failedMs: f.failedMs,
      );
    } catch (_) {
      return null;
    }
  }

  /// Take whatever is already known about this record, before the first frame is painted.
  ///
  /// This is the difference between an album page that fills instantly and one that shows a spinner
  /// for six seconds — on every single visit, on every device, because none of them kept the answer
  /// and none of them shared it.
  void _adoptFacts(AlbumFacts f) {
    _official = f.tracklist;
    _officialFrom = f.source;
    _officialYear = f.year;
    _officialBonus = f.bonus;
    _officialBestFit = f.bestFit;
    _officialMbid = f.mbid;
    _officialFor = _albumKey;
  }

  /// The official tracklist: which pressing of this record you actually own.
  ///
  /// Chosen by CONTAINMENT, not by size. Asking for the first pressing big enough to hold the
  /// library picked a Malaysian double CD for an eleven-track album and then reported five gaps,
  /// one of them a Christmas song. The pressing that names every track on disk and adds fewest of
  /// its own is the record; see pickPressing().
  ///
  /// Candidates come from the RELEASE GROUP, not a free-text release search, so every one of them
  /// is a pressing of this same record and a same-named single can never win.
  ///
  /// A pinned pressing wins outright — if you picked an edition in the gallery, that edition is
  /// the answer, not a candidate.
  Future<void> _loadOfficial({bool force = false}) async {
    if (!mounted || album.isSingle) return;
    final a = album;
    final want = _albumKey;
    final lib = context.read<LibraryStore>();
    final mb = context.read<MusicBrainzService>();
    final settings = context.read<AppSettings>();
    final pinnedMbid = lib.pinnedMbid(a);
    final pinned = lib.pinnedRelease(a);

    final uid = lib.uidOf(a);
    final hash = lib.trackSetHashFor(a);
    final known = lib.facts.get(uid);

    // What we already know, unless something below says otherwise. Painted with no spinner and no
    // request — this is the point of the whole exercise.
    if (!needsResolve(known,
        trackSetHash: hash,
        nowMs: DateTime.now().millisecondsSinceEpoch,
        pinnedMbid: pinnedMbid,
        pinned: pinned,
        force: force)) {
      setState(() {
        _adoptFacts(known!);
        _officialBusy = false;
      });
      return;
    }

    setState(() {
      _officialBusy = true;
      _officialFor = want;
    });

    // On a phone, an iPad or the television the PC does the looking up. Not an optimisation — it is
    // the difference between one MusicBrainz search per record and one per record PER DEVICE,
    // against a budget of one request a second that all of them share.
    final fresh = lib.isRemote
        ? await _factsFromPc(lib, uid, hash, force: force)
        : await resolveAlbumFacts(
            a,
            uid: uid,
            trackSetHash: hash,
            mb: mb,
            settings: settings,
            pinnedMbid: pinnedMbid,
            pinned: pinned,
          );
    if (fresh == null) {
      if (mounted) setState(() => _officialBusy = false);
      return;
    }

    // Kept even when it found nothing — an empty answer carries a failedMs, and remembering a "no"
    // for a day is what stops the six-request chain being paid again at every open.
    if (uid.isNotEmpty) {
      // No sidecar from here: the music lives on the PC, and this device has no business writing
      // into a folder it only sees over a stream URL.
      lib.facts.put(fresh, folder: lib.isRemote ? null : lib.sidecarFolderFor(a));
    }

    if (!mounted) return;
    setState(() {
      _adoptFacts(fresh);
      _officialBusy = false;
    });
  }

  // ── Filling the gaps ──────────────────────────────────────────────────────

  /// Stable per-track key so the download button can become that download's progress ring, and
  /// stay bound to it across rebuilds. Keyed on the record, not on this page's object identity.
  String _jobKey(int i) => 'own:$_albumKey:$i';

  /// What this track IS, regardless of what the peer called it. The same rule as the browse page:
  /// Soulseek supplies audio, the app supplies the numbering, the title, the album and the year.
  TrackTags _authorityFor(AlbumSlot s) => TrackTags(
        title: s.title,
        artist: album.artist,
        albumArtist: album.artist,
        album: album.title,
        trackNo: s.number,
        trackTotal: _stampTotal,
        year: _officialYear ?? album.year,
      );

  /// How many tracks to WRITE into a downloaded file — what the album already says, not what the
  /// pressing says.
  ///
  /// TRACKTOTAL is the tag the library separates editions on. Stamping a download with the official
  /// pressing's total while the tracks around it carry another one does not fill a gap in the
  /// record, it adds another opinion to it: Backstreet's Back held files claiming 0, 11 and 12, and
  /// a download stamped 16 made that a fourth. Only a record whose files say nothing at all takes
  /// the pressing's number.
  int get _stampTotal {
    final counts = <int, int>{};
    for (final t in album.tracks) {
      if (t.trackTotal > 0) counts[t.trackTotal] = (counts[t.trackTotal] ?? 0) + 1;
    }
    if (counts.isEmpty) return _official.length;
    var best = counts.entries.first;
    for (final e in counts.entries) {
      if (e.value > best.value) best = e;
    }
    return best.key;
  }

  Future<List<SoulseekFile>> _albumWide() async {
    if (_slskLoaded) return _albumSlsk;
    final soulseek = context.read<SoulseekService>();
    try {
      final r = await soulseek.search('${album.artist} ${album.title}');
      if (mounted) setState(() { _albumSlsk = r; _slskLoaded = true; });
      return r;
    } catch (_) {
      return const [];
    }
  }

  /// Copies of one missing track: the album-wide search first, then a search aimed at this title.
  /// Both filtered to this exact title and running time, so the pool can never fill with a
  /// different song by the same artist.
  Future<List<SoulseekFile>> _candidatesFor(AlbumSlot s) async {
    final soulseek = context.read<SoulseekService>();
    bool fits(SoulseekFile f) =>
        f.isAudio && fileOffersTitle(s.title, s.seconds, album.artist, f.filename, f.durationSec);
    final pool = <String, SoulseekFile>{
      for (final f in (await _albumWide()).where(fits)) '${f.username}|${f.filename}': f
    };
    if (pool.isEmpty) {
      try {
        for (final f in await soulseek.search(soulseekQuery(album.artist, s.title))) {
          if (fits(f)) pool.putIfAbsent('${f.username}|${f.filename}', () => f);
        }
      } catch (_) {}
    }
    return pool.values.toList();
  }

  /// The copy of this slot we already hold somewhere ELSE in the library.
  ///
  /// The tracklist is matched against this album's own files only, so a copy filed under a
  /// composite artist — or a loose rip with no album tag at all — reads as a gap on this page. It
  /// is not one, and fetching it again is exactly what happened: the radio edit came down a second
  /// time, byte for byte identical to a file already on disk.
  Track? _ownedElsewhere(AlbumSlot s) => context.read<LibraryStore>().recordingElsewhere(
        album.artist,
        s.title,
        seconds: s.official?.seconds,
        exclude: album.tracks.map((t) => t.path).toSet(),
      );

  /// Where a track lives, in the fewest words that still place it: its album, or else its folder.
  String _whereIs(Track t) {
    final a = context.read<LibraryStore>().albumForPath(t.path);
    if (a != null) return '“${a.title}”';
    final parts = t.path.split(RegExp(r'[\\/]'));
    return parts.length > 1 ? 'map “${parts[parts.length - 2]}”' : 'je bibliotheek';
  }

  Future<void> _downloadMissing(AlbumSlot s, {String? jobKey, bool force = false}) async {
    final dm = context.read<DownloadManager>();
    final soulseek = context.read<SoulseekService>();
    if (!soulseek.available) {
      _srcToast(context, 'Stel je Soulseek-login in (Instellingen).');
      return;
    }
    if (!force) {
      final have = _ownedElsewhere(s);
      if (have != null) {
        _srcToastAction(
            context,
            '“${s.title}” heb je al — staat onder ${_whereIs(have)}.',
            'Toch downloaden',
            () => _downloadMissing(s, jobKey: jobKey, force: true));
        return;
      }
    }
    _srcToast(context, 'Bron zoeken voor “${s.title}”…');
    final cands = await _candidatesFor(s);
    if (!mounted) return;
    if (cands.isEmpty) {
      _srcToast(context, 'Geen Soulseek-bron gevonden voor “${s.title}”.');
      return;
    }
    try {
      final started = await dm.enqueueSoulseekBest(cands,
          key: jobKey ?? _jobKey(s.index), authority: _authorityFor(s));
      if (mounted) {
        _srcToast(context,
            started ? '“${s.title}” via Soulseek…' : '“${s.title}” loopt al — zie Mijn downloads.');
      }
    } catch (e) {
      if (mounted) _srcToast(context, 'Download mislukt: $e');
    }
  }

  /// A track from another pressing of this record.
  ///
  /// Numbered AFTER your own tracks and stamped with your album's own trackTotal, so it joins the
  /// record instead of splitting it: a bonus that claimed an existing number, or brought its own
  /// pressing's total, is exactly what turned one Backstreet's Back tile into four.
  Future<void> _downloadBonus(int i) async {
    final b = _officialBonus[i];
    await _downloadMissing(
      AlbumSlot(
          index: _official.length + i,
          official: ChoiceTrack('', b.track.title, b.track.seconds)),
      jobKey: 'bonus:$_albumKey:$i',
    );
  }

  /// Every missing track at once.
  ///
  /// The enqueues are NOT awaited in the loop: enqueueSoulseekBest runs the transfer before it
  /// returns, so awaiting each would download them strictly one after another. Fired instead as
  /// they are found — the manager already caps how many run at once on the shared login.
  Future<void> _downloadAllMissing(List<AlbumSlot> missing) async {
    final dm = context.read<DownloadManager>();
    final soulseek = context.read<SoulseekService>();
    if (!soulseek.available) {
      _srcToast(context, 'Stel je Soulseek-login in (Instellingen).');
      return;
    }
    // A copy already on disk is not a gap. Counted rather than quietly dropped: "12 gestart" when
    // you asked for 13 has to be able to say where the thirteenth went.
    final wanted = <AlbumSlot>[];
    var already = 0;
    for (final s in missing) {
      if (_ownedElsewhere(s) != null) {
        already++;
      } else {
        wanted.add(s);
      }
    }
    if (wanted.isEmpty) {
      _srcToast(context, 'Je hebt ze alle $already al — elders in je bibliotheek.');
      return;
    }
    _srcToast(context, 'Bronnen zoeken voor ${wanted.length} ontbrekende nummers…');
    final running = <Future<bool>>[];
    var none = 0;
    for (final s in wanted) {
      final cands = await _candidatesFor(s);
      if (!mounted) return;
      if (cands.isEmpty) {
        none++;
        continue;
      }
      running.add(dm
          .enqueueSoulseekBest(cands, key: _jobKey(s.index), authority: _authorityFor(s))
          .catchError((_) => false));
    }
    if (!mounted) return;
    final started = running.length;
    _srcToast(
        context,
        started == 0
            ? 'Geen bronnen gevonden voor de ontbrekende nummers.'
            : '$started gestart${none > 0 ? ' · $none zonder bron' : ''}'
                '${already > 0 ? ' · $already had je al' : ''} — zie Mijn downloads.');
    await Future.wait(running);
  }

  // A correction rebuilds the album list into new objects; re-point at the regrouped
  // album (matched by track path) so this page shows the fixed title/artist/cover.
  void _refresh() {
    final paths = widget.album.tracks.map((t) => t.path).toSet();
    for (final a in context.read<LibraryStore>().albums) {
      if (a.tracks.any((t) => paths.contains(t.path))) {
        setState(() => album = a);
        // A merge, a correction or a newly picked pressing can all mean a different record — and
        // the pinned edition is exactly what the tracklist is read from.
        if (_albumKey != _officialFor || _official.isEmpty) _loadOfficial();
        return;
      }
    }
    setState(() {});
  }

  Future<void> _edit() async {
    final changed = await showDialog<bool>(context: context, builder: (_) => MetadataEditor(album));
    if (changed == true && mounted) {
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Metadata bijgewerkt'), duration: Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch the library so a delete (or correction) shows up here immediately — _buildAlbums
    // creates NEW Album objects, so holding on to the original would keep showing stale tracks.
    final lib = context.watch<LibraryStore>();
    final paths = album.tracks.map((t) => t.path).toSet();
    Album? fresh;
    for (final a in lib.albums) {
      if (a.tracks.any((t) => paths.contains(t.path))) {
        fresh = a;
        break;
      }
    }
    if (fresh != null) {
      album = fresh;
    } else if (lib.albums.isNotEmpty && !lib.scanning) {
      // Every track of this album is gone — there's nothing left to show.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
    // The record laid next to the files. Recomputed per build on purpose: a download that lands
    // triggers a rescan, `album` above is re-pointed at the new grouping, and the track it filled
    // in flips from missing to owned without this page having to be told.
    final comp = _official.isEmpty
        ? null
        : matchAlbumTracks(_official, album.tracks, album.artist, source: _officialFrom);
    final rows = comp == null
        ? null
        : (_showMissing ? comp.slots : [for (final s in comp.slots) if (!s.missing) s]);
    return Scaffold(
      // Pushed as its own route, so it sits OUTSIDE the shell's overscan margin — its app bar
      // icons and the sleeve were hard against the panel edge, which is the first strip a
      // television crops away. Horizontal and top only: the player bar below draws its own
      // surface to the bottom edge and must keep doing so.
      body: Column(
        children: [
          // Pushed as its own route, so it sits OUTSIDE the shell's overscan margin — its app bar
          // icons and the sleeve were hard against the panel edge, which is the first strip a
          // television crops away. Around the scrolling part only: the player bar below draws its
          // own surface and must keep reaching the edge, or it floats in a black gutter.
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: tvOverscan.left,
                right: tvOverscan.right,
                top: tvOverscan.top,
              ),
              child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  backgroundColor: _bg,
                  pinned: true,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  actions: [
                    if (!album.isSingle)
                      IconButton(
                        icon: const Icon(Icons.auto_stories_outlined),
                        tooltip: 'Boekje doorbladeren',
                        onPressed: () {
                          // Read the pinned pressing here, not inside the route: a booklet is
                          // only worth reading if it is the one that came with this record.
                          final pinned = context.read<LibraryStore>().pinnedRelease(album);
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => BookletScreen(
                              artist: album.artist,
                              album: album.title,
                              pinned: pinned,
                              expectedTracks: album.tracks.length,
                            ),
                          ));
                        },
                      ),
                    if (!album.isSingle)
                      IconButton(
                        icon: const Icon(Icons.photo_library_outlined),
                        tooltip: 'Uitgave kiezen — met hoes, achterkant en cd',
                        onPressed: () async {
                          final picked = await showDialog<bool>(
                              context: context, builder: (_) => ReleaseGallery(album));
                          if (picked == true && mounted) _refresh();
                        },
                      ),
                    if (!album.isSingle)
                      IconButton(
                        icon: const Icon(Icons.merge_rounded),
                        tooltip: 'Een ander album hierin samenvoegen',
                        onPressed: () async {
                          final source = await showDialog<Album>(
                              context: context, builder: (_) => PickAlbumDialog(exclude: album));
                          if (source == null || !context.mounted) return;
                          final done = await showDialog<bool>(
                              context: context,
                              builder: (_) => MergeAlbumsDialog(album: album, absorb: source));
                          if (done == true && mounted) _refresh();
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.edit_rounded),
                      tooltip: 'Metadata corrigeren',
                      onPressed: _edit,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      tooltip: album.isSingle ? 'Nummer verwijderen' : 'Album verwijderen',
                      onPressed: () async {
                        await _confirmDelete(context, '“${album.title}”',
                            album.tracks.map((t) => t.path).toList());
                        if (context.mounted) Navigator.of(context).maybePop();
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                SliverToBoxAdapter(child: _header(context)),
                if (!album.isSingle)
                  SliverToBoxAdapter(
                    child: AlbumInfoPanel(
                        artist: album.artist,
                        album: album.title,
                        trackCount: album.tracks.length,
                        pinned: context.watch<LibraryStore>().pinnedRelease(album),
                        pinnedMbid: context.watch<LibraryStore>().pinnedMbid(album),
                        roles:
                            context.watch<LibraryStore>().albumArtRoles(album.artist, album.title)),
                  ),
                if (!album.isSingle)
                  SliverToBoxAdapter(
                    child: CreditsPanel(artist: album.artist, album: album.title),
                  ),
                if (_officialBusy && _official.isEmpty && !album.isSingle)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(22, 4, 20, 10),
                      child: Row(children: [
                        SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 10),
                        Text('Officiële tracklijst ophalen…',
                            style: TextStyle(color: _muted, fontSize: 12)),
                      ]),
                    ),
                  ),
                // Remembering an answer means being able to be wrong about it for a long time. The
                // pressing is picked automatically, and when it picked badly there has to be a way
                // to say "look again" without waiting a day for the retry window.
                if (!_officialBusy && !album.isSingle)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 20, 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        // A plain TextButton: it already takes focus and already draws the app's
                        // focus ring from the theme, so a remote reaches it without extra wrapping.
                        child: TextButton.icon(
                          onPressed: () => _loadOfficial(force: true),
                          icon: const Icon(Icons.refresh_rounded, size: 15),
                          label: Text(
                            _official.isEmpty
                                ? 'Geen officiële tracklijst gevonden — opnieuw zoeken'
                                : 'Tracklijst opnieuw ophalen',
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: TextButton.styleFrom(foregroundColor: _muted),
                        ),
                      ),
                    ),
                  ),
                if (comp != null && !comp.complete)
                  SliverToBoxAdapter(child: _completenessBar(context, comp)),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      if (rows == null) {
                        return TrackRow(
                            track: album.tracks[i],
                            index: i,
                            queue: album.tracks,
                            albumCover: album.cover);
                      }
                      final s = rows[i];
                      final prev = i == 0 ? null : rows[i - 1];
                      final t = s.track;
                      final row = t == null
                          ? MissingTrackRow(
                              slot: s, jobKey: _jobKey(s.index), onDownload: () => _downloadMissing(s))
                          // The queue is what's playable, so the index has to be this track's place
                          // in the FILES — its place in the release would play the wrong song.
                          : TrackRow(
                              track: t,
                              index: album.tracks.indexOf(t),
                              queue: album.tracks,
                              albumCover: album.cover,
                              // An extra shows no number at all — not even its own tag's. See
                              // AlbumSlot.label.
                              label: s.index < 0 ? '' : s.label);

                      // A double album says which disc you are looking at, and files the pressing
                      // doesn't name say so — left unlabelled the latter read as part of the record,
                      // carrying their own tag's number into the middle of the official run.
                      String? heading;
                      if (s.index == -1 && (prev == null || prev.index != -1)) {
                        heading = 'Niet op deze uitgave';
                      } else if (s.index >= 0 && s.multiDisc && s.disc != (prev?.disc ?? 0)) {
                        heading = 'Schijf ${s.disc}';
                      }
                      if (heading == null) return row;
                      return Column(children: [_listLabel(heading), row]);
                    },
                    childCount: rows?.length ?? album.tracks.length,
                  ),
                ),
                if (_officialBonus.isNotEmpty) SliverToBoxAdapter(child: _bonusSection()),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
              ),
            ),
          ),
          const PlayerBar(),
        ],
      ),
    );
  }

  /// A quiet divider inside the tracklist — a disc number, or where the record stops.
  Widget _listLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(34, 14, 20, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text,
              style: const TextStyle(color: _muted, fontSize: 11, letterSpacing: .4)),
        ),
      );

  /// What the OTHER pressings of this record hold.
  ///
  /// Not missing — never on your record. Backstreet's Back is eleven tracks in Britain and
  /// thirteen in America, and there is a Malaysian second disc with a Christmas song on it. Folded
  /// shut by default, so a record you hold complete still looks complete.
  Widget _bonusSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _showBonus = !_showBonus),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(children: [
                Icon(_showBonus ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 18, color: _muted),
                const SizedBox(width: 8),
                Text('Op andere uitgaves · ${_officialBonus.length}',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(width: 8),
                const Text('niet op jouw persing, wel op deze plaat',
                    style: TextStyle(color: _muted, fontSize: 11.5)),
              ]),
            ),
          ),
          if (_showBonus)
            for (var i = 0; i < _officialBonus.length; i++)
              MissingTrackRow(
                // Numbered after your own tracks: a bonus must never claim a number the record
                // already uses, or the library reads the two as separate pressings.
                // Blank position on purpose: the source pressing's own number would read as a
                // second "10" beside your track 10. The number shown is the one it would get.
                slot: AlbumSlot(
                    index: _official.length + i,
                    official: ChoiceTrack(
                        '', _officialBonus[i].track.title, _officialBonus[i].track.seconds)),
                jobKey: 'bonus:$_albumKey:$i',
                note: _officialBonus[i].edition,
                onDownload: () => _downloadBonus(i),
              ),
        ],
      ),
    );
  }

  /// "12 van 16 nummers · 4 ontbreken", and the way to fill them in.
  ///
  /// Only ever shown when something IS missing: a record you hold complete says so by having no
  /// bar at all, which is quieter than a badge on every album page in the library.
  Widget _completenessBar(BuildContext context, AlbumCompleteness c) {
    final missing = c.missing;
    final narrow = isCompact(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      // Icon, sentence, a text button and a filled button. On a phone the sentence is what gets
      // squeezed, and "4 van 12 nummers" came out one letter per line. Stacked instead: the
      // sentence on its own row, the two buttons under it.
      child: Flex(
        direction: narrow ? Axis.vertical : Axis.horizontal,
        crossAxisAlignment: narrow ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Row(children: [
          const Icon(Icons.playlist_add_check_rounded, size: 18, color: _accent2),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${c.have} van ${c.total} nummers · ${missing.length} ontbreken',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(
                    _officialBestFit
                        ? 'Volgens ${c.source.isEmpty ? 'de officiële uitgave' : c.source}'
                        // No pressing named everything on disk, so this is the closest one rather
                        // than the record. Say so instead of presenting a near miss as fact.
                        : 'Volgens de best passende uitgave — niet al je nummers staan erop',
                    style: const TextStyle(color: _muted, fontSize: 11.5)),
              ],
            ),
          ),
          ]),
          if (narrow) const SizedBox(height: 6),
          TextButton(
            onPressed: () => setState(() => _showMissing = !_showMissing),
            child: Text(_showMissing ? 'Verberg ontbrekende' : 'Toon ontbrekende',
                style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
            onPressed: () => _downloadAllMissing(missing),
            icon: const Icon(Icons.download_rounded, size: 17),
            label: const Text('Ontbrekende downloaden'),
          ),
        ],
      ),
    );
  }

  /// Is the track playing right now one of THIS album's? The disc only turns for the record it
  /// belongs to — every sleeve in the library spinning at once would be nonsense.
  bool _albumIsPlaying(BuildContext context) {
    final p = context.watch<PlayerStore>();
    if (!p.playing) return false;
    final now = p.current?.path;
    return now != null && album.tracks.any((t) => t.path == now);
  }

  Widget _header(BuildContext context) {
    final player = context.read<PlayerStore>();
    final narrow = isCompact(context);
    final pad = narrow ? 18.0 : 28.0;

    // The sleeve asks for more room than its own width: the disc slides out to the side, and
    // AlbumArt reserves size * 1.62 for that. Beside a title column on a phone that came to 404 of
    // 412 points, so the title got eight and printed one letter per line.
    //
    // Sized from what there actually is rather than from a number chosen for a desktop window, and
    // divided by 1.62 so the disc has somewhere to go instead of sliding off the screen.
    final available = MediaQuery.sizeOf(context).width - pad * 2;
    // Divided by what the disc ACTUALLY reserves, not by a number copied here. When the travel was
    // cut to .30 in portrait this still said 1.62, so the sleeve was sized for a stride the disc no
    // longer takes and left a band of empty screen beside it.
    final artSize =
        narrow ? (available / (1 + discTravelFactor(context))).clamp(120.0, 260.0) : 200.0;

    final art = AlbumArt(
            artist: album.artist,
            album: album.title,
            identity: context.watch<LibraryStore>().uidOf(album),
            size: artSize,
            fallback: album.cover,
            chosen: album.correctedCover,
            pinned: context.watch<LibraryStore>().pinnedRelease(album),
            // Your own choice still wins; otherwise the pressing this page is describing. Without
            // that the art searched on its own and was steered by the FILE count — three files of a
            // sixteen-track album ruled out every pressing over seven, so it found the single.
            pinnedMbid: context.watch<LibraryStore>().pinnedMbid(album) ?? _officialMbid,
            trackCount: _official.isNotEmpty ? _official.length : album.tracks.length,
            playing: _albumIsPlaying(context),
            roles: context.watch<LibraryStore>().albumArtRoles(album.artist, album.title),
          );

    final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(album.isSingle ? 'Single' : 'Album', style: const TextStyle(color: _muted)),
                const SizedBox(height: 6),
                Text(album.title,
                    style: TextStyle(fontSize: narrow ? 24 : 30, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                // The artist is a link: from a record you're holding, the obvious next question is
                // "what else did they make".
                // A Wrap and not a Row. “Sophie Ellis-Bextor · 2001 · Dance-pop · 12 nummers”
                // is wider than a phone, and a Row that wide does not shrink or ellipsize — it
                // overflows, and Flutter paints the yellow-and-black bar over the record you were
                // looking at. Here the year and the rest simply drop to a second line.
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ArtistNames(names: [album.artist], style: const TextStyle(color: _muted)),
                    Text(
                      [
                        '',
                        if (album.year != null) '${album.year}',
                        if (album.genre != null) album.genre!,
                        '${album.tracks.length} nummers',
                      ].join(' · '),
                      style: const TextStyle(color: _muted),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                // Wrapped on a phone rather than a Row. Afspelen, Offline bewaren and Radio are
                // 447 points side by side and a phone has 411 — the row hung 36 pixels off the
                // right edge, with "Radio" half outside the screen.
                Wrap(
                  spacing: narrow ? 8 : 0,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                      ),
                      // Where the highlight lands when an album opens on a television. Flutter's
                      // default is the first focusable thing in the route, which here is the back
                      // arrow — so opening a record put the highlight on "leave this record".
                      autofocus: isTv,
                      onPressed: () => player.playQueue(album.tracks, 0, cover: album.cover),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Afspelen'),
                    ),
                    if (!narrow) const SizedBox(width: 10),
                    // Only where the music lives somewhere else AND where carrying a copy makes
                    // sense. On the PC the files ARE the library. And a television is bolted to the
                    // wall next to the machine it streams from, on mains power, with a few gigabytes
                    // of storage it needs for apps — filling that with lossless copies of records
                    // it can already play is all cost and no benefit.
                    if (context.watch<LibraryStore>().isRemote && !isTv) ...[
                      _OfflineAlbumButton(album: album),
                      if (!narrow) const SizedBox(width: 10),
                    ],
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _panel2,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      ),
                      onPressed: () => startRadio(context, album.artist),
                      icon: const Icon(Icons.radio_rounded, size: 20),
                      label: const Text('Radio'),
                    ),
                    // Offered only where there is something to merge: the library holds more than
                    // one pressing of this record, or the user already told us to keep them one.
                    if (album.edition != null || context.watch<LibraryStore>().isMerged(album)) ...[
                      if (!narrow) const SizedBox(width: 10),
                      Builder(builder: (context) {
                        final merged = context.watch<LibraryStore>().isMerged(album);
                        return FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _panel2,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          ),
                          onPressed: () {
                            if (merged) {
                              // Splitting moves nothing, so it needs no plan.
                              context.read<LibraryStore>().unmergeEditions(album);
                              _srcToast(context, 'Uitgaves weer apart');
                              return;
                            }
                            // Merging rewrites the folder tree. Show what it would do first.
                            showDialog<bool>(
                                context: context, builder: (_) => MergeAlbumsDialog(album: album));
                          },
                          icon: Icon(merged ? Icons.call_split_rounded : Icons.merge_rounded, size: 20),
                          label: Text(merged ? 'Uitgaves splitsen' : 'Uitgaves samenvoegen'),
                        );
                      }),
                    ],
                  ],
                ),
              ],
            );

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 8, pad, 24),
      // Stacked on a phone, side by side everywhere else. The sleeve and a title column simply do
      // not both fit across 412 points, and squeezing them is what produced a column of single
      // letters.
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [art, const SizedBox(height: 16), details],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [art, const SizedBox(width: 24), Expanded(child: details)],
            ),
    );
  }
}

/// Manual metadata editor: search Deezer/Discogs/MusicBrainz for the correct
/// release and apply its cover/artist/title to a wrong album or single.
class MetadataEditor extends StatefulWidget {
  final Album album;
  const MetadataEditor(this.album, {super.key});
  @override
  State<MetadataEditor> createState() => _MetadataEditorState();
}

class _MetadataEditorState extends State<MetadataEditor> {
  late final TextEditingController _artist = TextEditingController(text: widget.album.artist);
  late final TextEditingController _title = TextEditingController(text: widget.album.title);
  late final TextEditingController _query =
      TextEditingController(text: '${widget.album.artist} ${widget.album.title}'.trim());
  String _provider = 'Deezer';
  bool _searching = false;

  /// What went wrong last time, if anything. Without this a failed lookup left the spinner turning
  /// for ever — the await below had no catch, so `_searching` was never set back and the dialog
  /// looked frozen rather than broken.
  String? _searchError;
  bool _applying = false;
  List<MetaResult> _results = const [];
  MetaResult? _picked;

  /// The release id, held separately from [_picked]. Kept apart on purpose: the pin arrived empty
  /// once and everything downstream then silently fell back to guessing, so this no longer depends
  /// on the picked object still being the same instance at apply time.
  int? _pickedRelease;

  /// The MusicBrainz pressing picked, when the answer came from there.
  String? _pickedMbid;
  Uint8List? _pickedCover;

  @override
  void dispose() {
    _artist.dispose();
    _title.dispose();
    _query.dispose();
    for (final n in _editFocus.values) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _search() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searchError = null;
      _results = const [];
    });
    var res = const <MetaResult>[];
    String? failure;
    try {
      // The timeout is the point as much as the catch: a provider that accepts the connection and
      // then says nothing would otherwise hold this dialog open indefinitely.
      res = await MetadataSearch(context.read<AppSettings>())
          .search(_provider, _query.text, track: widget.album.isSingle)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      failure = '$_provider antwoordde niet op tijd. Probeer het opnieuw of kies een andere bron.';
    } catch (e) {
      failure = _provider == 'Discogs'
          ? 'Discogs gaf een fout: $e\nStaat je Discogs-token in Instellingen?'
          : '$_provider gaf een fout: $e';
    }
    if (!mounted) return;
    setState(() {
      _results = res;
      _searching = false;
      _searchError = failure;
    });
  }

  Future<void> _pick(MetaResult m) async {
    final newTitle = widget.album.isSingle ? m.title : m.album;
    setState(() {
      _picked = m;
      _pickedRelease = m.releaseId;
      _pickedMbid = m.mbid;
      _pickedCover = null;
      if (m.artist.isNotEmpty) _artist.text = m.artist;
      if (newTitle.isNotEmpty) _title.text = newTitle;
    });
    if (m.coverUrl != null) {
      final bytes = await CoverEnricher(context.read<AppSettings>()).downloadImage(m.coverUrl!);
      if (mounted && identical(_picked, m)) setState(() => _pickedCover = bytes);
    }
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    try {
      await _applyInner();
    } catch (e) {
      // Same trap as _search had: without this the button spins for ever and the dialog looks
      // frozen, while what actually happened — the PC refused it, the network dropped — is thrown
      // away. On a Mac or an iPad this is the whole write path, so it must say what went wrong.
      if (!mounted) return;
      setState(() => _applying = false);
      _srcToast(context, 'Aanpassen mislukte: $e');
    }
  }

  Future<void> _applyInner() async {
    await context.read<LibraryStore>().applyCorrection(
          widget.album,
          context.read<AppSettings>(),
          artist: _artist.text,
          albumTitle: widget.album.isSingle ? null : _title.text,
          title: widget.album.isSingle ? _title.text : null,
          coverBytes: _pickedCover,
          discogsRelease: _pickedRelease,
          mbid: _pickedMbid,
        );
    // Says out loud what was pinned. The pin went missing twice while every line of the path read
    // correctly, so this is no longer something to reason about — it is something to see.
    if (mounted) {
      _srcToast(
          context,
          _pickedMbid != null
              ? 'Aangepast — MusicBrainz-uitgave vastgezet'
              : _pickedRelease == null
                  ? 'Aangepast — geen uitgave vastgezet'
                  : 'Aangepast — uitgave $_pickedRelease vastgezet');
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isSingle = widget.album.isSingle;
    return Dialog(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth(context, 580),
        height: dialogHeight(context, 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Metadata corrigeren',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(false)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cover(_pickedCover ?? widget.album.cover, size: 88),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      children: [
                        _field(_artist, 'Artiest'),
                        const SizedBox(height: 8),
                        _field(_title, isSingle ? 'Titel' : 'Album'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Source, query and button. On a phone the query is what gets crushed — between a
              // "Deezer" dropdown and a "Zoeken" button it came out about fifty points wide and
              // showed two characters of what you typed. So on a phone it gets its own line.
              Builder(builder: (context) {
                final narrow = isCompact(context);
                final source = Container(
                  decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _provider,
                      dropdownColor: _panel2,
                      items: MetadataSearch.providers
                          .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: (v) => setState(() => _provider = v ?? 'Deezer'),
                    ),
                  ),
                );
                final field = TextField(
                  controller: _query,
                  focusNode: _editFocusFor(_query),
                  onSubmitted: (_) => _search(),
                  decoration: _inputDeco('Zoeken…'),
                );
                final button = FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _accent),
                  onPressed: _searching ? null : _search,
                  child: const Text('Zoeken'),
                );
                if (!narrow) {
                  return Row(children: [
                    source,
                    const SizedBox(width: 8),
                    Expanded(child: field),
                    const SizedBox(width: 8),
                    button,
                  ]);
                }
                return Column(
                  children: [
                    Row(children: [
                      source,
                      const SizedBox(width: 8),
                      Expanded(child: button),
                    ]),
                    const SizedBox(height: 8),
                    field,
                  ],
                );
              }),
              const SizedBox(height: 12),
              Expanded(
                child: _searching
                    ? const Center(child: CircularProgressIndicator(color: _accent))
                    : _results.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                _searchError ?? 'Zoek hierboven een correcte versie.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: _searchError == null ? _muted : Colors.orangeAccent,
                                    height: 1.4),
                              ),
                            ))
                        : ListView.builder(
                            itemCount: _results.length,
                            itemBuilder: (_, i) {
                              final m = _results[i];
                              final sel = identical(_picked, m);
                              return InkWell(
                                onTap: () => _pick(m),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: sel ? _accent.withValues(alpha: 0.18) : _panel2,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: sel ? _accent : Colors.transparent),
                                  ),
                                  child: Row(
                                    children: [
                                      _netCover(m.coverUrl, size: 44, radius: 6),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(m.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontWeight: FontWeight.w600)),
                                            Text(
                                                // The pressing, where the provider knows it. Five
                                                // rows reading "30 — Adele" give nothing to choose
                                                // between; a format and a catalogue number do.
                                                m.detail ?? (m.artist.isEmpty ? '—' : m.artist),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(color: _muted, fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                      if (sel) const Icon(Icons.check_circle_rounded, color: _accent),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Annuleren', style: TextStyle(color: _muted)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _accent),
                    onPressed: _applying ? null : _apply,
                    child: _applying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Toepassen'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Same bargain as everywhere else on a television: skipped when arrowing, entered with OK.
  ///
  /// Three fields here, and this dialog is the one place you correct a record by hand — so the
  /// keyboard opening itself over the whole screen the moment the highlight passes by is worse
  /// than usual: you cannot see what you are correcting.
  final _editFocus = <TextEditingController, FocusNode>{};

  FocusNode _editFocusFor(TextEditingController c) =>
      _editFocus.putIfAbsent(c, () => FocusNode(skipTraversal: isTv));

  Widget _field(TextEditingController c, String label) => MaybePressable(
        enabled: isTv,
        onPressed: () => _editFocusFor(c).requestFocus(),
        borderRadius: BorderRadius.circular(8),
        child: TextField(
          controller: c,
          focusNode: _editFocusFor(c),
          decoration: _inputDeco(label),
        ),
      );

  InputDecoration _inputDeco(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _muted),
        isDense: true,
        filled: true,
        fillColor: _panel2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      );
}

class TrackRow extends StatefulWidget {
  final Track track;
  final int index;
  final List<Track> queue;
  final Uint8List? albumCover;

  /// The number the RELEASE gives this track, when the page knows it. Overrides the file's own
  /// tag, which is whatever the peer that uploaded it typed. A string, because a double album
  /// numbers from 1 on each disc and reads "2-1".
  final String? label;
  const TrackRow(
      {super.key,
      required this.track,
      required this.index,
      required this.queue,
      this.albumCover,
      this.label});
  @override
  State<TrackRow> createState() => _TrackRowState();
}

/// What the hover icons offer, reachable by holding OK.
///
/// The same two actions and the same dialogs — this is a way IN to them, not a second way of doing
/// them. The highlight starts on "Sluiten", because one of the two deletes a file.
Future<void> _trackOptions(BuildContext context, Track t) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _panel,
      title: Text(titleWithoutFeat(t.title),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      content: const Text('Wat wil je met dit nummer doen?',
          style: TextStyle(color: _muted, height: 1.4)),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Sluiten'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'move'),
          child: const Text('Naar ander album'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'delete'),
          child: const Text('Verwijderen'),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'move') {
    final from = context.read<LibraryStore>().albumForPath(t.path);
    await showDialog<bool>(context: context, builder: (_) => MoveTrackDialog(track: t, from: from));
  } else {
    await _confirmDelete(context, '“${t.title}”', [t.path]);
  }
}

class _TrackRowState extends State<TrackRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.track;
    final current = context.watch<PlayerStore>().current;
    final isCurrent = current?.path == t.path;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Pressable(
        onPressed: () => context
            .read<PlayerStore>()
            .playQueue(widget.queue, widget.index, cover: widget.albumCover),
        // Hold OK for what the mouse reaches by hovering.
        //
        // "Verplaatsen" and "Verwijderen" live INSIDE this row, and Flutter's directional traversal
        // can never select a node whose rectangle lies within the focused one's — so with a remote
        // those two were simply unreachable, and moving or deleting a single track could not be
        // done from the sofa at all. A held OK is the ordinary television gesture for "options".
        //
        // Television only: on a desktop a long press is a held mouse button, which nobody means as
        // "open a menu", and the hover icons are already right there.
        onLongPress: isTv ? () => _trackOptions(context, t) : null,
        borderRadius: BorderRadius.circular(10),
        // A list of rows: one growing would push every row under it down as the highlight runs
        // through the album. The row already lights up on hover, and focus drives that.
        scaleOnFocus: false,
        onFocusChange: (v) => setState(() => _hover = v),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: isCurrent
                ? _accent.withValues(alpha: .16)
                : (_hover ? _panel : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: _hover
                    ? const Icon(Icons.play_arrow_rounded, size: 18, color: _accent)
                    : Text(widget.label ?? '${t.trackNo > 0 ? t.trackNo : widget.index + 1}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: _muted, fontSize: 13)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Builder(builder: (context) {
                  // Guests named in this track's own tags, shown under the title. No catalogue
                  // lookup here — that would be one network call per row of every album.
                  final guests = splitFeatured(t.artist, t.title).featured;
                  final title = Text(titleWithoutFeat(t.title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w600, color: isCurrent ? _accent2 : _text));
                  if (guests.isEmpty) return title;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      // Only the guests — the album already belongs to the main artist. Out of the
                      // highlight's path on a television for the same reason as the track lists:
                      // this sits inside a row that is itself the thing you want to press.
                      _maybeFocusable(
                        ArtistNames(names: guests, style: const TextStyle(color: _muted, fontSize: 11.5)),
                      ),
                    ],
                  );
                }),
              ),
              _qualityBadge(_trackQuality(t)),
              Text(_fmt(t.duration), style: const TextStyle(color: _muted, fontSize: 13)),
              // Both appear on hover, so neither can be hit by accident.
              SizedBox(
                width: 36,
                child: _hover
                    ? IconButton(
                        icon: const Icon(Icons.drive_file_move_outline, size: 17),
                        color: _muted,
                        tooltip: 'Naar ander album verplaatsen',
                        // A bare icon with no padding is a hit area the size of the glyph — hard to
                        // land on with a mouse, and the row underneath swallows every near miss and
                        // starts playing instead. Give it something to aim at.
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        // The album comes from the library rather than a parameter: every caller
                        // of this row would otherwise have to thread it through.
                        onPressed: () {
                          // No source album is not a reason to do nothing — see MoveTrackDialog.from.
                          final from = context.read<LibraryStore>().albumForPath(t.path);
                          showDialog<bool>(context: context, builder: (_) => MoveTrackDialog(track: t, from: from));
                        },
                      )
                    : null,
              ),
              SizedBox(
                width: 36,
                child: _hover
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 17),
                        color: _muted,
                        tooltip: 'Nummer verwijderen',
                        // A bare icon with no padding is a hit area the size of the glyph — hard to
                        // land on with a mouse, and the row underneath swallows every near miss and
                        // starts playing instead. Give it something to aim at.
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: () => _confirmDelete(context, '“${t.title}”', [t.path]),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A track the record has and the library hasn't.
///
/// Deliberately built like [TrackRow] and dimmed rather than hidden: the album is the record, and
/// a gap in it is something to see and act on, not something to leave out of the list.
class MissingTrackRow extends StatefulWidget {
  final AlbumSlot slot;
  final String jobKey;
  final VoidCallback onDownload;

  /// What the chip says instead of "niet in bibliotheek" — for a track that is on another
  /// pressing, which pressing that is.
  final String? note;
  const MissingTrackRow(
      {super.key,
      required this.slot,
      required this.jobKey,
      required this.onDownload,
      this.note});
  @override
  State<MissingTrackRow> createState() => _MissingTrackRowState();
}

class _MissingTrackRowState extends State<MissingTrackRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.slot;
    final dim = _muted.withValues(alpha: .75);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: _hover ? _panel.withValues(alpha: .6) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(s.label,
                  textAlign: TextAlign.right, style: TextStyle(color: dim, fontSize: 13)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: dim, fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _line),
                    ),
                    child: Text(widget.note ?? 'niet in bibliotheek',
                        style: TextStyle(color: dim, fontSize: 10.5, letterSpacing: .2)),
                  ),
                ],
              ),
            ),
            if (s.seconds != null && s.seconds! > 0)
              Text(_fmt(Duration(seconds: s.seconds!)), style: TextStyle(color: dim, fontSize: 13)),
            const SizedBox(width: 8),
            SizedBox(
              width: 72,
              child: Align(
                alignment: Alignment.centerRight,
                child: _downloadControl(context,
                    jobKey: widget.jobKey,
                    onDownload: widget.onDownload,
                    tooltip: 'Dit nummer downloaden via Soulseek'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Artists ──────────────────────────────────────────────────────────────────
class ArtistsView extends StatefulWidget {
  final LibraryStore lib;

  /// Albums already narrowed by the shell's search/filter (defaults to the whole library).
  final List<Album>? albums;

  /// How this view tells the shell it has a layer of its own to close.
  ///
  /// Handed up rather than handled here with a second PopScope. Both would be registered on the
  /// SAME route — this view is a swapped-in body, not a route — so one press of BACK fires both:
  /// the shell would jump to Start while this cleared its selection, and you would lose your place
  /// in the artist list. Measured on the Shield, not guessed.
  /// Told when an artist page opens or closes, and what that page is called — the shell puts
  /// the name in the bar at the top and the arrow beside it.
  final void Function(VoidCallback? pop, {String? title})? onInnerLayer;

  const ArtistsView({super.key, required this.lib, this.albums, this.onInnerLayer});
  @override
  State<ArtistsView> createState() => _ArtistsViewState();
}

class _ArtistsViewState extends State<ArtistsView> {
  String? _selected;

  List<Album> get _source => widget.albums ?? widget.lib.albums;

  /// Select an artist, or go back to the grid, and tell the shell either way.
  void _select(String? name) {
    setState(() => _selected = name);
    widget.onInnerLayer?.call(name == null ? null : () => _select(null), title: name);
  }

  @override
  void dispose() {
    // The shell must not keep a callback into a view that is gone.
    widget.onInnerLayer?.call(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_selected != null) {
      return ArtistDetailView(
        name: _selected!,
        libraryAlbums: _source.where((a) => a.artist == _selected!).toList(),
        onBack: () => _select(null),
        onArtist: _select,
      );
    }
    // Only artists that still have a matching album after the shell's search/filter.
    final visible = {for (final a in _source) a.artist};
    final artists = widget.lib.artists.where(visible.contains).toList();
    if (artists.isEmpty) {
      return const Center(child: Text('Geen artiesten gevonden.', style: TextStyle(color: _muted)));
    }
    final pad = pagePad(context);
    final filtered = artists.length != widget.lib.artists.length;
    // Same as the album grid: the bar above says “Artiesten” already. What it cannot say is that
    // you are looking at a filtered list, so that line stays.
    final heading = isCompact(context)
        ? (filtered ? '${artists.length} artiesten' : null)
        : 'Artiesten${filtered ? " · ${artists.length}" : ""}';
    return CustomScrollView(
      slivers: [
        if (heading != null)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 22, pad, 8),
            sliver: SliverToBoxAdapter(
              child: Text(heading,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, heading == null ? 12 : 0, pad, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 20,
                crossAxisSpacing: 20,
                childAspectRatio: .82),
            delegate: SliverChildBuilderDelegate((_, i) {
              final name = artists[i];
              // Most artists have no photo, and then this is one of their record sleeves. Which of
              // the two it is decides how the tile draws it, so it is passed on rather than
              // guessed at further down.
              final photo = widget.lib.artistImages[name];
              return _ArtistCard(
                name: name,
                image: photo ?? _source.firstWhere((a) => a.artist == name).cover,
                isPhoto: photo != null,
                onTap: () => _select(name),
              );
            }, childCount: artists.length),
          ),
        ),
      ],
    );
  }
}

/// Who made this record. Names are links wherever there is something behind them, which is the
/// thread Roon pulls: from a record you like, to the producer, to everything else they touched.
class CreditsPanel extends StatefulWidget {
  final String artist, album;
  const CreditsPanel({super.key, required this.artist, required this.album});

  @override
  State<CreditsPanel> createState() => _CreditsPanelState();
}

class _CreditsPanelState extends State<CreditsPanel> {
  List<Credit> _credits = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CreditsPanel old) {
    super.didUpdateWidget(old);
    if (old.artist != widget.artist || old.album != widget.album) {
      setState(() => _credits = const []);
      _load();
    }
  }

  Future<void> _load() async {
    final artist = widget.artist, album = widget.album;
    final c = await CreditsService(context.read<AppSettings>()).forAlbum(artist, album);
    if (!mounted || artist != widget.artist || album != widget.album) return;
    setState(() => _credits = c);
  }

  @override
  Widget build(BuildContext context) {
    if (_credits.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CREDITS',
              style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .8)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final c in _credits.take(14))
                _CreditChip(credit: c),
            ],
          ),
        ],
      ),
    );
  }
}

class _CreditChip extends StatefulWidget {
  final Credit credit;
  const _CreditChip({required this.credit});

  @override
  State<_CreditChip> createState() => _CreditChipState();
}

class _CreditChipState extends State<_CreditChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Pressable(
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => PersonPage(widget.credit.name, role: widget.credit.role))),
        borderRadius: BorderRadius.circular(999),
        scaleOnFocus: false,
        onFocusChange: (v) => setState(() => _hover = v),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: _hover ? _panel2 : _panel,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _hover ? Colors.white.withValues(alpha: .18) : _line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.credit.role,
                  style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(width: 7),
              Text(widget.credit.name,
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600, color: _hover ? Colors.white : null)),
            ],
          ),
        ),
      ),
    );
  }
}

/// What one person made. Reached by tapping a credit; a name with nothing behind it says so
/// plainly rather than showing an empty page.
class PersonPage extends StatefulWidget {
  final String name;
  final String? role;
  const PersonPage(this.name, {super.key, this.role});

  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  List<CreditedWork> _works = const [];
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final w = await CreditsService(context.read<AppSettings>()).producedBy(widget.name);
    if (!mounted) return;
    setState(() {
      _works = w;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: ArtistBackdrop(
        name: widget.name,
        child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                ArtistHero(
                  name: widget.name,
                  ownBackdrop: false,
                  subtitle: widget.role == null ? null : '${widget.role} · ${_works.length} producties',
                  actions: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: _accent, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10)),
                      onPressed: () => openArtist(context, widget.name),
                      icon: const Icon(Icons.person_rounded, size: 18),
                      label: const Text('Als artiest'),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 0, 0),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
          if (_busy)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(color: _accent)),
              ),
            )
          else if (_works.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Text('Geen verdere producties gevonden voor deze naam.',
                    style: TextStyle(color: _muted)),
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
                child: Text('Werkte mee aan  ${_works.length}',
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final w = _works[i];
                  return ListTile(
                    title: Text(w.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: w.year == null ? null : Text(w.year!, style: const TextStyle(color: _muted, fontSize: 12)),
                    trailing: const Icon(Icons.search_rounded, size: 17, color: _muted),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => Scaffold(
                        backgroundColor: _bg,
                        appBar: AppBar(backgroundColor: _bg, title: Text(w.title)),
                        body: SingleChildScrollView(child: SourcesView(query: '${widget.name} ${w.title}')),
                      ),
                    )),
                  );
                },
                childCount: _works.length,
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
        ),
      ),
    );
  }
}

/// Everything about one artist on a single page: what you own, their whole catalogue with the
/// gaps visible, who they sound like, and who worked on the records.
///
/// The split is the point — "in mijn bibliotheek" answers "what can I play", "discografie"
/// answers "what else is there", and a release you already own is marked as such so the gap in a
/// collection is obvious at a glance.
class ArtistDetailView extends StatefulWidget {
  final String name;
  final List<Album> libraryAlbums;
  final VoidCallback onBack;
  final void Function(String name)? onArtist;
  const ArtistDetailView({
    super.key,
    required this.name,
    required this.libraryAlbums,
    required this.onBack,
    this.onArtist,
  });

  @override
  State<ArtistDetailView> createState() => _ArtistDetailViewState();
}

class _ArtistDetailViewState extends State<ArtistDetailView> {
  final _catalog = CatalogService();
  List<CatalogAlbum> _discography = [];
  List<CatalogArtist> _related = [];
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ArtistDetailView old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name) {
      setState(() {
        _discography = [];
        _related = [];
        _busy = true;
      });
      _load();
    }
  }

  Future<void> _load() async {
    final name = widget.name;
    try {
      final hits = await _catalog.searchArtists(name);
      if (hits.isEmpty) {
        if (mounted && name == widget.name) setState(() => _busy = false);
        return;
      }
      final id = hits.first.id;
      final albums = await _catalog.artistAlbums(id);
      final related = await _catalog.relatedArtists(id);
      if (!mounted || name != widget.name) return;
      setState(() {
        _discography = albums;
        _related = related;
        _busy = false;
      });
    } catch (_) {
      if (mounted && name == widget.name) setState(() => _busy = false);
    }
  }

  /// The library album matching a catalogue release, if you own it.
  Album? _owned(CatalogAlbum a) {
    final key = normKey(a.title);
    for (final l in widget.libraryAlbums) {
      if (normKey(l.title) == key) return l;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final trackCount = widget.libraryAlbums.fold<int>(0, (s, a) => s + a.tracks.length);
    final bio = lib.artistBios[widget.name];

    // Split the way a discography is actually read: the records first, the odds and ends after.
    final main = _discography.where((a) => a.recordType == 'album').toList();
    final rest = _discography.where((a) => a.recordType != 'album').toList();

    return ArtistBackdrop(
      name: widget.name,
      fallbackImage: lib.artistImages[widget.name],
      child: CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Stack(
            children: [
              ArtistHero(
                name: widget.name,
                ownBackdrop: false,
                subtitle: '${widget.libraryAlbums.length} albums · $trackCount nummers in je bibliotheek',
                fallbackImage: lib.artistImages[widget.name],
                actions: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: _accent, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10)),
                    onPressed: () => startRadio(context, widget.name),
                    icon: const Icon(Icons.radio_rounded, size: 18),
                    label: const Text('Radio'),
                  ),
                  const SizedBox(width: 10),
                  // The app guesses portrait-vs-backdrop from the shape of a picture; a guess is
                  // exactly the thing worth being able to overrule.
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: _panel2,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                    onPressed: () =>
                        showDialog<void>(context: context, builder: (_) => ArtistArtGallery(widget.name)),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Foto kiezen'),
                  ),
                ],
              ),
              // Only where nothing else offers the way back. On a phone the bar at the top of
              // the screen carries the artist's name and an arrow, and a second arrow drawn over
              // the photo — in accent purple, on whatever colours that photo happens to have — was
              // both unreadable and redundant.
              if (!isCompact(context))
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 0, 0),
                  child: TextButton.icon(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('Artiesten'),
                  ),
                ),
            ],
          ),
        ),
        if (bio != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
              child: BioText(widget.name, bio),
            ),
          ),
        _header('In mijn bibliotheek', '${widget.libraryAlbums.length}'),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 190, mainAxisSpacing: 20, crossAxisSpacing: 20, childAspectRatio: .78),
            delegate: SliverChildBuilderDelegate(
              (_, i) => AlbumCard(album: widget.libraryAlbums[i]),
              childCount: widget.libraryAlbums.length,
            ),
          ),
        ),
        if (_busy)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator(color: _accent, strokeWidth: 2.4)),
            ),
          ),
        if (main.isNotEmpty) ...[
          _header('Discografie', '${main.length} albums'),
          _discoGrid(main),
        ],
        if (rest.isNotEmpty) ...[
          _header('Singles & EP’s', '${rest.length}'),
          _discoGrid(rest),
        ],
        if (_related.isNotEmpty) ...[
          _header('Klinkt als', '${_related.length}'),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 176,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: _related.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, i) {
                  final r = _related[i];
                  return _RelatedArtistCard(
                    artist: r,
                    inLibrary: lib.hasArtist(r.name),
                    onTap: () {
                      // Someone you already own opens your own page; anyone else opens theirs.
                      if (lib.hasArtist(r.name) && widget.onArtist != null) {
                        widget.onArtist!(lib.displayArtist(r.name));
                      } else {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArtistBrowsePage(r)));
                      }
                    },
                  );
                },
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
      ),
    );
  }

  Widget _header(String title, String badge) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
          child: Row(
            children: [
              Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Text(badge, style: const TextStyle(color: _muted, fontSize: 12.5)),
            ],
          ),
        ),
      );

  Widget _discoGrid(List<CatalogAlbum> items) => SliverPadding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 190, mainAxisSpacing: 20, crossAxisSpacing: 20, childAspectRatio: .78),
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              final a = items[i];
              final owned = _owned(a);
              return _DiscoCard(
                album: a,
                artist: widget.name,
                owned: owned,
              );
            },
            childCount: items.length,
          ),
        ),
      );
}

/// A release from the catalogue, marked with whether it's already on your shelf.
class _DiscoCard extends StatefulWidget {
  final CatalogAlbum album;
  final String artist;
  final Album? owned;
  const _DiscoCard({required this.album, required this.artist, this.owned});

  @override
  State<_DiscoCard> createState() => _DiscoCardState();
}

class _DiscoCardState extends State<_DiscoCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.album;
    final have = widget.owned != null;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Pressable(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => have
              ? AlbumDetailPage(album: widget.owned!)
              : AlbumBrowsePage(widget.artist, a),
        )),
        borderRadius: BorderRadius.circular(14),
        scaleOnFocus: false,
        onFocusChange: (v) => setState(() => _hover = v),
        child: AnimatedScale(
          scale: _hover ? 1.06 : 1,
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _hover ? _panel2 : _panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: have ? _accent2.withValues(alpha: .45) : _line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (_, c) => Stack(
                      children: [
                        _netCover(a.cover, size: c.maxWidth),
                        if (have)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(color: _accent2, shape: BoxShape.circle),
                              child: const Icon(Icons.check_rounded, size: 13, color: Colors.black),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Text(a.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                Text(
                  have ? 'in je bibliotheek' : (a.year ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: have ? _accent2 : _muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A "sounds like" artist, flagged when you already own something of theirs.
class _RelatedArtistCard extends StatefulWidget {
  final CatalogArtist artist;
  final bool inLibrary;
  final VoidCallback onTap;
  const _RelatedArtistCard({required this.artist, required this.inLibrary, required this.onTap});

  @override
  State<_RelatedArtistCard> createState() => _RelatedArtistCardState();
}

class _RelatedArtistCardState extends State<_RelatedArtistCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 118,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Pressable(
          onPressed: widget.onTap,
          borderRadius: BorderRadius.circular(14),
          scaleOnFocus: false,
          onFocusChange: (v) => setState(() => _hover = v),
          child: AnimatedScale(
            scale: _hover ? 1.06 : 1,
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOut,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    _netCover(widget.artist.picture, size: 118, circle: true),
                    if (widget.inLibrary)
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(color: _accent2, shape: BoxShape.circle),
                          child: const Icon(Icons.check_rounded, size: 12, color: Colors.black),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(widget.artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12.5, color: _hover ? Colors.white : null)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An artist in the grid. Grows on hover like the album cards, so both grids behave the same.
class _ArtistCard extends StatefulWidget {
  final String name;
  final Uint8List? image;

  /// True when [image] is a picture OF the artist, false when it is one of their record sleeves.
  final bool isPhoto;
  final VoidCallback onTap;
  const _ArtistCard(
      {required this.name,
      required this.image,
      required this.onTap,
      this.isPhoto = false});

  @override
  State<_ArtistCard> createState() => _ArtistCardState();
}

class _ArtistCardState extends State<_ArtistCard> {
  bool _hover = false;

  /// A round tile that does not eat the picture inside it.
  ///
  /// A photo of a person survives a circle — that is what circles are for, and the face is in the
  /// middle. A record sleeve does not: it is a square with the title printed to its edges, and a
  /// circle cuts all four corners off. Adele's own name, "take me home", "ONEREPUBLIC" — every one
  /// of them was sliced through in the grid, because most artists have no photo and it is a sleeve
  /// that gets drawn.
  ///
  /// So the sleeve is set INSIDE the circle whole, on a blurred blow-up of itself. The same trick
  /// the artist page uses behind its portrait, and for the same reason: colours the picture
  /// already has, rather than a crop that is luck.
  Widget _tile(double size) {
    final img = widget.image;
    if (img == null || widget.isPhoto) return cover(img, size: size, circle: true);
    // A square inside a circle of diameter d has sides d/√2, which leaves 0.146·d of margin.
    final inset = size * .145;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Image.memory(img,
                  fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
            ),
            // The blur alone is still the sleeve's own brightness; this is what the sleeve on top
            // has to stand out against.
            DecoratedBox(decoration: BoxDecoration(color: Colors.black.withValues(alpha: .28))),
            Padding(
              padding: EdgeInsets.all(inset),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.memory(img,
                    fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Pressable(
        onPressed: widget.onTap,
        borderRadius: BorderRadius.circular(14),
        scaleOnFocus: false,
        onFocusChange: (v) => setState(() => _hover = v),
        child: AnimatedScale(
          scale: _hover ? 1.06 : 1,
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (_, c) => AnimatedContainer(
                    duration: const Duration(milliseconds: 170),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: _hover
                          ? [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: .45),
                                  blurRadius: 22,
                                  offset: const Offset(0, 10))
                            ]
                          : const [],
                    ),
                    child: _tile(c.maxWidth),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: _hover ? Colors.white : null)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Artist credits ───────────────────────────────────────────────────────────
/// Open an artist's discography. Goes to the catalogue rather than your own shelf on purpose:
/// a guest like Beyoncé usually isn't in your library at all, and even for an artist you do own
/// the interesting thing here is their whole catalogue — that's what tapping a name promises.
Future<void> openArtist(BuildContext context, String name) async {
  final navigator = Navigator.of(context);
  final mb = context.read<MusicBrainzService>();

  CatalogArtist? artist;
  try {
    final hits = await CatalogService().searchArtists(name);
    // Prefer an exact name match over the first (fuzzy) hit.
    if (hits.isNotEmpty) {
      artist = hits.firstWhere((a) => artistKey(a.name) == artistKey(name), orElse: () => hits.first);
    }
  } catch (_) {/* fall through to MusicBrainz */}

  // Deezer catalogues what streams, so it has never heard of plenty of acts a real library holds.
  // MusicBrainz usually has them, and its discography is the fuller one anyway.
  if (artist == null) {
    try {
      final a = await mb.resolveArtist(name);
      if (a != null) {
        artist = CatalogArtist(0, a.name, null, 0,
            origin: CatalogRef.musicbrainz(a.mbid), detail: a.line);
      }
    } catch (_) {}
  }

  // Still nothing: open the page regardless. It can show no discography, but it CAN show the
  // records of theirs you already own — and refusing to open at all showed you neither.
  artist ??= CatalogArtist(0, name, null, 0);
  navigator.push(MaterialPageRoute(builder: (_) => ArtistBrowsePage(artist!)));
}

/// Minimise, maximise/restore and close, drawn by the app.
///
/// The system title bar is switched off so the window is all app, which means these three have to
/// exist here — without them a maximised window could not be shrunk or closed at all.
class _WindowButtons extends StatefulWidget {
  const _WindowButtons();
  @override
  State<_WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<_WindowButtons> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  // The window can also be maximised by dragging it to the top edge or by a keyboard shortcut, so
  // the icon follows the window rather than only the button that was pressed.
  @override
  void onWindowMaximize() => mounted ? setState(() => _maximized = true) : null;
  @override
  void onWindowUnmaximize() => mounted ? setState(() => _maximized = false) : null;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(Icons.remove_rounded, 'Minimaliseren', () => windowManager.minimize()),
          _btn(
            _maximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
            _maximized ? 'Verkleinen' : 'Maximaliseren',
            () async => _maximized ? windowManager.unmaximize() : windowManager.maximize(),
            size: _maximized ? 13 : 15,
          ),
          _btn(Icons.close_rounded, 'Sluiten', () => windowManager.close(), danger: true),
        ],
      );

  Widget _btn(IconData icon, String tip, VoidCallback onTap, {double size = 17, bool danger = false}) =>
      Tooltip(
        message: tip,
        waitDuration: const Duration(milliseconds: 600),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          // Red on hover for close, the one that loses work if hit by accident.
          hoverColor: danger ? const Color(0xFFE81123) : Colors.white.withValues(alpha: .10),
          child: SizedBox(
            width: 38,
            height: 30,
            child: Icon(icon, size: size, color: _muted),
          ),
        ),
      );
}

/// "Lady Gaga · Beyoncé" — every name tappable.
///
/// The guest credit lives wherever the ripper put it: the artist tag, the title, or — for the
/// Lady Gaga file on this machine — nowhere at all. So when the tags name nobody and [lookup] is
/// on, the catalogue is asked who else played on it.
class ArtistLine extends StatefulWidget {
  final String artist;
  final String title;
  final TextStyle style;
  final bool lookup;
  const ArtistLine({
    super.key,
    required this.artist,
    required this.title,
    required this.style,
    this.lookup = false,
  });

  @override
  State<ArtistLine> createState() => _ArtistLineState();
}

class _ArtistLineState extends State<ArtistLine> {
  List<String> _extra = const [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(ArtistLine old) {
    super.didUpdateWidget(old);
    if (old.artist != widget.artist || old.title != widget.title) {
      setState(() => _extra = const []);
      _fetch();
    }
  }

  Future<void> _fetch() async {
    if (!widget.lookup) return;
    final local = splitFeatured(widget.artist, widget.title);
    if (local.featured.isNotEmpty) return; // the tags already say who's on it
    final artist = widget.artist, title = widget.title;
    final names = await CatalogService().trackContributors(artist, titleWithoutFeat(title));
    if (!mounted || artist != widget.artist || title != widget.title) return;
    final guests = names.where((n) => artistKey(n) != artistKey(local.main)).toList();
    if (guests.isNotEmpty) setState(() => _extra = guests);
  }

  @override
  Widget build(BuildContext context) {
    final split = splitFeatured(widget.artist, widget.title);
    final lib = context.watch<LibraryStore>();
    return ArtistNames(
      names: [lib.displayArtist(split.main), ...split.featured, ..._extra],
      style: widget.style,
    );
  }
}

/// The artist line of a track row, tappable.
///
/// Every track list in the app used to print the artist as plain text, so the one place a record's
/// artist was reachable from was an album page. Wherever a name is shown it is now the way to that
/// artist — and a "A feat. B" tag becomes two names, because a guest is an artist too.
/// Clickable everywhere, but out of the remote's path on a television.
///
/// For controls that sit INSIDE something you already press. A mouse can reach a small link within
/// a big target; a remote has to stop on both, and the small one is almost never what you meant.
Widget _maybeFocusable(Widget child) => isTv ? ExcludeFocus(child: child) : child;

Widget _artistLine(({String main, List<String> featured}) who, TextStyle style) {
  final names = [if (who.main.trim().isNotEmpty) who.main.trim(), ...who.featured];
  if (names.isEmpty) return const SizedBox.shrink();
  final line = ArtistNames(names: names, style: style);
  // Every name here is its own focus stop, and this line sits inside a row of a track list. On a
  // television that turns one press-down-to-the-next-track into three or four, all the way through
  // a list that can be ten thousand rows long. The names stay clickable — ExcludeFocus takes them
  // out of the highlight's path, not out of the app.
  return isTv ? ExcludeFocus(child: line) : line;
}

/// A row of artist names, each tappable. Takes the names as-is — the caller decides who's on it.
class ArtistNames extends StatefulWidget {
  final List<String> names;
  final TextStyle style;
  const ArtistNames({super.key, required this.names, required this.style});

  @override
  State<ArtistNames> createState() => _ArtistNamesState();
}

class _ArtistNamesState extends State<ArtistNames> {
  String? _hover;

  @override
  Widget build(BuildContext context) {
    final names = widget.names;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < names.length; i++) ...[
          if (i > 0)
            Text(' · ', style: widget.style.copyWith(color: widget.style.color?.withValues(alpha: .5))),
          Flexible(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hover = names[i]),
              onExit: (_) => setState(() => _hover = _hover == names[i] ? null : _hover),
              child: Pressable(
                onPressed: () => openArtist(context, names[i]),
                borderRadius: BorderRadius.circular(6),
                scaleOnFocus: false,
                // The name is underlined on hover; focus does the same, so a remote sees the link
                // as a link rather than as a ring around a piece of prose.
                onFocusChange: (v) => setState(() => _hover = v ? names[i] : null),
                child: Text(
                  names[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _hover == names[i]
                      ? widget.style.copyWith(color: Colors.white, decoration: TextDecoration.underline)
                      : widget.style,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Move the playhead by [seconds], clamped to the track.
///
/// Clamped rather than left to the player: seeking past the end restarts the queue on some
/// backends and stalls on others, and neither is what "ten seconds forward" means.
void _nudge(PlayerStore p, int seconds) {
  final total = p.duration;
  if (total.inMilliseconds <= 0) return;
  var target = p.position + Duration(seconds: seconds);
  if (target < Duration.zero) target = Duration.zero;
  if (target > total) target = total;
  p.seek(target);
}

/// The transport, wherever the music actually is.
///
/// Casting moves the remote. Every one of these controls used to speak to the local libmpv, which
/// is deliberately silent while a speaker has the queue — so on a phone steering the KEF, pause,
/// next, previous and the scrubber all appeared to do nothing while the music played on.
///
/// One place, read by the desktop bar, the phone bar and the full player alike: three copies of
/// "which player am I talking to" is three chances for one of them to be wrong.
class _Transport {
  _Transport(BuildContext context)
      : player = context.watch<PlayerStore>(),
        speaker = context.watch<SpeakerTarget>();

  final PlayerStore player;
  final SpeakerTarget speaker;

  bool get casting => speaker.isCasting;
  Track? get track => player.current;

  /// Position and length come from the SPEAKER while casting — it is the only one that knows.
  Duration get position => casting ? (speaker.position ?? Duration.zero) : player.position;
  Duration get duration => casting ? (speaker.duration ?? Duration.zero) : player.duration;
  bool get playing => casting ? speaker.isPlaying : player.playing;

  double get progress => duration.inMilliseconds == 0
      ? 0.0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

  bool get canSeek => duration.inMilliseconds > 0 && (casting || track != null);

  VoidCallback? get playPause => casting
      ? () => unawaited(speaker.playPause())
      : (track == null ? null : player.playPause);

  VoidCallback? get next => casting
      ? ((speaker.status?.hasNext ?? false) ? () => unawaited(speaker.next()) : null)
      : (player.hasNext ? player.next : null);

  /// Below three seconds, "previous" means the previous track; after that it means this one again.
  /// That is a local nicety and stays local: the speaker is told plainly which track to play.
  VoidCallback? get previous => casting
      ? ((speaker.status?.hasPrev ?? false) ? () => unawaited(speaker.previous()) : null)
      : (player.hasPrev || player.position > const Duration(seconds: 3) ? player.prev : null);

  /// While the finger moves. Carried locally when casting and sent once on release — a seek per
  /// pixel would flood an embedded UPnP stack and land behind where you let go.
  void scrub(double fraction) =>
      casting ? speaker.scrubTo(duration * fraction) : player.seek(duration * fraction);

  void seekEnd(double fraction) {
    if (casting) unawaited(speaker.seekTo(duration * fraction));
  }

  /// Ten seconds either way, for a remote — and for a speaker, the only seek that needs no slider.
  void nudge(int seconds) {
    if (!casting) return _nudge(player, seconds);
    final total = duration;
    if (total.inMilliseconds <= 0) return;
    var target = position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > total) target = total;
    unawaited(speaker.seekTo(target));
  }
}

// ── Now-playing bar ──────────────────────────────────────────────────────────
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key, this.bottomSafeArea = true});

  /// Whether this bar is the last thing above the bottom of the screen.
  ///
  /// False when the phone's section bar sits underneath it. Both reserve the gesture inset
  /// otherwise, and the two reservations stack into 34 points of empty surface between two bars
  /// that are meant to read as one block.
  final bool bottomSafeArea;

  @override
  Widget build(BuildContext context) {
    final x = _Transport(context);
    final p = x.player;
    final t = x.track;
    // Under the home indicator on an iPad: the bar's colour runs to the bottom edge, its contents
    // stop above the bar the system draws over everything.
    final bottomInset =
        (_isTouch && bottomSafeArea) ? MediaQuery.viewPaddingOf(context).bottom : 0.0;
    // 280 a side in a desktop window, which is what centres the transport controls. Two of those
    // plus the controls do not fit on an iPad in portrait — 596 of 834 points gone before the
    // buttons start — so they give way instead of overflowing.
    final width = MediaQuery.sizeOf(context).width;

    // A phone gets a different bar entirely, not a squeezed one.
    //
    // The desktop bar reserves a side block for the track and centres the transport in what is
    // left. At 411 points that block bottoms out at its 96-point floor, of which the cover takes 54
    // and the gap 12 — leaving thirty points for the title, which printed "Niets aan het spelen"
    // one letter per line and overflowed the bar by 45 pixels.
    if (isCompact(context)) return _compactBar(context, x, bottomInset);

    final side = math.min(280.0, math.max(96.0, (width - 336) / 2));
    return Container(
      height: 84 + bottomInset,
      decoration: const BoxDecoration(
        color: Color(0xFF12141D),
        border: Border(top: BorderSide(color: _line)),
      ),
      padding: EdgeInsets.fromLTRB(18, 0, 18, bottomInset),
      child: Row(
        children: [
          SizedBox(
            width: side,
            child: Row(
              children: [
                Pressable(
                  // Null while nothing plays, which also stops the highlight from resting on a
                  // cover that opens nothing.
                  onPressed: t == null
                      ? null
                      : () => Navigator.of(context)
                          .push(nowPlayingRoute()),
                  borderRadius: BorderRadius.circular(8),
                  child: MouseRegion(
                    cursor: t == null ? MouseCursor.defer : SystemMouseCursors.click,
                    child: cover(p.currentCover, size: 54, radius: 8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(t?.title ?? '—',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          // What quality am I actually hearing? (local files only — a streamed
                          // source's real quality isn't known here.)
                          if (t != null && t.sizeBytes > 0) _qualityBadge(_trackQuality(t)),
                        ],
                      ),
                      if (p.radioMode && p.radioStatus.isNotEmpty)
                        Text(p.radioStatus,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _accent2, fontSize: 12.5))
                      else if (t == null)
                        const Text('Niets aan het spelen',
                            style: TextStyle(color: _muted, fontSize: 12.5))
                      else
                        // Everyone on the track, each name tappable — a guest artist is exactly
                        // who you want to look up while their verse is playing.
                        ArtistLine(
                          artist: t.artist,
                          title: t.title,
                          lookup: true,
                          style: const TextStyle(color: _muted, fontSize: 12.5),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Shuffle and repeat are the two you reach for least, and on a phone the row
                    // has to hold a rewind and a forward besides. They are on the full player,
                    // which is one tap away.
                    if (!isCompact(context))
                    IconButton(
                      icon: const Icon(Icons.shuffle_rounded, size: 20),
                      color: p.shuffle ? _accent : _muted,
                      onPressed: p.toggleShuffle,
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded),
                      color: _muted,
                      onPressed: x.previous,
                    ),
                    // Seeking, for a remote.
                    //
                    // The progress bar below is a Slider, and a Slider binds all FOUR arrows to
                    // changing its value — so the highlight goes in and cannot come out. It is
                    // therefore skipped on a television, which left no way to seek at all. Two
                    // buttons are the honest answer: they are reachable, they say what they do,
                    // and they cost a mouse nothing because they are not built for it.
                    // No TvLabelled here: the bar is 84 points tall and a caption under the icon
                    // overflowed it by three pixels. These two glyphs carry a "10" on their face,
                    // which is the label.
                    if (isTv)
                      IconButton(
                        icon: const Icon(Icons.replay_10_rounded, size: 22),
                        color: _muted,
                        tooltip: '10 seconden terug',
                        onPressed: x.canSeek ? () => x.nudge(-10) : null,
                      ),
                    const SizedBox(width: 2),
                    Container(
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: IconButton(
                        icon: Icon(x.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        color: _bg,
                        iconSize: 26,
                        onPressed: x.playPause,
                      ),
                    ),
                    const SizedBox(width: 2),
                    if (isTv)
                      IconButton(
                        icon: const Icon(Icons.forward_10_rounded, size: 22),
                        color: _muted,
                        tooltip: '10 seconden vooruit',
                        onPressed: x.canSeek ? () => x.nudge(10) : null,
                      ),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded),
                      color: _muted,
                      onPressed: x.next,
                    ),
                    if (!isCompact(context))
                    IconButton(
                      icon: Icon(p.repeat == RepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                          size: 20),
                      color: p.repeat == RepeatMode.off ? _muted : _accent,
                      // Local only: the speaker is handed one track at a time, so a change here
                      // would take effect on whatever is sent next and look like it did nothing.
                      onPressed: x.casting ? null : p.cycleRepeat,
                    ),
                    const _SpeakerButton(),
                  ],
                ),
                Row(
                  children: [
                    Text(_fmt(x.position), style: const TextStyle(color: _muted, fontSize: 11.5)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          activeTrackColor: _accent,
                          inactiveTrackColor: const Color(0xFF2A2F42),
                          thumbColor: Colors.white,
                        ),
                        child: _maybeFocusable(Slider(
                          value: x.progress,
                          onChanged: x.canSeek ? x.scrub : null,
                          onChangeEnd: x.casting && x.canSeek ? x.seekEnd : null,
                        )),
                      ),
                    ),
                    Text(_fmt(x.duration), style: const TextStyle(color: _muted, fontSize: 11.5)),
                  ],
                ),
              ],
            ),
          ),
          // The mirror of the leading block: it is what keeps the transport in the middle.
          SizedBox(width: side),
        ],
      ),
    );
  }

}

// ── Now playing (full screen, enlargeable art) ───────────────────────────────
/// Where the music comes out — and, while it is somewhere else, a way back.
///
/// One button in both players. It carries the state rather than hiding it: cast to a speaker and it
/// turns accent-coloured and names the speaker underneath, because "why is there no sound from this
/// device" is the question a silent cast button leaves you with.
class _SpeakerButton extends StatelessWidget {
  const _SpeakerButton({this.iconSize = 20});
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final client = lib.remote;
    // Only where a PC is doing the sending. On the machine that holds the music this is its own
    // output and there is nothing to choose.
    if (client == null) return const SizedBox.shrink();

    final target = context.watch<SpeakerTarget>();
    final player = context.read<PlayerStore>();
    final casting = target.isCasting;

    return TvLabelled(
      label: 'Speaker',
      child: IconButton(
        icon: Icon(casting ? Icons.speaker_rounded : Icons.speaker_group_outlined, size: iconSize),
        color: casting ? _accent : _muted,
        tooltip: casting ? 'Speelt op ${target.device!.name}' : 'Afspelen op…',
        onPressed: () => showSpeakerPicker(
          context,
          client: client,
          target: target,
          thisDeviceName: _thisDeviceName(),
          onPickedHere: () {
            // Silence the speaker before taking the music back, or it keeps playing the queue it
            // was given and you have the same record in two rooms.
            final was = target.device;
            if (was != null) unawaited(client.castControl(was.id, 'stop'));
          },
          onPickedRemote: (device) async {
            final ids = [
              for (final t in player.queueTracks)
                if (lib.remoteTrackId(t.path) case final id?) id,
            ];
            if (ids.isEmpty) {
              _srcToast(context, 'Zet eerst iets op, dan stuur ik het door.');
              return;
            }
            final index = player.queueTracks.indexWhere((t) => t.path == player.current?.path);
            // This device goes quiet: the point is that it plays THERE.
            if (player.playing) player.playPause();
            final ok = await client.castPlay(device.id, ids, index < 0 ? 0 : index);
            if (!context.mounted) return;
            if (!ok) _srcToast(context, '${device.name} nam het niet aan.');
          },
        ),
      ),
    );
  }
}

/// The mini player a phone gets: the track, one button, and the whole thing opens the full player.
///
/// Not the desktop bar with smaller numbers. On a phone there is room for a cover, a title and one
/// control — shuffle, repeat, skip-back and the seek bar all live on the full player, which is now
/// one tap away because the entire bar is the tap target rather than the 54-point cover on the far
/// left.
Widget _compactBar(BuildContext context, _Transport x, double bottomInset) {
  final p = x.player;
  final t = x.track;
  final open = t == null
      ? null
      : () => Navigator.of(context)
          .push(nowPlayingRoute());

  return Container(
    height: 66 + bottomInset,
    decoration: const BoxDecoration(
      color: Color(0xFF12141D),
      border: Border(top: BorderSide(color: _line)),
    ),
    padding: EdgeInsets.only(bottom: bottomInset),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The progress line, full width and two points tall. A draggable slider needs a thumb and
        // room for a thumb; this only has to answer "how far in am I".
        SizedBox(
          height: 2,
          child: LinearProgressIndicator(
            value: x.progress,
            backgroundColor: const Color(0xFF2A2F42),
            valueColor: const AlwaysStoppedAnimation(_accent),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Pressable(
                  onPressed: open,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
                    child: Row(
                      children: [
                        cover(p.currentCover, size: 44, radius: 6),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t?.title ?? '—',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600, fontSize: 14)),
                              Text(
                                  t == null
                                      ? 'Niets aan het spelen'
                                      : (p.radioMode && p.radioStatus.isNotEmpty
                                          ? p.radioStatus
                                          : t.artist),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: _muted, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(x.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 30),
                color: Colors.white,
                onPressed: x.playPause,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded, size: 26),
                color: _muted,
                onPressed: x.next,
              ),
              const _SpeakerButton(iconSize: 22),
              const SizedBox(width: 2),
            ],
          ),
        ),
      ],
    ),
  );
}

/// How big the sleeve on the now-playing screen may be.
///
/// AlbumArt reserves size * 1.62 so the disc has somewhere to slide out to. At the old fixed 360
/// that is 583 points — on a 412-point phone the disc came out into a part of the screen that is
/// not there, which is why it looked like the animation had been lost.
///
/// Also capped by height: in landscape, or on a phone with the keyboard up, a sleeve sized from
/// the width alone pushes the title and the transport controls off the bottom.
double _sleeve(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final narrow = isCompact(context);
  // The sleeve plus the room the disc needs to slide into — less of that room in portrait, so the
  // sleeve is not paying for a stride nobody has space for.
  final byWidth = (size.width - 40) / (1 + discTravelFactor(context));
  // And a firm ceiling on height in portrait. Below the sleeve sit the title, the seek bar and the
  // five transport buttons, and those are the reason the screen exists: a sleeve sized from width
  // alone pushes them under the fold on a tall, narrow screen. Sideways the height is the binding
  // constraint anyway, so the looser factor there costs nothing.
  final byHeight = size.height * (narrow ? 0.34 : 0.46);
  final smaller = byWidth < byHeight ? byWidth : byHeight;
  return smaller.clamp(140.0, 360.0);
}

/// The now-playing screen, and the way it arrives and leaves: up from the bar, down off the
/// bottom.
///
/// A MaterialPageRoute takes the platform's own transition, which on Android is a sideways slide.
/// So pulling the screen down with a finger ended with it leaving to the RIGHT — the gesture and
/// the animation disagreed about which way "away" was, and the seam between them was the most
/// visible thing on the screen. Enter and exit along the same path, and the drag simply continues
/// into the exit.
Route<void> nowPlayingRoute() => PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 280),
      // Out faster than in. Arriving is worth watching; leaving is not.
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => const NowPlayingScreen(),
      transitionsBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            // Out fast too, and NOT the mirrored ease-in that symmetry argues for. This exit is
            // usually the end of a drag: the finger was already carrying the screen down, and a
            // curve that starts slow stops it dead at the exact moment the hand says keep going.
            // The seam between the gesture and the animation is the thing worth protecting.
            reverseCurve: Curves.easeOutCubic,
          ),
        ),
        child: child,
      ),
    );

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with SingleTickerProviderStateMixin {
  /// The sleeve the AlbumArt below settled on, so enlarging it shows THAT image.
  ///
  /// The zoom used to open the player's own cover, which is captured when a track starts and knows
  /// nothing about the pressing this screen resolved — so clicking the art you were looking at
  /// produced a different, older one.
  Uint8List? _shown;

  /// How far the screen has been pulled down, in points.
  ///
  /// Unbounded because it is not a 0..1 progress: while a finger is down this IS the offset, set
  /// straight from the drag, and when the finger lifts a spring carries the same number back to
  /// zero. One value for both halves is what makes the hand-off seamless — the spring starts from
  /// where the finger actually left it, at the speed it left at, rather than from a fresh zero.
  late final AnimationController _pull = AnimationController.unbounded(vsync: this);

  /// Critically damped: a screen coming back to rest should not bounce. Overshoot belongs to
  /// something you threw, and a pull that did not travel far enough to dismiss was not a throw.
  static final _settle = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 500,
    ratio: 1,
  );

  @override
  void dispose() {
    _pull.dispose();
    super.dispose();
  }

  /// Where a flick is heading, not where the finger stopped.
  ///
  /// The exponential decay a scroll view uses, so a small fast flick dismisses and a long slow
  /// drag that stalls halfway does not.
  static double _project(double velocity) => (velocity / 1000) * 0.998 / (1 - 0.998);

  void _onPull(DragUpdateDetails d) {
    // 1:1 with the finger, and never above the top — there is nothing up there to reveal.
    final next = _pull.value + d.delta.dy;
    _pull.value = next < 0 ? 0 : next;
  }

  void _onPullEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final height = MediaQuery.sizeOf(context).height;
    // Velocity decides, not the position it happens to have reached: a short sharp flick means
    // "away" just as clearly as a slow drag past the halfway mark.
    if (v > 700 || _pull.value + _project(v) > height * .28) {
      Navigator.pop(context);
      return;
    }
    // Reduced motion is not no feedback — the screen still goes back where it belongs, it simply
    // does not travel there. Someone who gets motion sick from a full-screen surface sliding
    // around is exactly who this spring would catch.
    if (MediaQuery.disableAnimationsOf(context)) {
      _pull.value = 0;
      return;
    }
    _pull.animateWith(SpringSimulation(_settle, _pull.value, 0, v));
  }

  /// The player, pullable downwards to close it.
  ///
  /// Only where there is a finger. A window has the chevron, and a mouse dragging a screen off
  /// the bottom is not a gesture anyone reaches for.
  ///
  /// The gesture sits around everything rather than only the sleeve: the two sliders below it are
  /// horizontal, so they never contend for a vertical drag, and a bigger target is the difference
  /// between a gesture you can use without looking and one you have to aim at.
  Widget _dismissable(Widget child) {
    if (!_isTouch) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: _onPull,
      onVerticalDragEnd: _onPullEnd,
      child: AnimatedBuilder(
        animation: _pull,
        builder: (_, inner) => Transform.translate(offset: Offset(0, _pull.value), child: inner),
        // Built once and carried through every frame of the drag: the sleeve, the disc and the
        // blurred backdrop are expensive, and none of them changes because the screen moved.
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final x = _Transport(context);
    final p = x.player;
    final t = x.track;
    final cast = x.speaker;
    final casting = x.casting;
    final position = x.position;
    final duration = x.duration;
    final playing = x.playing;
    final prog = x.progress;
    return Scaffold(
      backgroundColor: _bg,
      body: _dismissable(Stack(
        children: [
          if (p.currentCover != null)
            Positioned.fill(
              child: Opacity(opacity: .22, child: Image.memory(p.currentCover!, fit: BoxFit.cover)),
            ),
          Positioned.fill(child: Container(color: _bg.withValues(alpha: .5))),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                      tooltip: 'Terug',
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    // Only where there is a queue to look at. On the radio the list is built as it
                    // goes, and a button onto a list that is one item long says nothing.
                    if (!p.radioMode && p.queueTracks.length > 1)
                      IconButton(
                        icon: const Icon(Icons.queue_music_rounded, size: 26),
                        tooltip: 'Wachtrij',
                        onPressed: () => _openQueue(context),
                      ),
                    if (t != null)
                      IconButton(
                        icon: const Icon(Icons.more_vert_rounded, size: 24),
                        tooltip: 'Meer',
                        onPressed: () => _openTrackMenu(context, t),
                      ),
                    const SizedBox(width: 4),
                  ],
                ),
                const Spacer(),
                Pressable(
                  // What the sleeve is actually drawing wins; the player's snapshot is only the
                  // fallback for a track whose art has not resolved yet.
                  onPressed: (_shown ?? p.currentCover) == null
                      ? null
                      : () => showDialog(
                          context: context, builder: (_) => _ZoomView((_shown ?? p.currentCover)!)),
                  borderRadius: BorderRadius.circular(10),
                  child: MouseRegion(
                    cursor: (_shown ?? p.currentCover) == null
                        ? MouseCursor.defer
                        : SystemMouseCursors.zoomIn,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: .5), blurRadius: 44, offset: const Offset(0, 22))
                        ],
                      ),
                      // Same sleeve-and-disc as the album page, at the size this screen deserves.
                      // The album is taken from the track that is playing, so the disc that comes
                      // out is the one this song is actually on.
                      child: t == null
                          ? cover(p.currentCover, size: _sleeve(context), radius: 16)
                          : Builder(builder: (context) {
                              // Ask the library which album this track is on, rather than resolving
                              // the record again from its artist and title. Without it this screen
                              // did its own Discogs lookup and showed a different artist's album
                              // that shared a title, while the album page had the right one pinned.
                              final lib = context.watch<LibraryStore>();
                              final al = lib.albumForPath(t.path);
                              return AlbumArt(
                                artist: al?.artist ?? t.artist,
                                album: al?.title ?? t.album,
                                identity: al == null ? '' : lib.uidOf(al),
                                size: _sleeve(context),
                                fallback: p.currentCover,
                                chosen: al?.correctedCover,
                                trackCount: al?.tracks.length ?? 0,
                                pinned: al == null ? null : lib.pinnedRelease(al),
                                pinnedMbid: al == null ? null : lib.pinnedMbid(al),
                                roles: al == null
                                    ? const {}
                                    : lib.albumArtRoles(al.artist, al.title),
                                // Out and spinning while a speaker has it too. This device is
                                // deliberately silent then, so p.playing is false — but the record
                                // IS playing, just somewhere else, and that is what you came to
                                // this screen to look at.
                                playing: p.playing || context.watch<SpeakerTarget>().isCasting,
                                onFront: (f) {
                                  if (mounted && !identical(f, _shown)) {
                                    setState(() => _shown = f);
                                  }
                                },
                              );
                            }),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                Text(t?.title ?? '—',
                    style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (t != null)
                      ArtistLine(
                        artist: t.artist,
                        title: t.title,
                        lookup: true,
                        style: const TextStyle(color: _muted, fontSize: 15),
                      ),
                    if (t != null && t.sizeBytes > 0) _qualityBadge(_trackQuality(t)),
                  ],
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: dialogWidth(context, 540),
                  child: Row(
                    children: [
                      Text(_fmt(position), style: const TextStyle(color: _muted, fontSize: 12)),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                            activeTrackColor: _accent,
                            inactiveTrackColor: const Color(0xFF2A2F42),
                            thumbColor: Colors.white,
                          ),
                          // Same as the player bar's: a Slider eats left and right to change its
                          // value, so the highlight would enter the seek bar and never leave it.
                          child: _maybeFocusable(Slider(
                            value: prog,
                            // Dragging is carried locally and sent once on release: a seek per pixel
                            // would flood an embedded stack and land behind where you let go.
                            onChanged: duration.inMilliseconds == 0 || (!casting && t == null)
                                ? null
                                : casting
                                    ? (v) => cast.scrubTo(duration * v)
                                    : (v) => p.seek(duration * v),
                            onChangeEnd:
                                casting && duration.inMilliseconds > 0 ? (v) => cast.seekTo(duration * v) : null,
                          )),
                        ),
                      ),
                      Text(_fmt(duration), style: const TextStyle(color: _muted, fontSize: 12)),
                    ],
                  ),
                ),
                // Where it is actually coming out, when that is not here. No fake progress bar
                // above it: the position lives on the speaker and this device does not know it, so
                // a bar that crawled along on a guess would be a lie you could watch.
                Builder(builder: (context) {
                  final target = context.watch<SpeakerTarget>();
                  if (!target.isCasting) return const SizedBox(height: 8);
                  return Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.speaker_rounded, size: 16, color: _accent),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text('Speelt op ${target.device!.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _accent, fontSize: 13.5)),
                      ),
                    ]),
                  );
                }),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                        icon: const Icon(Icons.shuffle_rounded),
                        iconSize: 24,
                        color: p.shuffle ? _accent : _muted,
                        onPressed: p.toggleShuffle),
                    const SizedBox(width: 12),
                    IconButton(
                        icon: const Icon(Icons.skip_previous_rounded),
                        iconSize: 34,
                        color: _text,
                        onPressed: casting
                            ? (cast.status?.hasPrev ?? false ? cast.previous : null)
                            : (p.hasPrev || p.position > const Duration(seconds: 3) ? p.prev : null)),
                    const SizedBox(width: 8),
                    Container(
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: IconButton(
                        icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        color: _bg,
                        iconSize: 40,
                        onPressed: casting ? cast.playPause : (t == null ? null : p.playPause),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                        icon: const Icon(Icons.skip_next_rounded),
                        iconSize: 34,
                        color: _text,
                        onPressed: casting
                            ? (cast.status?.hasNext ?? false ? cast.next : null)
                            : (p.hasNext ? p.next : null)),
                    const SizedBox(width: 12),
                    // Shuffle and repeat stay local on purpose: the speaker plays the queue the PC
                    // hands it one track at a time, so changing the order here would take effect on
                    // whatever is sent NEXT and look like it did nothing now.
                    IconButton(
                        icon: Icon(p.repeat == RepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded),
                        iconSize: 24,
                        color: p.repeat == RepeatMode.off ? _muted : _accent,
                        onPressed: casting ? null : p.cycleRepeat),
                    const SizedBox(width: 12),
                    const _SpeakerButton(iconSize: 24),
                  ],
                ),
                // The speaker's own volume, and only when it says it has one. A Sonos and the KEF
                // both do; a renderer without RenderingControl simply shows nothing here rather
                // than a slider that moves and changes nothing.
                if (casting && cast.hasVolume)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: SizedBox(
                      width: dialogWidth(context, 320),
                      child: Row(
                        children: [
                          const Icon(Icons.volume_down_rounded, size: 19, color: _muted),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                activeTrackColor: _accent,
                                inactiveTrackColor: const Color(0xFF2A2F42),
                                thumbColor: Colors.white,
                              ),
                              child: _maybeFocusable(Slider(
                                value: cast.volume.clamp(0, 100).toDouble(),
                                max: 100,
                                onChanged: (v) => cast.setVolume(v.round()),
                              )),
                            ),
                          ),
                          const Icon(Icons.volume_up_rounded, size: 19, color: _muted),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 30,
                            child: Text('${cast.volume}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(color: _muted, fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                  ),
                const Spacer(),
              ],
            ),
          ),
        ],
      )),
    );
  }
}

/// The record this song is on, and the person who made it.
///
/// Every music player has this menu, and it is the one thing the now-playing screen was missing:
/// you are looking at a sleeve and an artist's name with no way to open either of them. The album
/// comes from the library by path rather than from the track's own tags — the same lookup the
/// sleeve above it already uses, so the two can never disagree about which record this is.
void _openTrackMenu(BuildContext context, Track t) {
  final lib = context.read<LibraryStore>();
  final album = lib.albumForPath(t.path);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: _panel,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheet) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
            child: Row(
              children: [
                cover(album?.cover, size: 44, radius: 6),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(t.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: _line, height: 1),
          // Only when there is a record here to open. A radio track that is not in the library
          // has no album page, and an entry that goes nowhere is worse than no entry.
          if (album != null)
            ListTile(
              leading: const Icon(Icons.album_rounded, size: 21),
              title: const Text('Naar het album'),
              subtitle: Text(album.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 12)),
              onTap: () {
                Navigator.pop(sheet);
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => AlbumDetailPage(album: album)));
              },
            ),
          if (t.artist.trim().isNotEmpty && !_genericArtist(t.artist))
            ListTile(
              leading: const Icon(Icons.person_rounded, size: 21),
              title: const Text('Naar de artiest'),
              subtitle: Text(t.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 12)),
              onTap: () {
                Navigator.pop(sheet);
                openArtist(context, t.artist);
              },
            ),
          ListTile(
            leading: const Icon(Icons.radio_rounded, size: 21),
            title: const Text('Radio hieruit'),
            subtitle: const Text('Meer in deze richting',
                style: TextStyle(color: _muted, fontSize: 12)),
            onTap: () {
              Navigator.pop(sheet);
              startRadio(context, t.artist);
            },
          ),
        ],
      ),
    ),
  );
}

/// What is coming, and a way to jump to any of it.
///
/// Opened from the now-playing screen rather than sitting on it: the queue is what you consult,
/// the record is what you look at, and a list of four hundred songs under the sleeve would make
/// the second one the smaller half of the screen.
void _openQueue(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: _panel,
    showDragHandle: true,
    // The sheet sets its own height below; without this it is capped at half the screen.
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => const _QueueSheet(),
  );
}

class _QueueSheet extends StatefulWidget {
  const _QueueSheet();

  @override
  State<_QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<_QueueSheet> {
  /// Every row the same height, which is what lets the list open on the right one without
  /// measuring anything: the offset is simply the index times this.
  static const _rowHeight = 58.0;

  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    // Open where you are, not at the top. A queue of four hundred songs otherwise opens three
    // hundred rows away from the only one you came to see. Half a row up so it is clear the list
    // continues above.
    final at = context.read<PlayerStore>().queueIndex;
    _scroll = ScrollController(
        initialScrollOffset: at <= 0 ? 0 : (at * _rowHeight) - (_rowHeight / 2));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerStore>();
    final queue = p.queueTracks;
    final at = p.queueIndex;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
            child: Row(
              children: [
                const Text('Wachtrij',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text('${queue.length} nummers',
                    style: const TextStyle(color: _muted, fontSize: 12.5)),
              ],
            ),
          ),
          const Divider(color: _line, height: 1),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              itemExtent: _rowHeight,
              itemCount: queue.length,
              padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom),
              itemBuilder: (_, i) => _queueRow(context, queue[i], i, i == at),
            ),
          ),
        ],
      ),
    );
  }

  Widget _queueRow(BuildContext context, Track t, int i, bool playing) => InkWell(
        // Straight to PlayerStore.jumpTo, which moves the cursor and nothing else. Handing the
        // queue back through playQueue would reshuffle it and play the wrong song.
        onTap: playing ? null : () => context.read<PlayerStore>().jumpTo(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                child: playing
                    ? const Icon(Icons.equalizer_rounded, size: 17, color: _accent2)
                    : Text('${i + 1}',
                        style: const TextStyle(color: _muted, fontSize: 12.5)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: playing ? FontWeight.w700 : FontWeight.w600,
                          color: playing ? _accent2 : _text,
                        )),
                    Text(t.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(_fmt(t.duration),
                  style: const TextStyle(color: _muted, fontSize: 12.5)),
            ],
          ),
        ),
      );
}


class _ZoomView extends StatelessWidget {
  final Uint8List bytes;
  const _ZoomView(this.bytes);
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Center(child: Image.memory(bytes)),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Online search (TorBox) ───────────────────────────────────────────────────
String _fmtBytes(int b) => b >= 1000000000
    ? '${(b / 1e9).toStringAsFixed(2)} GB'
    : b >= 1000000
        ? '${(b / 1e6).round()} MB'
        : '${(b / 1e3).round()} KB';

// Shared source-result rendering + actions (used by direct search AND browse sources).
void _srcToast(BuildContext context, String m) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));
}

/// A toast that offers a way out, for where the app REFUSES what was asked.
///
/// Every refusal here rests on a guess about what you already own, and that guess can be wrong —
/// two different takes can run equally long. A refusal you cannot overrule turns into a button that
/// silently does nothing, which is worse than the duplicate it was avoiding. Longer on screen than
/// a plain toast, because it asks something of the reader.
/// A message with a way to overrule it.
///
/// On a television this cannot be a toast. A SnackBarAction is technically focusable but the
/// highlight never travels there, and it is gone after eight seconds — so the button sits on
/// screen, plainly visible, and cannot be reached. That matters here more than it sounds: this is
/// the ONLY way to overrule the app when it wrongly decides a download is a duplicate you already
/// own. On a remote that whole branch of the app was dead.
void _srcToastAction(BuildContext context, String m, String label, VoidCallback onTap) {
  if (isTv) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _panel,
        content: Text(m, style: const TextStyle(height: 1.4)),
        actions: [
          // The highlight starts on "leave it" — the action behind this dialog is a download the
          // app has already advised against.
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Laat maar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onTap();
            },
            child: Text(label),
          ),
        ],
      ),
    );
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(m),
    duration: const Duration(seconds: 8),
    action: SnackBarAction(label: label, onPressed: onTap),
  ));
}

// ── Radio / Smart Shuffle ────────────────────────────────────────────────────
String _radioNorm(String s) {
  var x = s.toLowerCase();
  // Drop version/edition suffixes — "(2012 Remaster)", "[Live]", "- Single Version" —
  // so a clean library file matches a Deezer title that carries them (and vice-versa).
  x = x.replaceAll(RegExp(r'[\(\[].*?[\)\]]'), ' ');
  final f = x.indexOf(' feat');
  if (f > 0) x = x.substring(0, f);
  return x.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// Build a Radio queue around [artist]: Deezer recommendations, matched against the
/// local library (owned tracks play instantly; the rest resolve via TorBox on demand).
List<RadioItem> _radioItemsFor(List<RecTrack> recs, LibraryStore lib) {
  final index = <String, Track>{};
  for (final t in lib.tracks) {
    index.putIfAbsent('${_radioNorm(t.artist)}|${_radioNorm(t.title)}', () => t);
  }
  return recs
      .map((r) => RadioItem(
            artist: r.artist,
            title: r.title,
            local: index['${_radioNorm(r.artist)}|${_radioNorm(r.title)}'],
          ))
      .toList();
}

/// Library-forward ordering for Smart Shuffle: play mostly tracks the listener already
/// owns (instant, gap-free) with online discovery sprinkled in (~2 owned : 1 online).
/// Starts on an owned track so there's no first-track sourcing wait, and never leaves a
/// long silent stretch churning through uncached online tracks. If the seed yields no
/// owned tracks (e.g. a discovery seed), the mix is returned unchanged (all discovery).
List<RadioItem> _smartShuffle(List<RadioItem> items) {
  final owned = items.where((i) => i.isLocal).toList();
  final online = items.where((i) => !i.isLocal).toList();
  if (owned.isEmpty || online.isEmpty) return items;
  final out = <RadioItem>[];
  var oi = 0, ni = 0;
  while (oi < owned.length || ni < online.length) {
    if (oi < owned.length) out.add(owned[oi++]);
    if (oi < owned.length) out.add(owned[oi++]);
    if (ni < online.length) out.add(online[ni++]);
  }
  return out;
}

Future<void> startRadio(BuildContext context, String artist) async {
  final player = context.read<PlayerStore>();
  final lib = context.read<LibraryStore>();
  _srcToast(context, '📻 Radio starten voor $artist…');
  final rec = RecommendService();
  List<RecTrack> recs;
  try {
    recs = await rec.mixRadio(artist);
  } catch (_) {
    recs = const [];
  }
  if (!context.mounted) return;
  if (recs.isEmpty) {
    _srcToast(context, 'Geen radio gevonden voor $artist.');
    return;
  }
  // Library-forward smart shuffle: lead with owned tracks (instant), mix in discovery.
  var items = _smartShuffle(_radioItemsFor(recs, lib));

  // Away from the PC, discovery is not on the menu.
  //
  // Every track the radio suggests that you do not own has to be resolved to an online stream, and
  // a client cannot do that — playing an online source is the one thing that stays on the PC. The
  // queue then filled with items that were skipped one by one, silently, which from where you are
  // sitting is a Radio button that does nothing. So the queue is what this device can actually
  // play, and when that is nothing it says so rather than starting.
  if (lib.isRemote) {
    items = items.where((i) => i.isLocal).toList();
    if (items.isEmpty) {
      _srcToast(context,
          'Radio voor $artist vindt niets uit je eigen bibliotheek. Op de pc speelt hij ook wat je nog niet hebt.');
      return;
    }
  }
  // Keep it endless: fetch a fresh (also library-forward) batch when the queue runs low.
  player.radioExtend = () async {
    try {
      final more = _smartShuffle(_radioItemsFor(await rec.mixRadio(artist), lib));
      return lib.isRemote ? more.where((i) => i.isLocal).toList() : more;
    } catch (_) {
      return <RadioItem>[];
    }
  };
  await player.playRadio(items);
}

bool _genericArtist(String s) {
  final x = s.trim().toLowerCase();
  return x.isEmpty || x == 'various' || x == 'various artists' || x == 'va' || x == 'onbekende artiest';
}

// ── Tracks (flat, all library songs) ─────────────────────────────────────────
class TracksView extends StatelessWidget {
  /// Library search + quality filter from the shell (null = show everything).
  final bool Function(Track)? match;
  final String query;
  const TracksView({super.key, this.match, this.query = ''});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final player = context.watch<PlayerStore>();
    final all = lib.tracks;
    final tracks = match == null ? all : all.where(match!).toList();
    if (lib.scanning && all.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (all.isEmpty) {
      return const Center(child: Text('Geen tracks gevonden.', style: TextStyle(color: _muted)));
    }
    if (tracks.isEmpty) {
      return Center(
        child: Text(query.isEmpty ? 'Niets binnen dit filter.' : 'Niets gevonden voor “$query”.',
            style: const TextStyle(color: _muted)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Builder(builder: (context) {
          final narrow = isCompact(context);
          // “Tracks” is what the bar at the top of a phone already says. The number is not, and
          // it is the half of this line worth keeping — it is how you tell a filtered list from
          // the whole library at a glance.
          final title = narrow
              ? Text('${tracks.length} nummers',
                  style: const TextStyle(color: _muted, fontSize: 13.5))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Tracks',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 10),
                  Text('${tracks.length}', style: const TextStyle(color: _muted, fontSize: 14)),
                ]);
          final buttons = [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
              onPressed: () => player.shuffleAll(tracks),
              icon: const Icon(Icons.shuffle_rounded, size: 18),
              label: const Text('Shuffle alles'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: _panel2,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
              onPressed: () => player.playQueue(tracks, 0),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Speel alles'),
            ),
          ];
          return Padding(
            padding: EdgeInsets.fromLTRB(
                narrow ? pagePad(context) : 28, narrow ? 12 : 22, narrow ? pagePad(context) : 24, 10),
            // Title, count and two buttons. Three pixels too wide on a phone, and the count
            // vanished under the first button — so on a phone the buttons drop to their own line.
            // The Row stays everywhere else, Spacer and all, because that is where it fits.
            child: narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, const SizedBox(height: 8), Row(children: buttons)],
                  )
                : Row(children: [title, const Spacer(), ...buttons]),
          );
        }),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: tracks.length,
            itemExtent: 56, // fixed height → smooth scrolling at 10k+ tracks
            itemBuilder: (_, i) {
              final t = tracks[i];
              final isCurrent = !player.radioMode && player.current?.path == t.path;
              return InkWell(
                onTap: () => player.playQueue(tracks, i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  color: isCurrent ? _panel : Colors.transparent,
                  child: Row(
                    children: [
                      SizedBox(width: 22, child: Text('${i + 1}', style: const TextStyle(color: _muted, fontSize: 11))),
                      cover(lib.coverForTrack(t), size: 40, radius: 6),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isCurrent ? _accent : _text)),
                            // Through displayArtist: the track's own tag may spell the artist
                            // differently from the name shown everywhere else. Split so a guest
                            // is their own name here, not part of one long unclickable string.
                            _artistLine(splitFeatured(lib.displayArtist(t.artist), t.title),
                                const TextStyle(fontSize: 12, color: _muted)),
                          ],
                        ),
                      ),
                      _qualityBadge(_trackQuality(t)),
                      const SizedBox(width: 4),
                      Text(_fmt(t.duration), style: const TextStyle(color: _muted, fontSize: 12)),
                      const SizedBox(width: 10),
                      Icon(isCurrent && player.playing ? Icons.volume_up_rounded : Icons.play_arrow_rounded,
                          color: isCurrent ? _accent : _muted, size: 19),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Ontdek (discovery feed) ──────────────────────────────────────────────────
// ── Start / welcome screen (TIDAL-style rows) ────────────────────────────────
class HomeStartView extends StatefulWidget {
  const HomeStartView({super.key});
  @override
  State<HomeStartView> createState() => _HomeStartViewState();
}

class _HomeStartViewState extends State<HomeStartView> {
  /// The margin every row on this screen hangs off.
  ///
  /// One number, used by the headings AND by the rows of covers under them. They were 28 and 24,
  /// which is not a difference you can name but is one you can see: every cover on the screen sat
  /// four points to the left of the heading it belonged to.
  double get _pad => isCompact(context) ? 18.0 : 28.0;

  final _catalog = CatalogService();
  final _rec = RecommendService();
  List<CatalogAlbumHit> _charts = [];
  List<CatalogAlbumHit> _releases = [];
  List<RecTrack> _forYou = [];
  bool _chartsLoading = true;
  bool _seedsRequested = false; // the library's artists have been used to load the personal rows
  bool _seedsLoading = false;

  @override
  void initState() {
    super.initState();
    // Charts need no library — load them right away.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCharts());
  }

  Future<void> _loadCharts() async {
    try {
      final c = await _catalog.chartAlbums();
      if (mounted) setState(() => _charts = c);
    } catch (_) {}
    if (mounted) setState(() => _chartsLoading = false);
  }

  /// The personal rows depend on the scanned library. On a cold start the scan is still running
  /// when this view first builds, so we load these ONCE the library actually has artists (driven
  /// from build via context.watch) — not eagerly with an empty seed list.
  Future<void> _loadSeeds(List<String> seeds) async {
    if (mounted) setState(() => _seedsLoading = true);
    final relF = _catalog.latestFromArtists(seeds);
    final fyF = _rec.discover(seeds.take(6).toList());
    List<CatalogAlbumHit> rel = [];
    List<RecTrack> fy = [];
    try {
      rel = await relF;
    } catch (_) {}
    try {
      fy = await fyF;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _releases = rel;
      _forYou = fy;
      _seedsLoading = false;
    });
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return 'Goedenacht';
    if (h < 12) return 'Goedemorgen';
    if (h < 18) return 'Goedemiddag';
    return 'Goedenavond';
  }

  Future<void> _playRec(RecTrack t) async {
    final online = context.read<OnlineService>();
    final player = context.read<PlayerStore>();
    _srcToast(context, 'Bron voorbereiden voor ${t.title}…');
    try {
      final url = await online.resolveRadio(t.artist, t.title, instantOnly: false);
      if (!mounted) return;
      if (url == null) {
        _srcToast(context, 'Geen bron gevonden — zoek het op via Online zoeken.');
        return;
      }
      player.playUrl(url, title: t.title, artist: t.artist);
    } catch (_) {
      if (mounted) _srcToast(context, 'Kan niet afspelen.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final artists = lib.artists.where((a) => !_genericArtist(a)).toList();
    // Fire the personal rows the first time the library actually has artists.
    if (!_seedsRequested && artists.isNotEmpty) {
      _seedsRequested = true;
      final seeds = [...artists]..shuffle();
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSeeds(seeds));
    }
    final recent = [...lib.albums.where((a) => a.addedMs > 0)]..sort((a, b) => b.addedMs.compareTo(a.addedMs));
    final anyLoading = _chartsLoading || _seedsLoading || (!_seedsRequested && lib.scanning);
    // New releases by artists you own lead the hero; the global chart fills in until those are
    // loaded (or if you have no library yet), so the top of the page is never an empty band.
    final hero = _releases.isNotEmpty ? _releases : _charts;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(_pad, 22, _pad, 2),
          child: Text('${_greeting()} 👋', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(_pad, 0, _pad, 6),
          child: const Text('Ontdek nieuwe muziek en pak op waar je gebleven was',
              style: TextStyle(color: _muted, fontSize: 13.5)),
        ),
        if (hero.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(_pad, 14, _pad, 4),
            child: HeroCarousel(hits: hero.take(7).toList()),
          ),
        if (recent.isNotEmpty) _section('Recent toegevoegd', _localRow(recent.take(15).toList())),
        if (_forYou.isNotEmpty || _seedsLoading)
          _section('Aanbevolen voor jou',
              _forYou.isEmpty ? _loadingRow() : _recRow(_forYou.take(15).toList())),
        if (_charts.isNotEmpty || _chartsLoading)
          _section('Top van dit moment',
              _charts.isEmpty ? _loadingRow() : _catalogRow(_charts.take(20).toList())),
        if (_releases.isNotEmpty || _seedsLoading)
          _section('Nieuw van jouw artiesten',
              _releases.isEmpty ? _loadingRow() : _catalogRow(_releases.take(20).toList())),
        if (!anyLoading && _charts.isEmpty && _releases.isEmpty && _forYou.isEmpty && recent.isEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(_pad, 40, _pad, 0),
            child: const Text('Nog niks om te tonen — download wat muziek of ga naar Online zoeken.',
                style: TextStyle(color: _muted)),
          ),
      ],
    );
  }

  Widget _section(String title, Widget row) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(_pad, 22, _pad, 12),
            child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          // Taller than the tile itself: a horizontal ListView gives its children a TIGHT height
          // and clips them, so without slack the hover growth would be sliced off top and bottom.
          SizedBox(height: 204, child: row),
        ],
      );

  Widget _loadingRow() => const Center(child: CircularProgressIndicator(color: _accent, strokeWidth: 2.4));

  Widget _localRow(List<Album> albums) => ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: _pad),
        itemCount: albums.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => _card(
            cover(albums[i].cover, size: 140), albums[i].title, albums[i].artist,
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AlbumDetailPage(album: albums[i])))),
      );

  Widget _catalogRow(List<CatalogAlbumHit> hits) => ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: _pad),
        itemCount: hits.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => _card(
            _netCover(hits[i].album.cover, size: 140), hits[i].album.title, hits[i].artist,
            () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => AlbumBrowsePage(hits[i].artist, hits[i].album)))),
      );

  Widget _recRow(List<RecTrack> ts) => ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: _pad),
        itemCount: ts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        // To the album, the same as every other row here. A tile that started playing instead was
        // the odd one out, and it gave you no way to see what the record was.
        //
        // Long-press still plays it: the quickest way to hear a recommendation should not disappear
        // because the tap now goes somewhere better.
        itemBuilder: (_, i) => _HoverCard(
          art: _netCover(ts[i].cover, size: 140),
          title: ts[i].title,
          subtitle: ts[i].artist,
          onTap: () => _openRec(ts[i]),
          onLongPress: () => _playRec(ts[i]),
        ),
      );

  /// Where a recommended track lives. Deezer names the album it came from; when it does not, the
  /// track itself is still worth hearing, so that falls back to playing it.
  void _openRec(RecTrack t) {
    if (!t.hasAlbum) {
      unawaited(_playRec(t));
      return;
    }
    // A positive id is a Deezer one — see CatalogAlbum.ref — and this hit came from Deezer. The
    // tracklist and the year are fetched by the page itself, so nothing is invented here.
    final album = CatalogAlbum(t.albumId, t.album, t.cover, null, 0, 'album');
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => AlbumBrowsePage(t.artist, album)));
  }

  Widget _card(Widget art, String title, String subtitle, VoidCallback onTap) =>
      _HoverCard(art: art, title: title, subtitle: subtitle, onTap: onTap);
}

/// A tile in one of the home rows. Same hover growth as the album and artist grids, so the whole
/// app responds the same way to the pointer.
class _HoverCard extends StatefulWidget {
  final Widget art;
  final String title, subtitle;
  final VoidCallback onTap;

  /// The second thing this tile can do, where it has one — play a recommendation outright instead
  /// of opening the record it is on. Null everywhere else, and then nothing changes.
  final VoidCallback? onLongPress;
  const _HoverCard(
      {required this.art,
      required this.title,
      required this.subtitle,
      required this.onTap,
      this.onLongPress});

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Pressable(
          onPressed: widget.onTap,
          onLongPress: widget.onLongPress,
          borderRadius: BorderRadius.circular(14),
          scaleOnFocus: false,
          onFocusChange: (v) => setState(() => _hover = v),
          child: AnimatedScale(
            scale: _hover ? 1.06 : 1,
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOut,
            // min + centred: the row hands out a tight height, and a Column that fills it would
            // scale past the row's edges and get clipped.
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 170),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: _hover
                        ? [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: .45),
                                blurRadius: 22,
                                offset: const Offset(0, 10))
                          ]
                        : const [],
                  ),
                  child: widget.art,
                ),
                const SizedBox(height: 8),
                Text(widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13.5, color: _hover ? Colors.white : null)),
                Text(widget.subtitle,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OntdekView extends StatefulWidget {
  const OntdekView({super.key});
  @override
  State<OntdekView> createState() => _OntdekViewState();
}

class _OntdekViewState extends State<OntdekView> {
  final _rec = RecommendService();
  List<RecTrack> _tracks = [];
  bool _busy = false;
  String? _status;
  int? _expanded;
  int? _playing; // row whose source is being resolved (shows a spinner)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final lib = context.read<LibraryStore>();
    final seeds = lib.artists.where((a) => !_genericArtist(a)).toList()..shuffle();
    if (seeds.isEmpty) {
      setState(() => _status = 'Nog geen bibliotheek om op te ontdekken.');
      return;
    }
    setState(() {
      _busy = true;
      _tracks = [];
      _status = null;
      _expanded = null;
    });
    final owned = <String>{};
    for (final t in lib.tracks) {
      owned.add('${_radioNorm(t.artist)}|${_radioNorm(t.title)}');
    }
    List<RecTrack> recs;
    try {
      recs = await _rec.discover(seeds.take(4).toList());
    } catch (_) {
      recs = const [];
    }
    final fresh = recs
        .where((r) => !owned.contains('${_radioNorm(r.artist)}|${_radioNorm(r.title)}'))
        .toList();
    if (mounted) {
      setState(() {
        _tracks = fresh;
        _busy = false;
        _status = fresh.isEmpty ? 'Niets nieuws gevonden — ververs eens.' : null;
      });
    }
  }

  Future<void> _play(int i, RecTrack t) async {
    final online = context.read<OnlineService>();
    final player = context.read<PlayerStore>();
    setState(() => _playing = i);
    _srcToast(context, 'Bron voorbereiden voor ${t.title}…');
    try {
      final url = await online.resolveRadio(t.artist, t.title, instantOnly: false);
      if (!mounted) return;
      if (url == null) {
        _srcToast(context, 'Geen bron gevonden — open de bronnen (⬇) om te downloaden.');
        return;
      }
      player.playUrl(url, title: t.title, artist: t.artist);
    } catch (e) {
      if (mounted) _srcToast(context, 'Kan niet afspelen: $e');
    } finally {
      if (mounted) setState(() => _playing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
          child: Row(
            children: [
              const Text('Ontdek', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              const Expanded(
                  child: Text('Nieuwe muziek op basis van je bibliotheek',
                      style: TextStyle(color: _muted, fontSize: 13))),
              IconButton(
                  onPressed: _busy ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                  color: _muted,
                  tooltip: 'Ververs'),
            ],
          ),
        ),
        if (_status != null)
          Padding(padding: const EdgeInsets.all(24), child: Text(_status!, style: const TextStyle(color: _muted))),
        if (_busy)
          const Expanded(child: Center(child: CircularProgressIndicator(color: _accent)))
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: _tracks.length,
              itemBuilder: (_, i) => _row(i, _tracks[i]),
            ),
          ),
      ],
    );
  }

  Widget _row(int i, RecTrack t) {
    final open = _expanded == i;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: open ? _panel : Colors.transparent, borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              _netCover(t.cover, size: 44, radius: 6),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    _artistLine(splitFeatured(t.artist, t.title),
                        const TextStyle(color: _muted, fontSize: 12)),
                  ],
                ),
              ),
              _playing == i
                  ? const SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _accent))))
                  : TvLabelled(label: 'Afspelen', child: IconButton(icon: const Icon(Icons.play_arrow_rounded), color: _accent, tooltip: 'Afspelen', onPressed: () => _play(i, t))),
              TvLabelled(label: 'Radio', child: IconButton(icon: const Icon(Icons.radio_rounded, size: 20), color: _muted, tooltip: 'Radio hieruit', onPressed: () => startRadio(context, t.artist))),
              IconButton(
                  icon: Icon(open ? Icons.expand_less_rounded : Icons.download_rounded, size: 20),
                  color: _muted,
                  tooltip: 'Bronnen / download',
                  onPressed: () => setState(() => _expanded = open ? null : i)),
            ],
          ),
        ),
        if (open) Padding(padding: const EdgeInsets.only(bottom: 8), child: SourcesView(query: t.query)),
      ],
    );
  }
}

Future<void> _playTorrent(BuildContext context, SearchResult r) async {
  _srcToast(context, 'Bron voorbereiden…');
  try {
    final url = await context.read<OnlineService>().resolveStreamUrl(r);
    if (context.mounted) context.read<PlayerStore>().playUrl(url, title: r.name, artist: r.source);
  } catch (e) {
    if (context.mounted) _srcToast(context, 'Kan niet afspelen: $e');
  }
}

void _downloadTorrent(BuildContext context, SearchResult r) {
  context.read<DownloadManager>().enqueue(r);
  _srcToast(context, r.cached
      ? 'Downloaden gestart — zie de downloadlijst.'
      : 'Voorbereiden bij TorBox (kan even duren bij weinig seeders) — zie de downloadlijst.');
}

void _pickTorrentTracks(BuildContext context, SearchResult r) {
  showDialog(context: context, builder: (_) => _TrackPickerDialog(r));
}

/// Every peer in [all] offering the same track as [f] (including f itself), best-first.
/// The rule itself lives in organize.dart, where it can be tested without a live peer.
List<SoulseekFile> _slskCandidates(List<SoulseekFile> all, SoulseekFile f) {
  final out =
      all.where((o) => o.isAudio && sameRecording(f.filename, f.durationSec, o.filename, o.durationSec)).toList();
  return out.isEmpty ? [f] : out;
}

/// Ask what "delete" should mean, then do it. [what] names the thing ("het album “Bad”"), and
/// [paths] are the files it covers. Deliberately two distinct choices — removing something from
/// the library must never silently wipe the files off disk.
Future<void> _confirmDelete(BuildContext context, String what, List<String> paths) async {
  final n = paths.length;
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _panel,
      title: Text('$what verwijderen?', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      content: Text(
        'Dit gaat over $n bestand${n == 1 ? "" : "en"}.\n\n'
        '• Alleen uit bibliotheek: het blijft op je pc staan, maar verdwijnt uit de app.\n'
        '• Ook van pc: de bestanden worden definitief verwijderd.',
        style: const TextStyle(color: _muted, fontSize: 13, height: 1.45),
      ),
      actions: [
        // Where the highlight starts, said out loud rather than left to whatever Flutter picks.
        //
        // "Ook van pc" deletes files from the disk and cannot be undone, and it is the last action
        // — which is exactly where a convention of "focus the primary button" would put it. On a
        // remote, one stray press of OK on a dialog you had not read yet would be gone music. So
        // the highlight starts on Cancel, and reaching the red button takes two deliberate presses.
        TextButton(
          autofocus: isTv,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Annuleren'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'library'),
          child: const Text('Alleen uit bibliotheek'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: () => Navigator.pop(ctx, 'disk'),
          child: const Text('Ook van pc'),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;

  final lib = context.read<LibraryStore>();
  final fromDisk = choice == 'disk';
  final deleted = await lib.removeTracks(paths, fromDisk: fromDisk);
  if (!context.mounted) return;
  _srcToast(
      context,
      fromDisk
          ? '$what verwijderd — $deleted bestand${deleted == 1 ? "" : "en"} van je pc gewist.'
          : '$what uit je bibliotheek gehaald (bestanden staan er nog).');
}

String _slskKey(SoulseekFile f) => '${f.username}|${f.filename}';

Future<void> _downloadSoulseek(BuildContext context, SoulseekFile f, List<SoulseekFile> all,
    {TrackTags? authority}) async {
  try {
    // false means it was refused — this track is already downloading. Say so; a "started" message
    // for something that never started is worse than no message.
    final started = await context
        .read<DownloadManager>()
        .enqueueSoulseekBest(_slskCandidates(all, f), key: _slskKey(f), authority: authority);
    if (context.mounted) {
      _srcToast(context,
          started ? '“${f.displayName}” via Soulseek…' : '“${f.displayName}” loopt al — zie Mijn downloads.');
    }
  } catch (e) {
    if (context.mounted) _srcToast(context, 'Download mislukt: $e');
  }
}

/// A download button that turns into a live progress ring while THIS key's job runs — so the
/// user sees progress right on the tile/track row, without opening the download list. Shows a
/// check when done and a retry (with the failure reason as tooltip) when it failed.
/// Everything the app is downloading, in one place — the equivalent of the native Soulseek
/// transfer list. Split into what's still running and what's finished, because a track that is
/// merely WAITING for an uploader's slot is not a failure and shouldn't look like one.
class DownloadsView extends StatelessWidget {
  const DownloadsView({super.key});

  static String statusLabel(DownloadJob j) => switch (j.status) {
        'done' => 'Klaar',
        // A download the user stopped themselves didn't fail — saying "Mislukt" makes it look
        // like something went wrong with it.
        'failed' => j.cancelled ? 'Gestopt' : 'Mislukt',
        'waiting' => j.queuePlace > 0 ? 'Wacht op peer · plaats ${j.queuePlace}' : 'Wacht op peer',
        'queued' => 'In wachtrij',
        // Already on disk and playable; a better copy is still being chased.
        'upgrading' => 'Speelbaar · upgrade',
        'preparing' => j.progress > 0 ? 'Voorbereiden ${(j.progress * 100).round()}%' : 'Voorbereiden',
        _ => 'Bezig ${(j.progress * 100).round()}%',
      };

  static Color statusColor(DownloadJob j) => switch (j.status) {
        'done' => _accent2,
        'failed' => Colors.redAccent,
        'waiting' => const Color(0xFFE0B341),
        'upgrading' => _accent2, // green: you can play it, this is a bonus not a problem
        _ => _accent,
      };

  static IconData statusIcon(DownloadJob j) => switch (j.status) {
        'done' => Icons.check_circle_rounded,
        'failed' => Icons.error_rounded,
        'waiting' => Icons.hourglass_top_rounded,
        'queued' => Icons.schedule_rounded,
        'upgrading' => Icons.upgrade_rounded,
        _ => Icons.downloading_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadManager>(
      builder: (_, dm, __) {
        final active = dm.jobs.where((j) => j.busy).toList();
        final finished = dm.jobs.where((j) => !j.busy).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 30),
          children: [
            // What is kept on THIS device, above what is being fetched onto the PC. Two different
            // things that both live under "downloads": one is music arriving into your library,
            // the other is a copy of your library travelling with you.
            const _OfflineSection(),
            // Title, a running count and a clear button. Side by side that is wider than a phone —
            // the count ran under the button and "Wis afgeronde" hung off the right edge. Wrapped,
            // so it stays one line where there is room and folds where there is not.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 14,
              runSpacing: 4,
              children: [
                const Text('Mijn downloads',
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -.4)),
                if (active.isNotEmpty)
                  // Counted from the jobs themselves: a download waiting in an uploader's queue has
                  // handed its parallel slot back, so the scheduler's counters would read 0 here.
                  Text('${active.where((j) => j.status == 'downloading' || j.status == 'preparing').length} bezig'
                      ' · ${active.where((j) => j.status == 'waiting' || j.status == 'queued').length} wachtend',
                      style: const TextStyle(color: _muted, fontSize: 12.5)),
                if (finished.isNotEmpty)
                  TextButton.icon(
                    onPressed: dm.clearFinished,
                    icon: const Icon(Icons.clear_all_rounded, size: 16),
                    label: const Text('Wis afgeronde'),
                    style: TextButton.styleFrom(foregroundColor: _muted),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (dm.jobs.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(
                  child: Text('Nog geen downloads.\nStart er een vanuit een album of via Online zoeken.',
                      textAlign: TextAlign.center, style: TextStyle(color: _muted, height: 1.6)),
                ),
              ),
            if (active.isNotEmpty) ...[
              const _DlHeader('BEZIG'),
              ...active.map((j) => _DlRow(job: j)),
              const SizedBox(height: 22),
            ],
            if (finished.isNotEmpty) ...[
              const _DlHeader('AFGEROND'),
              ...finished.map((j) => _DlRow(job: j)),
            ],
          ],
        );
      },
    );
  }
}

class _DlHeader extends StatelessWidget {
  final String text;
  const _DlHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .8)),
      );
}

class _DlRow extends StatelessWidget {
  final DownloadJob job;
  const _DlRow({required this.job});

  @override
  Widget build(BuildContext context) {
    final color = DownloadsView.statusColor(job);
    final indeterminate = job.status == 'queued' || job.status == 'waiting';
    // Playable already: show the bar full, whatever is still running for it is a bonus.
    final filled = job.status == 'done' || job.status == 'upgrading';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          Icon(DownloadsView.statusIcon(job), size: 19, color: color),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(job.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
                if (job.detail != null && job.detail!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(job.detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: job.status == 'failed' ? Colors.red.shade300 : _muted)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 190,
            child: LinearProgressIndicator(
              value: filled ? 1 : (indeterminate || job.progress <= 0 ? null : job.progress),
              backgroundColor: const Color(0xFF2A2F42),
              color: color,
            ),
          ),
          const SizedBox(width: 14),
          // Stop what you no longer want — a slot freed here is a slot another download gets.
          SizedBox(
            width: 34,
            child: job.busy && job.canCancel
                ? Consumer<DownloadManager>(
                    builder: (_, dm, __) => IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      color: _muted,
                      tooltip: 'Download stoppen',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => dm.cancelJob(job),
                    ),
                  )
                : null,
          ),
          SizedBox(
            // 150 fixed was the last straw on a phone: a title, a bar, a cancel button and this all
            // side by side ran off the right edge and "Speelbaar · upgrade" was cut mid-word. Half
            // that on a narrow screen, and the label ellipsises rather than the row overflowing.
            width: isCompact(context) ? 74 : 150,
            child: Text(DownloadsView.statusLabel(job),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

Widget _downloadControl(BuildContext context,
    {required String jobKey, required VoidCallback onDownload, String tooltip = 'Downloaden via Soulseek'}) {
  return Consumer<DownloadManager>(
    builder: (_, dm, __) {
      final job = dm.jobByKey(jobKey);
      final status = job?.status;
      if (status == 'queued') {
        // Waiting for a download slot — show a queue clock, NOT a spinner (a spinning ring here
        // looked like a stuck download when several tracks were started at once).
        return const Padding(
          padding: EdgeInsets.all(9),
          child: Tooltip(
            message: 'In wachtrij…',
            child: Icon(Icons.schedule_rounded, color: _muted, size: 19),
          ),
        );
      }
      if (status == 'waiting') {
        // The uploader has us in its queue and will start when a slot frees — exactly what the
        // native client shows as "Queued". Not a failure, so no red: an hourglass plus the place.
        final place = job!.queuePlace;
        return Tooltip(
          message: job.detail ?? 'Wachten op peer…',
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(alignment: Alignment.center, children: [
              const Icon(Icons.hourglass_top_rounded, color: Color(0xFFE0B341), size: 19),
              if (place > 0)
                Positioned(
                  bottom: 2,
                  child: Text('$place',
                      style: const TextStyle(fontSize: 8.5, color: _muted, fontWeight: FontWeight.w700)),
                ),
            ]),
          ),
        );
      }
      if (status == 'downloading' || status == 'preparing') {
        final pct = (job!.progress * 100).round();
        return Tooltip(
          message: job.detail ?? 'Bezig…',
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    value: job.progress > 0 ? job.progress : null,
                    color: _accent,
                    backgroundColor: const Color(0xFF2A2F42)),
              ),
              Text('$pct', style: const TextStyle(fontSize: 8.5, color: _muted, fontWeight: FontWeight.w700)),
            ]),
          ),
        );
      }
      if (status == 'upgrading') {
        // Downloaded and playable — the arrow says a better copy is still being fetched.
        return Tooltip(
          message: job?.detail ?? 'Speelbaar · betere kwaliteit onderweg',
          child: const Padding(
            padding: EdgeInsets.all(9),
            child: Icon(Icons.upgrade_rounded, color: _accent2, size: 20),
          ),
        );
      }
      if (status == 'done') {
        return const Padding(padding: EdgeInsets.all(9), child: Icon(Icons.check_circle_rounded, color: _accent2, size: 20));
      }
      if (status == 'failed') {
        return IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: Colors.redAccent,
            tooltip: job?.detail != null ? 'Mislukt: ${job!.detail} — opnieuw' : 'Mislukt — opnieuw proberen',
            onPressed: onDownload);
      }
      return IconButton(icon: const Icon(Icons.download_rounded), color: _accent, tooltip: tooltip, onPressed: onDownload);
    },
  );
}

/// The most complete album folder among Soulseek hits (most audio files from ONE peer's
/// folder) — so "Download album" grabs a coherent album from a single source.
List<SoulseekFile> _bestSoulseekFolder(List<SoulseekFile> files) {
  final groups = <String, List<SoulseekFile>>{};
  for (final f in files) {
    final p = f.filename.replaceAll('/', '\\');
    final folder = p.contains('\\') ? p.substring(0, p.lastIndexOf('\\')) : p;
    groups.putIfAbsent('${f.username}|$folder', () => []).add(f);
  }
  final ranked = groups.values.toList()
    ..sort((a, b) {
      if (a.length != b.length) return b.length.compareTo(a.length); // most tracks
      final fa = a.where((f) => f.freeSlots).length, fb = b.where((f) => f.freeSlots).length;
      return fb.compareTo(fa); // then most free-slot peers
    });
  return ranked.isEmpty ? const [] : ranked.first;
}

Future<void> _downloadSoulseekAlbum(
    BuildContext context, List<SoulseekFile> folder, List<SoulseekFile> all,
    {ReleaseAuthority? authority}) async {
  // Each folder track → its cross-peer candidates, so a busy peer for one track falls back
  // to another peer offering the same song instead of failing the whole album.
  final tracks = [for (final f in folder) _slskCandidates(all, f)];
  // Which official track each file actually is, decided by name and running time rather than by
  // the number the uploader happened to type in front of it.
  final authorities = [
    for (final f in folder) authority?.match(f.displayName, f.durationSec ?? 0)
  ];
  final n = await context
      .read<DownloadManager>()
      .enqueueSoulseekAlbum(tracks, authorities: authorities);
  if (context.mounted) {
    _srcToast(context, '$n nummer(s) via Soulseek — volg de voortgang in de downloadlijst.');
  }
}

/// Soulseek section header with a "Download album" action for the best complete folder.
/// [all] is the full (unfiltered) result set — used to find fallback peers per track.
Widget _soulseekHeader(BuildContext context, List<SoulseekFile> slsk, bool busy, List<SoulseekFile> all,
    {ReleaseAuthority? authority}) {
  final folder = _bestSoulseekFolder(slsk);
  return Padding(
    padding: const EdgeInsets.fromLTRB(24, 14, 18, 6),
    child: Row(
      children: [
        const Text('SOULSEEK · P2P',
            style: TextStyle(color: _muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6)),
        const SizedBox(width: 8),
        Text('${slsk.length}', style: const TextStyle(color: _muted, fontSize: 11.5)),
        // Back-off notice: after a refused login the app stops touching Soulseek entirely, so the
        // user knows WHY there are no results (instead of thinking the search is just empty).
        if (context.read<SoulseekService>().blocked) ...[
          const SizedBox(width: 10),
          Icon(Icons.pause_circle_outline_rounded, size: 13, color: Colors.orange.shade300),
          const SizedBox(width: 4),
          Text(
              'gepauzeerd — login geweigerd, wacht nog ${(context.read<SoulseekService>().blockedFor?.inMinutes ?? 0) + 1} min',
              style: TextStyle(color: Colors.orange.shade300, fontSize: 11.5)),
          const SizedBox(width: 6),
          // This wait is OUR guard, not Soulseek's. When the official client is logged in fine,
          // the account clearly isn't blocked and the user should never be stuck behind it.
          TextButton(
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 26)),
            onPressed: () {
              context.read<SoulseekService>().retryLoginNow();
              _srcToast(context, 'Soulseek opnieuw proberen…');
            },
            child: const Text('nu opnieuw proberen', style: TextStyle(fontSize: 11.5)),
          ),
        ],
        if (busy) ...const [
          SizedBox(width: 8),
          SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: _muted)),
        ],
        const Spacer(),
        if (folder.length >= 2)
          TextButton.icon(
            onPressed: () => _downloadSoulseekAlbum(context, folder, all, authority: authority),
            icon: const Icon(Icons.library_add_rounded, size: 16),
            label: Text('Download album (${folder.length})'),
            style: TextButton.styleFrom(foregroundColor: _accent, padding: const EdgeInsets.symmetric(horizontal: 8)),
          ),
      ],
    ),
  );
}

Widget _qualityBadge(Quality q) {
  Color fg, bg, border;
  switch (q.tier) {
    case QTier.hires: // hi-res lossless (24-bit / >48kHz / DSD) — gold
      fg = const Color(0xFFF2C14E);
      bg = const Color(0xFF2A2413);
      border = const Color(0xFF5A4A1E);
      break;
    case QTier.lossless: // CD-quality lossless — teal
      fg = _accent2;
      bg = const Color(0xFF0F2521);
      border = const Color(0xFF24493F);
      break;
    case QTier.lossy: // MP3/AAC — blue-grey
      fg = const Color(0xFFA9B6E8);
      bg = const Color(0xFF161A2C);
      border = const Color(0xFF2A3350);
      break;
    case QTier.unknown: // unclear — subtle grey
      fg = _muted;
      bg = const Color(0xFF1A1D29);
      border = _line;
      break;
  }
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 8),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: border)),
    child: Text(q.label, style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w600)),
  );
}

/// Quality of a LOCAL library track (real bitrate from size÷duration, so a 16/44 FLAC and a
/// 24-bit hi-res FLAC read differently).
Quality _trackQuality(Track t) => qualityFromFile(
      name: t.title,
      ext: t.ext,
      isFlac: t.isFlac,
      durationSec: t.duration?.inSeconds,
      size: t.sizeBytes,
    );

Quality _slskQuality(SoulseekFile f) => qualityFromFile(
      name: f.displayName,
      ext: f.ext,
      isFlac: f.isFlac,
      bitrate: f.bitrate,
      durationSec: f.durationSec,
      size: f.size,
      isVbr: f.isVbr,
    );

/// A row of quality-filter chips (Alles / Lossless / Hi-Res / MP3), shared by the
/// direct-search results and the browse "Bronnen" panel.
Widget _filterChipsRow(QFilter current, ValueChanged<QFilter> onChanged) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 20, 2),
      child: Row(
        children: [
          const Icon(Icons.tune_rounded, size: 15, color: _muted),
          const SizedBox(width: 8),
          ...QFilter.values.map((f) {
            final sel = current == f;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: () => onChanged(f),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: sel ? _accent : _panel,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: sel ? _accent : _line),
                  ),
                  child: Text(f.label,
                      style: TextStyle(
                          color: sel ? Colors.white : _muted, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            );
          }),
        ],
      ),
    );

Widget _sourceHeader(String title, int count, bool loading) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
      child: Row(
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(color: _muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6)),
          const SizedBox(width: 8),
          Text('$count', style: const TextStyle(color: _muted, fontSize: 11.5)),
          if (loading) ...const [
            SizedBox(width: 8),
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: _muted)),
          ],
        ],
      ),
    );

Widget _torrentTile(BuildContext context, SearchResult r) {
  final q = qualityFromName(r.name);
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 1),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(8)),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text('${r.source} · ${r.seeders} seeders · ${_fmtBytes(r.size)}',
                      style: const TextStyle(color: _muted, fontSize: 12)),
                  if (r.cached)
                    const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Text('⚡ Instant', style: TextStyle(color: _accent2, fontSize: 12))),
                ],
              ),
            ],
          ),
        ),
        _qualityBadge(q),
        TvLabelled(label: 'Beste nummer', child: IconButton(icon: const Icon(Icons.play_arrow_rounded), color: _accent, tooltip: 'Beste nummer afspelen', onPressed: () => _playTorrent(context, r))),
        TvLabelled(label: 'Kies nummer', child: IconButton(icon: const Icon(Icons.queue_music_rounded), color: _muted, tooltip: 'Kies nummer', onPressed: () => _pickTorrentTracks(context, r))),
        TvLabelled(label: 'Alles', child: IconButton(icon: const Icon(Icons.download_rounded), color: _muted, tooltip: 'Alles downloaden', onPressed: () => _downloadTorrent(context, r))),
      ],
    ),
  );
}

Widget _soulseekTile(BuildContext context, SoulseekFile f, List<SoulseekFile> all, {TrackTags? authority}) {
  final status = f.freeSlots ? 'vrij' : 'wachtrij ${f.queueLength}';
  final q = _slskQuality(f);
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 1),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(8)),
    child: Row(
      children: [
        Icon(f.freeSlots ? Icons.circle : Icons.schedule_rounded, size: 10, color: f.freeSlots ? _accent2 : _muted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(f.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                  '$status · ${f.username} · ${_fmtBytes(f.size)}'
                  '${f.durationSec != null && f.durationSec! > 0 ? " · ${_fmt(Duration(seconds: f.durationSec!))}" : ""}',
                  style: const TextStyle(color: _muted, fontSize: 12)),
            ],
          ),
        ),
        _qualityBadge(q),
        _downloadControl(context,
            jobKey: _slskKey(f),
            onDownload: () => _downloadSoulseek(context, f, all, authority: authority)),
      ],
    ),
  );
}

/// Network cover with a graceful placeholder (album browse / artist photos from Deezer).
Widget _netCover(String? url, {double size = 160, double radius = 12, bool circle = false}) =>
    _NetCover(url: url, size: size, radius: radius, circle: circle);

/// A cover that lives at a URL, drawn from disk the second time you see it.
///
/// `Image.network` caches in memory and nothing else, so every launch of Start, Ontdek or Online
/// zoeken downloaded every cover on the page again — which is what "everything comes in very
/// slowly" was. The bytes go through [CoverEnricher.netImage], which keeps them on disk, and
/// through the map below, which keeps the last few hundred in memory so scrolling a row does not
/// go back to the disk for a picture that is two tiles away.
class _NetCover extends StatefulWidget {
  const _NetCover({required this.url, required this.size, required this.radius, required this.circle});

  final String? url;
  final double size;
  final double radius;
  final bool circle;

  @override
  State<_NetCover> createState() => _NetCoverState();
}

class _NetCoverState extends State<_NetCover> {
  /// Insertion-ordered, so the oldest entry is the first one out. Bounded because a long scroll
  /// through search results would otherwise hold every cover it passed for as long as the app runs.
  static final _mem = <String, Uint8List>{};
  static const _memMax = 300;

  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(_NetCover old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _bytes = null;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final url = widget.url;
    if (url == null || url.isEmpty) return;
    final hit = _mem[url];
    if (hit != null) {
      // Synchronously during initState would be a setState before the first build.
      if (mounted) setState(() => _bytes = hit);
      return;
    }
    final settings = context.read<AppSettings>();
    final bytes = await CoverEnricher(settings).netImage(url);
    if (bytes == null || !mounted || widget.url != url) return;
    _mem[url] = bytes;
    if (_mem.length > _memMax) _mem.remove(_mem.keys.first);
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final shape = widget.circle ? BoxShape.circle : BoxShape.rectangle;
    final br = widget.circle ? null : BorderRadius.circular(widget.radius);
    final b = _bytes;
    if (b == null) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: shape,
          borderRadius: br,
          gradient: const LinearGradient(colors: [Color(0xFF242838), Color(0xFF1A1D29)]),
        ),
        child: Icon(widget.circle ? Icons.person_rounded : Icons.album_rounded,
            color: _muted.withValues(alpha: .4), size: widget.size * .34),
      );
    }
    return Container(
      width: widget.size,
      height: widget.size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(shape: shape, borderRadius: br),
      // A cover arriving is the page filling in, not an effect: it fades rather than snapping,
      // because a grid where twenty tiles pop in at slightly different moments reads as flicker.
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: Image.memory(b,
            key: ValueKey(widget.url),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox()),
      ),
    );
  }
}

/// Combined torrent + Soulseek sources for one query — the "streams" list under a track/album.
class SourcesView extends StatefulWidget {
  final String query;

  /// The official release this list of sources belongs to, when it was opened from an album page.
  ///
  /// Soulseek serves one song under a dozen names and each carries its own tags. Without this the
  /// peer decides what track it is; with it, the record does and Soulseek only supplies the audio.
  /// Null when the sources were opened from a loose search, where there is no release to appeal to.
  final ReleaseAuthority? authority;

  /// The one track these sources are for, when this list is under a track row.
  final ChoiceTrack? track;
  const SourcesView({super.key, required this.query, this.authority, this.track});
  @override
  State<SourcesView> createState() => _SourcesViewState();
}

class _SourcesViewState extends State<SourcesView> {
  List<SearchResult> _torrents = [];
  List<SoulseekFile> _slsk = [];
  bool _tBusy = true, _sBusy = false;
  QFilter _filter = QFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final online = context.read<OnlineService>();
    final soulseek = context.read<SoulseekService>();
    if (mounted) setState(() { _tBusy = true; _sBusy = soulseek.available; });
    if (soulseek.available) {
      soulseek.search(widget.query, onPartial: (p) {
        if (mounted) setState(() => _slsk = p);
      }).then((r) {
        if (mounted) setState(() { _slsk = r; _sBusy = false; });
      }).catchError((_) { if (mounted) setState(() => _sBusy = false); });
    }
    try {
      final r = await online.search(widget.query, onPartial: (p) {
        if (mounted) setState(() => _torrents = p);
      });
      if (mounted) setState(() => _torrents = r);
    } catch (_) {}
    if (mounted) setState(() => _tBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    final ready = context.read<SoulseekService>().available;
    final torrents = _torrents.where((r) => _filter.matches(qualityFromName(r.name))).toList();
    final slsk = _slsk.where((f) => _filter.matches(_slskQuality(f))).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_torrents.isNotEmpty || _slsk.isNotEmpty)
          _filterChipsRow(_filter, (f) => setState(() => _filter = f)),
        _sourceHeader('Torrents · TorBox', torrents.length, _tBusy),
        if (torrents.isEmpty && !_tBusy)
          const Padding(
              padding: EdgeInsets.fromLTRB(24, 2, 24, 6),
              child: Text('Geen torrents gevonden.', style: TextStyle(color: _muted, fontSize: 12.5))),
        ...torrents.map((r) => _torrentTile(context, r)),
        if (ready)
          _soulseekHeader(context, slsk, _sBusy, slsk, authority: widget.authority)
        else
          const Padding(
              padding: EdgeInsets.fromLTRB(24, 14, 24, 6),
              child: Text('SOULSEEK · log in via Instellingen',
                  style: TextStyle(color: _muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6))),
        if (ready && slsk.isEmpty && !_sBusy)
          const Padding(
              padding: EdgeInsets.fromLTRB(24, 2, 24, 6),
              child: Text('Geen Soulseek-bronnen.', style: TextStyle(color: _muted, fontSize: 12.5))),
        // Whichever copy the user picks, the record decides what it is. That is the whole point:
        // this same song is offered as "13 …", "19. …" and "…The Essential … - 01 - …".
        ..._slskTiles(context, slsk, authority: _trackAuthority),
      ],
    );
  }

  /// What the track under this list IS, when it was opened from an album page.
  TrackTags? get _trackAuthority {
    final a = widget.authority, t = widget.track;
    if (a == null || t == null) return null;
    // The position IS the number: this tracklist came from the official release. Never indexOf on
    // the track — ChoiceTrack has no equality, so it would miss every time and fall back to
    // something that is not a track number at all.
    final stated = int.tryParse(t.position) ?? 0;
    if (stated > 0) return a.forTrack(t, stated);
    final at = a.tracks.indexWhere((x) => normKey(x.title) == normKey(t.title));
    return at < 0 ? null : a.forTrack(t, at + 1);
  }
}

/// Rows are built eagerly inside a plain ListView, so a broad query (3500+ hits is normal for a
/// popular track) would build every one of them on every rebuild and lock the UI. Results are
/// quality-sorted, so showing the head is no loss — and the full list is still handed to each
/// tile as its candidate pool, so downloading keeps every fallback peer.
const _slskShown = 250;

List<Widget> _slskTiles(BuildContext context, List<SoulseekFile> slsk, {TrackTags? authority}) {
  final shown = slsk.length <= _slskShown ? slsk : slsk.sublist(0, _slskShown);
  return [
    ...shown.map((f) => _soulseekTile(context, f, slsk, authority: authority)),
    if (slsk.length > _slskShown)
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
        child: Text(
          'Nog ${slsk.length - _slskShown} bronnen niet getoond — de beste staan bovenaan. '
          'Verfijn je zoekopdracht om ze te zien.',
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
      ),
  ];
}

class OnlineSearchScreen extends StatefulWidget {
  const OnlineSearchScreen({super.key});
  @override
  State<OnlineSearchScreen> createState() => _OnlineSearchScreenState();
}

class _OnlineSearchScreenState extends State<OnlineSearchScreen> {
  final _c = TextEditingController();

  /// Skipped when arrowing on a television, for the same reason as the library search: focus opens
  /// the leanback keyboard, and the keyboard then swallows every arrow press — so the whole tab
  /// below it becomes unreachable. OK on the field is what opens it.
  final _searchFocus = FocusNode(skipTraversal: isTv, debugLabel: 'online search');
  final _catalog = CatalogService();
  int _mode = 0; // 0 = Bladeren, 1 = Direct, 2 = TIDAL
  // browse (artists + albums + tracks)
  List<CatalogArtist> _artists = [];
  List<CatalogAlbumHit> _albumHits = [];
  List<CatalogTrackHit> _trackHits = [];
  bool _browseBusy = false;
  int? _trackExpanded;
  // direct
  List<SearchResult> _torrents = [];
  List<SoulseekFile> _slsk = [];
  bool _busy = false, _slskBusy = false;
  String? _status;
  QFilter _filter = QFilter.all;
  int _searchGen = 0; // guards streaming callbacks from a superseded search
  // tidal
  List<TidalTrack> _tidalTracks = [];
  bool _tidalBusy = false, _tidalConnecting = false;
  int? _tidalExpanded;

  Future<void> _search() async {
    final q = _c.text.trim();
    if (q.isEmpty) return;
    if (_mode == 0) {
      await _searchBrowse(q);
    } else if (_mode == 1) {
      await _searchDirect(q);
    } else {
      await _searchTidal(q);
    }
  }

  Future<void> _searchTidal(String q) async {
    final tidal = context.read<TidalService>();
    if (!tidal.connected) return;
    setState(() { _tidalBusy = true; _tidalTracks = []; _tidalExpanded = null; _status = null; });
    try {
      final t = await tidal.searchTracks(q);
      if (mounted) setState(() { _tidalTracks = t; _status = t.isEmpty ? 'Geen TIDAL-resultaten.' : null; });
    } catch (e) {
      if (mounted) setState(() => _status = 'TIDAL-zoeken mislukt: $e');
    } finally {
      if (mounted) setState(() => _tidalBusy = false);
    }
  }

  Future<void> _connectTidal() async {
    final tidal = context.read<TidalService>();
    setState(() => _tidalConnecting = true);
    try {
      await tidal.login();
      if (mounted) _srcToast(context, 'TIDAL verbonden ✓');
    } catch (e) {
      if (mounted) _srcToast(context, 'TIDAL-login mislukt: $e');
    } finally {
      if (mounted) setState(() => _tidalConnecting = false);
    }
  }

  Future<void> _manualTidal() async {
    final tidal = context.read<TidalService>();
    final ctrl = TextEditingController();
    final pasted = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('TIDAL-code plakken', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: dialogWidth(context, 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Plak de volledige "debridmusic://…"-URL (of enkel de code) die je browser na het inloggen toonde.',
                  style: TextStyle(color: _muted, fontSize: 12.5)),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                autofocus: true,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFF14161F),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _line)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _line)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuleren')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Verbind'),
          ),
        ],
      ),
    );
    if (pasted == null || pasted.isEmpty) return;
    setState(() => _tidalConnecting = true);
    try {
      await tidal.completeManual(pasted);
      if (mounted) _srcToast(context, 'TIDAL verbonden ✓');
    } catch (e) {
      if (mounted) _srcToast(context, 'Mislukt: $e');
    } finally {
      if (mounted) setState(() => _tidalConnecting = false);
    }
  }

  /// Append what Discogs has that Deezer does not.
  ///
  /// Deezer catalogues what streams and is the faster, cleaner search, so it stays first and the
  /// list is usable before Discogs answers at all. Discogs is where the editions, the promos and
  /// the regional issues live — the versions Deezer has no entry for.
  ///
  /// Deduped on artist + title, so the same record never appears twice; a different EDITION of it
  /// carries a different title and still comes through, which is the whole reason to add it.
  Future<void> _addDiscogsAlbums(String q) async {
    try {
      final extra = await DiscogsService(context.read<AppSettings>()).searchAlbums(q);
      if (!mounted || extra.isEmpty) return;
      String key(CatalogAlbumHit h) => '${artistKey(h.artist)}|${normKey(h.album.title)}';
      final seen = {for (final h in _albumHits) key(h)};
      final add = [
        for (final h in extra)
          if (seen.add(key(h))) h
      ];
      if (add.isEmpty) return;
      setState(() {
        _albumHits = [..._albumHits, ...add];
        _status = null;
      });
    } catch (_) {/* Deezer on its own is still a working search */}
  }

  /// Add what MusicBrainz knows: albums, tracks and artists.
  ///
  /// Runs AFTER Deezer, never inside its Future.wait — MusicBrainz spaces its requests 1100 ms
  /// apart, and putting it in the same wait would hold the fast results hostage to the slow one.
  ///
  /// Every query is scoped to an artist first. MusicBrainz ranks on text alone with no popularity
  /// signal at all: bare "thriller" returns Part Chimp and Swoop before Michael Jackson, and bare
  /// "quit playing games" returns Mar.Ko before the Backstreet Boys. Scoped, both are exact.
  Future<void> _addMusicBrainzHits(String q) async {
    final mb = context.read<MusicBrainzService>();
    try {
      // "Artist - Album" first, then the whole query as an artist name, then whatever the Deezer
      // pass already decided the artist was. Any of the three gives the scoping that makes this work.
      var artist = '', rest = q.trim();
      final dash = q.indexOf(' - ');
      if (dash > 0) {
        artist = q.substring(0, dash).trim();
        rest = q.substring(dash + 3).trim();
      } else if (_artists.isNotEmpty) {
        artist = _artists.first.name;
      }

      final found = await mb.searchArtists(q, max: 8);
      if (!mounted) return;
      if (found.isNotEmpty) {
        final have = {for (final a in _artists) artistKey(a.name)};
        final add = [
          for (final a in found)
            if (have.add(artistKey(a.name)))
              CatalogArtist(0, a.name, null, 0,
                  origin: CatalogRef.musicbrainz(a.mbid), detail: a.line)
        ];
        if (add.isNotEmpty) setState(() => _artists = [..._artists, ...add]);
        if (artist.isEmpty) artist = found.first.name;
      }

      // Records, not pressings — otherwise twenty CDs of one album are twenty cards.
      final groups = await mb.searchReleaseGroups(rest, artist: artist);
      if (!mounted) return;
      if (groups.isNotEmpty) {
        final have = {
          for (final h in _albumHits) '${artistKey(h.artist)}|${normKey(h.album.title)}'
        };
        final add = <CatalogAlbumHit>[];
        for (final g in groups) {
          if (!have.add('${artistKey(g.artist)}|${normKey(g.title)}')) continue;
          add.add(CatalogAlbumHit(
            CatalogAlbum(0, g.title, null, g.firstDate, 0,
                g.primaryType.toLowerCase().isEmpty ? 'album' : g.primaryType.toLowerCase(),
                // A GROUP, not a release. Opening it resolves a pressing first — only a pressing
                // has a tracklist, and handing a group id to the release endpoint loads nothing.
                origin: CatalogRef.musicbrainzGroup(g.mbid)),
            g.artist,
          ));
          if (add.length >= 12) break;
        }
        if (add.isNotEmpty) setState(() => _albumHits = [..._albumHits, ...add]);
      }

      final recs = await mb.searchRecordings(rest, artist: artist);
      if (!mounted || recs.isEmpty) return;
      // MusicBrainz returns one row per release a recording appears on, so a popular song comes
      // back twenty-five times. Without this the track list is one title repeated.
      final have = {for (final t in _trackHits) '${artistKey(t.artist)}|${normKey(t.title)}'};
      final add = [
        for (final r in recs)
          if (have.add('${artistKey(r.artist)}|${normKey(r.title)}'))
            CatalogTrackHit(r.title, r.artist, null)
      ];
      if (add.isNotEmpty) setState(() => _trackHits = [..._trackHits, ...add.take(12)]);
    } catch (_) {/* Deezer and Discogs on their own are still a working search */}
  }

  Future<void> _searchBrowse(String q) async {
    setState(() {
      _browseBusy = true;
      _artists = [];
      _albumHits = [];
      _trackHits = [];
      _trackExpanded = null;
      _status = null;
    });
    try {
      final res = await Future.wait([
        _catalog.searchArtists(q),
        _catalog.searchAlbums(q),
        _catalog.searchTracks(q),
      ]);
      if (!mounted) return;
      setState(() {
        _artists = res[0] as List<CatalogArtist>;
        _albumHits = res[1] as List<CatalogAlbumHit>;
        _trackHits = res[2] as List<CatalogTrackHit>;
        _status = (_artists.isEmpty && _albumHits.isEmpty && _trackHits.isEmpty)
            ? 'Niets gevonden.'
            : null;
      });
      await _addDiscogsAlbums(q);
      await _addMusicBrainzHits(q);
      if (mounted && _artists.isEmpty && _albumHits.isEmpty && _trackHits.isEmpty) {
        setState(() => _status = 'Niets gevonden.');
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Zoeken mislukt: $e');
    } finally {
      if (mounted) setState(() => _browseBusy = false);
    }
  }

  Future<void> _searchDirect(String q) async {
    final online = context.read<OnlineService>();
    final soulseek = context.read<SoulseekService>();
    final gen = ++_searchGen; // a newer search invalidates this one's streaming callbacks
    bool live() => mounted && gen == _searchGen;
    setState(() {
      _busy = true;
      _slskBusy = soulseek.available;
      _torrents = [];
      _slsk = [];
      _status = 'Zoeken…';
    });
    if (soulseek.available) {
      soulseek.search(q, onPartial: (p) {
        if (live()) setState(() => _slsk = p); // stream results as peers respond
      }).then((r) {
        if (live()) setState(() { _slsk = r; _slskBusy = false; });
      }).catchError((_) {
        if (live()) setState(() => _slskBusy = false);
      });
    }
    try {
      final r = await online.search(q, onPartial: (p) {
        if (live()) setState(() { _torrents = p; _status = null; }); // fast sources show first
      });
      if (live()) setState(() { _torrents = r; _status = null; });
    } catch (e) {
      if (live()) setState(() => _status = 'Torrent-zoeken mislukt: $e');
    } finally {
      if (live()) setState(() => _busy = false);
    }
  }

  void _setMode(int m) {
    if (m == _mode) return;
    setState(() { _mode = m; _status = null; });
  }

  @override
  void dispose() {
    _c.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final soulseekReady = context.read<SoulseekService>().available;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 22, 24, 8),
          child: Text('Online zoeken', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: Row(children: [
            _modeChip('Bladeren', 0),
            const SizedBox(width: 8),
            _modeChip('Direct zoeken', 1),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Row(
            children: [
              Expanded(
                child: MaybePressable(
                  enabled: isTv,
                  onPressed: _searchFocus.requestFocus,
                  borderRadius: BorderRadius.circular(11),
                  child: TextField(
                  controller: _c,
                  focusNode: _searchFocus,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    hintText: _mode == 0
                        ? 'Zoek artiest, album of nummer…'
                        : (_mode == 2 ? 'Zoek in TIDAL…' : 'Artiest, album of nummer…'),
                    filled: true,
                    fillColor: _panel,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _line)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _line)),
                  ),
                ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: _accent, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18)),
                // Guarded on a television, disabled everywhere else.
                //
                // Disabling it is right under a mouse — the button greys out and the cursor says
                // so. On a TV it is wrong: a disabled button leaves the traversal order, and while
                // a search runs this was the only thing next to a field that is skipped, so the
                // highlight had nowhere to be. Guarding it on BOTH would have quietly taken the
                // grey away from Windows and the iPad, where nothing was broken.
                onPressed: (!isTv && (_busy || _browseBusy || _tidalBusy))
                    ? null
                    : () {
                        if (_busy || _browseBusy || _tidalBusy) return;
                        _search();
                      },
                autofocus: isTv,
                child: const Text('Zoek'),
              ),
            ],
          ),
        ),
        Consumer<DownloadManager>(
          builder: (_, dm, __) {
            final recent = dm.jobs.take(5).toList();
            if (recent.isEmpty) return const SizedBox.shrink();
            final hasFinished = dm.jobs.any((j) => j.status == 'done' || j.status == 'failed');
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text('DOWNLOADS',
                          style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .6)),
                      const Spacer(),
                      if (hasFinished)
                        TextButton.icon(
                          onPressed: () => dm.clearFinished(),
                          icon: const Icon(Icons.clear_all_rounded, size: 15),
                          label: const Text('Wis afgeronde'),
                          style: TextButton.styleFrom(
                              foregroundColor: _muted,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              textStyle: const TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                  ...recent
                    .map((j) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(j.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12.5)),
                                      if (j.detail != null && j.detail!.isNotEmpty)
                                        Text(j.detail!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 10.5,
                                                color: j.status == 'failed' ? Colors.red.shade300 : _muted)),
                                    ],
                                  )),
                              SizedBox(
                                width: 160,
                                child: LinearProgressIndicator(
                                  value: j.status == 'done'
                                      ? 1
                                      : (j.status == 'preparing' && j.progress <= 0 ? null : j.progress),
                                  backgroundColor: const Color(0xFF2A2F42),
                                  color: j.status == 'failed'
                                      ? Colors.red
                                      : (j.status == 'done' ? _accent2 : _accent),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 70,
                                child: Text(
                                  j.status == 'done'
                                      ? 'klaar'
                                      : (j.status == 'failed'
                                          ? (j.cancelled ? 'gestopt' : 'mislukt')
                                          : (j.status == 'queued'
                                              ? 'wachtrij'
                                              : (j.status == 'preparing'
                                                  ? (j.progress > 0 ? 'TorBox ${(j.progress * 100).round()}%' : 'voorbereiden')
                                                  : '${(j.progress * 100).round()}%'))),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(color: _muted, fontSize: 11.5),
                                ),
                              ),
                            ],
                          ),
                        )),
                ],
              ),
            );
          },
        ),
        if (_status != null)
          Padding(padding: const EdgeInsets.all(24), child: Text(_status!, style: const TextStyle(color: _muted))),
        Expanded(
            child: _mode == 0
                ? _browseResults()
                : (_mode == 1 ? _directResults(soulseekReady) : _tidalResults())),
      ],
    );
  }

  Widget _tidalResults() {
    final tidal = context.read<TidalService>();
    if (!tidal.configured) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Stel je TIDAL Client ID + Secret in via Instellingen (⚙) om TIDAL te gebruiken.',
              textAlign: TextAlign.center, style: TextStyle(color: _muted)),
        ),
      );
    }
    if (!tidal.connected) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text('Verbind je TIDAL-account om je muziek te doorzoeken.\n'
                  'Je logt in op TIDAL zelf — DebridMusic ziet je wachtwoord niet.',
                  textAlign: TextAlign.center, style: TextStyle(color: _muted)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _accent, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
              icon: _tidalConnecting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.link_rounded, size: 18),
              label: Text(_tidalConnecting ? 'Bezig… (log in in je browser)' : 'Verbind TIDAL'),
              onPressed: _tidalConnecting ? null : _connectTidal,
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: _tidalConnecting ? null : _manualTidal,
              child: const Text('Lukt het automatisch niet? Plak de URL handmatig',
                  style: TextStyle(color: _muted, fontSize: 12.5)),
            ),
          ],
        ),
      );
    }
    if (_tidalBusy) return const Center(child: CircularProgressIndicator(color: _accent));
    if (_tidalTracks.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Verbonden met TIDAL ✓  — zoek een nummer; de bronnen (torrent/Soulseek) verschijnen eronder.',
              textAlign: TextAlign.center, style: TextStyle(color: _muted)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _tidalTracks.length,
      itemBuilder: (_, i) => _tidalTrackRow(i, _tidalTracks[i]),
    );
  }

  Widget _tidalTrackRow(int i, TidalTrack t) {
    final open = _tidalExpanded == i;
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _tidalExpanded = open ? null : i),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(color: open ? _panel : Colors.transparent, borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (t.artist.isNotEmpty)
                        _artistLine(splitFeatured(t.artist, t.title),
                            const TextStyle(color: _muted, fontSize: 12)),
                    ],
                  ),
                ),
                Icon(open ? Icons.expand_less_rounded : Icons.travel_explore_rounded, size: 18, color: open ? _accent : _muted),
              ],
            ),
          ),
        ),
        if (open) Padding(padding: const EdgeInsets.only(bottom: 8), child: SourcesView(query: t.sourceQuery)),
      ],
    );
  }

  Widget _modeChip(String label, int m) {
    final sel = _mode == m;
    return Pressable(
      onPressed: () => _setMode(m),
      borderRadius: BorderRadius.circular(999),
      scaleOnFocus: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? _accent : _panel,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: sel ? _accent : _line),
        ),
        child: Text(label, style: TextStyle(color: sel ? Colors.white : _muted, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _browseResults() {
    if (_browseBusy) return const Center(child: CircularProgressIndicator(color: _accent));
    if (_artists.isEmpty && _albumHits.isEmpty && _trackHits.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Zoek een artiest, album of nummer — bronnen (torrent/Soulseek) verschijnen eronder.',
              textAlign: TextAlign.center, style: TextStyle(color: _muted)),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (_artists.isNotEmpty) ...[
          _browseHeader('Artiesten', _artists.length),
          SizedBox(
            height: 158,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _artists.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final a = _artists[i];
                return InkWell(
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ArtistBrowsePage(a))),
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 116,
                    child: Column(
                      children: [
                        _netCover(a.picture, size: 116, circle: true),
                        const SizedBox(height: 6),
                        Text(a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        if (_albumHits.isNotEmpty) ...[
          _browseHeader('Albums', _albumHits.length),
          SizedBox(
            height: 186,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _albumHits.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final h = _albumHits[i];
                return InkWell(
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => AlbumBrowsePage(h.artist, h.album))),
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 132,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _netCover(h.album.cover, size: 132, radius: 10),
                        const SizedBox(height: 6),
                        Text(h.album.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        Text(h.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: _muted)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        if (_trackHits.isNotEmpty) ...[
          _browseHeader('Nummers', _trackHits.length),
          ..._trackHits.asMap().entries.map((e) => _browseTrackRow(e.key, e.value)),
        ],
      ],
    );
  }

  Widget _browseHeader(String title, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
        child: Text('${title.toUpperCase()}  ·  $count',
            style: const TextStyle(
                color: _muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6)),
      );

  Widget _browseTrackRow(int i, CatalogTrackHit t) {
    final open = _trackExpanded == i;
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _trackExpanded = open ? null : i),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration:
                BoxDecoration(color: open ? _panel : Colors.transparent, borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                _netCover(t.cover, size: 42, radius: 6),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      _artistLine(splitFeatured(t.artist, t.title),
                          const TextStyle(fontSize: 12, color: _muted)),
                    ],
                  ),
                ),
                Icon(open ? Icons.expand_less_rounded : Icons.chevron_right_rounded, color: _muted),
              ],
            ),
          ),
        ),
        if (open) Padding(padding: const EdgeInsets.only(bottom: 8), child: SourcesView(query: t.query)),
      ],
    );
  }

  Widget _directResults(bool soulseekReady) {
    final torrents = _torrents.where((r) => _filter.matches(qualityFromName(r.name))).toList();
    final slsk = _slsk.where((f) => _filter.matches(_slskQuality(f))).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (_torrents.isNotEmpty || _slsk.isNotEmpty)
          _filterChipsRow(_filter, (f) => setState(() => _filter = f)),
        if (torrents.isNotEmpty) _sourceHeader('Torrents · TorBox', torrents.length, _busy),
        ...torrents.map((r) => _torrentTile(context, r)),
        if (_status == null || _slsk.isNotEmpty || _slskBusy)
          (soulseekReady
              ? _soulseekHeader(context, slsk, _slskBusy, slsk)
              : const Padding(
                  padding: EdgeInsets.fromLTRB(24, 16, 24, 6),
                  child: Text('SOULSEEK · log in via Instellingen om P2P mee te zoeken',
                      style: TextStyle(color: _muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: .6)))),
        ..._slskTiles(context, slsk),
      ],
    );
  }
}

/// Resolves a torrent's audio files and lets the user play or download any single track.
class _TrackPickerDialog extends StatefulWidget {
  final SearchResult result;
  const _TrackPickerDialog(this.result);
  @override
  State<_TrackPickerDialog> createState() => _TrackPickerDialogState();
}

class _TrackPickerDialogState extends State<_TrackPickerDialog> {
  bool _loading = true;
  String? _error;
  TbTorrent? _torrent;
  List<TbFile> _files = [];
  double _prep = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (t, f) = await context.read<OnlineService>().tracklist(widget.result, onProgress: (p, s) {
        if (mounted) setState(() => _prep = p);
      });
      if (!mounted) return;
      setState(() {
        _torrent = t;
        _files = f;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _play(TbFile f) async {
    try {
      final url = await context.read<OnlineService>().resolveTrackUrl(_torrent!.id, f.id);
      if (!mounted) return;
      context.read<PlayerStore>().playUrl(url, title: f.label, artist: widget.result.source);
      Navigator.pop(context);
    } catch (e) {
      _snack('Afspelen mislukt: $e');
    }
  }

  void _download(TbFile f) {
    context.read<DownloadManager>().enqueue(widget.result, fileId: f.id);
    _snack('“${f.label}” naar downloads');
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        width: dialogWidth(context, 560),
        constraints: const BoxConstraints(maxHeight: 560),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.result.name,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Kies een nummer om af te spelen of los te downloaden',
                style: TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 14),
            if (_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                child: Center(
                  child: Column(children: [
                    const CircularProgressIndicator(color: _accent),
                    const SizedBox(height: 16),
                    Text(
                        _prep > 0
                            ? 'TorBox haalt de torrent op… ${(_prep * 100).round()}%'
                            : 'Bron voorbereiden bij TorBox…',
                        style: const TextStyle(color: _muted, fontSize: 12.5)),
                    if (_prep > 0) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                            value: _prep, minHeight: 4, backgroundColor: _panel2, color: _accent),
                      ),
                    ],
                    if (!widget.result.cached) ...const [
                      SizedBox(height: 10),
                      Text('Niet-gecachte torrents met weinig seeders kunnen even duren.',
                          textAlign: TextAlign.center, style: TextStyle(color: _muted, fontSize: 11)),
                    ],
                  ]),
                ),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _files.length,
                  itemBuilder: (_, i) {
                    final f = _files[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(f.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
                                Text('${_fmtBytes(f.size)}${f.isFlac ? " · FLAC" : ""}',
                                    style: const TextStyle(color: _muted, fontSize: 11.5)),
                              ],
                            ),
                          ),
                          IconButton(
                              icon: const Icon(Icons.play_arrow_rounded, size: 22),
                              color: _accent,
                              tooltip: 'Afspelen',
                              onPressed: () => _play(f)),
                          IconButton(
                              icon: const Icon(Icons.download_rounded, size: 20),
                              color: _muted,
                              tooltip: 'Download dit nummer',
                              onPressed: () => _download(f)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Sluiten')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Collapsed artist bio (3 lines) that opens the full text in a dialog on tap.
class BioText extends StatelessWidget {
  final String artist;
  final String text;
  const BioText(this.artist, this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    // Capped where the long text actually lives, so artist bios and album blurbs both get it.
    // Align is load-bearing: a list hands its children a TIGHT width and a bare ConstrainedBox
    // cannot shrink below that — without it the cap silently does nothing.
    //
    // The Align sits OUTSIDE the Pressable, not inside it. Inside, the opaque hit test claimed the
    // Align's full row width, so on Windows a hand cursor appeared and a click landed hundreds of
    // pixels to the right of any text — over empty background. The press target is the paragraph.
    return Align(
      alignment: Alignment.topLeft,
      child: Pressable(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: _panel,
            title: Text(artist, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            content: SizedBox(
              width: dialogWidth(context, 540),
              child: SingleChildScrollView(
                child: Text(text, style: const TextStyle(color: Color(0xFFC7CBDA), fontSize: 13.5, height: 1.5)),
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Sluiten'))],
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 13, height: 1.45)),
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Text('Lees meer',
                    style: TextStyle(color: _accent, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The banner at the top of the start page: the newest releases, one at a time, large.
///
/// The cover doubles as the backdrop — blurred, darkened and bled to the edges — because an album
/// has no separate wide artwork the way a film has a still. Auto-advances, but stops the moment
/// the pointer is on it so it can't slide away mid-read.
class HeroCarousel extends StatefulWidget {
  final List<CatalogAlbumHit> hits;
  const HeroCarousel({super.key, required this.hits});

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final _page = PageController();
  Timer? _timer;
  int _index = 0;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    if (widget.hits.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || _hover || !_page.hasClients) return;
      _page.animateToPage((_index + 1) % widget.hits.length,
          duration: const Duration(milliseconds: 550), curve: Curves.easeInOutCubic);
    });
  }

  void _go(int delta) {
    if (!_page.hasClients) return;
    final n = widget.hits.length;
    _page.animateToPage((_index + delta + n) % n,
        duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          // The banner lays a cover beside a title, a year and a button. On a phone that column is
          // narrow enough that the title takes two lines and the button fell one pixel past the
          // bottom — so the banner is taller there, not shorter.
          height: isCompact(context) ? 300 : 260,
          child: Stack(
            children: [
              PageView.builder(
                controller: _page,
                itemCount: widget.hits.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _slide(widget.hits[i]),
              ),
              if (widget.hits.length > 1) ...[
                _arrow(Alignment.centerLeft, Icons.chevron_left_rounded, -1),
                _arrow(Alignment.centerRight, Icons.chevron_right_rounded, 1),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < widget.hits.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 260),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _index ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == _index ? Colors.white : Colors.white.withValues(alpha: .38),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _arrow(Alignment side, IconData icon, int delta) => Align(
        alignment: side,
        child: AnimatedOpacity(
          opacity: _hover ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Material(
              color: Colors.black.withValues(alpha: .45),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _go(delta),
                child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, size: 26, color: Colors.white)),
              ),
            ),
          ),
        ),
      );

  Widget _slide(CatalogAlbumHit hit) {
    final cover = hit.album.cover;
    // The whole banner is clickable AND carries a "Bekijken" button that does the same thing. For a
    // mouse that is a convenience; for a remote it is two stops with one outcome, and a ring drawn
    // around 260 points of artwork.
    //
    // So on a television the banner is not pressable and the button is. NOT ExcludeFocus, which was
    // the first attempt and was simply wrong: it excludes the whole subtree, so it took the
    // "Bekijken" button out of the highlight's path as well and left the entire carousel
    // unreachable — the opposite of what the comment claimed.
    return Pressable(
      onPressed: isTv
          ? null
          : () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => AlbumBrowsePage(hit.artist, hit.album))),
      borderRadius: BorderRadius.circular(12),
      scaleOnFocus: false,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (cover != null)
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
              ),
            // Without this the blurred art is too busy to read white text on. Kept dark even at
            // the far edge: a mostly-white sleeve blurs to near-white and washed the banner out.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.black.withValues(alpha: .88), Colors.black.withValues(alpha: .62)],
                ),
              ),
            ),
            Padding(
              // 28 a side plus a 168 cover plus a 24 gap is 248 of a phone's 411 points, and the
              // 163 left over is not enough for the button beside it — "Bekijken" broke in half.
              padding: EdgeInsets.fromLTRB(
                  isCompact(context) ? 16 : 28, 24, isCompact(context) ? 16 : 28, 28),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: isCompact(context) ? 118 : 168,
                      height: isCompact(context) ? 118 : 168,
                      child: cover == null
                          ? Container(color: _panel2)
                          : Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: _panel2)),
                    ),
                  ),
                  SizedBox(width: isCompact(context) ? 14 : 24),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('NIEUWE RELEASE',
                            style: TextStyle(
                                color: _accent2, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                        const SizedBox(height: 8),
                        Text(hit.album.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800, height: 1.1)),
                        const SizedBox(height: 6),
                        Text(hit.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, color: Color(0xFFC7CBDA))),
                        if (hit.album.year != null) ...[
                          const SizedBox(height: 2),
                          Text('${hit.album.year}', style: const TextStyle(fontSize: 12.5, color: _muted)),
                        ],
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: _accent, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                          onPressed: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => AlbumBrowsePage(hit.artist, hit.album))),
                          icon: const Icon(Icons.playlist_add_rounded, size: 18),
                          label: const Text('Bekijken'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A cinematic banner for an artist: wide backdrop, and the act's OWN wordmark rather than their
/// name set in the app's typeface.
///
/// The wordmark is the point. There is no way to render text in an artist's official lettering —
/// those fonts aren't distributed — but the logo itself is an image of exactly that lettering, so
/// showing it is the real thing instead of an imitation. Falls back to plain text for the acts
/// that have no logo (about one in four).
/// The artist's own photo, blurred, standing behind a WHOLE page rather than behind a banner.
///
/// It does not scroll: the records and tracks move over a wash that stays put, so the page reads
/// as one thing about one artist instead of a strip of atmosphere with a list bolted under it.
/// The scrim is light at the top, where the portrait and wordmark are, and settles to near-solid
/// below that — album titles and track rows have to stay readable over it.
class ArtistBackdrop extends StatefulWidget {
  final String name;
  final Uint8List? fallbackImage;
  final Widget child;
  const ArtistBackdrop({super.key, required this.name, this.fallbackImage, required this.child});

  @override
  State<ArtistBackdrop> createState() => _ArtistBackdropState();
}

class _ArtistBackdropState extends State<ArtistBackdrop> {
  ArtistArt? _art;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ArtistBackdrop old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name) {
      setState(() => _art = null);
      _load();
    }
  }

  Uint8List? _chosenBackdrop;
  String? _loadedUrl;

  Future<void> _load() async {
    final name = widget.name;
    final settings = context.read<AppSettings>();
    final art = await CoverEnricher(settings).artistArt(name);
    if (!mounted || name != widget.name) return;
    setState(() => _art = art);
    // A picture the user picked outranks anything the shape heuristic chose. Fetched here rather
    // than stored as bytes, so the choice survives independently of any cache being cleared.
    final lib = context.read<LibraryStore>();
    for (final kind in const ['backdrop']) {
      final url = lib.chosenArtistArt(name, kind);
      if (url == null) continue;
      final bytes = await CoverEnricher(settings).downloadImage(url);
      if (!mounted || name != widget.name || bytes == null) continue;
      if (kind == 'backdrop') setState(() => _chosenBackdrop = bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Same as the hero: a fresh pick has to show without leaving the page and coming back.
    final chosen = context.watch<LibraryStore>().chosenArtistArt(widget.name, 'backdrop');
    if (chosen != _loadedUrl) {
      _loadedUrl = chosen;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    final img = _chosenBackdrop ?? _art?.backdropBytes ?? _art?.thumbBytes ?? widget.fallbackImage;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (img != null)
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              // Overscanned, or the blur samples past the image and the edges fade to nothing.
              child: Transform.scale(
                scale: 1.25,
                child: Image.memory(img,
                    fit: BoxFit.cover, alignment: Alignment.topCenter, errorBuilder: (_, __, ___) => const SizedBox()),
              ),
            ),
          ),
        // The hero fills roughly the top third of a WINDOW, and the scrim was drawn for that: dark
        // from 58% down. Stacked on a phone the hero reaches nearly half the page, so those same
        // stops closed the wash in right across the artist's own colours and left a flat grey
        // rectangle — the backdrop was there, you simply could not see it. On a phone it stays
        // light further down and closes below the buttons instead.
        Builder(builder: (context) {
          final narrow = isCompact(context);
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: narrow ? .18 : .26),
                  Colors.black.withValues(alpha: narrow ? .26 : .40),
                  const Color(0xFF0B0D14).withValues(alpha: .86),
                  const Color(0xFF0B0D14).withValues(alpha: .92),
                ],
                stops: narrow ? const [0, .42, .78, 1] : const [0, .30, .58, 1],
              ),
            ),
          );
        }),
        widget.child,
      ],
    );
  }
}

class ArtistHero extends StatefulWidget {
  final String name;
  final String? subtitle;
  final Uint8List? fallbackImage;
  final List<Widget> actions;

  /// False when an [ArtistBackdrop] is already washing the whole page — the hero then contributes
  /// only the portrait and the wordmark, and doesn't paint a second, differently-cropped copy.
  final bool ownBackdrop;
  const ArtistHero({
    super.key,
    required this.name,
    this.subtitle,
    this.fallbackImage,
    this.actions = const [],
    this.ownBackdrop = true,
  });

  @override
  State<ArtistHero> createState() => _ArtistHeroState();
}

class _ArtistHeroState extends State<ArtistHero> {
  ArtistArt? _art;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ArtistHero old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name) {
      setState(() => _art = null);
      _load();
    }
  }

  /// The URLs this hero last fetched, so a fresh pick can be spotted while the page stays open.
  String? _loadedPortraitUrl, _loadedBackdropUrl;

  /// Re-fetch when the user picks a different photo. Without this the choice was saved and simply
  /// not shown until you left the page and came back — a setting that appears to do nothing.
  void _syncChoice() {
    final lib = context.watch<LibraryStore>();
    final p = lib.chosenArtistArt(widget.name, 'portrait');
    final b = lib.chosenArtistArt(widget.name, 'backdrop');
    if (p == _loadedPortraitUrl && b == _loadedBackdropUrl) return;
    _loadedPortraitUrl = p;
    _loadedBackdropUrl = b;
    // After this frame: build must not kick off a setState of its own.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final name = widget.name;
    final settings = context.read<AppSettings>();
    final art = await CoverEnricher(settings).artistArt(name);
    if (!mounted || name != widget.name) return;
    setState(() => _art = art);
    // Same as the page backdrop: a picture the user picked outranks the shape heuristic.
    final lib = context.read<LibraryStore>();
    for (final kind in const ['portrait', 'backdrop']) {
      final url = lib.chosenArtistArt(name, kind);
      if (url == null) continue;
      final bytes = await CoverEnricher(settings).downloadImage(url);
      if (!mounted || name != widget.name || bytes == null) continue;
      setState(() => kind == 'portrait' ? _chosenPortrait = bytes : _chosenBackdrop = bytes);
    }
  }

  Uint8List? _chosenPortrait, _chosenBackdrop;

  @override
  Widget build(BuildContext context) {
    _syncChoice();
    final logo = _art?.logoBytes;
    final portrait = _chosenPortrait ?? _art?.thumbBytes ?? widget.fallbackImage;
    final backdrop = _chosenBackdrop ?? _art?.backdropBytes ?? widget.fallbackImage;

    final narrow = isCompact(context);
    final pad = narrow ? 18.0 : 28.0;
    // Beside the wordmark a square is right: it is a slot, and the face goes in the middle of it.
    //
    // Stacked, a square is what was cutting the photo in half. This file's own comment two hundred
    // lines up says it: every artist image any database has is 16:9. Cropping one into a square
    // throws away nearly half its width, and for a group photo — five people standing in a row —
    // that is the two on the outside. Full width and a shallower frame, with the picture set
    // INSIDE it whole on a blurred blow-up of itself, so a 16:9 press shot and a squarer portrait
    // both arrive complete.
    final photoW = narrow ? (MediaQuery.sizeOf(context).width - pad * 2) : 270.0;
    final photoH = narrow ? photoW * .70 : 270.0;
    // Wide enough for the wordmark to sit beside the portrait, so a fixed 400 fits it. Stacked, it
    // does not: everything below the photo — wordmark, count, two buttons — was being squeezed into
    // what a number chosen for a different layout left over.
    final heroHeight = narrow ? photoH + 208 : 400.0;

    return SizedBox(
      // Room for a 270px portrait with the wordmark and buttons beside it. The backdrop is very
      // wide, so every extra pixel of height is another band of it that isn't cropped away.
      height: heroHeight,
      // A blur paints outside its child's bounds, and the overscan pushes it further still — without
      // this the wash ran on down the page and the biography underneath was hard to read.
      child: ClipRect(
        child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred on purpose. Every artist image any database has is 16:9 — fanart, widethumb,
          // all of it — and a banner this wide can only show a quarter of one. Sharp, that quarter
          // was a gamble: it framed Michael Jackson but gave Stromae a band of forehead, because his
          // photo is a close-up that no crop can survive. So the backdrop is atmosphere drawn from
          // the artist's own colours, and the portrait beside it is what you actually recognise.
          if (backdrop != null && widget.ownBackdrop)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
              // Overscanned: a blur samples past the edges, and at 1.0 the sides faded out.
              child: Transform.scale(
                scale: 1.15,
                child: Image.memory(backdrop,
                    fit: BoxFit.cover,
                    alignment: const Alignment(0, -.3),
                    errorBuilder: (_, __, ___) => const SizedBox()),
              ),
            ),
          // Dark enough at the bottom that the wordmark and buttons always read. Skipped when the
          // page already carries the wash — a second gradient on top of it just muddies the top.
          if (widget.ownBackdrop)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: .30),
                    Colors.black.withValues(alpha: .38),
                    Colors.black.withValues(alpha: .82),
                    const Color(0xFF0B0D14),
                  ],
                  stops: const [0, .40, .82, 1],
                ),
              ),
            ),
          Builder(builder: (context) {
            final photo = portrait == null
                ? null
                : DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      // Lifts it off a backdrop that is, by design, the same photo's colours.
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .55), blurRadius: 28, offset: const Offset(0, 10))],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: photoW,
                        height: photoH,
                        child: narrow
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  ImageFiltered(
                                    imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                                    child: Image.memory(portrait,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const SizedBox()),
                                  ),
                                  DecoratedBox(
                                      decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: .3))),
                                  Image.memory(portrait,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const SizedBox()),
                                ],
                              )
                            : Image.memory(portrait,
                                fit: BoxFit.cover,
                                alignment: const Alignment(0, -.25),
                                errorBuilder: (_, __, ___) => const SizedBox()),
                      ),
                    ),
                  );

            final details = Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    // Beside the portrait everything hangs off the same left edge. Under it, that
                    // same left edge leaves the whole right half of a phone empty and the page
                    // looks broken rather than composed.
                    crossAxisAlignment:
                        narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                    children: [
                      if (logo != null)
                        ConstrainedBox(
                          // A wordmark is decoration; on a phone it must not cost more height than
                          // the name it replaces.
                          constraints: BoxConstraints(maxHeight: narrow ? 62 : 96, maxWidth: 460),
                          child: Image.memory(logo,
                              fit: BoxFit.contain,
                              alignment: narrow ? Alignment.center : Alignment.centerLeft,
                              errorBuilder: (_, __, ___) => _plainName(narrow)),
                        )
                      else
                        _plainName(narrow),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 8),
                        Text(widget.subtitle!,
                            textAlign: narrow ? TextAlign.center : TextAlign.start,
                            style: const TextStyle(color: Color(0xFFC7CBDA), fontSize: 13.5)),
                      ],
                      if (widget.actions.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment:
                              narrow ? MainAxisAlignment.center : MainAxisAlignment.start,
                          children: widget.actions,
                        ),
                      ],
                    ],
                  );

            return Padding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 22),
              child: narrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // The photo used to start where the title bar stopped, edge to edge, so it
                        // read as a banner that had been cut off rather than as a picture.
                        const SizedBox(height: 14),
                        if (photo != null) ...[photo, const SizedBox(height: 16)],
                        details,
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // The portrait is what makes this a page about a PERSON. A wide backdrop
                        // cropped to a banner shows a horizontal slice, and whether the face is in
                        // it is luck.
                        if (photo != null) ...[photo, const SizedBox(width: 26)],
                        Expanded(child: details),
                      ],
                    ),
            );
          }),
        ],
        ),
      ),
    );
  }

  /// Tighter tracking the bigger it gets — letters read as further apart the larger they are, so
  /// a single letter-spacing value is wrong at one of the two sizes.
  Widget _plainName(bool narrow) => Text(widget.name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: narrow ? TextAlign.center : TextAlign.start,
      style: TextStyle(
          fontSize: narrow ? 27 : 34,
          fontWeight: FontWeight.w800,
          height: 1.1,
          letterSpacing: narrow ? -.3 : -.5));
}

/// What this release IS: the official blurb plus year, genre, label and rating — the album
/// equivalent of a film's synopsis panel. Silent when nothing is known, so a page never shows
/// an empty box.
class AlbumInfoPanel extends StatefulWidget {
  final String artist, album;

  /// How many tracks the library holds for this album — used to reject a Discogs pressing that
  /// is really a single or a sampler filed under the same master.
  final int trackCount;

  /// The Discogs release the user pinned to this album, if any.
  final int? pinned;

  /// Or the MusicBrainz one, when they pinned there instead.
  final String? pinnedMbid;

  /// Images the user assigned by hand — the back cover shown here is one of them.
  final Map<String, String> roles;
  const AlbumInfoPanel(
      {super.key,
      required this.artist,
      required this.album,
      this.trackCount = 0,
      this.pinned,
      this.pinnedMbid,
      this.roles = const {}});

  @override
  State<AlbumInfoPanel> createState() => _AlbumInfoPanelState();
}

class _AlbumInfoPanelState extends State<AlbumInfoPanel> {
  AlbumInfo? _info;
  DiscogsEdition? _edition;
  Uint8List? _back;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AlbumInfoPanel old) {
    super.didUpdateWidget(old);
    // The PIN counts as a change too. Without it, picking a different release of the same record
    // changed nothing here: the name stays "Adele – 30", so this saw no difference and never
    // refetched. The front cover did change, because that comes down a different path entirely —
    // which is exactly what it looked like from the outside.
    if (old.artist != widget.artist ||
        old.album != widget.album ||
        old.pinned != widget.pinned ||
        old.pinnedMbid != widget.pinnedMbid ||
        !mapEquals(old.roles, widget.roles)) {
      // Not cleared first: the year, label and catalogue number of the pressing you just left are
      // a better thing to look at for one network round trip than an empty panel that collapses
      // the page and pushes the tracklist up under your cursor.
      _load();
    }
  }

  /// Which load is current — see the same field on [_AlbumArtState].
  int _gen = 0;

  Future<void> _load() async {
    final artist = widget.artist, album = widget.album;
    final mine = ++_gen;
    final settings = context.read<AppSettings>();
    // The blurb comes from TheAudioDB, which is the only one of the two that writes one. Discogs
    // knows what the record IS: which pressing, on whose label, under what catalogue number.
    final info = await CoverEnricher(settings).albumInfo(artist, album);
    if (!mounted || mine != _gen || artist != widget.artist || album != widget.album) return;
    if (info != null) setState(() => _info = info);
    final discogs = DiscogsService(settings);
    final ed =
        await discogs.edition(artist, album, expectedTracks: widget.trackCount, pinned: widget.pinned).catchError((_) => null);
    if (!mounted || mine != _gen || artist != widget.artist || album != widget.album) return;
    if (ed != null) setState(() => _edition = ed);
    // Remember what this record sounds like. The map fills in as albums are opened, which is what
    // makes browsing by style possible without sweeping the whole library up front.
    if (ed != null && mounted) {
      unawaited(context.read<LibraryStore>().rememberStyles(artist, album, [...ed.genres, ...ed.styles]));
    }
    // The scans come off the same cached edition, so this costs nothing beyond the images.
    final art = await discogs
        .releaseArt(artist, album,
            expectedTracks: widget.trackCount,
            pinned: widget.pinned,
            pinnedMbid: widget.pinnedMbid,
            roles: widget.roles)
        .catchError((_) => null);
    if (!mounted || mine != _gen || artist != widget.artist || album != widget.album) return;
    if (art?.back != null) setState(() => _back = art!.back);
  }

  /// "CD" reads oddly next to a year; "File" reads as nothing at all.
  static String _formatLabel(String f) => switch (f.toLowerCase()) {
        'file' => 'digitaal',
        'vinyl' => 'vinyl',
        'cd' => 'cd',
        'cdr' => 'cd-r',
        'cassette' => 'cassette',
        _ => f.toLowerCase(),
      };

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final ed = _edition;
    if (info == null && ed == null) return const SizedBox.shrink();
    // Discogs describes one specific pressing, so where the two disagree its year and label are
    // the ones that belong to the record in front of you.
    final genres = <String>{...ed?.genres ?? const [], ...ed?.styles ?? const []};
    if (genres.isEmpty) {
      if (info?.genre != null) genres.add(info!.genre!);
      if (info?.style != null) genres.add(info!.style!);
    }
    // The RECORD's year leads, not the pressing's: Demon Days is a 2005 album, even when the copy
    // being described is the 2014 digital reissue.
    final year = ed?.albumYear ?? ed?.year ?? info?.year;
    final facts = <String>[
      if (year != null) '$year',
      ...genres.take(4),
      if ((ed?.label ?? info?.label) != null) (ed?.label ?? info?.label)!,
    ];
    // The pressing itself, kept apart from the genre soup: this is the line that says WHICH copy
    // of the record the page is describing.
    final pressing = <String>[
      if (ed != null && ed.format.isNotEmpty) _formatLabel(ed.format),
      // Only when it differs from the album's own year — otherwise it just repeats the line above.
      if (ed?.year != null && ed!.year != year) '${ed.year}',
      if (ed?.catno != null && ed!.catno!.isNotEmpty && ed.catno!.toLowerCase() != 'none') ed.catno!,
      if (ed?.country != null && ed!.country!.isNotEmpty) ed.country!,
    ];
    final text = info?.text;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
      // Capped: on a maximised window the blurb would otherwise run the full 1400px, and a line
      // that long is genuinely hard to read back to the next line.
      //
      // Align first, and that is not decoration: a list hands its children a TIGHT width, and a
      // bare ConstrainedBox cannot shrink below a tight constraint — the cap silently did nothing
      // until this was added. Align loosens the constraint so the cap can take effect.
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (info?.score != null) ...[
                const Icon(Icons.star_rounded, size: 16, color: Color(0xFFE0B341)),
                const SizedBox(width: 4),
                Text(info!.score!.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(width: 12),
              ],
              Flexible(
                // Every style is a door. Clicking "Synth-pop" is the difference between a label on
                // a page and a way into the rest of the music that sounds like this.
                child: Wrap(spacing: 5, runSpacing: 2, children: [
                  for (var i = 0; i < facts.length; i++) ...[
                    if (i > 0) const Text('·', style: TextStyle(color: _muted, fontSize: 12.5)),
                    if (genres.contains(facts[i]))
                      InkWell(
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => StylePage(facts[i]))),
                        borderRadius: BorderRadius.circular(4),
                        child: Text(facts[i],
                            style: const TextStyle(color: _accent2, fontSize: 12.5)),
                      )
                    else
                      Text(facts[i], style: const TextStyle(color: _muted, fontSize: 12.5)),
                  ],
                ]),
              ),
            ],
          ),
          if (pressing.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.album_outlined, size: 13, color: _muted),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                    // Named, so it is always plain whether the page is describing the release YOU
                    // chose or the one the app picked for itself.
                    '${widget.pinned != null ? "Jouw uitgave" : "Uitgave"}: ${pressing.join(' · ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12)),
              ),
            ]),
          ],
          // The back of the sleeve, next to the line describing the pressing it belongs to. Click
          // to see it full size — the track list and the small print are the reason to look.
          if (_back != null) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding: const EdgeInsets.all(40),
                  child: InteractiveViewer(child: Image.memory(_back!)),
                ),
              ),
              borderRadius: BorderRadius.circular(6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(_back!, height: 116, fit: BoxFit.contain),
              ),
            ),
          ],
          if (text != null && text.isNotEmpty) ...[
            const SizedBox(height: 8),
            BioText('${widget.artist} — ${widget.album}', text),
          ],
        ],
        ),
        ),
      ),
    );
  }
}

// ── Stremio-style online browse: artist → albums → tracks → sources ──────────
class ArtistBrowsePage extends StatefulWidget {
  final CatalogArtist artist;
  const ArtistBrowsePage(this.artist, {super.key});
  @override
  State<ArtistBrowsePage> createState() => _ArtistBrowsePageState();
}

class _ArtistBrowsePageState extends State<ArtistBrowsePage> {
  final _catalog = CatalogService();
  List<CatalogAlbum> _albums = [];
  String? _bio;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
    _loadBio();
  }

  Future<void> _load() async {
    final ref = widget.artist.ref;
    try {
      // A MusicBrainz artist has no Deezer id, so asking Deezer for album id 0 returns nothing —
      // and this page draws an empty grid with no empty state, so it looks like a working page for
      // an artist with no records. It also has the better answer: MusicBrainz carries the regional
      // oddities and the compilations a streaming catalogue has never listed.
      if (ref.isMb) {
        final groups = await context.read<MusicBrainzService>().discographyOf(ref.id);
        if (!mounted) return;
        setState(() {
          _albums = [
            for (final g in groups)
              CatalogAlbum(0, g.title, null, g.firstDate, 0,
                  g.primaryType.toLowerCase().isEmpty ? 'album' : g.primaryType.toLowerCase(),
                  origin: CatalogRef.musicbrainzGroup(g.mbid))
          ];
          _busy = false;
        });
        return;
      }
      final a = await _catalog.artistAlbums(widget.artist.id);
      if (mounted) setState(() { _albums = a; _busy = false; });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadBio() async {
    final enricher = CoverEnricher(context.read<AppSettings>());
    var bio = await enricher.cachedBio(widget.artist.name);
    bio ??= await enricher.fetchArtistBio(widget.artist.name);
    if (mounted && bio != null) setState(() => _bio = bio);
  }

  @override
  Widget build(BuildContext context) {
    // The records of this artist you actually hold. Matched on the normalised artist name, the same
    // key the library groups by, so a stray capital or accent doesn't hide your own albums.
    final lib = context.watch<LibraryStore>();
    final mine = lib.albums
        .where((a) => artistKey(a.artist) == artistKey(widget.artist.name))
        .toList()
      ..sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
    final owned = {for (final a in mine) normKey(a.title)};

    return Scaffold(
      backgroundColor: _bg,
      body: ArtistBackdrop(
        name: widget.artist.name,
        // Same as the album browse page: this draws its own hero rather than an AppBar, so the
        // status bar had nothing keeping it clear. The backdrop stays behind it — only the
        // content is inset.
        child: SafeArea(
        bottom: false,
        child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                ArtistHero(
                  name: widget.artist.name,
                  ownBackdrop: false,
                  subtitle: _busy
                      ? 'Albums laden…'
                      : [
                          if (mine.isNotEmpty) '${mine.length} in je bibliotheek',
                          '${_albums.length} albums',
                        ].join(' · '),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 0, 0),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
          if (_bio != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: BioText(widget.artist.name, _bio!),
              ),
            ),
          // What you already own by this artist, first. Reaching an artist from an album used to
          // show only the online discography, so the records sitting on your own disk were the one
          // thing this page would not tell you about.
          if (mine.isNotEmpty) ...[
            SliverToBoxAdapter(child: _sectionTitle('In mijn bibliotheek', '${mine.length}')),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: .74),
                delegate:
                    SliverChildBuilderDelegate((_, i) => AlbumCard(album: mine[i]), childCount: mine.length),
              ),
            ),
          ],
          if (_busy)
            const SliverToBoxAdapter(
                child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: _accent))))
          else ...[
            SliverToBoxAdapter(
                child: _sectionTitle(
                    mine.isEmpty ? 'Discografie' : 'Volledige discografie', '${_albums.length}')),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: .74),
                delegate: SliverChildBuilderDelegate(
                    (_, i) => _albumCard(_albums[i], owned.contains(normKey(_albums[i].title))),
                    childCount: _albums.length),
              ),
            ),
          ],
        ],
        ),
        ),
      ),
    );
  }

  Widget _albumCard(CatalogAlbum al, [bool owned = false]) {
    final sub = [
      if (al.year != null) al.year!,
      if (al.isSingle) 'Single' else if (al.trackCount > 0) '${al.trackCount} nummers',
    ].join(' · ');
    return InkWell(
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AlbumBrowsePage(widget.artist.name, al))),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (_, c) => Stack(children: [
                _netCover(al.cover, size: c.maxWidth),
                // Which of the discography you already hold — so the gap in the collection is the
                // thing you can see, rather than something to work out by comparing two lists.
                if (owned)
                  Positioned(
                    right: 5,
                    top: 5,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: _bg.withValues(alpha: .72),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_circle_rounded, size: 15, color: _accent2),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Text(al.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String count) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
        child: Row(children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Text(count, style: const TextStyle(color: _muted, fontSize: 13)),
        ]),
      );
}

class AlbumBrowsePage extends StatefulWidget {
  final String artistName;
  final CatalogAlbum album;
  const AlbumBrowsePage(this.artistName, this.album, {super.key});
  @override
  State<AlbumBrowsePage> createState() => _AlbumBrowsePageState();
}

class _AlbumBrowsePageState extends State<AlbumBrowsePage> {
  static const _albumLevel = -1;
  final _catalog = CatalogService();
  List<CatalogTrack> _tracks = [];
  bool _busy = true;
  int? _expanded; // track index whose sources are shown; -1 = whole album

  // Soulseek sources for the WHOLE album, pre-loaded in the background with ONE search when the
  // page opens — so tapping a track's download button is instant (no per-track search). Kept to
  // one search per album-open on purpose (never a per-track burst) so we don't trip the login block.
  List<SoulseekFile> _albumSlsk = [];
  bool _slskBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _preloadSoulseek());
  }

  Future<void> _load() async {
    // Where this album came from decides who can describe it. The sign of the id used to say, and
    // it had run out of values — it also meant two different things at once, since a negative id
    // was a Discogs RELEASE from search but a Discogs MASTER from a style page. Feeding a master
    // to the release endpoint is why an album opened from a style page had no tracklist at all.
    final ref = widget.album.ref;
    switch (ref.source) {
      case CatalogSource.musicbrainz:
        await _loadMusicBrainzRelease(ref.id);
        return;
      case CatalogSource.musicbrainzGroup:
        await _loadMusicBrainzGroup(ref.id);
        return;
      case CatalogSource.discogsRelease:
        await _loadDiscogsRelease(ref.intId);
        return;
      case CatalogSource.discogsMaster:
        await _loadDiscogsMaster(ref.intId);
        return;
      case CatalogSource.deezer:
        break;
    }
    try {
      final (_, tracks) = await _catalog.albumTracks(widget.album.id);
      if (mounted) setState(() { _tracks = tracks; _busy = false; });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
    await _preferOfficialTracklist();
  }

  /// A record, not a pressing — so resolve its best pressing first. Only a pressing has a
  /// tracklist, and this is the single easiest way to ship a page that loads nothing.
  Future<void> _loadMusicBrainzGroup(String groupMbid) async {
    try {
      final mb = context.read<MusicBrainzService>();
      final editions = MusicBrainzService.orderByPreference(await mb.editionsOf(groupMbid));
      if (editions.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      await _loadMusicBrainzRelease(editions.first.mbid);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadMusicBrainzRelease(String mbid) async {
    try {
      final e = await context.read<MusicBrainzService>().release(mbid);
      if (!mounted) return;
      setState(() {
        _tracks = [
          for (var i = 0; i < (e?.tracks.length ?? 0); i++)
            CatalogTrack(
              // No Deezer id exists for these; the index keys the row and Soulseek is searched by
              // name anyway, which is all this page does with it.
              -(i + 1),
              e!.tracks[i].title,
              widget.artistName,
              e.tracks[i].seconds ?? 0,
              i + 1,
            )
        ];
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A Discogs MASTER groups every pressing of a record and has no tracklist of its own; the style
  /// page hands these out, and they were being read as releases.
  Future<void> _loadDiscogsMaster(int masterId) async {
    try {
      final dg = DiscogsService(context.read<AppSettings>());
      final versions = DiscogsService.orderByPreference(await dg.versionsOf(masterId));
      if (versions.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      await _loadDiscogsRelease(versions.first.id);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadDiscogsRelease(int releaseId) async {
    try {
      final e = await DiscogsService(context.read<AppSettings>()).release(releaseId);
      if (!mounted) return;
      setState(() {
        _tracks = [
          for (var i = 0; i < (e?.tracklist.length ?? 0); i++)
            CatalogTrack(
              // No Deezer id exists for these; the index is enough to key a row and to search
              // Soulseek with, which is all this page does with it.
              -(i + 1),
              e!.tracklist[i].title,
              widget.artistName,
              e.tracklist[i].seconds ?? 0,
              i + 1,
            )
        ];
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Replace Deezer's tracklist with the one from the pressing itself.
  ///
  /// Deezer catalogues the streaming edition, and it names tracks after whichever recording it
  /// licensed: on *Off the Wall* it lists "Rock with You (Single Version)", while the record simply
  /// has "Rock with You". Discogs describes an actual pressing, so its tracklist is the album's.
  ///
  /// Only swapped when the two agree about the SHAPE of the record — same number of tracks. A
  /// different count means a different edition, and renaming your tracks from the wrong one would
  /// be worse than leaving Deezer's names alone.
  Future<void> _preferOfficialTracklist() async {
    if (_tracks.isEmpty || !mounted) return;
    // MusicBrainz first, Discogs as the supplement. MusicBrainz needs no token, so for anyone who
    // has not entered a Discogs one this stops being a guaranteed no-op.
    var titles = <String>[], secs = <int>[];
    // Both read before the first await: after one, this widget may be gone and its context with it.
    final mb = context.read<MusicBrainzService>();
    final settings = context.read<AppSettings>();
    try {
      final hits = await mb.searchReleases(
          widget.artistName, DiscogsService.plainTitle(widget.album.title),
          expectedTracks: _tracks.length);
      if (hits.isNotEmpty) {
        final full = await mb.release(hits.first.mbid);
        final ts = full?.tracks ?? const <MbTrack>[];
        if (ts.length == _tracks.length) {
          titles = [for (final t in ts) t.title];
          secs = [for (final t in ts) t.seconds ?? 0];
          // When the RECORD came out, not when this pressing did — a 2009 reissue of a 1996 album
          // is still a 1996 album. Kept because a download has to be stamped with it, and the
          // search hit this page was opened from carries no date at all.
          _officialYear = full?.albumYear ?? full?.year;
        }
      }
    } catch (_) {/* fall through to Discogs */}

    if (titles.isEmpty) {
      try {
        final e = await DiscogsService(settings)
            .edition(widget.artistName, widget.album.title, expectedTracks: _tracks.length);
        final dg = e?.tracklist ?? const <DiscogsTrack>[];
        if (dg.length == _tracks.length) {
          titles = [for (final t in dg) t.title];
          secs = [for (final t in dg) t.seconds ?? 0];
          _officialYear = e?.albumYear ?? e?.year;
        }
      } catch (_) {/* the Deezer list is a fine fallback */}
    }
    if (!mounted || titles.length != _tracks.length) return;

    // Index-aligned, so a pressing that agrees on the COUNT but not the order would rename every
    // track after the first difference. The running times are the check that they are the same
    // record in the same order; a couple of disagreements is normal, wholesale is not.
    var wrong = 0;
    for (var i = 0; i < titles.length; i++) {
      final a = _tracks[i].durationSec, b = secs[i];
      if (a > 0 && b > 0 && (a - b).abs() > 15) wrong++;
    }
    if (wrong > titles.length / 3) return;

    setState(() {
      _tracks = [
        for (var i = 0; i < _tracks.length; i++)
          CatalogTrack(
            _tracks[i].id,
            titles[i].isEmpty ? _tracks[i].title : titles[i],
            _tracks[i].artist,
            // Keep Deezer's running time when the pressing doesn't state one.
            secs[i] > 0 ? secs[i] : _tracks[i].durationSec,
            _tracks[i].position,
          )
      ];
    });
  }

  Future<void> _preloadSoulseek() async {
    if (!mounted) return;
    final soulseek = context.read<SoulseekService>();
    if (!soulseek.available) return;
    setState(() => _slskBusy = true);
    try {
      final r = await soulseek.search('${widget.artistName} ${widget.album.title}', onPartial: (p) {
        if (mounted) setState(() => _albumSlsk = p);
      });
      if (mounted) setState(() { _albumSlsk = r; _slskBusy = false; });
    } catch (_) {
      if (mounted) setState(() => _slskBusy = false);
    }
  }

  /// Pre-loaded Soulseek copies of one track. Empty if the album-wide search didn't cover it.
  /// Deezer's running time is passed along because the title alone can't tell a track from a
  /// medley that contains it, nor from a remix of about the same length.
  List<SoulseekFile> _slskForTitle(CatalogTrack t) => _albumSlsk
      .where((f) => f.isAudio && fileOffersTitle(t.title, t.durationSec, widget.artistName, f.filename, f.durationSec))
      .toList();

  /// The copy of this track already in the library (null if we don't have it). Version markers
  /// are part of the identity, so a Live/Radio-Edit/compilation cut still counts as NOT owned.
  Track? _owned(CatalogTrack t) => context.read<LibraryStore>().ownedTrack(widget.artistName, t.title);

  /// What year the RECORD is from, according to whichever catalogue described it.
  ///
  /// Not from widget.album: a search hit carries no release date, so leaving it out meant DATE was
  /// never written and each downloaded file kept whatever year its uploader had put in — one album
  /// came out of three peers stamped 1996, 1998 and 1999.
  int? _officialYear;

  /// This album, as the official release the sources should be judged against.
  ///
  /// The tracklist here has already been through [_preferOfficialTracklist], so it is MusicBrainz's
  /// or Discogs's idea of the record rather than a streaming catalogue's — and emphatically rather
  /// than a Soulseek uploader's.
  ReleaseAuthority get _release => ReleaseAuthority(
        artist: widget.artistName,
        album: widget.album.title,
        albumArtist: widget.artistName,
        year: _officialYear ?? int.tryParse(widget.album.year ?? ''),
        tracks: [
          for (var i = 0; i < _tracks.length; i++)
            ChoiceTrack('${_numberOf(_tracks[i], i)}', _tracks[i].title, _tracks[i].durationSec)
        ],
      );

  /// This track's number on the record.
  ///
  /// Deezer's album endpoint does not return `track_position` at all — it only exists on the
  /// per-track endpoint — so every position here is 0 and the numbers on screen are really just row
  /// indexes. Taking `position` at face value filed a download as "We've Got It Goin' On.flac"
  /// with no number in front of it. The list is in release order either way, so the index IS the
  /// number whenever the catalogue declines to say.
  int _numberOf(CatalogTrack t, int i) => t.position > 0 ? t.position : i + 1;

  /// What this track IS, from the page the user is looking at.
  ///
  /// This tracklist has already been through _preferOfficialTracklist, so its titles and order come
  /// from MusicBrainz or Discogs rather than from a streaming catalogue — and certainly rather than
  /// from whichever peer serves the file. Soulseek offers this same song as "13 Anywhere for You",
  /// "19. Backstreet Boys - Anywhere For You" and "…The Essential Backstreet Boys - 01 - …";
  /// downloading any of them must still produce track 2 of this album.
  TrackTags _authorityFor(CatalogTrack t, int i) => TrackTags(
        title: t.title,
        artist: widget.artistName,
        album: widget.album.title,
        albumArtist: widget.artistName,
        trackNo: _numberOf(t, i),
        trackTotal: _tracks.length,
        year: _officialYear ?? int.tryParse(widget.album.year ?? ''),
      );

  /// Every peer copy of this track worth trying — the preload's, plus a fresh targeted search.
  ///
  /// The album-wide preload often lists a track's copies only from peers that are now offline, so
  /// a download built on it alone can report "no source" while a live copy plainly exists. A search
  /// aimed at this one track finds those live peers. Both sets are filtered to this exact title and
  /// running time, so the pool can never fill with a different song from the same user — which is
  /// what happened when the old path took every audio result the search returned and, after the
  /// query broadened to just the artist, would have downloaded the wrong song under this one's tags.
  Future<List<SoulseekFile>> _slskCandidatesForTrack(CatalogTrack t) async {
    final soulseek = context.read<SoulseekService>();
    final pool = <String, SoulseekFile>{
      for (final f in _slskForTitle(t)) '${f.username}|${f.filename}': f
    };
    try {
      final r = await soulseek.search(soulseekQuery(widget.artistName, t.title));
      for (final f in r) {
        if (!f.isAudio) continue;
        if (!fileOffersTitle(t.title, t.durationSec, widget.artistName, f.filename, f.durationSec)) {
          continue;
        }
        pool.putIfAbsent('${f.username}|${f.filename}', () => f);
      }
    } catch (_) {/* the preload's copies are still worth a try on their own */}
    return pool.values.toList();
  }

  Future<void> _downloadTrack(CatalogTrack t, int i) async {
    final dm = context.read<DownloadManager>();
    final soulseek = context.read<SoulseekService>();
    if (_owned(t) != null) {
      _srcToast(context, '“${t.title}” heb je al — niet opnieuw gedownload.');
      return;
    }
    if (!soulseek.available) {
      _srcToast(context, 'Stel je Soulseek-login in (Instellingen).');
      return;
    }
    if (mounted) _srcToast(context, 'Bron zoeken voor “${t.title}”…');
    final cands = await _slskCandidatesForTrack(t);
    if (!mounted) return;
    if (cands.isEmpty) {
      _srcToast(context, 'Geen Soulseek-bron gevonden voor “${t.title}”.');
      return;
    }
    try {
      final started = await dm.enqueueSoulseekBest(cands,
          key: 'alb:${widget.album.ref.keyPart}:$i', authority: _authorityFor(t, i));
      if (mounted) {
        _srcToast(context, started ? '“${t.title}” via Soulseek…' : '“${t.title}” loopt al — zie Mijn downloads.');
      }
    } catch (e) {
      if (mounted) _srcToast(context, 'Download mislukt: $e');
    }
  }

  void _toggle(int i) => setState(() => _expanded = _expanded == i ? null : i);

  @override
  Widget build(BuildContext context) {
    final al = widget.album;
    return Scaffold(
      backgroundColor: _bg,
      // Its own header rather than an AppBar, so nothing was adding the status bar's height —
      // the cover and the title were drawn UNDER the clock and the wifi icons. The album page
      // escaped this only because a SliverAppBar puts that inset in by itself.
      body: SafeArea(
        bottom: false,
        child: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 20, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context)),
                const SizedBox(width: 4),
                _netCover(al.cover, size: 128),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      Text(al.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                          '${widget.artistName}${al.year != null ? " · ${al.year}" : ""}${_tracks.isNotEmpty ? " · ${_tracks.length} nummers" : ""}',
                          style: const TextStyle(color: _muted, fontSize: 13)),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: _panel2, foregroundColor: Colors.white),
                        icon: Icon(_expanded == _albumLevel ? Icons.expand_less_rounded : Icons.travel_explore_rounded, size: 18),
                        label: const Text('Bronnen voor album'),
                        onPressed: () => _toggle(_albumLevel),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_expanded == _albumLevel)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SourcesView(query: '${widget.artistName} ${al.title}', authority: _release),
            ),
          AlbumInfoPanel(artist: widget.artistName, album: al.title),
          CreditsPanel(artist: widget.artistName, album: al.title),
          if (_busy)
            const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: _accent)))
          else if (_tracks.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('Geen tracklijst gevonden.', style: TextStyle(color: _muted)))
          else
            ..._tracks.asMap().entries.map((e) => _trackRow(e.key, e.value)),
        ],
        ),
      ),
    );
  }

  Widget _trackRow(int i, CatalogTrack t) {
    final open = _expanded == i;
    final soulseekReady = context.read<SoulseekService>().available;
    final srcCount = soulseekReady ? _slskForTitle(t).length : 0;
    return Column(
      children: [
        InkWell(
          onTap: () => _toggle(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
            color: open ? _panel : Colors.transparent,
            child: Row(
              children: [
                SizedBox(
                    width: 26,
                    child: Text('${_numberOf(t, i)}',
                        style: const TextStyle(color: _muted, fontSize: 13))),
                // Which tracks of this record you already have — the gap in the album, at a glance.
                Builder(builder: (context) {
                  final have = context.watch<LibraryStore>().ownedTrack(widget.artistName, t.title) != null;
                  return SizedBox(
                    width: 22,
                    child: have
                        ? const Icon(Icons.check_circle_rounded, size: 14, color: _accent2)
                        : const SizedBox.shrink(),
                  );
                }),
                Expanded(
                    child: Text(t.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                // "N bronnen klaar" hint (or a tiny spinner while the album search is still running).
                if (soulseekReady && srcCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text('$srcCount ⌄',
                        style: const TextStyle(color: _accent2, fontSize: 11, fontWeight: FontWeight.w600)),
                  )
                else if (soulseekReady && _slskBusy)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.6, color: _muted)),
                  ),
                Text(t.durationLabel, style: const TextStyle(color: _muted, fontSize: 12)),
                if (_owned(t) != null)
                  const Padding(
                    padding: EdgeInsets.all(9),
                    child: Tooltip(
                      message: 'Al in je bibliotheek',
                      child: Icon(Icons.library_add_check_rounded, color: _accent2, size: 19),
                    ),
                  )
                else if (soulseekReady)
                  _downloadControl(context,
                      jobKey: 'alb:${widget.album.ref.keyPart}:$i',
                      onDownload: () => _downloadTrack(t, i),
                      tooltip: 'Download via Soulseek'),
                const SizedBox(width: 2),
                Icon(open ? Icons.expand_less_rounded : Icons.travel_explore_rounded,
                    size: 18, color: open ? _accent : _muted),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SourcesView(
                query: '${widget.artistName} ${t.title}',
                authority: _release,
                track: ChoiceTrack('${_numberOf(t, i)}', t.title, t.durationSec)),
          ),
      ],
    );
  }
}

// ── Settings dialog ──────────────────────────────────────────────────────────
/// Which build is this, and where is it running from?
///
/// Read from the RUNNING executable rather than a constant in the source: a hand-maintained
/// number drifts the moment someone forgets to bump it, and the whole point here is to stop
/// guessing. The install path is shown for the same reason — a second copy left behind
/// elsewhere on disk looks identical until you can see which one you actually opened.
class _AboutSection extends StatefulWidget {
  const _AboutSection();

  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  String _version = '…';
  String _path = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var version = '?';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.buildNumber.isEmpty ? info.version : '${info.version}+${info.buildNumber}';
    } catch (_) {/* fall through to the placeholder */}
    if (!mounted) return;
    setState(() {
      _version = version;
      _path = Platform.resolvedExecutable;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Info', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _accent.withValues(alpha: .35)),
              ),
              child: Text('DebridMusic $_version',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
            const SizedBox(width: 10),
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 15),
              color: _muted,
              tooltip: 'Versie kopiëren',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: 'DebridMusic $_version'));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Versie gekopieerd'), duration: Duration(seconds: 2)),
                );
              },
            ),
          ],
        ),
        if (_path.isNotEmpty) ...[
          const SizedBox(height: 6),
          // Zero-width spaces after each separator: a path has no spaces, so Flutter would
          // otherwise break it after the "C:" and the rest reads as if it started at \Users.
          SelectableText(_path.replaceAll(r'\', '\\\u200B'),
              style: const TextStyle(color: _muted, fontSize: 11, height: 1.35)),
        ],
      ],
    );
  }
}

/// Sharing this library with the Mac, the iPad and the Shield.
///
/// The address and the token are the whole pairing story, so they are shown plainly and can be
/// copied — and offered as a QR code, because typing a 32-character token on a TV remote is not
/// something anyone should be asked to do.
class _SharingSection extends StatefulWidget {
  const _SharingSection();

  @override
  State<_SharingSection> createState() => _SharingSectionState();
}

class _SharingSectionState extends State<_SharingSection> {
  late final TextEditingController _root;
  bool _showToken = false;

  // Signing this PC in to the account. The same two fields as LoginScreen, but a different job: a
  // Mac signs in to FIND the music, this machine signs in to be findable.
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _cloudBusy = false;
  bool _cloudRegister = false;
  String? _cloudError;

  @override
  void initState() {
    super.initState();
    _root = TextEditingController(text: context.read<LibraryStore>().rootPath);
  }

  @override
  void dispose() {
    _root.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Sign in (or register) and start publishing straight away.
  ///
  /// The publish is not left to the next launch: the reason to sign in here is so a Mac or an iPad
  /// can find this PC, and "restart the app first" is not an answer to that.
  Future<void> _cloudSubmit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _cloudError = 'Vul je e-mailadres en wachtwoord in.');
      return;
    }
    setState(() {
      _cloudBusy = true;
      _cloudError = null;
    });
    final cloud = context.read<CloudSession>();
    try {
      if (_cloudRegister) {
        await cloud.register(email, password);
      } else {
        await cloud.signIn(email, password);
      }
      if (!mounted) return;
      await publishAsOwner(cloud, context.read<AppSettings>(), context.read<LanSharing>(),
          context.read<LibraryStore>(), context.read<DownloadManager>());
      if (!mounted) return;
      // Not kept in memory a moment longer than the request needs them.
      _email.clear();
      _password.clear();
      setState(() => _cloudBusy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cloudBusy = false;
        _cloudError = '$e';
      });
    }
  }

  /// This PC's account: signed in, or the form to sign in with.
  Widget _cloudPanel(CloudSession cloud) {
    // A build with no Firebase project configured cannot sign in to anything, and saying so is
    // better than a form that always fails. The pairing code below still works.
    if (cloud.state == CloudState.disabled) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: Text(
          'Deze build heeft geen cloud-project, dus inloggen kan niet. '
          'Je apparaten koppelen met de code hieronder werkt gewoon.',
          style: TextStyle(color: _muted, fontSize: 11.5, height: 1.35),
        ),
      );
    }

    final title = Row(
      children: [
        const Icon(Icons.cloud_outlined, size: 16, color: _muted),
        const SizedBox(width: 6),
        const Text('Account', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        if (cloud.state == CloudState.restoring) ...[
          const SizedBox(width: 8),
          const SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.6)),
        ],
      ],
    );

    if (cloud.isSignedIn) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            const SizedBox(height: 6),
            Text(cloud.user?.email ?? 'Ingelogd',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              cloud.lastError != null
                  ? 'Deze pc kon zich niet aanmelden: ${cloud.lastError}'
                  : 'Deze pc meldt zich aan onder dit account. Log op je Mac, iPad of Shield in met '
                      'hetzelfde account — dan vinden ze hem zonder code.',
              style: TextStyle(
                  color: cloud.lastError != null ? const Color(0xFFFF6B6B) : _muted,
                  fontSize: 11.5,
                  height: 1.35),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final serverId = context.read<AppSettings>().serverId;
                // Tell the account this PC is going away before forgetting the account, or the
                // devices keep seeing a server that will never answer again.
                if (serverId.isNotEmpty) {
                  try {
                    await cloud.goOffline(serverId);
                  } catch (_) {/* signing out matters more than the last word */}
                }
                await cloud.signOut();
              },
              icon: const Icon(Icons.logout_rounded, size: 16),
              label: const Text('Uitloggen'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 4),
          const Text(
            'Log in en je Mac, iPad en Shield vinden deze pc zonder code — ook op een netwerk '
            'dat automatisch zoeken blokkeert. Begin hier: een apparaat kan pas verbinden als '
            'deze pc onder het account bekend is.',
            style: TextStyle(color: _muted, fontSize: 11.5, height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _email,
                  enabled: !_cloudBusy,
                  autofillHints: const [AutofillHints.email],
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mailadres',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _password,
                  enabled: !_cloudBusy,
                  obscureText: true,
                  autofillHints: [_cloudRegister ? AutofillHints.newPassword : AutofillHints.password],
                  onSubmitted: (_) => _cloudBusy ? null : _cloudSubmit(),
                  decoration: const InputDecoration(
                    labelText: 'Wachtwoord',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          if (_cloudError != null) ...[
            const SizedBox(height: 8),
            Text(_cloudError!,
                style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 12, height: 1.35)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _accent),
                onPressed: _cloudBusy ? null : _cloudSubmit,
                child: Text(_cloudBusy
                    ? 'Bezig…'
                    : (_cloudRegister ? 'Account aanmaken' : 'Inloggen')),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _cloudBusy
                    ? null
                    : () => setState(() {
                          _cloudRegister = !_cloudRegister;
                          _cloudError = null;
                        }),
                child: Text(_cloudRegister
                    ? 'Ik heb al een account'
                    : 'Nog geen account? Maak er een'),
              ),
            ],
          ),
          const Divider(height: 26),
        ],
      ),
    );
  }

  void _copy(String value, String what) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what gekopieerd'), duration: const Duration(seconds: 2)),
    );
  }

  /// What this panel says on a device that reads someone else's library: which PC, whether it is
  /// answering, and the way back out.
  Widget _connectedPanel(ClientSession session) {
    final endpoint = session.endpoint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Verbonden met je pc',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.computer_rounded,
                color: session.lastError == null ? _accent2 : Colors.orangeAccent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(session.serverName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                Text(
                  // Deliberately verbatim: a port is a number you type, not one to be shown as
                  // "47.820" by whatever the device's locale thinks a thousands separator is.
                  endpoint == null
                      ? ''
                      : '${endpoint.baseUrl.host}:${endpoint.baseUrl.port} · '
                          '${session.library.tracks.length} nummers',
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ]),
            ),
            TextButton(
              onPressed: () => session.refreshNow(),
              child: const Text('Ververs', style: TextStyle(color: _muted)),
            ),
          ]),
        ),
        if (session.lastError != null) ...[
          const SizedBox(height: 10),
          Text(session.lastError!,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
        ],
        const SizedBox(height: 14),
        Text(
          'Je bibliotheek, je covers en je bewerkingen komen van je pc. Aanpassen doe je daar; '
          'hier zie je het resultaat vanzelf terug.',
          style: TextStyle(color: _muted.withValues(alpha: .85), fontSize: 12, height: 1.45),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () async {
            final yes = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                backgroundColor: _panel,
                title: const Text('Koppeling verbreken?'),
                content: const Text(
                    'Dit apparaat vergeet je pc. Je muziek blijft gewoon op de pc staan.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false), child: const Text('Annuleer')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true), child: const Text('Verbreken')),
                ],
              ),
            );
            if (yes == true) await session.unpair();
          },
          icon: const Icon(Icons.link_off_rounded, size: 18),
          label: const Text('Koppeling verbreken'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sharing = context.watch<LanSharing>();
    final settings = context.read<AppSettings>();
    final session = context.watch<ClientSession>();

    // On a Mac or an iPad this panel is the other way round: this device does not share a library,
    // it reads one. Offering a server switch here would let you turn on a server with nothing
    // behind it.
    if (!session.owner) return _connectedPanel(session);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The account comes first: it is what a device uses to find this PC, and the code below is
        // the fallback for when it cannot.
        _cloudPanel(context.watch<CloudSession>()),
        Row(
          children: [
            const Expanded(
              child: Text('Delen met andere apparaten',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            Switch(
              value: settings.lanEnabled,
              activeThumbColor: _accent,
              onChanged: (on) async {
                settings.lanEnabled = on;
                await settings.save();
                await sharing.applySettings();
              },
            ),
          ],
        ),
        const Text(
          'Zet dit aan en je Mac, iPad en Shield zien dezelfde bibliotheek — '
          'inclusief je eigen covers en persingen.',
          style: TextStyle(color: _muted, fontSize: 11.5, height: 1.35),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Expanded(
              child: Text('Albuminfo vooraf ophalen',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            Switch(
              value: settings.warmFacts,
              activeThumbColor: _accent,
              onChanged: (on) async {
                settings.warmFacts = on;
                await settings.save();
                // The warmer reads the setting before every album, so switching off stops the
                // sweep where it is rather than at the end of the library.
              },
            ),
          ],
        ),
        const Text(
          'Deze pc zoekt van elke plaat de persing en de officiële tracklijst op vóórdat je hem '
          'opent, zodat een album nooit meer laat wachten. Eén keer per plaat, en elk toestel in '
          'huis heeft er wat aan. Hij schrijft bij elk album een klein bestandje in die albummap, '
          'zodat je metadata meeverhuist met je muziek.',
          style: TextStyle(color: _muted, fontSize: 11.5, height: 1.35),
        ),
        if (settings.lanEnabled) ...[
          const SizedBox(height: 10),
          if (sharing.error != null)
            Text(sharing.error!, style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 12))
          else if (!sharing.running)
            const Text('Starten…', style: TextStyle(color: _muted, fontSize: 12))
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Adres', style: TextStyle(color: _muted, fontSize: 11.5)),
                      for (final url in sharing.addresses)
                        InkWell(
                          onTap: () => _copy(url, 'Adres'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(url,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                const SizedBox(width: 6),
                                const Icon(Icons.copy_rounded, size: 13, color: _muted),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      const Text('Toegangscode', style: TextStyle(color: _muted, fontSize: 11.5)),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _showToken ? sharing.token : '•' * 16,
                              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: Icon(_showToken ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                size: 15),
                            color: _muted,
                            tooltip: _showToken ? 'Verbergen' : 'Tonen',
                            onPressed: () => setState(() => _showToken = !_showToken),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 15),
                            color: _muted,
                            tooltip: 'Code kopiëren',
                            onPressed: () => _copy(sharing.token, 'Toegangscode'),
                          ),
                        ],
                      ),
                      Text(
                        sharing.discoverable
                            ? 'Je apparaten vinden deze pc vanzelf.'
                            : 'Automatisch vinden lukt niet — vul het adres hierboven met de hand in.',
                        style: const TextStyle(color: _muted, fontSize: 11, height: 1.35),
                      ),
                    ],
                  ),
                ),
                if (sharing.pairingCode != null) ...[
                  const SizedBox(width: 14),
                  // White backing on purpose: a QR on a dark panel is unreadable to most scanners.
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: QrImageView(
                      data: sharing.pairingCode!,
                      size: 96,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            // Pairing by six digits, because the alternative is typing 32 hex characters on a
            // TV remote with an on-screen keyboard.
            if (sharing.pairingCodeDigits != null)
              Row(
                children: [
                  for (final digit in sharing.pairingCodeDigits!.split(''))
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: _accent.withValues(alpha: .35)),
                      ),
                      child: Text(digit,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: sharing.stopPairing,
                    style: TextButton.styleFrom(
                        foregroundColor: _muted, textStyle: const TextStyle(fontSize: 12)),
                    child: const Text('Klaar'),
                  ),
                ],
              )
            else
              Row(
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: _accent, textStyle: const TextStyle(fontSize: 12.5)),
                    onPressed: sharing.startPairing,
                    icon: const Icon(Icons.add_link_rounded, size: 16),
                    label: const Text('Apparaat koppelen'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () async {
                      final ok = await _confirmRotate();
                      if (ok) await sharing.rotateToken();
                    },
                    icon: const Icon(Icons.autorenew_rounded, size: 15),
                    label: const Text('Nieuwe toegangscode'),
                    style: TextButton.styleFrom(
                        foregroundColor: _muted, textStyle: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            if (sharing.pairingCodeDigits != null)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Typ deze zes cijfers op je Shield of iPad. Vijf minuten geldig.',
                    style: TextStyle(color: _muted, fontSize: 11, height: 1.35)),
              ),
          ],
        ],
        const SizedBox(height: 12),
        const Text('Muziekmap', style: TextStyle(color: _muted, fontSize: 12.5)),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _root,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFF14161F),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(color: _line)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(color: _line)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: const BorderSide(color: _accent)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () async {
                final path = _root.text.trim();
                if (path.isEmpty) return;
                final lib = context.read<LibraryStore>();
                settings.musicRoot = path;
                await settings.save();
                lib.rootPath = path;
                await lib.scan();
              },
              style: TextButton.styleFrom(foregroundColor: _accent),
              child: const Text('Opnieuw scannen'),
            ),
          ],
        ),
      ],
    );
  }

  Future<bool> _confirmRotate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('Nieuwe toegangscode?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text(
          'Je Mac, iPad en Shield verliezen de verbinding en moeten opnieuw gekoppeld worden.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
              autofocus: isTv,
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuleren')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Vervangen'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}

/// Opening the settings: a page on a phone, a dialog in a window.
///
/// One helper rather than a showDialog at each of the three places that offer it — a Scaffold
/// inside a dialog is what you get otherwise, and only on a phone, which is exactly the kind of
/// thing that reaches a build.
Future<void> openSettings(BuildContext context) {
  if (isCompact(context)) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const SettingsDialog(), fullscreenDialog: true),
    );
  }
  return showDialog<void>(context: context, builder: (_) => const SettingsDialog());
}

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});
  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _discogs, _torbox, _slskUser, _slskPass, _lastfm, _rtUser, _rtPass, _slskPort;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppSettings>();
    _discogs = TextEditingController(text: s.discogsToken);
    _torbox = TextEditingController(text: s.torboxToken);
    _slskUser = TextEditingController(text: s.soulseekUser);
    _slskPass = TextEditingController(text: s.soulseekPass);
    _slskPort = TextEditingController(text: s.soulseekPort > 0 ? s.soulseekPort.toString() : "");
    _lastfm = TextEditingController(text: s.lastfmKey);
    _rtUser = TextEditingController(text: s.rutrackerUser);
    _rtPass = TextEditingController(text: s.rutrackerPass);
  }

  bool _testing = false;
  bool _rtBusy = false;
  bool _tidying = false;
  String? _tidyResult;
  final Map<String, ConnResult> _conn = {};

  /// One focus node per field, made on demand by [_field].
  ///
  /// Eight text fields on one screen, and on a television every one of them opens the leanback
  /// keyboard the moment it takes focus — after which the keyboard owns all four arrows and the
  /// only way out is BACK, which closes the settings and discards everything typed. So they are
  /// skipped when arrowing and entered on purpose, and the nodes have to be kept somewhere.
  final _fieldFocus = <TextEditingController, FocusNode>{};

  @override
  void dispose() {
    _discogs.dispose();
    _torbox.dispose();
    _slskUser.dispose();
    _slskPass.dispose();
    _slskPort.dispose();
    _lastfm.dispose();
    _rtUser.dispose();
    _rtPass.dispose();
    for (final n in _fieldFocus.values) {
      n.dispose();
    }
    super.dispose();
  }

  /// Sort the app's download folder into Albums/Singles/Compilaties per artist and drop exact
  /// duplicate tracks (best format/size wins). Never touches the user's own collection.
  Future<void> _tidyDownloads() async {
    final lib = context.read<LibraryStore>();
    setState(() {
      _tidying = true;
      _tidyResult = null;
    });
    try {
      final root = '${lib.rootPath}${Platform.pathSeparator}DebridMusic Downloads';
      final report = await tidyDownloads(root);
      await lib.scan();
      if (mounted) setState(() => _tidyResult = 'Klaar — $report');
    } catch (e) {
      if (mounted) setState(() => _tidyResult = 'Opruimen mislukt: $e');
    } finally {
      if (mounted) setState(() => _tidying = false);
    }
  }

  /// Test the credentials as currently typed (without saving to disk).
  Future<void> _testAll() async {
    final real = context.read<AppSettings>();
    final probe = AppSettings()
      // A throwaway that must never reach the disk. It has never seen the TIDAL tokens, the LAN
      // token, the server id or the music folder, so one save() from anywhere down this path would
      // write those away as empty. Today nothing on this path saves; this is so that stays true.
      ..readOnly = true
      ..torboxToken = _torbox.text.trim()
      ..discogsToken = _discogs.text.trim()
      ..soulseekUser = _slskUser.text.trim()
      ..soulseekPass = _slskPass.text.trim()
      ..soulseekPort = int.tryParse(_slskPort.text.trim()) ?? 0
      ..rutrackerUser = _rtUser.text.trim()
      ..rutrackerPass = _rtPass.text
      ..rutrackerCookie = real.rutrackerCookie; // RuTracker validity depends on the live session
    // Soulseek deliberately uses the app's REAL service, not a probe copy: a probe would have its
    // own client, so testing the connection would open a SECOND login on an account that allows
    // one — kicking the live session and provoking a re-login. It also wouldn't see the app's
    // back-off, so "Test" could keep hammering an account that is already blocked.
    final checker = ConnectionChecker(probe, TorBox(() => probe.torboxToken),
        context.read<SoulseekService>(), RuTrackerService(probe));
    setState(() {
      _testing = true;
      for (final k in ['torbox', 'discogs', 'soulseek', 'rutracker']) {
        _conn[k] = const ConnResult(ConnState.checking);
      }
    });
    Future<void> run(String key, Future<ConnResult> Function() f) async {
      final r = await f();
      if (mounted) setState(() => _conn[key] = r);
    }

    await Future.wait([
      run('torbox', checker.torboxCheck),
      run('discogs', checker.discogsCheck),
      run('soulseek', checker.soulseekCheck),
      run('rutracker', checker.rutrackerCheck),
    ]);
    if (mounted) setState(() => _testing = false);
  }

  /// Log in to RuTracker (persisting the typed creds first), solving a CAPTCHA if asked.
  Future<void> _rtLogin() async {
    final settings = context.read<AppSettings>();
    final rt = context.read<OnlineService>().rutracker;
    settings.rutrackerUser = _rtUser.text.trim();
    settings.rutrackerPass = _rtPass.text;
    await settings.save();
    setState(() {
      _rtBusy = true;
      _conn['rutracker'] = const ConnResult(ConnState.checking);
    });
    try {
      var result = await rt.login();
      while (result.captcha != null && mounted) {
        final answer = await _captchaDialog(result.captcha!);
        if (answer == null || answer.isEmpty) {
          if (mounted) setState(() => _conn['rutracker'] = const ConnResult(ConnState.fail, 'Login geannuleerd'));
          return;
        }
        result = await rt.login(captchaAnswer: answer, captcha: result.captcha);
      }
      if (!mounted) return;
      setState(() => _conn['rutracker'] = result.ok
          ? ConnResult(ConnState.ok, 'Ingelogd als ${settings.rutrackerUser}')
          : ConnResult(ConnState.fail, result.error ?? 'Login mislukt'));
    } finally {
      if (mounted) setState(() => _rtBusy = false);
    }
  }

  Future<String?> _captchaDialog(RtCaptcha cap) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _panel,
        title: const Text('RuTracker CAPTCHA', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Typ de tekens uit de afbeelding over.',
                  style: TextStyle(color: _muted, fontSize: 12.5)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(6),
                color: Colors.white,
                child: Image.network(cap.imageUrl,
                    height: 72,
                    errorBuilder: (_, __, ___) =>
                        const Text('Afbeelding kon niet laden', style: TextStyle(color: Colors.black54))),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                autofocus: true,
                onSubmitted: (v) => Navigator.pop(context, v.trim()),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFF14161F),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _line)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _line)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuleren')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Verstuur'),
          ),
        ],
      ),
    );
  }

  Widget _statusRow(String label, String key, {Widget? trailing}) {
    final r = _conn[key];
    IconData icon;
    Color color;
    String text;
    switch (r?.state) {
      case ConnState.ok:
        icon = Icons.check_circle_rounded;
        color = _accent2;
        text = r!.detail;
        break;
      case ConnState.fail:
        icon = Icons.cancel_rounded;
        color = Colors.redAccent;
        text = r!.detail;
        break;
      case ConnState.absent:
        icon = Icons.remove_circle_outline_rounded;
        color = _muted;
        text = r!.detail;
        break;
      case ConnState.checking:
        icon = Icons.hourglass_top_rounded;
        color = _muted;
        text = 'Testen…';
        break;
      default:
        icon = Icons.circle_outlined;
        color = _muted;
        text = 'Nog niet getest';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          r?.state == ConnState.checking
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _muted))
              : Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          SizedBox(
              width: 84,
              child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: color))),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c, {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _muted, fontSize: 12.5)),
          const SizedBox(height: 5),
          MaybePressable(
            enabled: isTv,
            onPressed: () => _focusFor(c).requestFocus(),
            borderRadius: BorderRadius.circular(9),
            child: TextField(
            controller: c,
            focusNode: _focusFor(c),
            obscureText: obscure,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF14161F),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _line)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _line)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: _accent)),
            ),
            ),
          ),
        ],
      ),
    );
  }

  /// The node for this field, made once and kept. Keyed by the controller because that is what
  /// [_field] is handed — there is no id, and eight call sites should not have to invent one.
  FocusNode _focusFor(TextEditingController c) => _fieldFocus.putIfAbsent(
        c,
        () => FocusNode(skipTraversal: isTv),
      );

  @override
  Widget build(BuildContext context) {
    // A page on a phone, a dialog in a window.
    //
    // This was always a settings PAGE wearing a dialog: 480 points wide, 640 tall, scrolling
    // inside itself. dialogWidth already kept it from overflowing a 412-point screen, but what was
    // left was a panel with a strip of dimmed app around it and a scroll of its own — a window
    // drawn on a phone. Full screen it is simply the screen you are on, and the fields get the
    // width back.
    if (isCompact(context)) {
      return Scaffold(
        backgroundColor: _panel,
        body: SafeArea(
          child: Column(
            children: [
              // The way out, top left, where a phone looks for it. “Annuleren” at the bottom does
              // the same thing and stays in view, but a full screen with an empty top-left corner
              // reads as a dead end.
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Terug',
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                  child: _body(context),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Dialog(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: dialogWidth(context, 480),
        constraints: const BoxConstraints(maxHeight: 640),
        padding: const EdgeInsets.all(24),
        child: _body(context),
      ),
    );
  }

  /// Two fields that sit side by side in a window and stack on a phone.
  ///
  /// Two Expandeds share 380 points minus the padding on a phone, which leaves about 170 each —
  /// the width at which a label like “Soulseek wachtwoord” prints on two lines above a field you
  /// cannot read what you typed into.
  Widget _pair(BuildContext context, Widget a, Widget b) => isCompact(context)
      ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [a, b])
      : Row(children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)]);

  Widget _body(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Instellingen', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            context.watch<CloudSession>().isSignedIn
                ? 'Je sleutels reizen mee met je account, zodat een nieuwe installatie ze '
                    'terugkrijgt.'
                : 'Sleutels blijven op dit apparaat. Log in en ze reizen mee met je account.',
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
          // The one thing that must not stay quiet. When settings.json cannot be read, the app
          // now refuses to save over it — which is right, and which without a word here would
          // simply look like "my settings do not stick" with no reason given anywhere.
          if (context.watch<AppSettings>().loadFailed) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B6B).withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: .4)),
              ),
              child: const Text(
                'Je instellingenbestand is beschadigd en kon niet worden gelezen. De app bewaart '
                'nu niets, expres: dat bestand is het enige waar je wachtwoorden in staan, en er '
                'lege velden overheen schrijven zou ze definitief wissen. Vul ze hieronder '
                'opnieuw in en druk op Opslaan, dan is het hersteld.',
                style: TextStyle(color: Color(0xFFFF6B6B), fontSize: 12, height: 1.4),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field('TorBox API-sleutel', _torbox),
                  _field('Discogs token', _discogs),
                  _pair(
                    context,
                    _field('Soulseek gebruiker', _slskUser),
                    _field('Soulseek wachtwoord', _slskPass, obscure: true),
                  ),
                  _field('Soulseek luisterpoort (zelfde als de native app)', _slskPort),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                        'Zonder open poort ziet de app alleen peers die zelf bereikbaar zijn — dat is waarom '
                        'de native app soms méér vindt. Vul dezelfde poort in die SoulseekQt gebruikt (die '
                        'staat al doorgestuurd in je router) en zet er een Windows Firewall-uitzondering op.',
                        style: TextStyle(color: _muted, fontSize: 11.5)),
                  ),
                  _pair(
                    context,
                    _field('RuTracker gebruiker', _rtUser),
                    _field('RuTracker wachtwoord', _rtPass, obscure: true),
                  ),
                  _field('Last.fm API-sleutel', _lastfm),
                  const SizedBox(height: 4),
                  const Divider(color: _line, height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Verbindingen',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _testing ? null : _testAll,
                        icon: _testing
                            ? const SizedBox(
                                width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _accent))
                            : const Icon(Icons.wifi_tethering_rounded, size: 16),
                        label: Text(_testing ? 'Testen…' : 'Test verbindingen'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  _statusRow('TorBox', 'torbox'),
                  _statusRow('Discogs', 'discogs'),
                  _statusRow('Soulseek', 'soulseek'),
                  _statusRow('RuTracker', 'rutracker',
                      trailing: TextButton(
                        onPressed: _rtBusy ? null : _rtLogin,
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                        child: Text(_rtBusy ? 'Bezig…' : 'Inloggen', style: const TextStyle(fontSize: 12.5)),
                      )),
                  const SizedBox(height: 10),
                  const Divider(color: _line, height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Downloads opruimen',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                            SizedBox(height: 2),
                            Text(
                                'Sorteert je downloads in Albums / Singles / Compilaties per artiest en '
                                'gooit dubbele nummers weg (beste kwaliteit blijft). Raakt alleen de map '
                                '“DebridMusic Downloads” aan — je eigen collectie blijft ongemoeid.',
                                style: TextStyle(color: _muted, fontSize: 11.5)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: _panel2, foregroundColor: Colors.white),
                        onPressed: _tidying ? null : _tidyDownloads,
                        icon: _tidying
                            ? const SizedBox(
                                width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _accent))
                            : const Icon(Icons.cleaning_services_rounded, size: 16),
                        label: Text(_tidying ? 'Bezig…' : 'Opruimen'),
                      ),
                    ],
                  ),
                  if (_tidyResult != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_tidyResult!, style: TextStyle(color: _accent2, fontSize: 12)),
                    ),
                  // Tracks removed "from library only" are still on disk — offer them back.
                  Consumer<LibraryStore>(
                    builder: (_, lib, __) => lib.hiddenCount == 0
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                      '${lib.hiddenCount} nummer(s) verborgen uit je bibliotheek '
                                      '(staan nog wel op je pc).',
                                      style: const TextStyle(color: _muted, fontSize: 11.5)),
                                ),
                                const SizedBox(width: 10),
                                TextButton.icon(
                                  onPressed: () => lib.restoreHidden(),
                                  icon: const Icon(Icons.undo_rounded, size: 15),
                                  label: const Text('Terugzetten'),
                                  style: TextButton.styleFrom(
                                      foregroundColor: _accent, textStyle: const TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 14),
                  const Divider(color: _line, height: 1),
                  const SizedBox(height: 12),
                  const _SharingSection(),
                  const SizedBox(height: 14),
                  const Divider(color: _line, height: 1),
                  const SizedBox(height: 12),
                  const _AboutSection(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuleren')),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _accent),
                onPressed: () async {
                  final s = context.read<AppSettings>();
                  final lib = context.read<LibraryStore>();
                  s.discogsToken = _discogs.text.trim();
                  s.torboxToken = _torbox.text.trim();
                  s.soulseekUser = _slskUser.text.trim();
                  s.soulseekPass = _slskPass.text.trim();
                  s.soulseekPort = int.tryParse(_slskPort.text.trim()) ?? 0;
                  s.rutrackerUser = _rtUser.text.trim();
                  s.rutrackerPass = _rtPass.text;
                  s.lastfmKey = _lastfm.text.trim();
                  // Pressing Save here is the deliberate override of the refuse-to-write guard:
                  // these values came from the fields, not from a failed load, so writing them
                  // over a broken file is a repair rather than the loss the guard exists for.
                  s.forgetLoadFailure();
                  await s.save();
                  if (context.mounted) Navigator.pop(context);
                  lib.enrich(s); // pick up covers that need the (new) Discogs token
                },
                child: const Text('Opslaan'),
              ),
            ],
          ),
        ],
      );
}

String _fmt(Duration? d) {
  if (d == null) return '0:00';
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// The album sleeve, with the disc sliding out from behind it while the record plays.
///
/// Both scans come from Discogs, which does not label them — see artwork.dart for how the disc is
/// told apart from a back cover. When there is no disc scan the sleeve simply sits there, which is
/// what every album looked like before.
class AlbumArt extends StatefulWidget {
  final String artist, album;
  final Uint8List? fallback;

  /// A sleeve the user picked by hand. It outranks anything Discogs offers — an automatic source
  /// correcting a deliberate choice is the app arguing with its owner.
  final Uint8List? chosen;
  final double size;

  /// Which RECORD this is, when the caller knows (the album uid). Only used to tell "the same
  /// record under a new name" apart from "a different record altogether": scans are kept on screen
  /// through the first, and must not be through the second.
  final String identity;

  final int trackCount;
  final bool playing;

  /// The Discogs release the user pinned, if any — see LibraryStore.pinnedRelease.
  final int? pinned;

  /// Or the MusicBrainz one — see LibraryStore.pinnedMbid.
  final String? pinnedMbid;

  /// The sleeve this widget ended up drawing, handed back as it resolves.
  ///
  /// For the screens that show the art AND let you open it: the enlarged view has to be the same
  /// image as the thumbnail, and only this widget knows which pressing's scan won.
  final ValueChanged<Uint8List?>? onFront;

  /// Images the user assigned by hand — see LibraryStore.albumArtRoles. They outrank every guess.
  final Map<String, String> roles;
  const AlbumArt({
    super.key,
    required this.artist,
    required this.album,
    required this.size,
    this.identity = '',
    this.fallback,
    this.chosen,
    this.trackCount = 0,
    this.playing = false,
    this.pinned,
    this.pinnedMbid,
    this.onFront,
    this.roles = const {},
  });

  @override
  State<AlbumArt> createState() => _AlbumArtState();
}

/// How far the disc stays out when nothing is playing.
///
/// Enough to see that there IS one, and to check the scan you just chose; not so much that pressing
/// play has nothing left to show. A quarter of the travel leaves the label behind the sleeve, so it
/// still reads as a disc tucked into a card rather than one lying beside it.
const _discRest = 0.26;

/// A disc with a hole in it, the way a CD has one.
///
/// Two circles in one path with [PathFillType.evenOdd]: the outer one keeps, the inner one gives
/// back. The sleeve behind shows through the hole, which is what makes it read as a disc lying on
/// top rather than as a printed circle.
///
/// Still one clip, so the [RepaintBoundary] above it does its job exactly as before: the mask is
/// rasterised once and each frame only turns an existing layer. Doing this with a second widget
/// stacked on top — a hole painted in the background colour — would have looked right on the album
/// page and wrong everywhere the background is not that colour.
class _DiscClipper extends CustomClipper<Path> {
  const _DiscClipper();

  /// A CD is 120 mm across with a 15 mm hole: an eighth. Measured rather than eyeballed, because
  /// slightly too big reads as a vinyl label and slightly too small as a smudge.
  static const _holeFraction = 15 / 120;

  @override
  Path getClip(Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: centre, radius: radius))
      ..addOval(Rect.fromCircle(center: centre, radius: radius * _holeFraction));
  }

  @override
  bool shouldReclip(_DiscClipper oldClipper) => false;
}

class _AlbumArtState extends State<AlbumArt> with TickerProviderStateMixin {
  ReleaseArt? _art;
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 750),
    reverseDuration: const Duration(milliseconds: 450),
  );
  // Roughly a third of an RPM on screen — enough to read as turning, slow enough not to nag.
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 9));

  @override
  void initState() {
    super.initState();
    _load();
    _sync();
  }

  @override
  void didUpdateWidget(AlbumArt old) {
    super.didUpdateWidget(old);
    // Same as the info panel: a new pin is a new set of scans, even when the album's name is
    // unchanged. This is why the disc never followed the release you picked.
    if (old.artist != widget.artist ||
        old.album != widget.album ||
        old.pinned != widget.pinned ||
        old.pinnedMbid != widget.pinnedMbid ||
        !mapEquals(old.roles, widget.roles)) {
      // A DIFFERENT record: drop what is up. Keeping it would put one album's sleeve and disc on
      // another album's page for the length of a round trip, which is not a smaller lie than a gap.
      if (widget.identity.isNotEmpty && old.identity.isNotEmpty &&
          old.identity != widget.identity) {
        setState(() => _art = null);
      }
      // Otherwise the old scans stay up until the new ones arrive — renaming a record does not
      // change its sleeve. Clearing here left a gap the length of a network round trip, in which
      // the disc vanished and the sleeve fell back to the file's own cover, which read as the app
      // losing the choice that was just made.
      _load();
    }
    if (old.playing != widget.playing) _sync();
  }

  void _sync() {
    if (widget.playing) {
      _slide.forward();
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _slide.reverse();
      // Left where it stopped rather than snapped back to zero: a record that stops turning
      // stops where it is.
      _spin.stop();
    }
  }

  /// Which load is the current one. A pin can be changed twice before the first fetch returns, and
  /// without this the slower answer would land last and win — showing scans nobody asked for.
  int _gen = 0;

  Future<void> _load() async {
    final artist = widget.artist, album = widget.album;
    final mine = ++_gen;
    try {
      final art = await DiscogsService(context.read<AppSettings>()).releaseArt(artist, album,
          expectedTracks: widget.trackCount,
          pinned: widget.pinned,
          pinnedMbid: widget.pinnedMbid,
          roles: widget.roles);
      if (!mounted || mine != _gen || artist != widget.artist || album != widget.album) return;
      // Nothing found leaves what is on screen alone: an empty answer is not a better answer than
      // the sleeve already showing.
      if (art != null) setState(() => _art = art);
      // Hand it to the library too. Without this the correction lived only on the open page: the
      // album showed the right sleeve, and going back to the grid showed the wrong one again.
      //
      // `from` is what makes that actually true now. With a pressing pinned or matched, this is the
      // art OF that release and outranks whatever the files carry; without one it is a search by
      // name, which is a guess and stays below the embedded cover.
      final front = art?.front;
      if (front != null && mounted) {
        final from = widget.pinnedMbid != null && widget.pinnedMbid!.isNotEmpty
            ? 'mb:${widget.pinnedMbid}'
            : (widget.pinned != null && widget.pinned! > 0 ? 'rel:${widget.pinned}' : null);
        context.read<LibraryStore>().adoptAlbumCover(artist, album, front, from: from);
      }
      widget.onFront?.call(widget.chosen ?? front ?? widget.fallback);
    } catch (_) {/* no artwork is not an error worth showing */}
  }

  @override
  void dispose() {
    _slide.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final front = widget.chosen ?? _art?.front ?? widget.fallback;
    final disc = _art?.disc;
    // How far the disc comes out. Started at .42 — enough to see it, not enough to enjoy it — so
    // it now clears the sleeve by a good margin while the label still sits behind the card.
    //
    // Less of it in portrait on a phone. The travel is reserved WIDTH, so on 411 points every
    // percent of it is taken off the sleeve and off whatever sits beside it — and on the player
    // screen that is the row of transport buttons, which has to be there. Sideways and on the TV
    // there is width to spare, so the disc gets its full stride.
    final travel = s * discTravelFactor(context);

    final sleeve = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: front == null
          ? Container(width: s, height: s, color: _panel2, child: const Icon(Icons.album, color: _muted))
          : Image.memory(front, width: s, height: s, fit: BoxFit.cover),
    );

    if (disc == null) return sleeve;

    // Built once and handed to the animation as a child, so none of this is rebuilt per frame.
    //
    // The order is load-bearing. ClipOval forces a saveLayer — Flutter renders into an offscreen
    // buffer, masks it, then composites — which is the most expensive thing in the raster pipeline.
    // Written the obvious way, that saveLayer sat INSIDE the rotation, so a ~660px disc was masked
    // and re-composited sixty times a second. That is the stutter, and it was mine, not the Shield's.
    //
    // With the clip inside a RepaintBoundary and the rotation outside it, the mask is rasterised
    // ONCE into a layer and each frame only moves a transform.
    final spinningDisc = RotationTransition(
      turns: _spin,
      child: RepaintBoundary(
        child: ClipPath(
          clipper: const _DiscClipper(),
          child: Image.memory(disc, width: s * .92, height: s * .92, fit: BoxFit.cover),
        ),
      ),
    );

    return SizedBox(
      width: s + travel,
      height: s,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Behind the sleeve, and drawn first so it stays there.
          Positioned(
            left: 0,
            top: s * .04,
            child: AnimatedBuilder(
              animation: _slide,
              // Translate rather than reposition: a Positioned inside a builder would relayout the
              // Stack every frame, where a transform only moves an already-painted layer.
              // A resting sliver, always. Standing still the disc used to sit entirely behind the
              // sleeve, so an album page you were not playing showed no disc at all — and somebody
              // who had just chosen a disc scan had no way to look at it without pressing play.
              // The reveal is still the reveal: it comes the rest of the way out and starts turning.
              builder: (context, child) => Transform.translate(
                offset: Offset(
                  (_discRest + (1 - _discRest) * Curves.easeOutCubic.transform(_slide.value)) *
                      travel,
                  0,
                ),
                child: child,
              ),
              child: spinningDisc,
            ),
          ),
          // Never rebuilt: it is outside the builder entirely, and it never changes while a record
          // plays.
          Positioned(left: 0, top: 0, child: sleeve),
        ],
      ),
    );
  }
}

/// Pick which pressing describes an album — showing, before you choose, what each one carries.
///
/// The metadata editor could already pin a release, but it listed them as bare names and said
/// nothing about their artwork. Choosing blind meant finding out afterwards that a pressing had no
/// disc scan, and the animation had nothing to spin.
class ReleaseGallery extends StatefulWidget {
  final Album album;
  const ReleaseGallery(this.album, {super.key});

  @override
  State<ReleaseGallery> createState() => _ReleaseGalleryState();
}

/// The three things a scan can be, and what to call each on screen.
///
/// One list, read by the gallery and by the assign dialog: two copies would drift, and the role
/// KEYS are what album_art_roles.json stores — a label changed in one place and not the other would
/// write a role nothing reads.
const artRoles = [('front', 'hoes'), ('back', 'achter'), ('disc', 'cd')];

class _ReleaseGalleryState extends State<ReleaseGallery> {
  static const _roles = artRoles;

  List<ReleaseChoice>? _choices;
  String? _error;

  /// Which source has reported in. Discogs takes far longer, so the list is live before it lands
  /// and the footer has to be able to say so.
  bool _mbDone = false, _dgDone = false, _dgFailed = false;
  bool _busy = false;

  /// Which formats to show. Everything Discogs has is fetched; this only narrows what is listed,
  /// so switching filters never costs another request.
  String _filter = 'Alles';

  /// role → the scan picked for it, possibly from a DIFFERENT pressing than the others.
  ///
  /// A record you own rarely matches one catalogue entry exactly: the sleeve is best photographed on
  /// the digital release, the tray inlay only exists on the CD, and the disc scan on a third. Held
  /// here until Save so a half-made choice never reaches the album, and so "cancel" means cancel.
  final Map<String, ChoiceImage> _staged = {};
  bool _saving = false;

  void _stage(String role, ChoiceImage img) {
    setState(() {
      // Tapping the same one again takes it back, which is the only way to undo without cancelling
      // the whole dialog.
      if (_staged[role]?.uri == img.uri) {
        _staged.remove(role);
      } else {
        _staged[role] = img;
      }
    });
  }

  /// Write the picked scans and have every screen show them in the same frame.
  ///
  /// Two different writes, on purpose:
  ///   - back and disc are ROLES: a url per role, which releaseArt reads and which its cache key
  ///     already includes, so the album page re-fetches by itself.
  ///   - the front is also fetched and pinned as the album's cover, because the grid, the player bar
  ///     and the Tracks list read Album.cover and would otherwise keep the old sleeve until
  ///     something happened to re-enrich them. That is the difference between "instant on this page"
  ///     and "instant everywhere", which is what was asked for.
  Future<void> _save() async {
    if (_staged.isEmpty || _saving) return;
    setState(() => _saving = true);
    final lib = context.read<LibraryStore>();
    final settings = context.read<AppSettings>();
    final mbSvc = context.read<MusicBrainzService>();
    try {
      for (final e in _staged.entries) {
        await lib.setAlbumArtRole(widget.album.artist, widget.album.title, e.key, e.value.uri);
      }
      final front = _staged['front'];
      if (front != null) {
        // Each catalogue serves its own images, and Discogs wants its token on the request.
        final bytes = front.uri.contains('coverartarchive.org')
            ? await mbSvc.fetchImage(front.uri)
            : await DiscogsService(settings).fetchImage(front.uri);
        if (bytes != null && bytes.isNotEmpty) {
          await lib.setAlbumCover(widget.album, settings, bytes);
        }
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _srcToast(context, 'Kon de keuze niet opslaan: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// MusicBrainz first, Discogs appended — which is the order the user asked for and also the
  /// order the two can deliver in. One release-group browse names every pressing at once, so the
  /// dialog fills in about two seconds; Discogs needs a request per pressing and takes fifteen.
  ///
  /// So the list is shown as soon as MusicBrainz answers rather than waiting for both. A user
  /// staring at a spinner while a source they did not ask about finishes is the thing to avoid.
  Future<void> _load() async {
    final lib = context.read<LibraryStore>();
    final settings = context.read<AppSettings>();
    final pinnedMb = lib.pinnedMbid(widget.album);
    final pinnedDg = lib.pinnedRelease(widget.album);

    try {
      final mb = await context
          .read<MusicBrainzService>()
          .editionChoices(widget.album.artist, widget.album.title, pinnedMbid: pinnedMb);
      if (!mounted) return;
      setState(() {
        _choices = mb;
        _mbDone = true;
      });
    } catch (_) {
      if (mounted) setState(() => _mbDone = true);
    }

    // Discogs supplements: it has scans for pressings the archive has never seen. Its failures are
    // reported separately, because "Discogs is unreachable" and "this record has no pressings" are
    // very different things to be told.
    // Everything MusicBrainz found, kept aside so each progressive Discogs update can be merged
    // against it without the two lists fighting over the same variable.
    final fromMb = [...?_choices];
    void merge(List<ReleaseChoice> dg) {
      if (!mounted) return;
      final have = {for (final c in fromMb) c.dedupeKey};
      setState(() => _choices = [...fromMb, ...dg.where((c) => have.add(c.dedupeKey))]);
    }

    try {
      // The rows appear as soon as the versions listing lands — one request for a whole master.
      // Their scans are fetched per row, as each is scrolled into view: see _wantDetail.
      await DiscogsService(settings).releaseChoices(widget.album.artist, widget.album.title,
          pinned: pinnedDg, onPartial: merge);
      if (mounted) setState(() => _dgDone = true);
    } catch (_) {
      if (mounted) setState(() { _dgDone = true; _dgFailed = true; });
    }
    if (mounted && (_choices?.isEmpty ?? true)) {
      setState(() => _error = _dgFailed
          ? 'Geen uitgaves gevonden. Discogs was niet bereikbaar, dus de aanvulling ontbreekt.'
          : 'Geen uitgaves gevonden.');
    }
  }

  /// Discogs pressings whose scans have been asked for, so scrolling past a row twice doesn't ask
  /// twice. Holds ids, not rows: the list is rebuilt as answers merge in.
  final _asked = <int>{};

  /// This row is on screen, so now it is worth knowing what it holds.
  ///
  /// Called from the builder, which Flutter only runs for visible rows — that is the whole saving.
  /// Deferred by a frame because a builder must not setState while it is building.
  void _wantDetail(ReleaseChoice c) {
    if (c.isMb || c.detailed || c.releaseId <= 0 || !_asked.add(c.releaseId)) return;
    final settings = context.read<AppSettings>();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final filled = await DiscogsService(settings).detailOf(c).catchError((_) => null);
      if (!mounted || filled == null) return;
      final list = _choices;
      if (list == null) return;
      final i = list.indexWhere((x) => x.key == c.key);
      if (i < 0) return;
      setState(() => _choices = [...list]..[i] = filled);
    });
  }

  /// Open the assign panel for one pressing, fetching its scans first if that hasn't happened.
  Future<void> _assign(ReleaseChoice c) async {
    if (!mounted) return;
    await showDialog<void>(
        context: context, builder: (_) => AssignScansDialog(album: widget.album, choice: c));
  }

  Future<void> _choose(ReleaseChoice c) async {
    if (_busy) return;
    setState(() => _busy = true);
    final lib = context.read<LibraryStore>();
    final settings = context.read<AppSettings>();
    final mbSvc = context.read<MusicBrainzService>();
    try {
      Uint8List? front;
      if (c.front != null) {
        // Each catalogue serves its own images; Discogs wants its token on the request.
        front = c.isMb
            ? await mbSvc.fetchImage(c.front!.uri)
            : await DiscogsService(settings).fetchImage(c.front!.uri);
      }
      if (!mounted) return;
      // Choosing an EDITION means using its scans — all three of them. Any single scan picked
      // earlier is an override that outranks the pressing, so leaving those in place made this
      // button look like it did nothing: you chose the CD and kept the digital sleeve.
      await lib.clearAlbumArtRoles(widget.album.artist, widget.album.title);
      await lib.applyCorrection(widget.album, settings,
          coverBytes: front,
          discogsRelease: c.isMb ? null : c.releaseId,
          mbid: c.isMb ? c.mbid : null);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      // The pin may already be on disk; saying nothing would leave the dialog dead and the button
      // spinning, which is how a failure here used to present.
      if (mounted) {
        setState(() => _busy = false);
        _srcToast(context, 'Kon deze uitgave niet toepassen.');
      }
    }
  }

  /// Take this pressing's numbering for the library's own files.
  ///
  /// Separate from choosing it, because they are different decisions: one describes the record,
  /// the other rewrites what the tracklist says. A user with correct tags wants only the first.
  Future<void> _renumber(ReleaseChoice c) async {
    final lib = context.read<LibraryStore>();
    final mbSvc = context.read<MusicBrainzService>();
    var list = c.tracklist;
    // A row arrives without a tracklist until something looks it up — the picker lists a whole
    // master off one request and fills the rest in as rows come into view. So ask, per catalogue,
    // rather than telling the user a pressing has no numbering when only nobody had asked yet.
    if (list.isEmpty && c.isMb && c.mbid != null) {
      final full = await mbSvc.release(c.mbid!);
      if (full != null) list = await mbSvc.tracklistOf(full);
    } else if (list.isEmpty && !c.isMb && c.releaseId > 0) {
      final full = await DiscogsService(context.read<AppSettings>()).release(c.releaseId);
      if (full != null) {
        list = [for (final t in full.tracklist) ChoiceTrack(t.position, t.title, t.seconds)];
      }
    }
    if (!mounted || list.isEmpty) {
      if (mounted) _srcToast(context, 'Deze uitgave geeft geen nummering.');
      return;
    }
    final plan = lib.planRenumber(widget.album, list);
    if (!mounted) return;
    final done = await showDialog<bool>(
        context: context, builder: (_) => RenumberDialog(album: widget.album, plan: plan));
    if (done == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    // Both, because an album pinned to a MusicBrainz pressing marked no row at all before: the
    // gallery only ever asked about the Discogs pin.
    final pinnedKey = lib.pinnedMbid(widget.album) != null
        ? 'mb:${lib.pinnedMbid(widget.album)}'
        : (lib.pinnedRelease(widget.album) != null
            ? 'dg:${lib.pinnedRelease(widget.album)}'
            : null);
    return Dialog(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth(context, 820),
        height: dialogHeight(context, 660),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('Uitgave kiezen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop(false)),
              ]),
              Text('${widget.album.artist} — ${widget.album.title}',
                  style: const TextStyle(color: _muted, fontSize: 12.5)),
              const SizedBox(height: 14),
              // Filters over what was fetched, not another trip to Discogs.
              Row(children: [
                for (final f in const ['Alles', 'CD', 'Vinyl', 'Digitaal'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () => setState(() => _filter = f),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: _filter == f ? _accent : Colors.white.withValues(alpha: .06),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(f,
                            style: TextStyle(
                                fontSize: 12,
                                color: _filter == f ? Colors.white : _muted,
                                fontWeight: _filter == f ? FontWeight.w600 : FontWeight.w400)),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 12),
              Expanded(child: _body(pinnedKey)),
              // MusicBrainz answers in about two seconds and Discogs in fifteen, so the list is
              // usable long before it is finished. Say which, rather than let a short list look
              // like the whole answer.
              if (_mbDone && !_dgDone)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Row(children: [
                    SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(strokeWidth: 1.6, color: _muted)),
                    SizedBox(width: 8),
                    Text('Discogs vult nog aan…', style: TextStyle(color: _muted, fontSize: 11.5)),
                  ]),
                ),
              if (_dgDone && _dgFailed)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Discogs was niet bereikbaar — dit zijn alleen de MusicBrainz-uitgaves.',
                      style: TextStyle(color: _muted, fontSize: 11.5)),
                ),
              // Only once something is picked: an empty bar at the bottom of every gallery would be
              // a control that does nothing, most of the time.
              if (_staged.isNotEmpty) ...[
                const Divider(height: 18),
                Row(children: [
                  Expanded(
                    child: Text(
                      // Names what will change, in the words the thumbnails use, so pressing Save is
                      // not a leap of faith.
                      'Overnemen: ${[
                        for (final r in _roles)
                          if (_staged.containsKey(r.$1)) r.$2
                      ].join(', ')}',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: _saving ? null : () => setState(_staged.clear),
                    child: const Text('Ongedaan maken'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _accent),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_rounded, size: 18),
                    label: Text(_saving ? 'Opslaan…' : 'Opslaan'),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(String? pinnedKey) {
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: _muted)));
    final list = _choices;
    if (list == null) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(strokeWidth: 2, color: _accent),
          SizedBox(height: 14),
          // Honest about the wait: this is several Discogs calls plus their images, and Discogs
          // allows sixty a minute.
          Text('Uitgaves en scans ophalen…', style: TextStyle(color: _muted, fontSize: 12.5)),
        ]),
      );
    }
    if (list.isEmpty) return const Center(child: Text('Geen uitgaves gevonden.', style: TextStyle(color: _muted)));
    // 'File' is what Discogs calls a digital release; nobody looking for one thinks of it that way.
    // Through the shared bucketing, not substring matching: MusicBrainz says `12" Vinyl`,
    // `Digital Media` and `Enhanced CD` where Discogs says `Vinyl` and `File`, and one rule has
    // to cover both or the filters silently hide half the list.
    final shown = _filter == 'Alles'
        ? list
        : list.where((c) {
            final m = majorFormat(c.format);
            if (_filter == 'CD') return m == 'CD' || m == 'CDr';
            if (_filter == 'Vinyl') return m == 'Vinyl';
            return m == 'File';
          }).toList();
    if (shown.isEmpty) {
      return const Center(child: Text('Geen uitgaves in dit formaat.', style: TextStyle(color: _muted)));
    }
    return ListView.separated(
      itemCount: shown.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final c = shown[i];
        // Only rows that are actually built get looked up — that is what makes this cheap.
        _wantDetail(c);
        final isPinned = pinnedKey != null && pinnedKey == c.key;
        return InkWell(
          onTap: () => _choose(c),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isPinned ? _accent.withValues(alpha: .16) : _panel2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isPinned ? _accent : Colors.transparent),
            ),
            child: Row(children: [
              // The three scans side by side, so what you get is visible rather than described.
              // Clicking one opens every scan this pressing has, to say which is which — the roles
              // below are inferred, and inference on a catalogue that never labels its images gets
              // the back and the disc the wrong way round often enough to need an answer.
              _thumb(c.front, 'hoes', role: 'front', row: c, onLongPress: () => _assign(c)),
              const SizedBox(width: 8),
              _thumb(c.back, 'achter', role: 'back', row: c, onLongPress: () => _assign(c)),
              const SizedBox(width: 8),
              _thumb(c.disc, 'cd', role: 'disc', row: c, onLongPress: () => _assign(c)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.line, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                  if ((c.label ?? '').isNotEmpty)
                    Text(c.label!, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  Row(children: [
                    // Which catalogue this row came from. The user asked to choose the source, so
                    // it has to be visible rather than inferred from the row's shape.
                    _source(c.isMb),
                    const SizedBox(width: 6),
                    // Until this pressing has been looked up we do not know whether it has a back
                    // or a disc, and saying "–" would be a claim we have not earned. A row you can
                    // see is always on its way now — being visible is what starts the lookup — so
                    // the spinner is always honest here.
                    if (!c.detailed) ...[
                      const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 1.4, color: _muted)),
                      const SizedBox(width: 6),
                      const Text('scans ophalen…', style: TextStyle(color: _muted, fontSize: 10.5)),
                    ] else ...[
                      _tag('achterkant', c.hasBack),
                      const SizedBox(width: 6),
                      _tag('cd-scan', c.hasDisc),
                    ],
                  ]),
                ]),
              ),
              IconButton(
                icon: const Icon(Icons.format_list_numbered_rounded, size: 19),
                tooltip: 'Nummering van deze uitgave overnemen',
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                onPressed: () => _renumber(c),
              ),
              if (isPinned) const Icon(Icons.check_circle_rounded, color: _accent, size: 20),
            ]),
          ),
        );
      },
    );
  }

  /// One scan of one pressing, and a way to say "this one, for this role".
  ///
  /// Tap picks it for [role] on the RECORD — the sleeve of the digital edition beside the disc of
  /// the CD, which is the thing a record collector's own copy actually looks like. Long-press still
  /// opens every scan this pressing has, for the case where the roles within one pressing are simply
  /// swapped.
  Widget _thumb(ChoiceImage? img, String label,
      {required String role, required ReleaseChoice row, VoidCallback? onLongPress}) {
    final staged = _staged[role];
    final chosen = img != null && staged != null && staged.uri == img.uri;
    return InkWell(
      onTap: img == null ? null : () => _stage(role, img),
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(6),
      child: Tooltip(
        message: img == null
            ? 'Deze uitgave heeft geen $label'
            : 'Klik: neem deze $label over · Lang indrukken: alle scans van deze uitgave',
        child: Column(children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: chosen ? _accent : Colors.transparent,
                width: 2,
              ),
            ),
            padding: const EdgeInsets.all(1),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: img == null
                  ? Container(
                      width: 58,
                      height: 58,
                      color: Colors.white.withValues(alpha: .04),
                      child: const Icon(Icons.close_rounded, size: 16, color: _muted))
                  : _netCover(img.thumb, size: 58, radius: 6),
            ),
          ),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  color: chosen ? _accent : _muted,
                  fontSize: 10,
                  fontWeight: chosen ? FontWeight.w700 : FontWeight.w400)),
        ]),
      ),
    );
  }

  /// Which catalogue found this pressing. The user asked to be able to choose the source, so the
  /// source has to be readable on the row rather than inferred from what the row happens to carry.
  Widget _source(bool isMb) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: (isMb ? _accent : _accent2).withValues(alpha: .18),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(isMb ? 'MusicBrainz' : 'Discogs',
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w600, color: isMb ? _accent : _accent2)),
      );

  /// Present or absent, stated rather than implied — the reason this dialog exists.
  Widget _tag(String text, bool on) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: on ? _accent2.withValues(alpha: .16) : Colors.white.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(on ? Icons.check_rounded : Icons.remove_rounded, size: 11, color: on ? _accent2 : _muted),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: on ? _accent2 : _muted, fontSize: 10.5)),
        ]),
      );
}

/// Say which scan is the sleeve, which is the back, and which is the disc.
///
/// Discogs marks one image "primary" and calls the rest "secondary" — it never states what a
/// picture SHOWS. So the app infers: primary is the front, wider-than-tall is the rear inlay, and a
/// punched hole in the middle means a disc. Measured on Random Access Memories, eight of its
/// fourteen scans are wider than tall, so the back-cover rule picks whichever booklet spread comes
/// first. This is where you say otherwise, and your answer outranks every guess afterwards.
class AssignScansDialog extends StatefulWidget {
  final Album album;
  final ReleaseChoice choice;
  const AssignScansDialog({super.key, required this.album, required this.choice});

  @override
  State<AssignScansDialog> createState() => _AssignScansDialogState();
}

class _AssignScansDialogState extends State<AssignScansDialog> {
  List<ChoiceImage>? _images;
  String? _error;

  static const _roles = artRoles;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Both read before the first await: after it this State may be gone, and reaching back into
    // context then is exactly what use_build_context_synchronously is warning about.
    final mb = context.read<MusicBrainzService>();
    final settings = context.read<AppSettings>();
    try {
      final c = widget.choice;
      final list = c.isMb
          ? [for (final i in await mb.art(c.mbid ?? '')) ChoiceImage(i.full, i.thumb)]
          : await DiscogsService(settings).allImages(c.releaseId);
      if (!mounted) return;
      setState(() {
        _images = list;
        if (list.isEmpty) _error = 'Deze uitgave heeft geen scans.';
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Kon de scans niet ophalen.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final roles = lib.albumArtRoles(widget.album.artist, widget.album.title);
    final images = _images;
    return Dialog(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth(context, 760),
        height: dialogHeight(context, 620),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('Scans toewijzen',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop()),
              ]),
              const Text('Klik onder een scan om te zeggen wat het is. Jouw keuze wint van wat de app zelf denkt.',
                  style: TextStyle(color: _muted, fontSize: 12.5)),
              const SizedBox(height: 14),
              Expanded(
                child: _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: _muted)))
                    : images == null
                        ? const Center(child: CircularProgressIndicator())
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 170,
                                mainAxisSpacing: 14,
                                crossAxisSpacing: 14,
                                childAspectRatio: .78),
                            itemCount: images.length,
                            itemBuilder: (_, i) {
                              final img = images[i];
                              return Column(children: [
                                Expanded(child: _netCover(img.thumb, size: 150, radius: 8)),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (final (role, label) in _roles)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 2),
                                        child: _roleChip(
                                          label,
                                          on: roles[role] == img.uri,
                                          onTap: () => lib.setAlbumArtRole(
                                              widget.album.artist,
                                              widget.album.title,
                                              role,
                                              // Clicking the role it already has clears it, so a
                                              // wrong assignment can be undone without a reset.
                                              roles[role] == img.uri ? '' : img.uri),
                                        ),
                                      ),
                                  ],
                                ),
                              ]);
                            },
                          ),
              ),
              if (roles.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: TextButton(
                    onPressed: () =>
                        lib.clearAlbumArtRoles(widget.album.artist, widget.album.title),
                    child: const Text('Alles weer laten raden',
                        style: TextStyle(color: _muted, fontSize: 12)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleChip(String text, {required bool on, required VoidCallback onTap}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: on ? _accent : Colors.white.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(text,
              style: TextStyle(
                  fontSize: 10.5,
                  color: on ? Colors.white : _muted,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
        ),
      );
}

/// Choose an artist's portrait and the backdrop behind their page.
///
/// Discogs holds dozens of photos per act (twenty-nine for Daft Punk) and TheAudioDB adds its own
/// fanart and thumbs, but neither labels what a picture is FOR. The app guesses by shape — squarish
/// reads as a portrait, wide as a backdrop — and a guess is exactly the thing worth overruling.
/// Portrait or backdrop, asked of a device that has only one kind of tap.
Future<void> _pickArtKind(BuildContext context, String artist, String url) async {
  final lib = context.read<LibraryStore>();
  final kind = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: _panel,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheet) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.person_rounded, size: 21),
            title: const Text('Als portret'),
            subtitle: const Text('De foto bij de naam',
                style: TextStyle(color: _muted, fontSize: 12)),
            onTap: () => Navigator.pop(sheet, 'portrait'),
          ),
          ListTile(
            leading: const Icon(Icons.wallpaper_rounded, size: 21),
            title: const Text('Als achtergrond'),
            subtitle: const Text('De wazige kleuren achter de pagina',
                style: TextStyle(color: _muted, fontSize: 12)),
            onTap: () => Navigator.pop(sheet, 'backdrop'),
          ),
        ],
      ),
    ),
  );
  if (kind != null) await lib.setArtistArt(artist, kind, url);
}

class ArtistArtGallery extends StatefulWidget {
  final String artist;
  const ArtistArtGallery(this.artist, {super.key});

  @override
  State<ArtistArtGallery> createState() => _ArtistArtGalleryState();
}

class _ArtistArtGalleryState extends State<ArtistArtGallery> {
  List<DiscogsImage>? _images;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = context.read<AppSettings>();
    try {
      final a = await DiscogsService(settings).artist(widget.artist);
      final extra = <DiscogsImage>[];
      // TheAudioDB's fanart is the widest thing either source has, and is usually the better
      // backdrop; Discogs almost never has anything that shape.
      final tadb = await CoverEnricher(settings).artistArt(widget.artist);
      for (final url in [tadb?.backdrop, tadb?.thumb]) {
        if (url != null && url.isNotEmpty) extra.add(DiscogsImage(url, url, 0, 0, false));
      }
      if (!mounted) return;
      setState(() => _images = [...a?.images ?? const <DiscogsImage>[], ...extra]);
    } catch (_) {
      if (mounted) setState(() => _error = 'Kon de foto\'s niet ophalen.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final portrait = lib.chosenArtistArt(widget.artist, 'portrait');
    final backdrop = lib.chosenArtistArt(widget.artist, 'backdrop');
    return Dialog(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth(context, 860),
        height: dialogHeight(context, 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('Foto kiezen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(context).pop()),
              ]),
              Text(widget.artist, style: const TextStyle(color: _muted, fontSize: 12.5)),
              const SizedBox(height: 4),
              const Text('Klik een foto voor het portret · rechtsklik voor de achtergrond',
                  style: TextStyle(color: _muted, fontSize: 11.5)),
              const SizedBox(height: 14),
              Expanded(child: _body(portrait, backdrop)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(String? portrait, String? backdrop) {
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: _muted)));
    final list = _images;
    if (list == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: _accent));
    }
    if (list.isEmpty) return const Center(child: Text('Geen foto\'s gevonden.', style: TextStyle(color: _muted)));
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: .82),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final img = list[i];
        final isPortrait = portrait == img.uri;
        final isBackdrop = backdrop == img.uri;
        final lib = context.read<LibraryStore>();
        return Pressable(
          // A finger has no right button and no OK to hold. On touch a tap therefore asks which of
          // the two this picture is for — until now choosing a backdrop from a phone was simply
          // not possible, and nothing on screen said so.
          onPressed: _isTouch
              ? () => _pickArtKind(context, widget.artist, img.uri)
              : () => lib.setArtistArt(widget.artist, 'portrait', img.uri),
          // Right-click sets the backdrop, and a remote has no right button — so on a television
          // holding OK does the same thing. Both, not one instead of the other: choosing a backdrop
          // was something you simply could not do from the sofa, and nothing on screen said why.
          //
          // Gated, because on a phone or an iPad a long press on a photo is not "set as backdrop"
          // to anybody, and it would fire where a drag or a context menu was meant.
          onSecondaryTap: () => lib.setArtistArt(widget.artist, 'backdrop', img.uri),
          onLongPress:
              isTv ? () => lib.setArtistArt(widget.artist, 'backdrop', img.uri) : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: isPortrait
                      ? _accent
                      : isBackdrop
                          ? _accent2
                          : Colors.transparent,
                  width: 2),
            ),
            child: Column(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: _netCover(img.thumb, size: 150, radius: 6),
                ),
              ),
              if (isPortrait || isBackdrop)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(isPortrait ? 'portret' : 'achtergrond',
                      style: TextStyle(fontSize: 10, color: isPortrait ? _accent : _accent2)),
                ),
            ]),
          ),
        );
      },
    );
  }
}

/// Move a track into another album — showing, before anything is touched, what happens on disk.
///
/// The one operation here that rewrites the folder tree, so it states its plan first. A file that
/// can't be moved still gets regrouped: the tags are what decide where a track lives, and leaving
/// it correct-but-in-place beats refusing the whole thing.
class MoveTrackDialog extends StatefulWidget {
  final Track track;

  /// The album the track is leaving, when it has one. Null for a track that no album page shows:
  /// a rip with no album tag sits in its own single, and a copy that lost a title collision is on
  /// no page at all. Those are precisely the tracks that need moving, so the dialog must open
  /// without a source — it only ever used this to keep the current album out of the target list.
  final Album? from;
  const MoveTrackDialog({super.key, required this.track, this.from});

  @override
  State<MoveTrackDialog> createState() => _MoveTrackDialogState();
}

class _MoveTrackDialogState extends State<MoveTrackDialog> {
  final _query = TextEditingController();
  Album? _target;
  bool _moveFiles = true;
  bool _busy = false;

  /// What the chosen target would do on disk. Fetched rather than computed: on a Mac or an iPad
  /// the PC is the only one that knows the folders, so this arrives a moment after the target is
  /// picked instead of being there in the same frame.
  List<MovePlan> _plan = const [];
  bool _planning = false;

  Future<void> _pick(Album album) async {
    setState(() {
      _target = album;
      _plan = const [];
      _planning = true;
    });
    try {
      final result = await context.read<LibraryStore>().planMoveAsync([widget.track], album);
      if (!mounted || _target != album) return; // a different album was picked meanwhile
      setState(() {
        _plan = result.items;
        _planning = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _planning = false);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final target = _target;
    if (target == null) return;
    setState(() => _busy = true);
    final moved = await context
        .read<LibraryStore>()
        .moveTracksToAlbum([widget.track], target, context.read<AppSettings>(),
            moveFiles: _moveFiles, plan: _plan);
    if (!mounted) return;
    _srcToast(context, moved > 0 ? 'Verplaatst — $moved bestand mee verhuisd' : 'Verplaatst — bestand bleef staan');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final q = normKey(_query.text);
    final options = lib.albums
        .where((a) => !a.isSingle && a != widget.from)
        .where((a) => q.isEmpty || normKey('${a.artist} ${a.title}').contains(q))
        .take(40)
        .toList();
    final plan = _plan;

    return Dialog(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth(context, 640),
        height: dialogHeight(context, 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Nummer verplaatsen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(widget.track.title, style: const TextStyle(color: _muted, fontSize: 12.5)),
            const SizedBox(height: 14),
            TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Zoek een album…', isDense: true),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final a = options[i];
                  final sel = identical(_target, a);
                  return InkWell(
                    onTap: () => _pick(a),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 5),
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: sel ? _accent.withValues(alpha: .18) : _panel2,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: sel ? _accent : Colors.transparent),
                      ),
                      child: Row(children: [
                        cover(a.cover, size: 34, radius: 5),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(a.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text('${a.artist} · ${a.tracks.length} nummers',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: _muted, fontSize: 11.5)),
                          ]),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              value: _moveFiles,
              onChanged: (v) => setState(() => _moveFiles = v ?? true),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Bestand mee verplaatsen', style: TextStyle(fontSize: 13)),
              subtitle: Text(
                // The plan, in words, before the button is pressed.
                plan.isEmpty
                    ? 'Kies eerst een album.'
                    : plan.first.movesFile
                        ? 'Naar: ${File(plan.first.to!).parent.path}'
                        : 'Doelmap onbekend — alleen de indeling verandert.',
                style: const TextStyle(color: _muted, fontSize: 11.5),
              ),
            ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  autofocus: isTv,
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Annuleren')),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _accent),
                onPressed: (_target == null || _busy || _planning) ? null : _go,
                child: _busy
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Verplaatsen'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Take an official pressing's numbering for a mistagged album — showing every change first.
///
/// Rippers get this wrong constantly: one album here arrived with two number sixes, two number
/// tens and a track with no number at all, so its tracklist could not be read or played in order.
/// The pressing knows; the tags do not. But rewriting what a user's library says about their own
/// files is not something to do silently, so the whole list is shown and collisions are refused.
class RenumberDialog extends StatefulWidget {
  final Album album;
  final RenumberPlan plan;
  const RenumberDialog({super.key, required this.album, required this.plan});

  @override
  State<RenumberDialog> createState() => _RenumberDialogState();
}

class _RenumberDialogState extends State<RenumberDialog> {
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    await context.read<LibraryStore>().applyRenumber(widget.plan);
    if (!mounted) return;
    _srcToast(context, 'Nummering overgenomen');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final blocked = plan.collides || plan.titleCollides;
    return Dialog(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth(context, 700),
        height: dialogHeight(context, 620),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Nummering overnemen',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('${widget.album.artist} · ${widget.album.title}',
                style: const TextStyle(color: _muted, fontSize: 12.5)),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: blocked ? Colors.red.withValues(alpha: .12) : _panel2,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  plan.collides
                      ? 'Geweigerd: twee nummers zouden hetzelfde nummer krijgen.'
                      : plan.titleCollides
                          ? 'Geweigerd: twee nummers zouden dezelfde titel krijgen — dan verdwijnt er één uit de lijst.'
                          : plan.changing.isEmpty
                              ? 'De nummering klopt al.'
                              : '${plan.changing.length} van de ${plan.steps.length} worden aangepast · ${plan.total} nummers',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                if (plan.unmatched.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                      '${plan.unmatched.length} niet herkend op deze uitgave — die houden hun eigen tags.',
                      style: const TextStyle(color: _muted, fontSize: 11.5)),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: plan.steps.length,
                itemBuilder: (_, i) {
                  final st = plan.steps[i];
                  final was = st.track.trackNo > 0 ? '${st.track.trackNo}' : '—';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      SizedBox(
                        width: 62,
                        child: Text(st.unmatched ? '$was  ·' : '$was → ${st.newNo}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: st.changes ? FontWeight.w700 : FontWeight.w400,
                                color: st.unmatched
                                    ? _muted
                                    : st.changes
                                        ? _accent
                                        : _muted)),
                      ),
                      Expanded(
                        child: Text(
                          st.official != null && st.official!.title != st.track.title
                              ? '${st.track.title}  →  ${st.official!.title}'
                              : st.track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5, color: st.unmatched ? _muted : Colors.white),
                        ),
                      ),
                    ]),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  autofocus: isTv,
                  onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuleren')),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _accent),
                onPressed: (_busy || blocked || plan.changing.isEmpty) ? null : _go,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Overnemen'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Pick one album out of the library. Pops the chosen [Album], or null.
class PickAlbumDialog extends StatefulWidget {
  /// The album doing the asking — never offered as an answer to itself.
  final Album exclude;
  const PickAlbumDialog({super.key, required this.exclude});

  @override
  State<PickAlbumDialog> createState() => _PickAlbumDialogState();
}

class _PickAlbumDialogState extends State<PickAlbumDialog> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final q = normKey(_query.text);
    final options = lib.albums
        .where((a) => !a.isSingle && a != widget.exclude)
        .where((a) => q.isEmpty || normKey('${a.artist} ${a.title}').contains(q))
        .take(60)
        .toList();

    return Dialog(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth(context, 620),
        height: dialogHeight(context, 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Welk album samenvoegen?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('Dit album gaat op in “${widget.exclude.title}”.',
                style: const TextStyle(color: _muted, fontSize: 12.5)),
            const SizedBox(height: 14),
            TextField(
              controller: _query,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Zoek een album…', isDense: true),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final a = options[i];
                  return InkWell(
                    onTap: () => Navigator.of(context).pop(a),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 5),
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        cover(a.cover, size: 34, radius: 5),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(a.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text('${a.artist} · ${a.tracks.length} nummers',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: _muted, fontSize: 11.5)),
                          ]),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  autofocus: isTv,
                  onPressed: () => Navigator.of(context).pop(), child: const Text('Annuleren')),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Clean up albums that are wholly duplicates of one you already own — the dry-run before it acts.
///
/// The stale fragments and junk singles the library found on its own: a "Special Edition" holding
/// three tracks that are all in the real album, an unknown-artist WAV that is really track two.
/// Nothing moves until Opruimen — and even then the loser of each pair goes to _dubbel, never the
/// bin, because the better copy is sometimes the one in the fragment.
class RedundantCleanupDialog extends StatefulWidget {
  final List<RedundantAlbum> found;
  const RedundantCleanupDialog({super.key, required this.found});

  @override
  State<RedundantCleanupDialog> createState() => _RedundantCleanupDialogState();
}

class _RedundantCleanupDialogState extends State<RedundantCleanupDialog> {
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    final lib = context.read<LibraryStore>();
    for (final r in widget.found) {
      await lib.consolidate(r);
    }
    if (!mounted) return;
    _srcToast(context, 'Dubbele albums opgeruimd');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final found = widget.found;
    final totalTracks = found.fold<int>(0, (n, r) => n + r.pairs.length);
    return Dialog(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth(context, 760),
        height: dialogHeight(context, 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Dubbele albums opruimen',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              '${found.length} ${found.length == 1 ? 'album gaat' : 'albums gaan'} op in een album dat je al hebt · '
              '$totalTracks ${totalTracks == 1 ? 'nummer' : 'nummers'}',
              style: const TextStyle(color: _muted, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: found.length,
                itemBuilder: (_, i) {
                  final r = found[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(11),
                    decoration:
                        BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(9)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${r.source.title}  →  ${r.target.title}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                      const SizedBox(height: 2),
                      Text(
                        r.upgrades > 0
                            ? '${r.upgrades} van de ${r.pairs.length} ${r.upgrades == 1 ? 'is' : 'zijn'} beter en vervangt wat je hebt · de rest naar _dubbel'
                            : 'alle ${r.pairs.length} zijn dubbel · naar _dubbel',
                        style: const TextStyle(color: _muted, fontSize: 11.5),
                      ),
                      const SizedBox(height: 6),
                      for (final p in r.pairs)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(children: [
                            Icon(p.dupWins ? Icons.upgrade_rounded : Icons.content_copy_rounded,
                                size: 14, color: p.dupWins ? _accent : _accent2),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                p.dupWins
                                    ? '${p.owned.trackNo}. ${p.owned.title} — betere kopie behouden, oude naar _dubbel'
                                    : '${p.owned.trackNo}. ${p.owned.title} — dubbel naar _dubbel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5),
                              ),
                            ),
                          ]),
                        ),
                    ]),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  autofocus: isTv,
                  onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuleren')),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _accent),
                onPressed: _busy ? null : _go,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Opruimen'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Put a record back together — showing, file by file, what that does on disk before it does it.
///
/// Two ways in. With no [absorb] it gathers the editions of ONE record that are scattered over
/// several folders. With [absorb] it swallows another album whole, the way Roon does.
///
/// The plan is the point. Merging used to change only the grouping, which left the folders exactly
/// as jumbled as before; moving files without showing the plan first is the other way to get it
/// wrong. So nothing moves until the list below has been read and confirmed.
class MergeAlbumsDialog extends StatefulWidget {
  final Album album;

  /// The album being absorbed into [album], for a Roon-style merge of two different records.
  final Album? absorb;
  const MergeAlbumsDialog({super.key, required this.album, this.absorb});

  @override
  State<MergeAlbumsDialog> createState() => _MergeAlbumsDialogState();
}

class _MergeAlbumsDialogState extends State<MergeAlbumsDialog> {
  bool _moveFiles = true;
  bool _busy = false;

  /// Worked out ONCE, when the dialog opens. Re-planning on every rebuild would read the folder
  /// again mid-run and could carry out something other than what was on screen when the user
  /// pressed the button — and it walks the disk, which has no business happening per frame.
  MergePlan _plan = const MergePlan(null, []);

  /// True while the PC is working out where the files would land. The confirm button waits for it:
  /// this dialog exists to say what will happen, and agreeing to a blank plan agrees to nothing.
  bool _planning = false;

  @override
  void initState() {
    super.initState();
    final lib = context.read<LibraryStore>();
    // Absorbing another record means moving its files, and only the machine holding them can say
    // where they would land — so that plan is awaited. Merging editions of one record touches no
    // files and stays immediate.
    _plan = widget.absorb != null ? const MergePlan(null, []) : lib.planMerge(widget.album);
    if (widget.absorb != null) {
      _planning = true;
      lib.planMoveAsync(widget.absorb!.tracks, widget.album).then((result) {
        if (!mounted) return;
        setState(() {
          _plan = MergePlan(result.folder, result.items);
          _planning = false;
        });
      }).catchError((Object _) {
        if (mounted) setState(() => _planning = false);
      });
    }
  }

  Future<void> _go() async {
    setState(() => _busy = true);
    final lib = context.read<LibraryStore>();
    final settings = context.read<AppSettings>();
    int moved;
    if (widget.absorb != null) {
      moved = await lib.moveTracksToAlbum(widget.absorb!.tracks, widget.album, settings,
          moveFiles: _moveFiles, plan: _plan.items);
    } else {
      // Regroup first: the tags are what decide, and the user's word beats them.
      await lib.mergeEditions(widget.album);
      moved = _moveFiles ? await lib.gatherAlbumFiles(widget.album, plan: _plan.items) : 0;
    }
    if (!mounted) return;
    _srcToast(context,
        moved > 0 ? 'Samengevoegd — $moved ${moved == 1 ? 'bestand' : 'bestanden'} verhuisd' : 'Samengevoegd');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    // Only what actually happens. A screen of "blijft staan" is noise between the user and the
    // three lines they need to check.
    final acts = plan.items.where((i) => i.fate != MoveFate.stays).toList();

    return Dialog(
      backgroundColor: _panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth(context, 720),
        height: dialogHeight(context, 620),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.absorb == null ? 'Uitgaves samenvoegen' : 'Albums samenvoegen',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              widget.absorb == null
                  ? '${widget.album.artist} · ${widget.album.title}'
                  : '${widget.absorb!.title} → ${widget.album.title}',
              style: const TextStyle(color: _muted, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(color: _panel2, borderRadius: BorderRadius.circular(9)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(plan.isNoop ? 'Alles staat al in één map' : plan.summary,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                if (plan.folder != null) ...[
                  const SizedBox(height: 3),
                  Text('Doelmap: ${plan.folder}',
                      style: const TextStyle(color: _muted, fontSize: 11.5)),
                ],
                if (plan.parking > 0) ...[
                  const SizedBox(height: 3),
                  Text(
                      'Bij dezelfde bestandsnaam houdt de beste kopie de naam; de andere gaat naar '
                      '$dupeFolder. Er wordt niets gewist.',
                      style: const TextStyle(color: _muted, fontSize: 11.5)),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: acts.isEmpty
                  ? const Center(
                      child: Text('Geen enkel bestand hoeft te verhuizen.',
                          style: TextStyle(color: _muted, fontSize: 12.5)))
                  : ListView.builder(
                      itemCount: acts.length,
                      itemBuilder: (_, i) {
                        final p = acts[i];
                        final dupe = p.fate == MoveFate.toDupes;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(dupe ? Icons.content_copy_rounded : Icons.arrow_forward_rounded,
                                size: 15, color: dupe ? _accent2 : _accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child:
                                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5)),
                                Text(
                                  // Where it comes from, and the folder it lands in. The full
                                  // target path is already in the header, so only the last part is
                                  // repeated here — for a duplicate that is "_dubbel" itself.
                                  '${File(p.from).parent.path}  →  '
                                  '${p.to == null ? '—' : File(p.to!).parent.path.split(Platform.pathSeparator).last}',
                                  maxLines: 2,
                                  style: TextStyle(
                                      color: dupe ? _accent2.withValues(alpha: .85) : _muted,
                                      fontSize: 10.5),
                                ),
                              ]),
                            ),
                          ]),
                        );
                      },
                    ),
            ),
            CheckboxListTile(
              value: _moveFiles,
              onChanged: (v) => setState(() => _moveFiles = v ?? true),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Bestanden mee verplaatsen', style: TextStyle(fontSize: 13)),
              subtitle: const Text('Uit: alleen de indeling verandert, de mappen blijven zoals ze zijn.',
                  style: TextStyle(color: _muted, fontSize: 11.5)),
            ),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                  autofocus: isTv,
                  onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuleren')),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _accent),
                onPressed: (_busy || _planning) ? null : _go,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Samenvoegen'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Everything that sounds like one thing — your own records first, then more of it.
///
/// A Discogs style is much finer than a genre: not "Electronic" but "Deep House", "Synth-pop",
/// "Happy Hardcore". That granularity is what makes this browsing by feel rather than by category,
/// which is the whole point of going deeper than Deezer's handful of genres.
class StylePage extends StatefulWidget {
  final String style;
  const StylePage(this.style, {super.key});

  @override
  State<StylePage> createState() => _StylePageState();
}

class _StylePageState extends State<StylePage> {
  List<CatalogAlbumHit>? _more;

  /// False shows the records that define a style; true shows what sits behind them.
  bool _deep = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Discogs can search by style directly, which is the one thing Deezer cannot do at all.
      final hits = await DiscogsService(context.read<AppSettings>()).searchByStyle(widget.style, deep: _deep);
      if (mounted) setState(() => _more = hits);
    } catch (_) {
      if (mounted) setState(() => _more = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final mine = lib.albumsWithStyle(widget.style);
    final have = {for (final a in mine) '${artistKey(a.artist)}|${normKey(a.title)}'};
    // Anything already owned is not a discovery — it is the shelf it came from.
    final more = [
      for (final h in _more ?? const <CatalogAlbumHit>[])
        if (!have.contains('${artistKey(h.artist)}|${normKey(h.album.title)}')) h
    ];

    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          backgroundColor: _bg,
          pinned: true,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).pop()),
          title: Text(widget.style, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
        if (mine.isNotEmpty) ...[
          SliverToBoxAdapter(child: _sectionTitle('In mijn bibliotheek', '${mine.length}')),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 175, mainAxisSpacing: 18, crossAxisSpacing: 18, childAspectRatio: .78),
              delegate: SliverChildBuilderDelegate((_, i) => AlbumCard(album: mine[i]), childCount: mine.length),
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: Row(children: [
            _sectionTitle('Meer in deze stijl', _more == null ? '…' : '${more.length}'),
            const Spacer(),
            // Two ways into a style: the records that define it, or everything behind them.
            Padding(
              padding: const EdgeInsets.only(right: 24),
              child: Row(children: [
                for (final d in const [false, true])
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: InkWell(
                      onTap: _deep == d
                          ? null
                          : () {
                              setState(() {
                                _deep = d;
                                _more = null;
                              });
                              _load();
                            },
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: _deep == d ? _accent : Colors.white.withValues(alpha: .06),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(d ? 'Minder bekend' : 'Bekend',
                            style: TextStyle(
                                fontSize: 12,
                                color: _deep == d ? Colors.white : _muted,
                                fontWeight: _deep == d ? FontWeight.w600 : FontWeight.w400)),
                      ),
                    ),
                  ),
              ]),
            ),
          ]),
        ),
        if (_more == null)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: _accent)),
            ),
          )
        else if (more.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Text('Niets nieuws gevonden in deze stijl.', style: TextStyle(color: _muted)),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 175, mainAxisSpacing: 18, crossAxisSpacing: 18, childAspectRatio: .78),
              delegate: SliverChildBuilderDelegate(
                (_, i) => _OnlineAlbumCard(more[i]),
                childCount: more.length,
              ),
            ),
          ),
      ]),
    );
  }

  Widget _sectionTitle(String t, String badge) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
        child: Row(children: [
          Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Text(badge, style: const TextStyle(color: _muted, fontSize: 12.5)),
        ]),
      );
}

/// An album that isn't yours yet — tapping it opens the sources for it.
class _OnlineAlbumCard extends StatelessWidget {
  final CatalogAlbumHit hit;
  const _OnlineAlbumCard(this.hit);

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AlbumBrowsePage(hit.artist, hit.album))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: LayoutBuilder(
              builder: (_, c) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _netCover(hit.album.cover, size: c.maxWidth, radius: 8),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(hit.album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          Text([hit.artist, if (hit.album.year != null) hit.album.year!].join(' · '),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 12)),
        ]),
      );
}

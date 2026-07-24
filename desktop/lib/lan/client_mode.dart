/// Which of the two the app is this time: the machine that owns the music, or one reading it.
///
/// One file so the answer is decided once and cannot drift. `main()` asks [resolveMode] before it
/// builds anything, and everything downstream reads [LibraryStore.isRemote].
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../paths.dart';
import '../settings.dart';
import 'client.dart';

/// Where the paired PC is remembered. Its own file rather than a key in the settings: it holds a
/// token, and it is written from the pairing screen at a moment when the settings may not have
/// been touched at all.
File get _pairedFile => appFile('paired_server.json');

/// The PC this device is paired with, or null.
Future<RemoteEndpoint?> loadPairedServer() async {
  try {
    final f = _pairedFile;
    if (!await f.exists()) return null;
    final j = jsonDecode(await f.readAsString());
    if (j is! Map<String, dynamic>) return null;
    return RemoteEndpoint.fromJson(j);
  } catch (e) {
    debugPrint('Paired server unreadable: $e');
    return null;
  }
}

Future<void> savePairedServer(RemoteEndpoint endpoint) async {
  try {
    await _pairedFile.writeAsString(jsonEncode(endpoint.toJson()));
  } catch (e) {
    // Pairing still worked for this run; it will simply be asked for again next start.
    debugPrint('Could not remember the paired server: $e');
  }
}

Future<void> forgetPairedServer() async {
  try {
    final f = _pairedFile;
    if (await f.exists()) await f.delete();
  } catch (_) {/* nothing to forget */}
}

/// Does this device hold the music?
///
/// Not "is this Windows". A Mac with a music folder configured is just as much the owner, and that
/// is the honest test — the app already works entirely off [AppSettings.musicRoot].
///
/// Windows is the exception: it answers yes even when the drive is not mounted this minute. The PC
/// is the library, and a USB disk that has not spun up yet must not silently turn the app into a
/// client of itself.
bool ownsTheMusic(AppSettings settings) {
  if (Platform.isIOS || Platform.isAndroid) return false;
  if (Platform.isWindows) return true;
  final root = settings.musicRoot.trim();
  if (root.isEmpty) return false;
  try {
    return Directory(root).existsSync();
  } catch (_) {
    return false;
  }
}

/// What `main()` needs to know at startup.
class StartupMode {
  /// True on the machine that scans the disk.
  final bool owner;

  /// The paired PC, when this is a client that has been paired. Null means the pairing screen.
  final RemoteEndpoint? endpoint;

  const StartupMode({required this.owner, this.endpoint});

  bool get needsPairing => !owner && endpoint == null;
}

Future<StartupMode> resolveMode(AppSettings settings) async {
  if (ownsTheMusic(settings)) return const StartupMode(owner: true);
  return StartupMode(owner: false, endpoint: await loadPairedServer());
}

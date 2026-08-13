/// What the lockscreen, Control Center and the media keys see.
///
/// libmpv plays the audio; this only tells the system what is playing and hands the buttons back
/// to [PlayerStore]. It is the one thing the SwiftUI app got for free from AVFoundation, and the
/// price of having a single codebase — so it is written once, here, rather than lived without.
///
/// Only where a system asks for it: iOS, macOS and Android. On Windows the app has its own window
/// with its own buttons, and `audio_service` has nothing to talk to there.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'auto_bladeren.dart';
import 'auto_hoezen.dart';
import 'models.dart';
import 'paths.dart';
import 'player.dart';

/// Waar de boom voor Android Auto vandaan komt. Null = geen bladeren; de app is dan zichtbaar in de
/// auto maar leeg — precies de toestand van vóór 11-08-2026.
///
/// Een functie en geen momentopname: een scan of een download verandert de bibliotheek onder de app
/// door, en Auto vraagt telkens opnieuw. Een kopie zou je door de bibliotheek van gisteren laten
/// bladeren.
///
/// Als losse haak in deze module en niet als veld op de handler: die wordt binnen `AudioService.init`
/// gebouwd, dus `main` heeft er nooit een verwijzing naar — en de handler is met opzet alleen voor
/// tests zichtbaar.
AutoBron Function()? autoBladerBron;

/// Voor het beginpunt van "Alles schudden". Zie [autoStartIndex].
final _rnd = Random();

/// Wat er moet gebeuren als iemand in de auto iets aantikt.
///
/// De index hoort erbij en is niet altijd 0: zie [autoStartIndex].
Future<void> Function(List<Track> rij, int start)? autoSpeel;

bool get _wantsSystemControls => Platform.isIOS || Platform.isMacOS || Platform.isAndroid;

/// Start publishing. Safe to call anywhere: it does nothing where there is nothing to publish to,
/// and a failure to register is never a reason for the app not to start.
Future<void> initNowPlaying(NowPlayingSource player, {Uint8List? Function(Track)? cover}) async {
  if (!_wantsSystemControls) return;
  try {
    await AudioService.init(
      builder: () => NowPlayingHandler(player, cover),
      config: const AudioServiceConfig(
        // debridmusic, not debridmedia — this named a different app entirely. Harmless while
        // Android was switched off; the moment it is on, this string is the notification channel
        // the user sees in Android's own settings.
        androidNotificationChannelId: 'com.debridmusic.app.playback',
        androidNotificationChannelName: 'Afspelen',
        androidNotificationOngoing: true,
        // The adaptive launcher icon is the default here, and as a status-bar glyph it renders as a
        // white blob. The monochrome layer of that same icon is what the shape was drawn for.
        androidNotificationIcon: 'drawable/ic_launcher_monochrome',
        // Artwork goes to the system as a decoded Bitmap over Binder. An embedded FLAC cover is
        // routinely 1500x1500, which is about 9 MB as ARGB_8888 — parcelled on every track change.
        // That is how you get a TransactionTooLargeException and a now-playing card that vanishes.
        // Both dimensions are required together; audio_service asserts on it.
        artDownscaleWidth: 512,
        artDownscaleHeight: 512,
      ),
    );
    await _claimAudioFocus(player);
  } catch (e) {
    // A missing platform implementation, or a second init during a hot restart. The app plays
    // either way; only the lockscreen goes quiet.
    debugPrint('Now Playing unavailable: $e');
  }
}

/// Tell Android that this app is the one making sound, and listen for being told otherwise.
///
/// Nothing in this app asked for audio focus before. media_kit plays through libmpv's OpenSL ES
/// output, which never requests it, and `audio_service` does not either — it publishes what is
/// playing, it does not arbitrate who may play. On a phone that is merely impolite. On a television
/// it is wrong in a way you notice every day: start Netflix from the Android TV home screen while a
/// record is on and both come out of the same HDMI cable at once, and nothing pauses for the
/// Assistant either.
///
/// `becomingNoisy` is the other half — on a TV that is the AVR being switched off or the input
/// changing, which should stop the music rather than leave it playing to nobody.
/// Wat er met de muziek moet gebeuren als iets anders geluid wil maken.
enum Onderbreking { niets, pauzeren, hervatten, dempen, ontdempen }

/// De regel, als pure functie zodat er een toets op past zonder auto, telefoon of speler.
///
/// **Wat er hiervoor stond: pauzeren bij álles, en nooit meer hervatten.** In een auto is dat
/// precies de ergernis die je elke rit hebt: Waze zegt "sla rechtsaf", de muziek valt stil en komt
/// niet terug. Terwijl het systeem het onderscheid gewoon meestuurt en niemand ernaar keek.
///
/// De drie soorten betekenen elk iets anders:
///
/// * [AudioInterruptionType.duck] — iets korts praat er even doorheen. Zachter zetten is beleefd;
///   pauzeren is te veel, want het duurt twee seconden.
/// * [AudioInterruptionType.pause] — een gesprek of een andere speler. Pauzeren, en achteraf weer
///   verder waar je was.
/// * [AudioInterruptionType.unknown] — we weten niet waaróm het stopte. Dan achteraf uit zichzelf
///   weer beginnen is erger dan stil blijven: dat is muziek die opeens aangaat in een stille auto.
///
/// [zelfGepauzeerd] is de tweede helft van dezelfde voorzichtigheid: alleen hervatten wat wíj hebben
/// stilgezet. Wie zelf op pauze drukte terwijl er een gesprek binnenkwam, wil niet dat het daarna
/// alsnog begint te spelen.
Onderbreking bijOnderbreking({
  required bool begint,
  required AudioInterruptionType soort,
  required bool speelt,
  required bool zelfGepauzeerd,
}) {
  if (begint) {
    if (!speelt) return Onderbreking.niets;
    return soort == AudioInterruptionType.duck ? Onderbreking.dempen : Onderbreking.pauzeren;
  }
  return switch (soort) {
    AudioInterruptionType.duck => Onderbreking.ontdempen,
    AudioInterruptionType.pause =>
      zelfGepauzeerd ? Onderbreking.hervatten : Onderbreking.niets,
    AudioInterruptionType.unknown => Onderbreking.niets,
  };
}

Future<void> _claimAudioFocus(NowPlayingSource player) async {
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    var zelfGepauzeerd = false;
    session.interruptionEventStream.listen((event) {
      switch (bijOnderbreking(
        begint: event.begin,
        soort: event.type,
        speelt: player.playing,
        zelfGepauzeerd: zelfGepauzeerd,
      )) {
        case Onderbreking.pauzeren:
          zelfGepauzeerd = true;
          player.playPause();
        case Onderbreking.hervatten:
          zelfGepauzeerd = false;
          player.playPause();
        case Onderbreking.dempen:
          player.zetDemping(true);
        case Onderbreking.ontdempen:
          player.zetDemping(false);
        case Onderbreking.niets:
          break;
      }
    });
    session.becomingNoisyEventStream.listen((_) {
      // De koptelefoon of de bluetoothspeaker viel weg. Niet hervatten als hij terugkomt: dan
      // begint de muziek uit de telefoonluidspreker in een stille kamer.
      zelfGepauzeerd = false;
      if (player.playing) player.playPause();
    });
    await session.setActive(true);
  } catch (e) {
    // Never a reason not to play. Without focus the old behaviour is what you get back.
    debugPrint('Audio focus unavailable: $e');
  }
}

/// Public only so it can be tested without a platform channel: [AudioService.init] needs one, the
/// handler itself does not.
@visibleForTesting
class NowPlayingHandler extends BaseAudioHandler with SeekHandler {
  NowPlayingHandler(this.player, this.coverFor) {
    player.addListener(_onChanged);
    _onChanged();
  }

  final NowPlayingSource player;
  final Uint8List? Function(Track)? coverFor;


  /// What was last published, so the artwork is only written to disk when something the lockscreen
  /// SHOWS has changed — this listener fires on every position tick.
  ///
  /// The path alone is not enough. Correcting the artist of the track that is playing changes no
  /// path, so this used to suppress the republish and Control Center kept the old name until the
  /// next song. The signature covers exactly the four fields [_publishItem] puts on screen.
  String? _publishedSig;
  bool _lastPlaying = false;
  Duration _lastPosition = Duration.zero;

  /// Ook shuffle en herhalen, anders loopt de auto achter op de app.
  ///
  /// De poort hieronder publiceert alleen bij een sprong in de positie of bij play/pauze — dat is
  /// met opzet, want deze luisteraar vuurt bij elke tik. Maar wie in de app op shuffle drukt
  /// verandert geen van beide, en dan blijft de knop in de auto in de oude stand staan.
  bool _lastShuffle = false;
  RepeatMode _lastRepeat = RepeatMode.off;

  /// Joined on a NUL, which cannot occur in any of the four. A printable separator would let a
  /// title that ends where an artist begins produce the signature of a different pair.
  static String _sigOf(Track t) => [t.path, t.title, t.artist, t.album].join('\u0000');

  void _onChanged() {
    final track = player.current;
    if (track == null) {
      if (_publishedSig != null) {
        _publishedSig = null;
        mediaItem.add(null);
        playbackState.add(PlaybackState(processingState: AudioProcessingState.idle));
      }
      return;
    }

    final sig = _sigOf(track);
    if (sig != _publishedSig) {
      _publishedSig = sig;
      unawaited(_publishItem(track));
    }

    // Position moves constantly; the system only needs it when it jumps or when play/pause flips.
    // Publishing every tick makes the lockscreen scrubber stutter and wakes the OS needlessly.
    final drift = (player.position - _lastPosition).inMilliseconds.abs();
    if (player.playing != _lastPlaying ||
        drift > 1200 ||
        player.shuffle != _lastShuffle ||
        player.repeat != _lastRepeat) {
      _lastPlaying = player.playing;
      _lastPosition = player.position;
      _lastShuffle = player.shuffle;
      _lastRepeat = player.repeat;
      _publishState();
    }
  }

  void _publishState() {
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        _shuffleKnop(),
        _herhaalKnop(),
      ],
      // setShuffleMode/setRepeatMode zeggen dat deze sessie de STANDEN kent. Dat is wat een
      // Automotive-hoofdunit (het scherm dat in de auto zelf zit) gebruikt om zijn eigen knoppen te
      // tekenen.
      //
      // Het is NIET wat Android Auto op een telefoon doet. Daar bleven de knoppen weg, gemeten in
      // de DHU: alleen vorige/play/volgende. Auto tekent op dat scherm custom actions — precies wat
      // Tidal op deze telefoon doet, te zien in `dumpsys media_session`: zijn sessie draagt
      // "Shuffle in-/uitschakelen" en "Beginnen met alle nummers herhalen" als custom action.
      // Vandaar allebei: de standen hierboven én de twee knoppen in [controls].
      systemActions: const {
        MediaAction.seek,
        MediaAction.setShuffleMode,
        MediaAction.setRepeatMode,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
      playing: player.playing,
      updatePosition: player.position,
      bufferedPosition: player.duration,
      speed: player.playing ? 1.0 : 0.0,
      queueIndex: null,
      shuffleMode: player.shuffle
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
      repeatMode: switch (player.repeat) {
        RepeatMode.one => AudioServiceRepeatMode.one,
        RepeatMode.all => AudioServiceRepeatMode.all,
        RepeatMode.off => AudioServiceRepeatMode.none,
      },
    ));
  }

  /// De namen waaronder de twee knoppen terugkomen in [customAction].
  static const knopShuffle = 'debridmusic.shuffle';
  static const knopHerhaal = 'debridmusic.herhaal';

  /// De shuffleknop, met de huidige stand in de tekening.
  ///
  /// Aan het pictogram te zien, want Auto tekent bij een custom action geen aan/uit-toestand: druk
  /// je erop zonder dat het plaatje verandert, dan weet je achter het stuur niet of je hem net aan
  /// of uit gezet hebt.
  MediaControl _shuffleKnop() => MediaControl.custom(
        androidIcon:
            player.shuffle ? 'drawable/ic_auto_shuffle_aan' : 'drawable/ic_auto_shuffle',
        label: player.shuffle ? 'Shuffle uit' : 'Shuffle aan',
        name: knopShuffle,
      );

  MediaControl _herhaalKnop() => MediaControl.custom(
        androidIcon: switch (player.repeat) {
          RepeatMode.one => 'drawable/ic_auto_herhaal_een',
          RepeatMode.all => 'drawable/ic_auto_herhaal_alles',
          RepeatMode.off => 'drawable/ic_auto_herhaal',
        },
        label: switch (player.repeat) {
          RepeatMode.one => 'Herhalen: dit nummer',
          RepeatMode.all => 'Herhalen: alles',
          RepeatMode.off => 'Herhalen uit',
        },
        name: knopHerhaal,
      );

  /// Een tik op een van die twee knoppen in de auto.
  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case knopShuffle:
        player.zetShuffle(!player.shuffle);
      case knopHerhaal:
        // Dezelfde ronde als de knop in de app: uit → alles → één → uit.
        player.zetHerhaal(switch (player.repeat) {
          RepeatMode.off => RepeatMode.all,
          RepeatMode.all => RepeatMode.one,
          RepeatMode.one => RepeatMode.off,
        });
      default:
        return super.customAction(name, extras);
    }
    // Meteen opnieuw publiceren, anders blijft het pictogram in de auto in de oude stand staan tot
    // er toevallig iets anders verandert.
    _publishState();
  }

  /// Shuffle vanuit de auto.
  ///
  /// Een stand en geen omschakeling: zie [NowPlayingSource.zetShuffle] voor waarom dat verschil
  /// hier telt. `group` bestaat in de norm maar niet in deze app — alles wat niet "geen" is, is
  /// gewoon schudden.
  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    player.zetShuffle(shuffleMode != AudioServiceShuffleMode.none);
    _publishState();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    player.zetHerhaal(switch (repeatMode) {
      AudioServiceRepeatMode.none => RepeatMode.off,
      AudioServiceRepeatMode.one => RepeatMode.one,
      // `group` hoort bij wachtrijen die deze app niet kent; hetzelfde als "alles".
      AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => RepeatMode.all,
    });
    _publishState();
  }

  Future<void> _publishItem(Track track) async {
    Uri? art;
    try {
      final bytes = coverFor?.call(track) ?? player.currentCover;
      if (bytes != null && bytes.length > 100) {
        // Op Android via de eigen provider, en niet als `file:`-pad. Dit is geen voorkeur maar een
        // eis van `audio_service`: zijn `setMetadata` laadt de hoes alléén als de URI met `content:`
        // begint (of als er een `artCacheFile` meekomt) — in élk ander geval zet hij `artBitmap` op
        // null en gaat er geen plaatje mee de mediasessie in.
        //
        // Gevolg zolang dit een file:-URI was: een grijs vlak op het nu-speelt-scherm in Android
        // Auto, en om precies dezelfde reden ook geen hoes op het vergrendelscherm. Het viel niet op
        // omdat de app in zijn eigen schermen wél een hoes toont — die leest de bytes rechtstreeks.
        art = autoHoesUri(bytes) ?? await _artFile(bytes);
      }
    } catch (_) {
      // No cover is a cosmetic loss; the title still shows.
    }
    mediaItem.add(MediaItem(
      id: track.path,
      title: track.title,
      artist: track.artist,
      album: track.album.isEmpty ? null : track.album,
      duration: track.duration ?? player.duration,
      artUri: art,
    ));
    _publishState();
  }

  /// The system wants a URL for the artwork, not bytes — so the cover goes to a file named after
  /// its own contents. Same cover, same file: an album played twice writes nothing the second
  /// time, and the folder cannot grow past one file per distinct cover.
  Future<Uri?> _artFile(Uint8List bytes) async {
    final dir = appSubdir('nowplaying');
    final file = File('${dir.path}${Platform.pathSeparator}'
        '${md5.convert(bytes).toString().substring(0, 16)}.jpg');
    if (!await file.exists()) await file.writeAsBytes(bytes);
    return Uri.file(file.path);
  }

  // The store has one toggle, the system sends two distinct commands. Checking the state first is
  // not a nicety: a "play" arriving while already playing would otherwise pause the music, which
  // is exactly what happens when a headset reconnects and asks for playback.
  @override
  Future<void> play() async {
    if (!player.playing) player.playPause();
  }

  @override
  Future<void> pause() async {
    if (player.playing) player.playPause();
  }

  @override
  Future<void> skipToNext() => player.next();

  @override
  Future<void> skipToPrevious() => player.prev();

  @override
  Future<void> seek(Duration position) async => player.seek(position);

  @override
  Future<void> stop() async {
    if (player.playing) player.playPause();
    await super.stop();
  }

  // ── Android Auto ───────────────────────────────────────────────────────────
  //
  // Auto praat met de MediaBrowserService die audio_service al draait, en vraagt maar twee dingen:
  // "wat zit er onder deze knoop" en "speel dit id". De boom zelf staat in auto_bladeren.dart, als
  // pure functie, zodat hij te toetsen is zonder auto, telefoon of speler. Hier alleen de aansluiting.
  //
  // Zonder [autoBron] gebeurt er niets bijzonders: dan is de app in de auto zichtbaar maar leeg, en
  // dat is precies de toestand van vóór vandaag.

  @override
  Future<List<MediaItem>> getChildren(String parentMediaId, [Map<String, dynamic>? options]) async {
    final bron = autoBladerBron?.call();
    if (bron == null) return const [];
    return autoKinderenMetLeegmelding(parentMediaId, bron);
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    final bron = autoBladerBron?.call();
    if (bron == null) return null;
    // Het item zelf komt uit de lijst waar het in staat; Auto vraagt hier bijvoorbeeld naar om een
    // hoes te tonen bij wat er speelt.
    for (final knoop in [AutoId.verder, AutoId.recent, AutoId.favorieten, AutoId.albums]) {
      for (final i in autoKinderen(knoop, bron)) {
        if (i.id == mediaId) return i;
      }
    }
    return null;
  }

  @override
  Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
    final bron = autoBladerBron?.call();
    if (bron == null) return;
    final rij = autoSpeellijstVoor(mediaId, bron);
    // Leeg betekent "hier valt niets te spelen". Dan hoort er NIETS te gebeuren — de vorige wachtrij
    // laten doorlopen leest achter het stuur als "hij speelt iets anders dan ik koos".
    if (rij.isEmpty) return;
    // "Alles schudden" is hetzelfde nummerlijstje met shuffle aan. Vóór het spelen, zodat de
    // wachtrij meteen geschud opgebouwd wordt in plaats van eerst op alfabet te beginnen.
    if (mediaId == AutoId.schudAlles) player.zetShuffle(true);
    await autoSpeel?.call(rij, autoStartIndex(mediaId, rij.length, _rnd.nextInt));
  }
}

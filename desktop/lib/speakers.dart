/// Choosing where the music comes out.
///
/// The engine for this has been in the app the whole time — SSDP discovery, SOAP to a renderer, a
/// direct handover to a television running this app — and none of it was reachable, because the
/// picker went away with the SwiftUI app and was never rebuilt. This is the steering wheel.
///
/// The PC does the sending. That is not an implementation detail you can move: the audio then goes
/// straight from the machine holding the files to the speaker, instead of being relayed by
/// whatever you happened to tap on, and it sidesteps the multicast entitlement an iPad would need
/// to run SSDP itself.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'lan/client.dart';

const _panel = Color(0xFF181B26);
const _line = Color(0xFF272B3A);
const _muted = Color(0xFF9AA0B4);
const _accent = Color(0xFF7C5CFF);
const _accent2 = Color(0xFF00D4C8);

/// Where the music is playing right now, as far as this device knows.
///
/// Held here rather than in the player: the player plays on THIS device, and casting is precisely
/// the case where it does not. Nothing about libmpv changes when a speaker is chosen.
class SpeakerTarget extends ChangeNotifier {
  CastDevice? _device;

  /// Null means this device's own output — the ordinary case, and the one you return to.
  CastDevice? get device => _device;

  bool get isCasting => _device != null;

  /// The client to steer through, set once by main. Null on the machine that holds the music, which
  /// is also the machine that never needs it.
  RemoteClient? client;

  CastStatus? _status;

  /// What the speaker last told us. Null until the first answer arrives, and again if it stops
  /// answering — which is not the same as "stopped", and must not be drawn as one.
  CastStatus? get status => _status;

  Timer? _poll;

  /// The real answer, and when it arrived. Between polls the position is worked out from these two
  /// rather than left to sit still for two seconds: interpolating from a measured anchor is not the
  /// same as inventing a bar out of nothing, and it is never more than one poll out.
  Duration? _anchorPosition;
  DateTime? _anchorAt;

  /// Set while a drag is in progress, so an answer that is already in flight — describing where the
  /// speaker was BEFORE the seek — cannot yank the handle back under the finger.
  Duration? _scrubbing;

  /// Where to draw the handle: what the finger is doing, else the anchor carried forward.
  Duration? get position {
    final scrubbing = _scrubbing;
    if (scrubbing != null) return scrubbing;
    final anchor = _anchorPosition, at = _anchorAt;
    if (anchor == null || at == null) return null;
    if (_status?.playing != true) return anchor;
    final ahead = anchor + DateTime.now().difference(at);
    final total = _status?.duration;
    return total != null && total > Duration.zero && ahead > total ? total : ahead;
  }

  Duration? get duration => _status?.duration;

  /// Whether the SPEAKER is playing. The local player is deliberately silent while casting, so its
  /// own flag says nothing about the record you are listening to.
  bool get isPlaying => _status?.playing ?? false;

  int get volume => _status?.volume ?? 50;

  bool get hasVolume => _status?.volume != null;

  void select(CastDevice? d) {
    if (_device?.id == d?.id) return;
    _device = d;
    _status = null;
    _anchorPosition = null;
    _anchorAt = null;
    _scrubbing = null;
    notifyListeners();
    if (d == null) {
      _poll?.cancel();
      _poll = null;
    } else {
      _startPolling();
    }
  }

  /// Ask the speaker where it is, every two seconds.
  ///
  /// Two, not one: each poll is a SOAP round trip to embedded hardware, and the bar between polls
  /// is carried by [position] rather than by asking more often.
  void _startPolling() {
    _poll?.cancel();
    unawaited(refresh(withVolume: true));
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(refresh()));
  }

  Future<void> refresh({bool withVolume = false}) async {
    final device = _device, c = client;
    if (device == null || c == null) return;
    final fresh = await c.castStatus(device.id, withVolume: withVolume);
    // Selected somewhere else while this was in flight — that answer is about a speaker nobody is
    // looking at any more.
    if (fresh == null || _device?.id != device.id) return;
    // Keep the volume we knew: a poll that did not ask for it must not read as "no volume control".
    _status = fresh.volume == null && _status?.volume != null
        ? CastStatus(
            casting: fresh.casting,
            position: fresh.position,
            duration: fresh.duration,
            playing: fresh.playing,
            volume: _status!.volume,
            index: fresh.index,
            queueLength: fresh.queueLength,
          )
        : fresh;
    if (fresh.position != null) {
      _anchorPosition = fresh.position;
      _anchorAt = DateTime.now();
    }
    notifyListeners();
  }

  Future<void> _send(String action, {int? value}) async {
    final device = _device, c = client;
    if (device == null || c == null) return;
    await c.castControl(device.id, action, value: value);
    // Ask straight away rather than waiting for the next tick: a button that takes two seconds to
    // look like it worked reads as a button that did not.
    await refresh();
  }

  Future<void> playPause() => _send(isPlaying ? 'pause' : 'play');

  Future<void> next() => _send('next');

  Future<void> previous() => _send('previous');

  /// While a finger is on the scrubber. Nothing is sent yet — a seek per pixel would flood the
  /// speaker and land somewhere behind where you let go.
  void scrubTo(Duration to) {
    _scrubbing = to;
    notifyListeners();
  }

  Future<void> seekTo(Duration to) async {
    _scrubbing = to;
    // Carry the handle at the new spot immediately, so it does not snap back for one poll.
    _anchorPosition = to;
    _anchorAt = DateTime.now();
    notifyListeners();
    await _send('seek', value: to.inSeconds);
    _scrubbing = null;
    notifyListeners();
  }

  Future<void> setVolume(int v) async {
    final clamped = v.clamp(0, 100);
    // Shown at once; the speaker confirms a moment later.
    final was = _status;
    if (was != null) {
      _status = CastStatus(
        casting: was.casting,
        position: was.position,
        duration: was.duration,
        playing: was.playing,
        volume: clamped,
        index: was.index,
        queueLength: was.queueLength,
      );
      notifyListeners();
    }
    await _send('volume', value: clamped);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _poll = null;
    super.dispose();
  }
}

/// The sheet you get from the speaker button.
class SpeakerPicker extends StatefulWidget {
  const SpeakerPicker({
    super.key,
    required this.client,
    required this.target,
    required this.thisDeviceName,
    this.onPickedRemote,
    this.onPickedHere,
  });

  final RemoteClient client;
  final SpeakerTarget target;
  final String thisDeviceName;

  /// Start the current queue on the chosen device.
  final void Function(CastDevice device)? onPickedRemote;

  /// Bring it back to this device's own output.
  final VoidCallback? onPickedHere;

  @override
  State<SpeakerPicker> createState() => _SpeakerPickerState();
}

class _SpeakerPickerState extends State<SpeakerPicker> {
  List<CastDevice> _devices = const [];
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    // Discovery is a three-second SSDP wait plus a sweep of the subnet, so the list arrives late
    // enough that a spinner is the honest thing to show.
    final found = await widget.client.castDevices();
    if (!mounted) return;
    setState(() {
      _devices = found;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final here = widget.target.device == null;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(children: [
              const Icon(Icons.speaker_rounded, size: 20, color: _accent),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Afspelen op',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'Opnieuw zoeken',
                onPressed: _busy ? null : _load,
              ),
            ]),
          ),
          const Divider(color: _line, height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
              children: [
                _tile(
                  icon: Icons.smartphone_rounded,
                  title: widget.thisDeviceName,
                  subtitle: 'Dit apparaat',
                  selected: here,
                  onTap: () {
                    widget.target.select(null);
                    widget.onPickedHere?.call();
                    Navigator.pop(context);
                  },
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 22),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: _accent),
                      ),
                    ),
                  )
                else if (_devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 18, 20, 22),
                    child: Text(
                      'Niets gevonden. Staan de speakers aan en hangen ze aan hetzelfde netwerk?',
                      style: TextStyle(color: _muted, height: 1.4, fontSize: 13),
                    ),
                  )
                else
                  for (final d in _devices)
                    _tile(
                      icon: d.playsUntouched ? Icons.tv_rounded : Icons.speaker_group_rounded,
                      title: d.name,
                      subtitle: _describe(d),
                      selected: widget.target.device?.id == d.id,
                      onTap: () {
                        widget.target.select(d);
                        widget.onPickedRemote?.call(d);
                        Navigator.pop(context);
                      },
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// What this speaker will actually do with the file.
  ///
  /// The number matters and is usually hidden: a Sonos stops at 48 kHz, so a 24/96 record is
  /// converted on the way there. Better said before you press play than wondered about after.
  static String _describe(CastDevice d) {
    if (d.playsUntouched) return 'Speelt lossless door, zonder omzetten';
    if (d.maxSampleRate > 0) {
      final khz = (d.maxSampleRate / 1000).toStringAsFixed(d.maxSampleRate % 1000 == 0 ? 0 : 1);
      return '${d.model.isEmpty ? 'Speaker' : d.model} · tot $khz kHz';
    }
    return d.model.isEmpty ? 'Speaker' : d.model;
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      ListTile(
        leading: Icon(icon, color: selected ? _accent : _muted),
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        subtitle: Text(subtitle,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 12)),
        trailing: selected ? const Icon(Icons.check_rounded, color: _accent2) : null,
        selected: selected,
        selectedTileColor: _accent.withValues(alpha: .10),
        onTap: onTap,
      );
}

/// Open the picker as a sheet.
Future<void> showSpeakerPicker(
  BuildContext context, {
  required RemoteClient client,
  required SpeakerTarget target,
  required String thisDeviceName,
  void Function(CastDevice)? onPickedRemote,
  VoidCallback? onPickedHere,
}) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SpeakerPicker(
        client: client,
        target: target,
        thisDeviceName: thisDeviceName,
        onPickedRemote: onPickedRemote,
        onPickedHere: onPickedHere,
      ),
    );

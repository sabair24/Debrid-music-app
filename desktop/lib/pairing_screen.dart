/// The first thing you see on a Mac or an iPad that has never met your PC.
///
/// It replaces the SwiftUI pairing view, and does the same three things: find the PC by itself,
/// take the six digits off its screen, and fall back to typing an address when the network refuses
/// to cooperate. The PC end of this — `POST /pair`, five minutes, five attempts — has not changed
/// and is already proven on the Shield and the iPad.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'lan/client.dart';
import 'lan/discovery.dart';
import 'tv.dart';
import 'ui/kleuren.dart';

const _bg = kAchtergrond;
const _panel = kPaneel;
const _panel2 = kPaneelHoog;
const _text = kTekst;
const _muted = kGedempt;
const _accent = kAccent;

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key, required this.deviceName, required this.onPaired});

  /// What the PC will list this device as.
  final String deviceName;

  /// Called once, with a usable endpoint. The app restarts itself into client mode from here.
  final void Function(RemoteEndpoint) onPaired;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  List<FoundServer> _found = const [];
  bool _searching = true;
  bool _pairing = false;
  String? _error;

  /// The PC being paired with — chosen from the list, or resolved from what was typed.
  Uri? _target;
  String? _targetName;

  final _codeController = TextEditingController();
  final _hostController = TextEditingController();
  bool _manual = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _hostController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _error = null;
    });
    final found = await LanBrowser.find();
    if (!mounted) return;
    setState(() {
      _found = found;
      _searching = false;
      // Only one PC on the network is the ordinary case, so save a tap.
      if (found.length == 1 && _target == null) {
        _target = found.first.baseUrl;
        _targetName = found.first.name;
      }
    });
  }

  Future<void> _useTypedAddress() async {
    final uri = RemoteEndpoint.parseHost(_hostController.text);
    if (uri == null) {
      setState(() => _error = 'Dat lijkt geen adres. Bijvoorbeeld: 192.168.0.216');
      return;
    }
    setState(() {
      _error = null;
      _searching = true;
    });
    // Ask before pairing, so "verkeerd adres" and "verkeerde code" are two different messages
    // instead of one shrug.
    final health = await RemoteClient.health(uri);
    if (!mounted) return;
    setState(() {
      _searching = false;
      if (health == null) {
        _error = 'Op $uri antwoordt geen DebridMusic. Staat de app op de pc open?';
      } else {
        _target = uri;
        _targetName = health.name.isEmpty ? uri.host : health.name;
      }
    });
  }

  Future<void> _pair() async {
    final target = _target;
    final code = _codeController.text.replaceAll(RegExp(r'\D'), '');
    if (target == null) return;
    if (code.length != 6) {
      setState(() => _error = 'De code is zes cijfers.');
      return;
    }
    setState(() {
      _pairing = true;
      _error = null;
    });
    try {
      final endpoint = await RemoteClient.pair(target, code, deviceName: widget.deviceName);
      if (!mounted) return;
      widget.onPaired(endpoint);
    } on RemoteException catch (e) {
      if (!mounted) return;
      setState(() {
        _pairing = false;
        _error = e.message;
        _codeController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.library_music_rounded, size: 56, color: _accent),
                  const SizedBox(height: 18),
                  const Text(
                    'Verbind met je pc',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _text, fontSize: 26, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Je muziek staat op je Windows-pc. Open daar DebridMusic en ga naar '
                    'Instellingen → Apparaat koppelen voor de code.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted, fontSize: 14, height: 1.45),
                  ),
                  const SizedBox(height: 26),
                  if (_target == null) ..._chooseServer() else ..._enterCode(),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _ErrorBox(_error!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _chooseServer() => [
        if (_searching && _found.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 26),
            child: Column(children: [
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: _accent),
              ),
              SizedBox(height: 14),
              Text('Zoeken op je netwerk…', style: TextStyle(color: _muted)),
            ]),
          )
        else if (_found.isEmpty && !_manual)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14)),
            child: const Text(
              'Geen pc gevonden. Staat DebridMusic open op je pc, en hangen beide apparaten '
              'aan hetzelfde netwerk?',
              style: TextStyle(color: _muted, height: 1.45),
            ),
          ),
        for (final s in _found) _ServerTile(s, onTap: () {
          setState(() {
            _target = s.baseUrl;
            _targetName = s.name;
          });
        }),
        const SizedBox(height: 18),
        if (_manual) ...[
          TextField(
            controller: _hostController,
            autocorrect: false,
            style: const TextStyle(color: _text),
            decoration: _fieldStyle('Adres van de pc', hint: '192.168.0.216'),
            onSubmitted: (_) => _useTypedAddress(),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _searching ? null : _useTypedAddress,
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Verbinden'),
          ),
        ] else
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton(
              onPressed: _searching ? null : _search,
              child: Text(_searching ? 'Zoeken…' : 'Opnieuw zoeken',
                  style: const TextStyle(color: _muted)),
            ),
            const Text('·', style: TextStyle(color: _muted)),
            TextButton(
              onPressed: () => setState(() => _manual = true),
              child: const Text('Adres invoeren', style: TextStyle(color: _muted)),
            ),
          ]),
      ];

  List<Widget> _enterCode() => [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            const Icon(Icons.computer_rounded, color: _accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(_targetName ?? _target!.host,
                  style: const TextStyle(color: _text, fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: _pairing
                  ? null
                  : () => setState(() {
                        _target = null;
                        _error = null;
                      }),
              child: const Text('Wijzig', style: TextStyle(color: _muted)),
            ),
          ]),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _codeController,
          autofocus: !isTv,
          enabled: !_pairing,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          style: const TextStyle(
            color: _text,
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: 12,
          ),
          decoration: _fieldStyle('Code van je pc', hint: '000000', counter: true),
          onSubmitted: (_) => _pair(),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _pairing ? null : _pair,
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _pairing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                )
              : const Text('Koppelen', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ];

  InputDecoration _fieldStyle(String label, {String? hint, bool counter = false}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: counter ? '' : null,
        labelStyle: const TextStyle(color: _muted),
        hintStyle: TextStyle(color: _muted.withValues(alpha: .4)),
        filled: true,
        fillColor: _panel2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );
}

class _ServerTile extends StatelessWidget {
  const _ServerTile(this.server, {required this.onTap});
  final FoundServer server;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            // 44 logical pixels of height minimum: this is the first thing a finger touches on an
            // iPad, and a row sized for a mouse is a row you miss.
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              const Icon(Icons.computer_rounded, color: _accent, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(server.name,
                        style: const TextStyle(color: _text, fontWeight: FontWeight.w600)),
                    Text(
                      server.trackCount > 0
                          ? '${server.baseUrl.host} · ${server.trackCount} nummers'
                          : server.baseUrl.host,
                      style: const TextStyle(color: _muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _muted),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF3A1E24),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline_rounded, color: Color(0xFFFF8A9B), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message,
              style: const TextStyle(color: Color(0xFFFFC9D1), height: 1.4, fontSize: 13.5)),
        ),
      ]),
    );
  }
}

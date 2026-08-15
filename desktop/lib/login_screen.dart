/// Signing in, on a device that does not hold the music.
///
/// Replaces the six digits. What it buys is not only convenience: the code handed every device the
/// same shared secret, so a single device could never be cut off on its own. Here the account says
/// who you are and the PC issues a token to this device alone.
///
/// The address field stays. Firestore is how a device normally finds the PC, but a network without
/// internet, or a Firebase that is having a bad day, must not leave you unable to reach a machine
/// sitting two metres away.
library;

import 'package:flutter/material.dart';

import 'cloud/cloud_session.dart';
import 'lan/client.dart';
import 'tv.dart';
import 'ui/kleuren.dart';

const _bg = kAchtergrond;
const _panel2 = kPaneelHoog;
const _text = kTekst;
const _muted = kGedempt;
const _accent = kAccent;

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.session,
    required this.onConnected,
    this.onUseCode,
  });

  final CloudSession session;

  /// Called once the PC has issued a token for this device.
  final void Function(RemoteEndpoint) onConnected;

  /// The way back to the old pairing code, kept as an escape hatch.
  final VoidCallback? onUseCode;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode(skipTraversal: isTv, debugLabel: 'login e-mail');
  final _passwordFocus = FocusNode(skipTraversal: isTv, debugLabel: 'login wachtwoord');

  bool _busy = false;
  bool _register = false;
  String? _error;

  /// Set while the PC has not answered the access request — which is simply what it looks like
  /// when the PC is switched off.
  String? _waiting;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Vul je e-mailadres en wachtwoord in.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _waiting = null;
    });
    try {
      if (_register) {
        await widget.session.register(email, password);
      } else {
        await widget.session.signIn(email, password);
      }
      await _findServer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  /// After signing in: which PC, and may this device use it?
  Future<void> _findServer() async {
    final servers = await widget.session.servers();
    if (!mounted) return;

    if (servers.isEmpty) {
      // Almost always the first-run ordering problem, and worth naming rather than showing a
      // spinner: the PC has to sign in too before it can hand out anything.
      setState(() {
        _busy = false;
        _error = 'Nog geen pc gevonden onder dit account.\n'
            'Log op je pc in met hetzelfde account — daarna verschijnt hij hier vanzelf.';
      });
      return;
    }

    // The freshest one that says it is online; otherwise whichever was seen last.
    servers.sort((a, b) => (b.lastSeen ?? DateTime(0)).compareTo(a.lastSeen ?? DateTime(0)));
    final server = servers.firstWhere((s) => s.online && s.isFresh, orElse: () => servers.first);

    setState(() => _waiting = server.isFresh
        ? 'Toegang aanvragen bij ${server.name}…'
        : '${server.name} lijkt uit te staan. Je aanvraag blijft klaarstaan.');

    final token = await widget.session.awaitAccess(server.id);
    if (!mounted) return;

    if (token == null) {
      setState(() {
        _busy = false;
        _waiting = null;
        _error = 'Je pc heeft nog niet geantwoord. Zet hem aan en probeer opnieuw — '
            'je aanvraag staat er al, dus hij pikt het vanzelf op.';
      });
      return;
    }

    // Every address the PC published; the one that answers wins. A machine with a VPN or Hyper-V
    // has several, and only this device knows which of them it can reach.
    for (final url in server.urls) {
      final base = RemoteEndpoint.parseHost(url);
      if (base == null) continue;
      if (await RemoteClient.health(base) != null) {
        widget.onConnected(RemoteEndpoint(baseUrl: base, token: token, name: server.name));
        return;
      }
    }

    setState(() {
      _busy = false;
      _waiting = null;
      _error = 'Je pc gaf toegang, maar is op dit netwerk niet te bereiken.\n'
          'Hangen beide apparaten aan hetzelfde netwerk?';
    });
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
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.library_music_rounded, size: 56, color: _accent),
                  const SizedBox(height: 18),
                  Text(
                    _register ? 'Maak een account' : 'Inloggen',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _text, fontSize: 26, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Log op elk apparaat in met hetzelfde account. Je muziek blijft op je pc — '
                    'die geeft dit apparaat toegang zodra je bent ingelogd.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted, fontSize: 14, height: 1.45),
                  ),
                  const SizedBox(height: 26),
                  // Reachable, but skipped when arrowing: focus opens the leanback keyboard, and
                  // the keyboard then swallows every arrow press. OK on the field is what opens
                  // it, which is the same bargain the library search makes.
                  MaybePressable(
                    enabled: isTv,
                    onPressed: _emailFocus.requestFocus,
                    borderRadius: BorderRadius.circular(12),
                    child: TextField(
                      controller: _email,
                      focusNode: _emailFocus,
                      enabled: !_busy,
                      autocorrect: false,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(color: _text),
                      decoration: _field('E-mailadres'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  MaybePressable(
                    enabled: isTv,
                    onPressed: _passwordFocus.requestFocus,
                    borderRadius: BorderRadius.circular(12),
                    child: TextField(
                      controller: _password,
                      focusNode: _passwordFocus,
                      enabled: !_busy,
                      obscureText: true,
                      style: const TextStyle(color: _text),
                      decoration: _field('Wachtwoord'),
                      onSubmitted: (_) => _busy ? null : _submit(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    // Guarded on a television, disabled everywhere else.
                    //
                    // While _busy, both fields and both links below are disabled too. A disabled
                    // Material widget leaves the traversal order, so with onPressed:null this
                    // screen held NOT ONE focusable widget — and awaitAccess waits up to a minute
                    // on a PC that may be switched off. A remote pointing at a screen with nothing
                    // to focus is a frozen app, whatever the spinner says.
                    onPressed: (!isTv && _busy)
                        ? null
                        : () {
                            if (_busy) return;
                            _submit();
                          },
                    // Where the highlight starts on a TV: on the button, not in a text field —
                    // a focused field raises the on-screen keyboard over everything before you
                    // have read a word of the screen.
                    autofocus: isTv,
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                          )
                        : Text(_register ? 'Account aanmaken' : 'Inloggen',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  if (_waiting != null) ...[
                    const SizedBox(height: 16),
                    Row(children: [
                      const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _muted),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_waiting!,
                            style: const TextStyle(color: _muted, fontSize: 13, height: 1.4)),
                      ),
                    ]),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _ErrorBox(_error!),
                  ],
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _register = !_register;
                                _error = null;
                              }),
                      child: Text(
                        _register ? 'Ik heb al een account' : 'Nog geen account?',
                        style: const TextStyle(color: _muted),
                      ),
                    ),
                    if (widget.onUseCode != null) ...[
                      const Text('·', style: TextStyle(color: _muted)),
                      TextButton(
                        onPressed: _busy ? null : widget.onUseCode,
                        child: const Text('Koppelen met een code',
                            style: TextStyle(color: _muted)),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _field(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _muted),
        filled: true,
        fillColor: _panel2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );
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

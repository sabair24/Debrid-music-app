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
import 'cloud/device_identity.dart';
import 'lan/client.dart';
import 'lan/discovery.dart';
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
  final _adres = TextEditingController();
  final _emailFocus = FocusNode(skipTraversal: isTv, debugLabel: 'login e-mail');
  final _passwordFocus = FocusNode(skipTraversal: isTv, debugLabel: 'login wachtwoord');
  final _adresFocus = FocusNode(skipTraversal: isTv, debugLabel: 'login adres');

  bool _busy = false;
  bool _register = false;

  /// De laatste foutmelding, of null.
  ///
  /// Met een eigen setter, zodat [_toonAdres] omhoog gaat op élke plek waar iets misging — het zijn
  /// er acht, en de negende die iemand erbij zet zou het anders vergeten.
  String? _errorVeld;
  String? get _error => _errorVeld;
  set _error(String? melding) {
    _errorVeld = melding;
    if (melding != null) _toonAdres = true;
  }

  /// Set while the PC has not answered the access request — which is simply what it looks like
  /// when the PC is switched off.
  String? _waiting;

  /// Wat een pc op dít netwerk zei toen hij dit toestel weigerde. Zie [_zoekOpNetwerk].
  String? _netwerkUitleg;

  /// Staat het adresveld eenmaal open, dan blijft het open. Zie [_probeerAdres].
  ///
  /// **Niet aan [_error] hangen, en dat is geen detail.** Dat was de eerste versie, en die at
  /// zichzelf op: [_probeerAdres] wist de foutmelding voordat hij begint, dus het veld waar je net
  /// op tikte verdween onder je vingers — inclusief de knop en de melding "verbinden met…". Wat je
  /// overhoudt is een scherm dat lijkt te doen alsof er niets gebeurde.
  ///
  /// Eén kant op: er is geen reden om hem weer weg te halen. Wie hier eenmaal is, heeft het nodig
  /// gehad, en de volgende poging is er dan meteen.
  bool _toonAdres = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _adres.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _adresFocus.dispose();
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
  ///
  /// **Twee wegen, en de tweede is er sinds 02-09-2026.** De eerste vraagt aan de accountdatabase
  /// welke pc's er onder dit account staan; die werkt overal waar je pc een bereikbaar adres
  /// publiceerde. Maar toen die dienst zijn daglimiet bereikte, was er GEEN tweede weg — en dan sta
  /// je buiten je eigen muziek met je pc twee meter verderop. *"dit ben ik echt beu."*
  ///
  /// De tweede weg is dat lokale netwerk zelf: de pc roept zich daar toch al om. Zie
  /// [_zoekOpNetwerk] en `lan/accountkoppeling.dart`.
  Future<void> _findServer() async {
    List<CloudServer> servers = const [];
    Object? databaseFout;
    try {
      servers = await widget.session.servers();
    } catch (e) {
      // NIET doorgooien. Dat deed hij, en daarmee was een volle database een dichte deur.
      databaseFout = e;
    }
    if (!mounted) return;

    if (servers.isEmpty) {
      // Eerst het netwerk, dán pas een foutmelding. Ook als de database gewoon leeg was: de pc kan
      // wel degelijk naast je staan zonder ooit iets gepubliceerd te hebben.
      setState(() => _waiting = 'Zoeken naar je pc op dit netwerk…');
      if (await _zoekOpNetwerk()) return;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _waiting = null;
        _error = _netwerkUitleg ??
            (databaseFout != null
                ? '$databaseFout\n\nEn op dit netwerk is je pc ook niet gevonden. '
                    'Staat hij aan en hangt hij aan dezelfde wifi?'
                : 'Nog geen pc gevonden onder dit account.\n'
                    'Log op je pc in met hetzelfde account — daarna verschijnt hij hier vanzelf.');
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
      // De aanvraag liep via de accountdatabase en die is niet opgepikt. Dat zegt niets over de
      // pc: staat hij naast je op hetzelfde wifi, dan kan hij zelf antwoorden. Dit is precies het
      // geval waarin je vroeger vastliep terwijl alles er stond.
      setState(() => _waiting = 'Geen antwoord. Zoeken naar je pc op dit netwerk…');
      if (await _zoekOpNetwerk()) return;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _waiting = null;
        _error = _netwerkUitleg ??
            'Je pc heeft nog niet geantwoord. Zet hem aan en probeer opnieuw — '
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

    // De pc gaf toegang maar geen van zijn gepubliceerde adressen antwoordt. Dat gebeurt zodra hij
    // een ander ip kreeg dan hij ooit opschreef — dan is het adres oud, niet de pc weg. Hij roept
    // zich op dit netwerk gewoon om.
    setState(() => _waiting = 'Adres klopt niet meer. Zoeken op dit netwerk…');
    if (await _zoekOpNetwerk()) return;
    if (!mounted) return;

    setState(() {
      _busy = false;
      _waiting = null;
      _error = _netwerkUitleg ??
          'Je pc gaf toegang, maar is op dit netwerk niet te bereiken.\n'
              'Hangen beide apparaten aan hetzelfde netwerk?';
    });
  }

  /// De pc zelf zoeken op het lokale netwerk, en binnenkomen op grond van je ACCOUNT.
  ///
  /// Geen zes cijfers en geen accountdatabase: het toestel laat zijn verse inlogsleutel zien en de
  /// pc vraagt bij Google van wie die is. Zie `lan/accountkoppeling.dart` voor de beslissing aan de
  /// andere kant.
  ///
  /// Geeft true als er verbonden is. Lukt het niet, dan blijft in [_netwerkUitleg] staan wat de pc
  /// er zélf van zei — dat is de enige zin die verder helpt, en die mag niet in een `catch`
  /// verdwijnen. Wat er verder misgaat levert false op en geen fout: dit is een tweede kans, en een
  /// mislukte tweede kans hoort de melding van de eerste niet te overschrijven.
  Future<bool> _zoekOpNetwerk() async {
    _netwerkUitleg = null;
    try {
      final sleutel = await widget.session.idToken();
      if (sleutel.isEmpty) return false;
      final ik = await thisDevice();
      final gevonden = await LanBrowser.find();
      for (final pc in gevonden) {
        RemoteEndpoint? toegang;
        try {
          toegang = await RemoteClient.pairMetAccount(
            pc.baseUrl,
            idToken: sleutel,
            deviceId: ik.id,
            deviceName: ik.name,
            platform: ik.platform,
          );
        } on RemoteException catch (e) {
          // Deze pc antwoordde en zei nee. Onthouden en verder kijken: op een netwerk met twee
          // machines kan de volgende wél de jouwe zijn.
          _netwerkUitleg = '${pc.name}: ${e.message}';
          continue;
        }
        if (toegang == null) continue;
        if (!mounted) return true;
        widget.onConnected(RemoteEndpoint(
          baseUrl: toegang.baseUrl,
          token: toegang.token,
          name: toegang.name ?? pc.name,
        ));
        return true;
      }
    } catch (_) {/* een tweede kans die niet lukte */}
    return false;
  }

  /// Zelf zeggen waar je pc staat, en binnenkomen op je account.
  ///
  /// **Waarom dit er alsnog moest komen, op 04-09-2026.** De ochtend na de vorige uitgave stond er
  /// op de telefoon: *"En op dit netwerk is je pc ook niet gevonden"* — terwijl de pc aan stond, de
  /// app draaide en Tailscale op allebei verbonden was (`saber-pc`, 100.97.101.113).
  ///
  /// Dat klopte allebei. [_zoekOpNetwerk] zoekt met een omroep over het LOKALE netwerk, en zo'n
  /// omroep gaat een tailnet niet over: dat is geen wifi maar een reeks rechtstreekse verbindingen.
  /// Je pc was dus bereikbaar en tegelijk onvindbaar. En de enige twee wegen die zijn adres kenden
  /// — de accountdatabase, en wat het toestel van een eerdere verbinding onthouden had — waren
  /// allebei leeg: de eerste zat aan zijn daglimiet, de tweede was er nog nooit geweest.
  ///
  /// Eén ding wist jij wél, en de app vroeg het nooit: het adres. Het staat in Tailscale op je pc
  /// en in Instellingen van de app daar. Dus vraag het.
  ///
  /// **Eén keer.** Wat het oplevert wordt bewaard als het adres van deze pc, en de eerste
  /// verbinding haalt meteen zijn uitwijkadressen op (`uitwijk.dart`). Vanaf dan gaat het vanzelf,
  /// thuis en op de baan.
  ///
  /// Nog steeds geen code en geen gedeelde sleutel: er gaat je inlogsleutel heen, en de pc vraagt
  /// bij Google van wie die is. Precies dezelfde deur als [_zoekOpNetwerk], alleen weet dit toestel
  /// nu waar hij zit.
  Future<void> _probeerAdres() async {
    final basis = RemoteEndpoint.parseHost(_adres.text);
    if (basis == null) {
      setState(() => _error = 'Dat lijkt geen adres. Iets als 100.97.101.113 of 192.168.0.117.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _waiting = 'Verbinden met ${basis.host}…';
    });
    try {
      final sleutel = await widget.session.idToken();
      if (sleutel.isEmpty) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _waiting = null;
          _error = 'Log eerst in met je e-mailadres en wachtwoord.';
        });
        return;
      }
      final ik = await thisDevice();
      final toegang = await RemoteClient.pairMetAccount(
        basis,
        idToken: sleutel,
        deviceId: ik.id,
        deviceName: ik.name,
        platform: ik.platform,
      );
      if (!mounted) return;
      if (toegang == null) {
        setState(() {
          _busy = false;
          _waiting = null;
          _error = 'Op ${basis.host} nam niemand op.\n'
              'Staat de app op je pc aan, en klopt het adres?';
        });
        return;
      }
      widget.onConnected(toegang);
    } on RemoteException catch (e) {
      // De pc antwoordde en zei nee. Zijn eigen zin is beter dan alles wat we hier kunnen bedenken.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _waiting = null;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _waiting = null;
        _error = 'Kon ${basis.host} niet bereiken: $e';
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
                  if (_toonAdres) ...[
                    // **Het adres vragen, maar pas als het uitzoeken niet lukte.**
                    //
                    // Op 04-09-2026 stond er "je pc is niet gevonden" terwijl hij aan stond en
                    // Tailscale op allebei verbonden was. Zie [_probeerAdres]: een omroep over het
                    // lokale netwerk gaat een tailnet niet over, dus je pc was bereikbaar én
                    // onvindbaar. Jij wist het adres, de app vroeg het nooit.
                    //
                    // Onder de foutmelding en niet erboven, om dezelfde reden als de koppelcode:
                    // op het eerste scherm lijkt het een keuze die je moet maken, en dat is het
                    // niet — in verreweg de meeste gevallen zoekt de app hem gewoon zelf.
                    const SizedBox(height: 20),
                    const Text(
                      'Weet je waar je pc staat?',
                      style: TextStyle(color: _text, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Vul zijn adres in en je komt er rechtstreeks op — nog steeds op je account, '
                      'zonder code. Gebruik je Tailscale, neem dan dat adres (100.…): dat werkt '
                      'ook buitenshuis. Je vindt het op je pc in Instellingen, onder '
                      '"Delen met andere apparaten".',
                      style: TextStyle(color: _muted, fontSize: 13, height: 1.45),
                    ),
                    const SizedBox(height: 12),
                    MaybePressable(
                      enabled: isTv,
                      onPressed: _adresFocus.requestFocus,
                      borderRadius: BorderRadius.circular(12),
                      child: TextField(
                        controller: _adres,
                        focusNode: _adresFocus,
                        enabled: !_busy,
                        autocorrect: false,
                        keyboardType: TextInputType.url,
                        style: const TextStyle(color: _text),
                        decoration: _field('Adres van je pc'),
                        onSubmitted: (_) => _busy ? null : _probeerAdres(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: (!isTv && _busy)
                          ? null
                          : () {
                              if (_busy) return;
                              _probeerAdres();
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _accent,
                        side: const BorderSide(color: _accent),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Verbinden met dit adres',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
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
                    // **De koppelcode staat er PAS als inloggen niet lukte.**
                    //
                    // Gevraagd op 02-09-2026: *"ik wil verlost zijn van die code koppeling, dit is
                    // veel te ingewikkeld, het moet simpel: ik log overal in met gebruikersnaam en
                    // wachtwoord en that's it."* Volkomen terecht — inloggen is al de gewone weg en
                    // de code was alleen het vangnet. Maar hij stond er wél naast, even groot, op
                    // het allereerste scherm, en dan lijkt het een keuze die je moet maken.
                    //
                    // Weghalen kan niet: hij is er precies voor het geval dat de andere weg niet
                    // werkt — geen internet, of de accountdatabase die zijn daglimiet bereikt heeft,
                    // zoals op 31-08. Wie dat overkomt zit anders volledig vast. Dus: onzichtbaar
                    // tot je hem nodig hebt, en dán met de reden erbij.
                    // Op [_toonAdres] en niet op `_error`, om dezelfde reden: die wordt gewist
                    // zodra je iets probeert, en dan verdwijnt het vangnet precies terwijl je het
                    // aan het gebruiken bent.
                    if (widget.onUseCode != null && _toonAdres) ...[
                      const Text('·', style: TextStyle(color: _muted)),
                      TextButton(
                        onPressed: _busy ? null : widget.onUseCode,
                        child: const Text('Lukt inloggen niet? Koppel met een code',
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

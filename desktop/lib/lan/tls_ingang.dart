/// Een versleutelde ingang van de pc (47822 thuis, 47821 van buiten), met grenzen voor wie nog niets
/// bewezen heeft.
///
/// **Waarom een eigen omhulling.** `HttpServer.bindSecure` doet de TLS-handdruk zelf, zonder tijdslimiet
/// en zonder plafond: wie duizend verbindingen opent en nooit iets zegt, houdt ze allemaal open. Van
/// buiten vindt een scanner deze poort binnen dagen. Hier:
///
/// * hoogstens [maxWachtend] verbindingen tegelijk die nog geen geldig verzoek deden (handdruk bezig, of
///   klaar maar nog geen verzoek met een goede sleutel); daarboven wordt een nieuwe meteen gesloten;
/// * [handdruk] voor de TLS-handdruk;
/// * [eersteVerzoek] daarna voor het eerste GELDIGE verzoek ([geldig]); wie dat niet haalt, vliegt eruit.
///
/// Een verbinding die eenmaal geldig was, telt niet meer mee: een lopende stroom wordt nooit afgebroken
/// omdat iemand anders de poort volstopt.
///
/// `HttpServer.listenOn` neemt een [ServerSocket]; deze klasse is er een, en geeft de versleutelde sockets
/// door. Zie stap 5.3 van het plan "verbinden zoals Roon ARC" (14-10-2026).
library;

import 'dart:async';
import 'dart:io';

class TlsIngang extends Stream<Socket> implements ServerSocket {
  TlsIngang._(this._ruw, this._context, this.maxWachtend, this.handdruk, this.eersteVerzoek) {
    _ruw.listen(_nieuw, onError: (Object _) {}, onDone: () {
      if (!_uit.isClosed) unawaited(_uit.close());
    });
  }

  static Future<TlsIngang> bind(
    InternetAddress adres,
    int poort,
    SecurityContext context, {
    int maxWachtend = 64,
    Duration handdruk = const Duration(seconds: 10),
    Duration eersteVerzoek = const Duration(seconds: 10),
  }) async =>
      TlsIngang._(await ServerSocket.bind(adres, poort), context, maxWachtend, handdruk, eersteVerzoek);

  final ServerSocket _ruw;
  final SecurityContext _context;
  final int maxWachtend;
  final Duration handdruk;
  final Duration eersteVerzoek;
  final StreamController<Socket> _uit = StreamController<Socket>();

  /// Verbindingen die nog niets bewezen hebben, op "adres:poort" van de andere kant. De waarde maakt de
  /// plek vrij (en zet de klok stil).
  final Map<String, void Function()> _wacht = {};
  int _wachtend = 0;

  /// Hoeveel verbindingen er nu wachten. Voor toetsen en het logboek.
  int get wachtend => _wachtend;

  /// Hoeveel er geweigerd zijn omdat het plafond vol zat.
  int geweigerd = 0;

  void _nieuw(Socket s) {
    if (_wachtend >= maxWachtend) {
      geweigerd++;
      s.destroy();
      return;
    }
    _wachtend++;
    final sleutel = '${s.remoteAddress.address}:${s.remotePort}';
    var vrij = false;
    Timer? klok;
    // Na de handdruk ligt de versleutelde socket over de ruwe heen; dan is DIE het die dicht moet. De
    // ruwe wegdoen deed niets (gevonden met een mutatie: zonder klok bleef alles groen).
    Socket actief = s;
    void maakVrij() {
      if (vrij) return;
      vrij = true;
      _wachtend--;
      klok?.cancel();
      _wacht.remove(sleutel);
    }

    // Eén klok over handdruk én eerste verzoek samen: wie de handdruk traag doet, heeft minder tijd over.
    klok = Timer(handdruk + eersteVerzoek, () {
      if (vrij) return;
      maakVrij();
      actief.destroy();
    });
    _wacht[sleutel] = maakVrij;
    SecureSocket.secureServer(s, _context).timeout(handdruk).then((veilig) {
      if (vrij) {
        veilig.destroy();
        return;
      }
      actief = veilig;
      // Valt de verbinding weg voor er een geldig verzoek kwam, dan komt de plek vrij.
      unawaited(veilig.done.then((_) => maakVrij(), onError: (Object _) => maakVrij()));
      if (_uit.isClosed) {
        veilig.destroy();
        return;
      }
      _uit.add(veilig);
    }, onError: (Object _) {
      maakVrij();
      s.destroy();
    });
  }

  /// Deze verbinding deed een geldig verzoek: ze telt niet meer mee en krijgt geen klok meer.
  void geldig(HttpConnectionInfo? info) {
    if (info == null) return;
    _wacht['${info.remoteAddress.address}:${info.remotePort}']?.call();
  }

  @override
  StreamSubscription<Socket> listen(void Function(Socket event)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      _uit.stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  int get port => _ruw.port;

  @override
  InternetAddress get address => _ruw.address;

  @override
  Future<ServerSocket> close() async {
    await _ruw.close();
    if (!_uit.isClosed) await _uit.close();
    return this;
  }
}

/// Een HTTP-client die alleen de eigen pc aanvaardt: het certificaat moet precies de vastgepinde
/// vingerafdruk hebben (`certificaat.dart`).
///
/// **Waarom geen gewone https.** De pc heeft geen domeinnaam en dus geen certificaat van een publieke
/// autoriteit; een gewone client zou elke verbinding weigeren, en een client die "alles goed" vindt,
/// aanvaardt ook een tussenpersoon. Met de pin aanvaardt hij precies één certificaat: dat van jouw pc.
///
/// Stap 5.5 van "verbinden zoals Roon ARC" (14-10-2026).
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'certificaat.dart';

/// Een client voor de versleutelde ingang van de pc.
///
/// * [pin] bekend: alleen een server met precies dat certificaat.
/// * [pin] null: de eerste kennismaking — elk certificaat, maar [gezien] hoort welk het was, zodat de
///   aanroeper het kan vastleggen. Alleen gebruiken thuis of via Tailscale (zie `pairMetAccount`), en
///   met [verwacht] (de pin uit je account) als die er is: dan geldt alleen die.
http.Client pinClient({String? pin, String? verwacht, void Function(String pin)? gezien}) {
  final hc = HttpClient(context: SecurityContext(withTrustedRoots: false))
    ..connectionTimeout = const Duration(seconds: 5)
    // Zonder vertrouwde wortels faalt de gewone controle altijd; dan beslist dit, voor elke verbinding.
    ..badCertificateCallback = (cert, host, port) {
      final p = pinVan(cert.der);
      gezien?.call(p);
      final eis = (pin != null && pin.isNotEmpty) ? pin : ((verwacht != null && verwacht.isNotEmpty) ? verwacht : null);
      return eis == null || p == eis;
    };
  return IOClient(hc);
}

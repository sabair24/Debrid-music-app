/// Voor toetsen die met de versleutelde ingang van de pc praten (47822): één proefcertificaat en een
/// client die precies dat certificaat aanvaardt. Geen toets zelf.
///
/// Sinds uitlevering B gaat koppelen via het account alleen nog versleuteld (`/pair-cloud` over 47820
/// geeft 410); toetsen die dat aan de server toetsen, praten daarom hiermee.
library;

import 'dart:io';

import 'package:debridmusic/lan/certificaat.dart';

/// Eén keer gemaakt: een EC-sleutel maken kost een fractie van een seconde, en elke toets hoeft er niet
/// een eigen.
final PcCertificaat proefCertificaat = PcCertificaat.maak();

/// Een `HttpClient` die alleen [proefCertificaat] aanvaardt.
HttpClient pinHttpClient() => HttpClient(context: SecurityContext(withTrustedRoots: false))
  ..badCertificateCallback = (cert, host, port) => pinVan(cert.der) == proefCertificaat.pin;

/// Een kale versleutelde socket naar [poort] op loopback, voor toetsen die zelf bytes schrijven.
Future<SecureSocket> pinSocket(int poort) => SecureSocket.connect(InternetAddress.loopbackIPv4, poort,
    onBadCertificate: (cert) => pinVan(cert.der) == proefCertificaat.pin);

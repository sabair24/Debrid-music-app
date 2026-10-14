/// Het eigen certificaat van de pc, voor de versleutelde poorten 47822 (thuis) en 47821 (van buiten).
///
/// **Waarom.** Stap 5 van "verbinden zoals Roon ARC" (plan 14-10-2026). Van buiten mag niets
/// onversleuteld binnen: een sleutel in een HTTP-kop over mobiele data is een sleutel voor iedereen die
/// meeleest. Een publieke certificaatautoriteit kan hier niet — de pc heeft geen domeinnaam, alleen een
/// adres dat kan wisselen — dus maakt hij zelf één certificaat, één keer, en bewaart het.
///
/// **Vertrouwen gaat via de pin, niet via een keten.** Een toestel leert de vingerafdruk (sha256 over het
/// DER-certificaat) thuis of via Tailscale, en aanvaardt daarna alleen een server met precies die
/// vingerafdruk. Een tussenpersoon met een ander certificaat valt zo af, wat die ook beweert te zijn.
///
/// EC P-256, en de naam erin is "DebridMusic": geen pc-naam, geen gebruikersnaam — wie het certificaat
/// van buiten ophaalt, leert er niets uit over wie erachter zit.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

/// De vingerafdruk van een certificaat: sha256 over zijn DER-bytes, in kleine hexletters.
String pinVan(List<int> der) => sha256.convert(der).toString();

class PcCertificaat {
  const PcCertificaat({required this.certPem, required this.sleutelPem});

  final String certPem;
  final String sleutelPem;

  List<int> get der => CryptoUtils.getBytesFromPEMString(certPem);
  String get pin => pinVan(der);

  /// De context voor een TLS-server met dit certificaat. Dart kent alleen TLS 1.2 en 1.3, en staat
  /// standaard al op 1.2 als ondergrens; lager kan hier dus niet.
  SecurityContext context() => SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(certPem.codeUnits)
    ..usePrivateKeyBytes(sleutelPem.codeUnits);

  /// Een nieuw certificaat, tien jaar geldig, met een dag speling terug voor een klok die achterloopt.
  /// Puur rekenwerk; [laadOfMaak] doet het in een eigen isolate.
  static PcCertificaat maak({DateTime? nu}) {
    final paar = CryptoUtils.generateEcKeyPair();
    final prive = paar.privateKey as ECPrivateKey;
    final publiek = paar.publicKey as ECPublicKey;
    final csr = X509Utils.generateEccCsrPem({'CN': 'DebridMusic'}, prive, publiek);
    // Een willekeurig volgnummer (positief, 62 bits): twee certificaten met hetzelfde nummer van
    // dezelfde "uitgever" kunnen een TLS-bibliotheek in de war brengen.
    final rnd = Random.secure();
    var volgnummer = BigInt.zero;
    for (var i = 0; i < 8; i++) {
      volgnummer = (volgnummer << 8) | BigInt.from(rnd.nextInt(256));
    }
    volgnummer = (volgnummer >> 2) + BigInt.one;
    final cert = X509Utils.generateSelfSignedCertificate(
      prive,
      csr,
      3650,
      serialNumber: volgnummer.toString(),
      notBefore: (nu ?? DateTime.now()).toUtc().subtract(const Duration(days: 1)),
    );
    return PcCertificaat(certPem: cert, sleutelPem: CryptoUtils.encodeEcPrivateKeyToPem(prive));
  }

  /// Het bewaarde certificaat uit [map], of een nieuw (en dat dan bewaard).
  ///
  /// **Een nieuw certificaat is een nieuwe pin**, en elk gekoppeld toestel weigert dan de versleutelde
  /// weg tot het de nieuwe pin thuis of via Tailscale leert. Daarom wordt er alleen een gemaakt als er
  /// niets bruikbaars ligt, en staat dat in het logboek.
  static Future<PcCertificaat> laadOfMaak(Directory map, {void Function(String regel)? log}) async {
    final certBestand = File('${map.path}${Platform.pathSeparator}tls_cert.pem');
    final sleutelBestand = File('${map.path}${Platform.pathSeparator}tls_sleutel.pem');
    if (certBestand.existsSync() && sleutelBestand.existsSync()) {
      try {
        final c = PcCertificaat(certPem: await certBestand.readAsString(), sleutelPem: await sleutelBestand.readAsString());
        c.context(); // gooit als het niet bij elkaar past of niet te lezen is
        return c;
      } catch (e) {
        log?.call('certificaat onleesbaar ($e) — een nieuw maken; gekoppelde toestellen leren de nieuwe pin thuis');
      }
    }
    final nieuw = await Isolate.run(PcCertificaat.maak);
    await map.create(recursive: true);
    // Eerst naar een tijdelijk bestand en dan hernoemen: een half geschreven sleutel is erger dan geen.
    for (final (bestand, inhoud) in [(sleutelBestand, nieuw.sleutelPem), (certBestand, nieuw.certPem)]) {
      final tmp = File('${bestand.path}.tmp');
      await tmp.writeAsString(inhoud, flush: true);
      await tmp.rename(bestand.path);
    }
    log?.call('nieuw certificaat gemaakt, pin ${nieuw.pin.substring(0, 12)}…');
    return nieuw;
  }
}

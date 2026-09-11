/// Een geweigerde sleutel vervangen: eerst via je account, pas daarna via de accountdatabase.
///
/// **Waarom dit bestaat.** Op 11-09-2026 werd de Shield door zijn eigen pc geweigerd, elke vijftien
/// seconden, terwijl de Mac met zijn sleutel bij diezelfde pc gewoon binnenkwam. Er was al een
/// zelfherstel, maar dat liep alleen via Firestore -- precies de dienst waarvan #161 had vastgesteld
/// dat hij aan zijn daglimiet zit -- en het gaf stil op. De weg die daar wél omheen gaat bestond al:
/// het toestel laat zijn verse inlogsleutel zien, de pc vraagt bij Google van wie die is en laat een
/// toestel van zijn eigen account binnen (`accountkoppeling.dart`). Alleen gebruikte niemand hem
/// voor een toestel dat al gekoppeld wás.
///
/// **Waarom het adres dat weigerde, en niet zoeken op het netwerk.** Die pc heeft net geantwoord --
/// met een weigering, maar hij antwoordde. We weten dus precies waar hij staat. Zoeken met een
/// omroep kost seconden, gaat een tailnet niet over, en levert op de Shield in slaapstand zelfs een
/// "Operation not permitted" op. Dat hoeft allemaal niet.
///
/// **Waarom zuiver.** Dit is een deur, en een fout hier ziet er in code precies zo uit als de goede
/// versie. De drie diensten komen als functies binnen, zodat de volgorde getoetst kan worden zonder
/// dat er een netwerk, een Google-account of een pc aan te pas komt.
library;

import 'client.dart';

/// Wat een poging opleverde, en hoe het ging -- voor het logboek.
class Sleutelherstel {
  const Sleutelherstel(this.sleutel, this.verloop);

  /// De nieuwe sleutel, of null als geen van beide wegen er een gaf.
  final String? sleutel;

  /// Elke stap in gewone taal. Ook als het lukt: dan staat er via welke weg.
  final List<String> verloop;
}

/// Eerst [viaAccount], dan [viaDatabase].
///
/// * [inlogsleutel] geeft een inlogsleutel die NU geldig is, of leeg als dit toestel niet ingelogd
///   is (of het netwerk er even niet is -- dan kan de accountweg ook niet).
/// * [viaAccount] is `RemoteClient.pairMetAccount`: null betekent "deze pc kent die weg niet"
///   (oudere bouw), een [RemoteException] betekent dat de pc nee zei, en zijn zin is de reden.
/// * [viaDatabase] is de oude weg via Firestore. Die blijft de terugval: een pc die zelf niet
///   ingelogd is, kan de accountweg niet beoordelen maar wel een aanvraag in de database oppikken.
Future<Sleutelherstel> herstelSleutel({
  required Uri basis,
  required Future<String> Function() inlogsleutel,
  required Future<RemoteEndpoint?> Function(Uri basis, String inlogsleutel) viaAccount,
  required Future<String?> Function(Uri basis) viaDatabase,
}) async {
  final verloop = <String>[];

  var sleutel = '';
  try {
    sleutel = await inlogsleutel();
  } catch (e) {
    verloop.add('geen inlogsleutel: $e');
  }

  if (sleutel.isEmpty) {
    verloop.add('niet ingelogd, of geen netwerk voor een verse inlogsleutel — de accountweg vervalt');
  } else {
    try {
      final toegang = await viaAccount(basis, sleutel);
      if (toegang != null && toegang.token.isNotEmpty) {
        verloop.add('accountweg: toegang van ${basis.host}');
        return Sleutelherstel(toegang.token, verloop);
      }
      verloop.add('accountweg: ${basis.host} kent hem niet (oudere bouw)');
    } on RemoteException catch (e) {
      verloop.add('accountweg: ${basis.host} zei nee — ${e.message}');
    } catch (e) {
      verloop.add('accountweg mislukte: $e');
    }
  }

  try {
    final uitDatabase = await viaDatabase(basis);
    if (uitDatabase != null && uitDatabase.isNotEmpty) {
      verloop.add('accountdatabase: toegang');
      return Sleutelherstel(uitDatabase, verloop);
    }
    verloop.add('accountdatabase: geen sleutel');
  } catch (e) {
    verloop.add('accountdatabase mislukte: $e');
  }
  return Sleutelherstel(null, verloop);
}

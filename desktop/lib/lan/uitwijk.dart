/// Welke adressen probeert een toestel, en in welke volgorde?
///
/// **Waarom dit er moest komen.** Op 04-09-2026: *"ik heb tailscale op men smartphone, dus moet
/// lukken als ik op de baan ben ook."*
///
/// Dat klopt aan de kant van de pc — die weet allang welke van zijn adressen de voordeur overleven
/// (`net.dart`, `isRemoteReachable`) en zet ze vooraan in wat hij publiceert. Maar het toestel
/// onthield er precies **één**: het adres dat werkte op de dag dat je koppelde. Koppel je thuis,
/// dan staat er `192.168.0.117` in `paired_server.json`, en dat adres bestaat niet meer zodra je de
/// deur uit loopt. Het opstartpad zocht dan nog wel op het lokale netwerk — maar dat is precies het
/// netwerk dat je net verlaten hebt.
///
/// De pc kende het antwoord dus, en het toestel vroeg het nooit. Nu wel: bij elke verbinding haalt
/// het toestel de adressen op die van buitenaf werken en bewaart die ernaast. Op de baan zijn ze er
/// al voordat je ze nodig hebt.
///
/// **Waarom de volgorde apart staat, met een toets.** Elke poging naar een adres dat niemand
/// opneemt kost een paar seconden voordat je je muziek ziet, en dat is precies het verschil tussen
/// "hij doet het" en "hij hapert". Een fout in deze lijst valt niet op als een fout; hij valt op
/// als traagheid.
library;

/// De adressen om te proberen, beste eerst, zonder dubbele.
///
/// **Het onthouden adres gaat voorop, en dat is bewust.** Het is het adres dat de vórige keer
/// werkte, en de aanroeper legt vast wélk adres het uiteindelijk werd. Daarmee corrigeert deze
/// volgorde zichzelf: koppel je thuis en lukt het buiten via Tailscale, dan staat dát adres de
/// volgende keer vooraan — thuis werkt het ook, want op hetzelfde netwerk verbindt Tailscale de
/// twee toestellen gewoon rechtstreeks. Alleen de eerste overstap kost één mislukte poging.
///
/// Daarna de adressen die van buitenaf werken, en pas dan wat er op dit netwerk omgeroepen wordt.
/// Andersom zou een toestel op de baan eerst het lokale netwerk moeten afzoeken — daar staat je pc
/// niet, en dat zoeken duurt seconden.
///
/// Rommel wordt weggelaten en niet doorgegeven: een leeg adres of iets zonder host is geen adres,
/// en de aanroeper hoort daar geen verzoek naartoe te sturen.
List<Uri> weguitVolgorde({
  required Uri? onthouden,
  List<Uri> uitwijk = const [],
  List<Uri> gevondenOpNetwerk = const [],
}) {
  final uit = <Uri>[];
  final gezien = <String>{};
  for (final groep in [
    if (onthouden != null) [onthouden],
    uitwijk,
    gevondenOpNetwerk,
  ]) {
    for (final u in groep) {
      if (u.host.isEmpty) continue;
      // Op host én poort, want twee apps op dezelfde machine zijn twee servers. Het schema hoort
      // er niet bij: `http://pc:47820` en `https://pc:47820` zijn hetzelfde adres, en twee keer
      // proberen levert niets op.
      final sleutel = '${u.host}:${u.port}';
      if (!gezien.add(sleutel)) continue;
      uit.add(u);
    }
  }
  return uit;
}

/// Adressen zoals de pc ze opschrijft (`http://100.101.42.7:47820`) omzetten naar iets om naartoe
/// te bellen.
///
/// Alles wat geen host oplevert valt weg. Dat is geen strengheid maar zelfbehoud: één rare regel
/// uit een oudere of nieuwere pc mag niet de hele lijst onbruikbaar maken.
List<Uri> leesAdressen(Iterable<String> ruw) {
  final uit = <Uri>[];
  for (final s in ruw) {
    final tekst = s.trim();
    if (tekst.isEmpty) continue;
    final u = Uri.tryParse(tekst);
    if (u == null || u.host.isEmpty) continue;
    uit.add(u);
  }
  return uit;
}

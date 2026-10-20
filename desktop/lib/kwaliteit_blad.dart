/// De teksten van het kwaliteitsblad op Nu speelt: wat je nu hoort, en wat het bestand echt is.
///
/// Saber, 20-10-2026: "als ik op de kwaliteit klik, bij streamen over mobile data natuurlijk dat ik zie
/// wat de echte kwaliteit is … bij gewoon wifi en internet thuis, toon altijd de echte kwaliteit". Zuiver,
/// zodat het blad zonder speler te toetsen is; het blad zelf staat in main.dart (`_toonKwaliteitBlad`).
library;

import 'echtheid.dart';

/// Wat je NU hoort, in één zin. [nu] en [bestand] zijn badgeteksten ("FLAC · 16/44.1"); [omgezet]: de pc
/// stuurt onderweg een kleinere versie ([PlayerStore.stroomGrens]). [speaker]: er wordt gestreamd.
String nuHoorZin({required String nu, required String bestand, required bool omgezet, String? speaker}) {
  if (speaker != null) return 'Speelt op $speaker.';
  if (omgezet && nu != bestand) {
    return 'Je pc stuurt onderweg een kleinere versie om data te sparen: $nu in plaats van $bestand. '
        'Thuis op wifi hoor je het bestand zoals het is.';
  }
  return 'Je hoort het bestand zoals het is.';
}

/// Wat het bestand ECHT is, regel voor regel: de volle meting (echtheid_meter.dart) en de controlesom.
/// Leeg oordeel = nog niet gemeten, en dat staat er dan ook.
List<String> bestandRegels(Echtheidsoordeel? o, {required int kopSampleRate, required int kopBits}) {
  if (o == null) {
    return const ['Nog niet gemeten. De pc meet elk nummer één keer helemaal: de controlesom, de bits en '
        'het spectrum van begin tot eind.'];
  }
  final uit = <String>[];
  final echt = echteResolutie(o, kopSampleRate: kopSampleRate, kopBits: kopBits);
  if (o.isKapot) {
    uit.add('Beschadigd: de controlesom klopt niet. De samples zijn niet wat de encoder schreef; je hoort er '
        'haperingen of gaten. Opnieuw downloaden.');
  } else if (o.isNep) {
    uit.add('Wat erin zit: ${echt ?? 'minder dan de kop belooft'} — ${waarom(o)}.');
  } else if (o.isVermoedelijk) {
    uit.add('${_hoofdletter(waarom(o))}.');
  } else if (o.isOnbekend) {
    uit.add('Niet te beoordelen (te kort of te stil om te meten).');
  } else {
    uit.add('Echt wat de kop zegt: geen afkap, ${o.boven == Bovenband.vol ? 'inhoud boven 24 kHz, ' : ''}'
        '${o.gebruikteBits != null && kopBits > 16 ? '${o.gebruikteBits} bits in gebruik' : 'niets dat het tegenspreekt'}.');
  }
  switch (o.integriteit) {
    case Integriteit.klopt:
      uit.add('Controlesom klopt: bit voor bit wat de encoder schreef.');
    case Integriteit.geenControlesom:
      uit.add('Geen controlesom in het bestand: de integriteit is niet te bewijzen.');
    case Integriteit.fout:
    case Integriteit.onbekend:
      break;
  }
  return uit;
}

String _hoofdletter(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

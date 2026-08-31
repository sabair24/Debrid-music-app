/// Hoeveel je pc over de lijn stuurt als je telefoon van hem afspeelt.
///
/// **Waarom dit bestaat.** Speelt een gekoppeld toestel muziek van de pc, dan gaat het bestand tot
/// nu toe byte voor byte de deur uit. Een 24/192 FLAC is vijf à zes megabit per seconde. Thuis op
/// wifi is dat prima en precies wat je wilt; onderweg op mobiele data is het de reden dat het
/// hapert — en het is ook nog eens je databundel. Gevraagd op 28-08-2026, met schermafdrukken van
/// TIDAL erbij: *"zorg dat alles vlot gaat, zo weinig mogelijk druk."*
///
/// **Alles blijft lossless.** Er komt geen lossy codec aan te pas: alleen de bemonsteringsfrequentie
/// en de bitdiepte gaan omlaag, en het blijft FLAC. Een cd-stand is dus nog altijd bit-voor-bit een
/// cd — je verliest wat er boven de cd zit, niet wat erin zit.
///
/// **Deze hele weg is zuiver.** Tekst in, tekst uit; geen netwerk, geen schijf. Dat is met opzet: of
/// er omgezet wordt en wat er dan in de URL komt te staan is precies het stuk waar een fout niet
/// omvalt maar stilletjes het verkeerde doet — een bestand dat onnodig omgezet wordt, of een URL die
/// met de verkeerde extensie geweigerd wordt. Zie `test/stroomstand_test.dart`.
library;

import 'upnp.dart';

/// De drie sporten van de ladder.
///
/// Bewaard als tekst (`'max'` / `'hoog'` / `'cd'`), zoals elke andere keuze in [AppSettings]: er
/// staat geen enkele Dart-enum in dat bestand, en een naam overleeft het bijwerken van de app beter
/// dan een volgnummer.
enum Stroomstand { max, hoog, cd }

/// Het plafond dat bij een sport hoort. `(0, 0)` betekent: geen plafond, stuur het origineel.
///
/// **Waarom de middenstand 24/48 is en geen 24/96.** Dat staat al ergens anders in deze app
/// opgeschreven, bij het vooruitlezen in `player.dart`: de uitgang van het toestel is gemeten op
/// 48 kHz en 16 bit. Boven 48 kHz rekent het toestel het zelf terug, dus bij 24/96 betaal je bijna
/// het dubbele aan mobiele data voor een verschil dat de hardware niet kan weergeven. 24/48 is
/// bovendien precies het Sonos-plafond, dus het is dezelfde omzetting die de app toch al maakt.
({int rate, int bits}) plafondVan(Stroomstand s) => switch (s) {
      Stroomstand.max => (rate: 0, bits: 0),
      Stroomstand.hoog => (rate: 48000, bits: 24),
      Stroomstand.cd => (rate: 44100, bits: 16),
    };

/// Wat er op het scherm staat. Engels, zoals de andere kwaliteitsnamen in deze app.
String labelVan(Stroomstand s) => switch (s) {
      Stroomstand.max => 'Max',
      Stroomstand.hoog => 'Hi-Res 24/48',
      Stroomstand.cd => 'CD 16/44.1',
    };

/// Ruwweg hoeveel dit kost, in woorden die iemand iets zeggen.
String tempoVan(Stroomstand s) => switch (s) {
      Stroomstand.max => 'tot ~6 Mbit/s',
      Stroomstand.hoog => '~1,5 Mbit/s',
      Stroomstand.cd => '~0,9 Mbit/s',
    };

/// Een bewaarde naam terug naar een sport, met [terugval] als er iets onbekends staat.
///
/// Een instellingenbestand van een oudere of nieuwere versie mag nooit een lege lijst of een
/// uitzondering opleveren — het is een voorkeur, geen contract.
Stroomstand standUitNaam(String? naam, {Stroomstand terugval = Stroomstand.max}) =>
    switch ((naam ?? '').trim()) {
      'max' => Stroomstand.max,
      'hoog' => Stroomstand.hoog,
      'cd' => Stroomstand.cd,
      _ => terugval,
    };

String naamVan(Stroomstand s) => s.name;

/// Welke extensies de app als lossless behandelt.
///
/// Alleen hiervan mag er omgezet worden. Zie [metStand] voor waarom dat niet vrijblijvend is.
const _lossless = {'flac', 'wav', 'aiff', 'aif', 'alac', 'm4a_alac', 'ape', 'wv', 'tta'};

bool losslessExtensie(String ext) => _lossless.contains(ext.toLowerCase().replaceFirst('.', ''));

/// De speel-URL met een plafond erop — of onveranderd, en dat is het normale geval.
///
/// **De URL wordt met opzet alleen aangeraakt als er ECHT omgezet gaat worden.** Dat is geen zuinigheid
/// maar de kern van de zaak, om drie redenen die elk apart een storing zouden opleveren:
///
///  * **De extensie moet meebewegen.** De uitvoer is altijd FLAC, en `Track.path` eindigt op de
///    extensie van de BRON. Een `.wav`-URL die FLAC-bytes teruggeeft wordt door AVFoundation
///    geweigerd voordat er één byte gelezen is — daarom staat die extensie er überhaupt op. Alleen
///    door herschrijven en omzetten in hetzelfde besluit te nemen blijven ze gelijk lopen.
///  * **Een lossy bron mag nooit door de omzetter.** Een mp3 van 320 kbit/s die naar 44,1 kHz
///    "verlaagd" wordt komt er als FLAC van zo'n 800 uit: de databesparing zou de data VERDUBBELEN,
///    precies op de bestanden waarvoor hij bedoeld is.
///  * **Wat al onder het plafond zit blijft het origineel.** [castGrenzen] zegt dan `omzetten: false`,
///    en dan gaat er niets over de lijn dat niet ook zonder deze hele instelling was verstuurd.
///
/// Alles wat geen `/stream/`-adres van de eigen pc is — een torrent, de radio, een offline kopie op
/// `file:` — komt er ongewijzigd uit. Die kent deze zeef niet en hoort er ook niet in.
/// De naam van de grens zoals hij in de URL staat. Eén plek, want hij wordt geschreven in [metStand]
/// en gelezen in `player.dart` — en twee losse letterlijke teksten lopen vroeg of laat uiteen.
const _grensSleutel = 'maxRate';

/// Gaat de pc dit adres eerst helemaal omzetten voordat er één byte vertrekt?
///
/// **Waarom de speler dit wil weten.** Een 24/192 van vijf minuten is zo'n 180 MB, en die is pas
/// klaar na tien tot twintig seconden. In die tijd staat de teller op 0:00 — precies het beeld waar
/// [Stilstandwacht] anders na tien seconden "Er komt geen geluid" over roept, op een kerngezonde pc.
/// Dus: meer geduld als dit true is, en zeggen wat er gebeurt in plaats van klagen.
///
/// Ook het antwoord op "valt er voor het volgende nummer iets vooruit klaar te zetten": staat er
/// geen grens op, dan serveert de pc gewoon het origineel en is een `HEAD` vooruit verkeer voor
/// niets.
bool omzettenGevraagd(String url) => grensUitUrl(url) != null;

/// Welke grens er in dit adres staat, of null als er geen op staat.
///
/// **Het tegendeel van [metStand], en het bestond niet.** De grens werd in de URL geschreven en
/// daarna las niemand hem meer terug: de speler wist alleen DÁT er omgezet werd (`maxRate=` staat
/// erin), niet waarnaar. Op het scherm stond daardoor onveranderd wat het BESTAND is — "FLAC · 24/96"
/// — terwijl je pc 16/44.1 stuurde. Gemeld op 29-08-2026 vanaf 5G: "ik zie niet dat het
/// geconverteerd wordt."
///
/// `bits: 0` betekent "de diepte is niet begrensd", precies zoals [metStand] hem dan ook weglaat.
({int rate, int bits})? grensUitUrl(String url) {
  final u = Uri.tryParse(url);
  if (u == null) return null;
  final rate = int.tryParse(u.queryParameters[_grensSleutel] ?? '');
  if (rate == null || rate <= 0) return null;
  final bits = int.tryParse(u.queryParameters['maxBits'] ?? '') ?? 0;
  return (rate: rate, bits: bits < 0 ? 0 : bits);
}

String metStand(
  String url, {
  required Stroomstand stand,
  required int sampleRate,
  required int bits,
  required bool lossless,
}) {
  if (stand == Stroomstand.max || !lossless) return url;
  if (!url.contains('/stream/')) return url;
  final u = Uri.tryParse(url);
  if (u == null || u.pathSegments.isEmpty) return url;

  final plafond = plafondVan(stand);
  final grens = castGrenzen(
    sampleRate: sampleRate,
    bits: bits,
    maxSampleRate: plafond.rate,
    maxBitDepth: plafond.bits,
  );
  if (!grens.omzetten) return url;

  final segmenten = [...u.pathSegments];
  final laatste = segmenten.last;
  final punt = laatste.lastIndexOf('.');
  segmenten[segmenten.length - 1] = '${punt > 0 ? laatste.substring(0, punt) : laatste}.flac';

  return u.replace(
    pathSegments: segmenten,
    queryParameters: {
      ...u.queryParameters,
      _grensSleutel: '${grens.rate}',
      // Een onbekende diepte is geen diepte. `maxBits=0` zou de server een `-bits_per_raw_sample 0`
      // laten doorgeven aan ffmpeg, en dat is geen grens maar onzin.
      if (grens.bits > 0) 'maxBits': '${grens.bits}',
    },
  ).toString();
}

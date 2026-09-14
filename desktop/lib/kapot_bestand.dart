/// Waarom een bestand niet open te krijgen is, in gewone taal.
///
/// **Waarvoor dit bestaat.** Op 31-08-2026 stond er op het speelscherm: *"Kan dit nummer niet openen
/// — Failed to recognize file format."* Dat is mpv's eigen zin, in het Engels, en hij zegt precies
/// niets: is het bestand stuk, is het leeg, is het helemaal geen muziek, staat er een halve download?
/// De gebruiker las het als "de app kan mijn FLAC niet lezen" — *"is gewoon flac file van rutracker"*
/// — en had geen enkele reden om iets anders te denken.
///
/// Terwijl het antwoord in de eerste bytes staat. Vrijwel elk formaat begint met een herkenningsteken,
/// en de bestandsgrootte zegt de rest. Dit is dezelfde les als bij het taalmodel dat alleen "400"
/// mocht zeggen en bij de stroomgrens die onzichtbaar was: de app wist het en gooide het weg.
///
/// **Zuiver.** Naam, grootte en de eerste bytes in; een zin eruit, of null als er niets bijzonders te
/// zien is — dan is mpv's eigen woord nog altijd beter dan een verzonnen verklaring.
library;

import 'audioformaten.dart';

/// Een herkenningsteken: de bytes waarmee een bestand van dit soort begint.
///
/// Als BYTES en niet als tekst, want een deel ervan is niet te typen: een PNG begint met 0x89 en een
/// JPEG met 0xFF 0xD8. Zo'n byte in een tekstliteraal zetten levert een onzichtbaar stuurteken in de
/// broncode op — dat is bij het schrijven van dit bestand één keer gebeurd, en het is precies het
/// soort regel die er goed uitziet en iets anders doet.
class _Teken {
  /// Waarmee het bestand begint.
  final List<int> bytes;

  /// Hoe dit soort in gewone taal heet.
  final String heet;

  /// De extensies waar dit teken bij HOORT. Staat de naam daarin, dan is er niets aan de hand en
  /// wordt er niets beweerd — een `.mp3` die met "ID3" begint is precies wat je verwacht.
  final Set<String> hoortBij;

  const _Teken(this.bytes, this.heet, this.hoortBij);
}

List<int> _ascii(String s) => s.codeUnits;

final List<_Teken> _tekens = [
  _Teken(_ascii('fLaC'), 'een FLAC-bestand', const {'flac'}),
  _Teken(_ascii('OggS'), 'een Ogg-bestand', const {'ogg', 'oga', 'opus', 'spx'}),
  _Teken(_ascii('RIFF'), 'een WAV-bestand', const {'wav'}),
  _Teken(_ascii('FRM8'), 'een DSD-bestand', const {'dff'}),
  _Teken(_ascii('FORM'), 'een AIFF-bestand', const {'aiff', 'aif', 'aifc'}),
  _Teken(_ascii('DSD '), 'een DSD-bestand', const {'dsf'}),
  _Teken(_ascii('MAC '), "een Monkey's Audio-bestand", const {'ape'}),
  _Teken(_ascii('wvpk'), 'een WavPack-bestand', const {'wv'}),
  // Hier stond ooit `ID3` -> 'een MP3-achtig blok'. Dat was fout; zie [id3TagLengte].
  _Teken(_ascii('%PDF'), 'een pdf', const <String>{}),
  _Teken(_ascii('PK'), 'een zip-archief', const <String>{}),
  _Teken(_ascii('GIF8'), 'een plaatje', const <String>{}),
  _Teken(const [0x89, 0x50, 0x4E, 0x47], 'een plaatje', const <String>{}), // PNG
  _Teken(const [0xFF, 0xD8, 0xFF], 'een plaatje', const <String>{}), // JPEG
  // Een webpagina die als muziek is opgeslagen. Dat is bijna altijd een foutmelding van een server
  // die met de bestandsnaam van je nummer is neergezet.
  _Teken(_ascii('<!DO'), 'een webpagina — waarschijnlijk een foutmelding van de bron', const <String>{}),
  _Teken(_ascii('<!do'), 'een webpagina — waarschijnlijk een foutmelding van de bron', const <String>{}),
  _Teken(_ascii('<htm'), 'een webpagina — waarschijnlijk een foutmelding van de bron', const <String>{}),
  _Teken(_ascii('<HTM'), 'een webpagina — waarschijnlijk een foutmelding van de bron', const <String>{}),
  _Teken(_ascii('<?xm'), 'een webpagina — waarschijnlijk een foutmelding van de bron', const <String>{}),
];

bool _begintMet(List<int> kop, List<int> teken) {
  if (kop.length < teken.length) return false;
  for (var i = 0; i < teken.length; i++) {
    if (kop[i] != teken[i]) return false;
  }
  return true;
}

/// Het eerste teken dat op [kop] past, of null als we deze bytes niet kennen.
_Teken? _tekenVoor(List<int> kop) {
  for (final t in _tekens) {
    if (_begintMet(kop, t.bytes)) return t;
  }
  return null;
}

/// Waarom [naam] niet te openen is, of null als er aan het bestand zelf niets te zien is.
///
/// [bytes] is de grootte op schijf, [kop] de eerste bytes ervan (twaalf is genoeg). Een negatieve
/// [bytes] betekent: de grootte is niet op te vragen — dan wordt er niets beweerd.
String? waaromNietTeOpenen({
  required String naam,
  required int bytes,
  required List<int> kop,
}) {
  if (bytes < 0) return null;
  // Nul bytes is het duidelijkste geval en tegelijk het meest voorkomende: het restafval van een
  // afgebroken bewerking. Zeggen dát het leeg is, is hier het hele antwoord.
  if (bytes == 0) return 'het bestand is leeg (0 bytes) — er staat geen muziek in';
  if (bytes < kMinimumBytes) {
    return 'het bestand is maar $bytes bytes — te klein om muziek te zijn';
  }

  // **Staat er een ID3-tag voorop, dan begint het bestand pas daarachter.** Zo'n tag kan honderden
  // kilobytes groot zijn, dus meestal reikt [kop] er niet overheen — en dan weten we niets en
  // zeggen we niets. Zie [id3TagLengte] voor waarom dat beter is dan de gok die hier eerder stond.
  final tag = id3TagLengte(kop);
  if (tag != null) {
    if (kop.length < tag + 4) return null;
    kop = kop.sublist(tag);
  }

  // **Een FLAC die veel te licht is voor wat hij zelf belooft.** Dit is het gat dat hieronder
  // beschreven staat: een AFGEKAPTE flac begint nog altijd met "fLaC" en heet nog altijd .flac, dus
  // geen van de onderstaande regels ziet hem. Zijn eigen kop verraadt hem wel — daar staat hoeveel
  // monsters er hadden moeten zijn. Zie [kMinimaleFlacVerhouding] voor de meting achter die grens.
  //
  // Dit kan geen werkend bestand tegenhouden: deze functie wordt pas geraadpleegd nadat het openen
  // al mislukt is. Het ergste wat een verkeerde gok hier doet, is een foutmelding minder precies
  // maken dan hij had kunnen zijn.
  final onverpakt = flacOnverpakteBytes(kop);
  if (onverpakt != null && bytes < onverpakt * kMinimaleFlacVerhouding) {
    final deel = (bytes * 100 / onverpakt);
    return 'er staat maar ${deel < 1 ? "minder dan 1" : deel.round()}% in van het geluid dat de kop '
        'belooft — het bestand is afgekapt';
  }

  final teken = _tekenVoor(kop);
  // Een kop die we niet herkennen is geen bewijs van iets. Dan weten we het niet beter dan mpv, en
  // dan is zwijgen eerlijker dan raden — een AFGEKAPTE flac begint nog altijd met "fLaC", en die
  // valt hieronder dus ook netjes stil.
  if (teken == null) return null;
  final soort = soortVan(naam);
  if (teken.hoortBij.contains(soort)) return null;
  if (soort == 'flac') return 'dit heet .flac maar het is ${teken.heet}';
  return 'de inhoud past niet bij de naam: dit lijkt ${teken.heet}';
}

/// Hoeveel een FLAC minstens mag wegen, als deel van wat zijn eigen kop belooft.
///
/// **GETELD OP 14-09-2026 over alle 907 FLAC-bestanden in de bibliotheek** (899 met een leesbare
/// STREAMINFO; de acht andere dragen een ID3-tag, zie [id3TagLengte]). De verhouding tussen wat een
/// bestand werkelijk weegt en wat het onverpakt zou zijn:
///
///     laagste ECHTE nummer    21,2 %
///     1 op de 100             42,6 %
///     mediaan                 70,2 %
///     hoogste                109,9 %
///
/// Vier bestanden zaten daar ver onder, en alle vier geeft ffmpeg er "invalid residual" en
/// "decode_frame() failed" op:
///
///     0,13 %  Stromae - Sommeil          (76 KB voor 3:38)
///     0,86 %  Britney Spears - Radar     (507 KB voor 3:49)
///     2,19 %  Stromae - Moules frites    (898 KB voor 2:38)
///     2,37 %  Tiesto - Heroes            (7,5 MB voor 9:24 op 96/24)
///
/// Tussen het slechtste ECHTE nummer (21,2 %) en het beste KAPOTTE (2,37 %) zit een factor negen.
/// Tien procent ligt daar tussenin: ruim vier keer boven het ergste kapotte en twee keer onder het
/// zuinigste echte.
///
/// **Waarom dat zuinigste echte nummer zo laag zit**, want dat is de enige reden dat de marge niet
/// groter is: Seal - Stand by Me staat op 192 kHz terwijl er 44,1-materiaal in zit. De kop rekent
/// dan met viermaal zoveel monsters als er werkelijk informatie is, en FLAC perst de rest weg. Elk
/// opgewaardeerd bestand drukt deze ondergrens dus verder omlaag — een reden om de grens niet
/// hoger te zetten dan hij nu staat.
const kMinimaleFlacVerhouding = 0.10;

/// Hoeveel bytes de ID3-tag vooraan inneemt, of null als er geen (leesbare) ID3-tag staat.
///
/// **Waarom dit er is.** Hierboven stond een regel die zei: begint een bestand met `ID3`, dan is het
/// "een MP3-achtig blok". Op 14-09-2026 bleek dat acht bestanden in de bibliotheek te raken — David
/// Guetta, Dr. Alban (twee), Real McCoy, Spice Girls, Âme, Richard Cocciante, DJ Stijn — en alle
/// acht zijn ze een **volwaardige FLAC**: ffprobe zegt `codec_name=flac`, en op de byte direct
/// achter de tag staat netjes `fLaC`. De app zou de gebruiker dus vertellen dat zijn goede bestand
/// een mp3 is.
///
/// Een ID3-tag zegt namelijk niets over wat eronder ligt — hij wordt op mp3, FLAC, AIFF en WAV
/// geplakt. Het enige eerlijke antwoord is: kijk erachter. De tags in die acht bestanden liepen van
/// 2 KB tot 896 KB, dus daar reikt een kop van een paar tientallen bytes niet overheen. Kan het
/// niet, dan zegt [waaromNietTeOpenen] niets, en dat is beter dan een verkeerde beschuldiging.
///
/// De lengte staat in vier "syncsafe" bytes: van elke byte tellen alleen de lage zeven bits, zodat
/// de reeks nooit op een mp3-synchronisatiepatroon lijkt. Staat er in een van die bytes tóch een
/// hoge bit, dan is het geen geldige tag en wordt er niets beweerd.
int? id3TagLengte(List<int> kop) {
  if (kop.length < 10) return null;
  if (kop[0] != 0x49 || kop[1] != 0x44 || kop[2] != 0x33) return null; // 'ID3'
  // 0xFF is in geen enkele ID3-versie geldig en verraadt een toevallige botsing.
  if (kop[3] == 0xFF || kop[4] == 0xFF) return null;
  for (var i = 6; i < 10; i++) {
    if (kop[i] >= 0x80) return null;
  }
  final n = (kop[6] << 21) | (kop[7] << 14) | (kop[8] << 7) | kop[9];
  // Vlagbit 4 betekent dat er achteraan de tag nog een voettekst van tien bytes staat. Bit 7
  // (0x80, "unsynchronisation") staat in twee van die acht bestanden aan en telt NIET mee — dat
  // is nagerekend: 10 + n kwam er precies op `fLaC` uit.
  final voet = (kop[5] & 0x10) != 0 ? 10 : 0;
  return 10 + n + voet;
}

/// Wat een FLAC onverpakt zou wegen volgens zijn eigen STREAMINFO, of null als dat er niet staat.
///
/// STREAMINFO is het eerste metablok en staat altijd vooraan: `fLaC`, dan een blokkop van vier
/// bytes, dan vierendertig bytes waarin onder andere de monsterfrequentie, het aantal kanalen, de
/// bitdiepte en het TOTALE aantal monsters staan. Dat laatste is wat een afgekapt bestand verraadt:
/// de kop belooft nog steeds de hele plaat.
///
/// De velden liggen niet op bytegrenzen — twintig bits frequentie, drie bits kanalen, vijf bits
/// diepte, zesendertig bits monsters — dus dit schuift door de bytes heen in plaats van ze te lezen.
int? flacOnverpakteBytes(List<int> kop) {
  // 4 bytes 'fLaC' + 4 bytes blokkop + 34 bytes STREAMINFO; we hebben er tot en met 25 nodig.
  if (kop.length < 26) return null;
  if (kop[0] != 0x66 || kop[1] != 0x4C || kop[2] != 0x61 || kop[3] != 0x43) return null;
  // Het eerste metablok MOET STREAMINFO zijn (type 0 in de lage zeven bits).
  if ((kop[4] & 0x7F) != 0) return null;

  final frequentie = (kop[18] << 12) | (kop[19] << 4) | (kop[20] >> 4);
  final kanalen = ((kop[20] >> 1) & 0x07) + 1;
  final diepte = (((kop[20] & 0x01) << 4) | (kop[21] >> 4)) + 1;
  // Zesendertig bits: de lage vier van byte 21 plus vier hele bytes. Boven de 2^32 zou een int op
  // het web overlopen, maar zesendertig bits passen ruim in een Dart-int op elk platform hier.
  final monsters =
      ((kop[21] & 0x0F) * 4294967296) + (kop[22] << 24) + (kop[23] << 16) + (kop[24] << 8) + kop[25];

  // Nul monsters betekent "onbekend" en is geen bewering — een gestreamde FLAC weet zijn lengte
  // niet. Nul als frequentie is volgens de beschrijving ongeldig, en een diepte onder de vier bits
  // bestaat niet; allebei betekenen ze dat de kop zelf beschadigd is, en dan valt er niets uit af
  // te leiden. Op `kanalen` staat GEEN wacht: dat veld is drie bits plus één, dus altijd 1 tot 8.
  if (monsters <= 0 || frequentie <= 0 || diepte < 4) return null;
  return monsters * kanalen * ((diepte + 7) ~/ 8);
}

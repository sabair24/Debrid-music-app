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
  _Teken(_ascii('ID3'), 'een MP3-achtig blok', const {'mp3', 'mp2', 'aac'}),
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

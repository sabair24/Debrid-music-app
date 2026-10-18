/// Een eigen foto van internet voor een artiest (Saber, 18-10-2026: "maak het mogelijk om zelf een
/// afbeelding te importeren van internet voor artiesten").
///
/// Je plakt in "Foto kiezen" het adres van een foto. Dat adres wordt bewaard zoals elke andere keuze
/// (een webadres, zie `LibraryStore.setArtistArt`), dus de gsm, de iPad en de Shield halen hem net zo
/// op als een foto van Discogs of TheAudioDB.
library;

/// Wat er van een geplakt adres overblijft als webadres van een afbeelding, of null.
///
/// - Een link uit Google Afbeeldingen (`google.…/imgres?imgurl=…`) of Bing (`bing.com/images/search?…
///   &mediaurl=…`) wijst naar de pagina eromheen; het echte adres staat erin als parameter.
/// - `data:` is een miniatuur uit de zoekresultaten zelf (Google zet die in de pagina): te klein, en
///   geen adres dat een ander toestel kan ophalen. Null, zodat de aanroeper kan uitleggen wat wel.
/// - Alleen http en https: een pad op deze pc kan de gsm niet openen.
String? echtAfbeeldingsadres(String invoer) {
  final tekst = invoer.trim();
  if (tekst.isEmpty || tekst.startsWith('data:')) return null;
  final uri = Uri.tryParse(tekst);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) return null;
  final host = uri.host.toLowerCase();
  String? binnen;
  if (host.contains('google.') && uri.path.contains('imgres')) binnen = uri.queryParameters['imgurl'];
  if (host.endsWith('bing.com')) binnen = uri.queryParameters['mediaurl'];
  if (binnen != null && binnen.isNotEmpty) return echtAfbeeldingsadres(binnen);
  return uri.toString();
}

/// Wat de gebruiker te lezen krijgt als [echtAfbeeldingsadres] null gaf.
String waaromGeenAdres(String invoer) {
  final tekst = invoer.trim();
  if (tekst.isEmpty) return 'Plak eerst het adres van een foto.';
  if (tekst.startsWith('data:')) {
    return 'Dat is een miniatuur uit de zoekresultaten. Klik de foto eerst open en kopieer dan het '
        'afbeeldingsadres.';
  }
  return 'Dat is geen webadres van een foto: het moet met http:// of https:// beginnen.';
}

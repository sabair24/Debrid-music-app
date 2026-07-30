/// Eén manier om JSON uit een HTTP-antwoord te lezen, omdat de gewone manier stuk is.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Lees het antwoord als JSON. Altijd UTF-8, wat de server ook beweert.
///
/// `response.body` van het http-pakket kijkt naar de `charset` in de Content-Type-kop en valt bij
/// gebrek daaraan terug op **latin1**. Dat is de val: een server die netjes `application/json`
/// stuurt zonder charset -- TheAudioDB doet dat -- levert dan tekst waarin elke accentletter uit
/// elkaar valt. De UTF-8-bytes van een ’ (E2 80 99) worden dan drie losse latin1-tekens: `â€™`.
///
/// Gemeten in de eigen bibliotheek: op de albumpagina van Unapologetic stond
/// "Nobodyâ€™s Business" en in de feitencache "MÃ¡s es amar". De caches van MusicBrainz en Discogs
/// waren schoon -- die lazen al bytes -- en van de 112 albumbeschrijvingen waren er 6 verminkt.
///
/// JSON is per RFC 8259 altijd UTF-8, dus de bytes zelf decoderen is niet alleen een reparatie maar
/// simpelweg het juiste antwoord. `allowMalformed` zodat één kapotte byte niet een hele opzoeking
/// weggooit: een vraagteken in een titel is beter dan geen titel.
dynamic jsonBody(http.Response r) => jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));

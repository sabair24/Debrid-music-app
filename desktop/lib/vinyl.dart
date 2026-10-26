// Een vinyl-rip herkennen aan zijn pad.
//
// Saber, 24-10-2026: vinyl-rips zijn een andere bron dan de cd of de digitale uitgave — vaak 24/96 of 24/192, maar
// met naaldgeluid en een andere lengte ("Mademoiselle chante le blues": 235 s tegen 228 s). In de zoeklijst staat er een
// label "vinyl" bij. Zoeken met "vinyl" erbij vond er veel: Daft Punk — Digital Love 165 hi-res kopieën die de gewone
// zoekopdracht niet had.
//
// Eerst "alleen als ik kies" (24-10-2026). Sinds 25-10-2026 mag de app er ook vanzelf een nemen (Saber: "ik mis wel heel
// veel goede kwaliteit liedjes door vinyl en lp weg te laten oor, laat ze toch maar door"), maar altijd na de
// digitale kopieën ([vinylAchteraan]), en door dezelfde keuring.

// PBTHAL en "LP 24-96" (Saber, 24-10-2026): de Africa die vanzelf binnenkwam, kwam uit "PBTHAL rips [NOT REENCODED]\Toto\
// Toto - IV (TML)", een vinylrip zonder een van de drie tekens. PBTHAL maakt alleen vinylrips; zijn mappen heten
// "(PBTHAL LP 24-96)" of "[Flac 24-96 LP]". GEMETEN op 24.264 zoekresultaten: 62 mappen nieuw herkend, allemaal vinyl;
// van de 3007 bestanden met "(LP Version)" (de albumversie, geen rip) kwam er geen enkele door deze tekens bij.
final _vinyl = RegExp(
    r'vinyl|needle[\s_.-]*drop|\blp[\s_.-]*rip|pbthal'
    r'|\blp[\s_.\-\[\]()]*(24|16)[\s_./-]*(44|48|88|96|176|192)\b|\b(24|16)[\s_./-]*(44|48|88|96|176|192)[\s_.\-\[\]()]*lp\b'
    // Een kaal "[LP]" of "(2LP)" als merkje achter de albumnaam (26-10-2026, bij de versies): een vinylrip. "(LP Version)"
    // niet — daar staat iets achter "LP".
    r'|[\[(][2-4]?\s*lp[\])]',
    caseSensitive: false);

/// Noemt [pad] (map of bestandsnaam) een vinyl-rip? "1988 - Mademoiselle chante (vinyl rip)", "[Japan Vinyl LP 24-96
/// kHz]", "needle drop", "LP rip", PBTHAL, "LP 24-96". Een gewone "LP" in een albumnaam telt niet, "(LP Version)" evenmin.
bool isVinylRip(String pad) => _vinyl.hasMatch(pad);

/// Wat een ripper in de tags achterlaat bij een vinylrip: "MEDIA=Vinyl (LP,Album)" (Patricia Kaas), het element waarmee hij
/// draaide ("COMMENT=AT150ANV" — een Audio-Technica, Toto IV van PBTHAL), een draaitafel, of gewoon "vinyl". Gezien op
/// 26-10-2026 bij de versies: na het opbergen staat de bron nergens meer, maar die velden blijven.
final _vinylInTags = RegExp(
    r'vinyl|needle[\s_.-]*drop|\blp[\s_.-]*rip|pbthal|turntable|draaitafel|platenspeler|\bphono\b|cartridge'
    r'|\bortofon\b|\bshure\s*(v|m)\d|\bgrado\b|\bnagaoka\b|\bsumiko\b|\bgoldring\b|\bclearaudio\b|\bdl-?103\b'
    r'|audio[\s-]*technica|\bat-?(vm|oc|art)\d+|\bat-?\d{2,3}[a-z]*\b|\btechnics\s*sl-?\d|\bthorens\b|\brega\s*(p|planar)\d',
    caseSensitive: false);

/// De velden waar zo'n spoor in staat — niet de titel of het album (daar kan "Vinyl" gewoon een naam zijn).
const _vinylVelden = [
  'media', 'source', 'sourcemedia', 'comment', 'description', 'encodedby', 'encoded by', 'originator', 'codinghistory', //
  'ripper', 'lineage', 'notes', 'ripping tool', 'encoder settings',
];

/// Zeggen de tags van een bestand ([velden], kleine sleutels — `readFlacRawFields`) dat het een vinylrip is?
bool vinylUitTags(Map<String, String> velden) {
  for (final k in _vinylVelden) {
    final v = velden[k];
    if (v != null && _vinylInTags.hasMatch(v)) return true;
  }
  return false;
}

/// [kandidaten] met de vinyl-rips achteraan, verder in dezelfde volgorde ([padVan]: het pad van een kandidaat). Voor wat
/// de app zelf kiest (▶, de radio): een vinyl-rip alleen als er niets anders is — anders bleef ▶ stil terwijl er wel
/// een kopie van het nummer was.
List<T> vinylAchteraan<T>(List<T> kandidaten, String Function(T) padVan) => [
      ...kandidaten.where((k) => !isVinylRip(padVan(k))),
      ...kandidaten.where((k) => isVinylRip(padVan(k))),
    ];

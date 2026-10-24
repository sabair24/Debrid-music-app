// Een vinyl-rip herkennen aan zijn pad.
//
// Saber, 24-10-2026: vinyl-rips zijn een andere bron dan de cd of de digitale uitgave — vaak 24/96 of 24/192, maar
// met naaldgeluid en een andere lengte ("Mademoiselle chante le blues": 235 s tegen 228 s). Zijn keuze: "alleen als
// ik kies". De app zet er dus nooit vanzelf een in de plaats van jouw versie (`magOpwaarderen`, de FLAC-wens), en in
// de zoeklijst staat er een label "vinyl" bij. Zoeken met "vinyl" erbij vond er veel: Daft Punk — Digital Love 165
// hi-res kopieën die de gewone zoekopdracht niet had.

final _vinyl = RegExp(r'vinyl|needle[\s_.-]*drop|\blp[\s_.-]*rip', caseSensitive: false);

/// Noemt [pad] (map of bestandsnaam) een vinyl-rip? "1988 - Mademoiselle chante (vinyl rip)", "[Japan Vinyl LP 24-96
/// kHz]", "needle drop", "LP rip". Een gewone "LP" in een albumnaam telt niet.
bool isVinylRip(String pad) => _vinyl.hasMatch(pad);

/// [kandidaten] met de vinyl-rips achteraan, verder in dezelfde volgorde ([padVan]: het pad van een kandidaat). Voor wat
/// de app zelf kiest (▶, de radio): een vinyl-rip alleen als er niets anders is — anders bleef ▶ stil terwijl er wel
/// een kopie van het nummer was.
List<T> vinylAchteraan<T>(List<T> kandidaten, String Function(T) padVan) => [
      ...kandidaten.where((k) => !isVinylRip(padVan(k))),
      ...kandidaten.where((k) => isVinylRip(padVan(k))),
    ];

/// De loopbaan van een artiest als een strook jaartallen.
///
/// **Waarom dit bestaat.** Onder de biografie komt een lint: geboren, elke plaat, overleden. Wijs
/// er een jaartal aan en het beeld eronder kruisvervaagt traag naar die periode. Alle grondstof lag
/// er al — `DiscoRelease.year` staat op elke regel van de discografie, en de geboorte- en
/// sterfjaren komen mee met de biografie die de app toch al ophaalt — dus dit kost **nul extra
/// verzoeken**.
///
/// **Waarom hier en niet in `lib/ui/`.** Het is lijstopbouw over domeinobjecten, en `lib/ui/` vrij
/// houden van domeinimports is wat `beeldvorm.dart` en `ui/speelvlak.dart` toetsbaar maakt zonder
/// widgetboom. Dit bestand is om dezelfde reden puur: geen `BuildContext`, geen `dart:io`.
library;

import 'discography.dart';
import 'enrichment.dart' show ArtiestFeiten;
import 'models.dart' show Album;

/// Waar een punt op het lint voor staat.
enum Jaarsoort { geboorte, oprichting, plaat, overlijden, ontbinding }

/// Eén jaartal op het lint.
class Jaarpunt {
  final int jaar;
  final Jaarsoort soort;

  /// Wat er onder het jaartal staat: "Geboren", "Thriller", "Overleden".
  final String label;

  /// Alleen bij [Jaarsoort.plaat] — waarmee de plaat in de eigen bibliotheek teruggevonden wordt.
  /// Zie [eigenPlaat]; dit is `discoKey(titel)` en dus dezelfde sleutel als de bezitsstreep.
  final String? plaatSleutel;

  /// Alleen bij [Jaarsoort.plaat], en alleen als een bron er een had.
  final String? hoesUrl;

  const Jaarpunt({
    required this.jaar,
    required this.soort,
    required this.label,
    this.plaatSleutel,
    this.hoesUrl,
  });
}

/// De vroegste opname die deze app serieus kan nemen.
///
/// Onder dit jaar is het geen jaartal maar rommel. Zowel Discogs als MusicBrainz sturen die: een
/// `0202`, een `19`, een tikfout van iemand die tien jaar geleden een release invoerde. Eén zo'n
/// getal rekt het lint uit over achttien eeuwen en dan staat alles wat er echt toe doet op elkaar
/// geplakt aan de rechterkant.
const int kEersteOpnamejaar = 1877;

/// Bouwt het lint.
///
/// **Alleen albums, tenzij dat te weinig oplevert.** `DiscoRelease.blok` scheidt een album al van
/// een uitgave-variant, een single en een verzamelaar. Zonder die zeef is het lint voor Enrique
/// Iglesias tweehonderd regels — dat is geen tijdlijn maar een veeg.
///
/// **Eén punt per jaar, en de keuze is BEPAALD.** Bij twee platen in hetzelfde jaar wint die met de
/// meeste bronnen, en bij gelijkspel de alfabetisch eerste. Dat het bepaald is, is niet netheid:
/// de artiestpagina voegt drie bronnen samen op volgorde van binnenkomst, en `main.dart` schrijft
/// daar al voor dat het samenvoegen bij het TEKENEN gebeurt "zodat elke hertekening hetzelfde
/// antwoord geeft ongeacht welke bron het eerst binnenkwam". Een lint dat onder je hand van
/// volgorde wisselt is precies wat die regel moet voorkomen.
List<Jaarpunt> bouwJaarlint({
  required List<DiscoRelease> platen,
  ArtiestFeiten? feiten,
  int maximum = 24,
  int? nu,
}) {
  final ditJaar = nu ?? DateTime.now().year;

  bool verstandig(int? j) => j != null && j >= kEersteOpnamejaar && j <= ditJaar + 1;

  // Van breed naar smal: eerst alleen echte albums, en pas verbreden als dat te mager is. Vier is
  // de ondergrens waaronder een lint geen lint meer is maar twee losse stipjes.
  List<DiscoRelease> zeef(Set<RecordKind> soorten) =>
      platen.where((p) => soorten.contains(p.blok) && verstandig(p.year)).toList();

  var gekozen = zeef({RecordKind.album});
  if (gekozen.length < 4) gekozen = zeef({RecordKind.album, RecordKind.albumVersie});
  if (gekozen.length < 4) gekozen = zeef(RecordKind.values.toSet());

  // Eén per jaar. Meeste bronnen wint; daarna alfabetisch, zodat gehusselde invoer hetzelfde
  // antwoord geeft.
  final perJaar = <int, DiscoRelease>{};
  for (final p in gekozen) {
    final jaar = p.year!;
    final zittend = perJaar[jaar];
    if (zittend == null) {
      perJaar[jaar] = p;
      continue;
    }
    if (p.sources.length > zittend.sources.length) {
      perJaar[jaar] = p;
    } else if (p.sources.length == zittend.sources.length &&
        p.title.toLowerCase().compareTo(zittend.title.toLowerCase()) < 0) {
      perJaar[jaar] = p;
    }
  }

  final punten = <Jaarpunt>[
    for (final e in perJaar.entries)
      Jaarpunt(
        jaar: e.key,
        soort: Jaarsoort.plaat,
        label: e.value.title,
        plaatSleutel: e.value.key,
        hoesUrl: e.value.cover,
      ),
  ]..sort((a, b) => a.jaar.compareTo(b.jaar));

  // De ankers: geboorte of oprichting ervóór, overlijden of ontbinding erna. Die twee mogen NOOIT
  // wegvallen bij het uitdunnen — ze zijn het begin en het einde van het verhaal.
  Jaarpunt? begin;
  if (verstandig(feiten?.opgerichtJaar)) {
    begin = Jaarpunt(jaar: feiten!.opgerichtJaar!, soort: Jaarsoort.oprichting, label: 'Opgericht');
  } else if (verstandig(feiten?.geborenJaar)) {
    begin = Jaarpunt(jaar: feiten!.geborenJaar!, soort: Jaarsoort.geboorte, label: 'Geboren');
  }

  Jaarpunt? einde;
  if (verstandig(feiten?.gestorvenJaar)) {
    einde = Jaarpunt(jaar: feiten!.gestorvenJaar!, soort: Jaarsoort.overlijden, label: 'Overleden');
  } else {
    final ontbonden = ArtiestFeiten.jaarUit(feiten?.ontbonden);
    if (verstandig(ontbonden)) {
      einde = Jaarpunt(jaar: ontbonden!, soort: Jaarsoort.ontbinding, label: 'Uit elkaar');
    }
  }

  final middenIn = _dun(punten, maximum - (begin == null ? 0 : 1) - (einde == null ? 0 : 1));
  return [
    if (begin != null) begin,
    ...middenIn,
    if (einde != null) einde,
  ];
}

/// Dunt de middenmoot uit tot er [ruimte] over is, met de eerste en de laatste altijd erin.
///
/// Gelijkmatig en niet "de laatste N": een loopbaan van veertig jaar hoort van begin tot eind te
/// lopen, ook als er in de jaren tachtig meer verscheen dan daarna.
List<Jaarpunt> _dun(List<Jaarpunt> punten, int ruimte) {
  if (ruimte < 2) return punten.isEmpty ? punten : [punten.first];
  if (punten.length <= ruimte) return punten;
  final uit = <Jaarpunt>[];
  final stap = (punten.length - 1) / (ruimte - 1);
  for (var i = 0; i < ruimte; i++) {
    uit.add(punten[(i * stap).round().clamp(0, punten.length - 1)]);
  }
  // Afronden kan hetzelfde punt twee keer aanwijzen; de volgorde blijft, de dubbele gaat eruit.
  final gezien = <int>{};
  return [
    for (final p in uit)
      if (gezien.add(p.jaar)) p,
  ];
}

/// De plaat uit je eigen bibliotheek die bij dit punt hoort, of null.
///
/// **[eigenPerSleutel] moet met `discoKey` gebouwd zijn** — dezelfde uitdrukking die de
/// artiestpagina al gebruikt voor de bezitsstreep: `{for (final a in mine) discoKey(a.title): a}`.
/// Dat staat er niet voor de netheid. `discoKey` waarschuwt in zijn eigen uitleg dat een tweede
/// idee van "dezelfde plaat" een album stil laat verdwijnen, en dit is precies de plek waar er een
/// geboren zou worden: een lint dat op iets ánders matcht dan het vinkje ernaast toont een hoes
/// voor een plaat die volgens de rest van de pagina niet van jou is.
Album? eigenPlaat(Jaarpunt punt, Map<String, Album> eigenPerSleutel) {
  final sleutel = punt.plaatSleutel;
  return sleutel == null ? null : eigenPerSleutel[sleutel];
}

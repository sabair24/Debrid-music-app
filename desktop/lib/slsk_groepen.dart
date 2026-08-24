/// Soulseek-treffers gebundeld tot gebruikers en mappen, zoals het Soulseek-programma zelf ze toont.
///
/// **Waarom dit een eigen bestand is.** Een zoekopdracht op een populair nummer levert hier
/// routineus drie- tot zevenduizend bestanden op, en die stonden tot nu toe als één platte lijst op
/// het scherm — dezelfde gebruiker twintig keer onder elkaar, zijn naam op elke regel opnieuw. Wat
/// een mens wil zien is: wie heeft het, wat heeft hij (een los nummer of het hele album), en van
/// wie is het het beste. Dat is precies een gebruiker → map → nummers-boom.
///
/// Alles hieronder is zuivere rekenkunde op een lijst: geen widgets, geen netwerk, geen `BuildContext`.
/// Dat is met opzet, want hier draait geen Flutter en geen toestel — een toets is het enige dat deze
/// volgorde kan controleren vóórdat hij op de telefoon staat.
///
/// Het rangschikken zelf staat hier **niet**. `rang` en `volgorde` komen van buiten mee, uit
/// `main.dart`, dat ze op zijn beurt uit `quality.dart` haalt. Er zijn in deze app al vier plekken
/// die iets van kwaliteit vinden; een vijfde erbij zou betekenen dat de lijst en de groepen bij
/// elkaar uit de pas kunnen lopen zonder dat iemand het merkt.
library;

import 'soulseek.dart';

/// Het pad zonder de bestandsnaam — de map waarin dit nummer bij die gebruiker staat.
///
/// Peers sturen een Windows-pad met backslashes (`@@abc\Music\Backstreet Boys\Backstreet's Back\03
/// Everybody.flac`), maar niet allemaal: er zitten er tussen met gewone schuine strepen. Allebei
/// worden ze hier gelijkgetrokken, anders is dezelfde map bij twee peers twee groepen.
///
/// Een naam zónder map levert een lege string op, en dat is de bedoeling: die bestanden horen bij
/// elkaar in de "losse nummers"-hoek van hun gebruiker, niet elk in een eigen map.
String mapVan(String filename) {
  final p = filename.replaceAll('/', '\\');
  final cut = p.lastIndexOf('\\');
  return cut < 0 ? '' : p.substring(0, cut);
}

/// Alleen de laatste laag van een pad: wat een mens "het album" noemt.
///
/// Het volledige pad is de juiste sleutel (twee gebruikers hebben allebei een map `Greatest Hits`,
/// en die zijn niet hetzelfde), maar het is een waardeloos etiket — `@@xyz\Muziek\Gedeeld\Pop\...`
/// zegt niets en past nergens. Vandaar twee functies in plaats van één.
String mapNaam(String pad) {
  final delen = pad.split('\\').where((d) => d.trim().isNotEmpty).toList();
  return delen.isEmpty ? '' : delen.last;
}

/// Vergelijkt twee bestandsnamen zoals een mens een tracklijst leest.
///
/// Gewoon alfabetisch zet `10 - ...` vóór `2 - ...`, en dan staat een album in een volgorde die
/// niemand herkent. Deze loopt de namen door in stukken cijfer / stukken tekst, en vergelijkt een
/// cijferstuk als getal. Hoofdletters tellen niet mee: `A2` en `a2` horen naast elkaar.
int natuurlijkeVolgorde(String a, String b) {
  final x = a.toLowerCase(), y = b.toLowerCase();
  var i = 0, j = 0;
  while (i < x.length && j < y.length) {
    final cx = x.codeUnitAt(i), cy = y.codeUnitAt(j);
    final dx = cx >= 0x30 && cx <= 0x39, dy = cy >= 0x30 && cy <= 0x39;
    if (dx && dy) {
      var i2 = i, j2 = j;
      while (i2 < x.length && x.codeUnitAt(i2) >= 0x30 && x.codeUnitAt(i2) <= 0x39) i2++;
      while (j2 < y.length && y.codeUnitAt(j2) >= 0x30 && y.codeUnitAt(j2) <= 0x39) j2++;
      // Voorloopnullen eraf: "03" en "3" zijn hetzelfde nummer, en `int.parse` zou op een
      // belachelijk lang cijferstuk (een tijdstempel in een naam) overlopen. Vandaar tryParse met
      // een terugval op tekst.
      final gx = int.tryParse(x.substring(i, i2)), gy = int.tryParse(y.substring(j, j2));
      if (gx == null || gy == null) {
        final t = x.substring(i, i2).compareTo(y.substring(j, j2));
        if (t != 0) return t;
      } else if (gx != gy) {
        return gx.compareTo(gy);
      }
      i = i2;
      j = j2;
      continue;
    }
    if (cx != cy) return cx.compareTo(cy);
    i++;
    j++;
  }
  return (x.length - i).compareTo(y.length - j);
}

/// Eén map van één gebruiker: meestal een album, soms één los nummer.
class SlskMap {
  /// Het volledige pad. Uniek binnen een gebruiker, en de sleutel waarop gegroepeerd is.
  final String pad;

  /// De laatste laag van [pad] — wat er op het scherm komt.
  final String naam;

  /// De nummers, al op nummervolgorde. Nooit leeg.
  final List<SoulseekFile> nummers;

  /// De rang van het béste nummer in deze map. Zie [groepeerSoulseek].
  final int rang;

  const SlskMap({required this.pad, required this.naam, required this.nummers, required this.rang});

  int get aantal => nummers.length;
  int get totaal {
    var n = 0;
    for (final f in nummers) {
      n += f.size;
    }
    return n;
  }

  /// Het best gerangschikte bestand — waar het keurmerk van de mapregel vandaan komt.
  SoulseekFile get beste => nummers.first;
}

/// Alles wat één gebruiker in dit zoekresultaat aanbiedt.
///
/// [vrij], [wachtrij] en [snelheid] komen niet per bestand over de lijn maar per antwoord van die
/// peer, dus ze horen hier thuis en niet op elke nummerregel apart. Dat scheelde ook meteen de
/// zesduizend keer herhaalde gebruikersnaam op het scherm.
class SlskGebruiker {
  final String naam;

  /// De mappen, beste eerst. Nooit leeg.
  final List<SlskMap> mappen;

  final bool vrij;
  final int wachtrij;
  final int snelheid;

  /// De rang van het beste bestand van deze gebruiker.
  final int rang;

  const SlskGebruiker({
    required this.naam,
    required this.mappen,
    required this.vrij,
    required this.wachtrij,
    required this.snelheid,
    required this.rang,
  });

  int get aantal {
    var n = 0;
    for (final m in mappen) {
      n += m.aantal;
    }
    return n;
  }

  int get totaal {
    var n = 0;
    for (final m in mappen) {
      n += m.totaal;
    }
    return n;
  }

  /// Het best gerangschikte bestand van deze gebruiker — het keurmerk in de kop.
  SoulseekFile get beste => mappen.first.beste;

  /// Eén map met één nummer erin: dan is er geen album om te tonen en slaat het scherm de
  /// maplaag over. "Gebruiker, **eventueel** album, en daar de liedjes."
  bool get losNummer => mappen.length == 1 && mappen.first.aantal == 1;
}

/// Bundelt een (al gefilterde) lijst bestanden tot gebruikers met mappen.
///
/// [rang] geeft de kwaliteitsrang van één bestand — in de app is dat `kwaliteitsRang` uit
/// `quality.dart`, één plat getal, waardoor de rang van een hele map gewoon het maximum van zijn
/// nummers kan zijn. [volgorde] is de vergelijker die de losse lijst ook gebruikt (`_besteEerst`),
/// zodat de boom en de platte lijst het nooit oneens zijn over wat beter is.
///
/// **De volgorde, en waarom precies deze.** Gevraagd is "de beste kwaliteit en per grote boven":
///
/// 1. kwaliteit van het beste bestand — daar kies je op;
/// 2. bij gelijke kwaliteit het grootst, want dat is bij Soulseek het verschil tussen een compleet
///    album en één afgeknepen nummer;
/// 3. dan vrije slots en de kortste wachtrij: van twee even goede kopieën wil je die die je nú
///    krijgt.
///
/// Binnen een map juist géén rangschikking maar **nummervolgorde** — daar is de kwaliteit toch
/// gelijk, en een album hoort op volgorde te staan.
///
/// Filteren moet hiervóór gebeuren, niet erna: een gebruiker van wie alle nummers wegvallen komt
/// dan vanzelf niet in de uitkomst voor, in plaats van als lege kop te blijven staan.
List<SlskGebruiker> groepeerSoulseek(
  Iterable<SoulseekFile> files, {
  required int Function(SoulseekFile) rang,
  required int Function(SoulseekFile, SoulseekFile) volgorde,
}) {
  // Twee lagen tegelijk opbouwen: gebruiker → pad → bestanden. Eén doorloop, want dit gebeurt op
  // elke rebuild van het scherm met duizenden bestanden.
  final perGebruiker = <String, Map<String, List<SoulseekFile>>>{};
  final peer = <String, SoulseekFile>{};
  for (final f in files) {
    (perGebruiker.putIfAbsent(f.username, () => {}).putIfAbsent(mapVan(f.filename), () => []))
        .add(f);
    // Slots, wachtrij en snelheid staan per antwoord van de peer op élk van zijn bestanden. Eentje
    // onthouden is genoeg.
    peer.putIfAbsent(f.username, () => f);
  }

  int rangVan(Iterable<SoulseekFile> fs) {
    var hoogste = 0;
    var eerste = true;
    for (final f in fs) {
      final r = rang(f);
      if (eerste || r > hoogste) {
        hoogste = r;
        eerste = false;
      }
    }
    return hoogste;
  }

  final gebruikers = <SlskGebruiker>[];
  perGebruiker.forEach((naam, mappenRuw) {
    final mappen = <SlskMap>[];
    mappenRuw.forEach((pad, nummers) {
      final gesorteerd = nummers.toList()
        ..sort((a, b) => natuurlijkeVolgorde(a.displayName, b.displayName));
      mappen.add(SlskMap(
        pad: pad,
        naam: mapNaam(pad),
        nummers: gesorteerd,
        rang: rangVan(gesorteerd),
      ));
    });
    mappen.sort((a, b) {
      if (a.rang != b.rang) return b.rang.compareTo(a.rang);
      if (a.totaal != b.totaal) return b.totaal.compareTo(a.totaal);
      return volgorde(a.beste, b.beste);
    });
    final p = peer[naam]!;
    gebruikers.add(SlskGebruiker(
      naam: naam,
      mappen: mappen,
      vrij: p.freeSlots,
      wachtrij: p.queueLength,
      snelheid: p.speed,
      rang: mappen.first.rang,
    ));
  });

  gebruikers.sort((a, b) {
    if (a.rang != b.rang) return b.rang.compareTo(a.rang);
    // De grootte van hun BESTE map, niet van alles bij elkaar: wie duizend losse nummers deelt is
    // daarmee nog geen betere bron voor dit ene album.
    final ta = a.mappen.first.totaal, tb = b.mappen.first.totaal;
    if (ta != tb) return tb.compareTo(ta);
    if (a.vrij != b.vrij) return a.vrij ? -1 : 1;
    if (a.wachtrij != b.wachtrij) return a.wachtrij.compareTo(b.wachtrij);
    // Laatste redmiddel: op naam. Zonder dit is de volgorde van twee gelijkwaardige gebruikers de
    // volgorde waarin hun antwoorden binnenkwamen, en die verschilt per zoekopdracht — dan springt
    // de lijst onder je vinger terwijl er niets veranderd is.
    return a.naam.compareTo(b.naam);
  });
  return gebruikers;
}

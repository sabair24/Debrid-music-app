/// Welke soort kopie een nummer is: studio, cd of vinyl — en welke soort je zelf koos.
///
/// Saber, 25-10-2026: *"bij zoek in high res, wil ik een paar optie's hebben. download in studio kwaliteit, download in
/// cd kwaliteit, en download in vinyl ... eerst mag de app doen wat hij wil en als ik dan hoor van hmmm, dit hoor ik
/// niet graag in die versie dan kan ik zelf altijd kiezen"*. Zijn antwoorden op de vragen erover:
///
/// * **studio** is elke 24-bit digitale kopie (ook 24/44,1 en 24/48), nooit een vinylrip — en sinds 28-10-2026 alleen
///   als de echtheidsmeter het niet tegenspreekt ([echteSoort]);
/// * **cd** is elke digitale 16/44,1: een cd-rip van Soulseek of een torrent, en TIDAL LOSSLESS — geen naar 16 bit
///   omgezette vinylrip;
/// * **vinyl** is een vinylrip, herkend aan waar hij vandaan kwam ([isVinylRip]): na het opbergen staat dat nergens
///   meer, dus het wordt hier bij het landen onthouden.
///
/// Alleen nieuwe downloads krijgen een soort (geen herkenning achteraf). Koos je zelf een soort voor een nummer
/// ([SoortInfo.gekozen]), dan waardeert de app dat nummer daarna alleen nog op binnen die soort ([magVanzelf]).
///
/// Op de pc staat het in `soorten.json`; een toestel krijgt het per nummer mee met de catalogus ([zetSoortVanPc]).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'echtheid.dart' show Bandbreedte, Echtheidsoordeel;
import 'paths.dart';
import 'vinyl.dart' show isVinylRip;

enum Kopiesoort { studio, cd, vinyl }

extension KopiesoortTekst on Kopiesoort {
  /// Het label naast de kwaliteit: "studio", "cd", "vinyl".
  String get naam => switch (this) { Kopiesoort.studio => 'studio', Kopiesoort.cd => 'cd', Kopiesoort.vinyl => 'vinyl' };

  /// In een zin: "studio-kwaliteit", "cd-kwaliteit", "vinyl".
  String get voluit => switch (this) {
        Kopiesoort.studio => 'studio-kwaliteit',
        Kopiesoort.cd => 'cd-kwaliteit',
        Kopiesoort.vinyl => 'vinyl',
      };
}

/// Uit [naam] (of null).
Kopiesoort? kopiesoortUit(Object? naam) => switch (naam) {
      'studio' => Kopiesoort.studio,
      'cd' => Kopiesoort.cd,
      'vinyl' => Kopiesoort.vinyl,
      _ => null,
    };

/// Wat een binnengekomen kopie is. [bronpad]: waar hij vandaan kwam (het pad bij de uploader, in de torrent, of
/// "TIDAL …"); [bits] en [hz] uit zijn kop. Null: geen van de drie — verliesgevend, 16/48, of de kop zegt niets.
///
/// [oordeel]: wat de echtheidsmeter over het bestand zei — de kop alleen maakt nog geen studio ([echteSoort]).
Kopiesoort? kopiesoortVan(
    {required String bronpad,
    required int bits,
    required int hz,
    bool verliesvrij = true,
    Echtheidsoordeel? oordeel}) {
  if (!verliesvrij) return null;
  final Kopiesoort? kop;
  if (isVinylRip(bronpad)) {
    kop = Kopiesoort.vinyl;
  } else if (bits >= 24) {
    kop = Kopiesoort.studio;
  } else if (bits == 16 && hz == 44100) {
    kop = Kopiesoort.cd;
  } else {
    kop = null;
  }
  return echteSoort(kop, oordeel);
}

/// [soort] zoals de echtheidsmeter hem laat staan ([o]): een studiokopie die de meter tegenspreekt ([studioTegengesproken])
/// is geen studio, en een bewezen uit een mp3 omgezette kopie ([Bandbreedte.afgekapt]) is geen studio, cd of vinyl.
/// Zonder oordeel blijft [soort] wat hij is: een meting die niet kon draaien, bewijst niets.
///
/// **Waarom (Saber, 28-10-2026).** Lil' Kim — How Many Licks? kwam als FLAC 24/44,1 van Soulseek, met een muur van 64 dB
/// op 20,85 kHz en een trede op 16 kHz: een mp3 die naar 24 bit was omgezet. De meter zag het ("vermoedelijk"), maar
/// de kop zei 24 bit, dus heette hij studio en bood de app hem aan als studioversie naast je cd. *"Ik wil geen fake
/// enkel echt dus dan moet de app gewoon wegsmijten … liever cd kwaliteit dan fake studio"*. Zonder soort is hij geen
/// versie ([versiebesluit] → gewoon), en beslist de keuring alleen: niet beter, dus weg.
///
/// Een vinylrip waarvan de kop liegt — "24/192" maar opgeschaald uit 44,1, of opgeblazen — is evengoed nep. Saber,
/// 28-10-2026, op de vraag of zo'n vinylrip als vinyl mag blijven: *"Weggooien"*. Een muur rond 20 kHz laat een vinylrip
/// wel staan: dat is vaak de omzetter waarmee hij opgenomen is.
Kopiesoort? echteSoort(Kopiesoort? soort, Echtheidsoordeel? o) {
  if (soort == null || o == null) return soort;
  if (o.band == Bandbreedte.afgekapt) return null;
  if (soort == Kopiesoort.studio && studioTegengesproken(o)) return null;
  if (soort == Kopiesoort.vinyl && o.isNep) return null;
  return soort;
}

/// De soort van je NUMMER ([soort], uit soorten.json, het register of de kop) zoals de meter hem bewijst ([o]) — voor de
/// vraag wat een binnenkomer ernaast is ([versiebesluit]). Strenger dan dat zou je versies kosten, dus alleen het bewezene:
///
/// * een opgeschaalde of opgeblazen "studio" is wat hij draagt, een cd. Een echte cd die binnenkomt is dan dezelfde soort,
///   en de keuring laat de eerlijke winnen ([vergelijkKwaliteit], [Kwaliteit.kopLiegt]) — als "studio" werd die cd een
///   versie naast hem, en bleef de nep het nummer;
/// * een bewezen omgezette kopie ([Bandbreedte.afgekapt]) heeft geen soort: wat er verliesvrij binnenkomt, vervangt hem;
/// * een muur rond 20 kHz ([Bandbreedte.vermoedelijk]) laat de soort staan. Niet bewezen, en als je nummer geen soort
///   meer had, werd een vinylrip die binnenkomt geen versie maar vervangt hij je nummer, of gaat hij weg.
Kopiesoort? ankerSoortGemeten(Kopiesoort? soort, Echtheidsoordeel? o) {
  if (soort == null || o == null) return soort;
  if (o.band == Bandbreedte.afgekapt) return null;
  if (soort == Kopiesoort.studio && o.isNep) return Kopiesoort.cd;
  return soort;
}

/// Spreekt de meter een studiokopie (24 bit, of meer dan 48 kHz) tegen? Opgeblazen (16 bits in gebruik), opgeschaald
/// (boven 24,5 kHz leeg), afgekapt, of een muur rond 20 kHz ([Bandbreedte.vermoedelijk]). Die laatste bewijst op zichzelf
/// niet dat het een mp3 is — het kan ook een filter in de master zijn — maar een studio is dan ook niet bewezen, en
/// Saber wil alleen echt.
bool studioTegengesproken(Echtheidsoordeel o) => o.isNep || o.isVermoedelijk;

/// Kan een kandidaat uit een zoeklijst [gevraagd] zijn? Waar als zijn pad en zijn opgave het zeggen, onwaar als ze
/// het tegenspreken, null als de uploader de diepte niet meldt ([bits] 0) — dan zegt pas het bestand het.
bool? kanSoortZijn(Kopiesoort gevraagd, {required String bronpad, int bits = 0, int hz = 0}) {
  final vinyl = isVinylRip(bronpad);
  if (gevraagd == Kopiesoort.vinyl) return vinyl;
  if (vinyl) return false;
  if (bits <= 0) return null;
  return kopiesoortVan(bronpad: bronpad, bits: bits, hz: hz) == gevraagd;
}

/// De soort van een nummer, en of je die zelf koos.
typedef SoortInfo = ({Kopiesoort soort, bool gekozen});

String _sleutel(String pad) =>
    pad.replaceAll('/', Platform.pathSeparator).replaceAll('\\', Platform.pathSeparator).toLowerCase();

final Map<String, SoortInfo> _soorten = {};

/// Wat de pc zegt, op een toestel waar de bestanden niet staan. Alleen voor deze sessie, zoals `zetVasteKeuzeVanPc`.
final Map<String, SoortInfo> _vanPc = {};

/// Gaat omhoog bij elke wijziging: de catalogus en de labels luisteren ernaar.
final ValueNotifier<int> soortUitgave = ValueNotifier<int>(0);

/// In een toets: dit bestand in plaats van dat in de appmap. **Zonder: in een toets niets naar schijf** — de appmap is in
/// een toets die van de echte app (APPDATA), en elke toets die een download laat landen, zet een soort.
@visibleForTesting
String? soortenBestandVoorToets;

File? get _bestand {
  if (soortenBestandVoorToets case final p?) return File(p);
  if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
  return File('$appDir${Platform.pathSeparator}soorten.json');
}

/// Inlezen bij het opstarten (op de pc). Een kapotte lijst begint leeg: dan staan er alleen geen labels.
Future<void> laadSoorten() async {
  try {
    final f = _bestand;
    if (f == null || !await f.exists()) return;
    final j = jsonDecode(await f.readAsString());
    if (j is! Map) return;
    for (final e in j.entries) {
      final v = e.value;
      final s = kopiesoortUit(v is Map ? v['s'] : null);
      if (s == null) continue;
      _soorten['${e.key}'] = (soort: s, gekozen: v is Map && v['g'] == true);
    }
    soortUitgave.value++;
  } catch (e) {
    debugPrint('soorten.json onleesbaar: $e');
  }
}

Timer? _bewaarKlok;

/// Bewaren, gebundeld: een album dat binnenkomt zijn twaalf landingen achter elkaar.
void _bewaarStraks() {
  if (_bestand == null) return;
  _bewaarKlok?.cancel();
  _bewaarKlok = Timer(const Duration(seconds: 2), () => unawaited(bewaarSoortenNu()));
}

@visibleForTesting
Future<void> bewaarSoortenNu() async {
  _bewaarKlok?.cancel();
  _bewaarKlok = null;
  try {
    final f = _bestand;
    if (f == null) return;
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode({
      for (final e in _soorten.entries) e.key: {'s': e.value.soort.naam, if (e.value.gekozen) 'g': true},
    }));
    await tmp.rename(f.path);
  } catch (e) {
    debugPrint('soorten.json niet te bewaren: $e');
  }
}

/// De soort van het nummer op [pad], of null (een ouder nummer, of geen van de drie).
SoortInfo? soortVoor(String pad) {
  final k = _sleutel(pad);
  return _soorten[k] ?? _vanPc[k];
}

/// Wat er net op [pad] landde. [soort] null wist: een nieuwe kopie zonder soort erft die van de vorige niet.
/// [gekozen]: je koos deze soort zelf. Een automatische landing van dezelfde soort laat een eigen keuze staan.
void zetSoort(String pad, Kopiesoort? soort, {bool gekozen = false}) {
  final k = _sleutel(pad);
  final oud = _soorten[k];
  if (soort == null) {
    if (_soorten.remove(k) == null) return;
  } else {
    final nieuw = (soort: soort, gekozen: gekozen || (oud?.gekozen == true && oud?.soort == soort));
    if (oud == nieuw) return;
    _soorten[k] = nieuw;
  }
  soortUitgave.value++;
  _bewaarStraks();
}

/// Het bestand is verplaatst: de soort verhuist mee (zoals [herNoemVasteKeuze]).
void herNoemSoort(String van, String naar) {
  final s = _soorten.remove(_sleutel(van));
  if (s == null) return;
  _soorten[_sleutel(naar)] = s;
  soortUitgave.value++;
  _bewaarStraks();
}

/// Uit de catalogus van de pc. Null wist.
void zetSoortVanPc(String pad, SoortInfo? info) {
  final k = _sleutel(pad);
  final oud = _vanPc[k];
  if (info == null) {
    if (_vanPc.remove(k) != null) soortUitgave.value++;
    return;
  }
  if (oud == info) return;
  _vanPc[k] = info;
  soortUitgave.value++;
}

/// Mag een automatische opwaardering van [pad] naar een kopie van soort [nieuw]? Ja, tenzij je zelf een soort koos:
/// dan alleen binnen die soort (Saber, 25-10-2026: koos cd → een betere cd mag, nooit vanzelf vinyl).
bool magVanzelf(String pad, Kopiesoort? nieuw) {
  final i = soortVoor(pad);
  if (i == null || !i.gekozen) return true;
  return nieuw == i.soort;
}

/// De soort die je zelf koos voor [pad], of null.
Kopiesoort? gekozenSoort(String pad) {
  final i = soortVoor(pad);
  return i != null && i.gekozen ? i.soort : null;
}

@visibleForTesting
void resetSoortenVoorToets() {
  _bewaarKlok?.cancel();
  _bewaarKlok = null;
  _soorten.clear();
  _vanPc.clear();
}

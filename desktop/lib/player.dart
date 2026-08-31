import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'artwork.dart' show kleurBuitenDeTekendraad;
import 'lan/stroomstand.dart' show grensUitUrl;
import 'models.dart';
import 'paths.dart';
import 'schudvolgorde.dart';
import 'warm_log.dart';

enum RepeatMode { off, all, one }

/// One item in a Radio / Smart-Shuffle queue: a local library track (plays
/// instantly) or an online recommendation resolved to a stream URL on demand.
class RadioItem {
  final String artist;
  final String title;
  final Track? local; // non-null => in the library
  String? url; // resolved online stream URL (cached after first resolve)
  bool failed = false;
  Future<String?>? pending; // in-flight resolve, so prefetch + open share one call
  RadioItem({required this.artist, required this.title, this.local});
  bool get isLocal => local != null;
}

/// The little of the player that the lockscreen needs. Named here, next to the thing that
/// implements it, so the compiler checks the two agree — and so what publishes to Control Center
/// can be exercised without libmpv, which cannot load in a test at all.
abstract interface class NowPlayingSource implements Listenable {
  Track? get current;
  bool get playing;
  Duration get position;
  Duration get duration;
  Uint8List? get currentCover;
  void playPause();

  /// Play en pause los van elkaar, want een schakelaar kent de stand van een SPEAKER niet.
  void speelAf();
  void pauzeer();

  /// Wat er klinkt, waar dan ook. Zie de gelijknamige leden in PlayerStore.
  bool get speeltErgens;
  Duration get positieErgens;
  Duration get duurErgens;
  Future<void> next();
  Future<void> prev();
  void seek(Duration d);

  /// Shuffle en herhalen, als STAND en niet als schakelaar.
  ///
  /// De app zelf heeft genoeg aan `toggleShuffle`/`cycleRepeat` — daar is één knop die rondloopt.
  /// Een hoofdunit werkt andersom: Android Auto stuurt "zet shuffle op aan" of "zet herhalen op
  /// één", en met alleen een omschakelaar wordt dat een gok over wat de huidige stand is. Zit die
  /// gok ernaast, dan zet je in de auto shuffle aan en gaat hij uit.
  bool get shuffle;
  RepeatMode get repeat;
  void zetShuffle(bool aan);
  void zetHerhaal(RepeatMode m);

  /// Even zachter, zonder de ingestelde stand te vergeten.
  ///
  /// Voor het geval dat een navigatiestem er doorheen praat: pauzeren is dan te veel, want het duurt
  /// twee seconden. Zie `bijOnderbreking` in now_playing.dart.
  void zetDemping(bool aan);
}

/// Re-resolve a queue against the library, or null when nothing anyone can see has changed.
///
/// Pulled out of [PlayerStore.refreshTracks] as a plain function so it can be tested: constructing
/// a PlayerStore loads libmpv, which does not exist in a test run, and this is the half with the
/// invariants worth pinning down.
///
/// [original] and [order] hold the SAME instances in different orders — order is original with
/// shuffle applied. Replacing values position by position therefore preserves the permutation
/// exactly, which is what keeps the playing index pointing at the playing song. Rebuilding order
/// from the resolver instead would silently unshuffle the queue.
({List<Track> original, List<Track> order})? remapQueue(
  List<Track> original,
  List<Track> order,
  Track? Function(String path) resolve,
) {
  final fresh = <String, Track>{};
  var changed = false;
  for (final t in original) {
    final n = resolve(t.path);
    // Null is not an answer: the album is mid-regroup, or this is a stream with no library entry.
    // Keeping what we have beats blanking the bar — the same rule refreshCover follows.
    if (n == null) continue;
    fresh[t.path] = n;
    if (!t.sameDisplayAs(n)) changed = true;
  }
  if (!changed) return null;
  return (
    original: [for (final t in original) fresh[t.path] ?? t],
    order: [for (final t in order) fresh[t.path] ?? t],
  );
}

/// De speaker die de wachtrij op dit moment heeft, voor zover de SPELER het moet weten.
///
/// Klein met opzet: de speler hoeft niet te weten wat daar staat te spelen, alleen dat er een
/// speaker is en hoe je hem bedient. `SpeakerTarget` voldoet hier al aan.
///
/// Dit bestaat omdat de bediening van buiten de app -- de mediatoetsen op je afstandsbediening, het
/// vergrendelscherm, een bluetoothknop, Android Auto -- via `NowPlayingSource` rechtstreeks bij
/// [PlayerStore] uitkomt en dus niet langs de castcontrole van het scherm loopt. Gemeten op de
/// Shield op 16-08-2026: één druk op de mediatoets "volgende" liet libmpv hier beginnen, waarop de
/// Sonos Amp terugviel op zijn tv-ingang en de muziek stopte -- terwijl het scherm "Speelt op Sonos
/// Amp" bleef tonen met een balk die gewoon doorliep. De knoppen op het scherm gingen wél goed, en
/// dat is precies waarom het zo lang onopgemerkt bleef.
/// Wie de bediening moet krijgen: de speaker, of niemand (en dan doet de speler het zelf).
///
/// Los van [PlayerStore] om dezelfde reden als [ordenVoor] en [hoesOpScherm]: die klasse bouwt een
/// libmpv-speler in een veld en is in geen enkele test te maken. Zie media_keys_cast_test.dart.
///
/// Het onderscheid tussen "geen speaker" en "wel een speaker, maar hij heeft de muziek niet" is de
/// hele grap: op een pc of Mac staat er altijd een [Speakerbediening] klaar, en zolang je niet cast
/// hoort de bediening gewoon lokaal te blijven.
Speakerbediening? bedienVia(Speakerbediening? speaker) =>
    speaker != null && speaker.isCasting ? speaker : null;

abstract class Speakerbediening {
  bool get isCasting;
  bool get isPlaying;
  Duration? get position;
  Duration? get duration;
  Future<void> playPause();
  Future<void> next();
  Future<void> previous();
  Future<void> seekTo(Duration to);
}

/// Welke hoes er op het scherm hoort, gegeven wat de bibliotheek op dit moment weet.
///
/// Los van [PlayerStore] om dezelfde reden als [ordenVoor]: die bouwt een libmpv-speler in een veld
/// en is daardoor in geen enkele test te maken -- terwijl dit nu juist de regel is die bepaalt of je
/// het album ziet dat klinkt. Zie player_cover_test.dart.
///
/// [zelfdeNummer] is het hele verschil, en het stond er eerst niet in.
///
/// * Dezelfde plaat, opnieuw opgezocht omdat de bibliotheek iets gecorrigeerd heeft: een leeg
///   antwoord is geen antwoord. Het album wordt op dat moment hergroepeerd en de hoes die het krijgt
///   is nog niet bekend; de balk blanco maken is dan erger dan hem laten staan.
/// * De SPEAKER schuift door naar een ander nummer: precies andersom. Wat er staat hoort dan bij een
///   album dat niet meer speelt, en dat liegt harder dan een leeg vakje. Zonder dit onderscheid bleef
///   op de Mac de hoes hangen van het album waar het casten mee begon.
Uint8List? hoesOpScherm(Uint8List? staatEr, Uint8List? gevonden, {required bool zelfdeNummer}) =>
    gevonden ?? (zelfdeNummer ? staatEr : null);

/// De speelvolgorde, met [anker] als het nummer dat blijft klinken.
///
/// Los van [PlayerStore] omdat die een libmpv-speler in een veld bouwt en dus in geen enkele test te
/// maken is -- terwijl juist deze regel gelijk moet lopen met wat een SPEAKER in handen heeft. Twee
/// eigenschappen doen ertoe, en die staan in cast_control_test.dart:
///
/// * op de teruggegeven index staat het anker, dus wie deze lijst doorgeeft hoeft niets te heropenen;
/// * er valt niets weg en er komt niets bij, dus dezelfde nummers in een andere volgorde.
///
/// Zonder de eerste zou shuffle tijdens het casten het lopende nummer opnieuw laten beginnen; zonder de
/// tweede zouden de app en de speaker uit elkaar lopen en toont het scherm een ander album dan er klinkt.
///
/// **[reedsGespeeld] is de reparatie van "hij speelt telkens hetzelfde".** Wat al geklonken heeft
/// blijft vooraan staan en wordt niet opnieuw uitgedeeld; alleen de staart wordt geschud. Zonder dit
/// bouwde één tik op het shuffle-icoontje een compleet nieuwe volgorde van ALLES met de index terug
/// op nul — alles wat je net gehoord had stond weer voor je. Android Auto loopt langs diezelfde knop,
/// dus in de auto was dat één druk.
///
/// De prefix blijft ÍN de teruggegeven lijst staan. Dat moet: `cast_control_test.dart` eist dezelfde
/// lengte en dezelfde verzameling, en de speaker meldt zijn plek terug als index in deze lijst.
///
/// **[gewicht] is de weging.** Null betekent gelijk gewicht, en dat is wat een verse installatie en
/// elke toets krijgt. Zie `schudvolgorde.dart` voor wat er anders gebeurt.
({List<Track> order, int index}) ordenVoor(
  List<Track> alles,
  Track? anker, {
  required bool shuffle,
  List<Track> reedsGespeeld = const <Track>[],
  double Function(Track)? gewicht,
  Random? toeval,
}) {
  if (shuffle && alles.isNotEmpty) {
    // Eerst de prefix eruit, dan pas het anker: staat het anker toevallig ook in de prefix, dan is
    // dat de vorige beurt van een nummer dat nu opnieuw klinkt, en niet hetzelfde exemplaar.
    final prefix = zonder(reedsGespeeld, [if (anker != null) anker]);
    final rest = zonder(alles, [...prefix, if (anker != null) anker]);
    final geschud = gewicht == null
        ? (List.of(rest)..shuffle(toeval))
        : gewogenVolgorde(rest, gewicht: gewicht, toeval: toeval ?? Random());
    // De kop is wat vaststaat: het verleden, en daarachter wat er nu klinkt.
    final kop = [...prefix, if (anker != null) anker];
    // Spreiden over de HELE lijst maar alleen vanaf de staart, zodat het eerste nieuwe nummer ook
    // niet botst met wat er net klonk — en zodat er in de kop niets meer beweegt.
    final volledig = uitElkaar([...kop, ...geschud], vanaf: kop.length);
    return (
      order: volledig,
      // Het anker staat achteraan de kop; is er geen anker, dan begint het bij het eerste nieuwe.
      index: anker == null ? kop.length : kop.length - 1,
    );
  }
  final order = List.of(alles);
  return (
    order: order,
    index: anker == null ? 0 : order.indexWhere((t) => t.path == anker.path).clamp(0, order.length - 1),
  );
}

/// Staat het wachtrijpaneel open?
///
/// Een eigen notifier omdat de knop en het paneel ver uit elkaar liggen: de knop zit in de
/// spelerbalk onderaan, het paneel hangt naast de inhoud daarboven. Ze delen geen ouder waar een
/// `setState` bij allebei aankomt, en de hele boom laten hertekenen voor één schakelaar zou elke
/// albumhoes op het scherm opnieuw laten bouwen.
class WachtrijPaneel extends ChangeNotifier {
  bool _open = false;
  bool get open => _open;

  void wissel() {
    _open = !_open;
    notifyListeners();
  }

  void sluit() {
    if (!_open) return;
    _open = false;
    notifyListeners();
  }
}

/// De hele wachtrij in één waarde: de aangeleverde volgorde, de speelvolgorde, en waar we zijn.
typedef Wachtrij = ({List<Track> origineel, List<Track> volgorde, int index});

/// [nieuw] erbij — achter het lopende nummer, of achteraan.
///
/// Los van [PlayerStore] om dezelfde reden als [ordenVoor]: die klasse bouwt een libmpv-speler in
/// een veld en is in geen enkele test te maken, terwijl juist dit rekenwerk moet kloppen.
///
/// Beide lijsten, altijd. [_rebuildOrder] bouwt de speelvolgorde opnieuw uit het origineel zodra
/// iemand shuffle aantikt — wat alleen in de speelvolgorde staat is dan weg, zonder foutmelding.
///
/// In het origineel achter hetzelfde NUMMER en niet achter dezelfde index: bij shuffle staan de twee
/// lijsten in een andere volgorde, en dan wijst een index in de verkeerde lijst.
Wachtrij voegInWachtrij(Wachtrij w, List<Track> nieuw, {required bool hierna}) {
  if (nieuw.isEmpty) return w;
  final volgorde = List.of(w.volgorde), origineel = List.of(w.origineel);
  if (hierna) {
    final huidig = w.index >= 0 && w.index < volgorde.length ? volgorde[w.index] : null;
    volgorde.insertAll((w.index + 1).clamp(0, volgorde.length), nieuw);
    final na = huidig == null ? -1 : origineel.indexWhere((t) => t.path == huidig.path);
    origineel.insertAll((na + 1).clamp(0, origineel.length), nieuw);
  } else {
    volgorde.addAll(nieuw);
    origineel.addAll(nieuw);
  }
  return (origineel: origineel, volgorde: volgorde, index: w.index);
}

/// Het nummer op [plek] eruit. Raakt geen bestand aan.
///
/// Het lopende nummer kan er niet uit: dat is geen "deze hoef ik straks niet" maar "stop" of
/// "volgende", en die knoppen bestaan al. Het hier stilzwijgend als iets anders uitvoeren maakt van
/// één druk een onvoorspelbare handeling.
Wachtrij haalUitWachtrijLijst(Wachtrij w, int plek) {
  if (plek < 0 || plek >= w.volgorde.length || plek == w.index) return w;
  final volgorde = List.of(w.volgorde), origineel = List.of(w.origineel);
  final weg = volgorde.removeAt(plek);
  // Op instantie, met het pad als terugval: staat hetzelfde nummer twee keer in de wachtrij — en dat
  // mag — dan moet precies díé eruit en niet de eerste die erop lijkt.
  var oi = origineel.indexWhere((t) => identical(t, weg));
  if (oi < 0) oi = origineel.indexWhere((t) => t.path == weg.path);
  if (oi >= 0) origineel.removeAt(oi);
  return (
    origineel: origineel,
    volgorde: volgorde,
    index: plek < w.index ? w.index - 1 : w.index,
  );
}

/// Van [van] naar [naar] slepen.
///
/// Bij shuffle UIT lopen beide lijsten gelijk en verhuist het in allebei. Bij shuffle AAN is het
/// origineel de albumvolgorde en de speelvolgorde die van jou — dan verhuist alleen die laatste, en
/// gaat het handwerk verloren zodra je shuffle uit en weer aan tikt. Dat is inherent aan een
/// geschudde lijst die uit het origineel wordt herbouwd; de schudvolgorde als nieuw origineel
/// opslaan zou de albumvolgorde voorgoed weggooien.
Wachtrij verplaatsInWachtrijLijst(Wachtrij w, int van, int naar, {required bool shuffle}) {
  if (van < 0 || van >= w.volgorde.length || w.volgorde.isEmpty) return w;
  final doel = naar.clamp(0, w.volgorde.length - 1);
  if (van == doel) return w;

  final volgorde = List.of(w.volgorde);
  final t = volgorde.removeAt(van);
  volgorde.insert(doel, t);

  var origineel = w.origineel;
  if (!shuffle) {
    origineel = List.of(w.origineel);
    var oi = origineel.indexWhere((x) => identical(x, t));
    if (oi < 0) oi = origineel.indexWhere((x) => x.path == t.path);
    if (oi >= 0) {
      origineel.removeAt(oi);
      origineel.insert(doel.clamp(0, origineel.length), t);
    }
  }

  // De index volgt het nummer dat klinkt, niet zijn oude plaatsnummer.
  var index = w.index;
  if (van == w.index) {
    index = doel;
  } else if (van < w.index && doel >= w.index) {
    index--;
  } else if (van > w.index && doel <= w.index) {
    index++;
  }
  return (origineel: origineel, volgorde: volgorde, index: index);
}

/// Eén regel van de radio, zoals een lijst hem toont.
///
/// [eigen] is het onderscheid waar alles om draait: staat dit nummer als BESTAND in je bibliotheek,
/// of is het (nog) niets meer dan een artiest en een titel? Alleen het eerste kan zonder wachten
/// klinken, en alleen het tweede mag straks weer weg.
typedef Radioregel = ({Track nummer, bool eigen, bool mislukt});

/// De radio als een lijst nummers, zodat een paneel er niets bijzonders voor hoeft te weten.
///
/// **Waarom dit bestond te maken.** [PlayerStore.radioQueue] had tot nu toe geen enkele lezer. Zet
/// je een radio aan, dan bleef het wachtrijpaneel de lijst tonen van vóór de radio — het toonde dus
/// iets wat niet ging klinken. Dat is geen ontbrekende voorziening maar een onwaarheid, en die
/// verdwijnt door de radio in dezelfde vorm aan te bieden als een gewone wachtrij.
///
/// Los van [PlayerStore] om dezelfde reden als [ordenVoor] en [voegInWachtrij]: die klasse bouwt een
/// libmpv-speler in een veld en is in geen enkele toets te maken.
///
/// Een nummer dat je niet hebt krijgt een [Track] met het adres als pad, of met een leeg pad als er
/// nog geen adres is. Leeg is goed: elke opzoeking op pad — de hoes, het echtheidsmerk — vindt dan
/// niets en toont niets, in plaats van per ongeluk de hoes van een ander nummer te pakken.
List<Radioregel> radioAlsRij(List<RadioItem> radio) => [
      for (final it in radio)
        (
          nummer: it.local ??
              Track(path: it.url ?? '', title: it.title, artist: it.artist, album: ''),
          eigen: it.isLocal,
          // Mislukt telt alleen als er ook geen bestand ligt: een nummer dat je zelf hebt is er,
          // wat een eerdere zoektocht online ook gedaan heeft.
          mislukt: !it.isLocal && it.failed && it.url == null,
        ),
    ];

/// Wat er moet gebeuren als de speler zegt dat een nummer afgelopen is.
enum NaHetEinde {
  /// Gewoon door naar het volgende.
  volgende,

  /// Herhaalstand "dit nummer": nog een keer van voren af aan.
  ditNummerOpnieuw,

  /// Dit was geen einde maar een breuk. Opnieuw openen, op dezelfde plek.
  stroomHervatten,
}

/// Hoeveel er nog te spelen moet zijn voordat "afgelopen" een breuk heet.
///
/// Ruim genomen. Een nummer dat een halve seconde eerder ophoudt dan zijn looptijd zegt is gewoon
/// afgelopen — dat verschil zit in afrondingen en in de stilte aan het eind. Tien seconden is
/// onmiskenbaar: dat is geen afronding meer.
const _breukMarge = Duration(seconds: 10);

/// Hoe vaak we een afgebroken stroom opnieuw proberen voordat we doorgaan.
///
/// Niet oneindig: staat de pc echt uit, dan zou de app op één nummer blijven hangen zonder ooit iets
/// te zeggen. Na drie pogingen gaat hij verder, en het logboek vertelt waarom.
const _maxHervatpogingen = 3;

/// **Het geval waarvoor dit bestaat, gemeld op 13-08-2026 uit de auto:** "ik hoor de muziek wel,
/// maar hij skipt naar het volgende midden in een track."
///
/// De telefoon streamt van de pc. Valt die verbinding onderweg even weg, dan ziet mpv het einde van
/// het bestand en meldt netjes "afgelopen" — en de app deed precies wat haar gevraagd werd: door
/// naar het volgende nummer. Onderweg op mobiel internet gebeurt dat om de haverklap, en van buiten
/// lijkt het alsof de app zelf staat te springen.
///
/// Een einde ver voor de looptijd is geen einde. De positie en de looptijd staan er allebei; er
/// keek alleen niemand naar.
NaHetEinde watNaHetEinde({
  required Duration positie,
  required Duration duur,
  required RepeatMode herhaal,
  required int mislukt,
}) {
  // Zonder looptijd valt er niets te vergelijken. Dan maar het oude gedrag: doorgaan.
  final gebroken = duur > Duration.zero && duur - positie > _breukMarge;
  if (gebroken && mislukt < _maxHervatpogingen) return NaHetEinde.stroomHervatten;
  return herhaal == RepeatMode.one ? NaHetEinde.ditNummerOpnieuw : NaHetEinde.volgende;
}

/// Bewaakt of "speelt" ook betekent dat er iets speelt.
///
/// **Gemeten op 12-08-2026, en het is precies hoe een app kapot aanvoelt terwijl er niets kapot is.**
/// De pc stond uit. De telefoon haalt zijn muziek daarvandaan, dus mpv wachtte op een verbinding die
/// niet kwam — maar hij meldde geen fout. De mediasessie zei achttien seconden lang
/// `state=PLAYING(3), position=0`, de knop toonde een pauzestreep, en er was geen enkele audiostroom.
/// Geen melding, geen uitleg, niets om op te reageren.
///
/// Een fout van mpv opvangen is niet genoeg: die komt alleen als de bron actief geweigerd wordt. Een
/// bron die simpelweg nooit antwoordt, of een pc die midden in een nummer verdwijnt, geeft dit beeld
/// — en dat is nu juist het geval dat thuis het vaakst voorkomt.
///
/// Los van [PlayerStore] om dezelfde reden als [ordenVoor] en [voegInWachtrij]: die klasse bouwt een
/// libmpv-speler in een veld en is in geen enkele toets te maken, terwijl juist deze regel moet
/// kloppen. De klok komt van buiten, zodat een toets geen tien seconden hoeft te duren.
class Stilstandwacht {
  Stilstandwacht({this.geduld = const Duration(seconds: 10)});

  /// Hoe lang de teller stil mag staan voordat er iets te melden valt.
  ///
  /// Ruim genomen: bij het openen van een nummer over het netwerk staat de teller even stil terwijl
  /// er gebufferd wordt, en een melding die daar al op afgaat is erger dan geen melding.
  final Duration geduld;

  Duration? _positie;
  DateTime? _sinds;

  /// Voer de laatst bekende toestand in. Geeft true zodra het te lang stilstaat.
  bool voeden({required bool speelt, required Duration positie, required DateTime nu}) {
    // Pauze is geen stilstand. Wie zelf op pauze drukt hoort geen klacht te krijgen.
    if (!speelt) {
      reset();
      return false;
    }
    if (_positie != positie || _sinds == null) {
      _positie = positie;
      _sinds = nu;
      return false;
    }
    return nu.difference(_sinds!) >= geduld;
  }

  /// Vergeten wat er stilstond. Bij een nieuw nummer, of zodra er weer iets beweegt.
  void reset() {
    _positie = null;
    _sinds = null;
  }
}

/// Native (libmpv) player with a queue, shuffle, repeat and a Radio mode.
class PlayerStore extends ChangeNotifier implements NowPlayingSource {
  /// **Ruim vooruit lezen, want de muziek komt over het netwerk.**
  ///
  /// Gemeld op 15-08-2026 na een rit: draadloos Android Auto verloor geregeld de verbinding, "zeker
  /// bij hi-res", en met de bluetooth-oordopjes haperde het op dezelfde bestanden. Aan de kabel was
  /// alles vlekkeloos — en dat is precies de aanwijzing: het ligt niet aan het decoderen maar aan de
  /// aanvoer.
  ///
  /// Wat er gebeurt: de telefoon haalt een FLAC van de pc (een 24/192 is al gauw 5 à 6 Mbit/s) over
  /// dezelfde wifi die tegelijk de draadloze Android Auto-verbinding draagt. Elke keer dat die twee
  /// om de lucht vechten valt de aanvoer even stil.
  ///
  /// media_kit zet uit zichzelf alleen `demuxer-max-bytes` — hoe GROOT de buffer mag worden. Hoe VER
  /// mpv vooruit leest staat daarmee nog op zijn standaard van een paar seconden, en dan is elke
  /// hapering van meer dan dat meteen een gat in de muziek. De grens hieronder is met opzet ruim: bij
  /// audio kost vooruitlezen bijna niets, en een heel nummer vooruit hebben maakt een wifi-dip
  /// onhoorbaar.
  ///
  /// De uitgang van het toestel is gemeten op 48 kHz / 16 bit — een hi-res bestand wordt dus hoe dan
  /// ook omgerekend, ook aan de kabel. Dat is niet waar het misging.
  final Player _player = Player(
    configuration: const PlayerConfiguration(bufferSize: 64 * 1024 * 1024),
  );

  /// De vooruitleesinstellingen die media_kit niet zelf zet.
  ///
  /// Achteraf en niet via [PlayerConfiguration], want die kent ze niet. Alles in een `try`: mislukt
  /// dit, dan speelt de app precies zoals daarvoor — een instelling die het afspelen kan breken is
  /// erger dan geen instelling.
  /// Hoeveel seconden er nu vooruit gelezen wordt. Zie [zetVooruitlezen].
  int _vooruit = 300;

  /// Het vooruitlezen bijstellen omdat het toestel op een ander net zit.
  ///
  /// **Op wifi moet dit 300 blijven** — dat is de reparatie hierboven, en daar wordt niet aan
  /// getornd. Op mobiele data is vooruitlezen niet gratis meer: 300 seconden op de cd-stand is
  /// ruwweg vierendertig megabyte per nummer, en skip je na twintig seconden door, dan gooi je
  /// tweeëndertig megabyte weg waar je voor betaald hebt. Zie `netsoort.dart`.
  ///
  /// `cache` en `stream-buffer-size` blijven altijd staan: dat is de anti-hik-knop en die kost
  /// niets.
  Future<void> zetVooruitlezen({required int secs}) async {
    if (secs == _vooruit) return;
    _vooruit = secs;
    await _zetVooruitlezen(secs: secs);
  }

  Future<void> _zetVooruitlezen({int secs = 300}) async {
    final p = _player.platform;
    if (p is! NativePlayer) return;
    try {
      // Aanzetten in plaats van 'auto': auto laat het van de bron afhangen, en een LAN-stream ziet
      // er voor mpv uit als een lokaal bestand dat geen cache nodig heeft.
      await p.setProperty('cache', 'yes');
      // Vijf minuten vooruit. Bij audio is dat een handvol megabytes.
      await p.setProperty('cache-secs', '$secs');
      await p.setProperty('demuxer-readahead-secs', '$secs');
      // En de leesbuffer van de stroom zelf omhoog (standaard 128 kB): op een schokkerige
      // verbinding scheelt dat het aantal keren dat er helemaal niets binnenkomt.
      await p.setProperty('stream-buffer-size', '4MiB');
    } catch (e) {
      _log?.line('vooruitlezen niet ingesteld: $e');
    }
  }
  List<Track> _original = [];
  List<Track> _order = [];
  int _index = -1;

  // Radio / Smart Shuffle
  List<RadioItem> _radio = [];
  int _radioIndex = -1;
  int _radioGen = 0; // bumped on every (re)open so a stale async open aborts
  bool radioMode = false;
  String radioStatus = '';
  Future<String?> Function(String artist, String title)? resolver;
  Future<List<RadioItem>> Function()? radioExtend; // fetch more items to keep radio endless
  bool _extending = false;
  int _radioSession = 0; // bumped per playRadio() so a stale extend can't pollute a new radio
  List<RadioItem> get radioQueue => _radio;
  int get radioIndex => _radioIndex;

  /// De radio is voorbij. Precies één keer, hoe je hem ook verlaat.
  ///
  /// **Waarom een haak en geen `if` op de vijf plekken.** Een radio wordt niet afgesloten, hij houdt
  /// gewoon op: een nummer aantikken, naar een speaker sturen, "Shuffle alles", een adres afspelen,
  /// of de app opnieuw starten — vijf plekken die alle vijf `radioMode` op false zetten. Wie daar iets
  /// aan wil hangen (opruimen, een overzicht tonen) moet dat vijf keer doen, en dan denkt er vroeg of
  /// laat eentje niet aan. Vandaar [_verlaatRadio], die alle vijf aanroepen.
  void Function(List<RadioItem> gespeeld)? bijRadioEinde;

  /// De hoes van wat er NU speelt.
  ///
  /// Een setter en geen kaal veld, en dat is de hele reden dat dit hier staat: elke plek die de hoes
  /// wisselt — een nummer openen, een wachtrij aannemen, een speaker de muziek overnemen — hoort
  /// meteen ook de KLEUR van die hoes te laten uitrekenen. Als veld moest elk van die acht plekken
  /// daar zelf aan denken, en dan denkt er vroeg of laat eentje niet aan.
  @override
  Uint8List? get currentCover => _hoesNu;
  Uint8List? _hoesNu;

  set currentCover(Uint8List? bytes) {
    if (identical(bytes, _hoesNu)) return;
    _hoesNu = bytes;
    // De kleur van de vorige plaat hoort niet bij deze. Liever even geen was dan de verkeerde.
    wasKleur = null;
    if (bytes != null) unawaited(_wasUitHoes(bytes));
  }

  /// De hoofdkleur van de hoes die nu speelt, als ARGB — of null.
  ///
  /// **Waarom hier en niet per scherm.** Het speelscherm, de spelerbalk onderaan en de smalle balk op
  /// een telefoon willen alle drie dezelfde kleur, en het uitrekenen ervan decodeert een plaatje van
  /// soms vijf megabyte. Drie schermen die dat elk apart doen is drie keer datzelfde werk én drie
  /// antwoorden die kunnen verschillen — precies wat er in ronde 2 dreigde te ontstaan.
  ///
  /// Null bij een zwart-witte hoes; zie `dominantColour`. Geen was is beter dan een grijze.
  int? wasKleur;

  Future<void> _wasUitHoes(Uint8List bytes) async {
    int? kleur;
    try {
      kleur = await kleurBuitenDeTekendraad(bytes);
    } catch (_) {
      return; // een hoes die niet te lezen is laat de schermen gewoon zoals ze waren
    }
    // Er speelt intussen iets anders: dit antwoord is van de vorige plaat.
    if (!identical(bytes, _hoesNu) || kleur == wasKleur) return;
    wasKleur = kleur;
    notifyListeners();
  }

  @override
  bool shuffle = false;
  @override
  RepeatMode repeat = RepeatMode.off;

  @override
  bool playing = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = Duration.zero;

  /// De speaker die de muziek heeft, gezet door main. Zie [Speakerbediening].
  ///
  /// Null op een toestel dat nooit cast; niet-null maar `isCasting == false` zodra er een speaker
  /// gekozen KAN worden. Alleen dat tweede geval leidt bediening om.
  Speakerbediening? speaker;

  /// De speaker als hij de muziek op dit moment ook echt heeft.
  Speakerbediening? get _bijSpeaker => bedienVia(speaker);

  /// Resolves an album cover for a track (set by main to LibraryStore.coverForTrack)
  /// so the flat Tracks queue shows the right cover per song.
  Uint8List? Function(Track)? coverResolver;

  /// Looks a queued track up again by path (set by main to LibraryStore.trackByPath), so a
  /// correction reaches what is playing. See [refreshTracks].
  Track? Function(String path)? trackResolver;

  /// The library's "something a track is CALLED has changed" counter. See [refreshTracks] for why
  /// this is a counter and not a comparison.
  int Function()? metaRevOf;
  int _seenMetaRev = -1;

  /// How many times [refreshTracks] actually walked the queue. The point of the counter above is
  /// that this stays near zero while covers stream in; a test that cannot see it cannot prove that.
  @visibleForTesting
  int remapCount = 0;

  /// Last step before a path is handed to libmpv. Identity on the machine that owns the music; on
  /// a Mac or an iPad it turns a library path into a stream URL carrying the pairing token.
  ///
  /// It happens HERE, and not in the stored path, because the path is the identity key for
  /// favourites, playlists and resume: baking a token into it would break all three the moment you
  /// paired again, and would write the key for your library into a plain file on disk.
  String Function(String path) mediaResolver = (p) => p;

  /// Where we are, for the other devices. Set by main to the LAN sharing store, so pausing here
  /// and carrying on from the iPad works in both directions. Called on the same throttle as the
  /// local resume file — every few seconds, and always on pause or a track change.
  void Function(Track track, Duration position, bool playing, List<Track> queue, int index)?
      onProgress;

  /// A track was actually LISTENED TO — feeds the shared play counts and "recently played".
  ///
  /// **Niet meer bij het openen.** Tot 28-08-2026 vuurde dit in [_openCurrent], dus doorskippen op
  /// zoek naar iets telde vol mee — en die telling is precies wat de shuffle gebruikt om te bepalen
  /// wat je vaak gehoord hebt. Zie [_telMee] en [telMeeAlsGespeeld].
  void Function(Track track)? onPlayed;

  /// Hoe vaak en hoe lang geleden een nummer geklonken heeft. Ingehangen vanuit main.dart; null op
  /// een toestel zonder gedeelde staat, en dan is de shuffle gewoon gelijk gewogen.
  Speelstand? Function(Track track)? speelstandVan;

  /// Wat je duim er nog bij optelt: groen zwaarder, rood lichter.
  ///
  /// Een FACTOR en geen oordeel, en dat is bewust: zo hoeft de speler niets van duimen te weten en
  /// blijft `oordeelBonus` op één plek staan. main.dart hangt hem erin.
  double Function(Track track)? oordeelWeging;

  /// Wat er deze sessie geopend werd, ongeacht of het als beluisterd telde. Zie [_gewichtVanNummer].
  final Set<String> _geopendDezeSessie = {};

  /// Opgetelde luistertijd van het lopende nummer — niet de stand van de teller.
  ///
  /// **Dat verschil is de hele reparatie.** Naar de stand kijken telt een nummer mee dat je op 80%
  /// opendraaide en meteen wegklikte, en telt een nummer níét mee dat je twee keer half hoorde.
  Duration _geluisterd = Duration.zero;
  Duration? _vorigePositie;
  bool _geteld = false;

  /// Een sprong groter dan dit is geen luisteren maar slepen.
  ///
  /// Ruim genomen, want de twee voedingen tikken heel verschillend: libmpv stuurt tien tot dertig
  /// keer per seconde, een speaker om de twee seconden. Vijf seconden vangt allebei en laat een
  /// echte sprong door de balk er niet doorheen.
  static const _maxStap = Duration(seconds: 5);

  /// Een tik luistertijd erbij, en melden zodra het genoeg is.
  void _telMee(Duration nu) {
    final vorig = _vorigePositie;
    _vorigePositie = nu;
    if (vorig == null || _geteld) return;
    final stap = nu - vorig;
    // Terug gesleept, of een gat: geen van beide is geluisterde tijd.
    if (stap <= Duration.zero || stap > _maxStap) return;
    _geluisterd += stap;
    if (!telMeeAlsGespeeld(geluisterd: _geluisterd, duur: duurErgens)) return;
    _geteld = true;
    final t = current;
    if (t != null) onPlayed?.call(t);
  }

  /// De teller op nul, bij elk nummer dat werkelijk nieuw is.
  void _nieuwVoorDeTelling(Track? t) {
    _geluisterd = Duration.zero;
    _vorigePositie = null;
    _geteld = false;
    if (t != null) _geopendDezeSessie.add(t.path);
  }

  /// Het hapert. Ingehangen vanuit main.dart, precies zoals [mediaResolver] en [onProgress].
  ///
  /// De speler leert hiermee niets over instellingen — hij meldt alleen dát het misging, en wat
  /// daar dan mee gebeurt (één sport lager voor deze sessie) staat in `netsoort.dart`. Twee
  /// aanroepers: de stilstandwacht, en een stroom die afbreekt voordat het nummer op is.
  void Function()? onHapering;

  /// Het volgende nummer alvast laten klaarzetten op de pc. Ingehangen vanuit main.dart, dat er een
  /// `HEAD` op doet: de server zet dan de hele omzetting klaar en stuurt alleen de kop terug.
  ///
  /// **Dit is de maatregel die het wachten tussen nummers wegneemt.** Staat er een plafond op de
  /// URL, dan moet de pc het bestand eerst helemaal omzetten voordat er één byte vertrekt — een paar
  /// seconden per nummer. Door dat bij het openen van nummer N alvast voor N+1 te vragen wacht je
  /// één keer, bij het aanzetten, en daarna nooit meer.
  void Function(String url)? onKlaarzetten;

  /// Staat er een plafond op de lijn, dan zet de pc eerst om en staat de teller even op 0:00.
  bool _omzetten = false;

  /// Wat er WERKELIJK over de lijn komt, of null als het bestand onveranderd verstuurd wordt.
  ///
  /// Voor het scherm. Zonder dit staat er op "Nu speelt" onveranderd wat het bestand is — "FLAC ·
  /// 24/96" — terwijl je pc onderweg 16/44.1 stuurt, en dan is er geen enkele manier om te zien dat
  /// de zuinige stand werkt. Zie `grensUitUrl`.
  ({int rate, int bits})? stroomGrens;

  Stilstandwacht _wacht = Stilstandwacht();

  /// De bron zoals libmpv hem krijgt, plus het geduld dat daarbij hoort.
  ///
  /// **Waarom het geduld hieraan hangt.** Een 24/192 van vijf minuten is zo'n 180 MB, en die moet
  /// helemaal omgezet zijn voor er één byte vertrekt. Op een kerngezonde pc duurt dat tien tot
  /// twintig seconden — en dat is precies het beeld waar de wacht na tien seconden "Er komt geen
  /// geluid" over zou roepen. Vandaar vijfentwintig zodra er een plafond in de URL staat.
  String _bron(String path) {
    final url = mediaResolver(path);
    stroomGrens = grensUitUrl(url);
    _omzetten = stroomGrens != null;
    _wacht = Stilstandwacht(
        geduld: Duration(seconds: _omzetten ? 25 : 10));
    return url;
  }

  /// The queue as it will actually play, shuffle applied.
  List<Track> get queueTracks => List.unmodifiable(_order);

  /// Waar we in [queueTracks] staan, of -1. Nodig zodra iemand die lijst tóónt: `current` zegt wél
  /// wat er klinkt maar niet wélke van twee gelijke regels het is.
  int get currentIndex => radioMode ? _radioIndex : _index;

  // Resume: persist the library queue + position so the app reopens where you left off.
  bool _resumable = false;
  bool _restoring = false; // block saves while restore() opens+seeks (position blips to 0)
  DateTime _lastPosSave = DateTime.fromMillisecondsSinceEpoch(0);
  bool resumedPaused = false; // true right after a startup restore (awaiting the user's play)

  String get _appDir => appDir;

  File get _queueFile => File('$_appDir${Platform.pathSeparator}resume_queue.json');
  File get _posFile => File('$_appDir${Platform.pathSeparator}resume_pos.json');

  @override
  Track? get current {
    if (radioMode) {
      if (_radioIndex >= 0 && _radioIndex < _radio.length) {
        final it = _radio[_radioIndex];
        return it.local ?? Track(path: it.url ?? '', title: it.title, artist: it.artist, album: '');
      }
      return null;
    }
    return (_index >= 0 && _index < _order.length) ? _order[_index] : null;
  }

  bool get hasNext => radioMode
      ? _radioIndex < _radio.length - 1
      : (_index < _order.length - 1 || (repeat == RepeatMode.all && _order.isNotEmpty));
  bool get hasPrev => radioMode ? _radioIndex > 0 : _index > 0;


  /// Wat er mis is met wat er nu zou moeten spelen, of null als er niets mis is.
  ///
  /// Voor de spelerbalk. Zie [Stilstandwacht] voor het geval dat dit veld bestaat.
  String? speelFout;

  Timer? _stilstandTikker;

  /// Welk kwart seconde er het laatst gemeld is. Zie de positiestroom hieronder.
  int _laatsteMeldvak = -1;

  void _meldStilstand(String? wat) {
    if (speelFout == wat) return;
    speelFout = wat;
    notifyListeners();
  }

  PlayerStore() {
    unawaited(_zetVooruitlezen());
    _player.stream.playing.listen((p) {
      playing = p;
      if (p) resumedPaused = false;
      if (!p) _saveProgress(force: true); // capture the spot on pause
      notifyListeners();
    });
    _player.stream.position.listen((p) {
      position = p;
      _saveProgress(); // throttled
      // Vóór de rem hieronder: die slaat drie van de vier tikken over, en dan zou een nummer pas na
      // het dubbele van de luistertijd meetellen.
      _telMee(p);
      // **De melding wél afgeremd, de waarde niet.**
      //
      // media_kit stuurt elke `time-pos`-wijziging van mpv door, ongethrottled — tien tot dertig
      // keer per seconde. Elke melding liet ÉLKE `context.watch<PlayerStore>()` hertekenen, en dat
      // zijn er veel: de spelerbalk, het wachtrijpaneel, het hele nu-speelt-scherm, en het
      // nummerscherm — dat bij elke hertekening ook nog eens zijn hele lijst van 770 nummers
      // opnieuw filtert. Zolang er muziek speelde gebeurde dat dus meerdere keren per seconde, voor
      // niets: op het scherm staat een seconde-teller en een balk.
      //
      // Vier keer per seconde is ruim genoeg om vloeiend te ogen. [position] zelf wordt nog steeds
      // bij elke tik bijgewerkt, zodat alles wat hem uitleest (het bewaren van je plek, de
      // stilstandwacht, het einde-of-breuk-oordeel) de exacte waarde ziet.
      final vak = p.inMilliseconds ~/ 250;
      if (vak == _laatsteMeldvak) return;
      _laatsteMeldvak = vak;
      notifyListeners();
    });
    // De foutstroom van media_kit. Die bestond al en werd door niemand beluisterd — dezelfde soort
    // stilte als `RemoteException.isUnauthorized`, dat een comment had die het probleem exact
    // beschreef en nergens werd aangeroepen.
    _player.stream.error.listen((e) {
      if (e.trim().isEmpty) return;
      // MET de reden erbij. Hier stond alleen de kale zin, en dat is precies het antwoord waar
      // niemand iets mee kan: mpv zégt waarom het niet lukte — een verbinding die geweigerd werd,
      // een adres dat niet te bereiken is, een antwoord dat te lang uitbleef — en die zin werd
      // weggegooid. Dezelfde fout als bij het taalmodel dat alleen "400" mocht zeggen.
      _log?.line('OPENEN MISLUKT — ${current?.title ?? "?"} — ${e.trim()}');
      _meldStilstand('Kan dit nummer niet openen — ${_kortereReden(e)}');
      _probeerNogEens();
    });
    // Twee seconden: vaak genoeg om binnen het geduld van de wacht te vallen, zeldzaam genoeg om
    // niets te kosten. Een timer en niet de positiestroom, want het geval dát dit moet vangen is nu
    // juist dat er geen positie meer binnenkomt.
    _stilstandTikker = Timer.periodic(const Duration(seconds: 2), (_) {
      final vast = _wacht.voeden(speelt: playing, positie: position, nu: DateTime.now());
      if (vast) {
        _meldStilstand('Er komt geen geluid — staat de pc aan?');
        onHapering?.call();
      } else if (playing && position > Duration.zero) {
        _meldStilstand(null);
      } else if (playing && _omzetten) {
        // Teller op 0:00 met een plafond op de lijn: de pc is aan het omzetten. Zeggen wat er
        // gebeurt is beter dan een lege balk waar iemand op gaat zitten drukken.
        _meldStilstand('Omzetten op de pc…');
      }
    });
    _player.stream.duration.listen((d) {
      duration = d;
      notifyListeners();
    });
    _player.stream.completed.listen((done) {
      if (done) _onCompleted();
    });
  }

  /// Hoe vaak deze stroom al afgebroken is. Nul bij elk nieuw nummer.
  int _hervatpogingen = 0;

  /// Voor welk nummer er al een tweede poging gedaan is. Hoogstens één per nummer.
  ///
  /// Op het PAD en niet op een vlag, en dat is geen smaak. De tweede poging van een radionummer
  /// loopt via [_openRadioCurrent] — dezelfde weg die ook een nieuw nummer opent — dus een vlag die
  /// daar teruggezet wordt, wordt door de poging zelf teruggezet. Dan probeert hij elke vier
  /// seconden opnieuw, voor altijd.
  String? _tweedePogingVoor;

  /// Nog één keer proberen te openen, na een tel of vier.
  ///
  /// **Waarom juist hier, en waarom precies één keer.** Een stroom die HALVERWEGE afbreekt werd al
  /// hervat (zie [_onCompleted]); een stroom die nooit OPENGING kreeg niets — die bleef als dood
  /// nummer op 0:00 staan tot je zelf iets aanraakte. En dat is het geval dat onderweg het vaakst
  /// voorkomt: je pc zet een hi-res bestand eerst helemaal om, stuurt in die tien tot twintig
  /// seconden nog geen byte, en een verbinding die dan afhaakt levert precies deze fout op.
  ///
  /// De tweede poging is bijna altijd raak, want de omgezette kopie staat dan in de cache van de pc
  /// en komt meteen. Vandaar één poging en geen lus: helpt hij niet, dan is er iets anders aan de
  /// hand en hoort de melding te blijven staan in plaats van eindeloos te knipperen.
  void _probeerNogEens() {
    if (position > Duration.zero) return;
    final t = current;
    if (t == null || t.path.isEmpty || _tweedePogingVoor == t.path) return;
    _tweedePogingVoor = t.path;
    _log?.line('nog één poging over vier tellen — ${t.title}');
    Timer(const Duration(seconds: 4), () {
      // Intussen doorgeklikt of gestopt? Dan hoort deze poging nergens meer bij.
      if (current?.path != t.path || position > Duration.zero) return;
      _meldStilstand('Nog een poging…');
      unawaited(radioMode ? _openRadioCurrent() : _hervatOpDezelfdePlek());
    });
  }

  /// De reden van mpv, kort genoeg voor één regel op het scherm.
  ///
  /// mpv schrijft er soms een pad of een hele URL bij, en die hoort niet op het speelscherm: hij
  /// draagt het toegangskoekje van je pc en hij duwt de eigenlijke reden van het scherm af.
  static String _kortereReden(String rauw) {
    var s = rauw.trim().replaceAll(RegExp(r'https?://\S+'), 'je pc');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    return s.length <= 70 ? s : '${s.substring(0, 69)}…';
  }

  /// Wat de speler onderweg besluit, in `speler.log` naast de andere staat.
  ///
  /// Een release-build slikt [debugPrint], dus zonder dit is de speler in een rijdende auto een
  /// zwarte doos: je hoort alleen dát hij springt, nooit waarom. Zie ook `warm.log`, dat om precies
  /// dezelfde reden bestaat.
  late final WarmLog? _log = () {
    try {
      return WarmLog('$logDir${Platform.pathSeparator}speler.log');
    } catch (_) {
      return null;
    }
  }();

  void _onCompleted() {
    switch (watNaHetEinde(
      positie: position,
      duur: duration,
      herhaal: repeat,
      mislukt: _hervatpogingen,
    )) {
      case NaHetEinde.stroomHervatten:
        _hervatpogingen++;
        _log?.line('AFGEBROKEN op $position van $duration — poging $_hervatpogingen'
            ' — ${current?.title ?? "?"}');
        // Een stroom die halverwege afbreekt is de duidelijkste hapering die er is.
        onHapering?.call();
        unawaited(_hervatOpDezelfdePlek());
      case NaHetEinde.ditNummerOpnieuw:
        _hervatpogingen = 0;
        radioMode ? _openRadioCurrent() : _openCurrent();
      case NaHetEinde.volgende:
        // Alleen melden als we het écht opgeven. Een nummer dat na één hik gewoon uitspeelt komt
        // hier ook langs, en dat is geen nieuws.
        if (_hervatpogingen >= _maxHervatpogingen) {
          _log?.line('OPGEGEVEN na $_hervatpogingen pogingen — door naar het volgende');
        }
        _hervatpogingen = 0;
        next();
    }
  }

  /// Hetzelfde nummer opnieuw openen en terugspringen naar waar het afbrak.
  ///
  /// Niet [_openCurrent], want die zet de teller terug naar nul en meldt het nummer opnieuw als
  /// "nu gestart" — dan zou een hik onderweg je plek in het nummer kosten én de geschiedenis
  /// vervuilen met een tweede keer hetzelfde liedje.
  Future<void> _hervatOpDezelfdePlek() async {
    // **De luisterteller wordt hier met opzet NIET teruggezet.** Dit is dezelfde opname die
    // doorloopt na een afgebroken stroom, geen nieuw nummer: opnieuw beginnen zou de tijd die je al
    // geluisterd hebt weggooien, en had het al genoeg geteld dan zou het dubbel meetellen. Het
    // terugspringen naar [plek] komt binnen als één sprong die groter is dan [_maxStap] en wordt
    // daar genegeerd in plaats van bijgeteld. "Doet niets" is hier de correctheid.
    final t = current;
    if (t == null) return;
    final plek = position;
    try {
      await _player.open(Media(_bron(t.path)), play: true);
      if (plek <= Duration.zero) return;

      // **Een seek vlak na open() wordt stil genegeerd** zolang libmpv het bestand nog niet geladen
      // heeft. Dat stond al uitgeschreven boven de lus in [restore] — en ik liep er recht in: de
      // eerste versie hiervan sprong terug naar nul, en in het logboek zag je alleen dat het nummer
      // niet oversloeg, niet dát je je plek kwijt was.
      //
      // Daar kan op `duration` gewacht worden omdat die bij een koude start nog nul is. Hier niet:
      // het is hetzelfde nummer, dus die waarde staat er al. Vandaar proberen tot de teller er
      // werkelijk staat, en het opschrijven als dat niet lukt. Een reparatie die zichzelf niet kan
      // controleren is de vorige fout nog een keer.
      // EERST wachten tot het bestand echt loopt, dan pas springen.
      //
      // De vorige versie begon meteen te seeken en probeerde het twintig keer. Het logboek van een
      // echte rit liet zien dat dat niet genoeg is:
      //
      //   HERVAT maar NIET teruggesprongen naar 0:03:47 — staat op 0:00:00
      //
      // Het nummer begon dus gewoon opnieuw. Zolang libmpv het bestand nog aan het openen is wordt
      // een seek stil weggegooid, en twee seconden proberen was te kort voor een stroom die net
      // afgebroken was en opnieuw moest verbinden. Een teller die loopt is het bewijs dat hij er
      // klaar voor is.
      for (var i = 0; i < 100 && position <= Duration.zero && duration <= Duration.zero; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      for (var poging = 0; poging < 60; poging++) {
        await _player.seek(plek);
        await Future.delayed(const Duration(milliseconds: 150));
        if ((position - plek).abs() < const Duration(seconds: 3)) return;
      }
      _log?.line('HERVAT maar NIET teruggesprongen naar $plek — staat op $position');
    } catch (e) {
      _log?.line('HERVATTEN MISLUKT: $e');
    }
  }

  /// Where a new queue goes when a speaker has the music. Set by main to the cast target; null on a
  /// device that is not casting, and then nothing here changes.
  ///
  /// Returning true means the speaker took it and this device stays silent. Without this, tapping a
  /// track while casting started it HERE: the phone began playing out loud while the KEF carried on
  /// with the queue it had been given. Every entry point goes through [playQueue], so this is the
  /// one seam that covers a track row, an album's play button and the shuffle-everything button
  /// alike.
  /// Geeft terug WELKE nummers de speaker gekregen heeft, in die volgorde -- of null als hij niets nam.
  ///
  /// Niet zomaar true/false, en dat is de reparatie. De overdracht filtert de lijst op wat de pc kan
  /// serveren, en elk nummer dat wegvalt schoof alles erachter op terwijl de index in de OUDE lijst
  /// bleef wijzen. Bij shuffle-all over een hele bibliotheek is dat gegarandeerd mis: de app toonde een
  /// ander album dan er klonk. Door de aangenomen lijst terug te geven lopen beide kanten per definitie
  /// gelijk, in plaats van dat er twee keer hetzelfde gerekend moet worden.
  Future<List<Track>?> Function(List<Track> tracks, int index)? castQueue;

  Future<void> playQueue(List<Track> tracks, int index, {Uint8List? cover}) async {
    if (await _handedToSpeaker(tracks, index, cover)) return;
    _verlaatRadio();
    _resumable = true;
    resumedPaused = false;
    currentCover = cover;
    _original = List.of(tracks);
    _rebuildOrder(start: (index >= 0 && index < _original.length) ? _original[index] : null);
    await _openCurrent();
    _saveQueue();
  }

  /// Hand a queue to the speaker, and keep it here WITHOUT opening it.
  ///
  /// The queue and the cover still live locally, because every screen reads the title, the artist
  /// and the sleeve from here — the difference is only that libmpv is never asked to play it.
  Future<bool> _handedToSpeaker(List<Track> tracks, int index, Uint8List? cover) async {
    final hand = castQueue;
    if (hand == null || tracks.isEmpty) return false;
    final aangenomen = await hand(tracks, index);
    if (aangenomen == null || aangenomen.isEmpty) return false;
    // Whatever was coming out of this device stops: the point is that it plays THERE.
    if (playing) await _player.pause();
    _verlaatRadio();
    _resumable = true;
    resumedPaused = false;
    currentCover = cover;
    // De lijst die de SPEAKER heeft, niet de lijst die gevraagd was. Zo betekent "nummer 5" aan beide
    // kanten hetzelfde, en hoeft niemand een index om te rekenen.
    _original = List.of(aangenomen);
    // De volgorde staat al vast: hij is hier geschud en zo doorgegeven. Opnieuw ordenen zou hem
    // herschudden en daarmee weer laten afwijken van wat er speelt.
    _order = List.of(aangenomen);
    _index = _order.isEmpty ? -1 : 0;
    playing = false;
    position = Duration.zero;
    notifyListeners();
    _saveQueue();
    return true;
  }

  /// Geef de wachtrij die hier staat door aan de speaker die zojuist gekozen is.
  ///
  /// Eén weg naar buiten, en dat is het punt: de speakerkiezer bouwde zijn eigen overdracht en nam
  /// daardoor de aangenomen lijst niet over. Alles wat [_handedToSpeaker] regelt -- filteren, de lijst
  /// van de SPEAKER aannemen, hier stil worden -- gold daar niet.
  ///
  /// False als er niets te sturen viel of de speaker het weigerde; de aanroeper zet de keuze dan terug.
  Future<bool> handOverToSpeaker() =>
      _handedToSpeaker(_order, _index < 0 ? 0 : _index, currentCover);

  /// De speaker zegt bij welk nummer hij is; volg dat.
  ///
  /// Zonder dit staat de app stil op het nummer dat bij de overdracht is doorgegeven terwijl de speaker
  /// verder loopt -- de balk, de hoes en het album op het scherm horen dan bij iets wat niet klinkt.
  /// Alleen de index verschuift: er wordt hier niets geopend of gespeeld, want het geluid komt daar
  /// vandaan.
  /// De speaker heeft iets nieuws gemeld -- desnoods alleen dat hij nog steeds speelt.
  ///
  /// Zonder dit ververst de mediasessie alleen als libmpv iets doet, en die staat tijdens het casten
  /// stil. De melding en het vergrendelscherm bleven dan hangen op de stand van de overdracht: pauze
  /// je op de Sonos, dan bleef de knop een pauzeknop.
  ///
  /// **Ook de enige voeding van de luisterteller tijdens het casten**, want
  /// libmpv staat dan stil en [position] blijft op nul. Tot 28-08-2026 telde een nummer dat je naar
  /// de Sonos stuurde daardoor helemaal niet mee.
  void speakerMeldde() {
    final p = _bijSpeaker?.position;
    if (p != null) _telMee(p);
    notifyListeners();
  }

  void followSpeaker(int index) {
    if (index < 0 || index >= _order.length || index == _index) return;
    _index = index;
    position = Duration.zero;
    _nieuwVoorDeTelling(current);
    // Een ANDER nummer, dus niet via refreshCover: die houdt bij een leeg antwoord vast wat er
    // staat, en dat is hier de hoes van het album waarmee de overdracht begon. Op de Mac naar de
    // Sonos stond zo Whitney Houston boven een nummer van Michael Jackson, hele wachtrij lang.
    _zetHoes(zelfdeNummer: false);
    notifyListeners();
  }

  /// Shuffle the whole library (or any list): every track plays exactly once (repeat
  /// off), starting from a random one. Scales to tens of thousands of tracks.
  Future<void> shuffleAll(List<Track> tracks) async {
    // Shuffled HERE and then handed over in that order: the speaker is given one track at a time,
    // so it has no notion of shuffling a queue itself.
    //
    // **Eén trekking, en die loopt door [ordenVoor].** Hier stond een eigen `..shuffle()` — en een
    // tweede, verderop, die de lijst nóg eens schudde. Twee shuffle-wegen naast elkaar is precies
    // hoe er één achterblijft zonder weging: de knop "Shuffle alles" ging langs de ene, het
    // shuffle-icoontje langs de andere.
    final shuffled = ordenVoor(tracks, null, shuffle: true, gewicht: _gewichtVanNummer).order;
    if (await _handedToSpeaker(shuffled, 0, null)) {
      shuffle = true;
      notifyListeners();
      return;
    }
    _verlaatRadio();
    _resumable = true;
    resumedPaused = false;
    shuffle = true;
    currentCover = null;
    _original = List.of(tracks);
    // Dezelfde lijst die de speaker hierboven zou hebben gekregen; niet nog een keer schudden.
    _order = shuffled;
    _index = _order.isEmpty ? -1 : 0;
    await _openCurrent();
    _saveQueue();
  }

  /// Play a remote URL (e.g. a resolved TorBox stream) as a one-item queue.
  Future<void> playUrl(String url, {required String title, required String artist}) async {
    _verlaatRadio();
    _resumable = false;
    currentCover = null;
    _original = [Track(path: url, title: title, artist: artist, album: '')];
    _order = List.of(_original);
    _index = 0;
    await _openCurrent();
  }

  /// Start a Radio / Smart-Shuffle queue of mixed local + online items.
  ///
  /// Een lopende radio wordt eerst netjes verlaten. Anders schuift de tweede radio over de eerste
  /// heen zonder dat er iemand van weet, en blijft alles wat die eerste opgehaald had zwerven.
  Future<void> playRadio(List<RadioItem> items, {int start = 0}) async {
    _verlaatRadio();
    radioMode = true;
    _resumable = false;
    _radioSession++; // invalidate any in-flight extend from a previous radio
    _extending = false;
    currentCover = null;
    _radio = items;
    _radioIndex = items.isEmpty ? -1 : start.clamp(0, items.length - 1);
    await _openRadioCurrent();
  }

  /// Naar een ander nummer in de LOPENDE radio, zonder de radio te verlaten.
  ///
  /// Zonder dit deed een tik op een radioregel `playQueue` — en die verlaat de radio. Je klikte op
  /// het derde nummer van je radio en had er geen radio meer, alleen dat ene nummer.
  Future<void> springInRadio(int plek) async {
    if (!radioMode || plek < 0 || plek >= _radio.length) return;
    _radioIndex = plek;
    await _openRadioCurrent();
  }

  /// De radio verlaten. De enige weg naar `radioMode = false`.
  ///
  /// Het sessienummer gaat omhoog zodat een aanvulling die nog onderweg is niet alsnog in een lijst
  /// valt die niemand meer speelt. Wat er gespeeld is blijft staan: [bijRadioEinde] moet erover
  /// kunnen vertellen, en dat kan niet als het hier al weggegooid is.
  void _verlaatRadio() {
    if (!radioMode) return;
    radioMode = false;
    radioStatus = '';
    _radioSession++;
    _extending = false;
    bijRadioEinde?.call(List.of(_radio));
  }

  /// Resolve an item's URL, sharing a single in-flight call between the foreground
  /// open and the background prefetch so they never race a second resolver.
  Future<String?> _resolveItem(RadioItem it) {
    if (it.url != null) return Future.value(it.url);
    if (it.failed) return Future.value(null);
    return it.pending ??= () async {
      final url = await resolver?.call(it.artist, it.title);
      if (url != null) {
        it.url = url;
      } else {
        it.failed = true;
      }
      it.pending = null;
      return it.url;
    }();
  }

  Future<void> _openRadioCurrent() async {
    final gen = ++_radioGen; // any earlier in-flight open is now stale
    while (_radioIndex >= 0 && _radioIndex < _radio.length) {
      final it = _radio[_radioIndex];
      if (it.url == null && !it.failed && !it.isLocal) {
        radioStatus = 'Bron zoeken: ${it.artist} — ${it.title}…';
        notifyListeners();
        await _resolveItem(it);
        if (gen != _radioGen) return; // superseded by a newer next()/prev()
      }
      final path = it.isLocal ? it.local!.path : it.url;
      if (path != null) {
        radioStatus = '';
        _radioDroog = false;
        currentCover = it.isLocal ? coverResolver?.call(it.local!) : null;
        notifyListeners();
        _nieuwVoorDeTelling(it.local);
        await _player.open(Media(_bron(path)), play: true);
        if (gen != _radioGen) return; // superseded while opening
        _prefetchNext();
        _maybeExtend();
        return;
      }
      if (_radioIndex >= _radio.length - 1) break; // don't overrun the end
      _radioIndex++; // couldn't source this one — skip forward
    }
    _radioIndex = _radio.isEmpty ? -1 : _radioIndex.clamp(0, _radio.length - 1);
    radioStatus = 'Radio klaar';
    _radioDroog = true;
    notifyListeners();
    _maybeExtend();
  }

  /// De radio staat droog: hij is door zijn rij heen en wacht op wat er nog komt.
  ///
  /// Zonder dit was "de rij is op" niet te onderscheiden van "er speelt gewoon niets", en dan zou een
  /// nummer dat vijf seconden later alsnog binnenkomt stil achteraan blijven liggen.
  bool _radioDroog = false;

  /// Nummers achter de radiorij plakken zonder hem te onderbreken.
  ///
  /// **Waarom een radio dit nodig heeft.** De rij van een radio is niet vooraf bekend: hij groeit
  /// terwijl je luistert, telkens als er weer een bestand geland is. Er was hier maar één weg naar
  /// binnen — [radioExtend], en die vuurt pas als je bijna aan het eind bent. Voor een radio die
  /// vooruit meeloopt is dat te laat en te weinig.
  ///
  /// Stond de radio dróóg, dan begint hij hier meteen weer. Dat is het geval waarin je nog niets van
  /// de eerste nummers had: dan is de rij bij de start leeg, en zonder deze regel blijft hij dat.
  void voegToeAanRadio(List<RadioItem> meer) {
    if (!radioMode || meer.isEmpty) return;
    final was = _radio.length;
    _radio.addAll(meer);
    if (_radioDroog) {
      _radioDroog = false;
      _radioIndex = was;
      unawaited(_openRadioCurrent());
      return; // die roept zelf notifyListeners aan
    }
    notifyListeners();
  }

  /// Eén nummer uit de LOPENDE radiorij halen. True als er werkelijk iets weg is.
  ///
  /// **Waarom dit er is.** Een duim omlaag wist het bestand meteen — zo is het gevraagd. Bleef het
  /// nummer daarna in de rij staan, dan kwam de radio er even later alsnog bij, vond niets, en stond
  /// je met een stilte waar je nooit om gevraagd hebt. Weg is weg, ook hier.
  ///
  /// **Eerst doorspoelen, dan pas terugmelden.** Speelt het nummer dat weg moet op ditzelfde moment,
  /// dan gaat de radio eerst een nummer verder. libmpv houdt een bestand open zolang het klinkt, en
  /// op Windows laat een geopend bestand zich niet wissen — zonder deze volgorde zou de duim omlaag
  /// er precies bij het nummer dat je hoorde niets doen. Is er niets om naar door te gaan, dan valt
  /// de radio stil tot er weer iets landt; [voegToeAanRadio] pakt hem daar weer op.
  Future<bool> haalUitRadio(String pad) async {
    if (!radioMode) return false;
    bool ditIsHem(RadioItem it) => it.isLocal && it.local!.path == pad;
    if (!_radio.any(ditIsHem)) return false;

    if (_radioIndex >= 0 && _radioIndex < _radio.length && ditIsHem(_radio[_radioIndex])) {
      if (_radioIndex < _radio.length - 1) {
        await next();
      } else {
        if (playing) await _player.pause();
        _radioDroog = true;
      }
      // Een tel om libmpv het bestand te laten loslaten. Zonder dat is het wissen een race die je
      // een op de vijf keer verliest, en dan blijft er een nummer op je schijf staan dat je hebt
      // weggegooid.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    // Het nummer waar de radio NU op staat, als voorwerp: na het weghalen schuiven de indexen op, en
    // een index die je vasthoudt wijst dan naar de buurman.
    final hier = _radioIndex >= 0 && _radioIndex < _radio.length ? _radio[_radioIndex] : null;
    _radio.removeWhere(ditIsHem);
    final terug = hier == null ? -1 : _radio.indexOf(hier);
    _radioIndex = terug >= 0 ? terug : _radio.length - 1;
    notifyListeners();
    return true;
  }

  /// Warm the next couple of online items so skipping ahead is snappy (shares the call).
  void _prefetchNext() {
    for (var i = 1; i <= 2; i++) {
      final ni = _radioIndex + i;
      if (ni >= _radio.length) break;
      final it = _radio[ni];
      if (!it.isLocal && it.url == null && !it.failed) _resolveItem(it);
    }
  }

  /// Keep the radio endless: near the tail, fetch and append more recommendations.
  void _maybeExtend() {
    if (radioExtend == null || _extending || _radioIndex < _radio.length - 3) return;
    _extending = true;
    final session = _radioSession; // tie this extend to the current radio
    radioExtend!().then((more) {
      if (session != _radioSession) return; // a newer radio started; drop this batch
      if (radioMode && more.isNotEmpty) _radio.addAll(more);
      _extending = false;
      notifyListeners();
    }).catchError((_) {
      if (session == _radioSession) _extending = false;
    });
  }

  /// [behoudGespeeld] laat staan wat al geklonken heeft.
  ///
  /// **Dit is de reparatie van "hij speelt telkens hetzelfde".** Zonder dit bouwde één tik op het
  /// shuffle-icoontje een compleet nieuwe volgorde van ALLES met [_index] terug op nul — alles wat
  /// je net gehoord had stond weer voor je, en bij vijfduizend nummers is dat het verschil tussen
  /// een doorloop en een vijver waarin je rondjes zwemt. Android Auto loopt langs diezelfde knop
  /// (`now_playing.dart`), dus in de auto was het één druk.
  ///
  /// Een NIEUWE wachtrij heeft geen verleden; daar blijft dit uit.
  void _rebuildOrder({Track? start, bool behoudGespeeld = false}) {
    final prefix =
        (behoudGespeeld && _index > 0) ? _order.sublist(0, _index) : const <Track>[];
    final uit = ordenVoor(_original, start ?? current,
        shuffle: shuffle, reedsGespeeld: prefix, gewicht: _gewichtVanNummer);
    _order = uit.order;
    _index = uit.index;
  }

  /// Hoe zwaar een nummer weegt in de trekking, of null als er niets te wegen valt.
  ///
  /// Null wordt doorgegeven als "gelijk gewicht", en dat is wat een verse installatie, een toestel
  /// zonder gedeelde staat en elke toets krijgt: dan is het gewoon de shuffle die er altijd was.
  double Function(Track)? get _gewichtVanNummer {
    final lees = speelstandVan;
    final duim = oordeelWeging;
    if (lees == null && duim == null) return null;
    final nu = DateTime.now().millisecondsSinceEpoch;
    return (t) {
      var basis = lees == null ? 1.0 : gewichtVan(lees(t), nuMs: nu);
      if (duim != null) basis *= duim(t);
      // **Wat deze sessie al geopend werd, weegt lichter — ook als het niet als beluisterd telde.**
      // "Precies één keer" geldt per trekking. Druk je halverwege nog eens op shuffle, dan is dat
      // een nieuwe trekking, en een nummer dat je na twintig seconden wegklikte draagt geen straf
      // omdat het de helft niet haalde. Zonder deze regel hoor je bij twee keer drukken dezelfde
      // handvol nummers. In het geheugen, dus bij een herstart is het weer schoon.
      return _geopendDezeSessie.contains(t.path) ? basis * .3 : basis;
    };
  }

  /// Ask again what the playing track's cover is.
  ///
  /// [currentCover] is otherwise a snapshot taken when a track opens, so correcting a sleeve while
  /// it plays left this holding the old bytes — and they are what the mini bar, the backdrop and
  /// the tap-to-zoom all read. The album page showed the new sleeve, the zoom showed the old one,
  /// on the same screen.
  ///
  /// Dezelfde plaat, opnieuw opgezocht: een leeg antwoord telt niet mee. Zie [hoesOpScherm].
  void refreshCover() => _zetHoes(zelfdeNummer: true);

  void _zetHoes({required bool zelfdeNummer}) {
    final t = current;
    if (t == null || coverResolver == null) return;
    final nieuw = hoesOpScherm(currentCover, coverResolver!(t), zelfdeNummer: zelfdeNummer);
    if (identical(nieuw, currentCover)) return;
    currentCover = nieuw;
    notifyListeners();
  }

  /// Ask again what the queued tracks are CALLED.
  ///
  /// The same bug as [refreshCover], one layer up and never fixed. The queue holds `Track` values
  /// taken when it was built; `Track` is immutable and a correction builds new ones, so the player
  /// keeps pointing at the old objects for as long as the queue lives. Correct an artist while it
  /// plays and every list in the app updates except the three places you are actually looking at —
  /// the player bar, the now-playing screen and the lockscreen — where the old name simply stays.
  ///
  /// Remapping both lists element-wise keeps the shuffle permutation and [_index] exactly as they
  /// were: the two hold the same instances in different orders, so replacing values in place moves
  /// nothing. Nothing reopens, so the music does not skip.
  void refreshTracks() {
    // Radio items carry their own artist/title from the recommender, not from the library, and the
    // local ones are held in a final field. Nothing here to refresh, and nothing stale either.
    if (radioMode || _original.isEmpty) return;
    final resolve = trackResolver;
    if (resolve == null) return;

    // The guard that makes this affordable. The library notifies once per cached cover during
    // startup enrichment — hundreds of times — and a shuffled queue can be the entire library, so
    // walking it on every notification would be millions of lookups for nothing. An integer says
    // "no track's text has changed since you last asked" in one comparison.
    final rev = metaRevOf?.call() ?? 0;
    if (rev == _seenMetaRev) return;
    _seenMetaRev = rev;
    remapCount++;

    final next = remapQueue(_original, _order, resolve);
    if (next == null) return;
    _original = next.original;
    _order = next.order;
    notifyListeners();
  }

  Future<void> _openCurrent() async {
    final t = current;
    if (t == null) return;
    // Een nieuw nummer verdient zijn eigen geduld: de klacht van het vorige zegt niets over dit.
    _wacht.reset();
    _meldStilstand(null);
    _hervatpogingen = 0;
    // Een nummer dat je opnieuw aanzet verdient opnieuw een tweede kans. Alleen hier, want dit is
    // de weg voor een NIEUW nummer — de tweede poging zelf loopt langs [_hervatOpDezelfdePlek].
    _tweedePogingVoor = null;
    if (coverResolver != null) currentCover = coverResolver!(t);
    _nieuwVoorDeTelling(t);
    await _player.open(Media(_bron(t.path)), play: true);
    _saveProgress(force: true); // track changed → persist the new spot
    _zetVolgendeKlaar();
    notifyListeners();
  }

  /// Het volgende nummer in de rij vast laten klaarzetten. Zie [onKlaarzetten].
  ///
  /// Alleen als er echt iets klaar te zetten valt: zonder plafond op de lijn serveert de pc gewoon
  /// het origineel, en dan is een `HEAD` vooruit verkeer voor niets. Buiten de wachtrij (radio) ook
  /// niet — daar staat het volgende nummer nog niet vast.
  void _zetVolgendeKlaar() {
    if (onKlaarzetten == null || radioMode) return;
    final volgende = _index + 1;
    if (volgende < 0 || volgende >= _order.length) return;
    final url = mediaResolver(_order[volgende].path);
    if (grensUitUrl(url) == null) return;
    onKlaarzetten!(url);
  }

  /// De schakelaar van DIT toestel, met opzet niet omgeleid naar de speaker.
  ///
  /// Zijn andere aanroepers gaan namelijk over de audio hier: een telefoongesprek dat erdoorheen
  /// komt, een koptelefoon die eruit wordt getrokken, een zender die stopt met casten naar deze tv.
  /// Zou dit meelopen met de speaker, dan pauzeerde een melding op de Shield de muziek in een andere
  /// kamer. Wat de gebruiker zelf indrukt gaat via [speelAf] en [pauzeer].
  @override
  void playPause() => _player.playOrPause();

  /// Wat er klinkt, en waar het staat -- niet wat libmpv doet.
  ///
  /// Tijdens het casten staat libmpv hier stil, en dat is precies wat er aan het systeem gemeld
  /// werd. Android geloofde dus dat de app gepauzeerd was terwijl de Sonos speelde: de melding
  /// toonde een play-knop bij een lopend nummer, de positie bevroor, en de play/pauzetoets van de
  /// afstandsbediening loste daardoor altijd op naar "afspelen" -- wat al speelde. Eén druk deed
  /// dus niets, en pauzeren op afstand bestond niet.
  @override
  bool get speeltErgens => _bijSpeaker?.isPlaying ?? playing;
  @override
  Duration get positieErgens => _bijSpeaker?.position ?? position;
  @override
  Duration get duurErgens => _bijSpeaker?.duration ?? duration;

  /// "Speel af" en "pauzeer" als OPDRACHT, op de plek waar de muziek is.
  ///
  /// Het vergrendelscherm, de mediatoetsen en Android Auto sturen play óf pause -- geen schakelaar.
  /// Een schakelaar heeft een stand nodig, en tijdens het casten staat de stand hier op stil terwijl
  /// er in de kamer muziek speelt. Zo werd "afspelen" op de afstandsbediening een pauze op de Sonos.
  @override
  void speelAf() {
    final s = _bijSpeaker;
    if (s != null) {
      if (!s.isPlaying) unawaited(s.playPause());
      return;
    }
    if (!playing) _player.playOrPause();
  }

  @override
  void pauzeer() {
    final s = _bijSpeaker;
    if (s != null) {
      if (s.isPlaying) unawaited(s.playPause());
      return;
    }
    if (playing) _player.playOrPause();
  }

  @override
  Future<void> next() async {
    final s = _bijSpeaker;
    if (s != null) return s.next();
    if (radioMode) {
      if (_radioIndex < _radio.length - 1) {
        _radioIndex++;
        await _openRadioCurrent();
      }
      return;
    }
    if (_index < _order.length - 1) {
      _index++;
      await _openCurrent();
    } else if (repeat == RepeatMode.all && _order.isNotEmpty) {
      // **Ronde twee is een nieuwe trekking, niet dezelfde volgorde nog eens.** Bij vijfduizend
      // nummers duurt een doorloop dagen, en wie hem uitzit hoort daarna liever niet exact dezelfde
      // reeks. Alleen bij shuffle: staat die uit, dan is de volgorde van de plaat de bedoeling.
      // Zonder anker: elk nummer mag ronde twee openen. `_rebuildOrder` zou hier `current` als
      // anker nemen — het laatste nummer van ronde één — en dat vooraan vastzetten.
      if (shuffle) {
        _order = ordenVoor(_original, null, shuffle: true, gewicht: _gewichtVanNummer).order;
      }
      _index = 0;
      await _openCurrent();
    }
  }

  @override
  Future<void> prev() async {
    // Vóór de drie-secondenregel: die leest `position` van libmpv, en die staat tijdens het casten
    // stil op nul. De speaker krijgt gewoon te horen dat hij een nummer terug moet.
    final s = _bijSpeaker;
    if (s != null) return s.previous();
    if (position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    if (radioMode) {
      // Step back to the previous item that's playable or still resolvable
      // (skip ones already known to have failed to source).
      var i = _radioIndex - 1;
      while (i >= 0 && _radio[i].failed && !_radio[i].isLocal && _radio[i].url == null) {
        i--;
      }
      if (i >= 0) {
        _radioIndex = i;
        await _openRadioCurrent();
      }
      return;
    }
    if (_index > 0) {
      _index--;
      await _openCurrent();
    }
  }

  @override
  void seek(Duration d) {
    final s = _bijSpeaker;
    if (s != null) return unawaited(s.seekTo(d));
    _player.seek(d);
  }

  /// Het volume dat de gebruiker heeft ingesteld, los van wat er nu klinkt.
  ///
  /// Twee getallen omdat er twee dingen zijn: wat jij gekozen hebt, en wat er op dit moment uit de
  /// speakers komt. Zonder dat onderscheid komt een navigatiestem die halverwege afgebroken wordt
  /// nooit meer terug op je eigen stand — of erger, hij bewaart de gedempte stand als de jouwe.
  double _volume = 100;
  bool _gedempt = false;

  void setVolume(double v) {
    _volume = v;
    if (!_gedempt) _player.setVolume(v);
  }

  /// Een kwart van de ingestelde stand. Zacht genoeg om overheen te praten, hard genoeg om te horen
  /// dat de muziek niet gestopt is.
  @override
  void zetDemping(bool aan) {
    if (_gedempt == aan) return;
    _gedempt = aan;
    _player.setVolume(aan ? _volume * 0.25 : _volume);
  }

  /// De speaker dezelfde nieuwe volgorde geven, zonder het lopende nummer opnieuw te beginnen.
  ///
  /// Wordt ALTIJD aangeroepen bij het herschikken, ook als er niets gecast wordt. Dat is met opzet: de
  /// vorige versie vroeg eerst aan een vlag in deze klasse of de wachtrij bij een speaker stond, en die
  /// vlag stond uit omdat de speakerkiezer buiten [_handedToSpeaker] om ging. De reparatie kwam daardoor
  /// nooit aan de beurt en niets verried dat -- er is geen foutpad, er gebeurt alleen niets.
  ///
  /// Wie de speakers bedient wéét of er een speaker gekozen is; die kant beslist. Eén waarheid in plaats
  /// van een kopie die kan verlopen, en als bijvangst komt elke druk op shuffle in cast.log terecht.
  Future<void> Function(List<Track> volgorde, int index)? castReorder;

  void toggleShuffle() {
    shuffle = !shuffle;
    if (_original.isEmpty) {
      notifyListeners();
      return;
    }
    _rebuildOrder(behoudGespeeld: true);
    // Heeft een speaker de wachtrij, dan moet DIE dezelfde volgorde krijgen.
    //
    // Zonder deze regel schudde de app haar eigen lijst en liet die van de speaker staan. De index die
    // de speaker daarna elke twee seconden terugmeldt wees vanaf dat moment in twee verschillende
    // lijsten: het scherm toonde een ander album dan er klonk, zonder dat er iets haperde. Precies wat
    // [_handedToSpeaker] voor de overdracht al voorkomt -- alleen kon shuffle het daarna weer stukmaken.
    //
    // [_rebuildOrder] zet het spelende nummer vooraan, dus de speaker hoeft niets opnieuw te openen.
    unawaited(castReorder?.call(_order, _index) ?? Future<void>.value());
    notifyListeners();
  }

  void cycleRepeat() {
    repeat = RepeatMode.values[(repeat.index + 1) % RepeatMode.values.length];
    notifyListeners();
  }

  /// Shuffle op een stand zetten. Via [toggleShuffle], want daar zit de speaker-afhandeling in.
  @override
  void zetShuffle(bool aan) {
    if (shuffle != aan) toggleShuffle();
  }

  @override
  void zetHerhaal(RepeatMode m) {
    if (repeat == m) return;
    repeat = m;
    notifyListeners();
  }

  // ── De wachtrij bijwerken ──────────────────────────────────────────────────
  //
  // Tot nu toe kon deze app precies één ding met een wachtrij: hem vervangen. Elke klik in de hele
  // app roept [playQueue] aan.
  //
  // DE VAL, en die is stil. Er zijn TWEE lijsten: [_original] is de verzameling zoals aangeleverd,
  // [_order] is hoe hij echt speelt. [toggleShuffle] bouwt `_order` opnieuw op uit `_original`
  // (zie [_rebuildOrder]). Wat alleen in `_order` wordt gezet, verdwijnt dus zodra iemand shuffle
  // aantikt — zonder foutmelding, zonder crash, gewoon weg. Daarom raakt elke methode hieronder
  // beide lijsten, behalve waar het uitdrukkelijk anders hoort.
  //
  // Radio blijft ongemoeid: dat is een oneindige stroom die zichzelf aanvult ([_maybeExtend]), geen
  // lijst die je samenstelt. Iets invoegen tussen items die nog gegenereerd moeten worden betekent
  // niets.

  /// Wat er na elke wijziging moet gebeuren — dezelfde drie dingen als bij [toggleShuffle].
  ///
  /// De speaker hoort erbij: heeft een KEF of Sonos de wachtrij, dan moet DIE dezelfde volgorde
  /// krijgen, anders wijst de index die hij elke twee seconden terugmeldt in een andere lijst dan
  /// die op het scherm. [CastManager.requeue] heropent het lopende nummer niet, dus de muziek slaat
  /// nergens over.
  void _naWijziging() {
    unawaited(_saveQueue());
    unawaited(castReorder?.call(_order, _index) ?? Future<void>.value());
    notifyListeners();
  }

  /// Zet [nieuw] direct achter het nummer dat nu klinkt.
  void speelHierna(List<Track> nieuw) => _voegIn(nieuw, hierna: true);

  /// Hang [nieuw] achteraan de wachtrij.
  void zetAchteraan(List<Track> nieuw) => _voegIn(nieuw, hierna: false);

  void _voegIn(List<Track> nieuw, {required bool hierna}) {
    if (nieuw.isEmpty || radioMode) return;
    // Niets om achter te zetten: dan is dit gewoon "speel dit". Anders zou de eerste klik op
    // "toevoegen aan de wachtrij" bij een stille app niets hoorbaars doen.
    if (_order.isEmpty) {
      playQueue(nieuw, 0);
      return;
    }
    _pas(voegInWachtrij(_nu, nieuw, hierna: hierna));
  }

  /// Haal het nummer op [plek] in de speelvolgorde uit de wachtrij. Raakt geen bestand aan.
  bool haalUitWachtrij(int plek) {
    if (radioMode) return false;
    final uit = haalUitWachtrijLijst(_nu, plek);
    if (identical(uit.volgorde, _order)) return false; // niets veranderd
    _pas(uit);
    return true;
  }

  /// Versleep het nummer van [van] naar [naar] in de speelvolgorde.
  bool verplaatsInWachtrij(int van, int naar) {
    if (radioMode) return false;
    final uit = verplaatsInWachtrijLijst(_nu, van, naar, shuffle: shuffle);
    if (identical(uit.volgorde, _order)) return false;
    _pas(uit);
    return true;
  }

  Wachtrij get _nu => (origineel: _original, volgorde: _order, index: _index);

  void _pas(Wachtrij w) {
    _original = w.origineel;
    _order = w.volgorde;
    _index = w.index;
    _naWijziging();
  }

  // ── Resume (persist the library queue + position) ──────────────────────────
  Future<void> _saveQueue() async {
    if (!_resumable) return;
    try {
      await Directory(_appDir).create(recursive: true);
      await _queueFile.writeAsString(jsonEncode({
        'order': _order.map((t) => t.path).toList(),
        'shuffle': shuffle,
        'repeat': repeat.index,
      }));
    } catch (_) {}
  }

  Future<void> _saveProgress({bool force = false}) async {
    if (!_resumable || _restoring) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastPosSave).inSeconds < 5) return; // throttle
    _lastPosSave = now;
    final t = current;
    if (t == null) return;
    onProgress?.call(t, position, playing, _order, _index);
    try {
      await Directory(_appDir).create(recursive: true);
      await _posFile.writeAsString(jsonEncode({
        'index': _index,
        'positionMs': position.inMilliseconds,
        'path': t.path,
      }));
    } catch (_) {}
  }

  /// On startup, reopen the last library queue at the saved song + position — PAUSED,
  /// so nothing blasts out; the player bar shows it and the user presses play to resume.
  Future<void> restore(Track? Function(String path) resolveTrack) async {
    _restoring = true;
    try {
      if (!await _queueFile.exists()) return;
      final q = jsonDecode(await _queueFile.readAsString()) as Map<String, dynamic>;
      final paths = ((q['order'] as List?) ?? const []).cast<String>();
      final tracks = paths.map(resolveTrack).whereType<Track>().toList();
      if (tracks.isEmpty) return;
      shuffle = q['shuffle'] == true;
      repeat = RepeatMode.values[((q['repeat'] as int?) ?? 0).clamp(0, RepeatMode.values.length - 1)];
      _original = List.of(tracks);
      _order = tracks;

      var idx = 0, posMs = 0;
      if (await _posFile.exists()) {
        final p = jsonDecode(await _posFile.readAsString()) as Map<String, dynamic>;
        final byPath = _order.indexWhere((t) => t.path == (p['path'] as String? ?? ''));
        idx = byPath >= 0 ? byPath : ((p['index'] as int?) ?? 0);
        posMs = (p['positionMs'] as int?) ?? 0;
      }
      _index = idx.clamp(0, _order.length - 1);
      _resumable = true;
      _verlaatRadio();
      final t = current;
      if (t == null) return;
      currentCover = coverResolver?.call(t);
      _nieuwVoorDeTelling(t);
      await _player.open(Media(_bron(t.path)), play: false); // reopen PAUSED
      if (posMs > 0) {
        // The seek only sticks once libmpv has loaded the file (duration known);
        // seeking too early is silently dropped → playback would restart at 0.
        for (var i = 0; i < 40 && duration <= Duration.zero; i++) {
          await Future.delayed(const Duration(milliseconds: 75));
        }
        await _player.seek(Duration(milliseconds: posMs));
        position = Duration(milliseconds: posMs);
      }
      resumedPaused = true;
      notifyListeners();
    } catch (_) {
    } finally {
      _restoring = false;
    }
  }

  @override
  void dispose() {
    _stilstandTikker?.cancel();
    _player.dispose();
    super.dispose();
  }
}

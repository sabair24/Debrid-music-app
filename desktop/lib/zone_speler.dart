/// Een zone op afstand als speler, en welke zone er gekozen is ("Speelt op: … ▾").
///
/// **Wat Saber koos (21-10-2026).** Kies je op je gsm de pc als zone, dan tonen de spelerbalk en Nu speelt
/// wat de pc speelt, en sturen hun knoppen de pc: afspelen en pauzeren, volgende en vorige, spoelen,
/// shuffle en herhalen, en het volume van de app. Een tik in je bibliotheek speelt daar. Bij het openen
/// staat de laatst gekozen zone er weer, tenzij die niet bereikbaar is, niets speelt of al een half uur op
/// pauze staat ([kiesBijStart]). Een zone kiezen verplaatst de muziek nooit; dat doet "Hier verder".
///
/// **Hoe.** [ZoneSpeler] leest de zone uit de [ZoneLijst] (die de pc meteen bijwerkt) en stuurt
/// opdrachten naar `/api/zone/cmd`. Wat je indrukt, staat meteen op het scherm ([ZoneSpeler] verwacht
/// het al), en wordt rechtgezet zodra de zone zelf meldt wat er gebeurde — of na drie seconden, als ze
/// niets meldt.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'artwork.dart' show HoesVlek, kleurEnVlekkenBuitenDeTekendraad;
import 'lan/zones.dart';
import 'luidheid.dart' show Bijstelling;
import 'models.dart';
import 'player.dart' show RepeatMode, Rijbediening, Speelbron;
import 'zone_lijst.dart';

/// Hoe lang wat je indrukte op het scherm blijft staan als de zone (nog) niets anders meldt.
const kZoneVerwacht = Duration(seconds: 3);

/// Hoe lang het volgende nummer na "volgende" blijft staan als de zone nog het oude meldt. Ruimer dan
/// [kZoneVerwacht]: het nummer moet eerst openen, en terugspringen naar het oude en dan weer vooruit is erger dan even
/// wachten. Gemeten 26-10-2026: de Shield vroeg het nieuwe nummer 250–350 ms na de opdracht aan de pc.
const kZoneVerwachtNummer = Duration(seconds: 8);

/// Hoe lang een meting van "volgende" wacht op een nieuw nummer ([ZoneSpeler.meet]).
const kZoneMeetVolgende = Duration(seconds: 15);

/// Een zone die al zo lang op pauze staat, opent de app niet meer vanzelf (Saber: "langer dan 30 min
/// stil").
const kZoneStilTeLang = Duration(minutes: 30);

/// Welke zone er bij het openen gekozen is: de laatst gekozen [laatste], tenzij die er niet (meer) is,
/// niet bereikbaar is, niets speelt of langer dan [kZoneStilTeLang] op pauze staat. Null = dit toestel.
String? kiesBijStart(String laatste, List<ZoneStaat> zones, {required int nuMs, required String hier}) {
  if (laatste.isEmpty || laatste == hier) return null;
  final z = zones.where((z) => z.id == laatste).firstOrNull;
  if (z == null || !z.online || !z.speeltIets) return null;
  if (!z.playing && nuMs - z.opMs > kZoneStilTeLang.inMilliseconds) return null;
  return laatste;
}

/// De volgende stand van herhalen, zoals de knop rondloopt.
RepeatMode volgendeHerhaal(RepeatMode m) => switch (m) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };

RepeatMode herhaalUit(String s) => switch (s) {
      'all' => RepeatMode.all,
      'one' => RepeatMode.one,
      _ => RepeatMode.off,
    };

/// Wat er met de ids van [tracks] naar de zone gaat: de ids die de pc kent, en de plek van [index] in
/// die lijst. Nummers zonder id (een adres, iets wat de pc niet heeft) vallen weg; valt het nummer op
/// [index] zelf weg, dan het eerstvolgende dat overblijft.
({List<String> ids, int plek}) idsVoor(List<Track> tracks, int index, String? Function(Track t) idVan) {
  final ids = <String>[];
  var plek = -1;
  for (var i = 0; i < tracks.length; i++) {
    final id = idVan(tracks[i]);
    if (id == null || id.isEmpty) continue;
    if (i >= index && plek < 0) plek = ids.length;
    ids.add(id);
  }
  return (ids: ids, plek: plek < 0 ? 0 : plek);
}

/// Een zone op afstand, zoals de spelerbalk en Nu speelt haar zien. Zie de uitleg bovenaan.
class ZoneSpeler extends ChangeNotifier implements Speelbron, Rijbediening {
  ZoneSpeler({
    required this.lijst,
    required this.zoneId,
    required this.nummer,
    required this.idVan,
    required this.hoesVan,
    required this.stuur,
    this.haalRij,
    this.meet,
    int Function()? klok,
  }) : _klok = klok {
    lijst.addListener(_lijstVeranderd);
    _lijstVeranderd();
  }

  /// Een venster op de wachtrij van deze zone (`{index, lengte, van, rij}`) tot [na] nummers ná het spelende, of
  /// null. Zie `ZoneRegister.rijVenster`. Null: geen wachtrij te zien (een oudere pc).
  final Future<Map<String, dynamic>?> Function(int na)? haalRij;

  /// Elke nummerwissel van deze zone: hoe oud de melding van de pc was toen ze hier aankwam, en na een druk op
  /// "volgende" hoe lang dat duurde. Saber, 26-10-2026: *"op de shield klonk het volgende liedje, maar op de gsm duurde
  /// het echt paar seconden eer ik het zag"* — en niets in de logboeken zei waar die seconden zaten.
  final void Function(String regel)? meet;

  final ZoneLijst lijst;
  final String zoneId;

  /// Een id van de pc als nummer hier, of null.
  final Track? Function(String id) nummer;

  /// Het id van de pc voor een nummer hier, of null (dan kan het niet mee).
  final String? Function(Track t) idVan;

  /// De hoes van een nummer, zoals de bibliotheek hier hem heeft.
  final Uint8List? Function(Track t) hoesVan;

  /// Stuur een opdracht naar deze zone (`{cmd, …}`; zone en id vult [_stuur] in). Null als ze aankwam,
  /// anders de zin die op het scherm hoort.
  final Future<String?> Function(Map<String, dynamic> opdracht) stuur;

  final int Function()? _klok;
  int get _nu => _klok?.call() ?? DateTime.now().millisecondsSinceEpoch;

  ZoneStaat? _zone;

  /// De zone zoals de pc haar het laatst meldde, of null als ze uit de lijst verdween.
  ZoneStaat? get zone => _zone;

  // Wat je net indrukte, tot de zone het bevestigt of [kZoneVerwacht] voorbij is.
  bool? _speeltV;
  int? _plekV, _plekVOp;
  bool? _shuffleV;
  RepeatMode? _herhaalV;
  double? _volumeV;
  int _verwachtTot = 0;

  // Na "volgende": het nummer dat de zone gaat openen ([ZoneStaat.volgendeId]), tot ze een ander nummer meldt dan wat
  // er speelde toen je drukte ([_nogNiet]).
  String? _nummerV;
  Set<String> _nogNiet = const {};

  // De meting van een druk op "volgende" ([meet]): wanneer, vanaf welk nummer, en welk nummer we verwachtten.
  int? _meetOp;
  String _meetVan = '', _meetNaar = '';

  String? _fout;
  Timer? _foutWeg;
  Timer? _tik;
  var _opdrachtNr = 0;

  void _lijstVeranderd() {
    final z = lijst.zones.where((z) => z.id == zoneId).firstOrNull;
    final was = _zone;
    _zone = z;
    // Wat je indrukte blijft staan tot de zone het bevestigt, of tot [kZoneVerwacht] om is. Niet bij de
    // eerste de beste melding: een gewone melding die vertrok vlak voor je druk aankwam, liet de knop
    // anders even terugspringen.
    if (z != null && (_nu > _verwachtTot || _bevestigt(z))) _wisVerwacht();
    if (z != null && was != null && z.trackId != was.trackId && z.trackId.isNotEmpty) _meetWissel(z);
    _volgTik();
    // Er keek de laatste tien seconden iemand naar de wachtrij, en die kan nu anders zijn.
    if (_nu - _rijGevraagdOp < 10000 && _rijSleutel != _rijVoor) _haalRijLater();
    if (was != z) notifyListeners();
  }

  // ── De wachtrij: een venster rond het spelende nummer ──────────────────────

  List<Track> _rij = const [];
  List<String> _rijIds = const [];
  int _rijVan = 0;

  /// Voor welke stand van de zone het venster gehaald werd (nummer, plek, lengte). Leeg = opnieuw halen.
  String _rijVoor = '';
  bool _rijBezig = false;
  int _rijGevraagdOp = 0;

  String get _rijSleutel {
    final z = _zone;
    return z == null ? '' : '${z.trackId}|${z.index}|${z.lengte}';
  }

  /// Hoeveel nummers ná het spelende het venster vraagt. Begint op [kZoneRijNa] en groeit met [meerHierna].
  int _na = kZoneRijNa;

  /// Hoeveel er nog komen na het spelende nummer, in de HELE wachtrij van de zone — niet in het venster
  /// ([queueTracks]). Saber, 25-10-2026: *"shuffle heel men bibliotheek, hierna 400 ????"*: de Shield had alle 1769
  /// nummers in zijn wachtrij (gemeten, geen enkele dubbel), maar het paneel telde het venster.
  int get hiernaInRij {
    final z = _zone;
    return z == null ? 0 : (z.lengte - z.index - 1).clamp(0, 1 << 30);
  }

  /// Hoeveel er al speelden, in de hele wachtrij.
  int get eerderInRij => (_zone?.index ?? 0).clamp(0, 1 << 30);

  /// Je scrolt naar het einde van wat er staat: haal er [kZoneRijStap] bij, tot de hele wachtrij er staat. Bouwt niet
  /// zelf: het halen loopt over een klok ([_haalRijLater]), dus dit mag vanuit het bouwen van een regel.
  void meerHierna() {
    final z = _zone;
    if (z == null || _weg) return;
    final tot = _rijVan + _rijIds.length;
    if (tot >= z.lengte) return; // alles staat er al
    final nodig = tot - z.index - 1 + kZoneRijStap;
    if (nodig <= _na) return; // al gevraagd
    _na = nodig;
    _rijVoor = '';
    _haalRijLater();
  }

  void _haalRijLater() {
    final h = haalRij;
    if (_rijBezig || h == null || _weg) return;
    _rijBezig = true;
    Timer(const Duration(milliseconds: 150), () async {
      final sleutel = _rijSleutel;
      try {
        final m = await h(_na);
        if (_weg) return;
        _rijVoor = sleutel;
        final ids = [for (final x in (m?['rij'] as List? ?? const [])) '$x'];
        _rijIds = ids;
        _rijVan = (m?['van'] as num?)?.toInt() ?? 0;
        _rij = [
          for (final id in ids)
            nummer(id) ?? Track(path: 'zone:$id', title: 'Onbekend nummer', artist: '', album: ''),
        ];
        notifyListeners();
      } catch (_) {
        // Geen pc: niet blijven proberen tot de zone iets nieuws meldt.
        _rijVoor = sleutel;
      } finally {
        _rijBezig = false;
      }
      if (!_weg && _rijSleutel != _rijVoor && _nu - _rijGevraagdOp < 10000) _haalRijLater();
    });
  }

  /// Na een opdracht die de wachtrij verandert: even later opnieuw halen (het toestel moet ze eerst
  /// uitvoeren en melden; een verplaatsing verandert nummer, plek noch lengte).
  void _rijStraksOpnieuw() {
    Timer(const Duration(milliseconds: 900), () {
      if (_weg) return;
      _rijVoor = '';
      if (_nu - _rijGevraagdOp < 10000) _haalRijLater();
    });
  }

  void _meetWissel(ZoneStaat z) {
    final m = meet;
    if (m == null) return;
    final oud = lijst.nuOpPc() - z.opMs;
    final druk = _meetOp;
    final naDruk = druk != null && z.trackId != _meetVan
        ? ' · ${_nu - druk} ms na je druk op volgende${z.trackId == _meetNaar || _meetNaar.isEmpty ? '' : ' (een ander nummer dan verwacht)'}'
        : '';
    if (naDruk.isNotEmpty) _meetOp = null;
    final wat = [z.artiest, z.titel].where((x) => x.isNotEmpty).join(' — ');
    m('${z.naam}: nieuw nummer${wat.isEmpty ? '' : ' "$wat"'} · melding ${z.opMs > 0 ? '$oud ms' : 'zonder tijd'} oud bij aankomst$naDruk');
  }

  /// Zegt [z] wat we verwachtten?
  bool _bevestigt(ZoneStaat z) {
    if (_nummerV != null && _nogNiet.contains(z.trackId)) return false;
    if (_speeltV != null && z.playing != _speeltV) return false;
    if (_shuffleV != null && z.shuffle != _shuffleV) return false;
    if (_herhaalV != null && herhaalUit(z.repeat) != _herhaalV) return false;
    if (_volumeV != null && (z.volume - _volumeV!).abs() > 1) return false;
    final plek = _plekV;
    if (plek != null) {
      final sinds = (_speeltV ?? z.playing) && _plekVOp != null ? _nu - _plekVOp! : 0;
      if ((positieNu(z, nuMs: lijst.nuOpPc()).inMilliseconds - (plek + sinds)).abs() > 2000) return false;
    }
    return true;
  }

  void _wisVerwacht() {
    _nummerV = null;
    _nogNiet = const {};
    _speeltV = null;
    _plekV = null;
    _plekVOp = null;
    _shuffleV = null;
    _herhaalV = null;
    _volumeV = null;
  }

  void _verwacht([Duration hoeLang = kZoneVerwacht]) {
    // Nooit korter dan wat er al liep: een volumetik vlak na "volgende" laat het volgende nummer niet vroeger los.
    final tot = _nu + hoeLang.inMilliseconds;
    if (tot > _verwachtTot) _verwachtTot = tot;
    Timer(hoeLang + const Duration(milliseconds: 50), () {
      if (_nu > _verwachtTot) {
        _wisVerwacht();
        notifyListeners();
      }
    });
  }

  /// De plek schuift op zolang er iets speelt en er iemand kijkt.
  void _volgTik() {
    final moet = playing && hasListeners;
    if (moet && _tik == null) {
      _tik = Timer.periodic(const Duration(milliseconds: 500), (_) => notifyListeners());
    } else if (!moet && _tik != null) {
      _tik?.cancel();
      _tik = null;
    }
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _volgTik();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _volgTik();
  }

  Future<void> _stuur(String cmd, [Map<String, dynamic> extra = const {}]) async {
    final nr = ++_opdrachtNr;
    final fout = await stuur({'cmd': cmd, ...extra});
    if (nr != _opdrachtNr && fout == null) return;
    _fout = fout;
    _foutWeg?.cancel();
    if (fout != null) {
      // Het lukte niet: niet blijven doen alsof.
      _wisVerwacht();
      _foutWeg = Timer(const Duration(seconds: 6), () {
        _fout = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  // ── Wat er te zien is ──────────────────────────────────────────────────────

  String? _hoesVoor;
  Uint8List? _hoes;

  @override
  Track? get current {
    final z = _zone;
    if (z == null || !z.speeltIets) return null;
    final v = _nummerV;
    if (v != null) {
      final t = nummer(v);
      if (t != null) return t;
    }
    return nummer(z.trackId) ??
        Track(
          path: 'zone:${z.trackId}',
          title: z.titel.isEmpty ? 'Onbekend nummer' : z.titel,
          artist: z.artiest,
          album: z.album,
          duration: z.durationMs > 0 ? Duration(milliseconds: z.durationMs) : null,
        );
  }

  @override
  Uint8List? get currentCover {
    final t = current;
    final sleutel = t?.path;
    if (sleutel != _hoesVoor) {
      _hoesVoor = sleutel;
      _hoes = t == null ? null : hoesVan(t);
      wasKleur = null;
      hoesVlekken = const [];
      final b = _hoes;
      if (b != null) unawaited(_kleurUit(b));
    } else if (_hoes == null && t != null) {
      // Op een toestel komen de hoezen pas na een ronde van de pc binnen: later nog eens kijken.
      _hoes = hoesVan(t);
      if (_hoes != null) unawaited(_kleurUit(_hoes!));
    }
    return _hoes;
  }

  Future<void> _kleurUit(Uint8List bytes) async {
    try {
      final uit = await kleurEnVlekkenBuitenDeTekendraad(bytes);
      if (!identical(bytes, _hoes)) return;
      wasKleur = uit.kleur;
      hoesVlekken = uit.vlekken;
      notifyListeners();
    } catch (_) {}
  }

  @override
  int? wasKleur;
  @override
  List<HoesVlek> hoesVlekken = const [];

  @override
  bool get playing => _speeltV ?? (_zone?.playing ?? false);

  @override
  Duration get position {
    final v = _plekV;
    if (v != null) {
      final sinds = playing && _plekVOp != null ? _nu - _plekVOp! : 0;
      final ms = v + sinds;
      final duur = duration.inMilliseconds;
      return Duration(milliseconds: duur > 0 && ms > duur ? duur : ms);
    }
    final z = _zone;
    if (z == null) return Duration.zero;
    // Pauze ingedrukt en nog niet bevestigd: niet verder laten lopen.
    if (_speeltV == false) return positieNu(metSpelen(z, false), nuMs: lijst.nuOpPc());
    return positieNu(z, nuMs: lijst.nuOpPc());
  }

  @override
  Duration get duration {
    final z = _zone;
    // Het volgende nummer staat er al: zijn eigen lengte, niet die van het nummer dat de zone nog meldt.
    if (_nummerV != null) {
      final d = current?.duration;
      if (d != null && d > Duration.zero) return d;
    }
    if (z != null && z.durationMs > 0) return Duration(milliseconds: z.durationMs);
    return current?.duration ?? Duration.zero;
  }

  @override
  bool get speeltErgens => playing;
  @override
  Duration get positieErgens => position;
  @override
  Duration get duurErgens => duration;

  @override
  bool get shuffle => _shuffleV ?? (_zone?.shuffle ?? false);
  @override
  RepeatMode get repeat => _herhaalV ?? herhaalUit(_zone?.repeat ?? 'off');

  @override
  double get volume => _volumeV ?? ((_zone?.volume ?? -1) >= 0 ? _zone!.volume.toDouble() : 100);

  /// Meldt de zone haar volume? Een oudere app of een speaker zonder volume niet.
  bool get heeftVolume => (_zone?.volume ?? -1) >= 0 || _volumeV != null;

  @override
  bool get radioMode => (_zone?.radio ?? '').isNotEmpty;
  @override
  bool get hasNext {
    final z = _zone;
    return z != null && z.speeltIets && (radioMode || z.index + 1 < z.lengte);
  }

  @override
  bool get hasPrev {
    final z = _zone;
    return z != null && z.speeltIets && (z.index > 0 || position > const Duration(seconds: 3));
  }

  @override
  String? get speelFout {
    final z = _zone;
    if (z == null) return 'Deze zone is er niet meer';
    if (!z.online) return '${z.naam} is niet bereikbaar';
    return _fout;
  }

  @override
  bool get speeltHerhaling => false;
  /// De plek van het spelende nummer in [queueTracks] (het venster), niet in de hele wachtrij.
  @override
  int get currentIndex {
    final z = _zone;
    if (z == null) return 0;
    var i = z.index - _rijVan;
    // Na "volgende": de regel van het volgende nummer, zoals de balk en Nu speelt.
    final v = _nummerV;
    if (v != null) {
      final j = _rijIds.indexOf(v, i < 0 ? 0 : i);
      if (j >= 0) i = j;
    }
    return i >= 0 && i < _rij.length ? i : 0;
  }

  /// Het venster op de wachtrij van de zone: tot 100 nummers ervoor en 400 erna. Wie dit leest, wil het
  /// zien: dan wordt het bijgehouden zolang er iemand kijkt.
  @override
  List<Track> get queueTracks {
    _rijGevraagdOp = _nu;
    if (_rijSleutel != _rijVoor) _haalRijLater();
    return _rij;
  }
  @override
  Track? get volgendNummer => null;
  @override
  Bijstelling? get luidheidToegepast => null;

  // ── Wat je kunt doen ───────────────────────────────────────────────────────

  @override
  void playPause() => playing ? pauzeer() : speelAf();

  @override
  void speelAf() {
    _speeltV = true;
    _plekV = position.inMilliseconds;
    _plekVOp = _nu;
    _verwacht();
    notifyListeners();
    _volgTik();
    unawaited(_stuur('play'));
  }

  @override
  void pauzeer() {
    _plekV = position.inMilliseconds;
    _plekVOp = _nu;
    _speeltV = false;
    _verwacht();
    notifyListeners();
    _volgTik();
    unawaited(_stuur('pause'));
  }

  @override
  Future<void> next() {
    _verwachtVolgende();
    return _stuur('next');
  }

  /// Het volgende nummer meteen op het scherm, met de plek op nul, tot de zone het meldt. Alleen als vaststaat welk
  /// nummer het wordt ([ZoneStaat.volgendeId], of na een tweede druk het nummer daarna in het venster) en dit toestel
  /// het kent; anders blijft het scherm wachten op de zone, zoals voorheen.
  void _verwachtVolgende() {
    final z = _zone;
    if (z == null || !z.speeltIets) return;
    final al = _nummerV;
    var id = z.volgendeId;
    if (al != null) {
      final i = _rijIds.indexOf(al);
      id = i >= 0 && i + 1 < _rijIds.length ? _rijIds[i + 1] : '';
    }
    _meetOp = _nu;
    _meetVan = z.trackId;
    _meetNaar = id;
    final m = meet;
    if (m != null) {
      final op = _meetOp;
      Timer(kZoneMeetVolgende, () {
        if (_weg || _meetOp != op) return;
        _meetOp = null;
        m('${_zone?.naam ?? zoneId}: volgende → geen nieuw nummer binnen ${kZoneMeetVolgende.inSeconds} s');
      });
    }
    if (id.isEmpty || nummer(id) == null) return;
    _nogNiet = {..._nogNiet, z.trackId, if (al != null) al};
    _nummerV = id;
    _plekV = 0;
    _plekVOp = _nu;
    _verwacht(kZoneVerwachtNummer);
    notifyListeners();
  }
  @override
  Future<void> prev() => _stuur('previous');

  @override
  void seek(Duration d) {
    _plekV = d.inMilliseconds;
    _plekVOp = _nu;
    _verwacht();
    notifyListeners();
    unawaited(_stuur('seek', {'ms': d.inMilliseconds}));
  }

  @override
  void zetShuffle(bool aan) {
    _shuffleV = aan;
    _verwacht();
    notifyListeners();
    unawaited(_stuur('shuffle', {'aan': aan}));
  }

  @override
  void toggleShuffle() => zetShuffle(!shuffle);

  @override
  void zetHerhaal(RepeatMode m) {
    _herhaalV = m;
    _verwacht();
    notifyListeners();
    unawaited(_stuur('repeat', {'stand': m.name}));
  }

  @override
  void cycleRepeat() => zetHerhaal(volgendeHerhaal(repeat));

  Timer? _volumeKlok;
  double? _volumeTeSturen;

  /// Hoogstens vier keer per seconde, en de laatste stand komt altijd aan.
  @override
  void setVolume(double v) {
    _volumeV = v.clamp(0, 100).toDouble();
    _verwacht();
    notifyListeners();
    _volumeTeSturen = _volumeV;
    if (_volumeKlok != null) return;
    void verstuur() {
      final w = _volumeTeSturen;
      _volumeTeSturen = null;
      if (w == null) {
        _volumeKlok = null;
        return;
      }
      unawaited(_stuur('volume', {'waarde': w.round()}));
      _volumeKlok = Timer(const Duration(milliseconds: 250), verstuur);
    }

    verstuur();
  }

  /// Een zone op afstand: haar volume regel je hier niet zachter voor een navigatiestem.
  @override
  void zetDemping(bool aan) {}

  /// Naar [plek] in [queueTracks]. Het nummer gaat mee: is de rij intussen verschoven, dan zoekt de zone
  /// het zelf op.
  @override
  Future<void> springNaar(int plek) => _stuur('jump', {
        'plek': plek + _rijVan,
        if (plek >= 0 && plek < _rijIds.length) 'trackId': _rijIds[plek],
      });

  @override
  bool haalUitWachtrij(int plek) {
    if (plek < 0 || plek >= _rijIds.length) return false;
    final id = _rijIds[plek];
    // Meteen weg op het scherm; de zone meldt daarna haar echte wachtrij.
    _rijIds = [..._rijIds]..removeAt(plek);
    _rij = [..._rij]..removeAt(plek);
    notifyListeners();
    unawaited(_stuur('remove', {'plek': plek + _rijVan, 'trackId': id}).then((_) => _rijStraksOpnieuw()));
    return true;
  }

  @override
  bool verplaatsInWachtrij(int van, int naar) {
    if (van < 0 || van >= _rijIds.length || naar < 0 || naar >= _rijIds.length || van == naar) return false;
    final id = _rijIds[van];
    _rijIds = [..._rijIds]..removeAt(van);
    _rijIds.insert(naar, id);
    final t = _rij[van];
    _rij = [..._rij]..removeAt(van);
    _rij.insert(naar, t);
    notifyListeners();
    unawaited(_stuur('move', {'van': van + _rijVan, 'naar': naar + _rijVan, 'trackId': id})
        .then((_) => _rijStraksOpnieuw()));
    return true;
  }

  @override
  Future<void> playQueue(List<Track> queue, int index, {Uint8List? cover}) {
    final r = idsVoor(queue, index, idVan);
    if (r.ids.isEmpty) return _meld('Dit nummer kan niet mee: het staat niet in je bibliotheek op de pc.');
    return _stuur('speel', {'ids': r.ids, 'plek': r.plek});
  }

  @override
  Future<void> shuffleAll(List<Track> tracks) {
    final r = idsVoor(tracks, 0, idVan);
    if (r.ids.isEmpty) return _meld('Deze nummers kunnen niet mee: ze staan niet in je bibliotheek op de pc.');
    return _stuur('speel', {'ids': r.ids, 'plek': 0, 'shuffle': true});
  }

  @override
  void speelHierna(List<Track> nummers) => unawaited(_rijOpdracht('hierna', nummers).then((_) => _rijStraksOpnieuw()));
  @override
  void zetAchteraan(List<Track> nummers) =>
      unawaited(_rijOpdracht('achteraan', nummers).then((_) => _rijStraksOpnieuw()));

  @override
  Future<void> speelNuMetRest(Track t) {
    final id = idVan(t);
    if (id == null) return _meld('Dit nummer kan niet mee: het staat niet in je bibliotheek op de pc.');
    return _stuur('nu', {'id': id});
  }

  /// Een radio starten in deze zone, rond [artiest] met [zaad] (of het nummer [titel]) eerst.
  Future<void> startRadio(String artiest, {Track? zaad, String? titel}) => _stuur('radio', {
        'artiest': artiest,
        // Wie startte: als de radio vanzelf eindigt, komt het overzicht hier (Saber, 23-10-2026).
        'door': lijst.hier,
        if (zaad != null && idVan(zaad) != null) 'zaad': idVan(zaad),
        if (titel != null && titel.isNotEmpty) 'titel': titel,
      });

  /// Speelt hier de radio van de pc ([ZoneStaat.radio] bij een speaker)? Dan gaan [radioStop] en [radioOordeel] erover.
  bool get radioVanDePc => radioMode && zoneId.startsWith('spk:');

  /// De radio van deze zone afsluiten — de radio van de pc op een speaker, of die van een ander toestel. Het overzicht
  /// komt dan hier (Saber, 23-10-2026: "waar ik 'Radio afsluiten' tik").
  Future<void> radioStop() => _stuur('radioStop', {'door': lijst.hier});

  /// Een oordeel over het spelende nummer: 'past', 'pastNiet', 'houden' of 'weg'. Null als de pc het kreeg, anders
  /// de reden (die staat dan ook als [speelFout] op het scherm).
  Future<String?> radioOordeel(String wat) async {
    final id = _zone?.trackId ?? '';
    if (id.isEmpty) return 'Er speelt niets.';
    await _stuur('radioOordeel', {'wat': wat, 'trackId': id});
    return _fout;
  }

  Future<void> _rijOpdracht(String cmd, List<Track> nummers) {
    final ids = [for (final t in nummers) if (idVan(t) case final id?) id];
    if (ids.isEmpty) return _meld('Dit kan niet mee: het staat niet in je bibliotheek op de pc.');
    return _stuur(cmd, {'ids': ids});
  }

  Future<void> _meld(String zin) async {
    _fout = zin;
    _foutWeg?.cancel();
    _foutWeg = Timer(const Duration(seconds: 6), () {
      _fout = null;
      notifyListeners();
    });
    notifyListeners();
  }

  bool _weg = false;

  /// Een klok of een hoeskleur die na het weggooien nog aankomt, meldt niets meer.
  @override
  void notifyListeners() {
    if (!_weg) super.notifyListeners();
  }

  @override
  void dispose() {
    _weg = true;
    lijst.removeListener(_lijstVeranderd);
    _tik?.cancel();
    _foutWeg?.cancel();
    _volumeKlok?.cancel();
    super.dispose();
  }
}

/// [z], maar met [speelt] als stand: voor de plek terwijl een pauze nog niet bevestigd is.
ZoneStaat metSpelen(ZoneStaat z, bool speelt) => ZoneStaat(
      id: z.id,
      soort: z.soort,
      naam: z.naam,
      online: z.online,
      playing: speelt,
      trackId: z.trackId,
      positionMs: z.positionMs,
      durationMs: z.durationMs,
      opMs: z.opMs,
    );

/// Welke zone er gekozen is ("Speelt op: … ▾"), per toestel bewaard. Zie de uitleg bovenaan.
class GekozenZone extends ChangeNotifier {
  GekozenZone({required this.lijst, required this.maak, required this.bewaar, String laatste = ''})
      : _laatste = laatste {
    lijst.addListener(_lijstVeranderd);
    _lijstVeranderd();
  }

  final ZoneLijst lijst;

  /// Een [ZoneSpeler] voor een zone.
  final ZoneSpeler Function(String zoneId) maak;

  /// Bewaar de keuze (leeg = dit toestel).
  final void Function(String zoneId) bewaar;

  final String _laatste;
  bool _beslist = false;
  ZoneSpeler? _speler;

  /// De zone op afstand die gekozen is, of null: dan speelt en bedient alles dit toestel.
  ZoneSpeler? get opAfstand => _speler;

  /// De id van de gekozen zone (dit toestel als er niets op afstand gekozen is).
  String get gekozen => _speler?.zoneId ?? lijst.hier;

  void _lijstVeranderd() {
    if (!lijst.ondersteund) {
      // Een pc zonder zones (meer): terug naar dit toestel, zonder de keuze te vergeten.
      if (_speler != null) _zet(null, bewaren: false);
      return;
    }
    if (!_beslist) {
      _beslist = true;
      final z = kiesBijStart(_laatste, lijst.zones, nuMs: lijst.nuOpPc(), hier: lijst.hier);
      if (z != null) _zet(z, bewaren: false);
    }
  }

  /// Kies [zoneId] (dit toestel = [ZoneLijst.hier]). De muziek verhuist niet.
  void kies(String zoneId) => _zet(zoneId == lijst.hier ? null : zoneId, bewaren: true);

  void _zet(String? zoneId, {required bool bewaren}) {
    if (zoneId == _speler?.zoneId) return;
    final oud = _speler;
    oud?.removeListener(notifyListeners);
    _speler = zoneId == null ? null : maak(zoneId);
    // Wie naar de gekozen zone kijkt (de balk, Nu speelt), ziet ook elke wijziging van haar speler.
    _speler?.addListener(notifyListeners);
    if (bewaren) bewaar(zoneId ?? '');
    notifyListeners();
    // Pas na het hertekenen weg: een scherm dat nog naar de oude luistert, mag dat nog even.
    if (oud != null) scheduleMicrotask(oud.dispose);
  }

  @override
  void dispose() {
    lijst.removeListener(_lijstVeranderd);
    _speler?.removeListener(notifyListeners);
    _speler?.dispose();
    super.dispose();
  }
}

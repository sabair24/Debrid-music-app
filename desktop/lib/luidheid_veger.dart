/// Gelijk volume — de pc meet elk nummer één keer, op de achtergrond.
///
/// Eén ffmpeg tegelijk, op één kern (`-threads 1`), met 200 ms rust ertussen; de eerste ronde over
/// Sabers 1437 nummers kost zo 30–35 minuten (gemeten 0,7–1,1 s per nummer, plus een tweede gang
/// voor de ~430 bestanden boven 48 kHz), daarna alleen wat nieuw of veranderd is. De veger wacht
/// zolang de bibliotheek scant en zolang de pc voor een toestel omzet:
/// de eerste byte voor de telefoon op 5G gaat voor.
///
/// **Een time-out of een bestand dat tijdens de meting verandert wordt nooit als "mislukt" bewaard**:
/// dat gaat voorbij, en een bewaarde mislukking komt pas terug als het bestand verandert. Een time-out
/// die in twee sessies optreedt is wél definitief, anders blijft de eerste ronde op één bestand hangen.
///
/// Zie luidheid.dart voor de rekensom en luidheid_winkel.dart voor de opslag.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'ffmpeg.dart';
import 'flac_tags.dart';
import 'lan/transcode.dart' show Transcoder;
import 'library.dart';
import 'luidheid.dart';
import 'luidheid_winkel.dart';
import 'models.dart';
import 'paths.dart';
import 'warm_log.dart';

/// Wat één meting opleverde.
typedef MeetUitkomst = ({
  Luidheidsuitslag uitslag,
  FlacKern? erfbaar,
  bool tijdOp,
});

const _nulMd5 = '00000000000000000000000000000000';

String? _pcmVoor(FlacKern? kern) {
  if (kern == null || kern.md5 == _nulMd5) return null;
  return switch (kern.diepte) { 16 => 'pcm_s16le', 24 => 'pcm_s24le', _ => null };
}

final _md5Regel = RegExp(r'MD5=([0-9a-fA-F]{32})');

/// Een fout die niets over het BESTAND zegt: vergrendeld (Windows, een virusscanner) of even
/// onbereikbaar. Zo'n uitslag wordt niet bewaard; de volgende ronde probeert het opnieuw.
final _tijdelijkeFout = RegExp(
    r'Permission denied|Device or resource busy|Resource temporarily unavailable|'
    r'being used by another process',
    caseSensitive: false);

/// Zegt deze foutuitvoer van ffmpeg niets over het bestand zelf? Zie [_tijdelijkeFout]. "Invalid
/// argument" hoort er bewust niet bij: dat geeft ffmpeg ook op een echt kapot bestand, en dan zou het
/// elke ronde opnieuw geprobeerd worden en nooit "kon niet meten" zeggen.
@visibleForTesting
bool isTijdelijkeFout(String stderr) => _tijdelijkeFout.hasMatch(stderr);

typedef _Uitvoer = ({int code, String fout, String uit, bool tijdOp});

/// Eén ffmpeg-gang: stderr en stdout als tekst (UTF-8, kapotte tekens toegestaan), met een limiet.
/// Gooit als het proces niet start.
Future<_Uitvoer> _draai(String exe, List<String> args, Duration limiet, void Function(Process p)? opStart) async {
  final p = await Process.start(exe, args);
  opStart?.call(p);
  final fout = StringBuffer(), uit = StringBuffer();
  const lezer = Utf8Decoder(allowMalformed: true);
  final klaarErr = p.stderr.transform(lezer).listen(fout.write).asFuture<void>();
  final klaarUit = p.stdout.transform(lezer).listen(uit.write).asFuture<void>();
  try {
    final code = await p.exitCode.timeout(limiet);
    await Future.wait([klaarErr, klaarUit]).timeout(const Duration(seconds: 5), onTimeout: () => const []);
    return (code: code, fout: fout.toString(), uit: uit.toString(), tijdOp: false);
  } on TimeoutException {
    p.kill();
    await p.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
    return (code: -1, fout: fout.toString(), uit: uit.toString(), tijdOp: true);
  }
}

/// Meet [pad]: geïntegreerde luidheid, monster- en ware piek, het aantal kanalen — en bij een FLAC van
/// 16 of 24 bit in DEZELFDE decodeergang de MD5 van de gedecodeerde monsters. Klopt die met de MD5 in
/// de kop, dan is bewezen dat de meting de volledige, correct gedecodeerde audio betrof, en is de
/// uitslag erfbaar (zie [erfbareLuidheid]). Een afgekapte FLAC belooft in zijn kop nog steeds het hele
/// nummer; die geeft hier een andere MD5 en wordt dus nooit erfbaar.
///
/// **Boven 48 kHz: een tweede gang na herbemonstering naar 48 kHz.** mpv zet zo'n bestand om naar de
/// mengfrequentie van het toestel (48 kHz op Windows en Android) en haalt daarbij alles boven 24 kHz
/// weg — en daarna liggen de pieken hoger dan in het bestand zelf. Nagemeten: 28 bestanden van
/// 192 kHz tot +0,45 dB boven hun eigen ware piek, en op 96 kHz evengoed (Bob Marley, "Could You Be
/// Loved", 96/24: −0,1 → +0,5). Een zacht hi-res nummer dat "tot −1 dBTP" opgehoogd werd, kwam zo op
/// −0,55 uit. Daarom P = max(P, piek na `aresample=48000`), voor ELK gemeten bestand boven 48 kHz:
/// de oorspronkelijke grens ≥ 176,4 kHz miste 88,2 en 96 kHz, en de drempel "alleen als P > −3"
/// beschermde een ophoging niet (P −5 met +4 dB komt net zo goed boven −1). ~430 bestanden, zo'n
/// zeven minuten extra in de eerste ronde. ffmpeg's eigen `aresample` gaf op de nagemeten bestanden
/// gelijke of hogere pieken dan mpv's instellingen: de veilige kant.
///
/// [opStart] krijgt het proces, zodat de veger het kan afbreken als het bestand verplaatst of gewist
/// wordt (Windows houdt een open bestand vast).
Future<MeetUitkomst> meetLuidheid(
  String pad, {
  String? ffmpeg,
  Duration limiet = const Duration(minutes: 3),
  void Function(Process p)? opStart,
}) async {
  final exe = ffmpeg ?? Ffmpeg().pad;
  if (exe == null) return (uitslag: const Mislukt('ffmpeg ontbreekt', tijdelijk: true), erfbaar: null, tijdOp: false);
  final kern = leesFlacKern(File(pad));
  final pcm = _pcmVoor(kern);
  const kop = ['-nostdin', '-hide_banner', '-nostats', '-loglevel', 'info', '-threads', '1'];
  final args = [
    ...kop, '-i', pad, //
    '-map', '0:a:0', '-af', 'ebur128=peak=sample+true:framelog=verbose', '-f', 'null', '-',
    if (pcm != null) ...['-map', '0:a:0', '-c:a', pcm, '-f', 'md5', 'pipe:1'],
  ];
  _Uitvoer r;
  try {
    r = await _draai(exe, args, limiet, opStart);
  } catch (e) {
    return (uitslag: Mislukt('ffmpeg start niet: $e', tijdelijk: true), erfbaar: null, tijdOp: false);
  }
  if (r.tijdOp) return (uitslag: const Mislukt('te lang'), erfbaar: null, tijdOp: true);
  if (r.code != 0) {
    final regel = r.fout
        .split('\n')
        .map((x) => x.trim())
        .firstWhere((x) => x.isNotEmpty && !x.startsWith('Input #') && !x.startsWith('Duration'),
            orElse: () => 'ffmpeg stopte met code ${r.code}');
    return (
      uitslag: Mislukt(regel, tijdelijk: _tijdelijkeFout.hasMatch(r.fout)),
      erfbaar: null,
      tijdOp: false,
    );
  }
  final e = leesEbur128(r.fout);
  var uitslag = uitslagUit(e, kanalenUitKop: kern?.kanalen);
  FlacKern? erfbaar;
  if (pcm != null && uitslag is! Mislukt) {
    final m = _md5Regel.firstMatch(r.uit);
    if (m != null && m.group(1)!.toLowerCase() == kern!.md5) erfbaar = kern;
  }

  final hz = e.frequentie ?? kern?.frequentie;
  if (uitslag is Gemeten && tweedeGangNodig(hz)) {
    _Uitvoer r48;
    try {
      r48 = await _draai(
          exe,
          [
            ...kop, '-i', pad, //
            '-map', '0:a:0', '-af', 'aresample=48000,ebur128=peak=sample+true:framelog=verbose', '-f', 'null', '-',
          ],
          limiet,
          opStart);
    } catch (e) {
      return (uitslag: Mislukt('ffmpeg start niet: $e', tijdelijk: true), erfbaar: null, tijdOp: false);
    }
    if (r48.tijdOp) return (uitslag: const Mislukt('te lang'), erfbaar: null, tijdOp: true);
    final u48 = r48.code == 0 ? uitslagUit(leesEbur128(r48.fout), kanalenUitKop: kern?.kanalen) : null;
    // Zonder de tweede piek is de eerste niet te vertrouwen: niet bewaren, de volgende ronde opnieuw.
    if (u48 is! Gemeten) {
      return (uitslag: const Mislukt('piek na 48 kHz niet gemeten', tijdelijk: true), erfbaar: null, tijdOp: false);
    }
    final m = uitslag.meting;
    uitslag = Gemeten(Luidheidsmeting(lufs: m.lufs, piek: math.max(m.piek, u48.meting.piek)));
  }
  return (uitslag: uitslag, erfbaar: erfbaar, tijdOp: false);
}

/// De mengfrequentie van mpv op Windows en Android. Boven deze frequentie meet [meetLuidheid] de piek
/// ook na herbemonstering ernaartoe.
const kMengfrequentie = 48000;

/// Krijgt een bestand van [hz] de tweede gang na herbemonstering? Alles boven [kMengfrequentie]: ook
/// 88,2 en 96 kHz, want mpv haalt daar evengoed alles boven 24 kHz weg.
bool tweedeGangNodig(int? hz) => hz != null && hz > kMengfrequentie;

/// De controlegang van de snelweg: decodeert [pad] (zonder ebur128, ~0,1–0,3 s) en zegt of de MD5 van
/// de monsters gelijk is aan die in de kop. Alleen dan mag een eerdere meting overgenomen worden.
Future<bool> controleerFlacMd5(String pad, FlacKern kern,
    {String? ffmpeg, void Function(Process p)? opStart}) async {
  final exe = ffmpeg ?? Ffmpeg().pad;
  final pcm = _pcmVoor(kern);
  if (exe == null || pcm == null) return false;
  try {
    final p = await Process.start(exe, [
      '-nostdin', '-hide_banner', '-loglevel', 'error', '-threads', '1', //
      '-i', pad, '-map', '0:a:0', '-c:a', pcm, '-f', 'md5', 'pipe:1',
    ]);
    opStart?.call(p);
    const lezer = Utf8Decoder(allowMalformed: true);
    final uit = StringBuffer();
    final klaarUit = p.stdout.transform(lezer).listen(uit.write).asFuture<void>();
    final klaarErr = p.stderr.drain<void>();
    final code = await p.exitCode.timeout(const Duration(minutes: 2), onTimeout: () {
      p.kill();
      return -1;
    });
    await Future.wait([klaarUit, klaarErr]).timeout(const Duration(seconds: 5), onTimeout: () => const []);
    if (code != 0) return false;
    final m = _md5Regel.firstMatch(uit.toString());
    return m != null && m.group(1)!.toLowerCase() == kern.md5;
  } catch (_) {
    return false;
  }
}

/// De veger: één ronde over de bibliotheek, en daarna alleen wat verandert.
class LuidheidVeger {
  LuidheidVeger({
    required this.library,
    this.enabled = true,
    Future<MeetUitkomst> Function(String pad, void Function(Process p) opStart)? meet,
    Future<bool> Function(String pad, FlacKern kern, void Function(Process p) opStart)? controleer,
    FlacKern? Function(File f)? leesKern,
    bool Function()? ffmpegAanwezig,
    this.bezigElders,
    this.startNa = const Duration(minutes: 3),
    this.rust = const Duration(seconds: 10),
    this.publiceerElke = const Duration(minutes: 10),
    this.tussenpoos = const Duration(milliseconds: 200),
    this.leeftijd = const Duration(seconds: 60),
    DateTime Function()? nu,
  })  : _meet = meet ?? ((pad, opStart) => meetLuidheid(pad, opStart: opStart)),
        _controleer = controleer ?? ((pad, kern, opStart) => controleerFlacMd5(pad, kern, opStart: opStart)),
        _leesKern = leesKern ?? leesFlacKern,
        _ffmpegAanwezig = ffmpegAanwezig ?? (() => Ffmpeg().available),
        _nu = nu ?? DateTime.now;

  final LibraryStore library;
  final bool enabled;
  final bool Function()? bezigElders;
  final Duration startNa, rust, publiceerElke, tussenpoos, leeftijd;

  final Future<MeetUitkomst> Function(String pad, void Function(Process p) opStart) _meet;
  final Future<bool> Function(String pad, FlacKern kern, void Function(Process p) opStart) _controleer;
  final FlacKern? Function(File f) _leesKern;
  final bool Function() _ffmpegAanwezig;
  final DateTime Function() _nu;

  /// Voor de hartslag en de instelling: wat de veger nu doet.
  static final ValueNotifier<String> voortgang = ValueNotifier<String>('');

  /// Heeft deze pc ffmpeg? Null zolang het niet gevraagd is.
  static bool? ffmpegGevonden;

  late final WarmLog _log = WarmLog('${library.configDir}${Platform.pathSeparator}luidheid.log');

  bool _gestart = false, _gestopt = false, _bezig = false, _nogEens = false;
  Timer? _start, _herstart;
  DateTime _laatstGepubliceerd = DateTime.fromMillisecondsSinceEpoch(0);

  /// Wanneer een (grootte, mtime) voor het eerst zo gezien is — voor de 60-s-regel.
  final Map<String, DateTime> _eersteKeerGezien = {};

  /// Lopende ffmpeg-processen per pad, en paden die even niet aangeraakt mogen worden.
  final Map<String, Process> _lopend = {};
  final Map<String, DateTime> _geblokkeerd = {};
  final Set<String> _afgebroken = {};

  /// Sleutels die deze sessie al een time-out kregen: niet opnieuw in een volgende ronde.
  final Set<String> _tijdOpDezeSessie = {};

  Future<void> start() async {
    if (!enabled || library.isRemote || _gestart) return;
    _gestart = true;
    publiceerLuidheid(nummers: library.tracks, ffmpeg: true, kaartOok: true);
    library.addListener(_bibliotheekVeranderd);
    _start = Timer(startNa, () => unawaited(ronde()));
  }

  void stop() {
    _gestopt = true;
    _start?.cancel();
    _herstart?.cancel();
    library.removeListener(_bibliotheekVeranderd);
    for (final p in _lopend.values) {
      p.kill();
    }
  }

  void _bibliotheekVeranderd() {
    if (_gestopt || !_gestart || (_start?.isActive ?? false)) return;
    _herstart?.cancel();
    _herstart = Timer(rust, () => unawaited(ronde()));
  }

  /// Breek een lopende meting op [paden] af en laat die paden ~10 s met rust. Voor wissen en
  /// verplaatsen: Windows houdt een bestand vast zolang ffmpeg het open heeft.
  Future<void> laatLos(List<String> paden) async {
    final tot = _nu().add(const Duration(seconds: 10));
    for (final pad in paden) {
      final k = padSleutel(pad);
      _geblokkeerd[k] = tot;
      _afgebroken.add(k);
      final p = _lopend[k];
      if (p != null) {
        p.kill();
        try {
          await p.exitCode.timeout(const Duration(seconds: 5));
        } catch (_) {/* dan maar zonder; de rename probeert het zelf opnieuw */}
      }
    }
  }

  bool _isGeblokkeerd(String pad) {
    final tot = _geblokkeerd[padSleutel(pad)];
    return tot != null && _nu().isBefore(tot);
  }

  Future<bool> _wachtOpRust() async {
    while (!_gestopt && (library.scanning || (bezigElders?.call() ?? false) || Transcoder.bezig)) {
      voortgang.value = library.scanning ? 'wacht: bibliotheek scant' : 'wacht: pc zet om';
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return !_gestopt;
  }

  /// Plaat voor plaat, nieuwste eerst; binnen een plaat in plaatvolgorde.
  List<Track> _volgorde(List<Track> alle) {
    final perPlaat = <Object, List<Track>>{};
    for (final t in alle) {
      final a = library.albumForPath(t.path);
      (perPlaat[a ?? t.path] ??= []).add(t);
    }
    final platen = perPlaat.values.toList()
      ..sort((x, y) => y.map((t) => t.addedMs).reduce((a, b) => a > b ? a : b).compareTo(
          x.map((t) => t.addedMs).reduce((a, b) => a > b ? a : b)));
    return [for (final p in platen) ...p];
  }

  /// Eén ronde (of meer, als er tijdens de ronde iets veranderde).
  @visibleForTesting
  Future<void> ronde() async {
    if (_gestopt) return;
    if (_bezig) {
      _nogEens = true;
      return;
    }
    _bezig = true;
    var jongOvergeslagen = false, later = false;
    try {
      final heeftFfmpeg = _ffmpegAanwezig();
      ffmpegGevonden = heeftFfmpeg;
      if (!heeftFfmpeg) {
        _log.line('ffmpeg ontbreekt — geen metingen (${Ffmpeg.laatsteFout ?? ''})');
        voortgang.value = 'ffmpeg ontbreekt';
        publiceerLuidheid(nummers: library.tracks, ffmpeg: false, kaartOok: true);
        return;
      }
      do {
        _nogEens = false;
        final lijst = _volgorde(List<Track>.of(library.tracks));
        final eersteRonde = !luidheidKlaar;
        final teMeten = [
          for (final t in lijst)
            if (luidheidSleutel(t) case final k? when !luidheidBekend(k)) t
        ];
        final groot = !eersteRonde && teMeten.length > lijst.length * 0.2;
        final alleenStatus = eersteRonde || groot;
        if (teMeten.isNotEmpty) {
          _log.line('ronde: ${teMeten.length} te meten (van ${lijst.length})'
              '${eersteRonde ? ' — eerste ronde' : (groot ? ' — grote herronde' : '')}');
        }
        var gedaan = 0, gemeten = 0, overgenomen = 0, mislukt = 0;
        for (final t in teMeten) {
          if (!await _wachtOpRust()) return;
          gedaan++;
          voortgang.value = 'meten… $gedaan van ${teMeten.length}';
          final k = luidheidSleutel(t)!;
          if (luidheidBekend(k) || _isGeblokkeerd(t.path)) continue;
          final f = File(t.path);
          FileStat st;
          try {
            st = f.statSync();
          } catch (_) {
            continue;
          }
          if (st.type != FileSystemEntityType.file ||
              st.size != t.sizeBytes ||
              st.modified.millisecondsSinceEpoch != t.addedMs) {
            continue; // veranderd sinds de scan; die komt vanzelf terug
          }
          // Oud genoeg: de mtime ligt minstens [leeftijd] in het verleden — het gewone geval, een
          // bestand dat al lang staat — of deze veger zag het al [leeftijd] lang onveranderd (een mtime
          // in de toekomst, een klok die versprong). Alleen het tweede telde eerst, en de veger zag in
          // zijn eerste ronde ELK bestand voor het eerst: hij sloeg alle 1437 nummers over en zette toch
          // "klaar".
          final nu = _nu();
          final gezien = _eersteKeerGezien.putIfAbsent(k, () => nu);
          final ouderdom = nu.difference(st.modified);
          if ((ouderdom.isNegative || ouderdom < leeftijd) && nu.difference(gezien) < leeftijd) {
            jongOvergeslagen = true;
            continue;
          }
          // Een time-out krijgt één poging per sessie; pas een tweede sessie maakt hem definitief.
          if (_tijdOpDezeSessie.contains(k)) continue;
          final ps = padSleutel(t.path);
          _afgebroken.remove(ps);
          // Ook als het verplaatsen begint terwijl ffmpeg nog opstart: dan is er nog geen proces om af
          // te breken op het moment dat laatLos kijkt.
          void aangemeld(Process p) {
            _lopend[ps] = p;
            if (_afgebroken.contains(ps)) p.kill();
          }

          // De snelweg: dezelfde audio als een bewezen volledige meting.
          final kern = _leesKern(f);
          if (kern != null) {
            final erf = erfbareLuidheid(kern);
            if (erf != null) {
              final ok = await _controleer(t.path, kern, aangemeld);
              _lopend.remove(ps);
              if (_afgebroken.contains(ps)) continue;
              if (ok) {
                onthoudLuidheid(k, pad: t.path, uitslag: erf.uitslag, erfbaar: kern);
                overgenomen++;
                continue;
              }
            }
          }

          final u = await _meet(t.path, aangemeld);
          _lopend.remove(ps);
          if (_afgebroken.contains(ps)) continue;
          if (u.tijdOp) {
            _tijdOpDezeSessie.add(k);
            final n = onthoudLuidheidTimeout(k, pad: t.path);
            _log.line('te lang (${n}e keer): ${t.title} — ${t.path}');
            continue;
          }
          final fout = u.uitslag;
          if (fout is Mislukt && fout.tijdelijk) {
            _log.line('nu niet te meten: ${t.title} — ${fout.reden}');
            if (fout.reden == 'ffmpeg ontbreekt' || fout.reden.startsWith('ffmpeg start niet')) {
              // ffmpeg zelf is weg (bijgewerkt, in quarantaine): niet de rest van de ronde als
              // mislukt laten eindigen. Over vijf minuten opnieuw, met een nieuwe controle.
              voortgang.value = '';
              _herstart?.cancel();
              _herstart = Timer(const Duration(minutes: 5), () => unawaited(ronde()));
              return;
            }
            later = true;
            continue;
          }
          if (u.uitslag is Mislukt) {
            // Alleen bewaren als het bestand er nog precies zo staat: een bestand dat verhuisde of een
            // D: die wegviel is geen kapot bestand.
            try {
              final na = f.statSync();
              if (na.type != FileSystemEntityType.file ||
                  na.size != t.sizeBytes ||
                  na.modified.millisecondsSinceEpoch != t.addedMs) {
                continue;
              }
            } catch (_) {
              continue;
            }
            mislukt++;
            _log.line('kon niet meten: ${t.title} — ${(u.uitslag as Mislukt).reden}');
          } else {
            gemeten++;
            if (kern != null && _pcmVoor(kern) != null && u.erfbaar == null) {
              _log.line('md5 klopt niet: ${t.title} — ${t.path}');
            }
          }
          onthoudLuidheid(k, pad: t.path, uitslag: u.uitslag, erfbaar: u.erfbaar);
          if ((gemeten + mislukt) % 25 == 0) await bewaarLuidheid();
          if (_nu().difference(_laatstGepubliceerd) >= publiceerElke) {
            publiceerLuidheid(nummers: library.tracks, ffmpeg: true, kaartOok: !alleenStatus);
            _laatstGepubliceerd = _nu();
            _log.line(alleenStatus ? 'status gepubliceerd' : 'kaart gepubliceerd');
          }
          if (tussenpoos > Duration.zero) await Future<void>.delayed(tussenpoos);
        }
        if (eersteRonde && lijst.isNotEmpty && !_gestopt) {
          zetLuidheidKlaar();
          _log.line('eerste ronde klaar');
        }
        await bewaarLuidheid();
        publiceerLuidheid(nummers: library.tracks, ffmpeg: true, kaartOok: true);
        _laatstGepubliceerd = _nu();
        if (teMeten.isNotEmpty) {
          _log.line('klaar: $gemeten gemeten, $overgenomen overgenomen, $mislukt mislukt'
              '${_mediaan(lijst)} — kaart gepubliceerd');
        }
        voortgang.value = '';
      } while (_nogEens && !_gestopt);
    } finally {
      _bezig = false;
    }
    if (jongOvergeslagen && !_gestopt) {
      _herstart?.cancel();
      _herstart = Timer(leeftijd + const Duration(seconds: 1), () => unawaited(ronde()));
    } else if (later && !_gestopt) {
      // Een vergrendeld bestand: over tien minuten nog eens, niet pas bij de volgende wijziging.
      _herstart?.cancel();
      _herstart = Timer(const Duration(minutes: 10), () => unawaited(ronde()));
    }
  }

  String _mediaan(List<Track> lijst) {
    final waarden = <double>[];
    for (final t in lijst) {
      final b = bijstellingVoorNummer(t,
          rij: [t],
          plek: 0,
          opVolgorde: false,
          stand: Luidheidsstand.normaal,
          albumGeheel: false,
          albumVan: (_) => null);
      final m = b.meting;
      if (m != null) waarden.add(m.lufs);
    }
    if (waarden.isEmpty) return '';
    waarden.sort();
    return ', mediaan ${waarden[waarden.length ~/ 2].toStringAsFixed(1)} LUFS';
  }
}

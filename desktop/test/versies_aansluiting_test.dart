// Versies (Saber, 26-10-2026): aangesloten op elke weg — speler, offline, zones, speakers, server, opbergen, schermen.
import 'dart:io';

import 'package:debridmusic/lan/server.dart' show weigerVanBuiten;
import 'package:debridmusic/lan/state_store.dart' show PlaybackProgress;
import 'package:flutter_test/flutter_test.dart';

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  test('de speler opent wat er voor een nummer speelt, en een wissel geldt alleen voor dat nummer', () {
    final speler = _bron('lib/player.dart');
    expect(speler, contains('    final url = mediaResolver(_speelPad(path));'));
    expect(speler, contains('    final speel = _speelPad(t.path);\n    final vers = trackResolver?.call(speel)'),
        reason: 'gelijk volume met de meting van de versie');
    expect(speler, contains('    if (_versieGekozen?.anker != t.path) _versieGekozen = null;'));
    expect(speler, contains('static const kVersieOvervloei = Duration(milliseconds: 300);'));
    // Overvloeien even sterk (cos/sin), terug naar de eerste speler lineair (hetzelfde bestand).
    expect(speler, contains('_player.setVolume(volume * cos(x * pi / 2)),'));
    expect(speler, contains('proef.setVolume(volume * sin(x * pi / 2)),'));
    expect(speler, contains('await Future.wait([_player.setVolume(volume * x), proef.setVolume(volume * (1 - x))]);'));
  });

  test('main: de keuze, offline bewaren, de zones, uitlijnen en _dubbel', () {
    final main = _bron('lib/main.dart');
    expect(main, contains('    ..versieVoor = ((p) => offline.localFor(p) != null ? p : library.speelPadVoor(p))'),
        reason: 'onderweg zonder pc speelt de offline kopie');
    // Offline bewaren neemt de versie die speelt — sinds 27-10-2026 in cd-kwaliteit als je dat koos.
    expect(main, contains('        final pad = library.speelPadVoor(p);\n        final url = resolver(pad);'));
    expect(main, contains('  if (mode.owner) await versies.laad();'));
    expect(main, contains('  if (mode.owner) versies.uitgave.addListener(library.versiesVeranderd);'));
    expect(main, contains('      VersieUitlijnRonde(log: versieLog, wacht: const Duration(minutes: 2)).start();'));
    expect(main, contains('      Timer(const Duration(minutes: 10), () => unawaited(terug.ronde()));'));
    expect(main, contains('    await library.loadEerstGezien();'));
    // Een toestel als zone.
    expect(main, contains('      return await player.wisselVersie(v, lijst) ? null : \'Wisselen lukte niet\';'));
  });

  test('Nu speelt: vegen zonder stapel, lang drukken, de kwaliteitsregel, de pijlen op de tv', () {
    final main = _bron('lib/main.dart');
    expect(main, contains('    final hoesMetVersies = isTv || stapelAan || t == null || !metVersies'));
    expect(main, contains("            key: const ValueKey('np-hoes-versies'),"));
    expect(main, contains('    final hoesOfStapel = !stapelAan || t == null\n        ? hoesMetVersies'));
    expect(main, contains('          : (!isTv && t != null && metVersies ? () => unawaited(toonVersies(context, t)) : null),'));
    expect(main, contains('              for (final v in versiesNu) _versieRegel(context, ctx, anker, v, klinkt: v.track.path == t.path),'));
    expect(main, contains('        _versieNaast(nu, e.logicalKey == LogicalKeyboardKey.arrowUp ? 1 : -1) != null) {'),
        reason: 'voorbij de laatste versie doen de pijlen wat ze altijd deden');
    expect(main, contains("          MenuRegel(Icons.layers_rounded, 'Versies (\${vs.length}):"));
    expect(main, contains('                SliverToBoxAdapter(child: AlbumVersies(album: album)),'));
    expect(main, contains("              'Nieuwe versies',"));
  });

  test('de pc: speakers, zones, /api/versie (ook onderweg), en de catalogus', () {
    final server = _bron('lib/lan/server.dart');
    expect(server, contains('    cast.speelVersie = (id) {'));
    expect(server, contains("          case 'versie':\n            final vid = '\${op['versieId'] ?? ''}';"));
    expect(server, contains("      case '/api/versie':\n        return _versie(req);"));
    expect(weigerVanBuiten('/api/versie', 'POST'), isNull);
    final cast = _bron('lib/lan/cast_manager.dart');
    expect(cast, contains('    final id = anker == null ? null : _speelId(session, session.index, anker);'));
    expect(cast, contains('    final nextId = volgend == null ? null : _speelId(session, session.index + 1, volgend);'));
    expect(cast, contains('    final ids = [for (final id in trackIds) speelVersie?.call(id) ?? id];'));
    final zone = _bron('lib/zone_opdracht.dart');
    expect(zone, contains("        case 'versie':"));
    final catalog = _bron('lib/lan/catalog.dart');
    expect(catalog, contains('          versies: _versiesVan(t, root, trackById),'));
    expect(catalog, contains("      if (t.versies != null) fingerprint.add('V\${jsonEncode(t.versies)}');"));
    expect(catalog, contains('    versies.uitgave.addListener(_markDirty);'));
  });

  // Nagelopen op de pc (26-10-2026): de vinylrip van 24/192 speelde, de zonekaart zei "FLAC 16/44.1".
  test('de zonekaart toont de kwaliteit van de versie die klinkt', () {
    final p = PlaybackProgress.fromJson(PlaybackProgress(trackId: 'a', versie: 'v').toJson());
    expect(p.versie, 'v');
    expect(PlaybackProgress.fromJson(PlaybackProgress(trackId: 'a').toJson()).toJson().containsKey('versie'), isFalse);
    final zones = _bron('lib/lan/zones.dart');
    expect(zones, contains('    final b = bestandVan?.call(p.versie.isNotEmpty ? p.versie : p.trackId);'));
    expect(zones, contains('bestandVan?.call(versieOpSpeaker?.call(s.id) ?? s.trackId!);'));
    expect(_bron('lib/lan/server.dart'), contains('    zones.versieOpSpeaker = cast.versieVan;'));
    expect(_bron('lib/lan/state_store.dart'), contains("            versie: '\${op['versie'] ?? ''}',"));
    final main = _bron('lib/main.dart');
    expect(main, contains("              if (player.speelPad case final v? when v != track.path) 'versie': library.gedeeldId(v) ?? '',"));
    expect(main, contains("          versiePad: player.speelPad ?? '');"));
  });

  // Nagelopen op de pc (26-10-2026): na het terugzetten stond de cd op de plek van de vinylrip, evenveel nummers — en de
  // zone kreeg het oude nummer (24/192) terug.
  test('een nummer op id volgt elke scan, niet alleen een ander aantal', () {
    expect(_bron('lib/lan/sharing.dart'), contains('    if (_idsVoor != tracks.length || _idsRev != library.metaRev) {'));
    expect(_bron('lib/main.dart'), contains('    if (_idsVoor != tracks.length || _idsRev != library.metaRev) {'));
  });

  test('opbergen: elke weg kent versies, en een verhuizing neemt het register mee', () {
    final organize = _bron('lib/organize.dart');
    expect(organize, contains('    versies.herNoem(src.path, naar);'));
    expect(organize, contains('    versies.verhuisAnker(l.path, dest.path);'));
    expect(organize, contains('  versies.verhuisAnker(h, doel.path);'));
    final online = _bron('lib/online.dart');
    expect(online, contains('      final uit = await _bergOpAlsVersie(staged, plan, w.authority, bron, inJacht: inJacht);'));
    expect(online, contains("              final uitslag = await _bergOpAlsVersie(staged, plan, job.authority, 'Soulseek \${f.username}', inJacht: false);"));
    expect(online, contains('        (w.authority!.seconds! - lengte!).abs() <= kVinylLengteSpeling;'),
        reason: 'een vinylrip duurt vaak langer, maar alleen als versie');
    // Klaar om te kiezen: bewaren als versie, of bewaren en standaard maken.
    expect(_bron('lib/main.dart'), contains("          'bewaar' => await dm!.vervangDoorTwijfel(t.path, alsVersie: true),"));
    expect(online, contains('      return _bewaarTwijfelAlsVersie(pad, g, lijst,'));
    final library = _bron('lib/library.dart');
    expect(library, contains('          if (versies.isVersie(t.path)) {\n            _versieTracks[_padSleutel(t.path)] = t;'));
    expect(library, contains('    final t = _trackFromDtoMet(d, pad);\n    if (d.versies case final vs?) _versiesUitDto(t, vs);'));
    final veger = _bron('lib/luidheid_veger.dart');
    expect(veger, contains('final lijst = _volgorde(List<Track>.of(library.metVersies));'));
  });
}

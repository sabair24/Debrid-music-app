/// Wat de Sonos van een omgezet nummer te zien krijgt.
///
/// Deze toets bestaat omdat de reparatie van 08-08-2026 een release lang niets deed: het omzetten
/// naar een BESTAND liep stuk op de tijdelijke naam. ffmpeg kiest de container op de extensie, en
/// `….flac.tmp` kent hij niet — hij stopte met "Unable to choose an output format", schreef niets,
/// en de server viel terug op precies de pijp die de speaker stil houdt. Alles was groen, want er
/// werd nergens echt omgezet.
///
/// Daarom draait dit de ECHTE ffmpeg. Wat hier vastligt zijn de twee dingen waar de Sonos op afknapt
/// en die je alleen aan het bestand zelf kunt zien: is het werkelijk FLAC, en staat het aantal
/// samples in de kop. Nul samples is "onbekende lengte", en dat leest een Sonos als een eindeloze
/// radiostream — hij meldt PLAYING en rendert geen noot.
///
/// Zonder ffmpeg op de machine wordt er overgeslagen; op de bouwmachines staat hij niet.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/lan/transcode.dart';

/// De STREAMINFO van een FLAC-bestand, rechtstreeks uit de kop gelezen.
///
/// Met opzet zonder ffprobe: dat is een tweede programma dat er niet hoeft te zijn, en het gaat hier
/// juist om wat er in het BESTAND staat.
({String magie, int hz, int kanalen, int bits, int samples}) leesKop(File f) {
  final b = f.readAsBytesSync();
  final magie = String.fromCharCodes(b.sublist(0, 4));
  // Na "fLaC" komt een blokkop van 4 bytes; STREAMINFO begint dus op 8. Daarin: 2+2 blokgroottes,
  // 3+3 framegroottes, en dan op 18 het veld waar dit alles in zit.
  final p = 18;
  final hz = (b[p] << 12) | (b[p + 1] << 4) | (b[p + 2] >> 4);
  final kanalen = ((b[p + 2] >> 1) & 0x7) + 1;
  final bits = (((b[p + 2] & 0x1) << 4) | (b[p + 3] >> 4)) + 1;
  final samples = ((b[p + 3] & 0x0F) << 32) | (b[p + 4] << 24) | (b[p + 5] << 16) | (b[p + 6] << 8) | b[p + 7];
  return (magie: magie, hz: hz, kanalen: kanalen, bits: bits, samples: samples);
}

void main() {
  final ffmpeg = Transcoder().path;
  final geenFfmpeg = ffmpeg == null ? 'ffmpeg staat niet op deze machine' : null;

  late Directory tijdelijk;
  late File bron;

  setUpAll(() {
    if (ffmpeg == null) return;
    tijdelijk = Directory.systemTemp.createTempSync('dm_cast_');
    // Een echte 96 kHz-bron, gemaakt met hetzelfde ffmpeg — geen bestand uit de bibliotheek, want
    // een toets hoort niet van D: af te hangen.
    bron = File('${tijdelijk.path}${Platform.pathSeparator}bron.flac');
    final r = Process.runSync(ffmpeg, [
      '-hide_banner', '-loglevel', 'error', '-y',
      '-f', 'lavfi', '-i', 'sine=frequency=440:duration=2:sample_rate=96000',
      '-sample_fmt', 's32', '-c:a', 'flac', bron.path,
    ]);
    expect(r.exitCode, 0, reason: 'de bron voor de proef kon niet gemaakt worden: ${r.stderr}');
    expect(leesKop(bron).hz, 96000);
  });

  tearDownAll(() {
    if (ffmpeg == null) return;
    try {
      tijdelijk.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('96 kHz wordt een écht FLAC-bestand van 48 kHz', () async {
    final cache = Directory('${tijdelijk.path}${Platform.pathSeparator}cache');
    final uit = await Transcoder().resampleToFile(bron, maxSampleRate: 48000, cacheDir: cache);

    // Dit is de regressie zelf: vóór de reparatie kwam hier null uit en zweeg de speaker.
    expect(uit, isNotNull, reason: 'omzetten naar een bestand mislukte — dan valt de server terug op de pijp');
    expect(uit!.existsSync(), isTrue);
    expect(uit.lengthSync(), greaterThan(1024));

    final kop = leesKop(uit);
    expect(kop.magie, 'fLaC', reason: 'de doos moet FLAC zijn, niet wat de extensie toevallig suggereert');
    expect(kop.hz, 48000, reason: 'het plafond van de Sonos');
    expect(kop.samples, isNot(0),
        reason: 'nul = onbekende lengte, en dát is wat een Sonos als eindeloze radiostream leest');
    expect(kop.samples, closeTo(96000, 2000), reason: '2 seconden op 48 kHz');
  }, skip: geenFfmpeg);

  test('dezelfde bron en hetzelfde plafond wordt niet twee keer omgezet', () async {
    final cache = Directory('${tijdelijk.path}${Platform.pathSeparator}cache2');
    final eerste = await Transcoder().resampleToFile(bron, maxSampleRate: 48000, cacheDir: cache);
    expect(eerste, isNotNull);
    final stempel = eerste!.statSync().modified;

    final tweede = await Transcoder().resampleToFile(bron, maxSampleRate: 48000, cacheDir: cache);
    expect(tweede!.path, eerste.path);
    expect(tweede.statSync().modified, stempel, reason: 'de tweede keer hoort een opzoeking te zijn');
  }, skip: geenFfmpeg);

  test('er blijft geen half bestand achter', () async {
    final cache = Directory('${tijdelijk.path}${Platform.pathSeparator}cache3');
    await Transcoder().resampleToFile(bron, maxSampleRate: 48000, cacheDir: cache);
    final losseEindjes = cache.listSync().where((f) => f.path.endsWith('.tmp')).toList();
    expect(losseEindjes, isEmpty, reason: 'de .tmp hoort hernoemd te zijn, niet blijven liggen');
  }, skip: geenFfmpeg);
}

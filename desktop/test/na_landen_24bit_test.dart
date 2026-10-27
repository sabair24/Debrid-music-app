// "24bit" na het landen (Saber, 24-10-2026: "Na het landen"). Als eigen zoekopdracht kost "24bit" ±8 s, en
// meegestuurd met de gewone vraag leverde het bijna niets op (gemeten: 9 tegen 112 bestanden met 24bit, Phil
// Collins). Dus: ▶ en downloaden blijven even snel, en na het landen in 16 bit of minder zoekt de app op de
// achtergrond "<artiest> <titel> 24bit" — voor een album één keer — zonder terugval naar de artiest, en zonder TIDAL.
import 'dart:io';

import 'package:debridmusic/models.dart';
import 'package:debridmusic/online.dart';
import 'package:debridmusic/settings.dart';
import 'package:debridmusic/soulseek.dart';
import 'package:flutter_test/flutter_test.dart';

class _Zoeker extends SoulseekService {
  _Zoeker() : super(AppSettings());
  final vragen = <({String q, List<String> extra, bool terugval})>[];

  @override
  bool get available => true;

  @override
  Future<List<SoulseekFile>> search(String query,
      {void Function(List<SoulseekFile>)? onPartial,
      void Function(String)? gebruikteVraag,
      bool achtergrond = false,
      List<String> extra = const [],
      bool terugval = true,
      bool Function()? nogNodig,
      Zoekrem? eigenRem}) async {
    vragen.add((q: query, extra: extra, terugval: terugval));
    return const [];
  }
}

Track _t(String titel, {String album = 'Discovery'}) => Track(
    path: '${Directory.systemTemp.path}${Platform.pathSeparator}nl24 - $titel.flac',
    title: titel,
    artist: 'Daft Punk',
    album: album,
    duration: const Duration(seconds: 298),
    isFlac: true,
    bitsPerSample: 16,
    sampleRate: 44100);

String _bron(String pad) => File(pad).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  late _Zoeker zoeker;
  late DownloadManager d;
  var tidal = 0;
  setUp(() {
    zoeker = _Zoeker();
    tidal = 0;
    d = DownloadManager(OnlineService(AppSettings()), zoeker, Directory.systemTemp.path, () async {})
      ..tidalNu = (l) {
        tidal++;
        return {for (final t in l) t.path};
      };
  });

  test('na het landen: alleen "… 24bit", zonder terugval, en niet bij TIDAL', () async {
    await d.zoekBeterVoor([_t('Digital Love')], alleenHires: true);
    expect(zoeker.vragen, hasLength(1));
    expect(zoeker.vragen.single.q, allOf(contains('Digital Love'), endsWith(' 24bit')));
    expect(zoeker.vragen.single.terugval, isFalse, reason: 'niets met 24bit is niet "zoek dan de artiest"');
    expect(zoeker.vragen.single.extra, isEmpty);
    expect(tidal, 0, reason: 'de TIDAL-ronde komt er zelf langs');
  });

  test('een album: één zoekopdracht "<artiest> <album> 24bit" voor alle nummers', () async {
    await d.zoekBeterVoor([_t('Digital Love'), _t('One More Time')], album: 'Discovery', alleenHires: true);
    expect(zoeker.vragen, hasLength(1));
    expect(zoeker.vragen.single.q, allOf(contains('Discovery'), endsWith(' 24bit')));
  });

  test('"Zoek hi-res" zelf: de gewone vraag met 24bit als eigen zoekopdracht erachter, en TIDAL', () async {
    await d.zoekBeterVoor([_t('Digital Love')]);
    expect(zoeker.vragen.single.q, isNot(endsWith('24bit')));
    expect(zoeker.vragen.single.extra, ['24bit']);
    expect(zoeker.vragen.single.terugval, isTrue);
    expect(tidal, 1);
  });

  test('bedrading: na een download en na ▶, niet bij hi-res en niet bij jouw eigen keuze', () {
    final o = _bron('lib/online.dart');
    expect(o, contains('if (ok) _naLandenHires(padVanWatErLigt, job.authority, from);'), reason: 'na een download');
    final fin = o.substring(o.indexOf('    Future<bool> finish(SlskDone res, SoulseekFile from) async {'));
    expect(fin.indexOf('if (vast) return ok;'), lessThan(fin.indexOf('_naLandenHires(')),
        reason: 'een vaste keuze komt er niet langs');
    expect(o, contains('    _naLandenHires(pad, plaatsing, gekozen);'), reason: 'na ▶');
    expect(o, contains('if ((van.bitDepth ?? 0) > 16 || (van.sampleRate ?? 0) > 48000) return;'),
        reason: 'wat al hi-res is, hoeft niet');
    expect(o, contains('final rondes = terugval && !stil ? alle : alle.take(1).toList();'));
    final m = _bron('lib/main.dart');
    expect(m, contains('..trackVoorPad = library.trackByPath'));
    expect(m, contains('..gezagVoor = library.tagsVoorVervanger;'));
    expect(DownloadManager.kNaLandenAdem, const Duration(seconds: 90));
  });
}

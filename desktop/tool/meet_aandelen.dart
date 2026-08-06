// Voor elk proefnummer: wat biedt het NETWERK aan, per sample rate?
//
// De waarheid staat ernaast. `echt` betekent dat de spectrumproef inhoud boven 22 kHz vond in het
// eigen bestand -- dan BESTAAT die uitgave, en mag de regel hem nooit wegzetten. Dat is de enige
// harde kant; "nep" zegt alleen dat de eigen kopie opgeschaald is, niet dat er niets echts bestaat.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final tok = args[0], basis = args[1];
  final werk = (jsonDecode(File(args[2]).readAsStringSync()) as List).cast<Map<String, dynamic>>();
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  final uit = <Map<String, dynamic>>[];

  for (final w in werk) {
    final q = '${w['artiest']} ${w['titel']}';
    List files = const [];
    try {
      final req = await http.getUrl(Uri.parse('$basis/api/soulseek/search?q=${Uri.encodeQueryComponent(q)}'));
      req.headers.set('Authorization', 'Bearer $tok');
      final res = await req.close().timeout(const Duration(seconds: 180));
      final body = await res.transform(utf8.decoder).join();
      files = (jsonDecode(body)['files'] as List? ?? const []);
    } catch (e) {
      stdout.writeln('${w['groep'].toString().padRight(4)} $q -> zoeken mislukt ($e)');
      continue;
    }
    final perRate = <int, int>{};
    for (final f in files.cast<Map<String, dynamic>>()) {
      final naam = (f['filename'] as String).toLowerCase();
      if (!naam.endsWith('.flac') && !naam.endsWith('.wav') && !naam.endsWith('.aiff')) continue;
      final sr = f['sampleRate'] as int? ?? 0;
      if (sr < 44100) continue;
      perRate.update(sr, (v) => v + 1, ifAbsent: () => 1);
    }
    final r441 = perRate[44100] ?? 0;
    final r48 = perRate[48000] ?? 0;
    final boven48 = perRate.entries.where((e) => e.key > 48000).fold(0, (s, e) => s + e.value);
    uit.add({...w, 'rates': perRate.map((k, v) => MapEntry('$k', v)), 'r441': r441, 'r48': r48, 'boven48': boven48});
    final cd = r441 + r48;
    stdout.writeln('${w['groep'].toString().padRight(4)} ${q.padRight(46)} '
        '44,1=${r441.toString().padLeft(4)} 48=${r48.toString().padLeft(3)} >48=${boven48.toString().padLeft(4)}  '
        'aandeel>48 ${cd == 0 ? "-" : (boven48 / cd).toStringAsFixed(3)}  '
        'aandeel48 ${r441 == 0 ? "-" : (r48 / r441).toStringAsFixed(3)}');
    await Future<void>.delayed(const Duration(seconds: 3));
  }
  File(args[3]).writeAsStringSync(jsonEncode(uit));
  http.close();
}

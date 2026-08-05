// Wat antwoordt de Soulseek-server op ONZE loginbytes, en op de variant van vóór 3.9.46?
//
// Buiten de app om, zodat dit te weten is zonder aan DebridMusic te sleutelen. Eén poging per aanroep,
// want een burst is precies wat een account blokkeert.
//
// Aanleiding, 05-08-2026: de officiële SoulseekQt logt op ditzelfde moment gewoon in als `leedagair`,
// terwijl DebridMusic met dezelfde gegevens `INVALIDPASS` terugkrijgt. Er is dan niets bezet — het
// verschil moet in de bytes zitten.
//
// Gebruik:  dart run tool/slsk_probe.dart <variant>
//   hash-user-pass   md5(gebruikersnaam + wachtwoord)   <- wat de app nu stuurt
//   hash-pass        md5(wachtwoord)                    <- wat de app vóór 3.9.46 stuurde
//
// Het wachtwoord wordt uit settings.json gelezen en NOOIT afgedrukt.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class W {
  final _b = BytesBuilder();
  void u32(int v) => _b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  void str(String s) {
    final x = utf8.encode(s);
    u32(x.length);
    _b.add(x);
  }

  Uint8List bytes() => _b.takeBytes();
}

Uint8List message(int code, Uint8List payload) {
  final head = (W()
        ..u32(payload.length + 4)
        ..u32(code))
      .bytes();
  return Uint8List.fromList([...head, ...payload]);
}

int rdU32(Uint8List b, int i) => b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24);

Future<void> main(List<String> args) async {
  final variant = args.isEmpty ? 'hash-user-pass' : args.first;

  final settings = File('${Platform.environment['APPDATA']}\\DebridMusic\\settings.json');
  final j = jsonDecode(await settings.readAsString()) as Map<String, dynamic>;
  final user = (j['soulseek_user'] ?? '').toString();
  final pass = (j['soulseek_pass'] ?? '').toString();
  if (user.isEmpty || pass.isEmpty) {
    stdout.writeln('geen gegevens in settings.json');
    return;
  }
  final hash = variant == 'hash-pass'
      ? md5.convert(utf8.encode(pass)).toString()
      : md5.convert(utf8.encode('$user$pass')).toString();

  stdout.writeln('variant   : $variant');
  stdout.writeln('gebruiker : $user  (wachtwoord ${pass.length} tekens, niet getoond)');

  // Het enige wat de app wél doet en deze proef niet: eerst de luisterpoort binden.
  ServerSocket? luister;
  if (variant == 'met-poort') {
    try {
      luister = await ServerSocket.bind(InternetAddress.anyIPv4, 10422);
      stdout.writeln('gebonden  : poort ${luister.port}');
    } catch (e) {
      stdout.writeln('gebonden  : MISLUKT ($e)');
    }
  }

  final s = await Socket.connect('server.slsknet.org', 2242, timeout: const Duration(seconds: 10));
  stdout.writeln('verbonden met ${s.remoteAddress.address}:${s.remotePort}');

  final buf = BytesBuilder();
  final klaar = Completer<void>();
  s.listen((d) {
    buf.add(d);
    final b = buf.toBytes();
    if (b.length < 13) return;
    final len = rdU32(b, 0);
    if (b.length < 4 + len) return;
    final code = rdU32(b, 4);
    if (code != 1) return;
    final ok = b[8] != 0;
    final rlen = rdU32(b, 9);
    final reason = utf8.decode(b.sublist(13, 13 + rlen), allowMalformed: true);
    stdout.writeln(ok ? 'ANTWOORD  : GELUKT — "$reason"' : 'ANTWOORD  : GEWEIGERD — "$reason"');
    if (!klaar.isCompleted) klaar.complete();
  }, onDone: () {
    if (!klaar.isCompleted) klaar.complete();
  }, onError: (e) {
    stdout.writeln('fout: $e');
    if (!klaar.isCompleted) klaar.complete();
  });

  final bericht = message(1, (W()..str(user)..str(pass)..u32(160)..str(hash)..u32(17)).bytes());
  // De bytes zelf, zodat ze naast die van de app te leggen zijn. Het wachtwoord zit erin, dus alleen
  // een vingerafdruk en de lengte — nooit de inhoud.
  stdout.writeln('bericht   : ${bericht.length} bytes, sha1 '
      '${sha1.convert(bericht).toString().substring(0, 24)}');
  s.add(bericht);
  await klaar.future.timeout(const Duration(seconds: 15), onTimeout: () {
    stdout.writeln('ANTWOORD  : GEEN — de server zweeg 15 seconden');
  });
  // Netjes dicht, zodat de sessie niet blijft hangen voor de volgende proef.
  await s.close();
  s.destroy();
  await luister?.close();
}

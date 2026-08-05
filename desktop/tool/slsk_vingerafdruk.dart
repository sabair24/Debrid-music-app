// Welke variant van het loginbericht levert de vingerafdruk op die de app logde?
//
// De app stuurde 81 bytes met sha1 c4c08f6f...; deze proef stuurt er 82 met sha1 00a48bd6... en wordt
// wél geaccepteerd. Eén byte verschil betekent dat één veld één teken korter is. Dit programma rekent
// de kandidaten door met exact dezelfde schrijver als de app, zodat er niets te raden valt.
//
// Het wachtwoord wordt gelezen uit settings.json en NOOIT afgedrukt.
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

Uint8List bericht(String user, String pass, String hash) {
  final payload = (W()..str(user)..str(pass)..u32(160)..str(hash)..u32(17)).bytes();
  final head = (W()
        ..u32(payload.length + 4)
        ..u32(1))
      .bytes();
  return Uint8List.fromList([...head, ...payload]);
}

String md5hex(String s) => md5.convert(utf8.encode(s)).toString();
String kort(Uint8List b) => sha1.convert(b).toString().substring(0, 24);

Future<void> main() async {
  final f = File('${Platform.environment['APPDATA']}\\DebridMusic\\settings.json');
  final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
  final u = (j['soulseek_user'] ?? '').toString();
  final p = (j['soulseek_pass'] ?? '').toString();

  final kandidaten = <String, Uint8List>{
    'volledig (mijn proef)': bericht(u, p, md5hex('$u$p')),
    'hash = md5(wachtwoord)': bericht(u, p, md5hex(p)),
    'wachtwoord mist LAATSTE teken': bericht(u, p.substring(0, p.length - 1), md5hex('$u${p.substring(0, p.length - 1)}')),
    'wachtwoord mist EERSTE teken': bericht(u, p.substring(1), md5hex('$u${p.substring(1)}')),
    'gebruiker mist laatste teken':
        bericht(u.substring(0, u.length - 1), p, md5hex('${u.substring(0, u.length - 1)}$p')),
    'hash 31 tekens (geen padding)': bericht(u, p, md5hex('$u$p').substring(1)),
  };

  for (final e in kandidaten.entries) {
    stdout.writeln('${e.key.padRight(32)} ${e.value.length.toString().padLeft(3)} bytes  sha1 ${kort(e.value)}');
  }
  stdout.writeln('');
  stdout.writeln('${'DE APP STUURDE'.padRight(32)}  81 bytes  sha1 c4c08f6fd8b9cbc0e0bd8153');
}

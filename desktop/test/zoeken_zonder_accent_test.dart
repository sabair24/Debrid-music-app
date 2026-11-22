/// Zoeken op Soulseek hangt niet af van accenten in je tags (Saber, 22-11-2026: *"in soulseek veelal, de accenten niet
/// gebruikt worden of teveel, dus dit mag geen impact hebben op resultaten"*). Aanleiding: "Claude deelt in" zet een naam
/// zonder accent recht naar die mét ("Hélène Segara" → "Hélène Ségara"), en Soulseek telt "ségara" en "segara" als
/// verschillende woorden. Elke ronde stuurt daarom bij een vraag met accenten ook dezelfde vraag zonder.
library;

import 'dart:io';

import 'package:debridmusic/organize.dart' show fileWords, zonderAccentenVoorZoeken;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DE KERN: klein en zonder accenten — ook wat de app zelf bouwt en wat iemand typt', () {
    expect(zonderAccentenVoorZoeken('Hélène Ségara Voici'), 'helene segara voici');
    expect(zonderAccentenVoorZoeken('france gall débranche'), 'france gall debranche');
    expect(zonderAccentenVoorZoeken('Âme Rej'), 'ame rej');
    expect(zonderAccentenVoorZoeken('Beyoncé Halo'), 'beyonce halo');
    expect(zonderAccentenVoorZoeken('Bjørk Jóga'), 'bjork joga');
  });

  test('niets te vouwen: geen tweede vraag', () {
    expect(zonderAccentenVoorZoeken('sting fields of gold'), isNull);
    expect(zonderAccentenVoorZoeken('Sting Fields Of Gold'), isNull, reason: 'alleen hoofdletters: Soulseek kijkt er niet naar');
    expect(zonderAccentenVoorZoeken('Поп'), isNull, reason: 'cyrillisch heeft geen gewone vorm');
  });

  test('het vergelijken achteraf vouwt al: beide vormen passen op hetzelfde bestand', () {
    expect(fileWords('Hélène Ségara - Il y a trop de gens qui t\'aiment.flac'),
        fileWords('Helene Segara - Il y a trop de gens qui t\'aiment.flac'));
  });

  test('aangesloten: elke ronde, naast de jokervorm, bij de eerste vraag — en niet bij een telling', () {
    final o = File('lib/online.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(o, contains('      final eerste = variants.isEmpty;\n'
        "      if (!telling && variants.isEmpty && jokerHelpt(q)) variants.add('*\${q.substring(1)}');\n"
        '      variants.add(q);'));
    expect(o, contains('      if (!telling && eerste) {\n'
        '        final gevouwen = zonderAccentenVoorZoeken(q);\n'
        '        if (gevouwen != null) variants.add(gevouwen);\n'
        '      }'));
  });
}

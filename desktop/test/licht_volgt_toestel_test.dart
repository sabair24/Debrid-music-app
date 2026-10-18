// De glans op gsm en iPad volgt de kanteling van het toestel, en de vlekken van de hoes liggen achter
// Nu speelt (Saber, 18-10-2026).
import 'dart:async';
import 'dart:io';

import 'package:debridmusic/ui/glas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(GlasLicht.vergeet);

  testWidgets('stil vasthouden verplaatst het licht niet; kantelen wel', (t) async {
    final melder = StreamController<Offset>.broadcast();
    GlasLicht.volgToestel(melder: () => melder.stream);
    final gezien = <Offset?>[];
    void kijk() => gezien.add(GlasLicht.bron.value);
    GlasLicht.bron.addListener(kijk);
    addTearDown(() => GlasLicht.bron.removeListener(kijk));

    // Schuin in de hand, met een beetje trilling.
    for (var i = 0; i < 20; i++) {
      melder.add(Offset(i.isEven ? .002 : -.002, .5));
      await t.pump(const Duration(milliseconds: 16));
    }
    final naRust = gezien.length;
    expect(naRust, lessThanOrEqualTo(1), reason: 'hooguit de eerste plek; trillen tekent niets');

    // Een flinke kanteling naar links.
    melder.add(const Offset(.12, .5));
    await t.pump();
    expect(gezien.length, greaterThan(naRust));
    final links = GlasLicht.bron.value!;
    final views = t.binding.platformDispatcher.views.first;
    final breedte = views.physicalSize.width / views.devicePixelRatio;
    expect(links.dx, lessThan(breedte / 2), reason: 'links kantelen: het licht schuift naar links');
  });

  testWidgets('in de achtergrond luistert er niets', (t) async {
    final melder = StreamController<Offset>.broadcast();
    GlasLicht.volgToestel(melder: () => melder.stream);
    expect(melder.hasListener, isTrue);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(melder.hasListener, isFalse);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(melder.hasListener, isTrue);
    GlasLicht.vergeet();
    expect(melder.hasListener, isFalse);
  });

  test('aangesloten: gsm en iPad volgen het toestel, de vlekken liggen achter Nu speelt', () {
    final bron = File('lib/main.dart').readAsStringSync();
    expect(bron, contains('} else if (Platform.isAndroid || Platform.isIOS) {'));
    expect(bron, contains('GlasLicht.volgToestel();'));
    expect(bron, contains('Positioned.fill(child: HoesVlekkenLaag(p.hoesVlekken, sterkte: kNuSpeeltVlekken)),'));
  });
}

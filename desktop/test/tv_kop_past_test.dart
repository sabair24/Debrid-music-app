/// De kop van de artiestpagina past op een tv in één scherm, ook bij een naam van twee regels.
///
/// Saber, 16-10-2026: "alles in één scherm" — foto, naam, genre, Ook in en Radio boven de spelerbalk.
/// Op de Shield (17-10-2026) stond Radio bij Michael Jackson bij het openen half onder de spelerbalk:
/// "MICHAEL / JACKSON" op twee regels, met "Michael Joseph Jackson" eronder en drie feitenrijen.
///
/// Met de echte letters (Inter) en de tekstschaal van een tv (1,35): in een toets zijn alle letters
/// anders even breed als hoog, en dan wrapt de feitenstrook anders dan op het toestel.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/main.dart';
import 'package:debridmusic/tv.dart';
import 'package:debridmusic/ui/kleuren.dart';
import 'package:debridmusic/ui/vlak.dart';

/// Waar de spelerbalk op een tv begint: 540 min 105 (zie `kTvKopZicht`), min 12 punten lucht: de
/// selectiegloed van Radio steekt buiten de knop uit, en op 3 punten raakte hij de balk.
const double kSpelerbalkBoven = 540 - 105 - 12;

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(Future.value(ByteData.sublistView(File('fonts/Inter-$w.ttf').readAsBytesSync())));
    }
    await inter.load();
  });

  setUp(() => setTvModeForTest(true));
  tearDown(() => setTvModeForTest(false));

  Future<double> radioOnder(WidgetTester t, {required String naam, String? echteNaam, List<String> groepen = const []}) async {
    t.view.physicalSize = const Size(960, 540);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Inter'),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(960, 540), textScaler: TextScaler.linear(1.35)),
        child: Material(
          color: kAchtergrond,
          child: Align(
            alignment: Alignment.topLeft,
            child: EditorialeKop(
              naam: naam,
              echteNaam: echteNaam,
              bibliotheek: '8 albums · 75 nummers · 6u 10m',
              genres: const ['Pop', 'Rock', 'Funk / Soul'],
              groepen: groepen,
              // Zoals op de pagina: het stuk achter de zwevende balk.
              bovenBloed: TvTopBar.hoogte + tvOverscan.top,
              actions: [
                GlasKnop(key: const ValueKey('radio'), icoon: Icons.radio_rounded, label: 'Radio', onPressed: () {}),
              ],
            ),
          ),
        ),
      ),
    ));
    await t.pump();
    final r = t.getRect(find.byKey(const ValueKey('radio')));
    return r.bottom;
  }

  testWidgets('Michael Jackson: naam op twee regels, echte naam, drie groepen — Radio boven de spelerbalk',
      (t) async {
    final onder = await radioOnder(t,
        naam: 'Michael Jackson',
        echteNaam: 'Michael Joseph Jackson',
        groepen: const ['The Jackson 5', 'USA For Africa', 'The Jacksons']);
    expect(onder, lessThanOrEqualTo(kSpelerbalkBoven),
        reason: 'Radio eindigt op ${onder.round()}, de spelerbalk begint op ${kSpelerbalkBoven.round()}');
    expect(find.text('Michael Joseph Jackson'), findsOneWidget, reason: 'de echte naam blijft, op de regel bovenaan');
  });

  testWidgets('*NSYNC met vijf leden past ook', (t) async {
    final onder = await radioOnder(t,
        naam: '*NSYNC', groepen: const ['Justin Timberlake', 'JC Chasez', 'Chris Kirkpatrick', 'Joey Fatone']);
    expect(onder, lessThanOrEqualTo(kSpelerbalkBoven));
  });
}

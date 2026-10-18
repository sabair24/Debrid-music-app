/// De mediatoetsen en de knoppen in de taakbalk op Windows (Saber, 17-10-2026: "mijn media toetsen op
/// men toetsenbord moeten er op werken, ik heb een logitech G213 toetsenbord").
///
/// De runner (C++) is hier niet te draaien; wat hier vastligt is wat een knop doet, en dat de draad
/// van Windows tot in Dart aangesloten is. De Windows-bouw compileert de C++.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:debridmusic/mediabediening.dart';

void main() {
  group('wat een knop doet', () {
    test('afspelen en pauze zijn opdrachten, geen schakelaar', () {
      expect(mediaKnopActie('afspelen', speelt: false), MediaActie.speelPauze);
      expect(mediaKnopActie('afspelen', speelt: true), isNull, reason: 'speelt al: niets doen');
      expect(mediaKnopActie('pauze', speelt: true), MediaActie.speelPauze);
      expect(mediaKnopActie('pauze', speelt: false), isNull, reason: 'staat al stil');
    });

    test('stop pauzeert, en de knop in de taakbalk wisselt', () {
      expect(mediaKnopActie('stop', speelt: true), MediaActie.speelPauze);
      expect(mediaKnopActie('stop', speelt: false), isNull);
      expect(mediaKnopActie('speelpauze', speelt: true), MediaActie.speelPauze);
      expect(mediaKnopActie('speelpauze', speelt: false), MediaActie.speelPauze);
    });

    test('vorige, volgende, en iets onbekends', () {
      expect(mediaKnopActie('volgende', speelt: true), MediaActie.volgende);
      expect(mediaKnopActie('vorige', speelt: false), MediaActie.vorige);
      expect(mediaKnopActie('snelvooruit', speelt: true), isNull);
      expect(mediaKnopActie(null, speelt: true), isNull);
    });
  });

  group('aangesloten', () {
    final runner = File('windows/runner/mediabediening.cpp').readAsStringSync();
    final venster = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();
    final hoofd = File('lib/main.dart').readAsStringSync();

    test('de runner meldt zich bij de mediabediening van Windows en zet drie knoppen in de taakbalk', () {
      expect(runner, contains('GetForWindow(venster'));
      expect(runner, contains('add_ButtonPressed('));
      expect(runner, contains('ThumbBarAddButtons(venster, 3, knoppen)'));
      expect(runner, contains('RegisterWindowMessageW(L"TaskbarButtonCreated")'));
      // Windows meldt een knop op een eigen draad; het kanaal mag alleen op de vensterdraad.
      expect(runner, contains('PostMessageW(doel, kMediaKnopBericht'));
      expect(runner, contains('"debridmusic/mediabediening"'));
    });

    test('het venster maakt hem en geeft hem zijn berichten vóór Flutter', () {
      expect(venster, contains('media_ = std::make_unique<Mediabediening>(GetHandle()'));
      final bericht = venster.indexOf('media_->Bericht(message, wparam, lparam)');
      final flutter = venster.indexOf('HandleTopLevelWindowProc(hwnd, message, wparam');
      expect(bericht, greaterThan(-1));
      expect(bericht, lessThan(flutter), reason: 'Flutter zou de klik in de taakbalk anders kunnen opeten');
      // En weg vóór de controller: hij praat over een kanaal met de engine.
      expect(venster.indexOf('media_ = nullptr;'), lessThan(venster.indexOf('flutter_controller_ = nullptr;')));
    });

    test('de opruimvlag staat bij het maken weer op nee', () {
      // `Win32Window::Create` roept eerst `Destroy()` en dus OnDestroy aan. Zonder deze regel stond
      // `tearing_down_` vanaf het begin op ja en kwam er geen bericht meer bij de mediabediening of de
      // plug-ins (17-10-2026, met een debugger op de proef gezien).
      final win32 = File('windows/runner/win32_window.cpp').readAsStringSync();
      expect(win32, contains('const Size& size) {\n  Destroy();'),
          reason: 'als Create niet meer met Destroy begint, mag deze toets mee veranderen');
      final maken = venster.indexOf('bool FlutterWindow::OnCreate() {');
      // Een hele regel, zodat een uitgecommentarieerde versie niet meetelt.
      final terug = venster.indexOf('\n  tearing_down_ = false;\n', maken);
      expect(terug, greaterThan(maken));
      expect(terug, lessThan(venster.indexOf('flutter_controller_ = std::make_unique', maken)));
    });

    test('de bouw kent het bestand en de bibliotheken', () {
      expect(cmake, contains('"mediabediening.cpp"'));
      expect(cmake, contains('"runtimeobject.lib" "shlwapi.lib" "shcore.lib"'));
    });

    test('de app start hem bij het opstarten', () {
      expect(hoofd, contains('Mediabediening.start(speler: player, speaker: speakers, meld: startLog.line);'),
          reason: 'en wat er binnenkomt staat in start.log');
    });
  });
}

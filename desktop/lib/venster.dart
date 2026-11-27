// Het venster op pc en Mac, via window_manager (15-11-2026).
//
// Vanaf window_manager 0.6 draait het pakket op een nieuwe kern (nativeapi), en de API van 0.5 staat in
// `package:window_manager/legacy.dart`, verouderd verklaard. Die oude API is precies wat de app gebruikt:
// tonen bij het opstarten, netjes afsluiten (setPreventClose + onWindowClose), maximaliseren en de eigen
// vensterknoppen. Omzetten naar de nieuwe API raakt de vensterprocedure waar de runner zelf de titelbalk
// verbergt en de crash bij afsluiten opvangt (windows/runner/flutter_window.cpp) — dat is een eigen klus.
//
// Hier, en alleen hier, staan de verouderde namen; main.dart gebruikt [venster], [VensterLuisteraar] en
// [VensterOpties], zodat de analyse elders schoon blijft.
// ignore_for_file: deprecated_member_use
library;

import 'package:flutter/widgets.dart' show Size;
import 'package:window_manager/legacy.dart';

export 'package:window_manager/legacy.dart' show TitleBarStyle;
export 'package:window_manager/window_manager.dart' show DragToMoveArea;

/// Het venster van de app (de oude `windowManager`).
final venster = windowManager;

/// Een venster dat geen beeld meer tekent even van maat laten veranderen, zodat de tekenaar een nieuw vlak krijgt
/// (warmtemeter.dart, `losmaken`; pc 27-11-2026: 40 minuten hetzelfde beeld terwijl de app doorliep). Een groot
/// venster gaat even klein en weer groot, een ander venster 1 pixel breder en terug. Zegt wat het deed.
Future<String> vensterLosmaken() async {
  if (await venster.isFullScreen()) {
    await venster.setFullScreen(false);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await venster.setFullScreen(true);
    return 'volledig scherm even uit en weer aan';
  }
  if (await venster.isMaximized()) {
    await venster.unmaximize();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await venster.maximize();
    return 'groot venster even klein en weer groot';
  }
  final s = await venster.getSize();
  await venster.setSize(Size(s.width + 1, s.height));
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await venster.setSize(s);
  return 'venster 1 px breder en terug (${s.width.round()}×${s.height.round()})';
}

/// Wie wil horen wat het venster doet (de oude `WindowListener`).
typedef VensterLuisteraar = WindowListener;

/// Hoe het venster opent (de oude `WindowOptions`).
typedef VensterOpties = WindowOptions;

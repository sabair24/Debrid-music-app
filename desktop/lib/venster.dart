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

import 'package:window_manager/legacy.dart';

export 'package:window_manager/legacy.dart' show TitleBarStyle;
export 'package:window_manager/window_manager.dart' show DragToMoveArea;

/// Het venster van de app (de oude `windowManager`).
final venster = windowManager;

/// Wie wil horen wat het venster doet (de oude `WindowListener`).
typedef VensterLuisteraar = WindowListener;

/// Hoe het venster opent (de oude `WindowOptions`).
typedef VensterOpties = WindowOptions;

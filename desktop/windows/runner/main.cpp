#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Wie startte ons, en met welke vensterstand. Een gewone start komt van Verkenner, een start na
  // het bijwerken van de installer; dat verschil was op 04-10-2026 het enige wat vaststond toen het
  // venster na een update klein opende. De opstartinfo bepaalt wat de EERSTE ShowWindow werkelijk
  // doet, ongeacht wat er gevraagd wordt -- vandaar dat die hier staat. Zie StartLogRegel in utils.h.
  {
    STARTUPINFOW opstart = {};
    ::GetStartupInfoW(&opstart);
    const std::string ouder = OuderProces();
    StartLogRegel(
        "runner: proces %lu gestart door %s, nCmdShow=%d, opstartinfo dwFlags=0x%lX "
        "wShowWindow=%u",
        ::GetCurrentProcessId(), ouder.empty() ? "?" : ouder.c_str(), show_command,
        opstart.dwFlags, static_cast<unsigned>(opstart.wShowWindow));
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  // Skia, niet Impeller (18-10-2026). Flutter 3.47 zette Windows standaard op Impeller, en daarmee
  // kostte Nu speelt openen of sluiten op Sabers pc een paar seconden lang 15 tot 20 GB werkgeheugen
  // en 6 tot 9 GB videogeheugen, met 65 tot 123 ms per beeld: "heel stroef". Gemeten met dezelfde
  // proef op vier bouwen: 3.9.504 (Flutter 3.41, Skia) bleef op 1,2 GB en 2,3 ms per beeld, en de
  // bouw met alleen de overstap naar 3.47 (b317fc2) had het al. In rust ook vijf keer zoveel
  // videogeheugen (0,9 tegen 0,2 GB). Het vloeibare glas (de lensrand is een shader als filter)
  // vraagt Impeller; zonder valt de pc terug op matglas, zoals in 3.9.504 (lib/ui/glas.dart).
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"debridmusic", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // ELKE keer dat deze app afsloot kwam er een crashdump van 38 MB. Gemeten, niet vermoed.
  //
  // Tien dumps in twee dagen (samen 387 MB in AppData\Local\CrashDumps), en alle tien met dezelfde
  // handtekening: `coremessaging.dll+0x16cf4`, leesfout 0xC0000005. De stapel van de crashende
  // draad is elke keer dezelfde en bestaat volledig uit `coremessaging` + `dcomp` + `ntdll` — een
  // CoreMessaging-werkdraad van DirectComposition, niet de hoofddraad. Die valt om zodra de
  // compositie onder hem uit wordt getrokken terwijl hij nog een bericht aan het bezorgen is.
  //
  // Dit is een ANDERE crash dan die van 19-08 (WM_PARENTNOTIFY naar een stervende controller, zie
  // `flutter_window.cpp`); die zat in de vensterprocedure en is met `tearing_down_` opgelost.
  //
  // Op dit punt is alles wat de app te bewaren had al gebeurd: `_NetjesAfsluiten` heeft zijn
  // opslag geleegd, zich bij Soulseek afgemeld en het browservenster opgeruimd, daarna is via
  // `windowManager.destroy()` het venster vernietigd, is `flutter_controller_` weggegooid en is de
  // Dart-isolate gestopt. De berichtenlus is leeg. Wat hierna nog gebeurt is uitsluitend het
  // afbreken van DLL's — en dáár zit de leesfout. Een proces dat toch verdwijnt hoeft dat niet
  // netjes te doen.
  //
  // `TerminateProcess` en niet `exit()`: dat laatste draait de atexit-haken en DLL_PROCESS_DETACH
  // alsnog af, en dat is precies het stuk dat omvalt. Bewust VOOR `CoUninitialize`, want die haalt
  // zelf de COM-objecten weg waar die werkdraad nog in zit — hij is onderdeel van het afbreken,
  // geen bescherming ertegen.
  ::TerminateProcess(::GetCurrentProcess(), 0);

  ::CoUninitialize();
  return EXIT_SUCCESS;
}

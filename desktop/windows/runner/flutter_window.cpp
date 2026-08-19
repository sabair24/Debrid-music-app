#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // Eerst de vlag, dan pas opruimen: het opruimen zelf brengt ons hieronder terug.
  tearing_down_ = true;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // ELKE keer dat deze app afsloot, crashte hij. Gemeten, niet vermoed.
  //
  // Vier crashdumps van 15 t/m 18-08 plus een naspeling op 19-08 om 06:24 wijzen allemaal naar
  // dezelfde instructie: `flutter_windows.dll+0x1cda0`, `mov rax,[rcx+10h]`, met rcx = 0 — een
  // leesfout op adres 0x10. De stack eronder is elke keer dezelfde:
  //
  //     flutter_windows!FlutterDesktopViewControllerHandleTopLevelWindowProc+0x32
  //     debridmusic!FlutterWindow::MessageHandler            <- deze regels
  //     user32!UserCallWinProcCheckWow
  //     user32!_fnDWORD                                      <- door de kernel bezorgd
  //
  // En het bericht dat het afvuurt is 0x210, WM_PARENTNOTIFY: dat stuurt Windows naar het
  // hoofdvenster zodra een KINDvenster verdwijnt. Bij het afsluiten is dat precies de Flutter-view.
  // Het bericht komt synchroon terug terwijl de controller aan het verdwijnen is, en dan geeft de
  // regel hieronder hem door aan iets wat er niet meer is.
  //
  // De `if (flutter_controller_)` die hier stond dekt dat niet: hij is niet leeg, hij is stervende.
  // Vandaar een vlag die vanaf het eerste opruimmoment ALLES tegenhoudt.
  //
  // Waarom dit zeven keer "willekeurig" leek: er is niets mis vóór de crash, dus in de logboeken
  // staat niets, en het gebeurt op het moment dat je de app toch al wegklikt.
  if (!tearing_down_ && flutter_controller_) {
    // Give Flutter, including plugins, an opportunity to handle window messages.
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      // Deze stond ONgeschermd: een lettertypewissel tijdens of na het opruimen liep hier zo een
      // lege controller in. Dezelfde fout als hierboven, alleen zeldzamer.
      if (!tearing_down_ && flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

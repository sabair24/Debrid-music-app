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
  // GEEN Windows-titelbalk. Hier, en niet meer via het pakket.
  //
  // De app tekent zijn eigen knoppen in de bovenbalk, en er hoort dus geen tweede set boven te
  // staan. Dat werd tot nu toe aan `window_manager` gevraagd -- `titleBarStyle: hidden`, bij het
  // maken van het venster en later nog eens na het maximaliseren -- en het gebeurde gewoon niet.
  // Gemeten op 22-08-2026, op een venster dat NIET gemaximaliseerd was: de balk stond er, met twee
  // sets vensterknoppen onder elkaar. Dat het ook zonder maximaliseren misgaat sluit die weg uit.
  //
  // Er is geen manier om aan dat pakket terug te vragen of de balk werkelijk verborgen is, dus
  // "nog een keer vragen" is niet te controleren. Hier wél: dit is onze eigen vensterprocedure,
  // hij staat in dit bestand, en de Windows-bouw compileert hem.
  //
  // **Hoe het werkt.** Windows vraagt met WM_NCCALCSIZE hoeveel van het venster CLIËNTgebied is.
  // We laten hem eerst normaal rekenen en zetten dan alleen de BOVENkant terug op de vensterrand.
  // Daarmee wordt de strook waar de titelbalk stond gewoon app, en tekent Windows hem niet meer.
  //
  // Links, rechts en onder blijven met opzet niet-cliëntgebied: dat zijn de sleepranden. Zou je die
  // ook opeisen, dan is het venster niet meer te vergroten aan de randen en verliest het zijn
  // schaduw en het vastklikken tegen de schermrand. De bovenrand is de enige die dit kost -- daar
  // ligt nu de bovenbalk van de app, en die sleept het venster (DragToMoveArea) in plaats van het
  // te vergroten.
  //
  // Gemaximaliseerd maakt Windows het venster juist GROTER dan het scherm, precies met de
  // framedikte eromheen. Zonder die inzet terug te geven zou de bovenrand van de app buiten beeld
  // vallen -- de knoppen zouden er half af zijn.
  //
  // Vóór de doorgifte aan de plug-ins, en dat is nodig: geeft `window_manager` zelf een antwoord op
  // dit bericht, dan komt de regel hieronder er nooit aan toe en verandert er niets.
  if (message == WM_NCCALCSIZE && wparam == TRUE) {
    NCCALCSIZE_PARAMS* maten = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
    const LONG boven = maten->rgrc[0].top;
    const LRESULT standaard = DefWindowProc(hwnd, message, wparam, lparam);
    if (standaard != 0) {
      return standaard;
    }
    maten->rgrc[0].top = boven;
    if (IsZoomed(hwnd)) {
      maten->rgrc[0].top +=
          GetSystemMetrics(SM_CYSIZEFRAME) + GetSystemMetrics(SM_CXPADDEDBORDER);
    }
    return 0;
  }

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

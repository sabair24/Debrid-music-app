#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Is het opruimen al begonnen?
  //
  // Vanaf dat moment gaat er geen enkel vensterbericht meer naar Flutter. Het opruimen van de
  // Flutter-view laat Windows namelijk zelf nog berichten sturen -- WM_PARENTNOTIFY komt synchroon
  // uit de kernel terug naar dit venster -- en die kwamen terecht bij een controller die al aan het
  // verdwijnen was. De meting staat in flutter_window.cpp.
  bool tearing_down_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_

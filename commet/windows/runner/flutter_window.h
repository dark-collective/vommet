#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // Vommet issue 714: don't show the window on the first frame
  // (--start-in-tray); Dart hides it to the tray or shows it minimized.
  void SetStartHidden(bool start_hidden) { start_hidden_ = start_hidden; }

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Vommet issue 883: runs the message loop until Dart asks to quit or
  // |timeout_ms| passes, so the session doesn't end under Dart while it
  // still closes its clients.
  void WaitForQuitRequest(DWORD timeout_ms);

  // The project to run.
  flutter::DartProject project_;

  bool start_hidden_ = false;

  // Vommet issue 883: Dart asked to quit ("quit" on im.nether.vommet/session).
  bool quit_requested_ = false;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Vommet: "Copy image" clipboard channel.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      clipboard_channel_;

  // Vommet: metered connection check (automatic media download).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      network_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_

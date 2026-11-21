#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

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
  // v2.19.68 F11 borderless fullscreen: saves the current window placement,
  // toggles the WS_OVERLAPPEDWINDOW / WS_POPUP frame styles and stretches to
  // the primary monitor; restoring uses the saved WINDOWPLACEMENT. Returns
  // true when the window is in fullscreen after the call.
  bool ToggleFullscreen(HWND window);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Wave2 drag-and-drop: file paths received via WM_DROPFILES are forwarded
  // to Dart through this channel (method name "onFiles", payload is a list
  // of UTF-8 path strings).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      file_drop_channel_;

  // v2.19.68 F11 borderless fullscreen: the Dart side
  // (lib/services/window_channel.dart) calls method "toggleFullscreen" on
  // this channel; the reply is a bool (true = now in fullscreen).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  // True while the window is in borderless fullscreen (toggle state).
  bool fullscreen_ = false;

  // Window placement saved right before entering fullscreen, used to restore
  // the previous size/position when leaving it.
  WINDOWPLACEMENT saved_placement_ = {};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_

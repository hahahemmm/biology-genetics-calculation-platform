#include "flutter_window.h"

#include <optional>
#include <shellapi.h>
// shellapi.h (WM_DROPFILES / DragAcceptFiles / DragQueryFileW) depends on
// windows.h being included first - flutter_window.h -> win32_window.h
// already brings it in.

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

  // Wave2 drag-and-drop: create the "biology/file_drop" channel and make the
  // top-level window accept file drops. WM_DROPFILES is forwarded in the
  // dedicated branch of MessageHandler below; when the Dart side
  // (lib/ui/file_drop_io.dart) has not registered a handler yet,
  // InvokeMethod lands as a fire-and-forget no-reply call - the frame is
  // dropped safely without crashing.
  file_drop_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "biology/file_drop",
          &flutter::StandardMethodCodec::GetInstance());
  DragAcceptFiles(GetHandle(), TRUE);

  // v2.19.68 F11 borderless fullscreen: the Dart side (F11 shortcut in
  // lib/main.dart -> lib/services/window_channel.dart) invokes method
  // "toggleFullscreen"; the reply bool tells it whether the window is now
  // in fullscreen. Unknown methods fall through to NotImplemented so the
  // Dart side's PlatformException fallback keeps working.
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "biology/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name().compare("toggleFullscreen") == 0) {
          result->Success(
              flutter::EncodableValue(ToggleFullscreen(GetHandle())));
        } else {
          result->NotImplemented();
        }
      });

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
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

// v2.19.68 F11 borderless fullscreen (classic Raymond Chen recipe):
// entering saves the WINDOWPLACEMENT, strips the WS_OVERLAPPEDWINDOW frame
// styles (keeping WS_POPUP semantics via a bare borderless style), and
// stretches over the primary monitor with SWP_FRAMECHANGED so the
// non-client area is recomputed; leaving restores the saved placement and
// re-adds WS_OVERLAPPEDWINDOW. Returns true when in fullscreen afterwards.
bool FlutterWindow::ToggleFullscreen(HWND window) {
  if (!window) {
    return false;
  }
  LONG_PTR style = GetWindowLongPtr(window, GWL_STYLE);
  if (fullscreen_) {
    // Leave fullscreen: swap the popup style back to the framed window
    // style, then put the window to its saved placement (size + maximized
    // state).
    SetWindowLongPtr(window, GWL_STYLE,
                     (style & ~WS_POPUP) | WS_OVERLAPPEDWINDOW);
    SetWindowPlacement(window, &saved_placement_);
    SetWindowPos(window, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                     SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    fullscreen_ = false;
    return false;
  }
  // Enter fullscreen: remember where the window is now.
  saved_placement_.length = sizeof(WINDOWPLACEMENT);
  if (!GetWindowPlacement(window, &saved_placement_)) {
    return false;
  }
  MONITORINFO mi = {};
  mi.cbSize = sizeof(mi);
  if (!GetMonitorInfo(MonitorFromWindow(window, MONITOR_DEFAULTTOPRIMARY),
                      &mi)) {
    return false;
  }
  SetWindowLongPtr(window, GWL_STYLE,
                   (style & ~WS_OVERLAPPEDWINDOW) | WS_POPUP);
  SetWindowPos(window, HWND_TOP, mi.rcMonitor.left, mi.rcMonitor.top,
               mi.rcMonitor.right - mi.rcMonitor.left,
               mi.rcMonitor.bottom - mi.rcMonitor.top,
               SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  fullscreen_ = true;
  return true;
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_DROPFILES: {
      // Wave2 drag-and-drop: collect the dropped file paths and forward them
      // to Dart. Non-ASCII (e.g. Chinese) paths must go through
      // DragQueryFileW + WideCharToMultiByte to convert to UTF-8
      // (DragQueryFileA mangles non-ASCII paths).
      HDROP hdrop = reinterpret_cast<HDROP>(wparam);
      // iFile = 0xFFFFFFFF queries the total file count; each item's length
      // (excluding the trailing null) is then queried one by one.
      const UINT count = DragQueryFileW(hdrop, 0xFFFFFFFF, nullptr, 0);
      flutter::EncodableList files;
      files.reserve(count);
      std::wstring wide;
      for (UINT i = 0; i < count; ++i) {
        const UINT len = DragQueryFileW(hdrop, i, nullptr, 0);
        wide.resize(len + 1);
        DragQueryFileW(hdrop, i, wide.data(), len + 1);
        wide.resize(len);  // drop the trailing null written into the buffer
        if (wide.empty()) continue;
        const int utf8_len = WideCharToMultiByte(
            CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.size()), nullptr,
            0, nullptr, nullptr);
        if (utf8_len <= 0) continue;
        std::string utf8(static_cast<size_t>(utf8_len), '\0');
        WideCharToMultiByte(CP_UTF8, 0, wide.c_str(),
                            static_cast<int>(wide.size()), utf8.data(),
                            utf8_len, nullptr, nullptr);
        files.emplace_back(std::move(utf8));
      }
      DragFinish(hdrop);
      if (!files.empty() && file_drop_channel_) {
        file_drop_channel_->InvokeMethod(
            "onFiles",
            std::make_unique<flutter::EncodableValue>(std::move(files)));
      }
      return 0;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

#include "flutter_window.h"

#include <dwmapi.h>
#include <optional>
#include <utility>
#include <windowsx.h>

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

  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "soundneed/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const HWND window = GetHandle();
        if (!window) {
          result->Error("window_unavailable", "The window is not available.");
          return;
        }

        const auto& method = call.method_name();
        if (method == "startOutputSpectrum") {
          spectrum_capture_.Start();
          result->Success(flutter::EncodableValue());
        } else if (method == "stopOutputSpectrum") {
          spectrum_capture_.Stop();
          result->Success(flutter::EncodableValue());
        } else if (method == "getOutputSpectrum") {
          flutter::EncodableList values;
          for (double value : spectrum_capture_.GetSpectrum()) {
            values.emplace_back(value);
          }
          result->Success(flutter::EncodableValue(std::move(values)));
        } else if (method == "minimize") {
          ShowWindow(window, SW_MINIMIZE);
          result->Success(flutter::EncodableValue());
        } else if (method == "toggleMaximize") {
          const bool was_maximized = IsZoomed(window) != FALSE;
          ShowWindow(window, was_maximized ? SW_RESTORE : SW_MAXIMIZE);
          result->Success(
              flutter::EncodableValue(IsZoomed(window) != FALSE));
        } else if (method == "close") {
          PostMessage(window, WM_CLOSE, 0, 0);
          result->Success(flutter::EncodableValue());
        } else if (method == "drag") {
          ReleaseCapture();
          POINT cursor{};
          GetCursorPos(&cursor);
          SendMessage(window, WM_NCLBUTTONDOWN, HTCAPTION,
                      MAKELPARAM(cursor.x, cursor.y));
          result->Success(flutter::EncodableValue());
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
  spectrum_capture_.Stop();
  window_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Windows reapplies its accent-colored frame when an unmaximized window
  // becomes active. Use the app's near-black edge instead.
  if (message == WM_ACTIVATE || message == WM_NCACTIVATE) {
    const COLORREF border_color = RGB(18, 18, 24);
    DwmSetWindowAttribute(hwnd, DWMWA_BORDER_COLOR, &border_color,
                          sizeof(border_color));
  }

  // Paint the dark client background before forwarding messages to Flutter.
  // This prevents Windows from briefly exposing a white erase frame when the
  // window regains focus and its Flutter surface is repainted.
  if (message == WM_ERASEBKGND) {
    RECT client_area = GetClientArea();
    FillRect(reinterpret_cast<HDC>(wparam), &client_area,
             reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH)));
    return 1;
  }

  // Let Windows own the move loop started from the custom Flutter title area.
  if (message == WM_NCLBUTTONDOWN && wparam == HTCAPTION) {
    return DefWindowProc(hwnd, message, wparam, lparam);
  }

  // Keep a native resize frame while restored so Windows shows the resize
  // cursor. When maximized, remove it so Flutter fills the monitor work area.
  if (message == WM_NCCALCSIZE) {
    if (IsZoomed(hwnd)) {
      return 0;
    }
    return DefWindowProc(hwnd, message, wparam, lparam);
  }

  if (message == WM_GETMINMAXINFO) {
    const HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFO monitor_info{};
    monitor_info.cbSize = sizeof(monitor_info);
    auto* limits = reinterpret_cast<MINMAXINFO*>(lparam);
    if (limits && GetMonitorInfo(monitor, &monitor_info)) {
      const RECT& monitor_area = monitor_info.rcMonitor;
      const RECT& work_area = monitor_info.rcWork;
      limits->ptMaxPosition.x = work_area.left - monitor_area.left;
      limits->ptMaxPosition.y = work_area.top - monitor_area.top;
      limits->ptMaxSize.x = work_area.right - work_area.left;
      limits->ptMaxSize.y = work_area.bottom - work_area.top;
      return 0;
    }
  }

  if (message == WM_NCHITTEST && !IsZoomed(hwnd)) {
    RECT bounds{};
    if (GetWindowRect(hwnd, &bounds)) {
      const int x = GET_X_LPARAM(lparam);
      const int y = GET_Y_LPARAM(lparam);
      const int border = GetSystemMetrics(SM_CXSIZEFRAME) +
                         GetSystemMetrics(SM_CXPADDEDBORDER);
      const bool left = x < bounds.left + border;
      const bool right = x >= bounds.right - border;
      const bool top = y < bounds.top + border;
      const bool bottom = y >= bounds.bottom - border;

      if (top && left) return HTTOPLEFT;
      if (top && right) return HTTOPRIGHT;
      if (bottom && left) return HTBOTTOMLEFT;
      if (bottom && right) return HTBOTTOMRIGHT;
      if (left) return HTLEFT;
      if (right) return HTRIGHT;
      if (top) return HTTOP;
      if (bottom) return HTBOTTOM;
    }
  }

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
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

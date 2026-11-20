// The launch splash on Windows (lib/desktop/ui/launch_splash.dart; Matt, 2026-11-20: "add a checking for updates splash
// window that shows before the app launches and load the app on this screen too similar to how discord does on
// launch"): the window starts small and centred, with no resize edge or maximise button, while the app looks for an
// update and loads; "splash" false gives it the size main.cpp asked for, centred on the same screen.
#include "splash.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

namespace {

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;
HWND g_window = nullptr;
LONG_PTR g_style = 0;
bool g_splash = false;

// The window's own size, in 96-DPI pixels, as main.cpp makes it.
constexpr int kFullWidth = 1100;
constexpr int kFullHeight = 740;
constexpr int kSplashWidth = 300;
constexpr int kSplashHeight = 340;

void Centre(HWND window, int width, int height) {
  const UINT dpi = GetDpiForWindow(window);
  const int w = MulDiv(width, dpi, 96), h = MulDiv(height, dpi, 96);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  GetMonitorInfo(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &info);
  const RECT& work = info.rcWork;
  const int cw = (w < work.right - work.left) ? w : work.right - work.left;
  const int ch = (h < work.bottom - work.top) ? h : work.bottom - work.top;
  const int x = work.left + ((work.right - work.left) - cw) / 2;
  const int y = work.top + ((work.bottom - work.top) - ch) / 2;
  SetWindowPos(window, nullptr, x, y, cw, ch, SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
}

void Leave() {
  if (!g_splash || g_window == nullptr) return;
  g_splash = false;
  SetWindowLongPtr(g_window, GWL_STYLE, g_style);
  Centre(g_window, kFullWidth, kFullHeight);
}

}  // namespace

void RegisterSplash(flutter::BinaryMessenger* messenger, HWND window) {
  g_window = window;
  g_style = GetWindowLongPtr(window, GWL_STYLE);
  SetWindowLongPtr(window, GWL_STYLE, g_style & ~(WS_THICKFRAME | WS_MAXIMIZEBOX));
  g_splash = true;
  Centre(window, kSplashWidth, kSplashHeight);
  g_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(messenger, "ghost_desktop/window", &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler([](const flutter::MethodCall<flutter::EncodableValue>& call, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (call.method_name() == "splash") {
      const auto* on = std::get_if<bool>(call.arguments());
      if (on != nullptr && !*on) Leave();
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
}

#include "main_thread.h"

namespace {

constexpr UINT kRun = WM_APP + 0x47;
HWND g_window = nullptr;

LRESULT CALLBACK Proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == kRun) {
    auto* work = reinterpret_cast<std::function<void()>*>(lparam);
    (*work)();
    delete work;
    return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

HWND Make(const wchar_t* name, WNDPROC proc) {
  WNDCLASSW wc = {};
  wc.lpfnWndProc = proc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.lpszClassName = name;
  RegisterClassW(&wc);
  return CreateWindowExW(0, name, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, wc.hInstance, nullptr);
}

}  // namespace

void MainThreadInit() {
  if (!g_window) g_window = Make(L"GhostMainThread", Proc);
}

void RunOnMain(std::function<void()> work) {
  if (!g_window) return;
  auto* held = new std::function<void()>(std::move(work));
  if (!PostMessage(g_window, kRun, 0, reinterpret_cast<LPARAM>(held))) delete held;
}

HWND MainThreadWindow(WNDPROC handler) {
  static int made = 0;
  wchar_t name[64];
  wsprintfW(name, L"GhostMainThread%d", ++made);
  return Make(name, handler);
}

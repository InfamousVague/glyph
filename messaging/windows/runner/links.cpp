// Circles' invite links opened into the app on Windows (Matt, 2026-11-19: "make a route to allow people to click a
// link on their phone or desktop to join a circle"). The invite page (site/join) opens ghostmsg://join/#c.…, which
// Windows runs this app with. A copy already running is handed the link (WM_COPYDATA) and the new one goes; else this
// copy keeps it until the app asks ("take"); later ones are handed over as they come ("open").
#include "links.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <memory>
#include <vector>

#include "utils.h"

namespace {

constexpr ULONG_PTR kLinkMessage = 0x47484C4B;  // "GHLK"
constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr const wchar_t kWindowTitle[] = L"Ghost Messaging";

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;
std::vector<std::string> g_pending;
bool g_taken = false;

void Opened(const std::wstring& link) {
  std::string url = Utf8FromUtf16(link.c_str());
  if (url.empty()) return;
  if (g_taken && g_channel) {
    g_channel->InvokeMethod("open", std::make_unique<flutter::EncodableValue>(url));
  } else {
    g_pending.push_back(url);
  }
}

bool SetKey(HKEY root, const std::wstring& path, const wchar_t* name, const std::wstring& value) {
  HKEY key;
  if (RegCreateKeyExW(root, path.c_str(), 0, nullptr, 0, KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) return false;
  LONG done = RegSetValueExW(key, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(value.c_str()),
                             static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(key);
  return done == ERROR_SUCCESS;
}

}  // namespace

std::wstring LinkInCommandLine() {
  int argc = 0;
  wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  std::wstring found;
  if (argv == nullptr) return found;
  for (int i = 1; i < argc; i++) {
    std::wstring a = argv[i];
    if (a.size() > 9 && _wcsnicmp(a.c_str(), L"ghostmsg:", 9) == 0) {
      found = a;
      break;
    }
  }
  LocalFree(argv);
  return found;
}

bool HandToRunningCopy(const std::wstring& link) {
  HWND other = FindWindowW(kWindowClassName, kWindowTitle);
  if (other == nullptr) return false;
  COPYDATASTRUCT data;
  data.dwData = kLinkMessage;
  data.cbData = static_cast<DWORD>((link.size() + 1) * sizeof(wchar_t));
  data.lpData = const_cast<wchar_t*>(link.c_str());
  DWORD_PTR answer = 0;
  if (!SendMessageTimeoutW(other, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG, 3000, &answer)) return false;
  // Windows lets the copy the person started bring the other to the front.
  AllowSetForegroundWindow(ASFW_ANY);
  if (IsIconic(other)) ShowWindow(other, SW_RESTORE);
  SetForegroundWindow(other);
  return answer == 1;
}

void RegisterLinkScheme() {
  wchar_t exe[MAX_PATH];
  DWORD n = GetModuleFileNameW(nullptr, exe, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) return;
  const std::wstring root = L"Software\\Classes\\ghostmsg";
  SetKey(HKEY_CURRENT_USER, root, nullptr, L"URL:Ghost Messaging");
  SetKey(HKEY_CURRENT_USER, root, L"URL Protocol", L"");
  SetKey(HKEY_CURRENT_USER, root + L"\\DefaultIcon", nullptr, std::wstring(L"\"") + exe + L"\",0");
  SetKey(HKEY_CURRENT_USER, root + L"\\shell\\open\\command", nullptr, std::wstring(L"\"") + exe + L"\" \"%1\"");
}

void RegisterLinks(flutter::BinaryMessenger* messenger, const std::wstring& first) {
  if (!first.empty()) Opened(first);
  g_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "ghost_desktop/links", &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler([](const flutter::MethodCall<flutter::EncodableValue>& call, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (call.method_name() != "take") {
      result->NotImplemented();
      return;
    }
    flutter::EncodableList list;
    for (const auto& url : g_pending) list.push_back(flutter::EncodableValue(url));
    g_pending.clear();
    g_taken = true;
    result->Success(flutter::EncodableValue(list));
  });
}

bool LinkCopied(HWND window, LPARAM lparam) {
  auto data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
  if (data == nullptr || data->dwData != kLinkMessage || data->lpData == nullptr || data->cbData < sizeof(wchar_t)) return false;
  std::wstring link(static_cast<const wchar_t*>(data->lpData), data->cbData / sizeof(wchar_t));
  while (!link.empty() && link.back() == L'\0') link.pop_back();
  Opened(link);
  if (IsIconic(window)) ShowWindow(window, SW_RESTORE);
  SetForegroundWindow(window);
  return true;
}

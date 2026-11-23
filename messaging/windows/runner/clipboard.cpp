// A picture on the clipboard, for pasting into the message field on Windows (lib/desktop/platform.dart
// `pasteImage`; Matt, 2026-11-16: "add the ability to paste images into the chatbar on desktop"): the path of an
// image file copied in Explorer, or a copied picture (a screenshot, an image copied from a page) written out as a
// BMP in the temporary folder, which the app makes a PNG. Nothing where there is neither, and the field pastes words.
#include "clipboard.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <shellapi.h>

#include <algorithm>
#include <cwctype>
#include <memory>
#include <string>

namespace {

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;

// Windows' own wide text as UTF-8, which is what the channel carries.
std::string Utf8(const std::wstring& wide) {
  if (wide.empty()) return {};
  int size = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, nullptr, 0, nullptr, nullptr);
  std::string out(size - 1, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, out.data(), size, nullptr, nullptr);
  return out;
}

// Whether [path] ends as a picture's file does, whatever its letters' case.
bool IsImage(std::wstring path) {
  std::transform(path.begin(), path.end(), path.begin(), [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
  for (const wchar_t* end : {L".png", L".jpg", L".jpeg", L".gif", L".webp", L".heic", L".bmp"}) {
    size_t n = wcslen(end);
    if (path.size() > n && path.compare(path.size() - n, n, end) == 0) return true;
  }
  return false;
}

// An image file copied in Explorer: the first one.
std::string CopiedFile() {
  HANDLE data = GetClipboardData(CF_HDROP);
  if (!data) return {};
  auto drop = static_cast<HDROP>(GlobalLock(data));
  if (!drop) return {};
  std::string found;
  UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
  for (UINT i = 0; i < count && found.empty(); i++) {
    wchar_t path[MAX_PATH];
    if (DragQueryFileW(drop, i, path, MAX_PATH) && IsImage(path)) found = Utf8(path);
  }
  GlobalUnlock(data);
  return found;
}

// A copied picture, as a BMP file: the clipboard's device-independent bitmap with a file header before it.
std::string CopiedPicture() {
  HANDLE data = GetClipboardData(CF_DIB);
  if (!data) return {};
  auto bits = static_cast<const BYTE*>(GlobalLock(data));
  if (!bits) return {};
  SIZE_T size = GlobalSize(data);
  // The file header says where the pixels begin: after the bitmap's own header, its three colour masks where it has
  // them apart, and its colour table (a full one for 8 bits or fewer where the count is not given).
  auto info = reinterpret_cast<const BITMAPINFOHEADER*>(bits);
  DWORD colors = info->biClrUsed ? info->biClrUsed : (info->biBitCount <= 8 ? (1u << info->biBitCount) : 0);
  DWORD masks = (info->biCompression == BI_BITFIELDS && info->biSize == sizeof(BITMAPINFOHEADER)) ? 12 : 0;
  BITMAPFILEHEADER header{};
  header.bfType = 0x4D42;  // "BM"
  header.bfSize = static_cast<DWORD>(sizeof(header) + size);
  header.bfOffBits = static_cast<DWORD>(sizeof(header) + info->biSize + masks + colors * sizeof(RGBQUAD));
  wchar_t folder[MAX_PATH];
  GetTempPathW(MAX_PATH, folder);
  std::wstring path = std::wstring(folder) + L"ghost-pasted-" + std::to_wstring(GetTickCount64()) + L".bmp";
  std::string out;
  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_TEMPORARY, nullptr);
  if (file != INVALID_HANDLE_VALUE) {
    DWORD wrote = 0;
    bool ok = WriteFile(file, &header, sizeof(header), &wrote, nullptr) && WriteFile(file, bits, static_cast<DWORD>(size), &wrote, nullptr);
    CloseHandle(file);
    if (ok) out = Utf8(path);
  }
  GlobalUnlock(data);
  return out;
}

}  // namespace

// "ghost_desktop/system" on Windows answers `pasteImage` alone: a copied file first, else a copied picture.
void RegisterClipboard(flutter::BinaryMessenger* messenger) {
  g_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(messenger, "ghost_desktop/system", &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler([](const flutter::MethodCall<flutter::EncodableValue>& call, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (call.method_name() != "pasteImage") {
      result->NotImplemented();
      return;
    }
    std::string path;
    if (OpenClipboard(nullptr)) {
      path = CopiedFile();
      if (path.empty()) path = CopiedPicture();
      CloseClipboard();
    }
    if (path.empty()) {
      result->Success();
    } else {
      result->Success(flutter::EncodableValue(path));
    }
  });
}

#include "tray_icon.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <shellapi.h>
#include <windowsx.h>

#include <algorithm>
#include <cstring>
#include <memory>
#include <optional>
#include <string>
#include <vector>

// Vommet: see tray_icon.h. The icon belongs to a hidden window of its own,
// which gets the icon's mouse events and the shell's "TaskbarCreated"
// broadcast (Explorer restarted: the icon has to be added again).
// Everything runs on the platform thread.

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

namespace {

constexpr wchar_t kWindowClass[] = L"VOMMET_TRAY_ICON_WINDOW";
constexpr UINT kIconId = 1;
constexpr UINT kCallbackMessage = WM_APP + 0x63;

struct Pixmap {
  int width = 0;
  int height = 0;
  std::vector<uint8_t> argb;  // A, R, G, B per pixel, rows top to bottom
};

HWND g_window = nullptr;
UINT g_taskbar_created = 0;
std::unique_ptr<flutter::MethodChannel<EncodableValue>> g_channel;
bool g_started = false;
bool g_added = false;
HICON g_icon = nullptr;
std::wstring g_tooltip;
std::vector<std::optional<std::wstring>> g_menu;  // nullopt = separator

std::wstring Widen(const std::string& text) {
  if (text.empty()) return std::wstring();
  int size = MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                 static_cast<int>(text.size()), nullptr, 0);
  std::wstring wide(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      wide.data(), size);
  return wide;
}

const EncodableValue* Find(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::vector<Pixmap> ReadPixmaps(const EncodableMap& args) {
  std::vector<Pixmap> pixmaps;
  const auto* list = Find(args, "icons");
  if (!list || !std::holds_alternative<EncodableList>(*list)) return pixmaps;
  for (const auto& entry : std::get<EncodableList>(*list)) {
    const auto* map = std::get_if<EncodableMap>(&entry);
    if (!map) continue;
    const auto* width = Find(*map, "width");
    const auto* height = Find(*map, "height");
    const auto* argb = Find(*map, "argb");
    if (!width || !height || !argb) continue;
    Pixmap pixmap;
    pixmap.width = static_cast<int>(width->LongValue());
    pixmap.height = static_cast<int>(height->LongValue());
    if (const auto* bytes = std::get_if<std::vector<uint8_t>>(argb)) {
      pixmap.argb = *bytes;
    }
    if (pixmap.width <= 0 || pixmap.height <= 0 ||
        pixmap.argb.size() !=
            static_cast<size_t>(pixmap.width) * pixmap.height * 4) {
      continue;
    }
    pixmaps.push_back(std::move(pixmap));
  }
  return pixmaps;
}

// The pixmap made for the tray's icon size, or the smallest larger one
// (else the largest), centred on a square icon and scaled to that size.
HICON CreateIconFromPixmaps(const std::vector<Pixmap>& pixmaps) {
  if (pixmaps.empty()) return nullptr;
  const int target = GetSystemMetrics(SM_CXSMICON);
  const Pixmap* best = nullptr;
  for (const auto& pixmap : pixmaps) {
    const int size = std::max(pixmap.width, pixmap.height);
    const int best_size = best ? std::max(best->width, best->height) : 0;
    if (!best || (best_size < target && size > best_size) ||
        (size >= target && size < best_size)) {
      best = &pixmap;
    }
  }

  const int size = std::max(best->width, best->height);
  BITMAPV5HEADER header = {};
  header.bV5Size = sizeof(header);
  header.bV5Width = size;
  header.bV5Height = -size;  // top-down
  header.bV5Planes = 1;
  header.bV5BitCount = 32;
  header.bV5Compression = BI_BITFIELDS;
  header.bV5RedMask = 0x00FF0000;
  header.bV5GreenMask = 0x0000FF00;
  header.bV5BlueMask = 0x000000FF;
  header.bV5AlphaMask = 0xFF000000;

  HDC screen = GetDC(nullptr);
  void* bits = nullptr;
  HBITMAP color =
      CreateDIBSection(screen, reinterpret_cast<BITMAPINFO*>(&header),
                       DIB_RGB_COLORS, &bits, nullptr, 0);
  ReleaseDC(nullptr, screen);
  if (!color || !bits) {
    if (color) DeleteObject(color);
    return nullptr;
  }

  // Icons take straight (not premultiplied) alpha, as BGRA in memory.
  auto* out = static_cast<uint8_t*>(bits);
  memset(out, 0, static_cast<size_t>(size) * size * 4);
  const int left = (size - best->width) / 2;
  const int top = (size - best->height) / 2;
  for (int y = 0; y < best->height; ++y) {
    for (int x = 0; x < best->width; ++x) {
      const uint8_t* src =
          best->argb.data() + (static_cast<size_t>(y) * best->width + x) * 4;
      uint8_t* dst =
          out + (static_cast<size_t>(y + top) * size + x + left) * 4;
      dst[0] = src[3];  // B
      dst[1] = src[2];  // G
      dst[2] = src[1];  // R
      dst[3] = src[0];  // A
    }
  }

  // The alpha channel decides; the mask only has to exist.
  std::vector<uint8_t> mask_bits(((size + 15) / 16) * 2 * size, 0);
  HBITMAP mask = CreateBitmap(size, size, 1, 1, mask_bits.data());

  ICONINFO info = {};
  info.fIcon = TRUE;
  info.hbmColor = color;
  info.hbmMask = mask;
  HICON icon = CreateIconIndirect(&info);
  DeleteObject(color);
  if (mask) DeleteObject(mask);
  if (!icon || size == target) return icon;

  HICON scaled = static_cast<HICON>(
      CopyImage(icon, IMAGE_ICON, target, target, LR_COPYDELETEORG));
  return scaled ? scaled : icon;
}

NOTIFYICONDATAW IconData(UINT flags) {
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = g_window;
  data.uID = kIconId;
  data.uFlags = flags;
  data.uCallbackMessage = kCallbackMessage;
  data.hIcon = g_icon;
  wcsncpy_s(data.szTip, g_tooltip.c_str(), _TRUNCATE);
  return data;
}

void SetAvailable(bool available) {
  if (g_channel) {
    g_channel->InvokeMethod(
        "available", std::make_unique<EncodableValue>(available));
  }
}

bool AddIcon() {
  NOTIFYICONDATAW data =
      IconData(NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP);
  g_added = Shell_NotifyIconW(NIM_ADD, &data) == TRUE;
  if (g_added) {
    data.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &data);
  }
  return g_added;
}

void RemoveIcon() {
  if (!g_added) return;
  NOTIFYICONDATAW data = IconData(0);
  Shell_NotifyIconW(NIM_DELETE, &data);
  g_added = false;
}

void UpdateIcon() {
  if (!g_added) return;
  NOTIFYICONDATAW data = IconData(NIF_ICON | NIF_TIP | NIF_SHOWTIP);
  Shell_NotifyIconW(NIM_MODIFY, &data);
}

void ShowMenu(int x, int y) {
  HMENU menu = CreatePopupMenu();
  if (!menu) return;
  for (size_t i = 0; i < g_menu.size(); ++i) {
    if (g_menu[i]) {
      AppendMenuW(menu, MF_STRING, i + 1, g_menu[i]->c_str());
    } else {
      AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    }
  }
  // Without the foreground the menu doesn't close on a click elsewhere.
  SetForegroundWindow(g_window);
  UINT align = GetSystemMetrics(SM_MENUDROPALIGNMENT) ? TPM_RIGHTALIGN
                                                       : TPM_LEFTALIGN;
  const int command = TrackPopupMenuEx(
      menu, align | TPM_BOTTOMALIGN | TPM_RIGHTBUTTON | TPM_RETURNCMD |
                TPM_NONOTIFY,
      x, y, g_window, nullptr);
  PostMessage(g_window, WM_NULL, 0, 0);
  DestroyMenu(menu);
  if (command > 0 && g_channel) {
    g_channel->InvokeMethod(
        "menuClicked", std::make_unique<EncodableValue>(command - 1));
  }
}

LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                            LPARAM lparam) {
  if (message == kCallbackMessage) {
    switch (LOWORD(lparam)) {
      case NIN_SELECT:
      case NIN_KEYSELECT:
        if (g_channel) g_channel->InvokeMethod("activate", nullptr);
        return 0;
      case WM_CONTEXTMENU:
        ShowMenu(GET_X_LPARAM(wparam), GET_Y_LPARAM(wparam));
        return 0;
    }
    return 0;
  }
  if (g_taskbar_created != 0 && message == g_taskbar_created) {
    // Explorer (re)started: its tray forgot every icon.
    if (g_started) {
      g_added = false;
      SetAvailable(AddIcon());
    }
    return 0;
  }
  return DefWindowProc(window, message, wparam, lparam);
}

bool EnsureWindow() {
  if (g_window) return true;
  HINSTANCE instance = GetModuleHandle(nullptr);
  WNDCLASSW window_class = {};
  window_class.lpfnWndProc = WindowProc;
  window_class.hInstance = instance;
  window_class.lpszClassName = kWindowClass;
  RegisterClassW(&window_class);
  g_taskbar_created = RegisterWindowMessageW(L"TaskbarCreated");
  // A hidden top-level window: message-only windows miss the broadcast.
  g_window = CreateWindowExW(0, kWindowClass, L"", WS_POPUP, 0, 0, 0, 0,
                             nullptr, nullptr, instance, nullptr);
  if (g_window) {
    // Lets Explorer's broadcast through to an elevated process too.
    ChangeWindowMessageFilterEx(g_window, g_taskbar_created, MSGFLT_ALLOW,
                                nullptr);
  }
  return g_window != nullptr;
}

void SetIconFrom(const EncodableMap& args) {
  if (const auto* tooltip = Find(args, "tooltip")) {
    if (const auto* text = std::get_if<std::string>(tooltip)) {
      g_tooltip = Widen(*text);
    }
  }
  std::vector<Pixmap> pixmaps = ReadPixmaps(args);
  if (!pixmaps.empty()) {
    if (HICON icon = CreateIconFromPixmaps(pixmaps)) {
      if (g_icon) DestroyIcon(g_icon);
      g_icon = icon;
    }
  }
}

void Stop() {
  RemoveIcon();
  g_started = false;
  if (g_icon) {
    DestroyIcon(g_icon);
    g_icon = nullptr;
  }
}

void HandleCall(const flutter::MethodCall<EncodableValue>& call,
                std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto* args = std::get_if<EncodableMap>(call.arguments());
  const std::string& method = call.method_name();

  if (method == "start") {
    if (!args) {
      result->Error("bad_args", "expected a map");
      return;
    }
    if (!EnsureWindow()) {
      result->Error("no_window", "could not create the tray window");
      return;
    }
    RemoveIcon();
    SetIconFrom(*args);
    g_menu.clear();
    if (const auto* menu = Find(*args, "menu")) {
      if (const auto* items = std::get_if<EncodableList>(menu)) {
        for (const auto& item : *items) {
          const auto* label = std::get_if<std::string>(&item);
          if (label) {
            g_menu.push_back(Widen(*label));
          } else {
            g_menu.push_back(std::nullopt);
          }
        }
      }
    }
    g_started = true;
    result->Success(EncodableValue(AddIcon()));
    return;
  }
  if (method == "setIcon") {
    if (!args) {
      result->Error("bad_args", "expected a map");
      return;
    }
    SetIconFrom(*args);
    UpdateIcon();
    result->Success();
    return;
  }
  if (method == "setMenuLabel") {
    const auto* index = args ? Find(*args, "index") : nullptr;
    const auto* label = args ? Find(*args, "label") : nullptr;
    const auto* text = label ? std::get_if<std::string>(label) : nullptr;
    if (!index || !text) {
      result->Error("bad_args", "expected index and label");
      return;
    }
    const auto i = index->LongValue();
    if (i >= 0 && static_cast<size_t>(i) < g_menu.size()) {
      g_menu[static_cast<size_t>(i)] = Widen(*text);
    }
    result->Success();
    return;
  }
  if (method == "dispose") {
    Stop();
    result->Success();
    return;
  }
  result->NotImplemented();
}

}  // namespace

void TrayIconRegister(flutter::BinaryMessenger* messenger) {
  g_channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "im.nether.vommet/tray",
      &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(HandleCall);
}

void TrayIconShutdown() {
  Stop();
  g_channel = nullptr;
  if (g_window) {
    DestroyWindow(g_window);
    g_window = nullptr;
  }
}

#include "widget_dock.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <objidl.h>
#include <shellapi.h>
#include <shlobj.h>
#include <wrl.h>

#include <WebView2.h>
#include <WebView2EnvironmentOptions.h>

#include <algorithm>
#include <functional>
#include <iostream>
#include <map>
#include <memory>
#include <string>
#include <vector>

// Vommet: see widget_dock.h. One entry per open widget, keyed by the id the
// Dart side gave it. Docked, the WebView2 controller's parent is a child
// window of the main window placed at the rectangle Dart keeps free (above
// the Flutter view); popped out, its parent is a top-level window of its
// own. put_ParentWindow moves the same controller, so the page keeps
// running. Everything runs on the platform thread, which owns both windows.

using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

namespace {

constexpr wchar_t kHostClass[] = L"VOMMET_WIDGET_DOCK_HOST";
constexpr wchar_t kWindowClass[] = L"VOMMET_WIDGET_DOCK_WINDOW";
constexpr UINT kRunTask = WM_APP + 0x51;

struct DockEntry {
  std::string id;
  std::wstring title;
  HWND host = nullptr;    // child of the main window, at the docked rect
  HWND popout = nullptr;  // own top-level window while popped out
  ComPtr<ICoreWebView2Controller> controller;
  ComPtr<ICoreWebView2> webview;
  RECT rect = {0, 0, 0, 0};  // physical pixels in the Flutter view
  bool visible = false;
  bool destroyed = false;
  bool popout_pending = false;
  std::vector<std::wstring> pending_scripts;  // before the view exists

  // The page is full screen: |fullscreen_window| (the main window when
  // docked, else the popped out one) was made full screen for it, unless it
  // already was. Its earlier style and placement come back afterwards.
  bool fullscreen = false;
  HWND fullscreen_window = nullptr;
  bool fullscreen_restore = false;
  LONG_PTR fullscreen_style = 0;
  WINDOWPLACEMENT fullscreen_placement = {sizeof(WINDOWPLACEMENT)};
};

HWND g_flutter_view = nullptr;
HWND g_task_window = nullptr;
std::unique_ptr<flutter::MethodChannel<EncodableValue>> g_channel;
std::map<std::string, std::shared_ptr<DockEntry>> g_entries;
ComPtr<ICoreWebView2Environment> g_environment;
bool g_environment_failed = false;
std::vector<std::function<void()>> g_environment_waiters;
int g_profile_counter = 0;

std::wstring Widen(const std::string& text) {
  if (text.empty()) return std::wstring();
  int size = MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                 static_cast<int>(text.size()), nullptr, 0);
  std::wstring wide(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      wide.data(), size);
  return wide;
}

std::string Narrow(const wchar_t* text) {
  if (text == nullptr || *text == L'\0') return std::string();
  int size =
      WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0, nullptr, nullptr);
  std::string narrow(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text, -1, narrow.data(), size, nullptr,
                      nullptr);
  narrow.resize(size - 1);
  return narrow;
}

HWND MainWindow() { return GetAncestor(g_flutter_view, GA_ROOT); }

void Notify(const char* method, const DockEntry& entry,
            const std::string* message = nullptr) {
  if (!g_channel) return;
  EncodableMap args = {{EncodableValue("id"), EncodableValue(entry.id)}};
  if (message != nullptr) {
    args[EncodableValue("message")] = EncodableValue(*message);
  }
  g_channel->InvokeMethod(method,
                          std::make_unique<EncodableValue>(std::move(args)));
}

// Runs |task| from the message loop, outside the WebView2 event handler
// that asked for it (handlers must not block on modal UI).
void RunLater(std::function<void()> task) {
  PostMessage(g_task_window, kRunTask, 0,
              reinterpret_cast<LPARAM>(new std::function<void()>(std::move(task))));
}

DockEntry* EntryOf(HWND window) {
  return reinterpret_cast<DockEntry*>(GetWindowLongPtr(window, GWLP_USERDATA));
}

void FitToClient(DockEntry* entry, HWND parent) {
  if (!entry->controller) return;
  RECT client;
  GetClientRect(parent, &client);
  entry->controller->put_Bounds(client);
}

// The docked entry that is full screen, if any: it covers the whole main
// window, over the other docked views.
DockEntry* FullscreenDocked() {
  for (auto& pair : g_entries) {
    DockEntry* entry = pair.second.get();
    if (entry->fullscreen && entry->popout == nullptr) return entry;
  }
  return nullptr;
}

void ApplyDocked(DockEntry* entry) {
  if (entry->popout != nullptr) return;
  RECT r = entry->rect;
  bool show = entry->visible && r.right > r.left && r.bottom > r.top;
  DockEntry* fullscreen = FullscreenDocked();
  if (fullscreen == entry) {
    // The rect and visibility Dart sends meanwhile are kept for after.
    RECT client;
    GetClientRect(GetParent(g_flutter_view), &client);
    SetWindowPos(entry->host, HWND_TOP, 0, 0, client.right, client.bottom,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);
    show = true;
  } else if (fullscreen != nullptr) {
    ShowWindow(entry->host, SW_HIDE);
    show = false;
  } else if (show) {
    // The Flutter view fills the main window's client area today, but map
    // anyway so a title bar or border drawn by Flutter can't shift it.
    POINT corners[2] = {{r.left, r.top}, {r.right, r.bottom}};
    MapWindowPoints(g_flutter_view, GetParent(g_flutter_view), corners, 2);
    SetWindowPos(entry->host, HWND_TOP, corners[0].x, corners[0].y,
                 corners[1].x - corners[0].x, corners[1].y - corners[0].y,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);
  } else {
    ShowWindow(entry->host, SW_HIDE);
  }
  if (entry->controller) {
    FitToClient(entry, entry->host);
    entry->controller->put_IsVisible(show ? TRUE : FALSE);
  }
}

void PopOut(DockEntry* entry);
void DockBack(DockEntry* entry);

void ApplyAllDocked() {
  for (auto& pair : g_entries) ApplyDocked(pair.second.get());
}

bool IsFullscreenWindow(HWND window) {
  if (GetWindowLongPtr(window, GWL_STYLE) & WS_CAPTION) return false;
  MONITORINFO monitor = {sizeof(MONITORINFO)};
  GetMonitorInfo(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &monitor);
  RECT rect;
  GetWindowRect(window, &rect);
  return EqualRect(&rect, &monitor.rcMonitor) != FALSE;
}

// WebView2 only reports that the page went full screen; making the window
// full screen is up to us.
void EnterFullscreen(DockEntry* entry) {
  if (entry->fullscreen) return;
  HWND window = entry->popout != nullptr ? entry->popout : MainWindow();
  entry->fullscreen = true;
  entry->fullscreen_window = window;
  entry->fullscreen_restore = !IsFullscreenWindow(window);
  if (entry->fullscreen_restore) {
    entry->fullscreen_style = GetWindowLongPtr(window, GWL_STYLE);
    GetWindowPlacement(window, &entry->fullscreen_placement);
    MONITORINFO monitor = {sizeof(MONITORINFO)};
    GetMonitorInfo(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                   &monitor);
    SetWindowLongPtr(window, GWL_STYLE,
                     entry->fullscreen_style & ~WS_OVERLAPPEDWINDOW);
    const RECT& r = monitor.rcMonitor;
    SetWindowPos(window, HWND_TOP, r.left, r.top, r.right - r.left,
                 r.bottom - r.top, SWP_FRAMECHANGED | SWP_NOOWNERZORDER);
  }
  if (entry->popout == nullptr) ApplyAllDocked();
  Notify("fullscreenEntered", *entry);
}

// Puts the window back. |leave_page| also takes the page out of full
// screen, for when we end it (moving or closing the view) rather than the
// page.
void LeaveFullscreen(DockEntry* entry, bool leave_page) {
  if (!entry->fullscreen) return;
  entry->fullscreen = false;
  HWND window = entry->fullscreen_window;
  entry->fullscreen_window = nullptr;
  if (entry->fullscreen_restore && IsWindow(window)) {
    SetWindowLongPtr(window, GWL_STYLE, entry->fullscreen_style);
    SetWindowPlacement(window, &entry->fullscreen_placement);
    SetWindowPos(window, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER |
                     SWP_FRAMECHANGED);
  }
  if (leave_page && entry->webview) {
    entry->webview->ExecuteScript(
        L"document.fullscreenElement && document.exitFullscreen()", nullptr);
  }
  ApplyAllDocked();
  Notify("fullscreenLeft", *entry);
}

LRESULT CALLBACK HostProc(HWND window, UINT message, WPARAM wparam,
                          LPARAM lparam) {
  if (message == kRunTask) {
    auto* task = reinterpret_cast<std::function<void()>*>(lparam);
    (*task)();
    delete task;
    return 0;
  }
  if (message == WM_SIZE) {
    DockEntry* entry = EntryOf(window);
    if (entry != nullptr && entry->popout == nullptr) {
      FitToClient(entry, window);
    }
  }
  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT CALLBACK PopoutProc(HWND window, UINT message, WPARAM wparam,
                            LPARAM lparam) {
  DockEntry* entry = EntryOf(window);
  switch (message) {
    case WM_SIZE:
      if (entry != nullptr) FitToClient(entry, window);
      return 0;
    case WM_MOVE:
      if (entry != nullptr && entry->controller) {
        entry->controller->NotifyParentWindowPositionChanged();
      }
      break;
    case WM_DPICHANGED: {
      auto* suggested = reinterpret_cast<RECT*>(lparam);
      SetWindowPos(window, nullptr, suggested->left, suggested->top,
                   suggested->right - suggested->left,
                   suggested->bottom - suggested->top,
                   SWP_NOZORDER | SWP_NOACTIVATE);
      return 0;
    }
    case WM_CLOSE:
      // Closing the window brings the widget back into the room.
      if (entry != nullptr) {
        DockBack(entry);
        return 0;
      }
      break;
  }
  return DefWindowProc(window, message, wparam, lparam);
}

void RegisterClasses() {
  WNDCLASS host = {};
  host.lpszClassName = kHostClass;
  host.hInstance = GetModuleHandle(nullptr);
  host.lpfnWndProc = HostProc;
  host.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClass(&host);

  WNDCLASS popout = {};
  popout.lpszClassName = kWindowClass;
  popout.hInstance = GetModuleHandle(nullptr);
  popout.lpfnWndProc = PopoutProc;
  popout.hCursor = LoadCursor(nullptr, IDC_ARROW);
  popout.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  RegisterClass(&popout);
}

// One environment for every docked widget, in its own user data folder:
// its browser arguments differ from the other WebView2 users in the app
// (in-app web views), which an environment sharing a folder would refuse.
void WithEnvironment(std::function<void()> then) {
  if (g_environment || g_environment_failed) {
    then();
    return;
  }
  g_environment_waiters.push_back(std::move(then));
  if (g_environment_waiters.size() > 1) return;

  std::wstring folder;
  PWSTR local_app_data = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr,
                                     &local_app_data))) {
    folder = std::wstring(local_app_data) + L"\\Vommet\\WidgetDock";
  }
  CoTaskMemFree(local_app_data);

  auto options = Microsoft::WRL::Make<CoreWebView2EnvironmentOptions>();
  // Like the widget window: media may start without a click (Watch
  // Together starts playback when someone else presses play).
  options->put_AdditionalBrowserArguments(
      L"--autoplay-policy=no-user-gesture-required");

  HRESULT hr = CreateCoreWebView2EnvironmentWithOptions(
      nullptr, folder.empty() ? nullptr : folder.c_str(), options.Get(),
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [](HRESULT result, ICoreWebView2Environment* environment) {
            if (SUCCEEDED(result) && environment != nullptr) {
              g_environment = environment;
            } else {
              std::cerr << "Widget dock: no WebView2 environment (0x"
                        << std::hex << result << std::dec << ")" << std::endl;
              g_environment_failed = true;
            }
            auto waiters = std::move(g_environment_waiters);
            g_environment_waiters.clear();
            for (auto& waiter : waiters) waiter();
            return S_OK;
          })
          .Get());
  if (FAILED(hr)) {
    std::cerr << "Widget dock: WebView2 unavailable (0x" << std::hex << hr
              << std::dec << ")" << std::endl;
    g_environment_failed = true;
    auto waiters = std::move(g_environment_waiters);
    g_environment_waiters.clear();
    for (auto& waiter : waiters) waiter();
  }
}

void OnPermissionRequested(std::shared_ptr<DockEntry> entry,
                           ICoreWebView2PermissionRequestedEventArgs* args) {
  COREWEBVIEW2_PERMISSION_KIND kind;
  args->get_PermissionKind(&kind);
  // Microphone/camera: ask first. Everything else is denied.
  if (kind != COREWEBVIEW2_PERMISSION_KIND_MICROPHONE &&
      kind != COREWEBVIEW2_PERMISSION_KIND_CAMERA) {
    args->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY);
    return;
  }
  ComPtr<ICoreWebView2Deferral> deferral;
  args->GetDeferral(&deferral);
  ComPtr<ICoreWebView2PermissionRequestedEventArgs> kept(args);
  RunLater([entry, kept, deferral]() {
    HWND owner = entry->popout != nullptr ? entry->popout : MainWindow();
    int answer = MessageBox(
        owner, L"This widget wants to use your microphone or camera.",
        entry->title.c_str(), MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2);
    kept->put_State(answer == IDYES ? COREWEBVIEW2_PERMISSION_STATE_ALLOW
                                    : COREWEBVIEW2_PERMISSION_STATE_DENY);
    deferral->Complete();
  });
}

void OnController(std::shared_ptr<DockEntry> entry, std::wstring url,
                  std::wstring script, std::wstring user_agent,
                  ICoreWebView2Controller* controller) {
  if (entry->destroyed) {
    controller->Close();
    return;
  }
  entry->controller = controller;
  controller->get_CoreWebView2(&entry->webview);
  ICoreWebView2* webview = entry->webview.Get();
  EventRegistrationToken token;

  ComPtr<ICoreWebView2Settings> settings;
  webview->get_Settings(&settings);
  settings->put_AreDevToolsEnabled(FALSE);
  settings->put_IsStatusBarEnabled(FALSE);
  ComPtr<ICoreWebView2Settings2> settings2;
  if (!user_agent.empty() && SUCCEEDED(settings.As(&settings2))) {
    settings2->put_UserAgent(user_agent.c_str());
  }

  // Messages from the page (widgets_ipc.js sendIpc) go to Dart unchanged.
  webview->add_WebMessageReceived(
      Callback<ICoreWebView2WebMessageReceivedEventHandler>(
          [entry](ICoreWebView2*, ICoreWebView2WebMessageReceivedEventArgs* args) {
            LPWSTR text = nullptr;
            if (FAILED(args->TryGetWebMessageAsString(&text))) {
              args->get_WebMessageAsJson(&text);
            }
            std::string message = Narrow(text);
            CoTaskMemFree(text);
            Notify("message", *entry, &message);
            return S_OK;
          })
          .Get(),
      &token);

  // Links that open a new window go to the default browser.
  webview->add_NewWindowRequested(
      Callback<ICoreWebView2NewWindowRequestedEventHandler>(
          [](ICoreWebView2*, ICoreWebView2NewWindowRequestedEventArgs* args) {
            args->put_Handled(TRUE);
            LPWSTR uri = nullptr;
            args->get_Uri(&uri);
            std::wstring target = uri == nullptr ? L"" : uri;
            CoTaskMemFree(uri);
            if (target.rfind(L"https://", 0) == 0 ||
                target.rfind(L"http://", 0) == 0) {
              ShellExecute(nullptr, L"open", target.c_str(), nullptr, nullptr,
                           SW_SHOWNORMAL);
            }
            return S_OK;
          })
          .Get(),
      &token);

  webview->add_PermissionRequested(
      Callback<ICoreWebView2PermissionRequestedEventHandler>(
          [entry](ICoreWebView2*, ICoreWebView2PermissionRequestedEventArgs* args) {
            OnPermissionRequested(entry, args);
            return S_OK;
          })
          .Get(),
      &token);

  webview->add_ProcessFailed(
      Callback<ICoreWebView2ProcessFailedEventHandler>(
          [entry](ICoreWebView2*, ICoreWebView2ProcessFailedEventArgs* args) {
            COREWEBVIEW2_PROCESS_FAILED_KIND kind;
            args->get_ProcessFailedKind(&kind);
            if (kind == COREWEBVIEW2_PROCESS_FAILED_KIND_BROWSER_PROCESS_EXITED ||
                kind == COREWEBVIEW2_PROCESS_FAILED_KIND_RENDER_PROCESS_EXITED) {
              std::cerr << "Widget web process ended (" << kind << ")"
                        << std::endl;
              Notify("closed", *entry);
            }
            return S_OK;
          })
          .Get(),
      &token);

  controller->add_GotFocus(
      Callback<ICoreWebView2FocusChangedEventHandler>(
          [entry](ICoreWebView2Controller*, IUnknown*) {
            Notify("focused", *entry);
            return S_OK;
          })
          .Get(),
      &token);

  // A video's full screen button (and Esc, or the page, leaving it again).
  webview->add_ContainsFullScreenElementChanged(
      Callback<ICoreWebView2ContainsFullScreenElementChangedEventHandler>(
          [entry](ICoreWebView2* sender, IUnknown*) {
            BOOL contains = FALSE;
            sender->get_ContainsFullScreenElement(&contains);
            if (contains) {
              EnterFullscreen(entry.get());
            } else {
              LeaveFullscreen(entry.get(), false);
            }
            return S_OK;
          })
          .Get(),
      &token);

  // Navigate once the script is in, so it runs before the page's own.
  webview->AddScriptToExecuteOnDocumentCreated(
      script.c_str(),
      Callback<ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler>(
          [entry, url](HRESULT, LPCWSTR) {
            if (!entry->destroyed && entry->webview) {
              entry->webview->Navigate(url.c_str());
            }
            return S_OK;
          })
          .Get());

  for (auto& pending : entry->pending_scripts) {
    webview->ExecuteScript(pending.c_str(), nullptr);
  }
  entry->pending_scripts.clear();

  ApplyDocked(entry.get());
  if (entry->popout_pending) {
    entry->popout_pending = false;
    PopOut(entry.get());
  }
}

void Create(const std::string& id, const std::string& url,
            const std::string& script, const std::string& title,
            const std::string& user_agent) {
  auto entry = std::make_shared<DockEntry>();
  entry->id = id;
  entry->title = Widen(title);
  entry->host = CreateWindowEx(
      0, kHostClass, L"", WS_CHILD | WS_CLIPCHILDREN | WS_CLIPSIBLINGS, 0, 0, 0,
      0, GetParent(g_flutter_view), nullptr, GetModuleHandle(nullptr), nullptr);
  SetWindowLongPtr(entry->host, GWLP_USERDATA,
                   reinterpret_cast<LONG_PTR>(entry.get()));
  g_entries[id] = entry;

  std::wstring wide_url = Widen(url);
  std::wstring wide_script = Widen(script);
  std::wstring wide_agent = Widen(user_agent);
  WithEnvironment([entry, wide_url, wide_script, wide_agent]() {
    if (entry->destroyed) return;
    if (!g_environment) {
      Notify("closed", *entry);
      return;
    }
    auto done = Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
        [entry, wide_url, wide_script, wide_agent](
            HRESULT result, ICoreWebView2Controller* controller) {
          if (FAILED(result) || controller == nullptr) {
            std::cerr << "Widget dock: no WebView2 controller (0x" << std::hex
                      << result << std::dec << ")" << std::endl;
            if (!entry->destroyed) Notify("closed", *entry);
            return S_OK;
          }
          OnController(entry, wide_url, wide_script, wide_agent, controller);
          return S_OK;
        });
    // Like the widget window: nothing is kept between sessions, and every
    // widget gets its own cookies and storage.
    ComPtr<ICoreWebView2Environment10> environment10;
    ComPtr<ICoreWebView2ControllerOptions> options;
    if (SUCCEEDED(g_environment.As(&environment10)) &&
        SUCCEEDED(environment10->CreateCoreWebView2ControllerOptions(&options))) {
      options->put_IsInPrivateModeEnabled(TRUE);
      std::wstring profile = L"widget" + std::to_wstring(++g_profile_counter);
      options->put_ProfileName(profile.c_str());
      environment10->CreateCoreWebView2ControllerWithOptions(
          entry->host, options.Get(), done.Get());
    } else {
      g_environment->CreateCoreWebView2Controller(entry->host, done.Get());
    }
  });
}

void PopOut(DockEntry* entry) {
  if (!entry->controller) {
    entry->popout_pending = true;
    return;
  }
  if (entry->popout != nullptr) {
    if (IsIconic(entry->popout)) ShowWindow(entry->popout, SW_RESTORE);
    SetForegroundWindow(entry->popout);
    return;
  }
  LeaveFullscreen(entry, true);
  HWND main = MainWindow();
  double scale = GetDpiForWindow(main) / 96.0;
  int width = std::max<int>(entry->rect.right - entry->rect.left,
                            static_cast<int>(960 * scale));
  int height = std::max<int>(entry->rect.bottom - entry->rect.top,
                             static_cast<int>(600 * scale));
  std::wstring title = L"Vommet | " + entry->title;
  HWND window = CreateWindowEx(
      0, kWindowClass, title.c_str(), WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
      CW_USEDEFAULT, CW_USEDEFAULT, width, height, nullptr, nullptr,
      GetModuleHandle(nullptr), nullptr);
  if (window == nullptr) return;
  HICON icon_big = reinterpret_cast<HICON>(SendMessage(main, WM_GETICON, ICON_BIG, 0));
  HICON icon_small = reinterpret_cast<HICON>(SendMessage(main, WM_GETICON, ICON_SMALL, 0));
  if (icon_big == nullptr) {
    icon_big = reinterpret_cast<HICON>(GetClassLongPtr(main, GCLP_HICON));
  }
  if (icon_big != nullptr) {
    SendMessage(window, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(icon_big));
  }
  if (icon_small != nullptr) {
    SendMessage(window, WM_SETICON, ICON_SMALL,
                reinterpret_cast<LPARAM>(icon_small));
  }

  entry->popout = window;
  SetWindowLongPtr(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(entry));
  entry->controller->put_ParentWindow(window);
  ShowWindow(entry->host, SW_HIDE);
  ShowWindow(window, SW_SHOWNORMAL);
  FitToClient(entry, window);
  entry->controller->put_IsVisible(TRUE);
  entry->controller->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
  Notify("poppedOut", *entry);
}

void DockBack(DockEntry* entry) {
  if (entry->popout == nullptr) {
    entry->popout_pending = false;
    return;
  }
  LeaveFullscreen(entry, true);
  HWND window = entry->popout;
  entry->popout = nullptr;
  SetWindowLongPtr(window, GWLP_USERDATA, 0);
  entry->controller->put_ParentWindow(entry->host);
  DestroyWindow(window);
  ApplyDocked(entry);
  Notify("docked", *entry);
}

void Destroy(const std::string& id) {
  auto found = g_entries.find(id);
  if (found == g_entries.end()) return;
  std::shared_ptr<DockEntry> entry = found->second;
  LeaveFullscreen(entry.get(), false);
  g_entries.erase(found);
  entry->destroyed = true;
  if (entry->controller) {
    entry->controller->Close();
    entry->controller.Reset();
    entry->webview.Reset();
  }
  if (entry->popout != nullptr) {
    SetWindowLongPtr(entry->popout, GWLP_USERDATA, 0);
    DestroyWindow(entry->popout);
    entry->popout = nullptr;
  }
  SetWindowLongPtr(entry->host, GWLP_USERDATA, 0);
  DestroyWindow(entry->host);
  entry->host = nullptr;
}

const EncodableValue* Lookup(const EncodableMap& args, const char* key) {
  auto found = args.find(EncodableValue(key));
  return found == args.end() ? nullptr : &found->second;
}

std::string LookupString(const EncodableMap& args, const char* key) {
  const EncodableValue* value = Lookup(args, key);
  if (value == nullptr) return std::string();
  const auto* text = std::get_if<std::string>(value);
  return text == nullptr ? std::string() : *text;
}

bool HasString(const EncodableMap& args, const char* key) {
  const EncodableValue* value = Lookup(args, key);
  return value != nullptr && std::holds_alternative<std::string>(*value);
}

double LookupDouble(const EncodableMap& args, const char* key) {
  const EncodableValue* value = Lookup(args, key);
  if (value == nullptr) return 0;
  if (const auto* d = std::get_if<double>(value)) return *d;
  if (const auto* i = std::get_if<int32_t>(value)) return *i;
  if (const auto* l = std::get_if<int64_t>(value)) return static_cast<double>(*l);
  return 0;
}

void Snapshot(DockEntry* entry,
              std::shared_ptr<flutter::MethodResult<EncodableValue>> result) {
  if (!entry->webview) {
    result->Success();
    return;
  }
  ComPtr<IStream> stream;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream))) {
    result->Success();
    return;
  }
  HRESULT hr = entry->webview->CapturePreview(
      COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_PNG, stream.Get(),
      Callback<ICoreWebView2CapturePreviewCompletedHandler>(
          [stream, result](HRESULT error) {
            if (FAILED(error)) {
              result->Success();
              return S_OK;
            }
            HGLOBAL memory = nullptr;
            GetHGlobalFromStream(stream.Get(), &memory);
            STATSTG stat = {};
            stream->Stat(&stat, STATFLAG_NONAME);
            auto size = static_cast<size_t>(stat.cbSize.QuadPart);
            std::vector<uint8_t> png(size);
            if (size > 0 && memory != nullptr) {
              void* data = GlobalLock(memory);
              memcpy(png.data(), data, size);
              GlobalUnlock(memory);
            }
            result->Success(EncodableValue(std::move(png)));
            return S_OK;
          })
          .Get());
  if (FAILED(hr)) result->Success();
}

bool WebView2Installed() {
  LPWSTR version = nullptr;
  HRESULT hr = GetAvailableCoreWebView2BrowserVersionString(nullptr, &version);
  bool installed = SUCCEEDED(hr) && version != nullptr;
  CoTaskMemFree(version);
  return installed;
}

void OnMethodCall(const flutter::MethodCall<EncodableValue>& call,
                  std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();

  if (method == "isAvailable") {
    result->Success(EncodableValue(WebView2Installed()));
    return;
  }
  if (method == "focusFlutter") {
    SetFocus(g_flutter_view);
    result->Success();
    return;
  }

  const auto* args = std::get_if<EncodableMap>(call.arguments());
  if (args == nullptr || !HasString(*args, "id")) {
    result->Error("bad_args", "expected a map with an id");
    return;
  }
  std::string id = LookupString(*args, "id");

  if (method == "create") {
    if (!HasString(*args, "url") || !HasString(*args, "script") ||
        g_entries.count(id) != 0) {
      result->Error("bad_args", "bad create");
      return;
    }
    std::string title = LookupString(*args, "title");
    Create(id, LookupString(*args, "url"), LookupString(*args, "script"),
           title.empty() ? "Widget" : title, LookupString(*args, "userAgent"));
    result->Success();
    return;
  }

  auto found = g_entries.find(id);
  if (found == g_entries.end()) {
    result->Error("unknown_id", id);
    return;
  }
  DockEntry* entry = found->second.get();

  if (method == "setRect") {
    // Physical pixels, which is also what Win32 and WebView2 use here.
    LONG x = static_cast<LONG>(LookupDouble(*args, "x"));
    LONG y = static_cast<LONG>(LookupDouble(*args, "y"));
    entry->rect = {x, y, x + static_cast<LONG>(LookupDouble(*args, "width")),
                   y + static_cast<LONG>(LookupDouble(*args, "height"))};
    ApplyDocked(entry);
  } else if (method == "setVisible") {
    const EncodableValue* visible = Lookup(*args, "visible");
    const bool* flag =
        visible == nullptr ? nullptr : std::get_if<bool>(visible);
    entry->visible = flag != nullptr && *flag;
    ApplyDocked(entry);
  } else if (method == "evaluate") {
    std::wstring script = Widen(LookupString(*args, "script"));
    if (entry->webview) {
      entry->webview->ExecuteScript(script.c_str(), nullptr);
    } else {
      entry->pending_scripts.push_back(script);
    }
  } else if (method == "popOut") {
    PopOut(entry);
  } else if (method == "dockBack") {
    DockBack(entry);
  } else if (method == "snapshot") {
    Snapshot(entry, std::shared_ptr<flutter::MethodResult<EncodableValue>>(
                        std::move(result)));
    return;
  } else if (method == "destroy") {
    Destroy(id);
  } else {
    result->NotImplemented();
    return;
  }
  result->Success();
}

}  // namespace

void WidgetDockRegister(flutter::BinaryMessenger* messenger,
                        HWND flutter_view) {
  g_flutter_view = flutter_view;
  // Keeps Flutter from painting over the docked views (its siblings).
  SetWindowLongPtr(flutter_view, GWL_STYLE,
                   GetWindowLongPtr(flutter_view, GWL_STYLE) | WS_CLIPSIBLINGS);
  RegisterClasses();
  g_task_window =
      CreateWindowEx(0, kHostClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr,
                     GetModuleHandle(nullptr), nullptr);
  g_channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "vommet/widget_dock",
      &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler(OnMethodCall);
}

void WidgetDockOnMainWindowMessage(UINT message) {
  if (message == WM_SIZE) {
    // A full screen docked view follows the main window's size.
    if (DockEntry* entry = FullscreenDocked()) ApplyDocked(entry);
    return;
  }
  if (message != WM_MOVE && message != WM_MOVING &&
      message != WM_WINDOWPOSCHANGED) {
    return;
  }
  for (auto& pair : g_entries) {
    DockEntry* entry = pair.second.get();
    if (entry->popout == nullptr && entry->controller) {
      entry->controller->NotifyParentWindowPositionChanged();
    }
  }
}

void WidgetDockShutdown() {
  // The engine may already be gone: nothing more goes to Dart.
  g_channel.reset();
  std::vector<std::string> ids;
  for (auto& pair : g_entries) ids.push_back(pair.first);
  for (auto& id : ids) Destroy(id);
  if (g_task_window != nullptr) {
    DestroyWindow(g_task_window);
    g_task_window = nullptr;
  }
  g_environment.Reset();
}

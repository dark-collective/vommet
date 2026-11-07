#include "flutter_window.h"
#include "tray_icon.h"
#include "widget_dock.h"

#include <cstring>
#include <optional>
#include <string>
#include <vector>

#include <flutter/standard_method_codec.h>
#include <netlistmgr.h>
#include <wincodec.h>
#include <wrl/client.h>

#include "flutter/generated_plugin_registrant.h"

#pragma comment(lib, "windowscodecs.lib")

namespace {

// Vommet issues 331 and 883: the runner sends "end" when the session ends;
// Dart sends "quit" when it has closed its clients and wants to exit.
constexpr char kSessionChannel[] = "im.nether.vommet/session";

// Vommet issue 883: posted to the main window when Dart asks to quit.
constexpr UINT kQuitMessage = WM_APP + 0x83;

// Vommet issue 883: how long WM_ENDSESSION waits for Dart to close its
// clients. Windows lists an app as holding up the shutdown after about 5 s.
constexpr DWORD kEndSessionWaitMs = 4000;

// Vommet: "Copy image". Puts a PNG on the Windows clipboard twice: as "PNG"
// (keeps transparency; browsers, Discord, Office) and as CF_DIB (Paint and
// most other Win32 apps). The pasteboard plugin only writes images on iOS.
HGLOBAL CopyToGlobal(const void* data, size_t size) {
  HGLOBAL handle = ::GlobalAlloc(GMEM_MOVEABLE, size);
  if (!handle) return nullptr;
  void* target = ::GlobalLock(handle);
  if (!target) {
    ::GlobalFree(handle);
    return nullptr;
  }
  memcpy(target, data, size);
  ::GlobalUnlock(handle);
  return handle;
}

// Decodes |png| with WIC into a bottom-up 32-bit DIB (header + pixels).
bool PngToDib(const std::vector<uint8_t>& png, std::vector<uint8_t>& dib) {
  using Microsoft::WRL::ComPtr;
  ComPtr<IWICImagingFactory> factory;
  if (FAILED(::CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&factory)))) {
    return false;
  }
  ComPtr<IWICStream> stream;
  if (FAILED(factory->CreateStream(&stream)) ||
      FAILED(stream->InitializeFromMemory(
          const_cast<BYTE*>(png.data()), static_cast<DWORD>(png.size())))) {
    return false;
  }
  ComPtr<IWICBitmapDecoder> decoder;
  ComPtr<IWICBitmapFrameDecode> frame;
  ComPtr<IWICBitmapSource> converted;
  if (FAILED(factory->CreateDecoderFromStream(
          stream.Get(), nullptr, WICDecodeMetadataCacheOnLoad, &decoder)) ||
      FAILED(decoder->GetFrame(0, &frame)) ||
      FAILED(::WICConvertBitmapSource(GUID_WICPixelFormat32bppBGRA,
                                      frame.Get(), &converted))) {
    return false;
  }
  UINT width = 0, height = 0;
  if (FAILED(converted->GetSize(&width, &height)) || width == 0 ||
      height == 0) {
    return false;
  }
  const UINT stride = width * 4;
  std::vector<uint8_t> pixels(static_cast<size_t>(stride) * height);
  if (FAILED(converted->CopyPixels(nullptr, stride,
                                   static_cast<UINT>(pixels.size()),
                                   pixels.data()))) {
    return false;
  }

  BITMAPINFOHEADER header = {};
  header.biSize = sizeof(BITMAPINFOHEADER);
  header.biWidth = static_cast<LONG>(width);
  header.biHeight = static_cast<LONG>(height);  // bottom-up
  header.biPlanes = 1;
  header.biBitCount = 32;
  header.biCompression = BI_RGB;
  header.biSizeImage = static_cast<DWORD>(pixels.size());

  dib.resize(sizeof(header) + pixels.size());
  memcpy(dib.data(), &header, sizeof(header));
  for (UINT row = 0; row < height; ++row) {
    memcpy(dib.data() + sizeof(header) + static_cast<size_t>(row) * stride,
           pixels.data() + static_cast<size_t>(height - 1 - row) * stride,
           stride);
  }
  return true;
}

bool WriteImageToClipboard(HWND window, const std::vector<uint8_t>& png) {
  std::vector<uint8_t> dib;
  const bool have_dib = PngToDib(png, dib);

  if (!::OpenClipboard(window)) return false;
  ::EmptyClipboard();
  bool wrote = false;

  const UINT png_format = ::RegisterClipboardFormatW(L"PNG");
  if (HGLOBAL png_handle = CopyToGlobal(png.data(), png.size())) {
    if (::SetClipboardData(png_format, png_handle)) {
      wrote = true;
    } else {
      ::GlobalFree(png_handle);
    }
  }
  if (have_dib) {
    if (HGLOBAL dib_handle = CopyToGlobal(dib.data(), dib.size())) {
      if (::SetClipboardData(CF_DIB, dib_handle)) {
        wrote = true;
      } else {
        ::GlobalFree(dib_handle);
      }
    }
  }
  ::CloseClipboard();
  return wrote;
}

// Vommet issue 484: the paste side. Reads the "PNG" format (ours, browsers,
// Discord) so "Copy image" pastes back into Vommet; the pasteboard plugin
// reads only CF_DIB and uses the clipboard handle without GlobalLock, which
// loses the DIB we write. Empty when there is no PNG; Dart then falls back
// to the plugin.
std::vector<uint8_t> ReadPngFromClipboard(HWND window) {
  std::vector<uint8_t> png;
  const UINT png_format = ::RegisterClipboardFormatW(L"PNG");
  if (!png_format || !::IsClipboardFormatAvailable(png_format)) return png;
  if (!::OpenClipboard(window)) return png;
  if (HANDLE handle = ::GetClipboardData(png_format)) {
    const SIZE_T size = ::GlobalSize(handle);
    if (const void* data = ::GlobalLock(handle)) {
      const auto* bytes = static_cast<const uint8_t*>(data);
      png.assign(bytes, bytes + size);
      ::GlobalUnlock(handle);
    }
  }
  ::CloseClipboard();
  return png;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

// Vommet: whether Windows marks the internet connection as metered, for the
// automatic media download choices (Vommet issue 75). Unknown counts as not
// metered.
static bool IsMeteredConnection() {
  Microsoft::WRL::ComPtr<INetworkCostManager> manager;
  if (FAILED(::CoCreateInstance(__uuidof(NetworkListManager), nullptr,
                                CLSCTX_ALL, IID_PPV_ARGS(&manager)))) {
    return false;
  }
  DWORD cost = 0;
  if (FAILED(manager->GetCost(&cost, nullptr))) {
    return false;
  }
  if (cost == NLM_CONNECTION_COST_UNKNOWN) {
    return false;
  }
  return (cost & NLM_CONNECTION_COST_UNRESTRICTED) == 0;
}

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

  // Vommet: clipboard channel for "Copy image" and pasting PNGs.
  clipboard_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "im.nether.vommet/clipboard",
          &flutter::StandardMethodCodec::GetInstance());
  clipboard_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "readImage") {
          std::vector<uint8_t> png = ReadPngFromClipboard(GetHandle());
          if (png.empty()) {
            result->Success();
          } else {
            result->Success(flutter::EncodableValue(std::move(png)));
          }
          return;
        }
        if (call.method_name() != "writeImage") {
          result->NotImplemented();
          return;
        }
        const auto* png = std::get_if<std::vector<uint8_t>>(call.arguments());
        if (png == nullptr || png->empty()) {
          result->Error("bad_args", "expected PNG bytes");
          return;
        }
        if (WriteImageToClipboard(GetHandle(), *png)) {
          result->Success(flutter::EncodableValue(true));
        } else {
          result->Error("clipboard_failed", "could not write the clipboard");
        }
      });

  // Vommet: metered connection check for automatic media download.
  network_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "im.nether.vommet/network",
          &flutter::StandardMethodCodec::GetInstance());
  network_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "isMetered") {
          result->Success(flutter::EncodableValue(IsMeteredConnection()));
          return;
        }
        result->NotImplemented();
      });

  // Vommet issue 883: Dart quits through here instead of dart:io's exit().
  // exit() calls ExitProcess on the UI thread while the engine, the plugins
  // and WebView2 still run, and their global teardown then crashes (an
  // access violation that held up Windows shutdown). Closing the window
  // tears them down in order instead (see kQuitMessage).
  flutter_controller_->engine()->messenger()->SetMessageHandler(
      kSessionChannel,
      [this](const uint8_t* message, size_t message_size,
             flutter::BinaryReply reply) {
        const std::string text =
            message ? std::string(reinterpret_cast<const char*>(message),
                                  message_size)
                    : std::string();
        HWND window = GetHandle();
        if (text != "quit" || window == nullptr) {
          reply(nullptr, 0);
          return;
        }
        quit_requested_ = true;
        // Posted, not done here: the engine is running this handler.
        ::PostMessage(window, kQuitMessage, 0, 0);
        static const char kOk[] = "ok";
        reply(reinterpret_cast<const uint8_t*>(kOk), sizeof(kOk) - 1);
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!start_hidden_) this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  // Vommet: docked widgets (experiment), see widget_dock.h.
  WidgetDockRegister(flutter_controller_->engine()->messenger(),
                     flutter_controller_->view()->GetNativeWindow());

  // Vommet issue 632: the tray icon, see tray_icon.h.
  TrayIconRegister(flutter_controller_->engine()->messenger());

  return true;
}

void FlutterWindow::OnDestroy() {
  clipboard_channel_ = nullptr;
  network_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  WidgetDockShutdown();
  TrayIconShutdown();
  Win32Window::OnDestroy();
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
  WidgetDockOnMainWindowMessage(message);

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    // Vommet issue 331: the session is ending (logout, restart, shutdown,
    // or an installer's Restart Manager). Windows doesn't send WM_CLOSE
    // then, so tell Dart to close its clients and quit even with "Minimize
    // on close" on. lib/utils/window_management.dart listens.
    case WM_QUERYENDSESSION:
    case WM_ENDSESSION:
      if (flutter_controller_ &&
          (message == WM_QUERYENDSESSION || wparam == TRUE)) {
        static const char kEnd[] = "end";
        flutter_controller_->engine()->messenger()->Send(
            kSessionChannel,
            reinterpret_cast<const uint8_t*>(kEnd), sizeof(kEnd) - 1);
      }
      // Vommet issue 883: Windows can end the process any time after
      // WM_ENDSESSION returns, so give Dart a moment to finish closing its
      // clients (it then asks to quit) before returning.
      if (message == WM_ENDSESSION && wparam == TRUE && flutter_controller_) {
        WaitForQuitRequest(kEndSessionWaitMs);
      }
      break;
    // Vommet issue 883: Dart has closed its clients. Close the window the
    // way a plain Flutter app does: OnDestroy shuts the engine down and
    // removes the widget dock and the tray icon, then WM_DESTROY ends the
    // message loop and wWinMain returns.
    case kQuitMessage:
      ::DestroyWindow(hwnd);
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::WaitForQuitRequest(DWORD timeout_ms) {
  const ULONGLONG deadline = ::GetTickCount64() + timeout_ms;
  while (!quit_requested_) {
    const ULONGLONG now = ::GetTickCount64();
    if (now >= deadline) return;
    ::MsgWaitForMultipleObjectsEx(0, nullptr,
                                  static_cast<DWORD>(deadline - now),
                                  QS_ALLINPUT, MWMO_INPUTAVAILABLE);
    // Stops as soon as Dart asks to quit, so kQuitMessage stays queued for
    // the main loop and the window isn't destroyed inside WM_ENDSESSION.
    ::MSG msg;
    while (!quit_requested_ &&
           ::PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE)) {
      if (msg.message == WM_QUIT) {
        ::PostQuitMessage(static_cast<int>(msg.wParam));
        return;
      }
      ::TranslateMessage(&msg);
      ::DispatchMessage(&msg);
    }
  }
}

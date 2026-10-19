#include "flutter_window.h"

#include <cstring>
#include <optional>
#include <vector>

#include <flutter/standard_method_codec.h>
#include <wincodec.h>
#include <wrl/client.h>

#include "flutter/generated_plugin_registrant.h"

#pragma comment(lib, "windowscodecs.lib")

namespace {

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

}  // namespace

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

  // Vommet: clipboard channel for "Copy image".
  clipboard_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "im.nether.vommet/clipboard",
          &flutter::StandardMethodCodec::GetInstance());
  clipboard_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
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
  clipboard_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

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

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

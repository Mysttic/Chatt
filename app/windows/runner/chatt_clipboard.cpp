#include "chatt_clipboard.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <shlobj.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <cstring>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

// Obrazek rozłożony na piksele: BGRA, wiersz po wierszu od góry.
struct Bitmap {
  UINT width = 0;
  UINT height = 0;
  std::vector<uint8_t> pixels;  // 4 bajty na piksel
};

std::wstring Widen(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  const int size = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                         static_cast<int>(utf8.size()),
                                         nullptr, 0);
  std::wstring wide(size, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                        wide.data(), size);
  return wide;
}

// Dekodowanie przez WIC, czyli ten sam kodek, którego używa Eksplorator.
// Bierzemy pierwszą klatkę i wymuszamy 32bpp BGRA, żeby dalej nie zgadywać
// formatu źródła (PNG, JPEG, BMP, GIF, TIFF, HEIF, WebP zależnie od systemu).
std::optional<Bitmap> Decode(const std::wstring& path) {
  ComPtr<IWICImagingFactory> factory;
  if (FAILED(::CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&factory)))) {
    return std::nullopt;
  }

  ComPtr<IWICBitmapDecoder> decoder;
  if (FAILED(factory->CreateDecoderFromFilename(
          path.c_str(), nullptr, GENERIC_READ,
          WICDecodeMetadataCacheOnDemand, &decoder))) {
    return std::nullopt;
  }

  ComPtr<IWICBitmapFrameDecode> frame;
  if (FAILED(decoder->GetFrame(0, &frame))) {
    return std::nullopt;
  }

  ComPtr<IWICFormatConverter> converter;
  if (FAILED(factory->CreateFormatConverter(&converter)) ||
      FAILED(converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppBGRA,
                                   WICBitmapDitherTypeNone, nullptr, 0.0,
                                   WICBitmapPaletteTypeCustom))) {
    return std::nullopt;
  }

  Bitmap bitmap;
  if (FAILED(converter->GetSize(&bitmap.width, &bitmap.height)) ||
      bitmap.width == 0 || bitmap.height == 0) {
    return std::nullopt;
  }

  // Zabezpieczenie przed obrazkiem, który nie zmieści się w pamięci: 4 bajty
  // na piksel przy 2 GB to około 536 megapikseli.
  const uint64_t pixels =
      static_cast<uint64_t>(bitmap.width) * bitmap.height;
  if (pixels > 512ull * 1024 * 1024 / 4) {
    return std::nullopt;
  }

  const UINT stride = bitmap.width * 4;
  bitmap.pixels.resize(static_cast<size_t>(stride) * bitmap.height);
  if (FAILED(converter->CopyPixels(nullptr, stride,
                                   static_cast<UINT>(bitmap.pixels.size()),
                                   bitmap.pixels.data()))) {
    return std::nullopt;
  }
  return bitmap;
}

// CF_DIB: nagłówek BITMAPINFOHEADER i piksele, wiersze od dołu (dodatnia
// wysokość). Układ odwrócony (ujemna wysokość) też jest legalny, ale część
// starszych programów wkleja go do góry nogami, więc przepisujemy wiersze.
//
// Przezroczystość składamy na biało zamiast wystawiać CF_DIBV5. Kanał alfa
// w schowku jest interpretowany różnie i częstym wynikiem jest czarne tło;
// białe jest przewidywalne i tak samo wygląda w każdym programie.
HGLOBAL BuildDib(const Bitmap& bitmap) {
  const size_t stride = static_cast<size_t>(bitmap.width) * 4;
  const size_t bytes = sizeof(BITMAPINFOHEADER) + stride * bitmap.height;
  HGLOBAL handle = ::GlobalAlloc(GMEM_MOVEABLE, bytes);
  if (handle == nullptr) {
    return nullptr;
  }
  auto* target = static_cast<uint8_t*>(::GlobalLock(handle));
  if (target == nullptr) {
    ::GlobalFree(handle);
    return nullptr;
  }

  auto* header = reinterpret_cast<BITMAPINFOHEADER*>(target);
  *header = BITMAPINFOHEADER{};
  header->biSize = sizeof(BITMAPINFOHEADER);
  header->biWidth = static_cast<LONG>(bitmap.width);
  header->biHeight = static_cast<LONG>(bitmap.height);
  header->biPlanes = 1;
  header->biBitCount = 32;
  header->biCompression = BI_RGB;
  header->biSizeImage = static_cast<DWORD>(stride * bitmap.height);

  uint8_t* out = target + sizeof(BITMAPINFOHEADER);
  for (UINT y = 0; y < bitmap.height; ++y) {
    const uint8_t* src = bitmap.pixels.data() +
                         static_cast<size_t>(bitmap.height - 1 - y) * stride;
    uint8_t* dst = out + static_cast<size_t>(y) * stride;
    for (UINT x = 0; x < bitmap.width; ++x) {
      const uint8_t alpha = src[x * 4 + 3];
      for (int c = 0; c < 3; ++c) {
        const int value = src[x * 4 + c] * alpha + 255 * (255 - alpha);
        dst[x * 4 + c] = static_cast<uint8_t>(value / 255);
      }
      dst[x * 4 + 3] = 255;
    }
  }

  ::GlobalUnlock(handle);
  return handle;
}

// CF_HDROP: ta sama zawartość, tylko jako "plik skopiowany w Eksploratorze".
// Dzięki temu Ctrl+V działa też tam, gdzie wkleja się pliki, a nie obrazy.
HGLOBAL BuildDrop(const std::wstring& path) {
  const size_t chars = path.size() + 2;  // lista kończy się podwójnym zerem
  const size_t bytes = sizeof(DROPFILES) + chars * sizeof(wchar_t);
  HGLOBAL handle = ::GlobalAlloc(GMEM_MOVEABLE, bytes);
  if (handle == nullptr) {
    return nullptr;
  }
  auto* target = static_cast<uint8_t*>(::GlobalLock(handle));
  if (target == nullptr) {
    ::GlobalFree(handle);
    return nullptr;
  }

  auto* drop = reinterpret_cast<DROPFILES*>(target);
  *drop = DROPFILES{};
  drop->pFiles = sizeof(DROPFILES);
  drop->fWide = TRUE;

  auto* list = reinterpret_cast<wchar_t*>(target + sizeof(DROPFILES));
  std::memcpy(list, path.c_str(), path.size() * sizeof(wchar_t));
  list[path.size()] = L'\0';
  list[path.size() + 1] = L'\0';

  ::GlobalUnlock(handle);
  return handle;
}

// Zwraca false, gdy schowek jest zajęty przez inny proces (typowe: menedżer
// schowka w tle) albo gdy nie udało się zbudować żadnego formatu.
bool CopyImage(const std::wstring& path) {
  const auto bitmap = Decode(path);
  if (!bitmap.has_value()) {
    return false;
  }
  HGLOBAL dib = BuildDib(*bitmap);
  if (dib == nullptr) {
    return false;
  }
  HGLOBAL drop = BuildDrop(path);  // opcjonalny dodatek, brak nie przeszkadza

  if (!::OpenClipboard(nullptr)) {
    ::GlobalFree(dib);
    if (drop != nullptr) {
      ::GlobalFree(drop);
    }
    return false;
  }
  ::EmptyClipboard();

  // Po udanym SetClipboardData pamięć należy do systemu i nie wolno jej
  // zwalniać; po nieudanym dalej jest nasza.
  bool ok = ::SetClipboardData(CF_DIB, dib) != nullptr;
  if (!ok) {
    ::GlobalFree(dib);
  }
  if (drop != nullptr && ::SetClipboardData(CF_HDROP, drop) == nullptr) {
    ::GlobalFree(drop);
  }

  ::CloseClipboard();
  return ok;
}

const std::string* ArgumentPath(const EncodableValue* arguments) {
  const auto* map = std::get_if<EncodableMap>(arguments);
  if (map == nullptr) {
    return nullptr;
  }
  const auto entry = map->find(EncodableValue("path"));
  if (entry == map->end()) {
    return nullptr;
  }
  return std::get_if<std::string>(&entry->second);
}

}  // namespace

void RegisterChattClipboard(flutter::FlutterEngine* engine) {
  // Kanał żyje tyle, co proces: statyczny, bo runner nie ma gdzie go trzymać.
  static auto channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          engine->messenger(), "chatt/clipboard",
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() != "copyImage") {
          result->NotImplemented();
          return;
        }
        const std::string* path = ArgumentPath(call.arguments());
        if (path == nullptr || path->empty()) {
          result->Error("no_path", "Brak sciezki do pliku");
          return;
        }
        result->Success(EncodableValue(CopyImage(Widen(*path))));
      });
}

#include "chatt_clipboard.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <shlobj.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace {

using flutter::EncodableList;
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

std::string Narrow(const std::wstring& wide) {
  if (wide.empty()) {
    return std::string();
  }
  const int size = ::WideCharToMultiByte(CP_UTF8, 0, wide.data(),
                                         static_cast<int>(wide.size()), nullptr,
                                         0, nullptr, nullptr);
  std::string utf8(size, '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                        utf8.data(), size, nullptr, nullptr);
  return utf8;
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

// --- odczyt ze schowka ------------------------------------------------------

// Otwarcie schowka na czas jednego odczytu. OpenClipboard odbija się, gdy
// trzyma go inny proces (menedżer schowka zagląda do niego po każdym Ctrl+C),
// więc ponawiamy przez chwilę, zamiast od razu mówić "nie da się".
class ClipboardLock {
 public:
  ClipboardLock() {
    for (int attempt = 0; attempt < 10 && !open_; ++attempt) {
      open_ = ::OpenClipboard(nullptr) != 0;
      if (!open_) {
        ::Sleep(20);
      }
    }
  }
  ~ClipboardLock() {
    if (open_) {
      ::CloseClipboard();
    }
  }
  ClipboardLock(const ClipboardLock&) = delete;
  ClipboardLock& operator=(const ClipboardLock&) = delete;

  bool open() const { return open_; }

 private:
  bool open_ = false;
};

// Format "PNG" rejestrują przeglądarki i część edytorów grafiki. Jest wart
// pierwszeństwa przed bitmapą: to gotowy plik, bez zgadywania o kanale alfa.
UINT PngFormat() {
  static const UINT id = ::RegisterClipboardFormatW(L"PNG");
  return id;
}

// Kopia zawartości formatu do własnego bufora. Dokumentacja każe skopiować
// dane natychmiast: uchwyt należy do schowka i przestaje być ważny, gdy
// zawartość się zmieni. Uchwytu nie wolno zwalniać ani zostawić zablokowanego.
std::vector<uint8_t> ReadFormat(UINT format) {
  std::vector<uint8_t> bytes;
  HANDLE handle = ::GetClipboardData(format);
  if (handle == nullptr) {
    return bytes;
  }
  const size_t size = ::GlobalSize(handle);
  if (size == 0) {
    return bytes;
  }
  const auto* data = static_cast<const uint8_t*>(::GlobalLock(handle));
  if (data == nullptr) {
    return bytes;
  }
  bytes.assign(data, data + size);
  ::GlobalUnlock(handle);
  return bytes;
}

// Długość pliku PNG policzona po strukturze chunków, od sygnatury do IEND.
// GlobalSize oddaje wielkość *bloku pamięci*, która bywa większa od danych,
// więc bez tego do pliku doklejałyby się śmieci zza końca obrazka.
// Zero znaczy "to nie jest PNG".
size_t PngLength(const std::vector<uint8_t>& bytes) {
  static const uint8_t signature[8] = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1A, '\n'};
  if (bytes.size() < sizeof(signature) ||
      std::memcmp(bytes.data(), signature, sizeof(signature)) != 0) {
    return 0;
  }
  size_t offset = sizeof(signature);
  while (offset + 8 <= bytes.size()) {
    const uint8_t* chunk = bytes.data() + offset;
    const uint64_t length = (static_cast<uint64_t>(chunk[0]) << 24) |
                            (static_cast<uint64_t>(chunk[1]) << 16) |
                            (static_cast<uint64_t>(chunk[2]) << 8) |
                            static_cast<uint64_t>(chunk[3]);
    const uint64_t next = static_cast<uint64_t>(offset) + 12 + length;
    if (next > bytes.size()) {
      return 0;  // obcięty plik
    }
    if (std::memcmp(chunk + 4, "IEND", 4) == 0) {
      return static_cast<size_t>(next);
    }
    offset = static_cast<size_t>(next);
  }
  return 0;
}

// Widok na spakowany DIB: gdzie są piksele, w którą stronę idą wiersze i czy
// nagłówek w ogóle deklaruje kanał alfa.
struct DibView {
  const uint8_t* bits = nullptr;
  size_t stride = 0;
  UINT width = 0;
  UINT height = 0;
  WORD depth = 0;
  bool bottom_up = true;
  bool declares_alpha = false;
};

std::optional<DibView> ViewDib(const std::vector<uint8_t>& bytes) {
  if (bytes.size() < sizeof(BITMAPINFOHEADER)) {
    return std::nullopt;
  }
  const uint8_t* data = bytes.data();
  const auto* header = reinterpret_cast<const BITMAPINFOHEADER*>(data);
  const size_t header_size = header->biSize;
  if (header_size < sizeof(BITMAPINFOHEADER) || header_size > bytes.size() ||
      header->biPlanes != 1 || header->biWidth <= 0 || header->biHeight == 0) {
    return std::nullopt;
  }
  // Tylko 24 i 32 bity na piksel. Paleta i 16 bitów to dziś muzeum, a każdy
  // z tych układów to osobna ścieżka, którą nie ma jak sprawdzić.
  if (header->biBitCount != 24 && header->biBitCount != 32) {
    return std::nullopt;
  }
  if (header->biCompression != BI_RGB &&
      header->biCompression != BI_BITFIELDS) {
    return std::nullopt;  // RLE, BI_JPEG, BI_PNG: nie nasz przypadek
  }

  // Maski kanałów zaczynają się zawsze od bajtu 40: albo są częścią nagłówka
  // V4/V5, albo dopisane za gołym BITMAPINFOHEADER. Bierzemy wyłącznie układ
  // BGRA; przy innym przepisanie na ślepo dałoby obrazek z zamienionym
  // czerwonym i niebieskim, więc lepiej nie wklejać nic.
  if (header->biCompression == BI_BITFIELDS) {
    if (bytes.size() < 40 + 3 * sizeof(DWORD)) {
      return std::nullopt;
    }
    const auto* masks = reinterpret_cast<const DWORD*>(data + 40);
    if (masks[0] != 0x00FF0000u || masks[1] != 0x0000FF00u ||
        masks[2] != 0x000000FFu) {
      return std::nullopt;
    }
  }

  DibView view;
  view.depth = header->biBitCount;
  view.width = static_cast<UINT>(header->biWidth);
  view.bottom_up = header->biHeight > 0;
  view.height = static_cast<UINT>(
      view.bottom_up ? header->biHeight
                     : -static_cast<int64_t>(header->biHeight));
  // Maska alfy jest jedynym śladem w danych, że źródło w ogóle miało zamiar
  // wystawić przezroczystość. Przy BI_RGB górny bajt jest udokumentowany jako
  // nieużywany i u wielu programów jest zerem: przepisany wprost dałby obrazek
  // całkiem przezroczysty.
  if (header_size >= 56 && header->biBitCount == 32) {
    view.declares_alpha =
        *reinterpret_cast<const DWORD*>(data + 52) == 0xFF000000u;
  }

  // Wiersz zawsze dobity do czterech bajtów, nie do szerokości razy głębia.
  view.stride =
      ((static_cast<size_t>(view.width) * header->biBitCount + 31) / 32) * 4;
  const uint64_t needed = static_cast<uint64_t>(view.stride) * view.height;
  if (needed == 0 || needed > 512ull * 1024 * 1024 || needed > bytes.size()) {
    return std::nullopt;
  }

  // Gdzie zaczynają się piksele. Konwencje się różnią i nie da się ich
  // wyczytać z nagłówka: CF_DIBV5 dorobiony przez system z gołej bitmapy ma
  // maski i w nagłówku (124 bajty), i jeszcze raz za nim; nagłówki 52-
  // i 56-bajtowe liczą je w biSize; a za nagłówkiem bywa jeszcze tablica
  // kolorów, legalna także przy 24 i 32 bitach. Zamiast zgadywać, wypisujemy
  // wszystkie możliwe początki i bierzemy ten, przy którym piksele kończą się
  // dokładnie na końcu bufora.
  //
  // Paleta większa niż 256 pozycji nie istnieje; taka liczba znaczy, że
  // nagłówek jest zmyślony.
  if (header->biClrUsed > 256) {
    return std::nullopt;
  }
  const size_t colors = static_cast<size_t>(header->biClrUsed) * sizeof(RGBQUAD);
  const size_t masks = 3 * sizeof(DWORD);
  size_t candidates[4];
  int count = 0;
  candidates[count++] = header_size;
  if (colors != 0) candidates[count++] = header_size + colors;
  if (header->biCompression == BI_BITFIELDS) {
    candidates[count++] = header_size + masks;
    if (colors != 0) candidates[count++] = header_size + colors + masks;
  }

  const size_t space = bytes.size() - static_cast<size_t>(needed);
  size_t offset = bytes.size();
  for (int i = 0; i < count; ++i) {
    if (candidates[i] == space) {
      offset = candidates[i];
      break;
    }
    // Bufor bywa większy od zawartości (GlobalSize podaje wielkość bloku),
    // więc gdy nic nie pasuje co do bajtu, zostaje najdalszy, który się mieści.
    if (candidates[i] <= space && (offset > space || candidates[i] > offset)) {
      offset = candidates[i];
    }
  }
  if (offset > space) {
    return std::nullopt;
  }
  view.bits = data + offset;
  return view;
}

// DIB -> Bitmap (BGRA, od góry). Tutaj rozstrzyga się kanał alfa, bo to
// jedyne miejsce, gdzie widać nagłówek i piksele naraz.
std::optional<Bitmap> DibToBitmap(const DibView& view) {
  Bitmap bitmap;
  bitmap.width = view.width;
  bitmap.height = view.height;
  bitmap.pixels.resize(static_cast<size_t>(view.width) * view.height * 4);

  const size_t out_stride = static_cast<size_t>(view.width) * 4;
  const size_t in_pixel = view.depth == 32 ? 4 : 3;
  for (UINT y = 0; y < view.height; ++y) {
    const size_t row = view.bottom_up ? (view.height - 1 - y) : y;
    const uint8_t* src = view.bits + row * view.stride;
    uint8_t* dst = bitmap.pixels.data() + y * out_stride;
    for (UINT x = 0; x < view.width; ++x) {
      dst[x * 4 + 0] = src[x * in_pixel + 0];
      dst[x * 4 + 1] = src[x * in_pixel + 1];
      dst[x * 4 + 2] = src[x * in_pixel + 2];
      dst[x * 4 + 3] =
          view.declares_alpha ? src[x * in_pixel + 3] : 255;
    }
  }

  if (!view.declares_alpha) {
    return bitmap;
  }

  // Zadeklarowana maska alfy przy pustym kanale znaczy "brak przezroczystości",
  // a nie "obrazek niewidoczny".
  bool any_alpha = false;
  for (size_t i = 3; i < bitmap.pixels.size() && !any_alpha; i += 4) {
    any_alpha = bitmap.pixels[i] != 0;
  }
  if (!any_alpha) {
    for (size_t i = 3; i < bitmap.pixels.size(); i += 4) {
      bitmap.pixels[i] = 255;
    }
    return bitmap;
  }

  // Przeglądarki wystawiają alfę pomnożoną przez kolor, a nagłówek tego nie
  // mówi. Poznać to po tym, że żadna składowa nie przekracza alfy; na obrazku
  // bez przezroczystości ten warunek i tak nic nie zmienia, bo piksele
  // całkiem kryjące i całkiem puste zostawiamy w spokoju.
  bool premultiplied = true;
  for (size_t i = 0; i < bitmap.pixels.size() && premultiplied; i += 4) {
    const uint8_t alpha = bitmap.pixels[i + 3];
    premultiplied = bitmap.pixels[i] <= alpha &&
                    bitmap.pixels[i + 1] <= alpha &&
                    bitmap.pixels[i + 2] <= alpha;
  }
  if (premultiplied) {
    for (size_t i = 0; i < bitmap.pixels.size(); i += 4) {
      const uint8_t alpha = bitmap.pixels[i + 3];
      if (alpha == 0 || alpha == 255) {
        continue;
      }
      for (int c = 0; c < 3; ++c) {
        bitmap.pixels[i + c] = static_cast<uint8_t>(
            (bitmap.pixels[i + c] * 255 + alpha / 2) / alpha);
      }
    }
  }
  return bitmap;
}

// Bitmap (BGRA, od góry) -> plik PNG. 32bppBGRA jest własnym formatem kodera
// PNG, więc SetPixelFormat nie ma powodu go podmienić; gdyby podmienił,
// zapisalibyśmy śmieci, dlatego sprawdzamy, co wyszło.
bool SavePng(Bitmap& bitmap, const std::wstring& path) {
  ComPtr<IWICImagingFactory> factory;
  if (FAILED(::CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&factory)))) {
    return false;
  }
  ComPtr<IWICStream> stream;
  if (FAILED(factory->CreateStream(&stream)) ||
      FAILED(stream->InitializeFromFilename(path.c_str(), GENERIC_WRITE))) {
    return false;
  }
  ComPtr<IWICBitmapEncoder> encoder;
  if (FAILED(factory->CreateEncoder(GUID_ContainerFormatPng, nullptr,
                                    &encoder)) ||
      FAILED(encoder->Initialize(stream.Get(), WICBitmapEncoderNoCache))) {
    return false;
  }
  ComPtr<IWICBitmapFrameEncode> frame;
  if (FAILED(encoder->CreateNewFrame(&frame, nullptr)) ||
      FAILED(frame->Initialize(nullptr)) ||
      FAILED(frame->SetSize(bitmap.width, bitmap.height))) {
    return false;
  }
  WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
  if (FAILED(frame->SetPixelFormat(&format)) ||
      !IsEqualGUID(format, GUID_WICPixelFormat32bppBGRA)) {
    return false;
  }
  if (FAILED(frame->WritePixels(bitmap.height, bitmap.width * 4,
                                static_cast<UINT>(bitmap.pixels.size()),
                                bitmap.pixels.data())) ||
      FAILED(frame->Commit()) || FAILED(encoder->Commit())) {
    return false;
  }
  return true;
}

// Ścieżka na obrazek ze schowka: <TEMP>\chatt\wklejone\<chwila>-<licznik>\<nazwa>.
// Osobny katalog na każdy plik, bo dwa zrzuty ekranu nazywają się tak samo.
std::optional<std::wstring> ScratchPath(const std::wstring& name) {
  // Nazwa przychodzi z tłumaczeń, więc jest nasza, ale sprawdzamy ją i tak:
  // to jedyne miejsce, gdzie napis staje się tutaj ścieżką.
  if (name.empty() || name == L"." || name == L".." ||
      name.find_first_of(L"\\/:*?\"<>|") != std::wstring::npos) {
    return std::nullopt;
  }
  wchar_t temp[MAX_PATH + 1];
  const DWORD length = ::GetTempPathW(MAX_PATH + 1, temp);
  if (length == 0 || length > MAX_PATH) {
    return std::nullopt;
  }

  // GetTempPathW nie sprawdza, czy katalog istnieje i czy da się w nim pisać,
  // więc każdy poziom zakładamy sami i godzimy się na "już jest".
  static ULONGLONG counter = 0;
  const std::wstring steps[3] = {
      L"chatt",
      L"wklejone",
      std::to_wstring(::GetTickCount64()) + L"-" + std::to_wstring(++counter),
  };
  std::wstring dir(temp, length);
  for (const std::wstring& step : steps) {
    dir += step;
    dir += L'\\';
    if (!::CreateDirectoryW(dir.c_str(), nullptr) &&
        ::GetLastError() != ERROR_ALREADY_EXISTS) {
      return std::nullopt;
    }
  }
  return dir + name;
}

bool WriteAllBytes(const std::wstring& path, const uint8_t* data, size_t size) {
  HANDLE file = ::CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return false;
  }
  bool ok = true;
  size_t written = 0;
  while (ok && written < size) {
    const DWORD chunk =
        static_cast<DWORD>(std::min<size_t>(size - written, 1u << 20));
    DWORD done = 0;
    ok = ::WriteFile(file, data + written, chunk, &done, nullptr) != 0 &&
         done == chunk;
    written += done;
  }
  ::CloseHandle(file);
  if (!ok) {
    ::DeleteFileW(path.c_str());  // plik w połowie nie ma prawa pójść dalej
  }
  return ok;
}

// Czy w schowku jest obrazek, i to obrazek sam dla siebie.
//
// Zaznaczony fragment arkusza albo dokumentu jedzie do schowka razem
// z bitmapą: Excel, Word i LibreOffice wystawiają obok napisu obrazek, a gdy
// wystawią gołą bitmapę, system dorabia z niej jeszcze CF_DIB. Gdyby liczyła
// się sama obecność bitmapy, Ctrl+V po skopiowaniu komórek wysyłałby
// rozmówcy ich zrzut, o który nikt nie prosił. Dlatego napis w schowku
// wygrywa: zostaje zwykłym wklejeniem tekstu.
//
// Plików z Eksploratora to nie dotyczy, tam napisu nie ma.
bool HasImage() {
  if (::IsClipboardFormatAvailable(CF_UNICODETEXT) ||
      ::IsClipboardFormatAvailable(CF_TEXT)) {
    return false;
  }
  return ::IsClipboardFormatAvailable(CF_DIB) ||
         ::IsClipboardFormatAvailable(PngFormat());
}

// Czy jest co wklejać. Bez otwierania schowka: IsClipboardFormatAvailable
// tego nie wymaga, a widzi też formaty, które system dorabia sam.
bool HasFiles() {
  return ::IsClipboardFormatAvailable(CF_HDROP) || HasImage();
}

// Ścieżki do wysłania. Pliki skopiowane w Eksploratorze idą wprost, bez
// kopiowania: leżą już na dysku i nikt ich spod nas nie zabierze. Obrazek bez
// pliku źródłowego trzeba najpierw zapisać, i to jako PNG, bo dokładnie tym
// jest zrzut ekranu.
std::vector<std::wstring> PasteFiles(const std::wstring& name) {
  std::vector<std::wstring> paths;
  std::vector<uint8_t> bytes;
  bool ready_png = false;

  {
    ClipboardLock clipboard;
    if (!clipboard.open()) {
      return paths;
    }

    if (::IsClipboardFormatAvailable(CF_HDROP)) {
      auto drop = static_cast<HDROP>(::GetClipboardData(CF_HDROP));
      if (drop == nullptr) {
        return paths;
      }
      const UINT count = ::DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
      for (UINT i = 0; i < count; ++i) {
        const UINT length = ::DragQueryFileW(drop, i, nullptr, 0);
        if (length == 0) {
          continue;
        }
        std::wstring path(length + 1, L'\0');  // zwrot nie liczy zera na końcu
        const UINT copied = ::DragQueryFileW(drop, i, path.data(), length + 1);
        if (copied == 0) {
          continue;
        }
        path.resize(copied);
        paths.push_back(std::move(path));
      }
      return paths;
    }

    if (!HasImage()) {
      return paths;  // pusty schowek albo zaznaczony tekst z bitmapą w tle
    }
    if (::IsClipboardFormatAvailable(PngFormat())) {
      bytes = ReadFormat(PngFormat());
      const size_t png = PngLength(bytes);
      if (png == 0) {
        bytes.clear();  // format "PNG" bez PNG w środku: idziemy po bitmapę
      } else {
        bytes.resize(png);
        ready_png = true;
      }
    }
    if (bytes.empty()) {
      const UINT format = ::IsClipboardFormatAvailable(CF_DIBV5) ? CF_DIBV5
                          : ::IsClipboardFormatAvailable(CF_DIB) ? CF_DIB
                                                                 : 0;
      if (format != 0) {
        bytes = ReadFormat(format);
      }
    }
  }
  // Schowek zamknięty. Kodowanie i zapis potrafią potrwać, a przez ten czas
  // żaden inny program nie mógłby kopiować ani wklejać.

  if (bytes.empty()) {
    return paths;
  }
  const auto path = ScratchPath(name);
  if (!path.has_value()) {
    return paths;
  }

  bool ok = false;
  if (ready_png) {
    ok = WriteAllBytes(*path, bytes.data(), bytes.size());
  } else {
    const auto view = ViewDib(bytes);
    if (view.has_value()) {
      auto bitmap = DibToBitmap(*view);
      ok = bitmap.has_value() && SavePng(*bitmap, *path);
    }
  }
  if (ok) {
    paths.push_back(*path);
  }
  return paths;
}

const std::string* Argument(const EncodableValue* arguments,
                            const char* name) {
  const auto* map = std::get_if<EncodableMap>(arguments);
  if (map == nullptr) {
    return nullptr;
  }
  const auto entry = map->find(EncodableValue(name));
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
        const std::string& method = call.method_name();

        if (method == "copyImage") {
          const std::string* path = Argument(call.arguments(), "path");
          if (path == nullptr || path->empty()) {
            result->Error("no_path", "Brak sciezki do pliku");
            return;
          }
          result->Success(EncodableValue(CopyImage(Widen(*path))));
          return;
        }

        if (method == "hasFiles") {
          result->Success(EncodableValue(HasFiles()));
          return;
        }

        if (method == "pasteFiles") {
          const std::string* name = Argument(call.arguments(), "name");
          if (name == nullptr || name->empty()) {
            result->Error("no_name", "Brak nazwy dla obrazka");
            return;
          }
          EncodableList list;
          for (const std::wstring& path : PasteFiles(Widen(*name))) {
            list.push_back(EncodableValue(Narrow(path)));
          }
          result->Success(EncodableValue(std::move(list)));
          return;
        }

        result->NotImplemented();
      });
}

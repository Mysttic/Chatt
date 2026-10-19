#include "chatt_links.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <shellapi.h>

#include <cctype>
#include <cstdint>
#include <memory>
#include <string>
#include <string_view>
#include <variant>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

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

bool StartsWithNoCase(const std::string& text, std::string_view prefix) {
  if (text.size() < prefix.size()) {
    return false;
  }
  for (size_t i = 0; i < prefix.size(); ++i) {
    const char c =
        static_cast<char>(std::tolower(static_cast<unsigned char>(text[i])));
    if (c != prefix[i]) {
      return false;
    }
  }
  return true;
}

// Wylacznie adresy stron. Dart sprawdza schemat juz wczesniej, a tu drugi
// raz, bo to ostatnie miejsce przed systemem: ShellExecute otworzy tez file:,
// ms-settings: i wszystko, co ma w systemie zarejestrowana obsluge. Znaki
// sterujace odpadaja razem z calym adresem.
bool IsWebAddress(const std::string& url) {
  if (!StartsWithNoCase(url, "http://") && !StartsWithNoCase(url, "https://")) {
    return false;
  }
  for (const char c : url) {
    const auto code = static_cast<unsigned char>(c);
    if (code < 0x20 || code == 0x7f) {
      return false;
    }
  }
  return true;
}

// Wczesniej adres szedl jako argument explorer.exe, a explorer dzieli swoj
// wiersz polecen na przecinkach i znakach rownosci: odnosnik z
// "?client=desktop_app" otwieral folder Dokumenty zamiast przegladarki.
bool OpenUrl(const std::string& url) {
  if (!IsWebAddress(url)) {
    return false;
  }
  const std::wstring wide = Widen(url);
  const HINSTANCE result = ::ShellExecuteW(nullptr, L"open", wide.c_str(),
                                           nullptr, nullptr, SW_SHOWNORMAL);
  // Wartosc ponizej 33 to kod bledu (dokumentacja ShellExecute).
  return reinterpret_cast<INT_PTR>(result) > 32;
}

}  // namespace

void RegisterChattLinks(flutter::FlutterEngine* engine) {
  static auto channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          engine->messenger(), "chatt/links",
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() != "openUrl") {
          result->NotImplemented();
          return;
        }
        const auto* arguments = std::get_if<EncodableMap>(call.arguments());
        if (arguments == nullptr) {
          result->Error("no_data", "Brak parametrow");
          return;
        }
        const auto entry = arguments->find(EncodableValue("url"));
        if (entry == arguments->end()) {
          result->Error("no_data", "Brak parametru url");
          return;
        }
        const auto* url = std::get_if<std::string>(&entry->second);
        if (url == nullptr) {
          result->Error("no_data", "Parametr url nie jest napisem");
          return;
        }
        result->Success(EncodableValue(OpenUrl(*url)));
      });
}

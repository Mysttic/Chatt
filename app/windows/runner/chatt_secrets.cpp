#include "chatt_secrets.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <dpapi.h>

#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

// Dodatkowa "sól" DPAPI: bez niej blob odwinie każdy proces tego samego
// użytkownika. To nie jest sekret (leży w binarce), tylko odgrodzenie od
// przypadkowego cudzego CryptUnprotectData.
const char kEntropy[] = "chatt/klucz-bazy";

DATA_BLOB Entropy() {
  DATA_BLOB blob{};
  blob.cbData = static_cast<DWORD>(sizeof(kEntropy) - 1);
  blob.pbData = reinterpret_cast<BYTE*>(const_cast<char*>(kEntropy));
  return blob;
}

// Zwraca pusty optional, gdy DPAPI odmówi — najczęściej dlatego, że blob
// powstał na innym koncie albo innym komputerze.
std::optional<std::vector<uint8_t>> Transform(const std::vector<uint8_t>& data,
                                              bool protect) {
  DATA_BLOB in{};
  in.cbData = static_cast<DWORD>(data.size());
  in.pbData = reinterpret_cast<BYTE*>(const_cast<uint8_t*>(data.data()));

  DATA_BLOB entropy = Entropy();
  DATA_BLOB out{};
  const BOOL ok =
      protect ? CryptProtectData(&in, nullptr, &entropy, nullptr, nullptr,
                                 CRYPTPROTECT_UI_FORBIDDEN, &out)
              : CryptUnprotectData(&in, nullptr, &entropy, nullptr, nullptr,
                                   CRYPTPROTECT_UI_FORBIDDEN, &out);
  if (!ok) {
    return std::nullopt;
  }

  std::vector<uint8_t> result(out.pbData, out.pbData + out.cbData);
  SecureZeroMemory(out.pbData, out.cbData);
  LocalFree(out.pbData);
  return result;
}

const std::vector<uint8_t>* ArgumentData(const EncodableValue* arguments) {
  const auto* map = std::get_if<EncodableMap>(arguments);
  if (map == nullptr) {
    return nullptr;
  }
  const auto entry = map->find(EncodableValue("data"));
  if (entry == map->end()) {
    return nullptr;
  }
  return std::get_if<std::vector<uint8_t>>(&entry->second);
}

}  // namespace

void RegisterChattSecrets(flutter::FlutterEngine* engine) {
  // Kanał żyje tyle, co proces: statyczny, bo runner nie ma gdzie go trzymać.
  static auto channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          engine->messenger(), "chatt/sekrety",
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        const bool protect = call.method_name() == "protect";
        if (!protect && call.method_name() != "unprotect") {
          result->NotImplemented();
          return;
        }

        const std::vector<uint8_t>* data = ArgumentData(call.arguments());
        if (data == nullptr) {
          result->Error("no_data", "Brak danych");
          return;
        }

        auto transformed = Transform(*data, protect);
        if (!transformed.has_value()) {
          result->Error("dpapi", "DPAPI odmowilo przetworzenia danych");
          return;
        }
        result->Success(EncodableValue(*transformed));
      });
}

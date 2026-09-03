#include "chatt_autostart.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <string>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kValueName[] = L"Chatt";

// Aplikacja podniesiona przez system startuje schowana do zasobnika. Bez tego
// każde włączenie komputera kończyłoby się oknem na środku ekranu.
constexpr wchar_t kHiddenArgument[] = L" --minimized";

// Ścieżka do pliku .exe w cudzysłowie: bez niego Windows gubi ścieżkę ze
// spacjami i po restarcie nic się nie uruchamia.
std::wstring CommandLine() {
  wchar_t path[MAX_PATH];
  const DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
  if (length == 0 || length == MAX_PATH) {
    return std::wstring();
  }
  return L"\"" + std::wstring(path, length) + L"\"" + kHiddenArgument;
}

bool IsEnabled() {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_READ, &key) !=
      ERROR_SUCCESS) {
    return false;
  }
  const LSTATUS status =
      RegQueryValueExW(key, kValueName, nullptr, nullptr, nullptr, nullptr);
  RegCloseKey(key);
  return status == ERROR_SUCCESS;
}

bool SetEnabled(bool enabled) {
  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kRunKey, 0, KEY_SET_VALUE, &key) !=
      ERROR_SUCCESS) {
    return false;
  }

  LSTATUS status;
  if (enabled) {
    const std::wstring command = CommandLine();
    if (command.empty()) {
      RegCloseKey(key);
      return false;
    }
    status = RegSetValueExW(
        key, kValueName, 0, REG_SZ,
        reinterpret_cast<const BYTE*>(command.c_str()),
        static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  } else {
    status = RegDeleteValueW(key, kValueName);
    // Skasowanie czegoś, czego nie ma, to też stan „wyłączone".
    if (status == ERROR_FILE_NOT_FOUND) {
      status = ERROR_SUCCESS;
    }
  }
  RegCloseKey(key);
  return status == ERROR_SUCCESS;
}

}  // namespace

void RegisterChattAutostart(flutter::FlutterEngine* engine) {
  static auto channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          engine->messenger(), "chatt/autostart",
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() == "get") {
          result->Success(EncodableValue(IsEnabled()));
          return;
        }
        if (call.method_name() != "set") {
          result->NotImplemented();
          return;
        }

        const auto* arguments = std::get_if<EncodableMap>(call.arguments());
        if (arguments == nullptr) {
          result->Error("no_data", "Brak parametrow");
          return;
        }
        const auto entry = arguments->find(EncodableValue("enabled"));
        if (entry == arguments->end()) {
          result->Error("no_data", "Brak parametru enabled");
          return;
        }
        const auto* enabled = std::get_if<bool>(&entry->second);
        if (enabled == nullptr) {
          result->Error("no_data", "Parametr enabled nie jest logiczny");
          return;
        }
        result->Success(EncodableValue(SetEnabled(*enabled)));
      });
}

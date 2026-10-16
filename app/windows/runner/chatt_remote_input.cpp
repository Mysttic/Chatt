#include "chatt_remote_input.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <dwmapi.h>
#include <timeapi.h>
#include <uiautomation.h>
#include <wrl/client.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cwchar>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

// --- Napisy ----------------------------------------------------------------

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

std::wstring BaseName(const std::wstring& path) {
  const size_t slash = path.find_last_of(L"\\/");
  return slash == std::wstring::npos ? path : path.substr(slash + 1);
}

// --- Cel: dokąd trafi pisanie ----------------------------------------------

struct Target {
  bool active = false;
  bool own_app = false;
  // Na wierzchu okno tego właśnie procesu.
  bool own_window = false;
  bool locked = false;
  bool elevated = false;
  std::string field = "none";
  std::string app;
  std::string app_label;
};

// Okno samego Chatta chwilowo bez pisania (ustawia Dart przez holdOwnApp):
// wisi karta z pytaniem, której zdalny Enter nie ma prawa odpowiedzieć, albo
// to urządzenie samo pisze na innym, a jego ekran pisania odesłałby wpisany
// tekst dalej.
std::atomic<bool> g_hold_own{false};

// Rośnie przy Stopie i końcu zgody: paczka, która jeszcze się wpisuje,
// urywa się przy następnym znaku.
std::atomic<uint32_t> g_typing_generation{0};

// Ekran blokady i okno UAC to osobne pulpity. Do nich SendInput nie sięga,
// a przy zablokowanym ekranie OpenInputDesktop w ogóle się nie udaje.
bool InputDesktopIsDefault() {
  HDESK desktop = ::OpenInputDesktop(0, FALSE, DESKTOP_READOBJECTS);
  if (desktop == nullptr) {
    return false;
  }
  wchar_t name[64] = {};
  DWORD needed = 0;
  const BOOL ok = ::GetUserObjectInformationW(desktop, UOI_NAME, name,
                                              sizeof(name), &needed);
  ::CloseDesktop(desktop);
  return ok && ::_wcsicmp(name, L"Default") == 0;
}

std::wstring ImagePath(DWORD pid) {
  HANDLE process =
      ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process == nullptr) {
    return std::wstring();
  }
  wchar_t path[MAX_PATH * 2] = {};
  DWORD size = static_cast<DWORD>(sizeof(path) / sizeof(path[0]));
  const BOOL ok = ::QueryFullProcessImageNameW(process, 0, path, &size);
  ::CloseHandle(process);
  return ok ? std::wstring(path, size) : std::wstring();
}

// Poziom integralności procesu (RID z SECURITY_MANDATORY_*). Zero znaczy, że
// nie dało się go odczytać.
DWORD IntegrityOf(HANDLE process) {
  HANDLE token = nullptr;
  if (!::OpenProcessToken(process, TOKEN_QUERY, &token)) {
    return 0;
  }
  DWORD size = 0;
  ::GetTokenInformation(token, TokenIntegrityLevel, nullptr, 0, &size);
  std::vector<uint8_t> buffer(size);
  DWORD level = 0;
  if (size > 0 && ::GetTokenInformation(token, TokenIntegrityLevel,
                                        buffer.data(), size, &size)) {
    const auto* label =
        reinterpret_cast<const TOKEN_MANDATORY_LABEL*>(buffer.data());
    const UCHAR count = *::GetSidSubAuthorityCount(label->Label.Sid);
    if (count > 0) {
      level = *::GetSidSubAuthority(label->Label.Sid, count - 1);
    }
  }
  ::CloseHandle(token);
  return level;
}

DWORD OwnIntegrity() {
  static const DWORD level = IntegrityOf(::GetCurrentProcess());
  return level;
}

// Czy SendInput dotrze do tego procesu. UIPI odcina okna o wyższym poziomie
// integralności (uruchomione jako administrator) i nie zgłasza tego ani
// wynikiem, ani w GetLastError, więc trzeba sprawdzić to samemu. Proces,
// którego żetonu nie da się nawet odczytać, też traktujemy jak wyższy.
bool IsElevatedAboveUs(DWORD pid) {
  HANDLE process =
      ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (process == nullptr) {
    return true;
  }
  const DWORD level = IntegrityOf(process);
  ::CloseHandle(process);
  return level == 0 || level > OwnIntegrity();
}

// Nazwa programu do pokazania: opis pliku z zasobu wersji, a gdy go nie ma,
// nazwa pliku bez rozszerzenia. Tytułu okna świadomie nie bierzemy: niesie
// treść (nazwę dokumentu, temat wiadomości), a tej nadawca nie dostaje.
std::wstring ProgramName(const std::wstring& path) {
  std::wstring name = BaseName(path);
  const size_t dot = name.find_last_of(L'.');
  if (dot != std::wstring::npos) {
    name = name.substr(0, dot);
  }
  DWORD ignored = 0;
  const DWORD size = ::GetFileVersionInfoSizeW(path.c_str(), &ignored);
  if (size == 0) {
    return name;
  }
  std::vector<uint8_t> data(size);
  if (!::GetFileVersionInfoW(path.c_str(), 0, size, data.data())) {
    return name;
  }
  struct Translation {
    WORD language;
    WORD code_page;
  };
  Translation* translations = nullptr;
  UINT length = 0;
  if (!::VerQueryValueW(data.data(), L"\\VarFileInfo\\Translation",
                        reinterpret_cast<void**>(&translations), &length) ||
      length < sizeof(Translation)) {
    return name;
  }
  wchar_t query[64] = {};
  ::swprintf_s(query, L"\\StringFileInfo\\%04x%04x\\FileDescription",
               translations[0].language, translations[0].code_page);
  wchar_t* description = nullptr;
  if (!::VerQueryValueW(data.data(), query,
                        reinterpret_cast<void**>(&description), &length) ||
      description == nullptr || length <= 1) {
    return name;
  }
  return std::wstring(description);
}

struct ChildSearch {
  DWORD frame_pid;
  DWORD found_pid;
};

// Aplikacje ze Sklepu stoją za oknem ApplicationFrameHost.exe, a prawdziwy
// proces siedzi w oknie potomnym. Bez tego każda z nich nazywałaby się
// „Application Frame Host".
DWORD RealProcess(HWND window, DWORD pid, const std::wstring& image) {
  if (::_wcsicmp(BaseName(image).c_str(), L"ApplicationFrameHost.exe") != 0) {
    return pid;
  }
  ChildSearch search{pid, 0};
  ::EnumChildWindows(
      window,
      [](HWND child, LPARAM param) -> BOOL {
        auto* state = reinterpret_cast<ChildSearch*>(param);
        DWORD child_pid = 0;
        ::GetWindowThreadProcessId(child, &child_pid);
        if (child_pid != 0 && child_pid != state->frame_pid) {
          state->found_pid = child_pid;
          return FALSE;
        }
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&search));
  return search.found_pid != 0 ? search.found_pid : pid;
}

std::wstring OwnExeName() {
  wchar_t path[MAX_PATH * 2] = {};
  const DWORD size = ::GetModuleFileNameW(
      nullptr, path, static_cast<DWORD>(sizeof(path) / sizeof(path[0])));
  return BaseName(std::wstring(path, size));
}

// --- UI Automation w osobnym wątku -------------------------------------------
//
// Pytanie o rodzaj pola idzie do aplikacji, która ma fokus. Zawieszona
// aplikacja potrafi nie odpowiadać, więc pytamy z osobnego wątku z własnym
// COM (MTA) i krótkimi limitami IUIAutomation2, a wątek platformy czeka na
// wynik najwyżej chwilę. Gdy wątek dalej siedzi nad poprzednim pytaniem,
// odpowiedzią jest od razu "none".

struct UiaState {
  std::mutex mutex;
  std::condition_variable wake;
  std::condition_variable done;
  uint64_t asked = 0;
  uint64_t answered = 0;
  std::string field = "none";
  bool started = false;
};

UiaState& Uia() {
  static UiaState state;
  return state;
}

std::string FocusedField(IUIAutomation* automation) {
  if (automation == nullptr) {
    return "none";
  }
  ComPtr<IUIAutomationElement> element;
  if (FAILED(automation->GetFocusedElement(&element)) || !element) {
    return "none";
  }
  BOOL password = FALSE;
  if (SUCCEEDED(element->get_CurrentIsPassword(&password)) && password) {
    return "password";
  }
  CONTROLTYPEID type = 0;
  if (FAILED(element->get_CurrentControlType(&type))) {
    return "none";
  }
  if (type == UIA_EditControlTypeId || type == UIA_DocumentControlTypeId) {
    return "text";
  }
  return "none";
}

void UiaLoop() {
  ::CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  ComPtr<IUIAutomation> automation;
  ComPtr<IUIAutomation2> automation2;
  if (SUCCEEDED(::CoCreateInstance(__uuidof(CUIAutomation8), nullptr,
                                   CLSCTX_INPROC_SERVER,
                                   IID_PPV_ARGS(&automation2)))) {
    automation2->put_ConnectionTimeout(400);
    automation2->put_TransactionTimeout(400);
    automation = automation2;
  } else {
    ::CoCreateInstance(__uuidof(CUIAutomation), nullptr, CLSCTX_INPROC_SERVER,
                       IID_PPV_ARGS(&automation));
  }
  UiaState& state = Uia();
  for (;;) {
    uint64_t number = 0;
    {
      std::unique_lock<std::mutex> lock(state.mutex);
      state.wake.wait(lock, [&state] { return state.asked != state.answered; });
      number = state.asked;
    }
    const std::string field = FocusedField(automation.Get());
    {
      std::lock_guard<std::mutex> lock(state.mutex);
      state.field = field;
      state.answered = number;
    }
    state.done.notify_all();
  }
}

std::string QueryField() {
  UiaState& state = Uia();
  std::unique_lock<std::mutex> lock(state.mutex);
  if (!state.started) {
    state.started = true;
    std::thread(UiaLoop).detach();
  }
  if (state.asked != state.answered) {
    return "none";
  }
  const uint64_t number = ++state.asked;
  state.wake.notify_one();
  if (!state.done.wait_for(lock, std::chrono::milliseconds(600),
                           [&state, number] {
                             return state.answered >= number;
                           })) {
    return "none";
  }
  return state.field;
}

Target ReadTarget(bool with_field) {
  Target target;
  if (!InputDesktopIsDefault()) {
    target.locked = true;
    return target;
  }
  HWND window = ::GetForegroundWindow();
  if (window == nullptr) {
    return target;
  }
  DWORD pid = 0;
  ::GetWindowThreadProcessId(window, &pid);
  pid = RealProcess(window, pid, ImagePath(pid));
  const std::wstring path = ImagePath(pid);
  const std::wstring name = BaseName(path);
  target.app = Narrow(name);
  target.app_label = path.empty() ? std::string() : Narrow(ProgramName(path));
  // Każda instancja Chatta. Pisać w niej wolno jak w każdym innym oknie,
  // a karty z pytaniem chroni Dart: przy wiszącej karcie nic się nie wpisuje.
  // Nadawca dostaje tylko informację, że na wierzchu jest Chatt.
  target.own_window = pid == ::GetCurrentProcessId();
  target.own_app = target.own_window ||
                   (!name.empty() && ::_wcsicmp(name.c_str(),
                                                OwnExeName().c_str()) == 0);
  // Inna instancja Chatta uruchomiona jako administrator jest poza zasięgiem
  // jak każdy inny program: SendInput nic by do niej nie wpisał.
  target.elevated = !target.own_window && IsElevatedAboveUs(pid);
  target.active =
      !target.elevated && !(target.own_window && g_hold_own.load());
  // O własne okno UI Automation pyta wątek platformy, czyli ten, który tu
  // czeka na odpowiedź: pytanie kończyło się po limicie czasu z "none",
  // a okno Chatta stało przez ten czas przy każdym pingu (sprawdzone na
  // żywo: 400 ms co sekundę). Rodzaj pola we własnym oknie podaje Dart
  // z drzewa widżetów.
  if (with_field && target.active && !target.own_window) {
    target.field = QueryField();
  }
  return target;
}

EncodableMap TargetMap(const Target& target) {
  return EncodableMap{
      {EncodableValue("active"), EncodableValue(target.active)},
      {EncodableValue("field"), EncodableValue(target.field)},
      // Windows nie zna akcji pola: akcja to zawsze zwykły Enter.
      {EncodableValue("action"), EncodableValue("none")},
      {EncodableValue("app"), EncodableValue(target.app)},
      {EncodableValue("appLabel"), EncodableValue(target.app_label)},
      {EncodableValue("ownApp"), EncodableValue(target.own_app)},
      // Tylko dla Darta: pole we własnym oknie ustala on sam.
      {EncodableValue("ownWindow"), EncodableValue(target.own_window)},
      {EncodableValue("locked"), EncodableValue(target.locked)},
      {EncodableValue("elevated"), EncodableValue(target.elevated)},
  };
}

// --- SendInput ---------------------------------------------------------------

// Tekst jako znaki Unicode (KEYEVENTF_UNICODE), więc niezależnie od układu
// klawiatury i bez modyfikatorów. Do KEYEVENTF_UNICODE wolno dołożyć tylko
// KEYEVENTF_KEYUP.
void AddUnicode(std::vector<INPUT>& inputs, wchar_t unit) {
  INPUT down = {};
  down.type = INPUT_KEYBOARD;
  down.ki.wScan = unit;
  down.ki.dwFlags = KEYEVENTF_UNICODE;
  INPUT up = down;
  up.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
  inputs.push_back(down);
  inputs.push_back(up);
}

void AddKey(std::vector<INPUT>& inputs, WORD vk, bool extended) {
  INPUT down = {};
  down.type = INPUT_KEYBOARD;
  down.ki.wVk = vk;
  down.ki.wScan = static_cast<WORD>(::MapVirtualKeyW(vk, MAPVK_VK_TO_VSC));
  down.ki.dwFlags = extended ? KEYEVENTF_EXTENDEDKEY : 0;
  INPUT up = down;
  up.ki.dwFlags |= KEYEVENTF_KEYUP;
  inputs.push_back(down);
  inputs.push_back(up);
}

const EncodableValue* Field(const EncodableMap& map, const char* name) {
  const auto entry = map.find(EncodableValue(name));
  return entry == map.end() ? nullptr : &entry->second;
}

int64_t Count(const EncodableValue* value) {
  if (value == nullptr) {
    return 0;
  }
  if (const auto* krotka = std::get_if<int32_t>(value)) {
    return *krotka;
  }
  if (const auto* dluga = std::get_if<int64_t>(value)) {
    return *dluga;
  }
  return 0;
}

// Zamienia paczkę na zdarzenia klawiatury. false przy czymkolwiek, czego
// nie znamy: wtedy nie wpisujemy niczego z tej paczki.
bool BuildInputs(const EncodableList& ops, std::vector<INPUT>& inputs) {
  for (const EncodableValue& value : ops) {
    const auto* op = std::get_if<EncodableMap>(&value);
    if (op == nullptr) {
      return false;
    }
    const auto* kind = std::get_if<std::string>(Field(*op, "t"));
    if (kind == nullptr) {
      return false;
    }
    if (*kind == "insert") {
      const auto* text = std::get_if<std::string>(Field(*op, "s"));
      if (text == nullptr) {
        return false;
      }
      for (const wchar_t unit : Widen(*text)) {
        if (unit == L'\n') {
          AddKey(inputs, VK_RETURN, false);
        } else if (unit >= 0x20) {
          AddUnicode(inputs, unit);
        }
      }
    } else if (*kind == "bs" || *kind == "del") {
      const int64_t count = Count(Field(*op, "n"));
      if (count < 1 || count > 64) {
        return false;
      }
      for (int64_t i = 0; i < count; i++) {
        if (*kind == "bs") {
          AddKey(inputs, VK_BACK, false);
        } else {
          AddKey(inputs, VK_DELETE, true);
        }
      }
    } else if (*kind == "action") {
      AddKey(inputs, VK_RETURN, false);
    } else {
      return false;
    }
  }
  return true;
}

// Znak po znaku, z przerwą. Znak z KEYEVENTF_UNICODE (VK_PACKET) aplikacja
// odczytuje dopiero przy obsłudze zdarzenia, a następny SendInput go
// nadpisuje: gdy aplikacja nie nadąża, znaki giną albo powtarza się ostatni.
// Notatnik z Windows 11 (WinUI, sprawdzanie pisowni) zwalnia na granicy słowa.
// Sprawdzone na żywo: przy 1 ms „Chatt ąęł 124" wychodziło jako
// „Chatt 4444443", przy 10 ms gubił się jeszcze pojedynczy znak po spacji,
// przy 10 ms i 40 ms po spacji i Enterze 12 linii na 12 przeszło czysto.
constexpr DWORD kPrzerwaZnaku = 10;
constexpr DWORD kPrzerwaSlowa = 40;

// Spacja, tabulator i Enter kończą słowo.
bool KoniecSlowa(const INPUT& down) {
  if (down.ki.dwFlags & KEYEVENTF_UNICODE) {
    return down.ki.wScan == L' ' || down.ki.wScan == L'\t';
  }
  return down.ki.wVk == VK_RETURN;
}

// Okno z fokusem pilnujemy po drodze: gdy fokus przejdzie na ekran blokady
// albo do okna administratora, gdy w oknie Chatta, do którego właśnie się
// pisze, wyskoczy karta z pytaniem, albo gdy padnie Stop, reszta paczki
// przepada.
bool TypePaced(const std::vector<INPUT>& inputs, HWND window,
               uint32_t generation) {
  for (size_t i = 0; i + 1 < inputs.size(); i += 2) {
    if (g_typing_generation.load() != generation) {
      return false;
    }
    if (::GetForegroundWindow() != window || g_hold_own.load()) {
      if (!ReadTarget(false).active) {
        return false;
      }
      window = ::GetForegroundWindow();
    }
    INPUT pair[2] = {inputs[i], inputs[i + 1]};
    if (::SendInput(2, pair, sizeof(INPUT)) != 2) {
      return false;
    }
    ::Sleep(KoniecSlowa(inputs[i]) ? kPrzerwaSlowa : kPrzerwaZnaku);
  }
  return true;
}

// Paczka wpisywana w tle. Wynik wraca do Darta na wątku platformy, przez
// okno komunikatów: tylko tam wolno odpowiedzieć na wywołanie kanału.
struct TypingJob {
  std::vector<INPUT> inputs;
  HWND window = nullptr;
  uint32_t generation = 0;
  bool applied = false;
  std::unique_ptr<flutter::MethodResult<EncodableValue>> result;
};

constexpr UINT kTypingDone = WM_APP + 1;
HWND g_messages = nullptr;

LRESULT CALLBACK MessagesProc(HWND window, UINT message, WPARAM wparam,
                              LPARAM lparam) {
  if (message == kTypingDone) {
    std::unique_ptr<TypingJob> job(reinterpret_cast<TypingJob*>(lparam));
    EncodableMap reply = TargetMap(ReadTarget(true));
    reply[EncodableValue("applied")] = EncodableValue(job->applied);
    job->result->Success(EncodableValue(std::move(reply)));
    return 0;
  }
  return ::DefWindowProcW(window, message, wparam, lparam);
}

bool EnsureMessages() {
  if (g_messages != nullptr) {
    return true;
  }
  WNDCLASSEXW window_class = {};
  window_class.cbSize = sizeof(window_class);
  window_class.lpfnWndProc = MessagesProc;
  window_class.hInstance = ::GetModuleHandleW(nullptr);
  window_class.lpszClassName = L"ChattRemoteInputMessages";
  ::RegisterClassExW(&window_class);
  g_messages = ::CreateWindowExW(0, window_class.lpszClassName, L"", 0, 0, 0,
                                 0, 0, HWND_MESSAGE, nullptr,
                                 ::GetModuleHandleW(nullptr), nullptr);
  return g_messages != nullptr;
}

void TypeInBackground(std::unique_ptr<TypingJob> job) {
  TypingJob* raw = job.release();
  std::thread([raw]() {
    // Bez tego Sleep śpi do najbliższego tyknięcia zegara, czyli nawet
    // 15 ms ponad zadaną przerwę.
    ::timeBeginPeriod(1);
    raw->applied = TypePaced(raw->inputs, raw->window, raw->generation);
    ::timeEndPeriod(1);
    ::PostMessageW(g_messages, kTypingDone, 0, reinterpret_cast<LPARAM>(raw));
  }).detach();
}

// --- Pływający pasek ze Stopem ------------------------------------------------
//
// Widoczny przez całą zgodę, także przy oknie Chatta schowanym w zasobniku.
// Okno nigdy nie przejmuje fokusu (WS_EX_NOACTIVATE, MA_NOACTIVATE,
// PA_NOACTIVATE), jak systemowa klawiatura ekranowa: Stop stuknięty palcem
// albo kliknięty myszą nie zabiera pola, do którego pisze nadawca.

flutter::MethodChannel<EncodableValue>* g_channel = nullptr;

constexpr wchar_t kBarClass[] = L"ChattRemoteInputBar";

struct Bar {
  HWND window = nullptr;
  std::wstring text;
  std::wstring stop;
  RECT button = {};
  bool pressed = false;
  HFONT font = nullptr;
  UINT dpi = 96;
};

Bar& TheBar() {
  static Bar bar;
  return bar;
}

int Scale(int value, UINT dpi) { return ::MulDiv(value, dpi, 96); }

void RefreshFont(Bar& bar) {
  if (bar.font != nullptr) {
    ::DeleteObject(bar.font);
  }
  bar.font = ::CreateFontW(-Scale(15, bar.dpi), 0, 0, 0, FW_SEMIBOLD, FALSE,
                           FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                           CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                           DEFAULT_PITCH, L"Segoe UI");
}

// Rozmiar i miejsce: u góry obszaru roboczego monitora, na którym jest okno
// z fokusem, wyśrodkowany. Przycisk ma co najmniej 44 px wg DPI okna, żeby
// trafić w niego palcem.
void Layout(Bar& bar) {
  HWND anchor = ::GetForegroundWindow();
  HMONITOR monitor = ::MonitorFromWindow(
      anchor != nullptr ? anchor : bar.window, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO info = {};
  info.cbSize = sizeof(info);
  ::GetMonitorInfoW(monitor, &info);

  const UINT dpi = ::GetDpiForWindow(bar.window);
  if (dpi != bar.dpi || bar.font == nullptr) {
    bar.dpi = dpi == 0 ? 96 : dpi;
    RefreshFont(bar);
  }

  HDC dc = ::GetDC(bar.window);
  HGDIOBJ old = ::SelectObject(dc, bar.font);
  SIZE text_size = {};
  ::GetTextExtentPoint32W(dc, bar.text.c_str(),
                          static_cast<int>(bar.text.size()), &text_size);
  SIZE stop_size = {};
  ::GetTextExtentPoint32W(dc, bar.stop.c_str(),
                          static_cast<int>(bar.stop.size()), &stop_size);
  ::SelectObject(dc, old);
  ::ReleaseDC(bar.window, dc);

  const int padding = Scale(12, bar.dpi);
  const int button_height = Scale(44, bar.dpi);
  const int button_width =
      stop_size.cx + 2 * Scale(20, bar.dpi) > Scale(88, bar.dpi)
          ? stop_size.cx + 2 * Scale(20, bar.dpi)
          : Scale(88, bar.dpi);
  const int height = button_height + 2 * Scale(6, bar.dpi);
  const int area_width = info.rcWork.right - info.rcWork.left;
  int width = padding + text_size.cx + padding + button_width + Scale(6, bar.dpi);
  if (width > area_width - 2 * padding) {
    width = area_width - 2 * padding;
  }
  const int x = info.rcWork.left + (area_width - width) / 2;
  const int y = info.rcWork.top + Scale(12, bar.dpi);

  bar.button.right = width - Scale(6, bar.dpi);
  bar.button.left = bar.button.right - button_width;
  bar.button.top = (height - button_height) / 2;
  bar.button.bottom = bar.button.top + button_height;

  ::SetWindowPos(bar.window, HWND_TOPMOST, x, y, width, height,
                 SWP_NOACTIVATE);
}

void Paint(Bar& bar, HDC dc) {
  RECT client = {};
  ::GetClientRect(bar.window, &client);
  HBRUSH background = ::CreateSolidBrush(RGB(32, 32, 36));
  ::FillRect(dc, &client, background);
  ::DeleteObject(background);

  HBRUSH button = ::CreateSolidBrush(bar.pressed ? RGB(150, 32, 22)
                                                 : RGB(196, 43, 28));
  ::FillRect(dc, &bar.button, button);
  ::DeleteObject(button);

  HGDIOBJ old = ::SelectObject(dc, bar.font);
  ::SetBkMode(dc, TRANSPARENT);
  ::SetTextColor(dc, RGB(255, 255, 255));
  RECT text = client;
  text.left += Scale(12, bar.dpi);
  text.right = bar.button.left - Scale(12, bar.dpi);
  ::DrawTextW(dc, bar.text.c_str(), static_cast<int>(bar.text.size()), &text,
              DT_SINGLELINE | DT_VCENTER | DT_LEFT | DT_END_ELLIPSIS |
                  DT_NOPREFIX);
  RECT stop = bar.button;
  ::DrawTextW(dc, bar.stop.c_str(), static_cast<int>(bar.stop.size()), &stop,
              DT_SINGLELINE | DT_VCENTER | DT_CENTER | DT_NOPREFIX);
  ::SelectObject(dc, old);
}

void HideBar() {
  Bar& bar = TheBar();
  bar.pressed = false;
  if (bar.window != nullptr) {
    ::ShowWindow(bar.window, SW_HIDE);
  }
}

void StopPressed() {
  g_typing_generation.fetch_add(1);
  HideBar();
  if (g_channel != nullptr) {
    g_channel->InvokeMethod("stopRequested", nullptr);
  }
}

bool InButton(const Bar& bar, LPARAM lparam) {
  const POINT point = {static_cast<short>(LOWORD(lparam)),
                       static_cast<short>(HIWORD(lparam))};
  return ::PtInRect(&bar.button, point) != FALSE;
}

LRESULT CALLBACK BarProc(HWND window, UINT message, WPARAM wparam,
                         LPARAM lparam) {
  Bar& bar = TheBar();
  switch (message) {
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case WM_POINTERACTIVATE:
      return PA_NOACTIVATE;
    case WM_SETCURSOR:
      ::SetCursor(::LoadCursorW(nullptr, IDC_HAND));
      return TRUE;
    case WM_LBUTTONDOWN:
      if (InButton(bar, lparam)) {
        bar.pressed = true;
        ::SetCapture(window);
        ::InvalidateRect(window, nullptr, FALSE);
      }
      return 0;
    case WM_LBUTTONUP: {
      const bool was_pressed = bar.pressed;
      bar.pressed = false;
      ::ReleaseCapture();
      ::InvalidateRect(window, nullptr, FALSE);
      if (was_pressed && InButton(bar, lparam)) {
        StopPressed();
      }
      return 0;
    }
    case WM_DPICHANGED:
      if (::IsWindowVisible(window)) {
        Layout(bar);
        ::InvalidateRect(window, nullptr, TRUE);
      }
      return 0;
    case WM_PAINT: {
      PAINTSTRUCT paint = {};
      HDC dc = ::BeginPaint(window, &paint);
      Paint(bar, dc);
      ::EndPaint(window, &paint);
      return 0;
    }
    case WM_ERASEBKGND:
      return 1;
    default:
      break;
  }
  return ::DefWindowProcW(window, message, wparam, lparam);
}

bool EnsureBar() {
  Bar& bar = TheBar();
  if (bar.window != nullptr) {
    return true;
  }
  WNDCLASSEXW window_class = {};
  window_class.cbSize = sizeof(window_class);
  window_class.lpfnWndProc = BarProc;
  window_class.hInstance = ::GetModuleHandleW(nullptr);
  window_class.hCursor = ::LoadCursorW(nullptr, IDC_ARROW);
  window_class.lpszClassName = kBarClass;
  ::RegisterClassExW(&window_class);
  bar.window = ::CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, kBarClass, L"Chatt",
      WS_POPUP, 0, 0, 1, 1, nullptr, nullptr, ::GetModuleHandleW(nullptr),
      nullptr);
  if (bar.window == nullptr) {
    return false;
  }
  // Zaokrąglone rogi na Windows 11; starszy system po prostu zignoruje.
  const DWORD corner_preference_attribute = 33;  // DWMWA_WINDOW_CORNER_PREFERENCE
  const int round = 2;                            // DWMWCP_ROUND
  ::DwmSetWindowAttribute(bar.window, corner_preference_attribute, &round,
                          sizeof(round));
  return true;
}

void ShowBar(const std::wstring& text, const std::wstring& stop) {
  if (!EnsureBar()) {
    return;
  }
  Bar& bar = TheBar();
  const bool same = ::IsWindowVisible(bar.window) && text == bar.text &&
                    stop == bar.stop;
  if (same) {
    return;
  }
  bar.text = text;
  bar.stop = stop;
  Layout(bar);
  ::ShowWindow(bar.window, SW_SHOWNOACTIVATE);
  ::InvalidateRect(bar.window, nullptr, TRUE);
}

const std::string* StringArgument(const EncodableValue* arguments,
                                  const char* name) {
  const auto* map = std::get_if<EncodableMap>(arguments);
  return map == nullptr ? nullptr
                        : std::get_if<std::string>(Field(*map, name));
}

}  // namespace

void RegisterChattRemoteInput(flutter::FlutterEngine* engine) {
  // Kanał żyje tyle, co proces: statyczny, bo runner nie ma gdzie go trzymać.
  static auto channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          engine->messenger(), "chatt/remoteinput",
          &flutter::StandardMethodCodec::GetInstance());
  g_channel = channel.get();

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        const std::string& method = call.method_name();

        if (method == "status") {
          result->Success(EncodableValue(TargetMap(ReadTarget(true))));
          return;
        }

        if (method == "apply") {
          const auto* arguments = std::get_if<EncodableMap>(call.arguments());
          const auto* ops =
              arguments == nullptr
                  ? nullptr
                  : std::get_if<EncodableList>(Field(*arguments, "ops"));
          // Cel sprawdzany tuż przed wpisaniem: między paczkami fokus mógł
          // przejść na ekran blokady albo do okna administratora.
          const Target before = ReadTarget(false);
          auto job = std::make_unique<TypingJob>();
          const bool built = ops != nullptr && BuildInputs(*ops, job->inputs);
          if (!built || !before.active || job->inputs.empty() ||
              !EnsureMessages()) {
            EncodableMap reply = TargetMap(ReadTarget(true));
            reply[EncodableValue("applied")] =
                EncodableValue(built && before.active && job->inputs.empty());
            result->Success(EncodableValue(std::move(reply)));
            return;
          }
          job->window = ::GetForegroundWindow();
          job->generation = g_typing_generation.load();
          job->result = std::move(result);
          TypeInBackground(std::move(job));
          return;
        }

        if (method == "setSession") {
          const auto* arguments = std::get_if<EncodableMap>(call.arguments());
          const auto* active =
              arguments == nullptr
                  ? nullptr
                  : std::get_if<bool>(Field(*arguments, "active"));
          // Koniec zgody chowa pasek, cokolwiek powie Dart: pasek bez zgody
          // straszyłby kogoś, kto już nic nie pisze.
          if (active == nullptr || !*active) {
            g_typing_generation.fetch_add(1);
            HideBar();
          }
          result->Success(EncodableValue(EncodableMap{}));
          return;
        }

        if (method == "holdOwnApp") {
          const auto* arguments = std::get_if<EncodableMap>(call.arguments());
          const auto* on = arguments == nullptr
                               ? nullptr
                               : std::get_if<bool>(Field(*arguments, "on"));
          g_hold_own.store(on != nullptr && *on);
          result->Success(EncodableValue(EncodableMap{}));
          return;
        }

        if (method == "setImeEnabled") {
          // Na Windows nie ma komponentu klawiatury do włączania.
          result->Success(EncodableValue(EncodableMap{
              {EncodableValue("ok"), EncodableValue(true)},
          }));
          return;
        }

        if (method == "showIndicator") {
          const std::string* text = StringArgument(call.arguments(), "text");
          const std::string* stop = StringArgument(call.arguments(), "stop");
          if (text == nullptr || stop == nullptr) {
            result->Error("bad_args", "Brak tekstow paska");
            return;
          }
          ShowBar(Widen(*text), Widen(*stop));
          result->Success(EncodableValue(EncodableMap{
              {EncodableValue("ok"), EncodableValue(true)},
          }));
          return;
        }

        if (method == "hideIndicator") {
          HideBar();
          result->Success(EncodableValue(EncodableMap{
              {EncodableValue("ok"), EncodableValue(true)},
          }));
          return;
        }

        result->NotImplemented();
      });
}

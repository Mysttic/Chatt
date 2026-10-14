// winsock2.h musi wyprzedzic windows.h, inaczej windows.h wciagnie stare
// winsock.h i zablokuje nowe naglowkiem straznikiem. Wlasny naglowek idzie
// tu nizej niz zwykle wlasnie dlatego: flutter_engine.h ciagnie windows.h.
// ws2bth.h doklada AF_BTH i rekordy SDP.
#include <winsock2.h>
#include <ws2bth.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <bluetoothapis.h>
#include <objbase.h>

#include "chatt_bluetooth.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <cstdio>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr uint32_t kFnvStart = 2166136261u;
constexpr uint32_t kFnvPrime = 16777619u;

bool StartWinsock() {
  static bool ready = false;
  static bool tried = false;
  if (!tried) {
    tried = true;
    WSADATA data;
    ready = WSAStartup(MAKEWORD(2, 2), &data) == 0;
  }
  return ready;
}

// --- pomocnicze -------------------------------------------------------------

std::string Narrow(const wchar_t* text) {
  if (text == nullptr || *text == L'\0') {
    return std::string();
  }
  const int length = WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0,
                                         nullptr, nullptr);
  if (length <= 1) {
    return std::string();
  }
  std::string out(static_cast<size_t>(length) - 1, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text, -1, out.data(), length, nullptr,
                      nullptr);
  return out;
}

std::wstring Widen(const std::string& text) {
  if (text.empty()) {
    return std::wstring();
  }
  const int length = MultiByteToWideChar(
      CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()), nullptr, 0);
  if (length <= 0) {
    return std::wstring();
  }
  std::wstring out(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.c_str(), static_cast<int>(text.size()),
                      out.data(), length);
  return out;
}

// Adres radia w postaci, ktora widzi uzytkownik i ktora przyjmuje Android.
std::string FormatAddress(ULONGLONG address) {
  char text[18] = {};
  const auto* bytes = reinterpret_cast<const unsigned char*>(&address);
  sprintf_s(text, sizeof(text), "%02X:%02X:%02X:%02X:%02X:%02X", bytes[5],
            bytes[4], bytes[3], bytes[2], bytes[1], bytes[0]);
  return std::string(text);
}

// Odwrotnosc FormatAddress. Dwukropki sa opcjonalne, wielkosc liter obojetna.
bool ParseAddress(const std::string& text, BTH_ADDR* out) {
  unsigned int bytes[6] = {};
  int count = sscanf_s(text.c_str(), "%2x:%2x:%2x:%2x:%2x:%2x", &bytes[0],
                       &bytes[1], &bytes[2], &bytes[3], &bytes[4], &bytes[5]);
  if (count != 6) {
    count = sscanf_s(text.c_str(), "%2x%2x%2x%2x%2x%2x", &bytes[0], &bytes[1],
                     &bytes[2], &bytes[3], &bytes[4], &bytes[5]);
  }
  if (count != 6) {
    return false;
  }
  ULONGLONG address = 0;
  for (int i = 0; i < 6; ++i) {
    address = (address << 8) | static_cast<ULONGLONG>(bytes[i] & 0xFFu);
  }
  *out = address;
  return true;
}

// CLSIDFromString chce klamer, a z Darta przychodzi goly UUID.
bool ParseGuid(const std::string& text, GUID* out) {
  const std::wstring braced = L"{" + Widen(text) + L"}";
  return CLSIDFromString(braced.c_str(), out) == NOERROR;
}

const EncodableValue* Find(const EncodableMap* args, const char* name) {
  if (args == nullptr) {
    return nullptr;
  }
  const auto entry = args->find(EncodableValue(name));
  return entry == args->end() ? nullptr : &entry->second;
}

// Dart wysyla liczby raz jako 32-, raz jako 64-bitowe, zaleznie od wartosci.
int64_t IntArg(const EncodableMap* args, const char* name, int64_t fallback) {
  const EncodableValue* value = Find(args, name);
  if (value == nullptr) {
    return fallback;
  }
  // Nazwa narrow: rpcndr.h spod windows.h ma makro small (#define small char).
  if (const auto* narrow = std::get_if<int32_t>(value)) {
    return *narrow;
  }
  if (const auto* wide = std::get_if<int64_t>(value)) {
    return *wide;
  }
  return fallback;
}

std::string StringArg(const EncodableMap* args, const char* name,
                      const std::string& fallback) {
  const EncodableValue* value = Find(args, name);
  const auto* text = value == nullptr ? nullptr : std::get_if<std::string>(value);
  return text == nullptr ? fallback : *text;
}

bool BoolArg(const EncodableMap* args, const char* name, bool fallback) {
  const EncodableValue* value = Find(args, name);
  const auto* flag = value == nullptr ? nullptr : std::get_if<bool>(value);
  return flag == nullptr ? fallback : *flag;
}

// Wzorzec bajtow wspolny z ChattBluetooth.kt: odbior sprawdza sam siebie.
unsigned char Pattern(int64_t index) {
  return static_cast<unsigned char>((index * 31 + 7) & 0xFF);
}

int64_t NowMicros() {
  LARGE_INTEGER frequency = {};
  LARGE_INTEGER counter = {};
  QueryPerformanceFrequency(&frequency);
  QueryPerformanceCounter(&counter);
  if (frequency.QuadPart == 0) {
    return 0;
  }
  return counter.QuadPart * 1000000 / frequency.QuadPart;
}

EncodableValue ErrorMap(const std::string& reason, int code) {
  EncodableMap out;
  out[EncodableValue("error")] = EncodableValue(reason);
  out[EncodableValue("code")] = EncodableValue(code);
  return EncodableValue(out);
}

void CloseSocket(SOCKET& sock) {
  if (sock != INVALID_SOCKET) {
    closesocket(sock);
    sock = INVALID_SOCKET;
  }
}

// --- rekord SDP -------------------------------------------------------------

// Bez rekordu SDP druga strona nie ma jak znalezc numeru kanalu RFCOMM.
bool PublishSdp(const GUID& service, const std::wstring& name,
                SOCKADDR_BTH* bound, bool register_it) {
  CSADDR_INFO addr_info = {};
  addr_info.LocalAddr.iSockaddrLength = sizeof(SOCKADDR_BTH);
  addr_info.LocalAddr.lpSockaddr = reinterpret_cast<SOCKADDR*>(bound);
  addr_info.iSocketType = SOCK_STREAM;
  addr_info.iProtocol = BTHPROTO_RFCOMM;

  std::wstring instance = name.empty() ? L"Chatt" : name;
  GUID service_copy = service;

  WSAQUERYSETW query = {};
  query.dwSize = static_cast<DWORD>(sizeof(query));
  query.lpszServiceInstanceName = instance.data();
  query.lpServiceClassId = &service_copy;
  query.dwNameSpace = NS_BTH;
  query.dwNumberOfCsAddrs = 1;
  query.lpcsaBuffer = &addr_info;

  return WSASetServiceW(&query,
                        register_it ? RNRSERVICE_REGISTER : RNRSERVICE_DELETE,
                        0) == 0;
}

// --- lacza ------------------------------------------------------------------

// Jedno lacze: gniazdo RFCOMM plus gniazdo nasluchu na petli zwrotnej, pod
// ktore podlacza sie strona Dartowa. Bajty przepisuja dwa watki, po jednym
// na kierunek.
struct Link {
  int id = 0;
  std::string peer;
  bool incoming = false;
  SOCKET rfcomm = INVALID_SOCKET;
  SOCKET listener = INVALID_SOCKET;
  SOCKET local = INVALID_SOCKET;
  std::atomic<bool> closed{false};
};

std::mutex g_mutex;
std::map<int, std::shared_ptr<Link>> g_links;

// Gniazda w trakcie laczenia. Nieudana proba potrafi dobijac sie kilkanascie
// sekund i przez ten czas zaglusza radio, a przy wyszukiwaniu takich prob jest
// tyle, ile urzadzen w zasiegu. Zamkniecie gniazda przerywa connect od razu.
std::map<int, SOCKET> g_connecting;

// Notatki ze strony natywnej, odbierane przez linkPoll. Radio nie ma konsoli,
// a bledy mostka widac inaczej dopiero po skutku.
std::vector<EncodableValue> g_notes;
std::vector<EncodableValue> g_ready;
std::vector<EncodableValue> g_failed;
std::vector<EncodableValue> g_closed;
int g_next_id = 1;

SOCKET g_listening = INVALID_SOCKET;
SOCKADDR_BTH g_bound = {};
GUID g_service = {};
std::atomic<bool> g_sdp{false};
std::atomic<bool> g_accepting{false};

// Wyniki wyszukiwania. Klucz to adres, zeby to samo urzadzenie nie weszlo
// do listy dwa razy.
struct Found {
  std::string name;
  // Glowna klasa z Class of Device, juz z maska 0x1F00. Po niej Dart
  // uklada kolejke pytania: komputery i telefony najpierw.
  int major = 0;
};
std::mutex g_scan_mutex;
std::map<std::string, Found> g_found;
std::atomic<bool> g_scanning{false};
// Ustawiane przez LinkStop: watek szukania nie zapisuje juz niczego, co
// przyniesie zapytanie w eter. Samego zapytania nie da sie przerwac, trwa do
// konca swoich niecalych osmiu sekund.
std::atomic<bool> g_scan_cancel{false};

// Powod zerwania jedzie do Darta razem z numerem lacza. Bez tego obie
// strony widza tylko cisze tej drugiej i nie da sie powiedziec, ktora
// odlozyla sluchawke pierwsza.
void Note(const std::string& text) {
  std::lock_guard<std::mutex> guard(g_mutex);
  // Gorna granica, zeby log nie urosl w nieskonczonosc, gdy nikt nie pyta.
  if (g_notes.size() < 200) {
    g_notes.push_back(EncodableValue(text));
  }
}

void DropLink(const std::shared_ptr<Link>& link, const std::string& reason) {
  if (link->closed.exchange(true)) {
    return;
  }
  Note("lacze " + std::to_string(link->id) + ": zrywam, " + reason);
  CloseSocket(link->rfcomm);
  CloseSocket(link->listener);
  CloseSocket(link->local);
  std::lock_guard<std::mutex> guard(g_mutex);
  g_links.erase(link->id);
  EncodableMap entry;
  entry[EncodableValue("id")] = EncodableValue(static_cast<int32_t>(link->id));
  entry[EncodableValue("reason")] = EncodableValue(reason);
  g_closed.push_back(EncodableValue(entry));
}

void Pump(const std::shared_ptr<Link>& link, SOCKET from, SOCKET to,
          const char* label) {
  std::vector<char> buffer(16 * 1024);
  while (!link->closed.load()) {
    const int read = recv(from, buffer.data(), static_cast<int>(buffer.size()), 0);
    if (read <= 0) {
      DropLink(link, std::string(label) + " recv=" + std::to_string(read) +
                         " wsa=" + std::to_string(WSAGetLastError()));
      return;
    }
    int written = 0;
    while (written < read) {
      const int wrote = send(to, buffer.data() + written, read - written, 0);
      if (wrote <= 0) {
        DropLink(link, std::string(label) + " send wsa=" +
                           std::to_string(WSAGetLastError()));
        return;
      }
      written += wrote;
    }
  }
  DropLink(link, std::string(label) + " lacze zamkniete obok");
}

// Gotowe lacze: zakladamy pod nie gniazdo nasluchu na petli zwrotnej
// i czekamy, az strona Dartowa sie podlaczy. Dopiero wtedy rusza pompa,
// wiec zaden bajt z radia nie przepada w miedzyczasie.
bool Announce(SOCKET rfcomm, const std::string& peer, bool incoming, int id) {
  // Tylko petla zwrotna: ten port nie ma prawa byc widoczny z sieci.
  SOCKET listener = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (listener == INVALID_SOCKET) {
    return false;
  }
  sockaddr_in local = {};
  local.sin_family = AF_INET;
  local.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  local.sin_port = 0;
  if (bind(listener, reinterpret_cast<SOCKADDR*>(&local), sizeof(local)) ==
          SOCKET_ERROR ||
      listen(listener, 1) == SOCKET_ERROR) {
    closesocket(listener);
    return false;
  }
  sockaddr_in bound = {};
  int bound_length = static_cast<int>(sizeof(bound));
  if (getsockname(listener, reinterpret_cast<SOCKADDR*>(&bound),
                  &bound_length) == SOCKET_ERROR) {
    closesocket(listener);
    return false;
  }
  const int port = ntohs(bound.sin_port);

  auto link = std::make_shared<Link>();
  link->id = id;
  link->peer = peer;
  link->incoming = incoming;
  link->rfcomm = rfcomm;
  link->listener = listener;

  {
    std::lock_guard<std::mutex> guard(g_mutex);
    g_links[id] = link;
    EncodableMap entry;
    entry[EncodableValue("id")] = EncodableValue(static_cast<int32_t>(id));
    entry[EncodableValue("peer")] = EncodableValue(peer);
    entry[EncodableValue("port")] = EncodableValue(static_cast<int32_t>(port));
    entry[EncodableValue("incoming")] = EncodableValue(incoming);
    g_ready.push_back(EncodableValue(entry));
  }

  std::thread([link]() {
    // Strona Dartowa ma kilkanascie sekund na odebranie z linkPoll
    // i podlaczenie sie. Dluzsze czekanie znaczy, ze po tamtej stronie
    // nikt juz tego lacza nie chce.
    fd_set readable = {};
    readable.fd_count = 1;
    readable.fd_array[0] = link->listener;
    timeval limit = {};
    limit.tv_sec = 15;
    if (select(0, &readable, nullptr, nullptr, &limit) != 1) {
      DropLink(link, "Dart nie podlaczyl sie do portu lokalnego");
      return;
    }
    SOCKET local = accept(link->listener, nullptr, nullptr);
    if (local == INVALID_SOCKET) {
      DropLink(link, "accept lokalny wsa=" + std::to_string(WSAGetLastError()));
      return;
    }
    BOOL nodelay = TRUE;
    setsockopt(local, IPPROTO_TCP, TCP_NODELAY,
               reinterpret_cast<const char*>(&nodelay), sizeof(nodelay));
    link->local = local;
    CloseSocket(link->listener);
    Note("lacze " + std::to_string(link->id) + ": mostek stoi, rfcomm=" +
         std::to_string(static_cast<uint64_t>(link->rfcomm)) + " local=" +
         std::to_string(static_cast<uint64_t>(local)));

    // Drugi kierunek wlasnym watkiem: jeden watek na oba skonczylby sie
    // zakleszczeniem przy pierwszym wiekszym pliku.
    std::thread([link]() { Pump(link, link->local, link->rfcomm, "dart->radio"); })
        .detach();
    Pump(link, link->rfcomm, link->local, "radio->dart");
  }).detach();

  return true;
}

EncodableValue LinkStart(const EncodableMap* args) {
  if (g_accepting.load()) {
    EncodableMap out;
    out[EncodableValue("listening")] = EncodableValue(true);
    return EncodableValue(out);
  }

  GUID service = {};
  if (!ParseGuid(StringArg(args, "uuid", ""), &service)) {
    return ErrorMap("Zly UUID uslugi", 0);
  }
  const bool secure = BoolArg(args, "secure", false);
  const std::wstring name = Widen(StringArg(args, "name", "Chatt"));

  SOCKET listener = socket(AF_BTH, SOCK_STREAM, BTHPROTO_RFCOMM);
  if (listener == INVALID_SOCKET) {
    return ErrorMap("Nie da sie otworzyc gniazda RFCOMM", WSAGetLastError());
  }
  if (secure) {
    // Czego wtyczki z pub.dev tu nie robia: bez tego nasluch przyjmuje
    // takze polaczenia nieuwierzytelnione, mimo wlaczonej flagi.
    ULONG on = TRUE;
    setsockopt(listener, SOL_RFCOMM, SO_BTH_AUTHENTICATE,
               reinterpret_cast<const char*>(&on), sizeof(on));
    setsockopt(listener, SOL_RFCOMM, SO_BTH_ENCRYPT,
               reinterpret_cast<const char*>(&on), sizeof(on));
  }

  SOCKADDR_BTH local = {};
  local.addressFamily = AF_BTH;
  local.btAddr = 0;
  local.serviceClassId = service;
  local.port = BT_PORT_ANY;
  if (bind(listener, reinterpret_cast<SOCKADDR*>(&local), sizeof(local)) ==
      SOCKET_ERROR) {
    const int code = WSAGetLastError();
    closesocket(listener);
    return ErrorMap("bind sie nie udal", code);
  }
  if (listen(listener, 2) == SOCKET_ERROR) {
    const int code = WSAGetLastError();
    closesocket(listener);
    return ErrorMap("listen sie nie udal", code);
  }
  g_bound = {};
  int length = static_cast<int>(sizeof(g_bound));
  if (getsockname(listener, reinterpret_cast<SOCKADDR*>(&g_bound), &length) ==
      SOCKET_ERROR) {
    const int code = WSAGetLastError();
    closesocket(listener);
    return ErrorMap("getsockname sie nie udal", code);
  }
  g_service = service;
  if (!PublishSdp(service, name, &g_bound, true)) {
    const int code = WSAGetLastError();
    closesocket(listener);
    return ErrorMap("Nie da sie oglosic uslugi w SDP", code);
  }
  g_sdp.store(true);
  g_listening = listener;
  g_accepting.store(true);

  std::thread([listener]() {
    while (g_accepting.load()) {
      SOCKADDR_BTH peer = {};
      int peer_length = static_cast<int>(sizeof(peer));
      SOCKET fresh =
          accept(listener, reinterpret_cast<SOCKADDR*>(&peer), &peer_length);
      if (fresh == INVALID_SOCKET) {
        // Zamkniecie gniazda nasluchu wyglada tak samo jak blad.
        break;
      }
      int id;
      {
        std::lock_guard<std::mutex> guard(g_mutex);
        id = g_next_id++;
      }
      if (!Announce(fresh, FormatAddress(peer.btAddr), true, id)) {
        closesocket(fresh);
      }
    }
    g_accepting.store(false);
  }).detach();

  EncodableMap out;
  out[EncodableValue("listening")] = EncodableValue(true);
  return EncodableValue(out);
}

EncodableValue LinkStop() {
  g_accepting.store(false);
  g_scan_cancel.store(true);
  {
    std::lock_guard<std::mutex> guard(g_scan_mutex);
    g_found.clear();
  }
  if (g_sdp.exchange(false)) {
    PublishSdp(g_service, L"Chatt", &g_bound, false);
  }
  CloseSocket(g_listening);

  std::vector<std::shared_ptr<Link>> alive;
  {
    std::lock_guard<std::mutex> guard(g_mutex);
    for (const auto& entry : g_connecting) {
      closesocket(entry.second);
    }
    g_connecting.clear();
    for (const auto& entry : g_links) {
      alive.push_back(entry.second);
    }
  }
  for (const auto& link : alive) {
    DropLink(link, "transport wylaczony");
  }
  return EncodableValue(true);
}

// Laczenie idzie wlasnym watkiem i melduje sie przez LinkPoll, bo RFCOMM
// potrafi sie zastanawiac kilkanascie sekund, a kanal ma wracac od razu.
EncodableValue LinkConnect(const EncodableMap* args) {
  BTH_ADDR address = 0;
  const std::string text = StringArg(args, "address", "");
  if (!ParseAddress(text, &address)) {
    return ErrorMap("Zly adres urzadzenia", 0);
  }
  GUID service = {};
  if (!ParseGuid(StringArg(args, "uuid", ""), &service)) {
    return ErrorMap("Zly UUID uslugi", 0);
  }
  const bool secure = BoolArg(args, "secure", false);

  int id;
  {
    std::lock_guard<std::mutex> guard(g_mutex);
    id = g_next_id++;
  }

  std::thread([address, service, secure, id, text]() {
    SOCKET fresh = socket(AF_BTH, SOCK_STREAM, BTHPROTO_RFCOMM);
    if (fresh == INVALID_SOCKET) {
      std::lock_guard<std::mutex> guard(g_mutex);
      EncodableMap entry;
      entry[EncodableValue("id")] = EncodableValue(static_cast<int32_t>(id));
      entry[EncodableValue("error")] = EncodableValue(std::string("socket"));
      g_failed.push_back(EncodableValue(entry));
      return;
    }
    if (secure) {
      ULONG on = TRUE;
      setsockopt(fresh, SOL_RFCOMM, SO_BTH_AUTHENTICATE,
                 reinterpret_cast<const char*>(&on), sizeof(on));
    }
    {
      std::lock_guard<std::mutex> guard(g_mutex);
      g_connecting[id] = fresh;
    }
    SOCKADDR_BTH target = {};
    target.addressFamily = AF_BTH;
    target.btAddr = address;
    target.serviceClassId = service;
    // port 0 znaczy "odszukaj numer kanalu po UUID w SDP drugiej strony".
    target.port = 0;

    const bool polaczone =
        connect(fresh, reinterpret_cast<SOCKADDR*>(&target), sizeof(target)) !=
        SOCKET_ERROR;
    {
      std::lock_guard<std::mutex> guard(g_mutex);
      g_connecting.erase(id);
    }
    if (!polaczone || !Announce(fresh, text, false, id)) {
      const int code = WSAGetLastError();
      closesocket(fresh);
      std::lock_guard<std::mutex> guard(g_mutex);
      EncodableMap entry;
      entry[EncodableValue("id")] = EncodableValue(static_cast<int32_t>(id));
      entry[EncodableValue("error")] = EncodableValue(std::to_string(code));
      g_failed.push_back(EncodableValue(entry));
    }
  }).detach();

  EncodableMap out;
  out[EncodableValue("id")] = EncodableValue(static_cast<int32_t>(id));
  return EncodableValue(out);
}

EncodableValue LinkClose(const EncodableMap* args) {
  const int id = static_cast<int>(IntArg(args, "id", 0));
  Note("lacze " + std::to_string(id) + ": Dart kazal zamknac");
  std::shared_ptr<Link> link;
  {
    std::lock_guard<std::mutex> guard(g_mutex);
    const auto pending = g_connecting.find(id);
    if (pending != g_connecting.end()) {
      closesocket(pending->second);
      g_connecting.erase(pending);
    }
    const auto entry = g_links.find(id);
    if (entry != g_links.end()) {
      link = entry->second;
    }
  }
  if (link) {
    DropLink(link, "zamkniete przez Darta");
  }
  return EncodableValue(true);
}

// Wszystko, co sie wydarzylo od ostatniego pytania. Zabieramy przy odczycie,
// zeby to samo lacze nie weszlo do Darta dwa razy.
EncodableValue LinkPoll() {
  EncodableMap out;
  std::lock_guard<std::mutex> guard(g_mutex);
  out[EncodableValue("ready")] = EncodableValue(EncodableList(g_ready));
  out[EncodableValue("failed")] = EncodableValue(EncodableList(g_failed));
  out[EncodableValue("closed")] = EncodableValue(EncodableList(g_closed));
  out[EncodableValue("listening")] = EncodableValue(g_accepting.load());
  out[EncodableValue("notes")] = EncodableValue(EncodableList(g_notes));
  g_ready.clear();
  g_failed.clear();
  g_closed.clear();
  g_notes.clear();
  return EncodableValue(out);
}

// --- radio ------------------------------------------------------------------

// Bez tego komputera nie da sie znalezc: Windows jest wykrywalny tylko przy
// otwartym oknie "Dodaj urzadzenie". Wlacza to uzytkownik razem z transportem
// i gasnie razem z nim.
EncodableValue SetDiscoverable(const EncodableMap* args) {
  const bool on = BoolArg(args, "on", true);
  BLUETOOTH_FIND_RADIO_PARAMS params = {};
  params.dwSize = static_cast<DWORD>(sizeof(params));
  HANDLE radio = nullptr;
  HBLUETOOTH_RADIO_FIND finder = BluetoothFindFirstRadio(&params, &radio);
  if (finder == nullptr) {
    return EncodableValue(false);
  }
  bool any = false;
  do {
    // Wylaczenie gasi sama wykrywalnosc. Przychodzace polaczenia Windows ma
    // wlaczone od siebie, a ich wylaczenie odcieloby od komputera takze
    // sparowane sluchawki i myszy, wiec ich nie ruszamy.
    if (on) {
      BluetoothEnableIncomingConnections(radio, TRUE);
    }
    BluetoothEnableDiscovery(radio, on ? TRUE : FALSE);
    any = true;
    CloseHandle(radio);
    radio = nullptr;
  } while (BluetoothFindNextRadio(finder, &radio));
  BluetoothFindRadioClose(finder);
  return EncodableValue(any);
}

// Pytanie w eter trwa kilka sekund i musi isc wlasnym watkiem. Wyniki
// odbiera ScanResults.
EncodableValue Scan() {
  // Najpierw: zapytanie, ktore jeszcze trwa po wylaczeniu transportu, ma
  // zasilic to nowe szukanie.
  g_scan_cancel.store(false);
  if (g_scanning.exchange(true)) {
    EncodableMap out;
    out[EncodableValue("scanning")] = EncodableValue(true);
    out[EncodableValue("granted")] = EncodableValue(true);
    return EncodableValue(out);
  }
  {
    std::lock_guard<std::mutex> guard(g_scan_mutex);
    g_found.clear();
  }

  std::thread([]() {
    BLUETOOTH_DEVICE_SEARCH_PARAMS search = {};
    search.dwSize = static_cast<DWORD>(sizeof(search));
    search.fReturnAuthenticated = TRUE;
    search.fReturnRemembered = TRUE;
    search.fReturnConnected = TRUE;
    search.fReturnUnknown = TRUE;
    search.fIssueInquiry = TRUE;
    // Jednostka to 1,28 s. Szesc daje niecale osiem sekund, czyli tyle, ile
    // trwa sensowne rozejrzenie sie po pokoju.
    search.cTimeoutMultiplier = 6;
    search.hRadio = nullptr;

    BLUETOOTH_DEVICE_INFO device = {};
    device.dwSize = static_cast<DWORD>(sizeof(device));
    HBLUETOOTH_DEVICE_FIND found = BluetoothFindFirstDevice(&search, &device);
    if (found != nullptr) {
      do {
        const std::string address = FormatAddress(device.Address.ullLong);
        std::string name = Narrow(device.szName);
        if (name.empty()) {
          name = address;
        }
        {
          // Pod tym samym zamkiem co czyszczenie w LinkStop: nic nie
          // wpadnie na liste po jej wyczyszczeniu.
          std::lock_guard<std::mutex> guard(g_scan_mutex);
          if (g_scan_cancel.load()) {
            break;
          }
          g_found[address] =
              Found{name, static_cast<int>(device.ulClassofDevice & 0x1F00)};
        }
        device = {};
        device.dwSize = static_cast<DWORD>(sizeof(device));
      } while (BluetoothFindNextDevice(found, &device));
      BluetoothFindDeviceClose(found);
    }
    g_scanning.store(false);
  }).detach();

  EncodableMap out;
  out[EncodableValue("scanning")] = EncodableValue(true);
  out[EncodableValue("granted")] = EncodableValue(true);
  return EncodableValue(out);
}

EncodableValue ScanResults() {
  EncodableList devices;
  {
    std::lock_guard<std::mutex> guard(g_scan_mutex);
    for (const auto& entry : g_found) {
      EncodableMap one;
      one[EncodableValue("address")] = EncodableValue(entry.first);
      one[EncodableValue("name")] = EncodableValue(entry.second.name);
      one[EncodableValue("bonded")] = EncodableValue(false);
      one[EncodableValue("major")] = EncodableValue(entry.second.major);
      devices.push_back(EncodableValue(one));
    }
  }
  EncodableMap out;
  out[EncodableValue("scanning")] = EncodableValue(g_scanning.load());
  out[EncodableValue("devices")] = EncodableValue(devices);
  return EncodableValue(out);
}

EncodableValue Status() {
  EncodableMap out;
  bool available = false;
  std::string name;
  std::string address;

  // Wszystkie radia: komputer z ukladem na plycie
  // i pastylka w USB ma dwa, a druga strona jest sparowana tylko z jednym.
  EncodableList radios;
  BLUETOOTH_FIND_RADIO_PARAMS params = {};
  params.dwSize = static_cast<DWORD>(sizeof(params));
  HANDLE radio = nullptr;
  HBLUETOOTH_RADIO_FIND finder = BluetoothFindFirstRadio(&params, &radio);
  if (finder != nullptr) {
    do {
      available = true;
      BLUETOOTH_RADIO_INFO info = {};
      info.dwSize = static_cast<DWORD>(sizeof(info));
      if (BluetoothGetRadioInfo(radio, &info) == ERROR_SUCCESS) {
        EncodableMap one;
        one[EncodableValue("name")] = EncodableValue(Narrow(info.szName));
        one[EncodableValue("address")] =
            EncodableValue(FormatAddress(info.address.ullLong));
        radios.push_back(EncodableValue(one));
        if (address.empty()) {
          name = Narrow(info.szName);
          address = FormatAddress(info.address.ullLong);
        }
      }
      CloseHandle(radio);
      radio = nullptr;
    } while (BluetoothFindNextRadio(finder, &radio));
    BluetoothFindRadioClose(finder);
  }

  EncodableList paired;
  BLUETOOTH_DEVICE_SEARCH_PARAMS search = {};
  search.dwSize = static_cast<DWORD>(sizeof(search));
  search.fReturnAuthenticated = TRUE;
  search.fReturnRemembered = TRUE;
  search.fReturnConnected = TRUE;
  search.fReturnUnknown = FALSE;
  // Bez inquiry: pytanie eteru o nowe urzadzenia trwa dziesiatki sekund
  // i zaglusza kazde otwarte polaczenie. Od tego jest Scan.
  search.fIssueInquiry = FALSE;
  search.cTimeoutMultiplier = 0;
  search.hRadio = nullptr;

  BLUETOOTH_DEVICE_INFO device = {};
  device.dwSize = static_cast<DWORD>(sizeof(device));
  HBLUETOOTH_DEVICE_FIND found = BluetoothFindFirstDevice(&search, &device);
  if (found != nullptr) {
    do {
      EncodableMap one;
      one[EncodableValue("name")] = EncodableValue(Narrow(device.szName));
      one[EncodableValue("address")] =
          EncodableValue(FormatAddress(device.Address.ullLong));
      paired.push_back(EncodableValue(one));
      device = {};
      device.dwSize = static_cast<DWORD>(sizeof(device));
    } while (BluetoothFindNextDevice(found, &device));
    BluetoothFindDeviceClose(found);
  }

  out[EncodableValue("available")] = EncodableValue(available);
  out[EncodableValue("enabled")] = EncodableValue(available);
  out[EncodableValue("granted")] = EncodableValue(true);
  out[EncodableValue("canScan")] = EncodableValue(true);
  // Windows nie wiaze wyszukiwania Bluetooth z uslugami lokalizacji.
  out[EncodableValue("locationOn")] = EncodableValue(true);
  out[EncodableValue("name")] = EncodableValue(name);
  out[EncodableValue("address")] = EncodableValue(address);
  out[EncodableValue("radios")] = EncodableValue(radios);
  out[EncodableValue("paired")] = EncodableValue(paired);
  return EncodableValue(out);
}

// --- pomiar (rozpoznanie, tool/bt_spike.dart) --------------------------------

SOCKET g_bench_listening = INVALID_SOCKET;
SOCKET g_bench_data = INVALID_SOCKET;
SOCKADDR_BTH g_bench_bound = {};
GUID g_bench_service = {};
bool g_bench_sdp = false;

void BenchTimeouts(int64_t timeout_ms) {
  if (g_bench_data == INVALID_SOCKET) {
    return;
  }
  // Bez limitu jedno zerwane polaczenie zawiesiloby okno na zawsze.
  DWORD value = static_cast<DWORD>(timeout_ms <= 0 ? 60000 : timeout_ms);
  setsockopt(g_bench_data, SOL_SOCKET, SO_RCVTIMEO,
             reinterpret_cast<const char*>(&value), sizeof(value));
  setsockopt(g_bench_data, SOL_SOCKET, SO_SNDTIMEO,
             reinterpret_cast<const char*>(&value), sizeof(value));
}

void BenchCloseAll() {
  if (g_bench_sdp) {
    PublishSdp(g_bench_service, L"Chatt", &g_bench_bound, false);
    g_bench_sdp = false;
  }
  CloseSocket(g_bench_data);
  CloseSocket(g_bench_listening);
}

EncodableValue BenchListen(const EncodableMap* args) {
  if (g_bench_data != INVALID_SOCKET) {
    EncodableMap out;
    out[EncodableValue("connected")] = EncodableValue(true);
    return EncodableValue(out);
  }

  GUID service = {};
  if (!ParseGuid(StringArg(args, "uuid", ""), &service)) {
    return ErrorMap("Zly UUID uslugi", 0);
  }
  const bool secure = BoolArg(args, "secure", true);
  const int64_t timeout_ms = IntArg(args, "timeoutMs", 5000);
  const std::wstring name = Widen(StringArg(args, "name", "Chatt"));

  if (g_bench_listening == INVALID_SOCKET) {
    g_bench_listening = socket(AF_BTH, SOCK_STREAM, BTHPROTO_RFCOMM);
    if (g_bench_listening == INVALID_SOCKET) {
      return ErrorMap("Nie da sie otworzyc gniazda RFCOMM", WSAGetLastError());
    }
    if (secure) {
      ULONG on = TRUE;
      setsockopt(g_bench_listening, SOL_RFCOMM, SO_BTH_AUTHENTICATE,
                 reinterpret_cast<const char*>(&on), sizeof(on));
      setsockopt(g_bench_listening, SOL_RFCOMM, SO_BTH_ENCRYPT,
                 reinterpret_cast<const char*>(&on), sizeof(on));
    }

    SOCKADDR_BTH local = {};
    local.addressFamily = AF_BTH;
    local.btAddr = 0;
    local.serviceClassId = service;
    local.port = BT_PORT_ANY;
    if (bind(g_bench_listening, reinterpret_cast<SOCKADDR*>(&local),
             sizeof(local)) == SOCKET_ERROR) {
      const int code = WSAGetLastError();
      BenchCloseAll();
      return ErrorMap("bind sie nie udal", code);
    }
    if (listen(g_bench_listening, 1) == SOCKET_ERROR) {
      const int code = WSAGetLastError();
      BenchCloseAll();
      return ErrorMap("listen sie nie udal", code);
    }
    g_bench_bound = {};
    int length = static_cast<int>(sizeof(g_bench_bound));
    if (getsockname(g_bench_listening,
                    reinterpret_cast<SOCKADDR*>(&g_bench_bound),
                    &length) == SOCKET_ERROR) {
      const int code = WSAGetLastError();
      BenchCloseAll();
      return ErrorMap("getsockname sie nie udal", code);
    }
    g_bench_service = service;
    g_bench_sdp = PublishSdp(service, name, &g_bench_bound, true);
    if (!g_bench_sdp) {
      const int code = WSAGetLastError();
      BenchCloseAll();
      return ErrorMap("Nie da sie oglosic uslugi w SDP", code);
    }
  }

  // FD_SET jako makro potrafi zapalic ostrzezenie, a runner ma /WX.
  fd_set readable = {};
  readable.fd_count = 1;
  readable.fd_array[0] = g_bench_listening;
  timeval limit = {};
  limit.tv_sec = static_cast<long>(timeout_ms / 1000);
  limit.tv_usec = static_cast<long>((timeout_ms % 1000) * 1000);

  const int ready = select(0, &readable, nullptr, nullptr, &limit);
  EncodableMap out;
  if (ready == 0) {
    out[EncodableValue("connected")] = EncodableValue(false);
    return EncodableValue(out);
  }
  if (ready == SOCKET_ERROR) {
    return ErrorMap("select sie nie udal", WSAGetLastError());
  }

  SOCKADDR_BTH peer = {};
  int peer_length = static_cast<int>(sizeof(peer));
  SOCKET fresh = accept(g_bench_listening,
                        reinterpret_cast<SOCKADDR*>(&peer), &peer_length);
  if (fresh == INVALID_SOCKET) {
    return ErrorMap("accept sie nie udal", WSAGetLastError());
  }
  g_bench_data = fresh;
  if (g_bench_sdp) {
    PublishSdp(g_bench_service, name, &g_bench_bound, false);
    g_bench_sdp = false;
  }
  CloseSocket(g_bench_listening);

  out[EncodableValue("connected")] = EncodableValue(true);
  out[EncodableValue("peer")] = EncodableValue(FormatAddress(peer.btAddr));
  return EncodableValue(out);
}

EncodableValue BenchConnect(const EncodableMap* args) {
  if (g_bench_data != INVALID_SOCKET) {
    EncodableMap out;
    out[EncodableValue("connected")] = EncodableValue(true);
    return EncodableValue(out);
  }

  BTH_ADDR address = 0;
  if (!ParseAddress(StringArg(args, "address", ""), &address)) {
    return ErrorMap("Zly adres urzadzenia", 0);
  }
  GUID service = {};
  if (!ParseGuid(StringArg(args, "uuid", ""), &service)) {
    return ErrorMap("Zly UUID uslugi", 0);
  }
  const bool secure = BoolArg(args, "secure", true);

  SOCKET fresh = socket(AF_BTH, SOCK_STREAM, BTHPROTO_RFCOMM);
  if (fresh == INVALID_SOCKET) {
    return ErrorMap("Nie da sie otworzyc gniazda RFCOMM", WSAGetLastError());
  }
  if (secure) {
    ULONG on = TRUE;
    setsockopt(fresh, SOL_RFCOMM, SO_BTH_AUTHENTICATE,
               reinterpret_cast<const char*>(&on), sizeof(on));
  }

  SOCKADDR_BTH target = {};
  target.addressFamily = AF_BTH;
  target.btAddr = address;
  target.serviceClassId = service;
  target.port = 0;

  if (connect(fresh, reinterpret_cast<SOCKADDR*>(&target), sizeof(target)) ==
      SOCKET_ERROR) {
    const int code = WSAGetLastError();
    closesocket(fresh);
    return ErrorMap("connect sie nie udal", code);
  }
  g_bench_data = fresh;

  EncodableMap out;
  out[EncodableValue("connected")] = EncodableValue(true);
  out[EncodableValue("peer")] = EncodableValue(FormatAddress(address));
  return EncodableValue(out);
}

EncodableValue BenchSend(const EncodableMap* args) {
  if (g_bench_data == INVALID_SOCKET) {
    return ErrorMap("Brak polaczenia", 0);
  }
  const int64_t total = IntArg(args, "bytes", 0);
  int64_t chunk = IntArg(args, "chunk", 1024);
  if (chunk < 1) {
    chunk = 1;
  }
  BenchTimeouts(IntArg(args, "timeoutMs", 60000));

  std::vector<char> buffer(static_cast<size_t>(chunk));
  const int64_t start = NowMicros();
  int64_t done = 0;
  while (done < total) {
    const int64_t take = (total - done) < chunk ? (total - done) : chunk;
    for (int64_t i = 0; i < take; ++i) {
      buffer[static_cast<size_t>(i)] = static_cast<char>(Pattern(done + i));
    }
    int64_t written = 0;
    while (written < take) {
      const int wrote = send(g_bench_data, buffer.data() + written,
                             static_cast<int>(take - written), 0);
      if (wrote == SOCKET_ERROR || wrote == 0) {
        return ErrorMap("send sie nie udal", WSAGetLastError());
      }
      written += wrote;
    }
    done += take;
  }

  EncodableMap out;
  out[EncodableValue("bytes")] = EncodableValue(done);
  out[EncodableValue("ms")] = EncodableValue((NowMicros() - start) / 1000);
  out[EncodableValue("chunk")] = EncodableValue(chunk);
  return EncodableValue(out);
}

EncodableValue BenchReceive(const EncodableMap* args) {
  if (g_bench_data == INVALID_SOCKET) {
    return ErrorMap("Brak polaczenia", 0);
  }
  const int64_t total = IntArg(args, "bytes", 0);
  BenchTimeouts(IntArg(args, "timeoutMs", 60000));

  std::vector<char> buffer(16 * 1024);
  int64_t done = 0;
  int64_t start = 0;
  bool started = false;
  bool ok = true;
  uint32_t hash = kFnvStart;
  while (done < total) {
    const int64_t left = total - done;
    const int want = left < static_cast<int64_t>(buffer.size())
                         ? static_cast<int>(left)
                         : static_cast<int>(buffer.size());
    const int read = recv(g_bench_data, buffer.data(), want, 0);
    if (read == SOCKET_ERROR || read == 0) {
      return ErrorMap("recv sie nie udal", WSAGetLastError());
    }
    if (!started) {
      start = NowMicros();
      started = true;
    }
    for (int i = 0; i < read; ++i) {
      const unsigned char value =
          static_cast<unsigned char>(buffer[static_cast<size_t>(i)]);
      if (value != Pattern(done + i)) {
        ok = false;
      }
      hash = (hash ^ value) * kFnvPrime;
    }
    done += read;
  }

  EncodableMap out;
  out[EncodableValue("bytes")] = EncodableValue(done);
  out[EncodableValue("ms")] = EncodableValue((NowMicros() - start) / 1000);
  out[EncodableValue("ok")] = EncodableValue(ok);
  out[EncodableValue("hash")] = EncodableValue(static_cast<int32_t>(hash));
  return EncodableValue(out);
}

bool BenchReadExactly(char* buffer, int length) {
  int done = 0;
  while (done < length) {
    const int read = recv(g_bench_data, buffer + done, length - done, 0);
    if (read == SOCKET_ERROR || read == 0) {
      return false;
    }
    done += read;
  }
  return true;
}

bool BenchWriteExactly(const char* buffer, int length) {
  int done = 0;
  while (done < length) {
    const int wrote = send(g_bench_data, buffer + done, length - done, 0);
    if (wrote == SOCKET_ERROR || wrote == 0) {
      return false;
    }
    done += wrote;
  }
  return true;
}

// Czas obrotu krotkiej wiadomosci. Ruch Chatta to glownie krotkie teksty,
// wiec ta liczba wazy wiecej niz przepustowosc hurtowa.
EncodableValue BenchPing(const EncodableMap* args, bool answering) {
  if (g_bench_data == INVALID_SOCKET) {
    return ErrorMap("Brak polaczenia", 0);
  }
  int64_t size = IntArg(args, "bytes", 200);
  int64_t rounds = IntArg(args, "rounds", 20);
  if (size < 1) {
    size = 1;
  }
  if (rounds < 1) {
    rounds = 1;
  }
  BenchTimeouts(IntArg(args, "timeoutMs", 60000));

  const int length = static_cast<int>(size);
  std::vector<char> buffer(static_cast<size_t>(length));
  std::vector<char> back(static_cast<size_t>(length));
  if (!answering) {
    for (int i = 0; i < length; ++i) {
      buffer[static_cast<size_t>(i)] = static_cast<char>(Pattern(i));
    }
  }

  const int64_t start = NowMicros();
  for (int64_t round = 0; round < rounds; ++round) {
    if (answering) {
      if (!BenchReadExactly(buffer.data(), length) ||
          !BenchWriteExactly(buffer.data(), length)) {
        return ErrorMap("echo sie nie udalo", WSAGetLastError());
      }
    } else {
      if (!BenchWriteExactly(buffer.data(), length) ||
          !BenchReadExactly(back.data(), length)) {
        return ErrorMap("ping sie nie udal", WSAGetLastError());
      }
    }
  }

  EncodableMap out;
  out[EncodableValue("rounds")] = EncodableValue(rounds);
  out[EncodableValue("ms")] = EncodableValue((NowMicros() - start) / 1000);
  out[EncodableValue("bytes")] = EncodableValue(size);
  return EncodableValue(out);
}

}  // namespace

void RegisterChattBluetooth(flutter::FlutterEngine* engine) {
  static auto channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          engine->messenger(), "chatt/bluetooth",
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (!StartWinsock()) {
          result->Error("winsock", "Nie da sie uruchomic Winsocka");
          return;
        }
        const auto* args = std::get_if<EncodableMap>(call.arguments());
        const std::string& method = call.method_name();

        // Rodzina link* i scan* wraca natychmiast: wszystko, co trwa, dzieje
        // sie wlasnym watkiem i melduje przez linkPoll albo scanResults.
        // Watek platformy nie ma prawa czekac, bo na nim stoi caly interfejs.
        if (method == "status") {
          result->Success(Status());
          return;
        }
        if (method == "openLocationSettings") {
          result->Success(EncodableValue(false));
          return;
        }
        if (method == "openSettings") {
          // Windows nie ma czego pytac o zgode: radio wlacza uzytkownik
          // w ustawieniach systemu.
          result->Success(EncodableValue(false));
          return;
        }
        if (method == "discoverable") {
          result->Success(SetDiscoverable(args));
          return;
        }
        if (method == "scan") {
          result->Success(Scan());
          return;
        }
        if (method == "scanResults") {
          result->Success(ScanResults());
          return;
        }
        if (method == "linkStart") {
          result->Success(LinkStart(args));
          return;
        }
        if (method == "linkStop") {
          result->Success(LinkStop());
          return;
        }
        if (method == "linkConnect") {
          result->Success(LinkConnect(args));
          return;
        }
        if (method == "linkClose") {
          result->Success(LinkClose(args));
          return;
        }
        if (method == "linkPoll") {
          result->Success(LinkPoll());
          return;
        }

        // Pomiar z rozpoznania. Te blokuja watek platformy i tak ma byc:
        // wola je wylacznie tool/bt_spike.dart, ktory nie ma interfejsu.
        if (method == "benchListen") {
          result->Success(BenchListen(args));
          return;
        }
        if (method == "benchConnect") {
          result->Success(BenchConnect(args));
          return;
        }
        if (method == "benchSend") {
          result->Success(BenchSend(args));
          return;
        }
        if (method == "benchReceive") {
          result->Success(BenchReceive(args));
          return;
        }
        if (method == "benchPing") {
          result->Success(BenchPing(args, false));
          return;
        }
        if (method == "benchEcho") {
          result->Success(BenchPing(args, true));
          return;
        }
        if (method == "benchClose") {
          BenchCloseAll();
          result->Success(EncodableValue(true));
          return;
        }
        result->NotImplemented();
      });
}

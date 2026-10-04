#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>
#include <tlhelp32.h>

#include <cstdarg>
#include <iostream>

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  unsigned int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, nullptr, 0, nullptr, nullptr)
    -1; // remove the trailing null character
  int input_length = (int)wcslen(utf16_string);
  std::string utf8_string;
  if (target_length == 0 || target_length > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}

void StartLogRegel(const char* opmaak, ...) {
  char tekst[600];
  va_list args;
  va_start(args, opmaak);
  vsnprintf(tekst, sizeof(tekst), opmaak, args);
  va_end(args);

  // Dezelfde map als `initAppPaths` in lib/paths.dart: %APPDATA%\DebridMusic.
  wchar_t map[MAX_PATH];
  const DWORD lengte = ::GetEnvironmentVariableW(L"APPDATA", map, MAX_PATH);
  if (lengte == 0 || lengte >= MAX_PATH) {
    return;
  }
  std::wstring pad(map, lengte);
  pad += L"\\DebridMusic\\start.log";

  // Tot op de milliseconde en in plaatselijke tijd, zoals `DateTime.now()` aan de Dart-kant.
  // GetLocalTime loopt in tikken van zo'n 15 ms, en twee regels liggen hier soms dichter bij elkaar.
  FILETIME utc = {};
  FILETIME lokaal = {};
  SYSTEMTIME tijd = {};
  ::GetSystemTimePreciseAsFileTime(&utc);
  if (!::FileTimeToLocalFileTime(&utc, &lokaal) ||
      !::FileTimeToSystemTime(&lokaal, &tijd)) {
    ::GetLocalTime(&tijd);
  }
  char regel[640];
  const int n = snprintf(regel, sizeof(regel), "%02u:%02u:%02u.%03u  %s\n",
                         static_cast<unsigned>(tijd.wHour),
                         static_cast<unsigned>(tijd.wMinute),
                         static_cast<unsigned>(tijd.wSecond),
                         static_cast<unsigned>(tijd.wMilliseconds), tekst);
  if (n <= 0) {
    return;
  }
  size_t lang = static_cast<size_t>(n);
  if (lang >= sizeof(regel)) {
    lang = sizeof(regel) - 1;
    regel[lang - 1] = '\n';
  }

  // FILE_APPEND_DATA: elke WriteFile landt in zijn geheel achteraan. En alle drie de deelvlaggen,
  // zodat dit en `WarmLog` aan de Dart-kant elkaar nooit buitensluiten.
  HANDLE bestand = ::CreateFileW(
      pad.c_str(), FILE_APPEND_DATA,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
      OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (bestand == INVALID_HANDLE_VALUE) {
    return;
  }
  DWORD geschreven = 0;
  ::WriteFile(bestand, regel, static_cast<DWORD>(lang), &geschreven, nullptr);
  ::CloseHandle(bestand);
}

std::string OuderProces() {
  HANDLE foto = ::CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (foto == INVALID_HANDLE_VALUE) {
    return std::string();
  }
  const DWORD ik = ::GetCurrentProcessId();
  DWORD ouder = 0;
  PROCESSENTRY32W item = {};
  item.dwSize = static_cast<DWORD>(sizeof(item));
  for (BOOL verder = ::Process32FirstW(foto, &item); verder;
       verder = ::Process32NextW(foto, &item)) {
    if (item.th32ProcessID == ik) {
      ouder = item.th32ParentProcessID;
      break;
    }
  }
  std::string naam;
  if (ouder != 0) {
    item.dwSize = static_cast<DWORD>(sizeof(item));
    for (BOOL verder = ::Process32FirstW(foto, &item); verder;
         verder = ::Process32NextW(foto, &item)) {
      if (item.th32ProcessID == ouder) {
        naam = Utf8FromUtf16(item.szExeFile);
        break;
      }
    }
  }
  ::CloseHandle(foto);
  if (ouder == 0) {
    return std::string();
  }
  // Een ouder die al weg is laat alleen zijn nummer achter.
  return std::to_string(ouder) + " " + (naam.empty() ? std::string("(al weg)") : naam);
}

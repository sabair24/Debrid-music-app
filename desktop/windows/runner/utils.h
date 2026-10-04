#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

// Creates a console for the process, and redirects stdout and stderr to
// it for both the runner and the Flutter library.
void CreateAndAttachConsole();

// Takes a null-terminated wchar_t* encoded in UTF-16 and returns a std::string
// encoded in UTF-8. Returns an empty std::string on failure.
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// Gets the command line arguments passed in as a std::vector<std::string>,
// encoded in UTF-8. Returns an empty std::vector<std::string> on failure.
std::vector<std::string> GetCommandLineArguments();

// Eén regel achteraan %APPDATA%\DebridMusic\start.log, met dezelfde tijdkop als de Dart-kant
// (`12:03:42.947  `). Opmaak zoals printf. Zwijgt bij elke fout: een logboek mag de app niet breken.
//
// Hetzelfde bestand en niet een eigen, zodat wat Windows met het venster doet en wat de app ervan
// denkt op één tijdlijn staan. Dat was de vraag op 04-10-2026: na een update opende het venster klein
// en een gewone start niet, en niets schreef op wat er tussen het eerste beeld en "klein" gebeurde.
void StartLogRegel(const char* opmaak, ...);

// "43920 DebridMusic-Setup-3.9.435.tmp": wie dit proces startte. Leeg als dat niet te vinden is.
std::string OuderProces();

#endif  // RUNNER_UTILS_H_

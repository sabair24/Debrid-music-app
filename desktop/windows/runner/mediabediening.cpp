#include "mediabediening.h"

// De headers van Windows zelf op waarschuwingsniveau 0: deze bouw draait met /W4 /WX, en een
// waarschuwing in een systeemheader is dan een fout die wij niet kunnen repareren.
#pragma warning(push, 0)
#include <roapi.h>
#include <shcore.h>
#include <shlwapi.h>
#include <shobjidl.h>
#include <systemmediatransportcontrolsinterop.h>
#include <windows.foundation.h>
#include <windows.media.h>
#include <windows.storage.streams.h>
#include <wrl/client.h>
#include <wrl/event.h>
#include <wrl/wrappers/corewrappers.h>
#pragma warning(pop)

#include <flutter/standard_method_codec.h>

#include "utils.h"

#include <map>
#include <variant>

namespace {

namespace wf = ABI::Windows::Foundation;
namespace wm = ABI::Windows::Media;
namespace wss = ABI::Windows::Storage::Streams;
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Wrappers::HStringReference;

constexpr boolean kJa = 1;
constexpr boolean kNee = 0;

// De drie knoppen in de taakbalk.
constexpr UINT kKnopVorige = 1;
constexpr UINT kKnopSpeel = 2;
constexpr UINT kKnopVolgende = 3;

// De tekens uit "Segoe MDL2 Assets" (Windows 10 en 11): vorige, afspelen, pauze, volgende.
constexpr wchar_t kTekenVorige = 0xE892;
constexpr wchar_t kTekenSpeel = 0xE768;
constexpr wchar_t kTekenPauze = 0xE769;
constexpr wchar_t kTekenVolgende = 0xE893;

std::wstring NaarBreed(const std::string& tekst) {
  if (tekst.empty()) {
    return std::wstring();
  }
  const int lengte = MultiByteToWideChar(CP_UTF8, 0, tekst.data(),
                                         static_cast<int>(tekst.size()), nullptr, 0);
  if (lengte <= 0) {
    return std::wstring();
  }
  std::wstring uit(static_cast<size_t>(lengte), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, tekst.data(), static_cast<int>(tekst.size()), &uit[0],
                      lengte);
  return uit;
}

// Een icoon van één teken uit het pictogramlettertype van Windows, wit met een zachte rand. Het
// teken wordt wit op zwart getekend en de grijswaarde wordt de doorzichtigheid.
HICON MaakIcoon(wchar_t teken) {
  const int maat = GetSystemMetrics(SM_CXSMICON);
  HDC scherm = GetDC(nullptr);
  HDC dc = CreateCompatibleDC(scherm);
  BITMAPINFO info = {};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = maat;
  info.bmiHeader.biHeight = -maat;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* punten = nullptr;
  HBITMAP kleur = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &punten, nullptr, 0);
  HICON icoon = nullptr;
  if (kleur != nullptr && punten != nullptr) {
    HGDIOBJ oud = SelectObject(dc, kleur);
    const size_t aantal = static_cast<size_t>(maat) * static_cast<size_t>(maat);
    auto* px = static_cast<uint32_t*>(punten);
    for (size_t i = 0; i < aantal; ++i) {
      px[i] = 0;
    }
    HFONT letter = CreateFontW(-(maat * 3 / 4), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                               DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                               ANTIALIASED_QUALITY, DEFAULT_PITCH, L"Segoe MDL2 Assets");
    HGDIOBJ oudeLetter = SelectObject(dc, letter);
    SetTextColor(dc, RGB(255, 255, 255));
    SetBkMode(dc, TRANSPARENT);
    RECT vak = {0, 0, maat, maat};
    wchar_t tekst[2] = {teken, 0};
    DrawTextW(dc, tekst, 1, &vak, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    GdiFlush();
    for (size_t i = 0; i < aantal; ++i) {
      const uint32_t grijs = (px[i] >> 8) & 0xFFu;
      px[i] = (grijs << 24) | (grijs << 16) | (grijs << 8) | grijs;
    }
    SelectObject(dc, oudeLetter);
    DeleteObject(letter);
    SelectObject(dc, oud);
    // Het masker wordt bij een kleurbeeld met doorzichtigheid niet gebruikt, maar moet er zijn.
    std::vector<BYTE> leeg(static_cast<size_t>((maat + 15) / 16 * 2 * maat), 0);
    HBITMAP masker = CreateBitmap(maat, maat, 1, 1, leeg.data());
    ICONINFO ii = {};
    ii.fIcon = TRUE;
    ii.hbmMask = masker;
    ii.hbmColor = kleur;
    icoon = CreateIconIndirect(&ii);
    DeleteObject(masker);
  }
  if (kleur != nullptr) {
    DeleteObject(kleur);
  }
  DeleteDC(dc);
  ReleaseDC(nullptr, scherm);
  return icoon;
}

const char* KnopNaam(wm::SystemMediaTransportControlsButton knop) {
  switch (knop) {
    case wm::SystemMediaTransportControlsButton_Play:
      return "afspelen";
    case wm::SystemMediaTransportControlsButton_Pause:
      return "pauze";
    case wm::SystemMediaTransportControlsButton_Stop:
      return "stop";
    case wm::SystemMediaTransportControlsButton_Next:
      return "volgende";
    case wm::SystemMediaTransportControlsButton_Previous:
      return "vorige";
    default:
      return nullptr;
  }
}

}  // namespace

struct Mediabediening::Binnen {
  HWND venster = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> kanaal;

  ComPtr<wm::ISystemMediaTransportControls> smtc;
  ComPtr<wm::ISystemMediaTransportControlsDisplayUpdater> scherm;
  EventRegistrationToken knopToken = {};

  UINT taakbalkBericht = 0;
  ComPtr<ITaskbarList3> taakbalk;
  bool knoppenStaan = false;
  HICON icoonVorige = nullptr;
  HICON icoonSpeel = nullptr;
  HICON icoonPauze = nullptr;
  HICON icoonVolgende = nullptr;
  bool speelt = false;

  void MaakSmtc() {
    ComPtr<ISystemMediaTransportControlsInterop> interop;
    HRESULT hr = RoGetActivationFactory(
        HStringReference(RuntimeClass_Windows_Media_SystemMediaTransportControls).Get(),
        IID_PPV_ARGS(&interop));
    if (FAILED(hr) || !interop) {
      StartLogRegel("media: geen mediabediening van Windows (fabriek, hr=0x%08lX)", static_cast<unsigned long>(hr));
      return;
    }
    hr = interop->GetForWindow(venster, IID_PPV_ARGS(&smtc));
    if (FAILED(hr) || !smtc) {
      StartLogRegel("media: geen mediabediening van Windows (venster, hr=0x%08lX)", static_cast<unsigned long>(hr));
      smtc.Reset();
      return;
    }
    smtc->put_IsEnabled(kJa);
    smtc->put_IsPlayEnabled(kJa);
    smtc->put_IsPauseEnabled(kJa);
    smtc->put_IsStopEnabled(kJa);
    smtc->put_IsNextEnabled(kJa);
    smtc->put_IsPreviousEnabled(kJa);
    smtc->put_PlaybackStatus(wm::MediaPlaybackStatus_Closed);
    HWND doel = venster;
    auto opKnop = Microsoft::WRL::Callback<wf::ITypedEventHandler<
        wm::SystemMediaTransportControls*, wm::SystemMediaTransportControlsButtonPressedEventArgs*>>(
        [doel](wm::ISystemMediaTransportControls*,
               wm::ISystemMediaTransportControlsButtonPressedEventArgs* args) -> HRESULT {
          wm::SystemMediaTransportControlsButton knop = wm::SystemMediaTransportControlsButton_Play;
          if (args == nullptr || FAILED(args->get_Button(&knop))) {
            return S_OK;
          }
          // Een eigen draad van Windows: naar de vensterdraad, daar mag het kanaal gebruikt worden.
          PostMessageW(doel, kMediaKnopBericht, static_cast<WPARAM>(knop), 0);
          return S_OK;
        });
    hr = smtc->add_ButtonPressed(opKnop.Get(), &knopToken);
    StartLogRegel("media: aangemeld bij de mediabediening van Windows (knoppen hr=0x%08lX)",
                  static_cast<unsigned long>(hr));
    smtc->get_DisplayUpdater(&scherm);
  }

  void ZetStand(bool nuSpeelt, bool heeftNummer, const std::string& titel, const std::string& artiest,
                const std::string& album, const std::vector<uint8_t>* hoes) {
    speelt = nuSpeelt;
    WerkTaakbalkBij();
    if (!smtc) {
      return;
    }
    if (!heeftNummer) {
      smtc->put_PlaybackStatus(wm::MediaPlaybackStatus_Stopped);
      if (scherm) {
        scherm->ClearAll();
      }
      return;
    }
    smtc->put_PlaybackStatus(nuSpeelt ? wm::MediaPlaybackStatus_Playing : wm::MediaPlaybackStatus_Paused);
    if (!scherm) {
      return;
    }
    scherm->put_Type(wm::MediaPlaybackType_Music);
    ComPtr<wm::IMusicDisplayProperties> muziek;
    if (SUCCEEDED(scherm->get_MusicProperties(&muziek)) && muziek) {
      const std::wstring t = NaarBreed(titel);
      const std::wstring a = NaarBreed(artiest);
      muziek->put_Title(HStringReference(t.c_str(), static_cast<unsigned int>(t.size())).Get());
      muziek->put_Artist(HStringReference(a.c_str(), static_cast<unsigned int>(a.size())).Get());
      ComPtr<wm::IMusicDisplayProperties2> muziek2;
      if (SUCCEEDED(muziek.As(&muziek2)) && muziek2) {
        const std::wstring al = NaarBreed(album);
        muziek2->put_AlbumTitle(HStringReference(al.c_str(), static_cast<unsigned int>(al.size())).Get());
      }
    }
    if (hoes != nullptr && !hoes->empty()) {
      ZetHoes(*hoes);
    }
    scherm->Update();
  }

  void ZetHoes(const std::vector<uint8_t>& bytes) {
    ComPtr<IStream> stroom;
    stroom.Attach(SHCreateMemStream(bytes.data(), static_cast<UINT>(bytes.size())));
    if (!stroom) {
      return;
    }
    ComPtr<wss::IRandomAccessStream> willekeurig;
    if (FAILED(CreateRandomAccessStreamOverStream(stroom.Get(), BSOS_DEFAULT,
                                                  IID_PPV_ARGS(&willekeurig))) ||
        !willekeurig) {
      return;
    }
    ComPtr<wss::IRandomAccessStreamReferenceStatics> fabriek;
    if (FAILED(RoGetActivationFactory(
            HStringReference(RuntimeClass_Windows_Storage_Streams_RandomAccessStreamReference).Get(),
            IID_PPV_ARGS(&fabriek))) ||
        !fabriek) {
      return;
    }
    ComPtr<wss::IRandomAccessStreamReference> verwijzing;
    if (SUCCEEDED(fabriek->CreateFromStream(willekeurig.Get(), &verwijzing)) && verwijzing) {
      scherm->put_Thumbnail(verwijzing.Get());
    }
  }

  void MaakTaakbalkKnoppen() {
    if (knoppenStaan) {
      return;
    }
    if (!taakbalk) {
      if (FAILED(CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                                  IID_PPV_ARGS(&taakbalk))) ||
          !taakbalk || FAILED(taakbalk->HrInit())) {
        taakbalk.Reset();
        return;
      }
    }
    if (icoonVorige == nullptr) icoonVorige = MaakIcoon(kTekenVorige);
    if (icoonSpeel == nullptr) icoonSpeel = MaakIcoon(kTekenSpeel);
    if (icoonPauze == nullptr) icoonPauze = MaakIcoon(kTekenPauze);
    if (icoonVolgende == nullptr) icoonVolgende = MaakIcoon(kTekenVolgende);
    THUMBBUTTON knoppen[3] = {};
    Vul(knoppen[0], kKnopVorige, icoonVorige, L"Vorige");
    Vul(knoppen[1], kKnopSpeel, speelt ? icoonPauze : icoonSpeel, speelt ? L"Pauzeren" : L"Afspelen");
    Vul(knoppen[2], kKnopVolgende, icoonVolgende, L"Volgende");
    const HRESULT hr = taakbalk->ThumbBarAddButtons(venster, 3, knoppen);
    knoppenStaan = SUCCEEDED(hr);
    StartLogRegel("media: knoppen in de taakbalk %s (hr=0x%08lX)", knoppenStaan ? "gezet" : "NIET gezet",
                  static_cast<unsigned long>(hr));
  }

  void WerkTaakbalkBij() {
    if (!knoppenStaan || !taakbalk) {
      return;
    }
    THUMBBUTTON knop = {};
    Vul(knop, kKnopSpeel, speelt ? icoonPauze : icoonSpeel, speelt ? L"Pauzeren" : L"Afspelen");
    taakbalk->ThumbBarUpdateButtons(venster, 1, &knop);
  }

  static void Vul(THUMBBUTTON& knop, UINT id, HICON icoon, const wchar_t* tip) {
    knop.dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
    knop.iId = id;
    knop.hIcon = icoon;
    knop.dwFlags = THBF_ENABLED;
    wcscpy_s(knop.szTip, tip);
  }

  void Stuur(const char* knop) {
    StartLogRegel("media: knop %s naar de app%s", knop == nullptr ? "(onbekend)" : knop,
                  kanaal ? "" : " -- GEEN KANAAL");
    if (kanaal && knop != nullptr) {
      kanaal->InvokeMethod("knop", std::make_unique<flutter::EncodableValue>(std::string(knop)));
    }
  }
};

Mediabediening::Mediabediening(HWND venster, flutter::BinaryMessenger* boodschapper)
    : binnen_(std::make_unique<Binnen>()) {
  binnen_->venster = venster;
  binnen_->taakbalkBericht = RegisterWindowMessageW(L"TaskbarButtonCreated");
  binnen_->kanaal = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      boodschapper, "debridmusic/mediabediening", &flutter::StandardMethodCodec::GetInstance());
  Binnen* b = binnen_.get();
  binnen_->kanaal->SetMethodCallHandler(
      [b](const flutter::MethodCall<flutter::EncodableValue>& oproep,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> antwoord) {
        if (oproep.method_name() != "stand") {
          antwoord->NotImplemented();
          return;
        }
        const auto* kaart = std::get_if<flutter::EncodableMap>(oproep.arguments());
        if (kaart == nullptr) {
          antwoord->Error("stand", "geen kaart");
          return;
        }
        auto lees = [kaart](const char* sleutel) -> const flutter::EncodableValue* {
          auto it = kaart->find(flutter::EncodableValue(std::string(sleutel)));
          return it == kaart->end() ? nullptr : &it->second;
        };
        auto tekst = [&lees](const char* sleutel) -> std::string {
          const auto* v = lees(sleutel);
          const auto* s = v == nullptr ? nullptr : std::get_if<std::string>(v);
          return s == nullptr ? std::string() : *s;
        };
        const auto* speeltWaarde = lees("speelt");
        const bool* speelt = speeltWaarde == nullptr ? nullptr : std::get_if<bool>(speeltWaarde);
        const auto* hoesWaarde = lees("hoes");
        const auto* hoes =
            hoesWaarde == nullptr ? nullptr : std::get_if<std::vector<uint8_t>>(hoesWaarde);
        const std::string titel = tekst("titel");
        b->ZetStand(speelt != nullptr && *speelt, !titel.empty(), titel, tekst("artiest"),
                    tekst("album"), hoes);
        antwoord->Success();
      });
  binnen_->MaakSmtc();
}

Mediabediening::~Mediabediening() {
  if (binnen_->smtc) {
    binnen_->smtc->remove_ButtonPressed(binnen_->knopToken);
    binnen_->smtc->put_IsEnabled(kNee);
  }
  for (HICON icoon : {binnen_->icoonVorige, binnen_->icoonSpeel, binnen_->icoonPauze,
                      binnen_->icoonVolgende}) {
    if (icoon != nullptr) {
      DestroyIcon(icoon);
    }
  }
  if (binnen_->kanaal) {
    binnen_->kanaal->SetMethodCallHandler(nullptr);
  }
}

bool Mediabediening::Bericht(UINT bericht, WPARAM wparam, LPARAM lparam) {
  (void)lparam;
  if (bericht == kMediaKnopBericht) {
    StartLogRegel("media: bericht van Windows binnen (knop %d)", static_cast<int>(wparam));
    binnen_->Stuur(KnopNaam(static_cast<wm::SystemMediaTransportControlsButton>(wparam)));
    return true;
  }
  if (binnen_->taakbalkBericht != 0 && bericht == binnen_->taakbalkBericht) {
    // De knop in de taakbalk bestaat (weer): na het starten, en na een herstart van Verkenner.
    binnen_->knoppenStaan = false;
    binnen_->MaakTaakbalkKnoppen();
    return false;
  }
  if (bericht == WM_COMMAND && HIWORD(wparam) == THBN_CLICKED) {
    switch (LOWORD(wparam)) {
      case kKnopVorige:
        binnen_->Stuur("vorige");
        return true;
      case kKnopSpeel:
        binnen_->Stuur("speelpauze");
        return true;
      case kKnopVolgende:
        binnen_->Stuur("volgende");
        return true;
      default:
        break;
    }
  }
  return false;
}

#ifndef RUNNER_MEDIABEDIENING_H_
#define RUNNER_MEDIABEDIENING_H_

// De mediabediening van Windows en de knoppen in de taakbalk (Saber, 17-10-2026: "mijn media
// toetsen op men toetsenbord moeten er op werken, ik heb een logitech G213 toetsenbord", en
// "knoppen in de taakbalk").
//
// **Waarom via Windows en niet via de toetsen zelf.** De mediatoetsen van een toetsenbord gaan in
// Windows naar de "System Media Transport Controls": het venstertje met de hoes dat verschijnt als
// je op zo'n toets drukt. Wie zich daar aanmeldt, krijgt de toetsen, ook als zijn venster op de
// achtergrond staat; speelt er ook iets in Chrome, dan beslist Windows (wie het laatst speelde).
// Dat is wat Saber koos. De toetsen zelf afvangen zou Chrome en Spotify ze afpakken.
//
// De knoppen in de taakbalk zijn de drie onder het voorbeeld als je met de muis op het
// taakbalkpictogram staat: vorige, afspelen of pauze, volgende — zoals Spotify.
//
// Dart vertelt over het kanaal "debridmusic/mediabediening" wat er speelt ("stand"), en krijgt
// terug welke knop er ingedrukt werd ("knop"). Windows meldt een knop van de mediabediening op een
// eigen draad; hier gaat dat via PostMessage naar de vensterdraad, want een Flutter-kanaal mag
// alleen daar gebruikt worden.

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

// Het bericht waarmee de draad van Windows een knop doorgeeft aan het venster. WPARAM = welke.
constexpr UINT kMediaKnopBericht = WM_APP + 0x51;

class Mediabediening {
 public:
  Mediabediening(HWND venster, flutter::BinaryMessenger* boodschapper);
  ~Mediabediening();

  Mediabediening(const Mediabediening&) = delete;
  Mediabediening& operator=(const Mediabediening&) = delete;

  // Een vensterbericht dat hierbij hoort? Dan afgehandeld en waar.
  bool Bericht(UINT bericht, WPARAM wparam, LPARAM lparam);

 private:
  struct Binnen;
  std::unique_ptr<Binnen> binnen_;
};

#endif  // RUNNER_MEDIABEDIENING_H_

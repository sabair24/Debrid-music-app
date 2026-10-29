/// De versleutelde poorten van de pc. Apart, zodat een toestel ze kent zonder de hele server te laden.
/// Zie `server.dart` voor wat er op welke poort mag.
library;

/// De gewone poort (HTTP, thuis en Tailscale), met HTTP-sleutels. Gelijk aan `kLanPort` op de pc.
const int kHttpPoort = 47820;

/// De versleutelde poort voor thuis en Tailscale (alleen privé-adressen), met TLS-sleutels.
const int kTlsPoort = 47822;

/// De versleutelde poort voor buiten: het enige doel van de deur in de modem (UPnP), met een witte lijst.
const int kPubliekPoort = 47821;

/// Een tweede buitenpoort naar dezelfde deur: 443, de poort van gewoon webverkeer. Een regel in de modem die je zelf
/// zet (buiten 443 → binnen [kPubliekPoort]); de pc luistert er niet zelf op.
///
/// **Waarom (Saber, 28-10-2026).** *"gisteren moest ik weer tailscale aanzetten, want rechtsstreeks ging niet, ik zat
/// wel op een heel zwak internet wifi signaal van een bedrijf"*. Gemeten op de pc: om 08:08–08:30 kwam hij rechtstreeks
/// binnen (246 MB muziek), daarna geen énkele poging meer op 47821 — een bedrijfsnetwerk dat alleen webverkeer doorlaat.
const int kWebPoort = 443;

/// De versleutelde poorten van de pc. Apart, zodat een toestel ze kent zonder de hele server te laden.
/// Zie `server.dart` voor wat er op welke poort mag.
library;

/// De versleutelde poort voor thuis en Tailscale (alleen privé-adressen), met TLS-sleutels.
const int kTlsPoort = 47822;

/// De versleutelde poort voor buiten: het enige doel van de deur in de modem (UPnP), met een witte lijst.
const int kPubliekPoort = 47821;

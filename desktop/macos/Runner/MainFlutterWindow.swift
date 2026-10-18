import Cocoa
import FlutterMacOS
import Network

/// Elke netwerkwissel naar Dart (lib/netwerkwissel.dart), zodat de app meteen een ander adres van de
/// pc kiest in plaats van te wachten tot een verzoek vastloopt. Stap 4 van "verbinden zoals Roon ARC"
/// (14-10-2026). Eén monitor zolang de app draait; alleen een echte wissel (wifi, mobiel, weg) wordt
/// een melding.
final class NetwerkWacht: NSObject, FlutterStreamHandler {
  private var monitor: NWPathMonitor?
  private var oor: FlutterEventSink?
  private var laatste = ""

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    oor = events
    if monitor == nil {
      let m = NWPathMonitor()
      m.pathUpdateHandler = { [weak self] pad in
        let transport: String
        if pad.status != .satisfied {
          transport = "weg"
        } else if pad.usesInterfaceType(.wifi) {
          transport = "wifi"
        } else if pad.usesInterfaceType(.cellular) {
          transport = "mobiel"
        } else if pad.usesInterfaceType(.wiredEthernet) {
          transport = "kabel"
        } else {
          transport = "anders"
        }
        let gevalideerd = pad.status == .satisfied
        DispatchQueue.main.async {
          guard let zelf = self else { return }
          let stand = "\(transport)|\(gevalideerd)"
          if stand == zelf.laatste { return }
          zelf.laatste = stand
          zelf.oor?([
            "soort": "pad",
            "netwerk": "",
            "transport": transport,
            "gevalideerd": gevalideerd,
          ])
        }
      }
      m.start(queue: DispatchQueue(label: "debridmusic.netwerk"))
      monitor = m
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    oor = nil
    return nil
  }
}

class MainFlutterWindow: NSWindow {
  private let netwerkWacht = NetwerkWacht()
  private var netwerkKanaal: FlutterEventChannel?
  private var systeemKanaal: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Netwerkwissels, zie NetwerkWacht hierboven.
    let kanaal = FlutterEventChannel(
      name: "debridmusic/netwerk", binaryMessenger: flutterViewController.engine.binaryMessenger)
    kanaal.setStreamHandler(netwerkWacht)
    netwerkKanaal = kanaal

    // Wil het systeem dicht glas? "Transparantie verminderen" of de energiebesparingsmodus. Zie
    // lib/systeem_glas.dart.
    let systeem = FlutterMethodChannel(
      name: "debridmusic/systeem", binaryMessenger: flutterViewController.engine.binaryMessenger)
    systeem.setMethodCallHandler { call, result in
      guard call.method == "dichtGlas" else {
        result(FlutterMethodNotImplemented)
        return
      }
      var zuinig = false
      if #available(macOS 12.0, *) {
        zuinig = ProcessInfo.processInfo.isLowPowerModeEnabled
      }
      result(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || zuinig)
    }
    systeemKanaal = systeem

    super.awakeFromNib()
  }
}

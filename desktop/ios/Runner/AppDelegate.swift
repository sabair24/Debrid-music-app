import Flutter
import Network
import UIKit

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

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Vastgehouden, zodat het kanaal blijft bestaan zolang de app draait.
  private var warmteKanaal: FlutterMethodChannel?
  private var systeemKanaal: FlutterMethodChannel?
  private var netwerkKanaal: FlutterEventChannel?
  private var ruimteKanaal: FlutterMethodChannel?
  private let netwerkWacht = NetwerkWacht()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // De warmtestand en de batterij voor de warmtemeter (lib/warmtemeter.dart). Een iPad hangt
    // niet aan een kabel; dit is hoe "hij wordt heet" meetbaar wordt.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DebridMusicWarmte") {
      let kanaal = FlutterMethodChannel(
        name: "debridmusic/warmte", binaryMessenger: registrar.messenger())
      kanaal.setMethodCallHandler { call, result in
        guard call.method == "stand" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let toestel = UIDevice.current
        toestel.isBatteryMonitoringEnabled = true
        result([
          "warmte": ProcessInfo.processInfo.thermalState.rawValue,
          "batterij": toestel.batteryLevel,
          "laden": toestel.batteryState.rawValue,
        ])
      }
      warmteKanaal = kanaal
    }

    // Wil het systeem dicht glas? "Minder transparantie" of de energiebesparingsmodus. Zie
    // lib/systeem_glas.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DebridMusicSysteem") {
      let kanaal = FlutterMethodChannel(
        name: "debridmusic/systeem", binaryMessenger: registrar.messenger())
      kanaal.setMethodCallHandler { call, result in
        guard call.method == "dichtGlas" else {
          result(FlutterMethodNotImplemented)
          return
        }
        result(UIAccessibility.isReduceTransparencyEnabled || ProcessInfo.processInfo.isLowPowerModeEnabled)
      }
      systeemKanaal = kanaal
    }

    // Vrije ruimte op dit toestel, voor de vraag vóór "Op dit toestel" (lib/ui/op_toestel.dart, Saber 29-10-2026).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DebridMusicRuimte") {
      let kanaal = FlutterMethodChannel(
        name: "debridmusic/ruimte", binaryMessenger: registrar.messenger())
      kanaal.setMethodCallHandler { call, result in
        guard call.method == "vrij" else {
          result(FlutterMethodNotImplemented)
          return
        }
        let map = URL(fileURLWithPath: NSHomeDirectory())
        if let w = try? map.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
          let vrij = w.volumeAvailableCapacityForImportantUsage
        {
          result(NSNumber(value: vrij))
        } else {
          result(nil)
        }
      }
      ruimteKanaal = kanaal
    }

    // Netwerkwissels, zie NetwerkWacht hierboven.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DebridMusicNetwerk") {
      let kanaal = FlutterEventChannel(name: "debridmusic/netwerk", binaryMessenger: registrar.messenger())
      kanaal.setStreamHandler(netwerkWacht)
      netwerkKanaal = kanaal
    }
  }
}

import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Vastgehouden, zodat het kanaal blijft bestaan zolang de app draait.
  private var warmteKanaal: FlutterMethodChannel?

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
  }
}

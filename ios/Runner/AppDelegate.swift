import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Covers the frame iOS captures for the App Switcher.
  ///
  /// That capture happens before `applicationDidEnterBackground`, so nothing on
  /// the Flutter side is early enough to hide the round's takings from it. A solid
  /// view installed in `applicationWillResignActive` is what gets captured
  /// instead. Same overlay the member app uses.
  private var snapshotOverlay: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    showSnapshotOverlay()
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    hideSnapshotOverlay()
  }

  private func showSnapshotOverlay() {
    guard snapshotOverlay == nil else { return }
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow } ?? self.window
    guard let window else { return }
    let overlay = UIView(frame: window.bounds)
    overlay.backgroundColor = UIColor(red: 0.94, green: 0.94, blue: 0.96, alpha: 1.0)
    window.addSubview(overlay)
    snapshotOverlay = overlay
  }

  private func hideSnapshotOverlay() {
    snapshotOverlay?.removeFromSuperview()
    snapshotOverlay = nil
  }
}

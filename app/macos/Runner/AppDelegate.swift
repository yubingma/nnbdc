import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Register AI inference channel
    let controller = mainFlutterWindow?.contentViewController as? FlutterViewController
    if let registrar = controller?.registrar(forPlugin: "AiInferenceChannel") {
      AiInferenceChannel.register(with: registrar)
    }
  }
  
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

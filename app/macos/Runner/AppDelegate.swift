import Cocoa
import FlutterMacOS
import StoreKit

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Register AI inference channel
    let controller = mainFlutterWindow?.contentViewController as? FlutterViewController
    if let registrar = controller?.registrar(forPlugin: "AiInferenceChannel") {
      AiInferenceChannel.register(with: registrar)
    }
    
    // Register OCR channel
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      OcrChannel.register(with: controller.engine.binaryMessenger)
    }
    
    // 设置应用评分 MethodChannel
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let reviewChannel = FlutterMethodChannel(
        name: "com.nnbdc.review",
        binaryMessenger: controller.engine.binaryMessenger
      )
      reviewChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
        self?.handleReviewMethodCall(call: call, result: result)
      }
    }
  }
  
  private func handleReviewMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestReview":
      requestAppReview(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  
  private func requestAppReview(result: @escaping FlutterResult) {
    print("macOS: Requesting app review")
    
    // macOS 不支持 SKStoreReviewController，直接返回成功
    NSLog("[AppDelegate] macOS 不支持应用内评分，跳过请求")
    result(nil)
  }
  
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationWillTerminate(_ notification: Notification) {
    AiInferenceChannel.cleanup()
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

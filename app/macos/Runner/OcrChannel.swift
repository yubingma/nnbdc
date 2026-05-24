import Cocoa
import FlutterMacOS
import Vision

/// 使用 Apple Vision 框架进行本地 OCR 文字识别（macOS 版本）
/// 注意：ML Kit 数字墨水识别为 iOS-only，macOS 上暂不支持手写识别
class OcrChannel {
    
    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: "nnbdc/ocr",
            binaryMessenger: messenger
        )
        
        channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
            switch call.method {
            case "recognizeText":
                guard let args = call.arguments as? [String: Any],
                      let imagePath = args["imagePath"] as? String else {
                    result(FlutterError(
                        code: "INVALID_ARGUMENTS",
                        message: "Missing imagePath parameter",
                        details: nil
                    ))
                    return
                }
                recognizeText(imagePath: imagePath, result: result)
                
            case "recognizeHandwriting":
                // macOS 不支持 ML Kit 数字墨水识别
                result(FlutterError(
                    code: "UNSUPPORTED_ON_MACOS",
                    message: "手写识别在 macOS 上暂不支持",
                    details: nil
                ))
                
            case "prepareModel":
                // ML Kit 模型下载为 iOS-only，macOS 上无需操作
                result(nil)
                
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
    
    private static func recognizeText(imagePath: String, result: @escaping FlutterResult) {
        guard let image = NSImage(contentsOfFile: imagePath),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            result(FlutterError(
                code: "INVALID_IMAGE",
                message: "无法加载图片: \(imagePath)",
                details: nil
            ))
            return
        }
        
        let request = VNRecognizeTextRequest { (request, error) in
            if let error = error {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "OCR_ERROR",
                        message: "文字识别失败: \(error.localizedDescription)",
                        details: nil
                    ))
                }
                return
            }
            
            guard let observations = (request as? VNRecognizeTextRequest)?.results,
                  !observations.isEmpty else {
                DispatchQueue.main.async {
                    result("")
                }
                return
            }
            
            var recognizedStrings: [String] = []
            for observation in observations {
                if let topCandidate = observation.topCandidates(1).first {
                    recognizedStrings.append(topCandidate.string)
                }
            }
            
            let fullText = recognizedStrings.joined(separator: "\n")
            
            DispatchQueue.main.async {
                result(fullText)
            }
        }
        
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "OCR_ERROR",
                        message: "执行识别失败: \(error.localizedDescription)",
                        details: nil
                    ))
                }
            }
        }
    }
}

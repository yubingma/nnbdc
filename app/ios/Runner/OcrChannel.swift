import Flutter
import UIKit
import Vision

/// 使用 Apple Vision 框架进行本地 OCR 文字识别
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
                
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
    
    private static func recognizeText(imagePath: String, result: @escaping FlutterResult) {
        guard let image = UIImage(contentsOfFile: imagePath),
              let cgImage = image.cgImage else {
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
            
            guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                // 关键修复：准确模式对孤立字符有时过于挑剔。如果没结果，尝试用快速模式回退。
                if request.recognitionLevel == .accurate {
                    let fastRequest = VNRecognizeTextRequest(completionHandler: request.completionHandler as! VNRequestCompletionHandler)
                    fastRequest.recognitionLevel = .fast
                    fastRequest.recognitionLanguages = request.recognitionLanguages
                    let fastHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    try? fastHandler.perform([fastRequest])
                    return
                }
                
                DispatchQueue.main.async {
                    result("")
                }
                return
            }
            
            // 提取所有识别到的文字
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
        
        // 配置识别参数
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = true
        
        // 执行识别
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

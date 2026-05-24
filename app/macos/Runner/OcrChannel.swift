import Cocoa
import FlutterMacOS
import Vision

/// 使用 Apple Vision 框架进行本地 OCR 文字识别（macOS 版本）
/// 手写识别：将笔画渲染为位图后使用 Vision 文字识别
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
                guard let args = call.arguments as? [String: Any],
                      let strokes = args["strokes"] as? [[[String: Any]]] else {
                    result(FlutterError(
                        code: "INVALID_ARGUMENTS",
                        message: "Missing strokes parameter",
                        details: nil
                    ))
                    return
                }
                recognizeHandwriting(strokesData: strokes, result: result)
                
            case "prepareModel":
                result(nil)
                
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
    
    // MARK: - Text Recognition (from image file)
    
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
        
        performVisionRecognition(cgImage: cgImage, result: result)
    }
    
    // MARK: - Handwriting Recognition (from digital ink strokes)
    
    private static func recognizeHandwriting(strokesData: [[[String: Any]]], result: @escaping FlutterResult) {
        guard let cgImage = renderStrokesToImage(strokesData: strokesData) else {
            result(FlutterError(
                code: "RENDER_ERROR",
                message: "无法渲染笔画图像",
                details: nil
            ))
            return
        }
        
        performVisionRecognition(cgImage: cgImage, result: result)
    }
    
    private static func renderStrokesToImage(strokesData: [[[String: Any]]]) -> CGImage? {
        var allPoints: [(CGFloat, CGFloat)] = []
        for stroke in strokesData {
            for point in stroke {
                if let x = (point["x"] as? NSNumber)?.doubleValue,
                   let y = (point["y"] as? NSNumber)?.doubleValue {
                    allPoints.append((CGFloat(x), CGFloat(y)))
                }
            }
        }
        
        guard !allPoints.isEmpty else { return nil }
        
        let minX = allPoints.map { $0.0 }.min()!
        let minY = allPoints.map { $0.1 }.min()!
        let maxX = allPoints.map { $0.0 }.max()!
        let maxY = allPoints.map { $0.1 }.max()!
        let strokeWidth = maxX - minX
        let strokeHeight = maxY - minY
        
        guard strokeWidth > 0 && strokeHeight > 0 else { return nil }
        
        let canvasWidth: CGFloat = 512
        let canvasHeight: CGFloat = 256
        let padding: CGFloat = 24
        
        let availableW = canvasWidth - padding * 2
        let availableH = canvasHeight - padding * 2
        let scale = min(availableW / strokeWidth, availableH / strokeHeight) * 0.85
        let offsetX = (canvasWidth - strokeWidth * scale) / 2 - minX * scale
        let offsetY = (canvasHeight - strokeHeight * scale) / 2 - minY * scale
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(canvasWidth),
            height: Int(canvasHeight),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        
        context.setStrokeColor(CGColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1))
        context.setLineWidth(5.0)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        // CoreGraphics Y 轴向上，Flutter Y 轴向下，需要翻转
        for stroke in strokesData {
            guard stroke.count >= 1 else { continue }
            context.beginPath()
            var first = true
            for point in stroke {
                guard let x = (point["x"] as? NSNumber)?.doubleValue,
                      let y = (point["y"] as? NSNumber)?.doubleValue else { continue }
                let px = CGFloat(x) * scale + offsetX
                let py = canvasHeight - (CGFloat(y) * scale + offsetY)
                if first {
                    context.move(to: CGPoint(x: px, y: py))
                    first = false
                } else {
                    context.addLine(to: CGPoint(x: px, y: py))
                }
            }
            context.strokePath()
        }
        
        return context.makeImage()
    }
    
    // MARK: - Vision Recognition
    
    private static func performVisionRecognition(cgImage: CGImage, result: @escaping FlutterResult) {
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

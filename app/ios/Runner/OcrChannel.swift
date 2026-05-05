import Flutter
import UIKit
import Vision
import MLKit
import MLKitDigitalInkRecognition

/// 使用 Apple Vision 框架与 Google ML Kit 进行本地 OCR 与手写识别
class OcrChannel {
    
    // 必须持有强引用，否则异步识别回调返回前对象会被 ARC 释放
    private static var recognizer: DigitalInkRecognizer?
    private static var currentModel: DigitalInkRecognitionModel?
    
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
            
            guard let textRequest = request as? VNRecognizeTextRequest,
                  let observations = textRequest.results, !observations.isEmpty else {
                
                // 关键修复：如果准确模式没搜到结果，尝试快速模式
                if let textReq = request as? VNRecognizeTextRequest, textReq.recognitionLevel == .accurate {
                    let fastRequest = VNRecognizeTextRequest(completionHandler: textReq.completionHandler)
                    fastRequest.recognitionLevel = .fast
                    fastRequest.recognitionLanguages = textReq.recognitionLanguages
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

    private static func recognizeHandwriting(strokesData: [[[String: Any]]], result: @escaping FlutterResult) {
        var recognitionStrokes: [Stroke] = []
        for strokeData in strokesData {
            var points: [StrokePoint] = []
            for pointData in strokeData {
                let x = (pointData["x"] as? NSNumber)?.floatValue ?? 0.0
                let y = (pointData["y"] as? NSNumber)?.floatValue ?? 0.0
                let t = (pointData["t"] as? NSNumber)?.intValue ?? 0
                points.append(StrokePoint(x: x, y: y, t: t)) 
            }
            recognitionStrokes.append(Stroke(points: points))
        }
        let ink = Ink(strokes: recognitionStrokes)
        
        let languageTag = "en-US"
        guard let modelIdentifier = DigitalInkRecognitionModelIdentifier(forLanguageTag: languageTag) else {
            result(FlutterError(code: "MODEL_ERROR", message: "无法识别语言模型: \(languageTag)", details: nil))
            return
        }
        
        let model = DigitalInkRecognitionModel(modelIdentifier: modelIdentifier)
        let modelManager = ModelManager.modelManager()
        
        if modelManager.isModelDownloaded(model) {
            performHandwritingRecognition(ink: ink, model: model, result: result)
        } else {
            // 开始下载模型，并监听下载完成通知
            NotificationCenter.default.addObserver(
                forName: .mlkitModelDownloadDidSucceed,
                object: nil,
                queue: nil
            ) { notification in
                // 模型下载成功后，执行识别
                performHandwritingRecognition(ink: ink, model: model, result: result)
            }
            
            NotificationCenter.default.addObserver(
                forName: .mlkitModelDownloadDidFail,
                object: nil,
                queue: nil
            ) { notification in
                result(FlutterError(code: "MODEL_DOWNLOAD_ERROR", message: "模型下载失败", details: nil))
            }
            
            modelManager.download(model, conditions: ModelDownloadConditions())
        }
    }
    
    private static func performHandwritingRecognition(ink: Ink, model: DigitalInkRecognitionModel, result: @escaping FlutterResult) {
        // 缓存 model 和 recognizer，防止被 ARC 释放
        if currentModel != model {
            let options = DigitalInkRecognizerOptions(model: model)
            recognizer = DigitalInkRecognizer.digitalInkRecognizer(options: options)
            currentModel = model
        }
        
        guard let activeRecognizer = recognizer else {
            result(FlutterError(code: "RECOGNIZER_ERROR", message: "识别器初始化失败", details: nil))
            return
        }
        
        activeRecognizer.recognize(ink: ink) { recognitionResult, error in
            if let error = error {
                result(FlutterError(code: "RECOGNITION_ERROR", message: "识别失败: \(error.localizedDescription)", details: nil))
                return
            }
            
            if let topCandidate = recognitionResult?.candidates.first {
                result(topCandidate.text)
            } else {
                result("")
            }
        }
    }
}


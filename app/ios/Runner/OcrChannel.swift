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
                let language = args["language"] as? String ?? "en-US"
                let areaWidth = (args["writingAreaWidth"] as? NSNumber)?.doubleValue
                let areaHeight = (args["writingAreaHeight"] as? NSNumber)?.doubleValue
                let preContext = args["preContext"] as? String ?? ""
                recognizeHandwriting(
                    strokesData: strokes, language: language,
                    writingAreaWidth: areaWidth, writingAreaHeight: areaHeight,
                    preContext: preContext,
                    result: result)
                
            case "prepareModel":
                let language = (call.arguments as? [String: Any])?["language"] as? String ?? "en-US"
                prepareModel(language: language, result: result)
                
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

    private static func recognizeHandwriting(strokesData: [[[String: Any]]], language: String, writingAreaWidth: Double?, writingAreaHeight: Double?, preContext: String, result: @escaping FlutterResult) {
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
        
        // 提供手写区尺寸与前置文本上下文，帮助 ML Kit 正确切分多字连写（避免多个汉字被合成一个字）。
        // 注意：preContext 必须非 nil。ML Kit 头文件声明它是 nullable，但内部按 C 字符串（UTF8String）
        // 构造 std::string，传 nil 会在 -[MLKDigitalInkRecognizer recognitionForInk:context:error:]
        // 里 strlen(NULL) 崩溃（UCrash 已抓到该栈）。
        var context: DigitalInkRecognitionContext? = nil
        if let width = writingAreaWidth, let height = writingAreaHeight, width > 0, height > 0 {
            let area = WritingArea(width: Float(width), height: Float(height))
            context = DigitalInkRecognitionContext(preContext: preContext, writingArea: area)
        }
        
        let languageTag = language
        guard let modelIdentifier = DigitalInkRecognitionModelIdentifier(forLanguageTag: languageTag) else {
            result(FlutterError(code: "MODEL_ERROR", message: "无法识别语言模型: \(languageTag)", details: nil))
            return
        }
        
        let model = DigitalInkRecognitionModel(modelIdentifier: modelIdentifier)
        let modelManager = ModelManager.modelManager()
        
        if modelManager.isModelDownloaded(model) {
            performHandwritingRecognition(ink: ink, model: model, context: context, result: result)
        } else {
            // 模型还没下载：先触发下载，等"就是这个模型"下载完成后再识别。
            // 不能像以前那样用 object: nil 注册 observer 且用完不移除：
            // 下载通知是全局广播（任意模型，比如英文模型），且观察者只增不减——
            // 一次下载成功会让此前所有挂起的识别在同一时刻一起回调，表现为
            // "点提交后没反应，过一会儿一堆结果/提示一起涌出来"。
            waitForModelDownload(model: model, onReady: {
                performHandwritingRecognition(ink: ink, model: model, context: context, result: result)
            }, onFailure: { error in
                result(FlutterError(
                    code: "MODEL_DOWNLOAD_ERROR",
                    message: "模型下载失败: \(error?.localizedDescription ?? "未知错误")",
                    details: nil
                ))
            })
        }
    }

    /// 等待 [model] 这一个模型下载完成后再回调 [onReady]；下载失败则回调 [onFailure]。
    ///
    /// 下载通知里带着"是哪个模型下载好了"（见 MLKModelDownloadNotifications.h），因此必须
    /// 过滤出自己等的模型，并在回调后立刻移除观察者。否则任意模型下载完成都会唤醒等待方，
    /// 而且每等待一次就永久多一个观察者，历次挂起的识别会在同一次通知里成批完成。
    private static func waitForModelDownload(
        model: DigitalInkRecognitionModel,
        onReady: @escaping () -> Void,
        onFailure: @escaping (Error?) -> Void
    ) {
        var successObserver: NSObjectProtocol?
        var failureObserver: NSObjectProtocol?
        func removeObservers() {
            if let observer = successObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = failureObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            successObserver = nil
            failureObserver = nil
        }
        func isTargetModel(_ notification: Notification) -> Bool {
            guard let notified = notification.userInfo?[ModelDownloadUserInfoKey.remoteModel.rawValue]
                as? RemoteModel else {
                return false
            }
            if let notifiedInkModel = notified as? DigitalInkRecognitionModel {
                return notifiedInkModel.modelIdentifier.languageTag == model.modelIdentifier.languageTag
            }
            return notified.name == model.name
        }

        successObserver = NotificationCenter.default.addObserver(
            forName: .mlkitModelDownloadDidSucceed,
            object: nil,
            queue: nil
        ) { notification in
            guard isTargetModel(notification) else { return }
            removeObservers()
            onReady()
        }

        failureObserver = NotificationCenter.default.addObserver(
            forName: .mlkitModelDownloadDidFail,
            object: nil,
            queue: nil
        ) { notification in
            guard isTargetModel(notification) else { return }
            removeObservers()
            onFailure(notification.userInfo?[ModelDownloadUserInfoKey.error.rawValue] as? Error)
        }

        ModelManager.modelManager().download(model, conditions: ModelDownloadConditions())
    }

    private static func prepareModel(language: String, result: @escaping FlutterResult) {
        let languageTag = language
        guard let modelIdentifier = DigitalInkRecognitionModelIdentifier(forLanguageTag: languageTag) else {
            result(FlutterError(code: "MODEL_ERROR", message: "无法识别语言模型: \(languageTag)", details: nil))
            return
        }
        
        let model = DigitalInkRecognitionModel(modelIdentifier: modelIdentifier)
        let modelManager = ModelManager.modelManager()
        
        if modelManager.isModelDownloaded(model) {
            print("OcrChannel: \(languageTag) handwriting model already downloaded")
            warmupRecognizer(model: model)
            result(nil)
        } else {
            print("OcrChannel: \(languageTag) handwriting model is downloading...")
            waitForModelDownload(model: model, onReady: {
                print("OcrChannel: \(languageTag) handwriting model downloaded successfully")
                warmupRecognizer(model: model)
            }, onFailure: { error in
                print("OcrChannel: \(languageTag) handwriting model download failed: \(error?.localizedDescription ?? "未知错误")")
            })
            result(nil)
        }
    }

    private static func warmupRecognizer(model: DigitalInkRecognitionModel) {
        print("OcrChannel: Warming up DigitalInkRecognizer...")
        if currentModel != model || recognizer == nil {
            let options = DigitalInkRecognizerOptions(model: model)
            recognizer = DigitalInkRecognizer.digitalInkRecognizer(options: options)
            currentModel = model
        }
        
        guard let activeRecognizer = recognizer else {
            print("OcrChannel: Warmup failed, recognizer is nil")
            return
        }
        
        // 构造一个超级简单的 Dummy 轨迹来触发模型加载和首次推理
        let points = [
            StrokePoint(x: 0, y: 0, t: 0),
            StrokePoint(x: 1, y: 1, t: 10)
        ]
        let stroke = Stroke(points: points)
        let dummyInk = Ink(strokes: [stroke])
        
        let startTime = CACurrentMediaTime()
        activeRecognizer.recognize(ink: dummyInk) { _, error in
            let duration = (CACurrentMediaTime() - startTime) * 1000
            if let error = error {
                print("OcrChannel: Warmup recognition finished with error: \(error.localizedDescription) (took \(String(format: "%.1f", duration))ms)")
            } else {
                print("OcrChannel: Warmup recognition completed successfully (took \(String(format: "%.1f", duration))ms)")
            }
        }
    }

    
    private static func performHandwritingRecognition(ink: Ink, model: DigitalInkRecognitionModel, context: DigitalInkRecognitionContext?, result: @escaping FlutterResult) {
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
        
        let onRecognitionDone: (DigitalInkRecognitionResult?, Error?) -> Void = { recognitionResult, error in
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
        
        if let ctx = context {
            activeRecognizer.recognize(ink: ink, context: ctx, completion: onRecognitionDone)
        } else {
            activeRecognizer.recognize(ink: ink, completion: onRecognitionDone)
        }
    }
}


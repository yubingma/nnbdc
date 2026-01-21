import Foundation
import FlutterMacOS

class AiInferenceChannel: NSObject, FlutterPlugin {
    private static let channelName = "com.nnbdc.ai_inference"
    private var modelPath: String?
    private var isModelLoaded = false
    private var llamaBridge: LlamaCppBridge?
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger
        )
        let instance = AiInferenceChannel()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "loadModel":
            handleLoadModel(call, result: result)
        case "inference":
            handleInference(call, result: result)
        case "unloadModel":
            handleUnloadModel(result: result)
        case "checkCapability":
            handleCheckCapability(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func handleLoadModel(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let modelPath = args["modelPath"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "modelPath is required",
                details: nil
            ))
            return
        }
        
        // 检查文件是否存在
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: modelPath) else {
            result(FlutterError(
                code: "FILE_NOT_FOUND",
                message: "Model file not found at: \(modelPath)",
                details: nil
            ))
            return
        }
        
        // 加载 llama.cpp 模型
        let bridge = LlamaCppBridge()
        let success = bridge.loadModel(path: modelPath)
        
        if success {
            self.modelPath = modelPath
            self.isModelLoaded = true
            self.llamaBridge = bridge
            
            NSLog("[AiInferenceChannel] llama.cpp 模型加载成功: \(modelPath)")
            result([
                "success": true,
                "modelPath": modelPath,
                "message": "llama.cpp model loaded successfully"
            ])
        } else {
            result(FlutterError(
                code: "LOAD_FAILED",
                message: "Failed to load llama.cpp model",
                details: nil
            ))
        }
    }
    
    private func handleInference(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard isModelLoaded else {
            result(FlutterError(
                code: "MODEL_NOT_LOADED",
                message: "Model not loaded. Call loadModel first.",
                details: nil
            ))
            return
        }
        
        guard let args = call.arguments as? [String: Any],
              let prompt = args["prompt"] as? String else {
            result(FlutterError(
                code: "INVALID_ARGS",
                message: "prompt is required",
                details: nil
            ))
            return
        }
        
        guard let bridge = llamaBridge else {
            result(FlutterError(
                code: "BRIDGE_NOT_READY",
                message: "llama.cpp bridge not initialized",
                details: nil
            ))
            return
        }
        
        let maxTokens = args["maxTokens"] as? Int ?? 512
        let temperature = args["temperature"] as? Double ?? 0.7
        
        NSLog("[AiInferenceChannel] 开始 llama.cpp 推理, prompt 长度: \(prompt.count)")
        
        // 在后台线程执行推理
        DispatchQueue.global(qos: .userInitiated).async {
            let startTime = Date()
            
            // 调用 llama.cpp 推理 - 添加崩溃保护
            var response: String?
            do {
                NSLog("[AiInferenceChannel] 调用 LlamaCppBridge.inference")
                response = bridge.inference(
                    prompt: prompt,
                    maxTokens: maxTokens,
                    temperature: temperature
                )
                NSLog("[AiInferenceChannel] LlamaCppBridge.inference 返回")
            } catch {
                NSLog("[AiInferenceChannel] ❌ 推理过程异常: \(error)")
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "INFERENCE_EXCEPTION",
                        message: "Inference crashed: \(error)",
                        details: nil
                    ))
                }
                return
            }
            
            guard let response = response else {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "INFERENCE_FAILED",
                        message: "llama.cpp inference failed",
                        details: nil
                    ))
                }
                return
            }
            
            let inferenceTime = Int(Date().timeIntervalSince(startTime) * 1000)
            let tokenCount = response.split(separator: " ").count
            
            NSLog("[AiInferenceChannel] llama.cpp 推理完成: \(tokenCount) tokens, \(inferenceTime)ms")
            
            DispatchQueue.main.async {
                result([
                    "success": true,
                    "text": response,
                    "tokensGenerated": tokenCount,
                    "inferenceTimeMs": inferenceTime
                ])
            }
        }
    }
    
    private func handleUnloadModel(result: @escaping FlutterResult) {
        llamaBridge?.unloadModel()
        llamaBridge = nil
        self.modelPath = nil
        self.isModelLoaded = false
        
        NSLog("[AiInferenceChannel] llama.cpp 模型已卸载")
        result(["success": true])
    }
    
    private func handleCheckCapability(result: @escaping FlutterResult) {
        // 检查系统能力
        let processInfo = ProcessInfo.processInfo
        let physicalMemory = processInfo.physicalMemory
        let memoryGB = Double(physicalMemory) / 1024.0 / 1024.0 / 1024.0
        
        // macOS 上一般都可以跑小模型
        let capability: String
        if memoryGB >= 16 {
            capability = "full"
        } else if memoryGB >= 8 {
            capability = "light"
        } else {
            capability = "none"
        }
        
        result([
            "capability": capability,
            "memoryGB": memoryGB,
            "platform": "macos"
        ])
    }
}

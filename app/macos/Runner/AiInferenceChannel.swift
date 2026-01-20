import Foundation
import FlutterMacOS

class AiInferenceChannel: NSObject, FlutterPlugin {
    private static let channelName = "com.nnbdc.ai_inference"
    private var modelPath: String?
    private var isModelLoaded = false
    
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
        
        // TODO: 实际加载 llama.cpp 模型
        // 目前先占位实现
        self.modelPath = modelPath
        self.isModelLoaded = true
        
        NSLog("[AiInferenceChannel] Model loaded (placeholder): \(modelPath)")
        result([
            "success": true,
            "modelPath": modelPath,
            "message": "Model loaded successfully (placeholder implementation)"
        ])
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
        
        let maxTokens = args["maxTokens"] as? Int ?? 512
        let temperature = args["temperature"] as? Double ?? 0.7
        
        NSLog("[AiInferenceChannel] Running inference with prompt length: \(prompt.count)")
        
        // TODO: 实际调用 llama.cpp 推理
        // 目前返回占位响应
        DispatchQueue.global(qos: .userInitiated).async {
            // 模拟推理延迟
            Thread.sleep(forTimeInterval: 0.5)
            
            let mockResponse = """
            [EXPLANATION]
            这是一个测试响应（占位实现）。模型文件已加载，但 llama.cpp 推理引擎尚未完全集成。
            
            [MEMORY_TIP]
            请等待 llama.cpp 完全集成后，将获得真实的 AI 生成内容。
            
            [EXAMPLES]
            1. This is a placeholder example.
               这是一个占位示例。
            2. Real AI responses coming soon!
               真实的 AI 响应即将到来！
            """
            
            DispatchQueue.main.async {
                result([
                    "success": true,
                    "text": mockResponse,
                    "tokensGenerated": 50,
                    "inferenceTimeMs": 500
                ])
            }
        }
    }
    
    private func handleUnloadModel(result: @escaping FlutterResult) {
        // TODO: 实际卸载模型
        self.modelPath = nil
        self.isModelLoaded = false
        
        NSLog("[AiInferenceChannel] Model unloaded")
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

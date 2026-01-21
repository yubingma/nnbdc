import Foundation
import LlamaCpp

/// llama.cpp C API 的 Swift 桥接
/// 这是一个轻量级的实现，直接调用 llama.cpp 的 C 接口
class LlamaCppBridge {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var contextParams: llama_context_params
    
    init() {
        // 初始化上下文参数
        contextParams = llama_context_default_params()
        contextParams.n_ctx = 2048  // 上下文长度
        contextParams.n_batch = 512  // batch size
        contextParams.n_threads = 4  // 线程数
        contextParams.n_threads_batch = 4
    }
    
    /// 加载模型
    func loadModel(path: String) -> Bool {
        NSLog("[LlamaCppBridge] 开始加载模型: \(path)")
        
        // 初始化 llama.cpp 后端
        llama_backend_init()
        
        // 设置模型参数
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 0  // Metal 加速（macOS）
        modelParams.use_mmap = true
        modelParams.use_mlock = false
        
        // 加载模型
        guard let loadedModel = llama_load_model_from_file(path, modelParams) else {
            NSLog("[LlamaCppBridge] ❌ 模型加载失败")
            return false
        }
        
        self.model = loadedModel
        
        // 创建上下文
        guard let createdContext = llama_new_context_with_model(loadedModel, contextParams) else {
            NSLog("[LlamaCppBridge] ❌ 上下文创建失败")
            llama_model_free(loadedModel)
            self.model = nil
            return false
        }
        
        self.context = createdContext
        
        NSLog("[LlamaCppBridge] ✅ 模型加载成功")
        return true
    }
    
    /// 执行推理
    func inference(prompt: String, maxTokens: Int, temperature: Double) -> String? {
        guard let model = model, let context = context else {
            NSLog("[LlamaCppBridge] ❌ 模型或上下文未初始化")
            return nil
        }
        
        NSLog("[LlamaCppBridge] 开始推理，prompt 长度: \(prompt.count), maxTokens: \(maxTokens)")
        
        // 1. Tokenize 输入
        let promptCString = prompt.cString(using: .utf8)!
        let nPromptTokens = -llama_tokenize(model, promptCString, Int32(promptCString.count), nil, 0, true, false)
        
        var tokens = [llama_token](repeating: 0, count: Int(nPromptTokens))
        let actualTokens = llama_tokenize(model, promptCString, Int32(promptCString.count), &tokens, Int32(nPromptTokens), true, false)
        
        guard actualTokens == nPromptTokens else {
            NSLog("[LlamaCppBridge] ❌ Tokenization 失败")
            return nil
        }
        
        NSLog("[LlamaCppBridge] Tokenized: \(nPromptTokens) tokens")
        
        // 2. 准备批处理 - 使用简化的单token batch
        var batch = llama_batch_get_one(&tokens, Int32(tokens.count))
        
        // 3. 解码输入 tokens
        if llama_decode(context, batch) != 0 {
            NSLog("[LlamaCppBridge] ❌ llama_decode 失败")
            return nil
        }
        
        // 4. 生成输出 tokens
        var outputTokens = [llama_token]()
        var output = ""
        
        for _ in 0..<maxTokens {
            // 获取 logits
            let logits = llama_get_logits_ith(context, batch.n_tokens - 1)
            let nVocab = llama_vocab_n_tokens(llama_model_get_vocab(model))
            
            // 简化采样：使用 greedy sampling
            var maxLogit: Float = -Float.infinity
            var newToken: llama_token = 0
            for i in 0..<nVocab {
                if logits![Int(i)] > maxLogit {
                    maxLogit = logits![Int(i)]
                    newToken = i
                }
            }
            
            // 检查是否结束
            if newToken == llama_token_eos(model) {
                NSLog("[LlamaCppBridge] 遇到 EOS token，结束生成")
                break
            }
            
            outputTokens.append(newToken)
            
            // Detokenize 当前 token
            var buffer = [CChar](repeating: 0, count: 256)
            let n = llama_token_to_piece(model, newToken, &buffer, Int32(buffer.count), 0, false)
            if n > 0 {
                let piece = String(cString: buffer)
                output += piece
            }
            
            // 准备下一次解码
            var singleToken = newToken
            batch = llama_batch_get_one(&singleToken, 1)
            
            if llama_decode(context, batch) != 0 {
                NSLog("[LlamaCppBridge] ❌ 解码生成的 token 失败")
                break
            }
        }
        
        NSLog("[LlamaCppBridge] ✅ 推理完成，生成了 \(outputTokens.count) tokens")
        NSLog("[LlamaCppBridge] 输出内容: \(output.prefix(200))...")
        
        return output
    }
    
    /// 卸载模型
    func unloadModel() {
        NSLog("[LlamaCppBridge] 开始卸载模型")
        
        if let ctx = context {
            llama_free(ctx)
            context = nil
        }
        
        if let mdl = model {
            llama_model_free(mdl)
            model = nil
        }
        
        llama_backend_free()
        
        NSLog("[LlamaCppBridge] ✅ 模型卸载完成")
    }
    
    deinit {
        unloadModel()
    }
}

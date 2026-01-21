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
        guard let loadedModel = llama_model_load_from_file(path, modelParams) else {
            NSLog("[LlamaCppBridge] ❌ 模型加载失败")
            return false
        }
        
        self.model = loadedModel
        
        // 创建上下文
        guard let createdContext = llama_init_from_model(loadedModel, contextParams) else {
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
        
        // 防御性检查
        guard maxTokens > 0 && maxTokens <= 2048 else {
            NSLog("[LlamaCppBridge] ❌ maxTokens 超出范围: \(maxTokens)")
            return nil
        }
        
        guard !prompt.isEmpty && prompt.count <= 10000 else {
            NSLog("[LlamaCppBridge] ❌ prompt 长度异常: \(prompt.count)")
            return nil
        }
        
        // 获取 vocab
        let vocab = llama_model_get_vocab(model)
        
        // 1. Tokenize 输入
        guard let promptCString = prompt.cString(using: .utf8) else {
            NSLog("[LlamaCppBridge] ❌ 无法转换 prompt 为 C 字符串")
            return nil
        }
        
        NSLog("[LlamaCppBridge] Prompt C 字符串长度: \(promptCString.count)")
        
        // 第一次调用获取需要的 token 数量
        let nPromptTokens = -llama_tokenize(
            vocab,
            promptCString,
            Int32(promptCString.count - 1),  // 不包含 null terminator
            nil,
            0,
            true,   // add_special: true
            false   // parse_special: false
        )
        
        guard nPromptTokens > 0 && nPromptTokens < 2048 else {
            NSLog("[LlamaCppBridge] ❌ Token 数量异常: \(nPromptTokens)")
            return nil
        }
        
        NSLog("[LlamaCppBridge] 预计需要 \(nPromptTokens) tokens")
        
        var tokens = [llama_token](repeating: 0, count: Int(nPromptTokens))
        
        // 第二次调用实际 tokenize
        let actualTokens = llama_tokenize(
            vocab,
            promptCString,
            Int32(promptCString.count - 1),
            &tokens,
            Int32(nPromptTokens),
            true,
            false
        )
        
        guard actualTokens == nPromptTokens else {
            NSLog("[LlamaCppBridge] ❌ Tokenization 失败，期望: \(nPromptTokens), 实际: \(actualTokens)")
            return nil
        }
        
        NSLog("[LlamaCppBridge] Tokenized: \(nPromptTokens) tokens")
        
        // 2. 准备批处理 - 使用简化的单token batch
        var batch = llama_batch_get_one(&tokens, Int32(tokens.count))
        
        NSLog("[LlamaCppBridge] Batch 准备完成, n_tokens: \(batch.n_tokens)")
        
        // 3. 解码输入 tokens
        let decodeResult = llama_decode(context, batch)
        if decodeResult != 0 {
            NSLog("[LlamaCppBridge] ❌ llama_decode 失败，错误码: \(decodeResult)")
            return nil
        }
        
        NSLog("[LlamaCppBridge] 输入 tokens 解码成功")
        
        // 4. 创建 sampler chain (temperature + repetition penalty + greedy/dist)
        var samplerParams = llama_sampler_chain_default_params()
        samplerParams.no_perf = false
        
        let sampler = llama_sampler_chain_init(samplerParams)
        llama_sampler_chain_add(sampler, llama_sampler_init_min_p(0.05, 1))  // min-p sampling
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(Float(temperature)))  // temperature
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32(time(nil))))  // distribution sampling
        
        defer {
            llama_sampler_free(sampler)
        }
        
        // 5. 生成输出 tokens
        var outputTokens = [llama_token]()
        var output = ""
        var lastTokens = [llama_token]()  // 用于检测重复
        let repeatCheckWindow = 5  // 重复检测窗口大小
        
        for i in 0..<maxTokens {
            // 使用 llama.cpp 的 sampler 进行采样
            let newToken = llama_sampler_sample(sampler, context, -1)
            
            // 检查是否结束
            let eosToken = llama_vocab_eos(llama_model_get_vocab(model))
            if newToken == eosToken {
                NSLog("[LlamaCppBridge] 遇到 EOS token，结束生成")
                break
            }
            
            // 检查是否是特殊 token（比如 <|im_end|>）
            // Qwen 模型的 im_end token 通常是 151645
            if newToken == 151645 || newToken == 151643 || newToken == 151644 {
                NSLog("[LlamaCppBridge] 遇到特殊结束 token: \(newToken)，结束生成")
                break
            }
            
            outputTokens.append(newToken)
            lastTokens.append(newToken)
            
            // 通知 sampler 已接受此 token
            llama_sampler_accept(sampler, newToken)
            
            // 检测短期重复（每 3 次检查一次）
            if lastTokens.count >= repeatCheckWindow * 2 && i % 3 == 0 {
                let recent = Array(lastTokens.suffix(repeatCheckWindow))
                let before = Array(lastTokens.dropLast(repeatCheckWindow).suffix(repeatCheckWindow))
                if recent == before {
                    NSLog("[LlamaCppBridge] ⚠️ 检测到 \(repeatCheckWindow) token 重复序列，提前结束")
                    break
                }
            }
            
            // Detokenize 当前 token
            var buffer = [CChar](repeating: 0, count: 256)
            let n = llama_token_to_piece(vocab, newToken, &buffer, Int32(buffer.count), 0, false)
            if n > 0 {
                // 使用更安全的字符串转换
                if let piece = String(data: Data(bytes: buffer, count: Int(n)), encoding: .utf8) {
                    output += piece
                } else {
                    NSLog("[LlamaCppBridge] ⚠️ 无法解码 token \(newToken)")
                }
            }
            
            // 准备下一次解码
            var singleToken = newToken
            batch = llama_batch_get_one(&singleToken, 1)
            
            let nextDecodeResult = llama_decode(context, batch)
            if nextDecodeResult != 0 {
                NSLog("[LlamaCppBridge] ❌ 解码生成的 token 失败，错误码: \(nextDecodeResult), 位置: \(i)")
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

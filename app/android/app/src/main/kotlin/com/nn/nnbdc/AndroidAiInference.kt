package com.nn.nnbdc

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.File

private const val TAG = "AndroidAiInference"

class AndroidAiInference(private val context: Context) {
    private var methodChannel: MethodChannel? = null
    
    // AI模型相关变量
    private var isModelLoaded = false
    private var modelPath: String? = null
    private var capabilityLevel: String = "none"
    private var deviceMemoryGB: Double = 0.0
    
    // 协程作用域
    private val aiScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // Native methods from ai-chat (llama.cpp)
    private external fun init(nativeLibDir: String)
    private external fun load(modelPath: String): Int
    private external fun prepare(): Int
    private external fun systemInfo(): String
    private external fun processSystemPrompt(prompt: String): Int
    private external fun processUserPrompt(prompt: String, nPredict: Int): Int
    private external fun processRawPrompt(prompt: String, nPredict: Int): Int
    private external fun generateNextToken(): String?
    private external fun runCpuBenchmark(): Double
    private external fun unload()
    private external fun shutdown()

    init {
        try {
            System.loadLibrary("ai-chat")
            val nativeLibDir = context.applicationInfo.nativeLibraryDir
            init(nativeLibDir)
            Log.i(TAG, "Native library 'ai-chat' loaded and initialized. System info: ${systemInfo()}")
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "Failed to load native library 'ai-chat'", e)
        }
    }

    fun initChannel(flutterEngine: FlutterEngine) {
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.nnbdc.ai_inference"
        )
        
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkCapability" -> {
                    checkCapability(result)
                }
                "loadModel" -> {
                    val path = call.argument<String>("modelPath")
                    if (path != null) {
                        loadModel(path, result)
                    } else {
                        result.error("INVALID_ARGS", "Missing modelPath argument", null)
                    }
                }
                "inference" -> {
                    val prompt = call.argument<String>("prompt")
                    val maxTokens = call.argument<Int>("maxTokens") ?: 2048
                    val temperature = call.argument<Double>("temperature") ?: 0.7
                    val stopTokens = call.argument<List<String>>("stop") ?: listOf("\u1010", "", "\u1011")
                    
                    if (prompt != null) {
                        runInference(prompt, maxTokens, temperature, stopTokens, result)
                    } else {
                        result.error("INVALID_ARGS", "Missing prompt argument", null)
                    }
                }
                "unloadModel" -> {
                    unloadModel(result)
                }
                "runCpuBenchmark" -> {
                    val score = runCpuBenchmark()
                    result.success(score)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun checkCapability(result: MethodChannel.Result) {
        try {
            // 1. 检查设备内存
            val memoryInfo = android.app.ActivityManager.MemoryInfo()
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
            activityManager.getMemoryInfo(memoryInfo)
            
            deviceMemoryGB = memoryInfo.totalMem.toDouble() / (1024 * 1024 * 1024)
            
            // 2. 检查 CPU 特性 (通过 llama.cpp 的 systemInfo)
            val sysInfo = try { systemInfo() } catch (e: Exception) { "" }
            val hasDotProd = sysInfo.contains("DOTPROD = 1") || sysInfo.contains("ARM_FMA = 1") // ARM_FMA 也是一个性能指标
            val hasNeon = sysInfo.contains("NEON = 1")
            
            // 3. 检查 CPU 核心数
            val cpuCores = Runtime.getRuntime().availableProcessors()
            
            // 4. 获取硬件 ID (用于识别老旧芯片)
            val hardware = android.os.Build.HARDWARE.lowercase()
            val isOldChip = hardware.contains("hi3670") || // Kirin 970
                           hardware.contains("hi3660") || // Kirin 960
                           hardware.contains("sdm6") ||    // Snapdragon 6xx
                           hardware.contains("msm8998")    // Snapdragon 835
            
            // 5. 综合评定能力等级
            capabilityLevel = when {
                // 如果内存很大且具备现代指令集，或者是高性能核心
                deviceMemoryGB >= 10.0 && hasDotProd && !isOldChip -> "full"
                
                // 如果内存足够且有基础 SIMD 支持
                deviceMemoryGB >= 4.0 && hasNeon && !isOldChip -> "light"
                
                // 内存极小，或者已知的老旧芯片（如麒麟 970）
                deviceMemoryGB < 4.0 || isOldChip -> "light" // 即使是老芯片，也允许尝试 light
                
                else -> "light"
            }
            
            // 特殊逻辑：如果是老旧芯片且内存小于 8G，强制建议 light
            if (isOldChip && deviceMemoryGB < 8.0) {
                capabilityLevel = "light"
            }

            Log.i(TAG, "Device capability info: Memory=${String.format("%.1f", deviceMemoryGB)}GB, cores=$cpuCores, hardware=$hardware, DotProd=$hasDotProd, Neon=$hasNeon")
            Log.i(TAG, "Final recommendation: $capabilityLevel")
            
            result.success(mapOf(
                "capability" to capabilityLevel,
                "memoryGB" to deviceMemoryGB,
                "cores" to cpuCores,
                "hardware" to hardware,
                "hasDotProd" to hasDotProd,
                "hasNeon" to hasNeon,
                "systemInfo" to sysInfo,
                "platform" to "Android"
            ))
        } catch (e: Exception) {
            Log.e(TAG, "Check capability failed", e)
            result.error("CHECK_FAILED", e.message, null)
        }
    }

    private fun loadModel(modelPath: String, result: MethodChannel.Result) {
        aiScope.launch {
            try {
                Log.i(TAG, "Loading model: $modelPath")
                
                // 验证模型文件是否存在
                val modelFile = File(modelPath)
                if (!modelFile.exists()) {
                    Log.e(TAG, "Model file not found: $modelPath")
                    withContext(Dispatchers.Main) {
                        result.success(mapOf("success" to false, "error" to "Model file not found"))
                    }
                    return@launch
                }

                // 实际调用 native 加载
                val loadResult = load(modelPath)
                if (loadResult != 0) {
                    Log.e(TAG, "Native load failed with code: $loadResult")
                    withContext(Dispatchers.Main) {
                        result.success(mapOf("success" to false, "error" to "Native load failed: $loadResult"))
                    }
                    return@launch
                }

                val prepareResult = prepare()
                if (prepareResult != 0) {
                    Log.e(TAG, "Native prepare failed with code: $prepareResult")
                    withContext(Dispatchers.Main) {
                        result.success(mapOf("success" to false, "error" to "Native prepare failed: $prepareResult"))
                    }
                    return@launch
                }
                
                this@AndroidAiInference.modelPath = modelPath
                isModelLoaded = true
                
                Log.i(TAG, "Model loaded successfully via llama.cpp")
                withContext(Dispatchers.Main) {
                    result.success(mapOf("success" to true))
                }
            } catch (e: Exception) {
                Log.e(TAG, "Model loading failed", e)
                withContext(Dispatchers.Main) {
                    result.success(mapOf("success" to false, "error" to e.message))
                }
            }
        }
    }

    private fun runInference(
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        stopTokens: List<String>,
        result: MethodChannel.Result
    ) {
        if (!isModelLoaded) {
            result.error("MODEL_NOT_LOADED", "Model not loaded", null)
            return
        }

        aiScope.launch {
            try {
                Log.d(TAG, "Running real inference with prompt length: ${prompt.length}")
                
                val startTime = System.currentTimeMillis()
                
                // 使用 processRawPrompt 直接处理完整的格式化 prompt (包含 system/user 标签)
                // 这样可以避免双重模板问题，并且原生层会强制重置 Context，防止 KV cache 冲突
                val processResult = processRawPrompt(prompt, maxTokens)
                if (processResult != 0) {
                    throw Exception("Native processUserPrompt failed: $processResult")
                }

                val fullResponse = StringBuilder()
                var tokensGenerated = 0

                while (true) {
                    val token = generateNextToken() ?: break
                    if (token.isNotEmpty()) {
                        fullResponse.append(token)
                        tokensGenerated++
                        
                        // 发送增量结果回 Flutter 侧以支持流式显示
                        withContext(Dispatchers.Main) {
                            methodChannel?.invokeMethod("onPartialResult", token)
                        }
                    }
                }

                val inferenceTimeMs = System.currentTimeMillis() - startTime
                Log.i(TAG, "Inference completed: $tokensGenerated tokens, ${inferenceTimeMs}ms")
                
                withContext(Dispatchers.Main) {
                    result.success(mapOf(
                        "success" to true,
                        "text" to fullResponse.toString(),
                        "tokensGenerated" to tokensGenerated,
                        "inferenceTimeMs" to inferenceTimeMs.toInt()
                    ))
                }
            } catch (e: Exception) {
                Log.e(TAG, "Inference failed", e)
                withContext(Dispatchers.Main) {
                    result.error("INFERENCE_FAILED", e.message, null)
                }
            }
        }
    }

    private fun unloadModel(result: MethodChannel.Result) {
        try {
            Log.i(TAG, "Unloading model")
            if (isModelLoaded) {
                unload()
            }
            isModelLoaded = false
            modelPath = null
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Unload model failed", e)
            result.error("UNLOAD_FAILED", e.message, null)
        }
    }

    fun cleanup() {
        if (isModelLoaded) {
            unload()
            shutdown()
        }
        aiScope.cancel()
        isModelLoaded = false
        modelPath = null
    }
}
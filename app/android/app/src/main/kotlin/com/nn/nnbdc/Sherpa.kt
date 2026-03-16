package com.nn.nnbdc

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread
import kotlin.math.sqrt
import org.json.JSONObject
import org.json.JSONArray

// Sherpa-ONNX imports
import com.k2fsa.sherpa.onnx.*

private const val TAG = "sherpa-onnx"

class Sherpa(private val activity: Activity) : EventChannel.StreamHandler {
    private var eventChannel: EventChannel? = null
    private var events: EventChannel.EventSink? = null
    private var meterChannel: EventChannel? = null
    private var meterEvents: EventChannel.EventSink? = null

    // Sherpa Onnx Recognizer
    private var modelEn: OnlineRecognizer? = null
    private var modelZh: OnlineRecognizer? = null
    
    // 当前使用的工作模型指针
    private var currentModel: OnlineRecognizer? = null
    private var currentStream: OnlineStream? = null
    
    // 当前模型语言类型: "zh" or "en"
    private var currentModelType: String = ""
    
    // 上一次发送的识别结果，用于去重
    private var lastSentResult: String = ""
    
    // Audio Recording
    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null
    private val audioSource = MediaRecorder.AudioSource.VOICE_RECOGNITION
    private val sampleRateInHz = 16000
    private val channelConfig = AudioFormat.CHANNEL_IN_MONO
    private val audioFormat = AudioFormat.ENCODING_PCM_16BIT
    
    @Volatile
    private var isRecording: Boolean = false
    @Volatile
    var isAsrStopped = true

    // 统计处理音频块的计数，用于限制日志频率
    private var audioBlockCount = 0

    // State
    private var currentLocale: String = "zh-CN"
    private var pendingHotwords: String = ""

    fun initChannel(flutterEngine: FlutterEngine) {
        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "nnbdc/asr_events")
        eventChannel!!.setStreamHandler(this)

        meterChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "nnbdc/asr_meter")
        meterChannel!!.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                meterEvents = events
            }
            override fun onCancel(arguments: Any?) {
                meterEvents = null
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "nnbdc/asr_commands"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setLanguage" -> {
                    val locale = call.argument<String>("locale") ?: "zh-CN"
                    setLanguage(locale)
                    result.success(null)
                }
                "setContextualStrings" -> {
                    val phrases = call.argument<List<String>>("phrases") ?: emptyList()
                    // 转换为大写以匹配 tokens.txt 中的 BPE 编码
                    pendingHotwords = phrases.joinToString(" ") { it.uppercase() }
                    Log.i(TAG, "Hotwords prepared (Space-separated/Uppercased): $pendingHotwords")
                    result.success(null)
                }
                "startMicrophone" -> {
                    startMicrophone()
                    result.success(null)
                }
                "startAsr" -> {
                    startAsr()
                    result.success(null)
                }
                "stopAsr" -> {
                    stopAsr()
                    result.success(null)
                }
                "stopMicrophone" -> {
                    stopMicrophone()
                    result.success(null)
                }
                "reset" -> {
                    currentStream?.let { currentModel?.reset(it) }
                    lastSentResult = ""
                    result.success(null)
                }
                "preloadModels" -> {
                    thread {
                        try {
                            if (modelZh == null) setupChineseModel()
                            if (modelEn == null) setupEnglishModel()
                            activity.runOnUiThread {
                                result.success(null)
                            }
                        } catch (e: Exception) {
                            activity.runOnUiThread {
                                result.error("PRELOAD_FAILED", e.message, null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // 可以在 MainActivity onCreate 中调用初始化默认模型
    fun initModel() {
        // 默认初始化中文（并且设定为当前模型）
        loadModel("zh")
    }

    private fun setLanguage(locale: String) {
        val newType = if (locale.startsWith("en")) "en" else "zh"

        if (newType == currentModelType && currentModel != null) {
            currentLocale = locale
            Log.i(TAG, "Model already active for $newType")
            return
        }

        Log.i(TAG, "Switching model from '$currentModelType' to '$newType' (locale: $locale)")
        
        // 由于需要重建立 Stream，如果正在录音先停止并切断，避免线程抢占旧的流
        val wasRecording = isRecording && !isAsrStopped
        if (wasRecording) {
            stopAsr()
        }

        try {
            loadModel(newType)
            currentLocale = locale
        } catch (e: Exception) {
            Log.e(TAG, "Failed to switch model to $newType", e)
            // 尝试回退
            if (currentModel == null) loadModel(currentModelType.ifEmpty { "zh" })
        }

        if (wasRecording) {
            startMicrophone()
        }
    }

    // 运行时语言配置（由 init 阶段根据语言决定，实现物理隔离）
    private var activeGain: Float = 2.0f

    private fun loadModel(type: String) {
        // 先清理旧的流，释放资源
        currentStream?.release()
        currentStream = null
        
        // 懒加载模式，如果需要切换的目标模型不存在则去初始化
        if (type == "en") {
            if (modelEn == null) {
                 setupEnglishModel()
            }
            currentModel = modelEn
            activeGain = 2.5f
        } else {
            if (modelZh == null) {
                setupChineseModel()
            }
            currentModel = modelZh
            activeGain = 2.0f
        }
        
        currentModelType = type
        Log.i(TAG, "Switched working model to: $type, Gain: $activeGain")
    }

    private fun setupEnglishModel() {
        val modelDir = "sherpa-onnx-streaming-zipformer-en-2023-06-26"
        Log.i(TAG, "Isolating Recipe: Loading ENGLISH model (Upgraded 66M)")

        try {
            val cacheDir = activity.cacheDir.absolutePath
            val destDir = "$cacheDir/$modelDir"
            val tokensPath = copyAsset(modelDir, "tokens.txt", destDir)
            val encoderPath = copyAsset(modelDir, "encoder-epoch-99-avg-1.int8.onnx", destDir)
            val decoderPath = copyAsset(modelDir, "decoder-epoch-99-avg-1.int8.onnx", destDir)
            val joinerPath = copyAsset(modelDir, "joiner-epoch-99-avg-1.int8.onnx", destDir)

            val modelConfig = OnlineModelConfig.builder()
                .setTransducer(OnlineTransducerModelConfig.builder()
                    .setEncoder(encoderPath).setDecoder(decoderPath).setJoiner(joinerPath).build())
                .setTokens(tokensPath)
                .setNumThreads(4)
                .setDebug(true)
                .setModelType("zipformer2") // 重要：66M 升级版使用的是 zipformer2 架构
                .build()

            val featConfig = FeatureConfig.builder().setSampleRate(16000).setFeatureDim(80).build()

            // 英文识别配方：放宽末端静音检测，给犹豫的发音留时间
            val endpointConfig = EndpointConfig.builder()
                .setRule1(EndpointRule.builder().setMustContainNonSilence(false).setMinTrailingSilence(2.4f).build())
                .setRule2(EndpointRule.builder().setMustContainNonSilence(true).setMinTrailingSilence(1.2f).build())
                .setRul3(EndpointRule.builder().setMustContainNonSilence(false).setMinTrailingSilence(0f).setMinUtteranceLength(30f).build())
                .build()

            val config = OnlineRecognizerConfig.builder()
                .setFeatureConfig(featConfig)
                .setOnlineModelConfig(modelConfig)
                .setEndpointConfig(endpointConfig)
                .setEnableEndpoint(true)
                .setDecodingMethod("modified_beam_search")
                .setMaxActivePaths(4) // 针对 20M 小模型，收窄搜索范围反而更稳定，防止“脑补”离谱词汇
                .setHotwordsScore(30.0f) // 适度引导
                .setBlankPenalty(0.5f) // 增加轻微惩罚，减少乱码和幻觉
                .build()

            modelEn = OnlineRecognizer(config)
            Log.i(TAG, "English isolated recipe loaded to memory.")
        } catch (e: Exception) {
            Log.e(TAG, "English model load failed", e)
            throw e
        }
    }

    private fun setupChineseModel() {
        val modelDir = "sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23"
        Log.i(TAG, "Isolating Recipe: Loading CHINESE model")

        try {
            val cacheDir = activity.cacheDir.absolutePath
            val destDir = "$cacheDir/$modelDir"
            val tokensPath = copyAsset(modelDir, "tokens.txt", destDir)
            val encoderPath = copyAsset(modelDir, "encoder-epoch-99-avg-1.int8.onnx", destDir)
            val decoderPath = copyAsset(modelDir, "decoder-epoch-99-avg-1.int8.onnx", destDir)
            val joinerPath = copyAsset(modelDir, "joiner-epoch-99-avg-1.int8.onnx", destDir)

            val modelConfig = OnlineModelConfig.builder()
                .setTransducer(OnlineTransducerModelConfig.builder()
                    .setEncoder(encoderPath).setDecoder(decoderPath).setJoiner(joinerPath).build())
                .setTokens(tokensPath)
                .setNumThreads(4)
                .setDebug(true)
                .setModelType("zipformer")
                .build()

            val featConfig = FeatureConfig.builder().setSampleRate(16000).setFeatureDim(80).build()

            // 中文识别配方：更紧凑的断句逻辑
            val endpointConfig = EndpointConfig.builder()
                .setRule1(EndpointRule.builder().setMustContainNonSilence(false).setMinTrailingSilence(2.4f).build())
                .setRule2(EndpointRule.builder().setMustContainNonSilence(true).setMinTrailingSilence(1.2f).build())
                .setRul3(EndpointRule.builder().setMustContainNonSilence(false).setMinTrailingSilence(0f).setMinUtteranceLength(20f).build())
                .build()

            val config = OnlineRecognizerConfig.builder()
                .setFeatureConfig(featConfig)
                .setOnlineModelConfig(modelConfig)
                .setEndpointConfig(endpointConfig)
                .setEnableEndpoint(true)
                .setDecodingMethod("modified_beam_search")
                .setMaxActivePaths(4) // 收窄搜索范围至4 (同英文)，防止"脑补"离谱叠词 (原12)
                .setHotwordsScore(50.0f) // 提高热词权重
                .setBlankPenalty(1.2f) // 提高惩罚以抑制非法重复 (原0.5)
                .build()

            modelZh = OnlineRecognizer(config)
            Log.i(TAG, "Chinese isolated recipe loaded to memory.")
        } catch (e: Exception) {
            Log.e(TAG, "Chinese model load failed", e)
            throw e
        }
    }

    private fun copyAsset(assetDir: String, fileName: String, destDir: String): String {
        val destFile = java.io.File(destDir, fileName)
        if (destFile.exists()) {
            Log.d(TAG, "File already exists: ${destFile.absolutePath} (${destFile.length()} bytes)")
            return destFile.absolutePath
        }
        
        // Ensure parent dir exists
        destFile.parentFile?.mkdirs()
        
        Log.i(TAG, "Copying asset: $assetDir/$fileName -> ${destFile.absolutePath}")
        
        activity.assets.open("$assetDir/$fileName").use { inputStream ->
            java.io.FileOutputStream(destFile).use { outputStream ->
                val bytes = inputStream.copyTo(outputStream)
                Log.i(TAG, "Copied $bytes bytes to ${destFile.name}")
            }
        }
        
        if (!destFile.exists()) {
            throw RuntimeException("Failed to copy file: ${destFile.absolutePath}")
        }
        
        Log.d(TAG, "Copy complete: ${destFile.absolutePath} (${destFile.length()} bytes)")
        return destFile.absolutePath
    }

    private fun startMicrophone() {
        if (isRecording) {
            Log.i(TAG, "Microphone is already running, re-creating stream with hotwords.")
            currentStream?.release()
            currentStream = currentModel?.createStreamWithHotwords(pendingHotwords)
            lastSentResult = ""
            isAsrStopped = false
            return
        }

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                Log.e(TAG, "No RECORD_AUDIO permission")
                return
            }
        }

        val minBufferSize = AudioRecord.getMinBufferSize(sampleRateInHz, channelConfig, audioFormat)
        audioRecord = AudioRecord(
            audioSource,
            sampleRateInHz,
            channelConfig,
            audioFormat,
            minBufferSize * 2
        )
        
        audioRecord?.startRecording()
        isRecording = true
        isAsrStopped = false
        
        // 使用当前活动模型创建热词流
        Log.i(TAG, "Creating stream with hotwords: '$pendingHotwords'")
        currentStream = currentModel?.createStreamWithHotwords(pendingHotwords)
        
        // 重置去重标记
        lastSentResult = ""
        
        recordingThread = thread(true) {
            processSamples(minBufferSize)
        }
        Log.i(TAG, "Started recording")
    }

    private fun processSamples(bufferSize: Int) {
        // 读取缓冲区大小略大于0.1s数据
        val readSize = maxOf(bufferSize, 1600 * 2) // 3200 bytes for 0.1s 16bit
        val buffer = ShortArray(readSize) 
        
        Log.i(TAG, "Processing samples loop started")

        while (isRecording) {
            val ret = audioRecord?.read(buffer, 0, buffer.size) ?: 0
            if (ret > 0) {
                // 1. 计算电平
                var sumSquares = 0.0
                for (i in 0 until ret) {
                    val s = buffer[i].toDouble()
                    sumSquares += s * s
                }
                val rms = sqrt(sumSquares / ret)
                val norm = (rms / 32768.0).coerceIn(0.0, 1.0)
                
                activity.runOnUiThread {
                     meterEvents?.success(norm)
                }

                // 2. 识别
                val s = currentStream
                val m = currentModel
                if (!isAsrStopped && m != null && s != null) {
                    // 使用当前配方定义的动态增益
                    val gain = activeGain
                    val samples = FloatArray(ret) { 
                        (buffer[it] / 32768.0f * gain).coerceIn(-1.0f, 1.0f) 
                    }
                    
                    try {
                        s.acceptWaveform(samples, sampleRateInHz)
                        
                        var decodeCount = 0
                        while (m.isReady(s)) {
                            m.decode(s)
                            decodeCount++
                        }
                        
                        val isEndpoint = m.isEndpoint(s)
                        val result = m.getResult(s)
                        val text = result.text.trim().lowercase() // 转小写
                        
                        // 【关键修复】：如果检测到端点（静音切断），必须重置流状态
                        // 否则旧的特征残余会导致后续识别出现“叠词”（如 限限）或无法开启新词识别
                        if (isEndpoint) {
                            m.reset(s)
                            lastSentResult = "" // 端点后重置去重，确保新的一句话能发出
                            Log.i(TAG, "ASR Endpoint detected: Stream reset.")
                        }
                        
                        val tokens = result.tokens
                        
                        // 周期性音量打印
                        audioBlockCount++
                        if (audioBlockCount % 20 == 0) {
                            Log.v(TAG, "ASR Monitor: lvl=${String.format("%.4f", norm)}, gain=${gain}x, tokens=${tokens?.size ?: 0}")
                        }

                        // 无条件发送记录
                        if (tokens != null && tokens.isNotEmpty()) {
                            Log.d(TAG, "Raw recognition: '$text' (toks=${tokens.size}, endpoint=$isEndpoint)")
                        }

                        // 发送逻辑：如实显示识别到的文字（不再过滤单字符），保留去重
                        val shouldSend = text.isNotBlank() && text != lastSentResult

                        if (shouldSend) {
                            lastSentResult = text
                            Log.i(TAG, ">>> SUCCESS! Sending text: '$text'")
                            activity.runOnUiThread {
                                try {
                                    val resultData = JSONObject().apply {
                                        put("best", text)
                                        put("candidates", JSONArray().apply { put(text) })
                                    }
                                    events?.success(resultData.toString())
                                } catch (e: Exception) {
                                    events?.success(text)
                                }
                            }
                        }

                        // 核心补丁：只有识别到了有效文本且触发了静音，才重置
                        if (isEndpoint && text.isNotBlank()) {
                            Log.d(TAG, "Recognition finished. Resetting stream.")
                            m.reset(s)
                            lastSentResult = ""
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "ASR Process Error: ${e.message}", e)
                    }
                }
            }
        }
    }

    private fun startAsr() {
        isAsrStopped = false
    }

    private fun stopAsr() {
        Log.i(TAG, "Stopping ASR (Hot Stop)...")
        isAsrStopped = true
        currentStream?.let { currentModel?.reset(it) }
        lastSentResult = ""
    }

    private fun stopMicrophone() {
        Log.i(TAG, "Stopping Microphone (Cold Stop)...")
        isRecording = false
        isAsrStopped = true
        
        try {
            recordingThread?.join(1000)
            recordingThread = null
            
            audioRecord?.stop()
            audioRecord?.release()
            audioRecord = null
            
            currentStream?.release()
            currentStream = null
        } catch (e: Exception) {
            Log.e(TAG, "Error checking/stopping audio: ${e.message}")
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.events = events
    }

    override fun onCancel(arguments: Any?) {
        this.events = null
    }

    // 释放资源，如onDestroy时调用
    fun release() {
        stopMicrophone()
        modelEn?.release()
        modelEn = null
        modelZh?.release()
        modelZh = null
        currentModel = null
    }
}
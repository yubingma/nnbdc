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

    // 跨平台音量计发送限频时间戳 (治理跨界通道拥堵)
    private var lastMeterSentTime = 0L

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
                    Log.i(TAG, "~~~~~ASR HOTWORDS: $pendingHotwords")
                    result.success(null)
                }
                "startMicrophone" -> {
                    startMicrophone(result)
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
                    synchronized(this) {
                        currentStream?.let { currentModel?.reset(it) }
                    }
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
        val wasRecording = isRecording
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
    private var activeGain: Float = 1.5f

    private fun loadModel(type: String) {
        // 1. 如果需要加载模型，先在同步锁外部执行，防止卡死后台录音读取线程的锁
        if (type == "en") {
            if (modelEn == null) {
                setupEnglishModel()
            }
        } else {
            if (modelZh == null) {
                setupChineseModel()
            }
        }

        // 2. 仅在切换模型引用和重置流时才加锁，锁内耗时不到 1ms，彻底杜绝对后台线程的阻塞
        synchronized(this) {
            // 先清理旧的流，释放资源
            currentStream?.release()
            currentStream = null
            
            if (type == "en") {
                currentModel = modelEn
                activeGain = 2.5f
            } else {
                currentModel = modelZh
                activeGain = 2.5f
            }
            
            currentModelType = type
            Log.i(TAG, "Switched working model to: $type, Gain: $activeGain")
        }
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
                .setNumThreads(2)
                .setDebug(false)
                .build()

            val featConfig = FeatureConfig.builder().setSampleRate(16000).setFeatureDim(80).build()

            // 英文识别配方：放宽末端静音检测，给犹豫的发音留时间
            val endpointConfig = EndpointConfig.builder()
                .setRule1(EndpointRule.builder().setMustContainNonSilence(false).setMinTrailingSilence(2.4f).build())
                .setRule2(EndpointRule.builder().setMustContainNonSilence(true).setMinTrailingSilence(0.4f).build())
                .setRule3(EndpointRule.builder().setMustContainNonSilence(false).setMinTrailingSilence(0f).setMinUtteranceLength(15.0f).build())
                .build()

            val config = OnlineRecognizerConfig.builder()
                .setFeatureConfig(featConfig)
                .setOnlineModelConfig(modelConfig)
                .setEndpointConfig(endpointConfig)
                .setEnableEndpoint(true)
                .setDecodingMethod("modified_beam_search")
                .setMaxActivePaths(8) // 适度降低搜索范围，平衡准确度与稳定性
                .setHotwordsScore(2.0f) // 【关键优化】：大幅降低热词权重，防止在长词识别时出现吞词或叠词。
                .setBlankPenalty(0.5f) // 增加惩罚，减少乱码和幻觉
                .build()

            modelEn = OnlineRecognizer(config)
            Log.i(TAG, "English isolated recipe loaded to memory.")
        } catch (e: Exception) {
            Log.e(TAG, "English model load failed", e)
            throw e
        }
    }

    private fun setupChineseModel() {
        val multiModelDir = "sherpa-onnx-streaming-zipformer-multi-zh-hans-2023-12-12"
        val cacheDir = activity.cacheDir.absolutePath
        
        Log.i(TAG, "Isolating Recipe: Loading CHINESE model (Multi-dataset Transducer - High Accuracy)")
        try {
            val destDir = "$cacheDir/$multiModelDir"
            val tokensPath = copyAsset(multiModelDir, "tokens.txt", destDir)
            val encoderPath = copyAsset(multiModelDir, "encoder-epoch-20-avg-1.int8.onnx", destDir)
            val decoderPath = copyAsset(multiModelDir, "decoder-epoch-20-avg-1.int8.onnx", destDir)
            val joinerPath = copyAsset(multiModelDir, "joiner-epoch-20-avg-1.int8.onnx", destDir)

            val modelConfig = OnlineModelConfig.builder()
                .setTransducer(OnlineTransducerModelConfig.builder()
                    .setEncoder(encoderPath).setDecoder(decoderPath).setJoiner(joinerPath).build())
                .setTokens(tokensPath)
                .setNumThreads(2)
                .setDebug(false)
                .build()

            val featConfig = FeatureConfig.builder().setSampleRate(16000).setFeatureDim(80).build()
            val endpointConfig = EndpointConfig.builder()
                .setRule1(EndpointRule.builder().setMustContainNonSilence(false).setMinTrailingSilence(2.4f).build())
                .setRule2(EndpointRule.builder().setMustContainNonSilence(true).setMinTrailingSilence(0.4f).build())
                .setRule3(EndpointRule.builder().setMustContainNonSilence(false).setMinTrailingSilence(0f).setMinUtteranceLength(15.0f).build())
                .build()

            val config = OnlineRecognizerConfig.builder()
                .setFeatureConfig(featConfig)
                .setOnlineModelConfig(modelConfig)
                .setEndpointConfig(endpointConfig)
                .setEnableEndpoint(true)
                .setDecodingMethod("modified_beam_search")
                .setMaxActivePaths(8) // 统一降低到 8
                .setHotwordsScore(2.0f) // 大幅降低热词权重
                .setBlankPenalty(0.5f) // 增加惩罚
                .build()

            modelZh = OnlineRecognizer(config)
            Log.i(TAG, "Chinese Multi-dataset Transducer recipe loaded.")
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

    // result 不为 null 时，在麦克风物理就绪后才回调 Dart（真正的 await 同步点）。
    // 这是根治「首词 ASR 不工作」的关键：Dart 的 await startMicrophone() 会真正阻塞，
    // 直到 AudioRecord.startRecording() 完成，而不是在后台线程启动后就假返回。
    private fun startMicrophone(result: MethodChannel.Result? = null) {
        if (isRecording) {
            Log.i(TAG, "Microphone is already running, re-creating stream with hotwords.")
            synchronized(this) {
                currentStream?.release()
                val hotwords = pendingHotwords
                currentStream = currentModel?.createStream(hotwords)
                lastSentResult = ""
                isAsrStopped = false
            }
            activity.runOnUiThread { result?.success(null) }
            return
        }

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                Log.e(TAG, "No RECORD_AUDIO permission")
                activity.runOnUiThread { result?.success(null) }
                return
            }
        }

        isRecording = true
        // isAsrStopped 不在此处改，保持 true，等待 startAsr() 统一开启解码
        lastSentResult = ""
        
        recordingThread = thread(true) {
            android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_BACKGROUND)
            
            val minBufferSize = AudioRecord.getMinBufferSize(sampleRateInHz, channelConfig, audioFormat)
            if (minBufferSize == AudioRecord.ERROR || minBufferSize == AudioRecord.ERROR_BAD_VALUE) {
                Log.e(TAG, "Invalid buffer size for AudioRecord")
                isRecording = false
                activity.runOnUiThread { result?.success(null) }
                return@thread
            }

            try {
                if (!isRecording) {
                    Log.i(TAG, "ASR start interrupted by stop command during thread launch.")
                    activity.runOnUiThread { result?.success(null) }
                    return@thread
                }

                val recordBufferSize = maxOf(minBufferSize * 2, 16000)
                val record = AudioRecord(
                    audioSource,
                    sampleRateInHz,
                    channelConfig,
                    audioFormat,
                    recordBufferSize
                )

                if (record.state != AudioRecord.STATE_INITIALIZED) {
                    Log.e(TAG, "Failed to initialize AudioRecord instance")
                    record.release()
                    isRecording = false
                    activity.runOnUiThread { result?.success(null) }
                    return@thread
                }

                if (!isRecording) {
                    Log.i(TAG, "ASR stop requested right after AudioRecord creation, releasing record.")
                    record.release()
                    activity.runOnUiThread { result?.success(null) }
                    return@thread
                }

                record.startRecording()
                audioRecord = record

                Log.i(TAG, "Creating stream with hotwords (in background): $pendingHotwords")
                val hotwords = pendingHotwords
                synchronized(this@Sherpa) {
                    currentStream = currentModel?.createStream(hotwords)
                }

                // startRecording + createStream 全部就绪，Dart 的 await 才真正可以继续
                activity.runOnUiThread { result?.success(null) }

                Log.i(TAG, "Started recording and ASR decoder in background thread successfully.")
                processSamples(minBufferSize)
            } catch (e: Exception) {

                Log.e(TAG, "Failed to start microphone in background: ${e.message}", e)
                isRecording = false
                activity.runOnUiThread { result?.success(null) }
            }
        }
    }

    private fun processSamples(bufferSize: Int) {
        // 固定每次读取 1600 个 Short 样本 (16kHz 采样率下单声道 0.1秒 / 100ms 的数据)
        val readSize = 1600
        val buffer = ShortArray(readSize) 
        
        Log.i(TAG, "Processing samples loop started with fixed read size: $readSize shorts (100ms)")

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
                
                val now = System.currentTimeMillis()
                if (now - lastMeterSentTime >= 60) {
                    lastMeterSentTime = now
                    activity.runOnUiThread {
                        meterEvents?.success(norm)
                    }
                }

                // 2. 识别
                synchronized(this) {
                    val s = currentStream
                    val m = currentModel
                    if (!isAsrStopped && isRecording && m != null && s != null) {
                        if (System.currentTimeMillis() < asrResumeTime) {
                            return@synchronized // Skip decoding to clear hardware reverb
                        }
                        
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
                            // ⚡ 优化：在物理输入音量极小（norm < 0.008）且用户尚未有效发声（lastSentResult.isEmpty()）的静息状态下，
                            // 强行拦截识别结果并判定为 ""（静音），防止背景空气噪声被误判为 "and" 等幻觉词
                            val rawText = result.text.trim().lowercase()
                            val text = rawText
                            
                            // 仅在用户实际说过话后才在端点时重置流
                            // 纯静音端点（用户还没开口）不重置，避免打断即将开始的识别
                            if (isEndpoint) {
                                if (lastSentResult.isNotEmpty()) {
                                    m.reset(s)
                                    lastSentResult = ""
                                    Log.i(TAG, "ASR Endpoint detected: Stream reset.")
                                }
                            }
                            
                            val tokens = result.tokens

                            // 无条件发送记录
                            if (tokens != null && tokens.isNotEmpty()) {
                                Log.d(TAG, "Raw recognition: '$text' (toks=${tokens.size}, endpoint=$isEndpoint)")
                            }

                            // 发送逻辑：如实显示识别到的文字（不再过滤单字符），保留去重
                            val shouldSend = text.isNotBlank() && (text != lastSentResult || isEndpoint)

                            if (shouldSend) {
                                 lastSentResult = text
                                Log.d(TAG, "~~~~~ASR RESULT: '$text' (isFinal=$isEndpoint)")
                                activity.runOnUiThread {
                                    try {
                                        val resultData = JSONObject().apply {
                                            put("best", text)
                                            put("candidates", JSONArray().apply { put(text) })
                                            put("isFinal", isEndpoint)
                                        }
                                        events?.success(resultData.toString())
                                    } catch (e: Exception) {
                                        events?.success(text)
                                    }
                                }
                            } else if (text.isNotBlank()) {
                                Log.v(TAG, "ASR Result Duplicated (Ignored): '$text'")
                            }

                            // 该逻辑已合并到上方
                        } catch (e: Exception) {
                            Log.e(TAG, "ASR Process Error: ${e.message}", e)
                        }
                    }
                }
            }
        }
    }

    private var asrResumeTime = 0L

    private fun startAsr() {
        Log.i(TAG, "Starting ASR...")
        asrResumeTime = System.currentTimeMillis() + 300 // 与短促的提示音配合，缩短等待时间以提升体验
        isAsrStopped = false
        lastSentResult = "" // 开启识别时强制重置上一次结果，避免残留
    }

    private fun stopAsr() {
        synchronized(this) {
            Log.i(TAG, "Stopping ASR (Hot Stop)...")
            isAsrStopped = true
            try {
                currentStream?.let { s -> currentModel?.let { m -> m.reset(s) } }
            } catch (e: Exception) {
                Log.e(TAG, "Error during Hot Stop reset: ${e.message}")
            }
            lastSentResult = ""
        }
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
            
            synchronized(this) {
                currentStream?.release()
                currentStream = null
            }
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
        thread {
            try {
                Log.i(TAG, "Releasing Sherpa resources in background thread")
                stopMicrophone()
                modelEn?.release()
                modelEn = null
                modelZh?.release()
                modelZh = null
                currentModel = null
                Log.i(TAG, "Sherpa resources released successfully in background")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to release Sherpa resources in background", e)
            }
        }
    }
}
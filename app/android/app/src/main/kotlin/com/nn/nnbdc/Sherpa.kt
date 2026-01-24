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
    private var model: OnlineRecognizer? = null
    private var stream: OnlineStream? = null
    // 当前模型语言类型: "zh" or "en"
    private var currentModelType: String = ""
    
    // 上一次发送的识别结果，用于去重
    private var lastSentResult: String = ""
    
    // Audio Recording
    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null
    private val audioSource = MediaRecorder.AudioSource.MIC
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
                "reset" -> {
                    stream?.let { model?.reset(it) }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // 可以在 MainActivity onCreate 中调用初始化默认模型
    fun initModel() {
        // 默认初始化中文
        loadModel("zh")
    }

    private fun setLanguage(locale: String) {
        val newType = if (locale.startsWith("en")) "en" else "zh"

        if (newType == currentModelType && model != null) {
            currentLocale = locale
            Log.i(TAG, "Model already loaded for $newType")
            return
        }

        Log.i(TAG, "Switching model from '$currentModelType' to '$newType' (locale: $locale)")
        
        // 如果正在录音，需要重启录音线程以确保模型切换不用锁
        val wasRecording = isRecording && !isAsrStopped
        if (wasRecording) {
            stopAsr()
        }

        try {
            loadModel(newType)
            currentLocale = locale
        } catch (e: Exception) {
            Log.e(TAG, "Failed to switch model to $newType", e)
            // 尝试回退到中文
            if (model == null) loadModel("zh")
        }

        if (wasRecording) {
            startMicrophone()
        }
    }

    private fun loadModel(type: String) {
        // 释放旧模型和流
        stream?.release()
        stream = null
        model?.release()
        model = null
        
        val modelDir: String
        // 定义资源路径 (相对于 assets)
        if (type == "en") {
            // Sherpa-onnx Streaming Zipformer English 20M 2023-02-17
            modelDir = "sherpa-onnx-streaming-zipformer-en-20M-2023-02-17"
        } else {
            // Sherpa-onnx Streaming Zipformer Chinese 14M 2023-02-23
            modelDir = "sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23"
        }

        Log.i(TAG, "Loading model from assets: $modelDir")

        try {
            // 1. 将模型文件从 Assets 复制到 Cache 目录
            val cacheDir = activity.cacheDir.absolutePath
            val destDir = "$cacheDir/$modelDir"
            val tokensPath = copyAsset(modelDir, "tokens.txt", destDir)
            val encoderPath = copyAsset(modelDir, "encoder-epoch-99-avg-1.int8.onnx", destDir)
            val decoderPath = copyAsset(modelDir, "decoder-epoch-99-avg-1.int8.onnx", destDir)
            val joinerPath = copyAsset(modelDir, "joiner-epoch-99-avg-1.int8.onnx", destDir)

            // 2. 配置模型 (使用 Builder 模式)
            val transducerConfig = OnlineTransducerModelConfig.builder()
                .setEncoder(encoderPath)
                .setDecoder(decoderPath)
                .setJoiner(joinerPath)
                .build()
            
            val modelConfig = OnlineModelConfig.builder()
                .setTransducer(transducerConfig)
                .setTokens(tokensPath)
                .setNumThreads(2)
                .setDebug(true)
                .setModelType("zipformer")
                .build()
            
            val featConfig = FeatureConfig.builder()
                .setSampleRate(16000)
                .setFeatureDim(80)
                .build()

            // 英文模型：使用最宽松的端点检测，防止误杀
            val (rule1Silence, rule2Silence, rule3Length) = if (type == "en") {
                Triple(10.0f, 5.0f, 60.0f)  // 英文：给足 10 秒静音余地
            } else {
                Triple(2.4f, 0.8f, 20.0f)  // 中文
            }

            val rule1 = EndpointRule.builder()
                .setMustContainNonSilence(false)
                .setMinTrailingSilence(rule1Silence)
                .setMinUtteranceLength(0f)
                .build()
            
            val rule2 = EndpointRule.builder()
                .setMustContainNonSilence(true)
                .setMinTrailingSilence(rule2Silence)
                .setMinUtteranceLength(0f)
                .build()
            
            val rule3 = EndpointRule.builder()
                .setMustContainNonSilence(false)
                .setMinTrailingSilence(0f)
                .setMinUtteranceLength(rule3Length)
                .build()

            val endpointConfig = EndpointConfig.builder()
                .setRule1(rule1)
                .setRule2(rule2)
                .setRul3(rule3)
                .build()

            val config = OnlineRecognizerConfig.builder()
                .setFeatureConfig(featConfig)
                .setOnlineModelConfig(modelConfig)
                .setEndpointConfig(endpointConfig)
                .setEnableEndpoint(true)
                .setDecodingMethod("modified_beam_search")
                .setMaxActivePaths(4)
                .build()
            
            // 验证配置路径
            Log.i(TAG, "Model config paths:")
            Log.i(TAG, "  Tokens: $tokensPath")
            Log.i(TAG, "  Encoder: $encoderPath")
            Log.i(TAG, "  Decoder: $decoderPath")
            Log.i(TAG, "  Joiner: $joinerPath")

            // 3. 创建识别器 (使用通用 Java API，无 AssetManager)
            model = OnlineRecognizer(config)
            
            currentModelType = type
            Log.i(TAG, "Sherpa-ONNX model loaded successfully: $type")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error loading model: ${e.message}")
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
            stopAsr()
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
        
        // 创建新的识别流
        stream = model?.createStream()
        
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
                val s = stream
                val m = model
                if (!isAsrStopped && m != null && s != null) {
                    // 提升增益至 8 倍，确保“听得见”
                    val gain = 8.0f
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
                        val text = result.text.trim().uppercase() // 转大写增强对比度
                        val tokens = result.tokens
                        
                        // 周期性音量打印
                        audioBlockCount++
                        if (audioBlockCount % 20 == 0) {
                            Log.v(TAG, "ASR Monitor: lvl=${String.format("%.4f", norm)}, gain=8x, tokens=${tokens?.size ?: 0}")
                        }

                        // 无条件发送记录
                        if (tokens != null && tokens.isNotEmpty()) {
                            Log.d(TAG, "Raw recognition: '$text' (toks=${tokens.size}, endpoint=$isEndpoint)")
                        }

                        // 发送逻辑：过滤单字母和空白
                        val shouldSend = text.isNotBlank() && 
                                        text.length > 1 && 
                                        text != lastSentResult

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
        Log.i(TAG, "Stopping ASR...")
        isRecording = false
        isAsrStopped = true
        
        try {
            recordingThread?.join(1000)
            recordingThread = null
            
            audioRecord?.stop()
            audioRecord?.release()
            audioRecord = null
            
            stream?.release()
            stream = null
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
        stopAsr()
        model?.release()
        model = null
    }
}
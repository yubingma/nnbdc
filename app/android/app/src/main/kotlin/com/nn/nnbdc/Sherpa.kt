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
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

// Sherpa-ONNX imports
import com.k2fsa.sherpa.onnx.*

private const val TAG = "sherpa-onnx"

// 静音判定阈值:归一化 RMS 低于此值视为静音块(16kHz 16bit,静音环境约 0.003-0.01)
private const val SILENCE_THRESHOLD = 0.015f
// 连续静音块数:达到此数量(每块 100ms)认为用户已说完、缓冲区尾部音频已排空
private const val SILENCE_BLOCK_COUNT = 3

class Sherpa(private val activity: Activity) : EventChannel.StreamHandler {
    private var eventChannel: EventChannel? = null
    private var events: EventChannel.EventSink? = null
    private var meterChannel: EventChannel? = null
    private var meterEvents: EventChannel.EventSink? = null

    // Sherpa Onnx Recognizer
    private val modelInitLock = Any()
    @Volatile
    private var modelEn: OnlineRecognizer? = null
    @Volatile
    private var modelEnSentence: OnlineRecognizer? = null
    @Volatile
    private var modelZh: OnlineRecognizer? = null
    private var sentenceBpeTokenizer: BpeTokenizer? = null
    
    // 当前使用的工作模型指针
    @Volatile
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
    // ASR 会话代际：startAsr/stopAsr 均递增。runOnUiThread 发送前校验，
    // 丢弃 stop 前已入队的遗留事件，避免污染下一次 PTT 识别会话
    @Volatile
    private var asrEpoch = 0L
    // Flush 排空信号：stopAsr 等待 processSamples 把 AudioRecord 缓冲区中的
    // 尾部音频(含词尾静音)全部喂入后通知，确保 flush 能解出完整尾部单词。
    @Volatile
    private var flushSignal: CountDownLatch? = null
    // 停止后连续静音块计数，用于判定用户已说完、缓冲区尾部音频已排空
    private var silentBlockCount = 0

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
                    thread {
                        try {
                            setLanguage(locale)
                            activity.runOnUiThread {
                                result.success(null)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to setLanguage asynchronously", e)
                            activity.runOnUiThread {
                                result.error("SET_LANGUAGE_FAILED", e.message, null)
                            }
                        }
                    }
                }
                "setContextualStrings" -> {
                    val phrases = call.argument<List<String>>("phrases") ?: emptyList()
                    pendingHotwords = if (sentenceBpeTokenizer != null && (currentModelType == "en_sentence" || currentModelType == "en")) {
                        // 英文模型(基于 Zipformer BPE): Java 侧先用 BPE 分词器把短语编码为 token 序列,
                        // 再用 "/" 分隔多个短语。createStream 会把 "/" 转 "\n",
                        // EncodeBase 直接查 symbol_table 得到 token id(无需 C++ bpe_encoder)。
                        phrases.map { sentenceBpeTokenizer!!.tokenize(it) }.filter { it.isNotEmpty() }.joinToString("/")
                    } else {
                        phrases.joinToString(" ") { it.uppercase() }
                    }
                    Log.i(TAG, "~~~~~ASR HOTWORDS (Tokenized): $pendingHotwords")
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
                    // stopAsr 内含 latch.await + flush decode 循环(最长 ~1.5s),
                    // 必须在后台线程执行,否则会阻塞 Android 主线程,
                    // 导致松开按钮瞬间 UI 事件滞留、识别结果显示立刻停止。
                    thread {
                        val flushText = stopAsr()
                        activity.runOnUiThread {
                            result.success(flushText)
                        }
                    }
                }
                "stopMicrophone" -> {
                    thread {
                        try {
                            stopMicrophone()
                            activity.runOnUiThread {
                                result.success(null)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to stopMicrophone asynchronously", e)
                            activity.runOnUiThread {
                                result.success(null)
                            }
                        }
                    }
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
                            synchronized(modelInitLock) {
                                if (modelZh == null) setupChineseModel()
                                if (modelEn == null) setupEnglishModel()
                                if (modelEnSentence == null) setupEnglishSentenceModel()
                            }
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
        thread {
            try {
                // 默认初始化中文（并且设定为当前模型）
                loadModel("zh")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to initModel in background", e)
            }
        }
    }

    private fun setLanguage(locale: String) {
        val newType = if (locale.startsWith("en")) {
            if (locale.contains("sentence")) "en_sentence" else "en"
        } else {
            "zh"
        }

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
        // 1. 如果需要加载模型，使用独立的模型加载锁保护，防止并发加载导致文件写入竞争与内存峰值，
        //    同时完全不占用 this 锁，杜绝卡死后台录音 processSamples 线程
        synchronized(modelInitLock) {
            if (type == "en_sentence") {
                if (modelEnSentence == null) {
                    setupEnglishSentenceModel()
                }
            } else if (type == "en") {
                if (modelEn == null) {
                    setupEnglishModel()
                }
            } else {
                if (modelZh == null) {
                    setupChineseModel()
                }
            }
        }

        // 2. 仅在切换模型引用和重置流时才加锁，锁内耗时不到 1ms，彻底杜绝对后台线程的阻塞
        synchronized(this) {
            // 先清理旧的流，释放资源
            currentStream?.release()
            currentStream = null
            
            if (type == "en_sentence") {
                currentModel = modelEnSentence
                activeGain = 2.5f
                Log.i(TAG, "ASR_MODEL_ACTIVE: Switched working model to ENGLISH SENTENCE MODEL (en-20M BPE)")
            } else if (type == "en") {
                currentModel = modelEn
                activeGain = 2.5f
                Log.i(TAG, "ASR_MODEL_ACTIVE: Switched working model to ENGLISH PHONE-BASED MODEL (en-66M Phone)")
            } else {
                currentModel = modelZh
                activeGain = 2.5f
                Log.i(TAG, "ASR_MODEL_ACTIVE: Switched working model to CHINESE/MULTI MODEL")
            }
            
            currentModelType = type
            Log.i(TAG, "Switched working model to: $type, Gain: $activeGain")
        }
    }

    private fun setupEnglishModel() {
        val modelDir = "sherpa-onnx-streaming-zipformer-en-2023-06-21"
        Log.i(TAG, "ASR_MODEL_ACTIVE: Loading UNIFIED ENGLISH model (Standard 80M)")

        try {
            val cacheDir = activity.cacheDir.absolutePath
            val destDir = "$cacheDir/$modelDir"
            val tokensPath = copyAsset(modelDir, "tokens.txt", destDir)
            val encoderPath = copyAsset(modelDir, "encoder-epoch-99-avg-1.int8.onnx", destDir)
            val decoderPath = copyAsset(modelDir, "decoder-epoch-99-avg-1.onnx", destDir)
            val joinerPath = copyAsset(modelDir, "joiner-epoch-99-avg-1.int8.onnx", destDir)
            val bpeVocabPath = copyAsset(modelDir, "bpe_vocab.txt", destDir)

            if (sentenceBpeTokenizer == null) {
                val tokensContent = java.io.File(tokensPath).readText()
                sentenceBpeTokenizer = BpeTokenizer(tokensContent)
            }

            val modelConfig = OnlineModelConfig.builder()
                .setTransducer(OnlineTransducerModelConfig.builder()
                    .setEncoder(encoderPath).setDecoder(decoderPath).setJoiner(joinerPath).build())
                .setTokens(tokensPath)
                .setModelingUnit("bpe")
                .setBpeVocab(bpeVocabPath)
                .setNumThreads(2)
                .setDebug(false)
                .build()

            val featConfig = FeatureConfig.builder().setSampleRate(16000).setFeatureDim(80).build()

            // 英文识别配方：放宽末端静音检测，给犹豫的发音留时间
            val endpointConfig = EndpointConfig.builder()
                .setRule1(EndpointRule.builder().setMustContainNonSilence(false).setMinTrailingSilence(2.4f).build())
                .setRule2(EndpointRule.builder().setMustContainNonSilence(true).setMinTrailingSilence(1.2f).build())
                .setRule3(EndpointRule.builder().setMustContainNonSilence(false).setMinTrailingSilence(0f).setMinUtteranceLength(15.0f).build())
                .build()

            val config = OnlineRecognizerConfig.builder()
                .setFeatureConfig(featConfig)
                .setOnlineModelConfig(modelConfig)
                .setEndpointConfig(endpointConfig)
                .setEnableEndpoint(true)
                .setDecodingMethod("modified_beam_search")
                .setMaxActivePaths(8) // 适度降低搜索范围，平衡准确度与稳定性
                .setHotwordsScore(3.0f) // 【关键优化】：微调热词权重为 3.0f，平衡口音纠偏与吞词叠词副作用。
                .setBlankPenalty(0.5f) // 增加惩罚，减少乱码和幻觉
                .build()

            modelEn = OnlineRecognizer(config)
            Log.i(TAG, "English isolated recipe loaded to memory.")
        } catch (e: Exception) {
            Log.e(TAG, "English model load failed", e)
            throw e
        }
    }

    private fun setupEnglishSentenceModel() {
        val modelDir = "sherpa-onnx-streaming-zipformer-en-2023-06-21"
        Log.i(TAG, "ASR_MODEL_ACTIVE: Loading ENGLISH SENTENCE BPE model (Standard 80M)")

        try {
            val cacheDir = activity.cacheDir.absolutePath
            val destDir = "$cacheDir/$modelDir"
            val tokensPath = copyAsset(modelDir, "tokens.txt", destDir)
            val encoderPath = copyAsset(modelDir, "encoder-epoch-99-avg-1.int8.onnx", destDir)
            val decoderPath = copyAsset(modelDir, "decoder-epoch-99-avg-1.onnx", destDir)
            val joinerPath = copyAsset(modelDir, "joiner-epoch-99-avg-1.int8.onnx", destDir)

            val tokensContent = java.io.File(tokensPath).readText()
            sentenceBpeTokenizer = BpeTokenizer(tokensContent)

            // 热词需要 modeling_unit=bpe + bpe_vocab:C++ 的 EncodeHotwords 才能把
            // 原始英文短语编码为 token 序列。默认 modeling_unit=cjkchar 会按字符切分
            // 英文导致热词编码失败("Encode hotwords failed"),热词 biasing 完全失效。
            val bpeVocabPath = copyAsset(modelDir, "bpe_vocab.txt", destDir)

            val modelConfig = OnlineModelConfig.builder()
                .setTransducer(OnlineTransducerModelConfig.builder()
                    .setEncoder(encoderPath).setDecoder(decoderPath).setJoiner(joinerPath).build())
                .setTokens(tokensPath)
                .setModelingUnit("bpe")
                .setBpeVocab(bpeVocabPath)
                .setNumThreads(2)
                .setDebug(false)
                .build()

            val featConfig = FeatureConfig.builder().setSampleRate(16000).setFeatureDim(80).build()

            val endpointConfig = EndpointConfig.builder()
                .setRule1(EndpointRule.builder().setMustContainNonSilence(false).setMinTrailingSilence(2.4f).build())
                .setRule2(EndpointRule.builder().setMustContainNonSilence(true).setMinTrailingSilence(1.2f).build())
                .setRule3(EndpointRule.builder().setMustContainNonSilence(false).setMinTrailingSilence(0f).setMinUtteranceLength(15.0f).build())
                .build()

            val config = OnlineRecognizerConfig.builder()
                .setFeatureConfig(featConfig)
                .setOnlineModelConfig(modelConfig)
                .setEndpointConfig(endpointConfig)
                .setEnableEndpoint(true)
                .setDecodingMethod("modified_beam_search")
                .setMaxActivePaths(20)
                .setHotwordsScore(3.0f)
                .setBlankPenalty(0.5f)
                .build()

            modelEnSentence = OnlineRecognizer(config)
            Log.i(TAG, "ASR_MODEL_ACTIVE: English sentence BPE 20M recipe loaded to memory successfully.")
        } catch (e: Exception) {
            Log.e(TAG, "English sentence model load failed", e)
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
        val assetPath = "$assetDir/$fileName"

        // 尝试获取 asset 的预期解压大小：优先 openFd，若被压缩则通过 APK ZipEntry 读取未压缩大小
        val expectedSize: Long = try {
            activity.assets.openFd(assetPath).use { it.length }
        } catch (e: Exception) {
            try {
                java.util.zip.ZipFile(activity.applicationInfo.sourceDir).use { zip ->
                    zip.getEntry("assets/$assetPath")?.size ?: -1L
                }
            } catch (ze: Exception) {
                -1L
            }
        }

        // 如果目标文件已存在，校验其完整性：
        // 1. 不能是 0 字节的残缺文件
        // 2. 若 expectedSize > 0，大小必须严格与 asset 一致，避免历史上异常中断留下的半写入文件
        if (destFile.exists()) {
            val currentLen = destFile.length()
            val isValid = if (expectedSize > 0L) {
                currentLen == expectedSize
            } else {
                currentLen > 0L
            }

            if (isValid) {
                Log.d(TAG, "File already exists and verified: ${destFile.absolutePath} ($currentLen bytes)")
                return destFile.absolutePath
            } else {
                Log.w(TAG, "Found corrupt or incomplete file: ${destFile.absolutePath} ($currentLen bytes, expected: $expectedSize). Deleting and re-copying.")
                destFile.delete()
            }
        }

        // Ensure parent dir exists
        destFile.parentFile?.mkdirs()

        Log.i(TAG, "Copying asset: $assetPath -> ${destFile.absolutePath} (expected: $expectedSize bytes)")

        // 写入临时文件，写入完毕并验证无误后原子重命名，防止并发读取半成品或写入中断留残存文件
        val tempFile = java.io.File(destDir, "$fileName.tmp_${System.currentTimeMillis()}")
        try {
            activity.assets.open(assetPath).use { inputStream ->
                java.io.FileOutputStream(tempFile).use { outputStream ->
                    val bytes = inputStream.copyTo(outputStream)
                    outputStream.flush()
                    Log.i(TAG, "Copied $bytes bytes to temp file ${tempFile.name}")
                }
            }

            if (!tempFile.exists() || tempFile.length() == 0L || (expectedSize > 0L && tempFile.length() != expectedSize)) {
                throw java.io.IOException("Incomplete asset copy for $assetPath: copied ${tempFile.length()} bytes, expected $expectedSize")
            }

            // 原子重命名为正式目标文件
            if (!tempFile.renameTo(destFile)) {
                destFile.delete()
                if (!tempFile.renameTo(destFile)) {
                    throw java.io.IOException("Failed to rename temp file ${tempFile.absolutePath} to ${destFile.absolutePath}")
                }
            }
        } catch (e: Exception) {
            tempFile.delete()
            throw e
        }

        Log.d(TAG, "Copy complete and verified: ${destFile.absolutePath} (${destFile.length()} bytes)")
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
                asrResumeTime = System.currentTimeMillis() + 300 // 重建 Stream 后静默 300ms，清理时序抖动
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
                    asrResumeTime = System.currentTimeMillis() + 300 // 物理麦克风就绪后静默 300ms，避开开启时的瞬态脉冲
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
            if (ret < 0) {
                Log.e(TAG, "AudioRecord read returned error code: $ret. Stopping recording loop.")
                isRecording = false
                break
            } else if (ret == 0) {
                try {
                    Thread.sleep(20)
                } catch (e: InterruptedException) {
                    // Ignore
                }
                continue
            }

            if (ret > 0) {
                // 1. 计算电平 (加入 3.5x 硬件增益补偿与分贝对数归一化，与 iOS 灵敏度完全对齐)
                var sumSquares = 0.0
                for (i in 0 until ret) {
                    val s = (buffer[i].toDouble() / 32768.0) * 3.5
                    sumSquares += s * s
                }
                val rms = sqrt(sumSquares / ret).toFloat()
                val minDb = -45.0f
                var db = 20.0f * kotlin.math.log10(maxOf(rms, 1e-5f))
                if (db < minDb) db = minDb
                if (db > 0.0f) db = 0.0f
                val norm = (1.0f - kotlin.math.abs(db) / kotlin.math.abs(minDb)).coerceIn(0.0f, 1.0f)
                
                val now = System.currentTimeMillis()
                if (now - lastMeterSentTime >= 35) {
                    lastMeterSentTime = now
                    activity.runOnUiThread {
                        meterEvents?.success(norm.toDouble())
                    }
                }

                // 2. 识别
                synchronized(this) {
                    val s = currentStream
                    val m = currentModel
                    if (isRecording && m != null && s != null) {
                        if (System.currentTimeMillis() < asrResumeTime) {
                            return@synchronized // Skip decoding to clear hardware reverb
                        }

                        // 使用当前配方定义的动态增益
                        val gain = activeGain
                        val samples = FloatArray(ret) {
                            (buffer[it] / 32768.0f * gain).coerceIn(-1.0f, 1.0f)
                        }

                        try {
                            // 无条件喂入：即使已收到停止信号，仍要把本块喂入，
                            // 让 stopAsr 的 flush 能解码到松开瞬间的尾部单词
                            s.acceptWaveform(samples, sampleRateInHz)

                            // 停止信号已发出：本块已喂入，不再解码发送，由 stopAsr 统一 flush。
                            // 连续静音块意味着 AudioRecord 缓冲区中的尾部音频(含词尾)已
                            // 全部读出喂入——此时通知 stopAsr 可以安全 inputFinished + flush，
                            // 避免词尾音频仍滞留在缓冲区导致最后一个词解码不完整。
                            if (isAsrStopped) {
                                if (norm < SILENCE_THRESHOLD) {
                                    silentBlockCount++
                                    if (silentBlockCount >= SILENCE_BLOCK_COUNT) {
                                        flushSignal?.let { latch ->
                                            flushSignal = null
                                            latch.countDown()
                                        }
                                    }
                                } else {
                                    silentBlockCount = 0
                                }
                                return@synchronized
                            }

                            var decodeCount = 0
                            while (m.isReady(s)) {
                                m.decode(s)
                                decodeCount++
                            }
                            
                            val isEndpoint = m.isEndpoint(s)
                            val result = m.getResult(s)
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
                                val sendEpoch = asrEpoch
                                activity.runOnUiThread {
                                    // 若已 stop/start 切换会话，丢弃已入队的遗留事件
                                    if (sendEpoch != asrEpoch) return@runOnUiThread
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
        synchronized(this) {
            // PTT 重按热复用:旧 stream 已在 stopAsr 释放,此处为空则重建,避免复用残留音频。
            // 关键:即使 stream 已存在(startMicrophone 预创建),也要用最新 pendingHotwords
            // 重建——否则 startMicrophone 时热词可能尚未设置(setContextualStrings 在
            // startAsr 之前才调用),复用旧 stream 会导致热词 biasing 不生效,
            // 识别准确率差(如 discipline 识别为 easy plain)。
            val hotwords = pendingHotwords
            currentStream?.release()
            Log.i(TAG, "Creating fresh stream with hotwords: $hotwords")
            currentStream = currentModel?.createStream(hotwords)
            asrResumeTime = System.currentTimeMillis() + 300 // 恢复至 300ms 安全延迟，避免吞句首词
            asrEpoch++
            isAsrStopped = false
            lastSentResult = "" // 开启识别时强制重置上一次结果，避免残留
        }
    }

    private fun stopAsr(): String? {
        var flushText: String? = null
        val latch = CountDownLatch(1)
        synchronized(this) {
            Log.i(TAG, "Stopping ASR (Flush Stop)...")
            isAsrStopped = true
            asrEpoch++
            silentBlockCount = 0
            flushSignal = latch
        }
        // 等待 processSamples 排空 AudioRecord 缓冲区中的尾部音频：
        // 停止后它持续喂入，直到读到连续静音块(用户已说完、词尾音频+静音全部
        // 进入 stream)才通知本方法。词尾静音是 sherpa-onnx 在线模型确定词边界
        // 的必要输入，等不到静音就 inputFinished 会导致最后一个词解码不完整
        // (如 yesterday 只解出 yesterd)。800ms 超时仅作环境持续噪音时的兜底。
        try {
            latch.await(800, TimeUnit.MILLISECONDS)
        } catch (e: InterruptedException) {
            Log.e(TAG, "Interrupted while waiting for in-flight audio feed", e)
        }
        synchronized(this) {
            try {
                val s = currentStream
                val m = currentModel
                if (m != null && s != null) {
                    // 优雅收尾:结束音频输入,解码所有已喂入的残留音频,送出最终结果。
                    // 这样松开按钮不会硬切丢词,尾部单词自然识别完成后再释放。
                    //
                    // 关键:sherpa-onnx 流式解码按 chunk 批量进行,IsReady() 要求至少
                    // 有 1 个完整 chunk 的新帧才解码。松开瞬间尾部音频不足一个 chunk 时,
                    // 最后几个词(尤其最后一个词)的帧永远不会被解码,导致词尾缺失
                    // (如 yesterday 只解出 yesterd)。解决:填充尾部静音 padding,
                    // 让 NumFramesReady 覆盖所有真实帧,IsReady 保持 true 直到真实
                    // 音频(含词尾)全部解码完。静音 padding 只产生 blank,不引入噪音。
                    val tailPadSeconds = 0.8f
                    val tailPadding = FloatArray((tailPadSeconds * sampleRateInHz).toInt())
                    s.acceptWaveform(tailPadding, sampleRateInHz)
                    s.inputFinished()
                    var decodeCount = 0
                    val flushDeadline = System.currentTimeMillis() + 1000 // 安全上限,防极端长音频卡死 UI 线程
                    while (m.isReady(s) && System.currentTimeMillis() < flushDeadline) {
                        m.decode(s)
                        decodeCount++
                    }
                    if (decodeCount > 0) {
                        Log.i(TAG, "Flush decoded $decodeCount extra chunk(s).")
                    }
                    val result = m.getResult(s)
                    val text = result.text.trim().lowercase()
                    // 不能以 text != lastSentResult 作为返回条件:processSamples 在发送事件
                    // 前就已同步更新 lastSentResult,但该事件可能因 asrEpoch 递增被丢弃,
                    // 导致 Flutter 端未收到含尾词的文本。flush 必须无条件返回完整文本,
                    // 去重拼接交给 Flutter 端的 stitchTexts 处理。
                    if (text.isNotBlank()) {
                        lastSentResult = text
                        flushText = text
                        Log.d(TAG, "~~~~~ASR FLUSH FINAL: '$text'")
                        // Flutter 的 EventSink.success 必须在主线程调用(@UiThread),
                        // stopAsr 在后台线程执行,因此经 runOnUiThread 发送。
                        // Flutter 端 stopPttAsr 已改用 flushText 直接判定,不依赖
                        // 此事件先行到达,故可安全切主线程发送。
                        try {
                            val resultData = JSONObject().apply {
                                put("best", text)
                                put("candidates", JSONArray().apply { put(text) })
                                put("isFinal", true)
                            }
                            activity.runOnUiThread {
                                try {
                                    events?.success(resultData.toString())
                                } catch (e: Exception) {
                                    events?.success(text)
                                }
                            }
                        } catch (e: Exception) {
                            activity.runOnUiThread {
                                events?.success(text)
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error during Flush Stop: ${e.message}", e)
            }
            // 彻底释放旧 stream 及其内部未解码的音频特征(Sherpa reset 不清空特征提取器,
            // 复用旧 stream 会把残留音频在新会话中解码出来)。下次 startAsr 重建干净 stream。
            currentStream?.release()
            currentStream = null
            lastSentResult = ""
            flushSignal = null
        }
        return flushText
    }

    private fun stopMicrophone() {
        if (!isRecording && audioRecord == null && recordingThread == null && currentStream == null) {
            return
        }
        Log.i(TAG, "Stopping Microphone (Cold Stop)...")
        isRecording = false
        isAsrStopped = true
        
        try {
            recordingThread?.join(500)
            recordingThread = null
            
            try {
                audioRecord?.stop()
            } catch (e: Exception) {
                Log.w(TAG, "Error stopping audioRecord: ${e.message}")
            }
            try {
                audioRecord?.release()
            } catch (e: Exception) {
                Log.w(TAG, "Error releasing audioRecord: ${e.message}")
            }
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
                synchronized(modelInitLock) {
                    modelEn?.release()
                    modelEn = null
                    modelEnSentence?.release()
                    modelEnSentence = null
                    modelZh?.release()
                    modelZh = null
                    currentModel = null
                }
                Log.i(TAG, "Sherpa resources released successfully in background")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to release Sherpa resources in background", e)
            }
        }
    }

    private fun getRms(buffer: ShortArray, size: Int): Float {
        var sum = 0.0f
        for (i in 0 until size) {
            val sample = buffer[i] / 32768.0f
            sum += sample * sample
        }
        return if (size > 0) Math.sqrt((sum / size).toDouble()).toFloat() else 0.0f
    }
}

class BpeTokenizer(tokensFileContent: String) {
    private val tokenSet = HashSet<String>()
    
    init {
        tokensFileContent.lines().forEach { line ->
            val parts = line.trim().split(Regex("\\s+"))
            if (parts.size >= 2) {
                val token = parts[0].replace("▁", "\u2581")
                tokenSet.add(token)
            }
        }
    }

    fun tokenize(text: String): String {
        val words = text.uppercase().trim().split(Regex("[^A-Z0-9'#]+")).filter { it.isNotEmpty() }
        val resultTokens = mutableListOf<String>()

        for (word in words) {
            val bpeWord = "\u2581$word"
            var temp = bpeWord
            while (temp.isNotEmpty()) {
                var matched = false
                for (len in temp.length downTo 1) {
                    val sub = temp.substring(0, len)
                    if (tokenSet.contains(sub)) {
                        resultTokens.add(sub)
                        temp = temp.substring(len)
                        matched = true
                        break
                    }
                }
                if (!matched) {
                    val singleChar = temp.substring(0, 1)
                    resultTokens.add(singleChar)
                    temp = temp.substring(1)
                }
            }
        }
        return resultTokens.joinToString(" ")
    }
}
package com.nn.nnbdc

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Bundle
import android.text.method.ScrollingMovementMethod
import android.util.Log
import android.widget.Button
import android.widget.TextView
import kotlin.concurrent.thread

import android.app.Activity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.k2fsa.sherpa.ncnn.*
import kotlin.math.sqrt
import org.json.JSONObject

private const val TAG = "sherpa-ncnn"

class Sherpa(private val activity: Activity) : EventChannel.StreamHandler {
    private var eventChannel: EventChannel? = null
    private var events: EventChannel.EventSink? = null
    private var meterChannel: EventChannel? = null
    private var meterEvents: EventChannel.EventSink? = null

    // If there is a GPU and useGPU is true, we will use GPU
    // If there is no GPU and useGPU is true, we won't use GPU
    private val useGPU: Boolean = true

    private lateinit var model: SherpaNcnn
    private var audioRecord: AudioRecord? = null
    private var recordingThread: Thread? = null

    private val audioSource = MediaRecorder.AudioSource.MIC
    private val sampleRateInHz = 16000
    private val channelConfig = AudioFormat.CHANNEL_IN_MONO

    // Note: We don't use AudioFormat.ENCODING_PCM_FLOAT
    // since the AudioRecord.read(float[]) needs API level >= 23
    // but we are targeting API level >= 21
    private val audioFormat = AudioFormat.ENCODING_PCM_16BIT
    private var idx: Int = 0
    private var lastText: String = ""
    private var currentLocale: String = "zh-CN" // 默认中文，用于识别单词释义

    @Volatile
    private var isRecording: Boolean = false

    fun initChannel(flutterEngine: FlutterEngine) {
        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "nnbdc/asr_events")
        eventChannel!!.setStreamHandler(this)

        // 音量电平事件通道（用于 Flutter 端绘制波形）
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
        ).setMethodCallHandler {
            // Note: this method is invoked on the main thread.
                call, result ->
            Log.i(TAG, call.method)
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
                    model.reset()
                    result.success(null)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun setLanguage(locale: String) {
        currentLocale = locale
        Log.i(TAG, "Language set to: $locale")
        
        // 当前sherpa模型支持中文识别，用于识别单词释义
        if (locale.startsWith("en")) {
            Log.i(TAG, "English recognition requested, but model is configured for Chinese")
        }
        
        // 如果正在录音，重新启动以应用新语言设置
        if (isRecording && !isAsrStopped) {
            // 重置模型以清除之前的状态
            model.reset()
        }
    }

    // 初始化sherpa（语音识别）- 当前模型配置为中文识别
    fun initModel() {
        val featConfig = getFeatureExtractorConfig(
            sampleRate = 16000.0f,
            featureDim = 80
        )
        //Please change the argument "type" if you use a different model
        val modelConfig = getModelConfig(type = 5, useGPU = useGPU)!!
        val decoderConfig = getDecoderConfig(method = "greedy_search", numActivePaths = 4)

        val config = RecognizerConfig(
            featConfig = featConfig,
            modelConfig = modelConfig,
            decoderConfig = decoderConfig,
            enableEndpoint = true,
            rule1MinTrailingSilence = 2.0f,
            rule2MinTrailingSilence = 0.8f,
            rule3MinUtteranceLength = 20.0f,
        )

        model = SherpaNcnn(
            assetManager = activity.getApplication().assets,
            config = config,
        )
    }


    private fun processSamples() {
        Log.i(TAG, "processing samples")

        val interval = 0.1 // i.e., 100 ms
        val bufferSize = (interval * sampleRateInHz).toInt() // in samples
        val buffer = ShortArray(bufferSize)

        while (isRecording) {
            val ret = audioRecord?.read(buffer, 0, buffer.size)
            if (ret != null && ret > 0) {
                // 计算当前缓冲区的 RMS 音量并归一化到 0..1
                var sumSquares = 0.0
                for (i in 0 until ret) {
                    val s = buffer[i].toDouble()
                    sumSquares += s * s
                }
                val rms = sqrt(sumSquares / ret)
                val norm = (rms / 32768.0).coerceIn(0.0, 1.0)
                // 发送到 Flutter 端的 asr_meter 通道（总是发送电平信息）
                activity.runOnUiThread {
                    meterEvents?.success(norm)
                }

                // 只有在未停止时才进行语音识别
                if (!isAsrStopped) {
                    val samples = FloatArray(ret) { buffer[it] / 32768.0f }
                    model.acceptSamples(samples)
                    while (model.isReady()) {
                        model.decode()
                    }
                    val isEndpoint = model.isEndpoint()
                    val text = model.text

                    if (text.isNotBlank()) {
                        activity.runOnUiThread {
                            // 创建统一的JSON格式候选结果
                            try {
                                val resultData = JSONObject().apply {
                                    put("best", text)
                                    // sherpa模型当前只提供一个结果，所以候选结果数组只包含这一个结果
                                    put("candidates", org.json.JSONArray().apply {
                                        put(text)
                                    })
                                }
                                val jsonString = resultData.toString()
                                events?.success(jsonString)
                                Log.i(TAG, "===== ANDROID: Sending result with candidates to Flutter: '$text' candidates: [$text]")
                            } catch (e: Exception) {
                                // 如果JSON创建失败，回退到发送单个结果
                                Log.e(TAG, "Failed to create JSON result, sending single result: ${e.message}")
                                events?.success(text)
                            }
                        }
                        Log.i(TAG, "===== ANDROID: " + text)
                    }

                    if (isEndpoint) {
                        model.reset()
                    }
                }
            }
        }
    }

    private fun initMicrophone(): Boolean {

        val numBytes = AudioRecord.getMinBufferSize(sampleRateInHz, channelConfig, audioFormat)
        Log.i(
            TAG,
            "buffer size in milliseconds: ${numBytes * 1000.0f / sampleRateInHz}"
        )

        audioRecord = AudioRecord(
            audioSource,
            sampleRateInHz,
            channelConfig,
            audioFormat,
            numBytes * 2 // a sample has two bytes as we are using 16-bit PCM
        )
        return true
    }


    private fun startMicrophone() {
        // 如果已经在录音，先停止旧的
        if (isRecording || audioRecord != null) {
            Log.w(TAG, "Microphone already running, stopping old instance first")
            stopAsr()
        }
        
        val ret = initMicrophone()
        if (!ret) {
            Log.e(TAG, "Failed to initialize microphone")
            return
        }
        Log.i(TAG, "state: ${audioRecord?.state}")
        audioRecord!!.startRecording()
        isRecording = true
        isAsrStopped = false  // 必须在启动线程之前设置
        lastText = ""
        idx = 0

        recordingThread = thread(true) {
            model.reset(true)

            processSamples()
        }
        Log.i(TAG, "Started recording")
    }

    private fun startAsr() {
        isAsrStopped = false
    }

    var isAsrStopped = true

    private fun stopAsr() {
        Log.i(TAG, "Stopping ASR...")
        isRecording = false
        isAsrStopped = true
        
        // 等待录音线程结束
        recordingThread?.join(1000)
        recordingThread = null
        
        // 停止并释放音频资源
        try {
            audioRecord?.stop()
            audioRecord?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping AudioRecord: ${e.message}")
        }
        audioRecord = null
        
        Log.i(TAG, "ASR stopped successfully")
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        this.events = events
    }

    override fun onCancel(arguments: Any?) {
        this.events = null
    }
}
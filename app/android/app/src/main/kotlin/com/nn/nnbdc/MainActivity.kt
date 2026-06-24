package com.nn.nnbdc

import android.os.Bundle
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var asr: Sherpa? = null
    private var tts: Tts? = null
    private var aiInference: AndroidAiInference? = null
    private var ocr: OcrChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // 友盟预初始化 (合规要求)
        com.umeng.commonsdk.UMConfigure.preInit(this, "69b011176f259537c773e1f0", "AppStore")
        
        asr = Sherpa(this)
        tts = Tts(this)
        aiInference = AndroidAiInference(this)
        ocr = OcrChannel(this)
        
        asr?.initModel()
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Ensure components are initialized before use
        val currentAsr = asr ?: Sherpa(this).also { asr = it }
        val currentTts = tts ?: Tts(this).also { tts = it }
        val currentAiInference = aiInference ?: AndroidAiInference(this).also { aiInference = it }
        val currentOcr = ocr ?: OcrChannel(this).also { ocr = it }

        currentAsr.initChannel(flutterEngine)
        currentTts.initChannel(flutterEngine)
        currentAiInference.initChannel(flutterEngine)
        currentOcr.initChannel(flutterEngine)
    }

    override fun onDestroy() {
        super.onDestroy()
        tts?.shutdown()
        aiInference?.cleanup()
    }
}

package com.nn.nnbdc

import android.os.Bundle
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private lateinit var asr: Sherpa
    private lateinit var tts: Tts
    private lateinit var aiInference: AndroidAiInference

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        asr = Sherpa(this)
        tts = Tts(this)
        aiInference = AndroidAiInference(this)
        
        asr.initModel()
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Ensure components are initialized before use
        if (!::asr.isInitialized) asr = Sherpa(this)
        if (!::tts.isInitialized) tts = Tts(this)
        if (!::aiInference.isInitialized) aiInference = AndroidAiInference(this)

        asr.initChannel(flutterEngine)
        tts.initChannel(flutterEngine)
        aiInference.initChannel(flutterEngine)
    }

    override fun onDestroy() {
        super.onDestroy()
        if (::tts.isInitialized) tts.shutdown()
        if (::aiInference.isInitialized) aiInference.cleanup()
    }
}

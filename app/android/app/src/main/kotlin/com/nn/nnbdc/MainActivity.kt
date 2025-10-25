package com.nn.nnbdc

import android.os.Bundle
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var asr: Sherpa = Sherpa(this)

    private var tts: Tts = Tts(this)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        asr.initModel()
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        asr.initChannel(flutterEngine)
        tts.initChannel(flutterEngine)
    }

    override fun onDestroy() {
        super.onDestroy()
        tts.shutdown()
    }
}

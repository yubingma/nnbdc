package com.nn.nnbdc

import android.app.Activity
import android.content.Context
import android.os.Bundle
import android.os.Build
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.*

class Tts(private val activity: Activity) : EventChannel.StreamHandler {
    private lateinit var eventChannel: EventChannel
    private var events: EventChannel.EventSink? = null
    private lateinit var ttobj: TextToSpeech

    fun initChannel(flutterEngine: FlutterEngine) {
        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "nnbdc/tts_events")
        eventChannel.setStreamHandler(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nnbdc/tts_commands").setMethodCallHandler { call, result ->
            if (call.method == "speak") {
                speak(call.argument("text") ?: "", call.argument("utteranceId") ?: "")
                result.success(null)
            } else if (call.method == "stop") {
                stop()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        this.events = events

        ttobj = TextToSpeech(activity) { status ->
            if (status == TextToSpeech.SUCCESS) {
                ttobj.language = Locale.CHINA
            }

            activity.runOnUiThread {
                val event: MutableMap<String, Any> = HashMap()
                event["type"] = "initStatus"
                event["data"] = status
                events.success(event)
            }
        }
        
        // 不同Android版本使用不同的监听器API
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            ttobj.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String) {}
                
                override fun onDone(utteranceId: String) {
                    val event: MutableMap<String, Any> = HashMap()
                    event["type"] = "ttsCompleted"
                    event["data"] = utteranceId
                    activity.runOnUiThread { events.success(event) }
                }
                
                override fun onError(utteranceId: String) {}
            })
        } else {
            @Suppress("DEPRECATION")
            ttobj.setOnUtteranceCompletedListener { utteranceId ->
                val event: MutableMap<String, Any> = HashMap()
                event["type"] = "ttsCompleted"
                event["data"] = utteranceId
                activity.runOnUiThread { events.success(event) }
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        this.events = null
    }

    fun speak(text: String, utteranceId: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val params = Bundle()
            ttobj.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
        } else {
            @Suppress("DEPRECATION")
            val params = HashMap<String, String>()
            params[TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID] = utteranceId
            ttobj.speak(text, TextToSpeech.QUEUE_FLUSH, params)
        }
    }

    fun stop() {
        ttobj.stop()
    }

    fun shutdown() {
        ttobj.shutdown()
    }
} 
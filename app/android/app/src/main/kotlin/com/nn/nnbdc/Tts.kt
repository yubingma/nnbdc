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
                val text = call.argument<String>("text") ?: ""
                val utteranceId = call.argument<String>("utteranceId") ?: ""
                val language = call.argument<String>("language") ?: "en-US"
                speak(text, utteranceId, language)
                result.success(null)
            } else if (call.method == "stop") {
                stop()
                result.success(null)
            } else if (call.method == "checkLanguageSupport") {
                val language = call.argument<String>("language") ?: "en-US"
                val locale = when (language) {
                    "zh-CN" -> Locale.CHINA
                    "en-US" -> Locale.US
                    else -> Locale.US
                }
                if (::ttobj.isInitialized) {
                    val resultVal = ttobj.isLanguageAvailable(locale)
                    val supported = resultVal >= TextToSpeech.LANG_AVAILABLE
                    result.success(supported)
                } else {
                    result.error("NOT_INITIALIZED", "TTS not initialized", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        this.events = events

        ttobj = TextToSpeech(activity) { status ->
            if (status == TextToSpeech.SUCCESS) {
                // Initialize with a default language, but it will be overridden in speak()
                val result = ttobj.setLanguage(Locale.US)
                if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                    Log.e("TTS", "Language is not supported or missing data")
                }
            } else {
                Log.e("TTS", "Initialization failed with status: $status")
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
                override fun onStart(utteranceId: String) {
                    Log.d("TTS", "onStart: $utteranceId")
                }
                
                override fun onDone(utteranceId: String) {
                    Log.d("TTS", "onDone: $utteranceId")
                    val event: MutableMap<String, Any> = HashMap()
                    event["type"] = "ttsCompleted"
                    event["data"] = utteranceId
                    activity.runOnUiThread { events?.success(event) }
                }
                
                override fun onError(utteranceId: String) {
                    Log.e("TTS", "onError: $utteranceId")
                    val event: MutableMap<String, Any> = HashMap()
                    event["type"] = "ttsCompleted"
                    event["data"] = utteranceId
                    activity.runOnUiThread { events?.success(event) }
                }
            })
        } else {
            @Suppress("DEPRECATION")
            ttobj.setOnUtteranceCompletedListener { utteranceId ->
                Log.d("TTS", "onUtteranceCompleted: $utteranceId")
                val event: MutableMap<String, Any> = HashMap()
                event["type"] = "ttsCompleted"
                event["data"] = utteranceId
                activity.runOnUiThread { events?.success(event) }
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        this.events = null
    }

    fun speak(text: String, utteranceId: String, language: String) {
        if (!::ttobj.isInitialized) {
            Log.e("TTS", "ttobj not initialized")
            return
        }

        // Set language based on the argument from Flutter
        // Use Locale.CHINA for zh-CN to be more specific (zh_CN), which is usually what's needed for mainland China.
        val locale = when (language) {
            "zh-CN" -> Locale.CHINA
            "en-US" -> Locale.US
            else -> Locale.US
        }
        
        Log.d("TTS", "Setting language to $locale for text: $text")
        val result = ttobj.setLanguage(locale)
        if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
            Log.e("TTS", "Language $language is not supported or missing data (result code: $result)")
            // Even if language is not supported, we should still try to speak or signal completion
            // so that the Flutter side doesn't hang for 10 seconds.
            val event: MutableMap<String, Any> = HashMap()
            event["type"] = "ttsCompleted"
            event["data"] = utteranceId
            activity.runOnUiThread { events?.success(event) }
            return
        }

        Log.d("TTS", "Speaking ($language): $text")

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
        if (::ttobj.isInitialized) {
            ttobj.stop()
        }
    }

    fun shutdown() {
        if (::ttobj.isInitialized) {
            ttobj.shutdown()
        }
    }
} 
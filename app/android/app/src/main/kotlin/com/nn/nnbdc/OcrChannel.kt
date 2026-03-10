package com.nn.nnbdc

import android.content.Context
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Android 平台 OCR 识别通道，使用 Google ML Kit
 */
class OcrChannel(private val context: Context) {

    fun initChannel(flutterEngine: FlutterEngine) {
        val methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "nnbdc/ocr"
        )

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "recognizeText" -> {
                    val imagePath = call.argument<String>("imagePath")
                    if (imagePath != null) {
                        recognizeText(imagePath, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "Missing imagePath parameter", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun recognizeText(imagePath: String, result: MethodChannel.Result) {
        try {
            val file = File(imagePath)
            if (!file.exists()) {
                result.error("INVALID_IMAGE", "文件不存在: $imagePath", null)
                return
            }

            val image = InputImage.fromFilePath(context, Uri.fromFile(file))
            val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

            recognizer.process(image)
                .addOnSuccessListener { visionText ->
                    // 提取所有识别到的文字，用换行符连接
                    val recognizedText = visionText.text
                    result.success(recognizedText)
                }
                .addOnFailureListener { e ->
                    result.error("OCR_ERROR", "文字识别失败: ${e.message}", null)
                }
        } catch (e: Exception) {
            result.error("OCR_ERROR", "执行识别失败: ${e.message}", null)
        }
    }
}

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

            // 1. 先通过系统解码成 Bitmap，确保图片格式 100% 被识别
            val bitmap = android.graphics.BitmapFactory.decodeFile(imagePath)
            if (bitmap == null) {
                result.error("DECODE_ERROR", "图片解码失败", null)
                return
            }
            
            // 2. 从 Bitmap 创建 InputImage
            val image = InputImage.fromBitmap(bitmap, 0)
            val options = TextRecognizerOptions.Builder()
                .build() // 默认拉丁文识别器
            val recognizer = TextRecognition.getClient(options)

            recognizer.process(image)
                .addOnSuccessListener { visionText ->
                    result.success(visionText.text)
                }
                .addOnFailureListener { e ->
                    result.error("OCR_ERROR", "文字识别失败: ${e.message}", null)
                }
        } catch (e: Exception) {
            result.error("OCR_ERROR", "执行识别失败: ${e.message}", null)
        }
    }
}

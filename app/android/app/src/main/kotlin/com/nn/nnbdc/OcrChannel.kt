package com.nn.nnbdc

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.digitalink.*
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
                "recognizeHandwriting" -> {
                    val strokes = call.argument<List<List<Map<String, Double>>>>("strokes")
                    if (strokes != null) {
                        recognizeHandwriting(strokes, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "Missing strokes parameter", null)
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
            // 强制转换为 ARGB_8888 并填充白色背景，防止透明 PNG 被识别为黑色
            val whiteBitmap = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
            val canvas = android.graphics.Canvas(whiteBitmap)
            canvas.drawColor(android.graphics.Color.WHITE)
            canvas.drawBitmap(bitmap, 0f, 0f, null)

            val image = InputImage.fromBitmap(whiteBitmap, 0)
            val options = TextRecognizerOptions.Builder().build()
            val recognizer = TextRecognition.getClient(options)

            recognizer.process(image)
                .addOnSuccessListener { visionText ->
                    val pixel = whiteBitmap.getPixel(whiteBitmap.width / 2, whiteBitmap.height / 2)
                    val info = "[Native ${whiteBitmap.width}x${whiteBitmap.height} Px:${Integer.toHexString(pixel)}]"
                    // 使用 ||| 作为分隔符，方便 Flutter 端拆分诊断信息
                    result.success("${visionText.text} ||| $info")
                }
                .addOnFailureListener { e ->
                    result.error("OCR_ERROR", "文字识别失败: ${e.message}", null)
                }
        } catch (e: Exception) {
            result.error("OCR_ERROR", "执行识别失败: ${e.message}", null)
        }
    }

    private fun recognizeHandwriting(strokesData: List<List<Map<String, Double>>>, result: MethodChannel.Result) {
        val inkBuilder = Ink.builder()
        for (strokeData in strokesData) {
            val strokeBuilder = Ink.Stroke.builder()
            for (pointData in strokeData) {
                val x = pointData["x"]?.toFloat() ?: 0f
                val y = pointData["y"]?.toFloat() ?: 0f
                strokeBuilder.addPoint(Ink.Point.create(x, y))
            }
            inkBuilder.addStroke(strokeBuilder.build())
        }
        val ink = inkBuilder.build()

        val modelIdentifier = DigitalInkRecognitionModelIdentifier.fromLanguageTag("en-US")
        if (modelIdentifier == null) {
            result.error("MODEL_ERROR", "无法识别语言模型: en-US", null)
            return
        }
        
        val model = DigitalInkRecognitionModel.builder(modelIdentifier).build()
        val remoteModelManager = RemoteModelManager.getInstance()

        // 检查模型是否已下载
        remoteModelManager.isModelDownloaded(model)
            .addOnSuccessListener { isDownloaded ->
                if (isDownloaded) {
                    performRecognition(ink, model, result)
                } else {
                    // 如果没下载，则开始下载（建议提示用户，由于是后台逻辑这里直接触发）
                    remoteModelManager.download(model, DownloadConditions.Builder().build())
                        .addOnSuccessListener {
                            performRecognition(ink, model, result)
                        }
                        .addOnFailureListener { e ->
                            result.error("MODEL_DOWNLOAD_ERROR", "语言模型下载失败: ${e.message}", null)
                        }
                }
            }
    }

    private fun performRecognition(ink: Ink, model: DigitalInkRecognitionModel, result: MethodChannel.Result) {
        val recognizer = DigitalInkRecognition.getClient(
            DigitalInkRecognizerOptions.builder(model).build()
        )
        recognizer.recognize(ink)
            .addOnSuccessListener { recognitionResult ->
                if (recognitionResult.candidates.isNotEmpty()) {
                    // 返回置信度最高的候选结果
                    result.success(recognitionResult.candidates[0].text)
                } else {
                    result.success("")
                }
            }
            .addOnFailureListener { e ->
                result.error("RECOGNITION_ERROR", "识别失败: ${e.message}", null)
            }
    }
}

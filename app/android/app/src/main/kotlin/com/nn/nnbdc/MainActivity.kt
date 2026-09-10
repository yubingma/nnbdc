package com.nn.nnbdc

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var asr: Sherpa? = null
    private var tts: Tts? = null
    private var aiInference: AndroidAiInference? = null
    private var ocr: OcrChannel? = null

    /** 外部应用传入、尚未交给 Flutter 的 Excel URI（冷启动场景）。 */
    private var pendingImportUri: Uri? = null
    private var externalFileChannel: MethodChannel? = null

    /** Dart 侧是否已就绪；未就绪时先缓存 URI，避免冷启动时推送丢失。 */
    private var externalFileReady = false
    private val fileCopyExecutor = Executors.newSingleThreadExecutor()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // 友盟预初始化 (合规要求)
        com.umeng.commonsdk.UMConfigure.preInit(this, "69b011176f259537c773e1f0", "AppStore")
        
        asr = Sherpa(this)
        tts = Tts(this)
        aiInference = AndroidAiInference(this)
        ocr = OcrChannel(this)

        // 冷启动时就带着文件进入的情况
        pendingImportUri = extractImportUri(intent)
        
        asr?.initModel()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val uri = extractImportUri(intent) ?: return
        val channel = externalFileChannel
        if (channel == null || !externalFileReady) {
            // Flutter 侧尚未就绪，留给 getInitialFile 取走
            pendingImportUri = uri
            return
        }
        fileCopyExecutor.execute {
            val payload = copyToCache(uri)
            if (payload != null) {
                runOnUiThread { channel.invokeMethod("onFileReceived", payload) }
            }
        }
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

        setupExternalFileChannel(flutterEngine)
    }

    /**
     * 外部文件通道。
     *
     * 外部 content:// URI 无法直接交给 Dart 读取（分区存储 + 无持久授权），
     * 因此统一复制到应用私有缓存后，再把路径交给 Flutter。
     */
    private fun setupExternalFileChannel(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nnbdc/external_file")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialFile" -> {
                    externalFileReady = true
                    val uri = pendingImportUri
                    pendingImportUri = null
                    if (uri == null) {
                        result.success(null)
                    } else {
                        fileCopyExecutor.execute {
                            val payload = copyToCache(uri)
                            runOnUiThread { result.success(payload) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        externalFileChannel = channel
    }

    /** 取出 ACTION_VIEW / ACTION_SEND 携带的文件 URI。 */
    private fun extractImportUri(intent: Intent?): Uri? {
        if (intent == null) return null
        return when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND ->
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
            else -> null
        }
    }

    private fun copyToCache(uri: Uri): Map<String, String>? {
        return try {
            val displayName = queryDisplayName(uri) ?: "import_${System.currentTimeMillis()}.xlsx"
            val safeName = displayName.replace(Regex("[^A-Za-z0-9._\\-\\u4e00-\\u9fff]"), "_")
            val target = File(cacheDir, "${System.currentTimeMillis()}_$safeName")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(target).use { output -> input.copyTo(output) }
            } ?: return null
            mapOf("name" to displayName, "path" to target.absolutePath)
        } catch (e: Exception) {
            null
        }
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0 && cursor.moveToFirst()) cursor.getString(index) else null
            }
        } catch (e: Exception) {
            null
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        fileCopyExecutor.shutdown()
        tts?.shutdown()
        aiInference?.cleanup()
        asr?.release()
    }
}

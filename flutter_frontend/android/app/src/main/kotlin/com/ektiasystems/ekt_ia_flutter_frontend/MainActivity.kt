package com.ektiasystems.ekt_ia_flutter_frontend

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

class MainActivity : FlutterActivity() {
    private val channelName = "com.ektiasystems/shared_statement"
    private var channel: MethodChannel? = null
    private var pendingShare: Map<String, String>? = null
    private val textRecognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialShare" -> {
                    result.success(pendingShare)
                    pendingShare = null
                }
                else -> result.notImplemented()
            }
        }
        receiveShare(intent, notifyFlutter = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receiveShare(intent, notifyFlutter = true)
    }

    private fun receiveShare(intent: Intent?, notifyFlutter: Boolean) {
        if (intent?.action != Intent.ACTION_SEND) return
        val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: return
        val payload = readPayload(uri) ?: return
        if (payload["mimeType"]?.startsWith("image/") == true) {
            try {
                textRecognizer.process(InputImage.fromFilePath(this, uri))
                    .addOnSuccessListener { result ->
                        deliver(payload + ("extractedText" to result.text), true)
                    }
                    .addOnFailureListener { deliver(payload, true) }
            } catch (_: Exception) {
                deliver(payload, true)
            }
            return
        }
        deliver(payload, notifyFlutter)
    }

    private fun deliver(payload: Map<String, String>, notifyFlutter: Boolean) {
        if (notifyFlutter) {
            channel?.invokeMethod("sharedFile", payload)
        } else {
            pendingShare = payload
        }
    }

    private fun readPayload(uri: Uri): Map<String, String>? = try {
        val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return null
        val mimeType = contentResolver.getType(uri) ?: "application/octet-stream"
        var filename = "comprovante"
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) filename = cursor.getString(0) ?: filename
        }
        if (!filename.contains('.')) {
            filename += when (mimeType) {
                "application/pdf" -> ".pdf"
                "image/png" -> ".png"
                else -> ".jpg"
            }
        }
        mapOf(
            "name" to filename,
            "mimeType" to mimeType,
            "contentBase64" to Base64.encodeToString(bytes, Base64.NO_WRAP),
        )
    } catch (_: Exception) {
        null
    }

    override fun onDestroy() {
        textRecognizer.close()
        super.onDestroy()
    }
}

package com.ektiasystems.ekt_ia_flutter_frontend

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "com.ektiasystems/shared_statement"
    private var channel: MethodChannel? = null
    private var pendingShare: Map<String, String>? = null
    private val textRecognizer by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    private val vault by lazy { LocalVault(this) }
    private val io = java.util.concurrent.Executors.newSingleThreadExecutor()
    private var preparing = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialShare" -> { result.success(pendingShare); prepareHead() }
                "acknowledgeShare" -> {
                    val id = call.argument<String>("shareId")
                    if (id == null || id != pendingShare?.get("shareId")) {
                        result.error("share_mismatch", "Comprovante não confirmado.", null)
                    } else {
                        io.execute {
                            try {
                                vault.delete(id)
                                runOnUiThread {
                                    if (intent?.getStringExtra("ekt.shareId") == id) {
                                        setIntent(Intent(this, MainActivity::class.java).setAction(Intent.ACTION_MAIN))
                                    }
                                    pendingShare = null
                                    result.success(null)
                                    prepareHead()
                                }
                            } catch (_: Exception) {
                                runOnUiThread { result.error("storage", "Não foi possível confirmar o envio local.", null) }
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.ektiasystems/session")
            .setMethodCallHandler { call, result ->
                io.execute {
                    try {
                        val response = when (call.method) {
                            "read" -> vault.read("session")
                            "write" -> { vault.write("session", call.arguments as String); null }
                            "clear" -> { vault.delete("session"); null }
                            else -> throw IllegalArgumentException("Unknown method")
                        }
                        runOnUiThread { result.success(response) }
                    } catch (_: Exception) {
                        runOnUiThread { result.error("storage", "Não foi possível acessar a sessão protegida.", null) }
                    }
                }
            }
        receiveShare(intent)
        prepareHead()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receiveShare(intent)
    }

    private fun receiveShare(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: return
        val id = intent.getStringExtra("ekt.shareId") ?: "receipt_${System.currentTimeMillis()}_${java.util.UUID.randomUUID()}"
        intent.putExtra("ekt.shareId", id)
        io.execute {
            try {
                if (vault.read(id) == null) {
                    val payload = readPayload(uri) ?: throw IllegalArgumentException("Arquivo ilegível")
                    vault.write(id, org.json.JSONObject(payload + ("shareId" to id)).toString())
                }
                runOnUiThread { prepareHead() }
            } catch (_: Exception) {
                runOnUiThread { android.widget.Toast.makeText(this,
                    "Não foi possível guardar o comprovante. Salve o arquivo e compartilhe novamente (máximo 15 MB).",
                    android.widget.Toast.LENGTH_LONG).show() }
            }
        }
    }

    private fun prepareHead() {
        if (preparing || pendingShare != null || isDestroyed) return
        preparing = true
        io.execute {
            try {
                val id = vault.receipts().firstOrNull()
                val json = id?.let { vault.read(it) }?.let { org.json.JSONObject(it) }
                val payload = json?.keys()?.asSequence()?.associateWith { json.getString(it) }
                runOnUiThread {
                    if (payload == null) { preparing = false; return@runOnUiThread }
                    if (payload["mimeType"]?.startsWith("image/") == true && payload["ocrDone"] != "1") {
                        try {
                            val bytes = Base64.decode(payload["contentBase64"], Base64.NO_WRAP)
                            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                                ?: throw IllegalArgumentException("Imagem inválida")
                            textRecognizer.process(InputImage.fromBitmap(bitmap, 0))
                                .addOnSuccessListener { result ->
                                    bitmap.recycle()
                                    deliver(payload + mapOf("extractedText" to result.text, "ocrDone" to "1"))
                                }
                                .addOnFailureListener { bitmap.recycle(); deliver(payload + ("ocrDone" to "1")) }
                        } catch (_: Exception) { deliver(payload + ("ocrDone" to "1")) }
                    } else { deliver(payload) }
                }
            } catch (_: Exception) {
                runOnUiThread {
                    preparing = false
                    android.widget.Toast.makeText(this, "Não foi possível recuperar o comprovante guardado.",
                        android.widget.Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    private fun deliver(payload: Map<String, String>) {
        io.execute {
            try {
                vault.write(payload.getValue("shareId"), org.json.JSONObject(payload).toString())
                runOnUiThread {
                    preparing = false
                    if (!isDestroyed) {
                        pendingShare = payload
                        channel?.invokeMethod("sharedFile", payload)
                    }
                }
            } catch (_: Exception) { runOnUiThread { preparing = false } }
        }
    }

    private fun readPayload(uri: Uri): Map<String, String>? {
        return try {
        var bytes = contentResolver.openInputStream(uri)?.use { stream ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            var count = stream.read(buffer)
            while (count != -1) {
                if (output.size() + count > 15 * 1024 * 1024) return null
                output.write(buffer, 0, count)
                count = stream.read(buffer)
            }
            output.toByteArray()
         } ?: return null
        if (bytes.size > 15 * 1024 * 1024) return null
        var mimeType = contentResolver.getType(uri) ?: "application/octet-stream"
        var filename = "comprovante"
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) filename = cursor.getString(0) ?: filename
        }
        if (mimeType.startsWith("image/")) {
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            if (bitmap != null) {
                val output = ByteArrayOutputStream()
                if (bitmap.compress(Bitmap.CompressFormat.JPEG, 94, output)) {
                    bytes = output.toByteArray()
                    mimeType = "image/jpeg"
                    filename = filename.substringBeforeLast('.', filename) + ".jpg"
                }
                bitmap.recycle()
            }
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

    }

    override fun onDestroy() {
        textRecognizer.close()
        super.onDestroy()
    }
}

package com.ektiasystems.ekt_ia_flutter_frontend

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Private, encrypted, excluded from backups; no password is stored. */
class LocalVault(context: Context) {
    private val directory = File(context.noBackupFilesDir, "ekt-vault").apply { mkdirs() }
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        return (store.getKey("ekt-local-v1", null) as? SecretKey) ?: KeyGenerator
            .getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
                init(KeyGenParameterSpec.Builder("ekt-local-v1",
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
            }.generateKey()
    }
    private fun file(name: String): AtomicFile {
        require(Regex("[a-zA-Z0-9_-]+").matches(name))
        return AtomicFile(File(directory, name))
    }
    @Synchronized fun write(name: String, value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD(name.toByteArray(Charsets.UTF_8))
        val data = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val target = file(name)
        val stream = target.startWrite()
        try { stream.write(data); target.finishWrite(stream) }
        catch (error: Exception) { target.failWrite(stream); throw error }
    }
    @Synchronized fun read(name: String): String? {
        val target = file(name)
        if (!target.baseFile.exists()) return null
        val data = target.readFully()
        require(data.size > 12)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, data.copyOfRange(0, 12)))
        cipher.updateAAD(name.toByteArray(Charsets.UTF_8))
        return String(cipher.doFinal(data.copyOfRange(12, data.size)), Charsets.UTF_8)
    }
    @Synchronized fun delete(name: String) = file(name).delete()
    @Synchronized fun receipts(): List<String> = directory.listFiles()
        ?.filter { it.name.startsWith("receipt_") && !it.name.contains('.') }
        ?.sortedBy { it.name }?.map { it.name } ?: emptyList()
}

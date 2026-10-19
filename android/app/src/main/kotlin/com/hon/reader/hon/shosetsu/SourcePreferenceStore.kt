package com.hon.reader.hon.shosetsu

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** All source settings are encrypted, including credentials unknown to the UI. */
object SourcePreferenceStore {
    private const val alias = "hon_source_settings_v1"
    @Synchronized private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    private fun prefs(context: Context) = context.getSharedPreferences("hon_source_settings_encrypted", Context.MODE_PRIVATE)
    @Synchronized fun read(context: Context, source: String): JSONObject {
        val encrypted = prefs(context).getString(source, null)
        if (encrypted != null) {
            val bytes = Base64.decode(encrypted, Base64.NO_WRAP)
            require(bytes.size >= 28) { "Source preferences are damaged" }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
            cipher.updateAAD(source.toByteArray(Charsets.UTF_8))
            return JSONObject(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
        }
        val legacy = context.getSharedPreferences("hon_source_preferences", Context.MODE_PRIVATE)
        val raw = legacy.getString(source, null) ?: return JSONObject()
        val value = JSONObject(raw)
        write(context, source, value)
        // The old copy is removed only after encrypted persistence succeeds.
        legacy.edit().remove(source).commit()
        return value
    }
    @Synchronized fun write(context: Context, source: String, value: JSONObject) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD(source.toByteArray(Charsets.UTF_8))
        val encrypted = Base64.encodeToString(cipher.iv + cipher.doFinal(value.toString().toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
        check(prefs(context).edit().putString(source, encrypted).commit()) { "Could not save source preferences" }
        context.getSharedPreferences("hon_source_preferences", Context.MODE_PRIVATE).edit().remove(source).commit()
    }
}

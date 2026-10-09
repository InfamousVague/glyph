package com.mattssoftware.ghost_md

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * What makes this phone a signed-in device, kept where only this app on this phone can read it
 * (lib/account/device_keys.dart `ChannelSecureStore`): the session, the account key, this device's signing key and
 * the account's key pair, each a small string.
 *
 * Each value is encrypted with AES-256-GCM under one key that is made in the Android Keystore and never leaves it
 * (hardware-backed where the phone has the hardware), with the value's own name as the associated data, so a file
 * renamed to another's name does not open. A file is `iv (12 bytes) ‖ ciphertext and tag`, written beside itself
 * and renamed, in `noBackupFilesDir/secure/`: Android leaves that folder out of every backup and every move to a
 * new phone, where the Keystore's key would not be there to open it anyway.
 *
 * Nothing here throws to Dart for a value it cannot read: a key the Keystore has lost, a file cut short or written
 * under another key reads as none, and the file is removed. A device that cannot remember is signed out, not
 * broken. A value that cannot be WRITTEN is an error, which Dart holds in memory for as long as the app is open.
 *
 * The key asks for no unlock and no fingerprint: sync runs with the screen off. The work is done off the main
 * thread (a Keystore call can take tens of milliseconds) and answered on it.
 */
class SecureStore(context: Context) {
    private val folder = File(context.noBackupFilesDir, "secure")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** The channel Dart asks through: `read {name}`, `write {name, value}`, `delete {name}`. */
    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            val name = call.argument<String>("name")
            if (name == null || !NAME.matches(name)) {
                result.error("name", "That is not a name the secure store keeps.", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "read" -> answer(result) { read(name) }
                "write" -> {
                    val value = call.argument<String>("value")
                    if (value == null) result.error("value", "There is nothing to keep.", null)
                    else answer(result) { write(name, value); null }
                }
                "delete" -> answer(result) { delete(name); null }
                else -> result.notImplemented()
            }
        }
    }

    private fun answer(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (failure: Exception) {
                main.post { result.error("secure_store", failure.message ?: "The secure store failed.", null) }
            }
        }
    }

    private fun fileOf(name: String) = File(folder, name)

    /** The one key, made the first time it is asked for. */
    private fun key(): SecretKey {
        val keystore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (keystore.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val spec = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE).run {
            init(spec)
            generateKey()
        }
    }

    /** The value kept under `name`, or null: none, or one that no longer opens (and is then removed). */
    fun read(name: String): String? {
        val file = fileOf(name)
        if (!file.isFile) return null
        return try {
            val bytes = file.readBytes()
            if (bytes.size <= IV) throw IllegalStateException("cut short")
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, bytes, 0, IV))
            cipher.updateAAD(name.toByteArray(Charsets.UTF_8))
            String(cipher.doFinal(bytes, IV, bytes.size - IV), Charsets.UTF_8)
        } catch (failure: Exception) {
            file.delete()
            null
        }
    }

    /** Keeps `value` under `name`: whole, or not at all. */
    fun write(name: String, value: String) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        // The Keystore draws the IV itself, fresh for every write.
        cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD(name.toByteArray(Charsets.UTF_8))
        val sealed = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val iv = cipher.iv
        if (iv.size != IV) throw IllegalStateException("The Keystore gave an IV of ${iv.size} bytes.")
        folder.mkdirs()
        val beside = File(folder, "$name.new")
        beside.outputStream().use { out ->
            out.write(iv)
            out.write(sealed)
            out.fd.sync()
        }
        if (!beside.renameTo(fileOf(name))) {
            beside.delete()
            throw IllegalStateException("The value could not be put in place.")
        }
    }

    fun delete(name: String) {
        fileOf(name).delete()
    }

    /**
     * Every value gone, whatever its name: a reset's (ResetChannel.kt). Done on the store's own worker, behind any
     * write already asked for, and `done` hears on the main thread whether every file went. The Keystore's key
     * stays: it opens nothing once the files are gone, and the next value is sealed under it.
     */
    fun clear(done: (Boolean) -> Unit) {
        worker.execute {
            val left = (folder.listFiles() ?: emptyArray()).count { !it.delete() }
            main.post { done(left == 0) }
        }
    }

    companion object {
        const val CHANNEL = "ghost_md/secure_store"
        private const val KEYSTORE = "AndroidKeyStore"
        private const val ALIAS = "ghost_md.secure_store.v1"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV = 12
        private const val TAG_BITS = 128

        /**
         * A name is a file's: letters, digits, `-` and `_`, nothing that could leave the folder; and `:`, which a
         * plugin's secrets are named with where one name is the prefix of several (`glyph-slack-webhook:<id>`,
         * lib/plugins/slack/manifest.dart), and which is an ordinary character in a file's name here.
         */
        private val NAME = Regex("^[A-Za-z0-9_:-]{1,64}$")
    }
}

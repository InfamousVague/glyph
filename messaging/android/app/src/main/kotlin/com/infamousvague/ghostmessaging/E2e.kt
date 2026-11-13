package com.infamousvague.ghostmessaging

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import org.json.JSONObject
import java.security.KeyStore
import java.security.PrivateKey
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Ghost Messaging's own encryption between two phones that both run it: this phone's key, the keys other people
 * sent, and where each conversation stands. The cryptography is [E2eCrypto]'s; this is what Android keeps.
 *
 * A conversation with one person is in one of four states:
 * - none: nothing exchanged.
 * - offered: this phone sent its key and waits for theirs.
 * - pending: they sent a key and the person here has not said yes. Also where a conversation goes back to when a
 *   DIFFERENT key arrives from someone already exchanged with (`changed`): nothing is encrypted to a new key until
 *   the person accepts it, since a new key is what someone in the middle would send too.
 * - on: both keys held. Every text to that person goes out sealed, and theirs are opened.
 *
 * Sealed texts are kept sealed in Android's SMS database, which other apps with SMS access can read, and opened as
 * they are shown ([read]). This phone's private key is kept encrypted under a key in the Android Keystore, which
 * never leaves the phone's secure hardware.
 *
 * One person at a time: a group conversation and a picture message are MMS and go as they always have.
 */
object E2e {
    private const val TAG = "GhostMessaging"
    private const val PREFS = "e2e"
    private const val WRAP_ALIAS = "ghost_e2e_wrap"
    const val KEY_NOTE = "Ghost Messaging encryption key. With the app (ghost-sms.com) our texts can be end-to-end encrypted."

    private fun prefs(context: Context) = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** A person's number as conversations are told apart by it: its last ten digits, or the address in lower case. */
    fun norm(address: String): String {
        val digits = address.filter { it.isDigit() }
        return if (digits.length >= 7) digits.takeLast(10) else address.trim().lowercase()
    }

    // --- this phone's key --------------------------------------------------------------------------------------------

    private fun wrapKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(WRAP_ALIAS, null) as SecretKey?)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(WRAP_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build())
        }.generateKey()
    }

    @Volatile private var identity: Pair<PrivateKey, ByteArray>? = null
    private val sessions = HashMap<String, ByteArray>()

    /** This phone's key pair, made the first time it is asked for. */
    @Synchronized
    private fun identity(context: Context): Pair<PrivateKey, ByteArray> {
        identity?.let { return it }
        val p = prefs(context)
        val stored = p.getString("identity", null)
        val pub = p.getString("identity_pub", null)
        if (stored != null && pub != null) {
            try {
                val raw = Base64.getDecoder().decode(stored)
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.DECRYPT_MODE, wrapKey(), GCMParameterSpec(128, raw, 0, 12))
                val pair = E2eCrypto.privateFrom(cipher.doFinal(raw, 12, raw.size - 12)) to Base64.getDecoder().decode(pub)
                identity = pair
                return pair
            } catch (e: Exception) { Log.e(TAG, "e2e identity unreadable; a new one is made", e) }
        }
        val pair = E2eCrypto.newKeyPair()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, wrapKey())
        val sealed = cipher.iv + cipher.doFinal(pair.private.encoded)
        val public = E2eCrypto.publicBytes(pair.public)
        p.edit().putString("identity", Base64.getEncoder().encodeToString(sealed)).putString("identity_pub", Base64.getEncoder().encodeToString(public)).apply()
        return (pair.private to public).also { identity = it }
    }

    fun hasIdentity(context: Context) = prefs(context).contains("identity")

    fun myFingerprint(context: Context): String = E2eCrypto.fingerprint(identity(context).second)

    // --- the people ----------------------------------------------------------------------------------------------------

    private fun peer(context: Context, address: String): JSONObject? =
        prefs(context).getString("peer:${norm(address)}", null)?.let { runCatching { JSONObject(it) }.getOrNull() }

    private fun save(context: Context, address: String, o: JSONObject) {
        prefs(context).edit().putString("peer:${norm(address)}", o.toString()).apply()
        synchronized(sessions) { sessions.remove(norm(address)) }
    }

    fun isOn(context: Context, address: String): Boolean = peer(context, address)?.optString("state") == "on"

    /** Whether a key of [address]'s is here: they have the app, whatever was done about the key. */
    fun hasTheirKey(context: Context, address: String): Boolean = peer(context, address)?.optString("pub", "")?.isNotEmpty() == true

    /** Where the conversation with [address] stands, for the screen. */
    fun state(context: Context, address: String): Map<String, Any?> {
        val o = peer(context, address)
        val state = o?.optString("state", "none") ?: "none"
        val pub = o?.optString("pub", "")?.takeIf { it.isNotEmpty() }?.let { Base64.getDecoder().decode(it) }
        return mapOf(
            "address" to (o?.optString("address", address) ?: address),
            "state" to state,
            "verified" to (o?.optBoolean("verified", false) ?: false),
            "changed" to (o?.optBoolean("changed", false) ?: false),
            "safety" to (if (pub != null && hasIdentity(context)) E2eCrypto.safetyNumber(identity(context).second, pub) else null),
            "theirKey" to pub?.let { E2eCrypto.fingerprint(it) },
        )
    }

    fun list(context: Context): List<Map<String, Any?>> =
        prefs(context).all.keys.filter { it.startsWith("peer:") }.mapNotNull { k ->
            val o = runCatching { JSONObject(prefs(context).getString(k, "") ?: "") }.getOrNull() ?: return@mapNotNull null
            state(context, o.optString("address", k.removePrefix("peer:")))
        }.filter { it["state"] != "none" }

    /** The text that carries this phone's key. */
    fun keyMessage(context: Context): String = KEY_NOTE + "\n" + E2eCrypto.keyText(identity(context).second)

    /**
     * This phone sends its key to [address] (the caller sends [keyMessage]): turning encryption on where their key is
     * already here, waiting for it where it is not.
     */
    fun offered(context: Context, address: String) {
        val o = peer(context, address) ?: JSONObject()
        o.put("address", address)
        o.put("sent", true)
        o.put("changed", false)
        o.put("state", if (o.optString("pub", "").isNotEmpty()) "on" else "offered")
        save(context, address, o)
    }

    /** A key arrived from [address]. Returns true when the conversation is now on. */
    fun received(context: Context, address: String, publicKey: ByteArray): Boolean {
        val o = peer(context, address) ?: JSONObject()
        val b64 = Base64.getEncoder().encodeToString(publicKey)
        val before = o.optString("pub", "")
        o.put("address", address)
        if (before == b64) {
            // The key already held, sent again: nothing changes but that a conversation waiting for it is on.
            if (o.optString("state") == "offered") o.put("state", "on")
        } else if (before.isNotEmpty()) {
            // A different key from someone already exchanged with: back to asking, and no longer verified.
            o.put("pub", b64); o.put("state", "pending"); o.put("changed", true); o.put("verified", false); o.put("sent", false)
        } else {
            o.put("pub", b64)
            o.put("state", if (o.optBoolean("sent", false)) "on" else "pending")
        }
        save(context, address, o)
        return o.optString("state") == "on"
    }

    fun setVerified(context: Context, address: String, verified: Boolean) {
        val o = peer(context, address) ?: return
        o.put("verified", verified)
        save(context, address, o)
    }

    /** Encryption off with [address]: their key is let go, and texts go as plain SMS again. */
    fun off(context: Context, address: String) {
        prefs(context).edit().remove("peer:${norm(address)}").apply()
        synchronized(sessions) { sessions.remove(norm(address)) }
    }

    /** A new key for this phone: every conversation's encryption ends, and each is exchanged again to go on. */
    @Synchronized
    fun reset(context: Context) {
        prefs(context).edit().clear().apply()
        identity = null
        synchronized(sessions) { sessions.clear() }
        runCatching { KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(WRAP_ALIAS) }
    }

    // --- texts ---------------------------------------------------------------------------------------------------------

    private fun key(context: Context, address: String): ByteArray? {
        val n = norm(address)
        synchronized(sessions) { sessions[n]?.let { return it } }
        val pub = peer(context, address)?.optString("pub", "")?.takeIf { it.isNotEmpty() } ?: return null
        return try {
            val (mine, minePub) = identity(context)
            E2eCrypto.conversationKey(mine, minePub, Base64.getDecoder().decode(pub))?.also { synchronized(sessions) { sessions[n] = it } }
        } catch (e: Exception) { Log.e(TAG, "e2e key", e); null }
    }

    /** [text] as it should go to [address]: sealed where encryption is on with them, else null (send it as it is). */
    fun wire(context: Context, address: String, text: String): String? {
        if (!isOn(context, address) || E2eCrypto.keyIn(text) != null) return null
        val k = key(context, address) ?: return null
        return E2eCrypto.seal(k, text)
    }

    /** A stored text for the screen: its words, and what it was ("encrypted", "undecryptable", "key", or null). */
    fun read(context: Context, address: String, body: String): Pair<String, String?> {
        if (E2eCrypto.isSealed(body)) {
            val k = key(context, address)
            val words = k?.let { E2eCrypto.open(it, body) }
            return if (words != null) words to "encrypted" else "" to "undecryptable"
        }
        if (E2eCrypto.keyIn(body) != null) return "" to "key"
        return body to null
    }

    /** One line for a conversation's preview. */
    fun preview(context: Context, address: String?, body: String): String {
        if (address == null) return body
        val (words, kind) = read(context, address, body)
        return when (kind) {
            "undecryptable" -> "Encrypted message"
            "key" -> "Encryption key"
            else -> words
        }
    }
}

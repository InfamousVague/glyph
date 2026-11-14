package com.infamousvague.ghostmessaging

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyStore
import java.util.Base64
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The computers this phone is paired with (Matt, 2026-11-13: "a companion desktop app that can proxy messages
 * encrypted from my phone to my desktop and then send back to the phone to send again"; docs/desktop.md): who they
 * are, the key kept with each, a pairing while it is being made, and the connections open now. The sealing is
 * [DeskCrypto]'s and a connection is a [DeskSession]; the sockets are [DeskService]'s. This is what Android keeps,
 * and what the sessions ask of the phone.
 *
 * A pairing's key is kept encrypted under a key in the Android Keystore, as [E2e] keeps this phone's own. The
 * private key made for a pairing is used once, to make that key, and is never kept.
 */
object Desk : DeskHost {
    private const val TAG = "GhostDesk"
    private const val PREFS = "desk"
    private const val WRAP_ALIAS = "ghost_desk_wrap"

    /** How long a scanned code waits for its computer. */
    const val PAIRING_LIFE = 10 * 60 * 1000L
    private const val SENT_KEPT = 500

    class Pairing(val id: String, var name: String, val key: ByteArray, var mode: String, var relay: String, val since: Long, var seen: Long)

    /** A pairing being made: the code was scanned, and the two have yet to say their six digits match. */
    class Pending(val offer: DeskCrypto.Offer, @Volatile var mode: String, val phonePublic: ByteArray, val key: ByteArray, val started: Long) {
        val pairingId: String = DeskCrypto.pairingId(offer.secret)

        /** waiting (for the computer to connect), code (both show the digits), done, failed. */
        @Volatile var phase = "waiting"
        @Volatile var mine = false
        @Volatile var theirs = false
        @Volatile var session: DeskSession? = null
        @Volatile var error: String? = null
        val expired: Boolean get() = System.currentTimeMillis() - started > PAIRING_LIFE
    }

    /** A relay channel to remove: its pairing was unpaired here. */
    class Removed(val relay: String, val channel: String, val token: String)

    @Volatile private var appContext: Context? = null
    private val pairings = LinkedHashMap<String, Pairing>()
    private var loaded = false
    @Volatile var pending: Pending? = null
        private set
    private val sessions = CopyOnWriteArrayList<DeskSession>()
    private val removed = ArrayList<Removed>()

    /** The screen, told that something about computers changed; and the service, told to look at what it should hold. */
    @Volatile var listener: (() -> Unit)? = null
    @Volatile var serviceListener: (() -> Unit)? = null

    private val io = Executors.newSingleThreadExecutor()
    private val pictures = Executors.newFixedThreadPool(2)
    private val teller = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var seenSaved = 0L

    fun init(context: Context) {
        if (appContext == null) appContext = context.applicationContext
        load()
    }

    private fun context(): Context = appContext ?: throw IllegalStateException("Desk.init was not called")
    private fun prefs() = context().getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private fun changedHere() { main.post { listener?.invoke() } }
    private fun tellService() { main.post { serviceListener?.invoke() } }

    // --- what is kept ---------------------------------------------------------------------------------------------------

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

    private fun wrap(key: ByteArray): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, wrapKey())
        return Base64.getEncoder().encodeToString(cipher.iv + cipher.doFinal(key))
    }

    private fun unwrap(text: String): ByteArray {
        val raw = Base64.getDecoder().decode(text)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, wrapKey(), GCMParameterSpec(128, raw, 0, 12))
        return cipher.doFinal(raw, 12, raw.size - 12)
    }

    @Synchronized
    private fun load() {
        if (loaded) return
        loaded = true
        val all = try { JSONArray(prefs().getString("pairings", "[]")) } catch (_: Exception) { JSONArray() }
        for (i in 0 until all.length()) {
            val o = all.optJSONObject(i) ?: continue
            try {
                val p = Pairing(o.getString("id"), o.optString("name", "A computer"), unwrap(o.getString("key")), o.optString("mode", "both"), o.optString("relay"), o.optLong("since"), o.optLong("seen"))
                pairings[p.id] = p
            } catch (e: Exception) {
                // A key that no longer opens (the Keystore's key is gone): that computer is paired again.
                Log.e(TAG, "a pairing could not be read and is dropped", e)
            }
        }
    }

    @Synchronized
    private fun save() {
        val all = JSONArray()
        for (p in pairings.values) {
            all.put(JSONObject().put("id", p.id).put("name", p.name).put("key", wrap(p.key)).put("mode", p.mode).put("relay", p.relay).put("since", p.since).put("seen", p.seen))
        }
        prefs().edit().putString("pairings", all.toString()).apply()
    }

    @Synchronized fun all(): List<Pairing> = pairings.values.toList()

    /** Whether there is anything for [DeskService] to hold a connection for. */
    fun wanted(): Boolean = all().isNotEmpty() || pending?.let { it.phase == "waiting" || it.phase == "code" } == true

    /** The port the phone listened on last, so a computer that remembers the address finds it again. */
    var port: Int
        get() = prefs().getInt("port", 0)
        set(value) { prefs().edit().putInt("port", value).apply() }

    /**
     * Where this phone is listening on the local network, as `address:port`: for a computer on a network that keeps
     * the two from finding each other, typed there by hand. Empty before the phone has listened once.
     */
    fun addresses(): List<String> {
        val port = port
        if (port <= 0) return emptyList()
        return try {
            java.net.NetworkInterface.getNetworkInterfaces().toList()
                .filter { it.isUp && !it.isLoopback }
                .flatMap { it.inetAddresses.toList() }
                .filterIsInstance<java.net.Inet4Address>()
                .filter { it.isSiteLocalAddress }
                .map { "${it.hostAddress}:$port" }
        } catch (_: Exception) { emptyList() }
    }

    /** What the phone calls itself on the local network: `Ghost-` and six letters that say nothing of whose it is. */
    fun serviceName(): String {
        val p = prefs()
        p.getString("nsd", null)?.let { return it }
        val name = "Ghost-" + DeskCrypto.hex(ByteArray(3).also { java.security.SecureRandom().nextBytes(it) })
        p.edit().putString("nsd", name).apply()
        return name
    }

    // --- for the screen (MainActivity) -----------------------------------------------------------------------------------

    /** Every paired computer: its name, how it connects, when it was paired and last seen, and how it is connected now. */
    fun list(): List<Map<String, Any?>> = all().map { p ->
        mapOf(
            "id" to p.id, "name" to p.name, "mode" to p.mode, "relay" to p.relay, "since" to p.since, "seen" to p.seen,
            // Connected both ways for a moment (the computer moving from the relay to the local network): local is said.
            "via" to sessions.filter { it.id == p.id && it.live && !it.pairing }.let { live -> if (live.any { it.via == "local" }) "local" else live.firstOrNull()?.via },
        )
    }

    /** The pairing being made, for its page: where it stands, the computer's name, the six digits once both have them. */
    fun state(): Map<String, Any?> {
        val p = pending ?: return mapOf("phase" to "none")
        if (p.phase != "done" && p.phase != "failed" && p.expired) {
            p.phase = "failed"
            p.error = "The code ran out. Show a new one on the computer."
            tellService()
        }
        return mapOf(
            "phase" to p.phase, "name" to p.offer.name, "mode" to p.mode, "offered" to p.offer.mode, "relay" to p.offer.relay,
            "code" to (if (p.phase == "code" || p.phase == "done") DeskCrypto.code(p.key) else null),
            "mine" to p.mine, "theirs" to p.theirs, "error" to p.error,
        )
    }

    /** What a code offers, before anything is done with it: the computer's name and how it would connect. */
    fun peek(code: String): Map<String, Any?> {
        val offer = DeskCrypto.parseOffer(code) ?: throw IllegalArgumentException("That isn't a Ghost Messaging pairing code")
        return mapOf("name" to offer.name, "mode" to offer.mode, "relay" to offer.relay)
    }

    /**
     * A code was scanned or pasted: this phone's key pair for the pairing is made, and with it the pairing's key.
     * The service then listens, and the computer, which is looking, connects. [mode] is how the two will connect
     * from then on; left out, it is what the computer offered.
     */
    fun begin(code: String, mode: String?): Map<String, Any?> {
        val offer = DeskCrypto.parseOffer(code) ?: throw IllegalArgumentException("That isn't a Ghost Messaging pairing code")
        val chosen = mode?.takeIf { it in DeskCrypto.MODES } ?: offer.mode
        pending?.session?.close()
        val pair = E2eCrypto.newKeyPair()
        val public = E2eCrypto.publicBytes(pair.public)
        val key = DeskCrypto.pairKey(pair.private, public, offer.key, offer.secret) ?: throw IllegalArgumentException("That code's key could not be read")
        pending = Pending(offer, chosen, public, key, System.currentTimeMillis())
        tellService()
        changedHere()
        return state()
    }

    /** How the pairing being made will connect, changed on its page before it is confirmed. */
    fun setPendingMode(mode: String) {
        val p = pending ?: return
        if (mode !in DeskCrypto.MODES) return
        if (mode != "local" && p.offer.relay.isBlank()) throw IllegalArgumentException("The computer gave no relay to use")
        p.mode = mode
        teller.execute { p.session?.event("mode", JSONObject().put("mode", mode)) }
        changedHere()
    }

    /** "They match", here. */
    fun confirm() {
        val p = pending ?: return
        if (p.phase != "code") return
        p.mine = true
        teller.execute {
            p.session?.event("mode", JSONObject().put("mode", p.mode))
            p.session?.event("confirmed")
            finishIfBoth(p)
        }
        changedHere()
    }

    fun cancel() {
        val p = pending ?: return
        pending = null
        teller.execute { p.session?.event("cancel"); p.session?.close() }
        tellService()
        changedHere()
    }

    /** The page has shown how the pairing ended: it is forgotten. */
    fun done() {
        val p = pending ?: return
        if (p.phase == "done" || p.phase == "failed") { pending = null; tellService() }
    }

    @Synchronized
    private fun finishIfBoth(p: Pending) {
        if (!p.mine || !p.theirs || p.phase != "code") return
        val session = p.session ?: return
        val now = System.currentTimeMillis()
        val pairing = Pairing(DeskCrypto.id(p.key), session.peerName.ifBlank { p.offer.name }, p.key, p.mode, p.offer.relay, now, now)
        pairings[pairing.id] = pairing
        save()
        session.paired(pairing.id)
        sessions.addIfAbsent(session)
        p.phase = "done"
        tellService()
        changedHere()
    }

    fun unpair(id: String) {
        val p = synchronized(this) { pairings.remove(id) } ?: return
        save()
        synchronized(removed) { if (p.relay.isNotBlank()) removed += Removed(p.relay, DeskCrypto.relayChannel(p.key), DeskCrypto.relayToken(p.key)) }
        val open = sessions.filter { it.id == id }
        teller.execute { for (s in open) { s.event("unpaired"); s.close() } }
        tellService()
        changedHere()
    }

    fun setMode(id: String, mode: String) {
        if (mode !in DeskCrypto.MODES) return
        val p = synchronized(this) { pairings[id] } ?: return
        if (mode != "local" && p.relay.isBlank()) throw IllegalArgumentException("This computer was paired with no relay to use")
        p.mode = mode
        save()
        val open = sessions.filter { it.id == id }
        teller.execute { for (s in open) s.event("mode", JSONObject().put("mode", mode)) }
        tellService()
        changedHere()
    }

    /** The relay channels of pairings removed since this was last asked: the service tells the relay to forget them. */
    fun takeRemoved(): List<Removed> = synchronized(removed) { removed.toList().also { removed.clear() } }

    /** A conversation changed ([Bus.changed]): every computer connected now is told, and reads it again. */
    fun changed(thread: Long) {
        if (sessions.isEmpty()) return
        teller.execute {
            for (s in sessions) if (s.live && !s.pairing) s.event("changed", JSONObject().put("thread", thread))
        }
    }

    // --- for a session (DeskHost) ---------------------------------------------------------------------------------------

    override val name: String
        get() = try {
            android.provider.Settings.Global.getString(context().contentResolver, "device_name")?.takeIf { it.isNotBlank() } ?: Build.MODEL
        } catch (_: Exception) { Build.MODEL ?: "Phone" }

    override val app: String
        get() = try { context().packageManager.getPackageInfo(context().packageName, 0).versionName ?: "" } catch (_: Exception) { "" }

    @Synchronized override fun pairKey(id: String): ByteArray? = pairings[id]?.key

    override fun pending(pairingId: String): DeskPending? {
        val p = pending ?: return null
        if (p.pairingId != pairingId || p.expired || (p.phase != "waiting" && p.phase != "code")) return null
        // The computer connecting again (the local network and the relay both reached it, or it tried twice): the
        // newer connection is the pairing's, and the digits are compared afresh.
        val old = p.session
        p.session = null
        p.mine = false
        p.theirs = false
        p.phase = "waiting"
        old?.close()
        return DeskPending(p.key, p.phonePublic)
    }

    override fun mode(session: DeskSession): String = if (session.pairing) (pending?.mode ?: "both") else synchronized(this) { pairings[session.id]?.mode } ?: "both"

    override fun call(session: DeskSession, method: String, args: JSONObject): Any? {
        val p = synchronized(this) { pairings[session.id] } ?: throw IllegalStateException("This computer is not paired with the phone")
        val now = System.currentTimeMillis()
        p.seen = now
        if (now - seenSaved > 60_000) { seenSaved = now; save() }
        return calls.call(method, args)
    }

    override fun event(session: DeskSession, name: String, args: JSONObject) {
        val p = pending
        when (name) {
            "ready" -> {
                if (session.pairing) {
                    if (p == null || p.pairingId != session.id) { session.close(); return }
                    p.session = session
                    p.phase = "code"
                } else {
                    sessions.addIfAbsent(session)
                    synchronized(this) { pairings[session.id]?.let { it.seen = System.currentTimeMillis(); if (session.peerName.isNotBlank()) it.name = session.peerName } }
                    save()
                }
                changedHere()
            }
            "confirmed" -> if (p != null && p.session === session) { p.theirs = true; finishIfBoth(p); changedHere() }
            "cancel" -> if (p != null && p.session === session && p.phase != "done") {
                p.phase = "failed"
                p.error = "Pairing was cancelled on the computer."
                session.close()
                tellService()
                changedHere()
            }
            "unpaired" -> if (!session.pairing) {
                // The computer tells the relay to forget the channel itself, where it can; the phone does too, since
                // the computer may have been on the local network alone at that moment.
                synchronized(this) { pairings.remove(session.id) }?.let { gone ->
                    if (gone.relay.isNotBlank()) synchronized(removed) { removed += Removed(gone.relay, DeskCrypto.relayChannel(gone.key), DeskCrypto.relayToken(gone.key)) }
                }
                save()
                session.close()
                tellService()
                changedHere()
            }
            // The computer is leaving this connection for another (the local network, where it was on the relay).
            "bye" -> session.close()
            "mode" -> {
                val mode = args.optString("mode")
                if (mode !in DeskCrypto.MODES) return
                if (session.pairing) { if (p != null && p.session === session) p.mode = mode }
                else { synchronized(this) { pairings[session.id]?.mode = mode }; save(); tellService() }
                changedHere()
            }
        }
    }

    override fun run(method: String, work: () -> Unit) {
        (if (method == "photo" || method == "part") pictures else io).execute(work)
    }

    override fun closed(session: DeskSession) {
        sessions.remove(session)
        val p = pending
        if (p != null && p.session === session && p.phase == "code") {
            // The computer went before both said the digits match: it may come back while the code lasts.
            p.session = null
            p.mine = false
            p.theirs = false
            p.phase = "waiting"
        }
        changedHere()
    }

    // --- what the phone does for a computer -----------------------------------------------------------------------------

    private val calls by lazy { DeskCalls(Phone(context())) }

    /** The contacts changed: who a number is is asked again, as the screen's own store does. */
    fun contactsChanged() { try { (callsStore ?: return).contactsChanged() } catch (_: Exception) {} }
    @Volatile private var callsStore: Store? = null

    private class Phone(private val context: Context) : DeskPhone {
        private val store = Store(context).also { callsStore = it }
        private val sent = context.getSharedPreferences("desk_sent", Context.MODE_PRIVATE)

        override fun conversations() = store.conversations()
        override fun conversationsPage(limit: Int, offset: Int, pinned: Boolean, archived: Boolean) =
            store.conversationsPage(limit = limit, offset = offset, pinnedToo = pinned, only = if (archived) store.archivedThreads() else null)
        override fun conversation(thread: Long) = store.conversation(thread)
        override fun archivedCount() = (store.conversationsPage(only = store.archivedThreads())["items"] as List<*>).size
        override fun messages(thread: Long, limit: Int) = store.messages(thread, limit)
        override fun people(thread: Long) = store.threadPeople(thread)
        override fun threadFor(addresses: List<String>) = store.threadFor(addresses)
        override fun searchContacts(query: String) = store.searchContacts(query)
        override fun contact(address: String) = store.contact(address)
        override fun photo(uri: String) = store.photo(uri)
        override fun part(id: Long) = store.readPart(id)
        override fun send(addresses: List<String>, body: String) = Sender.send(context, addresses, body)
        // Told to the phone's own screen alone: a computer that heard "changed" would read the conversation again
        // and mark it read again, round and round.
        override fun markRead(thread: Long) { store.markRead(thread); Notifier.cancel(context, thread); Bus.changedOnPhone(thread) }
        override fun setFlag(name: String, thread: Long, on: Boolean) { store.setThreadFlag(name, thread, on); Bus.changed(-1) }
        override fun archive(thread: Long, archived: Boolean) { store.setArchived(thread, archived); Bus.changed(-1) }
        override fun draft(thread: Long) = store.draft(thread)
        override fun setDraft(thread: Long, text: String) = store.setDraft(thread, text)
        override fun e2e(address: String) = E2e.state(context, address)

        override fun sent(key: String): Long? = sent.getLong("k:$key", -1).takeIf { it >= 0 }

        override fun remember(key: String, thread: Long) {
            val order = (sent.getString("order", "") ?: "").split('\n').filter { it.isNotEmpty() } + key
            val edit = sent.edit().putLong("k:$key", thread)
            for (old in order.dropLast(SENT_KEPT)) edit.remove("k:$old")
            edit.putString("order", order.takeLast(SENT_KEPT).joinToString("\n")).apply()
        }
    }
}

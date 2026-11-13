package com.infamousvague.ghostmessaging

import org.json.JSONArray
import org.json.JSONObject
import java.security.SecureRandom
import java.util.Base64

/**
 * One connection from a paired computer, as the phone answers it (docs/desktop.md). It knows nothing of sockets:
 * frames come in through [receive] and go out through the function it was given, so the local network and the relay
 * are the same to it, and it runs on the JVM under test (DeskSessionTest) with a made-up phone behind it.
 *
 * A connection goes: the computer's hello in the clear (which pairing, a random number, a throwaway public key),
 * the phone's hello back, and from then sealed frames only ([DeskCrypto.Channel]). The computer's first sealed
 * frame, `ready`, is what shows it holds the pairing's key: nothing is answered before it. Then the computer asks
 * (`req`), the phone answers (`res`), and either may say something happened (`ev`).
 */
class DeskSession(private val host: DeskHost, val via: String, private val out: (ByteArray) -> Unit, private val random: SecureRandom = SecureRandom()) {
    /** The pairing this connection is under: its id once paired, the QR code's while pairing. */
    @Volatile var id: String = ""
        private set

    /** The two are still comparing their codes: nothing is asked or answered until both said they match. */
    @Volatile var pairing = false
        private set

    /** The computer has proved it holds the key. */
    @Volatile var live = false
        private set

    @Volatile var closed = false
        private set

    /** The computer's name, as its `ready` gave it. */
    @Volatile var peerName: String = ""
        private set

    private var channel: DeskCrypto.Channel? = null
    private val sendLock = Any()

    fun receive(frame: ByteArray) {
        if (closed) return
        if (frame.isEmpty() || frame.size > DeskCrypto.MAX_FRAME) return close()
        val body = frame.copyOfRange(1, frame.size)
        when (frame[0]) {
            DeskCrypto.HELLO -> hello(body)
            DeskCrypto.SEALED -> {
                val text = channel?.open(body) ?: return close()
                val message = try { JSONObject(text) } catch (_: Exception) { return close() }
                sealed(message)
            }
            else -> close()
        }
    }

    private fun hello(body: ByteArray) {
        // One hello to a connection: a second would ask for new keys under the old connection's name.
        if (channel != null) return close()
        val refuse = { why: String -> out(byteArrayOf(DeskCrypto.HELLO) + JSONObject().put("v", 1).put("err", why).toString().toByteArray()); close() }
        val o = try { JSONObject(String(body, Charsets.UTF_8)) } catch (_: Exception) { return close() }
        if (o.optInt("v") != 1) return refuse("version")
        val name = o.optString("id")
        val wantsPairing = o.optBoolean("pair", false)
        val theirNonce = try { Base64.getDecoder().decode(o.optString("n")) } catch (_: Exception) { return close() }
        val theirKey = try { Base64.getDecoder().decode(o.optString("e")) } catch (_: Exception) { return close() }
        if (theirNonce.size != 16 || theirKey.size != 33) return close()

        val pending = if (wantsPairing) host.pending(name) else null
        val key = if (wantsPairing) pending?.key else host.pairKey(name)
        if (key == null) return refuse("unknown")

        val mine = E2eCrypto.newKeyPair()
        val nonce = ByteArray(16).also { random.nextBytes(it) }
        val keys = DeskCrypto.sessionKeys(key, theirNonce, nonce, mine.private, theirKey) ?: return close()
        channel = DeskCrypto.Channel(sendKey = keys.second, receiveKey = keys.first)
        id = name
        pairing = wantsPairing
        val reply = JSONObject().put("v", 1)
            .put("n", Base64.getEncoder().encodeToString(nonce))
            .put("e", Base64.getEncoder().encodeToString(E2eCrypto.publicBytes(mine.public)))
        // While pairing the computer does not have the phone's public key yet: it travels here, in the clear. Swapped
        // on the way, it makes a key the swapper cannot (the QR code's secret is in it), and the codes will not match.
        if (pending != null) reply.put("k", Base64.getEncoder().encodeToString(pending.phonePublic))
        out(byteArrayOf(DeskCrypto.HELLO) + reply.toString().toByteArray())
    }

    private fun sealed(m: JSONObject) {
        val type = m.optString("t")
        if (type == "ready") {
            if (live) return close()
            live = true
            peerName = m.optString("name").take(60)
            send(JSONObject().put("t", "ready").put("name", host.name).put("app", host.app).put("proto", 1).put("mode", host.mode(this)))
            host.event(this, "ready", m)
            return
        }
        if (!live) return close()
        when (type) {
            "ev" -> host.event(this, m.optString("m"), m.optJSONObject("a") ?: JSONObject())
            "req" -> {
                val call = m.optInt("id")
                if (pairing) { send(JSONObject().put("t", "res").put("id", call).put("ok", false).put("e", "Not paired yet")); return }
                val method = m.optString("m")
                val args = m.optJSONObject("a") ?: JSONObject()
                host.run(method) {
                    val answer = JSONObject().put("t", "res").put("id", call)
                    try { answer.put("ok", true).put("r", toJson(host.call(this, method, args))) }
                    catch (e: Exception) { answer.put("ok", false).put("e", e.message ?: e.toString()) }
                    send(answer)
                }
            }
            else -> close()
        }
    }

    /** Both said the codes match: this connection goes on as an ordinary one, under the pairing's own id. */
    fun paired(newId: String) {
        id = newId
        pairing = false
    }

    /** Something happened that the computer should know: a conversation changed, the pairing was removed. */
    fun event(name: String, args: JSONObject? = null) {
        if (!live || closed) return
        val m = JSONObject().put("t", "ev").put("m", name)
        if (args != null) m.put("a", args)
        send(m)
    }

    private fun send(message: JSONObject) {
        val channel = channel ?: return
        // Sealed and sent as one step: frames must arrive in the order their counters were taken.
        synchronized(sendLock) {
            if (closed) return
            try { out(byteArrayOf(DeskCrypto.SEALED) + channel.seal(message.toString())) } catch (_: Exception) { close() }
        }
    }

    fun close() {
        if (closed) return
        closed = true
        live = false
        host.closed(this)
    }

    companion object {
        /** What a call answered, as JSON: maps and lists as they are, bytes as base64. */
        fun toJson(value: Any?): Any = when (value) {
            null -> JSONObject.NULL
            is Map<*, *> -> JSONObject().also { o -> for ((k, v) in value) o.put(k.toString(), toJson(v)) }
            is Iterable<*> -> JSONArray().also { a -> for (v in value) a.put(toJson(v)) }
            is ByteArray -> Base64.getEncoder().encodeToString(value)
            is Array<*> -> JSONArray().also { a -> for (v in value) a.put(toJson(v)) }
            else -> value
        }
    }
}

/** A pairing in progress, as a session needs it: the key both sides will keep, and the phone's public half of it. */
class DeskPending(val key: ByteArray, val phonePublic: ByteArray)

/** What a session needs of the phone around it (Desk.kt on a phone; a made-up one under test). */
interface DeskHost {
    /** The phone's name, as the computer shows it, and the app's version. */
    val name: String
    val app: String

    /** The key of the paired computer [id] names, or null: unpaired, or never paired. */
    fun pairKey(id: String): ByteArray?

    /** The pairing in progress the QR code's [pairingId] names, or null. */
    fun pending(pairingId: String): DeskPending?

    /** How [session]'s pairing connects: both, local, relay. */
    fun mode(session: DeskSession): String

    /** Does what the computer asked; an exception's message is the computer's to show. */
    fun call(session: DeskSession, method: String, args: JSONObject): Any?

    /** `ready` (the computer proved itself), or what the computer said: confirmed, cancel, unpaired, mode. */
    fun event(session: DeskSession, name: String, args: JSONObject)

    /** Runs [work] off the thread frames arrive on, so a long read does not hold the next frame. */
    fun run(method: String, work: () -> Unit)

    fun closed(session: DeskSession)
}

/** What the phone does for a computer: what the screen's own channel asks of Android (MainActivity), a part of it. */
interface DeskPhone {
    fun conversations(): List<Map<String, Any?>>
    fun messages(thread: Long, limit: Int): List<Map<String, Any?>>
    fun people(thread: Long): List<Map<String, Any?>>
    fun threadFor(addresses: List<String>): Long
    fun searchContacts(query: String): List<Map<String, Any?>>
    fun contact(address: String): Map<String, Any?>
    fun photo(uri: String): ByteArray?
    fun part(id: Long): ByteArray?
    fun send(addresses: List<String>, body: String): Long
    fun markRead(thread: Long)
    fun setFlag(name: String, thread: Long, on: Boolean)
    fun archive(thread: Long, archived: Boolean)
    fun draft(thread: Long): String?
    fun setDraft(thread: Long, text: String)
    fun e2e(address: String): Map<String, Any?>

    /** The conversation a text the computer named [key] went to, if it was already sent; and remembering one. */
    fun sent(key: String): Long?
    fun remember(key: String, thread: Long)
}

/**
 * The computer's requests, by name, onto [DeskPhone]. What is not here the computer cannot do: it reads, sends text,
 * marks read, pins, mutes, archives and keeps a draft. It cannot delete, block, change encryption or read the
 * phone's settings.
 */
class DeskCalls(private val phone: DeskPhone) {
    /** The picture last asked for, kept while its pieces are fetched. */
    private var lastPart: Pair<Long, ByteArray>? = null

    fun call(method: String, a: JSONObject): Any? = when (method) {
        "ping" -> null
        "conversations" -> phone.conversations()
        "messages" -> phone.messages(a.getLong("thread"), a.optInt("limit", 300).coerceIn(1, 1000))
        "people" -> phone.people(a.getLong("thread"))
        "threadFor" -> phone.threadFor(strings(a.getJSONArray("addresses")))
        "searchContacts" -> phone.searchContacts(a.optString("query"))
        "contact" -> phone.contact(a.getString("address"))
        "photo" -> phone.photo(a.getString("uri"))?.takeIf { it.size <= PIECE }
        "part" -> piece(a.getLong("id"), a.optInt("offset", 0), a.optInt("max", PIECE))
        "send" -> send(a.getString("key"), strings(a.getJSONArray("addresses")), a.optString("body"))
        "markRead" -> { phone.markRead(a.getLong("thread")); null }
        "threadFlag" -> {
            val name = a.getString("name")
            require(name == "pinned" || name == "muted") { "Not something a computer can change" }
            phone.setFlag(name, a.getLong("thread"), a.optBoolean("on", true)); null
        }
        "archive" -> { phone.archive(a.getLong("thread"), a.optBoolean("archived", true)); null }
        "draft" -> phone.draft(a.getLong("thread"))
        "setDraft" -> { phone.setDraft(a.getLong("thread"), a.optString("text")); null }
        "e2e" -> phone.e2e(a.getString("address"))
        else -> throw IllegalArgumentException("The phone doesn't do \"$method\" for a computer")
    }

    /**
     * Sends [body] once. The computer names each text it asks for; asked again for one already sent (its answer was
     * lost with the connection, and it tried again), the phone says where it went and sends nothing.
     */
    @Synchronized
    private fun send(key: String, addresses: List<String>, body: String): Map<String, Any?> {
        require(key.isNotBlank() && key.length <= 64) { "A text needs a name" }
        require(body.isNotBlank()) { "Nothing to send" }
        phone.sent(key)?.let { return mapOf("thread" to it, "again" to true) }
        val thread = phone.send(addresses, body)
        phone.remember(key, thread)
        return mapOf("thread" to thread)
    }

    /** A picture crosses in pieces: [max] bytes from [offset], and how long the whole is. */
    @Synchronized
    private fun piece(id: Long, offset: Int, max: Int): Map<String, Any?>? {
        val bytes = lastPart?.takeIf { it.first == id }?.second ?: (phone.part(id) ?: return null).also { lastPart = id to it }
        val from = offset.coerceIn(0, bytes.size)
        val to = (from + max.coerceIn(1, PIECE)).coerceAtMost(bytes.size)
        if (to >= bytes.size) lastPart = null
        return mapOf("data" to bytes.copyOfRange(from, to), "total" to bytes.size)
    }

    private fun strings(a: JSONArray): List<String> = (0 until a.length()).map { a.getString(it) }

    companion object {
        /** As much of a picture as one frame carries: its base64 stays well under [DeskCrypto.MAX_FRAME]. */
        const val PIECE = 384 * 1024
    }
}

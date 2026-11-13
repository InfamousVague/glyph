package com.infamousvague.ghostmessaging

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.SecureRandom
import java.util.Base64

/** A computer, played here in Kotlin, against the phone's session with a made-up phone behind it. */
class DeskSessionTest {
    private val random = SecureRandom()

    /** A phone with two conversations, that remembers what it was asked to send. */
    private class FakePhone : DeskPhone {
        val sentTexts = ArrayList<Pair<List<String>, String>>()
        val read = ArrayList<Long>()
        val keys = HashMap<String, Long>()
        var picture = ByteArray(1000000) { (it % 251).toByte() }
        override fun conversations() = listOf(mapOf("id" to 7L, "snippet" to "See you at 7", "people" to listOf(mapOf("address" to "+15550100", "name" to "Maya"))))
        override fun messages(thread: Long, limit: Int) = listOf(mapOf("id" to 1L, "kind" to "sms", "body" to "See you at 7", "thread" to thread, "limit" to limit))
        override fun people(thread: Long) = listOf(mapOf("address" to "+15550100"))
        override fun threadFor(addresses: List<String>) = 7L
        override fun searchContacts(query: String) = emptyList<Map<String, Any?>>()
        override fun contact(address: String) = mapOf<String, Any?>("address" to address)
        override fun photo(uri: String): ByteArray? = byteArrayOf(1, 2, 3)
        override fun part(id: Long): ByteArray? = if (id == 5L) picture else null
        override fun send(addresses: List<String>, body: String): Long { sentTexts += addresses to body; return 7L }
        override fun markRead(thread: Long) { read += thread }
        override fun setFlag(name: String, thread: Long, on: Boolean) {}
        override fun archive(thread: Long, archived: Boolean) {}
        override fun draft(thread: Long): String? = null
        override fun setDraft(thread: Long, text: String) {}
        override fun e2e(address: String) = mapOf<String, Any?>("state" to "none")
        override fun sent(key: String): Long? = keys[key]
        override fun remember(key: String, thread: Long) { keys[key] = thread }
    }

    private class Host(val phone: FakePhone) : DeskHost {
        val keys = HashMap<String, ByteArray>()
        val pendings = HashMap<String, DeskPending>()
        val events = ArrayList<String>()
        val calls = DeskCalls(phone)
        override val name = "Fold"
        override val app = "0.7.0"
        override fun pairKey(id: String) = keys[id]
        override fun pending(pairingId: String) = pendings[pairingId]
        override fun mode(session: DeskSession) = "both"
        override fun call(session: DeskSession, method: String, args: JSONObject) = calls.call(method, args)
        override fun event(session: DeskSession, name: String, args: JSONObject) { events += name }
        override fun run(method: String, work: () -> Unit) = work()
        override fun closed(session: DeskSession) { events += "closed" }
    }

    /** The computer's side of one connection. */
    private inner class Computer(val host: Host, val pairKey: ByteArray?, val id: String, val pairing: Boolean = false, val secret: ByteArray? = null, val deskPrivate: java.security.PrivateKey? = null, val deskPublic: ByteArray? = null) {
        val fromPhone = ArrayList<ByteArray>()
        val session = DeskSession(host, "local", { fromPhone += it })
        var channel: DeskCrypto.Channel? = null
        var key: ByteArray? = pairKey
        var refused: String? = null
        private var next = 1

        fun hello() {
            val eph = E2eCrypto.newKeyPair()
            val nonce = ByteArray(16).also { random.nextBytes(it) }
            val hello = JSONObject().put("v", 1).put("id", id).put("n", b64(nonce)).put("e", b64(E2eCrypto.publicBytes(eph.public)))
            if (pairing) hello.put("pair", true)
            session.receive(byteArrayOf(DeskCrypto.HELLO) + hello.toString().toByteArray())
            val reply = fromPhone.removeAt(0)
            assertEquals(DeskCrypto.HELLO, reply[0])
            val o = JSONObject(String(reply, 1, reply.size - 1))
            if (o.has("err")) { refused = o.getString("err"); return }
            if (pairing) key = DeskCrypto.pairKey(deskPrivate!!, deskPublic!!, Base64.getDecoder().decode(o.getString("k")), secret!!)
            val keys = DeskCrypto.sessionKeys(key!!, nonce, Base64.getDecoder().decode(o.getString("n")), eph.private, Base64.getDecoder().decode(o.getString("e")))!!
            channel = DeskCrypto.Channel(sendKey = keys.first, receiveKey = keys.second)
        }

        fun say(message: JSONObject) = session.receive(byteArrayOf(DeskCrypto.SEALED) + channel!!.seal(message.toString()))

        fun hear(): JSONObject {
            val frame = fromPhone.removeAt(0)
            assertEquals(DeskCrypto.SEALED, frame[0])
            return JSONObject(channel!!.open(frame.copyOfRange(1, frame.size))!!)
        }

        fun ready(): JSONObject { say(JSONObject().put("t", "ready").put("name", "Matt's MacBook").put("proto", 1)); return hear() }

        fun ask(method: String, args: JSONObject = JSONObject()): JSONObject {
            val call = next++
            say(JSONObject().put("t", "req").put("id", call).put("m", method).put("a", args))
            val answer = hear()
            assertEquals("res", answer.getString("t"))
            assertEquals(call, answer.getInt("id"))
            return answer
        }
    }

    private fun b64(b: ByteArray) = Base64.getEncoder().encodeToString(b)

    private fun paired(): Pair<Host, Computer> {
        val host = Host(FakePhone())
        val key = ByteArray(32).also { random.nextBytes(it) }
        host.keys[DeskCrypto.id(key)] = key
        return host to Computer(host, key, DeskCrypto.id(key))
    }

    @Test
    fun aPairedComputerConnectsAsksAndIsAnswered() {
        val (host, mac) = paired()
        mac.hello()
        val ready = mac.ready()
        assertEquals("ready", ready.getString("t"))
        assertEquals("Fold", ready.getString("name"))
        assertEquals("both", ready.getString("mode"))
        assertTrue(mac.session.live)
        assertEquals("Matt's MacBook", mac.session.peerName)
        assertEquals(listOf("ready"), host.events)

        val list = mac.ask("conversations")
        assertTrue(list.getBoolean("ok"))
        assertEquals("See you at 7", list.getJSONArray("r").getJSONObject(0).getString("snippet"))
        assertEquals("Maya", list.getJSONArray("r").getJSONObject(0).getJSONArray("people").getJSONObject(0).getString("name"))

        val messages = mac.ask("messages", JSONObject().put("thread", 7).put("limit", 50))
        assertEquals(50, messages.getJSONArray("r").getJSONObject(0).getInt("limit"))

        mac.ask("markRead", JSONObject().put("thread", 7))
        assertEquals(listOf(7L), host.phone.read)

        // The phone says a conversation changed.
        mac.session.event("changed", JSONObject().put("thread", 7))
        val event = mac.hear()
        assertEquals("changed", event.getString("m"))
        assertEquals(7, event.getJSONObject("a").getInt("thread"))
    }

    @Test
    fun aTextAskedForTwiceIsSentOnce() {
        val (host, mac) = paired()
        mac.hello(); mac.ready()
        val args = JSONObject().put("key", "mac-1").put("addresses", JSONArray(listOf("+15550100"))).put("body", "On my way")
        val first = mac.ask("send", args)
        assertEquals(7, first.getJSONObject("r").getInt("thread"))
        // The answer was lost with the connection; the computer asks again, on a new one.
        val again = Computer(host, mac.pairKey, mac.id)
        again.hello(); again.ready()
        val second = again.ask("send", args)
        assertTrue(second.getJSONObject("r").getBoolean("again"))
        assertEquals(1, host.phone.sentTexts.size)
        assertEquals("On my way", host.phone.sentTexts[0].second)
        // Words with nothing in them, and a text with no name, are refused.
        assertFalse(mac.ask("send", JSONObject().put("key", "mac-2").put("addresses", JSONArray(listOf("+15550100"))).put("body", "  ")).getBoolean("ok"))
        assertFalse(mac.ask("send", JSONObject().put("key", "").put("addresses", JSONArray(listOf("+15550100"))).put("body", "x")).getBoolean("ok"))
        assertEquals(1, host.phone.sentTexts.size)
    }

    @Test
    fun aRecordedFramePlayedAgainEndsTheConnectionAndSendsNothing() {
        val (host, mac) = paired()
        mac.hello(); mac.ready()
        val frame = byteArrayOf(DeskCrypto.SEALED) + mac.channel!!.seal(
            JSONObject().put("t", "req").put("id", 9).put("m", "send").put("a", JSONObject().put("key", "mac-9").put("addresses", JSONArray(listOf("+15550100"))).put("body", "Once")).toString())
        mac.session.receive(frame)
        assertEquals(1, host.phone.sentTexts.size)
        mac.session.receive(frame)
        assertTrue(mac.session.closed)
        assertEquals(1, host.phone.sentTexts.size)
        // On a new connection the old frame is under the wrong key: refused there too.
        val later = Computer(host, mac.pairKey, mac.id)
        later.hello(); later.ready()
        later.session.receive(frame)
        assertTrue(later.session.closed)
        assertEquals(1, host.phone.sentTexts.size)
    }

    @Test
    fun aStrangerLearnsNothingAndNothingIsAnsweredBeforeTheComputerProvesItself() {
        val (host, mac) = paired()
        // A pairing the phone does not have.
        val stranger = Computer(host, ByteArray(32), "0011223344556677")
        stranger.hello()
        assertEquals("unknown", stranger.refused)
        assertTrue(stranger.session.closed)
        // The right id, the wrong key: its first sealed frame does not open.
        val wrong = Computer(host, ByteArray(32) { 9 }, mac.id)
        wrong.hello()
        wrong.session.receive(byteArrayOf(DeskCrypto.SEALED) + wrong.channel!!.seal(JSONObject().put("t", "ready").toString()))
        assertTrue(wrong.session.closed)
        assertTrue(wrong.fromPhone.isEmpty())
        assertFalse(host.events.contains("ready"))
        // The right key, but asking before `ready`.
        mac.hello()
        mac.say(JSONObject().put("t", "req").put("id", 1).put("m", "conversations"))
        assertTrue(mac.session.closed)
        assertTrue(mac.fromPhone.isEmpty())
        // A sealed frame before any hello, an empty frame, a frame of another kind.
        for (frame in listOf(byteArrayOf(DeskCrypto.SEALED, 1, 2, 3), byteArrayOf(), byteArrayOf(9, 9))) {
            val s = DeskSession(host, "local", { throw AssertionError("nothing should be said") })
            s.receive(frame)
            assertTrue(s.closed)
        }
    }

    @Test
    fun whatAComputerMayNotDoIsRefused() {
        val (_, mac) = paired()
        mac.hello(); mac.ready()
        for (method in listOf("deleteThread", "deleteMessage", "setBlocked", "e2eReset", "prefs", "setPref", "sendSticker")) {
            val answer = mac.ask(method, JSONObject().put("thread", 7))
            assertFalse(method, answer.getBoolean("ok"))
        }
        assertFalse(mac.ask("threadFlag", JSONObject().put("name", "archived").put("thread", 7)).getBoolean("ok"))
        assertTrue(mac.ask("threadFlag", JSONObject().put("name", "pinned").put("thread", 7)).getBoolean("ok"))
    }

    @Test
    fun aPictureCrossesInPieces() {
        val (host, mac) = paired()
        mac.hello(); mac.ready()
        val whole = java.io.ByteArrayOutputStream()
        var total = -1
        while (total < 0 || whole.size() < total) {
            val r = mac.ask("part", JSONObject().put("id", 5).put("offset", whole.size())).getJSONObject("r")
            total = r.getInt("total")
            val piece = Base64.getDecoder().decode(r.getString("data"))
            assertTrue(piece.isNotEmpty() && piece.size <= DeskCalls.PIECE)
            whole.write(piece)
        }
        assertArrayEquals(host.phone.picture, whole.toByteArray())
        assertTrue(mac.ask("part", JSONObject().put("id", 6)).isNull("r"))
        assertEquals("AQID", mac.ask("photo", JSONObject().put("uri", "content://x")).getString("r"))
    }

    @Test
    fun pairingGivesBothTheSameKeyAndCodeAndNothingIsAnsweredUntilBothSayTheyMatch() {
        val host = Host(FakePhone())
        // The computer's QR code.
        val desk = E2eCrypto.newKeyPair()
        val deskPublic = E2eCrypto.publicBytes(desk.public)
        val secret = ByteArray(16).also { random.nextBytes(it) }
        val offer = DeskCrypto.parseOffer(DeskCrypto.offerText(DeskCrypto.Offer(deskPublic, secret, "Matt's MacBook", "both", "")))!!
        // The phone scans it: its own key pair, and the pairing's key.
        val phone = E2eCrypto.newKeyPair()
        val phonePublic = E2eCrypto.publicBytes(phone.public)
        val phoneKey = DeskCrypto.pairKey(phone.private, phonePublic, offer.key, offer.secret)!!
        host.pendings[DeskCrypto.pairingId(offer.secret)] = DeskPending(phoneKey, phonePublic)

        val mac = Computer(host, null, DeskCrypto.pairingId(secret), pairing = true, secret = secret, deskPrivate = desk.private, deskPublic = deskPublic)
        mac.hello()
        assertArrayEquals(phoneKey, mac.key)
        assertEquals(DeskCrypto.code(phoneKey), DeskCrypto.code(mac.key!!))
        mac.ready()
        assertTrue(mac.session.pairing)
        assertFalse(mac.ask("conversations").getBoolean("ok"))
        mac.say(JSONObject().put("t", "ev").put("m", "confirmed"))
        assertEquals(listOf("ready", "confirmed"), host.events)
        // The phone said so too: the connection goes on as an ordinary one.
        host.keys[DeskCrypto.id(phoneKey)] = phoneKey
        mac.session.paired(DeskCrypto.id(phoneKey))
        assertTrue(mac.ask("conversations").getBoolean("ok"))
        assertEquals(DeskCrypto.id(phoneKey), mac.session.id)

        // Someone in the middle who swaps the phone's public key for their own never saw the QR code: no key.
        val eve = E2eCrypto.newKeyPair()
        val theirs = DeskCrypto.pairKey(desk.private, deskPublic, E2eCrypto.publicBytes(eve.public), secret)!!
        assertFalse(theirs.contentEquals(phoneKey))
        assertNull(host.pairKey(DeskCrypto.id(theirs)))
    }
}

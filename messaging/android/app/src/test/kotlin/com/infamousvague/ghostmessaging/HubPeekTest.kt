package com.infamousvague.ghostmessaging

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.DataInputStream
import java.io.OutputStream
import java.net.ServerSocket
import java.security.MessageDigest
import java.security.Signature
import java.util.Base64

/**
 * The fifteen-minute look at the hub (HubPeek.kt): against a hub written out here, and, where GHOST_TEST_HUB names
 * one (`dart run relay/bin/relay.dart --port 18999`, then GHOST_TEST_HUB=ws://127.0.0.1:18999/hub), the real one.
 */
class HubPeekTest {
    private fun serverFrame(out: OutputStream, text: String) {
        val payload = text.toByteArray()
        out.write(0x81)
        out.write(payload.size)
        out.write(payload)
        out.flush()
    }

    private fun clientText(input: DataInputStream): String {
        input.readUnsignedByte()
        val b1 = input.readUnsignedByte()
        var length = (b1 and 0x7F).toLong()
        if (length == 126L) length = input.readUnsignedShort().toLong()
        val mask = ByteArray(4).also { input.readFully(it) }
        val payload = ByteArray(length.toInt()).also { input.readFully(it) }
        for (i in payload.indices) payload[i] = (payload[i].toInt() xor mask[i % 4].toInt()).toByte()
        return String(payload)
    }

    /** A hub that greets with [hello] and answers a sign-in with [answer]; what the client said, in [said]. */
    private fun hub(hello: String, answer: String, said: MutableList<String>): Pair<String, Thread> {
        val server = ServerSocket(0)
        val t = Thread {
            server.use { srv ->
                srv.accept().use { s ->
                    val input = DataInputStream(s.getInputStream().buffered())
                    val out = s.getOutputStream()
                    val head = StringBuilder()
                    while (!head.endsWith("\r\n\r\n")) head.append(input.read().toChar())
                    val key = head.lines().first { it.startsWith("Sec-WebSocket-Key:") }.substringAfter(':').trim()
                    val accept = Base64.getEncoder().encodeToString(MessageDigest.getInstance("SHA-1").digest((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").toByteArray()))
                    out.write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: $accept\r\n\r\n".toByteArray())
                    out.flush()
                    serverFrame(out, hello)
                    try {
                        val first = clientText(input)
                        said += first
                        if (!first.startsWith("{")) return@use
                        serverFrame(out, answer)
                        clientText(input)
                    } catch (_: Exception) {}
                }
            }
        }.apply { start() }
        return "ws://127.0.0.1:${server.localPort}/hub" to t
    }

    @Test
    fun itSignsInOnlyToLookAndReadsHowMuchIsHeld() {
        val said = mutableListOf<String>()
        val (url, t) = hub("{\"hello\":\"0a0b\",\"peek\":true}", "{\"ok\":true,\"held\":3,\"peek\":true,\"here\":false}", said)
        var signed: ByteArray? = null
        val held = HubPeek.look(url, "ab".repeat(16), ByteArray(33) { 2 }, { signed = it; ByteArray(64) }, waitSeconds = 5)
        t.join(3000)
        assertEquals(3, held)
        assertTrue("the greeting and the hub's number are what is signed", signed!!.contentEquals("ghost-hub v1 ".toByteArray() + byteArrayOf(10, 11)))
        val hello = JSONObject(said[0])
        assertEquals(true, hello.getBoolean("peek"))
        assertEquals("ab".repeat(16), hello.getString("id"))
    }

    @Test
    fun aHubThatDoesNotSayItKnowsALookIsNotSignedInTo() {
        val said = mutableListOf<String>()
        val (url, t) = hub("{\"hello\":\"0a0b\"}", "{\"ok\":true,\"held\":3}", said)
        var signedAnything = false
        val held = HubPeek.look(url, "ab".repeat(16), ByteArray(33), { signedAnything = true; ByteArray(64) }, waitSeconds = 3)
        t.join(3000)
        assertNull(held)
        assertTrue(!signedAnything)
        assertTrue("nothing signed in with: ${said}", said.none { it.startsWith("{") })
    }

    @Test
    fun anAnswerThatIsNoLookIsNotBelieved() {
        val said = mutableListOf<String>()
        val (url, t) = hub("{\"hello\":\"0a0b\",\"peek\":true}", "{\"ok\":true,\"held\":3}", said)
        val held = HubPeek.look(url, "ab".repeat(16), ByteArray(33), { ByteArray(64) }, waitSeconds = 3)
        t.join(3000)
        assertNull(held)
    }

    @Test
    fun againstTheRealHub() {
        val url = System.getenv("GHOST_TEST_HUB")
        assumeTrue(url != null)
        val pair = E2eCrypto.newKeyPair()
        val pub = E2eCrypto.publicBytes(pair.public)
        val sign = { m: ByteArray -> Net.rawSignature(Signature.getInstance("SHA256withECDSA").apply { initSign(pair.private); update(m) }.sign())!! }
        assertEquals(0, HubPeek.look(url!!, Net.idOf(pub), pub, sign, waitSeconds = 5))
    }
}

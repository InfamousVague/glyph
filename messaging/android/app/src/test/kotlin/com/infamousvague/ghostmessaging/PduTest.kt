package com.infamousvague.ghostmessaging

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.ByteArrayOutputStream

/** The MMS encoder and decoder against each other and against bytes laid out by hand from the spec. */
class PduTest {
    @Test
    fun sendReqReadsBack() {
        val jpeg = ByteArray(5000) { (it * 7).toByte() }
        val parts = listOf(
            Pdu.Part("image/jpeg", jpeg, name = "image0.jpg", contentLocation = "image0.jpg", contentId = "image0"),
            Pdu.Part("text/plain", "Hello 👻 group".toByteArray(), contentLocation = "text0.txt", contentId = "text0"),
        )
        val bytes = Pdu.sendReq(listOf("+1 (555) 123-4567", "5559876543"), parts)
        val m = Pdu.parse(bytes)
        assertEquals(Pdu.SEND_REQ, m.type)
        assertEquals(listOf("+15551234567", "5559876543"), m.to)
        assertEquals("application/vnd.wap.multipart.related", m.contentType)
        assertEquals(3, m.parts.size)
        assertEquals("application/smil", m.parts[0].contentType)
        assertEquals("image/jpeg", m.parts[1].contentType)
        assertEquals("image0.jpg", m.parts[1].name)
        assertEquals("image0.jpg", m.parts[1].contentLocation)
        assertEquals("image0", m.parts[1].contentId)
        assertArrayEquals(jpeg, m.parts[1].data)
        assertEquals("text/plain", m.parts[2].contentType)
        assertEquals("Hello 👻 group", m.parts[2].text())
    }

    @Test
    fun notifyRespInd() {
        val m = Pdu.parse(Pdu.notifyRespInd("abc123"))
        assertEquals(Pdu.NOTIFYRESP_IND, m.type)
        assertEquals("abc123", m.transactionId)
        assertEquals(0x81, m.status)
    }

    private fun text(o: ByteArrayOutputStream, s: String) { o.write(s.toByteArray()); o.write(0) }

    @Test
    fun notificationInd() {
        val o = ByteArrayOutputStream()
        o.write(0x8C); o.write(0x82)
        o.write(0x98); text(o, "TID1")
        o.write(0x8D); o.write(0x92)
        // From: length, address-present, text
        val from = "+15551112222/TYPE=PLMN"
        o.write(0x89); o.write(from.length + 2); o.write(0x80); text(o, from)
        o.write(0x8A); o.write(0x80) // message class personal
        o.write(0x8E); o.write(2); o.write(0x30); o.write(0x39) // message size, long-integer 12345
        o.write(0x88); o.write(5); o.write(0x81); o.write(3); o.write(0x02); o.write(0xA3); o.write(0x00) // expiry, relative
        o.write(0x83); text(o, "http://mmsc.example/abc?x=1")
        val m = Pdu.parse(o.toByteArray())
        assertEquals(Pdu.NOTIFICATION_IND, m.type)
        assertEquals("TID1", m.transactionId)
        assertEquals("+15551112222", m.from)
        assertEquals("http://mmsc.example/abc?x=1", m.contentLocation)
    }

    @Test
    fun retrieveConfFromACarrier() {
        // Laid out as carriers send them: encoded To with a charset, a date, multipart/related with type and start
        // parameters, a SMIL part, a text part with charset given as a long integer, and a picture with a name.
        val o = ByteArrayOutputStream()
        o.write(0x8C); o.write(0x84)
        o.write(0x98); text(o, "TID9")
        o.write(0x8D); o.write(0x92)
        o.write(0x8B); text(o, "MSGID")
        o.write(0x85); o.write(4); o.write(0x65); o.write(0x00); o.write(0x00); o.write(0x00) // date
        val from = "+15550001111/TYPE=PLMN"
        o.write(0x89); o.write(from.length + 2); o.write(0x80); text(o, from)
        val to1 = "+15550002222/TYPE=PLMN"
        o.write(0x97); o.write(to1.length + 2); o.write(0xEA); text(o, to1) // encoded string with utf-8
        o.write(0x97); text(o, "+15550003333/TYPE=PLMN")
        o.write(0x96); o.write(7); o.write(0xEA); text(o, "Hey!!")
        // Content-Type: related; type=application/smil; start=<smil>
        val ct = ByteArrayOutputStream()
        ct.write(0xB3); ct.write(0x89); text(ct, "application/smil"); ct.write(0x8A); text(ct, "<smil>")
        o.write(0x84); o.write(ct.size()); o.write(ct.toByteArray())

        fun uintvar(out: ByteArrayOutputStream, v: Int) {
            if (v >= 128) out.write(0x80 or (v shr 7)); out.write(v and 0x7F)
        }
        fun part(ctBytes: ByteArray, headers: ByteArray, data: ByteArray): ByteArray {
            val p = ByteArrayOutputStream()
            uintvar(p, ctBytes.size + headers.size); uintvar(p, data.size)
            p.write(ctBytes); p.write(headers); p.write(data)
            return p.toByteArray()
        }
        val smilData = "<smil/>".toByteArray()
        val smilCt = byteArrayOf(0x11) + "application/smil".toByteArray() + byteArrayOf(0)
        val txtData = "hi everyone".toByteArray(Charsets.UTF_8)
        val txtCt = byteArrayOf(0x04, 0x83.toByte(), 0x81.toByte(), 0x01, 0x6A) // text/plain; charset=106 as long int
        val txtHeaders = byteArrayOf(0x8E.toByte()) + "text_0.txt".toByteArray() + byteArrayOf(0)
        val img = ByteArray(300) { it.toByte() }
        val imgCt = byteArrayOf(0x0A, 0x9E.toByte(), 0x85.toByte()) + "pic.jpg".toByteArray() + byteArrayOf(0)
        val imgHeaders = byteArrayOf(0xC0.toByte(), 0x22) + "<pic>".toByteArray() + byteArrayOf(0)
        o.write(3)
        o.write(part(smilCt, byteArrayOf(), smilData))
        o.write(part(txtCt, txtHeaders, txtData))
        o.write(part(imgCt, imgHeaders, img))

        val m = Pdu.parse(o.toByteArray())
        assertEquals(Pdu.RETRIEVE_CONF, m.type)
        assertEquals("+15550001111", m.from)
        assertEquals(listOf("+15550002222", "+15550003333"), m.to)
        assertEquals("Hey!!", m.subject)
        assertEquals("MSGID", m.messageId)
        assertEquals(0x65000000L, m.date)
        assertEquals(3, m.parts.size)
        assertEquals("application/smil", m.parts[0].contentType)
        assertEquals("text/plain", m.parts[1].contentType)
        assertEquals("hi everyone", m.parts[1].text())
        assertEquals("text_0.txt", m.parts[1].contentLocation)
        assertEquals("image/jpeg", m.parts[2].contentType)
        assertEquals("pic.jpg", m.parts[2].name)
        assertEquals("pic", m.parts[2].contentId)
        assertArrayEquals(img, m.parts[2].data)
    }
}

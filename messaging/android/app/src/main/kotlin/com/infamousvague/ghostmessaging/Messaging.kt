package com.infamousvague.ghostmessaging

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import android.util.Log
import java.io.ByteArrayOutputStream
import java.io.File

private const val TAG = "GhostMessaging"

/** Tells the app on screen, when there is one, that a conversation changed. */
object Bus {
    @Volatile var listener: ((Long) -> Unit)? = null

    /** The choices the screen reads (the "ui" preferences) were changed from this side: a background that arrived. */
    @Volatile var prefsListener: (() -> Unit)? = null
    private val main = Handler(Looper.getMainLooper())
    fun changed(thread: Long) {
        main.post { listener?.invoke(thread) }
        // And the computers paired with this phone that are connected now (Desk.kt).
        Desk.changed(thread)
    }

    /** For the phone's own screen alone: something a paired computer did that it need not be told back. */
    fun changedOnPhone(thread: Long) { main.post { listener?.invoke(thread) } }
    fun prefsChanged() { main.post { prefsListener?.invoke() } }
}

/** Mutable where the system adds its result extras to the intent it sends back (Android 12 asks that it be said). */
private val MUTABLE = PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT

private fun smsManager(context: Context, subId: Int): SmsManager {
    val base = context.getSystemService(SmsManager::class.java)
    return if (subId != SubscriptionManager.INVALID_SUBSCRIPTION_ID && subId >= 0) base.createForSubscriptionId(subId) else base
}

private fun defaultSub(): Int = SubscriptionManager.getDefaultSmsSubscriptionId()

object Sender {
    /**
     * Sends [body] to [addresses]: one person is an SMS (in as many parts as it takes), several are one group MMS,
     * and pictures ([attachments], content URIs) make it an MMS too. Returns the conversation.
     */
    /**
     * Sends one of the app's stickers (Matt, 2026-11-13: "generate 4 sticker packs using our ghost mascot") to
     * [addresses] as a picture message. [picture] is the sticker as the app keeps it (a WebP with a clear
     * background); it goes as a PNG, which every phone's texting app can show and which keeps the clear background a
     * photograph's JPEG would paint black. Its name, `ghost-sticker-…`, is how this app knows to draw it as a sticker
     * and not a photograph. Returns the conversation.
     */
    fun sendSticker(context: Context, addresses: List<String>, picture: ByteArray, name: String): Long {
        val store = Store(context)
        val clean = addresses.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
        require(clean.isNotEmpty()) { "No one to send to" }
        val thread = store.threadFor(clean)
        val sub = defaultSub()
        val config = try { smsManager(context, sub).carrierConfigValues } catch (_: Exception) { Bundle() }
        val budget = config.getInt(SmsManager.MMS_CONFIG_MAX_MESSAGE_SIZE, 300 * 1024).coerceAtLeast(100 * 1024) - 8 * 1024
        var bitmap = BitmapFactory.decodeByteArray(picture, 0, picture.size) ?: throw IllegalStateException("That sticker could not be read")
        var png: ByteArray
        while (true) {
            val out = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            png = out.toByteArray()
            if (png.size <= budget || bitmap.width < 160) break
            bitmap = Bitmap.createScaledBitmap(bitmap, (bitmap.width * 0.8).toInt(), (bitmap.height * 0.8).toInt(), true)
        }
        val file = Stickers.file(name)
        sendMms(context, store, thread, clean, "", emptyList(), listOf(Pdu.Part("image/png", png, name = file, contentLocation = file, contentId = "sticker")))
        Bus.changed(thread)
        return thread
    }

    /** The most a message may weigh on this phone's carrier, less room for its own headers: what a voice message may fill. */
    fun voiceBudget(context: Context): Long {
        val config = try { smsManager(context, defaultSub()).carrierConfigValues } catch (_: Exception) { Bundle() }
        return (config.getInt(SmsManager.MMS_CONFIG_MAX_MESSAGE_SIZE, 300 * 1024).coerceAtLeast(100 * 1024) - 8 * 1024).toLong()
    }

    /**
     * Sends a voice message (Voice.kt) to [addresses]: the recording in [file], as an MMS with one audio part, which
     * any phone can play. It goes as a picture does, so it is not encrypted. Returns the conversation.
     */
    fun sendVoice(context: Context, addresses: List<String>, file: File): Long {
        val store = Store(context)
        val clean = addresses.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
        require(clean.isNotEmpty()) { "No one to send to" }
        val bytes = file.readBytes()
        require(bytes.size <= voiceBudget(context) + 8 * 1024) { "That recording is too long for a message on this carrier" }
        val thread = store.threadFor(clean)
        sendMms(context, store, thread, clean, "", emptyList(), listOf(Pdu.Part("audio/mp4", bytes, name = file.name, contentLocation = file.name, contentId = "voice")))
        Bus.changed(thread)
        return thread
    }

    /**
     * Sends a picture message that did not go once more, as it was: its pictures, stickers, sound and words read back
     * from where they are kept ([body], where given, in place of its words). The one that failed is removed only once
     * the new one is on its way, so a voice message that could not go is never lost to trying again.
     */
    fun sendAgain(context: Context, id: Long, addresses: List<String>, body: String? = null): Long {
        val store = Store(context)
        val clean = addresses.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
        require(clean.isNotEmpty()) { "No one to send to" }
        val kept = store.partsToSendAgain(id, body)
        require(kept.isNotEmpty()) { "What that message held is no longer on this phone" }
        val thread = store.threadFor(clean)
        sendMms(context, store, thread, clean, "", emptyList(), kept)
        // The one that failed goes, and why it failed with it (MmsDiag keeps that by its row).
        MmsDiag.cleared(context, Uri.withAppendedPath(Telephony.Mms.CONTENT_URI, id.toString()))
        store.deleteMessage("mms", id)
        Bus.changed(thread)
        return thread
    }

    fun send(context: Context, addresses: List<String>, body: String, attachments: List<String> = emptyList(), plain: Boolean = false): Long {
        val store = Store(context)
        val clean = addresses.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
        require(clean.isNotEmpty()) { "No one to send to" }
        val thread = store.threadFor(clean)
        // To one person with encryption on, the words go sealed (E2e), and are kept sealed in the SMS database.
        if (clean.size == 1 && attachments.isEmpty()) {
            var text = if (plain) body else (E2e.wire(context, clean[0], body) ?: body)
            // Not sealed, so nothing is exchanged with them yet: the invisible hello rides on the text where it costs
            // nothing (the same number of SMS with it as without), so their copy of the app, if they have one, knows.
            if (!plain && text == body && GhostMark.mayCarry(text) && E2e.wantsMark(context, clean[0]) && sameCost(text, GhostMark.add(text))) {
                text = GhostMark.add(text)
                E2e.marked(context, clean[0])
            }
            sendSms(context, store, thread, clean[0], text)
        } else sendMms(context, store, thread, clean, body, attachments)
        Bus.changed(thread)
        return thread
    }

    /** Whether [b] goes as the same number of SMS as [a]. */
    private fun sameCost(a: String, b: String): Boolean = try {
        android.telephony.SmsMessage.calculateLength(a, false)[0] == android.telephony.SmsMessage.calculateLength(b, false)[0]
    } catch (_: Exception) { false }

    private fun sendSms(context: Context, store: Store, thread: Long, address: String, body: String) {
        val sub = defaultSub()
        val row = store.insertSmsOutbox(thread, address, body, sub) ?: throw IllegalStateException("Could not save the message")
        val sms = smsManager(context, sub)
        val parts = sms.divideMessage(body)
        val sent = ArrayList<PendingIntent>()
        val delivered = ArrayList<PendingIntent>()
        for (i in parts.indices) {
            val code = (row.toString() + i).hashCode()
            // Only the last part's result marks the message: the others would race it.
            val last = i == parts.size - 1
            // Delivery reports are asked for unless switched off in Settings › Receipts.
            sent += PendingIntent.getBroadcast(context, code, Intent(context, SmsStatusReceiver::class.java).apply {
                action = if (last) SmsStatusReceiver.SENT else SmsStatusReceiver.SENT_PART
                data = row
            }, MUTABLE)
            delivered += PendingIntent.getBroadcast(context, code + 1, Intent(context, SmsStatusReceiver::class.java).apply {
                action = if (last) SmsStatusReceiver.DELIVERED else SmsStatusReceiver.DELIVERED_PART
                data = row
            }, MUTABLE)
        }
        try {
            val reports = context.getSharedPreferences("ui", Context.MODE_PRIVATE).getString("delivery_reports", "on") != "off"
            if (parts.size == 1) sms.sendTextMessage(address, null, body, sent[0], if (reports) delivered[0] else null)
            else sms.sendMultipartTextMessage(address, null, parts, sent, if (reports) delivered else null)
        } catch (e: Exception) {
            Log.e(TAG, "send failed", e)
            store.setSmsType(row, Telephony.Sms.MESSAGE_TYPE_FAILED)
        }
    }

    private fun sendMms(context: Context, store: Store, thread: Long, to: List<String>, body: String, attachments: List<String>, ready: List<Pdu.Part> = emptyList()) {
        val sub = defaultSub()
        val sms = smsManager(context, sub)
        val config = try { sms.carrierConfigValues } catch (_: Exception) { Bundle() }
        val maxBytes = config.getInt(SmsManager.MMS_CONFIG_MAX_MESSAGE_SIZE, 300 * 1024).coerceAtLeast(100 * 1024)
        // [ready]: parts that go as they are (a sticker, already a PNG that fits).
        val parts = ArrayList<Pdu.Part>(ready)
        val budget = (maxBytes - 8 * 1024 - body.toByteArray().size) / attachments.size.coerceAtLeast(1)
        attachments.forEachIndexed { i, a ->
            val bytes = compressImage(context, Uri.parse(a), budget) ?: return@forEachIndexed
            parts += Pdu.Part("image/jpeg", bytes, name = "image$i.jpg", contentLocation = "image$i.jpg", contentId = "image$i")
        }
        if (body.isNotEmpty()) parts += Pdu.Part("text/plain", body.toByteArray(), contentLocation = "text0.txt", contentId = "text0")
        val row = store.insertMms(Telephony.Mms.MESSAGE_BOX_OUTBOX, thread, null, to, emptyList(), parts, System.currentTimeMillis() / 1000, null, null, null, sub)
            ?: throw IllegalStateException("Could not save the message")
        // Delivery reports are asked for always; read reports unless switched off in Settings (few phones answer).
        val wantRead = context.getSharedPreferences("ui", Context.MODE_PRIVATE).getString("read_reports", "on") != "off"
        val wantDelivery = context.getSharedPreferences("ui", Context.MODE_PRIVATE).getString("delivery_reports", "on") != "off"
        val pdu = Pdu.sendReq(to, parts, deliveryReport = wantDelivery, readReport = wantRead)
        val file = File(MmsFileProvider.dir(context), "send-${System.nanoTime()}.pdu")
        file.writeBytes(pdu)
        val uri = MmsFileProvider.uriFor(context, file)
        val sent = PendingIntent.getBroadcast(context, row.hashCode(), Intent(context, MmsResultReceiver::class.java).apply {
            action = MmsResultReceiver.SENT
            data = row
            putExtra("file", file.absolutePath)
        }, MUTABLE)
        MmsDiag.cleared(context, row)
        try {
            sms.sendMultimediaMessage(context, uri, null, null, sent)
        } catch (e: Exception) {
            Log.e(TAG, "mms send failed", e)
            store.setMmsBox(row, Telephony.Mms.MESSAGE_BOX_FAILED)
            val why = "Android wouldn't take it (${e.message ?: e.javaClass.simpleName})"
            MmsDiag.failed(context, row, why)
            MmsDiag.note(context, "send", false, "$why, ${pdu.size / 1024} KB")
            file.delete()
        }
    }

    /** A picture as a JPEG that fits in [budget] bytes: scaled down and squeezed until it does. */
    private fun compressImage(context: Context, uri: Uri, budget: Int): ByteArray? {
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            var sample = 1
            while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 2048) sample *= 2
            var bmp = context.contentResolver.openInputStream(uri)?.use {
                BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample })
            } ?: return null
            bmp = rotated(context, uri, bmp)
            var side = 1600
            var quality = 85
            while (true) {
                val scale = side.toFloat() / maxOf(bmp.width, bmp.height)
                val b = if (scale < 1f) Bitmap.createScaledBitmap(bmp, (bmp.width * scale).toInt(), (bmp.height * scale).toInt(), true) else bmp
                val out = ByteArrayOutputStream()
                b.compress(Bitmap.CompressFormat.JPEG, quality, out)
                if (out.size() <= budget || side < 320) return out.toByteArray()
                if (quality > 55) quality -= 10 else side = (side * 0.75).toInt()
            }
            @Suppress("UNREACHABLE_CODE") null
        } catch (e: Exception) { Log.e(TAG, "image", e); null }
    }

    private fun rotated(context: Context, uri: Uri, bmp: Bitmap): Bitmap = try {
        val exif = context.contentResolver.openInputStream(uri)?.use { android.media.ExifInterface(it) }
        val deg = when (exif?.getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION, 1)) {
            android.media.ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            android.media.ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            android.media.ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> 0f
        }
        if (deg == 0f) bmp else Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, android.graphics.Matrix().apply { postRotate(deg) }, true)
    } catch (_: Exception) { bmp }
}

/** An SMS sent, or delivered: the row in the provider says so. */
class SmsStatusReceiver : BroadcastReceiver() {
    companion object {
        const val SENT = "ghost.SMS_SENT"
        const val SENT_PART = "ghost.SMS_SENT_PART"
        const val DELIVERED = "ghost.SMS_DELIVERED"
        const val DELIVERED_PART = "ghost.SMS_DELIVERED_PART"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val row = intent.data ?: return
        val store = Store(context)
        when (intent.action) {
            SENT -> {
                if (resultCode == Activity.RESULT_OK) store.setSmsType(row, Telephony.Sms.MESSAGE_TYPE_SENT)
                else {
                    store.setSmsType(row, Telephony.Sms.MESSAGE_TYPE_FAILED, resultCode)
                    Notifier.failed(context, store.threadOfSms(row))
                }
            }
            SENT_PART -> if (resultCode != Activity.RESULT_OK) store.setSmsType(row, Telephony.Sms.MESSAGE_TYPE_FAILED, resultCode)
            DELIVERED -> store.setSmsStatus(row, Telephony.Sms.STATUS_COMPLETE)
        }
        Bus.changed(store.threadOfSms(row))
    }
}

/** Incoming SMS, delivered to the default SMS app alone: it is this app's to keep. */
class SmsDeliverReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (messages.isEmpty()) return
        val address = messages[0].displayOriginatingAddress ?: messages[0].originatingAddress ?: return
        val body = messages.joinToString("") { it.displayMessageBody ?: it.messageBody ?: "" }
        val sub = intent.getIntExtra("android.telephony.extra.SUBSCRIPTION_INDEX", intent.getIntExtra("subscription", -1))
        val store = Store(context)
        val row = store.insertSmsInbox(address, body, System.currentTimeMillis(), messages[0].timestampMillis, sub) ?: return
        // Someone's encryption key: kept, and the conversation moves on (E2e.received).
        val key = E2eCrypto.keyIn(body)
        key?.let { try { E2e.received(context, address, it) } catch (e: Exception) { Log.e(TAG, "e2e key", e) } }
        // The invisible hello of another copy of the app: they have it, and their conversation now offers encryption
        // in a banner (the screen asks E2e.state). Nothing is sent because of it.
        try { if (GhostMark.has(body)) Backgrounds.sawGhost(context, address) } catch (e: Exception) { Log.e(TAG, "ghost mark", e) }
        val thread = store.threadOfSms(row)
        // A text only Ghost Messaging writes: they have the app. And a chat background, sealed or not, is worn.
        try {
            if (Backgrounds.isGhostText(body)) Backgrounds.sawGhost(context, address)
            BackgroundWire.valueIn(E2e.read(context, address, body).first)?.let {
                Backgrounds.sawGhost(context, address)
                Backgrounds.received(context, thread, it)
            }
        } catch (e: Exception) { Log.e(TAG, "shared background", e) }
        store.setArchived(thread, false)
        Notifier.incoming(context, thread)
        // A paired computer hears of it through the service, which Android may have stopped since: a text arriving is
        // one of the few moments it lets a stopped app start one again.
        DeskService.sync(context)
        Bus.changed(thread)
        // A sign-in code: Ghost Keyboard, if it is watching, asks for it now (Codes.kt).
        try { Codes.arrived(context, E2e.read(context, address, body).first) } catch (e: Exception) { Log.e(TAG, "code", e) }
    }
}

/**
 * An MMS's notification (WAP push): the message itself waits at the carrier's MMSC, to be fetched. Android fetches
 * it into our file ([MmsFileProvider]) and tells [MmsResultReceiver].
 */
class MmsPushReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val data = intent.getByteArrayExtra("data") ?: return
        val sub = intent.getIntExtra("android.telephony.extra.SUBSCRIPTION_INDEX", intent.getIntExtra("subscription", defaultSub()))
        val ind = try { Pdu.parse(data) } catch (e: Exception) { Log.e(TAG, "push", e); return }
        // A report on a message of ours: delivered to someone's phone, or read on it.
        if (ind.type == Pdu.DELIVERY_IND || ind.type == Pdu.READ_ORIG_IND) {
            val id = ind.messageId ?: return
            val store = Store(context)
            val state = when {
                ind.type == Pdu.READ_ORIG_IND -> if (ind.readStatus == null || ind.readStatus == 0x80) "read" else null
                ind.status == 0x81 -> "delivered" // retrieved
                else -> null
            }
            if (state != null) { store.setReceipt(id, state); Bus.changed(-1) }
            return
        }
        if (ind.type != Pdu.NOTIFICATION_IND || ind.contentLocation == null) return
        // The announcement is kept in the sender's conversation until the picture is here: if it cannot be brought
        // down, that is where it is shown, with a way to try again.
        val store = Store(context)
        val from = ind.from?.takeIf { it.isNotBlank() && !it.contains("insert-address-token", ignoreCase = true) }
        val notice = if (from == null) null else try {
            store.insertMmsNotice(store.threadFor(listOf(from)), from, ind.contentLocation, ind.transactionId, sub)
        } catch (e: Exception) { Log.e(TAG, "notice", e); null }
        if (notice != null) Bus.changed(store.threadOfMms(notice))
        download(context, ind.contentLocation, ind.transactionId, sub, notice)
    }

    companion object {
        /** Asks Android to fetch the picture message waiting at [location]. [notice]: its announcement's row, if kept. */
        fun download(context: Context, location: String, transactionId: String?, sub: Int, notice: Uri? = null) {
            val file = File(MmsFileProvider.dir(context), "recv-${System.nanoTime()}.pdu")
            val uri = MmsFileProvider.uriFor(context, file)
            val done = PendingIntent.getBroadcast(context, file.name.hashCode(), Intent(context, MmsResultReceiver::class.java).apply {
                action = MmsResultReceiver.DOWNLOADED
                putExtra("file", file.absolutePath)
                putExtra("location", location)
                putExtra("tid", transactionId)
                putExtra("sub", sub)
                if (notice != null) putExtra("notice", notice.toString())
            }, MUTABLE)
            // It waits from now until it has come: a fetch that fails is asked for again (retryWaiting).
            MmsDiag.fetching(context, location, transactionId, sub)
            try {
                smsManager(context, sub).downloadMultimediaMessage(context, location, uri, null, done)
            } catch (e: Exception) {
                Log.e(TAG, "download", e)
                MmsDiag.note(context, "download", false, "Android wouldn't fetch it (${e.message ?: e.javaClass.simpleName})")
                failed(context, notice)
            }
        }

        /** The picture could not be brought down: its announcement says so in its conversation, and a notification leads there. */
        fun failed(context: Context, notice: Uri?) {
            val store = Store(context)
            val thread = notice?.let {
                try { store.setMmsNoticeDownloading(it, false); store.threadOfMms(it) } catch (e: Exception) { Log.e(TAG, "notice", e); null }
            }
            Notifier.downloadFailed(context, thread)
            if (thread != null) Bus.changed(thread)
        }

        /** Try again, from the conversation: the picture message announced as [id] is asked for once more. */
        fun retry(context: Context, id: Long) {
            val store = Store(context)
            val (location, transactionId, sub) = store.mmsNotice(id) ?: throw IllegalStateException("That picture is no longer waiting")
            val notice = Uri.withAppendedPath(Telephony.Mms.CONTENT_URI, id.toString())
            store.setMmsNoticeDownloading(notice, true)
            Bus.changed(store.threadOfMms(notice))
            download(context, location, transactionId, if (sub >= 0) sub else defaultSub(), notice)
        }

        /**
         * Asks again for the picture messages announced and never fetched. Answers how many were asked for. One whose
         * announcement is kept in its conversation is asked for as that one, so the conversation follows it.
         */
        fun retryWaiting(context: Context): Int {
            val all = MmsDiag.worthRetrying(context)
            val store = Store(context)
            for (w in all) {
                val notice = try { store.mmsNoticeAt(w.location) } catch (e: Exception) { Log.e(TAG, "notice", e); null }
                if (notice != null) {
                    try { store.setMmsNoticeDownloading(notice, true); Bus.changed(store.threadOfMms(notice)) } catch (e: Exception) { Log.e(TAG, "notice", e) }
                }
                download(context, w.location, w.transactionId, if (w.sub >= 0) w.sub else defaultSub(), notice)
            }
            return all.size
        }
    }
}

/** An MMS sent (or not), or one downloaded: written into the provider and shown. */
class MmsResultReceiver : BroadcastReceiver() {
    companion object {
        const val SENT = "ghost.MMS_SENT"
        const val DOWNLOADED = "ghost.MMS_DOWNLOADED"
        const val ACK = "ghost.MMS_ACK"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val file = intent.getStringExtra("file")?.let { File(it) }
        val store = Store(context)
        when (intent.action) {
            SENT -> {
                val row = intent.data ?: return
                val size = file?.takeIf { it.exists() }?.length()?.let { ", ${it / 1024} KB" } ?: ""
                // The carrier's answer: it names the message (its delivery and read reports come back under that
                // name), and it says whether the message was accepted. Android calls a message sent once the
                // carrier's server has answered at all; an answer that refuses it is a message that did not go.
                val conf = try { intent.getByteArrayExtra(SmsManager.EXTRA_MMS_DATA)?.takeIf { it.isNotEmpty() }?.let { Pdu.parse(it) } } catch (e: Exception) { Log.w(TAG, "send-conf", e); null }
                val refused = if (resultCode == Activity.RESULT_OK) MmsWhy.refused(conf?.responseStatus, conf?.responseText) else null
                if (resultCode == Activity.RESULT_OK && refused == null) {
                    store.setMmsBox(row, Telephony.Mms.MESSAGE_BOX_SENT)
                    if (!conf?.messageId.isNullOrBlank()) store.setMmsMessageId(row, conf!!.messageId!!)
                    MmsDiag.cleared(context, row)
                    MmsDiag.note(context, "send", true, "sent$size")
                } else {
                    val why = refused ?: MmsWhy.send(resultCode, intent.getIntExtra(SmsManager.EXTRA_MMS_HTTP_STATUS, 0))
                    Log.w(TAG, "mms send result $resultCode: $why")
                    store.setMmsBox(row, Telephony.Mms.MESSAGE_BOX_FAILED)
                    MmsDiag.failed(context, row, why)
                    MmsDiag.note(context, "send", false, "$why$size")
                    Notifier.failed(context, store.threadOfMms(row))
                }
                file?.delete()
                Bus.changed(store.threadOfMms(row))
            }
            DOWNLOADED -> {
                val sub = intent.getIntExtra("sub", defaultSub())
                val bytes = file?.takeIf { it.exists() }?.readBytes()
                file?.delete()
                val notice = intent.getStringExtra("notice")?.let { Uri.parse(it) }
                val location = intent.getStringExtra("location")
                if (resultCode != Activity.RESULT_OK || bytes == null || bytes.isEmpty()) {
                    val http = intent.getIntExtra(SmsManager.EXTRA_MMS_HTTP_STATUS, 0)
                    val why = if (resultCode == Activity.RESULT_OK) "the carrier sent nothing" else MmsWhy.download(resultCode, http)
                    Log.w(TAG, "mms download result $resultCode: $why")
                    MmsDiag.note(context, "download", false, why)
                    // One the carrier no longer has will never come; any other waits and is asked for again.
                    if (http == 404 || http == 410) MmsDiag.fetched(context, location)
                    // Its announcement says so in its conversation, with Try again, and the notification leads there.
                    MmsPushReceiver.failed(context, notice)
                    return
                }
                MmsDiag.fetched(context, location)
                MmsDiag.note(context, "download", true, "fetched, ${bytes.size / 1024} KB")
                val pending = goAsync()
                Thread {
                    try {
                        if (keep(context, store, bytes, intent.getStringExtra("tid"), sub)) {
                            // The picture is here: its announcement has done its work.
                            notice?.let { val thread = store.threadOfMms(it); store.deleteMms(it); Bus.changed(thread) }
                        } else MmsPushReceiver.failed(context, notice)
                    } catch (e: Exception) { Log.e(TAG, "keep", e); MmsPushReceiver.failed(context, notice) }
                    finally { pending.finish() }
                }.start()
            }
            ACK -> file?.delete()
        }
    }

    /** Keeps the picture message in [bytes]; false where they are no picture message, or it could not be kept. */
    private fun keep(context: Context, store: Store, bytes: ByteArray, notificationTid: String?, sub: Int): Boolean {
        val m = Pdu.parse(bytes)
        if (m.type != Pdu.RETRIEVE_CONF) return false
        val own = store.ownNumbers()
        val from = m.from ?: ""
        // The people of the conversation: the sender and everyone else it went to, never this phone. With no number
        // of its own known, a message to one address is taken to be to this phone alone.
        val others = (m.to + m.cc).filter { !store.isOwn(it, own) }
        val people = if (m.to.size + m.cc.size <= 1) listOf(from) else (listOf(from) + others)
        val unique = people.filter { it.isNotBlank() }.distinctBy { it.filter(Char::isDigit).takeLast(10).ifEmpty { it } }
        val thread = store.threadFor(unique.ifEmpty { listOf(from) })
        val row = store.insertMms(
            Telephony.Mms.MESSAGE_BOX_INBOX, thread, from, m.to, m.cc, m.parts,
            m.date ?: (System.currentTimeMillis() / 1000), m.subject, m.messageId, m.transactionId ?: notificationTid, sub,
        )
        if (row != null) {
            // A chat background shared by someone here with the app: the message's picture, or what its words name.
            try {
                val words = m.parts.filter { it.contentType.startsWith("text/plain") }.joinToString("\n") { String(it.data, Charsets.UTF_8) }
                BackgroundWire.valueIn(words)?.let { value ->
                    Backgrounds.sawGhost(context, from)
                    Backgrounds.received(context, thread, value, m.parts.firstOrNull { it.contentType.startsWith("image/") }?.data)
                }
            } catch (e: Exception) { Log.e(TAG, "shared background", e) }
            store.setArchived(thread, false)
            Notifier.incoming(context, thread)
            Bus.changed(thread)
        }
        // Tell the MMSC it came down, or it may send the notification again.
        val tid = notificationTid ?: m.transactionId ?: return row != null
        try {
            val ack = File(MmsFileProvider.dir(context), "ack-${System.nanoTime()}.pdu")
            ack.writeBytes(Pdu.notifyRespInd(tid))
            val pi = PendingIntent.getBroadcast(context, ack.name.hashCode(), Intent(context, MmsResultReceiver::class.java).apply {
                action = ACK; putExtra("file", ack.absolutePath)
            }, MUTABLE)
            smsManager(context, sub).sendMultimediaMessage(context, MmsFileProvider.uriFor(context, ack), null, null, pi)
        } catch (e: Exception) { Log.w(TAG, "ack", e) }
        return row != null
    }
}

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
    private val main = Handler(Looper.getMainLooper())
    fun changed(thread: Long) { main.post { listener?.invoke(thread) } }
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
    fun send(context: Context, addresses: List<String>, body: String, attachments: List<String> = emptyList(), plain: Boolean = false): Long {
        val store = Store(context)
        val clean = addresses.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
        require(clean.isNotEmpty()) { "No one to send to" }
        val thread = store.threadFor(clean)
        // To one person with encryption on, the words go sealed (E2e), and are kept sealed in the SMS database.
        if (clean.size == 1 && attachments.isEmpty()) sendSms(context, store, thread, clean[0], if (plain) body else (E2e.wire(context, clean[0], body) ?: body))
        else sendMms(context, store, thread, clean, body, attachments)
        Bus.changed(thread)
        return thread
    }

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

    private fun sendMms(context: Context, store: Store, thread: Long, to: List<String>, body: String, attachments: List<String>) {
        val sub = defaultSub()
        val sms = smsManager(context, sub)
        val config = try { sms.carrierConfigValues } catch (_: Exception) { Bundle() }
        val maxBytes = config.getInt(SmsManager.MMS_CONFIG_MAX_MESSAGE_SIZE, 300 * 1024).coerceAtLeast(100 * 1024)
        val parts = ArrayList<Pdu.Part>()
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
        try {
            sms.sendMultimediaMessage(context, uri, null, null, sent)
        } catch (e: Exception) {
            Log.e(TAG, "mms send failed", e)
            store.setMmsBox(row, Telephony.Mms.MESSAGE_BOX_FAILED)
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
        E2eCrypto.keyIn(body)?.let { key -> try { E2e.received(context, address, key) } catch (e: Exception) { Log.e(TAG, "e2e key", e) } }
        val thread = store.threadOfSms(row)
        store.setArchived(thread, false)
        Notifier.incoming(context, thread)
        Bus.changed(thread)
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
        download(context, ind.contentLocation, ind.transactionId, sub)
    }

    companion object {
        fun download(context: Context, location: String, transactionId: String?, sub: Int) {
            val file = File(MmsFileProvider.dir(context), "recv-${System.nanoTime()}.pdu")
            val uri = MmsFileProvider.uriFor(context, file)
            val done = PendingIntent.getBroadcast(context, file.name.hashCode(), Intent(context, MmsResultReceiver::class.java).apply {
                action = MmsResultReceiver.DOWNLOADED
                putExtra("file", file.absolutePath)
                putExtra("location", location)
                putExtra("tid", transactionId)
                putExtra("sub", sub)
            }, MUTABLE)
            try {
                smsManager(context, sub).downloadMultimediaMessage(context, location, uri, null, done)
            } catch (e: Exception) {
                Log.e(TAG, "download", e)
                Notifier.downloadFailed(context)
            }
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
                if (resultCode == Activity.RESULT_OK) {
                    store.setMmsBox(row, Telephony.Mms.MESSAGE_BOX_SENT)
                    // The MMSC's answer names the message: its delivery and read reports come back under that name.
                    try {
                        val conf = intent.getByteArrayExtra(SmsManager.EXTRA_MMS_DATA)
                        val id = conf?.let { Pdu.parse(it).messageId }
                        if (!id.isNullOrBlank()) store.setMmsMessageId(row, id)
                    } catch (e: Exception) { Log.w(TAG, "send-conf", e) }
                } else {
                    Log.w(TAG, "mms send result $resultCode")
                    store.setMmsBox(row, Telephony.Mms.MESSAGE_BOX_FAILED)
                    Notifier.failed(context, store.threadOfMms(row))
                }
                file?.delete()
                Bus.changed(store.threadOfMms(row))
            }
            DOWNLOADED -> {
                val sub = intent.getIntExtra("sub", defaultSub())
                val bytes = file?.takeIf { it.exists() }?.readBytes()
                file?.delete()
                if (resultCode != Activity.RESULT_OK || bytes == null || bytes.isEmpty()) {
                    Log.w(TAG, "mms download result $resultCode")
                    Notifier.downloadFailed(context)
                    return
                }
                val pending = goAsync()
                Thread {
                    try { keep(context, store, bytes, intent.getStringExtra("tid"), sub) } catch (e: Exception) { Log.e(TAG, "keep", e) }
                    finally { pending.finish() }
                }.start()
            }
            ACK -> file?.delete()
        }
    }

    private fun keep(context: Context, store: Store, bytes: ByteArray, notificationTid: String?, sub: Int) {
        val m = Pdu.parse(bytes)
        if (m.type != Pdu.RETRIEVE_CONF) return
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
            store.setArchived(thread, false)
            Notifier.incoming(context, thread)
            Bus.changed(thread)
        }
        // Tell the MMSC it came down, or it may send the notification again.
        val tid = notificationTid ?: m.transactionId ?: return
        try {
            val ack = File(MmsFileProvider.dir(context), "ack-${System.nanoTime()}.pdu")
            ack.writeBytes(Pdu.notifyRespInd(tid))
            val pi = PendingIntent.getBroadcast(context, ack.name.hashCode(), Intent(context, MmsResultReceiver::class.java).apply {
                action = ACK; putExtra("file", ack.absolutePath)
            }, MUTABLE)
            smsManager(context, sub).sendMultimediaMessage(context, MmsFileProvider.uriFor(context, ack), null, null, pi)
        } catch (e: Exception) { Log.w(TAG, "ack", e) }
    }
}

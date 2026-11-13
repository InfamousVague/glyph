package com.infamousvague.ghostmessaging

import android.app.IntentService
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.Telephony
import java.io.File

/** Notifications: one per conversation, its newest messages in it, with Reply and Mark as read. */
object Notifier {
    private const val CHANNEL = "messages"
    private const val CHANNEL_ALERTS = "alerts"
    const val EXTRA_THREAD = "thread"
    const val KEY_REPLY = "reply"

    private fun manager(context: Context): NotificationManager {
        val nm = context.getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Messages", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "New text messages"
                enableVibration(true)
            })
            nm.createNotificationChannel(NotificationChannel(CHANNEL_ALERTS, "Problems", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "A message that could not be sent or downloaded"
            })
        }
        return nm
    }

    private fun open(context: Context, thread: Long): PendingIntent =
        PendingIntent.getActivity(context, thread.toInt(), Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            putExtra(EXTRA_THREAD, thread)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

    fun incoming(context: Context, thread: Long) {
        if (thread < 0) return
        if (MainActivity.openThread == thread && MainActivity.inFront) return
        val store = Store(context)
        if (store.isMuted(thread)) return
        val people = store.threadPeople(thread)
        val unread = store.messages(thread, 8).filter { !(it["outgoing"] as Boolean) && !(it["read"] as Boolean) }.reversed()
        if (unread.isEmpty()) { cancel(context, thread); return }
        val ui = context.getSharedPreferences("ui", Context.MODE_PRIVATE)
        val previews = ui.getString("notif_preview", "on") != "off"
        val group = people.size > 1
        val title = people.joinToString(", ") { (it["name"] as String?) ?: (it["address"] as String) }
        val me = Person.Builder().setName("You").build()
        val style = Notification.MessagingStyle(me).setGroupConversation(group)
        if (group) style.conversationTitle = title
        for (m in unread) {
            val addr = (m["address"] as String).ifEmpty { (people.firstOrNull()?.get("address") as String?) ?: "" }
            val c = store.contact(addr)
            val sender = Person.Builder().setName((c["name"] as String?) ?: addr).setKey(addr).build()
            var body = m["body"] as String
            when (m["notice"]) {
                "key" -> body = "Sent an encryption key. Open to turn encryption on."
                "undecryptable" -> body = "Encrypted message"
            }
            if (!previews && m["notice"] == null) body = "New message"
            @Suppress("UNCHECKED_CAST") val parts = m["parts"] as List<Map<String, Any?>>? ?: emptyList()
            if (body.isBlank()) body = if (parts.any { (it["type"] as String).startsWith("image/") }) "📷 Picture" else "Attachment"
            style.addMessage(Notification.MessagingStyle.Message(body, m["date"] as Long, sender))
        }

        val reply = Notification.Action.Builder(
            Icon.createWithResource(context, android.R.drawable.ic_menu_send), "Reply",
            PendingIntent.getBroadcast(context, thread.toInt(), Intent(context, NotificationActionReceiver::class.java).apply {
                action = NotificationActionReceiver.REPLY; putExtra(EXTRA_THREAD, thread)
            }, PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
        ).addRemoteInput(RemoteInput.Builder(KEY_REPLY).setLabel("Message").build())
            .setSemanticAction(Notification.Action.SEMANTIC_ACTION_REPLY)
            .setAllowGeneratedReplies(true)
            .build()
        val read = Notification.Action.Builder(
            Icon.createWithResource(context, android.R.drawable.ic_menu_view), "Mark as read",
            PendingIntent.getBroadcast(context, thread.toInt() + 1_000_000, Intent(context, NotificationActionReceiver::class.java).apply {
                action = NotificationActionReceiver.READ; putExtra(EXTRA_THREAD, thread)
            }, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
        ).setSemanticAction(Notification.Action.SEMANTIC_ACTION_MARK_AS_READ).build()

        // A sign-in code in the newest message gets a button that copies it.
        val code = if (previews && ui.getString("notif_code", "on") != "off") otp(unread.last()["body"] as String) else null

        val builder = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_ghost)
            .setStyle(style)
            .setContentIntent(open(context, thread))
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setColor(0xFF4F5BD5.toInt())
            .setShortcutId(null)
        if (code != null) {
            builder.addAction(Notification.Action.Builder(
                Icon.createWithResource(context, android.R.drawable.ic_menu_save), "Copy $code",
                PendingIntent.getBroadcast(context, thread.toInt() + 2_000_000, Intent(context, NotificationActionReceiver::class.java).apply {
                    action = NotificationActionReceiver.COPY; putExtra(EXTRA_THREAD, thread); putExtra("code", code)
                }, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
            ).build())
        }
        builder.addAction(reply).addAction(read)
        val n = builder.build()
        try { manager(context).notify(thread.toInt(), n) } catch (_: SecurityException) {}
    }

    private val codeWord = Regex("(?i)(code|passcode|password|pin|otp|verif|one[- ]time|2fa|login|log in|sign in|security)")
    private val codeDigits = Regex("(?<![\\w.,/-])(\\d{3}[- ]\\d{3}|\\d{4,8})(?![\\w/-]|[.,]\\d)")

    /** The sign-in code in [body], if it reads like one: 4 to 8 digits (or 123-456) in a text that speaks of a code. */
    fun otp(body: String): String? {
        if (body.length > 400 || !codeWord.containsMatchIn(body)) return null
        return codeDigits.find(body)?.value?.filter { it.isDigit() }
    }

    fun cancel(context: Context, thread: Long) {
        context.getSystemService(NotificationManager::class.java).cancel(thread.toInt())
    }

    fun failed(context: Context, thread: Long) {
        if (thread < 0) return
        val people = Store(context).threadPeople(thread)
        val who = people.joinToString(", ") { (it["name"] as String?) ?: (it["address"] as String) }
        val n = Notification.Builder(context, CHANNEL_ALERTS)
            .setSmallIcon(R.drawable.ic_stat_ghost)
            .setContentTitle("Message not sent")
            .setContentText(if (who.isEmpty()) "Tap to try again" else "To $who. Tap to try again.")
            .setContentIntent(open(context, thread))
            .setAutoCancel(true)
            .build()
        try { manager(context).notify(-thread.toInt() - 1, n) } catch (_: SecurityException) {}
    }

    fun downloadFailed(context: Context) {
        val n = Notification.Builder(context, CHANNEL_ALERTS)
            .setSmallIcon(R.drawable.ic_stat_ghost)
            .setContentTitle("A picture message couldn't be downloaded")
            .setContentText("Check mobile data is on. Your carrier will usually send it again.")
            .setAutoCancel(true)
            .build()
        try { manager(context).notify(42, n) } catch (_: SecurityException) {}
    }
}

class NotificationActionReceiver : BroadcastReceiver() {
    companion object {
        const val REPLY = "ghost.REPLY"
        const val READ = "ghost.READ"
        const val COPY = "ghost.COPY"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val thread = intent.getLongExtra(Notifier.EXTRA_THREAD, -1)
        if (thread < 0) return
        val store = Store(context)
        when (intent.action) {
            REPLY -> {
                val text = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(Notifier.KEY_REPLY)?.toString()?.trim()
                if (!text.isNullOrEmpty()) {
                    val people = store.threadPeople(thread).map { it["address"] as String }
                    if (people.isNotEmpty()) Sender.send(context, people, text)
                }
                store.markRead(thread)
                Notifier.cancel(context, thread)
            }
            READ -> {
                store.markRead(thread)
                Notifier.cancel(context, thread)
            }
            COPY -> {
                val code = intent.getStringExtra("code") ?: return
                val clip = context.getSystemService(android.content.ClipboardManager::class.java)
                clip.setPrimaryClip(android.content.ClipData.newPlainText("Code", code))
                store.markRead(thread)
                Notifier.cancel(context, thread)
            }
        }
        Bus.changed(thread)
    }
}

/** "Respond via message" from the incoming-call screen: send it, with no screen of our own. */
@Suppress("DEPRECATION")
class HeadlessSmsSendService : IntentService("HeadlessSmsSendService") {
    @Deprecated("IntentService")
    override fun onHandleIntent(intent: Intent?) {
        if (intent?.action != "android.intent.action.RESPOND_VIA_MESSAGE") return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
        val to = intent.data?.schemeSpecificPart?.substringBefore('?')?.split(',', ';')?.map { Uri.decode(it).trim() }?.filter { it.isNotEmpty() }.orEmpty()
        if (text.isEmpty() || to.isEmpty()) return
        try { Sender.send(this, to, text) } catch (_: Exception) {}
    }
}

/**
 * Files the phone process reads (an MMS to send) or writes (one it downloaded) by content URI. Android's MMS
 * service is granted the URI on our behalf by SmsManager, which is why it must be grantable.
 */
class MmsFileProvider : ContentProvider() {
    companion object {
        fun dir(context: Context): File = File(context.cacheDir, "mms").apply { mkdirs() }
        fun uriFor(context: Context, file: File): Uri = Uri.Builder().scheme("content").authority("${context.packageName}.mmsfiles").path(file.name).build()
    }

    override fun onCreate() = true

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor? {
        val ctx = context ?: return null
        val name = uri.lastPathSegment ?: return null
        if (name.contains('/') || name.contains("..")) return null
        val file = File(dir(ctx), name)
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.parseMode(mode))
    }

    override fun query(uri: Uri, p: Array<out String>?, s: String?, a: Array<out String>?, o: String?): Cursor? = null
    override fun getType(uri: Uri): String = "application/vnd.wap.mms-message"
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, s: String?, a: Array<out String>?) = 0
    override fun update(uri: Uri, v: ContentValues?, s: String?, a: Array<out String>?) = 0
}


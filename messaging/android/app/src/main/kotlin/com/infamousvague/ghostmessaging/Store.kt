package com.infamousvague.ghostmessaging

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.provider.ContactsContract
import android.provider.Telephony
import android.telephony.PhoneNumberUtils
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager

/**
 * Android's own SMS/MMS database (the Telephony provider), read and written as the default SMS app. Every message
 * lives there, not in this app: another SMS app picked later, or this one reinstalled, sees the same conversations.
 *
 * What goes to Flutter is plain maps and lists (the MethodChannel's StandardMessageCodec).
 */
class Store(private val context: Context) {
    private val resolver = context.contentResolver

    // --- people ------------------------------------------------------------------------------------------------------

    /**
     * Who a number is, kept until Android says the contacts have changed ([contactsChanged]): the list of
     * conversations is read again on every text that comes or goes, and asking Android for each person each time
     * was most of what that cost.
     */
    private val nameCache = java.util.concurrent.ConcurrentHashMap<String, Map<String, Any?>>()

    fun contactsChanged() { known = null; nameCache.clear() }

    /** One of the phone's contacts' numbers, as the contacts keep it. */
    private class Known(val number: String, val name: String?, val photo: String?)

    /** The contacts' numbers by [ContactKey], read once and kept until Android says the contacts changed. */
    @Volatile private var known: Map<String, List<Known>>? = null

    /**
     * Every contact's numbers in one question to Android (Matt, 2026-11-13: "Users with a ton of messages stored on
     * their phone are taking forever to load"). Looking each conversation's number up was a question apiece: with
     * three thousand conversations, most of the twenty seconds the list took to appear.
     */
    private fun knownNumbers(): Map<String, List<Known>> {
        known?.let { return it }
        if (!hasContacts()) return emptyMap()
        val out = HashMap<String, ArrayList<Known>>()
        try {
            val phone = ContactsContract.CommonDataKinds.Phone.CONTENT_URI
            resolver.query(phone, arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER, ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.PHOTO_THUMBNAIL_URI), null, null, null)?.use { c ->
                while (c.moveToNext()) {
                    val number = c.getString(0) ?: continue
                    val key = ContactKey.of(number) ?: continue
                    out.getOrPut(key) { ArrayList() } += Known(ContactKey.main(number), c.getString(1), c.getString(2))
                }
            }
        } catch (_: Exception) {
            return emptyMap()   // not kept: asked again the next time a name is wanted
        }
        known = out
        return out
    }

    /** The contact for [address]: their name and photo's URI where the phone has them. */
    fun contact(address: String): Map<String, Any?> {
        nameCache[address]?.let { return it }
        // A sender's name or an email address is nobody's phone number; a number is found among the contacts by its
        // last digits and then compared whole, as Android compares two numbers.
        val found = ContactKey.of(address)?.let { key -> knownNumbers()[key]?.firstOrNull { sameNumber(it.number, address) } }
        val out = mapOf("address" to address, "name" to found?.name, "photo" to found?.photo)
        nameCache[address] = out
        return out
    }

    fun clearContactCache() { known = null; nameCache.clear() }

    private fun hasContacts() = context.checkSelfPermission(android.Manifest.permission.READ_CONTACTS) == android.content.pm.PackageManager.PERMISSION_GRANTED

    /** Contacts with a phone number matching [query] (name or digits), for a new message's To. */
    fun searchContacts(query: String, limit: Int = 40): List<Map<String, Any?>> {
        if (!hasContacts()) return emptyList()
        val out = ArrayList<Map<String, Any?>>()
        val seen = HashSet<String>()
        val uri = if (query.isBlank()) ContactsContract.CommonDataKinds.Phone.CONTENT_URI
        else Uri.withAppendedPath(ContactsContract.CommonDataKinds.Phone.CONTENT_FILTER_URI, Uri.encode(query))
        try {
            resolver.query(
                uri,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    ContactsContract.CommonDataKinds.Phone.NUMBER,
                    ContactsContract.CommonDataKinds.Phone.PHOTO_THUMBNAIL_URI,
                    ContactsContract.CommonDataKinds.Phone.TYPE,
                    ContactsContract.CommonDataKinds.Phone.LABEL,
                ),
                null, null,
                if (query.isBlank()) "${ContactsContract.CommonDataKinds.Phone.TIMES_CONTACTED} DESC, ${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC" else null,
            )?.use { c ->
                while (c.moveToNext() && out.size < limit) {
                    val number = c.getString(1) ?: continue
                    val key = number.filter { it.isDigit() }.takeLast(10)
                    if (!seen.add(c.getString(0) + key)) continue
                    val label = ContactsContract.CommonDataKinds.Phone.getTypeLabel(context.resources, c.getInt(3), c.getString(4)).toString()
                    out += mapOf("name" to c.getString(0), "address" to number, "photo" to c.getString(2), "label" to label)
                }
            }
        } catch (_: Exception) {}
        return out
    }

    fun photo(uri: String): ByteArray? = try {
        resolver.openInputStream(Uri.parse(uri))?.use { it.readBytes() }
    } catch (_: Exception) { null }

    // --- this phone's own numbers ------------------------------------------------------------------------------------

    /** This phone's own numbers, to leave out of a group MMS's people. Empty when Android will not say. */
    fun ownNumbers(): Set<String> {
        val out = HashSet<String>()
        try {
            val sm = context.getSystemService(SubscriptionManager::class.java)
            val subs = sm.activeSubscriptionInfoList ?: emptyList()
            for (s in subs) {
                val n = if (android.os.Build.VERSION.SDK_INT >= 33) sm.getPhoneNumber(s.subscriptionId) else @Suppress("DEPRECATION") s.number
                if (!n.isNullOrBlank()) out += n
            }
        } catch (_: Exception) {}
        try {
            @Suppress("DEPRECATION", "MissingPermission")
            val n = context.getSystemService(TelephonyManager::class.java).line1Number
            if (!n.isNullOrBlank()) out += n
        } catch (_: Exception) {}
        val saved = context.getSharedPreferences("ghost", Context.MODE_PRIVATE).getString("own_number", null)
        if (!saved.isNullOrBlank()) out += saved
        return out
    }

    fun isOwn(address: String, own: Set<String>): Boolean = own.any { sameNumber(it, address) }

    // --- conversations -----------------------------------------------------------------------------------------------

    private val canonical = java.util.concurrent.ConcurrentHashMap<Long, String>()
    @Volatile private var canonicalRead = false

    /** Every address Android keeps for conversations, in one question: each conversation's own was one apiece. */
    private fun readCanonical() {
        if (canonicalRead) return
        try {
            resolver.query(Uri.parse("content://mms-sms/canonical-addresses"), null, null, null, null)?.use { c ->
                val iId = c.getColumnIndex("_id"); val iAddress = c.getColumnIndex("address")
                if (iId >= 0 && iAddress >= 0) while (c.moveToNext()) c.getString(iAddress)?.let { canonical[c.getLong(iId)] = it }
            }
        } catch (_: Exception) {}   // a store that will not list them is asked for each, below
        canonicalRead = true
    }

    private fun canonicalAddress(id: Long): String? {
        canonical[id]?.let { return it }
        // One that is not in the list read at the start: a conversation begun since, or a store that lists none.
        resolver.query(Uri.parse("content://mms-sms/canonical-address/$id"), null, null, null, null)?.use {
            if (it.moveToFirst()) { val a = it.getString(0); canonical[id] = a; return a }
        }
        return null
    }

    private fun recipientsOf(ids: String?): List<String> =
        (ids ?: "").split(' ').mapNotNull { it.toLongOrNull() }.mapNotNull { canonicalAddress(it) }

    /** Every conversation, the newest first. */
    @Suppress("UNCHECKED_CAST")
    fun conversations(): List<Map<String, Any?>> = conversationsPage()["items"] as List<Map<String, Any?>>

    /** One conversation as the list has it, or null where it is gone. */
    @Suppress("UNCHECKED_CAST")
    fun conversation(thread: Long): Map<String, Any?>? = (conversationsPage(only = setOf(thread))["items"] as List<Map<String, Any?>>).firstOrNull()

    /**
     * Conversations, the newest first, a lot at a time (Matt, 2026-11-13: "see if we can load by most recent first
     * so that things are faster"): [limit] of them from the [offset]th row of Android's list, or all of them where
     * [limit] is 0. Answers with `items`, and with `next`: the row the next lot starts at, or null at the end.
     *
     * [pinnedToo] adds the pinned conversations wherever they are in the list, for the first lot: they head the
     * screen however old they are. [only]: these conversations alone (the archived ones' page, or one by its id).
     */
    fun conversationsPage(limit: Int = 0, offset: Int = 0, pinnedToo: Boolean = false, only: Set<Long>? = null): Map<String, Any?> {
        val out = ArrayList<Map<String, Any?>>()
        var next: Int? = null
        if (only != null && only.isEmpty()) return mapOf("items" to out, "next" to null)
        val uri = Uri.parse("content://mms-sms/conversations?simple=true")
        val archived = archivedThreads()
        val pinned = threadFlags("pinned")
        val muted = threadFlags("muted")
        val drafts = drafts()
        // Android's blocked list, read once: asking it about each conversation's number is a call to Android apiece.
        val blocked = blockedKeys()
        readCanonical()
        // No projection: OEM providers (Samsung's among them) differ in the columns they keep, and naming one they
        // lack fails the whole query. Each column is read if it is there.
        try {
            resolver.query(uri, null, only?.let { "_id IN (${it.joinToString(",")})" }, null, "date DESC")?.use { c ->
                fun col(name: String) = c.getColumnIndex(name)
                val iId = col("_id"); val iDate = col("date"); val iCount = col("message_count"); val iRec = col("recipient_ids")
                val iSnip = col("snippet"); val iRead = col("read"); val iErr = col("error"); val iAtt = col("has_attachment")
                fun row(): Map<String, Any?>? {
                    val id = c.getLong(iId)
                    // A store that takes no notice of which were asked for is held to them here.
                    if (only != null && id !in only) return null
                    val count = if (iCount >= 0) c.getInt(iCount) else 1
                    // A count of nothing is believed only where the conversation holds nothing: some phones' stores
                    // do not keep the count, and every conversation would be left out.
                    if (count == 0 && !hasMessages(id)) return null
                    val recipients = recipientsOf(if (iRec >= 0) c.getString(iRec) else null)
                    val date = if (iDate >= 0) c.getLong(iDate) else 0L
                    val summary = E2e.preview(context, recipients.singleOrNull(), if (iSnip >= 0) c.getString(iSnip) ?: "" else "").let { if (BackgroundWire.valueIn(it) != null) "Chat background" else it }
                    return mapOf(
                        "id" to id,
                        "date" to date,
                        "count" to count,
                        "people" to recipients.map { contact(it) },
                        // A picture message's summary in Android's list is its subject, often empty: its words, or
                        // what it is, instead.
                        "snippet" to summary.ifBlank { latestSnippet(id, "$date:$count") },
                        "encrypted" to (recipients.size == 1 && E2e.isOn(context, recipients[0])),
                        "unread" to (iRead >= 0 && c.getInt(iRead) == 0),
                        "error" to (iErr >= 0 && c.getInt(iErr) != 0),
                        "attachment" to (iAtt >= 0 && c.getInt(iAtt) != 0),
                        "archived" to archived.contains(id),
                        "pinned" to pinned.contains(id),
                        "muted" to muted.contains(id),
                        "draft" to drafts[id.toString()],
                        "blocked" to (recipients.size == 1 && E2e.norm(recipients[0]) in blocked),
                    )
                }
                if (offset <= 0 || c.moveToPosition(offset - 1)) {
                    while (c.moveToNext()) {
                        if (limit > 0 && out.size >= limit) { next = c.position; break }
                        row()?.let { out += it }
                    }
                }
                // The pinned ones further down: the cursor stands on the first row not taken.
                if (pinnedToo && next != null && pinned.isNotEmpty()) {
                    val have = out.mapTo(HashSet()) { it["id"] as Long }
                    do {
                        val id = c.getLong(iId)
                        if (id in pinned && id !in have) row()?.let { out += it }
                    } while (c.moveToNext())
                }
            }
        } catch (e: Exception) {
            // A phone whose store will not answer this way is read the plain way, from the texts themselves. If that
            // fails too the screen is told, and says so: an empty list would look like every message had gone.
            android.util.Log.e("GhostMessaging", "conversations", e)
            out.clear()
            next = null
            if (offset <= 0) out += conversationsFromTexts(archived, pinned, muted, drafts).filter { only == null || (it["id"] as Long) in only }
        }
        return mapOf("items" to out, "next" to next)
    }

    /** The numbers on Android's blocked list, as conversations are told apart by them ([E2e.norm]). */
    private fun blockedKeys(): Set<String> {
        val out = HashSet<String>()
        try {
            resolver.query(android.provider.BlockedNumberContract.BlockedNumbers.CONTENT_URI, arrayOf(android.provider.BlockedNumberContract.BlockedNumbers.COLUMN_ORIGINAL_NUMBER), null, null, null)?.use {
                while (it.moveToNext()) it.getString(0)?.let { n -> out += E2e.norm(n) }
            }
        } catch (_: Exception) {}
        return out
    }

    /** Whether [thread] holds a text or a picture message at all. */
    private fun hasMessages(thread: Long): Boolean {
        for (uri in listOf(Telephony.Sms.CONTENT_URI, Telephony.Mms.CONTENT_URI)) {
            val any = try {
                resolver.query(uri, arrayOf("_id"), "thread_id = ?", arrayOf(thread.toString()), "_id LIMIT 1")?.use { it.count > 0 } ?: false
            } catch (_: Exception) { false }
            if (any) return true
        }
        return false
    }

    /**
     * The conversations as the texts themselves give them, for a store that will not list its conversations: the
     * newest text of each, by the conversation it says it is in. One person each (a text has one address); group
     * picture messages are found by [threadPeople] where the store answers that.
     */
    private fun conversationsFromTexts(archived: Set<Long>, pinned: Set<Long>, muted: Set<Long>, drafts: Map<String, String>): List<Map<String, Any?>> {
        val seen = LinkedHashMap<Long, Map<String, Any?>>()
        resolver.query(Telephony.Sms.CONTENT_URI, arrayOf("thread_id", "address", "body", "date", "read", "type"), null, null, "date DESC")?.use { c ->
            while (c.moveToNext()) {
                val id = c.getLong(0)
                if (seen.containsKey(id)) continue
                val address = c.getString(1) ?: ""
                val people = try { threadPeople(id).ifEmpty { listOf(contact(address)) } } catch (_: Exception) { listOf(contact(address)) }
                val one = people.singleOrNull()?.get("address") as String?
                seen[id] = mapOf(
                    "id" to id,
                    "date" to c.getLong(3),
                    "count" to 1,
                    "people" to people,
                    "snippet" to E2e.preview(context, one, c.getString(2) ?: "").let { if (BackgroundWire.valueIn(it) != null) "Chat background" else it },
                    "encrypted" to (one != null && E2e.isOn(context, one)),
                    "unread" to (c.getInt(4) == 0 && c.getInt(5) == Telephony.Sms.MESSAGE_TYPE_INBOX),
                    "error" to (c.getInt(5) == Telephony.Sms.MESSAGE_TYPE_FAILED),
                    "attachment" to false,
                    "archived" to archived.contains(id),
                    "pinned" to pinned.contains(id),
                    "muted" to muted.contains(id),
                    "draft" to drafts[id.toString()],
                    "blocked" to (one != null && isBlocked(one)),
                )
            }
        }
        return seen.values.toList()
    }

    /** What a conversation with no summary of its own shows, kept while the conversation stands as it did. */
    private val snippets = java.util.concurrent.ConcurrentHashMap<Long, Pair<String, String>>()

    /**
     * The summary of [thread] where Android's own is empty, as its newest message gives it. [stamp] is the
     * conversation's date and count: while they are what they were, the answer is what it was, where it used to be
     * read again (several questions to Android) for every such conversation each time the list was.
     */
    private fun latestSnippet(thread: Long, stamp: String): String {
        snippets[thread]?.let { if (it.first == stamp) return it.second }
        val words = try { readLatestSnippet(thread) } catch (_: Exception) { "" }
        snippets[thread] = stamp to words
        return words
    }

    private fun readLatestSnippet(thread: Long): String {
        val which = arrayOf(thread.toString())
        // The newest picture message, unless a text is newer still.
        var mms: Long? = null
        var mmsDate = 0L
        resolver.query(Telephony.Mms.CONTENT_URI, arrayOf("_id", "date"), "thread_id = ?", which, "date DESC LIMIT 1")?.use {
            if (it.moveToFirst()) { mms = it.getLong(0); mmsDate = it.getLong(1) * 1000 }
        }
        resolver.query(Telephony.Sms.CONTENT_URI, arrayOf("date", "address", "body"), "thread_id = ?", which, "date DESC LIMIT 1")?.use {
            if (it.moveToFirst() && (mms == null || it.getLong(0) >= mmsDate)) {
                val opened = E2e.read(context, it.getString(1) ?: "", it.getString(2) ?: "").first
                return if (BackgroundWire.valueIn(opened) != null) "Chat background" else opened
            }
        }
        val id = mms ?: return ""
        val parts = mmsPartsOf(listOf(id))[id] ?: emptyList()
        val written = parts.filter { it["type"] == "text/plain" }.joinToString("\n") { it["text"] as String? ?: "" }
        if (BackgroundWire.valueIn(written) != null) return "Chat background"
        if (written.isNotBlank()) return written
        val rest = parts.filter { it["type"] != "text/plain" && it["type"] != "application/smil" }
        return when {
            rest.any { (it["type"] as String).startsWith("image/") && Stickers.isSticker(it["name"] as String?) } -> "Sticker"
            rest.any { (it["type"] as String).startsWith("image/") } -> "Picture"
            rest.any { (it["type"] as String).startsWith("audio/") } -> "Voice message"
            rest.any { (it["type"] as String).startsWith("video/") } -> "Video"
            rest.isNotEmpty() -> "Attachment"
            else -> ""
        }
    }

    fun threadPeople(thread: Long): List<Map<String, Any?>> {
        resolver.query(Uri.parse("content://mms-sms/conversations?simple=true"), arrayOf("_id", "recipient_ids"), "_id = ?", arrayOf(thread.toString()), null)?.use {
            if (it.moveToFirst()) return recipientsOf(it.getString(1)).map { a -> contact(a) }
        }
        return emptyList()
    }

    fun threadFor(addresses: List<String>): Long = Telephony.Threads.getOrCreateThreadId(context, addresses.toSet())

    // --- messages ----------------------------------------------------------------------------------------------------

    /** The newest [limit] messages of [thread], SMS and MMS together, the newest first. */
    fun messages(thread: Long, limit: Int = 300): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val receipts = receipts()
        resolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf("_id", "address", "body", "date", "type", "status", "read", "date_sent"),
            "thread_id = ?", arrayOf(thread.toString()), "date DESC LIMIT $limit",
        )?.use { c ->
            while (c.moveToNext()) {
                val type = c.getInt(4)
                // A sealed text is opened here, as it is shown; a text carrying a key is a notice, not words.
                val (opened, sealed) = E2e.read(context, c.getString(1) ?: "", c.getString(2) ?: "")
                // A text that carried a chat background (BackgroundWire) is a notice too.
                val background = BackgroundWire.valueIn(opened)
                val words = if (background != null) "" else opened
                out += mapOf(
                    "id" to c.getLong(0),
                    "kind" to "sms",
                    "address" to (c.getString(1) ?: ""),
                    "body" to words,
                    "encrypted" to (sealed == "encrypted"),
                    "notice" to (if (sealed == "key" || sealed == "undecryptable") sealed else if (background != null) "background" else null),
                    "date" to c.getLong(3),
                    "outgoing" to (type != Telephony.Sms.MESSAGE_TYPE_INBOX),
                    "state" to smsState(type, c.getInt(5)),
                    "read" to (c.getInt(6) != 0),
                )
            }
        }
        resolver.query(
            Telephony.Mms.CONTENT_URI,
            arrayOf("_id", "date", "msg_box", "read", "m_type", "sub", "m_id", "st"),
            "thread_id = ?", arrayOf(thread.toString()), "date DESC LIMIT $limit",
        )?.use { c ->
            // Every message's parts in one question to Android, where it was one question a message.
            val rows = ArrayList<List<Any?>>()
            while (c.moveToNext()) rows += listOf(c.getLong(0), c.getLong(1), c.getInt(2), c.getInt(3), c.getInt(4), c.getString(5), c.getString(6), c.getInt(7))
            val partsOf = mmsPartsOf(rows.map { it[0] as Long })
            for (row in rows) {
                val id = row[0] as Long
                val box = row[2] as Int
                val mType = row[4] as Int
                val outgoing = box != Telephony.Mms.MESSAGE_BOX_INBOX
                val parts = partsOf[id] ?: emptyList()
                val written = parts.filter { it["type"] == "text/plain" }.joinToString("\n") { it["text"] as String? ?: "" }
                // A picture or group message that carried a chat background: a notice, its picture not a message's.
                val background = BackgroundWire.valueIn(written)
                val text = if (background != null) "" else written
                out += mapOf(
                    "id" to id,
                    "kind" to "mms",
                    "address" to (if (outgoing) "" else mmsSender(id)),
                    "body" to text,
                    "notice" to (if (background != null) "background" else null),
                    "subject" to row[5] as String?,
                    "date" to (row[1] as Long) * 1000,
                    "outgoing" to outgoing,
                    "state" to when {
                        // A picture message announced and not here: being brought down now, or it could not be
                        // (insertMmsNotice). The conversation draws it with a way to try again.
                        mType == Pdu.NOTIFICATION_IND -> if ((row[7] as Int) == NOTICE_DOWNLOADING) "downloading" else "pending_download"
                        box == Telephony.Mms.MESSAGE_BOX_OUTBOX -> "sending"
                        box == Telephony.Mms.MESSAGE_BOX_FAILED -> "failed"
                        outgoing -> receipts[row[6] as String? ?: ""] ?: "sent"
                        else -> "received"
                    },
                    "read" to ((row[3] as Int) != 0),
                    "parts" to (if (background != null) emptyList() else parts.filter { it["type"] != "text/plain" && it["type"] != "application/smil" }),
                )
            }
        }
        out.sortByDescending { it["date"] as Long }
        val originals = originals()
        val marked = if (originals.isEmpty()) out else out.map { m ->
            val original = originals["${m["kind"]}:${m["id"]}"]
            if (original == null) m else m + mapOf("edited" to true, "original" to original)
        }
        return if (marked.size > limit) marked.subList(0, limit) else marked
    }

    /** The texts that arrived since [since], opened where they were sealed: their words and when, newest first. */
    fun recentInbox(since: Long, limit: Int = 20): List<Pair<String, Long>> {
        val out = ArrayList<Pair<String, Long>>()
        resolver.query(Telephony.Sms.Inbox.CONTENT_URI, arrayOf("address", "body", "date"), "date >= ?", arrayOf(since.toString()), "date DESC LIMIT $limit")?.use { c ->
            while (c.moveToNext()) out += E2e.read(context, c.getString(0) ?: "", c.getString(1) ?: "").first to c.getLong(2)
        }
        return out
    }

    private fun smsState(type: Int, status: Int): String = when (type) {
        Telephony.Sms.MESSAGE_TYPE_INBOX -> "received"
        Telephony.Sms.MESSAGE_TYPE_OUTBOX, Telephony.Sms.MESSAGE_TYPE_QUEUED -> "sending"
        Telephony.Sms.MESSAGE_TYPE_FAILED -> "failed"
        else -> if (status == Telephony.Sms.STATUS_COMPLETE) "delivered" else "sent"
    }

    /** The parts of each of [ids], in the order each message keeps them: asked for a hundred messages at a time. */
    private fun mmsPartsOf(ids: List<Long>): Map<Long, List<Map<String, Any?>>> {
        val out = HashMap<Long, ArrayList<Map<String, Any?>>>()
        for (chunk in ids.chunked(100)) {
            resolver.query(Uri.parse("content://mms/part"), arrayOf("_id", "ct", "text", "name", "cl", "_data", "mid"), "mid IN (${chunk.joinToString(",")})", null, "mid ASC, seq ASC")?.use { c ->
                while (c.moveToNext()) {
                    val partId = c.getLong(0)
                    val type = (c.getString(1) ?: "").lowercase()
                    var text: String? = null
                    if (type == "text/plain") {
                        text = c.getString(2)
                        if (text == null && c.getString(5) != null) text = readPart(partId)?.toString(Charsets.UTF_8)
                    }
                    out.getOrPut(c.getLong(6)) { ArrayList() } += mapOf("id" to partId, "type" to type, "text" to text, "name" to (c.getString(3) ?: c.getString(4)))
                }
            }
        }
        return out
    }

    /**
     * A stored picture message's parts as they would be sent: its pictures, stickers, sound and words, read back from
     * where they are kept. Its layout is left out (it is written anew), and [body], where given, stands for its words.
     */
    fun partsToSendAgain(id: Long, body: String? = null): List<Pdu.Part> {
        val out = ArrayList<Pdu.Part>()
        (mmsPartsOf(listOf(id))[id] ?: emptyList()).forEachIndexed { i, p ->
            val type = p["type"] as String
            val name = (p["name"] as String?)?.takeIf { it.isNotBlank() } ?: "part$i"
            when {
                type == "application/smil" -> {}
                type == "text/plain" -> if (body == null) (p["text"] as String?)?.takeIf { it.isNotEmpty() }?.let {
                    out += Pdu.Part("text/plain", it.toByteArray(), contentLocation = "text$i.txt", contentId = "text$i")
                }
                else -> readPart(p["id"] as Long)?.let { out += Pdu.Part(type, it, name = name, contentLocation = name, contentId = "part$i") }
            }
        }
        if (!body.isNullOrEmpty()) out += Pdu.Part("text/plain", body.toByteArray(), contentLocation = "text0.txt", contentId = "text0")
        return out
    }

    fun readPart(partId: Long): ByteArray? = try {
        resolver.openInputStream(Uri.parse("content://mms/part/$partId"))?.use { it.readBytes() }
    } catch (_: Exception) { null }

    /** Who sent each picture message, remembered: a stored message's sender does not change. */
    private val senders = java.util.concurrent.ConcurrentHashMap<Long, String>()

    private fun mmsSender(id: Long): String {
        senders[id]?.let { return it }
        var from = ""
        resolver.query(Uri.parse("content://mms/$id/addr"), arrayOf("address", "type"), "type = 137", null, null)?.use {
            if (it.moveToFirst()) from = it.getString(0) ?: ""
        }
        if (from.isNotEmpty()) senders[id] = from
        return from
    }

    // --- writing -----------------------------------------------------------------------------------------------------

    fun insertSmsInbox(address: String, body: String, date: Long, dateSent: Long, subId: Int): Uri? {
        val v = ContentValues().apply {
            put("address", address)
            put("body", body)
            put("date", date)
            put("date_sent", dateSent)
            put("read", 0)
            put("seen", 0)
            put("type", Telephony.Sms.MESSAGE_TYPE_INBOX)
            put("sub_id", subId)
        }
        return resolver.insert(Telephony.Sms.Inbox.CONTENT_URI, v)
    }

    fun insertSmsOutbox(thread: Long, address: String, body: String, subId: Int): Uri? {
        val v = ContentValues().apply {
            put("thread_id", thread)
            put("address", address)
            put("body", body)
            put("date", System.currentTimeMillis())
            put("read", 1)
            put("seen", 1)
            put("type", Telephony.Sms.MESSAGE_TYPE_OUTBOX)
            put("status", Telephony.Sms.STATUS_PENDING)
            put("sub_id", subId)
        }
        return resolver.insert(Telephony.Sms.CONTENT_URI, v)
    }

    fun setSmsType(uri: Uri, type: Int, errorCode: Int = 0) {
        resolver.update(uri, ContentValues().apply { put("type", type); put("error_code", errorCode) }, null, null)
    }

    fun setSmsStatus(uri: Uri, status: Int) {
        resolver.update(uri, ContentValues().apply { put("status", status) }, null, null)
    }

    fun threadOfSms(uri: Uri): Long {
        resolver.query(uri, arrayOf("thread_id"), null, null, null)?.use { if (it.moveToFirst()) return it.getLong(0) }
        return -1
    }

    fun threadOfMms(uri: Uri): Long {
        resolver.query(uri, arrayOf("thread_id"), null, null, null)?.use { if (it.moveToFirst()) return it.getLong(0) }
        return -1
    }

    /** Writes an MMS (received or being sent) with its people and parts; returns its row. */
    fun insertMms(
        box: Int,
        thread: Long,
        from: String?,
        to: List<String>,
        cc: List<String>,
        parts: List<Pdu.Part>,
        dateSeconds: Long,
        subject: String?,
        messageId: String?,
        transactionId: String?,
        subId: Int,
    ): Uri? {
        val v = ContentValues().apply {
            put("thread_id", thread)
            put("date", dateSeconds)
            put("date_sent", dateSeconds)
            put("msg_box", box)
            put("read", if (box == Telephony.Mms.MESSAGE_BOX_INBOX) 0 else 1)
            put("seen", if (box == Telephony.Mms.MESSAGE_BOX_INBOX) 0 else 1)
            put("m_type", if (box == Telephony.Mms.MESSAGE_BOX_INBOX) Pdu.RETRIEVE_CONF else Pdu.SEND_REQ)
            put("v", 0x12)
            put("ct_t", "application/vnd.wap.multipart.related")
            put("text_only", if (parts.all { it.isText || it.isSmil }) 1 else 0)
            if (!subject.isNullOrBlank()) { put("sub", subject); put("sub_cs", 106) }
            if (messageId != null) put("m_id", messageId)
            if (transactionId != null) put("tr_id", transactionId)
            put("sub_id", subId)
        }
        val uri = resolver.insert(Telephony.Mms.CONTENT_URI, v) ?: return null
        val id = uri.lastPathSegment ?: return uri
        fun addr(a: String, type: Int) {
            resolver.insert(Uri.parse("content://mms/$id/addr"), ContentValues().apply {
                put("address", a); put("type", type); put("charset", 106)
            })
        }
        addr(from ?: "insert-address-token", 137)
        to.forEach { addr(it, 151) }
        cc.forEach { addr(it, 130) }
        var seq = 0
        for (p in parts) {
            val pv = ContentValues().apply {
                put("mid", id)
                put("seq", if (p.isSmil) -1 else seq++)
                put("ct", p.contentType)
                put("cid", "<${p.contentId ?: p.contentLocation ?: "part$seq"}>")
                put("cl", p.contentLocation ?: p.name ?: "part$seq")
                if (p.name != null) put("name", p.name)
                if (p.isText || p.isSmil) { put("chset", 106); put("text", p.text()) }
            }
            val partUri = resolver.insert(Uri.parse("content://mms/$id/part"), pv) ?: continue
            if (!p.isText && !p.isSmil) {
                try { resolver.openOutputStream(partUri)?.use { it.write(p.data) } } catch (_: Exception) {}
            }
        }
        return uri
    }

    /**
     * A picture message the carrier has announced and that is not here yet (Matt, 2026-11-13, of "a photo could not
     * be downloaded": "when I tap it I'd like it to take me to the associated chat and show the failed image with a
     * retry if needed"). Kept as Android keeps one, a row of the announcement itself: where the picture waits at the
     * carrier, and the name the carrier knows the fetch by. It stands in the sender's conversation until the picture
     * comes down, which takes its place, and is what Try again fetches from. One announced twice is one row.
     */
    fun insertMmsNotice(thread: Long, from: String, location: String, transactionId: String?, subId: Int): Uri? {
        resolver.query(Telephony.Mms.CONTENT_URI, arrayOf("_id"), "m_type = ${Pdu.NOTIFICATION_IND} AND ct_l = ?", arrayOf(location), null)?.use { c ->
            if (c.moveToFirst()) return Uri.withAppendedPath(Telephony.Mms.CONTENT_URI, c.getLong(0).toString()).also { setMmsNoticeDownloading(it, true) }
        }
        val uri = resolver.insert(Telephony.Mms.CONTENT_URI, ContentValues().apply {
            put("thread_id", thread)
            put("date", System.currentTimeMillis() / 1000)
            put("msg_box", Telephony.Mms.MESSAGE_BOX_INBOX)
            put("read", 0)
            put("seen", 0)
            put("m_type", Pdu.NOTIFICATION_IND)
            put("v", 0x12)
            put("ct_l", location)
            if (transactionId != null) put("tr_id", transactionId)
            put("st", NOTICE_DOWNLOADING)
            put("sub_id", subId)
        }) ?: return null
        val id = uri.lastPathSegment ?: return uri
        resolver.insert(Uri.parse("content://mms/$id/addr"), ContentValues().apply { put("address", from); put("type", 137); put("charset", 106) })
        return uri
    }

    /** Whether the picture [notice] stands for is being brought down now, or could not be. */
    fun setMmsNoticeDownloading(notice: Uri, downloading: Boolean) {
        resolver.update(notice, ContentValues().apply { put("st", if (downloading) NOTICE_DOWNLOADING else NOTICE_FAILED) }, null, null)
    }

    /** Where the picture message announced as [id] waits at the carrier, the fetch's name there, and the SIM. */
    fun mmsNotice(id: Long): Triple<String, String?, Int>? {
        resolver.query(Telephony.Mms.CONTENT_URI, arrayOf("ct_l", "tr_id", "sub_id"), "_id = ? AND m_type = ${Pdu.NOTIFICATION_IND}", arrayOf(id.toString()), null)?.use { c ->
            if (c.moveToFirst()) return Triple(c.getString(0) ?: return null, c.getString(1), c.getInt(2))
        }
        return null
    }

    fun deleteMms(uri: Uri) { resolver.delete(uri, null, null) }

    fun setMmsBox(uri: Uri, box: Int) {
        resolver.update(uri, ContentValues().apply { put("msg_box", box) }, null, null)
    }

    fun markRead(thread: Long) {
        val v = ContentValues().apply { put("read", 1); put("seen", 1) }
        resolver.update(Telephony.Sms.CONTENT_URI, v, "thread_id = ? AND read = 0", arrayOf(thread.toString()))
        resolver.update(Telephony.Mms.CONTENT_URI, v, "thread_id = ? AND read = 0", arrayOf(thread.toString()))
    }

    fun deleteThread(thread: Long) {
        resolver.delete(Uri.parse("content://mms-sms/conversations/$thread"), null, null)
    }

    fun deleteMessage(kind: String, id: Long) {
        val uri = if (kind == "mms") Uri.parse("content://mms/$id") else Uri.parse("content://sms/$id")
        resolver.delete(uri, null, null)
        editsPrefs.edit().remove("$kind:$id").apply()
    }

    fun unreadCount(): Int {
        var n = 0
        resolver.query(Telephony.Sms.Inbox.CONTENT_URI, arrayOf("_id"), "read = 0", null, null)?.use { n += it.count }
        resolver.query(Telephony.Mms.Inbox.CONTENT_URI, arrayOf("_id"), "read = 0", null, null)?.use { n += it.count }
        return n
    }

    // --- receipts: what came back about an MMS of ours, by the name the MMSC gave it --------------------------------

    private val receiptPrefs get() = context.getSharedPreferences("receipts", Context.MODE_PRIVATE)

    /** Message-ID -> "delivered" or "read". */
    fun receipts(): Map<String, String> = receiptPrefs.all.mapValues { it.value.toString() }

    /** Read outranks delivered: a delivery report arriving after a read report changes nothing. */
    fun setReceipt(messageId: String, state: String) {
        if (state == "delivered" && receiptPrefs.getString(messageId, null) == "read") return
        receiptPrefs.edit().putString(messageId, state).apply()
    }

    fun setMmsMessageId(uri: Uri, messageId: String) {
        resolver.update(uri, ContentValues().apply { put("m_id", messageId) }, null, null)
    }

    // --- edits (this app's own record: SMS has no edit, so the original is kept here) ------------------------------

    private val editsPrefs get() = context.getSharedPreferences("edits", Context.MODE_PRIVATE)

    /** "sms:12" -> the text it had before its first edit. */
    fun originals(): Map<String, String> = editsPrefs.all.mapValues { it.value.toString() }

    /** Changes the text of one of your messages on this phone, keeping what it first said. */
    fun editMessage(kind: String, id: Long, body: String) {
        val key = "$kind:$id"
        val before: String?
        if (kind == "mms") {
            var partId = -1L
            var text: String? = null
            resolver.query(Uri.parse("content://mms/part"), arrayOf("_id", "text"), "mid = ? AND ct = 'text/plain'", arrayOf(id.toString()), "seq ASC")?.use {
                if (it.moveToFirst()) { partId = it.getLong(0); text = it.getString(1) }
            }
            before = text
            if (partId >= 0) {
                resolver.update(Uri.parse("content://mms/part/$partId"), ContentValues().apply { put("text", body) }, null, null)
            } else {
                resolver.insert(Uri.parse("content://mms/$id/part"), ContentValues().apply {
                    put("mid", id); put("seq", 0); put("ct", "text/plain"); put("chset", 106)
                    put("cid", "<text0>"); put("cl", "text0.txt"); put("text", body)
                })
            }
        } else {
            var text: String? = null
            var address = ""
            resolver.query(Uri.parse("content://sms/$id"), arrayOf("body", "address"), null, null, null)?.use {
                if (it.moveToFirst()) { text = it.getString(0); address = it.getString(1) ?: "" }
            }
            // What it first said is kept as words; the row keeps a sealed text sealed.
            val sealed = text != null && E2eCrypto.isSealed(text!!)
            before = if (sealed) E2e.read(context, address, text!!).first else text
            val stored = if (sealed) (E2e.wire(context, address, body) ?: body) else body
            resolver.update(Uri.parse("content://sms/$id"), ContentValues().apply { put("body", stored) }, null, null)
        }
        if (!editsPrefs.contains(key)) editsPrefs.edit().putString(key, before ?: "").apply()
    }

    // --- archive (this app's own, not the provider's) ----------------------------------------------------------------

    private val prefs get() = context.getSharedPreferences("ghost", Context.MODE_PRIVATE)

    /** A set of conversations kept by this app under [name]: "pinned", "muted". */
    fun threadFlags(name: String): Set<Long> = prefs.getStringSet(name, emptySet())!!.mapNotNull { it.toLongOrNull() }.toSet()

    fun setThreadFlag(name: String, thread: Long, on: Boolean) {
        val s = prefs.getStringSet(name, emptySet())!!.toMutableSet()
        if (on) s += thread.toString() else s -= thread.toString()
        prefs.edit().putStringSet(name, s).apply()
    }

    fun isMuted(thread: Long) = threadFlags("muted").contains(thread)

    // --- drafts: what was typed into a conversation and not sent ----------------------------------------------------

    private val draftPrefs get() = context.getSharedPreferences("drafts", Context.MODE_PRIVATE)

    fun drafts(): Map<String, String> = draftPrefs.all.mapValues { it.value.toString() }

    fun draft(thread: Long): String? = draftPrefs.getString(thread.toString(), null)

    fun setDraft(thread: Long, text: String) {
        if (text.isBlank()) draftPrefs.edit().remove(thread.toString()).apply() else draftPrefs.edit().putString(thread.toString(), text).apply()
    }

    /** Every number on Android's blocked list, with the contact it is, for Settings. */
    fun blockedNumbers(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        try {
            resolver.query(android.provider.BlockedNumberContract.BlockedNumbers.CONTENT_URI, arrayOf(android.provider.BlockedNumberContract.BlockedNumbers.COLUMN_ORIGINAL_NUMBER), null, null, null)?.use {
                while (it.moveToNext()) { val n = it.getString(0) ?: continue; out += contact(n) }
            }
        } catch (_: Exception) {}
        return out
    }

    // --- blocked numbers: Android's own list, which the default SMS app may read and write --------------------------

    fun isBlocked(address: String): Boolean = try {
        android.provider.BlockedNumberContract.isBlocked(context, address)
    } catch (_: Exception) { false }

    /** Android itself stops a blocked number's texts and calls before any app sees them. */
    fun setBlocked(address: String, blocked: Boolean) {
        if (blocked) {
            resolver.insert(android.provider.BlockedNumberContract.BlockedNumbers.CONTENT_URI, ContentValues().apply {
                put(android.provider.BlockedNumberContract.BlockedNumbers.COLUMN_ORIGINAL_NUMBER, address)
            })
        } else {
            android.provider.BlockedNumberContract.unblock(context, address)
        }
    }

    fun archivedThreads(): Set<Long> = prefs.getStringSet("archived", emptySet())!!.mapNotNull { it.toLongOrNull() }.toSet()

    fun setArchived(thread: Long, archived: Boolean) {
        val s = prefs.getStringSet("archived", emptySet())!!.toMutableSet()
        if (archived) s += thread.toString() else s -= thread.toString()
        prefs.edit().putStringSet("archived", s).apply()
    }

    companion object {
        /** A picture message's announcement: being brought down, or it could not be (Android's own two numbers). */
        const val NOTICE_DOWNLOADING = 129
        const val NOTICE_FAILED = 130

        fun sameNumber(a: String, b: String): Boolean {
            if (a.contains('@') || b.contains('@')) return a.equals(b, ignoreCase = true)
            val da = a.filter { it.isDigit() }
            val db = b.filter { it.isDigit() }
            if (da.isEmpty() || db.isEmpty()) return a == b
            @Suppress("DEPRECATION")
            return PhoneNumberUtils.compare(a, b) || da.takeLast(10) == db.takeLast(10)
        }

        @Suppress("unused")
        private fun Cursor.str(name: String): String? = getColumnIndex(name).let { if (it < 0) null else getString(it) }
    }
}

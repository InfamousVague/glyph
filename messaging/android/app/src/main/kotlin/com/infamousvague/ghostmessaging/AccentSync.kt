package com.infamousvague.ghostmessaging

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.pm.ApplicationInfo
import android.database.ContentObserver
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Binder
import android.os.Handler
import android.os.Looper

/**
 * The colour of your bubbles everywhere (`bubble` in the "ui" preferences, lib/accent.dart's accent), kept in step
 * with Ghost Keyboard's colour (Matt, 2026-11-15: "make the color themes available the same as the ghost messaging app
 * and keep the two in sync"). The keyboard offers the same colours by the same ids (its AccentSync.kt, the list of
 * lib/backgrounds.dart's `bubbleColors`), worn as its enter key's.
 *
 * Each app keeps its choice and when it was made (`bubble_at` here), and answers the other with the two at
 * `content://<package>.accent/current` ([AccentProvider]). Whichever was chosen last wins: each app asks the other as
 * it comes to the front, and watches the other's address while it is there, so a colour chosen in one shows in the
 * other at once. Taking the other's choice keeps its time, so the two never trade a choice back and forth.
 *
 * The two are signed with different keys, so each pins the other's certificate, as the codes do ([CodesProvider]).
 * Only the colour's id and its time cross.
 */
object AccentSync {
    const val KEYBOARD = "com.infamousvague.devkeyboard"
    private const val KEYBOARD_AUTHORITY = "$KEYBOARD.accent"

    /** lib/backgrounds.dart's `bubbleColors` ids, the keyboard's AccentSync.COLOURS. */
    val IDS = listOf("ghost", "ink", "wallpaper", "white", "silver", "gray", "graphite", "blue", "indigo", "purple", "pink", "red", "orange", "yellow", "green", "mint")

    private fun ui(context: Context) = context.applicationContext.getSharedPreferences("ui", Context.MODE_PRIVATE)
    fun ownUri(context: Context): Uri = Uri.parse("content://${context.packageName}.accent/current")
    private val keyboardUri: Uri by lazy { Uri.parse("content://$KEYBOARD_AUTHORITY/current") }

    /** Your bubbles' colour (white where none was chosen, as AppState's) and when it was chosen (0: never). */
    fun current(context: Context): Pair<String, Long> {
        val ui = ui(context)
        return (ui.getString("bubble", null) ?: "white") to (ui.getString("bubble_at", null)?.toLongOrNull() ?: 0L)
    }

    /** A colour was chosen here (Settings › Appearance › Bubbles): stamped now, and the keyboard told. */
    fun chosen(context: Context) {
        ui(context).edit().putString("bubble_at", System.currentTimeMillis().toString()).apply()
        runCatching { context.contentResolver.notifyChange(ownUri(context), null) }
    }

    /** The keyboard's id where it was chosen after ours, else null; an id not known here is not taken. */
    fun take(mine: Long, theirId: String?, theirs: Long): String? =
        if (theirId != null && theirId in IDS && theirs > mine) theirId else null

    private fun trusted(context: Context): Boolean = runCatching {
        val provider = context.packageManager.resolveContentProvider(KEYBOARD_AUTHORITY, 0) ?: return false
        provider.packageName == KEYBOARD && CodesProvider.keyboardHere(context)
    }.getOrDefault(false)

    /** Asks the keyboard for its colour and takes it if newer; the screens are told. True where it changed. */
    fun pull(context: Context): Boolean {
        if (!trusted(context)) return false
        val (id, at) = runCatching {
            context.contentResolver.query(keyboardUri, null, null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getString(0) to c.getString(1).toLong() else null
            }
        }.getOrNull() ?: return false
        val (mine, mineAt) = current(context)
        val taken = take(mineAt, id, at) ?: return false
        ui(context).edit().putString("bubble", taken).putString("bubble_at", at.toString()).apply()
        if (taken != mine) Bus.prefsChanged()
        return taken != mine
    }

    /** Watches the keyboard's address while [context] is in front. */
    fun watch(context: Context): ContentObserver? {
        if (!trusted(context)) return null
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) { Thread { pull(context) }.start() }
        }
        return if (runCatching { context.contentResolver.registerContentObserver(keyboardUri, false, observer) }.isSuccess) observer else null
    }

    fun unwatch(context: Context, observer: ContentObserver?) {
        if (observer != null) runCatching { context.contentResolver.unregisterContentObserver(observer) }
    }
}

/**
 * `content://com.infamousvague.ghostmessaging.accent/current`: your bubbles' colour (`accent`) and when it was chosen
 * (`at`, milliseconds since 1970, 0 where never). Read-only, for Ghost Keyboard alone ([CodesProvider.KEYBOARDS]'
 * package and certificate; a debug build of this app lets any build of it in).
 */
class AccentProvider : ContentProvider() {
    override fun onCreate() = true

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? {
        val context = context ?: return null
        val cursor = MatrixCursor(arrayOf("accent", "at"))
        if (uri.lastPathSegment != "current" || !allowed(context)) return cursor
        val (id, at) = AccentSync.current(context)
        cursor.addRow(arrayOf<Any>(id, at.toString()))
        return cursor
    }

    private fun allowed(context: Context): Boolean {
        val packages = context.packageManager.getPackagesForUid(Binder.getCallingUid()) ?: return false
        if (AccentSync.KEYBOARD !in packages) return false
        val debuggable = context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        return debuggable || CodesProvider.keyboardHere(context)
    }

    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}

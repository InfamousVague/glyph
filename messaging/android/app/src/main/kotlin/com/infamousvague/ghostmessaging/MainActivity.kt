package com.infamousvague.ghostmessaging

import android.Manifest
import android.app.role.RoleManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * The one screen, Flutter's. Two channels: `ghost_messaging/sms` (calls: the provider, sending, the SMS role,
 * permissions) and `ghost_messaging/events` (a conversation changed; a notification or another app asked for one).
 * Every provider call runs on one background thread, in order.
 */
class MainActivity : FlutterActivity() {
    companion object {
        @Volatile var openThread: Long = -1
        @Volatile var inFront = false
        private const val ROLE_REQUEST = 41
        private const val PERMS_REQUEST = 42
        private const val PICK_REQUEST = 43
    }

    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null
    private var pendingOpen: Map<String, Any?>? = null
    private var roleResult: MethodChannel.Result? = null
    private var permsResult: MethodChannel.Result? = null
    private var pickResult: MethodChannel.Result? = null
    private lateinit var store: Store

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        store = Store(applicationContext)
        pendingOpen = openRequest(intent)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, "ghost_messaging/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                events = sink
                Bus.listener = { thread -> events?.success(mapOf("type" to "changed", "thread" to thread)) }
            }
            override fun onCancel(arguments: Any?) { events = null; Bus.listener = null }
        })

        MethodChannel(messenger, "ghost_messaging/sms").setMethodCallHandler { call, result ->
            fun bg(work: () -> Any?) = io.execute {
                try { val v = work(); main.post { result.success(v) } }
                catch (e: Exception) { main.post { result.error("failed", e.message ?: e.toString(), null) } }
            }
            when (call.method) {
                "status" -> result.success(status())
                "requestDefault" -> requestDefault(result)
                "requestPermissions" -> requestPermissions(result)
                "openRequest" -> { result.success(pendingOpen); pendingOpen = null }
                "conversations" -> bg { store.clearContactCache(); store.conversations() }
                "messages" -> bg { store.messages(call.argument<Number>("thread")!!.toLong(), call.argument<Int>("limit") ?: 300) }
                "people" -> bg { store.threadPeople(call.argument<Number>("thread")!!.toLong()) }
                "threadFor" -> bg { store.threadFor(call.argument<List<String>>("addresses")!!) }
                "send" -> bg {
                    Sender.send(applicationContext, call.argument<List<String>>("addresses")!!, call.argument<String>("body") ?: "", call.argument<List<String>>("attachments") ?: emptyList())
                }
                "markRead" -> bg {
                    val t = call.argument<Number>("thread")!!.toLong()
                    store.markRead(t); Notifier.cancel(applicationContext, t); null
                }
                "deleteThread" -> bg { val t = call.argument<Number>("thread")!!.toLong(); store.deleteThread(t); Notifier.cancel(applicationContext, t); null }
                "deleteMessage" -> bg { store.deleteMessage(call.argument<String>("kind")!!, call.argument<Number>("id")!!.toLong()); null }
                "archive" -> bg { store.setArchived(call.argument<Number>("thread")!!.toLong(), call.argument<Boolean>("archived") ?: true); null }
                "searchContacts" -> bg { store.searchContacts(call.argument<String>("query") ?: "") }
                "contact" -> bg { store.contact(call.argument<String>("address")!!) }
                "photo" -> bg { store.photo(call.argument<String>("uri")!!) }
                "part" -> bg { store.readPart(call.argument<Number>("id")!!.toLong()) }
                "pickImages" -> pickImages(result)
                "setOpenThread" -> {
                    openThread = call.argument<Number>("thread")?.toLong() ?: -1
                    if (openThread >= 0) Notifier.cancel(applicationContext, openThread)
                    result.success(null)
                }
                "dial" -> {
                    try { startActivity(Intent(Intent.ACTION_DIAL, Uri.fromParts("tel", call.argument<String>("address")!!, null))) } catch (_: Exception) {}
                    result.success(null)
                }
                "prefs" ->result.success(getSharedPreferences("ui", MODE_PRIVATE).all.mapValues { it.value.toString() })
                "setPref" -> {
                    getSharedPreferences("ui", MODE_PRIVATE).edit().putString(call.argument<String>("key")!!, call.argument<String>("value")).apply()
                    result.success(null)
                }
                "ownNumber" -> bg { store.ownNumbers().firstOrNull() }
                "setOwnNumber" -> {
                    getSharedPreferences("ghost", MODE_PRIVATE).edit().putString("own_number", call.argument<String>("number")).apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() { super.onResume(); inFront = true }
    override fun onPause() { super.onPause(); inFront = false }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val req = openRequest(intent) ?: return
        if (events != null) events?.success(mapOf("type" to "open") + req) else pendingOpen = req
    }

    /** What the intent asks to open: a conversation (a notification), or a new message to someone (sms: links, shares). */
    private fun openRequest(intent: Intent?): Map<String, Any?>? {
        intent ?: return null
        val thread = intent.getLongExtra(Notifier.EXTRA_THREAD, -1)
        if (thread >= 0) return mapOf("thread" to thread)
        val data = intent.data
        if (data != null && data.scheme in setOf("sms", "smsto", "mms", "mmsto")) {
            val to = data.schemeSpecificPart.substringBefore('?').split(',', ';').map { Uri.decode(it).trim() }.filter { it.isNotEmpty() }
            val body = intent.getStringExtra("sms_body") ?: intent.getStringExtra(Intent.EXTRA_TEXT) ?: data.getQueryParameterSafe("body")
            return mapOf("addresses" to to, "body" to body)
        }
        if (intent.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            return mapOf("addresses" to emptyList<String>(), "body" to intent.getStringExtra(Intent.EXTRA_TEXT))
        }
        return null
    }

    private fun Uri.getQueryParameterSafe(name: String): String? = try {
        Uri.parse("x://h?" + (toString().substringAfter('?', ""))).getQueryParameter(name)
    } catch (_: Exception) { null }

    private fun granted(p: String) = checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED

    private fun status(): Map<String, Any?> {
        val role = getSystemService(RoleManager::class.java)
        return mapOf(
            "isDefault" to (role.isRoleAvailable(RoleManager.ROLE_SMS) && role.isRoleHeld(RoleManager.ROLE_SMS)),
            "contacts" to granted(Manifest.permission.READ_CONTACTS),
            "notifications" to (android.os.Build.VERSION.SDK_INT < 33 || granted(Manifest.permission.POST_NOTIFICATIONS)),
            "phone" to granted(Manifest.permission.READ_PHONE_NUMBERS),
        )
    }

    private fun requestDefault(result: MethodChannel.Result) {
        val role = getSystemService(RoleManager::class.java)
        if (role.isRoleHeld(RoleManager.ROLE_SMS)) { result.success(true); return }
        roleResult = result
        @Suppress("DEPRECATION")
        startActivityForResult(role.createRequestRoleIntent(RoleManager.ROLE_SMS), ROLE_REQUEST)
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        val want = mutableListOf(Manifest.permission.READ_CONTACTS, Manifest.permission.READ_PHONE_STATE, Manifest.permission.READ_PHONE_NUMBERS)
        if (android.os.Build.VERSION.SDK_INT >= 33) want += Manifest.permission.POST_NOTIFICATIONS
        val missing = want.filter { !granted(it) }
        if (missing.isEmpty()) { result.success(status()); return }
        permsResult = result
        requestPermissions(missing.toTypedArray(), PERMS_REQUEST)
    }

    private fun pickImages(result: MethodChannel.Result) {
        pickResult = result
        val i = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "image/*"
            addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        @Suppress("DEPRECATION")
        startActivityForResult(Intent.createChooser(i, "Add a picture"), PICK_REQUEST)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            ROLE_REQUEST -> {
                roleResult?.success(getSystemService(RoleManager::class.java).isRoleHeld(RoleManager.ROLE_SMS)); roleResult = null
            }
            PICK_REQUEST -> {
                val uris = ArrayList<String>()
                if (resultCode == RESULT_OK && data != null) {
                    val clip = data.clipData
                    if (clip != null) for (k in 0 until clip.itemCount) uris += clip.getItemAt(k).uri.toString()
                    else data.data?.let { uris += it.toString() }
                }
                pickResult?.success(uris); pickResult = null
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMS_REQUEST) { permsResult?.success(status()); permsResult = null }
    }
}

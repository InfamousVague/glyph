package com.mattssoftware.ghost_md

import android.annotation.SuppressLint
import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.work.WorkManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream

/**
 * What the Tauri app's page kept in its web view, asked of a web view once (lib/carry/tauri_carry.dart).
 *
 * This app is installed over Ghost.md's Tauri app under the same id, so it wakes in that app's data folder, and
 * the page's `localStorage` and IndexedDB are still there under `app_webview/`, kept for the origin the page was
 * served from: `http://tauri.localhost`. Nothing reads another origin's storage but a page at that origin, so
 * this makes one: a web view that is never put in a window, whose every request is answered here (so nothing is
 * asked of any network, and `tauri.localhost` is never looked up), loads one page of this file's own at that
 * origin, and the page hands back
 *
 * - every key and value of `localStorage`;
 * - each team note's document from IndexedDB (`glyph-team`, src/app/core/team/docs.ts), its bytes as base64url;
 * - of the account's three keys (`glyph-account`, src/app/core/account/keystore.ts): which are there, the public
 *   half of each pair, and a few bytes sealed under the account key. The keys themselves are not extractable and
 *   no page can read them out; Dart reads their bytes from the files (lib/carry/web_stores.dart) and opens what
 *   was sealed here to know it read the right ones.
 *
 * It only reads. A database the page never made is not made by looking for it, nothing is written or deleted, and
 * the web view is destroyed when it has answered. One read at a time; a page that does not answer in fifteen
 * seconds is an error Dart falls back from.
 */
class TauriCarry(private val activity: Activity) {
    private val main = Handler(Looper.getMainLooper())
    private var view: WebView? = null
    private var waiting: MethodChannel.Result? = null
    private var deadline: Runnable? = null

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "read" -> read(call.argument<String>("probeContext") ?: "", result)
                // The Tauri app's own queued work that this app has no class for (its update check): let go of by
                // name, so WorkManager does not keep trying to make a worker that is not there.
                "forgetWork" -> {
                    try {
                        val names = call.argument<List<String>>("names") ?: emptyList()
                        val work = WorkManager.getInstance(activity.applicationContext)
                        names.forEach { work.cancelUniqueWork(it) }
                        result.success(names.size)
                    } catch (failure: Exception) {
                        result.error("work", failure.message ?: "WorkManager would not answer.", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Called from onDestroy: a read still going is ended with the activity. */
    fun close() = finish { it.error("closed", "The app closed before the web view answered.", null) }

    @SuppressLint("SetJavaScriptEnabled")
    private fun read(probeContext: String, result: MethodChannel.Result) {
        if (waiting != null) {
            result.error("busy", "The web view's storage is already being read.", null)
            return
        }
        if (!CONTEXT.matches(probeContext)) {
            result.error("context", "That is not a context to seal a probe under.", null)
            return
        }
        waiting = result
        try {
            val made = WebView(activity)
            view = made
            made.settings.javaScriptEnabled = true
            made.settings.domStorageEnabled = true
            made.settings.allowFileAccess = false
            made.settings.allowContentAccess = false
            made.addJavascriptInterface(Bridge(), "ghostCarry")
            val page = PAGE.replace("__CONTEXT__", probeContext).toByteArray(Charsets.UTF_8)
            made.webViewClient = object : WebViewClient() {
                // Every request is answered here: the one page, and nothing for anything else.
                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse {
                    return if (request.url.toString() == URL) {
                        WebResourceResponse("text/html", "utf-8", ByteArrayInputStream(page))
                    } else {
                        WebResourceResponse("text/plain", "utf-8", 404, "Not Found", emptyMap(), ByteArrayInputStream(ByteArray(0)))
                    }
                }
            }
            deadline = Runnable { finish { it.error("timeout", "The web view did not answer.", null) } }.also { main.postDelayed(it, 15_000) }
            made.loadUrl(URL)
        } catch (failure: Exception) {
            // No web view on this phone, or one that is being updated this minute.
            finish { it.error("webview", failure.message ?: "No web view.", null) }
        }
    }

    private fun finish(answer: (MethodChannel.Result) -> Unit) {
        val result = waiting ?: return
        waiting = null
        deadline?.let { main.removeCallbacks(it) }
        deadline = null
        view?.let {
            it.stopLoading()
            it.removeJavascriptInterface("ghostCarry")
            it.destroy()
        }
        view = null
        answer(result)
    }

    /** What the page calls, on a thread of the web view's own. */
    private inner class Bridge {
        @JavascriptInterface
        fun done(json: String) {
            main.post { finish { it.success(json) } }
        }

        @JavascriptInterface
        fun failed(message: String) {
            main.post { finish { it.error("page", message, null) } }
        }
    }

    companion object {
        const val CHANNEL = "ghost_md/tauri_carry"

        /** The Tauri app's origin on Android (wry's default, with no `useHttpsScheme`), and a path its page never had. */
        private const val URL = "http://tauri.localhost/__ghost_carry__.html"

        private val CONTEXT = Regex("^[A-Za-z0-9/_:.-]{1,80}$")

        /**
         * The page. `indexedDB.databases()` says what is there before anything is opened, so nothing is made; a web
         * view too old to have it (before Chromium 72) opens each by name and backs out of a creation. The seal is
         * `src/app/core/sync/crypto.ts`'s `sealBytes`: a version byte, twelve random bytes, AES-GCM with the
         * context as the additional data.
         */
        private val PAGE = """
<!doctype html><meta charset="utf-8"><script>
(async () => {
  const b64 = (bytes) => { let s = ''; const u = new Uint8Array(bytes); for (let i = 0; i < u.length; i += 1) s += String.fromCharCode(u[i]); return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+${'$'}/, ''); };
  const asked = (r) => new Promise((res, rej) => { r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
  const out = { v: 1, origin: location.origin, agent: navigator.userAgent, local: {}, databases: [], keys: {}, team: [], notes: [] };
  for (let i = 0; i < localStorage.length; i += 1) { const k = localStorage.key(i); if (k !== null) out.local[k] = localStorage.getItem(k); }
  let names = null;
  try { if (indexedDB.databases) names = (await indexedDB.databases()).map((d) => d.name); } catch (e) { out.notes.push('databases: ' + e); }
  if (names) out.databases = names;
  const open = (name) => new Promise((res) => {
    if (names && !names.includes(name)) return res(null);
    let made = false;
    const r = indexedDB.open(name);
    r.onupgradeneeded = () => { made = true; r.transaction.abort(); };
    r.onsuccess = () => res(made ? (r.result.close(), null) : r.result);
    r.onerror = () => res(null);
    r.onblocked = () => res(null);
  });
  const account = await open('glyph-account');
  if (account && account.objectStoreNames.contains('keys')) {
    const get = (name) => asked(account.transaction('keys', 'readonly').objectStore('keys').get(name)).catch(() => undefined);
    const key = await get('account');
    if (key) {
      const entry = { algorithm: key.algorithm && key.algorithm.name, extractable: key.extractable };
      try {
        const iv = crypto.getRandomValues(new Uint8Array(12));
        const sealed = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData: new TextEncoder().encode('__CONTEXT__') }, key, new TextEncoder().encode(JSON.stringify('ghost-carry'))));
        const all = new Uint8Array(1 + 12 + sealed.length); all[0] = 1; all.set(iv, 1); all.set(sealed, 13);
        entry.probe = b64(all);
      } catch (e) { entry.failed = String(e); }
      out.keys.account = entry;
    }
    for (const name of ['device', 'encryption']) {
      const pair = await get(name);
      if (!pair) continue;
      const entry = { algorithm: pair.privateKey && pair.privateKey.algorithm && pair.privateKey.algorithm.name };
      try { entry.public = b64(await crypto.subtle.exportKey('raw', pair.publicKey)); } catch (e) { entry.failed = String(e); }
      out.keys[name] = entry;
    }
    account.close();
  }
  const team = await open('glyph-team');
  if (team && team.objectStoreNames.contains('docs')) {
    await new Promise((res) => {
      const r = team.transaction('docs', 'readonly').objectStore('docs').openCursor();
      r.onerror = () => res();
      r.onsuccess = () => {
        const at = r.result;
        if (!at) return res();
        try {
          const d = at.value;
          if (typeof at.key === 'string' && d && d.state) out.team.push({ id: at.key, state: b64(d.state), seq: Number(d.seq) || 0, snapshotSeq: Number(d.snapshotSeq) || 0, pending: (d.pending || []).map((u) => b64(u)) });
        } catch (e) { out.notes.push('team ' + at.key + ': ' + e); }
        at.continue();
      };
    });
    team.close();
  }
  ghostCarry.done(JSON.stringify(out));
})().catch((e) => ghostCarry.failed(String(e)));
</script>
""".trimIndent()
    }
}

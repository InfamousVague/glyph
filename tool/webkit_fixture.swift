// Makes a real WebKit's storage for the Mac carry's tests (lib/carry/webkit_stores.dart, docs/CUTOVER.md §7): a
// WKWebView at `tauri://localhost`, the origin the Tauri Mac app's page has, keeps what that page keeps, the way it
// keeps it (tauri/src/app/core/account/keystore.ts, orgs/wrap.ts, sync/crypto.ts, team/docs.ts): `localStorage`,
// the three keys as CryptoKeys that cannot be exported in IndexedDB `glyph-account`, a team document in
// `glyph-team`. The files WebKit wrote are copied out, with `expected.json` beside them saying what a reader must
// find.
//
// Everything in it is made up here, on the spot: no account, no note and no key of anybody's. It still holds keys,
// so what it writes is not committed (test/carry/fixtures is ignored by the tests that do not find it).
//
// WebKit wraps a stored CryptoKey under a "master key". An app's own is in the login Keychain; this tool hands
// WebKit one of its own instead (`_webCryptoMasterKeyForWebView:`), written into expected.json, so nothing is put
// in or read from a Keychain. The web view's store is one made for the run and removed after it.
//
//   swiftc -O tool/webkit_fixture.swift -o build/ghost-webkit-fixture
//   build/ghost-webkit-fixture test/carry/fixtures/mac_webkit
import Cocoa
import WebKit

let page = """
<!doctype html><meta charset="utf-8"><script>
(async () => {
  const b64 = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=+$/, '');
  const say = (what) => window.webkit.messageHandlers.done.postMessage(JSON.stringify(what));
  try {
    const out = { agent: navigator.userAgent, origin: location.origin, local: {}, keys: {}, team: [] };
    const local = {
      'glyph-preferences': JSON.stringify({ theme: 'dawn', words: 'h\\u00e9llo \\u2713 \\ud834\\udd1e', workspaces: [{ id: 'w1', name: 'Fixture' }] }),
      'glyph-account-session': JSON.stringify({ token: 'fixture-token', handle: 'fixture', accountId: 7 }),
      'glyph-github-token': 'ghp_fixture',
      'glyph-note-places': '{}',
      'glyph-empty': '',
      'glyph-long': 'x'.repeat(70000),
      'someone-elses': 'not carried',
    };
    for (const [key, value] of Object.entries(local)) localStorage.setItem(key, value);
    for (let i = 0; i < localStorage.length; i += 1) out.local[localStorage.key(i)] = localStorage.getItem(localStorage.key(i));

    const open = (name, store) => new Promise((resolve, reject) => {
      const req = indexedDB.open(name, 1);
      req.onupgradeneeded = () => req.result.createObjectStore(store);
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
    const put = (db, store, value, key) => new Promise((resolve, reject) => {
      const tx = db.transaction(store, 'readwrite');
      tx.objectStore(store).put(value, key);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
    const remove = (db, store, key) => new Promise((resolve, reject) => {
      const tx = db.transaction(store, 'readwrite');
      tx.objectStore(store).delete(key);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
    const keys = await open('glyph-account', 'keys');

    // An earlier account's key, written and replaced: the newest must be the one read.
    const earlier = await crypto.subtle.importKey('raw', crypto.getRandomValues(new Uint8Array(32)), { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
    await put(keys, 'keys', earlier, 'account');
    await remove(keys, 'keys', 'account');

    // The account key: AES-256-GCM, kept so that no page can export it (sync/crypto.ts `settle`).
    const accountRaw = crypto.getRandomValues(new Uint8Array(32));
    const account = await crypto.subtle.importKey('raw', accountRaw, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
    await put(keys, 'keys', account, 'account');
    out.keys.account = { raw: b64(accountRaw) };

    // The account's pair: ECDH on P-256, the private half not extractable (orgs/wrap.ts `pairFromPrivate`).
    const CURVE = { name: 'ECDH', namedCurve: 'P-256' };
    const made = await crypto.subtle.generateKey(CURVE, true, ['deriveBits']);
    const jwk = await crypto.subtle.exportKey('jwk', made.privateKey);
    const privateKey = await crypto.subtle.importKey('jwk', jwk, CURVE, false, ['deriveBits']);
    const { d, ...publicJwk } = jwk;
    const publicKey = await crypto.subtle.importKey('jwk', { ...publicJwk, key_ops: [] }, CURVE, true, []);
    await put(keys, 'keys', { privateKey, publicKey }, 'encryption');
    out.keys.encryption = { d, public: b64(await crypto.subtle.exportKey('raw', publicKey)) };

    // The device's signing key: Ed25519, generated not extractable (sync/crypto.ts `newDeviceKey`), so only its
    // public half can be said; and one more made from known bytes, under a name the page does not use.
    try {
      const device = await crypto.subtle.generateKey({ name: 'Ed25519' }, false, ['sign', 'verify']);
      await put(keys, 'keys', device, 'device');
      out.keys.device = { public: b64(await crypto.subtle.exportKey('raw', device.publicKey)) };
      const known = await crypto.subtle.generateKey({ name: 'Ed25519' }, true, ['sign', 'verify']);
      const seed = (await crypto.subtle.exportKey('jwk', known.privateKey)).d;
      const kept = await crypto.subtle.importKey('pkcs8', await crypto.subtle.exportKey('pkcs8', known.privateKey), { name: 'Ed25519' }, false, ['sign']);
      await put(keys, 'keys', { privateKey: kept, publicKey: known.publicKey }, 'device-known');
      out.keys.deviceKnown = { d: seed, public: b64(await crypto.subtle.exportKey('raw', known.publicKey)) };
    } catch (failure) {
      out.keys.deviceFailure = String(failure);
    }

    // Two team documents (team/docs.ts): the CRDT's state, two numbers, what was typed and not sent.
    const team = await open('glyph-team', 'docs');
    const bytes = (count, from) => Uint8Array.from({ length: count }, (_, i) => (from + i * 7) & 0xff);
    const docs = [
      ['2f768660-4265-40a7-a677-daf32de584bd', { state: bytes(300, 1), seq: 12, snapshotSeq: 9, pending: [bytes(5, 3), bytes(70000, 9)] }],
      ['aaaaaaaa-0000-4000-8000-000000000001', { state: bytes(0, 0), seq: 0, snapshotSeq: 0, pending: [] }],
      ['bbbbbbbb-0000-4000-8000-000000000002', { state: bytes(40, 200), seq: 70000, snapshotSeq: 1, pending: [bytes(1, 255)] }],
    ];
    for (const [id, record] of docs) {
      await put(team, 'docs', record, id);
      out.team.push({ id, state: b64(record.state), seq: record.seq, snapshotSeq: record.snapshotSeq, pending: record.pending.map(b64) });
    }
    keys.close();
    team.close();
    say(out);
  } catch (failure) {
    say({ failure: String(failure) + ' ' + (failure && failure.stack) });
  }
})();
</script>
"""

final class Maker: NSObject, WKURLSchemeHandler, WKScriptMessageHandler, WKNavigationDelegate {
  let master: Data
  var asked = false
  var done: ((String) -> Void)?

  init(master: Data) { self.master = master }

  func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
    let response = HTTPURLResponse(url: task.request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/html; charset=utf-8"])!
    task.didReceive(response)
    task.didReceive(Data(page.utf8))
    task.didFinish()
  }

  func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

  func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
    done?(message.body as? String ?? "{}")
  }

  // WebKit's own question for the key it wraps stored CryptoKeys under (WKNavigationDelegatePrivate), in the two
  // forms it has had.
  @objc(_webCryptoMasterKeyForWebView:) func masterKey(_ webView: WKWebView) -> NSData {
    asked = true
    return master as NSData
  }

  @objc(_webCryptoMasterKeyForWebView:completionHandler:) func masterKey(_ webView: WKWebView, completionHandler: @escaping (NSData?) -> Void) {
    asked = true
    completionHandler(master as NSData)
  }
}

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(Data("usage: ghost-webkit-fixture <folder to write>\n".utf8))
  exit(2)
}
let target = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
var masterBytes = [UInt8](repeating: 0, count: 16)
guard SecRandomCopyBytes(kSecRandomDefault, masterBytes.count, &masterBytes) == errSecSuccess else { exit(1) }
let maker = Maker(master: Data(masterBytes))

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let identifier = UUID()
let store = WKWebsiteDataStore(forIdentifier: identifier)
let configuration = WKWebViewConfiguration()
configuration.websiteDataStore = store
configuration.setURLSchemeHandler(maker, forURLScheme: "tauri")
configuration.userContentController.add(maker, name: "done")
var view: WKWebView? = WKWebView(frame: NSRect(x: 0, y: 0, width: 200, height: 200), configuration: configuration)
view!.navigationDelegate = maker

/// Where WebKit keeps this run's store: under this tool's own name, never an app's.
func storeFolder() -> URL {
  let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
  let name = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
  return library.appendingPathComponent("WebKit/\(name)/WebsiteDataStore/\(identifier.uuidString)", isDirectory: true)
}

func finish(_ code: Int32) -> Never {
  view = nil
  let group = DispatchGroup()
  group.enter()
  WKWebsiteDataStore.remove(forIdentifier: identifier) { _ in group.leave() }
  let until = Date().addingTimeInterval(5)
  while group.wait(timeout: .now()) == .timedOut && Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
  // WebKit lets go of a store only once nothing holds it, which may be after this process: what is left of this
  // run's is removed by hand, and the tool's folder with it when that was all it held.
  let kept = storeFolder()
  try? FileManager.default.removeItem(at: kept)
  for folder in [kept.deletingLastPathComponent(), kept.deletingLastPathComponent().deletingLastPathComponent()] {
    if (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true { try? FileManager.default.removeItem(at: folder) }
  }
  exit(code)
}

maker.done = { said in
  // A moment for WebKit to have written what the page was told is written.
  DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
    let manager = FileManager.default
    let kept = storeFolder()
    guard manager.fileExists(atPath: kept.path) else {
      FileHandle.standardError.write(Data("WebKit kept nothing at \(kept.path)\n".utf8))
      finish(1)
    }
    do {
      try? manager.removeItem(at: target)
      try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      try manager.copyItem(at: kept, to: target)
      guard var expected = try JSONSerialization.jsonObject(with: Data(said.utf8)) as? [String: Any] else { finish(1) }
      expected["masterKey"] = maker.master.base64EncodedString()
      expected["masterKeyAsked"] = maker.asked
      try JSONSerialization.data(withJSONObject: expected, options: [.prettyPrinted, .sortedKeys]).write(to: target.appendingPathComponent("expected.json"))
      print("written to \(target.path); WebKit asked for the master key: \(maker.asked); failure: \(expected["failure"] ?? "none")")
      finish(maker.asked && expected["failure"] == nil ? 0 : 1)
    } catch {
      FileHandle.standardError.write(Data("could not copy: \(error)\n".utf8))
      finish(1)
    }
  }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
  FileHandle.standardError.write(Data("the page did not answer in 30 seconds\n".utf8))
  finish(1)
}
view!.load(URLRequest(url: URL(string: "tauri://localhost/")!))
app.run()

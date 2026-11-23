import '../standalone/store.dart';
import 'browser.dart';

/// [StandaloneStore] for the app in a web page: the browser's own store for this page (IndexedDB, browser_web.dart).
///
/// - The JSON is one record, `state`, written whole each time.
/// - The key that is who this device is, and every secret (the account's words, forward secrecy's prekeys, circles'
///   keys), are sealed before they are kept, with a key the browser made for this page and will not hand out: the
///   page can seal and open with it, and neither the page's own code nor anything that reads the browser's files
///   has the key itself. What it does not do: keep out a script running in this page, which can ask the same.
class WebStandaloneStore implements StandaloneStore {
  WebStandaloneStore(this.store);
  final BrowserStore store;

  static const stateName = 'state', identityName = 'identity';
  static String secretName(String name) => 'secret:$name';

  @override
  Future<void> open() async {}

  @override
  Future<String?> readState() => store.read(stateName);

  @override
  Future<void> writeState(String text) => store.write(stateName, text);

  @override
  Future<String?> readIdentity() => store.readSealed(identityName);

  @override
  Future<void> writeIdentity(String hex, {bool imported = false}) => store.writeSealed(identityName, hex);

  @override
  Future<String?> readSecret(String name) => store.readSealed(secretName(name));

  @override
  Future<void> writeSecret(String name, String value) => store.writeSealed(secretName(name), value);

  @override
  Future<void> deleteSecret(String name) => store.delete(secretName(name));
}

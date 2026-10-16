/// Publishing a note or a notebook as a site (docs/SITES.md): the shared link's sealed content, read on the reader
/// page as a small website, with an address per page.
///
/// A site is a share in everything that keeps it private: what it holds ([sharedOf]: a note, or a notebook's index
/// and every page that has a note, in the notebook's order, with the pictures they show) is sealed on the device under
/// a key made for that site alone, and the key rides in the link after the `#`, which a browser never sends. The
/// service (server/src/sites.rs) keeps ciphertext it cannot open. What is the site's own:
///
/// - **It is published by hand.** [Sites.publish] writes it, and writes it again at the same address; an edit in
///   between reaches it only then, where a shared link follows every save.
/// - **Its devices find it on the service.** Beside the sealed site, the service keeps a second blob sealed under the
///   ACCOUNT key, its [SiteEntry] (what it is of, its title, its key), in the context `site:<id>`. So every device of
///   the account lists the account's sites with their links ([Sites.refresh]), and the synced settings carry nothing.
/// - **It never carries where a page was written, nor the places in it**, whatever a shared link of the same note is
///   ticked to carry: a site has no ticks, and is the kind of thing a person passes round.
/// - **It is not indexed.** The page asks search engines not to, and none could read it: the key is in the part of
///   the address a search engine never sees. There is no setting for it, since there is nothing it could change.
///
/// The address is `https://ghostmarkdown.com/s/<id>#<key>`; the reader page gives each page its own,
/// `/s/<id>/<page>#<key>` (tauri/src/read/site.ts names them). The page names in an address are the one part of a site
/// the web server receives as written, when someone opens a page's own address; the words never are.
library;

import 'package:flutter/foundation.dart';

import '../account/api.dart';
import '../account/crypto_api.dart';
import '../account/session.dart';
import '../core/book.dart' show isBookBody;
import '../core/note.dart';
import '../core/note_text.dart';
import 'share.dart';

/// The context a site is sealed in: a share's ciphertext is not a site's, nor the reverse.
const String siteContext = 'glyph/v1/site';

/// The context what the account's devices keep about a site is sealed in, under the account key.
String siteMetaContext(String id) => 'site:$id';

/// Where sites are read: the reader page under `/s/` on ghostmarkdown.com. `--dart-define GLYPH_SITES=…` names another
/// (a local preview).
final String sitesUrl = () {
  const given = String.fromEnvironment('GLYPH_SITES');
  final trimmed = given.replaceFirst(RegExp(r'/+$'), '');
  return trimmed.isEmpty ? 'https://ghostmarkdown.com/s' : trimmed;
}();

/// A site's address: its first page, with the key after the `#`.
String siteLink(String id, String key) => '$sitesUrl/$id#$key';

/// Whether this build offers sites and email to a note: everywhere but the iPhone, whose store build stays as it was
/// reviewed until a version that says so.
bool publishingOffered([TargetPlatform? platform]) => (platform ?? defaultTargetPlatform) != TargetPlatform.iOS;

/// A published site, as its owner's devices know it.
@immutable
class SiteEntry {
  const SiteEntry({required this.id, required this.key, required this.noteId, required this.title, required this.kind, this.created = 0, this.updated = 0});

  final String id;

  /// The key its link carries; never sent anywhere but sealed under the account key.
  final String key;

  /// The note it was published from: the note, or the notebook's index.
  final String noteId;
  final String title;

  /// `note` or `book`.
  final String kind;

  /// When it was first and last published, in ms.
  final int created;
  final int updated;

  String get link => siteLink(id, key);

  /// What is sealed under the account key.
  Map<String, Object?> toMeta() => {'v': 1, 'noteId': noteId, 'key': key, 'title': title, 'kind': kind};

  SiteEntry withTimes({required int created, required int updated}) => SiteEntry(id: id, key: key, noteId: noteId, title: title, kind: kind, created: created, updated: updated);

  @override
  String toString() => 'SiteEntry($title, $id)';
}

/// The account's sites, as this device last read them, and publishing.
class Sites extends ChangeNotifier {
  Sites({required this.account, required this.api, required this.crypto, required this.pictures, required this.listNotes}) {
    account.addListener(_accountChanged);
  }

  final AccountSource account;
  final Api api;
  final AccountCrypto crypto;
  final SharePictures pictures;
  final Future<List<Note>> Function() listNotes;

  List<SiteEntry> _list = const [];
  bool _read = false;
  int _unread = 0;

  /// The sites, last published first, as last read.
  List<SiteEntry> get list => _list;

  /// Whether the list has been read from the service since this device signed in.
  bool get read => _read;

  /// How many sites the service lists that this device could not open: published by a newer app.
  int get unread => _unread;

  /// The site published from [noteId], if there is one.
  SiteEntry? siteFor(String noteId) {
    for (final site in _list) {
      if (site.noteId == noteId) return site;
    }
    return null;
  }

  String _token() {
    final session = account.session;
    if (session == null) throw const ShareError('Sign in under Settings › Account to publish: a site is kept with your account.');
    return session.token;
  }

  Future<SealKey> _accountKey() async {
    final key = await account.accountKey();
    if (key == null) throw const ShareError('Sign in again on this device first: its key is not here.');
    return key;
  }

  void _set(List<SiteEntry> next) {
    _list = List.unmodifiable(next);
    notifyListeners();
  }

  /// The account's sites, from the service, opened with the account key.
  Future<List<SiteEntry>> refresh() async {
    final answer = await api.callMap('GET', 'sites', token: _token());
    final key = await _accountKey();
    final out = <SiteEntry>[];
    var unread = 0;
    for (final each in answer['sites'] is List ? answer['sites'] as List : const <Object?>[]) {
      if (each is! Map || each['id'] is! String || each['meta'] is! String) continue;
      final id = each['id'] as String;
      try {
        final meta = await crypto.open(key, each['meta'] as String, siteMetaContext(id));
        if (meta is! Map || meta['key'] is! String || meta['noteId'] is! String) throw const FormatException('not a site');
        out.add(SiteEntry(
          id: id,
          key: meta['key'] as String,
          noteId: meta['noteId'] as String,
          title: meta['title'] is String ? meta['title'] as String : 'Untitled',
          kind: meta['kind'] == 'book' ? 'book' : 'note',
          created: each['created'] is num ? (each['created'] as num).toInt() : 0,
          updated: each['updated'] is num ? (each['updated'] as num).toInt() : 0,
        ));
      } catch (_) {
        unread += 1;
      }
    }
    _read = true;
    _unread = unread;
    _set(out);
    return out;
  }

  /// Publishes [note] (a notebook's index with its pages among [notes]), or publishes it again at its address.
  Future<SiteEntry> publish(Note note, List<Note> notes) async {
    final token = _token();
    final accountKey = await _accountKey();
    if (!_read) await refresh();
    final had = siteFor(note.id);
    final title = noteTitle(note.body).isEmpty ? 'Untitled' : noteTitle(note.body);
    final site = SiteEntry(id: had?.id ?? newShareId(crypto), key: had?.key ?? newShareKey(crypto), noteId: note.id, title: title, kind: isBookBody(note.body) ? 'book' : 'note');
    final carried = await withPictures(sharedOf(note, notes), pictures);
    final blob = await sealShare(crypto, carried.shared, site.key, context: siteContext);
    if (blob.length > shareLimit) throw const ShareError('That is more than a site can hold, even with its pictures drawn smaller. Publish fewer pages.');
    final meta = await crypto.seal(accountKey, site.toMeta(), siteMetaContext(site.id));
    final answer = await api.callMap('PUT', 'sites/${site.id}', token: token, body: {'blob': blob, 'meta': meta});
    final updated = answer['updated'] is num ? (answer['updated'] as num).toInt() : DateTime.now().millisecondsSinceEpoch;
    final published = site.withTimes(created: had?.created ?? updated, updated: updated);
    _set([published, for (final s in _list) if (s.id != site.id) s]);
    return published;
  }

  /// Takes [site] down: its link reads nothing from then on.
  Future<void> unpublish(SiteEntry site) async {
    await api.call('DELETE', 'sites/${site.id}', token: _token());
    _set([for (final s in _list) if (s.id != site.id) s]);
  }

  /// What a site's link holds, read and opened, as the reader page reads it: for the tests, and anyone checking one.
  Future<Shared> readSite(String id, String key) async {
    final answer = await api.callMap('GET', 'sites/$id');
    final blob = answer['blob'];
    if (blob is! String) throw const ShareError('Nothing is published at that link.');
    return openShare(crypto, blob, key, context: siteContext);
  }

  Future<void>? _reading;
  int _triedAt = 0;

  /// Reads the list soon, once: for a page that draws it. Offline, it is tried again a minute later at the soonest,
  /// however often the page is drawn.
  void readSoon() {
    if (_read || _reading != null || account.session == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _triedAt < 60000) return;
    _triedAt = now;
    _reading = refresh().then<void>((_) {}, onError: (Object _) {}).whenComplete(() => _reading = null);
  }

  int? _for;

  /// Signed out, or another account in: what this device knew of the sites goes.
  void _accountChanged() {
    final now = account.session?.accountId;
    if (now == _for) return;
    _for = now;
    if (_read || _list.isNotEmpty) forget();
  }

  /// Nothing is known of the account's sites here.
  void forget() {
    _read = false;
    _triedAt = 0;
    _unread = 0;
    _set(const []);
  }

  @override
  void dispose() {
    account.removeListener(_accountChanged);
    super.dispose();
  }
}

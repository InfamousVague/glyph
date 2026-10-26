/// Email to a note, on the device (docs/MAIL.md): the account's private address, and the step of a sync pass that
/// files what was mailed to it.
///
/// The service took each mail in the clear, as any mail server must, and sealed it at once to the account's
/// encryption PUBLIC key (server/src/mail/seal.rs): a fresh key wrapped by ECIES exactly as an organization's key is
/// wrapped to a member (core/orgs/wrap.ts), with `inbound-mail:<id>` as the wrap's context, and the mail sealed under
/// that key as everything synced is, with `mail:<id>`. So a device opens it with what it already has
/// ([openSealedMail]): [AccountCrypto.unwrapWith] with the account's pair, [AccountCrypto.importSealKey],
/// [AccountCrypto.openBytes]. The core is asked for nothing new.
///
/// [syncMail] is a step of the pass (lib/sync/engine.dart `mailIn`), before the notes: each mail waiting is opened,
/// its pictures kept, its note written into the library through the same door a note from another device comes in by
/// (`store_apply`, [LocalNotes.apply]) with no folder, so it lands in Inbox/, and the service told it is filed. The
/// notes step of the same pass then sends the note to the account's other devices as any new note. A note's id is
/// made from the mail's ([mailNoteId]), so a pass cut short, or two devices at once, file one note and not two.
///
/// [MailIn] is the setting (Settings › Account's Email to a note, and the meeting plugins' invite cards): the address,
/// a new one in its place or a name of one's own (lib/mail/mail_name.dart), off.
library;

import 'package:flutter/foundation.dart';

import '../account/api.dart';
import '../account/crypto_api.dart';
import '../account/enc_key.dart';
import '../account/keystore.dart';
import '../account/session.dart';
import '../core/bytes.dart';
import '../core/note.dart';
import '../sync/notes.dart' show FileKind, LocalFiles, LocalNotes;
import 'mail_name.dart';
import 'mail_note.dart';


/// The context a mail's key is wrapped in (server/src/mail/seal.rs `wrap_context`).
String mailWrapContext(String id) => 'inbound-mail:$id';

/// The context a mail is sealed in (`seal_context`).
String mailSealContext(String id) => 'mail:$id';

/// The mail [id] opened: its key out of [wrapped] with the account's [pair], then the mail out of [blob].
Future<OpenedMail> openSealedMail(AccountCrypto crypto, EncryptionKey pair, {required String id, required String wrapped, required String blob}) async {
  final raw = await crypto.unwrapWith(pair, wrapped, mailWrapContext(id));
  final key = await crypto.importSealKey(raw);
  return readMail(await crypto.openBytes(key, fromBase64Url(blob), mailSealContext(id)));
}

/// What the mail step works with.
class MailPassContext {
  const MailPassContext({required this.token, required this.api, required this.crypto, required this.pair, required this.notes, required this.files, required this.now, this.keepOther = keepMailFile});
  final String token;
  final Api api;
  final AccountCrypto crypto;

  /// The account's encryption pair, asked for only when there is mail to open.
  final Future<EncryptionKey> Function() pair;
  final LocalNotes notes;
  final LocalFiles files;
  final int Function() now;

  /// What becomes of a file that is not a picture (mail_note.dart, the seam for general attachments).
  final MailFileKeeper keepOther;
}

/// One mail step, as the engine is handed it: answers how many notes it filed.
typedef MailPass = Future<int> Function(MailPassContext ctx);

bool _noRoute(Object failure) => failure is ApiError && failure.status == 404 && failure.message == 'no such route';

/// The mail step (see the header). Quiet against a service that has no mail routes yet.
Future<int> syncMail(MailPassContext ctx) async {
  final Map<String, Object?> listed;
  try {
    listed = await ctx.api.callMap('GET', 'mail', token: ctx.token);
  } catch (failure) {
    if (_noRoute(failure)) return 0;
    rethrow;
  }
  final waiting = listed['mail'];
  if (waiting is! List || waiting.isEmpty) return 0;
  EncryptionKey? pair;
  var filed = 0;
  for (final each in waiting) {
    final id = each is Map && each['id'] is String ? each['id'] as String : null;
    if (id == null) continue;
    final noteId = mailNoteId(id);
    if (await ctx.notes.get(noteId) == null) {
      final Map<String, Object?> sealed;
      try {
        sealed = await ctx.api.callMap('GET', 'mail/$id', token: ctx.token);
      } on ApiError catch (failure) {
        // Filed by another device a moment ago.
        if (failure.status == 404) continue;
        rethrow;
      }
      final wrapped = sealed['wrapped'], blob = sealed['blob'];
      if (wrapped is! String || blob is! String) continue;
      final OpenedMail mail;
      try {
        mail = await openSealedMail(ctx.crypto, pair ??= await ctx.pair(), id: id, wrapped: wrapped, blob: blob);
      } catch (failure) {
        // Left waiting: a newer app may read what this one cannot.
        debugPrint('[mail] a mail would not open: $failure');
        continue;
      }
      final pictures = <int, String>{};
      final others = <String>[];
      for (final (index, file) in mail.files.indexed) {
        final ext = pictureExtension(file.type);
        if (ext != null) {
          final name = mailPictureName(id, index, ext);
          try {
            await ctx.files.write(FileKind.image, name, file.bytes);
            pictures[index] = name;
            continue;
          } catch (failure) {
            // Not what its name says (the core checks a picture's bytes): said, as any other file is.
            debugPrint('[mail] a picture was not kept: $failure');
          }
        }
        others.add(await ctx.keepOther(file, index));
      }
      final at = ctx.now();
      await ctx.notes.apply(Note(id: noteId, body: mailNoteBody(mail, pictures: pictures, others: others), createdAt: mail.date > 0 ? mail.date : at, updatedAt: at));
      filed += 1;
    }
    // Filed, here or before: the sealed copy goes from the service.
    await ctx.api.call('DELETE', 'mail/$id', token: ctx.token);
  }
  return filed;
}

/// The account's address as the setting shows it.
@immutable
class MailAddress {
  const MailAddress({this.address, this.available = false});

  /// The whole address, or null while it is off.
  final String? address;

  /// Whether the service takes mail at all: an older service, or one not set up for it, does not.
  final bool available;
}

/// The setting's side of email to a note (see the header): the address as the service last said it, and the three
/// things a person may do with it.
class MailIn extends ChangeNotifier {
  MailIn({required this.account, required this.keys, required this.api, required this.crypto}) {
    account.addListener(_accountChanged);
  }

  final AccountSource account;
  final KeyStore keys;
  final Api api;
  final AccountCrypto crypto;

  MailAddress? _address;

  /// The address as last read; null until it has been.
  MailAddress? get address => _address;

  String _token() {
    final session = account.session;
    if (session == null) throw const ApiError(401, 'Sign in under Settings › Account first.');
    return session.token;
  }

  void _set(MailAddress next) {
    _address = next;
    notifyListeners();
  }

  Future<void>? _reading;
  int _triedAt = 0;
  int? _for;

  /// Reads the address soon, once: for a page that draws it. Offline, it is tried again a minute later at the
  /// soonest, however often the page is drawn.
  void readSoon() {
    if (_address != null || _reading != null || account.session == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _triedAt < 60000) return;
    _triedAt = now;
    _reading = refresh().then<void>((_) {}, onError: (Object _) {}).whenComplete(() => _reading = null);
  }

  /// Signed out, or another account in: the address this device read is forgotten.
  void _accountChanged() {
    final now = account.session?.accountId;
    if (now == _for) return;
    _for = now;
    _triedAt = 0;
    if (_address != null) {
      _address = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    account.removeListener(_accountChanged);
    super.dispose();
  }

  /// What the service says now. An older service, with no mail routes, reads as one that takes none.
  Future<MailAddress> refresh() async {
    try {
      final said = await api.callMap('GET', 'mail/address', token: _token());
      _set(MailAddress(address: said['address'] is String ? said['address'] as String : null, available: said['available'] == true));
    } catch (failure) {
      if (!_noRoute(failure)) rethrow;
      _set(const MailAddress());
    }
    return _address!;
  }

  /// An address on, or a new one in place of the old: the account's encryption key seen to first, since mail is
  /// sealed to it as it arrives.
  Future<String> newAddress() async {
    final token = _token();
    final accountKey = await account.accountKey();
    if (accountKey == null) throw const ApiError(409, 'Sign in again on this device first: its key is not here.');
    await ensureEncryptionKey(EncryptionKeyContext(token: token, accountKey: accountKey, keys: keys, api: api, crypto: crypto));
    final said = await api.callMap('POST', 'mail/address', token: token);
    final address = said['address'];
    if (address is! String) throw const ApiError(500, 'The service answered without an address.');
    _set(MailAddress(address: address, available: true));
    return address;
  }

  /// What the service says of [name] as the account's address (`POST mail/address/available`, lib/mail/mail_name.dart):
  /// the name in the body, not the query, so it is not in the proxy's log. An older service, with no names yet, is
  /// said as [mailNamesNotYet].
  Future<MailNameCheck> checkName(String name) async {
    final Map<String, Object?> said;
    try {
      said = await api.callMap('POST', 'mail/address/available', token: _token(), body: {'name': name});
    } catch (failure) {
      if (_noNames(failure)) throw const ApiError(404, mailNamesNotYet);
      rethrow;
    }
    final reason = said['reason'], message = said['message'], kept = said['name'];
    return MailNameCheck(name: kept is String ? kept : mailNameNormal(name), available: said['available'] == true, reason: reason is String ? reason : null, message: message is String ? message : null);
  }

  /// [name] in place of the address, as [newAddress] puts a made one (`PUT mail/address`): the old one takes no mail
  /// from then on. A name refused comes back as an [ApiError] whose words are the field's ([MailNameCheck.words]).
  Future<String> chooseAddress(String name) async {
    final token = _token();
    final accountKey = await account.accountKey();
    if (accountKey == null) throw const ApiError(409, 'Sign in again on this device first: its key is not here.');
    await ensureEncryptionKey(EncryptionKeyContext(token: token, accountKey: accountKey, keys: keys, api: api, crypto: crypto));
    final Map<String, Object?> said;
    try {
      said = await api.callMap('PUT', 'mail/address', token: token, body: {'name': name});
    } on ApiError catch (failure) {
      if (_noNames(failure)) throw const ApiError(404, mailNamesNotYet);
      final body = failure.body;
      final reason = body is Map ? body['reason'] : null;
      if (reason is String) throw ApiError(failure.status, MailNameCheck(name: name, available: false, reason: reason, message: failure.message).words, body);
      rethrow;
    }
    final address = said['address'];
    if (address is! String) throw const ApiError(500, 'The service answered without an address.');
    _set(MailAddress(address: address, available: true));
    return address;
  }

  /// A service from before the names: `POST mail/address/available` is no route, and `PUT mail/address` a method
  /// the route does not take.
  static bool _noNames(Object failure) => _noRoute(failure) || (failure is ApiError && failure.status == 405);

  /// The address off. Mail already on its way is still filed.
  Future<void> turnOff() async {
    await api.call('DELETE', 'mail/address', token: _token());
    _set(MailAddress(available: _address?.available ?? true));
  }
}

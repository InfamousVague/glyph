import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/account/account.dart';
import 'package:ghost_messaging/account/account_crypto.dart';
import 'package:ghost_messaging/me/me.dart' show MemoryMeStore;
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_relay/accounts.dart';
import 'package:ghost_relay/handles.dart';
import 'package:ghost_relay/texts.dart';

/// Making a Ghost account and signing in to it on other devices, end to end against the relay's own accounts and
/// handles (relay/lib/accounts.dart, handles.dart) in this process (Matt, 2026-11-17: "We need to have a way to login to
/// existing accounts. We might need to add password based authentication as well as SMS verification for verified
/// numbers"; "i also want accounts to be generated based on ethereum type addresses with a recovery seed we can back
/// up"). Each device has its own identity, secure storage and preferences, as an install does.
class FakeTexts implements TextCodes {
  final sent = <String, String>{};
  var n = 0;
  @override
  Future<Texted> send(String number) async {
    sent[number] = '${700000 + ++n}';
    return Texted.sent;
  }

  @override
  Future<bool?> check(String number, String code) async => sent[number] == code ? (sent.remove(number) != null) : false;
}

/// One install: its identity (as the hub would know it), what it keeps securely, its preferences and its profile.
class Device implements AccountPort, AccountRelay, AccountProfiles {
  Device(this.relayAccounts, this.handles, {NetKeys? keys, this.username = '', this.hasFriends = false}) : keys = keys ?? NetKeys.generate() {
    _connect();
  }

  final Accounts relayAccounts;
  final Handles handles;
  NetKeys keys;
  String username;
  bool hasFriends;
  final secrets = <String, String>{};
  final store = MemoryMeStore();
  var restarts = 0;
  AccountBackup? applied;

  /// The hub's name for this device's connection, made as it connected: an identity taken on goes on speaking under the
  /// old name until the app starts again.
  late String connection;
  final heard = <Map<String, Object?>>[];

  void _connect() {
    connection = keys.id;
    handles.came(connection, heard.add, key: keys.public);
  }

  late final Account account = Account(relay: this, port: this, store: store, profiles: this);

  // AccountRelay: the relay's accounts, answered in this process.
  @override
  String get hubId => connection;
  @override
  Future<Map<String, dynamic>> ask(Map<String, Object?> what) async {
    Map<String, Object?>? got;
    await relayAccounts.said(connection, what, (m) => got = m);
    if (got!['dir'] == 'err') throw AccountError(got!['err'] as String);
    return Map<String, dynamic>.from(got!);
  }

  // AccountPort
  @override
  Future<Uint8List> identityExport() async => keys.scalar;
  @override
  Future<void> identityImport(List<int> scalar, List<int> public) async {
    keys = NetKeys.fromScalar(scalar);
    expect(keys.public, public);
  }

  @override
  Future<void> secretKeep(String name, String value) async => value.isEmpty ? secrets.remove(name) : secrets[name] = value;
  @override
  Future<String?> secretRead(String name) async => secrets[name];
  @override
  Future<bool> restart() async {
    restarts++;
    // Started again: connected under the identity it has now.
    _connect();
    return true;
  }

  // AccountProfiles
  @override
  bool get fresh => username.isEmpty && !hasFriends;
  @override
  String get deviceName => 'Test ${keys.id.substring(0, 4)}';
  @override
  AccountBackup fill(AccountBackup b) => b.copyWith(username: username, displayName: 'Maya Chen', friends: hasFriends ? const [{'u': 'sam'}] : const []);
  @override
  Future<void> apply(AccountBackup b) async {
    applied = b;
    username = b.username;
  }

  @override
  Future<void> forget() async => username = '';
  @override
  Future<void> stopAll() async {}

  Future<void> claim(String name) async {
    await handles.said(connection, {'dir': 'claim', 'name': name});
    expect(heard.last['ok'], isTrue);
    username = name;
  }
}

void main() {
  late FakeTexts texts;
  late Handles handles;
  late Accounts accounts;

  setUp(() {
    texts = FakeTexts();
    handles = Handles(texts: texts)..load();
    accounts = Accounts(handles: handles);
  });

  Future<(Device, AccountDraft)> made({String password = 'correct horse battery'}) async {
    final phone = Device(accounts, handles, hasFriends: true);
    await phone.claim('maya');
    final draft = phone.account.draft();
    expect(await phone.account.create(draft, password), isFalse, reason: 'an install people know keeps its own key');
    return (phone, draft);
  }

  test('an install with friends makes an account: its own key kept, the words in secure storage, nothing in the clear', () async {
    final before = NetKeys.generate();
    final phone = Device(accounts, handles, keys: before, hasFriends: true);
    await phone.claim('maya');
    final draft = phone.account.draft();
    expect(draft.words.length, 12);
    expect(AccountCrypto.goodAddress(draft.address), isTrue);
    expect(await phone.account.create(draft, 'correct horse battery'), isFalse);
    expect(phone.keys.id, before.id, reason: 'bound: the identity friends know stays');
    expect(phone.account.address, draft.address);
    expect(phone.account.mode, 'bound');
    expect(phone.secrets['account_words'], draft.words.join(' '));
    // The preferences hold the address, the device and a sealed blob: no word, no key.
    final prefs = phone.store.kept.values.join(' ');
    for (final w in draft.words.toSet()) {
      expect(RegExp('\\b$w\\b').hasMatch(prefs), isFalse, reason: 'a recovery word in the preferences');
    }
    expect(prefs.contains(NetCrypto.hex(before.scalar)), isFalse);
    expect(accounts.accountOf(before.id), draft.address.toLowerCase());
    expect((await phone.account.devices()).single.here, isTrue);
  });

  test('signed in on a new device by username and password: the same identity, profile and friends, and a clean start', () async {
    final (phone, draft) = await made();
    final fresh = Device(accounts, handles);
    expect((await fresh.account.findByName('@Maya')).phone, isFalse);
    await expectLater(fresh.account.signInWithPassword('maya', 'wrong password'), throwsA(isA<AccountError>().having((e) => e.message, 'message', 'That password isn\'t right.')));
    final restore = await fresh.account.signInWithPassword('maya', 'correct horse battery');
    expect(restore.address, draft.address);
    expect(await fresh.account.finish(restore), isTrue);
    expect(fresh.keys.id, phone.keys.id, reason: 'the account\'s Ghost identity, in place of the fresh one');
    expect(fresh.restarts, 1);
    expect(fresh.applied!.username, 'maya');
    expect(fresh.applied!.friends, isNotEmpty);
    expect(fresh.account.address, draft.address);
    final list = await fresh.account.devices();
    expect(list.length, 2);
    expect(list.where((d) => d.here).length, 1);
    await expectLater(Device(accounts, handles).account.findByName('nobody'), throwsA(isA<AccountError>()));
  });

  test('a verified number: a code texted to it is needed, to that number only', () async {
    final (phone, _) = await made();
    await handles.said(phone.connection, {'dir': 'text', 'p': 'phone', 'handle': '+14155550100'});
    await handles.said(phone.connection, {'dir': 'code', 'p': 'phone', 'handle': '+14155550100', 'code': texts.sent['+14155550100']});
    final fresh = Device(accounts, handles);
    expect((await fresh.account.findByName('maya')).phone, isTrue);
    await expectLater(fresh.account.signInWithPassword('maya', 'correct horse battery'), throwsA(isA<AccountNeedsCode>()));
    await expectLater(fresh.account.textCode('maya', '+1 415 555 0199'), throwsA(isA<AccountError>()));
    await fresh.account.textCode('maya', '(415) 555-0100');
    await expectLater(fresh.account.signInWithPassword('maya', 'correct horse battery', number: '+14155550100', code: '123456'), throwsA(isA<AccountError>()));
    final restore = await fresh.account.signInWithPassword('maya', 'correct horse battery', number: '+14155550100', code: texts.sent['+14155550100']);
    await fresh.account.finish(restore);
    expect(fresh.keys.id, phone.keys.id);
  });

  test('signed in with the recovery words alone: no password, no text', () async {
    final (phone, draft) = await made();
    await handles.said(phone.connection, {'dir': 'text', 'p': 'phone', 'handle': '+14155550100'});
    await handles.said(phone.connection, {'dir': 'code', 'p': 'phone', 'handle': '+14155550100', 'code': texts.sent['+14155550100']});
    final fresh = Device(accounts, handles);
    await expectLater(fresh.account.signInWithWords([...draft.words.sublist(0, 11), draft.words[0] == 'zoo' ? 'abandon' : 'zoo']), throwsA(isA<AccountError>()));
    final restore = await fresh.account.signInWithWords(draft.words);
    expect(restore.backedUp, isTrue);
    await fresh.account.finish(restore);
    expect(fresh.keys.id, phone.keys.id);
    // The password's copy came with it: the words can be shown here again for the password.
    expect(await fresh.account.revealWords('correct horse battery'), draft.words);
  });

  test('a fresh install\'s account is the words\' own identity: restored from the words even with no backup left', () async {
    final first = Device(accounts, handles);
    final draft = first.account.draft();
    expect(await first.account.create(draft, 'pw for a fresh one'), isTrue, reason: 'it takes on the words\' identity and starts again');
    final seedIdentity = AccountCrypto.identityOf(AccountCrypto.seedOf(draft.words));
    expect(first.keys.id, seedIdentity.id);
    expect(first.account.mode, 'seed');
    // The relay loses everything (or the account is deleted): the words still make the same identity.
    final empty = Accounts(handles: handles);
    final elsewhere = Device(empty, handles);
    final restore = await elsewhere.account.signInWithWords(draft.words);
    expect(restore.backedUp, isFalse);
    await expectLater(elsewhere.account.finish(restore), throwsA(isA<AccountError>()), reason: 'a new password is needed to back it up again');
    await elsewhere.account.finish(restore, password: 'a new one');
    expect(elsewhere.keys.id, seedIdentity.id);
    expect(empty.accountOf(seedIdentity.id), draft.address.toLowerCase());
  });

  test('a new password: the old one opens nothing, the new one does; the words shown only for the password', () async {
    final (phone, draft) = await made();
    await expectLater(phone.account.revealWords('nope'), throwsA(isA<AccountError>()));
    expect(await phone.account.revealWords('correct horse battery'), draft.words);
    await expectLater(phone.account.changePassword('nope', 'next one'), throwsA(isA<AccountError>()));
    await phone.account.changePassword('correct horse battery', 'next one');
    final fresh = Device(accounts, handles);
    await expectLater(fresh.account.signInWithPassword('maya', 'correct horse battery'), throwsA(isA<AccountError>()));
    expect((await fresh.account.signInWithPassword('maya', 'next one')).address, draft.address);
    expect(await phone.account.revealWords('next one'), draft.words);
  });

  test('a device removed from another forgets the account when it next asks; signing out leaves it someone new', () async {
    final (phone, _) = await made();
    final laptop = Device(accounts, handles);
    await laptop.account.finish(await laptop.account.signInWithPassword('maya', 'correct horse battery'));
    final listed = await phone.account.devices();
    final theirs = listed.firstWhere((d) => !d.here);
    expect((await phone.account.removeDevice(theirs.id)).length, 1);
    await laptop.account.check();
    expect(laptop.account.signedIn, isFalse);
    expect(laptop.account.removedHere, isTrue);
    expect(laptop.secrets, isEmpty);
    // Signing out the phone itself: off the list, the words gone, a new identity of its own.
    final was = phone.keys.id;
    await phone.account.signOut();
    expect(phone.account.signedIn, isFalse);
    expect(phone.keys.id, isNot(was));
    expect(phone.username, isEmpty);
  });

  test('the backup is brought up to date from the device, with the password\'s key kept beside the words', () async {
    final (phone, draft) = await made();
    expect(phone.secrets.containsKey('account_pwkey'), isTrue);
    phone.hasFriends = false;
    expect(await phone.account.refresh(), isTrue);
    expect(await phone.account.refresh(), isFalse, reason: 'once a day');
    final fresh = Device(accounts, handles);
    final restore = await fresh.account.signInWithPassword('maya', 'correct horse battery');
    expect(restore.backup.friends, isEmpty, reason: 'friends as they are now');
    // Signed in by the words: no password typed here, so nothing to seal with until it is.
    final byWords = Device(accounts, handles);
    await byWords.account.finish(await byWords.account.signInWithWords(draft.words));
    expect(await byWords.account.refresh(force: true), isFalse);
    await byWords.account.revealWords('correct horse battery');
    expect(await byWords.account.refresh(force: true), isTrue);
  });

  test('signing in by password sends only the proof, never weaker than an account is made with', () async {
    await made();
    // A relay offering cheaper Argon2id settings than an account is made with gets no proof at all.
    final fresh = _Tampering(accounts, handles);
    await expectLater(fresh.account.signInWithPassword('maya', 'correct horse battery'), throwsA(isA<AccountError>()));
    expect(fresh.said.where((m) => m['dir'] == 'acct-get'), isEmpty);
    // Honest: the password itself never leaves, only the proof, which is not the key that seals the copy.
    fresh.weaken = false;
    final restore = await fresh.account.signInWithPassword('maya', 'correct horse battery');
    final get = fresh.said.singleWhere((m) => m['dir'] == 'acct-get');
    expect(get.toString().contains('correct horse battery'), isFalse);
    final pk = restore.passwordKey!;
    expect(get['auth'], NetCrypto.hex(pk.auth));
    expect(NetCrypto.hex(pk.auth), isNot(NetCrypto.hex(pk.key)));
    expect(pk.verifier, NetCrypto.hex(NetCrypto.sha256(pk.auth)));
  });
}

/// A device whose relay, where [weaken], offers Argon2id settings cheaper than an account is made with.
class _Tampering extends Device {
  _Tampering(super.relayAccounts, super.handles);
  var weaken = true;
  final said = <Map<String, Object?>>[];
  @override
  Future<Map<String, dynamic>> ask(Map<String, Object?> what) async {
    said.add(what);
    final m = await super.ask(what);
    if (weaken && m['kdf'] is Map) m['kdf'] = {...(m['kdf'] as Map), 'm': 8 * 1024, 't': 1};
    return m;
  }
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/account/account.dart';
import 'package:ghost_messaging/account/account_crypto.dart';
import 'package:ghost_messaging/circles/circle_keys.dart' show CircleKeys;
import 'package:ghost_messaging/me/me.dart' show Me, MemoryMeStore;
import 'package:ghost_messaging/net/crypto.dart';
import 'package:ghost_messaging/net/forward_secrecy.dart' show ForwardSecrecy;
import 'package:ghost_messaging/net/p2p/p2p.dart' show P2p;
import 'package:ghost_messaging/sms.dart' show Sms;
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

  @override
  Future<bool> identityForget() async => false;

  /// Each time everything here was deleted ([Account] on a device of its own), with why.
  final wipes = <String>[];
  @override
  Future<void> wipeHere(String note) async {
    wipes.add(note);
    secrets.clear();
    store.kept.clear();
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
  var stops = 0, profileWipes = 0;
  @override
  Future<void> stopAll() async => stops++;
  @override
  Future<void> wipe() async => profileWipes++;

  Future<void> claim(String name) async {
    await handles.said(connection, {'dir': 'claim', 'name': name});
    expect(heard.last['ok'], isTrue);
    username = name;
  }
}

/// An iPhone: it can't start itself again.
class _Stuck extends Device {
  _Stuck(super.relayAccounts, super.handles);
  @override
  Future<bool> restart() async {
    restarts++;
    return false;
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

  Future<(Device, AccountDraft)> made({String password = 'correct horse battery', String name = 'maya'}) async {
    final phone = Device(accounts, handles, hasFriends: true);
    await phone.claim(name);
    final draft = phone.account.draft();
    expect(await phone.account.create(draft, password), isFalse, reason: 'an install people know keeps its own key');
    return (phone, draft);
  }

  /// Another account, beside [made]'s.
  Future<(Device, AccountDraft)> made2() => made(name: 'nell');

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

  // docs/OPEN_NETWORK.md, section 1: the node key is the device's, and a device that leaves an account takes nothing of
  // it along: not the key its node id is made from, nor the cards of the account's friends, nor what it told whom.
  test('signing out deletes the device\'s place on the direct network: the node key, its card, the cards held and what was told', () async {
    final (phone, _) = await made();
    phone.secrets[P2p.keyName] = 'ab' * 32;
    for (final name in P2p.keptNames) {
      phone.store.set(name, '{"kept":"while signed in"}');
    }
    phone.store.set(P2p.helpersOnlyName, 'on');
    await phone.account.signOut();
    expect(phone.secrets.keys, isNot(contains(P2p.keyName)));
    for (final name in P2p.keptNames) {
      expect(phone.store.choice(name, 'unset'), isEmpty, reason: name);
    }
    expect(P2p.keptNames, containsAll(['p2p_id', 'p2p_card', 'p2p_cards', 'p2p_told']));
    expect(phone.store.choice(P2p.helpersOnlyName, ''), 'on', reason: 'the person\'s choice stays');
    // And on a device another device removed, when it next asks.
    final (other, _) = await made2();
    final laptop = Device(accounts, handles);
    await laptop.account.finish(await laptop.account.signInWithPassword('nell', 'correct horse battery'));
    laptop.secrets[P2p.keyName] = 'cd' * 32;
    laptop.store.set(P2p.cardsName, '{"x":[]}');
    final theirs = (await other.account.devices()).firstWhere((d) => !d.here);
    await other.account.removeDevice(theirs.id);
    await laptop.account.check();
    expect(laptop.account.signedIn, isFalse);
    expect(laptop.secrets, isEmpty);
    expect(laptop.store.choice(P2p.cardsName, 'unset'), isEmpty);
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

  // A page in a browser keeps no recovery words and no password key (Account.keepsWords): anything running in the page
  // could open what it keeps. The password opens them from the sealed copy each time they are wanted.
  group('in a browser', () {
    setUp(() {
      Sms.browser = true;
      Sms.standalone = true;
    });
    tearDown(() {
      Sms.browser = false;
      Sms.standalone = false;
    });

    test('making an account, or signing in, keeps no words and no password key: only the key copies are sealed with', () async {
      final page = Device(accounts, handles, hasFriends: true);
      await page.claim('maya');
      final draft = page.account.draft();
      await page.account.create(draft, 'correct horse battery');
      expect(page.secrets.keys, [Me.mineSecret]);
      expect(page.secrets[Me.mineSecret], NetCrypto.hex(Me.mineKeyOf(draft.words)));
      // Nothing of the words anywhere it keeps.
      final kept = [...page.secrets.values, ...page.store.kept.values].join(' ');
      for (final w in draft.words.toSet()) {
        expect(RegExp('\\b$w\\b').hasMatch(kept), isFalse, reason: 'a recovery word kept in a browser');
      }
      // Shown, and a new password: for the password, and still nothing kept of it.
      expect(await page.account.revealWords('correct horse battery'), draft.words);
      await page.account.changePassword('correct horse battery', 'a new one here');
      expect(page.secrets.keys, [Me.mineSecret]);
      // Signed in on another browser: the same.
      final other = Device(accounts, handles);
      await other.account.finish(await other.account.signInWithPassword('maya', 'a new one here'));
      expect(other.secrets.keys, [Me.mineSecret]);
      expect(other.secrets[Me.mineSecret], page.secrets[Me.mineSecret]);
      // And by the words: nothing of them kept either, nor the identity it had before.
      final third = Device(accounts, handles);
      await third.account.finish(await third.account.signInWithWords(draft.words));
      expect(third.secrets.keys, [Me.mineSecret]);
    });

    test('the devices, a removal and the backup brought up to date are opened with the password each time', () async {
      final page = Device(accounts, handles, hasFriends: true);
      await page.claim('maya');
      final draft = page.account.draft();
      await page.account.create(draft, 'correct horse battery');
      // Nothing it keeps can sign for the account.
      await expectLater(page.account.devices(), throwsA(isA<AccountError>().having((e) => e.message, 'says', contains('password'))));
      await expectLater(page.account.keysWith('not it'), throwsA(isA<AccountError>()));
      final keys = await page.account.keysWith('correct horse battery');
      final other = Device(accounts, handles);
      await other.account.finish(await other.account.signInWithPassword('maya', 'correct horse battery'));
      final list = await page.account.devices(keys: keys);
      expect(list, hasLength(2));
      expect((await page.account.removeDevice(list.firstWhere((d) => !d.here).id, keys: keys)), hasLength(1));
      // Once a day by itself is not for a browser: only when asked, with the password.
      expect(await page.account.refresh(force: true), isFalse);
      page.hasFriends = false;
      await expectLater(page.account.refreshWith('not it'), throwsA(isA<AccountError>()));
      expect(await page.account.refreshWith('correct horse battery'), isTrue);
      final fresh = Device(accounts, handles);
      expect((await fresh.account.signInWithPassword('maya', 'correct horse battery')).backup.username, 'maya');
      expect(page.secrets.keys, [Me.mineSecret]);
    });

    test('a store from before, with the words in it: the key made from them kept in their place, the words gone', () async {
      final page = Device(accounts, handles);
      final words = page.account.draft().words;
      page.secrets['account_words'] = words.join(' ');
      page.secrets['account_pwkey'] = '{"v":1}';
      page.account.start(page.store);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(page.secrets, {Me.mineSecret: NetCrypto.hex(Me.mineKeyOf(words))});
    });

    // The phone beside the page is a phone: what it does is done as one.
    Future<T> asPhone<T>(Future<T> Function() what) async {
      Sms.browser = false;
      Sms.standalone = false;
      try {
        return await what();
      } finally {
        Sms.browser = true;
        Sms.standalone = true;
      }
    }

    test('signing out takes it off the list by its own number, and deletes everything here', () async {
      final (phone, _) = await asPhone(made);
      final page = Device(accounts, handles);
      await page.account.finish(await page.account.signInWithPassword('maya', 'correct horse battery'));
      expect(await asPhone(phone.account.devices), hasLength(2));
      final restarts = page.restarts;
      expect(await page.account.signOut(), isTrue);
      expect(page.wipes, ['signed-out']);
      expect(page.stops, greaterThan(0), reason: 'the routes stopped before anything was deleted');
      expect(page.restarts, restarts + 1);
      expect(page.secrets, isEmpty);
      // Off the account's list, though it keeps no key to sign that with.
      expect(await asPhone(phone.account.devices), hasLength(1));
      expect(phone.account.signedIn, isTrue);
    });

    test('removed from another device: everything here deleted the next time it asks', () async {
      final (phone, _) = await asPhone(made);
      final page = Device(accounts, handles);
      await page.account.finish(await page.account.signInWithPassword('maya', 'correct horse battery'));
      final theirs = (await asPhone(phone.account.devices)).firstWhere((d) => !d.here);
      await asPhone(() => phone.account.removeDevice(theirs.id));
      await page.account.check();
      expect(page.account.removedHere, isTrue);
      expect(page.wipes, ['removed']);
      expect(page.secrets, isEmpty);
      expect(page.store.kept, isEmpty);
    });
  });

  // An iPhone, or a computer with no phone (Sms.standalone): removed, it stops being the account altogether; signing out
  // offers to delete everything here too, and says what stays where it doesn't (lib/ui/account_screens.dart).
  group('on a device of its own', () {
    setUp(() => Sms.standalone = true);
    tearDown(() => Sms.standalone = false);

    test('removed from another device: everything of the account here deleted, its keys first, the routes stopped', () async {
      final (phone, _) = await made();
      final laptop = Device(accounts, handles);
      await laptop.account.finish(await laptop.account.signInWithPassword('maya', 'correct horse battery'));
      laptop.secrets[ForwardSecrecy.secretsName] = 'prekeys';
      laptop.secrets[CircleKeys.secretsName] = 'circle keys';
      final theirs = (await phone.account.devices()).firstWhere((d) => !d.here);
      await phone.account.removeDevice(theirs.id);
      final restarts = laptop.restarts;
      await laptop.account.check();
      expect(laptop.account.removedHere, isTrue);
      expect(laptop.wipes, ['removed']);
      expect(laptop.stops, greaterThan(0));
      expect(laptop.profileWipes, 1, reason: 'its Files spaces\' files too');
      expect(laptop.secrets, isEmpty);
      expect(laptop.restarts, restarts + 1);
      expect(laptop.account.ended, isFalse, reason: 'it started again by itself');
    });

    test('signing out keeps the conversations unless everything is to go; either way off the list', () async {
      final (phone, _) = await made();
      final laptop = Device(accounts, handles);
      await laptop.account.finish(await laptop.account.signInWithPassword('maya', 'correct horse battery'));
      await laptop.account.signOut();
      expect(laptop.wipes, isEmpty, reason: 'signed out as before: someone new, the rest stays');
      expect(laptop.account.signedIn, isFalse);
      expect(await phone.account.devices(), hasLength(1));
      final mac = Device(accounts, handles);
      await mac.account.finish(await mac.account.signInWithPassword('maya', 'correct horse battery'));
      mac.secrets[ForwardSecrecy.secretsName] = 'prekeys';
      expect(await mac.account.signOut(everything: true), isTrue);
      expect(mac.wipes, ['signed-out']);
      expect(mac.secrets, isEmpty);
      expect(await phone.account.devices(), hasLength(1));
    });

    test('a device that can\'t start again by itself shows only that it is to be opened again', () async {
      final (phone, _) = await made();
      final iphone = _Stuck(accounts, handles);
      await iphone.account.finish(await iphone.account.signInWithPassword('maya', 'correct horse battery'));
      await phone.account.removeDevice((await phone.account.devices()).firstWhere((d) => !d.here).id);
      var told = 0;
      iphone.account.addListener(() => told++);
      await iphone.account.check();
      expect(iphone.account.ended, isTrue);
      expect(told, greaterThan(0));
    });
  });

  // An Android phone (or a computer paired with one): removed, it forgets the account's words and keys, as before.
  test('elsewhere, a removed device forgets the account and deletes nothing else', () async {
    final (phone, _) = await made();
    final android = Device(accounts, handles);
    await android.account.finish(await android.account.signInWithPassword('maya', 'correct horse battery'));
    await phone.account.removeDevice((await phone.account.devices()).firstWhere((d) => !d.here).id);
    await android.account.check();
    expect(android.wipes, isEmpty);
    expect(android.account.signedIn, isFalse);
    expect(android.secrets, isEmpty);
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

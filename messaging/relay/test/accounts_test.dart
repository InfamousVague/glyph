import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ghost_relay/accounts.dart';
import 'package:ghost_relay/handles.dart';
import 'package:ghost_relay/hub.dart';
import 'package:ghost_relay/p256.dart';
import 'package:ghost_relay/relay.dart';
import 'package:ghost_relay/secp256k1.dart';
import 'package:ghost_relay/sha256.dart';
import 'package:ghost_relay/texts.dart';
import 'package:test/test.dart';

/// Ghost accounts on the relay (accounts.dart; Matt, 2026-11-17: "We need to have a way to login to existing accounts.
/// We might need to add password based authentication as well as SMS verification for verified numbers"): sealed
/// blobs kept by address, found by username, handed over after a texted code where a number is verified, and written
/// only by the account's own signature.
final _rnd = Random(7);
List<int> _bytes(int n) => [for (var i = 0; i < n; i++) _rnd.nextInt(256)];
List<int> _unhex(String s) => [for (var i = 0; i + 1 < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)];

/// A password blob as the app makes one: its Argon2id settings and salt, and [c] standing for the sealed part.
String pwBlob(String c) => jsonEncode({'v': 1, 'k': 'argon2id', 'm': 65536, 't': 3, 'p': 1, 's': base64Encode(List.filled(16, 1)), 'c': c});

/// The proof a password makes (the app's is HKDF of its Argon2id key; any 32 bytes do here), as `acct-get` carries it.
List<int> _proof(String password) => sha256(utf8.encode('proof|$password'));
final right = hexOf(_proof('right'));

/// A Ghost identity (P-256, as the hub knows it) with an account key (secp256k1, as the address is made).
class Who {
  Who() : identity = _bytes(32), account = _bytes(32);
  final List<int> identity;
  final List<int> account;
  List<int> get key => P256.publicOf(identity);
  String get id => hexOf(sha256(key).sublist(0, 16));
  String get address => Secp256k1.addressOfScalar(account);

  /// A message signed as the account, said from the connection [by].
  Map<String, Object?> signed(String dir, String op, String by, Map<String, Object?> more, {DateTime? at, List<int>? as}) {
    final body = jsonEncode({'op': op, 'a': address, 'by': by, 'at': (at ?? DateTime.now()).millisecondsSinceEpoch, ...more});
    final sig = Secp256k1.sign(as ?? account, utf8.encode(body), _bytes(32));
    return {'dir': dir, 'body': body, 'sig': hexOf(sig)};
  }

  Map<String, Object?> put(String by, {String? pw, String password = 'right', String seed = 'SEED-BLOB', List<int>? bindWith, DateTime? at, List<int>? as}) => signed('acct-put', 'put', by, {
        'id': id,
        'key': base64Encode(key),
        'bind': base64Encode(P256.sign(bindWith ?? identity, utf8.encode('ghost-account bind v1|${address.toLowerCase()}'), _bytes(32))),
        'pw': pw ?? pwBlob('PW'),
        'pwv': hexOf(sha256(_proof(password))),
        'seed': seed,
      }, at: at, as: as);
}

class FakeTexts implements TextCodes {
  final sent = <String, String>{};
  var count = 0;
  @override
  Future<Texted> send(String number) async {
    count++;
    sent[number] = '${100000 + count}';
    return Texted.sent;
  }

  @override
  Future<bool?> check(String number, String code) async {
    final ok = sent[number] == code;
    if (ok) sent.remove(number);
    return ok;
  }
}

void main() {
  late Directory dir;
  late FakeTexts texts;
  late Handles handles;
  late Accounts accounts;
  late Map<String, List<Map<String, Object?>>> heard;
  final tells = <String, void Function(Map<String, Object?>)>{};

  void Function(Map<String, Object?>) tellOf(String id) => tells[id] ??= (m) => (heard[id] ??= []).add(m);
  Map<String, Object?> last(String id) => heard[id]!.last;
  void come(String id, List<int> key) {
    heard[id] ??= [];
    handles.came(id, tellOf(id), key: key);
  }

  Future<Map<String, Object?>> ask(String id, Map<String, Object?> what) async {
    await accounts.said(id, what, tellOf(id));
    return last(id);
  }

  Future<void> claim(Who w, String name) async {
    come(w.id, w.key);
    await handles.said(w.id, {'dir': 'claim', 'name': name});
    expect(last(w.id), containsPair('ok', true));
  }

  Future<void> verify(Who w, String number) async {
    await handles.said(w.id, {'dir': 'text', 'p': 'phone', 'handle': number});
    await handles.said(w.id, {'dir': 'code', 'p': 'phone', 'handle': number, 'code': texts.sent[Handles.tidyNumber(number)]});
    expect(last(w.id), containsPair('dir', 'linked'));
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('accounts');
    texts = FakeTexts();
    heard = {};
    tells.clear();
    handles = Handles(dataDir: dir, texts: texts)..load();
    accounts = Accounts(dataDir: dir, handles: handles)..load();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('made by the account\'s signature with the identity\'s proof; found by username; the password\'s blob handed to a new install', () async {
    final maya = Who();
    await claim(maya, 'maya');
    expect(await ask(maya.id, maya.put(maya.id)), {'dir': 'acct-put', 'ok': true, 'a': maya.address.toLowerCase()});
    expect(accounts.accountOf(maya.id), maya.address.toLowerCase());
    // A new phone, with a key of its own, signing in.
    final fresh = Who();
    final found = await ask(fresh.id, {'dir': 'acct-find', 'name': '@Maya'});
    expect(found, containsPair('phone', false));
    // The blob's settings and salt, to make the proof of the password from; never its sealed part.
    expect(found['kdf'], {'v': 1, 'k': 'argon2id', 'm': 65536, 't': 3, 'p': 1, 's': base64Encode(List.filled(16, 1))});
    expect(await ask(fresh.id, {'dir': 'acct-find', 'name': 'nobody'}), containsPair('none', true));
    final got = await ask(fresh.id, {'dir': 'acct-get', 'name': 'maya', 'auth': right});
    expect(got['blob'], pwBlob('PW'));
    expect(got['a'], maya.address.toLowerCase());
    // A new password: the blobs replaced, the account the same.
    await ask(maya.id, maya.put(maya.id, pw: pwBlob('PW-2')));
    expect((await ask(fresh.id, {'dir': 'acct-get', 'name': 'maya', 'auth': right}))['blob'], pwBlob('PW-2'));
  });

  test('writes that are not the account\'s, not fresh, not from this connection, or not agreed by the identity are refused', () async {
    final maya = Who(), sam = Who();
    await claim(maya, 'maya');
    String? err(Map<String, Object?> m) => m['dir'] == 'err' ? m['err'] as String : null;
    expect(err(await ask(maya.id, maya.put(maya.id, as: sam.account))), 'That is not signed by the account.');
    expect(err(await ask(maya.id, maya.put(sam.id))), 'That is not signed for this.');
    expect(err(await ask(maya.id, maya.put(maya.id, at: DateTime.now().subtract(const Duration(minutes: 30))))), contains('clock'));
    expect(err(await ask(maya.id, maya.put(maya.id, bindWith: sam.identity))), 'That identity did not agree to this account.');
    expect(err(await ask(maya.id, {...maya.put(maya.id), 'sig': 'zz'})), 'That is not signed.');
    expect(err(await ask(maya.id, maya.put(maya.id, pw: 'x' * (Accounts.maxBlob + 1)))), contains('too big'));
    expect(accounts.count, 0);
    // One account to an identity: a second address for Maya's identity is refused.
    await ask(maya.id, maya.put(maya.id));
    final same = _SameIdentity(maya, Who());
    expect(err(await ask(maya.id, same.put(maya.id))), 'This Ghost identity already has an account.');
    // Written from another connection (a restored device with another hub name) is fine, so long as it says so.
    expect(await ask(sam.id, maya.put(sam.id, pw: pwBlob('from elsewhere'))), containsPair('ok', true));
  });

  test('a verified number: the password\'s blob only after a fresh code texted to it', () async {
    final maya = Who();
    await claim(maya, 'maya');
    await verify(maya, '+1 415 555 0100');
    await ask(maya.id, maya.put(maya.id));
    final fresh = Who();
    expect(await ask(fresh.id, {'dir': 'acct-find', 'name': 'maya'}), containsPair('phone', true));
    // Without a code: told one is needed, and no blob.
    final asked = await ask(fresh.id, {'dir': 'acct-get', 'name': 'maya'});
    expect(asked, {'dir': 'acct-get', 'name': 'maya', 'phone': true});
    // Another number is never texted on the account's behalf.
    expect(await ask(fresh.id, {'dir': 'acct-text', 'name': 'maya', 'number': '+1 415 555 0199'}), containsPair('err', 'That isn\'t the number verified on this account.'));
    final before = texts.count;
    expect(await ask(fresh.id, {'dir': 'acct-text', 'name': 'maya', 'number': '(415) 555-0100'}), containsPair('sent', true));
    expect(texts.count, before + 1);
    expect(await ask(fresh.id, {'dir': 'acct-get', 'name': 'maya', 'number': '+14155550100', 'code': '000000'}), containsPair('err', contains('not the code')));
    // A code asked for by one install cannot be tried by another.
    final other = Who();
    expect(await ask(other.id, {'dir': 'acct-get', 'name': 'maya', 'number': '+14155550100', 'code': texts.sent['+14155550100']}), containsPair('err', contains('Ask for a code first')));
    final got = await ask(fresh.id, {'dir': 'acct-get', 'name': 'maya', 'number': '+14155550100', 'code': texts.sent['+14155550100'], 'auth': right});
    expect(got['blob'], pwBlob('PW'));
    // Used once: the same code again is not enough.
    expect(await ask(fresh.id, {'dir': 'acct-get', 'name': 'maya', 'number': '+14155550100', 'code': '100002'}), containsPair('dir', 'err'));
  });

  test('the password\'s blob only for the proof of the password: nobody takes it away to try passwords against', () async {
    final maya = Who();
    await claim(maya, 'maya');
    await ask(maya.id, maya.put(maya.id));
    final fresh = Who();
    String? err(Map<String, Object?> m) => m['dir'] == 'err' ? m['err'] as String : null;
    expect(err(await ask(fresh.id, {'dir': 'acct-get', 'name': 'maya'})), 'That password isn\'t right.');
    expect(err(await ask(fresh.id, {'dir': 'acct-get', 'name': 'maya', 'auth': hexOf(_proof('wrong'))})), 'That password isn\'t right.');
    expect(err(await ask(fresh.id, {'dir': 'acct-get', 'name': 'maya', 'auth': right.substring(2)})), 'That password isn\'t right.');
    expect(await ask(fresh.id, {'dir': 'acct-get', 'name': 'maya', 'auth': right}), containsPair('blob', pwBlob('PW')));
    // Wrong guesses count against the account from any connection: a few an hour, then none, even the right one.
    for (var i = 0; i < Accounts.getsForAccountAnHour - 4; i++) {
      await ask(Who().id, {'dir': 'acct-get', 'name': 'maya', 'auth': hexOf(_proof('guess $i'))});
    }
    expect(err(await ask(Who().id, {'dir': 'acct-get', 'name': 'maya', 'auth': right})), contains('Too many'));
    // A new password: the old proof opens nothing.
    final again = Accounts(handles: handles);
    await again.said(maya.id, maya.put(maya.id, password: 'next'), tellOf(maya.id));
    await again.said(fresh.id, {'dir': 'acct-get', 'name': 'maya', 'auth': right}, tellOf(fresh.id));
    expect(err(last(fresh.id)), 'That password isn\'t right.');
    await again.said(fresh.id, {'dir': 'acct-get', 'name': 'maya', 'auth': hexOf(_proof('next'))}, tellOf(fresh.id));
    expect(last(fresh.id), containsPair('blob', pwBlob('PW')));
  });

  test('a backup without the proof\'s check, or with a blob that is not a password blob, is not kept', () async {
    final maya = Who();
    await claim(maya, 'maya');
    final put = maya.put(maya.id);
    final body = (jsonDecode(put['body'] as String) as Map)..remove('pwv');
    expect(await ask(maya.id, maya.signed('acct-put', 'put', maya.id, {...body.cast<String, Object?>()..remove('op')..remove('a')..remove('by')..remove('at')})), containsPair('err', contains('Update the app')));
    expect(await ask(maya.id, maya.put(maya.id, pw: 'not a blob')), containsPair('err', contains('Update the app')));
    expect(accounts.count, 0);
  });

  test('a signed message is taken once: said again inside its ten minutes, it is refused', () async {
    final maya = Who();
    await claim(maya, 'maya');
    await ask(maya.id, maya.put(maya.id));
    final mac = 'b' * 32;
    final add = maya.signed('acct-devices', 'devices', maya.id, {'add': {'d': mac, 'n': 'MacBook', 'p': 'macos'}});
    await ask(maya.id, add);
    await ask(maya.id, maya.signed('acct-devices', 'devices', maya.id, {'remove': mac}));
    // The add seen on the way, said again to put the removed device back: refused, and the device stays off.
    expect(await ask(maya.id, add), containsPair('err', 'That was said already.'));
    // Nor with v written the other way (27/28 as 0/1), which is the same signature.
    final sig = _unhex(add['sig'] as String);
    sig[64] -= 27;
    expect(await ask(maya.id, {...add, 'sig': hexOf(sig)}), containsPair('err', 'That was said already.'));
    expect(await ask(maya.id, {'dir': 'acct-hello', 'a': maya.address, 'd': mac}), containsPair('known', false));
    final delete = maya.signed('acct-delete', 'delete', maya.id, const {});
    await ask(maya.id, delete);
    await ask(maya.id, maya.put(maya.id));
    expect(await ask(maya.id, delete), containsPair('err', 'That was said already.'));
    expect(accounts.count, 1);
  });

  test('a verified number cannot be found out by trying numbers, from one connection or many', () async {
    final maya = Who();
    await claim(maya, 'maya');
    await verify(maya, '+14155550100');
    await ask(maya.id, maya.put(maya.id));
    for (var i = 0; i < Accounts.numbersForAccountAnHour; i++) {
      final who = Who();
      final dir = i.isEven ? 'acct-text' : 'acct-get';
      expect(await ask(who.id, {'dir': dir, 'name': 'maya', 'number': '+1415555${1000 + i}', 'code': '123456'}), containsPair('err', contains('isn\'t the number')));
    }
    // Then even the right number says nothing, and no text is sent.
    final before = texts.count;
    expect(await ask(Who().id, {'dir': 'acct-text', 'name': 'maya', 'number': '+14155550100'}), containsPair('err', contains('Too many')));
    expect(await ask(Who().id, {'dir': 'acct-get', 'name': 'maya', 'number': '+14155550100', 'code': '123456'}), containsPair('err', contains('Too many')));
    expect(texts.count, before);
  });

  test('a right code lets that connection try the password again for a few minutes without another', () async {
    final maya = Who();
    await claim(maya, 'maya');
    await verify(maya, '+14155550100');
    await ask(maya.id, maya.put(maya.id));
    final fresh = Who();
    await ask(fresh.id, {'dir': 'acct-text', 'name': 'maya', 'number': '+14155550100'});
    final code = texts.sent['+14155550100'];
    expect(await ask(fresh.id, {'dir': 'acct-get', 'name': 'maya', 'number': '+14155550100', 'code': code, 'auth': hexOf(_proof('typo'))}), containsPair('err', 'That password isn\'t right.'));
    // Another connection still needs a code of its own.
    expect(await ask(Who().id, {'dir': 'acct-get', 'name': 'maya', 'auth': right}), containsPair('phone', true));
    expect(await ask(fresh.id, {'dir': 'acct-get', 'name': 'maya', 'auth': right}), containsPair('blob', pwBlob('PW')));
    // Handed over: the next time needs a code again.
    expect(await ask(fresh.id, {'dir': 'acct-get', 'name': 'maya', 'auth': right}), containsPair('phone', true));
  });

  test('the words\' way: both blobs to a signature by the account key, no text needed', () async {
    final maya = Who();
    await claim(maya, 'maya');
    await verify(maya, '+14155550100');
    await ask(maya.id, maya.put(maya.id));
    final fresh = Who();
    final got = await ask(fresh.id, maya.signed('acct-seed', 'seed', fresh.id, const {}));
    expect(got, {'dir': 'acct-seed', 'a': maya.address.toLowerCase(), 'blob': 'SEED-BLOB', 'pw': pwBlob('PW')});
    expect(await ask(fresh.id, maya.signed('acct-seed', 'seed', fresh.id, const {}, as: fresh.account)), containsPair('dir', 'err'));
    final nobody = Who();
    expect(await ask(fresh.id, nobody.signed('acct-seed', 'seed', fresh.id, const {})), containsPair('none', true));
  });

  test('lookups and downloads are limited per connection and per account', () async {
    final maya = Who();
    await claim(maya, 'maya');
    await ask(maya.id, maya.put(maya.id));
    final a = Who();
    for (var i = 0; i < Accounts.getsAnHour; i++) {
      expect(await ask(a.id, {'dir': 'acct-get', 'name': 'maya', 'auth': right}), containsPair('blob', pwBlob('PW')));
    }
    expect(await ask(a.id, {'dir': 'acct-get', 'name': 'maya', 'auth': right}), containsPair('err', contains('Too many')));
    // Other connections share the account's own limit.
    final b = Who();
    for (var i = 0; i < Accounts.getsForAccountAnHour - Accounts.getsAnHour; i++) {
      expect(await ask(b.id, {'dir': 'acct-get', 'name': 'maya', 'auth': right}), containsPair('blob', pwBlob('PW')));
    }
    expect(await ask(Who().id, {'dir': 'acct-get', 'name': 'maya', 'auth': right}), containsPair('err', contains('Too many')));
    final c = Who();
    for (var i = 0; i < Accounts.findsAnHour; i++) {
      await ask(c.id, {'dir': 'acct-find', 'name': 'maya$i'});
    }
    expect(await ask(c.id, {'dir': 'acct-find', 'name': 'maya'}), containsPair('err', contains('Too many')));
  });

  test('devices: added by the device signing in, listed, removed; a removed device hears so', () async {
    final maya = Who();
    await claim(maya, 'maya');
    await ask(maya.id, maya.put(maya.id));
    final phone = 'a' * 32, mac = 'b' * 32;
    await ask(maya.id, maya.signed('acct-devices', 'devices', maya.id, {'add': {'d': phone, 'n': 'Galaxy Z Fold', 'p': 'android'}}));
    final listed = await ask(maya.id, maya.signed('acct-devices', 'devices', maya.id, {'add': {'d': mac, 'n': 'MacBook', 'p': 'macos'}}));
    expect([for (final d in listed['list'] as List) (d as Map)['n']], ['Galaxy Z Fold', 'MacBook']);
    expect(await ask(maya.id, {'dir': 'acct-hello', 'a': maya.address, 'd': mac}), containsPair('known', true));
    final after = await ask(maya.id, maya.signed('acct-devices', 'devices', maya.id, {'remove': mac}));
    expect((after['list'] as List).length, 1);
    expect(await ask(maya.id, {'dir': 'acct-hello', 'a': maya.address, 'd': mac}), containsPair('known', false));
    // Not the account's signature: nothing listed or changed.
    expect(await ask(maya.id, Who().signed('acct-devices', 'devices', maya.id, {'remove': phone})), containsPair('dir', 'err'));
  });

  test('kept across a restart, with no username or number in the file; deleted by the account', () async {
    final maya = Who();
    await claim(maya, 'maya');
    await verify(maya, '+14155550100');
    await ask(maya.id, maya.put(maya.id));
    final file = File('${dir.path}/accounts.json').readAsStringSync();
    expect(file, isNot(contains('maya')));
    expect(file, isNot(contains('4155550100')));
    handles.save();
    final again = Accounts(dataDir: dir, handles: handles)..load();
    expect(again.count, 1);
    expect(again.accountOf(maya.id), maya.address.toLowerCase());
    await again.said(maya.id, maya.signed('acct-delete', 'delete', maya.id, const {}), tellOf(maya.id));
    expect(last(maya.id), containsPair('ok', true));
    expect(again.count, 0);
  });

  group('over the hub', () {
    late Relay relay;
    tearDown(() => relay.stop());

    test('acct- messages reach the accounts; what a 0.9.4 app says is answered as before', () async {
      final h = Handles(texts: texts);
      relay = Relay(hub: Hub(handles: h, accounts: Accounts(handles: h)));
      final url = 'ws://127.0.0.1:${await relay.start(port: 0)}/hub';
      final a = await _Install.connect(url);
      // An old app's hello to handles, and a username: the same answers as ever.
      a.ws.add(jsonEncode({'dir': 'hello'}));
      expect((await a.next())['dir'], 'hello');
      a.ws.add(jsonEncode({'dir': 'claim', 'name': 'maya'}));
      expect(await a.next(), containsPair('ok', true));
      a.ws.add(jsonEncode({'dir': 'acct-find', 'name': 'maya'}));
      expect(await a.next(), containsPair('none', true));
      await a.ws.close();
    });

    test('a hub without accounts says so, as one without invites does', () async {
      relay = Relay(hub: Hub(handles: Handles()));
      final url = 'ws://127.0.0.1:${await relay.start(port: 0)}/hub';
      final a = await _Install.connect(url);
      a.ws.add(jsonEncode({'dir': 'acct-find', 'name': 'maya'}));
      expect(await a.next(), {'dir': 'err', 'about': 'acct-find', 'err': 'This server keeps no accounts.'});
      await a.ws.close();
    });
  });
}

/// Another account key claiming an identity that already has an account: the same identity, its own address.
class _SameIdentity extends Who {
  _SameIdentity(this.of, Who other) : _account = other.account;
  final Who of;
  final List<int> _account;
  @override
  List<int> get identity => of.identity;
  @override
  List<int> get account => _account;
}

class _Install {
  _Install._(this.ws, this._said);
  final WebSocket ws;
  final StreamIterator<Map> _said;

  static Future<_Install> connect(String url) async {
    final scalar = _bytes(32);
    final key = P256.publicOf(scalar);
    final ws = await WebSocket.connect(url);
    final said = StreamIterator(ws.where((d) => d is String).map((d) => jsonDecode(d as String) as Map));
    await said.moveNext();
    final nonce = _unhex(said.current['hello'] as String);
    final sig = P256.sign(scalar, [...utf8.encode(Hub.greeting), ...nonce], _bytes(32));
    ws.add(jsonEncode({'id': Hub.nameOf(key), 'key': base64Encode(key), 'sig': base64Encode(sig)}));
    await said.moveNext();
    expect(said.current['ok'], isTrue);
    return _Install._(ws, said);
  }

  Future<Map> next() async {
    expect(await _said.moveNext().timeout(const Duration(seconds: 5)), isTrue);
    return _said.current;
  }
}

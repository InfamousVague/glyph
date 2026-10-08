import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/account.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/keystore.dart';

import '../core/make_note.dart';
import '../support/fake_service.dart';

/// The account on this device, against the service in memory (test/support/fake_service.dart): making one, the
/// three ways in, the two changes that need the password, what launch does with a session it finds, and the two
/// ways out. The web's `src/app/core/account/account.test.ts`, case for case.
///
/// What differs: the page has one account state for the module, read with `accountState()` whichever device's
/// `Deps` made the last change; here each device is an [Account] with its own state, so a case reads the state of
/// the device it is about. The crypto is the fake's, which is not cryptography: these are the FLOWS.
const handle = 'matt';
const password = 'correct horse';

/// A device: its own keys, and the service it talks to (`deviceOf`).
Account deviceOf(FakeService service, {KeyStore? keys, Fetcher? fetcher}) =>
    Account(keys: keys ?? MemoryKeyStore(), api: Api(base: 'http://service.test/api', fetcher: fetcher ?? service.fetcher), crypto: service.crypto, iterations: fastRounds, label: 'Test');

/// A refusal's status, or what went wrong instead (`statusOf`).
Future<Object> statusOf(Future<Object?> attempt) async {
  try {
    await attempt;
    return 'no refusal';
  } catch (failure) {
    return failure is ApiError ? failure.status : failure;
  }
}

void main() {
  group('signing up', () {
    test('makes the account, hands back a sheet of eight codes, and leaves this device signed in and unlocked', () async {
      final service = await FakeService.start();
      final phone = deviceOf(service);
      final made = await phone.signUp(handle, password);
      expect(made.codes, hasLength(8));
      expect(made.codes.toSet(), hasLength(8));
      expect(phone.value.session?.handle, handle);
      expect(phone.value.session?.accountId, 7);
      expect(phone.value.unlocked, isTrue);
      expect(await phone.keys.accountKey(), isNotNull);
      expect(await phone.keys.deviceKey(), isNotNull);
      // Signed up with the device key, so no second call to register it.
      expect(service.calls, ['POST signup']);
    });

    test('says what is wrong with a handle or a password before asking the service anything', () async {
      final service = await FakeService.start();
      expect(await statusOf(deviceOf(service).signUp('m', password)), 400);
      expect(await statusOf(deviceOf(service).signUp(handle, 'short')), 400);
      expect(service.calls, isEmpty);
    });

    test('is refused for a handle already taken', () async {
      final service = await FakeService.start();
      await deviceOf(service).signUp(handle, password);
      expect(await statusOf(deviceOf(service).signUp(handle, 'another horse')), 409);
    });
  });

  group('signing in with the password', () {
    test('comes away with the account’s own key, and registers this device once', () async {
      final service = await FakeService.start(seed: (handle: handle, password: password));
      await service.deviceWrites(makeNote('n1', body: '# Groceries'));
      final desk = deviceOf(service);
      await desk.signIn(handle, password);
      expect(desk.value.session?.handle, handle);
      expect(desk.value.unlocked, isTrue);
      // The key this device kept opens what another device sealed.
      final key = (await desk.keys.accountKey())!;
      final opened = await service.crypto.open(key, service.notes['n1']!.blob!, 'note:n1') as Map;
      expect((opened['note'] as Map)['body'], '# Groceries');
      expect(service.calls, ['POST login', 'POST device']);
      await desk.signIn(handle, password);
      expect(service.calls.where((call) => call == 'POST device'), hasLength(1));
    });

    test('is refused on the wrong password, and leaves the device as it was', () async {
      final service = await FakeService.start(seed: (handle: handle, password: password));
      final desk = deviceOf(service);
      expect(await statusOf(desk.signIn(handle, 'wrong horse')), 401);
      expect(await desk.keys.accountKey(), isNull);
      expect(desk.value.session, isNull);
    });
  });

  group('recovering with a code', () {
    test('spends the code, sets the new password, and answers a fresh sheet in place of the old', () async {
      final service = await FakeService.start();
      final first = deviceOf(service);
      final codes = (await first.signUp(handle, password)).codes;
      // That phone is gone, and the password with it: a new one starts from the sheet.
      await first.signOut();
      final lost = deviceOf(service);
      // Typed as a person types it off the sheet: case and dashes do not matter.
      final fresh = await lost.recover(handle, codes[0].toLowerCase(), 'a new horse');
      expect(fresh.codes, hasLength(8));
      expect(fresh.codes.where(codes.contains), isEmpty);
      expect(lost.value.session?.handle, handle);
      expect(lost.value.unlocked, isTrue);
      expect(await lost.keys.deviceKey(), isNotNull);
      // The password is the new one, the spent code is gone, and so is the rest of the old sheet.
      expect(await statusOf(deviceOf(service).signIn(handle, password)), 401);
      await deviceOf(service).signIn(handle, 'a new horse');
      expect(await statusOf(deviceOf(service).recover(handle, codes[0], 'third horse')), 401);
      expect(await statusOf(deviceOf(service).recover(handle, codes[1], 'third horse')), 401);
      await deviceOf(service).recover(handle, fresh.codes[3], 'third horse');
      expect(service.codesLeft(), 8);
    });

    test('will not set a password too short to keep, and asks nothing of the service for it', () async {
      final service = await FakeService.start();
      expect(await statusOf(deviceOf(service).recover(handle, 'ABCD-EFGH', 'short')), 400);
      expect(service.calls, isEmpty);
    });
  });

  group('what needs the password on a signed-in device', () {
    test('changes the password, once the current one has opened the key', () async {
      final service = await FakeService.start();
      final phone = deviceOf(service);
      await phone.signUp(handle, password);
      expect(await statusOf(phone.changePassword('wrong horse', 'a new horse')), 401);
      expect(await statusOf(phone.changePassword(password, 'short')), 400);
      await phone.changePassword(password, 'a new horse');
      expect(await statusOf(deviceOf(service).signIn(handle, password)), 401);
      await deviceOf(service).signIn(handle, 'a new horse');
    });

    test('makes a new recovery sheet, and the old one stops working', () async {
      final service = await FakeService.start();
      final phone = deviceOf(service);
      final codes = (await phone.signUp(handle, password)).codes;
      expect(await statusOf(phone.newRecoveryCodes('wrong horse')), 401);
      final next = await phone.newRecoveryCodes(password);
      expect(next.codes, hasLength(8));
      expect(await statusOf(deviceOf(service).recover(handle, codes[0], 'a new horse')), 401);
      await deviceOf(service).recover(handle, next.codes[0], 'a new horse');
    });

    test('asks for a session before either', () async {
      final service = await FakeService.start();
      expect(await statusOf(deviceOf(service).changePassword(password, 'a new horse')), 401);
      expect(await statusOf(deviceOf(service).newRecoveryCodes(password)), 401);
      expect(service.calls, isEmpty);
    });
  });

  group('resuming on launch', () {
    /// A phone signed up on the service, with the session it would find in its storage at the next launch.
    Future<({FakeService service, Account phone, Session before})> launched() async {
      final service = await FakeService.start();
      final phone = deviceOf(service);
      await phone.signUp(handle, password);
      final before = phone.value.session!;
      service.calls.clear();
      return (service: service, phone: phone, before: before);
    }

    test('renews a live session', () async {
      final (:service, :phone, :before) = await launched();
      await phone.resume();
      expect(service.calls, ['POST refresh']);
      expect(phone.value.session?.token, isNot(before.token));
      expect(phone.value.unlocked, isTrue);
    });

    test('keeps the session it had while the service cannot be reached', () async {
      final (:service, :phone, :before) = await launched();
      // The app launched again with no network: a new Account over what the phone kept.
      final offline = deviceOf(service, keys: phone.keys, fetcher: (request) async => throw const FormatException('Failed to fetch'));
      expect(offline.value, AccountState.none);
      await offline.resume();
      expect(offline.value, AccountState(session: before, unlocked: true));
    });

    test('signs in again with this device’s own key when the session has lapsed', () async {
      final (:service, :phone, :before) = await launched();
      service.expireAllTokens();
      await phone.resume();
      expect(service.calls, ['POST refresh', 'POST login/challenge', 'POST login/device']);
      expect(phone.value.session?.handle, handle);
      expect(phone.value.session?.accountId, 7);
      expect(phone.value.session?.token, isNot(before.token));
      // And the token it came away with works.
      service.calls.clear();
      await phone.resume();
      expect(service.calls, ['POST refresh']);
    });

    test('signs out, keys and all, when the session has lapsed and the device key cannot renew it', () async {
      final (:service, :phone, before: _) = await launched();
      // A key the account never registered, as on a device the account has since been taken from.
      await phone.keys.setDeviceKey(await service.crypto.newDeviceKey());
      service.expireAllTokens();
      await phone.resume();
      expect(service.calls, ['POST refresh', 'POST login/challenge', 'POST login/device']);
      expect(phone.value, AccountState.none);
      expect(await phone.keys.accountKey(), isNull);
      expect(await phone.keys.deviceKey(), isNull);
      expect(await phone.keys.session(), isNull);
    });

    test('signs out when the session has lapsed on a device with no key of its own', () async {
      final (:service, :phone, before: _) = await launched();
      service.expireAllTokens();
      await phone.keys.setDeviceKey(null);
      await phone.resume();
      expect(phone.value.session, isNull);
      expect(await phone.keys.accountKey(), isNull);
      expect(service.calls, ['POST refresh']);
    });

    test('settles signed out when there is no session to resume', () async {
      final service = await FakeService.start();
      final phone = deviceOf(service);
      await phone.resume();
      expect(phone.value, AccountState.none);
      expect(service.calls, isEmpty);
    });

    test('shows what the device kept before the service is asked anything', () async {
      // Not a case of the web's: the page reads its session as the module loads; here it is `restore`.
      final (:service, :phone, :before) = await launched();
      final again = deviceOf(service, keys: phone.keys);
      await again.restore();
      expect(again.value, AccountState(session: before, unlocked: true));
      expect(service.calls, isEmpty);
    });
  });

  group('the ways out', () {
    test('deletes the account only with the password, then signs out and leaves the notes to the device', () async {
      final service = await FakeService.start();
      final phone = deviceOf(service);
      await phone.signUp(handle, password);
      expect(await statusOf(phone.deleteAccount('wrong horse')), 403);
      expect(service.hasAccount(), isTrue);
      expect(phone.value.session, isNotNull);
      await phone.deleteAccount(password);
      expect(service.hasAccount(), isFalse);
      expect(phone.value, AccountState.none);
      expect(await phone.keys.accountKey(), isNull);
      // Gone from the service too: the password no longer signs in anywhere.
      expect(await statusOf(deviceOf(service).signIn(handle, password)), 401);
    });

    test('signs out of this device alone: the session and both keys go, the account stays', () async {
      final service = await FakeService.start();
      final phone = deviceOf(service);
      await phone.signUp(handle, password);
      var told = 0;
      phone.addListener(() => told += 1);
      await phone.signOut();
      expect(told, 1);
      expect(phone.value, AccountState.none);
      expect(await phone.keys.accountKey(), isNull);
      expect(await phone.keys.deviceKey(), isNull);
      expect(service.hasAccount(), isTrue);
      expect(await statusOf(phone.deleteAccount(password)), 401);
    });
  });

  group('the rules', () {
    test('are the service’s own for a handle and a password', () {
      expect(handleProblem('matt'), isNull);
      expect(handleProblem('  m.a-t_t9 '), isNull);
      expect(handleProblem('ma'), isNotNull);
      expect(handleProblem('.matt'), isNotNull);
      expect(handleProblem('a' * 25), isNotNull);
      expect(passwordProblem('12345678'), isNull);
      expect(passwordProblem('1234567'), isNotNull);
    });
  });
}

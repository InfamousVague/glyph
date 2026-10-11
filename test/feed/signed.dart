import 'package:flutter/foundation.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/account/session.dart';

import '../support/fake_service.dart';

/// The account as a test hands it out: a session and a key it sets by hand, where the web's tests mock the account
/// module (`vi.mock('../account/account.ts')`).
class SignedAccount extends ChangeNotifier implements AccountSource {
  SignedAccount({this.session, this.key});

  @override
  Session? session;
  SealKey? key;

  @override
  Future<SealKey?> accountKey() async => key;

  /// Signed in to [service], with a token it issued and its key here (`signIn`).
  void signIn(FakeService service) {
    session = Session(token: service.signedIn(), handle: 'matt', accountId: 7);
    key = service.accountKey;
    notifyListeners();
  }
}

/// The session the web's tests start from.
const Session testSession = Session(token: 't1', handle: 'matt', accountId: 7);

/// The account the service is seeded with.
const ({String handle, String password}) testAccount = (handle: 'matt', password: 'correct horse');

/// The service, as an [Api]: through its own fetcher, or one a test stands in front of it.
Api apiOf(FakeService service, [Fetcher? fetcher]) => Api(base: 'http://service.test/api', fetcher: fetcher ?? service.fetcher);

/// A service that answers everything 500, in its own words.
Future<FetchResponse> down(FetchRequest request) async => FetchResponse.json(500, {'error': 'The service is down.'});

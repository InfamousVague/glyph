import 'dart:convert';
import 'dart:io';

import 'package:ghost_relay/handles.dart';
import 'package:ghost_relay/hub.dart';
import 'package:ghost_relay/relay.dart';
import 'package:ghost_relay/sha256.dart';
import 'package:test/test.dart';

/// The handles people linked, with the networks stood in for: no request leaves this machine.
const alice = 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1';
const bob = 'b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2';
const carol = 'c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3';

class Net {
  /// handle -> what its public profile says, per network.
  final bios = <String, String>{};
  final follows = <String, List<String>>{};
  final asked = <String>[];

  /// Who a sign-in's code belongs to: code -> (id, username).
  final codes = <String, (String, String)>{};

  /// The text service: the code it "sent" each number and is waiting to hear back, how many texts went, the
  /// numbers it will not text, and whether it answers at all.
  final texted = <String, String>{};
  var texts = 0;
  final landlines = <String>{};
  var textsDown = false;

  Future<Fetched> fetch(String method, Uri url, {Map<String, String> headers = const {}, String? body, bool outside = false}) async {
    asked.add('$method ${url.host}${url.path}${outside ? ' (outside)' : ''}');
    final q = url.queryParameters;
    if (url.host == 'public.api.bsky.app' && url.path.endsWith('getProfile')) {
      final bio = bios['bluesky:${q['actor']}'];
      return bio == null ? const Fetched(400, '{}') : Fetched(200, jsonEncode({'did': 'did:plc:${q['actor']}', 'description': bio}));
    }
    if (url.host == 'public.api.bsky.app' && url.path.endsWith('getFollows')) {
      final all = follows['bluesky:${q['actor']}'] ?? const [];
      final from = int.parse(q['cursor'] ?? '0');
      final page = all.skip(from).take(100).toList();
      return Fetched(200, jsonEncode({'follows': [for (final h in page) {'handle': h}], if (from + 100 < all.length) 'cursor': '${from + 100}'}));
    }
    if (url.path == '/api/v1/accounts/lookup') {
      final bio = bios['mastodon:${q['acct']}@${url.host}'];
      return bio == null ? const Fetched(404, '{}') : Fetched(200, jsonEncode({'id': '77', 'note': '<p>hello</p>', 'fields': [{'name': 'ghost', 'value': bio}]}));
    }
    if (url.path == '/api/v1/accounts/77/following') {
      return Fetched(200, jsonEncode([{'acct': 'local'}, {'acct': 'far@other.example'}]));
    }
    if (url.host == 'api.github.com' && url.path.endsWith('/following')) {
      return Fetched(200, jsonEncode([for (final h in follows['github:${url.pathSegments[1]}'] ?? const []) {'login': h}]));
    }
    if (url.host == 'api.github.com') {
      final bio = bios['github:${url.pathSegments.last}'];
      return bio == null ? const Fetched(404, '{}') : Fetched(200, jsonEncode({'id': 4242, 'bio': bio}));
    }
    if (url.host == 'discord.com' && url.path == '/api/oauth2/token') {
      final code = Uri.splitQueryString(body ?? '')['code'];
      return codes.containsKey(code) ? Fetched(200, jsonEncode({'access_token': 'tok-$code'})) : const Fetched(400, '{}');
    }
    if (url.host == 'discord.com' && url.path == '/api/users/@me') {
      final who = codes[headers['Authorization']!.substring('Bearer tok-'.length)]!;
      return Fetched(200, jsonEncode({'id': who.$1, 'username': who.$2}));
    }
    if (url.host == 'api.x.com' && url.path == '/2/oauth2/token') {
      final form = Uri.splitQueryString(body ?? '');
      // PKCE: the verifier that comes back must be the one whose hash went out.
      if (!codes.containsKey(form['code']) || (form['code_verifier'] ?? '').length < 43) return const Fetched(400, '{}');
      return Fetched(200, jsonEncode({'access_token': 'tok-${form['code']}'}));
    }
    if (url.host == 'verify.twilio.com') {
      if (textsDown) return const Fetched(503, '');
      if (headers['Authorization'] != 'Basic ${base64Encode(utf8.encode('ACsid:secret'))}') return const Fetched(401, '{}');
      final form = Uri.splitQueryString(body ?? '');
      final to = form['To']!;
      if (url.path == '/v2/Services/VAservice/Verifications') {
        if (form['Channel'] != 'sms') return const Fetched(400, '{}');
        if (landlines.contains(to)) return const Fetched(403, '{"code": 60205}');
        texts++;
        // The same code while one is waiting, as the service sends it.
        texted[to] ??= '${482913 + texts}';
        return Fetched(201, jsonEncode({'status': 'pending', 'to': to}));
      }
      if (url.path == '/v2/Services/VAservice/VerificationCheck') {
        final want = texted[to];
        if (want == null) return const Fetched(404, '{}');
        if (form['Code'] != want) return Fetched(200, jsonEncode({'status': 'pending'}));
        texted.remove(to);
        return Fetched(200, jsonEncode({'status': 'approved'}));
      }
      return const Fetched(404, '{}');
    }
    if (url.host == 'api.x.com' && url.path == '/2/users/me') {
      final who = codes[headers['Authorization']!.substring('Bearer tok-'.length)]!;
      return Fetched(200, jsonEncode({'data': {'id': who.$1, 'username': who.$2}}));
    }
    return const Fetched(404, '');
  }
}

void main() {
  late Net net;
  late Handles h;
  late Map<String, List<Map<String, Object?>>> heard;
  late Directory dir;
  const config = HandlesConfig(publicUrl: 'http://127.0.0.1', discordId: 'did', discordSecret: 'dsecret', xId: 'xid', telegramBot: 'ghost_bot', telegramToken: '123:abc');

  // The same function each time for one install, as a connection's is: leaving is by that function.
  final tells = <String, void Function(Map<String, Object?>)>{};
  void Function(Map<String, Object?>) tellOf(String id) => tells[id] ??= (m) => (heard[id] ??= []).add(m);
  void come(Handles to, String id) {
    heard[id] ??= [];
    to.came(id, tellOf(id));
  }

  void leave(Handles from, String id) => from.went(id, tellOf(id));
  Map<String, Object?>? last(String id, String dir) => heard[id]!.lastWhere((m) => m['dir'] == dir, orElse: () => const {}).isEmpty ? null : heard[id]!.lastWhere((m) => m['dir'] == dir);

  setUp(() {
    net = Net();
    heard = {};
    dir = Directory.systemTemp.createTempSync('handles');
    h = Handles(dataDir: dir, config: config, fetch: net.fetch)..load();
    for (final id in [alice, bob]) {
      come(h, id);
    }
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> prove(String id, String network, String handle) async {
    await h.said(id, {'dir': 'proof', 'p': network, 'handle': handle});
    final code = last(id, 'proof')!['code'] as String;
    net.bios['$network:${Handles.tidy(network, handle)}'] = 'I am on Ghost Messaging $code';
    await h.said(id, {'dir': 'check', 'p': network, 'handle': handle});
  }

  test('a handle is tidied and hashed the same however it is written', () {
    expect(Handles.keyOf('discord', '@Maya'), Handles.keyOf('discord', ' maya '));
    expect(Handles.keyOf('discord', 'maya'), isNot(Handles.keyOf('x', 'maya')));
    expect(Handles.keyOf('x', 'maya'), hexOf(sha256(utf8.encode('ghost-handle v1|x|maya'))));
    expect(Handles.wellFormed('mastodon', 'maya@mastodon.social'), isTrue);
    expect(Handles.wellFormed('mastodon', 'maya@localhost'), isFalse);
    expect(Handles.wellFormed('mastodon', 'maya@10.0.0.1'), isFalse);
    expect(Handles.wellFormed('mastodon', 'maya@evil.example/../x'), isFalse);
    expect(Handles.wellFormed('bluesky', 'maya.bsky.social'), isTrue);
    expect(Handles.wellFormed('github', 'maya/../x'), isFalse);
    expect(hexOf(hmacSha256(utf8.encode('key'), utf8.encode('The quick brown fox jumps over the lazy dog'))), 'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8');
  });

  test('hello says how each network is linked, and a network with no sign-in set up is off', () async {
    await h.said(alice, {'dir': 'hello'});
    final ways = last(alice, 'hello')!['ways'] as Map;
    expect(ways, {'discord': 'signin', 'telegram': 'signin', 'x': 'signin', 'bluesky': 'proof', 'mastodon': 'proof', 'github': 'proof', 'phone': 'off'});
    expect(Handles(fetch: net.fetch).ways['discord'], 'off');
    final bare = Handles(fetch: net.fetch)..load();
    come(bare, carol);
    await bare.said(carol, {'dir': 'link', 'p': 'discord'});
    expect(last(carol, 'err')!['err'], contains('not set up'));
  });

  test('a code in the profile proves the account; without it nothing is linked', () async {
    await h.said(alice, {'dir': 'proof', 'p': 'bluesky', 'handle': '@Maya.bsky.social'});
    final code = last(alice, 'proof')!['code'] as String;
    expect(code, startsWith('ghost-'));
    // Someone else's code for the same handle is another code.
    await h.said(bob, {'dir': 'proof', 'p': 'bluesky', 'handle': 'maya.bsky.social'});
    expect(last(bob, 'proof')!['code'], isNot(code));

    net.bios['bluesky:maya.bsky.social'] = 'just me';
    await h.said(alice, {'dir': 'check', 'p': 'bluesky', 'handle': 'maya.bsky.social'});
    expect(last(alice, 'err')!['err'], contains('not in that profile'));
    expect(h.linked, 0);

    // Bob's code in Maya's profile links it to Bob, not to Alice who asks.
    net.bios['bluesky:maya.bsky.social'] = 'hi ${last(bob, 'proof')!['code']}';
    await h.said(alice, {'dir': 'check', 'p': 'bluesky', 'handle': 'maya.bsky.social'});
    expect(h.linked, 0);

    net.bios['bluesky:maya.bsky.social'] = 'hi $code';
    await h.said(alice, {'dir': 'check', 'p': 'bluesky', 'handle': 'maya.bsky.social'});
    expect(last(alice, 'linked'), {'dir': 'linked', 'p': 'bluesky', 'handle': 'maya.bsky.social', 'k': Handles.keyOf('bluesky', 'maya.bsky.social')});
    expect(h.linked, 1);
  });

  test('someone watching is told when a listed handle joins, at once or when they next come; never an unlisted one', () async {
    final k = Handles.keyOf('github', 'maya');
    await h.said(bob, {'dir': 'watch', 'add': [k, Handles.keyOf('github', 'nobody')]});
    expect(last(bob, 'watching')!['n'], 2);
    expect(last(bob, 'joined'), isNull);

    // Linked but not listed: nobody hears.
    await prove(alice, 'github', 'Maya');
    expect(h.linked, 1);
    expect(last(bob, 'joined'), isNull);

    // Listed: Bob hears the hash, and only the hash.
    await h.said(alice, {'dir': 'listed', 'on': true});
    expect(last(bob, 'joined'), {'dir': 'joined', 'list': [k]});

    // Carol starts watching afterwards: told it is already here.
    come(h, carol);
    await h.said(carol, {'dir': 'watch', 'add': [k]});
    expect(last(carol, 'joined'), {'dir': 'joined', 'list': [k], 'already': true});

    // Someone away is told when they next say hello.
    leave(h, bob);
    heard[bob]!.clear();
    final mk = Handles.keyOf('mastodon', 'maya@mastodon.social');
    await h.said(bob, {'dir': 'watch', 'add': [mk]}); // not connected: not heard
    come(h, bob);
    await h.said(bob, {'dir': 'watch', 'add': [mk]});
    leave(h, bob);
    await prove(alice, 'mastodon', 'maya@mastodon.social');
    expect(net.asked.last, contains('(outside)'));
    come(h, bob);
    heard[bob]!.clear();
    await h.said(bob, {'dir': 'hello'});
    expect(last(bob, 'joined'), {'dir': 'joined', 'list': [mk]});
    heard[bob]!.clear();
    await h.said(bob, {'dir': 'hello'});
    expect(last(bob, 'joined'), isNull, reason: 'told once');

    // Listing turned off: a new watcher hears nothing.
    await h.said(alice, {'dir': 'listed', 'on': false});
    heard[carol]!.clear();
    await h.said(carol, {'dir': 'watch', 'add': [mk]});
    expect(last(carol, 'joined'), isNull);
    // Nobody is told of their own handle.
    await h.said(alice, {'dir': 'watch', 'add': [k]});
    await h.said(alice, {'dir': 'listed', 'on': true});
    expect(last(alice, 'joined'), isNull);
  });

  test('what is kept names no handle, and comes back after a restart', () async {
    await prove(alice, 'github', 'maya');
    await h.said(alice, {'dir': 'listed', 'on': true});
    await h.said(bob, {'dir': 'watch', 'add': [Handles.keyOf('x', 'someone')]});
    h.save();
    final kept = File('${dir.path}/handles.json').readAsStringSync();
    expect(kept, isNot(contains('maya')));
    expect(kept, isNot(contains('someone')));
    expect(kept, isNot(contains('4242')), reason: 'the account number is kept hashed');
    expect(kept, contains(Handles.keyOf('github', 'maya')));

    final again = Handles(dataDir: dir, config: config, fetch: net.fetch)..load();
    expect(again.linked, 1);
    expect(again.listed, 1);
    expect(again.watched, 1);
    // The same secret, so a code given before the restart still proves.
    expect(again.codeFor(alice, 'github', 'maya'), h.codeFor(alice, 'github', 'maya'));
    come(again, alice);
    await again.said(alice, {'dir': 'hello'});
    expect((last(alice, 'hello')!['links'] as List).single, containsPair('p', 'github'));
    expect(last(alice, 'hello')!['listed'], isTrue);

    // Forget: nothing of Alice is left.
    await again.said(alice, {'dir': 'forget'});
    again.save();
    expect(File('${dir.path}/handles.json').readAsStringSync(), isNot(contains(alice)));
  });

  test('an account linked from a second install leaves the first', () async {
    await prove(alice, 'github', 'maya');
    // The same account (GitHub's number for it), now proved by Bob's install: a new phone.
    await prove(bob, 'github', 'maya');
    expect(h.linked, 1);
    await h.said(alice, {'dir': 'hello'});
    expect(last(alice, 'hello')!['links'], isEmpty);
    await h.said(bob, {'dir': 'unlink', 'p': 'github'});
    expect(h.linked, 0);
  });

  test('who you follow is read only for the account you proved, and comes back tidy', () async {
    net.follows['bluesky:maya.bsky.social'] = [for (var i = 0; i < 250; i++) 'Friend$i.bsky.social'];
    await h.said(alice, {'dir': 'follows', 'p': 'bluesky', 'handle': 'maya.bsky.social'});
    expect(last(alice, 'err')!['err'], contains('Link that account first'));
    await prove(alice, 'bluesky', 'maya.bsky.social');
    await h.said(alice, {'dir': 'follows', 'p': 'bluesky', 'handle': 'maya.bsky.social'});
    final got = last(alice, 'follows')!['handles'] as List;
    expect(got.length, 250);
    expect(got.first, 'friend0.bsky.social');

    await prove(alice, 'mastodon', 'maya@mastodon.social');
    await h.said(alice, {'dir': 'follows', 'p': 'mastodon', 'handle': 'maya@mastodon.social'});
    expect(last(alice, 'follows')!['handles'], ['local@mastodon.social', 'far@other.example']);
    await h.said(alice, {'dir': 'follows', 'p': 'discord', 'handle': 'maya'});
    expect(last(alice, 'err')!['err'], contains('cannot be read'));
  });

  test('an install may make this server fetch only so often', () async {
    net.bios['github:maya'] = 'nothing';
    for (var i = 0; i < Handles.fetchesAnHour; i++) {
      await h.said(alice, {'dir': 'check', 'p': 'github', 'handle': 'maya'});
    }
    final before = net.asked.length;
    await h.said(alice, {'dir': 'check', 'p': 'github', 'handle': 'maya'});
    expect(last(alice, 'err')!['err'], contains('Too many'));
    expect(net.asked.length, before);
  });

  group('a phone number, by a code texted to it', () {
    const texting = HandlesConfig(publicUrl: 'http://127.0.0.1', twilioSid: 'ACsid', twilioToken: 'secret', twilioVerify: 'VAservice');
    const hers = '+15550100199';
    late DateTime clock;
    late Handles t;

    Handles make([HandlesConfig config = texting]) {
      final made = Handles(dataDir: dir, config: config, fetch: net.fetch, now: () => clock)..load();
      for (final id in [alice, bob, carol]) {
        come(made, id);
      }
      return made;
    }

    Future<void> text(String id, String number) => t.said(id, {'dir': 'text', 'p': 'phone', 'handle': number});
    Future<void> code(String id, String number, String code) => t.said(id, {'dir': 'code', 'p': 'phone', 'handle': number, 'code': code});
    int checks() => net.asked.where((a) => a.endsWith('/VerificationCheck')).length;

    setUp(() {
      clock = DateTime.utc(2026, 11, 14, 12);
      t = make();
    });

    test('a number is tidied the same however it is written, and only a whole one is taken', () {
      for (final written in ['(555) 010-0199', '555.010.0199', '1 555 010 0199', '+1 555 010 0199', ' +15550100199 ']) {
        expect(Handles.tidyNumber(written), hers, reason: written);
        expect(Handles.keyOf('phone', written), Handles.keyOf('phone', hers));
      }
      expect(Handles.tidyNumber('+44 20 7946 0958'), '+442079460958');
      expect(Handles.tidyNumber('call me'), '');
      expect(Handles.tidyNumber('555-0199 ext 2'), '');
      expect(Handles.wellFormed('phone', hers), isTrue);
      expect(Handles.wellFormed('phone', '+442079460958'), isTrue);
      for (final not in ['', '5550199', '+1555', '+10550100199', '+155501001990', '+0442079460958']) {
        expect(Handles.wellFormed('phone', Handles.tidyNumber(not)), isFalse, reason: not);
      }
    });

    test('with no text service set up a number is off, and nothing is sent', () async {
      expect(h.ways['phone'], 'off');
      expect(t.ways['phone'], 'text');
      await h.said(alice, {'dir': 'text', 'p': 'phone', 'handle': hers});
      expect(last(alice, 'err')!['err'], contains('not set up'));
      await h.said(alice, {'dir': 'code', 'p': 'phone', 'handle': hers, 'code': '482914'});
      expect(last(alice, 'err')!['err'], contains('not set up'));
      // Half set up is not set up.
      expect(Handles(config: const HandlesConfig(twilioSid: 'ACsid', twilioToken: 'secret'), fetch: net.fetch).ways['phone'], 'off');
      expect(net.texts, 0);
      expect(HandlesConfig.fromEnvironment({'GHOST_TWILIO_SID': 'ACsid', 'GHOST_TWILIO_TOKEN': 'secret', 'GHOST_TWILIO_VERIFY': 'VAservice', 'GHOST_TEXT_TO': '+1, +44,nonsense', 'GHOST_TEXTS_A_DAY': '50'}).textTo, ['+1', '+44']);
      expect(HandlesConfig.fromEnvironment(const {}).texts, isFalse);
      expect(HandlesConfig.fromEnvironment(const {}).textTo, ['+1']);
    });

    test('the code that reached the number links it; a wrong one, and someone else\'s try, do not', () async {
      await text(alice, '(555) 010-0199');
      expect(last(alice, 'text'), {'dir': 'text', 'p': 'phone', 'handle': hers});
      final sent = net.texted[hers]!;

      await code(alice, hers, '000000');
      expect(last(alice, 'err')!['err'], contains('not the code'));
      expect(t.linked, 0);

      // Bob knows her number, and guesses: his guess is not even passed on.
      final before = checks();
      await code(bob, hers, sent);
      expect(last(bob, 'err')!['err'], contains('Ask for a code first'));
      expect(checks(), before);
      expect(t.linked, 0);

      // Written as the text shows it, with a space.
      await code(alice, '555 010 0199', '${sent.substring(0, 3)} ${sent.substring(3)}');
      expect(last(alice, 'linked'), {'dir': 'linked', 'p': 'phone', 'handle': hers, 'k': Handles.keyOf('phone', hers)});
      expect(t.linked, 1);
      await t.said(alice, {'dir': 'hello'});
      expect((last(alice, 'hello')!['links'] as List).single, containsPair('p', 'phone'));

      // Good once: the same code again proves nothing.
      await code(alice, hers, sent);
      expect(last(alice, 'err')!['about'], 'code');

      // What is kept is the number's hash, never the number.
      t.save();
      final kept = File('${dir.path}/handles.json').readAsStringSync();
      expect(kept, isNot(contains('5550100199')));
      expect(kept, contains(Handles.keyOf('phone', hers)));

      // A code is not a profile's: the other ways of linking refuse a number.
      await t.said(alice, {'dir': 'proof', 'p': 'phone', 'handle': hers});
      expect(last(alice, 'err')!['err'], contains('code sent to it'));
      await t.said(alice, {'dir': 'follows', 'p': 'phone', 'handle': hers});
      expect(last(alice, 'err')!['err'], contains('cannot be read'));
      await t.said(alice, {'dir': 'text', 'p': 'github', 'handle': 'maya'});
      expect(last(alice, 'err')!['err'], contains('Only a phone number'));

      await t.said(alice, {'dir': 'unlink', 'p': 'phone'});
      expect(t.linked, 0);
    });

    test('a code runs out after ten minutes', () async {
      await text(alice, hers);
      final sent = net.texted[hers]!;
      clock = clock.add(const Duration(minutes: 11));
      final before = checks();
      await code(alice, hers, sent);
      expect(last(alice, 'err')!['err'], contains('Ask for a code first'));
      expect(checks(), before);
    });

    test('a number that moves to a new phone leaves the old one', () async {
      await text(alice, hers);
      await code(alice, hers, net.texted[hers]!);
      await text(bob, hers);
      await code(bob, hers, net.texted[hers]!);
      expect(t.linked, 1);
      await t.said(alice, {'dir': 'hello'});
      expect(last(alice, 'hello')!['links'], isEmpty);
      await t.said(bob, {'dir': 'hello'});
      expect((last(bob, 'hello')!['links'] as List).single, containsPair('k', Handles.keyOf('phone', hers)));
    });

    test('a linked number is told to nobody, listed or not', () async {
      final k = Handles.keyOf('phone', hers);
      // Bob watches for her number before she links it, Carol after.
      await t.said(bob, {'dir': 'watch', 'add': [k]});
      await t.said(alice, {'dir': 'listed', 'on': true});
      await text(alice, hers);
      await code(alice, hers, net.texted[hers]!);
      await t.said(carol, {'dir': 'watch', 'add': [k]});
      await t.said(alice, {'dir': 'listed', 'on': false});
      await t.said(alice, {'dir': 'listed', 'on': true});
      expect(last(bob, 'joined'), isNull);
      expect(last(carol, 'joined'), isNull);
      // And nothing waits for one who was away.
      leave(t, bob);
      await t.said(alice, {'dir': 'unlink', 'p': 'phone'});
      await text(alice, hers);
      await code(alice, hers, net.texted[hers]!);
      come(t, bob);
      await t.said(bob, {'dir': 'hello'});
      expect(last(bob, 'joined'), isNull);
    });

    test('only so many texts: for one install, to one number, and in all', () async {
      const other = '+15550100142';
      for (var i = 0; i < Handles.textsAnHour; i++) {
        await text(alice, hers);
      }
      expect(net.texts, 3);
      // Alice has had her three, to any number; and her number its three, whoever asks.
      await text(alice, other);
      expect(last(alice, 'err')!['err'], contains('asked for a few codes'));
      await text(bob, hers);
      expect(last(bob, 'err')!['err'], contains('That number has been sent'));
      expect(net.texts, 3);

      // An hour on, three more: six in a day, and then no more that day.
      clock = clock.add(const Duration(minutes: 61));
      for (var i = 0; i < Handles.textsAnHour; i++) {
        await text(alice, other);
      }
      expect(net.texts, 6);
      clock = clock.add(const Duration(minutes: 61));
      await text(alice, other);
      expect(last(alice, 'err')!['err'], contains('asked for a few codes'));
      expect(net.texts, 6);
      clock = clock.add(const Duration(hours: 23));
      await text(alice, other);
      expect(net.texts, 7);

      // In all: a server set to two a day sends two, to anyone.
      t = make(const HandlesConfig(twilioSid: 'ACsid', twilioToken: 'secret', twilioVerify: 'VAservice', textsADay: 2));
      await text(alice, '+15550100101');
      await text(bob, '+15550100102');
      await text(carol, '+15550100103');
      expect(last(carol, 'err')!['err'], contains('No more codes can be sent today'));
      expect(net.texts, 9);
    });

    test('only so many tries of a code', () async {
      await text(alice, hers);
      for (var i = 0; i < Handles.triesAnHour; i++) {
        await code(alice, hers, '111111');
      }
      final before = checks();
      await code(alice, hers, net.texted[hers]!);
      expect(last(alice, 'err')!['err'], contains('Too many tries'));
      expect(checks(), before);
      expect(t.linked, 0);
    });

    test('a number that may not be texted is refused before anything is sent; one the service refuses says so', () async {
      await text(alice, '+44 20 7946 0958');
      expect(last(alice, 'err')!['err'], contains('country'));
      await text(alice, 'my number');
      expect(last(alice, 'err')!['err'], contains('does not look like a phone number'));
      expect(net.asked, isEmpty);

      net.landlines.add(hers);
      await text(alice, hers);
      expect(last(alice, 'err')!['err'], contains('cannot be sent a text'));
      net.landlines.clear();
      net.textsDown = true;
      await text(alice, hers);
      expect(last(alice, 'err')!['err'], contains('could not be sent just now'));
      net.textsDown = false;
      await text(alice, hers);
      expect(last(alice, 'text')!['handle'], hers);
      net.textsDown = true;
      await code(alice, hers, net.texted[hers]!);
      expect(last(alice, 'err')!['err'], contains('could not be checked'));
      expect(t.linked, 0);

      // A wrong password for the service is the service being down, to the person.
      t = make(const HandlesConfig(twilioSid: 'ACsid', twilioToken: 'wrong', twilioVerify: 'VAservice'));
      net.textsDown = false;
      await text(bob, '+15550100142');
      expect(last(bob, 'err')!['err'], contains('could not be sent just now'));
    });
  });

  group('signing in, through the relay\'s own pages', () {
    late Relay relay;
    late int port;
    late HttpClient client;

    Future<({int status, String body, String? location})> get(String path) async {
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
      request.followRedirects = false;
      final response = await request.close();
      return (status: response.statusCode, body: await utf8.decodeStream(response), location: response.headers.value('location'));
    }

    setUp(() async {
      relay = Relay(hub: Hub(handles: h));
      port = await relay.start(port: 0);
      client = HttpClient();
    });
    tearDown(() async {
      client.close(force: true);
      await relay.stop();
    });

    Future<String> state(String id, String network) async {
      await h.said(id, {'dir': 'link', 'p': network});
      final url = Uri.parse(last(id, 'link')!['url'] as String);
      expect(url.path, '/link/$network');
      return url.queryParameters['s']!;
    }

    test('Discord: the app is sent to Discord, and what Discord says on the way back is who signed in', () async {
      final s = await state(alice, 'discord');
      final start = await get('/link/discord?s=$s');
      expect(start.status, 302);
      final to = Uri.parse(start.location!);
      expect(to.host, 'discord.com');
      expect(to.queryParameters['scope'], 'identify');
      expect(to.queryParameters['state'], s);
      expect(to.queryParameters['redirect_uri'], 'http://127.0.0.1/link/discord/callback');

      net.codes['good'] = ('9001', 'Maya');
      final bad = await get('/link/discord/callback?code=wrong&state=$s');
      expect(bad.status, 400);
      expect(h.linked, 0);
      // A state is good once: the failed try used it up.
      final spent = await get('/link/discord/callback?code=good&state=$s');
      expect(spent.status, 400);

      final s2 = await state(alice, 'discord');
      final done = await get('/link/discord/callback?code=good&state=$s2');
      expect(done.status, 200);
      expect(done.body, contains('@maya on Discord is linked'));
      expect(last(alice, 'linked'), {'dir': 'linked', 'p': 'discord', 'handle': 'maya', 'k': Handles.keyOf('discord', 'maya')});
    });

    test('X: with a challenge whose answer only this server has', () async {
      final s = await state(bob, 'x');
      final to = Uri.parse((await get('/link/x?s=$s')).location!);
      expect(to.host, 'x.com');
      expect(to.queryParameters['code_challenge_method'], 'S256');
      expect(to.queryParameters['code_challenge']!.length, 43);
      net.codes['xcode'] = ('55', 'Bob_X');
      final done = await get('/link/x/callback?code=xcode&state=$s');
      expect(done.status, 200);
      expect(last(bob, 'linked')!['handle'], 'bob_x');
    });

    test('Telegram: only what its bot signed is believed, and not for long', () async {
      final s = await state(alice, 'telegram');
      final page = await get('/link/telegram?s=$s');
      expect(page.status, 200);
      expect(page.body, contains('data-telegram-login="ghost_bot"'));

      final when = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      String signed(Map<String, String> fields) {
        final lines = [for (final k in fields.keys.toList()..sort()) '$k=${fields[k]}'].join('\n');
        return hexOf(hmacSha256(sha256(utf8.encode('123:abc')), utf8.encode(lines)));
      }

      final fields = {'id': '777', 'first_name': 'Maya', 'username': 'MayaTG', 'auth_date': '$when'};
      String query(Map<String, String> f, String hash, String st) => Uri(queryParameters: {...f, 'hash': hash, 'state': st}).query;

      // Another username under the same signature: refused.
      final forged = await get('/link/telegram/callback?${query({...fields, 'username': 'someoneelse'}, signed(fields), s)}');
      expect(forged.status, 400);
      expect(h.linked, 0);

      final s2 = await state(alice, 'telegram');
      final old = {...fields, 'auth_date': '${when - 90000}'};
      expect((await get('/link/telegram/callback?${query(old, signed(old), s2)}')).status, 400);

      final s3 = await state(alice, 'telegram');
      final done = await get('/link/telegram/callback?${query(fields, signed(fields), s3)}');
      expect(done.status, 200);
      expect(last(alice, 'linked')!['handle'], 'mayatg');

      // No username: said so, and nothing linked.
      final s4 = await state(bob, 'telegram');
      final bare = {'id': '778', 'first_name': 'Bob', 'auth_date': '$when'};
      final none = await get('/link/telegram/callback?${query(bare, signed(bare), s4)}');
      expect(none.status, 400);
      expect(none.body, contains('has no username'));
    });

    test('a sign-in that finishes while the app is away is told when it comes back', () async {
      final s = await state(alice, 'discord');
      leave(h, alice);
      heard[alice]!.clear();
      net.codes['good'] = ('9001', 'maya');
      expect((await get('/link/discord/callback?code=good&state=$s')).status, 200);
      come(h, alice);
      await h.said(alice, {'dir': 'hello'});
      expect(last(alice, 'linked')!['handle'], 'maya');
    });

    test('an address that is not a sign-in is the relay\'s own answer', () async {
      expect((await get('/link/discord?s=nothing')).status, 400);
      expect((await get('/link/github?s=x')).body, contains('Ghost Messaging relay'));
      expect((await get('/')).body, contains('Ghost Messaging relay'));
    });
  });
}

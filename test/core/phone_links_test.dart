import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/phone_links.dart';
import 'package:ghost_md/share/app_links.dart';

/// The phone's links (lib/core/phone_links.dart) under `followAppLinks`, with the activity stood in for as
/// AppLinks.kt answers: the cases of `src/app/share/appLinks.test.ts` that are about the roads a link arrives by,
/// on the one road this app has.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();

  /// What the activity is keeping.
  late List<String> kept;
  late int asked;

  void activity() => messenger.setMockMethodCallHandler(phoneLinksChannel, (call) async {
        if (call.method != 'take') throw MissingPluginException();
        asked += 1;
        final handed = List<String>.of(kept);
        kept.clear();
        return handed;
      });

  /// The activity keeping `link` while the app runs, and saying so.
  Future<void> arrives(String link) async {
    kept.add(link);
    await messenger.handlePlatformMessage(phoneLinksChannel.name, codec.encodeMethodCall(const MethodCall('arrived')), (_) {});
    await pumpEventQueue();
  }

  setUp(() {
    kept = [];
    asked = 0;
  });
  tearDown(() => messenger.setMockMethodCallHandler(phoneLinksChannel, null));

  test('takes the link that started the app once the notes are read, and hands it over once', () async {
    activity();
    kept.add('ghostmd://note/m1');
    final links = PhoneLinks();
    addTearDown(links.dispose);
    final opened = <String>[];
    final stop = followAppLinks(opened.add, links);
    await pumpEventQueue();
    expect(opened, ['ghostmd://note/m1']);
    expect(await links.take(), isEmpty, reason: 'taken once');
    stop();
  });

  test('takes again whenever another arrives while the app runs, every kind of link as it came', () async {
    activity();
    final links = PhoneLinks();
    addTearDown(links.dispose);
    final opened = <String>[];
    final stop = followAppLinks(opened.add, links);
    await pumpEventQueue();
    expect(opened, isEmpty);
    final share = 'ghostmd://fork#${'a' * 22}.${'b' * 43}';
    for (final link in [share, 'ghostmd://join/AbCdEfGhIjKlMnOpQrSt_-', 'ghostmd://notifications', 'ghostmd://org/o1']) {
      await arrives(link);
    }
    expect(opened, [share, 'ghostmd://join/AbCdEfGhIjKlMnOpQrSt_-', 'ghostmd://notifications', 'ghostmd://org/o1']);
    expect(asked, 5);
    expect(readAppLink(opened[0]), isA<ShareAppLink>());
    expect(readAppLink(opened[1]), isA<JoinAppLink>());
    expect(readAppLink(opened[2]), isA<PlaceAppLink>());
    stop();
  });

  test('a link that arrives after the stop is left with the activity for whoever follows next', () async {
    activity();
    final links = PhoneLinks();
    addTearDown(links.dispose);
    final opened = <String>[];
    followAppLinks(opened.add, links)();
    await arrives('ghostmd://note/late');
    expect(opened, isEmpty);
    expect(asked, 1, reason: 'the first take, and none after the stop');
    final later = <String>[];
    final stop = followAppLinks(later.add, links);
    await pumpEventQueue();
    expect(later, ['ghostmd://note/late']);
    stop();
  });

  test('one link kept twice is opened once, and nothing but the app’s own scheme comes through', () async {
    messenger.setMockMethodCallHandler(phoneLinksChannel, (call) async => ['ghostmd://note/m1', 'https://example.com/', 7, 'ghostmd://note/m1']);
    final links = PhoneLinks();
    addTearDown(links.dispose);
    expect(await links.take(), ['ghostmd://note/m1', 'ghostmd://note/m1']);
    final opened = <String>[];
    final stop = followAppLinks(opened.add, links);
    await pumpEventQueue();
    expect(opened, ['ghostmd://note/m1']);
    stop();
  });

  test('with no phone half there is nothing to take, and the activity has no second road', () async {
    final links = PhoneLinks();
    addTearDown(links.dispose);
    expect(await links.take(), isEmpty);
    expect(links.takeActivityLink(), isNull);
    final opened = <String>[];
    final stop = followAppLinks(opened.add, links);
    await pumpEventQueue();
    expect(opened, isEmpty);
    stop();
  });
}

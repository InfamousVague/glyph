// A note's Figma frames as Lovart's references (lib/plugins/lovart/figma_refs.dart; Matt, 2026-11-02: "feed figma
// designs into the lovart inspo generator or header generator"): the frames read from a note's words, each once, three
// at most; the switch, off until turned on and nothing asked of Figma while it is; the frames' pictures asked of Figma
// with the person's token, one Figma will not say left out; the prompt's line for a banner and a moodboard; and the
// cog's Inspiration images and Header image sending them, saying what Lovart left out. Figma and Lovart are the test's
// own: nothing is asked of the network.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/images.dart';
import 'package:ghost_md/plugins/figma/figma.dart';
import 'package:ghost_md/plugins/figma/manifest.dart' as figma;
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/lovart/figma_refs.dart';
import 'package:ghost_md/plugins/lovart/lovart.dart';
import 'package:ghost_md/plugins/lovart/manifest.dart' as lovart;
import 'package:ghost_md/plugins/registry.dart';

import '../github/support.dart';
import 'lovart_test.dart' show FakeClient;

const String fileKey = 'abcDEF1234567890ghijKL';
const String otherKey = 'zyxWVU0987654321tsrqPO';
const String frameUrl = 'https://www.figma.com/design/$fileKey/Mobile-app?node-id=12-34&t=xyz';
const String fileUrl = 'https://www.figma.com/file/$otherKey/Brand';
const String framePicture = 'https://figma-alpha-api.s3.us-west-2.amazonaws.com/images/frame.png';
const String fileThumb = 'https://s3-alpha.figma.com/thumbnails/brand.png';

/// Figma as the test has it: [fileKey] with one frame, [otherKey] a file with a thumbnail, any other file not there.
FetchResponse figmaAnswers(FetchRequest request) {
  final path = request.url.path;
  if (path == '/v1/files/$fileKey/nodes') {
    return FetchResponse.json(200, {
      'name': 'Mobile app',
      'thumbnailUrl': fileThumb,
      'nodes': {
        '12:34': {
          'document': {'id': '12:34', 'name': 'Login', 'type': 'FRAME', 'absoluteBoundingBox': {'x': 0, 'y': 0, 'width': 390, 'height': 844}},
        },
      },
    });
  }
  if (path == '/v1/images/$fileKey') return FetchResponse.json(200, {'err': null, 'images': {'12:34': framePicture}});
  if (path == '/v1/files/$otherKey') return FetchResponse.json(200, {'name': 'Brand', 'thumbnailUrl': fileThumb});
  return FetchResponse(404, headers: const {'content-type': 'application/json'}, bytes: Uint8List.fromList('{"status":404,"err":"Not found"}'.codeUnits));
}

void main() {
  test('reads the Figma files and frames a note links to, each once, in order, three at most, and nothing else', () {
    final body = [
      '# Onboarding',
      'The login screen: $frameUrl.',
      '[Brand file]($fileUrl) and again $frameUrl',
      'Not Figma: https://www.figma.org/design/$fileKey/x and https://example.com',
      'A community file: https://www.figma.com/community/file/1234567890123/kit',
    ].join('\n');
    expect([for (final link in figmaLinksIn(body)) (link.fileKey, link.nodeId)], [(fileKey, '12:34'), (otherKey, null)]);
    final many = [for (var i = 0; i < 5; i++) 'https://www.figma.com/design/${'a' * 10}$i${'b' * 9}/F$i'].join('\n');
    expect(figmaLinksIn(many), hasLength(figmaRefsMost));
    expect(figmaLinksIn('# No links\n\nJust words.'), isEmpty);
  });

  test('the prompt says what the attached frames are: a banner’s reference in the house’s style, a moodboard’s directions', () {
    expect(withFigmaRefs('Draw it.', 0, banner: true), 'Draw it.');
    final banner = withFigmaRefs('Draw it.', 1, banner: true);
    expect(banner, startsWith('Draw it.\n\nThe attached image is a design from this note’s Figma file.'));
    expect(banner, contains('drawn in the style asked for above, not as a copy'));
    final moodboard = withFigmaRefs('Make four.', 2, banner: false);
    expect(moodboard, contains('The 2 attached images are designs being worked on in Figma'));
    expect(moodboard, contains('directions that build on them'));
    expect(figmaRefsDroppedWords(['', 'Failed review.']), 'Lovart left out a Figma frame: Failed review.');
    expect(figmaRefsDroppedWords(['']), 'Lovart left out a Figma frame and made the image without it.');
  });

  group('with Figma connected', () {
    late TestGround ground;
    late Registry registry;
    late FakeClient fake;
    late MemoryPictureStore pictures;

    setUp(() async {
      ground = useGround((request) async => figmaAnswers(request));
      registry = createRegistry([lovartPlugin, figmaPlugin], store: MemorySwitches());
      registry.setEnabled('lovart', true);
      registry.setEnabled('figma', true);
      usePlugins(registry);
      await figma.host.secrets.write(figma.tokenSecret, 'figd_test');
      await lovart.host.secrets.write(lovart.accessKeySecret, 'ak-1');
      await lovart.host.secrets.write(lovart.secretKeySecret, 'sk-1');
      fake = FakeClient(count: 4);
      lovartClient = () => fake;
      pictures = MemoryPictureStore();
      lovartPictureStore = pictures;
    });

    tearDown(() {
      lovartPictureStore = null;
      lovartClient = () => LovartClient.kept();
      usePluginGround(PluginGround());
      usePlugins(createRegistry(const []));
    });

    test('ships off, and while it is off nothing is asked of Figma and no reference goes', () async {
      expect(figmaRefsOn(), isFalse);
      expect(await figmaRefsFor('# Login\n\n$frameUrl'), isEmpty);
      expect(ground.asked, isEmpty);
      final note = TestNote('# Login\n\n$frameUrl');
      await makeInspiration(note);
      expect(fake.referenced.single, isEmpty);
      expect(fake.asked.single, isNot(contains('Figma')));
    });

    test('on, a frame’s render and a file’s thumbnail are asked of Figma with the token; one Figma will not say is left out', () async {
      setFigmaRefs(true);
      const missing = 'https://www.figma.com/design/qqqQQQ1234567890qqqQQQ/Gone?node-id=1-2';
      expect(await figmaRefsFor('$frameUrl\n$missing\n$fileUrl'), [framePicture, fileThumb]);
      expect({for (final asked in ground.asked) asked.url.host}, {'api.figma.com'});
      expect({for (final asked in ground.asked) asked.headers['X-Figma-Token']}, {'figd_test'});
    });

    test('on, but the Figma plugin off or its token gone, nothing goes', () async {
      setFigmaRefs(true);
      registry.setEnabled('figma', false);
      expect(await figmaRefsFor(frameUrl), isEmpty);
      registry.setEnabled('figma', true);
      await figma.host.secrets.write(figma.tokenSecret, null);
      expect(await figmaRefsFor(frameUrl), isEmpty);
      expect(ground.asked, isEmpty);
    });

    test('Inspiration images sends the note’s frames with a line saying what they are, and says what Lovart left out', () async {
      setFigmaRefs(true);
      fake.drops = ['1 reference asset(s) failed content moderation.'];
      final note = TestNote('# Login redesign\n\nWarmer.\n\n$frameUrl');
      await makeInspiration(note);
      expect(fake.referenced.single, [framePicture]);
      expect(fake.asked.single, contains('The attached image is a design being worked on in Figma'));
      expect(note.said, contains('Added 4 inspiration images.'));
      expect(note.said.last, 'Lovart left out a Figma frame: 1 reference asset(s) failed content moderation.');
    });

    test('Header image sends them too, for the banner’s subject in the house’s style', () async {
      setFigmaRefs(true);
      fake.count = 1;
      final note = TestNote('# Login redesign\n\nThe new sign-in screen for the app, warmer and simpler.\n\n$frameUrl\n\nMore words about it here.');
      await makeBanner(note);
      expect(fake.referenced.single, [framePicture]);
      expect(fake.asked.single, contains('The attached image is a design from this note’s Figma file.'));
      expect(note.body(), contains('banner:'));
    });
  });
}

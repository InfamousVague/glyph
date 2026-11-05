// Pictures given to the assistant in its chat (lib/claude/chat_images.dart; docs/CLAUDE_APP.md, "Pictures"; Matt,
// 2026-11-05: "Add the ability to upload images to Claude in app (or whatever AI were using) so that it can inject
// contents of images broken apart into notes such as a list of appointments"). A picture made ready (its kind, its
// size brought down), sent in each provider's own shape over a fake HttpClient, attached, removed and held to its
// limit in the chat, refused where the model cannot see it, and an appointments picture ending in a note of them.
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/device_keys.dart' show MemorySecureStore;
import 'package:ghost_md/assistant/assistant.dart';
import 'package:ghost_md/assistant/provider.dart';
import 'package:ghost_md/assistant/provider_settings.dart';
import 'package:ghost_md/claude/chat_images.dart';
import 'package:ghost_md/claude/claude_chat.dart';
import 'package:ghost_md/claude/claude_run.dart';
import 'package:ghost_md/claude/claude_runner.dart';
import 'package:ghost_md/claude/claude_settings.dart' show ClaudeSettings;
import 'package:ghost_md/claude/claude_tools.dart';
import 'package:ghost_md/claude/messages_api.dart';
import 'package:ghost_md/claude/sse.dart';
import 'package:ghost_md/core/metrics.dart';
import 'package:ghost_md/plugins/gemini/gemini_api.dart';
import 'package:ghost_md/plugins/openai/chat_api.dart';

import '../assistant/fake_http.dart';
import '../assistant/support.dart';
import '../support/render.dart';

/// A PNG of [width] by [height], one colour.
Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), ui.Paint()..color = const ui.Color(0xff3366cc));
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// A picture as the chat sends it, small: nothing to draw again.
Future<ChatImage> _picture() async => readyChatImage(await _png(12, 8));

SseEvent _e(String name, Map<String, Object?> data) => SseEvent(name, jsonEncode(data));

/// One reply: [words], then a tool called with [input] whole, or no tool.
List<SseEvent> _turn({String words = '', String? tool, String id = 'toolu_1', Map<String, Object?>? input}) => [
      _e('message_start', {'type': 'message_start'}),
      if (words.isNotEmpty) ...[
        _e('content_block_start', {
          'index': 0,
          'content_block': {'type': 'text', 'text': ''},
        }),
        _e('content_block_delta', {
          'index': 0,
          'delta': {'type': 'text_delta', 'text': words},
        }),
        _e('content_block_stop', {'index': 0}),
      ],
      if (tool != null) ...[
        _e('content_block_start', {
          'index': 1,
          'content_block': {'type': 'tool_use', 'id': id, 'name': tool, 'input': <String, Object?>{}},
        }),
        _e('content_block_delta', {
          'index': 1,
          'delta': {'type': 'input_json_delta', 'partial_json': jsonEncode(input ?? const {})},
        }),
        _e('content_block_stop', {'index': 1}),
      ],
      _e('message_delta', {
        'delta': {'stop_reason': tool == null ? 'end_turn' : 'tool_use'},
      }),
      _e('message_stop', {'type': 'message_stop'}),
    ];

class _Api extends ClaudeApi {
  _Api(this.turns) : super(key: 'sk-ant-test');

  final List<List<SseEvent>> turns;
  final List<Map<String, Object?>> asked = [];

  @override
  ClaudeCall stream(Map<String, Object?> body) {
    asked.add(jsonDecode(jsonEncode(body)) as Map<String, Object?>);
    return ClaudeCall(Stream<SseEvent>.fromIterable(asked.length <= turns.length ? turns[asked.length - 1] : _turn(words: 'Done.')), () {});
  }
}

Future<void> _until(ClaudeRunner runner) async {
  while (runner.working || runner.run == null || runner.run!.state == ClaudeState.idle) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('a picture made ready', () {
    testWidgets('is read for its kind, sent as it is while small, and drawn down to its long side when large', (tester) async {
      await tester.runAsync(() async {
        final small = await _png(40, 30);
        expect(chatImageType(small), 'image/png');
        final kept = await readyChatImage(small);
        expect(identical(kept.bytes, small), isTrue);
        expect((kept.mediaType, kept.width, kept.height), ('image/png', 40, 30));

        // No JPEG writer here (a Mac, a test): drawn again as a PNG, its long side the limit.
        final large = await _png(2400, 1200);
        final drawn = await readyChatImage(large);
        expect((drawn.mediaType, drawn.width, drawn.height), ('image/png', chatImageLongSide, 784));
        final codec = await ui.instantiateImageCodec(drawn.bytes);
        final frame = await codec.getNextFrame();
        expect((frame.image.width, frame.image.height), (chatImageLongSide, 784));

        // The device's writer, where it has one (Android): asked for the long side and the quality.
        final asked = <(int, int)>[];
        final jpeg = await readyChatImage(large, jpeg: (bytes, {required longSide, required quality}) async {
          asked.add((longSide, quality));
          return Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
        });
        expect(asked, [(chatImageLongSide, chatImageQuality)]);
        expect((jpeg.mediaType, jpeg.width, jpeg.height, jpeg.extension), ('image/jpeg', chatImageLongSide, 784, 'jpg'));

        // A little over the limit, as the device's chooser keeps them (1600), is let be.
        final chooser = await _png(1600, 900);
        expect(identical((await readyChatImage(chooser)).bytes, chooser), isTrue);
      });
    });

    testWidgets('is refused in words when it is not a picture, will not open, or is too heavy', (tester) async {
      await tester.runAsync(() async {
        await expectLater(readyChatImage(Uint8List.fromList(utf8.encode('%PDF-1.7 not a picture'))), throwsA(isA<ChatImageProblem>().having((p) => p.message, 'message', contains('JPEG, PNG, WebP or GIF'))));
        await expectLater(readyChatImage(Uint8List.fromList([0xff, 0xd8, 0xff, 0, 0, 0])), throwsA(isA<ChatImageProblem>().having((p) => p.message, 'message', 'That picture couldn’t be opened.')));
        await expectLater(readyChatImage(await _png(30, 30), maxBytes: 10), throwsA(isA<ChatImageProblem>().having((p) => p.message, 'message', contains('too large'))));
        expect(chatImageType(Uint8List.fromList([...utf8.encode('RIFF'), 0, 0, 0, 0, ...utf8.encode('WEBPVP8 ')])), 'image/webp');
        expect(chatImageType(Uint8List.fromList(utf8.encode('GIF89a'))), 'image/gif');
      });
    });
  });

  group('who can see a picture', () {
    test('Claude’s models, OpenAI’s and Gemini’s by name, an endpoint’s only where its name says so', () {
      for (final model in ['claude-sonnet-5-5', 'claude-opus-5-5', 'claude-haiku-5-5', 'claude-3-haiku-20240307']) {
        expect(aiSeesImages('claude', model), isTrue, reason: model);
      }
      expect(aiSeesImages('claude', 'claude-2.1'), isFalse);
      for (final model in ['gpt-4o', 'gpt-4o-mini', 'gpt-4.1', 'gpt-5', 'gpt-5-mini', 'o3', 'o4-mini', 'o1']) {
        expect(aiSeesImages('openai', model), isTrue, reason: model);
      }
      for (final model in ['gpt-3.5-turbo', 'gpt-4', 'o3-mini', 'o1-mini', 'gpt-4o-audio-preview', 'gpt-4o-realtime-preview', 'text-embedding-3-small']) {
        expect(aiSeesImages('openai', model), isFalse, reason: model);
      }
      for (final model in ['gemini-2.5-pro', 'gemini-2.5-flash', 'models/gemini-3-pro', 'gemma-3-27b-it']) {
        expect(aiSeesImages('gemini', model), isTrue, reason: model);
      }
      for (final model in ['gemini-pro', 'gemini-1.0-pro', 'text-embedding-004', 'gemini-embedding-001']) {
        expect(aiSeesImages('gemini', model), isFalse, reason: model);
      }
      for (final model in ['llava:13b', 'qwen2.5-vl-72b-instruct', 'openai/gpt-4o', 'anthropic/claude-sonnet-4', 'meta-llama/llama-3.2-11b-vision-instruct', 'pixtral-12b']) {
        expect(aiSeesImages('custom-ai', model), isTrue, reason: model);
      }
      for (final model in ['llama3.1:8b', 'deepseek-chat', 'mistral-7b-instruct', 'kimi-k2', '']) {
        expect(aiSeesImages('custom-ai', model), isFalse, reason: model);
        expect(aiSeesImages('aster', model), isFalse, reason: model);
      }
      expect(aiSeesImages('local', 'gemma-3n'), isFalse);
    });
  });

  group('each provider’s own shape', () {
    testWidgets('Claude: a base64 image block before the words', (tester) async {
      final picture = await tester.runAsync(_picture);
      final http = FakeHttp((_) => FakeAnswer.sse([
            'event: message_start\ndata: {"type":"message_start"}\n\n',
            'event: message_delta\ndata: {"delta":{"stop_reason":"end_turn"}}\n\n',
            'event: message_stop\ndata: {"type":"message_stop"}\n\n',
          ]));
      final notes = MemoryNotes();
      await tester.runAsync(ClaudeRun(api: ClaudeApi(key: 'sk-ant-test', client: http.call), model: 'claude-sonnet-5-5', notes: notes, desk: BlindDesk(notes), prompt: 'Add these appointments', images: [picture!]).run);
      final content = ((http.requests.single.json['messages'] as List).single as Map)['content'] as List;
      expect(content, [
        {
          'type': 'image',
          'source': {'type': 'base64', 'media_type': 'image/png', 'data': base64Encode(picture.bytes)},
        },
        {'type': 'text', 'text': 'Add these appointments'},
      ]);
    });

    testWidgets('OpenAI: the turn as parts, the picture an image_url with a data URL; words alone stay a string', (tester) async {
      final picture = await tester.runAsync(_picture);
      final http = FakeHttp((_) => FakeAnswer.sse(['data: [DONE]\n\n']));
      final notes = MemoryNotes();
      await tester.runAsync(ClaudeRun(api: OpenAiChatApi(key: 'sk-test-0123456789abcdef', client: http.call), model: 'gpt-4o', notes: notes, desk: BlindDesk(notes), prompt: 'Make a to-do list', images: [picture!]).run);
      final messages = http.requests.single.json['messages'] as List;
      expect(messages.last, {
        'role': 'user',
        'content': [
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,${base64Encode(picture.bytes)}'},
          },
          {'type': 'text', 'text': 'Make a to-do list'},
        ],
      });
      expect(
        openAiMessages({
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'hi'},
              ],
            },
          ],
        }),
        [
          {'role': 'user', 'content': 'hi'},
        ],
      );
    });

    testWidgets('Gemini: an inlineData part with its type and bytes, before the words', (tester) async {
      final picture = await tester.runAsync(_picture);
      final http = FakeHttp((_) => FakeAnswer.sse(const []));
      final notes = MemoryNotes();
      await tester.runAsync(ClaudeRun(api: GeminiApi(key: 'AIzaTest-0123456789abcdefghijklmnop', client: http.call), model: 'gemini-2.5-flash', notes: notes, desk: BlindDesk(notes), prompt: 'Summarise', images: [picture!]).run);
      final contents = http.requests.single.json['contents'] as List;
      expect(contents.single, {
        'role': 'user',
        'parts': [
          {
            'inlineData': {'mimeType': 'image/png', 'data': base64Encode(picture.bytes)},
          },
          {'text': 'Summarise'},
        ],
      });
    });
  });

  group('a picture of appointments', () {
    // The fake model reads the picture as a model would and answers with the note tool; the run ends in a note with
    // each appointment a to-do of its own, its day where the app's calendar reads it.
    testWidgets('ends in a note with each appointment, the picture sent and the system told how to write them', (tester) async {
      final notes = MemoryNotes();
      final settings = ClaudeSettings(MemorySecureStore());
      await tester.runAsync(() => settings.setKey('sk-ant-test-0000000000'));
      const body = '# Appointments\n\n'
          '- [ ] Dentist, Dr Lee, 09:30, 12 High St 📅 2026-11-12\n'
          '- [ ] Physio, 14:00, Riverside Clinic 📅 2026-11-14\n'
          '- [ ] Eye test, 11:15, Boots, Market Square 📅 2026-11-20\n';
      final api = _Api([
        _turn(words: 'Three appointments.', tool: ClaudeTool.create, input: {'body': body}),
        _turn(words: 'Made [[Appointments]] with three appointments.'),
      ]);
      final runner = ClaudeRunner(settings: settings, notes: notes, desk: BlindDesk(notes), api: (_) => api);
      addTearDown(runner.dispose);
      expect(runner.seesImages, isTrue);
      final picture = (await tester.runAsync(_picture))!;
      await tester.runAsync(() async {
        await runner.ask('Add these appointments', images: [picture]);
        await _until(runner);
      });
      final run = runner.run!;
      expect(run.state, ClaudeState.done);
      expect(notes.bodies.values.single, body);
      expect(run.touched.values, ['Appointments']);
      expect(run.steps.first.pictures, [picture]);
      final first = api.asked.first;
      expect(((first['messages'] as List).first as Map)['content'], hasLength(2));
      expect(first['system'] as String, contains('`📅 2026-11-12`'));
      // Not let put pictures into notes, it is not offered the tool.
      expect([for (final tool in first['tools'] as List) (tool as Map)['name']], isNot(contains(ClaudePictureTool.add)));
      // The follow-up carries the picture still.
      final second = api.asked[1]['messages'] as List;
      expect(((second.first as Map)['content'] as List).first, containsPair('type', 'image'));
      expect(runner.picturesLeft, chatConversationImageLimit - 1);
      runner.newChat();
      expect(runner.picturesLeft, chatConversationImageLimit);
    });

    testWidgets('where let, puts the picture itself into the note through the library’s pictures', (tester) async {
      final notes = MemoryNotes()..bodies['w'] = '# Whiteboard\n\nIdeas.\n';
      final settings = ClaudeSettings(MemorySecureStore());
      await tester.runAsync(() => settings.setKey('sk-ant-test-0000000000'));
      final kept = <String, Uint8List>{};
      final api = _Api([
        _turn(tool: ClaudePictureTool.add, input: {'id': 'w', 'picture': 1, 'caption': 'The board'}),
        _turn(words: 'Put it in [[Whiteboard]].'),
      ]);
      final runner = ClaudeRunner(
        settings: settings,
        notes: notes,
        desk: BlindDesk(notes),
        api: (_) => api,
        keepPicture: (bytes, extension) async {
          kept['img-1.$extension'] = bytes;
          return 'img-1.$extension';
        },
      );
      addTearDown(runner.dispose);
      final picture = (await tester.runAsync(_picture))!;
      await tester.runAsync(() async {
        await runner.ask('Keep this with the note', images: [picture], keepPictures: true);
        await _until(runner);
      });
      expect([for (final tool in api.asked.first['tools'] as List) (tool as Map)['name']], contains(ClaudePictureTool.add));
      expect(kept.keys, ['img-1.png']);
      expect(notes.bodies['w'], '# Whiteboard\n\nIdeas.\n\n![The board](image/img-1.png)\n');
      expect(runner.run!.touched, {'w': 'Whiteboard'});
    });

    testWidgets('is refused where the model cannot see it, and nothing is sent', (tester) async {
      final notes = MemoryNotes();
      final store = MemorySecureStore();
      final openAi = AiProviderSettings(store, prefix: 'openai', name: 'OpenAI');
      await tester.runAsync(() async {
        await openAi.setKey('sk-test-0123456789abcdef');
        await openAi.setModel('gpt-3.5-turbo');
      });
      final http = FakeHttp((_) => FakeAnswer.sse(['data: [DONE]\n\n']));
      final route = AiRoute(AiPlugged(id: 'openai', name: 'OpenAI', settings: openAi, switchedOn: () => true, client: (s) => OpenAiChatApi(key: s.key, client: http.call)));
      final runner = ClaudeRunner(settings: ClaudeSettings(MemorySecureStore()), notes: notes, desk: BlindDesk(notes), route: () => route);
      addTearDown(runner.dispose);
      expect(runner.seesImages, isFalse);
      final picture = (await tester.runAsync(_picture))!;
      final failed = await tester.runAsync(() => runner.ask('x', images: [picture]).then<Object?>((_) => null, onError: (Object e) => e));
      expect(failed, isA<ClaudeError>().having((e) => e.message, 'message', 'OpenAI can’t see pictures with gpt-3.5-turbo. $chatImageHint'));
      expect(http.requests, isEmpty);
    });
  });

  group('the chat', () {
    Future<(ClaudeRunner, _Api)> runnerFor(WidgetTester tester, {String model = 'claude-sonnet-5-5', List<List<SseEvent>> turns = const []}) async {
      final settings = ClaudeSettings(MemorySecureStore());
      await tester.runAsync(() async {
        await settings.setKey('sk-ant-test-0000000000');
        await settings.setModel(model);
      });
      final notes = MemoryNotes();
      final api = _Api(turns);
      final runner = ClaudeRunner(settings: settings, notes: notes, desk: BlindDesk(notes), api: (_) => api);
      addTearDown(runner.dispose);
      return (runner, api);
    }

    /// A press that starts work in the engine (a picture decoded), let finish.
    Future<void> press(WidgetTester tester, Finder target) async {
      await tester.tap(target);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }

    testWidgets('attaches pictures from the chooser as thumbnails, each removed by its ×, five at most', (tester) async {
      final (runner, _) = await runnerFor(tester);
      final png = (await tester.runAsync(() => _png(16, 16)))!;
      var picked = 0;
      await pumpApp(tester, home: ClaudeChat(runner: runner, onClose: () {}, onOpenNote: (_) {}, onSettings: () {}, pictures: ChatPictureSource(pick: () async => (++picked, png).$2)));
      await tester.pump();
      expect(find.byKey(const ValueKey('claude-attach')), findsOneWidget);
      expect(find.byKey(const ValueKey('claude-pictures')), findsNothing);

      await press(tester, find.byKey(const ValueKey('claude-attach')));
      expect(find.byKey(const ValueKey('claude-picture:0')), findsOneWidget);
      // With a picture and nothing written, the chips.
      for (final chip in chatImageChips) {
        expect(find.byKey(ValueKey('claude-chip:$chip')), findsOneWidget);
      }
      await press(tester, find.byKey(const ValueKey('claude-attach')));
      expect(find.byKey(const ValueKey('claude-picture:1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('claude-picture-remove:0')));
      await tester.pump();
      expect(find.byKey(const ValueKey('claude-picture:1')), findsNothing);
      expect(find.byKey(const ValueKey('claude-picture:0')), findsOneWidget);

      for (var i = 0; i < 4; i += 1) {
        await press(tester, find.byKey(const ValueKey('claude-attach')));
      }
      expect(find.byKey(const ValueKey('claude-picture:4')), findsOneWidget);
      expect(picked, 6);
      // A sixth is not asked for: the button says why.
      await press(tester, find.byKey(const ValueKey('claude-attach')));
      expect(picked, 6);
      expect(find.byKey(const ValueKey('claude-picture:5')), findsNothing);
      expect(find.text('Up to $chatImageLimit pictures a message.'), findsOneWidget);
      // Words written, the chips make way.
      await tester.enterText(find.byKey(const ValueKey('claude-ask')), 'What is this?');
      await tester.pump();
      expect(find.byKey(ValueKey('claude-chip:${chatImageChips.first}')), findsNothing);
      debugDisableShadows = true;
    });

    testWidgets('a chip sends the pictures with its words, counted by number and provider only', (tester) async {
      final batches = <Map<String, Object?>>[];
      final metrics = Metrics(
        key: 'phc_test',
        host: 'https://us.i.posthog.com',
        keep: MemoryMetricsKeep(on: true),
        send: (url, body) async {
          batches.add(jsonDecode(utf8.decode(body)) as Map<String, Object?>);
          return true;
        },
        localOnly: () => false,
        context: () => const {'app_version': '2.4.23', 'app_build': '20261105120000', 'platform': 'android', 'form_factor': 'phone', 'simple': false, 'lang': 'en', 'plugins_on': ',', 'plugin_count': 0},
        batchSize: 1000,
        sendEvery: const Duration(hours: 1),
      );
      useMetrics(metrics);
      addTearDown(() => useMetrics(Metrics.off()));
      final (runner, api) = await runnerFor(tester, turns: [_turn(words: 'Made a list.')]);
      final png = (await tester.runAsync(() => _png(16, 16)))!;
      await pumpApp(tester, home: ClaudeChat(runner: runner, onClose: () {}, onOpenNote: (_) {}, onSettings: () {}, pictures: ChatPictureSource(pick: () async => png)));
      await tester.pump();
      await press(tester, find.byKey(const ValueKey('claude-attach')));
      await press(tester, find.byKey(const ValueKey('claude-chip:Make a to-do list')));
      await tester.runAsync(() => _until(runner));
      await tester.pump();
      final content = ((api.asked.single['messages'] as List).single as Map)['content'] as List;
      expect([for (final block in content) (block as Map)['type']], ['image', 'text']);
      expect((content.last as Map)['text'], 'Make a to-do list');
      // Sent: the tray is empty, the message shows its picture.
      expect(find.byKey(const ValueKey('claude-picture:0')), findsNothing);
      expect(find.text('Make a to-do list'), findsOneWidget);
      await tester.runAsync(metrics.flush);
      final sent = [for (final batch in batches) ...(batch['batch'] as List).cast<Map<String, Object?>>()];
      // The last: the runs before this test's were counted too, held until there was somewhere to send them.
      final attached = sent.where((e) => e['event'] == 'ai_image_attached').last['properties'] as Map;
      expect((attached['count'], attached['provider']), ('1', 'claude'));
      // Nothing of the picture: no bytes, no size, no name.
      expect(jsonEncode(attached).contains(base64Encode(png).substring(0, 16)), isFalse);
      expect(attached.keys.where((key) => !key.startsWith(r'$') && !superProps.containsKey(key) && !const {'count', 'provider', 'distinct_id', 'token'}.contains(key)), isEmpty);
      debugDisableShadows = true;
    });

    testWidgets('where the model cannot see pictures, the button is faded and says where to pick one that can', (tester) async {
      final (runner, _) = await runnerFor(tester, model: 'claude-2.1');
      var picked = 0;
      await pumpApp(tester, home: ClaudeChat(runner: runner, onClose: () {}, onOpenNote: (_) {}, onSettings: () {}, pictures: ChatPictureSource(pick: () async => (++picked, Uint8List(0)).$2)));
      await tester.pump();
      final faded = tester.widget<Opacity>(find.ancestor(of: find.byKey(const ValueKey('claude-attach')), matching: find.byType(Opacity)).first);
      expect(faded.opacity, lessThan(1));
      await tester.tap(find.byKey(const ValueKey('claude-attach')));
      await tester.pump();
      expect(picked, 0);
      expect(find.textContaining(chatImageHint), findsOneWidget);
      expect(find.textContaining('can’t see pictures'), findsOneWidget);
      debugDisableShadows = true;
    });

    testWidgets('a Mac’s paste attaches a picture on the clipboard, and puts words in as words', (tester) async {
      final (runner, _) = await runnerFor(tester);
      final png = (await tester.runAsync(() => _png(16, 16)))!;
      ({Uint8List? picture, String? text}) board = (picture: png, text: null);
      await pumpApp(tester, home: ClaudeChat(runner: runner, onClose: () {}, onOpenNote: (_) {}, onSettings: () {}, pictures: ChatPictureSource(pick: () async => null, clipboard: () async => board)));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('claude-ask')));
      await tester.pump();
      Future<void> paste() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump();
      }

      await paste();
      expect(find.byKey(const ValueKey('claude-picture:0')), findsOneWidget);
      board = (picture: null, text: 'Dentist at 3');
      await paste();
      expect(find.text('Dentist at 3'), findsOneWidget);
      expect(find.byKey(const ValueKey('claude-picture:1')), findsNothing);
      debugDisableShadows = true;
    });
  });
}

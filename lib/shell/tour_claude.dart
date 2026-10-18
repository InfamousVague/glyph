/// A DEBUG BUILD'S ONLY: the app's Claude for the App Store's pictures, shot in the iPhone's simulator over the
/// invented library (lib/shell/phone_tour.dart, its `claude` step; tauri/docs/store/apple/listing.md). No key, no
/// network: a run is handed this in place of Anthropic's API ([debugClaudeApi]), and it streams a conversation
/// written here, event by event and paced as a real one arrives, so the chat's thinking and Claude's typing into a
/// note can be photographed as they happen. The tools it calls are the app's own and run for real, over the
/// invented notes (`portugal`, `lisbon` and `coast`, lib/core/sample_library.dart), so what the chat says each did
/// is what the app did.
///
/// In a release none of this is reached: [debugClaudeApi] and [ClaudeSettings.debugStandIn] are read only where
/// `kDebugMode`, and the tour that sets them returns at once.
library;

import 'dart:async';
import 'dart:convert';

import '../claude/messages_api.dart';
import '../core/note.dart' show Note;
import '../claude/sse.dart';

/// What the person asks in the pictures' chat.
const String tourClaudeAsk = 'Plan my Lisbon days from the Portugal notes, with to-dos';

const String _firstThought = 'They want a plan for the Portugal trip. Their notebook links Packing, Lisbon, the first three '
    'days and The coast. I should read those before writing anything, so the plan uses their own days and not '
    'mine.';

const String _secondThought = 'Lisbon is three days: the castle and the long way down, the tram to Belém, and a day '
    'with nothing planned. The tip says the 28 tram is full by nine, so the castle day starts early. The coast is '
    'the train to Cascais and the bikes to Guincho if the wind allows, and the bikes are booked the night before. '
    'I will add the plan to the Lisbon note, a heading for each day and to-dos for what has to be booked or done early.';

const String _plan = '## The plan, a day at a time\n'
    '\n'
    '### Day 1, the castle\n'
    '\n'
    '- [ ] Walk up before nine, the 28 is full by then\n'
    '- [ ] The long way down through Alfama\n'
    '\n'
    '### Day 2, Belém\n'
    '\n'
    '- [ ] The tram out, then walk back along the river\n'
    '- [ ] Pastries from the bakery under the flat\n'
    '\n'
    '### Day 3, nothing planned\n'
    '\n'
    'Coffee, a bookshop, an early night.\n'
    '\n'
    '### Day 4, the coast\n'
    '\n'
    '- [ ] Book the bikes the night before\n'
    '- [ ] Train to Cascais, bikes to Guincho if the wind lets us\n';

/// The scripted API: each request answered with the next turn of the conversation.
class TourClaudeApi extends ClaudeApi {
  TourClaudeApi() : super(key: 'store-pictures-stand-in');

  int _asked = 0;

  /// Which of the two asks this run answers: the packing question asked first, or the plan.
  bool? _packing;

  @override
  ClaudeCall stream(Map<String, Object?> body) {
    _packing ??= _lastAsk(body).toLowerCase().contains('pack');
    final turn = _asked++;
    final packing = _packing!;
    var stopped = false;
    final controller = StreamController<SseEvent>();
    Future<void> play() async {
      for (final (event, pause) in packing ? _packingTurn(turn) : _turn(turn)) {
        if (stopped || controller.isClosed) return;
        if (pause > 0) await Future<void>.delayed(Duration(milliseconds: pause));
        if (stopped || controller.isClosed) return;
        controller.add(event);
      }
      if (!controller.isClosed) await controller.close();
    }

    controller.onListen = () => unawaited(play());
    return ClaudeCall(controller.stream, () {
      stopped = true;
      if (!controller.isClosed) {
        controller.addError(const ClaudeCancelled());
        controller.close();
      }
    });
  }

  @override
  Future<ClaudeError?> check() async => null;
}

/// The words of the last thing the person asked in [body]'s messages.
String _lastAsk(Map<String, Object?> body) {
  final messages = body['messages'];
  if (messages is! List) return '';
  for (final message in messages.reversed) {
    if (message is! Map || message['role'] != 'user') continue;
    final content = message['content'];
    if (content is! List) continue;
    for (final block in content) {
      if (block is Map && block['type'] == 'text') return block['text'] as String? ?? '';
    }
  }
  return '';
}

/// The question asked before the plan, so the chat's picture has a conversation above it.
const String tourClaudeFirstAsk = 'What is still to pack for Portugal?';

Iterable<(SseEvent, int)> _packingTurn(int turn) sync* {
  yield (_e('message_start', {'message': {'role': 'assistant'}}), 400);
  switch (turn) {
    case 0:
      yield* _thought(0, 'The Packing note is their list for the trip. I will read it and name what is not ticked yet.', pause: 60);
      yield* _tool(1, 'toolu_pack_1', 'read_note', {'id': 'packing'});
      yield* _end('tool_use');
    default:
      yield* _said(0, 'Three things are left in Packing: the adapter, the boots and the small bag for the train. The passport is already ticked.');
      yield* _end('end_turn');
  }
}

SseEvent _e(String name, Map<String, Object?> data) => SseEvent(name, jsonEncode({'type': name, ...data}));

/// [words] cut in pieces of [size], each after [pause] ms.
Iterable<(SseEvent, int)> _pieces(int index, String words, String type, String field, {int size = 10, int pause = 90}) sync* {
  for (var i = 0; i < words.length; i += size) {
    final piece = words.substring(i, i + size > words.length ? words.length : i + size);
    yield (_e('content_block_delta', {'index': index, 'delta': {'type': type, field: piece}}), pause);
  }
}

Iterable<(SseEvent, int)> _thought(int index, String words, {int pause = 90}) sync* {
  yield (_e('content_block_start', {'index': index, 'content_block': {'type': 'thinking', 'thinking': ''}}), 300);
  yield* _pieces(index, words, 'thinking_delta', 'thinking', size: 9, pause: pause);
  yield (_e('content_block_delta', {'index': index, 'delta': {'type': 'signature_delta', 'signature': 'stand-in'}}), 0);
  yield (_e('content_block_stop', {'index': index}), 200);
}

Iterable<(SseEvent, int)> _said(int index, String words) sync* {
  yield (_e('content_block_start', {'index': index, 'content_block': {'type': 'text', 'text': ''}}), 150);
  yield* _pieces(index, words, 'text_delta', 'text', size: 6, pause: 40);
  yield (_e('content_block_stop', {'index': index}), 100);
}

Iterable<(SseEvent, int)> _tool(int index, String id, String name, Map<String, Object?> input, {int size = 400, int pause = 0}) sync* {
  yield (_e('content_block_start', {'index': index, 'content_block': {'type': 'tool_use', 'id': id, 'name': name, 'input': <String, Object?>{}}}), 200);
  final json = jsonEncode(input);
  yield* _pieces(index, json, 'input_json_delta', 'partial_json', size: size, pause: pause);
  yield (_e('content_block_stop', {'index': index}), 150);
}

Iterable<(SseEvent, int)> _end(String stop) sync* {
  yield (_e('message_delta', {'delta': {'stop_reason': stop}}), 50);
  yield (_e('message_stop', {}), 0);
}

Iterable<(SseEvent, int)> _turn(int turn) sync* {
  yield (_e('message_start', {'message': {'role': 'assistant'}}), 500);
  switch (turn) {
    case 0:
      yield* _thought(0, _firstThought, pause: 110);
      yield* _said(1, 'I will read your Portugal notes first.');
      yield* _tool(2, 'toolu_tour_1', 'search_notes', {'query': 'Portugal'});
      yield* _end('tool_use');
    case 1:
      yield* _tool(0, 'toolu_tour_2', 'read_note', {'id': 'lisbon'});
      yield* _tool(1, 'toolu_tour_3', 'read_note', {'id': 'coast'});
      yield* _end('tool_use');
    case 2:
      // Slow enough for the chat's picture to be taken while it is still arriving.
      yield* _thought(0, _secondThought, pause: 260);
      // The plan's words, a few letters at a time, as a real stream cuts them, added to the Lisbon note (an existing
      // note, opened as Claude writes in it).
      yield* _tool(1, 'toolu_tour_4', 'append_to_note', {'id': 'lisbon', 'text': _plan}, size: 5, pause: 120);
      yield* _end('tool_use');
    default:
      yield* _said(0, 'I added The plan, a day at a time to Lisbon, the first three days, with The coast as day four and a to-do to book the bikes the night before.');
      yield* _end('end_turn');
  }
}

String _day(DateTime today, int days) {
  final at = DateTime(today.year, today.month, today.day + days);
  return '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
}

/// The notes the 2.2 pictures add to the invented library (lib/core/sample_library.dart [tourExtraNotes]), dated
/// from [now]: a week whose to-dos are on a calendar beside the calendar's events, and a launch timeline drawn as a
/// gantt, a page of the Product notebook's launch.
List<Note> storePictureNotes(int? now) {
  final moment = now ?? DateTime.now().millisecondsSinceEpoch;
  final today = DateTime.fromMillisecondsSinceEpoch(moment);
  int at(int daysAgo, int hh, int mm) => DateTime(today.year, today.month, today.day - daysAgo, hh, mm).millisecondsSinceEpoch;
  String d(int days) => _day(today, days);
  final week = [
    '# This week',
    '',
    'The to-dos with a day, on the calendar with the meetings.',
    '',
    '```query',
    'from: tasks',
    'show: calendar',
    '```',
    '',
    '- [ ] Pay the cabin deposit 📅 ${d(0)}',
    '- [ ] Send Sam the deck 📅 ${d(1)}',
    '- [ ] Book the venue 📅 ${d(3)}',
    '- [ ] Ask Ali about the form 📅 ${d(2)}',
    '- [ ] Oil change for the car 📅 ${d(5)}',
  ].join('\n');
  final timeline = [
    '# Launch timeline',
    '',
    'From the sign-in fix to the launch, as it stands.',
    '',
    '```mermaid',
    'gantt',
    '  dateFormat YYYY-MM-DD',
    '  axisFormat %b %d',
    '  tickInterval 1week',
    '  section Product',
    '  Sign-in loop fix :done, a1, ${d(-8)}, 5d',
    '  Pricing page copy :active, a2, ${d(-3)}, 6d',
    '  Release notes :a3, ${d(2)}, 4d',
    '  Offline search :a4, ${d(4)}, 9d',
    '  section Launch',
    '  Press list :b1, ${d(1)}, 7d',
    '  Beta closes :milestone, b2, ${d(9)}, 0d',
    '  Launch week :b3, ${d(12)}, 5d',
    '```',
    '',
    '- [[Fix the sign-in loop]]',
    '- [[Pricing page copy]]',
    '- [[Launch week]]',
  ].join('\n');
  return [
    Note(id: 'this-week', body: week, createdAt: at(1, 8, 30), updatedAt: at(0, 8, 0)),
    Note(id: 'launch-timeline', body: timeline, createdAt: at(4, 10, 0), updatedAt: at(0, 9, 30)),
  ];
}

/// The calendar the pictures read, as an iCal file served from the Mac (the pack's tools/serve-ics.mjs writes it):
/// the events are made up, dated from today.
const String storePicturesCalendarName = 'Work';
